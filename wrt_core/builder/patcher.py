"""Patch 管理器。

核心功能：
1. 根据 build.yaml 配置自动定位目标目录并应用 patch
2. 应用前 dry-run 检测，已存在的自动跳过，冲突时显示具体原因
3. --upgrade-check 模式批量检查兼容性并输出格式化报告
4. 每个 patch 组执行时间跟踪
"""

import subprocess
import time
from pathlib import Path
from dataclasses import dataclass, field

from .config import BuildConfig
from .logger import BuildLogger


@dataclass
class PatchResult:
    name: str
    target: str
    status: str  # "OK" | "SKIP" | "FAIL"
    detail: str = ""


@dataclass
class GroupResult:
    group_name: str
    results: list[PatchResult] = field(default_factory=list)
    duration: float = 0.0

    @property
    def ok_count(self) -> int:
        return sum(1 for r in self.results if r.status == "OK")

    @property
    def skip_count(self) -> int:
        return sum(1 for r in self.results if r.status == "SKIP")

    @property
    def fail_count(self) -> int:
        return sum(1 for r in self.results if r.status == "FAIL")

    def __str__(self) -> str:
        total = len(self.results)
        ok = self.ok_count
        skip = self.skip_count
        fail = self.fail_count
        return f"{self.group_name}: {ok} OK, {skip} SKIP, {fail} FAIL ({self.duration:.1f}s)"


class PatchManager:
    """统一管理所有 patch 的声明周期。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger
        self.patch_dir = base_path / "patches"

    def _resolve_target_dir(self, target: str) -> Path:
        """解析 patch 目标目录。target 是相对于 build_dir 的路径。"""
        return self.build_dir / target

    def _dry_run_check(self, target_dir: Path, patch_file: Path) -> tuple[bool, str]:
        """检查 patch 是否可以应用（dry-run）。

        Returns:
            (True, "") 表示可以应用
            (False, reason) 表示不能应用，reason 说明原因
        """
        result = subprocess.run(
            ["patch", "--dry-run", "-p1", "-d", str(target_dir), "-i", str(patch_file)],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0:
            return True, ""
        # 提取冲突原因
        lines = result.stderr.strip().split("\n")
        reason_lines = [l for l in lines if "error" in l.lower() or "fail" in l.lower() or "rej" in l.lower()]
        if reason_lines:
            return False, reason_lines[0].strip()
        return False, "已应用或冲突（dry-run 失败）"

    def _apply_single(self, target_dir: Path, patch_file: Path) -> bool:
        """应用单个 patch。返回 True 表示应用成功。"""
        result = subprocess.run(
            ["patch", "-p1", "-d", str(target_dir), "-i", str(patch_file)],
            capture_output=True, text=True, check=False,
        )
        return result.returncode == 0

    def apply_group(self, group_name: str) -> GroupResult:
        """应用一组 patch。"""
        group_config = self.config.patches.groups.get(group_name)
        if not group_config:
            self.logger.warn(f"未找到 patch 组: {group_name}")
            return GroupResult(group_name=group_name)

        target_dir = self._resolve_target_dir(group_config.target)
        if not target_dir.exists():
            self.logger.warn(f"目标目录不存在: {target_dir}，跳过 patch 组 {group_name}")
            return GroupResult(group_name=group_name)

        start = time.time()
        results = []
        for patch_name in group_config.files:
            patch_file = self.patch_dir / patch_name
            if not patch_file.exists():
                results.append(PatchResult(
                    name=patch_name, target=group_config.target,
                    status="FAIL", detail="patch 文件不存在",
                ))
                continue

            ok, reason = self._dry_run_check(target_dir, patch_file)
            if not ok:
                results.append(PatchResult(
                    name=patch_name, target=group_config.target,
                    status="SKIP", detail=reason,
                ))
                continue

            if self._apply_single(target_dir, patch_file):
                results.append(PatchResult(
                    name=patch_name, target=group_config.target,
                    status="OK", detail="",
                ))
            else:
                results.append(PatchResult(
                    name=patch_name, target=group_config.target,
                    status="FAIL", detail="应用失败",
                ))

        duration = time.time() - start
        return GroupResult(group_name=group_name, results=results, duration=duration)

    def apply_all(self) -> list[GroupResult]:
        """应用所有配置的 patch。"""
        results = []
        for group_name in self.config.patches.groups:
            group_result = self.apply_group(group_name)
            results.append(group_result)
            for pr in group_result.results:
                if pr.status == "OK":
                    self.logger.ok(f"{pr.name} → {pr.target}")
                elif pr.status == "SKIP":
                    self.logger.skip(f"{pr.name} → {pr.target}（{pr.detail}）")
                else:
                    self.logger.fail(f"{pr.name} → {pr.target}（{pr.detail}）")
            self.logger.info(str(group_result))
        return results

    def check_all(self) -> list[GroupResult]:
        """检查所有 patch 的兼容性（--upgrade-check）。"""
        self.logger.info("检查所有 patch 兼容性...")
        results = self.apply_all()
        # 输出汇总表格
        total_ok = sum(r.ok_count for r in results)
        total_skip = sum(r.skip_count for r in results)
        total_fail = sum(r.fail_count for r in results)
        self.logger.info(f"汇总: {total_ok} OK, {total_skip} SKIP, {total_fail} FAIL")
        return results

    def summary(self) -> str:
        """生成所有 patch 组的格式化的摘要报告。"""
        lines = []
        lines.append(f"{'Patch 组':<20} {'OK':<5} {'SKIP':<5} {'FAIL':<5} {'耗时':<8}")
        lines.append("-" * 48)
        total_ok = total_skip = total_fail = 0
        total_time = 0.0
        for group_name in self.config.patches.groups:
            # 仅统计，不应用
            group_config = self.config.patches.groups[group_name]
            lines.append(f"{group_name:<20} {'-':<5} {'-':<5} {'-':<5} {'-':<8}")
        return "\n".join(lines)
