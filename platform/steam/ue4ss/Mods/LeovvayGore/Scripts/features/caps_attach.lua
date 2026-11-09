-- status: worked DD2 origin: kb:stumps-caps#p14
-- (worked: follow mode, stand-in and same-frame swap; untested: the partial parent turn, keep/clear rules)
-- also: kb:stumps-caps#resource-loading-rebuild-proximity-preload-stand-in-and-same-frame-swap
-- caps_attach.lua: manifest-driven Stump Caps. A cut queues a request; the late-phase job spawns the FITTED Cap from
-- the manifest as soon as its resource is ready. Not ready within fit_wait 12 frames: the ORGANIC stand-in (a nub
-- with relief; a flat disc only for bone, rock and metal bodies: house rule, the author called flat caps 'a crappy
-- puck') shows, and the fitted Cap replaces it in the SAME call once ready: never a frame with no Cap or
-- with two. Each cap_attach record says which level showed (fitted, nub, disc) and how long it waited. A fitted
-- resource never fails for good: past fit_missing (600 frames) the request is logged once as 'fitted_missing' and
-- re-checked every fit_retry (120) frames, so the fitted Cap still swaps in the frame it turns ready (the author
-- refuses a permanent generic stand-in on a flesh cut). The adapter's cap_ready rebuilds a stuck holder itself.
-- Both sides: CA.attach_piece(v, cut, piece) (or the bus event 'piece_live') gives the Piece end its own Cap in the
-- Piece's go-live frame (piece_fit_wait 0: the stand-in shows at once, the fitted Cap swaps in later); it follows
-- the Piece (A.joint_world(piece, joint)); CA.remove_piece(v, part) or 'piece_gone' removes it. Call
-- CA.wake(piece_or_victim, rescale) after a kick and in the Piece's fade step, so a sleeping Cap neither lags
-- (DD2: 14 frames behind a kicked Piece) nor pops at full size while the Piece shrinks.
-- Placement: the manifest row's mode, else caps.mode ('parent', the UE default); caps.mode 'follow' is the config
--   switch that makes every Cap follow (spec M0 S1.7 and section 6). A stand-in takes its request's row mode (no row:
--   caps.mode), so its fitted swap places alike.
--   parent (UE default): A.cap_parent(h, v, joint, lpos, lrot) once in the spawn call, zero Lua per frame (SWZC: attach
--     to the never-hidden stump bone with SnapToTarget, scale KeepWorld, then the manifest's local pose relative to
--     the bone). A missing A.cap_parent, a raise, a false or a sentinel refusal turns the Cap to follow in that same
--     call, so the render phase of the same frame poses it: never an unposed Cap (PLAN P16, R2-B17). Every attach is
--     attributed ('caps.parent.first_attach'): armed until one attach proved itself this session, then each later
--     attach runs while the name lingers in armed.json (one write per burst; never a bare pcall, refuted.md:116).
--   follow (the fallback): each render frame pose = anchor world pose x manifest local pose, with a partial parent
--     turn: d = conj(q_anchor) q_parent conj(q_bind), dw = slerp(1, d, w x follow_parent), offset t + dw (lpos - t),
--     rotation dw lrot; w = 0 is the rigid anchor. An anchor that stays within 2 mm (V.m: engine units) and turns
--     neither itself nor its followed parent since the last pose write needs no write; 60 such frames put the Cap to
--     sleep, looked at every 15th frame; CA.wake(v) after a kick or a corpse hit.
-- Keep and clear (bus): whole(v, 'pieces') keeps the torso Stumps, whole(v, 'shards' | 'burst') clears them;
--   split_live(v) clears (never the kill frame's split event, so an aborted split keeps its Stumps); restore(v)
--   (revive) and victim_gone(v) destroy that victim's Caps.
-- Lifetime (DESIGN C4, C5; spec M0 D17): a Cap lives as long as the surface it closes and goes only with its unit (the
--   kept corpse: restore, victim_gone, whole, split_live; the Piece: piece_gone). Cap slots = limits.kept x
--   limits.parts_per_victim x 2 + limits.pieces (CA.slots(); no limit of its own). Full slots evict no live Cap: the
--   bus gets keep_evict_oldest(v, { id, part, caps, slots }) (the keep module drops its oldest whole victim, never v)
--   and the new Cap is refused with 'limit', so its staged hide never commits and the kill demotes.
--   A closed gate (caps.enabled, effects.caps, mod-off, Shift+F7) stops new work only: a request with no Cap yet
--   drops, a fitted swap waits for the gate, every shown Cap stays and keeps its pose upkeep. Mod-off hides only the
--   Piece-end Caps, with their Pieces (MO live()); a Stump Cap is never hidden or destroyed while its Stump shows.
-- The first spawn of each kind runs under the crash sentinel ('caps.<kind>.first_spawn', arm-once).
-- ADAPTER CONTRACT:
--   A.cap_fitted(v, cut, side) -> entry | nil   the manifest row for side 'stump' (nil) or 'piece':
--                                          { anchor, lpos, lrot, follow = { joint, w, t, bind }, mode = 'follow' | 'parent' }
--   A.cap_ready(entry) -> bool            its mesh and material resources report ready (DD2: a holder not ready after
--                                          90 frames is rebuilt fresh; never a permanent failed flag)
--   A.cap_spawn(v, cut, entry, kind, side, piece) -> handle   kind 'fitted' | 'nub' | 'disc' (entry nil: a stand-in);
--                                          the spawner also makes the mesh refuse world and effect decals
--   A.cap_pose(h, { p, q })  A.cap_destroy(h)  A.joint_world(v_or_piece, joint) -> { p = {x,y,z}, q = {w,x,y,z} }
--   A.cap_parent(h, v, joint, lpos, lrot)? -> true   parent mode only; false or a raise: the Cap follows
--                                          (UE: ue.cap_parent; wired into MAIN.A by the M1 glue, gated by G-CAP)
--   A.valid(v)? -> bool
--   A.cap_scale(h, s)?                    uniform rescale (a fading Piece's Cap shrinks with it)
-- CA.live(v, cut) is the 'cap' replacement provider hide.lua waits for (A.replacement.cap = CA.live).
-- kb:stumps-caps#p2 (both sides get a Cap)
-- Evidence: [worked DD2] caps.lua DEF 182-284 (cap_fit_wait/cap_fit_swap), PLACE.follow/turn 1348-1400, swap
-- 1932-1950; [worked SWZC] lib/gore.lua meat_cap 544-581; [untested] partial follow (claims A11) and keep/clear
-- (DD2 test_caps section 7 only)
-- kb:stumps-caps#runtime-cap-spawn-and-attach-follow-by-default-parent-optional
-- kb:stumps-caps#anchor-choice-and-partial-parent-follow kb:stumps-caps#body-level-events-cap-keep-and-clear-rules
-- kb:author-preferences#p38
local NAME0 = (...) or 'features.caps_attach'
local PFX, SEP = NAME0:match('^(.-)features([./])[^./]*$')
if not PFX then PFX, SEP = '', '.' end
local LOG = require(PFX .. 'core' .. SEP .. 'log')
local S = require(PFX .. 'core' .. SEP .. 'sched')
local BUS = require(PFX .. 'core' .. SEP .. 'bus')
local C = require(PFX .. 'core' .. SEP .. 'config')
local MO = require(PFX .. 'core' .. SEP .. 'modoff')
local SENT = require(PFX .. 'core' .. SEP .. 'sentinel')
local V = require(PFX .. 'core' .. SEP .. 'vmath')

local CA = { name = 'caps_attach' }
CA.DISC_KINDS = { bone = true, rock = true, metal = true }
CA.DEFAULTS = {
    enabled = true,          -- ships on
    fit_wait = 12,           -- frames a cut waits for its fitted Cap before the organic stand-in shows
    fit_missing = 600,       -- frames after which a missing fitted resource is logged once and polled slowly
    fit_retry = 120,         -- past fit_missing, re-check the fitted resource every this many frames (never give up)
    piece_fit_wait = 0,      -- a Piece end goes live with its Piece: the stand-in shows at once
    follow_parent = 1.0,     -- multiplies the manifest's follow weight w; 0 = the rigid anchor
    spawn_per_frame = 8,     -- spawns per late phase (Cap slots come from the unit budgets: CA.slots)
    sleep_frames = 60,       -- a follow Cap whose anchor moved under sleep_eps for this many frames sleeps
    sleep_eps = 0.002,       -- metres
    sleep_check = 15,        -- a sleeping Cap is looked at every 15th frame
    mode = 'parent',         -- UE default for a row without a mode; 'follow' is the config switch (M0 spec section 6)
}
CA.MODES = { parent = true, follow = true }
local opt = C.section_opt('caps', CA.DEFAULTS, nil, { mode = CA.MODES })
CA.opt = opt

local A = nil
local function fresh()
    return { pending = {}, caps = {}, proven = {}, spawned = 0, swaps = 0, standins = 0, evicted = 0, refused = 0,
        parent_fallbacks = 0 }
end
local st = fresh()
local ID = { w = 1, x = 0, y = 0, z = 0 }

-- slerp from the identity to q by t (shortest arc)
local function slerp_id(q, t)
    if q.w < 0 then q = { w = -q.w, x = -q.x, y = -q.y, z = -q.z } end
    local c = math.max(-1, math.min(1, q.w))
    local ang = math.acos(c)
    local s = math.sin(ang)
    if s < 1e-6 then return V.quat_norm({ w = 1 + (q.w - 1) * t, x = q.x * t, y = q.y * t, z = q.z * t }) end
    local a, b = math.sin((1 - t) * ang) / s, math.sin(t * ang) / s
    return { w = a + b * q.w, x = b * q.x, y = b * q.y, z = b * q.z }
end
CA.slerp_id = slerp_id

-- The Cap's world pose from its anchor (and followed parent) world poses: pure, the offline tests call it
function CA.place(rec, anchor, parent)
    local lpos, lrot = rec.lpos or V.new(), rec.lrot or ID
    local f = rec.follow
    local w = f and (tonumber(f.w) or 0) * opt('follow_parent') or 0
    if w > 0 and parent then
        local d = V.quat_norm(V.quat_mul(V.quat_mul(V.quat_conj(anchor.q), parent.q), V.quat_conj(f.bind or ID)))
        local dw = slerp_id(d, math.min(1, w))
        local t = f.t or V.new()
        lpos = V.add(t, V.rotate(dw, V.sub(lpos, t)))
        lrot = V.quat_mul(dw, lrot)
    end
    return { p = V.add(anchor.p, V.rotate(anchor.q, lpos)), q = V.quat_norm(V.quat_mul(anchor.q, lrot)) }
end

local function key(id, part, side)
    return tostring(id) .. '|' .. tostring(part) .. (side == 'piece' and '|p' or '')
end
function CA.live(v, cut)
    local r = st.caps[key(v.id, cut.part)]
    return r ~= nil and r.h ~= nil
end
function CA.live_piece(v, cut)
    local r = st.caps[key(v.id, cut.part, 'piece')]
    return r ~= nil and r.h ~= nil
end
function CA.count()
    local n = 0
    for _ in pairs(st.caps) do n = n + 1 end
    return n
end

local function fail(v, part, why)
    LOG.warn('cap_fail', { id = v and v.id, part = part, why = why })
    return nil, why
end

local function destroy(rec, why)
    if rec.h and A.cap_destroy then
        local ok, err = pcall(A.cap_destroy, rec.h)
        if not ok then LOG.warn('cap_fail', { id = rec.id, part = rec.part, why = 'destroy:' .. tostring(err) }) end
    end
    rec.h = nil
    st.caps[rec.k or key(rec.id, rec.part)] = nil
    if why then LOG.debug('cap_clear', { id = rec.id, part = rec.part, why = why }) end
end

-- Cap slots from the unit budgets (DESIGN C4): kept corpses x Parts x 2 sides, plus the live Pieces. A bad or missing
-- limits value reads as its DEFAULTS value
local function lim(t, k)
    local x = type(t) == 'table' and tonumber(t[k]) or nil
    if x and x >= 0 then return x end
    return tonumber(C.DEFAULTS.limits[k]) or 0
end
function CA.slots()
    local ok, s = pcall(C.get)
    local l = ok and type(s) == 'table' and s.limits or nil
    return lim(l, 'kept') * lim(l, 'parts_per_victim') * 2 + lim(l, 'pieces')
end

-- Full slots never evict a drawn Cap: the keep module is asked to drop its oldest whole victim (never v) and this Cap
-- is refused with 'limit', so the cut demotes and no Stump opens (DESIGN C4). Inside job() the ask waits until the
-- queue is settled (st.asks): a keep listener that drops a victim at once (victim_gone -> clear_v) edits st.pending,
-- and job() would write its own copy back over that edit, so the gone victim's request would spawn on a dead handle
local function make_room(v, part)
    local n, slots = CA.count(), CA.slots()
    if n < slots then return true end
    st.refused = st.refused + 1
    local info = { id = v.id, part = part, caps = n, slots = slots }
    if st.asks then st.asks[#st.asks + 1] = { v = v, info = info } return false end
    BUS.emit('keep_evict_oldest', v, info)
    return false
end

-- The placement mode: caps.mode 'follow' (the config switch) makes every Cap follow; else the manifest row's own mode,
-- else caps.mode ('parent' on UE). A stand-in passes its request's row (req.entry: false when there is none), so it
-- takes that row's mode
local function mode_of(row)
    local d = opt('mode')
    if d == 'follow' then return d end
    local m = type(row) == 'table' and row.mode or nil
    if CA.MODES[m] then return m end
    return d
end
CA.mode_of = mode_of

-- Parent mode: one attach with the manifest's local pose, onto the bone of what the Cap closes (the Piece for a Piece
-- end, as follow reads A.joint_world(r.target or r.v)). true, or false and why ('no_adapter': an adapter without
-- cap_parent, logged once at init and not per Cap). A new native call class whose crashes must stay attributed (a
-- first-call-only sentinel leaves later faults unattributed: refuted.md:116, spec M0 section 0 rule 7): armed until
-- one attach proved itself, then SENT.linger before every later attach (the spec's LAB.hot form, one write per
-- burst), so a fault inside any attach is a strike and two same-build strikes turn parent mode off (the Caps follow)
CA.PARENT_SENT, CA.PARENT_LINGER_S = 'caps.parent.first_attach', 3     -- 3 s: a world write (architecture.md)
local function attach_parent(rec)
    if not A.cap_parent then return false, 'no_adapter' end
    if st.proven.parent then SENT.linger(CA.PARENT_SENT, CA.PARENT_LINGER_S) end
    local why = nil                 -- the adapter's own reason for a false (SENT.risky passes one value through)
    local r, err = SENT.risky(CA.PARENT_SENT, st.proven, 'parent', true, function(...)
        local ok, w = A.cap_parent(...)
        why = w
        return ok
    end, rec.h, rec.target or rec.v, rec.anchor, rec.lpos, rec.lrot)
    if r == true then return true end
    return false, err or why or ('returned ' .. tostring(r))
end

local function spawn(req, entry, kind)
    local v, cut, side = req.v, req.cut, req.side
    local swap = st.caps[req.k] ~= nil                    -- a swap replaces its stand-in: it needs no room
    if not (A.cap_spawn and (swap or make_room(v, cut.part))) then
        return fail(v, cut.part, A.cap_spawn and 'limit' or 'no_spawner')
    end
    local h, err = SENT.risky('caps.' .. kind .. '.first_spawn', st.proven, kind, nil, A.cap_spawn, v, cut, entry, kind,
        side, req.piece)
    if h == nil then return fail(v, cut.part, tostring(err)) end
    st.spawned = st.spawned + 1
    local e = entry or {}
    local rec = { v = v, id = v.id, part = cut.part, kind = kind, h = h, n = st.spawned, party = v.party == true,
        anchor = e.anchor or cut.anchor or cut.root, lpos = e.lpos, lrot = e.lrot, follow = e.follow,
        mode = mode_of(entry or req.entry), still = 0, asleep = false, k = req.k, side = side, target = req.piece,
        stump = side ~= 'piece' and cut.stump ~= false }
    if rec.mode == 'parent' then
        local ok, why = attach_parent(rec)
        if not ok then
            rec.mode, rec.parent_fail = 'follow', why          -- this same call: the frame's render phase poses it
            st.parent_fallbacks = st.parent_fallbacks + 1
            if why ~= 'no_adapter' then
                LOG.warn('cap_fail', { id = v.id, part = cut.part, side = side, why = 'parent:' .. tostring(why),
                    fallback = 'follow' })
            end
        end
    end
    return rec
end

-- One request: fitted when ready, else the stand-in at fit_wait, then the same-call swap. Returns true when done.
local function serve(req)
    local v, cut, side = req.v, req.cut, req.side
    local waited = S.frame - req.f0
    local entry = req.entry
    if entry == nil and A.cap_fitted then entry = A.cap_fitted(v, cut, side) or false req.entry = entry end
    local ready = entry and A.cap_ready and A.cap_ready(entry) == true
    local k = req.k
    if ready then
        local rec = spawn(req, entry, 'fitted')
        if not rec then return true end
        local old = st.caps[k]
        if old then destroy(old) st.swaps = st.swaps + 1 end      -- same call, same frame: never zero, never two
        st.caps[k] = rec
        LOG.info('cap_attach', { id = v.id, part = cut.part, kind = 'fitted', level = 'fitted', frames = waited,
            side = side, swapped_from = old and old.kind or nil, mode = rec.mode })
        return true
    end
    local wait = side == 'piece' and opt('piece_fit_wait') or opt('fit_wait')
    if not st.caps[k] and (not entry or waited >= wait) then
        local bk = v.def and v.def.blood_kind
        local kind = CA.DISC_KINDS[bk] and 'disc' or 'nub'
        local rec = spawn(req, nil, kind)
        if not rec then return true end
        st.caps[k] = rec
        st.standins = st.standins + 1
        LOG.info('cap_attach', { id = v.id, part = cut.part, kind = kind, level = kind, standin = true, frames = waited,
            side = side, why = entry and 'not_ready' or 'no_fitted', mode = rec.mode })
        if not entry then return true end
    end
    -- never a permanent failure: logged once, then re-checked every fit_retry frames until the victim or Piece goes
    if waited >= opt('fit_missing') then
        if not req.missing then
            req.missing = true
            LOG.warn('cap_fail', { id = v.id, part = cut.part, side = side, why = 'fitted_missing', frames = waited })
        end
        req.next_f = S.frame + math.max(1, opt('fit_retry'))
    end
    return false
end

local function request(v, cut, side, piece)
    return { v = v, cut = cut, side = side, piece = piece, f0 = S.frame, k = key(v.id, cut.part, side) }
end

function CA.gate()
    if opt('enabled') == false then return false, 'off' end
    if not MO.enabled(CA.name) then return false, 'modoff' end
    local okc, eff = pcall(C.effect, 'caps')
    if okc and eff == false then return false, 'off' end
    return true
end

local function clear_v(id, why, engine)
    for _, r in pairs(st.caps) do
        if r.id == id then
            if engine == false then r.h = nil end
            destroy(r, why)
        end
    end
    local keep = {}
    for _, q in ipairs(st.pending) do if q.v.id ~= id then keep[#keep + 1] = q end end
    st.pending = keep
end
local function clear_all(why)
    for _, r in pairs(st.caps) do destroy(r, why) end
    st.pending = {}
end

-- A closed gate stops new work only (DESIGN C5 operation 1): a request with no Cap yet drops (its staged hide never
-- commits, so no Stump opens), a fitted swap for a shown stand-in waits for the gate, and no shown Cap goes
local function hold(why)
    if not st.pending[1] then return end
    local keep = {}
    for _, req in ipairs(st.pending) do
        if st.caps[req.k] then
            keep[#keep + 1] = req
        else
            fail(req.v, req.cut and req.cut.part, 'gate:' .. tostring(why))
        end
    end
    st.pending = keep
end

-- late phase: serve the requests within the spawn budget
local function job()
    local open, why = CA.gate()
    if not open then hold(why) return end
    local keep, n = {}, 0
    st.asks = {}
    for _, req in ipairs(st.pending) do
        if req.next_f and S.frame < req.next_f then
            keep[#keep + 1] = req                  -- a slow re-check that is not due costs no budget
        elseif n < opt('spawn_per_frame') then
            n = n + 1
            local ok, done = pcall(serve, req)     -- one bad request (a raising manifest lookup) never blocks the rest
            if not ok then
                LOG.warn('cap_fail', { id = req.v and req.v.id, part = req.cut and req.cut.part,
                    why = 'serve:' .. tostring(done) })
            elseif not done then keep[#keep + 1] = req end
        else
            keep[#keep + 1] = req
        end
    end
    st.pending = keep
    local asks = st.asks
    st.asks = nil
    for _, a in ipairs(asks) do BUS.emit('keep_evict_oldest', a.v, a.info) end
end

-- render phase: follow Caps take their anchor's pose; still anchors sleep. Every test is against the pose at the
-- LAST WRITE (DD2 caps.lua follow_one), never the previous frame: a ragdoll settling 1 mm per frame would otherwise
-- never be re-posed and the Cap would drift off its stump. Rotations count too (|dot| <= 0.99999 is a turn): an
-- anchor turning in place swings the Cap's offset, and the followed parent's turn (a neck under a still chest) wakes it.
local QDOT_STILL = 0.99999
local function qdot(a, b) return math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z) end
local function still(r, an, pa)
    if not (r.wp and r.wq) then return false end
    if V.dist(an.p, r.wp) >= V.m(opt('sleep_eps')) or qdot(an.q, r.wq) <= QDOT_STILL then return false end
    if pa and not (r.wpq and qdot(pa.q, r.wpq) > QDOT_STILL) then return false end
    return true
end
CA.still = still
-- copies: an adapter may hand back one reused table per joint
local function cp3(p) return { x = p.x, y = p.y, z = p.z } end
local function cpq(q) return q and { w = q.w, x = q.x, y = q.y, z = q.z } or nil end
local function pose_all()
    if not (A.joint_world and A.cap_pose) then return end
    local frame = S.frame
    for _, r in pairs(st.caps) do
        if r.h and r.mode == 'follow' and r.anchor and (not r.asleep or frame % opt('sleep_check') == 0) then
            local ok, an = pcall(A.joint_world, r.target or r.v, r.anchor)
            if ok and an and an.p and an.q then
                local pa = nil
                if r.follow and r.follow.joint and (tonumber(r.follow.w) or 0) > 0 then
                    local okp, p = pcall(A.joint_world, r.target or r.v, r.follow.joint)
                    if okp and p and p.q then pa = p end        -- a failed read poses from the anchor alone
                end
                if still(r, an, pa) then
                    r.still = r.still + 1
                    if r.still >= opt('sleep_frames') then r.asleep = true end
                else
                    pcall(A.cap_pose, r.h, CA.place(r, an, pa))
                    r.still, r.asleep, r.wp, r.wq, r.wpq = 0, false, cp3(an.p), cpq(an.q), pa and cpq(pa.q) or nil
                end
            end
        end
    end
end

-- v is a victim (all its Caps) or a Piece handle (that Piece's end Cap); rescale (optional) follows a fading Piece
function CA.wake(v, rescale)
    for _, r in pairs(st.caps) do
        if r.target == v or (r.target == nil and v.id ~= nil and r.id == v.id) then
            r.asleep, r.still, r.wp = false, 0, nil         -- wp nil: the next render frame re-poses
            if rescale and r.h and A.cap_scale then pcall(A.cap_scale, r.h, rescale) end
        end
    end
end

-- Bus listeners: the cut only queues; body-level events keep or clear
local function on_cut(v, cut)
    if not cut or not cut.part then return end
    st.pending[#st.pending + 1] = request(v, cut, nil)
end

-- The Piece end of a cut, from the Piece spawner in the Piece's go-live frame (late phase): served at once, so a
-- stand-in (or the ready fitted Cap) shows with the Piece; a later fitted Cap swaps in through the queue.
function CA.attach_piece(v, cut, piece)
    if not (v and cut and cut.part and piece) or not CA.gate() then return false end
    local req = request(v, cut, 'piece', piece)
    if st.caps[req.k] then return true end                         -- idempotent per Piece end
    for _, q in ipairs(st.pending) do if q.k == req.k then return true end end
    local ok, done = pcall(serve, req)
    if not ok then LOG.warn('cap_fail', { id = v.id, part = cut.part, side = 'piece', why = 'serve:' .. tostring(done) }) end
    if not (ok and done) then st.pending[#st.pending + 1] = req end
    return CA.live_piece(v, cut)
end
function CA.remove_piece(v, part, why)
    local k = key(v.id, part, 'piece')
    if st.caps[k] then destroy(st.caps[k], why or 'piece_gone') end
    local keep = {}
    for _, q in ipairs(st.pending) do if q.k ~= k then keep[#keep + 1] = q end end
    st.pending = keep
end
local function on_whole(v, mode)
    if mode == 'pieces' then return end                     -- a frozen shatter into Pieces keeps the torso Stumps
    for _, r in pairs(st.caps) do if r.id == v.id and r.stump then destroy(r, 'whole:' .. tostring(mode)) end end
end

function CA.init(adapter, opts)
    A = adapter or {}
    st = fresh()
    for _, fn in ipairs({ 'cap_spawn', 'cap_destroy', 'cap_fitted', 'joint_world', 'cap_pose' }) do
        if not A[fn] then LOG.info('adapter_missing', { module = CA.name, fn = fn, why = 'that Cap path is off' }) end
    end
    if not A.cap_parent then
        LOG.info('adapter_missing', { module = CA.name, fn = 'cap_parent', why = 'parent-mode Caps follow instead' })
    end
    BUS.on('cut', CA.name, on_cut)
    BUS.on('whole', CA.name, on_whole)
    BUS.on('split_live', CA.name, function(v) on_whole(v, 'split_live') end)
    BUS.on('corpse_hit', CA.name, function(v) CA.wake(v) end)
    BUS.on('piece_live', CA.name, function(v, cut, piece) CA.attach_piece(v, cut, piece) end)
    BUS.on('piece_gone', CA.name, function(v, part) CA.remove_piece(v, part) end, { teardown = true })
    BUS.on('restore', CA.name, function(v) clear_v(v.id, 'restore') end, { teardown = true })
    BUS.on('victim_gone', CA.name, function(v) clear_v(v.id, 'gone', false) end, { teardown = true })
    -- no mod_off listener: mod-off clears no Cap. It hides the loose objects only, so live() lists the Piece-end Caps
    -- (they hide with their Pieces); a Stump Cap stays while its Stump shows (DESIGN C5)
    MO.feature(CA.name, { gameplay = true, live = function()
        local out = {}
        for _, r in pairs(st.caps) do
            if r.h and r.side == 'piece' then out[#out + 1] = { obj = r.h, name = 'cap' } end
        end
        return out
    end })
    S.ticker(CA.name, job)
    S.writer(CA.name, pose_all)
    return true
end
function CA.shutdown(reason)
    clear_all(reason or 'shutdown')
    S.remove_ticker(CA.name)
    S.remove_writer(CA.name)
    for _, ev in ipairs({ 'cut', 'whole', 'split_live', 'corpse_hit', 'piece_live', 'piece_gone', 'restore',
        'victim_gone' }) do
        BUS.off(ev, CA.name)
    end
end
-- A map change: the Caps went with the old world (no engine call on them)
function CA.reset() st.pending, st.caps = {}, {} end
function CA.status()
    -- evicted stays 0 (no live Cap is evicted, DESIGN C4); refused counts the 'limit' refusals; parent_fallbacks the
    -- parent-mode Caps that follow instead
    return { caps = CA.count(), pending = #st.pending, spawned = st.spawned, swaps = st.swaps, standins = st.standins,
        evicted = st.evicted, refused = st.refused, slots = CA.slots(), parent_fallbacks = st.parent_fallbacks }
end
function CA.ui_status() return string.format('caps: %d alive, %d stand-ins swapped', CA.count(), st.swaps) end
function CA.handoff()
    local out = {}
    for _, r in pairs(st.caps) do out[#out + 1] = { id = r.id, part = r.part, kind = r.kind, side = r.side } end
    return out
end

return CA
