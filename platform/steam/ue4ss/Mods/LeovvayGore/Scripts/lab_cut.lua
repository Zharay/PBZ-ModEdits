-- status: new in M1a A3.6 (offline only; TC-LAB-02 L0i, HD1-HD3 and GC rows decide) origin: kb:dismember-core#hide-a-limb-on-ue-modular-characters-hidebonebyname-on-every-leader-component-swzc
-- lab_cut.lua: L0i armed, the component ladder and the head commit (spec M1a A3.6; D4, D9, D27; ladder P1, P1b, P17,
-- P18; sections 3.1, 3.2, 3.5, 3.8, 3.9), Limbs and GCAP-a (A3.7; D15, section 3.6). Dev builds only, dev set 'lab02'
-- (META.dev_sets, main.lua); the probe and release never require it, and init stays inert (no listener, no ticker, no
-- record) unless LAB.cut_set(). Engine work only through adapter/ue.lua, adapter/ue_lab.lua and adapter/ue_spawn.lua
-- helpers and lab_cap and lab_piece (rule 7), each call under a section 3.4 name.
-- * P1 (lab.inherit.hide) on the first live corpse of a no-cut row (control 1; a later keep row when that one went),
--   in its lab_row tick, in one armed call: the per-mesh bone cache (each part of data/lab_pairs.lua: the cut, child and
--   stump bones by GetBoneIndex, the stump the live GetParentBone when the pair names none, the chain from the cut
--   bone's child down to the child), then on the body leader HideBoneByName(neck, PBO_None), IsBoneHiddenByName,
--   GetOwner, ComponentHasTag, GetParentBone(neck), GetSocketTransform(neck, 3), GetSocketTransform(child, 3) (down the
--   chain: the bone direction), UnHideBoneByName, IsBoneHiddenByName. ok: all nine returned, the hide read back true
--   and the unhide false. P1b (probe.static.GetTimeSeconds) in a later tick; then the l0i_armed record (section 3.1).
--   The player beta (LAB.beta(), beta port S2) runs neither, nor P17 and P18: their proofs come from LAB.seed.
-- * P17 (hide.comp) on the first GuiChai corpse of a no-cut row: each head component hidden, bHiddenInGame read, shown
--   again, read again, in one tick; P18 (hide.tag) on the same corpse at its next due tick: TAG appended through the
--   ComponentTags TArray userdata, the array read back, ComponentHasTag read, the saved names restored (Empty and
--   re-append) and read back. Each ladder step waits the linger of the last proof and a later frame (section 3.5).
-- * Heads (section 3.8), per bus lab_row 'heads': the stage in a later frame than the row (F0+2) under 'lab.cut.stage'
--   (the victim live on life corpse_life + 1, else refused 'stale' or 'gone'; a new mesh asset resolved first under
--   'lab.inherit.hide'; d from the cached chain; lab_cap reserve and build; lab_piece build and the Piece-end Cap when
--   Pieces are ready, else no Piece (HD2)); a failure destroys what was built, nothing hidden, refused with the step.
--   The commit in a later frame (F0+3) under 'lab.cut.head': DisableAllOptimizations (P10 proven), then lab_piece's
--   commit (pose copy, isolation, place) with this module's hide inside it: HideBoneByName on every leader with the
--   cut bone (PBO_None), GuiChai head components hidden and tagged (P18 proven), the Stump Cap shown, the Piece-end Cap
--   shown; then the Piece shown, simulated and launched. A failure after the hide unhides in the same call, shows the
--   components back, destroys the staged objects: refused 'commit_fail:<step>'. Then the linger group (section 3.4),
--   lab_outcome committed with commit_ms (from the death source event) and cut_ms (the commit frame), the cut record
--   and bus lab_cut_live. At most one stage and one commit per frame; nothing while paused; off refuses ('modoff').
-- * The player beta (LAB.beta(); docs/research/beta-dismemberment-plan.md BD10, replacing beta port S4; the pure parts,
--   the levers and the breaker live in lab_cut_beta.lua): every lab_row 'heads' queues its primary job (rank 1,
--   at_death): KB.first's part (docs/spec/fixes-0.2.2.md D3: a head or neck bone the head, an arm or leg bone its part;
--   a torso hit, a coarse reading or a poll death draws from its body band's weights with the kill's own generator,
--   src 'band' or 'weighted'; the head is never forced; META.beta_limbs false the head). The primary's stage plans
--   the kill once, after the bone cache (K.parts_of: that first part, the swing-plane partner, the head, then the fixed
--   order; one part a family, none inside another's chain, only parts the rig resolves, limbs only when
--   META.beta_limbs and limb_ready allow; a primary limb that fails falls back to the head; n from K.nparts: 1, the
--   heavy_parts or shaqi_parts knob on a heavy or Sha-Qi kill of the player's, at most max_parts), queues the extras
--   (rank 2..n; at most parts_per_s parts a real second, never the primary) and writes one forced cut_plan record.
--   jobs_tick takes the commit and the stage of the lowest rank, then the queue order: every victim's primary before any
--   extra, still one stage and one commit a frame. Only the primary sends lab_outcome; every refused job writes a forced
--   cut_fail with its rank. MC3: the optimizer goes off once per victim (a sibling commits 'shared'), and an unwind
--   turns it back on only when its own cut turned it off. The breaker: 2 counted failures in a row on one mesh asset
--   blacklist it (forced bad_asset; its later jobs refused 'bad_asset'), 5 in a row overall stop the beta's cuts for the
--   session (forced beta_off; refused 'beta_off'); counted: stage, cap_build, cap_attach, piece_build, piece_cap and
--   commit_fail:*, never gone, stale, modoff, gib_off, an extra's no_bone or same_chain, nor the breaker's own refusals;
--   a commit resets both. MC5: the stage reads the keep levers (DisableDeathDissol, 'Death Delay', DestroyAfterDead,
--   DestroyDelay; never written) into cut.kept and cut.levers; it skips BonesToRemove (K.btr) and the head-bone CVar.
--   A3: a head's hide set is its data/cut_classes.lua row (d.class_row): the head names required (one missing refuses
--   'no_head_comp:<name>'), the hair, hat_mask and glow names optional (cut.opt_missing); META.beta_scan adds every
--   SceneComponent attached into the cut subtree (cut.extra_hidden); all hidden and tagged at the commit and covered
--   by the unwind, the re-assert and the restore (one that will not hide is left out and logged; one the game had
--   hidden stays hidden on the unwind and the restore, and never falls: cut.pre_hidden). C4: the stage reads
--   cut.size (R from the bone lengths and the shoulder span times cap_scale, the roll from the actor's forward; the D8
--   bucket when a read fails) and the joint; MC4: at death cut.dir, speed and up. A head takes lab_gib's mode first
--   (cut.head_mode, hair, hold_show; 'gib_off' refuses, never counted): a 'burst' head builds no Piece (piece_why
--   'burst'); a committed head carries cut.gib (lab_gib.lua's header). K.reassert never shows a faded Cap.
-- * D27: bus lab_revive of a cut victim: the bones shown, the head components shown and their tags restored, the Stump
--   Cap destroyed (C4: the bone reads shown first), the Piece stays; lab_restore record, bus lab_cut_gone. A corpse
--   that goes (not LAB.alive: destroyed, 6-11 s after its death, or collected; checked every GONE_S, spec M1a 4.1
--   item 2) leaves K.cuts() with bus lab_cut_gone, the cut's gone_why set.
-- * Limbs (section 3.6, A3.7): each keep_only row queues its corpse; at lab_plan's quiet() and LIMB_GAP_S after the
--   last one, the first corpse lab_keep read drawn at 120 s takes two jobs of the head path (stage under
--   'lab.cut.stage', commit under 'lab.cut.limb'): the struck arm (else lowerarm_r) and the leg it names (else the calf
--   on its side, else calf_l), bone_src logged; generic_s Stump, meat Piece end (lab_cap, D8), the Piece launched
--   LIMB_SPEED uu/s along the bone; no lab_outcome (the kill went out with its row), a refused limb writes cut_fail.
--   Never a control. The route waits for L0i, P1, the Cap attach and meat classes and a settled Piece ladder.
-- * GCAP-a (D15, A3.7): bus lab_key 'lab_3' only (lab_1 and lab_2 spawn): the nearest heads cut within GCAP_CM of the
--   lab pawn whose pair has no rawhide yet; the forearm and the leader's world transform read under
--   'lab.inherit.hide' in the press frame; the next frame under 'lab.cut.gcap': tech_b's copy built hidden, posed and
--   scaled (ISO), tech_a's raw HideBoneByName read back per leader, the copy shown; GCAP_S game seconds later (never
--   while the mod is off: mod-off hides the copy through K.live) UnHideBoneByName and the copy destroyed, one rawhide
--   record per layout; a refused press writes rawhide ok false with its why ('gcap_done', 'pending', 'no_corpse' ...).
--   tech_b runs on the Piece classes only (D4, D30): lab_piece's body_copy route ready, else refused 'pieces_pending'
--   while its ladder runs, else tech_a alone ('tech_b: pieces_off'); the copy destroyed once P16 passed, else hidden.
-- * Gauges (section 3.2): cut_frame_ms_p95, _p99, _max (the commit call with its sentinel writes), cut_work_ms_p95
--   (inside the armed function), cold_cut_ms (the first commit after a map load); absent before the first commit.
-- API (section 3.9): cuts() the live committed cuts (lab_hold); reassert(cut) re-hides under 'hide.bone' and
--   'hide.comp' and answers the writes; cache(pair, asset) for tests; limb_parts(bone); live() (mod-off's list);
--   njobs() (the jobs not committed yet: lab_drops' warm-up and the slicer's probe and route wait for none);
--   the beta's pure part_of(bone), nparts(kill), parts_of(kill, cache, n, opts) and levers(actor);
--   lifecycle init(A) shutdown() status() reset().
-- What the mock cannot prove: native faults, UE4SS marshalling on dff435dd (FName and TArray userdata, the ParentBone
-- space), whether HideBoneByName on the leader really hides a GuiChai meshhead, real timing of the death source, the
-- look of the cut and its Caps (HD1b, GC1).
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local US = require('adapter.ue_spawn')
local META = require('meta')
local LAB = require('lab_probe')
local KB = require('lab_cut_beta')

local K = { TAG = 'NPCOpt.ForceInvisible', CHAIN_MAX = 8, P1Q = 8, COMPQ = 8, JOBS = 32, GONE_S = 1, SAMPLES = 256,
    BTR_MAX = 64, ERR_CHARS = 160, LINGER_S = 3, CVAR = 'PBZ.Character.EnableHeadBonesToRemove',
    SKINNED = '/Script/Engine.SkinnedMeshComponent', JOBS_BETA = 48 }      -- JOBS_BETA: the beta's queue (BD10)
-- The beta's pure parts and levers (lab_cut_beta.lua) on K too: the plan's names
K.part_of, K.parts_of, K.nparts, K.levers = KB.part_of, KB.parts_of, KB.nparts, KB.levers
-- After each committed head cut: one write arms the classes the commit used (section 3.4)
K.HEAD_GROUP = { 'hide.bone', 'hide.comp', 'hide.tag', 'cap.parent', 'piece.pose', 'piece.isolate', 'piece.phys' }
K.NO_CUT = { keep_ctrl = true, keep_only = true }
-- A commit the guard refused before it ran (a stop, a struck name, a failed arm write): its why, never a commit failure
K.NEVER_RAN = { inherit_off = 'stopped', disabled_by_sentinel = 'disabled', arm_write_failed = 'commit_fail:arm' }
-- Limbs (section 3.6, D8): one kept-only corpse per LIMB_GAP_S real seconds at a quiet moment, two cuts each; a limb
-- Piece is launched LIMB_SPEED uu/s outward along the bone (no lift, LIMB_UP) [P]; at most LIMBQ corpses wait
K.LIMB_GAP_S, K.LIMB_SPEED, K.LIMB_UP, K.LIMBQ = 2, 200, 0, 16
-- After each committed limb cut: one write arms the classes a limb commit used (section 3.4; no head component)
K.LIMB_GROUP = { 'hide.bone', 'cap.parent', 'piece.pose', 'piece.isolate', 'piece.phys' }
K.COMMIT_NAME = { heads = 'lab.cut.head', limbs = 'lab.cut.limb' }     -- the commit's route name per row (section 3.4)
-- The struck bone (lower case, a twist bone too) to its limb part: arms, then legs, each {prefix, part stem}
K.ARM, K.LEG = KB.ARM, KB.LEG
-- GCAP-a (D15): held GCAP_S game seconds [P], on the nearest heads corpse within GCAP_CM of the lab pawn, the forearm
-- GCAP_PART; tech_b's copy BESIDE the corpse (cm), its bone at ISO; one per layout of GCAP_PAIRS; GCAPQ presses wait
K.GCAP_S, K.GCAP_CM, K.GCAP_PART, K.ISO, K.BOX_HALF, K.MAT_MAX, K.GCAPQ = 30, 300, 'lowerarm_r', 0.001, 12, 16, 4
K.BESIDE, K.GCAP_PAIRS = { x = 0, y = 100, z = 0 }, { 'MaleThug', 'GuiChai' }
K.ACTOR, K.BOX = '/Script/Engine.Actor', '/Script/Engine.BoxComponent'
K.POSEABLE = '/Script/Engine.PoseableMeshComponent'

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua lab.inherit.hide, hide.*, lab.cut.*)
local N = {}
local F = {
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SkeletalMeshComponent", "BonesToRemove"},
    {"/Script/Engine.BoneReference", "BoneName"},
    {"/Script/Engine.ActorComponent", "ComponentTags"},
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
}
K.N, K.F = N, F

