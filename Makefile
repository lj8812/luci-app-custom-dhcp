include $(TOPDIR)/rules.mk

# 包基本信息（必须定义在包含 luci.mk 前）
PKG_NAME:=luci-app-custom-dhcp
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your.email@example.com>

# LuCI 插件元信息
LUCI_TITLE:=Custom DHCP Client Management
LUCI_DEPENDS:=+luci-base +luci-compat +uci
LUCI_PKGARCH:=all

# 国际化配置（必须定义在包含 luci.mk 前）
LUCI_PKG_LANGUAGES:=zh_Hans

# 包含 OpenWrt 基础构建规则
include $(INCLUDE_DIR)/package.mk

# 包含 LuCI 构建宏（必须在变量定义后）
include $(TOPDIR)/feeds/luci/luci.mk

# 强制编译翻译文件（如果构建系统未自动处理）
define Build/Compile
    # 复制 .po 文件到构建目录
    $(INSTALL_DIR) $(PKG_BUILD_DIR)/i18n
    $(INSTALL_DATA) ./po/zh_Hans/custom-dhcp.po $(PKG_BUILD_DIR)/i18n/
    
    # 调用默认编译逻辑
    $(call Build/Compile/Default)
endef

# 安装插件文件
define Package/$(PKG_NAME)/install
    # 安装 LuCI 控制器
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/admin
    $(INSTALL_DATA) ./luasrc/controller/admin/custom-dhcp.lua $(1)/usr/lib/lua/luci/controller/admin/

    # 安装 CBI 配置界面
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp
    $(INSTALL_DATA) ./luasrc/model/cbi/admin_custom-dhcp/clients.lua $(1)/usr/lib/lua/luci/model/cbi/admin_custom-dhcp/

    # 安装配置文件
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/custom-dhcp $(1)/etc/config/

    # 安装初始化脚本（可选）
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/custom-dhcp $(1)/etc/init.d/
endef

# 调用 LuCI 插件构建宏
$(eval $(call BuildPackage,$(PKG_NAME)))
