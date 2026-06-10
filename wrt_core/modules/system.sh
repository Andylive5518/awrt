#!/usr/bin/env bash

fix_default_set() {
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    # install -Dm544 "$BASE_PATH/patches/993_ddns-go-config" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/993_ddns-go-config"
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

fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' "$BUILD_DIR/include/target.mk" 2>/dev/null
    if [ -f "$BUILD_DIR/target/linux/qualcommax/Makefile" ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' "$BUILD_DIR/target/linux/qualcommax/Makefile"
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
    local dir="$(get_custom_feed_worktree_dir)/luci-app-passwall"
    local chnlist_path="$dir/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi

    local patch_file="$BASE_PATH/patches/018-passwall-xray-util.patch"
    if [ -d "$dir" ]; then
        if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
            patch -p1 -d "$dir" -i "$patch_file" && echo "[passwall] xray util 已调优"
        fi
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    local apk_repos_dir="$BUILD_DIR/package/base-files/files/etc/apk/repositories.d"
    local apk_repos_file="$apk_repos_dir/distfeeds.list"
    local ver_file="$BUILD_DIR/include/version.mk"
    local repo mirror_replaced=0

    # 提取版本号：VERSION_NUMBER:=$(VERSION_NUMBER,5.15.150)
    local version_number
    version_number=$(sed -n 's/.*VERSION_NUMBER.*,\([0-9][0-9.]*\))$/\1/p' "$ver_file" | head -1)

    if [ -d "$emortal_def_dir" ]; then
        # 生成 opkg 和 APK 两种格式的软件源配置
        mkdir -p "$apk_repos_dir"
        : > "$distfeeds_conf"
        : > "$apk_repos_file"
        for repo in base luci packages routing telephony; do
            local url="https://mirrors.ustc.edu.cn/immortalwrt/releases/${version_number}/packages/x86_64/${repo}"
            echo "src/gz openwrt_${repo} ${url}" >> "$distfeeds_conf"
            echo "$url" >> "$apk_repos_file"
        done

        if ! grep -q '99-distfeeds.conf' "$emortal_def_dir/Makefile" 2>/dev/null; then
            sed -i "/define Package\/default-settings\/install/a\\
\t\$(INSTALL_DIR) \$(1)/etc\\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" "$emortal_def_dir/Makefile"

            sed -i "/exit 0/i\\
[ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\\
sed -i '/^option check_signature/d' /etc/opkg.conf\\
echo 'option check_signature 0' >> /etc/opkg.conf\n" "$emortal_def_dir/files/99-default-settings"
        fi

        echo "[opkg] 99-distfeeds.conf 已生成：${version_number}"
        echo "[apk]  distfeeds.list 已生成：${version_number}"
    fi

    if [ -n "$version_number" ]; then
        # 替换源码中所有硬编码的版本号和镜像地址
        while IFS= read -r -d '' f; do
            sed -i 's|$(call qstrip,$(CONFIG_VERSION_NUMBER))|'"${version_number}"'|g' "$f"
            sed -i "s|mirrors.vsean.net/openwrt|downloads.immortalwrt.org|g" "$f"
            mirror_replaced=1
        done < <(find "$BUILD_DIR/package" "$BUILD_DIR/include" "$BUILD_DIR/scripts" "$BUILD_DIR/feeds" \
            -type f \( -name '*.conf' -o -name '*.mk' -o -name 'Makefile' -o -name '*.sh' \) \
            -exec grep -l 'qstrip.*CONFIG_VERSION_NUMBER\|mirrors\.vsean\.net' {} \; 2>/dev/null | sort -u | tr '\n' '\0')

        if [ "$mirror_replaced" = "1" ]; then
            echo "[mirror] 版本号和镜像源已替换为官方源：${version_number}"
        fi
    fi
}

set_build_signature() {
    local dir="$BUILD_DIR/feeds/luci"
    local target="$dir/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    local patch_file="$BASE_PATH/patches/013-build-signature.patch"
    [ -f "$target" ] || return 0
    if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$dir" -i "$patch_file" && echo "[build] signature: build by Alex"
    fi
}

update_menu_location() {
    local patch_file

    patch_file="$BASE_PATH/patches/015-menu-samba4.patch"
    if [ -d "$BUILD_DIR/feeds/luci/applications/luci-app-samba4" ]; then
        if patch --dry-run -p1 -d "$BUILD_DIR/feeds/luci/applications/luci-app-samba4" -i "$patch_file" >/dev/null 2>&1; then
            patch -p1 -d "$BUILD_DIR/feeds/luci/applications/luci-app-samba4" -i "$patch_file"
        fi
    fi

    patch_file="$BASE_PATH/patches/016-menu-bandix.patch"
    local bdir="$(get_custom_feed_source_dir)/luci-app-bandix"
    if [ -d "$bdir" ]; then
        if patch --dry-run -p1 -d "$bdir" -i "$patch_file" >/dev/null 2>&1; then
            patch -p1 -d "$bdir" -i "$patch_file" && echo "[menu] bandix: network→status"
        fi
    fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

fix_quickstart() {
    local cf_dir patch_file
    cf_dir="$(get_custom_feed_source_dir)/luci-app-quickstart"
    patch_file="$BASE_PATH/patches/010-quickstart-istore-backend-cpu-temp.patch"
    local target="$cf_dir/luasrc/controller/istore_backend.lua"

    [ -f "$target" ] || {
        echo "[quickstart] istore_backend.lua 未找到，跳过"
        return 0
    }

    if patch --dry-run -p1 -d "$cf_dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$cf_dir" -i "$patch_file" && \
            echo "[quickstart] CPU 温度补丁已应用" || \
            echo "[quickstart] 警告：补丁应用失败" >&2
    else
        echo "[quickstart] CPU 温度补丁已存在，跳过"
    fi
}

update_oaf_deconfig() {
    local dir patch_file

    # appfilter.config: record_enable 1→0
    dir="$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type d -name 'open-app-filter' 2>/dev/null | head -1)"
    patch_file="$BASE_PATH/patches/020-oaf-appfilter-config.patch"
    if [ -n "$dir" ] && [ -f "$dir/files/appfilter.config" ]; then
        if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
            patch -p1 -d "$dir" -i "$patch_file" && echo "[OAF] appfilter: record_enable=0"
        fi
    fi

    # uci-defaults: 上游已无 disable_hnat，无需修补
    local uci_def
    uci_def=$(find "$(get_custom_feed_source_dir)" "$BUILD_DIR/feeds/" -maxdepth 8 -type f -path '*/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0' 2>/dev/null | head -1)
    if [ -n "$uci_def" ] && grep -q 'disable_hnat' "$uci_def" 2>/dev/null; then
        sed -i '/disable_hnat/d' "$uci_def"
        echo "[OAF] uci_def: removed disable_hnat"
    fi
}

fix_dockerman_menu_order() {
    local dir="$(get_custom_feed_worktree_dir)/luci-app-dockerman"
    local patch_file="$BASE_PATH/patches/012-dockerman-menu-order.patch"
    [ -f "$dir/root/usr/share/luci/menu.d/luci-app-dockerman.json" ] || return 0
    if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$dir" -i "$patch_file" && echo "[menu] dockerman order 40"
    fi
}

fix_adguardhome_rpcd() {
    local script
    script="$(get_custom_feed_worktree_dir)/luci-app-adguardhome/root/usr/libexec/rpcd/luci.adguardhome"
    [ -f "$script" ] || { echo "[adguardhome] rpcd script not found, skip"; return 0; }

    patch --no-backup-if-mismatch "$script" "$BASE_PATH/patches/995-adguardhome-rpcd.patch" && \
        echo "[adguardhome] rpcd script patched" || \
        echo "[adguardhome] rpcd patch failed"
}

# Docker 27+/29 的 /events 端点即使带 until 参数也不关闭连接（chunked 无终止符）
# 用 socket.poll 替代无限阻塞的 sock.recv，总超时 5 秒
fix_dockerman_events_timeout() {
    local script
    script="$(get_custom_feed_worktree_dir)/luci-app-dockerman/ucode/controller/docker.uc"
    [ -f "$script" ] || { echo "[dockerman] docker.uc not found, skip"; return 0; }

    patch --no-backup-if-mismatch "$script" "$BASE_PATH/patches/996-dockerman-events-timeout.patch" && \
        echo "[dockerman] events timeout patched" || \
        echo "[dockerman] events timeout patch failed"
}

# Docker rpcd 的 chunked_body_reader 有无限 while(true) 轮询
# Docker 不发 chunked 终止块时不退出，加 8 秒总超时
fix_dockerman_rpc_events_timeout() {
    local script
    script="$(get_custom_feed_worktree_dir)/luci-app-dockerman/root/usr/share/rpcd/ucode/docker_rpc.uc"
    [ -f "$script" ] || { echo "[dockerman-rpc] docker_rpc.uc not found, skip"; return 0; }

    patch --no-backup-if-mismatch "$script" "$BASE_PATH/patches/997-dockerman-rpc-events-timeout.patch" && \
        echo "[dockerman-rpc] events timeout patched" || \
        echo "[dockerman-rpc] events timeout patch failed"
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
    local dir="$BUILD_DIR/feeds/packages/net/pbr"
    local init_script="$dir/files/etc/init.d/pbr"
    local patch_file="$BASE_PATH/patches/019-pbr-ip-forward.patch"

    [ -f "$init_script" ] || {
        echo "PBR init script not found"; return 1
    }

    if grep -q '\[ -n "$enabled" \] && \[ -n "$strict_enforcement" \]' "$init_script"; then
        echo "PBR IP Forward fix already applied"
        return 0
    fi

    if ! grep -q '\[ -n "$strict_enforcement" \] && \[ "$(cat /proc/sys/net/ipv4/ip_forward)"' "$init_script"; then
        echo "PBR: 未找到需要修复的代码，跳过"
        return 0
    fi

    if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$dir" -i "$patch_file" && echo "PBR IP Forward 修复成功" || {
            echo "PBR IP Forward 修复失败" >&2; return 1
        }
    else
        echo "PBR: 补丁无法应用" >&2; return 1
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

remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}

enable_ttyd_autologin() {
    local dir="$BUILD_DIR/feeds/packages/utils/ttyd"
    local patch_file="$BASE_PATH/patches/014-ttyd-autologin.patch"
    [ -f "$dir/files/ttyd.config" ] || return 0
    if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$dir" -i "$patch_file" && echo "[ttyd] 自动登录"
    fi
}

fix_homeproxy_patches() {
    local cf_dir
    cf_dir="$(get_custom_feed_source_dir)/luci-app-homeproxy"

    [ -d "$cf_dir" ] || {
        echo "[homeproxy] luci-app-homeproxy 未找到，跳过"
        return 0
    }

    local patches=(
        "$BASE_PATH/patches/003-homeproxy-singbox-1.13-sniff.patch"
        "$BASE_PATH/patches/004-homeproxy-js-validator.patch"
        "$BASE_PATH/patches/005-homeproxy-client-ui.patch"
        "$BASE_PATH/patches/006-homeproxy-node-ui.patch"
        "$BASE_PATH/patches/007-homeproxy-uci-defaults.patch"
        "$BASE_PATH/patches/008-homeproxy-generate-client.patch"
        "$BASE_PATH/patches/009-homeproxy-migrate-config.patch"
    )

    for patch in "${patches[@]}"; do
        [ -f "$patch" ] || continue

        if patch --dry-run -p1 -d "$cf_dir" -i "$patch" >/dev/null 2>&1; then
            patch -p1 -d "$cf_dir" -i "$patch" &&
                echo "[homeproxy] $(basename $patch) 已应用" ||
                echo "[homeproxy] 警告：$(basename $patch) 应用失败" >&2
        elif grep -q "homeproxy" "$cf_dir/root/etc/homeproxy/scripts/homeproxy.uc" 2>/dev/null; then
            echo "[homeproxy] $(basename $patch) 已存在，跳过"
        else
            echo "[homeproxy] 警告：$(basename $patch) 无法应用，跳过" >&2
        fi
    done
}

fix_bandix_default_enabled() {
    local dir="$BASE_PATH/patches"
    local cf_dir="$(get_custom_feed_source_dir)/openwrt-bandix"
    local patch_file="$dir/011-bandix-default-enabled.patch"
    [ -f "$cf_dir/files/bandix.config" ] || return 0
    if patch --dry-run -p1 -d "$cf_dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$cf_dir" -i "$patch_file" && echo "[bandix] 默认启用"
    fi
}

fix_nikki_gobinpackage() {
    local dir="$(get_custom_feed_package_dir)/nikki"
    local patch_file="$BASE_PATH/patches/022-nikki-build-install.patch"
    [ -f "$dir/Makefile" ] || return 0
    if grep -q '^define Build/Install$' "$dir/Makefile" 2>/dev/null; then
        echo "[nikki] 修复已存在，跳过"
        return 0
    fi
    if patch --dry-run -p1 -d "$dir" -i "$patch_file" >/dev/null 2>&1; then
        patch -p1 -d "$dir" -i "$patch_file" && echo "[nikki] Build/Install 已覆盖（阻止 install_src）"
    else
        echo "[nikki] 错误：补丁无法应用" >&2
        return 1
    fi
}

fix_apk_package_versions() {
    local custom_feed_dir entry pkg_name makefile patch_file msg

    # update.sh 执行期间 ${BUILD_DIR}/.config 尚未生成，改用 deconfig 源文件
    grep -q '^CONFIG_USE_APK=y' "$CONFIG_FILE" 2>/dev/null || return 0

    echo "检测到 APK 包管理器，修复不兼容的版本号格式..."
    custom_feed_dir="$(get_custom_feed_source_dir 2>/dev/null)"

    # 包名 -> patch 文件映射
    local patches=(
        "luci-lib-docker:021-luci-lib-docker-apk-version.patch:版本号前缀 v 已去除"
        "luci-app-store:022-luci-app-store-apk-version.patch:版本号分隔符 - 已替换为 PKG_RELEASE"
    )

    for entry in "${patches[@]}"; do
        pkg_name="${entry%%:*}"
        patch_file="$BASE_PATH/patches/${entry#*:}"
        patch_file="${patch_file%%:*}"
        msg="${entry##*:}"

        makefile="$custom_feed_dir/$pkg_name/Makefile"
        [ -f "$makefile" ] && [ -f "$patch_file" ] || continue

        if patch --dry-run -p1 -d "$(dirname "$makefile")" -i "$patch_file" >/dev/null 2>&1; then
            patch -p1 -d "$(dirname "$makefile")" -i "$patch_file" && \
                echo "  $pkg_name: $msg"
        else
            echo "  $pkg_name: 补丁无需应用，跳过"
        fi
    done
}

fix_apk_file_conflicts() {
    local custom_feed_dir pkg init_script

    grep -q '^CONFIG_USE_APK=y' "$CONFIG_FILE" 2>/dev/null || return 0

    custom_feed_dir="$(get_custom_feed_source_dir 2>/dev/null)"

    # luci-app-adguardhome 依赖 +adguardhome，init 脚本应由 adguardhome 包独家提供
    # 删除 luci-app-adguardhome 中重复的 init 脚本，避免 APK 文件冲突
    init_script="$custom_feed_dir/luci-app-adguardhome/root/etc/init.d/adguardhome"
    if [ -f "$init_script" ]; then
        \rm -f "$init_script"
        echo "  luci-app-adguardhome: 已移除重复的 init 脚本（由 adguardhome 包提供）"
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

update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
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

update_geoip() {
    local geodata_path="$(get_custom_feed_package_dir)/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' "$geodata_path" | grep -oE "[0-9]{1,}")
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

fix_easytier_mk() {
    local mk_path="$(get_custom_feed_worktree_dir)/luci-app-easytier/easytier/Makefile"
    if [ -f "$mk_path" ]; then
        sed -i 's/!@(mips||mipsel)/!TARGET_mips \&\& !TARGET_mipsel/g' "$mk_path"
    fi
}

fix_easytier_lua() {
    local file_path="$(get_custom_feed_package_dir)/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then
        sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"
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

fix_opkg_check() {
    local patch_file="$BASE_PATH/patches/001-fix-provides-version-parsing.patch"
    local opkg_dir="$BUILD_DIR/package/system/opkg"
    if [ -f "$patch_file" ]; then
        install -Dm644 "$patch_file" "$opkg_dir/patches/001-fix-provides-version-parsing.patch"
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
