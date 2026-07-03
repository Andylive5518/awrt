"""系统配置。

UCI defaults、LAN 地址、ttyd、PBR ISP 路由、构建签名、菜单位置等。
"""

import shutil
from pathlib import Path

from .config import BuildConfig
from .logger import BuildLogger


class SystemConfigurator:
    """系统配置：UCI defaults、LAN 地址、ttyd、PBR 等。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    # ---- UCI Defaults ----

    def _install_uci_defaults(self) -> bool:
        """安装 UCI defaults 文件到 base-files。"""
        uci_cfg = self.config.uci_defaults
        if not uci_cfg.files:
            self.logger.skip("没有配置 UCI defaults 文件")
            return True

        target_dir = self.build_dir / "package" / "base-files" / "files" / "etc" / "uci-defaults"
        target_dir.mkdir(parents=True, exist_ok=True)

        for entry in uci_cfg.files:
            source = entry.get("source", "")
            target_name = entry.get("target", "")

            source_path = self.base_path / source
            if not source_path.exists():
                self.logger.warn(f"UCI defaults 源文件不存在: {source_path}")
                continue

            target_path = target_dir / target_name
            if target_path.exists():
                target_path.chmod(0o644)
            shutil.copy2(source_path, target_path)
            target_path.chmod(0o544)
            self.logger.ok(f"UCI defaults 已安装: {target_name}")

        return True

    def _fix_default_theme(self) -> bool:
        """替换默认主题为 argon。"""
        theme = self.config.uci_defaults.theme
        collections_dir = self.build_dir / "feeds" / "luci" / "collections"
        if not collections_dir.exists():
            self.logger.skip("luci collections 目录不存在")
            return True

        for makefile in collections_dir.rglob("Makefile"):
            content = makefile.read_text()
            if "luci-theme-bootstrap" in content:
                content = content.replace("luci-theme-bootstrap", f"luci-theme-{theme}")
                makefile.write_text(content)
                self.logger.ok(f"默认主题已替换为 {theme}")

        return True

    def _update_lan_addr(self) -> bool:
        """修改默认 LAN IP 地址。"""
        lan_addr = self.config.uci_defaults.lan_addr
        config_generate = self.build_dir / "package" / "base-files" / "files" / "bin" / "config_generate"
        if not config_generate.exists():
            self.logger.skip("config_generate 不存在")
            return True

        content = config_generate.read_text()
        # 替换所有 192.168.x.x 为配置的地址
        import re
        content = re.sub(r'192\.168\.[0-9]+\.[0-9]+', lan_addr, content)
        config_generate.write_text(content)
        self.logger.ok(f"默认 LAN 地址已更新为 {lan_addr}")
        return True

    # ---- PBR ISP 路由 ----

    def _install_pbr_isp(self, isp_lower: str, isp_upper: str) -> bool:
        """Install PBR ISP user-include config files and register them.

        The pbr package only ships a fixed set of pbr.user.* files.  We copy
        the per-ISP variants into the package files tree and extend the
        ``Package/pbr/install`` stanza so they land in the image.

        The install rules MUST be inserted on their own lines and AFTER the
        ``$(INSTALL_DIR) $(1)/usr/share/pbr`` line.  Earlier code appended the
        rules to the ``define Package/pbr/install`` line itself (no newline),
        which corrupted the Makefile and made OpenWrt report "package has no
        install section", skipping pbr entirely.
        """
        pbr_pkg_dir = self.build_dir / "package" / "feeds" / "packages" / "pbr"
        if not pbr_pkg_dir.exists():
            pbr_pkg_dir = self.build_dir / "feeds" / "packages" / "net" / "pbr"
        if not pbr_pkg_dir.exists():
            self.logger.warn("PBR package directory not found")
            return False

        pbr_dir = pbr_pkg_dir / "files" / "usr" / "share" / "pbr"
        pbr_dir.mkdir(parents=True, exist_ok=True)

        config_dir = self.base_path / self.config.pbr.config_dir

        # Copy IPv4 and IPv6 ISP configs into the package files tree.
        for suffix in ("", "6"):
            src = config_dir / f"pbr.user.{isp_lower}{suffix}"
            dst = pbr_dir / f"pbr.user.{isp_lower}{suffix}"
            if src.exists():
                if dst.exists():
                    dst.chmod(0o644)
                shutil.copy2(src, dst)
                self.logger.ok(f"PBR {isp_upper}{' IPv6' if suffix else ''} config installed")

        # Register the new files in Package/pbr/install.
        makefile = pbr_pkg_dir / "Makefile"
        if not makefile.exists():
            return True
        content = makefile.read_text()
        if f"pbr.user.{isp_lower}" in content:
            return True  # already registered

        new_rules = (
            f"\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.{isp_lower}"
            f" $(1)/usr/share/pbr/pbr.user.{isp_lower}\n"
            f"\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.{isp_lower}6"
            f" $(1)/usr/share/pbr/pbr.user.{isp_lower}6\n"
        )

        # Preferred anchor: the line that creates /usr/share/pbr, so the
        # directory always exists before INSTALL_DATA runs.
        marker = "\t$(INSTALL_DIR) $(1)/usr/share/pbr\n"
        if marker in content:
            content = content.replace(marker, marker + new_rules, 1)
        elif "define Package/pbr/install\n" in content:
            content = content.replace(
                "define Package/pbr/install\n",
                "define Package/pbr/install\n" + new_rules,
                1,
            )
        else:
            self.logger.warn("PBR Makefile install stanza not found; skipping rule injection")
            return True

        makefile.write_text(content)
        self.logger.ok(f"PBR Makefile {isp_upper} install rule added")
        return True

    # ---- 其他系统配置 ----

    def _change_dnsmasq2full(self) -> bool:
        """替换 dnsmasq 为 dnsmasq-full。"""
        target_mk = self.build_dir / "include" / "target.mk"
        if not target_mk.exists():
            return True

        content = target_mk.read_text()
        if "dnsmasq-full" not in content:
            content = content.replace("dnsmasq", "dnsmasq-full")
            target_mk.write_text(content)
            self.logger.ok("dnsmasq 已替换为 dnsmasq-full")
        return True

    def _fix_kconfig_recursive(self) -> bool:
        """修复 Kconfig 递归依赖生成逻辑。"""
        filepath = self.build_dir / "scripts" / "package-metadata.pl"
        if not filepath.exists():
            return True

        content = filepath.read_text()
        if "!=y" not in content:
            content = content.replace(
                "<PACKAGE_$pkgname",
                "!=y",
            )
            filepath.write_text(content)
            self.logger.ok("Kconfig 递归依赖已修复")
        return True

    def _install_monitoring_scripts(self) -> bool:
        """安装系统监控脚本。"""
        scripts = self.config.system.monitoring_scripts
        if not scripts:
            return True

        # cpuusage, tempinfo 等复制到 autocore
        autocore_dir = self.build_dir / "package" / "emortal" / "autocore" / "files"
        if autocore_dir.exists():
            for name, rel_path in scripts.items():
                src = self.base_path / rel_path
                if src.exists():
                    dst = autocore_dir / name
                    if dst.exists():
                        dst.chmod(0o644)
                    shutil.copy2(src, dst)
                    self.logger.ok(f"监控脚本已安装: {name}")

        return True

    def _install_smp_affinity(self) -> bool:
        """安装 SMP affinity 配置。"""
        smp_path = self.config.system.smp_affinity
        if not smp_path:
            return True

        src = self.base_path / smp_path
        if not src.exists():
            return True

        target_dir = self.build_dir / "package" / "base-files" / "files" / "etc" / "init.d"
        target_dir.mkdir(parents=True, exist_ok=True)
        dst = target_dir / "smp_affinity"
        if dst.exists():
            dst.chmod(0o644)
        shutil.copy2(src, dst)
        dst.chmod(0o755)
        self.logger.ok("SMP affinity 配置已安装")
        return True

    def _set_custom_cron(self) -> bool:
        """安装自定义 cron 任务 init 脚本。"""
        cron_tasks = self.config.system.cron_tasks
        if not cron_tasks:
            return True

        sh_dir = self.build_dir / "package" / "base-files" / "files" / "etc" / "init.d"
        sh_dir.mkdir(parents=True, exist_ok=True)

        script_content = """#!/bin/sh /etc/rc.common
