# luci-app-mesh — 802.11s Mesh 组网管理（JS 界面 · 主/子节点 · 配置同步 · 信道错开 · 全端口内网化）
#
# 上游 https://github.com/xxosdev/luci-app-mesh 已不可访问（404），本目录是
# 实机验证过的 luci-app-mesh 1.0.0-r58 固化为仓库内源码：
#   root/          来自 devicefit ipk 的 data.tar.gz（22 个文件，权限已保留）
#   postinst/prerm 来自同一 ipk
#   LUCI_DEPENDS   为 Run #5/#6 验证的完整组网依赖（见下）
#
# 依赖说明：
#   ① wpad-openssl 是 full 变体，hostapd 编 full 时本就 CONFIG_MESH=y，
#      所以不写 +wpad-mesh-openssl（两者会争同一组文件）。
#   ② +kmod-batman-adv +batctl：层二多跳路由；+luci-proto-batman-adv：
#      网络 → 接口 支持 batadv 协议（bat0）。
#   ③ +dawn +umdns：dawn 用 802.11k/v 引导客户端漫游，靠 umdns 跨 AP 交换
#      邻居/负载信息。dawn 自身已 DEPENDS +umdns，这里显式列出让漫游能力
#      在包依赖里可见。

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mesh
PKG_VERSION:=1.0.0
PKG_RELEASE:=58
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Xx

LUCI_TITLE:=802.11s Mesh 组网管理（JS 界面 · 主/子节点 · 配置同步 · 信道错开 · 全端口内网化）
LUCI_DEPENDS:=+uclient-fetch +rpcd +curl +jsonfilter +iwinfo +iw \
	+wpad-openssl \
	+kmod-batman-adv +batctl +luci-proto-batman-adv \
	+dawn +umdns
LUCI_PKGARCH:=all

# 下面的 Package/install 已手动逐项安装并设置权限，这里的 PKG_INSTALL 仅作兜底
PKG_INSTALL:=$(CURDIR)/root

include $(TOPDIR)/feeds/luci/luci.mk

# 保留 root/ 下的目录结构与权限（cgi-bin 可执行位）
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(CURDIR)/root/usr/sbin/meshctl $(1)/usr/sbin/
# 在线安装/升级/卸载脚本：随包落地后，设备上直接 `mesh-install upgrade` 即可升级。
	$(INSTALL_BIN) $(CURDIR)/root/usr/sbin/mesh-install $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/usr/libexec/mesh
	$(INSTALL_DATA) $(CURDIR)/root/usr/libexec/mesh/functions.sh $(1)/usr/libexec/mesh/
# 版本号落盘文件：mesh-install.sh 靠它判断"实际装了哪一版"。
	$(INSTALL_DATA) $(CURDIR)/root/usr/libexec/mesh/version $(1)/usr/libexec/mesh/
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) $(CURDIR)/root/usr/libexec/rpcd/mesh $(1)/usr/libexec/rpcd/mesh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/root/etc/init.d/mesh $(1)/etc/init.d/
# 无线漫游自检脚本：97 补齐 AP 的 802.11k/11v/11r，99 校正 dawn/umdns 的
# 广播地址与跨机参数。两者都是幂等的"差异修复器"。
	$(INSTALL_BIN) $(CURDIR)/root/etc/init.d/97-wifi-roaming $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/root/etc/init.d/99-dawn-roaming $(1)/etc/init.d/
# 编译进 image（随固件预装）时没有安装钩子，postinst 一次都不会跑，所以
# 用 uci-defaults 在首次开机补上 enable + cron_enable。
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(CURDIR)/root/etc/uci-defaults/40-luci-app-mesh-roaming $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) $(CURDIR)/root/etc/hotplug.d/iface/30-mesh-bat-mtu $(1)/etc/hotplug.d/iface/
# 按键一键组网：挂在系统 WPS 分发器 /etc/rc.button/wps 下。
	$(INSTALL_DIR) $(1)/etc/rc.wps
	$(INSTALL_BIN) $(CURDIR)/root/etc/rc.wps/10-mesh $(1)/etc/rc.wps/10-mesh
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) $(CURDIR)/root/etc/config/mesh $(1)/etc/config/
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(CURDIR)/root/www/cgi-bin/mesh-sync $(1)/www/cgi-bin/
# nginx + uwsgi 型固件专用：标准 OpenWrt 用 uhttpd，不需要本文件；
# 没有 nginx 的机器上它不会被读取，属无害冗余。
	$(INSTALL_DIR) $(1)/etc/nginx/conf.d
	$(INSTALL_DATA) $(CURDIR)/root/etc/nginx/conf.d/mesh-sync.locations $(1)/etc/nginx/conf.d/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(CURDIR)/root/usr/share/luci/menu.d/luci-app-mesh.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(CURDIR)/root/usr/share/rpcd/acl.d/luci-app-mesh.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/mesh
	$(INSTALL_DATA) $(CURDIR)/root/www/luci-static/resources/view/mesh/*.js $(1)/www/luci-static/resources/view/mesh/
	$(INSTALL_DATA) $(CURDIR)/root/www/luci-static/resources/view/mesh/mesh.css $(1)/www/luci-static/resources/view/mesh/
endef

# /etc/config/mesh 必须声明为 conffile：opkg 才会在 install/upgrade 时
# 保留用户改过的配置，新默认落到 /etc/config/mesh-opkg。
define Package/$(PKG_NAME)/conffiles
/etc/config/mesh
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1
[ -x /etc/init.d/mesh ] && /etc/init.d/mesh enable >/dev/null 2>&1
for s in 97-wifi-roaming 99-dawn-roaming; do
	[ -x "/etc/init.d/$$s" ] && "/etc/init.d/$$s" enable >/dev/null 2>&1
	[ -x "/etc/init.d/$$s" ] && "/etc/init.d/$$s" cron_enable >/dev/null 2>&1
done
if [ -x /etc/init.d/nginx ] && [ -f /etc/nginx/conf.d/mesh-sync.locations ] \
	&& [ -f /etc/nginx/uwsgi_params ] \
	&& grep -q 'conf\.d/\*\.locations' /etc/config/nginx 2>/dev/null; then
	/etc/init.d/nginx reload >/dev/null 2>&1
fi
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -x /etc/init.d/mesh ] && /etc/init.d/mesh stop >/dev/null 2>&1
[ -x /etc/init.d/mesh ] && /etc/init.d/mesh disable >/dev/null 2>&1
for s in 97-wifi-roaming 99-dawn-roaming; do
	[ -x "/etc/init.d/$$s" ] && "/etc/init.d/$$s" cron_disable >/dev/null 2>&1
	[ -x "/etc/init.d/$$s" ] && "/etc/init.d/$$s" disable >/dev/null 2>&1
done
exit 0
endef

$(eval $(call BuildPackage,luci-app-mesh))
