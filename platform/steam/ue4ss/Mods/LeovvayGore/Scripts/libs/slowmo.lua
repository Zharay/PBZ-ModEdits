-- slowmo.lua: the one owner of the global time scale. Engine-free: every engine read and write goes through the
-- adapter A given to SM.new, so the same arbiter runs on UE (SetGlobalTimeDilation), RE Engine
-- (via.Application.set_GlobalSpeed) or anything else with one global speed value. Lint L007 lets only this module
-- write the time scale.
-- status: worked origin: kb:audio-slowmo-feel#reframework-slow-motion-arbiter-that-cannot-get-stuck-via-application-set-globalspeed
-- also: kb:audio-slowmo-feel#ue4ss-kill-slow-motion-setglobaltimedilation-real-time-steps-restore-on-every-path
-- fixtures: DD2 (stuck-forever cases 1-13 of the 0.2.0 fix), SWZC (hitch, hot reload, step errors); tests/test_slowmo.lua
--
-- Rules (each one fixed a shipped bug; Nexus 0.1.3: "the slow-motion effect gets stuck permanently"):
-- * start only when the value reads 1.0 (within eps) and a ticker runs; never over another writer's value
-- * write only while the read-back is our last write (eps; own values within exact); anyone else's value: let go
-- * time in real seconds (A.clock), never game time; a run never plans past t0 + max_run_s, extensions included
-- * restore on every exit: timer, switch off, pause, gate, ownership loss, write error, unreadable value, watchdog
-- * guard() from every other callback list ends a run whose tick stopped for stale_s, and any run guard_s after
--   its first start (a hitch shift never moves that guard); guard_pre() (a list that runs ahead of the tick in the
--   same frame) acts only after the tick missed a whole frame
-- * a failed 1.0 is retried while the value still reads ours, backing off restore_gap -> restore_gap_max; after
--   stuck_tries A.last_resort() once (UE: the 'slomo 1' console command) and slowmo_stuck
-- * a marker (A.mark_put) is live while a run may hold the value and records every write as `last` (the start,
--   each ramp step; `tried` a write that reported a failure, it may have landed); the next Lua state of the same
--   launch (launch id within 2, marker age <= 60 s) puts 1.0 back only when the value is exactly `last` or `tried`
--   (within exact): never a range, never the base speed alone, so another mod's 0.3 over our 0.28 stays
--   (slowmo_repair; DESIGN C9 "0.28 is not an owner id")
-- * a leftover of ours (our exact value back after the value had moved off it, held hold_s) gets 1.0, at most
--   left_max times; a writer that never moved off our value is never fought
-- * a nil get() is unreadable: never 1.0 and never another owner's value; the run keeps its schedule (no write while
--   unreadable) and the finish writes 1.0 when a read shows our last write (or the one we tried; eps, the same
--   ownership test as each step, so a value the step owned is never left slow) or after two unreadable reads
-- * settings are clamped where they are read: speed 0.05-1, seconds 0.05-max_run_s
-- Adapter A (functions unless noted; a raising call reads as a failure):
--   get() -> number | nil        set(v) -> true | false/nil, err      clock() -> real seconds (monotonic, per process)
--   mark_get() -> table | nil    mark_put(t) -> true                  launch_id: number | function -> number
--   enabled() -> bool            gates() -> nil | reason ('cutscene', 'win_finish'...)   paused() -> bool
--   log(ev, rec, level)          optional: sentinel(name, fn) -> ok, err (first write; default pcall),
--   budget_s() -> nil | s (another mod's cap; 0: none), last_resort(), world() -> name | nil (UE: a new world starts
--   at 1.0: drop, no write), has_ticker() -> bool (default true), settings() -> {speed, seconds, cooldown, chain_s}
-- Use: local S = SM.new(A, {eps = 0.01}) (UE float compare) ; SM.decide(o, env) (pure trigger gate), then
-- S.request(reason, prio, opts) from the gameplay thread; S.tick() from the main ticker; S.guard() from every other list; S.guard_pre() from a pre list;
-- S.shutdown({engine = false}) when no engine call is allowed (UE4SS OnUnload): writes nothing, keeps the marker.
-- Unity (UNPROVEN, kb:audio-slowmo-feel): Time.timeScale plus Time.fixedDeltaTime = base * scale through the adapter.
-- Evidence: [worked DD2] lab L6 0.3 for 0.36/0.61 s restored, 7/7 slowmo_end after=1.0 in the author's launches;
-- anti-stuck paths [worked DD2 offline only]; [worked SWZC] 39 slowmo starts, 145 offline checks.

