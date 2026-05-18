#!/usr/bin/env bash

fix_default_set() {
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    install -Dm544 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"
    install -Dm544 "$BASE_PATH/patches/993_ddns-go-config" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/993_ddns-go-config"

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"

    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}

change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

fix_kconfig_recursive_dependency() {
    local file="$BUILD_DIR/scripts/package-metadata.pl"
    if [ -f "$file" ]; then
        sed -i 's/<PACKAGE_\$pkgname/!=y/g' "$file"
        echo "已修复 package-metadata.pl 的 Kconfig 递归依赖生成逻辑。"
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f "$CFG_PATH" ]; then
        sed -i "s/192\.168\.[0-9]*\.[0-9]*/${LAN_ADDR}/g" "$CFG_PATH"
    fi
}

remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")

    for target_mk in "${target_mks[@]}"; do
        if [ -f "$target_mk" ]; then
            sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"
        fi
    done

    if [ -f "$ipq_mk_path" ]; then
        sed -i '/kmod-qca-nss-drv-eogremgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-gre/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-map-t/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-match/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-mirror/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tun6rd/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tunipip6/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-macsec/d' "$ipq_mk_path"

        sed -i 's/automount //g' "$ipq_mk_path"
        sed -i 's/cpufreq //g' "$ipq_mk_path"
    fi
}

update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}

fix_hash_value() {
    local makefile_path="$1"
    local old_hash="$2"
    local new_hash="$3"
    local package_name="$4"

    if [ -f "$makefile_path" ]; then
        sed -i "s/$old_hash/$new_hash/g" "$makefile_path"
        echo "已修正 $package_name 的哈希值。"
    fi
}

apply_hash_fixes() {
    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "860a816bf1e69d5a8a2049483197dbebe8a3da2c9b05b2da68c85ef7dee7bdde" \
        "582021891808442b01f551bc41d7d95c38fb00c1ec78a58ac3aaaf898fbd2b5b" \
        "smartdns"

    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "320c99a65ca67a98d11a45292aa99b8904b5ebae5b0e17b302932076bf62b1ec" \
        "43e58467690476a77ce644f9dc246e8a481353160644203a1bd01eb09c881275" \
        "smartdns"
}

update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local local_mk="$BASE_PATH/patches/ath11k_fw.mk"
    local url="https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile"

    if [ ! -d "$(dirname "$makefile")" ]; then
        echo "ath11k-firmware 目录不存在，非 ipq60xx 目标，跳过更新" >&2
        return 0
    fi

    echo "正在更新 ath11k-firmware Makefile..."

    local tmp_mk
    tmp_mk=$(mktemp) || { echo "错误：无法创建临时文件" >&2; exit 1; }

    # Download upstream Makefile; fall back to local copy on failure
    if ! curl -fsSL --connect-timeout 15 --max-time 30 -o "$tmp_mk" "$url"; then
        echo "警告：从 $url 下载失败，使用本地 ath11k-firmware Makefile" >&2
        rm -f "$tmp_mk"
        if [ -f "$local_mk" ]; then
            cp -f "$local_mk" "$makefile"
            return 0
        fi
        echo "错误：无法从远程下载，本地备用文件也不存在" >&2
        exit 1
    fi

    if [ ! -s "$tmp_mk" ]; then
        echo "警告：下载的 ath11k-firmware Makefile 为空，使用本地备用文件" >&2
        rm -f "$tmp_mk"
        if [ -f "$local_mk" ]; then
            cp -f "$local_mk" "$makefile"
            return 0
        fi
        echo "错误：下载的文件为空，本地备用文件也不存在" >&2
        exit 1
    fi

    # Validate: the downloaded Makefile must have a PKG_MIRROR_HASH line
    if ! grep -q '^PKG_MIRROR_HASH:=' "$tmp_mk"; then
        echo "警告：下载的 Makefile 缺少 PKG_MIRROR_HASH，使用本地备用文件" >&2
        rm -f "$tmp_mk"
        if [ -f "$local_mk" ]; then
            cp -f "$local_mk" "$makefile"
            return 0
        fi
        echo "错误：下载的文件格式无效，本地备用文件也不存在" >&2
        exit 1
    fi

    mv -f "$tmp_mk" "$makefile"
    rm -f "$tmp_mk"
}

fix_mkpkg_format_invalid() {
    local custom_feed_worktree_dir
    custom_feed_worktree_dir=$(get_custom_feed_worktree_dir)

    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f "$custom_feed_worktree_dir/v2ray-geodata/Makefile" ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' "$custom_feed_worktree_dir/v2ray-geodata/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-lib-taskd/Makefile" ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' "$custom_feed_worktree_dir/luci-lib-taskd/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-openclash/Makefile" ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-openclash/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-quickstart/Makefile" ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' "$custom_feed_worktree_dir/luci-app-quickstart/Makefile"
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-quickstart/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-store/Makefile" ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' "$custom_feed_worktree_dir/luci-app-store/Makefile"
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-store/Makefile"
        fi
    fi
}

