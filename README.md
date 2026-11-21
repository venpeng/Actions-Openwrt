# Actions-OpenWrt MT7986（锐捷 X60 / X60 Pro）

一条 GitHub Actions 流水线，覆盖两台机器的固件编译：

| 设备 | 机型 profile | 说明 |
| --- | --- | --- |
| 锐捷 X60 | `ruijie_rg-x60-new-expand` | 你现用的扩容分区布局 |
| 锐捷 X60 Pro | `ruijie_rg-x60-pro-107m` | 107M 分区布局 |

源码用两份（同一套 mt7986 6.6 内核，驱动/固件版本不同）：

| 选项 | 仓库 | 特点 |
| --- | --- | --- |
| `padavanonly` | `padavanonly/immortalwrt-mt798x-6.6` | 上游原版，MTK 厂商 WiFi 驱动 |
| `yuzhii0718` | `Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly` | 二开版本，多一个 `rg-x60-new-ubi` 机型，厂商 WiFi 固件更新 |

## 怎么用

`Actions` → `Build ImmortalWrt MT7986` → `Run workflow`，七个下拉：

| 输入 | 取值 | 说明 |
| --- | --- | --- |
| `source` | `padavanonly` / `yuzhii0718` | 选源码仓库 |
| `branch` | 默认 `openwrt-24.10-6.6` | 自由填写，不存在会在第一步就报错并列出可用分支 |
| `device` | 2 个机型 / `all` | `all` = `config/devices.txt` 里列出的机型一起编（当前就是这两台） |
| `extra_plugins` | `true` / `false` | 额外插件开关，清单在 `config/extra-packages.config` |
| `scope` | `firmware` / `toolchain-only` | `toolchain-only` 只编工具链并写缓存，用于首次预热 |
| `cache` | `enable` / `disable` | `disable` = 不读不写缓存，冷编译排障用 |
| `upload_release` | `true` / `false` | `false` 只上传 Artifact，不发 Release |

产物：Artifact `firmware-<源码>-<机型>-<日期>`，同时发布到 Release（tag `<源码>-<机型>-<时间>`）。

> 首次运行建议：先跑一次 `scope=toolchain-only` 把工具链缓存建起来（约 25 分钟），
> 之后再跑 `firmware` 就只编 target 侧，省掉重复的工具链编译。

## 目录结构

```
.github/workflows/
  openwrt-builder.yml     统一主流程（源码/分支/机型/插件/缓存）
  cache-clean.yml         手动清缓存（默认 dry_run，先看再删）
config/
  base/padavanonly.config      基础 .config（不含机型符号、不含额外插件）
  base/yuzhii0718.config       同上，对应二开源码
  devices.txt                  all 要编的机型清单
  extra-packages.config        额外插件清单（改这里就能加/减插件）
scripts/ci/
  gen-config.sh           基础配置 + 机型 + 插件 → .config
  verify-config.sh        defconfig 后校验（机型丢失直接中止）
  cache.sh                缓存 key / 恢复后处理 / 冻结戳 / 轮换 / 报告
  diy-part1.sh            feeds 更新前的钩子（换源、加 feed）
  diy-part2.sh            defconfig 前的钩子（改 IP/主机名、追加配置）
```

## 设计要点

### 1. 机型不写死在配置里

`config/base/*.config` 里所有 `CONFIG_TARGET_*_DEVICE_*`、`CONFIG_DEFAULT_*` 都清掉了，
编译前由 `gen-config.sh` 按下拉重新追加：

- 单机型：`CONFIG_TARGET_mediatek_filogic_DEVICE_<机型>=y` + `CONFIG_TARGET_PROFILE="DEVICE_<机型>"`
- `all`：`CONFIG_TARGET_MULTI_PROFILE=y` + `CONFIG_TARGET_PER_DEVICE_ROOTFS=y`
  + 每个机型一行 `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<机型>=y`

`all` 编哪些机型由 `config/devices.txt` 决定（当前两台）。清单里的机型会先对着
源码树的 `target/linux/mediatek/image/*.mk` 校验一遍，对不上直接报错 ——
多机型模式里不存在的符号会被静默跳过，那个机型的固件就等于没编。

下拉只放了最常用的两个布局。要编别的布局（`-stock` / `-ubootmod` / `-ubi` 等），
把它加到 `config/devices.txt` 再选 `all`，或者临时加进 workflow 的 `device` options。

### 2. 工具链缓存（参考 Actions-OpenWrt-AN758X / OpenWRT-CI）

