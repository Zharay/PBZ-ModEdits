-- status: new for the beta (offline only; the author's run decides) origin: docs/research/beta-dismemberment-plan.md (group G, lab_gib: the author's answers 6, 7 and 10 of 2026-10-31)
-- lab_gib.lua: what a cut head leaves besides the flying Piece. The author's answers of 2026-10-31: 6 «it must
-- not be bald: either find a way to keep the original head or let the head burst into pieces (skull, meat and
-- so on)», 7 «fall» (hats and masks fall off as their own physics objects), 10 «together with the body». Player beta only
-- (META.beta_modules, after lab_cut, before lab_fade); the probe and dev profiles never require it, and init stays
-- inert (no listener, no ticker, no record) unless LAB.beta() and META.beta_gib. G.head_mode is pure and answers
-- whether init ran or not.
-- Design, from the evidence:
-- * Hats and masks (7). The 154 ordinary classes list masks only, no hat (data/hide_table.lua; scratch/all-enemies
--   buckets.md B7: 'Mask' on Gold, Iron and JadeMaskMan and the Tutorial, 'FeiZei_Mask' on the four FeiZei); a static
--   hat can still come from lab_cut's subtree scan. Their component class is [unknown]: no monster Blueprint is in the
--   26266538 ObjectDump, and the census says the GoldMaskMan mask has its own skeleton and physics asset
--   (docs/research/census.md:16 'mask flies'), so a skeletal mask is the expected case. Two copy routes, each made of
--   proven call classes: 'static' (a StaticMeshComponent with the source's StaticMesh and slot materials: cap.meat's
--   SetStaticMesh, piece.mesh's slot copy) and 'skinned' (a PoseableMeshComponent with the source's SkeletalMesh and
--   slot materials, its pose copied from the mask when it leads, else from its leader when the skeletons match:
--   piece.mesh and piece.pose through L.copy_pose's guard), placed at the world transform lab_cut read before the
--   hide, on its own Box carrier with the Piece's trace-neutral physics (piece.spawn, piece.phys) and a share of the
--   head's launch. Anything else ('other': Niagara, a cloth or non-SkeletalMesh asset, a follower whose leader is on
--   another skeleton) stays hidden and is logged.
-- * Cloth hair (6). CA_*Hair* are ChaosClothComponent leader-pose followers (rc records; CXXHeaderDump
--   BP_Renewal_Hun.hpp:19), on 12 elite classes. Keeping the hair needs a ChaosClothComponent made at runtime with
--   SetAsset and SetLeaderPoseComponent onto the head poseable: never run in PBZ (research A6: medium-high), and on a
--   body-copy head the isolation collapses every bone outside the cut subtree, so strands weighted to the neck or the
--   back stretch to the stump [inferred]; moving the corpse's own component to another actor is unproven (MC11) and it
--   dies with the corpse. The burst uses proven call classes only: a deferred Actor spawn with a Box root
--   (piece.spawn, runs 4-11), a StaticMeshComponent with SetStaticMesh and a BasicShapeMaterial MID (cap.meat,
--   cap.mid), trace-neutral physics and a velocity change (piece.phys), NS_BloodHeadBreak_001 through
--   SpawnSystemAtLocation (lab_blood's spray on every head cut of runs 9-11), LoadAsset (blood.load). So the default
--   stays 'burst' (core/config.lua hair_mode, BD0); 'keep' is built here behind that knob (about 70 lines) and bursts
--   on any failure: a head never flies bald.
-- * Assets (G.ASSETS; ObjectDump 26266538): NS_BloodHeadBreak_001 (sprite and decal renderers, no mesh: research route
--   c), SM_Skull_Old_01 with its MI_Skull_Old_01 (a lit static prop; the mesh carries a PBZCensorVariantUserData),
--   SM_FX_Flesh_001-003 (loaded in the dump) and _004 (the package oracle only). The flesh meshes' own slot is
--   probably the placeholder FX_SM_Common/WorldGridMaterial [inferred], so a chunk always takes our material. Their
--   sizes are [unknown]: StaticMesh:GetBounds (a struct return that never ran live) is read once a session per loaded
--   mesh, inside the first burst's 'gib.mesh' call after its objects (gib_bounds), never in a warm-up or at the main
--   menu (review round 2); a mesh whose bounds are not read yet or do not read is never used (the engine Sphere, 50
--   cm, takes a chunk's place; no skull), so the session's first burst throws Spheres.
-- The contract with lab_cut (BD0, pinned):
-- * G.head_mode(row): a data/cut_classes.lua row listing cloth hair (hair_cloth) takes the hair_mode knob: 'keep'
--   flies the head as a Piece with its hair put back on here, 'burst' blows it apart; another row bursts when its
--   head_mode is 'burst', else flies whole (hair inside the mesh rides on the copy).
-- * lab_cut (BD10), for a head job: mode, hair = G.head_mode(d.class_row), kept as job.head_mode and job.hair; in the
--   stage: hair 'keep' and not G.ready('keep') -> 'burst', 'hidden' (never a bald head); head_mode 'burst' and not
--   G.ready('burst') -> the head is refused 'gib_off' (a forced cut_fail, never counted by the breaker; with no lab_gib
--   loaded, a row with hair_cloth or head_mode 'burst' is refused so too, and any other row flies as 'piece', 'none').
--   A 'burst' head builds no flying-head Piece (cut.piece_why 'burst'; lab_cap may skip the Piece end's reserve, the
--   Stump Cap stays). hair 'keep' sets cut.hold_show: lab_piece commits the Piece hidden (its 'show' step skipped,
--   piece.held true, left out of P.live) and this module shows it with P.show(piece) once the hair is on, inside its
--   own armed call. A head hides its bone, head, hair, hat_mask and glow components and the scan hits as any head (the
--   cloth hair and the hats included: the originals stay hidden on the body).
-- * cut.gib, set by lab_cut on a committed head cut, read here on bus lab_cut_live(cut) (limb cuts carry none): at =
--   {x, y, z} the head bone's (cut.child) world location at the commit; joint = {x, y, z} the cut joint's; vel =
--   {x, y, z} uu/s the head's launch velocity (piece.vel when a Piece flew, else P.velocity(cut)) and vel_src; extras
--   = { { name, rec, class, src, fall, xf } } every hat, mask, glow and scan hit hidden at the commit: rec a
--   ue.keep_mod record, class 'static' | 'skinned' | 'other', src 'row' | 'scan', fall true for a row.fall name and
--   for a 'static' scan hit, xf = { loc, quat, scale } its world transform read in the commit before the hide (nil
--   when the read failed); hair = { { name, rec, xf } } the row.hair_cloth components hidden at the commit.
--   cut.head_mode, cut.hair ('none' | 'hidden' | 'keep') and cut.hold_show sit beside it.
-- Mechanics:
-- * Nothing before LAB.pinned() reads true, nothing while paused, off or under the vanilla compare, nothing in a busy
--   frame (a lab_death or a lab_cut_live seen this frame): the first step of a cut is in a later frame than its commit,
--   never in the kill frame. Every UFunction call and world write runs inside LAB.armed with the literal name, after
--   its sig (LAB.sig, resolved here once per session for G.NAMES, one call a frame), SENT.is_disabled and the stop rule
--   (usable()); only lookups (StaticFindObject) and property and identity reads run outside one.
-- * Warm (after each map load, one step a frame): the engine lookups at once (StaticFindObject only: the Sphere,
--   BasicShapeMaterial, the component classes; G.ready reads them). The rest waits for a lab_death of a
--   data/cut_classes.lua class on this map (a gameplay world: nothing loads or spawns at the main menu or at a map
--   load; review round 2), then runs only in frames where lab_cut has no job (K.status().jobs: never between a kill
--   and its commit): LoadAsset of each G.ASSETS path under 'gib.load' (a one-shot frame), then the keeper, one hidden
--   Actor of ours ('gib.spawn') holding each loaded static mesh on a hidden, collision-free StaticMeshComponent (the
--   skull's with MI_Skull_Old_01; 'gib.mesh'), so the GC leaves them for the map (Lua references root nothing,
--   refuted.md:89); one forced gib_assets record. A burst before then uses what it has (the engine Sphere at least).
-- * Jobs: bus lab_cut_live(cut) of a head cut with cut.gib queues one (at most JOBS). One job step a frame: the kept
--   hair (one 'hair.keep' call), then the objects, at most PER_FRAME a frame: the head-break FX ('gib.fx'), the skull
--   and the meat chunks in three batch calls ('gib.spawn' carriers, 'gib.mesh' meshes and materials, 'gib.phys'
--   physics, launch and show), the falls in one batch call ('extra.fall', each whole). A batch call runs each object in
--   its own pcall, so one failure drops one object. A job not started STALE_S game seconds after its commit, or whose
--   cut went or revived, ends with that why (a held Piece is destroyed).
-- * The burst: gib_count objects (the skull first when held with its bounds, then SM_FX_Flesh chunks of MEAT_R cm, an
--   engine Sphere when no flesh mesh reads) from cut.gib.at with BURST_SHARE of the head's launch, a spread and a spin
--   from the cut's own generator (core/rng.lua); a chunk takes LOOK.material('meat', 'piece') when it answers, else the
--   flat meat MID (data/caps_beta_sizing.lua colors.meat on BasicShapeMaterial); the skull keeps MI_Skull_Old_01.
-- * The kept hair: on the held Piece one ChaosClothComponent per cut.gib.hair entry (simulation off, the source's asset
--   and slot materials, led by the head poseable and snapped onto it), then P.show(piece). Any failure:
--   P.destroy(piece, 'hair_fail') in the same call and a burst where the Piece was.
-- * Breakers per kind ('burst', 'keep', 'fall', 'fx'): FAIL_MAX failures in a row stop that kind for the session (a
--   forced gib_off); G.ready then answers false, so lab_cut refuses a burst head 'gib_off' and bursts a kept-hair head.
--   A refused guard, a missing asset, the object cap or a mask whose source cannot copy (no mesh, no transform,
--   another skeleton: refused before anything spawns) is no failure. Never lab_cut's breaker.
-- * Lifetime (10): every object is listed from its spawn. On lab_cut_gone with gone_why 'destroyed' or 'collected'
--   and cut.kept not true (or cut.expired true: lab_corpse let that kept body go), the cut's objects go
--   piece_linger_s (the knob) later; a revive keeps them; a kept body keeps
--   OBJ_MAX (FIFO) and LIFE_S. One destroy a frame under 'gib.destroy' (a failed object first), never while off. At
--   most OBJ_HARD objects live: a new one past that is skipped ('cap').
-- * A sliced head (the game's own slicer, lab_slice_route; docs/research/slicer-stumps.md): its hats and masks fall off
--   as a cut head's do. The route reads and hides them (its 'slicer.drop') and sends bus lab_slice_fall { key, id,
--   class, part, at (the head half's head bone), vel (the head's launch), extras (as cut.gib.extras: name, rec, class
--   'static' | 'skinned' | 'other', src 'row', fall true, xf) }; one falls-only job takes it (no burst, no hair: its cut
--   is a plain table with slice and kept true). Its falls run under their own 'slicer.fall' (META.lab_risky, inherited,
--   10 s, extra.fall's class row; a skinned mask the slicer re-led to a half copies its pose from that half, so a
--   fault there never strikes extra.fall) and breaker kind 'slice_fall'; G.ready('slice_fall') is the route's question
--   (the extras_fall knob, the classes, the name, the breaker). Bus lab_slice_gone (lab_corpse: that sliced corpse
--   went) ends such a job and sends its objects piece_linger_s later, as lab_cut_gone does a cut's. Never a burst or a
--   kept hair on a slice (cloth-hair rows never reach the slicer).
-- * Mod-off: MODOFF.feature 'lab_gib' (gameplay: the vanilla compare blocks it too), its live list the shown actors
--   (kind 'actor'). Records: one forced 'gib' per head cut { id, class, mode, hair, extras, falls, chunks, skull, fx,
--   skip, kept_hair, why, frames }; a forced 'gib_fail' per failed object or step { id, kind, step, why, name };
--   gib_assets; gib_bounds { id, radius } (a burst that asked a mesh's bounds); gib_off. Counters (published at 0):
--   G.COUNTERS.
-- API, pinned: head_mode(row) -> mode ('piece' | 'burst'), hair ('none' | 'hidden' | 'keep'), why; ready(mode) -> bool,
--   why for mode 'burst', 'keep', 'fall' or 'slice_fall' (init, the switch, pinned, on, the mode's names usable, its breaker, its
--   classes and assets found; table reads only, safe inside lab_cut's armed stage); live() the shown gib actors
--   (mod-off); lifecycle init(A) warm() reset(reason) shutdown() status().
-- What the mock cannot prove: native faults, UE4SS marshalling on dff435dd (the GetBounds struct return, the cloth
--   calls), the real component class of a mask, real physics and landing, the burst's look and sizes, whether a
--   runtime ChaosClothComponent renders led by a poseable.
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local RNG = require('core.rng')
local C = require('core.config')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local US = require('adapter.ue_spawn')
local LAB = require('lab_probe')

local G = { PER_FRAME = 4, JOBS = 16, OBJ_MAX = 40, OBJ_HARD = 56, LIFE_S = 1080, STALE_S = 1.0, FAIL_MAX = 3,
    SIG_RETRY_S = 10, VEL_CAP = 700, MAT_MAX = 8, SKIP_MAX = 8, DESTROY_TRIES = 3,
    -- the burst [P]: the share of the head's launch, the spread and lift (uu/s), the spin (deg/s), sizes (cm), mass
    BURST_SHARE = 0.3, BURST_UP = 120, SPREAD = { 180, 380 }, SPIN = { 180, 720 }, MEAT_R = { 2.5, 4.5 },
    SKULL_R = 9, SKULL_SHARE = 0.5, SKULL_SPREAD = { 60, 140 }, SKULL_UP = 150, JITTER_CM = 5,
    CHUNK_HALF = { 2, 6 }, SKULL_HALF = 6, CHUNK_KG = 0.4, SKULL_KG = 1.2,
    -- a fall [P]
    FALL_SHARE = 0.5, FALL_UP = 120, FALL_SPREAD = { 30, 90 }, FALL_SPIN = { 60, 240 }, FALL_HALF = 8, FALL_KG = 0.8,
    SPHERE_R = 50, R_MIN = 0.5, R_MAX = 500,                 -- the engine Sphere's half extent; a bounds read's range
    ACTOR = '/Script/Engine.Actor', BOX = '/Script/Engine.BoxComponent', SMC = '/Script/Engine.StaticMeshComponent',
    POSEABLE = '/Script/Engine.PoseableMeshComponent', CLOTH = '/Script/ChaosClothAssetEngine.ChaosClothComponent',
    SKELETAL_MESH = '/Script/Engine.SkeletalMesh', SPHERE = '/Engine/BasicShapes/Sphere.Sphere',
    MAT = '/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial',
    MEAT = { R = 0.3, G = 0.04, B = 0.028 } }                -- data/caps_beta_sizing.lua colors.meat when unread
-- The assets of a burst head (object paths of UE4SS_ObjectDump 26266538; SM_FX_Flesh_004 only by the chunk-id oracle)
G.ASSETS = {
    fx = '/PBZVFXPack/VFX/BattleFX/Common/Blood_V2/NS_BloodHeadBreak_001.NS_BloodHeadBreak_001',
    skull = '/Game/PBZContent/Environments/Props/Bones/Mesh/SM_Skull_Old_01.SM_Skull_Old_01',
    skull_mat = '/Game/PBZContent/Environments/Props/Bones/Material/MI_Skull_Old_01.MI_Skull_Old_01',
    flesh = { '/PBZVFXPack/VFX/A_Meshes/FX_SM_Common/SM_FX_Flesh_001.SM_FX_Flesh_001',
        '/PBZVFXPack/VFX/A_Meshes/FX_SM_Common/SM_FX_Flesh_002.SM_FX_Flesh_002',
        '/PBZVFXPack/VFX/A_Meshes/FX_SM_Common/SM_FX_Flesh_003.SM_FX_Flesh_003',
        '/PBZVFXPack/VFX/A_Meshes/FX_SM_Common/SM_FX_Flesh_004.SM_FX_Flesh_004' },
}
-- The loads in warm order, and the static meshes the keeper holds
G.LOADS = { G.ASSETS.skull, G.ASSETS.skull_mat, G.ASSETS.flesh[1], G.ASSETS.flesh[2], G.ASSETS.flesh[3],
    G.ASSETS.flesh[4], G.ASSETS.fx }
G.HELD = { G.ASSETS.skull, G.ASSETS.flesh[1], G.ASSETS.flesh[2], G.ASSETS.flesh[3], G.ASSETS.flesh[4] }
-- The sentinel names (meta.lua lab_risky; data/lab_classes.lua rows behind __index) and the ones each mode needs
G.NAMES = { 'gib.load', 'gib.spawn', 'gib.mesh', 'gib.phys', 'gib.fx', 'gib.destroy', 'extra.fall', 'hair.keep',
    'slicer.fall' }
G.NEED = { burst = { 'gib.spawn', 'gib.mesh', 'gib.phys' }, keep = { 'hair.keep' }, fall = { 'extra.fall' },
    slice_fall = { 'slicer.fall' } }
G.COUNTERS = { 'gib_bursts', 'gib_chunks', 'gib_falls', 'gib_keeps', 'gib_fail', 'gib_evicted' }
-- A guard that refused: the call never ran, so the object is no failure of its route
G.NEVER_RAN = { inherit_off = true, disabled_by_sentinel = true, arm_write_failed = true }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua gib.*, extra.fall, hair.keep)
local N = {}
local F = {
    {"/Script/Engine.StaticMeshComponent", "StaticMesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SkinnedMeshComponent", "LeaderPoseComponent"},
    {"/Script/Engine.SkeletalMesh", "Skeleton"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.SceneComponent", "RelativeLocation"},
    {"/Script/CoreUObject.BoxSphereBounds", "BoxExtent"},
    {"/Script/CoreUObject.BoxSphereBounds", "SphereRadius"},
}
G.N, G.F = N, F

local A = nil
local function new_state()
    return { init = false, ended = false, jobs = {}, objs = {}, sig = {}, sig_at = {}, sig_done = false, fails = {},
        off = {}, busy_f = nil, warm = nil, found = nil, keeper = nil, radius = {}, bounds = {}, death_ep = nil,
        meat = G.MEAT, qdrop = 0, made = { bursts = 0, chunks = 0, falls = 0, keeps = 0, fail = 0, evicted = 0 } }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function gnow() return S.game_time or 0 end
local function text(s)
    s = tostring(s)
    return #s > 160 and s:sub(1, 160) or s
end
local function short(path) return type(path) == 'string' and (path:match('%.([^%.]+)$') or path) or tostring(path) end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
local function mod(name)                                -- a sibling module of the beta set (lab_piece, lab_look)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
local function live(rec) return type(rec) == 'table' and ue.live_mod(rec) or nil end

-- ---------- plain vectors ----------
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local ZERO, UP = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }
local function v3(v)
    if type(v) ~= 'table' then return nil end
    if num(v.x) and num(v.y) and num(v.z) then return { x = v.x, y = v.y, z = v.z } end
    return nil
end
local function add(a, b, k) k = k or 1 return { x = a.x + k * b.x, y = a.y + k * b.y, z = a.z + k * b.z } end
local function scale(v, k) return { x = v.x * k, y = v.y * k, z = v.z * k } end
local function unit(v)
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if not num(n) or n < 1e-6 then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
-- A random unit direction from the cut's generator, its z at least zlo (default -1)
local function rand_dir(rng, zlo)
    for _ = 1, 8 do
        local d = unit({ x = rng:range(-1, 1), y = rng:range(-1, 1), z = rng:range(zlo or -1, 1) })
        if d then return d end
    end
    return UP
end
-- A full FTransform (every field set: a missing one reads 0) from { loc, quat, scale (a number or {x, y, z}) }; a
-- quaternion or scale that does not read is the identity
local function ft(x)
    local l, q, s = x.loc, x.quat, x.scale
    if not (type(q) == 'table' and num(q.w) and num(q.x) and num(q.y) and num(q.z)
            and q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z > 1e-12) then
        q = { w = 1, x = 0, y = 0, z = 0 }
    end
    if num(s) then s = { x = s, y = s, z = s } end
    if not (type(s) == 'table' and num(s.x) and num(s.y) and num(s.z) and s.x > 0 and s.y > 0 and s.z > 0) then
        s = { x = 1, y = 1, z = 1 }
    end
    return { Translation = ue.vec(l.x, l.y, l.z), Rotation = { X = q.x + 0.0, Y = q.y + 0.0, Z = q.z + 0.0,
        W = q.w + 0.0 }, Scale3D = ue.vec(s.x, s.y, s.z) }
end

-- ---------- the head of a class, readiness, the breakers ----------
-- The head of a data/cut_classes.lua row: mode, hair, why. Cloth hair takes the hair_mode knob (never a bald head);
-- else the row's head_mode ('burst' bursts, anything else flies whole)
function G.head_mode(row)
    row = type(row) == 'table' and row or {}
    local cloth = type(row.hair_cloth) == 'table' and row.hair_cloth[1] ~= nil
    if cloth then
        if C.knob('hair_mode') == 'keep' then return 'piece', 'keep', 'hair_keep' end
        return 'burst', 'hidden', 'hair_burst'
    end
    if row.head_mode == 'burst' then return 'burst', 'none', 'row' end
    return 'piece', 'none', 'row'
end
-- A name LAB.armed would run now: pinned, not struck, not inherited after a stop, its sig resolved ok. ok, why
local function usable(name)
    if LAB.pinned() ~= true then return false, 'unpinned' end
    if SENT.is_disabled(name) then return false, 'disabled' end
    if LAB.inherited(name) and not LAB.inherit_ok() then return false, 'inherit_off' end
    local s = st.sig[name]
    if s == nil then return false, 'sig_pending' end
    if s ~= true then return false, s end
    return true
end
-- A burst has something to throw: the engine Sphere, the skull with its bounds, or a flesh mesh with its bounds and
-- BasicShapeMaterial for its MID
local function meat_ready(f)
    if f.sphere_ok or st.radius[G.ASSETS.skull] then return true end
    if not f.basic_ok then return false end
    for _, p in ipairs(G.ASSETS.flesh) do
        if st.radius[p] then return true end
    end
    return false
end
-- Whether a mode can run now (table reads only: lab_cut asks inside its armed stage)
function G.ready(mode)
    if not G.NEED[mode] then return false, 'bad_mode' end
    if not (st.init and META.beta_gib == true) then return false, 'off' end
    if st.ended then return false, 'ended' end
    if not MODOFF.enabled('lab_gib') then return false, 'modoff' end
    for _, n in ipairs(G.NEED[mode]) do
        local ok, why = usable(n)
        if not ok then return false, why end
    end
    if st.off[mode] then return false, 'breaker' end
    local f = st.found
    if not f then return false, 'warming' end
    if not (f.actor and f.box) then return false, 'no_class' end
    if mode == 'fall' or mode == 'slice_fall' then
        if C.knob('extras_fall') ~= true then return false, 'knob' end
        if not (f.smc and f.poseable) then return false, 'no_class' end
        return true
    end
    if not (f.smc and meat_ready(f)) then return false, 'no_assets' end
    if mode == 'keep' then
        local okb, wb = G.ready('burst')                -- a failed keep bursts: the burst must be there
        if not okb then return false, 'burst: ' .. tostring(wb) end
        local P = mod('lab_piece')
        if not (P and type(P.show) == 'function' and type(P.destroy) == 'function') then return false, 'no_show' end
        if not f.cloth then return false, 'no_class' end
    end
    return true
end
local function failed(kind, why)
    local n = (st.fails[kind] or 0) + 1
    st.fails[kind] = n
    if n >= G.FAIL_MAX and not st.off[kind] then
        st.off[kind] = true
        LAB.rec('gib_off', { kind = kind, fails = n, why = text(why) }, true)
    end
end
local function worked(kind) st.fails[kind] = 0 end
local function rec_fail(job, kind, step, why, name)
    st.made.fail = st.made.fail + 1
    LAB.count('gib_fail')
    LAB.rec('gib_fail', { id = job.cut.id, kind = kind, step = step, why = text(why), name = name }, true)
end

-- ---------- the objects of a cut: listed from the spawn until destroyed ----------
local function gone_evicts(cut)
    return type(cut) == 'table' and (cut.gone_why == 'destroyed' or cut.gone_why == 'collected')
        and (cut.kept ~= true or cut.expired == true)          -- expired: lab_corpse let that kept body go
end
local function linger_s() return C.knob('piece_linger_s') or 0 end
-- The object o (an item of a job, or an orphan) listed with its actor a; a failed one is due at once. o | nil
local function track(o, a, why)
    o.rec, o.t0 = ue.keep_mod(a), gnow()
    if not o.rec then return nil end
    st.objs[#st.objs + 1] = o
    if why then o.due, o.due_why = gnow(), why
    elseif gone_evicts(o.cut) then o.due, o.due_why = gnow() + linger_s(), 'body_gone' end
    return o
end
local function unlist(o)
    for i, x in ipairs(st.objs) do if x == o then table.remove(st.objs, i) return end end
end

-- ---------- materials ----------
-- Every slot of the source's materials onto c (at most MAT_MAX). The slots copied
local function copy_mats(c, src)
    local ok, n = ue.call(src, 'GetNumMaterials')
    if not ok or math.type(n) ~= 'integer' then return 0 end
    local done = 0
    for i = 0, math.min(n, G.MAT_MAX) - 1 do
        local okg, m = ue.call(src, 'GetMaterial', i)
        if okg and ue.valid(m) and ue.call(c, 'SetMaterial', i, m) then done = done + 1 end
    end
    return done
end
-- m in every slot of c from slot from (default 0); from 0 reads slot 0 back. true | false
local function all_slots(c, m, from)
    local okn, n = ue.call(c, 'GetNumMaterials')
    n = okn and math.tointeger(n) or 1
    n = math.max(1, math.min(n, G.MAT_MAX))
    for i = from or 0, n - 1 do
        if not ue.call(c, 'SetMaterial', i, m) then return false end
    end
    if (from or 0) > 0 then return true end
    local okr, back = ue.call(c, 'GetMaterial', 0)
    return okr == true and ue.same(back, m)
end
-- A meat chunk's look: lab_look's meat material when it answers (tier A or B), else the flat meat MID (a flesh mesh's
-- parent is BasicShapeMaterial: its own slot is a placeholder; the Sphere's own slot is BasicShapeMaterial already)
local function meat(it, c)
    local LOOK = mod('lab_look')
    if LOOK and type(LOOK.material) == 'function' then
        local okl, m, tier = pcall(LOOK.material, 'meat', 'piece')
        if okl and ue.valid(m) and all_slots(c, m) then
            it.look = tier or 'look'
            return true
        end
    end
    local parent = nil
    if not it.sphere then
        parent = st.found and ue.live(st.found.basic) or nil
        if not parent then return nil, 'no_basic' end
    end
    local m, why = L.mid(c, parent, st.meat)
    if not m then return nil, 'mid: ' .. text(why) end
    all_slots(c, m, 1)
    it.look = 'flat'
    return true
end

-- ---------- the object steps (each inside its caller's armed call; true | nil, why) ----------
-- The carrier: our own Actor, hidden at once, its Box root (collision off from the add) at it.at with half extent
-- it.half (the Piece's spawn, lab_piece.lua spawn and place)
local function carrier(it)
    if #st.objs >= G.OBJ_HARD then
        it.soft = true
        return nil, 'cap'
    end
    local cls = ue.class(G.ACTOR)
    if not cls then return nil, 'no_actor_class' end
    local a, why, half = US.spawn_deferred(cls, ue.xform(ue.vec(it.at.x, it.at.y, it.at.z)), {})
    if not a then
        if half then track({ kind = 'orphan', cut = it.cut }, half, 'failed') end
        return nil, 'spawn: ' .. text(why)
    end
    if not track(it, a) then return nil, 'unread' end
    local ok, w = US.set_actor_hidden(a, true)
    if not ok then return nil, 'hide: ' .. text(w) end
    local box, wb = ue.add_component(a, G.BOX, { no_collision = true })
    if not box then return nil, 'box: ' .. text(wb) end
    it.box = ue.keep_mod(box)
    ok, w = L.box_extent(box, { x = it.half, y = it.half, z = it.half })
    if not ok then return nil, 'extent: ' .. text(w) end
    ok, w = ue.call(box, 'K2_SetWorldTransform', ft({ loc = it.at }), false, {}, true)
    if not ok then return nil, 'place: ' .. text(w) end
    return true
end
-- A chunk's or the skull's mesh on its carrier: a StaticMeshComponent (collision off) scaled to its size, the mesh,
-- then the look (the skull keeps MI_Skull_Old_01, else its own slots)
local function chunk_mesh(it)
    local a = live(it.rec)
    if not a then return nil, 'gone' end
    if not ue.valid(it.asset) then return nil, 'asset_gone' end
    if not (num(it.scale) and it.scale > 0) then return nil, 'bad_scale' end
    local c, w = ue.add_component(a, G.SMC, { scale = it.scale, no_collision = true })
    if not c then return nil, 'add: ' .. text(w) end
    it.mesh = ue.keep_mod(c)
    local ok, wm = L.set_static_mesh(c, it.asset)
    if not ok then return nil, 'mesh: ' .. text(wm) end
    ue.refuse_decals(c, G.SMC)
    if it.kind == 'skull' then
        it.look = (ue.valid(it.mat) and all_slots(c, it.mat)) and 'skull' or 'own'
        return true
    end
    return meat(it, c)
end
-- Trace-neutral physics on the carrier (the Piece's: ue.trace_neutral, then L.physics_on), the launch capped at
-- VEL_CAP, a spin (logged when refused), then shown
local function launch(it)
    local a, box = live(it.rec), live(it.box)
    if not (a and box) then return nil, 'gone' end
    if not ue.trace_neutral(box) then return nil, 'trace_neutral' end
    local ok, w = L.physics_on(box, it.kg, true)
    if not ok then return nil, 'phys: ' .. text(w) end
    local okv, sent = L.velocity_change(box, it.v, G.VEL_CAP)
    if not okv then return nil, 'launch: ' .. text(sent) end
    it.vel = sent
    if it.spin then
        it.spin_ok = ue.call(box, 'AddAngularImpulseInDegrees', ue.vec(it.spin.x, it.spin.y, it.spin.z),
            ue.fname('None'), true) == true
    end
    local okh, wh = US.set_actor_hidden(a, false)
    if not okh then return nil, 'show: ' .. text(wh) end
    it.shown = true
    return true
end
-- The source of a fall that cannot copy, read before anything spawns: a refusal of this class's data, never a failure
-- of the route (soft: no breaker count). what (the mesh), pose_src (skinned) | nil, why
local function fall_source(it, src)
    local e = it.e
    if not (type(e.xf) == 'table' and v3(e.xf.loc)) then return nil, nil, 'no_xf' end
    if e.class == 'static' then
        local m = ue.prop(src, 'StaticMesh')
        if not ue.valid(m) then return nil, nil, 'no_mesh' end
        return m, nil
    end
    local asset = ue.prop(src, 'SkinnedAsset')
    if not ue.valid(asset) then return nil, nil, 'no_asset' end
    if ue.is_a(asset, G.SKELETAL_MESH) ~= true then return nil, nil, 'not_skeletal_mesh' end
    local lp = ue.weak(ue.get(src, 'LeaderPoseComponent'))
    if not ue.valid(lp) then return asset, src end      -- it leads: its own pose
    local la = ue.prop(lp, 'SkinnedAsset')              -- a follower takes its leader's pose, on the same skeleton only
    local s1, s2 = ue.prop(asset, 'Skeleton'), ue.prop(la, 'Skeleton')
    if not (ue.same(asset, la) or (ue.valid(s1) and ue.valid(s2) and ue.same(s1, s2))) then
        return nil, nil, 'skeleton_differs'
    end
    return asset, lp
end
-- A falling hat or mask, whole (inside 'extra.fall'): its source read first, then its carrier at the head, the copy at
-- the source's world transform, physics, launch and show
local function fall_run(it)
    local e = it.e
    local src = live(e.rec)
    if not src then
        it.soft = true
        return nil, 'gone'
    end
    local what, pose_src, why = fall_source(it, src)
    if not what then
        it.soft = true
        return nil, why
    end
    local x = e.xf
    local ok, w = carrier(it)
    if not ok then return nil, w end
    local a = live(it.rec)
    local cls = e.class == 'static' and G.SMC or G.POSEABLE
    local c, wc = ue.add_component(a, cls, { no_collision = true })
    if not c then return nil, 'add: ' .. text(wc) end
    it.mesh = ue.keep_mod(c)
    if e.class == 'static' then ok, w = L.set_static_mesh(c, what) else ok, w = L.set_asset(c, what, true) end
    if not ok then return nil, 'mesh: ' .. text(w) end
    ue.refuse_decals(c, cls)
    it.mats = copy_mats(c, src)
    if e.class ~= 'static' then
        ok, w = L.copy_pose(c, pose_src)
        if not ok then return nil, 'pose: ' .. text(w) end
    end
    ok, w = ue.call(c, 'K2_SetWorldTransform', ft(x), false, {}, true)
    if not ok then return nil, 'place: ' .. text(w) end
    return launch(it)
end
-- fn over every item still standing, each in its own pcall (the body of a batch's armed call). true
local function each(items, fn, step)
    for _, it in ipairs(items) do
        if not it.err then
            local okc, ok, w = pcall(fn, it)
            if not okc then
                ue.caught(ok, 'gib', step)                  -- lab_probe's stop rule reads an ArrayNum text there
                ok, w = nil, ok
            end
            if not ok then it.err, it.step = text(w or 'failed'), step end
        end
    end
    return true
end
-- A guard that refused (err): every item it would have run fails, soft (the call never ran)
local function refused(items, step, err)
    if err == nil then return end
    for _, it in ipairs(items) do
        if not it.err then it.err, it.step, it.soft = text(err), step, G.NEVER_RAN[err] == true end
    end
end
local function not_ready(items, step, why)
    for _, it in ipairs(items) do it.err, it.step, it.soft = text(why), step, true end
end

-- ---------- the burst, the falls, the FX ----------
-- A static mesh's size (StaticMesh:GetBounds): the largest box half extent, else the sphere radius / sqrt 3; nil when
-- it does not read or lies outside R_MIN .. R_MAX cm
local function bounds_r(m)
    local ok, b = ue.call(m, 'GetBounds')
    if not ok then return nil end
    b = ue.p(b)
    local e = ue.prop(b, 'BoxExtent')
    local x, y, z = ue.prop(e, 'X'), ue.prop(e, 'Y'), ue.prop(e, 'Z')
    local r = nil
    if num(x) and num(y) and num(z) then r = math.max(x, y, z)
    else
        local s = ue.prop(b, 'SphereRadius')
        if num(s) then r = s / math.sqrt(3) end
    end
    if r and r >= G.R_MIN and r <= G.R_MAX then return r end
    return nil
end
-- The sizes of the loaded G.HELD meshes not asked yet, each once a session (they stay across map loads: an asset's
-- bounds). { short name = cm | 'unread' } | nil when none was asked
local function read_bounds()
    local got = nil
    for _, p in ipairs(G.HELD) do
        local m = not st.bounds[p] and ue.asset_peek(p) or nil
        if m then
            st.bounds[p] = true
            st.radius[p] = bounds_r(m)
            got = got or {}
            got[short(p)] = st.radius[p] and math.floor(st.radius[p] * 10 + 0.5) / 10 or 'unread'
        end
    end
    return got
end
-- The body of a burst's 'gib.mesh' call: the batch's meshes, then the bounds not read yet (the header). The bounds
-- read, or nil
local function mesh_batch(batch)
    each(batch, chunk_mesh, 'gib.mesh')
    local ok, got = pcall(read_bounds)
    if ok then return got end
    ue.caught(got, 'gib', 'gib.bounds')                 -- lab_probe's stop rule reads an ArrayNum text there
    return nil
end
local function item_failed(job, it)
    rec_fail(job, it.kind, it.step, it.err, it.name)
    if it.rec then it.due, it.due_why = gnow(), 'failed' end
    if not it.soft and it.kind ~= 'fall' then job.burst_fail = it.err end
end
local function burst_batch(job, batch)
    local ok, why = true, nil
    for _, n in ipairs(G.NEED.burst) do
        if ok then ok, why = usable(n) end
    end
    if ok and st.off.burst then ok, why = false, 'breaker' end
    if not ok then
        not_ready(batch, 'ready', why)
    else
        local _, e1 = LAB.armed('gib.spawn', each, batch, carrier, 'gib.spawn')
        refused(batch, 'gib.spawn', e1)
        local got, e2 = LAB.armed('gib.mesh', mesh_batch, batch)
        refused(batch, 'gib.mesh', e2)
        if type(got) == 'table' then LAB.rec('gib_bounds', { id = job.cut.id, radius = got }, true) end
        local _, e3 = LAB.armed('gib.phys', each, batch, launch, 'gib.phys')
        refused(batch, 'gib.phys', e3)
    end
    for _, it in ipairs(batch) do
        if it.err then item_failed(job, it)
        elseif it.kind == 'skull' then job.skull = true
        else job.chunks = job.chunks + 1 end
    end
end
-- A job's fall mode (its G.NEED row and breaker kind): a sliced head's falls (job.cut.slice) run under their own
-- 'slicer.fall' and kind 'slice_fall' (header), a cut head's under 'extra.fall' and 'fall'. fall_batch writes the
-- name out as literals: the guard-name scan (tests/test_lab_stage1.lua) resolves those, not G.NEED[mode][1]
local function fall_mode(job) return job.cut.slice and 'slice_fall' or 'fall' end
local function fall_batch(job, falls)
    local kind = fall_mode(job)
    local name = kind == 'slice_fall' and 'slicer.fall' or 'extra.fall'
    local ok, why = usable(name)
    if ok and st.off[kind] then ok, why = false, 'breaker' end
    if not ok then
        not_ready(falls, 'ready', why)
    else
        local _, err = LAB.armed(name, each, falls, fall_run, name)
        refused(falls, name, err)
    end
    for _, it in ipairs(falls) do
        if it.err then
            item_failed(job, it)
            if not it.soft then failed(kind, it.err) end
        else
            job.falls = job.falls + 1
            st.made.falls = st.made.falls + 1
            LAB.count('gib_falls')
            worked(kind)
        end
    end
end
-- The head-break FX at the head (the vanilla NS_BloodHeadBreak_001, lab_blood's head spray: auto-destroyed)
local function fx_item(job, it)
    local ok, why = usable('gib.fx')
    if ok and st.off.fx then ok, why = false, 'breaker' end
    if not ok then job.fx = why return end
    local sys = ue.asset_peek(G.ASSETS.fx) or ue.find(G.ASSETS.fx)
    if not sys then job.fx = 'no_asset' return end
    local c, err = LAB.armed('gib.fx', function()
        return (ue.spawn_at(sys, ue.vec(it.at.x, it.at.y, it.at.z), ue.rot(90, 0, 0)))
    end)
    if c then
        job.fx = 'ok'
        worked('fx')
    else
        job.fx = text(err or 'no_component')
        rec_fail(job, 'fx', 'gib.fx', job.fx, it.name)
        if not G.NEVER_RAN[err] then failed('fx', job.fx) end
    end
end
-- A chunk's mesh: a held SM_FX_Flesh whose bounds read, picked by the cut's generator, else the engine Sphere.
-- mesh, half extent, sphere (bool), name | nil
local function flesh_pick(rng)
    local list = {}
    for _, p in ipairs(G.ASSETS.flesh) do
        local m, r = ue.asset_peek(p), st.radius[p]
        if m and r then list[#list + 1] = { m = m, r = r, name = short(p) } end
    end
    local e = rng:pick(list)
    if e then return e.m, e.r, false, e.name end
    local s = st.found and st.found.sphere_ok and ue.live(st.found.sphere) or nil
    if s then return s, G.SPHERE_R, true, 'Sphere' end
    return nil
end
-- The burst's objects into job.todo: the FX, the skull, then the meat chunks (gib_count in all, the skull included)
local function plan_burst(job)
    local at, vel, rng = job.at, job.vel or ZERO, job.rng
    if not at then job.burst_why = 'no_at' return end
    job.todo[#job.todo + 1] = { kind = 'fx', at = at, name = 'NS_BloodHeadBreak_001' }
    local n = C.knob('gib_count') or 0
    local skull, r = ue.asset_peek(G.ASSETS.skull), st.radius[G.ASSETS.skull]
    job.burst_n = n
    if n > 0 and skull and r then
        local d = rand_dir(rng, 0)
        job.todo[#job.todo + 1] = { kind = 'skull', cut = job.cut, name = 'SM_Skull_Old_01', asset = skull,
            mat = ue.asset_peek(G.ASSETS.skull_mat), scale = G.SKULL_R / r, half = G.SKULL_HALF, kg = G.SKULL_KG,
            at = add(at, d, rng:range(0, G.JITTER_CM)),
            v = add(add(scale(vel, G.SKULL_SHARE), d, rng:range(G.SKULL_SPREAD[1], G.SKULL_SPREAD[2])), UP,
                G.SKULL_UP),
            spin = scale(rand_dir(rng), rng:range(G.SPIN[1], G.SPIN[2]) / 2) }
        n = n - 1
    elseif n > 0 then
        job.skull_why = skull and 'no_bounds' or 'no_skull'
    end
    for _ = 1, n do
        local m, rr, sphere, name = flesh_pick(rng)
        if not m then
            job.burst_why = 'no_mesh'
            break
        end
        local tr, d = rng:range(G.MEAT_R[1], G.MEAT_R[2]), rand_dir(rng, -0.2)
        job.todo[#job.todo + 1] = { kind = 'chunk', cut = job.cut, name = name, asset = m, sphere = sphere,
            scale = tr / rr, half = clamp(tr * 0.8, G.CHUNK_HALF[1], G.CHUNK_HALF[2]), kg = G.CHUNK_KG,
            at = add(at, d, rng:range(0, G.JITTER_CM)),
            v = add(add(scale(vel, G.BURST_SHARE), d, rng:range(G.SPREAD[1], G.SPREAD[2])), UP, G.BURST_UP),
            spin = scale(rand_dir(rng), rng:range(G.SPIN[1], G.SPIN[2])) }
    end
end
local function skip(job, name, why)
    if #job.skip < G.SKIP_MAX then job.skip[#job.skip + 1] = { name = tostring(name), why = tostring(why) } end
end
-- A falling extra's object: from the head (else its own place) with FALL_SHARE of the head's launch
local function fall_item(job, e)
    local rng = job.rng
    local at = job.at or (type(e.xf) == 'table' and v3(e.xf.loc)) or nil
    if not at then return nil, 'no_at' end
    local d = rand_dir(rng, 0)
    return { kind = 'fall', cut = job.cut, name = tostring(e.name), e = e, half = G.FALL_HALF, kg = G.FALL_KG, at = at,
        v = add(add(scale(job.vel or ZERO, G.FALL_SHARE), d, rng:range(G.FALL_SPREAD[1], G.FALL_SPREAD[2])), UP,
            G.FALL_UP),
        spin = scale(rand_dir(rng), rng:range(G.FALL_SPIN[1], G.FALL_SPIN[2])) }
end
-- The job's objects: the burst when its mode is 'burst', then every extra that falls; the rest are logged
local function plan(job)
    if job.mode == 'burst' then
        local ok, why = G.ready('burst')
        if ok then plan_burst(job) else job.burst_why = why end
    end
    local extras = job.cut.gib.extras
    for _, e in ipairs(type(extras) == 'table' and extras or {}) do
        if type(e) == 'table' then
            if e.fall ~= true then skip(job, e.name, 'hidden')
            elseif e.class ~= 'static' and e.class ~= 'skinned' then
                skip(job, e.name, 'unsupported: ' .. tostring(e.class))
            else
                local ok, why = G.ready(fall_mode(job))
                local it = nil
                if ok then it, why = fall_item(job, e) end
                if it then job.todo[#job.todo + 1] = it else skip(job, e.name, why) end
            end
        end
    end
end

-- ---------- the kept hair (one 'hair.keep' call) ----------
-- One ChaosClothComponent per hidden source on the held Piece: simulation off, the source's asset and slots, led by
-- the head poseable and snapped onto it; then P.show(piece). n | nil, why
local function keep_hair(job, P, piece)
    local a = live(piece.rec)
    local q = type(piece.poses) == 'table' and piece.poses[1] or nil
    local hp = q and live(q.rec) or nil
    if not (a and hp) then return nil, 'no_piece' end
    local n = 0
    for _, h in ipairs(type(job.cut.gib.hair) == 'table' and job.cut.gib.hair or {}) do
        local src = live(h.rec)
        if not src then return nil, 'hair_gone: ' .. tostring(h.name) end
        local oka, asset = ue.call(src, 'GetAsset')
        asset = oka and ue.p(asset) or nil
        if not ue.valid(asset) then return nil, 'no_asset: ' .. tostring(h.name) end
        local c, w = ue.add_component(a, G.CLOTH)
        if not c then return nil, 'add: ' .. text(w) end
        if not ue.call(c, 'SetEnableSimulation', false) then return nil, 'simulation' end
        if not ue.call(c, 'SetAsset', asset) then return nil, 'asset' end
        copy_mats(c, src)
        if not ue.call(c, 'SetLeaderPoseComponent', hp, true, false) then return nil, 'leader' end
        local okt, r = ue.call(c, 'K2_AttachToComponent', hp, ue.fname('None'), 2, 2, 2, false)
        if not okt or r == false then return nil, 'attach' end
        n = n + 1
    end
    if n == 0 then return nil, 'no_hair' end
    local ok, w = P.show(piece)
    if not ok then return nil, 'show: ' .. text(w) end
    return n
end
-- The armed body: the hair kept, or the held Piece destroyed where it flew (its place read first: the burst goes
-- there). { ok, n } | { ok = false, why, at, destroyed }
local function keep_run(job)
    local P, piece = mod('lab_piece'), job.cut.piece
    local okc, n, why = pcall(keep_hair, job, P, piece)
    if not okc then
        ue.caught(n, 'gib', 'hair.keep')
        n, why = nil, n
    end
    if n then return { ok = true, n = n } end
    local a = live(piece.rec)
    local at = a and ue.root_loc(a) or nil
    local okd = P.destroy(piece, 'hair_fail')
    return { ok = false, why = text(why), at = at, destroyed = okd == true }
end
-- A held Piece no keep will show (a stale, gone or revived job, a refused keep guard): destroyed hidden under
-- 'hair.keep', else under lab_piece's own 'piece.destroy'
local function drop_held(job)
    local P, piece = mod('lab_piece'), job.cut.piece
    if not (P and type(P.destroy) == 'function' and type(piece) == 'table') then return end
    if usable('hair.keep') then LAB.armed('hair.keep', P.destroy, piece, 'hair_fail')
    elseif not SENT.is_disabled('piece.destroy') then LAB.armed('piece.destroy', P.destroy, piece, 'hair_fail') end
end
local function keep_step(job)
    local P = mod('lab_piece')
    local ok, why = usable('hair.keep')
    if ok and st.off.keep then ok, why = false, 'breaker' end
    if ok and not (P and type(P.show) == 'function' and type(P.destroy) == 'function') then
        ok, why = false, 'no_show'
    end
    local r, err = nil, nil
    if ok then r, err = LAB.armed('hair.keep', keep_run, job) end
    if ok and err == nil and type(r) == 'table' and r.ok then
        job.hair, job.kept = 'kept', r.n
        st.made.keeps = st.made.keeps + 1
        LAB.count('gib_keeps')
        worked('keep')
    else
        local w = type(r) == 'table' and r.why or err or why
        job.hair, job.mode, job.keep_why = 'keep_fail', 'burst', text(w)
        rec_fail(job, 'keep', 'hair.keep', w, 'hair')
        if ok and type(r) == 'table' then failed('keep', w) end   -- a refused guard is no failure of the route
        if not (type(r) == 'table' and r.destroyed) then drop_held(job) end
        if type(r) == 'table' and v3(r.at) then job.at = v3(r.at) end
    end
    plan(job)
    if job.todo[1] then job.state = 'objects' else job.state = 'done' end
end

-- ---------- jobs: one step a frame ----------
local function finish(job, why)
    if job.done then return end
    job.done = true
    for i, j in ipairs(st.jobs) do
        if j == job then table.remove(st.jobs, i) break end
    end
    local made = (job.chunks or 0) + (job.skull and 1 or 0)
    if (job.burst_n or 0) > 0 then
        if made > 0 then
            worked('burst')
            st.made.bursts, st.made.chunks = st.made.bursts + 1, st.made.chunks + (job.chunks or 0)
            LAB.count('gib_bursts')
            LAB.count('gib_chunks', job.chunks or 0)
        elseif job.burst_fail then
            failed('burst', job.burst_fail)
        end
    end
    local cut = job.cut
    local g = type(cut.gib) == 'table' and cut.gib or {}
    LAB.rec('gib', { id = cut.id, class = cut.class, mode = job.mode or 'unread', hair = job.hair or cut.hair or 'none',
        extras = type(g.extras) == 'table' and #g.extras or 0, falls = job.falls or 0, chunks = job.chunks or 0,
        skull = job.skull == true, skull_why = job.skull_why, fx = job.fx, burst_why = job.burst_why,
        keep_why = job.keep_why, kept_hair = job.kept, skip = (job.skip and job.skip[1]) and job.skip or nil, why = why,
        frames = S.frame - job.f, slice = cut.slice or nil }, true)
end
-- The first step: gone, revived or stale jobs end (a held Piece goes); the mode and hair from the cut; a kept hair
-- waits its own call, anything else plans its objects. done, why
local function start(job)
    local cut = job.cut
    local held = cut.hair == 'keep' and cut.hold_show and type(cut.piece) == 'table'
    if job.gone or gnow() - job.t > G.STALE_S then
        if held then drop_held(job) end
        return true, job.gone or 'stale'
    end
    job.mode = cut.head_mode == 'burst' and 'burst' or 'piece'
    job.hair = type(cut.hair) == 'string' and cut.hair or 'none'
    job.rng = RNG.new(RNG.seed_from(cut.id, 'gib'))
    job.at, job.vel = v3(cut.gib.at), v3(cut.gib.vel)
    if job.hair == 'keep' then
        if held then
            job.state = 'keep'
            return false
        end
        job.hair, job.mode, job.keep_why = 'keep_fail', 'burst', 'no_held'   -- never a bald head: it bursts
    end
    plan(job)
    if not job.todo[1] then return true, nil end
    job.state = 'objects'
    return false
end
local function objects_step(job)
    if job.gone then return finish(job, job.gone) end
    local batch, falls, n = {}, {}, 0
    while n < G.PER_FRAME and job.todo[1] do
        local it = table.remove(job.todo, 1)
        n = n + 1
        if it.kind == 'fx' then fx_item(job, it)
        elseif it.kind == 'fall' then falls[#falls + 1] = it
        else batch[#batch + 1] = it end
    end
    if batch[1] then burst_batch(job, batch) end
    if falls[1] then fall_batch(job, falls) end
    if not job.todo[1] then finish(job) end
end
-- One step of the oldest job, in a later frame than its commit. true when it ran
local function job_tick()
    local job = st.jobs[1]
    if not job or job.f >= S.frame then return false end
    if job.state == 'start' then
        local done, why = start(job)
        if done then
            finish(job, why)
            return true
        end
    end
    if job.state == 'keep' then
        keep_step(job)
        if job.state == 'done' then finish(job) end
    elseif job.state == 'objects' then
        objects_step(job)
    end
    return true
end

-- ---------- warm: the sigs once per session, then per map the lookups, the loads and the keeper ----------
-- One LAB.sig a frame until every name has its answer (a refused guard asks again SIG_RETRY_S later). true when it ran
local function sig_step()
    if st.sig_done then return false end
    local t, left = now(), false
    for _, n in ipairs(G.NAMES) do
        if st.sig[n] == nil then
            left = true
            if t >= (st.sig_at[n] or 0) then
                local ok, why = LAB.sig(n)
                if ok then st.sig[n] = true
                elseif why == 'sig_mismatch' or why == 'sig_unknown' then st.sig[n] = why
                elseif why ~= 'sig_pending' then st.sig_at[n] = t + G.SIG_RETRY_S end
                return true
            end
        end
    end
    st.sig_done = not left
    return false
end
local function load_one(path)
    local o, via = ue.asset(path)
    return o and via or 'nil'
end
-- The keeper actor (inside 'gib.spawn'): ours, hidden, no component yet. 'spawned' | why
local function keeper_spawn()
    local cls = ue.class(G.ACTOR)
    if not cls then return 'no_actor_class' end
    local a, why, half = US.spawn_deferred(cls, ue.xform(), {})
    if not a then
        if half then track({ kind = 'orphan' }, half, 'failed') end
        return 'spawn: ' .. text(why)
    end
    local rec = ue.keep_mod(a)
    if not rec then return 'unread' end
    st.keeper = { rec = rec, held = {} }
    US.set_actor_hidden(a, true)                        -- a refused hide leaves nothing to draw: its holders are hidden
    return 'spawned'
end
-- The keeper's holders (inside 'gib.mesh'): each loaded static mesh on a hidden, collision-free StaticMeshComponent
-- (the skull's with MI_Skull_Old_01); no bounds read here (the first burst reads them). The meshes held
local function keeper_hold()
    local a = live(st.keeper and st.keeper.rec)
    if not a then return 0 end
    local n = 0
    for _, p in ipairs(G.HELD) do
        local m = ue.asset_peek(p)
        if m then
            local c = ue.add_component(a, G.SMC, { no_collision = true })
            if c then
                ue.set_hidden(c, true)
                if L.set_static_mesh(c, m) then
                    n = n + 1
                    st.keeper.held[short(p)] = true
                    local mat = p == G.ASSETS.skull and ue.asset_peek(G.ASSETS.skull_mat) or nil
                    if mat and ue.call(c, 'SetMaterial', 0, mat) then
                        st.keeper.held[short(G.ASSETS.skull_mat)] = true
                    end
                end
            end
        end
    end
    return n
end
local function assets_rec(w)
    local radius = {}
    for p, r in pairs(st.radius) do radius[short(p)] = math.floor(r * 10 + 0.5) / 10 end
    local held = {}
    for k in pairs(st.keeper and st.keeper.held or {}) do held[#held + 1] = k end
    table.sort(held)
    local f = st.found or {}
    LAB.rec('gib_assets', { loads = w.res, held = held, radius = radius, keeper = w.keeper, sphere = f.sphere_ok,
        basic = f.basic_ok, cloth_class = f.cloth }, true)
end
-- One warm step: the lookups, then (once a cut class died on this map) one load, then the keeper's spawn, then its
-- holders, then the record. true when a step ran (a name whose sig is still pending waits)
local function warm_step()
    local w = st.warm
    if not w or w.done then return false end
    if not st.found then
        local sphere, basic = ue.find(G.SPHERE), ue.find(G.MAT)
        st.found = { sphere = ue.keep(sphere), basic = ue.keep(basic), sphere_ok = sphere ~= nil,
            basic_ok = basic ~= nil, actor = ue.class(G.ACTOR) ~= nil, box = ue.class(G.BOX) ~= nil,
            smc = ue.class(G.SMC) ~= nil, poseable = ue.class(G.POSEABLE) ~= nil, cloth = ue.class(G.CLOTH) ~= nil }
        return true
    end
    if st.death_ep ~= ue.epoch then return false end    -- no cut class died on this map yet: no load, no spawn
    local K = mod('lab_cut')                            -- nor while a kill's cuts wait for their commit
    if K and type(K.status) == 'function' then
        local okk, s = pcall(K.status)
        if okk and type(s) == 'table' and (tonumber(s.jobs) or 0) > 0 then return false end
    end
    local SLC = mod('lab_slice')                        -- nor while a slicer job holds a corpse (its slice frames)
    if SLC and type(SLC.busy_any) == 'function' and SLC.busy_any() then return false end
    local path = G.LOADS[w.i]
    if path then
        local ok, why = usable('gib.load')
        if why == 'sig_pending' then return false end
        w.i = w.i + 1
        if not ok then
            w.res[short(path)] = why
            return false
        end
        LAB.oneshot()                                   -- a cold package loads here, in play
        local r, err = LAB.armed('gib.load', load_one, path)
        w.res[short(path)] = err ~= nil and text(err) or r
        return true
    end
    if w.keeper == nil then
        local ok, why = usable('gib.spawn')
        if ok then ok, why = usable('gib.mesh') end
        if why == 'sig_pending' then return false end
        local any = false
        for _, p in ipairs(G.HELD) do if ue.asset_peek(p) then any = true end end
        if not ok then w.keeper = why
        elseif not any then w.keeper = 'nothing'
        else
            local r, err = LAB.armed('gib.spawn', keeper_spawn)
            w.keeper = err ~= nil and text(err) or r
            return true
        end
    end
    if w.keeper == 'spawned' and w.held == nil then
        local r, err = LAB.armed('gib.mesh', keeper_hold)
        w.held = err ~= nil and text(err) or r
        return true
    end
    assets_rec(w)
    w.done = true
    return false
end

-- ---------- evictions: one a frame under 'gib.destroy' (a failed or due object first, then FIFO and life) ----------
local function pick_evict()
    local g = gnow()
    for _, o in ipairs(st.objs) do
        if o.due and g >= o.due then return o end
    end
    local first = st.objs[1]
    if not first then return nil end
    if #st.objs > G.OBJ_MAX or g - (first.t0 or g) >= G.LIFE_S then return first end
    return nil
end
local function evict_tick()
    local o = pick_evict()
    if not o or not usable('gib.destroy') then return false end
    local a = live(o.rec)
    if not a then
        unlist(o)
        return false
    end
    local r, err = LAB.armed('gib.destroy', US.destroy_actor, a)
    if err == nil and r then
        unlist(o)
        o.shown = false
        st.made.evicted = st.made.evicted + 1
        LAB.count('gib_evicted')
    else
        o.tries = (o.tries or 0) + 1
        if o.tries >= G.DESTROY_TRIES then unlist(o) end   -- it stays in the world: the map takes it
    end
    return true
end

-- ---------- bus listeners (they only queue and mark) and the ticker ----------
-- One job for cut, at most JOBS (a full queue drops it: one 'gib' record, why 'queue_full')
local function queue(cut)
    if #st.jobs >= G.JOBS then
        st.qdrop = st.qdrop + 1
        LAB.rec('gib', { id = cut.id, class = cut.class, why = 'queue_full', slice = cut.slice or nil }, true)
        return
    end
    st.jobs[#st.jobs + 1] = { cut = cut, t = gnow(), f = S.frame, state = 'start', todo = {}, skip = {}, chunks = 0,
        falls = 0 }
end
local function on_live(cut)
    st.busy_f = S.frame
    if not st.init or st.ended or type(cut) ~= 'table' or type(cut.gib) ~= 'table' then return end
    if cut.part ~= nil and cut.part ~= 'head' then return end
    queue(cut)
end
-- A sliced head's hats and masks (bus lab_slice_fall, lab_slice_route's drop step; header): one falls-only job whose
-- cut is a plain table (no lab_cut cut: slice and kept true, the corpse's key for lab_slice_gone)
local function on_slice_fall(ev)
    st.busy_f = S.frame
    if not st.init or st.ended or type(ev) ~= 'table' or type(ev.extras) ~= 'table' or ev.extras[1] == nil then return end
    queue({ id = ev.id, class = ev.class, key = ev.key, part = 'head', slice = true, kept = true,
        head_mode = 'piece', hair = 'none', gib = { at = ev.at, vel = ev.vel, extras = ev.extras, hair = {} } })
end
-- A sliced corpse went (bus lab_slice_gone, lab_corpse): its falls go piece_linger_s later, a job of it ends
local function on_slice_gone(ev)
    if type(ev) ~= 'table' or ev.key == nil then return end
    for _, job in ipairs(st.jobs) do
        if job.cut.slice and job.cut.key == ev.key then job.gone = 'body_gone' end
    end
    local t = gnow() + linger_s()
    for _, o in ipairs(st.objs) do
        if type(o.cut) == 'table' and o.cut.slice and o.cut.key == ev.key and o.due == nil then
            o.due, o.due_why = t, 'body_gone'
        end
    end
end
-- A death marks a busy frame; one of a data/cut_classes.lua class also lets this map's warm load and hold
local function on_death(d)
    st.busy_f = S.frame
    if type(d) == 'table' and type(d.class) == 'string' and (data('data.cut_classes').classes or {})[d.class] then
        st.death_ep = ue.epoch
    end
end
-- A corpse gone (destroyed or collected, not kept): its objects go piece_linger_s later; a revive keeps them. A job
-- of that cut ends at its next step
local function on_gone(cut)
    if type(cut) ~= 'table' then return end
    for _, job in ipairs(st.jobs) do
        if job.cut == cut then job.gone = cut.gone_why and 'body_gone' or 'revived' end
    end
    if not gone_evicts(cut) then return end
    local t = gnow() + linger_s()
    for _, o in ipairs(st.objs) do
        if o.cut == cut and o.due == nil then o.due, o.due_why = t, 'body_gone' end
    end
end
local function tick()
    if not st.init or st.ended then return end
    if LAB.ended() then
        st.ended = true
        return
    end
    if LAB.paused() or st.busy_f == S.frame then return end
    if not MODOFF.enabled('lab_gib') or LAB.pinned() ~= true then return end
    if sig_step() then return end
    if job_tick() then return end
    if warm_step() then return end
    evict_tick()
end
local EVENTS = { 'lab_cut_live', 'lab_cut_gone', 'lab_death', 'lab_end', 'lab_slice_fall', 'lab_slice_gone' }

-- The shown gib actors (live, not hidden by us): MO.feature's live list
function G.live()
    local out = {}
    for _, o in ipairs(st.objs) do
        local a = o.shown and live(o.rec) or nil
        if a then out[#out + 1] = { obj = a, name = ue.name(a), kind = 'actor' } end
    end
    return out
end

-- ---------- lifecycle ----------
function G.init(adapter)
    A = adapter
    st = new_state()
    if not (LAB.beta() and META.beta_gib == true) then return true end
    st.init = true
    LAB.names(N, F)
    for _, k in ipairs(G.COUNTERS) do LAB.count(k, 0) end
    local c = (data('data.caps_beta_sizing').colors or {}).meat
    if type(c) == 'table' and num(c[1]) and num(c[2]) and num(c[3]) then st.meat = { R = c[1], G = c[2], B = c[3] } end
    -- mod-off hides the shown gib actors (kind 'actor'); the vanilla compare blocks new gibs, as mod-off does
    MODOFF.feature('lab_gib', { gameplay = true, live = G.live })
    BUS.on('lab_cut_live', 'lab_gib', on_live)
    BUS.on('lab_cut_gone', 'lab_gib', on_gone)
    BUS.on('lab_death', 'lab_gib', on_death)
    BUS.on('lab_end', 'lab_gib', function() st.ended = true end)
    BUS.on('lab_slice_fall', 'lab_gib', on_slice_fall)
    BUS.on('lab_slice_gone', 'lab_gib', on_slice_gone)
    S.ticker('lab_gib', tick)
    return true
end
-- After a map load (main.lua's staggered warm-up): the lookups again, one step a frame; the loads and the keeper once
-- a cut class dies on the map (warm_step)
function G.warm()
    if not st.init or st.ended then return end
    st.warm = { i = 1, res = {} }
end
-- A map load: the jobs, the objects, the keeper and its holds went with the old map; the sigs, the breakers and the
-- mesh sizes (an asset's bounds, read once a session) stay
function G.reset()
    if not st.init then return end
    st.jobs, st.objs, st.keeper, st.found, st.warm, st.busy_f = {}, {}, nil, nil, nil, nil
end
function G.status()
    local off = {}
    for k in pairs(st.off) do off[#off + 1] = k end
    table.sort(off)
    local w = st.warm or {}
    local sized = 0
    for _ in pairs(st.radius) do sized = sized + 1 end
    return { init = st.init, ended = st.ended, jobs = #st.jobs, objs = #st.objs, off = off, sig_done = st.sig_done,
        warm = w.done == true, keeper = st.keeper ~= nil, qdrop = st.qdrop, made = st.made, sized = sized,
        cut_death = st.death_ep ~= nil and st.death_ep == ue.epoch }
end
-- Engine-free (Ctrl+R runs it off the game thread): the objects stay in the world until the map goes
function G.shutdown()
    S.remove_ticker('lab_gib')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_gib') end
    st, A = new_state(), nil
end
return G
