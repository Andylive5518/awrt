#!/usr/bin/env bash

get_custom_feed_name() {
    printf '%s\n' "custom_feed"
}

get_custom_feed_source_dir() {
    printf '%s\n' "$BUILD_DIR/$(get_custom_feed_name)"
}

get_custom_feed_worktree_dir() {
    printf '%s\n' "$BUILD_DIR/feeds/$(get_custom_feed_name)"
}

get_custom_feed_package_dir() {
    printf '%s\n' "$BUILD_DIR/package/feeds/$(get_custom_feed_name)"
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite" "luci-app-unblockneteasemusic" "luci-app-adguardhome" "luci-app-diskman"
        "luci-app-argon-config" "luci-theme-argon" "luci-app-cpufreq" "luci-app-docker"
        "luci-app-wechatpush" "luci-app-zerotier" "luci-app-usb-printer"
        "luci-app-autoreboot" "luci-app-microsocks"
    )
    local packages_net=(
        "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria" "v2raya"
        "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria" "v2raya"
        "mosdns" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter" "msd_lite" "cdnspeedtest"
        "microsocks" "tuic-server" "shadow-tls"
    )
    local packages_utils=(
        "cups" "coremark"
    )

    for pkg in "${luci_packages[@]}"; do
        if [[ -d "$BUILD_DIR/feeds/luci/applications/$pkg" ]]; then
            \rm -rf "$BUILD_DIR/feeds/luci/applications/$pkg"
        fi
        if [[ -d "$BUILD_DIR/feeds/luci/themes/$pkg" ]]; then
            \rm -rf "$BUILD_DIR/feeds/luci/themes/$pkg"
        fi
    done

    for pkg in "${packages_net[@]}"; do
        if [[ -d "$BUILD_DIR/feeds/packages/net/$pkg" ]]; then
            \rm -rf "$BUILD_DIR/feeds/packages/net/$pkg"
        fi
    done

    for pkg in "${packages_utils[@]}"; do
        if [[ -d "$BUILD_DIR/feeds/packages/utils/$pkg" ]]; then
            \rm -rf "$BUILD_DIR/feeds/packages/utils/$pkg"
        fi
    done

    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

collect_missing_directories() {
    local base_dir="$1"
    local -n required_dirs_ref="$2"
    local -n missing_dirs_ref="$3"
    local dir_name

    for dir_name in "${required_dirs_ref[@]}"; do
        if [ ! -d "$base_dir/$dir_name" ]; then
            missing_dirs_ref+=("${base_dir#$BUILD_DIR/}/$dir_name")
        fi
    done
}

update_golang() {
    if [[ -d "$BUILD_DIR/feeds/packages/lang/golang" ]]; then
        echo "正在更新 golang 软件包..."
        \rm -rf "$BUILD_DIR/feeds/packages/lang/golang"
        if ! git clone --depth 1 -b $GOLANG_BRANCH $GOLANG_REPO "$BUILD_DIR/feeds/packages/lang/golang"; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
    fi
}

