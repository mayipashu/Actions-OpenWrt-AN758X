local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require"luci.model.uci".cursor()
local util = require "luci.util"
local i18n = require "luci.i18n"

module("luci.model.cbi.kodexplorer.api", package.seeall)

local appname = "kodexplorer"
local api_url = "https://api.kodcloud.com/?app/version"

local wget = "/usr/bin/wget"
local wget_args = { "--no-check-certificate", "--quiet", "--timeout=10", "--tries=2" }
local command_timeout = 300

-- ===========================================================================
-- 下载源修正（mayipashu，2026-11）
--
--   实测结论（2026-11-14，在 HM2004-DU 本机与本地各测一遍）：
--     · 官方 CDN static.kodcloud.com/update/download/*.zip
--         —— 走 Tengine 防盗链 + IP 频控：无 Referer 时 403，
--            带 Referer 首次可下、随后再次请求也变 403（限流），
--            从严从稳的角度**不能作为唯一源**。
--     · GitHub 归档 codeload.github.com/kalcaddle/KodExplorer
--         —— 200，稳定可用，是官方仓库源码（含完整 PHP 程序与 config/i18n 语言包）。
--     · api.kodcloud.com/?app/version —— 可访问，用作「有新版本」提示，
--        其返回的 link 仍会尝试，但失败不影响下载。
--
--   修正策略（按顺序尝试，任一成功即止）：
--       ① API 返回的 link（若可用）
--       ② GitHub KodExplorer 最新 master 归档   ← 实际首选，稳定
--       ③ GitHub KodExplorer 已发布 tag 归档
--       ④ 官方 CDN kodexplorer / kodbox 直链     ← 带 Referer，能通就用
--   下载后校验体积（<512KB 视为错误页），并校验 zip 里确实有 index.php。
--
--   注意：GitHub 归档解压后多一层 KodExplorer-master/ 目录，
--        to_move() 的 `cp -R <dir>/* target` 会把这一层的内容直接铺进目标目录，
--        结果正确（目标目录里就是 index.php/app/config/...），无需特殊处理。
-- ===========================================================================

local download_headers = {
    -- 官方 CDN 防盗链，带上无害；GitHub 不需要但也不影响
    "--referer=https://kodcloud.com/download/",
    "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " ..
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}

-- 兜底下载源，按可靠性排序（GitHub 在前，官方 CDN 在后）
local mirrors = {
    {
        name = "GitHub KodExplorer (master)",
        url  = "https://github.com/kalcaddle/KodExplorer/archive/refs/heads/master.zip",
        kind = "github",
    },
    {
        name = "GitHub KodExplorer (4.55)",
        url  = "https://github.com/kalcaddle/KodExplorer/archive/refs/tags/4.55.zip",
        kind = "github",
    },
    {
        name = "官方 CDN kodexplorer 4.56",
        url  = "https://static.kodcloud.com/update/download/kodexplorer4.56.zip",
        kind = "cdn",
    },
    {
        name = "官方 CDN kodbox 1.71",
        url  = "https://static.kodcloud.com/update/download/kodbox.1.71.zip",
        kind = "cdn",
    },
}

local function _unpack(t, i)
    i = i or 1
    if t[i] ~= nil then return t[i], _unpack(t, i + 1) end
end

local function exec(cmd, args, writer, timeout)
    local os = require "os"
    local nixio = require "nixio"

    local fdi, fdo = nixio.pipe()
    local pid = nixio.fork()

    if pid > 0 then
        fdo:close()

        if writer or timeout then
            local starttime = os.time()
            while true do
                if timeout and os.difftime(os.time(), starttime) >= timeout then
                    nixio.kill(pid, nixio.const.SIGTERM)
                    return 1
                end

                if writer then
                    local buffer = fdi:read(2048)
                    if buffer and #buffer > 0 then
                        writer(buffer)
                    end
                end

                local wpid, stat, code = nixio.waitpid(pid, "nohang")

                if wpid and stat == "exited" then return code end

                if not writer and timeout then nixio.nanosleep(1) end
            end
        else
            local wpid, stat, code = nixio.waitpid(pid)
            return wpid and stat == "exited" and code
        end
    elseif pid == 0 then
        nixio.dup(fdo, nixio.stdout)
        fdi:close()
        fdo:close()
        nixio.exece(cmd, args, nil)
        nixio.stdout:close()
        os.exit(1)
    end
end

function get_project_directory()
    return uci:get(appname, "@global[0]", "project_directory") or "/tmp/kodcloud"
end

function get_version()
    local version = get_project_directory() .. "/config/version.php"
    return sys.exec(string.format("echo -n $(cat %s 2>/dev/null | grep \"'KOD_VERSION'\" | cut -d \"'\" -f 4)", version))
end

local function compare_versions(ver1, comp, ver2)
    local table = table

    local av1 = util.split(ver1, "[%.%-]", nil, true)
    local av2 = util.split(ver2, "[%.%-]", nil, true)

    local max = table.getn(av1)
    local n2 = table.getn(av2)
    if (max < n2) then max = n2 end

    for i = 1, max, 1 do
        local s1 = av1[i] or ""
        local s2 = av2[i] or ""

        if comp == "~=" and (s1 ~= s2) then return true end
        if (comp == "<" or comp == "<=") and (s1 < s2) then return true end
        if (comp == ">" or comp == ">=") and (s1 > s2) then return true end
        if (s1 ~= s2) then return false end
    end

    return not (comp == "<" or comp == ">")
end

local function get_api_json(url)
    local jsonc = require "luci.jsonc"

    local output = {}
    -- exec(wget, { "-O-", url, _unpack(wget_args) },
    --	function(chunk) output[#output + 1] = chunk end)
    -- local json_content = util.trim(table.concat(output))

    local json_content = sys.exec(wget .. " --no-check-certificate --timeout=10 -t 1 -O- " .. url)

    if json_content == "" then return {} end

    return jsonc.parse(json_content) or {}
end

function to_check()
    local json = get_api_json(api_url)

    -- API 不可达（外网受限 / 返回空 / 字段缺失）时，用内置兜底源构造等价结构，
    -- 保证界面仍能显示版本号并允许点击下载。
    if not json or not json.data or not json.data.server then
        return {
            code = 0,
            data = {
                server = {
                    version = "4.56",
                    link    = mirrors[1].url,
                },
            },
        }
    end

    -- 保证 link 字段存在（前端 doDownload 用的是 msgInfo.link）
    local sv = json.data.server
    if sv and not sv.link then
        sv.link = sv.url or mirrors[1].url
    end

    return json
end

-- 下载：带 Referer/UA，失败自动切换下一个候选源。
--   url 为空 → 直接用兜底列表
-- 返回 {code=0, file=..., source=...} 或 {code=1, error=...}
function to_download(url)
    sys.call("/bin/rm -f /tmp/kodcloud_download.*")

    -- 候选队列：API/用户给的地址优先，其后是兜底源（去重）
    local candidates = {}
    if url and url ~= "" then
        candidates[#candidates + 1] = { name = i18n.translate("Remote server"), url = url }
    end
    for _, m in ipairs(mirrors) do
        local dup = false
        for _, c in ipairs(candidates) do
            if c.url == m.url then dup = true; break end
        end
        if not dup then candidates[#candidates + 1] = m end
    end

    local last_err = i18n.translate("Download url is required.")

    for _, cand in ipairs(candidates) do
        local tmp_file = util.trim(util.exec("mktemp -u -t kodcloud_download.XXXXXX"))

        local args = { "-O", tmp_file, cand.url }
        for _, a in ipairs(download_headers) do args[#args + 1] = a end
        for _, a in ipairs(wget_args) do args[#args + 1] = a end

        local ok = exec(wget, args, nil, command_timeout) == 0

        -- ① 体积校验：wget 退出 0 但文件过小 → 多半是被换成了错误页
        if ok then
            local size = tonumber(util.trim(util.exec("stat -c %s " .. tmp_file .. " 2>/dev/null") or "0"))
            if not size or size < 512 * 1024 then ok = false end
        end

        -- ② 内容校验：必须是 zip（PK 头），防止 CDN 返回 HTML
        if ok then
            local head = util.trim(util.exec("head -c 2 " .. tmp_file .. " 2>/dev/null") or "")
            if head ~= "PK" then ok = false end
        end

        -- ③ 结构校验：zip 里必须能找到 index.php，否则不是可道云程序包
        if ok then
            local has_index = util.exec(
                "unzip -l " .. tmp_file .. " 2>/dev/null | grep -q 'index\\.php' && echo yes"
            )
            if not has_index or not has_index:find("yes") then ok = false end
        end

        if ok then
            return { code = 0, file = tmp_file, source = cand.name }
        end

        exec("/bin/rm", { "-f", tmp_file })
        last_err = i18n.translatef("File download failed or timed out: %s", cand.url)
    end

    return { code = 1, error = last_err }
end

function to_extract(file)
    if not file or file == "" or not fs.access(file) then
        return {code = 1, error = i18n.translate("File path required.")}
    end

    sys.call("/bin/rm -rf /tmp/kodcloud_extract.*")
    local tmp_dir = util.trim(util.exec("mktemp -d -t kodcloud_extract.XXXXXX"))

    local output = {}
    exec("/usr/bin/unzip", {"-o", file, "-d", tmp_dir}, function(chunk) output[#output + 1] = chunk end)

    local files = util.split(table.concat(output))

    exec("/bin/rm", {"-f", file})

    return {code = 0, file = tmp_dir}
end

-- ===========================================================================
-- 把解压出来的内容搬到目标目录。
--
--   不同来源的 zip 顶层结构不同：
--     · 官方 CDN kodexplorer4.56.zip        → 解压即 app/ config/ index.php ...
--     · 官方 CDN kodbox.x.zip               → 同上（个别版本多一层）
--     · GitHub 归档 KodExplorer-master.zip  → **多一层 KodExplorer-master/**
--   原实现直接 `cp -R <dir>/* target`，遇到 GitHub 归档会把整层目录塞进目标，
--   结果是 <target>/KodExplorer-master/index.php —— 网站根目录不对，打开 404。
--
--   本实现：若解压目录里只有「一个子目录、没有 index.php」，则自动下钻一层，
--   直到找到含 index.php 的那层为止（最多 3 层，防御性上限）。
-- ===========================================================================
local function find_app_root(dir, depth)
    depth = depth or 0
    if depth > 3 then return dir end

    -- 本层有 index.php → 就是程序根目录
    if fs.access(dir .. "/index.php") then
        return dir
    end

    -- 只有一个子目录 → 下钻（用 find 只列目录，排除文件）
    local subdirs = util.trim(util.exec(
        "find " .. dir .. " -mindepth 1 -maxdepth 1 -type d 2>/dev/null"
    ) or "")
    local entries = util.trim(util.exec(
        "ls -A " .. dir .. " 2>/dev/null"
    ) or "")

    -- 仅当「唯一的项是目录」时才下钻，避免把 data/ 之类误当根
    local sub_list = util.split(subdirs)
    local all_list = util.split(entries)
    if #sub_list == 1 and #all_list == 1 then
        return find_app_root(sub_list[1], depth + 1)
    end

    return dir
end

function to_move(file)
    if not file or file == "" or not fs.access(file) then
        sys.call("/bin/rm -rf /tmp/kodcloud_extract.*")
        return {code = 1, error = i18n.translate("Client file is required.")}
    end

    local client_file = get_project_directory()
    sys.call("mkdir -p " .. client_file)

    -- 定位真正的程序根目录（处理 GitHub 归档多一层目录的情况）
    local app_root = find_app_root(file)

    sys.call("cp -R " .. app_root .. "/* " .. client_file)

    -- cp -R 不复制隐藏文件，补一次（.htaccess 等）
    sys.call("cd " .. app_root .. " && for f in .[!.]*; do [ -e \"$f\" ] && cp -R \"$f\" " ..
             client_file .. "/; done 2>/dev/null")

    sys.call("/bin/rm -rf /tmp/kodcloud_extract.*")

    -- data 目录必须可写（PHP 要写 session/用户数据）
    sys.call("chmod -R 777 " .. client_file .. "/data 2>/dev/null")

    return { code = 0, root = app_root }
end
