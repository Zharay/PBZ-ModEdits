-- status: worked DD2 origin: kb:testing-lab-playtest#principles (2: seed random choices by unit identity)
-- rng.lua: xorshift32 generators and the FNV-1a 32-bit hash. Never use the math library's generator: in a shared Lua
-- state (REFramework) every script shares it and other mods reseed it, and its sequence differs between Lua 5.3 and
-- 5.4. Each unit (a victim, a cut, a gib burst) gets its own generator seeded from its identity, so a cut reapplied
-- after a reload or a save load draws the same numbers. Integer-only arithmetic: the same sequence on Lua 5.3 and
-- 5.4 (tests pin golden vectors that a Python reference reproduces).
--   RNG.hash32(s [, h]) -> 0..2^32-1   FNV-1a over the bytes of tostring(s); h chains several strings (the code hash)
--   RNG.seed_from(...) -> seed          hash32 of the arguments joined by '|', never 0
--   RNG.new(seed) -> g                  g:u32() g:float() [0,1) g:range(lo, hi) g:int(lo, hi) g:chance(p) g:pick(list)
-- Evidence: [worked DD2] core/rng.lua; [worked SWZC] lib/util.lua hash32; kb:runtime-safety-perf#engine-notes (Lua 5.x)
local RNG = {}

local MASK32, FNV_PRIME, FNV_BASIS, DEFAULT = 0xFFFFFFFF, 0x01000193, 0x811C9DC5, 2463534242
local byte = string.byte

function RNG.hash32(s, h)
    s = tostring(s)
    h = h or FNV_BASIS
    for i = 1, #s do h = ((h ~ byte(s, i)) * FNV_PRIME) & MASK32 end
    return h
end

function RNG.seed_from(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
    local h = RNG.hash32(table.concat(parts, '|'))
    if h == 0 then h = DEFAULT end
    return h
end

local G = {}
G.__index = G

-- seed: an integer, a number or a numeric string; NaN, inf, huge or junk fall back to the default state
function RNG.new(seed)
    local n = math.type(seed) == 'integer' and seed or nil
    if not n then
        local f = tonumber(seed)
        n = (f and f == f and f > -2 ^ 53 and f < 2 ^ 53) and math.tointeger(math.floor(f)) or DEFAULT
    end
    n = n & MASK32
    if n == 0 then n = DEFAULT end
    return setmetatable({ state = n }, G)
end

function G:u32()
    local x = self.state
    x = x ~ ((x << 13) & MASK32)
    x = x ~ (x >> 17)
    x = x ~ ((x << 5) & MASK32)
    self.state = x & MASK32
    return self.state
end
function G:float() return self:u32() / 4294967296.0 end
function G:range(lo, hi) return lo + (hi - lo) * self:float() end
function G:int(lo, hi) return lo + (self:u32() % (hi - lo + 1)) end
function G:chance(p) return self:float() < p end
function G:pick(list) if #list == 0 then return nil end return list[self:int(1, #list)] end

-- module contract stubs (a pure library has no lifecycle)
function RNG.init() return true end
function RNG.shutdown() end
function RNG.status() return nil end
function RNG.reset() end

return RNG
