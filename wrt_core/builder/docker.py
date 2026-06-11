"""Docker 配置。"""

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

    def configure(self) -> bool:
        """执行所有 Docker 配置。"""
        # TODO: Phase 3 实现
        self.logger.skip("Docker 配置（Phase 3 实现）")
        return True
