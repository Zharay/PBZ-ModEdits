-- status: new for the beta test build (offline only, smoke-run on fakes; the author's run decides) origin: the route A
-- study of the slicer's CPU gate (2026-11-01, static: PBZ.exe 26266538 disassembly, the CXX and object dumps)
-- lab_slice_lod.lua: the per-LOD CPU state of a skeletal mesh for the game's own slicer, and the LOD experiment's
-- primitives, a library lab_slice requires (main.lua's LIBS puts it in the code hash). LD.bind(h) hands it lab_slice's
-- own guard (run), answer, same-frame checks, frame cache, cut job and self-call flag at lab_slice's load, so the names,
-- guards and refusals stay lab_slice's; it adds SL.preflight_lod, SL.prepare, SL.prep_read, SL.cut_prep and
-- SL.release. lab_slice_watch reads LD.view through SL.lod_view. No guard of its own: every job runs inside a lab_slice
-- run() under its own sentinel name.
-- * Why SourceModels: in this UE 5.7 build the per-LOD info lives in USkeletalMesh::SourceModels (TArray of
--   FSkeletalMeshSourceModel at 0x100, element 0x150, FSkeletalMeshLODInfo its base: bAllowCPUAccess is byte +0xD0 mask
--   4). The native GetLODInfo (0x1444d22e0, vtable slot +0x328/+0x330) indexes SourceModels, and the slicer's CPU gate
--   (0x14604ae20) reads the bit through it [verified, static]. USkeletalMesh::LODInfo (0x508) is a deprecated property
--   that stays empty: the 2026-11-01 test build read #LODInfo 0 on MaleThug and GuiChai, so its cpuflag never wrote.
-- * The bit only lets the gate pass; the CPU copies of the vertex, skin-weight and index buffers exist only for a LOD
--   that loaded or streamed in while r.FreeSkeletalMeshBuffers was 0 or its bit was already set (0x143a98570,
--   0x1444dc4f0) [inferred from that chain]: a bit set later passes the bit check, never the buffer checks.
-- * The experiment (X1, X4 of the study), for lab_slice_route when the LOD 0 preflight reports 'failed while extracting
--   source data' (or LOD 0's bit read false: the route then runs no LOD 0 rung, here or in X4, and writes no LOD 0 bit):
--   - one rung: in ONE guarded call, SourceModels[k].bAllowCPUAccess read; written true when it reads false (one
--     counted write, read back); DebugSkeletalMeshSlicePreflight with Options.LODIndex k; the bit written back to what
--     it read (also when the preflight raised) and read again. Never left set across a frame: Niagara's skeletal-mesh
--     data interface tests the same bit (0x144ab7184, 0x144abca46) and could read discarded CPU arrays [inferred].
--     Under 'slicer.cpuflag' for LOD 0, 'slicer.lodpre' for LOD 1-3. A k past GetNumLODs or #SourceModels refuses
--     'lod_range' before any write.
--   - NO direct cut on a LOD above 0, nor on a LOD whose bit had to be set (the 2026-11-01 22:17 lab run: the direct
--     cut on LOD 1, the old 'slicer.cut.lod', crashed natively with the component still rendering LOD 0; that name is
--     retired and never run again). Such a cut goes only the game's own way (GAAction_SliceSkeleton_C, route A):
--   - Prepare (under 'slicer.prepare', inherited: it forces the component's LOD): PrepareSkeletalMeshSliceRuntime with
--     LODIndex k and LifetimeSeconds; it zeroes the OutHandle (ID 0, LODIndex -1), checks k against the render data,
--     forces LOD k (SetForcedLOD(k + 1)) and stores a handle under a new FGuid (0x1460421a0): it copies no mesh data.
--     A struct out fills its own table in place (adapter/ue.lua): the handle reads out.ID.A-D and out.LODIndex (a build
--     that nests it under out.OutHandle is read too), copied to plain values in the call with ForcedLodModel before and
--     after it. A zero ID is no handle (nothing prepared); an unread one is never sent back (the caller falls back).
--   - the wait (SL.prep_read, under 'slicer.prep.read', reads only): the same-frame checks (a pending streaming update
--     answers pending with no read), then ForcedLodModel and GetPredictedLODLevel; ready when they read k + 1 and k
--     with nothing pending. The slicer's own 'stable resident LOD' (PreferredLOD against the render data's
--     CurrentFirstLOD/PendingFirstLOD) is not readable from Lua: these are its nearest reflected proxies [inferred].
--   - the prepared cut (SL.cut_prep, under 'slicer.cut.prep'): SL.cut's checks and cut-frame re-derivation, then in ONE
--     guarded call LOD k checked against GetNumLODs and #SourceModels, ForcedLodModel and GetPredictedLODLevel read
--     again (else refused before the slice: 'prep_forced_lost', 'prep_not_resident'), then lab_slice's cut job with the
--     handle (SlicePreparedSkeletalMeshComponentRuntime: Source, P, N, PreparedHandle, Options with LODIndex k,
--     OutResult; no debug report, no snapshot: Capture only feeds Restore) and LOD k's bit set and restored around it
--     when it read false. The slicer refuses natively a handle that expired or whose forced or resident LOD moved.
--   - Release (under 'slicer.release', not inherited: a stop must still undo a forced LOD) rebuilds the handle as a
--     fresh plain table. lab_slice's self flag is on around Prepare, the cut and Release, so lab_slice_watch's hooks of
--     them only count.
-- API: bind(h); view(asset) -> { n_src (#SourceModels | 'unread'), bits = { LOD0, LOD1, ... } (true | false |
--   'unread', at most LODS, bounded by #), n_legacy (#LODInfo | 'unread'), pending (bHasStreamingUpdatePending),
--   never_stream, force_resident (bForceMiplevelsToBeResident), err }; handle(out) -> the plain handle of a Prepare's
--   out table { a, b, c, d, lod, from ('in_place' | 'named') } | nil; zero(h) -> true for a plain handle whose ID
--   reads all zero (lab_slice exports it as SL.zero_handle).
-- What the mock cannot prove: whether UE4SS 1185 reads and writes a bitfield bool inside an array-of-structs element in
--   place, marshals the FGuid handle out and back, whether GetPredictedLODLevel tracks the slicer's stable resident LOD,
--   whether SlicePrepared on LOD 1 holds where the direct cut crashed, and whether any LOD of a cooked body keeps its CPU
--   copies.
local S = require('core.sched')
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')

local LD = { LODS = 8 }
local H = nil                                       -- lab_slice's helpers (LD.bind)

-- v when it is a boolean (false included), else 'unread'
local function flag(v) if type(v) == 'boolean' then return v end return 'unread' end
-- A ReturnValue: v when it is a boolean (false kept: 'x and v or nil' read a false return as nil), else nil
local function flag_or_nil(v) if type(v) == 'boolean' then return v end return nil end
-- A pcall'd ue.call's results (okp: pcall's, ok and ret: ue.call's) as a job's fields: { ok (it ran and returned),
-- ret (the ReturnValue, false kept: the explicit if, never 'and/or'), err (the raised or failed call's text) }
local function call_out(okp, ok, ret)
    local rv = nil
    if okp and ok then rv = flag_or_nil(ret) end
    return { ok = okp and ok == true, ret = rv, err = (not okp) and H.text(ok) or ((not ok) and H.text(ret) or nil) }
end
-- A guarded job's answer (lab_slice's answer: ok, why, d): its refusal or the guard's as it came, else the call's own
-- failure (d.err, or 'call_failed'). -> ok, why, d
local function done(ok, why, d)
    if not ok then return false, why, d end
    if not d.ok then return false, d.err or 'call_failed', d end
    return true, nil, d
end

function LD.view(asset)
    local out = {}
    local arr = ue.prop(asset, 'SourceModels')
    if arr == nil then
        out.n_src = 'unread'
    else
        local ok, n, bits = pcall(function()
            local k, b = #arr, {}
            for i = 1, math.min(k, LD.LODS) do              -- bounded by #: indexing past the end grows the array
                b[i] = flag(arr[i].bAllowCPUAccess)
            end
            return k, b
        end)
        if ok then
            out.n_src, out.bits = n, bits
        else
            ue.caught(n, 'slice', 'lod_view')
            out.n_src, out.err = 'unread', H.text(n)
        end
    end
    local legacy = ue.prop(asset, 'LODInfo')
    local okl, nl = false, nil
    if legacy ~= nil then okl, nl = pcall(function() return #legacy end) end
    out.n_legacy = okl and nl or 'unread'
    out.pending = flag(ue.prop(asset, 'bHasStreamingUpdatePending'))
    out.never_stream = flag(ue.prop(asset, 'NeverStream'))
    out.force_resident = flag(ue.prop(asset, 'bForceMiplevelsToBeResident'))
    return out
end

-- ---------- the bit around one call ----------
local function bit_get(arr, k)
    local ok, v = pcall(function() return arr[k + 1].bAllowCPUAccess end)
    if ok and type(v) == 'boolean' then return v end
    return nil
end
-- One counted write of LOD k's bit, read back: true when it now reads v
local function bit_put(arr, k, v)
    ue.count_write(1)
    local ok = pcall(function() arr[k + 1].bAllowCPUAccess = v end)
    return ok and bit_get(arr, k) == v
end
-- The component's SourceModels and the counts that bound k: arr, n_src, n_lods | nil, why
local function lods_of(c)
    local asset = H.skm_asset(c)
    if not asset then return nil, 'no_skeletal_mesh' end
    local arr = ue.prop(asset, 'SourceModels')
    local okn, ns = false, nil
    if arr ~= nil then okn, ns = pcall(function() return #arr end) end
    if not (okn and math.tointeger(ns)) then return nil, 'no_source_models' end
    local okl, nl = ue.call(c, 'GetNumLODs')
    return arr, ns, okl and math.tointeger(nl) or nil
end
-- fn(...) with SourceModels[k].bAllowCPUAccess true, the bit then written back as it read (fn raised or not). -> b
-- { lod, before, set (the write read back true), restored (the write-back read back) }, then pcall's results of fn
local function with_bit(arr, k, fn, ...)
    local b = { lod = k, before = bit_get(arr, k) }
    if b.before == nil then
        b.refused = 'bit_unread'
        return b, false, 'bit_unread'
    end
    -- LOD 0's bit is never written (0.2.0-beta release guard): a bit cooked false means its CPU copies were dropped at
    -- load, so a write cannot help, and the write itself never ran live
    if b.before == false and k == 0 then
        b.refused = 'lod0_bit_false'
        return b, false, 'lod0_bit_false'
    end
    if b.before == false then b.set = bit_put(arr, k, true) end
    local res = table.pack(pcall(fn, ...))
    if b.before == false then b.restored = bit_put(arr, k, false) end
    return b, table.unpack(res, 1, res.n)
end
-- The target's LOD k checked against GetNumLODs and #SourceModels: arr, counts | nil, refusal record
local function lod_target(c, k)
    local arr, ns, nl = lods_of(c)
    if not arr then return nil, { refused = ns } end
    if not nl or k < 0 or k >= nl or k >= ns then
        return nil, { refused = 'lod_range', n_src = ns, n_lods = nl or 'unread' }
    end
    return arr, { n_src = ns, n_lods = nl }
end

-- ---------- one rung: the preflight on LOD k with the bit set and restored ----------
local function rung_job(vp, vn, opts, k)
    local c, lib = H.recall('target'), ue.cdo(H.LIB)
    if not c then return { refused = 'target_gone' } end
    if not lib then return { refused = 'no_lib' } end
    local arr, n = lod_target(c, k)
    if not arr then return n end
    local rt = {}
    local t0 = H.clock()
    local b, okp, ok, ret = with_bit(arr, k, ue.call, lib, 'DebugSkeletalMeshSlicePreflight', c, vp, vn, opts, rt)
    if b.refused then return { refused = b.refused, bit = b } end
    local ms = H.r1((H.clock() - t0) * 1000)
    local r = call_out(okp, ok, ret)
    r.ms, r.bit, r.n_src, r.n_lods, r.report = ms, b, n.n_src, n.n_lods, ue.str(rt.OutReport) or ''
    return r
end
-- k 0: 'slicer.cpuflag'; 1-3: 'slicer.lodpre'. The same frame checks first ('slicer.read'), then the rung; the report
-- parsed as SL.preflight's. -> ok (the call ran and returned), why, data { ok, ret, ms, bit, n_src, n_lods, lines,
-- parsed fields (src_ok, extract_failed, pos, neg, mix, manual, cpu, ...), asset, pending }
local function preflight_lod(rec, name, P, N, cell, k)
    if math.type(k) ~= 'integer' then return false, 'bad_args' end
    local okp, wp = H.SL.plane_ok(P, N)
    if not okp then return false, wp end
    local opts = H.SL.options(nil, cell, k)
    local oko, wo = H.SL.check_options(opts, false)
    if not oko then return false, wo end
    local okr, wr, dr = H.prep(rec, name)
    if not okr then return false, wr, dr end
    local vp, vn = ue.vec(P.x, P.y, P.z), ue.vec(N.x, N.y, N.z)
    local r, err, det
    if k == 0 then r, err, det = H.run('slicer.cpuflag', rung_job, vp, vn, opts, k)
    else r, err, det = H.run('slicer.lodpre', rung_job, vp, vn, opts, k) end
    return H.pre_tail(r, err, det, dr)
end

-- ---------- Prepare and Release ----------
-- A handle struct as plain values: { a, b, c, d, lod } | nil (any field that reads no integer: unread)
local function handle_fields(h)
    if h == nil then return nil end
    local g, out = ue.prop(h, 'ID'), { lod = math.tointeger(ue.prop(h, 'LODIndex')) }
    if g == nil or not out.lod then return nil end
    for _, k in ipairs({ 'A', 'B', 'C', 'D' }) do
        local v = math.tointeger(ue.prop(g, k))
        if not v then return nil end
        out[k:lower()] = v
    end
    return out
end
-- The OutHandle of a Prepare's out table: filled in place (out.ID, out.LODIndex: 'in_place'), else nested under the
-- param's name ('named'); nil when neither reads
function LD.handle(out)
    if type(out) ~= 'table' then return nil end
    local h = handle_fields(out)
    if h then
        h.from = 'in_place'
        return h
    end
    h = handle_fields(rawget(out, 'OutHandle'))
    if h then h.from = 'named' end
    return h
end
-- A plain handle that reads all zero (Prepare's own zeroed OutHandle: nothing prepared); false for a non-table
function LD.zero(h) return type(h) == 'table' and h.a == 0 and h.b == 0 and h.c == 0 and h.d == 0 end
-- A plain handle sent back as a fresh FAkashaPreparedSkeletalMeshSliceHandle table (Release, SlicePrepared)
local function handle_arg(h) return { ID = { A = h.a, B = h.b, C = h.c, D = h.d }, LODIndex = h.lod } end
local function prepare_job(opts, life)
    local c, lib = H.recall('target'), ue.cdo(H.LIB)
    if not c then return { refused = 'target_gone' } end
    if not lib then return { refused = 'no_lib' } end
    local out, before = {}, ue.prop(c, 'ForcedLodModel')
    ue.count_write(1)                                   -- it forces the component's LOD
    H.self(true)
    local t0 = H.clock()
    local okp, ok, ret = pcall(ue.call, lib, 'PrepareSkeletalMeshSliceRuntime', c, opts, life, out)
    local ms = H.r1((H.clock() - t0) * 1000)
    H.self(false)
    local okh, h = pcall(LD.handle, out)
    local r = call_out(okp, ok, ret)
    r.ms, r.handle, r.forced_before, r.forced = ms, okh and h or nil, before, ue.prop(c, 'ForcedLodModel')
    return r
end
-- SL.prepare(rec, name, k, life): the same-frame checks ('slicer.read'), then Prepare on LOD k. -> ok, why, data { ok,
-- ret, ms, handle (plain, nil when unread), forced_before, forced (ForcedLodModel before and after), err, asset,
-- pending }
local function prepare(rec, name, k, life)
    if math.type(k) ~= 'integer' or type(life) ~= 'number' then return false, 'bad_args' end
    local opts = H.SL.options(nil, nil, k)
    local oko, wo = H.SL.check_options(opts, false)
    if not oko then return false, wo end
    local okr, wr, dr = H.prep(rec, name)
    if not okr then return false, wr, dr end
    local ok, why, d = H.answer(H.run('slicer.prepare', prepare_job, opts, life + 0.0))
    d = d or {}
    d.asset, d.pending = dr.asset, dr.pending
    return done(ok, why, d)
end
local function release_job(h)
    local lib = ue.cdo(H.LIB)
    if not lib then return { refused = 'no_lib' } end
    local arg = handle_arg(h)
    ue.count_write(1)                                   -- it gives the component its forced LOD back
    H.self(true)
    local okp, ok, ret = pcall(ue.call, lib, 'ReleasePreparedSkeletalMeshSlice', arg)
    H.self(false)
    return call_out(okp, ok, ret)
end
-- SL.release(h): h the plain handle SL.prepare answered. -> ok, why, data { ok, ret, err }
local function release(h)
    if type(h) ~= 'table' or not (math.tointeger(h.a) and math.tointeger(h.lod)) then return false, 'bad_args' end
    return done(H.answer(H.run('slicer.release', release_job, h)))
end

-- ---------- the wait for the prepared LOD (header) ----------
-- The component's forced and predicted LOD: { forced, predicted } (an integer or 'unread' each)
local function lod_now(c)
    local okp, p = ue.call(c, 'GetPredictedLODLevel')
    return math.tointeger(ue.prop(c, 'ForcedLodModel')) or 'unread', okp and math.tointeger(p) or 'unread'
end
local function read_job()
    local c = H.recall('target')
    if not c then return { refused = 'target_gone' } end
    local forced, predicted = lod_now(c)
    return { forced = forced, predicted = predicted }
end
-- SL.prep_read(rec, name, k): the same-frame checks ('slicer.read'; a pending or unread streaming flag answers ok with
-- { pending, ready = false } and no read), then ForcedLodModel and GetPredictedLODLevel ('slicer.prep.read'). -> ok,
-- why, data { pending, forced, predicted, ready (forced k + 1, predicted k, pending false) }
local function prep_read(rec, name, k)
    if math.type(k) ~= 'integer' then return false, 'bad_args' end
    local okr, wr, dr = H.prep(rec, name)
    if not okr then
        if wr == 'lod_streaming' then return true, nil, { pending = dr and dr.pending or 'unread', ready = false } end
        return false, wr, dr
    end
    local ok, why, d = H.answer(H.run('slicer.prep.read', read_job))
    if not ok then return false, why, d end
    d.pending = dr.pending
    d.ready = d.forced == k + 1 and d.predicted == k and d.pending == false
    return true, nil, d
end

-- ---------- the prepared cut (header) ----------
local function slice_prep_job(lib, body, vp, vn, opts, k, h)
    local arr, n = lod_target(body, k)
    if not arr then return n end
    local forced, predicted = lod_now(body)
    if forced ~= k + 1 then return { refused = 'prep_forced_lost', forced = forced, predicted = predicted } end
    if predicted ~= k then return { refused = 'prep_not_resident', forced = forced, predicted = predicted } end
    local b, okp, r = with_bit(arr, k, H.cut_job, lib, body, vp, vn, opts, {}, {}, nil, handle_arg(h))
    if b.refused then return { refused = b.refused, bit = b } end
    if not okp then error(r, 0) end                     -- the cut job raised: run() reports it as raised
    r.bit, r.n_src, r.n_lods, r.forced, r.predicted = b, n.n_src, n.n_lods, forced, predicted
    return r
end
local function good_handle(h, k)
    if type(h) ~= 'table' or h.lod ~= k then return false end
    for _, f in ipairs({ 'a', 'b', 'c', 'd' }) do if not math.tointeger(h[f]) then return false end end
    return not LD.zero(h)
end
-- SL.cut_prep(rec, P, N, choice, cell, key, k, h): the prepared slice of the victim rec's Character.Mesh on LOD k with
-- the handle h SL.prepare answered for LOD k: SL.cut's checks (mod-off, one slice a frame, the plane) and its cut-frame
-- re-derivation ('slicer.read'), then the call above ('slicer.cut.prep'). -> SL.cut's answer (ran, ok, ret, ms, pos,
-- neg, bit, forced, predicted; an empty report: the prepared form has none)
local function cut_prep(rec, P, N, choice, cell, key, k, h)
    if math.type(k) ~= 'integer' or not good_handle(h, k) then return false, 'bad_args' end
    if not MODOFF.enabled('lab_slice') then return false, 'modoff' end
    if H.SL.cut_frame() == S.frame then return false, 'cut_this_frame' end
    local okp, wp = H.SL.plane_ok(P, N)
    if not okp then return false, wp end
    local okr, wr, dr = H.answer(H.run('slicer.read', H.cut_read, rec, choice))
    if not okr then return false, wr, dr end
    local body, cap, lib = H.recall('body'), H.recall('cap'), H.recall('lib')
    if not (body and cap and lib) then return false, 'target_gone', dr end
    local vp, vn, opts = H.slice_args(P, N, cap, cell, k)
    if not vp then return false, vn, dr end
    local r, err, det = H.run('slicer.cut.prep', slice_prep_job, lib, body, vp, vn, opts, k, h)
    return H.slice_tail(r, err, det, dr, key)
end

-- h: lab_slice's helpers { SL, LIB, run, answer, prep (rec, name -> ok, why, data: the 'target' in the frame cache),
-- pre_tail (run's r, err, det, prep data -> SL.preflight's answer), recall, skm_asset, cut_job (its prepared form with
-- a handle), cut_read (the cut frame's re-derivation job), slice_args, slice_tail, self (on), clock, r1, text }. Adds
-- SL.preflight_lod, SL.prepare, SL.prep_read, SL.cut_prep, SL.release
function LD.bind(h)
    H = h
    h.SL.preflight_lod, h.SL.prepare, h.SL.release = preflight_lod, prepare, release
    h.SL.prep_read, h.SL.cut_prep = prep_read, cut_prep
end

return LD
