-- status: new for the beta test build (offline only, smoke-run on fakes; the author's run decides) origin:
-- docs/research/slicer-stumps.md sections 4, 5 and 7 (the production route) and the skeptic corrections there; the
-- author 2026-11-01 («I need not just research but the implementation too»)
-- lab_slice_route.lua: ordinary death cuts through the game's own skeletal-mesh slicer (lab_slice's primitives): the
-- real skin cut along a plane, each cut loop capped flush, two skinned halves with their own ragdoll. Where the slicer
-- cannot take a victim, that victim takes today's joint cut (lab_cut: HideBoneByName, our Caps, the Pieces) unchanged,
-- automatically, with one forced slice_skip record. The player beta only (META.beta_modules, after lab_slice) with
-- META.beta_slicer; inert otherwise (no listener, ticker or record). The knob 'slicer' (core/config.lua C.knob, live;
-- the test key Ctrl+Shift+F3 flips it) turns the route off: every death then takes the joint cut, as before.
-- * Routing (lab_plan's beta row, Lua only, no native call in its frame): where lab_plan would give a death the row
--   'heads' (the beta's cut rules hold first: the killing blow severs the struck part, a heavy blow 2 parts, Sha-Qi 3,
--   no cut on kicks, deflects, bleed deaths or executions, one part for an NPC's kill, never the player), it asks
--   R.wants(payload, row); true gives the row 'slice' (bus lab_row 'slice' with the Heads payload, queued here), else
--   'heads' as before. True only when all hold: the route is up and the knob 'slicer' on; mod-off and the vanilla
--   compare off; sched's breaker has not switched the route's ticker off (the bus would skip its lab_row listener:
--   'job_off'); LAB.pinned(); no stop (the cut names are inherited); not the player; with META.beta_limbs, no kill
--   that wants more than one part (KB.nparts) and whose first part (KB.first) is a limb ('multi_limb', D1 of
--   docs/spec/fixes-0.2.2.md: the joint cut plans it struck-first and keeps its extras, where a slice after the
--   first would drop them; the detail carries KB.first's pick); no slicer name struck or disabled (SL.hurt: a
--   crash or a quit inside a slicer linger costs the next session its slices); the class has a cut family
--   (SL.cut_family: MaleThug and GuiChai by class, every other cut class by its row's route) whose cut name is not
--   disabled; lab_corpse has not closed 'slicer.gone' (a sliced corpse could never go: 'gone_closed'); its row is no
--   cloth-hair burst head, no reviving and no exploding class; no earlier failure of the class this session (no LOD
--   passed the ladder, a preflight without triangles on both sides, a failed slice); the crash-flagged CVar not seen
--   non-zero; the cap material ladder not found empty in the last MAT_RETRY_S on this map; no joint cut on the key
--   ever (bus lab_cut_live; lab_plan gives a key lab_slice sliced the row 'sliced' before asking); no job of the key
--   queued or running ('in_flight'); lab_corpse keeps the corpse (state 'corpse', as the reads step needs: 'not_kept');
--   fewer than SLICED_MAX sliced corpses kept (lab_corpse's list, lab_slice's sliced keys) plus queued jobs; room in
--   the queue; the route's breaker not tripped. A refusal goes 'heads'; it writes one slice_skip record per class and
--   reason a session (knob off and mod-off none), the counters count them all.
-- * The job (one at a time, FIFO; one ticker step a frame, never in the row's frame, a frame with a lab_death or a
--   lab_cut_live or the frame after one; every native call a lab_slice primitive under its own sentinel name, each in
--   its own step: the reads, the preflight and the slice never share a frame):
--   - reads: lab_corpse keeps the corpse (state 'corpse'), then SL.brief (the body: IsA SkeletalMeshComponent, no
--     follower, shown; its asset; no Akasha half on the actor yet), SL.bones (the parts' and the side tests' bones),
--     SL.lodinfo (the body asset's per-LOD CPU bits from SourceModels, #LODInfo, GetNumLODs, ForcedLodModel: LOD 0's
--     bit true or false goes on, an unread one only when soft), the CVars once a session
--     (z.sliceUseEngineSetAllBodiesSimulatePhysics must read 0; r.FreeSkeletalMeshBuffers kept for the records). The
--     parts: lab_cut_beta's parts_of on the bones the rig has (KB.first's part, the swing partner, the head, the
--     fixed order; KB.nparts; limbs only with META.beta_limbs) in its rank order (docs/spec/fixes-0.2.2.md D1: the
--     first part is sliced first, never the head ahead of it), parts_of's pick kept for the rank-1 slice record. The
--     first part's plane and side test (an early look).
--   - the cap material once a map (mat_find, mat_load in its own frame when M_SKInteriror is not resident, mat_flags,
--     mat_hold when M_SKInteriror is chosen): the first material with skeletal-mesh usage and the Surface domain,
--     M_SKInteriror first, then lab_look's candidates; none: the joint cut (CapMaterial is never nil).
--   - pre: the body preflight once per body asset (lab_slice caches the verdict, this module the LOD the ladder
--     chose), on the plane's bones read again in its own frame (the reads were frames back, a body moved off that plane
--     would read one side empty): source data ok, triangles on both sides of the plane, the ManualPoseSkinning echo
--     true (else the options did not marshal: the route goes off for the session). LOD 0's bit true (or soft): the
--     plain preflight; false: no LOD 0 preflight and no write to SourceModels[0] (a bit cooked false: LOD 0's CPU
--     copies were discarded at load, a bit set later never brings them back), one ladder entry { lod 0, why
--     'bit_false_skip' }, then the ladder from LOD 1, as the f93cf2f lab run went (LOD 0 extract_failed, then LOD 1+).
--     Retried once a frame later when not good, except 'failed while extracting source data' (extract_failed: the LOD
--     has no CPU copies), which starts the LOD experiment (the route A study, 2026-11-01):
--     - the ladder (pre_lod): one rung a frame on LOD k = 1 .. min(LADDER_MAX, #SourceModels - 1, GetNumLODs - 1),
--       each a preflight with Options.LODIndex k and LOD k's bit set and restored in its call (slicer.lodpre); the
--       first good rung is cut on LOD k (lower-poly halves) through the prepared cut, never the direct one.
--     - Prepare (X4), once per body asset a session when no rung passed and LOD 0's bit did not read false (X4 runs the
--       LOD 0 rung again, slicer.cpuflag, whose call would set a false bit): PrepareSkeletalMeshSliceRuntime on LOD 0
--       (slicer.prepare: it forces LOD 0 streamed and rendered, copies nothing), the LOD 0 rung again once the
--       streaming flag reads false (at most PREP_WAIT_F frames), then ReleasePreparedSkeletalMeshSlice (slicer.release)
--       and the cut when that rung was good (after the cut step's LOD 0 check: once Release gives the forced LOD back,
--       the corpse may render another LOD). A job that ends between Prepare and Release (a timeout, mod-off, a stop)
--       leaves its handle to the ticker, which releases it first thing on a later frame (counted
--       slice_release_late).
--     No LOD passed: the class takes the joint cut for the session, the asset's answer kept (the next job of the
--     asset skips the ladder). A rung or Prepare refused for this job only (streaming still pending past
--     STREAM_TRIES, the body gone: anything outside LADDER_END) gives this job the joint cut and keeps no answer, so
--     the next job of the asset runs the ladder again, and X4 counts as spent only once its Prepare ran.
--   - prep (lab_slice_prep, its header): a first cut on a LOD above 0, on LOD 0 whose bit read false, or on LOD 0 the
--     corpse does not render (the cut step's LOD 0 check, the bit true) goes the game's own way, each call in its own
--     step: Prepare on LOD k (slicer.prepare), the wait until ForcedLodModel reads k + 1 and GetPredictedLODLevel k
--     with nothing streaming (slicer.prep.read), the cut step's SlicePrepared with the handle (slicer.cut.prep),
--     Release (slicer.release) on every path that holds a handle, before the joint cut or the after step. A handle that
--     does not read: no SlicePrepared, the joint cut. The direct cut on LOD k (the old slicer.cut.lod) crashed natively
--     in the 2026-11-01 22:17 lab run: retired, SL.cut takes no lod.
--   - cut: the plane's bones read again in the cut frame (a ragdoll moves), the plane and the side test again, then
--     SL.cut under the family's cut name (LOD 0, its bit as read) or the prepared cut (SL.cut_prep). Refused before the
--     call: the joint cut ('lod_streaming' retries STREAM_TRIES frames). The slice waits while lab_cut has a job, at
--     most CUT_WAIT_S. The direct cut first checks, in its cut frame, that the corpse renders LOD 0 (the 2026-11-01
--     crash was a direct cut on a LOD it did not render): SL.prep_read with k 0 (slicer.prep.read: ForcedLodModel,
--     GetPredictedLODLevel), per corpse and never kept for the asset. ForcedLodModel 0 or 1 and GetPredictedLODLevel 0
--     with nothing streaming: the direct cut; a pending stream: the STREAM_TRIES retries; any other read: the prepared
--     cut on LOD 0 for this corpse when LOD 0's bit read true, else the joint cut ('lod0_not_rendered'); the read
--     refused or raised: the joint cut. X4's cut after Release takes the same check.
--   - after (the next frame): the halves (the cut's result first, the name prefix second), each half's cap slot, side
--     and simulation, where every skinned component went, the source; the new halves' LODInfo CPU bit. No half and the
--     source still shown: nothing was cut, the joint cut takes the victim (a failed slice is counted and the class goes
--     to the joint cut for the session). Any half: the key is sliced for good (no joint cut ever, a revive included).
--   - rehome (a head slice): each skinned component of the class row's head, hair and glow lists that did not go to
--     the Positive half (a meshhead's bounds centre sits below the neck) is attached to it and led by it (SL.rehome).
--     Hair, checked against data/cut_classes.lua: all 12 rows that list hair list it as Chaos cloth (hair == hair_cloth,
--     CA_*Hair*), and those rows never reach the slicer (row_bad 'hair_cloth': lab_gib's burst or kept-hair head), so no
--     sliced head goes bald; a skinned hair name would be re-homed here.
--   - drop (a head slice): the class row's hats and masks (its fall list, every hat_mask name), read in the reads step
--     (SL.brief extras: class, fall kind, drawn before the cut), fall off as at a joint cut: wherever the slicer left
--     each one drawn before the cut (on the head half, on the body half or on the hidden source), SL.drop reads its
--     world transform and hides it under 'slicer.drop', then bus lab_slice_fall { key, id, class, part, at (the head
--     half's head bone), vel (the head's launch), extras } hands lab_gib its falling copies (lab_gib's fall route under
--     'slicer.fall'). When lab_gib cannot drop them now (G.ready('slice_fall') false: the knob extras_fall off, a
--     breaker, a struck name), nothing is hidden and a skinned one rides with the head half (re-homed).
--   - fix: SetSimulatePhysics(false) on what the slice hid (the source, or the half a re-slice cut; also when the
--     after read failed and halves were made), then one impulse on the Positive half (the part: HEAD_V for a head,
--     LIMB_V for a limb, along the plane normal, the blow's sweep and up; a pending sig waits a frame for it). The
--     slice record. Then the next part: when the Negative half's CPU bit read true, a re-slice of that half
--     (SL.reslice under 'slicer.reslice', its bones read on the half in the same frame, the side test without the
--     parts already off); false or unread, one slice_limb_skip record and the rest of the parts dropped. One route per
--     victim: never HideBoneByName and a slice on one victim.
--   A pre-cut job falls back to the joint cut on: the knob off, the breaker or a failed slice of its class since its
--   row, TIMEOUT_S of game time since its row, any refusal or failed read (a raised one counts toward the breaker),
--   never on a victim with an Akasha half (ours or the game's: lab_plan's 'sliced' row and a lab_skip outcome, no cut
--   at all). A stop or lab_end drops the uncut jobs with no cut (lab_plan's 'not_armed'). lab_slice reserves the key
--   from the row to the job's end (lab_corpse never lets it go meanwhile). bus lab_slice_live (kind 'slice', the
--   halves as keep records; prev, a re-slice's cut half, so lab_blood moves the pulses still queued on it) goes out
--   after each slice with two halves; lab_cut_live never does (lab_hold, lab_gib, lab_fade and lab_census would treat
--   the halves as a joint cut).
-- * Mod-off and the vanilla compare (MODOFF.feature 'lab_slice_route', gameplay; rule C5): nothing new is sliced and the
--   halves stay as the game made them (never in a live() list: no hide, no show, no destroy). At the next tick the
--   queued jobs and a job that has not cut yet drop, Lua only: no joint cut either (the death keeps lab_plan's 'off'
--   row through M.reroute and one lab_outcome { row 'off', outcome 'refused', why 'modoff' }, as a death that came while
--   off), counted slice_skip_modoff without a record. A job that already cut finishes only that slice's reads and the
--   hidden source's fix (upkeep: SetSimulatePhysics(false), no visible change); its re-home, the hats' drop, the
--   impulse, lab_slice_live and the next part are dropped (slice_limb_skip why 'modoff'). Mod-on re-runs nothing: a dropped job is gone, and every
--   death that came while off kept its 'off' row.
-- * The breaker: FAIL_OFF_N failures in a row (a slice that did not leave two halves, a guarded call that raised)
--   switch the route off for the session (one forced slice_off record); a slice that worked (its after read too)
--   resets the run.
-- * Records (forced): slice per slice { id, class, part, rank, fam, layout, asset, ok, why, ret, ms (per step),
--   total_ms, halves, n_halves, positive_is_part, cap_material, cap_ok, cell, side (ok, fails, values), P, N, pos_cpu,
--   neg_cpu, source, went, rehome, drop (names, hidden, sent, err), fix, push, off ('modoff' when mod-off came after
--   the cut), pick (rank 1: parts_of's pick { first, src, band, plane, plane_src, exec }), pre, lod (rank 1: reads,
--   ladder rungs { lod, before, set, restored, src_ok, extract_failed, cpu, pos, neg, mix, ms, why }, prep, chosen,
--   free_buffers, lod0: the cut step's LOD 0 check { forced, predicted, pending, direct }), prep (rank 1:
--   lab_slice_prep's record), cut_lod, cut_bit, lines
--   (failed only), err }; slice_skip { id, class, part, why, step, detail, layout, lod, prep }; slice_step { id, class,
--   step, k } before each native step of the prepared cut (lab_slice_prep);
--   slice_limb_skip { id, class, sliced, dropped, neg_cpu, err }; slice_off { why }. Counters (published at 0):
--   slice_ok, slice_fail, slice_skip, slice_limb_skip, and slice_skip_<why> per reason.
-- API: wants(payload, row) -> bool, why; status(); lifecycle init(A) reset(reason) shutdown(). R.sets(part) the side
--   test's bone groups; R.order(parts) a copy in rank order; R.plan_parts(job, bones) the job's parts in slicing
--   order and what parts_of dropped, job.pick set (a test seam).
-- What the mock cannot prove: everything native (whether a body asset keeps CPU data, the slicer's look and cost, the
--   halves' CPU bit, how a meshhead or a cloth component moves), whether the ragdoll starts before the impulse.
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')
local SL = require('lab_slice')
local KB = require('lab_cut_beta')
local PC = require('lab_slice_prep')                -- the prepared cut (a library: its header)

local R = { SLICED_MAX = 12, QMAX = 6, TIMEOUT_S = 3.0, CUT_WAIT_S = 0.5, PRE_TRIES = 1, STREAM_TRIES = 3,
    FAIL_OFF_N = 3, MAT_RETRY_S = 20, ERR_CHARS = 160, SIDE_FAR_CM = 10, SIDE_NEAR_CM = 2, T_HEAD = 0.5,
    T_LIMB = 0.4, UP_K = 0.3, SWEEP_K = 0.5, HEAD_V = KB.HEAD_V, LIMB_V = KB.LIMB_V,
    -- the LOD experiment (header 'pre'): the highest LOD the ladder tries, Prepare's handle lifetime, the frames a
    -- prepared LOD may stream before its rung or its cut, the late releases kept
    LADDER_MAX = 3, PREP_LIFE_S = 5.0, PREP_WAIT_F = 60, REL_MAX = 8 }
-- CapGridCellSize per family (cm, about the cut's diameter: one texture span over the face)
R.CELL = { head = 12, arm = 9, leg = 14 }
-- Reasons that only count (no slice_skip record): the author's switch, mod-off
R.QUIET = { knob_off = true, modoff = true }
R.COUNTERS = { 'slice_ok', 'slice_fail', 'slice_skip', 'slice_limb_skip' }
-- The class row lists whose skinned components a head slice re-homes to the head half when they went elsewhere (the
-- hats and masks, the row's fall list, fall off instead: STEPS.drop)
R.REHOME = { 'head', 'hair', 'glow' }
-- The bones each part takes off with it (dropped from the next re-slice's side test)
local CHAIN = {
    head = { 'head', 'Head', 'neck_02' },
    upperarm = { 'upperarm_%s', 'lowerarm_%s', 'forearm_%s', 'hand_%s' }, lowerarm = { 'lowerarm_%s', 'forearm_%s', 'hand_%s' },
    thigh = { 'thigh_%s', 'calf_%s', 'foot_%s' }, calf = { 'calf_%s', 'foot_%s' },
}

local A = nil
local function new_state()
    return { init = false, ended = false, q = {}, job = nil, busy_f = nil, cut_keys = {}, verdict = {}, mat = nil,
        cvar = nil, free = nil, off = nil, fail_run = 0, end_due = false, stop_due = nil, plan_recs = {},
        lod_of = {}, x4 = {}, rel_q = {}, n = { ok = 0, fail = 0, skip = 0, limb_skip = 0 } }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or os.clock() end
local function gnow() return S.game_time or 0 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function r3(v) return num(v) and math.floor(v * 1000 + 0.5) / 1000 or nil end
local function ms_since(t0) return r1((now() - t0) * 1000) end
local function text(s)
    s = tostring(s)
    return #s > R.ERR_CHARS and s:sub(1, R.ERR_CHARS) or s
end
-- How a lab_slice answer goes on ('ok', 'wait', 'refused', 'raised': SL.outcome), and its error text for a record
local outcome = SL.outcome
local function err_of(o, why, d) return (o ~= 'ok') and text(why) or (d and d.err) or nil end
local function mod(name)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
local function unit(v)
    if type(v) ~= 'table' or not (num(v.x) and num(v.y) and num(v.z)) then return nil end
    local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if l < 1e-6 then return nil end
    return { x = v.x / l, y = v.y / l, z = v.z / l }
end
local function vround(p) return p and { r1(p.x), r1(p.y), r1(p.z) } or nil end
local function nround(n) return n and { r3(n.x), r3(n.y), r3(n.z) } or nil end

-- ---------- Lua-only reads of the other modules (SL.corpse_state and SL.cut_jobs too) ----------
local corpse_state = SL.corpse_state
-- The sliced corpses still kept: lab_corpse's corpses whose key lab_slice sliced (the probe's too)
local function live_sliced()
    local K = mod('lab_corpse')
    if not (K and type(K.kept) == 'function') then return 0 end
    local ok, list = pcall(K.kept)
    if not ok or type(list) ~= 'table' then return 0 end
    local n = 0
    for _, c in ipairs(list) do if SL.sliced(c.key) then n = n + 1 end end
    return n
end
-- lab_corpse closed 'slicer.gone' for the session (a raised destroy, a failed sig): a sliced corpse could no longer go
local function gone_closed()
    local K = mod('lab_corpse')
    if not (K and type(K.status) == 'function') then return false end
    local ok, s = pcall(K.status)
    return ok and type(s) == 'table' and type(s.off) == 'table' and s.off['slicer.gone'] ~= nil
end
-- A job of the key queued or running (the same victim died again before its job ended)
local function in_flight(key)
    if st.job and st.job.key == key then return true end
    for _, j in ipairs(st.q) do if j.key == key then return true end end
    return false
end
local function layout_parts(layout)
    local p = (data('data.lab_pairs').pair or {})[layout]
    return type(p) == 'table' and type(p.parts) == 'table' and p.parts or {}
end

-- ---------- the parts, the planes, the side tests (pure) ----------
local function other(s) return s == 'l' and 'r' or 'l' end
-- A part's side test bone groups (plan section 5): far bones must lie more than SIDE_FAR_CM and near ones more than
-- SIDE_NEAR_CM on the body's side of the plane; a group is alternatives (the first the rig has counts). far, near
function R.sets(part)
    local far, near = {}, {}
    local function add(t, ...)
        for _, g in ipairs({ ... }) do t[#t + 1] = type(g) == 'table' and g or { g } end
    end
    local function low(s) return { 'lowerarm_' .. s, 'forearm_' .. s } end
    local stem, s = tostring(part):match('^(%a+)_([lr])$')
    if part == 'head' then
        add(far, 'pelvis', 'spine_01', 'spine_02', 'spine_03', 'thigh_l', 'thigh_r', 'calf_l', 'calf_r', 'foot_l',
            'foot_r', low('l'), low('r'), 'hand_l', 'hand_r')
        add(near, 'spine_04', 'spine_05', 'clavicle_l', 'clavicle_r', 'upperarm_l', 'upperarm_r')
    elseif stem == 'upperarm' or stem == 'lowerarm' then
        local x = other(s)
        add(far, 'pelvis', 'spine_01', 'spine_02', 'spine_03', { 'head', 'Head' }, 'thigh_l', 'thigh_r', 'calf_l',
            'calf_r', 'foot_l', 'foot_r', low(x), 'hand_' .. x)
        add(near, 'spine_05', 'clavicle_l', 'clavicle_r', 'upperarm_' .. x)
        if stem == 'lowerarm' then add(near, 'upperarm_' .. s) end
    elseif stem == 'thigh' or stem == 'calf' then
        local x = other(s)
        add(far, { 'head', 'Head' }, 'spine_02', 'spine_03', 'upperarm_l', 'upperarm_r', low('l'), low('r'), 'hand_l',
            'hand_r', 'calf_' .. x, 'foot_' .. x)
        add(near, 'pelvis', 'spine_01', 'thigh_' .. x)
        if stem == 'calf' then add(near, 'thigh_' .. s) end
    end
    return far, near
end
local function family_of(part)
    local f = KB.family(part)
    if f == 'head' then return 'head' end
    if f and f:sub(1, 3) == 'arm' then return 'arm' end
    return 'leg'
end
local function cell_of(part) return R.CELL[family_of(part)] or 12 end
-- The bones a part's chain takes off (the next re-slice's side test drops them)
local function chain_of(part)
    if part == 'head' then return CHAIN.head end
    local stem, s = tostring(part):match('^(%a+)_([lr])$')
    local out = {}
    for _, f in ipairs(CHAIN[stem] or {}) do out[#out + 1] = f:format(s) end
    return out
end
-- Every bone name the reads step wants: each part's cut and child candidates of the layout, the side tests' groups
local function names_all(layout)
    local out, seen = {}, {}
    local function add(n) if type(n) == 'string' and not seen[n] then seen[n], out[#out + 1] = true, n end end
    for _, e in pairs(layout_parts(layout)) do
        for _, n in ipairs(e.cut or {}) do add(n) end
        for _, n in ipairs(e.child or {}) do add(n) end
    end
    for _, p in ipairs({ 'head', 'upperarm_l', 'lowerarm_r', 'thigh_l', 'calf_r' }) do
        local far, near = R.sets(p)
        for _, list in ipairs({ far, near }) do for _, g in ipairs(list) do for _, n in ipairs(g) do add(n) end end end
    end
    table.sort(out)
    return out
end
-- The bones one part's cut frame wants: its cut and child bones and its side test's groups
local function names_part(p)
    local out, seen = {}, {}
    local function add(n) if type(n) == 'string' and not seen[n] then seen[n], out[#out + 1] = true, n end end
    add(p.bone)
    add(p.child)
    local far, near = R.sets(p.part)
    for _, list in ipairs({ far, near }) do for _, g in ipairs(list) do for _, n in ipairs(g) do add(n) end end end
    return out
end
-- The first candidate the read found on the rig, or nil
local function present(bones, list)
    for _, n in ipairs(list or {}) do if type(bones[n]) == 'table' then return n end end
    return nil
end
-- The groups resolved on the read: the first present name of each group; a group naming a gone bone drops; a group
-- with no present name and an unread one goes to unread (the side test then fails: an unread bone may lie over it)
local function resolve(bones, groups, gone)
    local out, unread = {}, {}
    for _, g in ipairs(groups) do
        local skip = false
        for _, n in ipairs(g) do if gone[n] then skip = true end end
        if not skip then
            local found, ur = nil, nil
            for _, n in ipairs(g) do
                local v = bones[n]
                if type(v) == 'table' then found = n break end
                if v ~= 'absent' then ur = ur or n end
            end
            if found then out[#out + 1] = found elseif ur then unread[#unread + 1] = ur end
        end
    end
    return out, unread
end
-- A part's plane (plan sections 4 and 5): P = cut + t (child - cut), N = unit(child - cut), t T_HEAD for the head and
-- T_LIMB for a limb; the part is the Positive half. P, N, length | nil, why
function R.plane(bones, p)
    local a, b = bones[p.bone], bones[p.child]
    if type(a) ~= 'table' or type(b) ~= 'table' then return nil, 'no_bones' end
    return SL.plane_of(a, b, p.part == 'head' and R.T_HEAD or R.T_LIMB)
end
-- The side test of a part on a bone read: { ok, fails, values }
function R.side(bones, part, P, N, gone)
    local fg, ng = R.sets(part)
    local far, ufar = resolve(bones, fg, gone or {})
    local near, unear = resolve(bones, ng, gone or {})
    local values, ok, fails = SL.side(bones, P, N, far, near, R.SIDE_FAR_CM, R.SIDE_NEAR_CM)
    for _, list in ipairs({ ufar, unear }) do
        for _, n in ipairs(list) do
            ok = false
            fails[#fails + 1] = 'unread:' .. n
        end
    end
    return { ok = ok, fails = fails[1] and fails or nil, values = values }
end
-- The kill's parts in slicing order: a copy in parts_of's rank order (D1 of docs/spec/fixes-0.2.2.md: the first part,
-- the struck one when a bone names it, is sliced first; the head never jumps ahead of it). The one ordering seam
function R.order(parts)
    local out = {}
    for i, p in ipairs(parts) do out[i] = p end
    return out
end
-- The kill's parts (lab_cut_beta parts_of on the bones the rig has; KB.nparts; limbs with META.beta_limbs), each
-- { part, src, bone, child } in slicing order, and what parts_of dropped; job.pick: parts_of's pick (its fifth value,
-- KB.first's draw before any filter) for the rank-1 slice record
local function plan_parts(job, bones)
    local cache = { parts = {} }
    for part, e in pairs(layout_parts(job.layout)) do
        local cut, child = present(bones, e.cut), present(bones, e.child)
        if cut and child then cache.parts[part] = { bone = cut, child = child, chain = {} } end
    end
    local kill = type(job.d.kill) == 'table' and job.d.kill or {}
    local parts, dropped, _, _, pick = KB.parts_of(kill, cache, KB.nparts(kill),
        { sweep = job.d.sweep_dir, limbs = META.beta_limbs == true })
    job.pick = pick
    local out = {}
    for _, p in ipairs(parts) do
        local e = cache.parts[p.part]
        if e then out[#out + 1] = { part = p.part, src = p.src, bone = e.bone, child = e.child } end
    end
    return R.order(out), dropped
end
R.plan_parts = plan_parts                               -- a test seam (tests/test_lab_slice_route.lua)
-- The impulse on the cut part's half: along the plane normal, the blow's sweep and up
local function push_dir(N, sweep)
    local s = unit(sweep) or { x = 0, y = 0, z = 0 }
    return unit({ x = N.x + R.SWEEP_K * s.x, y = N.y + R.SWEEP_K * s.y, z = N.z + R.SWEEP_K * s.z + R.UP_K }) or N
end

-- ---------- bookkeeping, records, counters ----------
local function reason_key(why) return (tostring(why):match('^[%w_]+') or 'other'):sub(1, 32) end
local function set_verdict(class, ok, why, detail)
    if type(class) ~= 'string' then return end
    st.verdict[class] = { ok = ok == true, why = why, detail = detail }
end
-- One failure toward the breaker (FAIL_OFF_N in a row: the route off for the session)
local function failed(why)
    st.fail_run = st.fail_run + 1
    if st.fail_run >= R.FAIL_OFF_N and not st.off then
        st.off = 'breaker'
        LAB.rec('slice_off', { why = 'breaker', last = text(why), run = st.fail_run }, true)
    end
end
-- A job's LOD state for its records (header 'pre'): the reads (SourceModels bits, #LODInfo, GetNumLODs,
-- ForcedLodModel), the ladder's rungs, Prepare's, the LOD chosen, r.FreeSkeletalMeshBuffers, the cut step's LOD 0
-- check; nil before any
local function lod_rec(job)
    if not (job.lodv or job.ladder or job.prep or job.lod or job.lod0) then return nil end
    return { reads = job.lodv, ladder = job.ladder, prep = job.prep, chosen = job.lod, free_buffers = st.free,
        lod0 = job.lod0 }
end
local function skip_rec(d, why, step, detail, part, lod, prep)
    st.n.skip = st.n.skip + 1
    LAB.count('slice_skip')
    LAB.count('slice_skip_' .. reason_key(why))
    if R.QUIET[why] then return end
    if step == 'plan' then                              -- the row's refusals: one record per class and reason a session
        local k = tostring(d.class) .. '|' .. tostring(why)
        if st.plan_recs[k] then return end              -- (the counters keep them all; LAB.CAP keeps the jobs' own)
        st.plan_recs[k] = true
    end
    LAB.rec('slice_skip', { id = d.id, class = d.class, layout = d.pair, part = part, why = why, step = step,
        detail = type(detail) == 'table' and detail or (detail ~= nil and text(detail) or nil), lod = lod, prep = prep },
        true)
end
-- A Prepare the job holds unreleased (it ended early) goes to the ticker's release queue: before its record
local function hand_off(job) PC.hand_off(job, st.rel_q, R.REL_MAX) end
-- The job ends; the key goes back to lab_corpse; its handle to the release queue
local function finish(job)
    if st.job == job then st.job = nil end
    SL.reserve(job.key, false)
    hand_off(job)
    if job.dropped_x and job.dropped_x[1] then
        st.n.limb_skip = st.n.limb_skip + 1
        LAB.count('slice_limb_skip')
        LAB.rec('slice_limb_skip', { id = job.id, class = job.class, sliced = job.done_parts, dropped = job.dropped_x,
            neg_cpu = job.cur and job.cur.neg_cpu, err = job.err }, true)
    end
end
-- lab_plan's row moves to row (with its tallies) and one lab_outcome { row, outcome, why } goes out: a death the route
-- holds no more and that takes no cut (Lua only)
local function no_cut(job, row, outcome, why)
    local L = mod('lab_plan')
    if L and type(L.reroute) == 'function' then pcall(L.reroute, job.id, row, job.layout) end
    BUS.emit('lab_outcome', job.id, { row = row, outcome = outcome, why = why })
end
-- A pre-cut job (or one whose slice left nothing) goes to the joint cut: today's route with the same payload. Never a
-- victim with an Akasha half on it (ours, SL.sliced, or the game's: 'has_halves'): lab_plan's 'sliced' rule, no cut
local function fallback(job, why, step, detail, raised)
    if raised then failed(tostring(why) .. ':' .. tostring(step)) end
    hand_off(job)
    local first = job.parts and job.parts[1] and job.parts[1].part or nil
    skip_rec(job.d, why, step, detail, first, lod_rec(job), job.pc)
    finish(job)
    if why == 'has_halves' or SL.sliced(job.key) then return no_cut(job, 'sliced', 'lab_skip', why) end
    local L = mod('lab_plan')
    if L and type(L.reroute) == 'function' then pcall(L.reroute, job.id, 'heads', job.layout) end
    BUS.emit('lab_row', 'heads', job.d)
end
-- Mod-off or the vanilla compare (header): false while new slicer work is held
local function on() return MODOFF.enabled('lab_slice_route') end
-- A queued job, or one that has not cut, dropped with no joint cut, the key back to lab_corpse (Lua only): while off
-- (lab_plan's 'off' row and its outcome, a counter), after a stop or lab_end ('not_armed', as lab_plan answers then;
-- the slice_skip record)
local function off_drop(job, why)
    why = why or 'modoff'
    hand_off(job)
    skip_rec(job.d, why, job.step or 'queue', nil, nil, lod_rec(job), job.pc)
    finish(job)
    if why == 'modoff' then return no_cut(job, 'off', 'refused', 'modoff') end
    no_cut(job, 'not_armed', 'lab_skip', why)
end
-- The parts not sliced after the first one (slice_limb_skip at the job's end)
local function drop_rest(job, from, why)
    job.dropped_x = job.dropped_x or {}
    for i = from, #job.parts do job.dropped_x[#job.dropped_x + 1] = { part = job.parts[i].part, why = why } end
    job.i = #job.parts + 1
end
-- A lab_slice answer that ends a pre-cut step: true on 'wait' (the same step next frame) and on anything but 'ok' (the
-- joint cut: word, or 'error' when the call raised, counted toward the breaker); false goes on
local function stops(job, ok, why, d, word, step)
    local o = outcome(ok, why, d)
    if o == 'ok' then return false end
    if o ~= 'wait' then fallback(job, o == 'raised' and 'error' or word, step, why, o == 'raised') end
    return true
end
-- A step refused 'lod_streaming' (the body asset's streaming update pending in that frame) runs again next frame, at
-- most STREAM_TRIES times over the job: true when this refusal is one of them
local function stream_retry(job, why)
    if why ~= 'lod_streaming' or job.stream_tries >= R.STREAM_TRIES then return false end
    job.stream_tries = job.stream_tries + 1
    return true
end

-- The prepared cut's steps (lab_slice_prep) on this route's fallback, breaker, class verdicts and streaming retries
PC.bind({ SL = SL, R = R, fallback = fallback, failed = failed, verdict = set_verdict, stream_retry = stream_retry,
    rec = function(ev, fields) LAB.rec(ev, fields, true) end })

-- ---------- routing (lab_plan's frame: Lua only) ----------
local function row_bad(row)
    if type(row) ~= 'table' then return 'no_row' end
    if type(row.hair_cloth) == 'table' and row.hair_cloth[1] ~= nil then return 'hair_cloth' end
    local f = type(row.flags) == 'table' and row.flags or {}
    if f.revives then return 'revives' end
    if f.explodes then return 'explodes' end
    return nil
end
local function lua_why(d, row)
    if C.knob('slicer') == false then return 'knob_off' end
    if C.stumps() == 'own' then return 'own_stumps' end   -- LeovvayGore's own stumps: never the game's slicer
    if not (MODOFF.enabled('lab_slice_route') and MODOFF.enabled('lab_slice')) then return 'modoff' end
    -- sched's breaker switched the route off: the bus skips its lab_row listener, a 'slice' row would get no cut at all
    if S.off()['lab_slice_route'] then return 'job_off' end
    if LAB.pinned() ~= true then return 'unpinned' end
    if not LAB.inherit_ok() then return 'stopped' end
    if st.off then return 'slice_off', st.off end
    local class = d.class
    if type(class) ~= 'string' or class:find('Player', 1, true) then return 'player' end
    -- D1 (docs/spec/fixes-0.2.2.md): a multi-part kill whose first part is a limb takes the joint cut, which plans it
    -- struck-first and keeps its extras (no re-slice ever ran live); a head-first or one-part kill goes on (pure Lua)
    if META.beta_limbs == true then
        local kill = type(d.kill) == 'table' and d.kill or {}
        if KB.nparts(kill) > 1 then
            local part, src, band, plane, psrc, exec = KB.first(kill, { sweep = d.sweep_dir })
            if part ~= 'head' then
                return 'multi_limb', { part = part, pick = src, band = band, plane = plane, plane_src = psrc,
                    exec = exec }
            end
        end
    end
    local fam = SL.cut_family(class, row)
    if not fam then return 'no_family' end
    local hurt = SL.hurt()
    if hurt then return 'struck', hurt end
    if SENT.is_disabled(SL.FAMILIES[fam]) then return 'disabled', SL.FAMILIES[fam] end
    if gone_closed() then return 'gone_closed' end      -- a new sliced corpse could never go (lab_corpse)
    local bad = row_bad(row)
    if bad then return 'class_row', bad end
    local v = st.verdict[class]
    if v and not v.ok then return v.why or 'verdict', v.detail end
    if st.cvar ~= nil and st.cvar ~= 0 then return 'cvar_engine_sim', tostring(st.cvar) end
    local m = st.mat
    if m and m.none and m.ep == ue.epoch and gnow() - m.t < R.MAT_RETRY_S then return 'no_cap_material' end
    if d.key == nil or st.cut_keys[d.key] then return 'joint_cut' end
    if in_flight(d.key) then return 'in_flight' end
    -- the reads step refuses a corpse lab_corpse does not keep: the row knows it already (Lua only)
    if corpse_state(d.key) ~= 'corpse' then return 'not_kept' end
    if #st.q >= R.QMAX then return 'queue_full' end
    if live_sliced() + #st.q + (st.job and 1 or 0) >= R.SLICED_MAX then return 'sliced_max' end
    return nil
end
-- lab_plan's beta row asks where it would give 'heads' (its frame: no native call). true: the row 'slice'
function R.wants(d, row)
    if not st.init or st.ended or type(d) ~= 'table' then return false end
    local why, detail = lua_why(d, row)
    if why == nil then return true end
    skip_rec(d, why, 'plan', detail, nil)
    return false, why
end

-- ---------- the steps (inside SL.step: the ticker's frame) ----------
local STEPS = {}
-- The slice entry of one part (the record's body)
local function new_slice(job, p, rank)
    return { part = p.part, src = p.src, rank = rank, bone = p.bone, child = p.child, cell = cell_of(p.part), ms = {} }
end
local function next_after_mat(job)
    local lod = st.lod_of[job.asset]                    -- the ladder's answer for this body asset (header 'pre')
    if lod then
        job.lod, job.step = lod, 'cut'
        return
    end
    if lod == false then
        set_verdict(job.class, false, 'preflight', 'cached_lod')
        return fallback(job, 'preflight', 'pre', 'cached_lod')
    end
    -- a plain LOD 0 preflight that passed (this route's or the probe's): the cut. One that failed decides nothing here
    -- any more: the ladder may still find a LOD (a job that ended mid-ladder left no answer), so the preflight again
    job.step = SL.verdict(job.asset) == true and 'cut' or 'pre'
end
local function next_after_reads(job)
    local m = st.mat
    if not (m and m.ep == ue.epoch and m.choice) then job.step = 'mat_find' return end
    return next_after_mat(job)
end
-- The class row's hats and masks (its fall list: every hat_mask name, data/cut_classes.lua), or nil
local function fall_names(job)
    local row = job.row
    if type(row) == 'table' and type(row.fall) == 'table' and row.fall[1] ~= nil then return row.fall end
    return nil
end
function STEPS.reads(job)
    local t0 = now()
    if corpse_state(job.key) ~= 'corpse' then return fallback(job, 'not_kept', 'reads', corpse_state(job.key)) end
    local ok, why, d = SL.brief(job.rec, fall_names(job))
    if stops(job, ok, why, d, 'reads', 'brief') then return end
    if not d.body_is_skm then return fallback(job, 'body', 'brief', 'body_not_skm') end
    if d.body_leader ~= 'none' then return fallback(job, 'body', 'brief', 'body_follower') end
    if d.body_visible == false or d.body_hidden == true then return fallback(job, 'body', 'brief', 'body_hidden') end
    if d.halves ~= 0 then return fallback(job, 'has_halves', 'brief', tostring(d.halves)) end
    job.asset, job.children = d.body_asset, d.names
    job.extras_pre = type(d.extras) == 'table' and d.extras or nil     -- the hats and masks before the cut
    local okb, wb, db = SL.bones(job.rec, names_all(job.layout))
    if stops(job, okb, wb, db, 'reads', 'bones') then return end
    local okl, wl, dl = SL.lodinfo({ 'body' })
    if stops(job, okl, wl, dl, 'cpu_unread', 'lodinfo') then return end
    local li = dl.lodinfo.body or {}
    job.cpu0, job.cpu_why = li.cpu, li.why              -- LOD 0's bit (SourceModels[1]): true | false | 'unread'
    job.lodv = { n_src = li.n, n_legacy = li.n_legacy, bits = li.bits, n_lods = li.n_lods, forced = li.forced }
    -- false goes on (no LOD 0 preflight, nothing written: the ladder from LOD 1, header 'pre'); unread goes on only
    -- soft (SourceModels read, no boolean: the native preflight gates CPU access itself, nothing written)
    if li.cpu ~= true and li.cpu ~= false and not li.soft then
        return fallback(job, 'cpu_unread', 'lodinfo', li.why)
    end
    if st.cvar == nil then                              -- the crash-flagged CVar, once a session
        local okc, wc, dc = SL.cvars()
        local oc = outcome(okc, wc, dc)
        if oc == 'wait' then return end
        -- a guard that refused read nothing (an armed.json write that failed once): this death takes the joint cut
        -- and the next job asks again; a read or a raised one is kept for the session
        if oc == 'refused' then return fallback(job, 'cvar_refused', 'cvars', wc) end
        st.cvar = type(dc) == 'table' and dc.engine_sim or 'unread'
        st.free = type(dc) == 'table' and dc.free_buffers or 'unread'     -- r.FreeSkeletalMeshBuffers, for the records
    end
    if st.cvar ~= 0 then return fallback(job, 'cvar_engine_sim', 'cvars', tostring(st.cvar)) end
    local parts, dropped = plan_parts(job, db.bones)
    job.parts = parts
    if not parts[1] then return fallback(job, 'no_part', 'reads', dropped[1] and dropped or nil) end
    local first = parts[1]
    local P, N = R.plane(db.bones, first)
    if not P then return fallback(job, 'side', 'reads', { part = first.part, why = N }) end
    local side = R.side(db.bones, first.part, P, N, {})
    if not side.ok then return fallback(job, 'side', 'reads', { part = first.part, fails = side.fails }) end
    job.P, job.N, job.i = P, N, 1
    job.ms.reads = ms_since(t0)
    return next_after_reads(job)
end
-- The cap material, once a map (header): the ladder's steps, each its own frame
local function set_mat(choice, why, info)
    st.mat = { ep = ue.epoch, choice = choice, why = why, none = choice == nil or nil, t = gnow(), info = info }
end
function STEPS.mat_find(job)
    local t0 = now()
    local ok, why, d = SL.mat_find()
    if stops(job, ok, why, d, 'cap_material', 'mat_find') then return end
    job.mat = { resident_before = d.resident }
    job.ms.mat = ms_since(t0)
    job.step = d.resident and 'mat_flags' or 'mat_load'
end
function STEPS.mat_load(job)
    local t0 = now()
    local ok, why, d = SL.mat_load()
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    if o == 'raised' then return fallback(job, 'error', 'mat_load', why, true) end
    job.mat.loaded, job.mat.load_ms = d and d.loaded, d and d.load_ms
    job.mat.load_err = err_of(o, why, d)
    job.ms.mat = (job.ms.mat or 0) + (ms_since(t0) or 0)
    job.step = 'mat_flags'
end
function STEPS.mat_flags(job)
    local t0 = now()
    local ok, why, d = SL.mat_flags()
    if stops(job, ok, why, d, 'cap_material', 'mat_flags') then return end
    local m = job.mat
    m.sk = d.sk and { skeletal = d.sk.skeletal, domain = d.sk.domain, base = d.sk.base } or nil
    m.chosen, m.why = d.choice and d.choice.name or nil, d.why
    m.alt = d.alt                                   -- the fallback when the M_SKInteriror hold fails
    job.ms.mat = (job.ms.mat or 0) + (ms_since(t0) or 0)
    if d.choice and d.choice.kind == 'sk_interior' then
        m.choice = d.choice
        job.step = 'mat_hold'
        return
    end
    set_mat(d.choice, d.why, m)
    if not d.choice then return fallback(job, 'no_cap_material', 'mat_flags', d.why) end
    return next_after_mat(job)
end
function STEPS.mat_hold(job)
    local ok, why, d = SL.mat_hold()
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    if o == 'raised' then return fallback(job, 'error', 'mat_hold', why, true) end
    local m = job.mat
    m.held = o == 'ok' and d.held == true or text(why)
    if o == 'ok' then set_mat(m.choice, 'sk_interior', m)
    else set_mat(m.alt, m.alt and 'hold_failed_look' or 'no_cap_material', m) end
    if not st.mat.choice then return fallback(job, 'no_cap_material', 'mat_hold', why) end
    return next_after_mat(job)
end
local pre_good = SL.pre_good
-- One rung's record (the ladder, header 'pre'): lod, the bit (before, set, restored), source data, the CPUAccess line
-- (success only), triangles, ms, the report's Notice line, why (a refusal or an error)
local function rung_rec(k, d, why)
    d = type(d) == 'table' and d or {}
    local b = type(d.bit) == 'table' and d.bit or {}
    return { lod = k, before = b.before, set = b.set, restored = b.restored, ok = d.ok, ret = d.ret, src_ok = d.src_ok,
        extract_failed = d.extract_failed, cpu = d.cpu, pos = d.pos, neg = d.neg, mix = d.mix, manual = d.manual,
        n_src = d.n_src, n_lods = d.n_lods, ms = d.ms, notice = d.notice, why = why ~= nil and text(why) or nil }
end
local function add_rung(job, k, d, why)
    job.ladder = job.ladder or {}
    job.ladder[#job.ladder + 1] = rung_rec(k, d, why)
end
-- The plane of the job's first part on bones read in this frame (a ragdoll moves between frames) -> true | nil
-- (stopped: waiting a frame, or fallen back)
local function plane_now(job, step)
    local first = job.parts[1]
    local okb, wb, db = SL.bones(job.rec, names_part(first))
    if stops(job, okb, wb, db, 'reads', step .. '_bones') then return nil end
    local P, N = R.plane(db.bones, first)
    if not P then
        fallback(job, 'side', step, { part = first.part, why = N })
        return nil
    end
    job.P, job.N = P, N
    return true
end
-- A good preflight whose ManualPoseSkinning echo is not true: the options did not arrive at their offsets, never
-- slice (the route off for the session). true when it stopped the job
local function marshal_bad(job, d)
    if not (pre_good(d) and d.manual ~= 'true') then return false end
    st.off = 'opts_marshal'
    LAB.rec('slice_off', { why = 'opts_marshal', manual = d.manual, class = job.class }, true)
    fallback(job, 'opts_marshal', 'pre', d.manual)
    return true
end
-- The ladder found LOD k: the cut slices it (with the bit set and restored when it read false); the body asset keeps
-- the answer for the session
local function chose(job, k, d)
    local b = type(d) == 'table' and type(d.bit) == 'table' and d.bit or {}
    job.lod = { k = k, set = b.before == false }
    st.lod_of[job.asset] = job.lod
    job.step = 'cut'
end
-- No LOD passed: the class goes to the joint cut for the session, the asset's answer kept
local function ladder_failed(job)
    local d = job.pre0 or {}
    st.lod_of[job.asset] = false
    set_verdict(job.class, false, 'preflight', { pos = d.pos, neg = d.neg, src_ok = d.src_ok })
    return fallback(job, 'preflight', 'pre', { pos = d.pos, neg = d.neg, src_ok = d.src_ok,
        extract_failed = d.extract_failed, lines = d.lines, cpu_why = job.cpu_why })
end
-- The rungs ran out: Prepare on LOD 0 once per body asset a session (X4: marked once its Prepare ran or was refused
-- for the session, so a job that ends before it leaves X4 to the next one), else the joint cut. Never when LOD 0's
-- bit read false: X4's LOD 0 rung would set it in its call, the write STEPS.pre skips
local function after_ladder(job)
    if not st.x4[job.asset] and job.cpu0 ~= false then
        job.step = 'prepare'
        return
    end
    return ladder_failed(job)
end
-- A rung or X4 refusal that holds for this asset or name for the session (the LOD out of range, its bit or the
-- SourceModels unreadable, the name switched off or its signature refused): the ladder ends there and its answer is
-- kept. Any other refusal (streaming still pending past STREAM_TRIES, the body or its target gone, a pending pin) is
-- this job's alone: the joint cut, the asset's answer left open (review: a short streaming streak turned the slicer off
-- for the body asset and its class for the session)
local LADDER_END = { lod_range = true, bit_unread = true, no_source_models = true, no_skeletal_mesh = true,
    disabled = true, disabled_by_sentinel = true, sig = true, unknown_name = true, inherit_off = true }
-- The LOD 0 preflight, the plain one (the bit read true, or soft). Good: the cut; 'failed while extracting source
-- data': the ladder (pre_lod); else once more, then the joint cut. A bit that read false: no LOD 0 preflight and no
-- write (header 'pre'), one ladder entry 'bit_false_skip', the ladder from LOD 1 next frame
function STEPS.pre(job)
    if job.cpu0 == false then
        add_rung(job, 0, { bit = { before = false } }, 'bit_false_skip')
        job.k, job.step = 1, 'pre_lod'
        return
    end
    local t0 = now()
    if not plane_now(job, 'pre') then return end
    local first = job.parts[1]
    local ok, why, d = SL.preflight(job.rec, 'body', job.P, job.N, cell_of(first.part))
    local o = outcome(ok, why, d)
    if o == 'wait' or stream_retry(job, why) then return end
    if o == 'raised' then return fallback(job, 'error', 'pre', why, true) end
    if o == 'refused' then return fallback(job, 'preflight', 'pre', why) end
    if not pre_good(d) and not d.extract_failed and job.tries < R.PRE_TRIES then   -- mid-transition: once more
        job.tries = job.tries + 1
        return
    end
    job.pre = { pos = d.pos, neg = d.neg, mix = d.mix, src_ok = d.src_ok, extract_failed = d.extract_failed,
        manual = d.manual, lod = d.lod, ms = d.ms, tries = job.tries + 1, notice = d.notice, bit = d.bit }
    job.pre0 = d
    add_rung(job, 0, d)
    job.ms.pre = ms_since(t0)
    if marshal_bad(job, d) then return end
    if pre_good(d) then return chose(job, 0, d) end
    if d.extract_failed then
        job.k, job.step = 1, 'pre_lod'
        return
    end
    return ladder_failed(job)
end
-- One rung a frame on LOD k = 1 .. min(LADDER_MAX, #SourceModels - 1, GetNumLODs - 1), the bit set and restored in
-- the call ('slicer.lodpre'); the first good one is cut
function STEPS.pre_lod(job)
    local k, v = job.k, job.lodv or {}
    local top = math.min(R.LADDER_MAX, (math.tointeger(v.n_src) or 1) - 1, (math.tointeger(v.n_lods) or 1) - 1)
    if k > top then return after_ladder(job) end
    if not plane_now(job, 'pre_lod') then return end
    local ok, why, d = SL.preflight_lod(job.rec, 'body', job.P, job.N, cell_of(job.parts[1].part), k)
    local o = outcome(ok, why, d)
    if o == 'wait' or stream_retry(job, why) then return end
    if o == 'raised' then return fallback(job, 'error', 'pre_lod', why, true) end
    add_rung(job, k, d, o ~= 'ok' and why or nil)
    if o == 'refused' then
        if LADDER_END[why] then return after_ladder(job) end    -- 'lod_range', 'bit_unread': no further rung
        return fallback(job, 'preflight', 'pre_lod', why)       -- this job's alone (LADDER_END)
    end
    if marshal_bad(job, d) then return end
    if pre_good(d) then return chose(job, k, d) end
    job.k = k + 1                                                -- the next LOD next frame
end
-- X4: Prepare on LOD 0 ('slicer.prepare': it forces LOD 0 streamed and rendered, copies nothing), then the LOD 0 rung
-- again once the streaming flag reads false (at most PREP_WAIT_F frames), then Release, then the cut or the joint cut
function STEPS.prepare(job)
    local ok, why, d = SL.prepare(job.rec, 'body', 0, R.PREP_LIFE_S)
    local o = outcome(ok, why, d)
    if o == 'wait' or stream_retry(job, why) then return end
    -- a refusal of this job's alone (LADDER_END) leaves X4 to the next job of the asset; else X4 is spent
    if o == 'refused' and not LADDER_END[why] then return fallback(job, 'preflight', 'prepare', why) end
    st.x4[job.asset] = true
    d = d or {}
    local h = d.handle
    if SL.zero_handle(h) then h = nil end              -- Prepare's zeroed handle: none
    job.prep = { ok = d.ok, ret = d.ret, ms = d.ms, forced = d.forced, err = err_of(o, why, d), wait_f = 0,
        handle = h and { lod = h.lod } or (d.handle and 'zero' or 'unread') }
    job.prep_h = h                                      -- released in STEPS.release, or by the ticker after an early end
    if o == 'raised' then return fallback(job, 'error', 'prepare', why, true) end
    if o ~= 'ok' or not h then return ladder_failed(job) end
    job.step = 'prepare_pre'
end
function STEPS.prepare_pre(job)
    if not plane_now(job, 'prepare_pre') then return end
    local ok, why, d = SL.preflight_lod(job.rec, 'body', job.P, job.N, cell_of(job.parts[1].part), 0)
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    if why == 'lod_streaming' and job.prep.wait_f < R.PREP_WAIT_F then
        job.prep.wait_f = job.prep.wait_f + 1
        return
    end
    job.prep.rung = rung_rec(0, d, o ~= 'ok' and why or nil)
    job.prep.good = o == 'ok' and pre_good(d) and d.manual == 'true'
    if o == 'raised' then failed('prepare_pre:' .. tostring(why)) end
    job.step = 'release'
end
function STEPS.release(job)
    local h = job.prep_h
    local ok, why, d = SL.release(h)
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    job.prep_h = nil
    job.prep.release = { ok = d and d.ok, ret = d and d.ret, err = err_of(o, why, d) }
    if o == 'raised' then failed('release:' .. tostring(why)) end
    if job.prep.good then return chose(job, 0, { bit = { before = job.prep.rung.before } }) end
    return ladder_failed(job)
end
-- The direct cut's LOD 0 check, in its cut frame before SL.cut (header 'cut'; X4's cut after Release too): SL.prep_read
-- with k 0 ('slicer.prep.read': ForcedLodModel, GetPredictedLODLevel), kept on the job (job.lod0), never for the asset.
-- -> true: the corpse renders LOD 0 (ForcedLodModel 0 or 1, GetPredictedLODLevel 0, nothing streaming), cut directly;
-- 'wait': the same step next frame; nil: moved on (the prepared cut on LOD 0 when LOD 0's bit read true, else the
-- joint cut 'lod0_not_rendered'; a refused or raised read: the joint cut)
local function lod0_check(job)
    local ok, why, d = SL.prep_read(job.rec, 'body', 0)
    local o = outcome(ok, why, d)
    if o == 'wait' then return 'wait' end
    if o ~= 'ok' then return fallback(job, o == 'raised' and 'error' or 'cut', 'lod0', why, o == 'raised') end
    local v = { forced = d.forced, predicted = d.predicted, pending = d.pending }
    job.lod0 = v
    if v.pending ~= false and stream_retry(job, 'lod_streaming') then return 'wait' end
    v.direct = v.pending == false and (v.forced == 0 or v.forced == 1) and v.predicted == 0
    if v.direct then return true end
    -- the prepared cut would set a false bit around its call and refuses an unread one: only on a bit that read true
    if job.cpu0 == true then return PC.begin(job, 0, 'lod0_not_rendered') end
    return fallback(job, 'lod0_not_rendered', 'lod0', v)
end
-- The slice of the job's current part: the first one on the body (SL.cut under the family's name) or a re-slice of
-- the last Negative half (SL.reslice). The plane's bones read in this frame first. -> 'wait' | nil (moved on)
local function slice_part(job, reslice)
    if reslice and not on() then                        -- mod-off: no next part (header)
        drop_rest(job, job.i, 'modoff')
        job.step = 'done'
        return
    end
    -- a first cut on a LOD above 0, or on LOD 0 whose bit read false: the prepared cut, its Prepare and wait first (a
    -- LOD 0 the corpse does not render goes there from the cut frame below: lod0_check)
    if not reslice and PC.wanted(job) and not job.pc then return PC.begin(job) end
    if SL.cut_frame() == S.frame then return 'wait' end
    if SL.cut_jobs() > 0 then                           -- lab_cut is busy: wait for it, at most CUT_WAIT_S
        job.cut_wait = job.cut_wait or gnow()
        if gnow() - job.cut_wait < R.CUT_WAIT_S then return 'wait' end
    end
    local p = job.parts[job.i]
    local t0 = now()
    local half = reslice and job.cur and job.cur.cut and job.cur.cut.neg or nil
    if reslice and not half then
        drop_rest(job, job.i, 'no_negative')
        job.step = 'done'
        return
    end
    local okb, wb, db = SL.bones(job.rec, names_part(p), half)
    local ob = outcome(okb, wb, db)
    if ob == 'wait' then return 'wait' end
    if ob ~= 'ok' then
        if not reslice then return fallback(job, ob == 'raised' and 'error' or 'cut', 'bones', wb, ob == 'raised') end
        if ob == 'raised' then failed('bones:reslice') end
        drop_rest(job, job.i, 'reslice_reads')
        job.step = 'done'
        return
    end
    local P, N = R.plane(db.bones, p)
    local side = P and R.side(db.bones, p.part, P, N, job.gone) or nil
    if not (P and side.ok) then
        local det = { part = p.part, why = (not P) and N or nil, fails = side and side.fails or nil }
        if not reslice then return fallback(job, 'side', 'cut', det) end
        job.dropped_x = job.dropped_x or {}
        job.dropped_x[#job.dropped_x + 1] = { part = p.part, why = 'side', fails = det.fails }
        job.i = job.i + 1
        job.step = job.i <= #job.parts and 'reslice' or 'done'
        return
    end
    local ms_bones = ms_since(t0)
    -- the first cut: LOD 0 with the bit read true under the family's name, only on a corpse that renders LOD 0 in this
    -- frame (lod0_check), else the prepared cut (lab_slice_prep: SlicePrepared with the handle, never the direct cut)
    local prep = (not reslice) and job.pc or nil
    if not (reslice or prep) then
        local r0 = lod0_check(job)
        if r0 ~= true then return r0 end
    end
    local t1 = now()
    local ok, why, d
    if reslice then ok, why, d = SL.reslice(job.rec, half, P, N, st.mat.choice, cell_of(p.part), job.key)
    elseif prep then ok, why, d = PC.cut(job, P, N, st.mat.choice, cell_of(p.part))
    else ok, why, d = SL.cut(job.fam, job.rec, P, N, st.mat.choice, cell_of(p.part), job.key) end
    local o = outcome(ok, why, d)
    if o == 'wait' or why == 'cut_this_frame' then return 'wait' end
    d = d or {}
    if d.ran ~= true then                               -- refused before the call: nothing was cut
        if stream_retry(job, why) then return 'wait' end
        if why == 'cap_material_gone' then st.mat = nil end
        if prep then return PC.refused(job, why, o) end     -- Release first, then the joint cut
        if not reslice then return fallback(job, 'cut_refused', 'cut', why, o == 'raised') end
        if o == 'raised' then failed('reslice:' .. tostring(why)) end
        drop_rest(job, job.i, 'reslice_refused:' .. reason_key(why))
        job.step = 'done'
        return
    end
    local s = new_slice(job, p, job.i)
    s.P, s.N, s.side = P, N, side
    s.ms.bones, s.ms.cut_step, s.ms.cut = ms_bones, ms_since(t1), d.ms
    s.cut = { ok = ok == true, ret = d.ret, why = (not ok) and text(why) or nil, err = d.err, pos = d.pos, neg = d.neg,
        pos_from = d.pos_from, neg_from = d.neg_from, named = d.named, cap = d.cap, lines = d.report,
        lod = prep and prep.k or nil,
        bit = d.bit, parsed = d.parsed and { ret = d.parsed.ret, pos_valid = d.parsed.pos_valid,
            neg_valid = d.parsed.neg_valid } or nil }
    s.prev_neg = half
    job.cut_any = true
    job.cur = s
    job.cut_wait = nil                                  -- each slice waits its own CUT_WAIT_S for lab_cut
    job.step = 'after'
    if prep then return PC.ran(job, ok, why) end        -- Release first, then the after step
end
function STEPS.cut(job) return slice_part(job, false) end
function STEPS.reslice(job) return slice_part(job, true) end
STEPS.prep, STEPS.prep_wait, STEPS.prep_release = PC.prep, PC.wait, PC.release
-- The slice record (once its post steps ended, or at an error)
local function slice_rec(job, s)
    if s.recorded then return end
    s.recorded = true
    local r = { id = job.id, class = job.class, part = s.part, src = s.src, rank = s.rank, fam = job.fam,
        layout = job.layout, asset = job.asset, ok = s.ok == true, why = s.why, ret = s.cut and s.cut.ret,
        cpu_why = job.cpu_why, ms = s.ms, total_ms = r1((now() - job.t_real) * 1000), n_halves = s.n_halves,
        halves = s.halves,
        positive_is_part = s.positive_is_part, cap_material = s.cut and s.cut.cap, cap_ok = s.cap_ok, cell = s.cell,
        side = s.side and { ok = s.side.ok, fails = s.side.fails, values = s.side.values } or nil, P = vround(s.P),
        N = nround(s.N), pos_cpu = s.pos_cpu, neg_cpu = s.neg_cpu, source = s.source, went = s.went,
        rehome = s.rehome, drop = s.drop, fix = s.fix, push = s.push, off = s.off, pos_from = s.cut and s.cut.pos_from,
        neg_from = s.cut and s.cut.neg_from, err = s.err or (s.cut and s.cut.err), cut_lod = s.cut and s.cut.lod,
        cut_bit = s.cut and s.cut.bit }
    if s.rank == 1 then
        r.pre, r.reads_ms, r.mat, r.lod, r.prep = job.pre, job.ms.reads, job.mat, lod_rec(job), job.pc
        r.pick = job.pick                               -- parts_of's pick (D3), as lab_cut's cut_plan carries it
    end
    if not s.ok and s.cut then r.lines, r.parsed = s.cut.lines, s.cut.parsed end
    LAB.rec('slice', r, true)
end
-- The after reads (the next frame): halves, children, source; the new halves' CPU bit. Lean: only what the slice
-- record and the next steps read (the part's bone on each half, the last material slot, no Niagara or name reads)
function STEPS.after(job)
    local s = job.cur
    local t0 = now()
    local want = { pos = s.cut.pos, neg = s.cut.neg, cap = s.cut.cap, children = job.children, bones = { s.child },
        lean = true, recs = true }
    local ok, why, d = SL.after(job.rec, s.P, s.N, want)
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    local pos, neg = nil, nil
    if o == 'ok' then
        s.halves = {}
        -- this slice's halves: the cut's result (by address, or its name cross-check); a first slice whose result
        -- read nothing takes any Akasha half (the actor held none before: SL.brief), a re-slice never an older one
        local any = s.rank == 1
        for _, h in ipairs(d.halves) do
            if h.from_res or any then
                if h.side == 'positive' and (not pos or (h.from_res and not pos.from_res)) then pos = h end
                if h.side == 'negative' and (not neg or (h.from_res and not neg.from_res)) then neg = h end
            end
            if s.prev_neg and h.name == s.prev_neg.name then
                s.prev_state = { visible = h.visible, hidden_in_game = h.hidden_in_game, sim = h.sim }
            end
        end
        -- a first slice whose cut frame listed no half (its component read failed there) takes the halves found now,
        -- so the bleed, the re-home, the impulse and the next part have them
        if pos and not s.cut.pos then s.cut.pos, s.cut.pos_from = pos.rec, 'after' end
        if neg and not s.cut.neg then s.cut.neg, s.cut.neg_from = neg.rec, 'after' end
        for _, h in ipairs({ pos or false, neg or false }) do
            if h then
                s.halves[#s.halves + 1] = { name = h.name, side = h.side, from_res = h.from_res, n_mat = h.n_mat,
                    cap = h.cap, cap_ok = h.cap_ok, swapped = h.swapped, sim = h.sim, bounds_side = h.bounds_side,
                    n_lods = h.n_lods }
            end
        end
        s.went = {}
        for _, c in ipairs(d.children or {}) do s.went[c.name] = c.went end
        s.source = d.source
        local t = pos and type(pos.bones) == 'table' and pos.bones[s.child] or nil     -- the part's bone on its half
        if type(t) == 'table' and num(t[1]) and num(t[2]) and num(t[3]) then s.tip = { x = t[1], y = t[2], z = t[3] } end
        local okl, wl, dl, pc, nc = SL.half_cpu(pos, neg)
        if okl then
            s.pos_cpu, s.neg_cpu = pc, nc
        else
            s.neg_cpu = 'unread'
            if outcome(okl, wl, dl) == 'raised' then failed('lodinfo:after') end
        end
    else
        s.err = 'after: ' .. text(why)
        if o == 'raised' then failed('after') end
    end
    s.ms.after = ms_since(t0)
    -- halves by the cut's own result when the after read failed (the records only)
    local np = (pos ~= nil or (o ~= 'ok' and s.cut.pos ~= nil)) and 1 or 0
    local nn = (neg ~= nil or (o ~= 'ok' and s.cut.neg ~= nil)) and 1 or 0
    s.n_halves = np + nn
    s.positive_is_part = pos ~= nil and pos.bounds_side == 1
    s.cap_ok = pos ~= nil and pos.cap_ok == true
    s.ok = s.cut.ok == true and s.n_halves == 2
    if s.ok then
        st.n.ok = st.n.ok + 1
        if o == 'ok' then st.fail_run = 0 end          -- an after read that raised stays in the breaker's run
        LAB.count('slice_ok')
    else
        st.n.fail = st.n.fail + 1
        LAB.count('slice_fail')
        s.why = s.cut.why or ('halves_' .. s.n_halves)
        failed('slice:' .. tostring(s.why))
        if s.rank == 1 then set_verdict(job.class, false, 'slice_failed', s.why) end
    end
    local shown = type(s.source) == 'table' and s.source.visible ~= false and s.source.hidden_in_game ~= true
    if s.n_halves == 0 and s.rank == 1 and shown then       -- nothing was cut: the joint cut takes the victim
        slice_rec(job, s)
        return fallback(job, 'slice_failed', 'after', s.why)
    end
    if s.n_halves > 0 then SL.mark_sliced(job.key) end
    job.done_parts = job.done_parts or {}
    job.done_parts[#job.done_parts + 1] = s.part
    for _, b in ipairs(chain_of(s.part)) do job.gone[b] = true end
    if not on() then s.off = 'modoff' end               -- mod-off: the reads and the source fix only (header)
    if s.ok and not s.off then
        BUS.emit('lab_slice_live', { kind = 'slice', key = job.key, id = job.id, class = job.class, part = s.part,
            rank = s.rank, layout = job.layout, rec = job.rec, pos = s.cut.pos, neg = s.cut.neg, P = s.P, N = s.N,
            bone = s.bone, child = s.child, prev = s.prev_neg, t = now() })
    end
    -- a head slice: the row's head components, and its skinned hair and glow, belong to the head half (the slicer
    -- moves a follower or an attached child by its bounds; a meshhead's centre sits below the neck); its hats and
    -- masks fall off (header)
    job.rehome, job.drops = nil, nil
    if s.part == 'head' and not s.off and type(job.row) == 'table' and s.cut.pos and s.went then
        local seen = {}
        local function rehome(n)
            if not seen[n] and s.went[n] and s.went[n] ~= 'positive' and s.went[n] ~= 'gone' then
                seen[n] = true
                job.rehome = job.rehome or {}
                job.rehome[#job.rehome + 1] = n
            end
        end
        for _, kind in ipairs(R.REHOME) do
            for _, n in ipairs(type(job.row[kind]) == 'table' and job.row[kind] or {}) do rehome(n) end
        end
        local G = mod('lab_gib')
        local okg, ready = false, false
        if G and type(G.ready) == 'function' then okg, ready = pcall(G.ready, 'slice_fall') end
        ready = okg and ready == true
        for _, n in ipairs(fall_names(job) or {}) do
            local pre = job.extras_pre and job.extras_pre[n]
            if type(pre) == 'table' and pre.drawn == true and not seen[n] then
                if ready then
                    seen[n] = true
                    job.drops = job.drops or {}
                    job.drops[#job.drops + 1] = n
                elseif pre.kind == 'skinned' then
                    rehome(n)                               -- no fall now: it rides with the head half
                end
            end
        end
    end
    job.step = job.rehome and 'rehome' or job.drops and 'drop' or 'fix'
end
function STEPS.rehome(job)
    local s = job.cur
    local t0 = now()
    if not on() then                                    -- mod-off since the after step: left as the game made it
        s.off, s.rehome, job.step = 'modoff', 'modoff', 'fix'
        return
    end
    s.rehome = {}
    for _, n in ipairs(job.rehome or {}) do
        local ok, why, d = SL.rehome(job.rec, n, s.cut.pos)
        local o = outcome(ok, why, d)
        if o == 'wait' then return end
        s.rehome[#s.rehome + 1] = { name = n, ok1 = d and d.ok1, ok2 = d and d.ok2,
            parent_after = d and d.parent_after, err = err_of(o, why, d) }
        if o == 'raised' then failed('rehome') end
    end
    s.ms.rehome = ms_since(t0)
    job.step = job.drops and 'drop' or 'fix'
end
-- A head slice's hats and masks fall off as at a joint cut (header): each read and hidden under 'slicer.drop', then
-- bus lab_slice_fall for lab_gib's falling copies (from the head half's head bone, with the head's launch)
function STEPS.drop(job)
    local s = job.cur
    local t0 = now()
    if not on() then                                    -- mod-off since the after step: left as the game made it
        s.off, s.drop, job.step = 'modoff', 'modoff', 'fix'
        return
    end
    local ok, why, d = SL.drop(job.rec, job.drops)
    local o = outcome(ok, why, d)
    if o == 'wait' then return end
    s.drop = { names = job.drops }
    if o == 'ok' then
        local extras, hidden = {}, 0
        for _, it in ipairs(d.items or {}) do
            if it.rec then
                if it.hidden then hidden = hidden + 1 end
                extras[#extras + 1] = { name = it.name, rec = it.rec, class = it.kind, src = 'row', fall = true,
                    xf = it.xf }
            end
        end
        s.drop.hidden = hidden
        if extras[1] then
            local dir = push_dir(s.N, job.d.sweep_dir)
            local v = R.HEAD_V                          -- a head slice's step only (STEPS.after)
            BUS.emit('lab_slice_fall', { key = job.key, id = job.id, class = job.class, part = s.part, at = s.tip,
                vel = { x = dir.x * v, y = dir.y * v, z = dir.z * v }, extras = extras })
            s.drop.sent = #extras
        end
    else
        s.drop.err = text(why)
        if o == 'raised' then failed('drop') end
    end
    s.ms.drop = ms_since(t0)
    job.step = 'fix'
end
-- The post-fix of what the slice hid, the impulse on the part, the record; then the next part or the end
function STEPS.fix(job)
    local s = job.cur
    local t0 = now()
    local hid = s.source                                -- what the slice hid: the source, or the re-sliced half
    if s.prev_neg then hid = s.prev_state end
    -- unread (the after read failed, or missed the re-sliced half): with halves made the slicer hid what it cut, so
    -- that is fixed all the same (left simulating, it would fall without bound)
    if not s.fixed and s.n_halves > 0 and (hid == nil or hid.visible == false or hid.hidden_in_game == true) then
        local ok, why, d
        if s.prev_neg then ok, why, d = SL.fix_half(s.prev_neg) else ok, why, d = SL.fix_source(job.rec) end
        local o = outcome(ok, why, d)
        if o == 'wait' then return end
        s.fix = { ok = d and d.ok, sim_before = d and d.sim_before, sim_after = d and d.sim_after,
            err = err_of(o, why, d) }
        if o == 'raised' then failed('fix') end
    end
    s.fixed = true                                      -- a pending impulse below re-runs this step, never the fix
    if not on() then s.off = 'modoff' end               -- mod-off: no impulse, no next part (header)
    if s.off then
        s.push = s.ok and { skipped = s.off } or nil
    elseif s.ok and s.cut.pos then
        local dir = push_dir(s.N, job.d.sweep_dir)
        local speed = s.part == 'head' and R.HEAD_V or R.LIMB_V
        local ok, why, d = SL.push(s.cut.pos, dir, speed, s.child)
        local o = outcome(ok, why, d)
        if o == 'wait' then return end                  -- a pending sig: the impulse next frame
        s.push = { ok = d and d.ok, speed = speed, dir = nround(dir), err = err_of(o, why, d) }
        if o == 'raised' then failed('push') end
    end
    s.ms.fix = ms_since(t0)
    slice_rec(job, s)
    -- the next part (plan section 5 G-RESLICE): the Negative half holds it; its CPU bit decides
    if s.off and job.i < #job.parts then
        drop_rest(job, job.i + 1, s.off)
    elseif s.ok and job.i < #job.parts then
        if s.neg_cpu == true then
            job.i = job.i + 1
            job.step = 'reslice'
            return
        end
        drop_rest(job, job.i + 1, s.neg_cpu == false and 'neg_cpu_false' or 'neg_cpu_unread')
    elseif job.i < #job.parts then
        drop_rest(job, job.i + 1, 'slice_failed')
    end
    job.step = 'done'
end
function STEPS.done(job) return finish(job) end

-- ---------- the ticker ----------
local function start(job)
    job.step, job.tries, job.stream_tries, job.ms, job.gone = 'reads', 0, 0, {}, {}
    job.fam = SL.cut_family(job.class, job.row)
end
local function step_once(job)
    local fn = STEPS[job.step]
    if not fn then return finish(job) end
    return fn(job)
end
-- The parts after the last one sliced (job.cur's rank): in the 'reslice' step job.i already names the next one
local function next_part(job) return (job.cur and job.cur.rank or job.i or 0) + 1 end
-- A job whose step raised a Lua error: the joint cut when nothing was cut yet, else the record and the end (the error
-- on the slice record when it is not written yet, always on the slice_limb_skip one)
local function error_out(job, err)
    if not job.cut_any then return fallback(job, 'error', job.step, err, true) end
    failed('step:' .. tostring(job.step))
    hand_off(job)
    job.err = 'error: ' .. text(err)
    local s = job.cur
    if s and not s.recorded then
        s.err = job.err
        slice_rec(job, s)
    end
    drop_rest(job, next_part(job), 'error')
    finish(job)
end
-- A stop or lab_end: the uncut jobs drop with no joint cut (lab_plan answers 'not_armed' then, and lab_cut runs
-- nothing after lab_end); a job that cut ends with its record
local function abort_all(why)
    for _, j in ipairs(st.q) do off_drop(j, why) end
    st.q = {}
    local job = st.job
    if not job then return end
    if not job.cut_any then return off_drop(job, why) end
    hand_off(job)
    if job.cur then slice_rec(job, job.cur) end
    drop_rest(job, next_part(job), why)
    finish(job)
end
-- A Prepare a job left unreleased (it ended early: header 'pre'): one SL.release a frame, before anything else and
-- also while off or after the end (it gives the component its forced LOD back); counted slice_release_late (and
-- slice_release_late_fail). true when this frame's step went to it
local function release_late()
    local h = st.rel_q[1]
    if not h or LAB.paused() or (st.busy_f and S.frame - st.busy_f <= 1) then return false end
    if not h.stepped then                               -- lab_slice_prep's slice_step, before the first attempt
        h.stepped = true
        LAB.rec('slice_step', { id = h.id, step = 'release_late', k = h.lod }, true)
    end
    local okc, ok, why = SL.step(SL.release, h)
    if okc and not ok and why == 'sig_pending' then return true end
    table.remove(st.rel_q, 1)
    LAB.count('slice_release_late')
    if not (okc and ok) then LAB.count('slice_release_late_fail') end
    return true
end
local function tick()
    if not st.init then return end
    if release_late() or st.ended then return end
    if st.end_due then
        st.ended = true
        abort_all('lab_end')
        return
    end
    if st.stop_due then
        st.stop_due = nil
        abort_all('stop')
        return
    end
    if not (st.job or st.q[1]) then return end
    if not on() then                                    -- mod-off (header): Lua only, paused or not
        local q = st.q
        st.q = {}
        for _, j in ipairs(q) do off_drop(j) end
        if st.job and not st.job.cut_any then off_drop(st.job) end
        if not st.job then return end
    end
    if LAB.paused() then return end
    local g = gnow()
    for i = #st.q, 1, -1 do                             -- queued past the deadline: the joint cut (Lua only)
        local j = st.q[i]
        if g - j.g0 > R.TIMEOUT_S then
            table.remove(st.q, i)
            fallback(j, 'timeout', 'queue')
        end
    end
    if not st.job then
        st.job = table.remove(st.q, 1)
        if not st.job then return end
        start(st.job)
    end
    local job = st.job
    if not job.cut_any then
        if C.knob('slicer') == false then return fallback(job, 'knob_off', job.step) end
        if C.stumps() == 'own' then return fallback(job, 'own_stumps', job.step) end
        -- the breaker or a failed slice of the class since its row: as lua_why refuses new rows
        if st.off then return fallback(job, 'slice_off', job.step, st.off) end
        local v = st.verdict[job.class]
        if v and not v.ok then return fallback(job, v.why or 'verdict', job.step, v.detail) end
        if g - job.g0 > R.TIMEOUT_S then return fallback(job, 'timeout', job.step) end
    end
    if job.f0 == S.frame then return end                -- never in the row's frame (lab_plan's)
    if st.busy_f and S.frame - st.busy_f <= 1 then return end      -- a kill frame or the one after: no native step
    local ok, err = SL.step(step_once, job)
    if not ok and st.job == job then error_out(job, err) end
end

-- ---------- the bus (listeners only queue or note) ----------
local function on_row(row, d)
    if row ~= 'slice' or not st.init or type(d) ~= 'table' or d.key == nil then return end
    SL.reserve(d.key, true)                             -- lab_corpse never lets it go before the job ends
    st.q[#st.q + 1] = { d = d, key = d.key, id = d.id, class = d.class, row = d.class_row, layout = d.pair,
        rec = d.victim or d.keep, g0 = gnow(), f0 = S.frame, t_real = now() }
end
local function on_cut_live(cut)
    st.busy_f = S.frame
    if type(cut) == 'table' and cut.key ~= nil then st.cut_keys[cut.key] = true end
end
local EVENTS = { 'lab_row', 'lab_death', 'lab_cut_live', 'lab_end', 'lab_stop' }

-- ---------- lifecycle ----------
-- Inert unless the player beta with META.beta_slicer and lab_slice up
function R.init(adapter)
    A = adapter
    st = new_state()
    local meta = adapter and adapter.meta or META
    if not (LAB.beta() and type(meta) == 'table' and meta.beta_slicer == true) then return true end
    local ok, s = pcall(SL.status)
    if not (ok and type(s) == 'table' and s.init == true) then return true end
    st.init = true
    for _, k in ipairs(R.COUNTERS) do LAB.count(k, 0) end
    MODOFF.feature('lab_slice_route', { gameplay = true })   -- mod-off and the vanilla compare stop new slices only
    BUS.on('lab_row', 'lab_slice_route', on_row)
    BUS.on('lab_death', 'lab_slice_route', function() st.busy_f = S.frame end)
    BUS.on('lab_cut_live', 'lab_slice_route', on_cut_live)
    BUS.on('lab_end', 'lab_slice_route', function() st.end_due = true end)
    BUS.on('lab_stop', 'lab_slice_route', function(why) st.stop_due = why or 'stop' end)
    S.ticker('lab_slice_route', tick)
    return true
end
-- A map load: the queued and running jobs and the cap material choice went with the old map (no record: their
-- corpses are gone); the joint-cut keys, the class verdicts, the CVar and the breaker stay
function R.reset(reason)
    if not st.init or reason ~= 'map' then return end
    st.q, st.job, st.mat, st.busy_f, st.rel_q = {}, nil, nil, nil, {}
end
function R.status()
    local v = 0
    for _ in pairs(st.verdict) do v = v + 1 end
    return { init = st.init, ended = st.ended, queued = #st.q, step = st.job and st.job.step or nil, ok = st.n.ok,
        fail = st.n.fail, skip = st.n.skip, limb_skip = st.n.limb_skip, off = st.off, sliced = live_sliced(),
        mat = st.mat and st.mat.choice and st.mat.choice.name or nil, verdicts = v, cvar = st.cvar, free = st.free,
        releases = #st.rel_q }
end
-- Engine-free (Ctrl+R runs it off the game thread)
function R.shutdown()
    S.remove_ticker('lab_slice_route')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_slice_route') end
    st, A = new_state(), nil
end
return R
