-- status: worked DD2 origin: kb:runtime-safety-perf#crash-sentinel-first-success-guard-linger-strikes-quit-hints-e-sentinel-e-risky-e-linger
-- (worked: sentinel, per-kind proof, same-build pairing; untested in game: quit hints, the two-strike rule)
-- sentinel.lua: the crash sentinel. pcall cannot catch a native fault: the process just ends. So a file written BEFORE
-- an unproven native call is the only evidence that survives: armed.json names the call in flight, and the next start
-- switches that name off (disabled.json) until the player presses Re-enable (SENT.enable). Files in opts.dir:
--   armed.json     { call, outer[], hooks[], linger[], quit, t, build } rewritten at each arm and disarm
--   disabled.json  { name = true }        strikes.json { names[], t, build, from, since }
-- Rules (each from a real failure):
-- * Every route / sub-feature has its own name, keyed by what can fault (mesh@LOD, not victim class); never rename a
--   shipped name (it lives in player files). The arm stack is re-entrant: an inner sentinel arms its own name and the
--   outer one is armed again when it returns (a flat design let a nested call clear the outer arm).
-- * A failed arm write SKIPS the call (nil, 'arm_write_failed'): an unrecorded crash is never blamed or learned from.
-- * SENT.risky = arm-once: under the sentinel until one call of its kind PROVED itself this session, then a plain
--   pcall. Proof only from a real result: not a caught error, not nil (a resource still streaming), not false (a refused
--   no-op), plus the caller's proves test. fn must raise when its inner writes failed. Use arm-once only for hot paths;
--   SENT.sentinel on every call (always-arm) where attribution matters. Each sentinel costs 2 synchronous writes
--   (median 0.73 ms, p99 6.4 ms on Windows): never around per-frame polls.
-- * Delayed faults (render workers 1-2 s after the call): SENT.linger(name, s) keeps the name in armed.json for s s of
--   real time (10 s texture/material writes, 5 s decals, 30 s holder releases). A quit leaves the same file, so a
--   lingering name is disabled only on its SECOND unexplained trip in a row, and only when both records come from the
--   SAME mod build (2026-10-13: four first strikes from a pre-release ended by Alt+F4 paired with the next build's first
--   crash and switched two features off in a published build). A quit hint (SENT.quit_hint, or Alt / Alt+F4 seen by
--   SENT.tick while something lingers) excuses lingering names; a call in flight is always a crash.
-- * A script reset or hot reload in the same process (check{ reset = true }) excuses a hooks:install batch and changes
--   no strike. opts.allow(name) -> false, why vetoes a call before arming (the adapter's per-game-build lab arming).
-- * Never trust the sentinel alone: read the dump; a crash proven 'not ours' must not keep features off (Re-enable).
-- API (fixed, lint L015): SENT.sentinel(name, fn, ...) SENT.risky(name, proven, key, proves, fn, ...) SENT.linger(name,
--   s) SENT.linger_group(names, s) SENT.quit_hint(via) SENT.check(opts) SENT.enable(name) SENT.tick([now]); also
--   disable, is_disabled, disabled, strikes, lingering, hook_pending, depth. Lifecycle init(A, opts) / shutdown /
--   status / reset. Call SENT.tick once a frame from every callback still alive.
-- Evidence: [worked DD2] core/engine.lua 460-772; [worked SWZC] lib/arm.lua (a failed write skips the call);
-- kb:runtime-safety-perf principles 2-6 and #refuted (first-call-only sentinels; linger disabling at once)
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local STORE = require(BASE .. 'store')
local LOG = require(BASE .. 'log')

local SENT = {}
local HOOKS_CALL = 'hooks:install'

local A, fs, cfg, allow = nil, nil, nil, nil
local build = 'dev'
local armed, pending, pending_age = {}, {}, 0
local lingering, linger_n = {}, 0
local quit, alt_since, alt_last = nil, nil, nil
local disabled = {}
local strikes, strikes_from, strikes_since = {}, nil, nil
local stats = { writes = 0, write_fail = 0, skipped = 0 }
local dirty = false

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end
local function real() return A.clock.real() end
local function wall() return A.clock.wall() end
local function save(path, t)
    if cfg.atomic then return STORE.write_atomic(fs, path, t) end
    return STORE.write_json(fs, path, t)
end

-- opts: dir, build (the mod build stamp), allow(name) -> false, why; linger_s 10, quit_hold 30, alt_hold 2,
-- alt_tail 1, vk_alt 0x12, vk_f4 0x73, atomic (tmp + rename writes; default off: 2 plain writes per arm)
function SENT.init(adapter, opts)
    opts = opts or {}
    A, fs, allow = adapter, adapter.fs, opts.allow
    local dir = opts.dir or ''
    cfg = { armed = dir .. 'armed.json', disabled = dir .. 'disabled.json', strikes = dir .. 'strikes.json',
        linger_s = opts.linger_s or 10, quit_hold = opts.quit_hold or 30, alt_hold = opts.alt_hold or 2,
        alt_tail = opts.alt_tail or 1, vk_alt = opts.vk_alt or 0x12, vk_f4 = opts.vk_f4 or 0x73, atomic = opts.atomic }
    build = opts.build or 'dev'
    armed, pending, pending_age, lingering, linger_n = {}, {}, 0, {}, 0
    quit, alt_since, alt_last, disabled, dirty = nil, nil, nil, {}, false
    strikes, strikes_from, strikes_since = {}, nil, nil
    stats = { writes = 0, write_fail = 0, skipped = 0 }
    return true
end

-- armed.json as the state is now; false when the write failed (a disarm retries from SENT.tick)
local function arm()
    local n = #armed
    local rec = { call = armed[n] or '', t = wall(), build = build }
    if n > 1 then
        rec.outer = {}
        for i = 1, n - 1 do rec.outer[i] = armed[i] end
    end
    if n == 0 and #pending > 0 then
        rec.call, rec.hooks = HOOKS_CALL, {}
        for i, k in ipairs(pending) do rec.hooks[i] = k end
    end
    if linger_n > 0 then rec.linger = sorted_keys(lingering) end
    if quit then rec.quit = quit.via end
    local t0 = real()                                   -- the write's cost (TC-BETA-01c: is it the lag on hits?)
    local ok = save(cfg.armed, rec)
    local ms = (real() - t0) * 1000
    stats.write_ms = (stats.write_ms or 0) + ms
    if ms > (stats.write_ms_max or 0) then stats.write_ms_max = ms end
    if ms >= 10 then stats.write_slow = (stats.write_slow or 0) + 1 end
    if ok then stats.writes, dirty = stats.writes + 1, false
    else stats.write_fail, dirty = stats.write_fail + 1, true end
    return ok
end

function SENT.sentinel(name, fn, ...)
    if disabled[name] then return nil, 'disabled_by_sentinel' end
    if allow then
        local okv, yes, why = pcall(allow, name)
        if not okv or yes == false then return nil, (okv and why) or 'not_armed' end
    end
    armed[#armed + 1] = name
    if not arm() then
        armed[#armed] = nil
        stats.skipped = stats.skipped + 1
        if LOG.every('arm_write_failed:' .. name, 60) then LOG.warn('arm_write_failed', { call = name }) end
        return nil, 'arm_write_failed'
    end
    local ok, r = pcall(fn, ...)
    armed[#armed] = nil                 -- also after an error: pcall returned
    arm()
    if not ok then return nil, tostring(r) end
    return r
end

-- proves: nil (any real result), a predicate of the result, or the value the result must equal
function SENT.risky(name, proven, key, proves, fn, ...)
    if disabled[name] then return nil, 'disabled_by_sentinel' end
    if proven[key] then
        local ok, r = pcall(fn, ...)
        if ok then return r end
        return nil, tostring(r)
    end
    local r, err = SENT.sentinel(name, fn, ...)
    if err == nil and r ~= nil and r ~= false then
        local good = proves == nil
        if type(proves) == 'function' then
            local okp, p = pcall(proves, r)
            good = okp and p == true
        elseif proves ~= nil then
            good = r == proves
        end
        if good then proven[key] = true end
    end
    return r, err
end

function SENT.depth() return #armed end

-- ---------- hook batches and lingering names ----------
-- Hooks the loader installs later (REFramework: next frame) keep armed.json at hooks:install with their keys until
-- two SENT.tick calls passed; a crash meanwhile disables the whole batch (which hook is unknown)
function SENT.hook_pending(k)
    pending[#pending + 1] = k
    pending_age = 0
    if #armed == 0 then arm() end
end
function SENT.hooks_pending() return #pending end

local function linger_one(name, s, now)
    if disabled[name] then return false end
    local fresh = lingering[name] == nil
    local untilt = now + (s or cfg.linger_s)
    if fresh or untilt > lingering[name] then lingering[name] = untilt end
    if fresh then linger_n = linger_n + 1 end
    return fresh
end
-- A repeat only moves the deadline (no write)
function SENT.linger(name, s)
    if linger_one(name, s, real()) then arm() end
end
-- Several names with one write (one kill's routes)
function SENT.linger_group(names, s)
    local now, any = real(), false
    for _, name in ipairs(names) do if linger_one(name, s, now) then any = true end end
    if any then arm() end
end
function SENT.lingering() return sorted_keys(lingering) end

-- A script reset in the same process: the lingers and the quit hint go (a reset is not a crash)
function SENT.linger_clear()
    if linger_n == 0 and quit == nil then return end
    lingering, linger_n, quit, alt_since = {}, 0, nil, nil
    arm()
end

-- ---------- quit hints ----------
-- app_exit (the loader's managed exit hook, a menu Quit) and alt_f4 are sticky: withdrawn when frames still run
-- quit_hold 30 s later (then it was no exit). alt: Alt held at most alt_hold 2 s, kept alt_tail 1 s after it went up
-- (Alt+F4 closes the window inside F4's own message, so the last frame sees Alt down and F4 not yet). Keys are read
-- only while a name lingers: the hint excuses lingering names only.
local function sticky(via) return via == 'app_exit' or via == 'alt_f4' end
local function key(vk)
    if not (A.keys and A.keys.down) then return false end
    local ok, r = pcall(A.keys.down, vk)
    return ok and r == true
end
local function set_quit(via, now)
    if (quit and quit.via) == via then return false end
    quit = via and { via = via, at = now } or nil
    arm()
    return true
end
function SENT.quit_hint(via)
    local v = via or 'app_exit'
    if set_quit(v, real()) then LOG.info('quit_hint', { via = v, linger = SENT.lingering() }) end
end

local function quit_tick(now)
    if quit and sticky(quit.via) then
        if now - quit.at < cfg.quit_hold then return false end
        local via = quit.via
        alt_since = nil                 -- an Alt press after the withdrawal starts its own hold time
        set_quit(nil, now)
        LOG.info('quit_withdrawn', { via = via })
        return true
    end
    if linger_n == 0 then
        quit, alt_since = nil, nil
        return false
    end
    local want = nil
    if key(cfg.vk_alt) then
        alt_since, alt_last = alt_since or now, now
        if key(cfg.vk_f4) then want = 'alt_f4'
        elseif now - alt_since <= cfg.alt_hold then want = 'alt' end
    else
        alt_since = nil
        if quit and quit.via == 'alt' and alt_last and now - alt_last <= cfg.alt_tail then want = 'alt' end
    end
    local wrote = set_quit(want, now)
    if wrote and want and LOG.every('quit_hint_keys', 1, now) then
        LOG.info('quit_hint', { via = want, linger = SENT.lingering() })
    end
    return wrote
end

-- Once a frame: expired lingers disarm, the quit hint follows the keys, a hook batch disarms on its second tick, and a
-- disarm write that failed is retried
function SENT.tick(now)
    if not A then return end
    now = now or real()
    local closed = false
    if linger_n > 0 then
        for k, t in pairs(lingering) do
            if now >= t then lingering[k], linger_n, closed = nil, linger_n - 1, true end
        end
    end
    local wrote = false
    if quit or linger_n > 0 then wrote = quit_tick(now) end
    if (closed or dirty) and not wrote and #armed == 0 then arm() end
    if #pending == 0 then return end
    pending_age = pending_age + 1
    if pending_age >= 2 then
        pending = {}
        if #armed == 0 then arm() end
    end
end

-- ---------- strikes, the start check, Re-enable ----------
local function persist_strikes()
    local names = sorted_keys(strikes)
    if not names[1] then strikes_from, strikes_since = nil, nil end
    save(cfg.strikes, { names = names, t = wall(), build = build, from = strikes_from, since = strikes_since })
end
local function persist_disabled()
    local out = {}
    for k, v in pairs(disabled) do if v then out[k] = true end end
    save(cfg.disabled, out)
end
local function same_set(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- At load, once. opts.reset: the same process after a script reset or hot reload. Returns the name the game died in
-- last time ('linger:<name>' when only a lingering name was disabled), the armed.json record, and res { quit,
-- disabled = names switched off now, struck = first strikes, excused = lingering names a quit hint explained,
-- renewed = struck names whose earlier strike came from another build's record, prev_from = that build }. Logs
-- sentinel_tripped / sentinel_strike (warn) and sentinel_quit (info); sentinel_tripped carries same_build (the
-- armed.json record's build equals this build: a card gate can count this build's trips alone).
function SENT.check(opts)
    local reset = type(opts) == 'table' and opts.reset == true
    local res = { disabled = {}, struck = {}, excused = {}, renewed = {} }
    local saved = STORE.read_json(fs, cfg.disabled)
    if type(saved) == 'table' then
        for k, v in pairs(saved) do if v == true then disabled[k] = true end end
    end
    local prev, prev_from, prev_since = {}, nil, nil
    local st = STORE.read_json(fs, cfg.strikes)
    if type(st) == 'table' and type(st.names) == 'table' then
        for _, k in ipairs(st.names) do if type(k) == 'string' and not disabled[k] then prev[k] = true end end
        if type(st.from) == 'string' and st.from ~= '' then prev_from = st.from end
        if type(st.since) == 'number' then prev_since = st.since end
    end
    strikes, strikes_from, strikes_since = prev, prev_from, prev_since
    res.prev_from = prev_from
    local s = STORE.read_json(fs, cfg.armed)
    if type(s) ~= 'table' then return nil, nil, res end   -- no record, or a torn one: no evidence either way
    local function off(k)
        disabled[k] = true
        res.disabled[#res.disabled + 1] = k
    end
    local tripped = nil
    local call = type(s.call) == 'string' and s.call or ''
    if call == HOOKS_CALL and type(s.hooks) == 'table' then
        if not reset then
            for _, k in ipairs(s.hooks) do if type(k) == 'string' then off('hook:' .. k) end end
            tripped = call
        end
    elseif call ~= '' then
        off(call)
        tripped = call
    end
    local q = type(s.quit) == 'string' and s.quit ~= '' and s.quit or nil
    res.quit = q
    local lingered = {}
    if type(s.linger) == 'table' then
        for _, k in ipairs(s.linger) do if type(k) == 'string' and not disabled[k] then lingered[#lingered + 1] = k end end
    end
    if not reset then
        local from = type(s.build) == 'string' and s.build ~= '' and s.build or nil
        local same = from ~= nil and from == prev_from
        local nxt = {}
        for _, k in ipairs(lingered) do
            if q then
                res.excused[#res.excused + 1] = k
            elseif prev[k] and same then
                off(k)
                tripped = tripped or ('linger:' .. k)
            else
                nxt[k] = true
                res.struck[#res.struck + 1] = k
                if prev[k] then res.renewed[#res.renewed + 1] = k end
            end
        end
        local any = next(nxt) ~= nil
        local nfrom = any and from or nil
        local nsince = any and type(s.t) == 'number' and s.t or nil
        local changed = not same_set(prev, nxt) or nfrom ~= prev_from or nsince ~= prev_since
        strikes, strikes_from, strikes_since = nxt, nfrom, nsince
        if changed then persist_strikes() end
    end
    if #res.disabled > 0 then persist_disabled() end
    if call ~= '' or #lingered > 0 or q then
        save(cfg.armed, { call = '', t = wall(), build = build, tripped = tripped })
    end
    local since, was = s.t, s.build
    -- same_build: the record came from this mod build (a trip carried over from an earlier build reads false)
    if tripped then
        LOG.warn('sentinel_tripped', { call = tripped, off = res.disabled, since = since, build = was,
            same_build = type(was) == 'string' and was == build })
    end
    if res.struck[1] then
        LOG.warn('sentinel_strike', { linger = res.struck, since = since, build = was,
            renewed = res.renewed[1] and res.renewed or nil, prev_build = res.renewed[1] and prev_from or nil })
    end
    if res.excused[1] then LOG.info('sentinel_quit', { via = q, linger = res.excused, since = since, build = was }) end
    return tripped, s, res
end

function SENT.is_disabled(name) return disabled[name] == true end
function SENT.disabled() return sorted_keys(disabled) end
function SENT.strikes() return sorted_keys(strikes) end

local function drop_strike(name)
    if strikes[name] then
        strikes[name] = nil
        persist_strikes()
    end
end
function SENT.disable(name, why)
    disabled[name] = true
    persist_disabled()
    drop_strike(name)
    LOG.info('sentinel_disable', { call = name, why = why })
end
-- Re-enable (the settings window's Status, a console command): the name starts over, its next trip is a first strike
function SENT.enable(name)
    local was = disabled[name] == true
    disabled[name] = nil
    persist_disabled()
    drop_strike(name)
    LOG.info('sentinel_enable', { call = name, was_disabled = was })
end

function SENT.status()
    return { disabled = SENT.disabled(), strikes = SENT.strikes(), lingering = SENT.lingering(), depth = #armed,
        quit = quit and quit.via or nil, writes = stats.writes, write_fail = stats.write_fail, skipped = stats.skipped,
        write_ms = math.floor((stats.write_ms or 0) + 0.5), write_ms_max = math.floor((stats.write_ms_max or 0) + 0.5),
        write_slow = stats.write_slow or 0 }
end
function SENT.reset() SENT.linger_clear() end
function SENT.shutdown()
    if not A then return end
    pending, lingering, linger_n, quit, alt_since = {}, {}, 0, nil, nil
    if #armed == 0 then arm() end
end
function SENT.handoff() return { lingering = SENT.lingering() } end

return SENT
