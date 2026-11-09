-- status: worked DD2 origin: kb:dismember-core#p2
-- (worked: snapshot, queue, confirm, classify, ladder data; untested: the weapon gate, the ladder dispatch, tear_once)
-- also: kb:dismember-core#re-engine-kill-pipeline-read-only-pre-snapshot-queue-lateupdatebehavior-preparerendering-writes-dd2
-- kill.lua: the kill pipeline. Engine-free: the adapter's death hook hands over the hit, this module decides.
-- 1. Hook side (K.on_kill / K.on_corpse_hit): copy K.SNAP_FIELDS field by field into a plain table (vectors copied
--    too; pooled hit structs are cleared and reused), queue it, return. The hook never acts and never stores the
--    source. K.SNAP_FIELDS is the one owner of the field list (DD2 had three modules copying 25 reads each).
-- 2. Queue: max_queue 64; over it the oldest corpse hit drops first, else the oldest event. Stale after 2 s for a kill
--    and 0.5 s for a corpse hit, on GAME time (slow motion and pauses stretch wall time). Paused: wait.
-- 3. Late phase (one sched ticker, its own breaker): kills before corpse hits, retried kills first, at most 6 events
--    and 0.4 ms per frame (the first event always runs). Death confirmed on the game thread: A.is_dead, retried 3
--    frames (pres run even when another mod skipped the death), else skip not_dead; a duplicate within 0.5 s is
--    already_cut; a corpse hit within 0.15 s of the death is the killing blow's own hit and is dropped; corpse hits
--    on one body wait 0.25 s apart and stop after 8 Part actions (skip limit, why cooldown / actions; DD2 DEFAULTS).
--    0.25 s does NOT stop multi-blast skills (Meteor Fall took 4 Parts off a Griffin 0.28 s apart); tear_once does:
--    an explosion that removes something (Part or whole body, kill or corpse hit) opens a fixed tear_once_s window per
--    victim and attack owner (b.owner, else killer, shell, gimmick, one shared key; never the attack name). That
--    owner's later blasts inside it remove nothing (skip tear_once) and still go on the bus as push, so push, bleed
--    and wear run. A blast that removes nothing opens no window; restore clears them (kb:dismember-core#p34).
-- 4. Decide: parts.locate -> parts.cut_part (minor promote) -> libs/classify.decide (precedence, tier 0-4, rules).
--    A player Part-filter refusal is none / kind_off and is NEVER demoted. Special cuts (split, cleave) read the weapon
--    only now, after classify's geometry and strength gates: an unknown weapon or one outside special_weapons gives a
--    plain cut (kb:dismember-core#p40). The ladder (parts.ladder) demotes on TECHNICAL blocks only (hide.can,
--    K.ext.block: cloth, budget, sentinel): arm -> forearm -> head -> the joint cut, so a promised cut never ends in
--    nothing. A Part already cut, or under a cut Part (hide records, P.chain), is skip already_cut, never demoted.
-- 5. Gates after all fallbacks, on the Part actually cut: K.ext.tough refuses corpse hits only and is IGNORED for a
--    killing blow (the killing blow always cuts: kb:dismember-core#p24); chance (setting 'chance', default 1.0) rolls
--    on corpse hits only. Every kill and corpse_hit record carries action or a skip word from events.schema.json.
-- 6. Dispatch on the bus: cut(v, cut) for Part actions (hide stages, caps attach, fx_gate bleeds), then kill(v, b) or
--    corpse_hit(v, b) for everything else that listens (a family with nothing to cut still gets kill, action none).
-- ADAPTER CONTRACT: A.victim(b) -> v (the victim record for the snapshot's id; default { id, family, party });
--   A.valid(v) -> bool; A.is_dead(v) -> bool (absent: the hook's word is trusted, logged once); A.weapon(v, b) ->
--   class | nil (absent or nil: unknown); A.clock.real() -> s (the per-frame seconds budget)
-- K.ext: tough(v, b, part) -> true to refuse; block[i](v, part, tech) -> reason | nil; skip[i](v, b, corpse) ->
--   reason | nil; party(v, b) -> true to allow a party victim; weapon(v, b) overrides A.weapon.
-- Snapshot identities (plain strings or numbers, never the object): owner = the attack owner object's address (the
--   tear_once key), hit_addr = the hit struct's address (hit listeners dedupe the kill's own hit by it, p32), shell =
--   the shell or projectile param id; explosion = true when the adapter already knows (classify reads it).
-- Case (DD2): onDieFromAttack pre caught 10/10 lab kills; 40 kills and 110 Cuts on TU 4.1 with 0 hook errors.
-- Case (DD2, Nexus B8): a Thief burst stripped a Goreminotaur 'like a LEGO man'; tear_once is the decided fix (no
--   tear_once skip logged in play yet).
-- Case (SWZC): 3 of 4 saber kills on Coil Strikers cut nothing until the ladder demoted instead of giving up.
-- Evidence: [worked DD2] kill.lua 90-114, 145-302, 1183-1326; killext.lua 341-463 (weapon read); [worked SWZC]
-- saber_tier8.lua (ladder), data/hooks.lua; kb:content-coverage#p11 kb:dismember-core#p23
-- kb:dismember-core#tier-8-swing-aware-joint-cut-with-a-demotion-ladder-the-permanent-fallback-swzc
-- [untested] tear_once: kb:dismember-core#one-tear-per-explosion-attack-multi-blast-dedupe-dd2-decision-22
local NAME0 = (...) or 'features.kill'
local PFX, SEP = NAME0:match('^(.-)features([./])[^./]*$')
if not PFX then PFX, SEP = '', '.' end
local BASE = NAME0:match('^(.-)[^./]*$') or ''
local LOG = require(PFX .. 'core' .. SEP .. 'log')
local S = require(PFX .. 'core' .. SEP .. 'sched')
local BUS = require(PFX .. 'core' .. SEP .. 'bus')
local C = require(PFX .. 'core' .. SEP .. 'config')
local MO = require(PFX .. 'core' .. SEP .. 'modoff')
local RNG = require(PFX .. 'core' .. SEP .. 'rng')
local CL = require(PFX .. 'libs' .. SEP .. 'classify')
local P = require(BASE .. 'parts')
local H = require(BASE .. 'hide')

local K = { name = 'kill' }
-- The hit fields the hook copies (plain values only; the adapter reads them by name from the engine's hit struct)
K.SNAP_FIELDS = { 'id', 'family', 'party', 'joint', 'joint_b', 'pos', 'attack_vec', 'weapon_pos', 'slash', 'blow',
    'shoot', 'magic', 'hit_eff', 'tier', 'react', 'floor', 'over', 'finish', 'damage', 'dmg_slash', 'dmg_blow',
    'force', 'name', 'tags', 'gimmick', 'element', 'frozen', 'blocked', 'max_hp', 'killer', 'region', 'owner',
    'hit_addr', 'shell', 'explosion' }
K.DEFAULTS = {
    enabled = true,          -- ships on
    max_per_frame = 6,       -- events processed per late phase
    budget_s = 0.0004,       -- seconds per late phase after the first event
    max_queue = 64,          -- queued events; over it the oldest corpse hit drops first
    kill_max_age_s = 2.0,    -- game seconds a kill may wait
    corpse_max_age_s = 0.5,  -- game seconds a corpse hit may wait
    confirm_retries = 3,     -- late phases a death may take to confirm
    dup_kill_s = 0.5,        -- a second kill of one victim within this is a duplicate
    corpse_grace_s = 0.15,   -- a corpse hit this soon after the death is the killing blow's own hit
    corpse_hits = true,      -- cut on hits to dead bodies
    corpse_cooldown_s = 0.25, -- game seconds between two corpse hits on one body; 0.25 s does NOT stop multi-blast
                              -- skills (Meteor Fall: 4 Parts 0.28 s apart); tear_once_s does
    tear_once_s = 1.5,       -- game seconds one attack owner's explosions may remove only once per victim
    max_actions = 8,         -- Part actions per victim; past it corpse hits skip limit / actions
    special_weapons = { blade = true },   -- weapon classes that may split or cleave (others give a plain cut)
}
local SPECIAL = { split = true, cleave = true }
K.ext = { tough = nil, block = {}, skip = {}, party = nil, weapon = nil }

local opt = C.section_opt('kill', K.DEFAULTS)
K.opt = opt

local A = nil
local st = { queue = {}, retry = {}, victims = {}, stats = {}, warned = {} }

local function count(k) st.stats[k] = (st.stats[k] or 0) + 1 end
local function copy_value(x)
    local t = type(x)
    if t == 'number' or t == 'string' or t == 'boolean' then return x end
    if t == 'table' then
        if type(x.x) == 'number' then return { x = x.x, y = x.y, z = x.z } end
        local out = {}
        for i = 1, #x do if type(x[i]) == 'string' or type(x[i]) == 'number' then out[#out + 1] = x[i] end end
        return out
    end
    return nil                                   -- userdata, functions: never kept past the hook
end

-- Hook side: the plain copy. read(src, field) reads one field (default src[field])
function K.snapshot(src, kind, read)
    local b = { kind = kind or 'kill', corpse = kind == 'corpse', gt = S.game_time, frame = S.frame }
    for _, f in ipairs(K.SNAP_FIELDS) do
        local ok, x = true, nil
        if read then ok, x = pcall(read, src, f) else x = src[f] end
        if ok and x ~= nil then b[f] = copy_value(x) end
    end
    return b
end

local function record(ev, v, b, extra)
    local rec = { id = v and v.id or b.id, family = v and v.family or b.family, blow = b.cls, strength = b.strength,
        part = b.part, killer = b.killer }
    for k, x in pairs(extra) do rec[k] = x end
    LOG.info(ev, rec)
end
-- One skip record: a fixed reason word in skip, the detail in why
local function skip(v, b, reason, why)
    count('skip_' .. reason)
    record(b.corpse and 'corpse_hit' or 'kill', v, b, { skip = reason, why = why })
end
K.skip_record = skip

function K.push(b)
    local q = st.queue
    if #q >= opt('max_queue') then
        local drop = 1
        for i, e in ipairs(q) do if e.corpse then drop = i break end end
        local old = table.remove(q, drop)
        skip(nil, old, 'limit', 'queue')
    end
    q[#q + 1] = b
end
function K.on_kill(src, read) K.push(K.snapshot(src, 'kill', read)) end
function K.on_corpse_hit(src, read) K.push(K.snapshot(src, 'corpse', read)) end

local function victim(b)
    local v = A.victim and A.victim(b) or nil
    if not v then v = { id = b.id, family = b.family, party = b.party } end
    local vs = st.victims[v.id]
    if not vs then vs = { state = 'alive' } st.victims[v.id] = vs end
    if vs.f_dead and v.f_dead == nil then v.f_dead, v.gt_dead = vs.f_dead, vs.gt_dead end   -- a fresh v per call
    return v, vs
end
-- The confirmed death of a victim id: frame, game time (nil, nil before the kill). For hit listeners whose adapter
-- builds a fresh victim record per call: copy them onto v before fx_gate.k (blood-wounds rule 25)
function K.death(id)
    local vs = st.victims[id]
    if vs and vs.f_dead then return vs.f_dead, vs.gt_dead end
    return nil, nil
end
local function once(key, rec)
    if st.warned[key] then return end
    st.warned[key] = true
    LOG.info('adapter_missing', rec)
end

-- The weapon class, read only for a special cut (counted: a plain cut never reads it)
local function weapon_of(v, b)
    local fn = K.ext.weapon or (A and A.weapon)
    if not fn then
        once('weapon', { module = K.name, fn = 'weapon', why = 'special cuts become plain cuts' })
        return nil
    end
    count('weapon_reads')
    local ok, w = pcall(fn, v, b)
    if ok then return w end
    return nil
end

-- Is this Part, or a Part above it, already cut on this victim? (records only, never transforms)
local function taken(v, fam, part)
    for _, pid in ipairs(P.chain(fam, part)) do
        if H.is_cut(v, pid) then return true end
    end
    return false
end
K.taken = taken

-- The first ladder rung that is not technically blocked; rungs the player's filter refuses, and rungs already gone
-- with an earlier cut, are passed over
local function pick_rung(v, fam, part)
    local last = nil
    for _, r in ipairs(P.ladder(fam, part)) do
        if (r.part == part or not taken(v, fam, r.part)) and (r.part == part or P.allowed(fam, r.part)) then
            local ok, why = H.can(v, r.part, r.tech)
            if ok then
                for _, fn in ipairs(K.ext.block) do
                    local okb, reason = pcall(fn, v, r.part, r.tech)
                    if okb and reason then ok, why = false, reason break end
                end
            end
            if ok then return r end
            last = why
        end
    end
    return nil, last
end

-- Decide and dispatch one confirmed blow on a victim record
local function decide(v, b, corpse)
    local ev = corpse and 'corpse_hit' or 'kill'
    local fam = P.family(v)
    if not fam then return skip(v, b, 'no_def') end
    v.def = v.def or fam
    if fam.scope ~= 'in' then return skip(v, b, 'excluded', fam.scope) end
    local okf, on = pcall(P.family_on, fam)
    if okf and on == false then return skip(v, b, 'family_off') end
    if v.party then
        local ok, allow = false, false
        if K.ext.party then ok, allow = pcall(K.ext.party, v, b) end
        if not (ok and allow) then return skip(v, b, 'party_rule') end
    end
    for _, fn in ipairs(K.ext.skip) do
        local ok, reason, why = pcall(fn, v, b, corpse)
        if ok and reason then return skip(v, b, reason, why) end
    end
    local raw = P.locate(v, b)
    local part = raw and P.cut_part(fam, raw) or nil
    local d = CL.decide(b, { corpse = corpse, party = v.party == true, frozen = b.frozen, max_hp = b.max_hp,
        kind = P.kind(fam, part), size = P.size(fam), part = part, allow = P.allow_fn(fam), T = K.T })
    b.cls, b.strength, b.part, b.seared, b.frozen = d.cls, d.strength, d.part, d.seared, d.frozen or b.frozen
    if d.action == 'none' then
        if d.reason == 'kind_off' then return skip(v, b, 'kind_off', d.koff) end        -- never demoted
        record(ev, v, b, { action = 'none', rule = d.rule, why = d.reason })
        BUS.emit(ev, v, b)
        return
    end
    local why = nil
    if SPECIAL[d.action] then
        local w = weapon_of(v, b)
        b.weapon = w
        if w == nil or not (opt('special_weapons') or {})[w] then
            d.was, d.action, why = d.action, 'cut', (w == nil) and 'weapon_unknown' or 'weapon_gate'
            d.part = d.part or part or (P.part(fam, 'head') and 'head') or nil   -- a torso split: the head is last
        end
    end
    local tech = nil
    if CL.PART_ACT[d.action] then
        if not d.part then return skip(v, b, 'no_part', 'no_struck_part') end
        -- gone with an earlier cut (the Part or a Part above it): nothing left to cut there, and never demoted into
        -- the removed subtree (a forearm under a cut arm would get a Cap floating at the collapsed joint)
        if taken(v, fam, d.part) then return skip(v, b, 'already_cut', d.part) end
        local rung, blocked = pick_rung(v, fam, d.part)
        if not rung then return skip(v, b, 'no_part', blocked) end
        if rung.part ~= d.part or rung.tech then d.demoted, why = d.part, why or blocked end
        d.part, tech, b.part = rung.part, rung.tech, rung.part
    end
    if K.ext.tough and d.part then
        local ok, refuse = pcall(K.ext.tough, v, b, d.part)
        if ok and refuse then
            if corpse then return skip(v, b, 'tough') end
            d.tough_ignored = true                     -- the killing blow always cuts
        end
    end
    if corpse then
        local okc, cs = pcall(C.get)
        local ch = okc and type(cs) == 'table' and tonumber(cs.chance) or 1.0
        local vs = st.victims[v.id] or {}
        vs.rng = vs.rng or RNG.new(RNG.seed_from('kill', v.id))       -- seeded per victim: replays stay stable
        if ch < 1 and not vs.rng:chance(ch) then return skip(v, b, 'chance') end
    end
    -- tear_once, on the action actually dispatched: the window opens only here, on a removal, and never extends
    if (d.expl or d.cls == 'explosion') and (CL.PART_ACT[d.action] or CL.WHOLE[d.action]) then
        local vs = st.victims[v.id]
        local who = b.owner or b.killer or b.shell or b.gimmick
        local key = tostring(who or 'shared')
        local t0 = vs and vs.tear and vs.tear[key]
        if t0 and b.gt - t0 < opt('tear_once_s') then
            skip(v, b, 'tear_once', who and 'owner' or 'shared')
            b.action, b.rule, b.once = 'push', d.rule, true   -- push, bleed and wear (b.part) still run
            BUS.emit(ev, v, b)
            return
        end
        if vs then
            vs.tear = vs.tear or {}
            vs.tear[key] = b.gt
            d.once = 'open'                              -- the record shows where a window opened
        end
    end
    b.action, b.rule = d.action, d.rule
    record(ev, v, b, { action = d.action, rule = d.rule, demoted = d.demoted, was = d.was, why = why,
        weapon = b.weapon, tough_ignored = d.tough_ignored, once = d.once })
    if CL.PART_ACT[d.action] then
        local vs = st.victims[v.id]
        if vs then vs.actions = (vs.actions or 0) + 1 end
        local p = P.part(fam, d.part)
        -- hide waits for the Stump Cap; a player who switched Caps off chose open stumps, so nothing is waited for
        -- (else every hide would drop as no_replacement and Caps-off would mean no cuts at all)
        local okc, caps_on = pcall(C.effect, 'caps')
        BUS.emit('cut', v, { part = d.part, tech = tech, root = p and p.root, action = d.action, rule = d.rule,
            blow = b, needs = (okc and caps_on == false) and {} or { 'cap' }, stump = true })
    end
    BUS.emit(ev, v, b)
end

-- One queued blow: 'retry' when the death is not confirmed yet
local function process_one(b)
    local corpse = b.corpse == true
    local v, vs = victim(b)
    if A.valid and not A.valid(v) then return skip(v, b, 'gone') end
    local dead = true
    if A.is_dead then dead = A.is_dead(v) == true
    else once('is_dead', { module = K.name, fn = 'is_dead', why = 'deaths trusted unconfirmed' }) end
    if not corpse then
        if not dead then
            b.retries = (b.retries or 0) + 1
            if b.retries <= opt('confirm_retries') then return 'retry' end
            return skip(v, b, 'not_dead', 'retries')
        end
        if vs.state == 'dead' and b.gt - (vs.gt_dead or -math.huge) < opt('dup_kill_s') then
            return skip(v, b, 'already_cut', 'dup_kill')
        end
        vs.state, vs.gt_dead, vs.f_dead = 'dead', b.gt, b.frame
        v.f_dead, v.gt_dead = b.frame, b.gt      -- living-hit listeners drop blows at or after it (fx_gate after_death)
        count('kills')
    else
        if not dead then count('alive_hit') return end            -- a living character: not a corpse hit
        if vs.state ~= 'dead' then vs.state, vs.gt_dead = 'dead', -math.huge end
        if b.gt - vs.gt_dead < opt('corpse_grace_s') then count('same_blow') return end
        count('corpse_hits')
        if opt('corpse_hits') == false then return skip(v, b, 'off', 'corpse_hits') end
        if b.gt - (vs.gt_hit or -math.huge) < opt('corpse_cooldown_s') then return skip(v, b, 'limit', 'cooldown') end
        vs.gt_hit = b.gt
        if (vs.actions or 0) >= opt('max_actions') then return skip(v, b, 'limit', 'actions') end
    end
    if opt('enabled') == false then return skip(v, b, 'off') end
    if not MO.enabled(K.name) then return skip(v, b, 'modoff') end
    return decide(v, b, corpse)
end

-- The late-phase job: kills before corpse hits, retried kills first, a count and seconds budget, stale on game time
function K.process()
    if not st.queue[1] and not st.retry[1] then return end
    if S.paused then return end
    local kills, corpses = st.retry, {}
    st.retry = {}
    for _, b in ipairs(st.queue) do
        if b.corpse then corpses[#corpses + 1] = b else kills[#kills + 1] = b end
    end
    st.queue = {}
    local clock = A.clock and A.clock.real
    local t0, n, carry, gt = clock and clock() or 0, 0, {}, S.game_time
    for _, group in ipairs({ kills, corpses }) do
        for _, b in ipairs(group) do
            local age = b.corpse and opt('corpse_max_age_s') or opt('kill_max_age_s')
            if n >= opt('max_per_frame') or (n > 0 and clock and clock() - t0 > opt('budget_s')) then
                carry[#carry + 1] = b
            elseif gt - (b.gt or gt) > age then
                count('stale')
                skip(nil, b, 'limit', 'stale')
            else
                n = n + 1
                local ok, r = pcall(process_one, b)
                if not ok then LOG.warn('kill_fault', { err = tostring(r), id = b.id })
                elseif r == 'retry' then st.retry[#st.retry + 1] = b count('retried') end
            end
        end
    end
    for _, b in ipairs(st.queue) do carry[#carry + 1] = b end   -- queued while processing go behind
    st.queue = carry
end

-- Lifecycle. opts: T (classify tables: rules, thresholds; default classify's K.T)
function K.init(adapter, opts)
    opts = opts or {}
    A = adapter or {}
    K.T = opts.T
    st = { queue = {}, retry = {}, victims = {}, stats = {}, warned = {} }
    BUS.on('restore', K.name, function(v)
        local vs = st.victims[v.id]
        if vs then vs.state, vs.actions, vs.tear = 'alive', 0, nil end      -- revived: whole again, no tear window
    end, { teardown = true })
    BUS.on('victim_gone', K.name, function(v) st.victims[v.id] = nil end, { teardown = true })
    MO.feature(K.name, { gameplay = true })
    S.ticker(K.name, K.process)
    return true
end
function K.shutdown()
    S.remove_ticker(K.name)
    BUS.off('restore', K.name)
    BUS.off('victim_gone', K.name)
    st.queue, st.retry = {}, {}
end
-- A map change: queued blows and victim states belong to the old world
function K.reset() st.queue, st.retry, st.victims = {}, {}, {} end
function K.status()
    local s = {}
    for k, x in pairs(st.stats) do s[k] = x end
    s.queue, s.retry = #st.queue, #st.retry
    return s
end
function K.ui_status()
    return string.format('kill: %d kills, %d corpse hits, %d queued', st.stats.kills or 0, st.stats.corpse_hits or 0,
        #st.queue)
end
function K.handoff() return nil end
K.queue = function() return st.queue end

return K
