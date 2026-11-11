#!/bin/bash
# ================================================================
# diy-part1.sh —— 只做一件事：拉取可选插件到 package/custom
# 运行目录: ponwrt 源码根目录（feeds 安装之后、加载 .config 之前）
#
# 用法：把需要的插件开关改成 true，再到 configs/<机型>.config 里
#       把对应 "# CONFIG_PACKAGE_xxx is not set" 改成 "=y"
# ================================================================
echo "=========================================="
echo "拉取可选插件 (diy-part1.sh)"
echo "=========================================="
PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"
# ---------------------------------------------------------
# 插件开关
# 默认开启：Airoha SoC 状态页（config 里已 =y，必须拉否则 defconfig 会剔除）
#
# 温度不再用 luci-app-temp-status —— 由 autocore 的 /sbin/tempinfo 提供，
# 见 files/sbin/tempinfo（概览页「温度」行：CPU / WiFi / PON 温度 + 光功率）
# ---------------------------------------------------------
# ⚠ 下面这些包都在 configs/an7581.config 与 an7583.config 里 =y 了，
#   关掉开关会让 defconfig 把 =y 静默剔除 —— 两处必须一起改。
#
# ⚠ 标了「只用 feeds」的四个，是它们的本体（mosdns / smartdns / xray-core /
#   sing-box）feeds 里已经有同名包，第三方源再拉一份会让索引里出现两个同名
#   Package，package-metadata 按扫描顺序挑一个，行为不可预期。所以只拷 luci
#   前端，本体一律用 feeds 的。
ADD_AIROHA_NPU=true    # luci-app-airoha-npu：Airoha SoC 状态页（NPU/CPU/Frame Engine/PPE）
ADD_FLUENT=true        # luci-theme-fluent：Fluent 2 风格主题
ADD_FLUENT_LITE=false  # luci-theme-fluent-lite：轻量版（与 fluent 互斥，二选一）
ADD_FLUENT_DASH=false  # luci-mod-fluentdashboard：可选状态概览卡片
ADD_PASSWALL=true      # luci-app-passwall（只用 feeds 的依赖包）
ADD_OPENCLASH=true     # luci-app-openclash ⚠ 依赖 Ruby/Rust，编译极慢
ADD_MOSDNS=true        # luci-app-mosdns（本体只用 feeds 的 mosdns）
ADD_LUCKY=true         # luci-app-lucky（DDNS + socat）
ADD_TAILSCALE=true     # luci-app-tailscale（本体只用 feeds 的 tailscale）
ADD_OPENLIST=true      # luci-app-openlist2（alist/openlist 挂载）
ADD_SMARTDNS=true      # luci-app-smartdns（本体只用 feeds 的 smartdns）
ADD_EASYTIER=true      # luci-app-easytier（另需 kmod-tun + easytier 本体，Rust 编译较慢）
ADD_POWEROFF=true      # luci-app-poweroffdevice（关机）
ADD_OWQ_WOL=true       # luci-app-owq-wol（网络唤醒，依赖 etherwake）
ADD_WATCHDOG=true      # luci-app-watchdog（看门狗，包在子目录，需特殊处理）
ADD_TASKPLAN=true      # luci-app-taskplan（定时任务）
ADD_OAF=true           # luci-app-oaf（应用过滤，含内核模块，高风险）
ADD_LUCI_APP=true       # qwe-qaq/luci-app 仓库（monorepo）
                        #   ├─ luci-app-natmode     NAT 类型三选一（网络 → NAT 类型）
                        #   ├─ luci-app-pon-status  PON 光模块卡片（概览页「系统」下一格）
                        #   └─ luci-app-igmpproxy    IGMP Proxy 组播代理 Web 界面
# --- 2026-11 定制预装（homeproxy / tinc / frpc / n2n / samba4 / FileBrowser）---
#     这几个全部来自官方 feeds：config 里 =y 即可，不需要在这里 clone。
#     下面三个不在 feeds，需要单独拉取 / 替换源码。
ADD_MESH=true           # luci-app-mesh（xxosdev）：802.11s 组网管理
                        #   依赖按实机验证过的 devicefit 版裁剪：wpad-openssl(full)
                        #   本身已带 mesh，不再强依赖 batman-adv / dawn / umdns
ADD_TIMECONTROL=true    # luci-app-timecontrol（kavass168，apk 版）：上网时间控制
                        #   构建期顺带修好上游 ACL 与匿名配置节问题
ADD_RTP2HTTPD_FORK=true # rtp2httpd：用本人仓库 mayipashu/rtp2httpd 源码编译，
                        #   替换 feeds 官方 3.16.0（详见 packages/rtp2httpd/）
# 下面这几个开关都能被环境变量覆盖（: ${VAR:=默认} 的写法）：
# workflow 里选了「不拉私有仓库」时会注入 ADD_FTTR=false，整段直接跳过。
: "${ADD_FTTR:=true}"       # FTTR 全家桶总开关（下面的子开关都受它管）★仅 HM2004-DU
: "${ADD_FMCS:=true}"       # h3c-fmcs：Micro-OLT FPGA 内核驱动（kmod-h3c-fmcs）
: "${ADD_FTTR_TOOLS:=true}" # openwrt-fttr：fttrd 控制器 + fttrctl（Rust 包）
: "${ADD_FMCS_FW:=true}"    # h3c-fmcs-firmware：FPGA 比特流 FTTR_TOP.sbit
: "${ADD_FTTR_LUCI:=true}"  # luci-app-fttr：界面包（公开 CI 生成的 package 分支）
                            # （前三个来自 openwrt-fttr 私有仓库；界面包单独拉，见下方）