change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local qualcommax_sbin_dir="$BUILD_DIR/target/linux/qualcommax/base-files/sbin"
    local filogic_sbin_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin"

    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
    fi

    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
    fi

    if [ -d "$BUILD_DIR/target/linux/qualcommax" ]; then
        install -Dm755 "$BASE_PATH/patches/cpuusage" "$qualcommax_sbin_dir/cpuusage"
    fi
    if [ -d "$BUILD_DIR/target/linux/mediatek" ]; then
        install -Dm755 "$BASE_PATH/patches/hnatusage" "$filogic_sbin_dir/cpuusage"
    fi
}

update_tcping() {
    local tcping_path="$(get_custom_feed_worktree_dir)/tcping/Makefile"
    local url="https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/refs/heads/main/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ]; then
        echo "正在更新 tcping Makefile..."
        if ! curl -fsSL -o "$tcping_path" "$url"; then
            echo "错误：从 $url 下载 tcping Makefile 失败" >&2
            exit 1
        fi
    fi
}

fix_gettext_full_csharp() {
    # gettext-full host 编译不需要 C# binding。部分版本的 gettext
    # 会进入 gettext-runtime/intl-csharp 并调用 csharpcomp.sh；CI 未安装 Mono 时会报：
    # "C# compiler not found, try installing mono, then reconfigure"。
    # 这里直接从 PKG_SUBDIRS 中移除 intl-csharp，并添加 --disable-csharp，避免依赖 Mono。
    # 不硬编码分支名，改为检测 Makefile 是否实际包含 intl-csharp。

    local gettext_mk="$BUILD_DIR/package/libs/gettext-full/Makefile"
    local tmp_mk="/tmp/gettext-full-Makefile-$$.mk"

    if [ ! -f "$gettext_mk" ]; then
        echo "gettext-full Makefile 不存在，跳过 C# binding 修复: $gettext_mk"
        return 0
    fi

    if ! grep -q '^[[:space:]]*intl-csharp[[:space:]]*\\[[:space:]]*$' "$gettext_mk"; then
        echo "gettext-full Makefile 不含 intl-csharp，无需修复"
        return 0
    fi

    local add_disable_csharp=1
    if grep -q -- '--disable-csharp' "$gettext_mk"; then
        add_disable_csharp=0
    fi

    awk -v add_disable_csharp="$add_disable_csharp" '
    /^[[:space:]]*intl-csharp[[:space:]]*\\[[:space:]]*$/ {
        next
    }

    /^CONFIGURE_ARGS[[:space:]]*\+=/ {
        in_configure = 1
        in_host_configure = 0
    }

    /^HOST_CONFIGURE_ARGS[[:space:]]*\+=/ {
        in_configure = 0
        in_host_configure = 1
    }

    {
        print

        if (add_disable_csharp == 1 && in_configure && !configure_added && $0 ~ /^[[:space:]]*--disable-java[[:space:]]*\\[[:space:]]*$/) {
            print "\t--disable-csharp \\"
            configure_added = 1
        }

        if (add_disable_csharp == 1 && in_host_configure && !host_added && $0 ~ /^[[:space:]]*--disable-java[[:space:]]*\\[[:space:]]*$/) {
            print "\t--disable-csharp \\"
            host_added = 1
        }

        if ($0 !~ /\\[[:space:]]*$/) {
            in_configure = 0
            in_host_configure = 0
        }
    }
    ' "$gettext_mk" > "$tmp_mk" && mv -f "$tmp_mk" "$gettext_mk"

    if grep -q '^[[:space:]]*intl-csharp[[:space:]]*\\[[:space:]]*$' "$gettext_mk"; then
        echo "错误：gettext-full Makefile 仍包含 intl-csharp，C# binding 修复失败" >&2
        return 1
    fi

    echo "已修复 gettext-full: 禁用 intl-csharp/C# binding，避免依赖 Mono"
}

