-- status: worked DD2+SWZC origin: kb:dismember-core#p21
-- (worked: the DD2 JS writer and newest-first restore, SWZC HBN on leaders; untested: this dispatcher form)
-- also: kb:dismember-core#joint-scale-hide-on-body-plus-every-equipment-slot-dd2-js-jsr-in-preparerendering
-- hide.lua: the Part-removal dispatcher. It never touches the engine: the adapter supplies one writer per technique,
-- and this module decides WHEN a hide happens and keeps the records.
-- Rules (each from a real failure):
-- * Never hide a Part unless its visible replacement shows in the same frame (kb:dismember-core#p21). A cut is STAGED;
--   in the render phase it commits only in the frame every replacement it needs (cut.needs, default the Cap) reports
--   live, so the first write and the show share a frame. Past wait_frames it drops with cut_fail no_replacement: a
--   DD2 frozen shatter made bodies 'just vanish', and a hide in the kill frame blinked the body for 3+ frames.
-- * Never read your own visual state back from transforms (kb:dismember-core#p20): ragdolled corpses are re-posed
--   every frame. H.is_cut reads the records only.
-- * Save the values each write replaces and restore NEWEST FIRST to them, never to 1.0 (kb:dismember-core#p37):
--   another mod may have scaled a joint first, and a hand cut inside an arm cut comes back right only in that order.
-- * The first write of each technique runs under the crash sentinel ('hide.<tech>.first_write', arm-once), and first
--   writes are capped at first_write_cap joints per frame (about two DD2 Bisects; the oldest op always goes).
-- * Writers with every_frame write each render frame while live (REF JS: corpses reset every joint every frame);
--   others write once and H.reassert(v) repeats it after an engine reset (UE: RefreshCustomization unhides bones).
-- * Budget from day one (kb:dismember-core#p38): every_frame writes skip a victim that is off-screen AND farther than
--   cull_m (A.visible; counted in status culled) and resume in the frame it is visible again. DD2 case: 179 Victims,
--   383 ops and 8,806 joint writes per frame cost 9.7 ms (18 fps) until the 600-joint first-write cap and this view
--   cull. Also give the mod a corpse cap: its Victims limit must be able to drop far, off-screen cut corpses (DD2's
--   never dropped a record with a Cut) through 'restore' or 'victim_gone'; party victims are never dropped.
-- * DESIGN C5, four operations never mixed (spec M0 S1.8, D17). (1) A closed gate (hide.enabled off, mod-off, the
--   vanilla compare) stops NEW requests only: H.can and H.request refuse. A staged op whose replacement already shows
--   still commits (else its Cap sits on a whole limb); under mod-off or the compare one whose replacement does not show
--   drops with cut_fail 'gate:modoff' (caps_attach drops its Cap request in the same gate, so no Stump opens later),
--   while hide.enabled off alone lets it wait for the Cap still coming (or time out). Committed hides stay,
--   every_frame writes and H.reassert keep running while the gate is closed (upkeep). (2) Mod-off hides loose objects only: hide.lua has no mod_off listener and no
--   live() list, a hidden Part is not a loose object. (3) Restore runs on the 'restore' event only and (4) the
--   'victim_gone' event drops records with no engine call. H.shutdown (unload) restores everything, as before.
--   Review-2 repro: mod_off restore_all and a gate-fail restore_all un-cut every corpse while its Cap was destroyed.
-- ADAPTER CONTRACT:
--   A.hide_writers[tech] = { save(v, op) -> prior, write(v, op) -> true, restore(v, op, prior) -> true,
--                            count(v, op)? -> joints written, every_frame = bool }
--     Case (DD2): 'JS' = set_LocalScale 1e-3 (never 0: segmentScaling makes 0 singular) on the subtree of the body and
--     every equipment slot, in PrepareRendering; then the INWARD COLLAPSE: with op.collapse_k (the per-cut k from the
--     Cap manifest row, e.g. neck 0.6, arm 0.15) the writer sets the cut joint's LocalPosition = BaseLocalPosition x k
--     right after the scale write, so the skin cone folds behind the Cap; k nil or 1 writes nothing, chain-driven
--     joints never; save() keeps the prior LocalPosition and restore() puts it back (kb:stumps-caps, caps.md
--     'Inward collapse'). Case (SWZC): 'HBN' = HideBoneByName on every leader component that
--     has the bone (followers ignore it), once, re-asserted after a customization refresh.
--   A.replacement[kind](v, cut) -> true once that replacement is visible this frame ('cap', 'piece', ...)
--   A.visible(v) -> on_screen (bool), dist (m) - optional, asked once per victim per frame; absent = never culled
-- op = { v, id, part, tech, root, needs, collapse_k, f0, state = 'staged' | 'live', prior, n };
-- cut = { part, tech, root, needs, collapse_k? }
-- Evidence: [worked DD2] hide.lua 1-110, 441-672 (add/restore), 742-794 (first writes cap 600); [worked SWZC]
-- cut_human.lua leaders_with_bone, verify/reapply; staging [untested]
-- kb:dismember-core#deferred-atomic-commit-for-a-two-piece-split-dd2
-- kb:dismember-core#hide-a-limb-on-ue-modular-characters-hidebonebyname-on-every-leader-component-swzc
local NAME0 = (...) or 'features.hide'
local PFX, SEP = NAME0:match('^(.-)features([./])[^./]*$')
if not PFX then PFX, SEP = '', '.' end
local LOG = require(PFX .. 'core' .. SEP .. 'log')
local S = require(PFX .. 'core' .. SEP .. 'sched')
local BUS = require(PFX .. 'core' .. SEP .. 'bus')
local C = require(PFX .. 'core' .. SEP .. 'config')
local MO = require(PFX .. 'core' .. SEP .. 'modoff')
local SENT = require(PFX .. 'core' .. SEP .. 'sentinel')

local H = { name = 'hide' }
H.DEFAULTS = {
    enabled = true,          -- ships on
    wait_frames = 30,        -- frames a staged hide waits for its replacement (Caps show a stand-in at frame 12)
    first_write_cap = 600,   -- joints per frame for first writes; the oldest op always goes
    cull_m = 6,              -- every_frame writes skip off-screen victims farther than this (DD2 view cull)
    tech = 'JS',             -- technique when the cut names none
}
local opt = C.section_opt('hide', H.DEFAULTS)
H.opt = opt

local A = nil
local st = { staged = {}, live = {}, by_v = {}, proven = {}, writes = 0, first = 0, culled = 0, fails = {} }

local function sent_name(tech) return 'hide.' .. tostring(tech) .. '.first_write' end
local function writer_of(tech) return A and A.hide_writers and A.hide_writers[tech] end

local function fail(op, err)
    st.fails[err] = (st.fails[err] or 0) + 1
    LOG.warn('cut_fail', { id = op.id, part = op.part, tech = op.tech, err = err })
    return nil, err
end

-- Records only: is this Part of this victim hidden (or staged to be)?
function H.is_cut(v, part)
    for _, op in ipairs(st.by_v[v.id] or {}) do if op.part == part then return true, op.state end end
    for _, op in ipairs(st.staged) do if op.id == v.id and op.part == part then return true, 'staged' end end
    return false
end
function H.cuts(v)
    local out = {}
    for _, op in ipairs(st.by_v[v.id] or {}) do out[#out + 1] = op.part end
    return out
end

-- Could this Part be hidden with this technique now? (kill's ladder asks before it picks a rung; with hide off kill
-- promises no cut, so no Cap or Piece shows on a whole limb)
function H.can(v, part, tech)
    local okg, whyg = H.gate()
    if not okg then return false, whyg end
    tech = tech or opt('tech')
    if tech == 'joint' then tech = (A and A.joint_tech) or opt('tech') end
    if not writer_of(tech) then return false, 'no_writer' end
    if SENT.is_disabled(sent_name(tech)) then return false, 'sentinel' end
    if v and H.is_cut(v, part) then return false, 'already_cut' end
    return true, tech
end

-- Stage a hide (no engine call): it commits in the render phase of the frame its replacements show
function H.request(v, cut)
    local tech = cut.tech or opt('tech')
    local op = { v = v, id = v.id, part = cut.part, tech = tech, root = cut.root or cut.part, f0 = S.frame,
        needs = cut.needs or { 'cap' }, state = 'staged', cut = cut, collapse_k = tonumber(cut.collapse_k) }
    local ok, why = H.can(v, cut.part, tech)
    if not ok then return fail(op, why) end
    op.tech = why
    for _, kind in ipairs(op.needs) do
        if not (A.replacement and A.replacement[kind]) then return fail(op, 'no_provider:' .. kind) end
    end
    st.staged[#st.staged + 1] = op
    return op
end

local function all_live(op)
    for _, kind in ipairs(op.needs) do
        local ok, live = pcall(A.replacement[kind], op.v, op.cut)
        if not (ok and live == true) then return false end
    end
    return true
end

local function commit(op, w, skip_wait)
    local okp, prior = pcall(w.save, op.v, op)
    if not okp then return fail(op, 'save:' .. tostring(prior)) end
    local r, err = SENT.risky(sent_name(op.tech), st.proven, op.tech, nil, w.write, op.v, op)
    if r == nil then return fail(op, tostring(err)) end
    op.state, op.prior, op.f1 = 'live', prior, S.frame
    local list = st.by_v[op.id] or {}
    list[#list + 1] = op
    st.by_v[op.id] = list
    st.live[#st.live + 1] = op
    st.first = st.first + 1
    LOG.info('cut', { id = op.id, part = op.part, tech = op.tech, waited = S.frame - op.f0,
        adopted = skip_wait or nil })
    return op
end

-- Restore one victim's live hides, newest first, to the values they replaced
local function restore_v(id, why, engine)
    local list = st.by_v[id]
    if not list then return 0 end
    for i = #list, 1, -1 do
        local op = list[i]
        local w = writer_of(op.tech)
        if engine ~= false and w and w.restore then
            local ok, err = pcall(w.restore, op.v, op, op.prior)
            if not ok then LOG.warn('cut_fail', { id = id, part = op.part, err = 'restore:' .. tostring(err) }) end
        end
        op.state = 'restored'
    end
    st.by_v[id] = nil
    local keep = {}
    for _, op in ipairs(st.live) do if op.state == 'live' then keep[#keep + 1] = op end end
    st.live = keep
    LOG.info('restore', { id = id, n = #list, why = why })
    return #list
end
function H.restore(v, why) return restore_v(v.id, why or 'restore') end
local function restore_all(why)
    local ids = {}
    for id in pairs(st.by_v) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do restore_v(id, why) end
    st.staged = {}
end

function H.gate()
    if opt('enabled') == false then return false, 'off' end
    if not MO.enabled(H.name) then return false, 'modoff' end
    if not (A and A.hide_writers) then return false, 'no_adapter' end
    return true
end

-- The render-phase writer: commit staged ops whose replacements show this frame, then the always-write ops. A closed
-- gate stops new work only (C5 operation 1): it never restores a live hide and the upkeep writes keep running
local function writer()
    if not (A and A.hide_writers) then return end
    local open, why = H.gate()
    local cap, used, keep, frame = opt('first_write_cap'), 0, {}, S.frame
    for _, op in ipairs(st.staged) do
        local w = writer_of(op.tech)
        if not w then
            fail(op, 'no_writer')
        elseif frame - op.f0 > opt('wait_frames') then
            fail(op, 'no_replacement')
        else
            local live = all_live(op)
            local n = w.count and w.count(op.v, op) or 1
            if live and (used == 0 or used + n <= cap) then
                used = used + n
                commit(op, w)
            elseif not open and why == 'modoff' and not live then
                -- mod-off and the compare close the Cap gate too (caps_attach drops a request with no Cap yet), so
                -- its replacement never comes: drop now, no Stump opens. hide.enabled off alone leaves the Cap request
                -- alive: the op keeps waiting and commits with its Cap (never a Cap on a whole limb) or times out
                fail(op, 'gate:' .. tostring(why))
            else
                keep[#keep + 1] = op
            end
        end
    end
    st.staged = keep
    local cm = opt('cull_m')
    local cull_m, shown = A.visible and tonumber(cm), {}
    for _, op in ipairs(st.live) do
        local w = writer_of(op.tech)
        if w and w.every_frame and op.f1 ~= frame then
            local vis = shown[op.id]
            if vis == nil then                              -- one visibility read per victim per frame
                vis = true
                if cull_m then
                    local okv, on, dist = pcall(A.visible, op.v)
                    vis = not (okv and on == false and tonumber(dist) and tonumber(dist) > cull_m)
                end
                shown[op.id] = vis
            end
            if vis then
                local okw = pcall(w.write, op.v, op)
                if okw then st.writes = st.writes + 1 end
            else
                st.culled = st.culled + 1
            end
        end
    end
end

-- A script reset or hot reload: the joints are still hidden and the replacement exists, so commit at once (no
-- replacement wait) with the prior the old state handed over (saving now would read our own 1e-3 back)
function H.adopt(v, cut, prior)
    local op = { v = v, id = v.id, part = cut.part, tech = cut.tech or opt('tech'), root = cut.root or cut.part,
        f0 = S.frame, needs = {}, state = 'staged', cut = cut, collapse_k = tonumber(cut.collapse_k) }
    local w = writer_of(op.tech)
    if not w then return fail(op, 'no_writer') end
    if prior == nil then return commit(op, w, true) end
    return commit(op, { save = function() return prior end, write = w.write }, true)
end
-- Write once-writers again after an engine event that resets draw state
function H.reassert(v)
    for _, op in ipairs(st.by_v[v.id] or {}) do
        local w = writer_of(op.tech)
        if w and not w.every_frame then pcall(w.write, op.v, op) end
    end
end

-- Lifecycle
function H.init(adapter, opts)
    A = adapter or {}
    st = { staged = {}, live = {}, by_v = {}, proven = {}, writes = 0, first = 0, culled = 0, fails = {} }
    if not A.hide_writers then
        LOG.info('adapter_missing', { module = H.name, fn = 'hide_writers', why = 'no hides' })
    end
    if not A.replacement then
        LOG.info('adapter_missing', { module = H.name, fn = 'replacement',
            why = 'no hide can commit (needs a replacement)' })
    end
    BUS.on('cut', H.name, function(v, cut) H.request(v, cut) end)
    BUS.on('restore', H.name, function(v, why) restore_v(v.id, why or 'restore') end, { teardown = true })
    BUS.on('victim_gone', H.name, function(v) restore_v(v.id, 'gone', false) end, { teardown = true })
    -- no mod_off listener: mod-off hides loose objects only and changes no cut (C5 operation 2)
    MO.feature(H.name, { gameplay = true })
    S.writer(H.name, writer)
    return true
end
function H.shutdown(reason)
    restore_all(reason or 'shutdown')
    S.remove_writer(H.name)
    for _, ev in ipairs({ 'cut', 'restore', 'victim_gone' }) do BUS.off(ev, H.name) end
end
-- A map change: the bodies went with the old world (no engine call on them)
function H.reset()
    st.staged, st.live, st.by_v = {}, {}, {}
end
function H.status()
    return { staged = #st.staged, live = #st.live, writes = st.writes, first = st.first, culled = st.culled,
        fails = st.fails }
end
function H.ui_status() return string.format('hide: %d live, %d staged', #st.live, #st.staged) end
-- What the next Lua state adopts (H.adopt): every live hide with the prior it saved
function H.handoff()
    local out = {}
    for _, op in ipairs(st.live) do
        out[#out + 1] = { id = op.id, part = op.part, tech = op.tech, root = op.root, prior = op.prior }
    end
    return out
end

return H
