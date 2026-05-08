#!/usr/bin/env bash

fix_default_set() {
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    install -Dm544 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"

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
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
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
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"
    local url="https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile"

    if [ -d "$(dirname "$makefile")" ]; then
        echo "正在更新 ath11k-firmware Makefile..."
        if ! curl -fsSL -o "$new_mk" "$url"; then
            echo "错误：从 $url 下载 ath11k-firmware Makefile 失败" >&2
            exit 1
        fi
        if [ ! -s "$new_mk" ]; then
            echo "错误：下载的 ath11k-firmware Makefile 为空文件" >&2
            exit 1
        fi
        mv -f "$new_mk" "$makefile"
    fi
}

fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
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
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"
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
    # gettext-full host 编译不需要 C# binding。openwrt-24.10 的 gettext 0.22.5
    # 会进入 gettext-runtime/intl-csharp 并调用 csharpcomp.sh；CI 未安装 Mono 时会报：
    # "C# compiler not found, try installing mono, then reconfigure"。
    # 这里直接从 PKG_SUBDIRS 中移除 intl-csharp，并添加 --disable-csharp，避免依赖 Mono。
    if [ "${REPO_BRANCH:-}" != "openwrt-24.10" ]; then
        echo "当前分支不是 openwrt-24.10，跳过 gettext-full C# binding 修复: ${REPO_BRANCH:-unknown}"
        return 0
    fi

    local gettext_mk="$BUILD_DIR/package/libs/gettext-full/Makefile"
    local tmp_mk="/tmp/gettext-full-Makefile-$$.mk"

    if [ ! -f "$gettext_mk" ]; then
        echo "gettext-full Makefile 不存在，跳过 C# binding 修复: $gettext_mk"
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
        local patches_json
        if patches_json=$(curl -fsSL "$zqin_patches_url" 2>/dev/null); then
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
    local chnlist_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi

    local xray_util_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    local ver_file="$BUILD_DIR/include/version.mk"
    local config_file="$BUILD_DIR/.config"

    # 从 version.mk 读取 VERSION_NUMBER（如 25.12-SNAPSHOT、24.10.6）
    local version_number
    version_number=$(grep -m1 "^VERSION_NUMBER:=" "$ver_file" | sed 's/.*:=//' | tr -d ' ')

    # 从 .config 读取目标架构（仅两个选项：x86_64 或 aarch64_cortex-a53）
    local arch="aarch64_cortex-a53"
    if [ -f "$config_file" ] && grep -q "^CONFIG_TARGET_X86_64=y" "$config_file"; then
        arch="x86_64"
    fi

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat >"$distfeeds_conf" <<EOF
src/gz openwrt_base https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/${version_number}/packages/${arch}/telephony/
EOF

        sed -i "/define Package\/default-settings\/install/a\\
