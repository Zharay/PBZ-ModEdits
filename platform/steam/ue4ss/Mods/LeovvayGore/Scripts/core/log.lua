-- status: worked DD2+SWZC (ended.json untested) origin: kb:testing-lab-playtest#principles (1, 3, 4)
-- log.lua: the JSONL log the analyzers, cards and triage tools read (tools/analyze, tools/triage). One record per line,
-- flushed per line (a crash must not eat the last lines). Files in opts.dir through the adapter fs:
--   log.a.jsonl / log.b.jsonl   the slots: a new game process takes the other slot and truncates it; a script reset or
--                               hot reload (same process) appends to the current one. No rename needed (REFramework).
--   log.json                    the pointer { slot, launch, token, t }. Same process = the stored token: A.proc_token()
--                               when the loader keeps one across reloads (UE4SS shared variable), else the stored
--                               launch id (wall - real clock) within opts.launch_tol 2 s, and the new state ADOPTS the
--                               stored id (a recomputed clock jitters by 1 s and dropped ~1/3 of hand-offs).
--   ended.json                  the clean-quit marker (L.mark_end); the next launch reports it as prev_end / prev_quit.
-- Record and field names follow tools/schemas/events.schema.json (the analyzers and triage read them from there).
-- Every record: ev, lvl, t (wall s), c (real clock s, ms), f (the main tick's frame, set_frame_source). Levels debug <
-- info < warn < error; ship at info. Per event name at most opts.ev_cap 2000 records below error, the cap hit reported
-- once as log_cap {what, cap}; past opts.max_bytes 16 MB only warn and error, reported once as log_cap {what = 'bytes',
-- bytes, cap}. Values are cleaned (userdata vectors -> {x,y,z}, other userdata and functions -> text, depth 6) and
-- escaped by store.lua's codec.
-- API (fixed, lint L015 and the adapters use it):
--   L.session(h) -> header   the immutable session header: a DEEP COPY of h plus reason (launch|reset), slot, launch,
--       launch_id (the process token, stable across resets), prev_end + prev_quit, log_cap (slot byte cap), ev_cap, and
--       every required field present: build ('<commit>[+dirty]-<code8>', else 'unstamped'), code_hash, version,
--       loader {kind, commit}, game_build, gates {region, rating, censor}; a value nobody read is 'unknown'. The caller
--       adds names_total, names_missing, modules, modules_failed, disabled, strikes (lists the analyzers print).
--   L.status_tick([now])     call from an INDEPENDENT callback (REF on_frame, a UE4SS loop): every opts.status_every
--       30 s real time one status record with window_s, the frame counter (a frozen frame next to live status =
--       starvation), counts, log_bytes, log_cap and each L.add_status(name, fn) provider's table (add the scheduler's
--       take_cost as 'cost': the analyzer reads cost.frames)
--   L.mark_end(reason)       ended.json for the next launch plus a session_end {via} record (a REF quit runs no Lua
--       callback: call it from a quit hint); L.mark_end(false) withdraws it (on quit_withdrawn)
--   L.every(key, s [, now])  a real-clock throttle (never frames: a per-30-frames row hit its cap above 81 fps)
--   L.set_sink(fn|false)     fn(rec, line) sees every record; the default is rawget(_G, 'GORE_LOG_TAP') (the offline
--       harness fails a test on any undeclared error record it sees there), nil in a game
--   L.debug/info/warn/error(ev, rec), L.write(lvl, ev, rec), L.start_error(module, err), L.guarded(counts, name, fn, max)
-- Lifecycle: init(A, opts) / shutdown / status / reset / handoff.
-- Evidence: [worked DD2] core/log.lua, main.lua status_record and session; [worked SWZC] lib/log.lua (sink, flush per
-- line), main.lua header; kb:runtime-safety-perf#principles (25: silent failure visible); ended.json [untested]
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local STORE = require(BASE .. 'store')

local L = {}
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local MAX_PENDING = 200

