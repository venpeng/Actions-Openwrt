# Actions-OpenWrt ACRH17（23.05 + helloworld）

一条 GitHub Actions 流水线，编 ASUS ACRH17（OpenWrt 机型名 `asus_rt-ac42u`，`ipq40xx/generic`）。

源码：`immortalwrt/immortalwrt`，分支 **`openwrt-23.05`**（内核 5.15）。
代理内核：**helloworld（`luci-app-ssr-plus` + `xray-core`）**，替代原来的 homeproxy。
xray 版本从下拉选：`24.12.31`（默认）或 `1.8.24`。

从 `acrh17-helloworld`（24.10）切出来的姊妹分支，差别只有两处：源码分支换成 23.05，
以及 xray 上限降到 24.12.31（23.05 的 Go 只有 1.21.13）。插件清单、机型、脚本逻辑完全一致。

## 怎么用

`Actions` → `Build ImmortalWrt ACRH17 (23.05)` → `Run workflow`，四个输入：

| 输入 | 取值 | 说明 |
| --- | --- | --- |
| `lan_ip` | `1.1`（默认） / `11.1` / `all` | 网关地址。`1.1` = `192.168.1.1`，即固件默认；`11.1` = `192.168.11.1`；`all` = 两个各编一份 |
| `hw_version` | `24.12.31`（默认） / `1.8.24` | helloworld 版本。`24.12.31` → `5eeaf1c`（2025-01-10）；`1.8.24` → `521e396`（2024-10-14） |
| `extra_plugins` | `true`（默认） / `false` | 是否编译 `config/extra-packages.config` 里的插件（代理就在这里面） |
| `upload_release` | `true` / `false` | `false` 只上传 Artifact，不发 Release |

## 为什么只有这两个版本

决定性因素是 Go 版本 —— 23.05 的 `packages` feed 里 golang 是 **1.21.13**：

| xray 版本 | go.mod 要求 | 23.05（1.21.13） |
| --- | --- | --- |
| `1.8.24` | `go 1.21.4` | ✅ |
| `24.12.31` | `go 1.21.4` | ✅ |
| `25.1.1` | `go 1.23` | ❌ |
| `25.3.31` 以后 | `go 1.24` | ❌ |
| `26.x` | `go 1.26` | ❌ |

24.12.31 的依赖也全部落在 1.21 以内（`xtls/quic-go` 分支 = 1.21、`sing 0.5.1` = 1.20、
`grpc 1.67.1` = 1.21），所以它能编；再往上一档就不行了。

两个提交都是「该 xray 版本的最后状态」，不是随便挑的散提交：

| `hw_version` | 提交 | 日期 | 配套 | 说明 |
| --- | --- | --- | --- | --- |
| `24.12.31` | `5eeaf1c` | 2025-01-10 | ssr-plus 189 / mosdns 5.3.3 / v2ray 5.22.0 | 下一个提交才升到 25.1.1 |
| `1.8.24` | `521e396` | 2024-10-14 | ssr-plus 188 / v2ray 5.16.1 | 下一个提交才升到 24.10.16 |

之所以取「升版提交的父提交」而不是升版那一提交，是为了白拿期间的应用层修复
（例如 1.8.24 那条线里有两笔 REALITY 订阅不读 `tls_flow` 的修复），
而 `xray-core/` 目录本身在这段时间没有任何改动。

> helloworld 上游没有 1.8.24 / 24.12.31 之类的版本分支，也没有对应 tag
> （tag 从 2026 年的 `v196.x` 才开始打），所以只能钉提交号。

> ⚠ **SHA 必须写满 40 位**。`scripts/feeds` 对 `^xxx` 的处理是
> `git fetch --depth=1 origin xxx`，短 SHA 会被 git 当成 ref 名去找 `refs/heads/5eeaf1c`，
> 直接报 `fatal: couldn't find remote ref 5eeaf1c`（clone 退回默认分支 master，
> xray 变成 26.x，编译期才炸）。40 位全 SHA 才会走「按对象拉取」，GitHub 支持。

