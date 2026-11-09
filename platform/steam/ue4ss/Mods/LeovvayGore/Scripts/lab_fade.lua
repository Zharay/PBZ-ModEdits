-- status: new in beta BD13 (offline only; the author's run decides) origin: docs/research/beta-dismemberment-research.md#multi-part-cut-at-death-on-a-vanilla-corpse-and-what-dissolve-and-destroy-do-to-our-objects
-- lab_fade.lua: the dissolve probe and the Cap fade (docs/research/beta-dismemberment-plan.md BD13; research MC7, MC9
-- without its hooks). Player beta only (META.beta_modules, after lab_gib); the probe and dev profiles never require
-- it, and init stays inert (no listener, no ticker, no record) unless LAB.beta(). META.beta_fade false keeps the record
-- and drops the writes (the resync and the fade). It makes no native call before LAB.pinned() reads true.
-- * Tracking: bus lab_cut_live(cut) queues the cut; its corpse (cut.id, one entry for every cut of one death) opens
--   at the next tick, at most CORPSES at once. The listeners only queue; a lab_death or a lab_cut_live seen this frame
--   or the frame before, or lab_cut's K.status().jobs > 0, makes a busy frame: nothing is read or written in it.
-- * The dissolve record per cut corpse (forced, one per corpse): sampled every SAMPLE_S game seconds from the first
--   commit until the corpse reads destroying (LAB.alive), WINDOW_S, or lab_end; at most PER_FRAME corpses a frame,
--   never while paused, off or under the vanilla compare. Each sample is one LAB.armed('lab.read.dissolve') call
--   (linger 0, after SENT.is_disabled and LAB.sig: a refused class ends every corpse at once, why 'disabled' or the sig
--   word):
--   - the actor's bHidden; the leader's bVisible, bHiddenInGame and RelativeScale3D.X (shrink under SHRINK);
--   - the leader's slot materials (GetNumMaterials, GetMaterial: identity by address and name, at most MAT_MAX) and, on
--     a MaterialInstanceDynamic slot 0 only, K2_GetScalarParameterValue of STAMP and DUR;
--   - HairDissolveComponent BeginDissolveTime, 'Dissolve Time' and CurrentDissolveIntensity (BP_NPC_Base_C);
--   - the four keep levers on their declaring classes (DisableDeathDissol, 'Death Delay', DestroyAfterDead,
--     DestroyDelay; read only, never written): kept now when DisableDeathDissol reads true or DestroyAfterDead false;
--   - every hidden head component that reads drawn again; each cut's Stump and Piece-end Cap drawn (lab_cap C.state).
--   No DissolveMesh TArray read. Snapshots at 'first', 'signal', 'fade' and 'last' add per Piece lab_piece's
--   P.probe (slot 0 shared with its source, bHidden, resyncs) and per cut the Caps drawn and whether the Stump Cap's
--   slot 0 is still the one of the first snapshot ('last' reads properties only: the corpse is going). The engine time
--   of the first sample comes from one LAB.armed('probe.static.GetTimeSeconds') (P-a; STAMP is in engine seconds).
--   The record: id, class, parts, why ('destroyed', 'collected', 'reused', 'stale', 'window', 'lab_end', 'map',
--   'revive', 'disabled', the sig word), samples, the first values (v0), the first time (s since the death) each
--   tracked value changed (first), the transitions (tr, at most TR_MAX, tr_drop beyond), lev0 and lev1, mats1 (the
--   first slot change: n changed, of, mid), stamp1, start, fade, resyncs, snaps, and piece_lag_s: the real seconds
--   from the corpse reading gone to its last Piece's destroy (lab_piece's body_gone eviction), waited TAIL_S at most.
-- * The decision (MC7; META.beta_fade, the cap_fade_s knob above 0, read at each use), for cuts with kept not true
--   (cut.kept and the levers read now) and not faded, never while off or under the vanilla compare:
--   - the actor hidden or the leader not drawn: fade now (fade_why 'hidden');
--   - the start: the first slot-material change against the first sample, or a STAMP change on slot 0. Every live
--     Piece of the corpse is resynced (LAB.armed('piece.mesh', P.resync, piece)), and again at each later slot change.
--     The fade is due at the start + cap_fade_s (fade_why 'signal'), or at STAMP + STAMP_K x DUR in engine time when
--     both read above 0 and that lies 0..DELAY_MAX_S ahead ('stamp');
--   - the fade: LAB.armed('hide.comp', C.fade, cut.slot), then cut.faded, cut.fade_t (real s) and cut.fade_why. A
--     refused or held fade is tried again at the next tick while the corpse is sampled;
--   - no signal, no fade: never a timer from the death.
-- The cut contract (lab_cut's cut table; bus lab_cut_live(cut) and lab_cut_gone(cut) pass the same table), pinned for
-- every reader (lab_cap, lab_piece, lab_hold, lab_blood, lab_gib and this module). Today's fields stay; BD10 adds:
--   * rank: 1 for the primary (the struck part, else the head), 2 .. nparts for the extras in their order; nparts: the
--     parts planned for the kill; tier: kill.tier; at_death: true for the beta's death-time jobs (the 120 s limb path
--     of the lab keeps nil). The job table carries the same rank, nparts, part, row and at_death, and for a head
--     head_mode and hair (lab_gib's G.head_mode, resolved in on_row or the stage).
--   * class: the victim class; class_row: the data/cut_classes.lua row (d.class_row of the 'heads' row).
--   * kept: true when DisableDeathDissol reads true or DestroyAfterDead reads false (a LingeringDead body), false on
--     the vanilla values, 'unread' when a read failed (treated as vanilla); levers = { disable_dissol, death_delay,
--     destroy_after, destroy_delay } as read in the stage ('unread' each when not read). Read only, never written.
--   * faded: nil until the fade hid the Caps, then true; fade_t (real s), fade_why ('hidden' | 'signal' | 'stamp').
--     Written here, and by lab_corpse when a kept body it lets go vanishes (fade_why 'corpse'). lab_cut's K.reassert
--     never shows a faded Cap; lab_hold counts a faded Cap as ok, never open_stump.
--   * expired: nil, or true once lab_corpse let the kept body go: lab_piece and lab_gib then treat it as not kept.
--   * size (cut.size: lab_look.lua's header), head_mode, hair, hold_show and gib (lab_gib.lua's header), hide_set,
--     opt_missing and extra_hidden (the per-cut record fields of BD10).
-- The calls this module makes on its siblings, pinned (each may be absent until its group lands: check the field):
--   * lab_cap C.fade(slot) -> the number hidden: both ends of the slot hidden with ue.set_hidden, slot.faded set;
--     C.show never shows a faded slot again. It arms nothing: the caller runs LAB.armed('hide.comp', C.fade,
--     cut.slot), then sets cut.faded, fade_t and fade_why.
--   * lab_piece P.resync(piece) -> the slots copied, why: each poseable's materials copied again from its live source
--     (GetMaterial, SetMaterial), piece.resynced counted. It arms nothing: the caller runs LAB.armed('piece.mesh',
--     P.resync, cut.piece). P.probe(piece[, opts]) (BD12): the Piece's reads for the snapshots, run inside this
--     module's 'lab.read.dissolve'.
--   * Pieces follow the body (lab_piece BD12, MC6; the author's answer 10): on lab_cut_gone with cut.gone_why
--     'destroyed' or 'collected' and cut.kept not true, the Piece is evicted piece_linger_s later (the knob; 0 at
--     once), one per frame under 'piece.destroy', why 'body_gone'; a revive keeps it; a kept body keeps FIFO and LIFE.
--     lab_gib does the same for its own objects under 'gib.destroy'.
-- API: tracked() the open corpses (tests); lifecycle init(A) shutdown() status() reset(reason).
-- What the mock cannot prove: native faults, UE4SS marshalling on dff435dd (the FName argument of
-- K2_GetScalarParameterValue), whether any signal fires on a vanilla corpse and when (the run measures it), the look of
-- the fade.
local META = require('meta')
local CFG = require('core.config')
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local US = require('adapter.ue_spawn')
local LAB = require('lab_probe')

local FADE = { SAMPLE_S = 0.25, WINDOW_S = 30, TAIL_S = 5, TR_MAX = 24, PER_FRAME = 4, CORPSES = 32, INBOX = 64,
    MAT_MAX = 16, STAMP_K = 0.7, SHRINK = 0.99, DELAY_MAX_S = 30, ERR_CHARS = 160, NAME = 'lab.read.dissolve',
    STAMP = 'DeathDissolve_TimeStamp', DUR = 'DeathDissolve_AniDuration',      -- research MC9 P-c [inferred names]
    MID = '/Script/Engine.MaterialInstanceDynamic',
    RENEWAL = '/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C',
    NPC_BASE = '/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C' }
-- The keep levers on their declaring class (lab_keep's rows): read only
FADE.LEVERS = { { key = 'disable_dissol', prop = 'DisableDeathDissol', cls = 'RENEWAL' },
    { key = 'death_delay', prop = 'Death Delay', cls = 'RENEWAL' },
    { key = 'destroy_after', prop = 'DestroyAfterDead', cls = 'NPC_BASE' },
    { key = 'destroy_delay', prop = 'DestroyDelay', cls = 'NPC_BASE' } }
-- The values a sample tracks (transitions only); the continuous ones keep their first change, not every change
FADE.TRACK = { 'hidden', 'lvis', 'lhig', 'shrink', 'scale', 'mats', 'nmats', 'mid0', 'stamp', 'dur', 'hair_begin',
    'hair_time', 'hair_int', 'kept', 'reshown' }
FADE.FIRST_ONLY = { scale = true, hair_int = true }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua 'lab.read.dissolve')
local N = {}
local F = {
    {"/Script/Engine.Actor", "bHidden"},
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SceneComponent", "bVisible"},
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.SceneComponent", "RelativeScale3D"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "HairDissolveComponent"},
    {"/AkashaEffects/GroomWindSystem/Blueprint/HairDissolveComponent.HairDissolveComponent_C", "BeginDissolveTime"},
    {"/AkashaEffects/GroomWindSystem/Blueprint/HairDissolveComponent.HairDissolveComponent_C", "Dissolve Time"},
    {"/AkashaEffects/GroomWindSystem/Blueprint/HairDissolveComponent.HairDissolveComponent_C",
        "CurrentDissolveIntensity"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "DisableDeathDissol"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "Death Delay"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyAfterDead"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyDelay"},
}
FADE.N, FADE.F = N, F

local A = nil
local function new_state()
    return { init = false, list = {}, by_id = {}, liveq = {}, goneq = {}, qdrop = 0, dropped = 0, busy_f = nil,
        end_due = false, ended = false, records = 0, samples = 0, fails = 0, fades = 0, resyncs = 0, busy = 0,
        holds = 0, sig_why = nil, last_err = nil }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function gnow() return S.game_time or 0 end
local function text(s)
    s = tostring(s)
    return #s > FADE.ERR_CHARS and s:sub(1, FADE.ERR_CHARS) or s
end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function bool(v) if type(v) == 'boolean' then return v end return nil end
local function mod(name)                                -- a sibling module of the set (lab_cap, lab_piece, lab_cut)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
-- Seconds since the corpse's death (the lab_death source time, lab_cut's cut.death_t), else since the corpse opened
local function since(e) return r2(now() - (e.death_t or e.t0)) end

-- ---------- the gates ----------
-- A busy frame (the contract of lab_look, lab_census and this module): a lab_death or lab_cut_live this frame or the
-- one before, or a cut job waiting in lab_cut
local function busy()
    if st.busy_f and S.frame - st.busy_f <= 1 then return true end
    local K = mod('lab_cut')
    if K and type(K.status) == 'function' then
        local ok, s = pcall(K.status)
        if ok and type(s) == 'table' and (s.jobs or 0) > 0 then return true end
    end
    return false
end
-- A class this module may run now: not struck, its sig check ok. true | false, why ('sig_pending' waits a frame)
local function may(name)
    if SENT.is_disabled(name) then return false, 'disabled' end
    local ok, why = LAB.sig(name)
    if not ok then return false, why or 'sig_unknown' end
    return true
end
-- The writes (the resync and the fade): the switch, not off, not under the vanilla compare
local function writes_on() return META.beta_fade == true and MODOFF.enabled('lab_fade') end

-- ---------- one sample (inside 'lab.read.dissolve'): reads only ----------
local function mat_id(m) return tostring(ue.addr(m)) .. '|' .. tostring(ue.name(m)) end
local function scalar(m, name)
    local ok, v = ue.call(m, 'K2_GetScalarParameterValue', ue.fname(name))
    if ok and num(v) then return r3(v) end
    return nil
end
local function levers(e, actor)
    if not e.has then
        e.has = { RENEWAL = ue.is_a(actor, FADE.RENEWAL) == true, NPC_BASE = ue.is_a(actor, FADE.NPC_BASE) == true }
    end
    local out = {}
    for _, l in ipairs(FADE.LEVERS) do
        local v = nil
        if e.has[l.cls] then v = ue.prop(actor, l.prop) end
        if type(v) == 'boolean' or num(v) then out[l.key] = v else out[l.key] = 'unread' end
    end
    return out
end
local function live_comp(rec)
    if type(rec) ~= 'table' then return nil end
    if rec.full then return ue.live_mod(rec) end
    return ue.live(rec)
end
local function read(e, actor)
    local v = { hidden = bool(ue.prop(actor, 'bHidden')) }
    local leader = ue.prop(actor, 'Mesh')
    if ue.valid(leader) then
        v.lvis, v.lhig = bool(ue.prop(leader, 'bVisible')), bool(ue.prop(leader, 'bHiddenInGame'))
        local x = ue.prop(ue.prop(leader, 'RelativeScale3D'), 'X')
        if num(x) then v.scale, v.shrink = r3(x), x < FADE.SHRINK end
        local ok, n = ue.call(leader, 'GetNumMaterials')
        if ok and math.type(n) == 'integer' then
            local ids, m0 = {}, nil
            for i = 0, math.min(n, FADE.MAT_MAX) - 1 do
                local okg, m = ue.call(leader, 'GetMaterial', i)
                local good = okg and ue.valid(m)
                ids[i + 1] = good and mat_id(m) or 'none'
                if i == 0 and good then m0 = m end
            end
            v.ids, v.nmats = ids, #ids
            v.mid0 = m0 ~= nil and ue.is_a(m0, FADE.MID) == true
            if v.mid0 then v.stamp, v.dur = scalar(m0, FADE.STAMP), scalar(m0, FADE.DUR) end
        end
    end
    local hc = ue.prop(actor, 'HairDissolveComponent')
    if ue.valid(hc) then
        local b, t = ue.prop(hc, 'BeginDissolveTime'), ue.prop(hc, 'Dissolve Time')
        local i = ue.prop(hc, 'CurrentDissolveIntensity')
        v.hair_begin, v.hair_time = num(b) and r3(b) or nil, num(t) and r3(t) or nil
        v.hair_int = num(i) and r3(i) or nil
    end
    v.lev = levers(e, actor)
    v.kept = v.lev.disable_dissol == true or v.lev.destroy_after == false
    local Cm = mod('lab_cap')
    v.caps = {}
    for j, cut in ipairs(e.cuts) do
        for _, h in ipairs(type(cut.head) == 'table' and cut.head or {}) do
            local c = type(h) == 'table' and live_comp(h.rec) or nil
            if c and L.comp_hidden(c) == false then v.reshown = tostring(h.name) end
        end
        local oks, s = false, nil
        if Cm and type(cut.slot) == 'table' then oks, s = pcall(Cm.state, cut.slot) end
        if oks and type(s) == 'table' then v.caps[j] = { stump = s.stump, piece = s.piece } end
    end
    return v
end
-- A snapshot of our objects (P-f, P-g): per Piece P.probe, per cut the Caps drawn and the Stump Cap's slot 0 against
-- the first snapshot's; no_src: property reads only (the corpse is going)
local function snap(e, at, no_src)
    local P, Cm = mod('lab_piece'), mod('lab_cap')
    local out = { t = since(e), pieces = {}, caps = {} }
    for j, cut in ipairs(e.cuts) do
        if P and type(P.probe) == 'function' and type(cut.piece) == 'table' then
            local r = P.probe(cut.piece, { no_src = no_src })
            if r then
                out.pieces[#out.pieces + 1] = { part = cut.part, state = r.state, shared = r.shared, hidden = r.hidden,
                    resynced = r.resynced, held = r.held or nil }
            end
        end
        local oks, s = false, nil
        if Cm and type(cut.slot) == 'table' then oks, s = pcall(Cm.state, cut.slot) end
        if oks and type(s) == 'table' then
            local c = {}
            c.part, c.stump, c.piece, c.faded = cut.part, s.stump, s.piece, cut.faded == true
            if not no_src then
                local cap = cut.slot.stump and live_comp(cut.slot.stump.comp)
                local ok, m = false, nil
                if cap then ok, m = ue.call(cap, 'GetMaterial', 0) end
                local id = (ok and ue.valid(m)) and mat_id(m) or nil
                e.cap0[j] = e.cap0[j] or id
                if id and e.cap0[j] then c.mid_same = id == e.cap0[j] else c.mid_same = 'unread' end
            end
            out.caps[#out.caps + 1] = c
        end
    end
    e.snaps[at] = e.snaps[at] or out
    return out
end

-- ---------- the record ----------
local function lag(e)
    local last, any = nil, false
    for _, cut in ipairs(e.cuts) do
        local p = cut.piece
        if type(p) == 'table' then
            any = true
            if p.state ~= 'destroyed' or not num(p.end_t) then return nil, false end
            if last == nil or p.end_t > last.end_t then last = p end
        end
    end
    if not any then return 'none', true end
    return { s = r2(last.end_t - (e.end_t or last.end_t)), live = last.live_n }, true
end
local function record(e)
    if e.done then return end
    e.done = true
    st.records = st.records + 1
    local parts, kept = {}, nil
    for _, cut in ipairs(e.cuts) do
        parts[#parts + 1] = cut.part
        if kept == nil then kept = cut.kept end
    end
    local pl = lag(e)
    local fade = e.fade_at and { at = r2(e.fade_at - e.g0), src = e.fade_src, n = e.faded, skip = e.fade_skip,
        err = e.fade_err } or (e.faded > 0 and { n = e.faded, src = 'hidden' }) or nil
    LAB.rec('dissolve', { id = e.id, class = e.class, pair = e.pair, parts = parts, kept = kept, why = e.why,
        samples = e.n, fails = e.fails > 0 and e.fails or nil, err = e.err, t_end = since(e),
        world0 = e.world0 or e.world_why or 'unread', v0 = e.v0, first = e.first, lev0 = e.lev0, lev1 = e.lev1,
        mats1 = e.mats1, stamp_seen = e.stamp_seen, stamp1 = e.stamp1, start = e.start, fade = fade,
        resyncs = e.resyncs, reshown = e.reshown,
        snaps = e.snaps, tr = e.tr, tr_drop = e.tr_drop > 0 and e.tr_drop or nil,
        piece_lag = type(pl) == 'table' and pl.s or (pl or 'pending'),
        pieces_live = type(pl) == 'table' and pl.live or nil }, true)
end
-- The sampling ends: the 'last' snapshot when it may still be read; a corpse that went (destroyed, collected) then
-- waits in the tail for its Pieces' destroy (TAIL_S at most) before the record, any other end records now
local GONE = { destroyed = true, collected = true }
local function close(e, why, last)
    if e.phase ~= 'sample' then return end
    e.phase, e.why, e.end_t, e.end_g = 'tail', why, now(), gnow()
    if last then LAB.armed('lab.read.dissolve', snap, e, 'last', true) end
    if not GONE[why] then record(e) end
end

-- ---------- the decision (MC7): resync and fade ----------
local function resync(e)
    if not writes_on() then st.holds = st.holds + 1 return end
    local P = mod('lab_piece')
    if not (P and type(P.resync) == 'function') or not may('piece.mesh') then return end
    for _, cut in ipairs(e.cuts) do
        local piece = cut.piece
        if type(piece) == 'table' and piece.state == 'live' and cut.kept ~= true then
            local _, err = LAB.armed('piece.mesh', P.resync, piece)
            if err ~= nil then e.err = text(err) else e.resyncs, st.resyncs = e.resyncs + 1, st.resyncs + 1 end
        end
    end
end
-- One cut's Caps hidden (C.fade under 'hide.comp'); a held fade (off, a pending sig) is tried again later
local function fade(e, cut, why)
    if cut.faded or cut.kept == true or e.kept_now then return end
    if META.beta_fade ~= true then e.fade_skip = 'beta_fade_off' return end
    local s = CFG.knob('cap_fade_s')
    if not (num(s) and s > 0) then e.fade_skip = 'knob_off' return end
    if not MODOFF.enabled('lab_fade') then st.holds = st.holds + 1 return end
    local Cm = mod('lab_cap')
    if not (Cm and type(Cm.fade) == 'function') then e.fade_skip = 'no_fade' return end
    if type(cut.slot) ~= 'table' then e.fade_skip = 'no_slot' return end
    local ok, w = may('hide.comp')
    if not ok then
        if w ~= 'sig_pending' then e.fade_skip = w end
        return
    end
    local _, err = LAB.armed('hide.comp', Cm.fade, cut.slot)
    if err ~= nil then
        e.fade_err = text(err)
        return
    end
    cut.faded, cut.fade_t, cut.fade_why = true, now(), why
    e.faded, st.fades = e.faded + 1, st.fades + 1
end
local function fade_all(e, why)
    local n0 = e.faded
    for _, cut in ipairs(e.cuts) do fade(e, cut, why) end
    if e.faded > n0 and not e.snaps.fade then LAB.armed('lab.read.dissolve', snap, e, 'fade') end
end
-- When the fade is due: the start + cap_fade_s, or STAMP + STAMP_K x DUR in engine time when both read and that lies
-- within DELAY_MAX_S of now (now when it passed already; the engine time now: the first sample's GetTimeSeconds plus
-- the game seconds since)
local function schedule(e, g, v)
    if e.fade_src == 'stamp' then return end
    if num(v.stamp) and num(v.dur) and v.stamp > 0 and v.dur > 0 and num(e.world0) then
        local d = v.stamp + FADE.STAMP_K * v.dur - (e.world0 + (g - e.g0w))
        if math.abs(d) <= FADE.DELAY_MAX_S then
            e.fade_at, e.fade_src = g + math.max(d, 0), 'stamp'
            return
        end
    end
    if e.fade_at == nil then
        local s = CFG.knob('cap_fade_s')
        e.fade_at, e.fade_src = g + (num(s) and s or 0), 'signal'
    end
end

-- ---------- the corpse's sample and its transitions ----------
local function track(e, k, val, t)
    if val == nil then return end
    local prev = e.last[k]
    e.last[k] = val
    if prev == nil or prev == val then return end
    if e.first[k] == nil then e.first[k] = t end
    if FADE.FIRST_ONLY[k] then return end
    if #e.tr >= FADE.TR_MAX then e.tr_drop = e.tr_drop + 1 return end
    e.tr[#e.tr + 1] = { t = t, k = k, v = val }
end
local function changed(ids0, ids)
    if type(ids0) ~= 'table' or type(ids) ~= 'table' then return nil end
    local n = 0
    for i = 1, math.max(#ids0, #ids) do if ids0[i] ~= ids[i] then n = n + 1 end end
    return n
end
local function world(e)
    local ok, why = may('probe.static.GetTimeSeconds')
    if not ok then
        if why ~= 'sig_pending' then e.world0, e.world_why = false, why end
        return
    end
    local v, err = LAB.armed('probe.static.GetTimeSeconds', US.time_seconds)
    if err == nil and num(v) then
        e.world0, e.g0w = r3(v), gnow()
    else
        e.world0, e.world_why = false, text(err or 'unread')
    end
end
local function sample(e, g)
    local actor, why = LAB.alive(e.victim)
    if not actor then return close(e, why or 'gone', true) end
    if g - e.g0 >= FADE.WINDOW_S then return close(e, 'window', true) end
    e.n, st.samples = e.n + 1, st.samples + 1
    local v, err = LAB.armed('lab.read.dissolve', read, e, actor)
    if err ~= nil or type(v) ~= 'table' then
        e.fails, st.fails, e.err, st.last_err = e.fails + 1, st.fails + 1, text(err or 'unread'), text(err or 'unread')
        return
    end
    local t = since(e)
    local first = e.v0 == nil
    if first then
        e.ids0, e.lev0 = v.ids, v.lev
        e.v0 = { hidden = v.hidden, lvis = v.lvis, lhig = v.lhig, scale = v.scale, nmats = v.nmats, mid0 = v.mid0,
            stamp = v.stamp, dur = v.dur, hair_begin = v.hair_begin, hair_time = v.hair_time, hair_int = v.hair_int }
        LAB.armed('lab.read.dissolve', snap, e, 'first')
    end
    if e.world0 == nil then world(e) end                -- once (a pending sig asks again at the next sample)
    e.lev1, e.kept_now = v.lev, v.kept
    v.mats = changed(e.ids0, v.ids)
    for _, k in ipairs(FADE.TRACK) do track(e, k, v[k], t) end
    for j, c in pairs(v.caps) do
        track(e, 'cap' .. j, c.stump, t)
        if c.piece ~= nil then track(e, 'capp' .. j, c.piece, t) end
    end
    if v.reshown and not e.reshown then e.reshown = { name = v.reshown, t = t } end
    if (v.mats or 0) > 0 and not e.mats1 then e.mats1 = { t = t, n = v.mats, of = v.nmats, mid = v.mid0 } end
    local stamp_moved = num(e.stamp_prev) and num(v.stamp) and v.stamp ~= e.stamp_prev
    if stamp_moved and not e.stamp1 then e.stamp1 = { t = t, stamp = v.stamp, dur = v.dur, from = e.stamp_prev } end
    if num(v.stamp) and not e.stamp_seen then e.stamp_seen = { t = t, stamp = v.stamp, dur = v.dur } end
    e.stamp_prev = v.stamp
    if v.kept then return end                           -- kept now (the levers): no decision, the record goes on
    if v.hidden == true or v.lvis == false or v.lhig == true then fade_all(e, 'hidden') end
    local start = not e.start and (((v.mats or 0) > 0 and 'mats') or (stamp_moved and 'stamp') or nil)
    if start then
        e.start, e.mats_seen = { why = start, t = t }, v.mats or 0
        LAB.armed('lab.read.dissolve', snap, e, 'signal')
        resync(e)
    elseif e.start and (v.mats or 0) ~= e.mats_seen then
        e.mats_seen = v.mats or 0                       -- a later slot change: the Pieces follow it again
        resync(e)
    end
    if e.start then schedule(e, g, v) end
end
-- The due fades of one corpse (each tick it is not busy: a held fade is tried again)
local function due(e, g)
    if e.fade_at and g >= e.fade_at and not e.kept_now then fade_all(e, e.fade_src) end
end
-- The tail: the record once every Piece of the corpse is destroyed (Lua fields only) or TAIL_S passed
local function tail(e, g)
    local _, settled = lag(e)
    if settled or g - e.end_g >= FADE.TAIL_S then record(e) end
end

-- ---------- tracking ----------
local function open(cut)
    local id = cut.id
    if id == nil then return end
    local e = st.by_id[id]
    if not e then
        if #st.list >= FADE.CORPSES then st.dropped = st.dropped + 1 return end
        local g = gnow()
        e = { id = id, victim = cut.victim, class = cut.class, pair = cut.pair, cuts = {}, t0 = now(), g0 = g,
            next_g = g + FADE.SAMPLE_S, death_t = type(cut.death_t) == 'number' and cut.death_t or nil, n = 0,
            fails = 0, phase = 'sample', last = {}, first = {}, tr = {}, tr_drop = 0, snaps = {}, cap0 = {}, faded = 0,
            resyncs = 0 }
        st.by_id[id], st.list[#st.list + 1] = e, e
    end
    for _, c in ipairs(e.cuts) do if c == cut then return end end
    e.cuts[#e.cuts + 1] = cut
end
-- lab_cut_gone: a revive (no gone_why) ends the corpse's record at once; a corpse gone goes to its tail
local function gone(cut)
    local e = cut.id ~= nil and st.by_id[cut.id] or nil
    if not e or e.phase ~= 'sample' then return end
    if cut.gone_why == nil then
        e.phase, e.why, e.end_t, e.end_g = 'tail', 'revive', now(), gnow()
        return record(e)
    end
    close(e, cut.gone_why, false)
end
local function drain()
    local q = st.liveq
    st.liveq = {}
    for _, cut in ipairs(q) do open(cut) end
    q = st.goneq
    st.goneq = {}
    for _, cut in ipairs(q) do gone(cut) end
end
local function prune()
    local keep = {}
    for _, e in ipairs(st.list) do
        if e.done then st.by_id[e.id] = nil else keep[#keep + 1] = e end
    end
    st.list = keep
end
-- Every open corpse recorded now (lab_end, a map load, a refused read class): no engine call
local function finish(why)
    for _, e in ipairs(st.list) do
        if e.phase == 'sample' then e.why, e.end_t, e.end_g = why, now(), gnow() end
        record(e)
    end
    st.list, st.by_id = {}, {}
end

-- ---------- the ticker and the bus ----------
local function tick()
    if not st.init or st.ended then return end
    if st.end_due then
        st.end_due, st.ended = false, true
        drain()
        return finish('lab_end')
    end
    if st.liveq[1] or st.goneq[1] then drain() end
    if not st.list[1] then return end
    local g = gnow()
    for _, e in ipairs(st.list) do if e.phase == 'tail' and not e.done then tail(e, g) end end
    if LAB.paused() or LAB.pinned() ~= true or not MODOFF.enabled('lab_fade') then return prune() end
    if busy() then
        st.busy = st.busy + 1
        return prune()
    end
    local ok, why = may(FADE.NAME)
    if not ok then
        if why ~= 'sig_pending' then
            st.sig_why = why
            finish(why)
        end
        return
    end
    local n = 0
    for _, e in ipairs(st.list) do
        if e.phase == 'sample' then
            if n < FADE.PER_FRAME and g >= e.next_g then
                n = n + 1
                e.next_g = g + FADE.SAMPLE_S
                sample(e, g)
            end
            if e.phase == 'sample' then due(e, g) end
        end
    end
    prune()
end
local function queue(q, cut)                            -- listeners only queue
    if type(cut) ~= 'table' or st.ended then return end
    if #q >= FADE.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    q[#q + 1] = cut
end
local EVENTS = { 'lab_death', 'lab_cut_live', 'lab_cut_gone', 'lab_end' }

-- ---------- lifecycle ----------
function FADE.tracked() return st.list end
-- A: the main.lua feature view (clock; LAB holds the records). Inert outside the beta
function FADE.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    LAB.names(N, F)
    MODOFF.feature('lab_fade', { gameplay = true })     -- off and the vanilla compare hold the reads and the writes
    BUS.on('lab_death', 'lab_fade', function() st.busy_f = S.frame end)
    BUS.on('lab_cut_live', 'lab_fade', function(cut)
        st.busy_f = S.frame
        queue(st.liveq, cut)
    end)
    BUS.on('lab_cut_gone', 'lab_fade', function(cut) queue(st.goneq, cut) end)
    BUS.on('lab_end', 'lab_fade', function() if not st.ended then st.end_due = true end end)
    S.ticker('lab_fade', tick)
    return true
end
-- A map load: every open corpse went with the old map; its record is written now ('map', no engine call). lab_cut's
-- reset announced the old cuts gone without a gone_why just before: those queued events are dropped, never a revive
function FADE.reset()
    if not st.init then return end
    st.liveq, st.goneq = {}, {}
    finish('map')
end
function FADE.status()
    return { init = st.init, corpses = #st.list, records = st.records, samples = st.samples, fails = st.fails,
        fades = st.fades, resyncs = st.resyncs, busy = st.busy, holds = st.holds, dropped = st.dropped,
        qdrop = st.qdrop, sig_why = st.sig_why, last_err = st.last_err, ended = st.ended }
end
function FADE.shutdown()
    S.remove_ticker('lab_fade')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_fade') end
    st, A = new_state(), nil
end
return FADE
