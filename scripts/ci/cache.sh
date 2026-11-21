#!/usr/bin/env bash
# =============================================================
# scripts/ci/cache.sh —— 构建缓存助手
#
# 缓存什么：
#   staging_dir/host*     host 工具 + hostpkg（go / python / cmake 这类）
#   staging_dir/tool*     交叉工具链（aarch64 gcc / musl）
#   dl/                   源码包下载缓存（另一条 key，按周复用）
#
# key 结构（前缀只由「源码 + 分支」决定，机型不进 key）：
#   工具链  mt7986-<源>-<分支>-tc-<提交号12位>      精确命中 = 同一提交编的
#          mt7986-<源>-<分支>-tc-<提交号12位>-early 工具链刚编完时的早期快照
#   下载    mt7986-<源>-<分支>-dl-<年周号>
#
# 为什么前缀不带机型：同一份源码、同一分支、同一 SoC，7 个锐捷机型用的是
# 完全相同的 host 工具和交叉工具链。机型只改 target 侧编哪些包，进 key 只会
# 让缓存变成 7 份，白占 10GB 配额。
#
# 子命令：
#   key <openwrt目录>       算前缀与两条 key（写 GITHUB_OUTPUT / GITHUB_ENV）
#   prepare <openwrt目录>   恢复缓存后让 make 认账（刷 stamp、还原 build_dir 戳、写 tmp/.build）
#   freeze <openwrt目录>    把 build_dir 里的 host 包戳冻进 staging_dir（随缓存走）
#   rollover                清理同前缀的旧代（保留本次 tc / tc-early / dl）
#   status <openwrt目录>    打印缓存体积与关键版本
# =============================================================

set -uo pipefail

CMD="${1:-}"
OW="${2:-$PWD}"

# 冻进缓存的 build_dir 戳镜像位置：staging_dir/host* 本来就在缓存路径里，
# 放这里不用改 workflow 的 path，两条通道（actions/cache / 手工导出）都能带上。
HOST_STAMP_MIRROR="staging_dir/host/.builddir-stamps"

out() {   # 写 GITHUB_OUTPUT 并回显
  echo "$1"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"
  return 0
}

env_out() {
  [ -n "${GITHUB_ENV:-}" ] && echo "$1" >> "$GITHUB_ENV"
  return 0
}

# key 里只允许 [A-Za-z0-9._-]
slug() { printf '%s' "${1:-unknown}" | tr -c 'A-Za-z0-9._-' '-'; }

cache_prefix() {
  printf 'mt7986-%s-%s' \
    "$(slug "${SOURCE_SLUG:-unknown}")" \
    "$(slug "${BRANCH_SLUG:-unknown}")"
}

# ---------------------------------------------------------------
# key —— 前缀 + 提交号；下载缓存按周
# ---------------------------------------------------------------
cmd_key() {
  cd "$OW" || { echo "::error::无法进入 $OW"; exit 1; }

  local commit prefix tc_key dl_key
  commit=$(git rev-parse HEAD 2>/dev/null) || commit=unknown
  prefix=$(cache_prefix)
  tc_key="${prefix}-tc-${commit:0:12}"
  dl_key="${prefix}-dl-$(date -u +%Y%W)"

  out "commit=$commit"
  out "prefix=$prefix"
  out "tc_key=$tc_key"
  out "dl_key=$dl_key"
  env_out "CACHE_PREFIX=$prefix"
  env_out "CACHE_TC_KEY=$tc_key"
  env_out "CACHE_DL_KEY=$dl_key"

  echo "========================================"
  echo "源码前缀 : $prefix"
  echo "上游提交 : $commit"
  echo "工具链键 : $tc_key"
  echo "下载键   : $dl_key"
  echo "========================================"
}

# ---------------------------------------------------------------
# build_dir 戳的冻结 / 还原
#
#   include/host-build.mk 里 host 包的四个戳分两处：
#     INSTALLED  staging_dir/hostpkg/stamp/.<pkg>_installed   ← 跟着缓存走
#     BUILT      build_dir/host/<pkg>/.built                  ← 不在缓存路径
#     CONFIGURED build_dir/host/<pkg>/.configured             ← 不在缓存路径
#     PREPARED   build_dir/host/<pkg>/.prepared_<md5>          ← 不在缓存路径
#   依赖链 installed ← built ← configured ← prepared。build_dir 不进缓存，
#   恢复后 built 这层就没了，make 认为没编过 → golang / rust 整条自举重来
#   （实测多花 20~40 分钟）。
#
#   所以只把「戳」复制进缓存，不复制内容：产物已经在 staging_dir 里，
#   缺的只是「我做过了」这个证据。戳全是 0 字节，100 来个包不到 10KB。
# ---------------------------------------------------------------
cmd_freeze() {
  cd "$OW" || { echo "::error::无法进入 $OW"; exit 1; }

  rm -rf "$HOST_STAMP_MIRROR"
  mkdir -p "$HOST_STAMP_MIRROR"

  local n=0 rel
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    mkdir -p "$HOST_STAMP_MIRROR/$(dirname "$rel")"
    cp -a "$f" "$HOST_STAMP_MIRROR/$rel" 2>/dev/null || continue
    n=$((n + 1))
  done < <(find build_dir/host build_dir/hostpkg \
             -maxdepth 2 -type f \
             \( -name '.prepared*' -o -name '.configured' -o -name '.built' \) \
             -print0 2>/dev/null)

  echo "已冻结 build_dir 戳 ${n} 个（$(du -sh "$HOST_STAMP_MIRROR" 2>/dev/null | cut -f1)）"
  if [ "$n" -eq 0 ]; then
    echo "::warning::一个戳都没找到 —— build_dir 可能已被清理，下一轮 host 包仍会重编"
  fi
}

