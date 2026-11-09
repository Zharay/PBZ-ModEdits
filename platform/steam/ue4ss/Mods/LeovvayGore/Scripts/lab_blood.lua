-- status: new for the beta (offline only; TC-LAB-02 run 4 decides) origin: lead 2026-10-31, the author's beta scope
-- («so there is more blood than usual ... and ideally so the clothes get stained with blood»)
-- lab_blood.lua: more blood than vanilla and blood on enemy clothes, in the lab build, with the game's own assets.
-- Dev builds, dev set 'lab02' (META.dev_sets), and the player beta (META.beta_modules); inert unless LAB.cut_set().
-- Bus listeners only queue; every engine call runs on the lab ticker (game thread) through LAB.armed or LAB.hot, never
-- in a hook body, except the plain-value copy in the vanilla SpawnDecal observer below.
-- * Who bleeds: never the player (the pawn bus lab_pawn named, or any class whose name holds 'Player': the key alone
--   can be late or stale after a map load, BP_Player_Base_C), never a class of data/no_blood.lua (puppets and vessels:
--   splinters only, «2: yes»; from data/census.json).
-- * Hits: bus lab_hit (lab_kill, once per victim per batch). A victim bleeds when a snapshot since its last bleed shows
--   damage (event GameplayEvent.Damage.Taken, or a damage hook: h02 OnDamage, h07 TakeDamage, h08 OnDamageReceived),
--   never its own attack (owner_is_victim); a parried or blocked blow leaves none (bug B2, Nexus 178914750): a damage
--   snapshot at or before BLOCK_S after the victim's newest block is no blow (counter blood_skip_blocked; that blow is
--   used up), the block being lab_kill's defender mark (M.blocked: a Deflect Consume or Defender.Normal/Perfect event)
--   or a snapshot, not of its own attack, whose hit react strength names Deflect.Defender. A Damage.Cause.Deflect
--   cause is no block: it rides on Soul's deflect counter, whose Kick.Player blow lands in its frame (session
--   20261031-1203-TC-LAB-02 log.jsonl:269-282). So a blocked blow makes no spray, decal, pool, Soul splash or
--   lab_bleed (no drops, no sword blood), and an older hit the gap held does not bleed at the block. At most one
--   bleed per victim per HIT_GAP_S. Where: the snapshot's HitBone (else HitBodyData.bone) on the victim's Mesh via
--   GetSocketLocation; no bone: the actor's location raised HIT_Z (no decal then). Which way: AttackDirection, else
--   SweepDirection. What: one Blood_V2 slash spray along the blow, one body spray, scale HIT_SCALE, DECALS_PER_HIT
--   skinned decals.
-- * Deaths: bus lab_death, drained after the hits of the same tick: one NS_BloodBodyBurst_003 at the last bled bone read
--   again now (else the actor, raised), scale KILL_SCALE, and KILL_DECALS decals there.
-- * Cuts: bus lab_cut_live (lab_cut, after each commit): a head cut sprays NS_BloodHeadBreak_001 at the stump bone; then
--   SPURTS stump spurts (NS_BloodSprint_003 head, _004 limb, attached to the stump bone of the leader mesh) every
--   SPURT_P s while the corpse is LAB.alive, and CUT_DECALS decals round the stump. The beta's extra parts of a kill
--   (cut.rank above 1, docs/research/beta-dismemberment-plan.md BD7, research MC10): PLAYER_EXTRA Soul splashes and no
--   ground pool of their own (the kill's and the primary's pools stay); a cut with no rank or rank 1 is unchanged.
-- * Slices (bus lab_slice_live from lab_slice_route: the game's own slicer cut a part off, two skinned halves, the
--   source hidden; docs/research/slicer-stumps.md): queued like cuts, bled by lab_blood_slice.lua (a library, its
--   header; BS.bind hands it these helpers): a cut's bleed on the halves, the stump pulses on the Negative half at the
--   cut bone (neck_01 for a head, the limb's cut bone), a trail on the Positive half at the part's bone, every call on a
--   half under its own 'slicer.blood' (adecal takes that guard name, attach_fx runs inside it). The hit blood, the
--   kill burst and Soul's splashes with their life, heal fade and revive wash are untouched. Mod-off drops the queued
--   slices and their pulses, as it does cuts.
-- * Skinned decals (blood on clothes): every BP_NPC_Base_C carries a SkinnedDecalSampler (object dump 26266538:
--   BP_NPC_Base_C:SkinnedDecalSampler_GEN_VARIABLE). SpawnDecal(Location, Rotation, Scale, BoneName, Size, SubUV,
--   Index) -> int32, read from PBZ.exe 0x144D30740 (thunk 0x144D32570): Location is world space (turned into the bone's
--   space through the mesh's GetSocketTransform(BoneName, World)); a null Mesh, an empty Materials list or a null
--   DataTarget is set up inside the call; a decal whose squared distance to another is under MinDecalDistance is
--   dropped (the answer is then the Index passed, -1); Index < 0 takes EmptyIndexes[0], else (LastDecalIndex + 1) %
--   MaxDecals: an integer divide by MaxDecals, a native fault at 0; the MinDecalDistance loop counts in 16 bits; the mesh
--   asset's skeleton is read unchecked. So (as the author's SWZC skin_decal.lua did with the same plugin) a decal goes
--   only on a set-up sampler whose Mesh is still the one first read, on a bone of that mesh, while MaxDecals reads
--   1..32767 and LastDecalIndex -1..32766, Size clamped, at most DECALS_PER_FRAME a frame, the first call per actor class
--   armed (a class whose armed call raised gets none again). A sampler not set up gets one armed AutoSetup, at most one
--   a frame, only when the actor's Mesh has a mesh asset, and is used only if its Mesh then is the actor's Mesh (never
--   SpawnDecal's own set-up). Jitter round the bone spot: DECAL_JITTER, at least 1.5x the minimum distance.
--   The look (colour and atlas) lives on the sampler's MIDs (SWZC: DecalColor, DecalNormal, DecalCompact). PBZ leaves
--   them at the plugin's empty defaults (run 4: 348 decals accepted, none seen), so look_on sets the plugin's own
--   WoundDecal textures (B.LOOK, a 2x2 atlas: SubUV 0-3) once per sampler under 'blood.look' and logs blood_look.
-- * Vanilla observer: a pre hook on SkinnedDecalSampler:SpawnDecal (registered on the first tick under 'blood.hook')
--   copies the plain values of the first VANILLA_N vanilla calls (not ours: st.ours is set around our call) and counts
--   the rest; the ticker logs them (blood_vanilla_decal). Once one is seen, our decals take its Size (clamped) and pick
--   SubUV among the ones it used: the game's own look on cloth.
-- * Assets: warm() queues every system; the ticker resolves one a frame (ue.asset: found, else LoadAsset) under
--   'blood.load', then logs blood_assets; the decal layers it draws are held for the map in the same call
--   (lab_blood_queue's load: the stain and the spatter, a later material only while neither can be had). The hit path
--   never loads and never looks a decal material up (session 20261101-lag, the author: «every hit on an enemy
--   causes micro-lags»): FX systems through ue.asset_peek, else ue.find with the miss kept for the map (system; a stale
--   one waits for its reload); decal materials and wound textures through lab_blood_queue's texture (a library, its
--   header: the holds, the reloads a bleed asks for, the decal queue, the lag guard). A plain hit's pool is the stain
--   alone (kills and cuts keep both layers); mod-off, effects.blood off and a map load drop the decal queue;
--   blood_layers: the decal layers in use, each time they change.
-- * Breaker: each call kind ('blood.fx', 'blood.spurt', 'blood.decal', 'blood.setup', and 'blood.hold', the layers'
--   holds inside 'blood.load') stops for the map after FAIL_MAX failures in a row (a raise or no answer; a rejected
--   decal is no failure; a hold with no PlayerController yet is none either): blood_off record.
-- * Loop check: the first FX_PROBE_N sprays are read again FX_PROBE_S later (IsActive): blood_fx_alive tells whether a
--   Blood_V2 system loops (a looping one never auto-destroys).
-- * Off: MODOFF.enabled('lab_blood') false (mod-off, or the vanilla compare: 'lab_blood' is a gameplay feature of
--   core/modoff.lua since beta port S6) or C.effect('blood') false (effects.blood or enabled set false) draws nothing
--   new; spurts already due stop too. lab_end stops all. What is drawn already stays (decals, pools), except Soul's
--   splashes (their removal, lab_blood_wash, runs while off too: it only removes the mod's own objects).
-- * Volumetric drops (lab_drops, the author 2026-11-01: «more volumetric drops»): every bleed drawn here emits bus
--   lab_bleed { kind, pos, ... } once: 'hit' (pos, dir, class, key), 'kill' (pos, class, key), 'head' or 'limb' (pos,
--   mesh, bone, keep, class, extra, at and joint: cut.gib's head and joint spots when the cut carries them) and
--   'spurt' (mesh, bone, keep, class, pulse 1..SPURTS) at each stump pulse. A slice's bleeds carry pos and axis read on
--   its halves (inside 'slicer.blood') and no mesh: 'head' or 'limb' (pos the stump, axis stump -> the part's bone,
--   else pelvis -> stump), then per pulse two 'spurt' (the stump: axis pelvis -> stump; the trail: pos the part's bone,
--   axis stump -> it), so lab_drops never reads a half. Plain values only; lab_drops queues them.
-- * Soul's splashes go (bd-heal: the life, the heal fade after a full heal, the revive wash; Blood on Soul off; Blood
--   on Soul's face off): lab_blood_wash.lua (a library, its header; WS.bind hands it lab_blood's helpers), run by this
--   ticker each unpaused frame before the gate (so also while off). Every st.pring entry carries its seq, its game
--   time and its face flag (lab_blood_queue's job_player). on_player lands nothing while soul_blood is false (no
--   receives switch either), and while soul_face_blood is false it skips each pick of a face bone (B.face_bone: the
--   head, neck, face and hair bones by name prefix; of PLAYER_BONES head and neck_01) or of a bone next to his neck
--   whose splash reaches his chin (B.FACE_NEAR: spine_05, clavicle_l, clavicle_r): no bone read, no decal, no
--   lab_grey splash (blood_skip_face); the other picks land as with it on (Nexus 178851837).
-- * Amount (beta port S6): d = clamp(blood_amount / AMOUNT_REF, AMOUNT_MIN, AMOUNT_MAX) from core/config.lua (default
--   3.0, presets 2.5/2.0/1.5, console 'leovvaygore set blood_amount N'), read every tick. It scales the attached
--   decals per hit, kill and cut, ADECALS_ACTOR, ADECALS_MAX, POOLS_MAX, PLAYER_MAX and Soul's splashes a bleed (PLAYER_HIT ..
--   PLAYER_EXTRA, Nexus 178842513) (rounded, at least 1) and the half-sizes ADECAL_SIZE and PLAYER_SIZE by sqrt(d) (the area
--   follows d). At exactly 3.0 (d 1) every constant is the one tuned live in runs 4-11. A lowered cap trims its ring by at most TRIM_PER_FRAME destroys a frame (never while off).
-- * The player beta (LAB.beta(), beta port S6): no skinned decal (decals() draws none: no sampler read, AutoSetup,
--   look or SpawnDecal), no vanilla SpawnDecal observer (no hook registered), no loop check (no IsActive read), no
--   wound texture load. Their code stays for a later fix.
-- * The grey A/B (the author 2026-11-01: «the blood on me still sometimes turns grey under some shadows»): the
--   console verbs live in lab_grey.lua (a library, its header; registered through MAIN.verb at GREY.bind). The
--   ticker runs GREY.step after lab_end's check (also paused and off); a map load and the shutdown pass on.
-- * The receive switch goes back (triage 2026-11-03 B4, Nexus 178919373: dark leaf-like patches on Soul «out of combat
--   with no blood present», and on bodies lying on the ground): every PBZ character ships with bReceivesDecals false,
--   and once receives_on switched a part on, the forest floor's world decals (BP_ErosionDecal leaf, dirt and puddle
--   boxes, docs/research/grey-under-trees.md) drew on it until the next map. Now the parts it switched (st.recv_parts:
--   their ue.keep records; a slice's Negative half by its keep_mod record, lab_blood_slice) go back to false through
--   recv_off once nothing of ours is left to draw on them: Soul's when his splash ring is empty and no splash was
--   queued for RECV_IDLE_S game seconds (lab_blood_wash, why 'empty': the life, a heal fade, a revive or Blood on Soul
--   off took the last one), a victim's or a half's once no stain of it is left in the ring (st.adecal_live) or in the
--   decal queue (st.adecal_q: a stain queued counts until it spawns, is dropped or fails; verify B4: a cut's spawns
--   that evicted a body's last old stains in the frame its new ones were queued left those on false parts), why
--   'stains': the ring evicted the last one, or the last queued ones were dropped (stale, gone, a full queue, the
--   queue cleared by mod-off or Blood effects off) before any spawned. Not while lab_cap's wound ring lives on the
--   body's leader (B.recv_pin from its dress: the ring is a decal on the leader, never in this module's ring, and draws
--   only while the leader receives; verify B4 P1): the key waits (st.recv_wait) and goes back once the ring is gone,
--   looked at each RECV_POLL_S (why 'ring'). Only a part still the one kept and reading true is written
--   (SetReceivesDecals(false), under 'blood.recv', a half's under 'slicer.blood'); st.recv forgets the key, so the next
--   splash or stain switches it on again. One blood_recv_off record { why, class, half, parts, switched, err } each,
--   RECV_LOG_MAX a session; counter blood_recv_off. While his splashes, a body's stains or its Cap's ring are on, the
--   world's decals still draw there (the beta look).
-- * Counters (published at 0): blood_hits, blood_fx, blood_fx_fail, blood_decals, blood_decal_rejected,
--   blood_decal_fail, blood_decal_skip, blood_decal_budget, blood_kills, blood_cuts, blood_spurts, blood_skip_player,
--   blood_skip_noblood, blood_skip_nodamage, blood_vanilla_decals, soul_wash, soul_wash_unread, soul_fade_life,
--   soul_fade_heal, soul_fade_revive, blood_slices (a slice also counts in blood_cuts), blood_skip_deadline,
--   blood_dq_stale, blood_dq_off, blood_dq_gone, blood_dq_full, blood_rewarm, blood_hold, blood_hold_fail,
--   blood_skip_face, soul_fade_face; blood_adecals, blood_pools count spawns, blood_player the bleeds that queued a
--   splash.
--   Records: blood (the first REC_N bleeds; kind 'slice' for a slice; kind 'blocked' for the first BLOCK_REC_N blocked
--   blows: by mark or strength, lab_kill's tag, dt_ms, the window's attack_type and strength), blood_sampler (the first
--   state read per class),
--   blood_vanilla_decal,
--   blood_assets, blood_hook, blood_off, blood_fx_alive, soul_wash, soul_wash_unread, blood_slow, blood_step_off,
--   blood_layers, blood_rewarm, blood_hold (soul_wash rules: life, heal_fade, revive, soul_off, face_off), blood_hl
--   (fixes-0.2.2 B3.5, D4: the first HL_N bled hits a session whose bone spot was read and whose bone's own snapshot
--   holds a non-zero HitLocation: class, bone, hl_cm its distance to the spot, hl_bone 'fine' HitBone or 'coarse').
-- What the mock cannot prove: native faults, the FX's look and orientation, the decal Size unit, the SubUV atlas.
local BUS = require('core.bus')
local S = require('core.sched')
local MODOFF = require('core.modoff')
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')
local NO_BLOOD = require('data.no_blood')
local GREY = require('lab_grey')                         -- the grey A/B console tools (a library, its header)
local BS = require('lab_blood_slice')                    -- the bleed of a slice (a library, its header)
local QL = require('lab_blood_queue')                    -- the hit lag: materials, decal queue, lag guard (its header)
local WS = require('lab_blood_wash')                     -- Soul's splashes go: life, heal fade, revive, switches
local lap, begin, texture, texture_any, rewarm = QL.lap, QL.begin, QL.texture, QL.texture_any, QL.rewarm
local dq_push, step, late, slow_check = QL.push, QL.step, QL.late, QL.slow_check

local function ns(dir, name) return dir .. name .. '.' .. name end
local V2 = '/PBZVFXPack/VFX/BattleFX/Common/Blood_V2/'
local COMMON = '/PBZVFXPack/VFX/BattleFX/Common/'
local B = {
    FX = {
        hit = { ns(V2, 'NS_BloodSlash_001'), ns(V2, 'NS_BloodSlash_002'), ns(V2, 'NS_BloodSlash_003'),
            ns(V2, 'NS_BloodSlash_004') },
        body = { ns(V2, 'NS_BloodBody_001'), ns(V2, 'NS_BloodBody_002'), ns(V2, 'NS_BloodBody_003'),
            ns(V2, 'NS_BloodBody_004') },
        kill = { ns(V2, 'NS_BloodBodyBurst_003') },
        head = { ns(V2, 'NS_BloodHeadBreak_001') },
        stump = { ns(COMMON, 'NS_BloodSprint_003'), ns(COMMON, 'NS_BloodSprint_004') },
    },
    SAMPLER = '/Script/SkinnedDecalComponent.SkinnedDecalSampler',
    -- The look (run 4: 348 decals accepted, none seen; the dump has the plugin's SDC_EmptyColor and SDC_EmptyNormal
    -- loaded, the defaults of SkinnedDecalFunction, and nothing in PBZ calls SpawnDecal on these NPCs, so nothing sets a
    -- look): the plugin's own wound textures on every MID of the sampler, the SWZC parameter names
    LOOK = {
        { 'DecalColor', '/SkinnedDecalComponent/WoundDecal/WoundDecal_basecolor.WoundDecal_basecolor' },
        { 'DecalNormal', '/SkinnedDecalComponent/WoundDecal/WoundDecal_normal.WoundDecal_normal' },
        { 'DecalCompact', '/SkinnedDecalComponent/WoundDecal/WoundDecal_compact.WoundDecal_compact' },
    },
    MIDS_MAX = 16,
    -- Run 6: DecalMax 100 and DecalInfo bound on every MID (the materials do draw the plugin's decals), but no
    -- DecalColor: the look's texture parameters are named otherwise in this plugin version. These names are asked of
    -- the first two MIDs once per class (K2_GetTextureParameterValue, a read); blood_look logs every one that answers
    LOOK_PROBE = { 'DecalColor', 'DecalTexture', 'DecalBaseColor', 'DecalAlbedo', 'DecalDiffuse', 'DecalColorTexture',
        'DecalColorTex', 'DecalTex', 'DecalAtlas', 'DecalMask', 'DecalNormal', 'DecalNormalMap', 'DecalNormalTexture',
        'DecalCompact', 'DecalCompactTexture', 'DecalMRA', 'DecalORM', 'DecalRoughness', 'Decal Color', 'Decal Texture',
        'Decal BaseColor', 'Decal Base Color', 'Decal Normal', 'Decal Compact', 'Decal Atlas', 'SkinnedDecalColor',
        'SkinnedDecalTexture', 'SkinnedDecalNormal', 'SDC_Color', 'SDC_Normal', 'SDCColor', 'SDCNormal', 'Color',
        'BaseColor', 'Base Color', 'Albedo', 'Diffuse', 'Normal', 'Compact', 'WoundColor', 'WoundTexture', 'Wound',
        'WoundNormal', 'BloodTexture', 'Blood', 'ColorAtlas', 'NormalAtlas', 'DecalColorAtlas', 'DecalNormalAtlas' },
    -- Attached deferred decals (run 5 fallback): the game's own blood decal materials, the first one found
    ADECAL_MATS = {
        '/Game/PBZContent/Environments/Decal/Nature/Material/MI_High_Velocity_Blood_Spatter_sgekfhvp_4K.MI_High_Velocity_Blood_Spatter_sgekfhvp_4K',
        '/Game/PBZContent/Environments/Decal/Nature/Material/MI_Blood_Stain_sgfjdepc_8K.MI_Blood_Stain_sgfjdepc_8K',
        '/AkashaEffects/MaterialLibrary/Template/MAI_Decal_DRA_Blood.MAI_Decal_DRA_Blood',
        '/PBZVFXPack/VFX/BattleFX/Common/Assets/MI_FX_DL2_BloodDecal_001_B.MI_FX_DL2_BloodDecal_001_B',
    },
    -- Run 6 («visible, though extremely faintly»): two layers per decal (the dense stain, then the spatter over it), bigger
    -- Run 8 («blood stains are super few and small, there should be many times more of them, literally multiples»): x1.8 size, x2-3 count
    ADECAL_SIZE = 32, ADECAL_DEPTH = 30, ADECAL_JITTER = 10, ADECALS_PER_HIT = 2, ADECALS_KILL = 5, ADECALS_CUT = 4,
    ADECALS_ACTOR = 60, ADECALS_MAX = 450,
    -- Pools (run 6: «the blood disappeared quickly»): our own ground decals under a kill and a cut, LifeSpan POOL_LIFE_S (the
    -- engine removes them), MI_Blood_Stain pointing down from the actor's centre (depth POOL_DEPTH reaches the ground)
    POOL_MAT = '/Game/PBZContent/Environments/Decal/Nature/Material/MI_Blood_Stain_sgfjdepc_8K.MI_Blood_Stain_sgfjdepc_8K',
    -- Run 7 («it disappears from the ground»): 10 minutes, 60 at most
    -- Run 8 («the pools disappear»): no LifeSpan at all (only the oldest past POOLS_MAX go), x2.3 size, both layers, and
    -- a small pool under every bled hit too
    -- Run 9 (the author: blood on the clothes «disappears as if a spotlight shines on it ... when you walk up to the blood on the ground
    -- it shows up on the hat»): the pool's 2.8 m box projected onto Soul, who now receives decals. A pool is a
    -- flat box on the ground now: centre at the victim's lowest foot bone minus FOOT_LIFT, half-depth POOL_DEPTH (boots
    -- only); no ground read, no pool
    POOL_LIFE_S = 0, POOL_DEPTH = 18, POOL_KILL = 160, POOL_CUT = 100, POOL_HIT = 55, POOLS_MAX = 200, FOOT_LIFT = 6,
    GROUND_BONES = { 'foot_l', 'foot_r', 'ball_l', 'ball_r', 'calf_l', 'calf_r', 'pelvis', 'hand_l', 'hand_r' },
    -- Blood on Soul (run 7, the author twice: «there's no blood on me at all»): the victims' blood only, never a wound. On a
    -- bled hit within PLAYER_RANGE cm of the player, with chance PLAYER_P, one two-layer attached decal on a random
    -- PLAYER_BONES bone of the player's Mesh, facing from the victim; PLAYER_MAX at most (the oldest destroyed first)
    -- Run 10 («I chop heads off up close, I should be covered in blood ... a couple of stains on the clothes and 0 on the face»): splashes on
    -- every bled hit (PLAYER_P 0.9), 2 per hit, 3 per kill, 4 per limb cut, 6 per head cut, bigger, and the head and
    -- neck first (the list repeats a bone to weight it); 3000 splashes kept
    PLAYER_RANGE = 500, PLAYER_P = 0.9, PLAYER_SIZE = 16, PLAYER_MAX = 3000,     -- the author: «up to 300», then run 11: «fps is fine, raise the limit on Soul to 3000»
    PLAYER_HIT = 2, PLAYER_KILL = 3, PLAYER_LIMB = 4, PLAYER_HEAD = 6,
    PLAYER_BONES = { 'head', 'head', 'head', 'neck_01', 'neck_01', 'spine_05', 'spine_05', 'spine_04', 'spine_03',
        'clavicle_r', 'clavicle_l', 'upperarm_r', 'upperarm_l', 'lowerarm_r', 'lowerarm_r', 'lowerarm_l', 'hand_r',
        'hand_r', 'hand_l', 'thigh_r', 'thigh_l' },
    HIT_GAP_S = 0.15, HIT_Z = 110, SNAP_BACK_S = 1.0,
    HIT_SCALE = 1.5, KILL_SCALE = 2.0, HEAD_SCALE = 1.6, STUMP_SCALE = 1.3,
    SPURTS = 4, SPURT_P = 0.45,
    DECALS_PER_HIT = 2, KILL_DECALS = 3, CUT_DECALS = 3, DECAL_SIZE = 14, DECAL_JITTER = 9,
    SIZE_MIN = 0.5, SIZE_MAX = 400, SUBUV_MAX = 3, VANILLA_N = 20, REC_N = 40, MAX_DECALS_CAP = 32767,
    PER_FRAME = 6, DECALS_PER_FRAME = 4, SETUPS_PER_FRAME = 1, QMAX = 64, SPURT_MAX = 32, FAIL_MAX = 3,
    -- The lag guard (TC-BETA-01b: hits on BP_Monster_MaleThug_Throw_Molotov_Corrupted_C cost about 150 ms each;
    -- session 20261101-lag: 60-210 ms a hit from StaticFindObject misses): at most one bled hit per HIT_RATE_S over all
    -- victims, no new bleed once FRAME_MS of this frame went to bleeds; BLEED_MS, SLOW_MS, SLOW_LOG_MAX, the STEP_*
    -- (TC-BETA-01c's first three bleeds, 20-86 ms each, very likely first-use costs, switched Soul's blood off for the
    -- whole map: the warm-up rule) and STEP_OFF_ESC (s per switch-off on a map, then the map): lab_blood_queue's header
    HIT_RATE_S = 0.12, FRAME_MS = 4, BLEED_MS = 8, SLOW_MS = 8, SLOW_LOG_MAX = 24, STEP_SLOW_MS = 20, STEP_SLOW_N = 5,
    STEP_WIN = 8, STEP_WARM = 12, STEP_HARD_MS = 30, STEP_OFF_ESC = { 30, 120 },
    -- The decal queue (header): spawns a frame, the drain's ms a frame, a job's age in game s, the queue's length
    DQ_PER_FRAME = 4, DQ_MS = 3, DQ_STALE_S = 0.6, DQ_MAX = 96,
    -- The decal materials (header, Assets): reloads of a path a map, blood_layers records a session
    REWARM_MAX = 3, LAYERS_LOG_MAX = 12,
    FX_PROBE_N = 10, FX_PROBE_S = 8,
    -- blood_amount (beta port S6): the reference (d 1 at the default 3.0), the clamp of d, the destroys a frame that
    -- bring a ring down to a lowered cap, the constants d scales and the sizes it scales by sqrt(d) (tune(), header)
    AMOUNT_REF = 3.0, AMOUNT_MIN = 0.25, AMOUNT_MAX = 3.0, TRIM_PER_FRAME = 4, SIZED = { 'ADECAL_SIZE', 'PLAYER_SIZE' },
    SCALED = { 'ADECALS_PER_HIT', 'ADECALS_KILL', 'ADECALS_CUT', 'ADECALS_ACTOR', 'ADECALS_MAX', 'POOLS_MAX',
        'PLAYER_MAX', 'PLAYER_HIT', 'PLAYER_KILL', 'PLAYER_LIMB', 'PLAYER_HEAD', 'PLAYER_EXTRA' },
    -- Soul's splashes go (bd-heal): his Health read every HEAL_POLL_S; armed HEAL_ARM of the max (HEAL_ARM_MIN points
    -- at least) below it, fired within HEAL_FULL of it; the revive, the heal fade and the life share one budget, at
    -- most WASH_PER_FRAME destroys and WASH_S seconds a frame (about 7 engine calls a destroy; a head cut's 150-250
    -- calls made an 11 ms frame, docs/research/beta-port-steps.md:67): a revive of PLAYER_MAX x 2 (6000) in about 4 s
    -- at 60 fps. A life batch's record is written LIFE_GAP_S game seconds after its last destroy. The knobs
    -- soul_blood_life_s, heal_hold_s, heal_fade_s and wash_on_heal live in core/config.lua
    HEAL_POLL_S = 0.3, HEAL_ARM = 0.02, HEAL_ARM_MIN = 2, HEAL_FULL = 0.002, HEAL_LOG_MAX = 4, WASH_PER_FRAME = 24,
    WASH_S = 0.0015, LIFE_GAP_S = 10,
    -- The receive switch back (header, B4): game s since Soul's last queued splash (past DQ_STALE_S: none still
    -- queued), blood_recv_off records a session, s between the looks at a body that waits for its wound ring to go
    RECV_IDLE_S = 3, RECV_LOG_MAX = 12, RECV_POLL_S = 2,
}
-- BD7 (MC10): an extra part of a multi-part kill (cut.rank above 1) splashes Soul half as much as a limb cut
B.PLAYER_EXTRA = B.PLAYER_LIMB // 2
-- Blood on Soul's face (soul_face_blood false, header): the bones whose splash paints his head, face or hair, by
-- lower-case name prefix. Of PLAYER_BONES: head and neck_01. Soul's skeleton: the neck chain spine_05 -> neck_01 ->
-- neck_02 -> head of every PBZ rig the lab read [inferred for Soul: his skeleton package was never read], meshhead
-- following CharacterMesh0's pose; and any face or hair bone a rig adds (FACIAL_*, jaw, eyes, brows, lids, lips,
-- teeth, tongue, nose, cheeks, ears, chin, hair). No body bone of the UE mannequin starts so
B.FACE_PREFIX = { 'head', 'neck', 'facial', 'face', 'jaw', 'eye', 'brow', 'lid', 'lip', 'teeth', 'tongue', 'nose',
    'cheek', 'ear', 'chin', 'hair' }
function B.face_bone(name)
    if type(name) ~= 'string' then return false end
    local s = name:lower()
    for _, p in ipairs(B.FACE_PREFIX) do if s:sub(1, #p) == p then return true end end
    return false
end
-- The body bones next to his neck whose splash reaches his chin and jaw, face picks too (player_bones: skipped while
-- the switch is off, and the face wash takes the ones he has). The bind poses of the PBZ rigs the lab read
-- (MaleThug_Body, GuiChai_Black_Body) put spine_05 19-23 cm below Head and clavicle_l/r 14-15 cm below it, 8-9 cm
-- off the midline; a splash box is PLAYER_SIZE x 0.7..1.3 half-size (11.2-20.8 cm at blood_amount 3) on its bone,
-- rolled at random, and Soul's head parts receive decals (receives_on). B.face_bone stays the name test
B.FACE_NEAR = { spine_05 = true, clavicle_l = true, clavicle_r = true }
B.DAMAGE_EVENT = 'GameplayEvent.Damage.Taken'
B.DAMAGE_KEYS = { h02 = true, h07 = true, h08 = true }
-- A blocked blow (header, Hits; bug B2): the hit react strength and the snapshot fields that carry it (lab_kill's
-- tier reads: Pre HitStrength, Post OriginStrength and StrengthAnimStrength), and BLOCK_S, how long after a block a
-- damage snapshot still counts as that blocked blow (the events of one blow share a frame); BLOCK_REC_N: the blocked
-- blows a session records (blood kind 'blocked', header Records)
B.BLOCK_STRENGTH, B.BLOCK_S, B.BLOCK_REC_N = 'Deflect.Defender', 0.1, 16
B.BLOCK_FIELDS = { 'hit_strength', 'origin_strength', 'anim_strength' }
B.HL_N = 150            -- blood_hl records a session (header, Records; its own cap, never REC_N's; L2 pools them for G2)
B.COUNTERS = { 'blood_hits', 'blood_fx', 'blood_fx_fail', 'blood_decals', 'blood_decal_rejected', 'blood_decal_fail',
    'blood_decal_skip', 'blood_decal_budget', 'blood_kills', 'blood_cuts', 'blood_spurts', 'blood_skip_player',
    'blood_skip_noblood', 'blood_skip_nodamage', 'blood_vanilla_decals', 'blood_adecals', 'blood_adecal_fail', 'blood_pools', 'blood_player',
    'soul_wash', 'soul_wash_unread', 'soul_fade_life', 'soul_fade_heal', 'soul_fade_revive', 'blood_skip_rate',
    'blood_slow', 'blood_step_off', 'blood_slices', 'blood_skip_deadline', 'blood_dq_stale', 'blood_dq_off',
    'blood_dq_gone', 'blood_dq_full', 'blood_rewarm', 'blood_hold', 'blood_hold_fail', 'blood_skip_face',
    'soul_fade_face', 'blood_skip_blocked', 'blood_recv_off' }

local A = nil
local alive = false                                     -- the vanilla observer returns at once when false
local new_heal = WS.new_heal                             -- the heal state (lab_blood_wash)
local function new_state()
    return { init = false, ended = false, hitq = {}, deathq = {}, cutq = {}, sliceq = {}, spurts = {}, qdrop = 0,
        pawn_key = nil,
        last = {}, seen_t = {}, spot = {}, samplers = {}, class_logged = {}, recs = 0, brecs = 0, hlrecs = 0, hooked = false,
        ours = false, vq = {}, vn = 0, v_size = nil, v_subuv = {}, v_subuv_n = 0, warmq = {}, got = {}, miss = {},
        missing = {}, first = true, spawned = 0, err = nil, dbudget = 0, sbudget = 0, decal_class = {}, look_class = {},
        look_logged = {}, recv = {}, adecal_logged = {}, adecal_n = {}, adecal_ring = {}, pawn = nil, pools = {}, pring = {},
        fails = {}, off = {}, probes = {}, nprobe = 0, d = nil, k = {}, skinned = true, observe = true, fx_probe = true,
        heal = new_heal(), heal_logged = {}, heal_logn = 0, pseq = 0, rev = nil, fade = nil, life = nil,
        hit_t = -math.huge, steps = {}, step_slow = {}, step_off = {}, step_calls = {}, slow_n = 0,
        -- the hit lag (header): the lag guard's levels and hard calls in a row, the per-call timers of the current bleed
        -- or drain (calls, the dearest call, the lookup counters at its start), the decal queue, the reloads, the held
        -- layers of the map, the layers
        step_lvl = {}, step_hard = {}, calls = {}, call_max = nil, call_max_ms = 0, f0 = 0, m0 = 0, dq = {},
        rewarm = {}, rewarmq = {}, held = {}, layers_key = nil, layers_logn = 0, pbones = nil,
        -- the receive switch back (header, B4): the parts switched per key, the ring's stains per key, Soul's key and
        -- the game time of his last queued splash, the records written; the stains still queued per key, lab_cap's
        -- wound rings per key (B.recv_pin) and the keys whose switch back waits for their ring to go
        recv_parts = {}, adecal_live = {}, soul_key = nil, soul_t = nil, recv_logn = 0, adecal_q = {}, recv_pin = {},
        recv_wait = {} }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or os.clock() end
local function gnow() return S.game_time or 0 end         -- game seconds: stops in pause and loads (Soul's splashes)
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function pick(list, i) return list[((i - 1) % #list) + 1] end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function short(path) return type(path) == 'string' and (path:match('([^/.]+)$') or path) or '?' end

-- ---------- the amount (beta port S6): blood_amount scales the attached decals, pools and Soul's splashes ----------
-- d from the settings (1 when unread or not a number); st.k holds the values in use, rebuilt when d changes: at d 1 the
-- B constants themselves
local function amount()
    local ok, s = pcall(C.get)
    local v = ok and type(s) == 'table' and tonumber(s.blood_amount) or nil
    if not num(v) then return 1 end
    return clamp(v / B.AMOUNT_REF, B.AMOUNT_MIN, B.AMOUNT_MAX)
end
local function tune()
    local d = amount()
    if d == st.d then return end
    st.d = d
    for _, name in ipairs(B.SCALED) do st.k[name] = d == 1 and B[name] or math.max(1, math.floor(B[name] * d + 0.5)) end
    for _, name in ipairs(B.SIZED) do st.k[name] = d == 1 and B[name] or B[name] * math.sqrt(d) end
end
local function blood_on()
    local ok, on = pcall(C.effect, 'blood')
    return not ok or on ~= false
end

-- {x, y, z} from an engine vector (X/Y/Z) or a plain one (x/y/z); nil unless three finite numbers
local function xyz(v)
    v = ue.p(v)
    if v == nil then return nil end
    local x, y, z
    if type(v) == 'table' and v.x ~= nil then x, y, z = v.x, v.y, v.z
    else x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z') end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
-- An FRotator facing along d (yaw from x/y, pitch from z); level when d is missing, zero or not finite
local function rot_of(d)
    if type(d) ~= 'table' or not (num(d.x) and num(d.y) and num(d.z)) then return ue.rot(0, 0, 0) end
    local n = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    if not num(n) or n < 1e-6 then return ue.rot(0, 0, 0) end
    return ue.rot(math.deg(math.asin(clamp(d.z / n, -1, 1))), math.deg(math.atan(d.y, d.x)), 0)
end

-- ---------- the breaker: a call kind stops for the map after FAIL_MAX failures in a row ----------
local function stopped(name) return st.off[name] == true end
local function failed(name, err)
    local n = (st.fails[name] or 0) + 1
    st.fails[name] = n
    if err then st.err = tostring(err):sub(1, 160) end
    if n >= B.FAIL_MAX and not st.off[name] then
        st.off[name] = true
        LAB.rec('blood_off', { name = name, fails = n, err = st.err }, true)
    end
end
local function worked(name) st.fails[name] = 0 end

-- ---------- assets: resolved one a frame after a map load; the hit path never loads ----------
-- A Niagara system: the cached one, else (never cached) one lookup with the miss kept for the map; a stale one (the GC
-- took it) is missing until its reload, never looked up
local function system(path)
    if st.missing[path] then return nil end
    local o, _, why = ue.asset_peek(path)
    if o then return o end
    if why == 'stale' then
        st.missing[path] = true
        rewarm(path, true)
        return nil
    end
    o = ue.find(path)
    if not o then st.missing[path] = true end
    return o
end
local function warm_step()
    local path = table.remove(st.warmq, 1)
    if not path then return end
    local o = QL.load(path)                             -- a decal layer lab_blood draws is held in the same call
    if o then st.got[#st.got + 1] = short(path) st.missing[path] = nil
    else st.miss[#st.miss + 1] = short(path) st.missing[path] = true end
    if not st.warmq[1] then
        table.sort(st.got)
        table.sort(st.miss)
        LAB.rec('blood_assets', { found = st.got, missing = st.miss }, true)
    end
end

-- ---------- engine calls (lab ticker only) ----------
local function probe_push(c, path)
    if not st.fx_probe or st.nprobe >= B.FX_PROBE_N then return end
    st.nprobe = st.nprobe + 1
    st.probes[#st.probes + 1] = { rec = ue.keep_mod(c), fx = short(path), due = now() + B.FX_PROBE_S }
end
-- Niagara at a world spot, scaled, auto-destroyed, no pool, scalability off (a far camera would cull it)
local function spray(path, pos, rot, scale)
    if stopped('blood.fx') then return false end
    local sys = system(path)
    local lib, w = ue.cdo('niagara'), ue.world()
    if not (sys and lib and w) then
        LAB.count('blood_fx_fail')
        return false
    end
    local t0 = now()
    local c, err = LAB.hot('blood.fx', function()
        ue.count_write()
        -- lint:allow L016 the lab's own gate: no player, no no_blood class, damage only, mod-off; the release port goes through fx_gate
        local c = lib:SpawnSystemAtLocation(w, sys, ue.vec(pos.x, pos.y, pos.z), rot, ue.vec(scale, scale, scale), true,
            false, 0, false)
        c = ue.p(c)
        if not ue.valid(c) then return nil end
        pcall(function() c:SetAllowScalability(false) end)
        pcall(function() c:Activate(true) end)
        return c
    end)
    lap('fx.spawn', t0)
    if c then
        worked('blood.fx')
        LAB.count('blood_fx')
        st.spawned = st.spawned + 1
        probe_push(c, path)
        return true
    end
    LAB.count('blood_fx_fail')
    failed('blood.fx', err or 'no_component')
    return false
end
-- Inside the caller's guard: Niagara attached to a bone of a mesh (SnapToTarget), auto-destroyed, scaled, scalability
-- off; the component or nil (spurt under 'blood.spurt'; a slice's pulse under 'slicer.blood', lab_blood_slice)
local function attach_fx(lib, sys, mesh, bone, scale)
    ue.count_write()
    -- lint:allow L016 the lab's own gate (cuts and slices of bleeding classes only, mod-off); the release port goes through fx_gate
    local c = ue.p(lib:SpawnSystemAttached(sys, mesh, ue.fname(bone), ue.vec(0, 0, 0), ue.rot(0, 0, 0), 2, true, false,
        0, false))
    if not ue.valid(c) then return nil end
    pcall(function() c:SetWorldScale3D(ue.vec(scale, scale, scale)) end)
    pcall(function() c:SetAllowScalability(false) end)
    pcall(function() c:Activate(true) end)
    return c
end
local function spurt(path, mesh, bone, scale)
    if stopped('blood.spurt') then return false end
    local sys = system(path)
    local lib = ue.cdo('niagara')
    if not (sys and lib and ue.valid(mesh)) then
        LAB.count('blood_fx_fail')
        return false
    end
    local c, err = LAB.hot('blood.spurt', attach_fx, lib, sys, mesh, bone, scale)
    if c then
        worked('blood.spurt')
        LAB.count('blood_fx')
        LAB.count('blood_spurts')
        probe_push(c, path)
        return true
    end
    LAB.count('blood_fx_fail')
    failed('blood.spurt', err or 'no_component')
    return false
end
-- The world spot of a bone on a mesh (GetSocketLocation), or nil
local function bone_pos(mesh, bone)
    if not (ue.valid(mesh) and type(bone) == 'string' and bone ~= '' and bone ~= 'None') then return nil end
    local t0 = now()
    local p = LAB.hot('blood.read', function() return xyz(mesh:GetSocketLocation(ue.fname(bone))) end)
    lap('read', t0)
    return p
end
local function actor_pos(actor)
    if not ue.valid(actor) then return nil end
    local t0 = now()
    local p = LAB.hot('blood.read', function() return xyz(actor:K2_GetActorLocation()) end)
    lap('read', t0)
    if p then p.z = p.z + B.HIT_Z end
    return p
end

-- The mesh a sampler (or an actor, field 'Mesh') holds while it is set up: a valid skinned component with a mesh
-- asset (SpawnDecal reads the asset's skeleton unchecked); nil otherwise
local function mesh_with_asset(o)
    local mesh = ue.get(o, 'Mesh')
    if not ue.valid(mesh) then return nil end
    local asset = ue.get(mesh, 'SkinnedAsset')
    if not ue.valid(asset) then asset = ue.get(mesh, 'SkeletalMeshAsset') end
    if not ue.valid(asset) then return nil end
    return mesh
end
-- The look on the sampler's MIDs (B.LOOK through SetTextureParameterValue), once per sampler; the first per class armed,
-- then hot. One blood_look record per class: the MIDs, DecalColor's texture before, how many writes ran, and whether
-- the sampler's mesh draws those MIDs (its GetMaterial(i) among them). The textures through texture_any (one lookup
-- per path per map at most)
local function name_of(o) return ue.valid(o) and ue.name(o) or 'none' end
local function look_on(s, class)
    if s.looked or stopped('blood.look') then return end
    s.looked = true
    local mids, arr = {}, ue.get(s.obj, 'Materials')
    pcall(function()
        for i = 1, math.min(#arr, B.MIDS_MAX) do
            local m = ue.p(arr[i])
            if ue.valid(m) then mids[#mids + 1] = m end
        end
    end)
    local before = {}
    for i, m in ipairs(mids) do
        if i > 4 then break end
        local t = LAB.hot('blood.read', function() return ue.p(m:K2_GetTextureParameterValue(ue.fname(B.LOOK[1][1]))) end)
        before[#before + 1] = name_of(t)
    end
    local function apply()
        local n = 0
        for _, m in ipairs(mids) do
            for _, pair in ipairs(B.LOOK) do
                local tex = texture_any(pair[2])
                if tex then
                    ue.count_write()
                    m:SetTextureParameterValue(ue.fname(pair[1]), tex)
                    n = n + 1
                end
            end
        end
        return n
    end
    local ck = class or '?'
    local n, err
    if st.look_class[ck] then n, err = LAB.hot('blood.look', apply)
    else n, err = LAB.armed('blood.look', apply) st.look_class[ck] = n ~= nil end
    if n == nil then failed('blood.look', err) else worked('blood.look') end
    if st.look_logged[ck] then return end
    st.look_logged[ck] = true
    local drawn, nm = 0, nil
    pcall(function()
        nm = s.mesh:GetNumMaterials()
        for i = 0, math.min((nm or 0) - 1, B.MIDS_MAX) do
            local g = ue.p(s.mesh:GetMaterial(i))
            for _, m in ipairs(mids) do if ue.same(g, m) then drawn = drawn + 1 break end end
        end
    end)
    local rm = ue.get(s.obj, 'RenderMeshes')
    local okr, nrm = pcall(function() return #rm end)
    -- Does the material draw the plugin's decals at all (run 5: the look set, still none seen)? The plugin writes
    -- DecalMax (MaxDecals), DecalInfo (the DataTarget) and DecalLast on its MIDs (PBZ.exe 0x144D30597-0x144D3067E); a
    -- material without SkinnedDecalFunction answers DecalMax 0 and DecalInfo none
    local probe = {}
    for i, m in ipairs(mids) do
        if i > 4 then break end
        local dmax = LAB.hot('blood.read', function() return m:K2_GetScalarParameterValue(ue.fname('DecalMax')) end)
        local info = LAB.hot('blood.read', function() return ue.p(m:K2_GetTextureParameterValue(ue.fname('DecalInfo'))) end)
        probe[#probe + 1] = { decal_max = dmax, decal_info = name_of(info), parent = name_of(ue.get(m, 'Parent')) }
    end
    -- The look's real parameter names: every probe name that answers a texture on the first two MIDs
    local answered = {}
    for i, m in ipairs(mids) do
        if i > 2 then break end
        for _, pname in ipairs(B.LOOK_PROBE) do
            local t = LAB.hot('blood.read', function() return ue.p(m:K2_GetTextureParameterValue(ue.fname(pname))) end)
            if ue.valid(t) then answered[#answered + 1] = i .. ':' .. pname .. '=' .. name_of(t) end
        end
    end
    LAB.rec('blood_look', { class = class, mids = #mids, before = before, writes = n, err = err and tostring(err):sub(1, 160),
        mesh_mats = nm, drawn = drawn, render_meshes = okr and nrm or 'unread', probe = probe, answered = answered,
        receives = ue.get(s.mesh, 'bReceivesDecals'),
        textures = { texture_any(B.LOOK[1][2]) ~= nil, texture_any(B.LOOK[2][2]) ~= nil,
            texture_any(B.LOOK[3][2]) ~= nil } }, true)
end
-- The victim's sampler and whether it may take a decal, read once per actor (keyed by address and name: a freed
-- actor's block reused by another reads as new; an actor with no sampler is remembered too). The BP variable
-- SkinnedDecalSampler (BP_NPC_Base_C), else the first component of the class. Not set up: one armed AutoSetup when the
-- frame allows it and the actor's own Mesh has an asset; used only if the sampler then holds the actor's Mesh
local function sampler_of(actor, class)
    local addr, name = ue.addr(actor), ue.name(actor)
    local key = addr and name and (tostring(addr) .. '|' .. name) or nil
    local s = key and st.samplers[key]
    if s and (s.obj == nil or ue.valid(s.obj)) then return s end
    s = { obj = nil, ok = false, why = 'none', mesh = nil }
    local o = ue.get(actor, 'SkinnedDecalSampler')
    if not ue.valid(o) then
        local list = LAB.hot('blood.comps', function() return (ue.components(actor, B.SAMPLER)) end) or {}
        o = list[1]
    end
    if ue.valid(o) then
        s.obj = o
        local mesh0 = mesh_with_asset(o)
        local setup = nil
        if not mesh0 then
            local own = mesh_with_asset(actor)
            if not own then setup = 'actor_mesh'
            elseif stopped('blood.setup') then setup = 'stopped'
            elseif st.sbudget <= 0 then setup = 'budget'
            else
                st.sbudget = st.sbudget - 1
                local r, err = LAB.armed('blood.setup', function()
                    ue.count_write()
                    -- lint:allow L015 AutoSetup only on an actor whose own Mesh has an asset, 1 a frame, armed, and its pick is checked below
                    o:AutoSetup()
                    return true
                end)
                if r then worked('blood.setup') setup = 'ran' else failed('blood.setup', err) setup = 'failed' end
                local after = mesh_with_asset(o)
                if after and ue.same(after, own) then mesh0 = after
                elseif after then setup = 'other_mesh' end
            end
        end
        local max, last = ue.get(o, 'MaxDecals'), ue.get(o, 'LastDecalIndex')
        local mind, tb, dt = ue.get(o, 'MinDecalDistance'), ue.get(o, 'TranslucentBlend'), ue.get(o, 'DataTarget')
        local mats = ue.get(o, 'Materials')
        local okn, nm = pcall(function() return #mats end)
        if not mesh0 then s.why = 'not_setup'
        elseif not num(max) or max < 1 or max > B.MAX_DECALS_CAP then s.why = 'max_decals'
        elseif not num(last) or last < -1 or last >= B.MAX_DECALS_CAP then s.why = 'last_index'
        else s.ok, s.why, s.mesh = true, nil, mesh0 end
        s.jitter = math.max(B.DECAL_JITTER, num(mind) and mind > 0 and 1.5 * math.sqrt(mind) or 0)
        if setup == 'budget' then s.retry = true end           -- no verdict yet: ask again on a later hit
        if not st.class_logged[class or '?'] and not s.retry then
            st.class_logged[class or '?'] = true
            LAB.rec('blood_sampler', { class = class, set_up = s.ok or mesh0 ~= nil, auto_setup = setup,
                max_decals = max, last_index = last, min_distance = r1(mind), translucent = tb,
                data_target = ue.valid(dt), materials = okn and nm or 'unread', ok = s.ok, why = s.why })
        end
    end
    if key and not s.retry then st.samplers[key] = s end
    if s.ok then look_on(s, class) end
    return s
end
-- One decal at pos on bone: Index -1 (the next slot), our Size or the vanilla one, a SubUV vanilla used (else
-- 0-SUBUV_MAX). The answer is the slot, or -1 when the plugin dropped it (too close to another): blood_decal_rejected
local function decal(s, pos, bone, class)
    if stopped('blood.decal') then return false end
    if not (s and s.ok and ue.valid(s.obj) and ue.valid(s.mesh)) then LAB.count('blood_decal_skip') return false end
    local ck = class or '?'
    if st.decal_class[ck] == 'failed' then LAB.count('blood_decal_skip') return false end
    if st.dbudget <= 0 then LAB.count('blood_decal_budget') return false end
    if type(bone) ~= 'string' or bone == '' or bone == 'None' or not ue.has_bone(s.mesh, bone) then
        LAB.count('blood_decal_skip')
        return false
    end
    if not ue.same(ue.get(s.obj, 'Mesh'), s.mesh) then                 -- re-read: a set-up may have moved it
        s.ok, s.why = false, 'mesh_changed'
        LAB.count('blood_decal_skip')
        return false
    end
    local last, max = ue.get(s.obj, 'LastDecalIndex'), ue.get(s.obj, 'MaxDecals')
    if not (num(max) and max >= 1 and max <= B.MAX_DECALS_CAP and num(last) and last >= -1
            and last < B.MAX_DECALS_CAP) then
        s.ok, s.why = false, 'max_decals'
        LAB.count('blood_decal_skip')
        return false
    end
    st.dbudget = st.dbudget - 1
    local j = s.jitter or B.DECAL_JITTER
    local p = ue.vec(pos.x + (math.random() * 2 - 1) * j, pos.y + (math.random() * 2 - 1) * j,
        pos.z + (math.random() * 2 - 1) * j)
    local size = clamp((st.v_size or B.DECAL_SIZE) * (0.8 + 0.4 * math.random()), B.SIZE_MIN, B.SIZE_MAX)
    local subuv = st.v_subuv_n > 0 and st.v_subuv[math.random(st.v_subuv_n)] or math.random(0, B.SUBUV_MAX)
    local function call()
        ue.count_write()
        st.ours = true
        local ok, idx = pcall(function()
            -- lint:allow L015 guarded above: set-up sampler with a mesh asset, its Mesh unchanged, bone on that mesh, MaxDecals 1..32767, 4 a frame, first per class armed
            return s.obj:SpawnDecal(p, { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, ue.vec(1, 1, 1), ue.fname(bone),
                size + 0.0, math.tointeger(subuv) or 0, -1)
        end)
        st.ours = false
        if not ok then error(idx, 0) end
        idx = ue.p(idx)
        return math.type(idx) == 'integer' and idx or -2                   -- -2: no integer came back
    end
    local idx, err
    if st.decal_class[ck] then idx, err = LAB.hot('blood.decal', call)
    else
        idx, err = LAB.armed('blood.decal', call)
        st.decal_class[ck] = idx ~= nil and true or 'failed'
    end
    if idx == nil then
        LAB.count('blood_decal_fail')
        failed('blood.decal', err)
        return false
    end
    worked('blood.decal')
    if idx < 0 then LAB.count('blood_decal_rejected') return false end
    LAB.count('blood_decals')
    return true
end
local function decals(actor, class, pos, bone, n)
    if not (st.skinned and actor and pos) then return 0 end      -- the beta: no skinned decal (S6)
    local s = sampler_of(actor, class)
    local k = 0
    for _ = 1, n do if decal(s, pos, bone, class) then k = k + 1 end end
    return k
end

-- ---------- attached deferred decals: the fallback for blood on clothes (run 5: skinned decals unseen) ----------
-- GameplayStatics.SpawnDecalAttached(Material, DecalSize, AttachTo, AttachPointName, Location, Rotation, LocationType 1
-- KeepWorldPosition, LifeSpan 0): a box of the game's own blood decal material on the struck bone of the victim's Mesh,
-- centred on the bone and facing from the player to the victim, so it paints the cloth on both sides of the limb and
-- follows the bone (destroyed with its owner). SetFadeScreenSize(0) (the engine's 0.01 fades small decals at distance).
-- Deferred decals draw on a primitive only while bReceivesDecals: a mesh of the victim that reads false is switched on
-- once per actor (SetReceivesDecals, 'blood.recv'), so the game's ground blood can mark the legs too, and back once
-- nothing of ours is left on it (recv_off: the switch back, header). Caps: ADECALS_ACTOR
-- per actor, ADECALS_MAX overall (the oldest destroyed first, only while it is still the one kept). blood_adecal: one
-- record per class (material, receives before, meshes switched)
-- The layers: the stain and the spatter (ADECAL_MATS 1 and 2) when in the asset cache, else the first other one there,
-- as paths (a queued decal finds its material again in its own frame) and short names. Peeks only (texture, header
-- Assets): once a bleed (st.bleed_paths, QL.begin clears it), never once a splash; a lost stain or spatter queues its
-- reload; a later material is reloaded only while neither of those can be had (QL.can_load), and then one at most: no
-- load for a material nothing draws once the two are back. An answer that differs from the last one writes blood_layers
local function adecal_layers()
    if st.bleed_paths then return st.bleed_paths, st.bleed_names end
    local t0 = now()
    local paths, names = {}, {}
    for i = 1, 2 do
        local p = B.ADECAL_MATS[i]
        if texture(p) then paths[#paths + 1], names[#names + 1] = p, short(p) end
    end
    if not paths[1] then
        local peek = QL.can_load(B.ADECAL_MATS[1]) or QL.can_load(B.ADECAL_MATS[2])
        for i = 3, #B.ADECAL_MATS do
            local p = B.ADECAL_MATS[i]
            if texture(p, peek) then
                paths[1], names[1] = p, short(p)
                break
            end
            if not peek and QL.can_load(p) then peek = true end      -- its reload waits: the rest peeked
        end
    end
    lap('layers', t0)
    local key = table.concat(names, '|')
    if key ~= st.layers_key then
        local was = st.layers_key
        st.layers_key = key
        if st.layers_logn < B.LAYERS_LOG_MAX then
            st.layers_logn = st.layers_logn + 1
            LAB.rec('blood_layers', { materials = names, was = was, reloads = #st.rewarmq }, true)
        end
    end
    st.bleed_paths, st.bleed_names = paths, names
    return paths, names
end
-- key: the actor's address (ue.addr; nil: never switched)
local function receives_on(actor, class, key)
    if not key or st.recv[key] then return end
    st.recv[key] = true
    local t0 = now()
    local before, switched, parts = {}, 0, {}
    local comps = LAB.hot('blood.comps', function() return (ue.components(actor, '/Script/Engine.SkinnedMeshComponent')) end)
        or {}
    for i, c in ipairs(comps) do
        if i > 16 then break end                        -- run 8: Soul is 13 skinned parts (8 left 5 unswitched)
        -- a slicer half (an actor bled first after its slice) is lab_blood_slice's, under 'slicer.blood' only
        local half = (ue.name(c) or ''):find('^Akasha%a*SliceComponent') ~= nil
        local r = nil
        if not half then r = ue.get(c, 'bReceivesDecals') end
        before[#before + 1] = half and 'half' or r
        if r == false and not stopped('blood.recv') then
            local ok, err = LAB.hot('blood.recv', function()
                ue.count_write()
                c:SetReceivesDecals(true)
                return true
            end)
            if ok then
                switched, parts[#parts + 1] = switched + 1, ue.keep(c)
                worked('blood.recv')
            else
                failed('blood.recv', err)
            end
        end
    end
    if parts[1] then st.recv_parts[key] = { parts = parts, class = class } end   -- recv_off takes them back (header)
    lap('recv', t0)
    if not st.adecal_logged[class or '?'] then
        st.adecal_logged[class or '?'] = true
        local _, names = adecal_layers()
        LAB.rec('blood_adecal', { class = class, materials = names, meshes = #comps, receives_before = before,
            switched = switched }, true)
    end
end
-- The receive switch back (header, B4): the parts switched for key (st.recv_parts) back to the game's false, each
-- still the one kept (a half by its full name) and reading true, in one call under 'blood.recv' (a half's under
-- 'slicer.blood'); st.recv forgets key, so the next splash or stain switches them on again. why: 'empty', 'stains' or
-- 'ring'. Not while lab_cap's wound ring lives on key's leader (pinned: the key waits in st.recv_wait, recv_poll).
-- true when it ran
local function ring_live(rec)                           -- lab_cap's keep: ue.keep_mod, else ue.keep
    if type(rec) ~= 'table' then return false end
    if rec.full then return ue.live_mod(rec) ~= nil end
    return ue.live(rec) ~= nil
end
local function pinned(key)                              -- a live ring on key (B.recv_pin); the gone ones forgotten
    local p = st.recv_pin[key]
    if not p then return false end
    for i = #p, 1, -1 do if not ring_live(p[i]) then table.remove(p, i) end end
    if p[1] then return true end
    st.recv_pin[key] = nil
    return false
end
local function recv_off(key, why)
    local r = key and st.recv_parts[key]
    if not r then return false end
    local name = r.half and 'slicer.blood' or 'blood.recv'
    if stopped(name) then return false end
    if pinned(key) then st.recv_wait[key] = true return false end
    st.recv_parts[key], st.recv[key], st.recv_wait[key] = nil, nil, nil
    local n, err = LAB.hot(name, function()
        local k = 0
        for _, rec in ipairs(r.parts) do
            local c = r.half and ue.live_mod(rec) or ue.live(rec)
            if c and ue.get(c, 'bReceivesDecals') == true then
                ue.count_write()
                c:SetReceivesDecals(false)
                k = k + 1
            end
        end
        return k
    end)
    if n == nil then failed(name, err) else worked(name) LAB.count('blood_recv_off') end
    if st.recv_logn < B.RECV_LOG_MAX then
        st.recv_logn = st.recv_logn + 1
        LAB.rec('blood_recv_off', { why = why, class = r.class, half = r.half and true or nil, parts = #r.parts,
            switched = n, err = err and tostring(err):sub(1, 160) or nil }, true)
    end
    return true
end
-- No stain of key left, none in the ring (st.adecal_live) and none still queued (st.adecal_q: the queue's spawn, drop
-- or fail takes it off): its parts back (recv_off; why 'stains' unless given). true when recv_off ran
local function stains_out(key, why)
    if key == nil or (st.adecal_live[key] or 0) > 0 or (st.adecal_q[key] or 0) > 0 then return false end
    return recv_off(key, why or 'stains')
end
-- A body whose switch back waited for its wound ring (recv_off, pinned): each RECV_POLL_S, once the ring is gone (its
-- Cap dropped, a restore, the corpse gone), its parts back unless it holds stains again (why 'ring')
local function recv_poll()
    if next(st.recv_wait) == nil or not LAB.due('lab_blood.recv', B.RECV_POLL_S) then return end
    local keys = {}
    for key in pairs(st.recv_wait) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        if not st.recv_parts[key] then st.recv_wait[key] = nil
        elseif not pinned(key) then
            st.recv_wait[key] = nil
            stains_out(key, 'ring')
        end
    end
end
-- A ring's oldest entry destroyed: a decal attached to a slicer half (rec.half) under 'slicer.blood', as every call
-- that touches a half (lab_blood_slice's header), so a fault there never strikes a blood.* name. A stain (rec.akey,
-- lab_blood_queue's job_adecal) leaves its key's count; its last one takes the key's parts back (stains_out)
local function evict(rec)
    local old = ue.live_mod(rec)
    if old then
        if type(rec) == 'table' and rec.half then LAB.hot('slicer.blood', ue.destroy, old) else ue.destroy(old) end
    end
    local key = type(rec) == 'table' and rec.akey or nil
    if key == nil then return end
    local n = (st.adecal_live[key] or 1) - 1
    st.adecal_live[key] = n > 0 and n or nil
    stains_out(key)
end

-- t: one call's decals on a mesh { name, actor, class, pos (one copy), bone, mesh, face, mrec, arec[, ok, key] }; ok
-- (mesh valid) and key (ue.addr of the half, else of the actor) are read at its first decal unless given. name: the
-- guard and breaker kind, 'blood.adecal', or 'slicer.blood' when mesh is a slice's Negative half (lab_blood_slice): no
-- receives switch of the actor's (the slice switches the half), and ADECALS_ACTOR counts the half's own decals (the
-- slice hid the actor's earlier ones with its source). mrec: the half's ue.keep_mod record (read only inside
-- 'slicer.blood'), else the mesh's ue.keep; arec: the victim's ue.keep. Queues one decal of layer mat (a path) round
-- bone; true when queued
local function adecal(t, mat)
    if stopped(t.name) then return false end
    if t.ok == nil then t.ok = ue.valid(t.mesh) end
    local bone, half = t.bone, t.name == 'slicer.blood'
    if not (t.ok and t.pos and mat) or type(bone) ~= 'string' or bone == '' or bone == 'None' then return false end
    local key = t.key
    if key == nil then key = ue.addr(half and t.mesh or t.actor) or false t.key = key end
    local n = key and (st.adecal_n[key] or 0) or 0
    if n >= st.k.ADECALS_ACTOR or not (t.mrec and t.arec) then return false end
    -- a full queue refuses before the receives switch: no on and off again for each stain of the bleed it cannot take
    if #st.dq >= B.DQ_MAX then LAB.count('blood_dq_full') return false end
    if not half then receives_on(t.actor, t.class, key) end
    local j = B.ADECAL_JITTER
    local r = rot_of(t.face)
    r.Roll = math.random() * 360.0
    local job = { kind = 'adecal', step = 'adecal', name = t.name, half = half, actor = t.arec, mesh = t.mrec,
        akey = key or nil, bone = bone, pos = t.pos, r = r, mat = mat, h = st.k.ADECAL_SIZE * (0.7 + 0.6 * math.random()),
        off = { x = (math.random() * 2 - 1) * j, y = (math.random() * 2 - 1) * j, z = (math.random() * 2 - 1) * j } }
    if not dq_push(job) then
        if key then stains_out(key) end                 -- a first stain the full queue refused: no switch left on
        return false
    end
    if key then st.adecal_n[key], st.adecal_q[key] = n + 1, (st.adecal_q[key] or 0) + 1 end
    return true
end
local function soul_at()                                -- Soul and his spot, read once a bleed (QL.begin clears them)
    local s = st.bleed_soul or { st.pawn and ue.live(st.pawn) or nil }
    if not st.bleed_soul then s[2], st.bleed_soul = s[1] and actor_pos(s[1]) or nil, s end
    return s[1], s[2]
end
-- The direction the decal box faces: from the player to the victim (the side the player sees), else the blow's
local function face_of(actor, dir)
    local a, b = select(2, soul_at()), actor_pos(actor)
    if a and b then
        local d = { x = b.x - a.x, y = b.y - a.y, z = 0 }
        if math.abs(d.x) + math.abs(d.y) > 1 then return d end
    end
    return dir
end
-- The PLAYER_BONES Soul's mesh has (a repeated name weights it), read once per mesh and map (21 GetBoneIndex a bleed
-- before), the mesh's address (its splashes' key) and the set of its face picks among them (B.face_bone, B.FACE_NEAR)
local function player_bones(mesh)
    local addr, name, c = ue.addr(mesh), ue.name(mesh), st.pbones
    if c and c.addr == addr and c.name == name and c.ep == ue.epoch then return c.list, addr, c.face end
    local list, face = {}, {}
    for _, b in ipairs(B.PLAYER_BONES) do
        if ue.has_bone(mesh, b) then
            list[#list + 1] = b
            if B.face_bone(b) or B.FACE_NEAR[b] then face[b] = true end
        end
    end
    st.pbones = { addr = addr, name = name, ep = ue.epoch, list = list, face = face }
    return list, addr, face
end
-- Blood on Soul (B.PLAYER_*): the player's meshes switched to receive decals once, then n splashes on random bones,
-- each layer queued (lab_blood_queue spawns it on the bone read again then); with Blood on Soul's face off a face
-- pick (player_bones) is skipped (header), the others land as with it on
local function on_player(victim_pos, n, sure)
    if C.knob('soul_blood') == false then return false end   -- Blood on Soul off (header): no splash, no receives switch
    if stopped('blood.player') or (not sure and math.random() > B.PLAYER_P) then return false end
    local pawn, ppos = soul_at()
    if not (ppos and victim_pos) then return false end
    local dx, dy, dz = ppos.x - victim_pos.x, ppos.y - victim_pos.y, ppos.z - victim_pos.z
    if dx * dx + dy * dy + dz * dz > B.PLAYER_RANGE * B.PLAYER_RANGE then return false end
    local mesh = ue.get(pawn, 'Mesh')
    if not ue.valid(mesh) then return false end
    local pkey = ue.addr(pawn)
    if GREY.recv_ok() then receives_on(pawn, 'player', pkey) end   -- 'soul_recv off' (lab_grey): none switched
    st.soul_key, st.soul_t = pkey, gnow()               -- the switch back waits RECV_IDLE_S from here (header)
    local bones, mkey, face = player_bones(mesh)
    if not bones[1] then return false end
    local layers = adecal_layers()
    if not layers[1] then return false end
    local clean = C.knob('soul_face_blood') == false    -- Blood on Soul's face off (header): its picks skipped
    local k = 0
    for _ = 1, (n or 1) do
        local bone = bones[math.random(#bones)]
        local bp = nil
        if clean and face[bone] then LAB.count('blood_skip_face') else bp = bone_pos(mesh, bone) end
        if bp then
            GREY.splash(mesh, bone, bp, -dx, -dy)       -- 'soul_ovl on' (lab_grey): his sampler too, toward the victim
            local r = rot_of({ x = dx, y = dy, z = 0 })
            r.Roll = math.random() * 360.0
            for _, mat in ipairs(layers) do
                if dq_push({ kind = 'player', step = 'player', name = 'blood.player', mesh = mkey, bone = bone, pos = bp,
                    r = r, mat = mat, h = st.k.PLAYER_SIZE * (0.7 + 0.6 * math.random()), face = face[bone] }) then
                    k = k + 1
                end
            end
        end
    end
    if k > 0 then LAB.count('blood_player') end
    return k > 0
end
local function adecals(actor, class, pos, bone, dir, n)
    local mesh = actor and pos and bone and ue.get(actor, 'Mesh')
    if not ue.valid(mesh) then return 0 end
    local t = { name = 'blood.adecal', actor = actor, class = class, bone = bone, mesh = mesh, ok = true,
        face = face_of(actor, dir), pos = { x = pos.x, y = pos.y, z = pos.z } }
    local layers, k = adecal_layers(), 0
    t.mrec, t.arec = ue.keep(mesh), ue.keep(actor)
    for _ = 1, n do for _, mat in ipairs(layers) do if adecal(t, mat) then k = k + 1 end end end
    return k
end
-- A pool on the ground under pos, size half-extent h, of layer mat (a path): queued; lab_blood_queue spawns it
local function pool_one(pos, h, mat)
    return dq_push({ kind = 'pool', step = 'pool', name = 'blood.pool', mat = mat, pos = { x = pos.x, y = pos.y, z = pos.z },
        s = h * (0.8 + 0.4 * math.random()), yaw = math.random() * 360.0 })
end
-- The ground under a body: its lowest bone of GROUND_BONES minus FOOT_LIFT (a standing body's feet, a lying corpse's
-- lowest limb); nil when none reads. read(mesh, bone): bone_pos (each read under 'blood.read'), else a slice's own
-- reader inside 'slicer.blood' on a half it resolved (lab_blood_slice)
local function ground_z(mesh, read)
    if read == nil then
        if not ue.valid(mesh) then return nil end
        read = bone_pos
    end
    local lo
    for _, b in ipairs(B.GROUND_BONES) do
        if ue.has_bone(mesh, b) then
            local p = read(mesh, b)
            if p and (lo == nil or p.z < lo) then lo = p.z end
        end
    end
    return lo and (lo - B.FOOT_LIFT) or nil
end
-- A pool at pos's x and y on the ground height gz (a slice reads gz on its Negative half under 'slicer.blood'): the
-- stain, then the spatter at 0.7 of the size over it for a denser pool; one: the stain alone (a plain hit's pool, the
-- hit lag: pools belong to kills and cuts)
local function pool_z(pos, gz, h, one)
    if stopped('blood.pool') or not (pos and gz) then return false end
    pos = { x = pos.x, y = pos.y, z = gz }
    local layers = adecal_layers()
    if not layers[1] then return false end
    local ok = pool_one(pos, h, layers[#layers])
    if layers[2] and not one then pool_one(pos, h * 0.7, layers[1]) end
    return ok
end
local function pool(pos, h, mesh, one)
    if stopped('blood.pool') or not pos then return false end
    return pool_z(pos, ground_z(mesh), h, one)
end

-- ---------- the vanilla SpawnDecal observer (a hook body: plain copies only, no IO, no raise out) ----------
local function on_vanilla(_, loc, _, _, bone, size, subuv, index)
    if not alive or st.ours then return end
    st.vn = st.vn + 1
    if #st.vq >= B.VANILLA_N then return end
    pcall(function()
        local p = xyz(loc)
        st.vq[#st.vq + 1] = { loc = p, bone = ue.str(ue.p(bone)), size = ue.p(size), subuv = ue.p(subuv),
            index = ue.p(index), t = now() }
    end)
end
local function hook_vanilla()
    st.hooked = true
    local r, err = LAB.armed('blood.hook', function()
        local ok, a, b = ue.register_hook(B.SAMPLER .. ':SpawnDecal', on_vanilla)
        if not ok then error(tostring(a), 0) end
        return { pre = a, post = b }
    end)
    LAB.rec('blood_hook', { ok = r ~= nil, err = err and tostring(err):sub(1, 160) or nil }, true)
end
local function drain_vanilla()
    if st.vn > 0 then
        LAB.count('blood_vanilla_decals', st.vn)
        st.vn = 0
    end
    if not st.vq[1] then return end
    local q = st.vq
    st.vq = {}
    for _, v in ipairs(q) do
        LAB.rec('blood_vanilla_decal', { bone = v.bone, size = r1(v.size), subuv = v.subuv, index = v.index,
            loc = v.loc and { x = r1(v.loc.x), y = r1(v.loc.y), z = r1(v.loc.z) } or nil })
        if num(v.size) and v.size > 0 and st.v_size == nil then st.v_size = clamp(v.size, B.SIZE_MIN, B.SIZE_MAX) end
        if math.type(v.subuv) == 'integer' and v.subuv >= 0 and v.subuv < 64 and st.v_subuv_n < 16 then
            local have = false
            for _, x in ipairs(st.v_subuv) do if x == v.subuv then have = true end end
            if not have then st.v_subuv_n = st.v_subuv_n + 1 st.v_subuv[st.v_subuv_n] = v.subuv end
        end
    end
end
-- The loop check: each probed spray read FX_PROBE_S after its spawn (IsActive; gone: auto-destroyed)
local function probe_step()
    if not st.probes[1] or now() < st.probes[1].due then return end
    local p = table.remove(st.probes, 1)
    local c = ue.live_mod(p.rec)
    local active = 'gone'
    if c then
        local v = LAB.hot('blood.read', function() return c:IsActive() end)
        active = type(v) == 'boolean' and v or 'unread'
    end
    LAB.rec('blood_fx_alive', { fx = p.fx, after_s = B.FX_PROBE_S, active = active })
end

-- ---------- hits, deaths, cuts (lab ticker) ----------
local function rec_bleed(kind, fields)
    if st.recs >= B.REC_N then return end
    st.recs = st.recs + 1
    fields.kind = kind
    LAB.rec('blood', fields)
end
-- A snapshot of a blocked blow (header, Hits): the defender's hit react strength, never on the victim's own attack
-- (no damage cause: Damage.Cause.Deflect rides on Soul's deflect counter)
local function block_snap(s)
    if s.owner_is_victim == true then return false end
    for _, f in ipairs(B.BLOCK_FIELDS) do
        local v = s[f]
        if type(v) == 'string' and v:find(B.BLOCK_STRENGTH, 1, true) then return true end
    end
    return false
end
-- lab_kill's newest block mark on the key and its tag (M.blocked; Lua only), else nil
local function block_mark(key)
    local K = package.loaded['lab_kill']
    if type(K) ~= 'table' or type(K.blocked) ~= 'function' then return nil end
    local t, tag = K.blocked(key)
    if num(t) then return t, tag end
    return nil
end
-- The damage, bone and direction of the snapshots since the victim's last bleed, not its own attacks (dmg false: none);
-- why, when no damage snapshot is left but one was dropped as a blocked blow (at or before BLOCK_S after the newest
-- block seen): by 'mark' (with lab_kill's tag) or 'strength', dt (the newest dropped snapshot after the block) and the
-- window's first attack type and hit react strength, for the blood record kind 'blocked'. B3.5: after why, the hit_loc
-- of the snapshot that gave the bone (never another's) and 'fine' (its HitBone) or 'coarse' (HitBodyData.bone)
local function blow_of(key, t)
    local since = st.seen_t[key] or (t - B.SNAP_BACK_S)
    local snaps = LAB.snaps(key, since) or {}
    local blk, tag = block_mark(key)
    local by = blk ~= nil and 'mark' or nil
    for _, s in ipairs(snaps) do
        local ts = s.t or 0
        if ts > since and block_snap(s) and (blk == nil or ts > blk) then blk, by = ts, 'strength' end
    end
    local dmg, bone, dir, newest, blocked, atk, str, hl, hlb = false, nil, nil, since, nil, nil, nil, nil, nil
    for _, s in ipairs(snaps) do
        if (s.t or 0) > since and s.owner_is_victim ~= true then
            if s.event == B.DAMAGE_EVENT or B.DAMAGE_KEYS[s.key] then
                if blk ~= nil and (s.t or 0) <= blk + B.BLOCK_S then blocked = s.t or 0 else dmg = true end
            end
            local b = s.bone or s.body_bone
            if b then bone, hl, hlb = b, s.hit_loc, s.bone and 'fine' or 'coarse' end
            dir = s.attack_dir or s.sweep_dir or dir
            atk = atk or s.attack_type or s.final_attack_type
            str = str or s.hit_strength or s.origin_strength or s.anim_strength
            if (s.t or 0) > newest then newest = s.t end
        end
    end
    if dmg or blocked == nil then return dmg, bone, dir, newest, nil, hl, hlb end
    return dmg, bone, dir, newest, { by = by, tag = by == 'mark' and tag or nil, dt = blocked - blk, attack_type = atk,
        strength = str }
end
-- The first BLOCK_REC_N blocked blows of a session (header, Records): what blocked each, so one lab log reads which
-- signal rides on a blocked blow and whether a landed hit was taken for one (its attack type and strength)
local function rec_blocked(class, why)
    if st.brecs >= B.BLOCK_REC_N then return end
    st.brecs = st.brecs + 1
    LAB.rec('blood', { kind = 'blocked', class = class, by = why.by, tag = why.tag,
        dt_ms = math.floor(why.dt * 1000 + 0.5), attack_type = why.attack_type, strength = why.strength })
end
-- fixes-0.2.2 B3.5 (D4; header, Records): one blood_hl from the bone spot this bleed read (pos) and the hit_loc of the
-- snapshot that named that bone; an unread or all-zero HitLocation (unfilled, as lab_poll's kill.hit_loc) writes none
local function rec_hl(class, bone, pos, hl, hlb)
    if st.hlrecs >= B.HL_N or type(hl) ~= 'table' or not (num(hl.x) and num(hl.y) and num(hl.z)) then return end
    if hl.x == 0 and hl.y == 0 and hl.z == 0 then return end
    st.hlrecs = st.hlrecs + 1
    local d = math.sqrt((hl.x - pos.x) ^ 2 + (hl.y - pos.y) ^ 2 + (hl.z - pos.z) ^ 2)
    LAB.rec('blood_hl', { class = class, bone = bone, hl_cm = math.floor(d + 0.5), hl_bone = hlb })
end
local function bleeds(key, class)
    if (st.pawn_key ~= nil and key == st.pawn_key) or (type(class) == 'string' and class:find('Player', 1, true)) then
        LAB.count('blood_skip_player')
        return false
    end
    if NO_BLOOD[class] then LAB.count('blood_skip_noblood') return false end
    return true
end
-- A key the game's slicer cut (lab_slice's sliced set; Lua only)
local function sliced(key)
    local SLC = package.loaded['lab_slice']
    return type(SLC) == 'table' and type(SLC.sliced) == 'function' and SLC.sliced(key) == true
end
local function do_hit(h)
    local rec = h.rec
    if not bleeds(rec.key, rec.class) then return end
    local t = now()
    if t - (st.last[rec.key] or -math.huge) < B.HIT_GAP_S then return end
    if t - st.hit_t < B.HIT_RATE_S then LAB.count('blood_skip_rate') return end
    local dmg, bone, dir, newest, why, hl, hlb = blow_of(rec.key, h.t)
    if not dmg then
        if why then                                     -- the blocked blow is used up: a later lab_hit skips it too
            st.seen_t[rec.key] = newest
            LAB.count('blood_skip_blocked')
            rec_blocked(rec.class, why)
        else
            LAB.count('blood_skip_nodamage')
        end
        return
    end
    st.seen_t[rec.key], st.last[rec.key], st.hit_t = newest, t, t
    local actor = LAB.alive(rec)
    if not actor then return end
    begin()
    local mesh = ue.get(actor, 'Mesh')
    LAB.linger('blood.read', LAB.HOT_LINGER_S)          -- its armed.json write before the timed read (review)
    local pos = step('read', bone_pos, mesh, bone)
    if not pos then bone, pos = nil, step('read', actor_pos, actor) end
    if not pos then return end
    if bone then rec_hl(rec.class, bone, pos, hl, hlb) end    -- B3.5: the bone spot only, never actor_pos's
    st.spot[rec.key] = { bone = bone }
    LAB.count('blood_hits')
    BUS.emit('lab_bleed', { kind = 'hit', pos = pos, dir = dir, class = rec.class, key = rec.key })
    local i = math.random(1, 4)
    local rot = rot_of(dir)
    local a = step('fx', spray, pick(B.FX.hit, i), pos, rot, B.HIT_SCALE)
    local b = step('fx', spray, pick(B.FX.body, i + 1), pos, rot, B.HIT_SCALE)
    local d = step('decal', decals, actor, rec.class, pos, bone, B.DECALS_PER_HIT)
    local ad = step('adecal', adecals, actor, rec.class, pos, bone, dir, st.k.ADECALS_PER_HIT)
    if not late(t) then
        step('pool', pool, pos, B.POOL_HIT, mesh, true)  -- a plain hit's pool: the stain alone (header, the decal queue)
        step('player', on_player, pos, st.k.PLAYER_HIT)
    end
    slow_check('hit', rec.class, t)
    rec_bleed('hit', { class = rec.class, bone = bone, fx = (a and 1 or 0) + (b and 1 or 0), decals = d, adecals = ad,
        dir = dir ~= nil })
end
local function do_death(dth)
    local key = dth.key
    if key == nil or not bleeds(key, dth.class) then return end
    local actor = LAB.alive(dth.keep or dth.obj)
    if not actor then return end
    local t0 = now()
    begin()
    local spot = st.spot[key]
    local bone = spot and spot.bone or nil
    local pos = bone and bone_pos(ue.get(actor, 'Mesh'), bone) or nil       -- the bone now, not where it was hit
    if not pos then bone, pos = nil, actor_pos(actor) end
    if not pos then return end
    LAB.count('blood_kills')
    BUS.emit('lab_bleed', { kind = 'kill', pos = pos, class = dth.class, key = key })
    local a = step('fx', spray, B.FX.kill[1], pos, ue.rot(0, 0, 0), B.KILL_SCALE)
    local d, ad
    -- a death bleed held behind hits until after the game's slicer cut this corpse: its Character.Mesh is the hidden
    -- source (no decal of it would show, its ground is the frozen source's); the slice bled on its halves
    local whole = not sliced(key)
    if whole then
        d = step('decal', decals, actor, dth.class, pos, bone, B.KILL_DECALS)
        ad = step('adecal', adecals, actor, dth.class, pos, bone, nil, st.k.ADECALS_KILL)
    end
    if not late(t0) then
        if whole then step('pool', pool, actor_pos(actor) or pos, B.POOL_KILL, ue.get(actor, 'Mesh')) end
        step('player', on_player, pos, st.k.PLAYER_KILL, true)
    end
    slow_check('kill', dth.class, t0)
    rec_bleed('kill', { class = dth.class, fx = a and 1 or 0, decals = d, adecals = ad })
end
local function do_cut(cut)
    local mesh = cut.leader
    local keep = ue.keep(cut.actor)
    local actor = keep and LAB.alive(keep) or nil
    if not (actor and ue.valid(mesh)) then return end
    local class = cut.victim and cut.victim.class or nil
    if NO_BLOOD[class] then LAB.count('blood_skip_noblood') return end
    local t0 = now()
    begin()
    local bone = cut.stump or cut.bone
    local pos = bone_pos(mesh, bone)
    if not pos then return end
    LAB.count('blood_cuts')
    local head = cut.row ~= 'limbs'
    local extra = type(cut.rank) == 'number' and cut.rank > 1     -- BD7: a later part of the same kill
    local g = type(cut.gib) == 'table' and cut.gib or {}
    BUS.emit('lab_bleed', { kind = head and 'head' or 'limb', pos = pos, mesh = mesh, bone = bone, keep = keep,
        class = class, extra = extra, at = g.at, joint = g.joint })
    local a = head and step('fx', spray, B.FX.head[1], pos, ue.rot(90, 0, 0), B.HEAD_SCALE) or false
    local d = step('decal', decals, actor, class, pos, bone, B.CUT_DECALS)
    local ad = step('adecal', adecals, actor, class, pos, bone, nil, st.k.ADECALS_CUT)
    if not late(t0) then
        if not extra then step('pool', pool, pos, B.POOL_CUT, mesh) end
        step('player', on_player, pos, extra and st.k.PLAYER_EXTRA or (head and st.k.PLAYER_HEAD or st.k.PLAYER_LIMB), true)
    end
    slow_check('cut', class, t0)
    if #st.spurts < B.SPURT_MAX then
        st.spurts[#st.spurts + 1] = { mesh = mesh, keep = keep, bone = bone, left = B.SPURTS, due = now(),
            fx = head and B.FX.stump[1] or B.FX.stump[2], class = class }
    end
    rec_bleed('cut', { class = class, part = cut.part, bone = bone, fx = a and 1 or 0, decals = d, adecals = ad,
        rank = extra and cut.rank or nil })
end
-- A slice's pulses (lab_blood_slice BS.slice queues them with e.slice) go to BS.pulse, a cut's to spurt; an entry whose
-- corpse (or, for a cut, its mesh) is gone is dropped
local function do_spurts(budget)
    if not st.spurts[1] then return budget end
    local t, keep = now(), {}
    for _, s in ipairs(st.spurts) do
        if budget > 0 and t >= s.due then
            if LAB.alive(s.keep) and (s.slice or ue.valid(s.mesh)) then
                if s.slice then
                    BS.pulse(s)
                else
                    spurt(s.fx, s.mesh, s.bone, B.STUMP_SCALE)
                    BUS.emit('lab_bleed', { kind = 'spurt', mesh = s.mesh, bone = s.bone, keep = s.keep,
                        class = s.class, pulse = B.SPURTS - s.left + 1 })
                end
                budget = budget - 1
                s.left, s.due = s.left - 1, t + B.SPURT_P
                if s.left > 0 then keep[#keep + 1] = s end
            end
        else
            keep[#keep + 1] = s
        end
    end
    st.spurts = keep
    return budget
end

-- A ring over its (lowered) cap: the oldest destroyed, at most TRIM_PER_FRAME a frame over the three rings (pring holds
-- two layers per splash)
local function trim()
    local left = B.TRIM_PER_FRAME
    for _, r in ipairs({ { st.adecal_ring, st.k.ADECALS_MAX }, { st.pools, st.k.POOLS_MAX },
        { st.pring, st.k.PLAYER_MAX * 2 } }) do
        while left > 0 and #r[1] > r[2] do
            evict(table.remove(r[1], 1))
            left = left - 1
        end
    end
end

local function tick()
    if not st.init or st.ended then return end
    if st.first then
        st.first = false
        if st.observe then hook_vanilla() end           -- the beta registers no observer (S6)
    end
    drain_vanilla()
    if LAB.ended() then st.ended = true return end
    GREY.step()                                         -- the grey console jobs (lab_grey): also paused and off
    if st.warmq[1] then warm_step() elseif st.rewarmq[1] then QL.rewarm_step() end   -- one load a frame
    probe_step()
    if LAB.paused() then return end
    WS.step()                                           -- before the gate: the wash runs while off too (header)
    recv_poll()                                         -- a body whose ring went: its parts back, also while off
    if not MODOFF.enabled('lab_blood') or not blood_on() then
        if st.hitq[1] or st.deathq[1] or st.cutq[1] or st.sliceq[1] or st.spurts[1] then   -- no garbage while idle
            st.hitq, st.deathq, st.cutq, st.sliceq, st.spurts = {}, {}, {}, {}, {}
        end
        if st.dq[1] then QL.clear() end                 -- each queued stain off its key's count (stains_out)
        return
    end
    tune()
    trim()
    st.dbudget, st.sbudget = B.DECALS_PER_FRAME, B.SETUPS_PER_FRAME
    local budget = B.PER_FRAME
    local f0 = now()                                    -- the lag guard: no new bleed past FRAME_MS this frame
    local function room() return (now() - f0) * 1000 < B.FRAME_MS end
    while budget > 0 and st.cutq[1] and room() do
        do_cut(table.remove(st.cutq, 1))
        budget = budget - 2
    end
    while budget > 0 and st.sliceq[1] and room() do
        BS.slice(table.remove(st.sliceq, 1))
        budget = budget - 2
    end
    while budget > 0 and st.hitq[1] and room() do       -- hits first: a one-blow kill's death reads the hit's bone
        do_hit(table.remove(st.hitq, 1))
        budget = budget - 2
    end
    while budget > 0 and st.deathq[1] and not st.hitq[1] and room() do
        do_death(table.remove(st.deathq, 1))
        budget = budget - 1
    end
    do_spurts(math.max(budget, 1))
    QL.drain()                                          -- the decal queue (lab_blood_queue): this tick's first spawns
end
local function queue(q, v)                              -- listeners only queue
    if v == nil or not st.init or st.ended then return end
    if #q >= B.QMAX then st.qdrop = st.qdrop + 1 return end
    q[#q + 1] = v
end
local EVENTS = { 'lab_hit', 'lab_death', 'lab_cut_live', 'lab_slice_live', 'lab_pawn', 'lab_end' }

B.layer = QL.layer                  -- a decal layer for lab_cap's ring and lab_drops' stains (lab_blood_queue)
-- lab_cap's wound ring (its dress, after make_ring): a decal on the victim's leader that draws only while the leader
-- receives decals, kept as the Cap's own (rec: its keep record, never in this module's ring). While it lives, recv_off
-- leaves the actor's switched parts on (header, B4). true when pinned
function B.recv_pin(actor, rec)
    if not st.init or type(rec) ~= 'table' then return false end
    local key = ue.addr(actor)
    if key == nil then return false end
    local p = st.recv_pin[key] or {}
    p[#p + 1] = rec
    st.recv_pin[key] = p
    return true
end

-- ---------- lifecycle ----------
function B.init(adapter)
    A = adapter
    st = new_state()
    QL.bind({ B = B, state = function() return st end, now = now, gnow = gnow, xyz = xyz, failed = failed,
        worked = worked, stopped = stopped, evict = evict, stains_out = stains_out })
    WS.bind({ B = B, state = function() return st end, now = now, stopped = stopped, failed = failed, worked = worked,
        recv_off = recv_off })
    if not LAB.cut_set() then return true end
    st.init, alive = true, true
    local beta = LAB.beta()
    st.skinned, st.observe, st.fx_probe = not beta, not beta, not beta
    tune()
    MODOFF.feature('lab_blood', { gameplay = true })    -- the vanilla compare stops new blood, as mod-off does (S6)
    for _, k in ipairs(B.COUNTERS) do LAB.count(k, 0) end
    BUS.on('lab_hit', 'lab_blood', function(rec, t)
        if type(rec) == 'table' and rec.key ~= nil then queue(st.hitq, { rec = rec, t = tonumber(t) or now() }) end
    end)
    BUS.on('lab_death', 'lab_blood', function(d) if type(d) == 'table' then queue(st.deathq, d) end end)
    BUS.on('lab_cut_live', 'lab_blood', function(cut) if type(cut) == 'table' then queue(st.cutq, cut) end end)
    BUS.on('lab_slice_live', 'lab_blood', function(s)
        if type(s) == 'table' and s.kind == 'slice' then queue(st.sliceq, s) end
    end)
    BUS.on('lab_pawn', 'lab_blood', function(rec)
        if type(rec) ~= 'table' then return end
        if rec.key == nil or rec.key ~= st.pawn_key then st.heal = new_heal() end   -- a new pawn starts disarmed
        st.pawn_key, st.pawn = rec.key, rec.pawn
    end)
    BUS.on('lab_end', 'lab_blood', function() st.ended = true end)
    GREY.bind({                                         -- the grey A/B (lab_grey.lua header): lab_blood's own helpers
        verb = adapter and adapter.verb, ended = function() return st.ended end,
        pawn = function() return st.pawn and ue.live(st.pawn) or nil end,
        rings = function() return { st.pring, st.adecal_ring, st.pools } end,
        mark_recv = function(pawn)                      -- the console owns his flag now: no switch back (B4)
            local k = ue.addr(pawn)
            if k then st.recv[k], st.recv_parts[k] = true, nil end
        end,
        bone_pos = bone_pos, xyz = xyz, name_of = name_of, now = now, stopped = stopped, failed = failed,
        worked = worked, texture = texture_any, blood_on = blood_on, B = B,
        ours = function(v) st.ours = v == true end,
    })
    BS.bind({                                           -- the bleed of a slice (lab_blood_slice.lua header)
        B = B, state = function() return st end, stopped = stopped, failed = failed, worked = worked, xyz = xyz,
        system = system, spray = spray, attach_fx = attach_fx, step = step, slow_check = slow_check, begin = begin,
        rec_bleed = rec_bleed, bleeds = bleeds, ground_z = ground_z, face_of = face_of, adecal_layers = adecal_layers,
        adecal = adecal, pool_z = pool_z, on_player = on_player, now = now, late = late,
    })
    S.ticker('lab_blood', tick)
    return true
end
-- After a map load (main.lua's staggered warm-up): every system queued; the ticker resolves one a frame
function B.warm()
    if not st.init or st.ended then return end
    st.warmq, st.got, st.miss = {}, {}, {}
    for _, key in ipairs({ 'hit', 'body', 'kill', 'head', 'stump' }) do
        for _, path in ipairs(B.FX[key]) do st.warmq[#st.warmq + 1] = path end
    end
    if st.skinned then for _, pair in ipairs(B.LOOK) do st.warmq[#st.warmq + 1] = pair[2] end end
    for _, path in ipairs(B.ADECAL_MATS) do st.warmq[#st.warmq + 1] = path end
    st.rewarm, st.rewarmq = {}, {}                      -- the warm resolves every path again
end
-- A map load: queues (the decal queue too), caches, the breaker, the lag guard's switch-offs and levels (its warm-up
-- counts stay: a session's), the reloads, the held layers (their keeper went with the map) and the player's key go
-- with the old map (no engine call); a revive wash, a heal fade, a face wash and a life batch still open write their
-- records (lab_blood_wash, cut 'map'; Soul's splashes go with the old world) and the heal state starts disarmed
function B.reset()
    if not st.init then return end
    WS.reset()
    st.hitq, st.deathq, st.cutq, st.sliceq, st.spurts, st.probes = {}, {}, {}, {}, {}, {}
    st.last, st.seen_t, st.spot, st.samplers, st.missing = {}, {}, {}, {}, {}
    st.fails, st.off, st.pawn_key, st.pawn = {}, {}, nil, nil
    st.recv, st.adecal_n, st.adecal_ring, st.pools, st.pring = {}, {}, {}, {}, {}
    st.recv_parts, st.adecal_live, st.soul_key, st.soul_t = {}, {}, nil, nil   -- the parts went with the old world
    st.adecal_q, st.recv_pin, st.recv_wait = {}, {}, {}
    st.dq, st.rewarm, st.rewarmq, st.held, st.pbones = {}, {}, {}, {}, nil
    st.step_off, st.step_lvl, st.step_hard, st.step_slow = {}, {}, {}, {}
    st.heal = new_heal()
    GREY.reset()
end
function B.status()
    local off, steps_off = {}, {}
    for k in pairs(st.off) do off[#off + 1] = k end
    table.sort(off)
    for k, at in pairs(st.step_off) do if at > now() then steps_off[k] = st.step_lvl[k] or 0 end end
    local held, washing, fading, face_washing = 0, WS.status()
    for _, h in pairs(st.held) do if h.ep == ue.epoch then held = held + 1 end end
    return { init = st.init, ended = st.ended, hooked = st.hooked, spurts = #st.spurts, qdrop = st.qdrop,
        spawned = st.spawned, v_size = st.v_size, v_subuv = st.v_subuv_n, off = off, pawn = st.pawn_key ~= nil,
        err = st.err, amount = st.d, skinned = st.skinned, splashes = #st.pring, heal_armed = st.heal.armed,
        washing = washing, fading = fading,
        life_batch = st.life ~= nil, soul_off = st.soul_off or nil, face_off = st.face_off or nil,
        face_washing = face_washing, queued = #st.dq, layers = st.layers_key,
        steps_off = next(steps_off) and steps_off or nil, reloads = #st.rewarmq, held = held }
end
-- Engine-free (Ctrl+R runs it off the game thread): the hook stays registered and returns at once (alive false)
function B.shutdown()
    alive = false
    S.remove_ticker('lab_blood')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_blood') end
    GREY.shutdown()
    st, A = new_state(), nil
end

return B
