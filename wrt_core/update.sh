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
LAN_ADDR="${LAN_ADDR:-192.168.168.1}"

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
    remove_tweaked_packages
    install_custom_feed
    fix_homeproxy_patches
    fix_argon_wget_depends
    fix_default_set
    fix_miniupnpd
    update_golang
    ## change_dnsmasq2full
    update_default_lan_addr
    set_custom_task
    apply_passwall_tweaks
    set_build_signature
    update_menu_location
    ## update_dnsmasq_conf
    fix_quickstart
    update_oaf_deconfig
    ## add_quickfile
    ## update_dockerman
    ## set_nginx_default_config
    # fix_apk_repo_mirrors
    fix_dockerman_menu_order
    fix_adguardhome_rpcd
    fix_dockerman_events_timeout
    fix_dockerman_rpc_events_timeout
    fix_bandix_default_enabled
    remove_attendedsysupgrade
    fix_kconfig_recursive_dependency
    install_feeds
    verify_custom_feed_installed_paths
    fix_apk_package_versions
    fix_apk_file_conflicts
    docker_stack_sync_nftables_compat "$BUILD_DIR" "0"
    fix_docker_uc_stream_timeout "$BUILD_DIR"
    update_smartdns
    fix_nikki_gobinpackage
    ## fix_cups_libcups_avahi_depends
    install_pbr_cmcc
    install_pbr_ctcc
    install_pbr_cucc
    enable_ttyd_autologin
    fix_pbr_ip_forward
}

main "$@"