映射写在 `diysh/acrh17/diy-part1.sh`；CI 里有两道保险 —— `Update feeds` 打印实际 xray 版本，
`verify-config.sh` 在 defconfig 后再核对一次，不一致就告警。

**1.8.24 的一个已知短板**：配套的 ssr-plus 188 订阅解析不支持 `hy2://`，hysteria2 只能手动填节点。
没有特别理由就用默认的 24.12.31。

## 配置怎么组织

`.config` 不是死文件，每次构建现拼：

```
config/base/immortalwrt-23.05.config   基础配置（种子，只写必须指定的项）
config/extra-packages.config           额外插件清单
scripts/ci/gen-config.sh               基础配置 + 机型 + 插件 → openwrt/.config
scripts/ci/verify-config.sh            defconfig 之后校验，30 秒内暴露静默丢包
```

`gen-config.sh` 干四件事：

1. 拷基础配置
2. 剔掉 `CONFIG_TARGET_*_DEVICE_*` / `CONFIG_TARGET_PROFILE` / `CONFIG_TARGET_MULTI_PROFILE` / `CONFIG_DEFAULT_*`
3. 追加机型符号 `CONFIG_TARGET_ipq40xx_generic_DEVICE_asus_rt-ac42u=y`
4. 按 `extra_plugins` 逐条写入插件：`true` 写 `=y`，`false` 写 `# CONFIG_x is not set`

机型符号必须追加而不是留在文件里 —— 否则换机型要改配置文件；而且 defconfig 会静默丢弃源码树里不存在的设备符号、回落到子目标默认机型，编出来是别的机器的固件。所以 `verify-config.sh` 在 defconfig 后硬性检查这一点。

### 为什么 23.05 的 base 是「种子」而不是完整 .config

24.10 分支用的是 7000 行 menuconfig 导出的完整配置，直接抄到 23.05 会有大量符号对不上，
被 defconfig 静默丢掉。而 immortalwrt 23.05 的默认包本来就够用（`include/target.mk`）：

- `DEFAULT_PACKAGES.router` → `dnsmasq-full` / `firewall4` / `nftables` / `ppp`
- `DEFAULT_PACKAGES.tweak` → `luci` / `luci-compat` / `luci-lib-ipkg` / `luci-app-opkg` / `default-settings-chn`
- `ipq40xx` 的 `target.mk` → `kmod-ath10k-ct` / `wpad-openssl` / `autocore` / `automount` / `luci-app-cpufreq`

所以种子只写：目标平台、中文界面、主题、`dnsmasq-full`、bash/curl/jq，其余交给 `make defconfig`。

首次构建的产物里带展开后的完整 `.config`，确认没问题后可以整份拷回来覆盖
`config/base/immortalwrt-23.05.config`（脚本带兜底清理，混进机型符号也不怕）。

## 改配置的两种姿势

**加 / 减插件**：只改 `config/extra-packages.config`，一行一条：

```
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_ttyd=y                        # 依赖也写上，关闭开关时才会一起 not set
# CONFIG_PACKAGE_xxx_INCLUDE_MosDNS is not set # 这种「显式关闭」也认
```

第三种写法专门用来对付 **defconfig 会自己打开的选项**（比如 ssr-plus 的 MosDNS 在
arm/aarch64 上默认 `=y`）。只写 `=y` 的条目在开关关闭时会被改成 `not set`；
`# ... is not set` 的条目无论开关如何都保持关闭。

**改其它选项**：本地 `make menuconfig` 导出完整 `.config`，直接覆盖
`config/base/immortalwrt-23.05.config` 即可；或者直接用产物里那份 `.config`。

## 本地先验证再推送

不用等 CI 跑几十分钟，本地造个假源码树就能验脚本逻辑：

