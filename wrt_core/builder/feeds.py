"""Feed 管理。

管理 feeds 的更新、安装和自定义 feed 的稀疏克隆。
支持多个 feed 源和外部独立仓库。
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .config import BuildConfig, FeedSource, ExternalFeed
from .logger import BuildLogger


CUSTOM_FEED_NAME = "custom_feed"

GOLANG_REPO = "https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH = "26.x"


class FeedManager:
    """管理 feeds 的更新、安装和自定义 feed 的稀疏克隆。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    # ---- 基础 feed 操作 ----

    def update_feeds(self) -> bool:
        """更新所有 feeds。"""
        # 确保 include/bpf.mk 存在
        bpf_mk = self.build_dir / "include" / "bpf.mk"
        if not bpf_mk.exists():
            bpf_mk.touch()
            self.logger.debug("创建 include/bpf.mk（空文件）")

        self.logger.info("更新 feeds...")
        result = subprocess.run(
            ["./scripts/feeds", "update", "-a"],
            cwd=str(self.build_dir), capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"feeds 更新失败: {result.stderr[:500]}")
            return False
        self.logger.ok("feeds 更新完成")
        return True

    def install_feeds(self) -> bool:
        """安装所有 feeds。"""
        self.logger.info("安装 feeds...")
        result = subprocess.run(
            ["./scripts/feeds", "install", "-a", "-f"],
            cwd=str(self.build_dir), capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"feeds 安装失败: {result.stderr[:500]}")
            return False
        self.logger.ok("feeds 安装完成")
        return True

    # ---- 自定义 feed 源 ----

    def _get_feeds_conf_path(self) -> Path:
        """获取 feeds.conf 路径。"""
        feeds_conf = self.build_dir / "feeds.conf"
        if feeds_conf.exists():
            return feeds_conf
        return self.build_dir / "feeds.conf.default"

    def _register_local_feed_source(self, custom_feed_dir: Path) -> bool:
        """将自定义 feed 目录注册为本地 src-link。"""
        feeds_path = self._get_feeds_conf_path()
        if not feeds_path.exists():
            self.logger.warn(f"feeds.conf 不存在: {feeds_path}")
            return False

        content = feeds_path.read_text()
        lines = content.split("\n")
        # 移除旧的 custom_feed 条目
        lines = [l for l in lines if CUSTOM_FEED_NAME not in l]
        # 添加新的
        lines.insert(0, f"src-link {CUSTOM_FEED_NAME} {custom_feed_dir}")
        feeds_path.write_text("\n".join(lines) + "\n")
        self.logger.ok(f"已将 {CUSTOM_FEED_NAME} 注册为本地 feed 源")
        return True

    def _sync_sparse_packages(self, repo_url: str, repo_branch: str,
                               target_dir: Path, repo_label: str,
                               packages: list[str]) -> bool:
        """从远程仓库稀疏同步指定包目录。"""
        if not packages:
            return True

        tmp_dir = Path(tempfile.mkdtemp())
        try:
            # 稀疏克隆
            clone_args = ["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse"]
            if repo_branch:
                clone_args.extend(["-b", repo_branch])
            clone_args.extend([repo_url, str(tmp_dir)])

            result = subprocess.run(clone_args, capture_output=True, text=True)
            if result.returncode != 0:
                self.logger.fail(f"从 {repo_label} 克隆失败: {result.stderr[:200]}")
                return False

            # 设置稀疏 checkout
            result = subprocess.run(
                ["git", "-C", str(tmp_dir), "sparse-checkout", "set", "--no-cone"] + packages,
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                self.logger.fail(f"稀疏检出配置失败: {result.stderr[:200]}")
                return False

            # checkout
            result = subprocess.run(
                ["git", "-C", str(tmp_dir), "checkout"],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                self.logger.fail(f"检出失败: {result.stderr[:200]}")
                return False

            # 复制包到目标目录
            for pkg in packages:
                src = tmp_dir / pkg
                dst = target_dir / pkg
                if src.exists():
                    if dst.exists():
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
                else:
                    self.logger.warn(f"{repo_label}: 包 {pkg} 不存在")

            self.logger.ok(f"{repo_label}: {len(packages)} 个包同步完成")
            return True

        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    def _fix_xray_allow_insecure_patch(self, custom_feed_dir: Path) -> bool:
        """Rewrite xray-core AllowInsecure patch for newer Xray-core sources.

        kiddin9/op-packages still carries a patch for an older Xray-core tree
        that removed a time-gated allowInsecure warning.  Xray-core 26.6.27
        removed the time gate and now returns PrintRemovedFeatureError()
        directly, so the old patch no longer applies.
        """
        patch_file = custom_feed_dir / "xray-core" / "patches" / "AllowInsecure.patch"
        if not patch_file.exists():
            return False

        patch_lines = [
            "--- a/infra/conf/transport_internet.go",
            "+++ b/infra/conf/transport_internet.go",
            "@@ -730,7 +730,7 @@ func (c *TLSConfig) Build() (proto.Message, error) {",
            " 	config.MasterKeyLog = c.MasterKeyLog",
            " ",
            " 	if c.AllowInsecure {",
            "-		return nil, errors.PrintRemovedFeatureError(`\"allowInsecure\"`, `\"pinnedPeerCertSha256\"(pcs) and \"verifyPeerCertByName\"(vcn)`)",
            "+		config.Fingerprint = \"unsafe+\" + config.Fingerprint",
            " 	}",
            ' 	if c.PinnedPeerCertSha256 != "" {',
            ' 		for v := range strings.SplitSeq(c.PinnedPeerCertSha256, ",") {',
            "--- a/transport/internet/tls/config.go",
            "+++ b/transport/internet/tls/config.go",
            "@@ -389,6 +389,9 @@ func (c *Config) GetTLSConfig(opts ...Option) *tls.Config {",
            " 		VerifyPeerCertificate:  randCarrier.verifyPeerCert,",
            " 	}",
            " 	randCarrier.Config = config",
            "+	if c.Fingerprint == \"unsafe\" || strings.HasPrefix(c.Fingerprint, \"unsafe+\") {",
            "+		config.InsecureSkipVerify = true",
            "+	}",
            " 	if len(c.VerifyPeerCertByName) > 0 {",
            " 		config.InsecureSkipVerify = true",
            " 	} else {",
            "--- a/transport/internet/tls/tls.go",
            "+++ b/transport/internet/tls/tls.go",
            "@@ -7,6 +7,7 @@ import (",
            " 	\"crypto/tls\"",
            " 	\"math/big\"",
            " 	\"slices\"",
            "+	\"strings\"",
            " 	\"time\"",
            " ",
            " 	utls \"github.com/refraction-networking/utls\"",
            "@@ -185,6 +186,9 @@ func init() {",
            " }",
            " ",
            " func GetFingerprint(name string) (fingerprint *utls.ClientHelloID) {",
            "+	if strings.HasPrefix(name, \"unsafe+\") {",
            "+		name = strings.TrimPrefix(name, \"unsafe+\")",
            "+	}",
            " 	if name == \"\" {",
            " 		return &utls.HelloChrome_Auto",
            " 	}",
            "",
        ]
        with patch_file.open("w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(patch_lines))
        self.logger.ok("xray-core: AllowInsecure.patch updated for Xray-core 26.6.27")
        return True

    def install_custom_feed(self) -> bool:
        """稀疏克隆自定义 feed 源并注册为本地 feed。"""
        sources = self.config.feeds.sources
        if not sources:
            self.logger.skip("没有配置自定义 feed 源")
            return True

        custom_feed_dir = self.build_dir / CUSTOM_FEED_NAME
        if custom_feed_dir.exists():
            shutil.rmtree(custom_feed_dir)
        custom_feed_dir.mkdir(parents=True)

        for source in sources:
            if not source.packages:
                continue
            ok = self._sync_sparse_packages(
                source.url, source.branch, custom_feed_dir,
                source.label, source.packages,
            )
            if not ok:
                self.logger.warn(f"{source.label}: 同步失败，继续下一个源")

        # 注册为本地 feed 源
        self._fix_xray_allow_insecure_patch(custom_feed_dir)

        self._register_local_feed_source(custom_feed_dir)

        # 更新 custom_feed 索引
        self.logger.info(f"更新 {CUSTOM_FEED_NAME} 本地 feed 索引...")
        subprocess.run(
            ["./scripts/feeds", "update", CUSTOM_FEED_NAME],
            cwd=str(self.build_dir), capture_output=True, check=False,
        )

        self.logger.ok("自定义 feed 安装完成")
        return True

    # ---- 外部独立仓库 ----

    def update_golang(self) -> bool:
        """更新 golang 包到指定版本。"""
        golang_dir = self.build_dir / "feeds" / "packages" / "lang" / "golang"
        if not golang_dir.exists():
            self.logger.skip("golang 目录不存在，跳过")
            return True

        self.logger.info("正在更新 golang 软件包...")
        shutil.rmtree(golang_dir)

        result = subprocess.run(
            ["git", "clone", "--depth", "1", "-b", GOLANG_BRANCH,
             GOLANG_REPO, str(golang_dir)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"golang 更新失败: {result.stderr[:200]}")
            return False

        self.logger.ok("golang 已更新")
        return True

    def update_smartdns(self) -> bool:
        """更新 smartdns 和 luci-app-smartdns。"""
        external = self.config.feeds.external
        smartdns_cfg = external.get("smartdns")
        luci_smartdns_cfg = external.get("luci_app_smartdns")

        if not smartdns_cfg:
            self.logger.skip("没有配置 smartdns 外部仓库")
            return True

        # smartdns 核心
        target_dir = self.build_dir / smartdns_cfg.target
        if target_dir.exists():
            shutil.rmtree(target_dir)

        self.logger.info("正在更新 smartdns...")
        result = subprocess.run(
            ["git", "clone", "--depth", "1", smartdns_cfg.repo, str(target_dir)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"smartdns 克隆失败: {result.stderr[:200]}")
            return False

        # 应用 smartdns 优化 patch
        patch_dir = self.base_path / "patches"
        for patch_name in smartdns_cfg.patches:
            patch_file = patch_dir / patch_name
            if patch_file.exists():
                # 复制 patch 到 smartdns 目录的 patches 子目录
                smartdns_patches_dir = target_dir / "patches"
                smartdns_patches_dir.mkdir(exist_ok=True)
                shutil.copy2(patch_file, smartdns_patches_dir / patch_name)
                self.logger.ok(f"smartdns: patch {patch_name} 已安装")

        # 跳过 PKG_MIRROR_HASH 检查
        makefile = target_dir / "Makefile"
        if makefile.exists():
            content = makefile.read_text()
            content = content.replace(
                "PKG_MIRROR_HASH:=",
                "PKG_MIRROR_HASH:=skip  # ",
            )
            makefile.write_text(content)

        # luci-app-smartdns
        if luci_smartdns_cfg:
            luci_target = self.build_dir / luci_smartdns_cfg.target
            if luci_target.exists():
                shutil.rmtree(luci_target)

            self.logger.info("正在更新 luci-app-smartdns...")
            result = subprocess.run(
                ["git", "clone", "--depth", "1", luci_smartdns_cfg.repo, str(luci_target)],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                self.logger.warn(f"luci-app-smartdns 克隆失败: {result.stderr[:200]}")
            else:
                self.logger.ok("luci-app-smartdns 已更新")

        self.logger.ok("smartdns 更新完成")
        return True

    def install_external_feeds(self) -> bool:
        """安装所有外部 feed 仓库（除 smartdns 外）。"""
        external = self.config.feeds.external
        if not external:
            return True

        for name, cfg in external.items():
            if name in ("smartdns", "luci_app_smartdns"):
                continue  # 由 update_smartdns 处理

            if not cfg.repo or not cfg.target:
                continue

            target_dir = self.build_dir / cfg.target
            if target_dir.exists():
                self.logger.skip(f"{name}: 目标目录已存在 {cfg.target}")
                continue

            self.logger.info(f"正在安装 {name}...")
            result = subprocess.run(
                ["git", "clone", "--depth", "1", cfg.repo, str(target_dir)],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                self.logger.warn(f"{name} 克隆失败: {result.stderr[:200]}")
            else:
                self.logger.ok(f"{name} 已安装到 {cfg.target}")

        return True
