-- status: worked DD2+SWZC origin: kb:runtime-safety-perf#object-caps-eviction-score-and-spawned-registry
-- registry.lua: tracked records (victims, corpses) and spawned objects (pieces, gibs, caps) in named pools with caps.
-- Rules (each from a real failure):
-- * A record is keyed by address AND identity (a name, a spawn serial): addresses are reused after a destroy, so a
--   record whose identity differs is dropped ('reused') and never handed back. Every record carries the epoch it was
--   made in; R.bump_epoch (a map change, a load) drops every record at once ('stale'); R.valid(rec) tells a holder.
-- * Caps count records (weight 1) or weights (rec.weight: a large piece 2, a huge one 4); cap may be a function, so a
--   lower setting applies live through R.trim (at most R.TRIM_PER_FRAME 8 evictions a call).
-- * Eviction plans first (R.can_admit evicts nothing; R.admit evicts only when the plan frees enough room). Highest
--   score goes first: the default is age_s/60 + rec.dist/30 - 5 while rec.flying; opts.fifo evicts the oldest first.
--   Never evicted: the player and the party (rec.player, rec.party, opts.protect(rec)) and anything younger than
--   opts.min_age 1 s. Evicting a companion's record once restored a texture under the renderer and crashed it.
-- * An evicted record exports its small state (opts.export(rec) -> table) into a bounded table keyed by address plus
--   identity, and R.get imports it (opts.import(rec, state)) when it recreates a record for the same object: a sweep
--   over the victim cap once dropped worn enemies' limb wear and blood.
-- * opts.evict(rec, why, score) frees the object (a short shrink, never a pop); it runs under pcall.
-- API (stable): R.pool(name, { cap, weight, score, protect, export, import, evict, fifo, min_age, export_max }),
--   get(pool, addr, ident [, init]) -> rec, created | nil, why; admit(pool [, weight]) -> true, n | false, 'limit';
--   can_admit(pool [, weight]); forget(pool, addr [, why]); each(pool, fn); trim(pool) -> n, more; bump_epoch; epoch;
--   count(pool); valid(rec); init(A, opts) reset shutdown status.
-- Evidence: [worked DD2] physics.lua PH.score/admit_plan/trim, victims.lua records; [worked SWZC] lib/registry.lua;
-- kb:runtime-safety-perf#ue4ss-identity-safe-caches-delayed-steps-and-destroy
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')

local R = { TRIM_PER_FRAME = 8, MIN_AGE = 1, EXPORT_MAX = 64 }

local A, clock = nil, function() return 0 end
local pools, epoch, seq = {}, 0, 0

