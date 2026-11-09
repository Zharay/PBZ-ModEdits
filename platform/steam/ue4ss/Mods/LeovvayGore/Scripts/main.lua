-- status: worked SWZC (the structure; untested as a template in game) origin: kb:runtime-safety-perf#module-contract-and-fault-tolerant-loading
-- main.lua: the LeovvayGore entry for UE4SS. A thin adapter over core-lua (Scripts/core): never fork core logic here.
-- THREADS: this body, key binds and OnUnload run on UE4SS's update thread: no engine call there, and a key bind is
-- VM-only (a counter, adapter/keys.lua; spec M1a 4.2 item 1): the tick drains it. Engine work runs on
-- the game thread: hooks, the LoadMap callback, console handlers, and the tick chain (adapter/tick.lua), whose first
-- frame writes session_engine (engine version, the arm build key, the hooks installed, each under its own sentinel);
-- from the next frame on, adapter/session_pbz.lua runs the staggered names lint and the censor reads and writes the env
-- record (every profile); every frame the tick writes hook_first for the ids that fired first since the last frame.
-- Order: meta -> env -> module requires (pure, timed; failures in MAIN.failed) -> log -> the session header (pure,
-- first record) -> mods.txt off -> core init (sentinel + arm check, sched, bus, config, the Mods Menu sync
-- (adapter/modsmenu.lua), modoff, dev) -> feature init
-- -> hook consumers -> LoadMap -> keys -> console -> tick -> OnUnload.
-- Profiles (meta.lua): release (no lab module, except META.beta_modules when META.beta: the player beta, beta port
-- S1; the header then reads beta true and lists META.lab_risky; with META.beta_spawn, the author's test build, also
-- lab_spawn when its file is there: one beta_spawn record), dev (bare F8, auto-armed RISKY gates, the features,
-- META.lab_modules, then the dev set's modules: META.dev_sets[META.dev_set], spec M1a D2), probe (META.lab_modules
-- only: no MAIN.MODULES, no META.extra_modules, no dev set module; spec M0 D5). Every
-- profile inits the hooks with count_only false: the lab modules declare their own optional consumers.
-- Evidence: [worked SWZC] main.lua 42-170, 338-373, 471-589, 594-664; [worked DD2] main.lua 1-60 (MAIN.MODULES,
-- failed, broken, load_ms); kb:runtime-safety-perf#ue4ss-hot-reload-engine-free-onunload-epochs-shared-variables,
-- #ue4ss-lookup-caching-and-staggered-warm-up
local META = require('meta')
local MAIN = { loaded = {}, failed = {}, broken = {}, order = {}, load_ms = {}, disabled = {}, absent = {} }
local track = rawget(_G, 'GORE_TRACK_MAIN')            -- the offline harness fails a test on any MAIN.failed entry
if track then track(MAIN) end

-- Feature modules in init order (data first, the kill pipeline after the features it emits to, UI late).
MAIN.MODULES = {
    -- <<gore:modules>>
}
-- Sentinel names of risky first writes (the header lists them; in the dev profile the lab-gated ones auto-arm)
MAIN.RISKY = {
    -- <<gore:sentinel>>
}

local ENV = require('adapter.env')
local LOG = require('core.log')
local S = require('core.sched')
local SENT = require('core.sentinel')
local BUS = require('core.bus')
local C = require('core.config')
local MODOFF = require('core.modoff')
local DEV = require('core.dev')
local NAMES = require('core.names')
local REG = require('core.registry')
local ue = require('adapter.ue')
local HOOKS = require('adapter.hooks')
local ARM = require('adapter.arm')
local KEYS = require('adapter.keys')
local TA = require('adapter.tarray')
local TICK = require('adapter.tick')
local MU = require('adapter.modoff_ue')
local SP = require('adapter.session_pbz')
local MENU = require('adapter.modsmenu')
local HDATA = require('data.hooks')

local E = ENV.init(META)
local A = ENV.adapter()
local profile = META.profile
local probe, dev = profile == 'probe', profile == 'dev'
local lab = probe or dev                                -- the lab builds (D4 stamp); never a player build
local beta = profile == 'release' and META.beta == true -- the player beta (beta port S1): META.beta_modules
local beta_spawn = beta and META.beta_spawn == true     -- its test build: lab_spawn too, when the file is there
local handoff = ENV.take() or {}

