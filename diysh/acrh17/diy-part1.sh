#!/bin/bash
# =============================================================
# diysh/acrh17/diy-part1.sh —— feeds 更新「之前」的钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 本分支只做一件事：把 helloworld 加成 feed，并固定到
# xray-core 25.1.1 那个提交。
#
# 为什么钉死 f92f566：
#   immortalwrt 24.10 的 golang 是 1.23.12，而 helloworld 从 xray
#   25.3.31 起要求 go 1.24、26.x 要求 go 1.26 —— 24.10 上编不过。
#   f92f566（2025-03-30）是最后一个 xray=25.1.1 的提交：
#     xray-core 25.1.1  → go 1.23   ✅
#     mosdns     5.3.3  → go 1.22   ✅（本分支仍会关掉它，见插件清单）
#   上游不会自己改这个 pin，所以不要随手去掉 ^f92f566。
# =============================================================

set -euo pipefail

HELLOWORLD_URL="https://github.com/fw876/helloworld.git"
HELLOWORLD_COMMIT="f92f566"

echo "== diy-part1: 加 helloworld feed（钉在 ${HELLOWORLD_COMMIT}）=="

# 幂等：重复执行不会加第二行
if grep -qE '^src-git[[:space:]]+helloworld' feeds.conf.default; then
  sed -i -E "s#^src-git[[:space:]]+helloworld.*#src-git helloworld ${HELLOWORLD_URL}^${HELLOWORLD_COMMIT}#" feeds.conf.default
else
  echo "src-git helloworld ${HELLOWORLD_URL}^${HELLOWORLD_COMMIT}" >> feeds.conf.default
fi

echo "--- feeds.conf.default ---"
grep -vE '^[[:space:]]*(#|$)' feeds.conf.default
echo "diy-part1 完成"
