"""CLI 入口 + 构建管线编排。

用法:
    python wrt_core/builder/main.py              # 完整构建
    python wrt_core/builder/main.py --step clone,feeds  # 部分步骤
    python wrt_core/builder/main.py --upgrade-check     # 检查 patch
    python wrt_core/builder/main.py --log-level debug   # 详细日志
    python wrt_core/builder/main.py --debug             # debug 模式
"""

import argparse
import os
import sys
from pathlib import Path

from .config import load_config, BuildConfig
from .logger import BuildLogger, LogLevel
from .repo import RepoManager
from .feeds import FeedManager
from .packages import PackageManager
from .patcher import PatchManager
from .system import SystemConfigurator
from .docker import DockerConfigurator
from .image import ImageManager


def _detect_wrt_core_path() -> Path:
    """检测 wrt_core 目录路径。"""
    candidates = [
        Path("wrt_core"),
        Path("../wrt_core"),
    ]
    for c in candidates:
        if c.is_dir():
            return c.resolve()
    raise FileNotFoundError(
        "未找到 wrt_core 目录，请在项目根目录运行此脚本"
    )


def _get_base_path() -> Path:
    """获取 wrt_core 的绝对路径。"""
    return _detect_wrt_core_path()


def _resolve_build_dir(config: BuildConfig, base_path: Path) -> Path:
    """解析构建目录路径。"""
    # 如果存在 action_build（GitHub Actions），优先使用
    action_build = base_path.parent / "action_build"
    if action_build.is_dir():
        return action_build
    return base_path.parent / config.source.build_dir


def _run_step(step_name: str, step_handlers: dict, logger: BuildLogger) -> bool:
    """运行单个步骤。"""
    handler = step_handlers.get(step_name)
    if handler is None:
        logger.warn(f"未知步骤: {step_name}，跳过")
        return True
    return handler()


def main():
    parser = argparse.ArgumentParser(
        description="ImmortalWrt x86_64 固件构建工具",
    )
    parser.add_argument(
        "--step", "-s",
        help="只运行指定步骤（逗号分隔），如: clone,feeds_update",
    )
    parser.add_argument(
        "--log-level",
        default="info",
        choices=["debug", "info", "warn", "error"],
        help="日志级别（默认: info）",
    )
    parser.add_argument(
        "--upgrade-check",
        action="store_true",
        help="检查所有 patch 在上游版本中的兼容性",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="debug 模式：clone + config 后退出",
    )

    args = parser.parse_args()

    # 映射日志级别
    level_map = {
        "debug": LogLevel.DEBUG,
        "info": LogLevel.INFO,
        "warn": LogLevel.WARN,
        "error": LogLevel.ERROR,
    }
    log_level = level_map.get(args.log_level, LogLevel.INFO)

    # 路径解析
    base_path = _get_base_path()
    config_path = base_path / "build.yaml"

    # 初始化日志
    log_file = base_path.parent / "build.log"
    with BuildLogger(str(log_file), level=log_level) as logger:
        logger.info(f"构建工具启动")
        logger.info(f"wrt_core 路径: {base_path}")
        logger.info(f"配置文件: {config_path}")
        logger.info(f"日志文件: {log_file}")

        # 加载配置
        logger.step(1, 1, "加载配置")
        try:
            config = load_config(str(config_path))
            logger.ok(f"配置加载完成: {config.source.repo} ({config.source.branch})")
        except (FileNotFoundError, ValueError) as e:
            logger.fail(f"配置加载失败: {e}")
            sys.exit(1)

        if args.debug:
            logger.info("Debug 模式：配置加载完成，退出")
            sys.exit(0)

        # 构建目录
        build_dir = _resolve_build_dir(config, base_path)

        # 初始化模块
        repo = RepoManager(config, base_path, logger)
        feeds = FeedManager(config, base_path, build_dir, logger)
        packages = PackageManager(config, base_path, build_dir, logger)
        patches = PatchManager(config, base_path, build_dir, logger)
        system = SystemConfigurator(config, base_path, build_dir, logger)
        docker = DockerConfigurator(config, base_path, build_dir, logger)
        image = ImageManager(config, base_path, build_dir, logger)

        # 步骤处理函数映射
        step_handlers = {
            "clone": repo.clone_repo,
            "clean_up": repo.clean_up,
            "feeds_update": feeds.update_feeds,
            "feeds_install": feeds.install_feeds,
            "remove_packages": packages.remove_unwanted,
            "remove_package_links": packages.remove_package_links,
            "install_custom_feed": feeds.install_custom_feed,
            "apply_patches": lambda: all(
                r.fail_count == 0
                for r in patches.apply_all()
            ) if not args.upgrade_check else True,
            "system_config": system.configure,
            "docker_config": docker.configure,
            "generate_config": image.generate_config,
            "make_download": image.make_download,
            "make_build": image.make_build,
            "package_output": image.package_output,
        }

        # 确定步骤列表
        if args.upgrade_check:
            logger.step(1, 1, "Patch 兼容性检查")
            results = patches.check_all()
            for gr in results:
                for pr in gr.results:
                    if pr.status == "OK":
                        logger.ok(f"{pr.name} → {pr.target}")
                    elif pr.status == "FAIL":
                        logger.fail(f"{pr.name} → {pr.target}: {pr.detail}")
                    else:
                        logger.skip(f"{pr.name} → {pr.target}: {pr.detail}")
            sys.exit(0)

        # 筛选步骤
        if args.step:
            selected_steps = [s.strip() for s in args.step.split(",")]
        else:
            selected_steps = config.steps

        # 执行步骤
        total_steps = len(selected_steps)
        success = True
        for i, step_name in enumerate(selected_steps, 1):
            logger.step(i, total_steps, step_name)
            ok = _run_step(step_name, step_handlers, logger)
            if ok:
                logger.done(f"{step_name} 完成")
            else:
                logger.fail(f"{step_name} 失败")
                success = False
                break

        if success:
            logger.info("构建完成")
        else:
            logger.error("构建失败")
            sys.exit(1)


if __name__ == "__main__":
    main()
