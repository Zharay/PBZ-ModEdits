-- status: new (offline only; the author's next lab run decides) origin: spec_149 (scratch/menu/spec_149.md), the
-- author 2026-11-01 («launch a workflow for native ingame settings menu and make mode configurable»)
-- modsmenu.lua: LeovvayGore's main settings in the game's own Settings panel through Mods Menu 0.4.2+ (Nexus 149) and
-- its UE4SS bridge PBZModsMenuBridge 0.2.0+. File reads and writes through the adapter fs on a sched ticker: no
-- console command (UE4SS 1185 never passes one to a mod), no loader call, no UFunction.
-- * Files: <dir><folder>.config.json, one flat object of exactly the MENU.MAP keys (any other flat scalar would be an
--   unlabelled menu row) and the read-only "status" (below), written by the bridge after each menu save (the menu
--   sets only the keys it changed in the text it read, so "status" rides along); <dir>menu_seen.json { format = 1,
--   seen }, ours alone (tmp + rename + bak), the file's values as last synced; <bridge>events-<enc>.txt, the menu's
--   change numbers,
--   read only; <config>.new, <bridge>pending-<enc>.json and claimed-<enc>.json, read only, to see a save in flight.
--   No done file is ever written (no action rows: an unreadable done file would block every event of ours).
-- * The A/B settings file (core/config.lua) stays the authority the page documents; the config is a mirror. Per key, a
--   file value that moved since the last sync (the seen mark) applies through C.set (never C.apply_preset); every other
--   key keeps the A/B value. So a hand edit of either side with the game closed wins at the next start, and a menu
--   change made in the last second before a quit (A/B not saved, the seen mark not written) applies again.
-- * Writers: our mod writes the config only in MENU.init at a fresh start (never at a hot reload, never during play;
--   the "status" value aside, below), in place with one whole write (the config never vanishes: the bridge drops a save that finds none): created when
--   the read says missing (errno 2) and no complete .new exists, or rewritten to the effective values when they differ
--   from it, it holds other keys or the menu cannot read it (not JSON, not an object, 10 bytes or fewer), and no save
--   is in flight (no .new, pending or claimed file). During play only the bridge writes it, apart from "status".
-- * The poll (ticker 'menu_poll', every frame, rate-limited on the real clock): the events file every POLL_S, and a
--   Changed= number above the last handled (in a file with its End=1 line) reads the config at once; the config text
--   every CONTENT_S anyway (hand edits, no bridge). A changed text is parsed and synced; a missing or locked config is
--   read again later and never created. The seen mark is written once C.dirty() is false (the A/B save is done).
--   The bridge is probed once, in init: with no events file and no <bridge>Scripts/main.lua (both missing, errno 2)
--   the events file is never polled that session; the content poll stays.
-- * The descriptor's language (the author 2026-11-02: Chinese and Vietnamese by the game's language). Mods Menu 0.4.2
--   shows each text in en, zh-Hans or zh-Hant by the game's culture and en for any other, and reads
--   <folder>.modsmenu.json again at every Settings open. The shipped descriptor holds en, zh-Hans and zh-Hant. A
--   second shipped copy, <folder>.modsmenu.vi.json, holds the Vietnamese in the en fields (both Chinese scripts kept,
--   the toggles as Tat/Bat choices of true and false); <folder>.modsmenu.en.json is the shipped descriptor byte for
--   byte (the way back with no network and no repo). At a fresh start only (never at a hot reload), before any
--   Settings open, the culture comes from the game's GameUserSettings.ini (opts.ini; MENU.culture), never from a
--   UFunction: vi (MENU.lang) takes the vi copy, any other the en copy, and the descriptor is written from it only when
--   its text differs, through STORE.put_atomic (tmp + rename + bak: one complete descriptor at every moment). No
--   culture, a copy that is not one ASCII JSON object with settings, or a descriptor that cannot be read: left alone;
--   with no culture, a missing descriptor (a crash between put_atomic's renames) gets the en copy. A culture changed
--   during play shows from the next start.
-- * The Status row (the author 2026-11-03: «maybe we can show some status in our settings if something went wrong?»):
--   the descriptor's first row is { type = 'readonly', key = 'status' }; Mods Menu 0.4.2 shows a UE4SS mod's read-only
--   row as String() of the config's value (readMod, fromRaw, label: a language object would read [object Object]), so
--   "status" is one plain string in the game's text language (MENU.text_lang: the menu's own lang() rule of the ini's
--   culture, vi for the vi descriptor). The word (MENU.word, first match): the mod off (Ctrl+F8), the vanilla compare,
--   no pin answer yet, the loader pin failed, the game build or ARM key pin failed, the loader waiver, a counted
--   disabled sentinel name (opts.known, MENU.known), else all on. opts.status() gives { off, vanilla, pin, disabled }
--   from module state (no engine call); the poll asks it every STATUS_S, and a new word reads the config at once. The
--   key is written only when the file's value differs, the config parses and no save is in flight: the text read now
--   with that one member's value replaced, or added as the first member (MENU.with_status: every other byte kept),
--   in place with one whole write as the start writes (put_atomic would leave no config for a moment, and the bridge
--   drops a save that finds none). Never created, never written while it does not parse. The poll then knows the text
--   (no sync, no record). Only with a bridge (P.ev, as the events poll): without one a "status" key is dropped by the
--   start rewrite like any other key outside MAP. The start writes (create, rewrite) carry the word of that moment; a
--   quiet start writes nothing, and the poll's first ask, STATUS_S later, writes the word only if the file's differs.
-- API: init(A, opts) tick([now]) shutdown status reset; pure parse(text) render(values[, status]) value(entry, raw)
--   effective(s) enc(name) culture(ini_text) lang(culture) text_lang(culture) word(s, known) say(id, lang)
--   known(names, hooks, quiet) json_text(s) with_status(text, value); tables MAP, WORDS, POLL_S, CONTENT_S, STATUS_S.
--   opts: dir (E.data), folder (E.folder), bridge (the bridge folder with its slash; nil: no events), reloaded
--   (E.reloaded), ticker (false: the caller calls MENU.tick), ini (the game's GameUserSettings.ini; nil: the
--   descriptor is left alone unless it is missing), status (the Status row's source; nil: no row), known (the counted
--   disabled names, a set; nil: every name counts).
-- Records: menu_start { config, set, rewrote, skip, seen, n } (or { on = false, why }), menu_apply { via start|event|
--   file, n, set }, menu_config_bad { why } (once per text), menu_write_fail { file, err } (once per file),
--   menu_lang { culture, lang, wrote, why } (fresh starts only; why: no_ini, ini_missing, ini_unreadable, no_culture,
--   template, locked, write_fail; none when the descriptor already matched or was written from the culture; with no
--   culture, lang = 'en' and wrote = true when a missing descriptor got the en copy).
-- Evidence: spec_149 sections 2-4 (the menu's reading rules from its own script 0.4.2 and the bridge's main.lua 0.2.0,
--   read only); core/dev.lua's file-drop poll on a sched ticker [worked DD2]. The language: the menu's lang(), LANGS,
--   text(), checkSetting() and discover() at each open (scratch/menu/pak_extract/DebugLoadServerGame.js.txt:869-944,
--   1046-1061, 1453-1459); the game's vi Game.locres (scratch/menu/vi/list_localization.txt:77); CultureName=en-us in
--   [/Script/ProjectPBZ.PBZSettingsLocal] of the author's GameUserSettings.ini. The Status row: the menu's readonly
--   rows (974), readMod (1159-1181), fromRaw (781-798), label (810-820) and show (1711-1731), its save of a UE4SS
--   config (1221-1245: JSON.parse of the file, the changed keys set, JSON.stringify with \u escapes) and refresh
--   (1877-1890). Offline only: tests/test_modsmenu.lua.
local STORE = require('core.store')
local LOG = require('core.log')
local S = require('core.sched')
local C = require('core.config')

