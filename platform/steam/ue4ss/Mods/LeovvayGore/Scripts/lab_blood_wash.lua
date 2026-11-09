-- status: new for the beta (the life, heal fade, revive wash and Blood on Soul off moved here from lab_blood.lua as
-- they were; the face wash offline only, the author's next run decides) origin: bd-heal (the author 2026-10-31), the
-- player requests of 2026-11-01 (spec_149 section 5) and 2026-11-02 (Nexus 178851837)
-- lab_blood_wash.lua: Soul's splashes go, a library lab_blood requires (main.lua's LIBS puts it in the code hash).
-- WS.bind(h) hands it lab_blood's helpers at lab_blood's init (B, state(), now, stopped, failed, worked, recv_off), so
-- the state (st.pring, st.heal, the events), the constants (lab_blood's B), the breaker, the counters and the records stay
-- lab_blood's; each entry point reads lab_blood's state anew (B.init and B.shutdown replace it). lab_blood's ticker
-- calls WS.step() each unpaused frame before its gate (the wash runs while off too), B.reset WS.reset() and B.status
-- WS.status(). Split out of lab_blood.lua at its module limit (lint L012, 2026-11-02); on_player and the decal
-- queue (lab_blood_queue's job_player) put the splashes into st.pring.
-- * Soul's splashes go (bd-heal; the author 2026-10-31: «the blood should go away on a full heal», «and after death
--   too», then, told that Soul regenerates out of combat: «let it fade progressively, and a full restore keeps the blood
--   for a while but speeds up the fade»). Every st.pring entry carries its seq (st.pseq, one up per entry) and its game
--   time t (S.game_time: stops in pause and loads, follows slow motion). Three rules take the ring's oldest entries:
--   - The life: an entry older than soul_blood_life_s (core/config.lua, default 300; 0 turns the life off) goes. A
--     fight keeps adding splashes, so a fighting Soul stays covered; the cap PLAYER_MAX still holds.
--   - The heal fade (rule 'heal_fade'): the blood stays heal_hold_s (15), then every entry the ring held at the heal
--     goes, oldest first, spread over heal_fade_s (45): at game time g, ceil(n x (stop - g) / heal_fade_s) of the n
--     it started with may stay. Entries that land after the heal follow their life. A second full heal during the hold
--     or the fade restarts nothing (fires counts). wash_on_heal false turns off this rule only (a fade ends, cut 'off').
--   - The revive wash (rule 'revive'): every entry the ring holds goes at once (a heal fade running ends, cut
--     'revive'; a second revive while one runs adds the newer entries). No wash at the 0 read itself: the respawn very
--     likely revives and teleports the same pawn behind the death screen (CXX dump: BP_Renewal_Hun_C's parent
--     BP_RenewalPlayer_C holds the Death Widget and RespawnResult, BP_RenewalPlayer.hpp:54, :74; GA_PlayerRespawn;
--     PBZPlayerReviveSubsystem OnPlayerRevived and OnPlayerTeleportRefresh, ProjectPBZ.hpp:11609-11613; W_PlayerDead
--     StartFadeOut and EndFadeOut, W_PlayerDead.hpp:31, :42), so the corpse is drawn while the death screen plays and
--     a wash at 0 would strip a dying body in view; dead_s (the first 0 read to the full one) tells the next run.
--   The signal: the lab_pawn pawn's AttributeSetBase (PBZCharacter, a UBasicAttributeSet: CXX dump
--   ProjectPBZ.hpp:4027, CharacterBasics.hpp:50-51) Health and Health_Max CurrentValue, property chains only (no
--   UFunction, as lab_poll reads the victims' Health), every HEAL_POLL_S while not paused. A read at or under
--   Health_Max - max(HEAL_ARM_MIN, HEAL_ARM x Health_Max) arms it (the lowest read kept); a later read within
--   HEAL_FULL x Health_Max of Health_Max fires once and disarms: 'revive' when the lowest read was 0 or less (a death
--   and a respawn on the same pawn), else 'heal' (an item, a bell rest, a talent, or regeneration: Soul's
--   BP_Renewal_Hun carries GA_ResotreHealth_Passive, GE_RestoreHealth_Passive with an IsInCombat check, object dump
--   26266538 :452593, :242614, :242816-242828, so a fight's end very likely starts a heal fade: the author's answer
--   above). The record's jump (the full read minus the one before) tells a regen tick from a medicine or a bell. Each
--   fire also goes out as bus lab_soul_heal { rule 'heal' | 'revive', key } (lab_sword: the blood on Soul's weapons),
--   whatever wash_on_heal says. A read in between changes nothing (a 1-point tick neither arms nor fires). A new pawn
--   key (bus lab_pawn) and a map load start disarmed: a new pawn carries none of the old splashes (they are components
--   of the old actor).
--   Unreadable (no AttributeSetBase, Health or Health_Max, or Health_Max not above 0): no heal fade and no revive,
--   one soul_wash_unread record per pawn class (HEAL_LOG_MAX classes at most) and the counter.
--   The destroys: each unpaused frame, the revive's entries first, else the heal fade's share, then the ones past
--   their life, at most WASH_PER_FRAME and none once WASH_S passed on the lab clock (one at least), in one
--   'blood.wash' call, about 7 engine calls each (ue.live_mod, then ue.destroy: K2_DestroyComponent(owner) on the
--   decal component, never its owner, never SetLifeSpan or SetFadeOut: bDestroyOwnerAfterFade defaults to true and
--   would take the owner, the player); destroyed while still the one kept, else gone; the ring is compacted once a
--   frame. Only Soul's splashes: the victims' attached decals and the ground pools stay.
--   Records: soul_wash once per event, never per splash: rule 'heal_fade' or 'revive' at its end { before, jump, low,
--   after, max, dead_s, hold, fade, queued, destroyed, gone, by_life, taken (by the cap), left, kept, frames, ms,
--   fires, cut, err }; rule 'life' per batch, LIFE_GAP_S game seconds after its last destroy { life_s, destroyed,
--   gone, frames, span_s, late_s (the most an entry outlived its life), kept, cut, err }. Counters soul_fade_life,
--   soul_fade_heal and soul_fade_revive count destroyed entries.
--   Mod-off and the vanilla compare do not stop them; a pause holds them; the breaker ('blood.wash', FAIL_MAX failed
--   frames in a row) stops all three for the map (open events end, cut 'breaker'; the cap still holds); a map load
--   ends them (cut 'map'); lab_end stops all.
--   - Blood on Soul off (soul_blood false, core/config.lua; the player request of 2026-11-01, spec_149 section 5):
--     on_player returns at once (no splash and no receives switch for hits, kills, cuts, extra parts and slices), no
--     Health is read but for bus lab_soul_heal while sword_blood is on (its fires touch no ring), a heal fade running
--     ends (cut 'soul_off'), and the whole ring goes as a revive wash (rule 'soul_off', one soul_wash record: nothing
--     lands while off, so the event fires once; no new event once the 'blood.wash' breaker tripped). No new engine
--     call: the same 'blood.wash' destroys. Back on starts the heal state disarmed (as the sword's poll left it). Once
--     the ring is empty his parts go back to the game's false (recv_step below, B4: until then a pool can tint his
--     boots); lab_grey's soul_ovl sampler decals (test build) are not in the ring.
--   - His parts back (recv_step, B4, Nexus 178919373): whatever emptied the ring (the life, a heal fade, a revive, Blood
--     on Soul off, his face's wash), RECV_IDLE_S game seconds after on_player last reached him, lab_blood's recv_off
--     takes back the parts receives_on switched (why 'empty'): no world decal (the forest floor's leaves and dirt) on
--     him out of a fight. Each frame of the wash, also while off; no engine call while his ring holds a splash.
--   - Blood on Soul's face off (soul_face_blood false, core/config.lua; the player request of 2026-11-02, Nexus
--     178851837: «a clean face»): a splash whose PLAYER_BONES pick is a face bone (B.face_bone: by name prefix, the
--     head, the neck chain, face and hair bones; of PLAYER_BONES head and neck_01) or a bone next to his neck whose
--     splash reaches his chin (B.FACE_NEAR: spine_05, clavicle_l, clavicle_r) is skipped (blood_skip_face): no
--     bone read, no decal, no lab_grey splash. The other picks land as before, so his body and clothes keep the
--     splashes Blood on Soul and blood_amount give them. Every splash carries its face flag from the queue to the
--     ring (st.pring entry .face); a queued face splash is dropped once the switch is off (blood_dq_gone). The switch
--     going off (read at each settings change, as soul_blood) starts the face wash (rule 'face_off'): every face entry
--     the ring holds at that moment goes, his other splashes stay. Each unpaused frame, before the rest of the
--     wash, it destroys the next face entries in one 'blood.wash' call (the same destroy, budget and breaker: at most
--     WASH_PER_FRAME, none past WASH_S; the life, heal fade and revive wait that frame), compacting the ring once;
--     one soul_wash record at its end { queued, destroyed, gone, taken (by the cap, the life, a heal fade or a revive
--     first), left, kept, frames, ms, fires, cut ('map', 'breaker'), err } and the counter soul_fade_face. A revive
--     or heal fade whose entries it took counts them in by_face. While Blood on Soul is off no face wash starts (its
--     own wash takes the whole ring); a second switch-off while one runs adds the newer face entries (fires). No new
--     engine call. Not covered [inferred, the eyes decide]: a splash box on an upper arm (17-20 cm below Head and
--     about 20 cm off the midline in the bind poses), on spine_04 or on a hand passing his face can still reach his
--     chin, jaw or cheek, more so at a high blood_amount (the half-size grows by sqrt(d): 19.4-36 cm at 9); a full
--     guarantee would need receives_on to leave his head parts unswitched while the switch is off (fewer
--     SetReceivesDecals, the author's call). Not persistent, not in st.pring, so the switch cannot take them:
--     receives_on switched all 13 of his parts (meshhead, Hun_Hat, Hun_Hat01, meshBrowLashCard, CA_Hun_Hair among
--     them; run 11's blood_adecal record), so any decal box his head enters projects onto his face while it is
--     inside: a victim's attached splash (ADECAL_DEPTH 30 cm along the victim-to-Soul axis, half-size up to 41.6 cm
--     at blood_amount 3) in a clinch or a finisher, a stump's cap ring, a pool, a drop's stain on a wall he leans
--     on. lab_grey's sampler decals already on his face stay.
-- API: bind(h) new_heal() step() reset() status() -> washing, fading, face_washing (the entries each open event
-- still holds; face_washing nil when no face wash runs).
-- What the mock cannot prove: when PBZ's regeneration and respawn reach Health, native faults, the look of a splash
-- box near the neck (whether one on an upper arm reaches his chin).
local BUS = require('core.bus')
local S = require('core.sched')
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local WS = {}
local H, B, st = nil, nil, nil                         -- lab_blood's helpers, its constants, its state (each entry)

local function now() return H.now() end
local function gnow() return S.game_time or 0 end         -- game seconds: stops in pause and loads (Soul's splashes)
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function stopped(name) return H.stopped(name) end
local function failed(name, err) return H.failed(name, err) end
local function worked(name) return H.worked(name) end
-- The heal state: armed, the lowest read while armed, the previous read, the game time of the first read at or under 0
function WS.new_heal() return { armed = false, low = nil, prev = nil, dead = nil } end
local new_heal = WS.new_heal

-- ---------- Soul's splashes go (bd-heal): the life, the heal fade, the revive wash (header) ----------
local FADE_COUNTER = { rev = 'soul_fade_revive', heal = 'soul_fade_heal', life = 'soul_fade_life' }
local function settings()
    local ok, s = pcall(C.get)
    return ok and type(s) == 'table' and s or {}
end
-- A seconds knob of core/config.lua (soul_blood_life_s, heal_hold_s, heal_fade_s): a number 0 or more, else its default
local function knob_s(s, k)
    local v = tonumber(s[k])
    if num(v) and v >= 0 then return v end
    v = tonumber(C.DEFAULTS[k])
    return num(v) and v >= 0 and v or 0
end
-- How many of st.pring's oldest entries carry a seq at or under cut (the ring is in seq order: a binary search)
local function upto(cut)
    local lo, hi = 0, #st.pring
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if (st.pring[mid].seq or 0) <= cut then lo = mid else hi = mid - 1 end
    end
    return lo
end
-- Health and Health_Max of the pawn (property chains: AttributeSetBase -> Health / Health_Max -> CurrentValue), or
-- nil, nil and why
local function heal_read(pawn)
    local attr = ue.prop(pawn, 'AttributeSetBase')
    if attr == nil then return nil, nil, 'no_attr' end
    local h = ue.prop(ue.prop(attr, 'Health'), 'CurrentValue')
    if not num(h) then return nil, nil, 'no_health' end
    local mx = ue.prop(ue.prop(attr, 'Health_Max'), 'CurrentValue')
    if not num(mx) then return nil, nil, 'no_max' end
    if mx <= 0 then return nil, nil, 'max_zero' end
    return h, mx
end
local function heal_unread(why, pawn)
    LAB.count('soul_wash_unread')
    local full = ue.full(pawn)
    local class = full and full:match('^(%S+) ') or 'unread'
    if st.heal_logged[class] or st.heal_logn >= B.HEAL_LOG_MAX then return end
    st.heal_logged[class], st.heal_logn = true, st.heal_logn + 1
    LAB.rec('soul_wash_unread', { why = why, class = class }, true)
end
-- An event at a full read (st.rev, the revive wash, or st.fade, the heal fade): its splashes are the ring's entries up
-- to seq, all it holds now (the ones that land later follow their life)
local function new_event(rule)
    return { rule = rule, seq = st.pseq, queued = #st.pring, destroyed = 0, gone = 0, frames = 0, fires = 1,
        t0 = now() }
end
-- The full read on an event: the read before it, the jump (small: a regen tick; large: a medicine, a bell), the lowest
local function event_read(e, hs, h, mx)
    e.before, e.low, e.after, e.max = r1(hs.prev), r1(hs.low), r1(h), r1(mx)
    e.jump = num(hs.prev) and r1(h - hs.prev) or nil
end
-- An event's soul_wash record at its end: left, its entries not reached (cut 'map': gone with the old world; 'off',
-- 'revive' or 'breaker': they stay in the ring, under the life and the cap); taken, the ones the cap took first (or,
-- for a heal fade fired while a revive wash still ran, that wash); by_face, the ones the face wash took first
local function event_done(key, cut)
    local e = st[key]
    st[key] = nil
    local left = upto(e.seq)
    LAB.count('soul_wash')
    LAB.rec('soul_wash', { rule = e.rule, before = e.before, jump = e.jump, low = e.low, after = e.after, max = e.max,
        dead_s = e.dead_s, hold = e.hold, fade = e.fade, queued = e.queued, destroyed = e.destroyed, gone = e.gone,
        by_life = e.by_life, by_face = e.by_face,
        taken = e.queued - e.destroyed - e.gone - (e.by_life or 0) - (e.by_face or 0) - left, left = left,
        kept = #st.pring - left, frames = e.frames, ms = math.floor((now() - e.t0) * 1000 + 0.5), fires = e.fires,
        cut = cut, err = e.err }, true)
end
-- The life batch's soul_wash record (rule 'life'): late_s, the most an entry outlived its life (the budget's lag)
local function life_done(cut)
    local l = st.life
    st.life = nil
    LAB.count('soul_wash')
    LAB.rec('soul_wash', { rule = 'life', life_s = l.life_s, destroyed = l.destroyed, gone = l.gone, frames = l.frames,
        span_s = r1(l.g1 - l.g0), late_s = r1(l.late), kept = #st.pring, cut = cut, err = l.err }, true)
end
-- Revive: every entry the ring holds goes at once; a heal fade running ends (cut 'revive': this wash takes its
-- entries); a second revive while one runs adds the newer ones. dead_s: the first read at or under 0 to the full one
local function revive_fire(hs, h, mx)
    if st.fade then event_done('fade', 'revive') end
    local e = st.rev
    if e then
        e.queued, e.seq, e.fires = e.queued + #st.pring - upto(e.seq), st.pseq, e.fires + 1
    else
        e = new_event('revive')
        st.rev = e
    end
    event_read(e, hs, h, mx)
    e.dead_s = hs.dead and r1(gnow() - hs.dead) or nil
end
-- Heal fade: the ring's entries now go after heal_hold_s, spread over heal_fade_s; a second full heal during the hold
-- or the fade restarts nothing (fires counts it)
local function fade_fire(s, hs, h, mx)
    if st.fade then
        st.fade.fires = st.fade.fires + 1
        return
    end
    local f = new_event('heal_fade')
    event_read(f, hs, h, mx)
    f.hold, f.fade, f.by_life = knob_s(s, 'heal_hold_s'), knob_s(s, 'heal_fade_s'), 0
    f.start = gnow() + f.hold
    f.stop = f.start + f.fade
    st.fade = f
end
-- One unpaused frame (header): the ring's oldest entries that are due go, the revive's first, else the heal fade's
-- share by its clock (ceil(n x (stop - g) / fade) of the n it started with may stay), then those past their life; at
-- most WASH_PER_FRAME and none once WASH_S passed (one at least), in one 'blood.wash' call: destroyed while still the
-- one kept, else gone (the component went with its actor or a map). The ring is compacted once. Then the events that
-- ended; the breaker ('blood.wash', FAIL_MAX failed frames in a row) ends them all. busy: the face wash used this
-- frame's 'blood.wash' call (no destroy here then; the events are still checked)
local function wash_step(s, busy)
    if st.fade and s.wash_on_heal == false then event_done('fade', 'off') end
    local g, life, f = gnow(), knob_s(s, 'soul_blood_life_s'), st.fade
    local nrev, nheal = st.rev and upto(st.rev.seq) or 0, 0
    if nrev == 0 and f and g >= f.start then
        local left = upto(f.seq)
        f.n = f.n or left                               -- the entries the fade starts with
        local keep = (f.fade > 0 and g < f.stop) and math.ceil(f.n * (f.stop - g) / f.fade) or 0
        nheal = math.max(0, left - keep)
    end
    local e1 = st.pring[1]
    local due = nrev > 0 or nheal > 0 or (life > 0 and e1 ~= nil and g - (e1.t or 0) >= life)
    if due and not busy and not stopped('blood.wash') then
        local m, evs = 0, { rev = st.rev, heal = f }
        local used, got = { rev = 0, heal = 0, life = 0 }, { rev = 0, heal = 0, life = 0 }
        local n, err = LAB.hot('blood.wash', function()
            local t0 = now()
            while m < B.WASH_PER_FRAME do
                local e = st.pring[m + 1]
                if e == nil then break end
                local why = (m < nrev and 'rev') or (m < nheal and 'heal') or nil
                if not why then
                    if life <= 0 or g - (e.t or 0) < life then break end
                    why = 'life'
                    local l = st.life
                    if not l then
                        l = { life_s = life, destroyed = 0, gone = 0, frames = 0, g0 = g, g1 = g, late = 0 }
                        st.life = l
                    end
                    evs.life, l.g1, l.late = l, g, math.max(l.late, g - (e.t or 0) - life)
                    if f and (e.seq or 0) <= f.seq then f.by_life = f.by_life + 1 end
                end
                m, used[why] = m + 1, used[why] + 1
                local ev = evs[why]
                local d = ue.live_mod(e)
                if d and ue.destroy(d) then
                    ev.destroyed, got[why] = ev.destroyed + 1, got[why] + 1
                else
                    ev.gone = ev.gone + 1
                end
                if now() - t0 > B.WASH_S then break end
            end
            return m
        end)
        if m > 0 then
            local len = #st.pring
            table.move(st.pring, m + 1, len, 1)
            for j = len - m + 1, len do st.pring[j] = nil end
        end
        for why, ev in pairs(evs) do if used[why] > 0 then ev.frames = ev.frames + 1 end end
        for why, k in pairs(FADE_COUNTER) do if got[why] > 0 then LAB.count(k, got[why]) end end
        if n == nil then
            failed('blood.wash', err or 'no_answer')
            if st.rev then st.rev.err = st.err end
            if st.fade then st.fade.err = st.err end
            if st.life then st.life.err = st.err end
        else
            worked('blood.wash')
        end
    end
    if stopped('blood.wash') then                       -- the cap still holds
        if st.rev then event_done('rev', 'breaker') end
        if st.fade then event_done('fade', 'breaker') end
        if st.life then life_done('breaker') end
        return
    end
    if st.rev and upto(st.rev.seq) == 0 then event_done('rev', nil) end
    if st.fade and upto(st.fade.seq) == 0 then event_done('fade', nil) end
    if st.life and g - st.life.g1 >= B.LIFE_GAP_S then life_done(nil) end
end
-- One read of the pawn's Health: arm, keep the lowest (and when it first read 0 or less), fire at the max (header);
-- each fire goes out on the bus (lab_soul_heal); soul_off (Blood on Soul off, the sword on): no ring is touched
local function heal_poll(s, soul_off)
    local pawn = st.pawn and ue.live(st.pawn) or nil
    if not pawn then return end
    local h, mx, why = heal_read(pawn)
    if not h then heal_unread(why, pawn) return end
    local hs = st.heal
    if h <= mx - math.max(B.HEAL_ARM_MIN, mx * B.HEAL_ARM) then
        hs.armed = true
        if hs.low == nil or h < hs.low then hs.low = h end
        if h <= 0 and hs.dead == nil then hs.dead = gnow() end
    elseif hs.armed and h >= mx - mx * B.HEAL_FULL then
        local revive = hs.low ~= nil and hs.low <= 0
        if revive and not soul_off then revive_fire(hs, h, mx)
        elseif not (revive or soul_off) and s.wash_on_heal ~= false then fade_fire(s, hs, h, mx) end
        BUS.emit('lab_soul_heal', { rule = revive and 'revive' or 'heal', key = st.pawn_key })
        hs.armed, hs.low, hs.dead = false, nil, nil
    end
    hs.prev = h
end
-- Blood on Soul off (soul_blood false): no splash lands (on_player), a heal fade ends (cut 'soul_off'), and every entry
-- the ring holds goes through the revive wash (rule 'soul_off'); like the rest of the wash it waits while paused and
-- runs during mod-off and with effects.blood off
local function soul_off()
    if st.fade then event_done('fade', 'soul_off') end
    if not st.soul_off then st.soul_off, st.heal = true, new_heal() end   -- back on: starts disarmed
    local e = st.rev
    if e then
        if st.pseq > e.seq then e.queued, e.seq, e.fires = e.queued + #st.pring - upto(e.seq), st.pseq, e.fires + 1 end
    elseif st.pring[1] and not stopped('blood.wash') then  -- a tripped wash leaves the ring to the map load
        st.rev = new_event('soul_off')
    end
end
-- ---------- Blood on Soul's face off: the face wash (header) ----------
-- The face entries of st.pring whose seq lies in (lo, hi] (the ring is in seq order)
local function faces_in(lo, hi)
    local n = 0
    for i = upto(lo) + 1, #st.pring do
        local e = st.pring[i]
        if (e.seq or 0) > hi then break end
        if e.face then n = n + 1 end
    end
    return n
end
-- The switch read off (once per switch-off): the face wash of every face entry the ring holds now; st.facew
-- { seq (the newest it takes), at (the last seq looked at), queued, destroyed, gone, frames, fires, t0 }. None while
-- Blood on Soul is off (soul_off's wash takes the whole ring) or once the 'blood.wash' breaker tripped; a switch-off
-- while one runs adds the newer face entries
local function face_off(soul_is_off)
    if st.face_off then return end
    st.face_off = true
    if soul_is_off or stopped('blood.wash') then return end
    local f = st.facew
    local n = faces_in(f and f.seq or -1, st.pseq)
    if f then
        f.queued, f.seq, f.fires = f.queued + n, st.pseq, f.fires + 1
    elseif n > 0 then
        st.facew = { rule = 'face_off', seq = st.pseq, at = -1, queued = n, destroyed = 0, gone = 0, frames = 0,
            fires = 1, t0 = now() }
    end
end
-- The face wash's soul_wash record at its end: left, its face entries not reached (cut 'map': gone with the old
-- world; 'breaker': they stay under the life and the cap); taken, the ones the cap, the life, a heal fade or a revive
-- took first
local function face_done(cut)
    local f = st.facew
    st.facew = nil
    local left = faces_in(-1, f.seq)
    LAB.count('soul_wash')
    LAB.rec('soul_wash', { rule = f.rule, queued = f.queued, destroyed = f.destroyed, gone = f.gone,
        taken = f.queued - f.destroyed - f.gone - left, left = left, kept = #st.pring, frames = f.frames,
        ms = math.floor((now() - f.t0) * 1000 + 0.5), fires = f.fires, cut = cut, err = f.err }, true)
end
-- One unpaused frame of the face wash (header): the next face entries up to its seq are picked in Lua (from the entry
-- after the last one taken, at most WASH_PER_FRAME); none left ends it. They go in one 'blood.wash' call, none once
-- WASH_S passed (one at least): destroyed while still the one kept, else gone; a revive or heal fade that holds one
-- counts it in by_face. The ring is compacted once. true when it made the frame's call
local function face_wash()
    local f = st.facew
    if not f then return false end
    if stopped('blood.wash') then face_done('breaker') return false end
    local ring, pick = st.pring, {}
    local i = upto(f.at) + 1
    while #pick < B.WASH_PER_FRAME do
        local e = ring[i]
        if e == nil or (e.seq or 0) > f.seq then break end
        if e.face then pick[#pick + 1] = i end
        i = i + 1
    end
    if not pick[1] then face_done(nil) return false end
    local m, got = 0, 0
    local n, err = LAB.hot('blood.wash', function()
        local t0 = now()
        for _, j in ipairs(pick) do
            local e = ring[j]
            local q = e.seq or 0
            m, f.at = m + 1, q
            if st.rev and q <= st.rev.seq then st.rev.by_face = (st.rev.by_face or 0) + 1 end
            if st.fade and q <= st.fade.seq then st.fade.by_face = (st.fade.by_face or 0) + 1 end
            local d = ue.live_mod(e)
            if d and ue.destroy(d) then f.destroyed, got = f.destroyed + 1, got + 1 else f.gone = f.gone + 1 end
            if now() - t0 > B.WASH_S then break end
        end
        return m
    end)
    if m > 0 then                                       -- pick[1..m] leave the ring, the rest keep their order
        local len, w, k = #ring, pick[1], 1
        for j = pick[1], len do
            if k <= m and j == pick[k] then k = k + 1 else ring[w], w = ring[j], w + 1 end
        end
        for j = w, len do ring[j] = nil end
        f.frames = f.frames + 1
        if got > 0 then LAB.count('soul_fade_face', got) end
    end
    if n == nil then
        failed('blood.wash', err or 'no_answer')
        f.err = st.err
        if stopped('blood.wash') then face_done('breaker') end
    else
        worked('blood.wash')
    end
    return true
end
-- ---------- his parts back to the game's false (B4, Nexus 178919373; lab_blood's header 'The receive switch goes back')
-- No splash left on him (the ring empty: the life, a heal fade, a revive, Blood on Soul off or his face's wash took
-- the last one) and none queued since RECV_IDLE_S game seconds (on_player's st.soul_t; a queued splash spawns or drops
-- within DQ_STALE_S): lab_blood's recv_off takes back the parts receives_on switched (why 'empty'), so the world's
-- decals stop drawing on him; his next splash switches them on again
local function recv_step()
    local key = st.soul_key
    if key == nil or st.pring[1] or not st.recv_parts[key] then return end
    if gnow() - (st.soul_t or 0) < B.RECV_IDLE_S then return end
    H.recv_off(key, 'empty')
end
local function heal_step()                              -- the knobs read again at each settings change (C.gen)
    local s, g = settings(), C.gen()
    if st.knob_gen ~= g then
        st.knob_gen, st.soul_k, st.sword_k = g, C.knob('soul_blood'), C.knob('sword_blood')
        st.face_k = C.knob('soul_face_blood')
    end
    local off = st.soul_k == false
    if off then soul_off() else st.soul_off = nil end
    if st.face_k == false then face_off(off) else st.face_off = nil end
    if (not off or st.sword_k ~= false) and LAB.due('lab_blood.heal', B.HEAL_POLL_S) then heal_poll(s, off) end
    wash_step(s, face_wash())
    recv_step()
end

-- ---------- entry points (lab_blood's ticker, B.reset, B.status) ----------
-- One unpaused frame: the knobs, Blood on Soul off, Blood on Soul's face off, the heal poll, the face wash, the wash
function WS.step()
    st = H.state()
    heal_step()
end
-- A map load: a revive wash, a heal fade, a face wash and a life batch still open write their records (cut 'map';
-- Soul's splashes go with the old world)
function WS.reset()
    st = H.state()
    if st.rev then event_done('rev', 'map') end
    if st.fade then event_done('fade', 'map') end
    if st.facew then face_done('map') end
    if st.life then life_done('map') end
end
-- The entries the open revive wash, heal fade and face wash still hold (0, 0, nil when none, and before the first
-- bind)
function WS.status()
    if not H then return 0, 0, nil end
    st = H.state()
    return st.rev and upto(st.rev.seq) or 0, st.fade and upto(st.fade.seq) or 0,
        st.facew and faces_in(-1, st.facew.seq) or nil
end

-- lab_blood's init: its helpers (B, state(), now, stopped, failed, worked, recv_off); nil unbinds
function WS.bind(h)
    H = type(h) == 'table' and h or nil
    B = H and H.B or nil
end
return WS