update_util_linux() {
    local util_linux_dir="$BUILD_DIR/package/utils/util-linux"
    local makefile_url="https://raw.githubusercontent.com/ZqinKing/immortalwrt/master/package/utils/util-linux/Makefile"
    local tmp_makefile="/tmp/util-linux-Makefile-$$.mk"

    if [ ! -d "$util_linux_dir" ]; then
        echo "util-linux 目录不存在，跳过更新: $util_linux_dir"
        return 0
    fi

    echo "正在更新 util-linux..."

    if ! curl -fsSL -o "$tmp_makefile" "$makefile_url"; then
        echo "错误：从 $makefile_url 下载 util-linux Makefile 失败" >&2
        rm -f "$tmp_makefile"
        return 1
    fi

    local ver
    ver=$(grep -m1 "^PKG_VERSION" "$tmp_makefile" 2>/dev/null | sed 's/.*:=//' | tr -d ' ')
    if [ "$ver" != "2.41.1" ]; then
        echo "错误：ZqinKing 的 util-linux 版本已是 $ver（不是预期的 2.41.1），AT_HANDLE_FID 问题可能仍存在，停止更新。" >&2
        echo "提示：请确认 ZqinKing 是否已同步上游，或手动检查 https://github.com/ZqinKing/immortalwrt/commits/master/package/utils/util-linux" >&2
        rm -f "$tmp_makefile"
        exit 1
    fi

    mv -f "$tmp_makefile" "$util_linux_dir/Makefile"

    local patches_dir="$util_linux_dir/patches"
    if [ -d "$patches_dir" ]; then
        local zqin_patches_url="https://api.github.com/repos/ZqinKing/immortalwrt/contents/package/utils/util-linux/patches?ref=master"
        if curl -fsSL "$zqin_patches_url" >/dev/null 2>&1; then
            echo "正在更新 util-linux patches..."
            find "$patches_dir" -maxdepth 1 -type f -name "[0-9][0-9][0-9]-*.patch" -exec rm -f {} \; 2>/dev/null || true
        fi
    fi

    echo "util-linux 已更新到 ZqinKing 版本 ($ver)"
}

set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
START=99