local SM = {}

-- speed 0.28: deliberately off the 0.3 of other slow-motion mods on the same field (DESIGN D8; spec M0 D15)
local DEFAULTS = {
    speed = 0.28, seconds = 0.5, cooldown = 8.0, chain_s = 0,
    eps = 1e-3, exact = 1e-6, ramp_in = 0.0, ramp_out = 0.12, step_s = 1 / 30,
    max_run_s = 2.5, guard_s = 3.0, stale_s = 0.5, overdue_s = 2.0,
    restore_gap = 0.5, restore_gap_max = 2.0, stuck_tries = 6,
    late_s = 0.1, late_max_s = 0.5, max_vals = 64,
    left_s = 60, hold_s = 5.0, left_max = 3, left_every = 0.2,
    mark_s = 60, mark_launch = 2, repair_reads = 30, world_tries = 30,
}
SM.DEFAULTS = DEFAULTS

-- ---------------------------------------------------------------------------------------------------------------
-- Pure helpers (no adapter)
-- ---------------------------------------------------------------------------------------------------------------
-- A setting as a float in [lo, hi]; def when it is no number (NaN too)
function SM.num(x, lo, hi, def)
    x = tonumber(x)
    if x == nil or x ~= x then x = def end
    return math.max(lo, math.min(hi, x)) + 0.0
end
local num = SM.num

local function ease(x)
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    return x * x * (3 - 2 * x)
end

-- s = {t0, scale, ri, ro, hold_until} (real s): the value at now and whether the run is over
function SM.value_at(s, now)
    local dt = now - s.t0
    if s.ri > 0 and dt < s.ri then return 1.0 + (s.scale - 1.0) * ease(dt / s.ri), false end
    if now < s.hold_until then return s.scale, false end
    if s.ro > 0 and now < s.hold_until + s.ro then
        return s.scale + (1.0 - s.scale) * ease((now - s.hold_until) / s.ro), false
    end
    return 1.0, true
end

-- duration (ramps included) and the ramps clamped into it: d, ri, ro
function SM.timing(seconds, ramp_in, ramp_out, max_run_s)
    local d = num(seconds, 0.05, max_run_s or DEFAULTS.max_run_s, DEFAULTS.seconds)
    local ri = num(ramp_in, 0, d / 2, 0)
    local ro = num(ramp_out, 0, d - ri, 0)
    return d, ri, ro
end

-- Real seconds until game_s of game time has passed from now under schedule s (nil: 1:1). A game-time delay
-- scheduled while slow motion runs (a pool that should appear 0.8 s after the fall) goes through this.
function SM.stretch_s(game_s, now, s)
    game_s = math.max(0, tonumber(game_s) or 0)
    if not s or game_s <= 0 then return game_s end
    local t, acc, dt = now, 0, 0.005
    local stop = s.hold_until + s.ro
    while acc < game_s and t < stop do
        acc = acc + SM.value_at(s, t) * dt
        t = t + dt
    end
    if acc < game_s then t = t + (game_s - acc) end
    return t - now
end

