-- status: new in M1a A3.5 (offline only; TC-LAB-02 HD0, HD2 and the landing rows decide) origin: kb:pieces-gibs-physics#flying-severed-limb-in-ue5-poseablemesh-copy-with-collapsed-ancestors-on-a-hidden-physics-box
-- lab_piece.lua: the lab's Pieces and the HD0 ladder (spec M1a D10, ladder P10-P16, sections 3.5, 3.8, 3.9). Dev builds
-- only, dev set 'lab02' (META.dev_sets, main.lua); the probe and release never require it, and init stays inert (no
-- listener, no ticker, no record) unless LAB.cut_set(). Engine work only through adapter/ue.lua, adapter/ue_lab.lua and
-- adapter/ue_spawn.lua helpers (rule 7); P.build and P.commit run inside the caller's 'lab.cut.stage' and commit calls
-- and arm nothing; the ladder and the evictions arm their own names (section 3.4); the land reads are property reads
-- of the mod's own actor (no UFunction).
-- * The Piece (D10): an own actor (a deferred spawn of /Script/Engine.Actor), hidden at once, whose root is a
--   BoxComponent carrier (half extents BOX_HALF [P]; collision off from the add until the commit's trace-neutral
--   physics, review A5.1 F9); poseables on it: MaleThug (route 'body_copy') the body leader's
--   mesh, GuiChai heads (route 'meshhead') the mesh of each head component data/lab_pairs.lua lists; every limb is a
--   body copy. Materials are copied slot by slot from the source component. The copy never clones AI, abilities or
--   handlers (pieces-physics.md hard rule 1); cloned counts the components on the actor the mod did not add.
-- * The carrier sits at the cut joint moved BOX_HALF along the bone direction (the box covers the cut end and the
--   Piece's near half, so a head does not sink through the floor); its rotation is the identity, so the Piece-end Cap's
--   carrier seat (piece.joint, piece.out = -d) is in world axes.
-- * P13 proves the pose copy (spec M1a 4.2 item 2): GetSocketTransform world locations of the cut bone, its child and
--   up to three probe bones (P.POSE_PROBES) on the poseable and on the body leader, the Piece's BESIDE offset taken off,
--   before and after the copy. ok when the largest after-gap is at most POSE_OK_CM; 'pose_ambiguous' when every
--   before-gap is already under POSE_AMBIG_CM (the check cannot tell); 'pose_ref' when the gap did not shrink (the
--   copy left the reference pose); 'pose_off' when it shrank but stays over POSE_OK_CM. The gaps, the copy's outcome
--   and the poseable's own component-space gap (delta_cs_cm) are in the record. P14 reads the gaps again before its
--   writes ('pose_stale'). L.copy_pose runs only on the same SkinnedAsset or an equal readable Skeleton.
-- * P.commit, in the order of section 3.8 (P.COMMIT): the pose copied from the body leader (never a leader-posed
--   follower: L.copy_pose refuses one) before any hide; the body copy isolated in three writes (the root bone at
--   ISO_SCALE 0.001, never 0; the stump bone at its saved component-space location and rotation with scale 0.001; the
--   cut bone at its saved transform with scale 1; both saved from the LEADER, GetSocketTransform RTS_Component, never
--   from the poseable's own possibly unrefreshed array), then read back: stray_bones (TARGETS bones outside the cut subtree
--   above STRAY_SCALE) and seam_ok (the stump at its saved place and scale, the cut bone at scale 1), and a copy that
--   fails either is destroyed (hard rule 1); the carrier, then each poseable to its world transform; the caller's
--   hide; shown; trace-neutral physics (the copies collision off, the box PhysicsBody, MASS_KG, CCD); a velocity change
--   of SPEED along the sweep, else the attack direction, else up, plus UP, capped at VEL_CAP [P]. A failed step
--   destroys the actor (hidden instead after a failed P16) and answers its name and whether the hide ran.
-- * Lifecycle: piece_spawn per committed Piece (and per failed commit), piece_land at LAND_S game seconds (land_m and
--   settled_s from the first rest: speed under REST_SPEED uu/s for REST_S s; a stray 20 m down or 30 m sideways is
--   logged and evicted); a FIFO of FIFO Pieces and a life of LIFE_S game seconds, evicted one per frame under
--   'piece.destroy' once P16 passed (never after a failed P16). Mod-off hides the Piece actors (MO.feature live list,
--   kind 'actor'); the vanilla compare blocks the ladder and P.build; both hold every eviction until 'on'.
-- * Ladder (section 3.5) on kept-only 2 (the second lab_row keep_only corpse; the next one takes over if it goes),
--   after P1 and P2 passed and the Cap ladder (lab_cap) is done, each step at least the last proof's linger after it and
--   in a later frame: P10 hide.optim, P11 piece.spawn (an actor BESIDE_CM beside the corpse, box root, hidden), P12
--   piece.mesh, P13 piece.pose, P14 piece.isolate, P15 piece.phys (shown, simulated, a zero impulse), P16
--   piece.destroy (DESTROY_WAIT_S later). A need that did not pass skips the step; nothing is retried. A test actor lost
--   to a map load is rebuilt under the names that built it, without new proofs.
-- * The player beta (LAB.beta(); docs/research/beta-dismemberment-plan.md BD12). The dev and probe paths above stay as
--   they are; under the beta:
--   - Head components: a meshhead Piece copies the class row's head names (cut.class_row.head, data/cut_classes.lua),
--     else the pair's.
--   - C5: isolate writes the stump bone at the cut joint (the leader's component-space cut bone) with scale 0.001, so
--     the Piece's stump-side skin gathers under the Piece-end Cap. seam_ok compares against that joint. piece_spawn
--     logs iso_cm (the stump bone's read-back distance to the joint) and iso_ref_cm (where the dev write puts it).
--   - C5b: the root write goes to the cut joint as well (SetBoneTransformByName, the leader's root rotation, scale
--     0.001) instead of SetBoneScaleByName in place: scaled in place, every bone outside the stump's subtree (pelvis,
--     the spine, the other limbs) collapsed onto the root at the component origin (the body's feet), and skin weighted
--     partly to them (a sleeve on spine_05, a neck on the clavicles) stretched into a cone from the cut toward the
--     feet. The read-back: root_cm (the root to the joint), out_cm and out_bone (the farthest of the root, the stump's
--     parent and the outside TARGETS from the joint); over OUT_CM (or unread) the isolation fails 'spike: <bone>'.
--   - MC4, a cut with at_death true:
--     . The carrier starts at least GROUND_CM above the lower foot bone plus BOX_HALF.
--     . The commit reads the joint and every source's world transform again before the place (the pose is copied a
--       frame after the stage) and keeps the stage's offset of the carrier from the joint.
--     . v_body is the joint's move from the stage over the real seconds between, capped at VBODY_CAP.
--     . P.velocity: SPEED (head) or SPEED_LIMB along unit(sweep + 0.5 d), else unit(attack + 0.5 d), else d (the bone
--       direction out of the body), else up; plus UP and v_body; vz kept in VZ_MIN..VZ_MAX and the horizontal part
--       capped so that |v| <= VEL_CAP_DEATH. cut.dir, cut.speed and cut.up are not read on this path.
--   - cut.hold_show (lab_gib's kept hair): the commit skips 'show', so the Piece stays hidden (piece.held) and out of
--     P.live until P.show(piece).
--   - MC6, Pieces follow the body: bus lab_cut_gone with gone_why 'destroyed' or 'collected' and cut.kept not true
--     (or cut.expired true: lab_corpse let that kept body go) queues the Piece for eviction piece_linger_s game seconds
--     later (the knob, read then), why 'body_gone', one per frame under 'piece.destroy' as every eviction. A revive (no
--     gone_why) and a kept body keep the Piece under the FIFO (P.FIFO_BETA in the beta) and LIFE_S.
--   - A4, META.beta_extras: extra poseables built in the stage. Any failure drops only that poseable (destroyed,
--     piece_spawn extras {name, kind, why}):
--     . (a) own-pose skeletal leaders with the cut bone other than the body leader (MaleThug_Cloth_00, the row's
--       'copy'): posed from themselves, isolated with the same three writes read from themselves;
--     . (b) on a meshhead route, the row's hair and hat_mask followers on the leader's skeleton: posed from the leader.
--     . Never a row 'fall' or 'hair_cloth' name (lab_gib's), a cloth component or an own-pose follower (logged); at
--       most EXTRAS_MAX.
--   - P.resync(piece) copies every poseable's materials again from its live source (the dissolve's new MIDs);
--     P.probe(piece) reads the Piece for lab_fade's dissolve record. Neither arms anything: the callers do.
-- API (section 3.9): build(cut) -> piece | nil, why; commit(piece, cut[, hide]) -> true, info | nil, why, hid;
--   destroy(piece[, why]) -> true | false, why; ready(route) -> bool; live() the shown Piece actors; velocity(cut[,
--   piece]) -> v, src, capped; the beta's show(piece) -> true | nil, why, resync(piece) -> slots, why and
--   probe(piece[, opts]) -> { state, held, hidden, shared, resynced }; lifecycle init(A) shutdown() status() reset().
-- What the mock cannot prove: native faults, UE4SS marshalling on dff435dd, a root-less actor's spawn, real physics and
-- landing, rendering of the copies and their seam, the real isolation look (HD0, HD1b).
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

local P = { BOX_HALF = 12, MASS_KG = 5, SPEED = 450, UP = 150, VEL_CAP = 600,      -- cm, kg, uu/s [P]
    ISO_SCALE = 0.001, STRAY_SCALE = 0.01, SEAM_CM = 0.5,
    POSE_OK_CM = 2, POSE_AMBIG_CM = 5, POSE_PROBES = { 'hand_r', 'foot_l', 'spine_05' },      -- P13's proof (4.2 item 2)
    FIFO = 30, LIFE_S = 1080, LAND_S = 60, REST_SPEED = 30, REST_S = 1, LAND_DT = 0.25, LAND_PER_TICK = 4,
    LAND_MIN_M = 1.5, LAND_MAX_M = 4.5, STRAY_DOWN_CM = 2000, STRAY_SIDE_CM = 3000,
    BESIDE_CM = 100, DESTROY_WAIT_S = 2, SIG_RETRY_S = 10, MAT_MAX = 16, CHAIN_MAX = 32, KEEPS = 8,
    ACTOR = '/Script/Engine.Actor', BOX = '/Script/Engine.BoxComponent',
    POSEABLE = '/Script/Engine.PoseableMeshComponent', SKINNED = '/Script/Engine.SkinnedMeshComponent',
    COMP = '/Script/Engine.ActorComponent' }
-- The beta (BD12): the at-death launch (MC4: uu/s, the ground margin in cm) [P], the extras, the body_gone queue
P.VEL_CAP_DEATH, P.SPEED_LIMB, P.VBODY_CAP, P.VZ_MIN, P.VZ_MAX, P.GROUND_CM = 700, 300, 400, 50, 300, 2
P.EXTRAS_MAX, P.GONEQ, P.FEET = 4, 64, { 'foot_l', 'foot_r' }
-- The beta's FIFO: lab_corpse keeps every corpse up to corpse_max (60) with up to 3 Pieces each; the lab keeps FIFO
P.FIFO_BETA = 90
-- C5b: a collapsed bone (the root, the stump's parent, an outside TARGET) read back farther than this from the cut
-- joint (cm) fails the isolation as a spike [P]
P.OUT_CM = 1.0
P.CLOTH = '/Script/ChaosClothAssetEngine.ChaosClothComponent'
-- The TC-LAB-02 target bones (lab_rc.lua M.TARGETS, every candidate): stray_bones reads those outside the cut subtree
P.TARGETS = { 'head', 'neck_01', 'neck', 'upperarm_l', 'upperarm_r', 'lowerarm_l', 'forearm_l', 'lowerarm_r',
    'forearm_r', 'thigh_l', 'thigh_r', 'calf_l', 'calf_r' }
-- The commit order (section 3.8): each a function of COMMIT_FN below; a failed one is the why
P.COMMIT = { 'copy', 'isolate', 'place', 'hide', 'show', 'phys', 'launch' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua piece.*)
local N = {}
local F = {
    {"/Script/Engine.Actor", "bHidden"},
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SceneComponent", "AttachParent"},
    {"/Script/Engine.SceneComponent", "RelativeLocation"},
    {"/Script/Engine.SkinnedMeshComponent", "LeaderPoseComponent"},
}
P.N, P.F = N, F

local A = nil
local function new_state()
    return { init = false, n = 0, live = {}, evict = {}, land = {}, keeps = {}, rows = 0, lad = nil, last = nil,
        no_destroy = false, no_evict = false, built = 0, committed = 0, failed = 0, evicted = 0, trees = {},
        goneq = {}, bodyq = {}, body_gone = 0, gone_drop = 0, resyncs = 0, extras = 0, extras_drop = 0 }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function gnow() return S.game_time or 0 end
local function name_ok(s) return type(s) == 'string' and s ~= '' and s ~= 'None' end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function text(s)
    s = tostring(s)
    return #s > 160 and s:sub(1, 160) or s
end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
-- A proven class LAB.armed would run now: not struck, and not an inherited name after a stop (D4 refuses those)
local function usable(name)
    return LAB.proof(name) == true and not SENT.is_disabled(name) and not (LAB.inherited(name) and not LAB.inherit_ok())
end

-- ---------- plain vectors and transforms ----------
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function v3(v)
    if type(v) ~= 'table' then return nil end
    local x, y, z = v.x, v.y, v.z
    if x == nil and y == nil and z == nil then x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z') end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
local function add(a, b, k) k = k or 1 return { x = a.x + k * b.x, y = a.y + k * b.y, z = a.z + k * b.z } end
local function len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function unit(v)
    v = v3(v)
    if not v then return nil end
    local n = len(v)
    if n < 1e-6 then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
-- An engine FTransform (a returned struct, or the mock's table) as { loc, quat {w,x,y,z}, scale }; nil when unread
local function xf_of(t)
    local l, r, s = v3(ue.prop(t, 'Translation')), ue.prop(t, 'Rotation'), v3(ue.prop(t, 'Scale3D'))
    local q = { w = ue.prop(r, 'W'), x = ue.prop(r, 'X'), y = ue.prop(r, 'Y'), z = ue.prop(r, 'Z') }
    if not (l and s and num(q.w) and num(q.x) and num(q.y) and num(q.z)) then return nil end
    return { loc = l, quat = q, scale = s }
end
-- A full FTransform table (every field set: a missing one would read 0) from a plain one, moved by off
local function ft(x, off)
    local l = off and add(x.loc, off) or x.loc
    local q, s = x.quat or { w = 1, x = 0, y = 0, z = 0 }, x.scale or { x = 1, y = 1, z = 1 }
    return { Translation = ue.vec(l.x, l.y, l.z), Rotation = { X = q.x + 0.0, Y = q.y + 0.0, Z = q.z + 0.0,
        W = q.w + 0.0 }, Scale3D = ue.vec(s.x, s.y, s.z) }
end
-- GetSocketTransform(name, RTS_World 0) on a skinned component (a read; 'None' answers the component's own transform)
local function world_of(mesh, name)
    local ok, t = ue.call(mesh, 'GetSocketTransform', ue.fname(name or 'None'), 0)
    if not ok then return nil, text(t) end
    local x = xf_of(t)
    if not x then return nil, 'unread' end
    return x
end
-- The kept mod object, or nil (D24: the full name compared)
local function live(rec) return type(rec) == 'table' and ue.live_mod(rec) or nil end

-- ---------- the cut's bones and geometry (reads) ----------
local function pair_of(name) return (data('data.lab_pairs').pair or {})[name] or {} end
-- 'meshhead' for a head of a meshhead pair (D10), else 'body_copy' (MaleThug, and every limb)
local function route_of(cut)
    if cut.part == 'head' and pair_of(cut.pair).route == 'meshhead' then return 'meshhead' end
    return 'body_copy'
end
-- The bones of the TARGETS a mesh has outside the cut bone's subtree, walked up through GetParentBone once per mesh
-- asset and cut bone (st.trees): the bones stray_bones reads after the isolation
local function outside(mesh, bone)
    local asset = ue.prop(mesh, 'SkinnedAsset')
    local key = tostring(ue.full(asset) or ue.name(asset) or '?') .. '|' .. bone:lower()
    local c = st.trees[key]
    if c then return c end
    c = {}
    for _, b in ipairs(P.TARGETS) do
        if b:lower() ~= bone:lower() and ue.has_bone(mesh, b) then
            local cur, inside = b, false
            for _ = 1, P.CHAIN_MAX do
                cur = L.bone_parent(mesh, cur)
                if not cur then break end
                if cur:lower() == bone:lower() then inside = true break end
            end
            if not inside then c[#c + 1] = b end
        end
    end
    st.trees[key] = c
    return c
end
-- The victim actor of a cut while live (lab_cut passes the actor, else its LAB victim record)
-- (not being destroyed: spec M1a 4.1 item 2, gone is destroyed)
local function actor_of(cut)
    local a = ue.valid(cut.actor) and cut.actor or (cut.victim and LAB.live(cut.victim)) or nil
    if not a or LAB.destroying(a) == true then return nil end
    return a
end
-- The class row of a cut under the beta (data/cut_classes.lua, lab_cut's cut.class_row), else nil
local function row_of(cut)
    return LAB.beta() and type(cut.class_row) == 'table' and cut.class_row or nil
end
-- The head components of a meshhead Piece: the class row's head names under the beta, else the pair's
local function head_names(cut)
    local row = row_of(cut)
    if row and type(row.head) == 'table' and row.head[1] ~= nil then return row.head end
    return pair_of(cut.pair).head_comps or {}
end
-- The source components: the body leader, or each head component of a meshhead pair by name. { {comp, asset, name} }
local function sources(actor, leader, cut, route)
    if route == 'body_copy' then
        local a = ue.prop(leader, 'SkinnedAsset')
        if not ue.valid(a) then return nil, 'no_asset' end
        return { { comp = leader, asset = a, name = 'body' } }
    end
    local out, list = {}, nil                           -- one K2_GetComponentsByClass for every name
    for _, n in ipairs(head_names(cut)) do
        local hit
        list = list or ue.components(actor, P.SKINNED)
        for _, c in ipairs(list) do if ue.name(c) == n then hit = c break end end
        local a = hit and ue.prop(hit, 'SkinnedAsset')
        if not ue.valid(a) then return nil, 'no_head_comp:' .. n end
        out[#out + 1] = { comp = hit, asset = a, name = n }
    end
    if not out[1] then return nil, 'no_head_comp' end
    return out
end
-- The cut joint J and its child in world space, d = the unit J -> child (up when they meet), the carrier's place
-- at = J + d x BOX_HALF, and each source's world transform. g | nil, why
local function geometry(leader, cut, srcs)
    local j, wj = world_of(leader, cut.bone)
    if not j then return nil, 'joint: ' .. tostring(wj) end
    local c, wc = world_of(leader, cut.child)
    if not c then return nil, 'child: ' .. tostring(wc) end
    local d = unit(add(c.loc, j.loc, -1)) or { x = 0, y = 0, z = 1 }
    for _, s in ipairs(srcs) do
        local x, wx = world_of(s.comp, nil)
        if not x then return nil, 'source: ' .. tostring(wx) end
        s.xf = x
    end
    return { j = j.loc, d = d, at = add(j.loc, d, P.BOX_HALF) }
end
-- MC4 (the beta's at-death cut): the carrier's z at least the lower foot bone's world z + BOX_HALF + GROUND_CM, so a
-- Piece cut near the floor never starts inside it. g.ground 'clamped' | 'ok' | 'unread' (no foot bone read), g.foot_z
local function ground(leader, g)
    local low
    for _, b in ipairs(P.FEET) do
        local x = ue.has_bone(leader, b) and world_of(leader, b) or nil
        if x and (low == nil or x.loc.z < low) then low = x.loc.z end
    end
    if low == nil then g.ground = 'unread' return end
    local z = low + P.BOX_HALF + P.GROUND_CM
    g.foot_z, g.ground = low, 'ok'
    if g.at.z < z then g.at, g.ground = { x = g.at.x, y = g.at.y, z = z }, 'clamped' end
end

-- ---------- building (inside the caller's armed stage, or a ladder step) ----------
-- The actor, hidden at once, and its box root at the identity (FinishAddComponent: the place is written at the
-- commit). true | nil, why; piece.actor and piece.carrier as they come
local function spawn(piece, at)
    local cls = ue.class(P.ACTOR)
    if not cls then return nil, 'no_actor_class' end
    local a, why, half = US.spawn_deferred(cls, ue.xform(ue.vec(at.x, at.y, at.z)), {})
    if not a then
        piece.rec = half and ue.keep_mod(half) or nil      -- an unfinished actor still goes (fail)
        return nil, 'spawn: ' .. text(why)
    end
    piece.actor, piece.rec = a, ue.keep_mod(a)
    if not piece.rec then return nil, 'unread' end
    local ok, wh = US.set_actor_hidden(a, true)
    if not ok then return nil, 'hide: ' .. text(wh) end
    -- collision off from the add (review A5.1 F9): a shape blocks by default, and the carrier waits hidden until the
    -- commit; physics() turns on what the Piece needs (ue.trace_neutral, then simulate). A refused call fails the build
    -- and the actor goes with its box
    local box, wb = ue.add_component(a, P.BOX, { no_collision = true })
    if not box then return nil, 'box: ' .. text(wb) end
    piece.carrier, piece.box = box, ue.keep_mod(box)
    local okb, we = L.box_extent(box, { x = P.BOX_HALF, y = P.BOX_HALF, z = P.BOX_HALF })
    if not okb then return nil, 'extent: ' .. text(we) end
    piece.ours = { box }
    return true
end
-- Material slot i of src into the poseable p, for every slot (at most MAT_MAX). The slots copied, a why when one failed
local function copy_mats(p, src)
    local ok, n = ue.call(src, 'GetNumMaterials')
    if not ok or math.type(n) ~= 'integer' then return 0, 'mats_unread' end
    local done = 0
    for i = 0, math.min(n, P.MAT_MAX) - 1 do
        local okg, m = ue.call(src, 'GetMaterial', i)
        if okg and ue.valid(m) and ue.call(p, 'SetMaterial', i, m) then done = done + 1 end
    end
    return done, done < math.min(n, P.MAT_MAX) and 'mat_slot' or nil
end
-- One poseable per source: the source's mesh (SkinnedAsset read back), decals refused again, the materials copied
local function meshes(piece, srcs)
    piece.poses, piece.mats = {}, 0
    for _, s in ipairs(srcs) do
        local p, w = ue.add_component(piece.actor, P.POSEABLE)
        if not p then return nil, 'poseable: ' .. text(w) end
        piece.ours[#piece.ours + 1] = p
        local ok, wa = L.set_asset(p, s.asset, true)
        if not ok then return nil, 'asset: ' .. text(wa) end
        ue.refuse_decals(p, P.POSEABLE)
        local n, wm = copy_mats(p, s.comp)
        piece.mats, piece.mat_err = piece.mats + n, piece.mat_err or wm
        piece.poses[#piece.poses + 1] = { p = p, rec = ue.keep_mod(p), src = s.comp, xf = s.xf, name = s.name,
            src_rec = LAB.beta() and ue.keep(s.comp) or nil }  -- the beta's resync and refresh find the source again
    end
    piece.poseable = piece.poses[1] and piece.poses[1].p or nil
    return true
end

-- ---------- the beta's extra poseables (A4, META.beta_extras; built in the stage, dropped one by one) ----------
local function leader_of(c)
    local lp = ue.get(c, 'LeaderPoseComponent')
    return ue.weak(lp)
end
local function set_of(...)
    local out = {}
    for i = 1, select('#', ...) do
        local list = select(i, ...)
        for _, n in ipairs(type(list) == 'table' and list or {}) do out[n] = true end
    end
    return out
end
-- An extra that failed: its poseable destroyed through the Piece actor (hidden when that is refused), the why logged.
-- Never fails the Piece
local function drop_extra(piece, e, why)
    if e.dropped then return end
    e.dropped = text(why)
    st.extras_drop = st.extras_drop + 1
    local p = live(e.rec)
    if p and not ue.destroy(p) then ue.set_hidden(p, true) end
end
-- The extras' sources (A4): (a) own-pose leaders with the cut bone but the body leader and the sources; (b) on a
-- meshhead route, the class row's hair and hat_mask components that follow a leader on the body leader's skeleton.
-- Row 'fall' and 'hair_cloth' names and cloth components are lab_gib's and never copied. -> { e }, { {name, why} }
local function extra_srcs(actor, leader, cut, route, srcs)
    local row, out, skipped = row_of(cut) or {}, {}, {}
    local never, taken = set_of(row.fall, row.hair_cloth), {}
    for _, s in ipairs(srcs) do taken[ue.name(s.comp) or '?'] = true end
    taken[ue.name(leader) or '?'] = true
    local function add_src(c, n, kind, pose, iso)
        if #out >= P.EXTRAS_MAX then skipped[#skipped + 1] = { name = n, why = 'max' } return end
        local a = ue.prop(c, 'SkinnedAsset')
        if not ue.valid(a) then skipped[#skipped + 1] = { name = n, why = 'no_asset' } return end
        taken[n] = true
        out[#out + 1] = { comp = c, asset = a, name = n, kind = kind, pose = pose, iso = iso, src_rec = ue.keep(c) }
    end
    for _, c in ipairs(ue.leaders_with_bone(actor, cut.bone)) do            -- (a)
        local n = ue.name(c) or '?'
        if not taken[n] and not ue.same(c, leader) then
            if never[n] then skipped[#skipped + 1] = { name = n, why = 'lab_gib' }
            elseif ue.is_a(c, P.CLOTH) == true then skipped[#skipped + 1] = { name = n, why = 'cloth' }
            else add_src(c, n, 'own', c, true) end
        end
    end
    if route ~= 'meshhead' then return out, skipped end
    local names, list = {}, nil                         -- (b): one K2_GetComponentsByClass for every name
    for _, n in ipairs(type(row.hair) == 'table' and row.hair or {}) do names[#names + 1] = n end
    for _, n in ipairs(type(row.hat_mask) == 'table' and row.hat_mask or {}) do names[#names + 1] = n end
    for _, n in ipairs(names) do
        if not taken[n] and not never[n] then
            if not list then list = ue.components(actor, P.SKINNED) end
            local hit
            for _, c in ipairs(list) do if ue.name(c) == n then hit = c break end end
            if not hit then skipped[#skipped + 1] = { name = n, why = 'missing' }
            elseif ue.is_a(hit, P.CLOTH) == true then skipped[#skipped + 1] = { name = n, why = 'cloth' }
            elseif not ue.valid(leader_of(hit)) then skipped[#skipped + 1] = { name = n, why = 'own_pose' }
            elseif not L.same_skeleton(hit, leader) then skipped[#skipped + 1] = { name = n, why = 'skeleton_differs' }
            else add_src(hit, n, 'follower', leader, false) end
        end
    end
    return out, skipped
end
-- The extras' poseables, hidden with the actor: the source's mesh and materials, its world transform, and for an
-- isolated one the TARGETS outside the cut subtree on the source. piece.extras { e }, piece.skipped { {name, why} }
local function extras(piece, actor, leader, cut, route, srcs)
    local list, skipped = extra_srcs(actor, leader, cut, route, srcs)
    piece.extras, piece.skipped = list, skipped
    for _, e in ipairs(list) do
        local p, w = ue.add_component(piece.actor, P.POSEABLE)
        if not p then
            drop_extra(piece, e, 'poseable: ' .. text(w))
        else
            piece.ours[#piece.ours + 1] = p
            e.p, e.rec = p, ue.keep_mod(p)
            local ok, wa = L.set_asset(p, e.asset, true)
            local x, wx = nil, nil
            if ok then x, wx = world_of(e.comp, nil) end
            if not ok then drop_extra(piece, e, 'asset: ' .. text(wa))
            elseif not x then drop_extra(piece, e, 'source: ' .. text(wx))
            else
                ue.refuse_decals(p, P.POSEABLE)
                e.xf, e.mats, e.mat_err = x, copy_mats(p, e.comp)
                if e.iso then e.outside = outside(e.comp, cut.bone) end
                st.extras = st.extras + 1
            end
        end
    end
end
-- The extras still on the Piece, each with its live poseable: an iterator of e, p (a gone poseable drops its extra)
local function each_extra(piece)
    local list, i = piece.extras or {}, 0
    return function()
        while true do
            i = i + 1
            local e = list[i]
            if e == nil then return nil end
            if not e.dropped then
                local p = live(e.rec)
                if p then return e, p end
                drop_extra(piece, e, 'gone')
            end
        end
    end
end

-- ---------- destroy (C4: the Piece-end Cap is a component of the actor and goes with it) ----------
local land_rec                                          -- the piece_land record (the landing section below)
local function unlist(piece)
    for i, x in ipairs(st.live) do if x == piece then table.remove(st.live, i) break end end
    st.land[piece] = nil
end
-- The actor goes (K2_DestroyActor); after a failed P16 it is hidden instead. A Piece still waiting for its landing
-- gets its piece_land first (why: the eviction's word, else 'destroyed'). true | false, why
function P.destroy(piece, why)
    if type(piece) ~= 'table' then return false, 'bad_piece' end
    local l = st.land[piece]
    if l then land_rec(piece, l, why or 'destroyed') end
    unlist(piece)
    piece.state, piece.end_why = 'destroyed', piece.end_why or why
    piece.end_t, piece.live_n = now(), #st.live         -- lab_fade's Piece lag (the beta's dissolve record)
    local a = live(piece.rec)
    if not a then return true end
    if st.no_destroy then
        local ok, w = US.set_actor_hidden(a, true)
        return ok == true, ok and 'hidden' or w
    end
    local ok, w = US.destroy_actor(a)
    if not ok then
        US.set_actor_hidden(a, true)
        return false, w
    end
    return true
end
local function fail(piece, why)
    st.failed = st.failed + 1
    P.destroy(piece, why)
    piece.state = 'failed'
    return nil, why
end

-- Pieces ready for a route (D30, section 3.5: P11-P15 proven, none struck); 'meshhead' needs no isolation
function P.ready(route)
    for _, n in ipairs({ 'piece.spawn', 'piece.mesh', 'piece.pose', 'piece.phys' }) do
        if not usable(n) then return false end
    end
    return route == 'meshhead' or usable('piece.isolate')
end
-- The Piece of a cut, built hidden (section 3.8 F0+2). cut = { id, pair, part, row, actor (or victim), leader (the
-- body leader), bone, child, stump; sweep_dir, attack_dir, dir, speed, up for the launch }. piece | nil, why
function P.build(cut)
    if not st.init then return nil, 'not_init' end
    if type(cut) ~= 'table' or cut.id == nil or type(cut.part) ~= 'string' then return nil, 'bad_cut' end
    if not MODOFF.enabled('lab_piece') then return nil, 'modoff' end
    local route = route_of(cut)
    if not P.ready(route) then return nil, 'pieces_off' end
    local actor = actor_of(cut)
    if not actor then return nil, 'gone' end
    local leader = ue.valid(cut.leader) and cut.leader or ue.prop(actor, 'Mesh')
    if not (ue.valid(leader) and name_ok(cut.bone) and name_ok(cut.child)) then return nil, 'no_pose' end
    if route == 'body_copy' and not name_ok(cut.stump) then return nil, 'no_pose' end
    local srcs, ws = sources(actor, leader, cut, route)
    if not srcs then return nil, ws end
    local g, wg = geometry(leader, cut, srcs)
    if not g then return nil, wg end
    local death = LAB.beta() and cut.at_death == true
    if death then ground(leader, g) end                 -- MC4: never below the feet
    st.n = st.n + 1
    local piece = { n = st.n, id = cut.id, pair = cut.pair, part = cut.part, row = cut.row, route = route,
        bone = cut.bone, child = cut.child, stump = cut.stump, leader = leader, at = g.at, d = g.d,
        joint = { x = -g.d.x * P.BOX_HALF, y = -g.d.y * P.BOX_HALF, z = -g.d.z * P.BOX_HALF },
        out = { x = -g.d.x, y = -g.d.y, z = -g.d.z }, iso = pair_of(cut.pair).iso, state = 'building' }
    if LAB.beta() then piece.rank, piece.class = cut.rank, cut.class end
    if death then                                       -- MC4: the stage's joint, its time and the carrier's offset
        piece.at_death, piece.j0, piece.t_stage, piece.ground, piece.foot_z = true, g.j, now(), g.ground, g.foot_z
        piece.off, piece.joint = add(g.at, g.j, -1), add(g.j, g.at, -1)
    end
    local ok, w = spawn(piece, g.at)
    if not ok then return fail(piece, w) end
    ok, w = meshes(piece, srcs)
    if not ok then return fail(piece, w) end
    if LAB.beta() and META.beta_extras == true then extras(piece, actor, leader, cut, route, srcs) end
    piece.outside = route == 'body_copy' and outside(leader, cut.bone) or {}
    local n = 0
    for _, c in ipairs(ue.components(piece.actor, P.COMP)) do
        local mine = false
        for _, o in ipairs(piece.ours) do if ue.same(c, o) then mine = true end end
        if not mine then n = n + 1 end
    end
    piece.cloned, piece.state = n, 'built'
    st.built = st.built + 1
    return piece
end

-- ---------- the commit steps ----------
local function root_of(piece, p)
    if name_ok(piece.iso) then return piece.iso end
    local ok, v = ue.call(p, 'GetBoneName', 0)
    local s = ok and ue.str(v) or nil
    return name_ok(s) and s or nil
end
-- D10's three writes on the body copy p, the stump and cut bone poses read from the leader (RTS_Component, before any
-- write; spec M1a 4.2 item 2), then the read-back. true | nil, why ('read', 'root', 'stump', 'cut', 'stray', 'seam' with the helper's why)
-- The beta's C5: the stump bone goes to the cut joint (c0's location), not its own; iso_cm and iso_ref_cm (cm) logged.
-- An extra poseable (A4) passes a view of the Piece whose leader is the extra's own source and outside its own bones
local function isolate(piece, p)
    local root = root_of(piece, p)
    if not root then return nil, 'no_root' end
    local s0, w1 = L.bone_component_xform(piece.leader, piece.stump)
    local c0, w2 = L.bone_component_xform(piece.leader, piece.bone)
    if not (s0 and c0) then return nil, 'read: ' .. tostring(w1 or w2) end
    local beta = LAB.beta()
    local at = beta and c0.loc or s0.loc
    local ok, w
    if beta then                                        -- the root to the joint too: no bone stays at the origin
        local r0 = L.bone_component_xform(piece.leader, root)
        ok, w = L.bone_xform_set(p, root, { loc = at, quat = r0 and r0.quat or s0.quat, scale = P.ISO_SCALE })
    else
        ok, w = L.bone_scale(p, root, P.ISO_SCALE)
    end
    if not ok then return nil, 'root: ' .. tostring(w) end
    ok, w = L.bone_xform_set(p, piece.stump, { loc = at, quat = s0.quat, scale = P.ISO_SCALE })
    if not ok then return nil, 'stump: ' .. tostring(w) end
    ok, w = L.bone_xform_set(p, piece.bone, { loc = c0.loc, quat = c0.quat, scale = 1 })
    if not ok then return nil, 'cut: ' .. tostring(w) end
    local stray, far, far_b = {}, 0, nil
    local function reach(b, x)                          -- the beta: the farthest collapsed bone from the joint
        local d = x and len(add(x.loc, at, -1)) or math.huge
        if d >= far then far, far_b = d, b end
    end
    for _, b in ipairs(piece.outside or {}) do
        local x = L.bone_xform_get(p, b)
        if x and x.scale.x > P.STRAY_SCALE then stray[#stray + 1] = b end
        if beta then reach(b, x) end
    end
    local s1, c1 = L.bone_xform_get(p, piece.stump), L.bone_xform_get(p, piece.bone)
    piece.stray_bones, piece.stray = #stray, stray[1] and stray or nil
    piece.seam_ok = s1 ~= nil and c1 ~= nil and len(add(s1.loc, at, -1)) <= P.SEAM_CM
        and math.abs(s1.scale.x - P.ISO_SCALE) < P.ISO_SCALE * 0.01 and math.abs(c1.scale.x - 1) < 1e-3
    if beta then                                        -- the isolation read-back probe (C5) and the spike's (C5b)
        piece.iso_cm = s1 and r1(len(add(s1.loc, c0.loc, -1))) or 'unread'
        piece.iso_ref_cm = r1(len(add(s0.loc, c0.loc, -1)))
        local x0 = L.bone_xform_get(p, root)
        reach(root, x0)
        piece.root_cm = x0 and r1(len(add(x0.loc, at, -1))) or 'unread'
        local up = L.bone_parent(p, piece.stump)
        if up then reach(up, L.bone_xform_get(p, up)) end
        piece.out_cm = far < math.huge and r1(far) or 'unread'
        piece.out_bone = far_b
    end
    if #stray > 0 then return nil, 'stray' end
    if not piece.seam_ok then return nil, 'seam' end
    if beta and not (far <= P.OUT_CM) then return nil, 'spike: ' .. tostring(far_b) end
    return true
end
-- An isolated extra (A4): the same three writes, the poses read from the extra's own source (it is posed from itself)
local function isolate_extra(piece, e, p)
    local src = ue.live(e.src_rec)
    if not src then return nil, 'gone' end
    local view = { leader = src, stump = piece.stump, bone = piece.bone, iso = piece.iso, outside = e.outside }
    local ok, w = isolate(view, p)
    e.stray_bones, e.seam_ok, e.iso_cm = view.stray_bones, view.seam_ok, view.iso_cm
    e.out_cm, e.out_bone = view.out_cm, view.out_bone
    return ok, w
end
-- The carrier to its place, then each poseable to its source's world transform (both moved by off). true | nil, why
local function place(piece, off)
    local box = live(piece.box)
    if not box then return nil, 'gone' end
    local ok, w = ue.call(box, 'K2_SetWorldTransform', ft({ loc = piece.at }, off), false, {}, true)
    if not ok then return nil, text(w) end
    for _, q in ipairs(piece.poses) do
        local p = live(q.rec)
        if not p then return nil, 'gone' end
        ok, w = ue.call(p, 'K2_SetWorldTransform', ft(q.xf, off), false, {}, true)
        if not ok then return nil, text(w) end
    end
    for e, p in each_extra(piece) do                    -- the beta's extras: a failed one is dropped alone
        local oke, we = ue.call(p, 'K2_SetWorldTransform', ft(e.xf, off), false, {}, true)
        if not oke then drop_extra(piece, e, 'place: ' .. text(we)) end
    end
    return true
end
-- MC4 at the commit of an at-death Piece (reads only): the joint and every source's world transform again, the
-- carrier at the new joint plus the stage's offset, and v_body = the joint's move over the real seconds since the
-- stage, capped at VBODY_CAP. A read that fails keeps the stage's value (piece.refresh says which)
local function refresh(piece)
    local j, wj = world_of(piece.leader, piece.bone)
    if not j then piece.refresh = 'joint: ' .. text(wj) return end
    local miss = nil
    for _, q in ipairs(piece.poses) do
        local x = world_of(ue.live(q.src_rec) or q.src, nil)
        if x then q.xf = x else miss = miss or q.name end
    end
    for e in each_extra(piece) do
        local x = world_of(ue.live(e.src_rec), nil)
        if x then e.xf = x else miss = miss or e.name end
    end
    piece.refresh = miss and ('source: ' .. tostring(miss)) or 'ok'
    piece.at = add(j.loc, piece.off)
    local dt = now() - (piece.t_stage or now())
    piece.vb_dt = r1(dt * 1000)
    if dt < 1e-3 then return end                        -- no time passed: no body speed read
    local v = add(j.loc, piece.j0, -1)
    v = { x = v.x / dt, y = v.y / dt, z = v.z / dt }
    local n = len(v)
    piece.vb_raw = r1(n)
    if n > P.VBODY_CAP then v = { x = v.x * P.VBODY_CAP / n, y = v.y * P.VBODY_CAP / n, z = v.z * P.VBODY_CAP / n } end
    piece.v_body = v
end
-- Trace-neutral physics: every copy collision off (no body of its own), the box PhysicsBody (ue.trace_neutral, before
-- the simulate), then mobility, mass, CCD and simulate (L.physics_on). true | nil, why
local function physics(piece)
    for _, q in ipairs(piece.poses) do
        local p = live(q.rec)
        if not (p and ue.call(p, 'SetCollisionEnabled', 0)) then return nil, 'copy_collision' end
    end
    for e, p in each_extra(piece) do                    -- the beta's extras: a failed one is dropped alone
        if not ue.call(p, 'SetCollisionEnabled', 0) then drop_extra(piece, e, 'collision') end
    end
    local box = live(piece.box)
    if not (box and ue.trace_neutral(box)) then return nil, 'trace_neutral' end
    return L.physics_on(box, P.MASS_KG, true)
end
-- MC4, the beta's at-death launch (pure): SPEED for a head, SPEED_LIMB for a limb, along unit(sweep + 0.5 d), else
-- unit(attack + 0.5 d), else d, else up (d: piece.d, the bone direction out of the body, when a Piece is given), plus
-- UP and piece.v_body; vz kept in VZ_MIN..VZ_MAX, then the horizontal part shortened so that |v| <= VEL_CAP_DEATH.
-- v, src ('sweep', 'attack', 'bone', 'up'), capped
local function death_velocity(cut, piece)
    local dout = type(piece) == 'table' and unit(piece.d) or nil
    local function mix(a)
        local u = unit(a)
        if u and dout then u = unit(add(u, dout, 0.5)) end
        return u
    end
    local d, src = mix(cut.sweep_dir), 'sweep'
    if not d then d, src = mix(cut.attack_dir), 'attack' end
    if not d and dout then d, src = dout, 'bone' end
    if not d then d, src = { x = 0.0, y = 0.0, z = 1.0 }, 'up' end
    local s = cut.part == 'head' and P.SPEED or P.SPEED_LIMB
    local v = { x = d.x * s, y = d.y * s, z = d.z * s + P.UP }
    local vb = type(piece) == 'table' and v3(piece.v_body) or nil
    if vb then v = add(v, vb) end
    v.z = math.max(P.VZ_MIN, math.min(P.VZ_MAX, v.z)) + 0.0
    local h, hmax, capped = math.sqrt(v.x * v.x + v.y * v.y), math.sqrt(P.VEL_CAP_DEATH ^ 2 - v.z * v.z), false
    if h > hmax then
        local k = hmax / h * (1 - 1e-9)
        v.x, v.y, capped = v.x * k, v.y * k, true
    end
    return v, src, capped
end
-- The launch velocity of a cut: SPEED (cut.speed) along cut.dir, else the sweep, else the attack direction, else up,
-- plus UP (cut.up) on Z; capped at VEL_CAP by L.velocity_change. Under the beta an at-death cut takes MC4's rule
-- (death_velocity above; piece optional: its bone direction and v_body). v, src[, capped]
function P.velocity(cut, piece)
    cut = type(cut) == 'table' and cut or {}
    if LAB.beta() and cut.at_death == true then return death_velocity(cut, piece) end
    local d, src = unit(cut.dir), 'dir'
    if not d then d, src = unit(cut.sweep_dir), 'sweep' end
    if not d then d, src = unit(cut.attack_dir), 'attack' end
    if not d then d, src = { x = 0, y = 0, z = 1 }, 'up' end
    local s, up = tonumber(cut.speed) or P.SPEED, tonumber(cut.up) or P.UP
    return { x = d.x * s, y = d.y * s, z = d.z * s + up }, src
end
local COMMIT_FN = {
    copy = function(piece, cut)
        for _, q in ipairs(piece.poses) do
            local p = live(q.rec)
            if not p then return nil, 'gone' end
            local ok, w = L.copy_pose(p, piece.leader)
            if not ok then return nil, w end
        end
        for e, p in each_extra(piece) do                -- the beta's extras: own-pose from the source, else the leader
            local ok, w = L.copy_pose(p, e.kind == 'own' and ue.live(e.src_rec) or piece.leader)
            if not ok then drop_extra(piece, e, 'copy: ' .. text(w)) end
        end
        return true
    end,
    isolate = function(piece)
        for e, p in each_extra(piece) do
            if e.iso then
                local ok, w = isolate_extra(piece, e, p)
                if not ok then drop_extra(piece, e, 'isolate: ' .. text(w)) end
            end
        end
        if piece.route ~= 'body_copy' then return true end
        local p = live(piece.poses[1].rec)
        if not p then return nil, 'gone' end
        return isolate(piece, p)
    end,
    place = function(piece)
        if piece.at_death then refresh(piece) end       -- the beta's at-death Piece (MC4)
        return place(piece, nil)
    end,
    hide = function(piece, cut, hide)
        if hide == nil then return true end
        piece.hid = true
        local ok, w = hide()
        if not ok then return nil, tostring(w) end
        return true
    end,
    show = function(piece, cut)
        if LAB.beta() and type(cut) == 'table' and cut.hold_show == true then  -- lab_gib shows it (P.show)
            piece.held = true
            return true
        end
        local a = live(piece.rec)
        if not a then return nil, 'gone' end
        return US.set_actor_hidden(a, false)
    end,
    phys = function(piece) return physics(piece) end,
    launch = function(piece, cut)
        local v, src, capped0 = P.velocity(cut, piece)
        local box = live(piece.box)
        if not box then return nil, 'gone' end
        local ok, sent, capped = L.velocity_change(box, v, piece.at_death and P.VEL_CAP_DEATH or P.VEL_CAP)
        if not ok then return nil, sent end
        piece.vel, piece.vel_src, piece.capped = sent, src, capped or capped0 == true
        return true
    end,
}
-- The piece_spawn record (section 3.1), forced
local function r1v(v) return v and { x = r1(v.x), y = r1(v.y), z = r1(v.z) } or nil end
-- The beta's fields (BD12): rank and class, the isolation read-back (C5), the at-death launch inputs (MC4: v_body
-- capped and raw, the stage-to-commit ms, the refresh, the carrier z against the lower foot), held, the extras
local function beta_fields(piece, f)
    f.rank, f.class, f.held = piece.rank, piece.class, piece.held
    f.iso_cm, f.iso_ref_cm = piece.iso_cm, piece.iso_ref_cm
    f.out_cm, f.out_bone, f.root_cm = piece.out_cm, piece.out_bone, piece.root_cm
    if piece.at_death then
        f.at_death, f.v_body, f.vb_raw, f.vb_dt_ms = true, r1v(piece.v_body), piece.vb_raw, piece.vb_dt
        f.refresh, f.ground, f.foot_z, f.z = piece.refresh, piece.ground, piece.foot_z and r1(piece.foot_z),
            piece.at and r1(piece.at.z)
    end
    local ex = {}
    for _, e in ipairs(piece.extras or {}) do
        ex[#ex + 1] = { name = e.name, kind = e.kind, ok = not e.dropped, why = e.dropped, mats = e.mats,
            seam_ok = e.seam_ok, stray_bones = e.stray_bones, iso_cm = e.iso_cm, out_cm = e.out_cm,
            out_bone = e.out_bone }
    end
    for _, s in ipairs(piece.skipped or {}) do
        ex[#ex + 1] = { name = s.name, ok = false, why = s.why, kind = 'skip' }
    end
    if ex[1] then f.extras = ex end
    return f
end
local function spawn_rec(piece, ok, why)
    local v = piece.vel
    local f = { id = piece.id, part = piece.part, pair = piece.pair, ok = ok, why = why,
        mesh_route = piece.route, stray_bones = piece.stray_bones or (piece.route == 'meshhead' and 0 or 'unread'),
        seam_ok = piece.seam_ok == nil and 'unread' or piece.seam_ok, stray = piece.stray, cloned = piece.cloned,
        row = piece.row, mats = piece.mats, mat_err = piece.mat_err, vel_src = piece.vel_src, capped = piece.capped,
        vel = v and { x = r1(v.x), y = r1(v.y), z = r1(v.z) } or nil, live = #st.live, ladder = piece.ladder }
    if LAB.beta() then beta_fields(piece, f) end
    LAB.rec('piece_spawn', f, true)
end
-- The commit (section 3.8 F0+3), inside the caller's commit call: the steps of P.COMMIT in order; hide (optional)
-- is the caller's hide, run between the place and the show. true, { vel, capped, src } | nil, why ('<step>' or
-- '<step>: <why>'), hid (whether the hide ran: the caller unhides). A failure destroys the Piece
function P.commit(piece, cut, hide)
    if type(piece) ~= 'table' or piece.state ~= 'built' then return nil, 'bad_piece', false end
    cut = type(cut) == 'table' and cut or {}
    if not live(piece.rec) then return nil, 'gone', false end
    for _, step in ipairs(P.COMMIT) do
        local okc, ok, w = pcall(COMMIT_FN[step], piece, cut, hide)   -- a raised step (the caller's hide) fails too
        if not okc then ok, w = nil, ok end
        if not ok then
            local why = w ~= nil and (step .. ': ' .. text(w)) or step
            fail(piece, why)
            spawn_rec(piece, false, why)
            return nil, why, piece.hid == true
        end
    end
    piece.state, piece.t0 = 'live', gnow()
    st.committed = st.committed + 1
    st.live[#st.live + 1] = piece
    st.land[piece] = { t0 = gnow(), from = piece.at, last = nil, next_t = gnow() + P.LAND_DT }
    spawn_rec(piece, true)
    return true, { vel = piece.vel, capped = piece.capped, src = piece.vel_src }
end
-- The shown Piece actors (live, not hidden by us), the ladder's shown test Piece included: MO.feature's live list. A
-- held Piece (the beta's cut.hold_show, not shown yet) is left out: 'on' must not show it
function P.live()
    local out = {}
    local function put(piece)
        local a = live(piece and piece.rec)
        if a then out[#out + 1] = { obj = a, name = ue.name(a), kind = 'actor' } end
    end
    for _, piece in ipairs(st.live) do if not piece.held then put(piece) end end
    local lad = st.lad
    if lad and lad.piece and lad.piece.shown then put(lad.piece) end
    return out
end

-- ---------- the beta's Piece API for lab_gib and lab_fade (BD12; each arms nothing: the caller arms) ----------
-- A held Piece shown (lab_gib, once the kept hair is on; inside its 'hair.keep'): SetActorHiddenInGame false, then it
-- joins P.live. A Piece already shown answers true. true | nil, why ('bad_piece', 'gone', the helper's why)
function P.show(piece)
    if type(piece) ~= 'table' or piece.state ~= 'live' then return nil, 'bad_piece' end
    if not piece.held then return true end
    local a = live(piece.rec)
    if not a then return nil, 'gone' end
    local ok, w = US.set_actor_hidden(a, false)
    if not ok then return nil, text(w) end
    piece.held, piece.shown_g = nil, gnow()
    return true
end
-- MC7's resync (lab_fade, inside its 'piece.mesh'): every poseable's materials copied again, slot by slot, from its
-- live source (the corpse's new dissolve MIDs, so the Piece dissolves with the body). The slots copied, the first why
-- ('bad_piece', 'gone', 'mats_unread', 'mat_slot')
function P.resync(piece)
    if type(piece) ~= 'table' or piece.state ~= 'live' then return 0, 'bad_piece' end
    local done, why = 0, nil
    local function one(rec, src_rec)
        local p, src = live(rec), ue.live(src_rec)
        if not (p and src) then why = why or 'gone' return end
        local n, w = copy_mats(p, src)
        done, why = done + n, why or w
    end
    for _, q in ipairs(piece.poses or {}) do one(q.rec, q.src_rec) end
    for e in each_extra(piece) do one(e.rec, e.src_rec) end
    piece.resynced = (piece.resynced or 0) + 1
    st.resyncs = st.resyncs + 1
    return done, why
end
-- The Piece for a reader (lab_fade's dissolve record, inside its 'lab.read.dissolve'): reads only. { state, held,
-- hidden (the actor's bHidden), shared (the first poseable's slot 0 is its source's slot 0 now), resynced };
-- 'unread' where a read gave nothing. opts.no_src: the source is not read (a corpse being destroyed)
function P.probe(piece, opts)
    if type(piece) ~= 'table' then return nil end
    local r = { state = piece.state, held = piece.held == true, resynced = piece.resynced or 0, hidden = 'unread',
        shared = 'unread' }
    local a = live(piece.rec)
    local h = a and US.actor_hidden(a)
    if h ~= nil then r.hidden = h end
    local q = (piece.poses or {})[1]
    local p = q and live(q.rec)
    local src = p and not (opts and opts.no_src) and ue.live(q.src_rec) or nil
    if p and src then
        local ok1, m1 = ue.call(p, 'GetMaterial', 0)
        local ok2, m2 = ue.call(src, 'GetMaterial', 0)
        if ok1 and ok2 and ue.valid(m1) and ue.valid(m2) then r.shared = ue.same(m1, m2) end
    end
    return r
end

-- ---------- the landing (property reads only: the box root's RelativeLocation, ue.root_loc) ----------
local function xy_m(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) / 100 end
-- The piece_land record once (section 3.1): land_m from the first rest, else where it is now; visible_60s only at
-- LAND_S ('unread' at lab_end)
function land_rec(piece, l, why, loc)
    if l.done then return end
    l.done = true
    local a = live(piece.rec)
    local at = l.land_at or loc or (a and ue.root_loc(a))
    local m = at and r1(xy_m(at, l.from)) or 'unread'
    local vis = 'unread'
    if why == nil then vis = a ~= nil and US.actor_hidden(a) == false end
    if why == 'gone' then vis = false end
    LAB.rec('piece_land', { id = piece.id, part = piece.part, pair = piece.pair, land_m = m,
        land_ok = type(m) == 'number' and m >= P.LAND_MIN_M and m <= P.LAND_MAX_M, visible_60s = vis,
        settled_s = l.settled_s or 'unread', why = why, stray = l.stray }, true)
end
-- One piece's landing step (every LAND_DT game seconds): speed from the last read, the first rest of REST_S, the
-- stray rule (evicted), the record at LAND_S
local function land_step(piece, l, g)
    local a = live(piece.rec)
    if not a then
        land_rec(piece, l, 'gone')
        st.land[piece] = nil
        return
    end
    local loc = ue.root_loc(a)
    if loc then
        if l.last and g > l.last.t then
            local sp = len(add(loc, l.last.loc, -1)) / (g - l.last.t)
            if sp < P.REST_SPEED then
                l.rest = l.rest or l.last.t
                if not l.settled_s and g - l.rest >= P.REST_S then l.settled_s, l.land_at = r1(l.rest - l.t0), loc end
            else
                l.rest = nil
            end
        end
        l.last = { loc = loc, t = g }
        if l.from.z - loc.z > P.STRAY_DOWN_CM or xy_m(loc, l.from) * 100 > P.STRAY_SIDE_CM then
            l.stray = true
            land_rec(piece, l, 'stray', loc)
            st.land[piece] = nil
            st.evict[#st.evict + 1] = { piece = piece, why = 'stray' }
            return
        end
    end
    if g - l.t0 >= P.LAND_S then
        land_rec(piece, l, nil, loc)
        st.land[piece] = nil
    end
end
local function land_tick()
    if LAB.paused() then return end
    local g, n = gnow(), 0
    for _, piece in ipairs(st.live) do                  -- in commit order; LAND_PER_TICK reads at most
        local l = st.land[piece]
        if l and g >= l.next_t and n < P.LAND_PER_TICK then
            n = n + 1
            l.next_t = g + P.LAND_DT
            land_step(piece, l, g)
        end
    end
end

-- ---------- evictions: FIFO, life, strays; one per frame under 'piece.destroy' once P16 passed ----------
-- A Piece stays in st.live (the mod-off list) until P.destroy unlists it: a refused destroy leaves it listed and the
-- FIFO or life rule queues it again. The queue drains before the oldest is queued, so one eviction frees one place.
-- While off or under the vanilla compare nothing is evicted (an armed world action, section 3.2): a Piece hidden by
-- 'off' must still be there for 'on' (L8 list_diff 0); its life end and a FIFO overflow wait for 'on'
local function evict_tick()
    if st.no_evict or not MODOFF.enabled('lab_piece') or not usable('piece.destroy') then return end
    if LAB.beta() then                                  -- the beta never runs a refused class: no eviction then
        local ok, why = LAB.sig('piece.destroy')
        if not ok then
            if why ~= 'sig_pending' and not st.evict_off then
                st.evict_off = tostring(why)
                LAB.rec('piece_evict_off', { why = st.evict_off, live = #st.live }, true)
            end
            return
        end
    end
    local g, first = gnow(), st.live[1]
    if not st.evict[1] and first then
        if #st.live > (LAB.beta() and P.FIFO_BETA or P.FIFO) then st.evict[1] = { piece = first, why = 'fifo' }
        elseif g - (first.t0 or g) >= P.LIFE_S then st.evict[1] = { piece = first, why = 'life' } end
    end
    local e = table.remove(st.evict, 1)
    while e and e.piece.state == 'destroyed' do e = table.remove(st.evict, 1) end
    if not e then return end
    local _, err = LAB.armed('piece.destroy', P.destroy, e.piece, e.why)      -- P.destroy writes a pending piece_land
    if err == nil then st.evicted = st.evicted + 1 end
end
-- MC6 (the beta): the cuts whose corpse went (lab_cut's bus lab_cut_gone, queued by the listener) give their Piece to
-- the body_gone queue, due piece_linger_s game seconds later; a revive (no gone_why) or a kept body (cut.kept true)
-- keeps it. A due Piece joins the eviction queue (evict_tick: one per frame, held while off)
local GONE = { destroyed = true, collected = true }
local function body_tick()
    local q, linger = st.goneq, CFG.knob('piece_linger_s')
    st.goneq = {}
    for _, cut in ipairs(q) do
        local piece = cut.piece
        if GONE[cut.gone_why] and (cut.kept ~= true or cut.expired == true) and type(piece) == 'table'
                and piece.state ~= 'destroyed'
                and not piece.body_gone then
            piece.body_gone, piece.gone_t = true, now()
            st.bodyq[#st.bodyq + 1] = { piece = piece, at = gnow() + (type(linger) == 'number' and linger or 0) }
        end
    end
    local g, keep = gnow(), {}
    for _, e in ipairs(st.bodyq) do
        if e.piece.state == 'destroyed' then              -- gone already (FIFO, life, stray)
        elseif g >= e.at then
            st.evict[#st.evict + 1] = { piece = e.piece, why = 'body_gone' }
            st.body_gone = st.body_gone + 1
        else
            keep[#keep + 1] = e
        end
    end
    st.bodyq = keep
end

-- ---------- the ladder P10-P16 (section 3.5) on kept-only 2 ----------
P.BESIDE = { x = 0, y = P.BESIDE_CM, z = 0 }
-- The head bones of the pair on the corpse's body leader (lab_pairs candidates, GetBoneIndex; the stump bone the live
-- parent), the world geometry, the body source and the stray set: the 'lab.inherit.hide' class P1 proved
local function resolve(actor, pair)
    local leader = ue.prop(actor, 'Mesh')
    if not ue.valid(leader) then return { why = 'no_leader' } end
    local head = (pair_of(pair).parts or {}).head
    if not head then return { why = 'no_part' } end
    local function first(list)
        for _, b in ipairs(list or {}) do if ue.has_bone(leader, b) then return b end end
    end
    local cut = { bone = first(head.cut), child = first(head.child), pair = pair, part = 'head' }
    if not (cut.bone and cut.child) then return { why = 'no_bone' } end
    cut.stump = first(head.stump) or L.bone_parent(leader, cut.bone)
    if not cut.stump then return { why = 'no_parent' } end
    local srcs, ws = sources(actor, leader, cut, 'body_copy')
    if not srcs then return { why = ws } end
    local g, wg = geometry(leader, cut, srcs)
    if not g then return { why = wg } end
    cut.leader, cut.srcs, cut.g, cut.outside = leader, srcs, g, outside(leader, cut.bone)
    return cut
end
-- The test Piece of the ladder from the resolved bones (route body_copy: the isolation is proven too)
local function test_piece(lad)
    local b = lad.bones
    return { id = lad.d.id, pair = lad.d.pair, part = 'head', route = 'body_copy', bone = b.bone, child = b.child,
        stump = b.stump, leader = b.leader, at = b.g.at, d = b.g.d, outside = b.outside, iso = pair_of(b.pair).iso,
        joint = { x = 0, y = 0, z = 0 }, out = { x = 0, y = 0, z = 1 }, ladder = true, state = 'building' }
end
local function rebind(lad)                               -- the current corpse's pose sources for P13
    local piece, b = lad.piece, lad.bones
    piece.leader, piece.at = b.leader, b.g.at
    if piece.poses and piece.poses[1] then piece.poses[1].xf = b.srcs[1].xf end
end
local function res(ok, w, f)
    f = f or {}
    f.err = (not ok) and w ~= nil and text(w) or f.err
    return { ok = ok == true, f = f }
end
-- The pose proof (spec M1a 4.2 item 2). The bones read on both meshes: the cut bone, its child, then up to three probes
-- the two meshes both hold. { bones } | nil, why ('no_bone: <b>' for the cut bone or its child)
local function pose_bones(piece, p)
    local list = { piece.bone, piece.child }
    for _, b in ipairs(list) do
        if not (ue.has_bone(piece.leader, b) and ue.has_bone(p, b)) then return nil, 'no_bone: ' .. tostring(b) end
    end
    local n = 0
    for _, b in ipairs(P.POSE_PROBES) do
        if n < 3 and ue.has_bone(piece.leader, b) and ue.has_bone(p, b) then list[#list + 1], n = b, n + 1 end
    end
    return list
end
-- Per bone, in cm: the world location of the bone on the poseable minus off (the Piece's BESIDE) minus its world
-- location on the leader, as a length. { gaps by bone }, the largest | nil, why when the cut bone or its child does
-- not read (a probe that does not read is left out)
-- lref (optional): the leader's locations by bone read at the copy (leader_locs), so a corpse that moved since then adds
-- no drift to the after-gaps
local function pose_gaps(piece, p, bones, off, lref)
    local gaps, hi = {}, 0
    for i, b in ipairs(bones) do
        local a, wa = world_of(p, b)
        local l, wl
        if lref then l, wl = lref[b] and { loc = lref[b] } or nil, 'no_ref' else l, wl = world_of(piece.leader, b) end
        if a and l then
            local g = len(add(add(a.loc, off, -1), l.loc, -1))
            gaps[b] = g
            if g > hi then hi = g end
        elseif i <= 2 then
            return nil, tostring(b) .. ': ' .. text(wa or wl)
        end
    end
    return gaps, hi
end
-- The leader's world location of each bone now: { loc by bone } (a bone that does not read is left out)
local function leader_locs(piece, bones)
    local out = {}
    for _, b in ipairs(bones) do
        local l = world_of(piece.leader, b)
        if l then out[b] = l.loc end
    end
    return out
end
-- P13's verdict from the largest gap before and after the copy (every bone under POSE_AMBIG_CM before the copy: the
-- check cannot tell a copy from no copy). true | false, why
local function pose_verdict(before_hi, after_hi)
    if before_hi < P.POSE_AMBIG_CM then return false, 'pose_ambiguous' end
    if after_hi >= before_hi then return false, 'pose_ref' end
    if after_hi > P.POSE_OK_CM then return false, 'pose_off' end
    return true
end
-- The gaps as a short list for the record: { { bone, before, after } }, one decimal (before, after: gaps by bone)
local function gap_list(bones, before, after)
    local out = {}
    for _, b in ipairs(bones) do
        out[#out + 1] = { b = b, before = before[b] and r1(before[b]) or 'unread',
            after = after and after[b] and r1(after[b]) or 'unread' }
    end
    return out
end
-- The poseable's own component-space answer against the leader's, the largest gap over the cut bone and its child:
-- tells a copy that did not carry from a poseable that has not refreshed its world answers yet
local function pose_cs_gap(piece, p)
    local hi
    for _, b in ipairs({ piece.bone, piece.child }) do
        local a = L.bone_xform_get(p, b)
        local l = L.bone_component_xform(piece.leader, b)
        if not (a and l) then return nil end
        local g = len(add(a.loc, l.loc, -1))
        if not hi or g > hi then hi = g end
    end
    return hi
end
P.LADDER = {
    { step = 'P10', name = 'hide.optim', run = function(lad, actor) return res(L.optim(actor, true)) end },
    { step = 'P11', name = 'piece.spawn', run = function(lad)
        lad.piece, lad.applied = test_piece(lad), {}
        return res(spawn(lad.piece, add(lad.piece.at, P.BESIDE)))
    end },
    { step = 'P12', name = 'piece.mesh', need = { 'piece.spawn' }, piece = true, run = function(lad)
        return res(meshes(lad.piece, lad.bones.srcs))
    end },
    -- Two passes (lead 2026-10-31, the fix round's runtime review): CopyPoseFromSkeletalComponent only marks the
    -- poseable's transforms dirty (MarkRefreshTransformDirty [inferred, UE source]); its component-space answers refresh
    -- on its next tick, so a gap read in the copy frame reads the reference pose ('pose_ref' on a good copy). Pass 1
    -- places, reads the before-gaps and the leader's locations, copies, and returns pending (no proof; the ladder runs
    -- the step again after its linger). Pass 2, a later frame on the same corpse, reads the after-gaps against the
    -- leader's locations of pass 1 (a corpse that moved adds no drift) and gives the verdict. Another corpse or a lost
    -- pass-1 state starts over at pass 1
    { step = 'P13', name = 'piece.pose', need = { 'piece.mesh' }, piece = true, run = function(lad)
        local piece, q = lad.piece, lad.p13
        if q and (q.d ~= lad.d or q.poseable ~= piece.poseable or q.frame >= S.frame) then q, lad.p13 = nil, nil end
        if not q then
            rebind(lad)
            lad.pose = nil
            local ok, w = place(piece, P.BESIDE)
            if not ok then return res(ok, w) end
            local p = piece.poseable
            local bones, wb = pose_bones(piece, p)
            if not bones then return res(false, wb) end
            local lref = leader_locs(piece, bones)
            local before, b_hi = pose_gaps(piece, p, bones, P.BESIDE, lref)
            if not before then return res(false, 'pose_unread: ' .. tostring(b_hi)) end
            local f = { probes = #bones, same_skel = L.same_skeleton(p, piece.leader) or 'none',
                delta_before_cm = r1(b_hi) }
            local okc, wc = COMMIT_FN.copy(piece)
            f.copy_ok = okc == true
            if not okc then
                f.deltas = gap_list(bones, before, nil)
                return res(false, wc, f)
            end
            local same, s_hi = pose_gaps(piece, p, bones, P.BESIDE, lref)   -- the copy frame's read, logged only
            f.delta_copyframe_cm = same and r1(s_hi) or 'unread'
            lad.p13 = { d = lad.d, poseable = p, frame = S.frame, bones = bones, lref = lref, before = before,
                b_hi = b_hi, f = f }
            return { ok = false, pending = true, f = f }
        end
        lad.p13 = nil
        local p, bones, f = piece.poseable, q.bones, q.f
        local after, a_hi = pose_gaps(piece, p, bones, P.BESIDE, q.lref)
        if not after then
            f.deltas = gap_list(bones, q.before, nil)
            return res(false, 'pose_unread: ' .. tostring(a_hi), f)
        end
        local cs = pose_cs_gap(piece, p)
        f.delta_after_cm, f.deltas, f.delta_cs_cm = r1(a_hi), gap_list(bones, q.before, after), cs and r1(cs) or 'unread'
        f.frames_after = S.frame - q.frame
        local lw = world_of(piece.leader, piece.bone)
        local moved = lw and q.lref[piece.bone] and len(add(lw.loc, q.lref[piece.bone], -1)) or nil
        f.leader_moved_cm = moved and r1(moved) or 'unread'
        local x = L.bone_xform_get(p, piece.child)
        f.head_z = x and r1(x.loc.z) or nil
        local good, why = pose_verdict(q.b_hi, a_hi)
        if good then lad.pose = { bones = bones, off = P.BESIDE, leader_loc = lw and lw.loc or nil } end
        return res(good, why, f)
    end },
    -- P14 reads the P13 gaps again before its writes: a poseable that refreshed back to the reference pose reads
    -- 'pose_stale' and nothing is written. A leader that moved since P13 (a corpse still settling) makes the re-read
    -- unprovable: the gaps are logged, the verdict is skipped
    { step = 'P14', name = 'piece.isolate', need = { 'piece.pose' }, piece = true, run = function(lad)
        local piece, pose, f = lad.piece, lad.pose, {}
        if pose then
            local gaps, hi = pose_gaps(piece, piece.poseable, pose.bones, pose.off)
            local lw = world_of(piece.leader, piece.bone)
            local moved = lw and pose.leader_loc and len(add(lw.loc, pose.leader_loc, -1)) or nil
            f.delta_next_cm, f.leader_moved_cm = gaps and r1(hi) or 'unread', moved and r1(moved) or 'unread'
            if gaps and moved ~= nil and moved <= P.POSE_OK_CM and hi > P.POSE_OK_CM then
                return res(false, 'pose_stale', f)
            end
        end
        local ok, w = COMMIT_FN.isolate(piece)
        f.stray_bones, f.seam_ok, f.stray = piece.stray_bones, piece.seam_ok, piece.stray
        return res(ok, w, f)
    end },
    { step = 'P15', name = 'piece.phys', need = { 'piece.isolate' }, piece = true, run = function(lad)
        local ok, w = COMMIT_FN.show(lad.piece)
        if ok then lad.piece.shown = true ok, w = physics(lad.piece) end
        if ok then ok, w = L.velocity_change(lad.piece.carrier, { x = 0, y = 0, z = 0 }, P.VEL_CAP) end
        return res(ok, w)
    end },
    -- gone: the actor reads invalid or bActorIsBeingDestroyed (UWorld::DestroyActor sets it at once [inferred, UE
    -- source]; BoolProperty in the ObjectDump). UE4SS's IsValid reads a destroyed actor valid until the GC (review A5.1
    -- F2), and its components stay listed (MarkComponentsAsGarbage), so neither IsValid nor the component list reads it
    { step = 'P16', name = 'piece.destroy', need = { 'piece.spawn' }, piece = true, wait = P.DESTROY_WAIT_S,
        rebuild = { P11 = true }, run = function(lad)
            local a = live(lad.piece.rec)
            local ok, w = US.destroy_actor(a)
            lad.piece.shown = lad.piece.shown and not ok      -- a test Piece that stays shown stays in the mod-off list
            return res(ok, w, { gone = not ue.valid(a) or ue.prop(a, 'bActorIsBeingDestroyed') == true })
        end },
}
local function wait_until(lad, t) if t > lad.next_t then lad.next_t = t end end
-- One armed call of the ladder (a step, the bone read, a replay): the next waits its linger
local function run(lad, name, fn, ...)
    local t0 = os.clock()
    local r, err = LAB.armed(name, fn, ...)
    wait_until(lad, now() + LAB.linger_s(name))
    return r, err, math.floor((os.clock() - t0) * 1000 + 0.5)
end
-- The first step that has not run, past the skipped ones (ran, disabled, a need that did not pass)
local function next_step(lad)
    while P.LADDER[lad.i] do
        local s, skip = P.LADDER[lad.i], nil
        if LAB.proof(s.name) ~= nil then skip = 'ran'
        elseif SENT.is_disabled(s.name) then skip = 'disabled'
        else for _, n in ipairs(s.need or {}) do if LAB.proof(n) ~= true then skip = 'need:' .. n end end end
        if not skip then return s end
        if skip ~= 'ran' then lad.skipped[s.step] = skip end
        lad.i = lad.i + 1
    end
    lad.done = true
    return nil
end
-- A step on the test Piece whose actor went (a map load): the earlier piece steps that passed, replayed in order
-- under their own names without a proof, one per frame. true when one ran (the tick ends there)
local function replay(lad, s)
    if not live(lad.piece and lad.piece.rec) or not lad.applied then lad.applied = {} end   -- none yet, or lost
    for _, e in ipairs(P.LADDER) do
        if e == s then break end
        if e.step ~= 'P10' and LAB.proof(e.name) == true and not lad.applied[e.step]
                and (s.rebuild == nil or s.rebuild[e.step]) then
            local r, err = run(lad, e.name, e.run, lad)
            if err ~= nil or type(r) ~= 'table' or not r.ok then
                lad.done, lad.why = true, 'rebuild:' .. e.step
            end
            lad.applied[e.step] = true
            return true
        end
    end
    return false
end
-- Is the Cap ladder (P3-P9b) done? Its last step ran, or lab_cap says so, or it is not loaded
local function cap_done()
    if LAB.proof('cap.keep') ~= nil then return true end
    local C = package.loaded['lab_cap']
    if type(C) ~= 'table' or type(C.status) ~= 'function' then return true end
    local ok, s = pcall(C.status)
    return ok and type(s) == 'table' and (s.done == true or s.init ~= true)
end
-- The corpse of a lab_row payload while it is alive (live and not being destroyed: spec M1a 4.1 item 2) and not on a
-- later life; nil and why ('destroyed', 'collected', 'reused', 'stale', 'none', 'revived') otherwise
local function corpse(d)
    if type(d) ~= 'table' then return nil, 'none' end
    local a, why = LAB.alive(d.victim or d.keep)
    if not a then return nil, why end
    if type(d.victim) == 'table' and d.corpse_life and d.victim.life ~= d.corpse_life + 1 then return nil, 'revived' end
    return a
end
-- M1a 4.1 item 3: the host reads dead before the next step (why: LAB.alive's word): that step is skipped 'host_dead'
-- (no call, no proof, one 'ladder_skip' record and the counter) and the ladder moves to the next kept corpse. Nothing
-- is skipped when no step is left to run
local function host_dead(lad, why)
    local s = next_step(lad)
    if not s then return end
    LAB.host_skip('lab_piece', s.step, lad.d, why)
    st.host_dead = (st.host_dead or 0) + 1
end
local function after(lad, s, ok)
    if s.step == 'P16' and not ok then st.no_evict, st.no_destroy = true, true end   -- the test Piece stays
    if lad.applied then lad.applied[s.step] = ok or nil end
    if s.step == 'P15' then lad.shown_t = now() end
end
local function ladder_tick()
    local lad = st.lad
    if not lad or lad.done or LAB.ended() or LAB.paused() or not MODOFF.enabled('lab_piece') then return end
    local t = now()
    if t < lad.next_t then return end
    local p2, p1 = LAB.proof('keep.write'), LAB.proof('lab.inherit.hide')
    if p2 == false or p1 == false then
        lad.done, lad.why = true, p2 == false and 'no_keep' or 'l0i_nogo'
        return
    end
    if p2 == nil or p1 == nil or not cap_done() then return end
    local last = st.last
    if last and (last.f >= S.frame or t < last.t + LAB.linger_s(last.name)) then return end
    local actor, dead = corpse(lad.d)
    if not actor then                                   -- the next kept-only corpse takes over
        lad.bones = nil
        while true do
            if lad.d ~= nil then host_dead(lad, dead) end
            lad.d = table.remove(st.keeps, 1)
            if lad.d == nil then return end
            actor, dead = corpse(lad.d)
            if actor then break end
        end
    end
    if not lad.bones then
        local r, err = run(lad, 'lab.inherit.hide', resolve, actor, lad.d.pair)
        if type(r) == 'table' and r.leader then lad.bones = r
        elseif type(r) == 'table' then lad.why, lad.d = 'bones:' .. tostring(r.why), nil
        else lad.done, lad.why = true, 'bones:' .. tostring(err) end
        return
    end
    local s = next_step(lad)
    if not s then return end
    if s.wait and t < (lad.shown_t or 0) + s.wait then return end
    if s.piece and replay(lad, s) then return end
    local sig_ok, why = LAB.sig(s.name)
    if not sig_ok then
        if why == 'sig_mismatch' or why == 'sig_unknown' then lad.skipped[s.step], lad.i = why, lad.i + 1
        elseif why ~= 'sig_pending' then wait_until(lad, t + P.SIG_RETRY_S) end      -- pending: the next frame
        return
    end
    local r, err, ms = run(lad, s.name, s.run, lad, actor)
    if err == nil and type(r) == 'table' and r.pending then return end     -- P13's pass 1: no proof, again later
    local ok = err == nil and type(r) == 'table' and r.ok == true
    local f = type(r) == 'table' and type(r.f) == 'table' and r.f or {}
    f.err, f.ms, f.id, f.pair = f.err or (err ~= nil and text(err) or nil), ms, lad.d.id, lad.d.pair
    LAB.host_state(actor, lad.d, f)                     -- host_age_s, host_destroying (M1a 4.1 item 3)
    LAB.prove(s.step, s.name, ok, f)
    after(lad, s, ok)
    lad.i = lad.i + 1
end

-- ---------- lifecycle ----------
-- lab_end (D20): the ladder's test Piece still shown (P15 showed it, P16 has not destroyed it) is hidden under
-- 'piece.phys', the name that showed it, in the first tick after lab_end (the lingers clear a frame after the end
-- flush); while off it waits for 'on', which shows it first
local function end_hide()
    local piece = st.lad and st.lad.piece
    if not (piece and piece.shown) or piece.end_hide or not MODOFF.enabled('lab_piece') then return end
    piece.end_hide = true                               -- tried once: a refused hide leaves it in the mod-off list
    local a = live(piece.rec)
    local ok, err = false, nil
    if a then ok, err = LAB.armed('piece.phys', US.set_actor_hidden, a, true) end
    if not a or (err == nil and ok) then piece.shown = false end
end
local function tick()
    ladder_tick()
    if LAB.ended() then return end_hide() end
    land_tick()
    if st.goneq[1] or st.bodyq[1] then body_tick() end     -- the beta's body_gone (MC6)
    evict_tick()
end
-- lab_end (D20): every Piece still waiting for its landing gets its record now (visible_60s 'unread')
local function on_end()
    for _, piece in ipairs(st.live) do
        local l = st.land[piece]
        if l then land_rec(piece, l, 'lab_end') end
    end
    st.land = {}
end
function P.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.cut_set() then return true end
    st.init = true
    LAB.names(N, F)
    LAB.count('lab_piece_host_dead', 0)
    -- mod-off hides the Piece actors (kind 'actor': SetActorHiddenInGame under 'modoff.hide', A1.7) and the vanilla
    -- compare blocks the ladder and P.build, as mod-off does
    MODOFF.feature('lab_piece', { gameplay = true, live = P.live })
    BUS.on('lab_row', 'lab_piece', function(row, d)     -- listeners only queue: kept-only 2 and later
        if row ~= 'keep_only' or type(d) ~= 'table' then return end
        st.rows = st.rows + 1
        if st.rows < 2 or #st.keeps >= P.KEEPS then return end
        st.keeps[#st.keeps + 1] = d
        if not st.lad then st.lad = { i = 1, next_t = 0, skipped = {} } end
    end)
    BUS.on('lab_proof', 'lab_piece', function(name) st.last = { name = name, t = now(), f = S.frame } end)
    BUS.on('lab_end', 'lab_piece', function() S.late('lab_piece.end', on_end) end)
    if LAB.beta() then                                  -- MC6: Pieces follow the body (the listener only queues)
        BUS.on('lab_cut_gone', 'lab_piece', function(cut)
            if type(cut) ~= 'table' or type(cut.piece) ~= 'table' then return end
            if #st.goneq >= P.GONEQ then st.gone_drop = st.gone_drop + 1 return end
            st.goneq[#st.goneq + 1] = cut
        end)
    end
    S.ticker('lab_piece', tick)
    return true
end
-- A map load: the Pieces and the test actor went with the old map (their records go stale); the proofs stay
function P.reset()
    if not st.init then return end
    for _, piece in ipairs(st.live) do
        local l = st.land[piece]
        if l then land_rec(piece, l, 'stale') end
    end
    st.live, st.land, st.evict, st.keeps, st.goneq, st.bodyq = {}, {}, {}, {}, {}, {}
    local lad = st.lad
    if lad and not lad.done then lad.d, lad.bones = nil, nil end
end
function P.status()
    local lad = st.lad or {}
    local s = P.LADDER[lad.i or 0]
    local land = 0
    for _ in pairs(st.land) do land = land + 1 end
    return { init = st.init, built = st.built, committed = st.committed, failed = st.failed, live = #st.live,
        evicted = st.evicted, no_evict = st.no_evict, land = land, step = s and s.step or nil, done = lad.done,
        why = lad.why, skipped = lad.skipped, corpse = lad.d and lad.d.id or nil, keeps = #st.keeps,
        host_dead = st.host_dead or 0, body_gone = st.body_gone, bodyq = #st.bodyq, gone_drop = st.gone_drop,
        resyncs = st.resyncs, extras = st.extras, extras_drop = st.extras_drop, evict_off = st.evict_off }
end
function P.shutdown()
    S.remove_ticker('lab_piece')
    BUS.off('lab_row', 'lab_piece')
    BUS.off('lab_proof', 'lab_piece')
    BUS.off('lab_end', 'lab_piece')
    BUS.off('lab_cut_gone', 'lab_piece')
    st, A = new_state(), nil
end

return P
