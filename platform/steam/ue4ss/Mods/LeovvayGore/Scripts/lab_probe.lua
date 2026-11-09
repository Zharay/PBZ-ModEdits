-- status: new in M0 S2.9 (offline only; TC-LAB-01 stage 0 decides) origin: kb:runtime-safety-perf#crash-sentinel-first-success-guard-linger-strikes-quit-hints-e-sentinel-e-risky-e-linger
-- lab_probe.lua: the lab core of the probe and dev builds (spec M0 section 3.5, D5, D8, D9, D12, D30). main.lua loads it
-- first of META.lab_modules (release requires it only as the first of the player beta's META.beta_modules, LAB.beta());
-- the other lab modules require it and use this API and the bus.
-- * Records: LAB.rec(ev, fields) writes at info with a per-event cap (CAP 200; CAPS.hook_fire 300); a record over its
--   cap is not written and counts in counters.records_capped.
-- * Guards (section 3.4). LAB.armed(name, fn, ...): fn under SENT.sentinel on EVERY call (always-arm: 2 writes per call;
--   a first-call-only sentinel leaves later crashes unattributed, refuted.md:116); after the name's first success
--   ARM.mark(name, '<LAB.CARD>@<loader sha>') once, so TC-LAB-02's dev build finds it armed on this build key.
--   LAB.hot(name, fn, ...): the 10 Hz form (the GAS reads): always-armed until one read returns a value, then
--   SENT.linger(name, HOT_LINGER_S) before every later read, so armed.json names it during each read (one write per
--   burst). No lab name is ever ARM.gate'd: the lab run is what arms them. Callers pass names listed in META.lab_risky.
--   A 'lab.inherit.*' call through LAB.armed (or an unproven LAB.hot) that ran also lingers INHERIT_LINGER_S after it
--   returns (SENT.linger: one write per burst), so a delayed native fault after it strikes that name (D9).
-- * Stop rule (D9): the first 'ArrayNum exceeds ArrayMax' in the error text of a LAB.armed or LAB.hot call (source
--   'pcall'), in an error a ue.lua read helper caught and answered nil for (ue.on_error; source 'swallowed', checked
--   after each guarded call and on every lab tick, so a session_pbz or main.lua read counts too), the first such line
--   in the UE4SS.log tail (ENV.log_scan every SCAN_S on the lab ticker, never in the beta; source 'log_unclear':
--   another mod such as UltraPlusExtensions can write it, so never an L0i NO-GO, HR-FIX-ONLY-MOD), or at this start a
--   name that was in flight or a struck or linger-tripped 'lab.inherit.*' name (MAIN.tripped, MAIN.struck; source
--   'start') sets inherit_off for the session: one stop record (kind 'stop'), bus lab_stop(why) on the next lab tick,
--   and every 'lab.inherit.*' call through LAB.armed or LAB.hot is refused with 'inherit_off', never run (each refusal
--   counts in counters.inherited_after_trip). Other names and the hooks keep running. The log tail stops once the stop
--   fired. A start strike or linger trip of another name (lab.read.gas lingers through play; PBZ has no quit hint, D30)
--   only writes a stop record kind 'strike' (review RUNTIME-4). An inherited name is struck at start when the process
--   ended inside its linger: a delayed fault, or a quit within INHERIT_LINGER_S of the call (the price of D9).
-- * LAB.l0i_ok() (the shared contract of fix round 2): true once lab_l0i reported L0i-lite returned 2 of 2
--   (LAB.set_l0i_ok), false before, after a stop and once an ArrayNum text was swallowed (the stop is due). No IO: a
--   hook body may ask it.
-- * Hooks never write records: a consumer copies plain values (LAB.snap_push) and queues work with LAB.post(fn); the lab
--   ticker runs it on the next frame (a map load drops what an older map queued).
-- * Frame gauges (section 3.2): the lab ticker reads MAIN.frame_cost() (the last finished on_frame: main's work, every
--   ticker, the lab reads) once per frame; LAB.oneshot() (MAIN.oneshot) frames go to probe_oneshot_ms_max, the others
--   to probe_frame_ms_p95 and probe_frame_ms_max, each over the last WINDOW_S (the status period). Reads never clear.
--   Paused frames are not sampled (LAB.paused: the poll and the observation reads do not run there).
--   A log tail read of more than SCAN_BIG bytes (the catch-up over the session head) marks its frame one-shot too.
-- * lab_flush(reason) on the bus every FLUSH_S (real time, also while paused: no quit hint exists on PBZ, D30, and a
--   quit from the pause menu must find fresh tallies), at each map load (reset 'map', before the other lab modules
--   reset) and once after lab_end. Listeners write their tallies from memory.
-- * Pause: LAB.paused() is the scheduler's flag (main.lua reads ue.paused() every 15 frames); LAB.due(key, s) is the
--   periodic gate lab modules put in front of their engine reads: false while paused.
-- * Victims (D31, C8): LAB.victim(obj or ue.keep record) -> the registry record keyed by address, full name and epoch,
--   with life (LAB.next_life steps it at a confirmed death; id = key#life); LAB.live(rec) is ue.live (nil and 'gone',
--   'reused' or 'stale'). The index clears at a map load. LAB.pair_of is a measurement label, never a gore decision.
--   LAB.alive(rec) (M1a 4.1 item 2: gone is destroyed): the actor of a keep record while it is live and not being
--   destroyed, else nil and why ('destroyed': Actor.bActorIsBeingDestroyed reads true; 'collected': ue.live's 'gone',
--   the garbage collector ran; 'reused', 'stale', 'none' as LAB.live). UE4SS's IsValid stays true until the GC runs (about
--   every 61 s), so every module that decides a corpse or a host is gone asks this and never LAB.live alone.
--   LAB.destroying(actor): true | false | nil (the flag read no boolean); actors only.
--   LAB.reserve(key, ok) and LAB.reserved(key): the admission ledger (M1a 4.1 item 1, above its code): 'ctrl' for the
--   first CTRL_N admitted lab-pair pawns of the session, 'armed' for every later one, with its ordinal.
--   LAB.host_state(actor, d[, f]) -> f with host_age_s and host_destroying (the proof fields of a ladder step on a
--   corpse, M1a 4.1 item 3); LAB.host_skip(owner, step, d, why): the 'ladder_skip' record and counter of a step skipped
--   because its host is dead.
-- * Snapshots: LAB.snap_push(key, snap) keeps the last SNAPS per registry key; LAB.snaps(key, since_t) reads one ring;
--   LAB.recent(since_t) lists the registry records whose newest snapshot is at or after since_t (lab_obs BL1).
-- * M1a (spec M1a A1.2, D4, D17, D20, section 3.9), read once at init from the view's meta (MAIN.meta), else meta.lua:
--   - LAB.inherited(name): a 'lab.inherit.*' name or one of META.lab_inherited. After a stop LAB.armed and LAB.hot
--     refuse every inherited name ('inherit_off'); the start rule stays the M0 D9 one ('lab.inherit.*' only), so a
--     start strike of a listed name writes a 'strike' record and sets nothing.
--   - Lingers: a call that ran through LAB.armed (or an unproven LAB.hot) lingers LAB.linger_s(name) after it returns:
--     META.lab_linger[name], at least INHERIT_LINGER_S for an inherited name, 0 (none) otherwise. A proven LAB.hot read
--     keeps its HOT_LINGER_S before each read, or META.lab_hot_linger[name] when listed (0: no linger, a bare pcall;
--     blood.wash, whose quit-time strikes would switch the Soul wash off). LAB.linger(names, s): SENT.linger_group,
--     one write.
--   - LAB.CARD: META.lab_card.probe ('TC-LAB-01') in the probe, else the dev set's card (META.dev_sets[META.dev_set]);
--     the ARM mark label is LAB.CARD .. '@' .. the loader sha. LAB.cut_set(): true when the dev profile's set loads
--     lab_plan (lab02), false in the probe and the spawn set. LAB.beta() (beta port S1): the release profile with
--     META.beta true; a cut set, LAB.CARD 'beta', no UE4SS.log tail scan.
--   - LAB.rec(ev, fields, force): force writes through a warn log level (mod-off lowers it, D14); the cap still counts.
--   - LAB.prove(step, name, ok, fields): one forced proof record { step, name, ok, ... } and bus lab_proof(name, ok);
--     LAB.proof(name): true, false or nil (not run), kept for the session.
--   - LAB.sig(name): the signature check of a call class (D17, below), kept for the session. LAB.refusal(name): the
--     guard tail lab modules share after their own words (disabled, inherit_off, the sig check).
--   - LAB.ended(): true after lab_end. In dev the tick that flushes for lab_end clears every lingering name in the
--     next frame (SENT.linger_clear, D20), after the end handlers of the lab modules armed their last calls, so a
--     menu quit after Ctrl+F11 strikes no name; the probe keeps its lingers.
-- API: rec count gauge armed hot names oneshot inherit_ok set_l0i_ok l0i_ok stop victim live next_life snap_push snaps
--   recent pair_of set_game_id game_id post paused due; M1a: inherited linger_s linger cut_set prove proof sig
--   refusal ended alive destroying host_state host_skip reserve reserved, LAB.CARD LAB.CTRL_N; beta seed pinned pin_state;
--   lifecycle init(A, opts) shutdown status reset.
-- What the mock cannot prove: native faults inside a guarded call, whether the ArrayNum check throws or only logs, the
-- real frame costs (os.clock steps 1 ms: the gauges are means of a quantized clock, D10).
local META = require('meta')
local LOG = require('core.log')
local SENT = require('core.sentinel')
local BUS = require('core.bus')
local S = require('core.sched')
local NAMES = require('core.names')
local C = require('core.config')                        -- the loader waiver knob (fixes-0.2.2 F4.1); no cycle
local ENV = require('adapter.env')
local ARM = require('adapter.arm')
local ue = require('adapter.ue')