# 这四个包只对 HM2004-DU 有意义：驱动按 @(TARGET_airoha_an7581) 限定了
# target，界面和后端都围着重型 FTTR 主从设备转。workflow 会把 PROFILE
# 导出成环境变量，非 2004 机型直接跳过，不白花 clone 时间；本地手工跑
# （PROFILE 为空）按 2004 处理。
# ⚠ 不能默认成 h3c_hm2004-du：warm-cache.yml 也会调这个脚本，而它不设
#   PROFILE（缓存与机型无关），更没有私有仓库凭证那三步 —— 默认成 h3c 会让
#   它去 clone 私有仓库 openwrt-fttr，然后因 "could not read Username" 失败。
#   本地手工跑 h3c 机型时，显式 PROFILE=h3c_hm2004-du 即可。
FTTR_PROFILE="${PROFILE:-none}"

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  echo "--- git clone $url -> $dir ---"
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
  else
    git clone --depth 1 "$url" "$dir" 2>&1 | tail -3
  fi
  if [ -d "$dir" ]; then
    echo "✅ 克隆成功: $dir"
    return 0
  fi
  echo "::error::克隆失败: $url"
  return 1
}
# =========================================================
# qwe3017/luci-app —— 三个 LuCI 插件的来源
#
# 这是一个 monorepo，结构为：
#   luci-app/
#   ├── luci-app-natmode/
#   ├── luci-app-pon-status/
#   └── luci-app-igmpproxy/
# =========================================================
if [ "$ADD_LUCI_APP" = "true" ]; then
  LUCI_APP_URL="https://github.com/qwe-qaq/luci-app"
  LUCI_APP_TMP="$(mktemp -d)/luci-app"
  if ! clone "$LUCI_APP_URL" "$LUCI_APP_TMP" main; then
    echo "::error::qwe3017/luci-app 拉取失败，natmode / pon-status / igmpproxy 会被 defconfig 剔除"
    exit 1
  fi
  for p in luci-app-natmode luci-app-pon-status luci-app-igmpproxy; do
    if [ ! -f "$LUCI_APP_TMP/$p/Makefile" ]; then
      echo "::error::$LUCI_APP_TMP/$p/Makefile 不存在，包无法被索引"
      exit 1
    fi
    rm -rf "$PKG_DIR/$p"
    cp -r "$LUCI_APP_TMP/$p" "$PKG_DIR/"
    echo "✅ 已拷贝: $p  (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$p/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  done
  rm -rf "$LUCI_APP_TMP"
fi

# =========================================================
# h3c-fmcs / openwrt-fttr / h3c-fmcs-firmware —— FTTR 后端三件套 ★HM2004-DU 专属
# 源：LazuliKao/openwrt-fttr（私有仓库，作者已共享；可用 PRIVATE_REPO 覆盖）
# ⚠ 这里必须用「裸 URL」：凭证由 workflow 的 GIT_ASKPASS 在认证时回调注入，
#   千万别拼 token —— clone 的 echo 会把它打进日志。
# ⚠ 该仓库是 feed 形态（根目录直接是包目录），拷进 package/custom/ 即可。
#   内核包 / 固件包目录名 = 包名；用户态 Rust 包在 2026-11 由 h3c-fttr-tools
#   改名为 openwrt-fttr（Makefile 已显式写死 PKG_NAME:=openwrt-fttr 与
#   BuildPackage,openwrt-fttr），但源目录在不同快照里可能是 fttr /
#   fttr-tools / h3c-fttr-tools。下面按候选名探测，统一拷成
#   package/custom/openwrt-fttr/，让索引包名与 config 的 =y 对得上。
#   h3c-fmcs           KernelPackage → 索引里叫 kmod-h3c-fmcs，DEPENDS 限定
#                      @(TARGET_airoha_an7581)，另依赖 +kmod-spi-gpio
#   openwrt-fttr       Rust 包，硬 include feeds/packages/lang/rust/rust-package.mk
#   h3c-fmcs-firmware  纯数据包，FPGA 比特流 → /lib/firmware/FTTR_TOP.sbit
# ⚠ h3c-fmcs 是 KernelPackage，索引里的名字是 kmod-h3c-fmcs。下面的包索引
#   校验内置了这层映射（pkgname_of），看到的是 ✅ h3c-fmcs → kmod-h3c-fmcs。
# =========================================================
if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  # 仓库与分支由 workflow 注入，本地手工跑时回退到下面的默认值
  FTTR_FEED_URL="https://github.com/${PRIVATE_REPO:-LazuliKao/openwrt-fttr}"
  FTTR_FEED_BRANCH="${PRIVATE_REPO_BRANCH:-main}"
  FTTR_FEED_TMP="$(mktemp -d)/openwrt-fttr"
  if ! clone "$FTTR_FEED_URL" "$FTTR_FEED_TMP" "$FTTR_FEED_BRANCH"; then
    echo "::error::openwrt-fttr 拉取失败：${FTTR_FEED_URL} (分支 ${FTTR_FEED_BRANCH})，kmod-h3c-fmcs / openwrt-fttr / h3c-fmcs-firmware 会被 defconfig 剔除；luci-app-fttr 因依赖 +openwrt-fttr 也会被连带剔除"
    echo "        公开仓库失败=仓库/分支名不对；私有仓库缺凭证=优先查 GitHub App（PRIVATE_SOURCE_APP_ID / PRIVATE_SOURCE_APP_PRIVATE_KEY，App 要装到该仓库且 Contents: Read-only），回退才看 Secret PRIVATE_REPO_TOKEN 是否有效（PAT 需对该仓库有 Contents 读权限）"
    exit 1
  fi

  # openwrt-fttr 硬 include 了 feeds/packages/lang/rust/rust-package.mk，
  # 这个文件不在的话 dump 直接失败、包静默不进索引。
  # 与其等到 defconfig 把它剔掉才发现，不如在这里就报错退出。
  if [ "$ADD_FTTR_TOOLS" = "true" ] && [ ! -f feeds/packages/lang/rust/rust-package.mk ]; then
    echo "::error::未找到 feeds/packages/lang/rust/rust-package.mk，openwrt-fttr 无法索引"
    echo "        确认 packages feed 已 update + install；或把 ADD_FTTR_TOOLS 置为 false"
    exit 1
  fi

  # 用户态后端改名后源目录不稳定（fttr / fttr-tools / h3c-fttr-tools），
  # 逐个探测；拷进 package/custom 时统一用包名 openwrt-fttr。
  FTTR_TOOLS_SRC=""
  for cand in fttr fttr-tools h3c-fttr-tools openwrt-fttr; do
    if [ -f "$FTTR_FEED_TMP/$cand/Makefile" ]; then
      FTTR_TOOLS_SRC="$cand"
      break
    fi
  done
  if [ "$ADD_FTTR_TOOLS" = "true" ] && [ -z "$FTTR_TOOLS_SRC" ]; then
    echo "::error::openwrt-fttr 源目录未找到（依次试过 fttr / fttr-tools / h3c-fttr-tools / openwrt-fttr）"
    exit 1
  fi

  FTTR_FEED_PKGS=""
  [ "$ADD_FMCS" = "true" ]       && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs"
  [ "$ADD_FTTR_TOOLS" = "true" ] && FTTR_FEED_PKGS="$FTTR_FEED_PKGS $FTTR_TOOLS_SRC"
  [ "$ADD_FMCS_FW" = "true" ]    && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs-firmware"

  for p in $FTTR_FEED_PKGS; do
    if [ ! -f "$FTTR_FEED_TMP/$p/Makefile" ]; then
      echo "::error::$FTTR_FEED_TMP/$p/Makefile 不存在（上游改结构了？）"
      exit 1
    fi
    # 源目录名可能与包名不同，统一落到与 CONFIG_PACKAGE_ 一致的目录名
    case "$p" in
      fttr|fttr-tools|h3c-fttr-tools|openwrt-fttr) dst="openwrt-fttr" ;;
      *) dst="$p" ;;
    esac
    rm -rf "$PKG_DIR/$dst"
    cp -a "$FTTR_FEED_TMP/$p" "$PKG_DIR/$dst"
    echo "✅ 已拷贝: $p → $dst  (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$dst/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  done
  rm -rf "$FTTR_FEED_TMP"
