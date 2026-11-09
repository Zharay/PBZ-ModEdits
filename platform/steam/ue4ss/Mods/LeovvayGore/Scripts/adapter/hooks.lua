-- status: worked SWZC origin: kb:runtime-safety-perf#ue4ss-guard-skeleton-hooks-as-data-profiles-mod-off
-- hooks.lua: hooks by id from data/hooks.lua (GENERATED from data/hooks.json by tools/ue/gore/hooks_gen.py).
-- * H.hook(id, feature, { pre, post, optional, lifecycle }) only declares a consumer (main.lua's body runs on the
--   update thread); H.install(opts) registers on the game thread (the first tick). An unknown id, or a native
--   UFunction that does not exist, disables only the consumers' features (H.missing(), unless optional); a Blueprint function whose class is
--   not loaded yet waits for a NotifyOnNewObject watch on its class (the first construction schedules the
--   registration on the game thread, outside the construction), plus one retry per class per LoadMap
--   (H.retry_pending): no polling, a lookup is a full object scan.
-- * Guards (M0 S2.2, spec section 3.4): opts.wrap(id, fn) runs each registration (main.lua passes the always-armed
--   'hook:<id>' sentinel, never the 'hooks:install' batch name); a wrap that refuses ('disabled_by_sentinel') leaves
--   that id alone unregistered (status 'failed', err = the reason). opts.meta(fn, ...) runs the flags read
--   (GetFunctionFlags, main.lua's always-armed 'probe.meta'), once per hook path; without it the flags read 'unread'.
--   This file itself makes no sentinel and no file call.
-- * Every registration attempt logs hook_install {key, ok, optional (every consumer optional), path, err, flags,
--   native 0x400, event 0x800, static 0x2000 ('unread' when not read)}; an unknown id logs it once with err
--   'unknown_id', at install (or at its declaration after the install), so optional covers every consumer declared
--   before it. The old 'hook' event went (spec section 0 rule 11). ok true is not a firing hook (refuted.md:111).
-- * fire() never logs (L014): the first fire of an id sets a flag per side and queues the id once; H.take_first()
--   hands out { {key, side} } and main.lua's tick writes hook_first (S2.17). The breaker's bounded fault records
--   below (hook_error, hook_off, hook_retry) are the only lines written from a hook body, as before.
-- * Native (/Script/) hooks get pre + post callbacks, Blueprint hooks post only. The callback is picked with if/else:
--   'which == pre and h.pre or h.post' ran a post-only consumer twice. Callbacks never return a value (a native hook's
--   return value would replace the function's result).
-- * Each consumer runs under its own pcall and its own feature gate (opts.gate(feature) -> bool: the sched breaker, the
--   mod-off switch), so one tripped feature never silences another on the same UFunction. A consumer's first 3 errors
--   are logged (hook_error). The breaker is windowed: MAX_ERRORS 20 inside WINDOW_S 30 s switch the consumer off
--   (hook_off), RETRY_S 60 s later it runs again (hook_retry), after MAX_OFFS 3 trips it stays off. Never a count per
--   session: '20 errors per session' switched features off for good after an hour or two ("gore stops after a while").
-- * A lifecycle consumer (upkeep that runs while the mod is off: Cap follow, hide re-assert; DESIGN C5) skips the gate
--   but keeps its own breaker, and unregister_all keeps its hook registered; the other consumers stay gated.
-- * Counters per id: calls (the pre side of a native hook, the post side of a Blueprint one), ms_max, ms_total and
--   n_ge_1ms (dispatches of one side at or over 1 ms), durations rounded to the microsecond; D10 reads means over many
--   fires (ms_total / calls), never one call.
-- * opts.count_only: every id in the data is registered, callbacks only count and flag first fires, no consumer runs;
--   nothing in M0 uses it (D5: every profile inits with count_only false).
-- * An inlined Blueprint call site never fires: check calls > 0 per hook in the first live run.
-- API: init(data, opts) hook install(opts) take_first retry_pending(reason) unregister_all reregister_all missing
-- status reset shutdown
-- Evidence: [worked SWZC] lib/guard.lua 117-322 (its breaker: 8 errors in 60 s), tools/luatest/test_failsafe.lua; the
-- breaker numbers follow core/sched.lua (DD2; the windowed rule untested in game);
-- kb:runtime-safety-perf#windowed-per-feature-circuit-breaker-with-timed-retry; engine note 'UE5 / UE4SS 527a483b'
local ue = require('adapter.ue')
local LOG = require('core.log')

-- UFunction flag bits (EFunctionFlags: FUNC_Native, FUNC_Event, FUNC_Static)
local H = { MAX_ERRORS = 20, WINDOW_S = 30, RETRY_S = 60, MAX_OFFS = 3,
    FLAG_NATIVE = 0x400, FLAG_EVENT = 0x800, FLAG_STATIC = 0x2000 }

local specs, hooks, order, pending, watched, class_state = {}, {}, {}, {}, {}, {}
local gate, count_only, alive, installed, on_missing = nil, false, true, false, nil
local wrap, meta = nil, nil                 -- H.install(opts): the per-registration guard and the flags-read guard
local firsts = {}                           -- hook records whose first fire H.take_first() has not handed out yet

-- opts: gate(feature) -> bool, count_only, on_missing(feature, id) (a Blueprint hook that failed after its class
-- loaded, past the first-tick H.missing() pass)
function H.init(data, opts)
    opts = opts or {}
    specs = type(data) == 'table' and type(data.hooks) == 'table' and data.hooks or {}
    hooks, order, pending, watched, class_state, firsts = {}, {}, {}, {}, {}, {}
    gate, on_missing = opts.gate or function() return true end, opts.on_missing
    count_only, alive, installed, wrap, meta = opts.count_only == true, true, false, nil, nil
    if count_only then
        local ids = {}
        for id in pairs(specs) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do H.hook(id, 'probe', {}) end
    end
    return true
end

local function class_of(spec) return spec.path:match('^([^:]+):') end

-- c.off: nil (on), a retry time (s, os.clock) or true (off for the session after MAX_OFFS trips)
local function trip(h, c, side, err, now)
    c.errors = c.errors + 1
    if c.errors <= 3 then LOG.warn('hook_error', { id = h.id, feature = c.feature, side = side, err = tostring(err) }) end
    if not c.win_t0 or now - c.win_t0 > H.WINDOW_S then c.win_t0, c.win_n = now, 0 end
    c.win_n = c.win_n + 1
    if c.win_n < H.MAX_ERRORS then return end
    c.offs, c.win_t0, c.win_n = c.offs + 1, nil, 0
    if c.offs >= H.MAX_OFFS then c.off = true else c.off = now + H.RETRY_S end
    LOG.error('hook_off', { id = h.id, feature = c.feature, errors = c.errors, offs = c.offs, retry = c.off ~= true,
        last = tostring(err) })
end

local function run_consumers(h, side, now, ...)
    for _, c in ipairs(h.consumers) do
        local cb
        if side == 'pre' then cb = c.pre else cb = c.post end
        if cb and type(c.off) == 'number' and now >= c.off then
            c.off = nil
            LOG.info('hook_retry', { id = h.id, feature = c.feature, offs = c.offs })
        end
        if cb and c.off == nil and (c.lifecycle or gate(c.feature)) then
            local ok, err = pcall(cb, ...)
            if not ok then trip(h, c, side, err, now) end
        end
    end
end

-- The hook body: count, flag the first fire, run the consumers, time them. No LOG, file or sentinel call here (L014):
-- the first fire of an id queues it once with its side, and the tick writes hook_first from H.take_first(). A duration
-- is rounded to the microsecond: on a 1 ms os.clock step, 10.0015 - 10.0005 reads 0.99999 ms and missed n_ge_1ms.
local function fire(h, side, counts)
    return function(...)
        if not alive then return end
        if counts then h.calls = h.calls + 1 end
        if not h.fired[side] then
            h.fired[side] = true
            if not h.first_side then
                h.first_side = side
                firsts[#firsts + 1] = h
            end
        end
        if count_only then return end
        local t0 = os.clock()
        run_consumers(h, side, t0, ...)
        local ms = math.floor((os.clock() - t0) * 1e6 + 0.5) / 1000
        h.ms_total = h.ms_total + ms
        if ms > h.ms_max then h.ms_max = ms end
        if ms >= 1 then h.n_ge_1ms = h.n_ge_1ms + 1 end
    end
end

-- The ids that fired for the first time since the last call, once each, in fire order: { {key, side} } (side: the
-- callback that fired first). For the tick (main.lua writes hook_first), never from a hook body.
function H.take_first()
    local out = {}
    for _, h in ipairs(firsts) do
        if hooks[h.id] == h then out[#out + 1] = { key = h.id, side = h.first_side } end
    end
    if firsts[1] ~= nil then firsts = {} end
    return out
end

-- One flag bit: true or false, 'unread' when the flags were not read
local function bit(f, b)
    local i = math.tointeger(f)
    if not i then return 'unread' end
    return (i & b) ~= 0
end
-- The UFunction flags, read once per hook path and only through the meta guard (GetFunctionFlags is a reflection
-- call this file never runs bare, spec section 3.4): an integer, or 'unread' without a guard, on a refusal or a miss
local function read_flags(h)
    if h.flags ~= nil then return h.flags end
    if not meta then return 'unread' end
    local okm, f = pcall(meta, ue.func_flags, h.spec.path)
    h.flags = okm and type(f) == 'number' and math.tointeger(f) or 'unread'
    return h.flags
end
-- optional = every consumer of the id is optional (a failure then disables no feature)
local function optional_of(h)
    for _, c in ipairs(h.consumers) do if not c.optional then return false end end
    return #h.consumers > 0
end
-- One record per registration attempt (and once per unknown id); the old 'hook' event went (spec section 0 rule 11)
local function log_install(h, ok, flags)
    local rec = { key = h.id, ok = ok, optional = optional_of(h), path = h.spec and h.spec.path, err = h.err,
        flags = flags, native = bit(flags, H.FLAG_NATIVE), event = bit(flags, H.FLAG_EVENT),
        static = bit(flags, H.FLAG_STATIC) }
    local write = ok and LOG.info or LOG.warn
    write('hook_install', rec)
end

-- Register one hook through the wrap (main.lua: the always-armed 'hook:<id>' sentinel). reg records RegisterHook's
-- own result, so a registration that ran is never lost behind a wrap's single return value; a wrap that returns
-- nil and a reason without running reg ('disabled_by_sentinel', 'not_armed', 'arm_write_failed') leaves the id
-- unregistered with that reason.
local function try_register(h)
    local flags = read_flags(h)
    local res
    local function reg()
        if h.spec.kind == 'native' then
            res = { ue.register_hook(h.spec.path, fire(h, 'pre', true), fire(h, 'post', false)) }
        else res = { ue.register_hook(h.spec.path, fire(h, 'post', true)) } end
        return true
    end
    local why
    if wrap then
        local okw, r, err = pcall(wrap, h.id, reg)
        if not okw then why = r elseif r == nil then why = err end
    else reg() end
    local ok = res ~= nil and res[1] == true
    if ok then h.status, h.err, h.ids = 'ok', nil, { res[2], res[3] }
    else h.status, h.err = 'failed', tostring(res and res[2] or why or 'wrap_refused') end
    log_install(h, ok, flags)
    return ok
end

-- Declare a consumer. Returns the hook record, or nil and 'unknown_id'.
function H.hook(id, feature, handlers)
    handlers = handlers or {}
    local spec = specs[id]
    local h = hooks[id]
    local new = h == nil
    if new then
        h = { id = id, spec = spec, status = spec and 'new' or 'unknown_id', err = not spec and 'unknown_id' or nil,
            calls = 0, ms_max = 0, ms_total = 0, n_ge_1ms = 0, fired = {}, consumers = {}, features = {} }
        hooks[id] = h
        order[#order + 1] = id
    end
    h.consumers[#h.consumers + 1] = { feature = feature, pre = handlers.pre, post = handlers.post, optional =
        handlers.optional == true, lifecycle = handlers.lifecycle == true, errors = 0, win_n = 0, offs = 0 }
    h.features[#h.features + 1] = feature
    -- an unknown id declared after the install logs at once; before it, H.install logs it (every consumer known)
    if not spec and installed and not h.logged then h.logged = true log_install(h, false, 'unread') end
    if installed and spec and h.status == 'new' then H.install() end
    if not spec then return nil, 'unknown_id' end
    return h
end

local function watch(cls)
    if watched[cls] then return end
    watched[cls] = 'on'
    local scheduled = false
    local ok, err = ue.watch_class(cls, function()
        if watched[cls] ~= 'on' then return true end           -- every hook of the class is in: unregister the watch
        if scheduled then return false end                      -- repeats arrive in the same frame
        scheduled = true
        class_state[cls] = true
        ExecuteInGameThread(function()
            local left = H.retry_class(cls)
            if left == 0 then watched[cls] = 'done' else scheduled = false end
            LOG.debug('hook_class_loaded', { class = cls, left = left })
        end)
        return false
    end)
    if not ok then LOG.warn('hook_watch_failed', { class = cls, err = tostring(err) }) end
end

local function class_loaded(cls)
    if class_state[cls] == nil then class_state[cls] = ue.find(cls) ~= nil end
    return class_state[cls]
end

-- Game thread: register every declared hook that is new (BP classes not loaded yet go pending behind a watch).
-- opts.wrap(id, fn) runs each registration, opts.meta(fn, ...) each flags read; both stick for later registrations
-- (a Blueprint class load, mod on) until the next H.init.
function H.install(opts)
    if type(opts) == 'table' then
        if opts.wrap ~= nil then wrap = opts.wrap end
        if opts.meta ~= nil then meta = opts.meta end
    end
    installed = true
    local n = 0
    for _, id in ipairs(order) do
        local h = hooks[id]
        if h.status == 'new' then
            local cls = class_of(h.spec)
            if h.spec.kind ~= 'native' and cls and not class_loaded(cls) then
                h.status, pending[id] = 'pending', true
                watch(cls)
            elseif try_register(h) then n = n + 1 end
        elseif h.status == 'unknown_id' and not h.logged then
            h.logged = true
            log_install(h, false, 'unread')
        end
    end
    return n
end

function H.retry_class(cls)
    local left = 0
    for _, id in ipairs(order) do
        local h = hooks[id]
        if pending[id] and class_of(h.spec) == cls then
            pending[id] = nil                            -- one try once the class exists: a miss now is a real miss
            if not try_register(h) and on_missing then
                for _, c in ipairs(h.consumers) do if not c.optional then pcall(on_missing, c.feature, id) end end
            end
        end
    end
    return left
end

-- A map load: one lookup per pending class (its miss was forgotten), then the class watch stays for the rest
function H.retry_pending(reason)
    local classes, left = {}, 0
    for id in pairs(pending) do classes[class_of(hooks[id].spec)] = true end
    for cls in pairs(classes) do
        class_state[cls] = nil
        if class_loaded(cls) then H.retry_class(cls) end
    end
    for _ in pairs(pending) do left = left + 1 end
    if reason then LOG.debug('hook_retry', { reason = reason, left = left }) end
    return left
end

-- feature -> the first missing or failed id (optional consumers excluded)
function H.missing()
    local out = {}
    for _, id in ipairs(order) do
        local h = hooks[id]
        if h.status == 'unknown_id' or h.status == 'failed' then
            for _, c in ipairs(h.consumers) do if not c.optional and not out[c.feature] then out[c.feature] = id end end
        end
    end
    return out
end

-- A hook with a lifecycle consumer stays registered through mod off (DESIGN C5: upkeep runs while off)
local function keeps(h)
    for _, c in ipairs(h.consumers) do if c.lifecycle then return true end end
    return false
end
-- Mod off / on (game thread): every registered hook down except the lifecycle ones, then back up
function H.unregister_all()
    local n = 0
    for _, id in ipairs(order) do
        local h = hooks[id]
        if h.status == 'ok' and not keeps(h) then
            ue.unregister_hook(h.spec.path, h.ids[1], h.ids[2])
            h.status, n = 'unregistered', n + 1
        end
    end
    return n
end
function H.reregister_all()
    local n = 0
    for _, id in ipairs(order) do
        local h = hooks[id]
        if h.status == 'unregistered' and try_register(h) then n = n + 1 end
    end
    return n
end

function H.status()
    local out = { ok = 0, failed = 0, pending = 0, unknown = 0, ids = {} }
    for _, id in ipairs(order) do
        local h = hooks[id]
        local s = h.status
        if s == 'ok' then out.ok = out.ok + 1 elseif s == 'pending' then out.pending = out.pending + 1
        elseif s == 'unknown_id' then out.unknown = out.unknown + 1 elseif s == 'failed' then out.failed = out.failed + 1 end
        local off = 0
        for _, c in ipairs(h.consumers) do if c.off ~= nil then off = off + 1 end end
        local fired = nil
        if h.first_side then fired = { pre = h.fired.pre, post = h.fired.post } end
        out.ids[id] = { status = s, calls = h.calls, ms_max = math.floor(h.ms_max * 100 + 0.5) / 100,
            ms_total = math.floor(h.ms_total * 1000 + 0.5) / 1000, n_ge_1ms = h.n_ge_1ms, err = h.err,
            consumers_off = off > 0 and off or nil, fired = fired }
    end
    return out
end
function H.reset() end
-- Unload (update thread, engine-free): stale callbacks do nothing; UE4SS drops the registrations itself
function H.shutdown() alive = false end

return H
