-- status: inferred origin: kb:blood-fx#p17
-- (the rule comes from a DD2 failure and its fix; this module form is untested in game)
-- fx_gate.lua: the ONE bleed gate. Every blood spawn of every feature (stump spray, pools, drips, carried heads, gib
-- splashes) goes through G.spawn, the only caller of A.spawn_blood (lint L016: blood calls outside this module are
-- errors). One rule decides which blows draw blood and how much:
--   refused, k = 0, with a reason word: off (setting or effects.blood), modoff, blocked (a guarded hit), family_off,
--     party (companions and the player; party_blood false), no_blood (bone, rock, debris, metal, iron, and the wooden
--     puppets' wood and the census 'none' bodies, the author's «2: yes»),
--     frozen (a frozen victim's killing blow shatters: ice, no blood), amount_zero (Blood amount 0), after_death (a
--     living hit, b.kind 'hit', at or after the victim's death frame v.f_dead, which kill.lua stamps on confirm: the
--     killing blow's own hit can arrive after the kill; route corpse hits as kind 'corpse'; blood-wounds rule 25)
--   else k = amount x size^2, size = clamp(scale^0.75, 0.6, 4), amount = the global blood_amount clamped 0-5
--     (1.0 = vanilla; HR-BLOOD-LIQUID asks for 3x, so the old 0-2 clamp would cut the baseline);
--     seared (fire, thunder) x seared_k 0.25, NEVER 0: a cauterized cut still leaves a pool;
--     corpse hit x freshness, never the HP share (the game deals 0 damage to a corpse): b.dead_age (s since death, from
--     the death time stored on EVERY confirmed death) gives 1 within 30 s, falling linearly to 0.3 at 180 s, times
--     b.blood_left (0-1), floor 0.3; no dead_age known: x corpse_k 0.6. Callers scale strength by k but never lower the
--     drop count with it (a hacked torso threw 2 drops instead of 8). Case (DD2): HP-share corpse splats 'disappear'.
-- Case (DD2): the liquid core bled from blocked hits and switched-off families, fire bled at full strength, and a
-- thrown goblin head sprayed as much as a human one at Blood amount 0; the author's lightning mace left no pool on 5 of
-- 6 head crushes ('the blood is barely visible') until seared cuts kept their pools.
-- ADAPTER CONTRACT: A.spawn_blood(req) -> handle | nil   req = { id, k, kind, pos, normal, part } (the engine spawner)
-- The victim v carries v.def (its resolved family: blood, blood_kind, scale) and v.family, v.party; the blow b carries
-- blocked, frozen, seared (classify's look), corpse.
-- Evidence: [inferred] kb:blood-fx#p17, kb:blood-fx#p18; [worked DD2] fx.lua amount(), fxcore.lua NO_BLOOD/blood_of,
-- liquid.lua seared_k 0.25, corpse_k 0.6
local NAME0 = (...) or 'features.fx_gate'
local PFX, SEP = NAME0:match('^(.-)features([./])[^./]*$')
if not PFX then PFX, SEP = '', '.' end
local LOG = require(PFX .. 'core' .. SEP .. 'log')
local S = require(PFX .. 'core' .. SEP .. 'sched')
local BUS = require(PFX .. 'core' .. SEP .. 'bus')
local C = require(PFX .. 'core' .. SEP .. 'config')
local MO = require(PFX .. 'core' .. SEP .. 'modoff')
local SENT = require(PFX .. 'core' .. SEP .. 'sentinel')

local G = { name = 'fx_gate' }
-- Non-flesh bodies draw no red blood. 'wood' and 'none' are the author's «2: yes» (DESIGN D2: wooden puppets get
-- splinters only, no red blood, by default); the census writes blood_kind 'none' for the 12 puppet and vessel families
-- and M1's family model maps puppet families to 'wood'. The splinter look itself is built in M3 and M7.
G.NO_BLOOD = { bone = true, rock = true, debris = true, metal = true, iron = true, wood = true, none = true }
G.DEFAULTS = {
    enabled = true,          -- ships on
    seared_k = 0.25,         -- fire and thunder cauterize: less blood, never none
    corpse_k = 0.6,          -- a hit on a dead body of unknown age bleeds this share
    fresh_s = 30, stale_s = 180, stale_share = 0.3, corpse_floor = 0.3,   -- corpse freshness (kb:content-coverage)
    party_blood = false,     -- the player and companions draw no gore blood
    size_exp = 0.75, size_min = 0.6, size_max = 4.0,   -- size = clamp(scale^0.75, 0.6, 4); k grows with size^2
    on_cut = true,           -- a stump spray per cut, as the example caller of G.spawn
    max_per_frame = 8,       -- spawns per frame from the cut queue
}
local opt = C.section_opt('fx_gate', G.DEFAULTS)
G.opt = opt

local A = nil
local st = { queue = {}, proven = {}, spawned = 0, refused = {}, faults = 0 }

local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

-- The global multiplier over the vanilla blood amount (1.0 = vanilla). Clamped 0..5 (D16, was 0..2) so the
-- HR-BLOOD-LIQUID baseline of 3x vanilla (Maximum preset blood_amount 3.0) reaches the spawner unclipped.
function G.amount()
    local ok, s = pcall(C.get)
    local a = ok and type(s) == 'table' and tonumber(s.blood_amount) or nil
    if a == nil then a = 1.0 end
    return clamp(a, 0, 5)
end
function G.size(def)
    local scale = def and tonumber(def.scale) or 1.0
    if not (scale > 0 and scale < math.huge) then scale = 1.0 end   -- bad data never gives a NaN bleed
    return clamp(scale ^ opt('size_exp'), opt('size_min'), opt('size_max'))
end
local function bleeds(def)
    return not (def and (def.blood == false or G.NO_BLOOD[def.blood_kind]))
end
-- The per-family switch, the same lookup kill makes: the resolved family's own base chain, nearest first (v.def
-- from parts/families_fn), else its key, else the victim's family id
local function family_on(v)
    local okc, s = pcall(C.get)
    local map = okc and type(s) == 'table' and s.families or nil
    if type(map) ~= 'table' then return true end
    local def, x = v.def, nil
    if def and type(def.chain) == 'table' then
        for i = #def.chain, 1, -1 do
            x = map[def.chain[i]]
            if x ~= nil then break end
        end
    else
        x = map[(def and def.key) or v.family]
    end
    return x ~= false and x ~= 'off'