-- Pure trigger gate, called before S.request (SWZC decide; cooldown and extension stay in the arbiter).
-- o = {on, why = {words} | nil, need_burst (true: something must have flown), chance, max_cam_dist, min_cam_dot};
-- env = {why, burst, active (S.active()), rnd (function -> [0, 1)), cam = {dist, dot} | function -> that, force}.
-- A running run skips the chance roll (the chained kill only extends it) but never the camera check: a kill that
-- extends a beat passes the same far and off_screen gate as one that starts it (DESIGN C9, R2-B11). force skips all.
-- Returns true, or false, the skip reason ('trigger_off' 'why' 'no_burst' 'chance' 'far' 'off_screen') and a detail.
function SM.decide(o, env)
    o, env = o or {}, env or {}
    if not env.force then
        if not o.on then return false, "trigger_off" end
        if type(o.why) == "table" then
            local hit = false
            for _, w in ipairs(o.why) do if w == env.why then hit = true break end end
            if not hit then return false, "why", env.why end
        end
        if o.need_burst == true and not env.burst then return false, "no_burst" end
    end
    if env.force then return true end
    local p = tonumber(o.chance) or 1
    if p < 1 and not env.active then
        local okr, r = false, nil
        if type(env.rnd) == "function" then okr, r = pcall(env.rnd) end
        if not (okr and type(r) == "number" and r < p) then return false, "chance" end
    end
    local cam = env.cam
    if type(cam) == "function" then
        local okc, c = pcall(cam)
        cam = okc and c or nil
    end
    if type(cam) == "table" then
        local far, dist, dot = tonumber(o.max_cam_dist) or 0, tonumber(cam.dist), tonumber(cam.dot)
        if dist and far > 0 and dist > far then return false, "far", math.floor(dist + 0.5) end
        if dot and dot < (tonumber(o.min_cam_dot) or -1) then return false, "off_screen", dot end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The arbiter
