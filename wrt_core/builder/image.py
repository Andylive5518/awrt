"""构建产物处理。"""

import subprocess
from pathlib import Path

from .config import BuildConfig
from .logger import BuildLogger


class ImageManager:
    """管理构建产物的清理、编译和打包。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    def make_download(self, jobs: int = 0) -> bool:
        """执行 make download。"""
        # TODO: Phase 3 实现
        self.logger.skip("make download（Phase 3 实现）")
        return True

    def make_build(self, jobs: int = 0) -> bool:
        """执行 make V=s。"""
        # TODO: Phase 3 实现
        self.logger.skip("make build（Phase 3 实现）")
        return True

    def package_output(self) -> bool:
        """复制构建产物到 firmware/ 目录。"""
        # TODO: Phase 3 实现
        self.logger.skip("产物打包（Phase 3 实现）")
        return True