end

-- How much this blow on this victim bleeds: k >= 0, and the reason word when it is 0
function G.k(v, b)
    b = b or {}
    if opt('enabled') == false then return 0, 'off' end
    local okc, eff = pcall(C.effect, 'blood')
    if okc and eff == false then return 0, 'off' end
    if not MO.enabled(G.name) then return 0, 'modoff' end
    if b.blocked then return 0, 'blocked' end
    if b.kind == 'hit' and v and tonumber(v.f_dead) and (tonumber(b.frame) or math.huge) >= tonumber(v.f_dead) then
        return 0, 'after_death'
    end
    if v and (v.def or v.family) then
        local okf, on = pcall(family_on, v)
        if okf and on == false then return 0, 'family_off' end
    end
    if v and v.party and not opt('party_blood') then return 0, 'party' end
    local def = v and v.def
    if not bleeds(def) then return 0, 'no_blood' end
    if b.frozen then return 0, 'frozen' end
    local amount = G.amount()
    if amount <= 0 then return 0, 'amount_zero' end
    local size = G.size(def)
    local k = amount * size * size
    if b.seared then k = k * math.max(0.05, opt('seared_k')) end
    if b.corpse then k = k * G.corpse_share(b) end
    return k, nil
end

-- A corpse hit's share by freshness (never by damage): 1 within fresh_s, linear to stale_share at stale_s, times the
-- blood left, floor corpse_floor; corpse_k when the death time is unknown
function G.corpse_share(b)
    local age = tonumber(b and b.dead_age)
    if not (age and age >= 0 and age < math.huge) then return opt('corpse_k') end
    local f0, f1, s1 = opt('fresh_s'), opt('stale_s'), opt('stale_share')
    local fresh = 1.0
    if age >= f1 then fresh = s1
    elseif age > f0 then fresh = 1.0 + (s1 - 1.0) * (age - f0) / (f1 - f0) end
    local left = tonumber(b.blood_left)
    if not (left and left >= 0) then left = 1.0 end
    return clamp(fresh * math.min(1, left), opt('corpse_floor'), 1.0)
end

local function refuse(kind, reason, v)
    st.refused[reason] = (st.refused[reason] or 0) + 1
    LOG.debug('fx_skip', { kind = kind, reason = reason, id = v and v.id })
    return nil, reason
end

-- The only blood path. req: { kind = 'blood' | 'spray' | 'pool' ..., scale (x k), pos, normal, part }.
-- Returns the spawner's handle, or nil and the reason word.
function G.spawn(v, b, req)
    req = req or {}
    local kind = req.kind or 'blood'
    local k, why = G.k(v, b)
    if k <= 0 then return refuse(kind, why, v) end
    if not (A and A.spawn_blood) then return refuse(kind, 'no_spawner', v) end
    local r = { id = v and v.id, k = k * (tonumber(req.scale) or 1.0), kind = kind, pos = req.pos,
        normal = req.normal, part = req.part }
    local h, err = SENT.risky('fx_gate.first_spawn', st.proven, kind, nil, A.spawn_blood, r)
    if h == nil then
        st.faults = st.faults + 1
        LOG.warn('fx_fault', { kind = kind, err = tostring(err), id = r.id })
        return nil, 'fault'
    end
    st.spawned = st.spawned + 1
    LOG.debug('fx', { kind = 'blood', sub = kind, id = r.id, k = math.floor(r.k * 1000 + 0.5) / 1000 })
    return h
end

-- The example caller: one stump spray per cut, queued by the listener and spawned by the ticker
local function on_cut(v, cut)
    if opt('on_cut') == false then return end
    local q = st.queue
    if #q >= 64 then
        local old = table.remove(q, 1)
        refuse('spray', 'limit', old.v)                 -- the oldest spray goes, with its reason word
    end
    q[#q + 1] = { v = v, b = cut and cut.blow or {}, part = cut and cut.part }
end
local function job()
    local n = 0
    while st.queue[1] and n < opt('max_per_frame') do
        local it = table.remove(st.queue, 1)
        G.spawn(it.v, it.b, { kind = 'spray', part = it.part })
        n = n + 1
    end
end

function G.init(adapter, opts)
    A = adapter or {}
    st = { queue = {}, proven = {}, spawned = 0, refused = {}, faults = 0 }
    if not A.spawn_blood then
        LOG.info('adapter_missing', { module = G.name, fn = 'spawn_blood', why = 'no blood: every spawn refused' })
    end
    BUS.on('cut', G.name, on_cut)
    MO.feature(G.name, { gameplay = true })
    S.ticker(G.name, job)
    return true
end
function G.shutdown()
    S.remove_ticker(G.name)
    BUS.off('cut', G.name)
    st.queue = {}
end
function G.reset() st.queue = {} end
function G.status() return { spawned = st.spawned, refused = st.refused, faults = st.faults, queue = #st.queue } end
function G.ui_status() return string.format('blood gate: %d spawned, amount %.2f', st.spawned, G.amount()) end
function G.handoff() return nil end

return G
