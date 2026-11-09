-- status: untested origin: kb:persistence-settings-api#public-lua-api-for-other-mods
-- api.lua: the public Lua API v1 for other mods. One global table, set by the one rawset line marked 'api global' (lint
-- L002 allows a global write only there); its name comes from the mod's meta (ctx.meta.api_global), never from core.
-- The table { api = 1, version, is_enabled, on, off } keeps its identity for the Lua state: a second init swaps the
-- functions in place; a script reset's new state makes a new table, and consumers subscribe again from their reload.
-- Consumers look it up lazily with rawget from their own first frame callback (scripts load in file-name order).
-- * is_enabled(feature) -> true | false, why, reasons in a fixed order: unknown_feature, closed, not_ready, off (the
--   mod-off switch or the master setting), vanilla (the compare is on), sentinel (the delivery or a listed
--   sentinel name is switched off), starved (opts.starved: our late phase does not run), then the feature's
--   own (A.reason).
-- * on(event, fn, name) -> token | nil, why (unknown_event, bad_args, too_many); off(token) -> bool. Events are the
--   ones features declare (A.event(name, { keep, stale })).
-- * Zero cost before the first on(): features ask A.wants(ev) before building a payload; A.push queues a plain table
--   (addresses, ids: never engine handles, since userdata equality is unproven and addresses are reused) only while
--   someone listens. Delivery is one late job (api_deliver) in the next late phase, in order, at most A.PER_JOB records
--   a job and A.OUT_MAX waiting (the oldest non-keep record goes first), inside the crash sentinel 'api_cb' (a native
--   fault in a subscriber switches the callbacks off at the next start, not our features). Each subscriber call runs
--   under pcall with its own copy of the payload; one that fails A.FAIL_MAX times is dropped.
-- * A.on_load() drops waiting stale records (their addresses may name other objects after a load).
-- API (stable): A.init(api_global, version [, opts]) or A.init(A, { global, version, ... }); event wants push reason
--   on_load reset shutdown status. opts: ready() -> bool (false: not_ready), starved() -> bool, sentinels { name }.
-- Evidence: [untested] DD2 api.lua (R.on/off/is_enabled, deliver_body, make_room, the rawset line); docs/spec/api.md;
-- kb:persistence-settings-api#public-lua-api-for-other-mods
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')
local S = require(BASE .. 'sched')
local SENT = require(BASE .. 'sentinel')
local C = require(BASE .. 'config')
local MODOFF = require(BASE .. 'modoff')

local A = { NUM = 1, MAX_SUBS = 32, FAIL_MAX = 5, PER_JOB = 64, OUT_MAX = 256, NAME_MAX = 40, SENTINEL = 'api_cb' }

local T = { api = A.NUM, version = nil }            -- the global table: same identity for the Lua state
A.T = T

local EVENTS, reasons = {}, {}
local subs, wants, next_id = {}, {}, 0
local OUT, head, tail, queued, queued_ep = {}, 1, 0, false, nil
local started, closed, installed = false, false, nil
local ready_fn, starved_fn, sentinels = nil, nil, {}
local stats, fn_errors = nil, {}

local function copy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end

local function base_reason()
    if closed then return 'closed' end
    if not started then return 'not_ready' end
    if ready_fn then
        local ok, r = pcall(ready_fn)
        if not (ok and r == true) then return 'not_ready' end
    end
    if MODOFF.is_off() then return 'off' end
    local okc, s = pcall(C.get)
    if okc and type(s) == 'table' and s.enabled == false then return 'off' end
    if MODOFF.is_vanilla() then return 'vanilla' end
    if SENT.is_disabled(A.SENTINEL) then return 'sentinel' end
    for _, n in ipairs(sentinels) do if SENT.is_disabled(n) then return 'sentinel' end end
    if starved_fn then
        local ok, r = pcall(starved_fn)
        if ok and r == true then return 'starved' end
    end
    return nil