local LAB = { CAP = 200, CAPS = { hook_fire = 300 }, ARRAYNUM = 'ArrayNum exceeds ArrayMax', HOT_LINGER_S = 1,
    INHERIT_LINGER_S = 2, SCAN_S = 0.5, SCAN_RETRY_S = 5, SCAN_BIG = 4096, FLUSH_S = 300, WINDOW_S = 30, SAMPLES = 8192, ONESHOTS = 256, SNAPS = 16,
    SNAP_KEYS = 256, POSTS = 256, VICTIMS = 1024, MARK_TRIES = 3, CARD = 'TC-LAB-01', CTRL_N = rawget(_G, 'GORE_LAB_CTRL_N') or 0, RESERVATIONS = 512 }
LAB.PIN_WAIT_S = 5                                       -- the beta's pin check waits at most this for a build key
-- CTRL_N 0 since run 7 (the author, 2026-10-31: «why the hell do we still need these control corpses»): the vanilla-control corpses
-- proved the keep levers in runs 3 and 4; every admitted pawn is armed now. The offline harness (tests/_setup.lua)
-- sets GORE_LAB_CTRL_N 5 so the scenarios written for TC-LAB-02's controls still run
local INHERIT = 'lab.inherit.'

local A = nil
local st = {}

local function ring(cap) return { n = 0, cap = cap, t = {}, v = {} } end
local function new_state()
    return { per_ev = {}, marked = {}, proven = {}, inherit_off = false, stop = nil, stop_emit = false, posts = {},
        l0i_ok = false, dropped = 0, stale = 0, reg = {}, nreg = 0, snaps = {}, nsnaps = 0, game_ids = {}, game_pair = {},
        log_off = 0, next_scan = 0, next_flush = 0, end_flush = false, flushes = 0, due = {}, last_f = nil,
        ord = ring(LAB.SAMPLES), one = ring(LAB.ONESHOTS), sw_n = 0, sw_first = nil, sw_last = nil,
        proofs = {}, sigs = {}, sig_paths = {}, sig_f = nil, ended = false, resv = {}, resv_order = {}, nctrl = 0, narm = 0 }
end
st = new_state()

local function now() return A and A.clock.real() or 0 end

-- ---------- the build's lab set (M1a D2, D4): the card label, the cut set, the inherited names, the lingers ----------
-- From the meta the adapter view carries (MAIN.meta), else meta.lua; read once at init. dev: the dev profile; cut: its
-- set loads lab_plan; inh: the META.lab_inherited set; linger: META.lab_linger
local cfg = { inh = {}, linger = {}, dev = false, cut = false, beta = false, pins = nil, seed = {} }
local function set_of(list)
    local out = {}
    for _, n in ipairs(type(list) == 'table' and list or {}) do out[n] = true end
    return out
