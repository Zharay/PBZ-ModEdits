-- status: worked DD2 origin: kb:dismember-core#p12
-- (worked: walk, aliases, torso stops; 16,540 pairs offline, heads and legs seen in game; untested: the ladder)
-- also: kb:dismember-core#struck-joint-part-parent-chain-walk-with-aliases-torso-stops-and-a-cache-dd2-parts-lua-families-lua
-- parts.lua: the ONE mapper from a struck joint to a Part (three DD2 copies drifted apart; kb:dismember-core#p12).
-- It wraps libs/families_fn over the generated family table: the longest family key prefix, the parent walk (64 hops
-- at most) to the first Part root or alias, a torso joint stops it (nil = torso), the longest Part root prefixing the
-- name at '_' as the fallback, a cache per family + joint. Then:
--   P.cut_part     minor Parts (jaw, ear) promote to their parent, cut_as redirects (drake head -> neck)
--   P.allowed      the player's Part filter (setting parts.groups {head, arm, leg, other}); a refused Part is refused,
--                  it is NEVER swapped for another Part (kill records none / kind_off)
--   P.ladder       the demotion rungs kill tries when a rung is TECHNICALLY blocked (cloth, budget, sentinel):
--                  the Part, its first non-minor child (arm -> forearm, leg -> shin), the head as the last Part, then
--                  the Part again as a plain joint cut (tech 'joint'), the permanent fallback (SWZC tier 8)
--   P.kind / P.size  the classify ctx words ('head' | 'limb' | 'appendage' | 'torso'; 'S' | 'L' | 'H')
--   P.chain / P.family_on  a Part and its ancestors (nested-cut check); the per-family switch on the base chain
-- ADAPTER CONTRACT: A.joint_parent(v, joint_name) -> parent name | nil (engine bone parent; read on cache misses only)
-- opts: data (the emitted families table {BUILDS, FAMILIES, NIL}), families (an FN.new instance instead), head ('head')
-- Case (DD2): bandits reported Hip/root on 5 of 6 slash kills (body capsules), so a torso answer is normal and the
-- caller falls back to geometry. Case (SWZC): UE mannequin twist bones are children of their segment.
-- Evidence: [worked DD2] parts.lua 1-60, families.lua; [worked SWZC] lib/parts.lua; ladder [untested]
-- kb:dismember-core#tier-8-swing-aware-joint-cut-with-a-demotion-ladder-the-permanent-fallback-swzc
local NAME0 = (...) or 'features.parts'
local PFX, SEP = NAME0:match('^(.-)features([./])[^./]*$')
if not PFX then PFX, SEP = '', '.' end
local LOG = require(PFX .. 'core' .. SEP .. 'log')
local C = require(PFX .. 'core' .. SEP .. 'config')
local FN = require(PFX .. 'libs' .. SEP .. 'families_fn')

local P = { name = 'parts' }
P.DEFAULTS = {
    enabled = true,                  -- the mapper itself (off: every hit is a torso hit)
    groups = { head = true, arm = true, leg = true, other = true },   -- the player's Part filter (all on)
}
local opt = C.section_opt('parts', P.DEFAULTS)
P.opt = opt

local A, FAM, head_id = nil, nil, 'head'
local stats = { locate = 0, torso = 0, none = 0, refused = 0 }
local GROUP_OF = { head = 'head', jaw = 'head', neck = 'head', arm = 'arm', forearm = 'arm', hand = 'arm',
    leg = 'leg', shin = 'leg', foot = 'leg' }

-- joints for families_fn are { v, n }: the victim and the joint name, so one table walks every skeleton
local J = {
    name = function(j) return j.n end,
    parent = function(j)
        local pn = A and A.joint_parent and A.joint_parent(j.v, j.n)
        return pn and { v = j.v, n = pn } or nil
    end,
}

function P.family(v) return FAM and v and FAM.resolve(v.family) or nil end
function P.part(fam, id) return FAM and FAM.part(fam, id) end

-- The Part and its ancestor Parts, nearest first (the family's parent links). A Part under a cut ancestor is gone
-- with it: kill skips it as already_cut (DD2 victims.lua is_cut walks the same chain), never cuts it again.
function P.chain(fam, id)
    local out, guard, pid = {}, 0, id
    while pid and guard < 16 do
        out[#out + 1] = pid
        local d = P.part(fam, pid)
        pid, guard = d and d.parent, guard + 1
    end
    return out
end

-- The player's per-family switch (settings 'families'), looked up on the family's OWN base chain, nearest first,
-- never on shorter key prefixes of the id (a skeleton row based on the biped goes off with it)
function P.family_on(fam)
    local okc, s = pcall(C.get)
    local map = okc and type(s) == 'table' and s.families or nil
    if not (fam and type(map) == 'table') then return true end
    local x = nil
    if FAM and FAM.setting then x = FAM.setting(fam, map) end
    if x == nil then x = map[fam.key] end
    return x ~= false and x ~= 'off'
end

-- Struck joint -> raw Part id (before promotion), the family, and how: walk | cache | prefix | torso | none |
-- no_family | no_joint | off. b.joint then b.joint_b (the other end of the hit capsule).
function P.locate(v, b)
    stats.locate = stats.locate + 1
    if opt('enabled') == false then return nil, nil, 'off' end
    local fam = P.family(v)
    if not fam then return nil, nil, 'no_family' end
    local how = 'no_joint'
    for _, jn in ipairs({ b.joint or false, b.joint_b or false }) do
        if jn then
            local pid, h = FAM.part_of_joint(fam, { v = v, n = jn }, jn)
            if pid then return pid, fam, h end
            how = h
        end
    end
    if how == 'torso' then stats.torso = stats.torso + 1 else stats.none = stats.none + 1 end
    return nil, fam, how
end

function P.cut_part(fam, id) return FAM and FAM.cut_part(fam, id) or id end

function P.group(fam, id)
    local p = P.part(fam, id)
    if p and p.group then return p.group end
    local stem = type(id) == 'string' and (id:match('^([%a]+)') or id) or 'other'
    return GROUP_OF[stem] or 'other'
end

function P.allowed(fam, id)
    local g = opt('groups')
    if type(g) ~= 'table' then return true end
    local ok = g[P.group(fam, id)] ~= false
    if not ok then stats.refused = stats.refused + 1 end
    return ok
end
-- the classify ctx.allow function for one family
function P.allow_fn(fam) return function(id) return P.allowed(fam, id) end end

function P.kind(fam, id)
    if id == nil then return 'torso' end
    local g = P.group(fam, id)
    if g == 'head' then return 'head' end
    if g == 'arm' or g == 'leg' then return 'limb' end
    return 'appendage'
end
local SIZE = { human = 'S', small = 'S', S = 'S', large = 'L', L = 'L', huge = 'H', H = 'H' }
function P.size(fam) return fam and SIZE[fam.size_class or fam.size] or 'S' end

-- The demotion rungs for a Part: { part, tech? } in order; kill takes the first rung that is not technically blocked
-- and skips rungs the player's filter refuses. Never empty: the last rung is the plain joint cut of the Part itself.
function P.ladder(fam, id)
    local out, seen = {}, {}
    local function add(pid, tech)
        local key = tostring(pid) .. '|' .. tostring(tech)
        if pid and not seen[key] and (tech or P.part(fam, pid)) then
            seen[key] = true
            out[#out + 1] = { part = pid, tech = tech }
        end
    end
    add(id)
    for _, c in ipairs(fam and fam.children[id] or {}) do
        local p = P.part(fam, c)
        if p and not p.minor and not p.anchor then add(c) break end
    end
    if P.part(fam, head_id) then add(head_id) end
    add(id, 'joint')
    return out
end

-- Lifecycle
function P.init(adapter, opts)
    opts = opts or {}
    A = adapter or {}
    head_id = opts.head or 'head'
    stats = { locate = 0, torso = 0, none = 0, refused = 0 }
    FAM = opts.families
    if not FAM and opts.data then FAM = FN.new(opts.data, J, { max_depth = 64 }) end
    if not FAM then
        LOG.info('adapter_missing', { module = 'parts', fn = 'families', why = 'every hit is a torso hit' })
    end
    if not A.joint_parent then
        LOG.info('adapter_missing', { module = 'parts', fn = 'joint_parent', why = 'no parent walk; name prefix only' })
    end
    P.families = FAM
    return true
end
function P.shutdown() end
function P.reset() if FAM and FAM.reset then FAM.reset() end end
function P.status()
    local s = { locate = stats.locate, torso = stats.torso, none = stats.none, refused = stats.refused }
    if FAM and FAM.status then s.families = FAM.status() end
    return s
end
function P.ui_status() return string.format('parts: %d located, %d torso', stats.locate, stats.torso) end
function P.handoff() return nil end

return P
