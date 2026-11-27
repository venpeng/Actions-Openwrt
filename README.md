# Actions-OpenWrt ACRH17（21.02 + helloworld）

一条 GitHub Actions 流水线，编 ASUS ACRH17（OpenWrt 机型名 `asus_rt-ac42u`，`ipq40xx/generic`）。

源码：`immortalwrt/immortalwrt`，分支 **`openwrt-21.02`**（内核 5.4，LuCI 还是 Lua 版）。
代理：**helloworld 的 `luci-app-ssr-plus` + `xray-core`**，替换掉 21.02 自带的 ssr-plus 187 / xray 1.8.3。

xray 版本从下拉选：`24.12.31`（默认） / `1.8.24`。

> 三个 `*-helloworld` 分支的 CI 都只 clone **上游**仓库：`immortalwrt/immortalwrt`、
> `fw876/helloworld`、以及 `immortalwrt/packages`/`luci`、`openwrt/routing`/`telephony` 四个 feed。
> 不使用任何个人 fork（`venpeng/immortalwrt` 上的 `openwrt-23.05-fix` 只供本地构建，CI 不引用）。

## 21.02 要额外解决的两件事

这两件都在 `scripts/ci/post-feeds.sh` 里，跑在 `feeds install` 之后、`defconfig` 之前：

**① Go 工具链太老**

21.02 的 `packages` feed 里 golang 是 **1.19.13**，而：

| xray | go.mod 要求 | 1.19.13 | 1.21.13（本分支） |
| --- | --- | --- | --- |
| `1.8.24` | `go 1.21.4` | ❌ | ✅ |
| `24.12.31` | `go 1.21.4` | ❌ | ✅ |
| `25.1.1` 以后 | `go 1.23` | ❌ | 本分支不提供 |

所以仓库里带了一份 `patches/golang-1.21.13/`（取自 `immortalwrt/packages@openwrt-23.05`，
5 个 `*.mk` + 整个 `golang/` 子目录，跨分支结构通用），构建时覆盖进 `feeds/packages/lang/golang/`。
`golang/patches/` 必须一起清掉 —— 21.02 里面那条给 Go 1.19 的 lib.go 补丁打到 1.21 上会 Hunk FAILED。

引导链是 `go1.4 → go1.17.13 → go1.21.13`（三级），主机编译大约多花 12 分钟。
选 1.21.13 而不是 1.23.12：xray 上限已收到 24.12.31（只要 go 1.21.4），少一级引导就少等 8~10 分钟。

**② 内置代理包与 helloworld 同名**

21.02 自带：

| 包 | 来源 | 版本 |
| --- | --- | --- |
| `luci-app-ssr-plus` | `luci` feed | 187（配 xray 1.8.3） |
| `xray-core` | `packages` feed | 1.8.3 |

包名和 helloworld 的一模一样。两个 feed 同时装会重复定义同名包（`luci.mk` 还会重复生成
`luci-i18n-ssr-plus-zh-cn`），所以脚本先把与 helloworld 重名的 symlink 全部摘掉，
再 `./scripts/feeds install -f -a -p helloworld` 强制重装，最后校验这两个包确实指向 helloworld。

## 怎么用

`Actions` → `Build ImmortalWrt ACRH17 (21.02)` → `Run workflow`，四个输入：

| 输入 | 取值 | 说明 |
| --- | --- | --- |
| `lan_ip` | `1.1`（默认） / `11.1` / `all` | 网关地址。`11.1` = `192.168.11.1`；`all` = 两个各编一份（并行 job） |
| `hw_version` | `24.12.31`（默认） / `1.8.24` | helloworld 版本。对应提交 `1869e7f` / `521e396` |
| `extra_plugins` | `true`（默认） / `false` | 是否编译 `config/extra-packages.config` 里的插件 |
| `upload_release` | `true` / `false` | `false` 只上传 Artifact，不发 Release |

