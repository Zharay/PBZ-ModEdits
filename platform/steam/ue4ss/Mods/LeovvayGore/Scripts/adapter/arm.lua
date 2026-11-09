-- status: worked SWZC (markers, in-flight sentinel, player window; auto-arm untested) origin: kb:runtime-safety-perf#ue4ss-arming-markers-per-build-lab-arming-in-flight-sentinel-call-window-auto-arm-retry-per-mod-version-lib-arm-lua
-- arm.lua: the UE4SS bindings of core/sentinel.lua (the logic lives there: in-flight record, strikes, Re-enable).
-- * Lab gates: a name declared with ARM.gate(name) (a native that never ran from UE4SS here: an uncallable route,
--   GeometryScript, a skinned decal) runs only once a lab card armed it ON THIS BUILD (ARM.mark), or, in the dev
--   profile, when it is on the auto list and nothing was decided on this build. Ungated names pass (first-write
--   sentinels of ordinary features need no lab run: defaults stay on).
-- * The build key is the engine version (its changelist changes with every patch) plus the Steam buildid. The engine
--   version is read on the first game-thread tick (ARM.set_engine): until then every gated name is 'unknown_build'.
-- * Markers in <state>arm.json { version, armed = { name = { key = { state, how, t, mod } } } }, at most MAX_BUILDS
--   keys per name, written tmp + rename (store.lua). Never packaged.
-- * The proc token (env.lua shared variable) tells a hot reload from a crash: ARM.check(reloaded) hands it to
--   SENT.check{ reset }; a name found in flight at a real start is switched off by the sentinel and disarmed here
--   on the next known build key.
-- * Call window (release profile): ARM.call keeps the name lingering window_s (0.5 s) after each call, so a fault in
--   the render work right after it is still attributed; SENT.tick (every frame) is the delayed step that clears it.
-- * No file I/O in kill frames beyond the sentinel's own two writes per armed call.
-- API: init(A, opts) gate allow set_engine key mark disarm call uncallable check status reset shutdown
-- Evidence: [worked SWZC] lib/arm.lua 1-101, 556-680, tools/luatest/test_arm.lua, test_arm_window.lua
local STORE = require('core.store')
local SENT = require('core.sentinel')
local LOG = require('core.log')
local ue = require('adapter.ue')

local ARM = { MAX_BUILDS = 4, WINDOW_S = 0.5 }
local A, path, data, key, cfg = nil, nil, nil, nil, nil
local gated, auto, crashed = {}, {}, {}

-- opts: state (path prefix), buildid, auto { name } (dev), window (bool), window_s, mod_version
function ARM.init(adapter, opts)
    opts = opts or {}
    A, key, gated, auto, crashed = adapter, nil, {}, {}, {}
    cfg = { buildid = opts.buildid, window = opts.window == true, window_s = opts.window_s or ARM.WINDOW_S,
        mod = opts.mod_version }
    path = (opts.state or '') .. 'arm.json'
    local raw = A.fs.read(path)
    data = STORE.read_atomic(A.fs, path)
    cfg.unreadable = raw ~= nil and type(data) ~= 'table'
    if type(data) ~= 'table' or type(data.armed) ~= 'table' then data = { version = 1, armed = {} } end
    for _, n in ipairs(opts.auto or {}) do auto[n] = true end
    return true
end

function ARM.gate(name) gated[name] = true end
function ARM.key() return key end

local function save() return STORE.write_atomic(A.fs, path, data) end

local function put(name, state, how)
    if not key then return false, 'unknown_build' end
    local e = data.armed[name] or {}
    data.armed[name] = e
    e[key] = { state = state, how = how, t = A.clock.wall(), mod = cfg.mod }
    local keys = {}
    for k in pairs(e) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return (e[a].t or 0) > (e[b].t or 0) end)
    for i = ARM.MAX_BUILDS + 1, #keys do e[keys[i]] = nil end
    return save()
end
function ARM.mark(name, how) return put(name, 'armed', how or 'lab') end
function ARM.disarm(name, why) return put(name, 'disarmed', why or 'lab') end

-- The first game-thread tick: the build key; a crash found at load is disarmed on it now
function ARM.set_engine(version)
    if type(version) ~= 'string' or version == '' then return nil end
    key = version .. '|' .. tostring(cfg.buildid or '?')
    for _, n in ipairs(crashed) do if gated[n] then ARM.disarm(n, 'crash') end end
    crashed = {}
    LOG.info('arm_build', { key = key, gated = ARM.names(gated), auto = ARM.names(auto) })
    return key
end

-- sentinel opts.allow: true | false, why (unknown_build, disarmed, other_build, never_armed)
function ARM.allow(name)
    if not gated[name] then return true end
    if not key then return false, 'unknown_build' end
    local e = data.armed[name]
    local m = e and e[key]
    if m and m.state == 'disarmed' then return false, 'disarmed' end
    if m and m.state == 'armed' then return true end
    if auto[name] and not cfg.unreadable then return true end
    if e and next(e) then return false, 'other_build' end
    return false, 'never_armed'
end

-- fn under the sentinel (it arms, calls, disarms; a failed arm write skips the call), plus the call window. Only a
-- call that ran lingers: a vetoed one (unknown_build, never_armed, disabled, a failed arm write) writes nothing more
-- and can never strike on a quit.
function ARM.call(name, fn, ...)
    local ran = false
    local r, err = SENT.sentinel(name, function(...)
        ran = true
        return fn(...)
    end, ...)
    if cfg.window and ran then SENT.linger(name, cfg.window_s) end
    return r, err
end
-- ue.call_uncallable as an armed, gated call: nil + why when refused or failed
function ARM.uncallable(name, spec)
    ARM.gate(name)
    return ARM.call(name, function()
        spec.armed = true
        local r, why = ue.call_uncallable(spec)
        spec.armed = nil
        if r == nil then error(why, 0) end
        return r
    end)
end

-- At load (pure: file reads and writes). reloaded = the same process (env proc token): not a crash
function ARM.check(reloaded)
    local tripped, _, res = SENT.check({ reset = reloaded == true })
    if tripped and not tripped:find('^linger:') and not tripped:find('^hooks:') then crashed[#crashed + 1] = tripped end
    return tripped, res
end

function ARM.names(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end
function ARM.status()
    return { key = key, gated = ARM.names(gated), auto = ARM.names(auto), window = cfg and cfg.window,
        unreadable = cfg and cfg.unreadable }
end
function ARM.reset() end
function ARM.shutdown() end

return ARM