缓存两条 key，前缀只由「源码 + 分支」决定，机型不进 key：

```
mt7986-<源码>-<分支>-tc-<提交号12位>        staging_dir/host* + staging_dir/tool*
mt7986-<源码>-<分支>-tc-<提交号12位>-early  工具链刚编完时的早期快照
mt7986-<源码>-<分支>-dl-<年周号>            dl/ 源码包下载缓存
```

- `restore-keys` 用前缀回退，提交号变了也能拿到上一代 → 缓存几乎总能命中
- 恢复后 `cache.sh prepare` 会：还原 `build_dir` 的 host 包戳、把非 target 的 stamp 刷成当前时间、
  写 `tmp/.build` —— 少这一步 make 会认为没编过，工具链白重编一遍
- `build_dir/host/*/.built` 这些「戳」会被冻进 `staging_dir/host/.builddir-stamps` 随缓存走：
  不冻的话 go / rust 那类 host 包每轮都要重新自举（实测多 20~40 分钟）
- 工具链一编完立刻存一份 `-early`：后面最长两小时，超时被取消也不至于白编
- 自检：缓存里 `staging_dir/host/bin/gcc` 或交叉 gcc 缺失时，自动清掉对应目录重编（缓存坏了能自愈）
- `cache-rollover` 作业在构建成功后清理同前缀的旧代（含已经不用的 `-early` 快照），
  每个前缀最终只留「当前完整版 + 本周 dl」，10GB 配额不会被旧条目吃满

### 3. 额外插件

`config/extra-packages.config` 一行一个 `CONFIG_PACKAGE_<包>=y`，开关为 `true` 时逐条写入，
为 `false` 时逐条写成 `# ... is not set`。加减插件只改这个文件，不用碰 workflow。

默认清单对应 `MT7986额外插件选择.txt`：autoreboot / ddns(+cloudflare) / homeproxy(+sing-box) /
ttyd / upnp / wechatpush / wol，以及它们的直接依赖。

> `autocore-arm`、`automount` 不在开关范围内 —— 它们是固件基础功能（概览页 CPU 温度、U 盘自动挂载），
> 关掉会让 LuCI 首页报错，已固化在基础配置里。

## 改配置

**加/减插件** → 改 `config/extra-packages.config`

**加机型**（别的分区布局）→ 改 `config/devices.txt`，选 `all` 时就会一起编

**改固件默认值**（IP、主机名、SSID、打补丁）→ 改 `scripts/ci/diy-part2.sh`
（必须在 defconfig 之前写 `.config`，否则会被重新展开剔除）

**换 feeds 源 / 加第三方 feed** → 改 `scripts/ci/diy-part1.sh`

**改基础配置**（内核选项、包选择）→ 建议本地 `make menuconfig` 后，
把 `CONFIG_TARGET_*DEVICE*`、`CONFIG_DEFAULT_*`、额外插件那几行删掉，再覆盖 `config/base/<源码>.config`

**缓存吃紧** → `Actions` → `Cache Clean`，前缀填 `mt7986-padavanonly-`，先 `dry_run=true` 看清楚

## 常见坑

| 现象 | 原因 / 处理 |
| --- | --- |
| `机型 X 不在当前源码树里` | 手填了源码树里没有的机型；`all` 则是 `config/devices.txt` 里某个机型该源码没有（`-ubi` 只有 `yuzhii0718` 有） |
| `defconfig 后被丢弃`（verify 步骤硬失败） | 同上；这个检查就是为了不让你拿到「别的机器的固件」 |
| 工具链编译报错、之前又能过 | 上游 bump 了 gcc/binutils，旧缓存不匹配：先用 `cache=disable` 冷编一次，再回 `enable` |
| 缓存写不进去（`Cache size exceeded`） | 跑一次 `Cache Clean`，或把前缀填 `mt7986-` 全清后重跑 |
| `make download` 连续 3 次失败 | 上游包地址挂了或被限流，日志里搜 `failed to download`；重跑通常能过 |
| 编译在 300 分钟超时 | `all` 多机型 + 冷编译的正常边界；先 `toolchain-only` 预热，或拆成单机型编 |

## 历史

旧的四个手动 workflow（`openwrt-builder-x60.yml` / `-x60-new` / `-x60-pro` / `-x60-pro-new`）
已合并到 `openwrt-builder.yml`，原文件仍在 git 历史里可查。
原来的 `config/x60/.config`、`config/x60-pro/.config` 已清洗成 `config/base/*.config`。

## License

[MIT](LICENSE)
