-- status: worked DD2 origin: kb:persistence-settings-api#crash-tolerant-a-b-json-store-for-reframework
-- store.lua: crash-tolerant JSON files and the JSON codec of core-lua. Pure library: every file call takes the
-- adapter's fs table (sched.lua's ADAPTER CONTRACT); nothing here touches a loader API, so it has no lifecycle (the
-- init/shutdown/status/reset stubs below exist only for the module contract).
--   STORE.encode(v, opts) -> text | nil, err   escapes every control byte, quote and backslash; NaN and +-inf -> null;
--       integers stay integers and floats keep a point (1.0); object keys sorted (stable lines and diffs); an empty
--       table -> {} (opts.empty = '[]' or 'null'); userdata and functions -> their tostring (a log line never fails);
--       depth over 30 or a cycle -> '"<deep>"' / '"<cycle>"'
--   STORE.decode(text) -> value | nil, err    strict: trailing bytes or a torn file are errors, never a partial table
--   STORE.read_json(fs, path) -> table | nil  nil for a missing, empty, torn or non-table file; never raises
--   STORE.put(fs, path, text) -> true | false, why   one whole write in place (no tmp); never raises
--   STORE.write_json(fs, path, t) -> true | false, 'encode'|'write'   encodes BEFORE the file is opened: REFramework's
--       json.dump_file truncates first, and an exit crash zeroed configs that way [worked DD2]
--   STORE.write_atomic / read_atomic: tmp + rename + bak when fs.rename exists; read takes the file, else a complete
--       .tmp (a crash between the two renames), else the .bak [worked SWZC lib/arm.lua]
--   STORE.put_atomic(fs, path, text) -> true | false, 'write'|'rename'   write_atomic's swap for a text kept
--       byte for byte (adapter/modsmenu.lua's descriptor); without fs.rename one whole write in place
--   STORE.load(fs, base) / STORE.save(fs, base, t): A/B slots base.a.json / base.b.json with a _seq number for loaders
--       without rename (REFramework): a save writes the slot the last one did not, the load takes the newest that parses
--   STORE.memfs(opts): an in-memory fs for offline tests with fault injection (fail_write, fail_open, torn, no_rename)
-- Evidence: [worked DD2] core/store.lua; [worked SWZC] lib/json.lua, lib/arm.lua write()/read();
-- kb:persistence-settings-api principle 8; kb:runtime-safety-perf#engine-notes (dump_file truncates, empty table -> null)
local STORE = {}

local fmt, byte, concat, sort = string.format, string.byte, table.concat, table.sort
local math_type, huge = math.type, math.huge

local ESC_OUT = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r',
    ['\t'] = '\\t' }
local function esc(c) return ESC_OUT[c] or fmt('\\u%04x', byte(c)) end
local function str(s) return '"' .. s:gsub('[%c"\\]', esc) .. '"' end

local function num(v)
    if v ~= v or v == huge or v == -huge then return 'null' end
    if math_type(v) == 'integer' then return fmt('%d', v) end
    local s = fmt('%.14g', v)
    if tonumber(s) ~= v then s = fmt('%.17g', v) end
    if not s:find('[%.eEn]') then s = s .. '.0' end          -- 1.0 stays a float after a round trip
    return s
end

local function enc(v, opts, depth, seen)
    local t = type(v)
    if v == nil then return 'null' end
    if t == 'boolean' then return v and 'true' or 'false' end
    if t == 'number' then return num(v) end
    if t == 'string' then return str(v) end
    if t ~= 'table' then
        local ok, s = pcall(tostring, v)
        return str(ok and s or ('<' .. t .. '>'))
    end
    if depth > 30 then return '"<deep>"' end
    if seen[v] then return '"<cycle>"' end
    if next(v) == nil then return opts.empty or '{}' end
    seen[v] = true
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    local out = {}
    if n > 0 and count == n then
        for i = 1, n do out[i] = enc(v[i], opts, depth + 1, seen) end
        seen[v] = nil
        return '[' .. concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == 'number' or ta == 'string' then return a < b end
        return tostring(a) < tostring(b)
    end)
    for i, k in ipairs(keys) do out[i] = str(tostring(k)) .. ':' .. enc(v[k], opts, depth + 1, seen) end
    seen[v] = nil
    return '{' .. concat(out, ',') .. '}'
end

function STORE.encode(v, opts)
    local ok, s = pcall(enc, v, opts or {}, 0, {})
    if ok then return s end
    return nil, tostring(s)
end

-- ---------- decoder ----------
local ESC_IN = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }

