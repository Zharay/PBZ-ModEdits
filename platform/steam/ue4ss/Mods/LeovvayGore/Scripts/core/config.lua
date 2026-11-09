-- status: worked DD2 (the base-preset fill of missing keys untested) origin: kb:persistence-settings-api#preset-layered-settings-config
-- config.lua: the settings layer. One table per Lua state, saved through store.lua's A/B slots (opts.base .. '.a.json'
-- and '.b.json'). Modules read it live (C.get each time, or one C.section_opt reader); nothing caches a value past a
-- C.gen() change.
-- Rules (each from a real failure):
-- * DEFAULTS is the top preset 'maximum' (house rule: every built feature ships on). C.PRESETS are sparse overlays
--   that lower amounts and never switch a built feature off; a preset owns only C.PRESET_KEYS. Changing an owned key
--   makes the preset 'custom'; C.base_preset() keeps the last named one, so a light player who moves one slider keeps
--   light's budgets. C.PRESET_NAMES is the display map (pinned to gore.project.json budgets.presets by a test).
-- * C.PRESET_ALIASES: the pre-release ids full and lite resolve to maximum and light for one version (spec M0 section
--   0 rule 11): C.PRESETS[old] (the console lookup), C.apply_preset(old) and C.load of a file holding an old id all
--   give the new id, and only the new id is ever stored or returned by C.base_preset.
-- * Load fills a missing key from DEFAULTS overlaid by the file's BASE PRESET, never from plain DEFAULTS (DD2 filled
--   new switches with Maximum's value on a Light file and had to patch it twice in one release). A value of the wrong
--   type is replaced the same way; a stored false stays false; the word 'off' (or 'on') in a boolean slot reads as
--   false (true); unknown keys are kept (a downgrade must not lose them).
-- * Migrations are keyed on value plus marker, never on the version alone: a build that rescales a value lists it in
--   C.MARKED, C.save writes '<key>_v<n>' beside it, and C.marked() tells the step the value is already on the new
--   scale (an older build re-saved the file as an older version and brightness was scaled twice).
-- * Saves are debounced (opts.debounce_s 1 s after the last change, C.tick: a sched ticker) and flushed on mod-off,
--   reset and shutdown. No Lua runs at a quit on some loaders: never rely on a save at exit. Sched tickers stop
--   while its gate is closed (title screen, loads), so the adapter also calls C.tick from its independent frame
--   callback: a change made in the title-screen window is otherwise saved only once a game is loaded.
-- * Dev overrides (C.override) are runtime-only: C.get() returns them overlaid, C.save never writes them, and the dev
--   channel clears them when it goes off. A dev 'set' that persisted once kept a probe running in release installs.
-- * User tables are type-guarded: C.section(name) is {} for a non-table, section_opt never throws.
-- * The beta's dismemberment knobs (docs/research/beta-dismemberment-plan.md BD0) are top-level DEFAULTS keys outside
--   C.PRESET_KEYS (a preset switch leaves them alone; the console 'leovvaygore set <key> <value>' writes them). Modules
--   read them through C.knob(name) only, live at each use: C.KNOBS clamps a number and checks a word, a wrong type
--   reads the default.
-- API (stable): C.init(A, opts) load get section section_opt(sec, defaults, presets, choices) word(path, choices)
--   effect(name) family_on(key) knob(name) set(path, v) reset(paths) apply_preset(name) base_preset([s])
--   preset_value(path) touch tick([now]) flush_if_dirty on_change(fn) gen override(path, v) clear_overrides
--   marked(t, key, ver) shutdown status; tables DEFAULTS PRESETS PRESET_KEYS PRESET_ORDER PRESET_NAMES PRESET_ALIASES
--   MIGRATIONS MARKED VERSION KNOBS. A path is 'a.b' or { 'a', 'b' }.
-- Evidence: [worked DD2] core/config.lua; [worked SWZC] lib/config_loader.lua (user_table guard);
-- kb:persistence-settings-api#versioned-idempotent-settings-migration, #one-section-reader; base-preset fill [untested]
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local STORE = require(BASE .. 'store')
local LOG = require(BASE .. 'log')
local S = require(BASE .. 'sched')

local C = {}
C.VERSION = 2

