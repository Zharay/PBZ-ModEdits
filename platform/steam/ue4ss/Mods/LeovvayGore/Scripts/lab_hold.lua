-- status: new in M1a A3.8 (offline only; TC-LAB-02 HD1, LM1 and L8 decide) origin: kb:runtime-safety-perf#crash-sentinel-first-success-guard-linger-strikes-quit-hints-e-sentinel-e-risky-e-linger
-- lab_hold.lua: the read-backs of committed cuts, the slow upkeep, the re-assert and the L8 counters (spec M1a A3.8; D14,
-- sections 3.1 'hold', 3.2, 3.8). Dev builds only, dev set 'lab02' (META.dev_sets, main.lua); the probe and release
-- never require it, and init stays inert (no listener, no ticker, no record) unless LAB.cut_set(). Engine reads only
-- through adapter/ue.lua and adapter/ue_lab.lua helpers and lab_cap's state; re-asserts only through lab_cut (rule 7).
-- * Tracking: bus lab_cut_live (lab_cut, after each commit) queues the cut; the next tick opens its window in game
--   seconds (S.game_time: stops in pause). Heads: a check every HEAD_P s for HEAD_S s; limbs: every LIMB_P s for LIMB_S
--   s [P]; then the slow upkeep, a check every UPKEEP_P s (0.2 Hz [P], D14), until lab_end, bus lab_cut_gone or a
--   failed LAB.live. No check while paused; at most PER_FRAME checks a frame (the others wait a frame); the cadence
--   keeps its phase (no burst of catch-up checks after a hitch). The player beta (LAB.beta(); docs/research/beta-
--   dismemberment-plan.md BD8, research MC8, for up to three cuts a kill): heads every HEAD_P_FAST s for their first
--   HEAD_FAST_S s, then every HEAD_P s; limbs every LIMB_P_BETA s; PER_FRAME unchanged.
-- * A check is one LAB.hot('lab.read.bonehidden') call per cut (armed until its first read, then a linger before each
--   read: never an arm per poll), after the class's sig check (LAB.sig, D17; a refused class reads nothing): every
--   leader with the cut bone (ue.leaders_with_bone, as the commit hid them) through IsBoneHiddenByName, the head
--   components' bHiddenInGame and bVisible (ue_lab.comp_hidden, through their kept full names), the Stump Cap's
--   lab_cap state (C.state: live and drawn; a bad one is told apart as missing, hidden or unread). A read where no
--   leader answered a boolean is no evidence: no check, no verdict (status unread, the record's unread and why); a
--   Cap whose visibility reads no boolean is unread, never an open stump. A Cap lab_fade faded (the beta's cut.faded
--   or slot.faded, BD8, research MC7) reads 'faded' and counts as ok, never an open stump (the record's faded).
-- * A mismatch (a leader reads the bone shown, a head component reads drawn, or the Stump Cap reads missing or hidden)
--   re-asserts in the same frame through lab_cut's K.reassert ('hide.bone', 'hide.comp'; it cannot bring back a Cap
--   that went) and counts. Reads and re-asserts go on while the mod is off and under the vanilla compare: a cut corpse
--   stays cut with its Caps (C5), and an F8 press after the windows still has upkeep work to count (D14).
-- * Counters (section 3.2), published at 0 from init: hide_checks (every check that read), hide_mismatch (checks with a
--   mismatch), reassert (re-asserts that ran), cut_changed (checks where a leader read the bone shown or the Stump Cap
--   was missing, before the re-assert), open_stump (checks where the Stump Cap was missing or hidden), upkeep_off
--   (checks while MODOFF.is_off(), the slow upkeep included). Gauge hide_ms_per_corpse: the mean ms of one cut's read
--   (the hot call; a rare re-assert is not in it), published once SAMPLES_MIN reads exist (nil before: absent).
-- * Records: one forced hold record per cut (section 3.1) when its window ends (reason 'window'), when its corpse goes
--   first ('gone': bus lab_cut_gone or a corpse that is not LAB.alive, spec M1a 4.1 item 2: the destroy, 6-11 s after
--   the death, not the 61 s GC; gone_why 'destroyed', 'collected', 'reused', 'stale', else 'none'; 'map' at a map load),
--   or at lab_end ('lab_end'). Its fields
--   count the window's checks only: the slow upkeep feeds the counters. after_walk: true when the first check after
--   lab_keep's corpse(id) knew after_walk read it true (the lab pawn 50 m away and back within 15 m, the corpse drawn)
--   and found no mismatch; false when no walk was seen before the record, without lab_keep, or on a mismatch there.
--   A window that ends while lab_keep tracks the corpse and has not decided its walk keeps its record (reason
--   'window', held_s at the window's end) until an upkeep check sees the walk decided, the corpse goes or lab_end:
--   the card's 50 m walk comes after the F12 shots, often past a head's 180 s (verify_whole P2).
-- * lab_end (D20): on the next tick every cut not recorded yet gets its record and every read stops.
-- API: tracked() the cuts still read (tests); lifecycle init(A, opts) shutdown(reason) status() reset(reason); H.N, H.F.
-- What the mock cannot prove: native faults, UE4SS marshalling on dff435dd, whether the engine's optimizer or the
-- head-bone channel re-shows a hide in game (reshown and cut_changed decide), the real cost of a read (os.clock steps
-- 1 ms in the harness: hide_ms_per_corpse there is a mean of a quantized clock).
local BUS = require('core.bus')
local S = require('core.sched')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local LAB = require('lab_probe')

local H = { HEAD_S = 180, HEAD_P = 1, LIMB_S = 60, LIMB_P = 0.1, UPKEEP_P = 5, PER_FRAME = 16, CUTS = 64, INBOX = 64,
    SAMPLES_MIN = 600, EPS = 1e-6, ERR_CHARS = 160, NAME = 'lab.read.bonehidden' }
-- The beta's cadence (BD8, MC8): a head every HEAD_P_FAST s for its first HEAD_FAST_S s, then HEAD_P; a limb LIMB_P_BETA
H.HEAD_P_FAST, H.HEAD_FAST_S, H.LIMB_P_BETA = 0.25, 15, 0.25
-- Published at 0 from init (section 3.2): a counter that never moved would be absent from status (main.lua)
H.COUNTERS = { 'hide_checks', 'hide_mismatch', 'reassert', 'cut_changed', 'open_stump', 'upkeep_off' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua 'lab.read.bonehidden'; the re-assert is lab_cut's)
local N = {}
local F = {
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.SceneComponent", "bVisible"},
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
}
H.N, H.F = N, F

local A = nil
local function new_state()
    return { init = false, list = {}, seen = {}, liveq = {}, goneq = {}, qdrop = 0, dropped = 0, end_due = false,
        ended = false, records = 0, checks = 0, mismatches = 0, reasserts = 0, refused = 0, unread = 0, upkeep = 0,
        sig_why = nil, last_err = nil, ms_sum = 0, ms_n = 0 }
end
local st = new_state()
local function gnow() return S.game_time or 0 end
local function text(s)
    s = tostring(s)
    return #s > H.ERR_CHARS and s:sub(1, H.ERR_CHARS) or s
end
local function mod(name)                                -- a sibling lab module of the set (lab_cap, lab_cut, lab_keep)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function r4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- ---------- one check ----------
-- Inside LAB.hot: { leaders (with the bone), shown (of them reading it shown), unread (no boolean back), comps (head
-- components reading drawn), comps_unread, cap ('ok', 'hidden', 'missing', 'unread') }. Reads only:
-- IsBoneHiddenByName and the leader walk (the class's calls), property reads, identity checks
local function read(cut)
    local r = { leaders = 0, shown = 0, unread = 0, comps = 0, comps_unread = 0, cap = 'missing' }
    for _, m in ipairs(ue.leaders_with_bone(cut.actor, cut.bone)) do
        r.leaders = r.leaders + 1
        local h = L.is_bone_hidden(m, cut.bone)
        if h == false then r.shown = r.shown + 1 elseif h == nil then r.unread = r.unread + 1 end
    end
    for _, h in ipairs(cut.head or {}) do
        local c = h.rec and ue.live_mod(h.rec) or nil
        local hid = c and L.comp_hidden(c)
        if hid == false then r.comps = r.comps + 1 elseif hid == nil then r.comps_unread = r.comps_unread + 1 end
    end
    local C, slot = mod('lab_cap'), cut.slot
    if C and type(slot) == 'table' then
        if cut.faded or slot.faded then                 -- lab_fade hid it with the dissolve (BD8): ok, never re-shown
            r.cap = 'faded'
        elseif C.state(slot).stump == true then
            r.cap = 'ok'
        else
            local e = slot.stump
            local rec = type(e) == 'table' and e.comp or nil
            local c = type(rec) == 'table' and (rec.full and ue.live_mod(rec) or ue.live(rec)) or nil
            if not c then r.cap = 'missing'
            elseif L.comp_hidden(c) == nil then r.cap = 'unread'     -- no boolean back: no evidence, no open_stump
            else r.cap = 'hidden' end
        end
    end
    return r
end
-- after_walk (section 3.1): decided at the first check once lab_keep knows the corpse's after_walk
local function walk(e, mis)
    local KP = mod('lab_keep')
    local c = KP and type(KP.corpse) == 'function' and KP.corpse(e.cut.id) or nil
    if type(c) == 'table' and c.after_walk ~= nil then e.walk = c.after_walk == true and not mis end
end
-- lab_keep tracks the corpse and has not decided its walk yet: a window that ended waits for it (the card's walk
-- comes after the F12 shots, often past a head's 180 s)
local function walk_pending(e)
    local KP = mod('lab_keep')
    local c = KP and type(KP.corpse) == 'function' and KP.corpse(e.cut.id) or nil
    return type(c) == 'table' and c.after_walk == nil
end
-- One check of entry e: the read, the verdict, the re-assert in the same frame, the counters, and the window's fields
-- while its record is not written. false when the corpse went (e recorded 'gone'); a refused class or read is no check
local function check(e, g, record)
    local cut = e.cut
    local alive, gwhy = LAB.alive(cut.victim)
    if not alive then
        e.gone_why = gwhy
        record(e, 'gone', g)
        return false
    end
    local okc, why = LAB.sig(H.NAME)
    if not okc and why == 'sig_pending' then return true end        -- one sig path a frame (A3.2): no check yet
    if not okc then
        st.refused, st.sig_why, e.why = st.refused + 1, why or 'sig_unknown', why or 'sig_unknown'
        return true
    end
    local t0 = os.clock()
    local r, err = LAB.hot(H.NAME, read, cut)
    local ms = (os.clock() - t0) * 1000
    if err ~= nil or type(r) ~= 'table' then
        st.refused, st.last_err = st.refused + 1, text(err or 'unread')
        e.why = st.last_err
        return true
    end
    if r.leaders == 0 or r.unread >= r.leaders then     -- no leader answered a boolean: no evidence, so no check
        st.unread = st.unread + 1
        if not e.done then e.unread, e.why = e.unread + 1, r.leaders == 0 and 'no_leader' or 'unread' end
        return true
    end
    local reshown, cap_bad = r.shown > 0 or r.comps > 0, r.cap == 'hidden' or r.cap == 'missing'
    local mis = reshown or cap_bad
    st.checks, st.ms_sum, st.ms_n = st.checks + 1, st.ms_sum + ms, st.ms_n + 1
    LAB.count('hide_checks')
    if MODOFF.is_off() then LAB.count('upkeep_off') end
    if cap_bad then LAB.count('open_stump') end
    if r.shown > 0 or r.cap == 'missing' then LAB.count('cut_changed') end
    if mis then
        st.mismatches = st.mismatches + 1
        LAB.count('hide_mismatch')
        local K = mod('lab_cut')
        local n, w = nil, 'no_cut'
        if K and type(K.reassert) == 'function' then n, w = K.reassert(cut) end
        if n ~= nil then
            st.reasserts, e.reasserts = st.reasserts + 1, e.reasserts + 1
            LAB.count('reassert')
        else
            e.why = text(w)
        end
    end
    if e.closed or e.done then                          -- the slow upkeep: counters only; a held record waits the walk
        if not e.done then
            if e.walk == nil then walk(e, mis) end
            if e.walk ~= nil or not walk_pending(e) then record(e, 'window', g) end
        end
        return true
    end
    if e.walk == nil then walk(e, mis) end
    e.checks, e.ms = e.checks + 1, e.ms + ms
    if mis then e.mismatches = e.mismatches + 1 end
    if reshown then e.reshown = e.reshown + 1 end
    if cap_bad then e.cap_bad = e.cap_bad + 1 end
    if r.cap == 'faded' then e.faded = (e.faded or 0) + 1 end
    if r.unread > 0 or r.comps_unread > 0 or r.cap == 'unread' then e.unread = e.unread + 1 end
    return true
end

-- ---------- records and the window schedule ----------
-- The cut's hold record (section 3.1), once, forced (D14: mod-off lowers the log level)
local function record(e, reason, g)
    if e.done then return end
    e.done = true
    st.records = st.records + 1
    local cut = e.cut
    LAB.rec('hold', { row = e.row, id = cut.id, part = cut.part, pair = cut.pair, checks = e.checks,
        mismatches = e.mismatches, reshown = e.reshown, cap_bad = e.cap_bad, held_s = r1(math.max(0, g - e.t0)),
        after_walk = e.walk == true, ms_mean = e.checks > 0 and r4(e.ms / e.checks) or 'unread', reason = reason,
        unread = e.unread, reasserts = e.reasserts, why = e.why, gone_why = e.gone_why or 'none', faded = e.faded,
        p0 = e.p0 }, true)
end
-- The record of a cut that ends (gone, a failed LAB.live, lab_end, a map load): a window that ended and waits for its
-- walk keeps its window record (held_s at the window's end), after_walk false unless the walk was seen
local function close(e, reason, g)
    if reason == 'gone' and e.gone_why == nil then e.gone_why = e.cut.gone_why end   -- lab_cut's word on bus lab_cut_gone
    if e.closed then return record(e, 'window', e.closed_g) end
    record(e, reason, g)
end
-- A committed cut joins the read-backs once (a second lab_cut_live of the same cut is ignored): its window opens now
local function track(cut, g)
    if st.seen[cut] then return end
    if #st.list >= H.CUTS then
        st.dropped = st.dropped + 1
        return
    end
    st.seen[cut] = true
    local limb, beta = cut.row == 'limbs', LAB.beta()
    local p = limb and H.LIMB_P or H.HEAD_P
    if beta then p = limb and H.LIMB_P_BETA or H.HEAD_P_FAST end      -- BD8: the beta's cadence
    st.list[#st.list + 1] = { cut = cut, row = limb and 'limbs' or 'heads', t0 = g, win = limb and H.LIMB_S or H.HEAD_S,
        p = p, next = g + p, checks = 0, mismatches = 0, reshown = 0, cap_bad = 0, unread = 0, reasserts = 0, ms = 0,
        done = false, walk = nil, fast = (beta and not limb) or nil, p0 = beta and p or nil }
end
-- The queued bus events: new cuts first, then the cuts whose corpse went or was restored (recorded 'gone', dropped)
local function drain(g)
    local q = st.liveq
    st.liveq = {}
    for _, cut in ipairs(q) do track(cut, g) end
    q = st.goneq
    st.goneq = {}
    for _, cut in ipairs(q) do
        for i = #st.list, 1, -1 do
            local e = st.list[i]
            if e.cut == cut then
                close(e, 'gone', g)
                table.remove(st.list, i)
            end
        end
    end
end
-- The due checks of this frame; the window's end writes the record and starts the slow upkeep
local function due(g)
    local n, keep = 0, {}
    for _, e in ipairs(st.list) do
        local alive = true
        if n < H.PER_FRAME and g >= e.next - H.EPS then
            n = n + 1
            alive = check(e, g, close)
            if alive then
                if e.fast and g - e.t0 >= H.HEAD_FAST_S - H.EPS then e.p, e.fast = H.HEAD_P, nil end   -- BD8
                e.next = e.next + e.p
                if e.next <= g then e.next = g + e.p end         -- a hitch or a long frame: no catch-up burst
                if not e.closed and not e.done and g - e.t0 >= e.win - H.EPS then
                    e.closed, e.closed_g = true, g
                    if e.walk ~= nil or not walk_pending(e) then record(e, 'window', g) end   -- else at the walk
                    e.p, e.next = H.UPKEEP_P, g + H.UPKEEP_P
                    st.upkeep = st.upkeep + 1
                end
            end
        end
        if alive then keep[#keep + 1] = e end
    end
    st.list = keep
end

-- ---------- the ticker, lab_end and the bus ----------
-- lab_end (D20): the queued cuts join, then every cut not recorded yet gets its record; nothing is read after it
local function finish()
    st.end_due, st.ended = false, true
    local g = gnow()
    drain(g)
    for _, e in ipairs(st.list) do close(e, 'lab_end', g) end
    st.list, st.liveq, st.goneq, st.seen = {}, {}, {}, {}
end
local function tick()
    if not st.init or st.ended then return end
    if st.end_due then return finish() end
    local g = gnow()
    if st.liveq[1] or st.goneq[1] then drain(g) end
    if LAB.paused() or not st.list[1] then return end
    due(g)
end
local function queue(q, cut)                            -- listeners only queue
    if type(cut) ~= 'table' or st.ended then return end
    if #q >= H.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    q[#q + 1] = cut
end
local EVENTS = { 'lab_cut_live', 'lab_cut_gone', 'lab_end' }

-- ---------- lifecycle ----------
function H.tracked() return st.list end
-- A: the main.lua feature view (count, gauge; LAB holds the records). Inert outside the lab02 set
function H.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.cut_set() then return true end
    st.init = true
    LAB.names(N, F)
    for _, k in ipairs(H.COUNTERS) do LAB.count(k, 0) end
    LAB.gauge('hide_ms_per_corpse', function()
        if st.ms_n < H.SAMPLES_MIN then return nil end
        return r4(st.ms_sum / st.ms_n)
    end)
    BUS.on('lab_cut_live', 'lab_hold', function(cut) queue(st.liveq, cut) end)
    BUS.on('lab_cut_gone', 'lab_hold', function(cut) queue(st.goneq, cut) end)
    BUS.on('lab_end', 'lab_hold', function() if not st.ended then st.end_due = true end end)
    S.ticker('lab_hold', tick)
    return true
end
-- A map load: the cut corpses went with the old map; every cut not recorded yet is recorded 'map' (no engine call)
function H.reset()
    if not st.init then return end
    local g = gnow()
    for _, e in ipairs(st.list) do close(e, 'map', g) end
    st.list, st.liveq, st.goneq, st.seen = {}, {}, {}, {}     -- lab_cut never announces an old map's cut again
end
function H.status()
    local window = 0
    for _, e in ipairs(st.list) do if not e.closed and not e.done then window = window + 1 end end
    return { init = st.init, cuts = #st.list, window = window, upkeep = #st.list - window, windows_ended = st.upkeep,
        records = st.records, unread = st.unread,
        checks = st.checks, mismatches = st.mismatches, reasserts = st.reasserts, refused = st.refused,
        sig_why = st.sig_why, last_err = st.last_err, dropped = st.dropped, qdrop = st.qdrop, ended = st.ended }
end
function H.shutdown()
    S.remove_ticker('lab_hold')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_hold') end
    st, A = new_state(), nil
end

return H
