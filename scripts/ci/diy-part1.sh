#!/usr/bin/env bash
# =============================================================
# scripts/ci/diy-part1.sh —— feeds 更新「之前」的自定义钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 可用的环境变量：
#   SOURCE_NAME    源码名（padavanonly / yuzhii0718）
#   REPO_URL       源码地址
#   BRANCH         源码分支
#   DEVICE         机型（或 all）
#   EXTRA_PLUGINS  true / false
#
# 典型用途：
#   - 换 feeds 源（国内镜像 / 指定分支）
#   - 给 feeds.conf.default 追加第三方 feed
#   - 改源码树里的默认配置（package/base-files/...）
#
# 例：
#   sed -i 's#;openwrt-24.10#;openwrt-24.10#g' feeds.conf.default
#   echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall.git' >> feeds.conf.default
# =============================================================

set -euo pipefail

echo "== diy-part1 =="
echo "源码: ${SOURCE_NAME} (${REPO_URL})"
echo "分支: ${BRANCH}"

# 在下面写你的改动，例如：
# sed -i 's#https://github.com/immortalwrt/packages.git#https://gitee.com/mirrors/immortalwrt-packages.git#' feeds.conf.default

echo "diy-part1 完成"