-- ---------------------------------------------------------------------------------------------------------------
function SM.new(A, opts)
    assert(type(A) == "table" and type(A.get) == "function" and type(A.set) == "function"
        and type(A.clock) == "function", "slowmo.new: adapter needs get, set and clock")
    local K = {}
    for k, v in pairs(DEFAULTS) do K[k] = v end
    for k, v in pairs(opts or {}) do K[k] = v end
    local S = {}
    local active, restore, left, pend = nil, nil, nil, nil
    local cool_until, last_tick, pre_since = -1e9, nil, 0
    local marked, busy, off_seen = false, nil, false
    local stats = { runs = 0, extended = 0, refused = {}, repairs = 0, reclaims = 0, stuck = 0, late = 0 }

    local function call(fn, ...)
        if type(fn) ~= "function" then return false, "missing" end
        return pcall(fn, ...)
    end
    local function log(ev, rec, level) if A.log then pcall(A.log, ev, rec, level or "info") end end
    local function now_s() return A.clock() end
    local function get()
        local ok, v = pcall(A.get)
        if ok and type(v) == "number" and v == v then return v end
        return nil
    end
    -- nil when the write took, else the error text
    local function set(v)
        local ok, r, e = pcall(A.set, v)
        if not ok then return tostring(r) end
        if r == false then return tostring(e or "set failed") end
        return nil
    end
    local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < K.eps end
    local function ms(x) return math.floor(x * 1000 + 0.5) / 1000 end
    local function launch()
        local l = A.launch_id
        if type(l) == "function" then local ok, v = pcall(l) l = ok and v or nil end
        return tonumber(l)
    end
    local function enabled()
        if A.enabled == nil then return true end
        local ok, v = call(A.enabled)
        return ok and v == true
    end
    local function paused() local ok, v = call(A.paused) return ok and v == true end
    local function world() local ok, v = call(A.world) if ok then return v end return nil end
    local function settings()
        local ok, t = call(A.settings)
        return (ok and type(t) == "table") and t or {}
    end
    -- one of our written values, exactly (as read back), never 1.0
    local function in_vals(cur, vals)
        if type(cur) ~= "number" or cur >= 1 - K.eps or not vals then return false end
        for i = 1, #vals do if math.abs(cur - vals[i]) < K.exact then return true end end
        return false
    end
    local function add_val(a, s) if #a.vals < K.max_vals then a.vals[#a.vals + 1] = s end end
    local function refuse(why)
        local k = tostring(why):match("^[%a_]+") or tostring(why)
        stats.refused[k] = (stats.refused[k] or 0) + 1
        return false, why
    end

    -- the marker: live from just before a run's first write until the value is no longer ours to put back. Written
    -- again after every write (the start, each ramp step, a failed finish), so `last` is always the value our latest
    -- write left and `tried` one that reported a failure (it may have landed). A.mark_put is a shared variable on
    -- UE4SS (no file write), cheap at the few writes of a run.
    local function mark(a)
        local ok, w = call(A.mark_put, { live = true, launch_id = launch(), speed = a.speed, t0 = a.t0, world = a.world,
            last = a.last, tried = a.tried })
        if ok and w ~= false then marked = true end  -- a failed put keeps an earlier live marker ours to clear
    end
    local function unmark()
        if not marked then return end
        marked = false
        call(A.mark_put, { live = false, launch_id = launch(), last = 1.0 })
    end
    -- the previous Lua state's marker when it is live, of this launch and recent
    local function read_mark()
        local ok, m = call(A.mark_get)
        if not ok or type(m) ~= "table" or m.live ~= true or type(m.speed) ~= "number" or type(m.t0) ~= "number" then
            return nil
        end
        local id = launch()
        if type(m.launch_id) ~= "number" or type(id) ~= "number" or math.abs(m.launch_id - id) > K.mark_launch then
            return nil
        end
        local age = now_s() - m.t0
        if age < -1 or age > K.mark_s then return nil end
        return m
    end

    -- End the run. 1.0 while the value is still ours (our last write, a write that reported a failure: it may have
    -- landed, or unreadable twice: no proof of another owner); else yield to whoever changed it. A failed 1.0 is
    -- retried (retry_restore). The run's values stay known for the leftover check (orphan).
    local function finish(forced, why, err)
        local a = active
        if not a then return end
        active = nil
        local cur = get()
        if cur == nil then cur = get() end
        local ours = cur == nil or near(cur, a.last) or near(cur, a.tried)
        local e = nil
        if ours then e = set(1.0) end
        local now = now_s()
        if e then
            restore = { val = cur, vals = a.vals, tries = 0, at = now + K.restore_gap }
            mark(a)                           -- the 1.0 failed: the marker keeps the value we left for the next state
        end
        local after = get()
        left = { vals = a.vals, until_c = now + K.left_s, away = not in_vals(after, a.vals), hold = nil, n = 0, next = 0 }
        if not e then unmark() end
        cool_until = now + num(settings().cooldown, 0, 1e9, K.cooldown)
        log("slowmo_end", { reason = a.reason, prio = a.prio, real_s = ms(now - a.g0), found = cur, after = after,
            restored = after ~= nil and near(after, 1.0),          -- TC-LAB-01 L6 reads after; this is the same check
            forced = forced == true or nil, why = why, yielded = (not ours) or nil, err = err or e, late_ms = a.late_ms })
    end
    -- Drop the run with no engine call (a new world starts at 1.0; a reset)
    local function drop(why)
        local a = active
        active, restore, left = nil, nil, nil
        unmark()
        if a then log("slowmo_end", { reason = a.reason, prio = a.prio, why = why, dropped = true }) end
    end

    -- The failed 1.0 again while the value reads the one we left or one of the run's (1.0 or anyone else's value
    -- ends it; an unreadable one is no proof of another owner), backing off restore_gap -> restore_gap_max.
    local function retry_restore(now, force)
        local r = restore
        if now < r.at and not force then return end
        local cur = get()
        if cur ~= nil and not (near(cur, r.val) or in_vals(cur, r.vals)) then
            restore = nil
            unmark()
            return
        end
        local e = set(1.0)
        r.tries = r.tries + 1
        r.at = now + math.min(K.restore_gap_max, K.restore_gap * 2 ^ (r.tries - 1))
        if e == nil then
            restore = nil
            unmark()
            log("slowmo_restore", { ok = true, tries = r.tries })
        elseif r.tries == 3 then
            log("slowmo_restore", { ok = false, err = e, tries = r.tries }, "warn")
        elseif r.tries == K.stuck_tries then
            stats.stuck = stats.stuck + 1
            local ok = call(A.last_resort)
            log("slowmo_stuck", { err = e, tries = r.tries, last_resort = ok or nil, found = cur }, "error")
        end
    end

    -- 1.0 over a leftover value of ours (left.vals)
    local function reclaim(cur, why, held)
        local l = left
        local e = set(1.0)
        l.n, l.hold, l.away = l.n + 1, nil, false
        if l.n >= K.left_max then left = nil end
        stats.reclaims = stats.reclaims + 1
        log("slowmo_reclaim", { found = cur, why = why, held_s = held and ms(held) or nil, n = l.n, err = e })
    end
    -- A value of the last run back after the value had moved off it (another writer put back what it found inside
    -- our run) and held hold_s: our leftover. A writer that keeps our value every frame never moves off it after
    -- that 1.0 and is left alone.
    local function orphan(now)
        local l = left
        if now < l.next then return end
        l.next = now + K.left_every
        if now > l.until_c and not l.hold then left = nil return end
        local cur = get()
        if cur == nil then return end
        if not in_vals(cur, l.vals) then l.away, l.hold = true, nil return end
        if not l.away then return end
        l.hold = l.hold or now
        if now - l.hold >= K.hold_s then reclaim(cur, "orphan", now - l.hold) end
    end

    -- The previous Lua state ended while its run held the value: only the exact value its latest write left (the
    -- marker's `last`, a ramp value included, or `tried`) is that run's: 1.0. Any other value, even one between the
    -- run's speed and 1.0 (another mod's 0.3 over our 0.28), another launch or another world: left alone.
    local function marker_vals(m)
        local out = {}
        if type(m.last) == "number" then out[#out + 1] = m.last end
        if type(m.tried) == "number" then out[#out + 1] = m.tried end
        return out
    end
    local function repair(now)
        local m = pend
        pend = nil
        local cur = get()
        local w = A.world and world() or nil
        if (cur == nil or (A.world and w == nil)) and (m.reads or 0) < K.repair_reads then
            m.reads = (m.reads or 0) + 1
            pend = m
            return
        end
        local same_world = not (A.world and m.world ~= nil and w ~= m.world)
        local mv = marker_vals(m)
        local hit = same_world and in_vals(cur, mv)
        local e = nil
        if hit then
            e = set(1.0)
            stats.repairs = stats.repairs + 1
            if e then restore = { val = cur, vals = mv, tries = 0, at = now + K.restore_gap } end
        end
        if not e then unmark() end
        log("slowmo_repair", { found = cur, speed = m.speed, last = m.last, tried = m.tried, age_s = ms(now - m.t0),
            repaired = (hit and not e) or nil, other_world = (not same_world) or nil, err = e })
    end

    -- The feature switched off: a run ends at once, a leftover of ours goes once per switch-off
    local function check_off()
        if enabled() then off_seen = false return end
        if active then return finish(true, "off") end
        if off_seen or not left then return end
        off_seen = true
        local cur = get()
        if in_vals(cur, left.vals) then reclaim(cur, "off") end
    end

    local function busy_refuse(cur)
        if cur ~= nil and not near(cur, busy) then
            busy = cur
            log("slowmo_busy", { found = cur, ours = in_vals(cur, left and left.vals) or nil })
        end
        return refuse("value:" .. tostring(cur))
    end

    -- Ask for slow motion. prio default 1; o.speed / o.seconds / o.ramp_in / o.ramp_out override the settings.
    -- Returns true when it started, else false and the reason ('extended', 'active', 'cooldown', 'paused', a gate...).
    function S.request(reason, prio, o)
        prio, o = tonumber(prio) or 1, o or {}
        local now = now_s()
        if pend then repair(now) end
        if not enabled() then return refuse("off") end
        local c = settings()
        local dur = num(o.seconds or c.seconds, 0.05, K.max_run_s, K.seconds)
        local okb, cap = call(A.budget_s)
        if okb and cap ~= nil then
            cap = num(cap, 0, K.max_run_s, 0)
            if cap <= 0 then return refuse("budget") end
            dur = math.min(dur, cap)
        end
        local a = active
        if a then
            local chain = num(c.chain_s or K.chain_s, 0, K.max_run_s, 0)
            if prio <= a.prio and chain <= 0 then return refuse("active") end
            local want = prio > a.prio and dur or chain
            local stop = a.hold_until + a.ro
            if stop >= a.max_end - 1e-6 then return refuse("max_total") end
            stop = math.min(math.max(stop, now + want), a.max_end)
            a.hold_until = stop - a.ro
            if prio > a.prio then a.prio, a.reason = prio, reason end
            stats.extended = stats.extended + 1
            return false, "extended"
        end
        if now < cool_until then return refuse("cooldown") end
        if paused() then return refuse("paused") end
        local okg, gate = call(A.gates)
        if okg and gate then return refuse(tostring(gate)) end
        if A.has_ticker then
            local okt, t = call(A.has_ticker)
            if not (okt and t) then return refuse("no_ticker") end
        end
        local w = nil
        if A.world then
            w = world()
            if w == nil then return refuse("no_world") end
        end
        local cur = get()
        if not near(cur, 1.0) then return busy_refuse(cur) end
        busy = nil
        local speed = num(o.speed or c.speed, 0.05, 1.0, K.speed)
        if speed >= 1 - K.eps then return refuse("speed_one") end
        local d, ri, ro = SM.timing(dur, o.ramp_in or c.ramp_in or K.ramp_in, o.ramp_out or c.ramp_out or K.ramp_out,
            K.max_run_s)
        a = { speed = speed, scale = speed, t0 = now, g0 = now, ri = ri, ro = ro, hold_until = now + d - ro,
            max_end = now + K.max_run_s, last = 1.0, tried = nil, vals = {}, prio = prio, reason = reason, world = w }
        local v0 = SM.value_at(a, now)
        if v0 < 1 - K.eps then a.tried = v0 end
        mark(a)                                   -- live before the first write; `tried` is the value it attempts
        if v0 < 1 - K.eps then
            local ok, err
            if A.sentinel then
                local okc, r1, r2 = pcall(A.sentinel, "time_scale", function()
                    local e = set(v0)
                    if e then error(e, 0) end
                    return true
                end)
                ok, err = okc and r1 ~= false, okc and r2 or r1
            else
                err = set(v0)
                ok = err == nil
            end
            -- read back: the engine may clamp the value, and a write that reported a failure may have landed
            local g = get()
            if near(g, 1.0) then
                unmark()
                return refuse(ok and "no_effect" or ("write_error:" .. tostring(err)))
            end
            if not ok then
                active = a
                a.last = v0
                finish(true, "write_error", tostring(err))
                return refuse("write_error:" .. tostring(err))
            end
            a.last, a.tried = g or v0, nil
            add_val(a, a.last)
            mark(a)                               -- the marker's `last`: the value read back after the first write
        end
        active = a
        restore, left = nil, nil              -- the value read 1.0: nothing of an earlier run is left to put back
        stats.runs = stats.runs + 1
        log("slowmo_start", { reason = reason, prio = prio, speed = speed, seconds = d })
        return true
    end

    -- Cheap pre-check, no engine call: would request refuse at once? (skip a costly trigger scan when it would)
    function S.can_request(prio)
        prio = tonumber(prio) or 1
        if not enabled() then return false end
        local okb, cap = call(A.budget_s)
        if okb and cap ~= nil and num(cap, 0, K.max_run_s, 0) <= 0 then return false end
        if active then return prio > active.prio or num(settings().chain_s or K.chain_s, 0, K.max_run_s, 0) > 0 end
        return now_s() >= cool_until and not paused()
    end

    -- One step of a run: world, read-back ownership, the first-step hitch shift, pause, gates, the schedule
    local function step(a, now)
        if A.world then
            local w = world()
            if w == nil then
                a.wtries = (a.wtries or 0) + 1
                if a.wtries >= K.world_tries then return finish(true, "no_world") end
                return
            end
            a.wtries = 0
            if a.world ~= nil and w ~= a.world then return drop("world") end
        end
        -- unreadable: no ownership check and no write, but every stop still ends the run (finish restores an
        -- unreadable value), and world_tries in a row restore blind: time left slow is worse than one blind write
        local cur = get()
        if cur == nil then
            a.rtries = (a.rtries or 0) + 1
            if a.rtries >= K.world_tries then return finish(true, "read_failed") end
        else
            a.rtries = 0
            if a.tried and near(cur, a.tried) then a.last, a.tried = a.tried, nil mark(a) end   -- it landed after all
            if not near(cur, a.last) then return finish(false, "changed") end
        end
        if not a.stepped then
            -- the kill frame hitched: shift the schedule by the lateness (capped), never the absolute guard
            a.stepped = true
            local late = now - a.t0 - K.step_s
            if late > K.late_s then
                local d = math.min(late, K.late_max_s)
                a.t0, a.hold_until, a.max_end = a.t0 + d, a.hold_until + d, a.max_end + d
                a.late_ms = math.floor(late * 1000 + 0.5)
                stats.late = stats.late + 1
            end
        end
        if paused() then return finish(false, "paused") end
        local okg, gate = call(A.gates)
        if okg and gate then return finish(false, tostring(gate)) end
        local v, over = SM.value_at(a, now)
        if over then return finish(false, nil) end
        if cur ~= nil and math.abs(v - a.last) > 1e-3 then
            a.tried = v
            local e = set(v)
            if e then return finish(false, "write_error", e) end   -- one failing call ends the run
            a.last, a.tried = v, nil
            add_val(a, v)
            mark(a)                               -- every ramp step is recorded as the marker's `last`
        end
    end

    -- From the main ticker (every frame while the feature may run)
    function S.tick()
        local now = now_s()
        last_tick, pre_since = now, 0
        if pend then repair(now) end
        check_off()
        local a = active
        if not a then
            if restore then retry_restore(now) elseif left then orphan(now) end
            return
        end
        step(a, now)
    end

    -- A run whose tick stopped (a load gate, another script's error ahead of ours) or that runs past guard_s from
    -- its first start never leaves the game slow
    local function watchdog(now)
        local a = active
        if now - a.g0 > K.guard_s then return finish(true, "guard") end
        local ref = math.max(last_tick or a.g0, a.g0)
        if now - ref > K.stale_s or now > a.hold_until + a.ro + K.overdue_s then finish(true, "watchdog") end
    end

    -- From every other callback list we own: repair, switch-off, watchdog, and the idle work of a stopped tick
    function S.guard()
        local now = now_s()
        if pend then repair(now) end
        if active then
            if not enabled() then return finish(true, "off") end
            return watchdog(now)
        end
        if last_tick and now - last_tick <= K.stale_s then return end
        check_off()
        if restore then retry_restore(now) elseif left then orphan(now) end
    end
    -- From a list that runs ahead of the tick in the same frame: one long frame (a hitch) is no stopped tick, so it
    -- acts only once the tick missed a whole frame (the repair at once)
    function S.guard_pre()
        pre_since = pre_since + 1
        if pre_since > 1 then return S.guard() end
        if pend then repair(now_s()) end
    end

    -- Read the previous state's marker (idempotent; SM.new calls it). No engine call.
    local inited = false
    function S.init()
        if inited then return end
        inited = true
        pend = read_mark()
        marked = pend ~= nil
    end
    -- End now, restoring (a lab cancel, another feature that needs normal time)
    function S.cancel(why) if active then finish(true, why or "cancel") return true end return false end
    -- Script reset or unload. engine == false (UE4SS OnUnload, off the game thread): no engine call at all, the
    -- marker stays live so the next state repairs. Else restore now, and try a pending failed 1.0 once more.
    function S.shutdown(o)
        o = o or {}
        local n = active and 1 or 0
        if o.engine == false then
            local a = active
            active, restore, left, pend = nil, nil, nil, nil
            if a then log("slowmo_end", { reason = a.reason, why = o.reason or "unload", dropped = true }) end
            return n
        end
        finish(true, o.reason or "shutdown")
        if restore then retry_restore(now_s(), true) end
        return n
    end
    -- A world or map change where the engine itself starts the new world at 1.0 (UE): drop with no engine call.
    -- Never use it where the value survives the change (RE Engine global speed): call shutdown there.
    function S.reset(why)
        drop(why or "map")
        cool_until, busy = -1e9, nil
    end
    function S.active() return active ~= nil, active and active.prio or nil end
    function S.status()
        return { runs = stats.runs, extended = stats.extended, refused = stats.refused, active = active ~= nil,
            restoring = restore ~= nil or nil, repairs = stats.repairs > 0 and stats.repairs or nil,
            reclaims = stats.reclaims > 0 and stats.reclaims or nil, stuck = stats.stuck > 0 and stats.stuck or nil,
            late = stats.late > 0 and stats.late or nil, marked = marked or nil,
            cooldown_left = math.max(0, ms(cool_until - now_s())) }
    end
    S.K = K
    S.init()
    return S
end

return SM
