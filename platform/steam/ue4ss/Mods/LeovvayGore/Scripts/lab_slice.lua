-- status: new (offline only, smoke-run on fakes; the author's S0 probe run decides) origin: docs/research/slicer-stumps.md
-- lab_slice.lua: the primitives of the game's own skeletal-mesh slicer (AkashaRuntimeSkeletalMeshSlicerLibrary), which
-- cuts the real skin along a plane, caps each cut loop flush and returns two skinned halves with their own ragdoll
-- (docs/research/slicer-stumps.md sections 1, 4-6, 9). The S0 probe (lab_slice_probe.lua, the test build's
-- Ctrl+Shift+F2) and the later production head route share them. The player beta loads this module (META.beta_modules,
-- last) and it stays inert: init registers no listener, no ticker and no record (only MODOFF.feature 'lab_slice', so
-- the switches gate new slices) and nothing here runs a native call unless a caller asks.
-- * Threads: every primitive runs only inside SL.step(fn, ...), which a ticker calls (the probe's; never a key
--   callback, a hook body, a bus listener or lab_plan's frame); outside it each answers false, 'not_tick'. Only the
--   slicer's worker checks IsInGameThread; the preflight does not (skeptic native R10).
-- * Guards: each native call runs inside LAB.armed under its own META.lab_risky name, named at the call (a literal, or
--   the family's SL.FAMILIES entry; run() takes only this module's names): slicer.read
--   (component, bone, material-slot and simulation reads, the streaming flags, the CapMaterial lookups), slicer.lodinfo
--   (SourceModels[i].bAllowCPUAccess, an array-of-structs read bounded by #, GetNumLODs, ForcedLodModel), the two CVar
--   reads, slicer.preflight (DebugSkeletalMeshSlicePreflight), lab_slice_lod's LOD experiment (slicer.cpuflag the LOD
--   0 preflight and slicer.lodpre the LOD 1-3 ones with the bit set and restored in the call, slicer.prepare,
--   slicer.prep.read, slicer.cut.prep the prepared cut, slicer.release), slicer.load (LoadAsset of M_SKInteriror and
--   its hold), slicer.mat (the material flags), slicer.cut.malethug / slicer.cut.guichai (the slice on LOD 0, one name
--   per body asset: a GuiChai-only fault never switches MaleThug off; never on another LOD: SL.cut takes no lod) and,
--   for every other cut class of the production route, slicer.cut.body /
--   slicer.cut.meshhead (by the class row's route), slicer.reslice (the production route's slice of a half that still
--   holds the next part), slicer.after (the halves, the children, the source), slicer.rehome (a component re-homed to
--   the Positive half), slicer.fix (SetSimulatePhysics(false) on the hidden source, or on a half a re-slice hid),
--   slicer.push (one impulse on a half), slicer.drop (a sliced head's hats and masks: their world transforms read, then
--   hidden, for lab_gib's falling copies, which run under slicer.fall), and slicer.gone (lab_corpse's vanish and
--   destroy of a sliced corpse); lab_blood's slicer.blood (lab_blood_slice.lua) runs every call on a half. One
--   slice a frame over every caller (SL.cut_frame; a second one refuses 'cut_this_frame'). Before running, every name
--   must be pinned (LAB.pinned), then pass LAB.refusal: not disabled, not inherited after a stop, and its sig check
--   ok (LAB.sig; 'sig_pending' answers that word: wait a frame). A refusal answers a word of SL.REFUSALS: nothing ran.
-- * Never sent to the slicer (skeptic native, the fault matrix): a component that is not valid AND IsA
--   SkeletalMeshComponent (SkeletalMeshComponentBudgeted passes, a ChaosClothComponent never), whose SkinnedAsset is not
--   a SkeletalMesh, a follower (a valid LeaderPoseComponent: preflight only, never a cut), a body whose
--   bHasStreamingUpdatePending does not read false in that frame ('lod_streaming'), a body whose LOD0 CPU bit reads
--   neither a boolean nor soft (the caller's gate), an actor that already holds an Akasha half. A bit that reads false
--   is set only inside one lab_slice_lod call and written back in it. DebugSkeletalMeshSliceComponent is never called
--   (it reads every CPU skin weight with no CPU check), nor Capture or Restore; Prepare, SlicePrepared and Release only
--   by lab_slice_lod. z.sliceUseEngineSetAllBodiesSimulatePhysics must read exactly 0.
-- * Marshalling (skeptic marshal, UE4SS cdbc0b66 LuaUObject.cpp): ue.call(lib, name, ...) with the exact arity:
--   Preflight(comp, P, N, opts, rt), WithDebugReport(comp, P, N, opts, res, rt); res and rt are fresh tables built in
--   the call's frame (a res an earlier call filled faults when marshalled back as input); P, N and ShockForce are plain
--   tables (ue.vec(x, y, z)); the five FName fields are FName userdata (ue.fname); the 24 option fields come from
--   SL.OPTS and SL.check_options refuses any miss ('opts_shape:<key>') or bad value ('opts_value:<key>') before the
--   call; CapMaterial is the live material object resolved in the cut frame (never nil in a cut, never carried across
--   frames). The FString outs are read with ue.str(...) or ''. After the cut res.PositiveComponent and
--   res.NegativeComponent are read in the same frame and kept (ue.keep_mod) only when their address is one of the
--   actor's components; res.Intersections is dropped unread.
-- * The self-call flag: ue.count_write(1), then st.in_cut true around the one pcall'd slice, false on every path (and
--   st.in_self around lab_slice_lod's Prepare and Release); SL.self_call() reads both (lab_kill's consumers of the
--   slicer hooks and lab_slice_watch's return at their first line while it is true). In the beta lab_kill registers
--   none of them, so in the player zip nothing should fire inside the call.
-- * Bookkeeping (Lua only): SL.sliced(key) for every key the cut left at least one half on (lab_plan gives it row
--   'sliced', lab_corpse lets it go under 'slicer.gone'); SL.reserve(key, on) / SL.busy(key) while a job holds a
--   corpse (lab_corpse's going skips it); SL.verdict(asset) the cached preflight verdict per body asset.
-- API: step(fn, ...) refused(why) outcome(ok, why, data) hurt() options(cap, cell) check_options(o, cut) plane(bones,
--   t) plane_of(a, b, t) plane_ok(P, N) side(bones, P, N, far, near, far_cm, near_cm) parse(report) keep(report)
--   pre_good(data) family(class) cut_family(class, row) cut_frame() zero_handle(h); reads for a caller's own job:
--   lod_view(asset) (lab_slice_lod) skm_asset(c) halves_of(actor) -> { { c, name, side } }, read last_mat(c, unnamed)
--   -> n, name; primitives (each -> ok, why, data): scan(list, pawn) reqs(rec, bones) brief(rec, extras)
--   drop(rec, names) bones(rec, names, half) lodinfo(names) half_cpu(pos, neg) cvars() preflight(rec, name, P, N, cell,
--   force) preflight_lod(rec, name, P, N, cell, k) prepare(rec, name, k, life) prep_read(rec, name, k) cut_prep(rec, P,
--   N, choice, cell, key, k, handle) release(handle) (lab_slice_lod) mat_find() mat_load()
--   mat_flags() mat_hold() cut(fam, rec, P, N, choice, cell, key) reslice(rec, half, P, N, choice, cell, key)
--   after(rec, P, N, want) rehome(rec, name, pos) fix_source(rec) fix_half(half) push(half, dir, speed, bone);
--   bookkeeping sliced(key) mark_sliced(key) reserve(key, on) busy(key) busy_any() self_call() verdict(asset);
--   Lua-only reads corpse_state(key) cut_jobs(); lifecycle init(A) reset(reason) status() shutdown().
-- What the mock cannot prove: whether UE4SS 1185 marshals the 24-field options struct, the StrProperty out and the
-- TMap result as cdbc0b66's source reads; the slicer's real behaviour, cost and look (S0 decides).
local META = require('meta')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local LAB = require('lab_probe')
local KB = require('lab_cut_beta')
local LD = require('lab_slice_lod')                 -- the per-LOD CPU bits (a library, its header)

local SL = {
    LIB = '/Script/AkashaEffects.Default__AkashaRuntimeSkeletalMeshSlicerLibrary',
    SKINNED = '/Script/Engine.SkinnedMeshComponent', SKM = '/Script/Engine.SkeletalMeshComponent',
    SCENE = '/Script/Engine.SceneComponent', EXTRAS_MAX = 8,
    SKMESH = '/Script/Engine.SkeletalMesh', MATIF = '/Script/Engine.MaterialInterface',
    MATERIAL = '/Script/Engine.Material', NIAGARA = '/Script/Niagara.NiagaraComponent',
    SK_INTERIOR = '/Game/Test/XYF/Materials/M_SKInteriror.M_SKInteriror',
    POS = 'AkashaPositiveSliceComponent', NEG = 'AkashaNegativeSliceComponent',
    CVAR_ENGINE_SIM = 'z.sliceUseEngineSetAllBodiesSimulatePhysics', CVAR_FREE = 'r.FreeSkeletalMeshBuffers',
    RTS_WORLD = 0, SNAP = 2, COMPS_MAX = 8, MATS_MAX = 12, NIAGARA_MAX = 8, ERR_CHARS = 160, LINE_CHARS = 300,
    SLICED_MAX = 512, VERDICTS = 64, REPORT_LINES = 40, REPORT_CHARS = 4000, N_EPS = 1e-3, COORD_MAX = 1e7, LOD_MAX = 3,
}
-- The cut's sentinel name per body asset (SL.cut runs the entry; a new family needs a row here and in META): the
-- two lab targets by class (META.spawn.targets lab_1, lab_2), every other data/cut_classes.lua class by its row's route
-- (the production route lab_slice_route: 'body' a head inside the body mesh, 'meshhead' a separate head component),
-- so a fault on one asset family never switches the others off
SL.FAMILIES = { malethug = 'slicer.cut.malethug', guichai = 'slicer.cut.guichai', body = 'slicer.cut.body',
    meshhead = 'slicer.cut.meshhead' }
-- Every name this module, lab_corpse or a sliced victim's other modules run (SL.hurt; lab_plan's sig pass asks the
-- ones with a data/lab_classes.lua row: all but slicer.blood, which lab_blood runs as LAB.hot)
SL.NAMES = { 'slicer.read', 'slicer.lodinfo', 'slicer.cpuflag', 'probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics',
    'probe.cvar.r.FreeSkeletalMeshBuffers', 'slicer.preflight', 'slicer.load', 'slicer.mat', 'slicer.cut.malethug',
    'slicer.cut.guichai', 'slicer.cut.body', 'slicer.cut.meshhead', 'slicer.reslice', 'slicer.after', 'slicer.rehome',
    'slicer.fix', 'slicer.push', 'slicer.gone', 'slicer.blood', 'slicer.drop', 'slicer.fall', 'slicer.lodpre',
    'slicer.prepare', 'slicer.release', 'slicer.prep.read', 'slicer.cut.prep' }
-- The names run() takes: SL.NAMES less the ones other modules run (lab_corpse slicer.gone, lab_blood slicer.blood,
-- lab_gib slicer.fall)
local RUN = {}
for _, n in ipairs(SL.NAMES) do RUN[n] = true end
RUN['slicer.gone'], RUN['slicer.blood'], RUN['slicer.fall'] = nil, nil, nil
-- A guard that refused: the native call never ran ('cut_this_frame': a slice already ran this frame, any caller)
SL.REFUSALS = { inert = true, not_tick = true, in_cut = true, unpinned = true, disabled = true, inherit_off = true,
    sig_pending = true, sig = true, unknown_name = true, modoff = true, disabled_by_sentinel = true,
    arm_write_failed = true, not_armed = true, cut_this_frame = true }
-- The 24 fields of FAkashaSkeletalMeshSliceOptions (AkashaEffects.hpp, size 0x90), exact case, in struct order, with
-- the kind SL.check_options wants: the constructor's defaults never apply (UE4SS zeroes the params and copies the
-- frame over them), so a misspelled or missing key reads 0
SL.OPTS = { { 'LODIndex', 'int' }, { 'bHideSourceComponent', 'bool' }, { 'bEnableRagdoll', 'bool' },
    { 'bCreateCap', 'bool' }, { 'bBuildSliceMeshFromCurrentPose', 'bool' }, { 'bTransferAttachedPrimitiveChildren', 'bool' },
    { 'PositiveAttachedChildTag', 'name' }, { 'NegativeAttachedChildTag', 'name' },
    { 'DisableAttachedChildTransferTag', 'name' }, { 'bUseManualPoseSkinning', 'bool' },
    { 'MaxOutputBoneInfluences', 'int' }, { 'MaxOutputTexCoords', 'int' }, { 'bCopyVertexColors', 'bool' },
    { 'CapMaterial', 'object' }, { 'OverridePhysicsAsset', 'none' }, { 'PositiveCollisionProfileName', 'name' },
    { 'NegativeCollisionProfileName', 'name' }, { 'MaxIntersectionBodies', 'int' }, { 'CapGridCellSize', 'float' },
    { 'CapCoverageHullAngleStepDegrees', 'float' }, { 'BoneWeightThreshold', 'float' }, { 'SplitForce', 'float0' },
    { 'ShockForce', 'vec' }, { 'bEnableDebugLog', 'bool' } }
-- The report lines kept (spec 7.2, plus the marshalling echo ManualPoseSkinning)
SL.KEEP = { 'Preflight', 'CPUAccess', 'LODIndex', 'LODCount', 'LOD0', 'Vertices', 'Sections', 'Material', 'SkeletalUsage',
    'SkinWeights', 'MaxInfluences', 'AnimationMode', 'LeaderPose', 'SourceVertices', 'CPUSkinned', 'PositiveTriangles',
    'NegativeTriangles', 'MixedTriangles', 'Notice', 'ReturnValue', 'ComponentValid', 'Cap', 'missing', 'failed',
    'Warning', 'Error', 'ManualPoseSkinning' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua 'slicer.*'). The probe registers them (LAB.names)
local N = {}
local F = {
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SkinnedMeshComponent", "LeaderPoseComponent"},
    {"/Script/Engine.SkeletalMesh", "Skeleton"},
    {"/Script/Engine.SkeletalMesh", "LODInfo"},
    {"/Script/Engine.SkeletalMesh", "SourceModels"},
    {"/Script/Engine.SkeletalMeshLODInfo", "bAllowCPUAccess"},
    {"/Script/Engine.SkinnedMeshComponent", "ForcedLodModel"},
    {"/Script/Engine.StreamableRenderAsset", "bHasStreamingUpdatePending"},
    {"/Script/Engine.StreamableRenderAsset", "NeverStream"},
    {"/Script/Engine.StreamableRenderAsset", "bForceMiplevelsToBeResident"},
    {"/Script/Engine.SceneComponent", "AttachParent"},
    {"/Script/Engine.SceneComponent", "bVisible"},
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.Material", "bUsedWithSkeletalMesh"},
    {"/Script/Engine.Material", "bUsedWithStaticMesh"},
    {"/Script/Engine.Material", "MaterialDomain"},
    {"/Script/Engine.Material", "BlendMode"},
    {"/Script/Engine.Material", "ShadingModel"},
    {"/Script/Engine.Material", "TwoSided"},
}
SL.N, SL.F = N, F

local A = nil
local function new_state()
    return { init = false, stepping = false, step_f = nil, in_cut = false, in_self = false, cache = { f = -1 },
        sliced = {}, sliced_order = {}, busy = {}, verdicts = {}, verdict_order = {}, hold_ep = nil, hold_id = nil, cuts = 0,
        calls = 0, refusals = 0, cut_f = nil, reslices = 0 }
end
local st = new_state()

local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function clock() return A and A.clock and A.clock.real() or os.clock() end
local function text(s, n)
    s = tostring(s)
    n = n or SL.ERR_CHARS
    return #s > n and s:sub(1, n) or s
end
local function mod(name)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
local function or_unread(v) if v == nil then return 'unread' end return v end
-- v when it is a boolean (false included: 'x and v or y' would drop it), else alt
local function bool_or(v, alt) if type(v) == 'boolean' then return v end return alt end
-- An object's short class: the first token of its full name
local function class_of(o) local f = ue.full(o) return f and f:match('^(%S+) ') or nil end
-- o's name: none when o is not valid, unnamed (default '?') when its name did not read
local function name_or(o, none, unnamed) if not ue.valid(o) then return none end return ue.name(o) or unnamed or '?' end
-- An FName value: UE4SS FName userdata; the offline mock's table form (mock_ue4ss FName) only offline
local function is_fname(v) return type(v) == 'userdata' or (type(v) == 'table' and rawget(v, '__fname') == true) end
local function is_object(v) return type(v) == 'userdata' or (type(v) == 'table' and rawget(v, '__mock') == true) end
local function is_skm(c) return ue.valid(c) and ue.is_a(c, SL.SKM) == true end

-- ---------- vectors ----------
local function xyz(v)
    v = ue.p(v)
    if v == nil then return nil end
    local x, y, z
    if type(v) == 'table' and v.x ~= nil then x, y, z = v.x, v.y, v.z
    else x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z') end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
local function sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function len(a) return math.sqrt(dot(a, a)) end
local function rv(p) return p and { r1(p.x), r1(p.y), r1(p.z) } or nil end
SL.rv = rv

-- ---------- the frame cache: objects found this frame, for the next primitive of the same step ----------
-- A material, a component or a half is never carried into a later frame (skeptic native: a GC between frames frees
-- it); within one ticker step no GC runs
local function remember(k, o)
    if st.cache.f ~= S.frame then st.cache = { f = S.frame } end
    st.cache[k] = o
end
local function recall(k)
    if st.cache.f ~= S.frame then return nil end
    local o = st.cache[k]
    if ue.valid(o) then return o end
    return nil
end
-- The victim of a step: LAB.alive(rec), then on demand its Character.Mesh and whether that is a SkeletalMeshComponent.
-- The first job of a step that asks reads them; a later job of the same step on the same record takes them as read
-- (SL.step clears it at both ends and a slice clears it: nothing between two jobs of one step changes them)
local function victim(rec)
    local v = st.victim
    if not (v and v.rec == rec) then
        local obj, why = LAB.alive(rec)
        v = { rec = rec, obj = obj, why = why }
        st.victim = v
    end
    return v
end
local function body_of(v)
    if v.body == nil then v.body = ue.prop(v.obj, 'Mesh') or false end
    return v.body or nil
end
local function body_skm(v)
    if v.skm == nil then v.skm = is_skm(body_of(v)) end
    return v.skm
end

-- ---------- guards ----------
-- The word that refuses name now, or nil (and the sig's own why as the second value)
local function guard(name)
    if not st.init then return 'inert' end
    if not st.stepping then return 'not_tick' end
    if st.in_cut then return 'in_cut' end
    if LAB.pinned() ~= true then return 'unpinned' end
    local word, detail, raised = LAB.refusal(name)          -- disabled, inherit_off, the sig check
    if raised then detail = text(detail) end
    return word, detail
end
-- fn(...) under LAB.armed(rname), rname one of this module's names (a literal or an SL.FAMILIES entry at every call):
-- its result (a table), or nil and why (a refusal word, or the raised text)
local function run(rname, fn, ...)
    local word, detail = guard(rname)
    if word then
        st.refusals = st.refusals + 1
        return nil, word, detail
    end
    st.calls = st.calls + 1
    if not RUN[rname] then return nil, 'unknown_name' end
    return LAB.armed(rname, fn, ...)
end
-- A caught error inside a guarded job goes to ue.caught (lab_probe's ArrayNum stop rule reads it there)
local function caught(err, step)
    ue.caught(err, 'slice', step)
    return text(err)
end
-- (ok, why, data) from a run(): data is the job's table; ok is false when the guard refused or the job raised
local function answer(r, err, detail)
    if type(r) == 'table' then
        if r.refused then return false, r.refused, r end
        return true, nil, r
    end
    local why = err ~= nil and text(err) or 'unread'
    return false, why, { err = why, detail = detail }
end

function SL.refused(why) return SL.REFUSALS[why] == true end
-- A job's or a primitive's own refusal (nothing native ran, or it ran and found the world not ready)
local REFUSED_JOB = { gone = true, not_found = true, not_skm = true, no_skeletal_mesh = true, lod_streaming = true,
    no_body = true, components_unread = true, body_not_skm = true, body_follower = true, has_halves = true,
    cap_material_gone = true, no_cap_material = true, target_gone = true, no_lib = true, not_resident = true,
    no_host = true, no_positive = true, no_component = true, no_half = true, not_a_half = true, half_follower = true,
    modoff = true, no_family = true, bad_args = true, degenerate_plane = true, lod_range = true, bit_unread = true,
    no_source_models = true, prep_forced_lost = true, prep_not_resident = true }
-- How a primitive's answer goes on for its caller (the probe, the route): 'ok'; 'wait' (a pending sig: the same step
-- next frame); 'refused' (a guard or a job refused: SL.REFUSALS, REFUSED_JOB, 'opts_*', 'plane_*', 'hold: *', a data
-- table marked refused); 'raised' (a guarded call raised or the call itself failed)
function SL.outcome(ok, why, d)
    if ok then return 'ok' end
    if why == 'sig_pending' then return 'wait' end
    if SL.refused(why) or REFUSED_JOB[why] then return 'refused' end
    if type(why) == 'string' and (why:find('^opts_') or why:find('^plane_') or why:find('^hold: ')) then
        return 'refused'
    end
    if type(d) == 'table' and d.refused then return 'refused' end
    return 'raised'
end
-- The first slicer name the sentinel struck or switched off (integrate: a crash inside a linger, or a quit there,
-- costs the next session its slices), or nil
function SL.hurt()
    for _, list in ipairs({ SENT.disabled(), SENT.strikes() }) do
        for _, n in ipairs(list) do
            for _, k in ipairs(SL.NAMES) do if n == k then return n end end
        end
    end
    return nil
end
-- The probe's step: fn(...) with the native primitives allowed, then off again whatever fn did. pcall's results
function SL.step(fn, ...)
    if st.stepping then return false, 'nested' end
    st.stepping, st.step_f, st.victim = true, S.frame, nil
    local res = table.pack(pcall(fn, ...))
    st.stepping, st.in_cut, st.in_self, st.victim = false, false, false, nil
    return table.unpack(res, 1, res.n)
end

-- ---------- pure helpers: the options, the plane, the side test, the report ----------
-- The full options table (docs/research/slicer-stumps.md section 4 step 4): cap the live material object (nil in a
-- preflight), cell the CapGridCellSize in cm, lod the LODIndex (default 0; lab_slice_lod's experiment 0 to LOD_MAX)
function SL.options(cap, cell, lod)
    return { LODIndex = math.tointeger(lod) or 0, bHideSourceComponent = true, bEnableRagdoll = true, bCreateCap = true,
        bBuildSliceMeshFromCurrentPose = true, bTransferAttachedPrimitiveChildren = true,
        PositiveAttachedChildTag = ue.fname('SlicedUpperBody'), NegativeAttachedChildTag = ue.fname('SlicedLowerBody'),
        DisableAttachedChildTransferTag = ue.fname('SlicedNoTransfer'), bUseManualPoseSkinning = true,
        MaxOutputBoneInfluences = 4, MaxOutputTexCoords = 1, bCopyVertexColors = false,
        CapMaterial = cap, OverridePhysicsAsset = nil,
        PositiveCollisionProfileName = ue.fname('None'), NegativeCollisionProfileName = ue.fname('None'),
        MaxIntersectionBodies = 5, CapGridCellSize = (tonumber(cell) or 12) + 0.0,
        CapCoverageHullAngleStepDegrees = 5.0, BoneWeightThreshold = 0.05, SplitForce = 0.0,
        ShockForce = ue.vec(0, 0, 0), bEnableDebugLog = false }
end
local OPT_KEY = {}
for _, f in ipairs(SL.OPTS) do OPT_KEY[f[1]] = f[2] end
-- true, or false and 'opts_shape:<key>' (a missing or mistyped field, an extra key) / 'opts_value:<key>' (a value the
-- native code clamps nowhere or refuses: skeptic native). cut: CapMaterial must be an object (a preflight passes none)
function SL.check_options(o, cut)
    if type(o) ~= 'table' or getmetatable(o) ~= nil then return false, 'opts_shape:table' end
    for k in pairs(o) do if OPT_KEY[k] == nil then return false, 'opts_shape:extra_' .. tostring(k) end end
    for _, f in ipairs(SL.OPTS) do
        local k, kind, v = f[1], f[2], o[f[1]]
        local good
        if kind == 'int' then good = math.type(v) == 'integer'
        elseif kind == 'bool' then good = type(v) == 'boolean'
        elseif kind == 'name' then good = is_fname(v)
        elseif kind == 'float' then good = num(v) and v > 0
        elseif kind == 'float0' then good = num(v) and v >= 0
        elseif kind == 'vec' then good = type(v) == 'table' and getmetatable(v) == nil and num(v.X) and num(v.Y)
            and num(v.Z)
        elseif kind == 'none' then good = v == nil
        else good = (cut and is_object(v)) or (not cut and v == nil) end
        if not good then return false, 'opts_shape:' .. k end
    end
    -- the job checks k against GetNumLODs and #SourceModels in the call's frame (lab_slice_lod 'lod_range')
    if o.LODIndex < 0 or o.LODIndex > SL.LOD_MAX then return false, 'opts_value:LODIndex' end
    if o.CapCoverageHullAngleStepDegrees < 1 then return false, 'opts_value:CapCoverageHullAngleStepDegrees' end
    if o.CapGridCellSize < 1 then return false, 'opts_value:CapGridCellSize' end
    if o.MaxIntersectionBodies < 0 then return false, 'opts_value:MaxIntersectionBodies' end
    if o.MaxOutputBoneInfluences < 1 or o.MaxOutputTexCoords < 1 then return false, 'opts_value:MaxOutput' end
    return true
end
-- P and N as the native code wants them: finite, inside the world, |N| = 1 within N_EPS (a zero or NaN normal is
-- refused natively; PlanePosition is never checked there). true | false, why
function SL.plane_ok(P, N)
    for _, v in ipairs({ P, N }) do
        if type(v) ~= 'table' then return false, 'plane_shape' end
        for _, k in ipairs({ 'x', 'y', 'z' }) do
            if not num(v[k]) or math.abs(v[k]) >= SL.COORD_MAX then return false, 'plane_value' end
        end
    end
    if math.abs(len(N) - 1) > SL.N_EPS then return false, 'plane_normal' end
    return true
end
-- The plane through two bone positions: P = a + t (b - a), N = unit(b - a). P, N, length (cm) | nil,
-- 'degenerate_plane' (under 1 cm)
function SL.plane_of(a, b, t)
    local d = sub(b, a)
    local l = len(d)
    if not num(l) or l < 1 then return nil, 'degenerate_plane' end
    return { x = a.x + t * d.x, y = a.y + t * d.y, z = a.z + t * d.z }, { x = d.x / l, y = d.y / l, z = d.z / l }, l
end
-- The neck plane from bone positions: P = neck_01 + t (head - neck_01), N = unit(head - neck_01). P, N, length (cm) |
-- nil, why ('no_bones', 'degenerate_plane' under 1 cm)
function SL.plane(bones, t)
    local a, b = type(bones) == 'table' and bones.neck_01 or nil, type(bones) == 'table' and bones.head or nil
    if type(a) ~= 'table' or type(b) ~= 'table' then return nil, 'no_bones' end
    return SL.plane_of(a, b, num(t) and t or 0.5)
end
-- The side test (plan section 5): side[b] = (b - P).N in cm (0.1); ok when every far bone present reads below -far_cm
-- and every near one below -near_cm; an absent bone is skipped, one that did not read ('unread': it may lie over the
-- plane) fails. side, ok, fails (the failing bone names)
function SL.side(bones, P, N, far, near, far_cm, near_cm)
    local side, fails = {}, {}
    for _, set in ipairs({ { far or {}, far_cm or 10 }, { near or {}, near_cm or 2 } }) do
        for _, b in ipairs(set[1]) do
            local p = bones and bones[b]
            if type(p) == 'table' then
                local d = dot(sub(p, P), N)
                side[b] = r1(d)
                if not (d < -set[2]) then fails[#fails + 1] = b end
            else
                side[b] = p or 'absent'
                if p ~= nil and p ~= 'absent' then fails[#fails + 1] = b end
            end
        end
    end
    return side, fails[1] == nil, fails
end
-- The report fields (spec 7.3 with the skeptics' parsing: an absent field reads nil, never 0 or false)
local function int_after(s, key)
    local v = s:match('%f[%w]' .. key .. '[%s=:]*(%-?%d+)')
    return v and tonumber(v) or nil
end
local function word_after(s, key)
    local v = s:match('%f[%w]' .. key .. '[%s=:]*(%a+)')
    return v and v:lower() or nil
end
function SL.parse(report)
    report = type(report) == 'string' and report or ''
    local low = report:lower()
    local notice = nil
    for line in (report .. '\n'):gmatch('([^\n]*)\n') do
        if notice == nil and line:find('Notice', 1, true) then notice = text(line, SL.LINE_CHARS) end
    end
    return { src_ok = low:find('source data ok', 1, true) ~= nil,
        extract_failed = low:find('failed while extracting', 1, true) ~= nil,
        lod = int_after(report, 'LODIndex'), pos = int_after(report, 'PositiveTriangles'),
        neg = int_after(report, 'NegativeTriangles'), mix = int_after(report, 'MixedTriangles'),
        manual = word_after(report, 'ManualPoseSkinning'), ret = word_after(report, 'ReturnValue'),
        pos_valid = word_after(report, 'PositiveComponentValid'), neg_valid = word_after(report, 'NegativeComponentValid'),
        cpu = { asset = word_after(report, 'AssetAllowCPUAccess'), position = word_after(report, 'Position'),
            static = word_after(report, 'Static'), skin = word_after(report, 'SkinWeights'),
            index = word_after(report, 'Index'), color = word_after(report, 'Color') },
        notice = notice, chars = #report }
end
-- The kept lines of a report: those naming a SL.KEEP word, at most REPORT_LINES lines and REPORT_CHARS characters
function SL.keep(report)
    local out, n = {}, 0
    if type(report) ~= 'string' then return out end
    for line in (report .. '\n'):gmatch('([^\n]*)\n') do
        if #out >= SL.REPORT_LINES or n >= SL.REPORT_CHARS then break end
        for _, w in ipairs(SL.KEEP) do
            if line:find(w, 1, true) then
                local l = text(line:gsub('%s+$', ''), SL.LINE_CHARS)
                out[#out + 1], n = l, n + #l
                break
            end
        end
    end
    return out
end
-- The family of a target class (META.spawn.targets lab_1 MaleThug, lab_2 GuiChai): 'malethug' | 'guichai' | nil
function SL.family(class)
    local t = type(META.spawn) == 'table' and META.spawn.targets or {}
    if type(t.lab_1) == 'table' and class == t.lab_1.class then return 'malethug' end
    if type(t.lab_2) == 'table' and class == t.lab_2.class then return 'guichai' end
    return nil
end
-- The cut family of any data/cut_classes.lua class (the production route): the lab targets' own, else the row's
-- route ('body' | 'meshhead'); nil for anything else
function SL.cut_family(class, row)
    local f = SL.family(class)
    if f then return f end
    if type(row) ~= 'table' then return nil end
    if row.route == 'body' then return 'body' end
    if row.route == 'meshhead' then return 'meshhead' end
    return nil
end
-- The frame a slice (cut or re-slice) last ran in, or nil: one slice a frame over every caller
function SL.cut_frame() return st.cut_f end

-- ---------- reads inside the jobs ----------
-- A bone's world location on a skinned component (GetBoneIndex, then GetSocketTransform RTS_World): {x, y, z} | nil,
-- 'absent' (INDEX_NONE) | nil, 'unread'
local function bone_at(mesh, bone)
    local ok, i = ue.call(mesh, 'GetBoneIndex', ue.fname(bone))
    if not ok or not num(i) then return nil, 'unread' end
    if i < 0 then return nil, 'absent' end
    local okt, t = ue.call(mesh, 'GetSocketTransform', ue.fname(bone), SL.RTS_WORLD)
    if not okt then return nil, 'unread' end
    local p = xyz(ue.prop(t, 'Translation'))
    if not p then return nil, 'unread' end
    return p
end
-- The named bones on c: { [name] = {x,y,z} | 'absent' | 'unread' } (a raised read goes to ue.caught as step)
local function bones_on(c, names, step)
    local at = {}
    for _, b in ipairs(names) do
        local okb, p, w = pcall(bone_at, c, b)
        if not okb then at[b] = caught(p, step) and 'unread' else at[b] = p or w or 'unread' end
    end
    return at
end
local function leader_of(c) return ue.weak(ue.get(c, 'LeaderPoseComponent')) end
-- The components of a list of the actor's skeletal ones (SkeletalMeshComponent only) whose name starts with an Akasha
-- half prefix; halves_of reads the list (and answers whether it read: an unread list is never "no half")
local function halves_in(list)
    local out = {}
    for _, c in ipairs(list) do
        local n = ue.name(c) or ''
        if n:sub(1, #SL.POS) == SL.POS then out[#out + 1] = { c = c, name = n, side = 'positive' }
        elseif n:sub(1, #SL.NEG) == SL.NEG then out[#out + 1] = { c = c, name = n, side = 'negative' } end
    end
    return out
end
local function halves_of(actor)
    local list, read = ue.components(actor, SL.SKM)
    return halves_in(list), read == true
end
-- A component of the actor by name among its skinned components (SkinnedMeshComponent: cloth included; list: that
-- list read once already), or nil
local function comp_named(actor, name, list)
    for _, c in ipairs(list or (ue.components(actor, SL.SKINNED))) do
        if ue.name(c) == name then return c end
    end
    return nil
end
local function mats_of(c)
    local okn, n = ue.call(c, 'GetNumMaterials')
    n = okn and math.tointeger(n) or nil
    if not n then return 'unread', nil end
    local out = {}
    for i = 0, math.min(n, SL.MATS_MAX) - 1 do
        local ok, m = ue.call(c, 'GetMaterial', i)
        m = ok and ue.p(m) or nil
        out[#out + 1] = ok and name_or(m, 'none') or 'unread'
    end
    return n, out
end
-- The material count and the last slot's name (slot n - 1, where the slicer puts the cap; mats_of stops at MATS_MAX):
-- n | 'unread', that slot's name ('none' for no material, unnamed (default '?') when its name did not read) |
-- 'unread' | nil
local function last_mat(c, unnamed)
    local okn, n = ue.call(c, 'GetNumMaterials')
    n = okn and math.tointeger(n) or nil
    if not n then return 'unread', nil end
    if n < 1 then return n, nil end
    local ok, m = ue.call(c, 'GetMaterial', n - 1)
    m = ok and ue.p(m) or nil
    return n, ok and name_or(m, 'none', unnamed) or 'unread'
end
local function simulating(c)
    local ok, v = ue.call(c, 'IsSimulatingPhysics', ue.fname('None'))
    if ok and type(v) == 'boolean' then return v end
    return 'unread'
end
local function stream_flags(asset)
    local p, nv = ue.prop(asset, 'bHasStreamingUpdatePending'), ue.prop(asset, 'NeverStream')
    return bool_or(p, 'unread'), bool_or(nv, 'unread')
end
-- c's SkinnedAsset when it is a SkeletalMesh, else nil
local function skm_asset(c)
    local asset = ue.prop(c, 'SkinnedAsset')
    if ue.valid(asset) and ue.is_a(asset, SL.SKMESH) == true then return asset end
    return nil
end
-- A prep's answer from the asset's streaming flags: asset, pending, never_stream, refused 'lod_streaming' unless the
-- pending flag reads false
local function streaming(asset)
    local pending, never = stream_flags(asset)
    return { asset = ue.full(asset) or 'unread', pending = pending, never_stream = never,
        refused = pending ~= false and 'lod_streaming' or nil }
end
-- The per-LOD CPU bits of a SkeletalMesh asset (lab_slice_lod, its header: SourceModels, not the deprecated LODInfo);
-- a plain Prepare handle that reads all zero (nothing prepared)
SL.lod_view, SL.zero_handle = LD.view, LD.zero
-- Reads for a caller's own guarded job (lab_slice_watch): a component's SkeletalMesh, an actor's Akasha halves and a
-- component's last material slot
SL.skm_asset, SL.halves_of, SL.last_mat = skm_asset, halves_of, last_mat
local function bounds_of(c)
    local ksl = ue.cdo('ksl')
    if not ksl then return nil end
    local o, e, rad = {}, {}, {}
    local ok = ue.call(ksl, 'GetComponentBounds', c, o, e, rad)
    if not ok then return nil end
    return xyz(o)
end
-- The victim body's own fields of reqs and brief: its name (name: read already), IsA SkeletalMeshComponent, leader,
-- asset, bVisible, bHiddenInGame
local function body_view(v, name)
    local body = body_of(v)
    return { body = name or ue.name(body) or '?', body_is_skm = body_skm(v),
        body_leader = name_or(leader_of(body), 'none'), body_asset = ue.full(ue.prop(body, 'SkinnedAsset')) or 'none',
        body_visible = or_unread(ue.prop(body, 'bVisible')), body_hidden = or_unread(ue.prop(body, 'bHiddenInGame')) }
end

-- ---------- scan: the candidates of a pick (one 'slicer.read' call) ----------
-- list: { { rec (a victim or keep record), key } }; pawn: the player's keep record. -> { player = {x,y,z} | nil,
-- items = { { why ('gone', 'destroyed', 'collected', 'no_body', 'no_pelvis', 'vanilla_sliced') | nil, pelvis, dist_m,
-- halves } } } in list order
local function scan_job(list, pawn)
    local p = pawn and ue.live(pawn) or nil
    local player = p and ue.root_loc(p) or nil
    local items = {}
    for i, e in ipairs(list) do
        local it = {}
        items[i] = it
        local obj, why = LAB.alive(e.rec)
        if not obj then
            it.why = why == 'collected' and 'gone' or why or 'gone'
        else
            local body = ue.prop(obj, 'Mesh')
            if not is_skm(body) then it.why = 'no_body'
            else
                local okb, pelvis = pcall(bone_at, body, 'pelvis')
                if not okb then caught(pelvis, 'scan') pelvis = nil end
                it.pelvis = pelvis
                if not pelvis then it.why = 'no_pelvis' end
                local okc, hs, hread = pcall(halves_of, obj)
                local okh = okc and hread
                it.halves = okh and #hs or 'unread'
                if not it.why then
                    if not okh then it.why = 'halves_unread' elseif #hs > 0 then it.why = 'vanilla_sliced' end
                end
                if pelvis and player then
                    local d = sub(pelvis, player)
                    it.dist_m = math.floor(len(d) / 10 + 0.5) / 10
                end
            end
        end
    end
    return { player = player, items = items }
end
function SL.scan(list, pawn)
    if type(list) ~= 'table' then return false, 'bad_args' end
    return answer(run('slicer.read', scan_job, list, pawn))
end

-- ---------- reqs: the components, the body, the bones (one 'slicer.read' call) ----------
-- Every skinned component (at most COMPS_MAX): name, class, is_skm (IsA SkeletalMeshComponent: a ChaosClothComponent
-- reads false and is never passed to the slicer), leader (the LeaderPoseComponent's name or 'none'), parent (the
-- AttachParent's name), asset (SkinnedAsset full name), n_lods, sim, n_mat, mats, same_skel (the body's Skeleton);
-- the body (Character.Mesh) and the bones on it. The objects go to the frame cache by name ('comp:<name>')
local function reqs_job(rec, bones)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local body = body_of(v)
    if not ue.valid(body) then return { refused = 'no_body' } end
    local list, read = ue.components(obj, SL.SKINNED)
    if not read then return { refused = 'components_unread' } end
    local bskel = ue.prop(ue.prop(body, 'SkinnedAsset'), 'Skeleton')
    local comps, body_name = {}, ue.name(body) or '?'
    for _, c in ipairs(list) do
        if #comps >= SL.COMPS_MAX then break end
        local name = ue.name(c) or '?'
        local asset = ue.prop(c, 'SkinnedAsset')
        local skel = ue.prop(asset, 'Skeleton')
        local e = { name = name, class = class_of(c) or 'unread', is_skm = ue.is_a(c, SL.SKM) == true,
            body = ue.same(c, body), leader = name_or(leader_of(c), 'none'),
            parent = name_or(ue.prop(c, 'AttachParent'), 'none'), asset = ue.full(asset) or 'none',
            asset_skm = ue.is_a(asset, SL.SKMESH) == true }
        if ue.valid(skel) and ue.valid(bskel) then e.same_skel = ue.same(skel, bskel) else e.same_skel = 'unread' end
        local okl, nl = ue.call(c, 'GetNumLODs')
        e.n_lods = okl and math.tointeger(nl) or 'unread'
        e.sim = simulating(c)
        e.n_mat, e.mats = mats_of(c)
        comps[#comps + 1] = e
        remember('comp:' .. name, c)
    end
    local at = bones_on(body, bones or {}, 'reqs')
    remember('body', body)
    remember('actor', obj)
    local r = body_view(v, body_name)
    r.comps, r.bones = comps, at
    return r
end
function SL.reqs(rec, bones) return answer(run('slicer.read', reqs_job, rec, bones)) end

-- ---------- hats and masks (a head slice's falls, lab_gib) ----------
-- The fall class lab_gib copies: 'static' | 'skinned' | 'other' (a Chaos cloth one too)
local fall_kind = KB.gib_class
-- Drawn now: not ue_lab's comp_hidden (bVisible true and bHiddenInGame false, property reads); nil when unread
local function drawn(c)
    local hid = L.comp_hidden(c)
    if hid == nil then return nil end
    return not hid
end
-- The actor's SceneComponents by name (one K2_GetComponentsByClass), the first of each name; nil when unread
local function scene_by_name(obj)
    local list, read = ue.components(obj, SL.SCENE)
    if not read then return nil end
    local by = {}
    for _, c in ipairs(list) do
        local n = ue.name(c)
        if n and by[n] == nil then by[n] = c end
    end
    return by
end
-- Before the cut (inside brief's 'slicer.read'): each named component's class, fall kind and whether it is drawn
local function extras_read(obj, names)
    local by = scene_by_name(obj)
    if not by then return 'unread' end
    local out = {}
    for i, n in ipairs(names) do
        if i > SL.EXTRAS_MAX then break end
        local c = by[n]
        if c then
            local cls = class_of(c) or 'unread'
            out[n] = { class = cls, kind = fall_kind(cls), drawn = drawn(c) }
        else
            out[n] = { absent = true }
        end
    end
    return out
end
-- 'slicer.drop' (a head slice, the frame after its after step): each named hat or mask, where the slicer left it (on
-- a half, re-led by it, or on the hidden source), its world transform read (K2_GetComponentToWorld), then hidden
-- (SetHiddenInGame(true, false)); a ue.keep_mod record each, for lab_gib's fall copy
local function drop_job(rec, names)
    local v = victim(rec)
    if not v.obj then return { refused = 'gone', host_why = v.why } end
    local by = scene_by_name(v.obj)
    if not by then return { refused = 'components_unread' } end
    local items = {}
    for i, n in ipairs(names) do
        if i > SL.EXTRAS_MAX then break end
        local c = by[n]
        if c then
            local cls = class_of(c) or 'unread'
            local okx, t = ue.call(c, 'K2_GetComponentToWorld')
            local it = { name = n, class = cls, kind = fall_kind(cls), xf = okx and KB.plain_xf(t) or nil,
                rec = ue.keep_mod(c) }
            it.hidden = ue.set_hidden(c, true) == true
            items[#items + 1] = it
        else
            items[#items + 1] = { name = n, why = 'absent' }
        end
    end
    return { items = items }
end
-- names: the class row's fall list (its hats and masks). -> ok, why, { items = { { name, class, kind, xf, rec,
-- hidden } | { name, why } } }
function SL.drop(rec, names)
    if type(names) ~= 'table' then return false, 'bad_args' end
    return answer(run('slicer.drop', drop_job, rec, names))
end

-- ---------- brief: the body and the skinned components' names (one 'slicer.read' call; the production route) ----------
-- reqs without the per-component reads (a death pays only these): every skinned component's name (names, at most
-- COMPS_MAX); the body's checks and asset; how many Akasha halves the actor already holds (ours or the game's). extras
-- (optional, the class row's hats and masks): each one's class, fall kind and whether it is drawn before the cut
-- (extras_read). The body and the actor go to the frame cache ('body', 'actor')
local function brief_job(rec, extras)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local body = body_of(v)
    if not ue.valid(body) then return { refused = 'no_body' } end
    local list, read = ue.components(obj, SL.SKINNED)
    if not read then return { refused = 'components_unread' } end
    local names = {}
    for _, c in ipairs(list) do
        if #names >= SL.COMPS_MAX then break end
        names[#names + 1] = ue.name(c) or '?'
    end
    local okc, hs, hread = pcall(halves_of, obj)
    local okh = okc and hread
    local ex = nil
    if type(extras) == 'table' and extras[1] ~= nil then
        local oke, e = pcall(extras_read, obj, extras)
        ex = oke and e or 'unread'
        if not oke then caught(e, 'brief') end
    end
    remember('body', body)
    remember('actor', obj)
    local r = body_view(v)
    r.names, r.halves, r.extras = names, okh and #hs or 'unread', ex
    return r
end
function SL.brief(rec, extras) return answer(run('slicer.read', brief_job, rec, extras)) end

-- ---------- bones: world bone locations on the body or on a half (one 'slicer.read' call) ----------
-- The production route reads the plane's bones again in the cut frame (a ragdoll moves between frames). half: a cut's
-- ue.keep_mod record (live in this frame: its full name, class included, is the one the cut kept from the actor's
-- SkeletalMeshComponents), else the body (Character.Mesh). -> { bones = { [name] = {x,y,z} | 'absent' | 'unread' },
-- comp }
local function bones_job(rec, names, half_rec)
    local v = victim(rec)
    if not v.obj then return { refused = 'gone', host_why = v.why } end
    local c
    if half_rec ~= nil then
        c = ue.live_mod(half_rec)
        if not c then return { refused = 'no_half' } end
    else
        c = body_of(v)
        if not body_skm(v) then return { refused = 'body_not_skm' } end
    end
    return { bones = bones_on(c, names, 'bones'), comp = ue.name(c) or '?' }
end
function SL.bones(rec, names, half_rec)
    if type(names) ~= 'table' then return false, 'bad_args' end
    return answer(run('slicer.read', bones_job, rec, names, half_rec))
end

-- ---------- lodinfo: the per-LOD CPU bits (one 'slicer.lodinfo' call) ----------
-- For each component named (found this frame by reqs or after), its SkinnedAsset (IsA SkeletalMesh): lab_slice_lod's
-- view (SourceModels: UE 5.7 keeps the per-LOD info there; LODInfo is deprecated and reads empty) and the component's
-- GetNumLODs and ForcedLodModel. cpu: LOD 0's bit (the LOD a non-prepared slice extracts at LODIndex 0; true | false |
-- 'unread'); soft when SourceModels read but LOD 0 gave no boolean (the callers let the native preflight decide: it
-- checks the bit and the CPU buffers itself and returns false cleanly, skeptic native)
local function cpu_of(c)
    local asset = ue.prop(c, 'SkinnedAsset')
    if not ue.valid(asset) or ue.is_a(asset, SL.SKMESH) ~= true then return { cpu = 'unread', why = 'no_skeletal_mesh' } end
    local v = LD.view(asset)
    local okl, nl = ue.call(c, 'GetNumLODs')
    local r = { n = v.n_src, n_legacy = v.n_legacy, bits = v.bits, n_lods = okl and math.tointeger(nl) or 'unread',
        forced = or_unread(ue.prop(c, 'ForcedLodModel')) }
    if v.n_src == 'unread' then
        r.cpu, r.why = 'unread', v.err or 'no_source_models'
        return r
    end
    local b = nil                                       -- a false bit stays false ('x and false or nil' reads nil)
    if type(v.bits) == 'table' then b = v.bits[1] end
    if type(b) == 'boolean' then
        r.cpu = b
        return r
    end
    r.cpu, r.soft, r.why = 'unread', true, v.n_src == 0 and 'no_lod' or 'not_bool'
    return r
end
local function lodinfo_job(names)
    local out = {}
    for _, k in ipairs(names) do
        local c = recall(k)
        out[k] = c and cpu_of(c) or { cpu = 'unread', why = 'not_found' }
    end
    return { lodinfo = out }
end
-- names: frame-cache keys ('comp:<name>', 'body', 'half:positive', 'half:negative'). -> ok, why, { lodinfo = { [key]
-- = { n (#SourceModels), n_legacy (#LODInfo), bits, n_lods, forced, cpu, soft, why } } }
function SL.lodinfo(names)
    if type(names) ~= 'table' then return false, 'bad_args' end
    return answer(run('slicer.lodinfo', lodinfo_job, names))
end
-- The CPU bit of the halves the after step left in the frame cache (pos, neg: whether that side was found; one
-- SL.lodinfo, none when neither). -> ok, why, data, pos_cpu, neg_cpu (nil for a side not asked)
function SL.half_cpu(pos, neg)
    local keys = {}
    if pos then keys[#keys + 1] = 'half:positive' end
    if neg then keys[#keys + 1] = 'half:negative' end
    if not keys[1] then return true end
    local ok, why, d = SL.lodinfo(keys)
    if not ok then return false, why, d end
    local pc, nc
    if pos then pc = (d.lodinfo['half:positive'] or {}).cpu end
    if neg then nc = (d.lodinfo['half:negative'] or {}).cpu end
    return true, nil, d, pc, nc
end

-- ---------- the CVars (the crash-flagged path must read exactly 0; the free-buffers CVar is logged) ----------
function SL.cvars()
    local out = {}
    local v, err = run('probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics',
        function() return { v = ue.cvar_int(SL.CVAR_ENGINE_SIM) } end)
    out.engine_sim = type(v) == 'table' and v.v or 'unread'
    out.engine_sim_err = v == nil and err ~= nil and text(err) or nil
    local f, ferr = run('probe.cvar.r.FreeSkeletalMeshBuffers', function() return { v = ue.cvar_int(SL.CVAR_FREE) } end)
    out.free_buffers = type(f) == 'table' and f.v or 'unread'
    out.free_buffers_err = f == nil and ferr ~= nil and text(ferr) or nil
    if v == nil then return false, err ~= nil and text(err) or 'unread', out end
    return true, nil, out
end

-- ---------- preflight ----------
-- The same-frame checks before a slicer call on one component: valid, IsA SkeletalMeshComponent, its SkinnedAsset a
-- SkeletalMesh, the asset's streaming flags (a pending update refuses 'lod_streaming', unread too); found by name
-- among the actor's skinned components ('body' = Character.Mesh). The component goes to the frame cache ('target')
local function prep_job(rec, name)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local c
    if name == 'body' then c = body_of(v) else c = comp_named(obj, name) end
    if not ue.valid(c) then return { refused = 'not_found' } end
    if not is_skm(c) then return { refused = 'not_skm' } end
    local asset = skm_asset(c)
    if not asset then return { refused = 'no_skeletal_mesh' } end
    local r = streaming(asset)
    r.follower = ue.valid(leader_of(c))
    if r.refused then return r end
    remember('target', c)
    remember('actor', obj)
    return r
end
local function preflight_job(vp, vn, opts)
    local c, lib = recall('target'), ue.cdo(SL.LIB)
    if not c then return { refused = 'target_gone' } end
    if not lib then return { refused = 'no_lib' } end
    local rt = {}
    local t0 = clock()
    local ok, ret = ue.call(lib, 'DebugSkeletalMeshSlicePreflight', c, vp, vn, opts, rt)
    local ms = (clock() - t0) * 1000
    local report = ue.str(rt.OutReport) or ''
    local rv = nil                                  -- the ReturnValue (false kept)
    if ok then rv = bool_or(ret, nil) end
    return { ok = ok == true, ret = rv, err = (not ok) and text(ret) or nil, ms = r1(ms),
        report = report }
end
-- A preflight that found the cut workable: the call ran and returned true, source data ok, triangles on both sides
function SL.pre_good(d)
    return type(d) == 'table' and d.ok == true and d.ret == true and d.src_ok == true and num(d.pos) and d.pos > 0
        and num(d.neg) and d.neg > 0
end
-- One preflight on the component name ('body' or a component's name) of the victim rec: the same-frame checks
-- ('slicer.read'), then DebugSkeletalMeshSlicePreflight (5 args) with CapMaterial none ('slicer.preflight'). The
-- parsed report (SL.parse), its kept lines, the verdict cached per asset when the call ran (force or not: a caller that
-- trusts the cache asks SL.verdict first). -> ok (the call ran and returned), why, data
-- The same-frame checks of a preflight ('slicer.read': the 'target' into the frame cache) -> ok, why, data
local function prep(rec, name) return answer(run('slicer.read', prep_job, rec, name)) end
-- A preflight's answer from its run (r, err, det) and the prep's data: the asset and streaming flags, the parsed report
-- and its kept lines (SL.preflight's and lab_slice_lod's rungs alike). -> ok, why, d
local function pre_tail(r, err, det, dr)
    local ok, why, d = answer(r, err, det)
    d = d or {}
    d.asset, d.pending, d.never_stream, d.follower = dr.asset, dr.pending, dr.never_stream, dr.follower
    if not ok then return false, why, d end
    local parsed = SL.parse(d.report)
    d.lines = SL.keep(d.report)
    d.report = nil
    for k, v in pairs(parsed) do d[k] = v end
    if not d.ok then return false, d.err or 'call_failed', d end
    return true, nil, d
end
function SL.preflight(rec, name, P, N, cell)
    local okp, wp = SL.plane_ok(P, N)
    if not okp then return false, wp end
    local opts = SL.options(nil, cell)
    local oko, wo = SL.check_options(opts, false)
    if not oko then return false, wo end
    local okr, wr, dr = prep(rec, name)
    if not okr then return false, wr, dr end
    local vp, vn = ue.vec(P.x, P.y, P.z), ue.vec(N.x, N.y, N.z)
    local r, err, det = run('slicer.preflight', preflight_job, vp, vn, opts)
    local ok, why, d = pre_tail(r, err, det, dr)
    if d.ok then
        local key = d.asset
        if st.verdicts[key] == nil then st.verdict_order[#st.verdict_order + 1] = key end
        st.verdicts[key] = { ok = (SL.pre_good(d) and d.manual == 'true') == true, f = S.frame }
        if #st.verdict_order > SL.VERDICTS then st.verdicts[table.remove(st.verdict_order, 1)] = nil end
    end
    return ok, why, d
end
function SL.verdict(asset)
    local v = st.verdicts[asset]
    if v then return v.ok end
    return nil
end

-- ---------- the cap material (plan section 6, with the skeptics: an object never crosses frames) ----------
-- The flags of a material's base: skeletal (bUsedWithSkeletalMesh), sm, domain, blend, shading, two_sided; 'unread'
-- for a flag that read nothing
local function flags_of(m)
    local base = m
    if ue.is_a(m, SL.MATERIAL) ~= true then
        local ok, b = ue.call(m, 'GetBaseMaterial')
        b = ok and ue.p(b) or nil
        base = ue.valid(b) and b or nil
    end
    if not base then return { base = 'unread' } end
    return { base = ue.name(base) or '?', skeletal = or_unread(ue.prop(base, 'bUsedWithSkeletalMesh')),
        sm = or_unread(ue.prop(base, 'bUsedWithStaticMesh')), domain = or_unread(ue.prop(base, 'MaterialDomain')),
        blend = or_unread(ue.prop(base, 'BlendMode')), shading = or_unread(ue.prop(base, 'ShadingModel')),
        two_sided = or_unread(ue.prop(base, 'TwoSided')) }
end
local function fit(f) return type(f) == 'table' and f.skeletal == true and f.domain == 0 end
local function look_list()
    local LOOK = mod('lab_look')
    if not (LOOK and type(LOOK.candidates) == 'function') then return {} end
    local ok, list = pcall(LOOK.candidates)
    return ok and type(list) == 'table' and list or {}
end
-- The material object a choice names, found in this frame: M_SKInteriror by its path (find only), a lab_look
-- candidate by name (held by lab_look); valid and IsA MaterialInterface, else nil, 'cap_material_gone'
local function cap_of(choice)
    if type(choice) ~= 'table' then return nil, 'no_cap_material' end
    local m = nil
    if choice.kind == 'sk_interior' then m = ue.find(SL.SK_INTERIOR)
    elseif choice.kind == 'look' then
        for _, c in ipairs(look_list()) do if c.name == choice.name then m = c.m break end end
    end
    if not ue.valid(m) or ue.is_a(m, SL.MATIF) ~= true then return nil, 'cap_material_gone' end
    return m
end
-- The cut frame's CapMaterial (the choice found again) and the slicer library, r.cap the material's name; nil and
-- r.refused when either is missing
local function cap_lib(r, choice)
    local cap, cwhy = cap_of(choice)
    if not cap then r.refused = cwhy return nil end
    local lib = ue.cdo(SL.LIB)
    if not lib then r.refused = 'no_lib' return nil end
    r.cap = ue.name(cap) or '?'
    return cap, lib
end
-- 'slicer.mat': is M_SKInteriror resident (StaticFindObject only)? -> ok, why, { resident }
function SL.mat_find()
    return answer(run('slicer.mat', function() return { resident = ue.find(SL.SK_INTERIOR) ~= nil } end))
end
-- 'slicer.load': one LoadAsset of M_SKInteriror (its own frame), timed; found again after it
function SL.mat_load()
    if not MODOFF.enabled('lab_slice') then return false, 'modoff' end
    return answer(run('slicer.load', function()
        local t0 = clock()
        local o, found, loaded, err = ue.load_asset(SL.SK_INTERIOR)
        local ms = (clock() - t0) * 1000
        return { loaded = loaded == true, found = found == true, valid = o ~= nil, load_ms = r1(ms),
            after = ue.find(SL.SK_INTERIOR) ~= nil, err = err and text(err) or nil }
    end))
end
-- 'slicer.mat': the flags of M_SKInteriror (a Material: its own base) and of every lab_look candidate (tier A meat, B
-- meat, pale: GetBaseMaterial, then the base's flags), then the choice: the first with skeletal usage and domain
-- Surface (0), M_SKInteriror first ('sk_interior'), then the candidates in their order ('look_<tier>'); none:
-- 'no_cap_material'. The choice is a name record, never an object; alt the first fitting candidate (the fallback when
-- the M_SKInteriror hold fails)
local function flags_job()
    local r = { look = {} }
    local sk = ue.find(SL.SK_INTERIOR)
    r.sk = sk and flags_of(sk) or { base = 'not_resident' }
    local choice, why = nil, nil
    if sk and fit(r.sk) then choice, why = { kind = 'sk_interior', name = ue.name(sk) or 'M_SKInteriror' }, 'sk_interior' end
    for _, c in ipairs(look_list()) do
        local f = ue.valid(c.m) and flags_of(c.m) or { base = 'gone' }
        r.look[#r.look + 1] = { name = c.name, tier = c.tier, skeletal = f.skeletal, domain = f.domain, blend = f.blend,
            base = f.base }
        if fit(f) then
            if not choice then choice, why = { kind = 'look', name = c.name, tier = c.tier }, 'look_' .. tostring(c.tier) end
            r.alt = r.alt or { kind = 'look', name = c.name, tier = c.tier }
        end
    end
    r.choice, r.why = choice, why or 'no_cap_material'
    return r
end
function SL.mat_flags() return answer(run('slicer.mat', flags_job)) end
-- 'slicer.load': M_SKInteriror held on the player controller's keeper (ue.hold kind 'material', as lab_look holds its
-- candidates) once per map, so no GC takes it before the cut (a half's slot holds it after)
function SL.mat_hold()
    if st.hold_ep == ue.epoch and st.hold_id then return true, nil, { held = true, again = true } end
    return answer(run('slicer.load', function()
        local m = ue.find(SL.SK_INTERIOR)
        if not m then return { refused = 'not_resident' } end
        local host = ue.first_of('PlayerController')
        if not host then return { refused = 'no_host' } end
        local id, why, add = ue.hold(host, m, 'material')
        if id == nil then return { refused = 'hold: ' .. tostring(why) .. (add ~= nil and (' ' .. tostring(add)) or '') } end
        st.hold_ep, st.hold_id = ue.epoch, id
        return { held = true }
    end))
end

-- ---------- the cut ----------
-- The cut frame's re-derivation ('slicer.read'): the actor alive, its Character.Mesh valid, IsA SkeletalMeshComponent,
-- no follower, its asset a SkeletalMesh, no Akasha half on the actor (ours or the game's), the streaming flags false,
-- the CapMaterial found again; objects into the frame cache
local function cut_prep_job(rec, choice)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local body = body_of(v)
    if not body_skm(v) then return { refused = 'body_not_skm' } end
    if ue.valid(leader_of(body)) then return { refused = 'body_follower' } end
    local asset = skm_asset(body)
    if not asset then return { refused = 'no_skeletal_mesh' } end
    local hs, hread = halves_of(obj)
    if not hread then return { refused = 'components_unread' } end
    if hs[1] then return { refused = 'has_halves', halves = #hs } end
    local r = streaming(asset)
    if r.refused then return r end
    local cap, lib = cap_lib(r, choice)
    if not cap then return r end
    remember('actor', obj)
    remember('body', body)
    remember('cap', cap)
    remember('lib', lib)
    return r
end
-- The slice itself, inside the family's armed name: the write counted, the self-call flag on around the one pcall'd
-- call and off on every path, then the result's components read in this same frame (each kept only when its address
-- is one of the actor's skeletal components, listed once), Intersections dropped unread. known: the addresses of the
-- halves the actor held before (a re-slice), never taken by the name cross-check. ph: a prepared handle table
-- (lab_slice_lod's prepared cut): SlicePreparedSkeletalMeshComponentRuntime instead, with no debug report
local function cut_job(lib, body, vp, vn, opts, res, rt, known, ph)
    st.cut_f, st.victim = S.frame, nil              -- the slice changes the victim: no later job reuses its reads
    ue.count_write(1)
    st.in_cut = true
    local t0 = clock()
    local fn, a4, a5, a6 = 'SliceSkeletalMeshComponentRuntimeWithDebugReport', opts, res, rt
    if ph then fn, a4, a5, a6 = 'SlicePreparedSkeletalMeshComponentRuntime', ph, opts, res end
    local okp, ok, ret = pcall(ue.call, lib, fn, body, vp, vn, a4, a5, a6)
    local ms = (clock() - t0) * 1000
    st.in_cut = false
    st.cuts = st.cuts + 1
    local rv = nil                                  -- the ReturnValue (false kept)
    if okp and ok then rv = bool_or(ret, nil) end
    local r = { okp = okp, ok = okp and ok == true, ret = rv, ms = r1(ms),
        err = (not okp) and text(ok) or ((not ok) and text(ret) or nil), report = ue.str(rt.OutDebugReport) or '' }
    pcall(rawset, res, 'Intersections', nil)
    local okr, pos, neg = pcall(function() return rawget(res, 'PositiveComponent'), rawget(res, 'NegativeComponent') end)
    r.res_read = okr
    local actor = recall('actor')
    local list = actor and ue.components(actor, SL.SKM) or {}
    local at = {}                                   -- each listed component's address, read once
    local function addr(c)
        if at[c] == nil then at[c] = ue.addr(c) or false end
        return at[c] or nil
    end
    local function mine(o)
        if not okr or o == nil then return nil, 'none' end
        local a = ue.addr(o)
        if a == nil then return nil, 'no_addr' end
        for _, c in ipairs(list) do
            if addr(c) == a then return ue.keep_mod(c), nil end
        end
        return nil, 'not_listed'
    end
    local pw, nw
    r.pos, pw = mine(pos)
    r.neg, nw = mine(neg)
    r.pos_from, r.neg_from = r.pos and 'res' or pw, r.neg and 'res' or nw
    -- the name cross-check (MakeUniqueObjectName suffixes; the game's own halves would match too: the prep refused them)
    r.named = {}
    for _, h in ipairs(halves_in(list)) do
        local a = known and addr(h.c) or nil
        if not (a and known[a]) then
            r.named[#r.named + 1] = h.name
            if h.side == 'positive' and not r.pos then r.pos, r.pos_from = ue.keep_mod(h.c), 'name' end
            if h.side == 'negative' and not r.neg then r.neg, r.neg_from = ue.keep_mod(h.c), 'name' end
        end
    end
    return r
end
-- The slice's arguments, every one built before the write count and the flag (skeptic marshal: ue.vec(P) raised after
-- in_cut): vp, vn, opts | nil, why (SL.check_options)
local function slice_args(P, N, cap, cell, lod)
    local vp, vn = ue.vec(P.x, P.y, P.z), ue.vec(N.x, N.y, N.z)
    local opts = SL.options(cap, cell, lod)
    local oko, wo = SL.check_options(opts, true)
    if not oko then return nil, wo end
    return vp, vn, opts
end
-- A slice's answer (run's r, err, det): the prep's cap, asset and streaming flag (dr), ran, the report parsed and its
-- kept lines; a key with a half joins the sliced set
local function slice_tail(r, err, det, dr, key)
    local ok, why, d = answer(r, err, det)
    d.cap, d.asset, d.never_stream = dr.cap, dr.asset, dr.never_stream
    -- a job's own refusal record (lab_slice_lod's cut on LOD k: 'lod_range', 'bit_unread') never reached the slicer
    d.ran = (type(r) == 'table' and not r.refused) or (type(r) ~= 'table' and not SL.refused(why))
    if type(d.report) == 'string' then
        d.parsed = SL.parse(d.report)
        d.report = SL.keep(d.report)
    end
    if d.pos or d.neg then SL.mark_sliced(key) end
    if not ok then return false, why, d end
    if not d.ok then return false, d.err or 'call_failed', d end
    if d.ret ~= true then return false, 'returned_false', d end
    return true, nil, d
end
-- One slice of the victim rec's Character.Mesh along (P, N) under the family's name (fam 'malethug' | 'guichai'),
-- CapMaterial the choice found again in this frame, CapGridCellSize cell. The guards, then the call; a raised or false
-- call still answers its data (the caller's after step decides by the halves). A key with a half joins the sliced set.
-- -> ok (the call ran and returned true), why, data { cap, ok, ret, ms, err, report (kept lines), parsed, pos, neg
-- (ue.keep_mod records), pos_from, neg_from, named, ran }. Always LOD 0 with its bit as read: it takes no lod (another
-- LOD, or a bit to set, goes only through lab_slice_lod's SL.cut_prep)
function SL.cut(fam, rec, P, N, choice, cell, key)
    if not SL.FAMILIES[fam] then return false, 'no_family' end
    if not MODOFF.enabled('lab_slice') then return false, 'modoff' end
    if st.cut_f == S.frame then return false, 'cut_this_frame' end
    local okp, wp = SL.plane_ok(P, N)
    if not okp then return false, wp end
    local pr, perr, pdet = run('slicer.read', cut_prep_job, rec, choice)
    local okr, wr, dr = answer(pr, perr, pdet)
    if not okr then return false, wr, dr end
    local body, cap, lib = recall('body'), recall('cap'), recall('lib')
    if not (body and cap and lib) then return false, 'target_gone', dr end
    local vp, vn, opts = slice_args(P, N, cap, cell)
    if not vp then return false, vn, dr end
    local r, err, det = run(SL.FAMILIES[fam], cut_job, lib, body, vp, vn, opts, {}, {})
    return slice_tail(r, err, det, dr, key)
end

-- ---------- the re-slice of a half (the production route's next part, plan section 5 G-RESLICE) ----------
-- The re-slice frame's re-derivation ('slicer.read'): the actor alive, the half (a cut's ue.keep_mod record) live, IsA
-- SkeletalMeshComponent, one of the actor's Akasha halves, no follower, its asset a SkeletalMesh with the streaming
-- flags false, the CapMaterial found again; known: the addresses of every half the actor holds before the call
local function reslice_prep_job(rec, half_rec, choice)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local half = ue.live_mod(half_rec)
    if not is_skm(half) then return { refused = 'no_half' } end
    local known, mine, ha = {}, false, ue.addr(half)
    local hs, hread = halves_of(obj)
    if not hread then return { refused = 'components_unread' } end
    for _, h in ipairs(hs) do
        local a = ue.addr(h.c)
        if a then
            known[a] = true
            if a == ha then mine = true end
        end
    end
    if not mine then return { refused = 'not_a_half' } end
    if ue.valid(leader_of(half)) then return { refused = 'half_follower' } end
    local asset = skm_asset(half)
    if not asset then return { refused = 'no_skeletal_mesh' } end
    local r = streaming(asset)
    r.known = known
    if r.refused then return r end
    local cap, lib = cap_lib(r, choice)
    if not cap then return r end
    remember('actor', obj)
    remember('target', half)
    remember('cap', cap)
    remember('lib', lib)
    return r
end
-- One slice of a half the route's earlier cut made (the Negative half that still holds the next part) along (P, N)
-- under 'slicer.reslice' (one name for every re-slice: a fault there never switches the first cut off). The caller
-- read that half's LOD 0 CPU bit (SourceModels) true first. The same call, flag and fresh tables as SL.cut; the halves the actor
-- held before are never taken for the new ones. -> as SL.cut
function SL.reslice(rec, half_rec, P, N, choice, cell, key)
    if not MODOFF.enabled('lab_slice') then return false, 'modoff' end
    if st.cut_f == S.frame then return false, 'cut_this_frame' end
    local okp, wp = SL.plane_ok(P, N)
    if not okp then return false, wp end
    local pr, perr, pdet = run('slicer.read', reslice_prep_job, rec, half_rec, choice)
    local okr, wr, dr = answer(pr, perr, pdet)
    if not okr then return false, wr, dr end
    local half, cap, lib = recall('target'), recall('cap'), recall('lib')
    if not (half and cap and lib) then return false, 'target_gone', dr end
    local vp, vn, opts = slice_args(P, N, cap, cell)
    if not vp then return false, vn, dr end
    local r, err, det = run('slicer.reslice', cut_job, lib, half, vp, vn, opts, {}, {}, dr.known)
    if type(r) == 'table' then st.reslices = st.reslices + 1 end
    return slice_tail(r, err, det, dr, key)
end

-- ---------- after: the halves, the children, the source ----------
-- want: { pos, neg (ue.keep_mod records from the cut), cap (the chosen material's name), children (component names),
-- bones (bone names read on each half, default head and neck_01), cloth (a component name whose spine_03 is read),
-- lean (the route: no Niagara walk, no asset, parent or child parent and leader names, the last slot only), recs (the
-- route: each half's ue.keep_mod record as rec) }. An unread component list refuses 'components_unread'.
-- Each half (the actor's skeletal components with an Akasha prefix): name, side, from_res (its address is the cut's
-- result), asset, n_lods, n_mat, mats, cap (the last slot), cap_ok, sim, parent, bounds_side (sign of (origin - P).N),
-- bones; every child's parent_after, leader_after and went ('positive', 'negative', 'source', 'other'); the Niagara
-- components' names and parents; the source's bVisible, bHiddenInGame, sim and pelvis. Halves into the frame cache
-- ('half:positive', 'half:negative') for SL.lodinfo
local function after_job(rec, P, N, want)
    local v = victim(rec)
    local obj = v.obj
    if not obj then return { refused = 'gone', host_why = v.why } end
    local lean = want.lean == true
    local pos = want.pos and ue.live_mod(want.pos) or nil
    local neg = want.neg and ue.live_mod(want.neg) or nil
    local body = body_of(v)
    -- the result's addresses, read once (as ue.same: an address that reads nil matches nothing); the source's on the
    -- first went() that gets that far (ba: nil unread, false when it matches nothing)
    local pa, na = ue.addr(pos), ue.addr(neg)
    local ba
    local out = { halves = {} }
    local hs, hread = halves_of(obj)
    if not hread then return { refused = 'components_unread' } end      -- never "no half"
    -- this step's halves only: an earlier after step of the frame (the route's or the probe's) leaves none behind
    if st.cache.f == S.frame then st.cache['half:positive'], st.cache['half:negative'] = nil, nil end
    for _, h in ipairs(hs) do
        local c = h.c
        local ca = ue.addr(c)
        local e = { name = h.name, side = h.side, from_res = ca ~= nil and (ca == pa or ca == na) }
        if want.recs then e.rec = ue.keep_mod(c) end   -- the route's (never in a record: an object inside)
        if not lean then e.asset = name_or(ue.prop(c, 'SkinnedAsset'), 'none') end
        e.sim = simulating(c)
        if not lean then e.parent = name_or(ue.prop(c, 'AttachParent'), 'none') end
        e.visible, e.hidden_in_game = or_unread(ue.prop(c, 'bVisible')), or_unread(ue.prop(c, 'bHiddenInGame'))
        local okl, nl = ue.call(c, 'GetNumLODs')
        e.n_lods = okl and math.tointeger(nl) or 'unread'
        local last
        if lean then
            e.n_mat, last = last_mat(c)
        else
            e.n_mat, e.mats = mats_of(c)
            last = type(e.mats) == 'table' and e.mats[#e.mats] or nil
            -- past MATS_MAX the list stops short of the last slot, the cap's: that slot read alone
            if type(e.n_mat) == 'number' and e.n_mat > SL.MATS_MAX then last = select(2, last_mat(c)) end
        end
        e.cap = last or 'unread'
        if last and want.cap then e.cap_ok = last == want.cap end
        if e.cap_ok == false then e.swapped = last end
        local o = bounds_of(c)
        if o then
            local d = dot(sub(o, P), N)
            e.bounds_side = d > 0 and 1 or d < 0 and -1 or 0
            e.bounds_d = r1(d)
        else
            e.bounds_side = 'unread'
        end
        e.bones = {}
        for _, b in ipairs(want.bones or { 'head', 'neck_01' }) do
            local okb, p, w = pcall(bone_at, c, b)                -- an absent bone stays 'absent' (bones_on's words)
            e.bones[b] = okb and (rv(p) or w) or 'unread'
        end
        out.halves[#out.halves + 1] = e
        -- the frame cache's half per side for SL.lodinfo: the cut's own result first (a re-slice leaves older halves)
        if e.from_res or not recall('half:' .. h.side) then remember('half:' .. h.side, c) end
    end
    local function went(p)
        if not ue.valid(p) then return 'other' end
        local a = ue.addr(p)
        if a == nil then return 'other' end
        if a == pa then return 'positive' end
        if a == na then return 'negative' end
        if ba == nil then ba = ue.valid(body) and ue.addr(body) or false end
        if a == ba then return 'source' end
        return 'other'
    end
    out.children = {}
    -- the skinned components, read once (only when a child or the cloth is asked)
    local wants = (type(want.children) == 'table' and want.children[1] ~= nil) or want.cloth
    local by = {}                                   -- the first of each name (comp_named's rule), each named once
    for _, c in ipairs(wants and (ue.components(obj, SL.SKINNED)) or {}) do
        local n = ue.name(c)
        if n and by[n] == nil then by[n] = c end
    end
    for _, n in ipairs(want.children or {}) do
        local c = by[n]
        if c then
            local parent = ue.prop(c, 'AttachParent')
            local leader = not lean and leader_of(c) or nil
            local w = went(parent)
            -- the route (lean) reads the leader only when the parent is neither half nor the source
            if lean and w == 'other' then leader = leader_of(c) end
            if w == 'other' and ue.valid(leader) then w = went(leader) end
            local e = { name = n, went = w }
            if not lean then e.parent_after, e.leader_after = name_or(parent, 'none'), name_or(leader, 'none') end
            out.children[#out.children + 1] = e
        else
            out.children[#out.children + 1] = { name = n, went = 'gone' }
        end
    end
    if not lean then
        out.niagara = {}
        for _, c in ipairs((ue.components(obj, SL.NIAGARA))) do
            if #out.niagara >= SL.NIAGARA_MAX then break end
            local parent = ue.prop(c, 'AttachParent')
            out.niagara[#out.niagara + 1] = { name = ue.name(c) or '?', parent_after = name_or(parent, 'none'),
                went = went(parent) }
        end
    end
    if ue.valid(body) then
        local vis, hid = ue.prop(body, 'bVisible'), ue.prop(body, 'bHiddenInGame')
        local okb, pelvis, pw = pcall(bone_at, body, 'pelvis')
        out.source = { name = ue.name(body) or '?', visible = or_unread(vis), hidden_in_game = or_unread(hid),
            sim = simulating(body), pelvis = okb and (rv(pelvis) or pw) or 'unread' }
    else
        out.source = { name = 'gone' }
    end
    if want.cloth then
        local c = by[want.cloth]
        local okb, p, w = false, nil, nil
        if c then okb, p, w = pcall(bone_at, c, 'spine_03') end
        out.cloth = { name = want.cloth, spine_03 = okb and (rv(p) or w) or 'unread' }
    end
    return out
end
function SL.after(rec, P, N, want)
    if type(want) ~= 'table' then return false, 'bad_args' end
    return answer(run('slicer.after', after_job, rec, P, N, want))
end

-- ---------- the post-fix (plan section 4 step 5) ----------
-- 'slicer.rehome': the victim's component named name (IsA SkeletalMeshComponent) attached to the Positive half
-- (K2_AttachToComponent(pos, None, SnapToTarget x3, false)) and led by it (SetLeaderPoseComponent(pos, true, true));
-- both read back. pos: the cut's ue.keep_mod record, live in this frame (its full name, class included, is the one the
-- cut kept from the actor's SkeletalMeshComponents)
local function rehome_job(rec, name, pos_rec)
    local v = victim(rec)
    if not v.obj then return { refused = 'gone', host_why = v.why } end
    local pos = ue.live_mod(pos_rec)
    if not pos then return { refused = 'no_positive' } end
    local c = comp_named(v.obj, name)
    if not is_skm(c) then return { refused = 'no_component' } end
    local ok1, e1 = ue.call(c, 'K2_AttachToComponent', pos, ue.fname('None'), SL.SNAP, SL.SNAP, SL.SNAP, false)
    local ok2, e2 = ue.call(c, 'SetLeaderPoseComponent', pos, true, true)
    return { ok1 = ok1 == true, ok2 = ok2 == true, err = (not ok1 and text(e1)) or (not ok2 and text(e2)) or nil,
        parent_after = name_or(ue.prop(c, 'AttachParent'), 'none'), leader_after = name_or(leader_of(c), 'none') }
end
function SL.rehome(rec, name, pos_rec) return answer(run('slicer.rehome', rehome_job, rec, name, pos_rec)) end
-- SetSimulatePhysics(false) on c, the simulation read before and after
local function unsim(c)
    local before = simulating(c)
    local ok, err = ue.call(c, 'SetSimulatePhysics', false)
    return { ok = ok == true, err = (not ok) and text(err) or nil, sim_before = before, sim_after = simulating(c) }
end
-- 'slicer.fix': SetSimulatePhysics(false) on the hidden source (the worker hides it and turns its collision off but
-- never stops its simulation: it would fall without bound and drag what stayed on it), read back
local function fix_job(rec)
    local v = victim(rec)
    if not v.obj then return { refused = 'gone', host_why = v.why } end
    if not body_skm(v) then return { refused = 'body_not_skm' } end
    return unsim(body_of(v))
end
function SL.fix_source(rec) return answer(run('slicer.fix', fix_job, rec)) end
-- 'slicer.fix' on a half a re-slice hid (the same post-fix: hidden, collision off, still simulating); half_rec the
-- earlier cut's ue.keep_mod record, live in this frame (one the cut kept from the actor's SkeletalMeshComponents)
local function fix_half_job(half_rec)
    local c = ue.live_mod(half_rec)
    if not c then return { refused = 'no_half' } end
    return unsim(c)
end
function SL.fix_half(half_rec) return answer(run('slicer.fix', fix_half_job, half_rec)) end
-- 'slicer.push': one impulse on a half (velocity change, cm/s) at a bone (default its root body), dir a plain unit
-- vector; the half is the cut's ue.keep_mod record, live in this frame (one the cut kept from the actor's
-- SkeletalMeshComponents)
local function push_job(half_rec, dir, speed, bone)
    local c = ue.live_mod(half_rec)
    if not c then return { refused = 'no_half' } end
    local ok, err = ue.call(c, 'AddImpulse', ue.vec(dir.x * speed, dir.y * speed, dir.z * speed),
        ue.fname(bone or 'None'), true)
    return { ok = ok == true, err = (not ok) and text(err) or nil }
end
function SL.push(half_rec, dir, speed, bone)
    if type(dir) ~= 'table' or not (num(dir.x) and num(dir.y) and num(dir.z)) or not num(speed) then
        return false, 'bad_args'
    end
    if type(bone) ~= 'nil' and type(bone) ~= 'string' then return false, 'bad_args' end
    return answer(run('slicer.push', push_job, half_rec, dir, speed, bone))
end

-- ---------- bookkeeping (Lua only) ----------
function SL.sliced(key) return key ~= nil and st.sliced[key] == true end
-- A key the slicer left at least one half on (the cut's result, or the after step's name search): no cut row ever
function SL.mark_sliced(key)
    if key == nil or st.sliced[key] then return end
    st.sliced[key] = true
    st.sliced_order[#st.sliced_order + 1] = key
    if #st.sliced_order > SL.SLICED_MAX then st.sliced[table.remove(st.sliced_order, 1)] = nil end
end
function SL.reserve(key, on) if key ~= nil then st.busy[key] = on == true or nil end end
function SL.busy(key) return key ~= nil and st.busy[key] == true end
-- Any corpse a slicer job holds now (the route's from its row, the probe's from its pick): the optional warm-ups
-- (lab_drops, lab_gib) wait, as they wait for lab_cut's jobs, so no slice frame stacks their spawns and loads
function SL.busy_any() return next(st.busy) ~= nil end
function SL.self_call() return st.in_cut == true or st.in_self == true end
-- Lua-only reads of the other modules for the probe and the route: lab_corpse's state of a kept key (nil when it keeps
-- none), lab_cut's job count (K.njobs, else its status' jobs on a lab_cut without njobs)
function SL.corpse_state(key)
    local K = mod('lab_corpse')
    if not (K and type(K.kept) == 'function') then return nil end
    local ok, list = pcall(K.kept)
    if not ok or type(list) ~= 'table' then return nil end
    for _, c in ipairs(list) do if c.key == key then return c.state end end
    return nil
end
function SL.cut_jobs()
    local K = mod('lab_cut')
    if not K then return 0 end
    if type(K.njobs) == 'function' then
        local ok, n = pcall(K.njobs)
        return ok and tonumber(n) or 0
    end
    if type(K.status) ~= 'function' then return 0 end
    local ok, s = pcall(K.status)
    return ok and type(s) == 'table' and tonumber(s.jobs) or 0
end

-- The LOD experiment's primitives (lab_slice_lod: SL.preflight_lod, SL.prepare, SL.prep_read, SL.cut_prep,
-- SL.release) on this module's own guard, frame cache, cut job and self flag
LD.bind({ SL = SL, LIB = SL.LIB, run = run, answer = answer, prep = prep, pre_tail = pre_tail, recall = recall,
    skm_asset = skm_asset, cut_job = cut_job, cut_read = cut_prep_job, slice_args = slice_args, slice_tail = slice_tail,
    self = function(on) st.in_self = on == true end, clock = clock, r1 = r1, text = text })

-- ---------- lifecycle ----------
-- Inert outside the beta; in the beta it only registers its switch gate (no listener, ticker or record)
function SL.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    MODOFF.feature('lab_slice', { gameplay = true })     -- mod-off and the vanilla compare stop new slices only
    return true
end
-- A map load: the frame cache, the holds' map and the reservations go; the sliced set (keys carry the epoch) and the
-- verdicts stay for the session
function SL.reset(reason)
    if reason ~= 'map' then return end
    st.cache, st.busy, st.hold_ep, st.hold_id = { f = -1 }, {}, nil, nil
end
function SL.status()
    local n = 0
    for _ in pairs(st.sliced) do n = n + 1 end
    return { init = st.init, cuts = st.cuts, reslices = st.reslices, calls = st.calls, refusals = st.refusals,
        sliced = n, in_cut = st.in_cut, held = st.hold_id ~= nil }
end
function SL.shutdown() st, A = new_state(), nil end
return SL
