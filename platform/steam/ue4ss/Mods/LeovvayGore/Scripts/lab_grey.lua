-- status: new for the beta test build (offline only; the author's next run decides) origin: the author 2026-11-01
-- («the blood on me still sometimes turns grey under some shadows / have we researched alternative techniques for putting
-- on blood?»)
-- lab_grey.lua: lab_blood's grey A/B tools, a library lab_blood requires (main.lua's LIBS puts it in the code hash).
-- The cause and the checks: docs/research/grey-under-trees.md; the alternatives: docs/research/soul-blood-alternatives.md.
-- Console verbs (G.VERBS) registered at G.bind through main.lua's MAIN.verb (ctx.verb). Nothing runs until one is
-- typed: the reply line comes at once, the job only queues, and lab_blood's ticker runs the queue on its next frame
-- (G.step; also while paused, mod-off or the vanilla compare: reads, or switches of Soul's own parts), each job
-- pcall'ed (a raise is one grey_error record, never out of the ticker: sched's breaker would stop all of lab_blood).
-- After lab_end (no ticker) a verb only says so.
-- * 'leovvaygore grey [tag]': one grey_census record. Every DecalComponent (FindAllOf, cap G.CAP) that is none of the
--   mod's own (Soul's splashes, the victims' attached decals, the pools: by address, ctx.rings) and whose origin lies
--   within G.RANGE of Soul's pelvis gets its oriented box tested against G.POINTS (head, spine_05, pelvis): local axis
--   k = dot(point - origin, the component's unit axis k) / |scale k| against DecalSize k (UE: the half size; the box is
--   DecalSize scaled by the component transform); fit = the largest of the three ratios, at most 1 means inside. The
--   list holds every box that holds a point, then the closest misses, G.LIST at least: owner class and name,
--   material, reach_x_cm (the projection half-depth, DecalSize.X x |scale X|), the two other half sizes, h_cm (the
--   origin's height above Soul's lowest foot bone), dist_cm, fit, the points inside, fwd_z (the forward axis' Z: -1
--   projects straight down). Then Soul's 13 parts' bReceivesDecals and his CharacterWeatherComponent
--   (BP_Player_Base_C, property reads) Raining, Wet, Snow, Dust, bLockWeather, UseSceneWeather. The FindAllOf and the
--   per-decal reads are one armed 'grey.census' call; the bone reads are lab_blood's 'blood.read', the parts
--   'blood.comps'. The tag is the author's word for the spot ('shade', 'indoors'). With lab_leash on, the sizes read
--   are the capped ones (its leash records say what it changed).
-- * 'leovvaygore soul_recv off|on': SetReceivesDecals on Soul's 13 parts (receives_on's call and name 'blood.recv',
--   each part whose flag differs, lab_blood's breaker), so the eyes see at once whether the grey goes with the world
--   decals. Off also stops his blood splashes drawing (attached deferred decals draw only on a receiving part; they
--   keep landing and show again at 'on'). The wish holds until the next one, map loads included: while off,
--   lab_blood's on_player switches no new pawn on (G.recv_ok). One soul_recv record { want, asked, why, meshes,
--   switched, before, after, err }.
-- * 'leovvaygore soul_ovl on|off': route A3 on Soul only (soul-blood-alternatives.md, route A 'How' and the A3
--   skeptic's fixes). ON, in this order, every native call under a blood.ovl.* name, the first call of each name
--   armed, then hot; any failure (a raise, no answer, a sentinel refusal) fails the overlay closed for the session with
--   one blood_ovl_fail record { name, err } (the off path still restores, unless the set name itself failed):
--   1. blood_ovl_probe, once per pawn, before any write: Soul's own SkinnedDecalSampler (BP_Player_Base_C, P1: Mesh,
--      counts, LayerIndex, Association, AdditionalData, MaxDecals, MinDecalDistance, TranslucentBlend, the TB material,
--      DataTarget size), the TB material's reflected flags (P2: domain, blend, shading, usage flags), the cvars
--      r.SkinCache.Mode and .CompileShaders, r.Substrate, r.PSOPrecaching, and per part (P3) its class, overlay,
--      receive flag, SkinnedAsset and LeaderPoseComponent (meshhead's own pose: the face's ref-pose risk).
--   2. 'blood.ovl.setup': never AutoSetup on Soul (its first leader-less SkeletalMeshComponent can be Knife, and it
--      skips the 4 ChaosCloth parts). While Mesh and DataTarget are both unset, MaxDecals OVL.MAX and MinDecalDistance
--      OVL.MIN_DIST first (the target's width is 5 x MaxDecals at creation); then SetMeshComponent(CharacterMesh0,
--      false) once per pawn (it turns his slots into MIDs with the same parents and binds DecalMax/DecalInfo/DecalLast;
--      a second root call grows RenderMeshes), skipped while Mesh already is CharacterMesh0 with Materials; a sampler
--      on another mesh refuses. DataTarget, else GetDataTarget(). Checked: Mesh, Materials > 0, MaxDecals 1..32767.
--   3. 'blood.ovl.mid': a MID of the sampler's TranslucentBlendMaterial (else OVL.TB) through KismetMaterialLibrary,
--      held for the map on the player controller's keeper (ue.hold 'material': a Lua handle roots nothing, and once
--      the game replaced our overlay the MID would be collected under our next write), DecalMax 5 x MaxDecals,
--      DecalInfo the target, DecalLast the stored count, and the plugin's WoundDecal look (lab_blood's B.LOOK) so a
--      working pipeline cannot hide behind the empty SDC defaults. Then (read) every LOOK_PROBE texture name and
--      OVL.SCALARS scalar that answers on it: blood_ovl_on's params.
--   4. 'blood.ovl.set': SetOverlayMaterial(mid) on OVL.PARTS (CharacterMesh0, meshhead, the upper cloth, skirt, cape,
--      scarf, band) where GetOverlayMaterial reads nothing; hair, brow and lash cards, the hats and the knife stay out
--      (an overlay ignores the opacity mask). Read back, then Soul's receive off (G.recv_apply; the attached splashes
--      stop drawing, so the eyes see only the overlay). One blood_ovl_on record.
--   While on, every Soul splash (lab_blood's on_player, G.splash) also goes through his sampler: the bone spot pushed
--   OVL.PUSH toward the victim and jittered at least 1.5 x sqrt(MinDecalDistance) (a bone-centre spot maps to one
--   ref-pose point and every later one is dropped as too close), Size OVL.SIZE x 0.8-1.2 (a working size: baked in at
--   spawn, so no sweep), SubUV 0-3, Index -1, OVL.PER_FRAME a frame, 'blood.ovl.decal'; then DecalLast on our MID (the
--   plugin refreshes it only on its own Materials). Refused before the call: the MID gone, Mesh not CharacterMesh0,
--   no Materials (SpawnDecal would set up again), MaxDecals or LastDecalIndex out of range. Counters
--   blood_ovl_decals, blood_ovl_rejected, blood_ovl_skip, blood_ovl_budget. The splash runs inside on_player, so
--   lab_blood's lag guard times it with the 'player' step. The first accepted slot's texels
--   5i..5i+5 are read once on the next frame ('blood.ovl.rt', ReadRenderTargetRawPixel): blood_ovl_rt (all
--   (0,0,0,1): the canvas draws do not land). Every OVL.WATCH_S unpaused: each part's overlay read; a part that lost
--   it to nothing gets it again, another material stays (the game's); blood_ovl_watch on a change, OVL.WATCH_N at most.
--   OFF ('soul_ovl off', mod-off or the vanilla compare): SetOverlayMaterial(nil) where ours still is, the hold
--   released, receive back to the soul_recv wish; his slot MIDs (same parents) and the sampler's data stay. One
--   blood_ovl_off record. A map load ends it (the objects went with the world).
-- Wiring, G.bind(ctx) at lab_blood's init: ctx.verb (MAIN.verb), ctx.ended() (lab_blood after lab_end),
-- ctx.pawn() the live player pawn, ctx.rings() the mod's own decal rings,
-- ctx.mark_recv(pawn) (receives_on leaves that pawn alone), ctx.bone_pos, ctx.xyz, ctx.name_of, ctx.now,
-- ctx.stopped, ctx.failed and ctx.worked (lab_blood's breaker), ctx.texture, ctx.blood_on, ctx.ours(flag) (the
-- vanilla observer skips our SpawnDecal), ctx.B (lab_blood's constants).
-- What the mock cannot prove: the decal box convention in game, the property names on the live weather component,
-- whether the TB material carries skeletal usage (without it the engine drops the overlay silently: UE4SS.log
-- 'Overlay material with missing usage flag'), the Size unit, the overlay on ChaosCloth parts.
local MODOFF = require('core.modoff')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local G = { RANGE = 2500, CAP = 20000, LIST = 16, Q = 8,
    POINTS = { 'head', 'spine_05', 'pelvis' }, FEET = { 'foot_l', 'foot_r', 'ball_l', 'ball_r' } }
-- The console verbs and their usage words (MAIN.verb)
G.VERBS = { { 'grey', 'grey [tag]' }, { 'soul_recv', 'soul_recv off|on' }, { 'soul_ovl', 'soul_ovl on|off' } }
-- Route A3 (header): the plugin's TB material, the parts that take the overlay, the sampler's capacity and spacing
-- (written only while it is unset), the splash's push toward the victim, its jitter floor, the working size, the
-- budget, the watch period and records, the texels read
G.OVL = {
    TB = '/SkinnedDecalComponent/SkinnedDecalTranslucentBlendMat.SkinnedDecalTranslucentBlendMat',
    PARTS = { CharacterMesh0 = true, meshhead = true, CA_Hun_UpperCloth = true, CA_Hun_Skirt = true, CA_Hun_Cape = true,
        meshScarf = true, meshBand = true },
    MAX = 256, MIN_DIST = 4.0, PUSH = 8, JITTER = 5, SIZE = 18, PER_FRAME = 4, WATCH_S = 5, WATCH_N = 20, RT_N = 6,
    FLAGS = { 'MaterialDomain', 'BlendMode', 'ShadingModel', 'TwoSided', 'TranslucencyLightingMode', 'bDisableDepthTest',
        'bUsedWithSkeletalMesh', 'bUsedWithClothing', 'bUsedWithMorphTargets', 'bUsedWithNanite', 'bUseMaterialAttributes' },
    CVARS = { 'r.SkinCache.Mode', 'r.SkinCache.CompileShaders', 'r.Substrate', 'r.PSOPrecaching' },
    SCALARS = { 'DecalMax', 'DecalLast', 'Opacity', 'DecalOpacity', 'FadeTime', 'FadeDuration', 'Lifetime', 'Roughness',
        'Specular', 'Metallic', 'NormalStrength', 'Brightness', 'EmissiveStrength', 'SubUVRows', 'SubUVColumns', 'Size' },
}

local K = nil
-- The overlay's state; a map load starts a new one, the failure and the names already run stay for the session
local function new_ovl(prev)
    return { on = false, dead = prev and prev.dead or nil, ran = prev and prev.ran or {}, s = nil, tb = nil, hold = nil,
        parts = {}, setup = nil, probed = nil, budget = 0, sent = 0, rejected = 0, rt_idx = nil,
        rt_done = prev and prev.rt_done or false, watch_t = 0, watch_n = 0, watch_sig = nil, lost = false }
end
local function new_state() return { init = false, q = {}, recv_want = true, ovl = new_ovl() } end
local st = new_state()

local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function r2(v) return num(v) and math.floor(v * 100 + 0.5) / 100 or nil end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function count(arr)                               -- a TArray property's length, 0 when unread
    local ok, v = pcall(function() return #arr end)
    return ok and type(v) == 'number' and v or 0
end

-- ---------- reads ----------
-- The class word of an object's full name ('BP_ErosionDecal_C /Game/...' -> 'BP_ErosionDecal_C')
local function class_of(o)
    if o == nil then return 'none' end
    local full = ue.full(o)
    return full and full:match('^(%S+) ') or 'unread'
end
-- Soul's skinned parts (13: 9 SkeletalMeshComponents, 4 ChaosClothComponents), 16 at most: { name, recv } and the list
function G.parts(pawn)
    local comps = LAB.hot('blood.comps', function()
        return (ue.components(pawn, '/Script/Engine.SkinnedMeshComponent'))
    end) or {}
    local out, list = {}, {}
    for i, c in ipairs(comps) do
        if i > 16 then break end
        list[i] = c
        out[i] = { name = ue.name(c) or '?', recv = ue.get(c, 'bReceivesDecals') }
    end
    return out, list
end
-- His CharacterWeatherComponent (BP_Player_Base_C, CharacterWeatherComponent.hpp): property reads only
local function weather(pawn)
    local w = ue.get(pawn, 'CharacterWeatherComponent')
    if not ue.valid(w) then return 'none' end
    return { raining = r2(ue.get(w, 'Raining')), wet = r2(ue.get(w, 'Wet')), snow = r2(ue.get(w, 'Snow')),
        dust = r2(ue.get(w, 'Dust')), locked = ue.get(w, 'bLockWeather'), scene = ue.get(w, 'UseSceneWeather') }
end

-- ---------- 'grey': the census (header) ----------
-- One world decal against Soul's points: nil when its origin is past RANGE, else its entry; raises when a read gives
-- nothing (the census counts it unread)
local function decal_read(d, pts, c0, foot)
    local xyz = K.xyz
    local loc = xyz(d:K2_GetComponentLocation())
    if not loc then error('no_location', 0) end
    local dx, dy, dz = loc.x - c0.x, loc.y - c0.y, loc.z - c0.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > G.RANGE then return nil end
    local fx, ry, uz = xyz(d:GetForwardVector()), xyz(d:GetRightVector()), xyz(d:GetUpVector())
    local sc, size = xyz(d:K2_GetComponentScale()), xyz(ue.get(d, 'DecalSize'))
    if not (fx and ry and uz and sc and size) then error('no_axes', 0) end
    local hx, hy, hz = math.abs(size.x * sc.x), math.abs(size.y * sc.y), math.abs(size.z * sc.z)
    local fit, best, inside = math.huge, nil, {}
    for _, q in ipairs(pts) do
        local v = { x = q.p.x - loc.x, y = q.p.y - loc.y, z = q.p.z - loc.z }
        local f = math.max(math.abs(dot(v, fx)) / math.max(hx, 1e-3), math.abs(dot(v, ry)) / math.max(hy, 1e-3),
            math.abs(dot(v, uz)) / math.max(hz, 1e-3))
        if f <= 1 then inside[#inside + 1] = q.b end
        if f < fit then fit, best = f, q.b end
    end
    local owner = ue.p(d:GetOwner())
    local mat = ue.get(d, 'DecalMaterial')
    return { owner_class = class_of(owner), owner = ue.name(owner) or 'none', mat = K.name_of(mat),
        mat_class = class_of(ue.valid(mat) and mat or nil), reach_x_cm = r1(hx), half_y_cm = r1(hy),
        half_z_cm = r1(hz), h_cm = foot and r1(loc.z - foot) or nil, dist_cm = r1(dist), fit = r2(fit) or 1e9,
        best = best, inside = inside[1] and inside or nil, fwd_z = r2(fx.z), visible = ue.get(d, 'bVisible'),
        hidden = ue.get(d, 'bHiddenInGame') }
end
local function census(tag)
    local pawn = K.pawn()
    local mesh = pawn and ue.get(pawn, 'Mesh') or nil
    if not ue.valid(mesh) then LAB.rec('grey_census', { tag = tag, err = 'no_pawn' }, true) return end
    local pts, foot = {}, nil
    for _, b in ipairs(G.POINTS) do
        local p = K.bone_pos(mesh, b)
        if p then pts[#pts + 1] = { b = b, p = p } end
    end
    for _, b in ipairs(G.FEET) do
        local p = K.bone_pos(mesh, b)
        if p and (foot == nil or p.z < foot) then foot = p.z end
    end
    if not pts[1] then LAB.rec('grey_census', { tag = tag, err = 'no_bones' }, true) return end
    local c0 = pts[#pts].p                                  -- the pelvis when it reads
    local ours = {}
    for _, ring in ipairs(K.rings()) do
        for _, r in ipairs(ring) do
            local a = type(r) == 'table' and ue.addr(r.obj) or nil
            if a then ours[a] = true end
        end
    end
    LAB.oneshot()
    local t0 = K.now()
    local res, err = LAB.armed('grey.census', function()
        local list, info = ue.find_all('DecalComponent', G.CAP, 'grey')
        if not list then error(tostring(info), 0) end
        local out = { n = info.n, capped = info.capped, ours = 0, far = 0, bad = 0, near = {} }
        for _, d in ipairs(list) do
            local a = ue.addr(d)
            if a and ours[a] then out.ours = out.ours + 1
            else
                local ok, e = pcall(decal_read, d, pts, c0, foot)
                if not ok then out.bad = out.bad + 1
                elseif e == nil then out.far = out.far + 1
                else out.near[#out.near + 1] = e end
            end
        end
        return out
    end)
    local near = res and res.near or {}
    table.sort(near, function(a, b) return a.fit < b.fit end)
    local n_in, list = 0, {}
    for _, e in ipairs(near) do if e.inside then n_in = n_in + 1 end end
    for i = 1, math.min(#near, math.max(G.LIST, n_in)) do list[i] = near[i] end
    LAB.rec('grey_census', { tag = tag, err = err and tostring(err):sub(1, 160) or nil, decals = res and res.n,
        capped = res and res.capped, ours = res and res.ours, far = res and res.far, unread = res and res.bad,
        near = #near, inside = n_in, list = list, parts = (G.parts(pawn)), weather = weather(pawn),
        recv_want = st.recv_want, ovl = st.ovl.on, soul = { x = r1(c0.x), y = r1(c0.y), z = r1(c0.z), foot_z = r1(foot) },
        world = K.name_of(ue.world()), ms = math.floor((K.now() - t0) * 1000 + 0.5) }, true)
end

-- ---------- 'soul_recv': Soul's 13 parts to a receive flag (header) ----------
-- Each part that reads otherwise is switched (receives_on's call under 'blood.recv'); the pawn is then marked done
-- for receives_on. One soul_recv record
function G.recv_apply(want, why)
    local pawn = K.pawn()
    if not pawn then LAB.rec('soul_recv', { want = want, asked = st.recv_want, why = why, err = 'no_pawn' }, true) return end
    local _, comps = G.parts(pawn)
    local before, after, n, err = {}, {}, 0, nil
    for _, c in ipairs(comps) do
        local r = ue.get(c, 'bReceivesDecals')
        before[#before + 1] = r
        if r ~= want and not K.stopped('blood.recv') then
            local ok, e = LAB.hot('blood.recv', function()
                ue.count_write()
                c:SetReceivesDecals(want)
                return true
            end)
            if ok then n = n + 1 K.worked('blood.recv') else K.failed('blood.recv', e) err = e end
        end
        after[#after + 1] = ue.get(c, 'bReceivesDecals')
    end
    K.mark_recv(pawn)
    LAB.rec('soul_recv', { want = want, asked = st.recv_want, why = why, meshes = #comps, switched = n,
        before = before, after = after, err = err and tostring(err):sub(1, 160) or nil }, true)
end
-- lab_blood's on_player asks before it switches Soul's parts on: the wish, and never while the overlay is on
function G.recv_ok() return st.recv_want == true and not st.ovl.on end

-- ---------- 'soul_ovl': route A3 on Soul (header) ----------
-- One overlay call: the first of each name armed, then hot; a failure fails the overlay closed for the session with
-- one blood_ovl_fail record. restore: the off path runs past an earlier failure of another name
local function ovl_call(name, fn, restore)
    local o = st.ovl
    if o.dead and not (restore and o.dead ~= name) then return nil, 'failed_before' end
    local r, err
    if o.ran[name] then r, err = LAB.hot(name, fn)
    else
        o.ran[name] = true
        r, err = LAB.armed(name, fn)
    end
    if r == nil then
        if not o.dead then
            o.dead = name
            LAB.rec('blood_ovl_fail', { name = name, err = tostring(err or 'no_answer'):sub(1, 160) }, true)
        end
        return nil, err or 'no_answer'
    end
    return r
end
local function tb_live()
    local t = st.ovl.tb
    if type(t) ~= 'table' then return nil end
    if t.full then return (ue.live_mod(t)) end
    return (ue.live(t))
end
-- Step 1, blood_ovl_probe: once per pawn, before any write (header)
local function probe(pawn, s, comps)
    local o = st.ovl
    local key = ue.addr(pawn)
    if key ~= nil and o.probed == key then return end
    o.probed = key
    local tbm, dt = ue.get(s, 'TranslucentBlendMaterial'), ue.get(s, 'DataTarget')
    local rec = { sampler = { mesh = K.name_of(ue.get(s, 'Mesh')), locations = count(ue.get(s, 'DecalLocations')),
        empty = count(ue.get(s, 'EmptyIndexes')), layer = ue.get(s, 'LayerIndex'), association = ue.get(s, 'Association'),
        additional = ue.get(s, 'AdditionalData'), materials = count(ue.get(s, 'Materials')),
        last = ue.get(s, 'LastDecalIndex'), max = ue.get(s, 'MaxDecals'), min_dist = r2(ue.get(s, 'MinDecalDistance')),
        tb = ue.get(s, 'TranslucentBlend'), tb_mat = ue.valid(tbm) and ue.full(tbm) or 'none',
        tb_mid = ue.valid(ue.get(s, 'TranslucentBlendMaterialDynamic')),
        render_meshes = count(ue.get(s, 'RenderMeshes')),
        dt = ue.valid(dt) and { x = ue.get(dt, 'SizeX'), y = ue.get(dt, 'SizeY'), fmt = ue.get(dt, 'RenderTargetFormat') }
            or 'none' } }
    local m = ue.valid(tbm) and tbm or ue.find(G.OVL.TB)
    local flags = {}
    if m then for _, k in ipairs(G.OVL.FLAGS) do flags[k] = ue.get(m, k) end end
    rec.tb_class, rec.tb_flags = class_of(m), m and flags or 'none'
    ovl_call('blood.ovl.read', function()
        local cv, parts = {}, {}
        for _, n in ipairs(G.OVL.CVARS) do cv[n] = ue.cvar_int(n) end
        for _, c in ipairs(comps) do
            parts[#parts + 1] = { name = ue.name(c) or '?', class = class_of(c),
                overlay = K.name_of(ue.p(c:GetOverlayMaterial())), recv = ue.get(c, 'bReceivesDecals'),
                asset = K.name_of(ue.get(c, 'SkinnedAsset')), leader = K.name_of(ue.weak(ue.get(c, 'LeaderPoseComponent'))) }
        end
        rec.cvars, rec.parts = cv, parts
        return true
    end)
    LAB.rec('blood_ovl_probe', rec, true)
end
-- ON (header steps 1-4): one blood_ovl_on record, ok false with the step that refused
local function ovl_on()
    local o = st.ovl
    if o.on then return end
    local function no(why) LAB.rec('blood_ovl_on', { ok = false, err = why }, true) end
    if o.dead then return no('failed_before:' .. o.dead) end
    if not (MODOFF.enabled('lab_blood') and K.blood_on()) then return no('off') end
    local pawn = K.pawn()
    local mesh = pawn and ue.get(pawn, 'Mesh') or nil
    local s = pawn and ue.get(pawn, 'SkinnedDecalSampler') or nil
    if not ue.valid(mesh) then return no('no_pawn') end
    if not ue.valid(s) then return no('no_sampler') end
    local B = K.B
    local _, comps = G.parts(pawn)
    probe(pawn, s, comps)
    if o.dead then return no('probe') end
    local rt = ovl_call('blood.ovl.setup', function()
        local m0 = ue.get(s, 'Mesh')
        if ue.valid(m0) and not ue.same(m0, mesh) then error('sampler_holds:' .. tostring(ue.name(m0)), 0) end
        if not (ue.same(m0, mesh) and count(ue.get(s, 'Materials')) > 0) then
            local key = ue.addr(pawn)
            if key ~= nil and key == o.setup then error('setup_once', 0) end
            o.setup = key
            if not ue.valid(m0) and not ue.valid(ue.get(s, 'DataTarget')) then
                ue.set(s, 'MaxDecals', G.OVL.MAX)
                ue.set(s, 'MinDecalDistance', G.OVL.MIN_DIST)
            end
            ue.count_write()
            s:SetMeshComponent(mesh, false)
        end
        local t = ue.get(s, 'DataTarget')
        if not ue.valid(t) then t = ue.p(s:GetDataTarget()) end
        local max = ue.get(s, 'MaxDecals')
        if not ue.same(ue.get(s, 'Mesh'), mesh) then error('mesh_not_set', 0) end
        if count(ue.get(s, 'Materials')) < 1 then error('no_materials', 0) end
        if not (num(max) and max >= 1 and max <= B.MAX_DECALS_CAP) then error('max_decals', 0) end
        if not ue.valid(t) then error('no_data_target', 0) end
        return t
    end)
    if not rt then return no('setup') end
    local pc = ue.first_of('PlayerController')
    local mid = ovl_call('blood.ovl.mid', function()
        local tbm = ue.get(s, 'TranslucentBlendMaterial')
        if not ue.valid(tbm) then tbm = ue.find(G.OVL.TB) end
        local kmat = ue.cdo('kmat')
        if not (ue.valid(tbm) and kmat) then error('no_tb_material', 0) end
        ue.count_write()
        local m = ue.p(kmat:CreateDynamicMaterialInstance(pawn, tbm, ue.fname('None'), 0))
        if not ue.valid(m) then error('no_mid', 0) end
        local hid, hwhy = nil, 'no_controller'
        if pc then hid, hwhy = ue.hold(pc, m, 'material') end
        o.hold, o.hold_why = hid, hid == nil and tostring(hwhy) or nil
        m:SetScalarParameterValue(ue.fname('DecalMax'), 5.0 * ue.get(s, 'MaxDecals'))
        m:SetTextureParameterValue(ue.fname('DecalInfo'), rt)
        m:SetScalarParameterValue(ue.fname('DecalLast'), count(ue.get(s, 'DecalLocations')) + 0.0)
        local looks = 0
        for _, pair in ipairs(B.LOOK) do
            local tex = K.texture(pair[2])
            if tex then
                m:SetTextureParameterValue(ue.fname(pair[1]), tex)
                looks = looks + 1
            end
        end
        o.looks = looks
        return m
    end)
    if not mid then return no('mid') end
    o.s, o.tb, o.on = ue.keep(s), ue.keep_mod(mid) or ue.keep(mid), true
    local params = { textures = {}, scalars = {} }
    ovl_call('blood.ovl.read', function()
        local names = { 'DecalInfo' }
        for _, n in ipairs(B.LOOK_PROBE) do names[#names + 1] = n end
        for _, n in ipairs(names) do
            local t = ue.p(mid:K2_GetTextureParameterValue(ue.fname(n)))
            if ue.valid(t) then params.textures[#params.textures + 1] = n .. '=' .. K.name_of(t) end
        end
        for _, n in ipairs(G.OVL.SCALARS) do
            local v = ue.p(mid:K2_GetScalarParameterValue(ue.fname(n)))
            if num(v) and v ~= 0 then params.scalars[#params.scalars + 1] = n .. '=' .. tostring(r2(v)) end
        end
        return true
    end)
    local skipped, names, back = {}, {}, {}
    ovl_call('blood.ovl.set', function()
        for _, c in ipairs(comps) do
            local nm = ue.name(c)
            if nm and G.OVL.PARTS[nm] then
                local prev = ue.p(c:GetOverlayMaterial())
                if ue.valid(prev) then skipped[#skipped + 1] = nm .. '=' .. K.name_of(prev)
                else
                    ue.count_write()
                    c:SetOverlayMaterial(mid)
                    o.parts[#o.parts + 1] = { rec = ue.keep(c), name = nm }
                    names[#names + 1] = nm
                end
            end
        end
        return true
    end)
    ovl_call('blood.ovl.read', function()
        for _, p in ipairs(o.parts) do
            local c = ue.live(p.rec)
            back[#back + 1] = p.name .. '=' .. (c and (ue.same(ue.p(c:GetOverlayMaterial()), mid) and 'ours' or 'other')
                or 'gone')
        end
        return true
    end)
    G.recv_apply(false, 'ovl_on')
    LAB.rec('blood_ovl_on', { ok = o.dead == nil, err = o.dead, parts = names, skipped = skipped, readback = back,
        max = ue.get(s, 'MaxDecals'), min_dist = r2(ue.get(s, 'MinDecalDistance')),
        materials = count(ue.get(s, 'Materials')), render_meshes = count(ue.get(s, 'RenderMeshes')),
        rt = { x = ue.get(rt, 'SizeX'), y = ue.get(rt, 'SizeY') }, looks = o.looks, hold = o.hold ~= nil,
        hold_why = o.hold_why, mid = K.name_of(mid), params = params }, true)
end
-- OFF (header): our overlay away where it still is ours, the hold released, receive back to the wish; false when off
local function ovl_off(why)
    local o = st.ovl
    if not o.on then return false end
    o.on = false
    local mid = tb_live()
    local restored, left = 0, {}
    ovl_call('blood.ovl.set', function()
        for _, p in ipairs(o.parts) do
            local c = ue.live(p.rec)
            if c and mid then
                if ue.same(ue.p(c:GetOverlayMaterial()), mid) then
                    ue.count_write()
                    c:SetOverlayMaterial(nil)
                    restored = restored + 1
                else left[#left + 1] = p.name end
            end
        end
        if o.hold then ue.release(o.hold) end
        return true
    end, true)
    o.parts, o.tb, o.hold = {}, nil, nil
    G.recv_apply(st.recv_want, 'ovl_off')
    LAB.rec('blood_ovl_off', { why = why, restored = restored, left = left, decals = o.sent, rejected = o.rejected,
        failed = o.dead }, true)
    return true
end
-- One overlay splash (header): the bone spot pushed toward the victim (tx, ty) and jittered, SpawnDecal, DecalLast
local function splash(mesh, bone, bp, tx, ty)
    local o = st.ovl
    if o.budget <= 0 then LAB.count('blood_ovl_budget') return end
    local s, mid = o.s and ue.live(o.s) or nil, tb_live()
    if not (s and mid and ue.same(ue.get(s, 'Mesh'), mesh)) then LAB.count('blood_ovl_skip') return end
    local B = K.B
    local last, max, mind = ue.get(s, 'LastDecalIndex'), ue.get(s, 'MaxDecals'), ue.get(s, 'MinDecalDistance')
    if not (num(max) and max >= 1 and max <= B.MAX_DECALS_CAP and num(last) and last >= -1
            and last < B.MAX_DECALS_CAP) or count(ue.get(s, 'Materials')) < 1 then
        LAB.count('blood_ovl_skip')
        return
    end
    o.budget = o.budget - 1
    local l = math.sqrt(tx * tx + ty * ty)
    local px, py = 0, 0
    if num(l) and l > 1e-3 then px, py = tx / l * G.OVL.PUSH, ty / l * G.OVL.PUSH end
    local j = math.max(G.OVL.JITTER, num(mind) and mind > 0 and 1.5 * math.sqrt(mind) or 0)
    local function jit() return (math.random() * 2 - 1) * j end
    local p = ue.vec(bp.x + px + jit(), bp.y + py + jit(), bp.z + jit())
    local size = math.max(B.SIZE_MIN, math.min(B.SIZE_MAX, G.OVL.SIZE * (0.8 + 0.4 * math.random())))
    local sub = math.random(0, B.SUBUV_MAX)
    local idx = ovl_call('blood.ovl.decal', function()
        ue.count_write()
        K.ours(true)
        local ok, r = pcall(function()
            -- lint:allow L015 guarded above: Soul's own set-up sampler on CharacterMesh0 (never AutoSetup), Materials > 0, MaxDecals 1..32767, a bone of that mesh, 4 a frame, the first call armed
            return ue.p(s:SpawnDecal(p, { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, ue.vec(1, 1, 1), ue.fname(bone),
                size + 0.0, sub, -1))
        end)
        K.ours(false)
        if not ok then error(r, 0) end
        mid:SetScalarParameterValue(ue.fname('DecalLast'), count(ue.get(s, 'DecalLocations')) + 0.0)
        return math.type(r) == 'integer' and r or -2
    end)
    if idx == nil then return end
    if idx < 0 then
        o.rejected = o.rejected + 1
        LAB.count('blood_ovl_rejected')
        return
    end
    o.sent = o.sent + 1
    LAB.count('blood_ovl_decals')
    if o.rt_idx == nil and not o.rt_done then o.rt_idx = idx end
end
-- lab_blood's on_player, each Soul splash: nothing unless the overlay is on; a raise is one grey_error record and
-- fails the overlay closed, never out of lab_blood's ticker
function G.splash(mesh, bone, bp, tx, ty)
    local o = st.ovl
    if not (st.init and o.on) or o.dead then return end
    local ok, err = pcall(splash, mesh, bone, bp, tx, ty)
    if not ok then
        o.dead = o.dead or 'splash'
        LAB.rec('grey_error', { verb = 'soul_ovl', where = 'splash', err = tostring(err):sub(1, 200) }, true)
    end
end
-- The first accepted slot's texels, once (header)
local function ovl_rt()
    local o = st.ovl
    o.rt_done = true
    local s = o.s and ue.live(o.s) or nil
    local rt = s and ue.get(s, 'DataTarget') or nil
    local krl, pawn = ue.cdo('krl'), K.pawn()
    if not (ue.valid(rt) and krl and pawn) then
        LAB.rec('blood_ovl_rt', { idx = o.rt_idx, err = 'unread' }, true)
        return
    end
    local sx = ue.get(rt, 'SizeX')
    local px = ovl_call('blood.ovl.rt', function()
        local out = {}
        for x = 5 * o.rt_idx, 5 * o.rt_idx + G.OVL.RT_N - 1 do
            if num(sx) and x >= sx then break end
            local c = ue.p(krl:ReadRenderTargetRawPixel(pawn, rt, x, 0, false))
            out[#out + 1] = c ~= nil and { r2(ue.prop(c, 'R')), r2(ue.prop(c, 'G')), r2(ue.prop(c, 'B')),
                r2(ue.prop(c, 'A')) } or 'none'
        end
        return out
    end)
    LAB.rec('blood_ovl_rt', { idx = o.rt_idx, size_x = sx, px = px, err = px == nil and (o.dead or 'failed') or nil },
        true)
end
-- Every WATCH_S unpaused (header): each part's overlay; one lost to nothing is set again; a record on a change
local function ovl_watch()
    local o = st.ovl
    local t = K.now()
    if t < o.watch_t then return end
    o.watch_t = t + G.OVL.WATCH_S
    local mid = tb_live()
    if not mid then
        if not o.lost then
            o.lost = true
            LAB.rec('blood_ovl_watch', { err = 'mid_gone', decals = o.sent }, true)
        end
        return
    end
    local words, again = {}, {}
    ovl_call('blood.ovl.read', function()
        for _, p in ipairs(o.parts) do
            local c = ue.live(p.rec)
            if not c then words[#words + 1] = p.name .. '=gone'
            else
                local ov = ue.p(c:GetOverlayMaterial())
                if ue.same(ov, mid) then words[#words + 1] = p.name .. '=ours'
                elseif ue.valid(ov) then words[#words + 1] = p.name .. '=' .. K.name_of(ov)
                else
                    words[#words + 1] = p.name .. '=none'
                    again[#again + 1] = c
                end
            end
        end
        return true
    end)
    if again[1] then
        ovl_call('blood.ovl.set', function()
            for _, c in ipairs(again) do
                ue.count_write()
                c:SetOverlayMaterial(mid)
            end
            return true
        end)
    end
    local sig = table.concat(words, ' ')
    if (sig ~= o.watch_sig or again[1]) and o.watch_n < G.OVL.WATCH_N then
        o.watch_sig, o.watch_n = sig, o.watch_n + 1
        local s = o.s and ue.live(o.s) or nil
        LAB.rec('blood_ovl_watch', { parts = words, reapplied = #again, decals = o.sent, rejected = o.rejected,
            stored = s and count(ue.get(s, 'DecalLocations')) or nil }, true)
    end
end
local function ovl_step()
    local o = st.ovl
    if not (MODOFF.enabled('lab_blood') and K.blood_on()) then ovl_off('off') return end
    o.budget = G.OVL.PER_FRAME
    if o.dead then return end
    if o.rt_idx ~= nil and not o.rt_done then ovl_rt() end
    if not LAB.paused() then ovl_watch() end
end

-- ---------- the queue and the console ----------
local function run(r)
    if r.verb == 'grey' then census(r.arg)
    elseif r.verb == 'soul_recv' then
        st.recv_want = r.arg == true
        G.recv_apply(st.recv_want and not st.ovl.on, 'console')
    elseif r.verb == 'soul_ovl' then
        if r.arg then ovl_on()
        elseif not ovl_off('console') then LAB.rec('blood_ovl_off', { why = 'console', err = 'not_on' }, true) end
    end
end
-- lab_blood's ticker, after lab_end's check: the jobs in the order typed, then the overlay's frame (budget, texels,
-- watch, the mod-off end)
function G.step()
    if not st.init then return end
    local q = st.q
    if q[1] then
        st.q = {}
        for _, r in ipairs(q) do
            local ok, err = pcall(run, r)
            if not ok then LAB.rec('grey_error', { verb = r.verb, err = tostring(err):sub(1, 200) }, true) end
        end
    end
    if not st.ovl.on then return end
    local ok, err = pcall(ovl_step)
    if not ok then
        st.ovl.dead = st.ovl.dead or 'step'
        LAB.rec('grey_error', { verb = 'soul_ovl', where = 'step', err = tostring(err):sub(1, 200) }, true)
    end
end
local function request(verb, arg)
    if not st.init or #st.q >= G.Q then return end
    st.q[#st.q + 1] = { verb = verb, arg = arg }
end
-- -> the reply line, and the job main.lua runs on the game thread (it only queues), or nil
function G.console(verb, arg)
    if not st.init then return verb .. ': not running in this build (no cut set)' end
    if K.ended and K.ended() then return verb .. ': not running after lab_end' end
    if verb == 'grey' then
        local tag = arg ~= nil and tostring(arg):sub(1, 24) or nil
        return 'grey census queued: record grey_census' .. (tag and (' tag ' .. tag) or '') .. ' in the log',
            function() request('grey', tag) end
    end
    if verb == 'soul_recv' then
        local a = arg ~= nil and tostring(arg):lower() or nil
        if a ~= 'on' and a ~= 'off' then return 'usage: soul_recv off|on (now ' .. (st.recv_want and 'on' or 'off') .. ')' end
        return 'Soul receives decals: ' .. a .. (a == 'off' and ' (his blood splashes stop drawing until on)' or '')
            .. (a == 'on' and st.ovl.on and ' after soul_ovl off (the overlay keeps it off)' or '')
            .. ': record soul_recv', function() request('soul_recv', a == 'on') end
    end
    if verb == 'soul_ovl' then
        local a, o = arg ~= nil and tostring(arg):lower() or nil, st.ovl
        local now_word = (o.on and 'on' or 'off') .. (o.dead and (', failed at ' .. o.dead) or '')
        if a ~= 'on' and a ~= 'off' then return 'usage: soul_ovl on|off (now ' .. now_word .. ')' end
        if a == 'on' and o.dead then
            return 'soul_ovl: failed earlier this session at ' .. o.dead .. ' (record blood_ovl_fail); off still restores'
        end
        return 'soul_ovl ' .. a .. (a == 'on' and ': the plugin overlay on Soul, his decal receive off'
            or ': overlay away, receive back') .. ' (records blood_ovl_*)', function() request('soul_ovl', a == 'on') end
    end
    return verb .. ': unknown'
end

-- ---------- lifecycle (lab_blood's) ----------
function G.bind(ctx)
    K = ctx
    st = new_state()
    st.init = type(ctx) == 'table'
    if not (st.init and type(ctx.verb) == 'function') then return end
    for _, v in ipairs(G.VERBS) do
        local name = v[1]
        ctx.verb(name, function(args) return G.console(name, type(args) == 'table' and args[2] or nil) end, v[2])
    end
end
-- A map load: the wish and the queue stay; the overlay ends (its objects went with the world; the hold ended in
-- ue.reset_caches), its failure stays for the session
function G.reset()
    if st.ovl.on then
        LAB.rec('blood_ovl_off', { why = 'map', decals = st.ovl.sent, rejected = st.ovl.rejected }, true)
    end
    st.ovl = new_ovl(st.ovl)
end
function G.status()
    return { recv_want = st.recv_want, queued = #st.q, ovl = st.ovl.on, ovl_failed = st.ovl.dead, ovl_decals = st.ovl.sent }
end
function G.shutdown() st, K = new_state(), nil end      -- engine-free

return G