\t\$(INSTALL_DIR) \$(1)/etc\\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\\
sed -ri '/check_signature/s@^[^#]@#&@' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi

    # 修复 ImmortalWrt build system 生成的 distfeeds 模板中未展开的变量
    # ImmortalWrt 的 distfeeds.conf 是由 build system 动态生成的，
    # 模板里 $(call qstrip,$(CONFIG_VERSION_NUMBER)) 在某些构建路径下不会被展开
    # 直接 find + sed 暴力替换，确保无论模板在哪都会被修复
    if [ -n "$version_number" ]; then
        local fixed=0
        while IFS= read -r -d '' f; do
            sed -i "s|\$(call qstrip,\$(CONFIG_VERSION_NUMBER))|${version_number}|g" "$f"
            sed -i "s|mirrors.vsean.net/openwrt|downloads.immortalwrt.org|g" "$f"
            fixed=1
        done < <(find "$BUILD_DIR/package" "$BUILD_DIR/include" "$BUILD_DIR/scripts" \
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
        sed -i 's|https://mirrors\.vsean\.net/openwrt|https://mirrors.ustc.edu.cn/immortalwrt|g' "$chn_settings"
        echo "[mirror] 99-default-settings-chinese 镜像已改为 USTC"
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

    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi

    # 将代理类应用从"服务"移到"VPN"菜单
    local proxy_apps="passwall passwall2 homeproxy openclash momo nikki"
    local feed_dir
    for feed_dir in "$BUILD_DIR/feeds/"*/; do
        local app
        for app in $proxy_apps; do
            local menu_dir="$feed_dir/luci-app-$app/root/usr/share/luci/menu.d"
            if [ -d "$menu_dir" ]; then
                find "$menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/vpn/|g' {} \;
            fi
        done
    done

    # PBR (策略路由) 移到"网络"菜单
    for feed_dir in "$BUILD_DIR/feeds/"*/; do
        local pbr_menu_dir="$feed_dir/luci-app-pbr/root/usr/share/luci/menu.d"
        if [ -d "$pbr_menu_dir" ]; then
            find "$pbr_menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/network/|g' {} \;
        fi
    done

    # WOL (网络唤醒) 移到"网络"菜单
    for feed_dir in "$BUILD_DIR/feeds/"*/; do
        local wol_menu_dir="$feed_dir/luci-app-wol/root/usr/share/luci/menu.d"
        if [ -d "$wol_menu_dir" ]; then
            find "$wol_menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/network/|g' {} \;
        fi
    done

    # Bandix 移到"状态"菜单，排在 WireGuard 上面
    local bandix_menu_dir="$BUILD_DIR/feeds/luci_app_bandix/luci-app-bandix/root/usr/share/luci/menu.d"
    if [ -d "$bandix_menu_dir" ]; then
        find "$bandix_menu_dir" -maxdepth 1 -name '*.json' \
            -exec sed -i 's|"admin/network/bandix|"admin/status/bandix|g' {} \;
        # WireGuard 在状态菜单的 order 通常是 4，bandix 设 3 排在它上面
        local bandix_json="$bandix_menu_dir/luci-app-bandix.json"
        if [ -f "$bandix_json" ]; then
            sed -i 's/"order": 90/"order": 3/' "$bandix_json"
        fi
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

    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

fix_quickstart() {
    local file_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/luasrc/controller/istore_backend.lua"
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
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"

    # 检测目标平台
    local is_x86=0
    if [ -f "$BUILD_DIR/.config" ] && grep -q "^CONFIG_TARGET_x86_64=y" "$BUILD_DIR/.config"; then
        is_x86=1
    fi

    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            "$conf_path"

        # x86 平台: 保持 auto_load_engine='1'（自动加载驱动）
        # ARM/IPQ60xx: 设为 '0'（NSS 冲突，不自动加载）
        if [ "$is_x86" = "0" ]; then
            sed -i "s/auto_load_engine '1'/auto_load_engine '0'/g" "$conf_path"
        fi
    fi

    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        # x86: 保留 auto_load_engine，只删 disable_hnat
        # ARM: 删除 auto_load_engine 和 disable_hnat
        if [ "$is_x86" = "1" ]; then
            sed -i '/disable_hnat/d' "$uci_def"
        else
            sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"
        fi

        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

update_geoip() {
    local geodata_path="$BUILD_DIR/package/feeds/small8/v2ray-geodata/Makefile"
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
    local file_path="$BUILD_DIR/package/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then
        sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"
    fi
}

fix_easytier_mk() {
    local mk_path="$BUILD_DIR/feeds/small8/luci-app-easytier/easytier/Makefile"
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

install_pbr_cmcc() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"

    if [ -d "$pbr_pkg_dir" ]; then
        echo "正在安装 PBR CMCC 配置文件..."
        install -Dm644 "$BASE_PATH/patches/pbr.user.cmcc" "$pbr_dir/pbr.user.cmcc"
        install -Dm644 "$BASE_PATH/patches/pbr.user.cmcc6" "$pbr_dir/pbr.user.cmcc6"

        if [ -f "$pbr_makefile" ]; then
            if ! grep -q "pbr.user.cmcc" "$pbr_makefile"; then
                echo "正在修改 PBR Makefile 添加 CMCC 安装规则..."
                sed -i '/pbr\.user\.netflix.*\$(1)/a\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc $(1)/usr/share/pbr/pbr.user.cmcc\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc6 $(1)/usr/share/pbr/pbr.user.cmcc6' "$pbr_makefile"
            fi
        fi
    fi

    if [ -f "$pbr_conf" ]; then
        if ! grep -q "pbr.user.cmcc" "$pbr_conf"; then
            echo "正在添加 PBR CMCC 配置条目..."
            sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
                /option enabled '0'/a\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cmcc'\\
	option enabled '0'\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cmcc6'\\
	option enabled '0'
            }" "$pbr_conf"
        fi
    fi
}

install_pbr_ctcc() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"

    if [ -d "$pbr_pkg_dir" ]; then
        echo "正在安装 PBR CTCC 配置文件..."
        install -Dm644 "$BASE_PATH/patches/pbr.user.ctcc" "$pbr_dir/pbr.user.ctcc"
        install -Dm644 "$BASE_PATH/patches/pbr.user.ctcc6" "$pbr_dir/pbr.user.ctcc6"

        if [ -f "$pbr_makefile" ]; then
            if ! grep -q "pbr.user.ctcc" "$pbr_makefile"; then
                echo "正在修改 PBR Makefile 添加 CTCC 安装规则..."
                sed -i '/pbr\.user\.netflix.*\$(1)/a\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.ctcc $(1)/usr/share/pbr/pbr.user.ctcc\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.ctcc6 $(1)/usr/share/pbr/pbr.user.ctcc6' "$pbr_makefile"
            fi
        fi
    fi

    if [ -f "$pbr_conf" ]; then
        if ! grep -q "pbr.user.ctcc" "$pbr_conf"; then
            echo "正在添加 PBR CTCC 配置条目..."
            sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
                /option enabled '0'/a\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.ctcc'\\
	option enabled '0'\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.ctcc6'\\
	option enabled '0'
            }" "$pbr_conf"
        fi
    fi
}

