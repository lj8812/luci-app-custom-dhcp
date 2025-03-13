-- /usr/lib/lua/luci/model/cbi/admin_custom-dhcp/clients.lua
local uci = luci.model.uci.cursor()
local sys = require "luci.sys"
local ip = require "luci.ip"

m = Map("custom-dhcp", translate("DHCP Client Management"),
    translate("Configure per-client DHCP options"))

-- ███ 辅助函数 ████████████████████████████████████████████████
local function safe_upper(str)
    return tostring(str or ""):upper()
end

local mac = {
    format = {
        display = function(raw)
            raw = safe_upper(raw):gsub("[^%x]", "")
            return (#raw == 12) and raw:gsub("(..)(..)(..)(..)(..)(..)", "%1:%2:%3:%4:%5:%6") or nil
        end,
        storage = function(raw)
            raw = safe_upper(raw):gsub("[^%x]", "")
            return (#raw == 12) and raw or nil
        end
    }
}

local function validate_ipv4(value)
    local cleaned = tostring(value or ""):gsub("%s+", "")
    return ip.IPv4(cleaned) and cleaned or nil
end

local function validate_hostname(value)
    local cleaned = tostring(value or ""):gsub("%s+", ""):sub(1,63)
    return cleaned:match("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$") and cleaned or nil
end

-- ███ 默认值配置 ████████████████████████████████████████████████
local function get_network_defaults()
    local cursor = luci.model.uci.cursor()
    return {
        lan_ip = cursor:get("network", "lan", "ipaddr") or "192.168.1.1",
        netmask = cursor:get("network", "lan", "netmask") or "255.255.255.0",
        dhcp_start = tonumber(cursor:get("dhcp", "lan", "start")) or 100
    }
end

local defaults = get_network_defaults()
defaults.base_ip = (ip.IPv4(defaults.lan_ip, defaults.netmask):minhost() + defaults.dhcp_start - 1):string()

-- ███ 设备发现（修复重点）█████████████████████████████████████████████
local function scan_devices()
    local devices = {}
    
    -- 1. 优先加载静态配置
    uci:foreach("dhcp", "host", function(s)
        if s.mac and s.ip then
            local mac_fmt = mac.format.display(s.mac)
            if mac_fmt then
                devices[mac_fmt] = {
                    ip = s.ip,
                    static = true,
                    active = false,
                    source = "Static Config"
                }
            end
        end
    end)

    -- 2. 合并动态ARP设备
    local arp_entries = sys.exec("ip -4 neigh show 2>/dev/null") or ""
    for line in arp_entries:gmatch("[^\r\n]+") do
        local ip_addr, raw_mac = line:match("^(%S+)%s+.+lladdr%s+(%S+)")
        if ip_addr and raw_mac then
            local mac_fmt = mac.format.display(raw_mac)
            if mac_fmt and not devices[mac_fmt] then  -- 不覆盖静态配置
                devices[mac_fmt] = {
                    ip = ip_addr,
                    active = true,
                    source = "ARP"
                }
            end
        end
    end

    -- 生成排序列表（静态置顶）
    local sorted = {}
    for mac_addr, data in pairs(devices) do
        table.insert(sorted, {
            mac = mac_addr,
            display = string.format("%s %s | IP: %s | %s",
                data.static and "★" or (data.active and "●" or "○"),
                mac_addr,
                data.ip,
                data.source
            ),
            static = data.static or false
        })
    end
    
    table.sort(sorted, function(a,b)
        if a.static ~= b.static then
            return a.static  -- 静态规则置顶
        end
        return a.mac < b.mac
    end)
    
    return sorted
end

-- ███ 界面配置 ██████████████████████████████████████████████████
s = m:section(TypedSection, "client", translate("Clients"))
s.template = "cbi/tblsection"
s.addremove = true
s.anonymous = true

-- MAC地址下拉列表（动态刷新）
mac_input = s:option(ListValue, "mac", translate("MAC Address"))
mac_input.rmempty = false

function mac_input.cfgvalue(self, section)
    -- 每次访问时重新加载设备列表
    self:value("", "-- 选择设备 --")
    for _, dev in ipairs(scan_devices()) do
        self:value(dev.mac, dev.display)
    end
    return self.super.cfgvalue(self, section)
end

-- 主机名输入
hostname = s:option(Value, "hostname", translate("Hostname"))
hostname.placeholder = "留空自动生成（如：client-A1B2）"
hostname.datatype = "hostname"

function hostname.validate(self, value)
    return value == "" or validate_hostname(value)
end

-- IP配置字段
local function create_ip_field(field, title)
    local o = s:option(Value, field, title)
    o.datatype = "ip4addr"
    o.rmempty = false
    o.default = defaults[field]
    o.placeholder = defaults[field]
    
    function o.validate(self, value)
        return validate_ipv4(value) or nil
    end
    
    return o
end

create_ip_field("ip", "静态IP")
create_ip_field("gateway", "网关")
create_ip_field("dns", "DNS服务器")

-- ███ 配置处理 ██████████████████████████████████████████████████
function m.on_commit(self)
    -- 清理旧配置
    uci:foreach("dhcp", "host", function(s)
        if s[".name"] and s[".name"]:match("^cust_") then
            pcall(uci.delete, "dhcp", s[".name"])
        end
    end)
    pcall(uci.commit, "dhcp")
    
    -- 处理新配置
    local dhcp_opts = {}
    uci:foreach("custom-dhcp", "client", function(s)
        local data = {
            mac = mac.format.storage(uci:get("custom-dhcp", s[".name"], "mac")),
            ip = validate_ipv4(uci:get("custom-dhcp", s[".name"], "ip")) or defaults.ip,
            gw = validate_ipv4(uci:get("custom-dhcp", s[".name"], "gateway")) or defaults.gateway,
            dns = validate_ipv4(uci:get("custom-dhcp", s[".name"], "dns")) or defaults.dns,
            hostname = validate_hostname(uci:get("custom-dhcp", s[".name"], "hostname")) or ""
        }

        if data.mac and data.ip and data.gw and data.dns then
            -- 生成主机名
            if data.hostname == "" then
                local mac_part = data.mac:sub(-4):gsub("%W", ""):lower()
                data.hostname = "client-"..mac_part
            end

            -- 生成唯一标识
            local tag = string.format("cust_%s_%s",
                data.mac:sub(-4),
                data.ip:match("(%d+%.%d+)$"):gsub("%.", "")
            )

            -- 写入DHCP配置
            pcall(uci.set, "dhcp", tag, "host", {
                mac = mac.format.display(data.mac),
                ip = data.ip,
                name = data.hostname,
                tag = tag
            })

            -- 收集DHCP选项
            table.insert(dhcp_opts, string.format("tag:%s,3,%s", tag, data.gw))
            table.insert(dhcp_opts, string.format("tag:%s,6,%s", tag, data.dns))
        end
    end)

    -- 提交配置并强制刷新
    uci:set("dhcp", "lan", "dhcp_option", dhcp_opts)
    if pcall(uci.commit, "dhcp") then
        os.execute("sleep 1 && /etc/init.d/dnsmasq reload >/dev/null 2>&1")
        luci.http.redirect(luci.dispatcher.build_url("admin/services/custom-dhcp"))
    else
        luci.http.status(500, "配置保存失败")
    end
end

return m
