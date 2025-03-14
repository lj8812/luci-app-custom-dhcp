module("luci.controller.admin.custom-dhcp", package.seeall)

function index()
    -- 直接将菜单名称改为中文（注意文件需保存为 UTF-8 编码）
    entry({"admin", "services", "custom-dhcp"}, cbi("admin_custom-dhcp/clients"), "DHCP服务", 60)
end