```bash
mkdir -p /tmp/ow/target/linux/ipq40xx/image
curl -sL https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-23.05/target/linux/ipq40xx/image/generic.mk \
  > /tmp/ow/target/linux/ipq40xx/image/generic.mk

bash scripts/ci/gen-config.sh /tmp/ow config/base/immortalwrt-23.05.config true
bash scripts/ci/verify-config.sh /tmp/ow true     # 种子阶段无线/插件项会是 warning，属正常
```

## 产物

Artifact：`OpenWrt_firmware_<机型>_<日期时间>_<LAN_IP>`，同时发 Release（tag `<年.月.日_时分>_<机型>_<LAN_IP>`）。

带 `_1.1` / `_11.1` 后缀是为了同一台机器两个网段的固件能分清，刷错包会连不上后台。

包里除固件外还带两样：

- `config-immortalwrt-23.05-<LAN_IP>-<日期>.config` —— **展开后的 .config**，即 `make defconfig` 之后真正驱动本次编译的那份
- `build-info.txt` —— 源码 / 分支 / 提交号 / 机型 / 代理内核版本与提交 / LAN 网段 / 内核版本 / 额外插件开关

排查「某个插件为什么没进去」时先看这两样，别去翻日志。

## 256MB 内存 / 19.5MB rootfs 的取舍

ACRH17 是 IPQ4019 + 256MB 内存 + 128MB NAND，但 rootfs 分区只有约 19.5MB
（`IMAGE_SIZE := 20439364`），装不下多少东西。本分支的取舍：

- **homeproxy → ssr-plus + xray**：sing-box 常驻比 xray 高，这是换 helloworld 的主要原因
- **MosDNS 显式关闭**：它是第二个常驻 Go 进程（30~50MB），256MB 上负担很重；
  分流用 `chinadns-ng`（C 实现，几 MB）
- **只留 Xray**：v2ray-core / hysteria / tuic / naiveproxy 都是几十 MB 的 Go 二进制，全部不选
- **节点优先 chacha20-poly1305**：IPQ4019 是 Cortex-A7，没有 AES 指令加速，
  Go 的 AES-GCM 走纯软件，实测比 ChaCha20 慢

如果还嫌挤，最省事的是把 `config/extra-packages.config` 里的
`autosamba` / `luci-app-samba4` / `luci-app-usb-printer` 三组去掉 —— 它们占的 flash 比代理还多。

## lan_ip = all 是两个 job 并行

`all` 走 `strategy.matrix`，展开成 `build (1.1)` 和 `build (11.1)` 两个 job，各跑一遍完整流程，
`fail-fast: false` 保证一个挂了另一个照常出包。

之所以不是「一个 job 编完再改地址编一次」：网关地址写在 `base-files` 的 `config_generate` 里，
改完必须重做 rootfs 才会进固件，而 `make` 对 `package/*/files/` 目录的增量判断是看目录 mtime 的 ——
改文件内容不一定触发重编，第二份固件有概率还是旧地址。两个 job 各自从零走一遍，
行为和单独编一个网段完全一致，代价是 CI 分钟数翻倍。

## 目录

```
.github/workflows/openwrt-builder.yml   唯一流水线
config/base/immortalwrt-23.05.config    基础配置（种子）
config/extra-packages.config            额外插件清单
scripts/ci/gen-config.sh                生成 .config
scripts/ci/verify-config.sh             defconfig 后校验
diysh/acrh17/diy-part1.sh               feeds 更新前：按 hw_version 给 helloworld 钉提交
diysh/acrh17/diy-part2.sh               feeds 更新后：网关 + WiFi SSID
自编译插件配置.txt                       插件菜单路径备忘（人工参考，CI 不读）
```

## 关于 ttyd

`自编译插件配置.txt` 里的 `luci-app-ttyd` 已进 `config/extra-packages.config`（连带 `ttyd` 本体）。
如果你手上那份 menuconfig 导出的 `.config` 里它还是 `# CONFIG_PACKAGE_luci-app-ttyd is not set`，
直接覆盖基础配置也没关系 —— 清单优先级更高，`extra_plugins=true` 时会被写成 `=y`。

## License

[MIT](LICENSE) © [P3TERX](https://p3terx.com)