local cfg, A, fs = nil, nil, nil
local fh, bytes, full, write_errors = nil, 0, false, 0
local min_level, echo_level = LEVELS.info, LEVELS.warn
local frame_fn = function() return 0 end
local counts, per_ev, capped = {}, {}, {}
local sink, header, prev_end = nil, nil, nil
local pending, every_t, status_fns, status_order, next_status, last_status = {}, {}, {}, {}, 0, 0
L.slot, L.launch, L.token, L.new_launch = nil, nil, nil, nil

local function real() return A.clock.real() end
local function wall() return A.clock.wall() end

local function copy(v, depth)
    if type(v) ~= 'table' then return v end
    if depth > 8 then return '<deep>' end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x, depth + 1) end
    return o
end
L.copy = function(v) return copy(v, 0) end

local function clean(v, depth)
    local t = type(v)
    if t == 'userdata' then
        local ok, x = pcall(function() return { v.x or v.X, v.y or v.Y, v.z or v.Z } end)
        if ok and type(x[1]) == 'number' then return x end
        return tostring(v)
    elseif t == 'function' or t == 'thread' then
        return tostring(v)
    elseif t == 'table' then
        if depth > 6 then return '<deep>' end
        local o = {}
        for k, x in pairs(v) do o[k] = clean(x, depth + 1) end
        return o
    end
    return v
end
L.clean = clean

function L.path() return L.slot and (cfg.dir .. 'log.' .. L.slot .. '.jsonl') or nil end

-- The slot for this Lua state (see the header); called once by init
local function open_slot()
    local ptr = STORE.read_json(fs, cfg.dir .. 'log.json')
    local tok = nil
    if A.proc_token then
        local ok, t = pcall(A.proc_token)
        if ok and t ~= nil then tok = tostring(t) end
    end
    local launch = math.floor(wall() - real() + 0.5)
    local valid = type(ptr) == 'table' and (ptr.slot == 'a' or ptr.slot == 'b')
    local same
    if tok then same = valid and ptr.token == tok
    else same = valid and type(ptr.launch) == 'number' and math.abs(ptr.launch - launch) <= cfg.launch_tol end
    if same then
        L.slot, L.new_launch, L.launch, L.token = ptr.slot, false, ptr.launch, ptr.token
        prev_end = nil
    else
        L.slot = (valid and ptr.slot == 'a') and 'b' or 'a'
        L.new_launch, L.launch, L.token = true, launch, tok or tostring(launch)
        prev_end = nil
        local ended = STORE.read_json(fs, cfg.dir .. 'ended.json')
        if valid then
            local clean_end = type(ended) == 'table' and ended.token ~= nil and ended.token == ptr.token
            prev_end = { clean = clean_end, reason = clean_end and ended.reason or nil, t = clean_end and ended.t or nil }
        end
        STORE.write_json(fs, cfg.dir .. 'log.json', { slot = L.slot, launch = L.launch, token = L.token, t = wall() })
    end
    local ok, h = pcall(fs.open_append, L.path(), L.new_launch)
    fh = ok and h or nil
    bytes = 0
    if fh and not L.new_launch and fh.seek then
        local oks, n = pcall(fh.seek, fh, 'end')
        if oks and type(n) == 'number' then bytes = n end
    end
end

local function emit_line(rec, n, force)
    local okc, cleaned = pcall(clean, rec, 0)          -- a raising __pairs/__tostring must not fail the caller
    local line = okc and STORE.encode(cleaned) or nil
    if not line then
        line = '{"ev":"log_error","lvl":"error","what":' .. (STORE.encode(tostring(rec.ev)) or '""') .. '}'
    end
    if sink then pcall(sink, rec, line) end
    if A.echo and n >= echo_level then pcall(A.echo, rec.lvl .. ' ' .. rec.ev) end
    if not fh and L.every('log_reopen', 5) then
        local ok, h = pcall(fs.open_append, L.path(), false)
        fh = ok and h or nil
    end
    if not fh then return end
    local ok = pcall(function() fh:write(line, '\n') fh:flush() end)
    if ok then bytes = bytes + #line + 1
    else write_errors, fh = write_errors + 1, nil end
