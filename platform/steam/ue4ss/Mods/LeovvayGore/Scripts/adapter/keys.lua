-- status: worked SWZC origin: kb:runtime-safety-perf#whole-mod-off-toggle
-- keys.lua: key binds from META.keys ({ action = { key = 'F8', mods = { 'CONTROL' } } }). RegisterKeyBind callbacks run
-- on UE4SS's event-loop thread, so a callback is VM-only (spec M1a 4.2 item 1): it adds one to a counter on an existing
-- table and nothing else: no UE4SS API, no C call, no allocation, no LOG, no pcall, no ExecuteInGameThread. The old hop
-- (ExecuteInGameThread per press) did lua_xmove and luaL_ref onto the mod's hook_lua stack from that thread while the
-- game thread was inside one of UE4SS's C metamethods on the same stack (an __index read of Level.WorldSettings): the
-- UE4SS Lua lock is taken per API call, not per metamethod, so a push between lua_pushvalue and lua_rawget made rawget
-- take a string for the table and crashed at UE4SS.dll+0xC8B000 (crash triage wf_586cb604-b4f, verdict loader).
-- K.drain() runs on the game thread, once per frame from the tick (main.lua on_frame): for each action it reads the
-- counter once, runs the handler for the presses since the last drain, at most MAX_PER_FRAME times, and counts the
-- rest (K.stats().dropped). A handler error is one LOG.warn('key_error'), via is 'key' on this path.
-- K.invoke(action, via) is the console twin: it already runs on the game thread, so it calls the handler directly.
-- A bind that fails (an unknown key name, a modifier bind this build refuses) logs one key_fail and stays reachable
-- from the console ('key' is the lab's key press record).
-- Collision: IsKeyBindRegistered(key, mods) runs right before our RegisterKeyBind; true means a bind on that key with
-- the exact same modifier set already exists, and both callbacks fire on a press (Handler.cpp:32, :89-105). It sees only
-- binds registered before ours: a mod that binds later is invisible to it. We bind anyway; the caller reads collision
-- (true, false, or 'unread' when the function is missing or raised).
-- API: init(opts) bind(action, binding, fn) -> ok, collision; drain() -> n ran; invoke(action, via); label(action)
--   table() status() stats() reset shutdown
-- Evidence: [worked SWZC] lib/keys.lua; engine note 'UE5 / UE4SS 527a483b' (RegisterKeyBind runs off the game thread);
-- UE4SS cdbc0b66 LuaMod.cpp:1451-1511 and Handler.cpp:89-105 (IsKeyBindRegistered, exact modifier set) [verified];
-- LuaMod.cpp:1654 (the callback runs under m_thread_actions_mutex on the mod's main Lua state) and :4369-4375
-- (ExecuteInGameThread: lua_xmove + luaL_ref onto hook_lua) [verified]
local LOG = require('core.log')

local K = {}
K.MAX_PER_FRAME = 4                         -- handler calls per key per frame; the rest of a burst is counted
local bound, handlers, slots, alive = {}, {}, {}, true
local st = { presses = 0, ran = 0, dropped = 0, errors = 0 }

-- fn(via) under pcall, on the game thread (drain and invoke); a raise is one key_error record
local function run(action, fn, via)
    local ok, err = pcall(fn, via)
    if not ok then
        st.errors = st.errors + 1
        LOG.warn('key_error', { action = action, err = tostring(err) })
    end
end

local function resolve(b)
    if type(b) ~= 'table' or not Key then return nil, nil, 'no binding' end
    local k = Key[b.key]
    if k == nil then return nil, nil, 'unknown key ' .. tostring(b.key) end
    local mods = {}
    for _, m in ipairs(b.mods or {}) do
        local mv = ModifierKey and ModifierKey[m]
        if mv == nil then return nil, nil, 'unknown modifier ' .. tostring(m) end
        mods[#mods + 1] = mv
    end
    return k, mods
end

local function label(b)
    if type(b) ~= 'table' then return nil end
    local parts = {}
    for _, m in ipairs(b.mods or {}) do parts[#parts + 1] = ({ CONTROL = 'Ctrl', SHIFT = 'Shift', ALT = 'Alt' })[m] or m end
    parts[#parts + 1] = tostring(b.key)
    return table.concat(parts, '+')
end

-- true or false from the loader; 'unread' and the reason when it is missing or raised (a non-integer key throws)
local function collides(k, mods)
    if type(IsKeyBindRegistered) ~= 'function' then return 'unread', 'no IsKeyBindRegistered' end
    local ok, r = pcall(function()
        if #mods > 0 then return IsKeyBindRegistered(k, mods) end
        return IsKeyBindRegistered(k)
    end)
    if not ok then return 'unread', tostring(r) end
    return r == true
end

local function register(k, mods, press)
    if #mods > 0 then RegisterKeyBind(k, mods, press) else RegisterKeyBind(k, press) end
end

local function fail(action, err) LOG.warn('key_fail', { action = action, err = err }) end

function K.init()
    bound, handlers, slots, alive = {}, {}, {}, true
    st.presses, st.ran, st.dropped, st.errors = 0, 0, 0, 0
    return true
end

-- fn(via) runs on the game thread (K.drain, K.invoke). Returns ok, collision (see the header).
function K.bind(action, binding, fn)
    handlers[action] = function(via) run(action, fn, via or 'key') end
    local k, mods, err = resolve(binding)
    if not k then
        bound[action] = { ok = false, err = err, collision = 'unread' }
        if binding ~= nil then fail(action, err) end
        return false, 'unread'
    end
    -- the slot is the callback's only upvalue: n counts presses (update thread), seen counts drained ones (game thread)
    local slot = { action = action, fn = fn, n = 0, seen = 0 }
    local press = function() slot.n = slot.n + 1 end
    local collision, cerr = collides(k, mods)
    local ok, rerr = pcall(register, k, mods, press)
    bound[action] = { key = label(binding), ok = ok, err = (not ok) and tostring(rerr) or nil, collision = collision,
        collision_err = cerr, presses = 0, dropped = 0 }
    if ok then slots[#slots + 1], slot.rec = slot, bound[action] else fail(action, tostring(rerr)) end
    return ok, collision
end

-- Game thread, once per frame: the handlers of the presses counted since the last call. The counter is read once, so
-- a press that lands meanwhile waits for the next frame. Returns the number of handler calls.
function K.drain()
    local ran = 0
    for i = 1, #slots do
        local slot = slots[i]
        local n = slot.n
        local pending = n - slot.seen
        if pending > 0 then
            slot.seen = n
            local rec = slot.rec
            local run_n = pending > K.MAX_PER_FRAME and K.MAX_PER_FRAME or pending
            rec.presses, st.presses = rec.presses + pending, st.presses + pending
            if run_n < pending then rec.dropped, st.dropped = rec.dropped + pending - run_n, st.dropped + pending - run_n end
            for _ = 1, run_n do
                if not alive then break end
                run(slot.action, slot.fn, 'key')
                ran = ran + 1
            end
        end
    end
    st.ran = st.ran + ran
    return ran
end

-- The console twin: already on the game thread, so the handler runs here, not through a counter
function K.invoke(action, via)
    local h = handlers[action]
    if not h or not alive then return false end
    h(via or 'console')
    return true
end
function K.label(action) return bound[action] and bound[action].key or nil end
function K.table() return bound end
function K.status() return bound end
-- presses seen by drain, handler calls, presses over the per-frame cap, handler errors (nil while nothing was pressed)
function K.stats()
    if st.presses == 0 and st.errors == 0 then return nil end
    return { presses = st.presses, ran = st.ran, dropped = st.dropped, errors = st.errors }
end
function K.reset() end
function K.shutdown() alive = false end

return K