-- The top preset. add-feature inserts a feature's section above the anchor line (one table per feature).
local DEFAULTS = {
    version = 1,
    enabled = true,
    preset = 'maximum',
    preset_base = 'maximum',     -- the last named preset ('custom' keeps its budgets); never a preset key
    log_level = 'info',
    chance = 1.0,                -- chance that a qualifying blow cuts (a killing blow always cuts: house rule)
    -- A multiplier over the vanilla blood spawn the fx path copies: 1.0 is the vanilla reference amount, so 3.0 is 3x
    -- vanilla (HR-BLOOD-LIQUID multiplier 3; spec M0 D15). Presets lower it: 3.0/2.5/2.0/1.5
    blood_amount = 3.0,
    -- Soul's blood goes progressively (lab_blood, the author 2026-10-31: «let it fade progressively, and a full
    -- restore keeps the blood for a while but speeds up the fade»): a splash on him goes once soul_blood_life_s seconds
    -- of game time passed (pause not counted; 0 keeps it until the cap or a map load). A full heal (wash_on_heal) leaves
    -- the blood heal_hold_s seconds, then takes what is left oldest first over heal_fade_s (false: no heal fade). A
    -- death and a respawn wash it at once either way («and after death too»). No preset owns them
    -- soul_blood: enemies' blood lands on Soul; false: none lands and his splashes wash at once (lab_blood; the player
    -- request of 2026-11-01, spec_149 section 5). A C.KNOBS type guard; no preset owns it
    soul_blood = true,
    -- soul_face_blood: enemies' blood lands on Soul's head and face too; false: his splashes skip the head, neck, face
    -- and hair bones and the body bones next to his neck (lab_blood's B.FACE_NEAR), and the ones already there wash
    -- at once (lab_blood; the player request of 2026-11-02, Nexus 178851837). His body and clothes keep what
    -- soul_blood gives them. A C.KNOBS type guard; no preset owns it
    soul_face_blood = true,
    -- sword_blood: the weapons Soul strikes with take the blood of the enemies he hits (lab_sword; the author
    -- 2026-11-01 «so the blood can stay on the sword only and not on Soul», look A of spike S1 kept 2026-11-02);
    -- false: the weapons stay clean and the blood on them goes at once. Independent of soul_blood (soul_blood false
    -- plus this true: blood on the sword only). It follows soul_blood_life_s and wash_on_heal (heal_hold_s,
    -- heal_fade_s), and a death cleans it. A C.KNOBS type guard; no preset owns it
    sword_blood = true,
    wash_on_heal = true,
    soul_blood_life_s = 300,
    heal_hold_s = 15,
    heal_fade_s = 45,
    effects = { cut = true, gib = true, pieces = true, caps = true, blood = true, wounds = true, slowmo = true,
        sound = true },
    -- kept: corpses kept with their cuts (spec M0 D15; replaces victims). No Cap limit: no limit evicts a live Cap
    -- (DESIGN C4, spec M0 D17). parts_per_victim: Parts one victim can lose [P]
    limits = { pieces = 150, gibs = 150, kept = 24, parts_per_victim = 8, pools = 200 },
    -- speed 0.28 (PLAN 4.4); the camera gate: a kill farther than max_cam_dist UE units (3000 = 30 m) or with a view
    -- dot under min_cam_dot gets no slow motion [P]
    slowmo = { speed = 0.28, seconds = 0.5, cooldown = 8.0, max_cam_dist = 3000, min_cam_dot = 0.6 },
    families = {},               -- family key -> false switches it off (absent = on)
    gates = {},                  -- lab gate id -> true once its card passed (unproven techniques stay closed)
    -- The beta's dismemberment knobs (BD0; the author's answers of 2026-10-31), read through C.knob (C.KNOBS):
    max_parts = 3,               -- the most parts one kill loses, one per family (head, arm_l, arm_r, leg_l, leg_r)
    heavy_parts = 2,             -- parts on a heavy blow (kill.tier 'heavy'; answer 1)
    shaqi_parts = 3,             -- parts on Sha-Qi, a main-weapon Power Surge or an Ultimate (tier 'shaqi'; 1, 2)
    -- cut_chance: the percent of eligible kills that cut (lab_plan rolls per kill id; 100 rolls nothing: today's
    -- behaviour). The player request F2 (Nexus 178914417, spec fixes-0.2.2 D5). Never the preset key 'chance' (light
    -- sets that to 0.25); no preset owns it
    cut_chance = 100,
    -- finisher_cuts: a finisher or a stealth kill (its bullet names an Execution) is an execution and cuts nothing
    -- (the author's answer 12, the page's "executions cut nothing"); true lets it cut like any blow. Players
    -- DragonBryan1997 (Nexus 178977255) and Jarol (178964712): a stealth kill takes a head it never aimed at
    finisher_cuts = false,
    parts_per_s = 6,             -- the most parts cut per real second over every victim (a primary is never dropped)
    -- the Cap sections (lab_look): basic (flat colours), textured (tier A), game (tier B: the default since TC-BETA-01,
    -- tier A has no live parent), native (tier N: the game's own art, the default since route B, settings v2)
    cap_look = 'native',
    cap_scale = 1.0,             -- a factor on the sized Cap radius
    cap_fade_s = 1.5,            -- the Caps hide this long after a dissolve signal (lab_fade); 0 turns the fade off
    piece_linger_s = 0,          -- a Piece or gib stays this long after its body went (0: it goes with it; answer 10)
    -- a cloth-hair head (answer 6): 'burst' (skull, meat and the vanilla head-break FX) or 'keep' (it flies with its
    -- hair: a Chaos cloth copy on a runtime component, unproven, so a failed keep bursts); never a bald head
    hair_mode = 'burst',
    extras_fall = true,          -- hats and masks fall off a cut head as their own physics copies (answer 7)
    gib_count = 6,               -- the chunks of a burst head (a skull and meat)
    -- the beta's corpse keep (lab_corpse; the author, 2026-11-01: «all corpses stay 15 min»)
    corpse_keep_s = 900,         -- game seconds an enemy corpse lies before it goes (0: the game's own 2 s dissolve)
    corpse_max = 60,             -- the most corpses kept at once; over it the oldest goes early
    -- the beta's volumetric drops (lab_drops; the author, 2026-11-01: «more volumetric drops»)
    drops = true,                -- 3D drops fly from wounds and stumps and leave small stains where they land
    drops_n = 8,                 -- drops of one bled hit at blood_amount 3 (kills, cuts and spurts scale from it)
    drops_max = 96,              -- the pool: the most drops in flight at once
    -- the game's own slicer on ordinary death cuts (lab_slice_route; the author, 2026-11-01: «there must be a way in ue
    -- to make really ultra-high-quality stumps»): false gives every death today's joint cut (our caps)
    slicer = true,
    -- other_ue4ss: true waives the loader pin only (game build and ARM key must still match) for a UE4SS build
    -- META.beta_loaders does not list. Load-only: lab_probe's pin check reads it once a session, so a change takes
    -- effect at the next game start. The player request F4 (Nexus 178901185, spec fixes-0.2.2 D6); false is today
    other_ue4ss = false,
    -- <<gore:defaults>>
}
C.DEFAULTS = DEFAULTS

