"""包管理。"""

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
        # TODO: Phase 2 实现
        self.logger.skip("包移除（Phase 2 实现）")
        return True

    def remove_tweaked(self) -> bool:
        """注释掉 target.mk 中的 tweak 包。"""
        # TODO: Phase 2 实现
        self.logger.skip("tweak 包移除（Phase 2 实现）")
        return True

    def remove_attendedsysupgrade(self) -> bool:
        """从 luci collections 中移除 attendedsysupgrade。"""
        # TODO: Phase 2 实现
        self.logger.skip("attendedsysupgrade 移除（Phase 2 实现）")
        return True

    def fix_apk_versions(self) -> bool:
        """修复 APK 版本号格式兼容性。"""
        # TODO: Phase 2 实现
        self.logger.skip("APK 版本修复（Phase 2 实现）")
        return True

    def fix_apk_conflicts(self) -> bool:
        """修复 APK 文件冲突。"""
        # TODO: Phase 2 实现
        self.logger.skip("APK 文件冲突修复（Phase 2 实现）")
        return True
