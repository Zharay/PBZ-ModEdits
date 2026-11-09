-- status: worked SWZC (call_uncallable worked live for one function; the texture keeper untested) origin: kb:runtime-safety-perf#ue4ss-identity-safe-caches-delayed-steps-and-destroy
-- ue.lua: the bridge. Every UObject touch, raw lookup and loader registration goes through here (lint L004/L019), so
-- the marshalling rules live in one file. The loaders here: Vercadi 1.0.1 reports Git SHA cdbc0b66c (R/data/logs/
-- UE4SS.log:2), a custom DLL whose changes are unread (docs/research/runtime-tooling.md:24, :115); the official 1185
-- reports dff435dd (the 2026-10-30 UE4SS.log:2, M0 spec 2.4), 2 commits past cdbc0b66 that change only
-- UE4SS/CMakeLists.txt, so its Lua marshalling is the same (runtime-tooling.md:38, RT26). The rules below are read in
-- the RE-UE4SS cdbc0b66 source (U = UE4SS/src, UI = UE4SS/include, LMS = deps/first/LuaMadeSimple, under
-- R/scratch/gore-feasibility-20261029-1504/work/runtime-tooling/dl_ue4ss_src). Source is evidence, never proof:
-- tests/test_ue4ss_marshal.lua runs every case under both mock builds (scalar_out_shift, tarray_poison), and the
-- lab's executed calls decide.
-- * Every Lua UFunction call goes through ProcessEvent (U/LuaType/LuaUObject.cpp:285); a wrong arity is a Lua error
--   (:187-192). FName params take FName userdata (ue.fname, cached); a Lua string is undefined behaviour. Every param
--   is passed (no defaults); bools are true/false (0 is true); enums are integers; always call with ':'.
-- * An unknown member of a valid UObject is an invalid-object userdata, never nil (LuaUObject.cpp:2258-2267): an LMS
--   'TrivialObject' over special_invalid_ptr (LMS/include/LuaMadeSimple/LuaObject.hpp:121-138) whose IsValid is false
--   (:171-180) and whose metatable has only __index and __newindex (:191-202; __call only when given, LMS/src/
--   LuaMadeSimple.cpp:597), so calling it raises 'attempt to call a userdata value'. ue.call never calls it: it runs
--   a member only when it is a function or a valid object, never on a nil test, and names the miss 'no function'.
--   A found UFunction is valid (LuaUFunction.cpp:33-55 adds it to the object map). A build whose invalid member is a
--   UObject would answer a call with nothing (UObject's __call raises only on nullptr, UI/LuaType/LuaUObject.hpp:
--   512-520); the IsValid test refuses that shape too. Callers pass function names only: a valid object property
--   named as fn would run that silent __call.
-- * Structs are full tables with exact-case fields: a missing field reads 0 (Scale3D 0 = invisible, quaternion W 0).
--   A const by-ref struct (the FTransform of a spawn) is an in param: a plain full table, not written back.
-- * Each non-const out param needs its own table, struct and array outs filled in place (LuaUObject.cpp:230-251);
--   each scalar-out table is popped on its own (discard_value's index 1, LMS/include/LuaMadeSimple/LuaMadeSimple.hpp:
--   527), the 527a483b shift fixed by PR #1454 (runtime-tooling.md:30, RT18). Unproven on the custom DLL; the mock
--   models the old rule as one shared table (an arity error for the other form), the real old build misread later
--   params instead (refuted.md:37). After the call a scalar out sits in its table under the param's name (read
--   t.bOutX; a missing key is unread, never false) and a struct, array or set out fills its table in place
--   (LuaUObject.cpp:303-307, :334-337).
-- * Hook params arrive wrapped: an object as RemoteUnrealParam (LuaUObject.cpp:471-472), a struct as a
--   LocalUnrealParam over a struct wrapper (:825-826). Unwrap with :get() inside the body (ue.p), copy plain values.
-- * UObject userdata has __eq, a pointer compare (LuaUObject.cpp:2212-2235, LuaUObject.hpp:522): equal addresses,
--   not identity. ue.same compares addresses. IsValid checks the object array and the unreachable flag, not the
--   identity: a reused address passes. So anything kept past the call is a record { obj, name, epoch } (ue.keep) and
--   ue.live(rec) re-checks valid AND same name AND same epoch; a record that failed never goes back to native code.
--   Mod-made objects share default short names, so they keep and compare the full name (ue.keep_mod, M1a D24).
-- * RegisterHook takes a native function (FUNC_Native, Func not ProcessInternal) or a Blueprint script function
--   (Func is ProcessInternal) and raises on anything else (U/Mod/LuaMod.cpp:4241-4297); a script hook matches the
--   full outer chain (:1165-1185), so a /Script base declaration misses Blueprint overrides. NotifyOnNewObject needs
--   no loaded class (it stores the two FNames, :2304-2360), matches subclasses through GetSuperStruct and hands the
--   callback the object itself, not a param (:6662-6753).
-- * Multicast delegates offer GetBindings: a list of { Object, FunctionName } or nil (U/LuaType/
--   LuaXDelegateProperty.cpp:279-316). TMap: # is Num, ForEach(fn(key, value)) passes params to :get() and stops on
--   true (LuaTMap.cpp:62-67, :113-170). UFunctions have Get/SetFunctionFlags (LuaUFunction.cpp:78-90), UStructs
--   ForEachProperty (LuaUStruct.cpp:96-124).
-- * Lookups: 527a483b (SWZC) scanned GUObjectArray (a miss 45-47 ms); 1185 here uses the hash tables (a class 0.112
--   ms, M0 spec 2.4). ue.class/cdo/asset still cache hits AND misses until ue.reset_caches() at a map load (misses
--   only) or ue.forget_misses() (lab_end). Kill paths use ue.asset_peek (no lookup).
-- * The world is seeded from the LoadMap post hook (ue.set_world): never a per-use GetWorld/GetPlayerController scan
--   (a hot load mid-map falls back to one lookup per 30 s).
-- * K2_DestroyComponent(Object) destroys only when Object is the owner: ue.destroy passes the owner.
-- * call_uncallable runs a UFunction UE4SS cannot marshal (out params, TArray-in-struct) by text: FUNC_Exec 0x200 on,
--   CDO:ProcessConsoleExec('<Func> <args>', nil, executor), flags restored in the same frame and read back. Only
--   through the arm (sentinel + window); a failed import still returns true, so judge by the result.
-- Evidence: [worked SWZC] lib/ue.lua, lib/slice_copy.lua 301-390; kb:runtime-safety-perf#ue4ss-lookup-caching-and-staggered-warm-up,
-- #ue4ss-hook-params-out-params-and-tarray-arguments, #keep-transient-textures-and-mod-loaded-assets-alive-ue4ss;
-- kb:pieces-gibs-physics#spawned-gore-body-profile-and-lifecycle-ue; kb:dismember-core (leader hides)
local LOG = require('core.log')                 -- core.log requires only core.store: no require cycle with the bridge
local ue = { epoch = 0 }

local fname_cache, class_cache, cdo_cache, asset_cache = {}, {}, {}, {}
local first_cache, field_cache = {}, {}         -- ue.first_of answers, ue.fields passes: both last until a map load
local resolved_logged = {}                      -- path -> true: asset_resolved once per path per session (P19)
local world, keeper, world_next = nil, nil, 0          -- world_next: the earliest fallback lookup (os.clock s)
local stats = { finds = 0, misses = 0, uncallable = 0, refused = 0, writes = 0, find_all = 0, find_all_ms = 0,
    first_of = 0, first_of_ms = 0, first_asks = 0, meta = 0, find_ms = 0, miss_ms = 0, miss_ms_max = 0,
    miss_path = nil }
