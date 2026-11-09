-- classify.lua: pure blow classifier and rule engine. Takes the plain snapshot the hook copied (never an engine
-- object) plus a context, gives the blow a class, a sub-class and a strength tier 0-4, then maps it to an action
-- through ordered rule rows. Every per-game word list, enum map and rule row is data passed in (T); nothing here
-- names a game or calls an engine, so every rule is covered by offline tests on logged kill records.
-- status: worked origin: kb:dismember-core#blow-classifier-pure-lua-fixed-precedence-strength-tier-0-4-dd2-classify-lua
-- also: kb:dismember-core#rules-table-r1-r20-blow-x-part-kind-x-size-x-strength-action-dd2-k-decide
-- fixtures: DD2 (precedence, explosion words, tiers, rules R1-R20, party, kind_off), SWZC (tag specs, first-match kinds)
--
-- Precedence, first match wins: frozen > explosion > shoot > physical (slash incl. stab and bite, blunt; physical
-- flags beat the magic flag; slash and blow both set: the larger damage wins) > magic > flagless (hit effect only) >
-- unknown. The element never decides the class: it only picks the look (seared, icy).
-- Frozen beats seared: a frozen victim is never seared (kb:dismember-core#p9).
-- Strength: max(authored tier, reaction tier, floor) + over-threshold + damage/max HP steps (whole percent: 833/1400
-- counts as 60 %) + finishing flag + strong/weak name words + force; clamped 0-4.
-- The killing blow always cuts: decide never reads toughness or wear. A toughness gate, if any, belongs to the
-- caller and applies to corpse hits only (kb:content-coverage#limb-toughness-per-family-wear-table).
-- blow b: slash, blow, shoot, magic (flags); hit_eff (number, T.hit ranges); tier, react (authored tiers); floor;
--   over (bool); finish (bool); damage, dmg_slash, dmg_blow, force; name (attack or collider name); tags (list);
--   gimmick (name); explosion (bool, set by a caller that already knows); centre ({x,y,z}); blunt (bool: the weapon
--   in hand is blunt, read by the caller).
-- ctx: frozen, max_hp, corpse (a hit on a dead body), party, kind ('head' | 'limb' | 'appendage' | 'torso'),
--   size ('S' | 'L' | 'H'), part (struck Part id or nil), allow (function(part) -> bool, the player's filter), T.
-- Evidence: [worked DD2] removal rates per class measured on logged kills (enchanted melee 274/278, arrows 58/140);
-- [worked SWZC] ability tag specs and ordered categories (shot design section 2).

local K = { counts = {} }

-- ---------------------------------------------------------------------------------------------------------------
-- Matchers
-- ---------------------------------------------------------------------------------------------------------------
-- any word of list as a plain substring (safe for Latin words that never occur inside others)
function K.has(s, list)
    if type(s) ~= "string" or type(list) ~= "table" then return false end
    for _, k in ipairs(list) do if s:find(k, 1, true) then return true end end
    return false
end
-- a Latin word as a whole token: no ASCII letter right before or after it ("Bomb_EX" holds EX, "Explosion" not).
-- The word must start and end with a letter; any punctuation inside it matches literally.
function K.has_token(s, list)
    if type(s) ~= "string" or type(list) ~= "table" then return false end
    for _, k in ipairs(list) do
        if s:find("%f[A-Za-z]" .. (tostring(k):gsub("%p", "%%%0")) .. "%f[^A-Za-z]") then return true end
    end
    return false
end
-- exact names (a set name -> true, or a list): CJK names are matched exactly, never as bare substrings
function K.exact(s, set)
    if type(s) ~= "string" or type(set) ~= "table" then return false end
    if set[s] then return true end
    for _, k in ipairs(set) do if s == k then return true end end
    return false
end
-- tag spec: an exact tag; 'A.B.*' = A.B and everything below it; '*.X' = any tag ending in '.X'
function K.tag_matches(tag, spec)
    if type(tag) ~= "string" or type(spec) ~= "string" then return false end
    if spec:sub(-2) == ".*" then
        local root = spec:sub(1, -3)
        return tag == root or tag:sub(1, #root + 1) == root .. "."
    end
    if spec:sub(1, 1) == "*" then
        local tail = spec:sub(2)
        return #tag >= #tail and tag:sub(-#tail) == tail
    end
    return tag == spec
end
-- the first tag matching any spec (spec order first), or nil
function K.match_tags(tags, specs)
    if type(tags) ~= "table" or type(specs) ~= "table" then return nil end
    for _, spec in ipairs(specs) do
        for _, t in ipairs(tags) do if K.tag_matches(t, spec) then return t end end
    end
    return nil
end
-- Ordered first-match kinds: entries {kind, tags = {specs}, names = {Lua patterns}}; within an entry the tags are
-- tried before the name. Returns kind, 'tag' | 'name', or nil.
function K.first_kind(entries, name, tags)
    if type(entries) ~= "table" then return nil end
    for _, e in ipairs(entries) do
        if K.match_tags(tags, e.tags) then return e[1] or e.kind, "tag" end
        if type(name) == "string" and type(e.names) == "table" then
            for _, p in ipairs(e.names) do if name:find(p) then return e[1] or e.kind, "name" end end
        end
    end
    return nil
end

local function in_range(x, r) return type(x) == "number" and type(r) == "table" and x >= r[1] and x <= r[2] end

-- ---------------------------------------------------------------------------------------------------------------
-- Classifier
-- ---------------------------------------------------------------------------------------------------------------
K.T = {
    ratio_plus1 = 0.6, ratio_plus2 = 1.5, force_plus = 1.5, max_hp_fallback = 1200,
    hit = { blade = { 0, 5 }, stab = { 3, 5 }, blunt = { 6, 8 }, shot = { 9, 11 }, bite = { 12, 14 } },
    hit_tier = {},                 -- hit effect -> authored tier (per game)
    react_tier = {},               -- reaction / damage type -> tier (per game)
    expl = { kw = {}, not_kw = {}, names = {}, tags = {}, gimmick_kw = {}, zone_in = {}, zone_out = {},
        up = {}, up_tokens = { "EX", "Ex" }, dn = {} },
    strong_kw = {}, weak_kw = {}, slash_kw = {},
    kinds = {},                    -- ordered first-match {kind, tags, names}: 'explosion' | 'shoot' | 'slash' ...
    thr = {},                      -- named strength thresholds the rule rows refer to
    rules = {},                    -- ordered rule rows (K.decide)
    party_whole_body = false,
}

-- Explosion from the caller's flag, the attack name (words, not excluded words), exact names, tags or a gimmick.
-- nil when not an explosion, else {zone = 'centre' | 'outer' | nil, size = 0.7 | 1.0 | 1.3, centre}.
function K.explosion_of(b, T)
    T = T or K.T
    local X = T.expl or {}
    local name = b.name or ""
    local hit = b.explosion == true or K.first_kind(T.kinds, b.name, b.tags) == "explosion"
    if not hit then
        if K.has(name, X.not_kw) then return nil end
        hit = K.has(name, X.kw) or K.exact(name, X.names) or K.match_tags(b.tags, X.tags) ~= nil
            or K.has(b.gimmick, X.gimmick_kw)
    end
    if not hit then return nil end
    return {
        zone = K.has(name, X.zone_in) and "centre" or (K.has(name, X.zone_out) and "outer" or nil),
        size = (K.has(name, X.up) or K.has_token(name, X.up_tokens)) and 1.3 or (K.has(name, X.dn) and 0.7 or 1.0),
        centre = b.centre,
    }
end

-- Strength tier 0-4 and its components (for the log and calibration)
function K.strength(b, max_hp, T)
    T = T or K.T
    local tier = tonumber(b.tier) or (T.hit_tier or {})[b.hit_eff] or 1
    local react = tonumber(b.react) or (T.react_tier or {})[b.react_type] or 0
    local s = math.max(tier, react, tonumber(b.floor) or 0)
    if b.over then s = s + 1 end
    local D = K.T                      -- a per-game T may leave any number out: the defaults fill it
    local mh = tonumber(max_hp)
    local hp = (mh and mh > 0) and mh or tonumber(T.max_hp_fallback) or D.max_hp_fallback
    local pct = math.floor((tonumber(b.damage) or 0) / hp * 100 + 0.5)
    if pct >= (tonumber(T.ratio_plus1) or D.ratio_plus1) * 100 then s = s + 1 end
    if pct >= (tonumber(T.ratio_plus2) or D.ratio_plus2) * 100 then s = s + 1 end
    if b.finish then s = s + 1 end
    local kw = K.has(b.name, T.strong_kw) and 1 or (K.has(b.name, T.weak_kw) and -1 or 0)
    s = s + kw
    if (tonumber(b.force) or 1) >= (tonumber(T.force_plus) or D.force_plus) then s = s + 1 end
    return math.max(0, math.min(4, s)), { tier = tier, react = react, pct = pct, kw = kw ~= 0 and kw or nil }
end

-- Class (frozen, explosion, shoot, slash, blunt, magic, unknown), sub-class (stab, bite), strength, explosion and
-- by (the precedence step that decided: the log's evidence word). base is the class the blow had before frozen won.
function K.classify(b, ctx)
    ctx = ctx or {}
    local T = ctx.T or K.T
    local H = T.hit or K.T.hit
    local s, parts = K.strength(b, ctx.max_hp, T)
    local C = { strength = s, tiers = parts, ratio = parts.pct / 100, frozen = ctx.frozen == true }
    local he = tonumber(b.hit_eff)
    local kind, kby = K.first_kind(T.kinds, b.name, b.tags)
    local blade = in_range(he, H.blade) or in_range(he, H.bite)
    C.expl = K.explosion_of(b, T)
    local cls, by
    if C.expl then cls, by = "explosion", "explosion"
    elseif b.shoot or in_range(he, H.shot) or kind == "shoot" then
        cls, by = "shoot", b.shoot and "flag" or (kind == "shoot" and kby or "hit_eff")
    elseif b.slash and b.blow then
        cls, by = ((tonumber(b.dmg_blow) or 0) > (tonumber(b.dmg_slash) or 0)) and "blunt" or "slash", "damage"
    elseif b.slash then cls, by = b.blunt == true and "blunt" or "slash", b.blunt == true and "weapon" or "flag"
    elseif b.blow then cls, by = "blunt", "flag"
    elseif kind == "slash" or kind == "blunt" then cls, by = kind, kby
    elseif b.magic or kind == "magic" then
        -- a spell whose name says it cuts, or with a blade hit effect, cuts like a blade
        if K.has(b.name, T.slash_kw) or blade then cls, by = "slash", "magic_blade" else cls, by = "magic", "flag" end
    elseif blade then cls, by = b.blunt == true and "blunt" or "slash", "flagless"
    elseif in_range(he, H.blunt) then cls, by = "blunt", "flagless"
    else cls, by = "unknown", "none" end
    C.base = cls
    if C.frozen then cls, by = "frozen", "frozen" end
    C.cls, C.by, C.kind = cls, by, kind
    if C.base == "slash" then
        if in_range(he, H.stab) then C.sub = "stab" elseif in_range(he, H.bite) then C.sub = "bite" end
    end
    C.element = b.element
    C.seared = (not C.frozen) and type(T.seared) == "table" and T.seared[b.element] == true or nil
    C.icy = (b.element == "ice" and not C.frozen) or nil
    K.counts[cls] = (K.counts[cls] or 0) + 1
    return C
end

-- ---------------------------------------------------------------------------------------------------------------
-- Rules: ordered rows, first match wins. A row: {id, action, reason, cls (name or set), kind, size, sub, corpse
-- (true: corpse hits only, false: kills only), zone (explosion zone), min (strength or a T.thr key), weak (reason
-- word when the row matches but the strength is short: stop there; without it the next row is tried), torn,
-- count}. Actions: cut bisect split cleave gib tear burst shatter push vanilla_fx none.
-- Every return carries action, rule and reason (the skip reason when nothing is removed).
-- ---------------------------------------------------------------------------------------------------------------
local WHOLE = { burst = true, bisect = true, split = true, shatter = true }
local PART_ACT = { cut = true, gib = true, cleave = true, tear = true }
K.WHOLE, K.PART_ACT = WHOLE, PART_ACT

local function one_of(v, want)
    if want == nil then return true end
    if type(want) == "table" then return K.exact(v, want) end
    return v == want
end

local function row_matches(row, C, r, ctx)
    if not one_of(C.cls, row.cls) or not one_of(r.kind, row.kind) or not one_of(r.size, row.size) then return false end
    if row.sub ~= nil and not one_of(C.sub or "none", row.sub) then return false end
    if row.corpse ~= nil and (ctx.corpse == true) ~= row.corpse then return false end
    if row.zone ~= nil and not one_of(C.expl and C.expl.zone or "none", row.zone) then return false end
    return true
end

-- Party downgrade and the player's Part filter. A switched-off Part takes nothing: none 'kind_off' (never swapped
-- for another Part), only a multi-Part Gib goes on with one less and no struck slot.
local function finish(r, ctx, T)
    if ctx.party == true and not T.party_whole_body and WHOLE[r.action] then
        r.was = r.action
        if r.struck then
            r.action, r.part = (r.action == "burst" or r.action == "shatter") and "gib" or "cut", r.struck
            r.reason = "party_single"
        else
            r.action, r.reason = "none", "party_single"
        end
    end
    if ctx.allow and r.part and PART_ACT[r.action] and not ctx.allow(r.part) then
        if r.action == "gib" and (r.count or 1) > 1 then
            r.koff, r.part, r.count = r.part, nil, r.count - 1
        else
            r.koff, r.was = r.part, r.action
            r.action, r.reason = "none", "kind_off"
        end
    end
    return r
end

-- Decide. ctx.cls may carry a classify() result already made. Never reads toughness or wear.
function K.decide(b, ctx)
    ctx = ctx or {}
    local T = ctx.T or K.T
    local C = ctx.cls or K.classify(b, ctx)
    local r = { cls = C.cls, base = C.base, sub = C.sub, by = C.by, strength = C.strength, ratio = C.ratio,
        expl = C.expl, frozen = C.frozen, element = C.element, seared = C.seared, icy = C.icy,
        kind = ctx.kind or (ctx.part and "limb" or "torso"), size = ctx.size or "S", struck = ctx.part }
    for _, row in ipairs(T.rules or {}) do
        if row_matches(row, C, r, ctx) then
            local need = row.min
            if type(need) == "string" then need = (T.thr or {})[need] end
            need = tonumber(need) or 0
            if C.strength >= need then
                r.action, r.rule, r.reason = row.action or "none", row.id or "R?", row.reason or row.id or "rule"
                r.torn, r.count = row.torn, row.count
                r.part = PART_ACT[r.action] and ctx.part or nil
                return finish(r, ctx, T)
            end
            if row.weak then
                r.action, r.rule, r.reason = "none", row.id or "R?", row.weak
                return r
            end
        end
    end
    r.action, r.rule, r.reason = "none", "R0", "no_rule"
    return r
end

-- Module contract (stateless apart from the class counters)
function K.init() end
function K.shutdown() end
function K.reset() K.counts = {} end
function K.status()
    local c = {}
    for k, v in pairs(K.counts) do c[k] = v end
    return c
end

return K
