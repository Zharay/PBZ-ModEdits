-- status: new (beta corpse keep; offline only, no test: the author's run decides) origin: docs/research/competitor-lingeringdead.md#corpses
-- lab_corpse.lua: the player beta keeps every enemy corpse corpse_keep_s game seconds, then lets it go (the author,
-- 2026-11-01: «the corpses disappear again», then «all corpses stay 15 min»). Player beta only (META.beta_modules, last); the
-- probe and dev profiles never require it (the lab keeps its corpses through lab_keep), and init stays inert (no
-- listener, no ticker, no record) unless LAB.beta(). No native call before LAB.pinned() reads true (another UE4SS
-- build: vanilla corpses, one corpse_off record).
-- * Which pawns: every one lab_poll admits (bus lab_admit: the BP_RenewalNPC_C class watch, hook hits, the per-map
--   FindAllOf) that is a BP_RenewalNPC_C (the enemy test, docs/research/competitor-lingeringdead.md:21-23), not the
--   player (PBZCharacter_Player, BP_RenewalPlayer_C; lab_poll never admits it either) and no class of
--   data/corpse_skip.lua: bosses (a kept boss body could stay in its scripted scene after the fight), allies and
--   scripted helpers (NpcHelper), phantoms, stands and dummies (they vanish by design). Those keep the vanilla dissolve.
-- * The levers: lab_keep's three proven ones (TC-LAB-02 runs 3-4 kept corpses with them; never 'Death Delay', which
--   may hold the death itself): BP_RenewalNPC_C.DisableDeathDissol true, BP_NPC_Base_C.DestroyAfterDead false and
--   DestroyDelay K.MARK, each only on the class that declares it, written with read-back (ue_lab.set_checked), one
--   pawn a frame, under LAB.armed('corpse.keep'), before the death: the destroy timer takes its values at the death,
--   so a write after it does nothing (runs 1-2). A pawn waits for its write until it reads alive (Health above 0: a
--   pawn under construction or still in its spawner reads 0), read again at most once a K.WAIT_S; a pawn whose death
--   came first is never written. A lever that does not read back puts the levers written in that call back and closes
--   'corpse.keep' (one record). corpse_keep_s 0 writes nothing (vanilla corpses).
-- * Another mod's corpse (LingeringDead writes the same levers): a pawn that reads DisableDeathDissol true or
--   DestroyAfterDead false before our write is left alone and never expired (foreign), unless DestroyDelay reads
--   K.MARK: our own write from before a hot reload, adopted (alive, or a corpse whose clock starts at the adoption).
-- * A written pawn is checked once a second (LAB.due: never while paused), K.CHECK_N a second round-robin, with
--   property reads only: gone (a map, a spawner) drops it; Health at 0 or below after a living read is a death bus
--   lab_death did not bring (a kill out of the poll's reach); a lever the game wrote back (BeginPlay) is written again.
-- * Deaths: bus lab_death (lab_poll's confirm) or the check above make a written pawn a kept corpse, its clock in game
--   seconds (S.game_time: the pause is not counted); bus lab_revive makes it a pawn again. Every cut lab_cut makes
--   (bus lab_cut_live) is listed under its corpse (cut.key) until lab_cut_gone.
-- * The going, once a second: a corpse is due at corpse_keep_s (why 'time'), or early when more than corpse_max wait
--   (the oldest first, why 'cap'). A due corpse goes, oldest first, at most K.GO_PER_S a second, as soon as it is over
--   K.FAR_M from the player (why 'far') or Actor:WasRecentlyRendered(K.SEEN_TOL_S) reads false (why 'unseen'; one
--   LAB.armed('corpse.seen') read each, at most K.SEEN_PER_S a second), else K.LATE_S after it fell due (why 'time' or
--   'cap'). Going: every cut of the corpse gets cut.expired = true first (lab_piece and lab_gib then send its Pieces,
--   gibs and fallen hats after it when lab_cut reads it gone, though cut.kept read true); then the vanilla look, one
--   LAB.armed('corpse.vanish'): DisableDeathDissol back to the value it read (false) and BP_RenewalNPC_C:Vanish()
--   (the object dump and BP_RenewalNPC.hpp:167 list it with no parameter; its body sits in the encrypted content, so
--   its first call in a session checks that arity, ue.sig_ok, and what it does is the author's run to see). The Caps of
--   its cuts hide K.CAP_FADE_S later (lab_cap C.fade under 'hide.comp', cut.faded and fade_why 'corpse'); K.VANISH_S
--   after the vanish a corpse still there goes through LAB.armed('corpse.destroy') (Actor:K2_DestroyActor). With
--   'corpse.vanish' off the corpse is destroyed at once.
-- * A corpse the game's slicer cut (lab_slice, lab_slice_route: docs/research/slicer-stumps.md) is kept like any other
--   (the route slices only a corpse this module keeps, state 'corpse': corpse_keep_s, corpse_max and the going rules
--   above hold for it unchanged). Its two halves go with it: they are the corpse actor's own components (the slicer
--   makes them with Outer = the owner actor [verified 0x14602f7c0, 0x146036410], registers them, and the route finds
--   them in the actor's K2_GetComponentsByClass list), so K2_DestroyActor takes them with the actor [inferred, UE
--   source: an actor's destroy destroys its owned components]. What Vanish() does to them is [unknown] (its body is
--   encrypted); the halves draw the source's own material objects [verified 0x146036595-0x1460365e0], so a dissolve on
--   those reaches them too [inferred], and either way the destroy K.VANISH_S after the vanish takes them. The going (the
--   vanish and the destroy) runs under 'slicer.gone' (10 s; not inherited, as no corpse name is: a stop must not leave
--   kept corpses that can no longer go) instead of corpse.vanish and corpse.destroy, so
--   a teardown fault of the transient halves strikes that name, never the corpse names every other corpse needs; with
--   'slicer.gone' off it stays until the map changes (counted stuck) with its halves. A vanish of a sliced corpse that
--   fails closes only that vanish (VANISH_SLICED, one corpse_off record), never 'slicer.gone': the destroy follows
--   under 'slicer.gone', as a vanilla corpse's destroy follows a closed 'corpse.vanish'. A corpse a slicer job holds
--   (lab_slice busy(key)) is never made to go. When a sliced corpse goes (any how, the map included) bus
--   lab_slice_gone { key, id, why, how } tells lab_gib (a sliced head's fallen masks follow it, as a cut's do).
-- * Records (forced): one corpse_keep per kept corpse when it goes { id, class, age_s (game seconds since the death),
--   why ('time', 'cap', 'far', 'unseen'; 'gone' when the game or a map took it first, with gone_why), how ('vanish',
--   'vanish_destroy', 'destroy', 'gone', 'map'), due, dist_m, via (the death's source), err, sliced (true for a corpse
--   the game's slicer cut) }; the counters
--   corpse_kept and corpse_gone and the gauge corpses_kept in status. LAB.CAPS.corpse_keep K.CAP_RECORDS.
-- * Fail closed: a corpse name that is struck (SENT.is_disabled), fails its sig check (LAB.sig) or raises is off for
--   the session with one forced corpse_off record { name, why }; 'corpse.keep' off writes no new pawn, and so does
--   'corpse.destroy' off (nothing could make a corpse go: the ones kept stay until the map changes, counted stuck);
--   'corpse.seen' off reads every corpse as seen; 'corpse.vanish' off destroys at once. Mod-off and the vanilla compare
--   (MODOFF.feature, gameplay) hold every write and every going.
-- API: kept() (the kept corpses, oldest first); lifecycle init(A) shutdown() status() reset(reason).
-- What the mock cannot prove: the lever writes on dff435dd (runs 3-4 proved them), whether BeginPlay writes a lever back,
-- which pawns lab_poll admits in time, every death bus lab_death misses, what Vanish does on a kept corpse, whether
-- WasRecentlyRendered reads false off screen in PBZ.
local BUS = require('core.bus')
local CFG = require('core.config')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local US = require('adapter.ue_spawn')
local LAB = require('lab_probe')

local K = { CHECK_S = 1, CHECK_N = 16, PAWNS = 256, WAIT_S = 1, RESOLVE_S = 0.25, RESOLVE_N = 20, CORPSES_HARD = 256, INBOX = 512, DEAD = 1024,
    CUTS = 8, CUT_KEYS = 512, ERR_CHARS = 160, MARK = 1000007, MARK_EPS = 0.5,
    FAR_M = 25, LATE_S = 60, SEEN_TOL_S = 1.0, SEEN_PER_S = 4, GO_PER_S = 2, VANISH_S = 2.5, CAP_FADE_S = 1.0,
    RENEWAL = '/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C',
    NPC_BASE = '/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C',
    PLAYER = '/Script/ProjectPBZ.PBZCharacter_Player',
    RENEWAL_PLAYER = '/Game/RenewalContent/Prototypes/Character/BP_RenewalPlayer.BP_RenewalPlayer_C',
    -- the dump's Blueprint function (UE4SS_ObjectDump: Function ...BP_RenewalNPC_C:Vanish, no parameter row)
    VANISH = '/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C:Vanish' }
-- The levers in write order: the record key, the property, the declaring class (a K path key), the kept value.
-- DestroyDelay K.MARK (a value no vanilla pawn and lab_keep's 1e6 never read, exact in a float) says the write is ours
K.LEVERS = { { key = 'disable_dissol', prop = 'DisableDeathDissol', cls = 'RENEWAL', v = true },
    { key = 'destroy_after', prop = 'DestroyAfterDead', cls = 'NPC_BASE', v = false },
    { key = 'destroy_delay', prop = 'DestroyDelay', cls = 'NPC_BASE', v = K.MARK } }
K.CAP_RECORDS = 1000                                    -- corpse_keep records a session (LAB.CAPS; below the log's 2000)
K.WHYS = { 'time', 'cap', 'far', 'unseen', 'gone', 'map' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua 'corpse.*') and the Blueprint Vanish (K.VANISH)
local N = {}
local F = {
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.SceneComponent", "RelativeLocation"},
    {"/Script/ProjectPBZ.PBZCharacter", "AttributeSetBase"},
    {"/Script/CharacterBasics.BasicAttributeSet", "Health"},
    {"/Script/GameplayAbilities.GameplayAttributeData", "CurrentValue"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "DisableDeathDissol"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyAfterDead"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyDelay"},
}
K.N, K.F = N, F

local A = nil
local SKIP = nil                                         -- data/corpse_skip.lua classes, loaded at init
local function new_state()
    local s = { init = false, inbox = {}, qdrop = 0, pawns = {}, plist = {}, corpses = {}, dead = {}, dead_list = {},
        cuts = {}, cut_keys = {}, off = {}, rr = 0, wrr = 0, pawn_in = nil, pawn = nil, vanish_sig = nil, why = {},
        n = { admitted = 0, skipped = 0, foreign = 0, unread = 0, kept = 0, adopted = 0, rewrites = 0,
            unseen_deaths = 0, died_first = 0, left = 0, full = 0, write_fail = 0, revived = 0, gone = 0,
            vanished = 0, destroyed = 0, stuck = 0, seen_reads = 0, cap_fades = 0, map_drop = 0 } }
    for _, w in ipairs(K.WHYS) do s.why[w] = 0 end
    return s
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or 0 end
local function gnow() return S.game_time or 0 end
-- The first TRACE_N decisions of a session, one forced corpse_trace record each { step, why, class, extra }
-- (TC-BETA-01d: no corpse was kept and nothing in the log said why)
local TRACE_N = 40
local function trace(step, why, class, extra)
    st.tn = (st.tn or 0) + 1
    if st.tn > TRACE_N then return end
    local r = { step = step, why = why, class = class }
    if type(extra) == 'table' then for k, v in pairs(extra) do r[k] = v end end
    LAB.rec('corpse_trace', r, true)
end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function text(s)
    s = tostring(s)
    return #s > K.ERR_CHARS and s:sub(1, K.ERR_CHARS) or s
end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end

-- ---------- fail closed: one record per name ----------
-- A corpse name off for the session (struck, a failed sig check, a raised call): one forced corpse_off record
local function close(name, why)
    if st.off[name] then return end
    st.off[name] = text(why or 'unread')
    LAB.rec('corpse_off', { name = name, why = st.off[name], kept = #st.corpses }, true)
end
-- May the name run now? true | nil (wait: a pending sig, a frame) | false (off: closed now or before)
local function may(name)
    if st.off[name] then return false end
    if SENT.is_disabled(name) then close(name, 'disabled') return false end
    local ok, why = LAB.sig(name)
    if ok then return true end
    if why == 'sig_pending' then return nil end
    close(name, why or 'sig_unknown')
    return false
end
-- lab_slice's bookkeeping (Lua only): a key the slicer cut, a key a slicer job holds now
local function slice_mod()
    local m = package.loaded['lab_slice']
    return type(m) == 'table' and m or nil
end
local function sliced(key)
    local m = slice_mod()
    return m ~= nil and type(m.sliced) == 'function' and m.sliced(key) == true
end
local function slicing(key)
    local m = slice_mod()
    return m ~= nil and type(m.busy) == 'function' and m.busy(key) == true
end
-- The writes and calls of this module: pinned (else closed: 'unpinned'), on and not under the vanilla compare
local function live()
    local p = LAB.pinned()
    if p == false then close('corpse.keep', 'unpinned') return false end
    return p == true and MODOFF.enabled('lab_corpse')
end

-- ---------- identities ----------
local function keep_of(x)
    if type(x) == 'table' and rawget(x, '__mock') == nil then return x.keep or (x.obj ~= nil and x or nil) end
    return ue.keep(x)
end
-- The player's location (bus lab_pawn's pawn, ue.root_loc) or nil
local function player_loc()
    if st.pawn_in ~= nil then
        local rec = st.pawn_in
        st.pawn_in = nil
        local kp = type(rec) == 'table' and keep_of(rec.pawn or rec.keep or rec.obj) or nil
        if kp then st.pawn = kp end
    end
    local p = st.pawn and ue.live(st.pawn) or nil
    return p and ue.root_loc(p) or nil
end
local function dist_m(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z) / 100
end
-- Why a pawn is not kept ('player', 'not_enemy', the corpse_skip word), else nil
local function skip_why(obj, class)
    if ue.is_a(obj, K.PLAYER) == true or ue.is_a(obj, K.RENEWAL_PLAYER) == true then return 'player' end
    if ue.is_a(obj, K.RENEWAL) ~= true then return 'not_enemy' end
    local s = SKIP and class and SKIP[class]
    if s then return s end
    return nil
end

-- ---------- levers ----------
-- The three values now, each only on its declaring class: the value when it has the lever's Lua type, else 'unread'
local function read_levers(obj)
    local has = { RENEWAL = ue.is_a(obj, K.RENEWAL) == true, NPC_BASE = ue.is_a(obj, K.NPC_BASE) == true }
    local prev = {}
    for _, l in ipairs(K.LEVERS) do
        local v = nil
        if has[l.cls] then v = ue.prop(obj, l.prop) end
        if type(v) == type(l.v) then prev[l.key] = v else prev[l.key] = 'unread' end
    end
    return prev
end
local function ours(prev) return num(prev.destroy_delay) and math.abs(prev.destroy_delay - K.MARK) <= K.MARK_EPS end
local function vanilla(prev) return prev.disable_dissol == false and prev.destroy_after == true end
-- The corpse.keep job: every lever written and read back; one that does not read back puts the ones written back
-- (a half-kept pawn would be an invisible actor) and raises
local function lever_job(obj, prev)
    local done = {}
    for _, l in ipairs(K.LEVERS) do
        local _, got, why = L.set_checked(obj, l.prop, l.v)
        local good = why == nil and (type(l.v) ~= 'number' and got == l.v or num(got) and math.abs(got - l.v) <= K.MARK_EPS)
        if not good then
            for _, d in ipairs(done) do L.set_checked(obj, d.prop, prev[d.key]) end
            error(l.key .. ': ' .. tostring(why or ('readback ' .. tostring(got))), 0)
        end
        done[#done + 1] = l
    end
    return #done
end

-- ---------- pawns and corpses ----------
local function plist_drop(p)
    for i, x in ipairs(st.plist) do
        if x == p then table.remove(st.plist, i) break end
    end
    st.pawns[p.key] = nil
end
local function corpse_drop(c)
    for i, x in ipairs(st.corpses) do
        if x == c then table.remove(st.corpses, i) break end
    end
end
local function mark_dead(key)
    if st.dead[key] then return end
    st.dead[key] = true
    st.dead_list[#st.dead_list + 1] = key
    if #st.dead_list > K.DEAD then st.dead[table.remove(st.dead_list, 1)] = nil end
end
-- A written pawn died (g: game seconds of the death; via 'bus', 'health' or 'adopt'): a kept corpse
local function to_corpse(p, g, via)
    plist_drop(p)
    if #st.corpses >= K.CORPSES_HARD then
        st.n.full = st.n.full + 1
        return
    end
    p.state, p.g_dead, p.via, p.t_dead = 'corpse', g, via, now()
    st.corpses[#st.corpses + 1] = p
end
-- The writes stop when nothing could make a kept corpse go ('corpse.destroy' off or struck)
local function destroy_off()
    if st.off['corpse.destroy'] then return true end
    if SENT.is_disabled('corpse.destroy') then close('corpse.destroy', 'disabled') return true end
    return false
end
-- One write a frame: the first pawn that wants it and is due for a look. A pawn not alive yet is read again WAIT_S
-- later; a foreign one is left alone; ours (a hot reload) is adopted
local function write_step(g)
    local n = #st.plist
    if n == 0 then return end
    local ks = CFG.knob('corpse_keep_s')
    if not (num(ks) and ks > 0) or destroy_off() then
        if not st.gate_traced then st.gate_traced = true trace('write', 'gate', nil, { keep_s = ks }) end
        return
    end
    local ok = may('corpse.keep')
    if not ok then
        if not st.may_traced then st.may_traced = true trace('write', 'may', nil, { ok = tostring(ok) }) end
        return
    end
    for _ = 1, n do
        st.wrr = st.wrr % n + 1
        local p = st.plist[st.wrr]
        if p and p.state == 'want' and g >= (p.next_g or 0) then
            local obj = LAB.alive(p.rec or p.keep)
            if not obj then
                p.tries = (p.tries or 0) + 1
                if p.tries < K.RESOLVE_N then
                    p.next_g = g + K.RESOLVE_S                -- not live yet: looked at again
                    return
                end
                plist_drop(p)
                st.n.left = st.n.left + 1
                trace('write', 'never_live', p.class, { tries = p.tries })
                return
            end
            if p.unresolved then
                p.unresolved = nil
                local why = skip_why(obj, p.class)
                if why then
                    plist_drop(p)
                    st.n.skipped = st.n.skipped + 1
                    trace('write', why, p.class)
                    return
                end
            end
            local prev = read_levers(obj)
            if not p.again and ours(prev) then
                st.n.adopted = st.n.adopted + 1
                p.prev = { disable_dissol = false, destroy_after = true, destroy_delay = 'unread' }
                local h = ue.health(obj)
                if num(h) and h <= 0 then return to_corpse(p, g, 'adopt') end
                p.state, p.alive_seen = 'kept', num(h) and h > 0
                return
            end
            if not p.again and not vanilla(prev) then
                plist_drop(p)
                if prev.disable_dissol == true or prev.destroy_after == false then
                    st.n.foreign = st.n.foreign + 1          -- another mod keeps it: never touched, never expired
                    trace('write', 'foreign', p.class, { prev = prev })
                else
                    st.n.unread = st.n.unread + 1            -- a lever read no value: never written blind
                    trace('write', 'unread', p.class, { prev = prev })
                end
                return
            end
            local h = ue.health(obj)
            if not (num(h) and h > 0) then
                if not p.wait_traced then p.wait_traced = true trace('write', 'not_alive', p.class, { h = tostring(h) }) end
                p.next_g = g + K.WAIT_S                      -- not alive yet (or a corpse): looked at again later
                return                                       -- one pawn looked at a frame
            end
            local r, err = LAB.armed('corpse.keep', lever_job, obj, prev)
            if err ~= nil or r == nil then
                plist_drop(p)
                st.n.write_fail = st.n.write_fail + 1
                close('corpse.keep', err or 'unread')
                trace('write', 'fail', p.class, { err = tostring(err) })
                return
            end
            if not p.again then
                trace('write', 'kept', p.class)
                p.prev = { disable_dissol = prev.disable_dissol, destroy_after = prev.destroy_after,
                    destroy_delay = prev.destroy_delay }
                st.n.kept = st.n.kept + 1
                LAB.count('corpse_kept')
            else
                st.n.rewrites = st.n.rewrites + 1
            end
            p.state, p.again, p.alive_seen, p.t_write = 'kept', nil, true, now()
            return
        end
    end
end
-- Once a second, K.CHECK_N written pawns round-robin, property reads only: gone, an unseen death, a lever written back
local function check_pawns(g)
    local n = #st.plist
    for _ = 1, math.min(K.CHECK_N, n) do
        if #st.plist == 0 then return end
        st.rr = st.rr % #st.plist + 1
        local p = st.plist[st.rr]
        if p.state == 'kept' then
            local obj = LAB.alive(p.keep)
            if not obj then
                plist_drop(p)
                st.n.left = st.n.left + 1
            else
                local h = ue.health(obj)
                if num(h) and h > 0 then
                    p.alive_seen = true
                    local now_v = read_levers(obj)
                    if now_v.disable_dissol == false or now_v.destroy_after == true then
                        p.state, p.again = 'want', true             -- the game wrote a lever back: written again
                    end
                elseif num(h) and p.alive_seen then
                    st.n.unseen_deaths = st.n.unseen_deaths + 1
                    mark_dead(p.key)
                    to_corpse(p, g, 'health')
                end
            end
        end
    end
end

-- ---------- the going (corpse_keep_s, corpse_max) ----------
-- One corpse_keep record (forced) and the counters; the corpse's cut list goes; a sliced corpse's bus lab_slice_gone
-- (header)
local function gone_rec(c, why, how, gone_why)
    st.n.gone = st.n.gone + 1
    st.why[why] = (st.why[why] or 0) + 1
    LAB.count('corpse_gone')
    local cut = sliced(c.key)
    LAB.rec('corpse_keep', { id = c.id, class = c.class, age_s = c.g_dead and r1(gnow() - c.g_dead) or 'unread',
        why = why, how = how, gone_why = gone_why, due = c.due, dist_m = c.dist and r1(c.dist) or 'unread',
        via = c.via, err = c.err, sliced = cut or nil }, true)
    st.cuts[c.key] = nil
    if cut then BUS.emit('lab_slice_gone', { key = c.key, id = c.id, why = why, how = how }) end
end
local function seen_job(obj)
    local ok, v = ue.call(obj, 'WasRecentlyRendered', K.SEEN_TOL_S)
    if not ok then error(tostring(v), 0) end
    if type(v) ~= 'boolean' then return nil end
    return v
end
-- The vanilla look: Vanish() after its arity check (once a session) and the dissolve lever back to its read value
local function vanish_job(obj, c)
    if st.vanish_sig == nil then
        local ok, why = ue.sig_ok(K.VANISH, {}, 'corpse.vanish')
        st.vanish_sig = ok == true
        if not st.vanish_sig then error('vanish ' .. tostring(why or 'sig_mismatch'), 0) end
    elseif st.vanish_sig == false then
        error('vanish sig_mismatch', 0)
    end
    if c.prev and c.prev.disable_dissol == false then L.set_checked(obj, 'DisableDeathDissol', false) end
    local ok, err = ue.call(obj, 'Vanish')
    if not ok then error(tostring(err), 0) end
    return true
end
local function destroy_job(obj)
    local ok, why = US.destroy_actor(obj)
    if not ok then error(tostring(why or 'unread'), 0) end
    return true
end
-- The destroy (how: 'destroy' or 'vanish_destroy'): true once the corpse is done (gone or stuck), false to wait a frame.
-- A sliced corpse goes under 'slicer.gone' (header)
local function destroy(c, obj, how)
    local gone = sliced(c.key)
    local name = gone and 'slicer.gone' or 'corpse.destroy'
    local ok = may(name)
    if ok == nil then return false end
    if ok then
        local _, err = LAB.armed(name, destroy_job, obj)
        if err == nil then
            corpse_drop(c)
            st.n.destroyed = st.n.destroyed + 1
            gone_rec(c, c.why, how)
            return true
        end
        c.err = text(err)
        close(name, err)
    end
    corpse_drop(c)                                       -- nothing makes it go now: it stays until the map changes
    st.n.stuck = st.n.stuck + 1
    st.cuts[c.key] = nil
    return true
end
-- A sliced corpse's failed vanish closes only this (header): 'slicer.gone' stays open for its destroy
local VANISH_SLICED = 'slicer.gone.vanish'
-- A due corpse goes (why): its cuts expire (the Pieces and gibs follow it), then the vanish, else the destroy
local function go(c, obj, why, g)
    c.why = why
    for _, cut in ipairs(st.cuts[c.key] or {}) do cut.expired = true end
    local gone = sliced(c.key)
    local name = gone and 'slicer.gone' or 'corpse.vanish'
    local v = not (gone and st.off[VANISH_SLICED]) and may(name)
    if v then
        local _, err = LAB.armed(name, vanish_job, obj, c)
        if err == nil then
            c.state, c.v_g = 'vanishing', g
            st.n.vanished = st.n.vanished + 1
            return
        end
        c.err = text(err)
        close(gone and VANISH_SLICED or name, err)
    end
    destroy(c, obj, 'destroy')
end
-- The Caps of a vanishing corpse hide (lab_cap C.fade under 'hide.comp', as lab_fade does at a vanilla dissolve)
local function fade_caps(c)
    c.capfade = true
    local Cm = package.loaded['lab_cap']
    if type(Cm) ~= 'table' or type(Cm.fade) ~= 'function' or SENT.is_disabled('hide.comp') then return end
    if not LAB.sig('hide.comp') then return end
    for _, cut in ipairs(st.cuts[c.key] or {}) do
        if type(cut.slot) == 'table' and not cut.faded then
            local _, err = LAB.armed('hide.comp', Cm.fade, cut.slot)
            if err == nil then
                cut.faded, cut.fade_t, cut.fade_why = true, now(), 'corpse'
                st.n.cap_fades = st.n.cap_fades + 1
            end
        end
    end
end
-- Every frame: the vanishing corpses (the Caps at CAP_FADE_S, the destroy at VANISH_S; one destroy a frame)
local function vanishing(g)
    for _, c in ipairs({ table.unpack(st.corpses) }) do
        if c.state == 'vanishing' then
            if not c.capfade and g >= c.v_g + K.CAP_FADE_S then fade_caps(c) end
            if g >= c.v_g + K.VANISH_S then
                local obj = LAB.alive(c.keep)
                if not obj then
                    corpse_drop(c)
                    gone_rec(c, c.why, 'vanish')
                else
                    destroy(c, obj, 'vanish_destroy')
                    return
                end
            end
        end
    end
end
-- Once a second: the corpses the game took; the due ones (corpse_max, corpse_keep_s); the goings, oldest first
local function expire(g)
    if not st.corpses[1] then return end
    local keep_s, max = CFG.knob('corpse_keep_s'), CFG.knob('corpse_max')
    keep_s, max = num(keep_s) and keep_s or 900, num(max) and max or 60
    local waiting = {}
    for _, c in ipairs({ table.unpack(st.corpses) }) do
        if c.state == 'corpse' then
            local obj, why = LAB.alive(c.keep)
            if not obj then
                corpse_drop(c)
                gone_rec(c, 'gone', 'gone', why)
            else
                waiting[#waiting + 1] = c
            end
        end
    end
    for i = 1, #waiting - max do
        local c = waiting[i]
        if not c.due then c.due, c.due_g = 'cap', g end
    end
    local ploc, gone_n, seen_n = nil, 0, 0
    for _, c in ipairs(waiting) do
        if not c.due and g - c.g_dead >= keep_s then c.due, c.due_g = 'time', g end
        if c.due and gone_n < K.GO_PER_S and not slicing(c.key) then
            local obj = LAB.alive(c.keep)
            if obj then
                ploc = ploc or player_loc()
                local loc = ue.root_loc(obj)
                c.dist = ploc and loc and dist_m(ploc, loc) or nil
                local why = nil
                if c.dist and c.dist > K.FAR_M then
                    why = 'far'
                elseif g >= c.due_g + K.LATE_S then
                    why = c.due
                elseif seen_n < K.SEEN_PER_S and may('corpse.seen') then
                    seen_n, st.n.seen_reads = seen_n + 1, st.n.seen_reads + 1
                    local v, err = LAB.armed('corpse.seen', seen_job, obj)
                    if err ~= nil then close('corpse.seen', err) elseif v == false then why = 'unseen' end
                end
                if why then
                    gone_n = gone_n + 1
                    go(c, obj, why, g)
                end
            end
        end
    end
end

-- ---------- the bus (listeners only queue or note) ----------
local function push(e)
    if #st.inbox >= K.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    st.inbox[#st.inbox + 1] = e
end
local function on_admit(rec, class)
    if type(rec) ~= 'table' or rec.key == nil or rec.keep == nil then
        trace('bus', 'bad_admit', class, { rec = type(rec), key = type(rec) == 'table' and tostring(rec.key) or nil })
        return
    end
    push({ k = 'admit', rec = rec, class = class or rec.class })
end
local function on_death(d)
    if type(d) ~= 'table' or d.key == nil then return end
    push({ k = 'death', key = d.key, id = d.id })
end
local function on_revive(rec)
    if type(rec) ~= 'table' or rec.key == nil then return end
    push({ k = 'revive', key = rec.key })
end
local function on_cut_live(cut)
    if type(cut) ~= 'table' or cut.key == nil then return end
    local list = st.cuts[cut.key]
    if not list then
        if #st.cut_keys >= K.CUT_KEYS then st.cuts[table.remove(st.cut_keys, 1)] = nil end
        list = {}
        st.cuts[cut.key] = list
        st.cut_keys[#st.cut_keys + 1] = cut.key
    end
    for _, c in ipairs(list) do if c == cut then return end end
    if #list < K.CUTS then list[#list + 1] = cut end
end
local function on_cut_gone(cut)
    local list = type(cut) == 'table' and cut.key ~= nil and st.cuts[cut.key] or nil
    if not list then return end
    for i, c in ipairs(list) do
        if c == cut then table.remove(list, i) break end
    end
end
-- The queued events, in order (Lua only): an admission makes a pawn that wants its write; a death makes a kept pawn
-- a corpse and drops a waiting one; a revive makes a corpse a kept pawn again
local function drain(g)
    if not st.inbox[1] then return end
    local q = st.inbox
    st.inbox = {}
    for _, e in ipairs(q) do
        if e.k == 'admit' then
            local key = e.rec.key
            if not st.pawns[key] and not st.dead[key] then
                -- an admission comes at the pawn's construction (the class watch, a spawn press): not live yet there
                -- (TC-BETA-01e: every pawn read 'gone' and was dropped for good), so a pawn not live yet waits as
                -- 'want' with the class checks left to write_step, which looks again every RESOLVE_S
                local obj = LAB.alive(e.rec)
                local why = obj and skip_why(obj, e.class) or nil
                if why then
                    st.n.skipped = st.n.skipped + 1
                    trace('admit', why, e.class)
                elseif #st.plist >= K.PAWNS then
                    st.n.full = st.n.full + 1
                else
                    local p = { key = key, keep = e.rec.keep, rec = e.rec, id = e.rec.id, class = e.class, state = 'want',
                        g0 = g, unresolved = obj == nil or nil, tries = 0 }
                    st.pawns[key] = p
                    st.plist[#st.plist + 1] = p
                    st.n.admitted = st.n.admitted + 1
                    trace('admit', obj and 'want' or 'pending', e.class)
                end
            end
        elseif e.k == 'death' then
            mark_dead(e.key)
            local p = st.pawns[e.key]
            if p and p.state == 'kept' then
                if e.id ~= nil then p.id = e.id end
                to_corpse(p, g, 'bus')
            elseif p then
                plist_drop(p)                            -- it died before its write: the vanilla corpse
                st.n.died_first = st.n.died_first + 1
                trace('death', 'died_first', p.class, { state = p.state })
            end
        elseif e.k == 'revive' then
            st.dead[e.key] = nil
            for i, c in ipairs(st.corpses) do
                if c.key == e.key and c.state == 'corpse' then
                    table.remove(st.corpses, i)
                    c.state, c.g_dead, c.due, c.due_g, c.alive_seen = 'kept', nil, nil, nil, true
                    st.pawns[c.key] = c
                    st.plist[#st.plist + 1] = c
                    st.n.revived = st.n.revived + 1
                    break
                end
            end
        end
    end
end

-- ---------- the ticker ----------
local function tick()
    if not st.init then return end
    local g = gnow()
    drain(g)
    if LAB.paused() then return end
    if not live() then
        if not st.live_traced then
            st.live_traced = true
            trace('tick', 'not_live', nil, { pinned = tostring(LAB.pinned()), on = MODOFF.enabled('lab_corpse') })
        end
        return
    end
    write_step(g)
    if st.corpses[1] then vanishing(g) end
    if LAB.due('lab_corpse', K.CHECK_S) then
        check_pawns(g)
        expire(g)
    end
end
local EVENTS = { 'lab_admit', 'lab_death', 'lab_revive', 'lab_cut_live', 'lab_cut_gone', 'lab_pawn' }

-- ---------- lifecycle ----------
function K.kept() return st.corpses end
-- A: the main.lua feature view (clock; LAB holds the records). Inert outside the beta
function K.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    local ok, data = pcall(require, 'data.corpse_skip')
    SKIP = ok and type(data) == 'table' and type(data.classes) == 'table' and data.classes or {}
    st.init = true
    LAB.names(N, F)
    if (LAB.CAPS.corpse_keep or 0) < K.CAP_RECORDS then LAB.CAPS.corpse_keep = K.CAP_RECORDS end
    for _, k in ipairs({ 'corpse_kept', 'corpse_gone' }) do LAB.count(k, 0) end
    LAB.gauge('corpses_kept', function() return #st.corpses end)
    MODOFF.feature('lab_corpse', { gameplay = true })   -- off and the vanilla compare hold every write and going
    BUS.on('lab_admit', 'lab_corpse', on_admit)
    BUS.on('lab_death', 'lab_corpse', on_death)
    BUS.on('lab_revive', 'lab_corpse', on_revive)
    BUS.on('lab_cut_live', 'lab_corpse', on_cut_live)
    BUS.on('lab_cut_gone', 'lab_corpse', on_cut_gone)
    BUS.on('lab_pawn', 'lab_corpse', function(rec) st.pawn_in = rec end)
    S.ticker('lab_corpse', tick)
    return true
end
-- A map load: every pawn and corpse went with the old map: one corpse_keep record per kept corpse (why 'map', no
-- engine call)
function K.reset()
    if not st.init then return end
    for _, c in ipairs(st.corpses) do gone_rec(c, 'map', 'map') end
    st.n.map_drop = st.n.map_drop + #st.corpses + #st.plist
    st.inbox, st.pawns, st.plist, st.corpses, st.cuts, st.cut_keys = {}, {}, {}, {}, {}, {}
    st.dead, st.dead_list, st.rr, st.wrr, st.pawn = {}, {}, 0, 0, nil
end
function K.status()
    local out = { init = st.init, pawns = #st.plist, corpses = #st.corpses, qdrop = st.qdrop,
        off = next(st.off) and st.off or nil, why = st.why, keep_s = CFG.knob('corpse_keep_s'),
        max = CFG.knob('corpse_max') }
    for k, v in pairs(st.n) do out[k] = v end
    return out
end
function K.shutdown()
    S.remove_ticker('lab_corpse')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_corpse') end
    st, A = new_state(), nil
end
return K
