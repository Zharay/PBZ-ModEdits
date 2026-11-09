-- status: worked SWZC+DD2 (the governor ran offline only; untested per preset in game) origin: kb:runtime-safety-perf#per-preset-slices-work-unit-governor
-- gov.lua: the frame watch and the work-unit governor. A quiet scene costs nothing; a busy one stays inside its slice.
-- FRAME WATCH (session level, sticky): G.watch_kill() after a REAL kill opens (or extends) a wall-clock window of
--   opts.watch_s 4 s; inside it opts.hitch_n 2 frames over opts.hitch_ms 250 ms raise the degrade level by one,
--   once per window (at most G.MAX_WATCH 2), and log gov_level. Frames while paused, while the scheduler gate is
--   closed (loads, title), the first frame after it reopens and opts.loading() frames never count: counting a save
--   load's frames as gore lag dropped the level twice with no kill ("feels like there's no dismemberment").
-- LAYERS: G.layer(name, { min_level, hero }) declares optional output; G.allows(name) is false from watch level
--   min_level on, or while the governor's level drops it (opts.drop order). A hero layer (the kill's own cut, the
--   opening gush: the signature moment) is allowed at every level. Delayed steps call G.allows again when they run.
-- GOVERNOR (per frame): units = calls x1 + rays x10 + vm x0.02 (1 unit is about 1 us in the harness), counted at the
--   bridge. The slice is G.SLICES[base preset] units (DD2 liquid: 1.0/0.6/0.3/0.1 ms from maximum to light). Features
--   report demand every frame, dropped or not (G.want(item, full, reduced); 'keep' for work that never drops), so the
--   governor knows when it fits again. Level L drops opts.drop[1..L]; it rises the frame after the demand did not fit,
--   never past the point where dropping more saves nothing (undroppable work once pushed the level to 4 and dropped
--   every look for 4 s for nothing), and falls one step per opts.calm_s 1 s of game time. Caps: G.take (per frame),
--   G.acquire / G.release (live), G.take_rate (a bucket refilled per second, full after a quiet second); a partial
--   grant must be released when unused.
-- The governor frame starts lazily on the first call of a new sched frame (G.begin; a second call does nothing).
-- API (stable): G.init(A, opts) watch_kill frame([now]) layer allows level gov_level begin want keep spend units room
--   take acquire release take_rate reset shutdown status.
-- Evidence: [worked SWZC] lib/gore.lua perf watch and hitch; [worked DD2 offline] liquid/governor.lua;
-- kb:runtime-safety-perf#frame-watch-with-degrade-levels-and-burst-budgets; kb:blood-fx principle 27
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')
local S = require(BASE .. 'sched')
local C = require(BASE .. 'config')

local G = { MAX_WATCH = 2 }
-- One slice per C.PRESET_ORDER id (C.base_preset returns only these ids; the old full and lite resolve to them)
G.SLICES = { maximum = 1000, balanced = 600, restrained = 300, light = 100 }
G.UNITS = { call = 1, ray = 10, vm = 0.02 }

local A, cfg = nil, nil
local layers, drop, rank = {}, {}, {}
local wlevel, watch, last_win = 0, nil, nil
local g = nil

local function new_gov()
    return { frame = -1, t = nil, slice = 0, lvl = 0, hold = 0, spent = 0, calls = 0, full = {}, red = {},
        last_full = {}, last_red = {}, keep = 0, last_keep = 0, per = {}, live = {}, bucket = {}, filled = false,
        by = {}, raised = 0, over = 0 }
end

local function real() return A.clock.real() end

-- opts: watch_s 4, hitch_ms 250, hitch_n 2, loading() -> bool, drop { item, ... } (first dropped first), slices
-- { preset = units }, calm_s 1, ticker (false: the adapter calls G.frame), caps { per_frame = { name = n },
-- live = { name = n }, rate = { name = per_s } }
function G.init(adapter, opts)
    opts = opts or {}
    A = adapter
    cfg = { watch_s = opts.watch_s or 4, hitch_ms = opts.hitch_ms or 250, hitch_n = opts.hitch_n or 2,
        loading = opts.loading, calm_s = opts.calm_s or 1, slices = opts.slices or G.SLICES,
        caps = opts.caps or {} }
    local caps = cfg.caps
    caps.per_frame, caps.live, caps.rate = caps.per_frame or {}, caps.live or {}, caps.rate or {}
    layers, drop, rank = {}, {}, {}
    for i, it in ipairs(opts.drop or {}) do drop[i], rank[it] = it, i end
    wlevel, watch, last_win = 0, nil, nil
    g = new_gov()
    if opts.ticker ~= false then S.ticker('gov_watch', function() G.frame() end) end
    return true
