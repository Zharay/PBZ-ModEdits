-- status: worked SWZC origin: kb:runtime-safety-perf#whole-mod-off-toggle
-- modoff.lua: the whole-mod off switch and the vanilla compare. Both are module-local state: a hot reload starts on.
-- OFF (M.off(via), player key Ctrl+F8: bare F8 was too easy to hit): flush first (opts.flush: settings, persistence),
--   block every registered feature, unhook (ops.unhook_all: on UE HOOKS.unregister_all, which keeps the hooks of
--   lifecycle consumers registered, M0 S2.2), drop the log to warn, and HIDE, never destroy, only our visible loose
--   objects (each feature's live() list, checked with ops.ours and ops.visible), logged as one list. ON restores
--   exactly what OFF changed: rehook, the earlier log level, unblock, show exactly that list (still ours).
--   A features-only toggle left hooks, logging and gibs behind, so off covers all of it.
-- DESIGN C5 (spec M0 S1.8, D17): four operations, never mixed. (1) Stop new effects: off, the vanilla compare, a
--   feature switch, a preset; this module only closes the gates (M.enabled). (2) Hide loose objects: off only, and
--   reversible. A feature's live() lists loose objects only (Pieces with their end Caps, gibs, pools, decals,
--   lingering FX), never a hidden Part or a Cap whose Stump shows: neither press changes a cut. (3) Restore a victim
--   and (4) drop records run on their own bus events ('restore', 'victim_gone'), never on mod_off, and their lifecycle
--   hooks stay registered while off, so no living actor shows a cut and no Stump opens. A mod_off listener may hide
--   or show its own loose objects; it never restores, clears or destroys (the review-2 repro: hide.lua restore_all and
--   caps_attach clear_all on mod_off un-cut every corpse and destroyed its Caps).
-- VANILLA (M.vanilla(via), Shift+F7): blocks the gameplay features (M.FEATURES and feature(name, {gameplay = true}))
--   that are not blocked yet, and the second press unblocks exactly that list. Hooks, logging and re-apply stay on.
-- They refuse each other: Ctrl+F8 -> Shift+F7 -> Ctrl+F8 once left the compare stuck on. A refused press is logged
--   with refused = the other switch. Settings are never written by either: a preset switched meanwhile applies at once
--   to the settings and its features come back with the mod.
-- Log: modoff { on = mod-off active after the press, mod = 'off'|'on', via, features, hooks, hidden|shown, list } at
--   warn (still visible at the lowered level); list = the names of the objects that press hid or showed (the second
--   press's list is the first one's, less what is no longer ours); the second press also logs list_diff = hidden
--   minus shown (0 when every hidden object came back; spec M1a D14, L8); vanilla { on, via, features } at info,
--   written whatever the level.
--   The bus gets mod_off(on) (teardown listeners).
-- Adapter ops (A.modoff, or opts.ops): unhook_all() -> n, rehook_all() -> n, hide(obj, kind), show(obj, kind),
--   visible(obj, kind) -> bool, ours(obj, name) -> bool. kind is the live() entry's own: 'actor' for an own actor (a
--   Piece), nil for a component; this module only passes it on. Engine work runs where the adapter calls M.off/M.on
--   (UE4SS: a key press is counted on the update thread and the tick runs the handler). M.shutdown is engine-free (OnUnload runs off the game thread).
-- API (stable): M.init(A, opts) feature(name, {live, gameplay}) enabled([name]) off on toggle vanilla is_off
--   is_vanilla reset shutdown status; M.KEYS, M.FEATURES.
-- Evidence: [worked SWZC] lib/mod_off.lua, main.lua vanilla action (refused while off);
-- kb:persistence-settings-api#vanilla-compare-toggle-and-mod-off-switch
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')
local BUS = require(BASE .. 'bus')

local M = {}
M.KEYS = { modoff = 'Ctrl+F8', vanilla = 'Shift+F7' }

-- Gameplay features the vanilla compare switches off. add-feature inserts a quoted name above the anchor line.
M.FEATURES = {
    -- <<gore:modoff>>
}

local ops, flush = {}, {}
local feats, order = {}, {}
local st = { off = false, vanilla = nil, blocked = {}, hidden = nil, level = nil }

local LEVEL_ORDER = { 'debug', 'info', 'warn', 'error' }
local function log_level()
    for _, l in ipairs(LEVEL_ORDER) do if LOG.enabled(l) then return l end end
    return 'error'
end

local function call(name, ...)
    local fn = ops[name]
    if type(fn) ~= 'function' then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
    LOG.warn('call_fault', { key = 'modoff:' .. name, err = tostring(r) })
    return nil
end

local function gameplay(name)
    local f = feats[name]
    if f and f.gameplay ~= nil then return f.gameplay end
    for _, n in ipairs(M.FEATURES) do if n == name then return true end end
    return false
end

