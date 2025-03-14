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
    local parts = {}
    for part in ip:gmatch("%d+") do
        table.insert(parts, string.format("%02x", tonumber(part)))
    end
    return #parts == 4 and table.concat(parts) or nil
end

-- ███ 设备发现 ██████████████████████████████████████████████████
local function get_network_devices()
    local devices = {}
    
    -- 读取DHCP租约信息
    local leases = {}
    local lease_file = io.open("/var/dhcp.leases", "r")
    if lease_file then
        for line in lease_file:lines() do
            local timestamp, mac, ip_addr, hostname = line:match("^(%d+) (%S+) (%S+) (%S+)")
            if mac and ip_addr then
                local clean_mac = format_mac_display(mac)
                if clean_mac then
                    leases[clean_mac] = (hostname ~= "*" and hostname ~= "") and hostname or nil
                end
            end
        end
        lease_file:close()
    end

    -- 扫描ARP表
    local arp_scan = sys.exec([[
        ip -4 neigh show 2>/dev/null | awk '
            {
                ip = ""; mac = ""
                for (i=1; i<=NF; i++) {
                    if ($i == "lladdr") {
                        mac = $(i+1)
                        ip = $1
                        break
                    }
                }
                if (mac != "" && ip != "") {
                    print ip, mac
                }
            }'
    ]]) or ""
    
    for line in arp_scan:gmatch("[^\r\n]+") do
        local ip_addr, raw_mac = line:match("^(%S+)%s+(%S+)$")
        if ip_addr and raw_mac then
            local clean_mac = format_mac_display(raw_mac)
            if clean_mac and validate_ipv4(ip_addr) then
                devices[clean_mac] = {
                    ip = ip_addr,
                    active = true,
                    hostname = leases[clean_mac],
                    static = false
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
                    static = true,
                    active = false,
                    hostname = s.name or nil
                }
            end
        end
    end)

    -- 生成显示内容
    local sorted = {}
    for mac, data in pairs(devices) do
        -- 新增显示格式逻辑
        local display_info
        if data.hostname then
            display_info = string.format("%s（%s）", data.hostname, data.ip)  -- 主机名+IP格式
        else
            display_info = data.ip  -- 仅显示IP
        end
        
        local type_str = data.static and "静态" or "动态"
        table.insert(sorted, {
            mac = mac,
            display = string.format("%s | %s | %s",  -- 保持三栏结构
                mac,
                display_info,    -- 第二栏显示主机名（IP）或IP
                type_str
            )
        })
    end
    
    table.sort(sorted, function(a,b) return a.mac < b.mac end)
    return sorted
end

-- ███ 界面配置 ██████████████████████████████████████████████████
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
hostname.placeholder = "字母开头，可包含数字和连字符（如：my-phone）"
hostname.maxlength = 63

function hostname.validate(self, value)
    local clean_value = value and value:gsub("%s+", ""):gsub("[^a-zA-Z0-9-]", "") or ""
    return validate_hostname(clean_value) or nil
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
    
    function o.formvalue(self, section)
        return validate_ipv4(Value.formvalue(self, section))
    end
    
    return o
end

create_ip_field("固定IP", "ip")
create_ip_field("网关地址", "gateway")
create_ip_field("DNS服务器", "dns")

-- ███ 配置提交处理 ██████████████████████████████████████████████
function m.on_commit(self)
    -- 清理所有旧host配置
    uci:foreach("dhcp", "host", function(s)
        if s[".name"]:match("^host_") then
            uci:delete("dhcp", s[".name"])
        end
    end)

    -- 获取并过滤现有选项
    local existing_opts = uci:get("dhcp", "lan", "dhcp_option") or {}
    local filtered_opts = {}
    for _, opt in ipairs(existing_opts) do
        if not opt:match("^tag:cust_") then  -- 保留非自定义选项
            table.insert(filtered_opts, opt)
        end
    end

    local dhcp_opts = {}
    local option_cache = {}
    
    -- 处理新配置
    uci:foreach("custom-dhcp", "client", function(section)
        local section_name = section[".name"]
        
        local raw_hostname = uci:get("custom-dhcp", section_name, "hostname") or ""
        local clean_hostname = raw_hostname:gsub("%s+", ""):gsub("[^a-zA-Z0-9-]", "")
        
        local data = {
            mac = format_mac_storage(uci:get("custom-dhcp", section_name, "mac") or ""),
            ip = uci:get("custom-dhcp", section_name, "ip") or "",
            gw = uci:get("custom-dhcp", section_name, "gateway") or "",
            dns = uci:get("custom-dhcp", section_name, "dns") or "",
            hostname = validate_hostname(clean_hostname) and clean_hostname or ""
        }

        if data.mac and data.ip and validate_ipv4(data.gw) and validate_ipv4(data.dns) then
            -- 生成配置标识
            local gw_hex = ip_to_hex(data.gw)
            local dns_hex = ip_to_hex(data.dns)
            if gw_hex and dns_hex then
                local config_id = gw_hex .. "_" .. dns_hex
                
                -- 处理DHCP选项
                if not option_cache[config_id] then
                    local tag = "cust_" .. config_id
                    table.insert(dhcp_opts, string.format("tag:%s,3,%s", tag, data.gw))
                    table.insert(dhcp_opts, string.format("tag:%s,6,%s", tag, data.dns))
                    option_cache[config_id] = true
                end
                
                -- 创建主机记录
                local host_tag = "host_" .. data.mac:gsub(":", "_")
                uci:section("dhcp", "host", host_tag, {
                    mac = format_mac_display(data.mac),
                    ip = data.ip,
                    name = data.hostname ~= "" and data.hostname or nil,
                    tag = "cust_" .. config_id
                })
            end
        end
    end)

    -- 合并新旧选项
    for _, opt in ipairs(dhcp_opts) do
        table.insert(filtered_opts, opt)
    end

    -- 最终设置（关键修复）
    if #filtered_opts > 0 then
        uci:set_list("dhcp", "lan", "dhcp_option", filtered_opts)  -- 使用set_list处理列表
    else
        uci:delete("dhcp", "lan", "dhcp_option")  -- 删除空配置
    end

    -- 提交配置
    if uci:commit("dhcp") then
        os.execute("sleep 1 && /etc/init.d/dnsmasq reload >/dev/null")
    else
        luci.http.status(500, "配置保存失败，请检查系统日志")
    end
end

return m
