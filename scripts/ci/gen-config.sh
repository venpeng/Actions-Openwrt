#!/usr/bin/env bash
# =============================================================
# scripts/ci/gen-config.sh —— 生成本次编译用的 .config（ACRH17）
#
#   基础配置（config/base/immortalwrt-23.05.config）
#     + 机型符号（asus_rt-ac42u）
#     + 额外插件开关（config/extra-packages.config）
#
# 用法:
#   gen-config.sh <openwrt目录> <基础配置> <true|false>
#
# 设计要点:
#   1) 基础配置里不留 CONFIG_TARGET_*_DEVICE_* / CONFIG_TARGET_PROFILE /
#      CONFIG_DEFAULT_*，这些由 defconfig 按机型重新推导 —— 机型靠这里追加。
#      脚本仍会兜底清一遍：base 直接用「menuconfig 导出的完整 .config」覆盖
#      也不会出错（多机型符号、设备选择、默认包快照都会被剔掉）。
#   2) 额外插件用逐条覆盖：先删同名行再追加，避免同一符号出现两次、
#      后写的被 Kconfig 前一次值带偏。
#   3) 机型必须真实存在于源码树，否则 defconfig 会静默回落到子目标默认机型，
#      出来的是别的机器的固件 —— 所以先查 image/*.mk 再干活。
# =============================================================

set -euo pipefail

OW="${1:-}"
BASE="${2:-}"
EXTRA="${3:-false}"

if [ -z "$OW" ] || [ -z "$BASE" ]; then
  echo "用法: $0 <openwrt目录> <基础配置> <true|false>" >&2
  exit 1
fi

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_FILE="${EXTRA_FILE:-$CI_DIR/../../config/extra-packages.config}"

# ACRH17 固定机型；要编别的 ipq40xx 设备时用 DEVICE= 覆盖
DEVICE="${DEVICE:-asus_rt-ac42u}"
BOARD="ipq40xx"
SUBTARGET="generic"
CONF="${BOARD}_${SUBTARGET}"

[ -d "$OW" ]        || { echo "::error::源码目录不存在: $OW"; exit 1; }
[ -f "$BASE" ]      || { echo "::error::基础配置不存在: $BASE"; exit 1; }
[ -f "$EXTRA_FILE" ]|| { echo "::error::额外插件清单不存在: $EXTRA_FILE"; exit 1; }

# 转绝对路径：下面要 cd 进源码树，相对路径会失效
BASE="$(cd "$(dirname "$BASE")" && pwd)/$(basename "$BASE")"
OW="$(cd "$OW" && pwd)"
cd "$OW"

# ---------------------------------------------------------------
# 机型是否存在于源码树
# ---------------------------------------------------------------
IMAGE_MK_DIR="target/linux/${BOARD}/image"
[ -d "$IMAGE_MK_DIR" ] || { echo "::error::找不到 $IMAGE_MK_DIR，源码树不完整？"; exit 1; }

TREE_DEVICES="$(grep -rhoE '^define Device/[^[:space:]]+' "$IMAGE_MK_DIR"/*.mk 2>/dev/null \
  | sed 's#^define Device/##' | sort -u)"
if ! echo "$TREE_DEVICES" | grep -qx "$DEVICE"; then
  echo "::error::机型 $DEVICE 不在当前源码树里（$IMAGE_MK_DIR）"
  echo "::error::可用机型里与 asus/rt 相关的："
  echo "$TREE_DEVICES" | grep -iE 'asus|rt-' | sed 's/^/        /' || true
  exit 1
fi

# ---------------------------------------------------------------
# 写一个 Kconfig 符号：先删同名行（=值 与 is not set 两种形态）再追加
# ---------------------------------------------------------------
set_config() {
  local sym="$1" val="${2:-y}"
  sed -i "\|^${sym}=|d; \|^# ${sym} is not set$|d" .config
  if [ "$val" = "n" ]; then
    echo "# ${sym} is not set" >> .config
  else
    echo "${sym}=${val}" >> .config
  fi
}

# 逐行应用清单文件（忽略注释/空行，去掉可能的 CR）
#   支持两种条目：
#     CONFIG_PACKAGE_x=y                正常写入
#     # CONFIG_PACKAGE_x is not set     显式关闭（用于「默认会被 defconfig 打开」的项，
#                                      比如 ssr-plus 的 MosDNS 在 arm 上默认 =y）
apply_list() {
  local file="$1" mode="$2" line sym val
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "# CONFIG_"*" is not set" ]]; then
      sym="${line#\# }"; sym="${sym% is not set}"
      set_config "$sym" n
      continue
    fi
    case "$line" in ''|\#*) continue ;; esac
    sym="${line%%=*}"
    val="${line#*=}"
    [ "$sym" = "$line" ] && continue          # 没有 = 号，跳过
    [ "$mode" = "off" ] && val="n"
    set_config "$sym" "$val"
  done < "$file"
}

# ---------------------------------------------------------------
# 1) 基础配置
# ---------------------------------------------------------------
: > .config
cat "$BASE" >> .config
echo "✅ 基础配置: $BASE（$(wc -l < .config) 行）"

# 兜底清机型/多机型/默认包符号（base 本身已清，防有人直接用完整 .config 覆盖）
sed -i '/^\(# \)\?CONFIG_TARGET_'"$CONF"'_DEVICE_/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_PROFILE=/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_MULTI_PROFILE[= ]/d; /^# CONFIG_TARGET_MULTI_PROFILE is not set$/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_PER_DEVICE_ROOTFS[= ]/d; /^# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set$/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_ALL_PROFILES[= ]/d; /^# CONFIG_TARGET_ALL_PROFILES is not set$/d' .config
sed -i '/^CONFIG_DEFAULT_/d' .config

# ---------------------------------------------------------------
# 2) 机型
# ---------------------------------------------------------------
set_config CONFIG_TARGET_MULTI_PROFILE n
# 单机型走 choice 里的符号（没有 TARGET_DEVICE_ 前缀）。
# ⚠ 写成 CONFIG_TARGET_DEVICE_... 是「Target Devices」菜单里的多机型符号，
#    在 MULTI_PROFILE=n 时它不参与选择，defconfig 会回落到子目标默认机型。
set_config "CONFIG_TARGET_${CONF}_DEVICE_${DEVICE}" y
set_config CONFIG_TARGET_PROFILE "\"DEVICE_${DEVICE}\""
set_config CONFIG_TARGET_BOARD "\"${BOARD}\""
set_config CONFIG_TARGET_SUBTARGET "\"${SUBTARGET}\""
echo "✅ 机型: $DEVICE（${BOARD}/${SUBTARGET}，单机型）"

# ---------------------------------------------------------------
# 3) 额外插件
# ---------------------------------------------------------------
if [ "$EXTRA" = "true" ]; then
  apply_list "$EXTRA_FILE" on
  echo "✅ 额外插件: 开启（清单 $(grep -cE '^CONFIG_' "$EXTRA_FILE") 项写入 .config）"
else
  apply_list "$EXTRA_FILE" off
  echo "✅ 额外插件: 关闭（清单 $(grep -cE '^CONFIG_' "$EXTRA_FILE") 项全部置为 not set）"
fi

echo "----------------------------------------"
echo "机型符号 : $(grep -c "^CONFIG_TARGET_${CONF}_DEVICE_" .config) 个（应为 1）"
echo "插件 =y  : $(grep -cE '^CONFIG_PACKAGE_.*=y' .config) 个包"
