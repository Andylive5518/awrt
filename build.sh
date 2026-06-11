#!/usr/bin/env bash
#
# ImmortalWrt x86_64 固件构建工具
# 兼容入口：自动安装依赖并调用 Python 构建工具
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 自动安装依赖
if [ ! -f "$SCRIPT_DIR/wrt_core/requirements.txt" ]; then
    echo "Error: requirements.txt not found"
    exit 1
fi

pip install -q -r "$SCRIPT_DIR/wrt_core/requirements.txt" 2>/dev/null || {
    echo "Warning: pip install failed, continuing anyway..."
}

cd "$SCRIPT_DIR"
exec python3 -m wrt_core.builder.main "$@"
