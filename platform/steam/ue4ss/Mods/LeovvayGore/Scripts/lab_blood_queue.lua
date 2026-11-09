-- status: new for the beta (offline only; the author's next run decides) origin: session 20261101-lag, the author
-- 2026-11-01 («every hit on an enemy causes micro-lags, this must be fixed urgently»)
-- lab_blood_queue.lua: lab_blood's hit-lag guard, a library lab_blood requires (main.lua's LIBS puts it in the code
-- hash); QL.bind(h) hands it lab_blood's helpers and state at lab_blood's init, so the state, the constants (lab_blood's
-- B), the breaker, the rings, the counters and the records stay lab_blood's.
-- Why (session 20261101-lag, the diagnoses in scratch/hitlag): every bleed resolved its decal materials through
-- ue.asset_peek, else an uncached StaticFindObject; three of the four (two of them brought in by LoadAsset at the
-- warm-up and held by nothing) had gone with a GC (very likely in an in-world loading screen: no LoadMap, no warm), so
-- every pool and every Soul splash paid 3 misses of about 23 ms (60-210 ms a hit, 24 blood_slow records), and the step
-- breaker let 12 warm-up calls through, then switched a step off for 30 s only after 5 slow calls of 8: in waves.
-- * Materials (texture): the asset cache only (ue.asset_peek), never a lookup. A cached object the GC took ('stale'), or
--   a path the cache does not hold, queues one reload (rewarm) on st.rewarmq when a bleed or a queued decal asks for
--   it, never on a timer (an idle stretch's GCs cost no load): ue.asset(path, true), LoadAsset alone (no
--   StaticFindObject), under 'blood.load', one a frame after lab_blood's warm queue (rewarm_step), at most B.REWARM_MAX
--   a path a map, none for a path the warm-up or the last reload could not load (st.missing); one blood_rewarm record
--   { asset, stale, ok, via, n, ms, err } each. texture_any (the test build's wound look on a sampler and lab_grey's
--   console tools) adds one lookup per path per map when the cache never held it.
-- * Holds (load): a reloaded material is held by nothing (adapter/ue.lua's ue.asset), and session 20261101-lag shows a
--   GC took the warm-up's within 4 min with no map load, so each GC would cost a burst of sync loads (34-85 ms frames).
--   The decal layers lab_blood draws (ADECAL_MATS 1 and 2; a later one only while neither of those can be had:
--   can_load) are held for the map on the player controller's keeper (ue.hold kind 'material', the route of lab_look,
--   lab_slice and lab_grey) in the same 'blood.load' call that loads them (the warm-up's step or a reload, as lab_slice
--   holds its cap material under 'slicer.load'): loaded once a map. A map load or a new keeper ends the holds (their
--   cache entries go: the next bleed reloads and holds again). One blood_hold record { asset, ok, why, held, reload }
--   per attempt; no PlayerController yet counts nothing, any other refusal counts in the 'blood.hold' breaker (a Lua
--   kind, no sentinel name of its own: FAIL_MAX in a row, no more holds on the map). MAI_Decal_DRA_Blood and the FX
--   decal are drawn only when the stain and the spatter cannot be had, so they are neither held nor reloaded before.
-- * The decal queue (push, drain): lab_blood's bleeds queue their decals (adecal on the victim's mesh or a slice's
--   Negative half, pool, Soul's splash) as plain jobs { kind, step, name, mat (a path), ... }; drain (lab_blood's ticker,
--   after the tick's bleeds) spawns them oldest first, at most B.DQ_PER_FRAME a frame and none once B.DQ_MS of the drain
--   went (one at least), each in its own guarded call under its old name ('blood.adecal' or 'slicer.blood',
--   'blood.pool', 'blood.player'). Dropped: a job older than B.DQ_STALE_S game seconds or of an older map
--   (blood_dq_stale), of a step that is off or a call kind its breaker stopped (blood_dq_off), or whose actor, mesh,
--   pawn or material went, or Blood on Soul went off, or Blood on Soul's face for a splash on a face bone
--   (blood_dq_gone); at most B.DQ_MAX wait (blood_dq_full). An attached
--   decal reads its bone again inside its own call (the body moved since the hit); a half is resolved only inside
--   'slicer.blood'. The rings, their caps and evictions, and Soul's seq and game time on each splash are lab_blood's.
--   A queued stain counts in its key's st.adecal_q until it spawns, drops or fails (unqueue; clear() drops the whole
--   queue for lab_blood's off gate the same way): a key with none left there or in the ring goes back to the game's
--   receive flag through lab_blood's stains_out (its header, the receive switch back, B4).
-- * The lag guard (step, judge, late, slow_check): every inline step of a bleed and every queued spawn is timed and
--   judged under its step name: one call of B.STEP_HARD_MS or more trips it ('ceiling'; in its first B.STEP_WARM calls
--   of the session only the second in a row: TC-BETA-01c's first bleeds cost 20-86 ms once), and so do B.STEP_SLOW_N
--   slow calls (B.STEP_SLOW_MS) of its last B.STEP_WIN past the warm-up ('window'); its k-th trip on a map switches it
--   off for B.STEP_OFF_ESC[k] s, past the list for the rest of the map (lab_blood's reset clears the switch-offs and
--   levels): one blood_step_off { step, ms, why, slow, level, off_s ('map'), call, call_ms } each. late(t0): a bleed
--   past B.BLEED_MS skips its pool and Soul steps (blood_skip_deadline).
-- * Timers (lap, begin): each native call kind of a bleed or a drain frame adds its ms to st.calls (read, fx.spawn,
--   recv, layers, adecal.spawn|keep|evict, pool.spawn|keep|evict, player.spawn|keep|evict); a bleed or a drain frame over
--   B.SLOW_MS writes one blood_slow (at most B.SLOW_LOG_MAX a session: kind 'hit', 'kill', 'cut', 'slice' or 'drain')
--   { ms, steps, calls, slowest, slowest_ms, finds, misses (ue.lookups deltas), queued }.
-- API: bind(h) lap(kind, t0) begin() texture(path[, peek]) texture_any(path) layer(path) can_load(path)
-- load(path[, reload]) rewarm(path, stale) rewarm_step() push(job) drain() clear() step(name, fn, ...) late(t0)
-- slow_check(kind, class, t0).
-- What the mock cannot prove: the real cost of a miss, a LoadAsset or a spawn on UE4SS 1185; when the engine's GC
-- runs; whether the keeper's slot keeps a decal material from the GC (the material route held materials in SWZC and
-- lab_look); the look of a decal spawned a few frames after its hit.
local C = require('core.config')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local QL = {}
local H = nil                                           -- lab_blood's helpers (QL.bind)

