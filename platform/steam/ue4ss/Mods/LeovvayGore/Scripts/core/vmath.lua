-- status: worked DD2 origin: kb:runtime-safety-perf#engine-notes (adapters own engine conversion)
-- vmath.lua: plain-table vectors {x, y, z} and quaternions {w, x, y, z}, so modules and offline tests need no engine
-- types. The adapter converts at the engine boundary (Vector3f / FVector) and sets the frame with V.set_frame:
--   RE Engine: Y up, metres (the defaults)       V.set_frame({ up = { x = 0, y = 0, z = 1 }, fwd = { x = 1, y = 0, z = 0 },
--   Unreal: Z up, centimetres                      unit = 100 })   -- engine units per metre
-- Tunables in metres go through V.m(x) (metres -> engine units) and V.to_m(x), so one default fits both engines.
-- V.of reads x/y/z or X/Y/Z (UE4SS structs); guards: V.finite, V.sane (no NaN/inf, none past 1e30), V.int, V.sane_int.
-- Evidence: [worked DD2] core/vmath.lua (to_engine/quat_to_engine dropped: adapters own conversion)
local V = {}

V.UP, V.FWD, V.UNIT = { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 }, 1
function V.set_frame(f)
    f = f or {}
    V.UP, V.FWD, V.UNIT = f.up or V.UP, f.fwd or V.FWD, f.unit or V.UNIT
end
function V.m(x) return x * V.UNIT end
function V.to_m(x) return x / V.UNIT end

function V.new(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function V.of(e)
    if e == nil then return nil end
    local x = e.x
    if x == nil then return { x = e.X, y = e.Y, z = e.Z } end
    return { x = x, y = e.y, z = e.z }
end
function V.arr(a) if a == nil then return nil end return { x = a[1], y = a[2], z = a[3] } end
function V.to_arr(a) return { a.x, a.y, a.z } end
function V.quat_of(q)
    if q == nil then return nil end
    if q.w == nil then return { w = q.W, x = q.X, y = q.Y, z = q.Z } end
    return { w = q.w, x = q.x, y = q.y, z = q.z }
end

function V.add(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
function V.sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
function V.scale(a, s) return { x = a.x * s, y = a.y * s, z = a.z * s } end
function V.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function V.cross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
function V.len(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function V.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function V.lerp(a, b, t) return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t } end
function V.norm(a)
    local l = V.len(a)
    if l < 1e-9 then return nil end
    return { x = a.x / l, y = a.y / l, z = a.z / l }
end
-- The height of p above the ground plane through origin (V.UP), in engine units
function V.height(p, origin) return V.dot(V.sub(p, origin or { x = 0, y = 0, z = 0 }), V.UP) end

-- ---------- quaternions (unit, w first) ----------
function V.quat_mul(a, b)
    return { w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w }
end
function V.quat_conj(q) return { w = q.w, x = -q.x, y = -q.y, z = -q.z } end
function V.quat_axis_angle(axis, angle)
    local s = math.sin(angle / 2)
    return { w = math.cos(angle / 2), x = axis.x * s, y = axis.y * s, z = axis.z * s }
end
function V.quat_norm(q)
    local l = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if l < 1e-9 then return { w = 1, x = 0, y = 0, z = 0 } end
    return { w = q.w / l, x = q.x / l, y = q.y / l, z = q.z / l }
end
-- The rotation taking unit vector a onto unit vector b (180 degrees: about any axis normal to a)
function V.quat_from_to(a, b)
    local d = V.dot(a, b)
    if d < -0.999999 then
        local axis = V.norm(V.cross({ x = 1, y = 0, z = 0 }, a)) or V.norm(V.cross({ x = 0, y = 1, z = 0 }, a))
        return { w = 0, x = axis.x, y = axis.y, z = axis.z }
    end
    local c = V.cross(a, b)
    return V.quat_norm({ w = 1 + d, x = c.x, y = c.y, z = c.z })
end
function V.rotate(q, p)
    local u = { x = q.x, y = q.y, z = q.z }
    local t = V.scale(V.cross(u, p), 2)
    return V.add(V.add(p, V.scale(t, q.w)), V.cross(u, t))
end

-- ---------- scalars and guards ----------
function V.clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
function V.round(x, n) local m = 10 ^ (n or 2) return math.floor(x * m + 0.5) / m end
function V.round_any(x, n) if type(x) ~= 'number' then return x end return V.round(x, n) end
function V.finite(x) return type(x) == 'number' and x == x and x > -math.huge and x < math.huge end
function V.sane(x) return type(x) == 'number' and x == x and x > -1e30 and x < 1e30 end
function V.sane_vec(a)
    return type(a) == 'table' and V.sane(a.x) and V.sane(a.y) and V.sane(a.z)
end
function V.int(x)
    x = tonumber(x)
    if x == nil or x ~= x or x == math.huge or x == -math.huge then return nil end
    return math.tointeger(x) or math.floor(x)
end
function V.sane_int(x)
    x = tonumber(x)
    if type(x) ~= 'number' or not V.sane(x) then return nil end
    return math.tointeger(x) or math.floor(x)
end

-- module contract stubs (a pure library has no lifecycle)
function V.init() return true end
function V.shutdown() end
function V.status() return nil end
function V.reset() end

return V
