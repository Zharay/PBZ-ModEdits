-- status: new for the beta, BD5 (offline only; the author's run decides) origin: docs/research/beta-dismemberment-research.md#what-the-cap-draws-today
-- lab_look.lua: the cap look probe and its tier resolver (docs/research/beta-dismemberment-plan.md BD5; research CM1,
-- CM4). Player beta only (META.beta_modules, after lab_plan); the probe and dev profiles never require it, and init
-- stays inert (no listener, no ticker, no record) unless LAB.beta(). BD11 (lab_cap) and lab_gib code against the API
-- below.
-- * When: init and warm() (after each map load) only queue. The ticker runs one step a frame, and only while all of
--   these hold (review round 2: no unproven native in an automatic warm-up or at the main menu):
--   - the cap_look knob asks for a tier ('textured' or 'game'). The default 'basic' never probes or builds, so a player
--     who keeps it makes none of these calls (nor lab_cap's cap_look_section, which needs a held candidate);
--   - a lab_death was seen on this map (a gameplay world: never the main menu, never right at a map load);
--   - lab_plan's quiet() reads true (no lab_death in 10 s, no hit in 3 s, not paused, mod-off and the vanilla compare
--     not on);
--   - the frame is not busy (a lab_death or a lab_cut_live seen this frame or the one before, through its own bus
--     listeners, or lab_cut's K.njobs() > 0), not paused, not off (MODOFF.feature 'lab_look');
--   - LAB.pinned() reads true (an unpinned build probes nothing), and lab_end has not come.
--   A step that loads or scans marks its frame one-shot. Nothing loads, creates or reads in a kill or commit frame.
-- * The probe (once per session, the slicer on up to SLICER_MAPS maps), in phases, each step its own frame:
--   1. cap_look_cvar: r.Material.IgnoreLVFUsageMode (lvf_mode; PBZ.exe registers it at 0, research 'Render risk').
--   2. cap_look_asset, one per path of LOOK.ASSETS: ue.asset (found, else LoadAsset) -> via 'found' | 'loaded' | 'nil'.
--   3. cap_look_sm, per static mesh (SM_FX_Flesh_001-004, the four SM_*_Head props, the NoHead corpse prop,
--      SM_Spine_001): GetNumSections(0), GetMaterial(i) for i below SLOTS, GetMaterialIndex of every CUT_SLOTS name
--      (>= 0 only), GetBounds (sphere radius, extent, origin), bAllowCPUAccess (cpu, a property read). A head prop's
--      cut slot material and another mesh's slot 0 join the material phase.
--   4. cap_look_slicer: GAAction_SliceSkeleton_C's CDO (StaticFindObject) and one FindAllOf capped at SLICER_CAP: per
--      object its outer and SliceOption bCreateCap, CapMaterial, CapGridCellSize, bCopyVertexColors, MaxOutputTexCoords
--      (struct fields of a top-level property). A CapMaterial joins the material phase; with no instance seen (the CDO
--      alone) the next map tries again, up to SLICER_MAPS maps.
--   5. cap_look_mat, per material: GetBaseMaterial and the Parent chain (PARENTS), the base material's domain, blend,
--      shading, two-sided, masked, clip and usage flags (the effective blend, shading and two-sided after the
--      BasePropertyOverrides of the MI chain), diff (the flags that differ from BasicShapeMaterial, the control that
--      renders on a PMC), and the parameter names over TEX_BC, TEX_N, TEX_OTHER (each answer's texture joins the
--      texture phase), SCALARS (non-zero) and VECTORS (non-black). A MaterialInstanceConstant answers its own
--      getters; a plain Material is read through one transient MID (KismetMaterialLibrary, flags 0, never attached).
--   6. cap_look_tex, per texture: VirtualTextureStreaming, SRGB, CompressionSettings, Blueprint_GetSizeX/Y.
--   7. cap_look_tier: the resolution (below), one record per new answer.
--   Top-level properties, struct fields of one and getters only: never an element of a struct array.
-- * The resolver (research CM4). A material passes when its domain is Surface (0), its shading model is not Unlit (0),
--   its blend mode is Opaque (0) or Masked (1), and the PMC's local vertex factory draws it: lvf_mode 1 or 2, or (0 or
--   unread) the base material's bUsedWithStaticMesh. Every unknown fails.
--   - Tier A (cap_look 'textured', meat): a MID of the first parent of TIER_A that passes, has a TEX_BC parameter
--     answering a texture, and whose texture's VirtualTextureStreaming equals T_FX_Flesh_001_BC's (both read: a non-VT
--     texture on a VT sampler draws the default texture), with T_FX_Flesh_001_BC (and T_FX_Flesh_001_N under the first
--     TEX_N name, when that parameter answers and the VT flags match too) set on it. pale: MI_Skull_Old_01 as it is.
--   - Tier B (cap_look 'game', meat): the first material that passes, in this order: the slicer CapMaterials, the
--     head props' cut slot materials, MI_FX_C2_Flesh_001_B. pale: MI_Skull_Old_01 as it is.
--   - Tier N (cap_look 'native', the default since route B of docs/research/slicer-stumps.md; the author 2026-11-01:
--     «the stumps ... still look amateurish»): the game's own art. meat: the first of LOOK.NATIVE that passes:
--     M_SKInteriror (the probable vanilla slicer cap, research section 6), then MI_FX_C2_Flesh_001_B. The NoHead stump
--     material (MI_NPC_SongXiaoWu_NoHead, the headless corpse prop's) is probed and logged first in N_tried but never
--     taken: it would need its stump's UV island in T_NPC_SongXiaoWu_NoHead_BC, which is [unknown]
--     (beta-dismemberment-research.md:520; the containers need the AES key, and GetSectionFromStaticMesh needs the
--     corpse prop's bAllowCPUAccess, which cap_look_sm 'nohead_sm' reads). pale: MI_Skull_Old_01 as it is (the bone
--     section is kept).
--   - dark has no tier: always the flat colour.
-- * The build (every map, after the resolution, under the same gates; it holds every resolved tier whichever one the
--   knob names, so a switch between 'textured' and 'game' takes the next cap at once, and lab_cap's test section has
--   its candidates; a switch from 'basic' waits for the probe and the build): the chosen assets through ue.asset under
--   'cap.look.load', the tier A MID under 'cap.look.mid' (CreateDynamicMaterialInstance, SetTextureParameterValue,
--   the K2_GetTextureParameterValue read-back: a texture that did not stick refuses tier A), then each kept material
--   held for the map with ue.hold(the player
--   controller, m, 'material') under 'cap.keep' (P9b's class: the keeper's hidden StaticMeshComponent roots it; Lua
--   references root nothing). One cap_look_build record per map. A map load ends the holds (ue.reset_caches) and the
--   build runs again.
-- * Names (meta.lua lab_risky, data/lab_classes.lua): 'cap.look.load' (linger 3), 'cap.look.read' (0), 'cap.look.mid'
--   (10, inherited), 'cap.look.slicer' (3), 'probe.cvar.r.Material.IgnoreLVFUsageMode' (0), and 'cap.keep' (M1a P9b's
--   hold class). Each step checks SENT.is_disabled and LAB.sig of its name first; a refused name skips its probe step
--   (one cap_look_skip record per name and why), 'sig_pending' waits a frame. The tier A MID's
--   SetTextureParameterValue is listed under 'lab.cut.stage' (BD0 MID_TEX), not under 'cap.look.mid': its build waits
--   for LAB.sig('lab.cut.stage') too.
-- * The knob cap_look (core/config.lua C.knob, read at every lookup): 'basic' (tier C everywhere), 'textured' (tier
--   A), 'game' (tier B), 'native' (tier N).
-- API, pinned for BD11 and lab_gib:
--   LOOK.material(section, side) -> m, tier | nil, why. section 'meat', 'pale' or 'dark' (caps_beta_sizing.sections),
--     side 'stump' or 'piece'. A pure lookup of what the build holds for the current cap_look: no load, no create, no
--     UFunction (ue.live's validity and name check only), safe inside 'lab.cut.stage'. tier 'A' (textured), 'B'
--     (game) or 'N' (native); the same answer for both sides. nil and why ('basic', 'pending' (probe or build not
--     done), 'refused' (no candidate passed, or its build failed), 'dark', 'gone' (a held object no longer live), 'off'
--     (not the beta, or mod-off), 'unpinned', 'bad_args') means tier C: the caller keeps the flat colour of
--     caps_beta_sizing.colors.
--     The caller sets m with ue_lab.set_material(c, slot, m) (BD4) and drops one tier on a failed read-back.
--   LOOK.candidates() -> { { name, m, tier } } the held materials, best first: tier A meat, tier B meat, tier N meat,
--     pale ({} while pending): lab_cap's cap_look_section tries each on its hidden section 3.
--   LOOK.native() -> { meat, mid, why }: what tier N holds, for lab_cap's cap_native record (pure lookup; mid false:
--     tier N holds a game material as it is, never a MID).
--   LOOK.stub() -> sm, { extent, origin } | nil, why: SM_Spine_001 held for the map (ue.hold kind 'mesh' under
--     'cap.keep', built with the tiers) and its bounds read in the probe, for lab_cap's vertebra stub (pure lookup).
--   LOOK.kmat_mid(outer, parent) -> mid | nil, why and LOOK.tex_param(mid, param, tex) -> set, same, err: the MID
--     calls this module and lab_iberico make inside their own armed jobs (no ue.count_write: ue.call counts the
--     SetTextureParameterValue write itself). LOOK.gates(s, owner, skip) -> { busy, quiet, gate }: the gates both
--     modules step under, over the module's own state (its listeners registered under owner).
--   lifecycle init(A) warm() reset(reason) shutdown() status().
-- * cut.size (lab_cut BD10 writes it inside 'lab.cut.stage', lab_cap BD11 reads it in C.build and C.attach_piece):
--   { cap = 'neck' | 'shoulder' | 'elbow' | 'hip' | 'knee' (head, upperarm, lowerarm, thigh, calf: the parts of
--   data/caps_beta_sizing.lua), L1 = cm | nil (|child - cut joint|), S = cm | nil (|upperarm_l - upperarm_r|), R = cm |
--   nil (the sized radius times the cap_scale knob), clamp = the bound that set R ('k1', 'k2', 'band_lo', 'band_hi',
--   'rmin', 'rmax'), scale = R / r_ref (ue.add_component opts.scale for every section of both ends), roll = { w, x, y,
--   z } | nil (a unit quaternion about the Cap's own +Z, composed after C.z_to(d): q = z_to(d) * roll; the Piece end
--   uses the cut-bone frame), src = 'read' | 'bucket' (a failed read: scale is the D8 bucket of data/lab_pairs.lua, R
--   and roll nil) }. The Cap meshes are data/caps_beta.lua's 'cap_<cap>_<s|p>_<section>' (BD2).
-- What the mock cannot prove: native faults, the real parameter names and flags, whether a material without PMC
-- shaders draws a grey grid, whether a hold keeps the assets alive for the map, LoadAsset's cost on a cold package.
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local LOOK = { SECTIONS = { 'meat', 'pale', 'dark' }, LVF = 'r.Material.IgnoreLVFUsageMode', SLICER_MAPS = 3,
    SLICER_CAP = 8, MAT_MAX = 24, TEX_MAX = 32, PARENTS = 4, SLOTS = 6, ERR_CHARS = 160 }
local function ref(dir, name) return dir .. name .. '.' .. name end
local VFX, HEADS = '/PBZVFXPack/VFX/', '/HuaShira/Characters/Hero/Hero_Hun/Weapon/Bullet/Head/'
local AKASHA, BONES = '/AkashaEffects/MaterialLibrary/Template/', '/Game/PBZContent/Environments/Props/Bones/Material/'
-- The candidates (research cap_look_asset; the chunk-id oracle, UE4SS_ObjectDump 26266538): key, kind, object path
LOOK.ASSETS = {
    { key = 'control', kind = 'mat', path = ref('/Engine/BasicShapes/', 'BasicShapeMaterial') },
    { key = 'flesh_mi', kind = 'mat', path = ref(VFX .. 'A_Materials/Common/Clip_002/', 'MI_FX_C2_Flesh_001_B') },
    { key = 'flesh_bc', kind = 'tex', path = ref(VFX .. 'A_Textures/', 'T_FX_Flesh_001_BC') },
    { key = 'flesh_n', kind = 'tex', path = ref(VFX .. 'A_Textures/', 'T_FX_Flesh_001_N') },
    { key = 'flesh_sm1', kind = 'sm', path = ref(VFX .. 'A_Meshes/FX_SM_Common/', 'SM_FX_Flesh_001') },
    { key = 'flesh_sm2', kind = 'sm', path = ref(VFX .. 'A_Meshes/FX_SM_Common/', 'SM_FX_Flesh_002') },
    { key = 'flesh_sm3', kind = 'sm', path = ref(VFX .. 'A_Meshes/FX_SM_Common/', 'SM_FX_Flesh_003') },
    { key = 'flesh_sm4', kind = 'sm', path = ref(VFX .. 'A_Meshes/FX_SM_Common/', 'SM_FX_Flesh_004') },
    { key = 'skull', kind = 'mat', path = ref(BONES, 'MI_Skull_Old_01') },
    { key = 'mai_sss', kind = 'mat', path = ref(AKASHA, 'MAI_Item_Subsurface') },
    { key = 'mai_item', kind = 'mat', path = ref(AKASHA, 'MAI_Item') },
    { key = 'head_malethug', kind = 'sm', path = ref(HEADS, 'SM_MaleThug_Head'), head = true },
    { key = 'head_spearman', kind = 'sm', path = ref(HEADS, 'SM_SpearMan_Head'), head = true },
    { key = 'head_huashan', kind = 'sm', path = ref(HEADS, 'SM_HuaShan_Head'), head = true },
    { key = 'head_sxyz', kind = 'sm', path = ref(HEADS, 'SM_SXYZ_Head'), head = true },
    { key = 'debug_mesh', kind = 'mat', path = ref('/Engine/EngineDebugMaterials/', 'DebugMeshMaterial') },
    { key = 'flatten', kind = 'mat', path = ref('/Engine/EngineMaterials/', 'FlattenMaterial') },
    { key = 'widget3d', kind = 'mat', path = ref('/Engine/EngineMaterials/', 'Widget3DPassThrough_Opaque_OneSided') },
    { key = 'vcol', kind = 'mat', path = ref('/Game/MasterMaterials/', 'M_Std_Layer_Vcol_Inta') },
    { key = 'wound_bc', kind = 'tex', path = ref('/SkinnedDecalComponent/WoundDecal/', 'WoundDecal_basecolor') },
    -- tier N (route B): the NoHead stump material, the probable vanilla slicer cap, and the headless corpse prop whose
    -- slots and bAllowCPUAccess say whether its stump section's UVs can be read (the island); the dump has all three
    -- [verified UE4SS_ObjectDump 26266538 :475702, :383232, :485334]
    { key = 'nohead_mi', kind = 'mat', path = ref('/Game/PBZContent/Characters/NPC/Songxiaowu/Material/',
        'MI_NPC_SongXiaoWu_NoHead') },
    { key = 'sk_interior', kind = 'mat', path = ref('/Game/Test/XYF/Materials/', 'M_SKInteriror') },
    { key = 'nohead_sm', kind = 'sm', path = ref('/Game/PBZContent/Characters/Corpse/Mesh/',
        'SM_SongXiaoWu_Die_Pose_NoHead_A_001') },
    -- the vertebra stub of a native neck Cap (lab_cap): the bones prop kit's spine [verified: chunk-id oracle,
    -- scratch/slicer/assets/out/oracle_gore2_hits.tsv]; its bounds size and place the stub
    { key = 'spine_sm', kind = 'sm', path = ref('/Game/PBZContent/Environments/Props/Bones/Mesh/', 'SM_Spine_001') },
}
-- Tier N: the best native flesh in order (keys of LOOK.ASSETS)
LOOK.NATIVE = { 'sk_interior', 'flesh_mi' }
-- The parameter names asked (research cap_look_mat): base colour, normal, the rest; scalars; vectors
LOOK.TEX_BC = { 'BaseColor', 'Base Color', 'BaseColorTexture', 'BaseColorMap', 'BC', 'Tex_BC', 'Albedo', 'Diffuse',
    'DiffuseTexture', 'Tex_Diffuse', 'Texture', 'MainTexture', 'Tex', 'BaseTexture', 'Color', 'D' }
LOOK.TEX_N = { 'Normal', 'NormalMap', 'NormalTexture', 'Tex_Normal', 'N' }
LOOK.TEX_OTHER = { 'ARM', 'ORM', 'MRA', 'RMA', 'DRA', 'DR', 'Mask', 'Masks', 'Packed', 'SlateUI', 'BO', 'NMR',
    'Layer1_BO', 'Layer1_NMR', 'Emissive', 'Opacity', 'OpacityMask', 'Erosion', 'Noise', 'DetailNormal',
    'SubsurfaceColor', 'BloodMask', 'Blood', 'Wound' }
LOOK.SCALARS = { 'Roughness', 'Metallic', 'Specular', 'Opacity', 'EmissiveStrength', 'Erosion', 'Clip', 'UVScale',
    'Tiling' }
LOOK.VECTORS = { 'Color', 'BaseColor', 'Tint', 'DebrisColor', 'DiffuseConst' }
LOOK.CUT_SLOTS = { 'Neck', 'Cut', 'Wound', 'Flesh', 'Blood', 'Stump', 'Meat', 'Section', 'Cap', 'Inner' }
-- The base material's flags as logged, in order (UMaterial props, dump 26266538 :29784-29879)
LOOK.FLAGS = { { 'domain', 'MaterialDomain' }, { 'blend', 'BlendMode' }, { 'shading', 'ShadingModel' },
    { 'two_sided', 'TwoSided' }, { 'masked', 'bIsMasked' }, { 'clip', 'OpacityMaskClipValue' },
    { 'sm', 'bUsedWithStaticMesh' }, { 'niagara_mesh', 'bUsedWithNiagaraMeshParticles' },
    { 'skeletal', 'bUsedWithSkeletalMesh' } }
-- The MI chain's overrides of the flags the checks read (MaterialInstanceBasePropertyOverrides)
LOOK.OVERRIDES = { { 'blend', 'BlendMode' }, { 'shading', 'ShadingModel' }, { 'two_sided', 'TwoSided' } }
LOOK.TIER_A = { 'skull', 'mai_sss', 'mai_item' }       -- research CM4: MI_Skull_Old_01 or MAI_Item_Subsurface
LOOK.SLICER_CDO = '/SGameCombatSystem/Weapon/Action/GAAction_SliceSkeleton.Default__GAAction_SliceSkeleton_C'
LOOK.SLICER_CLASS = 'GAAction_SliceSkeleton_C'
local MIC, MID, MAT = '/Script/Engine.MaterialInstanceConstant', '/Script/Engine.MaterialInstanceDynamic',
    '/Script/Engine.Material'
local TEX2D = '/Script/Engine.Texture2D'
local PHASES = { 'cvar', 'asset', 'sm', 'slicer', 'mat', 'tex', 'resolve', 'build', 'done' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua cap.look.*, the LVF CVar, cap.keep)
local N = {}
local F = {
    {"/Script/Engine.Material", "MaterialDomain"},
    {"/Script/Engine.Material", "BlendMode"},
    {"/Script/Engine.Material", "ShadingModel"},
    {"/Script/Engine.Material", "TwoSided"},
    {"/Script/Engine.Material", "bIsMasked"},
    {"/Script/Engine.Material", "OpacityMaskClipValue"},
    {"/Script/Engine.Material", "bUsedWithStaticMesh"},
    {"/Script/Engine.Material", "bUsedWithNiagaraMeshParticles"},
    {"/Script/Engine.Material", "bUsedWithSkeletalMesh"},
    {"/Script/Engine.MaterialInstance", "Parent"},
    {"/Script/Engine.MaterialInstance", "BasePropertyOverrides"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "bOverride_BlendMode"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "bOverride_ShadingModel"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "bOverride_TwoSided"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "BlendMode"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "ShadingModel"},
    {"/Script/Engine.MaterialInstanceBasePropertyOverrides", "TwoSided"},
    {"/Script/Engine.Texture", "VirtualTextureStreaming"},
    {"/Script/Engine.Texture", "SRGB"},
    {"/Script/Engine.Texture", "CompressionSettings"},
    {"/Script/Engine.StaticMesh", "bAllowCPUAccess"},
    {"/SGameCombatSystem/Weapon/Action/GAAction_SliceSkeleton.GAAction_SliceSkeleton_C", "SliceOption"},
    {"/Script/AkashaEffects.AkashaSkeletalMeshSliceOptions", "bCreateCap"},
    {"/Script/AkashaEffects.AkashaSkeletalMeshSliceOptions", "CapMaterial"},
    {"/Script/AkashaEffects.AkashaSkeletalMeshSliceOptions", "CapGridCellSize"},
    {"/Script/AkashaEffects.AkashaSkeletalMeshSliceOptions", "bCopyVertexColors"},
    {"/Script/AkashaEffects.AkashaSkeletalMeshSliceOptions", "MaxOutputTexCoords"},
}
LOOK.N, LOOK.F = N, F

local A = nil
local function new_state()
    return { init = false, ended = false, phase = 1, q = { asset = {}, sm = {}, mat = {}, tex = {}, build = {} },
        objs = {}, assets = {}, mats = {}, texs = {}, sms = {}, seen = {}, roles = {}, n_mat = 0, n_tex = 0, lvf = nil,
        slicer_maps = 0, slicer_seen = false, slicer_q = false, res = nil, res_key = nil, held = {}, built = nil,
        build_epoch = nil, skips = {}, busy_f = nil, busy = 0, steps = 0, death_ep = nil, wait = nil }
end
local st = new_state()
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r3(v) return num(v) and math.floor(v * 1000 + 0.5) / 1000 or nil end
local function err_text(e)
    e = tostring(e)
    return #e > LOOK.ERR_CHARS and e:sub(1, LOOK.ERR_CHARS) or e
end
local function path_of(o) local f = ue.full(o) return f and (f:match('^%S+ (.+)$') or f) or nil end
local function class_of(o) local f = ue.full(o) return f and f:match('^(%S+) ') or nil end
local function short(path) return type(path) == 'string' and (path:match('([^/.]+)$') or path) or 'unread' end
local function or_unread(v) if v == nil then return 'unread' end return v end

-- ---------- the MID calls (lab_iberico's build makes them too), inside the caller's armed job ----------
-- KismetMaterialLibrary:CreateDynamicMaterialInstance(outer, parent, None, 0) on its CDO; outer nil: the world, read
-- after the CDO. The MID | nil, why ('no_lib': no CDO or no outer, 'no_mid': nothing valid came back)
function LOOK.kmat_mid(outer, parent)
    local kmat = ue.cdo('kmat')
    if outer == nil then outer = ue.world() end
    if not (kmat and outer) then return nil, 'no_lib' end
    local ok, mid = ue.call(kmat, 'CreateDynamicMaterialInstance', outer, parent, ue.fname('None'), 0)
    mid = ok and ue.p(mid) or nil
    if not ue.valid(mid) then return nil, 'no_mid' end
    return mid
end
-- SetTextureParameterValue(param, tex) on mid, then K2_GetTextureParameterValue(param) read back: set (the call went
-- through), same (the read-back is tex), and the set's error text when it did not go through
function LOOK.tex_param(mid, param, tex)
    local oks, ws = ue.call(mid, 'SetTextureParameterValue', ue.fname(param), tex)
    local okg, back = ue.call(mid, 'K2_GetTextureParameterValue', ue.fname(param))
    local same = (okg and ue.same(ue.p(back), tex)) == true
    if oks == true then return true, same end
    return false, same, ws
end

-- ---------- gates ----------
-- The tier the cap_look knob asks for, read at every use: 'A' (textured), 'B' (game), 'N' (native), nil (basic)
local function knob_tier()
    local look = C.knob('cap_look')
    if look == 'textured' then return 'A' elseif look == 'game' then return 'B' end
    if look == 'native' then return 'N' end
    return nil
end
-- The gates this module and lab_iberico share, over a module's own state s ({ busy_f, death_ep, ended, skips }): its
-- listeners on LOOK.GATE_EVENTS under the bus owner `owner` (a lab_death marks the frame busy and the map seen, a
-- lab_cut_live the frame busy, lab_end ends the module), and
--   busy(): a busy frame (BD0): a lab_death or a lab_cut_live seen this frame or the one before, or lab_cut's jobs
--     waiting (K.njobs: staged or not committed yet; lab_cut ticks after both modules, so its commit frame shows here
--     as a job);
--   quiet(): a lab_death seen on this map and lab_plan's quiet moment: true | false, why ('no_death', 'no_plan',
--     'not_quiet');
--   gate(name[, probe]): 'ok', 'wait' (its sig check still pending: the same step next frame), or why the name is
--     refused ('disabled', 'sig_mismatch', 'sig_unknown', ...): one `skip` record { name, probe, why } per name and why.
LOOK.GATE_EVENTS = { 'lab_death', 'lab_cut_live', 'lab_end' }
function LOOK.gates(s, owner, skip)
    BUS.on('lab_death', owner, function() s.busy_f, s.death_ep = S.frame, ue.epoch end)
    BUS.on('lab_cut_live', owner, function() s.busy_f = S.frame end)
    BUS.on('lab_end', owner, function() s.ended = true end)
    local g = {}
    function g.busy()
        if s.busy_f and S.frame - s.busy_f <= 1 then return true end
        local K = package.loaded['lab_cut']
        return type(K) == 'table' and type(K.njobs) == 'function' and K.njobs() > 0
    end
    function g.quiet()
        if s.death_ep ~= ue.epoch then return false, 'no_death' end
        local PL = package.loaded['lab_plan']
        if not (type(PL) == 'table' and type(PL.quiet) == 'function') then return false, 'no_plan' end
        local ok, q = pcall(PL.quiet)
        if not (ok and q == true) then return false, 'not_quiet' end
        return true
    end
    function g.gate(name, probe)
        local why
        if SENT.is_disabled(name) then why = 'disabled'
        else
            local ok, w = LAB.sig(name)
            if ok then return 'ok' end
            if w == 'sig_pending' then return 'wait' end
            why = tostring(w or 'sig')
        end
        local k = name .. '|' .. why
        if not s.skips[k] then
            s.skips[k] = true
            LAB.rec(skip, { name = name, probe = probe, why = why }, true)
        end
        return why
    end
    return g
end
local G = nil                                           -- this module's gates (LOOK.init)
local function gate(name, probe) return G.gate(name, probe) end
-- Whether the probe and the build may step (the header): the knob asks for a tier, a lab_death was seen on this map
-- and lab_plan reads a quiet moment. true | false, why ('basic', 'no_death', 'no_plan', 'not_quiet')
local function wanted()
    if not knob_tier() then return false, 'basic' end
    return G.quiet()
end
-- The live object of a probe key: its keep record while ue.live holds, else a lookup by path (no load); nil when gone
local function obj_of(key)
    local o = st.objs[key] and ue.live(st.objs[key]) or nil
    if o then return o end
    local p = st.assets[key] and st.assets[key].path
    o = p and ue.find(p) or nil
    if o then st.objs[key] = ue.keep(o) end
    return o
end
-- A role of a material key ('candidate', 'cut_slot', 'mesh_slot', 'slicer'): one material may have several
local function role(key, r)
    st.roles[key] = st.roles[key] or {}
    st.roles[key][r] = true
end
-- A new material or texture for its phase, once per path (a material at most MAT_MAX, a texture TEX_MAX); a material
-- seen already takes the new role
local function add_mat(key, o, r)
    local p = path_of(o)
    if not p then return end
    if st.seen[p] then role(st.seen[p], r) return end
    if #st.q.mat + st.n_mat >= LOOK.MAT_MAX then return end
    st.seen[p] = key
    st.assets[key] = { path = p, kind = 'mat' }
    st.objs[key] = ue.keep(o)
    role(key, r)
    st.q.mat[#st.q.mat + 1] = { key = key }
end
local function add_tex(o, from)
    local p = path_of(o)
    if not p or st.seen[p] or #st.q.tex + st.n_tex >= LOOK.TEX_MAX then return end
    local key = 'tex:' .. p
    st.seen[p] = key
    st.assets[key] = { path = p, kind = 'tex' }
    st.objs[key] = ue.keep(o)
    st.q.tex[#st.q.tex + 1] = { key = key, from = from }
end

-- ---------- 1. the LVF CVar ----------
local function step_cvar()
    local g = gate('probe.cvar.r.Material.IgnoreLVFUsageMode', 'cvar')
    if g == 'wait' then return 'wait' end
    local v, err = nil, nil
    if g == 'ok' then
        v, err = LAB.armed('probe.cvar.r.Material.IgnoreLVFUsageMode', function() return ue.cvar_int(LOOK.LVF) end)
    else err = g end
    st.lvf = v
    LAB.rec('cap_look_cvar', { cvar = LOOK.LVF, lvf_mode = or_unread(v), err = err and err_text(err) or nil }, true)
end

-- ---------- 2. the candidates: found, else LoadAsset ----------
local function step_asset()
    local e = table.remove(st.q.asset, 1)
    if not e then return 'next' end
    local g = gate('cap.look.load', 'asset')
    if g == 'wait' then table.insert(st.q.asset, 1, e) return 'wait' end
    local r, err = nil, g ~= 'ok' and g or nil
    if g == 'ok' then
        LAB.oneshot()                                   -- a cold package loads here
        local t0 = os.clock()
        r, err = LAB.armed('cap.look.load', function()
            local o, via = ue.asset(e.path)
            return { o = o, via = via, ms = math.floor((os.clock() - t0) * 1000 + 0.5) }
        end)
    end
    local o = type(r) == 'table' and r.o or nil
    st.assets[e.key] = { path = e.path, kind = e.kind, via = o and r.via or 'nil' }
    if o then
        st.objs[e.key] = ue.keep(o)
        st.seen[e.path] = e.key
        if e.kind == 'mat' then
            role(e.key, 'candidate')
            st.q.mat[#st.q.mat + 1] = { key = e.key }
        elseif e.kind == 'sm' then st.q.sm[#st.q.sm + 1] = { key = e.key, head = e.head }
        elseif e.kind == 'tex' then st.q.tex[#st.q.tex + 1] = { key = e.key, from = 'candidate' } end
    end
    LAB.rec('cap_look_asset', { key = e.key, path = e.path, kind = e.kind, via = st.assets[e.key].via,
        class = o and class_of(o) or nil, ms = type(r) == 'table' and r.ms or nil,
        err = err and err_text(err) or nil }, true)
end

-- ---------- 3. static meshes: sections, slots, cut-slot indexes, bounds ----------
local function read_sm(sm)
    local r = { mats = {}, slots = {} }
    local ok, n = ue.call(sm, 'GetNumSections', 0)
    r.sections = ok and num(n) and n or 'unread'
    r.objs = {}
    for i = 0, LOOK.SLOTS - 1 do
        local okm, m = ue.call(sm, 'GetMaterial', i)
        m = okm and ue.p(m) or nil
        if ue.valid(m) then r.mats[#r.mats + 1] = i .. '=' .. (ue.name(m) or '?') r.objs[i] = m end
    end
    for _, s in ipairs(LOOK.CUT_SLOTS) do
        local oki, i = ue.call(sm, 'GetMaterialIndex', ue.fname(s))
        if oki and num(i) and i >= 0 then r.slots[s] = i end
    end
    local okb, b = ue.call(sm, 'GetBounds')
    if okb and b ~= nil then
        r.radius = r3(ue.prop(b, 'SphereRadius'))
        local e, o = ue.prop(b, 'BoxExtent'), ue.prop(b, 'Origin')
        r.extent = e and { r3(ue.prop(e, 'X')), r3(ue.prop(e, 'Y')), r3(ue.prop(e, 'Z')) } or nil
        r.origin = o and { r3(ue.prop(o, 'X')), r3(ue.prop(o, 'Y')), r3(ue.prop(o, 'Z')) } or nil
    end
    r.cpu = or_unread(ue.prop(sm, 'bAllowCPUAccess'))
    return r
end
local function step_sm()
    local e = st.q.sm[1]
    if not e then return 'next' end
    local g = gate('cap.look.read', 'sm')
    if g == 'wait' then return 'wait' end
    table.remove(st.q.sm, 1)
    local sm = obj_of(e.key)
    local r, err = nil, g ~= 'ok' and g or (not sm and 'gone' or nil)
    if g == 'ok' and sm then r, err = LAB.armed('cap.look.read', read_sm, sm) end
    local f = { key = e.key, name = short(st.assets[e.key].path), err = err and err_text(err) or nil }
    if type(r) == 'table' then
        f.sections, f.mats, f.slots, f.radius, f.extent = r.sections, r.mats, r.slots, r.radius, r.extent
        f.origin, f.cpu = r.origin, r.cpu
        st.sms[e.key] = { extent = r.extent, origin = r.origin, radius = r.radius }
        -- A head prop's cut slots are tier B candidates; a flesh mesh's slot 0 is read too (the meat fallback, CM5)
        if e.head then
            for s, i in pairs(r.slots) do
                if r.objs[i] then add_mat('slot:' .. e.key .. ':' .. s, r.objs[i], 'cut_slot') end
            end
        elseif r.objs[0] then
            add_mat('slot:' .. e.key .. ':0', r.objs[0], 'mesh_slot')
        end
    end
    LAB.rec('cap_look_sm', f, true)
end

-- ---------- 4. the slicer's CapMaterial: the CDO and the live instances ----------
local function read_slicer()
    local list, seen = {}, {}
    local function add(o, cdo)
        local a = ue.addr(o)
        if a == nil or seen[a] then return end
        seen[a] = true
        list[#list + 1] = { obj = o, cdo = cdo }
    end
    local cdo = ue.find(LOOK.SLICER_CDO)
    if cdo then add(cdo, true) end
    local all, info = ue.find_all(LOOK.SLICER_CLASS, LOOK.SLICER_CAP, 'cap_look')
    -- ue.find_all hands its error back (never swallowed): an ArrayNum text is raised again for LAB.armed's stop rule
    if all == nil and tostring(info):find(LAB.ARRAYNUM, 1, true) then error(tostring(info), 0) end
    for _, o in ipairs(all or {}) do add(o, false) end
    local out, inst = {}, 0
    for _, x in ipairs(list) do
        local so = ue.prop(x.obj, 'SliceOption')
        local okw, outer = pcall(function() return x.obj:GetOuter() end)
        local cm = ue.prop(so, 'CapMaterial')
        if not x.cdo then inst = inst + 1 end
        out[#out + 1] = { cdo = x.cdo, outer = okw and (ue.full(outer) or 'none') or 'unread',
            create_cap = or_unread(ue.prop(so, 'bCreateCap')),
            cap_material = ue.valid(cm) and (ue.full(cm) or '?') or 'none',
            grid = or_unread(r3(ue.prop(so, 'CapGridCellSize'))), copy_vc = or_unread(ue.prop(so, 'bCopyVertexColors')),
            max_uv = or_unread(ue.prop(so, 'MaxOutputTexCoords')), mat = ue.valid(cm) and cm or nil }
    end
    return { list = out, instances = inst, found = type(info) == 'table' and info.n or 'unread',
        err = all == nil and tostring(info) or nil }
end
local function step_slicer()
    if not st.slicer_q then return 'next' end
    local g = gate('cap.look.slicer', 'slicer')
    if g == 'wait' then return 'wait' end
    st.slicer_q = false
    st.slicer_maps = st.slicer_maps + 1
    local r, err = nil, g ~= 'ok' and g or nil
    if g == 'ok' then
        LAB.oneshot()                                   -- FindAllOf walks the object array
        r, err = LAB.armed('cap.look.slicer', read_slicer)
    end
    local f = { map_n = st.slicer_maps, err = err and err_text(err) or nil }
    if type(r) == 'table' then
        f.instances, f.found, f.list, f.err = r.instances, r.found, {}, f.err or r.err
        for i, x in ipairs(r.list) do
            f.list[i] = { cdo = x.cdo, outer = x.outer, create_cap = x.create_cap, cap_material = x.cap_material,
                grid = x.grid, copy_vc = x.copy_vc, max_uv = x.max_uv }
            if x.mat then add_mat('slicer:' .. st.slicer_maps .. ':' .. i, x.mat, 'slicer') end
        end
        if r.instances > 0 then st.slicer_seen = true end
    end
    LAB.rec('cap_look_slicer', f, true)
end

-- ---------- 5. materials: base, parents, flags, parameter names ----------
-- The base material's flags, then the effective blend, shading and two-sided after the overrides down the MI chain
local function flags_of(m, base)
    local f = {}
    for _, x in ipairs(LOOK.FLAGS) do f[x[1]] = or_unread(ue.prop(base, x[2])) end
    local cur = m
    for _ = 1, LOOK.PARENTS do
        if cur == nil or ue.same(cur, base) then break end
        local ov = ue.prop(cur, 'BasePropertyOverrides')
        if ov ~= nil then
            for _, x in ipairs(LOOK.OVERRIDES) do
                if f['ov_' .. x[1]] == nil and ue.prop(ov, 'bOverride_' .. x[2]) == true then
                    f['ov_' .. x[1]], f[x[1]] = true, or_unread(ue.prop(ov, x[2]))
                end
            end
        end
        cur = ue.prop(cur, 'Parent')
    end
    return f
end
local function color(v)
    local c = {}
    for i, k in ipairs({ 'R', 'G', 'B', 'A' }) do
        c[i] = r3(ue.prop(v, k))
        if c[i] == nil then return nil end
    end
    return c
end
-- The parameters of g (a MIC, or the transient MID of a plain Material): every answered texture { name, path }, the
-- non-zero scalars, the non-black vectors
local function params(g, r)
    r.tex, r.tex_path, r.tex_obj, r.scalars, r.vectors = {}, {}, {}, {}, {}
    for _, list in ipairs({ LOOK.TEX_BC, LOOK.TEX_N, LOOK.TEX_OTHER }) do
        for _, n in ipairs(list) do
            local ok, t = ue.call(g, 'K2_GetTextureParameterValue', ue.fname(n))
            t = ok and ue.p(t) or nil
            if ue.valid(t) then
                r.tex[#r.tex + 1] = n .. '=' .. (ue.name(t) or '?')
                r.tex_path[n], r.tex_obj[n] = path_of(t), t
            end
        end
    end
    for _, n in ipairs(LOOK.SCALARS) do
        local ok, v = ue.call(g, 'K2_GetScalarParameterValue', ue.fname(n))
        if ok and num(v) and v ~= 0 then r.scalars[n] = r3(v) end
    end
    for _, n in ipairs(LOOK.VECTORS) do
        local ok, v = ue.call(g, 'K2_GetVectorParameterValue', ue.fname(n))
        local c = ok and color(v) or nil
        if c and (c[1] ~= 0 or c[2] ~= 0 or c[3] ~= 0 or c[4] ~= 0) then r.vectors[n] = c end
    end
end
-- One material's read; via 'mic' | 'mid' (its own getters) | 'material' (a transient MID made here) | 'none' (no
-- getter class: the flags only)
local function read_mat(m, via)
    local r = { via = via }
    local g = m
    if via == 'material' then
        local why
        g, why = LOOK.kmat_mid(nil, m)
        if not g then return { via = via, err = why } end
        r.mid = true
    end
    local okb, base = ue.call(g, 'GetBaseMaterial')
    base = okb and ue.p(base) or nil
    if not ue.valid(base) then base = nil end
    r.base = base and (ue.name(base) or '?') or 'unread'
    r.parents = {}
    local cur = ue.prop(m, 'Parent')
    for _ = 1, LOOK.PARENTS do
        if not ue.valid(cur) then break end
        r.parents[#r.parents + 1] = ue.name(cur) or '?'
        cur = ue.prop(cur, 'Parent')
    end
    r.flags = base and flags_of(m, base) or nil
    if via ~= 'none' then params(g, r) end
    return r
end
local function step_mat()
    local e = st.q.mat[1]
    if not e then return 'next' end
    local m = obj_of(e.key)
    local via = 'none'
    if m then
        if ue.is_a(m, MIC) then via = 'mic' elseif ue.is_a(m, MID) then via = 'mid'
        elseif ue.is_a(m, MAT) then via = 'material' end
    end
    local name = (via == 'material' or via == 'mid') and 'cap.look.mid' or 'cap.look.read'
    local g = name == 'cap.look.mid' and gate('cap.look.mid', 'mat') or gate('cap.look.read', 'mat')
    if g == 'wait' then return 'wait' end
    table.remove(st.q.mat, 1)
    st.n_mat = st.n_mat + 1
    local r, err = nil, g ~= 'ok' and g or (not m and 'gone' or nil)
    if g == 'ok' and m then
        if name == 'cap.look.mid' then r, err = LAB.armed('cap.look.mid', read_mat, m, via)
        else r, err = LAB.armed('cap.look.read', read_mat, m, via) end
    end
    r = type(r) == 'table' and r or { via = via }
    r.err = r.err or (err and err_text(err)) or nil
    r.name, r.path = short(st.assets[e.key].path), st.assets[e.key].path
    st.mats[e.key] = r
    for n, t in pairs(r.tex_obj or {}) do add_tex(t, r.name .. ':' .. n) end
    r.tex_obj = nil
    local ctl = st.mats.control and st.mats.control.flags
    local diff = nil
    if ctl and r.flags and e.key ~= 'control' then
        diff = {}
        for _, x in ipairs(LOOK.FLAGS) do if r.flags[x[1]] ~= ctl[x[1]] then diff[#diff + 1] = x[1] end end
    end
    local roles = {}
    for x in pairs(st.roles[e.key] or {}) do roles[#roles + 1] = x end
    table.sort(roles)
    LAB.rec('cap_look_mat', { key = e.key, name = r.name, roles = roles, class = m and class_of(m) or nil, via = r.via,
        mid = r.mid, base = r.base, parents = r.parents, flags = r.flags, diff = diff, tex = r.tex,
        scalars = r.scalars, vectors = r.vectors, err = r.err }, true)
end

-- ---------- 6. textures: VT, sRGB, compression, size ----------
local function read_tex(t)
    local r = { vt = or_unread(ue.prop(t, 'VirtualTextureStreaming')), srgb = or_unread(ue.prop(t, 'SRGB')),
        compression = or_unread(ue.prop(t, 'CompressionSettings')) }
    if ue.is_a(t, TEX2D) then
        local okx, x = ue.call(t, 'Blueprint_GetSizeX')
        local oky, y = ue.call(t, 'Blueprint_GetSizeY')
        r.x, r.y = okx and num(x) and x or 'unread', oky and num(y) and y or 'unread'
    end
    return r
end
local function step_tex()
    local e = st.q.tex[1]
    if not e then return 'next' end
    local g = gate('cap.look.read', 'tex')
    if g == 'wait' then return 'wait' end
    table.remove(st.q.tex, 1)
    st.n_tex = st.n_tex + 1
    local t = obj_of(e.key)
    local r, err = nil, g ~= 'ok' and g or (not t and 'gone' or nil)
    if g == 'ok' and t then r, err = LAB.armed('cap.look.read', read_tex, t) end
    r = type(r) == 'table' and r or {}
    r.err = err and err_text(err) or nil
    st.texs[st.assets[e.key].path] = r
    LAB.rec('cap_look_tex', { key = e.key, name = short(st.assets[e.key].path), from = e.from, vt = r.vt,
        srgb = r.srgb, compression = r.compression, x = r.x, y = r.y, err = r.err }, true)
end

-- ---------- 7. the resolution ----------
-- true, or false and why: Surface, lit, opaque or masked, drawn by the PMC's local vertex factory
local function passes(r)
    local f = r and r.flags
    if not f then return false, r and r.err and 'unread' or 'missing' end
    if f.domain ~= 0 then return false, f.domain == 'unread' and 'unread' or 'domain' end
    if not num(f.shading) then return false, 'unread' end
    if f.shading == 0 then return false, 'unlit' end
    if f.blend ~= 0 and f.blend ~= 1 then return false, num(f.blend) and 'blend' or 'unread' end
    local mode = num(st.lvf) and st.lvf or 0           -- unread: the material's own flag (fail closed)
    if mode < 1 and f.sm ~= true then return false, 'no_static_mesh' end
    return true
end
-- The VT flag of a texture path (true | false), nil when unread
local function vt_of(path)
    local t = path and st.texs[path]
    if t and type(t.vt) == 'boolean' then return t.vt end
    return nil
end
local function first_param(r, list)
    for _, n in ipairs(list) do if r.tex_path and r.tex_path[n] then return n, r.tex_path[n] end end
    return nil
end
local function tier_a()
    local tried = {}
    local bc = st.assets.flesh_bc
    if not (bc and bc.via ~= 'nil') then return { why = 'no_flesh_bc', tried = tried } end
    local want = vt_of(bc.path)
    if want == nil then return { why = 'flesh_vt_unread', tried = tried } end
    for _, key in ipairs(LOOK.TIER_A) do
        local r = st.mats[key]
        local ok, why = passes(r)
        local bcn, bcp = nil, nil
        if ok then
            bcn, bcp = first_param(r, LOOK.TEX_BC)
            if not bcn then ok, why = false, 'no_bc_param'
            elseif vt_of(bcp) == nil then ok, why = false, 'vt_unread'
            elseif vt_of(bcp) ~= want then ok, why = false, 'vt_mismatch' end
        end
        tried[#tried + 1] = { key = key, ok = ok, why = why }
        if ok then
            local nn, np = first_param(r, LOOK.TEX_N)
            local fn = st.assets.flesh_n
            local n_ok = nn ~= nil and fn ~= nil and fn.via ~= 'nil' and vt_of(np) ~= nil
                and vt_of(np) == vt_of(fn.path)
            return { key = key, path = r.path, bc = bcn, n = n_ok and nn or nil, tried = tried }
        end
    end
    return { why = 'none_passed', tried = tried }
end
local function tier_b()
    local tried, order = {}, {}
    for _, want in ipairs({ 'slicer', 'cut_slot' }) do
        local keys = {}
        for k in pairs(st.mats) do if (st.roles[k] or {})[want] then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do order[#order + 1] = k end
    end
    order[#order + 1] = 'flesh_mi'
    for _, key in ipairs(order) do
        local ok, why = passes(st.mats[key])
        tried[#tried + 1] = { key = key, ok = ok, why = why }
        if ok then return { key = key, path = st.mats[key].path, tried = tried } end
    end
    return { why = 'none_passed', tried = tried }
end
-- Tier N (the header): the first of LOOK.NATIVE that passes; the NoHead material is tried first and never taken (its
-- stump island is unknown: 'island_unknown' when it passes). { key, path, tried } | { why, tried }
local function tier_n()
    local ok, why = passes(st.mats.nohead_mi)
    local tried = { { key = 'nohead_mi', ok = false, why = ok and 'island_unknown' or why } }
    for _, key in ipairs(LOOK.NATIVE) do
        ok, why = passes(st.mats[key])
        tried[#tried + 1] = { key = key, ok = ok, why = why }
        if ok then return { key = key, path = st.mats[key].path, tried = tried } end
    end
    return { why = 'none_passed', tried = tried }
end
local function tried_text(list)
    local out = {}
    for i, x in ipairs(list) do out[i] = x.key .. ':' .. (x.ok and 'ok' or tostring(x.why)) end
    return out
end
local queue_build
local function step_resolve()
    local ok, why = passes(st.mats.skull)
    local res = { A = tier_a(), B = tier_b(), N = tier_n(),
        pale = ok and { key = 'skull', path = st.mats.skull.path } or { why = why } }
    local sp, sb = st.assets.spine_sm, st.sms.spine_sm
    if not (sp and sp.via ~= 'nil') then res.stub = { why = 'no_mesh' }
    elseif not (sb and sb.extent and sb.origin) then res.stub = { why = 'no_bounds' }
    else res.stub = { key = 'spine_sm', path = sp.path, extent = sb.extent, origin = sb.origin } end
    st.res = res
    local f = { lvf_mode = or_unread(st.lvf), A = res.A.key and (short(res.A.path) .. ' bc=' .. res.A.bc
        .. (res.A.n and (' n=' .. res.A.n) or '')) or res.A.why, A_tried = tried_text(res.A.tried),
        B = res.B.key and short(res.B.path) or res.B.why, B_tried = tried_text(res.B.tried),
        N = res.N.key and short(res.N.path) or res.N.why,
        N_tried = tried_text(res.N.tried), pale = res.pale.key and short(res.pale.path) or res.pale.why,
        stub = res.stub.key and short(res.stub.path) or res.stub.why }
    local k = tostring(f.A) .. '|' .. tostring(f.B) .. '|' .. tostring(f.N) .. '|' .. tostring(f.pale) .. '|'
        .. tostring(f.stub)
    local changed = k ~= st.res_key
    if changed then
        st.res_key = k
        LAB.rec('cap_look_tier', f, true)
    end
    -- the same answer on a map already built (a slicer retry that found nothing new) keeps what is held
    if changed or st.build_epoch ~= ue.epoch then queue_build() end
end

-- ---------- 8. the build: the chosen assets loaded, the tier A MID made, each held for the map ----------
local function host() return (ue.first_of('PlayerController')) end
-- Held on the player controller's keeper (ue.hold kind 'material'); the MID made here keeps its full name
-- (ue.keep_mod: mod-made objects share default short names)
local function hold(m, j)
    local id, why, add = ue.hold(host(), m, j.kind or 'material')
    if id == nil then
        return { why = 'hold: ' .. tostring(why) .. (add ~= nil and (' add: ' .. tostring(add)) or '') }
    end
    local mod = j.slot == 'A'
    return { rec = mod and ue.keep_mod(m) or ue.keep(m), mod = mod, tier = j.tier, name = j.name, hold = id }
end
local function live(h)
    if not (h and h.rec) then return nil end
    if h.mod then return (ue.live_mod(h.rec)) end
    return (ue.live(h.rec))
end
local function make_mid(parent, a, bc, n)
    local mid, why = LOOK.kmat_mid(nil, parent)
    if not mid then return { why = why } end
    local set = {}
    for _, p in ipairs({ { a.bc, bc }, { a.n, n } }) do
        if p[1] and p[2] then
            local s, same = LOOK.tex_param(mid, p[1], p[2])
            set[#set + 1] = { param = p[1], set = s, same = same }
        end
    end
    if not (set[1] and set[1].same) then return { why = 'readback', set = set } end
    return { mid = mid, set = set }
end
-- One build job: { slot ('A' | 'B' | 'N' | 'pale' | 'stub'), tier, paths } -> st.held[slot] = { rec, tier, name,
-- hold } or why
local function build_one(j)
    local load = gate('cap.look.load', 'build')
    local mid = j.slot == 'A' and gate('cap.look.mid', 'build') or 'ok'
    local keep = gate('cap.keep', 'build')
    local stage = j.slot == 'A' and gate('lab.cut.stage', 'build') or 'ok'
    for _, g in ipairs({ load, mid, keep, stage }) do
        if g == 'wait' then return 'wait' end
    end
    for _, g in ipairs({ load, mid, keep, stage }) do
        if g ~= 'ok' then return { why = g } end
    end
    LAB.oneshot()
    local got, err = LAB.armed('cap.look.load', function()
        local out = {}
        for _, p in ipairs(j.paths) do out[#out + 1] = (ue.asset(p)) or false end
        return out
    end)
    if type(got) ~= 'table' then return { why = 'load: ' .. err_text(err) } end
    for i, o in ipairs(got) do if not o then return { why = 'load: ' .. short(j.paths[i]) } end end
    local m = got[1]
    if j.slot == 'A' then
        local r
        r, err = LAB.armed('cap.look.mid', make_mid, got[1], j, got[2], got[3])
        if type(r) ~= 'table' then return { why = 'mid: ' .. err_text(err) } end
        if not r.mid then return { why = 'mid: ' .. tostring(r.why), set = r.set } end
        m = r.mid
        j.set = r.set
    end
    local h
    h, err = LAB.armed('cap.keep', hold, m, j)
    if type(h) ~= 'table' then return { why = 'keep: ' .. err_text(err), set = j.set } end
    if not h.rec then return { why = h.why, set = j.set } end
    h.set = j.set
    return h
end
local function step_build()
    local j = st.q.build[1]
    if not j then
        if st.built == nil then
            st.built = { epoch = ue.epoch }
            local f = { epoch = ue.epoch }
            for _, s in ipairs({ 'A', 'B', 'N', 'pale', 'stub' }) do
                local h = st.held[s]
                f[s] = h == nil and 'none' or h.rec and ('held ' .. h.name) or h.why
            end
            local a = st.held.A and st.held.A.set
            if a then
                f.A_set = {}
                for i, x in ipairs(a) do
                    f.A_set[i] = x.param .. (x.set and ' set' or ' unset') .. (x.same and ' same' or ' differs')
                end
            end
            LAB.rec('cap_look_build', f, true)
        end
        return 'next'
    end
    local r = build_one(j)
    if r == 'wait' then return 'wait' end
    table.remove(st.q.build, 1)
    st.held[j.slot] = r
end
function queue_build()
    st.held, st.built, st.q.build, st.build_epoch = {}, nil, {}, ue.epoch
    local res = st.res
    if not res then return end
    if res.A.key then
        local p = { res.A.path, st.assets.flesh_bc.path }
        if res.A.n then p[3] = st.assets.flesh_n.path end
        st.q.build[#st.q.build + 1] = { slot = 'A', tier = 'A', paths = p, bc = res.A.bc, n = res.A.n,
            name = 'A:' .. short(res.A.path) }
    end
    if res.B.key then
        st.q.build[#st.q.build + 1] = { slot = 'B', tier = 'B', paths = { res.B.path }, name = short(res.B.path) }
    end
    if res.N.key then
        st.q.build[#st.q.build + 1] = { slot = 'N', tier = 'N', paths = { res.N.path }, name = short(res.N.path) }
    end
    if res.pale.key then
        st.q.build[#st.q.build + 1] = { slot = 'pale', tier = 'A', paths = { res.pale.path },
            name = short(res.pale.path) }
    end
    if res.stub and res.stub.key then                   -- the spine mesh held as a mesh (a hidden holder component)
        st.q.build[#st.q.build + 1] = { slot = 'stub', tier = 'N', kind = 'mesh', paths = { res.stub.path },
            name = short(res.stub.path) }
    end
end

-- ---------- the ticker: one step a frame ----------
local STEP = { cvar = step_cvar, asset = step_asset, sm = step_sm, slicer = step_slicer, mat = step_mat,
    tex = step_tex, resolve = step_resolve, build = step_build }
-- The current phase's step; a finished phase hands the frame to the next one (no engine call is made by 'next')
local function step()
    for _ = 1, #PHASES do
        local name = PHASES[st.phase]
        if name == 'done' then return end
        local r = STEP[name]()
        if r == 'wait' then return end
        if r ~= 'next' then
            st.steps = st.steps + 1
            if name == 'cvar' or name == 'resolve' then st.phase = st.phase + 1 end
            return
        end
        st.phase = st.phase + 1
    end
end
local function phase_of(name)
    for i, p in ipairs(PHASES) do if p == name then return i end end
    return #PHASES
end
local function tick()
    if not st.init or st.ended then return end
    if LAB.ended() then st.ended = true return end
    if LAB.pinned() ~= true or LAB.paused() or not MODOFF.enabled('lab_look') then return end
    -- a slicer retry on a later map: back to the slicer (a CapMaterial it finds goes through mat, tex, resolve, build)
    if st.phase > phase_of('slicer') and st.slicer_q then st.phase = phase_of('slicer') end
    if PHASES[st.phase] == 'done' then return end
    local ok, why = wanted()
    st.wait = why
    if not ok then return end
    if G.busy() then st.busy = st.busy + 1 return end
    step()
end

-- ---------- the API: pure lookups ----------
function LOOK.material(section, side)
    if type(section) ~= 'string' or (side ~= 'stump' and side ~= 'piece') then return nil, 'bad_args' end
    if not st.init or not MODOFF.enabled('lab_look') then return nil, 'off' end
    if LAB.pinned() ~= true then return nil, 'unpinned' end
    local tier = knob_tier()
    if not tier then return nil, 'basic' end
    if section == 'dark' then return nil, 'dark' end
    local slot = section == 'meat' and tier or section == 'pale' and 'pale' or nil
    if not slot then return nil, 'bad_args' end
    if st.res == nil then return nil, 'pending' end
    local want = slot == 'pale' and st.res.pale or st.res[slot]
    if not want.key then return nil, 'refused' end
    local h = st.held[slot]
    if h == nil then return nil, 'pending' end
    if not h.rec then return nil, 'refused' end
    local m = live(h)
    if not m then return nil, 'gone' end
    return m, tier
end
function LOOK.candidates()
    local out = {}
    if not st.init then return out end
    for _, s in ipairs({ 'A', 'B', 'N', 'pale' }) do
        local h = st.held[s]
        local m = live(h)
        if m then out[#out + 1] = { name = h.name, m = m, tier = h.tier } end
    end
    return out
end
-- The vertebra stub's mesh (held) and its bounds { extent, origin } in mesh space (cm), for lab_cap's native neck
-- Cap: sm, info | nil, why ('off', 'pending', 'no_mesh', 'no_bounds', the hold's why, 'gone'). A pure lookup
function LOOK.stub()
    if not st.init then return nil, 'off' end
    local r = st.res and st.res.stub
    if not r then return nil, 'pending' end
    if not r.key then return nil, r.why end
    local h = st.held.stub
    if h == nil then return nil, 'pending' end
    if not h.rec then return nil, h.why end
    local m = live(h)
    if not m then return nil, 'gone' end
    return m, { extent = r.extent, origin = r.origin }
end
-- What tier N holds (for lab_cap's cap_native record): { meat (the held name), mid (false: no MID), why }
function LOOK.native()
    local n = st.res and st.res.N
    if not st.init or not n then return { why = st.init and 'pending' or 'off' } end
    if not n.key then return { why = n.why } end
    local h = st.held.N
    if not (h and h.rec) then return { why = h and h.why or 'pending' } end
    return { meat = h.name, mid = false, why = live(h) == nil and 'gone' or nil }
end

-- ---------- lifecycle ----------
function LOOK.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    for _, e in ipairs(LOOK.ASSETS) do st.q.asset[#st.q.asset + 1] = e end
    LAB.names(N, F)
    MODOFF.feature('lab_look', {})                      -- mod-off pauses the probe; lab_plan's quiet() waits out both
    G = LOOK.gates(st, 'lab_look', 'cap_look_skip')
    S.ticker('lab_look', tick)
    return true
end
-- After each map load (main.lua's staggered warm-up): queues only. The slicer once more while no instance was seen
-- (SLICER_MAPS maps at most); the build again when the resolution is known
function LOOK.warm()
    if not st.init or st.ended then return end
    if not st.slicer_seen and st.slicer_maps < LOOK.SLICER_MAPS then st.slicer_q = true end
    if st.res and st.build_epoch ~= ue.epoch then
        queue_build()
        if st.phase > phase_of('build') then st.phase = phase_of('build') end
    end
end
-- A map load: the holds ended with the old map (ue.reset_caches), so nothing is held until the build runs again; the
-- probe's answers stay for the session
function LOOK.reset(reason)
    if not st.init then return end
    if reason == 'map' then st.held, st.built, st.q.build, st.busy_f = {}, nil, {}, nil end
end
function LOOK.status()
    local held = {}
    for s, h in pairs(st.held) do held[s] = h.rec and h.name or h.why end
    return { init = st.init, ended = st.ended, phase = PHASES[st.phase], steps = st.steps, busy = st.busy,
        wait = st.wait, lvf = st.lvf, slicer_maps = st.slicer_maps, slicer_seen = st.slicer_seen,
        resolved = st.res ~= nil, held = held, assets = #LOOK.ASSETS - #st.q.asset, mats = st.n_mat, texs = st.n_tex }
end
function LOOK.shutdown()
    S.remove_ticker('lab_look')
    for _, ev in ipairs(LOOK.GATE_EVENTS) do BUS.off(ev, 'lab_look') end
    st, A, G = new_state(), nil, nil
end
return LOOK
