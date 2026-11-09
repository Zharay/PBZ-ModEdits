-- status: untested (the chain is the SWZC delayed-step pattern; verify per UE4SS build) origin: kb:runtime-safety-perf#phase-scheduler-with-hook-inbox
-- tick.lua: the game-thread frame chain that drives core/sched.lua. UE4SS has no per-frame Lua callback, so:
-- * LoopInGameThreadAfterFrames(1, step) when the build has it, else a step that re-schedules itself with
--   ExecuteInGameThreadAfterFrames(1) or ExecuteInGameThreadWithDelay(16 ms). Needs DefaultExecuteInGameThreadMethod =
--   EngineTick (UE4SS-settings.ini); verify on each new UE4SS build that the chain ticks (frames grow in status).
-- * LoopAsync is NOT the game thread: never drive engine work (or this Lua state) from it.
-- * Every chain carries the epoch it started in; T.stop() (OnUnload, engine-free) bumps it and old steps do nothing.
--   Ctrl+R erases delayed actions anyway; the epoch covers the frame between.
-- * A separate status timer (LoopInGameThreadWithDelay, opts.status_ms 1000) calls opts.on_status: LOG.status_tick
--   writes a status record every 30 s from it, so a frozen frame counter next to live status shows a dead chain. It is
--   started by the first frame (game thread), so T.start, which runs on the update thread, makes one push only.
-- * T.after_frames / T.after_ms: epoch-guarded delayed steps (warm-up stagger, call windows).
-- API: start(opts { on_frame, on_status, status_ms }) stop frame after_frames(n, fn) after_ms(ms, fn) status
-- Evidence: [worked SWZC] main.lua 66-73, 640-658, lib/ue.lua after_frames/after_ms; engine note 'UE5 / UE4SS 527a483b'
local LOG = require('core.log')

local T = { epoch = 0 }
local st = { frames = 0, method = nil, errors = 0, status_errors = 0, running = false }

local function guarded(fn, key)
    local ok, err = pcall(fn)
    if not ok then
        st[key] = st[key] + 1
        if st[key] <= 3 then LOG.warn('tick_error', { what = key, err = tostring(err), n = st[key] }) end
    end
end

local function delay_ms(ms, fn)
    if ExecuteInGameThreadWithDelay then return (pcall(ExecuteInGameThreadWithDelay, math.max(1, math.floor(ms)), fn)) end
    return false
end
local function delay_frames(n, fn)
    if ExecuteInGameThreadAfterFrames and EngineTickAvailable ~= false then
        if pcall(ExecuteInGameThreadAfterFrames, n, fn) then return true end
    end
    return delay_ms(math.max(16, n * 17), fn)
end

function T.start(opts)
    opts = opts or {}
    T.epoch = T.epoch + 1
    local ep = T.epoch
    st.running, st.frames = true, 0
    local on_frame, on_status = opts.on_frame, opts.on_status
    local step, status_up
    -- The status timer starts from the first frame, on the game thread: T.start runs in main.lua's body on UE4SS's update
    -- thread, and every ExecuteInGameThread* / LoopInGameThread* call pushes onto the mod's hook_lua stack, which the game
    -- thread is already running the first step on after the first push (spec M1a 4.2 item 1 audit). One push from the body.
    local function start_status()
        if on_status and LoopInGameThreadWithDelay then
            pcall(LoopInGameThreadWithDelay, opts.status_ms or 1000, function()
                if ep == T.epoch then guarded(on_status, 'status_errors') end
            end)
        end
    end
    step = function()
        if ep ~= T.epoch then return end
        st.frames = st.frames + 1
        if not status_up then status_up = true start_status() end
        if on_frame then guarded(on_frame, 'errors') end
        if st.method ~= 'loop' and ep == T.epoch then delay_frames(1, step) end
    end
    if LoopInGameThreadAfterFrames and EngineTickAvailable ~= false and pcall(LoopInGameThreadAfterFrames, 1, step) then
        st.method = 'loop'
    elseif delay_frames(1, step) then
        st.method = 'chain'
    else
        st.method, st.running = 'none', false
        LOG.warn('tick_none', { msg = 'no game-thread delayed action API: the scheduler does not run' })
        return false
    end
    return true
end

-- Engine-free (OnUnload): stale steps return at their next call
function T.stop() T.epoch, st.running = T.epoch + 1, false end
function T.frame() return st.frames end

function T.after_frames(n, fn)
    local ep = T.epoch
    return delay_frames(math.max(1, math.floor(n)), function() if ep == T.epoch then fn() end end)
end
function T.after_ms(ms, fn)
    local ep = T.epoch
    return delay_ms(ms, function() if ep == T.epoch then fn() end end)
end

function T.status()
    return { frames = st.frames, method = st.method, running = st.running, errors = st.errors,
        status_errors = st.status_errors, epoch = T.epoch }
end
function T.reset() end
function T.shutdown() T.stop() end

return T
