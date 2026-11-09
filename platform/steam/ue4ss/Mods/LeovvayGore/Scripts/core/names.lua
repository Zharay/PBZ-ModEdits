-- status: worked DD2 origin: kb:testing-lab-playtest#engine-name-tables-plus-a-name-lint-against-the-dump
-- names.lua: every engine name a module uses, as data, so tools/lint/lint_names.py can check the tables against a dump
-- of the exact game build and the env record can report names_total / names_missing / names_pending. Each module
-- declares:
--   local N = { key = { 'Type', 'method(Param, Types)' } }     methods: key -> { declaring type, signature }
--   local F = { { 'Type', 'Field' } }                           fields
--   NAMES.register(N, F)
-- (keep that literal table syntax: the lint brace-matches it). On UE the Type is the declaring object path, the form
-- lint_names reads ('/Script/<Module>.<Class>', the base class for an inherited method), or a Blueprint class path
-- ('/<Mount>/<Dir>/BP_X.BP_X_C'). Keys are unique project-wide: the same key with another definition is flagged as
-- 'duplicate key <k>' in missing(). The adapter supplies the resolvers at init:
--   opts.resolve_path(path) -> handle | nil[, reason]   UE: path = NAMES.path(type, sig) = '<type>:<bare name>' (the
--       signature up to '('), the RegisterHook form; missing() lists that path
--   opts.resolve_method(type, sig) -> handle | nil[, reason]   only when resolve_path is absent (a TDB 'Type::sig'
--       form, REFramework); missing() lists 'Type::sig'
--   opts.resolve_field(type, fields) -> { [field] = handle | false } | nil[, reason]: ONE call covers every unresolved
--       field of one declaring class (UE: one ForEachProperty pass); nil means the class pass is unavailable
--       (pending on a Blueprint class or with a reason; on a /Script or TDB class every field is missing)
--   opts.class_loaded(type) -> bool (optional; default resolve_path(type) ~= nil): asked after a Blueprint miss
--   opts.lazy = true: nothing resolves at register; NAMES.step() resolves one entry per call (the sorted method keys,
--   then one declaring class of fields per step), NAMES.get and NAMES.field resolve on first use. A lazy miss is
--   remembered until NAMES.reset() (map change), so a kill path never repeats a slow failed lookup [inferred SWZC].
--   Eager (default, REFramework): register resolves at once.
-- Pending, never missing: a Blueprint class not loaded yet ('not_loaded'), a resolver that answers nil with a reason
-- (e.g. 'meta_off'), a Blueprint field class pass that answers nil ('not_loaded'). A reset retries them.
-- Missing: a lookup that answers nil, a /Script or TDB field class pass that answers nil without a reason, a resolver
-- that raises, or no resolver at all (a wiring fault stays visible).
-- API: register, get(key) -> handle | nil, has(key), field(type, field), def(key) -> type, sig, path(type, sig),
--      keys(), names_total(), missing(), pending() -> { {name, class, reason} }, step() -> entry, state | nil,
--      done(); lifecycle init(A, opts) / shutdown / status / reset.
-- Evidence: [worked DD2] core/engine.lua 1-127 (E.register, missing, names_total); lazy UE resolution [inferred SWZC]
-- kb:runtime-safety-perf#ue4ss-lookup-caching-and-staggered-warm-up; the path form: lint_names.py UPATH (S2.6, D22)
local NAMES = {}

local DEF, H, MISS, PEND, dup = {}, {}, {}, {}, {}  -- key -> def, handle | false, miss text, pending entry, dup flag
local FDEF, FIELDS, FPEND = {}, {}, {}              -- type -> {field = true}; 'T.f' -> handle | false; type -> reason
local resolve_p, resolve_m, resolve_f, loaded_f, lazy = nil, nil, nil, nil, false
local ORDER, cur = nil, 1                           -- the step queue (nil: rebuild) and its cursor

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- ok (false when fn is absent or raised), the handle, the resolver's reason
local function try(fn, a, b)
    if not fn then return false end
    local ok, h, why = pcall(fn, a, b)
    if not ok then return false end
    return true, h, why
