include $(TOPDIR)/rules.mk

# 插件基础信息
PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1

# 定义包信息
LUCI_TITLE:=Custom DHCP Configuration
LUCI_DESCRIPTION:=A custom DHCP configuration interface for OpenWrt
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

# 引入 OpenWrt 包管理配置
include $(TOPDIR)/feeds/luci/luci.mk

# 编译阶段：将 .po 文件转换为 .lmo
define Build/Compile
    # 创建临时编译目录
    mkdir -p $(PKG_BUILD_DIR)/i18n
    
    # 遍历所有 .po 文件并生成 .lmo
    $(foreach po_file, $(wildcard ${CURDIR}/po/*/*.po), \
        po2lmo $(po_file) $(PKG_BUILD_DIR)/i18n/$(basename $(notdir $(po_file))).lmo; \
    )
endef

# 安装阶段：将文件复制到目标目录
define Package/$(PKG_NAME)/install
    # 安装 Lua 文件、配置和国际化文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
    
    # 复制 Lua 文件
    $(INSTALL_DATA) ./files/luci/controller/custom-dhcp.lua $(1)/usr/lib/lua/luci/controller/
    $(INSTALL_DATA) ./files/luci/model/cbi/custom-dhcp.lua $(1)/usr/lib/lua/luci/model/cbi/
    
    # 复制配置文件
    $(INSTALL_CONF) ./files/etc/config/custom_dhcp $(1)/etc/config/
    
    # 复制国际化文件
    $(INSTALL_DATA) $(PKG_BUILD_DIR)/i18n/*.lmo $(1)/usr/lib/lua/luci/i18n/
endef

# 调用 OpenWrt 构建函数
$(eval $(call BuildPackage,$(PKG_NAME)))