boot() {
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

apply_passwall_tweaks() {
    local chnlist_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi

    local xray_util_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    local ver_file="$BUILD_DIR/include/version.mk"

    local version_number
    # VERSION_NUMBER 有两行：第1行是 $(call qstrip,...) 模板，第2行 $(if ...,fallback)
    # 需要取 fallback 值（如 24.10.6），不是模板
    # ipq60xx 用 SNAPSHOT：24.10.6 → 24.10-SNAPSHOT，25.12.0-rc1 → 25.12-SNAPSHOT
    local raw_version
    raw_version=$(sed -n 's/.*VERSION_NUMBER.*,\([0-9][0-9.]*\))$/\1/p' "$ver_file" | head -1)
    version_number=$(echo "$raw_version" | sed 's/^\([0-9]*\.[0-9]*\).*/\1-SNAPSHOT/')

    local arch="aarch64_cortex-a53"

    if [ -d "$emortal_def_dir" ]; then
        # 始终覆盖 distfeeds.conf，确保 URL 最新
        cat >"$distfeeds_conf" <<EOF
src/gz openwrt_base https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/telephony/
EOF

        # 仅在首次注入 install 规则和 uci-defaults mv 命令
        if ! grep -q '99-distfeeds.conf' "$emortal_def_dir/Makefile" 2>/dev/null; then
            sed -i "/define Package\/default-settings\/install/a\\
\t\$(INSTALL_DIR) \$(1)/etc\\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

            sed -i "/exit 0/i\\
[ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\\
sed -ri '/check_signature/s@^[^#]@#&@' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
        fi

        echo "[opkg] 99-distfeeds.conf 已生成：${version_number} (arch: ${arch}, raw: ${raw_version})"
    fi

    # 修复 ImmortalWrt build system 生成的 distfeeds 模板中未展开的变量
    # find 范围覆盖 package/ include/ scripts/ feeds/ — 模板可能在 feeds 中
    if [ -n "$version_number" ]; then
        local fixed=0
        while IFS= read -r -d '' f; do
            sed -i 's|$(call qstrip,$(CONFIG_VERSION_NUMBER))|'"${version_number}"'|g' "$f"
            sed -i "s|mirrors.vsean.net/openwrt|downloads.immortalwrt.org|g" "$f"
            fixed=1
        done < <(find "$BUILD_DIR/package" "$BUILD_DIR/include" "$BUILD_DIR/scripts" "$BUILD_DIR/feeds" \
            -type f \( -name '*.conf' -o -name '*.mk' -o -name 'Makefile' -o -name '*.sh' \) \
            -exec grep -l 'qstrip.*CONFIG_VERSION_NUMBER\|mirrors\.vsean\.net' {} \; 2>/dev/null | sort -u | tr '\n' '\0')

        if [ "$fixed" = "1" ]; then
            echo "[opkg] distfeeds 模板已修复：${version_number} (arch: ${arch})"
        fi
    fi

    # 修复 99-default-settings-chinese 中的 opkg/apk mirror 默认值
    # 该文件没有扩展名，上面的 find *.conf|*.mk|*.sh 匹配不到
    local chn_settings="$emortal_def_dir/files/99-default-settings-chinese"
    if [ -f "$chn_settings" ]; then
        sed -i 's|https://mirrors\.vsean\.net/openwrt|https://downloads.immortalwrt.org|g' "$chn_settings"
        echo "[mirror] 99-default-settings-chinese 镜像已改为官方"
    fi
}

update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by Alex')/g" "$file"
    fi
}

update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$(get_custom_feed_worktree_dir)/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi

    # 代理类应用 services → vpn（JSON menu.d / controller lua 两种方式）
    local proxy_apps="passwall passwall2 homeproxy openclash momo nikki"
    local app_feed="$(get_custom_feed_source_dir)"
    local app
    for app in $proxy_apps; do
        local json_dir="$app_feed/luci-app-$app/root/usr/share/luci/menu.d"
        if [ -d "$json_dir" ]; then
            find "$json_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/vpn/|g' {} \;
            echo "[menu] $app: services -> vpn — $json_dir"
        fi

        local ctrl_file="$app_feed/luci-app-$app/luasrc/controller/$app.lua"
        if [ -f "$ctrl_file" ]; then
            sed -i \
                -e 's/"admin", "services", appname/"admin", "vpn", appname/g' \
                -e "s/\"admin\", \"services\", \"$app\"/\"admin\", \"vpn\", \"$app\"/g" \
                "$ctrl_file"
            grep -q '"admin", "vpn"' "$ctrl_file" 2>/dev/null \
                && echo "[menu] $app: services -> vpn — $ctrl_file" \
                || echo "[menu] $app: WARNING sed unmatched — $ctrl_file"
        fi
    done

    # PBR (策略路由) 移到"网络"菜单
    local pbr_menu_dirs
    pbr_menu_dirs=$(find "$BUILD_DIR/feeds/" -maxdepth 9 -type d -path "*/luci-app-pbr/root/usr/share/luci/menu.d" 2>/dev/null)
    if [ -n "$pbr_menu_dirs" ]; then
        while IFS= read -r pbr_menu_dir; do
            [ -n "$pbr_menu_dir" ] && [ -d "$pbr_menu_dir" ] || continue
            find "$pbr_menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/network/|g' {} \;
            echo "[menu] pbr: services -> network — $pbr_menu_dir"
        done <<< "$pbr_menu_dirs"
    fi

    # WOL (网络唤醒) 移到"网络"菜单
    local wol_menu_dirs
    wol_menu_dirs=$(find "$BUILD_DIR/feeds/" -maxdepth 9 -type d -path "*/luci-app-wol/root/usr/share/luci/menu.d" 2>/dev/null)
    if [ -n "$wol_menu_dirs" ]; then
        while IFS= read -r wol_menu_dir; do
            [ -n "$wol_menu_dir" ] && [ -d "$wol_menu_dir" ] || continue
            find "$wol_menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/network/|g' {} \;
            echo "[menu] wol: services -> network — $wol_menu_dir"
        done <<< "$wol_menu_dirs"
    fi

    # Bandix 移到"状态"菜单，排在 WireGuard 下面 (order=8)
    local bandix_json_dir="$(get_custom_feed_source_dir)/luci-app-bandix/root/usr/share/luci/menu.d"
    if [ -d "$bandix_json_dir" ]; then
        find "$bandix_json_dir" -maxdepth 1 -name '*.json' \
            -exec sed -i 's|"admin/network/bandix|"admin/status/bandix|g' {} \;
        # WireGuard 在状态菜单的 order 通常是 4，bandix 设 8 排在它下面
        local bandix_json
        bandix_json=$(find "$bandix_json_dir" -maxdepth 1 -name '*.json' | head -1)
        if [ -n "$bandix_json" ] && [ -f "$bandix_json" ]; then
            sed -i 's/"order": 90/"order": 8/' "$bandix_json"
        fi
        echo "[menu] bandix: network -> status (order=8) — $bandix_json_dir"
    fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

update_script_priority() {
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    local mosdns_path="$(get_custom_feed_package_dir)/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$(get_custom_feed_worktree_dir)/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

fix_quickstart() {
    local file_path="$(get_custom_feed_worktree_dir)/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    local url="https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua"
    if [ -f "$file_path" ]; then
        echo "正在修复 quickstart..."
        if ! curl -fsSL -o "$file_path" "$url"; then
            echo "错误：从 $url 下载 istore_backend.lua 失败" >&2
            exit 1
        fi
    fi
}

update_oaf_deconfig() {
    # pitfall: ext4 readdir 非字母序 + maxdepth 不够深 → 改为遍历所有匹配项 + maxdepth 8
    local appfilter_confs
    appfilter_confs=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type f -path '*/open-app-filter/files/appfilter.config' 2>/dev/null)
    local uci_defs
    uci_defs=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type f -path '*/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0' 2>/dev/null)
    local disable_dirs
    disable_dirs=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type d -path '*/luci-app-oaf/root/etc/uci-defaults' 2>/dev/null)

    # 修改 appfilter.config
    if [ -n "$appfilter_confs" ]; then
        while IFS= read -r appfilter_conf; do
            [ -n "$appfilter_conf" ] && [ -f "$appfilter_conf" ] || continue
            sed -i -e "s/record_enable '1'/record_enable '0'/g" \
                   -e "s/auto_load_engine '[01]'/auto_load_engine '0'/g" "$appfilter_conf"
            echo "[OAF] auto_load_engine=0, record_enable=0 — $appfilter_conf"
        done <<< "$appfilter_confs"
    fi

    # 修改 94_feature_3.0，删除 disable_hnat 和 auto_load_engine，防止首次启动覆盖配置
    if [ -n "$uci_defs" ]; then
        while IFS= read -r uci_def; do
            [ -n "$uci_def" ] && [ -f "$uci_def" ] || continue
            if grep -q 'disable_hnat\|auto_load_engine' "$uci_def" 2>/dev/null; then
                sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"
                echo "[OAF] uci_def: removed disable_hnat + auto_load_engine — $uci_def"
            else
                echo "[OAF] uci_def: already clean — $uci_def"
            fi
        done <<< "$uci_defs"
    fi

    # 创建 99_disable_oaf
    if [ -n "$disable_dirs" ]; then
        while IFS= read -r disable_dir; do
            [ -n "$disable_dir" ] && [ -d "$disable_dir" ] || continue
            local disable_path="$disable_dir/99_disable_oaf"
            cat >"$disable_path" <<-'EOF'
