module("luci.controller.admin.custom-dhcp", package.seeall)

function index()
    -- 主入口直接指向客户端管理页面，并删除设置菜单
    entry({"admin", "services", "custom-dhcp"}, cbi("admin_custom-dhcp/clients"), _("Custom DHCP"), 60)
    
    -- 如果需要保留子菜单入口（可选），取消下面这行注释
    -- entry({"admin", "services", "custom-dhcp", "clients"}, cbi("admin_custom-dhcp/clients"), _("Client Management"), 10)
end
