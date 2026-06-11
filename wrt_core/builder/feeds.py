"""Feed 管理。"""

import subprocess
from pathlib import Path

from .config import BuildConfig, FeedSource, ExternalFeed
from .logger import BuildLogger


class FeedManager:
    """管理 feeds 的更新、安装和自定义 feed 的稀疏克隆。"""

    def __init__(self, config: BuildConfig, base_path: Path, build_dir: Path, logger: BuildLogger):
        self.config = config
        self.base_path = base_path
        self.build_dir = build_dir
        self.logger = logger

    def update_feeds(self) -> bool:
        """更新所有 feeds。"""
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

    def install_custom_feed(self) -> bool:
        """稀疏克隆自定义 feed 源并注册为本地 feed。"""
        # TODO: Phase 2 实现
        self.logger.skip("自定义 feed 安装（Phase 2 实现）")
        return True