#!/bin/sh
[ "$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
            chmod +x "$disable_path"
            echo "[OAF] 99_disable_oaf created — $disable_path"
        done <<< "$disable_dirs"
    fi
}

update_geoip() {
    local geodata_path="$(get_custom_feed_package_dir)/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            local old_SHA256
            if ! old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip.dat.sha256sum 获取旧的 geoip.dat 校验和失败" >&2
                return 1
            fi
            local new_SHA256
            if ! new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip-only-cn-private.dat.sha256sum 获取新的 geoip-only-cn-private.dat 校验和失败" >&2
                return 1
            fi
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}

fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}

fix_easytier_lua() {
    local file_path="$(get_custom_feed_package_dir)/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then
        sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"
    fi
}

fix_easytier_mk() {
    local mk_path="$(get_custom_feed_worktree_dir)/luci-app-easytier/easytier/Makefile"
    if [ -f "$mk_path" ]; then
        sed -i 's/!@(mips||mipsel)/!TARGET_mips \&\& !TARGET_mipsel/g' "$mk_path"
    fi
}

update_nginx_ubus_module() {
    local makefile_path="$BUILD_DIR/feeds/packages/net/nginx/Makefile"
    local source_date="2024-03-02"
    local source_version="564fa3e9c2b04ea298ea659b793480415da26415"
    local mirror_hash="92c9ab94d88a2fe8d7d1e8a15d15cfc4d529fdc357ed96d22b65d5da3dd24d7f"

    if [ -f "$makefile_path" ]; then
        sed -i "s/SOURCE_DATE:=2020-09-06/SOURCE_DATE:=$source_date/g" "$makefile_path"
        sed -i "s/SOURCE_VERSION:=b2d7260dcb428b2fb65540edb28d7538602b4a26/SOURCE_VERSION:=$source_version/g" "$makefile_path"
        sed -i "s/MIRROR_HASH:=515bb9d355ad80916f594046a45c190a68fb6554d6795a54ca15cab8bdd12fda/MIRROR_HASH:=$mirror_hash/g" "$makefile_path"
        echo "已更新 nginx-mod-ubus 模块的 SOURCE_DATE, SOURCE_VERSION 和 MIRROR_HASH。"
    else
        echo "错误：未找到 $makefile_path 文件，无法更新 nginx-mod-ubus 模块。" >&2
    fi
}

fix_openssl_ktls() {
    local config_in="$BUILD_DIR/package/libs/openssl/Config.in"
    if [ -f "$config_in" ]; then
        echo "正在更新 OpenSSL kTLS 配置..."
        sed -i 's/select PACKAGE_kmod-tls/depends on PACKAGE_kmod-tls/g' "$config_in"
        sed -i '/depends on PACKAGE_kmod-tls/a\\tdefault y if PACKAGE_kmod-tls' "$config_in"
    fi
}

fix_opkg_check() {
    local patch_file="$BASE_PATH/patches/001-fix-provides-version-parsing.patch"
    local opkg_dir="$BUILD_DIR/package/system/opkg"
    if [ -f "$patch_file" ]; then
        install -Dm644 "$patch_file" "$opkg_dir/patches/001-fix-provides-version-parsing.patch"
    fi
}

