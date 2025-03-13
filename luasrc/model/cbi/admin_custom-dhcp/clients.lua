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

-- ███ 设备发现 ██████████████████████████████████████████████████

local function get_network_devices()
    local devices = {}
    
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
            local clean_mac = raw_mac:upper():gsub("[^0-9A-F]", "")
            if #clean_mac == 12 then
                local mac = format_mac_display(clean_mac)
                if mac and validate_ipv4(ip_addr) then
                    devices[mac] = {
                        ip = ip_addr,
                        active = true
                    }
                end
            end
        end
    end

    uci:foreach("dhcp", "host", function(s)
        if s.mac and s.ip then
            local mac = format_mac_display(s.mac)
            if mac and validate_ipv4(s.ip) then
                if not devices[mac] then
                    devices[mac] = {
                        ip = s.ip,
                        static = true,
                        active = false
                    }
                end
            end
        end
    end)

    local sorted = {}
    for mac, data in pairs(devices) do
        table.insert(sorted, {
            mac = mac,
            display = string.format("%s %s | IP: %s | %s",
                data.active and "●" or "○",
                mac,
                data.ip,
                data.static and "静态" or "动态"
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

-- MAC地址输入
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
hostname.placeholder = "字母开头，可包含数字和连字符（如：iphone13）"
hostname.maxlength = 63

function hostname.validate(self, value)
    local clean_value = value and value:gsub("%s+", ""):gsub("[^a-zA-Z0-9-]", "") or ""
    return validate_hostname(clean_value) or nil
end

-- IP配置模板
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
    uci:foreach("dhcp", "host", function(s)
        if s[".name"]:match("^cust_") then
            uci:delete("dhcp", s[".name"])
        end
    end)

    local dhcp_opts = {}
    uci:foreach("dhcp", "dhcp_option", function(_, opt)
        if not opt:match("^tag:cust_") then
            table.insert(dhcp_opts, opt)
        end
    end)

    uci:foreach("custom-dhcp", "client", function(s)
        local raw_hostname = uci:get("custom-dhcp", s[".name"], "hostname") or ""
        local clean_hostname = raw_hostname:gsub("%s+", ""):gsub("[^a-zA-Z0-9-]", "")
        
        local data = {
            mac = format_mac_storage(uci:get("custom-dhcp", s[".name"], "mac") or ""),
            ip = uci:get("custom-dhcp", s[".name"], "ip") or "",
            gw = uci:get("custom-dhcp", s[".name"], "gateway") or "",
            dns = uci:get("custom-dhcp", s[".name"], "dns") or "",
            hostname = validate_hostname(clean_hostname) and clean_hostname or ""
        }

        if data.mac and data.ip and data.gw and data.dns then
            local tag = "cust_"..data.mac:sub(-4).."_"..(data.ip:match("(%d+)$") or "0")
            
            uci:section("dhcp", "host", tag, {
                mac = format_mac_display(data.mac),
                ip = data.ip,
                name = data.hostname ~= "" and data.hostname or nil,
                tag = tag
            })

            table.insert(dhcp_opts, ("tag:%s,3,%s"):format(tag, data.gw))
            table.insert(dhcp_opts, ("tag:%s,6,%s"):format(tag, data.dns))
        end
    end)

    if #dhcp_opts > 0 then
        uci:set("dhcp", "lan", "dhcp_option", dhcp_opts)
    else
        pcall(uci.delete, "dhcp", "lan", "dhcp_option")
    end

    if uci:commit("dhcp") then
        os.execute("sleep 1 && /etc/init.d/dnsmasq reload >/dev/null")
    else
        luci.http.status(500, "配置保存失败，请检查系统日志")
    end
end

return m
