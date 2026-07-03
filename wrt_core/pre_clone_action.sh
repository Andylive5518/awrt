#!/usr/bin/env bash
#
# ImmortalWrt x86_64 固件构建工具 - 预克隆阶段
# 从 build.yaml 读取上游仓库配置并执行 git clone（build.yaml 为唯一配置源）
#

set -e

# Determine wrt_core path
if [ -d "wrt_core" ]; then
    WRT_CORE_PATH="wrt_core"
elif [ -d "../wrt_core" ]; then
    WRT_CORE_PATH="../wrt_core"
else
    WRT_CORE_PATH=$(dirname "$0")
fi

BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)
CONFIG="$BASE_PATH/build.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Error: build.yaml not found: $CONFIG"
    exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "Error: 需要 python3 + PyYAML（运行 pip install -r wrt_core/requirements.txt）"
    exit 1
fi

# 从 build.yaml 读取 source 配置（唯一配置源）
REPO_URL=$(python3 -c "import yaml;d=yaml.safe_load(open('$CONFIG',encoding='utf-8'));print(d['source']['repo'])")
REPO_BRANCH=$(python3 -c "import yaml;d=yaml.safe_load(open('$CONFIG',encoding='utf-8'));print(d['source']['branch'])")

if [ -z "$REPO_URL" ] || [ -z "$REPO_BRANCH" ]; then
    echo "Error: build.yaml 中 source.repo / source.branch 缺失"
    exit 1
fi

# GitHub Actions 通常在仓库根目录运行；构建目录固定为 action_build（与 main.py 的 CI 分支一致）
BUILD_DIR="$BASE_PATH/../action_build"

echo "$REPO_URL $REPO_BRANCH"
# 写入 repo_flag（缓存 key 用），位于 wrt_core 上一级（通常是仓库根）
echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/../repo_flag"

git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"

# GitHub Action 移除国内下载源
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/\.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi
