#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default


# ---------------------------------------------------------
# 补回 libffi —— python3(3.14) 的 _ctypes 硬性需要
#
# 背景（2026-10-20 实测）：
#   1) CPython 自 3.11 起删除了 --with-system-ffi 选项，官方措辞是
#      "libffi must now always be supplied by the system on all
#      non-Windows platforms"。也就是说不管传不传这个参数，
#      _ctypes 都会 #include <ffi.h>。
#   2) 但 ponwrt 源码树的 package/libs/libffi/Makefile 不存在
#      （pbs05/ponwrt 与 qwe3017/ponwrt 都是 404），
#      packages feed 里也早已迁走（immortalwrt/packages 的
#      libs/libffi 同样是 404）。结果整棵树没有 libffi：
#      编译日志里一行 libffi 都没有，staging_dir 下没有
#      ffi.h / libffi.pc。
#   3) python3 的 Makefile 还只给 HOST_BUILD_DEPENDS 写了 libffi/host，
#      target 侧 python3-light 的 DEPENDS 里没有 +libffi，
#      python3-ctypes 子包才有 —— 依赖指向不存在的包会被 defconfig
#      静默丢弃，python3 照样进编译列表，编到 _ctypes.c 才炸：
#        ./Modules/_ctypes/_ctypes.c:119:10: fatal error: ffi.h:
#        No such file or directory
#      → make[5] Error 1 → package/feeds/packages/python3 failed to build
#        → world Error 2
#
# 处理：从 immortalwrt 基座取现成的包定义（3.4.7，自带 Build/InstallDev，
#       会把 ffi.h / ffitarget.h / fficonfig.h / libffi.pc 装进
#       staging_dir/target-*/usr/{include,lib/pkgconfig}），
#       再给 python3 补一条 target 侧构建依赖保证编译顺序。
#
# ⚠ 必须放在 prepare-tmpinfo 之前：目录要被扫进索引，
#    PKG_BUILD_DEPENDS 也要在 tmpinfo 里生效。
# ---------------------------------------------------------
FFI_DIR="package/custom/libffi"
if [ ! -d "$FFI_DIR" ]; then
  echo "--- 补回 libffi（python3 _ctypes 依赖，源码树中缺失）---"
  mkdir -p "$FFI_DIR"
  if curl -fsSL --retry 3 --max-time 60 \
       https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/package/libs/libffi/Makefile \
       -o "$FFI_DIR/Makefile"; then
    echo "✅ 已补回 libffi ($(grep -m1 '^PKG_VERSION' "$FFI_DIR/Makefile" 2>/dev/null))"
  else
    echo "::error::libffi 包定义下载失败 —— python3 的 _ctypes 会因缺 ffi.h 编译失败"
    rm -rf "$FFI_DIR"
  fi
else
  echo "已存在，跳过: $FFI_DIR"
fi

# python3 只声明了 libffi/host，target 侧没声明，补一条确保 libffi 先编译
PY3MK="feeds/packages/lang/python/python3/Makefile"
if [ -f "$PY3MK" ] && ! grep -q 'PKG_BUILD_DEPENDS:=bluez libffi' "$PY3MK"; then
  sed -i 's|^PKG_BUILD_DEPENDS:=bluez|PKG_BUILD_DEPENDS:=bluez libffi|' "$PY3MK"
  echo "✅ python3 已补 libffi 构建依赖（PKG_BUILD_DEPENDS，保证先编 libffi）"
fi
