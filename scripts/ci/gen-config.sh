#!/usr/bin/env bash
# =============================================================
# scripts/ci/gen-config.sh —— 生成本次编译用的 .config
#
#   基础配置（config/base/<源码>.config）
#     + 机型选择（单机型 / all=源码树里全部锐捷 X60 系）
#     + 额外插件开关（config/extra-packages.config）
#
# 用法:
#   gen-config.sh <openwrt目录> <基础配置> <机型|all> <true|false>
#
# 设计要点:
#   1) 基础配置里不留任何 CONFIG_TARGET_*_DEVICE_* / CONFIG_DEFAULT_*，
#      这些由 defconfig 按机型重新推导 —— 机型切换靠这里追加，不靠改文件。
#   2) all 的机型清单从源码树 image/*.mk 里实时抓，两个源码的设备差异
#      （比如 yuzhii 多了 rg-x60-new-ubi）自动跟随，不会写死对不上。
#   3) 额外插件用逐条覆盖的方式写入：先删同名行再追加，避免
#      "同一符号出现两次、后写的被 Kconfig 前一次值带偏"。
# =============================================================

set -euo pipefail

OW="${1:-}"
BASE="${2:-}"
DEVICE="${3:-}"
EXTRA="${4:-false}"

if [ -z "$OW" ] || [ -z "$BASE" ] || [ -z "$DEVICE" ]; then
  echo "用法: $0 <openwrt目录> <基础配置> <机型|all> <true|false>" >&2
  exit 1
fi

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_FILE="${EXTRA_FILE:-$CI_DIR/../../config/extra-packages.config}"
DEVICE_LIST_FILE="${DEVICE_LIST_FILE:-$CI_DIR/../../config/devices.txt}"

[ -d "$OW" ]      || { echo "::error::源码目录不存在: $OW"; exit 1; }
[ -f "$BASE" ]    || { echo "::error::基础配置不存在: $BASE"; exit 1; }
[ -f "$EXTRA_FILE" ] || { echo "::error::额外插件清单不存在: $EXTRA_FILE"; exit 1; }

# 转绝对路径：下面要 cd 进源码树，相对路径会失效
BASE="$(cd "$(dirname "$BASE")" && pwd)/$(basename "$BASE")"
OW="$(cd "$OW" && pwd)"

cd "$OW"

# filogic 子目标的机型定义文件
IMAGE_MK_DIR="target/linux/mediatek/image"
[ -d "$IMAGE_MK_DIR" ] || { echo "::error::找不到 $IMAGE_MK_DIR，源码树不完整？"; exit 1; }

# ---------------------------------------------------------------
# 机型清单
#   config/devices.txt   —— 下拉 all 要编的机型（人工维护）
#   源码树 image/*.mk     —— 用来校验机型是否真的存在
# ---------------------------------------------------------------
tree_devices() {
  grep -hoE '^define Device/ruijie_rg-x60[^[:space:]]*' "$IMAGE_MK_DIR"/*.mk 2>/dev/null \
    | sed 's#^define Device/##' | sort -u
}

# 读 config/devices.txt，忽略注释/空行，去掉可能的 CR
devices_from_list() {
  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    echo "$line"
  done < "$DEVICE_LIST_FILE"
}

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
apply_list() {
  local file="$1" mode="$2" line sym val
  while IFS= read -r line; do
    line="${line%$'\r'}"
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

# 兜底清一遍机型/多机型符号（基础配置本身已清，防止有人手工加回去）
sed -i '/^\(# \)\?CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_MULTI_PROFILE[= ]/d; /^# CONFIG_TARGET_MULTI_PROFILE is not set$/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_PER_DEVICE_ROOTFS[= ]/d; /^# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set$/d' .config
sed -i '/^\(# \)\?CONFIG_TARGET_ALL_PROFILES[= ]/d; /^# CONFIG_TARGET_ALL_PROFILES is not set$/d' .config

# ---------------------------------------------------------------
# 2) 机型
# ---------------------------------------------------------------
TREE="$(tree_devices)"
[ -n "$TREE" ] || { echo "::error::$IMAGE_MK_DIR 里找不到任何 ruijie_rg-x60* 机型，源码树不完整？"; exit 1; }

if [ "$DEVICE" = "all" ]; then
  [ -f "$DEVICE_LIST_FILE" ] || { echo "::error::缺机型清单 $DEVICE_LIST_FILE"; exit 1; }
  DEVICES="$(devices_from_list)"
  [ -n "$DEVICES" ] || { echo "::error::$DEVICE_LIST_FILE 里没有机型"; exit 1; }

  # 清单里的机型必须在当前源码树里，否则多机型模式会静默跳过它
  MISS=""
  while IFS= read -r d; do
    echo "$TREE" | grep -qx "$d" || MISS="$MISS $d"
  done <<< "$DEVICES"
  if [ -n "$MISS" ]; then
    echo "::error::config/devices.txt 里以下机型不在当前源码树里:$MISS"
    echo "::error::当前源码可用机型："
    echo "$TREE" | sed 's/^/        /'
    exit 1
  fi

  set_config CONFIG_TARGET_MULTI_PROFILE y
  set_config CONFIG_TARGET_PER_DEVICE_ROOTFS y        # 每机型独立 rootfs，不把别的机型包塞进来
  set_config CONFIG_TARGET_PROFILE '""'
  while IFS= read -r d; do
    set_config "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${d}" y
  done <<< "$DEVICES"
  echo "✅ 机型: all（本次编译以下 $(echo "$DEVICES" | wc -l) 个，来自 config/devices.txt）"
  echo "$DEVICES" | sed 's/^/     - /'
else
  if ! echo "$TREE" | grep -qx "$DEVICE"; then
    echo "::error::机型 $DEVICE 不在当前源码树里，可用："
    echo "$TREE" | sed 's/^/        /'
    echo "::error::提示：device 只支持下拉里那两个机型或 all；要编别的布局，先加到 config/devices.txt 再选 all"
    exit 1
  fi
  set_config CONFIG_TARGET_MULTI_PROFILE n
  # 单机型走 choice 里的那个符号（没有 TARGET_DEVICE_ 前缀）。
  # ⚠ 写成 CONFIG_TARGET_DEVICE_... 是「Target Devices」菜单里的多机型符号，
  #    在 MULTI_PROFILE=n 时它不参与选择，defconfig 会回落到子目标默认机型。
  set_config "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE}" y
  set_config CONFIG_TARGET_PROFILE "\"DEVICE_${DEVICE}\""
  echo "✅ 机型: $DEVICE（单机型）"
fi
set_config CONFIG_TARGET_BOARD '"mediatek"'
set_config CONFIG_TARGET_SUBTARGET '"filogic"'

# ---------------------------------------------------------------
# 3) 额外插件
# ---------------------------------------------------------------
if [ "$EXTRA" = "true" ]; then
  apply_list "$EXTRA_FILE" on
  echo "✅ 额外插件: 开启（$(grep -cE '^CONFIG_' "$EXTRA_FILE") 项写入 .config）"
else
  apply_list "$EXTRA_FILE" off
  echo "✅ 额外插件: 关闭（清单内 $(grep -cE '^CONFIG_' "$EXTRA_FILE") 项全部置为 not set）"
fi

echo "----------------------------------------"
echo "单机型符号 : $(grep -c '^CONFIG_TARGET_mediatek_filogic_DEVICE_' .config) 个（1 = 单机型模式）"
echo "多机型符号 : $(grep -c '^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_' .config) 个（>0 = 多机型模式）"