fix_netfilter_kmod_clash() {
    # OpenWrt issue #22992: kmod-nf-ipt and kmod-iptables both ship
    # ip_tables.ko / x_tables.ko on kernel 6.18+, causing file clash.
    #
    # Upstream fix (dqsq2e2): keep kmod-iptables as the owner of those
    # .ko files, and filter them out of kmod-nf-ipt's FILES/AUTOLOAD.
    # DEPENDS must remain +!LINUX_6_12:kmod-iptables so that kmod-nf-ipt
    # depends on kmod-iptables (which enables CONFIG_IP_NF_IPTABLES_LEGACY
    # in the kernel, actually building ip_tables.ko).
    #
    # Previous AWRT workaround changed DEPENDS to exclude LINUX_6_18 as
    # well — this prevented the file clash but also prevented ip_tables.ko
    # from being built at all, causing "module ip_tables.ko missing" errors.

    local netfilter_mk="$BUILD_DIR/package/kernel/linux/modules/netfilter.mk"

    if [ ! -f "$netfilter_mk" ]; then
        echo "Netfilter makefile not found: $netfilter_mk" >&2
        return 1
    fi

    # kernel 6.6 (openwrt-24.10) — no kmod-iptables version gate at all,
    # iptables/nf_tables coexist without conflict, nothing to do
    if ! grep -q 'kmod-iptables' "$netfilter_mk"; then
        echo "Netfilter kmod clash workaround not applicable (no kmod-iptables gate found)"
        return 0
    fi

    # Idempotent guard: filter-out already applied
    if grep -q 'filter-out ipv4/netfilter/ip_tables netfilter/x_tables' "$netfilter_mk"; then
        echo "Netfilter kmod filter-out workaround already applied"
        return 0
    fi

    # Step 1: Revert any stale AWRT-style DEPENDS mangling back to upstream
    # Old AWRT: +(!(LINUX_6_12||LINUX_6_18)):kmod-iptables — BROKEN on 6.18
    # Upstream: +!LINUX_6_12:kmod-iptables — correct; kmod-iptables owns ip_tables.ko
    local depends_line
    depends_line=$(grep 'DEPENDS:=+.*:kmod-iptables' "$netfilter_mk" | head -1)
    if echo "$depends_line" | grep -q '(LINUX_6_12.*LINUX_6_18)'; then
        echo "Reverting AWRT netfilter DEPENDS to upstream form..."
        sed -i '/^define KernelPackage\/nf-ipt$/,/^endef$/{
            s/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/DEPENDS:=+!LINUX_6_12:kmod-iptables/
            s/DEPENDS:=+(!LINUX_6_12&&!LINUX_6_18):kmod-iptables/DEPENDS:=+!LINUX_6_12:kmod-iptables/
        }' "$netfilter_mk"
    fi

    # Step 2: Apply filter-out to FILES and AUTOLOAD inside KernelPackage/nf-ipt
    # Removes ip_tables.ko / x_tables.ko from kmod-nf-ipt so kmod-iptables
    # is the sole owner — no file clash at opkg install time.
    echo "Applying netfilter kmod filter-out workaround (upstream openwrt#22992)..."
    sed -i '/^define KernelPackage\/nf-ipt$/,/^endef$/{
        s|FILES:=\$(foreach mod,\$(NF_IPT-m),\$(LINUX_DIR)/net/\$(mod)\.ko)|FILES:=\$(foreach mod,\$(filter-out ipv4/netfilter/ip_tables netfilter/x_tables,\$(NF_IPT-m)),\$(LINUX_DIR)/net/\$(mod).ko)|
        s|AUTOLOAD:=\$(call AutoProbe,\$(notdir \$(NF_IPT-m)))|AUTOLOAD:=\$(call AutoProbe,\$(notdir \$(filter-out ipv4/netfilter/ip_tables netfilter/x_tables,\$(NF_IPT-m))))|
    }' "$netfilter_mk"

    return 0
}

install_pbr_isp() {
    local isp_lower="$1"
    local isp_upper="$2"

    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"
    local tmp_rules

    if [ ! -d "$pbr_pkg_dir" ]; then
        echo "错误：PBR 包目录不存在: $pbr_pkg_dir" >&2
        return 1
    fi

    echo "正在安装 PBR $isp_upper 配置文件..."
    install -Dm644 "$BASE_PATH/patches/pbr.user.${isp_lower}" "$pbr_dir/pbr.user.${isp_lower}"
    install -Dm644 "$BASE_PATH/patches/pbr.user.${isp_lower}6" "$pbr_dir/pbr.user.${isp_lower}6"

    if [ -f "$pbr_makefile" ] && ! grep -q "pbr.user.${isp_lower}" "$pbr_makefile"; then
        echo "正在修改 PBR Makefile 添加 $isp_upper 安装规则..."
        tmp_rules=$(mktemp)
        printf '\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.%s $(1)/usr/share/pbr/pbr.user.%s\n' \
            "$isp_lower" "$isp_lower" > "$tmp_rules"
        printf '\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.%s6 $(1)/usr/share/pbr/pbr.user.%s6\n' \
            "$isp_lower" "$isp_lower" >> "$tmp_rules"
        sed -i "/pbr\.user\.netflix.*\$(1)/r $tmp_rules" "$pbr_makefile"
        rm -f "$tmp_rules"
    fi

    if [ -f "$pbr_conf" ] && ! grep -q "pbr.user.${isp_lower}" "$pbr_conf"; then
        echo "正在添加 PBR $isp_upper 配置条目..."
        tmp_rules=$(mktemp)
        cat > "$tmp_rules" << PBRCONFEOF

config include
	option path '/usr/share/pbr/pbr.user.${isp_lower}'
	option enabled '0'

config include
	option path '/usr/share/pbr/pbr.user.${isp_lower}6'
	option enabled '0'
PBRCONFEOF
        sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
/option enabled '0'/r $tmp_rules
}" "$pbr_conf"
        rm -f "$tmp_rules"
    fi
}