-- Old id -> new id, for one version (spec M0 section 0 rule 11); never stored, never listed
C.PRESET_ALIASES = { full = 'maximum', lite = 'light' }
local function canon(name) return C.PRESET_ALIASES[name] or name end

-- Slow motion and gibs stay on in every preset (spec M0 D15): a preset lowers amounts, it never switches a built
-- feature off (HR-DEFAULTS-ON). C.PRESETS[old id] resolves through the alias (pairs lists only the four ids).
C.PRESETS = setmetatable({
    maximum = {},
    balanced = { chance = 0.7, blood_amount = 2.5, slowmo = { cooldown = 15.0 },
        limits = { pieces = 90, gibs = 90, kept = 16, pools = 120 } },
    restrained = { chance = 0.4, blood_amount = 2.0,
        limits = { pieces = 50, gibs = 40, kept = 12, pools = 60 } },
    light = { chance = 0.25, blood_amount = 1.5,
        limits = { pieces = 24, gibs = 16, kept = 8, pools = 30 } },
}, { __index = function(t, k)
    local to = C.PRESET_ALIASES[k]
    if to ~= nil and to ~= k then return rawget(t, to) end
    return nil
end })
C.PRESET_ORDER = { 'maximum', 'balanced', 'restrained', 'light' }
-- Display names, pinned to gore.project.json budgets.presets (test_core_config)
C.PRESET_NAMES = { maximum = 'Maximum', balanced = 'Balanced', restrained = 'Restrained', light = 'Light' }
-- The keys a preset owns; everything else (enabled, families, gates, log level, module tuning) survives a preset switch
C.PRESET_KEYS = { chance = true, blood_amount = true, effects = true, limits = true, slowmo = true }
-- The beta's knobs (BD0): what C.knob accepts for each. lo and hi clamp a number (int: floored first), words is the
-- set of accepted words; an empty row takes any value of its default's type
C.KNOBS = {
    max_parts = { lo = 1, hi = 3, int = true }, heavy_parts = { lo = 1, hi = 3, int = true },
    shaqi_parts = { lo = 1, hi = 3, int = true }, parts_per_s = { lo = 1, hi = 12, int = true },
    cap_look = { words = { basic = true, textured = true, game = true, native = true } },
    cap_scale = { lo = 0.7, hi = 1.5 },
    cap_fade_s = { lo = 0, hi = 30 }, piece_linger_s = { lo = 0, hi = 60 },
    hair_mode = { words = { burst = true, keep = true } }, extras_fall = {},
    gib_count = { lo = 0, hi = 12, int = true },
    corpse_keep_s = { lo = 0, hi = 3600 }, corpse_max = { lo = 1, hi = 200, int = true },
    drops = {}, drops_n = { lo = 0, hi = 24, int = true }, drops_max = { lo = 8, hi = 128, int = true },
    slicer = {}, soul_blood = {}, soul_face_blood = {}, sword_blood = {},
    cut_chance = { lo = 0, hi = 100, int = true }, other_ue4ss = {}, finisher_cuts = {},
}
C.LOG_LEVELS = { debug = true, info = true, warn = true, error = true }
-- MIGRATIONS[n] = function(s, M) -> report | nil, run for every n above the file's version, in order. M.base: the
-- file's base preset; M.marked(path): the value equals its v<n> marker (already migrated by a newer build).
C.MIGRATIONS = {
    -- v2 (route B, 2026-11-01): a stored textured Cap look moves to 'native', the new default. 'game' was the
    -- default and 'textured' draws the flat colours (tier A has no live parent), so neither was a choice the look
    -- has to keep; 'basic' (the flat colours chosen on purpose) stays
    [2] = function(s)
        local was = s.cap_look
        if was ~= 'game' and was ~= 'textured' then return nil end
        s.cap_look = 'native'
        return { cap_look = { from = was, to = 'native' } }
    end,
}
-- Values a migration rescales: { path = { 'sec', 'key' }, ver = n }; C.save writes the '<key>_v<n>' marker beside each
C.MARKED = {}