local MENU = { POLL_S = 0.5, CONTENT_S = 2, STATUS_S = 1 }

-- ---------- the rows: flat key, the C path (default the key), the file rule, the effective value ----------
local K = C.KNOBS
local function knob(key) return function(s) return C.knob(key, s) end end
-- The stored value under the file rule, else the default (lab_blood reads these raw)
local function stored(s, e)
    local v = MENU.value(e, s[e.key])
    if v == nil then v = C.DEFAULTS[e.key] end
    return v
end
local function knob_num(key)
    local k = K[key]
    return { key = key, kind = 'num', lo = k.lo, hi = k.hi, int = k.int, eff = knob(key) }
end
-- In descriptor order (LeovvayGore.modsmenu.json). kind bool | num (lo, hi clamp; int floors first; min: below it the
-- value is no opinion, no clamp) | word (words)
MENU.MAP = {
    { key = 'effects_blood', path = 'effects.blood', kind = 'bool', eff = function(s)
        local x = nil
        if type(s.effects) == 'table' then x = s.effects.blood end
        return x ~= false and x ~= 'off'
    end },
    { key = 'blood_amount', kind = 'num', lo = 0.75, hi = 9, eff = stored },   -- lab_blood: d = v / 3, 0.25..3
    { key = 'drops', kind = 'bool', eff = knob('drops') },
    { key = 'soul_blood', kind = 'bool', eff = knob('soul_blood') },
    { key = 'soul_face_blood', kind = 'bool', eff = knob('soul_face_blood') },   -- lab_blood: the face bones skipped
    { key = 'sword_blood', kind = 'bool', eff = knob('sword_blood') },         -- lab_sword: blood on Soul's weapons
    { key = 'soul_blood_life_s', kind = 'num', min = 0, eff = stored },       -- lab_blood, lab_sword: under 0 reads 300
    { key = 'wash_on_heal', kind = 'bool', eff = function(s) return s.wash_on_heal ~= false end },
    knob_num('cut_chance'),                     -- lab_plan: the percent of eligible kills that cut (fixes-0.2.2 F2)
    knob_num('max_parts'), knob_num('heavy_parts'), knob_num('shaqi_parts'),
    { key = 'hair_mode', kind = 'word', words = K.hair_mode.words, eff = knob('hair_mode') },
    { key = 'extras_fall', kind = 'bool', eff = knob('extras_fall') },
    -- lab_probe pin_check: the loader waiver (fixes-0.2.2 F4), read once per session: the next game start
    { key = 'other_ue4ss', kind = 'bool', eff = knob('other_ue4ss') },
    { key = 'override_versions', kind = 'bool', eff = knob('override_versions') },
    { key = 'cap_look', kind = 'word', words = K.cap_look.words, eff = knob('cap_look') },
    knob_num('cap_scale'), knob_num('corpse_keep_s'),
}
local BY_KEY = {}
for _, e in ipairs(MENU.MAP) do BY_KEY[e.key] = e end

