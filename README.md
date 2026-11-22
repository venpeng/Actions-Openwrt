# Actions-OpenWrt ACRH17

一条 GitHub Actions 流水线，编 ASUS ACRH17（OpenWrt 机型名 `asus_rt-ac42u`，`ipq40xx/generic`）。

源码：`immortalwrt/immortalwrt`，分支 `openwrt-24.10`。

原来 `main` 上是两个 workflow，唯一差别是 LAN 网段（`192.168.1.1` 与 `192.168.11.1`），现在合并成一个，网段从下拉框选；插件也从配置里拆出来，用开关控制。

## 怎么用

`Actions` → `Build ImmortalWrt ACRH17` → `Run workflow`，三个输入：

| 输入 | 取值 | 说明 |
| --- | --- | --- |
| `lan_ip` | `1.1`（默认） / `11.1` / `all` | 网关地址。`1.1` = `192.168.1.1`，即固件默认；`11.1` = `192.168.11.1`；`all` = 两个各编一份 |
| `extra_plugins` | `true`（默认） / `false` | 是否编译 `config/extra-packages.config` 里的插件 |
| `upload_release` | `true` / `false` | `false` 只上传 Artifact，不发 Release |

## 配置怎么组织

`.config` 不再是一份死文件，每次构建现拼：

```
config/base/immortalwrt-24.10.config   基础配置：除机型符号、除额外插件之外的完整配置
config/extra-packages.config           额外插件清单（21 个符号）
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
CONFIG_PACKAGE_ttyd=y          # 依赖也写上，关闭开关时才会一起 not set
```

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
- `build-info.txt` —— 源码 / 分支 / 提交号 / 机型 / LAN 网段 / 内核版本 / 额外插件开关

排查「某个插件为什么没进去」时先看这两样，别去翻日志。

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
diysh/acrh17/diy-part1.sh               feeds 更新前（当前为空壳）
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
