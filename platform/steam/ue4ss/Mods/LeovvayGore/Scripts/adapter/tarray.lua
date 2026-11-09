-- status: worked SWZC (top-level TArrays; the leak estimate is a measured rule of thumb) origin: kb:runtime-safety-perf#ue4ss-hook-params-out-params-and-tarray-arguments
-- tarray.lua: plain Lua tables as UFunction TArray arguments on UE4SS 527a483b-class builds.
-- * Open question on PBZ (UE4SS cdbc0b66 = Vercadi 1.0.1; dff435dd = 1185 carries the same Lua marshalling, RT26):
--   whether top-level TArray arguments marshal there at all is unproven. S-TARRAY in TC-LAB-02 proves it in game (a
--   1-triangle ProceduralMeshComponent probe, then the generic nub; PLAN A8, U15); offline mocks never prove it.
-- * Only a TOP-LEVEL argument: a table for a TArray field inside a struct argument reads the wrong slot.
-- * A pure 1-based sequence of elements with the reflected field names ({X,Y,Z}, {R,G,B,A}): no holes, no key 0, no
--   string keys; scalars are numbers. An empty TArray is {} and never nil (a nil argument is not popped: every later
--   param shifts). TA.check(arr, kind) before the call returns n or nil, why.
-- * One element conversion error leaves the Lua state's converter stuck: TA.poison(where) after any failed call, and
--   every later TA.check refuses ('poisoned') until a hot reload gives a new state.
-- * Converted arrays are never freed (D19, R2-B20): TA.charge(verts, indices, kind) books (verts*64 + indices*4)*1.3
--   bytes per converted mesh, indices being the flat index count (3 per triangle; the leak bytes GM tools/gibs/
--   to_lua_mesh.py prints), and TA.pmc(n) books 27 KB per ProceduralMeshComponent made (each leaked about 26-28 KB).
--   Budgets: opts.budget_mb 32 per session for the whole route, arrays plus components (hot reload is off on PBZ, so a
--   session is one Lua state), and opts.lab_mb 4 for the converted arrays of lab stand-ins (kinds in TA.LAB_KINDS).
--   A charge past either budget books nothing and returns false, 'leak_budget'; a bad count returns 'bad_count'.
-- * TA.book(bytes, kind) books bytes the caller computed (M1a D16: S-SKIN's converted out arrays, kind 'skin', about
--   (8 B x 12 influences + 64 B) x 1.3 per GetVertexBoneWeights call and 224 B x 1.3 per bone, booked per chunk before it
--   runs) against the session budget, kind 'skin' also against opts.skin_mb 20 [P]; never against the lab sub-budget
--   (a lab stand-in kind is refused 'lab_kind': its arrays book through TA.charge). The charge rules are unchanged.
-- * Kind TA.CAP 'cap' (the player beta's Caps, docs/research/beta-dismemberment-plan.md BD4): the sections of
--   data/caps_beta.lua charge against the session budget only, never the lab sub-budget (in it the Caps would turn to
--   meat after about 26 heads), and are tallied apart as cap_bytes for the per-cut record.
--   status: bytes (converted arrays, booked bytes included), lab_bytes, skin_bytes, cap_bytes, pmc (components),
--   route_kb (arrays plus components, KB rounded up).
-- * TA.probe(fn): run one tiny call once per session to learn whether TArray arguments work here at all.
-- * Reading an engine TArray: bound every loop by #arr; indexing past the end GROWS the game's array.
-- API: init(opts) check(arr, kind) poison(where) poisoned() charge(verts, indices, kind) pmc(n) book(bytes, kind)
--   probe(fn) status reset shutdown
-- Evidence: [worked SWZC] lib/tarray.lua, tools/luatest/test_debris_custom.lua; engine note 'UE5 / UE4SS 527a483b'
local LOG = require('core.log')

local TA = { KINDS = { vec = { 'X', 'Y', 'Z' }, vec2 = { 'X', 'Y' }, color = { 'R', 'G', 'B', 'A' }, int = true,
    float = true } }

local MB = 1024 * 1024
TA.PMC_BYTES = 27 * 1024                                     -- booked per ProceduralMeshComponent (D19)
TA.LAB_KINDS = { probe = true, nub = true, standin = true }  -- lab stand-in routes: the opts.lab_mb sub-budget too
TA.CAP = 'cap'                                               -- the beta's Caps: the session budget only (BD4)

local function fresh(opts)
    return { poisoned = nil, bytes = 0, lab_bytes = 0, pmc = 0, budget = (opts.budget_mb or 32) * MB,
        lab_budget = (opts.lab_mb or 4) * MB, skin_bytes = 0, skin_budget = (opts.skin_mb or 20) * MB, cap_bytes = 0,
        refused = 0, probed = nil, calls = 0 }
end
local st = fresh({})

function TA.init(opts)
    st = fresh(opts or {})
    return true
end

local function elem_ok(v, kind)
    local spec = TA.KINDS[kind]
    if spec == true then
        if kind == 'int' then return math.type(v) == 'integer' end
        return type(v) == 'number'
    end
    if type(spec) ~= 'table' then return type(v) == 'table' end      -- a struct kind the caller vouches for
    if type(v) ~= 'table' then return false end
    for _, f in ipairs(spec) do if type(v[f]) ~= 'number' then return false end end
    return true
end

-- n, or nil and why: poisoned, not_table, not_sequence, bad_element
function TA.check(arr, kind)
    if st.poisoned then st.refused = st.refused + 1 return nil, 'poisoned' end
    if type(arr) ~= 'table' then return nil, 'not_table' end
    local n, count = #arr, 0
    for k in pairs(arr) do
        if math.type(k) ~= 'integer' or k < 1 or k > n then return nil, 'not_sequence' end
        count = count + 1
    end
    if count ~= n then return nil, 'not_sequence' end
    for i = 1, n do
        if not elem_ok(arr[i], kind) then return nil, 'bad_element' end
    end
    st.calls = st.calls + 1
    return n
end

function TA.poison(where)
    if st.poisoned then return end
    st.poisoned = tostring(where or '?')
    LOG.warn('tarray_poisoned', { where = st.poisoned, msg = 'TArray arguments are off until a hot reload' })
end
function TA.poisoned() return st.poisoned end

local function route_bytes() return st.bytes + st.pmc * TA.PMC_BYTES end

local function count(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v == math.huge then return nil end
    return v
end

local function refuse(which, want, kind)
    st.refused = st.refused + 1
    if LOG.every('tarray_budget_' .. which, 60) then
        local lab, skin = which == 'lab', which == 'skin'
        LOG.warn('tarray_budget', { budget = which, kind = kind, want = want,
            bytes = lab and st.lab_bytes or skin and st.skin_bytes or route_bytes(),
            cap = lab and st.lab_budget or skin and st.skin_budget or st.budget })
    end
    return false, 'leak_budget'
end

-- Book one converted mesh: true, bytes; false, 'leak_budget' past the session or (lab kinds) the lab budget, nothing
-- booked then; false, 'bad_count'. A triangle count passed as indices would under-book the indices 3x. Kind TA.CAP
-- is tallied in cap_bytes too.
function TA.charge(verts, indices, kind)
    local v, i = count(verts), count(indices)
    if not v or not i then return false, 'bad_count' end
    local b = math.floor((v * 64 + i * 4) * 1.3)
    local lab = TA.LAB_KINDS[kind] == true
    if route_bytes() + b > st.budget then return refuse('session', b, kind) end
    if lab and st.lab_bytes + b > st.lab_budget then return refuse('lab', b, kind) end
    st.bytes = st.bytes + b
    if lab then st.lab_bytes = st.lab_bytes + b end
    if kind == TA.CAP then st.cap_bytes = st.cap_bytes + b end
    return true, b
end

-- Book n ProceduralMeshComponents (default 1) against the session budget: true, bytes; false, 'leak_budget' or
-- 'bad_count'. Their leak is not a converted array, so it stays out of the lab sub-budget.
function TA.pmc(n)
    n = count(n == nil and 1 or n)
    n = n and math.tointeger(n)
    if not n then return false, 'bad_count' end
    local b = n * TA.PMC_BYTES
    if route_bytes() + b > st.budget then return refuse('session', b, 'pmc') end
    st.pmc = st.pmc + n
    return true, b
end

-- Book bytes the caller computed (rounded up) against the session budget, and kind 'skin' also against the skin
-- sub-budget (D16); the lab sub-budget is never reached from here. true, bytes; false, 'leak_budget' past either
-- budget (nothing booked), 'bad_count' (not a finite number at or over 0) or 'lab_kind' (a TA.LAB_KINDS kind)
function TA.book(bytes, kind)
    local v = count(bytes)
    if not v then return false, 'bad_count' end
    if TA.LAB_KINDS[kind] then return false, 'lab_kind' end
    local b = math.ceil(v)
    local skin = kind == 'skin'
    if route_bytes() + b > st.budget then return refuse('session', b, kind) end
    if skin and st.skin_bytes + b > st.skin_budget then return refuse('skin', b, kind) end
    st.bytes = st.bytes + b
    if skin then st.skin_bytes = st.skin_bytes + b end
    return true, b
end

-- fn() -> truthy when a tiny TArray call worked; run once, the answer kept for the session
function TA.probe(fn)
    if st.probed ~= nil then return st.probed end
    local ok, r = pcall(fn)
    st.probed = ok and r ~= nil and r ~= false
    if not st.probed then TA.poison('probe') end
    LOG.info('tarray_probe', { ok = st.probed, err = (not ok) and tostring(r) or nil })
    return st.probed
end

function TA.status()
    return { poisoned = st.poisoned, bytes = st.bytes, budget = st.budget, lab_bytes = st.lab_bytes,
        lab_budget = st.lab_budget, skin_bytes = st.skin_bytes, skin_budget = st.skin_budget, cap_bytes = st.cap_bytes,
        pmc = st.pmc, route_kb = math.ceil(route_bytes() / 1024), refused = st.refused, probed = st.probed,
        calls = st.calls }
end
function TA.reset() end
function TA.shutdown() end

return TA