local function decode(s)
    local i, n = 1, #s
    local function ws() i = s:find('[^ \t\r\n]', i) or (n + 1) end
    local function fail(what) error('json: ' .. what .. ' at ' .. i, 0) end
    local value
    local function string_at()
        local out, j = {}, i + 1
        while true do
            local k = s:find('["\\%c]', j)
            if not k then fail('unterminated string') end
            if k > j then out[#out + 1] = s:sub(j, k - 1) end
            local c = s:sub(k, k)
            if c == '"' then i = k + 1 return concat(out) end
            if c ~= '\\' then i = k fail('control byte in string') end
            local e = s:sub(k + 1, k + 1)
            if e == 'u' then
                local hex = s:sub(k + 2, k + 5)
                local cp = tonumber(hex, 16)
                if not cp then i = k fail('bad \\u escape') end
                j = k + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == '\\u' then
                    local hex2 = s:sub(j + 2, j + 5)
                    local lo = tonumber(hex2, 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp, j = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00), j + 6
                    end
                end
                out[#out + 1] = utf8.char(cp)
            elseif ESC_IN[e] then
                out[#out + 1], j = ESC_IN[e], k + 2
            else
                i = k fail('bad escape')
            end
        end
    end
    function value()
        ws()
        local c = s:sub(i, i)
        if c == '{' then
            i = i + 1
            local t = {}
            ws()
            if s:sub(i, i) == '}' then i = i + 1 return t end
            while true do
                ws()
                if s:sub(i, i) ~= '"' then fail('expected key') end
                local k = string_at()
                ws()
                if s:sub(i, i) ~= ':' then fail('expected :') end
                i = i + 1
                t[k] = value()
                ws()
                local d = s:sub(i, i)
                i = i + 1
                if d == '}' then return t end
                if d ~= ',' then fail('expected , or }') end
            end
        elseif c == '[' then
            i = i + 1
            local t, k = {}, 0
            ws()
            if s:sub(i, i) == ']' then i = i + 1 return t end
            while true do
                k = k + 1
                t[k] = value()
                ws()
                local d = s:sub(i, i)
                i = i + 1
                if d == ']' then return t end
                if d ~= ',' then fail('expected , or ]') end
            end
        elseif c == '"' then return string_at()
        elseif s:sub(i, i + 3) == 'true' then i = i + 4 return true
        elseif s:sub(i, i + 4) == 'false' then i = i + 5 return false
        elseif s:sub(i, i + 3) == 'null' then i = i + 4 return nil
        end
        local lit = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
        if not lit or lit == '' then fail('bad value') end
        i = i + #lit
        local v = tonumber(lit)
        if v == nil then fail('bad number') end
        if lit:find('[%.eE]') then return v + 0.0 end
        return math.tointeger(v) or v
    end
    local v = value()
    ws()
    if i <= n then fail('trailing bytes') end
    return v
end

function STORE.decode(s)
    if type(s) ~= 'string' then return nil, 'json: not a string' end
    local ok, v = pcall(decode, s)
    if ok then return v end
    return nil, tostring(v)
end

-- ---------- files through the adapter fs ----------
local function fs_read(fs, path)
    local ok, s = pcall(fs.read, path)
    if ok and type(s) == 'string' and s ~= '' then return s end
    return nil
end

function STORE.read_json(fs, path)
    local s = fs_read(fs, path)
    if not s then return nil end
    local t = STORE.decode(s)
    if type(t) == 'table' then return t end
    return nil
end

-- One whole write in place (no tmp): true | false, why (the write's error, or the raised text). Never raises
function STORE.put(fs, path, text)
    local ok, r, err = pcall(fs.write, path, text)
    if ok and r then return true end
    return false, tostring(ok and err or r)
end
local put = STORE.put

function STORE.write_json(fs, path, t, opts)
    local s = STORE.encode(t, opts)
    if not s then return false, 'encode' end
    local ok = put(fs, path, s)
    if not ok then return false, 'write' end
    return true
end

-- tmp + rename + bak for a text, byte for byte: the old file survives a crash at any point (one of path, .tmp, .bak is
-- complete) and a failed swap puts it back. true | false, 'write'|'rename'. Without fs.rename: one whole write in place
function STORE.put_atomic(fs, path, s)
    if not fs.rename then
        if not put(fs, path, s) then return false, 'write' end
        return true
    end
    local tmp, bak = path .. '.tmp', path .. '.bak'
    if not put(fs, tmp, s) then return false, 'write' end
    if fs.remove then pcall(fs.remove, bak) end
    local okb, had = pcall(fs.rename, path, bak)
    local okr, moved = pcall(fs.rename, tmp, path)
    if okr and moved then
        if fs.remove then pcall(fs.remove, bak) end
        return true
    end
    if okb and had then pcall(fs.rename, bak, path) end
    if fs.remove then pcall(fs.remove, tmp) end
    return false, 'rename'
end

-- STORE.put_atomic of the encoded table (encoded before any file is touched)
function STORE.write_atomic(fs, path, t, opts)
    if not fs.rename then return STORE.write_json(fs, path, t, opts) end
    local s = STORE.encode(t, opts)
    if not s then return false, 'encode' end
    return STORE.put_atomic(fs, path, s)
end

-- The file, else a complete tmp, else the backup; the second value names which one answered
function STORE.read_atomic(fs, path)
    for _, p in ipairs({ path, path .. '.tmp', path .. '.bak' }) do
        local t = STORE.read_json(fs, p)
        if t then return t, p end
    end
    return nil
end

-- A/B slots: newest valid wins; a torn or missing slot loses to the other
function STORE.load(fs, base)
    local a, b = STORE.read_json(fs, base .. '.a.json'), STORE.read_json(fs, base .. '.b.json')
    local sa = a and math.tointeger(tonumber(a._seq)) or -1
    local sb = b and math.tointeger(tonumber(b._seq)) or -1
    if a and sa >= sb then return a, sa end
    if b then return b, sb end
    return nil, -1
end

-- t._seq (from load) + 1 picks the slot: even -> a, odd -> b. t._seq is set only after the write succeeded.
function STORE.save(fs, base, t, opts)
    local n = (math.tointeger(tonumber(t._seq)) or -1) + 1
    local old = t._seq
    t._seq = n
    local ok, why = STORE.write_json(fs, base .. ((n % 2 == 0) and '.a.json' or '.b.json'), t, opts)
    if not ok then t._seq = old end
    return ok, why
end

-- A loader's json may write an empty table as null: re-create tables that must stay tables after a load
function STORE.ensure_table(t, key)
    if type(t[key]) ~= 'table' then t[key] = {} end
    return t[key]
end

-- ---------- memfs: the adapter fs in memory, for offline tests ----------
-- opts.no_rename: no fs.rename/remove (REFramework). Fault switches, all live tables the test may change:
--   fs.fail_write[path] = true   fs.write and open_append for path fail
--   fs.fail_open[path] = true    open_append fails
--   fs.torn[path] = n            the next whole write of path keeps only its first n bytes, then the write "crashes"
--   fs.locked[path] = true       fs.read(path) answers nil, 13 (another process holds it)
-- fs.files[path] = text, fs.writes (whole writes), fs.appends (append calls). fs.read(path) reads as the UE4SS
-- adapter's (adapter/env.lua): the text, or nil and the C errno (2 missing, 13 locked)
function STORE.memfs(opts)
    opts = opts or {}
    local fs = { files = {}, fail_write = {}, fail_open = {}, torn = {}, locked = {}, writes = 0, appends = 0 }
    function fs.read(path)
        if fs.locked[path] then return nil, 13 end
        local t = fs.files[path]
        if t == nil then return nil, 2 end
        return t
    end
    function fs.write(path, text)
        if fs.fail_write[path] then return nil, 'injected write failure' end
        local cut = fs.torn[path]
        if cut then
            fs.torn[path] = nil
            fs.files[path] = text:sub(1, cut)
            return nil, 'injected torn write'
        end
        fs.files[path] = text
        fs.writes = fs.writes + 1
        return true
    end
    function fs.open_append(path, truncate)
        if fs.fail_open[path] or fs.fail_write[path] then return nil, 'injected open failure' end
        if truncate or fs.files[path] == nil then fs.files[path] = '' end
        local h = {}
        function h.write(_, ...)
            for i = 1, select('#', ...) do fs.files[path] = (fs.files[path] or '') .. tostring(select(i, ...)) end
            fs.appends = fs.appends + 1
            return h
        end
        function h.flush() return true end
        function h.close() return true end
        function h.seek() return #(fs.files[path] or '') end
        return h
    end
    if not opts.no_rename then
        function fs.rename(a, b)
            if fs.files[a] == nil then return nil, 'no such file' end
            fs.files[b], fs.files[a] = fs.files[a], nil
            return true
        end
        function fs.remove(p)
            local had = fs.files[p] ~= nil
            fs.files[p] = nil
            return had or nil
        end
    end
    return fs
end

-- module contract stubs (a pure library has no lifecycle)
function STORE.init() return true end
function STORE.shutdown() end
function STORE.status() return nil end
function STORE.reset() end

return STORE
