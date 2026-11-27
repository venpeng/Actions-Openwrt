#!/bin/bash
# =============================================================
# diysh/acrh17/diy-part1.sh —— feeds 更新「之前」的钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 本分支只做一件事：把 helloworld 加成 feed，按 workflow 下拉的
# HW_VERSION 固定到对应的提交。
#
# 为什么要钉提交：
#   immortalwrt 24.10 的 golang 是 1.23.12，而 helloworld 从 xray
#   25.3.31 起要求 go 1.24、26.x 要求 go 1.26 —— 24.10 上编不过。
#   能编的只有 24.12.31 和 25.1.1 这两条版本线：
#
#     HW_VERSION   helloworld 提交   xray        要求      日期
#     24.12.31     1869e7f           24.12.31    go 1.21.4 2025-01-05
#     25.1.1       f92f566           25.1.1      go 1.23   2025-03-30（默认）
#
#   两个都是「升到下一个 xray 之前的最后一个提交」，且在 master 上可达。
#
# ⚠ SHA 必须写满 40 位，而且必须是远端仍然可达的提交：
#   - 短 SHA 会被 git 当成 ref 名，报 couldn't find remote ref，
#     clone 退回默认分支 master（xray 26.x），编译期才炸
#   - 上游 rebase / force-push 会丢弃旧提交：原来钉的 5eeaf1c（本地旧克隆里
#     R24.12.31 的 tip）在 GitHub 上已不在任何 ref 上，src-git 的
#     「全量 clone + checkout <sha>」拿不到它，只报
#     `fatal: unable to read tree (5eeaf1c...)`，看不出根因。
#     换版本前先在本地 clone 里 `git cat-file -e <sha>^{commit}` 确认。
# =============================================================

set -euo pipefail

HW_VERSION="${HW_VERSION:-25.1.1}"
HELLOWORLD_URL="https://github.com/fw876/helloworld.git"

case "$HW_VERSION" in
  25.1.1)
    HW_COMMIT="f92f56614c059d63941e04f37f18aea18e001868" ;;   # R25.1.1  tip，2025-03-30
  24.12.31)
    HW_COMMIT="1869e7f23ff8b90783b426136f6fb83919f190d1" ;;   # 2025-01-05，xray 24.12.31
  *)
    echo "::error::未知 HW_VERSION='${HW_VERSION}'，只支持 25.1.1 / 24.12.31"
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