-- ---------- module requires: pure, timed; a failure stays in MAIN.failed ----------
-- optional (META.beta_spawn's lab_spawn): a module no searcher finds is no failure; its name goes to MAIN.absent
local function load_modules(list, optional)
    for _, name in ipairs(list or {}) do
        if not MAIN.loaded[name] and not MAIN.failed[name] then
            local t0 = os.clock()
            local ok, m = pcall(require, name)
            MAIN.load_ms[name] = math.floor((os.clock() - t0) * 1000 + 0.5)
            if ok and type(m) == 'table' then
                MAIN.loaded[name] = m
                MAIN.order[#MAIN.order + 1] = name
            elseif optional and not ok and tostring(m):find("module '" .. name .. "' not found", 1, true) then
                MAIN.load_ms[name], MAIN.absent[#MAIN.absent + 1] = nil, name
            else
                MAIN.failed[name] = ok and 'not a module table' or tostring(m)
            end
        end
    end
end
-- The probe loads only META.lab_modules (D5); dev loads the features, the extras, then the lab modules (they enter
-- MAIN.order, so the header's modules and the code hash name them); release requires no lab module, except the player
-- beta's META.beta_modules (META.beta, beta port S1: the lab modules runs 4-10 ran, no lab key) and, in the author's
-- test build (META.beta_spawn), lab_spawn after them: the spawn keys, then lab_slice_probe (the slicer's S0 probe,
-- docs/research/slicer-stumps.md), lab_slice_watch (the passive listener of the game's own slicer calls),
-- lab_sword_looks (the sword spike's other looks and their key, plugged into the beta's lab_sword), then lab_testkeys:
-- the keys of the console verbs and the probes' keys (META.test_keys; the console does not reach the mod on UE4SS 1185
-- in PBZ). The
-- player zip leaves these files out (gore.project.json package.ship_when), so there they are absent: no spawn or test
-- key, no start_error, one beta_spawn record
local TEST_BUILD = { 'lab_spawn', 'lab_slice_probe', 'lab_slice_watch', 'lab_sword_looks', 'lab_testkeys' }   -- loaded, recorded
if not probe then
    load_modules(MAIN.MODULES)
    load_modules(META.extra_modules)                    -- dev builds and offline tests
    if beta then load_modules(META.beta_modules) end
    if beta_spawn then load_modules(TEST_BUILD, true) end
end
if lab then load_modules(META.lab_modules) end
-- The dev set (spec M1a D2): META.dev_sets[META.dev_set].modules, resolved in every profile (pure data, no require)
-- into META.dev_lab_modules, the M0 D32 name of the list the dev profile alone loads after META.lab_modules (kept, so a
-- test copy of the load line still finds it). An unknown set name resolves to none; the dev profile then loads none
-- and writes one start_error once the log is up (MAIN.dev_set_err)
local function dev_set_modules()
    local sets, name = META.dev_sets, META.dev_set
    local set = type(sets) == 'table' and sets[name] or nil
    if type(set) == 'table' and type(set.modules) == 'table' then return set.modules, nil end
    local known = {}
    for k in pairs(type(sets) == 'table' and sets or {}) do known[#known + 1] = tostring(k) end
    table.sort(known)
    return nil, string.format('unknown dev set %q (known: %s)', tostring(name), table.concat(known, ', '))
end
META.dev_lab_modules, MAIN.dev_set_err = dev_set_modules()
if dev then load_modules(META.dev_lab_modules) end      -- 'spawn': lab_spawn; 'lab02': the eight M1a modules

-- The header's risky list: MAIN.RISKY, plus META.lab_risky (nil safe) in the probe and dev profiles and the beta. Only
-- the header merges them: lab and probe names are never ARM.gate'd, so ARM's dev auto list stays MAIN.RISKY (spec 3.4)
function MAIN.risky()
    if not (lab or beta) or type(META.lab_risky) ~= 'table' then return MAIN.RISKY end
    local out, have = {}, {}
    for _, list in ipairs({ MAIN.RISKY, META.lab_risky }) do
        for _, name in ipairs(list) do
            if not have[name] then have[name], out[#out + 1] = true, name end
        end
    end
    return out
end

-- ---------- log and the session header (pure: nothing here touches the engine) ----------
-- The code hash's files (MAIN.CODE): every file under adapter/ and core/ is listed, which tests/test_session_pbz.lua
-- checks against the tree; the lab data tables and the two generated stubs too (spec M1a A1.10, tests/test_lab_data.lua)
-- and the beta's dismemberment data (BD0: the class table, the cap sizing, the cap meshes BD2 writes; a missing file
-- counts nothing), and lab_corpse's left-out classes. A module's own library follows it (LIBS: lab_cut requires
-- lab_cut_beta, BD10; lab_blood lab_grey, lab_blood_slice, lab_blood_queue and lab_blood_wash; lab_slice lab_slice_lod;
-- lab_slice_route lab_slice_prep)
local CODE = { 'main.lua', 'meta.lua', 'data/hooks.lua', 'data/hide_table.lua', 'data/lab_pairs.lua',
    'data/lab_classes.lua', 'data/sigs.lua', 'data/caps_generic.lua', 'data/no_blood.lua', 'data/cut_classes.lua',
    'data/caps_beta_sizing.lua', 'data/caps_beta.lua', 'data/corpse_skip.lua', 'adapter/env.lua', 'adapter/ue.lua',
    'adapter/hooks.lua', 'adapter/arm.lua', 'adapter/keys.lua', 'adapter/tarray.lua', 'adapter/tick.lua',
    'adapter/modoff_ue.lua', 'adapter/session_pbz.lua', 'adapter/ue_lab.lua', 'adapter/ue_spawn.lua',
    'adapter/modsmenu.lua' }
for _, m in ipairs({ 'api', 'bus', 'config', 'dev', 'gov', 'log', 'modoff', 'names', 'registry', 'rng', 'sched',
    'sentinel', 'store', 'vmath' }) do CODE[#CODE + 1] = 'core/' .. m .. '.lua' end
-- Jamon Iberico's fitted caps (tools/caps_dd2/to_pbz.py): one data file per cut level
for _, c in ipairs({ 'neck', 'shoulder', 'elbow', 'hip', 'knee' }) do CODE[#CODE + 1] = 'data/caps_dd2/' .. c .. '.lua' end
local LIBS = { lab_cut = { 'lab_cut_beta.lua' }, lab_blood = { 'lab_grey.lua', 'lab_blood_slice.lua',
    'lab_blood_queue.lua', 'lab_blood_wash.lua' }, lab_slice = { 'lab_slice_lod.lua' },
    lab_slice_route = { 'lab_slice_prep.lua' } }
for _, name in ipairs(MAIN.order) do
    CODE[#CODE + 1] = name:gsub('%.', '/') .. '.lua'
    for _, f in ipairs(LIBS[name] or {}) do CODE[#CODE + 1] = f end
end
MAIN.CODE = CODE

LOG.init(A, { dir = E.data, level = dev and 'debug' or 'info', frame = TICK.frame })
local label, sha = ENV.ue4ss_label()
local ue4ss_ver = nil
if UE4SS and UE4SS.GetVersion then
    local ok, a, b, c = pcall(UE4SS.GetVersion)
    if ok then ue4ss_ver = string.format('%s.%s.%s', a, b, c) end
end
local failed_list = {}
for name in pairs(MAIN.failed) do failed_list[#failed_list + 1] = name end
table.sort(failed_list)
local stamped = type(META.build) == 'string' and not META.build:find('@@', 1, true)
local mods_off = ENV.mods_off()
local header = LOG.session({
    mod = META.mod, version = META.VERSION, build = stamped and META.build or nil, code_hash = ENV.code_hash(CODE),
    profile = profile, lab = (probe or dev) or nil, beta = beta or nil,
    loader = { kind = 'ue4ss', commit = sha, label = label, version = ue4ss_ver },
    game_build = ENV.steam_buildid(), gates = META.region_gates, pins = META.build_pins, lua = _VERSION,
    starts = E.starts, reloaded = E.reloaded, folder = E.folder, neighbours = ENV.neighbours(), modules = MAIN.order,
    modules_failed = failed_list, load_ms = MAIN.load_ms, risky = MAIN.risky(), off_by = mods_off and 'mods_txt' or nil,
})
for _, name in ipairs(failed_list) do LOG.start_error(name, MAIN.failed[name]) end
if dev and MAIN.dev_set_err then LOG.start_error('dev_set', MAIN.dev_set_err) end   -- an unknown set: none loaded
-- The beta test build's one record: each TEST_BUILD module (lab_spawn, lab_slice_probe, lab_slice_watch,
-- lab_sword_looks, lab_testkeys) by name, 'loaded', 'absent' (no file: the player zip) or 'failed' (start_error)
if beta_spawn then
    local words = {}
    for _, name in ipairs(TEST_BUILD) do
        words[name] = MAIN.loaded[name] and 'loaded' or MAIN.failed[name] and 'failed' or 'absent'
    end
    LOG.info('beta_spawn', words)
end

-- '<folder> : 0' in mods.txt: nothing else runs (no hook, no key, no tick); back on needs a restart
if mods_off then
    LOG.write('warn', 'disabled', { by = 'mods_txt', msg = META.mod .. ' is switched off in mods.txt' }, true)
    return
end

-- ---------- core ----------
local state = { paused = false, speed = 1.0, pframes = 0, first = true }
S.init(A, { gate = function() return true, state.paused end })
ARM.init(A, { state = E.state, buildid = header.game_build ~= 'unknown' and header.game_build or nil,
    auto = dev and MAIN.RISKY or nil, window = profile == 'release', mod_version = META.VERSION })
SENT.init(A, { dir = E.data, build = header.build, allow = ARM.allow })
local tripped, checked = ARM.check(E.reloaded)
-- The start check for lab_probe's stop rule (spec M0 D9): the name found in flight (nil when none) and the names struck
-- at this start (first strikes of lingering names). A name in flight, or a struck or linger-tripped 'lab.inherit.*'
-- name, sets inherit_off for the session; any other strike only writes a stop record kind 'strike'
MAIN.tripped = tripped
MAIN.struck = type(checked) == 'table' and type(checked.struck) == 'table' and checked.struck or {}
BUS.init(A, { is_off = function(name) return S.off()[name] == true end })
REG.init(A)
-- The names lint (D22, D28): '<declaring path>:<bare name>' through ue.find; fields one ForEachProperty pass per declaring
-- class under the always-armed 'probe.meta' (session_pbz.lua); session_pbz steps it one entry per frame
NAMES.init(A, { lazy = true, resolve_path = ue.find, resolve_field = SP.resolve_field })
C.init(A, { base = E.state .. 'settings' })
-- Mods Menu (spec_149): the menu's config and the seen mark in our data folder, the bridge's files in its own folder
-- next to ours (with a data_dir, tests or a dev data folder, under it: the live bridge folder is never read then).
-- The game's GameUserSettings.ini gives the text language the descriptor is written in at a fresh start (with a
-- data_dir, a GameUserSettings.ini in it: the live one is never read then; with no LOCALAPPDATA, E.game_ini is nil
-- and the menu has no ini: menu_lang says no_ini).
-- File reads and writes only, polled by its sched ticker; a fault here never stops the start.
-- Its Status row (MENU.word) reads module state only, never the engine: mod-off and the vanilla compare, the beta's pin
-- answer (lab_probe LAB.pin_state, nil until lab_probe's init and its check; 'none' without lab_probe or after its
-- init broke) and the sentinel's disabled names, of which MENU.known counts META.lab_risky and every data/hooks.lua hook
-- less META.status_quiet (a retired name is in no list)
local menu_known = MENU.known(META.lab_risky, HDATA.hooks, META.status_quiet)
local function menu_state()
    local lab, pin = MAIN.loaded.lab_probe, 'none'
    if lab and not MAIN.broken.lab_probe and type(lab.pin_state) == 'function' then pin = lab.pin_state() end
    return { off = MODOFF.is_off(), vanilla = MODOFF.is_vanilla(), pin = pin, disabled = SENT.disabled() }
end
local menu_ok, menu_err = pcall(MENU.init, A, { dir = E.data, folder = E.folder, reloaded = E.reloaded,
    bridge = (META.data_dir == nil and E.mods_dir) and (E.mods_dir .. '/PBZModsMenuBridge/')
        or (E.data .. 'PBZModsMenuBridge/'),
    ini = META.data_dir ~= nil and (E.data .. 'GameUserSettings.ini') or E.game_ini,
    status = menu_state, known = menu_known })
if not menu_ok then LOG.start_error('adapter.modsmenu', menu_err) end
MODOFF.init(A, { ops = MU.ops(HOOKS), flush = { function() C.flush_if_dirty() end } })
DEV.init(A, { dir = E.data, last_id = type(handoff.dev) == 'table' and handoff.dev.last_id or nil })
TA.init()
KEYS.init()

-- The gate every hook consumer and feature asks: missing hook, mod off / vanilla, the sched breaker, the master switch
function MAIN.enabled(feature)
    if MAIN.disabled[feature] or not MODOFF.enabled(feature) or S.off()[feature] then return false end
    local ok, s = pcall(C.get)
    return not (ok and type(s) == 'table' and s.enabled == false)
end
-- A hook that is missing (first tick) or failed once its Blueprint class loaded switches only its features off
local function hook_missing(feature, id)
    if MAIN.disabled[feature] then return end
    MAIN.disabled[feature] = 'hook:' .. id
    LOG.warn('feature_off', { feature = feature, hook = id, reason = 'hook_missing' })
end
-- count_only false in every profile (D5): the probe's hooks are its lab modules' optional consumers
HOOKS.init(HDATA, { gate = MAIN.enabled, count_only = false, on_missing = hook_missing })
LOG.info('start', { disabled = SENT.disabled(), strikes = SENT.strikes(), tripped = tripped, dev = DEV.active,
    reloaded = E.reloaded, data = E.data ~= '' })

-- ---------- counters, gauges and one-shot frames (spec M0 section 3.2) ----------
-- MAIN.count(k, n): a cumulative counter (gates read grown()). MAIN.gauge(name, fn): a current value, fn() read at each
-- status record (nil = absent; an error reads { status_error }). Each provider returns nil while empty, so the status
-- field is absent (log.lua status_record), except that the probe and dev counters always carry world_writes
-- (ue.status().writes, 0 included; 'unread' when unreadable): the zero-writes gate passes on a real session and reads
-- NO DATA on a header-only log. A module publishes only the counters it owns.
-- MAIN.oneshot() marks the current frame one-shot (hook install, the names lint, RC, FindAllOf, the inventory, the
-- state probe); MAIN.frame_cost() -> frame, ms, oneshot of the last finished on_frame, timed in the probe and dev
-- only, for lab_probe's frame gauges (S2.9). In release oneshot only sets a flag nobody reads.
local stat = { counters = {}, gauges = {}, oneshot = false, f = nil, ms = nil, was_oneshot = nil }
function MAIN.count(k, n) stat.counters[k] = (stat.counters[k] or 0) + (n or 1) end
function MAIN.gauge(name, fn) stat.gauges[name] = fn end
function MAIN.oneshot() stat.oneshot = true end
function MAIN.frame_cost() return stat.f, stat.ms, stat.was_oneshot end
local function counters_status()
    local out, any = {}, false
    for k, v in pairs(stat.counters) do out[k], any = v, true end
    if lab then
        local ok, s = pcall(ue.status)
        out.world_writes, any = ok and type(s) == 'table' and s.writes or 'unread', true
    end
    return any and out or nil
end
local function gauges_status()
    local out, any = {}, false
    for name, fn in pairs(stat.gauges) do
        local ok, v = pcall(fn)
        if not ok then out[name], any = { status_error = tostring(v):sub(1, 200) }, true
        elseif v ~= nil then out[name], any = v, true end
    end
    return any and out or nil
end
-- The env record (every profile): registers the hook and session names, then one step per frame once session_engine
-- started it; each step frame is one-shot
SP.init(A, { hooks = HDATA.hooks, calls = HDATA.calls, oneshot = MAIN.oneshot, gates = META.region_gates })

-- ---------- features: init(MAIN) in order; an init that raises stays in MAIN.broken (its shutdown still runs) ----------
MAIN.A, MAIN.meta, MAIN.env, MAIN.ue, MAIN.hooks, MAIN.arm, MAIN.keys, MAIN.tarray, MAIN.tick = A, META, E, ue, HOOKS,
    ARM, KEYS, TA, TICK
MAIN.handoff = handoff.modules or {}
-- Feature contract: init(adapter, opts). The adapter is a view: MAIN.A first (fs, clock and the game glue a mod adds
-- there: apply, undo, is_dead, cap_spawn ...), then MAIN itself (ue, hooks, arm, tick, meta, handoff); opts come from
-- MAIN.FEATURE_OPTS[<module name>] (kill: { T = rules }, parts: { data = families_data }).
MAIN.FEATURE_OPTS = MAIN.FEATURE_OPTS or {}
-- Console verbs a module adds from its init (through the view: adapter.verb(name, fn, usage)): 'leovvaygore <name>
-- ...' calls fn(args) on the console thread, args[1] the verb; fn returns the reply and an optional job (it runs on the
-- game thread). fn does no engine work itself. A name of the built-in verbs is refused (false)
MAIN.verbs, MAIN.verb_usage = {}, {}
MAIN.BUILTIN_VERBS = { status = true, off = true, on = true, vanilla = true, preset = true, set = true, enable = true,
    dev = true }
function MAIN.verb(name, fn, usage)
    if type(name) ~= 'string' or type(fn) ~= 'function' or MAIN.BUILTIN_VERBS[name:lower()] then return false end
    MAIN.verbs[name:lower()], MAIN.verb_usage[name:lower()] = fn, type(usage) == 'string' and usage or name
    return true
end
MAIN.FA = setmetatable({}, { __index = function(_, k)
    local v = MAIN.A and MAIN.A[k]
    if v ~= nil then return v end
    return MAIN[k]
end })
for _, name in ipairs(MAIN.order) do
    local m = MAIN.loaded[name]
    if type(m.init) == 'function' then
        local ok, err = pcall(m.init, MAIN.FA, MAIN.FEATURE_OPTS[name])
        if not ok then
            MAIN.failed[name], MAIN.broken[name] = tostring(err), m
            LOG.start_error(name, err)
        end
    end
end

-- ---------- map loads: epochs, resets, one hook retry per pending class, the staggered warm-up ----------
-- Each module's warm() runs alone, one per META.warm_step_ms, so no frame pays for a dozen object scans
local function schedule_warm(start_ms)
    local ep, i = ue.epoch, 0
    for _, name in ipairs(MAIN.order) do
        local m = MAIN.loaded[name]
        if type(m.warm) == 'function' and not MAIN.broken[name] then
            TICK.after_ms(start_ms + i * (META.warm_step_ms or 150), function()
                if ep ~= ue.epoch then return end                    -- a newer map load owns the warm-up now
                local ok, err = pcall(m.warm)
                if not ok then LOG.warn('warm_error', { module = name, err = tostring(err) }) end
            end)
            i = i + 1
        end
    end
    return i
end

ue.on_load_map(function(_, world)
    local ok, err = pcall(function()
        S.bump_epoch('map')
        ue.bump_epoch()
        ue.reset_caches()
        ue.set_world(ue.p(world))
        REG.bump_epoch()
        MODOFF.reset()
        NAMES.reset()
        for _, name in ipairs(MAIN.order) do
            local m = MAIN.loaded[name]
            if type(m.reset) == 'function' then pcall(m.reset, 'map') end
        end
        BUS.emit('map_reset', 'map')
        local left = HOOKS.retry_pending('loadmap')
        local warms = schedule_warm(META.warm_start_ms or 3000)
        LOG.info('map', { world = ue.name(ue.world()), pending_hooks = left, warm = warms, epoch = ue.epoch })
    end)
    if not ok then LOG.warn('map_error', { err = tostring(err) }) end
    return nil
end)

-- ---------- keys (the callbacks only count; the tick drains them, keys.lua) ----------
local dkeys = dev and META.dev_keys or {}
KEYS.bind('modoff', dkeys.modoff or META.keys.modoff, function(via) MODOFF.toggle(via) end)
KEYS.bind('vanilla', dkeys.vanilla or META.keys.vanilla, function(via) MODOFF.vanilla(via) end)

-- ---------- one console command: reply before returning, queue the work, return true ----------
-- 'enable <name|all>' (beta port S7): PBZ gives no quit hint, so a quit inside a name's linger is a strike and a second
-- one in a row on the same build disables that name for good (core/sentinel.lua, disabled.json and strikes.json in the
-- mod folder). It hands the name back through SENT.enable (its strike goes too): 'all' every disabled and every struck
-- name, a bare 'enable' lists them. A module's own verb (MAIN.verb, above the feature init) runs after these; an
-- unknown word lists them after USAGE
local USAGE = META.prefix .. ' status|off|on|vanilla|preset <name>|set <path> <value>|enable <name|all>|dev <cmd> '
    .. '[key=value ...]'
local function value_of(s)
    if s == 'true' or s == 'on' then return true elseif s == 'false' or s == 'off' then return false end
    return tonumber(s) or s
end
local function status_line()
    local h = HOOKS.status()
    local nf = 0
    for _ in pairs(MAIN.failed) do nf = nf + 1 end
    return string.format('%s %s (%s) %s | off %s, vanilla %s | hooks ok %d, pending %d, failed %d | frames %d | '
        .. 'sentinel off %d | modules %d, failed %d', META.mod, META.VERSION, header.build, profile,
        tostring(MODOFF.is_off()), tostring(MODOFF.is_vanilla()), h.ok, h.pending, h.failed + h.unknown, TICK.frame(),
        #SENT.disabled(), #MAIN.order, nf)
end
local function console(_, params, out)
    local args = {}
    if type(params) == 'table' then for _, p in ipairs(params) do args[#args + 1] = tostring(p) end end
    local cmd = (args[1] or 'status'):lower()
    local reply, job = nil, nil
    if cmd == 'status' then
        reply, job = status_line(), function() LOG.status_record('cmd') end
    elseif cmd == 'off' or cmd == 'on' then
        if (cmd == 'off') == MODOFF.is_off() then reply = META.mod .. ' is already ' .. cmd
        elseif cmd == 'off' and MODOFF.is_vanilla() then reply = 'refused: the vanilla compare is on (' .. META.prefix .. ' vanilla first)'
        else reply, job = META.mod .. ' ' .. cmd, function() MODOFF.toggle('console') end end
    elseif cmd == 'vanilla' then
        if MODOFF.is_off() then reply = 'refused: ' .. META.mod .. ' is off (' .. META.prefix .. ' on first)'
        else reply, job = 'vanilla compare ' .. (MODOFF.is_vanilla() and 'off' or 'on'), function() MODOFF.vanilla('console') end end
    elseif cmd == 'preset' then
        local name = args[2]
        if name and C.PRESETS[name] then reply, job = 'preset ' .. name, function() C.apply_preset(name) end
        else reply = 'presets: ' .. table.concat(C.PRESET_ORDER or {}, ' ') end
    elseif cmd == 'set' and args[2] and args[3] then
        local path, v = args[2], value_of(args[3])
        reply, job = 'set ' .. path .. ' = ' .. tostring(v), function() C.set(path, v) end
    elseif cmd == 'enable' then
        local off, struck = SENT.disabled(), SENT.strikes()
        local listed, names = {}, {}
        for _, list in ipairs({ off, struck }) do
            for _, n in ipairs(list) do if not listed[n] then listed[n], names[#names + 1] = true, n end end
        end
        local want = args[2]
        if want and want:lower() ~= 'all' then names = listed[want] and { want } or {} end
        if not want then
            reply = 'disabled: ' .. (off[1] and table.concat(off, ' ') or 'none') .. ' | struck: '
                .. (struck[1] and table.concat(struck, ' ') or 'none') .. ' (' .. META.prefix .. ' enable <name|all>)'
        elseif not names[1] then
            reply = want:lower() == 'all' and 'nothing is disabled or struck' or (want .. ' is not disabled or struck')
        else
            reply, job = 'enabled: ' .. table.concat(names, ' '), function()
                for _, n in ipairs(names) do SENT.enable(n) end
            end
        end
    elseif cmd == 'dev' and args[2] then
        if not DEV.active then reply = 'dev channel off (no dev marker)'
        else
            local c = { cmd = args[2] }
            for i = 3, #args do
                local k, v = args[i]:match('^([%w_]+)=(.*)$')
                if k then c[k] = value_of(v) end
            end
            reply, job = 'dev ' .. c.cmd .. ' queued (answer in the log)', function() DEV.run(c) end
        end
    elseif MAIN.verbs[cmd] then                         -- a module's verb (MAIN.verb)
        local ok, r, j = pcall(MAIN.verbs[cmd], args)
        reply = ok and tostring(r or cmd) or ('error: ' .. tostring(r))
        if ok and type(j) == 'function' then job = j end
    else
        local extra = {}
        for name in pairs(MAIN.verbs) do extra[#extra + 1] = MAIN.verb_usage[name] end
        table.sort(extra)
        reply = 'usage: ' .. USAGE .. (extra[1] and ' | ' .. table.concat(extra, ' | ') or '')
    end
    for line in (reply .. '\n'):gmatch('([^\n]*)\n') do pcall(function() out:Log(line) end) end
    if job then
        ExecuteInGameThread(function()
            local ok, err = pcall(job)
            if not ok then LOG.warn('console_error', { cmd = cmd, err = tostring(err) }) end
        end)
    end
    return true
end
ue.console_command(META.prefix, console)

-- ---------- the game-thread tick ----------
MAIN.gauge('keys', KEYS.stats)                -- presses, handler calls, presses over the per-frame cap, errors
LOG.add_status('hooks', function() local h = HOOKS.status() return { ok = h.ok, pending = h.pending, failed = h.failed } end)
LOG.add_status('tick', TICK.status)
LOG.add_status('cost', S.take_cost)
LOG.add_status('sentinel', SENT.status)
LOG.add_status('ue', ue.status)
LOG.add_status('tarray', TA.status)
LOG.add_status('modoff', MODOFF.status)
LOG.add_status('menu', MENU.status)
LOG.add_status('counters', counters_status)
LOG.add_status('gauges', gauges_status)

-- The first frame: what only the game thread can read, then the hooks, then a warm-up for a hot load mid-map.
-- Guards (spec M0 S2.17, D8, section 3.4), always-armed in every profile, never SENT.risky (a first-call-only
-- sentinel leaves later crashes unattributed, refuted.md:116):
-- * each static CDO call (UFunction through ProcessEvent) runs once under its own 'probe.static.<fn>'; a disabled name
--   skips the call and reads 'unknown', so ARM gets no build key and arms nothing on an unknown build;
-- * every registration runs under its own 'hook:<id>' (hooks.lua opts.wrap, kept for later registrations: a Blueprint
--   class load, mod on): a crash there disables that id alone at the next start, never the 'hooks:install' batch;
-- * the UFunction flags read (GetFunctionFlags, once per hook path) runs under 'probe.meta' (hooks.lua opts.meta).
-- The install frame is one-shot for the lab's frame gauges (MAIN.oneshot).
local function hook_wrap(id, fn) return SENT.sentinel('hook:' .. id, fn) end
local function meta_wrap(fn, ...) return SENT.sentinel('probe.meta', fn, ...) end
local function session_engine()
    local v = SENT.sentinel('probe.static.GetEngineVersion', ue.engine_version)
    local key = ARM.set_engine(v)
    MAIN.oneshot()
    HOOKS.install({ wrap = hook_wrap, meta = meta_wrap })
    for feature, id in pairs(HOOKS.missing()) do hook_missing(feature, id) end
    local h = HOOKS.status()
    local f = SENT.sentinel('probe.static.GetFrameCount', ue.frame)
    LOG.info('session_engine', { engine = v or 'unknown', arm_key = key or 'unknown', gates = header.gates,
        hooks = { ok = h.ok, pending = h.pending, failed = h.failed, unknown = h.unknown }, tick = TICK.status().method,
        frame = f or 'unknown' })
    schedule_warm(5000)
    SP.start()                                          -- the names lint, the censor reads and env, from the next frame
end

-- hook_first (spec M0 section 3.1, D29): one record per id on the tick after its first fire, from the flags the hook
-- body set (hooks.lua take_first); written here, never inside a hook body (L014). With the lab's hook_fire records it
-- is the only attribution of a crash inside a hook body, whose payload reads run unguarded by design.
local function write_firsts()
    local list = HOOKS.take_first()
    for i = 1, #list do LOG.info('hook_first', { key = list[i].key, side = list[i].side }) end
end


-- ---------- Ctrl+R: engine-free (update thread, the world still ticks); never runs at process exit ----------
-- Spec M1a 4.2 item 1 asked for a flag only and a teardown on the tick. UE4SS cannot give that: uninstall() runs
-- OnUnload, then erases every pending game-thread action of the mod and lua_close()s its state
-- (LuaMod.cpp:6129-6270), so a tick step queued here never runs and the hand-off below would be lost. So OnUnload
-- does first the VM-only part (the flag MAIN.unloading, then the three upvalue switches: the tick chain's epoch, the key
-- drain and the hook consumers go inert at once; no ExecuteInGameThread, no UnregisterHook, no UObject), then the same
-- main-state teardown as before: file writes and the shared-variable hand-off, no engine call. The tick keeps no
-- teardown of its own (tests/test_ue4ss_main.lua pins both parts).
MAIN.unloading = false
function MAIN.OnUnload()
    MAIN.unloading = true
    TICK.stop()
    KEYS.shutdown()
    HOOKS.shutdown()
    pcall(SP.shutdown)
    S.bump_epoch('unload')
    local mods = {}
    for i = #MAIN.order, 1, -1 do
        local name = MAIN.order[i]
        local m = MAIN.loaded[name]
        if type(m.handoff) == 'function' then
            local ok, t = pcall(m.handoff)
            if ok and type(t) == 'table' then mods[name] = t end
        end
        if type(m.shutdown) == 'function' then pcall(m.shutdown, 'unload') end
    end
    pcall(C.shutdown)
    pcall(MENU.shutdown)                                -- after the A/B flush: the seen mark may follow it
    pcall(MODOFF.shutdown)
    pcall(DEV.shutdown, 'unload')
    pcall(SENT.shutdown)
    ENV.handoff({ dev = DEV.handoff(), sched = S.handoff(), modules = mods })
    LOG.shutdown('unload')
end
pcall(function() ModRef.OnUnload = MAIN.OnUnload end)

LOG.info('ready', { msg = META.mod .. ' ' .. META.VERSION .. ' | ' .. profile .. ' | ' .. USAGE })

-- The game-thread tick: the body's last statement (fix round 2 runtime review), so no body Lua runs on the update
-- thread once the game thread can run the first step
TICK.start({
    on_frame = function()
        local t0 = lab and os.clock() or nil            -- the lab's frame cost (MAIN.frame_cost); release: no clock
        KEYS.drain()                                    -- first: a raise below never starves the keys (mod-off, lab_end)
        if state.first then
            state.first = false
            session_engine()
        else
            SP.frame()                                  -- one session_pbz step (a no-op once env is written)
        end
        write_firsts()
        state.pframes = state.pframes + 1
        -- pause and game speed every 15 frames: WorldSettings property reads (S1.5), never a UFunction
        if state.pframes >= 15 then
            state.pframes, state.paused, state.speed = 0, ue.paused(), ue.dilation()
        end
        S.on_late(state.speed)
        S.on_render()
        SENT.tick()
        if t0 then                                      -- rounded to the microsecond (1 ms os.clock steps, D10)
            stat.f, stat.ms = TICK.frame(), math.floor((os.clock() - t0) * 1e6 + 0.5) / 1000
            stat.was_oneshot, stat.oneshot = stat.oneshot, false
        end
    end,
    on_status = function()
        LOG.status_tick()
        SENT.tick()
    end,
})
return MAIN
