-- status: new in M1a A3.2 (offline only; TC-LAB-02 decides) origin: kb:testing-lab-playtest#first-in-game-session-on-a-new-game-a-passive-probe-and-numbered-lab-gates-tc-lab-01
-- lab_plan.lua: TC-LAB-02's row plan, per-class readiness and the proof ladder bookkeeping (spec M1a D7, D30, sections
-- 3.5, 3.6, 3.9). Dev builds, dev set 'lab02' (META.dev_sets, main.lua), and the player beta (META.beta_modules); no
-- other build requires it, and init stays inert (no listener, no ticker, no record) unless LAB.cut_set(). No engine
-- call: it reads the bus, lab_probe's proofs and sig answers, and the env record of adapter/session_pbz.lua; the beta
-- also reads data/cut_classes.lua, data/no_blood.lua, data/lab_pairs.lua and core/config.lua's effects.cut and the
-- knob cut_chance.
-- * Rows (section 3.6, D7): each bus lab_death is queued with its frame and planned on a later tick (the tick after
--   lab_death whatever the ticker order), first match wins: pair 'other' (lab_skip 'other'); mod-off or the vanilla
--   compare (refused 'modoff'); kill.execution (lab_skip 'execution'); a stop, L0i-lite not ok or a failed P1
--   (not_armed, lab_skip 'stopped', 'no_l0i' or 'l0i_nogo'); CTRL_N controls (keep_ctrl); KEEP_N kept-only, the last
--   slot kept for a GuiChai while none was kept (keep_only); Heads when the pair is ready (heads, no outcome: lab_cut
--   sends it); else keep_only with the route's word: 'proof_pending' while a class is pending, else the first failure
--   ('no_keep', 'no_comp_hide', 'calls_missing', 'sig_mismatch', 'sig_unknown', 'disabled' lab_skip; 'cap_attach' and
--   'no_cap' refused, section 3.5). Every row goes out as bus lab_row(row, d); every no-cut row also as lab_outcome(id,
--   {row, outcome, why}). kills_off counts every death while off. After lab_end no row (lab_poll wrote it).
-- * The beta's rows (LAB.beta(); docs/research/beta-dismemberment-plan.md BD9, replacing beta port S3; the author's
--   answers of 2026-10-31), first match wins, and no control or kept-only slot ever (review round 1: lab_cut's limbq,
--   p1q and compq stay empty): a class whose name holds 'Player', a data/no_blood.lua class, or one data/cut_classes.lua
--   does not list or lists with a layout data/lab_pairs.lua lacks ('not_cut_class', lab_skip, why 'player',
--   'no_blood', 'not_listed', 'no_table' or 'bad_row'); mod-off or the vanilla compare ('off', refused 'modoff'); a
--   key the game's slicer cut ('sliced', lab_slice sliced(key): no cut row ever, docs/research/slicer-stumps.md);
--   kill.execution ('exec', answer 12); in the test build the slicer probe's claim ('slicer_hold', lab_skip, why
--   'slicer_probe': lab_slice_probe claim(d) holds the next spawned target death uncut while its hold is armed); kill.attack_kind 'kick' or 'deflect' ('no_cut_blow', why the kind: answer 3);
--   kill.bleed_only true ('bleed_only', a bleed or blood-burst death with no blow in its frame: answer 4); the mod
--   setting effects.cut off ('cut_off', why 'effects_cut'); a stop, L0i-lite not ok or a failed P1 ('not_armed'); then
--   Heads when the row's base pair is ready (M.base: MaleThug's route for a body layout, GuiChai's with P17 for a
--   meshhead one or a body row that hides components), else 'not_ready' with the route's word ('unpinned',
--   'proof_pending' ...). A kill that would be cut then rolls the knob cut_chance (a percent; spec fixes-0.2.2 D5,
--   Nexus 178914417): one draw of core/rng.lua seeded 'cut_chance'|the kill id, so a kill gets the same verdict on
--   every boot, and no draw at 100 (today's rows); a lost roll is 'cut_chance' (lab_skip, why 'chance', the schema's
--   skip word), which still bleeds (lab_blood takes bus lab_death, not lab_row) and applies to NPC kills too.
--   Where Heads would go, the game's own slicer takes the death when lab_slice_route wants it
--   (R.wants(payload, row), Lua only: the knob 'slicer', the class's slicer verdict, its family's names, the cap
--   material, SLICED_MAX, no joint cut on the key; docs/research/slicer-stumps.md sections 4, 5 and 7): row 'slice',
--   the same payload, no outcome. A slice job that cannot slice hands the death back as 'heads' (M.reroute: the row
--   and the plan record's tallies follow; lab_slice_route emits the lab_row). A beta Heads row goes out with a shallow
--   copy of d: pair = the row's layout (MaleThug,
--   GuiChai, BodyCopy or MeshHead), class_row = the row; a kill that is not the player's (kill.by_player not true:
--   an NPC's kill, a poll kill) carries a copy of its kill with tier 'normal' (tier_src 'none'): one part (answer 5;
--   lab_poll's tier says so already, this keeps it whatever the tier read). One unforced kill_row record per beta row
--   { id, class, row, outcome, why, layout }: the beta writes its kill record at confirm, before the row (S5).
-- * Reservations (spec M1a 4.1 item 1, the pre-arm): at bus lab_admit a lab-pair pawn (MaleThug, GuiChai) admitted
--   while the lab is armed and the mod is on is reserved in lab_probe's ledger (LAB.reserve, shared with lab_keep): the
--   first CTRL_N of the session are controls, every later one is pre-armed (lab_keep writes the levers before its
--   death).
--   At its death (the lab_death payload's key) a reserved control gets keep_ctrl whatever the count, and a pre-armed
--   pawn skips the control slots and takes the first free row of today's order (keep_only, then heads); a pawn that
--   was never reserved gets today's rule (CTRL_N controls first) and no write ever (lab_keep: why 'not_prearmed').
-- * Readiness (D30, section 3.5): Heads for a pair = L0i-lite ok, no stop, no commit name (lab.cut.stage,
--   lab.cut.head, hide.bone) disabled by the sentinel, and every group of M.HEADS (P1, P2, P6, P7 or P8; GuiChai also
--   P17) with a class that is not disabled, has every calls id present in env (calls_missing lists the path, or the key
--   of an id without one), answered its sig 'ok' and passed its proof (bus lab_proof, LAB.proof); a failed P3 or P4
--   fails P7 too (M.NEEDS: the meat route only), so P8 failing then ends the route 'no_cap'; Pieces = P11-P15
--   likewise. A missing name blocks only the classes that list it (data/lab_classes.lua). The beta (LAB.beta(), beta
--   port S2): Heads without the P2 group (no lab_keep; the proofs are lab_probe's pinned seed), and both routes read
--   'unpinned' once the pin check failed.
-- * Sigs (D17): once env is written, LAB.sig for every class of data/lab_classes.lua (sig_step below); the beta for
--   the classes of M.SIGS_BETA only, the ones its cut route arms or reads readiness from (BD9), and in the author's
--   test build (META.beta_spawn) M.SIGS_SPAWN too, while lab_spawn runs, and lab_slice's names with a class row
--   (SL.NAMES less slicer.blood) while lab_slice_route or lab_slice_probe runs.
-- * Records and counters: plan (section 3.1, forced) at init, at each readiness change ('ready'), at each lab_flush
--   ('lab_flush'; lab_flush 'lab_end' adds none) and once at lab_end; new_while_off and kills_off published at 0 from
--   init. new_while_off counts a lab_proof or lab_cut_live that arrives while off or under the vanilla compare (a bug
--   detector that must stay 0). The read-only dev command 'lab_status' (no world spec, D19) answers with the record.
--   Under the beta the record's rows are heads per layout and the beta's skip rows (M.BETA_ROWS), the rest 'other'.
-- * MODOFF.feature('lab_plan', {gameplay = true}): the vanilla compare blocks it as mod-off does.
-- API: ready(pair) pieces(pair) base(row) row_of(id) reroute(id, row, pair) quiet() consent([key]) classes();
--   lifecycle init(A, opts)
--   shutdown(reason) status() reset(reason). opts.env: a function returning the env record (tests); else SP.env.
-- What the mock cannot prove: the real order of lab_death against the other tickers, the cost of a LAB.sig frame on
-- PBZ (its arm writes), whether the env record lands before the first death of a session.
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local DEV = require('core.dev')
local C = require('core.config')
local SP = require('adapter.session_pbz')
local LAB = require('lab_probe')
local RNG = require('core.rng')

local M = { CTRL_N = LAB.CTRL_N, KEEP_N = 5, QUIET_DEATH_S = 10, QUIET_HIT_S = 3, SIG_RETRY_S = 10, INBOX = 256,
    IDS = 512,
    PAIRS = { 'MaleThug', 'GuiChai' } }
-- The beta (BD9): each data/cut_classes.lua layout and the proven pair whose readiness it takes (M.base); the plan
-- record's rows; a kick or a deflect counter never cuts (answer 3)
M.BASE = { MaleThug = 'MaleThug', BodyCopy = 'MaleThug', GuiChai = 'GuiChai', MeshHead = 'GuiChai' }
M.BETA_ROWS = { 'heads_MaleThug', 'heads_GuiChai', 'heads_BodyCopy', 'heads_MeshHead', 'not_cut_class', 'no_cut_blow',
    'bleed_only', 'cut_off', 'not_ready', 'sliced', 'slicer_hold', 'slice', 'cut_chance', 'other' }
M.NO_CUT_BLOW = { kick = true, deflect = true }

-- Names this module reads: none (no engine call); registered for the names contract (spec A3.2)
local N = {}
local F = {}
M.N, M.F = N, F

local A, cfg = nil, nil
local function new_state()
    return { init = false, q = {}, qdrop = 0, rows = {}, ids = {}, nids = 0, id_order = {}, ctrl = 0, keep = 0,
        keep_gc = 0, sig = {}, sig_left = nil, sig_at = {}, covered = {}, miss = nil, env = false, dirty = true,
        last_key = nil, l0i = nil, inherit = nil, last_death = nil, last_hit = nil, off_n = 0, end_due = false,
        ended = false, flushq = {}, after_end = 0, kills_off = 0 }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or 0 end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end

-- ---------- the ladder and the routes (section 3.5) ----------
-- Every ladder step by name, for the plan record's proofs
M.LADDER = { { 'P1', 'lab.inherit.hide' }, { 'P1b', 'probe.static.GetTimeSeconds' }, { 'P2', 'keep.write' },
    { 'P3', 'cap.pmc' }, { 'P4', 'lab.tarray.probe' }, { 'P5', 'cap.mid' }, { 'P6', 'cap.parent' },
    { 'P7', 'cap.mesh' }, { 'P8', 'cap.meat' }, { 'P9', 'cap.destroy' }, { 'P9b', 'cap.keep' }, { 'P10', 'hide.optim' },
    { 'P11', 'piece.spawn' }, { 'P12', 'piece.mesh' }, { 'P13', 'piece.pose' }, { 'P14', 'piece.isolate' },
    { 'P15', 'piece.phys' }, { 'P16', 'piece.destroy' }, { 'P17', 'hide.comp' }, { 'P18', 'hide.tag' } }
-- A route is a list of groups; a group holds alternatives (P7 or P8) and the word its failure ends the route with
-- (section 3.5 'On failure'); refused: that word ends a kill refused (a failure), else lab_skip
M.HEADS = { { 'lab.inherit.hide', why = 'l0i_nogo' }, { 'keep.write', why = 'no_keep' },
    { 'cap.parent', why = 'cap_attach', refused = true }, { 'cap.mesh', 'cap.meat', why = 'no_cap', refused = true } }
M.HEADS_GC = { { 'hide.comp', why = 'no_comp_hide' } }          -- GuiChai only (P17)
-- The beta's Heads (beta port S2): M.HEADS without the keep.write group (no lab_keep there; the proofs come from
-- LAB.seed). Literal tables, as test_lab_stage1's guard-name scan reads them
M.HEADS_BETA = { { 'lab.inherit.hide', why = 'l0i_nogo' }, { 'cap.parent', why = 'cap_attach', refused = true },
    { 'cap.mesh', 'cap.meat', why = 'no_cap', refused = true } }
M.PIECES = { { 'piece.spawn', why = 'no_piece' }, { 'piece.mesh', why = 'no_piece' }, { 'piece.pose', why = 'no_piece' },
    { 'piece.isolate', why = 'no_piece' }, { 'piece.phys', why = 'no_piece' } }
-- The commit's route names: a name the sentinel disabled after a crash keeps Heads off (architecture.md: readiness
-- depends on every sentinel of the feature)
M.COMMIT = { 'lab.cut.stage', 'lab.cut.head', 'hide.bone' }
M.REFUSED = { cap_attach = true, no_cap = true }
-- A class whose ladder prerequisite failed for good fails with it (section 3.5): a failed P3 leaves the meat route only
-- and a failed P4 makes every Cap meat, so the nub (P7) is out and P8 alone decides ('no_cap' when it fails too). The
-- ladder never runs P7 after them, so without this the group would read pending for the whole session
M.NEEDS = { ['cap.mesh'] = { 'cap.pmc', 'lab.tarray.probe' } }
-- The beta's sig pass (BD9; beta port S3 'the names the route uses'), so every answer is in before a kill frame asks:
-- the readiness groups (M.HEADS_BETA, M.HEADS_GC, M.PIECES), the seeded Cap and Piece names the stage builds under,
-- the commit names (M.COMMIT, the limb commit), lab_hold's read-back, and the BD0 names that run in a cut or right
-- after it (lab_cap's test section, lab_fade's dissolve, lab_gib). Not: the ladder and lab-key names (time, keep.write,
-- the mob group, cap.keep, GCAP-a, lab.spawn.* outside the test build, lab.skin.*), the CVar reads the beta skips,
-- mod-off's names, and the warm-time probes of lab_look and lab_census, which ask at their first use
M.SIGS_BETA = { 'lab.inherit.hide', 'cap.pmc', 'lab.tarray.probe', 'cap.mid', 'cap.parent', 'cap.mesh', 'cap.meat',
    'cap.destroy', 'hide.optim', 'piece.spawn', 'piece.mesh', 'piece.pose', 'piece.isolate', 'piece.phys',
    'piece.destroy', 'hide.comp', 'hide.tag', 'hide.bone', 'lab.cut.stage', 'lab.cut.head', 'lab.cut.limb',
    'lab.read.bonehidden', 'cap.look.section', 'lab.read.dissolve', 'gib.load', 'gib.spawn', 'gib.mesh', 'gib.phys',
    'gib.fx', 'gib.destroy', 'extra.fall', 'hair.keep', 'corpse.keep', 'corpse.seen', 'corpse.vanish',
    'corpse.destroy', 'cap.stub', 'cap.ring' }                                  -- lab_corpse asks LAB.sig before each kind (TC-BETA-01c: none answered)
