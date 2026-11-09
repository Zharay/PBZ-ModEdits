-- status: new in M1a A1.4 (offline only: the lab's executed calls decide) origin: kb:testing-lab-playtest#first-in-game-session-on-a-new-game-a-passive-probe-and-numbered-lab-gates-tc-lab-01
-- ue_spawn.lua: the lab's spawn, actor and time helpers over adapter/ue.lua (spec M1a D3, D12, rule 7, sections 3.4 and
-- 4.0): the pawn class, CheatManager Summon, the deferred spawn pair, the teleport, the default controller, an interface
-- call, the actor-hidden flag, the actor destroy and the game time. lab_spawn (A3.9) calls them, each under its own
-- section 3.4 name (lab.spawn.summon, .deferred, .move, .ai, .respawn); ue.load_asset stays in adapter/ue.lua.
-- * No raw lookup here (StaticFindObject, FindAllOf, LoadAsset, StaticConstructObject, hooks, NotifyOnNewObject stay in
--   adapter/ue.lua, L004) and no GeometryScript or ProcessConsoleExec token (L015): paths go through ue.find, ue.asset
--   and ue.cdo.
-- * No helper arms a sentinel: the callers do (LAB.armed under the class's name). A raised call answers nil and its
--   text, which went to ue.caught first (lab_probe's stop rule reads an ArrayNum text there); no helper raises.
-- * Every write helper (summon, spawn_deferred, teleport, spawn_controller, call_iface, set_actor_hidden, destroy_actor)
--   bumps ue.count_write once per engine call it attempts, after its own checks, so the probe's zero-writes gate sees
--   it (M0 S2.4); the reads (pawn_class, actor_hidden, time_seconds) never do. tests/test_ue_spawn.lua scans this file
--   and fails on a function that calls a write without the bump.
-- * A member is fetched by name and called only when it is a Lua function or a valid object (a found UFunction): an
--   unknown member is an invalid-object userdata on cdbc0b66 and dff435dd (ue.lua header), answered 'no_member'.
-- * Marshalling (ue.lua header): Summon takes one FString (CX Engine.hpp:14471): a Lua string, never a table. The spawn
--   FTransform is a const by-ref struct, an in param: a full table (Translation, Rotation with W, Scale3D), never
--   written back; a missing field would read 0 (Scale3D 0 draws nothing), so a partial one is refused. Enums and the
--   collision method are integers, bools true or false.
-- What the mock cannot prove: native faults, UE4SS's real marshalling on dff435dd, whether Summon by the full path finds
-- the class, AI and possession timing, whether a pawn spawned either way is visible (spec 4.0: a bare Summon left
-- GuiChai Black invisible).
local ue = require('adapter.ue')
local HDATA = require('data.hooks')

local CALLS = type(HDATA.calls) == 'table' and HDATA.calls or {}
local M = {
    BEGIN = CALLS.statics_begin_deferred_actor_spawn_from_class
        or '/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass',
    FINISH = CALLS.statics_finish_spawning_actor or '/Script/Engine.GameplayStatics:FinishSpawningActor',
    -- ESpawnActorCollisionHandlingMethod AdjustIfPossibleButAlwaysSpawn (2) and ESpawnActorScaleMethod MultiplyWithRoot
    -- (1): CX Engine_enums.hpp:4429-4443
    COLLISION = 2, SCALE_METHOD = 1,
}

-- ---------- calls by member name ----------
-- The callable member fn of a valid object: a Lua function (the mock, a loader C function such as CallFunction) or a
-- valid object (a found UFunction); nil and 'no_object' or 'no_member' (nil, or the invalid-object userdata)
local function member(o, fn)
    if not ue.valid(o) then return nil, 'no_object' end
    local ok, f = pcall(function() return o[fn] end)
    if not ok then ue.caught(f, 'spawn', fn) return nil, 'no_member' end
    if type(f) == 'function' or ue.valid(f) then return f end
    return nil, 'no_member'
end
-- pcall's answer passed through; a raised text goes to ue.caught first and comes back as false, text
local function answer(fn, ok, ...)
    if ok then return true, ... end
    ue.caught((...), 'spawn', fn)
    return false, ue.last_err
end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end

-- ---------- the pawn class (a read) ----------
-- The class at path ('<asset>.<leaf>_C'): ue.asset (found in memory, else LoadAsset; its first resolve logs
-- asset_resolved), else one ue.find, because ue.asset answers a cached miss until a map load while the class may have
-- loaded since (through the Blueprint's object path, as lab_spawn loads it); then IsClass (the UE4SS built-in, IsA
-- UClass: LuaUObject.hpp:630-638). cls, via ('found' | 'loaded') | nil, why ('bad_path', 'no_class', 'not_class')
function M.pawn_class(path)
    if type(path) ~= 'string' or path == '' then return nil, 'bad_path' end
    local cls, via = ue.asset(path)
    if not cls then
        cls, via = ue.find(path), 'found'
        if not cls then return nil, 'no_class' end
    end
    local ok, is = pcall(function() return cls:IsClass() end)
    if not ok then ue.caught(is, 'spawn', 'IsClass') return nil, 'not_class' end
    if is ~= true then return nil, 'not_class' end
    return cls, via
end

-- ---------- spawns ----------
-- CheatManager:Summon(class_path) (CX Engine.hpp:14471, void): UE's body finds a path with a dot by FindObject and
-- never loads (spec D12 [inferred, engine source]), so load the class first (pawn_class). The pawn is not returned:
-- lab_spawn matches it through bus lab_admit. true (the call ran, not that a pawn appeared) | nil, why ('bad_path': not
-- a non-empty string, a Lua table included; 'no_object', 'no_member', or the raised text)
function M.summon(cm, class_path)
    if type(class_path) ~= 'string' or class_path == '' then return nil, 'bad_path' end
    local f, why = member(cm, 'Summon')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('Summon', pcall(f, cm, class_path))
    if not ok then return nil, err end
    return true
end

-- The live params of a UFunction (ue.func_params), kept per path for the session (hits only); M.forget() drops them
local plist = {}
local function params(path)
    local l = plist[path]
    if l then return l end
    l = ue.func_params(path)
    if type(l) == 'table' then plist[path] = l end
    return l
end
function M.forget() plist = {} end
local PENDING = {}                               -- Finish's Actor slot until Begin answers
local NIL_OK = { owner = true }                  -- an object param that may stay nil (UE4SS pushes nullptr)
-- The Lua arguments for a live param list: one per param in order, ReturnValue apart, from vals by the lower-case
-- param name (FNames compare without case). out, n, at (name -> position) | nil, the name vals lacks
local function args_for(list, vals)
    local out, n, at = {}, 0, {}
    for _, p in ipairs(list) do
        local k = type(p.name) == 'string' and p.name:lower() or '?'
        if not p.ret and k ~= 'returnvalue' then
            if vals[k] == nil and not NIL_OK[k] then return nil, tostring(p.name) end
            n = n + 1
            out[n], at[k] = vals[k], n
        end
    end
    return out, n, at
end
-- A full FTransform: Translation, a non-zero Rotation quaternion and a Scale3D without a zero, all finite numbers
local function full_xform(t)
    if type(t) ~= 'table' then return false end
    local l, q, s = t.Translation, t.Rotation, t.Scale3D
    if type(l) ~= 'table' or type(q) ~= 'table' or type(s) ~= 'table' then return false end
    if not (num(l.X) and num(l.Y) and num(l.Z) and num(q.X) and num(q.Y) and num(q.Z) and num(q.W)) then return false end
    if not (num(s.X) and num(s.Y) and num(s.Z)) or s.X == 0 or s.Y == 0 or s.Z == 0 then return false end
    return q.X * q.X + q.Y * q.Y + q.Z * q.Z + q.W * q.W > 1e-12
end
-- BeginDeferredActorSpawnFromClass, then FinishSpawningActor, on the GameplayStatics CDO in this one function: once
-- Begin returned an actor, Finish always runs (an unfinished deferred actor never runs its construction script or
-- BeginPlay), so every check comes before Begin. The arguments follow the live params (ue.func_params, cached): by name
-- and in order, so the 5.7 form (CX Engine.hpp:16309, :16286) gets TransformScaleMethod and a form without it does
-- not; a param this helper does not know refuses ('sig_param', its name). opts: owner (an actor, default none),
-- collision (default M.COLLISION), scale_method (default M.SCALE_METHOD), world (default ue.world()). UE4SS passes the
-- raw pointer of the userdata it gets: the class param as a UClass with no type check (LuaMadeSimple.hpp:752-774,
-- LuaUObject.cpp:491-494) and the Owner as is (:456-459), so a non-class object or a set owner that is no valid object
-- is refused here. actor | nil, why: 'no_class', 'not_class', 'no_owner', 'bad_xform', 'no_statics', 'no_world',
-- 'no_params' (a function not in memory, or the pass failed), 'sig_param', 'no_object', 'no_member', 'begin: <text>',
-- 'begin_none' (Begin answered no actor), 'finish: <text>' or 'finish_gone' (the actor did not survive Finish); after
-- a raised Finish the third value is the unfinished actor (the caller destroys it). One write counted per call that
-- runs: two for a spawn.
function M.spawn_deferred(cls, xform, opts)
    opts = type(opts) == 'table' and opts or {}
    if not ue.valid(cls) then return nil, 'no_class' end
    local okc, isc = pcall(function() return cls:IsClass() end)
    if not okc then ue.caught(isc, 'spawn', 'IsClass') end
    if isc ~= true then return nil, 'not_class' end
    if opts.owner ~= nil and not ue.valid(opts.owner) then return nil, 'no_owner' end
    if not full_xform(xform) then return nil, 'bad_xform' end
    local gs, w = ue.cdo('gs'), opts.world or ue.world()
    if not gs then return nil, 'no_statics' end
    if not ue.valid(w) then return nil, 'no_world' end
    local bl, fl = params(M.BEGIN), params(M.FINISH)
    if not bl or not fl then return nil, 'no_params' end
    local sm = math.tointeger(opts.scale_method) or M.SCALE_METHOD
    local bargs, bn = args_for(bl, { worldcontextobject = w, actorclass = cls, spawntransform = xform,
        collisionhandlingoverride = math.tointeger(opts.collision) or M.COLLISION, owner = opts.owner,
        transformscalemethod = sm })
    if not bargs then return nil, 'sig_param', bn end
    local fargs, fn_, at = args_for(fl, { actor = PENDING, spawntransform = xform, transformscalemethod = sm })
    if not fargs then return nil, 'sig_param', fn_ end
    if not at.actor then return nil, 'sig_param', 'Actor' end
    local fb, why = member(gs, 'BeginDeferredActorSpawnFromClass')
    if not fb then return nil, why end
    local ff, whyf = member(gs, 'FinishSpawningActor')
    if not ff then return nil, whyf end
    ue.count_write()
    local ok, a = answer('BeginDeferredActorSpawnFromClass', pcall(fb, gs, table.unpack(bargs, 1, bn)))
    if not ok then return nil, 'begin: ' .. tostring(a) end
    if not ue.valid(a) then return nil, 'begin_none' end
    fargs[at.actor] = a                              -- from here on Finish always runs
    ue.count_write()
    local okf, err = answer('FinishSpawningActor', pcall(ff, gs, table.unpack(fargs, 1, fn_)))
    if not okf then return nil, 'finish: ' .. tostring(err), a end
    if not ue.valid(a) then return nil, 'finish_gone' end
    return a
end

-- ---------- placement, controller, interface calls ----------
-- A plain {x, y, z} or {X, Y, Z} table of finite numbers as a full FVector; nil otherwise
local function vec_of(v)
    if type(v) ~= 'table' then return nil end
    local x, y, z = v.X, v.Y, v.Z
    if x == nil and y == nil and z == nil then x, y, z = v.x, v.y, v.z end
    if not (num(x) and num(y) and num(z)) then return nil end
    return ue.vec(x, y, z)
end
-- A number (the yaw; pitch and roll 0) or a {Pitch, Yaw, Roll} table (each field also lower-case, as vec_of reads
-- them; a missing field 0, but at least one present) as a full FRotator; nil otherwise, so a missing rotation (nil,
-- {}, a table of other fields) never turns the actor to 0 unasked
local function rot_of(r)
    if num(r) then return ue.rot(0, r, 0) end
    if type(r) ~= 'table' then return nil end
    local p, y, l = r.Pitch, r.Yaw, r.Roll
    if p == nil then p = r.pitch end
    if y == nil then y = r.yaw end
    if l == nil then l = r.roll end
    if p == nil and y == nil and l == nil then return nil end
    p, y, l = p or 0, y or 0, l or 0
    if not (num(p) and num(y) and num(l)) then return nil end
    return ue.rot(p, y, l)
end
-- Actor:K2_TeleportTo(DestLocation, DestRotation) (CX Engine.hpp:10121, a bool back): loc in cm, rot as rot_of reads
-- it. true | nil, why ('bad_loc', 'bad_rot', 'no_object', 'no_member', 'refused': the engine answered false, as for an
-- actor without a root, or the raised text)
function M.teleport(actor, loc, rot)
    local v, r = vec_of(loc), rot_of(rot)
    if not v then return nil, 'bad_loc' end
    if not r then return nil, 'bad_rot' end
    local f, why = member(actor, 'K2_TeleportTo')
    if not f then return nil, why end
    ue.count_write()
    local ok, res = answer('K2_TeleportTo', pcall(f, actor, v, r))
    if not ok then return nil, res end
    if res == false then return nil, 'refused' end
    return true
end
-- Pawn:SpawnDefaultController() (CX Engine.hpp:11077, void) when the pawn's Controller (props:5590) holds no valid
-- object, then the Controller read again. controller, 'had' (no call: UE's body returns at once when one exists
-- [inferred, engine source]) or 'spawned' | nil, why ('no_object', 'no_member', 'none': still none after the call, or
-- the raised text)
function M.spawn_controller(pawn)
    if not ue.valid(pawn) then return nil, 'no_object' end
    local c = ue.prop(pawn, 'Controller')
    if ue.valid(c) then return c, 'had' end
    local f, why = member(pawn, 'SpawnDefaultController')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SpawnDefaultController', pcall(f, pawn))
    if not ok then return nil, err end
    c = ue.prop(pawn, 'Controller')
    if not ue.valid(c) then return nil, 'none' end
    return c, 'spawned'
end
-- obj:CallFunction(ue.find(fn_path), ...): ProcessEvent of that UFunction on obj (UE4SS LuaUObject.hpp:647-649), the
-- only route to an interface function such as SGameAISpawnerInterface:Respawn on a BP_AISpawner_C (spec D12 route
-- 'respawn'); counted as a write. The loader checks only that a function and an object were given
-- (call_ufunction_from_lua, LuaUObject.cpp:92-135), never that obj implements it: on such an obj the body runs on the
-- wrong object, a native fault class beyond pcall [inferred], so the caller passes the object the function belongs to,
-- under its sentinel (only the mock raises there). true and the call's results | nil, why ('no_object', 'no_function':
-- the path is not in memory, 'no_member', or the raised text)
function M.call_iface(obj, fn_path, ...)
    if not ue.valid(obj) then return nil, 'no_object' end
    local fn = type(fn_path) == 'string' and ue.find(fn_path) or nil
    if not fn then return nil, 'no_function' end
    local f, why = member(obj, 'CallFunction')
    if not f then return nil, why end
    ue.count_write()
    local r = table.pack(answer('CallFunction', pcall(f, obj, fn, ...)))
    if not r[1] then return nil, r[2] end
    return true, table.unpack(r, 2, r.n)
end

-- ---------- actor visibility, destroy, game time ----------
-- Actor:SetActorHiddenInGame(h) (CX Engine.hpp:10090): h true hides, anything else shows (bools true or false only:
-- UE4SS reads 0 as true). true | nil, why ('no_object', 'no_member', or the raised text)
function M.set_actor_hidden(a, h)
    local f, why = member(a, 'SetActorHiddenInGame')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetActorHiddenInGame', pcall(f, a, h == true))
    if not ok then return nil, err end
    return true
end
-- Actor.bHidden as a boolean (a property read, no UFunction); nil when unread (no object, no such field)
function M.actor_hidden(a)
    local v = ue.prop(a, 'bHidden')
    if type(v) == 'boolean' then return v end
    return nil
end
-- Actor:K2_DestroyActor() (CX Engine.hpp:10137): the actor goes pending destruction; nothing read back. true | nil, why
-- ('no_object', 'no_member', or the raised text)
function M.destroy_actor(a)
    local f, why = member(a, 'K2_DestroyActor')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('K2_DestroyActor', pcall(f, a))
    if not ok then return nil, err end
    return true
end
-- GameplayStatics:GetTimeSeconds(world) on the CDO (CX Engine.hpp:16245; a double): game seconds, which stop in pause
-- and follow time dilation; nil when the CDO, the world or the member is missing, the call raised or the answer is no
-- finite number. A read: no write counted
function M.time_seconds()
    local gs, w = ue.cdo('gs'), ue.world()
    if not gs or not w then return nil end
    local f = member(gs, 'GetTimeSeconds')
    if not f then return nil end
    local ok, v = answer('GetTimeSeconds', pcall(f, gs, w))
    if ok and num(v) then return v end
    return nil
end

return M
