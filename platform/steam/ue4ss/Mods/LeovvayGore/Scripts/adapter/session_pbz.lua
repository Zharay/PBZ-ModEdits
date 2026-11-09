-- status: new in M0 S2.8 (offline only; the lab's first run decides) origin: kb:testing-lab-playtest#engine-name-tables-plus-a-name-lint-against-the-dump
-- session_pbz.lua: the env record of Phantom Blade Zero (spec M0 S2.8, D7, D22, D28, section 3.1 'env'), every profile.
-- main.lua's session_engine (the first game-thread frame) calls SP.start(); from the next frame main.lua's on_frame
-- calls SP.frame(), which runs one step per frame, marked one-shot (MAIN.oneshot: the frame gauges keep it apart):
--   1. register: the hooks of data/hooks.lua (keys 'hook.<id>', each '/Script/M.C:F' or Blueprint path split into its
--      declaring path and bare name) and this file's literal N and F tables, with NAMES.register (pure). Negative
--      controls are never registered: a name expected absent keeps names_missing non-empty, so G1 could never pass.
--   2. names: one NAMES.step per frame (one lookup, or one ForEachProperty pass over a declaring class), timed.
--   3. calls: the calls section of data/hooks.lua (the M1 routes), one ue.find per frame, into calls_total and
--      calls_missing: a measurement for G16, never a names_missing entry and never a G1 gate (D28).
--   4. censor: one read per frame (spec section 3.4). Each CVar under its own always-armed 'probe.cvar.<cvar>'; each PBZ
--      static's params read once under the always-armed 'probe.meta', then, only for no params or one world-context
--      object param, the call once under 'pbz.censor.<fn>'; the property reads (World.AuthorityGameMode.CacheCensored,
--      the Default__PBZGameSettings bCensored and bSuperCensored) unguarded (proven property types).
--   5. loader and env: ENV.loader_package() (file IO), then one env record. Values only, never obeyed: a gore mod never
--      tones itself down on a censor value (HR-NO-TONE-GATES, DESIGN C13); nothing here writes the engine or the
--      console, and nothing reads these values back. A value not read is 'unread', its reason in censor_why.
--   6. re-lints (RUNTIME-6): env is written once, in the menu, before any gameplay Blueprint class loads, so its
--      Blueprint names sit in names_pending. RELINT_FRAMES after a map load (bus map_reset, after main's NAMES.reset)
--      while the last record listed pending names, and at once on lab_end (bus, once per session; NAMES.reset first),
--      the names phase re-opens: one NAMES.step per frame (one-shot frames), then one env_names record { names_total,
--      names_missing, names_pending, names_unchecked, reason 'map_load' | 'lab_end' }. env stays as written.
--   env and env_names carry names_unchecked (review RUNTIME-13): the names_pending entries { name, class, reason }
--   whose reason is not 'not_loaded' ('meta_off', 'meta_failed'), names no re-lint checks; empty when none.
-- SP.resolve_field(type, fields) is the field resolver main.lua hands NAMES.init: ue.has_field (one ForEachProperty pass
-- per declaring class, cached by ue.fields) under the always-armed 'probe.meta'. A refused 'probe.meta' (disabled, a
-- failed arm write) sends the class to names_pending with reason 'meta_off'; a class not in memory answers nil, so a
-- Blueprint class is pending 'not_loaded' and a /Script class is missing (core/names.lua).
-- What the mock cannot prove: native faults in these calls, the real param shapes of the PBZ statics, the CVar types,
-- the timing of a real lookup. The lab's env record decides.
-- API: init(A, opts) start frame resolve_field status reset shutdown env env_names; SP.N, SP.F (the literal tables,
-- read-only); SP.RELINT_FRAMES
-- Evidence: names.tsv rows E0 (R/scratch/gore-design-20261029-2347/work/engine/names.tsv:3-18, :75-81, :140-142);
-- script_objects.tsv:47986, :51035 (PBZGameSettings), :50036-50130 (the statics); props.tsv:3706, :3728, :3311,
-- :8502, :8529-8531, :8541, :19291-19292, :67191; structs.tsv:16504 (BP_GameMode_Build_C in
-- /Game/PBZContent/Blueprint/BP_GameMode_Build)
local ue = require('adapter.ue')
local ENV = require('adapter.env')
local BUS = require('core.bus')
local LOG = require('core.log')
local NAMES = require('core.names')
local SENT = require('core.sentinel')

local SP = { RELINT_FRAMES = 300 }                  -- a map-load re-lint starts about 5 s (at 60 fps) after the load

-- The names this file calls or reads (lint_names reads these literal tables: keep the syntax and the double quotes).
-- The PBZ statics' params are read live (ue.func_params) before any call: the signatures here carry the bare names only.
local N = {
    sp_ksl_get_engine_version = {"/Script/Engine.KismetSystemLibrary", "GetEngineVersion()"},
    sp_ksl_get_frame_count = {"/Script/Engine.KismetSystemLibrary", "GetFrameCount()"},
    sp_ksl_cvar_int = {"/Script/Engine.KismetSystemLibrary", "GetConsoleVariableIntValue(FString)"},
    sp_ksl_cvar_bool = {"/Script/Engine.KismetSystemLibrary", "GetConsoleVariableBoolValue(FString)"},
    sp_pbz_is_launch_censored = {"/Script/ProjectPBZ.PBZBlueprintFunctionLibrary", "IsLaunchCensored()"},
    sp_pbz_get_censored = {"/Script/ProjectPBZ.PBZBlueprintFunctionLibrary", "GetCensored()"},
    sp_pbz_get_super_censored = {"/Script/ProjectPBZ.PBZBlueprintFunctionLibrary", "GetSuperCensored()"},
    sp_pbz_is_censored_version = {"/Script/ProjectPBZ.PBZBlueprintFunctionLibrary", "IsCensoredVersion()"},
}
local F = {
    {"/Script/Engine.World", "PersistentLevel"},
    {"/Script/Engine.World", "AuthorityGameMode"},
    {"/Script/Engine.Level", "WorldSettings"},
    {"/Script/Engine.WorldSettings", "TimeDilation"},
    {"/Script/Engine.WorldSettings", "CinematicTimeDilation"},
    {"/Script/Engine.WorldSettings", "DemoPlayTimeDilation"},
    {"/Script/Engine.WorldSettings", "bAllowTimeDilation"},
    {"/Script/Engine.WorldSettings", "PauserPlayerState"},
    {"/Script/ProjectPBZ.PBZGameSettings", "bCensored"},
    {"/Script/ProjectPBZ.PBZGameSettings", "bSuperCensored"},
    {"/Game/PBZContent/Blueprint/BP_GameMode_Build.BP_GameMode_Build_C", "CacheCensored"},
}
SP.N, SP.F = N, F

local LIB = '/Script/ProjectPBZ.PBZBlueprintFunctionLibrary'
local LIB_CDO = '/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary'
local SETTINGS_CDO = '/Script/ProjectPBZ.Default__PBZGameSettings'
-- env censor field -> CVar name / PBZ static (section 3.1 order)
SP.CVARS = { { 'cvar_launch', 'PBZ.Censor.LaunchCensored' }, { 'cvar_level', 'z.Censoredlelvel' } }
SP.STATICS = { { 'launch_censored', 'IsLaunchCensored' }, { 'get_censored', 'GetCensored' },
    { 'get_super_censored', 'GetSuperCensored' }, { 'censored_version', 'IsCensoredVersion' } }
local CENSOR_FIELDS = { 'launch_censored', 'get_censored', 'get_super_censored', 'censored_version', 'cvar_launch',
    'cvar_level', 'cache_censored', 'settings_censored', 'settings_super' }

-- phase: 'off' until SP.start, then 'register', 'names', 'calls', 'censor', 'env', 'done'; 'renames' during a re-lint
local st = { phase = 'off' }
local run = {}
local PHASE = {}

local function clock() return st.clock() end
local function sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- opts: hooks (data/hooks.lua's hooks table), calls (its calls table), oneshot (MAIN.oneshot), gates (META.region_gates),
-- clock (seconds; default os.clock)
function SP.init(_, opts)
    opts = opts or {}
    st = { phase = 'off', hooks = opts.hooks or {}, calls = opts.calls or {}, oneshot = opts.oneshot,
        gates = type(opts.gates) == 'table' and opts.gates or {}, clock = opts.clock or os.clock,
        pending_n = 0, want_map = false, want_end = false, wait = nil, reason = nil }
    run = { ms_max = 0, steps = 0, registered = 0, call_keys = nil, ci = 1, calls_missing = {}, k = 1, censor = {},
        why = {}, loader = nil, relints = 0, relint_steps = 0 }
    -- The re-lint triggers (RUNTIME-6): main.lua emits map_reset after NAMES.reset, lab_l0i emits lab_end once on the
    -- first lab_end press. The listeners only set a flag; SP.frame acts on it
    BUS.on('map_reset', 'session_pbz', function() st.want_map = true end)
    BUS.on('lab_end', 'session_pbz', function() st.want_end = true end)
    return true
end

-- session_engine (the first frame): the steps run from the next frame on
function SP.start()
    if st.phase == 'off' then st.phase = 'register' end
end

-- 'done' (and during a re-lint): a lab_end re-opens every name now (NAMES.reset; it outranks a map-load re-lint); a
-- map load while the last record listed pending names starts a re-lint RELINT_FRAMES later, when the map's Blueprint
-- classes have had time to load. O(1) per frame: flags and a counter, never a scan
local function relint_due()
    if st.want_end then
        st.want_end, st.want_map, st.wait = false, false, nil
        -- ue.class remembers a class miss until the next map load (ue.reset_caches), so a Blueprint class loaded since
        -- then would still read 'not_loaded': ue.forget_misses drops the cached misses (hits and handles stay)
        if type(ue.forget_misses) == 'function' then pcall(ue.forget_misses) end
        NAMES.reset()
        st.reason, st.phase = 'lab_end', 'renames'
        return
    end
    if st.phase ~= 'done' then return end
    if st.want_map then
        st.want_map = false
        if st.pending_n > 0 then st.wait = SP.RELINT_FRAMES end
    end
    if st.wait then
        st.wait = st.wait - 1
        if st.wait <= 0 then st.wait, st.reason, st.phase = nil, 'map_load', 'renames' end
    end
end

-- One step per frame (main.lua's on_frame); a no-op before SP.start, and once env is written until a re-lint is due
function SP.frame()
    if st.phase == 'done' or st.phase == 'renames' then relint_due() end
    local step = PHASE[st.phase]
    if not step then return end
    if st.oneshot then pcall(st.oneshot) end
    step()
end

-- ---------- 1. register ----------
-- 'hook.<id>' -> { declaring path, bare name } for every hook path with a ':' (the RegisterHook form, D22)
local function hook_names(hooks)
    local out = {}
    for id, h in pairs(hooks) do
        if type(h) == 'table' and type(h.path) == 'string' then
            local t, f = h.path:match('^(.+):([^:]+)$')
            if t then out['hook.' .. tostring(id)] = { t, f } end
        end
    end
    return out
end
PHASE.register = function()
    local hn = hook_names(st.hooks)
    NAMES.register(hn)
    NAMES.register(N, F)
    local n = #F
    for _ in pairs(hn) do n = n + 1 end
    for _ in pairs(N) do n = n + 1 end
    run.registered, st.phase = n, 'names'
end

-- ---------- 2. names: one NAMES.step per frame, timed (rounded to the microsecond, D10) ----------
PHASE.names = function()
    local t0 = clock()
    local k = NAMES.step()
    if k == nil then
        st.phase = 'calls'
        return PHASE.calls()
    end
    local ms = math.floor((clock() - t0) * 1e6 + 0.5) / 1000
    run.steps = run.steps + 1
    if ms > run.ms_max then run.ms_max = ms end
end

-- ---------- 3. calls: one ue.find per frame, sorted by key ----------
PHASE.calls = function()
    if not run.call_keys then run.call_keys = sorted_keys(st.calls) end
    local key = run.call_keys[run.ci]
    if key == nil then
        st.phase = 'censor'
        return PHASE.censor()
    end
    run.ci = run.ci + 1
    local path = st.calls[key]
    if type(path) ~= 'string' then run.calls_missing[#run.calls_missing + 1] = tostring(key)
    elseif ue.find(path) == nil then run.calls_missing[#run.calls_missing + 1] = path end
end

-- ---------- 4. censor reads: values only ----------
local function put(field, v, why)
    if type(v) == 'boolean' or type(v) == 'number' then run.censor[field], run.why[field] = v, nil
    else run.censor[field], run.why[field] = 'unread', why or 'no_value' end
end
-- A sentinel refusal (the name disabled, a failed arm write, an allow veto) vs a call that raised
local function refused(err) return err == 'disabled_by_sentinel' and 'disabled' or 'refused' end

local function read_cvar(field, name)
    local ran = false
    local v, err = SENT.sentinel('probe.cvar.' .. name, function()
        ran = true
        return ue.cvar_int(name)
    end)
    if not ran then return put(field, nil, refused(err)) end
    put(field, v, err and 'error' or 'no_value')
end

-- No params, or exactly one world-context object param (the return value aside): ok, needs_world
local function call_shape(params)
    local ins = {}
    for _, p in ipairs(params) do if not p.ret then ins[#ins + 1] = p end end
    if #ins == 0 then return true, false end
    local p = ins[1]
    if #ins == 1 and p.class == 'ObjectProperty' and tostring(p.name):lower():find('world', 1, true) then
        return true, true
    end
    return false, false
end
local function read_static(field, fn)
    local ran = false
    local params, perr = SENT.sentinel('probe.meta', function()
        ran = true
        return ue.func_params(LIB .. ':' .. fn)
    end)
    if not ran then return put(field, nil, 'meta_off') end
    if type(params) ~= 'table' then return put(field, nil, perr and 'error' or 'no_function') end
    local ok, needs_world = call_shape(params)
    if not ok then return put(field, nil, 'params') end              -- skipped: never called
    local cdo = ue.cdo(LIB_CDO)
    if not cdo then return put(field, nil, 'no_cdo') end
    local w = nil
    if needs_world then
        w = ue.world()
        if not w then return put(field, nil, 'no_world') end
    end
    ran = false
    local box, err = SENT.sentinel('pbz.censor.' .. fn, function()
        ran = true
        local okc, v
        if needs_world then okc, v = ue.call(cdo, fn, w) else okc, v = ue.call(cdo, fn) end
        if not okc then error(tostring(v), 0) end
        return { v = v }
    end)
    if not ran then return put(field, nil, refused(err)) end
    if type(box) ~= 'table' then return put(field, nil, 'error') end
    put(field, box.v, 'no_value')
end

-- Property reads of proven types (spec section 3.4): no sentinel. CacheCensored lives on BP_GameMode_Build_C, so another
-- game mode (the menu) reads 'unread'
local function read_props()
    local w = ue.world()
    local gm = w and ue.prop(w, 'AuthorityGameMode') or nil
    put('cache_censored', gm and ue.prop(gm, 'CacheCensored'), (not w and 'no_world') or (not gm and 'no_game_mode') or nil)
    local s = ue.cdo(SETTINGS_CDO)
    put('settings_censored', s and ue.prop(s, 'bCensored'), not s and 'no_cdo' or nil)
    put('settings_super', s and ue.prop(s, 'bSuperCensored'), not s and 'no_cdo' or nil)
end

local CENSOR = {}
for _, c in ipairs(SP.CVARS) do CENSOR[#CENSOR + 1] = function() read_cvar(c[1], c[2]) end end
for _, s in ipairs(SP.STATICS) do CENSOR[#CENSOR + 1] = function() read_static(s[1], s[2]) end end
CENSOR[#CENSOR + 1] = read_props

PHASE.censor = function()
    local read = CENSOR[run.k]
    if read == nil then
        st.phase = 'env'
        return PHASE.env()
    end
    run.k = run.k + 1
    read()
end

-- ---------- 5. the loader package and the env record ----------
-- names_unchecked (review RUNTIME-13): the pending entries whose reason is not 'not_loaded' ('meta_off', 'meta_failed',
-- a resolver's own reason), copies in names_pending's order. A Blueprint class not loaded yet is checked by a later
-- re-lint; these names were not checked for another reason, so a gate that reads names_missing alone would pass them
local function unchecked(pending)
    local out = {}
    for _, p in ipairs(pending) do
        if p.reason ~= 'not_loaded' then out[#out + 1] = { name = p.name, class = p.class, reason = p.reason } end
    end
    return out
end
PHASE.env = function()
    if not NAMES.done() then                         -- a map load re-opened names (NAMES.reset): finish them first
        st.phase = 'names'
        return
    end
    if run.loader == nil then
        local ok, p = pcall(ENV.loader_package)
        run.loader = ok and type(p) == 'string' and p or 'unknown'
    end
    local censor, why = {}, {}
    for _, f in ipairs(CENSOR_FIELDS) do
        local v = run.censor[f]
        if v == nil then v, run.why[f] = 'unread', run.why[f] or 'not_read' end
        censor[f] = v
        if v == 'unread' then why[f] = run.why[f] end
    end
    local s = NAMES.status()
    local missing = {}
    for i, p in ipairs(run.calls_missing) do missing[i] = p end
    table.sort(missing)
    local g = st.gates
    local pending = NAMES.pending()
    st.env = { names_total = s.total + s.fields, names_missing = NAMES.missing(), names_pending = pending,
        names_unchecked = unchecked(pending),
        calls_total = #(run.call_keys or {}), calls_missing = missing, names_ms_max = run.ms_max, censor = censor,
        censor_why = next(why) and why or nil, loader_package = run.loader,
        region = type(g.region) == 'string' and g.region or 'none', rating = type(g.rating) == 'string' and g.rating or 'none' }
    LOG.info('env', st.env)
    st.phase, st.pending_n = 'done', #st.env.names_pending
end

-- ---------- 6. re-lints (RUNTIME-6): the re-opened names, one NAMES.step per frame, then one env_names record ----------
-- env stays the first record as written; env_names { names_total, names_missing, names_pending, reason 'map_load' |
-- 'lab_end' } is the later word on the names (the last one is the card's)
PHASE.renames = function()
    if NAMES.step() ~= nil then
        run.relint_steps = run.relint_steps + 1
        return
    end
    local s = NAMES.status()
    local pending = NAMES.pending()
    st.env_names = { names_total = s.total + s.fields, names_missing = NAMES.missing(), names_pending = pending,
        names_unchecked = unchecked(pending), reason = st.reason }
    LOG.info('env_names', st.env_names)
    run.relints = run.relints + 1
    st.phase, st.reason, st.pending_n = 'done', nil, #st.env_names.names_pending
end

-- ---------- the field resolver (core/names.lua opts.resolve_field) ----------
-- { [field] = true | false } for one declaring class from one ForEachProperty pass under 'probe.meta'; nil, 'meta_off'
-- when the guard refused; nil, 'meta_failed' when the pass raised on a class that is in memory; nil (no reason) when the
-- class is not in memory; a raise when the guarded step itself raised (core/names.lua: a resolver that raises is a miss)
function SP.resolve_field(t, fields)
    local ran = false
    local box, err = SENT.sentinel('probe.meta', function()
        ran = true
        local out = {}
        for _, f in ipairs(fields or {}) do
            local v, why = ue.has_field(t, f)
            if v == nil then return { why = why or 'unread' } end
            out[f] = v
        end
        return { set = out }
    end)
    if not ran then return nil, 'meta_off' end
    if type(box) ~= 'table' then error('probe.meta: ' .. tostring(err), 0) end
    if box.set then return box.set end
    if box.why == 'meta_failed' then return nil, 'meta_failed' end
    return nil
end

-- ---------- lifecycle ----------
function SP.status()
    return { phase = st.phase, registered = run.registered, steps = run.steps, ms_max = run.ms_max,
        calls_missing = #(run.calls_missing or {}), env = st.env ~= nil, relints = run.relints,
        relint_steps = run.relint_steps, relint_wait = st.wait }
end
function SP.env() return st.env end
function SP.env_names() return st.env_names end      -- the last env_names record, nil before the first
function SP.reset() end                              -- a map load: NAMES.reset re-opens names; SP.env re-checks done()
function SP.shutdown()
    st.phase = 'off'
    BUS.off('map_reset', 'session_pbz')
    BUS.off('lab_end', 'session_pbz')
end

return SP