end

function L.write(lvl, ev, rec, force)
    if type(ev) ~= 'string' then ev = tostring(ev) end
    if not A then
        if #pending < MAX_PENDING then pending[#pending + 1] = { lvl, ev, rec and copy(rec, 0) or nil, force } end
        return
    end
    local n = LEVELS[lvl] or LEVELS.info
    if n < min_level and not force then return end
    local c = (per_ev[ev] or 0) + 1
    per_ev[ev] = c
    if c > cfg.ev_cap and n < LEVELS.error and not force then
        if not capped[ev] then
            capped[ev] = true
            L.write('warn', 'log_cap', { what = ev, cap = cfg.ev_cap })
        end
        return
    end
    if bytes > cfg.max_bytes and n < LEVELS.warn and not force then
        if not full then
            full = true
            L.write('warn', 'log_cap', { what = 'bytes', bytes = bytes, cap = cfg.max_bytes })
        end
        return
    end
    counts[lvl] = (counts[lvl] or 0) + 1
    local r = {}
    if type(rec) == 'table' then for k, v in pairs(rec) do r[k] = v end
    elseif rec ~= nil then r.msg = tostring(rec) end
    r.ev, r.lvl, r.t = ev, lvl, wall()
    r.c = math.floor(real() * 1000) / 1000
    local okf, f = pcall(frame_fn)
    r.f = okf and f or nil
    emit_line(r, n, force)
end

function L.debug(ev, rec) L.write('debug', ev, rec) end
function L.info(ev, rec) L.write('info', ev, rec) end
function L.warn(ev, rec) L.write('warn', ev, rec) end
function L.error(ev, rec) L.write('error', ev, rec) end
function L.start_error(module, err) L.write('error', 'start_error', { module = module, err = tostring(err) }) end

-- opts: dir ('' or 'Mod/' with the slash), level 'info', echo_level 'warn', ev_cap 2000, max_bytes 16 MB,
-- status_every 30, launch_tol 2, frame (fn), sink (fn | false; nil = the harness tap)
function L.init(adapter, opts)
    opts = opts or {}
    A, fs = adapter, adapter.fs
    cfg = { dir = opts.dir or '', ev_cap = opts.ev_cap or 2000, max_bytes = opts.max_bytes or 16 * 1024 * 1024,
        status_every = opts.status_every or 30, launch_tol = opts.launch_tol or 2 }
    min_level = LEVELS[opts.level or 'info'] or LEVELS.info
    echo_level = LEVELS[opts.echo_level or 'warn'] or LEVELS.warn
    frame_fn = opts.frame or function() return 0 end
    if opts.sink == nil then sink = rawget(_G, 'GORE_LOG_TAP') else sink = opts.sink or nil end
    counts, per_ev, capped, every_t, status_fns, status_order = {}, {}, {}, {}, {}, {}
    full, write_errors, header = false, 0, nil
    open_slot()
    last_status = real()
    next_status = last_status + cfg.status_every
    local early = pending
    pending = {}
    for _, p in ipairs(early) do L.write(p[1], p[2], p[3], p[4]) end
    return fh ~= nil
end

function L.set_sink(fn) sink = fn or nil end
function L.level(name) min_level = LEVELS[name] or LEVELS.info end
function L.enabled(name) return (LEVELS[name] or LEVELS.info) >= min_level end
function L.set_frame_source(fn) frame_fn = fn end
function L.counts() return counts end

