include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ota
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Your Name <your-email@example.com>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ota
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OTA Update for iStoreOS
  DEPENDS:=+luci-base +curl +jsonfilter  # 仅保留必需依赖，删除不存在的依赖
  PKGARCH:=all
endef

define Package/luci-app-ota/description
  Simple OTA update tool for iStoreOS.
endef

define Build/Compile
# 若无需编译（纯脚本/配置文件），留空
endef

define Package/luci-app-ota/install
  # 安装LuCI页面（根据实际文件调整路径）
  $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
  $(INSTALL_DATA) ./files/luci/controller/ota.lua $(1)/usr/lib/lua/luci/controller/

  $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/ota
  $(INSTALL_DATA) ./files/luci/model/cbi/ota/settings.lua $(1)/usr/lib/lua/luci/model/cbi/ota/
endef

$(eval $(call BuildPackage,luci-app-ota))
