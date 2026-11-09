-- status: new in M0 S2.11 (offline only; TC-LAB-01 stage 0 decides) origin: kb:runtime-safety-perf#phase-scheduler-with-hook-inbox
-- lab_kill.lua: TC-LAB-01 stage 0 hook consumers and tallies (spec M0 S2.11, section 3.1, D5, D10, D29). Probe and dev
-- builds only (META.lab_modules); it uses the lab_probe API (section 3.5) and never writes a record from a hook body.
-- * One optional consumer (feature 'lab') per id of data/hooks.lua, on one side (SIDE: the hooks.json 'when', post by
--   default; a Blueprint hook has only post): a missing or failing hook never sets MAIN.disabled (D5). Observe only:
--   no argument write, no skip, the callback returns nothing (a native hook's return would replace the result).
-- * Two timed parts per fire (D10: means over many fires, os.clock steps 1 ms, each part rounded to the microsecond):
--   the minimal path (params unwrapped, the victim by the id's ROUTE and its registry key through LAB.victim,
--   LAB.count('hook_fires'), a timestamp) and the copy (plain values into a fresh table: the victim class, every
--   param's class or type through built-ins, and from the payload structs and payload objects HitBone,
--   HitBodyData.bone, HitBody.SocketName, AttackDirection and SweepDirection as {x,y,z}, the DamageCause tag, the
--   DamageSource class, the AttackType and FinalAttackType tags, the killer's class; HitLocation as {x,y,z} into
--   hit_loc, spec fixes-0.2.2 B3.4, D4: logged, never a part choice) into LAB.snap_push and the ticker queue. The
--   payload reads run unguarded inside the hook body by design (D29) and stay within the S1.10 field kinds: FName
--   and FVector fields of a struct param, UObject fields and params named by class through IsValid, GetClass and
--   GetFName, properties of a param object. Nothing but IsValid is asked of an object that answers IsValid false (a
--   null object param: a method on it is a native fault). Empty or 'None' bones, tags and classes are omitted: the
--   analyzer compares case-sensitively, so a logged 'None' would count as present.
-- * A struct param arrives from :get() as a UScriptStruct userdata that answers IsValid true, GetClass ScriptStruct and
--   GetFName its struct type (UE4SS cdbc0b66 LuaUScriptStruct.cpp:73-114, LuaUScriptStruct.hpp:16-19; review
--   RUNTIME-1): it reads 'struct:<type>' (a plain table, the mock's shape, reads 'struct') and is a payload.
-- * Killer (killer_src, review SEAMS-3): GameplayEventData.Instigator ('event'), else the DamageSource actor's
--   Instigator ('damage_source') or Owner ('owner') property (usmap_props.tsv:92, :78), else 'none'; a Controller
--   stands for its Pawn (:5641), a PlayerState for its PawnPrivate (:7618), and an actor that is no Pawn (a weapon, a
--   projectile) for its own Instigator, else its Owner, when that IsA Pawn ('owner_hop', checks:b, d). by_player
--   compares the killer's address and object name with the lab pawn's (ClientRestart's NewPawn or bus lab_pawn), never
--   a class name; absent before any lab pawn (lab_poll then compares class names). source_seen (true or absent): the
--   payloads read carried a valid Instigator or DamageSource object, so lab_poll can tell a kill with no source at all
--   (an environment death, killer_src 'no_source') from one whose source went unread.
-- * No member read probes a UObject for a field it may lack before L0i-lite proved the lookup (reviews RUNTIME-2,
--   PASSIVE-2: on UE4SS such a miss walks GetFunctionByNameInChain, the inherited lookup L0i-lite proves first): an
--   actor is the built-in IsA against /Script/Engine.Actor (Pawn, Controller and PlayerState likewise), each class
--   resolved by ue.class on the lab ticker, never in a hook body. Until then is_a answers nil: no fire names a victim,
--   and a killer is the source object itself (no Controller, PlayerState or weapon hop). Struct params are always
--   payloads: a struct miss raises (LuaUScriptStruct.cpp:176-185) and walks nothing. Payload objects (a valid
--   GameplayEventData.OptionalObject, an object param whose class names a Payload) are read only while LAB.l0i_ok()
--   (L0i-lite returned 2 of 2; false again after a stop) and LAB.inherit_ok(); before that each one is left unread and
--   counted (payload_skipped: the snapshot, hook_fire, counter and status).
-- * Field sets (spec M1a 4.0 Cost, M0 D29; the per-hit lag of session 20261030-215812: 4.3 ms per hook call from
--   trial reads, each missing struct member a C++ exception through UE4SS): a hook body asks a struct or a payload
--   object only for a member its type declares. Types are keyed by short name (a struct's GetFName, an object's class
--   name); the lab ticker learns each one once through ue.fields (one ForEachProperty pass per class of its
--   GetSuperStruct chain) under 'probe.meta' and keeps the answer, a negative one too, for the session (a map load
--   keeps them). M.PRIME (the payload types of F) is learned on the first tick; any other type a hook body meets is
--   queued with its path (GetFullName, once per type) and left unread on that fire (the fire still counts, its known
--   fields are copied). A plain Lua table (the mock's struct shape) declares its own keys. A GameplayTag is read only
--   for TagName. Counters field_queued, field_cached and trial_reads (a member asked of a type not learned, refused,
--   or a member read that raised inside a hook body: 0 by design) start with the first hook fire.
-- * No raise in a hook body (review check P0 of the perf fix: each raise is a C++ throw on UE4SS, whose Lua is built as
--   C++, LuaRaw CMakeLists.txt:51, ldo.c:58; about 300 us each [inferred from hook_tally]): a declared member is read
--   by a raw index, and IsValid is asked only of a value whose plain index answers it. An FName, FString or FText
--   userdata has no IsValid and no index callback, so that index answers nil there (LuaFName.cpp:119-150,
--   LuaMadeSimple.cpp:541-580) where ue.prop's probe would raise. Counter hook_raises: every error caught inside a
--   hook body (0 by design; trial_reads is its member-read part).
-- * Kinds: a struct param's type is fixed by its UFunction, so its kind is cached per id and param index; a struct
--   held in a declared field likewise per type and field. An object's class is read on every fire.
-- * The OnGameplayEventReceived hooks (h04, h20: every gameplay event, 10-15 per hit) read the EventTag first (h04 its
--   GameplayTag param, h20 its GameplayEventData's EventTag, then TagName) and return unless it is in M.EVENTS: such
--   a fire counts in hook_fires, hook_calls and event_skipped plus event_skip_<tag> (dots as '_', the first SKIP_TAGS
--   tags, then event_skip_other; 'unread' while a type is not learned, 'none' when no param carries one); it writes no
--   snapshot, so hook_tally counts their damage, kill and hit-react fires only. M.EVENTS holds the hit-react events:
--   in session 20261030-215812 every HitBone, HitBodyData.bone and attack type came through them (h11 never fired).
--   The snapshot carries the tag (event). h04 and h20 fire in pairs on one event (hook_tally 785/785): the second fire
--   of the same victim, tag and OptionalObject address in the same tick takes the first one's payload fields
--   (counter payload_reused) instead of copying them again.
-- * Block marks (bug B2, Nexus 178914750: «a blood effect is still triggered when I hit an opponent's block»): a
--   skipped fire whose tag is a defender's block event (M.BLOCKS: Deflect Consume, Defender.Normal, Defender.Perfect;
--   exe strings, death-pipeline/exe_dotted.tsv:1168, :10140-10141) also names its victim (the AI route) and keeps the
--   fire time and the tag per victim key, no payload read and no snapshot (counter block_marks); M.blocked(key) reads
--   them for lab_blood's hit bleed (its blood record kind 'blocked' names the tag). A map load drops them. Which of
--   these events rides on a blocked blow is unread (no log of one yet): the mark takes all three.
-- * Sharp and blunt: the attack data map sits behind the GetAttackData UFunctions (a TMap, not a D29 field kind) and
--   no plain payload field carries them (usmap_props.tsv: 0 Sharp or Blunt fields; HitBone found by the same grep),
--   so hook_fire logs both 'unread'.
-- * The beta's kill tier reads (docs/research/beta-dismemberment-plan.md BD3, research H1 and H2), only once the beta's
--   pin check passed (LAB.pinned() true: an unknown build reads nothing new; the probe and dev profiles never): the
--   strength tags of the payloads already read (Pre HitStrength, Post OriginStrength, StrengthAnimStrength and
--   HitState, by TagName: hit_strength, origin_strength, anim_strength, hit_state), and the bullet hop on a payload's
--   DamageSource whose class declares BulletData (PBZ_BulletAttackModule and its Scaled variant, M.PRIME_BETA, primed
--   once the pin check answered, either way): BulletData and LastOwnerAvatar (owner_is_pawn: its address against the
--   lab pawn's; owner_is_victim: against the hook's victim, true on an attacker's own Damage.Taken, which lab_blood
--   takes as no blow on it: item 178860405, session 20261102-f93cf2f log.a.jsonl:483-485; counter bullet_own_attack).
--   The owner test alone needs no pin (R4, intake 2026-11-03: on another UE4SS or game build the enemies bled from
--   their own attacks again): in every beta session it runs wherever payload objects are read (L0i-lite 2 of 2, the
--   same gate as the DamageSource read), one LastOwnerAvatar member read of a primed module type (no DamageSource
--   class is learned on sight without the pin); owner_is_pawn, the strength tags and the asset labels stay pinned.
--   The bullet data asset's
--   labels are read once per address and map (cache of M.BULLETS; a Blueprint bullet-data class is learned on sight,
--   its first hit left unread, counter bullet_unread): SkillType, HitStrength, AttackDirection (tags), OriginType (the
--   EPBZAttachedBulletOrigin name), its FName and folder (bullet, bullet_dir, skill_type, bd_strength, bd_dir,
--   bd_origin); a later hit on the same asset reads nothing beyond BulletData and LastOwnerAvatar. Each snapshot gets
--   seq (a per-session counter: the order of one frame's events in hook_fire). One bullet_seen record per asset name
--   (M.BULLET_SEEN, the cap), queued by the hook body and written by the ticker; status() adds tier, bullets and
--   bullet_seen. No UFunction, no trial read.
-- * The Akasha slicer hooks h13, h25 and h26 (docs/research/slicer-stumps.md, skeptic integrate) and the game-slice
--   observers h27-h32 (lab_slice_watch, the test build's own consumer): the beta declares no consumer for them here (no
--   beta module reads their snapshots; lab_tl, the one reader, is dev-only), so the player zip registers none and no
--   dispatch of ours runs nested inside lab_slice's own slicer call. Any profile that declares them returns at the
--   consumer's first line while lab_slice's self_call() reads true (counted in self_slices).
-- * client_restart: its NewPawn as a ue.keep record through LAB.post; the lab ticker emits bus lab_pawn {pawn, key, t}.
-- * The lab ticker (never a hook body): hook_fire for the first FIRST_N fires per id and for every fire within
--   BEFORE_S before a confirmed death (bus lab_death); each death settles SETTLE_S after it (a late hook such as a
--   ragdoll notify still counts); hook_tally per id on bus lab_flush, cumulative for the session.
-- * Tallies: per non-execution death and id, n = the fires that named the victim during its life plus the fires of
--   that id that named no victim within JOIN_S of the death (each joined to one death, the earliest settled first):
--   zero, once or multi; resolved when at least one fire named the victim. A death is an execution when an h12 or h24
--   fire named the victim within EXEC_S before it (or its kill record says execution): it counts in exec_deaths only.
--   once_all = once == deaths == resolved and deaths >= ONCE_MIN.
-- * Gauges (section 3.2): hook_us_mean (hooks.lua's whole dispatch per call, every consumer), hook_us_mean_min and
--   hook_us_mean_copy (the two parts here; a skipped event fire is all minimal path), hook_calls (the fires timed
--   here), hook_n_ge_1ms (hooks.lua) and hook_share_ge_1ms (n_ge_1ms over hooks.lua's calls, 4 decimals); counter
--   hook_fires. A gauge reads nil (absent) before the first fire.
-- * Bus lab_hit(rec, t, key) from the lab ticker, once per victim and tick (its newest fire): the registry record of
--   a victim a hook named, so lab_poll admits the victims seen in hook params (S2.12); listeners only queue.
-- API: init(A, opts) shutdown status reset; seen() -> the registry records of the victims hook params named this map
--   (the same set lab_hit carries, for a pull); types() -> the learned types { [type] = declared fields | false };
--   blocked(key) -> the victim's newest block mark time and its tag, or nil.
-- What the mock cannot prove: the payload types and param order on PBZ (the E0b dump), hook order and timing, native
--   faults inside the unguarded payload reads (D29: hook_first and hook_fire are the attribution), real costs.
local LAB = require('lab_probe')
local BUS = require('core.bus')
local S = require('core.sched')
local ue = require('adapter.ue')
local HDATA = require('data.hooks')

local M = { FEATURE = 'lab', FIRST_N = 3, BEFORE_S = 0.5, SETTLE_S = 2.0, JOIN_S = 0.5, EXEC_S = 15, OUTER_HOPS = 3,
    QMAX = 1024, LOOSE = 256, SEEN = 1024, ONCE_MIN = 10, TALLY_CAP = 1950, clock = os.clock }
-- The classes the hook bodies test with the built-in IsA (native /Script classes: loaded for the whole process)
M.CLS = { actor = '/Script/Engine.Actor', pawn = '/Script/Engine.Pawn', controller = '/Script/Engine.Controller',
    player_state = '/Script/Engine.PlayerState' }
-- The links from a weapon or projectile to its wielder, in order (wielder)
M.HOP = { 'Instigator', 'Owner' }
-- The class names of a struct param's UScriptStruct userdata (a Blueprint struct: UserDefinedStruct [inferred])
local STRUCT_CLASS = { ScriptStruct = true, UserDefinedStruct = true }
-- The gameplay events the card reads (TC-LAB-01 L0p, the kill contract): damage, kill and the victim's hit-react
-- events (the struck bone and the attack types: exe strings, death-pipeline/exe_dotted.tsv:1095, :1097). An
-- OnGameplayEventReceived fire with any other EventTag returns after that one read (data: add a tag to copy its fires)
M.EVENTS = { ['GameplayEvent.Damage.Taken'] = true, ['GameplayEvent.Actor.Killed'] = true,
    ['GameplayEvent.Hitreact.PreTakeHit.Target'] = true, ['GameplayEvent.Hitreact.PostTakeHit.Target'] = true }
-- The defender's block events (bug B2, header): skipped as any other tag, and each marks its victim (M.blocked). Not
-- the Frame.Deflect.Defender event: about one per landed hit (session 20261101-lag-final log.b.jsonl:1793), a window
-- check, not a block. BLOCKS_MAX: the marks a map keeps (a full table starts again)
M.BLOCKS = { ['GameplayEvent.Ability.Action.Deflect.Consume.Deflect.Defender'] = true,
    ['GameplayEvent.Ability.Action.Deflect.Defender.Normal'] = true,
    ['GameplayEvent.Ability.Action.Deflect.Defender.Perfect'] = true }
M.BLOCKS_MAX = 1024
-- The snapshot fields a payload copy writes (the second fire of one event takes them from the first); the beta's tier
-- fields (BD3) after by_player
M.PAY = { 'bone', 'body_bone', 'socket', 'attack_dir', 'sweep_dir', 'hit_loc', 'cause', 'source_class',
    'attack_type', 'final_attack_type', 'source_seen', 'killer', 'killer_src', 'by_player', 'hit_strength',
    'origin_strength', 'anim_strength', 'hit_state', 'bullet', 'bullet_dir', 'skill_type', 'bd_strength', 'bd_dir',
    'bd_origin', 'owner_is_pawn', 'owner_is_victim' }
M.EVENT_FN, M.OBJECT_PATH = ':OnGameplayEventReceived', '/Script/CoreUObject.Object'
-- Type cache bounds: types per session, field passes per tick, GetSuperStruct links per type, tag counters
M.TYPES_MAX, M.TYPES_TICK, M.SUPER_MAX, M.SKIP_TAGS = 256, 8, 8, 32
-- The payload types copy_payload reads, learned on the first lab tick (each path is an F declaring path below). A
-- primed path that finds nothing is forgotten, not cached: the type is then learned on sight from its GetFullName
M.PRIME = { '/Script/SGameAttributes.DamageTakenPayload', '/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload',
    '/Script/SGameCombatSystem.HitreactPreTakeHitEventPayload', '/Script/SGameCombatSystem.HitReactBodyData',
    '/Script/SGameUtils.ComponentSocket', '/Script/GameplayTags.GameplayTag',
    '/Script/GameplayAbilities.GameplayEventData', '/Script/CoreUObject.Vector' }
-- The beta's bullet hop (BD3): the DamageSource module types, primed once the pin check passed (header); the bullet
-- data asset cache per map, the bullet_seen cap per session; OriginType's names (EPBZAttachedBulletOrigin, the dump)
M.PRIME_BETA = { '/Script/PBZCombatAsset.PBZ_BulletAttackModule',
    '/Script/PBZCombatAsset.PBZ_ScaledBulletAttackModule' }
M.BULLETS, M.BULLET_SEEN = 512, 300
M.ORIGIN = { [0] = 'SourceAvatar', 'MainWeapon', 'ShachiWeapon', 'InteractWeapon', 'ParentBullet', 'TargetBody' }

-- The side each native hook is consumed on (hooks.json 'when'); every other id: post
local SIDE = { h02 = 'pre', h07 = 'pre', h09 = 'pre', h11 = 'pre', h18 = 'pre' }
-- Where a hook's victim is (hooks.json params): 'ctx' = the hook's object or one of its outers (the character, a
-- component), 'ai' = the Pawn property of the hook's AIScript or SGameAIComponent (usmap_props.tsv:15070, :15242),
-- never their outers: the SGameAIComponent is a subobject of the SGameAIController (script_objects_all.txt:57143),
-- an actor with its own root (TransformComponent0, :57145), so the outer walk named the controller; 'task' = the
-- actor of the AbilityTask's Ability field (usmap_props.tsv:10013; an ability instance's outer is its owner actor
-- [inferred], a task's own outer need not be), else the task's own outers; 'pawn' = client_restart (never a
-- victim); every other id 'param' = the first object param that is an actor or has one among its outers
local ROUTE = { client_restart = 'pawn', h02 = 'ctx', h04 = 'ai', h05 = 'ai', h06 = 'ai', h07 = 'ctx', h08 = 'task',
    h09 = 'ai', h11 = 'ctx', h17 = 'ctx', h19 = 'ai', h20 = 'ai', h21 = 'ai', h22 = 'ctx' }
-- The execution hooks: a death whose victim one of them named is an execution death
local EXEC = { h12 = true, h24 = true }
-- The Akasha slicer hooks (h13 Slice, h25 SlicePrepared, h26 WithDebugReport; lab_slice_watch's h27 Prepare, h28
-- Capture, h29 Release, h30 Restore, h31 and h32 GAAction_SliceSkeleton_C): not declared in the beta (header)
local SLICE_IDS = { h13 = true, h25 = true, h26 = true, h27 = true, h28 = true, h29 = true, h30 = true, h31 = true,
    h32 = true }
M.SIDE, M.ROUTE, M.EXEC, M.SLICE_IDS = SIDE, ROUTE, EXEC, SLICE_IDS
-- lab_slice's self-call flag: true only while its own slice call runs (no IO, no engine touch: a hook body asks it)
local function self_slicing()
    local SLC = package.loaded['lab_slice']
    return type(SLC) == 'table' and type(SLC.self_call) == 'function' and SLC.self_call() == true
end

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes). It calls
-- no UFunction (the hooks are session_pbz's 'hook.<id>' names); the fields are the payload fields of usmap_props.tsv
-- 15770-15776, 16562-16581, 47713, 30953, 30357, 30493-30495, the AI Pawn fields 15070, 15242, AbilityTask.Ability
-- 10013 and the killer links 92, 78, 5641, 7618, declaring paths from script_objects.tsv; the beta's strength tags and
-- bullet hop (BD3) from the build's UE4SS_ObjectDump (the Pre and Post payloads, BulletAttackModule,
-- PBZ_DamageBulletDataBase, PBZ_SweepTraceBulletData); the three HitLocation FVectors (fixes-0.2.2 B3.4) from
-- data/dumps/26266538/UE4SS_ObjectDump.txt:60262, :63085, :63095
local N = {}
local F = {
    {"/Script/SGameAttributes.DamageTakenPayload", "HitBody"},
    {"/Script/SGameAttributes.DamageTakenPayload", "AttackDirection"},
    {"/Script/SGameAttributes.DamageTakenPayload", "SweepDirection"},
    {"/Script/SGameAttributes.DamageTakenPayload", "DamageCause"},
    {"/Script/SGameAttributes.DamageTakenPayload", "DamageSource"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "HitBone"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "HitBodyData"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "FinalAttackType"},
    {"/Script/SGameCombatSystem.HitreactPreTakeHitEventPayload", "AttackType"},
    {"/Script/SGameCombatSystem.HitReactBodyData", "bone"},
    {"/Script/SGameUtils.ComponentSocket", "SocketName"},
    {"/Script/GameplayTags.GameplayTag", "TagName"},
    {"/Script/GameplayAbilities.GameplayEventData", "Instigator"},
    {"/Script/GameplayAbilities.GameplayEventData", "OptionalObject"},
    {"/Script/GameplayAbilities.GameplayEventData", "EventTag"},
    {"/Script/CoreUObject.Vector", "X"},
    {"/Script/CoreUObject.Vector", "Y"},
    {"/Script/CoreUObject.Vector", "Z"},
    {"/Script/SGameAI.AIScript", "Pawn"},
    {"/Script/SGameAI.SGameAIComponent", "Pawn"},
    {"/Script/GameplayAbilities.AbilityTask", "Ability"},
    {"/Script/Engine.Actor", "Instigator"},
    {"/Script/Engine.Actor", "Owner"},
    {"/Script/Engine.Controller", "Pawn"},
    {"/Script/Engine.PlayerState", "PawnPrivate"},
    {"/Script/SGameCombatSystem.HitreactPreTakeHitEventPayload", "HitStrength"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "OriginStrength"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "StrengthAnimStrength"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "HitState"},
    {"/Script/SGameCombatSystem.BulletAttackModule", "BulletData"},
    {"/Script/SGameCombatSystem.BulletAttackModule", "LastOwnerAvatar"},
    {"/Script/PBZCombatAsset.PBZ_DamageBulletDataBase", "SkillType"},
    {"/Script/PBZCombatAsset.PBZ_DamageBulletDataBase", "HitStrength"},
    {"/Script/PBZCombatAsset.PBZ_DamageBulletDataBase", "AttackDirection"},
    {"/Script/PBZCombatAsset.PBZ_SweepTraceBulletData", "OriginType"},
    {"/Script/SGameAttributes.DamageTakenPayload", "HitLocation"},
    {"/Script/SGameCombatSystem.HitreactPostTakeHitEventPayload", "HitLocation"},
    {"/Script/SGameCombatSystem.HitreactPreTakeHitEventPayload", "HitLocation"},
}
M.N, M.F = N, F

local A = nil
local st = {}
local function new_state()
    return { ids = {}, n = 0, min_ms = 0, copy_ms = 0, q = {}, qdrop = 0, dq = {}, fq = {}, tally = {}, cur = {},
        exec_at = {}, loose = {}, pending = {}, deaths = 0, exec_deaths = 0, seen = {}, nseen = 0, cls = {},
        pawn = nil, pawn_in = nil, pay_skip = 0, ev = {},
        types = {}, ntypes = 0, tq = {}, tpend = {}, depth = 0, trials = 0, early = {}, seeded = false,
        skip_key = {}, nskip_keys = 0, skipped = 0, pk = {}, nk = {}, raises = 0, reused = 0, ticks = 0,
        dup_key = nil, dup_tick = nil, dup_snap = nil, blocks = {}, btags = {}, nblocks = 0,
        -- the beta's tier reads (BD3): tier nil until the pin check answered, then true (read) or false
        beta = false, tier = nil, seq = 0, bullets = {}, nbullets = 0, bseen = {}, nbseen = 0, bq = {},
        written = setmetatable({}, { __mode = 'k' }), claimed = setmetatable({}, { __mode = 'k' }) }
end
st = new_state()

local function now() return A and A.clock.real() or 0 end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function ms(dt) return math.floor(dt * 1e6 + 0.5) / 1000 end      -- rounded to the microsecond (hooks.lua)

-- ---------- hook body helpers: built-ins and property reads only, never a UFunction (D29) ----------
-- A raw pcall's results passed through; a failure's text goes to ue.caught (helper 'lab_kill.<site>'), as ue.lua's
-- read helpers hand theirs, so an ArrayNum text raised here reaches lab_probe's stop rule (check:a; ue.caught only
-- keeps the text and calls the ue.on_error callbacks, no IO: safe in a hook body). Skipped on a bridge without it
local function caught(helper, key, ok, ...)
    if not ok and type(ue.caught) == 'function' then ue.caught((...), 'lab_kill.' .. helper, key) end
    return ok, ...
end
-- IsValid without a raise (header): nil for a value that is no object or whose plain index has no IsValid (an FName,
-- FString or FText userdata: no index callback, so the index answers nil; ue.valid's call would raise there), else
-- the answer (nil when it raised)
local function answers(v)
    local t = type(v)
    if t ~= 'userdata' and (t ~= 'table' or rawget(v, '__mock') ~= true) then return nil end
    local f = v.IsValid
    if f == nil then return nil end
    local ok, r = caught('valid', nil, pcall(f, v))
    if not ok then return nil end
    return r == true
end
local function valid(o) return answers(o) == true end
-- An object's own name and its class name through the built-ins (o known valid); nil when empty or 'None' (or no
-- class answered)
local function fname_of(o)
    local ok, s = caught('name', nil, pcall(function() return o:GetFName():ToString() end))
    if not ok or type(s) ~= 'string' or s == '' or s == 'None' then return nil end
    return s
end
local function cls_of(o)
    local ok, c = caught('class', nil, pcall(function() return o:GetClass() end))
    if not ok or c == nil then return nil end
    return fname_of(c)
end
-- The built-in IsA against a class of M.CLS the ticker resolved: true | false; nil when o is invalid, the class is not
-- resolved yet or the check raised. known: o already answered IsValid true in this hook body (not asked again)
local function is_a(o, which, known)
    local c = st.cls[which]
    if c == nil or not (known or valid(o)) then return nil end
    local ok, r = caught('is_a', which, pcall(function() return o:IsA(c) end))
    if not ok then return nil end
    return r == true
end
-- The actor a hook object belongs to: the object or one of its OUTER_HOPS outers, the first that IsA Actor (a
-- component, an AI script or an ability task is none); nil when the chain ends or an object is invalid
local function actor_of(o)
    for _ = 0, M.OUTER_HOPS do
        local a = is_a(o, 'actor')
        if a == nil then return nil end
        if a then return o end
        local ok, up = caught('outer', nil, pcall(function() return o:GetOuter() end))
        if not ok then return nil end
        o = up
    end
    return nil
end
-- The pawn an AI object names (its Pawn property, an object field): an actor, else nil (an empty Pawn leaves the fire
-- without a victim, never the controller above it)
local function pawn_of(o)
    local p = ue.prop(o, 'Pawn')
    if is_a(p, 'actor') then return p end
    return nil
end
local function victim_of(route, ctx, args, n)
    if route == 'ai' then return pawn_of(ctx) end
    if route == 'task' then
        local ab = ue.prop(ctx, 'Ability')
        return (ab ~= nil and actor_of(ab)) or actor_of(ctx)
    end
    if route == 'ctx' then return actor_of(ctx) end
    for i = 1, n do
        if valid(args[i]) then
            local a = actor_of(args[i])
            if a then return a end
        end
    end
    return nil
end
-- An execution hook's victim (h12, h24; param order unknown until E0b): the first actor param that is not the
-- executor (the actor of the hook's ExecutionComponent)
local function exec_target(ctx, args, n)
    local own = actor_of(ctx)
    for i = 1, n do
        local a = valid(args[i]) and actor_of(args[i]) or nil
        if a and not (own and ue.same(a, own)) then return a end
    end
    return nil
end
-- A class name through the built-ins (IsValid first: a null object answers nothing else); nil when empty or 'None'
local function class_name(o)
    if not valid(o) then return nil end
    return cls_of(o)
end
-- A param's class or type: the class of a valid object, 'null' for an object answering IsValid false, 'name' for an
-- FName or string wrapper (ToString), 'struct:<type>' for a UScriptStruct userdata (its GetFName), 'struct' for a
-- struct without a type name or a plain table (the mock's struct shape), else the Lua type. Nothing that raises is
-- asked: IsValid and ToString only when a plain index answers them
local function kind_of(v)
    local t = type(v)
    if v == nil then return 'nil' end
    if t ~= 'table' and t ~= 'userdata' then return t end
    if t == 'table' and getmetatable(v) == nil then return 'struct' end
    local isv = answers(v)
    if isv == false then return 'null' end
    if isv then
        local c = cls_of(v)
        if c == nil then return 'struct' end
        if not STRUCT_CLASS[c] then return c end
        local s = fname_of(v)
        return s and 'struct:' .. s or 'struct'
    end
    if v.ToString ~= nil and ue.str(v) ~= nil then return 'name' end
    return t == 'table' and 'struct' or 'userdata'
end
local function is_struct(k) return k == 'struct' or k:sub(1, 7) == 'struct:' end
-- A bone, socket or tag name as a plain string; nil when empty or 'None'
local function text(v)
    local s = ue.str(v)
    if s == nil or s == '' or s == 'None' then return nil end
    return s
end
-- ---------- field sets: a member is read only when its type declares it (header; M1a 4.0 Cost) ----------
-- The cost counters appear with the first hook fire (bumps before it wait in st.early): a session without a fire
-- writes none of them
local function bump(k, n)
    if st.seeded then LAB.count(k, n) else st.early[k] = (st.early[k] or 0) + (n or 1) end
end
local PLAIN = {}                -- the field set of a plain Lua table (the mock's struct shape): its own keys
local LOWER = setmetatable({}, { __index = function(t, k) local v = k:lower() t[k] = v return v end })
local WORDS = { ['nil'] = true, null = true, name = true, struct = true, userdata = true, table = true, number = true,
    string = true, boolean = true, ['function'] = true, thread = true }
-- The type key of v (k: its kind_of when known): a struct's type name, an object's class name, PLAIN for a plain
-- table; nil for anything else (no member is read)
local function type_key(v, k)
    if type(v) == 'table' and getmetatable(v) == nil then return PLAIN end
    k = k or kind_of(v)
    if k:sub(1, 7) == 'struct:' then return k:sub(8), true end
    if WORDS[k] then return nil end
    return k, false
end
-- 'ScriptStruct /Script/M.T' or 'Class /Game/P/BP.BP_C' -> the object path
local function path_of(full) return type(full) == 'string' and full:match('^%S+%s+(.+)$') or nil end
-- An unknown type for the ticker, once: its path from GetFullName (a struct userdata answers for its UScriptStruct;
-- an object through its class); no member read
local function queue(key, v, is_struct_v)
    if st.tpend[key] or st.ntypes >= M.TYPES_MAX then return end
    local path
    if is_struct_v then
        path = path_of(ue.full(v))
    else
        local ok, c = caught('class', nil, pcall(function() return v:GetClass() end))
        path = ok and path_of(ue.full(c)) or nil
    end
    st.tpend[key], st.ntypes = true, st.ntypes + 1
    st.tq[#st.tq + 1] = { key = key, path = path }
    bump('field_queued')
end
-- The field set of v's type: PLAIN, a learned set, or nil (not learned yet: queued; or learned to have none); then
-- the type key
local function fields(v, k)
    if v == nil then return nil end
    local key, is_s = type_key(v, k)
    if key == PLAIN or key == nil then return key, key end
    local f = st.types[key]
    if f ~= nil then return f or nil, key end
    queue(key, v, is_s)
    return nil, key
end
local function has(v, f, name)
    if f == PLAIN then return rawget(v, name) ~= nil end
    return f[LOWER[name]] ~= nil
end
local function index(v, name) return v[name] end
-- One member read of a declared field (f: fields(v)); a nil f is a trial read: counted, refused, never read. A raw
-- index (a raise goes to ue.caught as 'prop': a trial read), then IsValid only where a plain index answers it
-- (answers: an FName, a number or a struct is kept as read; an object answering false reads nil)
local function member(v, f, name)
    if f == nil then
        st.trials = st.trials + 1
        bump('trial_reads')
        return nil
    end
    if not has(v, f, name) then return nil end
    local ok, r = pcall(index, v, name)
    if not ok then
        if type(ue.caught) == 'function' then ue.caught(r, 'prop', name) end
        return nil
    end
    if r ~= nil and answers(r) == false then return nil end
    return r
end
-- A param's kind (kind_of), a struct param's cached per hook id and index: its type is fixed by the UFunction
local function param_kind(id, i, v)
    if v == nil then return 'nil' end
    if type(v) == 'table' and getmetatable(v) == nil then return 'struct' end
    local pk = st.pk[id]
    local k = pk and pk[i]
    if k then return k end
    k = kind_of(v)
    if k:sub(1, 7) == 'struct:' then
        if not pk then pk = {} st.pk[id] = pk end
        pk[i] = k
    end
    return k
end
-- The field set of v, a value read from the declared field 'field' of a type pkey: a struct's kind cached per
-- (pkey, field), as fixed as the declaring type
local function inner(v, pkey, field)
    if v == nil then return nil end
    local k
    if pkey ~= nil and not (type(v) == 'table' and getmetatable(v) == nil) then
        local c = st.nk[pkey]
        k = c and c[field]
        if k == nil then
            k = kind_of(v)
            if k:sub(1, 7) == 'struct:' then
                if not c then c = {} st.nk[pkey] = c end
                c[field] = k
            end
        end
    end
    return (fields(v, k))
end
-- A member of the struct in a declared field (v read from field of type pkey), when its type declares it
local function sub(v, pkey, field, name)
    local f = inner(v, pkey, field)
    if f == nil then return nil end
    return member(v, f, name)
end
-- The EventTag of an OnGameplayEventReceived fire, read first: a GameplayTag param's TagName (h04), else the EventTag
-- of the first struct param that declares one (h20's GameplayEventData). 'unread' while a type is not learned (or the
-- tag reads empty), nil when no param carries one. kinds[i]: each param's kind, kept for the snapshot
local function event_tag(id, args, n, kinds)
    local unread = false
    for i = 1, n do
        local v = args[i]
        local k = param_kind(id, i, v)
        kinds[i] = k
        if is_struct(k) then
            local f, key = fields(v, k)
            if f == nil then
                unread = true
            elseif has(v, f, 'TagName') then
                return text(member(v, f, 'TagName')) or 'unread'
            elseif has(v, f, 'EventTag') then
                return text(sub(member(v, f, 'EventTag'), key, 'EventTag', 'TagName')) or 'unread'
            end
        end
    end
    return unread and 'unread' or nil
end
-- A skipped event fire per tag: event_skipped and event_skip_<tag> (the first SKIP_TAGS tags, then 'other')
local function skip_event(tg)
    local k = st.skip_key[tg]
    if k == nil then
        if st.nskip_keys < M.SKIP_TAGS then
            k = 'event_skip_' .. (tg:gsub('[^%w_]', '_'))
            st.nskip_keys = st.nskip_keys + 1
        else
            k = 'event_skip_other'
        end
        st.skip_key[tg] = k
    end
    st.skipped = st.skipped + 1
    LAB.count('event_skipped')
    LAB.count(k)
end
-- Payload objects are read once L0i-lite returned 2 of 2 (LAB.l0i_ok, false again after a stop) and until a stop; a
-- lab_probe without LAB.l0i_ok reads none (the header)
local function objects_ok()
    return type(LAB.l0i_ok) == 'function' and LAB.l0i_ok() == true and LAB.inherit_ok()
end
-- The payloads of one fire as { v, f, key } (f: the field set of v's type, key: its type key): every struct param
-- whose type is learned; its OptionalObject when that type declares one (the GameplayEventData payload object;
-- IsValid on every such fire, so a skip is counted) and every object param whose class names a payload only while
-- objects_ok(), and only once their class is learned. -> the list, the payload objects left unread and the first
-- OptionalObject read (the key of one event's copy)
local function payloads(args, kinds, n)
    local out, objs, skipped, first = {}, objects_ok(), 0, nil
    for i = 1, n do
        local k = kinds[i]
        if is_struct(k) then
            local f, key = fields(args[i], k)
            if f then
                out[#out + 1] = { v = args[i], f = f, key = key }
                local oo = member(args[i], f, 'OptionalObject')
                if valid(oo) then
                    local fo, ko
                    if objs then fo, ko = fields(oo, cls_of(oo) or 'nil') end
                    if fo then
                        out[#out + 1] = { v = oo, f = fo, key = ko }
                        first = first or oo
                    elseif not objs then
                        skipped = skipped + 1
                    end
                end
            end
        elseif k:find('Payload', 1, true) then
            local f, key
            if objs then f, key = fields(args[i], k) end
            if f then out[#out + 1] = { v = args[i], f = f, key = key } elseif not objs then skipped = skipped + 1 end
        end
    end
    return out, skipped, first
end
-- The first payload that declares name and holds a value (never a member its type lacks), and its type key
local function pick(src, name)
    for i = 1, #src do
        local v = member(src[i].v, src[i].f, name)
        if v ~= nil then return v, src[i].key end
    end
    return nil
end
-- A member of the struct a payload field holds; a GameplayTag field's TagName; an FVector field as {x,y,z}
local function pick_sub(src, field, name)
    local v, key = pick(src, field)
    return sub(v, key, field, name)
end
local function tag(src, field) return text(pick_sub(src, field, 'TagName')) end
local function vec3(src, field)
    local v, key = pick(src, field)
    local f = inner(v, key, field)
    if f == nil then return nil end
    local x, y, z = member(v, f, 'X'), member(v, f, 'Y'), member(v, f, 'Z')
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    return { x = x, y = y, z = z }
end
-- One hop from a valid actor that is no pawn (a weapon, a projectile) to its wielder: its Instigator, else its Owner
-- (declared Actor properties, usmap_props.tsv:92, :78), taken only when it IsA Pawn (checks:b, d); nil otherwise
local function wielder(o)
    if is_a(o, 'actor', true) ~= true or is_a(o, 'pawn', true) ~= false then return nil end
    for _, f in ipairs(M.HOP) do
        local p = ue.prop(o, f)
        if is_a(p, 'pawn') then return p end
    end
    return nil
end
-- The pawn behind a killer object: a Controller's Pawn, a PlayerState's PawnPrivate (declared properties, read after
-- IsA), a weapon's or projectile's wielder (then true: the hop), else the object itself; nil when the object or that
-- link is empty
local function pawn_behind(o)
    if not valid(o) then return nil end
    if is_a(o, 'pawn', true) then return o end      -- the usual killer: no Controller, PlayerState or wielder hop
    if is_a(o, 'controller', true) then
        o = ue.prop(o, 'Pawn')
    elseif is_a(o, 'player_state', true) then
        o = ue.prop(o, 'PawnPrivate')
    else
        local w = wielder(o)
        if w then return w, true end
    end
    return valid(o) and o or nil
end
-- The killer object of one fire and its source: 'event' (GameplayEventData.Instigator), 'damage_source' or 'owner'
-- (the DamageSource actor's Instigator or Owner), 'owner_hop' when one of them was a weapon or projectile whose
-- wielder stands for it, nil and 'none'
local function killer_of(ins, ds)
    local k, hop = pawn_behind(ins)
    if k then return k, hop and 'owner_hop' or 'event' end
    if is_a(ds, 'actor') then
        k, hop = pawn_behind(ue.prop(ds, 'Instigator'))
        if k then return k, hop and 'owner_hop' or 'damage_source' end
        k, hop = pawn_behind(ue.prop(ds, 'Owner'))
        if k then return k, hop and 'owner_hop' or 'owner' end
    end
    return nil, 'none'
end
-- The labels of one bullet data asset (bd: a member read answered it, cls its class name), read on a cache miss
-- through its class's learned field set: a table; false when that class declares no field (cached: never asked
-- again); nil when the class is not learned yet (queued, counted in bullet_unread: a later hit reads it) or the map's
-- cache is full (bullet_cache_full)
local function read_bullet(bd, cls)
    if st.nbullets >= M.BULLETS then
        bump('bullet_cache_full')
        return nil
    end
    local f = fields(bd, cls)
    if f == nil then
        if st.types[cls] == false then return false end
        bump('bullet_unread')
        return nil
    end
    local function tg(name) return text(sub(member(bd, f, name), cls, name, 'TagName')) end
    local o = member(bd, f, 'OriginType')
    local path = path_of(ue.full(bd))
    bump('bullet_read')
    return { name = fname_of(bd), class = cls, dir = path and path:match('^(.*)/[^/]*$') or nil,
        skill = tg('SkillType'), strength = tg('HitStrength'), attack_dir = tg('AttackDirection'),
        origin = type(o) == 'number' and (M.ORIGIN[o] or tostring(o)) or nil }
end
-- The bullet hop (header; ds the payload's valid DamageSource, dsc its class name, victim the hook's victim object or
-- nil): owner_is_victim on every build (R4), then with the tier reads only owner_is_pawn and the asset's labels from
-- the map's cache (one read per address), into the snapshot; the first read of an asset name queues its bullet_seen
-- record for the ticker. Without the tier only a type already learned is read (the primed module types): nothing is
-- learned on sight there
local function bullet(snap, ds, dsc, victim)
    if not st.tier and st.types[dsc] == nil then return end
    local f = fields(ds, dsc)
    if f == nil or not has(ds, f, 'BulletData') then return end
    local owner = member(ds, f, 'LastOwnerAvatar')
    if owner ~= nil and victim ~= nil then              -- the receiver's own bullet: its own attack (item 178860405)
        local oa = ue.addr(owner)
        snap.owner_is_victim = oa ~= nil and oa == ue.addr(victim)
        if snap.owner_is_victim then bump('bullet_own_attack') end
    end
    if not st.tier then return end                      -- unpinned, or the pin check not answered yet: the owner only
    if owner ~= nil and st.pawn then snap.owner_is_pawn = ue.addr(owner) == st.pawn.addr end
    local bd = member(ds, f, 'BulletData')
    local addr = bd ~= nil and ue.addr(bd) or nil
    if addr == nil then return end
    local b = st.bullets[addr]
    if b == nil then
        local cls = cls_of(bd)
        if cls == nil then return end
        b = read_bullet(bd, cls)
        if b == nil then return end
        st.bullets[addr], st.nbullets = b, st.nbullets + 1
        if b and b.name and not st.bseen[b.name] and st.nbseen < M.BULLET_SEEN then
            st.bseen[b.name], st.nbseen = true, st.nbseen + 1
            st.bq[#st.bq + 1] = { bullet = b.name, dir = b.dir, class = b.class, skill_type = b.skill,
                strength = b.strength, attack_dir = b.attack_dir, origin = b.origin, victim = snap.victim,
                owner_is_pawn = snap.owner_is_pawn, owner_is_victim = snap.owner_is_victim }
        end
    end
    if not b then return end
    snap.bullet, snap.bullet_dir, snap.skill_type = b.name, b.dir, b.skill
    snap.bd_strength, snap.bd_dir, snap.bd_origin = b.strength, b.attack_dir, b.origin
end
-- The copy of the payload fields into the snapshot (plain values only). source_seen: the payloads read carried a
-- valid Instigator or DamageSource object (lab_poll tells an environment death, no source at all, from an unread one);
-- victim: the hook's victim object (the bullet hop's owner_is_victim) or nil
local function copy_payload(snap, src, victim)
    snap.bone = text((pick(src, 'HitBone')))
    snap.body_bone = text(pick_sub(src, 'HitBodyData', 'bone'))
    snap.socket = text(pick_sub(src, 'HitBody', 'SocketName'))
    snap.attack_dir = vec3(src, 'AttackDirection')
    snap.sweep_dir = vec3(src, 'SweepDirection')
    snap.hit_loc = vec3(src, 'HitLocation')         -- fixes-0.2.2 B3.4 (D4): logged only, its space unread yet
    snap.cause = tag(src, 'DamageCause')
    local ds = pick(src, 'DamageSource')
    snap.source_class = class_name(ds)
    snap.attack_type = tag(src, 'AttackType')
    snap.final_attack_type = tag(src, 'FinalAttackType')
    local ins = pick(src, 'Instigator')
    if valid(ins) or valid(ds) then snap.source_seen = true end
    local k, how = killer_of(ins, ds)
    snap.killer = k and cls_of(k)                   -- k answered IsValid true in killer_of
    snap.killer_src = snap.killer and how or 'none'
    local p = st.pawn
    if snap.killer and p then snap.by_player = ue.addr(k) == p.addr and fname_of(k) == p.name end
    if st.tier then                                 -- the beta's tier reads (BD3), once the pin check passed
        snap.hit_strength = tag(src, 'HitStrength')
        snap.origin_strength = tag(src, 'OriginStrength')
        snap.anim_strength = tag(src, 'StrengthAnimStrength')
        snap.hit_state = tag(src, 'HitState')
    end
    -- the bullet hop: its owner test in every beta session that reads payload objects (R4), the rest with the tier
    if st.beta and snap.source_class ~= nil and objects_ok() then bullet(snap, ds, snap.source_class, victim) end
end
-- client_restart: the first valid object param (NewPawn) as a keep record, emitted by the lab ticker as lab_pawn; its
-- address and name as the lab pawn (plain values) for by_player
local function post_pawn(args, n, ts)
    for i = 1, n do
        local p = args[i]
        if valid(p) then
            local kp = ue.keep(p)
            st.pawn = { addr = ue.addr(p), name = kp.name }
            local ev = { pawn = kp, t = ts,
                key = string.format('%s|%s|%d', tostring(ue.addr(p)), ue.full(p) or kp.name or 'unread', ue.epoch) }
            LAB.post(function() BUS.emit('lab_pawn', ev) end, 'lab_pawn')
            return
        end
    end
end

-- A defender's block event (M.BLOCKS, bug B2): its victim's mark, the fire time and the tag (no payload read, no
-- snapshot); counter block_marks
local function mark_block(route, ctx_p, args, n, tg)
    local v = victim_of(route, ue.p(ctx_p), args, n)
    local rec = v ~= nil and LAB.victim(v) or nil
    if rec == nil then return end
    if st.blocks[rec.key] == nil then
        if st.nblocks >= M.BLOCKS_MAX then st.blocks, st.btags, st.nblocks = {}, {}, 0 end
        st.nblocks = st.nblocks + 1
    end
    st.blocks[rec.key] = now()
    st.btags[rec.key] = tg
    LAB.count('block_marks')
end
-- The consumer of one id. Returns nothing. Records, file writes and sentinel calls stay out (L014): the snapshot goes
-- to LAB.snap_push (victim key) and to the ticker queue
local function consumer(id, route)
    local slicer = SLICE_IDS[id] == true
    return function(ctx_p, ...)
        if not A then return end
        if slicer and self_slicing() then          -- our own slice: nothing read, one counter, no return value
            st.self_slices = (st.self_slices or 0) + 1
            return
        end
        local t0 = M.clock()
        st.depth = st.depth + 1                 -- a member read that raises in here is a trial read (on_prop_error)
        local n = select('#', ...)
        local args, kinds = { ... }, {}
        for i = 1, n do args[i] = ue.p(args[i]) end
        local tg = nil
        if st.ev[id] then                       -- an OnGameplayEventReceived hook: the EventTag first (header)
            tg = event_tag(id, args, n, kinds)
            if not M.EVENTS[tg] then
                skip_event(tg or 'none')
                if M.BLOCKS[tg] then mark_block(route, ctx_p, args, n, tg) end
                LAB.count('hook_fires')
                st.n, st.min_ms, st.depth = st.n + 1, st.min_ms + ms(M.clock() - t0), st.depth - 1
                return
            end
        end
        local ctx = ue.p(ctx_p)
        local rec, v = nil, nil
        if route ~= 'pawn' then
            if EXEC[id] then v = exec_target(ctx, args, n) else v = victim_of(route, ctx, args, n) end
            if v ~= nil then rec = LAB.victim(v) end
        end
        LAB.count('hook_fires')
        local ts = now()
        local t1 = M.clock()
        local params = { self = kind_of(ctx) }
        for i = 1, n do
            kinds[i] = kinds[i] or param_kind(id, i, args[i])
            params['p' .. i] = kinds[i]
        end
        local snap = { key = id, t = ts, vkey = rec and rec.key or nil, victim = rec and rec.class or nil,
            params = params, event = tg }
        if st.tier then                         -- BD3: the order of one frame's events
            st.seq = st.seq + 1
            snap.seq = st.seq
        end
        local src, skipped, oo = payloads(args, kinds, n)
        -- one copy per event (header): the victim, the tag and the OptionalObject's address within this tick
        local addr = (oo ~= nil and rec ~= nil and tg ~= nil) and ue.addr(oo) or nil
        local dk = addr ~= nil and (rec.key .. '|' .. tg .. '|' .. tostring(addr)) or nil
        if dk ~= nil and st.dup_key == dk and st.dup_tick == st.ticks then
            local from = st.dup_snap
            for _, f in ipairs(M.PAY) do snap[f] = from[f] end
            st.reused = st.reused + 1
            LAB.count('payload_reused')
        elseif src[1] ~= nil then
            copy_payload(snap, src, rec and v)
            if dk ~= nil then st.dup_key, st.dup_tick, st.dup_snap = dk, st.ticks, snap end
        end
        if skipped > 0 then
            snap.payload_skipped, st.pay_skip = skipped, st.pay_skip + skipped
            LAB.count('payload_skipped', skipped)
        end
        if rec then
            LAB.snap_push(rec.key, snap)
            if st.seen[rec.key] == nil and st.nseen < M.SEEN then st.seen[rec.key], st.nseen = rec, st.nseen + 1 end
        end
        if route == 'pawn' then post_pawn(args, n, ts) end
        if #st.q < M.QMAX then st.q[#st.q + 1] = snap else st.qdrop = st.qdrop + 1 end
        local t2 = M.clock()
        st.n, st.min_ms, st.copy_ms = st.n + 1, st.min_ms + ms(t1 - t0), st.copy_ms + ms(t2 - t1)
        st.depth = st.depth - 1
    end
end
-- ue.on_error (key 'lab_kill'): every error caught inside a hook body counts in hook_raises (a C++ throw on UE4SS);
-- a property read that raised there is also a trial read (a member its type lacks: on UE4SS a missing struct member
-- throws, LuaUScriptStruct.cpp:176-185). No IO
local function on_prop_error(_, helper)
    if st.depth <= 0 then return end
    st.raises = st.raises + 1
    bump('hook_raises')
    if helper == 'prop' then
        st.trials = st.trials + 1
        bump('trial_reads')
    end
end

-- ---------- the lab ticker: hook_fire, deaths, tallies (never inside a hook body) ----------
local function tally(id)
    local T = st.tally[id]
    if not T then
        T = { fires = 0, once = 0, zero = 0, multi = 0, resolved = 0 }
        st.tally[id] = T
    end
    return T
end
-- One hook_fire per snapshot at most (section 3.1 fields; sharp and blunt 'unread', see the header); the beta's tier
-- fields (BD3) are absent unless read
local function write_fire(f)
    if st.written[f] then return end
    st.written[f] = true
    LAB.rec('hook_fire', { key = f.key, victim = f.victim, params = f.params, bone = f.bone, body_bone = f.body_bone,
        socket = f.socket, attack_dir = f.attack_dir, sweep_dir = f.sweep_dir, hit_loc = f.hit_loc, cause = f.cause,
        source_class = f.source_class, attack_type = f.attack_type, final_attack_type = f.final_attack_type,
        sharp = 'unread', blunt = 'unread', killer = f.killer, killer_src = f.killer_src, by_player = f.by_player,
        payload_skipped = f.payload_skipped, source_seen = f.source_seen, event = f.event, seq = f.seq,
        hit_strength = f.hit_strength, origin_strength = f.origin_strength, anim_strength = f.anim_strength,
        hit_state = f.hit_state, bullet = f.bullet, bullet_dir = f.bullet_dir, skill_type = f.skill_type,
        bd_strength = f.bd_strength, bd_dir = f.bd_dir, bd_origin = f.bd_origin, owner_is_pawn = f.owner_is_pawn,
        owner_is_victim = f.owner_is_victim })
end
local function on_fire(f)
    local T = tally(f.key)
    T.fires = T.fires + 1
    if T.fires <= M.FIRST_N then write_fire(f) end
    if f.vkey then
        local c = st.cur[f.vkey]
        if not c then
            c = {}
            st.cur[f.vkey] = c
        end
        c[f.key] = (c[f.key] or 0) + 1
        if EXEC[f.key] then st.exec_at[f.vkey] = f.t end
    elseif ROUTE[f.key] ~= 'pawn' then
        local L = st.loose
        L[#L + 1] = f
        if #L > M.LOOSE then table.remove(L, 1) end
    end
end
-- bus lab_death rec {key, t, kill, ...}: the life's counts stay open SETTLE_S; the fires of the last BEFORE_S written
local function on_death(d)
    if type(d) ~= 'table' or d.key == nil then return end
    local t = tonumber(d.t) or now()
    local c = st.cur[d.key] or {}
    st.cur[d.key] = c
    st.pending[#st.pending + 1] = { key = d.key, t = t, counts = c,
        exec = type(d.kill) == 'table' and d.kill.execution == true }
    for _, f in ipairs(LAB.snaps(d.key, t - M.BEFORE_S)) do
        if type(f.params) == 'table' and st.tally[f.key] and f.t <= t then write_fire(f) end
    end
    for _, f in ipairs(st.loose) do
        if f.t >= t - M.BEFORE_S and f.t <= t then write_fire(f) end
    end
end
local function settle(p)
    local ex = p.exec or (st.exec_at[p.key] or -math.huge) >= p.t - M.EXEC_S
    local joined = {}
    for _, f in ipairs(st.loose) do
        if not st.claimed[f] and math.abs(f.t - p.t) <= M.JOIN_S then
            st.claimed[f] = true
            joined[f.key] = (joined[f.key] or 0) + 1
        end
    end
    if ex then
        st.exec_deaths = st.exec_deaths + 1
    else
        st.deaths = st.deaths + 1
        for _, id in ipairs(st.ids) do
            local T, r = tally(id), p.counts[id] or 0
            local n = r + (joined[id] or 0)
            if n == 0 then T.zero = T.zero + 1 elseif n == 1 then T.once = T.once + 1 else T.multi = T.multi + 1 end
            if r > 0 then T.resolved = T.resolved + 1 end
        end
    end
    if st.cur[p.key] == p.counts then st.cur[p.key] = nil end
    st.exec_at[p.key] = nil
end
local function finalize(all)
    local t, keep = now(), {}
    for _, p in ipairs(st.pending) do
        if all or t >= p.t + M.SETTLE_S then settle(p) else keep[#keep + 1] = p end
    end
    st.pending = keep
end
local function hook_ids()
    local ok, s = pcall(A.hooks.status)
    return ok and type(s) == 'table' and type(s.ids) == 'table' and s.ids or {}
end
local function write_tallies(reason)
    local hs = hook_ids()
    for _, id in ipairs(st.ids) do
        local T, h = tally(id), hs[id] or {}
        local calls = tonumber(h.calls) or 0
        LAB.rec('hook_tally', { key = id, reason = reason, fires = T.fires, deaths = st.deaths,
            exec_deaths = st.exec_deaths, once = T.once, zero = T.zero, multi = T.multi, resolved = T.resolved,
            once_all = T.once == st.deaths and st.deaths == T.resolved and st.deaths >= M.ONCE_MIN,
            mean_us = calls > 0 and r2((tonumber(h.ms_total) or 0) * 1000 / calls) or nil, n_ge_1ms = h.n_ge_1ms })
    end
end
-- emit: bus lab_hit(rec, t, key) once per victim of this batch (its newest fire), the registry record of a victim a
-- hook named, for lab_poll's victim set (S2.12 admits hook-param victims through it); a map reset passes false (the
-- old map's records are stale there)
local function drain(emit)
    if st.q[1] then
        local q, last, order = st.q, {}, {}
        st.q = {}
        for i = 1, #q do
            local f = q[i]
            on_fire(f)
            if f.vkey ~= nil and st.seen[f.vkey] ~= nil then
                if last[f.vkey] == nil then order[#order + 1] = f.vkey end
                last[f.vkey] = f
            end
        end
        if emit ~= false then
            for _, k in ipairs(order) do BUS.emit('lab_hit', st.seen[k], last[k].t, last[k].key) end
        end
    end
    if st.dq[1] then
        local q = st.dq
        st.dq = {}
        for i = 1, #q do on_death(q[i]) end
    end
end
-- The IsA classes (a miss retried on every tick: ue.class caches it until a map load) and a bus lab_pawn's pawn
local function resolve()
    for k, path in pairs(M.CLS) do
        if st.cls[k] == nil then st.cls[k] = ue.class(path) end
    end
    local rec = st.pawn_in
    if rec == nil then return end
    st.pawn_in = nil
    local p = type(rec) == 'table' and rec.pawn or nil
    local o = (type(p) == 'table' and rawget(p, '__mock') == nil) and ue.live(p) or (ue.valid(p) and p or nil)
    if o then st.pawn = { addr = ue.addr(o), name = ue.name(o) } end
end
-- The fields a class or struct and its GetSuperStruct chain declare (up to SUPER_MAX links, UObject left out), merged
-- as { [lower-case name] = true }; false when no pass returned (not in memory, a pass that raised, no path)
local function learn(path)
    local set, any = {}, false
    for _ = 1, M.SUPER_MAX do
        if path == nil or path == M.OBJECT_PATH then break end
        local f = ue.fields(path)
        if f then
            any = true
            for k in pairs(f) do set[k] = true end
        end
        local cls = ue.class(path)
        if not cls then break end
        local ok, up = caught('super', path, pcall(function() return cls:GetSuperStruct() end))
        path = (ok and ue.valid(up)) and path_of(ue.full(up)) or nil
    end
    return any and set or false
end
-- Up to TYPES_TICK queued types per tick, every pass inside one LAB.armed('probe.meta') call (the field passes' guard,
-- as session_pbz's names lint): each answer kept for the session; a refused or failed guard answers false (no field)
local function learn_types()
    if not st.tq[1] then return end
    local batch = {}
    while st.tq[1] and #batch < M.TYPES_TICK do batch[#batch + 1] = table.remove(st.tq, 1) end
    local r = LAB.armed('probe.meta', function()
        local out = {}
        for i, e in ipairs(batch) do out[i] = learn(e.path) end
        return out
    end)
    for i, e in ipairs(batch) do
        local set = type(r) == 'table' and r[i] or false
        st.tpend[e.key] = nil
        if set == false and e.primed then
            st.ntypes = st.ntypes - 1           -- forgotten: a hook body queues it with its own path (M.PRIME)
        else
            st.types[e.key] = set
            bump('field_cached')
        end
    end
end
-- Queue type paths for learn_types, primed: a path that finds nothing is forgotten (M.PRIME, M.PRIME_BETA)
local function prime(list)
    for _, path in ipairs(list) do
        local key = path:match('%.([^.]+)$')
        if key and not st.tpend[key] and st.types[key] == nil then
            st.tpend[key], st.ntypes = true, st.ntypes + 1
            st.tq[#st.tq + 1] = { key = key, path = path, primed = true }
            bump('field_queued')                        -- held in st.early until the first hook fire
        end
    end
end
-- The beta's tier reads (BD3) wait for the pin check (header): once it answered, st.tier holds its verdict for the
-- session, and either answer primes the bullet module types (the owner test runs pinned or not: R4)
local function tier_gate()
    if st.tier ~= nil or not st.beta or type(LAB.pinned) ~= 'function' then return end
    local p = LAB.pinned()
    if p == nil then return end
    st.tier = p == true
    prime(M.PRIME_BETA)
end
local function tick()
    st.depth = 0                                -- never inside a hook body here (a consumer that raised left it up)
    st.ticks = st.ticks + 1                     -- one event's copy is shared within a tick only
    if not st.seeded and st.n > 0 then          -- the first fire: the cost counters start (trial_reads at 0)
        st.seeded = true
        LAB.count('trial_reads', 0)
        LAB.count('hook_raises', 0)
        for k, v in pairs(st.early) do LAB.count(k, v) end
        st.early = {}
    end
    tier_gate()
    learn_types()
    resolve()
    drain()
    if st.bq[1] then                            -- the hook bodies' bullet_seen records (BD3)
        local q = st.bq
        st.bq = {}
        for _, e in ipairs(q) do LAB.rec('bullet_seen', e) end
    end
    if st.pending[1] then finalize(false) end
    if st.fq[1] then
        local q = st.fq
        st.fq = {}
        for _, reason in ipairs(q) do
            if reason ~= 'periodic' then finalize(true) end     -- a map load or lab_end ends every open life
            write_tallies(reason)
        end
    end
end
-- hooks.lua sums: the whole dispatch per call (every consumer) and the fires at or over 1 ms
local function dispatch()
    local calls, total, n1 = 0, 0, 0
    for _, h in pairs(hook_ids()) do
        calls, total, n1 = calls + (tonumber(h.calls) or 0), total + (tonumber(h.ms_total) or 0), n1 + (h.n_ge_1ms or 0)
    end
    return calls, total, n1
end

-- ---------- lifecycle ----------
-- opts.hooks: the hook table (tests); default data/hooks.lua hooks
function M.init(adapter, opts)
    A = adapter
    st = new_state()
    LAB.names(N, F)
    local data = type(opts) == 'table' and opts.hooks or HDATA.hooks or {}
    for id in pairs(data) do st.ids[#st.ids + 1] = id end
    table.sort(st.ids)
    local beta = LAB.beta()
    for _, id in ipairs(st.ids) do
        if not (beta and SLICE_IDS[id]) then              -- the beta registers no slicer hook (header)
            local side = data[id].kind == 'native' and SIDE[id] or 'post'
            local path = data[id].path
            st.ev[id] = type(path) == 'string' and path:sub(-#M.EVENT_FN) == M.EVENT_FN or nil
            A.hooks.hook(id, M.FEATURE, { [side] = consumer(id, ROUTE[id] or 'param'), optional = true })
        end
    end
    prime(M.PRIME)                                  -- the payload types: learned on the first tick, before any hit
    ue.on_error(on_prop_error, 'lab_kill')
    -- hook_tally writes one record per id per flush: the default cap (200) would drop the lab_end flush after about
    -- 7 flushes of 26 ids, so this event gets TALLY_CAP (below the log's 2000 per event)
    if (LAB.CAPS.hook_tally or 0) < M.TALLY_CAP then LAB.CAPS.hook_tally = M.TALLY_CAP end
    st.beta = LAB.beta()
    if st.beta and (LAB.CAPS.bullet_seen or 0) < M.BULLET_SEEN then LAB.CAPS.bullet_seen = M.BULLET_SEEN end
    LAB.gauge('hook_us_mean', function()
        local calls, total = dispatch()
        if calls > 0 then return r2(total * 1000 / calls) end
    end)
    LAB.gauge('hook_us_mean_min', function() if st.n > 0 then return r2(st.min_ms * 1000 / st.n) end end)
    LAB.gauge('hook_us_mean_copy', function() if st.n > 0 then return r2(st.copy_ms * 1000 / st.n) end end)
    LAB.gauge('hook_calls', function() if st.n > 0 then return st.n end end)
    LAB.gauge('hook_n_ge_1ms', function()
        local calls, _, n1 = dispatch()
        if calls > 0 then return n1 end
    end)
    LAB.gauge('hook_share_ge_1ms', function()
        local calls, _, n1 = dispatch()
        if calls > 0 then return math.floor(n1 / calls * 1e4 + 0.5) / 1e4 end
    end)
    S.ticker('lab_kill', tick)
    BUS.on('lab_death', 'lab_kill', function(rec) st.dq[#st.dq + 1] = rec end)        -- listeners only queue
    BUS.on('lab_flush', 'lab_kill', function(reason) st.fq[#st.fq + 1] = reason or 'periodic' end)
    BUS.on('lab_pawn', 'lab_kill', function(rec) st.pawn_in = rec end)              -- L0i's FindFirstOf fallback too
    return true
end
function M.seen()
    local out = {}
    for _, rec in pairs(st.seen) do out[#out + 1] = rec end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end
-- A map load (lab_probe already queued the 'map' flush): the old map's fires and deaths are counted, every open life
-- settles, then the per-map state goes (the bullet data cache too: BD3); the tallies stay for the session
function M.reset(reason)
    if reason ~= 'map' then return end
    drain(false)
    finalize(true)
    st.cur, st.exec_at, st.loose, st.seen, st.nseen = {}, {}, {}, {}, 0
    st.bullets, st.nbullets, st.blocks, st.btags, st.nblocks = {}, 0, {}, {}, 0
end
-- The newest block mark of a victim key (bug B2, header): its fire time on the lab clock and its tag, or nil
function M.blocked(key)
    if key == nil or st.blocks[key] == nil then return nil end
    return st.blocks[key], st.btags[key]
end
function M.status()
    return { fires = st.n, queued = #st.q, dropped = st.qdrop, pending = #st.pending, deaths = st.deaths,
        exec_deaths = st.exec_deaths, seen = st.nseen, actor_class = st.cls.actor ~= nil, pawn = st.pawn ~= nil,
        payload_skipped = st.pay_skip, types = M.types(), types_pending = #st.tq, trial_reads = st.trials,
        event_skipped = st.skipped, hook_raises = st.raises, payload_reused = st.reused, tier = st.tier,
        bullets = st.beta and st.nbullets or nil, bullet_seen = st.beta and st.nbseen or nil,
        self_slices = st.self_slices or 0 }
end
-- The learned types: { [type] = the number of declared fields, or false (none: never read) }
function M.types()
    local out = {}
    for k, f in pairs(st.types) do
        local n = 0
        if f then for _ in pairs(f) do n = n + 1 end end
        out[k] = f and n or false
    end
    return out
end
function M.shutdown()
    ue.on_error(nil, 'lab_kill')
    S.remove_ticker('lab_kill')
    BUS.off('lab_death', 'lab_kill')
    BUS.off('lab_flush', 'lab_kill')
    BUS.off('lab_pawn', 'lab_kill')
    st, A = new_state(), nil
end

return M
