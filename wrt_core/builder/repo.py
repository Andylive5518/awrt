"""上游仓库管理。"""

import os
import subprocess
from pathlib import Path

from .config import BuildConfig
from .logger import BuildLogger


class RepoManager:
    """管理上游 ImmortalWrt 仓库的 clone、fetch、reset。"""

    def __init__(self, config: BuildConfig, base_path: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.logger = logger
        self.build_dir = base_path.parent / config.source.build_dir

    @property
    def repo_dir(self) -> Path:
        return self.build_dir

    def clone_repo(self) -> bool:
        """克隆上游仓库（不存在时）或更新（已存在时）。"""
        repo_dir = self.repo_dir
        if repo_dir.exists():
            self.logger.skip(f"仓库目录已存在: {repo_dir}")
            return True

        self.logger.info(f"克隆仓库: {self.config.source.repo} ({self.config.source.branch})")
        result = subprocess.run(
            ["git", "clone", "--depth", "1", "-b", self.config.source.branch,
             self.config.source.repo, str(repo_dir)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"克隆失败: {result.stderr}")
            return False
        self.logger.ok(f"仓库克隆完成: {repo_dir}")
        return True

    def clean_up(self) -> bool:
        """清理构建目录。"""
        repo_dir = self.repo_dir
        if not repo_dir.exists():
            self.logger.skip("构建目录不存在，跳过清理")
            return True

        # 删除 .config
        config_file = repo_dir / ".config"
        if config_file.exists():
            config_file.unlink()

        # 删除 tmp
        tmp_dir = repo_dir / "tmp"
        if tmp_dir.exists():
            subprocess.run(["rm", "-rf", str(tmp_dir)], check=False)

        # 删除 logs
        logs_dir = repo_dir / "logs"
        if logs_dir.exists():
            subprocess.run(["rm", "-rf", str(logs_dir / "*")], check=False)

        # 清理 feeds
        feeds_dir = repo_dir / "feeds"
        if feeds_dir.exists():
            subprocess.run(
                ["./scripts/feeds", "clean"],
                cwd=str(repo_dir), capture_output=True, check=False,
            )

        # 创建 tmp/.build
        tmp_dir.mkdir(parents=True, exist_ok=True)
        (tmp_dir / ".build").write_text("1")

        self.logger.ok("构建目录已清理")
        return True

    def reset_feeds_conf(self) -> bool:
        """重置 feeds.conf.default 到上游状态。"""
        repo_dir = self.repo_dir
        if not repo_dir.exists():
            self.logger.skip("仓库不存在，跳过 feeds.conf 重置")
            return True

        result = subprocess.run(
            ["git", "checkout", f"origin/{self.config.source.branch}", "--", "feeds.conf.default"],
            cwd=str(repo_dir), capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            # 尝试本地分支
            result = subprocess.run(
                ["git", "checkout", self.config.source.branch, "--", "feeds.conf.default"],
                cwd=str(repo_dir), capture_output=True, text=True, check=False,
            )
        if result.returncode == 0:
            self.logger.ok("feeds.conf.default 已重置到上游状态")
            return True
        self.logger.warn(f"feeds.conf.default 重置可能未完全成功: {result.stderr}")
        return True