fi

# =========================================================
# luci-app-fttr —— FTTR 管理界面（网络 → FTTR）★HM2004-DU 专属
# 源：LazuliKao/luci-app-fttr 的 package 分支（公开仓库，CI 生成的完整
#     OpenWrt 包：根目录直接是 Makefile + htdocs/ + po/ + root/）。
# 2026-11-08 起上游把构建产物发布到该分支，Makefile 不再用
# PKG_SOURCE_URL / PKG_HASH 下载 nightly tarball —— 前端 JS 已随包提交，
# 因此编译阶段不再联网取前端、也不存在 hash 失效问题。
# ⚠ package 分支是 orphan + force-push 生成（每次只有 1 个 commit），
#   必须用 --depth 1 每次重新 clone，不能复用旧目录。
# ⚠ Makefile 里 LUCI_DEPENDS:=+luci-base +rpcd +openwrt-fttr，后端仍由
#   上面的私有 feed 提供；私库里若还留着旧 luci-app-fttr/ 目录，本脚本
#   不会拷它（已从 FTTR_FEED_PKGS 移除），可自行清理避免混淆。
# ⚠ CI 生成的 Makefile 漏了「# call BuildPackage - OpenWrt buildroot
#   signature」这行标记。include/scan.mk 第 77 行用文本 grep 找
#   'call BuildPackage' 决定哪些 Makefile 进 FILELIST（不展开 include），
#   缺这行 → 目录不进扫描列表 → 不 DUMP → tmp/.packageinfo 里没有这个包，
#   表现就是「包拷好了、别的包全 ✅、唯独 luci-app-fttr ❌」，且没有 dump.txt。
#   所以每次拷贝后幂等补一行，见下方。
# =========================================================
if [ "$ADD_FTTR" = "true" ] && [ "$ADD_FTTR_LUCI" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  # 用独立变量名，不与 workflow 里指向「源码仓 main 分支」的 FTTR_LUCI_* 冲突
  FTTR_PKG_REPO="${FTTR_PKG_REPO:-LazuliKao/luci-app-fttr}"
  FTTR_PKG_BRANCH="${FTTR_PKG_BRANCH:-package}"
  FTTR_TMP="$(mktemp -d)/fttr"
  if ! clone "https://github.com/${FTTR_PKG_REPO}" "$FTTR_TMP" "$FTTR_PKG_BRANCH"; then
    echo "::error::luci-app-fttr 的 ${FTTR_PKG_BRANCH} 分支拉取失败，config 里的 =y 会被 defconfig 剔除"
    exit 1
  fi
  # 分支根目录就该是完整包；顺手确认前端产物在，防止 CI 生成了空壳
  if [ ! -f "$FTTR_TMP/Makefile" ] || \
     [ ! -d "$FTTR_TMP/htdocs/luci-static/resources/view/fttr" ]; then
    echo "::error::$FTTR_TMP 不是完整 OpenWrt 包（缺 Makefile 或 htdocs/view/fttr）"
    exit 1
  fi

  rm -rf "$PKG_DIR/luci-app-fttr"
  cp -a "$FTTR_TMP" "$PKG_DIR/luci-app-fttr"
  rm -rf "$PKG_DIR/luci-app-fttr/.git"   # 别把克隆元数据带进源码树

  # scan.mk 只按文本 grep 'call BuildPackage' 收录 Makefile，luci.mk 里的真实
  # 调用不算（grep 不展开 include）。上游 CI 模板漏了这行标准注释，补回来：
  # 注释行对 make 无害，但缺了它整个包不会被索引。上游修好后自动跳过。
  FTTR_MK="$PKG_DIR/luci-app-fttr/Makefile"
  if ! grep -qE 'call[[:space:]]+(Build/DefaultTargets|BuildPackage|BuildContainer|BuildCompose|KernelPackage)' "$FTTR_MK"; then
    printf '\n# call BuildPackage - OpenWrt buildroot signature\n' >> "$FTTR_MK"
    echo "⚠ 已补 BuildPackage 扫描标记（上游 package 分支 Makefile 缺失）"
  fi

  echo "✅ 已拷贝: luci-app-fttr (版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-fttr/Makefile" 2>/dev/null | sed 's/PKG_VERSION:=//'))"
  rm -rf "$FTTR_TMP"
fi


# --- Airoha SoC 状态页（NPU 卸载 / CPU 频率 / Frame Engine / PPE 流表）---
# 包名由目录名决定（luci.mk: PKG_NAME ?= $(notdir ${CURDIR})），
# 目录必须是 luci-app-airoha-npu，否则 config 里的符号对不上。
#
# 源用 luanmuc/luci-app-airoha-npu（rchen14b 的 fork 改进版）：
#   - 自带 po/zh_Hans 完整中文翻译（48 条）
#   - 无 rchen14b 那种「根目录 + 同名子目录」重复结构，feed 索引不会中断
#   - 修了 luci.mk 的 include 路径、加了独立 CPU 温度与 PLL 备用频率
if [ "$ADD_AIROHA_NPU" = "true" ]; then
  if ! clone https://github.com/luanmuc/luci-app-airoha-npu "$PKG_DIR/luci-app-airoha-npu" main; then
    echo "::error::luci-app-airoha-npu 拉取失败，后续 defconfig 会静默剔除该包"
    exit 1
  fi
  # 包名校验：Makefile 必须存在，否则 buildroot 扫不到这个包
  if [ ! -f "$PKG_DIR/luci-app-airoha-npu/Makefile" ]; then
    echo "::error::$PKG_DIR/luci-app-airoha-npu/Makefile 不存在，包无法被索引"
    exit 1
  fi
  echo "   版本: $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-airoha-npu/Makefile" 2>/dev/null)"
  # =========================================================
  # 关键：po 文件名必须改成 airoha-npu.po
  #   luci.mk 的 i18n 规则按 po 主名生成 lmo，运行时却按 LUCI_BASENAME
  #   （= airoha-npu）查找。上游两份 po 都叫 luci-app-airoha-npu.po，会生成
  #   luci-app-airoha-npu.zh-cn.lmo → 前端找不到 → 中文不生效。
  # =========================================================
  PODIR="$PKG_DIR/luci-app-airoha-npu/po"
  if [ -f "$PODIR/zh_Hans/luci-app-airoha-npu.po" ]; then
    # 确保 Language 头是 zh_Hans（上游头部缺该字段时 po2lmo 可能识别异常）
    grep -q '^"Language:' "$PODIR/zh_Hans/luci-app-airoha-npu.po" || \
      sed -i 's/^msgstr ""$/msgstr ""\n"Language: zh_Hans\\n"/' "$PODIR/zh_Hans/luci-app-airoha-npu.po"
    mv "$PODIR/zh_Hans/luci-app-airoha-npu.po" "$PODIR/zh_Hans/airoha-npu.po"
    echo "✅ po 改名: luci-app-airoha-npu.po -> airoha-npu.po（luci.mk 按 LUCI_BASENAME 查找）"
  fi
  if [ -f "$PODIR/es/luci-app-airoha-npu.po" ]; then
    mv "$PODIR/es/luci-app-airoha-npu.po" "$PODIR/es/airoha-npu.po"
  fi
  echo "   po/zh_Hans: $(ls -1 "$PODIR/zh_Hans/" 2>/dev/null | tr '\n' ' ')"
