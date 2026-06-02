#!/usr/bin/env bash

fix_default_set() {
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    # install -Dm544 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"
    install -Dm544 "$BASE_PATH/patches/993_ddns-go-config" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/993_ddns-go-config"
    install -Dm544 "$BASE_PATH/patches/994_adguardhome-config" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/994_adguardhome-config"
    install -Dm544 "$BASE_PATH/patches/995_pbr_isp_config" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/995_pbr_isp_config"

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

change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"

    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
    fi

    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
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

    local raw_version
    raw_version=$(sed -n 's/.*VERSION_NUMBER.*,\([0-9][0-9.]*\))$/\1/p' "$ver_file" | head -1)
    version_number="$raw_version"

    if [ -d "$emortal_def_dir" ]; then
        cat >"$distfeeds_conf" <<EOF
src/gz openwrt_base https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/base/
src/gz openwrt_luci https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/luci/
src/gz openwrt_packages https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/packages/
src/gz openwrt_routing https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/routing/
src/gz openwrt_telephony https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/telephony/
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

        echo "[opkg] 99-distfeeds.conf 已生成：${version_number} (arch: x86_64, raw: ${raw_version})"
    fi

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
            echo "[opkg] distfeeds 模板已修复：${version_number} (arch: x86_64)"
        fi
    fi

    local chn_settings="$emortal_def_dir/files/99-default-settings-chinese"
    if [ -f "$chn_settings" ]; then
        sed -i 's|https://mirrors\.vsean\.net/openwrt|https://downloads.immortalwrt.org|g' "$chn_settings"
        echo "[mirror] 99-default-settings-chinese 镜像已改为官方"
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by Alex')/g" "$file"
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

    # PBR、WOL 等网络工具移到"网络"菜单（services → network）
    local network_apps="pbr wol"
    local net_app
    for net_app in $network_apps; do
        local net_menu_dirs
        net_menu_dirs=$(find "$BUILD_DIR/feeds/" -maxdepth 9 -type d -path "*/luci-app-$net_app/root/usr/share/luci/menu.d" 2>/dev/null)
        if [ -n "$net_menu_dirs" ]; then
            while IFS= read -r net_menu_dir; do
                [ -n "$net_menu_dir" ] && [ -d "$net_menu_dir" ] || continue
                find "$net_menu_dir" -maxdepth 1 -name '*.json' -exec sed -i 's|"admin/services/|"admin/network/|g' {} \;
                echo "[menu] $net_app: services -> network — $net_menu_dir"
            done <<< "$net_menu_dirs"
        fi
    done

    # Bandix 移到"状态"菜单，排在 WireGuard 下面 (order=8)
    local bandix_json_dir="$(get_custom_feed_source_dir)/luci-app-bandix/root/usr/share/luci/menu.d"
    if [ -d "$bandix_json_dir" ]; then
        find "$bandix_json_dir" -maxdepth 1 -name '*.json' \
            -exec sed -i 's|"admin/network/bandix|"admin/status/bandix|g' {} \;
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
    local appfilter_confs
    appfilter_confs=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type f -path '*/open-app-filter/files/appfilter.config' 2>/dev/null)
    local uci_defs
    uci_defs=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type f -path '*/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0' 2>/dev/null)

    # 修改 appfilter.config
    if [ -n "$appfilter_confs" ]; then
        while IFS= read -r appfilter_conf; do
            [ -n "$appfilter_conf" ] && [ -f "$appfilter_conf" ] || continue
            sed -i -e "s/record_enable '1'/record_enable '0'/g" \
                   -e "s/auto_load_engine '[01]'/auto_load_engine '1'/g" "$appfilter_conf"
            echo "[OAF] auto_load_engine=1, record_enable=0 — $appfilter_conf"
        done <<< "$appfilter_confs"
    fi

    # 修改 94_feature_3.0，删除 disable_hnat，防止首次启动覆盖配置
    # x86_64: auto_load_engine 保留（已在 appfilter.config 中设为 '1'）
    if [ -n "$uci_defs" ]; then
        while IFS= read -r uci_def; do
            [ -n "$uci_def" ] && [ -f "$uci_def" ] || continue
            if grep -q 'disable_hnat' "$uci_def" 2>/dev/null; then
                sed -i '/disable_hnat/d' "$uci_def"
                echo "[OAF] uci_def: removed disable_hnat — $uci_def"
            else
                echo "[OAF] uci_def: already clean — $uci_def"
            fi
        done <<< "$uci_defs"
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

