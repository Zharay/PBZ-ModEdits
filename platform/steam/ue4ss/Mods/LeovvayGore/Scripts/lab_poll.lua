-- status: new in M0 S2.12 (offline only; TC-LAB-01 stage 0 decides) origin: kb:runtime-safety-perf#ue4ss-identity-safe-caches-delayed-steps-and-destroy
-- lab_poll.lua: TC-LAB-01 stage 0 victims, the 10 Hz death poll and the kill records (spec M0 S2.12, D1, D11, D31;
-- DESIGN C8, C11). Probe and dev builds (META.lab_modules) and the player beta (META.beta_modules). Observe only: no
-- engine write, no UFunction call.
-- * Victim set (D31): ue.keep records from the BP_RenewalNPC_C class watch (the callback runs during construction and
--   keeps only {obj, name, epoch}; Default__ is skipped), from hook params (bus lab_hit, below) and from one
--   ue.find_all of BP_RenewalNPC_C FIND_AFTER_S after each map load through LAB.armed('lab.findall') on a one-shot frame,
--   kept only within FIND_UU (50 m) of the pawn (it waits for the pawn's location). Each entry is a LAB.victim record,
--   read only after LAB.live: the first failed check ends it with its reason (gone, reused, stale), never read again.
-- * The player never enters the set (D1, the author's «1: never cut»): ue.is_a PBZCharacter_Player (the co-op second Hun
--   too) or the bus lab_pawn pawn; each excluded object counts once in status().excluded_player.
-- * Distances only from ue.root_loc (RootComponent -> RelativeLocation, property reads, D11), refreshed round-robin
--   (DIST_PER_TICK entries per poll, each after LAB.live).
-- * Poll every POLL_S through LAB.due (paused frames skip it) for victims hit in the last HIT_S or within NEAR_UU (30 m):
--   ue.health and ue.tags. Death = Health <= 0 or the CharacterState.Dead tag on a victim seen alive: a read showed it
--   alive, or a hook hit it at most KILL_S before the read (its newest snapshot). Admission is no proof of life: a
--   constructed NPC can read Health 0 before its attributes are set, and a victim that died unobserved (far, not hit)
--   is a corpse when the poll first meets it; neither is a kill. A new entry gets its distance and hit time at once.
--   One kill record per life (C8, C11): the life steps at the confirmed death (LAB.next_life); a revive reads alive.
-- * Kill record (section 3.1, C11, plus blow_src and killer_src) from LAB.snaps(key) since the life began; see
--   build_kill; spawned true (else absent) when lab_spawn's key spawned the victim (dev build, D32: it sets spawned
--   on the LAB.victim record, nothing on the pawn). The probe and the spawn set write it at confirm with no outcome,
--   commit_ms or actions (M0, unchanged); the lab02 set holds it (M1a D5, below).
--   Then death_poll, the PhysicsHits
--   keys under the always-armed 'lab.read.tmap' (phys_hits, 'unread' on failure), GetBindings of
--   AttributeComponent.OnDeath and PBZCharacter.OnCharacterDie once per pair label under 'lab.read.multicast'
--   (kill.bindings), counters.poll_deaths and bus lab_death.
-- * Fodder (section 3.1) on lab_flush, queued through LAB.post: one record per pair label (MaleThug, GuiChai, other,
--   zero members included) from session tallies a map load keeps. members: victims the poll read at least once.
-- Inputs from lab_kill.lua (S2.11): snapshots pushed with LAB.snap_push(LAB.victim(obj).key, snap), read by the
-- hook_fire field names (key = the hook id, t, bone, body_bone, socket, attack_dir, sweep_dir, cause, source_class,
-- attack_type, final_attack_type, sharp, blunt, killer, killer_src, die_reason, damage_tags, by_player, ev_id,
-- source_seen, payload_skipped, hit_loc (fixes-0.2.2 B3.4); the beta's hit_strength, origin_strength, anim_strength,
-- hit_state, bullet, bullet_dir, skill_type, bd_strength, bd_dir, bd_origin, owner_is_pawn, seq: BD3); bus
-- lab_hit(v, t, key) with v a LAB.victim record, a ue.keep record or the object, for each victim a hook param names
-- (listeners only queue).
-- M1a A3.1 (D5, D6, D27; sections 3.1, 3.3, 3.9):
-- * Bus lab_admit(rec, class, via) once per admission (via 'watch', 'hit' or 'findall'), from the tick; lab_revive(rec,
--   life) once per confirmed death when the victim then reads alive REVIVE_READS times in a row (life: the one that
--   ended). Both in every set: bus only, no record (spec M1a rule 9).
-- * lab_death's payload gains attack_dir and sweep_dir (fresh copies from the kill's blow snapshot), death_src, death_t
--   and corpse_life (= kill.life). death_src: 'hook:<id>' when data/lab_pairs.lua death_source names a hook that fired
--   this life (death_t: its first fire), else 'poll' (death_t: the confirm).
-- * lab02 set (LAB.cut_set()): P.confirm holds the kill (st.pending[id], death_src on it) and writes it once, forced,
--   on bus lab_outcome(id, {row, outcome, why, commit_ms, actions, cut_ms}), at OUTCOME_S of game time (refused,
--   'no_outcome': a failure), at lab_end ('lab_end'), a map load or a hot reload ('stale'); counted per M.counted; a
--   later outcome is ignored (status().late). A timed-out record keeps the row lab_plan's bus lab_row named. commit_ms
--   counts from the death source event, total_ms from the death frame's first hook snapshot; death_poll stays at
--   confirm.
-- * The player beta (LAB.beta(), beta port S5; a cut set): no PhysicsHits and no GetBindings read (two armed native
--   reads per death), the kill record written at confirm (plain, with death_src: a limb cut sends no lab_outcome, so a
--   held record would read refused 'no_outcome'; the cut record carries commit_ms), no fodder record. The lab_death
--   payload is unchanged, and the death source's next-tick read below runs as in lab02.
-- * lab02 set with a death_source: a lab_hit naming that hook (or a victim whose snapshots show a newer fire of it)
--   reads the victim on the next frame instead of its 10 Hz slot. The probe and the spawn set keep the 10 Hz poll:
--   TC-LAB-01 measures its latency (death_poll.lat_ms).
-- * blow_of 'source': the bullet system's melee strike (PBZ_BulletAttackModule, a SweepTrace bullet data asset) reads
--   'melee', never 'shot' (spec M1a 4.0, KF19); only projectile bullets are shots.
-- * The beta's kill tier (docs/research/beta-dismemberment-plan.md BD3, research H3; the contract in lab_census.lua's
--   header, with the author's answers of 2026-10-31): build_kill adds, from the death frame's snapshots (lab_kill's
--   strength tags and bullet hop), tier, tier_src, tier_parts, skill_type, strength, anim_strength, origin_strength,
--   attack_type, bullet, frame_bullets, attack_kind and bleed_only, and bd_dir (the bullet's AttackDirection tag,
--   absent when unread; spec fixes-0.2.2 D2); a poll kill reads normal, none and 'unread'. Pure Lua (P.tier); every
--   missing datum gives normal. P.confirm adds each beta kill to the session's tier tallies, and a lab_flush writes
--   one tier_tally record (P.tier_tally) in place of fodder.
-- * fixes-0.2.2 B3.2 (D2): the kill's bone is the fine HitBone only; a frame with only a coarse reading
--   (HitBodyData.bone, HitBody.SocketName) logs it as coarse with bone_src 'coarse' (build_kill).
-- * fixes-0.2.2 B3.4 (D4): kill.hit_loc, the blow's non-zero HitLocation (lab_kill's hit_loc), else the death frame's
--   same-source one (pick), and kill.root, the victim's ue.root_loc at the confirm (a property read this file already
--   makes), both {x, y, z} rounded to 0.1 cm and absent when unread. Set before any kill record is written, so the
--   record and lab_death's kill carry them. Logged only: no part choice reads them (HL.1 waits for TC-FIX022-G2).
-- API: seen(v, t, key); counted(outcome, why); pending(id) (spec 3.9 'LAB.pending', for tests); tier_parts(tier) (BD3:
-- the parts a kill tier asks for, live from the knobs); lifecycle init(A, opts) shutdown(reason) status()
-- reset(reason).
-- What the mock cannot prove: payload types and hook order (the snapshots here are test-made), the real TMap and
-- multicast marshalling, native faults inside the armed reads, real timing (the death source's real fire order and
-- its lag behind Health 0 on PBZ).
local BUS = require('core.bus')
local S = require('core.sched')
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local M = { RENEWAL = '/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C',
    RENEWAL_SHORT = 'BP_RenewalNPC_C', PLAYER = '/Script/ProjectPBZ.PBZCharacter_Player',
    POLL_S = 0.1, HIT_S = 10, KILL_S = 0.5, JOIN_S = 0.05, NEAR_UU = 3000, FIND_UU = 5000, FIND_AFTER_S = 5,
    DIST_PER_TICK = 16, READS_PER_TICK = 48, VICTIMS = 256, INBOX = 512, FIND_CAP = 512, PHYS_CAP = 16, BIND_CAP = 16,
    DEAD_TAG = 'CharacterState.Dead', LABELS = { 'MaleThug', 'GuiChai', 'other' },
    OUTCOME_S = 2.0, REVIVE_READS = 2, FRAME_BULLETS = 8, TIER_ROWS = 48 }