-- opts: ops (else A.modoff), flush = { fn, ... } run before the mod goes off
function M.init(adapter, opts)
    opts = opts or {}
    ops = opts.ops or (adapter and adapter.modoff) or {}
    flush = opts.flush or {}
    feats, order = {}, {}
    st = { off = false, vanilla = nil, blocked = {}, hidden = nil, level = nil }
    for _, n in ipairs(M.FEATURES) do M.feature(n, { gameplay = true }) end
    return true
end

-- A feature the switches gate. live() -> { { obj = o, name = n, kind = k }, ... }: the visible things it left in the
-- world (kind 'actor' for an own actor, nil for a component)
function M.feature(name, opts)
    opts = opts or {}
    if not feats[name] then order[#order + 1] = name end
    local gp = opts.gameplay
    if gp == nil and feats[name] then gp = feats[name].gameplay end
    feats[name] = { live = opts.live, gameplay = gp }
end

-- The gate features ask: false while the mod is off, or while this feature is blocked (vanilla compare)
function M.enabled(name)
    if st.off then return false end
    if name ~= nil and st.blocked[name] then return false end
    return true
end
function M.is_off() return st.off end
function M.is_vanilla() return st.vanilla ~= nil end

local function hide_all()
    local out, seen = {}, {}
    for _, name in ipairs(order) do
        local f = feats[name]
        if f and type(f.live) == 'function' then
            local ok, list = pcall(f.live)
            if ok and type(list) == 'table' then
                for _, x in ipairs(list) do
                    if type(x) == 'table' and x.obj ~= nil and not seen[x.obj] and call('ours', x.obj, x.name) == true
                        and call('visible', x.obj, x.kind) ~= false then
                        seen[x.obj] = true
                        call('hide', x.obj, x.kind)
                        out[#out + 1] = { obj = x.obj, name = x.name, kind = x.kind }
                    end
                end
            end
        end
    end
    return out
end
-- The logged list: one name per object, in the order off hid them
local function names(list)
    local out = {}
    for i, x in ipairs(list) do out[i] = x.name ~= nil and tostring(x.name) or tostring(x.obj) end
    return out
end

function M.off(via)
    if st.off then return false, 'already' end
    if st.vanilla then
        LOG.warn('modoff', { on = false, mod = 'on', via = via, refused = 'vanilla' })
        return false, 'vanilla'
    end
    for _, fn in ipairs(flush) do pcall(fn) end          -- files written before anything stops
    st.off, st.blocked = true, {}
    for _, name in ipairs(order) do st.blocked[name] = 'modoff' end
    local hooks = call('unhook_all')
    st.hidden = hide_all()
    st.level = log_level()
    LOG.warn('modoff', { on = true, mod = 'off', via = via, features = #order, hooks = hooks, hidden = #st.hidden,
        list = names(st.hidden), msg = 'the whole mod is off; the same key turns it back on' })
    LOG.level('warn')
    BUS.emit('mod_off', true)
    return true
end

function M.on(via)
    if not st.off then return false, 'already' end
    if st.level then LOG.level(st.level) end
    local hooks = call('rehook_all')
    local hidden, shown = st.hidden or {}, {}
    for _, x in ipairs(hidden) do
        if call('ours', x.obj, x.name) == true then
            call('show', x.obj, x.kind)
            shown[#shown + 1] = x
        end
    end
    st.off, st.blocked, st.hidden, st.level = false, {}, nil, nil
    LOG.warn('modoff', { on = false, mod = 'on', via = via, features = #order, hooks = hooks, shown = #shown,
        list = names(shown), list_diff = #hidden - #shown })
    BUS.emit('mod_off', false)
    return true
end

function M.toggle(via)
    if st.off then return M.on(via) end
    return M.off(via)
end

-- The vanilla compare, a toggle: refused while the mod is off
function M.vanilla(via)
    if st.off then
        LOG.write('info', 'vanilla', { on = false, via = via, refused = 'modoff' }, true)
        return false, 'modoff'
    end
    if st.vanilla then
        for _, name in ipairs(st.vanilla) do st.blocked[name] = nil end
        LOG.write('info', 'vanilla', { on = false, via = via, features = st.vanilla }, true)
        st.vanilla = nil
        return true
    end
    local list = {}
    for _, name in ipairs(order) do
        if gameplay(name) and not st.blocked[name] then
            st.blocked[name] = 'vanilla'
            list[#list + 1] = name
        end
    end
    st.vanilla = list
    LOG.write('info', 'vanilla', { on = true, via = via, features = list }, true)
    return true
end

-- A map change: the hidden objects went with the old world; the switches stay as they are
function M.reset()
    if st.off then st.hidden = {} end
end

-- Unload: engine-free; a hot reload starts with the mod on
function M.shutdown()
    st = { off = false, vanilla = nil, blocked = {}, hidden = nil, level = nil }
end

function M.status()
    local n = 0
    for _ in pairs(st.blocked) do n = n + 1 end
    return { off = st.off, vanilla = st.vanilla ~= nil, blocked = n, hidden = st.hidden and #st.hidden or 0,
        features = #order }
end

return M