local function now() return H.now() end
local function gnow() return H.gnow() end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function short(path) return type(path) == 'string' and (path:match('([^/.]+)$') or path) or '?' end

-- ---------- the per-call timers: one bleed or one decal-queue frame ----------
-- A call of kind took the ms since t0: added to st.calls[kind], the dearest single call kept (blood_slow's slowest and
-- blood_step_off's call name the slow native call)
function QL.lap(kind, t0)
    local st = H.state()
    local ms = (now() - t0) * 1000
    st.calls[kind] = (st.calls[kind] or 0) + ms
    if ms > st.call_max_ms then st.call_max, st.call_max_ms = kind, ms end
    return ms
end
local lap = QL.lap
-- A bleed or a drain starts: its steps, calls and the lookup counters (ue.lookups: plain numbers, no engine call); the
-- last bleed's decal layers and Soul with his spot (lab_blood's adecal_layers and soul_at, read once a bleed) go
function QL.begin()
    local st = H.state()
    st.steps, st.calls, st.call_max, st.call_max_ms = {}, {}, nil, 0
    st.f0, st.m0 = ue.lookups()
    st.bleed_paths, st.bleed_names, st.bleed_soul = nil, nil, nil
end

-- ---------- materials: the asset cache only, the layers held for the map, a lost one reloaded off the hit path ----------
-- One reload of path queued: stale, a cached object the GC took; else a path the cache does not hold (a bleed before
-- the warm-up, a hot reload, a hold that ended with its keeper). Either way LoadAsset alone (ue.asset(path, true)): it
-- answers the object in memory or loads it, with no StaticFindObject. st.rewarm[path]: the reloads done on this map,
-- negative while one waits
function QL.rewarm(path, stale)
    local st = H.state()
    local n = st.rewarm[path] or 0
    if n < 0 or n >= H.B.REWARM_MAX then return end
    st.rewarm[path] = -(n + 1)
    st.rewarmq[#st.rewarmq + 1] = { path = path, stale = stale == true }
end
local rewarm = QL.rewarm
-- A path lab_blood may still have on this map: neither the warm-up nor the last reload refused it (st.missing), and
-- its reloads are not used up (one waiting counts)
function QL.can_load(path)
    local st = H.state()
    if st.missing[path] then return false end
    local n = st.rewarm[path] or 0
    return n < 0 or n < H.B.REWARM_MAX
end
-- A decal material or wound texture from the asset cache, never looked up (the hit path): the object, else nil. A
-- stale one or one the cache does not hold queues its reload, unless peek (adecal_layers' later materials while the
-- stain or the spatter can still be had) or the warm-up or the last reload could not load it (st.missing)
function QL.texture(path, peek)
    local o, _, why = ue.asset_peek(path)
    if o then return o end
    if not peek and not H.state().missing[path] then rewarm(path, why == 'stale') end
    return nil
end
local texture = QL.texture
-- The same, with one lookup per path per map when the cache has none (the test build's wound look on a sampler, once
-- per sampler, and lab_grey's console tools): a stale object is never looked up
function QL.texture_any(path)
    local o, _, why = ue.asset_peek(path)
    if o then return o end
    if why == 'stale' then rewarm(path, true) return nil end
    local st = H.state()
    if st.missing[path] then return nil end
    o = ue.find(path)
    if not o then st.missing[path] = true end
    return o
end
-- One of lab_blood's decal layers for another module's kill path (lab_blood's B.layer: lab_cap's wound ring, lab_drops'
-- stains): QL.texture's rule, the cache only and never a lookup, a missing or stale layer reloaded off that path
-- (review: a map load deletes the held layers' cache entries, and their lookups missed in a kill frame). nil, 'inert'
-- while lab_blood does not run (the caller then reads the cache itself)
function QL.layer(path)
    local st = H and H.state()
    if not (st and st.init) or st.ended then return nil, 'inert' end
    return texture(path)
end
-- The index of path in ADECAL_MATS, else nil
local function layer_of(path)
    for i, p in ipairs(H.B.ADECAL_MATS) do if p == path then return i end end
    return nil
end
-- A held layer of this map: st.held[path] { id, ep }
local function held(path)
    local h = H.state().held[path]
    return h ~= nil and h.ep == ue.epoch
end
-- The decal layers lab_blood draws are held (header, Holds): ADECAL_MATS 1 and 2; a later one only while neither of
-- those can be had, and only the first such (adecal_layers draws the first later one the cache has). Not once held on
-- this map, nor once the 'blood.hold' breaker tripped
local function hold_wanted(path)
    local M = H.B.ADECAL_MATS
    local i = layer_of(path)
    if not i or held(path) or H.stopped('blood.hold') then return false end
    if i <= 2 then return true end
    if QL.can_load(M[1]) or QL.can_load(M[2]) then return false end
    for k = 3, i - 1 do if held(M[k]) then return false end end
    return true
end
-- One guarded call under 'blood.load' (lab_blood's warm-up step or a reload, one a frame): the asset through ue.asset
-- (reload: LoadAsset alone), then, for a layer to hold (hold_wanted), ue.hold(the player controller, it, 'material')
-- in the same call (header, Holds). -> obj | nil, via, err
function QL.load(path, reload)
    local st = H.state()
    local want = hold_wanted(path)
    local r, err = LAB.hot('blood.load', function()
        local o, via = ue.asset(path, reload)
        local out = { o = o, via = via }
        if o and want then
            local id, why, add = ue.hold(ue.first_of('PlayerController'), o, 'material')
            out.id, out.why, out.add = id, why, add
        end
        return out
    end)
    if type(r) ~= 'table' then return nil, nil, err end
    if r.o and want then
        local why = r.id == nil and (tostring(r.why) .. (r.add ~= nil and (' ' .. tostring(r.add)) or '')) or nil
        if r.id then
            st.held[path] = { id = r.id, ep = ue.epoch }
            H.worked('blood.hold')
            LAB.count('blood_hold')
        else
            LAB.count('blood_hold_fail')
            -- no PlayerController yet (a load screen): no breaker count, the next reload tries again
            if not (r.why == 'no_host' and r.add == 'no_actor') then H.failed('blood.hold', why) end
        end
        local n = 0
        for p in pairs(st.held) do if held(p) then n = n + 1 end end
        LAB.rec('blood_hold', { asset = short(path), ok = r.id ~= nil, why = why, held = n, reload = reload == true },
            true)
    end
    return r.o, r.via, err
end
-- One queued reload (lab_blood's ticker, after the warm queue, one load a frame) under 'blood.load', its hold with it:
-- one blood_rewarm. A reload means the path's hold (if any) ended; a failed one keeps the path missing for the map
function QL.rewarm_step()
    local st = H.state()
    local j = table.remove(st.rewarmq, 1)
    if not j then return end
    local t0 = now()
    st.held[j.path] = nil
    local o, via, err = QL.load(j.path, true)
    local n = -(st.rewarm[j.path] or -1)
    st.rewarm[j.path] = n
    st.missing[j.path] = (o == nil) or nil
    LAB.count('blood_rewarm')
    LAB.rec('blood_rewarm', { asset = short(j.path), stale = j.stale, ok = o ~= nil, via = via, n = n,
        ms = r1((now() - t0) * 1000), err = err and tostring(err):sub(1, 160) or nil }, true)
end

-- ---------- the decal queue: a bleed queues its decals, the drain spawns them over the next frames ----------
function QL.push(job)
    local st = H.state()
    if #st.dq >= H.B.DQ_MAX then LAB.count('blood_dq_full') return false end
    job.t, job.ep = gnow(), ue.epoch                    -- game time: a pause (no drain runs) ages no job (review)
    st.dq[#st.dq + 1] = job
    return true
end
-- Each job answers true when it made a spawn call (the frame's DQ_PER_FRAME counts those); the calls are timed by kind
-- (<step>.spawn, <step>.keep, <step>.evict: the next blood_slow names the slow one). memo: the drain's reads, each made
-- once a drain (nothing is collected between two jobs of one frame): an actor's liveness by its keep record (a
-- bleed's decals share one), a material by path, the GameplayStatics CDO, Soul's mesh and its address
local function alive_of(memo, rec)
    if rec == nil then return false end                 -- LAB.alive(nil): nil, with no engine call
    local a = memo.alive[rec]
    if a == nil then a = LAB.alive(rec) ~= nil memo.alive[rec] = a end
    return a
end
local function mat_of(memo, path)
    local o = memo.mat[path]
    if o == nil then o = texture(path) or false memo.mat[path] = o end
    return o or nil
end
local function gs_of(memo)
    if memo.gs == nil then memo.gs = ue.cdo('gs') or false end
    return memo.gs or nil
end
-- Soul's mesh while valid, and its address (job_player compares it with the bleed's)
local function soul_mesh(memo, st)
    if memo.mesh == nil then
        local pawn = st.pawn and ue.live(st.pawn) or nil
        local mesh = pawn and ue.get(pawn, 'Mesh') or nil
        memo.mesh = ue.valid(mesh) and mesh or false
        memo.addr = memo.mesh and ue.addr(mesh) or nil
    end
    return memo.mesh or nil, memo.addr
end
-- Inside the job's own guard: one decal of mat, half-size h, attached to bone of mesh at the world spot loc (location
-- type 1 KeepWorldPosition, no LifeSpan), with no screen-size fade (the engine's 0.01 fades small decals at distance):
-- the component, else nil
local function attached_decal(gs, mat, h, mesh, bone, loc, rot)
    ue.count_write()
    -- lint:allow L016 the lab's own gate (bleeding classes' hits, kills and cuts, their blood on the attacker; mod-off); the release port goes through fx_gate
    local d = ue.p(gs:SpawnDecalAttached(mat, ue.vec(H.B.ADECAL_DEPTH, h, h), mesh, ue.fname(bone), loc, rot, 1, 0.0))
    if not ue.valid(d) then return nil end
    pcall(function() d:SetFadeScreenSize(0.0) end)
    return d
end
-- A spawn's record rec, kept since t0, joins ring (<kind>.keep); past max the ring's oldest goes through lab_blood's
-- evict (<kind>.evict: a half's decal under 'slicer.blood'; Soul's splashes and the pools carry no .half)
local function keep_ring(ring, rec, max, kind, t0)
    ring[#ring + 1] = rec
    lap(kind .. '.keep', t0)
    if #ring > max then
        t0 = now()
        H.evict(table.remove(ring, 1))
        lap(kind .. '.evict', t0)
    end
end
-- A queued attached decal leaves the queue (spawned, dropped, gone, failed): its key's queued count (lab_blood's
-- st.adecal_q, charged by its adecal with ADECALS_ACTOR's). A job of an older map: lab_blood's reset cleared the counts
-- already. true when counted off
local function unqueue(j)
    if j.kind ~= 'adecal' or not j.akey or j.ep ~= ue.epoch then return false end
    local q = H.state().adecal_q
    local n = (q[j.akey] or 0) - 1
    q[j.akey] = n > 0 and n or nil
    return true
end
-- A queued attached decal that never spawned (dropped, gone, failed) gives its victim's ADECALS_ACTOR slot back (j.akey:
-- the key lab_blood's adecal charged when it queued the job; review: dropped jobs used up the victim's cap); with no
-- stain of the key left, in the ring or queued, its parts go back (lab_blood's stains_out, B4: a body switched on whose
-- stains never spawned)
local function refund(j)
    if not unqueue(j) then return end
    local n = H.state().adecal_n
    if (n[j.akey] or 0) > 0 then n[j.akey] = n[j.akey] - 1 end
    H.stains_out(j.akey)
end
-- The whole queue dropped (lab_blood's gate: mod-off or Blood effects off): each queued stain off its key's count, the
-- key settled as at a drop (stains_out); the ADECALS_ACTOR slots stay charged, as before
function QL.clear()
    local st = H.state()
    local dq = st.dq
    st.dq = {}
    for _, j in ipairs(dq) do if unqueue(j) then H.stains_out(j.akey) end end
end
-- A bone read inside a job's own guard: its point, else nil (a raised text goes to ue.caught first, so lab_probe's
-- ArrayNum stop rule sees it: review)
local function bone_at(m, bone)
    local okb, bp = pcall(function() return H.xyz(m:GetSocketLocation(ue.fname(bone))) end)
    if not okb then ue.caught(bp, 'blood', 'GetSocketLocation') return nil end
    return bp
end
-- An attached decal on the victim's mesh or a slice's half: the actor still alive, the material still cached; the
-- mesh resolved and the bone read again inside the call's own guard (a half only inside 'slicer.blood', and only by
-- its full name: a half's twin that took its address after a GC, valid with the same short name, is 'gone')
local function job_adecal(j, memo)
    local st = H.state()
    if not alive_of(memo, j.actor) then LAB.count('blood_dq_gone') refund(j) return false end
    local mat, gs = mat_of(memo, j.mat), gs_of(memo)
    if not (mat and gs) then LAB.count('blood_dq_gone') refund(j) return false end
    local function spawn()
        local m
        if j.half then m = ue.live_mod(j.mesh) else m = ue.live(j.mesh) end
        if not m then return 'gone' end
        local bp = bone_at(m, j.bone) or j.pos
        return attached_decal(gs, mat, j.h, m, j.bone, ue.vec(bp.x + j.off.x, bp.y + j.off.y, bp.z + j.off.z), j.r)
    end
    local t0 = now()
    local c, err
    if j.half then c, err = LAB.hot('slicer.blood', spawn) else c, err = LAB.hot('blood.adecal', spawn) end
    lap('adecal.spawn', t0)
    if c == 'gone' then LAB.count('blood_dq_gone') refund(j) return false end
    if not c then
        LAB.count('blood_adecal_fail')
        H.failed(j.name, err or 'no_component')
        refund(j)
        return true
    end
    H.worked(j.name)
    LAB.count('blood_adecals')
    t0 = now()
    unqueue(j)                                          -- from queued to the ring: the count below, before any evict
    local rec = ue.keep_mod(c)
    if rec and j.half then rec.half = true end
    if rec and j.akey then                              -- its key's stain count: the last one evicted switches back
        rec.akey = j.akey
        st.adecal_live[j.akey] = (st.adecal_live[j.akey] or 0) + 1
    end
    keep_ring(st.adecal_ring, rec, st.k.ADECALS_MAX, 'adecal', t0)
    return true
end
-- A splash on Soul: the same pawn and mesh as at the bleed, Blood on Soul still on (and Blood on Soul's face for one
-- on a face bone: j.face), the material still cached; the bone read again inside 'blood.player'. The ring entry
-- carries the face flag (lab_blood's face wash)
local function job_player(j, memo)
    local st = H.state()
    if C.knob('soul_blood') == false or (j.face and C.knob('soul_face_blood') == false) then
        LAB.count('blood_dq_gone')
        return false
    end
    local mesh, addr = soul_mesh(memo, st)
    if not (mesh and addr == j.mesh) then LAB.count('blood_dq_gone') return false end
    local mat, gs = mat_of(memo, j.mat), gs_of(memo)
    if not (mat and gs) then LAB.count('blood_dq_gone') return false end
    local t0 = now()
    local c, err = LAB.hot('blood.player', function()
        local bp = bone_at(mesh, j.bone) or j.pos
        return attached_decal(gs, mat, j.h, mesh, j.bone, ue.vec(bp.x, bp.y, bp.z), j.r)
    end)
    lap('player.spawn', t0)
    if not c then
        H.failed('blood.player', err or 'no_component')
        return true
    end
    H.worked('blood.player')
    t0 = now()
    local rec = ue.keep_mod(c)
    if rec then                                         -- its seq and game time: the life and the heal fade (lab_blood)
        st.pseq = st.pseq + 1
        rec.seq, rec.t, rec.face = st.pseq, gnow(), j.face
    end
    keep_ring(st.pring, rec, st.k.PLAYER_MAX * 2, 'player', t0)
    return true
end
-- A pool (SpawnDecalAtLocation through ue.spawn_decal: owned by WorldSettings, LifeSpan POOL_LIFE_S, no screen-size
-- fade); the oldest goes past POOLS_MAX
local function job_pool(j, memo)
    local st, B = H.state(), H.B
    local mat = mat_of(memo, j.mat)
    if not mat then LAB.count('blood_dq_gone') return false end
    local t0 = now()
    local d, err = LAB.hot('blood.pool', function()
        -- lint:allow L016 the lab's own gate (kills and cuts of bleeding classes, mod-off); the release port goes through fx_gate
        return (ue.spawn_decal(mat, ue.vec(B.POOL_DEPTH, j.s, j.s), ue.vec(j.pos.x, j.pos.y, j.pos.z),
            ue.rot(-90, 0, j.yaw), { life = B.POOL_LIFE_S, fade_screen = 0 }))
    end)
    lap('pool.spawn', t0)
    if not d then
        H.failed('blood.pool', err or 'no_component')
        return true
    end
    H.worked('blood.pool')
    LAB.count('blood_pools')
    t0 = now()
    keep_ring(st.pools, ue.keep_mod(d), st.k.POOLS_MAX, 'pool', t0)
    return true
end
local JOBS = { adecal = job_adecal, player = job_player, pool = job_pool }

-- ---------- the lag guard ----------
-- The verdict on one call of a step (an inline step of a bleed, or one queued spawn of it), ms long (header): a call of
-- STEP_HARD_MS or more trips it ('ceiling'; in its first STEP_WARM calls of the session only the second in a row), and
-- so do STEP_SLOW_N slow calls of its last STEP_WIN past the warm-up ('window'). The k-th trip on a map switches the
-- step off for STEP_OFF_ESC[k] s, past the list for the rest of the map; one blood_step_off record each, naming the
-- dearest single call of the bleed or drain (st.call_max)
local function step_on(st, name) return (st.step_off[name] or 0) <= now() end
local function trip(name, ms, why, slow)
    local st, B = H.state(), H.B
    local lvl = (st.step_lvl[name] or 0) + 1
    local off_s = B.STEP_OFF_ESC[lvl]                   -- nil past the list: the rest of the map
    st.step_lvl[name] = lvl
    st.step_off[name] = off_s and (now() + off_s) or math.huge
    st.step_slow[name], st.step_hard[name] = nil, 0     -- the window starts empty again
    LAB.count('blood_step_off')
    LAB.rec('blood_step_off', { step = name, ms = math.floor(ms + 0.5), why = why, slow = slow, level = lvl,
        off_s = off_s or 'map', call = st.call_max, call_ms = r1(st.call_max_ms) }, true)
end
-- The window: st.step_slow[name], a ring of STEP_WIN slots (true: a slow call) written at slot i (the newest), and
-- slow, how many of its slots hold true
local function judge(st, name, ms)
    local B = H.B
    local n = (st.step_calls[name] or 0) + 1
    st.step_calls[name] = n
    local warm = n <= B.STEP_WARM
    if ms >= B.STEP_HARD_MS then
        local k = (st.step_hard[name] or 0) + 1
        st.step_hard[name] = k
        if not warm or k >= 2 then trip(name, ms, 'ceiling') return end
    else
        st.step_hard[name] = 0
    end
    if warm then return end
    local h = st.step_slow[name]
    if not h then h = { i = 0, slow = 0 } st.step_slow[name] = h end
    local i, v = h.i % B.STEP_WIN + 1, ms >= B.STEP_SLOW_MS
    if h[i] then h.slow = h.slow - 1 end                -- a full window's oldest call leaves it
    if v then h.slow = h.slow + 1 end
    h[i], h.i = v, i
    if h.slow >= B.STEP_SLOW_N then trip(name, ms, 'window', h.slow) end
end
-- One timed call of a step (an inline step of a bleed, or one queued spawn of it): its ms add to st.steps and the lag
-- guard judges it
local function account(st, name, ms)
    st.steps[name] = (st.steps[name] or 0) + ms
    judge(st, name, ms)
end
-- One step of a bleed, timed (account); an off step returns nil
function QL.step(name, fn, ...)
    local st = H.state()
    if not step_on(st, name) then return nil end
    local t0 = now()
    local r = fn(...)
    account(st, name, (now() - t0) * 1000)
    return r
end
-- A bleed past BLEED_MS since t0: its pool and Soul steps are skipped
function QL.late(t0)
    if (now() - t0) * 1000 <= H.B.BLEED_MS then return false end
    LAB.count('blood_skip_deadline')
    return true
end
-- A bleed or a drain frame over SLOW_MS: one blood_slow record (at most SLOW_LOG_MAX a session) with its steps' ms,
-- its calls' ms by kind, the dearest single call, and the StaticFindObject lookups and misses it made (ue.lookups)
function QL.slow_check(kind, class, t0)
    local st, B = H.state(), H.B
    local ms = (now() - t0) * 1000
    if ms < B.SLOW_MS then return end
    LAB.count('blood_slow')
    if st.slow_n >= B.SLOW_LOG_MAX then return end
    st.slow_n = st.slow_n + 1
    local parts, calls = {}, {}
    for k, v in pairs(st.steps) do parts[k] = r1(v) end
    for k, v in pairs(st.calls) do calls[k] = r1(v) end
    local f1, m1 = ue.lookups()
    LAB.rec('blood_slow', { kind = kind, class = class, ms = math.floor(ms + 0.5), steps = parts, calls = calls,
        slowest = st.call_max, slowest_ms = st.call_max and r1(st.call_max_ms) or nil, finds = f1 - (st.f0 or f1),
        misses = m1 - (st.m0 or m1), queued = #st.dq }, true)
end
-- The decal queue's frame (lab_blood's ticker, after the bleeds): oldest first, at most DQ_PER_FRAME spawns and none
-- once DQ_MS went (one at least); a stale job, one of a step that is off, or one whose call kind's breaker stopped it is
-- dropped. Each spawn's time goes to the lag guard under its step (account); the jobs share one memo of reads
function QL.drain()
    local st, B = H.state(), H.B
    if not st.dq[1] then return end
    local f0 = now()
    QL.begin()
    local n, first, memo = 0, true, { alive = {}, mat = {} }
    while st.dq[1] and n < B.DQ_PER_FRAME and (first or (now() - f0) * 1000 < B.DQ_MS) do
        first = false
        local j = table.remove(st.dq, 1)
        if j.ep ~= ue.epoch or gnow() - j.t > B.DQ_STALE_S then LAB.count('blood_dq_stale') refund(j)
        elseif not step_on(st, j.step) or H.stopped(j.name) then LAB.count('blood_dq_off') refund(j)
        else
            local t0 = now()
            if JOBS[j.kind](j, memo) then
                n = n + 1
                account(st, j.step, (now() - t0) * 1000)
            end
        end
    end
    QL.slow_check('drain', nil, f0)
end

-- lab_blood's init: its helpers (B, state(), now, gnow, xyz, failed, worked, stopped, evict, stains_out); nil unbinds
function QL.bind(h) H = type(h) == 'table' and h or nil end
return QL
