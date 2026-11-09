-- families_fn.lua: runtime lookups over the GENERATED family table (tools/families/families.py emit). Pure data
-- access: the joint accessors are injected, so the same walk runs on UE bones, RE Engine joints or test tables.
-- status: worked origin: kb:content-coverage#generated-family-table-with-inheritance-and-an-offline-validator
-- also: kb:dismember-core#struck-joint-part-parent-chain-walk-with-aliases-torso-stops-and-a-cache-dd2-parts-lua-families-lua
-- fixtures: DD2-style biped and quadruped, UE-mannequin biped (tests/fixtures; Lua walk == Python walk on every joint)
--
-- local F = FN.new(require('families_data'), J, opts)
--   data: {BUILDS, FAMILIES, NIL} as emitted. J (joint accessors, all optional for pure lookups):
--   name(j) -> string, parent(j) -> joint | nil, by_name(tr, name) -> joint | nil, pos(j) -> {x, y, z} | {[1..3]}.
--   opts: sep = '_' (the name-prefix fallback separator, false to switch it off), min_key = 1 (shortest key tried),
--   max_depth = 64 (parent hops).
-- Resolve: the longest FAMILIES key that prefixes the id, then base chain -> build/parts -> over (NIL deletes a
-- field) / add (replaces by id) / drop, flags merged the same way, cap_scale applied once.
-- Settings: a per-family switch is looked up on the family's OWN base chain only (fam.chain), never on shorter key
-- prefixes of the id. Case (DD2): a 'ch270' row reached the tentacles 'ch27001' through the prefix and the Dragon's
-- 'ch258' reached the Fallen Dragon; a family with its own row now never takes another row's override.
-- Walk: the struck joint and its ancestors; the first Part root (or 'roots' entry) or alias wins; a torso joint
-- stops the walk (nil = torso); then the longest Part root that prefixes the name at a separator. Case (DD2): twist
-- and helper joints are named after their segment ('L_Arm_Lower_Twist_1'); UE mannequin twist bones
-- ('upperarm_twist_01_l') are children of their segment, so the walk already finds them. Cache per family + joint.
-- Evidence: [worked DD2] 16,540 (family, joint) pairs matched the Python reference walk, 0 fails; head and leg hides
-- seen on bandits in game.

local FN = {}

local SCALAR_SKIP = { base = true, over = true, add = true, drop = true, parts = true, flags = true }
local GATE_OF = { MAT = "G-MAT", VSP = "G-VSP", VVB = "G-VVB" }

function FN.wave_no(w)
    if type(w) == "number" then return w end
    local d = type(w) == "string" and w:match("^W(%d+)$") or nil
    return d and tonumber(d) or 99
end

