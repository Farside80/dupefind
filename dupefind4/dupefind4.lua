
-- dupefind4.lua - clean rebuild with robust name resolver
addon = {
    name = 'dupefind4',
    author = 'Lili (clean rebuild)',
    version = '1.2.0',
    commands = { 'dupefind4', 'dupe4', 'df4' }
}

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

-- Optional overrides set via /dupe4 setname <id> <name>
NameOverrides = NameOverrides or {}

-- ===== Resource helpers =====
local function get_res()
    local ok, res = pcall(function() return AshitaCore:GetResourceManager() end)
    if ok then return res end
    return nil
end

-- Safe attempt to coerce various userdata/table/string to a usable string.
local function _resolve_string(res, obj)
    if obj == nil then return nil end
    if type(obj) == 'string' and obj ~= '' then return obj end

    local ok, s = pcall(function() return obj:GetString() end)
    if ok and type(s) == 'string' and s ~= '' then return s end
    ok, s = pcall(function() return obj:GetString(0) end)
    if ok and type(s) == 'string' and s ~= '' then return s end
    ok, s = pcall(function() return obj:GetString(1) end)
    if ok and type(s) == 'string' and s ~= '' then return s end

    ok, s = pcall(function() return res:GetString(obj) end)
    if ok and type(s) == 'string' and s ~= '' then return s end
    ok, s = pcall(function() return res:GetString(obj, 0) end)
    if ok and type(s) == 'string' and s ~= '' then return s end
    ok, s = pcall(function() return res:GetString(obj, 1) end)
    if ok and type(s) == 'string' and s ~= '' then return s end

    ok, s = pcall(function() return obj[0] end)
    if ok and type(s) == 'string' and s ~= '' then return s end
    ok, s = pcall(function() return obj[1] end)
    if ok and type(s) == 'string' and s ~= '' then return s end

    if type(obj) == 'table' then
        if type(obj[0]) == 'string' and obj[0] ~= '' then return obj[0] end
        if type(obj[1]) == 'string' and obj[1] ~= '' then return obj[1] end
        if type(obj['en']) == 'string' and obj['en'] ~= '' then return obj['en'] end
    end
    return nil
end

-- ===== Robust item name resolver =====
local function df4_get_item_name(res, id)
    if NameOverrides[id] ~= nil then return NameOverrides[id] end
    if not res or not id then return tostring(id) end

    local it = nil
    pcall(function() it = res:GetItemById(id) end)
    if it ~= nil then
        local fields = { it.Name, it.LogNameSingular, it.LogNamePlural }
        for _, f in ipairs(fields) do
            local s = _resolve_string(res, f)
            if s and s ~= '' then return s end
        end
    end

    -- Optional string table fallbacks (dupefind-style)
    if get_string_from_any_table then
        local st = nil
        pcall(function() st = get_string_from_any_table(res, id) end)
        if st and st ~= '' then return st end
    end
    if get_string_from_tables then
        local st2 = nil
        pcall(function() st2 = get_string_from_tables(res, id) end)
        if st2 and st2 ~= '' then return st2 end
    end

    return tostring(id)
end

-- ===== Inventory helpers =====
local function get_inv()
    local ok, inv = pcall(function() return AshitaCore:GetMemoryManager():GetInventory() end)
    if ok then return inv end
    return nil
end

local function try_container_size(inv, cid)
    local ok, n = pcall(function() return inv:GetContainerSize(cid) end)
    if ok and type(n) == 'number' then return n end
    ok, n = pcall(function() return inv:GetContainerMax(cid) end)
    if ok and type(n) == 'number' then return n end
    ok, n = pcall(function() return inv:GetContainerCount(cid) end)
    if ok and type(n) == 'number' then return n end
    return 0
end

local function get_item(inv, cid, slot)
    local ok, it = pcall(function() return inv:GetItem(cid, slot) end)
    if ok and it then return it end
    ok, it = pcall(function() return inv:GetContainerItem(cid, slot) end)
    if ok and it then return it end
    return nil
end

local function get_item_id_count(item)
    if not item then return 0, 0 end
    local id = item.Id or item.ID or item.ItemId or item.item_id or item.id or 0
    local count = item.Count or item.Quantity or item.count or item.quantity or 0
    if count == 0 then count = 1 end
    return id or 0, count
end

local container_names = {
    [0]='inventory', [1]='safe', [2]='storage', [3]='temporary',
    [4]='locker', [5]='satchel', [6]='sack', [7]='case',
    [8]='wardrobe', [9]='safe2', [10]='wardrobe2', [11]='wardrobe3',
    [12]='wardrobe4', [13]='wardrobe5', [14]='wardrobe6', [15]='wardrobe7',
    [16]='wardrobe8', [17]='recycle', [18]='unknown18', [19]='unknown19',
    [20]='unknown20', [21]='unknown21',
}

-- ===== Main logic =====
local function run_dupefind(opts)
    opts = opts or {}
    local inv = get_inv()
    local res = get_res()
    if not inv then
        printf('[dupefind4] Inventory manager unavailable.')
        return
    end

    local haystack = {} -- id -> { loc -> total count }
    for cid = 0, 21 do
        local size = try_container_size(inv, cid)
        if size and size > 0 then
            for slot = 1, size do
                local it = get_item(inv, cid, slot)
                if it then
                    local id, count = get_item_id_count(it)
                    if id and id > 0 then
                        local loc = container_names[cid] or tostring(cid)
                        haystack[id] = haystack[id] or {}
                        haystack[id][loc] = (haystack[id][loc] or 0) + (count or 1)
                    end
                end
            end
        end
    end

    local results = 0
    for id, locations in pairs(haystack) do
        local distinct = 0
        for _ in pairs(locations) do distinct = distinct + 1 end
        if distinct > 1 then
            results = results + 1
            local name = df4_get_item_name(res, id)
            printf('%s found in:', name)
            for loc, count in pairs(locations) do
                printf('  %s  x%d', loc, count)
            end
        end
    end

    if results > 0 then
        local suffix = (results ~= 1) and 's' or ''
        printf('%d duplicate item%s found.', results, suffix)
    else
        printf('No duplicates found.')
    end
end

-- Very small flag parser (placeholder for future options)
local function parse_flags(s)
    return {}
end

-- ===== Command handler =====
ashita.events.register('command', 'dupefind4_command', function(e)
    local args = e.command:match('^/[%w]+%s+(.+)$') or ''
    local lower = args:lower()

    local cmdlower = (e.command or ''):lower()
    if cmdlower:match('^/dupefind4') or cmdlower:match('^/dupe4') or cmdlower:match('^/df4') then
        -- setname
        if lower:match('^setname%s+%d+%s+') then
            local idstr, namepart = args:match('^setname%s+(%d+)%s+(.+)$')
            local id = tonumber(idstr)
            if id and namepart and namepart ~= '' then
                NameOverrides[id] = namepart
                printf('[dupefind4] Set name for %d -> %s', id, namepart)
                return
            else
                printf('[dupefind4] Usage: /dupe4 setname <id> <custom name>')
                return
            end
        end

        local opts = parse_flags(lower)
        local ok, err = pcall(function() run_dupefind(opts) end)
        if not ok and err then
            printf('[dupefind4] Error: %s', tostring(err))
        end
    end
end)