-- opts: clock() -> s (default A.clock.real; pass sched's game clock to age in game time)
function R.init(adapter, opts)
    opts = opts or {}
    A = adapter
    clock = opts.clock or (adapter and adapter.clock and adapter.clock.real) or function() return 0 end
    pools, epoch, seq = {}, 0, 0
    return true
end

function R.pool(name, opts)
    opts = opts or {}
    local p = pools[name]
    if not p then
        p = { list = {}, by = {}, wsum = 0, exports = {}, export_order = {}, evicted = 0, reused = 0, stale = 0,
            imported = 0 }
        pools[name] = p
    end
    p.name, p.cap, p.weight, p.score, p.protect = name, opts.cap, opts.weight, opts.score, opts.protect
    p.export, p.import, p.evict, p.fifo = opts.export, opts.import, opts.evict, opts.fifo == true
    p.min_age, p.export_max = opts.min_age or R.MIN_AGE, opts.export_max or R.EXPORT_MAX
    return p
end

local function cap_of(p)
    local c = p.cap
    if type(c) == 'function' then
        local ok, v = pcall(c)
        c = ok and v or nil
    end
    if type(c) ~= 'number' then return math.huge end
    return c
end

local function weight_of(p, rec)
    local w = rec.weight
    if type(p.weight) == 'function' then
        local ok, v = pcall(p.weight, rec)
        if ok then w = v end
    end
    if type(w) ~= 'number' or w < 0 then w = 1 end
    return w
end

local function key_of(addr, ident) return tostring(addr) .. '|' .. tostring(ident) end

local function protected(p, rec, now)
    if rec.player or rec.party then return true end
    if now - (rec.born or now) < p.min_age then return true end
    if p.protect then
        local ok, v = pcall(p.protect, rec)
        if ok and v == true then return true end
    end
    return false
end

local function score_of(p, rec, now)
    local age = now - (rec.born or now)
    if p.fifo then return age end
    if p.score then
        local ok, v = pcall(p.score, rec, now)
        if ok and type(v) == 'number' then return v end
    end
    local s = age / 60 + (tonumber(rec.dist) or 0) / 30
    if rec.flying then s = s - 5 end
    return s
end

local function unlink(p, rec)
    if p.by[rec.addr] == rec then p.by[rec.addr] = nil end
    for i, r in ipairs(p.list) do
        if r == rec then table.remove(p.list, i) break end
    end
    p.wsum = p.wsum - (rec._w or 1)
    rec._gone = true
end

local function save_export(p, rec)
    if not p.export then return end
    local ok, st = pcall(p.export, rec)
    if not ok or st == nil then return end
    local key = key_of(rec.addr, rec.ident)
    if p.exports[key] == nil then p.export_order[#p.export_order + 1] = key end
    p.exports[key] = st
    while #p.export_order > p.export_max do
        p.exports[table.remove(p.export_order, 1)] = nil
    end
end

local function evict_one(p, rec, s)
    save_export(p, rec)
    unlink(p, rec)
    p.evicted = p.evicted + 1
    if p.evict then
        local ok, err = pcall(p.evict, rec, 'limit', s)
        if not ok and LOG.every('registry_evict_error:' .. p.name, 30) then
            LOG.warn('call_fault', { key = 'registry:' .. p.name .. ':evict', err = tostring(err) })
        end
    end
end

-- The candidates an eviction may take, scored once and highest first (ties: the older first)
local function candidates(p, now)
    local cand = {}
    for _, rec in ipairs(p.list) do
        if not protected(p, rec, now) then cand[#cand + 1] = { rec = rec, s = score_of(p, rec, now) } end
    end
    table.sort(cand, function(a, b)
        if a.s ~= b.s then return a.s > b.s end
        return a.rec._seq < b.rec._seq
    end)
    return cand
end

-- The records to evict so one more of weight w fits: true, plan (empty: room already) | false, 'limit'
local function plan(p, w)
    local cap = cap_of(p)
    if w > cap then return false, 'limit' end
    local total = p.wsum
    if total + w <= cap then return true, {} end
    local out = {}
    for _, c in ipairs(candidates(p, clock())) do
        out[#out + 1] = c
        total = total - (c.rec._w or 1)
        if total + w <= cap then return true, out end
    end
    return false, 'limit'
end

function R.can_admit(name, w)
    local p = pools[name]
    if not p then return false, 'no_pool' end
    return (plan(p, w or 1))
end

function R.admit(name, w)
    local p = pools[name]
    if not p then return false, 'no_pool' end
    local ok, out = plan(p, w or 1)
    if not ok then return false, out end
    for _, c in ipairs(out) do evict_one(p, c.rec, c.s) end
    return true, #out
end

local function drop(p, rec, why)
    unlink(p, rec)
    if why == 'reused' then p.reused = p.reused + 1 else p.stale = p.stale + 1 end
end

-- The record for (addr, ident): nil once its identity or epoch changed. With init (a fresh table, or true) a missing
-- record is made after admission (nil, 'limit' when no room) and an exported state is imported into it.
function R.get(name, addr, ident, init)
    local p = pools[name]
    if not p or addr == nil then return nil, 'bad_args' end
    local rec = p.by[addr]
    if rec then
        if rec.epoch ~= epoch then drop(p, rec, 'stale') rec = nil
        elseif ident ~= nil and rec.ident ~= ident then drop(p, rec, 'reused') rec = nil
        else return rec, false end
    end
    if not init then return nil, 'missing' end
    rec = type(init) == 'table' and init or {}
    rec.addr, rec.ident, rec.epoch = addr, ident, epoch
    if rec.born == nil then rec.born = clock() end
    local w = weight_of(p, rec)
    local ok, why = R.admit(name, w)
    if not ok then return nil, why end
    seq = seq + 1
    rec._w, rec._seq, rec._gone = w, seq, nil
    p.by[addr] = rec
    p.list[#p.list + 1] = rec
    p.wsum = p.wsum + w
    local key = key_of(addr, ident)
    local st = p.exports[key]
    if st ~= nil and p.import then
        p.exports[key] = nil
        for i, k in ipairs(p.export_order) do if k == key then table.remove(p.export_order, i) break end end
        local oki = pcall(p.import, rec, st)
        if oki then p.imported = p.imported + 1 end
    end
    return rec, true
end

-- The object went (destroyed, culled by its owner): no export, no evict call
function R.forget(name, addr, why)
    local p = pools[name]
    local rec = p and addr ~= nil and p.by[addr]
    if not rec then return false end
    unlink(p, rec)
    return true, why
end

-- Every live record of the pool, oldest first (a forget inside fn is safe)
function R.each(name, fn)
    local p = pools[name]
    if not p then return 0 end
    local list, n = {}, 0
    for i, rec in ipairs(p.list) do list[i] = rec end
    for _, rec in ipairs(list) do
        if not rec._gone and rec.epoch == epoch then
            n = n + 1
            fn(rec)
        end
    end
    return n
end

function R.count(name)
    local p = pools[name]
    if not p then return 0, 0 end
    return #p.list, p.wsum
end

-- Over the cap (a lower setting, live): at most TRIM_PER_FRAME evictions, highest score first. Returns n, more.
function R.trim(name)
    local p = pools[name]
    if not p then return 0, false end
    local cap = cap_of(p)
    if p.wsum <= cap then return 0, false end
    local n = 0
    for _, c in ipairs(candidates(p, clock())) do
        if p.wsum <= cap or n >= R.TRIM_PER_FRAME then break end
        evict_one(p, c.rec, c.s)
        n = n + 1
    end
    return n, p.wsum > cap
end

function R.epoch() return epoch end
-- A record handed out earlier is still the live one of its pool and epoch
function R.valid(rec) return type(rec) == 'table' and not rec._gone and rec.epoch == epoch end

-- A new world: every record goes at once (stale, counted; no export and no evict call: the objects went with it)
function R.bump_epoch()
    epoch = epoch + 1
    for _, p in pairs(pools) do
        for _, rec in ipairs(p.list) do
            rec._gone = true
            p.stale = p.stale + 1
        end
        p.list, p.by, p.wsum = {}, {}, 0
    end
    return epoch
end

-- A map change: every record of the old world is stale; exports stay (bounded)
function R.reset() R.bump_epoch() end
function R.shutdown() pools, seq = {}, 0 end

function R.status()
    local out = {}
    for name, p in pairs(pools) do
        local cap = cap_of(p)
        out[name] = { n = #p.list, weight = p.wsum, cap = cap ~= math.huge and cap or nil, evicted = p.evicted,
            reused = p.reused, stale = p.stale, imported = p.imported, exports = #p.export_order }
    end
    return { epoch = epoch, pools = out }
end

return R