local A, fs, cfg = nil, nil, { base = 'settings', debounce_s = 1.0 }
local cur, view, seq = nil, nil, -1
local ov, ov_n = {}, 0
local listeners, dirty_at, generation, save_fail = {}, nil, 0, 0
C.migrated = nil

local function now_s() return (A and A.clock.real()) or 0 end

local function copy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end

local function overlay(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' then
            if type(dst[k]) ~= 'table' then dst[k] = {} end
            overlay(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

-- Fill dst from src: missing keys, wrong types and non-tables where a table belongs; a stored false stays false, the
-- words off/on in a boolean slot become false/true, a boolean in a word slot: false -> 'off', true -> src's word
local function fill(dst, src)
    for k, d in pairs(src) do
        local v = dst[k]
        if type(d) == 'table' then
            if type(v) ~= 'table' then dst[k] = {} end
            fill(dst[k], d)
        elseif type(d) == 'boolean' and (v == 'off' or v == 'on') then
            dst[k] = v == 'on'
        elseif type(d) == 'string' and v == false then
            dst[k] = 'off'
        elseif v == nil or type(v) ~= type(d) then
            dst[k] = copy(d)
        end
    end
    return dst
end

local function split(path)
    if type(path) == 'table' then return path end
    local out = {}
    for part in tostring(path):gmatch('[^.]+') do out[#out + 1] = part end
    return out
end

local function walk(t, path)
    for _, k in ipairs(path) do
        if type(t) ~= 'table' then return nil end
        t = t[k]
    end
    return t
end

local function put(t, path, v)
    for i = 1, #path - 1 do
        if type(t[path[i]]) ~= 'table' then t[path[i]] = {} end
        t = t[path[i]]
    end
    t[path[#path]] = v
end

local function deep_eq(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The named preset whose values and budgets apply: the current one, or the last named one while 'custom'
function C.base_preset(s)
    s = s or C.get()
    if C.PRESETS[s.preset] then return canon(s.preset) end
    if C.PRESETS[s.preset_base] then return canon(s.preset_base) end
    return 'maximum'
end

-- DEFAULTS overlaid by preset name (what a fill, a reset and apply_preset write)
local function base_values(name)
    return overlay(copy(DEFAULTS), C.PRESETS[name] or {})
end

-- The view modules read: cur itself, or a copy with the dev overrides on top (rebuilt on a change, never saved)
local function rebuild()
    generation = generation + 1
    if ov_n == 0 then view = cur return end
    view = copy(cur)
    for _, o in pairs(ov) do put(view, o.path, copy(o.v)) end
end

local function notify()
    for _, fn in ipairs(listeners) do pcall(fn, view) end
end

-- t[key .. '_v' .. ver] marks a value a build of that version already wrote: the migration must leave it alone
function C.marked(t, key, ver)
    if type(t) ~= 'table' then return false end
    local m = t[key .. '_v' .. ver]
    local v = t[key]
    if type(v) == 'number' and type(m) == 'number' then return math.abs(v - m) <= 1e-9 end
    return v ~= nil and v == m
end

-- A file with no version key at all was written by hand (every C.save writes one; mod/README.txt has players write
-- the settings file themselves), so it is in today's format: no step runs on it (review: v2 turned a hand-written
-- cap_look 'textured', Jamon Iberico, into 'native'). A version that does not read as a number is version 1
local function migrate(s)
    local ver = math.tointeger(tonumber(s.version)) or (s.version == nil and C.VERSION) or 1
    local report, base = nil, C.base_preset(s)
    for n = ver + 1, C.VERSION do
        local step = C.MIGRATIONS[n]
        if step then
            local M = { base = base, version = n }
            function M.marked(path)
                local p = split(path)
                local parent = walk(s, { table.unpack(p, 1, #p - 1) })
                return C.marked(parent, p[#p], n)
            end
            local ok, r = pcall(step, s, M)
            if not ok then r = { error = tostring(r) } end
            if r ~= nil then
                report = report or {}
                report['v' .. n] = r
            end
        end
    end
    for _, m in ipairs(C.MARKED) do                      -- the file's own markers, not settings
        local p = split(m.path)
        local parent = walk(s, { table.unpack(p, 1, #p - 1) })
        if type(parent) == 'table' then parent[p[#p] .. '_v' .. m.ver] = nil end
    end
    return report, ver
end

-- Read the file, migrate, fill from the base preset. Returns the settings table.
function C.load()
    local s, n = nil, -1
    if fs then s, n = STORE.load(fs, cfg.base) end
    if type(s) ~= 'table' then s, n = {}, -1 end
    seq, s._seq = n, nil
    local report, from = migrate(s)
    s.preset, s.preset_base = canon(s.preset), canon(s.preset_base)   -- an old id (full, lite) reads as the new one
    if s.preset ~= 'custom' and not C.PRESETS[s.preset] then s.preset = C.base_preset(s) end
    fill(s, base_values(C.base_preset(s)))
    if C.PRESETS[s.preset] then s.preset_base = s.preset end
    if not C.PRESETS[s.preset_base] then s.preset_base = 'maximum' end
    s.version = C.VERSION
    C.migrated = nil
    if report then
        C.migrated = { from = from, to = C.VERSION, steps = report }
        LOG.info('settings_migrated', C.migrated)
        dirty_at = now_s()                               -- saved once at the next quiet second
    end
    cur = s
    rebuild()
    notify()
    return view
end

function C.get() return view or C.load() end

-- A module's own section, {} when absent or of another type (a config typo must never throw)
function C.section(name)
    local ok, s = pcall(C.get)
    local t = ok and type(s) == 'table' and s[name]
    if type(t) == 'table' then return t end
    return {}
end

-- One type-strict reader: k -> the stored value when it has the default's type (a key without a default takes any)
-- and passes choices[k] (a set of words, or { lo, hi } clamping a number); else the base preset's; else the default
function C.section_opt(section, defaults, presets, choices)
    defaults = defaults or {}
    return function(k)
        local ok, s = pcall(C.get)
        if not ok or type(s) ~= 'table' then return defaults[k] end
        local t = s[section]
        local v = nil
        if type(t) == 'table' then v = t[k] end          -- a stored false stays false
        local d = defaults[k]
        local w = choices and choices[k]
        if v ~= nil and (d == nil or type(v) == type(d)) then
            if type(w) == 'table' and type(v) == 'number' and (w.lo or w.hi) then
                if w.lo and v < w.lo then v = w.lo end
                if w.hi and v > w.hi then v = w.hi end
                return v
            end
            if w == nil or w[v] then return v end
        end
        local p = presets and presets[C.base_preset(s)]
        if type(p) == 'table' and p[k] ~= nil then return p[k] end
        return d
    end
end

-- A word-valued setting: the stored word when choices[word] (any word without choices), else the base preset's,
-- else the default's
function C.word(path, choices)
    local p = split(path)
    local s = C.get()
    local v = walk(s, p)
    if type(v) == 'string' and (choices == nil or choices[v]) then return v end
    local b = walk(base_values(C.base_preset(s)), p)
    if type(b) == 'string' and (choices == nil or choices[b]) then return b end
    return walk(DEFAULTS, p)
end

-- A switch of effects: on unless the mod setting is off, or the switch is false or the word 'off'
function C.effect(name)
    local s = C.get()
    if s.enabled == false then return false end
    local e = type(s.effects) == 'table' and s.effects[name]
    return e ~= false and e ~= 'off'
end

function C.family_on(key)
    local f = C.get().families
    if type(f) ~= 'table' then return true end
    return f[key] ~= false and f[key] ~= 'off'
end

-- One beta knob (BD0), live: the stored value when it has its default's type and passes C.KNOBS (a number clamped, a
-- word in its set), else the DEFAULTS value; nil for a name that is no knob. s: a settings table to read instead of
-- C.get() (adapter/modsmenu.lua's effective values). Never throws
function C.knob(name, s)
    local spec, d = C.KNOBS[name], DEFAULTS[name]
    if spec == nil or d == nil then return nil end
    if s == nil then
        local ok, g = pcall(C.get)
        if ok then s = g end
    end
    local v = nil
    if type(s) == 'table' then v = s[name] end          -- a stored false stays false
    if v == nil or type(v) ~= type(d) then return d end
    if type(v) == 'number' then
        if v ~= v then return d end
        if spec.int then v = math.floor(v) end
        if spec.lo and v < spec.lo then v = spec.lo end
        if spec.hi and v > spec.hi then v = spec.hi end
        return v
    end
    if spec.words and not spec.words[v] then return d end
    return v
end

-- Stump modes (the author 2026-11-01: «let's make two stump modes in the settings and call them jamon serrano & jamon
-- iberico, with the game's stumps and custom ones respectively», then «so it won't be two modes but several? well,
-- name them yourself»): each cap_look is a mode the menu names after a ham. The game's own stumps: native Jamón
-- Serrano, game Jamón de Teruel. LeovvayGore's own: textured Jamón Ibérico, basic Paleta. C.stumps: 'game' or 'own';
-- our own stumps never take the game's slicer (lab_slice_route). s as in C.knob
C.STUMPS = { native = 'game', game = 'game', textured = 'own', basic = 'own' }
function C.stumps(s) return C.STUMPS[C.knob('cap_look', s)] or 'game' end

-- ---------- changes and the debounced save ----------
function C.gen() return generation end
function C.on_change(fn) listeners[#listeners + 1] = fn end
function C.dirty() return dirty_at ~= nil end

-- The stored settings (never the overrides) with the C.MARKED markers beside their values
function C.save()
    if not cur then return false, 'not_loaded' end
    local out = copy(cur)
    for _, m in ipairs(C.MARKED) do
        local p = split(m.path)
        local parent = walk(out, { table.unpack(p, 1, #p - 1) })
        if type(parent) == 'table' and parent[p[#p]] ~= nil then parent[p[#p] .. '_v' .. m.ver] = parent[p[#p]] end
    end
    out._seq = seq
    local ok, why = false, 'no_fs'
    if fs then ok, why = STORE.save(fs, cfg.base, out) end
    if ok then
        seq, dirty_at = out._seq, nil
        return true
    end
    save_fail = save_fail + 1
    if LOG.every('settings_save_fail', 60) then LOG.warn('settings_save_fail', { why = why, n = save_fail }) end
    dirty_at = now_s()                                   -- retried after the next quiet period
    return false, why
end

function C.flush_if_dirty()
    if dirty_at then return C.save() end
    return true
end

-- A change happened: listeners now (each under pcall), the save after cfg.debounce_s without another change
function C.touch(now)
    dirty_at = now or now_s()
    rebuild()
    notify()
end

function C.tick(now)
    if dirty_at and (now or now_s()) - dirty_at >= cfg.debounce_s then C.save() end
end

-- ---------- writers ----------
-- Copies only the preset's keys from DEFAULTS overlaid by it; everything else stays. An old id applies its new one
-- (C.PRESET_ALIASES); the second return value is the id applied.
function C.apply_preset(name)
    name = canon(name)
    if type(name) ~= 'string' or not rawget(C.PRESETS, name) then return false, 'unknown_preset' end
    C.get()
    local b = base_values(name)
    for k in pairs(C.PRESET_KEYS) do cur[k] = copy(b[k]) end
    cur.preset, cur.preset_base = name, name
    C.touch()
    return true, name
end

function C.set(path, value)
    local p = split(path)
    if #p == 0 then return false, 'bad_path' end
    C.get()
    put(cur, p, copy(value))
    if C.PRESET_KEYS[p[1]] and C.PRESETS[cur.preset] then
        cur.preset_base, cur.preset = cur.preset, 'custom'
    end
    C.touch()
    return true
end

-- The value path has in the base preset (nil for a key DEFAULTS does not hold, such as a module tuning key)
function C.preset_value(path) return copy(walk(base_values(C.base_preset()), split(path))) end

-- reset(paths): each path gets the base preset's value back (a key DEFAULTS does not hold is removed, so the module
-- default applies); a 'custom' preset whose owned keys all match its base again gets its name back.
-- reset() without paths is the module-contract reset (map change): a pending save is flushed.
function C.reset(paths)
    if type(paths) ~= 'table' then return C.flush_if_dirty() end
    C.get()
    local base = base_values(C.base_preset(cur))
    for _, path in ipairs(paths) do
        local p = split(path)
        if #p > 0 then put(cur, p, copy(walk(base, p))) end
    end
    if cur.preset == 'custom' then
        local same = true
        for k in pairs(C.PRESET_KEYS) do if not deep_eq(cur[k], base[k]) then same = false break end end
        if same then cur.preset = C.base_preset(cur) end
    end
    C.touch()
    return true
end

-- ---------- runtime-only dev overrides (the dev channel's 'set'; never saved) ----------
function C.override(path, value)
    local p = split(path)
    if #p == 0 then return false, 'bad_path' end
    C.get()
    local key = table.concat(p, '.')
    if ov[key] == nil then ov_n = ov_n + 1 end
    ov[key] = { path = p, v = copy(value) }
    rebuild()
    notify()
    return true
end

function C.clear_overrides()
    if ov_n == 0 then return 0 end
    local n = ov_n
    ov, ov_n = {}, 0
    rebuild()
    notify()
    return n
end

function C.overrides()
    local out = {}
    for k, o in pairs(ov) do out[k] = copy(o.v) end
    return out
end

-- ---------- lifecycle ----------
-- opts: base ('Mod/settings': the A/B file stem), debounce_s 1.0, ticker (false: no sched ticker 'config_save'). The
-- adapter calls C.tick from its independent frame callback either way (the ticker stops on the title screen); a
-- repeated tick is harmless
function C.init(adapter, opts)
    opts = opts or {}
    A, fs = adapter, adapter and adapter.fs
    cfg = { base = opts.base or 'settings', debounce_s = opts.debounce_s or 1.0 }
    cur, view, seq, ov, ov_n = nil, nil, -1, {}, 0
    listeners, dirty_at, save_fail = {}, nil, 0
    C.load()
    if opts.ticker ~= false then S.ticker('config_save', function() C.tick() end) end
    return true
end

function C.shutdown()
    C.flush_if_dirty()
    ov, ov_n = {}, 0
end

function C.status()
    local s = view or {}
    return { preset = s.preset, base = s.preset and C.base_preset(s) or nil, version = C.VERSION, gen = generation,
        dirty = dirty_at ~= nil, overrides = ov_n > 0 and ov_n or nil, save_fail = save_fail > 0 and save_fail or nil,
        migrated = C.migrated and C.migrated.from or nil }
end

return C