end

-- The signature up to '(', trimmed; inner spaces stay (a Blueprint function may be named 'On Death Delay')
function NAMES.path(t, sig)
    local s = tostring(sig)
    return t .. ':' .. s:match('^[^%(]*'):match('^%s*(.-)%s*$')
end

-- A Blueprint (or any content) class path: loads late, so a miss may only mean 'not loaded yet'
local function is_bp(t) return t:sub(1, 1) == '/' and t:sub(1, 8) ~= '/Script/' end

-- True unless a check says the class is not loaded (a check that cannot run keeps the miss visible)
local function class_loaded(t)
    local ok, v
    if loaded_f then ok, v = try(loaded_f, t) v = v == true
    elseif resolve_p then ok, v = try(resolve_p, t) v = v ~= nil and v ~= false
    else return true end
    return not ok or v
end

local function resolve(k)
    local d = DEF[k]
    local name, ok, h, why
    if resolve_p then
        name = NAMES.path(d[1], d[2])
        ok, h, why = try(resolve_p, name)
    else
        name = d[1] .. '::' .. d[2]
        ok, h, why = try(resolve_m, d[1], d[2])
    end
    if ok and h ~= nil and h ~= false then H[k], MISS[k], PEND[k] = h, nil, nil return h end
    H[k], MISS[k], PEND[k] = false, nil, nil
    if ok and type(why) == 'string' then
        PEND[k] = { name = name, class = d[1], reason = why }
    elseif ok and is_bp(d[1]) and not class_loaded(d[1]) then
        PEND[k] = { name = name, class = d[1], reason = 'not_loaded' }
    else
        MISS[k] = name
    end
    return nil
end

