# PonWrt CI — H3C HM2004-DU (AN7581) FTTR 固件

> 本仓库是 [qwe-qaq/Actions-OpenWrt-AN758X](https://github.com/qwe-qaq/Actions-OpenWrt-AN758X) 的 fork，
> **只编译一个机型：`h3c_hm2004-du`**（H3C HM2004-DU 光猫，AN7581 SoC，带 FTTR）。

源码指向 [pbs05/ponwrt](https://github.com/pbs05/ponwrt)（默认分支 `master`）。
在官方固件基础上，预装 FTTR 全家桶与一组常用插件，并支持上游推送后自动滚动重建。

## 快速开始

workflow 的 `soc` / `profile` 已固定默认值，**手动触发即可，不用改任何输入**：

1. 打开 [Actions → Build PonWrt](https://github.com/mayipashu/Actions-OpenWrt-AN758X/actions/workflows/build-ponwrt.yml)
2. 点 `Run workflow`（`soc=an7581`、`profile=h3c_hm2004-du` 是默认值）
3. 等编译完成（有缓存约 30~60 分钟，冷编译 2~3 小时），固件自动发布到 Release

> 刷机前务必用 AN758x-Stock2UBI 备份原厂 flash，刷机后恢复 PON/校准数据。

## 固件里有什么

### FTTR 全家桶（本机型核心功能）

| 包 | 说明 |
|---|---|
| `kmod-h3c-fmcs` | Micro-OLT FPGA 内核驱动 |
| `h3c-fmcs-firmware` | FPGA 比特流 `FTTR_TOP.sbit` |
| `openwrt-fttr` | fttrd 控制器 + fttrctl（Rust 包） |
| `luci-app-fttr` (+ zh-cn) | 网络 → FTTR 管理界面 |

- 后端三件套来自私有仓库 [`LazuliKao/openwrt-fttr`](https://github.com/LazuliKao/openwrt-fttr)
  （作者已共享权限），构建时需要 Secrets 里的 `PRIVATE_REPO_TOKEN` 才能拉取；
  界面包来自公开的 [`LazuliKao/luci-app-fttr`](https://github.com/LazuliKao/luci-app-fttr) 的 `package` 分支。
- 私有仓库可在触发时用 `private_repo` 输入切换（`LazuliKao/openwrt-fttr` / `mayipashu/openwrt-fttr` / `none`）。

### 预装插件（`configs/h3c_hm2004-du.config` 第 19 节，全部编进固件，刷完免安装）

| 插件 | 包 | 说明 |
|---|---|---|
| HomeProxy | `luci-app-homeproxy` + `sing-box` + `ucode-mod-digest` | 官方 feeds；ARM64 代理平台 |
| Lucky | `luci-app-lucky` + `lucky` | sirpdboy 仓库；本体用本仓库 `packages/prebuilt/lucky.arm64`（v3.0.0 实机验证版，跳过 Release 下载） |
| EasyTier | `luci-app-easytier` + `easytier` | EasyTier 仓库；本体用本仓库 `packages/prebuilt/` 三件套（core/cli/web-embed = v2.6.3-12a7b5a5，跳过 Release 下载） |
| frp 客户端 | `luci-app-frpc` + `frpc` | 官方 feeds |
| Samba4 | `luci-app-samba4` + `samba4-server` | 官方 feeds |
| FileBrowser | `luci-app-filebrowser-go` (+ zh-cn) + `filebrowser` | 官方 feeds（Go 编译） |
| SFTP 服务 | `openssh-sftp-server` | 官方 feeds；SSH 文件传输 |
| Syncthing | `luci-app-syncthing` (+ zh-cn) + `syncthing` | 官方 feeds（Go 编译）；文件同步 + 配置界面 |
| Watchcat | `luci-app-watchcat` (+ zh-cn) + `watchcat` | 官方 feeds；定时重启/断网自动重启 + 配置界面 |
| tinc | `tinc` | 官方 feeds，**无 LuCI**，命令行使用 |
| n2n | `n2n` | 官方 feeds，**无 LuCI**，命令行使用 |
| Mesh 组网 | `luci-app-mesh` + `kmod-batman-adv` `batctl-default` `luci-proto-batman-adv` `dawn` `luci-app-dawn` `umdns` | [xxosdev/luci-app-mesh](https://github.com/xxosdev/luci-app-mesh)；依赖=上游完整版（仅去掉 wpad-mesh-openssl，wpad-openssl 自带 mesh）。**batman-adv 提供多跳路由、dawn 提供 802.11k/v 漫游引导、umdns 是 DAWN 的跨 AP 邻居发现** |
| 时间控制 | `luci-app-timecontrol` | [mayipashu/luci-app-timecontrol](https://github.com/mayipashu/luci-app-timecontrol)；fork 自 kavass168，**已修上游 ACL 与匿名配置节两个界面失效 bug**（永久内置，不再构建期打补丁） |
| rtp2httpd | `rtp2httpd` + `luci-app-rtp2httpd` | 二进制用 [mayipashu/rtp2httpd](https://github.com/mayipashu/rtp2httpd)@`d7cc99a`（v3.17.2，含定制 IPTV 播放器 UI）编译；init/配置/LuCI 沿用官方 |
| 可道云 | `luci-app-kodexplorer` + `nginx-ssl` + `php8` 全栈 | 插件源码来自 [kiddin9/op-packages](https://github.com/kiddin9/op-packages)（Kwrt），固化进 `packages/luci-app-kodexplorer/`。**独立 nginx 实例听 8081**，不碰 uhttpd 的 80。**程序本体运行时下载，优先 kodbox**（唯一支持移动端 App 的版本），KodExplorer 仅作兜底 |
| jq | `jq` | 官方 feeds；JSON 命令行处理 |

### 其他（官方原有）

- PON 驱动与用户态（`airoha-pond` / `airoha-ponctl` / `luci-app-pon`）、IGMP Proxy、`luci-app-iptv` 等
- Airoha SoC 状态页（NPU/CPU/Frame Engine/PPE）、`luci-app-natmode`、`luci-app-pon-status`
- Fluent 主题、时区 Asia/Shanghai、5G WiFi 国家码 CN

## 工作流

| 工作流 | 触发 | 作用 |
|---|---|---|
| `build-ponwrt.yml` | 手动 / 上游 `repository_dispatch` | 编译 `h3c_hm2004-du` 固件并发布到 Release |
| `warm-cache.yml` | 手动 / 每周一 03:17 | 预热工具链缓存（怕首次超时用） |
| `cache-keepalive.yml` | 每 3 天 | 逐条恢复缓存，避开 `actions/cache` 7 天未访问回收 |
| `cache-clean.yml` | 手动 / 每周一 04:20 | 清理旧缓存代 |

### 常用输入项（其余用默认即可）

| 输入 | 默认 | 说明 |
|---|---|---|
| `soc` / `profile` | `an7581` / `h3c_hm2004-du` | 已固定，一般不用动 |
| `source` | `pbs05/ponwrt` | 编译源码仓库；`fork` = `qwe-qaq/ponwrt` |
| `branch` | `master` | ponwrt 源码分支 |
| `prebuilt_host` | `true` | `true` 用 runner 的 Go/Rust/LLVM，快 1.5~2.5 小时 |
| `ignore_cache` | `false` | 平时保持 `false`；改源码树结构时才需要 `true` 强刷 |
| `upload_release` | `true` | `false` 只留 Artifact 不发 Release |
| `private_repo` | `LazuliKao/openwrt-fttr` | FTTR 私有仓库；`none` 会跳过 FTTR 全家桶 |
| `fw_author` | `qwe` | 固件版本后缀作者名 |

## 自动滚动更新

- Release tag 固定为 `ponwrt-an7581-h3c_hm2004-du-<分支>`，每次构建**原地覆盖**同名 Release，
  下载链接永远指向最新固件；同机型的旧 tag 由 `delete-older-releases` 清理（保留最近 10 个）。
- 上游 `pbs05/ponwrt` 有推送时会通过 `repository_dispatch` 自动触发重建——保持默认即可，
  不需要手动跟着更新。
- 想回退/留档时：把想留的 Release 的 tag 改名（或复制资产），它就不会被下一次构建覆盖。

## 插件开关（`diy-part1.sh`）

拉取第三方插件的开关都在 `diy-part1.sh` 头部，与 `configs/h3c_hm2004-du.config` 里的
`CONFIG_PACKAGE_*=y` 一一对应。**要增删插件，两处必须一起改**：

1. 脚本里 `ADD_xxx=true/false`（控制是否 clone / 拷贝到 `package/custom`）
2. config 里 `CONFIG_PACKAGE_xxx=y` 或 `# ...is not set`（控制是否编进固件）

只改一处会不一致：只关脚本 → `make defconfig` 把 `=y` 静默剔除；只关 config → 白 clone 一个仓库。

本 fork 与上游不同的开关：

| 开关 | 包 | 说明 |
|---|---|---|
| `ADD_MESH` | `luci-app-mesh` | 克隆 xxosdev 仓库，依赖恢复为上游完整版（仅去 wpad-mesh-openssl） |
| `ADD_TIMECONTROL` | `luci-app-timecontrol` | 克隆 [mayipashu/luci-app-timecontrol](https://github.com/mayipashu/luci-app-timecontrol)（fork 自 kavass168，已内置 ACL + 命名配置节修正） |
| `ADD_RTP2HTTPD_FORK` | `rtp2httpd` | 删除 feeds 官方 3.16.0，改用 `packages/rtp2httpd/`（本人仓库源码） |
| `ADD_LUCKY` / `ADD_EASYTIER` | lucky + luci-app-lucky / easytier + luci-app-easytier | 本体和界面两个包都拷（上游只拷了界面包，本体会缺依赖）；本体 Build/Prepare 被替换为「用 `packages/prebuilt/` 预置二进制」，不下载上游 Release |

其余开关（passwall / openclash / mosdns / smartdns / tailscale / fluent 等）保留可用，
但 `h3c_hm2004-du.config` 里默认是 `#` 关闭的，按需打开即可。

## 构建缓存

首次冷编译最慢（工具链 ~1 小时 + 全包编译），成功后缓存会自动保存到两条通道：

| 通道 | 介质 | 特点 |
|---|---|---|
| ① 快通道 | `actions/cache` | 秒级，7 天无访问即回收 |
| ② 备份通道 | Release `cache-backup` 资产 | 慢（~1 GB），永不过期 |

key = `ponwrt-<源站>-<分支>-<SoC>-<prebuilt|source>-<上游提交号>`，恢复按前缀回退。
**日常构建保持 `ignore_cache=false` 就能吃到缓存**；只有上游换了工具链版本（gcc/musl 升级）
才会回到接近冷编译的耗时。

> 本 fork 只编 AN7581 一个 SoC，所以缓存只有 `an7581` 一族，比上游省一半。

## 加密加速（可选）

| 输入 | 建议 | 说明 |
|---|---|---|
| `opt_arm64ce` | `1` | AN7581 没有 `aes` 指令，走 NEON 位切片，TLS/VPN 有收益 |
| `opt_chacha` | `1` | 跑 sing-box（HomeProxy）推荐 |
| `opt_eip93` | `0` | EIP93 硬件引擎对小包更慢，保持关闭 |

## 排错

| 症状 | 先看哪里 |
|---|---|
| `defconfig` 失败 / 关键包被剔除 | 日志里 `Validate configuration` 步骤；`diy-part1.sh` 末尾有包索引校验，缺包会直接报错 |
| FTTR 包缺失 | `Setup private repo credentials` 步骤：确认 Secrets 有 `PRIVATE_REPO_TOKEN` 且对 `LazuliKao/openwrt-fttr` 有 Contents 读权限 |
| `rtp2httpd` 编译失败 | `packages/rtp2httpd/Makefile`：源码 commit、hash 与 `RTP2HTTPD_SOURCES` 清单要和 [mayipashu/rtp2httpd](https://github.com/mayipashu/rtp2httpd) 当前结构一致 |
| 缓存命中却全量重编 | `prebuilt_host` / `source` / `branch` 是否和上次一致 |
| 编译超时 | 用 `warm-cache.yml` 先预热工具链；或把不需要的插件在 config 里关掉 |

## 与上游的差异（本 fork）

1. **只编译 `h3c_hm2004-du`**，workflow 默认值已固定为该机型
2. **预装插件**（HomeProxy / Lucky / EasyTier / frpc / Samba4 / FileBrowser-go / openssh-sftp-server / Syncthing / Watchcat / tinc / n2n / Mesh+batman-adv+dawn+umdns / 时间控制 / 定制 rtp2httpd）
3. **FTTR 私有仓库默认值**改为 `LazuliKao/openwrt-fttr`
4. **lucky / easytier** 本体包也编进固件（上游只拉界面包，本体依赖会落空）；且二进制改为仓库内预置（`packages/prebuilt/`）：lucky 3.0.0、easytier 2.6.3-12a7b5a5，构建不再依赖上游 Release 下载
5. `Validate configuration` 新增「定制预装插件」硬校验，缺任何一个直接失败，不会静默编出缺功能的固件
6. 时间控制的 ACL / 配置节问题在构建期直接修复
