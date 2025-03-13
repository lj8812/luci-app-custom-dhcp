include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DEPENDS:=luci-i18n-base-zh-cn
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

LUCI_TITLE:=Custom DHCP Management Interface
LUCI_DEPENDS:=+luci-base +luci-compat +luci-i18n-base-zh-cn
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
    # 配置文件
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_DATA) ./root/etc/config/custom-dhcp $(1)/etc/config/custom-dhcp

    # Init脚本
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/custom-dhcp $(1)/etc/init.d/custom-dhcp

    # 控制器
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
    $(INSTALL_DATA) ./luasrc/controller/admin/custom-dhcp.lua $(1)/usr/lib/lua/luci/controller/

    # CBI模型
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp
    $(INSTALL_DATA) ./luasrc/model/cbi/admin_custom-dhcp/clients.lua $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp/

endef

$(eval $(call BuildPackage,$(PKG_NAME)))
