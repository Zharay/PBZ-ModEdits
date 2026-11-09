-- status: worked DD2 (windowed rule untested in game) origin: kb:runtime-safety-perf#phase-scheduler-with-hook-inbox
-- sched.lua: the phase scheduler. Hooks only copy plain data (S.post) and return; every engine write runs here, a frame
-- later, on the game thread: the late phase drains the inbox, runs queued jobs within a per-frame budget (seconds AND
-- counted units, the rest carried over in order), due timers and tickers; the render phase runs ordered writers.
-- Nothing runs while the gate is closed (title, loads); the game clock stops in pause and follows the game speed.
-- Every callback is xpcall'd under its name with a windowed circuit breaker: MAX_ERRORS 20 errors inside one
-- ERR_WINDOW_S 30 s window switch the name off (job_off), a sweep retries it OFF_RETRY_S 60 s later (job_retry), and
-- after MAX_OFFS 3 switch-offs it stays off until S.reset_off (a Retry button). A per-session count switched features
-- off for good after an hour or two ("gore stops after a while"). S.teardown bypasses the breaker (cleanup must run
-- after a trip) and never counts. Every queued item carries the epoch it was queued in; S.bump_epoch (hot reload, map
-- change) makes older items drop instead of running against freed objects.
--
-- ADAPTER CONTRACT (the one canonical block: every lifecycle module of core-lua takes this table A in init(A, opts))
--   A.fs.read(path) -> text | nil                 the whole file; nil when missing
--   A.fs.write(path, text) -> true | nil, err     the whole file (store.lua encodes before it calls)
--   A.fs.open_append(path, truncate) -> h | nil   h:write(...), h:flush(), h:close() [, h:seek('end')]: io handles fit
--   A.fs.rename(from, to)?  A.fs.remove(path)?    absent on REFramework (no os.rename/os.remove): store.lua uses A/B
--                                                 slots there and tmp + rename + bak where they exist
--   A.clock.real() -> s                           monotonic seconds, fractional (os.clock; REFramework steps 1 ms)
--   A.clock.wall() -> s                           unix seconds (os.time)
--   A.json?                                       not used by core (store.lua owns the codec)
--   A.keys.down(vk)? -> bool                      quit hints in sentinel.lua (REF reframework:is_key_down)
--   A.proc_token()? -> string                     survives a hot reload, dies with the process (a UE4SS shared
--                                                 variable); absent: log.lua keys the process by its stored launch id
--   A.echo(line)?                                 the loader console; never the global printer (other mods hook it)
-- Phases (the adapter binds them; core never registers a callback):
--   REFramework: late = LateUpdateBehavior -> S.on_late(speed); render = PrepareRendering -> S.on_render();
--     status = re.on_frame -> LOG.status_tick() and SENT.tick() (independent: other scripts' errors can stop a list)
--   UE4SS: one game-thread tick: S.on_late(speed) then S.on_render() (writers after late); status from a separate
--     loop. OnUnload runs OFF the game thread: only S.bump_epoch, S.teardown of pure-Lua state and file writes there.
-- Modules require siblings through their own name (...): REFramework shares one Lua state among all scripts, so a bare
-- require('core.log') can load another mod's module. No global printing, no math-library random numbers, no globals.
-- API (fixed, lint L015): S.post S.on_post S.late S.after S.ticker S.writer S.run S.teardown S.bump_epoch S.charge
--   S.take_cost; also set_gate, late_unpaused, set_paused_source, remove_ticker, remove_writer, errors, off,
--   reset_off, pending, epoch, stale. Phase entry points for the adapter: S.on_late(speed), S.on_render().
-- Evidence: [worked DD2] core/sched.lua; [worked SWZC] lib/guard.lua (breaker, cleanup via safe(nil)), epochs in
-- debris.lua/blaster.lua; kb:runtime-safety-perf#windowed-per-feature-circuit-breaker-with-timed-retry, principles 8-11
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')

local S = { frame = 0, pass = 0, phase = 'load', game_time = 0.0, in_game = true, paused = false, out_frame = -1 }

local MAX_ERRORS, MAX_TRACES, TRACE_CHARS = 20, 12, 900
local ERR_WINDOW_S, OFF_RETRY_S, MAX_OFFS = 30, 60, 3
local BUDGET_S = 0.0003      -- seconds of queued jobs per frame (G-PERF 0.5 ms for everything)

local A, cfg = nil, nil
local clock = function() return 0 end
local inbox, handlers, jobs, timers = {}, {}, {}, {}
local tickers, ticker_order, writers, writer_order = {}, {}, {}, {}
local errors, off, win, off_at, offs = {}, {}, {}, {}, {}
local traces, epoch, drops, units = 0, 0, 0, 0
local last_real = nil
local gate_fn = function() return true, false end
local held, paused_fn = {}, nil
local cost, by, rby

local function new_cost()
    return { late = 0, render = 0, late_max = 0, render_max = 0, n = 0, late_sum = 0, render_sum = 0, units = 0,
        units_max = 0, teardown_errors = 0 }
end

-- opts: budget_s 0.0003, budget_units (nil: none), max_errors 20, err_window 30, retry_s 60, max_offs 3, gate(fn),
-- paused_source(fn)
function S.init(adapter, opts)
    opts = opts or {}
    A = adapter
    clock = adapter.clock.real
    cfg = { budget_s = opts.budget_s or BUDGET_S, budget_units = opts.budget_units, max_errors = opts.max_errors
        or MAX_ERRORS, err_window = opts.err_window or ERR_WINDOW_S, retry_s = opts.retry_s or OFF_RETRY_S,
        max_offs = opts.max_offs or MAX_OFFS }
    S.frame, S.pass, S.phase, S.game_time, S.in_game, S.paused, S.out_frame = 0, 0, 'load', 0.0, true, false, -1
    inbox, handlers, jobs, timers = {}, {}, {}, {}
    tickers, ticker_order, writers, writer_order = {}, {}, {}, {}
    errors, off, win, off_at, offs = {}, {}, {}, {}, {}
    traces, epoch, drops, units, last_real = 0, 0, 0, 0, nil
    gate_fn = opts.gate or function() return true, false end
    held, paused_fn = {}, opts.paused_source
    cost, by, rby = new_cost(), {}, {}
    return true
end

local function fail(name, err, tb)
    local n = (errors[name] or 0) + 1
    errors[name] = n
    if n <= 3 then LOG.warn('job_error', { job = name, err = tostring(err), n = n, tb = tb }) end
    if off[name] then return end
    local now, w = clock(), win[name]
    if not w or now - w.t0 > cfg.err_window then
        w = { t0 = now, n = 0 }
        win[name] = w
    end
    w.n = w.n + 1
    if w.n >= cfg.max_errors then
        local k = (offs[name] or 0) + 1
        off[name], off_at[name], offs[name] = true, now, k
        LOG.error('job_off', { job = name, why = k >= cfg.max_offs and 'max_offs' or 'breaker', errors = n,
            window_s = cfg.err_window, offs = k, last = tostring(err) })
    end
end

-- The sweep (top of the late phase, only while a name is off, also with the gate closed): a name off for retry_s runs
-- again with a new window unless it was switched off max_offs times. A name set off from outside starts its clock here.
local function retry(now)
    for name in pairs(off) do
        local at = off_at[name]
        if not at then
            off_at[name] = now
        elseif now - at >= cfg.retry_s and (offs[name] or 0) < cfg.max_offs then
            off[name], off_at[name], win[name] = nil, nil, nil
            LOG.info('job_retry', { job = name, offs = offs[name] or 0 })
        end
    end
end

-- The stack of the first MAX_TRACES errors (a bare message could not place an intermittent ticker error)
local function traced(e)
    if traces >= MAX_TRACES then return e end
    traces = traces + 1
    local tb = debug.traceback('', 2):gsub('\n%s*', ' | ')
    return { e = e, tb = tb:sub(1, TRACE_CHARS) }
end

local function run(name, fn, ...)
    if off[name] then return false end
    local ok, err = xpcall(fn, traced, ...)
    if not ok then
        if type(err) == 'table' and err.tb then fail(name, err.e, err.tb) else fail(name, err) end
    end
    return ok
end
-- A job run inside another (its own errors and switch-off: never tick one feature inside another's ticker unguarded)
S.run = run

-- Cleanup that must run after a trip: bypasses the breaker, logs teardown_error, never counts
function S.teardown(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        cost.teardown_errors = cost.teardown_errors + 1
        LOG.warn('teardown_error', { job = name, err = tostring(err) })
    end
    return ok
end

function S.set_gate(fn) gate_fn = fn end
function S.epoch() return epoch end
function S.stale(ep) return ep ~= epoch end
function S.bump_epoch(reason)
    epoch = epoch + 1
    local n = #inbox + #jobs + #timers + #held
    inbox, jobs, timers, held = {}, {}, {}, {}
    drops = drops + n
    LOG.info('epoch', { epoch = epoch, reason = reason, dropped = n })
    return epoch
end

-- Hooks: plain data only; the handler for kind runs in the next late phase with (rec, frame)
function S.post(kind, rec) inbox[#inbox + 1] = { kind = kind, rec = rec, frame = S.frame, ep = epoch } end
function S.on_post(kind, name, fn) handlers[kind] = { name = name, fn = fn } end
function S.late(name, fn, ...) jobs[#jobs + 1] = { name = name, fn = fn, args = table.pack(...), ep = epoch } end
-- Effect, spawn and sound jobs that must wait out a GUI pause or a missing player (paused_source() true): they keep
-- their order and join the job queue in the first late phase where it is false
function S.set_paused_source(fn) paused_fn = fn end
function S.late_unpaused(name, fn, ...)
    held[#held + 1] = { name = name, fn = fn, args = table.pack(...), ep = epoch }
end
-- clock 'game' (default: stops in pause and while the gate is closed, follows the speed) or 'real' (watchdogs)
function S.after(seconds, name, fn, clk, ...)
    local game = clk ~= 'real'
    timers[#timers + 1] = { at = (game and S.game_time or clock()) + seconds, game = game, name = name, fn = fn,
        args = table.pack(...), ep = epoch }
end
-- Registered again (also after remove_ticker): the old place in the order, never a second run per frame
function S.ticker(name, fn)
    tickers[name] = fn
    for _, n in ipairs(ticker_order) do if n == name then return end end
    ticker_order[#ticker_order + 1] = name
end
function S.remove_ticker(name) tickers[name] = nil end
-- before: a writer this one must run ahead of; unknown or already listed: the order stays
function S.writer(name, fn, before)
    writers[name] = fn
    for _, n in ipairs(writer_order) do if n == name then return end end
    local at = #writer_order + 1
    for i, n in ipairs(writer_order) do if n == before then at = i break end end
    table.insert(writer_order, at, name)
end
function S.remove_writer(name) writers[name] = nil end
-- Counted work units (engine calls, rays, VM-heavy steps) at one choke point; the job loop stops at budget_units
function S.charge(n) units = units + (n or 1) end

function S.errors() return errors end
function S.off() return off end
-- The Retry button: a new window and no sweep clock; errors and offs are kept (a 4th trip stays off)
function S.reset_off(name) off[name], off_at[name], win[name] = nil, nil, nil end
function S.pending() return #jobs, #inbox, #timers end

local function run_item(it)
    if it.ep ~= epoch then drops = drops + 1 return end
    run(it.name, it.fn, table.unpack(it.args, 1, it.args.n))
end

-- The late phase. speed: the game's time scale (1.0). The clock is read once at the top and once per job/ticker.
function S.on_late(speed)
    S.phase = 'late'
    S.frame, S.pass = S.frame + 1, S.pass + 1
    local now = clock()
    if next(off) ~= nil then retry(now) end
    local ok_gate, in_game, paused = pcall(gate_fn)
    if ok_gate then S.in_game, S.paused = in_game ~= false, paused == true end
    local dt = last_real and (now - last_real) or 0
    last_real = now
    if not S.in_game then
        S.out_frame = S.frame
        return
    end
    if not S.paused then S.game_time = S.game_time + dt * (speed or 1.0) end
    units = 0
    if #held > 0 then
        local ok, p = true, false
        if paused_fn then ok, p = pcall(paused_fn) end
        if not (ok and p == true) then
            for _, j in ipairs(held) do jobs[#jobs + 1] = j end
            held = {}
        end
    end
    if #inbox > 0 then
        local box = inbox
        inbox = {}
        for _, m in ipairs(box) do
            local h = handlers[m.kind]
            if m.ep ~= epoch then drops = drops + 1
            elseif h then run(h.name, h.fn, m.rec, m.frame) end
        end
    end
    if #jobs > 0 then
        local list, i, n = jobs, 1, #jobs
        jobs = {}
        while i <= n do
            run_item(list[i])
            i = i + 1
            if clock() - now > cfg.budget_s or (cfg.budget_units and units >= cfg.budget_units) then break end
        end
        if i <= n then
            local rest = {}
            for k = i, n do rest[#rest + 1] = list[k] end
            for _, j in ipairs(jobs) do rest[#rest + 1] = j end     -- queued meanwhile: after the carried ones
            jobs = rest
        end
    end
    if #timers > 0 then
        local real, due, keep = clock(), nil, nil
        for _, t in ipairs(timers) do
            if (t.game and S.game_time or real) >= t.at then due = due or {} due[#due + 1] = t
            else keep = keep or {} keep[#keep + 1] = t end
        end
        if due then
            timers = keep or {}
            for _, t in ipairs(due) do run_item(t) end
        end
    end
    for _, name in ipairs(ticker_order) do
        local fn = tickers[name]
        if fn then
            local t0 = clock()
            run(name, fn)
            by[name] = (by[name] or 0) + (clock() - t0)
        end
    end
    local d = clock() - now
    cost.late, cost.late_sum = d, cost.late_sum + d
    if d > cost.late_max then cost.late_max = d end
    cost.units = cost.units + units
    if units > cost.units_max then cost.units_max = units end
end

-- The render phase: writers in order (UE4SS: right after S.on_late in the same tick)
function S.on_render()
    S.phase = 'render'
    S.pass = S.pass + 1
    if not S.in_game then return end
    local c0 = clock()
    for _, name in ipairs(writer_order) do
        local fn = writers[name]
        if fn then
            local t0 = clock()
            run(name, fn)
            rby[name] = (rby[name] or 0) + (clock() - t0)
        end
    end
    local d = clock() - c0
    cost.render, cost.render_sum, cost.n = d, cost.render_sum + d, cost.n + 1
    if d > cost.render_max then cost.render_max = d end
end

-- Average and peak cost since the last call, in microseconds, and the window resets. by_us: the six dearest tickers
-- and writers (a writer's name ends in '/r'). REFramework's clock steps 1 ms: averages over thousands of frames are
-- right, single frames are not; assert counted units in tests, not seconds.
function S.take_cost()
    local n = math.max(1, cost.n)
    local list = {}
    for name, sec in pairs(by) do list[#list + 1] = { name = name, sec = sec } end
    for name, sec in pairs(rby) do list[#list + 1] = { name = name .. '/r', sec = sec } end
    table.sort(list, function(a, b) return a.sec > b.sec or (a.sec == b.sec and a.name < b.name) end)
    local by_us = nil
    for i = 1, math.min(6, #list) do
        local us = math.floor(list[i].sec / n * 1e6 + 0.5)
        if us > 0 then by_us = by_us or {} by_us[list[i].name] = us end
    end
    local r = { late_avg_us = math.floor(cost.late_sum / n * 1e6), late_max_us = math.floor(cost.late_max * 1e6),
        render_avg_us = math.floor(cost.render_sum / n * 1e6), render_max_us = math.floor(cost.render_max * 1e6),
        frames = cost.n, units = cost.units, units_max = cost.units_max, by_us = by_us,
        teardown_errors = cost.teardown_errors > 0 and cost.teardown_errors or nil }
    r.total_avg_us = r.late_avg_us + r.render_avg_us
    cost, by, rby = new_cost(), {}, {}
    return r
end

function S.status()
    local nj, ni, nt = S.pending()
    local offl = {}
    for k in pairs(off) do offl[#offl + 1] = k end
    table.sort(offl)
    return { frame = S.frame, pass = S.pass, in_game = S.in_game, paused = S.paused, epoch = epoch, drops = drops,
        queue = { jobs = nj, inbox = ni, timers = nt }, errors = next(errors) and errors or nil,
        off = offl[1] and offl or nil }
end
-- A map change: pending work goes (a new epoch); breaker windows and counters stay
function S.reset(reason) S.bump_epoch(reason or 'reset') end
-- Unload: engine-free; registrations go too
function S.shutdown(reason)
    if not A then return end
    S.bump_epoch(reason or 'shutdown')
    tickers, ticker_order, writers, writer_order, handlers = {}, {}, {}, {}, {}
end
function S.handoff() return { epoch = epoch, frame = S.frame } end

return S