fi

# --- passwall ---
# 源已从 xiaorouji 迁到 Openwrt-Passwall 组织（旧地址 404）。
# ⚠ 只拷 luci-app-passwall 子目录：openwrt-passwall-packages 是 monorepo，
#   里面 xray-core / sing-box / hysteria / naiveproxy / shadowsocks-rust …
#   全部与 feeds 同名，整仓拷进来就是两份同名包。依赖一律用 feeds 的。
if [ "$ADD_PASSWALL" = "true" ]; then
  PW_TMP="$(mktemp -d)/pw"
  if clone https://github.com/Openwrt-Passwall/openwrt-passwall "$PW_TMP" main \
     && [ -f "$PW_TMP/luci-app-passwall/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-passwall"
    cp -r "$PW_TMP/luci-app-passwall" "$PKG_DIR/"
    echo "✅ 已拷贝: luci-app-passwall"
  else
    echo "::error::luci-app-passwall 拉取失败或结构变化"
  fi
  rm -rf "$PW_TMP"
fi
# --- openclash ---
if [ "$ADD_OPENCLASH" = "true" ]; then
  echo "::warning::OpenClash 会触发 Ruby/Rust 编译，耗时极长"
  clone https://github.com/vernesong/OpenClash "$PKG_DIR/OpenClash" master
  mv "$PKG_DIR/OpenClash/luci-app-openclash" "$PKG_DIR/luci-app-openclash" 2>/dev/null
  rm -rf "$PKG_DIR/OpenClash"
fi
# --- mosdns ---
# ⚠ 只拷 luci-app-mosdns 子目录：仓库里还带 mosdns 本体与 v2ray-geodata，
#   两个都与 feeds 同名。本体用 feeds 的。
if [ "$ADD_MOSDNS" = "true" ]; then
  MD_TMP="$(mktemp -d)/mosdns"
  if clone https://github.com/sbwml/luci-app-mosdns "$MD_TMP" v5 \
     && [ -f "$MD_TMP/luci-app-mosdns/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-mosdns" "$PKG_DIR/geo2txt"
    cp -r "$MD_TMP/luci-app-mosdns" "$PKG_DIR/"
    # geo2txt 是 luci-app-mosdns 的硬依赖（LUCI_DEPENDS 里 +geo2txt），
    # feeds 里没有同名包，必须一起拷进来，否则索引时报
    # "has a dependency on 'geo2txt', which does not exist"
    if [ -f "$MD_TMP/geo2txt/Makefile" ]; then
      cp -r "$MD_TMP/geo2txt" "$PKG_DIR/"
      echo "✅ 已拷贝: geo2txt（luci-app-mosdns 依赖）"
    else
      echo "::warning::mosdns 仓库里没有 geo2txt，luci-app-mosdns 会缺这个依赖"
    fi
    echo "✅ 已拷贝: luci-app-mosdns（本体用 feeds）"
  else
    echo "::error::luci-app-mosdns 拉取失败或结构变化"
  fi
  rm -rf "$MD_TMP"
fi
# --- lucky ---
# 仓库是 monorepo：根目录没有 Makefile，真正的两个包在 lucky/（本体，预编译
# 二进制按架构下载）与 luci-app-lucky/（界面，DEPENDS += lucky）子目录里，
# 两个都要拷，只拷界面会因缺 lucky 依赖被索引丢弃。
if [ "$ADD_LUCKY" = "true" ]; then
  LUCKY_TMP="$(mktemp -d)/lucky"
  if clone https://github.com/sirpdboy/luci-app-lucky "$LUCKY_TMP" main; then
    for p in lucky luci-app-lucky; do
      if [ ! -f "$LUCKY_TMP/$p/Makefile" ]; then
        echo "::error::lucky 仓库里缺少 $p/Makefile（上游改结构了？）"
        exit 1
      fi
      rm -rf "$PKG_DIR/$p"
      cp -a "$LUCKY_TMP/$p" "$PKG_DIR/$p"
      echo "✅ 已拷贝: $p"
    done
  else
    echo "::error::luci-app-lucky 拉取失败，lucky 会被 defconfig 剔除"
    exit 1
  fi
  rm -rf "$LUCKY_TMP"
fi
# --- tailscale ---
if [ "$ADD_TAILSCALE" = "true" ]; then
  clone https://github.com/asvow/luci-app-tailscale "$PKG_DIR/luci-app-tailscale" main
fi
# --- openlist2 ---
if [ "$ADD_OPENLIST" = "true" ]; then
  clone https://github.com/sbwml/luci-app-openlist2 "$PKG_DIR/luci-app-openlist2" main
fi

# --- smartdns ---
# ⚠ 不拉 pymumu/smartdns 本体：与 feeds/packages/net/smartdns 同名。
if [ "$ADD_SMARTDNS" = "true" ]; then
  clone https://github.com/pymumu/luci-app-smartdns "$PKG_DIR/luci-app-smartdns" master
fi
# --- luci-theme-fluent ---
# ⚠ 包在仓库的 package/ 子目录下，不能直接 clone 到 package/custom，
#   必须把子目录拷出来，否则 buildroot 扫不到 Makefile
if [ "$ADD_FLUENT" = "true" ] || [ "$ADD_FLUENT_LITE" = "true" ] || [ "$ADD_FLUENT_DASH" = "true" ]; then
  FLUENT_TMP="$(mktemp -d)/fluent"
  clone https://github.com/LazuliKao/luci-theme-fluent "$FLUENT_TMP" main

  for p in luci-theme-fluent luci-theme-fluent-lite luci-mod-fluentdashboard; do
    case "$p" in
      luci-theme-fluent)        [ "$ADD_FLUENT" = "true" ] || continue ;;
      luci-theme-fluent-lite)   [ "$ADD_FLUENT_LITE" = "true" ] || continue ;;
      luci-mod-fluentdashboard) [ "$ADD_FLUENT_DASH" = "true" ] || continue ;;
    esac
    [ -d "$FLUENT_TMP/package/$p" ] || { echo "::error::$p 不存在"; continue; }
    rm -rf "$PKG_DIR/$p"
    cp -a "$FLUENT_TMP/package/$p" "$PKG_DIR/$p"
    echo "✅ 已拷贝: $p"
  done
  rm -rf "$FLUENT_TMP"
