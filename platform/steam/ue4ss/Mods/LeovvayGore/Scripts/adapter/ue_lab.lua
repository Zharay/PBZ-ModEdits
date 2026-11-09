-- status: new in M1a A1.5 (offline only: the lab's executed calls decide) origin: kb:runtime-safety-perf#ue4ss-identity-safe-caches-delayed-steps-and-destroy
-- ue_lab.lua: the lab's method helpers over adapter/ue.lua (spec M1a D3, rule 7, section 3.9): bones, components, tags,
-- checked writes, poseables and the Piece carrier (A1.5), Cap meshes, materials and the skin booking (A1.6). Lab code
-- calls these directly; no feature module is wired in M1a.
-- * No raw lookup here (StaticFindObject, FindAllOf, LoadAsset, StaticConstructObject, hooks, NotifyOnNewObject stay in
--   adapter/ue.lua, L004) and no token of the risky natives L015 names: classes go through ue.is_a, FNames through
--   ue.fname (cached, FNAME_Add), never a Lua string into an FName param (L010).
-- * No helper arms a sentinel: the callers do (LAB.armed or LAB.hot under the section 3.4 name of the class). A raised
--   call answers nil and its text, which went to ue.caught first (lab_probe's stop rule reads an ArrayNum text there);
--   no helper raises.
-- * Every write helper (add_tag, restore_tags, optim, set_checked, set_asset, copy_pose, bone_scale, bone_xform_set,
--   box_extent, physics_on, velocity_change, pmc_section, set_static_mesh, mid, set_material) bumps ue.count_write once
--   per engine write it attempts, after its own
--   checks, so the probe's zero-writes gate sees it (M0 S2.4); the reads never do. tests/test_ue_lab.lua scans this
--   file and fails on a function that writes without the bump. Property writes go through assign() and array appends
--   through append() only, so the scan sees them.
-- * A member is fetched by name and called only when it is a Lua function or a valid object (a found UFunction): an
--   unknown member is an invalid-object userdata on cdbc0b66 and dff435dd (ue.lua header), answered 'no_member'.
-- * Marshalling (ue.lua header): structs are full tables (ue.vec; an FTransform with Translation, a unit Rotation
--   quaternion and Scale3D, never a zero scale); enums and spaces are integers; bools true or false.
-- * Plain values out: a pose is { loc = {x, y, z}, quat = {w, x, y, z}, scale = {x, y, z} } (the lower-case form
--   ue.cap_parent takes); bone and tag names are strings. Nothing returned holds an engine struct or array.
-- * Cap meshes (A1.6): TArray arguments only through adapter/tarray.lua's rules (TA.check, TA.charge, TA.pmc before the
--   call, TA.poison after a raised one); the skin booking of S-SKIN (D16) is TA.book in adapter/tarray.lua.
-- * The player beta's Caps (docs/research/beta-dismemberment-plan.md BD4; research C3, CM3): pmc_section takes a
--   section index and mid a material slot, a nil colour and a texture map, so one ProceduralMeshComponent draws three
--   sections (meat, pale, dark) each with its own material; set_material puts a ready material into a slot and reads
--   it back. The defaults (section 0, slot 0, a colour, no texture) are the lab's calls as they were.
-- What the mock cannot prove: native faults, UE4SS's real marshalling on dff435dd (TArray arguments at all, TArray
-- element writes, the FName userdata an array element answers, the TWeakObjectPtr read), real poses, physics,
-- materials and rendering.
local ue = require('adapter.ue')
local TA = require('adapter.tarray')

local M = {
    SPACE_PARENT = 3,       -- ERelativeTransformSpace RTS_ParentBoneSpace (spec D9; 0 World, 1 Actor, 2 Component)
    SPACE_COMPONENT_SOCKET = 2,  -- ERelativeTransformSpace RTS_Component (GetSocketTransform; not the EBoneSpaces below)
    SPACE_COMPONENT = 1,    -- EBoneSpaces ComponentSpace (0 WorldSpace): every poseable read and write here
    MOVABLE = 2,            -- EComponentMobility Movable (pieces-physics.md launch step 2)
    VEL_CAP = 600,          -- uu/s, the velocity-change cap for limbs (pieces-physics.md launch step 4)
    CHAIN_MAX = 8,          -- bone_dir: at most this many GetParentBone links from the child up to the cut bone
    POSEABLE = '/Script/Engine.PoseableMeshComponent',
    SKELETAL = '/Script/Engine.SkeletalMeshComponent',
}

-- ---------- calls by member name, plain values ----------
-- The callable member fn of a valid object: a Lua function (the mock, a loader C function) or a valid object (a found
-- UFunction); nil and 'no_object' or 'no_member' (nil, or the invalid-object userdata)
local function member(o, fn)
    if not ue.valid(o) then return nil, 'no_object' end
    local ok, f = pcall(function() return o[fn] end)
    if not ok then ue.caught(f, 'lab', fn) return nil, 'no_member' end
    if type(f) == 'function' or ue.valid(f) then return f end
    return nil, 'no_member'
end
-- pcall's answer passed through; a raised text goes to ue.caught first and comes back as false, text
local function answer(fn, ok, ...)
    if ok then return true, ... end
    ue.caught((...), 'lab', fn)
    return false, ue.last_err
