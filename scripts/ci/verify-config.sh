#!/usr/bin/env bash
# =============================================================
# scripts/ci/verify-config.sh —— defconfig 之后的配置校验
#
# 目的：把「几小时后才在编译期炸」的问题提前到 30 秒内暴露。
#   defconfig 会静默丢弃源码树里不存在的符号 —— 机型选错、feeds 没装全、
#   插件名写错，全都表现为「编译成功但固件里没有」。
#
# 用法: verify-config.sh <openwrt目录> <机型|all> <true|false>
# 硬失败：板型不对、机型符号没选上
# 软提示：无线方案 / 额外插件缺失（只 warning，不阻断）
# =============================================================

set -uo pipefail

OW="${1:-.}"
DEVICE="${2:-}"
EXTRA="${3:-false}"

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_FILE="${EXTRA_FILE:-$CI_DIR/../../config/extra-packages.config}"
DEVICE_LIST="${DEVICE_LIST:-$CI_DIR/../../config/devices.txt}"

cd "$OW" || { echo "::error::无法进入 $OW"; exit 1; }
[ -f .config ] || { echo "::error::缺少 .config"; exit 1; }

FAIL=0
CONF="mediatek_filogic"

echo "========================================"
echo "配置校验"
echo "========================================"

# ---- 1) 板型 ----
BOARD=$(grep -m1 '^CONFIG_TARGET_BOARD=' .config | cut -d'"' -f2)
SUB=$(grep -m1 '^CONFIG_TARGET_SUBTARGET=' .config | cut -d'"' -f2)
echo "target     : ${BOARD:-?}/${SUB:-?}"
if [ "$BOARD" != "mediatek" ] || [ "$SUB" != "filogic" ]; then
  echo "::error::目标平台不是 mediatek/filogic，基础配置可能被改坏了"
  FAIL=1
fi

# ---- 2) 机型 ----
if [ "$DEVICE" = "all" ]; then
  echo "模式       : all（多机型）"
  if [ -f "$DEVICE_LIST" ]; then
    MISS=""
    N=0
    while IFS= read -r line; do
      line="${line%$'\r'}"
      case "$line" in ''|\#*) continue ;; esac
      N=$((N + 1))
      grep -qx "CONFIG_TARGET_DEVICE_${CONF}_DEVICE_${line}=y" .config || MISS="$MISS $line"
    done < "$DEVICE_LIST"
    echo "清单机型   : ${N} 个（config/devices.txt）"
    if [ -n "$MISS" ]; then
      echo "::error::以下机型在多机型模式下没有被选中:$MISS"
      echo "         多机型模式里符号不存在会被静默跳过，那个机型的固件就不会出现"
      FAIL=1
    fi
  else
    echo "::warning::缺 config/devices.txt，只做粗略校验"
  fi
  MAP=$(grep -c "^CONFIG_TARGET_DEVICE_${CONF}_DEVICE_ruijie_rg-x60.*=y" .config)
  echo "实际选中   : ${MAP} 个"
  grep "^CONFIG_TARGET_DEVICE_${CONF}_DEVICE_.*=y" .config | sed 's/^CONFIG_TARGET_DEVICE_.*DEVICE_/    - /; s/=y$//'
  if [ "$MAP" -lt 1 ]; then
    echo "::error::all 模式一个机型都没选中，检查基础配置或多机型清单"
    FAIL=1
  fi
else
  echo "模式       : 单机型"
  if grep -qx "CONFIG_TARGET_${CONF}_DEVICE_${DEVICE}=y" .config; then
    echo "选中机型   : ${DEVICE} ✅"
  else
    echo "::error::机型 ${DEVICE} 在 defconfig 后被丢弃 —— 当前源码树里没有这个设备符号"
    echo "         defconfig 会回落到该子目标的默认机型，出来的是别的机器的固件，必须中止"
    echo "         实际选中："
    grep "^CONFIG_TARGET_${CONF}_DEVICE_.*=y" .config | sed 's/^/           /'
    FAIL=1
  fi
fi

# ---- 3) 无线方案（这套源码走 MTK 厂商驱动，不是 mt76）----
if grep -qx 'CONFIG_PACKAGE_kmod-mt_wifi=y' .config; then
  echo "无线驱动   : kmod-mt_wifi（MTK 厂商驱动）✅"
else
  echo "::warning::CONFIG_PACKAGE_kmod-mt_wifi 未启用 —— 若源码分支走 mt76 路线可忽略"
fi
grep -q '^CONFIG_LUCI_LANG_zh_Hans=y' .config && echo "中文界面   : 已启用 ✅" \
  || echo "::warning::CONFIG_LUCI_LANG_zh_Hans 未启用，LuCI 将是英文"

# ---- 4) 额外插件 ----
if [ "$EXTRA" = "true" ]; then
  MISS=""
  TOTAL=0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    SYM="${line%%=*}"
    VAL="${line#*=}"
    [ "$VAL" = "y" ] || continue
    TOTAL=$((TOTAL + 1))
    grep -qx "${SYM}=y" .config || MISS="$MISS ${SYM#CONFIG_PACKAGE_}"
  done < "$EXTRA_FILE"

  if [ -n "$MISS" ]; then
    echo "::warning::以下额外插件在 defconfig 后没进 .config（源码分支的 feeds 里没有该包）:$MISS"
    echo "         对应机型仍会正常出固件，只是少这几个插件"
  else
    echo "额外插件   : ${TOTAL} 项全部就位 ✅"
  fi
else
  echo "额外插件   : 已按要求关闭"
fi

# ---- 5) 体积粗估（rootfs 包清单行数，仅参考）----
echo "包配置行数 : $(grep -c '^CONFIG_PACKAGE_.*=y' .config)"

echo "========================================"
if [ "$FAIL" -ne 0 ]; then
  echo "::error::配置校验未通过，终止构建"
  exit 1
fi
echo "✅ 配置校验通过"
