-- status: worked DD2 origin: kb:testing-lab-playtest#file-drop-json-dev-channel-cmd-json-in-answer-record-in-the-jsonl-log
-- dev.lua: the file-drop dev channel. The agent (tools/lab/send_cmd.ps1) writes <dir>cmd.json { id, cmd, ... }; the
-- mod runs each new id once in its late phase and answers with one record ev 'cmd' { cmd_id, cmd, ok, result, err,
-- src, before, after } in the current JSONL slot.
-- Rules (each from a real failure):
-- * Active only while the marker <dir>dev.json parses as a table. This module reads the marker and never writes it
--   (consent goes through the plugin hook, not a file the model can write). No marker at init = a release install:
--   zero cmd.json reads, no poll, no commands kept, D.run answers dev_off, D.status is nil. A release install that kept
--   probing paid an armed.json write per cut for a feature no player had asked for.
-- * The marker is checked again every opts.marker_s (2 s) while active; when it is gone the channel goes off for the
--   rest of the Lua state and the runtime-only setting overrides are cleared. A new marker needs a script reset.
-- * cmd.json is read raw every opts.poll_s (0.25 s), never through a loader json call that logs each read. The id
--   already in the file at init is remembered, so a reset does not run it again; ids seen are never run twice.
-- * World commands (spec.world) need a family and a radius (max_dist, or radius): a kill without a family once hit a
--   quest NPC 31 m away. spec.radius_max defaults to 3 m, hard cap D.RADIUS_CAP 6 m. Each world run is its own sentinel
--   'dev:<cmd>' with a linger (spec.linger_s, 3 s), and spec.read(c) gives the before/after readbacks of the answer.
-- * Commands run as late jobs on the game thread (a paused game answers after it is unpaused). D.run(c) is the
--   settings window's path: queued the same way, never run inside a UI draw.
-- * A dev 'set' is a runtime-only override (config C.override), never saved: a persisted dev set overrode every
--   preset in later sessions.
-- Built-in commands: status, mark { text }, set { path, value }, clear (the overrides), cmds.
-- API (stable): D.init(A, opts) command(name, fn, spec) run(c) tick([now]) status shutdown handoff reset.
--   fn(c) -> result | nil, err (a world fn must raise when its inner writes failed). The poll is a sched ticker
--   'dev_poll' (opts.ticker = false: the adapter calls D.tick from its own frame callback instead).
-- Evidence: [worked DD2] dev.lua run_cmd/D.run/poll/init, tools/send-cmd.ps1;
-- kb:runtime-safety-perf#safe-dev-lab-world-commands; kb:testing-lab-playtest principle 30
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local STORE = require(BASE .. 'store')
local LOG = require(BASE .. 'log')
local SENT = require(BASE .. 'sentinel')
local S = require(BASE .. 'sched')
local C = require(BASE .. 'config')

local D = { active = false, RADIUS_CAP = 6, RADIUS_MAX = 3, LINGER_S = 3, SEEN_MAX = 64 }

local A, fs, cfg = nil, nil, nil
local COMMANDS, order = {}, {}
local last_id, seen, seen_n = nil, {}, 0
local next_poll, next_marker, ui_seq = 0, 0, 0
local stats = { runs = 0, refused = 0, pending = 0 }

local function real() return A.clock.real() end

local function remember(id)
    if seen[id] then return end
    seen[id], seen_n = true, seen_n + 1
    if seen_n > D.SEEN_MAX then seen, seen_n = { [id] = true }, 1 end
end

-- One answer record per command; D.last for the settings window's dev panel
local function answer(c, ok, result, err, before, after)
    if type(result) == 'userdata' or type(result) == 'function' then result = true end
    local rec = { cmd_id = tostring(c.id), cmd = tostring(c.cmd), ok = ok == true, result = result,
        err = err ~= nil and tostring(err) or nil, src = c.src or 'dev', before = before, after = after }
    LOG.info('cmd', rec)
    if c.src == 'ui' then stats.pending = math.max(0, stats.pending - 1) end
    if not ok then stats.refused = stats.refused + 1 end
    D.last = { id = rec.cmd_id, cmd = rec.cmd, ok = rec.ok, err = rec.err, t = real() }
    return rec
end

local function readback(sp, c)
    if type(sp.read) ~= 'function' then return nil end
    local ok, r = pcall(sp.read, c)
    if ok then return r end
    return { read_error = tostring(r) }
end

-- The refusal a world command gets before anything runs, or nil
local function world_refusal(sp, c)
    if type(c.family) ~= 'string' or c.family == '' then return 'need_family' end
    local r = tonumber(c.max_dist)
    if r == nil then r = tonumber(c.radius) end
    if r == nil or r ~= r or r <= 0 then return 'need_radius' end
    if r > sp.radius_max then return 'radius_over' end
    return nil
end

local function run_cmd(c)
    local e = COMMANDS[c.cmd]
    if not e then return answer(c, false, nil, 'unknown_command') end
    local sp = e.spec
    if sp.world then
        local why = world_refusal(sp, c)
        if why then return answer(c, false, nil, why) end
    end
    stats.runs = stats.runs + 1
    local before = readback(sp, c)
    local r, err
    if sp.world then
        local name = 'dev:' .. c.cmd
        local packed, serr = SENT.sentinel(name, function() return table.pack(e.fn(c)) end)
        SENT.linger(name, sp.linger_s)
        if packed then r, err = packed[1], packed[2] else err = serr end
    else
        local ok, r1, e1 = pcall(e.fn, c)
        if ok then r, err = r1, e1 else err = tostring(r1) end
    end
    local after = readback(sp, c)
    local good = err == nil and r ~= nil and r ~= false
    if not good and err == nil then err = 'no_result' end
    return answer(c, good, r, err, before, after)