START=99

boot() {
    sed -i '/drop_caches/d' /etc/crontabs/root
"""
        for task in cron_tasks:
            script_content += f'    echo "{task.get("schedule", "")} {task.get("command", "")}" >>/etc/crontabs/root\n'

        script_content += """    crontab /etc/crontabs/root
}
"""
        script_path = sh_dir / "custom_task"
        script_path.write_text(script_content)
        script_path.chmod(0o755)
        self.logger.ok("自定义 cron 任务已安装")
        return True

    def _remove_attendedsysupgrade(self) -> bool:
        """从 luci collections 中移除 attendedsysupgrade。"""
        collections_dir = self.build_dir / "feeds" / "luci" / "collections"
        if not collections_dir.exists():
            return True

        for makefile in collections_dir.rglob("Makefile"):
            content = makefile.read_text()
            if "luci-app-attendedsysupgrade" in content:
                content = content.replace("luci-app-attendedsysupgrade", "")
                lines = [l for l in content.split("\n") if l.strip()]
                makefile.write_text("\n".join(lines) + "\n")
                self.logger.ok(f"已从 {makefile.name} 移除 attendedsysupgrade")

        return True

    # ---- 主入口 ----

    def configure(self) -> bool:
        """执行所有系统配置。"""
        self.logger.info("开始系统配置...")

        self._install_uci_defaults()
        self._fix_default_theme()
        self._update_lan_addr()
        self._change_dnsmasq2full()
        self._fix_kconfig_recursive()
        self._install_monitoring_scripts()
        self._install_smp_affinity()
        self._set_custom_cron()
        self._remove_attendedsysupgrade()

        # PBR ISP 配置
        for isp in self.config.pbr.isps:
            isp_upper = isp.upper()
            self._install_pbr_isp(isp, isp_upper)

        self.logger.done("系统配置完成")
        return True