end

-- ---------- delivery ----------
local function drain()
    OUT, head, tail = {}, 1, 0
end

local function remove(s)
    local list, found = {}, false
    for _, x in ipairs(subs) do
        if x == s then found = true else list[#list + 1] = x end
    end
    if found then
        subs = list
        wants[s.ev] = math.max(0, (wants[s.ev] or 1) - 1)
    end
    return found
end

local function call(s, r)
    local ok, err = pcall(s.fn, copy(r.p), r.ev)
    s.calls = s.calls + 1
    if ok then return end
    s.fails = s.fails + 1
    stats.cb_errors = stats.cb_errors + 1
    if s.fails <= 2 then LOG.warn('api_cb_error', { event = r.ev, name = s.name, err = tostring(err), n = s.fails }) end
    if s.fails >= A.FAIL_MAX and remove(s) then
        stats.cb_off = stats.cb_off + 1
        LOG.warn('api_cb_off', { event = s.ev, name = s.name, fails = s.fails })
    end
end

local function deliver_body()
    local n = 0
    while not closed and head <= tail and n < A.PER_JOB do
        local r = OUT[head]
        OUT[head], head, n = nil, head + 1, n + 1
        for _, s in ipairs(subs) do                    -- an on() or off() inside a callback counts from the next record
            if s.ev == r.ev then call(s, r) end
        end
        stats.delivered = stats.delivered + 1
    end
    return true
end

local deliver
-- One delivery job at a time. A job queued before a sched epoch bump (a load, a map change) is dropped unrun, so a
-- stale flag would stop every later delivery: queue again when the flagged job belongs to an older epoch.
local function kick()
    if queued and not S.stale(queued_ep) then return end
    queued, queued_ep = true, S.epoch()
    S.late('api_deliver', deliver)
end

deliver = function()
    queued = false
    if closed then return drain() end
    if SENT.is_disabled(A.SENTINEL) then
        stats.skipped = stats.skipped + (tail - head + 1)
        return drain()
    end
    local r, err = SENT.sentinel(A.SENTINEL, deliver_body)
    if r == nil and LOG.every('api_deliver_error', 30) then
        LOG.warn('api_error', { fn = 'deliver', err = tostring(err) })   -- e.g. arm_write_failed: retried next frame
    end
    if closed or head > tail then return drain() end
    kick()
end

-- Room for one more record: the oldest that is not a keep event goes (the oldest of all when every one is)
local function make_room()
    local at = head
    for i = head, tail do
        local e = EVENTS[OUT[i].ev]
        if not (e and e.keep) then at = i break end
    end
    for i = at, head + 1, -1 do OUT[i] = OUT[i - 1] end
    OUT[head] = nil
    head = head + 1
    stats.dropped = stats.dropped + 1
end

-- ---------- what features call ----------
-- Declare an API event: keep (never dropped for room: a subscriber waits on it), stale (dropped by A.on_load)
function A.event(name, opts)
    opts = opts or {}
    EVENTS[name] = { keep = opts.keep == true, stale = opts.stale == true }
end

function A.wants(ev) return not closed and (wants[ev] or 0) > 0 end

-- Queue a plain payload for the next late phase; false (nothing done) while nobody listens to ev
function A.push(ev, payload)
    if closed or (wants[ev] or 0) == 0 then return false end
    if tail - head + 1 >= A.OUT_MAX then make_room() end
    tail = tail + 1
    OUT[tail] = { ev = ev, p = payload, frame = S.frame }
    kick()
    return true
end

-- A feature for is_enabled: fn() -> nil (on) or its reason word (cut_off, family_off, kind_off, ...)
function A.reason(feature, fn) reasons[feature] = fn end

-- A load: waiting records of the world that went are dropped
function A.on_load()
    local list, k, n = {}, 0, 0
    for i = head, tail do
        local r = OUT[i]
        local e = EVENTS[r.ev]
        if e and e.stale then n = n + 1 else k = k + 1 list[k] = r end
    end
    OUT, head, tail = list, 1, k
    if stats then stats.stale = stats.stale + n end
    if k > 0 and not closed then kick() end             -- the kept records still go out (a new job if the old went)
    return n
end

-- ---------- the table's functions ----------
local R = {}

function R.is_enabled(feature)
    if feature ~= nil and not reasons[feature] then return false, 'unknown_feature' end
    local why = base_reason()
    if why then return false, why end
    if feature == nil then return true end
    local ok, r = pcall(reasons[feature])
    if not ok then return false, 'error' end
    if r ~= nil and r ~= true then return false, tostring(r) end
    return true
end

function R.on(ev, fn, name)
    if closed then return nil, 'closed' end
    if type(ev) ~= 'string' or not EVENTS[ev] then return nil, 'unknown_event' end
    if type(fn) ~= 'function' then return nil, 'bad_args' end
    if #subs >= A.MAX_SUBS then return nil, 'too_many' end
    stats = stats or { delivered = 0, dropped = 0, cb_errors = 0, cb_off = 0, skipped = 0, stale = 0 }
    next_id = next_id + 1
    local s = { id = next_id, ev = ev, fn = fn, fails = 0, calls = 0,
        name = type(name) == 'string' and name:sub(1, A.NAME_MAX) or '?' }
    local list = {}
    for i, x in ipairs(subs) do list[i] = x end
    list[#list + 1] = s
    subs = list
    wants[ev] = (wants[ev] or 0) + 1
    LOG.info('api_on', { event = ev, name = s.name, n = #subs })
    return s.id
end

function R.off(token)
    for _, s in ipairs(subs) do
        if s.id == token and remove(s) then
            LOG.info('api_off', { event = s.ev, name = s.name, n = #subs })
            return true
        end
    end
    return false
end

-- Every table function under pcall: an error of ours answers like a refusal and never reaches the caller
local FALLBACK = { is_enabled = function() return false, 'error' end, on = function() return nil, 'error' end,
    off = function() return false end }
local function guarded(k, fn)
    return function(...)
        local res = table.pack(pcall(fn, ...))
        if res[1] then return table.unpack(res, 2, res.n) end
        fn_errors[k] = (fn_errors[k] or 0) + 1
        if fn_errors[k] == 1 then pcall(LOG.warn, 'api_error', { fn = k, err = tostring(res[2]) }) end
        return FALLBACK[k]()
    end
end
local function install()
    for k, fn in pairs(R) do T[k] = guarded(k, fn) end
end
install()

-- ---------- lifecycle ----------
function A.init(a, b, c)
    local opts, name, version
    if type(a) == 'table' then
        opts = b or {}
        name, version = opts.global, opts.version
    else
        opts = c or {}
        name, version = a, b
    end
    T.version = version
    ready_fn, starved_fn = opts.ready, opts.starved
    sentinels = type(opts.sentinels) == 'table' and opts.sentinels or {}
    closed, started = false, true
    queued, queued_ep = false, nil                      -- a re-init of sched drops its jobs; at worst one extra job
    install()
    if type(name) == 'string' and name ~= '' and installed == nil then
        rawset(_G, name, T)                                                       -- api global
        installed = name
    end
    return true
end

-- A map change: like a load
function A.reset() A.on_load() end

function A.shutdown()
    closed, started = true, false
    subs, wants, queued, queued_ep = {}, {}, false, nil
    drain()
end

-- nil until the first on() (nothing to report before anyone used the API)
function A.status()
    if not stats then return nil end
    local q = tail - head + 1
    return { subs = #subs, queued = q > 0 and q or nil, delivered = stats.delivered, dropped = stats.dropped,
        cb_errors = stats.cb_errors, cb_off = stats.cb_off, skipped = stats.skipped, stale = stats.stale,
        global = installed }
end

return A
