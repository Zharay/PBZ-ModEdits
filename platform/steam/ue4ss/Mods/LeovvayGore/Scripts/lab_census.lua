-- status: new for the beta, BD6 (offline only; the author's run decides) origin: docs/research/beta-dismemberment-research.md#all-ordinary-enemies-findings
-- lab_census.lua: per-class and per-death read-only probes (docs/research/beta-dismemberment-plan.md BD6; research
-- A10 P1, P2, P4, P6, caps-shape probes 2 and 3). Player beta only (META.beta_modules, after lab_poll); the probe and
-- dev profiles never require it, and init stays inert (no listener, no ticker, no record) unless LAB.beta(). Reads
-- only: no write is counted (ue.status().writes), no object is made.
-- * When: bus listeners only queue (lab_death, lab_cut_live; nothing once LAB.pinned() reads false); the ticker runs
--   one step a frame, never in a busy frame (a lab_death or a lab_cut_live seen this frame or the one before, through
--   its own listeners, or lab_cut's K.status().jobs > 0: lab_cut ticks after this module, so its stage and commit
--   frames show here as jobs), never while paused or off (MODOFF.feature 'lab_census', not gameplay), never before
--   LAB.pinned() reads true, never after lab_end. After a stop (LAB.inherit_ok() false: the inherited lab.read.census
--   is refused from then on) the module ends for the session: one census_off record, the queue dropped, and the
--   bounds and body size reads, whose names are not inherited, stop with it. A step reads a corpse only while
--   LAB.alive holds it (not destroyed, not collected). Order: a weapon read at death, then the class census steps,
--   then a weapon read 1 s later once due, then a body size.
-- * class_census (P1, P4, P6, caps-shape probe 3), at the first death of each class per session (CLASSES_MAX classes,
--   TRIES deaths a class), four steps each its own frame, one forced record { class, id, age_s, row, tries, comps,
--   counts, slot0, lengths, span, neck, bounds, head_src, gone, errs }:
--   1. comps ('lab.read.census', a one-shot frame): K2_GetComponentsByClass(SceneComponent) (ue.components): every
--      skinned component (name, class, body, leader or follower, asset, same_skel: its asset's Skeleton is the
--      body's, the KEY_BONES it has), every StaticMesh, Niagara and Groom component (asset), each with its
--      AttachParent name and AttachSocketName (property reads); COMPS_MAX. The mod's own Cap meshes are
--      ProceduralMeshComponents and not listed; a meat Sphere fallback shows as a static 'Sphere'. slot0:
--      GetMaterial(0) class and name on the body and on the head (a meshhead route: the first component of the class
--      row's head names, 'no_head' when none is found; a body route: 'body').
--   2. bones ('lab.read.census'): world locations (GetSocketTransform RTS_World, after GetBoneIndex) on the body:
--      lengths L1 of every LENGTHS pair (the cap sizing's cut joint to child, data/caps_beta_sizing.lua), span S
--      (upperarm_l to upperarm_r), cm rounded to 0.1; on a meshhead route the neck bones (neck_01, neck_02, head).
--   3. bounds ('lab.read.bounds', meshhead routes only; 'no_head' without the head component): KismetSystemLibrary:
--      GetComponentBounds(head component) out params (Origin and BoxExtent filled in place, SphereRadius under its
--      name) and the origin relative to neck_01.
--   4. head_src ('lab.read.census'): whether a class of the victim's chain below BP_RenewalNPC_C declares
--      GetActorHead (StaticFindObject '<class path>:GetActorHead', walking GetSuperStruct, CHAIN_MAX), never called.
--   A corpse gone, or a refused or failed comps read, before step 1 read costs a try (the next death of the class
--   queues it again); the last try writes its record anyway (gone = why, errs), so a class never read is logged. Gone
--   later writes what was read with gone = why.
-- * weapon_at_death (P2), for classes of data/cut_classes.lua (WEAPON_PER_CLASS deaths a class, WEAPON_MAX records):
--   at the first free frame after the death and again WEAPON_LATER_S after that read: GetAttachedActors(out, true,
--   false) ('lab.read.census'; the out array fills the passed table, each element unwrapped with ue.p), each attached
--   actor's class, name, its root's AttachParent and AttachSocketName, and bHidden. Record { id, class, at 'death' |
--   'later', age_s (since the death source), n, actors, err } (err 'destroyed' or 'collected': the corpse went first).
--   The out array is a TArray argument, so adapter/tarray.lua's rule holds (one element conversion error leaves the
--   converter stuck for the session): a poisoned TA refuses the read before the call (one census_skip record, why
--   'poisoned'; no weapon record, no later read), the table goes through TA.check, and a call that raised poisons TA.
-- * body_size (caps-shape probe 2), on lab_cut_live, once per mesh asset and cut bone (BODY_MAX records; a class and
--   bone queued once, BODY_Q jobs at most): the Akasha slicer's GetSkeletalMeshPhysicsBodySize(the corpse's Mesh,
--   bone, OutRadius, OutLength) for the cut bone, and for head once per asset ('lab.read.bodysize'; each scalar out in
--   its own table under its name, the 1185 rule). Log only.
-- * Names (meta.lua lab_risky, data/lab_classes.lua): 'lab.read.census' (linger 0, inherited: refused after a stop,
--   lingers 2 s), 'lab.read.bounds' (3), 'lab.read.bodysize' (3), each checked with SENT.is_disabled and LAB.sig
--   first; a refused name skips its step and writes nothing more than one census_skip record per name and why (no
--   weapon or body record, no later read), 'sig_pending' waits a frame.
-- The kill contract (lab_poll build_kill writes it, BD3; lab_plan BD9 and lab_cut BD10 read it; BD0 pinned it in this
-- header, and the census itself reads none of it), pinned: every field below is on the beta's kill record and on the
-- lab_death payload's kill (d.kill), plain values only:
--   * tier: 'normal' | 'heavy' | 'shaqi', always set (missing data gives 'normal'; normal cuts 1 part, heavy the
--     heavy_parts knob, shaqi shaqi_parts, both capped by max_parts). The maximum over the player-bullet hits of the
--     death frame; status hits never count; a kill that is not the player's (by_player not true) is 'normal' and still
--     cuts one part (the author's answer 5).
--   * tier_src: what set a heavy or shaqi tier: 'skill' (SkillType Skill or Ultimate: shaqi; PowerAttack: heavy),
--     'path' (a ShachiWeapon or ShachiAbility bullet folder: shaqi), 'surge' (a main-weapon C-chain bullet, a Power
--     Surge such as GA_Hun_ZhanMa_C_C: shaqi, answer 2), 'attack_type' ('Shachi' in the attack type: shaqi), 'name' (a
--     B-chain or Charge combo token: heavy), 'strength' (a Heavy, Launchback, Knockdown or Dead.Launchback strength:
--     heavy); 'none' for normal.
--   * skill_type, strength, anim_strength, bullet: the killing hit's SkillType, Pre HitStrength, Post
--     StrengthAnimStrength and bullet asset name ('unread' when not read); frame_bullets: the distinct bullet names of
--     the death frame.
--   * attack_kind: 'weapon' | 'kick' | 'deflect' | 'status' | 'unread', from the blow (the snapshot kill.bone comes
--     from): 'kick' when its attack type (else its final attack type) names Kick (Kick.Player), 'deflect' when it
--     names Deflect (Deflect.Normal), 'status' when bleed_only, 'weapon' for any other read attack type or bullet. A
--     kick or a deflect never cuts, whoever kicked (answer 3).
--   * bleed_only: true when every hit of the death frame is a status hit (a StatusInfliction cause such as Bleed or
--     BloodBurst, a DamageSource_GameplayEffect source, attack type Energy) with no bullet or weapon hit; false when
--     the frame holds another hit; 'unread' for a poll kill (no frame). true never cuts: blood only (answer 4).
--   * unchanged: bone, bone_src, by_player, execution (an execution never cuts, answer 12), blow, killer.
-- lab_plan's beta decide (BD9) on top of beta port S3's skips: a class not in data/cut_classes.lua gives row
-- 'not_cut_class'; after the execution skip and before readiness, attack_kind 'kick' or 'deflect' gives row
-- 'no_cut_blow' (why: the kind) and bleed_only true gives row 'bleed_only'; all three lab_skip, blood only. A
-- 'heads' row carries d.pair = the class row's layout and d.class_row = the data/cut_classes.lua row (its shape: that
-- file's header).
-- API: CEN.N, CEN.F (the literal name tables); CEN.attached(actor, max, each) (the TArray-safe GetAttachedActors read,
--   lab_sword's census too); lifecycle init(A) reset(reason) shutdown() status().
-- What the mock cannot prove: native faults, UE4SS's out-param marshalling of GetComponentBounds and
-- GetSkeletalMeshPhysicsBodySize on dff435dd, the real component sets, weapon attachments and capsule sizes.
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local TA = require('adapter.tarray')
local LAB = require('lab_probe')

local CEN = { CLASSES_MAX = 64, TRIES = 3, WEAPON_PER_CLASS = 2, WEAPON_MAX = 60, BODY_MAX = 48, BODY_Q = 8,
    QMAX = 32, COMPS_MAX = 48, ATTACHED_MAX = 16, CHAIN_MAX = 8, WEAPON_LATER_S = 1, ERR_CHARS = 160,
    SCENE = '/Script/Engine.SceneComponent', SKINNED = '/Script/Engine.SkinnedMeshComponent',
    STATIC = '/Script/Engine.StaticMeshComponent', NIAGARA = '/Script/Niagara.NiagaraComponent',
    GROOM = '/Script/HairStrandsCore.GroomComponent',
    SLICER = '/Script/AkashaEffects.Default__AkashaRuntimeSkeletalMeshSlicerLibrary',
    HEAD_FN = 'GetActorHead', HEAD_BASE = 'BP_RenewalNPC_C', RTS_WORLD = 0 }
-- The bones a skinned component is checked for (research P1)
CEN.KEY_BONES = { 'neck_01', 'head', 'upperarm_r', 'lowerarm_r', 'thigh_r', 'calf_r' }
-- L1 of each cap part (data/caps_beta_sizing.lua l1: the cut joint to its child), both sides: { name, joint, child }
CEN.LENGTHS = { { 'head', 'neck_01', 'head' } }
for _, s in ipairs({ 'l', 'r' }) do
    for _, p in ipairs({ { 'upperarm', 'lowerarm' }, { 'lowerarm', 'hand' }, { 'thigh', 'calf' },
        { 'calf', 'foot' } }) do
        CEN.LENGTHS[#CEN.LENGTHS + 1] = { p[1] .. '_' .. s, p[1] .. '_' .. s, p[2] .. '_' .. s }
    end
end
CEN.NECK = { 'neck_01', 'neck_02', 'head' }
CEN.CLASS_STEPS = { 'comps', 'bones', 'bounds', 'head_src' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua lab.read.census, .bounds, .bodysize)
local N = {}
local F = {
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SkinnedMeshComponent", "LeaderPoseComponent"},
    {"/Script/Engine.SkeletalMesh", "Skeleton"},
    {"/Script/Engine.SceneComponent", "AttachParent"},
    {"/Script/Engine.SceneComponent", "AttachSocketName"},
    {"/Script/Engine.StaticMeshComponent", "StaticMesh"},
    {"/Script/Niagara.NiagaraComponent", "Asset"},
    {"/Script/HairStrandsCore.GroomComponent", "GroomAsset"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.Actor", "bHidden"},
}
CEN.N, CEN.F = N, F

local A = nil
local function new_state()
    return { init = false, ended = false, off = false, classes = {}, nclasses = 0, tries = {}, queued = {},
        weapons = {}, nweapons = 0, bodies = {}, nbodies = 0, heads = {}, body_q = {}, jobs = {}, dropped = 0,
        skips = {}, busy_f = nil, busy = 0, steps = 0 }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function r3(v) return num(v) and math.floor(v * 1000 + 0.5) / 1000 or nil end
local function err_text(e)
    e = tostring(e)
    return #e > CEN.ERR_CHARS and e:sub(1, CEN.ERR_CHARS) or e
end
local function class_of(o) local f = ue.full(o) return f and f:match('^(%S+) ') or nil end
local function path_of(o) local f = ue.full(o) return f and (f:match('^%S+ (.+)$') or f) or nil end
local function text(v)                              -- an FName or string as text; nil for '', 'None' or no value
    local s = ue.str(v)
    if s == nil or s == '' or s == 'None' then return nil end
    return s
end
local function name_or(o, w) return ue.valid(o) and (ue.name(o) or '?') or w end
local function or_unread(v) if v == nil then return 'unread' end return v end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
local function cut_row(class) return (data('data.cut_classes').classes or {})[class] end

-- ---------- gates ----------
-- A busy frame (BD0): a lab_death or a lab_cut_live seen this frame or the one before, or lab_cut's jobs waiting
local function busy()
    if st.busy_f and S.frame - st.busy_f <= 1 then return true end
    local K = package.loaded['lab_cut']
    if type(K) == 'table' and type(K.status) == 'function' then
        local ok, s = pcall(K.status)
        if ok and type(s) == 'table' and (tonumber(s.jobs) or 0) > 0 then return true end
    end
    return false
end
-- A refused step: one census_skip record per name and why. why
local function skip(name, probe, why)
    local k = name .. '|' .. tostring(why)
    if not st.skips[k] then
        st.skips[k] = true
        LAB.rec('census_skip', { name = name, probe = probe, why = why }, true)
    end
    return why
end
-- 'ok', 'wait' (its sig check pending: the same step next frame), or why the name is refused (skip)
local function gate(name, probe)
    local why
    if SENT.is_disabled(name) then why = 'disabled'
    else
        local ok, w = LAB.sig(name)
        if ok then return 'ok' end
        if w == 'sig_pending' then return 'wait' end
        why = w or 'sig'
    end
    return skip(name, probe, why)
end
-- After a stop lab.read.census is refused (inherited) and the module ends for the session, the bounds and body size
-- reads with it: one census_off record, nothing more is read
local function stop_all()
    if st.off then return end
    local n = #st.jobs
    st.off, st.jobs = true, {}
    LAB.rec('census_off', { why = 'inherit_off', dropped = n }, true)
end
-- A guarded call refused 'inherit_off' (a stop since this frame's check): true after ending the module
local function stopped(err)
    if err ~= 'inherit_off' then return false end
    stop_all()
    return true
end
local function push(job)
    if #st.jobs >= CEN.QMAX then st.dropped = st.dropped + 1 return false end
    st.jobs[#st.jobs + 1] = job
    return true
end

-- ---------- reads (each inside its armed call) ----------
local function xyz(v)
    local x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z')
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
local function rv(p) return p and { r1(p.x), r1(p.y), r1(p.z) } or nil end
local function dist(a, b)
    if not (a and b) then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return r1(math.sqrt(dx * dx + dy * dy + dz * dz))
end
-- A bone's world location on a skinned component (GetSocketTransform RTS_World after GetBoneIndex: a name that is no
-- bone answers the component's own transform); nil when it has no such bone or the read failed
local function bone_at(mesh, bone)
    if not ue.has_bone(mesh, bone) then return nil end
    local ok, t = ue.call(mesh, 'GetSocketTransform', ue.fname(bone), CEN.RTS_WORLD)
    if not ok then return nil end
    return xyz(ue.prop(t, 'Translation'))
end
local function slot0(c)
    if not ue.valid(c) then return 'none' end
    local ok, m = ue.call(c, 'GetMaterial', 0)
    m = ok and ue.p(m) or nil
    if not ue.valid(m) then return ok and 'none' or 'unread' end
    return (class_of(m) or '?') .. ' ' .. (ue.name(m) or '?')
end
local function kind_of(c)
    if ue.is_a(c, CEN.SKINNED) then return 'skinned' end
    if ue.is_a(c, CEN.STATIC) then return 'static' end
    if ue.is_a(c, CEN.NIAGARA) then return 'niagara' end
    if ue.is_a(c, CEN.GROOM) then return 'groom' end
    return nil
end
-- 1. comps: the components of interest and slot 0 of the body and the head; the head component kept for the bounds
local function read_comps(actor, row)
    local body = ue.get(actor, 'Mesh')
    local list, read = ue.components(actor, CEN.SCENE)
    if not read then return { err = 'components_unread' } end
    local bskel = ue.valid(body) and ue.prop(ue.prop(body, 'SkinnedAsset'), 'Skeleton') or nil
    local meshhead, heads = row ~= nil and row.route == 'meshhead', {}
    for _, n in ipairs(meshhead and type(row.head) == 'table' and row.head or {}) do heads[n] = true end
    local out, counts, head = {}, { skinned = 0, static = 0, niagara = 0, groom = 0 }, nil
    for _, c in ipairs(list) do
        local kind = kind_of(c)
        if kind then
            counts[kind] = counts[kind] + 1
            local name = ue.name(c) or '?'
            if heads[name] and head == nil then head = c end
            if #out < CEN.COMPS_MAX then
                local e = { name = name, class = class_of(c) or 'unread', kind = kind,
                    parent = name_or(ue.prop(c, 'AttachParent'), 'none'),
                    socket = text(ue.prop(c, 'AttachSocketName')) }
                if kind == 'skinned' then
                    local asset = ue.prop(c, 'SkinnedAsset')
                    local skel = ue.prop(asset, 'Skeleton')
                    e.asset, e.body = name_or(asset, 'none'), ue.same(c, body)
                    e.leader = not ue.valid(ue.weak(ue.get(c, 'LeaderPoseComponent')))
                    if ue.valid(skel) and ue.valid(bskel) then e.same_skel = ue.same(skel, bskel)
                    else e.same_skel = 'unread' end
                    e.bones = {}
                    for _, b in ipairs(CEN.KEY_BONES) do if ue.has_bone(c, b) then e.bones[#e.bones + 1] = b end end
                elseif kind == 'static' then e.asset = name_or(ue.prop(c, 'StaticMesh'), 'none')
                elseif kind == 'niagara' then e.asset = name_or(ue.prop(c, 'Asset'), 'none')
                else e.asset = name_or(ue.prop(c, 'GroomAsset'), 'none') end
                out[#out + 1] = e
            end
        end
    end
    local hslot = head and slot0(head) or (meshhead and 'no_head' or 'body')
    return { comps = out, counts = counts, slot0 = { body = slot0(body), head = hslot }, head = head }
end
-- 2. bones: L1 per part, the shoulder span, the neck bones on a meshhead route
local function read_bones(actor, meshhead)
    local body = ue.get(actor, 'Mesh')
    if not ue.valid(body) then return { err = 'no_body' } end
    local at = {}
    local function pos(b)
        if at[b] == nil then at[b] = bone_at(body, b) or false end
        return at[b] or nil
    end
    local lengths = {}
    for _, l in ipairs(CEN.LENGTHS) do lengths[l[1]] = or_unread(dist(pos(l[2]), pos(l[3]))) end
    local r = { lengths = lengths, span = or_unread(dist(pos('upperarm_l'), pos('upperarm_r'))) }
    if meshhead then
        r.neck = {}
        for _, b in ipairs(CEN.NECK) do r.neck[b] = rv(pos(b)) or 'none' end
        r.neck01 = pos('neck_01')
    end
    return r
end
-- 3. bounds: GetComponentBounds' out params (structs filled in place, the scalar under its name)
local function read_bounds(c)
    local ksl = ue.cdo('ksl')
    if not ksl then return { err = 'no_lib' } end
    local o, e, rad = {}, {}, {}
    local ok, err = ue.call(ksl, 'GetComponentBounds', c, o, e, rad)
    if not ok then return { err = err_text(err) } end
    return { origin = xyz(o), extent = xyz(e), radius = r1(rad.SphereRadius) }
end
-- 4. head_src: the first class of the chain below BP_RenewalNPC_C that declares GetActorHead (found, never called)
local function read_head_src(actor)
    local okc, cls = pcall(function() return actor:GetClass() end)
    if not okc or not ue.valid(cls) then return { override = 'unread' } end
    local walked = 0
    for _ = 1, CEN.CHAIN_MAX do
        local name = ue.name(cls)
        if name == nil then return { override = 'unread', walked = walked } end
        if name == CEN.HEAD_BASE then return { override = 'none', walked = walked } end
        local p = path_of(cls)
        if p and ue.find(p .. ':' .. CEN.HEAD_FN) then return { override = name, walked = walked } end
        walked = walked + 1
        local oks, sup = pcall(function() return cls:GetSuperStruct() end)
        if not oks or not ue.valid(sup) then return { override = 'none', walked = walked, base = false } end
        cls = sup
    end
    return { override = 'none', walked = walked, base = false }
end
-- The actors attached to actor: GetAttachedActors(out, true, false), its out array the passed table or a table under
-- its name. The table is a TArray argument: TA.check first (a poisoned state refuses), and a raise poisons TA (the
-- header; 'invalid object': no call was made). each(a) gets the elements unwrapped (ue.p), in order, at most max:
-- bounded by #, as a read past the end grows the array. Runs inside its caller's armed call (lab_sword's census too).
-- -> n | nil, where ('check' | 'call' | 'count'), why (TA.check's word, the call's error; nil for 'count')
function CEN.attached(actor, max, each)
    local t = {}
    local nt, why = TA.check(t, 'object')
    if not nt then return nil, 'check', why end
    local ok, err = ue.call(actor, 'GetAttachedActors', t, true, false)
    if not ok then
        if err ~= 'invalid object' then TA.poison('GetAttachedActors') end
        return nil, 'call', err
    end
    local arr = t.OutActors
    if arr == nil then arr = t end
    local okn, n = pcall(function() return #arr end)
    if not okn or type(n) ~= 'number' then return nil, 'count' end
    for i = 1, math.min(n, max) do each(ue.p(arr[i])) end
    return n
end
-- weapon_at_death: each attached actor's class, name, root attachment and bHidden
local function read_weapons(actor)
    local out = {}
    local n, at, why = CEN.attached(actor, CEN.ATTACHED_MAX, function(a)
        if ue.valid(a) then
            local root = ue.prop(a, 'RootComponent')
            out[#out + 1] = { class = class_of(a) or 'unread', name = ue.name(a) or '?',
                parent = name_or(ue.prop(root, 'AttachParent'), 'none'),
                socket = text(ue.prop(root, 'AttachSocketName')),
                hidden = or_unread(ue.prop(a, 'bHidden')) }
        end
    end)
    if n then return { n = n, actors = out } end
    if at == 'check' then return { err = why } end
    return { err = at == 'call' and err_text(why) or 'unread' }
end
-- body_size: GetSkeletalMeshPhysicsBodySize per bone, each scalar out in its own table (the 1185 rule)
local function read_bodysize(leader, bones)
    local lib = ue.cdo(CEN.SLICER)
    if not lib then return { err = 'no_lib' } end
    local out = {}
    for _, b in ipairs(bones) do
        local rt, lt = {}, {}
        local ok, err = ue.call(lib, 'GetSkeletalMeshPhysicsBodySize', leader, ue.fname(b), rt, lt)
        out[#out + 1] = { bone = b, radius = ok and r3(rt.OutRadius) or 'unread',
            length = ok and r3(lt.OutLength) or 'unread', err = (not ok) and err_text(err) or nil }
    end
    return { bones = out }
end

-- ---------- the jobs ----------
local function age(job) return num(job.death_t) and r1(now() - job.death_t) or 'unread' end
local function unqueue(job)
    table.remove(st.jobs, job.at)
    st.queued[job.class] = nil
end
-- The class census record: what was read, gone = why when the corpse went between steps (or before any read, on the
-- class's last try)
local function class_rec(job, gone)
    local r = job.r
    st.classes[job.class], st.nclasses = true, st.nclasses + 1
    local row = cut_row(job.class)
    LAB.rec('class_census', { class = job.class, id = job.id, age_s = job.age, row = row and (tostring(row.route)
        .. ' ' .. tostring(row.layout)) or 'not_cut_class', tries = st.tries[job.class], comps = r.comps,
        counts = r.counts, slot0 = r.slot0, lengths = r.lengths, span = r.span, neck = r.neck, bounds = r.bounds,
        head_src = r.head_src, gone = gone, errs = next(r.errs) and r.errs or nil }, true)
end
-- Nothing read for the class (its corpse gone, or the comps read refused or failed): the try is spent and the next
-- death of the class queues it again; the last try writes the record anyway, so a class never read is logged
local function spent(job, gone)
    unqueue(job)
    if (st.tries[job.class] or 0) >= CEN.TRIES and st.nclasses < CEN.CLASSES_MAX then class_rec(job, gone) end
end
local function step_class(job)
    local actor, why = LAB.alive(job.victim)
    if not actor then
        if job.r.comps then
            unqueue(job)
            class_rec(job, why)
        else spent(job, why) end
        return
    end
    local s = CEN.CLASS_STEPS[job.i]
    if s == 'bounds' and not (job.r.head and ue.live(job.r.head)) then      -- a body route, or no head component
        if job.row ~= nil and job.row.route == 'meshhead' then job.r.bounds = job.r.head and 'gone' or 'no_head' end
        job.i = job.i + 1
        s = CEN.CLASS_STEPS[job.i]
    end
    local g = s == 'bounds' and gate('lab.read.bounds', s) or gate('lab.read.census', s)
    if g == 'wait' then return 'wait' end
    local r, err = nil, g ~= 'ok' and g or nil
    if g == 'ok' then
        if s == 'comps' then
            LAB.oneshot()                               -- the component walk
            r, err = LAB.armed('lab.read.census', read_comps, actor, job.row)
            if type(r) == 'table' then job.age = age(job) end
        elseif s == 'bones' then
            r, err = LAB.armed('lab.read.census', read_bones, actor, job.row ~= nil and job.row.route == 'meshhead')
        elseif s == 'bounds' then r, err = LAB.armed('lab.read.bounds', read_bounds, ue.live(job.r.head))
        else r, err = LAB.armed('lab.read.census', read_head_src, actor) end
    end
    if stopped(err) then return end
    if type(r) == 'table' and r.err then err, r = r.err, nil end
    if err ~= nil then job.r.errs[s] = err_text(err) end
    if type(r) == 'table' then
        if s == 'comps' then
            job.r.comps, job.r.counts, job.r.slot0 = r.comps, r.counts, r.slot0
            job.r.head = r.head and ue.keep(r.head) or nil
        elseif s == 'bones' then
            job.r.lengths, job.r.span, job.r.neck, job.neck01 = r.lengths, r.span, r.neck, r.neck01
        elseif s == 'bounds' then
            local d = r.origin and job.neck01 and { r1(r.origin.x - job.neck01.x), r1(r.origin.y - job.neck01.y),
                r1(r.origin.z - job.neck01.z) } or nil
            job.r.bounds = { origin = rv(r.origin) or 'unread', extent = rv(r.extent) or 'unread',
                radius = or_unread(r.radius), from_neck_01 = d }
        else job.r.head_src = r end
    elseif s == 'comps' then                            -- nothing read: a try spent, the class may come again
        spent(job, nil)
        return
    end
    job.i = job.i + 1
    if job.i > #CEN.CLASS_STEPS then
        unqueue(job)
        class_rec(job, nil)
    end
end
local function step_weapon(job)
    table.remove(st.jobs, job.at)
    if st.nweapons >= CEN.WEAPON_MAX then return end
    local actor, err = LAB.alive(job.victim)
    local r = nil
    if actor then
        local g = gate('lab.read.census', 'weapon')
        if g == 'wait' then table.insert(st.jobs, job.at, job) return 'wait' end
        if g == 'ok' and TA.poisoned() then g = skip('lab.read.census', 'weapon', 'poisoned') end
        if g ~= 'ok' then return end                    -- refused: its census_skip record says why, no later read
        r, err = LAB.armed('lab.read.census', read_weapons, actor)
        if stopped(err) then return end
    end
    if type(r) == 'table' and r.err then err, r = r.err, nil end
    st.nweapons = st.nweapons + 1
    LAB.rec('weapon_at_death', { id = job.id, class = job.class, at = job.when, age_s = age(job),
        n = r and r.n or nil, actors = r and r.actors or nil, err = err and err_text(err) or nil }, true)
    if job.when == 'death' and actor then
        push({ kind = 'weapon', when = 'later', victim = job.victim, id = job.id, class = job.class,
            death_t = job.death_t, due = now() + CEN.WEAPON_LATER_S })
    end
end
-- The body size of the corpse's Mesh (lab_cut's leader, read again from the live corpse: no object kept across
-- frames) for the cut bone and head, each once per mesh asset. body_q[key] 'queued' -> 'done', or nil again when the
-- corpse went first (the next cut of that class and bone asks again)
local function step_body(job)
    table.remove(st.jobs, job.at)
    if st.nbodies >= CEN.BODY_MAX then return end
    local actor = LAB.alive(job.victim)
    local leader = actor and ue.get(actor, 'Mesh') or nil
    if not ue.valid(leader) then
        st.body_q[job.key] = nil
        return
    end
    local asset = path_of(ue.prop(leader, 'SkinnedAsset')) or 'unread'
    local bones = {}
    if job.bone ~= 'head' and not st.bodies[asset .. '|' .. job.bone] then bones[#bones + 1] = job.bone end
    if not st.heads[asset] then bones[#bones + 1] = 'head' end
    local g = bones[1] and gate('lab.read.bodysize', 'body_size') or 'none'
    if g == 'wait' then table.insert(st.jobs, job.at, job) return 'wait' end
    st.body_q[job.key] = 'done'
    if g ~= 'ok' then return end                        -- nothing new for this asset, or refused (census_skip)
    local r, err = LAB.armed('lab.read.bodysize', read_bodysize, leader, bones)
    for _, b in ipairs(bones) do
        if b == 'head' then st.heads[asset] = true else st.bodies[asset .. '|' .. b] = true end
    end
    if type(r) == 'table' and r.err then err, r = r.err, nil end
    st.nbodies = st.nbodies + 1
    LAB.rec('body_size', { asset = asset, class = job.class, part = job.part, bones = r and r.bones or nil,
        err = err and err_text(err) or nil }, true)
end
-- The next job: a weapon read at death, then the class census, then a later weapon read once due, then a body size
local function next_job()
    local t = now()
    for _, pass in ipairs({ 'death', 'class', 'later', 'body' }) do
        for i, j in ipairs(st.jobs) do
            local hit = (pass == 'death' and j.kind == 'weapon' and j.when == 'death') or (pass == 'class'
                and j.kind == 'class') or (pass == 'later' and j.kind == 'weapon' and j.when == 'later' and t >= j.due)
                or (pass == 'body' and j.kind == 'body')
            if hit then
                j.at = i
                return j
            end
        end
    end
    return nil
end
local RUN = { class = step_class, weapon = step_weapon, body = step_body }
local function tick()
    if not st.init or st.ended or st.off then return end
    if LAB.ended() then st.ended, st.jobs = true, {} return end
    if not LAB.inherit_ok() then stop_all() return end
    if LAB.pinned() ~= true or LAB.paused() or not MODOFF.enabled('lab_census') then return end
    if not st.jobs[1] then return end
    if busy() then st.busy = st.busy + 1 return end
    local job = next_job()
    if not job then return end
    if RUN[job.kind](job) ~= 'wait' then st.steps = st.steps + 1 end
end

-- ---------- the listeners: queue only ----------
local function on_death(d)
    st.busy_f = S.frame
    if type(d) ~= 'table' or st.off or st.ended or LAB.pinned() == false or type(d.class) ~= 'string' then return end
    local class, victim = d.class, d.victim or d.keep
    if victim == nil then return end
    local base = { victim = victim, id = d.id, class = class, death_t = tonumber(d.death_t) or tonumber(d.t) or now() }
    local row = cut_row(class)
    if row and (st.weapons[class] or 0) < CEN.WEAPON_PER_CLASS and st.nweapons < CEN.WEAPON_MAX then
        local j = { kind = 'weapon', when = 'death' }
        for k, v in pairs(base) do j[k] = v end
        if push(j) then st.weapons[class] = (st.weapons[class] or 0) + 1 end
    end
    if st.classes[class] or st.queued[class] or (st.tries[class] or 0) >= CEN.TRIES
        or st.nclasses >= CEN.CLASSES_MAX then return end
    local j = { kind = 'class', i = 1, row = row, r = { errs = {} } }
    for k, v in pairs(base) do j[k] = v end
    if push(j) then st.queued[class], st.tries[class] = true, (st.tries[class] or 0) + 1 end
end
-- Plain fields only: the cut table holds raw objects and lab_cut keeps writing it
local function on_cut(cut)
    st.busy_f = S.frame
    if type(cut) ~= 'table' or type(cut.bone) ~= 'string' or st.off or st.ended or LAB.pinned() == false
        or st.nbodies >= CEN.BODY_MAX then return end
    local victim = cut.victim or ue.keep(cut.actor)
    local class = cut.class or (type(cut.victim) == 'table' and cut.victim.class) or 'unread'
    local key = tostring(class) .. '|' .. cut.bone
    if victim == nil or st.body_q[key] then return end
    local n = 0
    for _, j in ipairs(st.jobs) do if j.kind == 'body' then n = n + 1 end end
    if n >= CEN.BODY_Q then st.dropped = st.dropped + 1 return end
    if push({ kind = 'body', victim = victim, key = key, class = class, bone = cut.bone, part = cut.part }) then
        st.body_q[key] = 'queued'
    end
end

-- ---------- lifecycle ----------
local EVENTS = { 'lab_death', 'lab_cut_live', 'lab_end' }
function CEN.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    LAB.names(N, F)
    MODOFF.feature('lab_census', {})                    -- mod-off pauses the reads; the vanilla compare does not
    BUS.on('lab_death', 'lab_census', on_death)
    BUS.on('lab_cut_live', 'lab_census', on_cut)
    BUS.on('lab_end', 'lab_census', function() st.ended, st.jobs = true, {} end)
    S.ticker('lab_census', tick)
    return true
end
-- A map load: the queued corpses went with the old map (a queued body size may ask again); the classes done, the
-- tries and the asset sets stay
function CEN.reset(reason)
    if not st.init or reason ~= 'map' then return end
    st.jobs, st.queued, st.busy_f = {}, {}, nil
    for k, v in pairs(st.body_q) do if v == 'queued' then st.body_q[k] = nil end end
end
function CEN.status()
    return { init = st.init, ended = st.ended, off = st.off, classes = st.nclasses, weapons = st.nweapons,
        bodies = st.nbodies, jobs = #st.jobs, dropped = st.dropped, steps = st.steps, busy = st.busy }
end
function CEN.shutdown()
    S.remove_ticker('lab_census')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_census') end
    st, A = new_state(), nil
end
return CEN
