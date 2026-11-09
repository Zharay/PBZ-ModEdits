-- status: new in M0 S2.10 (offline only; TC-LAB-01 stage 0 decides) origin: kb:testing-lab-playtest#engine-name-tables-plus-a-name-lint-against-the-dump
-- lab_l0i.lua: TC-LAB-01 stage 0 L0i-lite, S-KEYS, S-STATE and S-SPAWN-a (spec M0 S2.10, D8, D9, D12; sections 3.1,
-- 3.3, 3.4). Probe and dev builds (META.lab_modules, after lab_probe), and the player beta (META.beta_modules,
-- LAB.beta(): the pawn, the fallback and L0i-lite only; no lab key bound at init, no S-STATE, no S-SPAWN-a; in the
-- author's test build, META.beta_spawn, lab_spawn's handlers bind the spawn keys alone, M.on_press). Records: l0i, key,
-- state_probe, spawn_probe.
-- * L0i-lite (G2): on the first lab_pawn of the session (bus, section 3.3; the listener only queues), on the next
--   unpaused lab tick: pc = pawn.Controller and mesh = pawn.Mesh (property reads, props:5590, :5597), then step 1
--   pc:IsPlayerController() (declared on /Script/Engine.Controller, so:13970) under LAB.armed('lab.inherit.ipc') and
--   step 2 mesh:GetNumBones() (declared on SkinnedMeshComponent, so:20818) under LAB.armed('lab.inherit.bones'): both
--   inherited lookups, always-armed (2 sentinel writes each). One l0i record: returned (the steps that returned, 0-2),
--   num_bones and ipc ('unread' when not read), arraynum, ms, route 'chain', via, err. An 'ArrayNum exceeds ArrayMax'
--   text from step 1 stops inherited calls for the session (lab_probe, D9): step 2 and every later 'lab.inherit.*' call
--   are refused ('inherit_off'); the hooks keep counting. A queued pawn that is no longer live, or that has no body, is
--   dropped without a record (the fallback resumes), so neither spends the session's one L0i-lite run; S-SPAWN-a reads
--   the controller of the pawn L0i-lite accepted. No body: the built-in IsA against /Script/Engine.Character (M.CHARACTER,
--   resolved by ue.class on this ticker, never in a hook) answers false, so Mesh is never read on a menu, spectator or
--   default pawn (a member miss there walks GetFunctionByNameInChain), or Mesh does not read (an IsA that cannot answer
--   reads Mesh). A pawn dropped once is never read again on this map (the fallback no longer re-emits it); each drop
--   counts in status().no_mesh and LAB.count('l0i_no_mesh') (the status record's counters). When L0i-lite returned 2
--   of 2, LAB.set_l0i_ok(true) (lab_probe's LAB.l0i_ok: lab_kill gates its payload member reads on it).
-- * Fallback (V2-6, section 3.4): after a map load with no lab_pawn yet, FALLBACK_WAIT_S later and then at most once per
--   FALLBACK_S (LAB.due: never while paused), ue.first_of('PlayerController') (FindFirstOf, cached and rate-limited by the
--   bridge too) and its Pawn property (props:5641); a pawn found emits lab_pawn { pawn = ue.keep record, key, t, via
--   'findfirst' } for every lab module. Any lab_pawn after the map load ends the fallback until the next map load; none
--   runs before the first map load, and none per frame.
-- * S-KEYS (G13, D12): META.lab_keys bound through adapter/keys.lua (collision from IsKeyBindRegistered, asked before our
--   bind: it cannot see a bind another mod registers later); each press (game thread: the tick drains keys.lua) writes one key
--   record { action, key, collision, via } and emits bus lab_key(action) (spec M1a D19, A1.2: every press, lab_end's
--   included; listeners only queue); the first lab_end press also emits bus lab_end (lab_probe's final flush, lab_rc's
--   inventory). Later lab_end presses write their key record and lab_key only. lab_spawn (the dev build and the beta
--   test build) adds a press handler for each spawn target (M.on_press, D32): it runs after the key record, and an
--   action with no bind yet (a target past M.KEY_ORDER; in the beta every target) is bound then, from META.lab_keys.
--   lab_3 (Ctrl+F2, M1a D15: GCAP-a in lab02) is bound after the three M0 keys; in the probe and the spawn set its
--   press writes the key record only.
-- * S-STATE (G14, PLAN P5): once, on the first lab tick (a one-shot frame): E.state .. 'probe.a.json' written, renamed to
--   'probe.b.json' when A.fs.rename exists (the old .b removed first: a Windows rename refuses an existing target) and
--   read back; then the install save folder (<steamapps/common/<game>>/<saved_subdir>/Saved/SaveGames and its Steam
--   folder) is probed by name for every file the mod writes at its state prefix (Lua io cannot list a folder), and the
--   written file counts too when the state prefix itself lies under a SaveGames folder. state_probe { readback,
--   savegames_files, prefix (the %LOCALAPPDATA% part as a token: no user name in a shared log), renamed, fallback
--   (E.state is the mod folder: env.lua's own fallback without saved_subdir or LOCALAPPDATA), why }. The probe never
--   writes anywhere else; probe.b.json stays as the evidence the card lists.
-- * S-SPAWN-a (G15): once, on the lab tick after L0i-lite: cm_class = the class of pc.CheatManager (props:5660; 'absent'
--   when it holds nothing, as without CheatManagerEnablerMod; 'unread' without a live pc), summon_found =
--   StaticFindObject('/Script/Engine.CheatManager:Summon') through ue.find (so:13763), and only while LAB.inherit_ok()
--   the instance lookup cm.Summon under LAB.armed('lab.inherit.summon') (on_instance 'true' | 'false' | 'skipped').
--   Summon is never called. The lookup goes through ue.get, which answers nil on a raise and hands the text to
--   ue.on_error: an ArrayNum text there reaches lab_probe's stop rule (source 'swallowed', where 'lab.inherit.summon'),
--   and the record reads on_instance 'false' with that text in err.
-- * Names: N (the two inherited calls) and F (the four property reads) go to NAMES through LAB.names in init (D28);
--   the Summon path is the calls entry cheat_summon of data/hooks.lua, never a name. Engine access only through
--   adapter/ue.lua.
-- API: init(A, opts) shutdown(reason) status() reset(reason); M.saves_dir(E, meta); M.on_press(action, fn).
-- What the mock cannot prove: the real marshalling of the two inherited calls, whether the ArrayNum check throws or only
-- logs, the real key codes and binds of other mods, Windows rename semantics, the save folder layout of another install.
local META = require('meta')
local BUS = require('core.bus')
local S = require('core.sched')
local STORE = require('core.store')
local KEYS = require('adapter.keys')
local ue = require('adapter.ue')
local LAB = require('lab_probe')
local HDATA = require('data.hooks')

local M = { FALLBACK_WAIT_S = 5, FALLBACK_S = 5, ERR_CHARS = 200, CHARACTER = '/Script/Engine.Character' }
-- Summon is a path lookup, never a call: declared once, in the calls section of data/hooks.lua (data/hooks.json), so
-- session_pbz measures it in calls_total and calls_missing (D28: a calls miss is never a G1 names miss)
M.SUMMON = type(HDATA.calls) == 'table' and HDATA.calls.cheat_summon or '/Script/Engine.CheatManager:Summon'
M.KEY_ORDER = { 'lab_1', 'lab_2', 'lab_end', 'lab_3' }   -- lab_3 last (M1a A1.2): the M0 binds keep their order
-- The files the mod writes at its state prefix: settings A/B (core/config.lua), the arm markers (adapter/arm.lua through
-- STORE.write_atomic: tmp, bak) and this probe's own pair
M.STATE_FILES = { 'settings.a.json', 'settings.b.json', 'arm.json', 'arm.json.tmp', 'arm.json.bak', 'probe.a.json',
    'probe.b.json' }

local N = {
    l0i_is_player_controller = {"/Script/Engine.Controller", "IsPlayerController()"},
    l0i_get_num_bones = {"/Script/Engine.SkinnedMeshComponent", "GetNumBones()"},
}
local F = {
    {"/Script/Engine.Pawn", "Controller"},
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.Controller", "Pawn"},
    {"/Script/Engine.PlayerController", "CheatManager"},
}
M.N, M.F = N, F                                         -- read-only, for the env count checks (as session_pbz's SP.N)

local A = nil
local function new_state()
    return { alive = false, labels = {}, coll = {}, bound = {}, presses = 0, ended = false, state_done = false,
        pawn_q = nil, l0i = nil, pc = nil, spawn_due = false, spawned = false, summon_ran = false, after_map = false,
        map_pawn = false, fallback_at = 0, first_asks = 0, emitted = 0, no_mesh = 0, no_mesh_keys = {}, press_fn = {},
        lite = false }
end
local st = new_state()

local function now() return A and A.clock and A.clock.real() or 0 end
local function text200(s)
    s = tostring(s)
    return #s > M.ERR_CHARS and s:sub(1, M.ERR_CHARS) or s
end

-- ---------- S-KEYS ----------
local MOD_LABEL = { CONTROL = 'Ctrl', SHIFT = 'Shift', ALT = 'Alt' }
local function label(b)
    if type(b) ~= 'table' then return 'unread' end
    local parts = {}
    for _, m in ipairs(b.mods or {}) do parts[#parts + 1] = MOD_LABEL[m] or tostring(m) end
    parts[#parts + 1] = tostring(b.key)
    return table.concat(parts, '+')
end
-- A press, on the game thread (the tick drains keys.lua): one key record and bus lab_key(action); the first lab_end press emits
-- lab_end; then the press handler of that action, when a dev-only module added one (M.on_press)
local function on_key(action, via)
    if not st.alive then return end
    st.presses = st.presses + 1
    LAB.rec('key', { action = action, key = st.labels[action], collision = st.coll[action], via = via or 'key' })
    BUS.emit('lab_key', action)
    if action == 'lab_end' and not st.ended then
        st.ended = true
        BUS.emit('lab_end')
    end
    local fn = st.press_fn[action]
    if fn then fn(action, via or 'key') end
end
-- One action's bind from keys (META.lab_keys), once: st.bound reads true or false after it, nil before
local function bind_one(action, keys)
    local b = type(keys) == 'table' and keys[action] or nil
    st.labels[action] = label(b)
    local ok, collision = KEYS.bind(action, b, function(via) on_key(action, via) end)
    st.bound[action], st.coll[action] = ok == true, collision
end
local function bind_keys(keys)
    for _, action in ipairs(M.KEY_ORDER) do bind_one(action, keys) end
end
-- The spawn keys (lab_spawn, spec M0 D32; the dev build and the beta test build): fn(action, via) runs on the game
-- thread right after that key's record, on the bind made here (one bind per key, its collision check kept); fn nil
-- removes it. An action with no bind yet is bound at its first handler, from META.lab_keys: a target past
-- M.KEY_ORDER, and in the beta (no lab key bound at init) every target, so its spawn keys are the only lab keys there.
-- The probe adds none, so there a lab key writes its key record and nothing else. Cleared at init and shutdown.
function M.on_press(action, fn)
    if type(action) ~= 'string' then return false end
    st.press_fn[action] = type(fn) == 'function' and fn or nil
    if st.press_fn[action] and st.alive and st.bound[action] == nil then
        bind_one(action, ((A and A.meta) or META).lab_keys)
    end
    return true
end

-- ---------- lab_pawn: the listener only queues (a ue.keep record), the tick runs L0i-lite ----------
-- rec.pawn: a ue.keep record (lab_kill's post, this fallback), a registry record with .keep, or the object itself
local function keep_of(x)
    if type(x) == 'table' and rawget(x, '__mock') == nil then
        if x.keep ~= nil then x = x.keep end
        if type(x) == 'table' and x.obj ~= nil then return x end
        return nil
    end
    return ue.keep(x)
end
local function on_pawn(rec)
    local kp = type(rec) == 'table' and keep_of(rec.pawn) or nil
    if not kp then return end
    st.map_pawn = true                                  -- any lab_pawn ends this map's fallback
    if st.l0i or st.pawn_q then return end
    st.pawn_q = { keep = kp, via = rec.via == 'findfirst' and 'findfirst' or 'lab_pawn' }
end

-- ---------- L0i-lite ----------
-- One inherited call through the bridge; a failure raises its text, so LAB.armed sees an ArrayNum error (D9)
local function step_call(o, fn)
    local ok, v = ue.call(o, fn)
    if not ok then error(v, 0) end
    return v
end
-- mesh: the pawn's Mesh, read by the tick (a pawn without one never gets here)
local function run_l0i(q, pawn, mesh)
    local t0 = now()
    local r = { returned = 0, num_bones = 'unread', ipc = 'unread', arraynum = false, route = 'chain', via = q.via }
    local errs = {}
    local function step(name, o, fn, miss)
        if not o then errs[#errs + 1] = miss return nil end
        local v, err = LAB.armed(name, step_call, o, fn)
        if err ~= nil then errs[#errs + 1] = tostring(err) return nil end
        r.returned = r.returned + 1
        return v
    end
    local pc = ue.prop(pawn, 'Controller')
    local ipc = step('lab.inherit.ipc', pc, 'IsPlayerController', 'no_controller')
    if type(ipc) == 'boolean' then r.ipc = ipc end
    local nb = step('lab.inherit.bones', mesh, 'GetNumBones', 'no_mesh')
    if type(nb) == 'number' then r.num_bones = math.tointeger(nb) or nb end
    for _, e in ipairs(errs) do if e:find(LAB.ARRAYNUM, 1, true) then r.arraynum = true end end
    r.err = errs[1] and text200(errs[1]) or nil
    r.ms = math.floor((now() - t0) * 1e6 + 0.5) / 1000
    st.l0i, st.pc, st.spawn_due = r, pc and ue.keep(pc) or nil, true
    if r.returned == 2 then LAB.set_l0i_ok(true) end   -- L0i-lite proven: the shared contract (lab_probe)
    LAB.rec('l0i', r)
end

-- ---------- no body: never read twice on a map ----------
local function key_of(o) return string.format('%s|%s|%d', tostring(ue.addr(o)), ue.full(o) or 'unread', ue.epoch) end
-- The pawn's Mesh, read only on a Character (header); nil without a read for a pawn already dropped on this map or one
-- the built-in IsA calls no Character
local function body_of(pawn, key)
    if st.no_mesh_keys[key] or ue.is_a(pawn, M.CHARACTER) == false then return nil end
    return ue.prop(pawn, 'Mesh')
end
local function drop_no_mesh(key)
    st.no_mesh_keys[key], st.no_mesh, st.map_pawn = true, st.no_mesh + 1, false
    LAB.count('l0i_no_mesh')
end

-- ---------- the FindFirstOf fallback: after a map load, no lab_pawn yet, at most once per FALLBACK_S ----------
local function fallback()
    if not st.after_map or st.map_pawn or now() < st.fallback_at then return end
    if not LAB.due('lab_l0i.findfirst', M.FALLBACK_S) then return end
    st.first_asks = st.first_asks + 1
    local pc = ue.first_of('PlayerController')
    local pawn = pc and ue.prop(pc, 'Pawn') or nil
    if not ue.valid(pawn) then return end
    local key = key_of(pawn)
    if st.no_mesh_keys[key] then return end             -- dropped on this map already: not re-emitted every FALLBACK_S
    st.emitted = st.emitted + 1
    BUS.emit('lab_pawn', { pawn = ue.keep(pawn), key = key, t = now(), via = 'findfirst' })
end

-- ---------- S-SPAWN-a: the CheatManager's class and Summon, never called ----------
local function class_of(o)
    local full = ue.full(o)
    return full and full:match('^(%S+) ') or 'unread'
end
local function summon_lookup(cm)
    st.summon_ran = true                                -- a refusal (disabled, not armed, no arm write) never gets here
    local f = ue.get(cm, 'Summon')
    return f ~= nil and (type(f) == 'function' or ue.valid(f))
end
local function spawn_probe()
    st.spawned = true
    local r = { cm_class = 'unread', summon_found = ue.find(M.SUMMON) ~= nil, on_instance = 'skipped' }
    local pc = st.pc and ue.live(st.pc) or nil
    local cm = pc and ue.prop(pc, 'CheatManager') or nil
    if not pc then
        r.why = 'no_controller'
    elseif not cm then
        r.cm_class = 'absent'
    else
        r.cm_class = class_of(cm)
        if not LAB.inherit_ok() then
            r.why = 'inherit_off'
        else
            local v, err = LAB.armed('lab.inherit.summon', summon_lookup, cm)
            if err == nil then
                r.on_instance = v == true and 'true' or 'false'
            else
                r.err = text200(err)                    -- raised in the lookup: 'false'; refused before it: 'skipped'
                if st.summon_ran then r.on_instance = 'false' end
            end
        end
    end
    LAB.rec('spawn_probe', r)
end

-- ---------- S-STATE: written, renamed and read back at the state prefix; nothing of ours under SaveGames ----------
local function norm(p) return (tostring(p):gsub('\\', '/')) end
-- The game's save folder of a Steam install: <steamapps/common/<game>>/<saved_subdir>/Saved/SaveGames (PBZ:
-- G/ProjectPBZ/Saved/SaveGames, the saves under Steam/<id>); nil when the mod folder is not under steamapps/common or
-- saved_subdir is not set
function M.saves_dir(E, meta)
    local d = type(E) == 'table' and E.mod_dir or nil
    local root = d and norm(d):match('^(.-/[Ss]teamapps/[Cc]ommon/[^/]+)/') or nil
    local sub = type(meta) == 'table' and meta.saved_subdir or nil
    if not root or type(sub) ~= 'string' then return nil end
    return root .. '/' .. sub .. '/Saved/SaveGames'
end
-- The prefix for a log players may share: env.lua builds E.state as <LOCALAPPDATA>/<saved_subdir>/Saved/<MOD>_, so the
-- part before '/<saved_subdir>/Saved/' becomes '%LOCALAPPDATA%'; the mod-folder fallback reads '<mod folder>/'
local function prefix_label(state, meta, fallback)
    local p = norm(state)
    local tail = p:match('([^/]*)$') or ''
    if fallback then return '<mod folder>/' .. tail end
    local sub = type(meta) == 'table' and meta.saved_subdir or nil
    local i = type(sub) == 'string' and p:find('/' .. sub .. '/Saved/', 1, true) or nil
    if i then return '%LOCALAPPDATA%' .. p:sub(i) end
    return tail
end
local function exists(fs, path)
    local ok, s = pcall(fs.read, path)
    return ok and s ~= nil
end
-- Our files under SaveGames: each state file name probed in the save folder and its Steam folder, and the probe's own
-- file when the state prefix itself lies under a SaveGames folder; each path counted once
local function savegames_files(fs, E, meta, written)
    local seen, n = {}, 0
    local function count(path)
        local k = norm(path):lower()
        if not seen[k] then seen[k], n = true, n + 1 end
    end
    if written and norm(E.state):lower():find('/savegames/', 1, true) then count(written) end
    local saves, name = M.saves_dir(E, meta), norm(E.state):match('([^/]*)$') or ''
    if saves then
        for _, dir in ipairs({ saves, saves .. '/Steam' }) do
            for _, f in ipairs(M.STATE_FILES) do
                if exists(fs, dir .. '/' .. name .. f) then count(dir .. '/' .. name .. f) end
            end
        end
    end
    return n
end
local function done(okc, r) return okc and r ~= nil and r ~= false end
-- why: the first of write_failed, readback_mismatch, rename_failed, the fallback reason, no_rename; else 'ok'
local function state_probe()
    local E, meta, fs = A and A.env, (A and A.meta) or META, A and A.fs
    local r = { readback = false, savegames_files = 0, prefix = 'unread', renamed = false, fallback = false, why = 'ok' }
    if type(E) ~= 'table' or type(E.state) ~= 'string' or E.state == '' or type(fs) ~= 'table' or not fs.write
        or not fs.read then
        r.why = 'no_state'
        LAB.rec('state_probe', r)
        return
    end
    r.fallback = E.state == E.data
    r.prefix = prefix_label(E.state, meta, r.fallback)
    local a, b = E.state .. 'probe.a.json', E.state .. 'probe.b.json'
    local text = STORE.encode({ probe = 'S-STATE', t = A.clock and A.clock.wall and A.clock.wall() or 0,
        token = A.proc_token and A.proc_token() or 'none' })
    local why, at = {}, nil
    local okw, w, werr = pcall(fs.write, a, text)
    if not done(okw, w) then
        why[1] = 'write_failed: ' .. text200(okw and werr or w)
    else
        at = a
        if fs.rename then
            if fs.remove then pcall(fs.remove, b) end   -- a Windows rename refuses an existing target
            local okr, rr, rerr = pcall(fs.rename, a, b)
            r.renamed = done(okr, rr)
            if r.renamed then at = b else why[3] = 'rename_failed: ' .. text200(okr and rerr or rr) end
        else
            why[5] = 'no_rename'
        end
        local okb, back = pcall(fs.read, at)
        r.readback = okb and back == text
        if not r.readback then why[2] = 'readback_mismatch' end
    end
    if r.fallback then why[4] = (type(meta) == 'table' and meta.saved_subdir) and 'no_localappdata' or 'no_saved_subdir' end
    r.savegames_files = savegames_files(fs, E, meta, at)
    for i = 1, 5 do if why[i] then r.why = why[i] break end end
    LAB.rec('state_probe', r)
end

-- ---------- the lab tick: one piece of work per frame ----------
local function tick()
    if not st.state_done and not st.lite then
        st.state_done = true
        LAB.oneshot()
        state_probe()
        return
    end
    if LAB.paused() then return end                     -- a pause, menu or load screen: no engine read
    if st.pawn_q then
        local q = st.pawn_q
        st.pawn_q = nil
        local pawn = ue.live(q.keep)
        if not pawn then st.map_pawn = false return end -- gone, reused or stale: wait for the next lab_pawn
        local key = key_of(pawn)
        local mesh = body_of(pawn, key)
        if not mesh then                                -- no body (a menu, spectator or default pawn): not Soul's,
            drop_no_mesh(key)                           -- the run waits for the next lab_pawn or the fallback
            return
        end
        LAB.oneshot()
        run_l0i(q, pawn, mesh)
    elseif st.spawn_due and not st.spawned and not st.lite then
        LAB.oneshot()
        spawn_probe()
    else
        fallback()
    end
end

-- ---------- lifecycle ----------
-- A: the main.lua feature view (MAIN.A, then MAIN: clock, fs, env, meta, count, gauge, oneshot ...)
function M.init(adapter)
    A = adapter
    st = new_state()
    st.alive = true
    LAB.names(N, F)
    st.lite = LAB.beta()                                -- the beta (beta port S1): L0i-lite only, no lab key
    if not st.lite then bind_keys(((A and A.meta) or META).lab_keys) end
    BUS.on('lab_pawn', 'lab_l0i', on_pawn)
    S.ticker('lab_l0i', tick)
    return true
end
-- A map load: the queued pawn belongs to the old map; the fallback waits FALLBACK_WAIT_S for this map's lab_pawn. L0i,
-- the probes and the lab_end latch stay done for the session
function M.reset(reason)
    if reason ~= 'map' then return end
    st.pawn_q, st.after_map, st.map_pawn, st.no_mesh_keys = nil, true, false, {}
    st.fallback_at = now() + M.FALLBACK_WAIT_S
end
function M.status()
    return { keys = st.bound, presses = st.presses, ended = st.ended, l0i = st.l0i and st.l0i.returned or nil,
        state = st.state_done, spawn = st.spawned, fallback_asks = st.first_asks, fallback_pawns = st.emitted,
        fallback_on = st.after_map and not st.map_pawn, no_mesh = st.no_mesh }
end
function M.shutdown()
    S.remove_ticker('lab_l0i')
    BUS.off('lab_pawn', 'lab_l0i')
    st, A = new_state(), nil
end

return M
