#!/usr/bin/env bash
# =============================================================
# scripts/ci/verify-config.sh —— defconfig 之后的配置校验（ACRH17）
#
# 目的：把「几小时后才在编译期炸」的问题提前到 30 秒内暴露。
#   defconfig 会静默丢弃源码树里不存在的符号 —— 机型选错、feeds 没装全、
#   插件名写错，全都表现为「编译成功但固件里没有」。
#
# 用法: verify-config.sh <openwrt目录> <true|false>
# 硬失败：板型不对、机型符号没选上
# 软提示：无线方案 / 额外插件缺失（只 warning，不阻断）
# =============================================================

set -uo pipefail

OW="${1:-.}"
EXTRA="${2:-false}"

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_FILE="${EXTRA_FILE:-$CI_DIR/../../config/extra-packages.config}"

BOARD="ipq40xx"
SUBTARGET="generic"
CONF="${BOARD}_${SUBTARGET}"
DEVICE="${DEVICE:-asus_rt-ac42u}"

cd "$OW" || { echo "::error::无法进入 $OW"; exit 1; }
[ -f .config ] || { echo "::error::缺少 .config"; exit 1; }

FAIL=0

echo "========================================"
echo "配置校验"
echo "========================================"

# ---- 1) 板型 ----
B=$(grep -m1 '^CONFIG_TARGET_BOARD=' .config | cut -d'"' -f2)
S=$(grep -m1 '^CONFIG_TARGET_SUBTARGET=' .config | cut -d'"' -f2)
echo "target     : ${B:-?}/${S:-?}"
if [ "$B" != "$BOARD" ] || [ "$S" != "$SUBTARGET" ]; then
  echo "::error::目标平台不是 ${BOARD}/${SUBTARGET}，基础配置可能被改坏了"
  FAIL=1
fi

# ---- 2) 机型 ----
if grep -qx "CONFIG_TARGET_${CONF}_DEVICE_${DEVICE}=y" .config; then
  echo "选中机型   : ${DEVICE} ✅"
else
  echo "::error::机型 ${DEVICE} 在 defconfig 后被丢弃 —— 当前源码树里没有这个设备符号"
  echo "         defconfig 会回落到该子目标的默认机型，出来的是别的机器的固件，必须中止"
  echo "         实际选中："
  grep "^CONFIG_TARGET_${CONF}_DEVICE_.*=y" .config | sed 's/^/           /'
  FAIL=1
fi

# ---- 3) 无线方案（ipq40xx generic 走 ath10k-ct，不是 mt76 / mt_wifi）----
if grep -qx 'CONFIG_PACKAGE_kmod-ath10k-ct=y' .config; then
  echo "无线驱动   : kmod-ath10k-ct ✅"
else
  echo "::warning::CONFIG_PACKAGE_kmod-ath10k-ct 未启用 —— 这个机型靠它才有 5G"
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
    echo "::warning::以下额外插件在 defconfig 后没进 .config（feeds 里没有该包）:$MISS"
    echo "         固件仍会正常产出，只是少这几个插件"
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
