-- status: new for the beta test build (offline only; the author's next run decides) origin: the author 2026-11-01
-- («I don't care about pools / more volumetric drops»; research: docs/research/blood-fluid.md, scratch/drops/research)
-- lab_drops.lua: volumetric blood drops. Real 3D drops fly from wounds and stumps, arc under gravity, stretch along
-- their flight and leave a small stain where they land, beside the game's flat sprite blood (Blood_V2 is CPU sprites
-- and ribbons; no vanilla system draws 3D drops). The player beta only (META.beta_modules, after lab_blood, which
-- emits the bleeds this module follows) with META.beta_drops; inert otherwise. Knobs (core/config.lua C.knob, live):
-- drops (on/off; the test key Ctrl+Shift+F1 flips it), drops_n (drops of one bled hit, default 8), drops_max (the pool
-- and the most drops in flight at once, default 96).
-- * Sources: bus lab_bleed, which lab_blood emits after each bleed it draws, so its gates hold here too: never the
--   player, never a class of data/no_blood.lua (puppets, vessels, metal enemies), damage only, one bleed per victim per
--   HIT_GAP_S and one over all victims per HIT_RATE_S, its FRAME_MS check, mod-off, the vanilla compare and
--   effects.blood. Kinds: 'hit' (the bone spot, the blow's direction), 'kill' (the last bled bone; along the last blow
--   on that victim and up), 'head' and 'limb' (the stump; along the cut part's way out), 'spurt' (each stump pulse:
--   the stump bone read again, along pelvis -> stump in a 12 degree cone, speed x0.75 a pulse). A bleed that carries
--   its axis (a slice's: lab_blood read pos and axis on the game slicer's halves under 'slicer.blood' and sends no
--   mesh) is taken as it comes: no stump or pelvis read here, so no call of this module ever touches a half; a slice's
--   pulse sends two spurts, the stump on the body half and the trail on the flying part. This listener checks
--   the player and data/no_blood.lua again. Counts at blood_amount 3 (scaled as lab_blood scales, d = amount / 3,
--   clamped 0.25-3): D.KINDS n x drops_n (hit 6-10, kill 10-14, limb 12-16, head 18-24, spurt 4-6), at most EVENT_MAX.
-- * The drop (research route 'PMC'): an engine Sphere (/Engine/BasicShapes/Sphere, half extent 50) on a
--   StaticMeshComponent of one keeper Actor of ours, scaled (STRETCH x r, r, r) / 50, so X is the long axis, shadows
--   off, refusing decals, one shared MID of BasicShapeMaterial (Color COLOR, Roughness ROUGH: a glossy dark red),
--   collision QueryOnly with every channel Ignore but WorldStatic Block (object type WorldDynamic: no pawn, ragdoll,
--   camera or trace ever meets it). Its ProjectileMovementComponent (same keeper) moves it: gravity 1, no bounce,
--   rotation follows velocity (the stretch follows the arc), sweep on, so the engine stops it on the first floor or
--   wall it meets (StopSimulating sets UpdatedComponent to none). Lua pays only the launch and the landing.
-- * Warm-up, once per map (the pool goes with the map): on the first bleed of the map, never in a frame with a
--   lab_death or a lab_cut_live and never while lab_cut has a job or a slicer job holds a corpse (lab_slice busy_any:
--   a kill's frames stay as they were), in frames with
--   room: the keeper (a deferred Actor spawn with a collision-free Box root, 'drop.warm'), then WARM_PER_FRAME drops a
--   frame ('drop.warm': the mesh component; 'drop.pmc': its movement component). The movement component is added
--   registered, so it takes the keeper's root as its UpdatedComponent; it is deactivated in the same call, before any
--   tick moves anything (no bitfield write is needed to park it), then bRotationFollowsVelocity, bShouldBounce,
--   ProjectileGravityScale and bAutoRegisterPhysicsVolumeUpdates are written. The first one's read-back goes to the
--   warm record. The pool grows to drops_max (POOL_HARD at most); a pool short of it flies what it has.
-- * Launch (frames after the bleed, never a frame with a lab_death or a lab_cut_live): at most LAUNCH_PER_FRAME a
--   frame in one 'drop.fly' call, about 4 engine calls each: K2_SetWorldTransform with teleport (the wound, rotation
--   along the velocity, the stretched scale), SetUpdatedComponent(drop), SetVelocityInLocalSpace(|v|, 0, 0), Activate
--   when it was stopped, SetHiddenInGame(false) when hidden. A launch item waits at most ITEM_S (game time) for a free
--   drop and the flight cap; an empty pool skips it (counted 'empty'). No drop from a source farther than FAR_CM from
--   the player (one location read a frame with events).
-- * Flight costs no Lua call. Landing: from POLL_SHARE of the predicted fall (a floor H_GUESS under the wound) or
--   POLL_MIN_S, then every POLL_S, one property read of the movement component's UpdatedComponent (none: it stopped),
--   at most POLL_PER_FRAME reads a frame ('drop.land'). A landed drop is hidden and goes back to the pool; every
--   STAIN_EVERY-th landing leaves a stain: its location read (K2_GetComponentLocation), then one of STAIN_N pooled
--   decals (MI_Blood_Stain_sgfjdepc_8K, half size STAIN_HALF, flat on a floor, along the flight on a wall) moved there
--   (K2_SetWorldLocationAndRotation), or a new one spawned while the stain pool fills (at most one spawn a frame:
--   SpawnDecalAtLocation costs 1-2 ms; never in a lab_death or lab_cut_live frame). The stains are ue.keep_mod
--   records (WorldSettings owns them: one destroyed since leaves the ring), the Sphere and the stain material ue.keep
--   records, each resolved in the frame it is used. A drop still flying FLY_MAX_S after its launch is stopped
--   ('drop.stop': StopMovementImmediately, Deactivate, hidden) and goes back to the pool.
-- * Off: mod-off, the vanilla compare (MODOFF.feature 'lab_drops', gameplay) or the drops knob false: no new drop,
--   queued ones dropped, the keeper actor hidden ('drop.stop': every drop with it); landings and time-outs still run
--   (they only hide our own drops), without stains. On again shows the keeper. Stains stay, as lab_blood's pools do.
--   lab_end stops all.
-- * Guards: every engine call runs inside LAB.hot (armed until its first answer, then lingered) under drop.warm,
--   drop.pmc, drop.fly, drop.land or drop.stop (META.lab_risky; drop.warm, .pmc and .fly inherited: refused after an
--   ArrayNum stop), only once LAB.pinned() reads true and never for a name the sentinel switched off. Each object runs
--   in its own pcall inside the batch call. Breakers per kind ('warm', 'pmc', 'fly', 'land', 'stop', 'stain'):
--   FAIL_MAX failures in a row stop that kind for the map (one forced drops_off record); fly needs land and stop, and
--   the warm-up and the launches need drop.fly, drop.land and drop.stop usable (none switched off by the sentinel).
--   The frame budget: no new work once FRAME_MS of this frame went to drops (the lab_blood lag guard's value).
-- * Records: drops (forced) once the warm-up ends (phase 'warm': pool, frames, ms, the first movement component's
--   read-back) and at each lab_flush with something new (phase: the flush reason; one per map at least when anything
--   flew): events by kind, launched, landed, timeout, stains, spawned stains, empty, far, off, qdrop, fail, the ms of
--   fly, land, stop and warm calls with their batch counts and largest batch, the most in flight; drops_off.
--   Counters (published at 0): D.COUNTERS.
-- What the mock cannot prove: native faults, whether the movement component sweeps and stops on PBZ's floors, the
--   look of the drops and stains, the real per-call costs.
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local C = require('core.config')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local US = require('adapter.ue_spawn')
local LAB = require('lab_probe')
local NO_BLOOD = require('data.no_blood')

local D = {
    -- the pool, the per-frame caps, the budget
    POOL_HARD = 128, WARM_PER_FRAME = 2, LAUNCH_PER_FRAME = 8, POLL_PER_FRAME = 24, STOP_PER_FRAME = 8,
    STAIN_PER_FRAME = 4, FRAME_MS = 4, QMAX = 32, LQ_MAX = 128, EVENT_MAX = 40, ITEM_S = 0.3, FAIL_MAX = 3,
    -- the flight: the player range, the time-out, the landing polls, gravity (cm/s2), the stretch, the source jitter
    FAR_CM = 2500, FLY_MAX_S = 2.0, POLL_S = 0.045, POLL_MIN_S = 0.12, POLL_SHARE = 0.7, H_GUESS = 90, G = 980,
    STRETCH = 1.5, SPHERE_R = 50, JITTER_CM = 2, LASTDIR_MAX = 256,
    -- the look: BasicShapeMaterial's Color (linear) and Roughness (the parameter exists, default 0.641)
    COLOR = { R = 0.09, G = 0.004, B = 0.003 }, ROUGH = 0.08,
    -- the stains: pooled decals, one per STAIN_EVERY landings
    STAIN_N = 48, STAIN_EVERY = 2, STAIN_HALF = { 5, 10 }, STAIN_DEPTH = 10,
    -- blood_amount as lab_blood reads it
    AMOUNT_REF = 3.0, AMOUNT_MIN = 0.25, AMOUNT_MAX = 3.0,
    ACTOR = '/Script/Engine.Actor', BOX = '/Script/Engine.BoxComponent', SMC = '/Script/Engine.StaticMeshComponent',
    PMC = '/Script/Engine.ProjectileMovementComponent', SPHERE = '/Engine/BasicShapes/Sphere.Sphere',
    STAIN_MAT = '/Game/PBZContent/Environments/Decal/Nature/Material/MI_Blood_Stain_sgfjdepc_8K.MI_Blood_Stain_sgfjdepc_8K',
}
-- Per bleed kind: n (x drops_n), r (radius cm), v (speed cm/s), cone (degrees round the axis), up (cm/s added up),
-- decay (speed factor per spurt pulse)
D.KINDS = {
    hit = { n = 1.0, r = { 0.5, 1.2 }, v = { 150, 350 }, cone = 45, up = 60 },
    kill = { n = 1.5, r = { 0.6, 1.6 }, v = { 180, 380 }, cone = 60, up = 120 },
    limb = { n = 1.75, r = { 0.7, 1.6 }, v = { 220, 420 }, cone = 30, up = 60 },
    head = { n = 2.6, r = { 0.8, 1.8 }, v = { 250, 480 }, cone = 30, up = 80 },
    spurt = { n = 0.6, r = { 0.6, 1.4 }, v = { 300, 450 }, cone = 12, up = 0, decay = 0.75 },
}
D.NAMES = { 'drop.warm', 'drop.pmc', 'drop.fly', 'drop.land', 'drop.stop' }
D.COUNTERS = { 'drops_events', 'drops_launched', 'drops_landed', 'drops_timeout', 'drops_stains', 'drops_skip_empty',
    'drops_skip_far', 'drops_skip_off', 'drops_fail' }
-- A guard that refused: the call never ran, so it is no failure of its kind
D.NEVER_RAN = { inherit_off = true, disabled_by_sentinel = true, arm_write_failed = true }

local A = nil
local UP = { x = 0, y = 0, z = 1 }
local function new_tally()
    return { events = {}, launched = 0, landed = 0, timeout = 0, stains = 0, stain_spawns = 0, empty = 0, far = 0,
        off = 0, qdrop = 0, fail = 0, fly_ms = 0, fly_n = 0, fly_max = 0, land_ms = 0, land_n = 0, land_max = 0,
        stop_ms = 0, stop_n = 0, warm_ms = 0, warm_n = 0, flying_max = 0 }
end
local function new_state()
    return { init = false, ended = false, q = {}, lq = {}, pool = {}, free = {}, flying = {}, raw = {}, stains = {},
        si = 1, keeper = nil, kobj = nil, mid = nil, sphere = nil, stain_mat = nil, warm_ep = nil, warm_t0 = nil,
        warm_f = 0, warm_rec = false, props = nil, busy_f = nil, pawn = nil, lastdir = {}, nlast = 0, fails = {},
        off = {}, err = nil, hidden = false, land_n = 0, amount = 1, t = new_tally(), dirty = false, lost = 0 }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or os.clock() end
local function gnow() return S.game_time or 0 end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function rnd(a, b) return a + (b - a) * math.random() end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function text(s)
    s = tostring(s)
    return #s > 160 and s:sub(1, 160) or s
end
local function mod(name)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end

-- ---------- plain vectors ----------
local function unit(v)
    if type(v) ~= 'table' or not (num(v.x) and num(v.y) and num(v.z)) then return nil end
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if not num(n) or n < 1e-6 then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
local function add(a, b, k) k = k or 1 return { x = a.x + k * b.x, y = a.y + k * b.y, z = a.z + k * b.z } end
local function cross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
-- A cone of deg degrees round the axis, built once per bleed: the unit axis a, a basis u, w across it, 1 - cos(deg)
local X1 = { x = 1, y = 0, z = 0 }
local function cone_of(axis, deg)
    local a = unit(axis) or UP
    local u = unit(cross(a, math.abs(a.z) < 0.9 and UP or X1)) or X1
    return a, u, cross(a, u), 1 - math.cos(math.rad(deg))
end
-- A random unit direction within that cone (uniform over its cap): two draws, the height, then the angle. x, y, z
local function cone_dir(a, u, w, k)
    local c = 1 - math.random() * k
    local s = math.sqrt(math.max(0, 1 - c * c))
    local p = math.random() * 2 * math.pi
    local cp, sp = math.cos(p) * s, math.sin(p) * s
    return a.x * c + u.x * cp + w.x * sp, a.y * c + u.y * cp + w.y * sp, a.z * c + u.z * cp + w.z * sp
end
-- The FQuat of a rotator facing along d (roll 0; FRotator::Quaternion's formula)
local function quat_of(d)
    local pitch = math.asin(clamp(d.z, -1, 1))
    local yaw = math.atan(d.y, d.x)
    local sp, cp = math.sin(pitch / 2), math.cos(pitch / 2)
    local sy, cy = math.sin(yaw / 2), math.cos(yaw / 2)
    return { X = sp * sy + 0.0, Y = -sp * cy + 0.0, Z = cp * sy + 0.0, W = cp * cy + 0.0 }
end
-- {x, y, z} from an engine vector (X/Y/Z) or a plain one; nil unless three finite numbers
local function xyz(v)
    v = ue.p(v)
    if v == nil then return nil end
    local x, y, z
    if type(v) == 'table' and v.x ~= nil then x, y, z = v.x, v.y, v.z
    else x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z') end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end

-- ---------- settings ----------
local function amount()
    local ok, s = pcall(C.get)
    local v = ok and type(s) == 'table' and tonumber(s.blood_amount) or nil
    if not num(v) then return 1 end
    return clamp(v / D.AMOUNT_REF, D.AMOUNT_MIN, D.AMOUNT_MAX)
end
local function blood_on()
    local ok, on = pcall(C.effect, 'blood')
    return not ok or on ~= false
end
local function cap() return math.min(C.knob('drops_max') or 96, D.POOL_HARD) end

-- ---------- guards and breakers ----------
-- A name LAB.hot would run now: pinned, not struck, not inherited after a stop. ok, why
local function usable(name)
    if LAB.pinned() ~= true then return false, 'unpinned' end
    if SENT.is_disabled(name) then return false, 'disabled' end
    if LAB.inherited(name) and not LAB.inherit_ok() then return false, 'inherit_off' end
    return true
end
-- A drop can fly and end: drop.fly, drop.land and drop.stop all usable (a struck land or stop would leave flown drops
-- in sight, unpolled; a struck fly would build a pool that never flies)
local function flies() return usable('drop.fly') and usable('drop.land') and usable('drop.stop') end
local function failed(kind, err)
    local n = (st.fails[kind] or 0) + 1
    st.fails[kind] = n
    if err ~= nil then st.err = text(err) end
    st.t.fail, st.dirty = st.t.fail + 1, true
    LAB.count('drops_fail')
    if n >= D.FAIL_MAX and not st.off[kind] then
        st.off[kind] = true
        LAB.rec('drops_off', { kind = kind, fails = n, err = st.err }, true)
    end
end
local function worked(kind) st.fails[kind] = 0 end
-- An error raised inside one object's pcall: lab_probe's stop rule reads an ArrayNum text there
local function caught(err, step)
    ue.caught(err, 'drops', step)
    return text(err)
end
-- One guarded batch: fn(...) under LAB.hot(name), name one of D.NAMES (a literal at each call site; any other is
-- refused, never run), timed into the tally's <key>_ms, <key>_n and <key>_max. r, err
local GUARDED, TALLY = {}, {}
for _, n in ipairs(D.NAMES) do GUARDED[n] = true end
for _, k in ipairs({ 'warm', 'fly', 'land', 'stop' }) do TALLY[k] = { k .. '_ms', k .. '_n', k .. '_max' } end
local function batch(name, key, fn, ...)
    if not GUARDED[name] then return nil, 'unknown_name' end
    local t0 = now()
    local r, err = LAB.hot(name, fn, ...)
    local ms = (now() - t0) * 1000
    local t, k = st.t, TALLY[key]
    local kms, kn, kmax = k[1], k[2], k[3]
    t[kms], t[kn] = t[kms] + ms, t[kn] + 1
    if t[kmax] and ms > t[kmax] then t[kmax] = ms end
    st.dirty = true
    return r, err
end
-- The frame budget: true while this tick's work stays under FRAME_MS (the ticker sets frame_t0 as it starts its work)
local frame_t0 = 0
local function room() return (now() - frame_t0) * 1000 < D.FRAME_MS end

-- ---------- the pool ----------
local function free(d)
    d.state = 'free'
    st.free[#st.free + 1] = d
end
local function dead(d, why)
    d.state, d.why = 'dead', why
    for i, x in ipairs(st.pool) do if x == d then table.remove(st.pool, i) break end end
end
-- The keeper while it is still ours on this map; a lost keeper takes the pool with it (the warm-up starts again)
local function keeper_live()
    if not st.keeper then return nil end
    local a = ue.live_mod(st.keeper)
    if a then return a end
    st.keeper, st.kobj, st.mid = nil, nil, nil
    st.pool, st.free, st.flying, st.raw, st.raw_wait = {}, {}, {}, {}, nil
    st.lost = st.lost + 1
    return nil
end

-- The player's place (ue.root_loc: property reads of its unattached root, no UFunction), or nil
local function pawn_pos()
    local p = st.pawn and ue.live(st.pawn) or nil
    return p and ue.root_loc(p) or nil
end

-- ---------- warm-up (inside 'drop.warm' and 'drop.pmc') ----------
-- The keeper: a deferred Actor spawn at the player (else the origin) with a collision-free Box root, shown (its drops
-- hide one by one). The drops' movement components check their owner against the map's KillZ each tick (falling out
-- of the world destroys the actor): the player's place is above it, the origin need not be. true, or it raises why
local function warm_keeper()
    local cls = ue.class(D.ACTOR)
    if not cls then error('no_actor_class', 0) end
    local p = pawn_pos()
    local a, why, half = US.spawn_deferred(cls, ue.xform(p and ue.vec(p.x, p.y, p.z) or nil), {})
    if not a then
        if half then pcall(US.destroy_actor, half) end
        error('spawn: ' .. text(why), 0)
    end
    local rec = ue.keep_mod(a)
    if not rec then error('unread', 0) end
    local box, wb = ue.add_component(a, D.BOX, { no_collision = true })
    if not box then
        pcall(US.destroy_actor, a)
        error('box: ' .. text(wb), 0)
    end
    st.keeper, st.kobj, st.hidden = rec, a, false
    return true
end
-- One drop's mesh component on the keeper: no collision while it is set up, movable and absolute (the keeper's root
-- never carries a drop), the Sphere, no shadow, no decals, the shared MID (made on the first), hidden, then QueryOnly
-- with WorldStatic Block alone (object type WorldDynamic)
local function new_mesh(a, cls)
    local c = ue.p(a:AddComponentByClass(cls, false, ue.xform(), false))
    if not ue.valid(c) then return nil, 'add' end
    ue.count_write()
    c:SetCollisionEnabled(0)
    c:SetMobility(2)
    pcall(function() c:SetAbsolute(true, true, true) end)
    local ok, why = L.set_static_mesh(c, st.sphere and ue.live(st.sphere) or nil)
    if not ok then return nil, 'mesh: ' .. text(why) end
    c:SetCastShadow(false)
    ue.refuse_decals(c, D.SMC)
    if st.mid then
        c:SetMaterial(0, st.mid)
    else
        local m, wm = L.mid(c, nil, D.COLOR)
        if not m then return nil, 'mid: ' .. text(wm) end
        pcall(function() m:SetScalarParameterValue(ue.fname('Roughness'), D.ROUGH + 0.0) end)
        st.mid = m
    end
    c:SetHiddenInGame(true, false)
    c:SetCollisionResponseToAllChannels(0)
    c:SetCollisionResponseToChannel(0, 2)
    c:SetCollisionObjectType(1)
    c:SetCollisionEnabled(1)
    return c
end
local function warm_meshes(n)
    local a, cls = st.kobj, ue.class(D.SMC)
    if not cls then error('no_smc_class', 0) end      -- raised: LAB.hot keeps only fn's first value
    local made, why = 0, nil
    for _ = 1, n do
        local okc, c, w = pcall(new_mesh, a, cls)
        if not okc then c, w = nil, caught(c, 'drop.warm') end
        if not c then
            why = w or 'failed'
            break
        end
        local d = { c = c, m = nil, state = 'new', vis = false, active = false }
        st.pool[#st.pool + 1] = d
        st.raw[#st.raw + 1] = d
        made = made + 1
    end
    return { made = made, why = why }
end
-- One drop's movement component: added registered (it takes the keeper's root as its UpdatedComponent), deactivated
-- in the same call before any tick moves anything (one that still reads active is destroyed at once: it would carry
-- the keeper's root down), then its flags written, each in its own pcall (a refused flag costs the look, not the
-- drop); the first one's read-back is kept. m | nil, why
local function new_pmc(a, cls)
    local m = ue.p(a:AddComponentByClass(cls, false, ue.xform(), false))
    if not ue.valid(m) then return nil, 'add' end
    ue.count_write()
    local okd, err = pcall(function() m:Deactivate() end)
    local oka, act = pcall(function() return m:IsActive() end)
    if not okd or not oka or act ~= false then
        pcall(ue.destroy, m)
        return nil, 'park: ' .. text(okd and (oka and tostring(act) or act) or err)
    end
    ue.set(m, 'bRotationFollowsVelocity', true)
    ue.set(m, 'bShouldBounce', false)
    ue.set(m, 'ProjectileGravityScale', 1.0)
    ue.set(m, 'bAutoRegisterPhysicsVolumeUpdates', false)
    if not st.props then
        local u = ue.get(m, 'UpdatedComponent')
        st.props = { rot_follow = ue.get(m, 'bRotationFollowsVelocity'), bounce = ue.get(m, 'bShouldBounce'),
            gravity = r1(ue.get(m, 'ProjectileGravityScale')), phys_vol = ue.get(m, 'bAutoRegisterPhysicsVolumeUpdates'),
            took_root = ue.valid(u) and (ue.name(u) or 'unread') or 'none', active = act }
    end
    return m
end
local function warm_pmcs()
    local a, cls = st.kobj, ue.class(D.PMC)
    if not cls then error('no_pmc_class', 0) end
    local made, why = 0, nil
    for _, d in ipairs(st.raw) do
        local okc, m, w = pcall(new_pmc, a, cls)
        if not okc then m, w = nil, caught(m, 'drop.pmc') end
        if m then
            d.m = m
            made = made + 1
        else
            why = w or 'failed'
            d.why = why
        end
    end
    return { made = made, why = why }
end
-- The warm record, once per map, when the pool reaches its size (or a breaker ends the warm-up)
local function warm_done(why)
    if st.warm_rec then return end
    st.warm_rec = true
    LAB.rec('drops', { phase = 'warm', pool = #st.pool, target = cap(), frames = st.warm_f,
        s = st.warm_t0 and r1(now() - st.warm_t0) or nil, ms = r1(st.t.warm_ms), why = why, mid = st.mid ~= nil,
        stain_mat = st.stain_mat ~= nil, props = st.props, err = st.err }, true)
end
-- The warm-up still has work on this map: a bleed started it, the pool is short, no breaker stopped it, drops can fly
local function warming()
    return st.warm_ep == ue.epoch and #st.pool < cap() and not (st.off.warm or st.off.pmc) and flies()
end
-- The stain: lab_blood's own layer (B.layer: its asset cache, a missing or stale one reloaded by lab_blood off these
-- frames), never looked up (review: a map load deletes the held layer's cache entry, so a lookup missed in the bleed
-- frame); only while lab_blood does not run: the cache, never a stale one looked up, else one lookup
local function stain_obj()
    local B = mod('lab_blood')
    if B and type(B.layer) == 'function' then
        local ok, o, why = pcall(B.layer, D.STAIN_MAT)
        if ok and why ~= 'inert' then return o end
    end
    local sm, _, why = ue.asset_peek(D.STAIN_MAT)
    if not sm and why ~= 'stale' then sm = ue.find(D.STAIN_MAT) end
    return sm
end
-- One warm step a frame: the lookups, the keeper, then WARM_PER_FRAME drops (mesh, then movement). true when it ran
local function warm_step()
    if not warming() then return false end
    local K = mod('lab_cut')                            -- never while a kill's cuts wait for their commit
    if K and K.njobs and K.njobs() > 0 then return false end
    local SLC = mod('lab_slice')                        -- nor while a slicer job holds a corpse (its slice frames)
    if SLC and type(SLC.busy_any) == 'function' and SLC.busy_any() then return false end
    if not (st.sphere and ue.live(st.sphere)) then    -- ue.keep records: the assets are found again in each use's frame
        st.sphere = ue.keep(ue.find(D.SPHERE))
        st.stain_mat = ue.keep(stain_obj())
        if not st.sphere then
            failed('warm', 'no_sphere')
            if st.off.warm then warm_done('no_sphere') end
            return false
        end
    end
    if not (usable('drop.warm') and usable('drop.pmc')) then return false end
    st.warm_t0 = st.warm_t0 or now()
    st.warm_f = st.warm_f + 1
    if not st.kobj then
        local r, err = batch('drop.warm', 'warm', warm_keeper)
        if r then worked('warm') elseif not D.NEVER_RAN[err] then failed('warm', 'keeper: ' .. text(err)) end
    else
        -- meshes a refused 'drop.pmc' call left without a movement component go first: no new mesh meanwhile
        if st.raw_wait and st.raw_wait[1] then
            st.raw, st.raw_wait = st.raw_wait, nil
        else
            local n = math.min(D.WARM_PER_FRAME, cap() - #st.pool)
            st.raw = {}
            local r, err = batch('drop.warm', 'warm', warm_meshes, n)
            if type(r) == 'table' and r.made > 0 then worked('warm')
            elseif not D.NEVER_RAN[err] then failed('warm', type(r) == 'table' and r.why or err) end
        end
        if st.raw[1] then
            local p, perr = batch('drop.pmc', 'warm', warm_pmcs)
            if p == nil and D.NEVER_RAN[perr] then
                st.raw_wait = st.raw                    -- the call never ran: the same meshes wait for the next step
            else
                for _, d in ipairs(st.raw) do
                    if d.m then free(d) else dead(d, d.why or text(perr or 'no_pmc')) end
                end
                if type(p) == 'table' and p.made > 0 then worked('pmc')
                elseif not D.NEVER_RAN[perr] then failed('pmc', type(p) == 'table' and p.why or perr) end
            end
        end
        st.raw = {}
    end
    if st.off.warm or st.off.pmc then warm_done('breaker')
    elseif #st.pool >= cap() then warm_done(nil) end
    return true
end

-- ---------- launch (inside 'drop.fly') ----------
local function bone_at(mesh, bone)
    if not (ue.valid(mesh) and type(bone) == 'string' and bone ~= '' and bone ~= 'None') then return nil end
    local ok, p = pcall(function() return xyz(mesh:GetSocketLocation(ue.fname(bone))) end)
    if ok then return p end
    caught(p, 'drop.fly')
    return nil
end
-- LAB.alive by keep record within one fly_batch (a slice's pulse sends two spurts with the same keep); fly_batch
-- clears it before its bleeds
local ALIVE = {}
local function alive(keep)
    local v = ALIVE[keep]
    if v == nil then
        v = LAB.alive(keep) ~= nil
        ALIVE[keep] = v
    end
    return v
end
-- One bleed into launch items: its spot (a spurt reads its stump again), its axis, its count
local function expand(ev, ppos)
    local K = D.KINDS[ev.kind]
    if not K then return end
    local pos, axis = ev.pos, nil
    if ev.kind == 'spurt' then
        if not (ev.keep and alive(ev.keep)) then return end
        if ev.mesh ~= nil or not ev.pos then pos = bone_at(ev.mesh, ev.bone) end   -- a slice's pulse: read already
    end
    if ev.axis then                                     -- given (a head's joint -> head; a slice's, read on its halves)
        axis = ev.axis
    elseif ev.kind == 'spurt' or ev.kind == 'limb' or ev.kind == 'head' then
        -- the event's mesh, from an earlier frame, is read only while its corpse is LAB.alive (a spurt asked above)
        local pelvis = pos and ev.keep and alive(ev.keep) and bone_at(ev.mesh, 'pelvis') or nil
        axis = pelvis and unit({ x = pos.x - pelvis.x, y = pos.y - pelvis.y, z = pos.z - pelvis.z }) or nil
    elseif ev.kind == 'hit' then
        local dir = unit(ev.dir)
        axis = dir and unit(add(dir, UP, 0.35)) or nil
    else
        local ld = ev.key ~= nil and st.lastdir[ev.key] or nil
        axis = ld and unit(add(ld, UP, 0.8)) or nil
    end
    if not (type(pos) == 'table' and num(pos.x) and num(pos.y) and num(pos.z)) then return end
    if ppos then
        local dx, dy, dz = pos.x - ppos.x, pos.y - ppos.y, pos.z - ppos.z
        if dx * dx + dy * dy + dz * dz > D.FAR_CM * D.FAR_CM then
            st.t.far = st.t.far + 1
            LAB.count('drops_skip_far')
            return
        end
    end
    local n = (C.knob('drops_n') or 8) * K.n * st.amount * rnd(0.8, 1.2)
    if ev.extra then n = n / 2 end
    n = clamp(math.floor(n + 0.5), 0, D.EVENT_MAX)
    local k = (K.decay and ev.pulse and ev.pulse > 1) and K.decay ^ (ev.pulse - 1) or 1
    local j, g = D.JITTER_CM, gnow()
    local a, u, w, kc = cone_of(axis or UP, K.cone)
    for _ = 1, n do
        if #st.lq >= D.LQ_MAX then
            st.t.qdrop = st.t.qdrop + 1
            break
        end
        local dx, dy, dz = cone_dir(a, u, w, kc)
        local sp = rnd(K.v[1], K.v[2]) * k
        st.lq[#st.lq + 1] = { pos = { x = pos.x + rnd(-j, j), y = pos.y + rnd(-j, j), z = pos.z + rnd(-j, j) },
            v = { x = dx * sp, y = dy * sp, z = dz * sp + K.up }, r = rnd(K.r[1], K.r[2]), t = g }
    end
end
-- One drop off: teleported to the wound along its velocity, stretched, moved by its component, shown
local function launch_one(d, it)
    local dir = unit(it.v) or UP
    local speed = math.sqrt(it.v.x * it.v.x + it.v.y * it.v.y + it.v.z * it.v.z)
    local s = it.r / D.SPHERE_R
    d.c:K2_SetWorldTransform({ Translation = ue.vec(it.pos.x, it.pos.y, it.pos.z), Rotation = quat_of(dir),
        Scale3D = ue.vec(s * D.STRETCH, s, s) }, false, {}, true)
    d.m:SetUpdatedComponent(d.c)
    d.m:SetVelocityInLocalSpace(ue.vec(speed, 0, 0))
    if not d.active then
        d.m:Activate(false)
        d.active = true
    end
    if not d.vis then
        d.c:SetHiddenInGame(false, false)
        d.vis = true
    end
end
-- The predicted fall to a floor H_GUESS under the wound (game seconds)
local function t_fall(vz) return (vz + math.sqrt(math.max(0, vz * vz + 2 * D.G * D.H_GUESS))) / D.G end
local function fly_batch()
    local f, g, q = S.frame, gnow(), st.q
    if q[1] then
        local ready = false
        for _, ev in ipairs(q) do if ev.f < f then ready = true break end end
        local ppos = ready and pawn_pos() or nil
        for k in pairs(ALIVE) do ALIVE[k] = nil end
        local nq, j = #q, 0                             -- the bleeds of this frame stay queued, in order
        for i = 1, nq do
            local ev = q[i]
            if ev.f >= f then
                j = j + 1
                q[j] = ev
            else
                local ok, err = pcall(expand, ev, ppos)
                if not ok then caught(err, 'drop.fly') end
            end
        end
        for i = nq, j + 1, -1 do q[i] = nil end
    end
    local n, top = 0, cap()
    while n < D.LAUNCH_PER_FRAME and st.lq[1] and room() do
        local it = st.lq[1]
        if g - it.t > D.ITEM_S then
            table.remove(st.lq, 1)
            st.t.empty = st.t.empty + 1
            LAB.count('drops_skip_empty')
        elseif #st.flying >= top or not st.free[1] then
            break                                       -- it waits ITEM_S for a free drop (the warm-up, a landing)
        else
            local d = table.remove(st.free)
            table.remove(st.lq, 1)
            local ok, err = pcall(launch_one, d, it)
            if ok then
                d.state, d.t0, d.v0 = 'fly', g, it.v
                d.due = g + math.max(D.POLL_MIN_S, D.POLL_SHARE * t_fall(it.v.z))
                st.flying[#st.flying + 1] = d
                n = n + 1
                worked('fly')
            else
                dead(d, caught(err, 'drop.fly'))
                failed('fly', d.why)
            end
        end
    end
    if n > 0 then
        st.t.launched = st.t.launched + n
        LAB.count('drops_launched', n)
        if #st.flying > st.t.flying_max then st.t.flying_max = #st.flying end
    end
    return n
end

-- ---------- landing and time-out (inside 'drop.land' and 'drop.stop') ----------
-- A stain under a landed drop: flat on a floor, along the flight on a wall (the velocity at the stop: the launch's plus
-- gravity over the flight); a new pooled decal while the pool fills (one spawn a frame), else the oldest moved
local function stain_at(loc, d, spawn_ok)
    local t = gnow() - (d.t0 or gnow())
    local vx, vy, vz = d.v0.x, d.v0.y, d.v0.z - D.G * t
    local rot
    if math.abs(vz) >= math.sqrt(vx * vx + vy * vy) then rot = ue.rot(-90, 0, math.random() * 360.0)
    else rot = ue.rot(0, math.deg(math.atan(vy, vx)), math.random() * 360.0) end
    local at = ue.vec(loc.x, loc.y, loc.z)
    if #st.stains < D.STAIN_N and spawn_ok then
        local h = rnd(D.STAIN_HALF[1], D.STAIN_HALF[2])
        local mat = st.stain_mat and ue.live(st.stain_mat) or nil
        -- lint:allow L016 the bleeds lab_blood drew (its own gate: no player, no no_blood class, damage only, mod-off); the release port goes through fx_gate
        local dec = ue.spawn_decal(mat, ue.vec(D.STAIN_DEPTH, h, h), at, rot, { life = 0, fade_screen = 0 })
        if not dec then return nil, 'spawn' end
        st.stains[#st.stains + 1] = ue.keep_mod(dec)   -- a record (WorldSettings owns the decal: anyone may destroy it)
        st.t.stain_spawns = st.t.stain_spawns + 1
        return 'spawned'
    end
    if not st.stains[1] then return nil end
    if st.si > #st.stains then st.si = 1 end
    local s = ue.live_mod(st.stains[st.si])
    if not s then                                       -- destroyed since: it leaves the ring (a spawn refills it)
        table.remove(st.stains, st.si)
        return nil
    end
    st.si = st.si % #st.stains + 1
    s:K2_SetWorldLocationAndRotation(at, rot, false, {}, true)
    return 'moved'
end
-- The stain material of this frame's landings: the kept record while it lives, else lab_blood's cached one again (its
-- reload after a GC, or a warm step that came before lab_blood cached it again on this map), at most once a frame
-- (review: the warm step's answer stayed for the whole map, nil or dead)
local function stain_now()
    if st.stain_mat and ue.live(st.stain_mat) then return true end
    if st.stain_f ~= S.frame then
        st.stain_f = S.frame
        st.stain_mat = ue.keep(stain_obj())
    end
    return st.stain_mat ~= nil
end
local function updated_of(m) return m.UpdatedComponent end
-- A landed drop hidden, its location read first when a stain wants it. loc | nil
local function hide_landed(d, want)
    local p = want and xyz(d.c:K2_GetComponentLocation()) or nil
    d.c:SetHiddenInGame(true, false)
    d.vis = false
    return p
end
local function land_batch(due, stains_on)
    local g, n, nst, spawned = gnow(), 0, 0, false
    local mat_ok = stains_on and stain_now()
    for _, d in ipairs(due) do
        local ok, u = pcall(updated_of, d.m)
        if not ok then
            dead(d, caught(u, 'drop.land'))
            failed('land', d.why)
        elseif ue.valid(u) then
            d.due = g + D.POLL_S
        else
            st.land_n = st.land_n + 1
            local want = mat_ok and not st.off.stain and nst < D.STAIN_PER_FRAME
                and st.land_n % D.STAIN_EVERY == 0 and room()
            local okl, loc = pcall(hide_landed, d, want)
            if not okl then
                dead(d, caught(loc, 'drop.land'))
                failed('land', d.why)
            else
                free(d)
                n = n + 1
                worked('land')
                if loc then
                    nst = nst + 1
                    -- 'spawned' | 'moved' | nil, why (a failed spawn) | nil (nothing to move yet, no spawn this frame);
                    -- no spawn (1-2 ms) in a lab_death or lab_cut_live frame: a kill's frames stay as they were
                    local oks, r, why = pcall(stain_at, loc, d, not spawned and st.busy_f ~= S.frame)
                    if not oks then
                        failed('stain', caught(r, 'drop.land'))
                    elseif r then
                        if r == 'spawned' then spawned = true end
                        st.t.stains = st.t.stains + 1
                        LAB.count('drops_stains')
                        worked('stain')
                    elseif why then
                        failed('stain', why)
                    end
                end
            end
        end
    end
    return n
end
local function stop_one(d)
    d.m:StopMovementImmediately()
    d.m:Deactivate()
    d.active = false
    d.c:SetHiddenInGame(true, false)
    d.vis = false
end
local function stop_batch(late)
    local n = 0
    for _, d in ipairs(late) do
        local ok, err = pcall(stop_one, d)
        if ok then
            free(d)
            n = n + 1
            worked('stop')
        else
            dead(d, caught(err, 'drop.stop'))
            failed('stop', d.why)
        end
    end
    return n
end
-- The flying drops: the due polls (POLL_PER_FRAME at most) and the time-outs (STOP_PER_FRAME at most), gathered in
-- two scratch lists refilled each tick; landed and stopped ones leave the flying list (compacted in place, in order)
local DUE, LATE = {}, {}
local function land_step(stains_on)
    local fl = st.flying
    if not fl[1] then return end
    local g, nd, nl = gnow(), 0, 0
    for _, d in ipairs(fl) do
        if g - d.t0 >= D.FLY_MAX_S then
            if nl < D.STOP_PER_FRAME then
                nl = nl + 1
                LATE[nl] = d
            end
        elseif g >= d.due and nd < D.POLL_PER_FRAME then
            nd = nd + 1
            DUE[nd] = d
        end
    end
    for i = #DUE, nd + 1, -1 do DUE[i] = nil end
    for i = #LATE, nl + 1, -1 do LATE[i] = nil end
    if nd > 0 and not st.off.land and usable('drop.land') and room() then
        local r, err = batch('drop.land', 'land', land_batch, DUE, stains_on)
        if r == nil and not D.NEVER_RAN[err] then failed('land', err) end
        if type(r) == 'number' and r > 0 then
            st.t.landed = st.t.landed + r
            LAB.count('drops_landed', r)
        end
    end
    if nl > 0 and not st.off.stop and usable('drop.stop') then
        local r, err = batch('drop.stop', 'stop', stop_batch, LATE)
        if r == nil and not D.NEVER_RAN[err] then failed('stop', err) end
        if type(r) == 'number' and r > 0 then
            st.t.timeout = st.t.timeout + r
            LAB.count('drops_timeout', r)
        end
    end
    local nf, j = #fl, 0
    for i = 1, nf do
        local d = fl[i]
        if d.state == 'fly' then
            j = j + 1
            fl[j] = d
        end
    end
    for i = nf, j + 1, -1 do fl[i] = nil end
end

-- ---------- off: the keeper hidden (every drop with it), shown again on ----------
local function show(on)
    if st.hidden == not on or not st.kobj then return end
    if not usable('drop.stop') then return end
    local r = batch('drop.stop', 'stop', function()
        local ok, why = US.set_actor_hidden(st.kobj, not on)
        if not ok then error(why or 'hide', 0) end
        return true
    end)
    if r then st.hidden = not on end
end
local function drop_queued()
    local n = #st.q + #st.lq
    if n > 0 then
        st.t.off = st.t.off + n
        LAB.count('drops_skip_off', n)
        st.dirty = true
    end
    st.q, st.lq = {}, {}
end

-- ---------- the ticker ----------
local function tick()
    if not st.init or st.ended then return end
    if LAB.ended() then
        st.ended = true
        return
    end
    if LAB.paused() then return end
    if LAB.pinned() ~= true then
        if st.q[1] or st.lq[1] then st.q, st.lq = {}, {} end
        return
    end
    local queued = st.q[1] ~= nil or st.lq[1] ~= nil
    if not (queued or st.flying[1] or warming()) then return end
    if st.kobj and not keeper_live() then return end
    frame_t0 = now()
    local on = MODOFF.enabled('lab_drops') and C.knob('drops') ~= false and blood_on()
    if not on then
        drop_queued()
        show(false)
        land_step(false)
        return
    end
    show(true)
    st.amount = amount()
    land_step(true)
    if st.busy_f == S.frame then return end            -- a lab_death or a lab_cut_live this frame: nothing new
    if queued and room() then
        if st.off.fly or st.off.land or st.off.stop or not flies() then
            drop_queued()
        else
            local r, err = batch('drop.fly', 'fly', fly_batch)
            if r == nil and not D.NEVER_RAN[err] then failed('fly', err) end
        end
    end
    if room() then warm_step() end
end

-- ---------- bus listeners (they only queue and mark) ----------
local function on_bleed(ev)
    if not st.init or st.ended or type(ev) ~= 'table' or not D.KINDS[ev.kind] then return end
    if type(ev.class) == 'string' and (NO_BLOOD[ev.class] or ev.class:find('Player', 1, true)) then return end
    if ev.kind == 'hit' and ev.key ~= nil then
        local dir = unit(ev.dir)
        if dir then
            if st.lastdir[ev.key] == nil then st.nlast = st.nlast + 1 end
            if st.nlast > D.LASTDIR_MAX then st.lastdir, st.nlast = {}, 1 end
            st.lastdir[ev.key] = dir
        end
    end
    st.warm_ep = ue.epoch                               -- the first bleed of a map starts its warm-up
    st.t.events[ev.kind] = (st.t.events[ev.kind] or 0) + 1
    st.dirty = true
    LAB.count('drops_events')
    if #st.q >= D.QMAX then
        st.t.qdrop = st.t.qdrop + 1
        return
    end
    -- the way out given by the bleed (a slice's, read on its halves), else a head's: cut.gib's joint -> head spot
    local axis = type(ev.axis) == 'table' and unit(ev.axis) or nil
    if not axis and ev.kind == 'head' and type(ev.at) == 'table' and type(ev.joint) == 'table' and num(ev.at.x)
            and num(ev.at.y) and num(ev.at.z) and num(ev.joint.x) and num(ev.joint.y) and num(ev.joint.z) then
        axis = unit({ x = ev.at.x - ev.joint.x, y = ev.at.y - ev.joint.y, z = ev.at.z - ev.joint.z })
    end
    st.q[#st.q + 1] = { kind = ev.kind, pos = ev.pos, dir = ev.dir, axis = axis, mesh = ev.mesh, bone = ev.bone,
        keep = ev.keep, key = ev.key, pulse = ev.pulse, extra = ev.extra, f = S.frame }
end
local function flush_rec(reason)
    if not st.init or not st.dirty then return end
    st.dirty = false
    local t = st.t
    local function ms(k) return r1(t[k .. '_ms']) end
    LAB.rec('drops', { phase = reason or 'periodic', events = t.events, launched = t.launched, landed = t.landed,
        timeout = t.timeout, stains = t.stains, stain_spawns = t.stain_spawns, empty = t.empty, far = t.far,
        off = t.off, qdrop = t.qdrop, fail = t.fail, pool = #st.pool, free = #st.free, flying = #st.flying,
        flying_max = t.flying_max, fly_ms = ms('fly'), fly_n = t.fly_n, fly_max = r1(t.fly_max), land_ms = ms('land'),
        land_n = t.land_n, land_max = r1(t.land_max), stop_ms = ms('stop'), stop_n = t.stop_n, warm_ms = ms('warm'),
        warm_n = t.warm_n, breakers = next(st.off) and st.off or nil, lost = st.lost > 0 and st.lost or nil,
        err = st.err }, true)
end
local EVENTS = { 'lab_bleed', 'lab_death', 'lab_cut_live', 'lab_pawn', 'lab_flush', 'lab_end' }

-- ---------- lifecycle ----------
function D.init(adapter)
    A = adapter
    st = new_state()
    if not (LAB.beta() and META.beta_drops == true) then return true end
    st.init = true
    for _, k in ipairs(D.COUNTERS) do LAB.count(k, 0) end
    MODOFF.feature('lab_drops', { gameplay = true })   -- the vanilla compare stops new drops and hides the live ones
    BUS.on('lab_bleed', 'lab_drops', on_bleed)
    BUS.on('lab_death', 'lab_drops', function() st.busy_f = S.frame end)
    BUS.on('lab_cut_live', 'lab_drops', function() st.busy_f = S.frame end)
    BUS.on('lab_pawn', 'lab_drops', function(rec) if type(rec) == 'table' then st.pawn = rec.pawn end end)
    BUS.on('lab_flush', 'lab_drops', flush_rec)
    BUS.on('lab_end', 'lab_drops', function() st.ended = true end)
    S.ticker('lab_drops', tick)
    return true
end
-- A map load: the keeper, the pool, the stains and the queues went with the old map (lab_flush 'map' wrote their
-- record first); everything starts over as at init (the breakers too) but init, ended, the props read-back, the last
-- error and the amount; the counters stay
function D.reset()
    if not st.init then return end
    local old = st
    st = new_state()
    st.init, st.ended, st.props, st.err, st.amount = old.init, old.ended, old.props, old.err, old.amount
end
function D.status()
    local off = {}
    for k in pairs(st.off) do off[#off + 1] = k end
    table.sort(off)
    return { init = st.init, ended = st.ended, pool = #st.pool, free = #st.free, flying = #st.flying,
        stains = #st.stains, queued = #st.q + #st.lq, keeper = st.kobj ~= nil, hidden = st.hidden, off = off,
        warmed = st.warm_rec, err = st.err }
end
-- Engine-free (Ctrl+R runs it off the game thread): the keeper and the stains stay in the world until the map goes
function D.shutdown()
    S.remove_ticker('lab_drops')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_drops') end
    st, A = new_state(), nil
end
return D
