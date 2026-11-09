-- status: new for Jamon Iberico (offline only; the author's next lab run decides) origin: the author 2026-11-02, after
-- the f93cf2f run: "I did not see much difference between the jamon modes" (Iberico drew flat colours: tier A never
-- built); the review after 93e6d1a: the Caps were fitted in their anchor's frame, so they seat there (lab_cap ib_seat)
-- lab_iberico.lua: Jamon Iberico (cap_look 'textured'), LeovvayGore's own stumps: the DD2 cap pipeline's fitted meshes
-- (data/caps_dd2/<cap>.lua, tools/caps_dd2) on the bodies they were fitted to, drawn with our own cap atlas
-- (Textures/cap_iberico_256.png) through a MID of a game parent. Player beta (META.beta_modules, after lab_look, before
-- lab_cap); init stays inert (no listener, no ticker, no record) unless LAB.beta(). lab_cap asks it at the reserve
-- (IB.parts) and per section (IB.material): both pure lookups, no engine call, safe inside 'lab.cut.stage'.
-- * Fits (IB.FITS): the body mesh a data family was fitted to, by the leaf name of the cut's leader asset (cut.asset):
--   MaleThug_Body -> MaleThug. Any other body keeps today's Caps (data/caps_beta.lua); Serrano never comes here (lab_cap
--   asks only while cap_look reads 'textured').
-- * Data (no engine call): while cap_look reads 'textured', one step a frame outside busy frames: a level file required
--   and checked (version 1, set caps_dd2, its cap, both sides' meshes present and their anchor readable, mirror nil or
--   'y'), then one mesh a frame prepared: the left mesh as it is and, on a level with mirror 'y', its right copy (y
--   negated on positions and normals, every triangle reversed: index 2 <-> 3, the file header's rule), each expanded
--   once (ue_lab.expand: the TArray-ready form pmc_section takes). One cap_iberico_data record when the queue is done. A
--   cut before its meshes are ready keeps today's Caps ('loading'): nothing loads or expands in a kill frame.
-- * Seats (IB.parts' third value): each side's anchor { bone, loc, quat }, the bone and the cap frame's pose in that
--   bone's bind frame the meshes were fitted in (the file's sides.<side>.anchor: lpos, lrot as x, y, z, w; contain.py's
--   posed passes kept the Cap fixed in it); lab_cap seats an Iberico end there instead of the death pose's direction.
--   The right side's anchor is the left one mirrored (IB.mirror_anchor), as its meshes are.
-- * The look, one build a map under lab_look's gates (cap_look 'textured', a lab_death seen on this map, lab_plan's
--   quiet(), not busy, not paused, not off, LAB.pinned(), not lab_end), all in one one-shot frame, each step under its
--   own sentinel name (a texture or MID made in one frame and held in the same frame: no GC between them):
--   1. the PNG: <mod folder>/Textures/<file> (adapter/env.lua E.mod_dir, absolute in a Steam install); a file that does
--      not open refuses the look ('no_file').
--   2. 'cap.tex.import': KismetRenderingLibrary:ImportFileAsTexture2D(world, path) on its CDO (so:18064; PBZ.exe's path:
--      LoadFileToArray, the ImageWrapper decode, UTexture2D::CreateTransient with mip 0 only, SRGB left at its default
--      true: scratch/port-dd2/pbz-textures/import_path_disasm.txt). No texture: 'no_texture'.
--   3. 'cap.tex.read': Blueprint_GetSizeX and _GetSizeY, and the properties SRGB, CompressionSettings,
--      VirtualTextureStreaming, Filter, AddressX, AddressY; a size that is not above 0 refuses ('empty').
--   4. per parent of the look, in order: 'cap.tex.load' (ue.asset: found, else LoadAsset), then 'cap.tex.mid':
--      KismetMaterialLibrary:CreateDynamicMaterialInstance(world, parent, None, 0), SetTextureParameterValue(param, the
--      texture), K2_GetTextureParameterValue(param) read back. The first parent whose read-back is our texture wins.
--   5. 'cap.keep': the MID held for the map on the player controller's keeper (ue.hold kind 'material': the keeper's
--      slot roots the MID, and the MID's parameter roots the texture; Lua references root nothing). The look a press
--      replaced is released first under the same name (the Caps that drew it keep it in their own slots).
--   One forced cap_iberico_build record { look, file, abs, x, y, srgb, compression, vt, filter, address, parent, param,
--   set, same, tried, held, why, ms }. A build that ends refused stays refused for the map (a press or the next map
--   tries again); a map load ends the hold (ue.reset_caches) and the next map builds again.
-- * Looks (IB.LOOKS, the read-backs' test: the test build's key cycles them, Ctrl+Shift+F6 through lab_testkeys and
--   IB.press()): 'flesh' (the default: MI_FX_C2_Flesh_001_B's BaseColor, else FlattenMaterial's BaseColorTexture, with
--   cap_iberico_256.png), 'flesh_calib' and 'flatten_calib' (the calibration atlas cap_calib_256.png on one parent each:
--   which tile and flip each draws, whether the alpha ramp clips), 'flatten' (FlattenMaterial with the shipped atlas),
--   'flesh_512' (the 512 px lab atlas). A press only flips the look and queues a build for the next quiet moment; the
--   player zip leaves the calibration and 512 PNGs and the key out (gore.project.json package.ship_when).
-- * Names (meta.lua lab_risky, lab_linger; data/lab_classes.lua): cap.tex.load (3), cap.tex.import (10, inherited),
--   cap.tex.read (0), cap.tex.mid (10, inherited), cap.keep (M1a P9b's hold class). The build checks each with
--   SENT.is_disabled and LAB.sig first: a refused name refuses the build (one cap_iberico_skip record per name and
--   why), 'sig_pending' waits a frame.
-- API: IB.parts(cut, cap, side) -> meshes (expanded, in section order), secs ({ 'face', 'inlay' }), anchor ({ bone, loc
--   {x,y,z} cm, quat {w,x,y,z} unit }: this end's seat, mirrored on the right; shared, never written) | nil, why ('off',
--   'not_textured', 'no_fit', 'loading', 'no_data', 'no_side', 'no_mirror', 'bone'); IB.mirror_anchor(anchor) -> the
--   right side's anchor (pure); IB.material() -> mid, look | nil,
--   why ('off', 'not_textured', 'pending', 'refused: <why>', 'gone'); IB.press() -> word, reply; IB.LOOK_OF (the flat
--   colour section lab_cap falls back to: face meat, inlay pale); lifecycle init(A) reset(reason) shutdown() status().
-- What the mock cannot prove: native faults in the import or its decode, whether either parent samples our texture on a
-- ProceduralMeshComponent (the calibration looks settle it), the UV flip, the masked parent's alpha clip, mip 0
-- aliasing at distance, the hold keeping the texture alive for the map.
local BUS = require('core.bus')
local S = require('core.sched')
local MODOFF = require('core.modoff')
local C = require('core.config')
local V = require('core.vmath')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local ENV = require('adapter.env')
local LAB = require('lab_probe')
local LOOK = require('lab_look')                        -- its gates and MID calls (beta_modules loads it first)

local IB = { ERR_CHARS = 160 }
IB.LEVELS = { 'neck', 'shoulder', 'elbow', 'hip', 'knee' }
-- the body mesh (the leaf of the cut's leader asset) -> the family its data/caps_dd2 files were fitted to
IB.FITS = { MaleThug_Body = 'MaleThug' }
-- a section of a fitted Cap -> the flat colour (data/caps_beta_sizing.lua colors) lab_cap draws while no look is held
IB.LOOK_OF = { face = 'meat', inlay = 'pale' }
local function ref(dir, name) return dir .. name .. '.' .. name end
-- the parents: their object path and the texture parameter the look writes (cap_look_mat records of the f93cf2f run:
-- MI_FX_C2_Flesh_001_B answers BaseColor=T_FX_Flesh_001_BC, FlattenMaterial BaseColorTexture=BaseFlattenDiffuseMap)
IB.PARENTS = {
    flesh = { path = ref('/PBZVFXPack/VFX/A_Materials/Common/Clip_002/', 'MI_FX_C2_Flesh_001_B'), param = 'BaseColor' },
    flatten = { path = ref('/Engine/EngineMaterials/', 'FlattenMaterial'), param = 'BaseColorTexture' },
}
-- our PNGs (tools/caps_dd2/tex_pbz.py): the shipped atlas, the calibration atlas, the 512 px lab atlas
IB.FILES = { ship = 'cap_iberico_256.png', calib = 'cap_calib_256.png', hi = 'cap_iberico_512.png' }
IB.LOOKS = {
    { key = 'flesh', parents = { 'flesh', 'flatten' }, file = 'ship' },
    { key = 'flesh_calib', parents = { 'flesh' }, file = 'calib' },
    { key = 'flatten_calib', parents = { 'flatten' }, file = 'calib' },
    { key = 'flatten', parents = { 'flatten' }, file = 'ship' },
    { key = 'flesh_512', parents = { 'flesh' }, file = 'hi' },
}
IB.NAMES = { 'cap.tex.import', 'cap.tex.read', 'cap.tex.load', 'cap.tex.mid', 'cap.keep' }

-- The names this file reads (lint_names reads these literal tables: keep the syntax and the double quotes); its
-- UFunctions are data/hooks.json calls rows (data/lab_classes.lua cap.tex.*, cap.keep)
local N = {}
local F = {
    {"/Script/Engine.Texture", "SRGB"},
    {"/Script/Engine.Texture", "CompressionSettings"},
    {"/Script/Engine.Texture", "VirtualTextureStreaming"},
    {"/Script/Engine.Texture", "Filter"},
    {"/Script/Engine.Texture2D", "AddressX"},
    {"/Script/Engine.Texture2D", "AddressY"},
}
IB.N, IB.F = N, F

local A = nil
local function new_state()
    return { init = false, ended = false, look_i = 1, dirty = false, built_ep = nil, held = nil, why = nil,
        death_ep = nil, busy_f = nil, busy = 0, builds = 0, wait = nil, skips = {}, press_n = 0 }
end
local st = new_state()
-- the data cache: pure Lua, kept across map loads (shutdown drops it)
local function new_cache() return { levels = {}, prep = {}, bad = {}, queue = nil, qi = 1, done = false, t0 = nil } end
local cache = new_cache()

local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function err_text(e)
    e = tostring(e)
    return #e > IB.ERR_CHARS and e:sub(1, IB.ERR_CHARS) or e
end
local function or_unread(v) if v == nil then return 'unread' end return v end
-- cap_look reads 'textured': read again only when the settings changed (C.gen)
local tex_gen, tex_on = nil, false
local function textured()
    local g = C.gen()
    if g ~= tex_gen then tex_gen, tex_on = g, C.knob('cap_look') == 'textured' end
    return tex_on
end

-- ---------- the data: levels, mirrored copies, expanded meshes ----------
-- The right copy of a left mesh: y negated on positions and normals, every triangle reversed (index 2 <-> 3); uvs shared
function IB.mirror(m)
    local p, n, t = m.positions, m.normals or {}, m.tris
    local P, Nn, T = {}, {}, {}
    for i = 1, #p, 3 do P[i], P[i + 1], P[i + 2] = p[i], -p[i + 1], p[i + 2] end
    for i = 1, #n, 3 do Nn[i], Nn[i + 1], Nn[i + 2] = n[i], -n[i + 1], n[i + 2] end
    for i = 1, #t, 3 do T[i], T[i + 1], T[i + 2] = t[i], t[i + 2], t[i + 1] end
    return { name = tostring(m.name) .. '_r', side = m.side, section = m.section, nverts = m.nverts, ntris = m.ntris,
        positions = P, normals = Nn, uvs = m.uvs, tris = T }
end
-- A side's anchor as lab_cap seats it, { bone, loc {x,y,z}, quat {w,x,y,z} unit }, from the file's { bone, lpos, lrot
-- (x, y, z, w: to_pbz.py quat_xyzw) }; nil when it does not read
local function anchor_of(a)
    if type(a) ~= 'table' or type(a.bone) ~= 'string' or a.bone == '' then return nil end
    local p, r = a.lpos, a.lrot
    if type(p) ~= 'table' or type(r) ~= 'table' then return nil end
    for i = 1, 3 do if not num(p[i]) then return nil end end
    for i = 1, 4 do if not num(r[i]) then return nil end end
    local n = math.sqrt(r[1] * r[1] + r[2] * r[2] + r[3] * r[3] + r[4] * r[4])
    if math.abs(n - 1) > 1e-3 then return nil end
    return { bone = a.bone, loc = { x = p[1] + 0.0, y = p[2] + 0.0, z = p[3] + 0.0 },
        quat = { w = r[4] / n, x = r[1] / n, y = r[2] / n, z = r[3] / n } }
end
local qmul = V.quat_mul
-- Half turns about Y and Z
local Q_Y, Q_Z = { w = 0.0, x = 0.0, y = 1.0, z = 0.0 }, { w = 0.0, x = 0.0, y = 0.0, z = 1.0 }
-- The right side's anchor from the left one, by the rule the mesh mirror stands on: y -> -y in the cap frame (Dy) is
-- the world mirror x -> -x (S) of the mirror-identical skin (to_pbz.py checks it on the skeleton). A sided anchor
-- bone's twin (_l -> _r) has the left bind axes mirrored and all three negated (A_r = S A_l (-I)); a central bone
-- (pelvis) is its own mirror with its Z negated (S A = A diag(1, 1, -1)). So the right seat is F lpos and F R Dy with
-- F = -I on a sided bone (lpos negated; lrot then a half turn about Y) and F = diag(1, 1, -1) on a central one (z
-- negated; a half turn about Z, then lrot, then a half turn about Y). On MaleThug's bind skeleton every mirrored
-- level's right anchor, computed from the right bones, matches this within 1e-5 (tests/test_lab_iberico.lua)
function IB.mirror_anchor(a)
    local p, q = a.loc, qmul(a.quat, Q_Y)
    if a.bone:match('_[lL]$') then
        return { bone = (a.bone:gsub('_[lL]$', '_r')), loc = { x = -p.x, y = -p.y, z = -p.z }, quat = q }
    end
    return { bone = a.bone, loc = { x = p.x, y = p.y, z = -p.z }, quat = qmul(Q_Z, q) }
end
-- One level file required and checked; its meshes queued for the prep (left, then the right copy on a mirror 'y' level)
local function load_level(lv)
    local ok, d = pcall(require, 'data.caps_dd2.' .. lv)
    local why, by, anchors = nil, {}, {}
    if not ok then why = 'require: ' .. err_text(d)
    elseif type(d) ~= 'table' then why = 'not_table'
    elseif d.version ~= 1 or d.set ~= 'caps_dd2' or d.cap ~= lv or type(d.family) ~= 'string' then why = 'header'
    elseif d.mirror ~= nil and d.mirror ~= 'y' then why = 'mirror'
    elseif type(d.sides) ~= 'table' or type(d.meshes) ~= 'table' then why = 'sides'
    end
    if not why then
        for _, m in ipairs(d.meshes) do if type(m) == 'table' and type(m.name) == 'string' then by[m.name] = m end end
        for _, side in ipairs({ 'stump', 'piece' }) do
            local sd = d.sides[side]
            if type(sd) ~= 'table' or type(sd.meshes) ~= 'table' or sd.meshes[1] == nil or type(sd.cut) ~= 'string' then
                why = why or ('side ' .. side)
            else
                for _, n in ipairs(sd.meshes) do if not by[n] then why = why or ('mesh ' .. tostring(n)) end end
                local a = anchor_of(sd.anchor)         -- the meshes sit in this frame: no seat, no fitted Caps
                if not a then why = why or ('anchor ' .. side)
                else anchors[side] = { l = a, r = d.mirror == 'y' and IB.mirror_anchor(a) or nil } end
            end
        end
    end
    if why then
        cache.levels[lv], cache.bad[lv] = false, why
        return
    end
    cache.levels[lv] = { data = d, family = d.family, anchors = anchors }
    for _, side in ipairs({ 'stump', 'piece' }) do
        for _, n in ipairs(d.sides[side].meshes) do
            cache.queue[#cache.queue + 1] = { name = n, mesh = by[n] }
            if d.mirror == 'y' then cache.queue[#cache.queue + 1] = { name = n, mesh = by[n], right = true } end
        end
    end
end
local function prep_mesh(job)
    local key = job.name .. (job.right and '@r' or '')
    local m = job.right and IB.mirror(job.mesh) or job.mesh
    local e, why = L.expand(m)
    if e then cache.prep[key] = { mesh = e, section = job.mesh.section }
    else cache.prep[key], cache.bad[key] = false, tostring(why) end
end
-- One data step (a level or a mesh); true when it did work this frame
local function data_step()
    if cache.done then return false end
    if not cache.queue then
        cache.queue, cache.qi, cache.t0 = {}, 1, os.clock()
        for _, lv in ipairs(IB.LEVELS) do cache.queue[#cache.queue + 1] = { level = lv } end
    end
    local job = cache.queue[cache.qi]
    if not job then
        cache.done = true
        local n, bad = 0, {}
        for _, e in pairs(cache.prep) do if e then n = n + 1 end end
        for k, w in pairs(cache.bad) do bad[#bad + 1] = k .. ': ' .. w end
        table.sort(bad)
        local levels = {}
        for _, lv in ipairs(IB.LEVELS) do levels[#levels + 1] = lv .. (cache.levels[lv] and '' or ' refused') end
        LAB.rec('cap_iberico_data', { levels = levels, meshes = n, bad = bad[1] and bad or nil,
            ms = math.floor((os.clock() - (cache.t0 or os.clock())) * 1000 + 0.5) }, true)
        return false
    end
    cache.qi = cache.qi + 1
    if job.level then load_level(job.level) else prep_mesh(job) end
    return true
end

-- ---------- the API: pure lookups ----------
-- The family of the cut's body (IB.FITS by the leaf of cut.asset, 'SkeletalMesh /a/b/X.X' -> X); nil when not fitted
function IB.family(cut)
    local a = type(cut) == 'table' and cut.asset or nil
    if type(a) ~= 'string' then return nil end
    return IB.FITS[a:match('([^/.%s]+)$') or '']
end
local function right_of(part) return type(part) == 'string' and part:match('_[rR]$') ~= nil end
function IB.parts(cut, cap, side)
    if not st.init then return nil, 'off' end
    if not textured() then return nil, 'not_textured' end
    local fam = IB.family(cut)
    if not fam then return nil, 'no_fit' end
    local lv = cache.levels[cap]
    if lv == nil then return nil, 'loading' end
    if lv == false then return nil, 'no_data' end
    if lv.family ~= fam then return nil, 'no_fit' end
    local sd = lv.data.sides[side]
    if type(sd) ~= 'table' then return nil, 'no_side' end
    local right = right_of(cut.part)
    if right and lv.data.mirror ~= 'y' then return nil, 'no_mirror' end
    local want = sd.cut
    if right then want = (sd.cut:gsub('_[lL]$', '_r')) end
    if type(cut.bone) == 'string' and cut.bone:lower() ~= want:lower() then return nil, 'bone' end
    local list, secs = {}, {}
    for i, n in ipairs(sd.meshes) do
        local e = cache.prep[n .. (right and '@r' or '')]
        if e == nil then return nil, 'loading' end
        if e == false then return nil, 'no_data' end
        list[i], secs[i] = e.mesh, e.section
    end
    local an = lv.anchors[side]
    return list, secs, right and an.r or an.l
end
function IB.material()
    if not st.init then return nil, 'off' end
    if not textured() then return nil, 'not_textured' end
    local h = st.held
    if not h then return nil, st.why and ('refused: ' .. st.why) or 'pending' end
    local m = ue.live_mod(h.rec)
    if not m then return nil, 'gone' end
    return m, h.look
end
-- The test build's key (lab_testkeys, Ctrl+Shift+F6): the next look; it only flips it and queues a build
function IB.press()
    if not st.init then return 'off', 'lab_iberico is not running (the beta only)' end
    st.look_i = st.look_i % #IB.LOOKS + 1
    st.dirty, st.press_n = true, st.press_n + 1
    local look = IB.LOOKS[st.look_i]
    local note = textured() and 'builds at the next quiet moment after a kill'
        or ('stumps are not Iberico now (cap_look ' .. tostring(C.knob('cap_look')) .. ')')
    return look.key, 'iberico look ' .. look.key .. ' (' .. table.concat(look.parents, ', ') .. '; '
        .. IB.FILES[look.file] .. '): ' .. note
end

-- ---------- gates ----------
-- lab_look's busy(), quiet() and gate(name) over this module's state (one cap_iberico_skip record per name and why), set
-- at init with the listeners
local G = nil

-- ---------- the build (one frame) ----------
function IB.tex_dir()
    local E = ENV.E
    local d = type(E) == 'table' and E.mod_dir or nil
    if type(d) ~= 'string' then return nil end
    return (d:gsub('[\\/]+$', '')) .. '/Textures/'
end
function IB.exists(path)
    local ok, f = pcall(io.open, path, 'rb')
    if not ok or not f then return false end
    pcall(function() f:close() end)
    return true
end
local function read_tex(t)
    local okx, x = ue.call(t, 'Blueprint_GetSizeX')
    local oky, y = ue.call(t, 'Blueprint_GetSizeY')
    return { x = okx and num(x) and x or 'unread', y = oky and num(y) and y or 'unread',
        srgb = or_unread(ue.prop(t, 'SRGB')), compression = or_unread(ue.prop(t, 'CompressionSettings')),
        vt = or_unread(ue.prop(t, 'VirtualTextureStreaming')), filter = or_unread(ue.prop(t, 'Filter')),
        address = { or_unread(ue.prop(t, 'AddressX')), or_unread(ue.prop(t, 'AddressY')) } }
end
-- A MID of parent with tex on param, read back (lab_look's MID calls): { mid, set, same } | { why }
local function make_mid(w, parent, param, tex)
    local mid, why = LOOK.kmat_mid(w, parent)
    if not mid then return { why = why } end
    local r = { mid = mid }
    local err
    r.set, r.same, err = LOOK.tex_param(mid, param, tex)
    if not r.set then r.why = 'set: ' .. err_text(err)
    elseif not r.same then r.why = 'readback' end
    return r
end
local function finish(f, why, t0)
    f.why, st.why = why, why
    f.ms = math.floor((os.clock() - t0) * 1000 + 0.5)
    LAB.rec('cap_iberico_build', f, true)
end
local function build()
    local refused = nil                                 -- the first name refused, with its why
    for _, n in ipairs(IB.NAMES) do
        local g = G.gate(n)
        if g == 'wait' then return end
        if g ~= 'ok' and not refused then refused = n .. ' ' .. g end
    end
    local t0 = os.clock()
    local look = IB.LOOKS[st.look_i] or IB.LOOKS[1]
    local f = { look = look.key, file = IB.FILES[look.file], tried = {} }
    st.dirty, st.built_ep, st.why, st.builds = false, ue.epoch, nil, st.builds + 1
    local old = st.held
    st.held = nil
    if refused then return finish(f, refused, t0) end
    LAB.oneshot()                                       -- a decode, a load and a MID: this frame pays
    if old and old.hold then                            -- the look a press replaced: its slot freed
        local _, err = LAB.armed('cap.keep', function() return ue.release(old.hold) end)
        f.released = err == nil
    end
    local dir = IB.tex_dir()
    local path = dir and (dir .. f.file) or nil
    f.abs = path ~= nil and (path:match('^%a:[\\/]') ~= nil or path:sub(1, 1) == '/')
    if not (path and IB.exists(path)) then return finish(f, 'no_file', t0) end
    local w = ue.world()
    if not w then return finish(f, 'no_world', t0) end
    local r, err = LAB.armed('cap.tex.import', function()
        local krl = ue.cdo('krl')
        if not krl then return { why = 'no_library' } end
        ue.count_write()                                -- a new texture and its render resource
        local ok, t = ue.call(krl, 'ImportFileAsTexture2D', w, path)
        if not ok then return { why = 'import: ' .. err_text(t) } end
        t = ue.p(t)
        if not ue.valid(t) then return { why = 'no_texture' } end
        return { tex = t }
    end)
    if type(r) ~= 'table' then return finish(f, 'import: ' .. err_text(err), t0) end
    if not r.tex then return finish(f, r.why, t0) end
    local tex = r.tex
    local rd
    rd, err = LAB.armed('cap.tex.read', read_tex, tex)
    if type(rd) ~= 'table' then return finish(f, 'read: ' .. err_text(err), t0) end
    f.x, f.y, f.srgb, f.compression, f.vt = rd.x, rd.y, rd.srgb, rd.compression, rd.vt
    f.filter, f.address = rd.filter, rd.address
    if not (num(rd.x) and rd.x > 0 and num(rd.y) and rd.y > 0) then return finish(f, 'empty', t0) end
    local mid, used = nil, nil
    for _, pk in ipairs(look.parents) do
        local p = IB.PARENTS[pk]
        local word
        local parent, lerr = LAB.armed('cap.tex.load', function() return (ue.asset(p.path)) end)
        if not ue.valid(parent) then word = lerr and ('load: ' .. err_text(lerr)) or 'no_parent'
        else
            local m, merr = LAB.armed('cap.tex.mid', make_mid, w, parent, p.param, tex)
            if type(m) ~= 'table' then word = 'mid: ' .. err_text(merr)
            else
                f.set, f.same = m.set, m.same
                if m.mid and m.same then mid, used = m.mid, pk end
                word = m.why
            end
        end
        f.tried[#f.tried + 1] = pk .. ':' .. (word or 'ok')
        if mid then break end
    end
    if not mid then return finish(f, 'no_parent_took', t0) end
    f.parent, f.param = used, IB.PARENTS[used].param
    local h
    h, err = LAB.armed('cap.keep', function()
        local id, why, add = ue.hold((ue.first_of('PlayerController')), mid, 'material')
        if id == nil then return { why = 'hold: ' .. tostring(why) .. (add ~= nil and (' add: ' .. tostring(add)) or '') } end
        return { id = id, rec = ue.keep_mod(mid) }
    end)
    if type(h) ~= 'table' then return finish(f, 'keep: ' .. err_text(err), t0) end
    if not (h.id and h.rec) then return finish(f, h.why or 'keep: no_record', t0) end
    st.held = { rec = h.rec, hold = h.id, look = look.key, parent = used }
    f.held = true
    return finish(f, nil, t0)
end

-- ---------- the ticker: one step a frame ----------
local function tick()
    if not st.init or st.ended then return end
    if LAB.ended() then st.ended = true return end
    if not MODOFF.enabled('lab_iberico') then st.wait = 'off' return end
    if not textured() then st.wait = 'not_textured' return end
    if G.busy() then st.busy = st.busy + 1 return end
    if data_step() then return end                      -- one level or mesh a frame, no engine call
    if st.built_ep == ue.epoch and not st.dirty then st.wait = nil return end
    if LAB.pinned() ~= true then st.wait = 'unpinned' return end
    if LAB.paused() then st.wait = 'paused' return end
    local ok, why = G.quiet()
    st.wait = why
    if ok then build() end
end

-- ---------- lifecycle ----------
function IB.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.beta() then return true end
    st.init = true
    LAB.names(N, F)
    MODOFF.feature('lab_iberico', {})                   -- mod-off pauses the data and the build; held looks stay
    G = LOOK.gates(st, 'lab_iberico', 'cap_iberico_skip')
    S.ticker('lab_iberico', tick)
    return true
end
-- A map load: the hold ended with the old map (ue.reset_caches); the look and the data stay for the session
function IB.reset(reason)
    if not st.init then return end
    if reason == 'map' then st.held, st.built_ep, st.why, st.busy_f = nil, nil, nil, nil end
end
function IB.status()
    local n = 0
    for _, e in pairs(cache.prep) do if e then n = n + 1 end end
    local look = IB.LOOKS[st.look_i]
    return { init = st.init, ended = st.ended, look = look and look.key, held = st.held and st.held.look or nil,
        why = st.why, wait = st.wait, builds = st.builds, busy = st.busy, presses = st.press_n, data_done = cache.done,
        meshes = n, has_adapter = A ~= nil }
end
function IB.shutdown()
    S.remove_ticker('lab_iberico')
    for _, ev in ipairs(LOOK.GATE_EVENTS) do BUS.off(ev, 'lab_iberico') end
    st, A, G, cache = new_state(), nil, nil, new_cache()
end
return IB