-- ---------- pure ----------
local BOOL = { on = true, ['true'] = true, yes = true, ['1'] = true, off = false, ['false'] = false, no = false,
    ['0'] = false }
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- A file value under the menu's own reading: bool a boolean, a switch word (any case) or 1/0; num a finite number or a
-- numeric string ('2,5', 'x2'), floored for int, clamped to lo..hi, nil under min; word a word of the set (any case).
-- Anything else is nil (no opinion)
function MENU.value(e, raw)
    local t = type(raw)
    if e.kind == 'bool' then
        if t == 'boolean' then return raw end
        if t == 'number' then
            if raw == 1 then return true elseif raw == 0 then return false end
            return nil
        end
        if t == 'string' then return BOOL[trim(raw):lower()] end
        return nil
    end
    if e.kind == 'word' then
        if t ~= 'string' then return nil end
        local w = trim(raw):lower()
        if e.words[w] then return w end
        return nil
    end
    local v = nil
    if t == 'number' then v = raw
    elseif t == 'string' then v = tonumber((trim(raw):gsub(',', '.', 1):gsub('^[xX]', ''))) end
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
    if e.min and v < e.min then return nil end
    if e.int then v = math.floor(v) end
    if e.lo and v < e.lo then v = e.lo end
    if e.hi and v > e.hi then v = e.hi end
    return v
end

-- The flat values the mod runs with, from a settings table (C.get(), or DEFAULTS)
function MENU.effective(s)
    if type(s) ~= 'table' then s = {} end
    local out = {}
    for _, e in ipairs(MENU.MAP) do out[e.key] = e.eff(s, e) end
    return out
end

