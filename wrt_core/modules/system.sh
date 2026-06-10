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
