# Copyright (C) 2018-2026 Lienol <lawlienol@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
#
# ---------------------------------------------------------------------------
# 来源与改造说明（mayipashu fork，2026-11）
#   上游：https://github.com/kiddin9/op-packages 的 luci-app-kodexplorer/
#        （Kwrt / openwrt.ai 使用的版本，Lienol 原作）
#   本仓库固化原因：三方仓库随时可能下架（此前 xxosdev/luci-app-mesh 已 404），
#        故把整包连同 Kwrt 的 kodbox.patch 一起固化，构建只依赖本仓库。
#
#   Kwrt 的 kodbox.patch 已并入下列文件（上游 op-packages 已直接收录补丁后的版本）：
#     ① init.d/kodexplorer：如果系统里存在 /etc/nginx/conf.d/luci.locations
#        （即 LuCI 本身跑在 nginx 上，luci-nginx 场景），就把 kodexplorer 的
#        server 块写进 /etc/nginx/conf.d/kodexplorer.conf 并 reload nginx；
#        否则保持原行为，单独起一个 nginx 实例。
#        —— 本固件用 uhttpd，走 else 分支：kodexplorer 自带 nginx 听 8081。
#     ② controller/kodexplorer.lua：nginx_status 检测去掉 "grep kodexplorer"，
#        否则自带 nginx 进程命令行里没有 kodexplorer 字样，状态永远显示未运行。
#     ③ view/kodexplorer/status.htm：打开状态页时顺手把 php8-fpm 拉起来，
#        避免「服务已启用但 fpm 没跑」导致页面 502。
#
#   ⚠ kodexplorer 本体（KodExplorer/kodbox 的 PHP 程序）**不编译进固件**：
#     上游设计是装好后在 LuCI 页面里填下载地址，运行时 wget 到
#     project_directory（默认 /tmp/kodexplorer）。本包只提供 nginx/php 配置
#     模板、init 脚本和界面。
# ---------------------------------------------------------------------------

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-kodexplorer
PKG_VERSION:=20220109
PKG_RELEASE:=4

LUCI_TITLE:=LuCI support for KodExplorer
LUCI_PKGARCH:=all

# 把上游 config 段里的 select 同时写成硬依赖：
#   · select 只在 menuconfig 里生效，若构建脚本直接写 .config，
#     依赖不会被"选择"进来，php8/nginx 漏编会导致界面上按钮全废；
#   · LUCI_DEPENDS 直接进 ipk 的 DEPENDS，defconfig 求闭包时一定会带上。
#   两处都保留（select 给 menuconfig 用户，LUCI_DEPENDS 给纯 .config 构建）。
LUCI_DEPENDS:=+nginx-ssl +unzip +zoneinfo-asia \
	+php8 +php8-fastcgi +php8-fpm \
	+php8-mod-curl +php8-mod-dom +php8-mod-gd +php8-mod-iconv \
	+php8-mod-mbstring +php8-mod-opcache +php8-mod-pdo \
	+php8-mod-pdo-mysql +php8-mod-pdo-sqlite +php8-mod-session \
	+php8-mod-sqlite3 +php8-mod-xml +php8-mod-xmlreader \
	+php8-mod-xmlwriter +php8-mod-zip

define Package/$(PKG_NAME)/config

config PACKAGE_$(PKG_NAME)_depends
	depends on PACKAGE_$(PKG_NAME)
	bool
	default y
	select PACKAGE_nginx-ssl
	select PACKAGE_unzip
	select PACKAGE_zoneinfo-asia
	select PACKAGE_php8
	select PACKAGE_php8-fastcgi
	select PACKAGE_php8-fpm
	select PACKAGE_php8-mod-curl
	select PACKAGE_php8-mod-dom
	select PACKAGE_php8-mod-gd
	select PACKAGE_php8-mod-iconv
	select PACKAGE_php8-mod-mbstring
	select PACKAGE_php8-mod-opcache
	select PACKAGE_php8-mod-pdo
	select PACKAGE_php8-mod-pdo-mysql
	select PACKAGE_php8-mod-pdo-sqlite
	select PACKAGE_php8-mod-session
	select PACKAGE_php8-mod-sqlite3
	select PACKAGE_php8-mod-xml
	select PACKAGE_php8-mod-xmlreader
	select PACKAGE_php8-mod-xmlwriter
	select PACKAGE_php8-mod-zip

endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
