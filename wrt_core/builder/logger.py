"""结构化日志系统。

功能：
- 彩色终端输出（绿色 OK、红色 FAIL、黄色 SKIP、蓝色 STEP）
- 同时写入 build.log 文件（纯文本，含完整时间戳）
- 支持 INFO / DEBUG / WARN / ERROR 四级
- 自动检测 CI 环境（GITHUB_ACTIONS），禁用颜色
"""

import sys
import os
from datetime import datetime
from typing import TextIO


class Colors:
    GREEN = "\033[32m"
    RED = "\033[31m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


class LogLevel:
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3

    _LABELS = {DEBUG: "DEBUG", INFO: "INFO", WARN: "WARN", ERROR: "ERROR"}
    _COLORS = {DEBUG: Colors.CYAN, INFO: Colors.GREEN, WARN: Colors.YELLOW, ERROR: Colors.RED}


class BuildLogger:
    """构建日志器，同时输出到终端和文件。"""

    def __init__(self, log_file: str = "build.log", level: int = LogLevel.INFO):
        self.level = level
        self.in_ci = "GITHUB_ACTIONS" in os.environ
        self.log_file_path = log_file
        self._file: TextIO | None = None

    def __enter__(self):
        self._file = open(self.log_file_path, "w", encoding="utf-8")
        return self

    def __exit__(self, *args):
        if self._file:
            self._file.close()

    def _write(self, level: int, message: str, **kwargs):
        timestamp = datetime.now().strftime("%H:%M:%S")
        label = LogLevel._LABELS.get(level, "INFO")
        color = LogLevel._COLORS.get(level, Colors.RESET)

        # 文件日志（纯文本）
        if self._file:
            self._file.write(f"[{timestamp}] [{label}] {message}\n")
            self._file.flush()

        # 终端输出（彩色）
        if level >= self.level:
            prefix = f"{color}{label}{Colors.RESET}" if not self.in_ci else label
            print(f"{prefix} {message}", **kwargs)

    def debug(self, message: str):
        self._write(LogLevel.DEBUG, message)

    def info(self, message: str):
        self._write(LogLevel.INFO, message)

    def warn(self, message: str):
        self._write(LogLevel.WARN, message)

    def error(self, message: str):
        self._write(LogLevel.ERROR, message)

    def step(self, current: int, total: int, title: str):
        """输出步骤标题。"""
        ts = datetime.now().strftime("%H:%M:%S")
        if self._file:
            self._file.write(f"\n{'='*60}\n[{ts}] [STEP {current}/{total}] {title}\n{'='*60}\n")
        color = Colors.BOLD if not self.in_ci else ""
        reset = Colors.RESET if not self.in_ci else ""
        print(f"\n{color}[STEP {current}/{total}] {title}{reset}")

    def ok(self, message: str):
        c = Colors.GREEN if not self.in_ci else ""
        r = Colors.RESET if not self.in_ci else ""
        self.info(f"{c}[OK]{r}    {message}")

    def fail(self, message: str):
        c = Colors.RED if not self.in_ci else ""
        r = Colors.RESET if not self.in_ci else ""
        self.info(f"{c}[FAIL]{r}  {message}")

    def skip(self, message: str):
        c = Colors.YELLOW if not self.in_ci else ""
        r = Colors.RESET if not self.in_ci else ""
        self.info(f"{c}[SKIP]{r}  {message}")

    def done(self, message: str):
        c = Colors.GREEN if not self.in_ci else ""
        r = Colors.RESET if not self.in_ci else ""
        self.info(f"{c}[DONE]{r}  {message}")
