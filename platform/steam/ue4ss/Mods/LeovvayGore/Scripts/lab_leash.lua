-- status: new for the beta test build (offline only; the author's run decides) origin: docs/research/grey-under-trees.md
-- fix 1, the world-decal depth leash (the author 2026-11-01: «let's try both options, yes»)
-- lab_leash.lua: Soul goes grey in tree shade since lab_blood switches his 13 skinned parts to receive decals
-- (lab_blood.lua receives_on). The suspected cause [inferred, grey-under-trees.md]: the world's deferred decals project
-- their deep boxes onto him (57 of the 64 DecalComponents of the object dump are BP_ErosionDecal_C 'Decal' components:
-- dirt, puddles, erosion; scratch/soul-blood/grey_agents.md). UDecalComponent has no receiver filter
-- (CXXHeaderDump/Engine.hpp:15059-15086), so this caps the projection depth of the world's decals instead: the ground
-- keeps its look within the cap of the decal plane, and Soul's torso, head and hat leave the box.
-- Player beta and the author's test build (META.beta_modules, after lab_blood); inert unless LAB.cut_set(). Off by
-- default and for the session only: console '<prefix> leash on|off' (MAIN.verb); '<prefix> leash' tells the state.
-- * The cap: cm, the knob leash_cm ('<prefix> set leash_cm 40': a top-level settings key read here every tick, clamped
--   CM_LO..CM_HI, default CM_DEFAULT 35). A change while capped restores every capped decal, then caps again at the new
--   value (pass 'cm').
-- * The registry: one ue.find_all('DecalComponent', FIND_CAP) when the leash goes on, after each map load (warm) and
--   every SCAN_S while on (never while paused, never while the previous list is still walked). The list is walked
--   CHEAP_N a frame in one 'leash.read' call: a decal whose AttachParent is a SkinnedMeshComponent (Soul's splashes and
--   the victims' clothes decals: lab_blood's st.pring and st.adecal_ring) only counts (skipped skinned); every other
--   new one goes to the classify queue, PER_FRAME a frame, one 'leash.read' call each, which reads GetOwner, the owner's
--   class and IsA, DecalMaterial (and a MID's Parent), DecalSize, FadeScreenSize, K2_GetComponentScale,
--   K2_GetComponentLocation and K2_GetComponentRotation, and skips:
--   - 'no_owner' (GetOwner none: templates, CDOs), 'pawn' (owned by a Pawn or a Character), 'ours' (owned by
--     WorldSettings and drawing one of lab_blood's decal materials, B.ADECAL_MATS or B.POOL_MAT: its ground pools,
--     whose SpawnDecalAtLocation owner is WorldSettings, adapter/ue.lua ue.spawn_decal), 'unread' (DecalSize, the
--     scale or FadeScreenSize unread), 'bad_scale' (|scale.X| under SCALE_MIN), 'shallow' (DecalSize.X x |scale.X|,
--     the world half-depth, at or under cm + EPS: nothing to cap);
--   - every other decal is capped once, one 'leash.write' call: DecalSize = (cm / |scale.X|, Y, Z) written through the
--     property (a full table: UE4SS convert_lua_table_to_struct writes it in place), read back, then
--     SetFadeScreenSize(<its own FadeScreenSize>). That setter's thunk (PBZ.exe 0x143D7CCF0) stores unconditionally
--     and calls 0x143CD47A0, which sets the render-state dirty bit of a registered component (MarkRenderStateDirty
--     [inferred]), so the proxy is rebuilt; that the rebuild reads DecalSize is [inferred] from UE source
--     (FDeferredDecalProxy takes GetTransformIncludingDecalSize). A failure after the size write writes the original
--     back in the same call. The original (X, Y, Z exactly as read) and the cap are kept with ue.keep_mod (full name,
--     epoch).
--   A known decal (by address, while ue.live_mod holds) is never classified again. A capped one is read again after
--   each scan (DecalSize.X, CHECK_N a frame): a value other than the cap means the game wrote it (a construction
--   script [unknown]): that value is the new original and the decal is capped again (changed). A capped decal the scan
--   did not see and that is no longer live went with its World Partition cell (gone): a reloaded cell brings a new
--   object with its package size.
-- * Restore: the leash off, mod-off and the vanilla compare (MODOFF feature 'lab_leash', gameplay), settings enabled
--   false, a leash_cm change and lab_end restore every capped decal, RESTORE_N a frame, one 'leash.restore' call each:
--   DecalSize back to the kept (X, Y, Z), read back, SetFadeScreenSize(<its own>). A decal whose X no longer reads the
--   cap keeps what the game wrote (changed); one no longer live is gone. After lab_end the module stops for the
--   session. A map load makes no engine call: the old world's decals went with it and the new map's come from their
--   packages with their own sizes, so the records drop (dropped) and the next scan registers the new map's decals. A
--   Ctrl+R hot reload is engine-free (shutdown): a decal capped then stays capped until the next map load.
-- * Guards: every native call runs under its own sentinel name (META.lab_risky, lingers in META.lab_linger):
--   leash.find (FindAllOf), leash.read (the reads above, the cheap walk, the live checks, Soul's GetSocketLocation),
--   leash.write, leash.restore, all through LAB.hot. Fail closed: a name the sentinel disabled keeps the leash down
--   with one leash_refused record (a disabled restore included: nothing is ever capped then), and in the beta nothing
--   runs before LAB.pinned() reads true (false: one leash_refused, why 'unpinned'). Breaker per kind: FAIL_MAX failures
--   in a row stop that kind for the map (one leash_off record): no more scans, reads or caps; a stopped restore leaves
--   the rest capped (stuck in the record) until the map load, and so does a decal whose own restore failed FAIL_MAX
--   times.
-- * Records: leash once per change (why 'on', 'off', 'modoff', 'vanilla', 'disabled', 'cm', 'lab_end', 'map', and
--   'scan' when a rescan capped, lost or saw a changed decal): { why, cm, capped (now), world (registered), new,
--   restored, changed, gone, failed, stuck, dropped, skipped = { reason = n }, scan = { n, capped, ms }, feet_z };
--   leash_decal once per world decal per session (by full name, LIST_MAX at most; never a skinned one): { why
--   ('capped' or the skip reason), comp, owner (class), actor, mat, parent (a MID's), size, scale, pitch, depth_cm
--   (the world half-depth), new_cm, z_feet (the decal origin above Soul's lower foot bone, cm; 'unread' without
--   Soul), dist_m (horizontal, to Soul) }; leash_off, leash_refused. Counters leash_capped, leash_restored, leash_fail.
-- What the mock cannot prove: that the rebuilt proxy draws the new depth, how a capped decal looks on slopes and rocks
-- (ground coverage lost where the surface lies farther than cm from the decal origin), the scan's cost with thousands
-- of Soul's splashes alive (the record's scan.ms tells).
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local MODOFF = require('core.modoff')
local C = require('core.config')
local SENT = require('core.sentinel')
local ue = require('adapter.ue')
local LAB = require('lab_probe')

local M = {
    CM_DEFAULT = 35, CM_LO = 10, CM_HI = 200, EPS = 0.5, SCALE_MIN = 0.001, BACK_EPS = 1e-3,
    FIND_CAP = 8192, SCAN_S = 10, CHEAP_N = 128, PER_FRAME = 4, CHECK_N = 16, RESTORE_N = 8, FAIL_MAX = 3,
    LIST_MAX = 180, FEET_S = 2,
    NAMES = { 'leash.find', 'leash.read', 'leash.write', 'leash.restore' },
    SKINNED = '/Script/Engine.SkinnedMeshComponent', PAWN = '/Script/Engine.Pawn',
    WORLD_SETTINGS = '/Script/Engine.WorldSettings',
    FEET = { 'foot_l', 'foot_r' },
    COUNTERS = { 'leash_capped', 'leash_restored', 'leash_fail' },
}

local A = nil
local function new_state()
    return { init = false, want = false, active = false, ended = false, end_due = false, down = nil, cm = nil,
        reg = {}, ncap = 0, nstuck = 0, scanq = nil, si = 1, scan_id = 0, next_scan = 0, scan_due = false, classq = {},
        checkq = {}, pass = nil, logged = {}, nlogged = 0, fails = {}, off = {}, refused = {}, pawn = nil, feet = nil,
        feet_t = nil, ours = nil, err = nil }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or os.clock() end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function r1(v) return num(v) and math.floor(v * 10 + 0.5) / 10 or nil end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function short(path) return type(path) == 'string' and (path:match('([^/.]+)$') or path) or nil end
-- {x, y, z} from an engine vector (X/Y/Z) or a plain one; nil unless three finite numbers
local function xyz(v)
    v = ue.p(v)
    if v == nil then return nil end
    local x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z')
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
local function v3(p) return p and { x = r1(p.x), y = r1(p.y), z = r1(p.z) } or nil end
local function near(a, b) return num(a) and num(b) and math.abs(a - b) <= M.BACK_EPS * math.max(1, math.abs(b)) end

-- The cap in cm: the knob leash_cm, clamped; CM_DEFAULT when unset or not a number
local function cap_cm()
    local ok, s = pcall(C.get)
    local v = ok and type(s) == 'table' and tonumber(s.leash_cm) or nil
    if not num(v) then return M.CM_DEFAULT end
    return clamp(v, M.CM_LO, M.CM_HI)
end

-- ---------- the breaker: a kind stops for the map after FAIL_MAX failures in a row ----------
local function stopped(k) return st.off[k] == true end
local function failed(k, err)
    local n = (st.fails[k] or 0) + 1
    st.fails[k] = n
    if err ~= nil then st.err = tostring(err):sub(1, 160) end
    if st.pass then st.pass.failed, st.pass.dirty = st.pass.failed + 1, true end
    LAB.count('leash_fail')
    if n >= M.FAIL_MAX and not st.off[k] then
        st.off[k] = true
        LAB.rec('leash_off', { name = k, fails = n, err = st.err }, true)
    end
end
local function worked(k) st.fails[k] = 0 end
-- One leash_refused record per why and name for the session
local function refuse(why, name)
    local k = why .. '|' .. tostring(name)
    if st.refused[k] then return end
    st.refused[k] = true
    LAB.rec('leash_refused', { why = why, name = name, err = st.err }, true)
end
-- nil when the native calls may run; else why ('pin_wait' writes nothing: the beta's pin check is still to come)
local function gate()
    if LAB.beta() then
        local p = LAB.pinned()
        if p == nil then return 'pin_wait' end
        if p ~= true then refuse('unpinned') return 'unpinned' end
    end
    for _, n in ipairs(M.NAMES) do
        if SENT.is_disabled(n) then refuse('disabled', n) return 'disabled' end
    end
    return nil
end

-- ---------- one change, one leash record ----------
local function new_pass(why, force)
    return { why = why, force = force == true, dirty = false, new = 0, restored = 0, changed = 0, gone = 0, failed = 0,
        dropped = nil, skipped = {}, scan = nil }
end
local function world_n()
    local n = 0
    for _ in pairs(st.reg) do n = n + 1 end
    return n
end
local function close()
    local p = st.pass
    st.pass = nil
    if not p or not (p.force or p.dirty) then return end
    local stuck = st.nstuck > 0 and st.nstuck or nil
    if st.ncap > 0 and not st.active then stuck = (stuck or 0) + st.ncap end
    LAB.rec('leash', { why = p.why, cm = st.cm or cap_cm(), capped = st.ncap, world = world_n(), new = p.new,
        restored = p.restored, changed = p.changed, gone = p.gone, failed = p.failed, stuck = stuck,
        dropped = p.dropped, skipped = p.skipped, scan = p.scan, feet_z = st.feet and r1(st.feet.z) or 'unread',
        err = p.failed > 0 and st.err or nil }, true)
end
local function open(why, force)
    if st.pass then close() end
    st.pass = new_pass(why, force)
end
local function skipped(why, n)
    if not st.pass or (n or 1) <= 0 then return end
    st.pass.skipped[why] = (st.pass.skipped[why] or 0) + (n or 1)
end
-- A capped decal that is no longer live: its count goes
local function gone(key)
    local e = st.reg[key]
    st.reg[key] = nil
    if e and e.capped then
        st.ncap = st.ncap - 1
        if st.pass then st.pass.gone, st.pass.dirty = st.pass.gone + 1, true end
    end
end

-- ---------- reads (inside 'leash.read') ----------
-- lab_blood's decal materials by short name (its ground pools): read once from the loaded module, none without it
local function ours_set()
    if st.ours then return st.ours end
    local out, B = {}, package.loaded.lab_blood
    if type(B) == 'table' then
        for _, p in ipairs(type(B.ADECAL_MATS) == 'table' and B.ADECAL_MATS or {}) do
            local n = short(p)
            if n then out[n] = true end
        end
        local n = short(B.POOL_MAT)
        if n then out[n] = true end
    end
    st.ours = out
    return out
end
-- Soul's lower foot bone in the world (GetSocketLocation), read again at most every FEET_S; nil without a live pawn
local function feet_read()
    local t = now()
    if st.feet_t and t - st.feet_t < M.FEET_S then return st.feet end
    st.feet_t, st.feet = t, nil
    local pawn = st.pawn and ue.live(st.pawn) or nil
    local mesh = pawn and ue.get(pawn, 'Mesh') or nil
    if not ue.valid(mesh) then return nil end
    local lo = nil
    for _, b in ipairs(M.FEET) do
        local ok, v = ue.call(mesh, 'GetSocketLocation', ue.fname(b))
        local p = ok and xyz(v) or nil
        if p and (lo == nil or p.z < lo.z) then lo = p end
    end
    st.feet = lo
    return lo
end
local function class_of(o)
    local full = ue.full(o)
    return type(full) == 'string' and full:match('^(%S+)') or 'unread'
end
-- Everything one decal's decision needs: d.why is the skip reason, nil for a decal to cap
local function read_decal(c)
    local d = { keep = ue.keep_mod(c), comp = ue.name(c) }
    feet_read()
    local owner = ue.owner(c)
    if not owner then d.why = 'no_owner' return d end
    d.owner, d.actor = class_of(owner), ue.name(owner)
    if ue.is_a(owner, M.PAWN) == true then d.why = 'pawn' end
    local mat = ue.get(c, 'DecalMaterial')
    d.mat = ue.valid(mat) and ue.name(mat) or 'none'
    local parent = ue.valid(mat) and ue.get(mat, 'Parent') or nil
    if ue.valid(parent) then d.parent = ue.name(parent) end
    if not d.why and ours_set()[d.mat] and ue.is_a(owner, M.WORLD_SETTINGS) == true then d.why = 'ours' end
    d.size = xyz(ue.get(c, 'DecalSize'))
    local oks, sc = ue.call(c, 'K2_GetComponentScale')
    d.scale = oks and xyz(sc) or nil
    local okl, loc = ue.call(c, 'K2_GetComponentLocation')
    d.loc = okl and xyz(loc) or nil
    local okr, rot = ue.call(c, 'K2_GetComponentRotation')
    d.pitch = okr and r1(ue.prop(ue.p(rot), 'Pitch')) or nil
    d.fss = ue.get(c, 'FadeScreenSize')
    if d.why then return d end
    if not (d.size and d.scale and num(d.fss)) then d.why = 'unread' return d end
    d.sx = math.abs(d.scale.x)
    if d.sx < M.SCALE_MIN then d.why = 'bad_scale' return d end
    d.depth = math.abs(d.size.x) * d.sx
    if d.depth <= st.cm + M.EPS then d.why = 'shallow' end
    return d
end
-- The per-decal list: one leash_decal record per world decal per session
local function list_one(d, new_cm)
    if st.nlogged >= M.LIST_MAX then return end
    local full = d.keep and d.keep.full
    if not full or st.logged[full] then return end
    st.logged[full], st.nlogged = true, st.nlogged + 1
    local r = { why = d.why or 'capped', comp = d.comp, owner = d.owner, actor = d.actor, mat = d.mat,
        parent = d.parent, size = v3(d.size), scale = v3(d.scale), pitch = d.pitch, depth_cm = r1(d.depth),
        new_cm = r1(new_cm), z_feet = 'unread' }
    local f = st.feet
    if d.loc and f then
        local dx, dy = d.loc.x - f.x, d.loc.y - f.y
        r.z_feet, r.dist_m = r1(d.loc.z - f.z), r1(math.sqrt(dx * dx + dy * dy) / 100)
    end
    LAB.rec('leash_decal', r, true)
end

-- ---------- writes ----------
local function size_tbl(x, y, z) return { X = x + 0.0, Y = y + 0.0, Z = z + 0.0 } end
-- DecalSize.X to the cap, read back, then the proxy rebuilt through SetFadeScreenSize(<its own>); any failure after the
-- write puts the original back. true | nil, why
local function cap_write(c, d, nx)
    return LAB.hot('leash.write', function()
        ue.count_write(2)
        c.DecalSize = size_tbl(nx, d.size.y, d.size.z)
        local back = ue.prop(ue.get(c, 'DecalSize'), 'X')
        local ok, err = near(back, nx), 'readback ' .. tostring(back)
        if ok then
            ok, err = pcall(function() c:SetFadeScreenSize(d.fss + 0.0) end)
        end
        if not ok then
            pcall(function() c.DecalSize = size_tbl(d.size.x, d.size.y, d.size.z) end)
            error(err, 0)
        end
        return true
    end)
end
-- 'restored' | 'changed' (the game wrote another size: left as it is) | 'gone' (no longer live) | nil, why
local function restore_write(e)
    return LAB.hot('leash.restore', function()
        local c = ue.live_mod(e.keep)
        if not c then return 'gone' end
        local cur = ue.prop(ue.get(c, 'DecalSize'), 'X')
        if not num(cur) then error('size unread', 0) end
        if not near(cur, e.nx) then return 'changed' end
        local fss = ue.get(c, 'FadeScreenSize')
        if not num(fss) then error('fade size unread', 0) end
        ue.count_write(2)
        c.DecalSize = size_tbl(e.ox, e.oy, e.oz)
        local back = ue.prop(ue.get(c, 'DecalSize'), 'X')
        if not near(back, e.ox) then error('readback ' .. tostring(back), 0) end
        c:SetFadeScreenSize(fss + 0.0)
        return 'restored'
    end)
end

-- ---------- the steps (the lab ticker) ----------
local function scan()
    st.scan_due, st.next_scan = false, now() + M.SCAN_S
    if stopped('leash.find') or stopped('leash.read') then return end
    LAB.oneshot()
    local r, err = LAB.hot('leash.find', function()
        local list, info = ue.find_all('DecalComponent', M.FIND_CAP, 'lab_leash')
        if type(list) ~= 'table' then error(tostring(info), 0) end
        return { list = list, info = info }
    end)
    if not r then failed('leash.find', err) return end
    worked('leash.find')
    st.scanq, st.si, st.scan_id = r.list, 1, st.scan_id + 1
    if st.pass then
        local i = type(r.info) == 'table' and r.info or {}
        st.pass.scan = { n = i.n, capped = i.capped == true or nil, ms = r1(i.ms) }
    end
end
-- The capped decals the walk did not see: gone unless still live (FIND_CAP may have cut the list)
local function sweep()
    local r, err = LAB.hot('leash.read', function()
        local out = {}
        for key, e in pairs(st.reg) do
            if e.seen ~= st.scan_id and not ue.live_mod(e.keep) then out[#out + 1] = key end
        end
        return out
    end)
    if not r then failed('leash.read', err) return end
    for _, key in ipairs(r) do gone(key) end
end
-- CHEAP_N entries of the scan list: skinned ones counted, known ones checked live, the rest queued for classify
local function walk_step()
    local q = st.scanq
    if not q then return end
    if stopped('leash.read') then st.scanq = nil return end
    local r, err = LAB.hot('leash.read', function()
        local n, out = 0, { skinned = 0, new = {}, check = {}, lost = {} }
        while n < M.CHEAP_N and st.si <= #q do
            local c = q[st.si]
            st.si, n = st.si + 1, n + 1
            local key = ue.valid(c) and ue.addr(c) or nil
            local e = key and st.reg[key] or nil
            if e and not ue.live_mod(e.keep) then
                out.lost[#out.lost + 1] = key
                e = nil
            end
            if e then
                e.seen = st.scan_id
                if e.capped then out.check[#out.check + 1] = key end
            elseif key then
                local p = ue.get(c, 'AttachParent')
                if ue.valid(p) and ue.is_a(p, M.SKINNED) == true then out.skinned = out.skinned + 1
                else out.new[#out.new + 1] = c end
            end
        end
        return out
    end)
    if not r then
        failed('leash.read', err)
        return
    end
    worked('leash.read')
    for _, key in ipairs(r.lost) do gone(key) end
    skipped('skinned', r.skinned)
    for _, c in ipairs(r.new) do st.classq[#st.classq + 1] = c end
    for _, key in ipairs(r.check) do st.checkq[#st.checkq + 1] = key end
    if st.si > #q then
        st.scanq = nil
        sweep()
    end
end
local function classify(c)
    local key = ue.addr(c)
    if not key or st.reg[key] then return end
    local d, err = LAB.hot('leash.read', function() return read_decal(c) end)
    if not d then failed('leash.read', err) return end
    worked('leash.read')
    if not d.keep then skipped('unread') return end
    local e = { keep = d.keep, why = d.why, seen = st.scan_id }
    if d.why then
        skipped(d.why)
    else
        local nx = st.cm / d.sx
        local ok, werr = cap_write(c, d, nx)
        if not ok then failed('leash.write', werr) return end
        worked('leash.write')
        e.capped, e.ox, e.oy, e.oz, e.nx = true, d.size.x, d.size.y, d.size.z, nx
        st.ncap = st.ncap + 1
        LAB.count('leash_capped')
        if st.pass then st.pass.new, st.pass.dirty = st.pass.new + 1, true end
        d.new_cm = st.cm
    end
    st.reg[key] = e
    list_one(d, d.new_cm)
end
local function classify_step()
    if not st.classq[1] then return end
    if stopped('leash.read') or stopped('leash.write') then st.classq = {} return end
    for _ = 1, M.PER_FRAME do
        local c = table.remove(st.classq, 1)
        if not c then break end
        if ue.valid(c) then classify(c) end
    end
end
-- A capped decal read again: a size the game wrote is the new original, capped again (changed)
local function check_step()
    if not st.checkq[1] then return end
    if stopped('leash.read') then st.checkq = {} return end
    for _ = 1, M.CHECK_N do
        local key = table.remove(st.checkq, 1)
        if not key then break end
        local e = st.reg[key]
        if e and e.capped then
            local r, err = LAB.hot('leash.read', function()
                local c = ue.live_mod(e.keep)
                return { c = c, x = c and ue.prop(ue.get(c, 'DecalSize'), 'X') or nil }
            end)
            if not r then failed('leash.read', err) return end
            if not r.c then gone(key)
            elseif num(r.x) and not near(r.x, e.nx) then
                st.reg[key], st.ncap = nil, st.ncap - 1
                if st.pass then st.pass.changed, st.pass.dirty = st.pass.changed + 1, true end
                st.classq[#st.classq + 1] = r.c
            end
        end
    end
end
local function restore_step()
    local n = 0
    for key, e in pairs(st.reg) do
        if n >= M.RESTORE_N or stopped('leash.restore') then break end
        if e.capped then
            n = n + 1
            local r, err = restore_write(e)
            if not r then
                failed('leash.restore', err)
                e.rfail = (e.rfail or 0) + 1
                if e.rfail >= M.FAIL_MAX then             -- given up: it stays capped until the map load (stuck)
                    st.reg[key], st.ncap, st.nstuck = nil, st.ncap - 1, st.nstuck + 1
                end
            elseif r == 'gone' then
                gone(key)
            else
                worked('leash.restore')
                st.reg[key], st.ncap = nil, st.ncap - 1
                if st.pass then
                    if r == 'changed' then st.pass.changed = st.pass.changed + 1
                    else st.pass.restored = st.pass.restored + 1 end
                    st.pass.dirty = true
                end
                if r == 'restored' then LAB.count('leash_restored') end
            end
        end
    end
end

-- Why the leash is down now, nil when it may be on
local function down_why(cm)
    if st.end_due then return 'lab_end' end
    if not st.want then return 'off' end
    if MODOFF.is_off() then return 'modoff' end
    if not MODOFF.enabled('lab_leash') then return 'vanilla' end
    local ok, s = pcall(C.get)
    if ok and type(s) == 'table' and s.enabled == false then return 'disabled' end
    if (st.active or st.ncap > 0) and st.cm ~= nil and cm ~= st.cm then return 'cm' end
    return nil
end
local function tick()
    if not st.init or st.ended then return end
    local cm = cap_cm()
    local down = down_why(cm)
    if down then
        if st.active then
            st.active, st.down = false, down
            st.scanq, st.classq, st.checkq = nil, {}, {}
            open(down, true)
        end
        if st.ncap > 0 and not stopped('leash.restore') then restore_step() end
        -- a cm change keeps its pass open through the new caps: one record for the change
        local held = down == 'cm' and st.ncap == 0
        if st.pass and not held and (st.ncap == 0 or stopped('leash.restore')) then close() end
        if down == 'lab_end' and not st.pass then st.ended = true end
        return
    end
    if not st.active then
        if gate() then return end
        local why = st.down == 'cm' and 'cm' or 'on'
        st.active, st.cm, st.down = true, cm, nil
        for key, e in pairs(st.reg) do if not e.capped then st.reg[key] = nil end end
        st.scanq, st.classq, st.checkq, st.scan_due = nil, {}, {}, true
        if not (st.pass and st.pass.why == why) then open(why, true) end
    end
    local idle = not st.scanq and not st.classq[1] and not st.checkq[1]
    if idle and (st.scan_due or (not LAB.paused() and now() >= st.next_scan)) then
        if not st.pass then open('scan', false) end
        scan()
    end
    walk_step()
    classify_step()
    check_step()
    if st.pass and not st.scanq and not st.classq[1] and not st.checkq[1] then close() end
end

-- ---------- the console verb (MAIN.verb): the reply only; the job flips the switch on the game thread ----------
local function verb(args)
    local a = type(args) == 'table' and args[2] and tostring(args[2]):lower() or nil
    local cm = cap_cm()
    if a == 'on' or a == 'off' then
        local on = a == 'on'
        local note = ''
        if on then
            if not st.init then note = ' (inert in this build)' end
            for _, n in ipairs(M.NAMES) do
                if SENT.is_disabled(n) then note = note .. ' (refused: ' .. n .. ' is disabled; ' .. META.prefix
                    .. ' enable ' .. n .. ')' end
            end
            if MODOFF.is_off() or MODOFF.is_vanilla() then note = note .. ' (applies once the mod is back on)' end
        end
        return string.format('leash %s, %g cm%s', a, cm, note), function() st.want = on end
    end
    return string.format('leash %s, %g cm, %d decals capped (%s leash on|off; %s set leash_cm N)',
        st.want and 'on' or 'off', cm, st.ncap, META.prefix, META.prefix)
end

-- ---------- lifecycle ----------
local EVENTS = { 'lab_pawn', 'lab_end' }
function M.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.cut_set() then return true end
    st.init = true
    MODOFF.feature('lab_leash', { gameplay = true })    -- mod-off and the vanilla compare restore every capped decal
    for _, k in ipairs(M.COUNTERS) do LAB.count(k, 0) end
    BUS.on('lab_pawn', 'lab_leash', function(rec)
        if type(rec) == 'table' and rec.pawn ~= nil then st.pawn, st.feet_t = rec.pawn, nil end
    end)
    BUS.on('lab_end', 'lab_leash', function() st.end_due = true end)
    S.ticker('lab_leash', tick)
    if adapter and type(adapter.verb) == 'function' then adapter.verb('leash', verb, 'leash on|off') end
    return true
end
-- After a map load (main.lua's staggered warm-up): a scan of the new map when the leash is on
function M.warm()
    if st.init and st.active then st.scan_due = true end
end
-- A map load: no engine call (the old world's decals went with it); the records, the queues, the breaker and the
-- player's key drop, one leash record when anything was capped or the leash is on
function M.reset()
    if not st.init then return end
    if st.pass then close() end
    local n = st.ncap
    st.reg, st.ncap, st.nstuck, st.scanq, st.classq, st.checkq = {}, 0, 0, nil, {}, {}
    st.fails, st.off, st.pawn, st.feet, st.feet_t = {}, {}, nil, nil, nil
    if st.active or n > 0 then
        LAB.rec('leash', { why = 'map', cm = st.cm or cap_cm(), capped = 0, world = 0, dropped = n }, true)
    end
end
function M.status()
    local off = {}
    for k in pairs(st.off) do off[#off + 1] = k end
    table.sort(off)
    return { init = st.init, want = st.want, active = st.active, ended = st.ended, cm = st.cm, capped = st.ncap,
        world = world_n(), queued = #st.classq, off = off, err = st.err }
end
-- Engine-free (Ctrl+R runs it off the game thread): what is capped stays capped until the next map load
function M.shutdown()
    S.remove_ticker('lab_leash')
    for _, ev in ipairs(EVENTS) do BUS.off(ev, 'lab_leash') end
    st, A = new_state(), nil
end

return M