end

-- ---------- frame watch ----------
local function set_watch(lvl, why)
    local from = wlevel
    if lvl == from then return end
    wlevel = lvl
    LOG.info('gov_level', { level = lvl, from = from, why = why, kind = 'watch' })
end

-- A real kill (never a corpse re-apply after a load): the window opens or runs watch_s longer
function G.watch_kill(now)
    if not A then return end
    now = now or real()
    if watch then
        watch.t_end, watch.kills = now + cfg.watch_s, watch.kills + 1
    else
        watch = { t0 = now, t_end = now + cfg.watch_s, last = nil, kills = 1, frames = 0, long = 0, skipped = 0,
            max = 0 }
    end
end

-- Once a frame (a sched ticker or the adapter's frame callback); nothing to do while no window is open
function G.frame(now)
    local w = watch
    if not w then return end
    now = now or real()
    local skip = S.paused or not S.in_game or S.out_frame >= S.frame - 1
    if not skip and cfg.loading then
        local ok, l = pcall(cfg.loading)
        skip = ok and l == true
    end
    local dt = w.last and (now - w.last) or 0
    w.last = now
    if skip then
        w.skipped = w.skipped + 1
    elseif dt > 0 then
        w.frames = w.frames + 1
        if dt > w.max then w.max = dt end
        if dt * 1000 > cfg.hitch_ms then
            w.long = w.long + 1
            if w.long == cfg.hitch_n and wlevel < G.MAX_WATCH then set_watch(wlevel + 1, 'hitch') end
        end
    end
    if now >= w.t_end then
        last_win = { frames = w.frames, long = w.long, skipped = w.skipped, kills = w.kills,
            max_ms = math.floor(w.max * 1000 + 0.5) }
        watch = nil
    end
end

-- ---------- layers ----------
function G.layer(name, opts)
    opts = opts or {}
    layers[name] = { min_level = opts.min_level or 1, hero = opts.hero == true }
end

function G.level() return wlevel end

-- ---------- the governor ----------
local function slice_now()
    local ok, p = pcall(C.base_preset)
    local u = ok and cfg.slices[p]
    if type(u) ~= 'number' then u = cfg.slices.maximum or G.SLICES.maximum end
    return u
end

-- The last frame's demand at level L: dropped items at their reduced cost, the others in full, kept work always
local function demand(L)
    local d = g.last_keep
    for i, it in ipairs(drop) do
        if i <= L then d = d + (g.last_red[it] or 0) else d = d + (g.last_full[it] or 0) end
    end
    return d
end

-- Start a governor frame (frame: sched frame, t: game time). Called lazily by every governor call; idempotent.
function G.begin(frame, t)
    frame, t = frame or S.frame, t or S.game_time
    if g.frame == frame then return false end
    local gap = g.frame ~= frame - 1                     -- the counted demand belongs to an older frame
    local dt = g.t and (t - g.t) or 1
    if dt < 0 then dt = 0 elseif dt > 1 then dt = 1 end
    if g.spent > g.slice and g.frame >= 0 then g.over = g.over + 1 end
    g.frame, g.t, g.slice = frame, t, slice_now()
    for _, it in ipairs(drop) do
        if gap then g.last_full[it], g.last_red[it] = 0, 0
        else g.last_full[it], g.last_red[it] = g.full[it] or 0, g.red[it] or 0 end
        g.full[it], g.red[it] = 0, 0
    end
    if gap then g.last_keep = 0 else g.last_keep = g.keep end
    g.keep = 0
    -- the smallest level that fits, or past which dropping more saves nothing
    local want, least = 0, demand(#drop) + 1e-9
    while want < #drop do
        local d = demand(want)
        if d <= g.slice or d <= least then break end
        want = want + 1
    end
    if want > g.lvl then
        local from = g.lvl
        g.lvl, g.hold, g.raised = want, t + cfg.calm_s, g.raised + 1
        if LOG.every('gov_level_rise', 5) then
            LOG.info('gov_level', { level = want, from = from, why = 'over_slice', kind = 'gov', slice = g.slice })
        end
    elseif want < g.lvl then
        while g.lvl > want and t >= g.hold do g.lvl, g.hold = g.lvl - 1, g.hold + cfg.calm_s end
    elseif want > 0 then
        g.hold = math.max(g.hold, t + cfg.calm_s)       -- still needed: the calm period starts when it is not
    end
    g.spent, g.calls, g.per = 0, 0, {}
    for k, rate in pairs(cfg.caps.rate) do
        local b = g.bucket[k]
        if g.filled and b then g.bucket[k] = math.min(rate, b + rate * dt) else g.bucket[k] = rate end
    end
    g.filled = true
    return true
end

local function ensure() if g.frame ~= S.frame then G.begin() end end

function G.gov_level() ensure() return g.lvl end

-- Is the layer (or drop item) allowed now? Hero layers always; else not from its watch level on, nor while dropped
function G.allows(name)
    local l = layers[name]
    if l and l.hero then return true end
    if l and wlevel >= l.min_level then return false end
    local r = rank[name]
    if r then
        ensure()
        return r > g.lvl
    end
    return true
end

-- Demand of this frame: full units and its cost at the dropped level; item 'keep' never drops
function G.want(item, full, reduced)
    ensure()
    if item == 'keep' then
        g.keep = g.keep + (full or 0)
        return
    end
    if not rank[item] then return end
    g.full[item] = (g.full[item] or 0) + (full or 0)
    g.red[item] = (g.red[item] or 0) + (reduced or 0)
end

function G.units(calls, vm, rays)
    return (calls or 0) * G.UNITS.call + (vm or 0) * G.UNITS.vm + (rays or 0) * G.UNITS.ray
end

-- Work done this frame by a feature (calls, VM instructions, rays); returns the units
function G.spend(name, calls, vm, rays)
    ensure()
    local u = G.units(calls, vm, rays)
    g.spent, g.calls = g.spent + u, g.calls + (calls or 0)
    g.by[name] = (g.by[name] or 0) + u
    return u
end

-- Spent and wanted as kept work (never dropped)
function G.keep(name, calls, vm, rays)
    local u = G.spend(name, calls, vm, rays)
    g.keep = g.keep + u
    return u
end

function G.room()
    ensure()
    return g.slice - g.spent
end

local function grant(used_t, caps, cap, n)
    local max = caps[cap]
    if max == nil then return 0 end
    local used = used_t[cap] or 0
    local got = math.max(0, math.min(n or 1, max - used))
    used_t[cap] = used + got
    return got
end

-- Per-frame caps: up to n granted from what is left this frame
function G.take(cap, n)
    ensure()
    return grant(g.per, cfg.caps.per_frame, cap, n)
end
-- Live caps: held until released
function G.acquire(cap, n) return grant(g.live, cfg.caps.live, cap, n) end
function G.release(cap, n)
    local used = g.live[cap]
    if used then g.live[cap] = math.max(0, used - (n or 1)) end
end
-- Per-second caps: whole tokens from the bucket
function G.take_rate(cap, n)
    ensure()
    local b = g.bucket[cap]
    if b == nil then return 0 end
    local got = math.max(0, math.min(n or 1, math.floor(b)))
    g.bucket[cap] = b - got
    return got
end

-- ---------- lifecycle ----------
-- A map change: the open window and the governor's frame state go; the sticky watch level stays for the session
function G.reset()
    watch = nil
    local live = g and g.live or {}
    g = new_gov()
    g.live = live
end

function G.shutdown()
    watch, g = nil, new_gov()
end

function G.status()
    if not g then return nil end
    local by = nil
    for name, u in pairs(g.by) do
        if u > 0 then by = by or {} by[name] = math.floor(u + 0.5) end
    end
    return { level = wlevel, gov_level = g.lvl, slice = g.slice, spent = math.floor(g.spent + 0.5), over = g.over,
        raised = g.raised, watch = watch and { kills = watch.kills, long = watch.long } or nil, last_window = last_win,
        by = by }
end

return G
