"""系统配置。"""

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

    def configure(self) -> bool:
        """执行所有系统配置。"""
        # TODO: Phase 3 实现
        self.logger.skip("系统配置（Phase 3 实现）")
        return True