# Docker 菜单排序：LuCI 24.10 中字符串 "40" 和数字 40 排序不同
# 包默认 "order": "40"（字符串）被排到所有数字order之后（即最后）
# 改为数字 40，和 NAS 同值靠字母序排在前面
fix_dockerman_menu_order() {
    local json_path="$(get_custom_feed_worktree_dir)/luci-app-dockerman/root/usr/share/luci/menu.d/luci-app-dockerman.json"
    if [ -f "$json_path" ]; then
        sed -i 's/"order": "40"/"order": 40/' "$json_path"
        echo "[menu] dockerman order 字符串→数字 40（排在 NAS 上面）"
    fi
}

# 修复 luci-app-adguardhome 的 rpcd 脚本两个 bug：
# 1. curl -w "%{http_code}}" 多了一个 } → status code 变成 "200}" 而非 "200"
# 2. http_address=0.0.0.0 时拼 hostname.domain 做 URL，dnsmasq 不解析该域名 → 改用 LAN IP
fix_adguardhome_rpcd() {
    local script
    script="$(get_custom_feed_worktree_dir)/luci-app-adguardhome/root/usr/libexec/rpcd/luci.adguardhome"
    [ -f "$script" ] || { echo "[adguardhome] rpcd script not found, skip"; return 0; }

    # 修复 1: curl -w 多余的 }
    sed -i 's/"%{http_code}}"/"%{http_code}"/' "$script"
    # 修复 2: hostname → LAN IP（dnsmasq 不解析 ImmortalWrt.lan）
    sed -i '/^\[\[ "\${HOST}" == "0.0.0.0" \]\] && HOST=/c\[[ "${HOST}" == "0.0.0.0" ] \&\& HOST=$(uci get network.lan.ipaddr 2>/dev/null)' "$script"

    echo "[adguardhome] rpcd script patched"
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
    local pbr_makefile="$pbr_pkg_dir/Makefile"

    if [ ! -d "$pbr_pkg_dir" ]; then
        echo "错误：PBR 包目录不存在: $pbr_pkg_dir" >&2
        return 1
    fi

    echo "正在安装 PBR $isp_upper 配置文件..."
    install -Dm644 "$BASE_PATH/patches/pbr.user.${isp_lower}" "$pbr_dir/pbr.user.${isp_lower}"
    install -Dm644 "$BASE_PATH/patches/pbr.user.${isp_lower}6" "$pbr_dir/pbr.user.${isp_lower}6"

    # Makefile: 在 Package/pbr/install 段的 endef 前插入 INSTALL_DATA 规则
    # 注意：pbr Makefile 有多个 define...endef 块，必须只匹配 install 段的 endef
    if [ -f "$pbr_makefile" ] && ! grep -q "pbr.user.${isp_lower}" "$pbr_makefile"; then
        echo "正在修改 PBR Makefile 添加 $isp_upper 安装规则..."
        local tmp_mk=$(mktemp)
        awk -v isp="$isp_lower" '
            /^define Package\/pbr\/install$/ { in_install = 1 }
            in_install && /^endef$/ && !done {
                printf "\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.%s $(1)/usr/share/pbr/pbr.user.%s\n", isp, isp
                printf "\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.%s6 $(1)/usr/share/pbr/pbr.user.%s6\n", isp, isp
                done = 1
            }
            /^endef$/ { in_install = 0 }
            { print }
        ' "$pbr_makefile" > "$tmp_mk" && mv "$tmp_mk" "$pbr_makefile"
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

fix_bandix_default_enabled() {
    local bandix_config="$(get_custom_feed_source_dir)/openwrt-bandix/files/bandix.config"
    if [ -f "$bandix_config" ]; then
        sed -i "s/option enabled '0'/option enabled '1'/g" "$bandix_config"
        echo "[bandix] traffic/connections/dns 默认已启用 ($bandix_config)"
    fi
}
