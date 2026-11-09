-- status: worked SWZC origin: kb:runtime-safety-perf#whole-mod-off-toggle
-- modoff_ue.lua: the UE side of core/modoff.lua (the switch logic, the refusals and the log lines live there).
-- ops for MODOFF.init(A, { ops = MU.ops(hooks) }), all called on the game thread (the tick drains key presses first):
-- * unhook_all / rehook_all: every registered hook down, and back up (a features-only toggle left hooks running).
--   unhook_all runs under the always-armed 'modoff.unhook' in every profile (spec M1a 3.4, D14: L8 is the first live
--   UnregisterHook on 1185). A disabled name (a crash inside it at an earlier press) leaves the hooks registered while
--   off; the feature gates still refuse (MODOFF.enabled), and the refusal is one call_fault record. rehook_all
--   re-registers under adapter/hooks.lua's 'hook:<id>' guards (main.lua's wrap).
-- * hide / show (obj, kind): kind 'actor' (an own actor: a Piece) through SetActorHiddenInGame(h), each call under the
--   always-armed 'modoff.hide'; anything else (a component) through SetHiddenInGame(true|false, false). The mod
--   HIDES, never destroys: on comes back exactly.
-- * visible(obj, kind): false when already hidden (an actor reads Actor.bHidden; a component bHiddenInGame, then
--   IsVisible), so on never unhides what the game or a feature hid itself.
-- * ours(obj, name): valid and still that name (an address reused after a GC is not ours).
-- Both names linger MU.LINGER_S (3 s, section 3.4) after a call that ran; a refused call writes nothing more.
-- The lists come from each feature's live() { { obj, name, kind } } (MODOFF.feature(name, { live })); a map change
-- drops the hidden list (MODOFF.reset: those objects went with the old world).
-- Evidence: [worked SWZC] lib/mod_off.lua, tools/luatest/test_mod_off.lua
local ue = require('adapter.ue')
local SENT = require('core.sentinel')
local LOG = require('core.log')

local MU = { hidden = 0, shown = 0, refused = 0, failed = 0 }
MU.HIDE, MU.UNHOOK, MU.LINGER_S = 'modoff.hide', 'modoff.unhook', 3

-- fn(...) under the always-armed name; a call that ran lingers. A refusal (a disabled name, a failed arm write) or a
-- raise inside is one call_fault record and answers nil; else fn's first result
local function armed(name, fn, ...)
    local ran = false
    local r, err = SENT.sentinel(name, function(...)
        ran = true
        return fn(...)
    end, ...)
    if ran then SENT.linger(name, MU.LINGER_S) end
    if err ~= nil then
        MU.refused = MU.refused + 1
        LOG.warn('call_fault', { key = name, err = tostring(err), ran = ran })
        return nil
    end
    return r
end

-- true when the hide or show call returned (an actor through the bridge's ue.call, which counts the write). ue.call
-- catches the call's own error and answers false, so a failed actor call (a dead handle, a missing function, a
-- marshalling error) is one call_fault record too, never a silent hide behind the press's list
local function set_hidden(obj, kind, h)
    if kind == 'actor' then
        local why
        local r = armed(MU.HIDE, function()
            local ok, err = ue.call(obj, 'SetActorHiddenInGame', h)
            if ok ~= true then why = err end
            return ok
        end)
        if r == false then
            MU.failed = MU.failed + 1
            LOG.warn('call_fault', { key = MU.HIDE, err = tostring(why), ran = true })
        end
        return r == true
    end
    return ue.set_hidden(obj, h)
end

function MU.ops(hooks)
    return {
        unhook_all = function() return armed(MU.UNHOOK, hooks.unregister_all) end,
        rehook_all = function() return hooks.reregister_all() end,
        hide = function(obj, kind)
            if set_hidden(obj, kind, true) then MU.hidden = MU.hidden + 1 end
        end,
        show = function(obj, kind)
            if set_hidden(obj, kind, false) then MU.shown = MU.shown + 1 end
        end,
        visible = function(obj, kind)
            if kind == 'actor' then return ue.get(obj, 'bHidden') ~= true end
            local h = ue.get(obj, 'bHiddenInGame')
            if h == true then return false end
            local ok, v = ue.call(obj, 'IsVisible')
            if ok and v == false then return false end
            return true
        end,
        ours = function(obj, name) return ue.ours(obj, name) end,
    }
end

function MU.status() return { hidden = MU.hidden, shown = MU.shown, refused = MU.refused, failed = MU.failed } end
function MU.reset() end
function MU.shutdown() end

return MU