local A = nil
local function new_state()
    return { init = false, cache = {}, p1 = nil, p1q = {}, p1b = nil, l0i = nil, compq = {}, p17 = nil, last = nil,
        jobs = {}, cuts = {}, revq = {}, cvar = nil, cold = true, cold_ms = nil, frames = {}, work = {}, n = 0,
        staged = 0, committed = 0, refused = 0, restored = 0, gone = 0, end_due = false, ended = false, dropped = 0,
        last_err = nil, limbq = {}, limb_t = nil, limbs = 0, limb_fail = 0, limb_skip = 0, limb_why = nil,
        pawn_in = nil, pawn = nil,
        g = { q = {}, done = {}, open = nil, stage = nil, presses = 0, refused = 0, opened = 0 },
        -- the beta: the parts queued in the last real second, the session's breaker (lab_cut_beta), the plan counters,
        -- the scan's subtree verdicts per mesh asset
        rate = {}, brk = KB.breaker(), plans = 0, extras = 0, xdrop = 0, sub = {} }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function text(s)
    s = tostring(s)
    return #s > K.ERR_CHARS and s:sub(1, K.ERR_CHARS) or s
end
local function ms_since(t0) return math.floor((os.clock() - t0) * 10000 + 0.5) / 10 end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
local function pair_of(name) return (data('data.lab_pairs').pair or {})[name] or {} end
local function mod(name)                                -- a sibling lab module of the set (lab_cap, lab_piece)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
-- A proven class LAB.armed would run now: not struck, and not an inherited name after a stop (D4 refuses those)
local function usable(name)
    return LAB.proof(name) == true and not SENT.is_disabled(name) and not (LAB.inherited(name) and not LAB.inherit_ok())
end
local function v3(v) return v and { x = v.x, y = v.y, z = v.z } or nil end
local function r2(v) return v and { x = math.floor(v.x * 100 + 0.5) / 100, y = math.floor(v.y * 100 + 0.5) / 100,
    z = math.floor(v.z * 100 + 0.5) / 100 } or nil end
local function class_of(o) return (ue.full(o) or ''):match('^(%S+) ') or 'unread' end
-- A kept mod component (lab_cap keeps full names) or a plain keep record while it is the one kept
local function live(rec)
    if type(rec) ~= 'table' then return nil end
    if rec.full then return ue.live_mod(rec) end
    return ue.live(rec)
end

