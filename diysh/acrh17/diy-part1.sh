#!/bin/bash
# =============================================================
# diysh/acrh17/diy-part1.sh —— feeds 更新「之前」的钩子
#
# 运行位置：源码 clone 完成 → 本脚本 → ./scripts/feeds update -a
# 当前工作目录：/workdir/openwrt
#
# 本分支（21.02）只做一件事：把 helloworld 拉到 workflow 下拉选定的提交，
# 并注册成 feed。golang 升级和内置 ssr-plus 的替换在
# scripts/ci/post-feeds.sh 里做（feeds install 之后）。
#
# 版本与 Go 要求：
#
#   HW_VERSION   helloworld 提交    xray         Go 要求   日期
#   24.12.31     1869e7f            24.12.31     go 1.21.4 2025-01-05（默认）
#   1.8.24       521e396            1.8.24       go 1.21.4 2024-10-14
#
#   21.02 自带 golang 1.19.13，两个版本都编不过 —— post-feeds.sh 会把
#   feeds/packages/lang/golang 换成 1.21.13（来自 immortalwrt/packages@23.05）。
#   25.1.1 及以上不在本分支提供（25.1.1 要 go 1.23、25.3.31+ 要 go 1.24）。
#
# 两个提交都是「该 xray 版本的最后状态」（即升到下一个 xray 之前的最后一个提交）：
#   1869e7f 是 helloworld 把 xray 升到 25.1.1（ed7def9）之前的最后一个提交
#   521e396 是 helloworld 把 xray 升到 24.10.16（b09bf97）之前的最后一个提交
#   （比各自的升版提交多带一个月的 ssr-plus 修复，xray 包本身没变）
#
# 差别提醒：
#   - 1.8.24 配套 ssr-plus 188，订阅解析不支持 hy2://（只能手动填 hysteria2）
#   - 24.12.31 配套 189，支持 hy2:// 订阅
#
# ⚠ SHA 必须写满 40 位，而且必须是「远端真实存在」的提交：
#   - 短 SHA 会被 git 当 ref 名，报 couldn't find remote ref
#   - 上游 rebase / force-push 会把旧提交从远端丢弃。之前钉的 5eeaf1c
#     （本地旧克隆里 R24.12.31 的 tip）在 GitHub 上已经不存在，CI 只会给
#     一句 `fatal: unable to read tree (5eeaf1c...)`，很难联想到是提交没了。
#     换版本时先确认：本地 clone 一份，git cat-file -e <sha>^{commit} 能过。
# =============================================================

set -euo pipefail

HW_VERSION="${HW_VERSION:-24.12.31}"
HELLOWORLD_URL="https://github.com/fw876/helloworld.git"

case "$HW_VERSION" in
  24.12.31)
    HW_COMMIT="1869e7f23ff8b90783b426136f6fb83919f190d1" ;;   # 2025-01-05，xray 24.12.31
  1.8.24)
    HW_COMMIT="521e396be6c482e4638a6fadd0a34ba3e86a94b3" ;;   # 2024-10-14，xray 1.8.24
  *)
    echo "::error::未知 HW_VERSION='${HW_VERSION}'，只支持 24.12.31 / 1.8.24"
    exit 1 ;;
esac

echo "== diy-part1: helloworld ${HW_VERSION} → ${HW_COMMIT:0:7}（${HW_COMMIT}）=="

# ---------------------------------------------------------------
# 自己把 helloworld 拉到指定提交
#
# 为什么不交给 feeds 的 ^commit：src-git 的 init_commit 是
#   git clone <url> <dir> && git checkout -b <sha> <sha>
# 先做一次 13MB 全量克隆，SHA 失效时才报错，报的还是
# `fatal: unable to read tree (<sha>)` 这种看不出根因的信息。
# 这里直接按提交号浅取（约 4 秒），失败逐级退让，最后给出明确提示。
#
# 预先建好 feeds/helloworld 后，scripts/feeds 的 update_feed_via 会命中
# 「目录存在 + 指定了 commit」分支，跳过它自己的 clone/pull，
# 仍然正常生成本地 package index（feeds/helloworld.index）。
# ---------------------------------------------------------------
HW_DIR="feeds/helloworld"
rm -rf "$HW_DIR"
mkdir -p "$HW_DIR"
git -C "$HW_DIR" init -q
git -C "$HW_DIR" remote add origin "$HELLOWORLD_URL"

fetched=0
for depth in 1 100; do
  if git -C "$HW_DIR" fetch -q --depth="$depth" origin "$HW_COMMIT" \
     && git -C "$HW_DIR" rev-parse -q --verify "${HW_COMMIT}^{tree}" >/dev/null 2>&1; then
    fetched=1
    break
  fi
  echo "   --depth=${depth} 没取到完整对象，继续加深"
done

if [ "$fetched" -ne 1 ]; then
  echo "   改为抓取全部 refs（所有分支 + tag）"
  git -C "$HW_DIR" fetch -q --tags origin '+refs/heads/*:refs/remotes/origin/*' || true
  if ! git -C "$HW_DIR" rev-parse -q --verify "${HW_COMMIT}^{tree}" >/dev/null 2>&1; then
    echo "::error::远端不存在提交 ${HW_COMMIT}（${HW_VERSION}）"
    echo "::error::上游 rebase/force-push 会丢弃旧提交；请重新确认该版本对应的 SHA"
    exit 1
  fi
fi

git -C "$HW_DIR" -c advice.detachedHead=false checkout -q "$HW_COMMIT"

# 版本断言：pin 到错提交时立刻停，而不是编到几十分钟后才发现代理版本不对
GOT_XRAY=$(grep -m1 '^PKG_VERSION:=' "$HW_DIR/xray-core/Makefile" | sed 's/.*:=//')
echo "   xray-core: ${GOT_XRAY}（期望 ${HW_VERSION}），提交 $(git -C "$HW_DIR" rev-parse --short HEAD)"
if [ "$GOT_XRAY" != "$HW_VERSION" ]; then
  echo "::error::xray-core 实际是 ${GOT_XRAY}，与 hw_version=${HW_VERSION} 不符"
  exit 1
fi

# 注册成 feed（保留 ^commit，feeds 据此跳过自己的 git 操作）
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
