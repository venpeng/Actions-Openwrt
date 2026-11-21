#!/usr/bin/env bash
# =============================================================
# scripts/ci/diy-part2.sh —— .config 生成后、make defconfig 之前的钩子
#
# 运行位置：gen-config.sh 写好 .config → 本脚本 → make defconfig
# 当前工作目录：/workdir/openwrt
#
# 可用的环境变量：
#   SOURCE_NAME / REPO_URL / BRANCH / DEVICE / EXTRA_PLUGINS
#
# 典型用途：
#   - 改默认 LAN IP、主机名、WiFi SSID/密码
#   - 往 .config 追加 =y（必须在 defconfig 之前写，否则会被重新展开剔除）
#   - 打源码补丁（localedef、LuCI 文案、驱动参数……）
#
# 注意：.config 的机型与额外插件由 gen-config.sh 管，
#       这里只补它不管的东西，避免两边互相覆盖。
# =============================================================

set -euo pipefail

echo "== diy-part2 =="

# ---- 示例：改默认 LAN IP（按需取消注释）----
# sed -i 's/192\.168\.1\.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# ---- 示例：改默认主机名 ----
# sed -i "s/hostname='ImmortalWrt'/hostname='X60'/g" package/base-files/files/bin/config_generate

# ---- 示例：追加自定义配置项（defconfig 之前才有效）----
# echo 'CONFIG_PACKAGE_luci-app-argon-config=y' >> .config

echo "机型: ${DEVICE} / 额外插件: ${EXTRA_PLUGINS}"
echo "diy-part2 完成"
