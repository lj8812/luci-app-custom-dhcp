-- /usr/lib/lua/luci/model/cbi/admin_custom-dhcp/clients.lua
local uci = luci.model.uci.cursor()
local sys = require "luci.sys"
local ip = require "luci.ip"

m = Map("custom-dhcp", translate("DHCP客户端管理"),
    translate("为每个设备配置专属DHCP参数"))

-- ███ 辅助函数 ████████████████████████████████████████████████
local function validate_ipv4(value)
    value = tostring(value):gsub("%s+", "")
    if #value == 0 then return nil end
    
    if not value:match("^%d+%.%d+%.%d+%.%d+$") then
        return nil
    end
    
    local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    return (a <= 255 and b <= 255 and c <= 255 and d <= 255) and value or nil
end

local function format_mac_display(raw)
    local clean = raw:upper():gsub("[^0-9A-F]", ""):sub(1,12)
    if #clean ~= 12 then return nil end
    return clean:gsub("(..)(..)(..)(..)(..)(..)", "%1:%2:%3:%4:%5:%6")
end

local function format_mac_storage(raw)
    local clean = raw:upper():gsub("[^0-9A-F]", ""):sub(1,12)
    return (#clean == 12) and clean or nil
end

local function validate_hostname(value)
    value = tostring(value):gsub("%s+", "")
    if #value < 1 or #value > 63 then return nil end
    
    if value:match("^[a-zA-Z][a-zA-Z0-9-]*$") and not value:match("-$") then
        return value
    end
    return nil
end

local function ip_to_hex(ip)
    if not validate_ipv4(ip) then return nil end
    local parts = {}
    for part in ip:gmatch("%d+") do
        local num = tonumber(part)
        if num > 255 then return nil end
        table.insert(parts, string.format("%02x", num))
    end
    return (#parts == 4) and table.concat(parts) or nil
end

-- ███ 设备发现 ██████████████████████████████████████████████████
local function get_network_devices()
    local devices = {}
    
    -- 读取DHCP租约
    local leases = {}
    if nixio.fs.access("/tmp/dhcp.leases") then
        for line in io.lines("/tmp/dhcp.leases") do
            local ts, raw_mac, ip_addr, name = line:match("^(%d+) (%S+) (%S+) (%S+)")
            if raw_mac and ip_addr then
                local mac = format_mac_display(raw_mac)
                if mac then
                    leases[mac] = (name ~= "*" and name ~= "") and name or nil
                end
            end
        end
    end

    -- 扫描ARP表
    local arp_scan = sys.exec([[
        ip -4 neigh show 2>/dev/null | awk '
            $NF == "REACHABLE" || $NF == "STALE" {
                split($5, mac, /@/);
                print $1, mac[1];
            }'
    ]]) or ""
    
    -- 处理在线设备
    for line in arp_scan:gmatch("[^\r\n]+") do
        local ip_addr, raw_mac = line:match("^(%S+)%s+(%S+)$")
        if ip_addr and raw_mac then
            local mac = format_mac_display(raw_mac)
            if mac and validate_ipv4(ip_addr) then
                devices[mac] = {
                    ip = ip_addr,
                    hostname = leases[mac] or "",
                    static = false,
                    active = true
                }
            end
        end
    end

    -- 读取静态配置
    uci:foreach("dhcp", "host", function(s)
        if s.mac and s.ip then
            local mac = format_mac_display(s.mac)
            if mac and validate_ipv4(s.ip) then
                devices[mac] = {
                    ip = s.ip,
                    hostname = s.name or "",
                    static = true,
                    active = false
                }
            end
        end
    end)

    -- 生成显示列表
    local sorted = {}
    for mac, data in pairs(devices) do
        local display
        if data.hostname ~= "" then
            display = string.format("%s | %s (%s) | %s",
                mac, data.hostname, data.ip,
                data.static and "静态" or "动态")
        else
            display = string.format("%s | %s | %s",
                mac, data.ip,
                data.static and "静态" or "动态")
        end
        
        table.insert(sorted, {
            mac = mac,
            display = display,
            data = data
        })
    end
    
    table.sort(sorted, function(a,b) return a.mac < b.mac end)
    return sorted
end

-- ███ 全局设置 ██████████████████████████████████████████████████
s_global = m:section(NamedSection, "global", "global", translate("全局设置"))
s_global.anonymous = true

-- 默认规则按钮
btn_restore = s_global:option(Button, "_restore", translate("默认规则"))
btn_restore.inputtitle = translate("一键恢复默认规则")
btn_restore.inputstyle = "apply"
function btn_restore.write()
    uci:delete_all("custom-dhcp", "client")
    
    -- 修改点：将字段名从'name'改为'hostname'
    local defaults = {
        { mac = "B2:54:B6:96:E4:8C", ip = "192.168.0.168", gateway = "192.168.0.11", dns = "192.168.0.11", hostname = "iphone13" },
        { mac = "CC:29:BD:09:5C:EC", ip = "192.168.0.171", gateway = "192.168.0.1", dns = "192.168.0.1", hostname = "AAP" },
        { mac = "AA:CB:E3:30:D2:FA", ip = "192.168.0.128", gateway = "192.168.0.1", dns = "192.168.0.1", hostname = "iphone12" },
		{ mac = "1E:B6:E5:2B:B0:27", ip = "192.168.0.145", gateway = "192.168.0.1", dns = "192.168.0.1", hostname = "iphone7" }
    }
    
    for _, v in ipairs(defaults) do
        local sid = uci:add("custom-dhcp", "client")
        for key, val in pairs(v) do
            uci:set("custom-dhcp", sid, key, val)
        end
    end
    
    uci:commit("custom-dhcp")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/custom-dhcp"))
end

-- 清空规则按钮
btn_clear = s_global:option(Button, "_clear", translate("清空规则"))
btn_clear.inputtitle = translate("立即清空所有规则")
btn_clear.inputstyle = "remove"
function btn_clear.write()
    uci:delete_all("custom-dhcp", "client")
    uci:commit("custom-dhcp")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/custom-dhcp"))
end

-- 自动添加按钮
btn_auto = s_global:option(Button, "_autoadd", translate("添加规则"))
btn_auto.inputtitle = translate("一键添加所有设备")
btn_auto.inputstyle = "apply"
function btn_auto.write()
    local existing_macs = {}
    uci:foreach("custom-dhcp", "client", function(s)
        if s.mac then
            existing_macs[format_mac_storage(s.mac)] = true
        end
    end)
    
    local devices = get_network_devices()
    local added = 0
    
    for _, dev in ipairs(devices) do
        local raw_mac = format_mac_storage(dev.mac)
        if not existing_macs[raw_mac] then
            local sid = uci:add("custom-dhcp", "client")
            uci:set("custom-dhcp", sid, "mac", dev.mac)
            uci:set("custom-dhcp", sid, "ip", dev.data.ip)
            -- 新增：添加主机名字段
            if dev.data.hostname and #dev.data.hostname > 0 then
                uci:set("custom-dhcp", sid, "hostname", dev.data.hostname)
            end
            uci:set("custom-dhcp", sid, "gateway", uci:get("network", "lan", "ipaddr") or "192.168.1.1")
            uci:set("custom-dhcp", sid, "dns", uci:get("network", "lan", "dns") or uci:get("network", "lan", "ipaddr") or "192.168.1.1")
            added = added + 1
        end
    end
    
    if added > 0 then
        uci:commit("custom-dhcp")
    end
    luci.http.redirect(luci.dispatcher.build_url("admin/services/custom-dhcp"))
end

-- ███ 客户端列表 ██████████████████████████████████████████████████
s = m:section(TypedSection, "client", translate("客户端列表"))
s.template = "cbi/tblsection"
s.addremove = true
s.anonymous = true

-- MAC地址选择
mac = s:option(Value, "mac", translate("MAC地址"))
mac.rmempty = false
mac:value("", "-- 选择设备 --")

local ok, devices = pcall(get_network_devices)
if ok and devices then
    for _, dev in ipairs(devices) do
        mac:value(dev.mac, dev.display)
    end
end

function mac.validate(self, value)
    return format_mac_storage(value) and format_mac_display(value) or nil
end

-- 主机名配置
hostname = s:option(Value, "hostname", translate("设备名称"))
hostname.rmempty = true
hostname.placeholder = "字母开头，可包含数字和连字符"
hostname.maxlength = 63

function hostname.validate(self, value)
    return validate_hostname(value:gsub("%s+", "")) or nil
end

-- IP配置字段
local function create_ip_field(title, field)
    local o = s:option(Value, field, translate(title))
    o.datatype = "ip4addr"
    o.rmempty = false
    o.placeholder = "例如：192.168.1.1"
    
    function o.validate(self, value)
        return validate_ipv4(value) or nil
    end
    
    return o
end

create_ip_field("固定IP", "ip")
create_ip_field("网关地址", "gateway")
create_ip_field("DNS服务器", "dns")

-- ███ 配置提交 ██████████████████████████████████████████████████
function m.on_commit(self)
    -- 清理旧配置
    uci:foreach("dhcp", "host", function(s)
        if s[".name"]:match("^cust_") then
            uci:delete("dhcp", s[".name"])
        end
    end)

    -- 初始化配置缓存
    local option_cache = {}
    local dhcp_opts = {}
    local tag_map = {}

    -- 处理每个客户端
    uci:foreach("custom-dhcp", "client", function(s)
        local data = {
            mac = format_mac_storage(uci:get("custom-dhcp", s[".name"], "mac")),
            ip = validate_ipv4(uci:get("custom-dhcp", s[".name"], "ip")),
            gw = validate_ipv4(uci:get("custom-dhcp", s[".name"], "gateway")),
            dns = validate_ipv4(uci:get("custom-dhcp", s[".name"], "dns")),
            hostname = validate_hostname(uci:get("custom-dhcp", s[".name"], "hostname") or "")
        }

        if data.mac and data.ip and data.gw and data.dns then
            -- 生成配置标识
            local gw_hex = ip_to_hex(data.gw)
            local dns_hex = ip_to_hex(data.dns)
            if gw_hex and dns_hex then
                local config_id = gw_hex .. "_" .. dns_hex
                
                -- 合并相同配置
                if not option_cache[config_id] then
                    local tag = "cust_" .. config_id
                    table.insert(dhcp_opts, ("tag:%s,3,%s"):format(tag, data.gw))
                    table.insert(dhcp_opts, ("tag:%s,6,%s"):format(tag, data.dns))
                    option_cache[config_id] = tag
                end
                
                -- 创建主机条目
                local host_id = "cust_" .. data.mac:gsub(":", "")
                uci:section("dhcp", "host", host_id, {
                    mac = format_mac_display(data.mac),
                    ip = data.ip,
                    name = data.hostname ~= "" and data.hostname or nil,
                    tag = option_cache[config_id]
                })
            end
        end
    end)

    -- 更新DHCP选项
    if #dhcp_opts > 0 then
        uci:set("dhcp", "lan", "dhcp_option", dhcp_opts)
    else
        uci:delete("dhcp", "lan", "dhcp_option")
    end

    -- 提交配置
    if uci:commit("dhcp") then
        os.execute("sleep 1 && /etc/init.d/dnsmasq reload >/dev/null")
    else
        luci.http.status(500, "配置保存失败")
    end
end

return m