-- The author's test build (META.beta_spawn: main.lua loads lab_spawn after the beta set when its file is there): the
-- spawn press's names join the beta's pass while lab_spawn runs, so a press finds their answers in
M.SIGS_SPAWN = { 'lab.spawn.load', 'lab.spawn.hold', 'lab.spawn.deferred', 'lab.spawn.summon', 'lab.spawn.move',
    'lab.spawn.ai', 'lab.spawn.respawn' }

-- ---------- env calls (D30): a class whose ids session_pbz lists in calls_missing ----------
-- session_pbz's env record: calls_missing is a sorted list of the missing paths (the key itself when a calls entry
-- holds no path string); nil until env is written. The set per class is built once when env first reads
local function env_of()
    local fn = cfg and cfg.env or SP.env
    local ok, e = pcall(fn)
    return ok and type(e) == 'table' and e or nil
end
local function class_ids(name)
    local ids = data('data.lab_classes')[name]
    return type(ids) == 'table' and ids or {}
end
local function load_env()
    local e = env_of()
    if not e then return false end
    local set, calls = {}, data('data.hooks').calls
    calls = type(calls) == 'table' and calls or {}
    local list = type(e.calls_missing) == 'table' and e.calls_missing or nil
    for _, p in ipairs(list or {}) do set[tostring(p)] = true end
    st.miss = {}
    for name in pairs(data('data.lab_classes')) do
        local m = list == nil                           -- an env without the list: no class reads present
        for _, id in ipairs(class_ids(name)) do
            local path = calls[id]
            if type(path) ~= 'string' or set[path] or set[tostring(id)] then m = true end
        end
        st.miss[name] = m
    end
    st.env, st.dirty = true, true
    return true
