include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your.email@example.com>

LUCI_TITLE:=Custom DHCP Client Management
LUCI_DEPENDS:=+luci-base +luci-compat +uci
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
    # 安装LuCI组件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/admin
    $(INSTALL_DATA) ./luasrc/controller/admin/custom-dhcp.lua $(1)/usr/lib/lua/luci/controller/admin/
    
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp
    $(INSTALL_DATA) ./luasrc/model/cbi/admin_custom-dhcp/clients.lua $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp/

    # 安装配置文件
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/custom-dhcp $(1)/etc/config/

    # 安装初始化脚本
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/custom-dhcp $(1)/etc/init.d/
endef

# 国际化配置
PO_CONFIG:=../../build/i18n-config
PO_LANGUAGES:=zh_Hans

$(eval $(call BuildPackage,$(PKG_NAME)))