-- The world-writes counter (M0 S2.4): every helper that writes to the engine (a property set, a Set*/Add*/Spawn*/
-- Post*/Hide*/Destroy*/Attach* UFunction) bumps it once per write attempt, after its own validity checks, so an
-- attempt counts even when the call raises. Nested helpers each count (never_cull's ue.set calls too): the probe's
-- zero-writes gate reads only zero against non-zero (ue.status().writes). tests/test_ue4ss_lab_helpers.lua scans
-- this file and fails on a function that calls a write UFunction without wrote().
local function wrote() stats.writes = stats.writes + 1 end
-- The same counter for the write helpers outside this file (adapter/ue_lab.lua, adapter/ue_spawn.lua; M1a D3): n write
-- attempts, default 1; a fractional or non-number n counts 1, zero or a negative n adds nothing (the counter never
-- drops, so the zero-writes gate stays sound). The new total
function ue.count_write(n)
    n = type(n) == 'number' and math.tointeger(n) or 1
    if n > 0 then stats.writes = stats.writes + n end
    return stats.writes
end

-- Caught errors (M0 D9, review PASSIVE-1): the read helpers below (field/ue.prop, ue.get, ue.str, ue.name, ue.full,
-- ue.call, ue.weak, ue.tags, the lookups, the meta reads and the static engine reads) catch an error and answer nil
-- or false, so their callers never see its text. caught() keeps it: ue.last_err is the last caught text, and every
-- ue.on_error callback gets (text, helper, key) at once, inside the helper's frame (a hook body included: a callback
-- does no IO). lab_probe matches 'ArrayNum exceeds ArrayMax' there for its stop rule. A callback that raises is
-- skipped for that error only. Write helpers keep their own pcalls (the probe writes nothing), and ue.find_all hands
-- its error text back to the caller (nil, text), so it never counts as swallowed. ue.caught(err, helper, key) is the
-- same hand-over for a catch outside this file (a raw pcall in a lab module): the error as text (an error whose
-- __tostring raises reads 'unprintable error'), then ue.last_err, then every callback.
ue.last_err = nil
local err_subs = {}                             -- { key, fn } in registration order
-- fn(text, helper, key) on every caught error; key (default fn) names the entry, so a second registration under the
-- same key replaces it (a reloaded module) and fn nil removes it. true, or false without a key
function ue.on_error(fn, key)
    if key == nil then key = fn end
    if key == nil then return false end
    for i = #err_subs, 1, -1 do if err_subs[i].key == key then table.remove(err_subs, i) end end
    if type(fn) == 'function' then err_subs[#err_subs + 1] = { key = key, fn = fn } end
    return true
end
local function caught(err, helper, key)
    local ok, text = pcall(tostring, err)
    if not ok or type(text) ~= 'string' then text = 'unprintable error' end
    ue.last_err = text
    for i = 1, #err_subs do pcall(err_subs[i].fn, text, helper, key) end
end
ue.caught = caught
-- pcall's results passed through unchanged; a failure goes to caught() first
local function pass(helper, key, ok, ...)
    if not ok then caught((...), helper, key) end
    return ok, ...
end

-- Engine library CDOs only (game ones go in data/hooks.json 'classes' and through ue.cdo(path))
ue.CDO = {
    ksl = '/Script/Engine.Default__KismetSystemLibrary',
    gs = '/Script/Engine.Default__GameplayStatics',
    kml = '/Script/Engine.Default__KismetMathLibrary',
    krl = '/Script/Engine.Default__KismetRenderingLibrary',
    kmat = '/Script/Engine.Default__KismetMaterialLibrary',
    niagara = '/Script/Niagara.Default__NiagaraFunctionLibrary',
    akgs = '/Script/AkAudio.Default__AkGameplayStatics',
}
ue.FUNC_EXEC = 0x200

-- ---------- basics ----------
-- Real objects are userdata; the offline mock's are tables flagged __mock
local function is_obj(o)
    local t = type(o)
    return t == 'userdata' or (t == 'table' and rawget(o, '__mock') == true)
end
-- o's IsValid, or nil for a value without one. An FName on UE4SS has none (LuaFName.cpp:119-150 at cdbc0b66): a plain
-- index answers nil, while o:IsValid() raises, and every raise is a C++ throw (spec M1a 4.0, cost)
local function index(o, k) return o[k] end
local function isvalid_fn(o)
    local ok, f = pcall(index, o, 'IsValid')
    if ok then return f end
    return nil
end
function ue.valid(o)
    if o == nil or not is_obj(o) then return false end
    local f = isvalid_fn(o)
    if f == nil then return false end
    local ok, v = pcall(f, o)
    return ok and v == true
end
function ue.addr(o)
    if o == nil then return nil end
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok then return a end
    return nil
end
function ue.same(a, b)
    local x = ue.addr(a)
    return x ~= nil and x == ue.addr(b)
end
-- The cached FName for a name (refuses a non-string: never an FName from nil or a number)
function ue.fname(s)
    if type(s) ~= 'string' then error('ue.fname: a string name, got ' .. type(s), 2) end
    local f = fname_cache[s]
    if f then return f end
    if EFindName then f = FName(s, EFindName.FNAME_Add) else f = FName(s) end
    fname_cache[s] = f
    return f
end
function ue.str(v)
    local tv = type(v)
    if v == nil then return nil end
    if tv == 'string' or tv == 'number' or tv == 'boolean' then return tostring(v) end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == 'string' then return s end
    if not ok then caught(s, 'str') end
    return nil
end
function ue.name(o)
    if not ue.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    if not ok then caught(n, 'name') return nil end
    return n
end
function ue.full(o)
    if not ue.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetFullName() end)
    if not ok then caught(n, 'full') return nil end
    return n