版本映射写在 `diysh/acrh17/diy-part1.sh`，都是 **40 位全 SHA**，由脚本自己按提交号浅取
（约 5 秒 / 3.3MB），不再走 `scripts/feeds` 的 `^commit`：

> ⚠ 短 SHA 会被 git 当 ref 名，直接报 `couldn't find remote ref`；
> 更隐蔽的是**上游 rebase / force-push 会把旧提交从远端丢弃**——之前钉的 `5eeaf1c`
> （本地旧克隆里 `R24.12.31` 的 tip）就是这样：`git clone` 拿不到它，CI 只给一句
> `fatal: unable to read tree (5eeaf1c...)`。换版本前先确认提交可达
> （本地 clone 后 `git cat-file -e <sha>^{commit}` 能过）。
>
> 脚本还带一道版本断言：检出后比对 `xray-core/Makefile` 的 `PKG_VERSION` 与 `hw_version`，
> 不一致立即失败，不会等编到几十分钟后才发现代理版本不对。

### 为什么同一个 SHA 在 21.02 会挂、23.05 / 24.10 却能过

`scripts/feeds` 对 `^commit` 的实现不同（都以 `src-git` 为例）：

| | `init_commit` |
| --- | --- |
| 21.02 | `git clone '<url>' '<dir>' && git checkout -b '<sha>' '<sha>'` |
| 23.05 / 24.10 | `git clone --depth 1 '<url>' '<dir>' && git fetch --depth=1 origin '<sha>' && git checkout '<sha>'` |

`git clone` 只下载**各 ref 可达**的对象。上游 rebase 之后 `5eeaf1c` 成了悬空提交：
21.02 的全量克隆里没有它，checkout 直接报 `unable to read tree`；
23.05 / 24.10 多一句 `git fetch --depth=1 origin <sha>`，是按对象编号直接向服务器取，
GitHub 只要还没 GC 就能给（`allowAnySHA1InWant`），所以那两个分支当时能过。

**能过不等于正确**：悬空对象随时会被清理，上游一次 `git gc` 之后它们会以同样的方式挂。
所以三个分支统一钉到 `1869e7f`（在 `master` 上可达），21.02 还额外自己做预拉取并断言版本。

## 与 23.05 / 24.10 分支的差异

| 项 | 21.02 | 23.05 | 24.10 |
| --- | --- | --- | --- |
| 内核 | 5.4 | 5.15 | 6.6 |
| LuCI | Lua（原生支持 helloworld） | JS + `luci-compat` | JS + `luci-compat` |
| 默认 Go | 1.19.13 → 脚本换 1.21.13 | 1.21.13 | 1.23.12 |
| 防火墙 | firewall3 + iptables | firewall4 + nftables | firewall4 + nftables |
| UPnP | `miniupnpd` | `miniupnpd-nftables` | `miniupnpd-nftables` |
| xray 上限 | 24.12.31 | 24.12.31 | 25.1.1 |
| 内置代理冲突 | **有**（ssr-plus 187 / xray 1.8.3） | 无 | 无 |

## 配置怎么组织

```
config/base/immortalwrt-21.02.config   基础配置（本地 menuconfig 导出，已剥离机型/插件/代理符号）
config/extra-packages.config           额外插件清单（26 项）
feeds.conf                             21.02 的四个 feed，改成浅克隆
scripts/ci/gen-config.sh               基础配置 + 机型 + 插件 → openwrt/.config
scripts/ci/post-feeds.sh               golang 升级 + 内置代理替换
scripts/ci/verify-config.sh            defconfig 后校验机型/插件/Go/xray 版本
diysh/acrh17/diy-part1.sh              feeds 更新前：加 helloworld feed 并钉提交
diysh/acrh17/diy-part2.sh              feeds 更新后：网关 + WiFi SSID
自编译插件配置.txt                      插件菜单路径备忘（人工参考，CI 不读）
```

`gen-config.sh` 干四件事：拷基础配置 → 剔掉 `CONFIG_TARGET_*_DEVICE_*` / `PROFILE` /
`MULTI_PROFILE` / `DEFAULT_*` → 追加机型符号 → 按开关逐条写插件。

