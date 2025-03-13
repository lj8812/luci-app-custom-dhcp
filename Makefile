include $(TOPDIR)/rules.mk

# 包基本信息
PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your.email@example.com>

# LuCI 元信息
LUCI_TITLE:=Custom DHCP Client Management
LUCI_DEPENDS:=+luci-base +luci-compat +uci
LUCI_PKGARCH:=all

# 国际化配置
LUCI_PKG_LANGUAGES:=zh_Hans

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/luci/luci.mk

# 编译阶段生成 .lmo 文件
define Build/Compile
    $(INSTALL_DIR) $(PKG_BUILD_DIR)/i18n
    $(INSTALL_DATA) ./po/zh_Hans/custom-dhcp.po $(PKG_BUILD_DIR)/i18n/
    $(call Build/Compile/Default)
endef

# 安装阶段部署文件
define Package/$(PKG_NAME)/install
    # 安装翻译文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
    $(INSTALL_DATA) $(PKG_BUILD_DIR)/i18n/custom-dhcp.zh_Hans.lmo $(1)/usr/lib/lua/luci/i18n/
    
    # 安装 CBI 模块
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp
    $(INSTALL_DATA) ./luasrc/model/cbi/admin_custom-dhcp/clients.lua $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp/
    
    # 安装配置文件
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/custom-dhcp $(1)/etc/config/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