install_pbr_cmcc() { install_pbr_isp "cmcc" "CMCC"; }
install_pbr_ctcc() { install_pbr_isp "ctcc" "CTCC"; }
install_pbr_cucc() { install_pbr_isp "cucc" "CUCC"; }
fix_pbr_ip_forward() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_init_script="$pbr_pkg_dir/files/etc/init.d/pbr"

    if [ ! -d "$pbr_pkg_dir" ]; then
        echo "PBR package directory not found: $pbr_pkg_dir"
        return 1
    fi

    if [ ! -f "$pbr_init_script" ]; then
        echo "PBR init script not found: $pbr_init_script"
        return 1
    fi

    if grep -q '\[ -n "$enabled" \] && \[ -n "$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward fix already applied"
        return 0
    fi

    if ! grep -q '\[ -n "$strict_enforcement" \] && \[ "$(cat /proc/sys/net/ipv4/ip_forward)"' "$pbr_init_script"; then
        echo "PBR IP Forward: 未找到需要修复的代码，可能上游已修复或此版本无此问题"
        return 0
    fi

    echo "正在应用 PBR IP Forward 修复..."
    sed -i 's/\[ -n "\$strict_enforcement" \] && \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/\[ -n "\$enabled" \] \&\& \[ -n "\$strict_enforcement" \] \&\& \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/' "$pbr_init_script"
    
    if grep -q '\[ -n "$enabled" \] && \[ -n "$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward 修复应用成功"
        return 0
    else
        echo "修复应用失败：未找到预期的修复内容"
        return 1
    fi
}

fix_quectel_cm() {
    local makefile_path="$BUILD_DIR/package/feeds/packages/quectel-cm/Makefile"
    local cmake_patch_path="$BUILD_DIR/package/feeds/packages/quectel-cm/patches/020-cmake.patch"

    if [ -f "$makefile_path" ]; then
        echo "正在修复 quectel-cm Makefile..."

        sed -i '/^PKG_SOURCE:=/d' "$makefile_path"
        sed -i '/^PKG_SOURCE_URL:=@IMMORTALWRT/d' "$makefile_path"
        sed -i '/^PKG_HASH:=/d' "$makefile_path"

        sed -i '/^PKG_RELEASE:=/a\
\
PKG_SOURCE_PROTO:=git\
PKG_SOURCE_URL:=https://github.com/Carton32/quectel-CM.git\
PKG_SOURCE_VERSION:=$(PKG_VERSION)\
PKG_MIRROR_HASH:=skip' "$makefile_path"

        sed -i 's/^PKG_RELEASE:=2$/PKG_RELEASE:=3/' "$makefile_path"

        echo "quectel-cm Makefile 修复完成。"
    fi

    if [ -f "$cmake_patch_path" ]; then
        sed -i 's/-cmake_minimum_required(VERSION 2\.4)$/-cmake_minimum_required(VERSION 2.4) /' "$cmake_patch_path"
        sed -i 's/project(quectel-CM)$/project(quectel-CM) /' "$cmake_patch_path"
    fi
}

set_nginx_default_config() {
    local nginx_config_path="$BUILD_DIR/feeds/packages/net/nginx-util/files/nginx.config"
    if [ -f "$nginx_config_path" ]; then
        cat >"$nginx_config_path" <<EOF
config main 'global'
        option uci_enable 'true'

config server '_lan'
        list listen '443 ssl default_server'
        list listen '[::]:443 ssl default_server'
        option server_name '_lan'
        list include 'restrict_locally'
        list include 'conf.d/*.locations'
        option uci_manage_ssl 'self-signed'
        option ssl_certificate '/etc/nginx/conf.d/_lan.crt'
        option ssl_certificate_key '/etc/nginx/conf.d/_lan.key'
        option ssl_session_cache 'shared:SSL:32k'
        option ssl_session_timeout '64m'
        option access_log 'off; # logd openwrt'

config server 'http_only'
        list listen '80'
        list listen '[::]:80'
        option server_name 'http_only'
        list include 'conf.d/*.locations'
        option access_log 'off; # logd openwrt'
EOF
    fi

    local nginx_template="$BUILD_DIR/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [ -f "$nginx_template" ]; then
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            sed -i "/client_max_body_size 128M;/a\\
\tclient_body_in_file_only clean;\\
\tclient_body_temp_path /mnt/tmp;" "$nginx_template"
        fi
    fi

    local luci_support_script="$BUILD_DIR/feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support"

    if [ -f "$luci_support_script" ]; then
        if ! grep -q "client_body_in_file_only off;" "$luci_support_script"; then
            echo "正在为 Nginx ubus location 配置应用修复..."
            sed -i "/ubus_parallel_req 2;/a\\        client_body_in_file_only off;\\n        client_max_body_size 1M;" "$luci_support_script"
        fi
    fi
}

