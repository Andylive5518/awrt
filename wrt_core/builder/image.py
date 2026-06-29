"""构建产物处理。

管理 make download、make build、产物清理和打包。
"""

import os
import shutil
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
        jobs = jobs or self._detect_jobs()

        self.logger.info(f"执行 make download（-j{jobs}）...")
        result = subprocess.run(
            ["make", "download", f"-j{jobs}"],
            cwd=str(self.build_dir), capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"make download 失败: {result.stderr[:5000]}")
            return False
        self.logger.ok("make download 完成")
        return True

    def make_build(self, jobs: int = 0) -> bool:
        """执行 make V=s。"""
        jobs = jobs or self._detect_jobs()

        # 清理旧的构建产物
        target_dir = self.build_dir / "bin" / "targets"
        if target_dir.exists():
            self.logger.info("清理旧的构建产物...")
            subprocess.run(
                ["find", str(target_dir), "-type", "f",
                 "(", "-name", "*.manifest", "-o", "-name", "*efi.img.gz",
                 "-o", "-name", "*combined.img.gz", "-o", "-name", "*rootfs.tar.gz",
                 "-o", "-name", "*.vmdk", "-o", "-name", "*.qcow2", ")",
                 "-exec", "rm", "-f", "{}", "+"],
                capture_output=True, check=False,
            )

        self.logger.info(f"执行 make -j{jobs} V=s...")
        result = subprocess.run(
            ["make", f"-j{jobs}", "V=s"],
            cwd=str(self.build_dir), capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.logger.fail(f"构建失败: {result.stderr[:5000]}")
            return False
        self.logger.ok("构建完成")
        return True

    def package_output(self) -> bool:
        """复制构建产物到 firmware/ 目录。"""
        target_dir = self.build_dir / "bin" / "targets"
        firmware_dir = self.base_path.parent / "firmware"

        # 清空 firmware 目录
        if firmware_dir.exists():
            shutil.rmtree(firmware_dir)
        firmware_dir.mkdir(parents=True)

        # 查找并复制产物
        if target_dir.exists():
            result = subprocess.run(
                ["find", str(target_dir), "-type", "f",
                 "(", "-name", "*.manifest", "-o", "-name", "*efi.img.gz",
                 "-o", "-name", "*combined.img.gz", "-o", "-name", "*rootfs.tar.gz",
                 "-o", "-name", "*.vmdk", "-o", "-name", "*.qcow2", ")"],
                capture_output=True, text=True, check=False,
            )
            files = result.stdout.strip().split("\n") if result.stdout.strip() else []
            for f in files:
                if f:
                    shutil.copy2(f, firmware_dir / Path(f).name)
                    self.logger.ok(f"已复制: {Path(f).name}")

        # 删除 Packages.manifest（如果存在）
        packages_manifest = firmware_dir / "Packages.manifest"
        if packages_manifest.exists():
            packages_manifest.unlink()

        # GitHub Actions 中清理构建目录
        action_build = self.base_path.parent / "action_build"
        if action_build.is_dir():
            self.logger.info("清理 action_build...")
            subprocess.run(["make", "clean"], cwd=str(action_build), capture_output=True, check=False)

        self.logger.ok(f"构建产物已保存到 {firmware_dir}")
        return True

    def _detect_jobs(self) -> int:
        """检测并行编译任务数。"""
        env_jobs = os.environ.get("BUILD_JOBS")
        if env_jobs:
            return int(env_jobs)

        if "GITHUB_ACTIONS" in os.environ:
            return 2

        try:
            result = subprocess.run(["nproc"], capture_output=True, text=True)
            if result.returncode == 0:
                return int(result.stdout.strip()) + 1
        except Exception:
            pass

        return 2
