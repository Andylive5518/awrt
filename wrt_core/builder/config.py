"""配置加载与校验。

从 build.yaml 加载配置，用数据类进行结构校验。
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Optional

import yaml


# ---- 数据类定义 ----


@dataclass
class SourceConfig:
    repo: str = "https://github.com/immortalwrt/immortalwrt.git"
    branch: str = "v25.12.0"
    build_dir: str = "immortalwrt"


@dataclass
class TargetConfig:
    arch: str = "x86_64"
    device: str = "generic"
    rootfs_size: int = 3072
    images: list[str] = field(default_factory=lambda: ["vmdk", "qcow2", "efi.img.gz"])


@dataclass
class KernelConfig:
    base: str = ""
    fragments: list[str] = field(default_factory=list)


@dataclass
class PackageManagerConfig:
    type: str = "apk"
    repo: str = "https://mirrors.ustc.edu.cn/immortalwrt/releases/25.12.0"


@dataclass
class PackagesConfig:
    remove: dict[str, list[str]] = field(default_factory=dict)
    force_enable: list[str] = field(default_factory=list)
    apk_fixes: dict[str, str] = field(default_factory=dict)
    apk_file_conflicts: list[dict] = field(default_factory=list)


@dataclass
class FeedSource:
    label: str = ""
    url: str = ""
    branch: str = ""
    packages: list[str] = field(default_factory=list)


@dataclass
class ExternalFeed:
    repo: str = ""
    target: str = ""
    patches: list[str] = field(default_factory=list)


@dataclass
class FeedsConfig:
    sources: list[FeedSource] = field(default_factory=list)
    external: dict[str, ExternalFeed] = field(default_factory=dict)


@dataclass
class PatchDef:
    target: str = ""
    files: list[str] = field(default_factory=list)


@dataclass
class PatchesConfig:
    groups: dict[str, PatchDef] = field(default_factory=dict)


@dataclass
class UciDefaultsConfig:
    theme: str = "argon"
    lan_addr: str = "192.168.168.1"
    files: list[dict] = field(default_factory=list)


@dataclass
class PbrConfig:
    isps: list[str] = field(default_factory=lambda: ["cmcc", "ctcc", "cucc"])
    config_dir: str = "patches"


@dataclass
class SystemConfig:
    smp_affinity: str = ""
    monitoring_scripts: dict[str, str] = field(default_factory=dict)
    cron_tasks: list[dict] = field(default_factory=list)


@dataclass
class DockerConfig:
    firewall_backend: str = "nftables"
    storage_driver: str = "overlay2"
    data_root: str = "/opt/docker"
    registry_mirrors: list[str] = field(default_factory=list)


@dataclass
class BuildConfig:
    source: SourceConfig = field(default_factory=SourceConfig)
    target: TargetConfig = field(default_factory=TargetConfig)
    kernel_config: KernelConfig = field(default_factory=KernelConfig)
    package_manager: PackageManagerConfig = field(default_factory=PackageManagerConfig)
    packages: PackagesConfig = field(default_factory=PackagesConfig)
    feeds: FeedsConfig = field(default_factory=FeedsConfig)
    patches: PatchesConfig = field(default_factory=PatchesConfig)
    uci_defaults: UciDefaultsConfig = field(default_factory=UciDefaultsConfig)
    pbr: PbrConfig = field(default_factory=PbrConfig)
    system: SystemConfig = field(default_factory=SystemConfig)
    docker: DockerConfig = field(default_factory=DockerConfig)
    steps: list[str] = field(default_factory=lambda: [
        "clone", "feeds_update", "feeds_install", "remove_packages",
        "install_custom_feed", "apply_patches", "system_config",
        "docker_config", "generate_config", "make_download",
        "make_build", "package_output",
    ])


# ---- 加载函数 ----


def _merge_dict(base: dict, override: dict) -> dict:
    """递归合并字典。"""
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _merge_dict(result[key], value)
        else:
            result[key] = value
    return result


def _build_config_from_dict(data: dict) -> BuildConfig:
    """从字典构建 BuildConfig。"""
    config = BuildConfig()

    if "source" in data:
        s = data["source"]
        config.source = SourceConfig(
            repo=s.get("repo", config.source.repo),
            branch=s.get("branch", config.source.branch),
            build_dir=s.get("build_dir", config.source.build_dir),
        )

    if "target" in data:
        t = data["target"]
        config.target = TargetConfig(
            arch=t.get("arch", config.target.arch),
            device=t.get("device", config.target.device),
            rootfs_size=t.get("rootfs_size", config.target.rootfs_size),
            images=t.get("images", config.target.images),
        )

    if "kernel_config" in data:
        k = data["kernel_config"]
        config.kernel_config = KernelConfig(
            base=k.get("base", ""),
            fragments=k.get("fragments", []),
        )

    if "package_manager" in data:
        pm = data["package_manager"]
        config.package_manager = PackageManagerConfig(
            type=pm.get("type", config.package_manager.type),
            repo=pm.get("repo", config.package_manager.repo),
        )

    if "packages" in data:
        p = data["packages"]
        config.packages = PackagesConfig(
            remove=p.get("remove", {}),
            force_enable=p.get("force_enable", []),
            apk_fixes=p.get("apk_fixes", {}),
            apk_file_conflicts=p.get("apk_file_conflicts", []),
        )

    if "feeds" in data:
        f = data["feeds"]
        sources = []
        for src in f.get("sources", []):
            sources.append(FeedSource(
                label=src.get("label", ""),
                url=src.get("url", ""),
                branch=src.get("branch", ""),
                packages=src.get("packages", []),
            ))
        externals = {}
        for name, ext in f.get("external", {}).items():
            externals[name] = ExternalFeed(
                repo=ext.get("repo", ""),
                target=ext.get("target", ""),
                patches=ext.get("patches", []),
            )
        config.feeds = FeedsConfig(sources=sources, external=externals)

    if "patches" in data:
        groups = {}
        for name, pg in data["patches"].items():
            groups[name] = PatchDef(
                target=pg.get("target", ""),
                files=pg.get("files", []),
            )
        config.patches = PatchesConfig(groups=groups)

    if "uci_defaults" in data:
        u = data["uci_defaults"]
        config.uci_defaults = UciDefaultsConfig(
            theme=u.get("theme", config.uci_defaults.theme),
            lan_addr=u.get("lan_addr", config.uci_defaults.lan_addr),
            files=u.get("files", []),
        )

    if "pbr" in data:
        pb = data["pbr"]
        config.pbr = PbrConfig(
            isps=pb.get("isps", config.pbr.isps),
            config_dir=pb.get("config_dir", config.pbr.config_dir),
        )

    if "system" in data:
        sy = data["system"]
        config.system = SystemConfig(
            smp_affinity=sy.get("smp_affinity", ""),
            monitoring_scripts=sy.get("monitoring_scripts", {}),
            cron_tasks=sy.get("cron_tasks", []),
        )

    if "docker" in data:
        d = data["docker"]
        config.docker = DockerConfig(
            firewall_backend=d.get("firewall_backend", config.docker.firewall_backend),
            storage_driver=d.get("storage_driver", config.docker.storage_driver),
            data_root=d.get("data_root", config.docker.data_root),
            registry_mirrors=d.get("registry_mirrors", []),
        )

    if "steps" in data:
        config.steps = data["steps"]

    return config


def load_config(config_path: str) -> BuildConfig:
    """加载并校验 build.yaml 配置文件。

    Args:
        config_path: build.yaml 的路径

    Returns:
        校验后的 BuildConfig 对象

    Raises:
        FileNotFoundError: 配置文件不存在
        ValueError: YAML 格式错误或配置校验失败
    """
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"配置文件不存在: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            raise ValueError(f"YAML 解析错误: {e}")

    if not isinstance(data, dict):
        raise ValueError("配置文件必须是一个字典")

    return _build_config_from_dict(data)