thaw_host_stamps() {
  [ -d "$HOST_STAMP_MIRROR" ] || return 0

  local n=0 rel
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    mkdir -p "$(dirname "$rel")"
    cp -a "$HOST_STAMP_MIRROR/$rel" "$rel" 2>/dev/null || continue
    n=$((n + 1))
  done < <(cd "$HOST_STAMP_MIRROR" && find . -type f -print0)

  if [ "$n" -gt 0 ]; then
    echo "已还原 build_dir 戳 ${n} 个 —— 这些 host 包 make 会跳过，不再自举 go/rust"
  else
    echo "::warning::戳镜像存在但还原 0 个，本轮 host 包仍会重编"
  fi
}

# ---------------------------------------------------------------
# prepare —— 恢复缓存后让 make 认账
#
# 只刷「非 target」的 stamp：host / hostpkg / toolchain 是宿主侧产物，
# 恢复后本就该当成装好了；target-* 的 stamp 是固件包安装标记，不能碰，
# 否则这次改动过的包会被当成已安装而不重编。
# ---------------------------------------------------------------
cmd_prepare() {
  cd "$OW" || { echo "::error::无法进入 $OW"; exit 1; }

  # 顺序不能反：先还原 build_dir 的旧戳，再把 installed 刷成「现在」，
  # installed 才会比 built 新，make 不会重跑 install。
  thaw_host_stamps

  local nstamp=0
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    find "$d" -type f -exec touch {} + 2>/dev/null || true
    nstamp=$(( nstamp + $(find "$d" -type f 2>/dev/null | wc -l) ))
  done <<< "$(find staging_dir -type d -name stamp -not -path '*target*' 2>/dev/null)"

  # ⚠ 不要 touch tools/stamp-compile / toolchain/stamp-compile：
  #   它们是 make 变量不是文件，造同名文件会让 timestamp.pl 判定源码变了，
  #   每轮白重编 tools 与 toolchain（+13 分钟 × 2）。
  mkdir -p tmp
  echo "1" > tmp/.build

  find staging_dir -maxdepth 1 -type d -exec touch {} + 2>/dev/null || true

  echo "已刷新 stamp ${nstamp} 个（不含 target）"
  echo "已写入 tmp/.build"

  # ---- 落地校验：缓存到底能不能用 ----
  local host_ok=true toolchain_ok=true
  if [ ! -x staging_dir/host/bin/gcc ]; then
    host_ok=false
    echo "::warning::缓存里没有 staging_dir/host/bin/gcc —— 清空 host 缓存，本轮重编 host 工具"
    rm -rf staging_dir/host staging_dir/hostpkg
  fi

  # 交叉工具链的 gcc 名字随架构变，用通配找
  if ! ls staging_dir/toolchain-*/bin/*-gcc >/dev/null 2>&1; then
    toolchain_ok=false
    echo "::warning::缓存里没有交叉工具链 gcc —— 清空 toolchain 缓存，本轮重编工具链"
    rm -rf staging_dir/toolchain-*
  fi

  if [ "$host_ok" = true ] && [ "$toolchain_ok" = true ]; then
    echo "✅ 缓存自检通过：host 与交叉工具链都在位"
    ls -d staging_dir/toolchain-* 2>/dev/null | sed 's/^/    /'
    [ -x staging_dir/host/bin/gcc ] && echo "    host gcc: $(staging_dir/host/bin/gcc --version 2>/dev/null | head -1)"
  fi

  out "host_ok=$host_ok"
  out "toolchain_ok=$toolchain_ok"
}

# ---------------------------------------------------------------
# rollover —— 每个前缀只留当前这一代
#   保留：<prefix>-tc-<commit>、<prefix>-tc-<commit>-early、<prefix>-dl-<本周>
#   删除：同前缀下的其它条目（上一代工具链、上周的 dl）
# ---------------------------------------------------------------
cmd_rollover() {
  local prefix="${PREFIX:-${CACHE_PREFIX:-}}"
  local repo="${GITHUB_REPOSITORY:-}"
  local keep_tc="${TC_KEY:-${CACHE_TC_KEY:-}}"
  local keep_dl="${DL_KEY:-${CACHE_DL_KEY:-}}"

  [ -n "$prefix" ] || { echo "::warning::缺 CACHE_PREFIX，跳过轮换"; exit 0; }
  [ -n "$repo" ]   || { echo "::warning::缺 GITHUB_REPOSITORY，跳过轮换"; exit 0; }
  # 没有本次 key 就不知道「该留哪一代」，此时一旦执行就会把同前缀全删掉
  [ -n "$keep_tc" ] || { echo "::warning::缺 TC_KEY，跳过轮换（避免误删全部同前缀缓存）"; exit 0; }
  command -v gh >/dev/null 2>&1 || { echo "::warning::无 gh，跳过轮换"; exit 0; }

  # 本次要保留的白名单。
  # ⚠ 只留完整版 tc + 本周 dl：-early 是工具链刚编完的临时快照，
  #   完整版一存下来它就没用了，留着等于每前缀多占一倍配额。
  #   （只有在编译被 cancel、完整版没存成时它才有价值，那种情况也不会跑轮换。）
  local keep=" ${keep_tc} ${keep_dl} "

  # 当前 key 还没落库时不要动任何东西，否则可能删掉唯一一份
  local found=0
  for _ in 1 2 3 4 5; do
    if gh cache list -R "$repo" --key "$keep_tc" --limit 100 --json key --jq '.[].key' 2>/dev/null \
         | grep -qx "$keep_tc"; then
      found=1; break
    fi
    sleep 3
  done
  if [ "$found" -ne 1 ]; then
    echo "当前工具链 key 尚不可用（save 可能还没落库），跳过本轮轮换"
    exit 0
  fi

  echo "保留:${keep}"
  local deleted=0 failed=0
  while IFS=$'\t' read -r id k; do
    [ -n "${id:-}" ] || continue
    case "$keep" in *" $k "*) continue ;; esac
    echo "删除旧缓存: $k (id=$id)"
    if gh cache delete "$id" -R "$repo" 2>/dev/null; then
      deleted=$((deleted + 1))
    else
      failed=$((failed + 1))
      echo "::warning::删除失败 $k"
    fi
  done <<< "$(gh cache list -R "$repo" --key "${prefix}-" --limit 100 \
              --json id,key --jq '.[] | [.id,.key] | @tsv' 2>/dev/null || true)"

  echo "轮换完成：删除 ${deleted} 个，失败 ${failed} 个"
}

# ---------------------------------------------------------------
# status —— 体积与关键版本，落进 step summary
# ---------------------------------------------------------------
cmd_status() {
  cd "$OW" 2>/dev/null || { echo "::warning::无法进入 $OW"; exit 0; }

  echo "=== 缓存目录体积 ==="
  for d in staging_dir/host staging_dir/hostpkg staging_dir/toolchain* dl; do
    [ -e "$d" ] || continue
    printf '%-46s %s\n' "$d" "$(du -sh "$d" 2>/dev/null | cut -f1)"
  done

  echo ""
  echo "=== 工具链版本 ==="
  [ -x staging_dir/host/bin/gcc ] && echo "host gcc : $(staging_dir/host/bin/gcc --version 2>/dev/null | head -1)"
  for g in staging_dir/toolchain-*/bin/*-gcc; do
    [ -x "$g" ] && echo "cross gcc: $("$g" --version 2>/dev/null | head -1)  ($g)"
  done
  [ -x staging_dir/host/bin/go ] && echo "go       : $(staging_dir/host/bin/go version 2>/dev/null)"

  echo ""
  echo "=== 标记 ==="
  for f in tmp/.build; do
    printf '%-20s %s\n' "$f" "$([ -e "$f" ] && echo 有 || echo 无)"
  done
  printf '%-20s %s\n' "build_dir 戳镜像" \
    "$([ -d "$HOST_STAMP_MIRROR" ] && echo "$(find "$HOST_STAMP_MIRROR" -type f | wc -l) 个" || echo 无)"

  echo ""
  echo "=== 提交 ==="
  git rev-parse HEAD 2>/dev/null || echo "（非 git 仓库）"
}

case "$CMD" in
  key)      cmd_key ;;
  prepare)  cmd_prepare ;;
  freeze)   cmd_freeze ;;
  rollover) cmd_rollover ;;
  status)   cmd_status ;;
  *)
    echo "用法: $0 {key|prepare|freeze|rollover|status} <openwrt目录>" >&2
    exit 1
    ;;
esac