end
-- The player beta (beta port S1): the release profile with META.beta true, main.lua's own condition for loading
-- META.beta_modules. It is a cut set (lab_plan and the cut modules init), its ARM marks read 'beta@<sha>', and the
-- UE4SS.log tail scan stays off (another mod's line could stop every inherited name there; the in-process ArrayNum
-- checks stay)
local function configure(meta)
    meta = type(meta) == 'table' and meta or {}
    local dev = meta.profile == 'dev'
    local beta = meta.profile == 'release' and meta.beta == true
    local sets = type(meta.dev_sets) == 'table' and meta.dev_sets or {}
    local set = dev and sets[meta.dev_set] or nil
    if type(set) ~= 'table' then set = nil end          -- an unknown set (main.lua: start_error, none loaded)
    local probe = type(meta.lab_card) == 'table' and meta.lab_card.probe or nil
    LAB.CARD = beta and 'beta' or set and type(set.card) == 'string' and set.card or probe or 'TC-LAB-01'
    cfg = { inh = set_of(meta.lab_inherited), linger = type(meta.lab_linger) == 'table' and meta.lab_linger or {},
        hot = type(meta.lab_hot_linger) == 'table' and meta.lab_hot_linger or {},
        dev = dev, beta = beta, cut = beta or (set ~= nil and set_of(set.modules).lab_plan == true),
        pins = beta and type(meta.beta_pins) == 'table' and meta.beta_pins or nil,
        loaders = beta and type(meta.beta_loaders) == 'table' and meta.beta_loaders or nil,
        seed = beta and type(meta.beta_seed) == 'table' and meta.beta_seed or {} }
end
function LAB.cut_set() return cfg.cut == true end
function LAB.beta() return cfg.beta == true end

-- ---------- records, counters, gauges ----------
function LAB.count(k, n) if A and A.count then A.count(k, n) end end
function LAB.gauge(name, fn) if A and A.gauge then A.gauge(name, fn) end end
-- force: written below the log level too (mod-off lowers it to warn, D14); a record over its cap is never written
function LAB.rec(ev, fields, force)
    local n = (st.per_ev[ev] or 0) + 1
    st.per_ev[ev] = n
    if n > (LAB.CAPS[ev] or LAB.CAP) then
        LAB.count('records_capped')
        return false
    end
    if force then LOG.write('info', ev, fields, true) else LOG.info(ev, fields) end
    return true
end
function LAB.names(N, F) NAMES.register(N, F) end
function LAB.oneshot() if A and A.oneshot then A.oneshot() end end

-- ---------- the stop rule (D9) ----------
local function text200(s)
    s = tostring(s)
    return #s > 200 and s:sub(1, 200) or s
end
function LAB.inherit_ok() return not st.inherit_off end
-- L0i-lite proven (header): lab_l0i calls LAB.set_l0i_ok(true) when L0i-lite returned 2 of 2. LAB.l0i_ok() reads it
-- with no IO and no engine touch; st.sw_n > 0 means a swallowed ArrayNum text whose stop the next tick writes
function LAB.set_l0i_ok(v) st.l0i_ok = v == true end
function LAB.l0i_ok() return st.l0i_ok == true and not st.inherit_off and st.sw_n == 0 end
local function stop_rec(why, where, text, line, before, source, kind, at)
    local b = 'unread'
    if type(before) == 'table' then
        b = {}
        for i, x in ipairs(before) do b[i] = tostring(x) end
    end
    return { why = why or 'arraynum', source = source or 'pcall', where = where ~= nil and tostring(where) or 'unread',
        text = text ~= nil and text200(text) or 'unread', line = line ~= nil and tostring(line) or 'unread', before = b,
        kind = kind, at = at }
end
-- why 'arraynum' | 'sentinel'; where: the call name or the log position; text: the error or trip text; line and
-- before: the matched log line and the 3 lines before it ('unread' when none was read); source 'pcall' | 'swallowed'
-- | 'log_unclear' | 'start'; at (source 'swallowed' only): where ue.lua caught the text, 'ue.<helper>[:<key>]'. The
-- record has kind 'stop' (a start strike that sets nothing writes kind 'strike', LAB.init). Only the first stop
-- writes; later ones return false.
function LAB.stop(why, where, text, line, before, source, at)
    if st.inherit_off then return false end
    st.inherit_off = true
    st.stop = stop_rec(why, where, text, line, before, source, 'stop', at)
    st.stop_emit = true
    LAB.rec('stop', st.stop)
    return true
end
-- Swallowed ArrayNum texts (review PASSIVE-1). ue.lua's read helpers catch errors and answer nil; ue.on_error hands
-- every caught text to on_caught, which only counts an ArrayNum text and keeps the first and the last with where
-- ue.lua caught it (it may run inside a hook body: no IO, no record). swallowed() runs after a LAB.armed or LAB.hot fn
-- returns, before every guarded call (refused) and on every lab tick (a session_pbz or main.lua read is no LAB call):
-- LAB.stop('arraynum', where, text, nil, nil, 'swallowed', at), where the guarded name when the text came during that
-- call, else the at of the first text.
local function on_caught(text, helper, key)
    if type(text) ~= 'string' or not text:find(LAB.ARRAYNUM, 1, true) then return end
    st.sw_n = st.sw_n + 1
    st.sw_last = { text = text, at = 'ue.' .. tostring(helper) .. (key ~= nil and ':' .. tostring(key) or '') }
    if st.sw_first == nil then st.sw_first = st.sw_last end
end
-- n0: st.sw_n before a guarded call (nil outside one). The call's own text when it caught one (the call then answers
-- nil and that text, as if fn had raised it), else nil
local function swallowed(name, n0)
    local mine = n0 ~= nil and st.sw_n > n0
    local s = mine and st.sw_last or st.sw_first
    if s == nil then return nil end
    if not st.inherit_off then LAB.stop('arraynum', mine and name or s.at, s.text, nil, nil, 'swallowed', s.at) end
    return mine and s.text or nil
end