-- ---------- the per-mesh bone cache (P1's reads; a new mesh asset at a stage), and the bone direction ----------
-- The bones from bone's direct child down to desc (desc last), up through GetParentBone | nil, why
local function chain_to(mesh, bone, desc)
    local up, cur, lb = { desc }, desc, bone:lower()
    for _ = 1, K.CHAIN_MAX do
        local par, why = L.bone_parent(mesh, cur)
        if not par then return nil, why == 'no_parent' and 'not_child' or why end
        if par:lower() == lb then
            local down = {}
            for i = #up, 1, -1 do down[#down + 1] = up[i] end
            return down
        end
        up[#up + 1], cur = par, par
    end
    return nil, 'not_child'
end
-- The full name of a body leader's mesh asset ('unread' when none reads); the cache key: the pair and that name
local function asset_of(leader)
    local a = ue.prop(leader, 'SkinnedAsset')
    return tostring(ue.full(a) or ue.name(a) or 'unread')
end
function K.key(leader, pair) return tostring(pair) .. '|' .. asset_of(leader) end
-- Every part of the pair on the leader: { bone, child, stump, chain } or { why }. The entry, cached per key
function K.resolve(leader, pair)
    local key = K.key(leader, pair)
    local parts, n, names = {}, 0, {}
    for part in pairs(pair_of(pair).parts or {}) do names[#names + 1] = part end
    table.sort(names)
    local function first(list)
        for _, b in ipairs(list or {}) do if ue.has_bone(leader, b) then return b end end
    end
    for _, part in ipairs(names) do
        local p = pair_of(pair).parts[part]
        local bone, child = first(p.cut), first(p.child)
        local e = { why = 'no_bone' }
        if bone and child then
            local stump = first(p.stump) or L.bone_parent(leader, bone)
            local chain, why = chain_to(leader, bone, child)
            if not stump then e = { why = 'no_parent' }
            elseif not chain then e = { why = text(why) }
            else e, n = { bone = bone, child = child, stump = stump, chain = chain }, n + 1 end
        end
        parts[part] = e
    end
    local c = { key = key, pair = pair, parts = parts, n = n }
    st.cache[key] = c
    return c
end
function K.cache(key) return st.cache[key] end
local function qmul(a, b)
    return { w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w }
end
-- Section 3.8's d over a cached chain (no GetParentBone): the cut bone's parent-space rotation applied to the
-- normalized translation of the child in the cut bone's space. d, the cut bone's pose (parent space), the child's pose
-- in the cut bone's space | nil, why
function K.dir(leader, bone, chain)
    local a, wa = L.bone_parent_xform(leader, bone)
    if not a then return nil, wa end
    local b
    for i = #chain, 1, -1 do
        local x, wx = L.bone_parent_xform(leader, chain[i])
        if not x then return nil, wx end
        if b == nil then b = x else
            local s = x.scale
            local t = L.rotate(x.quat, { x = s.x * b.loc.x, y = s.y * b.loc.y, z = s.z * b.loc.z })
            b = { loc = { x = x.loc.x + t.x, y = x.loc.y + t.y, z = x.loc.z + t.z }, quat = qmul(x.quat, b.quat),
                scale = { x = s.x * b.scale.x, y = s.y * b.scale.y, z = s.z * b.scale.z } }
        end
    end
    if not b then return nil, 'no_chain' end
    local l = b.loc
    local n = math.sqrt(l.x * l.x + l.y * l.y + l.z * l.z)
    if n < 1e-4 then return nil, 'zero_len' end
    return L.rotate(a.quat, { x = l.x / n, y = l.y / n, z = l.z / n }), a, b
end

-- ---------- ladder spacing (section 3.5): a later frame than the last proof and past its linger ----------
local function spaced(t)
    local last = st.last
    return last == nil or (last.f < S.frame and t >= last.t + LAB.linger_s(last.name))
end
-- The corpse of a lab_row payload while it is live and on the life after its death; nil and why otherwise
local function corpse(d)
    if type(d) ~= 'table' then return nil, 'none' end
    local a, why = LAB.alive(d.victim or d.keep)
    if not a then return nil, why == 'stale' and 'stale' or 'gone' end
    if type(d.victim) == 'table' and d.corpse_life and d.victim.life ~= d.corpse_life + 1 then return nil, 'stale' end
    return a
end

-- ---------- P1: L0i armed in one tick (section 3.5), with the bone cache ----------
-- The nine calls on the body leader. r = { ok, returned (0-9), hidden_rb, unhidden_rb, same_tick, bone, parent,
-- child, lpos, dir, comp_class, owner_ok, has_tag, why }; the unhide runs whenever the hide ran
function K.p1(actor, pair)
    local f0, r = S.frame, { returned = 0 }
    local leader = ue.prop(actor, 'Mesh')
    if not ue.valid(leader) then r.why = 'no_leader' return r end
    r.comp_class = class_of(leader)
    local c = st.cache[K.key(leader, pair)] or K.resolve(leader, pair)
    local h = c.parts.head
    if not (h and h.bone) then r.why = 'bones:' .. tostring(h and h.why) return r end
    r.bone, r.child = h.bone, h.child
    local function ret(v) if v ~= nil then r.returned = r.returned + 1 end return v end
    local hid = ue.call(leader, 'HideBoneByName', ue.fname(h.bone), ue.PBO_NONE)
    if hid then r.returned = r.returned + 1 end
    local ok, err = pcall(function()
        r.hidden_rb = ret(L.is_bone_hidden(leader, h.bone))
        local o = ret(ue.owner(leader))
        r.owner_ok = o ~= nil and ue.same(o, actor)
        r.has_tag = ret(L.has_tag(leader, K.TAG))
        r.parent = ret(L.bone_parent(leader, h.bone))
        local a = ret(L.bone_parent_xform(leader, h.bone))
        r.lpos = a and r2(a.loc) or nil
        local d = ret((K.dir(leader, h.bone, h.chain)))
        r.dir = r2(d)
    end)
    if not ok then r.err = text(err) end
    if hid and ue.call(leader, 'UnHideBoneByName', ue.fname(h.bone)) then r.returned = r.returned + 1 end
    r.unhidden_rb = ret(L.is_bone_hidden(leader, h.bone))
    r.same_tick = S.frame == f0
    r.ok = r.returned == 9 and r.hidden_rb == true and r.unhidden_rb == false
    return r
end
local function p1_rec(f)
    local r = st.l0i
    if not r or r.done then return end
    r.done = true
    LAB.rec('l0i_armed', { returned = r.returned or 0, hidden_rb = r.hidden_rb, unhidden_rb = r.unhidden_rb,
        same_tick = r.same_tick == true, arraynum = r.arraynum == true, bone = r.bone, parent = r.parent,
        child = r.child, lpos = r.lpos, dir = r.dir, comp_class = r.comp_class, time_s = f.time_s or 'unread',
        ms = r.ms, id = r.id, pair = r.pair, owner_ok = r.owner_ok, has_tag = r.has_tag, err = r.err,
        why = f.why or r.why }, true)
end
-- The first queued corpse still live takes P1 (a gone one gives way to the next); a corpse whose leader lacks the
-- head bones too. The sig check first (refused: P1 never runs, no proof)
local function p1_tick(t)
    if st.p1 ~= nil or not st.p1q[1] then return end
    if LAB.proof('lab.inherit.hide') ~= nil then st.p1q = {} return end    -- proven already (a test's plant)
    local sig_ok, why = LAB.sig('lab.inherit.hide')
    if not sig_ok then
        if why == 'sig_mismatch' or why == 'sig_unknown' then st.p1, st.p1q = { skipped = why }, {} end
        return
    end
    while st.p1q[1] do
        local d = table.remove(st.p1q, 1)
        local actor = corpse(d)
        if actor then
            local inh, t0 = LAB.inherit_ok(), os.clock()
            local r, err = LAB.armed('lab.inherit.hide', K.p1, actor, d.pair)
            local ms = ms_since(t0)
            if type(r) == 'table' and r.why and r.returned == 0 and not err then
                st.p1_why = r.why                       -- no leader or no head bones here: the next corpse
            else
                r = type(r) == 'table' and r or { returned = 0 }
                r.err = r.err or (err ~= nil and text(err) or nil)
                r.arraynum = (inh and not LAB.inherit_ok()) or (type(err) == 'string'
                    and err:find(LAB.ARRAYNUM, 1, true) ~= nil)
                r.ok = r.ok == true and err == nil and not r.arraynum
                r.ms, r.id, r.pair, r.t = ms, d.id, d.pair, t
                st.p1, st.l0i, st.p1q = r, r, {}
                LAB.prove('P1', 'lab.inherit.hide', r.ok, { id = d.id, pair = d.pair, ms = ms, err = r.err or r.why,
                    returned = r.returned, hidden_rb = r.hidden_rb, unhidden_rb = r.unhidden_rb })
                return
            end
        end
    end
end
-- P1b: GameplayStatics:GetTimeSeconds in a later tick, spaced; then the l0i_armed record
local function p1b_tick(t)
    if st.p1 == nil or st.p1.skipped or st.p1b ~= nil or not spaced(t) then return end
    local name = 'probe.static.GetTimeSeconds'
    if SENT.is_disabled(name) then st.p1b = 'disabled' p1_rec({ why = 'p1b_disabled' }) return end
    local sig_ok, why = LAB.sig(name)
    if not sig_ok then
        if why == 'sig_mismatch' or why == 'sig_unknown' then st.p1b = why p1_rec({ why = 'p1b_' .. why }) end
        return
    end
    local t0 = os.clock()
    local v, err = LAB.armed(name, US.time_seconds)
    local ok = err == nil and type(v) == 'number'
    st.p1b = ok and 'ok' or 'fail'
    LAB.prove('P1b', name, ok, { ms = ms_since(t0), err = err ~= nil and text(err) or nil,
        time_s = ok and math.floor(v * 1000 + 0.5) / 1000 or 'unread' })
    p1_rec({ time_s = ok and math.floor(v * 1000 + 0.5) / 1000 or nil })
end

-- ---------- P17 and P18: the head components of a GuiChai (section 3.5) ----------
-- The head components data/lab_pairs.lua lists for the pair, found by name among the actor's skinned components (one
-- K2_GetComponentsByClass for every name): { {comp, name} } | nil, why ('no_head_comp:<name>')
function K.head_comps(actor, pair)
    local out, list = {}, nil
    for _, n in ipairs(pair_of(pair).head_comps or {}) do
        local hit
        list = list or ue.components(actor, K.SKINNED)
        for _, c in ipairs(list) do if ue.name(c) == n then hit = c break end end
        if not hit then return nil, 'no_head_comp:' .. n end
        out[#out + 1] = { comp = hit, name = n }
    end
    return out
end
-- P17 in one tick: each head component hidden, read, shown, read. { ok, comps = {name, hidden_rb, shown_rb}, why }
function K.p17(actor, pair)
    local hc, why = K.head_comps(actor, pair)
    if not hc or not hc[1] then return { why = why or 'no_head_comp' } end
    local r = { ok = true, comps = {} }
    for _, h in ipairs(hc) do
        local e = { name = h.name }
        local hid = ue.set_hidden(h.comp, true)
        e.hidden_rb = (L.comp_hidden(h.comp))
        local shown = ue.set_hidden(h.comp, false)
        e.shown_rb = (L.comp_hidden(h.comp))
        r.comps[#r.comps + 1] = e
        if not (hid and shown and e.hidden_rb == true and e.shown_rb == false) then r.ok = false end
    end
    return r
end
-- P18 in one tick: TAG appended, the names read back (count and names), ComponentHasTag, the saved names restored and
-- read back. { ok, comps = {name, n0, n1, names, has_tag, restored, err}, why }
function K.p18(actor, pair)
    local hc, why = K.head_comps(actor, pair)
    if not hc or not hc[1] then return { why = why or 'no_head_comp' } end
    local r = { ok = true, comps = {} }
    for _, h in ipairs(hc) do
        local c, e = h.comp, { name = h.name }
        local saved, ws = L.save_tags(c)
        if saved then
            e.n0 = #saved.names
            local added, wa = L.add_tag(c, K.TAG)
            local now_tags = L.save_tags(c)
            e.n1, e.names = now_tags and #now_tags.names or 'unread', now_tags and now_tags.names or 'unread'
            e.has_tag = L.has_tag(c, K.TAG)
            local okr, wr = L.restore_tags(c, saved)
            e.restored = okr == true and (L.tags_equal(c, saved)) == true
            e.err = (not added and wa) or (not okr and wr) or nil
            if not (added and e.n1 == e.n0 + 1 and e.has_tag == true and e.restored) then r.ok = false end
        else
            e.err, r.ok = ws, false
        end
        r.comps[#r.comps + 1] = e
    end
    return r
end
-- P17 on the first queued GuiChai corpse still live (P1 passed); P18 on the same corpse at its next spaced tick, or on
-- the next queued one when that corpse went. A step whose sig check refused is skipped (no proof)
K.COMP_STEPS = { { step = 'P17', name = 'hide.comp', run = K.p17 }, { step = 'P18', name = 'hide.tag', run = K.p18 } }
local function comp_tick(t)
    if LAB.proof('lab.inherit.hide') ~= true or not spaced(t) then return end
    local s = st.p17 or { i = 1 }
    st.p17 = s
    local step = K.COMP_STEPS[s.i]
    if not step or (s.d == nil and not st.compq[1]) then return end
    if SENT.is_disabled(step.name) or (step.step == 'P18' and LAB.proof('hide.comp') ~= true) then
        s.skipped, s.i = SENT.is_disabled(step.name) and 'disabled' or 'need:hide.comp', s.i + 1
        return
    end
    local sig_ok, why = LAB.sig(step.name)
    if not sig_ok then
        if why == 'sig_mismatch' or why == 'sig_unknown' then s.skipped, s.i = why, s.i + 1 end
        return
    end
    local actor = s.d and corpse(s.d) or nil
    while not actor and st.compq[1] do
        s.d = table.remove(st.compq, 1)
        actor = corpse(s.d)
    end
    if not actor then s.d = nil return end
    local t0 = os.clock()
    local r, err = LAB.armed(step.name, step.run, actor, s.d.pair)
    if type(r) == 'table' and r.why and r.comps == nil and err == nil then
        s.d = nil                                       -- no head component on this one: the next GuiChai
        return
    end
    local ok = err == nil and type(r) == 'table' and r.ok == true
    LAB.prove(step.step, step.name, ok, { id = s.d.id, pair = s.d.pair, ms = ms_since(t0),
        err = err ~= nil and text(err) or nil, comps = type(r) == 'table' and r.comps or nil })
    s.i = s.i + 1
end

-- ---------- Heads: the stage (section 3.8 F0+2) ----------
-- The outcome to lab_poll (one per job) and the tally. A limb job sends none (its kill went out with the keep_only
-- row): a limb that is not committed writes a forced cut_fail record (the base schema's event) instead. The beta's
-- death-time jobs end in lab_cut_beta's finish
local function finish(job, outcome, why, f)
    if job.done then return end
    job.done = true
    if job.at_death then return KB.finish(job, outcome, why, f, st) end
    if job.row == 'limbs' then
        if outcome ~= 'committed' then
            st.limb_fail = st.limb_fail + 1
            LAB.rec('cut_fail', { id = job.d.id, part = job.part, pair = job.d.pair, row = 'limbs',
                err = tostring(why or 'refused'), bone_src = job.bone_src }, true)
        end
        return
    end
    if outcome ~= 'committed' then st.refused = st.refused + 1 end
    f = f or {}
    BUS.emit('lab_outcome', job.d.id, { row = 'heads', outcome = outcome, why = why, commit_ms = f.commit_ms,
        actions = outcome == 'committed' and 1 or 0, cut_ms = f.cut_ms })
end
-- SkeletalMeshComponent.BonesToRemove (props:1841, TArray<FBoneReference>) as names, bounded by #; 'unread' on failure.
-- Each element is the struct itself (a TArray property's [i], LuaTArray.cpp:232-251), never a param: no ue.p (a struct
-- raises on the get it lacks, LuaUScriptStruct.cpp:181-185)
function K.btr(leader)
    local arr = ue.prop(leader, 'BonesToRemove')
    if arr == nil then return 'unread' end
    local out = {}
    local ok, err = pcall(function()
        for i = 1, math.min(#arr, K.BTR_MAX) do out[i] = ue.str(ue.prop(arr[i], 'BoneName')) or 'unread' end
    end)
    if not ok then ue.caught(err, 'lab', 'BonesToRemove') return 'unread' end
    return out
end
-- What a failed stage or a dropped job built goes: the Piece actor (its end Cap with it), then the Caps
local function drop_built(cut)
    local P, C = mod('lab_piece'), mod('lab_cap')
    if cut.piece and P then P.destroy(cut.piece, 'stage_fail') end
    if cut.slot and C then C.destroy(cut.slot) end
    return true
end
-- Inside 'lab.cut.stage': d, the leaders and BonesToRemove read, both Caps reserved and the Stump Cap built hidden,
-- the Piece built hidden with its end Cap when Pieces are ready. true | nil and cut.why (what was built is gone again)
function K.stage(cut)
    local C, P = mod('lab_cap'), mod('lab_piece')
    local function no(why, err)
        cut.why, cut.err = why, err ~= nil and text(err) or nil
        if cut.slot or cut.piece then drop_built(cut) end
        return nil
    end
    if not C then return no('no_cap') end
    local hc, wh, list = {}, nil, nil
    if cut.at_death and (cut.part == 'head' or META.beta_scan == true) then  -- the beta's one list: the row, the scan
        list = ue.components(cut.actor, KB.SCENE)
    end
    if cut.at_death and cut.part == 'head' then         -- A3: the class row's hide set (lab_cut_beta), keep records set
        hc, wh, cut.opt_missing = KB.hide_set(list, cut.class_row, pair_of(cut.pair).head_comps)
    elseif cut.part == 'head' then
        hc, wh = K.head_comps(cut.actor, cut.pair)      -- a limb hides no head component
    end
    if not hc then return no(wh) end
    for _, h in ipairs(hc) do                           -- full-name records: the commit, reassert and restore come later
        h.rec = h.rec or ue.keep_mod(h.comp)
        if not h.rec then return no('no_head_comp:' .. h.name) end
    end
    cut.head = hc
    local d, a, b = K.dir(cut.leader, cut.bone, cut.chain)
    if not d then return no('pose', a) end
    cut.d, cut.lpose, cut.cpose = d, a, b
    cut.leaders = {}
    local leaders = ue.leaders_with_bone(cut.actor, cut.bone)
    for _, m in ipairs(leaders) do cut.leaders[#cut.leaders + 1] = ue.name(m) end
    if not cut.leaders[1] then return no('no_leader') end
    if cut.at_death then                                -- MC5 levers, A3 scan, C4 size and roll: reads only
        cut.kept, cut.levers = KB.levers(cut.actor)
        if META.beta_scan == true then KB.scan(cut, list, leaders, st.sub) end
        local part = (pair_of(cut.pair).parts or {})[cut.part] or {}
        KB.size(cut, cut.span, tonumber(part.scale) or 1.0, C.z_to, now())
    end
    if not LAB.beta() then                              -- a struct-array read for the log only: never in the beta
        cut.btr = K.btr(cut.leader)
    end
    local slot, why = C.reserve(cut)
    if not slot then return no(why) end
    cut.slot = slot
    local ok, wb = C.build(slot, cut)
    if not ok then return no(wb == 'cap_attach' and 'cap_attach' or 'cap_build', wb) end
    local route = (pair_of(cut.pair).route == 'meshhead' and cut.part == 'head') and 'meshhead' or 'body_copy'
    if cut.head_mode == 'burst' then
        cut.piece_why = 'burst'                         -- lab_gib bursts the head: no flying-head Piece, the Stump Cap
    elseif P and P.ready(route) then
        local piece, wp = P.build(cut)
        if not piece then return no('piece_build', wp) end
        cut.piece = piece
        if cut.at_death then KB.launch(cut, piece.d)    -- MC4 at death (lab_cut_beta)
        elseif cut.row == 'limbs' then                  -- outward along the bone in world space (lab_piece's d) [P]
            cut.dir, cut.speed, cut.up = piece.d, K.LIMB_SPEED, K.LIMB_UP
        end
        local okp, wa = C.attach_piece(slot, piece)
        if not okp then return no(wa == 'cap_attach' and 'cap_attach' or 'piece_cap', wa) end
    else
        cut.piece_why = 'pieces_off'                    -- HD2: Heads without Pieces
    end
    if cut.at_death and not cut.piece then KB.launch(cut, cut.d_world) end  -- lab_gib's vel through P.velocity
    return true
end
-- The job's cut from the payload and the bone cache (a new mesh asset resolved first under 'lab.inherit.hide'); an
-- at_death primary plans its kill here, and a blacklisted mesh asset refuses an at_death job first. cut | nil, why
local function prepare(job, actor)
    local d = job.d
    local leader = ue.prop(actor, 'Mesh')
    if not ue.valid(leader) then return nil, 'no_leader' end
    local asset = asset_of(leader)
    job.asset = asset
    if job.at_death and st.brk.bad[asset] then return nil, 'bad_asset' end
    local key = tostring(d.pair) .. '|' .. asset          -- K.key
    local c = st.cache[key]
    if not c then
        local r, err = LAB.armed('lab.inherit.hide', K.resolve, leader, d.pair)
        if err ~= nil or type(r) ~= 'table' then return nil, 'bones' end
        c = r
    end
    if job.at_death and not job.planned and not KB.plan(job, c, st, now(), K.JOBS_BETA) then return nil, 'no_bone' end
    local part = job.part or 'head'
    local h = c.parts[part]
    if not (h and h.bone) then return nil, 'no_bone' end
    return { id = d.id, pair = d.pair, part = part, row = job.row or 'heads', actor = actor, victim = d.victim,
        key = d.victim and d.victim.key or d.key, corpse_life = d.corpse_life, leader = leader, bone = h.bone,
        child = h.child, stump = h.stump, chain = h.chain, sweep_dir = d.sweep_dir, attack_dir = d.attack_dir,
        death_t = d.death_t or d.t, bone_src = job.bone_src, asset = asset, at_death = job.at_death, rank = job.rank,
        nparts = job.nparts, tier = job.tier, class = d.class, class_row = d.class_row, kp = job.kp,
        span = { (c.parts.upperarm_l or {}).bone, (c.parts.upperarm_r or {}).bone } }
end
-- A route class whose sig check refused ends the kill; a refused guard reads as ok here (lab_plan asked them all by
-- now)
local function sig_word(name)
    local ok, why = LAB.sig(name)
    if not ok and (why == 'sig_mismatch' or why == 'sig_unknown') then return why end
    return nil
end
-- A class with a path still unchecked once this frame's path is paid (LAB.sig, one a frame: spec A3.2): its caller
-- waits a frame and asks again (never runs the class unchecked)
local function sig_pending(name)
    local ok, why = LAB.sig(name)
    return not ok and why == 'sig_pending'
end
-- The limb route (D30 for 'lab.cut.limb'): L0i armed and P1 proven, no stop, no commit name struck, the commit classes'
-- sigs not refused, and a Cap that attaches on both ends (a limb Piece end is always the meat cap, D8; P8 runs after
-- P7, so a passed nub route gives the Stump generic_s). true | false, why (the corpses wait)
local function limb_ready()
    if not LAB.l0i_ok() then return false, 'not_armed' end
    if LAB.proof('lab.inherit.hide') ~= true then return false, 'l0i' end
    for _, n in ipairs({ 'lab.cut.stage', 'lab.cut.limb', 'hide.bone' }) do
        if SENT.is_disabled(n) then return false, 'disabled' end
    end
    if sig_pending('lab.cut.stage') or sig_pending('lab.cut.limb') then return false, 'sig_pending' end
    local w = sig_word('lab.cut.stage') or sig_word('lab.cut.limb')
    if w then return false, w end
    local C = mod('lab_cap')
    if not C then return false, 'no_cap' end
    if not usable('cap.parent') then return false, 'cap_attach' end
    if not C.meat_ok() then return false, 'no_cap' end
    local P = mod('lab_piece')                          -- Pieces ready, their ladder ended or never started: else wait
    if P and not P.ready('body_copy') then
        local s = P.status()
        if s.done ~= true and (s.step ~= nil or s.corpse ~= nil) then return false, 'pieces_pending' end
    end
    return true
end
-- The beta's gates before an at_death job's stage: the breaker, then the limb route (an extra limb or a planned limb
-- primary waits on 'sig_pending' and is refused on any other word; an unplanned primary plans without limbs instead,
-- so a limb it struck falls back to the head). true | nil (the job waits) | false, why
local function beta_gate(job)
    if st.brk.off then return false, 'beta_off' end
    local ok, why = limb_ready()
    if not job.planned then
        job.limbs = META.beta_limbs == true and (ok or why == 'sig_pending')
        if why == 'sig_pending' and job.row == 'limbs' then return nil end
        return true
    end
    if job.row ~= 'limbs' or ok then return true end
    if why == 'sig_pending' then return nil end
    return false, why
end
local function stage_job(job)
    local actor, why = corpse(job.d)
    if job.revived then actor, why = nil, 'not_dead' end
    if not actor then return finish(job, 'refused', why) end
    if job.at_death then
        local go, wg = beta_gate(job)
        if go == nil then return end
        if not go then return finish(job, 'refused', wg) end
    end
    if sig_pending('lab.cut.stage') or sig_pending(K.COMMIT_NAME[job.row or 'heads'])
        or (st.cvar == nil and sig_pending('probe.cvar.PBZ.Character.EnableHeadBonesToRemove')) then
        return                                          -- the job stays 'row': a later frame stages it
    end
    local w = sig_word('lab.cut.stage') or sig_word(K.COMMIT_NAME[job.row or 'heads'])
    if w then return finish(job, 'refused', w) end
    local cut, wp = prepare(job, actor)
    if not cut then return finish(job, 'refused', wp) end
    if job.at_death then                                -- the plan may have turned a struck limb into the head
        if sig_pending(K.COMMIT_NAME[job.row]) then return end
        w = sig_word(K.COMMIT_NAME[job.row])
        if w then return finish(job, 'refused', w) end
    end
    if job.at_death and cut.part == 'head' then         -- lab_gib's head mode: 'gib_off' refuses (never counted)
        local mode, hair = KB.head_mode(cut.class_row, mod('lab_gib'))
        if not mode then return finish(job, 'refused', hair) end
        cut.head_mode, cut.hair, cut.hold_show = mode, hair, hair == 'keep' or nil
        job.head_mode, job.hair = mode, hair
    end
    if st.cvar == nil then                              -- the head-bone CVar once per session (section 3.8)
        if sig_word('probe.cvar.PBZ.Character.EnableHeadBonesToRemove') then
            st.cvar = 'unread'                          -- D17: a refused class never runs
        else
            local v, err = LAB.armed('probe.cvar.PBZ.Character.EnableHeadBonesToRemove', ue.cvar_int, K.CVAR)
            st.cvar = (err == nil and v ~= nil) and v or 'unread'
        end
    end
    local r, err = LAB.armed('lab.cut.stage', K.stage, cut)
    if err ~= nil then
        st.last_err = text(err)
        LAB.armed('lab.cut.stage', drop_built, cut)     -- a raised stage: what it built goes (a refused one built none)
        return finish(job, 'refused', err == 'inherit_off' and 'stopped' or 'stage')
    end
    if not r then return finish(job, 'refused', cut.why or 'stage') end
    job.cut, job.state, job.sf = cut, 'staged', S.frame
    st.staged = st.staged + 1
end

-- ---------- Heads: the commit (section 3.8 F0+3) ----------
-- A head component of the stage while its slot still holds it (D24: valid, same full name, same epoch; IsValid alone
-- passes a reused slot, refuted.md:112), else nil
local function head_comp(h) return h.rec and ue.live_mod(h.rec) or nil end
-- MC3: a committed cut of the same victim (key and corpse life) turned the optimizer off, or shares that
local function optim_off(cut)
    for _, c in ipairs(st.cuts) do
        if c ~= cut and c.key == cut.key and c.corpse_life == cut.corpse_life
            and (c.optim == 'ok' or c.optim == 'shared') then return true end
    end
    return false
end
-- Undo inside the commit call: the bones shown, the head components shown (never one the game had hidden: the beta's
-- h.pre_h) and their tags restored, optimizations back on (an at_death cut: only when no committed sibling still needs
-- them off, MC3), the Piece destroyed, the Caps destroyed (C4: the bone reads shown again first). hid: the hide ran
local function unwind(cut, hid)
    local C, P = mod('lab_cap'), mod('lab_piece')
    if hid then
        ue.unhide_bone_all(cut.actor, cut.bone)
        for _, h in ipairs(cut.head or {}) do
            if h.hidden and h.pre_h ~= true then ue.set_hidden(h.comp, false) end
            if h.saved and h.tagged then L.restore_tags(h.comp, h.saved) end
        end
    end
    if cut.optim == 'ok' and not (cut.at_death and optim_off(cut)) then L.optim(cut.actor, false) end
    if cut.piece and P then P.destroy(cut.piece, 'commit_fail') end
    if cut.slot and C then C.destroy(cut.slot) end
end
-- The hide of section 3.8, inside lab_piece's commit (after its place) or alone: the bone on every leader (PBO_None),
-- the head components hidden and tagged, the Stump Cap shown, the Piece-end Cap shown. true | nil, step. The beta:
-- each component's state and, on a head, lab_gib's world transforms read first; an optional or scan component that
-- will not hide is left out
local function hide(cut)
    local C = mod('lab_cap')
    cut.hid = true
    if cut.at_death then KB.pre_reads(cut) end
    if cut.at_death and cut.part == 'head' then KB.gib_reads(cut) end
    cut.hidden_n = ue.hide_bone_all(cut.actor, cut.bone)
    if cut.hidden_n < 1 then return nil, 'hide' end
    local tag = (cut.head or {})[1] ~= nil and usable('hide.tag')      -- a limb or a MaleThug head: nothing to tag
    cut.tag = tag and 'ok' or 'skip'
    for _, h in ipairs(cut.head or {}) do
        if not head_comp(h) or not ue.set_hidden(h.comp, true) then
            if not h.opt then return nil, 'comp' end
        else
            h.hidden = true
            if tag then
                h.saved = L.save_tags(h.comp)
                local ok = h.saved and L.add_tag(h.comp, K.TAG)
                h.tagged = ok == true
                if not h.tagged then cut.tag = 'fail' end     -- logged: the hide holds without the tag (P18)
            end
        end
    end
    if cut.at_death then KB.settle(cut) end
    if C.show(cut.slot, 'stump') < 1 then return nil, 'cap' end
    if cut.piece and C.show(cut.slot, 'piece') < 1 then return nil, 'piece_cap' end
    return true
end
-- The step word of a lab_piece commit why ('hide: cap' -> 'cap', 'phys: text' -> 'phys')
local function step_of(why)
    why = tostring(why)
    local inner = why:match('^hide: (%a[%w_]*)$')
    return inner or why:match('^([%a_]+)') or 'commit'
end
-- Inside 'lab.cut.head': optimizations off (P10 proven), then lab_piece's commit with the hide inside it, or the hide
-- alone without a Piece. true | nil and cut.why ('commit_fail:<step>'); a failure unwinds in this call
function K.commit(cut)
    local w0, P = os.clock(), mod('lab_piece')
    cut.optim, cut.hid = 'skip', false
    if usable('hide.optim') then
        if cut.at_death and optim_off(cut) then cut.optim = 'shared'       -- MC3: once per victim
        else cut.optim = L.optim(cut.actor, true) and 'ok' or 'fail' end
    end
    local ok, why
    if cut.piece and P then
        local okc, a, b = pcall(P.commit, cut.piece, cut, function() return hide(cut) end)
        if okc then ok, why = a, b else ok, why = nil, a end
    else
        local okc, a, b = pcall(hide, cut)
        if okc then ok, why = a, b else ok, why = nil, 'hide: ' .. text(a) end
        if okc and not ok then why = 'hide: ' .. tostring(b) end
    end
    if not ok then
        cut.why, cut.err = 'commit_fail:' .. step_of(why), text(why)
        unwind(cut, cut.hid)
        return nil
    end
    if not cut.piece then mod('lab_cap').destroy(cut.slot) end  -- HD2: gives back the unbuilt Piece end's bytes (C4 keeps the Stump Cap)
    if cut.at_death and cut.part == 'head' then cut.gib = KB.gib(cut, P) end    -- lab_gib's table (lab_cut_beta)
    cut.work_ms = ms_since(w0)
    return true
end
-- A ring of the last SAMPLES values; p in (0, 1]
local function push(list, v)
    list[#list + 1] = v
    if #list > K.SAMPLES then table.remove(list, 1) end
end
local function pct(list, p)
    if not list[1] then return nil end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    return s[math.max(1, math.ceil(#s * p))]
end
local function cut_rec(cut, f)
    local comps = {}
    for _, n in ipairs(cut.leaders or {}) do comps[#comps + 1] = n end
    for _, h in ipairs(cut.head or {}) do comps[#comps + 1] = h.name end
    local slot = cut.slot or {}
    local r = KB.rec(cut)                               -- the beta's fields (lab_cut_beta; none on a lab cut)
    for k, v in pairs({ id = cut.id, part = cut.part, pair = cut.pair, row = cut.row, tech = 'HBN', bone = cut.bone,
        stump_bone = cut.stump, comps = comps, bones_to_remove = cut.btr or 'unread', cvar_head_btr = st.cvar,
        cut_ms = f.cut_ms, work_ms = cut.work_ms, commit_ms = f.commit_ms, child = cut.child, optim = cut.optim,
        tag = cut.tag or 'skip', piece = cut.piece ~= nil, piece_why = cut.piece_why,
        stump_kind = slot.stump and slot.stump.kind, piece_kind = cut.piece and slot.piece and slot.piece.kind or nil,
        dir = r2(cut.d), hidden_n = cut.hidden_n, bone_src = cut.bone_src }) do r[k] = v end
    LAB.rec('cut', r, true)
end
local function commit_job(job)
    local cut = job.cut
    local actor, why = corpse(job.d)
    if job.revived then actor, why = nil, 'not_dead' end
    if actor and job.at_death and (st.brk.off or st.brk.bad[job.asset]) then         -- the breaker tripped meanwhile
        actor, why = nil, st.brk.off and 'beta_off' or 'bad_asset'
    end
    if not actor then
        LAB.armed('lab.cut.stage', drop_built, cut)
        return finish(job, 'refused', why)
    end
    local t0, limb = os.clock(), cut.row == 'limbs'
    local name = K.COMMIT_NAME[cut.row] or 'lab.cut.head'
    local r, err = LAB.armed(name, K.commit, cut)
    local frame_ms = ms_since(t0)
    if err ~= nil then
        st.last_err = text(err)
        local never = K.NEVER_RAN[err]
        if never then
            LAB.armed('lab.cut.stage', drop_built, cut)  -- the commit never ran: nothing was hidden
        else
            LAB.armed(name, unwind, cut, true)          -- it raised past its own pcalls: undo all now
        end
        return finish(job, 'refused', never or 'commit_fail:raised')
    end
    if not r then
        st.last_err = cut.err
        return finish(job, 'refused', cut.why or 'commit_fail:commit')
    end
    LAB.linger((limb and not (cut.head or {})[1]) and K.LIMB_GROUP or K.HEAD_GROUP, K.LINGER_S)    -- scan hits: HEAD
    local f = { cut_ms = frame_ms, commit_ms = math.floor((now() - (cut.death_t or now())) * 10000 + 0.5) / 10 }
    push(st.frames, frame_ms)
    push(st.work, cut.work_ms or frame_ms)
    if st.cold then st.cold, st.cold_ms = false, frame_ms end
    if limb then st.limbs = st.limbs + 1 else st.committed = st.committed + 1 end
    local kp = cut.kp
    if kp then                                          -- P-e: the kill's first commit, then each later one after it
        kp.f0, kp.t0 = kp.f0 or S.frame, kp.t0 or now()
        cut.after_f, cut.after_ms = S.frame - kp.f0, math.floor((now() - kp.t0) * 10000 + 0.5) / 10
    end
    finish(job, 'committed', nil, f)
    cut_rec(cut, f)
    cut.t = now()
    st.cuts[#st.cuts + 1] = cut
    BUS.emit('lab_cut_live', cut)
end
-- a goes before b: the lower rank (a lab job ranks 1), then the queue order (research MC2: every victim's primary before
-- any extra)
local function before(a, b)
    local ra, rb = a.rank or 1, b.rank or 1
    return ra < rb or (ra == rb and a.n < b.n)
end
-- One commit, then one stage per frame, each in a later frame than its row or stage, each the first by before(); off
-- refuses what waits
local function jobs_tick()
    local on, c, s = MODOFF.enabled('lab_cut'), nil, nil
    for _, job in ipairs(st.jobs) do
        if not job.done then
            if not on then
                if job.cut then LAB.armed('lab.cut.stage', drop_built, job.cut) end
                finish(job, 'refused', 'modoff')
            elseif job.state == 'staged' and job.sf < S.frame then
                if c == nil or before(job, c) then c = job end
            elseif job.state == 'row' and job.f < S.frame then
                if s == nil or before(job, s) then s = job end
            end
        end
    end
    if c then commit_job(c) end
    if s and not s.done then stage_job(s) end
    local keep = {}
    for _, job in ipairs(st.jobs) do if not job.done then keep[#keep + 1] = job end end
    st.jobs = keep
end

-- ---------- Limbs (section 3.6): two cuts on each kept-only corpse drawn at 120 s, at a quiet moment ----------
-- The two parts of a kill's struck bone: the upper arm or forearm it names (bone_src 'struck'), else lowerarm_r
-- ('fallback'); the leg it names ('struck'), else the calf on its side ('side'), else calf_l ('fallback').
-- { {part, bone_src}, {part, bone_src} }
function K.limb_parts(bone)
    local b = type(bone) == 'string' and bone:lower() or ''
    local side = b:match('_([lr])$')
    local arm, leg = side and KB.maps(b, K.ARM, side), side and KB.maps(b, K.LEG, side)
    local out = { arm and { part = arm, bone_src = 'struck' } or { part = 'lowerarm_r', bone_src = 'fallback' } }
    if leg then out[2] = { part = leg, bone_src = 'struck' }
    elseif side then out[2] = { part = 'calf_' .. side, bone_src = 'side' }
    else out[2] = { part = 'calf_l', bone_src = 'fallback' } end
    return out
end
-- At a quiet moment (lab_plan's quiet(): no lab_death in 10 s, no hook fire in 3 s, not paused, not off) and LIMB_GAP_S
-- after the last limb corpse: the first queued kept-only corpse lab_keep read drawn at 120 s takes two limb jobs; a
-- corpse not drawn, unread, untracked or gone leaves the queue; one not checked yet waits
local function limb_tick(t)
    if not st.limbq[1] or (st.limb_t ~= nil and t - st.limb_t < K.LIMB_GAP_S) then return end
    local PL, KP = mod('lab_plan'), mod('lab_keep')
    if not (PL and KP and PL.quiet() == true) then return end
    local ok, why = limb_ready()
    st.limb_why = why
    if not ok then return end
    local i = 1
    while st.limbq[i] do
        local d = st.limbq[i]
        local kc = KP.corpse(d.id)
        local drawn, actor = kc and kc.drawn_120s, corpse(d)
        if drawn == true and actor then
            table.remove(st.limbq, i)
            st.limb_t = t
            for _, p in ipairs(K.limb_parts(type(d.kill) == 'table' and d.kill.bone or nil)) do
                if #st.jobs >= K.JOBS then st.dropped = st.dropped + 1 else
                    st.n = st.n + 1
                    st.jobs[#st.jobs + 1] = { d = d, f = S.frame, state = 'row', n = st.n, row = 'limbs',
                        part = p.part, bone_src = p.bone_src }
                end
            end
            return
        elseif drawn == nil and kc and actor then
            i = i + 1                                   -- its 120 s check is still to come
        else
            table.remove(st.limbq, i)
            st.limb_skip = st.limb_skip + 1
        end
    end
end

-- ---------- D27: a revived cut victim is put back; a gone corpse leaves the list ----------
local function unlist(cut)
    for i, c in ipairs(st.cuts) do if c == cut then table.remove(st.cuts, i) break end end
end
-- Inside 'lab.cut.head': the bones shown, the head components shown and untagged, optimizations back on, the Stump
-- Cap destroyed once the bone reads shown (C4); the Piece stays a loose object. { bones, caps }: caps 1 when the Stump
-- Cap left the victim's component list (ue.listed: UE4SS's IsValid reads a destroyed component valid until the GC,
-- and a Cap hidden after a failed P9 or a destroy that did nothing is no destroy; review A5.1 F2); a list that could
-- not be read (ue.listed nil) counts nothing
function K.restore(cut)
    local C = mod('lab_cap')
    local bones = ue.unhide_bone_all(cut.actor, cut.bone)
    for _, h in ipairs(cut.head or {}) do
        local c = head_comp(h)
        if c then
            if h.pre_h ~= true then ue.set_hidden(c, false) end     -- the beta: never a variant the game had hidden
            if h.saved and h.tagged then L.restore_tags(c, h.saved) end
        end
    end
    if cut.optim == 'ok' then L.optim(cut.actor, false) end
    local stump = cut.slot and cut.slot.stump
    local sc = stump and stump.comp and live(stump.comp) or nil
    if C and cut.slot then C.destroy(cut.slot) end
    local caps = (sc and ue.listed(cut.actor, sc) == false) and 1 or 0
    return { bones = bones, caps = caps }
end
local function restore_tick()
    local q = st.revq
    st.revq = {}
    for _, e in ipairs(q) do
        for _, job in ipairs(st.jobs) do               -- a job of that life not committed yet: refused at its step
            local v = job.d.victim
            if v and v.key == e.key and job.d.corpse_life == e.life then job.revived = true end
        end
        for i = #st.cuts, 1, -1 do
            local cut = st.cuts[i]
            if cut.key == e.key and cut.corpse_life == e.life then
                unlist(cut)
                local r, err = nil, 'gone'
                if corpse({ victim = cut.victim }) then
                    r, err = LAB.armed(K.COMMIT_NAME[cut.row] or 'lab.cut.head', K.restore, cut)
                end
                st.restored = st.restored + 1
                LAB.rec('lab_restore', { id = cut.id, pair = cut.pair, why = 'revive', bones = r and r.bones or 0,
                    caps = r and r.caps or 0, err = err ~= nil and text(err) or nil }, true)
                BUS.emit('lab_cut_gone', cut)
            end
        end
    end
end
-- Every GONE_S: a cut whose corpse is no longer LAB.alive (destroyed or collected) leaves the list (its Caps went with
-- it); cut.gone_why tells lab_hold which
local function gone_tick()
    if not st.cuts[1] or not LAB.due('lab_cut.gone', K.GONE_S) then return end
    for i = #st.cuts, 1, -1 do
        local cut = st.cuts[i]
        local alive, why = LAB.alive(cut.victim)
        if not alive then
            cut.gone_why = why
            table.remove(st.cuts, i)
            st.gone = st.gone + 1
            BUS.emit('lab_cut_gone', cut)
        end
    end
end
-- The re-assert of a committed cut (lab_hold, A3.8): the bone re-hidden on every leader under 'hide.bone', the head
-- components hidden and the Stump Cap shown under 'hide.comp' (never a Cap lab_fade faded: cut.faded, slot.faded). The
-- writes made | nil, why
function K.reassert(cut)
    if type(cut) ~= 'table' or not LAB.live(cut.victim) then return nil, 'gone' end
    local n, err = LAB.armed('hide.bone', ue.hide_bone_all, cut.actor, cut.bone)
    if err ~= nil then return nil, text(err) end
    local m, err2 = LAB.armed('hide.comp', function()
        local k = 0
        for _, h in ipairs(cut.head or {}) do
            local c = head_comp(h)
            if c and ue.set_hidden(c, true) then k = k + 1 end
        end
        local c = cut.slot and cut.slot.stump and live(cut.slot.stump.comp)
        if c and not (cut.faded or cut.slot.faded) and ue.set_hidden(c, false) then k = k + 1 end
        return k
    end)
    if err2 ~= nil then return nil, text(err2) end
    return (n or 0) + (m or 0)
end

-- ---------- GCAP-a (D15, TC-GCAP-UE part 1): Ctrl+F2 (lab_3) on a heads corpse, one per layout ----------
local function gnow() return S.game_time or 0 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
-- rec.pawn of bus lab_pawn (a ue.keep record, a registry record with .keep, or the object): kept by the listener,
-- resolved at a press (lab_spawn's pattern)
local function keep_of(x)
    if type(x) == 'table' and rawget(x, '__mock') == nil then
        if x.keep ~= nil then x = x.keep end
        if type(x) == 'table' and x.obj ~= nil then return x end
        return nil
    end
    return ue.keep(x)
end
local function lab_pawn()
    if st.pawn_in ~= nil then
        local rec = st.pawn_in
        st.pawn_in = nil
        local kp = type(rec) == 'table' and keep_of(rec.pawn) or nil
        if kp then st.pawn = kp end
    end
    return st.pawn and ue.live(st.pawn) or nil
end
-- The nearest committed heads cut whose corpse is live within GCAP_CM of the lab pawn (ue.root_loc: property reads)
-- and whose pair has no rawhide yet. Only heads cuts are searched: never a control, kept-only or limb corpse.
-- cut, actor, dist_m | nil, why ('no_pawn', 'no_corpse')
local function gcap_target()
    local pawn = lab_pawn()
    local p = pawn and ue.root_loc(pawn)
    if not p then return nil, 'no_pawn' end
    local best, ba, bd
    for _, cut in ipairs(st.cuts) do
        if cut.row == 'heads' and not st.g.done[cut.pair] then
            local a = corpse({ victim = cut.victim, corpse_life = cut.corpse_life })
            local l = a and ue.root_loc(a)
            if l then
                local dd = math.sqrt((l.x - p.x) ^ 2 + (l.y - p.y) ^ 2 + (l.z - p.z) ^ 2)
                if dd <= K.GCAP_CM and (bd == nil or dd < bd) then best, ba, bd = cut, a, dd end
            end
        end
    end
    if not best then return nil, 'no_corpse' end
    return best, ba, math.floor(bd + 0.5) / 100
end
local function v3p(v)
    local x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z')
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
-- An engine FTransform as { loc, quat {w,x,y,z}, scale } | nil; and back as a full FTransform table moved by off
local function xf_of(t)
    local l, s, r = v3p(ue.prop(t, 'Translation')), v3p(ue.prop(t, 'Scale3D')), ue.prop(t, 'Rotation')
    local q = { w = ue.prop(r, 'W'), x = ue.prop(r, 'X'), y = ue.prop(r, 'Y'), z = ue.prop(r, 'Z') }
    if not (l and s and num(q.w) and num(q.x) and num(q.y) and num(q.z)) then return nil end
    return { loc = l, quat = q, scale = s }
end
local function ft(x, off)
    local l, q, s = x.loc, x.quat or { w = 1, x = 0, y = 0, z = 0 }, x.scale or { x = 1, y = 1, z = 1 }
    if off then l = { x = l.x + off.x, y = l.y + off.y, z = l.z + off.z } end
    return { Translation = ue.vec(l.x, l.y, l.z), Rotation = { X = q.x + 0.0, Y = q.y + 0.0, Z = q.z + 0.0,
        W = q.w + 0.0 }, Scale3D = ue.vec(s.x, s.y, s.z) }
end
-- Inside 'lab.inherit.hide' (the class P1 proved), in the press frame: the forearm on the corpse's body leader (the
-- data/lab_pairs.lua candidates of GCAP_PART by GetBoneIndex) and the leader's world transform (GetSocketTransform
-- None, RTS_World 0), kept as plain data. g, with g.why set when it found no forearm or no transform
function K.gcap_resolve(g)
    local leader = ue.prop(g.actor, 'Mesh')
    if not ue.valid(leader) then g.why = 'no_leader' return g end
    for _, b in ipairs(((pair_of(g.pair).parts or {})[K.GCAP_PART] or {}).cut or {}) do
        if ue.has_bone(leader, b) then g.bone = b break end
    end
    if not g.bone then g.why = 'no_bone' return g end
    local ok, t = ue.call(leader, 'GetSocketTransform', ue.fname('None'), 0)
    g.xf = ok and xf_of(t) or nil
    if not g.xf then g.why = 'xform' end
    return g
end
-- Material slot i of src into p, for every slot (at most MAT_MAX): the slots copied
local function copy_mats(p, src)
    local ok, n = ue.call(src, 'GetNumMaterials')
    if not ok or math.type(n) ~= 'integer' then return 0 end
    local done = 0
    for i = 0, math.min(n, K.MAT_MAX) - 1 do
        local okg, m = ue.call(src, 'GetMaterial', i)
        if okg and ue.valid(m) and ue.call(p, 'SetMaterial', i, m) then done = done + 1 end
    end
    return done
end
-- tech_b's copy goes: K2_DestroyActor once P16 proved that class (D4; lab_piece hides its Pieces too while
-- 'piece.destroy' is unproven, failed or struck), else, or when the destroy is refused, hidden. g.copy_end:
-- 'destroyed', 'hidden', 'stays' (neither call answered) or 'none' (no copy). true when no copy stays drawn
local function gcap_drop(g)
    local a = g.copy and ue.live_mod(g.copy)
    g.shown = false
    if not a then g.copy_end = g.copy_end or 'none' return true end
    if usable('piece.destroy') and US.destroy_actor(a) then g.copy_end = 'destroyed' return true end
    local ok = US.set_actor_hidden(a, true) == true
    g.copy_end = ok and 'hidden' or 'stays'
    return ok
end
-- tech_b's classes (D4, D30): the copy spawns, meshes, poses and scales through the Piece classes, so it runs only
-- while lab_piece reads the body_copy route ready (P11-P15 proven, none struck or stopped). true | false, why:
-- 'pieces_pending' while that ladder still runs (the press is refused; a later one may run both), else 'pieces_off'
-- (tech_a runs alone and the record reads ok false)
local function gcap_b_ready()
    local P = mod('lab_piece')
    if P and P.ready('body_copy') then return true end
    local s = P and P.status() or {}
    if s.done ~= true and (s.step ~= nil or s.corpse ~= nil) then return false, 'pieces_pending' end
    return false, 'pieces_off'
end
-- tech_b built hidden: an own Actor (deferred spawn) with a BoxComponent root BESIDE the corpse, a poseable copy
-- (PoseableMeshComponent) of the body leader's mesh with its materials at the leader's world transform moved BESIDE, the pose copied from the
-- leader before any hide (kill-and-cut.md, copies step 4), the forearm at ISO (SetBoneScaleByName exists only on a
-- poseable, so:20114). true | nil, why
local function gcap_copy(g, leader)
    local cls, asset = ue.class(K.ACTOR), ue.prop(leader, 'SkinnedAsset')
    if not cls then return nil, 'no_actor_class' end
    if not ue.valid(asset) then return nil, 'no_asset' end
    local at = { x = g.xf.loc.x + K.BESIDE.x, y = g.xf.loc.y + K.BESIDE.y, z = g.xf.loc.z + K.BESIDE.z }
    local a, why, half = US.spawn_deferred(cls, ue.xform(ue.vec(at.x, at.y, at.z)), {})
    if not a then
        g.copy = half and ue.keep_mod(half) or nil      -- an unfinished actor still goes
        return nil, 'spawn: ' .. text(why)
    end
    g.copy = ue.keep_mod(a)
    if not g.copy then return nil, 'unread' end
    local ok, w = US.set_actor_hidden(a, true)
    if not ok then return nil, 'hide: ' .. text(w) end
    local box, wb = ue.add_component(a, K.BOX, { no_collision = true })  -- never simulates: off for its show (A5.1 F9)
    if not box then return nil, 'box: ' .. text(wb) end
    ok, w = L.box_extent(box, { x = K.BOX_HALF, y = K.BOX_HALF, z = K.BOX_HALF })
    if not ok then return nil, 'extent: ' .. text(w) end
    ok, w = ue.call(box, 'K2_SetWorldTransform', ft({ loc = at }), false, {}, true)
    if not ok then return nil, 'box_place: ' .. text(w) end
    local p, wp = ue.add_component(a, K.POSEABLE)
    if not p then return nil, 'poseable: ' .. text(wp) end
    g.pose = ue.keep_mod(p)
    ok, w = L.set_asset(p, asset, true)
    if not ok then return nil, 'asset: ' .. text(w) end
    ue.refuse_decals(p, K.POSEABLE)
    g.mats = copy_mats(p, leader)
    ok, w = ue.call(p, 'K2_SetWorldTransform', ft(g.xf, K.BESIDE), false, {}, true)
    if not ok then return nil, 'place: ' .. text(w) end
    ok, w = L.copy_pose(p, leader)
    if not ok then return nil, 'pose: ' .. text(w) end
    ok, w = L.bone_scale(p, g.bone, K.ISO)
    if not ok then return nil, 'scale: ' .. text(w) end
    return true
end
local function rb(h) if h == nil then return 'unread' end return h end
-- Inside 'lab.cut.gcap' (one call per press, the frame after the resolve): tech_b built and posed hidden, then tech_a
-- HideBoneByName on every leader with the forearm (PBO_None, no Cap) read back per leader, then the copy shown. g gains
-- comps [{class, hidden_rb, tech}], hid, ok, why; a failed tech_a unhides and drops the copy in this call (held 0 s)
function K.gcap_open(g)
    g.comps = {}
    local leader = ue.prop(g.actor, 'Mesh')
    if not ue.valid(leader) then g.ok, g.why = false, 'no_leader' return g end
    local okb, wb
    if g.no_b then okb, wb = nil, g.no_b else okb, wb = gcap_copy(g, leader) end
    if not okb then
        g.why = 'tech_b: ' .. text(wb)
        gcap_drop(g)
    end
    g.hidden_n = ue.hide_bone_all(g.actor, g.bone)
    local all = g.hidden_n > 0
    for _, c in ipairs(ue.leaders_with_bone(g.actor, g.bone)) do
        local h = L.is_bone_hidden(c, g.bone)
        g.comps[#g.comps + 1] = { class = class_of(c), hidden_rb = rb(h), tech = 'a' }
        if h ~= true then all = false end
    end
    if not all then
        if g.hidden_n > 0 then g.unhidden = ue.unhide_bone_all(g.actor, g.bone) end
        gcap_drop(g)
        g.hid, g.ok, g.why = false, false, g.why or 'tech_a'
        return g
    end
    g.hid = true
    if okb then
        local a, p = ue.live_mod(g.copy), g.pose and ue.live_mod(g.pose)
        local oks, ws = false, 'gone'
        if a then oks, ws = US.set_actor_hidden(a, false) end
        if oks then
            g.shown = true
            g.comps[#g.comps + 1] = { class = p and class_of(p) or 'unread',
                hidden_rb = rb(p and L.is_bone_hidden(p, g.bone)), tech = 'b', scale = K.ISO }
        else
            okb, g.why = false, 'tech_b: show ' .. text(ws)
            gcap_drop(g)
        end
    end
    g.ok = okb == true
    return g
end
-- Inside 'lab.cut.gcap' at GCAP_S game seconds (or lab_end): UnHideBoneByName on every leader with the forearm (on the
-- victim whatever its life: a revived pawn gets its arm back too), the copy destroyed
function K.gcap_close(g)
    local a = LAB.live(g.victim)
    g.unhidden = a and ue.unhide_bone_all(a, g.bone) or 0
    g.dropped = gcap_drop(g)
    return true
end
-- The rawhide record (section 3.1), forced: one per layout that ran, and one per refused press (pair 'none' until a
-- corpse was chosen); ended: 'held', 'lab_end', 'map_load', or 'now' (closed in its own call)
local function gcap_rec(g, ended)
    LAB.rec('rawhide', { id = g.id, pair = g.pair or 'none', part = K.GCAP_PART, bone = g.bone, ok = g.ok == true,
        tech_a = 'hide_bone', tech_b = 'poseable_scale', comps = g.comps or {}, held_s = g.held_s or 0,
        closed = g.closed, why = g.why, ended = ended, dist_m = g.dist_m, press = g.press, scale = K.ISO,
        mats = g.mats, unhidden = g.unhidden, ms = g.ms, copy_end = g.copy_end }, true)
end
local function gcap_refuse(n, why, g)
    st.g.refused = st.g.refused + 1
    g = g or {}
    g.press, g.ok, g.why = n, false, why
    gcap_rec(g, 'refused')
end
local function gcap_end(g, ended)
    st.g.open = nil
    local _, err = LAB.armed('lab.cut.gcap', K.gcap_close, g)
    g.held_s = math.floor((gnow() - (g.t0 or gnow())) * 10 + 0.5) / 10
    g.closed = err == nil and 'unhide' or 'refused'
    if err ~= nil then g.ok, g.why = false, g.why or ('close: ' .. text(err)) end
    gcap_rec(g, ended)
end
-- A press: the refusals, the target, then the resolve under 'lab.inherit.hide' in this frame; the pair runs the next
local function gcap_press(press)
    local g = st.g
    local left = false
    for _, p in ipairs(K.GCAP_PAIRS) do if not g.done[p] then left = true end end
    if not left then return gcap_refuse(press.n, 'gcap_done') end
    if not MODOFF.enabled('lab_cut') then return gcap_refuse(press.n, 'modoff') end
    if g.open or g.stage then return gcap_refuse(press.n, 'pending') end
    if not LAB.l0i_ok() or LAB.proof('lab.inherit.hide') ~= true then return gcap_refuse(press.n, 'not_armed') end
    for _, n in ipairs({ 'lab.cut.gcap', 'hide.bone' }) do        -- tech_a is a HideBoneByName too
        if SENT.is_disabled(n) then return gcap_refuse(press.n, 'disabled') end
    end
    if sig_pending('lab.cut.gcap') then                 -- the press waits a frame at the head of the queue
        table.insert(g.q, 1, press)
        return
    end
    local w = sig_word('lab.cut.gcap')
    if w then return gcap_refuse(press.n, w) end
    local okb, wb = gcap_b_ready()
    if wb == 'pieces_pending' then return gcap_refuse(press.n, wb) end
    local cut, actor, dist = gcap_target()
    if not cut then return gcap_refuse(press.n, actor) end
    local s = { press = press.n, id = cut.id, pair = cut.pair, victim = cut.victim, key = cut.key,
        corpse_life = cut.corpse_life, actor = actor, dist_m = dist, no_b = (not okb) and wb or nil }
    local r, err = LAB.armed('lab.inherit.hide', K.gcap_resolve, s)
    if err ~= nil or type(r) ~= 'table' or not s.xf then
        if err == nil then g.done[s.pair] = true end    -- this layout lacks the forearm: nothing is retried
        return gcap_refuse(press.n, err ~= nil and text(err) or ('resolve: ' .. tostring(s.why)), s)
    end
    s.f = S.frame
    g.stage = s
end
local function gcap_run(s)
    local g = st.g
    if not MODOFF.enabled('lab_cut') then return gcap_refuse(s.press, 'modoff', s) end
    s.actor = corpse({ victim = s.victim, corpse_life = s.corpse_life })
    if not s.actor then return gcap_refuse(s.press, 'gone', s) end
    local t0 = os.clock()
    local r, err = LAB.armed('lab.cut.gcap', K.gcap_open, s)
    s.ms = ms_since(t0)
    if err ~= nil and K.NEVER_RAN[err] then return gcap_refuse(s.press, K.NEVER_RAN[err], s) end
    g.done[s.pair], g.opened = true, g.opened + 1
    if err ~= nil or type(r) ~= 'table' then
        LAB.armed('lab.cut.gcap', K.gcap_close, s)     -- it raised past its own checks: undo now
        s.ok, s.why, s.closed, s.held_s = false, 'raised: ' .. text(err), 'unhide', 0
        return gcap_rec(s, 'now')
    end
    if not s.hid then
        s.closed, s.held_s = 'unhide', 0
        return gcap_rec(s, 'now')
    end
    s.t0 = gnow()
    g.open = s
end
-- The open pair closes GCAP_S game seconds later (deferred while the mod is off: its copy is in the hidden list, and
-- the 'on' press must find it again, L8 list_diff); a staged press runs the frame after its resolve; then one press
local function gcap_tick()
    local g = st.g
    local o = g.open
    if o and gnow() - o.t0 >= K.GCAP_S and not MODOFF.is_off() then gcap_end(o, 'held') end
    local s = g.stage
    if s and s.f < S.frame then
        g.stage = nil
        return gcap_run(s)
    end
    if s == nil and g.q[1] then gcap_press(table.remove(g.q, 1)) end
end
-- MO.feature's live list: tech_b's copy while it is shown (an own actor, kind 'actor': mod-off hides it)
function K.live()
    local o = st.g.open
    local a = o and o.shown and o.copy and ue.live_mod(o.copy)
    if not a then return {} end
    return { { obj = a, name = ue.name(a), kind = 'actor' } }
end

-- ---------- the ticker, lab_end and the bus ----------
-- lab_end (D20): every job still waiting is dropped (lab_poll wrote its kill 'lab_end'), a pending l0i_armed written
local function on_end()
    st.end_due, st.ended = false, true
    for _, job in ipairs(st.jobs) do
        if not job.done and job.cut then LAB.armed('lab.cut.stage', drop_built, job.cut) end
        finish(job, 'refused', 'lab_end')
    end
    st.jobs, st.p1q, st.compq, st.limbq, st.rate = {}, {}, {}, {}, {}
    if st.g.open then gcap_end(st.g.open, 'lab_end') end   -- the raw hide closed now, its copy destroyed
    st.g.q, st.g.stage = {}, nil
    p1_rec({ why = 'lab_end' })
end
local function tick()
    if st.end_due then on_end() end
    if st.ended then return end
    if st.revq[1] then restore_tick() end
    if LAB.paused() then return end
    gone_tick()
    gcap_tick()
    local t = now()
    if MODOFF.enabled('lab_cut') then
        if not LAB.beta() then                          -- the beta runs no ladder step: lab_probe seeds its proofs
            p1_tick(t)
            p1b_tick(t)
            comp_tick(t)
        end
        limb_tick(t)
    end
    jobs_tick()
end
local function on_row(row, d)                           -- listeners only queue
    if type(d) ~= 'table' or d.id == nil then return end
    if row == 'heads' then
        if #st.jobs >= (LAB.beta() and K.JOBS_BETA or K.JOBS) then st.dropped = st.dropped + 1 return end
        st.n = st.n + 1
        local job = { d = d, f = S.frame, state = 'row', n = st.n }
        if LAB.beta() then KB.primary(job, st, now(), META.beta_limbs) end      -- rank 1; its stage plans the extras
        st.jobs[#st.jobs + 1] = job
    elseif K.NO_CUT[row] then
        if row == 'keep_only' and #st.limbq < K.LIMBQ then st.limbq[#st.limbq + 1] = d end   -- Limbs (never a control)
        if st.p1 == nil and #st.p1q < K.P1Q then st.p1q[#st.p1q + 1] = d end
        local s = st.p17
        if d.pair == 'GuiChai' and (s == nil or K.COMP_STEPS[s.i]) and #st.compq < K.COMPQ then
            st.compq[#st.compq + 1] = d
        end
    end
end
local EVENTS = { 'lab_row', 'lab_proof', 'lab_revive', 'lab_end', 'lab_key', 'lab_pawn' }

-- ---------- lifecycle ----------
function K.cuts() return st.cuts end
function K.njobs() return #st.jobs end
-- A: the main.lua feature view (clock, meta; LAB holds count, gauge and the records). Inert outside the lab02 set
function K.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.cut_set() then return true end
    st.init = true
    if LAB.beta() then st.cvar = 'skip' end             -- the beta never reads the head-bone CVar (BD10)
    LAB.names(N, F)
    LAB.names(KB.N, KB.F)
    -- the vanilla compare blocks the ladder steps and the cuts, as mod-off does; a cut's Caps and hides stay (C5);
    -- mod-off hides GCAP-a's shown copy (K.live)
    MODOFF.feature('lab_cut', { gameplay = true, live = K.live })
    BUS.on('lab_row', 'lab_cut', on_row)
    BUS.on('lab_key', 'lab_cut', function(action)        -- GCAP-a on lab_3 only (lab_1 and lab_2 spawn, D12)
        if action ~= 'lab_3' or st.ended then return end
        st.g.presses = st.g.presses + 1
        if #st.g.q < K.GCAPQ then st.g.q[#st.g.q + 1] = { n = st.g.presses, f = S.frame } end
    end)
    BUS.on('lab_pawn', 'lab_cut', function(rec) st.pawn_in = rec end)
    BUS.on('lab_proof', 'lab_cut', function(name) st.last = { name = name, t = now(), f = S.frame } end)
    BUS.on('lab_revive', 'lab_cut', function(rec, life)
        if type(rec) == 'table' and rec.key ~= nil then st.revq[#st.revq + 1] = { key = rec.key, life = life } end
    end)
    BUS.on('lab_end', 'lab_cut', function() if not st.ended then st.end_due = true end end)
    LAB.gauge('cut_frame_ms_p95', function() return pct(st.frames, 0.95) end)
    LAB.gauge('cut_frame_ms_p99', function() return pct(st.frames, 0.99) end)
    LAB.gauge('cut_frame_ms_max', function() return pct(st.frames, 1.0) end)
    LAB.gauge('cut_work_ms_p95', function() return pct(st.work, 0.95) end)
    LAB.gauge('cold_cut_ms', function() return st.cold_ms end)
    S.ticker('lab_cut', tick)
    return true
end
-- A map load: the corpses, the staged objects and the queued rows went with the old map (lab_poll wrote their kills
-- 'stale'); the next commit is cold again. The bone cache (per mesh asset), the proofs and the gauges stay
function K.reset()
    if not st.init then return end
    for _, job in ipairs(st.jobs) do job.done = true end
    for _, cut in ipairs(st.cuts) do BUS.emit('lab_cut_gone', cut) end
    st.jobs, st.cuts, st.p1q, st.compq, st.revq, st.cold, st.limbq = {}, {}, {}, {}, {}, true, {}
    if st.p17 then st.p17.d = nil end
    local o = st.g.open                                 -- its corpse and copy went with the old map: no engine call
    if o then
        st.g.open = nil
        o.closed, o.held_s = 'map_load', math.floor((gnow() - (o.t0 or gnow())) * 10 + 0.5) / 10
        gcap_rec(o, 'map_load')
    end
    st.g.q, st.g.stage = {}, nil
end
function K.status()
    local s = st.p17 or {}
    return { init = st.init, cuts = #st.cuts, jobs = #st.jobs, staged = st.staged, committed = st.committed,
        refused = st.refused, restored = st.restored, gone = st.gone, dropped = st.dropped, last_err = st.last_err,
        p1 = st.p1 and (st.p1.skipped or (st.p1.ok and 'ok' or 'fail')) or nil, p1b = st.p1b, p1_why = st.p1_why,
        comp_step = K.COMP_STEPS[s.i or 1] and K.COMP_STEPS[s.i or 1].step or 'done', comp_skipped = s.skipped,
        cache = (function() local n = 0 for _ in pairs(st.cache) do n = n + 1 end return n end)(), cvar = st.cvar,
        limbs = st.limbs, limb_fail = st.limb_fail, limb_skip = st.limb_skip, limbq = #st.limbq, limb_why = st.limb_why,
        gcap_presses = st.g.presses, gcap_refused = st.g.refused, gcap_opened = st.g.opened,
        gcap_open = st.g.open ~= nil, plans = st.plans, extras = st.extras, extras_dropped = st.xdrop,
        bad_assets = st.brk.nbad, beta_off = st.brk.off, fail_run = st.brk.run }
end
function K.shutdown()
    S.remove_ticker('lab_cut')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_cut') end
    st, A = new_state(), nil
end

return K
