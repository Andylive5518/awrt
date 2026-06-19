#!/usr/bin/env bash

# 启用 hplip 的 hpcups 打印驱动（HP 1020/P1106/M1136 共用）
# 上游默认禁用了 hpcups，需要去掉 --disable-hpcups-install 和 --enable-lite-build
fix_hplip_enable_hpcups() {
    local makefile
    for makefile in \
        "$BUILD_DIR/feeds/packages/utils/hplip/Makefile" \
        "$BUILD_DIR/package/feeds/packages/hplip/Makefile"; do
        [ -f "$makefile" ] && break
    done
    [ -f "$makefile" ] || { echo "hplip Makefile 未找到，跳过 hpcups 启用"; return 0; }

    if grep -q "hplip-hpcups" "$makefile"; then
        echo "hplip: hpcups 已启用，跳过"
        return 0
    fi

    echo "正在启用 hplip hpcups 驱动支持..."

    # 去掉禁用 hpcups 和 cups-drv 的参数
    sed -i '/--disable-hpcups-install/d' "$makefile"
    sed -i '/--disable-cups-drv-install/d' "$makefile"

    # 在 hplip-sane 的 endef 后添加 hpcups 子包
    local block
    block=$(mktemp)
    cat > "$block" <<'HPCUPS'
define Package/hplip-hpcups
$(call Package/hplip/Default)
  TITLE+= (hpcups printer driver)
  DEPENDS+=+hplip-common +libcups +cups
endef

define Package/hplip-hpcups/install
	$(INSTALL_DIR) $(1)/usr/lib/cups/filter
	$(CP) $(PKG_BUILD_DIR)/prnt/hpcups/hpcups $(1)/usr/lib/cups/filter/
endef

$(eval $(call BuildPackage,hplip-hpcups))
HPCUPS
    sed -i "/^\$(eval \$(call BuildPackage,hplip-sane))\$/r $block" "$makefile"
    rm -f "$block"

    echo "hplip: hpcups 驱动已启用"
}

# HP 1020/1106/M1136 打印机固件安装
# 这些打印机是 GDI（主机依赖型），每次上电需要加载固件
install_printer_firmware() {
    local fw_dir="$BUILD_DIR/package/base-files/files/lib/firmware"
    local src_dir="$BASE_PATH/patches/printer-firmware"

    [ -d "$src_dir" ] || return 0

    echo "正在安装打印机固件..."
    mkdir -p "$fw_dir"

    for fw in "$src_dir"/sihp*.dl; do
        [ -f "$fw" ] || continue
        install -Dm644 "$fw" "$fw_dir/$(basename "$fw")"
        echo "  固件: $(basename "$fw")"
    done
}

# 安装 PPD 文件到 CUPS
install_printer_ppd() {
    local ppd_dir="$BUILD_DIR/package/base-files/files/usr/share/cups/model"
    local src_dir="$BASE_PATH/patches/printer-firmware"

    [ -d "$src_dir" ] || return 0

    echo "正在安装打印机 PPD..."
    mkdir -p "$ppd_dir"

    for ppd in "$src_dir"/*.ppd; do
        [ -f "$ppd" ] || continue
        install -Dm644 "$ppd" "$ppd_dir/$(basename "$ppd")"
        echo "  PPD: $(basename "$ppd")"
    done
}

# 安装 USB 热插拔固件加载脚本
# HP 1020/1106/M1136 每次上电需要重新加载固件
install_printer_hotplug() {
    local hotplug_dir="$BUILD_DIR/package/base-files/files/etc/hotplug.d/usb"
    local script="$hotplug_dir/10-hp-firmware"

    echo "正在安装打印机热插拔固件加载脚本..."
    mkdir -p "$hotplug_dir"

    cat > "$script" <<'HOTPLUG'
#!/bin/sh
# HP LaserJet 1020/1106/M1136 firmware loader
# Triggered when USB printer is connected

[ "$ACTION" = "add" ] || exit 0
[ "$DEVTYPE" = "usb_device" ] || exit 0

# HP 1020: 03f0:2b17, HP P1106: 03f0:032a, HP M1136: 03f0:042a
case "$PRODUCT" in
    3f0/2b17/*) FW="/lib/firmware/sihp1020.dl" ;;
    3f0/32a/*)  FW="/lib/firmware/sihpP1106.dl" ;;
    3f0/42a/*)  FW="/lib/firmware/sihpM1136.dl" ;;
    *) exit 0 ;;
esac

[ -f "$FW" ] || { logger -t hp-fw "Firmware not found: $FW"; exit 1; }

logger -t hp-fw "Loading firmware $FW for $PRODUCT on /dev/$DEVNAME"
# Wait for device to settle
sleep 2
cat "$FW" > "/dev/$DEVNAME" 2>/dev/null && \
    logger -t hp-fw "Firmware loaded successfully" || \
    logger -t hp-fw "Firmware load failed"
HOTPLUG

    chmod +x "$script"
    echo "  热插拔脚本: 10-hp-firmware"
}

# 安装 AirPrint 服务文件
# AirPrint 通过 mDNS (avahi-daemon) 广播打印机服务
install_airprint_services() {
    local avahi_dir="$BUILD_DIR/package/base-files/files/etc/avahi/services"
    local src_dir="$BASE_PATH/patches/printer-firmware"

    echo "正在安装 AirPrint 服务..."
    mkdir -p "$avahi_dir"

    # 为每个 PPD 生成 AirPrint 服务文件
    for ppd in "$src_dir"/*.ppd; do
        [ -f "$ppd" ] || continue
        local model=$(basename "$ppd" .ppd)
        local svc="$avahi_dir/airprint-${model}.service"

        cat > "$svc" <<AIRPRINT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>${model}</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/${model}</txt-record>
    <txt-record>ty=${model}</txt-record>
    <txt-record>adminurl=http://\$(hostname).local:631/printers/${model}</txt-record>
    <txt-record>note=${model} on ImmortalWRT</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>product=(${model})</txt-record>
    <txt-record>URF=CP255,DM1,MT1-2-8-10-11,OB9,PQ3-4-5,RS600,SRGB24,V1.4,W8</txt-record>
    <txt-record>pdl=application/pdf,image/urf,image/jpeg</txt-record>
    <txt-record>Color=F</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>TLS=1.2</txt-record>
  </service>
</service-group>
AIRPRINT
        echo "  AirPrint: ${model}"
    done
}

# 修复 CUPS 配置以支持 AirPrint 和网络共享
fix_cups_airprint_config() {
    local cupsd_conf="$BUILD_DIR/package/base-files/files/etc/cups/cupsd.conf"

    echo "正在配置 CUPS AirPrint 支持..."
    mkdir -p "$(dirname "$cupsd_conf")"

    cat > "$cupsd_conf" <<'CUPSDCONF'
# CUPS configuration for AirPrint + network sharing
LogLevel warn
PageLogFormat

# Listen on all interfaces for network printing
Port 631

# Allow remote administration from LAN
<Location />
  Order allow,deny
  Allow @LOCAL
</Location>

<Location /admin>
  Order allow,deny
  Allow @LOCAL
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow @LOCAL
</Location>

# Share printers via IPP
DefaultShared Yes

# Enable web interface
WebInterface Yes

# Browsing for AirPrint discovery
Browsing On
BrowseLocalProtocols dnssd
BrowseAddress @LOCAL

# Idle timeout: 30 minutes
IdleExitTimeout 1800
CUPSDCONF
    echo "  cupsd.conf: AirPrint + 网络共享已配置"
}
