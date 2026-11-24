# Actions-OpenWrt ACRH17（helloworld 版）

一条 GitHub Actions 流水线，编 ASUS ACRH17（OpenWrt 机型名 `asus_rt-ac42u`，`ipq40xx/generic`）。

源码：`immortalwrt/immortalwrt`，分支 `openwrt-24.10`。
代理内核：**helloworld（`luci-app-ssr-plus` + `xray-core`）**，取代原来的 homeproxy。
xray 版本从下拉选：`25.1.1`（默认）或 `24.12.31`。

从 `acrh17` 分支切出来的，唯一区别就是代理内核：ACRH17 只有 256MB 内存，跑 sing-box 吃力，
换成 xray 后常驻内存明显下降。为什么只有这两个版本可选，见下面「为什么只能选这两个版本」。

## 怎么用

`Actions` → `Build ImmortalWrt ACRH17` → `Run workflow`，四个输入：

| 输入 | 取值 | 说明 |
| --- | --- | --- |
| `lan_ip` | `1.1`（默认） / `11.1` / `all` | 网关地址。`1.1` = `192.168.1.1`，即固件默认；`11.1` = `192.168.11.1`；`all` = 两个各编一份 |
| `hw_version` | `25.1.1`（默认） / `24.12.31` | helloworld（xray 内核）版本。`25.1.1` 对应提交 `f92f566`（2025-03-30）；`24.12.31` 对应 `5eeaf1c`（2025-01-10） |
| `extra_plugins` | `true`（默认） / `false` | 是否编译 `config/extra-packages.config` 里的插件（代理就在这里面） |
| `upload_release` | `true` / `false` | `false` 只上传 Artifact，不发 Release |

## 为什么只能选这两个版本

决定性因素是 Go 版本，不是 xray 本身：

| 组件 | 要求 | immortalwrt 24.10 实际 |
| --- | --- | --- |
| `xray 24.12.31` | `go 1.21.4` | **1.23.12** ✅ |
| `xray 25.1.1` | `go 1.23` | **1.23.12** ✅ |
| `xray 25.3.31` 及以后 | `go 1.24` | ❌ |
| `xray 26.x` | `go 1.26` | ❌ |

helloworld 从 2025-04 起把 xray 提到 25.3.31，24.10 就再也编不过了。所以只能在两条版本线上选，
两个都是**上游维护的版本分支**（不是 master 上某个散提交），分支 tip 就是该版本线的最终状态：

| `hw_version` | helloworld 分支 | tip 提交 | 日期 | 配套版本 |
| --- | --- | --- | --- | --- |
| `25.1.1` | `R25.1.1` | `f92f566` | 2025-03-30 | xray 25.1.1 / mosdns 5.3.3 / v2ray 5.25.0 |
| `24.12.31` | `R24.12.31` | `5eeaf1c` | 2025-01-10 | xray 24.12.31 / mosdns 5.3.3 / v2ray 5.22.0 |

两者差 74 个提交，大部分是 ssr-plus 的订阅解析修复；xray 本身从 24.12.31 到 25.1.1 只差 8 个小提交
（两个边缘 bug + 依赖升级）。**默认选 25.1.1**，除非你想避开 2025-01 之后的改动。

映射写在 `diysh/acrh17/diy-part1.sh` 里，workflow 只传版本号。CI 里有两道保险 ——
`Update feeds` 步骤打印实际 xray 版本，`verify-config.sh` defconfig 后再核对一次，不一致就告警。

> ⚠ **SHA 必须写满 40 位**。`scripts/feeds` 对 `^xxx` 的处理是
> `git fetch --depth=1 origin xxx`，短 SHA 会被 git 当成 ref 名去找 `refs/heads/f92f566`，
> 直接报 `fatal: couldn't find remote ref f92f566`（clone 会退回默认分支 master，
> 然后 xray 变成 26.x，编译期才炸）。40 位全 SHA 才会走「按对象拉取」，GitHub 支持这种拉法。

## 配置怎么组织

`.config` 不再是一份死文件，每次构建现拼：

```
config/base/immortalwrt-24.10.config   基础配置：除机型符号、除额外插件之外的完整配置
config/extra-packages.config           额外插件清单（24 个 =y + 1 个显式关闭）
scripts/ci/gen-config.sh               基础配置 + 机型 + 插件 → openwrt/.config
scripts/ci/verify-config.sh            defconfig 之后校验，30 秒内暴露静默丢包
```

`gen-config.sh` 干四件事：

1. 拷基础配置
2. 剔掉 `CONFIG_TARGET_*_DEVICE_*` / `CONFIG_TARGET_PROFILE` / `CONFIG_TARGET_MULTI_PROFILE` / `CONFIG_DEFAULT_*`
3. 追加机型符号 `CONFIG_TARGET_ipq40xx_generic_DEVICE_asus_rt-ac42u=y`
4. 按 `extra_plugins` 逐条写入插件：`true` 写 `=y`，`false` 写 `# CONFIG_x is not set`

机型符号必须追加而不是留在文件里 —— 否则换机型要改配置文件；而且 defconfig 会静默丢弃源码树里不存在的设备符号、回落到子目标默认机型，编出来是别的机器的固件。所以 `verify-config.sh` 在 defconfig 后硬性检查这一点。

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

不用碰基础配置，也不用改 workflow。

