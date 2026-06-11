"""Docker nftables 兼容性配置。

在 OpenWrt 构建树中配置 Docker 使用 nftables 后端而非 iptables-legacy。
主要操作：
1. 修改 dockerd Makefile 的 DEPENDS 块
2. 注入 nftables 前置校验函数到 dockerd init 脚本
3. 修改 process_config 处理 firewall_backend
4. 配置 UCI 默认值（registry_mirrors, firewall_backend, storage_driver）
5. 配置 sysctl（ip_forward）
6. 修补 dockerman init 脚本的 nftables 后端检测
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from .config import BuildConfig
from .logger import BuildLogger


class DockerConfigurator:
    """Docker nftables 兼容性配置。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    # ---- 文件定位辅助 ----

    def _resolve_dockerd_makefile(self) -> Path | None:
        """查找 dockerd Makefile。"""
        candidates = [
            self.build_dir / "package" / "feeds" / "packages" / "dockerd" / "Makefile",
            self.build_dir / "feeds" / "packages" / "utils" / "dockerd" / "Makefile",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _resolve_dockerd_init(self) -> Path | None:
        """查找 dockerd init 脚本。"""
        candidates = [
            self.build_dir / "package" / "feeds" / "packages" / "dockerd" / "files" / "dockerd.init",
            self.build_dir / "feeds" / "packages" / "utils" / "dockerd" / "files" / "dockerd.init",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _resolve_dockerd_config(self) -> Path | None:
        """查找 dockerd UCI 配置文件。"""
        candidates = [
            self.build_dir / "package" / "feeds" / "packages" / "dockerd" / "files" / "etc" / "config" / "dockerd",
            self.build_dir / "feeds" / "packages" / "utils" / "dockerd" / "files" / "etc" / "config" / "dockerd",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _resolve_dockerd_sysctl(self) -> Path | None:
        """查找 dockerd sysctl 文件。"""
        candidates = [
            self.build_dir / "package" / "feeds" / "packages" / "dockerd" / "files" / "etc" / "sysctl.d" / "sysctl-br-netfilter-ip.conf",
            self.build_dir / "feeds" / "packages" / "utils" / "dockerd" / "files" / "etc" / "sysctl.d" / "sysctl-br-netfilter-ip.conf",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _resolve_dockerman_init(self) -> Path | None:
        """查找 dockerman init 脚本。"""
        candidates = [
            self.build_dir / "package" / "feeds" / "luci" / "applications" / "luci-app-dockerman" / "root" / "etc" / "init.d" / "dockerman",
            self.build_dir / "feeds" / "luci" / "applications" / "luci-app-dockerman" / "root" / "etc" / "init.d" / "dockerman",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    # ---- Makefile 修补 ----

    def _patch_depends_block(self, makefile: Path) -> bool:
        """替换 dockerd Makefile 的 DEPENDS 块为 nftables 兼容依赖。"""
        content = makefile.read_text()

        # 匹配 DEPENDS 块
        pattern = r'(DEPENDS:=\$\((?:GO_)?ARCH_DEPENDS\) \\\n)(?:.*?\\\n)*.*?(?=\n\S|\Z)'

        new_depends = """  DEPENDS:=$(GO_ARCH_DEPENDS) \\
  +ca-certificates \\
  +containerd \\
  +iptables-nft \\
  +IPV6:ip6tables-nft \\
  +IPV6:kmod-nf-nat6 \\
  +KERNEL_SECCOMP:libseccomp \\
  +kmod-br-netfilter \\
  +kmod-nf-ipvs \\
  +kmod-veth \\
  +nftables \\
  +kmod-nft-nat \\
  +tini \\
  +uci-firewall"""

        # 找到 DEPENDS 行并替换
        lines = content.split("\n")
        new_lines = []
        in_depends = False
        replaced = False

        for line in lines:
            if re.match(r'^\s*DEPENDS:=\$\((GO_)?ARCH_DEPENDS\) \\$', line):
                in_depends = True
                new_lines.append(line)
                continue

            if in_depends:
                if re.match(r'^\s+\+', line) or line.rstrip().endswith('\\'):
                    continue  # 跳过旧依赖
                else:
                    # DEPENDS 块结束，插入新依赖
                    new_lines.append(new_depends)
                    in_depends = False
                    replaced = True
                    new_lines.append(line)
                    continue

            new_lines.append(line)

        if replaced:
            makefile.write_text("\n".join(new_lines))
            self.logger.ok("dockerd Makefile DEPENDS 已替换为 nftables 兼容依赖")
            return True
        else:
            self.logger.skip("dockerd Makefile 未找到 DEPENDS 块")
            return False

    def _fix_vendored_checks(self, makefile: Path) -> bool:
        """修复 vendored 依赖检查，容忍缺失的 installer 文件。"""
        content = makefile.read_text()

        # 1. 移除 containerd.installer 的存在性检查
        content = re.sub(
            r'^\s*\[ ! -f "\$\(PKG_BUILD_DIR\)/hack/dockerfile/install/containerd\.installer" \] \|\| \\\n',
            '',
            content,
        )
        # 2. 移除 runc.installer 的存在性检查
        content = re.sub(
            r'^\s*\[ ! -f "\$\(PKG_BUILD_DIR\)/hack/dockerfile/install/runc\.installer" \] \|\| \\\n',
            '',
            content,
        )
        # 3. 确保 vendored 调用前有存在性检查
        content = content.replace(
            "$(call EnsureVendoredVersion,../containerd/Makefile,containerd.installer)",
            "[ ! -f \"$(PKG_BUILD_DIR)/hack/dockerfile/install/containerd.installer\" ] || \\\n\t\t$(call EnsureVendoredVersion,../containerd/Makefile,containerd.installer)",
        )
        content = content.replace(
            "$(call EnsureVendoredVersion,../runc/Makefile,runc.installer)",
            "[ ! -f \"$(PKG_BUILD_DIR)/hack/dockerfile/install/runc.installer\" ] || \\\n\t\t$(call EnsureVendoredVersion,../runc/Makefile,runc.installer)",
        )

        makefile.write_text(content)
        self.logger.ok("dockerd Makefile vendored 检查已修复")
        return True

    # ---- Init 脚本修补 ----

    def _inject_nft_prereq_block(self, init_path: Path) -> bool:
        """在 dockerd init 脚本中注入 nftables 前置校验函数。"""
        content = init_path.read_text()

        # 如果已经注入，跳过
        if "DOCKER_STACK_NFT_PREREQ_START" in content:
            self.logger.skip("dockerd init 已包含 nftables 前置校验")
            return True

        # 查找插入点：DOCKERD_CONF 行之后
        insert_marker = 'DOCKERD_CONF="${DOCKER_CONF_DIR}/daemon.json"'
        if insert_marker not in content:
            self.logger.warn("dockerd init 未找到 DOCKERD_CONF 行，跳过 nftables 注入")
            return False

        nft_block = '''
# === DOCKER_STACK_NFT_PREREQ_START ===
NFT_DOCKER_USER_TABLE="docker-user"
NFT_DOCKER_USER_CHAIN="forward"

BLOCKING_RULE_ERROR=0

set_blocking_rule_error() {
\tBLOCKING_RULE_ERROR=1
}

verify_nftables_swarm_is_disabled() {
\tlocal data_root="${1}"
\treturn 0
}

verify_nftables_forwarding() {
\tlocal ipv4_forwarding=""
\tlocal ipv6_forwarding=""

\tipv4_forwarding="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)"
\tipv6_forwarding="$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null)"

\tif [ "${ipv4_forwarding}" != "1" ] || [ "${ipv6_forwarding}" != "1" ]; then
\t\tlogger -t "dockerd-init" -p err "Docker nftables backend requires net.ipv4.ip_forward=1 and net.ipv6.conf.all.forwarding=1 before startup"
\t\treturn 1
\tfi

\treturn 0
}

verify_nftables_prerequisites() {
\tlocal data_root="${1}"

\tverify_nftables_swarm_is_disabled "${data_root}" || return 1
\tverify_nftables_forwarding || return 1
}

ensure_docker_nftables_nat() {
\t# 验证 nftables 基础可用性。Docker nftables backend
\t# 自行管理 NAT 规则，此处仅做基础检查。
\tnft --version >/dev/null 2>&1 || {
\t\tlogger -t "dockerd-init" -p err "nftables is not available; Docker nftables backend will not work"
\t\treturn 1
\t}
\treturn 0
}
# === DOCKER_STACK_NFT_PREREQ_END ==='''

        content = content.replace(insert_marker, insert_marker + nft_block)
        init_path.write_text(content)
        self.logger.ok("dockerd init nftables 前置校验已注入")
        return True

    def _patch_process_config(self, init_path: Path) -> bool:
        """修改 process_config 函数以支持 firewall_backend 检测。"""
        content = init_path.read_text()

        # 如果已经修补，跳过
        if 'config_get firewall_backend globals firewall_backend "nftables"' in content:
            self.logger.skip("process_config 已包含 firewall_backend")
            return True

        # 替换 data_root 配置行，插入 firewall_backend 逻辑
        old_line = 'config_get data_root globals data_root "/opt/docker/"'
        new_block = '''\tconfig_get data_root globals data_root "/opt/docker/"
\tconfig_get log_level globals log_level "warn"
\tif uci_quiet get dockerd.globals.firewall_backend; then
\t\tconfig_get firewall_backend globals firewall_backend "nftables"
\telse
\t\tfirewall_backend="nftables"
\t\tlogger -t "dockerd-init" -p notice "Migrating dockerd firewall backend to ${firewall_backend}"
\t\tuci_quiet set dockerd.globals.firewall_backend="${firewall_backend}" && uci_quiet commit dockerd || {
\t\t\tlogger -t "dockerd-init" -p err "Failed to persist dockerd firewall backend migration"
\t\t\treturn 1
\t\t}
\tfi
\tcase "${firewall_backend}" in
\t\tiptables|nftables)
\t\t\t;;
\t\t*)
\t\t\tlogger -t "dockerd-init" -p notice "Unsupported dockerd firewall backend ${firewall_backend}, defaulting to nftables"
\t\t\tfirewall_backend="nftables"
\t\t\t;;
\tesac
\tif [ "${firewall_backend}" = "nftables" ]; then
\t\tverify_nftables_prerequisites "${data_root}" || return 1
\t\tensure_docker_nftables_nat || return 1
\tfi
\tconfig_get_bool iptables globals iptables "1"
\tconfig_get_bool ip6tables globals ip6tables "0"'''

        if old_line in content:
            content = content.replace(old_line, new_block)
            init_path.write_text(content)
            self.logger.ok("dockerd init process_config 已注入 firewall_backend")
            return True
        else:
            self.logger.warn("dockerd init 未找到 data_root 配置行")
            return False

    def _patch_blocking_rules(self, init_path: Path) -> bool:
        """注入 nftables blocking rules 支持。"""
        content = init_path.read_text()

        # 检查是否已注入
        if 'BLOCKING_RULE_ERROR=0' in content and 'nftables_create_blocking_table' in content:
            self.logger.skip("blocking rules 已注入")
            return True

        # 替换 iptables_add_blocking_rule 调用
        old = '''\t[ "${iptables}" -eq "1" ] && config_foreach iptables_add_blocking_rule firewall'''
        new = '''\tBLOCKING_RULE_ERROR=0
\tif [ "${firewall_backend}" = "nftables" ]; then
\t\tnftables_create_blocking_table || {
\t\t\tset_blocking_rule_error
\t\t\treturn 1
\t\t}
\t\tif ! nft flush chain inet "${NFT_DOCKER_USER_TABLE}" "${NFT_DOCKER_USER_CHAIN}"; then
\t\t\tlogger -t "dockerd-init" -p err "Failed to reset nftables docker policy chain"
\t\t\tset_blocking_rule_error
\t\t\treturn 1
\t\tfi
\tfi

\tconfig_foreach iptables_add_blocking_rule firewall "${firewall_backend}"
\t[ "${BLOCKING_RULE_ERROR}" -eq 0 ] || return 1'''

        if old in content:
            content = content.replace(old, new)
            init_path.write_text(content)
            self.logger.ok("dockerd init blocking rules 已注入")
            return True

        # 尝试另一种格式
        old2 = '''\t[ "${iptables}" -eq "1" ] && \\'''
        if old2 in content:
            # 找到多行版本
            pattern = re.compile(r'\t\[ "\$\{iptables\}" -eq "1" \] && \\\n\tconfig_foreach iptables_add_blocking_rule firewall')
            if pattern.search(content):
                content = pattern.sub(new, content)
                init_path.write_text(content)
                self.logger.ok("dockerd init blocking rules 已注入（多行格式）")
                return True

        self.logger.warn("dockerd init 未找到 blocking rules 注入点")
        return False

    def _inject_nft_rule_helpers(self, init_path: Path) -> bool:
        """在 dockerd init 脚本末尾注入 nftables 规则辅助函数。"""
        content = init_path.read_text()

        if 'nftables_create_blocking_table()' in content and 'nftables_add_blocking_rules()' in content:
            self.logger.skip("nftables 规则辅助函数已存在")
            return True

        helpers = '''

nftables_create_blocking_table() {
\tif ! nft list table inet "${NFT_DOCKER_USER_TABLE}" >/dev/null 2>&1; then
\t\tif ! nft add table inet "${NFT_DOCKER_USER_TABLE}"; then
\t\t\tlogger -t "dockerd-init" -p err "Failed to create nftables table inet ${NFT_DOCKER_USER_TABLE}"
\t\t\treturn 1
\t\tfi
\tfi

\tif ! nft list chain inet "${NFT_DOCKER_USER_TABLE}" "${NFT_DOCKER_USER_CHAIN}" >/dev/null 2>&1; then
\t\tif ! nft add chain inet "${NFT_DOCKER_USER_TABLE}" "${NFT_DOCKER_USER_CHAIN}" '{ type filter hook forward priority 0; policy accept; }'; then
\t\t\tlogger -t "dockerd-init" -p err "Failed to create nftables chain inet ${NFT_DOCKER_USER_TABLE} ${NFT_DOCKER_USER_CHAIN}"
\t\t\treturn 1
\t\tfi
\tfi
}

nftables_add_blocking_rules() {
\tlocal cfg="${1}"

\tlocal device=""
\tlocal extra_iptables_args=""

\thandle_nftables_rule() {
\t\tlocal interface="${1}"
\t\tlocal outbound="${2}"

\t\tlocal inbound=""

\t\t. /lib/functions/network.sh
\t\tnetwork_get_physdev inbound "${interface}"

\t\t[ -z "${inbound}" ] && {
\t\t\tlogger -t "dockerd-init" -p notice "Unable to get physical device for interface ${interface}"
\t\t\treturn
\t\t}

\t\tlogger -t "dockerd-init" -p notice "Drop traffic from ${inbound} to ${outbound}"
\t\tif ! nft add rule inet "${NFT_DOCKER_USER_TABLE}" "${NFT_DOCKER_USER_CHAIN}" iifname "${inbound}" oifname "${outbound}" reject; then
\t\t\tlogger -t "dockerd-init" -p err "Failed to add nftables docker policy from ${inbound} to ${outbound}"
\t\t\tset_blocking_rule_error
\t\t\treturn 1
\t\tfi
\t}

\tconfig_get device "${cfg}" device

\t[ -z "${device}" ] && {
\t\tlogger -t "dockerd-init" -p notice "No device configured for ${cfg}"
\t\treturn
\t}

\tconfig_get extra_iptables_args "${cfg}" extra_iptables_args
\t[ -n "${extra_iptables_args}" ] && {
\t\tlogger -t "dockerd-init" -p err "extra_iptables_args is not supported when firewall_backend is nftables"
\t\tset_blocking_rule_error
\t\treturn 1
\t}

\tconfig_list_foreach "${cfg}" blocked_interfaces handle_nftables_rule "${device}"
}'''

        # 在 stop_service 之前插入
        if 'stop_service() {' in content:
            content = content.replace('stop_service() {', helpers + '\n\nstop_service() {')
            init_path.write_text(content)
            self.logger.ok("dockerd init nftables 规则辅助函数已注入")
            return True

        # 否则追加到文件末尾
        content += helpers
        init_path.write_text(content)
        self.logger.ok("dockerd init nftables 规则辅助函数已追加到文件末尾")
        return True

    def _patch_service_error_handling(self, init_path: Path) -> bool:
        """修复 service 错误处理，确保 process_config 失败时中止。"""
        content = init_path.read_text()

        # 确保 process_config 前有错误处理
        content = content.replace(
            'start_service() {',
            'start_service() {\n\tprocess_config || return 1',
        )
        content = content.replace(
            'reload_service() {',
            'reload_service() {\n\tprocess_config || return 1',
        )

        # 注入 rpcd restart（Docker 启动后重启 rpcd 让其重新发现 Docker）
        if 'rpcd restart' not in content:
            content = content.replace(
                'rc_procd start_service',
                'rc_procd start_service\n\tsleep 5\n\t/etc/init.d/rpcd restart',
            )
            content = content.replace(
                'procd_close_instance',
                'procd_close_instance\n\tsleep 5\n\t/etc/init.d/rpcd restart',
            )

        init_path.write_text(content)
        self.logger.ok("dockerd init 错误处理已修复")
        return True

    # ---- Dockerman 修补 ----

    def _patch_dockerman_nftables(self, init_path: Path) -> bool:
        """修补 dockerman init 脚本的 nftables 后端检测。"""
        content = init_path.read_text()

        # 如果已经修补，跳过
        if 'dockerman_use_iptables()' in content:
            self.logger.skip("dockerman 已包含 nftables 后端检测")
            return True

        # 注入 firewall_backend 检测函数
        helpers = '''

dockerman_firewall_backend() {
\tlocal backend=""
\tbackend="$(uci -q get dockerd.globals.firewall_backend 2>/dev/null)"
\t[ -n "${backend}" ] || backend="nftables"
\techo "${backend}"
}

dockerman_use_iptables() {
\tlocal backend=""
\tlocal iptables_enabled=""

\tbackend="$(dockerman_firewall_backend)"
\t[ "${backend}" = "iptables" ] || return 1

\tiptables_enabled="$(uci -q get dockerd.globals.iptables 2>/dev/null)"
\t[ -n "${iptables_enabled}" ] || iptables_enabled="1"

\t[ "${iptables_enabled}" = "1" ]
}'''

        # 在 _DOCKERD 行后注入
        insert_marker = '_DOCKERD=/etc/init.d/dockerd'
        if insert_marker in content:
            content = content.replace(insert_marker, insert_marker + helpers)

        # 注入 nftables 分支到 start_service
        old_start = 'dockerd running) && docker_running || return 0'
        new_start = '''dockerd running) && docker_running || return 0
\tdockerman_use_iptables || {
\t\tlogger -t "dockerman" -p notice "dockerd firewall backend is nftables; skip DOCKER-MAN iptables chain management"
\t\treturn 0
\t}'''

        if old_start in content:
            content = content.replace(old_start, new_start)
            init_path.write_text(content)
            self.logger.ok("dockerman nftables 后端检测已注入")
            return True
        else:
            init_path.write_text(content)
            self.logger.ok("dockerman nftables 后端检测已注入（未找到精确匹配点）")
            return True

    # ---- UCI 配置 ----

    def _configure_dockerd_uci(self, config_path: Path) -> bool:
        """配置 dockerd UCI 默认值。"""
        docker_cfg = self.config.docker
        content = config_path.read_text()

        # 设置 firewall_backend
        if f"firewall_backend" not in content:
            if "config globals 'globals'" in content:
                content = content.replace(
                    "config globals 'globals'",
                    f"config globals 'globals'",
                )
                # 在 globals 段末尾添加
                lines = content.split("\n")
                new_lines = []
                in_globals = False
                added = False
                for line in lines:
                    new_lines.append(line)
                    if "config globals 'globals'" in line:
                        in_globals = True
                        continue
                    if in_globals and not added:
                        if line.strip().startswith("option") or line.strip().startswith("list"):
                            continue
                        if line.strip().startswith("config") or line.strip() == "":
                            new_lines.insert(-1, f"\toption firewall_backend '{docker_cfg.firewall_backend}'")
                            added = True
                            in_globals = False

                if not added:
                    # 简单追加
                    content = content.replace(
                        "config globals 'globals'",
                        f"config globals 'globals'\n\toption firewall_backend '{docker_cfg.firewall_backend}'",
                    )
                else:
                    content = "\n".join(new_lines)

        # 设置 registry_mirrors（删除旧的，添加新的）
        content = "\n".join([l for l in content.split("\n") if "registry_mirrors" not in l])
        for mirror in docker_cfg.registry_mirrors:
            content = content.replace(
                "config globals 'globals'",
                f"config globals 'globals'\n\tlist registry_mirrors '{mirror}'",
            )

        config_path.write_text(content)
        self.logger.ok(f"dockerd UCI 已配置（firewall_backend={docker_cfg.firewall_backend}）")
        return True

    def _configure_sysctl(self, sysctl_path: Path) -> bool:
        """配置 sysctl 确保 IP 转发启用。"""
        content = sysctl_path.read_text()

        for key, value in [("net.ipv4.ip_forward", "1"), ("net.ipv6.conf.all.forwarding", "1")]:
            pattern = re.compile(rf"^{re.escape(key)}\s*=\s*\d+", re.MULTILINE)
            if pattern.search(content):
                content = pattern.sub(f"{key}={value}", content)
            else:
                content += f"\n{key}={value}"

        sysctl_path.write_text(content)
        self.logger.ok("sysctl IP 转发已配置")
        return True

    # ---- 主入口 ----

    def configure(self) -> bool:
        """执行所有 Docker 配置。"""
        docker_cfg = self.config.docker

        # 检查 kernel 版本是否支持 nftables（>= 5.4）
        kernel_version = self._detect_kernel_version()
        if kernel_version:
            major, minor = kernel_version
            if major < 5 or (major == 5 and minor < 4):
                self.logger.skip(f"kernel {major}.{minor} < 5.4，跳过 nftables 迁移")
                return True

        # 1. 修补 dockerd Makefile
        makefile = self._resolve_dockerd_makefile()
        if makefile:
            self._patch_depends_block(makefile)
            self._fix_vendored_checks(makefile)
        else:
            self.logger.warn("dockerd Makefile 未找到")

        # 2. 修补 dockerd init 脚本
        init_path = self._resolve_dockerd_init()
        if init_path:
            self._inject_nft_prereq_block(init_path)
            self._patch_process_config(init_path)
            self._patch_blocking_rules(init_path)
            self._inject_nft_rule_helpers(init_path)
            self._patch_service_error_handling(init_path)
        else:
            self.logger.warn("dockerd init 脚本未找到")

        # 3. 配置 UCI
        config_path = self._resolve_dockerd_config()
        if config_path:
            self._configure_dockerd_uci(config_path)
        else:
            self.logger.warn("dockerd UCI 配置未找到")

        # 4. 配置 sysctl
        sysctl_path = self._resolve_dockerd_sysctl()
        if sysctl_path:
            self._configure_sysctl(sysctl_path)
        else:
            self.logger.warn("dockerd sysctl 文件未找到")

        # 5. 修补 dockerman
        dockerman_init = self._resolve_dockerman_init()
        if dockerman_init:
            self._patch_dockerman_nftables(dockerman_init)
        else:
            self.logger.skip("dockerman 未安装，跳过")

        # 6. 安装 docker 服务超时 uci-defaults
        timeouts_src = self.base_path / "patches" / "992-docker-service-timeouts"
        if timeouts_src.exists():
            uci_defaults_dir = self.build_dir / "package" / "base-files" / "files" / "etc" / "uci-defaults"
            uci_defaults_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(timeouts_src, uci_defaults_dir / "992-docker-service-timeouts")
            self.logger.ok("docker 服务超时 uci-defaults 已安装")

        self.logger.done("Docker 配置完成")
        return True

    def _detect_kernel_version(self) -> tuple[int, int] | None:
        """从 OpenWrt 构建树检测内核版本。"""
        for f in sorted(self.build_dir.glob("include/kernel-*")):
            try:
                content = f.read_text()
                match = re.search(r'LINUX_VERSION-(\d+)\.(\d+)', content)
                if match:
                    return (int(match.group(1)), int(match.group(2)))
            except Exception:
                continue
        return None