-- The session header: deep-copied at once (a live table mutated by later settings changes made the analyzer judge
-- against the wrong settings), complete, written whatever the level
local GATES = { 'region', 'rating', 'censor' }
function L.session(h)
    local s = copy(h or {}, 0)
    s.reason = L.new_launch and 'launch' or 'reset'
    s.slot, s.launch, s.token = L.slot, L.launch, L.token
    s.launch_id = tostring(L.token)
    s.build = s.build or 'unstamped'
    s.code_hash = s.code_hash or 'unknown'
    s.version = s.version or 'unknown'
    s.game_build = s.game_build or 'unknown'
    s.loader = type(s.loader) == 'table' and s.loader or {}
    s.loader.kind, s.loader.commit = s.loader.kind or 'unknown', s.loader.commit or 'unknown'
    s.gates = type(s.gates) == 'table' and s.gates or {}
    for _, g in ipairs(GATES) do if s.gates[g] == nil then s.gates[g] = 'unknown' end end
    if L.new_launch then
        s.prev_end = prev_end and copy(prev_end, 0) or 'unknown'
        -- no marker: a crash, a kill, or a quit the mod never saw (a quit hint in armed.json may still excuse it)
        s.prev_quit = not prev_end and 'unknown' or prev_end.clean and ('clean: ' .. tostring(prev_end.reason))
            or 'no_marker'
    end
    s.log_cap, s.ev_cap = cfg.max_bytes, cfg.ev_cap
    header = s
    L.write('info', 'session', s, true)
    return copy(s, 0)
end
function L.header() return header and copy(header, 0) or nil end

function L.add_status(name, fn)
    if not status_fns[name] then status_order[#status_order + 1] = name end
    status_fns[name] = fn
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- The capped event names, plus 'bytes' once the slot passed max_bytes
local function cap_list()
    if not next(capped) and not full then return nil end
    local out = sorted_keys(capped)
    if full then out[#out + 1] = 'bytes' end
    return out
end

-- One status record now (reason 'periodic' from status_tick, or the caller's), returned. window_s: since the last one.
function L.status_record(reason, now)
    if not A then return nil end
    now = now or real()
    local rec = { reason = reason or 'cmd', window_s = math.floor((now - last_status) * 10 + 0.5) / 10,
        counts = copy(counts, 0), log_bytes = bytes, log_cap = cap_list(),
        write_errors = write_errors > 0 and write_errors or nil }
    last_status = now
    local okf, f = pcall(frame_fn)
    rec.frame = okf and f or nil
    for _, name in ipairs(status_order) do
        local ok, s = pcall(status_fns[name])
        if ok and s ~= nil then rec[name] = s
        elseif not ok then rec[name] = { status_error = tostring(s):sub(1, 200) } end
    end
    L.write('info', 'status', rec, true)
    return rec
end

function L.status_tick(now)
    if not A then return nil end
    now = now or real()
    if now < next_status then return nil end
    next_status = now + cfg.status_every
    return L.status_record('periodic', now)
end

function L.every(key, seconds, now)
    now = now or (A and real()) or 0
    local t = every_t[key]
    if t and now - t < seconds then return false end
    every_t[key] = now
    return true
end

-- mark_end(false): withdraw the marker (a quit hint withdrawn because frames still run), so a later crash of this
-- process is not reported as a clean end
function L.mark_end(reason)
    if not A then return false end
    if reason == false then
        return STORE.write_json(fs, cfg.dir .. 'ended.json', { t = wall(), reason = 'withdrawn', token = '' })
    end
    local ok = STORE.write_json(fs, cfg.dir .. 'ended.json', { t = wall(), reason = reason or 'quit', token = L.token,
        launch = L.launch, slot = L.slot, build = header and header.build or nil })
    L.write('info', 'session_end', { via = reason or 'quit', ok = ok })
    return ok
end

-- fn under a pcall: errors counted per name in counts, the first max (3) logged as callback_error
function L.guarded(err_counts, name, fn, max)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local n = (err_counts[name] or 0) + 1
            err_counts[name] = n
            if n <= (max or 3) then pcall(L.error, 'callback_error', { cb = name, err = tostring(err), n = n }) end
        end
    end
end

function L.status()
    return { counts = copy(counts, 0), bytes = bytes, slot = L.slot, log_cap = cap_list(), write_errors = write_errors }
end
function L.reset() every_t = {} end
function L.handoff() return { slot = L.slot, launch = L.launch, token = L.token } end
function L.shutdown(reason)
    if A and fh then
        L.write('info', 'unload', { reason = reason })
        pcall(function() fh:close() end)
    end
    fh = nil
end

return L
