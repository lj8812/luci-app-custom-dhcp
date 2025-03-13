include $(TOPDIR)/rules.mk

# 插件基本信息
PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1

# Luci 插件定义
LUCI_TITLE:=Custom DHCP Configuration
LUCI_DESCRIPTION:=Web interface for custom DHCP settings
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

# 引入 OpenWrt 构建环境
include $(TOPDIR)/feeds/luci/luci.mk

# 编译阶段：生成 .lmo 文件
define Build/Compile
    # 创建临时目录
    mkdir -p $(PKG_BUILD_DIR)/i18n
    
    # 将 .po 文件转换为 .lmo
    $(foreach po_file, $(wildcard ${CURDIR}/po/*/*.po), \
        po2lmo $(po_file) $(PKG_BUILD_DIR)/i18n/$(basename $(notdir $(po_file))).lmo; \
    )
endef

# 安装阶段
define Package/$(PKG_NAME)/install
    # 安装配置文件
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/custom-dhcp $(1)/etc/config/
    
    # 安装初始化脚本
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/custom-dhcp $(1)/etc/init.d/
    
    # 安装 Lua 控制器
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/admin
    $(INSTALL_DATA) ./luasrc/controller/admin/custom-dhcp.lua $(1)/usr/lib/lua/luci/controller/admin/
    
    # 安装 Lua 模型
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp
    $(INSTALL_DATA) ./luasrc/model/cbi/admin_custom-dhcp/clients.lua $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp/
    
    # 安装国际化文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
    $(INSTALL_DATA) $(PKG_BUILD_DIR)/i18n/*.lmo $(1)/usr/lib/lua/luci/i18n/
endef

# 调用构建函数
$(eval $(call BuildPackage,$(PKG_NAME)))
