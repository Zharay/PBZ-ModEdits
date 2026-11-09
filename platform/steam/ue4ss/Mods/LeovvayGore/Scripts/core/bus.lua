-- status: worked DD2 origin: kb:runtime-safety-perf#principles (11: lifecycle cleanup via the bus)
-- bus.lua: the event bus between modules. The kill pipeline decides; feature modules subscribe to the outcome. Listeners
-- run in the phase that emits (the late phase for gameplay events), each under its own pcall, so one failing feature
-- never blocks another: listener_error is logged for the first 3 errors of each listener and every error is counted.
-- A listener of a feature that is switched off (opts.is_off(name), normally sched's breaker) is skipped, unless it was
-- registered with { teardown = true }: cleanup listeners (restore, victim_gone, map_reset, mod_off, shutdown) always
-- run, or a tripped feature leaves a hidden head or a glowing ember behind.
-- Generic vocabulary (payloads are plain tables; v is a victim record):
--   hit(v, blow)  kill(v, blow)  corpse_hit(v, blow)  cut(v, cut)  gib(v, g)  burst(v, b)  restore(v, reason)
--   victim_gone(v)  downed(v)  revived(v)  map_reset(reason)  mod_off(on)  shutdown(reason)
-- API: B.on(ev, name, fn [, opts]) (one listener per ev and name; again replaces it), B.off(ev, name), B.emit(ev, ...),
--      B.count(ev); lifecycle init(A, opts) / shutdown / status / reset.
-- Evidence: [worked DD2] core/bus.lua; design: teardown listeners bypass the kill switch (SWZC cleanup_after)
local BASE = ((...) or ''):match('^(.-)[^./]*$') or ''
local LOG = require(BASE .. 'log')

local B = {}
local subs, errors = {}, {}
local is_off = nil
local MAX_LOGGED = 3

function B.init(_, opts)
    subs, errors = {}, {}
    is_off = opts and opts.is_off or nil
    return true
end
function B.reset() errors = {} end
function B.shutdown() subs, errors = {}, {} end
function B.status()
    local n = 0
    for _, list in pairs(subs) do n = n + #list end
    return { listeners = n, errors = next(errors) and errors or nil }
end

function B.on(ev, name, fn, opts)
    local list = subs[ev]
    if not list then list = {} subs[ev] = list end
    local rec = { name = name, fn = fn, teardown = opts and opts.teardown == true }
    for i, s in ipairs(list) do
        if s.name == name then list[i] = rec return end
    end
    list[#list + 1] = rec
end

function B.off(ev, name)
    local list = subs[ev]
    if not list then return end
    for i, s in ipairs(list) do
        if s.name == name then table.remove(list, i) return end
    end
end

-- Runs over a copy of the list: a listener that removes itself (B.off) must not make the next one miss this event
function B.emit(ev, ...)
    local live = subs[ev]
    if not live or not live[1] then return 0 end
    local list = live
    if live[2] then
        list = {}
        for i = 1, #live do list[i] = live[i] end
    end
    local ran = 0
    for _, s in ipairs(list) do
        if s.teardown or not (is_off and is_off(s.name)) then
            ran = ran + 1
            local ok, err = pcall(s.fn, ...)
            if not ok then
                local key = ev .. ':' .. s.name
                local n = (errors[key] or 0) + 1
                errors[key] = n
                if n <= MAX_LOGGED then
                    LOG.warn('listener_error', { what = ev, listener = s.name, err = tostring(err), n = n })
                end
            end
        end
    end
    return ran
end

function B.count(ev) return subs[ev] and #subs[ev] or 0 end

return B