end
-- Unwrap a param (RemoteUnrealParam / LocalUnrealParam): a hook param inside the callback, a TMap ForEach key, and
-- every element of a UFunction's TArray return or array out-param (pushed with Operation::GetParam, U/LuaType/
-- LuaUObject.cpp:838-867: an object, name or number as a RemoteUnrealParam, :471-472, a struct as a LocalUnrealParam,
-- :824-826); never store the wrapper. Only those two answer get (UI/LuaType/LuaUObject.hpp:886-894; LuaUObject.cpp,
-- RemoteUnrealParam's member functions); their other members read nil (no metamethods, :2361-2363). A plain UObject
-- answers an unknown member with an invalid object whose call raises (LuaUObject.cpp:2258-2267), an FName with nil,
-- and a struct raises on the index itself (LuaUScriptStruct.cpp:181-185). Every UE4SS type declares type() in its
-- member table (a raw lookup, no property search: LMS/src/LuaMadeSimple.cpp:540-556), so ue.p asks type() first and
-- reads get only on the two param types, and only when a plain index answers a function (as isvalid_fn does for
-- IsValid): nothing raises (spec M1a 4.0, cost: every raise is a C++ throw). A TArray PROPERTY's [i] is the element
-- itself (LuaTArray.cpp:59-60, :251: Operation::Get), so property reads use it as it is
local PARAM_TYPES = { LocalUnrealParam = true, RemoteUnrealParam = true }
function ue.p(param)
    if param == nil then return nil end
    if type(param) == 'table' and rawget(param, '__param') then return param:get() end
    if type(param) ~= 'userdata' then return param end
    local okt, tf = pcall(index, param, 'type')
    if not okt or type(tf) ~= 'function' then return param end
    local okn, tn = pcall(tf, param)
    if not okn or not PARAM_TYPES[tn] then return param end
    local okg, g = pcall(index, param, 'get')
    if not okg or type(g) ~= 'function' then return param end
    local ok, v = pcall(g, param)
    if ok then return v end
    return param
end
-- A member is callable when it is a Lua function (the offline mock, a loader C function such as TMap.ForEach) or a
-- valid object (a found UFunction userdata). On cdbc0b66 an unknown member is an invalid-object userdata, never nil
-- (header): a nil test let it through to a call that raised an opaque 'attempt to call' error, and on a build whose
-- invalid member answers a call with nothing it would be a silent success.
local function callable(f)
    if type(f) == 'function' then return true end
    return ue.valid(f)
end
-- A write UFunction by name: one of these prefixes followed by an upper-case letter (SetVariableFloat, K2_Destroy
-- Component, K2_SetWorldLocation, UnHideBoneByName). ue.call counts such a call as a world write. Only these verbs
-- count: a write named otherwise (Activate) through ue.call is not seen, so write helpers bump the counter themselves.
local WRITE_PREFIX = { 'K2_Attach', 'K2_Destroy', 'K2_Set', 'K2_Add', 'Set', 'Attach', 'Add', 'Destroy', 'Spawn', 'Post',
    'Hide', 'UnHide' }
local write_memo = {}                           -- name -> bool: ue.call asks on every call
function ue.write_name(fn)
    if type(fn) ~= 'string' then return false end
    local w = write_memo[fn]
    if w ~= nil then return w end
    w = false
    for _, p in ipairs(WRITE_PREFIX) do
        if fn:sub(1, #p) == p and fn:sub(#p + 1, #p + 1):match('^%u$') then w = true break end
    end
    write_memo[fn] = w
    return w
end
function ue.call(o, fn, ...)
    if not ue.valid(o) then return false, 'invalid object' end
    if ue.write_name(fn) then wrote() end
    local args = table.pack(...)
    return pass('call', fn, pcall(function()
        local f = o[fn]
        if not callable(f) then error('no function ' .. tostring(fn)) end
        return f(o, table.unpack(args, 1, args.n))
    end))
end
function ue.get(o, prop)
    if not ue.valid(o) then return nil end
    local ok, v = pcall(function() return o[prop] end)
    if ok then return v end
    caught(v, 'get', prop)
    return nil
end
function ue.set(o, prop, v)
    if not ue.valid(o) then return false end
    wrote()
    return (pcall(function() o[prop] = v end))
end
-- Full structs: every field set (W = 1, Scale3D = 1)
function ue.vec(x, y, z) return { X = (x or 0) + 0.0, Y = (y or 0) + 0.0, Z = (z or 0) + 0.0 } end
function ue.rot(p, y, r) return { Pitch = (p or 0) + 0.0, Yaw = (y or 0) + 0.0, Roll = (r or 0) + 0.0 } end
function ue.xform(loc, quat, scale)
    return { Translation = loc or ue.vec(), Rotation = quat or { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
        Scale3D = scale or ue.vec(1, 1, 1) }
end

-- ---------- identity records ----------
function ue.keep(o, name)
    if not ue.valid(o) then return nil end
    return { obj = o, name = name or ue.name(o), epoch = ue.epoch }
end
-- The object while it is still the one kept: valid, same name, same map epoch; else nil and why
function ue.live(rec)
    if type(rec) ~= 'table' or rec.obj == nil then return nil, 'none' end
    if rec.epoch ~= ue.epoch then return nil, 'stale' end
    if not ue.valid(rec.obj) then return nil, 'gone' end
    if ue.name(rec.obj) ~= rec.name then return nil, 'reused' end
    return rec.obj
end
function ue.ours(o, name) return name ~= nil and ue.valid(o) and ue.name(o) == name end
-- Mod-made objects (M1a D24, M0 D31; refuted.md:113): the mod's components share default short names
-- (PoseableMeshComponent_0 on every Piece), so a short-name check takes a twin that reused the address for the kept
-- one. ue.keep_mod keeps the full name too (GetFullName: the class and the outer chain, actor included) and
-- ue.live_mod compares that. Victims keep ue.keep. A record, or nil when the object is invalid or its full name unread
function ue.keep_mod(o)
    if not ue.valid(o) then return nil end
    local full = ue.full(o)
    if not full then return nil end
    return { obj = o, name = ue.name(o), full = full, epoch = ue.epoch }
end
-- The kept mod object while it is still the one kept: valid, same full name, same map epoch; else nil and why
-- ('none': no record or a record without a full name, 'stale', 'gone', 'reused')
function ue.live_mod(rec)
    if type(rec) ~= 'table' or rec.obj == nil or type(rec.full) ~= 'string' then return nil, 'none' end
    if rec.epoch ~= ue.epoch then return nil, 'stale' end
    if not ue.valid(rec.obj) then return nil, 'gone' end
    if ue.full(rec.obj) ~= rec.full then return nil, 'reused' end
    return rec.obj
end

-- ---------- lookups (cached, misses included) ----------
-- Every StaticFindObject is timed (ue.clock, 1 ms steps live): find_ms over all, miss_ms over the misses, the dearest
-- miss and the last missed asset's short name (ue.status). Session 20261101-lag: a miss cost about 23 ms on 1185 in
-- the open world (131 misses in 3.1 s of lab_blood time), a hit about 0.1 ms; so no hit path may look up a path
-- whose object may be gone (asset_peek's 'stale': ue.asset(path, true) reloads it off the hit path)
function ue.find(path)
    if not StaticFindObject or type(path) ~= 'string' then return nil end
    stats.finds = stats.finds + 1
    local t0 = ue.clock()
    local ok, o = pcall(StaticFindObject, path)
    local ms = (ue.clock() - t0) * 1000
    stats.find_ms = stats.find_ms + ms
    if ok and ue.valid(o) then return o end
    if not ok then caught(o, 'find', path) end
    stats.misses = stats.misses + 1
    stats.miss_ms = stats.miss_ms + ms
    if ms > stats.miss_ms_max then stats.miss_ms_max = ms end
    stats.miss_path = path:match('([^/.]+)$') or path
    return nil
end
-- The lookup counters as plain numbers (no engine call, unlike ue.status's world read): finds, misses, miss_ms
function ue.lookups() return stats.finds, stats.misses, stats.miss_ms end
local function cached(cache, key, path)
    local c = cache[key]
    if c == false then return nil end
    if type(c) == 'table' then
        if ue.name(c.obj) == c.name then return c.obj end
        cache[key] = nil
    end
    local o = ue.find(path)
    cache[key] = o and { obj = o, name = ue.name(o) } or false
    return o
end
function ue.class(path) return cached(class_cache, path, path) end
function ue.cdo(key) return cached(cdo_cache, key, ue.CDO[key] or key) end
-- An asset: found in memory, else LoadAsset (game thread). via 'found' | 'loaded' (nothing roots a loaded one: keep it
-- through ue.hold, or a GC takes it: transient textures and sounds ~60 s later, materials ~30 min).
-- The first resolve of a path in this session logs asset_resolved {asked, resolved = GetFullName, via} (P19, DESIGN
-- C13): a censored launch redirects packages to /Game/_Censored/ copies at the package store, and that resolved path is
-- logged as is. The mod only reads the censor state; it never writes the launch latch, the censor CVars,
-- PBZGameSettings or the redirect backend (pinned by a source scan in tests/test_ue4ss_ue.lua).
-- reload true (a cached object that went stale: the GC took it): no StaticFindObject (a miss costs about 23 ms, see
-- ue.find), LoadAsset alone, which answers the object in memory or loads it; via 'loaded'. A cached entry that went
-- stale is asked of LoadAsset first the same way (review: its StaticFindObject was a near-certain miss), and looked up
-- only when LoadAsset answers nothing (a path that is no registry asset: a Blueprint class '<asset>.<leaf>_C')
function ue.asset(path, reload)
    local c = asset_cache[path]
    if c == false then return nil end
    if type(c) == 'table' and ue.name(c.obj) == c.name then return c.obj, c.via end
    local stale = type(c) == 'table'
    local a, via = nil, 'found'
    if not (reload or stale) then a = ue.find(path) end
    if not a and LoadAsset then
        local ok, o = pcall(LoadAsset, path)
        if ok and ue.valid(o) then a, via = o, 'loaded' elseif not ok then caught(o, 'load', path) end
    end
    if not a and stale and not reload then a, via = ue.find(path), 'found' end
    asset_cache[path] = a and { obj = a, name = ue.name(a), via = via } or false
    if a and not resolved_logged[path] then
        resolved_logged[path] = true
        LOG.info('asset_resolved', { asked = path, resolved = ue.full(a) or 'unread', via = via })
    end
    return a, a and via or nil
end
-- One uncached LoadAsset(path) with its three answers (lab_spawn, spec M0 D32). UE4SS 1185 = cdbc0b66 LuaMod.cpp:
-- 3334-3380: game thread only (it raises 'can only be called from within the game thread' elsewhere), one string;
-- FName(path) goes to AssetRegistry GetAssetByObjectPath, then UAssetRegistryHelpers::GetAsset; it returns the object,
-- was_asset_found (the registry knows the path) and did_asset_load (GetAsset returned an object). A package can load
-- while GetAsset answers nothing ('Asset was found but not loaded, could be a package'), so callers look up what they
-- need afterwards. obj (nil when invalid), found, loaded | nil, nil, nil, err (missing, a bad path, or it raised: the
-- text goes to ue.caught first, so lab_probe's stop rule sees an ArrayNum text). ue.asset is the cached form.
function ue.load_asset(path)
    if not LoadAsset then return nil, nil, nil, 'no LoadAsset' end
    if type(path) ~= 'string' then return nil, nil, nil, 'bad path' end
    local ok, o, found, loaded = pcall(LoadAsset, path)
    if not ok then
        caught(o, 'load', path)
        return nil, nil, nil, tostring(o)
    end
    return ue.valid(o) and o or nil, found == true, loaded == true
end
-- The cached asset with no lookup at all (kill paths): obj, via | nil, via, 'stale' | nil
function ue.asset_peek(path)
    local c = asset_cache[path]
    if type(c) ~= 'table' then return nil end
    if ue.name(c.obj) == c.name then return c.obj, c.via end
    return nil, c.via, 'stale'
end
-- The cached misses of the class, CDO and asset caches go, so the next ask looks the path up again (a Blueprint class
-- loaded since: ue.fields then reads its fields instead of 'not_loaded', which it derives from the class miss alone).
-- Hits, the ue.fields and ue.first_of answers, the world, the keeper and the holds stay. session_pbz calls it on
-- lab_end (RUNTIME-6: the names re-lint between map loads). The number of misses dropped
function ue.forget_misses()
    local n = 0
    for _, cache in ipairs({ class_cache, cdo_cache, asset_cache }) do
        for k, v in pairs(cache) do
            if v == false then cache[k], n = nil, n + 1 end
        end
    end
    return n
end
-- A map load: misses are retried, hits stay (their names are re-checked on use); the world and keeper go, and every
-- hold ends with its host, taking the cache entry of what it held (P18: no cache hit outlives its holder)
local end_holds                                 -- defined with the keeper below
function ue.reset_caches()
    ue.forget_misses()
    first_cache, field_cache = {}, {}
    end_holds()
    world, keeper, world_next = nil, nil, 0
end
function ue.bump_epoch() ue.epoch = ue.epoch + 1 return ue.epoch end
function ue.set_world(w) world = ue.valid(w) and ue.keep(w) or nil end
-- The world seeded at LoadMap. A hot load mid-map (Ctrl+R, a late install) gets no LoadMap: then one
-- FindFirstOf('PlayerController') + GetWorld at most every WORLD_RETRY_S (a full object scan here), game thread only
ue.WORLD_RETRY_S = 30
function ue.world()
    local w = world and ue.live(world) or nil
    if w or not FindFirstOf then return w end
    local now = os.clock()
    if now < world_next then return nil end
    world_next = now + ue.WORLD_RETRY_S
    local ok, pc = pass('first_of', 'PlayerController', pcall(FindFirstOf, 'PlayerController'))
    if not ok or not ue.valid(pc) then return nil end
    local okw, gw = pass('call', 'GetWorld', pcall(function() return pc:GetWorld() end))
    if not okw or not ue.valid(gw) then return nil end
    ue.set_world(gw)
    return gw
end

-- ---------- probe lookups (M0 S2.4). No helper arms a sentinel: the callers do (M0 spec section 3.4) ----------
-- ue.clock: seconds for the rate limits and timings (os.clock steps 1 ms here, refuted.md:127); tests swap it
ue.clock = os.clock
ue.FIND_ALL_CAP = 256
ue.FIRST_OF_RETRY_S = 5
-- One FindAllOf(short class name), timed and counted: a plain list of at most cap valid objects and
-- { n = valid objects found, capped, ms, why }; nil and why when there is no FindAllOf, no class name or it raised.
-- FindAllOf answers nil when it finds nothing: an empty list, n 0.
function ue.find_all(class, cap, why)
    if not FindAllOf or type(class) ~= 'string' then return nil, 'unavailable' end
    cap = math.tointeger(cap) or ue.FIND_ALL_CAP
    stats.find_all = stats.find_all + 1
    local t0 = ue.clock()
    local ok, all = pcall(FindAllOf, class)
    local out, n = {}, 0
    if ok and type(all) == 'table' then
        for i = 1, #all do
            if ue.valid(all[i]) then
                n = n + 1
                if #out < cap then out[#out + 1] = all[i] end
            end
        end
    end
    stats.find_all_ms = (ue.clock() - t0) * 1000
    if not ok then return nil, tostring(all) end      -- the text goes back to the caller: not swallowed
    return out, { n = n, capped = n > #out, ms = stats.find_all_ms, why = why }
end
-- FindFirstOf(short class name) at most once per FIRST_OF_RETRY_S per class; the answer, hit or miss, is cached until
-- a map load (ue.reset_caches), a hit as a keep record handed back while ue.live holds. obj | nil, why: 'wait' (a miss
-- or a lost hit inside the rate limit), 'none' (the lookup found nothing), 'unavailable'.
function ue.first_of(class)
    if not FindFirstOf or type(class) ~= 'string' then return nil, 'unavailable' end
    stats.first_asks = stats.first_asks + 1
    local c = first_cache[class]
    local o = c and c.rec and ue.live(c.rec)
    if o then return o end
    local now = ue.clock()
    if c and now < c.next then return nil, 'wait' end
    stats.first_of = stats.first_of + 1
    local ok, f = pass('first_of', class, pcall(FindFirstOf, class))
    stats.first_of_ms = (ue.clock() - now) * 1000
    o = ok and ue.valid(f) and f or nil
    first_cache[class] = { rec = o and ue.keep(o) or nil, next = now + ue.FIRST_OF_RETRY_S }
    if not o then return nil, 'none' end
    return o
end
-- StaticFindObject(path):GetFunctionFlags() as an integer; nil when the function is missing or the read raised
function ue.func_flags(path)
    local fn = ue.find(path)
    if not fn then return nil end
    local ok, f = pass('meta', path, pcall(function() return fn:GetFunctionFlags() end))
    return ok and type(f) == 'number' and math.tointeger(f) or nil
end
-- One ForEachProperty pass over a UStruct: a UFunction's params, or the fields a class declares itself (TFieldRange
-- without IncludeSuper, U/LuaType/LuaUStruct.cpp:96-124). A list of { name, class } from the FProperty's GetFName and
-- GetClass():GetFName() (LuaXProperty.cpp:97-128), or nil when the pass raised. The callback never raises and returns
-- nothing (a true return stops the loop).
local function each_prop(st)
    stats.meta = stats.meta + 1
    local out = {}
    local ok, err = pcall(function()
        st:ForEachProperty(function(p)
            local okn, name = pcall(function() return p:GetFName():ToString() end)
            local okc, cls = pcall(function() return p:GetClass():GetFName():ToString() end)
            if okn and type(name) == 'string' then
                out[#out + 1] = { name = name, class = okc and type(cls) == 'string' and cls or 'unread' }
            end
        end)
    end)
    if not ok then caught(err, 'meta') return nil end
    return out
end
-- A UFunction's params by path, in declaration order: { { name, class, ret }... } (ret: UHT names the return param
-- ReturnValue [inferred]); nil when the function is missing or the pass failed
function ue.func_params(path)
    local fn = ue.find(path)
    if not fn then return nil end
    local list = each_prop(fn)
    if not list then return nil end
    for _, p in ipairs(list) do p.ret = p.name == 'ReturnValue' end
    return list
end
-- The fields the class at type_path declares itself, { [lower-case name] = property class }, from one ForEachProperty
-- pass cached per class until a map load; nil, 'not_loaded' (no such class in memory: a Blueprint class may load later)
-- or nil, 'meta_failed' (the pass raised; cached too, so a failing class costs one pass per map); nil, 'bad_type' for a
-- path that is not a string (ue.class would raise on a nil key)
function ue.fields(type_path)
    if type(type_path) ~= 'string' then return nil, 'bad_type' end
    local c = field_cache[type_path]
    if c == false then return nil, 'meta_failed' end
    if c then return c end
    local cls = ue.class(type_path)
    if not cls then return nil, 'not_loaded' end
    local list = each_prop(cls)
    if not list then field_cache[type_path] = false return nil, 'meta_failed' end
    local set = {}
    for _, p in ipairs(list) do set[p.name:lower()] = p.class end
    field_cache[type_path] = set
    return set
end
-- Whether the class at type_path declares field (FNames compare case-insensitively): true | false | nil, why
function ue.has_field(type_path, field)
    if type(field) ~= 'string' then return nil, 'bad_field' end
    local set, why = ue.fields(type_path)
    if not set then return nil, why end
    return set[field:lower()] ~= nil
end
-- ---------- signatures (M1a D17) ----------
-- ue.sig_ok(path, want, name): the live params of the UFunction at path, from ue.func_params (the one each_prop pass
-- above, unchanged: no profile gains a reflection read), against want, the dump's list for that path (data/sigs.lua,
-- A0.5): entries { name, prop, out, const } by key or by position (a bare string is a name), ReturnValue apart on both
-- sides (the dump prints every return as void). Count, names and order are the hard check, names compared without case
-- as FNames compare (a cooked FName prints the case it was first made with); the FProperty classes go into types_ok,
-- only logged in M1a (a want prop 'unknown' or a live class 'unread' is not compared). want nil or an entry with no name
-- is false, 'sig_unknown' with no lookup at all; a function missing from memory or a failed pass is false,
-- 'sig_mismatch' with got 'unread'. Once per path per session: the first answer is kept across map loads (nothing is
-- retried, spec 3.5), with one forced sig record {path, name, ok, why, types_ok, want, got}, the lists as
-- 'Name:PropertyClass'; name is the caller's section 3.4 class, for the record only. No sentinel here: the caller arms
-- it (LAB.sig under 'probe.meta'). ok, why (nil when ok), types_ok (true, false or 'unread')
local sig_seen = {}                             -- path -> { ok, why, types_ok }: never cleared (once per session)
local function want_list(want)
    if type(want) ~= 'table' then return nil end
    local out = {}
    for i = 1, #want do
        local w, n, p = want[i], nil, nil
        if type(w) == 'string' then n = w elseif type(w) == 'table' then n, p = w.name or w[1], w.prop or w[2] end
        if type(n) ~= 'string' then return nil end
        if n:lower() ~= 'returnvalue' then out[#out + 1] = { name = n, prop = type(p) == 'string' and p or 'unknown' } end
    end
    return out
end
local function sig_strs(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.name .. ':' .. e.prop end
    return out
end
function ue.sig_ok(path, want, name)
    if type(path) ~= 'string' then return false, 'sig_unknown', 'unread' end
    local c = sig_seen[path]
    if c then return c.ok, c.why, c.types_ok end
    local w, got, ok, why, types_ok = want_list(want), nil, false, nil, 'unread'
    if not w then
        why = 'sig_unknown'
    else
        local list = ue.func_params(path)
        if list then
            got = {}
            for _, p in ipairs(list) do
                if not p.ret and p.name:lower() ~= 'returnvalue' then got[#got + 1] = { name = p.name, prop = p.class } end
            end
            ok, types_ok = #got == #w, true
            for i = 1, math.min(#got, #w) do
                local a, b = w[i], got[i]
                if a.name:lower() ~= b.name:lower() then ok = false end
                if a.prop ~= 'unknown' and b.prop ~= 'unread' and a.prop ~= b.prop then types_ok = false end
            end
        end
        if not ok then why = 'sig_mismatch' end
    end
    sig_seen[path] = { ok = ok, why = why, types_ok = types_ok }
    LOG.write('info', 'sig', { path = path, name = type(name) == 'string' and name or 'unread', ok = ok, why = why,
        types_ok = types_ok, want = w and sig_strs(w) or 'unread', got = got and sig_strs(got) or 'unread' }, true)
    return ok, why, types_ok
end
-- A console variable through the KismetSystemLibrary CDO (GetConsoleVariableIntValue / BoolValue, script_objects.tsv:
-- 18267-18269; one FString param in UE 5.x [inferred]): the value, or nil when the CDO or the getter is missing, the
-- call raised or the answer has another type. UE reads an unregistered CVar as 0 or false: a 0 does not prove it exists.
local function cvar(fn, name, want)
    if type(name) ~= 'string' then return nil end
    local ksl = ue.cdo('ksl')
    if not ksl then return nil end
    local ok, v = ue.call(ksl, fn, name)
    if ok and type(v) == want then return v end
    return nil
end
function ue.cvar_int(name)
    local v = cvar('GetConsoleVariableIntValue', name, 'number')
    return v and math.tointeger(v) or nil
end
function ue.cvar_bool(name) return cvar('GetConsoleVariableBoolValue', name, 'boolean') end

-- ---------- probe property reads (M0 S2.4, D11): property chains only, never a UFunction ----------
-- True when v answers IsValid with false: an invalid object (an unknown member, an empty object field) or an invalid
-- struct, array or map wrapper. A value without IsValid (a number, a string, an FName) is kept.
local function answers_invalid(v)
    if not is_obj(v) then return false end
    local f = isvalid_fn(v)
    if f == nil then return false end
    local ok, r = pcall(f, v)
    return ok and r == false
end
-- One link of a property chain: v[name] from a valid object or a struct; nil when v is nothing, invalid, the read
-- raised or the answer is an invalid object
local function field(v, name)
    local t = type(v)
    if (t ~= 'table' and t ~= 'userdata') or answers_invalid(v) then return nil end
    local ok, r = pcall(function() return v[name] end)
    if not ok then caught(r, 'prop', name) return nil end
    if r == nil or answers_invalid(r) then return nil end
    return r
end
local function chain(v, ...)
    for i = 1, select('#', ...) do
        v = field(v, (select(i, ...)))
        if v == nil then return nil end
    end
    return v
end
-- A property read: the value, or nil (an invalid object, a raised read, an invalid-object answer, on cdbc0b66 also
-- the answer to an unknown member)
function ue.prop(o, name) return field(o, name) end
-- The tags of a gameplay tag container field (default CharacterTags: FGameplayTagContainer.GameplayTags[].TagName,
-- props:19046, :30372, :30357) as plain strings, empty and 'None' names left out; nil when a link is missing or the
-- array read raised. Bounded by #: indexing past the end grows the engine array.
function ue.tags(o, container)
    local arr = chain(o, container or 'CharacterTags', 'GameplayTags')
    if arr == nil then return nil end
    local out = {}
    local ok, err = pcall(function()
        for i = 1, #arr do
            local s = ue.str(field(arr[i], 'TagName'))
            if s and s ~= '' and s ~= 'None' then out[#out + 1] = s end
        end
    end)
    if not ok then caught(err, 'tags', container or 'CharacterTags') return nil end
    return out
end
-- Health: AttributeSetBase -> BasicAttributeSet.Health -> CurrentValue (props:19052, :15869, :40353); a number or nil
function ue.health(o)
    local v = chain(o, 'AttributeSetBase', 'Health', 'CurrentValue')
    return type(v) == 'number' and v or nil
end
-- Where an unattached actor stands: RootComponent -> SceneComponent.RelativeLocation (props:94, :468) as plain
-- { x, y, z }; nil when the root has an AttachParent (props:464: its RelativeLocation is then parent-relative) or a
-- link is missing. Property reads only, never K2_GetActorLocation (D11).
function ue.root_loc(actor)
    local root = field(actor, 'RootComponent')
    if root == nil or field(root, 'AttachParent') ~= nil then return nil end
    local l = field(root, 'RelativeLocation')
    local x, y, z = field(l, 'X'), field(l, 'Y'), field(l, 'Z')
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    return { x = x, y = y, z = z }
end
-- The built-in IsA against the class at class_path (a UE4SS C++ method, never a UFunction): true | false; nil when the
-- object is invalid, the class path is not a string, the class is not loaded or the check raised
function ue.is_a(o, class_path)
    if not ue.valid(o) or type(class_path) ~= 'string' then return nil end
    local cls = ue.class(class_path)
    if not cls then return nil end
    local ok, r = pcall(function() return o:IsA(cls) end)
    if not ok then caught(r, 'is_a', class_path) return nil end
    return r == true
end

-- ---------- loader registrations (the only place they are made: lint L004/L019) ----------
function ue.register_hook(path, pre, post)
    if not RegisterHook then return false, 'no RegisterHook' end
    if post == nil then return pcall(RegisterHook, path, pre) end
    return pcall(RegisterHook, path, pre, post)
end
function ue.unregister_hook(path, a, b)
    if not UnregisterHook then return false end
    return (pcall(UnregisterHook, path, a, b))
end
function ue.watch_class(class_path, fn)
    if not NotifyOnNewObject then return false, 'no NotifyOnNewObject' end
    return pcall(NotifyOnNewObject, class_path, fn)
end
function ue.on_load_map(fn)
    if not RegisterLoadMapPostHook then return false, 'no RegisterLoadMapPostHook' end
    return pcall(RegisterLoadMapPostHook, fn)
end
function ue.console_command(name, fn)
    if not RegisterConsoleCommandHandler then return false, 'no console handler API' end
    return pcall(RegisterConsoleCommandHandler, name, fn)
end

-- ---------- engine facts (game thread) ----------
function ue.engine_version()
    local ksl = ue.cdo('ksl')
    if not ksl then return nil end
    local ok, v = pass('call', 'GetEngineVersion', pcall(function() return ksl:GetEngineVersion() end))
    if ok then return ue.str(v) end
    return nil
end
function ue.frame()
    local ksl = ue.cdo('ksl')
    if not ksl then return nil end
    local ok, f = pass('call', 'GetFrameCount', pcall(function() return ksl:GetFrameCount() end))
    if ok and type(f) == 'number' then return f end
    return nil
end
-- ---------- world time (DESIGN C9, M0 S1.5): property reads, so main.lua's 15-frame path runs no UFunction ----------
local function is_num(v) return type(v) == 'number' and v == v end
-- The world settings actor: World.PersistentLevel -> Level.WorldSettings (props:3706, :3311); nil when a link is missing
local function world_settings()
    local w = ue.world()
    if not w then return nil end
    return chain(w, 'PersistentLevel', 'WorldSettings')
end
-- The world time factors { td, cin, demo, allow } from WorldSettings TimeDilation, CinematicTimeDilation,
-- DemoPlayTimeDilation and bAllowTimeDilation (props:8529-8531, :8502). GetEffectiveTimeDilation is not reflected in
-- PBZ; the fields are (DESIGN C9). bAllowTimeDilation false reads as factor 1: td, cin and demo read 1.0 (allow keeps
-- the flag; nil when unread). nil when there is no world, a link is missing, or td or cin is no number; demo is nil
-- when unread (a replay factor: neither dilation nor vanilla_slow multiplies it).
function ue.world_factors()
    local ws = world_settings()
    if ws == nil then return nil end
    local td, cin = field(ws, 'TimeDilation'), field(ws, 'CinematicTimeDilation')
    if not is_num(td) or not is_num(cin) then return nil end
    local demo, allow = field(ws, 'DemoPlayTimeDilation'), field(ws, 'bAllowTimeDilation')
    if not is_num(demo) then demo = nil end
    if type(allow) ~= 'boolean' then allow = nil end
    if allow == false then td, cin, demo = 1.0, 1.0, demo and 1.0 or nil end
    return { td = td, cin = cin, demo = demo, allow = allow }
end
-- Paused: WorldSettings.PauserPlayerState (props:8541) holds a valid object; false otherwise and when unreadable. A
-- property read, never GameplayStatics IsGamePaused.
function ue.paused()
    local ws = world_settings()
    return ws ~= nil and ue.valid(field(ws, 'PauserPlayerState'))
end
-- Game speed for the scheduler: td x cin from ue.world_factors(), 1.0 when unreadable (the scheduler's fallback; the
-- arbiter never reads this: its getter is time_writer().get). Never GameplayStatics GetGlobalTimeDilation.
function ue.dilation()
    local f = ue.world_factors()
    local v = f and f.td * f.cin
    if is_num(v) and v > 0 then return v end
    return 1.0
end
-- Vanilla slow time, the A.gates entry of the slowmo adapter (wired in M2 after L6t): true when td x cin < 1 - 1e-3,
-- false at normal speed, nil when unreadable. In M0 the arbiter's writer still writes TimeDilation (time_writer), so a
-- beat of ours would read as vanilla slow here: M2 moves the write to DemoPlayTimeDilation before wiring the gate.
ue.VANILLA_EPS = 1e-3
function ue.vanilla_slow()
    local f = ue.world_factors()
    if not f then return nil end
    return f.td * f.cin < 1 - ue.VANILLA_EPS
end
-- The slow-motion arbiter's writer only (libs/slowmo.lua through its adapter; lint L007): nobody else sets time.
-- get is its own getter, GameplayStatics GetGlobalTimeDilation (WorldSettings.TimeDilation; the only UFunction time
-- read, and nothing calls it in M0): the number, or nil on a failed read (no CDO, no world, a raise, no number),
-- never 1.0, so the arbiter never takes an unreadable value for normal time (DESIGN C9; slowmo.lua rules).
function ue.time_writer()
    return {
        get = function()
            local gs, w = ue.cdo('gs'), ue.world()
            if not gs or not w then return nil end
            local ok, v = ue.call(gs, 'GetGlobalTimeDilation', w)
            if ok and is_num(v) then return v end
            return nil
        end,
        set = function(v)
            local gs, w = ue.cdo('gs'), ue.world()
            if not gs or not w or type(v) ~= 'number' then return false end
            wrote()
            return (pcall(function() gs:SetGlobalTimeDilation(w, v + 0.0) end))
        end,
    }
end
-- The view for the slow-motion camera gate (M2; nothing calls it in M0): { loc = {x, y, z}, fwd = {x, y, z} } from
-- PlayerController.PlayerCameraManager (props:5649) GetCameraLocation and GetCameraRotation (so:19858-19859), fwd the
-- unit vector of the rotation's pitch and yaw (FRotator::Vector); nil when a link, a call or a field fails. Two
-- UFunction calls through ProcessEvent: the M2 caller arms each ue.camera call under 'slowmo.cam' (a beat is rare).
-- pc: the player controller, else ue.first_of('PlayerController') (cached per map, at most one lookup per 5 s).
function ue.camera(pc)
    if pc == nil then pc = ue.first_of('PlayerController') end
    local cam = field(pc, 'PlayerCameraManager')
    if cam == nil then return nil end
    local okl, l = ue.call(cam, 'GetCameraLocation')
    local okr, r = ue.call(cam, 'GetCameraRotation')
    if not okl or not okr then return nil end
    local x, y, z = field(l, 'X'), field(l, 'Y'), field(l, 'Z')
    local p, yaw = field(r, 'Pitch'), field(r, 'Yaw')
    if not (is_num(x) and is_num(y) and is_num(z) and is_num(p) and is_num(yaw)) then return nil end
    p, yaw = math.rad(p), math.rad(yaw)
    return { loc = { x = x, y = y, z = z },
        fwd = { x = math.cos(p) * math.cos(yaw), y = math.cos(p) * math.sin(yaw), z = math.sin(p) } }
end

-- ---------- components ----------
function ue.owner(c)
    if not ue.valid(c) then return nil end
    local ok, o = pass('call', 'GetOwner', pcall(function() return c:GetOwner() end))
    if ok and ue.valid(o) then return o end
    return nil
end
-- What the mod adds is never distance-culled (SWZC gibs vanished past ~28 m): never-cull flags, then
-- SetCullDistance(1) and (0) so CachedMaxDrawDistance ends 0 and the render state is dirty. Box/Sphere proxies skip.
local NO_CULL = { ['/Script/Engine.BoxComponent'] = true, ['/Script/Engine.SphereComponent'] = true,
    ['/Script/Engine.ChildActorComponent'] = true }
function ue.never_cull(c, class_path)
    if NO_CULL[class_path or ''] or not ue.valid(c) then return false end
    wrote()
    ue.set(c, 'bNeverDistanceCull', true)
    ue.set(c, 'bAllowCullDistanceVolume', false)
    pcall(function() c:SetCullDistance(1.0) end)
    pcall(function() c:SetCullDistance(0.0) end)
    return true
end
-- Debris ignores pawns and other debris, blocks the world (before SetStaticMesh): PhysicsOnly, Block all, Pawn (2)
-- and PhysicsBody (5) ignored, object type PhysicsBody
function ue.trace_neutral(c)
    if not ue.valid(c) then return false end
    wrote()
    return (pcall(function()
        c:SetCollisionEnabled(2)
        c:SetCollisionResponseToAllChannels(2)
        c:SetCollisionResponseToChannel(2, 0)
        c:SetCollisionResponseToChannel(5, 0)
        c:SetCollisionObjectType(5)
    end))
end
-- Every mesh the mod spawns refuses world and effect decals (kb:wounds-materials#p12): the mod's own pool decals drew
-- coloured squares on its own stumps. Call again after SetStaticMesh/SetSkinnedAsset and the material, and on every
-- object taken from a pool for reuse (add_component already calls it once). Box/Sphere proxies draw nothing: skipped.
function ue.refuse_decals(c, class_path)
    if NO_CULL[class_path or ''] or not ue.valid(c) then return false end
    return ue.set(c, 'bReceivesDecals', false)
end
-- AddComponentByClass on the victim actor (it dies with it and goes on a map change), identity transform, never culled,
-- refusing decals. opts.trace_neutral: the debris profile. opts.no_collision: SetCollisionEnabled(0) right after the
-- add, before anything else (a StaticMeshComponent defaults to BlockAllDynamic, a shape blocks too: a Cap would push its
-- own Piece or ragdoll, the player and the camera); a refused call answers nil, 'collision: <why>' and the component
-- as a third value (the caller drops it its own way). opts.scale (M1a D8, the stand-in scale bucket): a positive
-- finite number s puts Scale3D (s, s, s) into the RelativeTransform, which a KeepWorld attach keeps; nil keeps the
-- identity; anything else is refused before any lookup or write ('bad_scale': a 0 scale draws nothing). Returns the
-- component and its keep record, or nil and why.
function ue.add_component(actor, class_path, opts)
    local s = opts and opts.scale
    if s ~= nil and not (type(s) == 'number' and s > 0 and s < math.huge) then return nil, 'bad_scale' end
    local cls = ue.class(class_path)
    if not cls then return nil, 'no_class' end
    if not ue.valid(actor) then return nil, 'no_actor' end
    local xf = s and ue.xform(nil, nil, ue.vec(s, s, s)) or ue.xform()
    wrote()
    local ok, c = pcall(function() return actor:AddComponentByClass(cls, false, xf, false) end)
    if not ok or not ue.valid(c) then return nil, tostring(c) end
    if opts and opts.no_collision then
        wrote()
        local okc, e = pcall(function() c:SetCollisionEnabled(0) end)
        if not okc then return nil, 'collision: ' .. tostring(e), c end
    end
    ue.never_cull(c, class_path)
    ue.refuse_decals(c, class_path)
    if opts and opts.trace_neutral then ue.trace_neutral(c) end
    return c, ue.keep(c)
end
-- Destroy through the owner (K2_DestroyComponent(self) is refused: 'May not destroy component'). false, 'no_owner' when
-- the owner reads nil (a component of a dead actor: the call would pass the component itself, which the engine refuses
-- with an error line; nothing is written then; M1a 4.1 item 4); false when the component is invalid or the call raised
function ue.destroy(c)
    if not ue.valid(c) then return false end
    local owner = ue.owner(c)
    if owner == nil then return false, 'no_owner' end
    wrote()
    return (pcall(function() c:K2_DestroyComponent(owner) end))
end
function ue.set_hidden(c, hidden)
    if not ue.valid(c) then return false end
    wrote()
    return (pcall(function() c:SetHiddenInGame(hidden == true, false) end))
end
-- The actor's valid components of the class (K2_GetComponentsByClass), and whether the list was read (false: no class,
-- no actor, the call or the walk failed). A UFunction's TArray return comes back as a new Lua table whose every element
-- is pushed with Operation::GetParam (U/LuaType/LuaUObject.cpp:349 GetNonTrivialLocal -> push_arrayproperty ->
-- iterate_array_and_turn_into_lua_table :838, :1013, :867): an object element is a RemoteUnrealParam (:471-472), so
-- each one is unwrapped with ue.p (type() first, then get: no raise)
function ue.components(actor, class_path)
    local out, cls = {}, ue.class(class_path)
    if not cls or not ue.valid(actor) then return out, false end
    -- UE4SS never frees a UFunction's returned TArray (the params buffer is freed, LuaUObject.cpp:149-172, with no
    -- DestroyValue on the return): about N x 8 B leak per call, small but per call
    local ok, arr = pass('call', 'K2_GetComponentsByClass',
        pcall(function() return actor:K2_GetComponentsByClass(cls) end))
    if not ok or arr == nil then return out, false end
    local okw = pass('components', class_path, pcall(function()
        for i = 1, #arr do                         -- bounded by #: indexing past the end grows the engine array
            local c = ue.p(arr[i])
            if ue.valid(c) then out[#out + 1] = c end
        end
    end))
    return out, okw == true
end
ue.COMPONENT = '/Script/Engine.ActorComponent'
-- A component destroy read back: whether owner's K2_GetComponentsByClass (class_path, default every ActorComponent)
-- still lists c, compared by address (ue.same). true, false, or nil and the word when it could not be read:
-- 'no_addr' (no address), 'owner_dead' (the owner is not valid: nothing to ask), 'call' (the call or the walk failed),
-- or 'empty' (a live owner answered an empty list: a live actor lists at least its root component, so with the
-- default class an empty list is a failed read, never 'destroyed'; review A5.1 recheck; the words are M1a 4.1 item 4).
-- K2_DestroyComponent takes the component out of its owner's list at once (UActorComponent::DestroyComponent,
-- RemoveOwnedComponent [inferred, UE source]) and marks it garbage, while UE4SS's IsValid checks only the object map
-- and the Unreachable flag (UI/LuaType/LuaUObject.hpp:761-772): it reads true until the GC runs
function ue.listed(owner, c, class_path)
    if ue.addr(c) == nil then return nil, 'no_addr' end
    if not ue.valid(owner) then return nil, 'owner_dead' end
    local list, read = ue.components(owner, class_path or ue.COMPONENT)
    if not read then return nil, 'call' end
    if #list == 0 then return nil, 'empty' end
    for _, x in ipairs(list) do if ue.same(x, c) then return true end end
    return false
end

-- ---------- bones and leader-pose hides ----------
function ue.has_bone(mesh, bone)
    local ok, i = pass('call', 'GetBoneIndex', pcall(function() return mesh:GetBoneIndex(ue.fname(bone)) end))
    return ok and type(i) == 'number' and i >= 0
end
-- A TWeakObjectPtr property (LeaderPoseComponent): the object it points at, or nil
function ue.weak(v)
    if v == nil then return nil end
    if ue.valid(v) then return v end
    local ok, o = pcall(function() return v:Get() end)
    if ok and ue.valid(o) then return o end
    if not ok then caught(o, 'weak') end
    return nil
end
-- The skinned components that lead (no LeaderPoseComponent) and have the bone: followers ignore HideBoneByName.
-- UE4 and UE5.0 name the property MasterPoseComponent (renamed in 5.1) [inferred]
local function leader_of(c)
    local lp = ue.get(c, 'LeaderPoseComponent')
    if lp == nil then lp = ue.get(c, 'MasterPoseComponent') end
    return ue.weak(lp)
end
function ue.leaders_with_bone(actor, bone)
    local out = {}
    for _, c in ipairs(ue.components(actor, '/Script/Engine.SkinnedMeshComponent')) do
        if not ue.valid(leader_of(c)) and ue.has_bone(c, bone) then out[#out + 1] = c end
    end
    return out
end
-- hide.lua's 'bone' writer: HideBoneByName on every leader with the bone. n hidden. Always EPhysBodyOp 0 PBO_None:
-- PBO_Term (1) terminates the bodies below the bone, which a victim that can come back still needs (DESIGN C6, PLAN
-- P17). There is no term parameter: an extra argument from an old caller is ignored, never turned into PBO_Term.
ue.PBO_NONE = 0
function ue.hide_bone_all(actor, bone)
    local n = 0
    for _, c in ipairs(ue.leaders_with_bone(actor, bone)) do
        if pcall(function() c:HideBoneByName(ue.fname(bone), ue.PBO_NONE) end) then n = n + 1 end
        wrote()                                     -- after the attempt: tests/test_ue4ss_ue.lua anchors the lines above
    end
    return n
end
function ue.unhide_bone_all(actor, bone)
    local n = 0
    for _, c in ipairs(ue.leaders_with_bone(actor, bone)) do
        wrote()
        if pcall(function() c:UnHideBoneByName(ue.fname(bone)) end) then n = n + 1 end
    end
    return n
end

-- ---------- Caps: parent mode (M0 S1.7, PLAN P16) ----------
local function norm_axis(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end
-- A unit quaternion {w,x,y,z} as an FRotator in degrees, the way FQuat::Rotator turns it (gimbal branches at
-- |Z X - W Y| > 0.4999995); tests/test_ue4ss_ue.lua turns it back with the mock's FRotator::Quaternion
function ue.quat_rot(q)
    local w, x, y, z = q.w, q.x, q.y, q.z
    local sing = z * x - w * y
    local yaw = math.deg(math.atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))
    if sing < -0.4999995 then return ue.rot(-90, yaw, norm_axis(-yaw - 2 * math.deg(math.atan(x, w)))) end
    if sing > 0.4999995 then return ue.rot(90, yaw, norm_axis(yaw - 2 * math.deg(math.atan(x, w)))) end
    local roll = math.deg(math.atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y)))
    return ue.rot(math.deg(math.asin(2 * sing)), yaw, roll)
end
-- The skinned component that carries the bone: v itself when it is a mesh with the bone (a Piece's pose copy), else
-- the first leader of the actor v with the bone (a follower takes the leader's pose). v may be a ue.keep record.
local function bone_mesh(v, bone)
    if type(v) == 'table' and not is_obj(v) then v = ue.live(v) end
    if not ue.valid(v) then return nil, 'no_target' end
    if ue.has_bone(v, bone) then return v end
    local m = ue.leaders_with_bone(v, bone)[1]
    if m then return m end
    return nil, 'no_bone'
end
-- caps_attach's A.cap_parent(h, v, bone, lpos, lrot): the Cap component h (or its keep record) goes onto v's mesh at
-- the bone with K2_AttachToComponent(mesh, bone, 2, 2, 1, false): EAttachmentRule SnapToTarget (2) for location and
-- rotation, KeepWorld (1) for scale, no weld (caps.md "UE fast path"); then the manifest's local pose relative to the
-- bone through K2_SetRelativeLocationAndRotation: lpos {x,y,z} in UE units (cm) and lrot {w,x,y,z} as an FRotator
-- (nil: the bone origin, no turn), which moves the Cap onto the collapsed joint. true, or false and why on any
-- failure, before or after a write (the caller then follows; an attach whose pose write failed stays attached and the
-- follow writes take over). One writes bump per call after the checks, for both engine writes.
function ue.cap_parent(h, v, bone, lpos, lrot)
    if type(h) == 'table' and not is_obj(h) then h = ue.live(h) end
    if not ue.valid(h) then return false, 'no_cap' end
    if type(bone) ~= 'string' or bone == '' then return false, 'no_bone' end
    local p = lpos or { x = 0, y = 0, z = 0 }
    local q = lrot or { w = 1, x = 0, y = 0, z = 0 }
    if not (is_num(p.x) and is_num(p.y) and is_num(p.z) and is_num(q.w) and is_num(q.x) and is_num(q.y)
            and is_num(q.z)) then
        return false, 'bad_pose'
    end
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if n < 1e-9 then return false, 'bad_pose' end
    local mesh, why = bone_mesh(v, bone)
    if not mesh then return false, why end
    local loc, rot = ue.vec(p.x, p.y, p.z), ue.quat_rot({ w = q.w / n, x = q.x / n, y = q.y / n, z = q.z / n })
    wrote()
    local ok, r = pcall(function() return h:K2_AttachToComponent(mesh, ue.fname(bone), 2, 2, 1, false) end)
    if not ok then return false, 'attach: ' .. tostring(r) end
    if r == false then return false, 'attach_refused' end
    ok, r = pcall(function() h:K2_SetRelativeLocationAndRotation(loc, rot, false, {}, false) end)
    if not ok then return false, 'pose: ' .. tostring(r) end
    return true
end

-- ---------- FX and sound (callers go through fx_gate: lint L016) ----------
-- Niagara attached: EAttachLocation 2 SnapToTarget (1 KeepWorldPosition), pool 0, bPreCullCheck false. Spawned
-- INACTIVE, SetAllowScalability(false), then Activate(true): scalability off must come before Activate or a far camera
-- still culls it. opts.activate = false leaves it inactive (set user params, then ue.call(c, 'Activate', true)).
-- opts: loc, rot, loctype, activate
local function no_cull_activate(c, activate)
    wrote()
    pcall(function() c:SetAllowScalability(false) end)
    if activate ~= false then pcall(function() c:Activate(true) end) end
    return c
end
function ue.spawn_attached(system, comp, bone, opts)
    opts = opts or {}
    local lib = ue.cdo('niagara')
    if not lib or not ue.valid(system) or not ue.valid(comp) then return nil, 'missing' end
    wrote()
    local ok, c = pcall(function()
        return lib:SpawnSystemAttached(system, comp, ue.fname(bone or 'None'), opts.loc or ue.vec(), opts.rot or ue.rot(),
            opts.loctype or 2, true, false, 0, false)
    end)
    if not ok or not ue.valid(c) then return nil, tostring(c) end
    return no_cull_activate(c, opts.activate)
end
function ue.spawn_at(system, pos, rot, activate)
    local lib, w = ue.cdo('niagara'), ue.world()
    if not lib or not w or not ue.valid(system) then return nil, 'missing' end
    wrote()
    local ok, c = pcall(function()
        return lib:SpawnSystemAtLocation(w, system, pos, rot or ue.rot(), ue.vec(1, 1, 1), true, false, 0, false)
    end)
    if not ok or not ue.valid(c) then return nil, tostring(c) end
    return no_cull_activate(c, activate)
end
-- The setter must match the user parameter's type (a Float setter on an Int32 parameter adds an unused one)
local NSET = { Float = 'SetVariableFloat', Int = 'SetVariableInt', Bool = 'SetVariableBool', Vec3 = 'SetVariableVec3',
    LinearColor = 'SetVariableLinearColor', Vec2 = 'SetVariableVec2' }
function ue.set_niagara(comp, kind, name, v)
    local fn = NSET[kind]
    if not fn then return false, 'bad kind' end
    if kind == 'Int' then v = math.tointeger(math.floor(v + 0.5)) or 0 elseif kind == 'Float' then v = v + 0.0 end
    return ue.call(comp, fn, ue.fname(name), v)
end
-- SpawnDecalAtLocation: owned by WorldSettings (anyone may destroy it); SetFadeScreenSize(0), or the engine's 0.01
-- fades a small decal out at distance. Never a fade that destroys the owner (SetFadeOut with its last arg true).
function ue.spawn_decal(mat, size, pos, rot, opts)
    opts = opts or {}
    local gs, w = ue.cdo('gs'), ue.world()
    if not gs or not w or not ue.valid(mat) then return nil, 'missing' end
    wrote()
    local ok, d = pcall(function()
        return gs:SpawnDecalAtLocation(w, mat, size, pos, rot or ue.rot(-90, 0, 0), math.max(0, tonumber(opts.life) or 0) + 0.0)
    end)
    if not ok or not ue.valid(d) then return nil, tostring(d) end
    pcall(function() d:SetFadeScreenSize((tonumber(opts.fade_screen) or 0) + 0.0) end)
    if opts.sort then pcall(function() d:SetSortOrder(math.tointeger(math.floor(opts.sort)) or 0) end) end
    return d
end
-- Wwise PostEventAtLocation(AkEvent, Location, Orientation, World) -> PlayingID; 0 = not played (data not loaded)
function ue.post_event(event, pos)
    local lib, w = ue.cdo('akgs'), ue.world()
    if not lib or not w or not ue.valid(event) then return nil, 'missing' end
    wrote()
    local ok, id = pcall(function() return lib:PostEventAtLocation(event, pos, ue.rot(), w) end)
    if not ok then return nil, tostring(id) end
    if id == 0 then return nil, 'not_played' end
    return id
end

-- ---------- keeper: Lua references root nothing (refuted.md:89) ----------
-- ue.hold(host, obj, kind) -> id | nil, why. host: an actor that lives for the map (the player controller). kind:
--   'material'  a slot of the keeper, a hidden meshless StaticMeshComponent on the host (OverrideMaterials roots it)
--   'texture'   a keeper slot holding a MID (parent KEEP_BASE) whose KEEP_PARAM texture parameter points at it
--   'mesh'      its own hidden StaticMeshComponent on the host, collision off before SetStaticMesh
--   'class'     a UClass (a pawn class LoadAsset brought in; spec M1a 4.2 item 4: the MaleThug class was collected after
--               its last pawn went): its own ChildActorComponent on the host with ChildActorClass assigned (a strong
--               TSubclassOf, so the collector sees it) AFTER the add, never through SetChildActorClass, so no child actor
--               is made; read back. Explicit only: the kind is never taken from a class [untested live]
--   nil         the kind from the object's class (a MID is a material). The texture and mesh routes are [untested]
--               until TC-LAB-03 S-GC; the material route held materials in SWZC. Pass ue.asset's result in
--               parentheses, (ue.asset(path)): its second value (via) is not a kind and would be refused.
-- Any other class or kind is refused 'unsupported', never a silent no-op; also 'invalid' (no object), 'no_host' (no
-- keeper or holder could be added; a third value is then add_component's why: 'no_actor', 'no_class' or the raised
-- text) and 'failed' (the engine call raised). A released slot is reused by the next hold.
-- ue.release(id) -> true | false, 'unknown': clears the slot (SetMaterial(i, nil): UE4SS pushes nil as nullptr) or
-- destroys the mesh holder, and drops the asset cache entry of what it held. A map load (ue.reset_caches) or a new
-- keeper ends the holds of the old one the same way, so no cache hit outlives its holder: the next ue.asset finds or
-- loads the asset again and its owner (a module's warm-up) holds it again.
ue.KEEP_KINDS = { material = '/Script/Engine.MaterialInterface', texture = '/Script/Engine.Texture',
    mesh = '/Script/Engine.StaticMesh' }
ue.KEEP_BASE = '/Engine/EngineMaterials/DefaultMaterial.DefaultMaterial'
ue.KEEP_PARAM = 'LG_Keep'
local KEEP_ORDER = { 'material', 'texture', 'mesh' }
local HOLDER = '/Script/Engine.StaticMeshComponent'
local holds, free_slots, hold_n = {}, {}, 0
local function is_a(o, class_path) return ue.is_a(o, class_path) == true end
local function kind_of(o, kind)
    if kind == 'class' then
        local ok, is = pcall(function() return o:IsClass() end)
        return (ok and is == true) and kind or nil
    end
    if kind ~= nil then return (ue.KEEP_KINDS[kind] and is_a(o, ue.KEEP_KINDS[kind])) and kind or nil end
    for _, k in ipairs(KEEP_ORDER) do if is_a(o, ue.KEEP_KINDS[k]) then return k end end
    return nil
end
-- Every asset cache entry of what rec held, whenever and under whichever path it was cached (an entry made after the
-- hold, or a second spelling of the path, counts too): no cache hit outlives its holder
local function drop_cached(rec)
    local a = ue.addr(rec.obj.obj)
    if a == nil then return end
    for path, c in pairs(asset_cache) do
        if type(c) == 'table' and ue.addr(c.obj) == a then asset_cache[path] = nil end
    end
end
-- End holds without engine calls (their holder is gone); slots_only keeps the mesh holders
function end_holds(slots_only)
    for id, rec in pairs(holds) do
        if not (slots_only and rec.comp) then holds[id] = nil drop_cached(rec) end
    end
    free_slots = {}
end
function ue.keeper(host)
    local k = keeper and ue.live(keeper)
    if k then return k end
    local c, why = ue.add_component(host, HOLDER)
    if not c then return nil, why end
    ue.set_hidden(c, true)
    end_holds(true)                                 -- slots of an older keeper died with it
    keeper = ue.keep(c)
    keeper.slots = 0
    return c
end
local function hold_slot(host, obj, rec)
    local c, wc = ue.keeper(host)
    if not c then return nil, 'no_host', wc end
    local n = #free_slots
    local i = free_slots[n] or keeper.slots
    local ok
    wrote()
    if rec.kind == 'material' then
        ok = pcall(function() c:SetMaterial(i, obj) end)
    else
        local base = ue.asset(ue.KEEP_BASE)
        ok = base ~= nil and pcall(function()
            -- NAME_None: the engine names it uniquely. A fixed per-slot name would meet the MID a release left in that
            -- slot (same outer, not collected yet), and NewObject would destroy and rebuild that object in place
            local mid = c:CreateDynamicMaterialInstance(i, base, ue.fname('None'))
            if not ue.valid(mid) then error('no MID') end
            mid:SetTextureParameterValue(ue.fname(ue.KEEP_PARAM), obj)
        end)
        if not ok then pcall(function() c:SetMaterial(i, nil) end) end
    end
    if not ok then return nil, 'failed' end
    if n > 0 then free_slots[n] = nil else keeper.slots = i + 1 end
    rec.slot = i
    return true
end
local function hold_mesh(host, obj, rec)
    local c, wc = ue.add_component(host, HOLDER)
    if not c then return nil, 'no_host', wc end
    ue.set_hidden(c, true)
    wrote()
    if not pcall(function() c:SetCollisionEnabled(0) c:SetStaticMesh(obj) end) then
        ue.destroy(c)
        return nil, 'failed'
    end
    rec.comp = ue.keep(c)
    return true
end
-- A class: a ChildActorComponent whose ChildActorClass property is the class (see the header). The property is
-- assigned after the component registered, so no child actor is created; a component that does not hold it on the
-- read-back goes again
local CHILD = '/Script/Engine.ChildActorComponent'
local function hold_class(host, obj, rec)
    local c, wc = ue.add_component(host, CHILD)
    if not c then return nil, 'no_host', wc end
    wrote()
    local ok = pcall(function() c.ChildActorClass = obj end)
    if not ok or not ue.same(ue.prop(c, 'ChildActorClass'), obj) then
        ue.destroy(c)
        return nil, 'failed'
    end
    -- No child actor may come of it (fix round 2 runtime review): one made anyway (a spawned enemy on the player)
    -- fails the hold and the component goes, its child with it
    if ue.valid(ue.prop(c, 'ChildActor')) then
        ue.destroy(c)
        return nil, 'child_made'
    end
    rec.comp = ue.keep(c)
    return true
end
local HOLDERS = { mesh = hold_mesh, class = hold_class }
function ue.hold(host, obj, kind)
    if not ue.valid(obj) then return nil, 'invalid' end
    local k = kind_of(obj, kind)
    if not k then return nil, 'unsupported' end
    local rec = { kind = k, obj = ue.keep(obj) }
    local ok, why, add = (HOLDERS[k] or hold_slot)(host, obj, rec)
    if not ok then return nil, why, add end
    hold_n = hold_n + 1
    holds[hold_n] = rec
    return hold_n
end
function ue.release(id)
    local rec = holds[id]
    if not rec then return false, 'unknown' end
    holds[id] = nil
    drop_cached(rec)
    if rec.comp then
        local c = ue.live(rec.comp)
        if c then ue.destroy(c) end
        return true
    end
    local c = keeper and ue.live(keeper)
    if c then wrote() pcall(function() c:SetMaterial(rec.slot, nil) end) end
    free_slots[#free_slots + 1] = rec.slot
    return true
end

-- ---------- call_uncallable (only through ARM.call: the sentinel and the call window) ----------
-- spec: fn (UFunction path), cdo (library CDO path), cmd ('<FuncName> <every param as text>'), executor (a UObject
-- that fills the first object param), need (flags that must be set, default 0x2400 Native|Static), expect (the flags
-- the research read, optional), armed (set only by ARM.call). Returns the ProcessConsoleExec result, or nil and why:
-- unarmed, missing, flags (unreadable, need missing, not the expected value, or FUNC_Exec already set), flags_write,
-- not_exec (found but not exec: the flag did not take), flags_restore (the read-back differs: the function stays
-- console-callable; switch the route off for the session, later calls refuse with 'flags' anyway).
ue.FUNC_NEED = 0x2400
function ue.call_uncallable(spec)
    if type(spec) ~= 'table' or spec.armed ~= true then stats.refused = stats.refused + 1 return nil, 'unarmed' end
    local fn, lib = ue.find(spec.fn), ue.cdo(spec.cdo)
    if not fn or not lib or not ue.valid(spec.executor) or type(spec.cmd) ~= 'string' then return nil, 'missing' end
    local okf, orig = pcall(function() return fn:GetFunctionFlags() end)
    orig = okf and math.tointeger(orig) or nil
    local need = math.tointeger(spec.need) or ue.FUNC_NEED
    if not orig or orig & need ~= need or orig & ue.FUNC_EXEC ~= 0 then return nil, 'flags' end
    if spec.expect ~= nil and math.tointeger(spec.expect) ~= orig then return nil, 'flags' end
    stats.uncallable = stats.uncallable + 1
    wrote()                                          -- a flags write on the UFunction, and whatever the call writes
    local okw = pcall(function() fn:SetFunctionFlags(orig | ue.FUNC_EXEC) end)
    local ok, ret = false, nil
    if okw then ok, ret = pcall(function() return lib:ProcessConsoleExec(spec.cmd, nil, spec.executor) end) end
    local restored = false
    for _ = 1, 2 do                                  -- restore in this frame and read back; once more if it did not take
        pcall(function() fn:SetFunctionFlags(orig) end)
        local okr, now = pcall(function() return fn:GetFunctionFlags() end)
        if okr and math.tointeger(now) == orig then restored = true break end
    end
    if not restored then return nil, 'flags_restore' end
    if not okw then return nil, 'flags_write' end
    if not ok then return nil, tostring(ret) end
    if ret == false then return nil, 'not_exec' end
    return ret
end

function ue.status()
    local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
    return { epoch = ue.epoch, finds = stats.finds, misses = stats.misses, uncallable = stats.uncallable,
        refused = stats.refused, world = ue.world() ~= nil, writes = stats.writes, find_all = stats.find_all,
        find_all_ms = stats.find_all_ms, first_of = stats.first_of, first_of_ms = stats.first_of_ms,
        first_asks = stats.first_asks, meta = stats.meta, find_ms = r1(stats.find_ms), miss_ms = r1(stats.miss_ms),
        miss_ms_max = r1(stats.miss_ms_max), miss_path = stats.miss_path }
end
function ue.init() return true end
function ue.reset() ue.reset_caches() end
function ue.shutdown() end_holds() world, keeper = nil, nil end

return ue
