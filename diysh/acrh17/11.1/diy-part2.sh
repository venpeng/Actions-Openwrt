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

#定义变量
CFG_FILE="./package/base-files/files/bin/config_generate"
WRT_IP="192.168.11.1"
WRT_WIFI="ASUS"
WRT_NAME="Openwrt"

#修改默认主题
#sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

#修改主机名称
#sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# 修改网关地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#sed -i 's/192.168.1.1/192.168.11.1/g' package/base-files/files/bin/config_generate

#修改immortalwrt.lan关联IP-immortalwrt才有flash.js,用于luci页面-->系统-->备份与升级页面操作完成之后,重新刷新luci页面
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#sed -i 's/192.168.1.1/192.168.11.1/g' feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js

# 修改wifi名称
#sed -i 's/ImmortalWrt/ASUS/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i "s/\.ssid=.*/\.ssid=$WRT_WIFI/g" $(find ./package/kernel/mac80211/ ./package/network/config/ -type f -name "mac80211.*")

