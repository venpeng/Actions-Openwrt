#!/bin/bash
# =============================================================
# diysh/acrh17/diy-part1.sh —— feeds 更新「之前」的钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 本分支（21.02）只做一件事：把 helloworld 加成 feed，按 workflow 下拉的
# HW_VERSION 固定到对应的提交。golang 升级和内置 ssr-plus 的替换
# 在 scripts/ci/post-feeds.sh 里做（feeds install 之后）。
#
# 版本与 Go 要求：
#
#   HW_VERSION   helloworld 提交    xray         Go 要求   日期
#   24.12.31     5eeaf1c            24.12.31     go 1.21.4 2025-01-10（默认）
#   1.8.24       521e396            1.8.24       go 1.21.4 2024-10-14
#
#   21.02 自带 golang 1.19.13，两个版本都编不过 —— post-feeds.sh 会把
#   feeds/packages/lang/golang 换成 1.21.13（来自 immortalwrt/packages@23.05）。
#   25.1.1 及以上不在本分支提供（25.1.1 要 go 1.23、25.3.31+ 要 go 1.24）。
#
# 两个提交都是「该 xray 版本的最后状态」：
#   5eeaf1c 是 helloworld 把 xray 升到 25.1.1 之前的最后一个提交
#   521e396 是 helloworld 把 xray 升到 24.10.16 之前的最后一个提交
#   （比各自的升版提交多带一个月的 ssr-plus 修复，xray 包本身没变）
#
# 差别提醒：
#   - 1.8.24 配套 ssr-plus 188，订阅解析不支持 hy2://（只能手动填 hysteria2）
#   - 24.12.31 配套 189，支持 hy2:// 订阅
#
# ⚠ SHA 必须写满 40 位，不能写短 SHA：
#   scripts/feeds 对 ^xxx 的处理是 `git fetch --depth=1 origin xxx`，
#   短 SHA 会被 git 当成 ref 名去找 refs/heads/f92f566，
#   报 "fatal: couldn't find remote ref f92f566"，
#   clone 会退回默认分支 master（xray 26.x），编译期才炸。
#   40 位全 SHA 才会走「按对象拉取」，GitHub 支持。
# =============================================================

set -euo pipefail

HW_VERSION="${HW_VERSION:-24.12.31}"
HELLOWORLD_URL="https://github.com/fw876/helloworld.git"

case "$HW_VERSION" in
  24.12.31)
    HW_COMMIT="5eeaf1cd1ff120b1d41674d263ff5b69c85b3ace" ;;   # 2025-01-10，xray 24.12.31
  1.8.24)
    HW_COMMIT="521e396be6c482e4638a6fadd0a34ba3e86a94b3" ;;   # 2024-10-14，xray 1.8.24
  *)
    echo "::error::未知 HW_VERSION='${HW_VERSION}'，只支持 24.12.31 / 1.8.24"
    exit 1 ;;
esac

echo "== diy-part1: helloworld ${HW_VERSION} → ${HW_COMMIT:0:7}（${HW_COMMIT}）=="

# 幂等：重复执行不会加第二行
if grep -qE '^src-git[[:space:]]+helloworld' feeds.conf.default; then
  sed -i -E "s#^src-git[[:space:]]+helloworld.*#src-git helloworld ${HELLOWORLD_URL}^${HW_COMMIT}#" feeds.conf.default
else
  echo "src-git helloworld ${HELLOWORLD_URL}^${HW_COMMIT}" >> feeds.conf.default
fi

# 给后续步骤（build-info.txt）用；本地手动跑时没有 GITHUB_ENV，忽略即可
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "HW_VERSION=${HW_VERSION}"
    echo "HW_COMMIT=${HW_COMMIT}"
    echo "HW_COMMIT_SHORT=${HW_COMMIT:0:7}"
  } >> "$GITHUB_ENV"
fi

echo "--- feeds.conf.default ---"
grep -vE '^[[:space:]]*(#|$)' feeds.conf.default
echo "diy-part1 完成"
