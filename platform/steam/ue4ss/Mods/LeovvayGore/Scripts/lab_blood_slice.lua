-- status: new for the beta test build (offline only, smoke-run on fakes; the author's run decides) origin:
-- docs/research/slicer-stumps.md (S2 wiring), the author 2026-11-01 («there must be a way in ue to make really
-- ultra-high-quality stumps»)
-- lab_blood_slice.lua: lab_blood's bleed of a slice, a library lab_blood requires (main.lua's LIBS puts it in the code
-- hash); BS.bind(h) hands it lab_blood's own helpers and state at lab_blood's init, so the gates, budgets, breaker,
-- counters and records stay lab_blood's. lab_blood queues bus lab_slice_live (lab_slice_route, after a slice that left
-- two halves) and its ticker calls BS.slice(s) for each, then BS.pulse(e) for each due pulse.
-- * What: a joint cut's bleed (lab_blood's header 'Cuts') on the halves instead of the hidden source. s.bone is the cut
--   bone (neck_01 for a head, the limb's cut bone: upperarm, lowerarm, thigh or calf), s.child the part's bone (head or
--   Head, the next bone down the limb), s.pos and s.neg the halves (ue.keep_mod records of SkeletalMeshComponents),
--   resolved in each call's own frame (ue.live_mod: still the one kept). A head sprays NS_BloodHeadBreak_001 at the
--   stump (a world spawn, lab_blood's spray under blood.fx); CUT_DECALS attached decals go round the stump on the
--   Negative half (the corpse, switched to receive decals once when its flag reads false); a pool under it for rank 1
--   (the ground: the Negative half's lowest GROUND_BONES bone less FOOT_LIFT, lab_blood's ground_z with this module's
--   reader; the pool itself is a world decal, blood.pool); Soul's splashes as for a cut (lab_blood's on_player,
--   blood.player). Then SPURTS pulses every SPURT_P s while the corpse is LAB.alive: each a stump spurt attached to the
--   Negative half at the cut bone and a trail spurt attached to the Positive half (the flying part) at the part's bone
--   (lab_blood's attach_fx).
-- * A re-slice (the route's next part cuts the Negative half again: the slicer hides that half and the route stops its
--   simulation) carries s.prev, that half's record: the pulses an earlier slice of the victim still has queued on it
--   move to the new Negative half (the rest of the body, the same bones), so no stump spurt comes out of the frozen,
--   hidden half; the stump decals the slicer hid with that half (decals are no primitive child: never transferred)
--   are drawn again at those stumps on the new half.
-- * Names: every call that reads a half, attaches to it or names it runs inside LAB.hot('slicer.blood') (META.lab_risky,
--   inherited, 3 s; no data/lab_classes.lua row, as the blood.* names), so a fault on a runtime half never strikes the
--   blood.* names every kill needs, and lab_slice's SL.hurt stops the next session's slices on it. Its breaker kind is
--   'slicer.blood' (lab_blood's FAIL_MAX in a row: off for the map).
-- * lab_bleed (lab_drops): pos and axis read on the halves, never a mesh, so lab_drops never touches a half: 'head' or
--   'limb' once (pos the stump, axis stump -> the part's bone, else pelvis -> stump: the pelvis read only then), then
--   per pulse two 'spurt' (the stump: axis pelvis -> stump; the trail: pos the part's bone, axis stump -> it).
-- * Off, gates: lab_blood's own (mod-off and the vanilla compare drop its queues and pulses; effects.blood; lab_end). The
--   player and data/no_blood.lua classes never bleed here (lab_plan never routes them to the slicer either).
-- * Counters (lab_blood publishes them at 0): blood_slices, and blood_cuts, blood_spurts, blood_fx as a cut's; record
--   blood kind 'slice' (lab_blood's first REC_N bleeds).
-- API: bind(h) slice(s) pulse(e).
-- What the mock cannot prove: native faults on the halves, whether an attached system follows a half's ragdoll, the look.
local BUS = require('core.bus')
local SENT = require('core.sentinel')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local BS = {}
local H = nil                                           -- lab_blood's helpers (BS.bind)

local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function unit(v)
    if type(v) ~= 'table' or not (num(v.x) and num(v.y) and num(v.z)) then return nil end
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if not num(n) or n < 1e-6 then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
-- A slice's half (lab_slice_route's ue.keep_mod record of a SkeletalMeshComponent lab_slice listed) in this frame:
-- still the one kept (identity reads only; the same full name is the same class, so still IsA one), else nil
local function half_of(rec)
    return type(rec) == 'table' and ue.live_mod(rec) or nil
end
-- Inside 'slicer.blood': a bone's world spot on a half, or nil
local function at(m, b)
    if not m or type(b) ~= 'string' or b == '' then return nil end
    return H.xyz(m:GetSocketLocation(ue.fname(b)))
end

-- Inside 'slicer.blood': the slice's spots on its halves now: stump (the cut bone on the Negative half), tip (the
-- part's bone on the Positive half), axis (stump -> tip, else pelvis -> stump: the Negative half's pelvis is read only
-- then), ground (with ground), neg (the Negative half). nil when the Negative half is gone
local function slice_read(s, ground)
    local neg, pos = half_of(s.neg), half_of(s.pos)
    if not neg then return nil end
    local r = { stump = at(neg, s.bone), tip = at(pos, s.child), neg = neg }
    if r.stump then
        r.axis = r.tip and unit(sub(r.tip, r.stump)) or nil
        if not r.axis then
            local pelvis = at(neg, 'pelvis')
            r.axis = pelvis and unit(sub(r.stump, pelvis)) or nil
        end
    end
    if ground then r.ground = H.ground_z(neg, at) end
    return r
end
-- Inside 'slicer.blood': the half switched to receive decals when its flag reads false. 1 when switched, else 0
local function recv_run(neg)
    if ue.get(neg, 'bReceivesDecals') == false then
        ue.count_write()
        neg:SetReceivesDecals(true)
        return 1
    end
    return 0
end
-- The attached decals of a slice on its Negative half neg (slice_read's, this frame) at the cut bone (each queued by
-- lab_blood's adecal under the name 'slicer.blood' with the half's own record neg_rec, s.neg: lab_blood's decal queue
-- resolves the half and spawns inside 'slicer.blood' in a later frame); the half switched to receive decals first (its
-- flag read and written in one 'slicer.blood' call, once per half; a failure counts in the breaker as lab_blood's
-- blood.recv does). The half's address keys its ADECALS_ACTOR count; its validity is read at the first decal
local function slice_adecals(actor, class, neg, neg_rec, bone, pos, n)
    local st = H.state()
    if H.stopped('slicer.blood') then return 0 end
    local key = ue.addr(neg)
    if key and not st.recv[key] then
        st.recv[key] = true
        local ok, err = LAB.hot('slicer.blood', recv_run, neg)
        if ok then H.worked('slicer.blood') else H.failed('slicer.blood', err or 'recv') end
        -- switched: back once the ring took the half's last stain (lab_blood's recv_off, its header, B4)
        if ok == 1 then st.recv_parts[key] = { parts = { neg_rec }, half = true, class = class } end
    end
    local t = { name = 'slicer.blood', actor = actor, class = class, bone = bone, mesh = neg, mrec = neg_rec,
        key = key or false, face = H.face_of(actor, nil), pos = pos and { x = pos.x, y = pos.y, z = pos.z } }
    local layers = H.adecal_layers()
    t.arec = ue.keep(actor)
    local k = 0
    for _ = 1, n do
        for _, mat in ipairs(layers) do
            if H.adecal(t, mat) then k = k + 1 end
        end
    end
    return k
end

-- One slice's bleed (header), lab_blood's ticker: the cut's bleed on the halves, then its pulses queued
function BS.slice(s)
    if not H or type(s) ~= 'table' then return end
    local B, st = H.B, H.state()
    -- a re-slice (header): the pulses still queued on the half it cut move to the new Negative half (Lua only); their
    -- stumps' bones get their decals drawn again there below
    local moved = {}
    if s.prev ~= nil and s.neg ~= nil then
        for _, e in ipairs(st.spurts) do
            if type(e.slice) == 'table' and e.slice.key == s.key and e.slice.neg == s.prev then
                e.slice.neg = s.neg
                moved[#moved + 1] = e.slice.bone
            end
        end
    end
    local class = s.class
    if not H.bleeds(s.key, class) then return end      -- never the player, never a data/no_blood.lua class
    if H.stopped('slicer.blood') or SENT.is_disabled('slicer.blood') then return end
    local actor = LAB.alive(s.rec)
    if not actor then return end
    local extra = type(s.rank) == 'number' and s.rank > 1
    local head = s.part == 'head'
    local t0 = H.now()                                  -- the reads count too, as a hit's, a kill's and a cut's (review)
    local r, err = LAB.hot('slicer.blood', slice_read, s, not extra)
    if not (type(r) == 'table' and r.stump) then
        H.failed('slicer.blood', err or 'no_stump')
        return
    end
    H.worked('slicer.blood')
    LAB.count('blood_cuts')
    LAB.count('blood_slices')
    local keep = s.rec.keep or s.rec                    -- the keep record LAB.alive just found live (LAB.live's)
    BUS.emit('lab_bleed', { kind = head and 'head' or 'limb', pos = r.stump, axis = r.axis, class = class, key = s.key,
        extra = extra })
    H.begin()
    local step = H.step
    local a = head and step('fx', H.spray, B.FX.head[1], r.stump, ue.rot(90, 0, 0), B.HEAD_SCALE) or false
    local ad = step('adecal', slice_adecals, actor, class, r.neg, s.neg, s.bone, r.stump, st.k.ADECALS_CUT)
    for _, b in ipairs(moved) do                        -- an earlier stump's decals went hidden with the half cut
        local p = LAB.hot('slicer.blood', at, r.neg, b)
        if type(p) == 'table' then step('adecal', slice_adecals, actor, class, r.neg, s.neg, b, p, st.k.ADECALS_CUT) end
    end
    if not H.late(t0) then                              -- a bleed past BLEED_MS skips its pool and Soul (lab_blood_queue)
        if not extra and r.ground then step('pool', H.pool_z, r.stump, r.ground, B.POOL_CUT) end
        step('player', H.on_player, r.stump, extra and st.k.PLAYER_EXTRA or (head and st.k.PLAYER_HEAD or st.k.PLAYER_LIMB),
            true)
    end
    H.slow_check('slice', class, t0)
    if #st.spurts < B.SPURT_MAX then
        st.spurts[#st.spurts + 1] = { slice = s, keep = keep, left = B.SPURTS, due = H.now(),
            fx = head and B.FX.stump[1] or B.FX.stump[2], class = class, key = s.key }
    end
    H.rec_bleed('slice', { class = class, part = s.part, bone = s.bone, child = s.child, fx = a and 1 or 0,
        adecals = ad, rank = extra and s.rank or nil, tip = r.tip ~= nil, ground = r.ground ~= nil })
end

-- Inside 'slicer.blood': one pulse: a stump spurt attached to the Negative half at the cut bone, a trail spurt
-- attached to the Positive half at the part's bone, and the spots read for lab_drops. { n, stump, tip, pelvis }
local function pulse_run(e, sys, lib)
    local s, B = e.slice, H.B
    local neg, pos = half_of(s.neg), half_of(s.pos)
    local out = { n = 0 }
    for _, h in ipairs({ { neg, s.bone, 'stump' }, { pos, s.child, 'tip' } }) do
        local m, bone = h[1], h[2]
        if m and type(bone) == 'string' and bone ~= '' then
            if H.attach_fx(lib, sys, m, bone, B.STUMP_SCALE) then out.n = out.n + 1 end
            out[h[3]] = at(m, bone)
        end
    end
    out.pelvis = at(neg, 'pelvis')
    return out
end
-- One pulse of a queued slice entry e (lab_blood's do_spurts, its corpse alive): the spurts, the counters, lab_bleed
-- 'spurt' per side with pos and axis
function BS.pulse(e)
    if not H or type(e) ~= 'table' or H.stopped('slicer.blood') then return end
    local sys, lib = H.system(e.fx), ue.cdo('niagara')
    if not (sys and lib) then
        LAB.count('blood_fx_fail')
        return
    end
    local r, err = LAB.hot('slicer.blood', pulse_run, e, sys, lib)
    if not (type(r) == 'table' and r.n > 0) then
        LAB.count('blood_fx_fail')
        H.failed('slicer.blood', err or 'no_component')
        return
    end
    H.worked('slicer.blood')
    LAB.count('blood_fx', r.n)
    LAB.count('blood_spurts', r.n)
    local pulse = H.B.SPURTS - e.left + 1
    -- one 'spurt' bleed at pos, its axis from -> pos
    local function bleed(pos, from)
        BUS.emit('lab_bleed', { kind = 'spurt', pos = pos, axis = from and unit(sub(pos, from)) or nil, keep = e.keep,
            class = e.class, key = e.key, pulse = pulse })
    end
    if r.stump then
        bleed(r.stump, r.pelvis)                        -- the stump: pelvis -> stump
        if r.tip then bleed(r.tip, r.stump) end         -- the trail: stump -> the part's bone
    end
end

-- lab_blood's init: its helpers (B, state(), stopped, failed, worked, xyz, system, spray, attach_fx, step, slow_check,
-- begin, rec_bleed, bleeds, ground_z, face_of, adecal_layers, adecal, pool_z, on_player, now); nil unbinds
function BS.bind(h) H = type(h) == 'table' and h or nil end
return BS