end
-- The two raw engine writes that are no UFunction call: a property assignment and an append at [#arr + 1] (a TArray
-- userdata grows by one there). Their callers bump ue.count_write
local function assign(o, k, v) return answer(k, pcall(function() o[k] = v end)) end
local function append(arr, v) return answer('append', pcall(function() arr[#arr + 1] = v end)) end
local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function name_ok(s) return type(s) == 'string' and s ~= '' and s ~= 'None' end
-- {x, y, z} from an engine or plain vector (X/Y/Z, or x/y/z for plain input); nil unless all three are finite numbers
local function vec3(v)
    local x, y, z = ue.prop(v, 'X'), ue.prop(v, 'Y'), ue.prop(v, 'Z')
    if x == nil and y == nil and z == nil and type(v) == 'table' then x, y, z = v.x, v.y, v.z end
    if num(x) and num(y) and num(z) then return { x = x, y = y, z = z } end
    return nil
end
-- A unit {w, x, y, z}; nil for a non-number or a zero quaternion
local function unit(q)
    if type(q) ~= 'table' or not (num(q.w) and num(q.x) and num(q.y) and num(q.z)) then return nil end
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if n < 1e-9 then return nil end
    return { w = q.w / n, x = q.x / n, y = q.y / n, z = q.z / n }
end
-- An engine FTransform (a returned struct) as the plain pose; nil when a field is missing or no number
local function plain_xf(t)
    local loc, s, r = vec3(ue.prop(t, 'Translation')), vec3(ue.prop(t, 'Scale3D')), ue.prop(t, 'Rotation')
    local q = unit({ w = ue.prop(r, 'W'), x = ue.prop(r, 'X'), y = ue.prop(r, 'Y'), z = ue.prop(r, 'Z') })
    if not (loc and s and q) then return nil end
    return { loc = loc, quat = q, scale = s }
end
-- The plain pose as a full FTransform table; scale a positive number or {x, y, z} of positive numbers (default 1);
-- nil when anything is missing, not finite, a zero quaternion or a scale at or under 0 (DESIGN C1: 0.001, never 0)
local function ft_of(x)
    if type(x) ~= 'table' then return nil end
    local l, q, s = vec3(x.loc), unit(x.quat), x.scale
    if s == nil then s = 1 end
    if num(s) then s = { x = s, y = s, z = s } end
    s = vec3(s)
    if not (l and q and s) or s.x <= 0 or s.y <= 0 or s.z <= 0 then return nil end
    return { Translation = ue.vec(l.x, l.y, l.z), Rotation = { X = q.x + 0.0, Y = q.y + 0.0, Z = q.z + 0.0, W = q.w + 0.0 },
        Scale3D = ue.vec(s.x, s.y, s.z) }
end
-- v turned by the unit quaternion q (q v q*)
local function rotate(q, v)
    local tx, ty, tz = 2 * (q.y * v.z - q.z * v.y), 2 * (q.z * v.x - q.x * v.z), 2 * (q.x * v.y - q.y * v.x)
    return { x = v.x + q.w * tx + (q.y * tz - q.z * ty), y = v.y + q.w * ty + (q.z * tx - q.x * tz),
        z = v.z + q.w * tz + (q.x * ty - q.y * tx) }
end
M.rotate = rotate

-- ---------- bones (reads; the lab.inherit.hide class) ----------
-- SkinnedMeshComponent:IsBoneHiddenByName(bone) (so:20829): true | false | nil, why ('bad_bone', 'no_object',
-- 'no_member', 'unread': no boolean back, or the raised text). A bone the mesh lacks reads false (UE's answer); a
-- follower answers through its leader. Callers that must know the bone exists ask ue.has_bone first
function M.is_bone_hidden(mesh, bone)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local f, why = member(mesh, 'IsBoneHiddenByName')
    if not f then return nil, why end
    local ok, v = answer('IsBoneHiddenByName', pcall(f, mesh, ue.fname(bone)))
    if not ok then return nil, v end
    if type(v) ~= 'boolean' then return nil, 'unread' end
    return v
end
-- SkinnedMeshComponent:GetParentBone(bone) (so:20820) as a string | nil, why ('bad_bone', 'no_object', 'no_member',
-- 'no_parent': the root, a bone the mesh lacks or an empty answer, or the raised text)
function M.bone_parent(mesh, bone)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local f, why = member(mesh, 'GetParentBone')
    if not f then return nil, why end
    local ok, v = answer('GetParentBone', pcall(f, mesh, ue.fname(bone)))
    if not ok then return nil, v end
    local s = ue.str(v)
    if not name_ok(s) then return nil, 'no_parent' end
    return s
end
-- The bone relative to its parent bone: GetSocketTransform(bone, RTS_ParentBoneSpace 3) (spec D9, section 3.4), after
-- ue.has_bone (GetBoneIndex), because a name that is no bone answers the component's own transform. The plain pose |
-- nil, why ('bad_bone', 'no_object', 'no_member', 'no_bone', 'unread', or the raised text)
function M.bone_parent_xform(mesh, bone)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local f, why = member(mesh, 'GetSocketTransform')
    if not f then return nil, why end
    if not ue.has_bone(mesh, bone) then return nil, 'no_bone' end
    local ok, t = answer('GetSocketTransform', pcall(f, mesh, ue.fname(bone), M.SPACE_PARENT))
    if not ok then return nil, t end
    local x = plain_xf(t)
    if not x then return nil, 'unread' end
    return x
end
-- The bones from bone's direct child down to desc (desc last), walked up through GetParentBone | nil, why ('not_child':
-- the root or M.CHAIN_MAX links reached without meeting bone, or a why of bone_parent)
local function chain_to(mesh, bone, desc)
    local up, cur, lb = { desc }, desc, bone:lower()
    for _ = 1, M.CHAIN_MAX do
        local par, why = M.bone_parent(mesh, cur)
        if not par then return nil, why == 'no_parent' and 'not_child' or why end
        if par:lower() == lb then
            local down = {}
            for i = #up, 1, -1 do down[#down + 1] = up[i] end
            return down
        end
        up[#up + 1], cur = par, par
    end
    return nil, 'not_child'
end
local function qmul(a, b)
    return { w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w }
end
-- The bone direction d of spec section 3.8: the cut bone's parent-space rotation applied to the normalized translation
-- of its child in the cut bone's space, so d points from the cut joint to the child in the stump bone's frame (the
-- Stump Cap's +Z outward, the Piece-end Cap's -d). child is a descendant of bone within M.CHAIN_MAX links: a direct
-- child reads its own parent-space pose; a deeper one (lab_pairs' head child 'head' under neck_01, with neck_02
-- between on the live MaleThug_Body, session 20261030-1522 rc) composes the parent-space poses down the chain. d
-- {x, y, z} (unit), the cut bone's pose (parent space) and the child's pose in the cut bone's space | nil, why
-- ('bad_bone', 'bad_child', 'not_child', 'zero_len', or a why of bone_parent or bone_parent_xform)
function M.bone_dir(mesh, bone, child)
    if not name_ok(bone) then return nil, 'bad_bone' end
    if not name_ok(child) then return nil, 'bad_child' end
    local down, why = chain_to(mesh, bone, child)
    if not down then return nil, why end
    local a, wa = M.bone_parent_xform(mesh, bone)
    if not a then return nil, wa end
    local b
    for i = #down, 1, -1 do                         -- bottom up: b becomes the child in down[i]'s parent space
        local x, wx = M.bone_parent_xform(mesh, down[i])
        if not x then return nil, wx end
        if b == nil then b = x else
            local s = x.scale
            local t = rotate(x.quat, { x = s.x * b.loc.x, y = s.y * b.loc.y, z = s.z * b.loc.z })
            b = { loc = { x = x.loc.x + t.x, y = x.loc.y + t.y, z = x.loc.z + t.z }, quat = qmul(x.quat, b.quat),
                scale = { x = s.x * b.scale.x, y = s.y * b.scale.y, z = s.z * b.scale.z } }
        end
    end
    local l = b.loc
    local n = math.sqrt(l.x * l.x + l.y * l.y + l.z * l.z)
    if n < 1e-4 then return nil, 'zero_len' end
    return rotate(a.quat, { x = l.x / n, y = l.y / n, z = l.z / n }), a, b
end

-- ---------- components (hide.comp reads) ----------
-- SceneComponent bHiddenInGame and bVisible (props:482; property reads, no UFunction): hidden (bHiddenInGame true or
-- bVisible false), the two raw values | nil, why ('no_object', 'unread': either is no boolean)
function M.comp_hidden(c)
    if not ue.valid(c) then return nil, 'no_object' end
    local h, v = ue.prop(c, 'bHiddenInGame'), ue.prop(c, 'bVisible')
    if type(h) ~= 'boolean' or type(v) ~= 'boolean' then return nil, 'unread' end
    return h or not v, h, v
end

-- ---------- tags (hide.tag): ActorComponent.ComponentTags, an Array of FName (props:449) ----------
-- The live TArray userdata and its count. Never assigned: a Lua table into a TArray property is unproven on 1185
-- (spec 2.2, V2-16), so every change goes through the array itself (append at [#arr + 1], Empty). Bounded by #:
-- indexing past the end grows the engine array
local function tag_array(c)
    if not ue.valid(c) then return nil, 'no_object' end
    local arr = ue.prop(c, 'ComponentTags')
    if arr == nil then return nil, 'unread' end
    local ok, n = pcall(function() return #arr end)
    if not ok then ue.caught(n, 'lab', 'ComponentTags') return nil, 'unread' end
    if math.type(n) ~= 'integer' or n < 0 then return nil, 'unread' end
    return arr, n
end
-- The element names in order as plain strings; nil, 'unread' when an element does not read as a name. An element of a
-- TArray property is the FName itself (LuaTArray.cpp:59-60, :232-251: Operation::Get), never a param: ue.p would ask it
-- for get, which an FName lacks (a raise per element on UE4SS)
local function tag_names(arr, n)
    local out = {}
    local ok, err = pcall(function()
        for i = 1, n do out[i] = ue.str(arr[i]) or false end
    end)
    if not ok then ue.caught(err, 'lab', 'ComponentTags') return nil, 'unread' end
    for i = 1, n do if type(out[i]) ~= 'string' then return nil, 'unread' end end
    return out
end
-- ComponentTags gains name (an FName userdata from ue.fname) at [#arr + 1]; a tag already there (FNames compare without
-- case) is left alone. true, 'added' or 'had' | nil, why ('bad_name', 'no_object', 'unread', or the raised text)
function M.add_tag(c, name)
    if not name_ok(name) then return nil, 'bad_name' end
    local arr, n = tag_array(c)
    if not arr then return nil, n end
    local names, why = tag_names(arr, n)
    if not names then return nil, why end
    for _, s in ipairs(names) do if s:lower() == name:lower() then return true, 'had' end end
    local f = ue.fname(name)
    ue.count_write()
    local ok, err = append(arr, f)
    if not ok then return nil, err end
    return true, 'added'
end
-- ActorComponent:ComponentHasTag(name) (so:12516): true | false | nil, why ('bad_name', 'no_object', 'no_member',
-- 'unread', or the raised text)
function M.has_tag(c, name)
    if not name_ok(name) then return nil, 'bad_name' end
    local f, why = member(c, 'ComponentHasTag')
    if not f then return nil, why end
    local ok, v = answer('ComponentHasTag', pcall(f, c, ue.fname(name)))
    if not ok then return nil, v end
    if type(v) ~= 'boolean' then return nil, 'unread' end
    return v
end
-- The tags now, to put back later: saved[i] an FName userdata made from the element's string (a copy: nothing points
-- into the array, which Empty frees), saved.names the strings. saved | nil, why ('no_object', 'unread')
function M.save_tags(c)
    local arr, n = tag_array(c)
    if not arr then return nil, n end
    local names, why = tag_names(arr, n)
    if not names then return nil, why end
    local saved = { names = names }
    for i, s in ipairs(names) do saved[i] = ue.fname(s) end
    return saved
end
-- The saved tags back in order: Empty(), the count read (0, else 'not_empty'), then each saved FName appended at
-- [#arr + 1]. One write counted for Empty and one per append. true | nil, why ('bad_saved': not save_tags' shape, a
-- string where an FName belongs; 'no_object', 'unread', 'not_empty', 'empty: <text>', 'append: <text>')
function M.restore_tags(c, saved)
    if type(saved) ~= 'table' or type(saved.names) ~= 'table' or #saved ~= #saved.names then return nil, 'bad_saved' end
    for i = 1, #saved do
        if type(saved[i]) == 'string' or ue.str(saved[i]) ~= saved.names[i] then return nil, 'bad_saved' end
    end
    local arr, n = tag_array(c)
    if not arr then return nil, n end
    ue.count_write(1 + #saved)
    local ok, err = answer('Empty', pcall(function() arr:Empty() end))
    if not ok then return nil, 'empty: ' .. tostring(err) end
    ok, n = pcall(function() return #arr end)
    if not ok or n ~= 0 then return nil, 'not_empty' end
    for i = 1, #saved do
        ok, err = append(arr, saved[i])
        if not ok then return nil, 'append: ' .. tostring(err) end
    end
    return true
end
-- The read-back: the array's names equal saved.names in order (without case, as FNames compare). equal (boolean), the
-- names read (plain strings, for the record) | nil, why ('bad_saved', 'no_object', 'unread')
function M.tags_equal(c, saved)
    local want = type(saved) == 'table' and saved.names or nil
    if type(want) ~= 'table' then return nil, 'bad_saved' end
    local arr, n = tag_array(c)
    if not arr then return nil, n end
    local names, why = tag_names(arr, n)
    if not names then return nil, why end
    if #names ~= #want then return false, names end
    for i = 1, #names do
        if type(want[i]) ~= 'string' or names[i]:lower() ~= want[i]:lower() then return false, names end
    end
    return true, names
end

-- ---------- the optimizer (hide.optim) ----------
-- The actor's OptimizationProxy (BP_RenewalNPC_C, props:67060): off true runs DisableAllOptimizations, off false
-- EnableOptimizations (so:41678, :41680). true | nil, why ('bad_arg': off not a boolean, 'no_object', 'no_proxy',
-- 'no_member', or the raised text)
function M.optim(actor, off)
    if type(off) ~= 'boolean' then return nil, 'bad_arg' end
    if not ue.valid(actor) then return nil, 'no_object' end
    local p = ue.prop(actor, 'OptimizationProxy')
    if not ue.valid(p) then return nil, 'no_proxy' end
    local fn = off and 'DisableAllOptimizations' or 'EnableOptimizations'
    local f, why = member(p, fn)
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer(fn, pcall(f, p))
    if not ok then return nil, err end
    return true
end

-- ---------- checked property writes (keep.write) ----------
-- obj[prop] = v with the value read before and after (spec D11: the keep levers DisableDeathDissol, 'Death Delay',
-- DestroyAfterDead, DestroyDelay; a name with a space is a plain string key). Scalars only: v a boolean or a finite
-- number, and the value read before of the same Lua type (UE4SS reads 0 as true for a bool). Never a blind write:
-- a lever that reads nothing is not written. prev, got (each the value or 'unread') and, when no write ran or it
-- raised, why ('bad_prop', 'bad_value', 'no_object', 'unread', 'type', or 'write: <text>')
function M.set_checked(obj, prop, v)
    if type(prop) ~= 'string' or prop == '' then return 'unread', 'unread', 'bad_prop' end
    if type(v) ~= 'boolean' and not num(v) then return 'unread', 'unread', 'bad_value' end
    if not ue.valid(obj) then return 'unread', 'unread', 'no_object' end
    local prev = ue.prop(obj, prop)
    if prev == nil then return 'unread', 'unread', 'unread' end
    if type(prev) ~= type(v) then return prev, 'unread', 'type' end
    ue.count_write()
    local ok, err = assign(obj, prop, v)
    local got = ue.prop(obj, prop)
    if got == nil then got = 'unread' end
    if not ok then return prev, got, 'write: ' .. tostring(err) end
    return prev, got
end

-- ---------- poseables (piece.mesh, piece.pose, piece.isolate) ----------
-- p when it is a PoseableMeshComponent: SetBoneScaleByName exists only there (so:20114), and a victim's body never takes
-- a poseable write. p | nil, why ('no_object', 'not_poseable', 'class_unread': the class is not in memory)
local function poseable(p)
    if not ue.valid(p) then return nil, 'no_object' end
    local is = ue.is_a(p, M.POSEABLE)
    if is == nil then return nil, 'class_unread' end
    if not is then return nil, 'not_poseable' end
    return p
end
-- SetSkinnedAssetAndUpdate(asset, reinit) (so:20844; reinit default true, pieces-physics.md copy step 2), then
-- SkinnedAsset (props:1746) read back. true | nil, why ('no_object', 'not_poseable', 'class_unread', 'no_asset',
-- 'no_member', 'not_set': the read-back is another object or nothing, or the raised text)
function M.set_asset(p, asset, reinit)
    local _, w0 = poseable(p)
    if w0 then return nil, w0 end
    if not ue.valid(asset) then return nil, 'no_asset' end
    local f, why = member(p, 'SetSkinnedAssetAndUpdate')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetSkinnedAssetAndUpdate', pcall(f, p, asset, reinit ~= false))
    if not ok then return nil, err end
    if not ue.same(ue.prop(p, 'SkinnedAsset'), asset) then return nil, 'not_set' end
    return true
end
-- The narrow case the copy runs in (spec M1a 4.2 item 2): the poseable and the source hold the same SkinnedAsset
-- ('asset'), or different assets whose Skeleton objects (USkeletalMesh.Skeleton, Engine.hpp:24712) both read and are the
-- same object ('skeleton'). nil otherwise: an unreadable asset or Skeleton is a refusal, never a guess (a copy between
-- two skeletons is the one native risk of the call [inferred: UE remaps by bone name there])
function M.same_skeleton(p, src)
    local pa, sa = ue.prop(p, 'SkinnedAsset'), ue.prop(src, 'SkinnedAsset')
    if not (ue.valid(pa) and ue.valid(sa)) then return nil end
    if ue.same(pa, sa) then return 'asset' end
    local ps, ss = ue.prop(pa, 'Skeleton'), ue.prop(sa, 'Skeleton')
    if ue.valid(ps) and ue.valid(ss) and ue.same(ps, ss) then return 'skeleton' end
    return nil
end
-- CopyPoseFromSkeletalComponent(src) (so:20106) from a SkeletalMeshComponent that leads: a source with a
-- LeaderPoseComponent (props:1747; the TWeakObjectPtr read as ue.lua's leader_of reads it) is refused (spec D10: a
-- leader-posed follower gives an empty pose), and so is a source on another skeleton (M.same_skeleton). The reflected
-- CachedBoneSpaceTransforms (props:1800) is no gate: it is the update-rate-optimization interpolation cache and reads
-- empty on live and dead bodies alike (run 3, P13: the engine copy never ran behind that old refusal); P13 proves the
-- pose by its bone positions instead. true | nil, why ('no_object', 'not_poseable', 'class_unread', 'no_source',
-- 'not_skeletal', 'follower', 'skeleton_differs', 'no_member', or the raised text)
function M.copy_pose(p, src)
    local _, w0 = poseable(p)
    if w0 then return nil, w0 end
    if not ue.valid(src) then return nil, 'no_source' end
    if ue.is_a(src, M.SKELETAL) ~= true then return nil, 'not_skeletal' end
    local lp = ue.get(src, 'LeaderPoseComponent')
    if lp == nil then lp = ue.get(src, 'MasterPoseComponent') end
    if ue.valid(ue.weak(lp)) then return nil, 'follower' end
    if not M.same_skeleton(p, src) then return nil, 'skeleton_differs' end
    local f, why = member(p, 'CopyPoseFromSkeletalComponent')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('CopyPoseFromSkeletalComponent', pcall(f, p, src))
    if not ok then return nil, err end
    return true
end
-- SetBoneScaleByName(bone, (s, s, s), ComponentSpace) (so:20114): s a positive finite number (0.001 collapses, never 0,
-- DESIGN C1). true | nil, why ('bad_bone', 'bad_scale', 'no_object', 'not_poseable', 'class_unread', 'no_member', or
-- the raised text)
function M.bone_scale(p, bone, s)
    if not name_ok(bone) then return nil, 'bad_bone' end
    if not (num(s) and s > 0) then return nil, 'bad_scale' end
    local _, w0 = poseable(p)
    if w0 then return nil, w0 end
    local f, why = member(p, 'SetBoneScaleByName')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetBoneScaleByName', pcall(f, p, ue.fname(bone), ue.vec(s, s, s), M.SPACE_COMPONENT))
    if not ok then return nil, err end
    return true
end
-- SetBoneTransformByName(bone, x, ComponentSpace) (so:20115): x the plain pose (scale a number or {x, y, z}, default 1)
-- as a full FTransform. true | nil, why ('bad_bone', 'bad_xform', 'no_object', 'not_poseable', 'class_unread',
-- 'no_member', or the raised text)
function M.bone_xform_set(p, bone, x)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local ft = ft_of(x)
    if not ft then return nil, 'bad_xform' end
    local _, w0 = poseable(p)
    if w0 then return nil, w0 end
    local f, why = member(p, 'SetBoneTransformByName')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetBoneTransformByName', pcall(f, p, ue.fname(bone), ft, M.SPACE_COMPONENT))
    if not ok then return nil, err end
    return true
end
-- The bone in component space on any skinned component: GetSocketTransform(bone, RTS_Component 2), after ue.has_bone
-- (a name that is no bone answers the component's own transform). Read from a corpse's body leader, it is the pose the
-- player sees; the poseable's own array may not be refreshed yet (spec M1a 4.2 item 2). The plain pose | nil, why
-- ('bad_bone', 'no_object', 'no_member', 'no_bone', 'unread', or the raised text)
function M.bone_component_xform(mesh, bone)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local f, why = member(mesh, 'GetSocketTransform')
    if not f then return nil, why end
    if not ue.has_bone(mesh, bone) then return nil, 'no_bone' end
    local ok, t = answer('GetSocketTransform', pcall(f, mesh, ue.fname(bone), M.SPACE_COMPONENT_SOCKET))
    if not ok then return nil, t end
    local x = plain_xf(t)
    if not x then return nil, 'unread' end
    return x
end
-- GetBoneTransformByName(bone, ComponentSpace) (so:20110) as the plain pose (a read). The plain pose | nil, why
-- ('bad_bone', 'no_object', 'not_poseable', 'class_unread', 'no_member', 'unread', or the raised text)
function M.bone_xform_get(p, bone)
    if not name_ok(bone) then return nil, 'bad_bone' end
    local _, w0 = poseable(p)
    if w0 then return nil, w0 end
    local f, why = member(p, 'GetBoneTransformByName')
    if not f then return nil, why end
    local ok, t = answer('GetBoneTransformByName', pcall(f, p, ue.fname(bone), M.SPACE_COMPONENT))
    if not ok then return nil, t end
    local x = plain_xf(t)
    if not x then return nil, 'unread' end
    return x
end

-- ---------- the Piece carrier (piece.spawn, piece.phys) ----------
-- BoxComponent:SetBoxExtent(e, false) (so:13445): e the half extent {x, y, z} (len/2, r, r; pieces-physics.md copy step
-- 7), each positive. true | nil, why ('bad_extent', 'no_object', 'no_member', or the raised text)
function M.box_extent(c, e)
    local v = vec3(e)
    if not v or v.x <= 0 or v.y <= 0 or v.z <= 0 then return nil, 'bad_extent' end
    local f, why = member(c, 'SetBoxExtent')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetBoxExtent', pcall(f, c, ue.vec(v.x, v.y, v.z), false))
    if not ok then return nil, err end
    return true
end
-- Physics on a trace-neutral carrier (the caller made it trace-neutral, ue.trace_neutral, and shows it first), in the
-- order of pieces-physics.md launch step 2, simulate last: SetMobility(Movable 2) (:20563), SetMassOverrideInKg('None',
-- kg, true) (:20292), SetUseCCD(ccd, 'None') (:20320), SetSimulatePhysics(true) (:20314). Every member is fetched before
-- the first write; a raised step stops the rest. One write counted per step that runs. true | nil, why ('bad_mass',
-- 'no_object', 'no_member:<fn>', '<fn>: <text>')
function M.physics_on(c, kg, ccd)
    if not (num(kg) and kg > 0) then return nil, 'bad_mass' end
    if not ue.valid(c) then return nil, 'no_object' end
    local none = ue.fname('None')
    local steps = { { 'SetMobility', M.MOVABLE }, { 'SetMassOverrideInKg', none, kg + 0.0, true },
        { 'SetUseCCD', ccd == true, none }, { 'SetSimulatePhysics', true } }
    local fs = {}
    for i, s in ipairs(steps) do
        local f, why = member(c, s[1])
        if not f then return nil, why .. ':' .. s[1] end
        fs[i] = f
    end
    for i, s in ipairs(steps) do
        ue.count_write()
        local ok, err = answer(s[1], pcall(fs[i], c, table.unpack(s, 2, #s)))
        if not ok then return nil, s[1] .. ': ' .. tostring(err) end
    end
    return true
end
-- AddImpulse(v, 'None', true) (:20168): a velocity change, mass-independent, its length capped at cap (default
-- M.VEL_CAP 600 uu/s; pieces-physics.md launch step 4); v {x, y, z} or {X, Y, Z}, a zero v allowed (P15). true, the
-- velocity sent {x, y, z}, capped (boolean) | nil, why ('bad_vel', 'bad_cap', 'no_object', 'no_member', or the raised
-- text)
function M.velocity_change(c, v, cap)
    if cap == nil then cap = M.VEL_CAP end
    if not (num(cap) and cap >= 0) then return nil, 'bad_cap' end
    local u = vec3(v)
    if not u then return nil, 'bad_vel' end
    local n = math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z)
    local capped = n > cap
    if capped then
        local k = cap / n
        u = { x = u.x * k, y = u.y * k, z = u.z * k }
    end
    local f, why = member(c, 'AddImpulse')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('AddImpulse', pcall(f, c, ue.vec(u.x, u.y, u.z), ue.fname('None'), true))
    if not ok then return nil, err end
    return true, u, capped
end

-- ---------- Cap meshes (cap.pmc, lab.tarray.probe, cap.mesh; spec D8, section 3.7) ----------
-- A mesh of data/caps_generic.lua (gore-mesh/1 via to_lua_mesh.py: flat positions and normals x,y,z per vertex, uvs
-- u,v, tris 0-based in UE front-face order, cm) as the TArray elements CreateMeshSection_LinearColor takes, built once
-- per mesh table and cached (weak keys). The expanded mesh: { name, nverts, ntris, V = {{X,Y,Z}}, N = {{X,Y,Z}} or {},
-- UV = {{X,Y}} or {}, T = the flat 0-based indices (the source table, never copied), expanded = true } | nil,
-- 'bad_mesh' (a missing or ragged array, a count off nverts or ntris, a non-number). Floats only in V, N and UV
local expanded = setmetatable({}, { __mode = 'k' })
local function elems(flat, width, n, fields)
    if flat == nil then return {} end
    if type(flat) ~= 'table' then return nil end
    if #flat == 0 then return {} end
    if #flat ~= width * n then return nil end
    local out = {}
    for i = 1, n do
        local e, b = {}, (i - 1) * width
        for k = 1, width do
            local v = flat[b + k]
            if not num(v) then return nil end
            e[fields[k]] = v + 0.0
        end
        out[i] = e
    end
    return out
end
function M.expand(mesh)
    if type(mesh) ~= 'table' then return nil, 'bad_mesh' end
    if mesh.expanded == true then return mesh end
    local e = expanded[mesh]
    if e then return e end
    local p, t = mesh.positions, mesh.tris
    if type(p) ~= 'table' or type(t) ~= 'table' or #p == 0 or #p % 3 ~= 0 or #t == 0 or #t % 3 ~= 0 then
        return nil, 'bad_mesh'
    end
    local nv, nt = #p // 3, #t // 3
    if (mesh.nverts ~= nil and mesh.nverts ~= nv) or (mesh.ntris ~= nil and mesh.ntris ~= nt) then
        return nil, 'bad_mesh'
    end
    local V, N, UV = elems(p, 3, nv, { 'X', 'Y', 'Z' }), elems(mesh.normals, 3, nv, { 'X', 'Y', 'Z' }),
        elems(mesh.uvs, 2, nv, { 'X', 'Y' })
    if not (V and N and UV) then return nil, 'bad_mesh' end
    e = { name = mesh.name, nverts = nv, ntris = nt, V = V, N = N, UV = UV, T = t, expanded = true }
    expanded[mesh] = e
    return e
end

M.SECTION = 0                   -- the default section: a lab Cap is section 0 of its own component (P7 replaces it)
-- Section `section` (default M.SECTION; a beta Cap builds 0, 1 and 2, lab_cap's hidden test section is 3) of pmc
-- becomes mesh (raw or expanded) through CreateMeshSection_LinearColor(section, V, T, N, UV0, {}, {}, {}, {}, {},
-- false, false): no collision, no sRGB conversion; UV1-UV3, VertexColors and Tangents are {} (a nil TArray is never
-- popped and shifts every later param), the colour comes from the MID (M.mid), never from vertex colours. Before the
-- call, in this order: the section an integer at or over 0, every array through TA.check (a poisoned state refuses
-- here), every index an integer in [0, nverts), both members fetched, then TA.charge(nverts, 3 x ntris, kind) (D19:
-- kind defaults to 'nub', a lab stand-in in the 4 MiB sub-budget; TA.CAP the session budget only) and, for section 0
-- (a component's first), TA.pmc(1): a later section of the same component books its arrays only, so a three-section
-- Cap books its sections plus one component. Nothing is booked when a check or the charge fails, but a TA.pmc
-- refusal after the charge (under 27 KB of the session budget left) keeps the charge booked: an over-booking, never an
-- under-booking. A raised call poisons TA
-- (TA.poison: one conversion error leaves the converter stuck). Then GetNumSections read back (at least section + 1),
-- and nothing else: no property of the component or of a section is read (spec M1a 4.2 item 3: an element of
-- ProcMeshSections is a struct inside a struct array, and reading one crashes UE4SS natively in PBZ [competitor
-- LingeringDead, Nexus 85]). sections (an integer, at least section + 1) and the bytes charged | nil, why
-- ('bad_section', 'bad_mesh', 'poisoned', 'not_table', 'not_sequence', 'bad_element', 'bad_index', 'no_object',
-- 'no_member', 'leak_budget', 'bad_count', 'unread', 'no_section', or the raised text)
function M.pmc_section(pmc, mesh, kind, section)
    if section == nil then section = M.SECTION end
    if math.type(section) ~= 'integer' or section < 0 then return nil, 'bad_section' end
    local e, we = M.expand(mesh)
    if not e then return nil, we end
    local u1, u2, u3, col, tan = {}, {}, {}, {}, {}
    local arrays = { { e.V, 'vec' }, { e.T, 'int' }, { e.N, 'vec' }, { e.UV, 'vec2' }, { u1, 'vec2' }, { u2, 'vec2' },
        { u3, 'vec2' }, { col, 'color' }, { tan, 'tangent' } }
    for _, a in ipairs(arrays) do
        local n, why = TA.check(a[1], a[2])
        if not n then return nil, why end
    end
    local nv, T = #e.V, e.T
    for i = 1, #T do
        if T[i] < 0 or T[i] >= nv then return nil, 'bad_index' end
    end
    local f, why = member(pmc, 'CreateMeshSection_LinearColor')
    if not f then return nil, why end
    local g, wg = member(pmc, 'GetNumSections')
    if not g then return nil, wg end
    local okc, bytes = TA.charge(nv, #T, kind or 'nub')
    if not okc then return nil, bytes end
    if section == 0 then
        local okp, wp = TA.pmc(1)
        if not okp then return nil, wp end
    end
    ue.count_write()
    local ok, err = answer('CreateMeshSection_LinearColor',
        pcall(f, pmc, section, e.V, T, e.N, e.UV, u1, u2, u3, col, tan, false, false))
    if not ok then TA.poison('CreateMeshSection_LinearColor') return nil, err end
    local okn, n = answer('GetNumSections', pcall(g, pmc))
    if not okn then return nil, n end
    if math.type(n) ~= 'integer' then return nil, 'unread' end
    if n < section + 1 then return nil, 'no_section' end
    return n, bytes
end

-- ---------- the meat cap and the Cap materials (cap.meat, cap.mid; caps.md 'UE fast path' step 1) ----------
-- StaticMeshComponent:SetStaticMesh(mesh) (so:21304), then StaticMesh read back. true, changed (the call's boolean:
-- false when that mesh was set already) | nil, why ('no_mesh', 'no_object', 'no_member', 'not_set': the read-back is
-- another mesh, as on a Static component, or the raised text)
function M.set_static_mesh(smc, mesh)
    if not ue.valid(mesh) then return nil, 'no_mesh' end
    local f, why = member(smc, 'SetStaticMesh')
    if not f then return nil, why end
    ue.count_write()
    local ok, changed = answer('SetStaticMesh', pcall(f, smc, mesh))
    if not ok then return nil, changed end
    if not ue.same(ue.prop(smc, 'StaticMesh'), mesh) then return nil, 'not_set' end
    return true, changed == true
end

M.COLOR_PARAM = 'Color'         -- BasicShapeMaterial's vector parameter (P5 sets it pink [P])
-- A plain colour as a full FLinearColor: R, G, B (or r, g, b) finite numbers, A (or a) default 1; nil otherwise
local function linear(c)
    if type(c) ~= 'table' then return nil end
    local r, g, b, a = c.R or c.r, c.G or c.g, c.B or c.b, c.A or c.a
    if a == nil then a = 1 end
    if not (num(r) and num(g) and num(b) and num(a)) then return nil end
    return { R = r + 0.0, G = g + 0.0, B = b + 0.0, A = a + 0.0 }
end
-- o:fn(...) through its UFunction member: true and the results | false, why
local function call(o, fn, ...)
    local f, why = member(o, fn)
    if not f then return false, why end
    return answer(fn, pcall(f, o, ...))
end
-- The library route of a MID, when the component's own CreateDynamicMaterialInstance gave nothing (TC-LAB-02 run 1: P5
-- no_mid on a PMC with one section; the cause was not logged): info gets the slot count (GetNumMaterials) and the
-- slot's material before (GetMaterial; key 'slot<slot>', slot0 for the lab's slot 0);
-- KismetMaterialLibrary:CreateDynamicMaterialInstance(c, parent or the slot's material, 'None', 0) on its CDO
-- (so:17279), SetMaterial(slot, mid) (so:20294), read back by GetMaterial(slot). The MID | nil, why
local function lib_mid(c, parent, info, slot)
    local okn, n = call(c, 'GetNumMaterials')
    info.n_mats = okn and math.tointeger(n) or 'unread'
    local okg, cur = call(c, 'GetMaterial', slot)
    cur = okg and ue.valid(cur) and cur or nil
    info['slot' .. slot] = cur and (ue.name(cur) or 'unread') or 'none'
    local src = parent or cur
    if not src then return nil, 'no_mid' end
    local lib = ue.cdo('kmat')
    if not ue.valid(lib) then return nil, 'no_mid: no_library' end
    ue.count_write()
    local okc, m = call(lib, 'CreateDynamicMaterialInstance', c, src, ue.fname('None'), 0)
    if not okc then return nil, 'no_mid: ' .. tostring(m) end
    if not ue.valid(m) then return nil, 'no_mid: library' end
    ue.count_write()
    local oks, ws = call(c, 'SetMaterial', slot, m)
    if not oks then return nil, 'no_mid: set: ' .. tostring(ws) end
    local okr, back = call(c, 'GetMaterial', slot)
    if not (okr and ue.same(back, m)) then return nil, 'no_mid: not_set' end
    info.via = 'library'
    return m
end
-- The parameter names of a texture map { [name] = texture object } in name order (two runs set them alike); {} for
-- nil; nil for anything else (a non-table, a bad name, an invalid texture)
local function texture_names(textures)
    if textures == nil then return {} end
    if type(textures) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(textures) do
        if not name_ok(k) or not ue.valid(v) then return nil end
        out[#out + 1] = k
    end
    table.sort(out)
    return out
end
-- A MID in material slot `slot` of c (default 0: the lab Cap's one section or the Sphere's one slot; a beta Cap's
-- section i draws slot i, BD4): CreateDynamicMaterialInstance(slot, parent, 'None') (so:20183; a nil parent keeps the
-- slot's own material as the parent), else the library route above; then, unless color is nil (the parent's own
-- colour stays), SetVectorParameterValue(FName M.COLOR_PARAM, the colour as an FLinearColor) (so:19150); then each
-- texture of textures ({ [parameter name] = texture object }, in name order) through SetTextureParameterValue(FName,
-- texture) (the blood.look call class). A Cap's colour lives here, never in vertex colours. One write counted per call.
-- The MID | nil, why ('bad_color', 'bad_slot', 'bad_textures', 'no_parent', 'no_object', 'no_member', 'no_mid': no
-- material in the slot and no parent, 'no_mid: <why>' when the library route failed too, the raised text; 'color:
-- <why>' or 'texture: <why>' when the colour or a texture failed after the MID was made, which then sits in the slot
-- with the parent's own values), and info { via = 'component' | 'library', n_mats, slot<slot> } (the last two only
-- after a fallback)
function M.mid(c, parent, color, slot, textures)
    local lc = nil
    if color ~= nil then
        lc = linear(color)
        if not lc then return nil, 'bad_color' end
    end
    if slot == nil then slot = 0 end
    if math.type(slot) ~= 'integer' or slot < 0 then return nil, 'bad_slot' end
    local texs = texture_names(textures)
    if not texs then return nil, 'bad_textures' end
    if parent ~= nil and not ue.valid(parent) then return nil, 'no_parent' end
    local f, why = member(c, 'CreateDynamicMaterialInstance')
    if not f then return nil, why end
    ue.count_write()
    local ok, m = answer('CreateDynamicMaterialInstance', pcall(f, c, slot, parent, ue.fname('None')))
    if not ok then return nil, m end
    local info = { via = 'component' }
    if not ue.valid(m) then
        info.via = 'none'
        m, why = lib_mid(c, parent, info, slot)
        if not m then return nil, why, info end
    end
    if lc then
        local g, wg = member(m, 'SetVectorParameterValue')
        if not g then return nil, 'color: ' .. tostring(wg), info end
        ue.count_write()
        local okv, err = answer('SetVectorParameterValue', pcall(g, m, ue.fname(M.COLOR_PARAM), lc))
        if not okv then return nil, 'color: ' .. tostring(err), info end
    end
    for _, p in ipairs(texs) do
        local h, wh = member(m, 'SetTextureParameterValue')
        if not h then return nil, 'texture: ' .. tostring(wh), info end
        ue.count_write()
        local okt, err = answer('SetTextureParameterValue', pcall(h, m, ue.fname(p), textures[p]))
        if not okt then return nil, 'texture: ' .. tostring(err), info end
    end
    return m, nil, info
end
-- A ready material m (a game material or a held MID, lab_look's tiers) into slot `slot` of c: SetMaterial(slot, m)
-- (so:20294), then GetMaterial(slot) read back. One write counted. true | nil, why ('bad_slot', 'no_material',
-- 'no_object', 'no_member', 'not_set': the read-back is another material or nothing, as on a component without that
-- slot, or the raised text)
function M.set_material(c, slot, m)
    if math.type(slot) ~= 'integer' or slot < 0 then return nil, 'bad_slot' end
    if not ue.valid(m) then return nil, 'no_material' end
    local f, why = member(c, 'SetMaterial')
    if not f then return nil, why end
    ue.count_write()
    local ok, err = answer('SetMaterial', pcall(f, c, slot, m))
    if not ok then return nil, err end
    local okr, back = call(c, 'GetMaterial', slot)
    if not (okr and ue.same(back, m)) then return nil, 'not_set' end
    return true
end

return M