sync_sparse_packages_to_feed_dir() {
    local repo_url="$1"
    local repo_branch="$2"
    local target_dir="$3"
    local repo_label="$4"
    shift 4

    local packages=("$@")
    local tmp_dir
    local missing_packages=()
    local clone_args=(clone --depth 1 --filter=blob:none --sparse)
    local pkg

    tmp_dir=$(mktemp -d)

    if [ -n "$repo_branch" ]; then
        clone_args+=(-b "$repo_branch")
    fi

    clone_args+=("$repo_url" "$tmp_dir")

    echo "正在从 $repo_label 稀疏同步指定目录..."
    if ! git "${clone_args[@]}"; then
        echo "错误：从 $repo_url 拉取仓库骨架失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! git -C "$tmp_dir" sparse-checkout set "${packages[@]}"; then
        echo "错误：配置 $repo_label 稀疏检出目录失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! git -C "$tmp_dir" checkout; then
        echo "错误：$repo_label 工作树检出失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    for pkg in "${packages[@]}"; do
        if [ -d "$tmp_dir/$pkg" ]; then
            if [ -d "$target_dir/$pkg" ]; then
                echo "注意：$pkg 已存在，将被 $repo_label 覆盖"
            fi
            rm -rf "$target_dir/$pkg"
            mv "$tmp_dir/$pkg" "$target_dir/"
        else
            missing_packages+=("$pkg")
        fi
    done

    rm -rf "$tmp_dir"

    if [ ${#missing_packages[@]} -ne 0 ]; then
        printf '错误：%s 仓库缺少以下必要目录：\n' "$repo_label" >&2
        printf '  - %s\n' "${missing_packages[@]}" >&2
        return 1
    fi
}

register_local_feed_source() {
    local custom_feed_dir="$1"
    local feeds_path="$2"
    local feed_name
    feed_name=$(get_custom_feed_name)

    sed -i "/[[:space:]]$feed_name[[:space:]]/d" "$feeds_path"
    [ -z "$(tail -c 1 "$feeds_path")" ] || echo "" >>"$feeds_path"
    echo "src-link $feed_name $custom_feed_dir" >>"$feeds_path"
    echo "已将 $feed_name 作为本地源 (src-link) 添加到 $feeds_path"
}

install_custom_feed() {
    local feeds_path
    local fullconenat_nft_dir="$BUILD_DIR/package/network/utils/fullconenat-nft"
    local fullconenat_dir="$BUILD_DIR/package/network/utils/fullconenat"
    local custom_feed_dir
    local custom_feed_worktree_dir
    local custom_feed_name

    local base_custom_feed_packages=(
        xray-core xray-plugin dns2socks hysteria microsocks \
        naiveproxy shadowsocks-rust sing-box geoview v2ray-plugin \
        chinadns-ng ipt2socks tcping simple-obfs shadowsocksr-libev \
        v2dat luci-app-adguardhome ddns-go luci-app-iperf3-server \
        luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd luci-app-store quickstart \
        luci-app-quickstart luci-app-istorex \
        lucky luci-app-lucky luci-app-openclash luci-app-homeproxy luci-app-amlogic \
        oaf open-app-filter luci-app-oaf easytier luci-app-easytier \
        msd_lite luci-app-msd_lite cups luci-app-cupsd mihomo \
        luci-app-fullconenat fullconenat luci-app-partexp momo luci-app-momo nikki luci-app-nikki \
        luci-app-zerotier luci-app-wechatpush luci-app-autoreboot mosdns luci-app-mosdns \
        luci-app-passwall luci-app-passwall2 openwrt-bandix luci-app-bandix luci-app-quickfile \
        luci-app-diskman \
        luci-theme-argon luci-app-argon-config
    )
    local required_feed_dirs=(
        v2ray-core v2ray-geodata
    )
    local custom_feed_sources=()
    local missing_feed_dirs=()
    local source_entry
    local repo_label
    local repo_url
    local repo_branch
    local repo_packages
    local repo_package_array=()

    if [ ! -d "$fullconenat_nft_dir" ]; then
        base_custom_feed_packages+=(fullconenat-nft)
    fi
    if [ ! -d "$fullconenat_dir" ]; then
        base_custom_feed_packages+=(fullconenat)
    fi

    custom_feed_sources=(
        "kiddin9/op-packages|https://github.com/kiddin9/op-packages.git||${base_custom_feed_packages[*]}"
        "kenzok8/jell|https://github.com/kenzok8/jell.git|main|v2ray-core v2ray-geodata"
    )

    feeds_path=$(get_feeds_path)
    custom_feed_name=$(get_custom_feed_name)
    custom_feed_dir=$(get_custom_feed_source_dir)
    custom_feed_worktree_dir=$(get_custom_feed_worktree_dir)

    if [ -d "$custom_feed_dir" ]; then
        echo "清理旧的自定义 feed 目录..."
        rm -rf "$custom_feed_dir"
    fi
    mkdir -p "$custom_feed_dir"

    for source_entry in "${custom_feed_sources[@]}"; do
        IFS='|' read -r repo_label repo_url repo_branch repo_packages <<< "$source_entry"
        read -r -a repo_package_array <<< "$repo_packages"

        if ! sync_sparse_packages_to_feed_dir "$repo_url" "$repo_branch" "$custom_feed_dir" "$repo_label" "${repo_package_array[@]}"; then
            rm -rf "$custom_feed_dir"
            return 1
        fi
    done

    register_local_feed_source "$custom_feed_dir" "$feeds_path"

    echo "正在更新 $custom_feed_name 本地 feed 索引..."
    ./scripts/feeds update "$custom_feed_name"

    collect_missing_directories "$custom_feed_worktree_dir" required_feed_dirs missing_feed_dirs

    if [ ${#missing_feed_dirs[@]} -ne 0 ]; then
        printf '错误：%s 本地 feed 未生成以下仓库依赖路径：\n' "$custom_feed_name" >&2
        printf '  - %s\n' "${missing_feed_dirs[@]}" >&2
        return 1
    fi

    echo "$custom_feed_name 指定包处理完成并已成功加载到 feeds 体系中！"
}

verify_custom_feed_installed_paths() {
    local custom_feed_name
    local custom_feed_package_dir
    local required_package_dirs=(
        luci-app-adguardhome luci-app-mosdns luci-app-easytier luci-app-homeproxy
        luci-app-passwall luci-app-nikki v2ray-core v2ray-geodata luci-app-quickfile
    )
    local missing_package_dirs=()

    custom_feed_name=$(get_custom_feed_name)
    custom_feed_package_dir=$(get_custom_feed_package_dir)

    collect_missing_directories "$custom_feed_package_dir" required_package_dirs missing_package_dirs

    if [ ${#missing_package_dirs[@]} -ne 0 ]; then
        printf '错误：%s 安装后缺少以下仓库依赖路径：\n' "$custom_feed_name" >&2
        printf '  - %s\n' "${missing_package_dirs[@]}" >&2
        return 1
    fi
}

check_default_settings() {
    local settings_dir="$BUILD_DIR/package/emortal/default-settings"
    if [ -z "$(find "$BUILD_DIR/package" -type d -name "default-settings" -print -quit 2>/dev/null)" ]; then
        echo "在 $BUILD_DIR/package 中未找到 default-settings 目录，正在从 immortalwrt 仓库克隆..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        if git clone --depth 1 --filter=blob:none --sparse https://github.com/immortalwrt/immortalwrt.git "$tmp_dir"; then
            pushd "$tmp_dir" >/dev/null
            git sparse-checkout set package/emortal/default-settings
            mkdir -p "$(dirname "$settings_dir")"
            mv package/emortal/default-settings "$settings_dir"
            popd >/dev/null
            rm -rf "$tmp_dir"
            echo "default-settings 克隆并移动成功。"
        else
            echo "错误：克隆 immortalwrt 仓库失败" >&2
            rm -rf "$tmp_dir"
            exit 1
        fi
    fi
}

add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"
    local repo_url="https://github.com/NONGFAH/luci-app-athena-led.git"

    echo "正在添加 luci-app-athena-led..."
    rm -rf "$athena_led_dir" 2>/dev/null

    if ! git clone --depth=1 "$repo_url" "$athena_led_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-athena-led 仓库失败" >&2
        exit 1
    fi

    if [ -d "$athena_led_dir" ]; then
        chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
        chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
    else
        echo "错误：克隆操作后未找到目录 $athena_led_dir" >&2
        exit 1
    fi
}

update_smartdns() {
    local target_dir="$(get_custom_feed_worktree_dir)"
    local smartdns_dir="$target_dir/smartdns"
    local luci_app_dir="$target_dir/luci-app-smartdns"

    echo "正在更新 smartdns..."
    rm -rf "$smartdns_dir"
    git clone --depth=1 "https://github.com/ZqinKing/openwrt-smartdns.git" "$smartdns_dir" || {
        echo "错误：克隆 smartdns 仓库失败" >&2
        return 1
    }

    echo "正在更新 luci-app-smartdns..."
    rm -rf "$luci_app_dir"
    git clone --depth=1 "https://github.com/pymumu/luci-app-smartdns.git" "$luci_app_dir" || {
        echo "错误：克隆 luci-app-smartdns 仓库失败" >&2
        return 1
    }

    echo "smartdns 更新完成。"
}

patch_smartdns() {
    local SMARTDNS_DIR="$(get_custom_feed_worktree_dir)/smartdns"

    echo "正在给 smartdns 打补丁..."
    install -Dm644 "$BASE_PATH/patches/100-smartdns-optimize.patch" "$SMARTDNS_DIR/patches/100-smartdns-optimize.patch"
    sed -i '/define Build\/Compile\/smartdns-ui/,/endef/s/CC=\$(TARGET_CC)/CC="\$(TARGET_CC_NOCACHE)"/' "$SMARTDNS_DIR/Makefile"
}

_sync_luci_lib_docker() {
    local lib_path="$BUILD_DIR/feeds/luci/libs/luci-lib-docker"
    local repo_url="https://github.com/lisaac/luci-lib-docker.git"

    if [ ! -d "$lib_path" ]; then
        echo "正在同步 luci-lib-docker..."
        mkdir -p "$BUILD_DIR/feeds/luci/libs" || return
        cd "$BUILD_DIR/feeds/luci/libs" || return

        if ! git clone --filter=blob:none --no-checkout "$repo_url" luci-lib-docker-tmp; then
            echo "错误：从 $repo_url 克隆 luci-lib-docker 仓库失败" >&2
            exit 1
        fi
        cd luci-lib-docker-tmp || return

        git sparse-checkout init --cone
        git sparse-checkout set collections/luci-lib-docker || return

        git checkout --quiet

        mv collections/luci-lib-docker ../luci-lib-docker || return
        cd .. || return
        \rm -rf luci-lib-docker-tmp
        cd "$BUILD_DIR"
        echo "luci-lib-docker 同步完成"
    fi
}

update_dockerman() {
    local path="$BUILD_DIR/feeds/luci/applications/luci-app-dockerman"
    local repo_url="https://github.com/lisaac/luci-app-dockerman.git"

    if [ -d "$path" ]; then
        echo "正在更新 dockerman..."
        _sync_luci_lib_docker || return

        cd "$BUILD_DIR/feeds/luci/applications" || return
        \rm -rf "luci-app-dockerman"

        if ! git clone --filter=blob:none --no-checkout "$repo_url" dockerman; then
            echo "错误：从 $repo_url 克隆 dockerman 仓库失败" >&2
            exit 1
        fi
        cd dockerman || return

        git sparse-checkout init --cone
        git sparse-checkout set applications/luci-app-dockerman || return

        git checkout --quiet

        mv applications/luci-app-dockerman ../luci-app-dockerman || return
        cd .. || return
        \rm -rf dockerman
        cd "$BUILD_DIR"

        if declare -F docker_stack_sync_dockerman_nftables_compat >/dev/null 2>&1; then
            docker_stack_sync_dockerman_nftables_compat "$BUILD_DIR" "0" || return 1
        fi

        echo "dockerman 更新完成"
    fi
}

add_quickfile() {
    local repo_url="https://github.com/sbwml/luci-app-quickfile.git"
    local target_dir="$BUILD_DIR/package/emortal/quickfile"
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi
    echo "正在添加 luci-app-quickfile..."
    if ! git clone --depth 1 "$repo_url" "$target_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-quickfile 仓库失败" >&2
        exit 1
    fi

    local makefile_path="$target_dir/quickfile/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i '/\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-\$(ARCH_PACKAGES)/c\
\tif [ "\$(ARCH_PACKAGES)" = "x86_64" ]; then \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-x86_64 \$(1)\/usr\/bin\/quickfile; \\\
\telse \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-aarch64_generic \$(1)\/usr\/bin\/quickfile; \\\
\tfi' "$makefile_path"
    fi
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

# 修复 kernel 6.18 上 kmod-iptables 与 kmod-nf-ipt 文件冲突
# 根因：上游 commit 94c7f4a 给 kmod-iptables 添加了显式 FILES 列表
# （ip_tables.ko, x_tables.ko），而这些文件 kmod-nf-ipt 也提供。
# 修复方案（上游 PR #23631）：从 kmod-iptables 的 FILES 中删除冲突文件，
# 让 kmod-nf-ipt 作为唯一提供者。
fix_netfilter_kmod_clash() {
    local netfilter_mk="$BUILD_DIR/package/kernel/linux/modules/netfilter.mk"

    if [ ! -f "$netfilter_mk" ]; then
        echo "fix_netfilter_kmod_clash: netfilter.mk 不存在，跳过"
        return 0
    fi

    if ! grep -q 'ip_tables.ko' "$netfilter_mk"; then
        echo "fix_netfilter_kmod_clash: 已修复，跳过"
        return 0
    fi

    echo "正在修复 kmod-iptables 与 kmod-nf-ipt 文件冲突..."

    # 在 KernelPackage/iptables 块内：
    # 删除 ip_tables.ko 和 x_tables.ko 行，将 FILES:= \ 改为 FILES:=
    sed -i '/^  DEPENDS:=@!LINUX_6_12$/,/AUTOLOAD:=\$(call AutoProbe,\$(notdir ip_tables x_tables))$/{
        /ip_tables.ko/d
        /x_tables.ko/d
        s/^  FILES:= \\$/  FILES:=/
    }' "$netfilter_mk"

    if grep -q 'ip_tables.ko' "$netfilter_mk"; then
        echo "错误：修复 netfilter.mk 失败，ip_tables.ko 仍然存在" >&2
        return 1
    fi

    echo "kmod-iptables FILES 已清空，kmod-nf-ipt 将作为 ip_tables.ko / x_tables.ko 的唯一提供者"
}