end

-- ---------- one class: 'ok', or 'fail' and its word, or 'pending' ----------
-- Definite failures first (a disabled name, a missing call, a failed sig, a failed proof), then the pending ones
local function class_state(name, why)
    if SENT.is_disabled(name) then return 'fail', 'disabled' end
    if st.env and st.miss[name] then return 'fail', 'calls_missing' end
    local sg = st.sig[name]
    if sg ~= nil and sg ~= 'ok' then return 'fail', sg end
    local pr = LAB.proof(name)
    if pr == false then return 'fail', why end
    for _, n in ipairs(M.NEEDS[name] or {}) do if LAB.proof(n) == false then return 'fail', why end end
    if pr == nil or not st.env or sg == nil then return 'pending', 'proof_pending' end
    return 'ok'
end
-- A group: ok when any alternative is ok; fail when every one failed (the first one's word); else pending
local function group_state(g)
    local first_fail, pend = nil, false
    for _, name in ipairs(g) do
        local s, w = class_state(name, g.why)
        if s == 'ok' then return 'ok' end
        if s == 'pending' then pend = true elseif first_fail == nil then first_fail = w end
    end
    if pend then return 'pending', 'proof_pending' end
    return 'fail', first_fail, g.refused and M.REFUSED[first_fail] == true
end
-- ok, why, refused over the route's groups: the first failure wins over every pending group
local function route_state(groups, extra)
    local pend = false
    for _, list in ipairs({ groups, extra or {} }) do
        for _, g in ipairs(list) do
            local s, w, refused = group_state(g)
            if s == 'fail' then return false, w, refused == true or nil end
            if s == 'pending' then pend = true end
        end
    end
    if pend then return false, 'proof_pending' end
    return true
end
local function armed_why()
    if not LAB.inherit_ok() then return 'stopped' end
    if not LAB.l0i_ok() then return 'no_l0i' end
    return nil
end
-- Heads ready for a pair (section 3.5, D30): L0i-lite ok, no stop, every class on the route proven with its calls
-- present and its sig ok, and no commit name disabled. ready, why (nil when ready), refused (the why ends refused)
function M.ready(pair)
    if not st.init then return false, 'inert' end
    local w = armed_why()
    if w then return false, w end
    if LAB.pinned() == false then return false, 'unpinned' end     -- the beta on another build: no seeded proof
    for _, name in ipairs(M.COMMIT) do if SENT.is_disabled(name) then return false, 'disabled' end end
    return route_state(LAB.beta() and M.HEADS_BETA or M.HEADS, pair == 'GuiChai' and M.HEADS_GC or nil)
end
-- The proven pair whose readiness a data/cut_classes.lua row takes (BD9), nil for an unknown layout: GuiChai's (P17
-- hide.comp too) for a meshhead layout and for a body row that hides a component (hair, a hat or mask, a glow), else
-- MaleThug's
function M.base(row)
    if type(row) ~= 'table' then return nil end
    local base = M.BASE[row.layout]
    if base ~= 'MaleThug' then return base end
    for _, k in ipairs({ 'head', 'hair', 'hat_mask', 'glow' }) do
        if type(row[k]) == 'table' and row[k][1] ~= nil then return 'GuiChai' end
    end
    return base