fi

if [ "$ADD_EASYTIER" = "true" ]; then
  # 同样是 monorepo：easytier/ 是本体（按架构下载预编译 zip），
  # luci-app-easytier/ 是界面。界面 DEPENDS 里只有 +kmod-tun +luci-compat，
  # 不含 +easytier，所以本体必须在 config 里显式 =y。
  ET_TMP="$(mktemp -d)/easytier"
  if clone https://github.com/EasyTier/luci-app-easytier "$ET_TMP" main; then
    for p in easytier luci-app-easytier; do
      if [ ! -f "$ET_TMP/$p/Makefile" ]; then
        echo "::error::easytier 仓库里缺少 $p/Makefile（上游改结构了？）"
        exit 1
      fi
      rm -rf "$PKG_DIR/$p"
      cp -a "$ET_TMP/$p" "$PKG_DIR/$p"
      echo "✅ 已拷贝: $p"
    done
  else
    echo "::error::luci-app-easytier 拉取失败，easytier 会被 defconfig 剔除"
    exit 1
  fi
  rm -rf "$ET_TMP"
fi
if [ "$ADD_POWEROFF" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-poweroffdevice "$PKG_DIR/luci-app-poweroffdevice" master
fi
if [ "$ADD_OWQ_WOL" = "true" ]; then
  clone https://github.com/isalikai/luci-app-owq-wol "$PKG_DIR/luci-app-owq-wol" main
fi
if [ "$ADD_TASKPLAN" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-taskplan "$PKG_DIR/luci-app-taskplan" main
fi
# --- watchdog ---
# ⚠ 仓库是 monorepo：根目录无 Makefile，luci-app-watchdog/（前端）与
#   watchdog/（本体）是两个包，前者依赖 +watchdog，两个都要拷。
#   只拷前端时索引会报 "has a dependency on 'watchdog', which does not exist"。
if [ "$ADD_WATCHDOG" = "true" ]; then
  WD_TMP="$(mktemp -d)/wd"
  if clone https://github.com/sirpdboy/luci-app-watchdog "$WD_TMP" main; then
    for p in luci-app-watchdog watchdog; do
      [ -f "$WD_TMP/$p/Makefile" ] || { echo "::warning::$p 不存在（上游改结构了？）"; continue; }
      rm -rf "$PKG_DIR/$p"
      cp -r "$WD_TMP/$p" "$PKG_DIR/"
      echo "✅ 已拷贝: $p"
    done
  else
    echo "::error::luci-app-watchdog 拉取失败"
  fi
  rm -rf "$WD_TMP"
fi
if [ "$ADD_OAF" = "true" ]; then
  clone https://github.com/destan19/OpenAppFilter "$PKG_DIR/OpenAppFilter" master
  for p in luci-app-oaf open-app-filter oaf; do
    cp -r "$PKG_DIR/OpenAppFilter/$p" "$PKG_DIR/" 2>/dev/null
  done
  rm -rf "$PKG_DIR/OpenAppFilter"
fi

# --- mesh（xxosdev/luci-app-mesh）---
# 802.11s 组网管理。仓库根目录就是完整 LuCI 包（Makefile + htdocs + root），
# 整包拷进 package/custom/luci-app-mesh 即可。
#
# ⚠ 上游 LUCI_DEPENDS 带 +wpad-mesh-openssl +kmod-batman-adv +batctl
#   +luci-proto-batman-adv +dawn +umdns。
#
#   2026-11 修正：此前把 batman-adv / dawn / umdns 当"可选增强"裁掉了，
#   实机反馈**组网能力不满足**：
#     · 缺 kmod-batman-adv + batctl → 没有多跳路由，节点只能一跳直连；
#     · 缺 dawn → 没有 802.11k/v 漫游引导，客户端粘在原 AP 不切换；
#     · 缺 umdns → DAWN 无法跨 AP 交换邻居/负载信息，等于 dawn 装了个空壳。
#   现恢复为强依赖（与上游一致，仅 wpad-mesh-openssl 除外，见下）。
#
#   唯一保留的裁剪：wpad-mesh-openssl。
#     wpad-openssl 是 full 变体，hostapd 编 full 时本就 CONFIG_MESH=y，
#     再拉 wpad-mesh-openssl 会与已有 wpad-openssl 争同一组文件。
#     → LUCI_DEPENDS 里保留 +wpad-openssl，不加 +wpad-mesh-openssl。
if [ "$ADD_MESH" = "true" ]; then
  MESH_TMP="$(mktemp -d)/mesh"
  if clone https://github.com/xxosdev/luci-app-mesh "$MESH_TMP" main \
     && [ -f "$MESH_TMP/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-mesh"
    cp -a "$MESH_TMP" "$PKG_DIR/luci-app-mesh"
    rm -rf "$PKG_DIR/luci-app-mesh/.git"
    awk '
      /^LUCI_DEPENDS:=/ {
        print "LUCI_DEPENDS:=+uclient-fetch +rpcd +curl +jsonfilter +iwinfo +iw +wpad-openssl \\"
        print "\t+kmod-batman-adv +batctl +luci-proto-batman-adv \\"
        print "\t+dawn +umdns"
        skip=1; next
      }
      skip && /^[[:space:]]+\+/ { next }
      { skip=0; print }
    ' "$PKG_DIR/luci-app-mesh/Makefile" > "$PKG_DIR/luci-app-mesh/Makefile.tmp" && \
      mv "$PKG_DIR/luci-app-mesh/Makefile.tmp" "$PKG_DIR/luci-app-mesh/Makefile"
    echo "✅ 已拷贝: luci-app-mesh（依赖恢复为上游完整版，仅去掉 wpad-mesh-openssl）"
    grep -m1 '^LUCI_DEPENDS' -A2 "$PKG_DIR/luci-app-mesh/Makefile" || true
  else
    echo "::error::luci-app-mesh 拉取失败，mesh 会被 defconfig 剔除"
    exit 1
  fi
  rm -rf "$MESH_TMP"
fi

# --- timecontrol（kavass168/luci-app-timecontrol-25.12）---
# 包在仓库的 luci-app-timecontrol/ 子目录；前端通过 cgi-io/ubus exec 调脚本。
# 上游两个已知问题在构建期直接修掉（等价于装机后跑 luci-app-timecontrol-postfix.sh）：
#   ① ACL 里 "ubus":{"file":["exec"]} 是无效写法 → 前端 fs.exec_direct 全被拒，
#      界面按钮（保存/重启/查流量/清日志）点了没反应；
#   ② /etc/config/timecontrol 全局节是匿名的：后端读 @timecontrol[0]，
#      前端读写 timecontrol.timecontrol，两边不是同一节 → 模式/强度不生效。
if [ "$ADD_TIMECONTROL" = "true" ]; then
  TC_TMP="$(mktemp -d)/timecontrol"
  if clone https://github.com/kavass168/luci-app-timecontrol-25.12 "$TC_TMP" main \
     && [ -f "$TC_TMP/luci-app-timecontrol/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-timecontrol"
    cp -a "$TC_TMP/luci-app-timecontrol" "$PKG_DIR/luci-app-timecontrol"
    TC_DIR="$PKG_DIR/luci-app-timecontrol"
    WS_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
    # ① ACL 换成修正版（源文件随本仓库提交：patches/luci-app-timecontrol/acl.json）
    if [ -f "$WS_DIR/patches/luci-app-timecontrol/acl.json" ]; then
      cp -f "$WS_DIR/patches/luci-app-timecontrol/acl.json" \
        "$TC_DIR/root/usr/share/rpcd/acl.d/luci-app-timecontrol.json"
      echo "✅ timecontrol: ACL 已替换为修正版"
    else
      echo "::warning::未找到 patches/luci-app-timecontrol/acl.json，ACL 仍是上游无效版本"
    fi
    # ② 默认配置的全局节改成命名节
    TC_CFG="$TC_DIR/root/etc/config/timecontrol"
    if [ -f "$TC_CFG" ]; then
      sed -i "s/^config timecontrol[[:space:]]*\$/config timecontrol 'timecontrol'/" "$TC_CFG"
    fi
    # ③ 老配置兜底：匿名节自动改名（uci-defaults 按文件名顺序执行）
    cat > "$TC_DIR/root/etc/uci-defaults/95-timecontrol-section" <<'TCPATCH'
#!/bin/sh
# 上游全局节是匿名的；后端读 @timecontrol[0]，前端读写 timecontrol.timecontrol。
# 已存在匿名节时改名为命名节，两边才指向同一节。
if uci -q get timecontrol.@timecontrol[0] >/dev/null 2>&1 && \
   ! uci -q get timecontrol.timecontrol >/dev/null 2>&1; then
	uci rename timecontrol.@timecontrol[0]=timecontrol
	uci commit timecontrol
fi
exit 0
TCPATCH
    chmod +x "$TC_DIR/root/etc/uci-defaults/95-timecontrol-section"
    echo "✅ 已拷贝: luci-app-timecontrol（ACL + 命名配置节已修）"
  else
    echo "::error::luci-app-timecontrol 拉取失败，timecontrol 会被 defconfig 剔除"
    exit 1
  fi
  rm -rf "$TC_TMP"
fi

# --- rtp2httpd：用本人仓库源码替换 feeds 官方版 ---
# 同名 Package 在索引里出现两次时，实际编进去哪份取决于扫描顺序，
# 所以先删掉 feeds 官方 3.16.0，再放自己那份（packages/rtp2httpd 随仓库提交）。
if [ "$ADD_RTP2HTTPD_FORK" = "true" ]; then
  WS_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
  if [ -f "$WS_DIR/packages/rtp2httpd/Makefile" ]; then
    rm -rf feeds/packages/net/rtp2httpd package/feeds/packages/net/rtp2httpd 2>/dev/null
    rm -rf "$PKG_DIR/rtp2httpd"
    cp -a "$WS_DIR/packages/rtp2httpd" "$PKG_DIR/rtp2httpd"
    echo "✅ 已替换 rtp2httpd：mayipashu/rtp2httpd @ d7cc99a（v3.17.2，官方 init/LuCI 不变）"
  else
    echo "::warning::未找到 $WS_DIR/packages/rtp2httpd，rtp2httpd 仍用 feeds 官方源码"
  fi
fi
# ---------------------------------------------------------
# 校验：默认开启的三个插件必须拉到，否则 defconfig 会静默剔除，
#       编出来的固件缺少状态页还不易察觉
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "::error::luci-app-airoha-npu 未拉到，config 里的 =y 会被 defconfig 剔除"
  exit 1
fi
# natmode / pon-status / igmpproxy 来自 qwe3017/luci-app（config 里也是 =y）
for p in luci-app-natmode luci-app-pon-status luci-app-igmpproxy; do
  if [ "$ADD_LUCI_APP" = "true" ] && [ ! -d "$PKG_DIR/$p" ]; then
    echo "::error::$p 未拉到，config 里的 =y 会被 defconfig 剔除"
    exit 1
  fi
done
# ---------------------------------------------------------
# 补回 libffi —— python3(3.14) 的 _ctypes 硬性需要
#   CPython 自 3.11 起删掉了 --with-system-ffi，_ctypes 永远 #include <ffi.h>；
#   而 ponwrt 与 immortalwrt/packages 的 libffi 目录都已不存在，整棵树里没有
#   ffi.h / libffi.pc，于是编到 _ctypes.c 才炸：
#     ./Modules/_ctypes/_ctypes.c:119:10: fatal error: ffi.h: No such file...
#   处理：从 immortalwrt 基座取现成的包定义（自带 Build/InstallDev，会把
#   ffi.h / libffi.pc 装进 staging_dir），再给 python3 补一条构建依赖。
# ⚠ 必须放在 prepare-tmpinfo 之前：目录要被扫进索引，PKG_BUILD_DEPENDS 也要生效。
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

# ---------------------------------------------------------
# 清理重复嵌套目录
# rchen14b/luci-app-airoha-npu 这个仓库有问题：包在根目录放了一份，
# 又在同名子目录 luci-app-airoha-npu/ 里放了完整一份（含 Makefile）。
# feeds 扫描会把两层都当成独立包，内层 dump 失败（报
# "feeds/custom/luci-app-airoha-npu/luci-app-airoha-npu"）会中断整个
# custom feed 的索引，导致 package/feeds/custom 压根不生成，
# 所有包符号都不存在。
# ---------------------------------------------------------
echo "--- 检查重复嵌套目录 ---"
# ⚠ 判据必须包含「根目录也有 Makefile」，否则会误删 monorepo 的真包：
#   lucky / openlist2 / easytier / taskplan / poweroffdevice 的仓库根目录【没有】
#   Makefile，同名子目录才是唯一的那份包 —— 只看「有同名子目录」就会把它们
#   当重复项删掉，包从索引里消失、config 的 =y 被 defconfig 静默剔除。
#   只有 rchen14b/luci-app-airoha-npu 那种「根目录一份 + 同名子目录又一份」
#   才是要清理的坏结构（内层 dump 失败会中断整个 custom feed 的索引）。
for d in "$PKG_DIR"/*; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if [ -f "$d/Makefile" ] && [ -d "$d/$n" ] && [ -f "$d/$n/Makefile" ]; then
    rm -rf "$d/$n"
    echo "✅ 已移除重复嵌套目录: $n/$n"
  fi
done
# ---------------------------------------------------------
# 让新包进入索引
#   ⚠ 判据是 tmp/.packageinfo，不是 package/feeds/custom
#   prepare-tmpinfo 直接扫 package/ 树（scan.mk: find -L package -maxdepth 5），
#   package/custom/<pkg>/Makefile 深度 3，本来就会被扫到，**不需要注册 feed**。
#   旧的 src-link custom feed 有两个坑：① 同一批 Makefile 被扫两遍，按 Override
#   挑一个、行为随扫描顺序漂移；② install_src() 看到 $installed 非空直接 return，
#   压根不建 package/feeds/custom/<pkg> —— 所以它不存在是正常的，拿它当判据必然误报。
# ---------------------------------------------------------
if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  # =========================================================
  # 强制重建索引
  #   只删 tmp/.packageinfo 是不够的：prepare-tmpinfo 有 scan_unchanged
  #   优化（拿 tmp/info/.scan-*.stamp 比 mtime），stamp 还在且没有更新的
  #   Makefile 时它会跳过扫描 —— 结果 .packageinfo 被删了却没人重建，
  #   索引反而空了。所以 stamp 和 scan.mk 的 .files* 清单缓存都要一起删。
  #   actions/cache 恢复的 tmp/ 会保留旧时间戳，而 cp -a 又保留源 mtime：
  #   新拷进来的 Makefile 可能比重建的 stamp 还旧，scan_unchanged 会判
  #   「无变化」直接跳过 —— 表现就是「包拷好了、别的包都 ✅、唯独它缺席」。
  #   所以删完缓存再统一刷新 package/custom 下所有文件的时间戳。
  # =========================================================
  rm -f tmp/.packageinfo tmp/.targetinfo
  rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
  rm -f tmp/info/.files* 2>/dev/null
  rm -f tmp/.config-package.in tmp/.config-target.in
  find "$PKG_DIR" -type f -exec touch {} + 2>/dev/null || true
  echo ">>> make prepare-tmpinfo（重新扫描 package/ 树）"
  make prepare-tmpinfo OPENWRT_BUILD= V=s 2>&1 | tail -60
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "::error::prepare-tmpinfo 执行失败，索引不会更新（见上方输出）"
    exit 1
  fi
  echo "=========================================="
  echo "包索引校验（判据：tmp/.packageinfo）"
  echo "=========================================="
  echo "package/custom 内容："
  INDEX_MISS=""
  # 目录名 ≠ 包名的情况（Makefile 里显式写了 PKG_NAME / KernelPackage）：
  #   open-app-filter 的包是 appfilter、oaf 的 KernelPackage 是 kmod-oaf，
  #   按目录名去索引里查必然查不到 —— 那是误报，不是索引失败。
  pkgname_of() {
    case "$1" in
      open-app-filter) echo "appfilter" ;;
      oaf)             echo "kmod-oaf" ;;
      h3c-fmcs)        echo "kmod-h3c-fmcs" ;;
      *)               echo "$1" ;;
    esac
  }

  for d in "$PKG_DIR"/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")

    # 无根 Makefile = monorepo 容器（lucky / openlist2 / easytier / taskplan /
    # poweroffdevice / watchdog），真正的包在同名子目录里，逐个查
    if [ ! -f "$d/Makefile" ]; then
      found=0
      # 直接对 glob 迭代，不拼字符串再分词 —— 拼了就得依赖 IFS 分词，
      # 换个 shell（zsh 默认不拆）行为就变
      for sd in "$d"/*/Makefile; do
        [ -f "$sd" ] || continue
        found=1
        sn="$(basename "$(dirname "$sd")")"
        if grep -qx "Package: $sn" tmp/.packageinfo 2>/dev/null; then
          echo "  ✅ $n → $sn"
        else
          echo "  ❌ $n → $sn —— tmp/.packageinfo 里查不到"
          INDEX_MISS="$INDEX_MISS $sn"
          for f in "logs/package/$sn/dump.txt" "logs/package/custom/$sn/dump.txt"; do
            [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; }
          done
        fi
      done
      [ "$found" = 1 ] || echo "  -  $n（无 Makefile，跳过）"
      continue
    fi

    pn="$(pkgname_of "$n")"
    if grep -qx "Package: $pn" tmp/.packageinfo 2>/dev/null; then
      echo "  ✅ $n${pn:+$([ "$pn" != "$n" ] && echo " → $pn")}"
    else
      echo "  ❌ $n（包名 $pn）—— tmp/.packageinfo 里查不到"
      INDEX_MISS="$INDEX_MISS $pn"
      # 真实错误在这里（scan.mk 落盘路径 logs/<SCAN_DIR>/<相对目录>/dump.txt）
      DUMP_SHOWN=0
      for f in "logs/package/$n/dump.txt" "logs/package/custom/$n/dump.txt"; do
        [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; DUMP_SHOWN=1; }
      done
      # scan.mk 压根没落 dump.txt（缓存跳过扫描时常见）：直接单包 dump 一次，
      # 把 Makefile 解析错误打出来，避免「查不到但日志里没有任何线索」。
      if [ "$DUMP_SHOWN" -eq 0 ]; then
        echo "===== 直接 dump: make $d/dump V=s ====="
        make "$d/dump" V=s 2>&1 | tail -40
      fi
    fi
  done
  echo "------------------------------------------"
  echo "luci.mk: $([ -f feeds/luci/luci.mk ] && echo '✓' || echo '✗ 缺失（luci app 无法解析）')"
  echo "tmp/.packageinfo 包总数: $(grep -c '^Package: ' tmp/.packageinfo 2>/dev/null || echo 0)"
  echo "=========================================="
  # 必装插件（config 里是 =y 的那几个）必须进索引，否则 defconfig 会静默剔除
  REQUIRED=""
  [ "$ADD_AIROHA_NPU" = "true" ] && REQUIRED="$REQUIRED luci-app-airoha-npu"
  if [ "$ADD_LUCI_APP" = "true" ]; then
    REQUIRED="$REQUIRED luci-app-natmode luci-app-pon-status luci-app-igmpproxy"
  fi

  # 与 configs/an7581.config / an7583.config 里 =y 的包一一对应。
  # 任一项没进索引，defconfig 都会把那个 =y 静默剔除 —— 编出来的固件少了菜单
  # 还不易察觉。所以这里和 config 必须同步改。
  [ "$ADD_FLUENT"    = "true" ] && REQUIRED="$REQUIRED luci-theme-fluent"
  [ "$ADD_OPENCLASH" = "true" ] && REQUIRED="$REQUIRED luci-app-openclash"
  [ "$ADD_PASSWALL"  = "true" ] && REQUIRED="$REQUIRED luci-app-passwall"
  [ "$ADD_MOSDNS"    = "true" ] && REQUIRED="$REQUIRED luci-app-mosdns"
  [ "$ADD_LUCKY"     = "true" ] && REQUIRED="$REQUIRED lucky luci-app-lucky"
  [ "$ADD_TAILSCALE" = "true" ] && REQUIRED="$REQUIRED luci-app-tailscale"
  [ "$ADD_OPENLIST"  = "true" ] && REQUIRED="$REQUIRED luci-app-openlist2"
  [ "$ADD_SMARTDNS"  = "true" ] && REQUIRED="$REQUIRED luci-app-smartdns"
  [ "$ADD_EASYTIER"  = "true" ] && REQUIRED="$REQUIRED easytier luci-app-easytier"
  [ "$ADD_POWEROFF"  = "true" ] && REQUIRED="$REQUIRED luci-app-poweroffdevice"
  [ "$ADD_OWQ_WOL"   = "true" ] && REQUIRED="$REQUIRED luci-app-owq-wol"
  [ "$ADD_WATCHDOG"  = "true" ] && REQUIRED="$REQUIRED luci-app-watchdog"
  [ "$ADD_TASKPLAN"  = "true" ] && REQUIRED="$REQUIRED luci-app-taskplan"
  [ "$ADD_OAF"       = "true" ] && REQUIRED="$REQUIRED luci-app-oaf"
  [ "$ADD_MESH"      = "true" ] && REQUIRED="$REQUIRED luci-app-mesh"
  [ "$ADD_TIMECONTROL" = "true" ] && REQUIRED="$REQUIRED luci-app-timecontrol"
  [ "$ADD_RTP2HTTPD_FORK" = "true" ] && REQUIRED="$REQUIRED rtp2httpd"
  true
  if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
    # KernelPackage 生成的包名带 kmod- 前缀，索引里写的是 kmod-h3c-fmcs
    if [ "$ADD_FMCS" = "true" ]; then
      REQUIRED="$REQUIRED kmod-h3c-fmcs"
    fi
    if [ "$ADD_FMCS_FW" = "true" ]; then
      REQUIRED="$REQUIRED h3c-fmcs-firmware"
    fi
    if [ "$ADD_FTTR_TOOLS" = "true" ]; then
      REQUIRED="$REQUIRED openwrt-fttr"
    fi
    if [ "$ADD_FTTR_LUCI" = "true" ]; then
      REQUIRED="$REQUIRED luci-app-fttr"
    fi
    # =========================================================
    # luci-app-fttr 依赖 +openwrt-fttr，后者依赖 +kmod-h3c-fmcs。
    # 链条上任一节不在树里，defconfig 都会静默把整条 FTTR 剔掉 —— 与其编出
    # 一个没有 FTTR 界面的固件还不易察觉，不如在这里直接报错。
    # 前者最常见原因是缺 rust-package.mk；后者受 @(TARGET_airoha_an7581) 限制。
    # 界面包来自 LazuliKao/luci-app-fttr 的 package 分支，前端 JS 已随包
    # 提交，编译不联网；后端三件套仍由私有 feed 提供。
    # =========================================================
    if [ "$ADD_FTTR_TOOLS" = "true" ] &&
       ! grep -qx "Package: openwrt-fttr" tmp/.packageinfo 2>/dev/null; then
      echo "::error::openwrt-fttr 不在包索引里（luci-app-fttr 的后端，Rust 包）"
      echo "        多半是缺 rust feed：确认 feeds.conf 里有 packages，且"
      echo "        ./scripts/feeds install 装到了 lang/rust。"
      echo "        不需要 FTTR 就把 diy-part1.sh 的 ADD_FTTR 改成 false。"
      exit 1
    fi
    if [ "$ADD_FMCS" = "true" ] &&
       ! grep -qx "Package: kmod-h3c-fmcs" tmp/.packageinfo 2>/dev/null; then
      echo "::error::kmod-h3c-fmcs 不在包索引里（openwrt-fttr 依赖它）"
      echo "        DEPENDS 是 @(TARGET_airoha_an7581)：非该 target 时包不会进索引。"
      echo "        不需要 FTTR 就把 diy-part1.sh 的 ADD_FTTR 改成 false。"
      exit 1
    fi
  fi
  HARD_MISS=""
  for r in $REQUIRED; do
    grep -qx "Package: $r" tmp/.packageinfo 2>/dev/null || HARD_MISS="$HARD_MISS $r"
  done
  if [ -n "$HARD_MISS" ]; then
    echo "::error::以下必装插件未进入 tmp/.packageinfo，defconfig 会把 .config 里的 =y 静默剔除:$HARD_MISS"
    echo "  已索引缺失清单:$INDEX_MISS"
    exit 1
  fi
  [ -n "$INDEX_MISS" ] && echo "::warning::部分可选包未进入索引（不影响必装插件）:$INDEX_MISS"
else
  echo "未启用任何第三方插件"
fi
echo "🎉 diy-part1.sh 执行完毕"