-- ---------- guards (section 3.4) ----------
local function is_inherit(name) return type(name) == 'string' and name:sub(1, #INHERIT) == INHERIT end
-- Refused after a stop (M1a D4): the 'lab.inherit.' prefix (alone keeps the M0 D9 start rule) or META.lab_inherited
function LAB.inherited(name) return is_inherit(name) or (type(name) == 'string' and cfg.inh[name] == true) end
-- The seconds a name lingers after a call that ran (M1a D4, section 3.4): META.lab_linger[name], at least
-- INHERIT_LINGER_S for an inherited name; 0 means no linger
function LAB.linger_s(name)
    local s = type(name) == 'string' and tonumber(cfg.linger[name]) or 0
    if LAB.inherited(name) and s < LAB.INHERIT_LINGER_S then s = LAB.INHERIT_LINGER_S end
    return s
end
-- Several names armed s more seconds with one write (a commit's linger group, section 3.4); a string is one name
function LAB.linger(names, s)
    if type(names) == 'string' then names = { names } end
    if type(names) ~= 'table' or names[1] == nil then return end
    SENT.linger_group(names, s)
end
local function refused(name)
    if not st.inherit_off then swallowed() end          -- a text caught outside every guard stops first
    if st.inherit_off and LAB.inherited(name) then
        LAB.count('inherited_after_trip')
        return true
    end
    return false
end
local function arraynum(name, err)
    if type(err) == 'string' and err:find(LAB.ARRAYNUM, 1, true) then LAB.stop('arraynum', name, err, nil, nil, 'pcall') end
end
-- ARM.mark once per name after a success; a refused mark (no build key yet, a failed write) retries MARK_TRIES times
local function mark(name)
    local m = st.marked[name]
    if m == true or (m or 0) >= LAB.MARK_TRIES then return end
    local h = LOG.header()
    local sha = h and type(h.loader) == 'table' and h.loader.commit or 'unknown'
    local ok, r = pcall(ARM.mark, name, LAB.CARD .. '@' .. tostring(sha))
    st.marked[name] = (ok and r) and true or (m or 0) + 1
end
-- A call that ran (not one the sentinel refused) lingers LAB.linger_s(name) after it returns: an inherited one at least
-- INHERIT_LINGER_S (D9: a delayed fault strikes its name, and for 'lab.inherit.*' the start check sets inherit_off).
-- The linger starts inside the call, after fn and before the sentinel's disarm write, a raised fn included (review
-- A5.1 F4): applied after SENT.sentinel returned, it left the disarm write (call '' and no linger) on disk for one file
-- write, where a render-thread fault of this call would strike no name
local function armed(name, fn, ...)
    local n0 = st.sw_n
    local s = LAB.linger_s(name)
    local call = fn
    if s > 0 then
        call = function(...)
            local res = table.pack(pcall(fn, ...))
            SENT.linger(name, s)
            if not res[1] then error(res[2], 0) end
            return table.unpack(res, 2, res.n)
        end
    end
    local r, err = SENT.sentinel(name, call, ...)
    -- A lingering call after the lab_end clear (lab_cap's or lab_piece's end hide that waited for F8 on, review int
    -- recheck): the dev clear runs again a frame later, so a menu quit after Ctrl+F11 still strikes no name (D20)
    if s > 0 and cfg.dev and st.ended and not st.clear_f then st.clear_f = S.frame end
    if err ~= nil then
        arraynum(name, err)
        swallowed(name, n0)
        return nil, err
    end
    local sw = swallowed(name, n0)
    if sw then return nil, sw end                       -- no mark: an ArrayNum inside is no success
    mark(name)
    return r
end
-- LAB.armed itself; LAB.sig runs its 'probe.meta' passes through it from inside the core, as LAB.hot runs armed(): a
-- lab02-only guard of the core, never a lab module's call (test_lab_stage0's guard scan reads LAB.armed calls only)
local function guard(name, fn, ...)
    if refused(name) then return nil, 'inherit_off' end
    return armed(name, fn, ...)
end
function LAB.armed(name, fn, ...) return guard(name, fn, ...) end
function LAB.hot(name, fn, ...)
    if refused(name) then return nil, 'inherit_off' end
    if not st.proven[name] then
        local r, err = armed(name, fn, ...)
        if err == nil and r ~= nil then st.proven[name] = true end
        return r, err
    end
    if SENT.is_disabled(name) then return nil, 'disabled_by_sentinel' end
    local hs = tonumber(cfg.hot[name]) or LAB.HOT_LINGER_S   -- META.lab_hot_linger: 0 runs a proven read bare
    if hs > 0 then SENT.linger(name, hs) end
    local n0 = st.sw_n
    local ok, r = pcall(fn, ...)
    if not ok then
        local err = tostring(r)
        arraynum(name, err)
        swallowed(name, n0)
        return nil, err
    end
    local sw = swallowed(name, n0)
    if sw then return nil, sw end
    return r
end