function FN.new(data, J, opts)
    assert(type(data) == "table" and type(data.FAMILIES) == "table", "families_fn.new: data needs FAMILIES")
    opts = opts or {}
    J = J or {}
    local BUILDS, FAMILIES, NIL = data.BUILDS or {}, data.FAMILIES, data.NIL or {}
    local SEP = opts.sep == nil and "_" or opts.sep
    local MIN_KEY, MAX_DEPTH = opts.min_key or 1, opts.max_depth or 64
    local M = { NIL = NIL, wave_no = FN.wave_no }
    local resolved, stats = {}, { resolved = 0, walks = 0, cache = 0, prefix = 0 }

    local function copy(v)
        if type(v) ~= "table" or v == NIL then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = copy(x) end
        return o
    end
    local function jcall(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    -- Longest prefix of the id that is a FAMILIES key ('ch270025_00' -> 'ch27002')
    function M.key_for(id)
        if type(id) ~= "string" then return nil end
        for n = #id, MIN_KEY, -1 do
            local k = id:sub(1, n)
            if FAMILIES[k] then return k end
        end
        return nil
    end

    local function merge_raw(key, depth)
        local f = FAMILIES[key]
        if not f or depth > 8 then return nil end
        local out
        if f.base then
            out = merge_raw(f.base, depth + 1)
            if not out then return nil end
            out.chain[#out.chain + 1] = key
        else
            out = { chain = { key }, flags = {}, parts = {} }
            local src = (f.build and BUILDS[f.build]) or f.parts or {}
            for i, p in ipairs(src) do out.parts[i] = copy(p) end
        end
        for k, v in pairs(f) do
            if not SCALAR_SKIP[k] then
                if v == NIL then out[k] = nil else out[k] = copy(v) end
            end
        end
        for k, v in pairs(f.flags or {}) do
            if v == NIL then out.flags[k] = nil else out.flags[k] = copy(v) end
        end
        if f.over then
            for _, p in ipairs(out.parts) do
                local ov = f.over[p.id]
                if ov then
                    for k, v in pairs(ov) do
                        if v == NIL then p[k] = nil else p[k] = copy(v) end
                    end
                end
            end
        end
        for _, a in ipairs(f.add or {}) do
            for i = #out.parts, 1, -1 do if out.parts[i].id == a.id then table.remove(out.parts, i) end end
            out.parts[#out.parts + 1] = copy(a)
        end
        if f.drop then
            local d = {}
            for _, id in ipairs(f.drop) do d[id] = true end
            for i = #out.parts, 1, -1 do if d[out.parts[i].id] then table.remove(out.parts, i) end end
        end
        return out
    end

    -- A FAMILIES key resolved into the table every other module uses (cached; false = unknown)
    function M.resolve_key(key)
        if key == nil then return nil end
        local r = resolved[key]
        if r ~= nil then return r or nil end
        r = merge_raw(key, 0)
        if not r then resolved[key] = false return nil end
        r.key = key
        local cs = r.cap_scale
        r.by_id, r.root2part, r.children, r.top, r.torso_set, r.jcache = {}, {}, {}, {}, {}, {}
        r.alias = r.alias or {}
        for _, p in ipairs(r.parts) do
            if type(cs) == "number" and type(p.cap) == "number" then p.cap = math.floor(p.cap * cs * 1000 + 0.5) / 1000 end
            r.by_id[p.id] = p
        end
        for _, p in ipairs(r.parts) do
            if not p.anchor and p.tech ~= "BLK" then
                for _, jn in ipairs(p.roots or { p.root }) do r.root2part[jn] = p.id end
            end
            if p.parent and r.by_id[p.parent] then
                local c = r.children[p.parent] or {}
                c[#c + 1] = p.id
                r.children[p.parent] = c
            elseif p.tech ~= "BLK" then
                r.top[#r.top + 1] = p.id
            end
        end
        for _, t in ipairs(r.torso or {}) do r.torso_set[t] = true end
        resolved[key] = r
        stats.resolved = stats.resolved + 1
        return r
    end
    function M.resolve(id) return M.resolve_key(M.key_for(id)) end

    -- The Part of the longest key of map (joint name -> Part id) that prefixes name at a separator, or nil
    function M.prefix_part(map, name)
        if not SEP or type(name) ~= "string" then return nil end
        local best, bestn = nil, 0
        for jn, pid in pairs(map) do
            local n = #jn
            if n > bestn and name:sub(1, n) == jn and name:sub(n + 1, n + #SEP) == SEP then best, bestn = pid, n end
        end
        return best
    end

    -- Struck joint -> Part id (nil = torso or unknown) and a reason word: cache | walk | torso | prefix | none.
    -- joint may be nil (only the name is known: no walk, the prefix fallback only).
    function M.part_of_joint(fam, joint, name)
        if not fam then return nil, "no_family" end
        name = name or (joint and jcall(J.name, joint))
        if not name then return nil, "no_name" end
        local c = fam.jcache[name]
        if c ~= nil then stats.cache = stats.cache + 1 return c or nil, "cache" end
        stats.walks = stats.walks + 1
        local j, n, depth = joint, name, 0
        while n and depth < MAX_DEPTH do
            local pid = fam.root2part[n] or fam.alias[n]
            if pid then fam.jcache[name] = pid return pid, "walk" end
            if fam.torso_set[n] then fam.jcache[name] = false return nil, "torso" end
            if not j then break end
            j = jcall(J.parent, j)
            n = j and jcall(J.name, j)
            depth = depth + 1
        end
        local pid = fam.root2part[name] or M.prefix_part(fam.root2part, name)
        if pid then stats.prefix = stats.prefix + 1 end
        fam.jcache[name] = pid or false
        return pid, pid and "prefix" or "none"
    end
    -- Same with only a joint name (a persisted cut, a logged joint): looked up on the transform first
    function M.part_of_joint_name(fam, tr, name)
        local j = tr and name and jcall(J.by_name, tr, name)
        return M.part_of_joint(fam, j, name)
    end

    function M.part(fam, id) return fam and fam.by_id[id] end
    -- hand_l -> {hand_l, forearm_l, arm_l}
    function M.chain(fam, id)
        local out, p, guard = {}, fam and fam.by_id[id], 0
        while p and guard < 16 do
            out[#out + 1] = p.id
            p = p.parent and fam.by_id[p.parent]
            guard = guard + 1
        end
        return out
    end
    -- arm_l -> {forearm_l, hand_l}: every Part inside it, depth first (removed together with it)
    function M.descendants(fam, id, out)
        out = out or {}
        for _, c in ipairs(fam.children[id] or {}) do
            out[#out + 1] = c
            M.descendants(fam, c, out)
        end
        return out
    end

    local function xyz(p)
        if type(p) ~= "table" then return nil end
        local x, y, z = p.x or p[1], p.y or p[2], p.z or p[3]
        if type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
        return nil
    end
    local function root_pos(tr, p)
        local j = jcall(J.by_name, tr, p.root)
        return j and jcall(J.pos, j)
    end
    -- Cut level from the hit point along a limb: candidates are id and its non-minor, non-anchor descendants; each
    -- owns the segment from its root to its first child Part's root (a leaf extends 60 % of its parent's segment).
    -- The nearest segment wins and ties go to the deeper Part: a forearm hit cuts at the elbow.
    function M.level_from_hit(fam, tr, id, hit)
        local hx, hy, hz = xyz(hit)
        if not (fam and tr and hx) then return id end
        local cand = { id }
        for _, c in ipairs(M.descendants(fam, id)) do
            local p = fam.by_id[c]
            if p and not p.minor and not p.anchor then cand[#cand + 1] = c end
        end
        local best, bestd = id, nil
        for _, pid in ipairs(cand) do
            local p = fam.by_id[pid]
            local ax, ay, az = xyz(root_pos(tr, p))
            if ax then
                local kids = fam.children[pid]
                local bx, by, bz = xyz(kids and kids[1] and root_pos(tr, fam.by_id[kids[1]]))
                if not bx then
                    bx, by, bz = ax, ay, az
                    local px, py, pz = xyz(p.parent and fam.by_id[p.parent] and root_pos(tr, fam.by_id[p.parent]))
                    if px then bx, by, bz = ax + (ax - px) * 0.6, ay + (ay - py) * 0.6, az + (az - pz) * 0.6 end
                end
                local dx, dy, dz = bx - ax, by - ay, bz - az
                local L2 = dx * dx + dy * dy + dz * dz
                local t = L2 > 1e-8 and ((hx - ax) * dx + (hy - ay) * dy + (hz - az) * dz) / L2 or 0
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
                local qx, qy, qz = ax + dx * t - hx, ay + dy * t - hy, az + dz * t - hz
                local d = qx * qx + qy * qy + qz * qz
                if not bestd or d <= bestd then best, bestd = pid, d end
            end
        end
        return best
    end

    -- The Part a Cut removes: minor Parts promote to their nearest non-minor ancestor, then cut_as redirects
    function M.cut_part(fam, id)
        local p, guard = fam and fam.by_id[id], 0
        while p and p.minor and p.parent and fam.by_id[p.parent] and guard < 8 do
            p = fam.by_id[p.parent]
            guard = guard + 1
        end
        if p and p.cut_as and fam.by_id[p.cut_as] then p = fam.by_id[p.cut_as] end
        return p and p.id
    end
    function M.top_parts(fam) return fam and fam.top or {} end
    function M.part_of_region(fam, region)
        if not (fam and region ~= nil) then return nil end
        for _, p in ipairs(fam.parts) do if p.region == region then return p.id end end
        return nil
    end
    function M.bisect(fam)
        if fam and fam.scope == "in" and type(fam.bisect) == "table" then return fam.bisect end
        return nil
    end
    function M.split(fam)
        if fam and fam.scope == "in" and type(fam.split) == "table" then return fam.split end
        return nil
    end

    -- A per-family setting from a map keyed like FAMILIES: the family's own chain, nearest first
    function M.setting(fam, map)
        if not (fam and type(map) == "table") then return nil end
        for i = #fam.chain, 1, -1 do
            local v = map[fam.chain[i]]
            if v ~= nil then return v end
        end
        return nil
    end
    -- May this family be cut at all? cfg.rollout = highest enabled wave ('W3'); cfg.families[key] == false on its
    -- own chain switches it off
    function M.active(fam, cfg)
        if not fam or fam.scope ~= "in" then return false end
        if cfg then
            if cfg.rollout and FN.wave_no(fam.wave) > FN.wave_no(cfg.rollout) then return false end
            if M.setting(fam, cfg.families) == false then return false end
        end
        return true
    end
    -- Effective technique under the lab gates: MAT, VSP and VVB stay closed until cfg.gates[gate] passes; a closed
    -- VSP/VVB falls back to authored groups (GRP), a GameObject hide (GO) or joint scale (JS); a closed MAT to
    -- p.fallback_tech or nothing
    function M.tech(fam, p, cfg)
        if not p or p.tech == "BLK" then return nil end
        local g = p.gate or GATE_OF[p.tech]
        if not g or (cfg and cfg.gates and cfg.gates[g]) then return p.tech end
        if p.fallback_tech then return p.fallback_tech end
        if p.tech == "VSP" or p.tech == "VVB" then
            if p.groups then return "GRP" end
            if p.go then return "GO" end
            return "JS"
        end
        return nil
    end
    function M.part_active(fam, p, cfg)
        if not M.tech(fam, p, cfg) then return false end
        if p.wave and cfg and cfg.rollout and FN.wave_no(p.wave) > FN.wave_no(cfg.rollout) then return false end
        return true
    end
    -- Every family key of a given length (nil: all), sorted, for a settings list
    function M.list(len)
        local out = {}
        for k, f in pairs(FAMILIES) do
            if not len or #k == len then
                local r = M.resolve_key(k)
                out[#out + 1] = { key = k, name = r and r.name or f.name, scope = r and r.scope, wave = r and r.wave }
            end
        end
        table.sort(out, function(a, b) return a.key < b.key end)
        return out
    end

    function M.init() end
    function M.shutdown() end
    -- drop every resolved family and joint cache (a data reload, a settings change that edits rows)
    function M.reset() resolved = {} end
    function M.status()
        return { resolved = stats.resolved, walks = stats.walks, cache = stats.cache, prefix = stats.prefix }
    end
    return M
end

return FN