-- One resolve_field call for every unresolved field of one declaring class -> 'ok' | 'missing' | 'pending'.
-- A pass that answers nil is pending only with a reason or on a Blueprint class; a /Script (or TDB) class is there
-- from the start, so a nil pass there is a wrong class name and its fields are missing
local function field_pass(t)
    local want = {}
    for f in pairs(FDEF[t] or {}) do if FIELDS[t .. '.' .. f] == nil then want[#want + 1] = f end end
    if #want == 0 then return 'ok' end
    table.sort(want)
    FPEND[t] = nil
    local ok, r, why = try(resolve_f, t, want)
    if ok and r == nil and (type(why) == 'string' or is_bp(t)) then
        FPEND[t] = type(why) == 'string' and why or 'not_loaded'
        return 'pending'
    end
    local state = 'ok'
    for _, f in ipairs(want) do
        local h = ok and type(r) == 'table' and r[f] or false
        FIELDS[t .. '.' .. f] = h
        if not h then state = 'missing' end
    end
    return state
end

function NAMES.init(_, opts)
    opts = opts or {}
    DEF, H, MISS, PEND, dup = {}, {}, {}, {}, {}
    FDEF, FIELDS, FPEND, ORDER, cur = {}, {}, {}, nil, 1
    resolve_p, resolve_m, resolve_f = opts.resolve_path, opts.resolve_method, opts.resolve_field
    loaded_f, lazy = opts.class_loaded, opts.lazy == true
    return true
end

function NAMES.register(N, F)
    for k, v in pairs(N or {}) do
        local d = DEF[k]
        if d and (d[1] ~= v[1] or d[2] ~= v[2]) then dup[k] = true end
        if not (d and d[1] == v[1] and d[2] == v[2] and H[k]) then
            DEF[k], H[k], MISS[k], PEND[k] = v, nil, nil, nil
            if not lazy then resolve(k) end
        end
    end
    local classes = {}
    for _, v in ipairs(F or {}) do
        local t = v[1]
        FDEF[t] = FDEF[t] or {}
        if not FDEF[t][v[2]] then FDEF[t][v[2]], classes[t] = true, true end
    end
    ORDER = nil
    if not lazy then for _, t in ipairs(sorted_keys(classes)) do field_pass(t) end end
end

function NAMES.get(k)
    local h = H[k]
    if h then return h end
    if h == false or not DEF[k] then return nil end
    return resolve(k)
end
function NAMES.has(k) return NAMES.get(k) ~= nil end
-- Lazy: the first use of an unresolved field runs its class pass (one call for the whole class)
function NAMES.field(t, f)
    local k = t .. '.' .. f
    if FIELDS[k] == nil and FDEF[t] and FDEF[t][f] and not FPEND[t] then field_pass(t) end
    return FIELDS[k] or nil
end
function NAMES.def(k) local d = DEF[k] if d then return d[1], d[2] end return nil end
function NAMES.keys() return sorted_keys(DEF) end
function NAMES.names_total() local n = 0 for _ in pairs(DEF) do n = n + 1 end return n end
local function fields_total() local n = 0 for _, fs in pairs(FDEF) do for _ in pairs(fs) do n = n + 1 end end return n end

-- A sorted copy: method misses, field misses, then duplicates (pending names are never listed here)
function NAMES.missing()
    local out = {}
    for _, k in ipairs(sorted_keys(MISS)) do out[#out + 1] = MISS[k] end
    for _, k in ipairs(sorted_keys(FIELDS)) do if FIELDS[k] == false then out[#out + 1] = k end end
    for _, k in ipairs(sorted_keys(dup)) do out[#out + 1] = 'duplicate key ' .. k end
    return out
end

-- Names not checked yet, sorted by name: { name ('<path>:<bare>' or 'T.Field'), class, reason }, plain copies
function NAMES.pending()
    local out = {}
    for _, p in pairs(PEND) do out[#out + 1] = { name = p.name, class = p.class, reason = p.reason } end
    for t, why in pairs(FPEND) do
        for f in pairs(FDEF[t] or {}) do
            if FIELDS[t .. '.' .. f] == nil then out[#out + 1] = { name = t .. '.' .. f, class = t, reason = why } end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ---------- staggered resolution: one entry per step (UE: one lookup per frame, timed by the caller) ----------
local function queue()
    if not ORDER then
        ORDER, cur = {}, 1
        for _, k in ipairs(sorted_keys(DEF)) do ORDER[#ORDER + 1] = { k } end
        for _, t in ipairs(sorted_keys(FDEF)) do ORDER[#ORDER + 1] = { t, true } end
    end
    return ORDER
end
local function open(e)
    if not e[2] then return H[e[1]] == nil end
    if FPEND[e[1]] then return false end
    for f in pairs(FDEF[e[1]]) do if FIELDS[e[1] .. '.' .. f] == nil then return true end end
    return false
end
local function next_open()
    local q = queue()
    while cur <= #q and not open(q[cur]) do cur = cur + 1 end
    return q[cur]
end

-- Resolves the next unresolved entry: a method key -> key, 'ok' | 'missing' | 'pending'; a declaring class of fields
-- -> '<type>.*', state. nil when nothing is left (done)
function NAMES.step()
    local e = next_open()
    if not e then return nil end
    if e[2] then return e[1] .. '.*', field_pass(e[1]) end
    if resolve(e[1]) ~= nil then return e[1], 'ok' end
    return e[1], PEND[e[1]] and 'pending' or 'missing'
end
function NAMES.done() return next_open() == nil end

-- A map change: misses and pending entries are forgotten (the class may exist now) and re-queued; handles stay
function NAMES.reset()
    for k, h in pairs(H) do if h == false then H[k], MISS[k], PEND[k] = nil, nil, nil end end
    for k, h in pairs(FIELDS) do if h == false then FIELDS[k] = nil end end
    FPEND, ORDER = {}, nil
end
function NAMES.shutdown() H, PEND, ORDER = {}, {}, nil end
function NAMES.status()
    return { total = NAMES.names_total(), fields = fields_total(), missing = #NAMES.missing(),
        pending = #NAMES.pending(), done = NAMES.done() }
end

return NAMES