-- ---------- the proof ladder (M1a section 3.5) ----------
-- One forced proof record { step, name, ok, ... fields (err, ms, id, pair, sections, stray_bones, seam_ok) } and bus
-- lab_proof(name, ok) (lab_plan's readiness, D30); LAB.proof(name) answers true, false or nil (the step has not run)
-- for the session: a map load keeps it, nothing is retried
function LAB.prove(step, name, ok, fields)
    if type(name) ~= 'string' then return false end
    ok = ok == true
    local r = {}
    if type(fields) == 'table' then for k, v in pairs(fields) do r[k] = v end end
    r.step, r.name, r.ok = step, name, ok
    st.proofs[name] = ok
    LAB.rec('proof', r, true)
    BUS.emit('lab_proof', name, ok)
    return ok
end
function LAB.proof(name) return st.proofs[name] end
function LAB.ended() return st.ended == true end
-- The beta's proofs (beta port S2), no ladder: each name proven true for the session as a passed step would be
-- (lab_plan's readiness; lab_cap's and lab_piece's ladders skip it as run), then one forced proof_seed record { via,
-- names, n, ... fields } and bus lab_proof(name, true) per name, once every name is set. No engine call. -> the names
function LAB.seed(names, via, fields)
    local list, r = {}, {}
    for _, n in ipairs(type(names) == 'table' and names or {}) do
        if type(n) == 'string' then
            st.proofs[n] = true
            list[#list + 1] = n
        end
    end
    if type(fields) == 'table' then for k, v in pairs(fields) do r[k] = v end end
    r.via, r.names, r.n = via or 'seed', list, #list
    LAB.rec('proof_seed', r, true)
    for _, n in ipairs(list) do BUS.emit('lab_proof', n, true) end
    return list
end
-- The beta's pin check: true once the pins matched and the seed ran, false after a mismatch, nil before the check (and
-- outside the beta)
function LAB.pinned() return st.pinned end
-- Its answer by cause, for the Mods Menu Status row (main.lua, adapter/modsmenu.lua MENU.word): nil before init and
-- before the check, 'none' outside the beta, else 'pinned', 'waived' (other_ue4ss took an unlisted loader), 'loader'
-- (only the loader failed, no waiver) or 'game' (the game build, the ARM key or the pin table failed). No IO
function LAB.pin_state()
    if not A then return nil end
    if not cfg.beta then return 'none' end
    return st.pin_state
end

-- ---------- signatures (M1a D17) ----------
-- LAB.sig(name): the call class name (a section 3.4 name, a key of data/lab_classes.lua) lists data/hooks.lua calls
-- ids; each id's path goes through ue.sig_ok(path, want, name) against data/sigs.lua[path], each path in its own
-- LAB.armed('probe.meta') call (guard, LAB.armed's own path) and once per session (a path two classes share is read
-- once). true when every path matched in count, names and order: a FProperty class mismatch only shows in the sig
-- record (types_ok false, A1.3).
-- false and the first why otherwise: 'sig_mismatch', or 'sig_unknown' (a name without a class row, an id without a
-- path, a path without a want); a class with no UFunction passes trivially. Every path is checked, so each gets its
-- sig record. The answer is kept for the session; a guard that refused or raised (a disabled 'probe.meta', a failed
-- arm write, an ArrayNum stop) answers false and its text and is not kept. One new path a frame over every caller
-- (spec A3.2; lab_plan's pass and a module's first use alike): a class with a path still unchecked once this frame
-- paid one answers false, 'sig_pending' (not kept; a later frame asks again), and that frame is one-shot. The data
-- tables load at the first call: the probe never asks, so it never requires them
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
-- ok, why, kept (false: a refused or raised guard, or 'sig_pending', not kept)
local function sig_path(path, name)
    local c = st.sig_paths[path]
    if c then return c.ok, c.why, true end
    if st.sig_f == S.frame then return false, 'sig_pending', false end
    st.sig_f = S.frame
    LAB.oneshot()
    local want = data('data.sigs')[path]
    local r, err = guard('probe.meta', function() return { ue.sig_ok(path, want, name) } end)
    if err ~= nil or type(r) ~= 'table' then return false, tostring(err or 'unread'), false end
    local ok = r[1] == true
    c = { ok = ok, why = (not ok) and (r[2] or 'sig_mismatch') or nil }
    st.sig_paths[path] = c
    return c.ok, c.why, true
end
function LAB.sig(name)
    if type(name) ~= 'string' then return false, 'sig_unknown' end
    local c = st.sigs[name]
    if c then return c.ok, c.why end
    local ids = data('data.lab_classes')[name]
    local ok, why, keep, pend = true, nil, true, false
    if type(ids) ~= 'table' then ok, why = false, 'sig_unknown' end
    local calls = data('data.hooks').calls
    calls = type(calls) == 'table' and calls or {}
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        local path, o, w, k = calls[id], false, 'sig_unknown', true
        if type(path) == 'string' then o, w, k = sig_path(path, name) end
        if w == 'sig_pending' then pend = true
        elseif not o then
            if ok then why = w end
            ok, keep = false, keep and k
        end
    end
    if pend and keep then return false, 'sig_pending' end     -- every path gets its record before the answer
    if keep then st.sigs[name] = { ok = ok, why = why } end
    return ok, why
end
-- The shared tail of a lab module's guard, after its own words (its pin check, a breaker): 'disabled' (the sentinel
-- switched name off), 'inherit_off' (an inherited name after a stop), the sig check ('sig_pending': ask again next
-- frame; 'sig' and the sig's why, 'sig_unknown' when it gave none); nil when name may run. -> word, detail, raised
-- (true when LAB.sig raised: detail is the raw error, the caller trims it)
function LAB.refusal(name)
    if SENT.is_disabled(name) then return 'disabled' end
    if LAB.inherited(name) and not LAB.inherit_ok() then return 'inherit_off' end
    local okc, ok, why = pcall(LAB.sig, name)
    if not okc then return 'sig', ok, true end
    if ok ~= true then
        if why == 'sig_pending' then return 'sig_pending' end
        return 'sig', why or 'sig_unknown'
    end
    return nil
end

-- ---------- victims (D31, C8) ----------
local function is_keep(o) return type(o) == 'table' and rawget(o, '__mock') == nil and o.obj ~= nil end
function LAB.live(rec)
    if type(rec) ~= 'table' then return nil, 'none' end
    return ue.live(rec.keep or rec)
end
-- Actor.bActorIsBeingDestroyed (props, dump line 88, +0x5D): true from the destroy, while IsValid still reads true until
-- the GC runs [inferred, UE source: UWorld::DestroyActor sets it; live: corpses go 6-11 s after death, TC-LAB-02]. A
-- plain property read of a member every AActor declares; the caller passes an actor (a live victim or host), never a
-- component or a data object
function LAB.destroying(actor)
    local v = ue.prop(actor, 'bActorIsBeingDestroyed')
    if type(v) == 'boolean' then return v end
    return nil
end
-- The actor of a victim or keep record while it is live and not being destroyed; else nil and why ('destroyed',
-- 'collected' for ue.live's 'gone', 'reused', 'stale', 'none')
function LAB.alive(rec)
    local obj, why = LAB.live(rec)
    if not obj then return nil, why == 'gone' and 'collected' or why end
    if LAB.destroying(obj) == true then return nil, 'destroyed' end
    return obj
end
-- Real seconds since the death that made a corpse (the lab_row payload's death_t, the death source event, else its t:
-- the confirm; both on the real clock), 'unread' without one
local function host_age(d)
    local t = nil
    if type(d) == 'table' then t = type(d.death_t) == 'number' and d.death_t or type(d.t) == 'number' and d.t or nil end
    return t and math.floor((now() - t) * 10 + 0.5) / 10 or 'unread'
end
-- ---------- the admission ledger (M1a 4.1 item 1): which admitted pawns are controls ----------
-- The first CTRL_N lab-pair pawns a session admits are controls ('ctrl': lab_plan gives them keep_ctrl, lab_keep writes
-- nothing); every later one is pre-armed ('armed': lab_keep writes the keep levers before the death, lab_plan gives its
-- death the first free kept row). LAB.reserve(key, ok, via) is called by the listeners of both modules at the bus
-- lab_admit (ok: the pawn is of a lab pair, the lab is armed and the mod is on; via: lab_poll's admission route); the
-- first call of a key decides, any later one reads. A 'findall' admission (the idle pawns within 50 m at a map load,
-- which the author may never kill) never takes a control slot: it is pre-armed at once (lead 2026-10-31, fix round
-- review P2), so the controls are the first CTRL_N pawns spawned or hit. -> kind, n (the pawn's ordinal among its kind,
-- from 1) | nil (not reserved: ok was not true). The ledger belongs to the session: a map load keeps it (registry keys
-- carry the epoch), a restart of the lab resets it
function LAB.reserve(key, ok, via)
    if type(key) ~= 'string' then return nil end
    local r = st.resv[key]
    if r then return r.kind, r.n end
    if ok ~= true then return nil end
    if via ~= 'findall' and st.nctrl < LAB.CTRL_N then
        st.nctrl = st.nctrl + 1
        r = { kind = 'ctrl', n = st.nctrl }
    else
        st.narm = st.narm + 1
        r = { kind = 'armed', n = st.narm }
    end
    st.resv[key] = r
    st.resv_order[#st.resv_order + 1] = key
    if #st.resv_order > LAB.RESERVATIONS then st.resv[table.remove(st.resv_order, 1)] = nil end
    return r.kind, r.n
end
-- The reservation of a key without making one: kind, n | nil
function LAB.reserved(key)
    local r = key ~= nil and st.resv[key] or nil
    if r then return r.kind, r.n end
    return nil
end
-- The host of a ladder step (M1a 4.1 item 3) as proof fields merged into f (a new table when nil): host_age_s (host_age)
-- and host_destroying, bActorIsBeingDestroyed read from the actor ('unread' when it reads no boolean or there is no
-- actor). The ladders read both after the step, so a host the game destroyed under the step shows
function LAB.host_state(actor, d, f)
    f = f or {}
    f.host_age_s = host_age(d)
    local dying = nil
    if actor ~= nil then dying = LAB.destroying(actor) end
    if dying == nil then f.host_destroying = 'unread' else f.host_destroying = dying end
    return f
end
-- A ladder step skipped because its host is dead (M1a 4.1 item 3): no call, no proof, the ladder re-hosts. One forced
-- 'ladder_skip' record { owner ('lab_cap', 'lab_piece'), step (the next step), why 'host_dead', host_why (LAB.alive's
-- word), id, pair, host_age_s } and the counter '<owner>_host_dead'
function LAB.host_skip(owner, step, d, host_why)
    d = type(d) == 'table' and d or {}
    LAB.count(owner .. '_host_dead')
    LAB.rec('ladder_skip', { owner = owner, step = step, why = 'host_dead', host_why = host_why or 'unread', id = d.id,
        pair = d.pair, host_age_s = host_age(d) }, true)
end
-- Over VICTIMS: records that fail LAB.live go, then the oldest
local function prune()
    for k, r in pairs(st.reg) do
        if not LAB.live(r) then st.reg[k], st.nreg = nil, st.nreg - 1 end
    end
    while st.nreg > LAB.VICTIMS do
        local old, ot = nil, nil
        for k, r in pairs(st.reg) do if ot == nil or r.t < ot or (r.t == ot and k < old) then old, ot = k, r.t end end
        st.reg[old], st.nreg = nil, st.nreg - 1
    end
end
-- The record of a live object (or a ue.keep record that still passes ue.live): nil and why otherwise. The class is the
-- first token of GetFullName ('<Class> <path>'): no UFunction, no class object kept
function LAB.victim(o)
    local kp, obj = nil, o
    if is_keep(o) then
        local why
        obj, why = ue.live(o)
        if not obj then return nil, why end
        kp = o
    elseif not ue.valid(o) then
        return nil, 'gone'
    end
    local full = ue.full(obj) or ue.name(obj) or 'unread'
    local key = string.format('%s|%s|%d', tostring(ue.addr(obj)), full, ue.epoch)
    local rec = st.reg[key]
    if rec then return rec end
    rec = { key = key, keep = kp or ue.keep(obj), full = full, class = full:match('^(%S+) ') or 'unread',
        epoch = ue.epoch, life = 1, id = key .. '#1', t = now() }
    st.reg[key], st.nreg = rec, st.nreg + 1
    if st.nreg > LAB.VICTIMS then prune() end
    return rec
end
-- A confirmed death: the life that ended; the record goes on with the next life (a revive is a new life)
function LAB.next_life(rec)
    local ended = rec.life
    rec.life = ended + 1
    rec.id = rec.key .. '#' .. rec.life
    return ended
end

-- ---------- snapshots: the last SNAPS per victim key, oldest first ----------
function LAB.snap_push(key, snap)
    if key == nil or type(snap) ~= 'table' then return end
    if snap.t == nil then snap.t = now() end
    local r = st.snaps[key]
    if not r then
        r = { n = 0 }
        st.snaps[key], st.nsnaps = r, st.nsnaps + 1
    end
    r.n, r.t = r.n + 1, snap.t
    r[(r.n - 1) % LAB.SNAPS + 1] = snap
    if st.nsnaps > LAB.SNAP_KEYS then
        local old, ot = nil, nil
        for k, x in pairs(st.snaps) do if k ~= key and (ot == nil or x.t < ot) then old, ot = k, x.t end end
        if old ~= nil then st.snaps[old], st.nsnaps = nil, st.nsnaps - 1 end
    end
end
function LAB.snaps(key, since_t)
    local r, out = st.snaps[key], {}
    if not r then return out end
    for i = math.max(1, r.n - LAB.SNAPS + 1), r.n do
        local s = r[(i - 1) % LAB.SNAPS + 1]
        if since_t == nil or (s.t or 0) >= since_t then out[#out + 1] = s end
    end
    return out
end
-- The victims hit since since_t (BL1's 'victims hit in the last 5 s', S2.15): { rec = the registry record, t = its
-- newest snapshot time } for each snapshot ring at or after since_t whose registry record still exists, by key
function LAB.recent(since_t)
    local keys, out = {}, {}
    for k, r in pairs(st.snaps) do
        if st.reg[k] ~= nil and (since_t == nil or (r.t or 0) >= since_t) then keys[#keys + 1] = k end
    end
    table.sort(keys)                                     -- registry keys are strings ('<addr>|<full name>|<epoch>')
    for i, k in ipairs(keys) do out[i] = { rec = st.reg[k], t = st.snaps[k].t } end
    return out
end

-- ---------- pair labels (refuted.md:98, review SEAMS-1) ----------
-- Anchored on the class token, case-insensitive (the last token of a path or full name): MaleThug is a class name
-- starting 'bp_monster_malethug_' (never FemaleThug, whose name contains 'malethug'); GuiChai only
-- 'bp_monster_guichai_black_' (family 037 Black, the PLAN pair; never the GuiChaiHorse, White, Yellow, Cyan or Red
-- classes). PBZ names its monster classes BP_Monster_<family>_... (410 of the 413 BP_RenewalNPC_C descendants in
-- data/hide_table.lua): such a family-named class takes its label from its own token only, and a game id never moves
-- it into a pair. The game id labels only classes without that token.
LAB.PAIRS = { { 'bp_monster_malethug_', 'MaleThug' }, { 'bp_monster_guichai_black_', 'GuiChai' } }
LAB.FAMILY_PREFIX = 'bp_monster_'
-- The pair name of a class, or nil; second: whether the name carries a family token
local function label_of(class)
    local s = tostring(class or ''):lower()
    s = s:match('([^%s%./]+)$') or s
    for _, p in ipairs(LAB.PAIRS) do
        if s:sub(1, #p[1]) == p[1] then return p[2], true end
    end
    return nil, s:sub(1, #LAB.FAMILY_PREFIX) == LAB.FAMILY_PREFIX
end
-- An id value as text, nil when it says nothing: nil, '', 'unread' (section 3: a value nobody read), 'None' (an empty
-- FName). Such a value never becomes a key: two families both read 'unread' would share one label
local NO_ID = { [''] = true, unread = true, none = true }
local function id_text(v)
    if type(v) == 'number' then return tostring(v) end
    if type(v) ~= 'string' then return nil end
    v = v:match('^%s*(.-)%s*$')
    if NO_ID[v:lower()] then return nil end
    return v
end
-- RC's game_id { codex, char_type_tags, actor_data } (or one plain id): the first informative of codex and actor_data,
-- else nil. CharacterType tags alone are never a game id: RC keeps only the CharacterType tags, and grunts of two
-- families share one set (CharacterType.Human), so a tag-only key merged them and the first label won
local function gid_key(g)
    if type(g) ~= 'table' then return id_text(g) end
    return id_text(g.codex) or id_text(g.actor_data)
end
-- A game id's label: the first pair name among the classes that report it ('other' until one has a pair name, and a
-- pair name never flips to the other one), so a later class with the same id gets the same label
function LAB.set_game_id(class, game_id)
    local g = gid_key(game_id)
    if class == nil or g == nil then return end
    st.game_ids[class] = g
    local named, was = label_of(class), st.game_pair[g]
    if was == nil or (was == 'other' and named) then st.game_pair[g] = named or 'other' end
end
-- The game id key RC stored for a class (the codex, else the Actor Config path), or nil (lab_poll: kill.family,
-- fodder.game_ids)
function LAB.game_id(class)
    if class == nil then return nil end
    return st.game_ids[class]
end
-- label, pair_by: a family-named class keeps its own label (a pair name or 'other'); another class takes its game id's
-- label once RC knows it. pair_by 'game_id' when the game id's label is the one returned, else 'class'
function LAB.pair_of(class, game_id)
    local g = gid_key(game_id)
    if g == nil and class ~= nil then g = st.game_ids[class] end
    local by_id = g ~= nil and st.game_pair[g] or nil
    local own, family = label_of(class)
    local label = own or ((family or by_id == nil) and 'other' or by_id)
    return label, by_id == label and 'game_id' or 'class'
end

-- ---------- posts, pause ----------
function LAB.post(fn, name)
    if type(fn) ~= 'function' then return false end
    if #st.posts >= LAB.POSTS then
        st.dropped = st.dropped + 1
        return false
    end
    st.posts[#st.posts + 1] = { fn = fn, name = name or 'lab_post', ep = ue.epoch }
    return true
end
function LAB.paused() return S.paused == true end
function LAB.due(key, period_s)
    if LAB.paused() then return false end
    local t, at = now(), st.due[key]
    if at and t < at then return false end
    st.due[key] = t + (period_s or 1)
    return true
end

-- ---------- frame gauges (section 3.2) ----------
local function push(r, t, v)
    r.n = r.n + 1
    local j = (r.n - 1) % r.cap + 1
    r.t[j], r.v[j] = t, v
end
local function window(r)
    local since, out = now() - LAB.WINDOW_S, {}
    for i = math.max(1, r.n - r.cap + 1), r.n do
        local j = (i - 1) % r.cap + 1
        if r.t[j] >= since then out[#out + 1] = r.v[j] end
    end
    return out
end
local function max_of(list)
    local m = nil
    for _, v in ipairs(list) do if m == nil or v > m then m = v end end
    return m
end
local function p95(list)
    if not list[1] then return nil end
    table.sort(list)
    return list[math.max(1, math.ceil(#list * 0.95))]
end
-- Once per lab tick: the last finished on_frame, each frame once; a paused frame is skipped (the poll and the
-- observation reads pause there, so its near-zero cost would pull the ordinary p95 down)
local function sample()
    if not (A and A.frame_cost) then return end
    local ok, f, ms, one = pcall(A.frame_cost)
    if not ok or f == nil or f == st.last_f or type(ms) ~= 'number' then return end
    st.last_f = f
    if LAB.paused() then return end
    push(one and st.one or st.ord, now(), ms)
end

-- ---------- the beta's pin check (beta port S2): once per session ----------
-- On the first lab tick with a build key (session_engine sets it on the first frame, before any ticker; a key still
-- unknown PIN_WAIT_S after init reads 'unknown'): the header's game_build, ARM.key() and the header's loader commit
-- against META.beta_pins, all three or nothing. A match seeds META.beta_seed (via 'pin', the pins in the record); a
-- mismatch, an unknown value or no pin table writes one forced beta_unpinned record { pins, want } and seeds nothing:
-- no cut route gets ready (fail closed), blood needs no proof. The loader pin also takes any commit of
-- META.beta_loaders (UE4SS builds whose Lua marshalling matches the pinned one's; the record lists them as loaders).
-- The loader waiver (fixes-0.2.2 F4.1, D6): the player knob other_ue4ss (default false), read once here under pcall
-- (`okk, on`; a knob that raises reads off) and only after a mismatch. When the game build and the ARM key matched and
-- only the loader failed, a knob that reads true pins the session anyway: META.beta_seed via 'waived' { pins, waived }
-- and one forced loader_waived record { loader, want, loaders, game_build, arm_key }. The waiver never covers the game
-- build or the ARM key (beta_unpinned then carries waiver = true), and it adds no guard exemption: LAB.seed sets proofs
-- only, every LAB.armed call stays armed and LAB.hot keeps its first-read arming. Knob off: today's path, the same
-- records. Load-only: pin_check runs once a session and a later flip waits for the next game start (17 consumers read
-- the session verdict; lab_kill fixes st.tier once, lab_corpse closes corpse.keep for the session)
local PIN_KEYS = { 'game_build', 'arm_key', 'loader' }
local function pin_ok(k, got, want)
    if type(want) == 'string' and got == want then return true end
    if k == 'loader' and type(cfg.loaders) == 'table' then
        for _, v in ipairs(cfg.loaders) do if got == v then return true end end
    end
    return false
end
local function pin_check(t)
    local key = ARM.key()
    if key == nil and t < st.pin_at then return end
    st.pin_done = true
    local h = LOG.header() or {}
    local got = { game_build = tostring(h.game_build or 'unknown'), arm_key = key or 'unknown',
        loader = tostring(type(h.loader) == 'table' and h.loader.commit or 'unknown') }
    local want, tbl = cfg.pins, type(cfg.pins) == 'table'
    local ok, other = tbl, not tbl                      -- other: a key but the loader failed (no pin table: all)
    for _, k in ipairs(PIN_KEYS) do
        if not tbl or type(want[k]) ~= 'string' or not pin_ok(k, got[k], want[k]) then
            ok = false
            if k ~= 'loader' then other = true end
        end
    end
    if ok then
        st.pinned, st.pin_state = true, 'pinned'
        LAB.seed(cfg.seed, 'pin', { pins = got })
        return
    end
    local okk, on = pcall(C.knob, 'other_ue4ss')
    local waive = okk and on == true
    if waive and not other then
        st.pinned, st.pin_state = true, 'waived'
        LAB.seed(cfg.seed, 'waived', { pins = got, waived = { 'loader' } })
        LAB.rec('loader_waived', { loader = got.loader, want = want.loader, loaders = cfg.loaders,
            game_build = got.game_build, arm_key = got.arm_key }, true)
        return
    end
    st.pinned, st.pin_state = false, other and 'game' or 'loader'
    LAB.rec('beta_unpinned',{ pins = got, want = tbl and want or 'none', loaders = cfg.loaders,
        waiver = waive or nil }, true)
end

-- ---------- the lab ticker: frame sample, the stop's bus event, posts, the log tail, lab_flush ----------
local function flush(reason)
    st.next_flush, st.flushes = now() + LAB.FLUSH_S, st.flushes + 1
    BUS.emit('lab_flush', reason)
end
local function drain()
    if not st.posts[1] then return end
    local list = st.posts
    st.posts = {}
    for _, p in ipairs(list) do
        if p.ep == ue.epoch then S.run(p.name, p.fn) else st.stale = st.stale + 1 end
    end
end
local function scan(t)
    local hits, off = ENV.log_scan(st.log_off, { LAB.ARRAYNUM })
    if hits == nil then
        st.next_scan = t + LAB.SCAN_RETRY_S                 -- unreadable (one log_scan_unavailable line per init)
        return
    end
    if off - st.log_off > LAB.SCAN_BIG then LAB.oneshot() end   -- a catch-up read (the session head) is one-shot
    st.log_off, st.next_scan = off, t + LAB.SCAN_S
    local h = hits[1]
    if h then LAB.stop('arraynum', 'UE4SS.log@' .. tostring(h.offset), h.line, h.line, h.before, 'log_unclear') end
end
local function tick()
    sample()
    if not st.inherit_off then swallowed() end
    if st.stop_emit then
        st.stop_emit = false
        BUS.emit('lab_stop', st.stop.why)
    end
    drain()
    local t = now()
    if cfg.beta and not st.pin_done then pin_check(t) end
    if not st.inherit_off and not cfg.beta and t >= st.next_scan then scan(t) end    -- the beta reads no log tail
    if st.clear_f and S.frame > st.clear_f then
        st.clear_f = nil
        SENT.linger_clear()                             -- M1a D20: no name left lingering (below)
    end
    if st.end_flush then
        st.end_flush = false
        flush('lab_end')
        -- M1a D20: the clear waits a frame. Every lab module ends in its first tick after lab_end (lab_cut closes an
        -- open GCAP-a and drops a staged job under its armed names, lab_cap and lab_piece hide a shown test object),
        -- and that tick comes before this ticker's tick in the next frame, whatever the ticker order
        if cfg.dev then st.clear_f = S.frame end
    elseif t >= st.next_flush then
        flush('periodic')
    end
end

-- ---------- lifecycle ----------
-- The start check (D9, review RUNTIME-4): inherit_off for a name that was in flight (MAIN.tripped names the armed
-- call; 'linger:<name>' is a second same-build strike of a name that only lingered) or for a struck or linger-tripped
-- 'lab.inherit.*' name (each lingers INHERIT_LINGER_S after its call: armed()). A strike or linger trip of any other
-- name writes one stop record kind 'strike' and sets nothing: lab.read.gas lingers through unpaused play and PBZ has
-- no quit hint (D30), so an Alt+F4 or a vanilla crash strikes it. The text names every trip and strike.
local function start_check(tripped, struck)
    struck = type(struck) == 'table' and struck or {}
    local parts = {}
    if tripped ~= nil then parts[#parts + 1] = 'sentinel_tripped: ' .. tostring(tripped) end
    if struck[1] ~= nil then parts[#parts + 1] = 'sentinel_strike: ' .. table.concat(struck, ', ') end
    if not parts[1] then return end
    local text = table.concat(parts, '; ')
    local lingered = type(tripped) == 'string' and tripped:match('^linger:(.+)$') or nil
    if (tripped ~= nil and lingered == nil) or is_inherit(lingered) then
        return LAB.stop('sentinel', tripped, text, nil, nil, 'start')
    end
    for _, n in ipairs(struck) do
        if is_inherit(n) then return LAB.stop('sentinel', n, text, nil, nil, 'start') end
    end
    LAB.rec('stop', stop_rec('sentinel', tripped or struck[1], text, nil, nil, 'start', 'strike'))
end
-- A: the main.lua feature view (MAIN.A, then MAIN: count, gauge, oneshot, frame_cost, tripped, struck)
function LAB.init(adapter)
    A = adapter
    st = new_state()
    configure((A and A.meta) or META)
    st.next_flush, st.pin_at = now() + LAB.FLUSH_S, now() + LAB.PIN_WAIT_S   -- st.pin_done, st.pinned: nil until then
    LAB.gauge('probe_frame_ms_p95', function() return p95(window(st.ord)) end)
    LAB.gauge('probe_frame_ms_max', function() return max_of(window(st.ord)) end)
    LAB.gauge('probe_oneshot_ms_max', function() return max_of(window(st.one)) end)
    S.ticker('lab_probe', tick)
    BUS.on('lab_end', 'lab_probe', function() st.end_flush, st.ended = true, true end)   -- queued: the tick flushes
    ue.on_error(on_caught, 'lab_probe')                 -- one entry: a reloaded module replaces it
    start_check(A.tripped, A.struck)
    return true
end
-- A map load: the older map's queued posts go (main.lua bumped ue.epoch already), then the old map's flush (lab_probe
-- resets before the other lab modules; a listener's LAB.post carries the new epoch and runs on the next tick), then
-- the index and the snapshots go; the stop, the pair labels and the log offset stay for the session
function LAB.reset(reason)
    st.stale = st.stale + #st.posts
    st.posts = {}
    if reason == 'map' and A then flush('map') end
    st.reg, st.nreg, st.snaps, st.nsnaps = {}, 0, {}, 0
end
function LAB.status()
    return { inherit_off = st.inherit_off, stop = st.stop and st.stop.why or nil, victims = st.nreg,
        posts = #st.posts, dropped = st.dropped, stale = st.stale, flushes = st.flushes, log_off = st.log_off }
end
function LAB.shutdown()
    S.remove_ticker('lab_probe')
    BUS.off('lab_end', 'lab_probe')
    ue.on_error(nil, 'lab_probe')
    st, A = new_state(), nil
end

return LAB