end
-- Pieces ready (P11-P15 likewise); the same classes for both pairs
function M.pieces(pair)
    if not st.init then return false, 'inert' end
    local w = armed_why()
    if w then return false, w end
    if LAB.pinned() == false then return false, 'unpinned' end
    return route_state(M.PIECES)
end

-- ---------- sig checks (D17): every class of data/lab_classes.lua, once env is written ----------
-- LAB.sig(name) checks at most one new path a frame over every caller (each path under its own
-- LAB.armed('probe.meta'), spec A3.2) and keeps a path once it answered, so a class whose paths earlier classes
-- covered costs no guarded call. Per frame: every class that adds no new path, then at most one class that does (the
-- one adding the fewest; ties in name order), and that frame is one-shot (LAB.oneshot: its arm writes stay out of the
-- frame gauges). 'sig_pending' (a path still unchecked once the frame's path is paid, here or by a module's first use)
-- asks again next frame. A guard that refused or raised (a disabled 'probe.meta', a failed arm write) is not kept by
-- LAB.sig: the class is asked again SIG_RETRY_S later.
local function class_paths(name)
    local calls, out, seen = data('data.hooks').calls, {}, {}
    calls = type(calls) == 'table' and calls or {}
    for _, id in ipairs(class_ids(name)) do
        local p = calls[id]
        if type(p) == 'string' and not seen[p] then seen[p], out[#out + 1] = true, p end
    end
    return out
end
local function fresh_paths(name)
    local n = 0
    for _, p in ipairs(class_paths(name)) do if not st.covered[p] then n = n + 1 end end
    return n
end
-- lab_spawn up in this session: the beta test build (the player zip has no lab_spawn.lua, so never there)
local function spawn_on()
    local SP = package.loaded['lab_spawn']
    if type(SP) ~= 'table' or type(SP.status) ~= 'function' then return false end
    local ok, s = pcall(SP.status)
    return ok and type(s) == 'table' and s.alive == true
end
-- lab_slice_route (META.beta_slicer) or lab_slice_probe (the beta test build) up in this session
local function slicer_on()
    for _, name in ipairs({ 'lab_slice_route', 'lab_slice_probe' }) do
        local SP = package.loaded[name]
        if type(SP) == 'table' and type(SP.status) == 'function' then
            local ok, s = pcall(SP.status)
            if ok and type(s) == 'table' and s.init == true then return true end
        end
    end
    return false
end
-- The game's slicer (docs/research/slicer-stumps.md): lab_slice's names (SL.NAMES) with a data/lab_classes.lua row join
-- the pass while slicer_on(), so a slice finds their answers in (an ask that finds none waits a frame on
-- 'sig_pending'); slicer.blood has none (lab_blood runs it as LAB.hot)
local function slicer_names()
    local SLC, rows, out = package.loaded['lab_slice'], data('data.lab_classes'), {}
    local names = type(SLC) == 'table' and type(SLC.NAMES) == 'table' and SLC.NAMES or {}
    for _, name in ipairs(names) do if rows[name] ~= nil then out[#out + 1] = name end end
    return out
end
function M.classes()                            -- every class name of data/lab_classes.lua (the beta's), sorted
    local out = {}
    if LAB.beta() then
        for _, name in ipairs(M.SIGS_BETA) do out[#out + 1] = name end
        if spawn_on() then for _, name in ipairs(M.SIGS_SPAWN) do out[#out + 1] = name end end
        if slicer_on() then for _, name in ipairs(slicer_names()) do out[#out + 1] = name end end
    else
        for name in pairs(data('data.lab_classes')) do out[#out + 1] = name end
    end
    table.sort(out)
    return out
end
local function sig_step(t)
    if st.sig_left == nil then st.sig_left = M.classes() end
    local paid = false
    while st.sig_left[1] do
        local best, bn, bi = nil, nil, nil
        for i, name in ipairs(st.sig_left) do
            if (st.sig_at[name] or 0) <= t then
                local n = name == st.sig_cur and 1 or fresh_paths(name)    -- a pending class goes on first
                if bn == nil or n < bn then best, bn, bi = name, n, i end
            end
        end
        if best == nil or (bn > 0 and paid) then return end
        table.remove(st.sig_left, bi)
        if bn > 0 then
            paid = true
            LAB.oneshot()
        end
        local okc, ok, why = pcall(LAB.sig, best)
        if best == st.sig_cur then st.sig_cur = nil end
        if okc and (ok == true or why == 'sig_mismatch' or why == 'sig_unknown') then
            st.sig[best] = ok == true and 'ok' or why
            for _, p in ipairs(class_paths(best)) do st.covered[p] = true end
            st.dirty = true
        elseif okc and why == 'sig_pending' then      -- this frame's path is paid: the class goes on next frame
            table.insert(st.sig_left, 1, best)
            st.sig_cur = best
            return
        else
            st.sig_at[best] = t + M.SIG_RETRY_S
            st.sig_left[#st.sig_left + 1] = best
        end
    end
end

-- ---------- the row plan (section 3.6, D7): at the tick after lab_death, first match wins ----------
local function off() return not MODOFF.enabled('lab_plan') end     -- mod-off, or the vanilla compare (gameplay)
local function not_armed()      -- the stop, L0i-lite, a failed P1 (L0i NO-GO): the why, or nil when armed
    local w = armed_why()
    if w == nil and LAB.proof('lab.inherit.hide') == false then w = 'l0i_nogo' end
    return w
end
local function cut_on()         -- the mod setting effects.cut (core/config.lua); a config that raises reads off
    local ok, on = pcall(C.effect, 'cut')
    return ok and on == true
end
-- The knob cut_chance (spec fixes-0.2.2 D5): true when this kill's roll lost. One draw per kill id from its own
-- generator (core/rng.lua, never the math library's), so the same id gets the same verdict on every boot; 100 draws
-- nothing (today), and a config that raises or answers no number reads 100. Never the preset key 'chance'
local function chance_lost(id)
    local ok, pct = pcall(C.knob, 'cut_chance')
    if not ok or type(pct) ~= 'number' or pct >= 100 then return false end
    return not RNG.new(RNG.seed_from('cut_chance', tostring(id))):chance(pct / 100)
end
-- A beta Heads row's payload (the BD0 contract): a shallow copy of d with pair = the row's layout and class_row = the
-- row; a kill that is not the player's carries a copy of its kill with tier 'normal' (one part: the author's answer 5)
local function heads_copy(d, row)
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    out.pair, out.class_row = row.layout, row
    local kill = type(d.kill) == 'table' and d.kill or {}
    if kill.by_player ~= true and kill.tier ~= 'normal' then
        local k2 = {}
        for k, v in pairs(kill) do k2[k] = v end
        k2.tier, k2.tier_src = 'normal', 'none'
        out.kill = k2
    end
    return out
end
-- A key the game's slicer cut (lab_slice: at least one half was found on it): no cut row ever, a revive's death
-- included (lab_cut's leader walk would hide a bone on the halves)
local function sliced(key)
    local SLC = package.loaded['lab_slice']
    return type(SLC) == 'table' and type(SLC.sliced) == 'function' and SLC.sliced(key) == true
end
-- The beta's row (header 'The beta's rows'): row, outcome, why, label (the layout, 'other' before a row is found) and
-- the Heads payload
local function decide_beta(d)
    local class = type(d.class) == 'string' and d.class or ''
    local kill = type(d.kill) == 'table' and d.kill or {}
    if class:find('Player', 1, true) then return 'not_cut_class', 'lab_skip', 'player', 'other' end
    if data('data.no_blood')[class] ~= nil then return 'not_cut_class', 'lab_skip', 'no_blood', 'other' end
    local classes = data('data.cut_classes').classes
    if type(classes) ~= 'table' then return 'not_cut_class', 'lab_skip', 'no_table', 'other' end
    local row = classes[class]
    if type(row) ~= 'table' then return 'not_cut_class', 'lab_skip', 'not_listed', 'other' end
    local label = row.layout
    if M.base(row) == nil or type((data('data.lab_pairs').pair or {})[label]) ~= 'table' then
        return 'not_cut_class', 'lab_skip', 'bad_row', 'other'
    end
    if off() then return 'off', 'refused', 'modoff', label end
    if sliced(d.key) then return 'sliced', 'lab_skip', 'sliced', label end
    if kill.execution == true and not (kill.execution_src == 'bullet' and C.knob('finisher_cuts') == true) then
        return 'exec', 'lab_skip', 'execution', label
    end
    -- the test build's slicer probe holds the next spawned target death uncut (Lua only: no native call in this frame)
    local SP = package.loaded['lab_slice_probe']
    if type(SP) == 'table' and type(SP.claim) == 'function' and SP.claim(d) == true then
        return 'slicer_hold', 'lab_skip', 'slicer_probe', label
    end
    if M.NO_CUT_BLOW[kill.attack_kind] then return 'no_cut_blow', 'lab_skip', kill.attack_kind, label end
    if kill.bleed_only == true then return 'bleed_only', 'lab_skip', 'bleed_only', label end
    if not cut_on() then return 'cut_off', 'lab_skip', 'effects_cut', label end
    local w = not_armed()
    if w then return 'not_armed', 'lab_skip', w, label end
    local ok, why, refused = M.ready(M.base(row))    -- no slot (review round 1): lab_cut's limbq, p1q, compq stay empty
    if not ok then return 'not_ready', refused and 'refused' or 'lab_skip', why or 'proof_pending', label end
    if chance_lost(d.id) then return 'cut_chance', 'lab_skip', 'chance', label end     -- D5: no Heads, no slice
    local payload = heads_copy(d, row)
    -- the game's own slicer where it can take the death (Lua only); it hands the death back as 'heads' when it cannot
    local RT = package.loaded['lab_slice_route']
    if type(RT) == 'table' and type(RT.wants) == 'function' then
        local okw, want = pcall(RT.wants, payload, row)
        if okw and want == true then return 'slice', nil, nil, label, payload end
    end
    return 'heads', nil, nil, label, payload
end
-- row, outcome, why, label (and the beta's Heads payload) for one lab_death payload; no outcome for a cut row (heads:
-- lab_cut sends it). Slots: CTRL_N controls, then KEEP_N kept-only of which the last one waits for a GuiChai while
-- none was kept
local function decide(d)
    if LAB.beta() then return decide_beta(d) end
    local pair = (d.pair == 'MaleThug' or d.pair == 'GuiChai') and d.pair or 'other'
    if pair == 'other' then return 'other', 'lab_skip', 'other', pair end
    if off() then return 'off', 'refused', 'modoff', pair end
    if type(d.kill) == 'table' and d.kill.execution == true then return 'exec', 'lab_skip', 'execution', pair end
    local w = not_armed()
    if w then return 'not_armed', 'lab_skip', w, pair end
    local rv = LAB.reserved(d.key)
    if rv == 'ctrl' or (rv == nil and st.ctrl < M.CTRL_N) then      -- a reserved control; else today's rule
        st.ctrl = st.ctrl + 1
        return 'keep_ctrl', 'lab_skip', 'keep_ctrl', pair
    end
    if st.keep < M.KEEP_N and (pair == 'GuiChai' or st.keep_gc > 0 or st.keep < M.KEEP_N - 1) then
        st.keep = st.keep + 1
        if pair == 'GuiChai' then st.keep_gc = st.keep_gc + 1 end
        return 'keep_only', 'lab_skip', 'keep_only', pair
    end
    local ok, why, refused = M.ready(pair)
    if ok then return 'heads', nil, nil, pair end
    return 'keep_only', refused and 'refused' or 'lab_skip', why or 'proof_pending', pair
end
-- The plan record's rows: heads per pair (per layout in the beta), the beta's skip rows; exec, off, not_armed and
-- other under 'other'
local BETA_ROW = {}
for _, k in ipairs(M.BETA_ROWS) do BETA_ROW[k] = true end
local function row_key(row, pair)
    if row == 'heads' then return 'heads_' .. pair end
    if row == 'keep_ctrl' or row == 'keep_only' then return row end
    if BETA_ROW[row] and LAB.beta() then return row end
    return 'other'
end
local function remember(id, row)
    if st.ids[id] == nil then
        st.id_order[#st.id_order + 1] = id
        st.nids = st.nids + 1
        if st.nids > M.IDS then
            st.ids[table.remove(st.id_order, 1)] = nil
            st.nids = st.nids - 1
        end
    end
    st.ids[id] = row
end
-- One death: kills_off for any death while off (section 3.2), the row, bus lab_row, and lab_outcome for a no-cut row
local function assign(d)
    if off() then
        st.kills_off = st.kills_off + 1
        LAB.count('kills_off')
    end
    local row, outcome, why, pair, heads = decide(d)
    remember(d.id, row)
    local k = row_key(row, pair)
    st.rows[k] = (st.rows[k] or 0) + 1
    if LAB.beta() then
        LAB.rec('kill_row', { id = d.id, class = d.class, row = row, outcome = outcome, why = why, layout = pair })
    end
    BUS.emit('lab_row', row, heads or d)
    if outcome then BUS.emit('lab_outcome', d.id, { row = row, outcome = outcome, why = why }) end
end
function M.row_of(id) return st.ids[id] end
-- A death lab_plan gave one row and another module handed on (lab_slice_route: a 'slice' that could not slice goes
-- 'heads'): the row it now has, and the plan record's tallies moved with it. true when the id was known
function M.reroute(id, row, pair)
    if not st.init or id == nil or st.ids[id] == nil or type(row) ~= 'string' then return false end
    local old = st.ids[id]
    st.ids[id] = row
    local ko, kn = row_key(old, pair), row_key(row, pair)
    st.rows[ko] = math.max(0, (st.rows[ko] or 1) - 1)
    st.rows[kn] = (st.rows[kn] or 0) + 1
    return true
end

-- ---------- the quiet moment (section 3.6: Limbs, S-SKIN) and the consent (META.lab_consent) ----------
function M.quiet()
    if not st.init or LAB.ended() or LAB.paused() or off() then return false end
    local t = now()
    if st.last_death ~= nil and t - st.last_death < M.QUIET_DEATH_S then return false end
    if st.last_hit ~= nil and t - st.last_hit < M.QUIET_HIT_S then return false end
    return true
end
-- consent(key) -> true only for an explicit true; consent() -> a copy { respawn = bool, ... } (no answer is no)
function M.consent(key)
    local c = cfg and cfg.consent or {}
    if key ~= nil then return c[key] == true end
    local out = { respawn = c.respawn == true }
    for k, v in pairs(c) do out[k] = v == true end
    return out
end

-- ---------- the plan record (section 3.1): each readiness change, each lab_flush, lab_end; lab_status ----------
local function plan_rec(reason)
    local r = { reason = reason, ready = {}, piece = {}, why = {}, proofs = {}, sigs = {}, rows = {},
        l0i_ok = LAB.l0i_ok(), dev_set = cfg.dev_set, consent = M.consent(), env = st.env and 'ok' or 'pending' }
    local keys = LAB.beta() and M.BETA_ROWS or { 'keep_ctrl', 'keep_only', 'heads_MaleThug', 'heads_GuiChai', 'other' }
    for _, k in ipairs(keys) do r.rows[k] = st.rows[k] or 0 end
    for _, p in ipairs(M.PAIRS) do
        local h, w = M.ready(p)
        r.ready[p], r.piece[p] = h, (M.pieces(p))
        if not h then r.why[p] = w end
    end
    if next(r.why) == nil then r.why = nil end
    for _, s in ipairs(M.LADDER) do
        local v = LAB.proof(s[2])
        r.proofs[s[2]] = v == true and 'ok' or v == false and 'fail' or 'pending'
    end
    for _, n in ipairs(M.classes()) do r.sigs[n] = st.sig[n] or 'pending' end
    return r
end
local function write_plan(reason) LAB.rec('plan', plan_rec(reason), true) end
local function ready_key()
    local parts = {}
    for _, p in ipairs(M.PAIRS) do parts[#parts + 1] = tostring((M.ready(p))) .. '/' .. tostring((M.pieces(p))) end
    return table.concat(parts, ',')
end

-- ---------- the ticker (every frame, paused too: memory and records only) ----------
-- new_while_off from the listeners; env until it reads; the deaths queued in an earlier frame (the tick after
-- lab_death, whatever the ticker order); the sig step; readiness changes; the flushes; lab_end
local function tick()
    local t = now()
    if st.off_n > 0 then
        LAB.count('new_while_off', st.off_n)
        st.off_n = 0
    end
    if not st.env then load_env() end
    if st.q[1] then
        local q, keep = st.q, {}
        st.q = {}
        for _, e in ipairs(q) do
            if e.f >= S.frame then keep[#keep + 1] = e
            elseif LAB.ended() then st.after_end = st.after_end + 1       -- lab_poll wrote it refused 'lab_end'
            else assign(e.d) end
        end
        for _, e in ipairs(st.q) do keep[#keep + 1] = e end                -- emitted while assigning
        st.q = keep
    end
    if st.env and not st.ended then sig_step(t) end
    local l0i, inh = LAB.l0i_ok(), LAB.inherit_ok()
    if l0i ~= st.l0i or inh ~= st.inherit then st.l0i, st.inherit, st.dirty = l0i, inh, true end
    if st.dirty then
        st.dirty = false
        local key = ready_key()
        if key ~= st.last_key then
            st.last_key = key
            write_plan('ready')
        end
    end
    if st.flushq[1] then
        st.flushq = {}
        write_plan('lab_flush')
    end
    if st.end_due then
        st.end_due, st.ended = false, true
        write_plan('lab_end')
    end
end

-- ---------- bus listeners (they only queue or note a time) ----------
local function on_death(d)
    if type(d) ~= 'table' or d.id == nil then return end
    st.last_death = now()
    if #st.q >= M.INBOX then
        st.qdrop = st.qdrop + 1
        return
    end
    st.q[#st.q + 1] = { d = d, f = S.frame }
end
local function while_off() if off() then st.off_n = st.off_n + 1 end end
-- A pawn the lab admitted (lab_poll): reserved when it is of a lab pair and the lab is armed with the mod on; the first
-- call of a key decides (LAB.reserve), so the order against lab_keep's listener does not matter
local function on_admit(rec, class, via)
    if type(rec) ~= 'table' or rec.key == nil then return end
    local pair = LAB.pair_of(class or rec.class)
    if pair ~= 'MaleThug' and pair ~= 'GuiChai' then return end
    LAB.reserve(rec.key, not off() and armed_why() == nil, via)
end
local EVENTS = { 'lab_death', 'lab_hit', 'lab_proof', 'lab_cut_live', 'lab_flush', 'lab_end', 'lab_stop', 'lab_admit' }

-- ---------- lifecycle ----------
local function config(meta, opts)
    meta = type(meta) == 'table' and meta or META
    return { dev_set = type(meta.dev_set) == 'string' and meta.dev_set or 'unread',
        consent = type(meta.lab_consent) == 'table' and meta.lab_consent or {},
        env = type(opts) == 'table' and type(opts.env) == 'function' and opts.env or nil }
end
-- A: the main.lua feature view (clock, meta; LAB holds count, oneshot and the records). Inert outside the lab02 set
function M.init(adapter, opts)
    A = adapter
    st = new_state()
    cfg = config(adapter and adapter.meta, opts)
    if not LAB.cut_set() then return true end
    st.init = true
    LAB.names(N, F)
    MODOFF.feature('lab_plan', { gameplay = true })      -- the vanilla compare blocks it, as mod-off does
    LAB.count('new_while_off', 0)
    LAB.count('kills_off', 0)
    BUS.on('lab_death', 'lab_plan', on_death)
    BUS.on('lab_admit', 'lab_plan', on_admit)
    BUS.on('lab_hit', 'lab_plan', function() st.last_hit = now() end)
    BUS.on('lab_proof', 'lab_plan', function()
        st.dirty = true
        while_off()
    end)
    BUS.on('lab_cut_live', 'lab_plan', while_off)
    BUS.on('lab_flush', 'lab_plan', function(reason)
        if reason ~= 'lab_end' then st.flushq[#st.flushq + 1] = reason or 'periodic' end   -- lab_end writes its own
    end)
    BUS.on('lab_end', 'lab_plan', function() st.end_due = true end)
    BUS.on('lab_stop', 'lab_plan', function() st.dirty = true end)
    S.ticker('lab_plan', tick)
    DEV.command('lab_status', function() return plan_rec('lab_status') end)   -- read-only: no world spec (D19)
    st.last_key = ready_key()
    write_plan('init')
    return true
end
-- A map load: the deaths queued on the old map go (lab_poll wrote their kills 'stale'); slots, rows, sigs and the env
-- stay for the session
function M.reset(reason)
    st.qdrop = st.qdrop + #st.q
    st.q = {}
end
function M.status()
    local n = 0
    for _ in pairs(st.sig) do n = n + 1 end
    return { init = st.init, ctrl = st.ctrl, keep = st.keep, keep_gc = st.keep_gc, queued = #st.q, qdrop = st.qdrop,
        after_end = st.after_end, kills_off = st.kills_off, env = st.env, sigs = n,
        sig_left = st.sig_left and #st.sig_left or nil, ended = st.ended }
end
function M.shutdown()
    S.remove_ticker('lab_plan')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_plan') end
    st, A = new_state(), nil
end

return M