-- The beta's kill tier (BD3): the words of the kill fields (the tallies count each), the knob of each tier's parts
M.TIERS = { 'normal', 'heavy', 'shaqi' }
M.TIER_SRCS = { 'none', 'skill', 'path', 'surge', 'attack_type', 'name', 'strength' }
M.KINDS = { 'weapon', 'kick', 'deflect', 'status', 'unread' }
M.TIER_KNOB = { heavy = 'heavy_parts', shaqi = 'shaqi_parts' }

-- Names this module reads (D28): property chains only, no UFunction (props: usmap_props.tsv lines; sp: struct paths)
local N = {}
local F = {
    {"/Script/ProjectPBZ.PBZCharacter", "AttributeSetBase"},
    {"/Script/ProjectPBZ.PBZCharacter", "CharacterTags"},
    {"/Script/ProjectPBZ.PBZCharacter", "OnCharacterDie"},
    {"/Script/CharacterBasics.BasicAttributeSet", "Health"},
    {"/Script/GameplayAbilities.GameplayAttributeData", "CurrentValue"},
    {"/Script/GameplayTags.GameplayTagContainer", "GameplayTags"},
    {"/Script/GameplayTags.GameplayTag", "TagName"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.SceneComponent", "RelativeLocation"},
    {"/Script/Engine.SceneComponent", "AttachParent"},
    {"/Script/SGameCombatSystem.HitreactComponent", "PhysicsHits"},
    {"/Script/SGameAttributes.AttributeComponent", "OnDeath"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "Hitreact Component"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "Attribute Component"},
}
M.N, M.F = N, F

local A = nil
local token = 0                                  -- the live watch's token: an older init's watch unregisters itself
-- The beta's tier tallies for the session (BD3): kills, the poll kills, another's kills (by_player false), the
-- status-only frames and the frames with hits but no bullet; per tier, tier_src and attack_kind; rows per (tier,
-- by_player, skill_type, combo class, origin_strength, attack_type), at most TIER_ROWS (more: the kills past them)
local function new_tiers()
    local x = { kills = 0, poll = 0, not_player = 0, status_only = 0, no_bullet = 0, tiers = {}, srcs = {}, kinds = {},
        rows = {}, list = {}, more = 0 }
    for _, w in ipairs(M.TIERS) do x.tiers[w] = 0 end
    for _, w in ipairs(M.TIER_SRCS) do x.srcs[w] = 0 end
    for _, w in ipairs(M.KINDS) do x.kinds[w] = 0 end
    return x
end
local function new_state()
    return { set = {}, list = {}, n = 0, inbox = {}, dropped = 0, full = 0, excluded = {}, excluded_player = 0,
        refused = 0, left = { gone = 0, reused = 0, stale = 0 }, pawn = nil, pawn_in = nil, pawn_class = nil,
        pawn_loc = nil, find_at = nil, find = 'none', found = nil, cur = 0, rr = 0, reads = 0, read_fail = 0,
        deaths = 0, candidates = 0, tally = {}, bound = {}, watch = false, init = false,
        -- M1a A3.1: admissions, revives; the held kill records (D5); the death source's next-tick reads (D6)
        admits = 0, revives = 0, pending = {}, npending = 0, seq = 0, outq = {}, rowq = {}, end_due = false,
        ended = false, late = 0, written = 0, qdrop = 0, ds = nil, fast = false, urgent = false, fastq = {},
        fast_reads = 0, tiers = new_tiers() }
end
local st = new_state()
local P = {}                                     -- the poll and record steps (fields, so their order is free)

local function now() return A and A.clock and A.clock.real() or 0 end

-- ---------- identity: an object from a LAB.victim record, a ue.keep record or the object itself ----------
local function obj_of(x)
    if type(x) == 'table' and rawget(x, '__mock') == nil then
        if x.keep ~= nil then return (LAB.live(x)) end
        if x.obj ~= nil then return (ue.live(x)) end
        return nil
    end
    return ue.valid(x) and x or nil
end
local function class_of(o)
    local full = ue.full(o)
    return full and full:match('^(%S+) ') or nil
end
local function dist(a, b)
    if not (a and b) then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function is_player(o)
    if ue.is_a(o, M.PLAYER) == true then return true end
    local p = st.pawn and ue.live(st.pawn)
    return p ~= nil and ue.same(o, p)
end

-- ---------- admission (on the poll tick, never inside a hook or a watch callback) ----------
-- Queue only: safe inside a hook body, a watch callback or a bus listener
local function queue(x, via, t, key)
    if x == nil then return false end
    if #st.inbox >= M.INBOX then
        st.dropped = st.dropped + 1
        return false
    end
    st.inbox[#st.inbox + 1] = { x = x, via = via, t = t, key = key }
    return true
end
function M.seen(v, t) return queue(v, 'hit', t or now()) end
-- The newest hook snapshot time of this life (lab_kill's LAB.snap_push) into v.hit_t
local function note_hits(v)
    local s = LAB.snaps(v.key, v.life_t0)
    local last = s[#s]
    if last and last.t and (v.hit_t == nil or last.t > v.hit_t) then v.hit_t = last.t end
end

local function admit(x, via, t)
    local rec, why
    if type(x) == 'table' and rawget(x, '__mock') == nil and x.key ~= nil and x.keep ~= nil then
        rec = x
        if not LAB.live(rec) then rec, why = nil, 'gone' end
    else
        rec, why = LAB.victim(x)
    end
    if not rec then
        st.refused = st.refused + 1
        return nil, why
    end
    local v = st.set[rec.key]
    if v then
        if t and (v.hit_t == nil or t > v.hit_t) then v.hit_t = t end
        return v
    end
    if st.excluded[rec.key] then return nil, 'player' end
    local o = LAB.live(rec)
    if not o then return nil, 'gone' end
    if is_player(o) then
        st.excluded[rec.key], st.excluded_player = true, st.excluded_player + 1
        return nil, 'player'
    end
    if st.n >= M.VICTIMS then
        st.full = st.full + 1
        return nil, 'full'
    end
    v = { rec = rec, key = rec.key, class = rec.class, via = via, alive = nil, hit_t = t, life_t0 = nil,
        dist = dist(ue.root_loc(o), st.pawn_loc), member = false }
    note_hits(v)
    st.set[rec.key], st.n = v, st.n + 1
    st.list[#st.list + 1] = v
    st.admits = st.admits + 1
    BUS.emit('lab_admit', rec, rec.class, via)          -- A3.1: once per admission (lab_spawn's match, D12)
    return v
end
local function drain()
    if not st.inbox[1] then return end
    local box = st.inbox
    st.inbox = {}
    for _, e in ipairs(box) do
        local v = admit(e.x, e.via, e.t)
        if v and st.fast and e.via == 'hit' then P.mark(v, e.key, e.t) end
    end
end
-- A victim leaves the set at its first failed LAB.live, with the reason, and is never read again
local function leave(v, why)
    v.out = true
    st.set[v.key], st.n = nil, st.n - 1
    st.left[why] = (st.left[why] or 0) + 1
end
local function compact()
    local keep = {}
    for _, v in ipairs(st.list) do if not v.out then keep[#keep + 1] = v end end
    st.list = keep
end

-- ---------- the pawn, the map-load FindAllOf, distances (property reads only, D11) ----------
-- bus lab_pawn's rec ({ pawn, t }): the pawn as an object, a ue.keep record or a LAB.victim record
local function pawn_of(x)
    if type(x) == 'table' and rawget(x, '__mock') == nil and x.pawn ~= nil then return obj_of(x.pawn) end
    return obj_of(x)
end
function P.pawn()
    if st.pawn_in ~= nil then
        local o = pawn_of(st.pawn_in)
        st.pawn_in = nil
        if o then st.pawn, st.pawn_class = ue.keep(o), class_of(o) end
    end
    local p = st.pawn and ue.live(st.pawn)
    st.pawn_loc = p and ue.root_loc(p) or nil
end
-- Once per map load, FIND_AFTER_S after it and once the pawn's location reads: BP_RenewalNPC_C within FIND_UU
function P.find(t)
    if st.find ~= 'wait' or t < (st.find_at or 0) or not st.pawn_loc then return end
    st.find = 'done'
    LAB.oneshot()
    local r, err = LAB.armed('lab.findall', function()
        local list, info = ue.find_all(M.RENEWAL_SHORT, M.FIND_CAP, 'lab_poll')
        return { list = list, info = info }
    end)
    local list = r and r.list
    if type(list) ~= 'table' then
        local e = tostring(err or (r and r.info) or 'unavailable')
        st.find, st.found = 'failed', { err = e }
        -- ue.find_all keeps a FindAllOf error as text: the ArrayNum stop rule reads it here (D9)
        if e:find(LAB.ARRAYNUM, 1, true) then LAB.stop('arraynum', 'lab.findall', e, nil, nil, 'pcall') end
        return
    end
    local near, far = 0, 0
    for _, o in ipairs(list) do
        local name = ue.name(o)
        if name and name:sub(1, 9) ~= 'Default__' then
            local d = dist(ue.root_loc(o), st.pawn_loc)
            if d and d <= M.FIND_UU then
                near = near + 1
                admit(o, 'findall', nil)
            else
                far = far + 1
            end
        end
    end
    local info = type(r.info) == 'table' and r.info or {}
    st.found = { n = info.n or #list, near = near, far = far, ms = info.ms }
end
-- DIST_PER_TICK entries per poll, round-robin, each after LAB.live: the distance to the pawn and the newest hook
-- snapshot time (hits lab_kill pushed without a lab_hit)
function P.refresh()
    local n = #st.list
    for _ = 1, math.min(M.DIST_PER_TICK, n) do
        st.cur = st.cur % n + 1
        local v = st.list[st.cur]
        if not v.out then
            local o, why = LAB.live(v.rec)
            if not o then
                leave(v, why or 'gone')
            else
                v.dist = dist(ue.root_loc(o), st.pawn_loc)
                note_hits(v)
            end
        end
    end
end

-- ---------- snapshot fields (lab_kill.lua pushes plain values by the hook_fire names) ----------
-- A text value, nil when it says nothing: nil, '', 'None' (an empty FName), 'unread' (section 3: never logged as text)
local function txt(v)
    local s = ue.str(v)
    if s == nil then return nil end
    s = s:match('^%s*(.-)%s*$')
    if s == '' or s:lower() == 'none' or s == 'unread' then return nil end
    return s
end
-- The struck bone: the fine HitBone only (Pre/PostTakeHit bone). HitBodyData.bone (body_bone) and HitBody.SocketName
-- (socket) are a two-region reading, spine_04 for the upper body and Root for pelvis and legs (spec fixes-0.2.2 D2):
-- coarse_of, a band for the part choice, never the struck bone
local function bone_of(s) return txt(s.bone) end
local function coarse_of(s) return txt(s.body_bone) or txt(s.socket) end
local function nonzero(d)
    if type(d) ~= 'table' then return false end
    for _, a in ipairs({ 'x', 'y', 'z', 'X', 'Y', 'Z' }) do
        local n = tonumber(d[a])
        if n and n ~= 0 then return true end
    end
    return false
end
local function swing_of(s) return nonzero(s.attack_dir) or nonzero(s.sweep_dir) end
-- A fresh {x, y, z} of a snapshot vector (lab_death's attack_dir and sweep_dir, section 3.3), nil when unread
local function vec(d)
    if type(d) ~= 'table' then return nil end
    local x, y, z = tonumber(d.x or d.X), tonumber(d.y or d.Y), tonumber(d.z or d.Z)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z }
end
-- A fresh {x, y, z} of a world point rounded to 0.1 cm (kill.hit_loc and kill.root, fixes-0.2.2 B3.4), nil when unread
local function loc1(d)
    local p = vec(d)
    if p == nil then return nil end
    for _, a in ipairs({ 'x', 'y', 'z' }) do p[a] = math.floor(p[a] * 10 + 0.5) / 10 end
    return p
end
local function hit_loc_of(s) return nonzero(s.hit_loc) and s.hit_loc or nil end
local function has_hit(s) return bone_of(s) ~= nil or coarse_of(s) ~= nil or swing_of(s) end
local function same_source(a, b) return txt(a.killer) == txt(b.killer) end
-- A notification that carried a killer source: a valid Instigator or DamageSource object (lab_kill's source_seen), a
-- killer or a source class, or a payload object lab_kill left unread (payload_skipped: a source may sit there)
local function carried(s)
    return s.source_seen == true or txt(s.killer) ~= nil or txt(s.source_class) ~= nil
        or (tonumber(s.payload_skipped) or 0) > 0
end
-- The first answer of fn on the blow, then on the death frame's other notifications from the same source (newest first)
local function pick(frame, blow, fn)
    local r = fn(blow)
    if r ~= nil then return r end
    for i = #frame, 1, -1 do
        local s = frame[i]
        if s ~= blow and same_source(s, blow) then
            r = fn(s)
            if r ~= nil then return r end
        end
    end
    return nil
end
local WORD_FIELDS = { 'cause', 'attack_type', 'final_attack_type' }
local function word(s, list)
    for _, f in ipairs(WORD_FIELDS) do
        local x = type(s[f]) == 'string' and s[f]:lower() or nil
        if x then for _, w in ipairs(list) do if x:find(w, 1, true) then return true end end end
    end
    return false
end
-- The DamageSource class words (blow_src 'damage_source', review SEAMS-7): whole tokens of the class name (split at
-- '_', digits and lower-upper steps), so 'MaxEndurance' is no axe. English weapon words of the game's class names
-- (BP_Weapon_JingYe_Sword_C, BP_Weapon_Hun_ChaosBlade_C, BP_Weapon_PengMeng_Axe_C, BP_Weapon_ChangHong_Spear_C,
-- BP_Weapon_FemaleDoll_Shield_C: BP_WeaponActor_C subclasses; BP_Weapon_YanYan_Dart_C, BP_Weapon_MiaoShouFeiDao_Bullet_C:
-- BP_PBZ_ProjectileBullet_C subclasses; docs/research/compare/work/K02/usmap/structs.tsv:21356, :29262, :22126, :24376,
-- :26608, :22092, :29092 [verified]); never a tag name, never pinyin (Dao is a saber and a Taoist). In order: the
-- first class with a word wins
M.SOURCE_WORDS = {
    { 'shot', { 'bullet', 'arrow', 'dart', 'projectile' } },
    { 'blast', { 'explosion', 'explode', 'bomb', 'grenade', 'blast' } },
    { 'blunt', { 'shield', 'hammer', 'mace', 'club', 'fist', 'punch', 'kick' } },
    { 'slash', { 'sword', 'blade', 'slash', 'saber', 'sabre', 'katana', 'axe', 'spear', 'knife', 'dagger', 'glaive',
        'scythe', 'sickle', 'cleaver', 'halberd' } },
}
local function tokens(s)
    local out = {}
    for part in s:gmatch('[^_%s%./:]+') do
        local p = part:gsub('%d+', ' ')
        p = p:gsub('(%l)(%u)', '%1 %2')
        p = p:gsub('(%u)(%u%l)', '%1 %2')
        for w in p:gmatch('%S+') do out[w:lower()] = true end
    end
    return out
end
-- The bullet system (research kill-flow KF19; spec M1a 4.0): PBZ melee strikes are SweepTrace "bullet" data assets
-- (PDA_SweepTraceDamageBulletData_Simple_Base) dealt through the bullet attack module, and session 20261030-1522 read
-- source_class PBZ_BulletAttackModule on 3 of 7 blade kills. So 'bullet' names a shot only on a projectile bullet class
-- (BP_Weapon_*_Bullet_C, PBZ_ProjectileBullet, PDA_ProjectileDamageBulletData...): a class with a SYSTEM token and no
-- projectile word is a melee strike ('melee': the source class does not tell slash from blunt), never a shot
M.BULLET_SYSTEM = { 'sweep', 'trace', 'module' }
M.PROJECTILE = { 'projectile', 'arrow', 'dart' }
local function any_of(tok, list)
    for _, w in ipairs(list) do if tok[w] then return true end end
    return false
end
local function source_blow(tok)
    local melee = tok.bullet == true and any_of(tok, M.BULLET_SYSTEM) and not any_of(tok, M.PROJECTILE)
    for _, e in ipairs(M.SOURCE_WORDS) do
        for _, w in ipairs(e[2]) do
            if tok[w] and not (melee and w == 'bullet') then return e[1] end
        end
    end
    return melee and 'melee' or nil
end
-- The blow class of one notification [inferred]: a measurement label, never a gore decision; the lab logs the raw names
-- next to it (hook_fire). how 'source': the DamageSource class words only ('damage_source'; 'melee' for the bullet
-- system's melee strike); else the game's cause and attack names ('tag') and the Sharp and Blunt amounts
-- ('attack_data'). -> class, blow_src ('unknown', 'none' on none)
function P.blow_of(s, how)
    if how == 'source' then
        local cls = txt(s.source_class)
        local b = cls and source_blow(tokens(cls)) or nil
        if b then return b, 'damage_source' end
        return 'unknown', 'none'
    end
    if word(s, { 'bleed', 'bloodburst' }) then return 'bleed', 'tag' end
    if word(s, { 'explo', 'blast' }) then return 'blast', 'tag' end
    if word(s, { 'projectile', 'bullet', 'arrow', 'shot' }) then return 'shot', 'tag' end
    local sh, bl = tonumber(s.sharp) or 0, tonumber(s.blunt) or 0
    if sh > 0 or bl > 0 then return sh >= bl and 'slash' or 'blunt', 'attack_data' end
    if word(s, { 'blunt', 'smash' }) then return 'blunt', 'tag' end
    if word(s, { 'slash', 'sharp', 'blade', 'cut' }) then return 'slash', 'tag' end
    return 'unknown', 'none'
end
-- The blow class of the death frame: the game's names first (the blow, then the frame's same-source notifications),
-- then the DamageSource class words the same way. -> class, blow_src
local function blow_class(frame, blow)
    for _, how in ipairs({ 'names', 'source' }) do
        local r = pick(frame, blow, function(s)
            local b, w = P.blow_of(s, how)
            if b ~= 'unknown' then return { b, w } end
            return nil
        end)
        if r then return r[1], r[2] end
    end
    return 'unknown', 'none'
end

-- ---------- the kill record (section 3.1, C11) ----------
-- From this life's snapshots: the window is KILL_S before the poll. The blow is the window's newest notification with
-- hit data (a fine or coarse bone, or a swing), else its newest one; the death frame runs from JOIN_S before the blow
-- to the poll, so a later notification without hit data (a tag added, a group member dead, a ragdoll notify) joins the
-- frame instead of pushing the blow out of it (review SEAMS-7). The struck bone is a fine HitBone only (bone_of; spec
-- fixes-0.2.2 D2): bone_src 'blow' when the blow names one, 'joined' when another notification of the frame from the
-- same source does (a Pre or PostTakeHit before a newer socket-only Damage.Taken); else the frame's coarse reading
-- (coarse_of: HitBodyData.bone or HitBody.SocketName, the same pick) goes to the field coarse, never to bone, with
-- bone_src 'coarse'; nothing at all is 'fallback'. No bone: never a head shot; headshot only with 'blow'. A poll kill
-- is 'fallback'. hit_loc the same pick over non-zero HitLocations (B3.4, rounded to 0.1 cm; absent on a poll kill).
-- blow and blow_src from blow_class. The killer is the blow's, else the frame's newest that names one;
-- killer_src and by_player come with it (lab_kill compares addresses), by_player else from the class names; a poll
-- kill has no killer (killer_src 'none'). Without a killer, a frame none of whose notifications carried a source
-- (carried: an environment death such as a fall, checks:b, d) has killer_src 'no_source'; one that carried a source
-- no snapshot resolved keeps 'none'. src is the frame's first hook id ('poll' when no hook fired), and its time is the
-- latency base. Returns the record and that time (nil without a hook).
function P.build_kill(v, t)
    local rec = v.rec
    local gid = type(LAB.game_id) == 'function' and LAB.game_id(rec.class) or nil
    local k = { id = rec.id, skip = 'dev', why = 'probe', life = rec.life, dup = false, class = rec.class,
        pair = (LAB.pair_of(rec.class)), family = gid ~= nil and tostring(gid) or 'unread', joined = 0, swing = false,
        execution = false, die_reason = 'unread', damage_tags = 'unread', by_player = 'unread', blow = 'unknown',
        blow_src = 'none', killer_src = 'none', spawned = rec.spawned == true or nil }
    local win = {}
    for _, s in ipairs(LAB.snaps(v.key, v.life_t0)) do
        if s.key == 'h12' or s.key == 'h24' or s.execution == true then k.execution = true end
        if (s.t or 0) >= t - M.KILL_S then win[#win + 1] = s end
    end
    if not win[1] then
        k.src, k.bone_src, k.ev_id = 'poll', 'fallback', 'poll@' .. math.floor(t * 1000)
        if LAB.beta() then P.tier(k, nil, nil) end
        return k, nil
    end
    local blow = win[#win]
    for i = #win, 1, -1 do if has_hit(win[i]) then blow = win[i] break end end
    local from, frame = (blow.t or t) - M.JOIN_S, {}
    for _, s in ipairs(win) do if (s.t or 0) >= from then frame[#frame + 1] = s end end
    k.src, k.joined = txt(frame[1].key) or 'unread', #frame - 1
    k.ev_id = txt(blow.ev_id) or ((txt(blow.key) or 'hook') .. '@' .. math.floor((blow.t or t) * 1000))
    local bone = bone_of(blow)
    if bone then
        k.bone, k.bone_src, k.headshot = bone, 'blow', bone:lower():find('head', 1, true) ~= nil
    else
        bone = pick(frame, blow, bone_of)
        if bone then
            k.bone, k.bone_src = bone, 'joined'
        else
            k.coarse = pick(frame, blow, coarse_of)
            k.bone_src = k.coarse and 'coarse' or 'fallback'
        end
    end
    k.swing = pick(frame, blow, function(s) return swing_of(s) or nil end) == true
    k.hit_loc = loc1(pick(frame, blow, hit_loc_of))           -- B3.4 (D4): logged, never a part choice
    k.blow, k.blow_src = blow_class(frame, blow)
    local ks = txt(blow.killer) and blow or nil
    for i = #frame, 1, -1 do
        local s = frame[i]
        if ks == nil and txt(s.killer) then ks = s end
        if k.die_reason == 'unread' and txt(s.die_reason) then k.die_reason = txt(s.die_reason) end
    end
    if ks then
        k.killer, k.killer_src = txt(ks.killer), txt(ks.killer_src) or 'unread'
        if type(ks.by_player) == 'boolean' then k.by_player = ks.by_player
        elseif st.pawn_class then k.by_player = k.killer == st.pawn_class end
    else
        local any = false
        for _, s in ipairs(frame) do any = any or carried(s) end
        if not any then k.killer_src = 'no_source' end
    end
    -- damage_tags: each snapshot's DamageTags list, plus the DamageCause tag lab_kill pushes as snap.cause, once each
    local seen_tag = {}
    local function add_tag(x)
        x = txt(x)
        if not x or seen_tag[x] then return end
        if k.damage_tags == 'unread' then k.damage_tags = {} end
        seen_tag[x] = true
        k.damage_tags[#k.damage_tags + 1] = x
    end
    for _, s in ipairs(win) do
        if k.die_reason == 'unread' and txt(s.die_reason) then k.die_reason = txt(s.die_reason) end
        if type(s.damage_tags) == 'table' then
            for _, x in ipairs(s.damage_tags) do add_tag(tostring(x)) end
        end
        add_tag(s.cause)
    end
    if LAB.beta() then P.tier(k, frame, blow) end
    return k, frame[1].t, blow
end

-- ---------- the beta's kill tier (BD3, research H3; the contract: lab_census.lua's header) ----------
-- A status hit: a StatusInfliction cause (Damage.Cause.StatusInfliction.Bleed, .BloodBurst), a GameplayEffect source
-- (DamageSource_GameplayEffect) or an Energy attack type (Hitreact.AttackType.Energy: the bleed tick's hit react)
function P.status_hit(s)
    local c, src = txt(s.cause), txt(s.source_class)
    if (c and c:find('StatusInfliction', 1, true)) or (src and src:find('GameplayEffect', 1, true)) then return true end
    for _, f in ipairs({ 'attack_type', 'final_attack_type' }) do
        local x = txt(s[f])
        if x and x:find('Energy', 1, true) then return true end
    end
    return false
end
-- A notification that carries a hit: a cause, a source class, an attack type or a bullet (an Actor.Killed or a hook
-- fire without payload fields carries none)
local function is_hit(s)
    return (txt(s.cause) or txt(s.source_class) or txt(s.attack_type) or txt(s.final_attack_type)
        or txt(s.bullet)) ~= nil
end
-- The combo token of a player bullet (the dump's names under /Players/Hun/BulletData/): the A, B and C letters after
-- the weapon as a whole word, B_Hun_Tang_AAB_02 -> AAB, BD_Hun_HeiMoShang_C_01_New -> C,
-- BulletData_Hun_ShachiHook_CC_01 -> CC; nil for any other name (B_Hun_Iron_BChargeAttack_Lv1, B_Hun_Long_CounterA_01,
-- an NPC bullet)
M.BULLET_PREFIX = { B = true, BD = true, BulletData = true }
function P.combo(name)
    if type(name) ~= 'string' then return nil end
    local pre, tok = name:match('^(%a+)_Hun_%a+_([ABC]+)_')
    if not pre then pre, tok = name:match('^(%a+)_Hun_%a+_([ABC]+)$') end
    if pre and M.BULLET_PREFIX[pre] then return tok end
    return nil
end
-- The combo class of a bullet name for the tallies: 'C' (a C chain), 'B' (ends in B), 'A', 'other' (no token), 'none'
local function combo_class(name)
    if txt(name) == nil then return 'none' end
    local tok = P.combo(name)
    if tok == nil then return 'other' end
    if tok:find('C', 1, true) then return 'C' end
    return tok:sub(-1) == 'B' and 'B' or 'A'
end
local function skill(s)                     -- the SkillType's last part: NormalAttack, PowerAttack, Skill, Ultimate
    local x = txt(s.skill_type)
    return x and x:match('([^.]+)$') or nil
end
local function names_word(s, w)             -- the attack type or final attack type names w (lower case)
    for _, f in ipairs({ 'attack_type', 'final_attack_type' }) do
        local x = txt(s[f])
        if x and x:lower():find(w, 1, true) then return true end
    end
    return false
end
M.HEAVY_STRENGTH = { 'heavy', 'launchback', 'knockdown' }
local STRENGTHS = { 'hit_strength', 'origin_strength', 'anim_strength', 'hit_state' }
-- The tier rules in order, each { tier, tier_src, test(s, nb) } over one player hit (nb: a hit of the frame read a
-- bullet): the first rule any hit matches wins, so a higher tier always beats a lower one.
-- * shaqi: SkillType Skill or Ultimate; a ShachiWeapon or ShachiAbility bullet folder; a C-chain bullet (a main-weapon
--   Power Surge such as GA_Hun_ZhanMa_C_C, the author's answer 2; the Sha-Qi hook's C chains match the folder first);
--   'Shachi' in the attack type (the Hook's Slash.ShachiHook, read with no bullet).
-- * heavy: SkillType PowerAttack; a bullet with no SkillType whose combo token ends in B or whose name holds Charge
--   (A means light, B heavy: outlaw-warblade.md:13); with no bullet in the frame, a Heavy, Launchback or Knockdown
--   strength tag (Hitreact.Strength.Income.*.Heavy, Launchback.*, Knockdown, Internal.Dead.Launchback).
local RULES = {
    { 'shaqi', 'skill', function(s) local k = skill(s) return k == 'Skill' or k == 'Ultimate' end },
    { 'shaqi', 'path', function(s)
        local d = txt(s.bullet_dir)
        return d ~= nil and ((d .. '/'):find('/ShachiWeapon/', 1, true) or (d .. '/'):find('/ShachiAbility/', 1, true))
            ~= nil
    end },
    { 'shaqi', 'surge', function(s)
        local tok = P.combo(txt(s.bullet))
        return tok ~= nil and tok:find('C', 1, true) ~= nil
    end },
    { 'shaqi', 'attack_type', function(s) return names_word(s, 'shachi') end },
    { 'heavy', 'skill', function(s) return skill(s) == 'PowerAttack' end },
    { 'heavy', 'name', function(s)
        local b = txt(s.bullet)
        if b == nil or skill(s) ~= nil then return false end
        local tok = P.combo(b)
        return (tok ~= nil and tok:sub(-1) == 'B') or b:find('Charge', 1, true) ~= nil
    end },
    { 'heavy', 'strength', function(s, nb)
        if nb then return false end
        for _, f in ipairs(STRENGTHS) do
            local x = txt(s[f])
            if x then
                x = x:lower()
                for _, w in ipairs(M.HEAVY_STRENGTH) do if x:find(w, 1, true) then return true end end
            end
        end
        return false
    end },
}
-- The attack kind of one hit (answer 3), each nil for a status hit: deflect, true when its cause, attack types or
-- bullet name Deflect (the counter's Damage.Cause.Deflect.Normal rides on the Damage.Taken of a Kick.Player hit, the
-- bow's B_UnnamedBow_DeflectCounter_* bullets); kind_tag, 'kick' when its attack type (else its final attack type)
-- names Kick, 'weapon' for any other attack type; kind_bullet, the same from the bullet name when no tag named it
-- (B_Hun_PerfectDodge_JumpKick_01)
local function deflect(s)
    if P.status_hit(s) then return nil end
    for _, f in ipairs({ 'cause', 'attack_type', 'final_attack_type', 'bullet' }) do
        local x = txt(s[f])
        if x and x:find('Deflect', 1, true) then return true end
    end
    return nil
end
local function kind_tag(s)
    local at = not P.status_hit(s) and (txt(s.attack_type) or txt(s.final_attack_type)) or nil
    if at == nil then return nil end
    return at:find('Kick', 1, true) and 'kick' or 'weapon'
end
local function kind_bullet(s)
    local b = not P.status_hit(s) and txt(s.bullet) or nil
    if b == nil then return nil end
    return b:find('Kick', 1, true) and 'kick' or 'weapon'
end
-- The parts a tier asks for, live through the knobs (core/config.lua C.knob): normal 1, heavy heavy_parts, shaqi
-- shaqi_parts, both capped by max_parts. lab_cut's n is this, cut further to the parts the rig has
function M.tier_parts(tier)
    local knob = M.TIER_KNOB[tier]
    if knob == nil then return 1 end
    return math.min(C.knob(knob) or 1, C.knob('max_parts') or 1)
end
-- The kill tier fields on k (the beta's kill record and its lab_death payload; frame nil: a poll kill, every field
-- normal, none or 'unread'). The hits: the frame's notifications that carry one; status hits never set the tier, and
-- a frame whose hits are all status hits is bleed_only (true never cuts, answer 4; false with another hit; 'unread'
-- with no hit read). attack_kind over the blow, then the frame's same-source notifications (newest first): 'deflect'
-- when one names Deflect, else kind_tag's first answer, else kind_bullet's, else 'status' when bleed_only, else
-- 'unread' (a kick or a deflect never cuts, answer 3). The tier: normal unless by_player is true (answer 5: another's
-- kill cuts one part); else the first RULES entry any of the player's hits (by_player not false) matches. skill_type,
-- strength (Pre HitStrength), anim_strength, origin_strength, attack_type and bullet: the first value among the hit
-- that set the tier, the blow, then the hits newest first. frame_bullets: the frame's distinct bullet names
-- (FRAME_BULLETS). tier_parts: M.tier_parts(tier)
function P.tier(k, frame, blow)
    k.tier, k.tier_src, k.tier_parts, k.attack_kind, k.bleed_only = 'normal', 'none', 1, 'unread', 'unread'
    k.skill_type, k.strength, k.anim_strength, k.origin_strength, k.attack_type, k.bullet, k.frame_bullets =
        'unread', 'unread', 'unread', 'unread', 'unread', 'unread', 'unread'
    if frame == nil then return end
    local hits, status, bullets, seen = {}, 0, {}, {}
    for i = #frame, 1, -1 do
        local s = frame[i]
        local b = txt(s.bullet)
        if b and not seen[b] and #bullets < M.FRAME_BULLETS then
            seen[b], bullets[#bullets + 1] = true, b
        end
        if is_hit(s) then
            if P.status_hit(s) then status = status + 1 else hits[#hits + 1] = s end
        end
    end
    if bullets[1] then k.frame_bullets = bullets end
    if hits[1] then k.bleed_only = false elseif status > 0 then k.bleed_only = true end
    k.attack_kind = (pick(frame, blow, deflect) and 'deflect') or pick(frame, blow, kind_tag)
        or pick(frame, blow, kind_bullet) or (k.bleed_only == true and 'status') or 'unread'
    local mine, nb = {}, false
    if k.by_player == true then
        for _, s in ipairs(hits) do
            if s.by_player ~= false then
                mine[#mine + 1] = s
                nb = nb or txt(s.bullet) ~= nil
            end
        end
    end
    local top = nil
    for _, r in ipairs(RULES) do
        for _, s in ipairs(mine) do
            if r[3](s, nb) then
                top, k.tier, k.tier_src = s, r[1], r[2]
                break
            end
        end
        if top then break end
    end
    k.tier_parts = M.tier_parts(k.tier)
    local order = { top }
    if blow ~= nil and blow ~= top and is_hit(blow) and not P.status_hit(blow) then order[#order + 1] = blow end
    for _, s in ipairs(hits) do if s ~= top and s ~= blow then order[#order + 1] = s end end
    local function first(f)
        for _, s in ipairs(order) do
            local x = txt(s[f])
            if x then return x end
        end
        return nil
    end
    k.skill_type, k.strength = first('skill_type') or 'unread', first('hit_strength') or 'unread'
    k.anim_strength, k.origin_strength = first('anim_strength') or 'unread', first('origin_strength') or 'unread'
    k.attack_type = first('attack_type') or first('final_attack_type') or 'unread'
    k.bullet = first('bullet') or 'unread'
    k.bd_dir = first('bd_dir')                      -- the bullet's AttackDirection tag (lab_cut_beta plane_of; D2)
    -- a player finisher or stealth kill: its bullet names an Execution (SimpleExecution_Single, _Multi3,
    -- TieKuangQuanTao_Execution in the lab logs) while no h12/h24 execution hook fired, so it reads as an execution
    -- too (execution_src 'bullet'; lab_plan: no cut unless finisher_cuts)
    if k.by_player == true and k.execution ~= true and k.bullet:find('Execution', 1, true) then
        k.execution, k.execution_src = true, 'bullet'
    end
end
-- One beta kill into the session's tier tallies (P.confirm); the status-only and no-bullet frames also count in
-- status.counters (kill_status_only, kill_no_bullet)
function P.tally_tier(k)
    local x = st.tiers
    x.kills = x.kills + 1
    x.tiers[k.tier] = (x.tiers[k.tier] or 0) + 1
    x.srcs[k.tier_src] = (x.srcs[k.tier_src] or 0) + 1
    x.kinds[k.attack_kind] = (x.kinds[k.attack_kind] or 0) + 1
    if k.src == 'poll' then x.poll = x.poll + 1 end
    if k.by_player == false then x.not_player = x.not_player + 1 end
    if k.bleed_only == true then
        x.status_only = x.status_only + 1
        LAB.count('kill_status_only')
    elseif k.bleed_only == false and k.frame_bullets == 'unread' then
        x.no_bullet = x.no_bullet + 1
        LAB.count('kill_no_bullet')
    end
    local row = { tier = k.tier, by_player = k.by_player, skill_type = k.skill_type, combo = combo_class(k.bullet),
        origin_strength = k.origin_strength, attack_type = k.attack_type }
    local key = table.concat({ row.tier, tostring(row.by_player), row.skill_type, row.combo, row.origin_strength,
        row.attack_type }, '|')
    local r = x.rows[key]
    if r then
        r.n = r.n + 1
    elseif #x.list < M.TIER_ROWS then
        row.n = 1
        x.rows[key], x.list[#x.list + 1] = row, row
    else
        x.more = x.more + 1
    end
end
-- One tier_tally record (lab_flush, the beta): the session's counts, rows most kills first (first seen on a tie)
function P.tier_tally(reason)
    local x = st.tiers
    local rows = {}
    for i, r in ipairs(x.list) do rows[i] = r end
    local at = {}
    for i, r in ipairs(rows) do at[r] = i end
    table.sort(rows, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return at[a] < at[b]
    end)
    LAB.rec('tier_tally', { reason = reason, kills = x.kills, poll = x.poll, not_player = x.not_player,
        status_only = x.status_only, no_bullet = x.no_bullet, tiers = x.tiers, srcs = x.srcs, kinds = x.kinds,
        rows = rows, rows_more = x.more })
end

-- ---------- per death: PhysicsHits keys and the death delegates' bindings (new types here: always-armed per read) ----------
local function comp(o, bp_field, field) return ue.prop(o, bp_field) or ue.prop(o, field) end
-- HitreactComponent.PhysicsHits (props:16502, a TMap) keys as text, capped PHYS_CAP; 'unread' when the read failed
function P.phys_hits(o)
    local r = LAB.armed('lab.read.tmap', function(obj)
        local map = ue.prop(comp(obj, 'Hitreact Component', 'HitreactComponent'), 'PhysicsHits')
        if map == nil then return nil end
        local out = {}
        map:ForEach(function(key)
            if #out >= M.PHYS_CAP then return true end
            local kv = ue.p(key)
            local s = txt(kv) or txt(ue.name(kv))
            if s then out[#out + 1] = s end
            return nil
        end)
        return out
    end, o)
    return type(r) == 'table' and r or 'unread'
end
-- A multicast delegate's GetBindings ({ Object, FunctionName } list, or nil when none) as 'Class:Function' texts
local function bind_list(d)
    if d == nil then return nil end
    local b = d:GetBindings()
    local out = {}
    if type(b) ~= 'table' then return out end
    for i = 1, math.min(#b, M.BIND_CAP) do
        local x = b[i]
        out[#out + 1] = (class_of(x.Object) or 'unread') .. ':' .. (txt(x.FunctionName) or 'unread')
    end
    return out
end
function P.bindings(o)
    local function read(src, field)
        local r = LAB.armed('lab.read.multicast', function() return bind_list(ue.prop(src, field)) end)
        return type(r) == 'table' and r or 'unread'
    end
    return { on_death = read(comp(o, 'Attribute Component', 'AttributeComponent'), 'OnDeath'),
        on_character_die = read(o, 'OnCharacterDie') }
end

-- ---------- the poll: Health and tags on property chains (no UFunction, no per-read sentinel, D11) ----------
local function tally(class)
    local x = st.tally[class]
    if not x then
        x = { members = 0, killed = 0 }
        st.tally[class] = x
    end
    return x
end
local function dead_tag(tags)
    local pre = M.DEAD_TAG .. '.'
    for _, s in ipairs(tags) do if s == M.DEAD_TAG or s:sub(1, #pre) == pre then return true end end
    return false
end
-- A confirmed death: one kill record for this life, death_poll, the counter, bus lab_death; then the next life
function P.confirm(v, o, t, route, agreed)
    local rec = v.rec
    local k, first_t, blow = P.build_kill(v, t)
    k.root = loc1(ue.root_loc(o))           -- B3.4: where the victim stands, before any kill record is written
    local beta = LAB.beta()
    if not beta then                                -- the beta reads neither: two armed native reads per death (S5)
        k.phys_hits = P.phys_hits(o)
        if not st.bound[k.pair] then
            st.bound[k.pair] = true
            k.bindings = P.bindings(o)
        end
    end
    local src, death_t = P.death_src(v, t)
    if beta then                                    -- the beta holds nothing: a limb cut sends no outcome (S5)
        k.death_src = src
        P.tally_tier(k)                             -- BD3: the session's tier tallies
        LAB.rec('kill', k)
    else
        if LAB.cut_set() then P.hold(k, first_t, death_t, src) else LAB.rec('kill', k) end   -- D5; M0 at confirm
    end
    local dp = { id = k.id, route = route, agreed = agreed == true }
    if first_t then dp.lat_ms = math.floor((t - first_t) * 1000 + 0.5) end   -- absent (null) when no hook fired
    LAB.rec('death_poll', dp)
    LAB.count('poll_deaths')
    st.deaths = st.deaths + 1
    local x = tally(v.class)
    x.killed = x.killed + 1
    LAB.next_life(rec)
    v.alive, v.life_t0, v.hit_t = false, t, nil
    v.dead_life, v.alive_n = k.life, 0
    BUS.emit('lab_death', { key = rec.key, keep = rec.keep, obj = rec.keep, victim = rec, id = k.id, class = rec.class,
        pair = k.pair, life = k.life, t = t, kill = k, attack_dir = vec(blow and blow.attack_dir),
        sweep_dir = vec(blow and blow.sweep_dir), death_src = src, death_t = death_t, corpse_life = k.life })
end
-- D6: 'hook:<id>' and that hook's first fire of the life when data/lab_pairs.lua names a death_source hook that fired
-- (its snapshot since the life began), else 'poll' and the confirm time. Before the life steps
function P.death_src(v, t)
    local ds = st.ds
    if ds ~= nil then
        for _, s in ipairs(LAB.snaps(v.key, v.life_t0)) do
            if s.key == ds then return 'hook:' .. ds, s.t or t end
        end
    end
    return 'poll', t
end
-- D27, section 3.3: a victim with a confirmed death that reads alive on REVIVE_READS reads in a row (a dead read
-- resets the run) emits bus lab_revive(rec, life) once per confirmed death: the registry record (its life already the
-- next one) and the life that ended. Bus only, no record (spec M1a rule 9); lab_cut puts the cut back. Only a read
-- with Health above 0 counts (kill-and-cut.md 'Revive': the dead flag gone with HP > 0): a corpse whose Health no
-- longer reads (AttributeSetBase gone) with a tag list lacking CharacterState.Dead (B4: no Dead tag at 9 of 9
-- confirms) is not alive, and that read breaks the run
function P.revive(v, hp)
    if v.dead_life == nil then return end
    if not (hp ~= nil and hp > 0) then
        v.alive_n = 0
        return
    end
    v.alive_n = (v.alive_n or 0) + 1
    if v.alive_n < M.REVIVE_READS then return end
    local life = v.dead_life
    v.dead_life, v.alive_n = nil, 0
    st.revives = st.revives + 1
    BUS.emit('lab_revive', v.rec, life)
end

-- ---------- the held kill record (lab02 set, D5, D6): one per life, written once after its outcome ----------
-- Outcome words: C11's (committed, fx_only, ink, excluded, refused) plus the lab word lab_skip. counted is false for
-- these outcomes and for the refusals that are no failure; true otherwise (committed, and a refusal naming a failure:
-- no_outcome, cap_attach, no_cap, commit_fail:<step> ...). lab_poll owns this rule
M.UNCOUNTED = { lab_skip = true, fx_only = true, ink = true, excluded = true }
M.NOT_FAILURE = { gone = true, not_dead = true, already_cut = true, dup_kill = true, stale = true, modoff = true,
    lab_end = true }
function M.counted(outcome, why)
    if M.UNCOUNTED[outcome] then return false end
    return not (outcome == 'refused' and M.NOT_FAILURE[why] == true)
end
local function r1(ms) return math.floor(ms * 10 + 0.5) / 10 end
-- Hold k (st.pending[id]) with death_src, on the game clock; after lab_end it is written at once (refused, lab_end)
function P.hold(k, first_t, death_t, src)
    k.death_src = src
    st.seq = st.seq + 1
    st.pending[k.id] = { k = k, first_t = first_t, death_t = death_t, gt = S.game_time, n = st.seq }
    st.npending = st.npending + 1
    if st.ended then P.finish(k.id, { outcome = 'refused', why = 'lab_end' }) end
end
-- Write the held record of id once, forced, with f = { row, outcome, why, commit_ms, actions, cut_ms, at }: row from
-- the outcome, else lab_plan's lab_row; why replaces M0's 'probe' (absent when the outcome names none); actions 0
-- unless given; commit_ms from the outcome, else (committed) its arrival since the death source event; total_ms =
-- commit_ms plus the death source event's lag behind the death frame's first hook snapshot (absent with no hook). An id
-- not held (written already, or never held) is a late outcome: counted in status().late and ignored
function P.finish(id, f)
    local h = st.pending[id]
    if h == nil then
        st.late = st.late + 1
        return false
    end
    st.pending[id], st.npending = nil, st.npending - 1
    local k = h.k
    k.row = type(f.row) == 'string' and f.row or h.row
    k.outcome = type(f.outcome) == 'string' and f.outcome or 'refused'
    k.why = type(f.why) == 'string' and f.why or nil
    k.counted = M.counted(k.outcome, k.why)
    k.actions = tonumber(f.actions) or 0
    k.cut_ms = tonumber(f.cut_ms)
    local cm = tonumber(f.commit_ms)
    if cm == nil and k.outcome == 'committed' and type(f.at) == 'number' then cm = (f.at - h.death_t) * 1000 end
    if cm ~= nil then
        k.commit_ms = r1(cm)
        if h.first_t ~= nil then k.total_ms = r1(cm + (h.death_t - h.first_t) * 1000) end
    end
    LAB.rec('kill', k, true)
    st.written = st.written + 1
    return true
end
-- Every held record at once, in hold order: outcome refused, why ('lab_end' at lab_end, 'stale' at a map load)
local function in_order(only)
    local list = {}
    for id, h in pairs(st.pending) do if only == nil or only(h) then list[#list + 1] = { id = id, n = h.n } end end
    table.sort(list, function(a, b) return a.n < b.n end)
    return list
end
function P.flush(why)
    for _, e in ipairs(in_order()) do P.finish(e.id, { outcome = 'refused', why = why }) end
end
-- The queued lab_row rows and lab_outcome fields, in arrival order (memory only)
function P.apply()
    if st.rowq[1] then
        local q = st.rowq
        st.rowq = {}
        for _, r in ipairs(q) do
            local h = st.pending[r.id]
            if h then h.row = r.row end
        end
    end
    if st.outq[1] then
        local q = st.outq
        st.outq = {}
        for _, o in ipairs(q) do P.finish(o.id, o.f) end
    end
end
-- Every frame, paused too (memory only): rows and outcomes, the lab_end flush, then the OUTCOME_S deadline on the game
-- clock (S.game_time stands still while paused): refused, why 'no_outcome' (a failure)
function P.outcomes()
    P.apply()
    if st.end_due then
        st.end_due, st.ended = false, true
        P.flush('lab_end')
    end
    if st.npending == 0 then return end
    local gt = S.game_time
    for _, e in ipairs(in_order(function(h) return gt - h.gt >= M.OUTCOME_S end)) do
        P.finish(e.id, { outcome = 'refused', why = 'no_outcome' })
    end
end
function M.pending(id)                       -- spec 3.9 'LAB.pending(id) for tests': the held kill record, or nil
    local h = st.pending[id]
    return h and h.k or nil
end
-- Bus listeners (they only queue): lab_outcome(id, fields) copies the plain fields and its arrival time
local function on_outcome(id, f)
    if id == nil then return end
    if #st.outq >= M.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    f = type(f) == 'table' and f or {}
    st.outq[#st.outq + 1] = { id = id, f = { row = f.row, outcome = f.outcome, why = f.why, commit_ms = f.commit_ms,
        actions = f.actions, cut_ms = f.cut_ms, at = now() } }
end
local function on_row(row, d)                -- lab_row(row, d): d the lab_death payload
    if type(d) ~= 'table' or d.id == nil then return end
    if #st.rowq >= M.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    st.rowq[#st.rowq + 1] = { id = d.id, row = row }
end
function P.read(v, t)
    v.rt = t                                              -- read this tick (P.poll skips it then)
    local o, why = LAB.live(v.rec)
    if not o then return leave(v, why or 'gone') end
    if not v.member then
        v.member = true
        local x = tally(v.class)
        x.members = x.members + 1
    end
    st.reads = st.reads + 1
    local hp, tags = ue.health(o), ue.tags(o)
    if hp == nil and tags == nil then
        st.read_fail = st.read_fail + 1
        return
    end
    local by_hp, by_tag = hp ~= nil and hp <= 0, tags ~= nil and dead_tag(tags)
    if not (by_hp or by_tag) then
        v.alive = true
        P.revive(v, hp)
        return
    end
    v.alive_n = 0
    if v.alive == nil then note_hits(v) end                -- a hit pushed since the last refresh counts
    if v.alive == true or (v.alive == nil and v.hit_t ~= nil and t - v.hit_t <= M.KILL_S) then
        P.confirm(v, o, t, by_hp and 'health' or 'tags', by_hp and by_tag)
    else
        v.alive = false                       -- a corpse first seen dead, or a later read of a death already logged
    end
end
-- Victims hit in the last HIT_S or within NEAR_UU, at most READS_PER_TICK per poll (round-robin)
function P.poll(t)
    local n, reads, cands = #st.list, 0, 0
    local start = n > 0 and st.rr % n or 0
    for i = 1, n do
        local v = st.list[(start + i - 1) % n + 1]
        if not v.out and v.rt ~= t
            and ((v.hit_t ~= nil and t - v.hit_t <= M.HIT_S) or (v.dist ~= nil and v.dist <= M.NEAR_UU)) then
            cands = cands + 1
            if reads < M.READS_PER_TICK then
                reads = reads + 1
                P.read(v, t)
            end
        end
    end
    st.rr, st.candidates = start + math.max(reads, 1), cands
end
-- ---------- the death source's next-tick read (D6, lab02 set only: TC-LAB-01 measures the poll's own latency) ----------
-- A lab_hit naming the death_source hook, or one whose victim has a newer snapshot of that hook this life (lab_kill
-- emits one lab_hit per victim and tick, keyed by its newest fire), queues the victim for a read on the next tick
function P.mark(v, key, t)
    if v.fast then return end
    local last = key == st.ds and t or nil
    for _, s in ipairs(LAB.snaps(v.key, v.life_t0)) do
        if s.key == st.ds and s.t ~= nil and (last == nil or s.t > last) then last = s.t end
    end
    if last == nil or last <= (v.ds_t or -math.huge) then return end
    v.ds_t, v.fast = last, true
    st.fastq[#st.fastq + 1] = v
end
-- The queued admissions, then one read of each victim the death source marked
function P.fast(t)
    st.urgent = false
    drain()
    if not st.fastq[1] then return end
    local q = st.fastq
    st.fastq = {}
    for _, v in ipairs(q) do
        v.fast = nil
        if not v.out then
            st.fast_reads = st.fast_reads + 1
            P.read(v, t)
        end
    end
end

-- ---------- fodder (section 3.1): one record per pair label on each lab_flush, from the session tallies ----------
-- members: victims the poll read at least once (met: hit or within NEAR_UU), alive or dead; killed: confirmed kills.
-- The label comes from LAB.pair_of per class now (a game id RC supplied later changes pair_by, never the label);
-- game_ids from LAB.game_id when lab_probe offers it
function P.fodder(reason)
    local by = {}
    for _, label in ipairs(M.LABELS) do
        by[label] = { pair = label, pair_by = 'class', reason = reason, members = 0, killed = 0, game_ids = {} }
    end
    local classes, gids = {}, {}
    for cls in pairs(st.tally) do classes[#classes + 1] = cls end
    table.sort(classes)
    for _, cls in ipairs(classes) do
        local x = st.tally[cls]
        local label, via = LAB.pair_of(cls)
        local r = by[label] or by.other
        r.members, r.killed = r.members + x.members, r.killed + x.killed
        if via == 'game_id' then r.pair_by = 'game_id' end
        local gid = type(LAB.game_id) == 'function' and LAB.game_id(cls) or nil
        local g = gid ~= nil and tostring(gid) or nil
        if g and not gids[r.pair .. '|' .. g] then
            gids[r.pair .. '|' .. g] = true
            r.game_ids[#r.game_ids + 1] = g
        end
    end
    for _, label in ipairs(M.LABELS) do
        table.sort(by[label].game_ids)
        LAB.rec('fodder', by[label])
    end
end

-- ---------- the class watch: the callback runs during construction, keeps a ue.keep record and returns ----------
local function watch()
    token = token + 1
    local mine = token
    local ok, err = ue.watch_class(M.RENEWAL, function(o)
        if mine ~= token then return true end                       -- an older init's watch unregisters itself
        pcall(function()
            local kp = ue.keep(o)
            if kp and type(kp.name) == 'string' and kp.name:sub(1, 9) ~= 'Default__' then queue(kp, 'watch', nil) end
        end)
        return nil
    end)
    st.watch, st.watch_err = ok == true, (not ok) and tostring(err) or nil
end

-- ---------- the lab ticker: every POLL_S while the game runs ----------
-- Every frame: the held records' outcomes and deadline (lab02), the death source's reads (lab02, unpaused); the rest
-- every POLL_S
local function tick()
    if not st.watched then st.watched = true watch() end   -- first lab tick: the game thread (not main.lua's body)
    P.outcomes()
    if not LAB.due('lab_poll', M.POLL_S) then
        if st.urgent and not LAB.paused() then P.fast(now()) end
        return
    end
    local t = now()
    P.pawn()
    P.find(t)
    P.fast(t)
    P.refresh()
    P.poll(t)
    compact()
end

-- ---------- lifecycle ----------
-- A: the main.lua feature view (clock; LAB holds count, gauge and oneshot)
function M.init(adapter)
    A = adapter
    st = new_state()
    st.init = true
    LAB.names(N, F)
    -- D6: the death source hook id (data/lab_pairs.lua, A5.3; nil keeps the poll); its next-tick read in lab02 only
    local okp, LP = pcall(require, 'data.lab_pairs')
    st.ds = okp and type(LP) == 'table' and type(LP.death_source) == 'string' and LP.death_source or nil
    st.fast = st.ds ~= nil and LAB.cut_set()
    BUS.on('lab_hit', 'lab_poll', function(v, t, key)
        queue(v, 'hit', t or now(), key)
        if st.fast then st.urgent = true end
    end)
    BUS.on('lab_pawn', 'lab_poll', function(rec) st.pawn_in = rec end)
    BUS.on('lab_flush', 'lab_poll', function(reason)
        if LAB.beta() then                              -- the beta writes no fodder record (S5): its tier tallies (BD3)
            LAB.post(function() P.tier_tally(reason or 'periodic') end, 'lab_poll_tier')
            return
        end
        LAB.post(function() P.fodder(reason) end, 'lab_poll_fodder')
    end)
    BUS.on('lab_outcome', 'lab_poll', on_outcome)
    BUS.on('lab_row', 'lab_poll', on_row)
    BUS.on('lab_end', 'lab_poll', function() st.end_due = true end)   -- the next tick writes the held records
    LAB.gauge('victims_tracked', function() return st.n > 0 and st.n or nil end)   -- absent while none (log.lua:266)
    S.ticker('lab_poll', tick)
    return true
end
-- A map load: the set, the queue and the pawn go (lab_probe cleared its registry); the tallies stay for the session;
-- one FindAllOf is due FIND_AFTER_S later
function M.reset(reason)
    P.apply()                                   -- outcomes that came before the load land first (lab02, D5)
    P.flush('stale')                            -- then every held record: refused, why 'stale'
    st.rowq, st.outq, st.fastq, st.urgent = {}, {}, {}, false
    st.set, st.list, st.n, st.inbox, st.cur, st.excluded = {}, {}, 0, {}, 0, {}
    st.pawn, st.pawn_loc = nil, nil
    if reason == 'map' then st.find, st.find_at, st.found = 'wait', now() + M.FIND_AFTER_S, nil end
end
function M.status()
    return { victims = st.n, excluded_player = st.excluded_player, left = st.left, deaths = st.deaths,
        find = st.find, found = st.found, watch = st.watch, inbox = #st.inbox, dropped = st.dropped, full = st.full,
        refused = st.refused, reads = st.reads, read_fail = st.read_fail, candidates = st.candidates,
        admits = st.admits, revives = st.revives, held = st.npending, written = st.written, late = st.late,
        qdrop = st.qdrop, fast_reads = st.fast_reads }
end
-- A hot reload (Ctrl+R, OnUnload: engine-free) drops this state: the queued outcomes land, then every held record is
-- written, refused 'stale' (lab02, D5), so no life loses its kill record
function M.shutdown()
    if st.npending > 0 then
        P.apply()
        P.flush('stale')
    end
    S.remove_ticker('lab_poll')
    for _, ev in ipairs({ 'lab_hit', 'lab_pawn', 'lab_flush', 'lab_outcome', 'lab_row', 'lab_end' }) do
        BUS.off(ev, 'lab_poll')
    end
    token = token + 1
    st, A = new_state(), nil
end

return M
