#
# rtp2httpd —— 用本人仓库（mayipashu/rtp2httpd）的源码编译
#
# 与 feeds/packages/net/rtp2httpd（官方 3.16.0）的区别只有「源码地址」：
#   - 源码：https://github.com/mayipashu/rtp2httpd @ d7cc99a（v3.17.2）
#     该 commit 已把定制播放器 Web UI 重新生成进 src/embedded_web_data.h，
#     因此编译阶段不需要 node / pnpm，直接 gcc 编即可。
#   - init / 配置 / LuCI 依旧沿用官方（UCI instance 段式），界面完全兼容：
#     luci-app-rtp2httpd（feeds/luci）的 DEPENDS += rtp2httpd 会落到本包。
#
# diy-part1.sh 会先删掉 feeds 里同名的官方包，再把本目录拷进 package/custom，
# 避免同名 Package 被索引两次（否则实际编进去的是哪份取决于扫描顺序）。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=rtp2httpd
PKG_VERSION:=3.17.2
PKG_RELEASE:=1

PKG_MAINTAINER:=Stackie Jia <jsq2627@gmail.com>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=LICENSE

# 固定到带定制 Web UI 的 commit（tar.gz 的 sha256 已本地校验）
PKG_SOURCE_REF:=d7cc99a
PKG_SOURCE:=rtp2httpd-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/mayipashu/rtp2httpd/tar.gz/$(PKG_SOURCE_REF)?
PKG_HASH:=9d6e524f427813f91f4badf8d3c2b07138533c9805b1cd598d3530e0fa42daaa

# codeload 的 commit 归档解压后自带 <repo>-<ref>/ 顶层目录，而默认
# PKG_BUILD_DIR 是 rtp2httpd-3.17.2，路径对不上；这里指向实际解压目录。
# （Build/Compile 里另有一层兜底判断，防止不同版本 buildroot 解压方式差异）
PKG_BUILD_DIR:=$(BUILD_DIR)/rtp2httpd-$(PKG_SOURCE_REF)

include $(INCLUDE_DIR)/package.mk

define Package/rtp2httpd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Multicast RTP/RTSP to Unicast HTTP stream converter
  URL:=https://rtp2httpd.com/en/
endef

define Package/rtp2httpd/description
  rtp2httpd converts RTP/UDP/RTSP media into http stream.
  It acts as a tiny HTTP server. When client connect,
  pre-configured multicast RTP service is choosen by URL.
  Program then join pre-configured multicast address and translate
  incoming RTP data to HTTP stream.
endef

# 源码清单对应上游 CMakeLists.txt 的 COMMON_SOURCES + Linux poller。
# 这里显式列出而不是 $(wildcard)：Makefile 解析发生在解压之前，wildcard 会
# 被固化成空列表，首次编译直接 "no input files"。
RTP2HTTPD_SOURCES := \
	src/rtp2httpd.c \
	src/supervisor.c \
	src/pid_file.c \
	src/configuration.c \
	src/access_log.c \
	src/http.c \
	src/http_headers.c \
	src/http_fetch.c \
	src/service.c \
	src/url_template.c \
	src/rtp.c \
	src/rtp_reorder.c \
	src/rtp_fec.c \
	src/rs_fec.c \
	src/multicast.c \
	src/fcc.c \
	src/fcc_telecom.c \
	src/fcc_huawei.c \
	src/stream.c \
	src/rtsp.c \
	src/http_chunked_decoder.c \
	src/http_proxy.c \
	src/http_proxy_rewrite.c \
	src/stun.c \
	src/snapshot.c \
	src/timezone.c \
	src/status.c \
	src/connection.c \
	src/worker.c \
	src/unix_socket.c \
	src/buffer_pool.c \
	src/send_queue.c \
	src/m3u.c \
	src/epg.c \
	src/embedded_web.c \
	src/utils.c \
	src/poller_epoll.c \
	src/vendor/hashmap/hashmap.c \
	src/vendor/md5/md5.c \
	src/vendor/picohttpparser/picohttpparser.c

define Build/Compile
	$(INSTALL_DIR) $(PKG_INSTALL_DIR)/usr/bin
	SRC="$(PKG_BUILD_DIR)"; \
	if [ ! -f "$$SRC/src/rtp2httpd.c" ] && \
	   [ -f "$(PKG_BUILD_DIR)/rtp2httpd-$(PKG_SOURCE_REF)/src/rtp2httpd.c" ]; then \
		SRC="$(PKG_BUILD_DIR)/rtp2httpd-$(PKG_SOURCE_REF)"; \
	fi; \
	test -f "$$SRC/src/rtp2httpd.c" || { \
		echo "ERROR: rtp2httpd 源码未解压到 $(PKG_BUILD_DIR)" >&2; \
		ls -la "$(PKG_BUILD_DIR)" >&2 2>/dev/null || true; \
		exit 1; \
	}; \
	cd "$$SRC" && $(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -D_GNU_SOURCE \
		-DSYSCONFDIR='"/etc"' -DPACKAGE='"rtp2httpd"' -DVERSION='"$(PKG_VERSION)"' \
		-O3 -fstack-protector-strong \
		-I src -o $(PKG_INSTALL_DIR)/usr/bin/rtp2httpd \
		$$(for f in $(RTP2HTTPD_SOURCES); do echo "$$SRC/$$f"; done) \
		-lpthread -lm
endef

define Package/rtp2httpd/conffiles
/etc/config/rtp2httpd
endef

define Package/rtp2httpd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/rtp2httpd $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/rtp2httpd.config $(1)/etc/config/rtp2httpd
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/rtp2httpd.init $(1)/etc/init.d/rtp2httpd
endef

$(eval $(call BuildPackage,rtp2httpd))
