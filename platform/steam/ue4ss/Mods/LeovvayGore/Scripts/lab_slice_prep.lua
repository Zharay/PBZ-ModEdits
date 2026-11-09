-- status: new for the beta test build (offline only, run on fakes; the author's lab run decides) origin: the
-- 2026-11-01 22:17 lab run (state/sessions/20261101-2217-crash: armed.json call 'slicer.cut.lod', the direct cut on
-- the ladder's LOD 1 rung, crashed the game on the second MaleThug slice row) and the route A study of the game's own
-- slice (GAAction_SliceSkeleton_C: Prepare, Capture, SlicePrepared, Release)
-- lab_slice_prep.lua: the prepared cut of lab_slice_route, a library the route requires (main.lua's LIBS puts it in
-- the code hash) and binds (PC.bind) to its own fallback, breaker, class verdicts and constants. A first cut on a LOD
-- above 0, on LOD 0 whose CPU bit read false, or on LOD 0 that the corpse did not render in the cut frame (the route's
-- LOD 0 check, per corpse: PC.begin(job, 0, 'lod0_not_rendered')) never runs the direct slice (SL.cut takes no lod:
-- LOD 0 only): it runs the game's own sequence, each native call a lab_slice primitive under its own sentinel name, in
-- its own ticker step (frame):
--   1. 'prep': PrepareSkeletalMeshSliceRuntime on LOD k (SL.prepare, 'slicer.prepare': it forces LOD k and stores a
--      handle for R.PREP_LIFE_S). A handle that did not read ('unread': UE4SS handed the out struct back in no form
--      lab_slice_lod reads), a zero one (Prepare's own zeroed OutHandle: nothing prepared), a false return, a refused
--      or raised call: never SlicePrepared; Release when a handle read, then the joint cut (the class's verdict goes
--      off for the session on 'prep_handle' and 'prep_failed').
--   2. 'prep_wait': one read a frame (SL.prep_read, 'slicer.prep.read') until ForcedLodModel reads k + 1,
--      GetPredictedLODLevel k and the asset's streaming flag false on STABLE_F frames in a row, at most
--      R.PREP_WAIT_F frames; a forced LOD that moved ('prep_forced_lost') or the time-out ('prep_wait'): Release, then
--      the joint cut.
--   3. 'cut' (lab_slice_route's slice_part: the plane's bones read in the cut frame, the side test, one slice a frame):
--      SL.cut_prep ('slicer.cut.prep': SlicePreparedSkeletalMeshComponentRuntime with the handle, LOD k's forced and
--      predicted LOD read again inside the call). Refused before the slice: Release, then the joint cut; ran: Release,
--      then the route's after step.
--   4. 'prep_release': ReleasePreparedSkeletalMeshSlice (SL.release, 'slicer.release', not inherited) on every path
--      that holds a handle, before the joint cut or the after step. A job that ends any other way (the route's
--      time-out, mod-off, a stop, lab_end, the knob, the breaker, a Lua error) hands its handle to the route's
--      late-release queue (PC.hand_off: released 'late'), which the ticker empties first thing each frame, while off
--      too.
-- One forced slice_step { id, class, step, k } record goes out before the first attempt of each native step
-- ('prepare', 'wait', 'cut', 'release'; the route's late release writes 'release_late'): the log flushes each line, so
-- a native crash leaves its step and LOD beside armed.json's call name.
-- Record (job.pc; the slice and slice_skip records' prep): { k, why ('lod0_not_rendered': the route's LOD 0 check sent
-- it; nil: the ladder's LOD), handle ({ lod, from } | 'unread' | 'zero' | 'not_run'), forced_before, forced_after
-- (ForcedLodModel around Prepare), ret, ms (Prepare's), resident (the last wait read: forced, predicted, pending),
-- frames_waited, stable, sliced (true | the cut's why | 'refused:<why>' | 'not_reached'), released (true | false |
-- 'ret_unread' | 'no_handle' | 'late' | 'dropped' | '<why>'), err }.
-- API: bind(h); wanted(job) -> bool; begin(job, k, why) (k: default job.lod.k); the steps prep(job) wait(job)
--   release(job); cut(job, P, N, choice, cell) -> SL.cut_prep's answer; refused(job, why, o) and ran(job, ok, why)
--   after the cut; hand_off(job, q, max).
-- What the mock cannot prove: everything native (whether the handle marshals out and back, whether GetPredictedLODLevel
--   tracks the slicer's stable resident LOD, whether SlicePrepared on LOD 1 holds where the direct cut crashed).
local PC = { STABLE_F = 2, ERR_CHARS = 160 }
local H = nil                                       -- the route's helpers (PC.bind)

local function text(s)
    s = tostring(s)
    return #s > PC.ERR_CHARS and s:sub(1, PC.ERR_CHARS) or s
end
-- The forced slice_step record, once per job and step, before the step's first native attempt
local function step_rec(job, step, k)
    job.pc_steps = job.pc_steps or {}
    if job.pc_steps[step] then return end
    job.pc_steps[step] = true
    H.rec('slice_step', { id = job.id, class = job.class, step = step, k = k })
end

-- The job's first cut goes prepared: the ladder's LOD above 0, or LOD 0 whose CPU bit read false (route 'chose'). A
-- LOD 0 cut the corpse does not render goes prepared too, decided in the cut frame (the route's PC.begin(job, 0, why))
function PC.wanted(job)
    local l = job.lod
    return type(l) == 'table' and math.type(l.k) == 'integer' and (l.k ~= 0 or l.set == true)
end
-- The prepared cut on LOD k (default the ladder's job.lod.k; the route's LOD 0 check passes 0 and its why): Prepare
function PC.begin(job, k, why)
    job.pc = { k = k or job.lod.k, why = why, sliced = 'not_reached', frames_waited = 0, stable = 0 }
    job.step = 'prep'
end
-- After the release: the after step, or the joint cut (with the class's verdict first when the reason asks for it)
local function go_on(job)
    local n = job.pc_next or { why = 'prep', step = 'prep_release' }
    job.pc_next = nil
    if n.after then
        job.step = 'after'
        return
    end
    if n.verdict then H.verdict(job.class, false, n.why, n.detail) end
    return H.fallback(job, n.why, n.step, n.detail, n.raised)
end
-- Release the handle in its own step, then go on (nxt: { after } or a fallback { why, step, detail, raised, verdict })
local function then_release(job, nxt)
    job.pc_next = nxt
    if job.prep_h then
        job.step = 'prep_release'
        return
    end
    job.pc.released = job.pc.released or 'no_handle'
    return go_on(job)
end

-- ---------- the steps (inside SL.step: the route's ticker frame) ----------
function PC.prep(job)
    local r, k = job.pc, job.pc.k
    step_rec(job, 'prepare', k)
    local ok, why, d = H.SL.prepare(job.rec, 'body', k, H.R.PREP_LIFE_S)
    local o = H.SL.outcome(ok, why, d)
    if o == 'wait' or H.stream_retry(job, why) then return end
    d = type(d) == 'table' and d or {}
    r.ret, r.ms, r.forced_before, r.forced_after = d.ret, d.ms, d.forced_before, d.forced
    r.err = o ~= 'ok' and text(why) or nil
    local h = d.handle
    if H.SL.zero_handle(h) then
        r.handle, h = 'zero', nil                   -- Prepare's own zeroed OutHandle: nothing was prepared
    elseif type(h) == 'table' then
        r.handle = { lod = h.lod, from = h.from }
    else
        r.handle = o == 'refused' and 'not_run' or 'unread'
    end
    if h then job.prep_h = h end                    -- released below, or by the route's late queue (PC.hand_off)
    if o ~= 'ok' then
        return then_release(job, { why = o == 'raised' and 'error' or 'prep_refused', step = 'prep', detail = why,
            raised = o == 'raised' })
    end
    if r.handle == 'unread' then                    -- never sent back unread: no SlicePrepared, no Release
        return then_release(job, { why = 'prep_handle', step = 'prep', detail = 'unread', verdict = true })
    end
    if d.ret ~= true or not h or h.lod ~= k then
        return then_release(job, { why = 'prep_failed', step = 'prep', detail = { ret = d.ret, handle = r.handle },
            verdict = true })
    end
    job.step = 'prep_wait'
end
function PC.wait(job)
    local r, k = job.pc, job.pc.k
    step_rec(job, 'wait', k)
    local ok, why, d = H.SL.prep_read(job.rec, 'body', k)
    local o = H.SL.outcome(ok, why, d)
    if o == 'wait' then return end
    r.frames_waited = r.frames_waited + 1
    if o ~= 'ok' then
        return then_release(job, { why = o == 'raised' and 'error' or 'prep_read', step = 'prep_wait', detail = why,
            raised = o == 'raised' })
    end
    r.resident = { forced = d.forced, predicted = d.predicted, pending = d.pending }
    if d.forced ~= nil and d.forced ~= k + 1 then   -- read (not a pending frame) and moved: someone forced another LOD
        return then_release(job, { why = 'prep_forced_lost', step = 'prep_wait', detail = r.resident })
    end
    r.stable = d.ready == true and r.stable + 1 or 0
    if r.stable >= PC.STABLE_F then
        job.step = 'cut'
        return
    end
    if r.frames_waited >= H.R.PREP_WAIT_F then
        return then_release(job, { why = 'prep_wait', step = 'prep_wait', detail = r.resident })
    end
end
function PC.release(job)
    local r, h = job.pc, job.prep_h
    if not h then
        r.released = r.released or 'no_handle'
        return go_on(job)
    end
    step_rec(job, 'release', r.k)
    local ok, why, d = H.SL.release(h)
    local o = H.SL.outcome(ok, why, d)
    if o == 'wait' then return end
    job.prep_h = nil
    if o == 'ok' then
        r.released = d.ret == nil and 'ret_unread' or d.ret
    else
        r.released = text(why)
        if o == 'raised' then H.failed('release:' .. tostring(why)) end
    end
    return go_on(job)
end

-- ---------- the cut (lab_slice_route's slice_part) ----------
function PC.cut(job, P, N, choice, cell)
    step_rec(job, 'cut', job.pc.k)
    return H.SL.cut_prep(job.rec, P, N, choice, cell, job.key, job.pc.k, job.prep_h)
end
-- Refused before the slice (o: SL.outcome's word): Release, then the joint cut
function PC.refused(job, why, o)
    job.pc.sliced = 'refused:' .. text(why)
    return then_release(job, { why = 'cut_refused', step = 'cut', detail = why, raised = o == 'raised' })
end
-- The slice ran: Release, then the route's after step
function PC.ran(job, ok, why)
    job.pc.sliced = ok == true or (why ~= nil and text(why)) or false
    return then_release(job, { after = true })
end

-- A job that ends holding a handle (its own or the route's X4 Prepare): the handle goes to the late-release queue q
-- (at most max; released 'late', 'dropped' when q is full). Call it before the job's record is written
function PC.hand_off(job, q, max)
    local h = job.prep_h
    if not h then return end
    job.prep_h = nil
    local r = job.pc
    if #q < max then
        h.id = job.id
        q[#q + 1] = h
        if r and r.released == nil then r.released = 'late' end
    elseif r and r.released == nil then
        r.released = 'dropped'
    end
end

-- h: the route's helpers { SL, R (its constants: PREP_LIFE_S, PREP_WAIT_F), fallback(job, why, step, detail, raised),
-- failed(why), verdict(class, ok, why, detail), stream_retry(job, why) (true: a 'lod_streaming' refusal the job
-- retries next frame, counted), rec(ev, fields) (a forced record) }
function PC.bind(h) H = h end
return PC