**改其它选项**（内核、包、文件系统…）：本地 `make menuconfig` 导出完整 `.config`，直接覆盖 `config/base/immortalwrt-24.10.config` 即可。脚本带兜底清理，即使里面混进了机型符号、`CONFIG_DEFAULT_*`、插件符号，也会被正确剔除/覆盖 —— 不用手工删。

## 本地先验证再推送

不用等 CI 跑几十分钟，本地造个假源码树就能验脚本逻辑：

```bash
mkdir -p /tmp/ow/target/linux/ipq40xx/image
echo 'define Device/asus_rt-ac42u' > /tmp/ow/target/linux/ipq40xx/image/generic.mk

bash scripts/ci/gen-config.sh /tmp/ow config/base/immortalwrt-24.10.config true
grep -c '^CONFIG_PACKAGE_.*=y' /tmp/ow/.config      # 292（含 ttyd）
bash scripts/ci/verify-config.sh /tmp/ow true
```

## 产物

Artifact：`OpenWrt_firmware_<机型>_<日期时间>_<LAN_IP>`，同时发 Release（tag `<年.月.日_时分>_<机型>_<LAN_IP>`）。

带 `_1.1` / `_11.1` 后缀是为了同一台机器两个网段的固件能分清，刷错包会连不上后台。

包里除固件外还带两样：

- `config-immortalwrt-24.10-<LAN_IP>-<日期>.config` —— **展开后的 .config**，即 `make defconfig` 之后真正驱动本次编译的那份（和 `config.buildinfo` 内容相同，只是名字能认出是哪个网段编的）
- `build-info.txt` —— 源码 / 分支 / 提交号 / 机型 / 代理内核版本 / LAN 网段 / 内核版本 / 额外插件开关

排查「某个插件为什么没进去」时先看这两样，别去翻日志。

## 256MB 内存 / 19.5MB rootfs 的取舍

ACRH17 是 IPQ4019 + 256MB 内存 + 128MB NAND，但 rootfs 分区只有约 19.5MB
（`IMAGE_SIZE := 20439364`），装不下多少东西。本分支的取舍：

- **homeproxy → ssr-plus + xray**：sing-box 常驻比 xray 高，这是换分支的主要原因
- **MosDNS 显式关闭**：它是第二个常驻 Go 进程（30~50MB），256MB 上负担很重；
  分流用 `chinadns-ng`（C 实现，几 MB）
- **只留 Xray**：v2ray-core / hysteria / tuic / naiveproxy 都是几十 MB 的 Go 二进制，全部不选
- **节点优先 chacha20-poly1305**：IPQ4019 是 Cortex-A7，没有 AES 指令加速，
  Go 的 AES-GCM 走纯软件，实测比 ChaCha20 慢
- **清掉 homeproxy 时代的残留**：`avahi-dbus-daemon` / `libdbus` / `knot-resolver_dnstap`
  这些是 sing-box 那套带进来的，换 xray 后没人用，留着白占 flash 还多一个守护进程

如果还嫌挤，最省事的是把 `config/extra-packages.config` 里的
`autosamba` / `luci-app-samba4` / `luci-app-usb-printer` 三组去掉 —— 它们占的 flash 比代理还多。

## lan_ip = all 是两个 job 并行

`all` 走 `strategy.matrix`，展开成 `build (1.1)` 和 `build (11.1)` 两个 job，各跑一遍完整流程，`fail-fast: false` 保证一个挂了另一个照常出包。

之所以不是「一个 job 编完再改地址编一次」：网关地址写在 `base-files` 的 `config_generate` 里，改完必须重做 rootfs 才会进固件，而 `make` 对 `package/*/files/` 目录的增量判断是看目录 mtime 的 —— 改文件内容不一定触发重编，第二份固件有概率还是旧地址。两个 job 各自从零走一遍，行为和单独编一个网段完全一致，代价是 CI 分钟数翻倍。

`all` 只在真的要一次拿两份固件时用；平时刷一台机器选单个网段就行。

## 目录

```
.github/workflows/openwrt-builder.yml   唯一流水线
config/base/immortalwrt-24.10.config    基础配置
config/extra-packages.config            额外插件清单
scripts/ci/gen-config.sh                生成 .config
scripts/ci/verify-config.sh             defconfig 后校验
diysh/acrh17/diy-part1.sh               feeds 更新前：按 hw_version 给 helloworld 钉提交
diysh/acrh17/diy-part2.sh               feeds 更新后：网关 + WiFi SSID
自编译插件配置.txt                       插件菜单路径备忘（人工参考，CI 不读）
```

基础配置里 `CONFIG_TARGET_PREINIT_IP` 仍是 `192.168.1.1`，那是镜像预初始化阶段的临时地址，
选 `11.1` 也不影响正常使用，所以没动它。

## 关于 ttyd

`自编译插件配置.txt` 里的 `luci-app-ttyd` 已进 `config/extra-packages.config`（连带 `ttyd` 本体）。
如果你手上那份 menuconfig 导出的 `.config` 里它还是 `# CONFIG_PACKAGE_luci-app-ttyd is not set`，
直接覆盖基础配置也没关系 —— 清单优先级更高，`extra_plugins=true` 时会被写成 `=y`。

## License

[MIT](LICENSE) © [P3TERX](https://p3terx.com)
