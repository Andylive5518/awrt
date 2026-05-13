#!/usr/bin/env bash

set -e

# Determine wrt_core path
if [ -d "wrt_core" ]; then
    WRT_CORE_PATH="wrt_core"
elif [ -d "../wrt_core" ]; then
    WRT_CORE_PATH="../wrt_core"
else
    echo "Error: wrt_core directory not found!"
    exit 1
fi

BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)

Build_Mod=$1

CONFIG_FILE="$BASE_PATH/deconfig/x64_immwrt.config"
INI_FILE="$BASE_PATH/compilecfg/x64_immwrt.ini"

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH="none"

apply_config() {
    \cp -f "$CONFIG_FILE" "$BASE_PATH/../$BUILD_DIR/.config"

    for frag in "$BASE_PATH/deconfig/"*.config; do
        [ "$(basename "$frag")" = "$(basename "$CONFIG_FILE")" ] && continue
        cat "$frag" >> "$BASE_PATH/../$BUILD_DIR/.config"
    done
}

remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/../$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/../$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

if [[ -d action_build ]]; then
    BUILD_DIR="action_build"
fi

"$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_DIR" "$COMMIT_HASH" "$CONFIG_FILE"

apply_config
remove_uhttpd_dependency

cd "$BASE_PATH/../$BUILD_DIR"
make defconfig

# 确保 dockerd 不被 defconfig 清除（small8 feed 索引残留导致 defconfig 误删）
if ! grep -q "^CONFIG_PACKAGE_dockerd=y$" "$BASE_PATH/../$BUILD_DIR/.config" 2>/dev/null; then
    if [ -f "$BASE_PATH/../$BUILD_DIR/feeds/packages/utils/dockerd/Makefile" ]; then
        echo "CONFIG_PACKAGE_dockerd=y" >> "$BASE_PATH/../$BUILD_DIR/.config"
        echo "dockerd: Makefile 存在但 defconfig 未包含，已强制添加到 .config"
    fi
fi

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/../$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*combined.img.gz" -o -name "*combined.img" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name "*.vmdk" -o -name "*.vdi" -o -name "*.vhdx" -o -name "*.qcow2" \) -exec rm -f {} +
fi

# BUILD_JOBS: 默认 $(($(nproc) + 1))，GitHub Actions 环境自动限制为 2
if [ -n "$BUILD_JOBS" ]; then
    BUILD_JOBS_VAL="$BUILD_JOBS"
elif [ -n "$GITHUB_ACTIONS" ]; then
    BUILD_JOBS_VAL=2
else
    BUILD_JOBS_VAL=$(($(nproc) + 1))
fi
echo "BUILD_JOBS=$BUILD_JOBS_VAL"

make download -j$BUILD_JOBS_VAL
make -j$BUILD_JOBS_VAL V=s

FIRMWARE_DIR="$BASE_PATH/../firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*combined.img.gz" -o -name "*combined.img" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name "*.vmdk" -o -name "*.vdi" -o -name "*.vhdx" -o -name "*.qcow2" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
\rm -f "$BASE_PATH/../firmware/Packages.manifest" 2>/dev/null

if [[ -d action_build ]]; then
    make clean
fi
