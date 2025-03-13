-- /usr/lib/lua/luci/model/cbi/clients.lua
local uci = luci.model.uci.cursor()
local sys = require "luci.sys"
local ip = require "luci.ip"

m = Map("custom-dhcp", translate("DHCP Client Management"),
    translate("Configure per-client DHCP options"))

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

-- 修正的主机名验证函数
local function validate_hostname(value)
    value = tostring(value):gsub("%s+", "")  -- 移除所有空格
    if #value < 1 or #value > 63 then return nil end
    
    -- 允许字母开头，后续可包含字母/数字/连字符，不能以连字符结尾
    if value:match("^[a-zA-Z][a-zA-Z0-9-]*$") and not value:match("-$") then
        return value
    end
    return nil
end

-- ███ 设备发现 ██████████████████████████████████████████████████

local function get_network_devices()
    local devices = {}
    
    -- 优化后的ARP解析命令
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
    
    -- 处理ARP条目
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

    -- 合并静态配置
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

    -- 生成有效列表
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

s = m:section(TypedSection, "client", translate("Clients"))
s.template = "cbi/tblsection"
s.addremove = true
s.anonymous = true

-- MAC地址输入
mac = s:option(Value, "mac", translate("MAC Address"))
mac.rmempty = false
mac:value("", "-- 选择设备 --")

-- 动态加载设备列表
local ok, devices = pcall(get_network_devices)
if ok and devices then
    for _, dev in ipairs(devices) do
        mac:value(dev.mac, dev.display)
    end
end

function mac.validate(self, value)
    return format_mac_storage(value) and format_mac_display(value) or nil
end

-- 增强的主机名输入配置
hostname = s:option(Value, "hostname", translate("Hostname"))
hostname.rmempty = true
hostname.placeholder = "字母开头，可包含数字和连字符（如：iphone13）"
hostname.maxlength = 63

function hostname.validate(self, value)
    -- 输入预处理步骤
    local clean_value = value and value:gsub("%s+", "")  -- 移除所有空格
                                      :gsub("[^a-zA-Z0-9-]", "")  -- 移除非允许字符
                                      or ""
    return validate_hostname(clean_value) or nil
end

-- IP类字段模板
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

create_ip_field("Static IP", "ip")
create_ip_field("Gateway", "gateway")
create_ip_field("DNS Server", "dns")

-- ███ 配置提交处理 ██████████████████████████████████████████████

function m.on_commit(self)
    -- 清理旧配置
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

    -- 处理每个客户端配置
    uci:foreach("custom-dhcp", "client", function(s)
        local raw_hostname = uci:get("custom-dhcp", s[".name"], "hostname") or ""
        
        -- 应用相同的清理逻辑
        local clean_hostname = raw_hostname:gsub("%s+", "")
                                          :gsub("[^a-zA-Z0-9-]", "")
        
        local data = {
            mac = format_mac_storage(uci:get("custom-dhcp", s[".name"], "mac") or ""),
            ip = uci:get("custom-dhcp", s[".name"], "ip") or "",
            gw = uci:get("custom-dhcp", s[".name"], "gateway") or "",
            dns = uci:get("custom-dhcp", s[".name"], "dns") or "",
            hostname = validate_hostname(clean_hostname) and clean_hostname or ""  -- 最终验证
        }

        if data.mac and data.ip and data.gw and data.dns then
            local tag = "cust_"..data.mac:sub(-4).."_"..(data.ip:match("(%d+)$") or "0")
            
            -- 写入DHCP配置
            uci:section("dhcp", "host", tag, {
                mac = format_mac_display(data.mac),
                ip = data.ip,
                name = data.hostname ~= "" and data.hostname or nil,
                tag = tag
            })

            -- 设置DHCP选项
            table.insert(dhcp_opts, ("tag:%s,3,%s"):format(tag, data.gw))
            table.insert(dhcp_opts, ("tag:%s,6,%s"):format(tag, data.dns))
        end
    end)

    -- 更新DHCP配置
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
