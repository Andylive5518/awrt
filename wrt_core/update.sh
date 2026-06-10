#!/usr/bin/env bash

set -e
set -o errexit
set -o errtrace

error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

trap 'error_handler' ERR

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4
CONFIG_FILE=$5

if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="26.x"
THEME_SET="argon"
LAN_ADDR="${LAN_ADDR:-192.168.192.1}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_PATH=${BASE_PATH:-$SCRIPT_DIR}

for module in "$SCRIPT_DIR/modules/"*.sh; do
    source "$module"
done


main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    install_custom_feed
    fix_luci_app_store_apk_version
    fix_homeproxy_patches
    fix_default_set
    fix_miniupnpd
    update_golang
    fix_mk_def_depends
    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    update_ath11k_fw
    add_ax6600_led
    set_custom_task
    apply_passwall_tweaks
    set_build_signature
    update_nss_diag
    update_menu_location
    update_dnsmasq_conf
    update_mosdns_deconfig
    fix_quickstart
    update_oaf_deconfig
    add_quickfile
    fix_rust_compile_error
    update_smartdns
    patch_smartdns
    # update_dockerman
    set_nginx_default_config
    update_uwsgi_limit_as
    update_nginx_ubus_module
    check_default_settings
    install_opkg_distfeeds
    fix_bandix_default_enabled
    fix_easytier_mk
    remove_attendedsysupgrade
    fix_kconfig_recursive_dependency
    install_feeds
    verify_custom_feed_installed_paths
    docker_stack_sync_nftables_compat "$BUILD_DIR" "0"
    fix_docker_uc_stream_timeout "$BUILD_DIR"
    # fix_cups_libcups_avahi_depends
    fix_easytier_lua
    update_script_priority
    update_geoip
    fix_opkg_check
    install_pbr_cmcc
    install_pbr_ctcc
    install_pbr_cucc
    enable_ttyd_autologin
    fix_nikki_gobinpackage
    fix_pbr_ip_forward
}

main "$@"