end

-- Register a command (lab modules call this from their own init). Inactive channel: nothing is kept, false, dev_off.
-- spec: world (acts on the world: family + radius, sentinel + linger), radius_max (3, at most 6), linger_s (3),
-- read(c) -> the readback logged before and after
function D.command(name, fn, spec)
    if not D.active then return false, 'dev_off' end
    if type(name) ~= 'string' or type(fn) ~= 'function' then return false, 'bad_args' end
    spec = spec or {}
    local rmax = tonumber(spec.radius_max) or D.RADIUS_MAX
    if rmax > D.RADIUS_CAP then rmax = D.RADIUS_CAP end
    if not COMMANDS[name] then order[#order + 1] = name end
    COMMANDS[name] = { fn = fn, spec = { world = spec.world == true, radius_max = rmax,
        linger_s = tonumber(spec.linger_s) or D.LINGER_S, read = spec.read } }
    return true
end

-- The settings window's dev buttons: queued for the next late phase through the same path as cmd.json
function D.run(c)
    if not D.active then return false, 'dev_off' end
    if type(c) ~= 'table' or not COMMANDS[c.cmd] then return false, 'unknown_command' end
    ui_seq = ui_seq + 1
    c.id, c.src = 'ui-' .. ui_seq, 'ui'
    stats.pending = stats.pending + 1
    S.late('dev_cmd', run_cmd, c)
    return true
end

local function builtins()
    D.command('status', function()
        local rec = LOG.status_record('cmd')
        return { frame = rec.frame, counts = rec.counts, overrides = C.overrides() }
    end)
    D.command('mark', function(c)
        LOG.info('mark', { text = tostring(c.text or ''), src = 'dev' })
        return true
    end)
    D.command('set', function(c)
        if c.path == nil then return nil, 'need_path' end
        local ok, why = C.override(c.path, c.value)
        if not ok then return nil, why end
        return { path = c.path, value = c.value, persisted = false }
    end)
    D.command('clear', function() return { cleared = C.clear_overrides() } end)
    D.command('cmds', function()
        local out = {}
        for i, n in ipairs(order) do out[i] = n end
        return out
    end)
end

-- Off for the rest of this Lua state (the marker went away, or unload). At an unload the overrides are left to
-- C.shutdown, which drops them without running listeners: UE4SS runs OnUnload off the game thread.
local function go_off(why, unload)
    if not D.active then return end
    D.active = false
    S.remove_ticker('dev_poll')
    COMMANDS, order = {}, {}
    local n = 0
    if not unload then n = C.clear_overrides() end
    LOG.info('dev_channel', { on = false, why = why, overrides_cleared = n })
end

-- The poll: the marker every marker_s, cmd.json every poll_s, each new id queued once as a late job
function D.tick(now)
    if not D.active then return end
    now = now or real()
    if now >= next_marker then
        next_marker = now + cfg.marker_s
        if type(STORE.read_json(fs, cfg.marker)) ~= 'table' then return go_off('marker_gone') end
    end
    if now < next_poll then return end
    next_poll = now + cfg.poll_s
    local c = STORE.read_json(fs, cfg.cmd)
    if type(c) ~= 'table' or c.id == nil or c.id == last_id or seen[c.id] then return end
    last_id = c.id
    remember(c.id)
    if type(c.cmd) ~= 'string' then
        answer(c, false, nil, 'bad_command')
        return
    end
    c.src = c.src or 'dev'
    S.late('dev_cmd', run_cmd, c)
end

-- opts: dir ('Mod/', with the slash), marker 'dev.json', cmd 'cmd.json', poll_s 0.25, marker_s 2, ticker (false: the
-- adapter calls D.tick), last_id (a hand-off's id)
function D.init(adapter, opts)
    opts = opts or {}
    A, fs = adapter, adapter.fs
    local dir = opts.dir or ''
    cfg = { marker = dir .. (opts.marker or 'dev.json'), cmd = dir .. (opts.cmd or 'cmd.json'),
        poll_s = opts.poll_s or 0.25, marker_s = opts.marker_s or 2 }
    COMMANDS, order, seen, seen_n, ui_seq = {}, {}, {}, 0, 0
    stats = { runs = 0, refused = 0, pending = 0 }
    last_id, D.last = nil, nil
    D.active = type(STORE.read_json(fs, cfg.marker)) == 'table'
    if not D.active then return true end                 -- release: nothing else, ever, in this Lua state
    local c = STORE.read_json(fs, cfg.cmd)
    if type(c) == 'table' and c.id ~= nil then last_id = c.id end   -- a command from before a reset is not run again
    if opts.last_id ~= nil then last_id = opts.last_id end
    if last_id ~= nil then remember(last_id) end
    local t = real()
    next_poll, next_marker = t, t + cfg.marker_s
    builtins()
    if opts.ticker ~= false then S.ticker('dev_poll', function() D.tick() end) end
    LOG.info('dev_channel', { on = true, marker = cfg.marker })
    return true
end

function D.status()
    if not D.active then return nil end
    return { commands = #order, last_id = last_id, runs = stats.runs, refused = stats.refused, pending = stats.pending }
end

-- A map change: the queued commands go with sched's epoch; the channel stays
function D.reset() end

function D.shutdown(reason) go_off(reason or 'shutdown', true) end

function D.handoff() return { last_id = last_id } end

return D