install_pbr_cucc() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"

    if [ -d "$pbr_pkg_dir" ]; then
        echo "正在安装 PBR CUCC 配置文件..."
        install -Dm644 "$BASE_PATH/patches/pbr.user.cucc" "$pbr_dir/pbr.user.cucc"
        install -Dm644 "$BASE_PATH/patches/pbr.user.cucc6" "$pbr_dir/pbr.user.cucc6"

        if [ -f "$pbr_makefile" ]; then
            if ! grep -q "pbr.user.cucc" "$pbr_makefile"; then
                echo "正在修改 PBR Makefile 添加 CUCC 安装规则..."
                sed -i '/pbr\.user\.netflix.*\$(1)/a\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cucc $(1)/usr/share/pbr/pbr.user.cucc\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cucc6 $(1)/usr/share/pbr/pbr.user.cucc6' "$pbr_makefile"
            fi
        fi
    fi

    if [ -f "$pbr_conf" ]; then
        if ! grep -q "pbr.user.cucc" "$pbr_conf"; then
            echo "正在添加 PBR CUCC 配置条目..."
            sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
                /option enabled '0'/a\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cucc'\\
	option enabled '0'\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cucc6'\\
	option enabled '0'
            }" "$pbr_conf"
        fi
    fi
}

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

# 京东云 IPQ60xx: 固定使用 kernel 6.12
# 原因: ath11k NSS 驱动 (nss.c) 使用了 kernel 6.16+ 已移除的 timer API (from_timer/del_timer_sync)
#       kernel 6.12 + 满血 NSS 是已验证的稳定组合
#       不关心上游当前是什么版本，京东云始终强制 6.12
fix_jdcloud_kernel_version() {
    local target_makefile="$BUILD_DIR/target/linux/qualcommax/Makefile"
    if [ ! -f "$target_makefile" ]; then
        return 0
    fi

    local current_ver
    current_ver=$(grep -m1 '^KERNEL_PATCHVER:=' "$target_makefile" | sed 's/.*:=//' | tr -d ' ')

    if [ "$current_ver" = "6.12" ]; then
        return 0
    fi

    sed -i "s/^KERNEL_PATCHVER:=${current_ver}/KERNEL_PATCHVER:=6.12/" "$target_makefile"
    if ! grep -q '^KERNEL_PATCHVER:=6.12$' "$target_makefile"; then
        echo "错误：内核版本 sed 未生效，当前值：" >&2
        grep 'KERNEL_PATCHVER' "$target_makefile" >&2
        exit 1
    fi
    echo "京东云: 内核版本从 ${current_ver} 回退到 6.12 (ath11k NSS timer API 兼容)"

    # feeds.conf.default 中 nss_packages 源也需要回退到 6.12 兼容的 qosmio/nss-packages
    # 匹配任何非 qosmio 的 nss-packages 源（如 VIKINGYFY/nss-packages-618 等）
    local feeds_conf="$BUILD_DIR/feeds.conf.default"
    if [ -f "$feeds_conf" ]; then
        local nss_feed
        nss_feed=$(grep -m1 'src-git nss_packages ' "$feeds_conf" | sed 's/.*src-git nss_packages //')
        if [ -n "$nss_feed" ] && ! echo "$nss_feed" | grep -q 'qosmio/nss-packages.git'; then
            sed -i "s|${nss_feed}|https://github.com/qosmio/nss-packages.git|" "$feeds_conf"
            if ! grep -q 'qosmio/nss-packages.git' "$feeds_conf"; then
                echo "错误：nss_packages feed sed 未生效" >&2
                grep 'src-git nss_packages' "$feeds_conf" >&2
                exit 1
            fi
            echo "京东云: nss_packages feed 从 ${nss_feed} 回退到 qosmio/nss-packages (kernel 6.12 兼容)"
        fi
    fi

    # kernel 6.12 降级时 config-6.12 缺少某些 ARM64 choice 默认选项
    # 会导致 syncconfig 交互式提示 "choice[1-3?]" → CI 环境无人应答 → Error 1
    # 参考: OpenWrt issue #19652, conf.c syncconfig 对 (NEW) choice 无法自动选择默认值
    #
    # 缺失选项分为两级：
    #   L1 (6.12 基础): ARM64_4K_PAGES, ARM64_VA_BITS_39 — 最初发现的，已导致上次失败
    #   L2 (6.12.85 新增): ARM64_PA_BITS_48, CPU_LITTLE_ENDIAN, SCHED_MC/CLUSTER/SMT, NR_CPUS
    #     6.12.85 引入 ARM64_PA_BITS_48 → 触发 Kernel Features 全部重问 → stdin 管道应答耗尽
    #     注意: CPU_BIG_ENDIAN 是 choice 默认(=1)，不设 CPU_LITTLE_ENDIAN 会生成大端内核 → 无法启动
    local config_6_12="$BUILD_DIR/target/linux/generic/config-6.12"
    if [ -f "$config_6_12" ]; then
        local added=0

        _append_if_missing() {
            local pattern="$1" value="$2"
            if ! grep -q "^${pattern}$" "$config_6_12" 2>/dev/null; then
                echo "$value" >> "$config_6_12"
                added=1
            fi
        }

        # L1: page size + VA bits (6.12 基础)
        _append_if_missing 'CONFIG_ARM64_4K_PAGES=y'     'CONFIG_ARM64_4K_PAGES=y'
        _append_if_missing 'CONFIG_ARM64_VA_BITS_39=y'   'CONFIG_ARM64_VA_BITS_39=y'

        # L2: 6.12.85 新增选项（ARM64_4K_PAGES 修复后级联触发 Kernel Features 重问）
        _append_if_missing 'CONFIG_ARM64_PA_BITS_48=y'   'CONFIG_ARM64_PA_BITS_48=y'
        _append_if_missing 'CONFIG_CPU_LITTLE_ENDIAN=y'  'CONFIG_CPU_LITTLE_ENDIAN=y'
        _append_if_missing '# CONFIG_SCHED_MC is not set'     '# CONFIG_SCHED_MC is not set'
        _append_if_missing '# CONFIG_SCHED_CLUSTER is not set' '# CONFIG_SCHED_CLUSTER is not set'
        _append_if_missing '# CONFIG_SCHED_SMT is not set'    '# CONFIG_SCHED_SMT is not set'
        _append_if_missing 'CONFIG_NR_CPUS=4'             'CONFIG_NR_CPUS=4'

        # 验证修复完整性（L1 + L2 关键项）
        local missing=""
        for opt in CONFIG_ARM64_4K_PAGES=y CONFIG_ARM64_VA_BITS_39=y \
                   CONFIG_ARM64_PA_BITS_48=y CONFIG_CPU_LITTLE_ENDIAN=y; do
            grep -q "^${opt}$" "$config_6_12" || missing="$missing $opt"
        done
        if [ -n "$missing" ]; then
            echo "错误：未能添加 ARM64 config 条目到 config-6.12:$missing" >&2
            exit 1
        fi

        if [ "$added" -gt 0 ]; then
            echo "京东云: config-6.12 已补全 ARM64 选项 (4K_PAGES+VA_BITS_39+PA_BITS_48+LITTLE_ENDIAN+调度器+NR_CPUS)"
        fi
    fi
}