-- A number token as JSON.parse takes it: -?(0|[1-9]digits)(.digits)?([eE][+-]?digits)?. STORE.decode is looser ('03',
-- '2.', '1.e0'); the menu refuses those and never saves the file again, so MENU.parse must refuse them too (and the
-- start then rewrites the file). STORE.decode itself stays as it is: the A/B settings reader uses it.
local function json_number(tok)
    local int, rest = tok:match('^%-?(%d+)(.*)$')
    if not int or (#int > 1 and int:sub(1, 1) == '0') then return false end
    if rest:sub(1, 1) == '.' then
        rest = rest:match('^%.%d+(.*)$')
        if not rest then return false end
    end
    return rest == '' or rest:match('^[eE][%+%-]?%d+$') ~= nil
end

-- true when every number token outside strings is valid JSON
local function strict_numbers(text)
    local i, n = 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == '"' then
            i = i + 1
            while i <= n do
                local d = text:sub(i, i)
                if d == '\\' then i = i + 2
                elseif d == '"' then break
                else i = i + 1 end
            end
            i = i + 1
        elseif c == '-' or c:match('%d') then
            local tok = text:match('^[%-%+%deE%.]+', i)
            if not json_number(tok) then return false end
            i = i + #tok
        else
            i = i + 1
        end
    end
    return true
end

-- F (MAP key -> value, nil when absent or no opinion), nil, the keys outside MAP and "status" (sorted, nil when none),
-- the "status" value as decoded (nil when absent); or nil, why: 'short' (10 bytes or fewer after a UTF-8 BOM: the menu
-- does not list the mod then), 'json', 'not_object'
function MENU.parse(text)
    if type(text) ~= 'string' then return nil, 'json' end
    if text:sub(1, 3) == '\239\187\191' then text = text:sub(4) end
    if #text < 11 then return nil, 'short' end
    local t, err = STORE.decode(text)
    if err or not strict_numbers(text) then return nil, 'json' end
    if type(t) ~= 'table' or not text:find('^%s*{') then return nil, 'not_object' end
    local F, extra = {}, nil
    for _, e in ipairs(MENU.MAP) do F[e.key] = MENU.value(e, t[e.key]) end
    for k in pairs(t) do
        if not BY_KEY[k] and k ~= 'status' then
            extra = extra or {}
            extra[#extra + 1] = tostring(k)
        end
    end
    if extra then table.sort(extra) end
    return F, nil, extra, t.status
end

-- A JSON string as the menu writes one (JSON.stringify's escapes, then \u and four lowercase hex digits for U+007F
-- and up, a surrogate pair past U+FFFF): ASCII, so the text ends in its CRLF in any encoding. s is UTF-8
local JS_ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r',
    ['\t'] = '\\t' }
function MENU.json_text(s)
    local out = {}
    for _, cp in utf8.codes(s) do
        local c = cp < 128 and string.char(cp) or nil
        if c and JS_ESC[c] then
            out[#out + 1] = JS_ESC[c]
        elseif cp < 32 or cp >= 127 then
            if cp > 0xFFFF then
                local v = cp - 0x10000
                out[#out + 1] = string.format('\\u%04x\\u%04x', 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
            else
                out[#out + 1] = string.format('\\u%04x', cp)
            end
        else
            out[#out + 1] = c
        end
    end
    return '"' .. table.concat(out) .. '"'
end

-- The config text: JSON.stringify(obj, null, 2) plus the menu's CRLF, so a menu save that changes nothing gives the
-- same text. "status" first when given (the descriptor's first row), then MAP order; an integer-valued number as an
-- integer (3, not 3.0), any other number %.14g
function MENU.render(values, status)
    local lines = {}
    if type(status) == 'string' then lines[1] = '  "status": ' .. MENU.json_text(status) end
    for _, e in ipairs(MENU.MAP) do
        local v, t = values[e.key], nil
        if type(v) == 'boolean' then t = v and 'true' or 'false'
        elseif type(v) == 'number' then
            local i = math.tointeger(v)
            t = i and string.format('%d', i) or string.format('%.14g', v)
        elseif type(v) == 'string' then t = STORE.encode(v) end
        if t then lines[#lines + 1] = '  ' .. STORE.encode(e.key) .. ': ' .. t end
    end
    return '{\n' .. table.concat(lines, ',\n') .. '\n}\r\n'
end

-- The bridge's file-name encoding: letters, digits and _ stay, every other byte is % and two lowercase hex digits
function MENU.enc(name)
    return (tostring(name):gsub('[^%w_]', function(c) return string.format('%%%02x', c:byte()) end))
end

-- The game's text language from the text of its GameUserSettings.ini, in lower case ('en-us', 'vi', 'zh-hans'), or nil
-- when none is set: [/Script/ProjectPBZ.PBZSettingsLocal] CultureName=, the game's own (its Settings write it), else
-- the engine's [Internationalization] Culture=. Sections and keys in any case, the last line of a key wins (UE's config
-- reader); a blank or odd value counts as none. A UTF-16LE file (UE saves an ini so when a value is not ASCII) is read
-- by its ASCII characters
local PBZ_SEC, I18N_SEC = '/script/projectpbz.pbzsettingslocal', 'internationalization'
function MENU.culture(text)
    if type(text) ~= 'string' then return nil end
    if text:sub(1, 2) == '\255\254' then
        text = text:sub(3):gsub('(.)(.)', function(lo, hi) return hi == '\0' and lo or '?' end)
    elseif text:sub(1, 3) == '\239\187\191' then
        text = text:sub(4)
    end
    local sec, found = nil, {}
    for line in text:gmatch('[^\r\n]+') do
        local s = line:match('^%s*%[(.-)%]%s*$')
        if s then
            sec = s:lower()
        elseif sec == PBZ_SEC or sec == I18N_SEC then
            local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
            k = k and k:lower()
            if (sec == PBZ_SEC and k == 'culturename') or (sec == I18N_SEC and k == 'culture') then
                v = v:match('^"(.*)"$') or v
                found[sec] = #v <= 32 and v:match('^%a%a%a?[%w%-_]*$') and v:lower() or false
            end
        end
    end
    return found[PBZ_SEC] or found[I18N_SEC] or nil
end

-- The descriptor copy a culture gets: 'vi' for Vietnamese (vi, vi-VN), 'en' (en, zh-Hans, zh-Hant) for any other
function MENU.lang(culture)
    if type(culture) == 'string' and (culture == 'vi' or culture:find('^vi[%-_]')) then return 'vi' end
    return 'en'
end

-- ---------- the Status row (pure) ----------
-- The language of the Status text for a culture: the menu's lang() (zh-Hant for zh-hant, zh-tw, zh-hk and zh-mo,
-- zh-Hans for any other zh and the game's he, its Simplified Chinese; en for the rest), and vi where MENU.lang takes
-- the vi descriptor (its en texts are Vietnamese)
function MENU.text_lang(culture)
    if type(culture) ~= 'string' then return 'en' end
    local c = culture:lower()
    if MENU.lang(c) == 'vi' then return 'vi' end
    if c:find('^zh%-hant') or c:find('^zh%-tw') or c:find('^zh%-hk') or c:find('^zh%-mo') then return 'zh-Hant' end
    if c:find('^zh') or c == 'he' or c:find('^he%-') then return 'zh-Hans' end
    return 'en'
end

-- The words, one short line each (the menu's value box): en within 24 characters, Chinese as the descriptor writes
-- it, vi with the vi descriptor's terms (Chem Dut for cuts, ban UE4SS, tro choi)
MENU.WORDS = {
    off = { en = 'Mod off (Ctrl+F8)', ['zh-Hans'] = '\u{6A21}\u{7EC4}\u{5DF2}\u{5173}\u{95ED}\u{FF08}Ctrl+F8\u{FF09}',
        ['zh-Hant'] = '\u{6A21}\u{7D44}\u{5DF2}\u{95DC}\u{9589}\u{FF08}Ctrl+F8\u{FF09}',
        vi = 'Mod \u{111}\u{E3} t\u{1EAF}t (Ctrl+F8)' },
    vanilla = { en = 'Game look (Shift+F7)', ['zh-Hans'] = '\u{539F}\u{7248}\u{753B}\u{9762}\u{FF08}Shift+F7\u{FF09}',
        ['zh-Hant'] = '\u{539F}\u{7248}\u{756B}\u{9762}\u{FF08}Shift+F7\u{FF09}',
        vi = 'H\u{EC}nh \u{1EA3}nh g\u{1ED1}c (Shift+F7)' },
    starting = { en = 'Starting', ['zh-Hans'] = '\u{6B63}\u{5728}\u{542F}\u{52A8}',
        ['zh-Hant'] = '\u{6B63}\u{5728}\u{555F}\u{52D5}', vi = '\u{110}ang kh\u{1EDF}i \u{111}\u{1ED9}ng' },
    ue4ss = { en = 'Cuts off: UE4SS build',
        ['zh-Hans'] = '\u{65AD}\u{80A2}\u{5DF2}\u{5173}\u{95ED}\u{FF1A}UE4SS \u{7248}\u{672C}',
        ['zh-Hant'] = '\u{65B7}\u{80A2}\u{5DF2}\u{95DC}\u{9589}\u{FF1A}UE4SS \u{7248}\u{672C}',
        vi = 'T\u{1EAF}t ch\u{E9}m \u{111}\u{1EE9}t: b\u{1EA3}n UE4SS' },
    game = { en = 'Cuts off: game version',
        ['zh-Hans'] = '\u{65AD}\u{80A2}\u{5DF2}\u{5173}\u{95ED}\u{FF1A}\u{6E38}\u{620F}\u{7248}\u{672C}',
        ['zh-Hant'] = '\u{65B7}\u{80A2}\u{5DF2}\u{95DC}\u{9589}\u{FF1A}\u{904A}\u{6232}\u{7248}\u{672C}',
        vi = 'T\u{1EAF}t ch\u{E9}m \u{111}\u{1EE9}t: b\u{1EA3}n tr\u{F2} ch\u{1A1}i' },
    waived = { en = 'Untested UE4SS build', ['zh-Hans'] = 'UE4SS \u{7248}\u{672C}\u{672A}\u{7ECF}\u{6D4B}\u{8BD5}',
        ['zh-Hant'] = 'UE4SS \u{7248}\u{672C}\u{672A}\u{7D93}\u{6E2C}\u{8A66}',
        vi = 'B\u{1EA3}n UE4SS ch\u{1B0}a th\u{1EED} nghi\u{1EC7}m' },
    effects = { en = 'Some effects off', ['zh-Hans'] = '\u{90E8}\u{5206}\u{6548}\u{679C}\u{5DF2}\u{5173}\u{95ED}',
        ['zh-Hant'] = '\u{90E8}\u{5206}\u{6548}\u{679C}\u{5DF2}\u{95DC}\u{9589}',
        vi = '\u{110}\u{E3} t\u{1EAF}t m\u{1ED9}t s\u{1ED1} hi\u{1EC7}u \u{1EE9}ng' },
    override = { en = 'Version checks bypassed',
        ['zh-Hans'] = '\u{5DF2}\u{8DF3}\u{8FC7}\u{7248}\u{672C}\u{68C0}\u{67E5}',
        ['zh-Hant'] = '\u{5DF2}\u{7565}\u{904E}\u{7248}\u{672C}\u{6AA2}\u{67E5}',
        vi = 'B\u{1ECF} qua ki\u{1EC3}m tra phi\u{EA}n b\u{1EA3}n' },
    all = { en = 'All on', ['zh-Hans'] = '\u{5168}\u{90E8}\u{5F00}\u{542F}', ['zh-Hant'] = '\u{5168}\u{90E8}\u{958B}\u{555F}',
        vi = 'T\u{1EA5}t c\u{1EA3} \u{111}\u{1EC1}u b\u{1EAD}t' },
}

-- The word id for s = { off, vanilla, pin, disabled } (main.lua's source), first match: off, vanilla, starting (no pin
-- answer yet: pin nil), ue4ss (pin 'loader'), game (pin 'game'), waived, effects (a disabled name known counts; known
-- nil: any name), override, all. pin 'none' (no beta pin check) and 'pinned' go on to the disabled names.
-- The override warning also yields to disabled effects. nil for no table
function MENU.word(s, known)
    if type(s) ~= 'table' then return nil end
    if s.off then return 'off' end
    if s.vanilla then return 'vanilla' end
    local pin = s.pin
    if pin == nil then return 'starting' end
    if pin == 'loader' then return 'ue4ss' end
    if pin == 'game' then return 'game' end
    if pin == 'waived' then return 'waived' end
    for _, n in ipairs(type(s.disabled) == 'table' and s.disabled or {}) do
        if known == nil or known[n] then return 'effects' end
    end
    if pin == 'override' then return 'override' end
    return 'all'
end

-- The text of word id in lang (MENU.text_lang), en when that language has none; nil for an unknown id
function MENU.say(id, lang)
    local w = MENU.WORDS[id]
    return w and (w[lang] or w.en) or nil
end

-- The disabled names the Status row counts, as a set: every name of names (META.lab_risky: the guarded calls the
-- build makes, where a retired name such as slicer.cut.lod is never listed again) and 'hook:<id>' for every key of
-- hooks (data/hooks.lua's hooks), less the names of quiet (META.status_quiet: calls no player effect depends on)
function MENU.known(names, hooks, quiet)
    local q, out = {}, {}
    for _, n in ipairs(type(quiet) == 'table' and quiet or {}) do q[n] = true end
    for _, n in ipairs(type(names) == 'table' and names or {}) do
        if type(n) == 'string' and not q[n] then out[n] = true end
    end
    for id in pairs(type(hooks) == 'table' and hooks or {}) do
        local n = 'hook:' .. tostring(id)
        if not q[n] then out[n] = true end
    end
    return out
end

-- The config text with its top-level "status" set to the string value and every other byte as it was: the value of
-- each "status" member replaced in place (JSON.parse takes the last of a repeated key), else a first member added
-- with the text's own spacing before its first key. nil for a text MENU.parse refuses. Scans one object MENU.parse
-- took (strict JSON), so a string ends at its unescaped quote and a value at the next , } or ] outside one
local function str_end(t, k)                            -- k at the opening quote: the index after the closing one
    local j, n = k + 1, #t
    while j <= n do
        local c = t:sub(j, j)
        if c == '\\' then j = j + 2
        elseif c == '"' then return j + 1
        else j = j + 1 end
    end
    return nil
end
local function value_end(t, k)                          -- k at a value's first byte: the index after it
    local c = t:sub(k, k)
    if c == '"' then return str_end(t, k) end
    if c ~= '{' and c ~= '[' then return t:find('[%s,}%]]', k) end
    local depth, j, n = 0, k, #t
    while j <= n do
        local d = t:sub(j, j)
        if d == '"' then
            j = str_end(t, j)
            if not j then return nil end
        else
            if d == '{' or d == '[' then depth = depth + 1 elseif d == '}' or d == ']' then depth = depth - 1 end
            j = j + 1
            if depth == 0 then return j end
        end
    end
    return nil
end
function MENU.with_status(text, value)
    if type(value) ~= 'string' or not MENU.parse(text) then return nil end
    local bom = ''
    if text:sub(1, 3) == '\239\187\191' then bom, text = text:sub(1, 3), text:sub(4) end
    local open = text:find('{', 1, true)
    local p, first, spans, close = open + 1, nil, {}, nil
    while true do
        local q = text:find('[^ \t\r\n]', p)
        if not q then return nil end
        local c = text:sub(q, q)
        if c == '}' then close = q break end
        if c == ',' then
            p = q + 1
        elseif c == '"' then
            local ke = str_end(text, q)
            local colon = ke and text:find(':', ke, true)
            local vs = colon and text:find('[^ \t\r\n]', colon + 1)
            local ve = vs and value_end(text, vs)
            if not ve then return nil end
            first = first or q
            if STORE.decode(text:sub(q, ke - 1)) == 'status' then spans[#spans + 1] = { vs, ve } end
            p = ve
        else
            return nil
        end
    end
    local v = MENU.json_text(value)
    if spans[1] then
        for i = #spans, 1, -1 do text = text:sub(1, spans[i][1] - 1) .. v .. text:sub(spans[i][2]) end
    elseif first then
        text = text:sub(1, first - 1) .. '"status": ' .. v .. ',' .. text:sub(open + 1, first - 1) .. text:sub(first)
    else
        text = text:sub(1, open) .. '\n  "status": ' .. v .. '\n' .. text:sub(close)
    end
    return bom .. text
end

-- A descriptor text the menu takes: ASCII only (\u escapes), over 10 bytes, one JSON object with a settings list
local function descriptor_ok(text)
    if type(text) ~= 'string' or #text < 11 or text:find('[^\t\n\r\32-\126]') then return false end
    local t = STORE.decode(text)
    return type(t) == 'table' and type(t.settings) == 'table' and #t.settings > 0
end

local function eq(a, b)
    if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) <= 1e-9 end
    return a == b
end
local function same(a, b)
    for _, e in ipairs(MENU.MAP) do if not eq(a[e.key], b[e.key]) then return false end end
    return true
end
local function copy(t)
    local o = {}
    for _, e in ipairs(MENU.MAP) do o[e.key] = t[e.key] end
    return o
end
-- The Changed= number of an events file whose End=1 line is written (13-digit milliseconds), else nil
local function changed(text)
    local m = type(text) == 'string' and text:find('\nEnd=1', 1, true) and text:match('\nChanged=(%d+)')
    return m and math.tointeger(tonumber(m)) or nil
end

-- ---------- state ----------
local A, fs, on = nil, nil, false
local P = {}                                            -- paths: cfg, new, seen, ev, pending, claimed
local last_n, want_n, next_ev, next_cfg = 0, nil, 0, 0
local last_text, base, seen_want, seen_last, seen_next = nil, {}, nil, nil, 0
local applies, bad_why, warned = 0, nil, {}
-- the Status row: its source and counted names, the text language, the word wanted (id and text), the last parsed
-- text's state (cfg_ok: it parsed; file_status: its "status" value), the next ask, the writes made
local status_fn, known, status_lang, want_id, status_want = nil, nil, 'en', nil, nil
local cfg_ok, file_status, next_status, status_writes, ini_seen = false, nil, 0, 0, nil

local function real() return A.clock.real() end
-- The text, or nil and the errno fs.read gives (adapter/env.lua; a missing path reads as missing, a raise as 'raise')
local function read(path)
    if not path then return nil, 2 end
    local ok, t, err = pcall(fs.read, path)
    if not ok then return nil, 'raise' end
    if type(t) ~= 'string' then return nil, err end
    return t
end
local function write_fail(file, err)
    if warned[file] then return end
    warned[file] = true
    LOG.warn('menu_write_fail', { file = file, err = tostring(err) })
end
local function bad(why)
    bad_why = why
    LOG.warn('menu_config_bad', { why = why })
end
local function seen_read()
    local t = STORE.read_atomic(fs, P.seen)
    if type(t) ~= 'table' or t.format ~= 1 or type(t.seen) ~= 'table' then return nil end
    local out = {}
    for _, e in ipairs(MENU.MAP) do out[e.key] = MENU.value(e, t.seen[e.key]) end
    return out
end
-- A save in flight: the first of the .new, pending and claimed files that is there (or unreadable), else nil
local function busy()
    for _, k in ipairs({ 'new', 'pending', 'claimed' }) do
        local t, err = read(P[k])
        if t ~= nil or err ~= 2 then return k end
    end
    return nil
end

-- The descriptor in the game's text language (a fresh start only): the culture's copy, written over the descriptor
-- only when the texts differ (a missing descriptor too); one menu_lang record
local function lang_start(ini)
    local r = { wrote = false }
    local text, err = read(ini)
    r.culture = MENU.culture(text)
    ini_seen = { culture = r.culture }                  -- the Status text's language, without a second read
    if not r.culture then
        r.why = (not ini and 'no_ini') or (text == nil and (err == 2 and 'ini_missing' or 'ini_unreadable'))
            or 'no_culture'
        -- no culture, but no descriptor either (a crash between put_atomic's two renames): the en copy, the shipped one
        local _, cur_err = read(P.desc)
        if cur_err == 2 then
            local en = read(P.tpl .. 'en.json')
            if descriptor_ok(en) then
                local ok, werr = STORE.put_atomic(fs, P.desc, en)
                if ok then r.lang, r.wrote = 'en', true else write_fail('descriptor', werr) end
            end
        end
    else
        r.lang = MENU.lang(r.culture)
        local want = read(P.tpl .. r.lang .. '.json')
        local cur, cur_err = read(P.desc)
        if not descriptor_ok(want) then
            r.why = 'template'
        elseif cur ~= want then
            if cur == nil and cur_err ~= 2 then
                r.why = 'locked'
            else
                local ok, werr = STORE.put_atomic(fs, P.desc, want)
                if ok then r.wrote = true else
                    r.why = 'write_fail'
                    write_fail('descriptor', werr)
                end
            end
        end
    end
    LOG.info('menu_lang', r)
    return r
end

-- The file's values F against the baseline (the file as last synced) and the effective values: a key whose file value
-- moved and differs from what the mod runs with applies; then the baseline is F
local function sync(F, via, n)
    local V = MENU.effective(C.get())
    local set = nil
    for _, e in ipairs(MENU.MAP) do
        local f = F[e.key]
        if f ~= nil and not eq(f, base[e.key]) and not eq(f, V[e.key]) then
            C.set(e.path or e.key, f)
            set = set or {}
            set[e.key] = f
        end
    end
    base, seen_want, bad_why = copy(F), copy(F), nil
    if set then
        applies = applies + 1
        LOG.info('menu_apply', { via = via, n = n, set = set })
    end
    return set
end

-- The seen mark, once the A/B save of what was applied is done; a failed write is tried again a content poll later
local function seen_step(now)
    if not seen_want or C.dirty() or now < seen_next then return end
    if seen_last == nil or not same(seen_want, seen_last) then
        local ok, err = STORE.write_atomic(fs, P.seen, { format = 1, seen = seen_want })
        if not ok then
            write_fail('seen', err)
            seen_next = now + MENU.CONTENT_S
            return
        end
        seen_last = seen_want
    end
    seen_want = nil
end

-- ---------- the Status row ----------
-- The word now (id, text in status_lang), or nil when the source raises or gives nothing
local function status_word()
    local ok, s = pcall(status_fn)
    if not ok then return nil end
    local id = MENU.word(s, known)
    if not id then return nil end
    return id, MENU.say(id, status_lang)
end
-- The config text just read: "status" set to the word when the file holds another value, the text parsed and no
-- save is in flight; a failed write is tried again at the next content poll (one menu_write_fail)
local function status_put(text)
    if not status_want or not cfg_ok or file_status == status_want or busy() then return end
    local t = MENU.with_status(text, status_want)
    if not t then return end
    local ok, err = STORE.put(fs, P.cfg, t)
    if not ok then return write_fail('config', err) end
    last_text, file_status, status_writes = t, status_want, status_writes + 1
end

-- ---------- the poll ----------
function MENU.tick(now)
    if not on then return end
    now = now or real()
    if P.ev and now >= next_ev then                     -- every POLL_S
        next_ev = now + MENU.POLL_S
        local n = changed((read(P.ev)))
        if n and n > last_n then want_n, next_cfg = n, now end
    end
    if status_fn and now >= next_status then            -- every STATUS_S: a new word reads the config at once
        next_status = now + MENU.STATUS_S
        local id, w = status_word()
        if w and w ~= status_want then want_id, status_want, next_cfg = id, w, now end
    end
    if now >= next_cfg then                             -- every CONTENT_S, or at once after a new number or word
        local text = read(P.cfg)
        if text == nil then                             -- gone mid-swap or locked: read again, never created here
            next_cfg = now + (want_n and MENU.POLL_S or MENU.CONTENT_S)
        else
            next_cfg = now + MENU.CONTENT_S
            if text ~= last_text then
                last_text = text
                local F, why, _, fst = MENU.parse(text)
                cfg_ok, file_status = F ~= nil, fst
                if F then sync(F, want_n and 'event' or 'file', want_n) else bad(why) end
            end
            if want_n then last_n, want_n = want_n, nil end
            status_put(text)
        end
    end
    seen_step(now)
end

-- ---------- lifecycle ----------
-- Right after C.init (main.lua's body). Off (one menu_start { on = false, why = 'no_dir' }) without a data folder
function MENU.init(adapter, opts)
    opts = opts or {}
    A, fs = adapter, adapter and adapter.fs
    on, applies, bad_why, warned, P = false, 0, nil, {}, {}
    last_n, want_n, last_text, base, seen_want, seen_last, seen_next = 0, nil, nil, {}, nil, nil, 0
    status_fn, known, status_lang, want_id, status_want = nil, nil, 'en', nil, nil
    cfg_ok, file_status, next_status, status_writes, ini_seen = false, nil, 0, 0, nil
    local dir = opts.dir or ''
    if dir == '' then
        LOG.info('menu_start', { on = false, why = 'no_dir' })
        return true
    end
    if not dir:find('[\\/]$') then dir = dir .. '/' end
    local folder = opts.folder or 'LeovvayGore'
    P.cfg, P.seen = dir .. folder .. '.config.json', dir .. 'menu_seen.json'
    P.new = P.cfg .. '.new'
    P.desc, P.tpl = dir .. folder .. '.modsmenu.json', dir .. folder .. '.modsmenu.'
    if opts.bridge then
        local b, enc = opts.bridge, MENU.enc(folder)
        P.ev, P.pending, P.claimed = b .. 'events-' .. enc .. '.txt', b .. 'pending-' .. enc .. '.json',
            b .. 'claimed-' .. enc .. '.json'
    end
    on = true
    local fresh = opts.reloaded ~= true
    -- 0. the descriptor's language, at a fresh start only (by a hot reload Settings may have read it already)
    if fresh then lang_start(opts.ini) end
    -- 1. the events number first: a save that lands before the config read gets a higher one, which the poll acts on.
    --    No events file yet and no bridge (its Scripts/main.lua missing too): no events poll this session
    local ev, ev_err = read(P.ev)
    if P.ev and ev_err == 2 then
        local _, br_err = read(opts.bridge .. 'Scripts/main.lua')
        if br_err == 2 then P.ev = nil end
    end
    last_n = changed(ev) or 0
    -- 1b. the Status row: with a source and the bridge; its language from the ini lang_start read (else read now: a
    --     hot reload), the word of this moment for the start's own writes (the poll's first ask decides the rest)
    local w0 = nil
    if type(opts.status) == 'function' and P.ev then
        status_fn, known = opts.status, type(opts.known) == 'table' and opts.known or nil
        local culture = ini_seen and ini_seen.culture
        if not ini_seen and opts.ini then culture = MENU.culture((read(opts.ini))) end
        status_lang = MENU.text_lang(culture)
        w0 = select(2, status_word())
    end
    -- 2. the seen mark: the baseline
    local seen = seen_read()
    base, seen_last = seen and copy(seen) or {}, seen
    -- 3. the config
    local V = MENU.effective(C.get())
    local text, err = read(P.cfg)
    local F, extra, source, skip, rewrote, set, fst = nil, nil, nil, nil, false, nil, nil
    if text then
        local why
        F, why, extra, fst = MENU.parse(text)
        last_text, source, cfg_ok, file_status = text, F and 'config' or 'bad', F ~= nil, fst
        if not F then bad(why) end
    elseif err == 2 then
        local nt = read(P.new)
        local NF, _, _, nst = MENU.parse(nt)
        if NF then                                      -- the bridge was mid-swap: it finishes it; never created now
            F, source, last_text, cfg_ok, file_status = NF, 'new', nt, true, nst
        elseif not fresh then
            source = 'missing'
        else
            local t = MENU.render(V, w0)
            local ok, werr = STORE.put(fs, P.cfg, t)   -- in place: the config must never be missing
            if ok then
                F, source, last_text, cfg_ok, file_status = copy(V), 'created', t, true, w0
            else
                source = 'write_fail'
                write_fail('config', werr)
            end
        end
    else
        source = 'locked'
    end
    -- 4. the file's moved keys apply
    if F then set = sync(F, 'start', last_n) end
    -- 5. the start rewrite: the config shows what the mod runs with, and only the described keys. A text the menu cannot
    --    read ('bad') is rewritten under the same rules: nobody else ever writes over it (the menu refuses the mod and
    --    never saves it, the bridge only moves the menu's saves), so the mod would leave the menu for good. "status"
    --    is described while the row is on (the rewrite carries the word); with the row off it goes as another key
    if source == 'config' or source == 'bad' then
        local D = MENU.effective(C.get())
        if source == 'bad' or extra or (not status_fn and fst ~= nil) or not same(D, F) then
            skip = (not fresh and 'reloaded') or busy()
            if not skip then
                local t = MENU.render(D, w0)
                local ok, werr = STORE.put(fs, P.cfg, t)
                if ok then
                    rewrote, last_text, base, seen_want, bad_why = true, t, copy(D), copy(D), nil
                    cfg_ok, file_status = true, w0
                else
                    skip = 'write_fail'
                    write_fail('config', werr)
                end
            end
        end
    end
    LOG.info('menu_start', { config = source, set = set, rewrote = rewrote, skip = skip, seen = seen ~= nil,
        n = last_n })
    local t = real()
    next_ev, next_cfg, next_status = t + MENU.POLL_S, t + MENU.CONTENT_S, t + MENU.STATUS_S
    if opts.ticker ~= false then S.ticker('menu_poll', function() MENU.tick() end) end
    seen_step(t)
    return true
end

-- Hot reload and unload (OnUnload, after C.shutdown flushed the A/B save): the seen mark, then off. File writes only
function MENU.shutdown()
    if not on then return end
    seen_next = 0
    seen_step(real())
    S.remove_ticker('menu_poll')
    on = false
end

-- A map change: nothing (the files and the poll belong to the process, not to a map)
function MENU.reset() end

function MENU.status()
    if not on then return nil end
    return { n = last_n, applies = applies, bad = bad_why, seen_wait = seen_want ~= nil or nil, word = want_id,
        word_writes = status_fn and status_writes or nil }
end

return MENU
