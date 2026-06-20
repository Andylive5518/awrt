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
        """从 feeds 和 package/feeds 中删除不需要的包。"""
        return self._remove_configured()

    def remove_package_links(self) -> bool:
        """从 package/feeds 中删除不需要的包（feeds install 后执行）。

        feeds install 根据索引重新创建了 package/feeds/ 下的包，
        需要再次清理。
        """
        return self._remove_configured(only_package_feeds=True)

    def _remove_configured(self, only_package_feeds: bool = False) -> bool:
        """根据 build.yaml 配置删除不需要的包。"""
        remove_config = self.config.packages.remove
        if not remove_config:
            self.logger.skip("没有配置要移除的包")
            return True

        total_removed = 0
        removed_names: set[str] = set()

        base_feeds = self.build_dir / "feeds"
        base_pkg_feeds = self.build_dir / "package" / "feeds"

        # 构建搜索路径列表
        def search_paths(category: str, pkg: str) -> list[Path]:
            paths = []
            if category == "luci_apps":
                if not only_package_feeds:
                    paths.extend([
                        base_feeds / "luci" / "applications" / pkg,
                        base_feeds / "luci" / "themes" / pkg,
                        base_feeds / "luci" / "collections" / pkg,
                    ])
                paths.append(base_pkg_feeds / "luci" / pkg)
            elif category == "net_packages":
                if not only_package_feeds:
                    paths.append(base_feeds / "packages" / "net" / pkg)
                paths.append(base_pkg_feeds / "packages" / pkg)
            elif category == "utils":
                if not only_package_feeds:
                    paths.append(base_feeds / "packages" / "utils" / pkg)
                paths.append(base_pkg_feeds / "packages" / pkg)
            # 回退：某些包直接位于 feeds/packages/<pkg>（不在子分类目录下）
            if not only_package_feeds:
                paths.append(base_feeds / "packages" / pkg)
            paths.append(base_pkg_feeds / "packages" / pkg)
            # custom_feed 路径（kiddin9/kenzok8 等自定义 feed 源）
            if not only_package_feeds:
                paths.append(self.build_dir / "custom_feed" / pkg)
            paths.append(base_pkg_feeds / "custom_feed" / pkg)
            return paths

        for category in ("luci_apps", "net_packages", "utils"):
            for pkg in remove_config.get(category, []):
                for path in search_paths(category, pkg):
                    if path.is_symlink() or path.exists():
                        # 读取 PKG_NAME 并加入 removed_names，处理目录名与包名不一致的情况
                        # 例如 open-app-filter 目录 → PKG_NAME=appfilter
                        makefile = path / "Makefile"
                        if makefile.exists():
                            content = makefile.read_text()
                            m = re.search(r'^PKG_NAME\s*:=\s*(\S+)', content, re.MULTILINE)
                            if m and m.group(1) != pkg:
                                removed_names.add(m.group(1))

                        if path.is_symlink():
                            path.unlink()
                        else:
                            shutil.rmtree(path)
                        total_removed += 1
                        removed_names.add(pkg)

        self.logger.ok(f"已移除 {total_removed} 个不需要的包目录")

        # 自动清理依赖已删除包的包
        orphaned = self._remove_orphaned_dependents(removed_names, only_package_feeds)
        if orphaned:
            self.logger.ok(f"自动清理了 {len(orphaned)} 个因依赖缺失的孤儿包: {', '.join(orphaned)}")

        return True

    def _remove_orphaned_dependents(self, removed_names: set[str],
                                    only_package_feeds: bool = False) -> list[str]:
        """扫描所有 feeds/package/feeds 中的 Makefile，递归删除依赖已删除包的包。

        提取所有 DEPENDS/BUILD_DEPENDS/PKG_BUILD_DEPENDS/LUCI_DEPENDS 行
        （含多行续行）中的包名，与已删除的包名集合做匹配。
        同时提取 PKG_NAME 以处理目录名与包名不一致的情况（如 open-app-filter
        目录的 PKG_NAME=appfilter）。
        递归执行直到没有新的孤儿包被发现。
        """
        orphaned: list[str] = []

        scan_dirs = []
        if not only_package_feeds:
            scan_dirs.append(self.build_dir / "feeds")
        scan_dirs.append(self.build_dir / "package" / "feeds")

        # 所有需要扫描的依赖声明前缀
        depends_prefixes = (
            "DEPENDS:=", "DEPENDS+=",
            "BUILD_DEPENDS:=", "BUILD_DEPENDS+=",
            "PKG_BUILD_DEPENDS:=", "PKG_BUILD_DEPENDS+=",
            "LUCI_DEPENDS:=", "LUCI_DEPENDS+=",
        )

        # 将 removed_names 扩展为包含 PKG_NAME 的集合
        # 例如 open-app-filter 目录 → PKG_NAME=appfilter
        all_removed = set(removed_names)

        def _collect_makefiles(feeds_base: Path) -> list[tuple[str, Path]]:
            """收集所有 Makefile 路径，返回 (目录名, Makefile路径) 列表。"""
            result: list[tuple[str, Path]] = []
            for dirpath, _dirnames, filenames in os.walk(
                str(feeds_base), followlinks=True,
            ):
                if "Makefile" not in filenames:
                    continue
                makefile = Path(dirpath) / "Makefile"
                result.append((makefile.parent.name, makefile))
            return result

        def _extract_dep_names(content: str) -> set[str]:
            """从 Makefile 内容中提取所有依赖包名。"""
            lines = content.split("\n")
            depends_blocks: list[str] = []
            current_block = ""
            in_depends = False
            for line in lines:
                stripped = line.strip()
                if stripped.startswith(depends_prefixes):
                    if current_block:
                        depends_blocks.append(current_block)
                    current_block = stripped
                    in_depends = True
                elif in_depends and stripped.endswith("\\"):
                    current_block += " " + stripped.rstrip("\\").strip()
                elif in_depends:
                    current_block += " " + stripped
                    depends_blocks.append(current_block)
                    current_block = ""
                    in_depends = False
            if current_block:
                depends_blocks.append(current_block)

            dep_names: set[str] = set()
            for block in depends_blocks:
                raw_deps = re.findall(r'\+([a-zA-Z0-9_./+-]+)', block)
                for dep in raw_deps:
                    if ":" in dep:
                        dep_names.add(dep.split(":", 1)[1])
                    else:
                        dep_names.add(dep)
                no_prefix_deps = re.findall(
                    r'(?:^|\s)([a-zA-Z][a-zA-Z0-9_-]*(?:\.[a-zA-Z0-9_-]+)*)(?=\s|$)',
                    block.split(":=", 1)[-1].split("+=", 1)[-1],
                )
                for dep in no_prefix_deps:
                    if dep and not dep.startswith("+"):
                        dep_names.add(dep)
            return dep_names

        def _extract_pkg_name(content: str) -> str | None:
            """从 Makefile 内容中提取 PKG_NAME。"""
            m = re.search(r'^PKG_NAME\s*:=\s*(\S+)', content, re.MULTILINE)
            return m.group(1) if m else None

        # 递归检测，直到没有新的孤儿包
        while True:
            new_orphans = 0
            for feeds_base in scan_dirs:
                if not feeds_base.exists():
                    continue

                makefiles = _collect_makefiles(feeds_base)
                for dir_name, makefile in makefiles:
                    if dir_name in all_removed:
                        continue  # 已删除
                    if not (makefile.parent.is_symlink() or makefile.parent.exists()):
                        continue
                    rel = makefile.parent.relative_to(feeds_base)
                    if str(rel).count("/") < 1:
                        continue

                    content = makefile.read_text()
                    dep_names = _extract_dep_names(content)

                    # 检查依赖是否缺失：目录名或 PKG_NAME 在 all_removed 中
                    matched = dep_names & all_removed
                    if not matched:
                        continue

                    pkg_dir = makefile.parent
                    if pkg_dir.is_symlink():
                        pkg_dir.unlink()
                    else:
                        shutil.rmtree(pkg_dir)
                    orphaned.append(dir_name)
                    all_removed.add(dir_name)

                    # 也加入 PKG_NAME 到 all_removed，让依赖此包的其他包能被检测到
                    pkg_name = _extract_pkg_name(content)
                    if pkg_name and pkg_name != dir_name:
                        all_removed.add(pkg_name)

                    new_orphans += 1
                    self.logger.debug(
                        f"自动清理孤儿包: {dir_name} "
                        f"(依赖 {', '.join(sorted(matched))})"
                    )

            if new_orphans == 0:
                break

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
                lines = [l for l in content.split("\n") if l.strip()]
                makefile.write_text("\n".join(lines) + "\n")
                found = True
                self.logger.ok(f"已从 {makefile.relative_to(self.build_dir)} 移除 attendedsysupgrade")

        if not found:
            self.logger.skip("未找到 attendedsysupgrade 引用")
        return True

    def fix_apk_versions(self) -> bool:
        """修复 APK 版本号格式兼容性。"""
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

            result = subprocess.run(
                ["patch", "--dry-run", "-p1", "-d", str(target_dir), "-i", str(patch_file)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0:
                self.logger.skip(f"{pkg_name}: APK 版本 patch 已存在或无法应用")
                continue

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