fix_nikki_gobinpackage() {
    # nikki 上游 Makefile 使用 GoBinPackage，但 Build/Compile 是空的，
    # 导致 install_src 失败：找不到 .go_work/build/src/github.com/metacubex/mihomo
    #
    # 正确思路：nikki 本身不该编译 mihomo，只作为配置/UI 包。
    # mihomo 二进制由 small8/mihomo（GoBinPackage，自带完整源码）提供。
    # nikki 的 +mihomo 依赖通过 small8/mihomo 的 PROVIDES:=mihomo 满足。
    #
    # 修复方法：
    # 1. GoBinPackage -> GoPackage，在空的 Build/Compile 中添加 GoPackage/Compile
    # 2. 在 $(eval ...) 之前追加空的 Build/InstallDev，覆盖 golang-package.mk 的全局挂载
    #
    # 注意：Build/InstallDev 不在 nikki Makefile 里定义——它由 golang-package.mk
    # 第 301 行全局挂载（ifneq ($(strip $(GO_PKG)),) ... Build/InstallDev=...），
    # 所以不能通过在 nikki 文件内匹配 Build/InstallDev 来修复，
    # 必须在 golang-package.mk include 之后追加空的 define Build/InstallDev/enef 来覆盖。
    # 通用路径查找：nikki 可能来自 nikki 官方 feed (feeds/nikki/nikki/)
    # 或 small8 feed (feeds/small8/nikki/)，取决于 feeds.conf 配置
    local nikki_makefile
    nikki_makefile=$(find "$BUILD_DIR/feeds" -maxdepth 4 -path '*/nikki/Makefile' -type f 2>/dev/null | head -1)
    if [ -n "$nikki_makefile" ] && [ -f "$nikki_makefile" ]; then
        local fixed=0

        # 修复1：GoBinPackage -> GoPackage + 在空的 Build/Compile 中加入 GoPackage/Compile
        # 用单次 awk 完成两项替换，避免多次读写
        if grep -q '$(eval $(call GoBinPackage,nikki))' "$nikki_makefile"; then
            awk '
            BEGIN { in_block = 0 }
            # 检测空的 Build/Compile 块（define 后直接跟着 endef，中间只有空行）
            /^define Build\/Compile[[:space:]]*$/ { in_block = 1; print; next }
            in_block && /^[[:space:]]*$/ { next }
            in_block && /^endef$/ {
                print "\t$(call GoPackage/Compile,$(GO_PKG))"
                print "endef"
                in_block = 0
                next
            }
            # GoBinPackage -> GoPackage
            /\$\(eval \$\(call GoBinPackage,nikki\)\)/ {
                gsub(/GoBinPackage/, "GoPackage")
                print
                next
            }
            { print }
            ' "$nikki_makefile" > "$nikki_makefile.tmp" && mv "$nikki_makefile.tmp" "$nikki_makefile"
            echo "[nikki] GoBinPackage -> GoPackage + Build/Compile 添加 GoPackage/Compile"
            fixed=1
        fi

        # 修复2：追加空的 Build/InstallDev，覆盖 golang-package.mk 的挂载
        # Build/InstallDev 由 golang-package.mk 全局挂载（GO_PKG 不为空时），
        # nikki Makefile 里没有这个定义，所以必须在 include 之后追加空定义来覆盖。
        # 修复1 已将 GoBinPackage -> GoPackage，所以这里匹配 GoPackage。
        if ! grep -q '^define Build/InstallDev$' "$nikki_makefile"; then
            awk '
            /^\$\(eval \$\(call GoPackage,nikki\)\)/ {
                print "define Build/InstallDev"
                print "endef"
                print ""
            }
            { print }
            ' "$nikki_makefile" > "$nikki_makefile.tmp" && mv "$nikki_makefile.tmp" "$nikki_makefile"
            echo "[nikki] Build/InstallDev 置空（覆盖 golang-package.mk 全局挂载）"
        fi

        [ "$fixed" = "1" ] && echo "[nikki] Makefile 双重修复完成"
    fi
}

fix_bandix_default_enabled() {
    local bandix_config="$BUILD_DIR/feeds/openwrt_bandix/openwrt-bandix/files/bandix.config"
    if [ -f "$bandix_config" ]; then
        sed -i "s/option enabled '0'/option enabled '1'/g" "$bandix_config"
        echo "[bandix] traffic/connections/dns 默认已启用"
    fi
}
