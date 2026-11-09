-- status: new for the beta (offline only; the author's run decides) origin: docs/research/beta-dismemberment-plan.md#bd10-g1-one-worktree-two-sequential-commits
-- lab_cut_beta.lua: the player beta's half of lab_cut (docs/research/beta-dismemberment-plan.md BD10, replacing beta
-- port S4; research H4, MC1-MC5, A3, C4): a library lab_cut requires (no init, no listener, no ticker; its functions
-- work on the state table lab_cut passes; house rule HR-CLEANUP keeps lab_cut under 1500 lines). It never arms: the
-- engine reads and writes below run inside lab_cut's armed calls ('lab.cut.stage', 'lab.cut.head', 'lab.cut.limb'),
-- and the records go through LAB.rec.
-- * Parts (pure): part_of(bone) the part the struck bone names; first(kill, opts) the kill's first part (D3 of
--   docs/spec/fixes-0.2.2.md: the struck part, else band_of(kill)'s weights drawn by body_pick(kill, plane) with the
--   kill's own generator; the head is never forced); parts_of(kill, cache, n, opts) the kill's parts in rank order with
--   what was dropped and why and first's pick; nparts(kill) how many the tier and the knobs want.
-- * Jobs (lab_cut's st): primary(job, st, t) a 'heads' row's rank-1 job; plan(job, c, st, t) the kill's plan at its
--   primary's stage (the extras queued under the parts_per_s cap, the forced cut_plan record); finish(job, outcome, why,
--   f, st) an at_death job's end (the forced cut_fail with its rank, the breaker, lab_outcome for the primary only).
-- * The breaker (st.brk, the session's): 2 counted failures in a row on one mesh asset blacklist it (forced bad_asset),
--   5 in a row overall stop the beta's cuts (forced beta_off); counted COUNTED and 'commit_fail:<step>'; a commit resets
--   both runs.
-- * Stage reads (inside 'lab.cut.stage'): levers(actor) (MC5: the keep levers of a LingeringDead body, never written:
--   cut.kept, cut.levers); hide_set(list, row, names) (A3: the class row's head names required, its hair, hat_mask and
--   glow names optional); scan(cut, list, leaders, sub) (META.beta_scan: SceneComponents attached into the cut
--   subtree); size(cut, span, bucket, z_to, t) (C4: cut.size from bone lengths and the shoulder span, the roll from the
--   actor's forward; cut.stage_joint, cut.stage_t, cut.d_world); launch(cut, d) (MC4's stage half: cut.dir, speed, up).
-- * The commit (inside 'lab.cut.head' or 'lab.cut.limb'): pre_reads(cut) whether each component of the hide set was
--   drawn before the hide (the unwind and the restore put its bHiddenInGame back); settle(cut) the hide set after the
--   hide (what did not hide is left out and logged).
-- * Heads (lab_gib's contract, lab_gib.lua header): head_mode(row, G) the mode and hair of a head job ('gib_off' when
--   lab_gib cannot take it); gib_reads(cut) the world transforms lab_gib needs, read in the commit before the hide;
--   gib(cut, P) cut.gib.
-- * rec(cut) the beta's fields of the cut record.
-- API: the functions above, ARM, LEG, FIXED, PLANE_Z, BANDS, BODY_W, VERT_HEAD_K, VERT_BANDS, LEVERS, COUNTED,
--   BAD_ASSET_N, BETA_OFF_N, HEAD_V, LIMB_V, UP_V, OUT_K, GIB_KIND, ROLL_COS, NOT_SCAN, SCENE, CHAIN_MAX, maps(b, list,
--   side), family(part), size_r(stem, L1, S), breaker(), counted(why), plain_xf(t) and gib_class(cls) (lab_slice's
--   hats and masks too), N, F.
-- What the mock cannot prove: the bone names, sockets and attachments of the 154 rigs, whether the tiers match the
-- author's blows, the levers on a LingeringDead body, the cap sizes and roll on real bodies, the launch look.
local BUS = require('core.bus')
local S = require('core.sched')
local CFG = require('core.config')
local RNG = require('core.rng')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local TA = require('adapter.tarray')
local LAB = require('lab_probe')

local KB = { CHAIN_MAX = 8, SCENE = '/Script/Engine.SceneComponent' }
-- The struck bone (lower case, a twist bone too) to its limb part: arms, then legs, each {prefix, part stem}
KB.ARM = { { 'upperarm', 'upperarm' }, { 'clavicle', 'upperarm' }, { 'lowerarm', 'lowerarm' }, { 'forearm', 'lowerarm' },
    { 'hand', 'lowerarm' } }
KB.LEG = { { 'thigh', 'thigh' }, { 'calf', 'calf' }, { 'foot', 'calf' }, { 'ball', 'calf' } }
-- The fixed fallbacks after the first part, the swing-plane partner and the head (research H4, D3); the unit sweep's
-- |z| at least PLANE_Z is a vertical swing
KB.FIXED, KB.PLANE_Z = { 'upperarm_r', 'upperarm_l', 'thigh_r', 'thigh_l' }, 0.6
-- The first part when no head, neck, arm or leg bone names it (docs/spec/fixes-0.2.2.md D3, rungs P2 and P3): the body
-- band of the reading (BANDS: the fine HitBone's prefix, else the coarse reading kill.coarse; 'none' when nothing
-- reads) draws from its weights { part, weight } (BODY_W, one data table: retune it here). The arrays keep a fixed
-- order: the draw walks them, never pairs(). A vertical swing multiplies the head's weight by VERT_HEAD_K in the
-- VERT_BANDS (an overhead chop crosses the neck); a horizontal one leaves the table
KB.BANDS = {
    fine = { { 'spine_03', 'chest' }, { 'spine_04', 'chest' }, { 'spine_05', 'chest' }, { 'spine_01', 'belly' },
        { 'spine_02', 'belly' }, { 'pelvis', 'hips' }, { 'root', 'hips' } },
    coarse = { { 'spine', 'upper' }, { 'root', 'lower' }, { 'pelvis', 'lower' } } }
KB.BODY_W = {
    chest = { { 'head', 40 }, { 'upperarm_l', 30 }, { 'upperarm_r', 30 } },
    belly = { { 'lowerarm_l', 25 }, { 'lowerarm_r', 25 }, { 'thigh_l', 20 }, { 'thigh_r', 20 }, { 'head', 10 } },
    hips = { { 'thigh_l', 50 }, { 'thigh_r', 50 } },
    upper = { { 'head', 30 }, { 'upperarm_l', 20 }, { 'upperarm_r', 20 }, { 'lowerarm_l', 15 }, { 'lowerarm_r', 15 } },
    lower = { { 'thigh_l', 50 }, { 'thigh_r', 50 } },
    none = { { 'head', 40 }, { 'upperarm_l', 15 }, { 'upperarm_r', 15 }, { 'thigh_l', 15 }, { 'thigh_r', 15 } } }
-- The vertical head factor and its bands (a name of its own: HEAD_V below is the head Piece's launch speed)
KB.VERT_HEAD_K, KB.VERT_BANDS = 2, { chest = true, upper = true, none = true }
-- The breaker: counted failures in a row on one mesh asset, overall; the refusals it counts besides 'commit_fail:<step>'
KB.BAD_ASSET_N, KB.BETA_OFF_N = 2, 5
KB.COUNTED = { stage = true, cap_build = true, cap_attach = true, piece_build = true, piece_cap = true }
-- MC5: the keep levers lab_keep writes (LingeringDead writes the same), read only: record key, property, type
KB.LEVERS = { { key = 'disable_dissol', prop = 'DisableDeathDissol', t = 'boolean' },
    { key = 'death_delay', prop = 'Death Delay', t = 'number' },
    { key = 'destroy_after', prop = 'DestroyAfterDead', t = 'boolean' },
    { key = 'destroy_delay', prop = 'DestroyDelay', t = 'number' } }
-- MC4 at death (research 'Launch from a body in its death animation'): uu/s along unit(sweep + OUT_K x d_out), a head
-- HEAD_V, a limb LIMB_V, UP_V up (lab_piece clamps vz, adds the body's motion and caps |v|)
KB.HEAD_V, KB.LIMB_V, KB.UP_V, KB.OUT_K = 450, 300, 150, 0.5
-- The hide set's optional kinds lab_gib takes as extras (hats, masks, glow, scan hits); the forward vector nearly along
-- d (|cos| above ROLL_COS) takes the stump bone's own axis for the roll
KB.GIB_KIND, KB.ROLL_COS = { hat_mask = true, glow = true, scan = true }, 0.9
-- Classes the scan never takes: the mod's own Caps and lab_blood's attached decals
KB.NOT_SCAN = { ProceduralMeshComponent = true, DecalComponent = true }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua lab.cut.stage, lab.cut.head, lab.cut.limb)
local N = {}
local F = {
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "DisableDeathDissol"},
    {"/Game/RenewalContent/Prototypes/Character/BP_RenewalNPC.BP_RenewalNPC_C", "Death Delay"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyAfterDead"},
    {"/Game/PBZContent/Blueprint/Character/NPC/BP_NPC_Base.BP_NPC_Base_C", "DestroyDelay"},
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.SceneComponent", "bVisible"},
}
KB.N, KB.F = N, F

local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function unit3(v)
    if type(v) ~= 'table' or not (num(v.x) and num(v.y) and num(v.z)) then return nil end
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if n < 1e-6 then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
local function r2(x) return num(x) and math.floor(x * 100 + 0.5) / 100 or nil end
-- {x, y, z} of an engine vector (X/Y/Z) or a plain one; nil unless three finite numbers
local function vec3(v)
    local x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z')
    if x == nil and type(v) == 'table' then x, y, z = v.x, v.y, v.z end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
-- An engine FTransform as { loc, quat {w,x,y,z}, scale } | nil
local function plain_xf(t)
    local l, s, r = vec3(ue.prop(t, 'Translation')), vec3(ue.prop(t, 'Scale3D')), ue.prop(t, 'Rotation')
    local q = { w = ue.prop(r, 'W'), x = ue.prop(r, 'X'), y = ue.prop(r, 'Y'), z = ue.prop(r, 'Z') }
    if not (l and s and num(q.w) and num(q.x) and num(q.y) and num(q.z)) then return nil end
    return { loc = l, quat = q, scale = s }
end
KB.plain_xf = plain_xf
-- A bone's world transform on a skinned component: GetSocketTransform(bone, RTS_World 0) | nil
local function bone_world(mesh, bone)
    if type(bone) ~= 'string' then return nil end
    local ok, t = ue.call(mesh, 'GetSocketTransform', ue.fname(bone), 0)
    return ok and plain_xf(t) or nil
end
-- The class name of an object (GetFullName's first word), 'unread' when none reads
local function class_of(o) return (ue.full(o) or ''):match('^(%S+) ') or 'unread' end

-- ---------- parts (pure) ----------
function KB.maps(b, list, side)
    for _, e in ipairs(list) do if b:sub(1, #e[1]) == e[1] then return e[2] .. '_' .. side end end
    return nil
end
-- The part a struck bone names: a head or neck bone the head, an arm or leg bone its part (ARM, LEG, the side from the
-- suffix); anything else the head. part, src ('struck'; 'torso': a bone naming no part; 'none': no bone, a poll death).
-- KB.first takes only a 'struck' answer and draws a body part for the other two
function KB.part_of(bone)
    local b = type(bone) == 'string' and bone:lower() or ''
    if b == '' or b == 'none' then return 'head', 'none' end
    if b:sub(1, 4) == 'head' or b:sub(1, 4) == 'neck' then return 'head', 'struck' end
    local side = b:match('_([lr])$')
    local p = side and (KB.maps(b, KB.ARM, side) or KB.maps(b, KB.LEG, side)) or nil
    if p then return p, 'struck' end
    return 'head', 'torso'
end
-- A part's family (one cut a family): head, arm_l, arm_r, leg_l, leg_r; nil for no part of the layouts
function KB.family(part)
    if part == 'head' then return 'head' end
    local stem, side = tostring(part):match('^(%a+)_([lr])$')
    if stem == 'upperarm' or stem == 'lowerarm' then return 'arm_' .. side end
    if stem == 'thigh' or stem == 'calf' then return 'leg_' .. side end
    return nil
end
-- The swing plane: kill.bd_dir (the bullet's AttackDirection tag: Top or Bottom vertical, Left or Right horizontal),
-- else the unit sweep (|z| at least PLANE_Z vertical). 'vertical' | 'horizontal' | nil, src ('bd_dir', 'sweep', 'none')
local function plane_of(kill, sweep)
    local t = type(kill.bd_dir) == 'string' and kill.bd_dir:lower() or ''
    if t:find('top', 1, true) or t:find('bottom', 1, true) then return 'vertical', 'bd_dir' end
    if t:find('left', 1, true) or t:find('right', 1, true) then return 'horizontal', 'bd_dir' end
    local s = unit3(sweep)
    if s then return math.abs(s.z) >= KB.PLANE_Z and 'vertical' or 'horizontal', 'sweep' end
    return nil, 'none'
end
-- The band of a BANDS list a bone name starts with (any case) | nil
local function band_in(bone, list)
    if type(bone) ~= 'string' then return nil end
    local b = bone:lower()
    for _, e in ipairs(list) do if b:sub(1, #e[1]) == e[1] then return e[2] end end
    return nil
end
-- The body band of a kill: the fine kill.bone's (chest, belly, hips), else the coarse kill.coarse's (upper, lower),
-- else 'none' (a poll death, no bone, no coarse value)
function KB.band_of(kill)
    kill = type(kill) == 'table' and kill or {}
    return band_in(kill.bone, KB.BANDS.fine) or band_in(kill.coarse, KB.BANDS.coarse) or 'none'
end
-- D3 P2 and P3: a part drawn from the kill's band weights (the head's times VERT_HEAD_K on a vertical plane in the
-- VERT_BANDS) with the kill's own generator, RNG.new(RNG.seed_from('part', tostring(kill.id))): one g:int(1, total)
-- over the fixed-order array, so every route asking about one kill draws the same part. part, src ('band'; 'weighted'
-- in band 'none'), band
function KB.body_pick(kill, plane)
    kill = type(kill) == 'table' and kill or {}
    local band = KB.band_of(kill)
    local list = KB.BODY_W[band] or KB.BODY_W.none
    local hk = (plane == 'vertical' and KB.VERT_BANDS[band]) and KB.VERT_HEAD_K or 1
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] * (e[1] == 'head' and hk or 1) end
    local src = band == 'none' and 'weighted' or 'band'
    if total <= 0 then return 'head', src, band end
    local r, acc = RNG.new(RNG.seed_from('part', tostring(kill.id))):int(1, total), 0
    for _, e in ipairs(list) do
        acc = acc + e[2] * (e[1] == 'head' and hk or 1)
        if r <= acc then return e[1], src, band end
    end
    return list[#list][1], src, band
end
-- The kill's first part, before any rig or limb filter (D3's ladder): P0 a fine head, neck, arm or leg bone names it
-- (part_of, src 'struck'), else P2/P3 body_pick. A finisher is any blow: exec marks it (kill.bullet holds 'Execution').
-- opts: { sweep }. part, src ('struck' | 'band' | 'weighted'), band (nil when struck), plane, plane_src, exec (true | nil)
function KB.first(kill, opts)
    kill, opts = type(kill) == 'table' and kill or {}, type(opts) == 'table' and opts or {}
    local plane, psrc = plane_of(kill, opts.sweep)
    local exec = (type(kill.bullet) == 'string' and kill.bullet:find('Execution', 1, true)) and true or nil
    local part, src = KB.part_of(kill.bone)
    local band = nil
    if src ~= 'struck' then part, src, band = KB.body_pick(kill, plane) end
    return part, src, band, plane, psrc, exec
end
-- x lies inside y on the cached chains (lab_cut's K.resolve entries): the same cut bone, or x's cut bone in y's chain
local function inside(x, y)
    if not (x and y and x.bone and y.bone) then return false end
    if x.bone:lower() == y.bone:lower() then return true end
    for _, b in ipairs(y.chain or {}) do if b:lower() == x.bone:lower() then return true end end
    return false
end
-- The parts of a kill in rank order (research H4 with MC1's filters; D3): KB.first's part (the struck part, else the
-- band's draw), else the head (P4, a technical demotion); then the swing-plane partner (horizontal: the other upper
-- arm, or the other thigh after a leg; vertical: the thigh on the first part's side, or the upper arm on that side
-- after a leg; the side from the first part's suffix, else the bone's, else r), the head, then FIXED. A candidate is
-- kept when its family is free, limbs are allowed (opts.limbs), the rig resolves it (cache.parts[part] has a bone,
-- when a cache is given) and no kept part lies inside it or around it; at most n. opts: { sweep, limbs }. parts
-- { {part, src} } (src: KB.first's, 'fallback', 'plane', 'head', 'fixed'; empty when neither the first part nor the
-- head passes), dropped { {part, why} } (why 'limbs_off', 'same_family', 'no_bone', 'same_chain'), plane, plane_src,
-- pick { first, src, band, plane, plane_src, exec } (KB.first's draw before any filter)
function KB.parts_of(kill, cache, n, opts)
    kill, opts = type(kill) == 'table' and kill or {}, opts or {}
    local cp = type(cache) == 'table' and type(cache.parts) == 'table' and cache.parts or nil
    local first, src, band, plane, psrc, exec = KB.first(kill, opts)
    local pick = { first = first, src = src, band = band, plane = plane, plane_src = psrc, exec = exec }
    local side = first:match('_([lr])$') or (type(kill.bone) == 'string' and kill.bone:lower():match('_([lr])$')) or 'r'
    local other = side == 'l' and 'r' or 'l'
    local leg = (KB.family(first) or ''):sub(1, 3) == 'leg'
    local partner = nil
    if plane == 'horizontal' then partner = leg and ('thigh_' .. other) or ('upperarm_' .. other)
    elseif plane == 'vertical' then partner = leg and ('upperarm_' .. side) or ('thigh_' .. side) end
    local parts, dropped, fam, seen = {}, {}, {}, {}
    local function why_not(p)
        if p ~= 'head' and opts.limbs ~= true then return 'limbs_off' end
        local f = KB.family(p)
        if not f or fam[f] then return 'same_family' end
        local e = cp and cp[p]
        if cp and not (e and e.bone) then return 'no_bone' end
        for _, k in ipairs(parts) do
            local ke = cp and cp[k.part]
            if inside(e, ke) or inside(ke, e) then return 'same_chain' end
        end
        return nil
    end
    n = math.max(1, math.floor(tonumber(n) or 1))
    local function try(p, s)
        if #parts >= n or seen[p] then return end
        seen[p] = true
        local w = why_not(p)
        if w then dropped[#dropped + 1] = { part = p, why = w } return end
        parts[#parts + 1] = { part = p, src = s }
        fam[KB.family(p)] = true
    end
    try(first, src)
    if not parts[1] then try('head', 'fallback') end
    if not parts[1] then return parts, dropped, plane, psrc, pick end
    if partner then try(partner, 'plane') end
    try('head', 'head')
    for _, p in ipairs(KB.FIXED) do try(p, 'fixed') end
    return parts, dropped, plane, psrc, pick
end
-- The parts a kill wants: 1; the heavy_parts knob on a heavy and shaqi_parts on a Sha-Qi kill of the player's
-- (kill.tier, lab_poll; an NPC's kill is normal); at most max_parts (core/config.lua knobs, read at each use)
function KB.nparts(kill)
    kill = type(kill) == 'table' and kill or {}
    local n = 1
    if kill.by_player == true and kill.tier == 'heavy' then n = CFG.knob('heavy_parts') or 1
    elseif kill.by_player == true and kill.tier == 'shaqi' then n = CFG.knob('shaqi_parts') or 1 end
    return math.max(1, math.min(n, CFG.knob('max_parts') or 1))
end

-- ---------- jobs: the primary, the plan, the end (lab_cut's st) ----------
-- The parts queued in the last real second (t: now)
local function rate_n(st, t)
    local keep = {}
    for _, x in ipairs(st.rate) do if t - x < 1 then keep[#keep + 1] = x end end
    st.rate = keep
    return #keep
end
-- A 'heads' row's primary job (lab_cut's on_row: plain values only): rank 1, KB.first's part (the head when limbs is
-- false: META.beta_limbs), at_death; kp: the kill's table its extras share (the first commit, P-e). It counts on the
-- per-second cap and always goes
function KB.primary(job, st, t, limbs)
    local kill = type(job.d.kill) == 'table' and job.d.kill or {}
    local part, src = KB.first(kill, { sweep = job.d.sweep_dir })
    if limbs ~= true then part = 'head' end
    job.at_death, job.rank, job.nparts, job.part, job.bone_src = true, 1, 1, part, src
    job.row, job.tier, job.kp = part == 'head' and 'heads' or 'limbs', kill.tier, {}
    rate_n(st, t)
    st.rate[#st.rate + 1] = t
end
-- The kill's plan, once, at its primary's stage once the bone cache c is read: the primary's final part (KB.first's
-- part, else the head), the extras queued in rank order (the parts_per_s cap and the queue of jobs_max drop the rest:
-- 'rate', 'queue_full'), the forced cut_plan record with KB.first's pick. false when neither the first part nor the
-- head resolves
function KB.plan(job, c, st, t, jobs_max)
    job.planned = true
    local d = job.d
    local kill = type(d.kill) == 'table' and d.kill or {}
    local want = KB.nparts(kill)
    local parts, dropped, plane, psrc, pick = KB.parts_of(kill, c, want, { sweep = d.sweep_dir, limbs = job.limbs })
    local names, extras = {}, {}
    if parts[1] then
        job.part, job.bone_src = parts[1].part, parts[1].src
        job.row = job.part == 'head' and 'heads' or 'limbs'
        names[1] = job.part
    end
    for i = 2, #parts do
        local p, why = parts[i], nil
        if rate_n(st, t) >= (CFG.knob('parts_per_s') or 1) then why = 'rate'
        elseif #st.jobs + #extras >= jobs_max then why = 'queue_full' end
        if why then
            dropped[#dropped + 1] = { part = p.part, why = why }
            st.xdrop = st.xdrop + 1
        else
            st.rate[#st.rate + 1] = t
            st.n = st.n + 1
            extras[#extras + 1] = { d = d, f = S.frame, state = 'row', n = st.n, at_death = true, rank = #names + 1,
                part = p.part, bone_src = p.src, row = p.part == 'head' and 'heads' or 'limbs', tier = job.tier,
                kp = job.kp, planned = true }
            names[#names + 1] = p.part
        end
    end
    job.nparts = #names
    for _, x in ipairs(extras) do
        x.nparts = #names
        st.jobs[#st.jobs + 1] = x
    end
    st.plans, st.extras = st.plans + 1, st.extras + #extras
    KB.plan_rec(job, { want = want, n = #names, parts = names, dropped = dropped, plane = plane, plane_src = psrc,
        first = pick.first, pick = pick.src, band = pick.band, exec = pick.exec,
        why = (not parts[1]) and 'no_bone' or nil })
    return parts[1] ~= nil
end
-- An at_death job ends: a commit resets the breaker's runs; a refusal writes the forced cut_fail with its rank (lab_poll
-- wrote the kill at confirm and holds nothing: no other record names it), counts on the breaker and, for a primary
-- refused before its plan, writes the kill's cut_plan; only the primary sends lab_outcome (it counts as late there)
function KB.finish(job, outcome, why, f, st)
    local d, b = job.d, st.brk
    if outcome == 'committed' then
        b.run = 0
        if job.asset then b.asset[job.asset] = 0 end
    else
        st.refused = st.refused + 1
        LAB.rec('cut_fail', { id = d.id, part = job.part or 'head', pair = d.pair, row = job.row or 'heads',
            rank = job.rank, nparts = job.nparts, err = tostring(why or 'refused'), bone_src = job.bone_src,
            tier = job.tier, class = d.class }, true)
        if KB.counted(why) then KB.strike(b, job, why) end
        if not job.planned and job.rank == 1 then         -- KB.first's pick too, as the plan's record carries it
            local kill = type(d.kill) == 'table' and d.kill or {}
            local p, src, band, plane, psrc, exec = KB.first(kill, { sweep = d.sweep_dir })
            KB.plan_rec(job, { why = tostring(why or 'refused'), first = p, pick = src, band = band, plane = plane,
                plane_src = psrc, exec = exec })
        end
    end
    if job.rank ~= 1 then return end
    f = f or {}
    BUS.emit('lab_outcome', d.id, { row = 'heads', outcome = outcome, why = why, commit_ms = f.commit_ms,
        actions = outcome == 'committed' and 1 or 0, cut_ms = f.cut_ms })
end

-- ---------- the breaker and the plan record ----------
-- A session's breaker: run (counted failures in a row), asset[a] (the same per mesh asset), bad[a] (blacklisted), nbad,
-- off (the beta's cuts stopped)
function KB.breaker() return { run = 0, asset = {}, bad = {}, nbad = 0, off = false } end
function KB.counted(why)
    return KB.COUNTED[why] == true or (type(why) == 'string' and why:sub(1, 12) == 'commit_fail:')
end
-- One counted failure of an at_death job (job.asset: its mesh asset): the run overall and on the asset; BAD_ASSET_N on
-- one asset blacklists it, BETA_OFF_N overall stops the beta's cuts for the session (each a forced record, once)
function KB.strike(b, job, why)
    local a = job.asset
    b.run = b.run + 1
    if a then
        b.asset[a] = (b.asset[a] or 0) + 1
        if b.asset[a] >= KB.BAD_ASSET_N and not b.bad[a] then
            b.bad[a], b.nbad = true, b.nbad + 1
            LAB.rec('bad_asset', { asset = a, class = job.d.class, id = job.d.id, n = b.asset[a], why = tostring(why) },
                true)
        end
    end
    if b.run >= KB.BETA_OFF_N and not b.off then
        b.off = true
        LAB.rec('beta_off', { n = b.run, why = tostring(why), id = job.d.id, asset = a, bad = b.nbad }, true)
    end
end
-- The kill's cut_plan record (forced, once per kill: at the plan, else at its primary's refusal before one). f: want,
-- n, parts (names in rank order), dropped, plane, plane_src, first (KB.first's part, before any filter), pick (its src
-- word), band, exec, why. The plan's record carries the pick, so an analyzer recomputes every draw from band, plane and
-- the kill id even when a technical demotion moved parts[1]
function KB.plan_rec(job, f)
    local d = job.d
    local kill = type(d.kill) == 'table' and d.kill or {}
    LAB.rec('cut_plan', { id = d.id, class = d.class, pair = d.pair, tier = kill.tier or 'unread',
        tier_src = kill.tier_src, by_player = kill.by_player, bone = kill.bone, want = f.want or KB.nparts(kill),
        n = f.n or 0, parts = f.parts or {}, dropped = f.dropped or {}, plane = f.plane or 'none',
        plane_src = f.plane_src or 'none', first = f.first, pick = f.pick, band = f.band, exec = f.exec,
        why = f.why }, true)
end

-- ---------- stage reads (inside lab_cut's 'lab.cut.stage') ----------
-- MC5: the keep levers, property reads (never written): every data/cut_classes.lua class is a BP_RenewalNPC_C, so a
-- BP_NPC_Base_C too (the declaring classes; no ue.is_a, a class lookup in the stage frame). kept (true:
-- DisableDeathDissol true or DestroyAfterDead false, a LingeringDead body; false: the vanilla values; 'unread': either
-- one unread, treated as vanilla), levers { disable_dissol, death_delay, destroy_after, destroy_delay } (each the value
-- of its type or 'unread')
function KB.levers(actor)
    local lv = {}
    for _, l in ipairs(KB.LEVERS) do
        local v = ue.prop(actor, l.prop)
        if type(v) == l.t then lv[l.key] = v else lv[l.key] = 'unread' end    -- (and/or would turn false unread)
    end
    local kept = lv.disable_dissol == true or lv.destroy_after == false
    if not kept and (lv.disable_dissol == 'unread' or lv.destroy_after == 'unread') then kept = 'unread' end
    return kept, lv
end
-- A3: the hide set of a head cut, by name among the actor's SceneComponents (list: one K2_GetComponentsByClass): the
-- row's head names (else names, the layout's head_comps) required, its hair, hat_mask and glow names optional. Entries
-- { comp, name, kind ('head', 'hair', 'hat_mask', 'glow'), opt, cloth (a hair_cloth name), fall (a row.fall name),
-- class, rec (ue.keep_mod) } | nil, why ('no_head_comp:<name>'); missing: the optional names not found (opt_missing)
function KB.hide_set(list, row, names)
    row = type(row) == 'table' and row or {}
    local function set(l) local s = {} for _, n in ipairs(type(l) == 'table' and l or {}) do s[n] = true end return s end
    local cloth, fall, by = set(row.hair_cloth), set(row.fall), {}
    for _, c in ipairs(list or {}) do
        local n = ue.name(c)
        if n and by[n] == nil then by[n] = c end
    end
    local out, missing, seen = {}, {}, {}
    local groups = { { 'head', type(row.head) == 'table' and row.head[1] and row.head or names, false },
        { 'hair', row.hair, true }, { 'hat_mask', row.hat_mask, true }, { 'glow', row.glow, true } }
    for _, g in ipairs(groups) do
        for _, n in ipairs(type(g[2]) == 'table' and g[2] or {}) do
            if not seen[n] then
                seen[n] = true
                local c = by[n]
                local rec = c and ue.keep_mod(c)
                if rec then
                    out[#out + 1] = { comp = c, name = n, kind = g[1], opt = g[3] or nil, cloth = cloth[n] or nil,
                        fall = fall[n] or nil, class = class_of(c), rec = rec }
                elseif not g[3] then return nil, 'no_head_comp:' .. n, missing
                else missing[#missing + 1] = n end
            end
        end
    end
    return out, nil, missing
end
-- The bone a socket of a leader resolves to (GetSocketBoneName) lies at the cut bone or below it (GetParentBone up at
-- most CHAIN_MAX links), cached in sub per mesh asset, leader, bone and cut bone. inside, bone
local function in_subtree(cut, par, sock, sub)
    local okb, b = ue.call(par, 'GetSocketBoneName', ue.fname(sock))
    local bone = okb and ue.str(b) or nil
    if not bone or bone == '' or bone == 'None' then return false, nil end
    local lb = cut.bone:lower()
    local key = tostring(cut.asset) .. '|' .. tostring(ue.name(par)) .. '|' .. bone:lower() .. '|' .. lb
    if sub[key] == nil then
        local cur, inn = bone, false
        for _ = 1, KB.CHAIN_MAX + 1 do
            if cur:lower() == lb then inn = true break end
            cur = L.bone_parent(par, cur)
            if not cur then break end
        end
        sub[key] = inn
    end
    return sub[key], bone
end
-- A3's safety net (META.beta_scan): the SceneComponents of list attached into the cut subtree, not listed and not ours
-- (NOT_SCAN). One counts when its parent (GetAttachParent, one read each) is a leader with the cut bone and its
-- AttachSocketName resolves into the subtree (in_subtree), or, at any depth up to CHAIN_MAX, a component of the hide
-- set or another hit (any socket: SetHiddenInGame does not reach a child). Each hit joins cut.head (kind 'scan', opt)
-- and cut.extra_hidden { name, class, socket, bone } (ok set at the commit). The hits
function KB.scan(cut, list, leaders, sub)
    local skip, inside = {}, {}
    for _, m in ipairs(leaders or {}) do local a = ue.addr(m) if a then skip[a] = 'leader' end end
    for _, h in ipairs(cut.head or {}) do local a = ue.addr(h.comp) if a then skip[a], inside[a] = 'listed', true end end
    local cand = {}
    for _, c in ipairs(list or {}) do
        local a = ue.addr(c)
        if a and not skip[a] then
            local okp, par = ue.call(c, 'GetAttachParent')
            local pa = okp and ue.valid(par) and ue.addr(par) or nil
            if pa then cand[#cand + 1] = { c = c, a = a, pa = pa, par = par } end
        end
    end
    for _, e in ipairs(cand) do                         -- on a leader's socket inside the subtree
        if skip[e.pa] == 'leader' then
            local oks, s = ue.call(e.c, 'GetAttachSocketName')
            e.sock = oks and ue.str(s) or nil
            if e.sock and e.sock ~= '' and e.sock ~= 'None' then
                e.hit, e.bone = in_subtree(cut, e.par, e.sock, sub)
                if e.hit then inside[e.a] = true end
            end
        end
    end
    for _ = 1, KB.CHAIN_MAX do                          -- then under the hide set or a hit, a level a pass
        local more = false
        for _, e in ipairs(cand) do
            if not e.hit and inside[e.pa] then e.hit, inside[e.a], more = true, true, true end
        end
        if not more then break end
    end
    cut.extra_hidden = cut.extra_hidden or {}
    local hits = 0
    for _, e in ipairs(cand) do
        local cls = e.hit and class_of(e.c) or nil
        local rec = cls and not KB.NOT_SCAN[cls] and ue.keep_mod(e.c) or nil
        if rec then
            local n = ue.name(e.c)
            cut.head[#cut.head + 1] = { comp = e.c, name = n, kind = 'scan', opt = true, class = cls, rec = rec,
                socket = e.sock }
            cut.extra_hidden[#cut.extra_hidden + 1] = { name = n, class = cls, socket = e.sock, bone = e.bone }
            hits = hits + 1
        end
    end
    return hits
end
-- C4 (pure): the cap radius in cm of a sizing part (data/caps_beta_sizing.lua: head, upperarm, lowerarm, thigh, calf)
-- from L1 (the cut joint to its child) and S (the shoulder span): clamp(clamp(k1 L1, band x k2 S), rmin, rmax), the
-- head k2 S first in the band of neck_k L1; before cap_scale. r, the bound that set it ('k1', 'k2', 'band_lo',
-- 'band_hi', 'rmin', 'rmax') | nil
function KB.size_r(stem, L1, Sp)
    local SZ = data('data.caps_beta_sizing')
    local z, band = (SZ.parts or {})[stem], SZ.band or { 0.85, 1.2 }
    if type(z) ~= 'table' or not (num(L1) and num(Sp)) then return nil end
    local r, mid, word = nil, z.k2 * Sp, 'k1'            -- mid: the band's centre
    if z.k1 == nil then r, mid, word = mid, z.neck_k * L1, 'k2' else r = z.k1 * L1 end
    if r < band[1] * mid then r, word = band[1] * mid, 'band_lo'
    elseif r > band[2] * mid then r, word = band[2] * mid, 'band_hi' end
    if r < z.rmin then r, word = z.rmin, 'rmin' elseif r > z.rmax then r, word = z.rmax, 'rmax' end
    return r, word
end
-- The roll about the Cap's own +Z (composed after z_to(d): q = z_to(d) x roll) that puts its +X on the actor's forward
-- projected onto the cut plane, in the stump bone's frame (sq: its world rotation); the bone's own X (else Y) when the
-- forward is unread or within ROLL_COS of d. roll {w, x, y, z}, src ('forward' | 'bone_axis'), |cos|, the angle in
-- degrees | nil
local function roll_of(d, q0, f, sq)
    local fl = (f and sq) and L.rotate({ w = sq.w, x = -sq.x, y = -sq.y, z = -sq.z }, f) or nil
    local c = fl and unit3(fl) and math.abs(dot(unit3(fl), d)) or nil
    local src = 'forward'
    if not c or c > KB.ROLL_COS then
        fl, src = { x = 1, y = 0, z = 0 }, 'bone_axis'
        if math.abs(dot(fl, d)) > KB.ROLL_COS then fl = { x = 0, y = 1, z = 0 } end
    end
    local k = dot(fl, d)
    local p = unit3({ x = fl.x - k * d.x, y = fl.y - k * d.y, z = fl.z - k * d.z })
    if not p then return nil end
    local x0 = L.rotate(q0, { x = 1, y = 0, z = 0 })
    local th = math.atan(dot(d, cross(x0, p)), dot(x0, p))
    return { w = math.cos(th / 2), x = 0.0, y = 0.0, z = math.sin(th / 2) }, src, c, math.deg(th)
end
-- C4 reads: the world joint, child, stump and the two upper arms on the body leader (GetSocketTransform world), the
-- actor's forward (GetActorForwardVector). cut.size = { cap, L1, S, R (times cap_scale), clamp, scale (R / r_ref), roll,
-- roll_src, cos, src 'read' } (lab_look.lua's header), or { cap, scale = bucket (the layout's D8 bucket), src 'bucket',
-- why } when a read failed; cut.stage_joint {x, y, z}, cut.stage_t { real, game, frame } (MC4: the joint at the stage,
-- lab_piece's body motion), cut.d_world the unit joint -> child. span: { upperarm_l, upperarm_r } bone names; z_to:
-- lab_cap's C.z_to
function KB.size(cut, span, bucket, z_to, t)
    local stem = cut.part == 'head' and 'head' or tostring(cut.part):match('^(%a+)_[lr]$')
    local z = (data('data.caps_beta_sizing').parts or {})[stem or '']
    local j, c = bone_world(cut.leader, cut.bone), bone_world(cut.leader, cut.child)
    cut.stage_t = { real = t, game = S.game_time, frame = S.frame }
    if j then cut.stage_joint = j.loc end
    if j and c then cut.d_world = unit3({ x = c.loc.x - j.loc.x, y = c.loc.y - j.loc.y, z = c.loc.z - j.loc.z }) end
    local ul, ur = bone_world(cut.leader, span and span[1]), bone_world(cut.leader, span and span[2])
    local size = { cap = z and z.cap, scale = bucket, src = 'bucket' }
    if not (z and j and c and ul and ur) then
        size.why = not z and 'no_part' or (not (j and c)) and 'joint' or 'span'
        cut.size = size
        return size
    end
    local L1, Sp = dist(j.loc, c.loc), dist(ul.loc, ur.loc)
    local r, word = KB.size_r(stem, L1, Sp)
    if not r then size.why = 'size' cut.size = size return size end
    local R = r * (CFG.knob('cap_scale') or 1.0)
    size = { cap = z.cap, L1 = L1, S = Sp, R = R, clamp = word, scale = R / (data('data.caps_beta_sizing').r_ref or 5),
        src = 'read' }
    local d, q0 = unit3(cut.d), type(z_to) == 'function' and z_to(cut.d) or nil
    local s = bone_world(cut.leader, cut.stump)
    if d and q0 then
        local okf, fv = ue.call(cut.actor, 'GetActorForwardVector')
        size.roll, size.roll_src, size.cos, size.roll_deg = roll_of(d, q0, okf and vec3(fv) or nil,
            s and s.quat or nil)
    end
    cut.size = size
    return size
end
-- MC4, the stage half (at death only; the lab's 120 s limb path keeps its rule): cut.dir = unit(sweep + OUT_K x d) (d:
-- lab_piece's world d of the Piece, else cut.d_world), else the attack direction with d, else d; HEAD_V or LIMB_V; UP_V
function KB.launch(cut, dw)
    local s, d = unit3(cut.sweep_dir) or unit3(cut.attack_dir), unit3(dw)
    local v = d
    if s and d then v = unit3({ x = s.x + KB.OUT_K * d.x, y = s.y + KB.OUT_K * d.y, z = s.z + KB.OUT_K * d.z }) or s
    elseif s then v = s end
    cut.dir, cut.speed, cut.up = v, cut.part == 'head' and KB.HEAD_V or KB.LIMB_V, KB.UP_V
end

-- ---------- heads: the mode (lab_gib), the commit's reads, the gib table ----------
-- The head of an at_death head job (lab_gib.lua's sequence): G.head_mode(row); hair 'keep' that lab_gib cannot keep
-- now bursts; a burst lab_gib cannot run is refused 'gib_off'; with no lab_gib, a row with cloth hair or head_mode
-- 'burst' is refused 'gib_off' and any other flies as 'piece', 'none'. mode, hair | nil, 'gib_off'
function KB.head_mode(row, G)
    if not (type(G) == 'table' and type(G.head_mode) == 'function' and type(G.ready) == 'function') then
        local r = type(row) == 'table' and row or {}
        if (type(r.hair_cloth) == 'table' and r.hair_cloth[1] ~= nil) or r.head_mode == 'burst' then
            return nil, 'gib_off'
        end
        return 'piece', 'none'
    end
    local mode, hair = G.head_mode(row)
    if hair == 'keep' and not G.ready('keep') then mode, hair = 'burst', 'hidden' end
    if mode == 'burst' and not G.ready('burst') then return nil, 'gib_off' end
    return mode, hair
end
-- Inside the commit, before the hide (property reads, after the optimizer went off): for each component of cut.head,
-- h.pre (L.comp_hidden: true when it was not drawn, a variant the class leaves hidden: hidden again, never a falling
-- copy) and h.pre_h (its own bHiddenInGame: the unwind and the restore put that back, never showing such a variant)
function KB.pre_reads(cut)
    for _, h in ipairs(cut.head or {}) do
        local hid, raw = L.comp_hidden(h.comp)
        h.pre, h.pre_h = hid, raw
    end
end
-- Inside the head commit, before the hide (lab_gib's world transforms): cut.gib_at (the child bone) and cut.gib_joint
-- (the cut joint), each a world location; h.xf for each hat, mask, glow, scan hit and cloth hair of cut.head
-- (K2_GetComponentToWorld; nil when the read failed)
function KB.gib_reads(cut)
    local j, c = bone_world(cut.leader, cut.bone), bone_world(cut.leader, cut.child)
    cut.gib_joint, cut.gib_at = j and j.loc or nil, c and c.loc or nil
    for _, h in ipairs(cut.head or {}) do
        if KB.GIB_KIND[h.kind] or h.cloth then
            local ok, t = ue.call(h.comp, 'K2_GetComponentToWorld')
            h.xf = ok and plain_xf(t) or nil
        end
    end
end
-- After the hide: cut.head keeps what hid (an optional or scan component that would not hide is left out: lab_hold,
-- the re-assert and the restore never see it), cut.hide_set the names hidden, cut.hide_fail the optional names that
-- did not, cut.pre_hidden the names not drawn before the hide, cut.extra_hidden[i].ok
function KB.settle(cut)
    local keep, set, fail, pre, ok = {}, {}, {}, {}, {}
    for _, h in ipairs(cut.head or {}) do
        if h.hidden then keep[#keep + 1], set[#set + 1] = h, h.name else fail[#fail + 1] = h.name end
        if h.pre == true then pre[#pre + 1] = h.name end
        if h.kind == 'scan' then ok[h.name] = h.hidden == true end
    end
    for _, e in ipairs(cut.extra_hidden or {}) do e.ok = ok[e.name] == true end
    cut.head, cut.hide_set, cut.hide_fail, cut.pre_hidden = keep, set, fail[1] and fail or nil, pre[1] and pre or nil
end
-- 'static' | 'skinned' | 'other' by class name (a StaticMeshComponent; a skeletal, skinned or poseable one; anything
-- else, a Chaos cloth one too: lab_gib copies cloth only as kept hair)
local function gib_class(cls)
    cls = tostring(cls)
    if cls:find('StaticMesh', 1, true) then return 'static' end
    if cls:find('ChaosCloth', 1, true) then return 'other' end
    if cls:find('Skeletal', 1, true) or cls:find('Skinned', 1, true) or cls:find('Poseable', 1, true) then
        return 'skinned'
    end
    return 'other'
end
KB.gib_class = gib_class
-- cut.gib of a committed head cut (lab_gib.lua's header): at, joint, vel (piece.vel when a Piece flew, else
-- P.velocity(cut)), vel_src, extras { name, rec, class, src, fall, xf, pre_hidden } (every hat, mask, glow and scan
-- hit hidden; fall for a row.fall name and a static scan hit that was drawn before the hide), hair { name, rec, xf }
-- (the cloth hair hidden)
function KB.gib(cut, P)
    local vel, src = nil, 'none'
    if cut.piece and type(cut.piece.vel) == 'table' then vel, src = cut.piece.vel, cut.piece.vel_src
    elseif P and type(P.velocity) == 'function' then vel, src = P.velocity(cut) end
    local g = { at = cut.gib_at, joint = cut.gib_joint, vel = vec3(vel), vel_src = src, extras = {}, hair = {} }
    for _, h in ipairs(cut.head or {}) do
        if h.cloth then g.hair[#g.hair + 1] = { name = h.name, rec = h.rec, xf = h.xf }
        elseif KB.GIB_KIND[h.kind] then
            local cls = gib_class(h.class)
            g.extras[#g.extras + 1] = { name = h.name, rec = h.rec, class = cls,
                src = h.kind == 'scan' and 'scan' or 'row', pre_hidden = h.pre == true or nil,
                fall = h.pre ~= true and (h.fall == true or (h.kind == 'scan' and cls == 'static')), xf = h.xf }
        end
    end
    return g
end
-- The beta's fields of the cut record (nil on a lab cut): the plan, the levers, P-e, A3's sets, C4's size and roll
-- inputs (rounded), the head mode, the Caps' booked bytes and the session's route_kb (TA)
function KB.rec(cut)
    if not cut.at_death then return {} end
    local z, slot = cut.size or {}, cut.slot or {}
    return { rank = cut.rank, nparts = cut.nparts, tier = cut.tier, class = cut.class, kept = cut.kept,
        levers = cut.levers, after_f = cut.after_f, after_ms = cut.after_ms, hide_set = cut.hide_set,
        opt_missing = cut.opt_missing, hide_fail = cut.hide_fail, pre_hidden = cut.pre_hidden,
        extra_hidden = cut.extra_hidden,
        size = { cap = z.cap, L1 = r2(z.L1), S = r2(z.S), R = r2(z.R), clamp = z.clamp, scale = r2(z.scale),
            src = z.src, why = z.why, roll_src = z.roll_src, cos = r2(z.cos), roll_deg = r2(z.roll_deg) },
        head_mode = cut.head_mode, hair = cut.hair, hold_show = cut.hold_show,
        stump_bytes = slot.stump and slot.stump.bytes, piece_bytes = slot.piece and slot.piece.bytes,
        route_kb = TA.status().route_kb }
end

return KB
