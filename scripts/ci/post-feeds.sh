#!/usr/bin/env bash
# =============================================================
# scripts/ci/post-feeds.sh —— feeds install 之后、defconfig 之前
#
# 21.02 这个分支上有两个「必须先处理掉」的坑：
#
#   1. golang 太老：21.02 的 packages feed 是 1.19.13，
#      xray 1.8.24 / 24.12.31 都要 go 1.21.4 —— 直接编必然报
#      "go.mod requires go >= 1.21.4"。
#      这里把 immortalwrt/packages@openwrt-24.10 的 golang 1.23.12 整体覆盖进
#      feeds/packages/lang/golang（5 个 *.mk + golang/ 子目录）。
#      golang/ 必须整目录替换：21.02 的 golang/patches/ 里有一条给 Go 1.19
#      准备的 lib.go 补丁，打到 1.23.12 上会 Hunk FAILED。
#
#   2. 内置代理包与 helloworld 同名：21.02 自带
#        luci feed  → luci-app-ssr-plus  187（配 xray 1.8.3）
#        packages   → xray-core          1.8.3
#      和 helloworld 的包名完全一样。两个 feed 同时装会重复定义同名包
#      （luci.mk 还会重复生成 luci-i18n-ssr-plus-zh-cn），所以先把这些
#      同名 symlink 全摘掉，再强制从 helloworld 重装。
#
# 用法: post-feeds.sh <openwrt目录>
# =============================================================

set -euo pipefail

OW="${1:-.}"
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
GO_SRC="$REPO_ROOT/patches/golang-1.23.12"
GO_DST="feeds/packages/lang/golang"

cd "$OW"

# ---------------------------------------------------------------
# 1) golang 1.19.13 → 1.23.12
# ---------------------------------------------------------------
echo "== 1) 替换 golang =="
[ -d "$GO_DST" ] || { echo "::error::找不到 $GO_DST，feeds 没更新？"; exit 1; }
for f in golang-build.sh golang-compiler.mk golang-host-build.mk golang-package.mk golang-values.mk; do
  [ -f "$GO_SRC/$f" ] || { echo "::error::缺 $GO_SRC/$f"; exit 1; }
  cp -f "$GO_SRC/$f" "$GO_DST/$f"
done
# golang/ 整个子目录一起换：21.02 的 golang/patches/001-cmd-link-... 是给 Go 1.19 的，
# 套到 1.23.12 会卡在 src/cmd/link/internal/ld/lib.go（Hunk #1 FAILED at 1515）；
# 24.10 没有 patches/，但多了 files/go-gcc-helper（Makefile 里装成交叉 gcc 包装）
[ -f "$GO_SRC/golang/Makefile" ] || { echo "::error::缺 $GO_SRC/golang/Makefile"; exit 1; }
rm -rf "$GO_DST/golang"
cp -a "$GO_SRC/golang" "$GO_DST/golang"
if [ -d "$GO_DST/golang/patches" ] && [ -n "$(ls -A "$GO_DST/golang/patches" 2>/dev/null)" ]; then
  echo "::error::golang/patches 没清干净，Go 1.23 会被旧补丁打挂"
  exit 1
fi

GO_MAJOR=$(grep -m1 '^GO_VERSION_MAJOR_MINOR:=' "$GO_DST/golang/Makefile" | sed 's/.*:=//')
GO_PATCH=$(grep -m1 '^GO_VERSION_PATCH:=' "$GO_DST/golang/Makefile" | sed 's/.*:=//')
echo "   golang: ${GO_MAJOR}.${GO_PATCH}（21.02 原本是 1.19.13）"
case "$GO_MAJOR" in
  1.2[1-9]|1.[3-9][0-9]) ;;
  *) echo "::error::golang ${GO_MAJOR} 低于 1.21，xray 编不过"; exit 1 ;;
esac

# ---------------------------------------------------------------
# 2) 摘掉与 helloworld 同名的内置包 symlink
# ---------------------------------------------------------------
echo "== 2) 摘掉同名内置包 =="
[ -d feeds/helloworld ] || { echo "::error::feeds/helloworld 不存在"; exit 1; }

removed=0
for d in feeds/helloworld/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  for link in package/feeds/*/"$name"; do
    [ -L "$link" ] || continue
    echo "   移除: ${link} -> $(readlink "$link")"
    rm -f "$link"
    removed=$((removed + 1))
  done
done
echo "   共摘掉 ${removed} 个 symlink"

# ---------------------------------------------------------------
# 3) 用 helloworld 补齐（-f 允许覆盖 core 里的同名包）
# ---------------------------------------------------------------
echo "== 3) 从 helloworld 安装 =="
./scripts/feeds install -f -a -p helloworld

# ---------------------------------------------------------------
# 4) 校验：ssr-plus / xray-core 必须指向 helloworld
# ---------------------------------------------------------------
echo "== 4) 校验 =="
for p in luci-app-ssr-plus xray-core; do
  link="$(find package/feeds -maxdepth 2 -name "$p" -type l 2>/dev/null | head -1)"
  [ -n "$link" ] || { echo "::error::$p 没装上"; exit 1; }
  tgt="$(readlink -f "$link")"
  case "$tgt" in
    */feeds/helloworld/*) echo "   ${p} -> ${tgt#*/feeds/} ✅" ;;
    *) echo "::error::$p 仍指向 ${tgt#*/feeds/}，不是 helloworld"; exit 1 ;;
  esac
done

echo "post-feeds 完成"
