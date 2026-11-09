-- status: worked SWZC origin: kb:runtime-safety-perf#ue4ss-hot-reload-engine-free-onunload-epochs-shared-variables
-- env.lua: the core adapter table A for UE4SS (core/sched.lua's ADAPTER CONTRACT) plus the pure facts the session
-- header needs. Pure Lua + io: no UObject call, so main.lua's body (UE4SS update thread) may use all of it.
-- * Paths: UE4SS loads main.lua as an anonymous chunk (debug source '=[C]'), so the mod folder comes from package.path
--   (UE4SS adds <Mods>/<folder>/Scripts/?.lua; any folder name works). E.data = META.data_dir or the mod folder (logs,
--   sentinel files, the dev marker: where tools/lab looks); E.state = %LOCALAPPDATA%/<saved_subdir>/Saved/<MOD>_ when
--   META.saved_subdir is set (settings and arm markers then survive a mod update), else E.data. E.game_ini (with
--   saved_subdir) = %LOCALAPPDATA%/<saved_subdir>/Saved/Config/Windows/GameUserSettings.ini, the game's own settings
--   file, read only (adapter/modsmenu.lua takes the text language from it).
-- * fs: whole-file read/write, rename/remove (store.lua then writes tmp + rename + bak), append handles that flush
--   every line (the CRT buffers a UE4SS file fully: a crash ate the last records). The read beyond core/sched.lua's
--   ADAPTER CONTRACT line: A.fs.read(path) -> text | nil, why, where why is the C errno io.open gives (2 missing, 13
--   locked or denied) or 'read' (the open went through, the read did not); a caller that takes one value gets the
--   text or nil as the contract says, and adapter/modsmenu.lua reads why (a missing config may be created, a locked
--   one may not).
-- * mods.txt: a '<folder> : 0' line switches the mod off even with enabled.txt present; the enabled neighbours are
--   listed read-only for the header (never called, never switched off).
-- * Shared variables (ModRef) survive Ctrl+R and die with the process: the proc token tells a hot reload from a new
--   launch (a reload is not a crash), and handoff()/take() carry small plain values across a reload.
-- * Steam buildid from appmanifest_<appid>.acf; the UE4SS label ('v3.0.1 ... Git SHA #abc') from UE4SS.log.
-- * UE4SS.log scanner (M0 S2.5): a bounded tail read from a byte offset with a plain find, each hit with its line and
--   the 3 lines before it (lab_probe's D9 stop rule), and the loader package from the '[GameDirectories] Resolved' line
--   that Vercadi's PBZ build writes (the env record, D7). File IO only: never inside a hook body.
-- API: init(META) -> E; adapter() -> A; code_hash(files); mods_off(); neighbours(); steam_buildid(); ue4ss_log();
--   ue4ss_label(); log_scan(offset, needles, max_bytes) -> hits, new_offset; loader_package(); shared_get/shared_set;
--   handoff(t); take(); reloaded(); fs, clock.
-- Evidence: [worked SWZC] lib/paths.lua, main.lua read_buildid/read_ue4ss_label/code_hash, compat.parse_label;
-- kb:runtime-safety-perf#read-only-neighbour-detection-and-known-incompatible-table; engine note
-- 'UE5 / UE4SS 527a483b'. Log scanner [offline only]: tests/test_ue4ss_env.lua over tests/fixtures/ue4ss_log_head.txt
-- (data/logs/UE4SS.log:2, :744-746 plus one planted ArrayNum line).
local RNG = require('core.rng')
local STORE = require('core.store')
local LOG = require('core.log')

local ENV = { E = nil }
local META = nil
local scan_warned = false           -- one log_scan_unavailable line per init

-- The whole file, or nil and why (the header: the C errno io.open gives, else 'read')
local function read(path)
    local f, _, code = io.open(path, 'rb')
    if not f then return nil, code end
    local s = f:read('a')
    f:close()
    if s == nil then return nil, 'read' end
    return s
end

-- True only once the close went through: the CRT buffers the text until close, so a flush that fails there (a full
-- disk) would leave an empty file behind a write that looked fine
local function write(path, text)
    local f, err = io.open(path, 'wb')
    if not f then return nil, err end
    local ok, werr = f:write(text)
    local cok, cerr = f:close()
    if not ok then return nil, werr end
    if not cok then return nil, cerr end
    return true
end

-- An append handle whose every write is flushed (h:write/h:flush/h:close/h:seek, as io handles)
local function open_append(path, truncate)
    local f = io.open(path, truncate and 'wb' or 'ab')
    if not f then return nil end
    local h = {}
    function h:write(...) local r = f:write(...) f:flush() return r and self or nil end
    function h:flush() return f:flush() end
    function h:close() return f:close() end
    function h:seek(...) return f:seek(...) end
    return h
end

ENV.fs = { read = read, write = write, open_append = open_append,
    rename = function(a, b) return os.rename(a, b) end, remove = function(p) return os.remove(p) end }
ENV.clock = { real = function() return os.clock() end, wall = function() return os.time() end }

local function scripts_dir()
    for entry in package.path:gmatch('[^;]+') do
        local dir = entry:match('^(.-)[\\/]%?%.lua$')
        if dir and dir:match('[\\/][Ss]cripts$') and read(dir .. '/main.lua') then return dir end
    end
    return nil
end

function ENV.shared_get(k)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(META.prefix .. '_' .. k) end)
    if ok then return v end
    return nil
end
function ENV.shared_set(k, v)
    return pcall(function() ModRef:SetSharedVariable(META.prefix .. '_' .. k, v) end)
end

-- meta: the META table (mod, prefix, saved_subdir, data_dir, mods_txt)
function ENV.init(meta)
    META = meta
    scan_warned = false
    local E = { scripts = scripts_dir() }
    E.mod_dir = E.scripts and E.scripts:match('^(.*)[\\/][Ss]cripts$') or nil
    E.folder = E.mod_dir and E.mod_dir:match('([^\\/]+)$') or meta.mod
    E.mods_dir = E.mod_dir and E.mod_dir:match('^(.*)[\\/][^\\/]+$') or nil
    E.data = meta.data_dir or (E.mod_dir and (E.mod_dir .. '/')) or ''
    local la = os.getenv('LOCALAPPDATA')
    if meta.saved_subdir and la and la ~= '' then
        E.state = la .. '/' .. meta.saved_subdir .. '/Saved/' .. meta.mod .. '_'
        E.game_ini = la .. '/' .. meta.saved_subdir .. '/Saved/Config/Windows/GameUserSettings.ini'
    else
        E.state = E.data
    end
    local tok = ENV.shared_get('proc')
    E.reloaded = type(tok) == 'string' and tok ~= ''
    if not E.reloaded then
        tok = string.format('%d-%08x', os.time(), RNG.hash32(tostring(os.clock()) .. tostring({})))
        ENV.shared_set('proc', tok)
    end
    E.proc = tok
    local starts = ENV.shared_get('starts')
    E.starts = (math.tointeger(starts) or 0) + 1
    ENV.shared_set('starts', E.starts)
    ENV.E = E
    return E
end

function ENV.reloaded() return ENV.E ~= nil and ENV.E.reloaded end

function ENV.adapter()
    return { fs = ENV.fs, clock = ENV.clock, proc_token = function() return ENV.E and ENV.E.proc or nil end,
        echo = function(line) print('[' .. META.mod .. '] ' .. tostring(line)) end }
end

-- mods.txt lines as { name = '1'|'0' }
local function mods_txt()
    local p = META.mods_txt or (ENV.E and ENV.E.mods_dir and (ENV.E.mods_dir .. '/mods.txt'))
    local text = p and read(p)
    local out = {}
    if not text then return out end
    for line in text:gmatch('[^\r\n]+') do
        local name, v = line:match('^%s*([^;:#][^:]-)%s*:%s*(%d)')
        if name then out[name:lower()] = v end
    end
    return out
end
function ENV.mods_off()
    local t = mods_txt()
    local f = ENV.E and ENV.E.folder or META.mod
    return t[f:lower()] == '0'
end
function ENV.neighbours()
    local out = {}
    for name, v in pairs(mods_txt()) do
        if v == '1' and name ~= (ENV.E and ENV.E.folder or META.mod):lower() then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function ENV.steam_buildid()
    local dir = ENV.E and ENV.E.mod_dir
    local steamapps = dir and dir:match('^(.-[\\/][Ss]teamapps[\\/])[Cc]ommon[\\/]')
    if not steamapps or not META.steam_appid then return nil end
    local text = read(steamapps .. 'appmanifest_' .. tostring(META.steam_appid) .. '.acf')
    return text and text:match('"buildid"%s+"(%d+)"') or nil
end

-- UE4SS.log sits next to the Mods folder (<ue4ss>/UE4SS.log); nil while the Mods folder is unknown
function ENV.ue4ss_log()
    local base = ENV.E and ENV.E.mods_dir and ENV.E.mods_dir:match('^(.*)[\\/][^\\/]+$')
    return base and (base .. '/UE4SS.log') or nil
end

-- The label line in the first 20: 'UE4SS - v3.0.1 Beta #0 - Git SHA #527a483b'
function ENV.ue4ss_label()
    local p = ENV.ue4ss_log()
    local f = p and io.open(p, 'rb')
    if not f then return nil, nil end
    local label = nil
    for _ = 1, 20 do
        local line = f:read('l')
        if not line then break end
        label = line:match('UE4SS %- (v.-%- Git SHA #%x+)')
        if label then break end
    end
    f:close()
    return label, label and label:match('#(%x+)$') or nil
end

-- ENV.log_scan(offset, needles, max_bytes) -> hits, new_offset. Reads at most max_bytes (default SCAN_BYTES) of
-- UE4SS.log from the byte offset (nil = 0; past the end = 0: a new launch rewrote the log) and plain-finds the needles
-- (a list or one string) in each complete line. A partial last line waits for the next call, unless one line fills the
-- whole window (then it is read in pieces, so a tail never stalls). One hit per line, the first needle in list order:
-- { needle, line, before = the CONTEXT lines before it, oldest first (read back from before the window when the hit
-- is near its start), offset = the line's byte offset }. At most MAX_HITS per call; new_offset then sits just past the
-- last hit's line, so the next call goes on from there. An unreadable log returns nil, offset (kept) and writes one
-- log_scan_unavailable warning per init; nothing raises. [P] SCAN_BYTES 64 KB, BACK_BYTES 4 KB, MAX_HITS 32.
local CONTEXT = 3
local SCAN_BYTES, BACK_BYTES, MAX_HITS, PKG_BYTES = 65536, 4096, 32, 1048576

local function split_lines(s)                      -- the complete lines of s, CR stripped
    local out = {}
    for line in s:gmatch('([^\n]*)\n') do out[#out + 1] = (line:gsub('\r$', '')) end
    return out
end

-- The last n complete lines that end before byte offset at, oldest first
local function lines_before(f, at, n)
    if at <= 0 or n <= 0 then return {} end
    local from = at > BACK_BYTES and (at - BACK_BYTES) or 0
    f:seek('set', from)
    local lines = split_lines(f:read(at - from) or '')
    local first = from > 0 and 2 or 1              -- a read that starts mid-line drops its first piece
    local out = {}
    for i = math.max(first, #lines - n + 1), #lines do out[#out + 1] = lines[i] end
    return out
end

local function scan(f, offset, needles, max_bytes)
    local size = f:seek('end')
    if not size then return nil, 'no_size' end
    if offset > size then offset = 0 end
    local n = math.min(max_bytes, size - offset)
    if n <= 0 then return {}, offset end
    f:seek('set', offset)
    local s = f:read(n) or ''
    local hits, ring, pos = {}, {}, 1
    while #hits < MAX_HITS do
        local nl = s:find('\n', pos, true)
        local stop = nl
        if not stop and pos == 1 and #s >= max_bytes then stop = #s end
        if not stop then break end
        local line = s:sub(pos, nl and (nl - 1) or stop):gsub('\r$', '')
        for _, nd in ipairs(needles) do
            if type(nd) == 'string' and nd ~= '' and line:find(nd, 1, true) then
                local before = {}
                if #ring < CONTEXT then before = lines_before(f, offset, CONTEXT - #ring) end
                for _, r in ipairs(ring) do before[#before + 1] = r end
                hits[#hits + 1] = { needle = nd, line = line, before = before, offset = offset + pos - 1 }
                break
            end
        end
        ring[#ring + 1] = line
        if #ring > CONTEXT then table.remove(ring, 1) end
        pos = stop + 1
    end
    return hits, offset + pos - 1
end

function ENV.log_scan(offset, needles, max_bytes)
    offset = math.tointeger(offset) or 0
    if offset < 0 then offset = 0 end
    max_bytes = math.tointeger(max_bytes) or SCAN_BYTES
    if max_bytes < 1 then max_bytes = SCAN_BYTES end
    if type(needles) ~= 'table' then needles = { needles } end
    local path = ENV.ue4ss_log()
    local f, err = nil, 'no_path'
    if path then f, err = io.open(path, 'rb') end
    if f then
        local ok, hits, new_offset = pcall(scan, f, offset, needles, max_bytes)
        f:close()
        if ok and hits then return hits, new_offset end
        if ok then err = new_offset else err = hits end
    end
    if not scan_warned then
        scan_warned = true
        LOG.warn('log_scan_unavailable', { path = path or 'none', err = tostring(err) })
    end
    return nil, offset
end

-- 'vercadi' when the log holds the '[GameDirectories] Resolved' line (Vercadi's UE4SS for PBZ writes it at mod start,
-- data/logs/UE4SS.log:744), 'other' when the first PKG_BYTES (1 MB) read without it (the 1185 build), 'unknown' when
-- the log cannot be read
local RESOLVED = '[GameDirectories] Resolved'
function ENV.loader_package()
    local off = 0
    while off < PKG_BYTES do
        local hits, new = ENV.log_scan(off, { RESOLVED }, SCAN_BYTES)
        if not hits then return 'unknown' end
        if #hits > 0 then return 'vercadi' end
        if new <= off then return 'other' end
        off = new
    end
    return 'other'
end

-- One FNV-1a over the files (relative to Scripts, '/' separators), file by file: '%08x/<files found>'
function ENV.code_hash(files)
    local dir, h, n = ENV.E and ENV.E.scripts, nil, 0
    for _, rel in ipairs(files or {}) do
        local s = dir and read(dir .. '/' .. rel)
        if s then h, n = RNG.hash32(s, h), n + 1 end
    end
    return string.format('%08x/%d', h or RNG.hash32(''), n)
end

-- Plain values across a hot reload (OnUnload -> next main.lua): one shared variable holding JSON text (a shared
-- variable carries strings, numbers and booleans, never a table of the old Lua state), taken once
function ENV.handoff(t)
    local text = STORE.encode(t)
    if not text then return false end
    return ENV.shared_set('handoff', text)
end
function ENV.take()
    local text = ENV.shared_get('handoff')
    if type(text) ~= 'string' or text == '' then return nil end
    ENV.shared_set('handoff', '')
    local t = STORE.decode(text)
    if type(t) ~= 'table' then return nil end
    return t
end

function ENV.reset() end
function ENV.shutdown() end

return ENV
