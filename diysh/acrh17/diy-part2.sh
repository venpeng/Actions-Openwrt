#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# LAN 网段由 workflow 下拉框传入（LAN_IP = 1.1 或 11.1），
# 手动本地执行时不传就退回固件默认的 1.1，保证脚本能单独跑。
LAN_IP="${LAN_IP:-1.1}"
WRT_IP="192.168.${LAN_IP}"

#定义变量
CFG_FILE="./package/base-files/files/bin/config_generate"
WRT_WIFI="ASUS"
WRT_NAME="Openwrt"

#修改默认主题
#sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

#修改主机名称
#sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# 修改网关地址
# 上游默认就是 192.168.1.1，选 1.1 时这次替换等于空操作，
# 所以不再像以前那样分两个脚本（一个注释掉、一个打开）。
if [ -f "$CFG_FILE" ]; then
  sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
  echo "网关地址已设为 ${WRT_IP}"
else
  echo "!! 找不到 $CFG_FILE，网关地址未修改"
fi

#修改immortalwrt.lan关联IP-immortalwrt才有flash.js,用于luci页面-->系统-->备份与升级页面操作完成之后,重新刷新luci页面
FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null | head -1)
if [ -n "$FLASH_JS" ]; then
  sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$FLASH_JS"
  echo "flash.js 已同步为 ${WRT_IP}"
else
  echo "-- 没有 flash.js（非 immortalwrt 源），跳过"
fi

# 修改wifi名称
#sed -i 's/ImmortalWrt/ASUS/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i "s/\.ssid=.*/\.ssid=$WRT_WIFI/g" $(find ./package/kernel/mac80211/ ./package/network/config/ -type f -name "mac80211.*")