## 改配置

**加 / 减插件**：只改 `config/extra-packages.config`，一行一条：

```
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_ttyd=y                         # 依赖也写上，关闭开关时才会一起 not set
# CONFIG_PACKAGE_xxx_INCLUDE_MosDNS is not set # 显式关闭 defconfig 会自动打开的项
```

**改其它选项**：本地 `make menuconfig` 导出 `.config` 覆盖
`config/base/immortalwrt-21.02.config` 即可（脚本会再兜底清一遍机型/插件/代理符号）。

## 本地验证

```bash
mkdir -p /tmp/ow/target/linux/ipq40xx/image
curl -sL https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-21.02/target/linux/ipq40xx/image/generic.mk \
  > /tmp/ow/target/linux/ipq40xx/image/generic.mk

bash scripts/ci/gen-config.sh /tmp/ow config/base/immortalwrt-21.02.config true
bash scripts/ci/verify-config.sh /tmp/ow true     # 没有 feeds 时会有两条 warning，属正常
```

## 参考配置：和你的 menuconfig 对比

`config/reference/menuconfig-21.02.config` 是本地 `make menuconfig` 的原始导出
（7274 行、337 个 `=y` 包），只作对照，CI 不读它。实际参与构建的是
`config/base/immortalwrt-21.02.config`（剥掉了机型/插件/ssr-plus 符号）。

编译完成后，从产物里取出 `config-immortalwrt-21.02-<LAN_IP>-<日期>.config`，两种比法：

```bash
# 只看「装了哪些包」
diff <(grep -E '^CONFIG_PACKAGE_.*=y$' config/reference/menuconfig-21.02.config | sort) \
     <(grep -E '^CONFIG_PACKAGE_.*=y$' config-immortalwrt-21.02-1.1-20261127.config | sort)

# 看全部差异（默认项会很多）
diff -u config/reference/menuconfig-21.02.config config-immortalwrt-21.02-1.1-20261127.config | less
```

预期的差异来源：

- 产物里的 `.config` 是 `make defconfig` 之后的状态，会多出几百行默认项（`DEFAULT_PACKAGES` 展开的结果）
- `CONFIG_TARGET_*_DEVICE_*`、`CONFIG_TARGET_PROFILE`、`CONFIG_MULTI_PROFILE` 是 `gen-config.sh` 追加的
- base 里剥掉的 `CONFIG_DEFAULT_*` 会重新出现
- `luci-app-ssr-plus*` / `xray-core` 来自 helloworld feed（你那份菜单里还是 21.02 自带的 187 / 1.8.3）

## 产物

Artifact：`OpenWrt_firmware_<机型>_<日期时间>_<LAN_IP>`，同时发 Release。

包里除固件外还带：

- `config-immortalwrt-21.02-<LAN_IP>-<日期>.config` —— 展开后的完整 `.config`
- `build-info.txt` —— 源码 / 分支 / 提交 / 机型 / xray 版本与提交 / **Go 工具链版本** / LAN 网段 / 额外插件开关

## 体积与风险

- 这份基础配置展开后 **330 个包**（23.05 那份 281），rootfs 上限只有 19.5MB，
  第一次构建很可能会撞 `Image too big`。真撞了先把 `extra_plugins` 设 `false`，
  再逐个加回来；最占地方的是 samba4（约 3MB）和 usb-printer。
- 21.02 已停止维护（内核 5.4 不再有安全更新）。这个分支适合「老机器维持现状」，
  不适合当长期方案。
- 21.02 的 ipq40xx 内核补丁可能和 5.4.255 对不上（23.05 就在 401 补丁上栽过）。
  如果构建卡在 `Applying ... patches-5.4/xxx.patch` + `Hunk #N FAILED`，
  把补丁名发出来，按 23.05 同样的方式处理：换成上游 openwrt 23.05 已刷新的同名补丁。

## License

[MIT](LICENSE) © [P3TERX](https://p3terx.com)
