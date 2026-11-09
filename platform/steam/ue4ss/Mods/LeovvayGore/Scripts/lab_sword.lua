-- status: new for the beta (offline only; the author's next run decides) origin: the author 2026-11-01 («launch
-- a research workflow so the blood can stay on the sword only and not on Soul»), spike S1 of
-- scratch/swordblood/spike_spec.md with its SKEPTIC CORRECTIONS, run 20261102-f93cf2f, then the author 2026-11-02 («I
-- left the last mode on Ctrl+Shift+F5 as the reference one»: the last press was look A, so A ships)
-- lab_sword.lua: blood on the weapons Soul strikes with, never on Soul. The player beta loads it (META.beta_modules,
-- after lab_blood, whose bus lab_bleed and lab_soul_heal it follows); outside the beta (LAB.beta()) init stays inert (no
-- listener, ticker or record). It touches only the weapon actors attached to the pawn (their WeaponMesh), never a
-- component of the pawn. The test build's other looks (A2, B, C, clean) and the look key Ctrl+Shift+F5 live in
-- lab_sword_looks.lua, which plugs in through W.extend; the player zip leaves that file out.
-- * Settings (core/config.lua, read again when C.gen() moves): sword_blood (Mods Menu 'Blood on the sword'; false
--   works as mod-off for this module: every weapon back at once, no new blood, no donor load) is independent of
--   soul_blood (lab_blood), so Blood on Soul off plus this on gives blood on the sword only. soul_blood_life_s ('Blood
--   lasts'), wash_on_heal, heal_hold_s, heal_fade_s and blood_amount shape the amount (below). With blood effects off
--   (C.effect('blood')) a blow adds nothing and the blood there fades.
-- * The weapons: the pawn of bus lab_pawn, its GetAttachedActors(out, true, false) (the lab_census TArray guard:
--   adapter/tarray.lua check first, a raise poisons it), every attached actor that IsA
--   /Script/PBZCombatAsset.WeaponActorBase with a valid WeaponMesh whose owner is not the pawn. Read per weapon:
--   class, Slot.TagName in any case (Weapon.Slot.Main 'main'; Weapon.Slot.Shachi 'shachi', as run 20261102-f93cf2f
--   read it, where the spike's exact 'Weapon.Slot.ShaChi' skipped every Sha-Qi blow; else 'other': never bloodied),
--   WeaponDisplayIndex, DisplayData.ArmedSocket and UnarmedSocket, the root's AttachParent and AttachSocketName (the
--   mesh's AttachSocketName when the root reads None), the actor's bHidden, the mesh's bVisible and bReceivesDecals,
--   GetNumMaterials, GetMaterial(0) and its Parent chain (CHAIN_MAX names). A weapon whose slot-0 material, or a name
--   of its chain, is in W.NO_BLOOD_MAT reads 'other' too (sword_census no_blood 'dissolve'): the game hides it through
--   a dissolve layer of that material that no donor carries, so our MID would show it (intake 2026-11-03c: the Tianmiao
--   sword that rides with the Wild Oriole showed as a second blade, «clone itself becomes dual weapon», «two sword on
--   me when i execute»; BP_Weapon_Hun_TianMiao, MI_NPC_MuTianMiao_Sword: Masked, ML_BoundSpaceDissolve_001 over the
--   MAI_Equipment_Mask chain, so look A took the FemaleThug cleaver; the HookMan hooks' MI_EliteBoss_HookMan_Hook_Hun
--   has the same layer over the same chain). In hand: a main weapon whose socket is its
--   ArmedSocket (Double R and L both); a Sha-Qi weapon (Armed = Unarmed socket) whose socket is its ArmedSocket and that
--   shows (actor not hidden, mesh visible). When no weapon of the slot reads any socket (root and mesh both None), the
--   weapons of the slot that show stand in (sword_blow by 'shown'). The census is lazy: on a blow that finds no weapon
--   of its slot in hand, at most every CENSUS_S; a blow re-reads the cached weapons' sockets and flags.
-- * Attribution, Lua only, per bus lab_bleed 'hit' or 'kill' (queued {kind, key, t}; head, limb and spurt bleeds carry
--   no victim key and add nothing): the newest LAB.snaps(key, t - SNAP_BACK) entry with owner_is_pawn true (lab_kill's
--   bullet hop). bd_origin MainWeapon, or no origin on an execution bullet (bullet_dir ending '/ExE', or an 'EB_'
--   bullet): the main weapons in hand. ShachiWeapon: the Sha-Qi weapons in hand, i.e. the ones that show (the
--   TieKuangQuanTao gauntlets show only while Soul uses them; a hidden bow takes nothing). SourceAvatar (kicks, the
--   slomo bullet): nothing. No owner_is_pawn entry: nothing.
-- * Look A (W.LOOKS.A, the spike's CPD route, the author's reference): a MID over the donor with Use Blood on whose
--   layers match the weapon's (W.LOOKS.A.pick: ZhanMa's MI_EliteMonster_JingYe_Armor -> MI_Boss_ShouMenRenTuoBI_Shield,
--   its own lightning layer; HeiMoShang's MI_NPC_MoTian_Sword and the gauntlets' MI_BOSS_LuanShi_Cloth_UDIM ->
--   MI_Boss_DuoLuoJiangJun_Weapon; else the chain: MAI_Equipment(_Mask) -> the FemaleThug cleaver, MAI_Character -> the
--   hoe), the weapon's own values copied in (K2_CopyMaterialInstanceParameters(orig, false)), MaskTiling 0.394, Mask |
--   Brightness 2.595 and Mask | Contrast 0.355 by name. The amount goes through SetCustomPrimitiveDataFloat on the
--   weapon mesh, CPD[16..19] (BloodCoverageCustom) = k, the dryness on CPD[20] and [21] (BloodFadeG, BloodFadeB).
--   Every slot that holds the slot-0 material is swapped (GetNumMaterials, SLOTS_MAX), never the others. Before the
--   first write a weapon's CustomPrimitiveData and CustomPrimitiveDataInternal are read once (CPD_MAX values; one
--   sword_cpd 'baseline'): the restore writes those values back.
-- * A slot that already holds a game MID (IsA MaterialInstanceDynamic; run 20261102-f93cf2f: the left gauntlet's
--   MID_MI_BOSS_LuanShi_Cloth_UDIM_<n>, ChiZheCanJian's MID_MI_Boss_JianChi_Weapon_DuanJian_<n>): the donor by the
--   first name of its Parent chain that has one, our MID copies its parameters from that MID (its live values), the
--   MID is held on the player controller's keeper under 'sword.load' while ours is on (ue.hold: nothing of the game
--   holds it then, and a GC taking it would make an exact restore impossible), never destroyed, and the restore puts
--   that very object back, then ends the hold. Gone anyway (the game dropped it): its Parent goes back (sword_restore
--   to 'parent'). The game re-setting the slot is a sword_lost (our CPD back, the hold ended, no restore over it),
--   whether the watch or an exit finds it first.
--   Unknown until live: whether the game keeps writing its MID (a dissolve) while ours is on, and whether the
--   gauntlets' UDIM textures (T_BOSS_LuanShi_Cloth_*_UDIM, likely virtual textures) render through the DuoLuoJiangJun
--   donor's shader.
-- * Donors load at init and at each map's warm-up, one a frame under 'sword.load' (LoadAsset alone), each held on
--   the player controller's keeper (ue.hold); never on a bloody hit, and none while sword_blood is off (switched on
--   again: queued then). An apply whose donor still loads waits (at most DONOR_WAIT_S); a donor that failed fails it.
-- * The amount, game time (S.game_time: stops in pause and loads): a blow adds HIT or KILL to the weapon's k, quantized
--   to 1/Q and capped at kmax = clamp(0.35 + 0.65 x blood_amount / 3, 0.35, 1). k holds soul_blood_life_s after the
--   last blow (0: until the next map), then goes down over FADE_S (a write each 1/Q step, at most every STEP_S), then
--   the vanilla material goes back (one sword_fade record, why 'life'). The dryness: 0 for FRESH_S, then up to 1 over
--   DRY_S. A blow on a fading weapon starts from its k now. Each weapon keeps its own k and clock (sheathe, draw and
--   swaps keep the blood). Per blow: property reads and 1-2 CPD setter calls on the weapon's mesh; nothing is spawned or
--   loaded. The first blood on a weapon makes its MID (an object, no component) on the ticker, one apply a frame.
-- * Heal and death (bus lab_soul_heal from lab_blood's Health poll, queued; HEALQ_MAX): a full heal with wash_on_heal on
--   gives every bloody weapon heal_hold_s, then a fade over heal_fade_s on top of its life (k x the life's share x the
--   heal's share), then its material back (sword_fade why 'heal'); a second heal during it restarts nothing, a blow
--   ends it (new blood), wash_on_heal switched off keeps the share reached. A revive (a death and a respawn on the same
--   pawn) cleans every weapon at once (sword_restore why 'revive'), as a new pawn key does ('pawn'). One sword_heal
--   record per event.
-- * The watch every WATCH_S (real time, not while paused): GetMaterial(0) of each weapon of ours is still our MID, else
--   one sword_lost record, the custom primitive data we wrote goes back and the weapon's blood drops (the game set a
--   material: no restore over it). It also reads CPD[16..21] of every weapon with a baseline that is not in look A (one
--   sword_cpd 'game_wrote' per weapon).
-- * Exits: mod-off, the vanilla compare (MODOFF feature 'lab_sword', gameplay) and sword_blood off restore every weapon
--   at once (the slots' own materials, else nil: the mesh asset's; the custom primitive data read before), drop the
--   blood and the queued blows; lab_end and a pawn change restore too, lab_end stops the module for the session. Every
--   restore (an exit, a fade's end, a revive) reads each slot first and gives back only the slots that still hold our
--   MID: a slot the game set inside the watch's WATCH_S keeps the game's material, and slot 0 no longer ours makes the
--   restore a sword_lost (our CPD back, the hold ended, why: the restore's word). A map
--   load drops the state with no engine call (the weapons went with the old world). A hot reload (Ctrl+R) is
--   engine-free: a MID set then stays until the next map (U16).
-- * Guards: every native call through LAB.armed or LAB.hot under its own name (META.lab_risky, lab_linger,
--   data/lab_classes.lua): sword.read (the census, the sockets, the slot reads, the CPD reads, the watch), sword.load,
--   sword.mid, sword.copy, sword.mat, sword.amt (the by-name writes and read-backs on our MID), sword.cpd and
--   sword.restore (sword.byinfo is the test build's). LAB.hot proves a whole name on one answer, so the first call of
--   each job runs through LAB.armed; the census (GetAttachedActors' TArray out param, as lab_census) always runs armed.
--   A proven sword.read read runs bare (META.lab_hot_linger 0). Before each: LAB.pinned() (nil waits), SENT.is_disabled,
--   an inherited name after a stop, LAB.sig ('sig_pending' waits); a refusal writes one sword_refused per word and
--   name. A blow and an apply wait in their queue while a name they need waits. FAIL_MAX failures in a row stop a name
--   for the map (one sword_off record); a stopped sword.restore leaves the weapons as they are until the map load. No
--   apply runs while sword.restore is refused (its breaker, the sentinel, unpinned, its signature; its wait words make
--   the apply wait): the weapon's apply fails at once (one sword_apply err 'no_restore'), so no MID goes on and no game
--   MID is held that nothing could give back. A refused restore writes one sword_refused, no sword_restore.
-- * Records (forced, capped by LAB.CAPS): sword_donor {name, ok, ms, via, held, err}; sword_census {name, class, slot,
--   idx, armed, unarmed, root_parent, root_socket, mesh_socket, in_hand, hidden, visible, recv, nmat, mat, chain, n, why,
--   no_blood}
--   once per weapon and state; sword_blow (the first 40) {kind, origin, dir, bullet, slot, by, weapons, k0, k1, wrote,
--   us, skip}; sword_apply {variant, weapon, donor, orig, parent, nmat, slots, copy, set, back, game_mid, held, wrote,
--   ms, err}; sword_param {variant, name, how, ok, err, read} once per look, name and answer; sword_cpd; sword_fade
--   {weapon, variant, k, why, held_s, fade_s, restored}; sword_restore {weapon, why, variant, ok, back, to, gone, err};
--   sword_lost
--   {weapon, variant, now, cpd_back, why (the restore that found it; none from the watch)}; sword_heal {rule, weapons, hold_s, fade_s}; sword_cost at lab_end and at a map
--   load {why, blows, writes, us_mean, us_max, census_n, census_ms_max, apply_ms_max}; sword_refused, sword_off.
--   Counters (published at 0): sword_blows, sword_writes, sword_apply, sword_apply_fail, sword_restores, sword_lost,
--   sword_skip_avatar, sword_skip_shachi (a Sha-Qi blow with no Sha-Qi weapon in hand), sword_skip_notpawn,
--   sword_skip_noweapon (a main blow with no main weapon in hand), sword_skip_origin (another origin, or none on a
--   bullet that is no execution), sword_skip_off (blood effects off).
-- API: W.extend(ext) (lab_sword_looks: looks, donors, names, a ticker step and a down hook) and W.x() (the helpers it
--   uses); status(); lifecycle init(A) warm() reset(reason) shutdown().
-- What the mock cannot prove: the look in game, whether the game re-sets weapon materials, the PSO flicker on the
--   first swap, whether Soul's weapons attach at the DisplayData sockets in every stance, native faults.
local BUS = require('core.bus')
local S = require('core.sched')
local MODOFF = require('core.modoff')
local C = require('core.config')
local SENT = require('core.sentinel')
local ue = require('adapter.ue')
local LAB = require('lab_probe')
local CEN = require('lab_census')

local function obj_path(dir, leaf) return dir .. leaf .. '.' .. leaf end
local CH = '/Game/PBZContent/Characters/'

local W = {
    FEATURE = 'lab_sword', LOOK = 'A',
    HIT = 0.2, KILL = 0.35, Q = 16, K_LO = 0.35, K_HI = 1.0, AMOUNT_REF = 3.0,
    SNAP_BACK = { hit = 1, kill = 3 },
    FADE_S = 30, STEP_S = 0.25, FRESH_S = 20, DRY_S = 40,
    CENSUS_S = 2, WATCH_S = 3, DONOR_WAIT_S = 30, ATTACHED_MAX = 16, SLOTS_MAX = 8, CPD_MAX = 32, CHAIN_MAX = 6,
    BLOWS_FRAME = 8, BLOWQ_MAX = 64, HEALQ_MAX = 8, FAIL_MAX = 3, ERR_CHARS = 160, EPS = 1e-3,
    WEAPON = '/Script/PBZCombatAsset.WeaponActorBase',
    MID = '/Script/Engine.MaterialInstanceDynamic',
    -- the slot tags in lower case: run 20261102-f93cf2f read 'Weapon.Slot.Main' and 'Weapon.Slot.Shachi'; the spike's
    -- 'Weapon.Slot.ShaChi' never matched, so its 10 Sha-Qi blows were skipped (sword_skip_shachi)
    SLOTS = { ['weapon.slot.main'] = 'main', ['weapon.slot.shachi'] = 'shachi' },
    -- the materials whose dissolve layer hides the weapon and that no donor matches (header; scratch/swordblood
    -- work/tables.md): a weapon over one of them gets no blood
    NO_BLOOD_MAT = { MI_NPC_MuTianMiao_Sword = true, MI_EliteBoss_HookMan_Hook_Hun = true },
    CPD_COVER = { 16, 17, 18, 19 }, CPD_FADE = { 20, 21 },
    MASK = { { 'MaskTiling', 0.394 }, { 'Mask | Brightness', 2.595 }, { 'Mask | Contrast', 0.355 } },
    NAMES = { 'sword.read', 'sword.load', 'sword.mid', 'sword.copy', 'sword.mat', 'sword.amt', 'sword.cpd',
        'sword.restore' },
    BLOW_NAMES = { 'sword.read', 'sword.amt', 'sword.cpd' },
    COUNTERS = { 'sword_blows', 'sword_writes', 'sword_apply', 'sword_apply_fail', 'sword_restores', 'sword_lost',
        'sword_skip_avatar', 'sword_skip_shachi', 'sword_skip_notpawn', 'sword_skip_noweapon', 'sword_skip_origin',
        'sword_skip_off' },
    CAPS = { sword_census = 24, sword_blow = 40, sword_apply = 40, sword_param = 60, sword_donor = 24, sword_cpd = 24,
        sword_fade = 40, sword_restore = 60, sword_lost = 20, sword_refused = 20, sword_off = 20, sword_heal = 20 },
}
-- Look A's donors by key (object paths '<package>.<leaf>'; scratch/swordblood work/paths.txt and tech/out/bloodmics.json)
W.DONOR = {
    dacaidao = obj_path(CH .. 'Monster/FemaleThug/Material/', 'MI_Monster_FemaleThug_DaCaiDao'),
    hoe = obj_path(CH .. 'Monster/FemaleThug/Material/', 'MI_Monster_FemaleThug_Hoe'),
    shield = obj_path(CH .. 'Boss/ShouMenRenZhuoBi/Material/', 'MI_Boss_ShouMenRenTuoBI_Shield'),
    duoluo = obj_path(CH .. 'Boss/DuoLuoJiangJun/Material/', 'MI_Boss_DuoLuoJiangJun_Weapon'),
}
W.DONOR_ORDER = { 'shield', 'duoluo', 'dacaidao', 'hoe' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes)
local N = {}
local F = {
    {"/Script/PBZCombatAsset.WeaponActorBase", "WeaponMesh"},
    {"/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh", "Slot"},
    {"/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh", "WeaponDisplayIndex"},
    {"/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh", "DisplayData"},
    {"/Script/SGameCombatSystem.WeaponDisplayData", "ArmedSocket"},
    {"/Script/SGameCombatSystem.WeaponDisplayData", "UnarmedSocket"},
    {"/Script/GameplayTags.GameplayTag", "TagName"},
    {"/Script/Engine.Actor", "RootComponent"},
    {"/Script/Engine.Actor", "bHidden"},
    {"/Script/Engine.SceneComponent", "AttachParent"},
    {"/Script/Engine.SceneComponent", "AttachSocketName"},
    {"/Script/Engine.SceneComponent", "bVisible"},
    {"/Script/Engine.PrimitiveComponent", "bReceivesDecals"},
    {"/Script/Engine.PrimitiveComponent", "CustomPrimitiveData"},
    {"/Script/Engine.PrimitiveComponent", "CustomPrimitiveDataInternal"},
    {"/Script/Engine.CustomPrimitiveData", "Data"},
    {"/Script/Engine.MaterialInstance", "Parent"},
}
W.N, W.F = N, F

local A, X = nil, nil
local function copy_list(l) local o = {} for i, v in ipairs(l or {}) do o[i] = v end return o end
local function copy_map(m) local o = {} for k, v in pairs(m or {}) do o[k] = v end return o end
local function new_cost()
    return { blows = 0, writes = 0, us_sum = 0, us_max = 0, census_n = 0, census_ms_max = 0, apply_ms_max = 0 }
end
local function new_state()
    return { init = false, ended = false, end_due = false, variant = W.LOOK, looks = copy_map(W.LOOKS),
        donor = copy_map(W.DONOR), donor_order = copy_list(W.DONOR_ORDER), names = copy_list(W.NAMES),
        blow_names = copy_list(W.BLOW_NAMES), ext = nil,
        pawn = nil, pawn_key = nil, pawn_in = nil, weapons = {}, census_t = nil, logged = {}, blowq = {}, dropped = 0,
        healq = {}, wash = nil, applyq = {}, donors = {}, loadq = {}, fails = {}, off = {}, refused = {}, params = {},
        down = nil, watch_t = nil, sig_ok = {}, sig_done = false, job_ok = {}, cost = new_cost(), blow_full = false,
        life_s = 0, hold_s = 0, hfade_s = 0, heal_on = true, set_gen = nil, blood_gen = nil, blood_off = false }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or os.clock() end
local function gtime() return S.game_time or 0 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function rnd(v, d) local m = 10 ^ (d or 3) return num(v) and math.floor(v * m + 0.5) / m or nil end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function q(v) return math.floor(clamp(v, 0, 1) * W.Q + 0.5) / W.Q end
local function text(s)
    s = tostring(s)
    return #s > W.ERR_CHARS and s:sub(1, W.ERR_CHARS) or s
end
local function name_text(v)
    local s = ue.str(v)
    if s == nil or s == '' or s == 'None' then return nil end
    return s
end
local function class_of(o) local f = ue.full(o) return f and f:match('^(%S+) ') or 'unread' end
local function sorted_weapons()
    local out = {}
    for _, w in pairs(st.weapons) do out[#out + 1] = w end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end
local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- ---------- settings (core/config.lua, on the tick after a change) ----------
-- A seconds knob (soul_blood_life_s, heal_hold_s, heal_fade_s): a number 0 or more, else its default (as lab_blood)
local function knob_s(s, k)
    local v = tonumber(s[k])
    if num(v) and v >= 0 then return v end
    v = tonumber(C.DEFAULTS[k])
    return num(v) and v >= 0 and v or 0
end
-- The heal fade's share of k at game time g (1 before its start, 0 from its stop)
local function heal_f(w, g)
    local h = w.heal
    if not h then return 1 end
    if g >= h.stop then return 0 end
    if g <= h.start then return 1 end
    return (h.stop - g) / (h.stop - h.start)
end
-- Read again only when C.gen() moved (a settings change), which is also the only time wash_on_heal can turn off
local function settings_step()
    local gen = C.gen()
    if st.set_gen == gen then return end
    st.set_gen = gen
    local ok, s = pcall(C.get)
    if not ok or type(s) ~= 'table' then s = {} end
    st.life_s, st.hold_s, st.hfade_s = knob_s(s, 'soul_blood_life_s'), knob_s(s, 'heal_hold_s'), knob_s(s, 'heal_fade_s')
    local on = s.wash_on_heal ~= false
    if st.heal_on and not on then                       -- switched off: a running heal fade keeps the share it reached
        local g = gtime()
        for _, w in pairs(st.weapons) do
            if w.heal and g < w.heal.stop then w.kh, w.heal = w.kh * heal_f(w, g), nil end
        end
    end
    st.heal_on = on
end

-- ---------- guards: refusals, the breaker, the guarded calls ----------
local WAIT = { pin_wait = true, sig_pending = true }
local function refused(word, name)
    local k = tostring(word) .. '|' .. tostring(name)
    if st.refused[k] then return end
    st.refused[k] = true
    LAB.rec('sword_refused', { why = word, name = name }, true)
end
local function failed(name, err)
    local n = (st.fails[name] or 0) + 1
    st.fails[name] = n
    if n >= W.FAIL_MAX and not st.off[name] then
        st.off[name] = true
        LAB.rec('sword_off', { name = name, fails = n, err = text(err) }, true)
    end
end
-- The word that refuses name now, or nil; WAIT words ask again later
local function refusal(name)
    if st.off[name] then return 'breaker' end
    local p = LAB.pinned()
    if p == nil then return 'pin_wait' end
    if p ~= true then return 'unpinned' end
    if SENT.is_disabled(name) then return 'disabled' end
    if LAB.inherited(name) and not LAB.inherit_ok() then return 'inherit_off' end
    local okc, ok, why = pcall(LAB.sig, name)
    if not okc then return 'sig' end
    if ok ~= true then return why == 'sig_pending' and 'sig_pending' or 'sig' end
    return nil
end
-- fn under LAB.hot or LAB.armed: its answer (never nil on success) | nil, why, wait (true: ask again later), refused
-- (true: the ladder refused name and fn never ran; false: fn failed)
local function guarded(how, name, fn, ...)
    local word = refusal(name)
    if word then
        if not WAIT[word] then refused(word, name) end
        return nil, word, WAIT[word] == true, true
    end
    local r, err = how(name, fn, ...)
    if r == nil then
        failed(name, err)
        return nil, text(err or 'no answer'), false, false
    end
    st.fails[name] = 0
    return r
end
-- LAB.hot proves a whole name on one answer; the spec arms the first call of each sentinel, so the first call of each
-- job runs through LAB.armed and only a job that answered once goes through LAB.hot (one name runs several jobs)
local function hot(name, fn, ...)
    if st.job_ok[fn] then return guarded(LAB.hot, name, fn, ...) end
    local r, err, wait, no = guarded(LAB.armed, name, fn, ...)
    if r ~= nil then st.job_ok[fn] = true end
    return r, err, wait, no
end
local function armed(name, fn, ...) return guarded(LAB.armed, name, fn, ...) end
-- true when none of names waits (a refusal that is no wait lets the step run: its guarded call records it), and the
-- word that refuses want (one of names) then, so want is asked once
local function ready(names, want)
    local ww = nil
    for _, name in ipairs(names) do
        local word = refusal(name)
        if word ~= nil and WAIT[word] then return false end
        if name == want then ww = word end
    end
    return true, ww
end
-- Every name's signature asked until each answers (LAB.sig checks one new path a frame over every caller), so the first
-- blow and the first apply find their names ready
local function sig_step()
    if st.sig_done then return end
    for _, name in ipairs(st.names) do
        if not st.sig_ok[name] then
            local word = refusal(name)
            if word ~= nil and WAIT[word] then return end
            st.sig_ok[name] = true
        end
    end
    st.sig_done = true
end

-- ---------- reads (inside 'sword.read') ----------
local function chain_of(m)
    local out, cur = {}, m
    for _ = 1, W.CHAIN_MAX do
        local p = ue.prop(cur, 'Parent')
        if not ue.valid(p) then break end
        out[#out + 1] = ue.name(p) or '?'
        cur = p
    end
    return out
end
local function chain_kind(chain)
    local char = false
    for _, n in ipairs(chain or {}) do
        if n:find('MAI_Equipment', 1, true) then return 'equip' end
        if n == 'MAI_Character' then char = true end
    end
    if char then return 'char' end
    return nil
end
-- 'dissolve' when the slot-0 material or a name of its chain (a game MID's MIC) is in W.NO_BLOOD_MAT, else nil
local function no_blood_of(mat, chain)
    if W.NO_BLOOD_MAT[mat] then return 'dissolve' end
    for _, nm in ipairs(chain or {}) do
        if W.NO_BLOOD_MAT[nm] then return 'dissolve' end
    end
    return nil
end
-- Where a weapon sits now: the root's socket (else the mesh's), shown, in hand (header); census: also the fields only
-- the sword_census record reads (root_parent, root_socket, mesh_socket)
local function hand_view(a, m, kind, armed_s, census)
    local root = ue.prop(a, 'RootComponent')
    local rs, ms = name_text(ue.prop(root, 'AttachSocketName')), name_text(ue.prop(m, 'AttachSocketName'))
    local sock = rs or ms
    local hidden, visible = ue.prop(a, 'bHidden'), ue.prop(m, 'bVisible')
    local shown = hidden ~= true and visible ~= false
    local in_hand = armed_s ~= nil and sock == armed_s
    if kind == 'shachi' then in_hand = in_hand and shown end
    local h = { socket = sock, hidden = hidden, visible = visible, shown = shown, in_hand = in_hand }
    if census then
        h.root_parent, h.root_socket, h.mesh_socket = ue.name(ue.prop(root, 'AttachParent')) or 'none', rs or 'None',
            ms or 'None'
    end
    return h
end
local function read_weapon(a, pawn)
    local m = ue.prop(a, 'WeaponMesh')
    if not ue.valid(m) then return nil end
    local own = ue.owner(m)
    if own ~= nil and pawn ~= nil and ue.same(own, pawn) then return nil end      -- never a component of the pawn
    local slot = name_text(ue.prop(ue.prop(a, 'Slot'), 'TagName')) or 'unread'
    local dd = ue.prop(a, 'DisplayData')
    local armed_s, unarmed_s = name_text(ue.prop(dd, 'ArmedSocket')), name_text(ue.prop(dd, 'UnarmedSocket'))
    local okn, n = ue.call(m, 'GetNumMaterials')
    local okm, m0 = ue.call(m, 'GetMaterial', 0)
    m0 = okm and ue.p(m0) or nil
    local has0 = ue.valid(m0)
    local mat, chain = has0 and (ue.name(m0) or '?') or 'none', has0 and chain_of(m0) or {}
    local no_blood = no_blood_of(mat, chain)
    local kind = not no_blood and W.SLOTS[slot:lower()] or 'other'
    return { actor = a, mesh = m, name = ue.name(a) or '?', class = class_of(a), slot = slot, kind = kind,
        idx = ue.prop(a, 'WeaponDisplayIndex'), armed = armed_s, unarmed = unarmed_s,
        recv = ue.prop(m, 'bReceivesDecals'), nmat = okn and math.tointeger(n) or nil,
        mat = mat, chain = chain, no_blood = no_blood, hand = hand_view(a, m, kind, armed_s, true) }
end
-- The weapon actors attached to the pawn (lab_census's TArray-safe read); a TA refusal answers { err } (sword_refused),
-- a failed call or an unread count raises (a failure of sword.read)
local function census_job(pawn)
    local out = {}
    local n, at, why = CEN.attached(pawn, W.ATTACHED_MAX, function(a)
        if ue.valid(a) and ue.is_a(a, W.WEAPON) == true then
            local r = read_weapon(a, pawn)
            if r then out[#out + 1] = r end
        end
    end)
    if n then return { n = n, weapons = out } end
    if at == 'check' then return { err = why } end
    error(at == 'call' and text(why) or 'attached actors unread', 0)
end
-- A custom primitive data array of the mesh (CPD_MAX values at most; 'unread' when the read fails); lo, hi: only the
-- elements lo..hi (1-based) are read and set, the others stay nil
local function cpd_list(m, prop, lo, hi)
    local d = ue.prop(ue.prop(m, prop), 'Data')
    if d == nil then return 'unread' end
    local okn, n = pcall(function() return #d end)
    if not okn or type(n) ~= 'number' then return 'unread' end
    local out = {}
    for i = lo or 1, math.min(n, hi or W.CPD_MAX) do
        local v = d[i]
        out[i] = num(v) and rnd(v, 4) or 'unread'
    end
    return out
end
local function cpd_job(m)
    return { def = cpd_list(m, 'CustomPrimitiveData'), rt = cpd_list(m, 'CustomPrimitiveDataInternal') }
end
local function slice(list, lo, hi)
    if type(list) ~= 'table' then return list end
    local out = {}
    for i = lo, hi do out[#out + 1] = list[i + 1] or 'none' end
    return out
end
-- The value to restore at a CPD index: the one read before our first write, 0 when there was none
local function base_of(w, idx)
    local rt = w.base and w.base.rt
    local v = type(rt) == 'table' and rt[idx + 1] or nil
    if num(v) then return v + 0.0 end
    return 0.0
end
local function cpd_rec(w, why, vals)
    local b = w.base or {}
    LAB.rec('sword_cpd', { weapon = w.name, why = why, n_def = type(b.def) == 'table' and #b.def or b.def,
        n_rt = type(b.rt) == 'table' and #b.rt or b.rt, def16 = slice(b.def, 16, 21), rt16 = slice(b.rt, 16, 21),
        rt8 = type(b.rt) == 'table' and (b.rt[9] or 'none') or b.rt, now16 = vals and slice(vals, 16, 21) or nil },
        true)
end

-- ---------- the weapons: census, cache, in hand ----------
local function census_rec(w, why, n)
    local h = w.hand or {}
    local sig = table.concat({ w.name, tostring(h.in_hand), tostring(h.shown), tostring(h.socket), w.mat }, '|')
    if st.logged[sig] then return end
    st.logged[sig] = true
    LAB.rec('sword_census', { name = w.name, class = w.class, slot = w.slot, idx = w.idx, armed = w.armed or 'unread',
        unarmed = w.unarmed or 'unread', root_parent = h.root_parent, root_socket = h.root_socket,
        mesh_socket = h.mesh_socket, in_hand = h.in_hand, hidden = h.hidden, visible = h.visible, recv = w.recv,
        nmat = w.nmat, mat = w.mat, chain = w.chain, n = n, why = why, no_blood = w.no_blood }, true)
end
local function merge(list, why, n)
    for _, x in ipairs(list) do
        local key = ue.addr(x.actor)
        local w = key and st.weapons[key] or nil
        if w and not ue.live(w.keep) then w = nil end
        local mk = ue.keep_mod(x.mesh)
        if key and mk then
            if not w then
                w = { key = key, keep = ue.keep(x.actor), mesh = mk, kh = 0, t = nil }
                st.weapons[key] = w
            end
            w.name, w.class, w.slot, w.kind, w.idx = x.name, x.class, x.slot, x.kind, x.idx
            w.armed, w.unarmed, w.recv, w.nmat, w.hand = x.armed, x.unarmed, x.recv, x.nmat, x.hand
            if not w.app then w.mat, w.chain, w.no_blood = x.mat, x.chain, x.no_blood end
            census_rec(w, why, n)
        end
    end
end
-- One census (why 'press' | 'miss'): at most every CENSUS_S unless forced; true when it ran
local function census(why, force)
    local t = now()
    if not force and st.census_t and t - st.census_t < W.CENSUS_S then return false end
    local pawn = st.pawn and ue.live(st.pawn) or nil
    if not pawn then return false end
    st.census_t = t
    LAB.oneshot()
    local r, err, wait = armed('sword.read', census_job, pawn)      -- always armed: the TArray out param (lab_census)
    if wait then
        st.census_t = nil
        return false, err
    end
    local ms = (now() - t) * 1000
    local c = st.cost
    c.census_n = c.census_n + 1
    if ms > c.census_ms_max then c.census_ms_max = ms end
    if not r then return false, err end
    if r.err then refused(r.err, 'sword.read') return false end
    merge(r.weapons, why, r.n)
    return true
end
-- The cached weapons of a kind in hand now (their sockets and flags read again), sorted by name, and how: 'socket';
-- 'shown' when no weapon of the kind reads any socket (root and mesh both None: the attachment is not the one the
-- research inferred, U7), so the weapons of the kind that show stand in and the census records tell the real one.
-- mesh: each read weapon's live mesh by weapon, for this frame's writes only
local function hands_job(kind)
    local out, shown, sockless, mesh = {}, {}, true, {}
    for _, w in ipairs(sorted_weapons()) do
        if w.kind == kind then
            local a, m = ue.live(w.keep), ue.live_mod(w.mesh)
            if a and m then
                w.hand, mesh[w] = hand_view(a, m, w.kind, w.armed), m
                if w.hand.in_hand then out[#out + 1] = w end
                if w.hand.socket ~= nil then sockless = false end
                if w.hand.shown then shown[#shown + 1] = w end
            end
        end
    end
    if not out[1] and sockless then return { list = shown, by = 'shown', mesh = mesh } end
    return { list = out, by = 'socket', mesh = mesh }
end
-- No call while no weapon of the kind is cached (the census comes first): an empty read would spend the job's armed
-- first call on nothing. -> the weapons, how, their meshes (hands_job; nil with no weapon)
local function hands(kind)
    local any = false
    for _, w in pairs(st.weapons) do
        if w.kind == kind then any = true break end
    end
    if not any then return {}, nil end
    local r = hot('sword.read', hands_job, kind)
    if not r then return {}, nil end
    return r.list, r.by, r.mesh
end

-- ---------- the amount: k now, the dryness, the end of the blood ----------
local function k_max()
    local ok, s = pcall(C.get)
    local a = ok and type(s) == 'table' and tonumber(s.blood_amount) or nil
    if not num(a) then a = W.AMOUNT_REF end
    return clamp(W.K_LO + (W.K_HI - W.K_LO) * a / W.AMOUNT_REF, W.K_LO, W.K_HI)
end
-- The life's share of k at game time g: 1 for soul_blood_life_s after the last blow (always, at 0), then down over FADE_S
local function life_f(w, g)
    local life = st.life_s
    if life <= 0 then return 1 end
    local age = g - w.t
    if age <= life then return 1 end
    if age >= life + W.FADE_S then return 0 end
    return 1 - (age - life) / W.FADE_S
end
local function k_now(w)
    if not w.t then return 0 end
    local g = gtime()
    return q(w.kh * life_f(w, g) * heal_f(w, g))
end
local function dry_now(w)
    if not w.t then return 0 end
    local age = gtime() - w.t
    if age <= W.FRESH_S then return 0 end
    return q((age - W.FRESH_S) / W.DRY_S)
end
-- Why the blood of w is gone for good ('life' | 'heal'; 'none' without blood), or nil while it lasts
local function gone_why(w)
    if not w.t then return 'none' end
    local g = gtime()
    if st.life_s > 0 and g - w.t >= st.life_s + W.FADE_S then return 'life' end
    if w.heal and g >= w.heal.stop then return 'heal' end
    return nil
end

-- ---------- the sword_param records: once per look, name, route and answer ----------
-- true when this look, name and route have no record yet (the caller reads back once)
local function first(variant, name, how) return not st.params[variant .. '|' .. name .. '|' .. how] end
local function param_rec(variant, name, how, ok, err, read)
    local k = variant .. '|' .. name .. '|' .. how
    local seen = st.params[k]
    local word = ok and 'ok' or 'fail'
    if seen and seen[word] then return end
    st.params[k] = seen or {}
    st.params[k][word] = true
    LAB.rec('sword_param', { variant = variant, name = name, how = how, ok = ok == true, err = err, read = read }, true)
end

-- ---------- writes (setters on the game's mesh or on our MID) ----------
local function cpd_set(m, idxs, v)
    for _, i in ipairs(idxs) do
        local ok, err = ue.call(m, 'SetCustomPrimitiveDataFloat', i, v + 0.0)
        if not ok then error(text(err), 0) end
    end
    return #idxs
end
local function scalar_set(mid, name, v, back)
    local ok, err = ue.call(mid, 'SetScalarParameterValue', ue.fname(name), v + 0.0)
    if not ok then error(text(err), 0) end
    if not back then return { n = 1 } end
    local okg, got = ue.call(mid, 'K2_GetScalarParameterValue', ue.fname(name))
    return { n = 1, read = okg and rnd(got, 4) or 'unread' }
end
-- Values at CPD indexes of the weapon's mesh under 'sword.cpd', each marked for the restore: the calls made, or nil
local function cpd_write(w, m, idxs, v)
    local r = hot('sword.cpd', cpd_set, m, idxs, v)
    if r and w.app then for _, i in ipairs(idxs) do w.app.cpd[i] = true end end
    return r
end
-- By-name values on our MID ({ name, value, setter } each), each recorded once per look and answer: the calls made
local function named(variant, mid, list)
    local n = 0
    for _, p in ipairs(list) do
        local back = first(variant, p[1], 'name')
        local r, err = hot('sword.amt', p[3], mid, p[1], p[2], back)
        if back or not r then param_rec(variant, p[1], 'name', r ~= nil, err, r and r.read) end
        if r then n = n + r.n end
    end
    return n
end
local MASK = {}
for i, p in ipairs(W.MASK) do MASK[i] = { p[1], p[2], scalar_set } end
-- The amount of a weapon of ours written where its look reads it, only what changed since the last write: the number
-- of setter calls made. Nothing is resolved while k and the dryness read as last written (wk, wd); m: the weapon's
-- mesh when the caller holds it live already (a blow: hands_job), else it is resolved here
local function write(w, m)
    local app = w.app
    if not app then return 0 end
    local look = st.looks[app.variant]
    if not (look and look.write) then return 0 end
    local k, d = k_now(w), dry_now(w)
    if k == w.wk and d == w.wd then return 0 end
    m = m or ue.live_mod(w.mesh)
    if not m then return 0 end
    local n = look.write(X, w, m, k, d) or 0
    if n > 0 then
        st.cost.writes = st.cost.writes + n
        LAB.count('sword_writes', n)
    end
    return n
end
-- Look A: the amount in CPD[16..19], the dryness in CPD[20..21] (on the mesh: our MID is never read here)
local function write_a(_, w, m, k, d)
    local n = 0
    if k ~= w.wk then
        local r = cpd_write(w, m, W.CPD_COVER, k)
        if r then n, w.wk = n + r, k end
    end
    if d ~= w.wd then
        local r = cpd_write(w, m, W.CPD_FADE, d)
        if r then n, w.wd = n + r, d end
    end
    return n
end
-- The looks: pick (by_mat, then the chain: equip, char; or all) names the donor, own a MID over the weapon's own
-- material; copy the weapon's values into our MID; setup(X, w, mid) -> calls, k written; write(X, w, mesh, k, dry) ->
-- calls (k and the dryness now; a look that writes on our MID resolves it with X.mid(w), nil when gone); route: the
-- name write's calls run under (refused for good: no apply, apply_step)
W.LOOKS = {
    A = { pick = { by_mat = { MI_EliteMonster_JingYe_Armor = 'shield', MI_NPC_MoTian_Sword = 'duoluo',
        MI_BOSS_LuanShi_Cloth_UDIM = 'duoluo' }, equip = 'dacaidao', char = 'hoe' }, copy = true,
        setup = function(_, _, mid) return named('A', mid, MASK) end, write = write_a, route = 'sword.cpd' },
}

-- ---------- restore ----------
-- The material a slot gets back and its word: the one it held ('orig'); a game MID gone meanwhile: its Parent
-- ('parent'); else nil, which clears the override ('asset': the mesh asset's material)
local function back_of(app, i)
    local o = app.orig[i] and ue.live(app.orig[i]) or nil
    if o then return o, 'orig' end
    local p = app.game_mid and app.parent and ue.live(app.parent) or nil
    if p then return p, 'parent' end
    return nil, 'asset'
end
-- The slots of app that still hold our MID; lost: the name slot 0 holds now when that is not ours (the game set a
-- material since the last watch; 'none' when it reads nothing), else nil
local function ours_now(m, app)
    local mid, mine, lost = ue.live_mod(app.mid), {}, nil
    for _, i in ipairs(app.slots) do
        local ok, cur = ue.call(m, 'GetMaterial', i)
        cur = ok and ue.p(cur) or nil
        if mid ~= nil and cur ~= nil and ue.same(cur, mid) then
            mine[#mine + 1] = i
        elseif i == app.slots[1] then
            lost = ue.valid(cur) and (ue.name(cur) or '?') or 'none'
        end
    end
    return mine, lost
end
-- cpd_only: the custom primitive data back, the slots left as they are. Else each slot is read first and only a slot
-- that still holds our MID gets its material back (never one over a material the game set); slot 0 no longer ours (a
-- material the game set: sword_lost) answers lost, and the other slots still ours get theirs back with the data
-- (review: they kept our MID, untracked, for the rest of the map). A game MID's hold ends once its slots hold it again
-- (or the game set another material, or the weapon is gone)
local function restore_job(w, cpd_only)
    local app = w.app
    local m = ue.live_mod(w.mesh)
    if not m then
        if app.hold then ue.release(app.hold) app.hold = nil end
        return { gone = true }
    end
    local mine, lost = {}, nil
    if not cpd_only then
        mine, lost = ours_now(m, app)
        if lost then cpd_only = true end                -- ours_now never lists slot 0 then: the game's stays
    end
    local bad, to = nil, nil
    for _, i in ipairs(mine) do
        local o, word = back_of(app, i)
        if i == app.slots[1] then to = word end
        local ok, err = ue.call(m, 'SetMaterial', i, o)
        if not ok then bad = err end
    end
    local idxs = {}
    for i in pairs(app.cpd) do idxs[#idxs + 1] = i end
    table.sort(idxs)
    for _, i in ipairs(idxs) do
        local ok, err = ue.call(m, 'SetCustomPrimitiveDataFloat', i, base_of(w, i))
        if not ok then bad = err end
    end
    if bad ~= nil then error(text(bad), 0) end
    if app.hold then ue.release(app.hold) app.hold = nil end
    if cpd_only then return { cpd = #idxs, lost = lost } end
    local okg, m0 = ue.call(m, 'GetMaterial', 0)
    local o0 = back_of(app, 0)
    local back = false
    if okg and o0 ~= nil then back = ue.same(ue.p(m0), o0) end
    return { back = back, cpd = #idxs, to = to }
end
local function drop_blood(w) w.kh, w.t, w.heal = 0, nil, nil end
-- A material the game set on slot 0 (now: its name): one sword_lost record, the weapon no longer ours, its blood
-- dropped (why: the restore that found it, nil from the watch)
local function mark_lost(w, now_name, cpd_back, why)
    LAB.count('sword_lost')
    LAB.rec('sword_lost', { weapon = w.name, variant = w.app and w.app.variant, now = now_name, cpd_back = cpd_back,
        why = why }, true)
    w.app, w.wk, w.wd = nil, nil, nil
    drop_blood(w)
end
-- The vanilla material and data back (why: the record's word); keep: the weapon keeps its blood (a look change). true
-- when the weapon is no longer ours (restored, or lost: the game had set slot 0); false, 'wait' when the name waits
-- (ask again next frame); false when it is refused (one sword_refused per word) or failed
local function restore(w, why, keep)
    if not w.app then return true end
    local variant = w.app.variant
    local r, err, wait, no = armed('sword.restore', restore_job, w)
    if wait then return false, 'wait' end
    if no then return false end                         -- refused: guarded wrote its sword_refused, no sword_restore
    if r and r.lost then
        mark_lost(w, r.lost, true, why)
        return true
    end
    LAB.rec('sword_restore', { weapon = w.name, why = why, variant = variant, ok = r ~= nil, back = r and r.back,
        to = r and r.to, gone = r and r.gone, err = r == nil and err or nil }, true)
    if r == nil then return false end
    LAB.count('sword_restores')
    w.app, w.wk, w.wd = nil, nil, nil
    if not keep then drop_blood(w) end
    return true
end
local function restore_all(why)
    for _, w in ipairs(sorted_weapons()) do
        if w.app then restore(w, why, false) else drop_blood(w) end
    end
end
local function any_ours()
    for _, w in pairs(st.weapons) do if w.app then return true end end
    return false
end

-- ---------- apply: our MID on every slot that holds the weapon's own material ----------
local function needs_apply(w)
    if not st.looks[st.variant] or w.fail_v == st.variant or k_now(w) <= 0 then return false end
    return not (w.app and w.app.variant == st.variant)
end
local function queue_apply(w)
    for _, k in ipairs(st.applyq) do if k == w.key then return end end
    st.applyq[#st.applyq + 1] = w.key
    w.apply_t = now()
end
-- The donor key of a look for w: its slot-0 material by name, else the first name of its Parent chain that has one (a
-- game MID: MID_MI_BOSS_LuanShi_Cloth_UDIM_<n> takes MI_BOSS_LuanShi_Cloth_UDIM's), else the chain's kind; nil and
-- 'own' (a MID over the weapon's own material), 'no_look' or 'chain_unread'
local function donor_key(variant, w)
    local look = st.looks[variant]
    if not look then return nil, 'no_look' end
    if look.own then return nil, 'own' end
    local p = look.pick or {}
    if p.all then return p.all end
    local by = p.by_mat or {}
    if by[w.mat or ''] then return by[w.mat] end
    for _, n in ipairs(w.chain or {}) do if by[n] then return by[n] end end
    local ck = chain_kind(w.chain)
    if ck and p[ck] then return p[ck] end
    return nil, 'chain_unread'
end
local function slots_job(w)
    local m = ue.live_mod(w.mesh)
    if not m then error('mesh gone', 0) end
    local okn, n = ue.call(m, 'GetNumMaterials')
    n = okn and math.tointeger(n) or nil
    if not n or n < 1 then error('no material slot', 0) end
    local top = math.min(n, W.SLOTS_MAX) - 1
    local mats = {}
    for i = 0, top do
        local ok, mi = ue.call(m, 'GetMaterial', i)
        mi = ok and ue.p(mi) or nil
        if ue.valid(mi) then mats[i] = mi end
    end
    local orig = mats[0]
    if not orig then error('slot 0 holds no material', 0) end
    local slots, keeps = {}, {}
    for i = 0, top do
        if mats[i] and ue.same(mats[i], orig) then
            slots[#slots + 1] = i
            keeps[i] = ue.keep(mats[i])
        end
    end
    -- a game MID (the left gauntlet's MID_MI_BOSS_LuanShi_Cloth_UDIM_<n>): its Parent kept for a restore it outlives
    local game_mid = ue.is_a(orig, W.MID) == true
    local parent = game_mid and ue.prop(orig, 'Parent') or nil
    return { mesh = m, n = n, mats = mats, orig = orig, orig_name = ue.name(orig) or '?', slots = slots, keeps = keeps,
        game_mid = game_mid, parent = ue.valid(parent) and ue.keep(parent) or nil }
end
-- A material held on the player controller's keeper: a donor (load_job), or a game MID while ours is on its slots
-- (nothing else may hold it then; the GC must not take what the restore gives back). { id } | { err } ('no_host' or
-- ue.hold's word)
local function hold_job(o)
    local host = ue.first_of('PlayerController')
    if not host then return { err = 'no_host' } end
    local id, why = ue.hold(host, o, 'material')
    return { id = id, err = id == nil and tostring(why) or nil }
end
local function mid_job(m, parent)
    local kmat = ue.cdo('kmat')
    if not kmat then error('no KismetMaterialLibrary', 0) end
    local ok, mid = ue.call(kmat, 'CreateDynamicMaterialInstance', m, parent, ue.fname('None'), 0)
    if not ok then error(text(mid), 0) end
    mid = ue.p(mid)
    if not ue.valid(mid) then error('no MID', 0) end
    return mid
end
local function copy_job(mid, orig)
    local ok, err = ue.call(mid, 'K2_CopyMaterialInstanceParameters', orig, false)
    if not ok then error(text(err), 0) end
    return true
end
local function set_job(m, mid, slots, mats)
    local done = {}
    for _, i in ipairs(slots) do
        local ok, err = ue.call(m, 'SetMaterial', i, mid)
        if not ok then
            for _, j in ipairs(done) do ue.call(m, 'SetMaterial', j, mats[j]) end
            error(text(err), 0)
        end
        done[#done + 1] = i
    end
    local okg, m0 = ue.call(m, 'GetMaterial', 0)
    local back = false
    if okg then back = ue.same(ue.p(m0), mid) end
    return { back = back }
end
-- A failed apply of w (needs_apply skips w on this look from now on): counted, one sword_apply record rec
local function apply_fail(w, variant, rec)
    w.fail_v = variant
    LAB.count('sword_apply_fail')
    LAB.rec('sword_apply', rec, true)
end
local function apply(w, variant, donor, dkey)
    local look = st.looks[variant]
    local t0 = now()
    LAB.oneshot()
    local r = { variant = variant, weapon = w.name, donor = dkey or 'own' }
    local function done(err)
        r.ms = rnd((now() - t0) * 1000, 2)
        if (r.ms or 0) > st.cost.apply_ms_max then st.cost.apply_ms_max = r.ms end
        if err then
            r.err = text(err)
            apply_fail(w, variant, r)
            return false
        end
        LAB.count('sword_apply')
        LAB.rec('sword_apply', r, true)
        return true
    end
    local rd, err = hot('sword.read', slots_job, w)
    if not rd then return done('read: ' .. tostring(err)) end
    r.orig, r.nmat, r.slots = rd.orig_name, rd.n, #rd.slots
    if not w.base then
        w.base = hot('sword.read', cpd_job, rd.mesh) or { def = 'unread', rt = 'unread' }
        cpd_rec(w, 'baseline')
    end
    local mid
    mid, err = armed('sword.mid', mid_job, rd.mesh, donor or rd.orig)
    if not mid then return done('mid: ' .. tostring(err)) end
    r.parent = ue.name(donor or rd.orig) or '?'
    if look.copy then
        local c
        c, err = armed('sword.copy', copy_job, mid, rd.orig)
        r.copy = c ~= nil
        if not c then return done('copy: ' .. tostring(err)) end
    else
        r.copy = 'none'
    end
    local n, wk = 0, nil
    if look.setup then n, wk = look.setup(X, w, mid) end
    -- the game's MID: copied from above, held BEFORE ours goes on its slots (nothing of the game holds it then, and a
    -- GC taking it would make an exact restore impossible), never destroyed. No hold: no apply (review: the swap ran
    -- first and went on unheld)
    local hold = nil
    if rd.game_mid then
        local h, herr = armed('sword.load', hold_job, rd.orig)
        hold = h and h.id or nil
        r.game_mid, r.held = true, hold ~= nil
        if not hold then return done('hold: ' .. tostring(h and h.err or herr)) end
    end
    local s
    s, err = armed('sword.mat', set_job, rd.mesh, mid, rd.slots, rd.mats)
    if not s then
        if hold then armed('sword.load', function() return ue.release(hold) end) end   -- set_job put the slots back
        return done('set: ' .. tostring(err))
    end
    r.set, r.back = true, s.back
    w.app = { variant = variant, mid = ue.keep_mod(mid), slots = rd.slots, orig = rd.keeps, cpd = {}, hold = hold,
        game_mid = rd.game_mid, parent = rd.parent }
    w.wk, w.wd, w.wt = wk, nil, gtime()                 -- wk: the k a look's setup wrote (B's probe)
    r.wrote = (n or 0) + write(w)
    return done(nil)
end
-- One apply a frame: a weapon whose look changed is restored first (its blood kept), one whose donor still loads waits
-- at the back of the queue. None while sword.restore is refused (its breaker, the sentinel, unpinned, its signature):
-- our MID would stay on the weapon (and a game MID's hold with it) until the map load, whatever exit comes
local function apply_step()
    local key = st.applyq[1]
    if not key then return end
    local w = st.weapons[key]
    if not (w and needs_apply(w) and ue.live(w.keep)) then
        table.remove(st.applyq, 1)
        return
    end
    local go, rw = ready(st.names, 'sword.restore')      -- sword.restore's wait words make it wait too
    if not go then return end
    if rw ~= nil then
        table.remove(st.applyq, 1)
        refused(rw, 'sword.restore')
        apply_fail(w, st.variant, { variant = st.variant, weapon = w.name, err = 'no_restore' })
        return
    end
    -- nor while the look's amount route is refused (the sentinel switched it off, its breaker, its signature): our MID
    -- would go on with no blood ever written on it (review: sword.cpd disabled, the donor shader at zero coverage)
    local route = (st.looks[st.variant] or {}).route
    local cw = route and refusal(route) or nil
    if cw ~= nil then
        if WAIT[cw] then return end
        table.remove(st.applyq, 1)
        refused(cw, route)
        apply_fail(w, st.variant, { variant = st.variant, weapon = w.name, err = 'no_route' })
        return
    end
    if w.app then
        local ok, why = restore(w, 'look', true)
        if not ok and why ~= 'wait' then
            table.remove(st.applyq, 1)
            w.fail_v = st.variant
        end
        return
    end
    local variant = st.variant
    local dkey, dwhy = donor_key(variant, w)
    local donor = nil
    if dkey then
        local d = st.donors[dkey]
        if d == nil or d.state == 'queued' then
            if d == nil then
                st.donors[dkey] = { state = 'queued' }
                st.loadq[#st.loadq + 1] = dkey
            end
            table.remove(st.applyq, 1)
            if now() - (w.apply_t or now()) < W.DONOR_WAIT_S then st.applyq[#st.applyq + 1] = key return end
            apply_fail(w, variant, { variant = variant, weapon = w.name, donor = dkey, err = 'donor_wait' })
            return
        end
        donor = d.state == 'ok' and ue.live(d.keep) or nil
        if not donor then dwhy = 'no_donor ' .. dkey .. ' (' .. tostring(d.err or d.state) .. ')' end
    end
    table.remove(st.applyq, 1)
    if (dkey ~= nil and donor == nil) or (dkey == nil and dwhy ~= 'own') then
        return apply_fail(w, variant, { variant = variant, weapon = w.name, donor = dkey or 'none', err = dwhy })
    end
    apply(w, variant, donor, dkey)
end

-- ---------- donors: one load a frame ----------
local function queue_donors()
    for _, k in ipairs(st.donor_order) do
        if st.donors[k] == nil then
            st.donors[k] = { state = 'queued' }
            st.loadq[#st.loadq + 1] = k
        end
    end
end
local function load_job(path)
    local o, via = ue.asset(path, true)                 -- LoadAsset alone: no StaticFindObject (a miss ~23 ms, ue.find)
    if not o then return { ok = false, err = 'missing' } end
    local h = hold_job(o)
    return { ok = true, keep = ue.keep(o), via = via, held = h.id ~= nil, hold_err = h.err }
end
local function load_step()
    local key = st.loadq[1]
    if not key then return end
    local t0 = now()
    local r, err, wait = armed('sword.load', load_job, st.donor[key])
    if wait then return end
    table.remove(st.loadq, 1)
    LAB.oneshot()
    local d = st.donors[key] or {}
    st.donors[key] = d
    d.state = (r and r.ok) and 'ok' or 'failed'
    d.keep, d.err = r and r.keep or nil, r and r.err or err
    LAB.rec('sword_donor', { name = key, ok = d.state == 'ok', ms = rnd((now() - t0) * 1000, 2), via = r and r.via,
        held = r and r.held, hold_err = r and r.hold_err, err = d.state ~= 'ok' and text(d.err) or nil }, true)
end

-- ---------- blows: attribution (Lua only), then the amount ----------
local function is_exe(s)
    local d, b = s.bullet_dir, s.bullet
    return (type(d) == 'string' and d:find('/ExE$') ~= nil) or (type(b) == 'string' and b:sub(1, 3) == 'EB_')
end
-- The newest snapshot of the victim with owner_is_pawn true since t - SNAP_BACK; nil and 'not_pawn' | 'none'
local function pick(b)
    local since = b.t - (W.SNAP_BACK[b.kind] or 1)
    local best, other = nil, false
    for _, s in ipairs(LAB.snaps(b.key, since) or {}) do
        if s.owner_is_pawn == true then best = s elseif s.owner_is_pawn == false then other = true end
    end
    if best then return best end
    return nil, other and 'not_pawn' or 'none'
end
-- 'main' | 'shachi', the origin word; nil, the origin word, the skip ('avatar' | 'origin')
local function slot_of(s)
    local o = s.bd_origin
    if o == 'MainWeapon' then return 'main', o end
    if o == 'ShachiWeapon' then return 'shachi', o end
    if o == 'SourceAvatar' then return nil, o, 'avatar' end
    if o == nil and is_exe(s) then return 'main', 'ExE' end
    return nil, o or 'none', 'origin'
end
-- One sword_blow record (f, its skip word if any). f is nil once LAB.rec refused one (the cap, W.CAPS: the first 40):
-- no field is built from then on, and LAB.rec still sees (and counts) every refused record
local NO_FIELDS = {}
local function blow_rec(f, skip)
    if f and skip then f.skip = skip end
    if LAB.rec('sword_blow', f or NO_FIELDS, true) == false then st.blow_full = true end
end
local function blow(b)
    local t0 = now()
    local f = not st.blow_full and { kind = b.kind } or nil
    local s, why = pick(b)
    if not s then
        LAB.count('sword_skip_notpawn')
        return blow_rec(f, why)
    end
    local kind, origin, skip = slot_of(s)
    if f then f.origin, f.dir, f.bullet, f.slot = origin, s.bullet_dir, s.bullet, kind end     -- kind: nil on a skip
    if skip then
        LAB.count(skip == 'avatar' and 'sword_skip_avatar' or 'sword_skip_origin')
        return blow_rec(f, skip)
    end
    if not C.effect('blood') then
        LAB.count('sword_skip_off')
        return blow_rec(f, 'blood_off')
    end
    local got, by, mesh = hands(kind)
    if not got[1] and census('miss') then got, by, mesh = hands(kind) end
    if f then f.by = by end
    if not got[1] then
        LAB.count(kind == 'shachi' and 'sword_skip_shachi' or 'sword_skip_noweapon')
        return blow_rec(f, st.pawn and 'no_weapon' or 'no_pawn')
    end
    local add, kmax = b.kind == 'kill' and W.KILL or W.HIT, k_max()
    local wrote = 0
    if f then f.weapons, f.k0, f.k1 = {}, {}, {} end
    for _, w in ipairs(got) do
        local k0 = k_now(w)
        local k1 = math.max(k0, math.min(q(kmax), q(k0 + add)))
        w.kh, w.t, w.heal, w.fade_failed = k1, gtime(), nil, nil       -- new blood: a heal fade running ends
        if needs_apply(w) then queue_apply(w)
        elseif st.looks[st.variant] then wrote = wrote + write(w, mesh[w]) end
        if f then f.weapons[#f.weapons + 1], f.k0[#f.k0 + 1], f.k1[#f.k1 + 1] = w.name, k0, k1 end
    end
    local us = math.floor((now() - t0) * 1e6 + 0.5)
    local c = st.cost
    c.blows, c.us_sum = c.blows + 1, c.us_sum + us
    if us > c.us_max then c.us_max = us end
    LAB.count('sword_blows')
    if f then f.wrote, f.us = wrote, us end
    return blow_rec(f)
end
local function blow_step()
    if not st.blowq[1] or not ready(st.blow_names) then return end
    for _ = 1, W.BLOWS_FRAME do
        local b = table.remove(st.blowq, 1)
        if not b then return end
        blow(b)
    end
end
local down_why
local function on_bleed(e)
    if not st.init or st.ended or type(e) ~= 'table' or down_why() then return end
    if (e.kind ~= 'hit' and e.kind ~= 'kill') or e.key == nil then return end
    if #st.blowq >= W.BLOWQ_MAX then st.dropped = st.dropped + 1 return end
    st.blowq[#st.blowq + 1] = { kind = e.kind, key = e.key, t = now() }
end

-- ---------- heal and death (bus lab_soul_heal) ----------
local function on_heal(e)
    if not st.init or st.ended or type(e) ~= 'table' or #st.healq >= W.HEALQ_MAX then return end
    if e.rule == 'heal' or e.rule == 'revive' then st.healq[#st.healq + 1] = { rule = e.rule, key = e.key } end
end
local function bloody_names()
    local out = {}
    for _, w in ipairs(sorted_weapons()) do if w.app or (w.t and w.kh > 0) then out[#out + 1] = w.name end end
    return out
end
-- The queued events: a revive cleans every weapon at once (retried while sword.restore waits), a heal with
-- wash_on_heal on starts the heal fade of every bloody weapon that has none
local function heal_step()
    while st.healq[1] do
        local e = table.remove(st.healq, 1)
        if e.rule == 'revive' then
            LAB.rec('sword_heal', { rule = 'revive', key = e.key, weapons = bloody_names() }, true)
            st.wash = 'revive'
        elseif st.heal_on then
            local g, out = gtime(), {}
            for _, w in ipairs(sorted_weapons()) do
                if w.t and w.kh > 0 and not w.heal then
                    w.heal = { start = g + st.hold_s, stop = g + st.hold_s + st.hfade_s, hold = st.hold_s,
                        fade = st.hfade_s }
                    out[#out + 1] = w.name
                end
            end
            LAB.rec('sword_heal', { rule = 'heal', key = e.key, weapons = out, hold_s = st.hold_s, fade_s = st.hfade_s },
                true)
        end
    end
    if st.wash then
        restore_all(st.wash)
        if not any_ours() or st.off['sword.restore'] then st.wash = nil end
    end
end

-- ---------- fade, watch ----------
-- Nothing to do (and nothing allocated) while no weapon has blood or our MID
local function fade_step()
    local any = false
    for _, w in pairs(st.weapons) do
        if w.t or w.app then any = true break end
    end
    if not any then return end
    local g = gtime()
    for _, w in ipairs(sorted_weapons()) do
        local why = gone_why(w)
        if w.app then
            if why then
                if not w.fade_failed then                   -- a failed fade restore waits for an exit or a blow
                    local variant, kh, held, fade = w.app.variant, w.kh, st.life_s, W.FADE_S
                    if why == 'heal' and w.heal then held, fade = w.heal.hold, w.heal.fade end
                    local ok, wwhy = restore(w, why, false)
                    if wwhy ~= 'wait' then
                        LAB.rec('sword_fade', { weapon = w.name, variant = variant, k = kh, why = why, held_s = held,
                            fade_s = fade, restored = ok }, true)
                        w.fade_failed = not ok
                    end
                end
            elseif g - (w.wt or -math.huge) >= W.STEP_S then
                w.wt = g
                write(w)
            end
        elseif why and why ~= 'none' then
            drop_blood(w)                               -- blood that never reached the weapon (a failed apply)
        end
    end
end
local function watch_job(list)
    local out = {}
    for _, w in ipairs(list) do
        local m = ue.live_mod(w.mesh)
        if m then
            local e = { w = w }
            if w.app then
                local ok, m0 = ue.call(m, 'GetMaterial', 0)
                m0 = ok and ue.p(m0) or nil
                local mid = ue.live_mod(w.app.mid)
                e.ours = mid ~= nil and m0 ~= nil and ue.same(m0, mid)
                if not e.ours then e.now = ue.valid(m0) and (ue.name(m0) or '?') or 'none' end   -- sword_lost's now
            end
            if w.base and not w.cpd_seen and not (w.app and w.app.variant == 'A') then
                e.rt = cpd_list(m, 'CustomPrimitiveDataInternal', 17, 22)       -- CPD[16..21]: game_wrote, now16
            end
            out[#out + 1] = e
        end
    end
    return out
end
-- The game's own CPD[16..21] (only on a weapon not in look A): a value other than the one read before our first write
local function game_wrote(w, rt)
    if type(rt) ~= 'table' then return false end
    for i = 16, 21 do
        local v = rt[i + 1]
        if num(v) and math.abs(v - base_of(w, i)) > W.EPS then return true end
    end
    return false
end
local function watch_step()
    local t = now()
    if st.watch_t and t - st.watch_t < W.WATCH_S then return end
    st.watch_t = t
    local list = {}
    for _, w in ipairs(sorted_weapons()) do if w.app or (w.base and not w.cpd_seen) then list[#list + 1] = w end end
    if not list[1] then return end
    local r = hot('sword.read', watch_job, list)
    for _, e in ipairs(r or {}) do
        local w = e.w
        if e.ours == false and w.app then
            -- our custom primitive data goes back (the game's material may read it), the other slots still ours get
            -- their material back and a game MID's hold ends; the material the game set stays. A restore that failed
            -- (it raised: the breaker counts it) or waits keeps the weapon ours, so the next watch tries again; a
            -- refused one (the breaker, the sentinel) leaves the weapon as it is, as every refused restore does
            local need = next(w.app.cpd) ~= nil or w.app.hold ~= nil or #w.app.slots > 1
            local r, wait, no = nil, false, true
            if need then
                local _
                r, _, wait, no = armed('sword.restore', restore_job, w)
            end
            if not (need and r == nil and (wait or not no)) then
                local cpd_back = nil
                if need then cpd_back = r ~= nil end
                mark_lost(w, e.now, cpd_back, nil)
            end
        end
        if e.rt and game_wrote(w, e.rt) then
            w.cpd_seen = true
            cpd_rec(w, 'game_wrote', e.rt)
        end
    end
end

-- ---------- the ticker ----------
local function cost_rec(why)
    local c = st.cost
    if c.blows == 0 and c.census_n == 0 and c.writes == 0 then return end
    LAB.rec('sword_cost', { why = why, blows = c.blows, writes = c.writes,
        us_mean = c.blows > 0 and math.floor(c.us_sum / c.blows + 0.5) or nil, us_max = c.us_max,
        census_n = c.census_n, census_ms_max = rnd(c.census_ms_max, 2), apply_ms_max = rnd(c.apply_ms_max, 2) }, true)
end
local function pawn_step()
    local rec = st.pawn_in
    if not rec then return end
    st.pawn_in = nil
    if rec.key == st.pawn_key and st.pawn ~= nil then return end
    if st.pawn_key ~= nil then restore_all('pawn') end
    st.weapons, st.applyq, st.census_t, st.wash = {}, {}, nil, nil
    st.pawn, st.pawn_key = rec.pawn, rec.key
end
-- 'modoff' | 'vanilla' | 'sword_blood' (the setting off: read again only when C.gen() moved), or nil
down_why = function()
    if MODOFF.is_off() then return 'modoff' end
    if not MODOFF.enabled(W.FEATURE) then return 'vanilla' end
    local gen = C.gen()
    if st.blood_gen ~= gen then st.blood_gen, st.blood_off = gen, C.knob('sword_blood') == false end
    if st.blood_off then return 'sword_blood' end
    return nil
end
local function tick()
    if not st.init or st.ended then return end
    if st.end_due then
        restore_all('lab_end')
        cost_rec('lab_end')
        st.ended, st.blowq, st.applyq, st.loadq, st.healq = true, {}, {}, {}, {}
        return
    end
    pawn_step()
    local down = down_why()
    if down then
        st.blowq, st.healq = {}, {}
        if st.down ~= down then
            st.down, st.applyq, st.wash = down, {}, nil
            if st.ext and st.ext.down then st.ext.down(down) end
            restore_all(down)
        elseif any_ours() then
            restore_all(down)
        end
        return
    end
    if st.down then queue_donors() end                  -- back on (sword_blood off loaded none)
    st.down = nil
    if LAB.paused() then return end
    settings_step()
    sig_step()
    load_step()
    heal_step()
    if st.ext and st.ext.step then st.ext.step() end    -- the test build's look press (lab_sword_looks)
    blow_step()
    apply_step()
    fade_step()
    watch_step()
end

-- ---------- the test build's looks (lab_sword_looks) ----------
X = {
    EPS = W.EPS, MASK = MASK,
    state = function() return st end, down = function() return down_why() end,
    hot = hot, armed = armed, ready = ready, param_rec = param_rec, named = named, scalar_set = scalar_set,
    cpd_write = cpd_write, k_now = k_now, gtime = gtime, rnd = rnd,
    mid = function(w) return w.app and ue.live_mod(w.app.mid) or nil end,
    census = census, needs_apply = needs_apply, queue_apply = queue_apply, write = write, restore_all = restore_all,
    sorted = sorted_weapons,
}
-- The helpers a look plug-in uses (nil while inert)
function W.x() if st.init and not st.ended then return X end return nil end
-- A plug-in (lab_sword_looks): looks by variant, donors by key in donor_order (queued now), sentinel names (asked by
-- sig_step, needed by an apply), blow_names (needed by a blow too), step() run by the ticker before the blows and
-- down(why) at a down. -> true when taken
function W.extend(ext)
    if not st.init or st.ended or type(ext) ~= 'table' then return false end
    for k, look in pairs(ext.looks or {}) do st.looks[k] = look end
    for _, k in ipairs(ext.donor_order or {}) do
        local path = (ext.donors or {})[k]
        if path and not st.donor[k] then
            st.donor[k] = path
            st.donor_order[#st.donor_order + 1] = k
        end
    end
    for _, n in ipairs(ext.names or {}) do
        if not has(st.names, n) then st.names[#st.names + 1] = n end
    end
    for _, n in ipairs(ext.blow_names or {}) do
        if not has(st.blow_names, n) then st.blow_names[#st.blow_names + 1] = n end
    end
    st.sig_done, st.ext = false, ext
    if C.knob('sword_blood') ~= false then queue_donors() end
    return true
end

-- ---------- lifecycle ----------
local EVENTS = { 'lab_bleed', 'lab_soul_heal', 'lab_pawn', 'lab_end' }
-- Inert outside the beta (LAB.beta())
function W.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    for k, v in pairs(W.CAPS) do LAB.CAPS[k] = v end
    for _, k in ipairs(W.COUNTERS) do LAB.count(k, 0) end
    LAB.names(N, F)
    MODOFF.feature(W.FEATURE, { gameplay = true })      -- mod-off and the vanilla compare restore every weapon
    BUS.on('lab_bleed', W.FEATURE, on_bleed)
    BUS.on('lab_soul_heal', W.FEATURE, on_heal)
    BUS.on('lab_pawn', W.FEATURE, function(rec)
        if type(rec) == 'table' and rec.pawn ~= nil then st.pawn_in = rec end
    end)
    BUS.on('lab_end', W.FEATURE, function() st.end_due = true end)
    S.ticker(W.FEATURE, tick)
    settings_step()
    if C.knob('sword_blood') ~= false then queue_donors() end
    return true
end
-- After a map load (main.lua's staggered warm-up): the donors again, one a frame (none while sword_blood is off)
function W.warm()
    if st.init and not st.ended and C.knob('sword_blood') ~= false then queue_donors() end
end
-- A map load: no engine call (the weapons went with the old world; ue.reset_caches ended the donors' holds); the look
-- and a plug-in stay
function W.reset(reason)
    if not st.init or reason ~= 'map' then return end
    cost_rec('map')
    st.weapons, st.blowq, st.applyq, st.donors, st.loadq, st.healq, st.wash = {}, {}, {}, {}, {}, {}, nil
    st.fails, st.off, st.census_t, st.watch_t, st.down = {}, {}, nil, nil, nil
    st.pawn, st.pawn_key, st.pawn_in, st.cost = nil, nil, nil, new_cost()
end
function W.status()
    local n, ours, donors, off = 0, 0, {}, {}
    for _, w in pairs(st.weapons) do
        n = n + 1
        if w.app then ours = ours + 1 end
    end
    for k, d in pairs(st.donors) do donors[k] = d.state end
    for k in pairs(st.off) do off[#off + 1] = k end
    table.sort(off)
    return { init = st.init, ended = st.ended, variant = st.variant, weapons = n, ours = ours, queued = #st.blowq,
        applyq = #st.applyq, dropped = st.dropped, donors = donors, off = off, down = down_why(), life_s = st.life_s,
        ext = st.ext ~= nil }
end
-- Engine-free (Ctrl+R runs it off the game thread): a MID set stays until the next map (U16)
function W.shutdown()
    S.remove_ticker(W.FEATURE)
    for _, ev in ipairs(EVENTS) do BUS.off(ev, W.FEATURE) end
    st, A = new_state(), nil
end
return W