update_uwsgi_limit_as() {
    local cgi_io_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"

    if [ -f "$cgi_io_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$cgi_io_ini"
    fi

    if [ -f "$webui_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$webui_ini"
    fi
}

remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}

enable_ttyd_autologin() {
    local ttyd_cfg="$BUILD_DIR/package/feeds/packages/ttyd/files/ttyd.config"
    if [ -f "$ttyd_cfg" ]; then
        sed -i 's|/bin/login|/usr/libexec/login.sh|g' "$ttyd_cfg"
        sed -i '/option interface/d' "$ttyd_cfg"
        echo "[ttyd] 自动登录 + 监听所有接口"
    fi
}

fix_nikki_gobinpackage() {
    # nikki 是纯配置/UI 元包（meta-package），不含 Go 源码也不应编译。
    # mihomo 二进制由独立的 mihomo 包（GoBinPackage）编译并提供。
    #
    # 问题：golang-package.mk 第 293-301 行检测到 GO_PKG 非空后，
    # 全局挂载了 Build/InstallDev=$(call GoPackage/Build/InstallDev)，而
    # GoPackage/Build/InstallDev 内部调用 install_src，需要复制源码到
    # .go_work/build/src/ 目录。但 nikki 没有 Go 源码（build_dir 为空），
    # golang-build.sh configure 阶段不会创建该目录，导致 install_src 失败。
    #
    # nikki 的 Build/Compile 已定义为空（正确阻止编译），
    # 但 Build/InstallDev 未在 Makefile 中定义，继承了全局挂载。
    #
    # 修复方法：在 $(eval ...) 调用前追加空的 Build/InstallDev，
    # 覆盖 golang-package.mk 的全局挂载。不改变 GoBinPackage/GoPackage 类型，
    # 不改变 Build/Compile。
    local nikki_makefile="$(get_custom_feed_package_dir)/nikki/Makefile"
    if [ -f "$nikki_makefile" ]; then
        if ! grep -q '^define Build/InstallDev$' "$nikki_makefile"; then
            # 在 $(eval $(call GoBinPackage,nikki)) 或 $(eval $(call GoPackage,nikki)) 之前插入
            awk '
            /^\$\(eval \$\(call Go(Bin)?Package,nikki\)\)/ {
                print "define Build/InstallDev"
                print "endef"
                print ""
            }
            { print }
            ' "$nikki_makefile" > "$nikki_makefile.tmp" && mv "$nikki_makefile.tmp" "$nikki_makefile"
            echo "[nikki] Build/InstallDev 置空（覆盖 golang-package.mk 全局挂载）"
        else
            echo "[nikki] Build/InstallDev 已存在，跳过"
        fi
    fi
}

fix_tuic_downgrade() {
    # ImmortalWrt 24.10 使用 Rust 1.90 stable，main 分支自编译 Rust 1.94。
    # tuic-client v1.8.0+ 使用 if-let guard（稳定于 Rust 1.95），均无法编译。
    # v1.7.2 不含此特性，可正常编译。此处将版本回退到 1.7.2。
    # custom_feed 的 PKG_HASH:=skip，因此只改版本号无需更新 hash。
    # 适用：x86_64 (24.10/Rust 1.90) + ipq60xx ARM64 (main/Rust 1.94)
    local tuic_mk="$(get_custom_feed_package_dir)/tuic-client/Makefile"
    [ -f "$tuic_mk" ] || return 0

    local current_ver
    current_ver=$(grep -oP '^PKG_VERSION:=\K[0-9.]+' "$tuic_mk" 2>/dev/null)

    case "$current_ver" in
        1.8.[01])
            sed -i "s/PKG_VERSION:=${current_ver}/PKG_VERSION:=1.7.2/" "$tuic_mk"
            echo "[tuic-client] downgraded v${current_ver} → v1.7.2 (if-let guard needs Rust ≥1.95)"
            ;;
        *)
            return 0
            ;;
    esac
}

fix_bandix_default_enabled() {
    # openwrt-bandix 只在 openwrt_bandix feed 下（luci_app_bandix feed 只含 luci-app-bandix，不含 openwrt-bandix）
    local bandix_config="$(get_custom_feed_source_dir)/openwrt-bandix/files/bandix.config"
    if [ -f "$bandix_config" ]; then
        sed -i "s/option enabled '0'/option enabled '1'/g" "$bandix_config"
        echo "[bandix] traffic/connections/dns 默认已启用 ($bandix_config)"
    fi
}
