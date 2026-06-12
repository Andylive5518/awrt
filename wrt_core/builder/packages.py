"""包管理。

从 build.yaml 配置中读取包列表，执行：
- 从 feeds 中删除不需要的包
- 移除 tweak 包依赖
- 修复 APK 版本号兼容性
- 修复 APK 文件冲突
"""

import os
import re
import shutil
import subprocess
from pathlib import Path

from .config import BuildConfig
from .logger import BuildLogger


class PackageManager:
    """管理包的移除、安装和 APK 兼容性修复。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    def remove_unwanted(self) -> bool:
        """从 feeds 中删除不需要的包。"""
        remove_config = self.config.packages.remove
        if not remove_config:
            self.logger.skip("没有配置要移除的包")
            return True

        total_removed = 0
        removed_names: set[str] = set()

        # 移除 luci_apps
        for pkg in remove_config.get("luci_apps", []):
            paths = [
                self.build_dir / "feeds" / "luci" / "applications" / pkg,
                self.build_dir / "feeds" / "luci" / "themes" / pkg,
                self.build_dir / "feeds" / "luci" / "collections" / pkg,
            ]
            for path in paths:
                if path.exists():
                    shutil.rmtree(path)
                    total_removed += 1
                    removed_names.add(pkg)

        # 移除 net_packages
        for pkg in remove_config.get("net_packages", []):
            path = self.build_dir / "feeds" / "packages" / "net" / pkg
            if path.exists():
                shutil.rmtree(path)
                total_removed += 1
                removed_names.add(pkg)

        # 移除 utils
        for pkg in remove_config.get("utils", []):
            path = self.build_dir / "feeds" / "packages" / "utils" / pkg
            if path.exists():
                shutil.rmtree(path)
                total_removed += 1
                removed_names.add(pkg)

        self.logger.ok(f"已移除 {total_removed} 个不需要的包目录")

        # 自动清理依赖已删除包的包
        orphaned = self._remove_orphaned_dependents(removed_names)
        if orphaned:
            self.logger.ok(f"自动清理了 {len(orphaned)} 个因依赖缺失的孤儿包: {', '.join(orphaned)}")

        return True

    def _remove_orphaned_dependents(self, removed_names: set[str]) -> list[str]:
        """扫描所有 feeds 和 package/feeds 中的 Makefile，删除依赖已删除包的包。

        这是避免手动追踪"依赖者的依赖者"的通用方案。
        会将 DEPENDS/BUILD_DEPENDS 行（含多行续行）中的所有包名提取出来，
        与已删除的包名集合做匹配。
        """
        orphaned: list[str] = []

        # 同时扫描 feeds/ 和 package/feeds/
        # feeds/ 是原始 feed 源，package/feeds/ 是 feeds install 后的链接
        scan_dirs = [
            self.build_dir / "feeds",
            self.build_dir / "package" / "feeds",
        ]

        for feeds_base in scan_dirs:
            if not feeds_base.exists():
                continue

            for makefile in feeds_base.rglob("Makefile"):
                content = makefile.read_text()

                # 提取 DEPENDS/BUILD_DEPENDS 块：从 "DEPENDS:=" 或 "BUILD_DEPENDS:=" 开始到下一个非续行
                depends_block = ""
                in_depends = False
                for line in content.split("\n"):
                    stripped = line.strip()
                    if stripped.startswith("DEPENDS:=") or stripped.startswith("BUILD_DEPENDS:="):
                        depends_block = stripped
                        in_depends = True
                    elif in_depends and stripped.endswith("\\"):
                        depends_block += " " + stripped.rstrip("\\").strip()
                    elif in_depends:
                        depends_block += " " + stripped
                        in_depends = False

                if not depends_block:
                    continue

                # 提取所有 +xxx 包名
                dep_names = set(re.findall(r'\+([a-zA-Z0-9_-]+)', depends_block))

                # 检查是否有任何依赖指向已删除的包
                matched = dep_names & removed_names
                if not matched:
                    continue

                pkg_dir = makefile.parent
                if not pkg_dir.exists() or pkg_dir == feeds_base:
                    continue

                rel = pkg_dir.relative_to(feeds_base)
                if str(rel).count("/") < 1:
                    continue

                shutil.rmtree(pkg_dir)
                orphaned.append(pkg_dir.name)
                self.logger.debug(
                    f"自动清理孤儿包: {pkg_dir.name} "
                    f"(依赖 {', '.join(sorted(matched))})"
                )

        return orphaned

    def remove_tweaked(self) -> bool:
        """注释掉 target.mk 中的 tweak 包。"""
        target_mk = self.build_dir / "include" / "target.mk"
        if not target_mk.exists():
            self.logger.skip("target.mk 不存在，跳过")
            return True

        with open(target_mk, "r") as f:
            content = f.read()

        if "DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)" in content:
            content = content.replace(
                "DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)",
                "# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)",
            )
            with open(target_mk, "w") as f:
                f.write(content)
            self.logger.ok("已注释 target.mk 中的 tweak 包")
        else:
            self.logger.skip("target.mk 中未找到 tweak 包配置")

        return True

    def remove_attendedsysupgrade(self) -> bool:
        """从 luci collections 中移除 attendedsysupgrade。"""
        collections_dir = self.build_dir / "feeds" / "luci" / "collections"
        if not collections_dir.exists():
            self.logger.skip("luci collections 目录不存在")
            return True

        found = False
        for makefile in collections_dir.rglob("Makefile"):
            content = makefile.read_text()
            if "luci-app-attendedsysupgrade" in content:
                content = content.replace("luci-app-attendedsysupgrade", "")
                # 清理空行
                lines = [l for l in content.split("\n") if l.strip()]
                makefile.write_text("\n".join(lines) + "\n")
                found = True
                self.logger.ok(f"已从 {makefile.relative_to(self.build_dir)} 移除 attendedsysupgrade")

        if not found:
            self.logger.skip("未找到 attendedsysupgrade 引用")
        return True

    def fix_apk_versions(self) -> bool:
        """修复 APK 版本号格式兼容性。

        对配置中 apk_fixes 指定的包，应用对应的 version patch 文件。
        """
        apk_fixes = self.config.packages.apk_fixes
        if not apk_fixes:
            self.logger.skip("没有配置 APK 版本修复")
            return True

        patch_dir = self.base_path / "patches"
        custom_feed_dir = self.build_dir / "package" / "feeds" / "custom_feed"

        for pkg_name, patch_name in apk_fixes.items():
            patch_file = patch_dir / patch_name
            if not patch_file.exists():
                self.logger.warn(f"APK 修复 patch 不存在: {patch_file}")
                continue

            # 查找包目录
            pkg_dirs = [
                custom_feed_dir / pkg_name,
                self.build_dir / "feeds" / "luci" / "applications" / pkg_name,
                self.build_dir / "package" / "feeds" / "luci" / pkg_name,
            ]
            target_dir = None
            for d in pkg_dirs:
                if d.exists():
                    target_dir = d
                    break

            if not target_dir:
                self.logger.skip(f"包目录不存在: {pkg_name}，跳过 APK 版本修复")
                continue

            # dry-run 检测
            result = subprocess.run(
                ["patch", "--dry-run", "-p1", "-d", str(target_dir), "-i", str(patch_file)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0:
                self.logger.skip(f"{pkg_name}: APK 版本 patch 已存在或无法应用")
                continue

            # 应用 patch
            result = subprocess.run(
                ["patch", "-p1", "-d", str(target_dir), "-i", str(patch_file)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode == 0:
                self.logger.ok(f"{pkg_name}: APK 版本已修复")
            else:
                self.logger.fail(f"{pkg_name}: APK 版本修复失败: {result.stderr[:200]}")

        return True

    def fix_apk_conflicts(self) -> bool:
        """修复 APK 文件冲突（删除重复的 init 脚本等）。"""
        conflicts = self.config.packages.apk_file_conflicts
        if not conflicts:
            self.logger.skip("没有配置 APK 文件冲突修复")
            return True

        custom_feed_dir = self.build_dir / "package" / "feeds" / "custom_feed"

        for entry in conflicts:
            pkg_name = entry.get("package", "")
            remove_files = entry.get("remove_files", [])

            pkg_dir = custom_feed_dir / pkg_name
            if not pkg_dir.exists():
                self.logger.skip(f"包目录不存在: {pkg_name}")
                continue

            for rel_path in remove_files:
                target = pkg_dir / rel_path
                if target.exists():
                    target.unlink()
                    self.logger.ok(f"{pkg_name}: 已删除冲突文件 {rel_path}")
                else:
                    self.logger.skip(f"{pkg_name}: 冲突文件不存在 {rel_path}")

        return True
