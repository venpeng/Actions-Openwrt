#!/bin/bash
# =============================================================
# diysh/acrh17/diy-part1.sh —— feeds 更新「之前」的钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 本分支只做一件事：修 401 内核补丁，让官方 23.05 能编 ipq40xx。
#
# 现象（target/linux 阶段，几十分钟后才炸）：
#   applying .../401-mmc-sdhci-msm-comment-unused-sdhci_msm_set_clock.patch
#   Hunk #1 FAILED at 1814.
#
# 原因：immortalwrt 23.05 把内核更到 5.15.198，但 ipq40xx/patches-5.15/401
#   还是旧上下文。stable 给 sdhci_msm_set_clock 加了一行 `struct mmc_ios ios`，
#   msm_set_clock_rate_for_bus_mode 也从 2 参数变成 3 参数，hunk 行号自然对不上。
#
# 处理：用 openwrt 官方 23.05 已刷新的同名补丁覆盖（改动内容一致，只是 hunk
#   行号和这几行 backport 对上了）。补丁放在仓库 patches/ 下，构建时不需要联网
#   去取，也不依赖 openwrt 那边的补丁文件一直保持这个状态。
# =============================================================

set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
K401="401-mmc-sdhci-msm-comment-unused-sdhci_msm_set_clock.patch"
SRC401="$REPO_ROOT/patches/ipq40xx-5.15/$K401"
DST401="target/linux/ipq40xx/patches-5.15/$K401"

if [ -f "$SRC401" ] && [ -f "$DST401" ]; then
  if cmp -s "$SRC401" "$DST401"; then
    echo "内核补丁 $K401 已是修正版，跳过"
  else
    cp -f "$SRC401" "$DST401"
    echo "已替换内核补丁: $K401（适配 5.15.198 的 sdhci-msm.c）"
  fi
elif [ -f "$SRC401" ]; then
  # 上游哪天把补丁自己修好了、或者挪了位置，这里会走到
  echo "-- 源码树里没有 $DST401（内核版本或补丁名变了？），跳过替换"
  echo "-- 若构建在 401 补丁处失败，回来核对这个文件名"
else
  echo "::warning::仓库里缺少 patches/ipq40xx-5.15/$K401，构建很可能在 401 补丁处失败"
fi

echo "diy-part1 完成"
