-- status: new in M1a A3.4 (offline only; TC-LAB-02 TA1 and GC1 decide) origin: kb:stumps-caps#ue5-meat-cap-plus-procedural-broken-bone-end
-- lab_cap.lua: the stand-in Caps and the TA1 ladder (spec M1a D8, D9, ladder P3-P9b, sections 3.5, 3.7, 3.8, 3.9). Dev
-- builds only, dev set 'lab02' (META.dev_sets, main.lua); the probe and release never require it, and init stays inert
-- (no listener, no ticker, no record) unless LAB.cut_set(). Engine work only through adapter/ue.lua and
-- adapter/ue_lab.lua helpers, each call under a section 3.4 name (the ladder arms its own steps; C.reserve, C.build,
-- C.attach_piece, C.show and C.destroy run inside the caller's 'lab.cut.stage' or commit call and arm nothing).
-- * Stand-ins (D8, section 3.7): the Stump Cap is generic_s (a ProceduralMeshComponent, section 0), a head Piece end
--   generic_p, a limb Piece end the meat cap (an engine Sphere StaticMeshComponent with a BasicShapeMaterial MID, no
--   arrays, collision off from the add: ue.add_component opts.no_collision, review A5.1 F3). C.reserve picks per end
--   before any hide: a nub when P3, P4 and P7 passed, the state is not poisoned and the charge fits, else meat (P8
--   passed), else the cut is refused 'no_cap'; 'cap_attach' when P6 failed, has not passed or is disabled (a Cap must
--   attach: D4, a class runs only after its proof). The reserve is a dry run of TA.charge and TA.pmc against
--   TA.status() plus the reservations not built yet (so two ends and two cuts in a row account for each other);
--   ue_lab.pmc_section makes the real TA.charge in C.build, in the same stage call,
--   before any hide, and a charge it still sees refused turns that end to meat there (never an open stump).
-- * Scale (D8): the bucket of data/lab_pairs.lua (cut.scale first) through ue.add_component opts.scale; the attach keeps
--   world scale (ue.cap_parent: KeepWorld). The meat Sphere (100 cm) takes MEAT_SCALE x the bucket [P].
-- * Seats (D9, parent mode only): the Stump Cap on the body leader at the stump bone (the live parent of the cut bone),
--   at the cut joint's pose in the stump bone's space (cut.lpose, GetSocketTransform space 3) with +Z along d (cut.d,
--   section 3.8); the Piece-end Cap on the Piece's poseable at the cut bone, zero offset, +Z along -d (in the cut bone's
--   frame); a poseable without the cut bone (GetBoneIndex -1: a GuiChai meshhead may) takes the first bone of the cut
--   subtree it has (cut.chain, the bones from the cut bone's child down to cut.child; else walked on the leader) with
--   the cut joint's offset in that bone's space composed from the leader's parent-space poses; else the carrier box at
--   piece.joint (default its origin). Never the stump bone or another ancestor: an isolated ancestor of the body copy
--   has component-space scale 0.001 (D10).
-- * C4: a shown Cap is never destroyed while its end is drawn: the Stump Cap goes only when the cut bone reads shown on
--   the leader again (a restore) or the corpse is gone; the Piece-end Cap only when the Piece actor is gone or hidden.
--   After a failed P9 every failure path and restore hides a Cap instead of destroying it.
-- * Ladder (section 3.5) on kept-only 1 (the first lab_row keep_only corpse): the head bones of the pair resolved once
--   under 'lab.inherit.hide' (P1 proven), then P3 cap.pmc (a hidden PMC on the corpse), P4 lab.tarray.probe (TA.probe:
--   a one-triangle section, GetNumSections; a failure poisons TA), P5 cap.mid (BasicShapeMaterial through ue.asset, a
--   MID, 'Color' pink [P]), P6 cap.parent (the PMC onto the stump bone with the cut joint's pose), P7 cap.mesh (section
--   0 becomes generic_s, booked first, GetNumSections, shown SHOW_S), P8 cap.meat (the Sphere through ue.asset, a
--   StaticMeshComponent with a MID, attached, shown SHOW_S), P9 cap.destroy (both through their owner), P9b cap.keep
--   (ue.hold of the material and the Sphere on the corpse). One step per frame, each at least the previous name's
--   linger after it and in a later frame than the last proof of any module (LAB.linger_s; a hide-back after SHOW_S
--   runs under the step's own name, waits out another name's proof and pushes the next step);
--   a step runs only while its corpse is live, not paused, not off, its class's sig ok and its prerequisites passed; a
--   prerequisite that did not pass (failed, disabled, sig refused) skips the step (nothing is retried). P3 did not pass:
--   P8's attach (the same ue.cap_parent calls) also writes P6 with via 'cap.meat', so the meat route can still prove
--   (the PMC steps never run under another name). A corpse that goes mid-ladder, or whose body leader lacks the head
--   bones, hands the rest to the next kept-only corpse (a gone test PMC is added again under 'cap.pmc', no new proof).
--   Gone is destroyed (spec M1a 4.1 item 2): a corpse is gone once Actor.bActorIsBeingDestroyed reads true (LAB.alive,
--   LAB.destroying), 6-11 s after its death, not at the 61 s GC; the host choice, a cut's actor and C4 read it.
-- * The warm step (warm(), after each map load): ue.find of the two engine assets and L.expand of the two nubs; no
--   LoadAsset, no ue.hold, no world write.
-- * Records and counters: cap_attach (section 3.1) for each Cap shown (P7, P8, every cut end), forced; proof records
--   through LAB.prove; cap_refused published at 0 from init: +1 per refused reserve and per end the budget or the
--   poison turned to meat.
-- * The player beta's Caps (LAB.beta(); docs/research/beta-dismemberment-plan.md BD11, research C3, C4, CM4, MC7):
--   - C.reserve takes data/caps_beta.lua's Cap of the cut level for both ends (head neck, upperarm shoulder, lowerarm
--     elbow, thigh hip, calf knee: data/caps_beta_sizing.lua parts, cut.size.cap first): cap_<cap>_s on the stump,
--     cap_<cap>_p on every Piece end, limbs included, each three sections (meat, pale, dark) booked as TA.CAP (the
--     session budget only: the sections plus one component). It needs what the nub needs (P3, P4 and P7 passed, the
--     same calls, TA not poisoned) and the room; else the end takes the lab's plan (generic_s, generic_p on a head, the
--     meat Sphere) with cap_why logged. A section that fails at the build drops that Cap the same way (cap_err): the
--     nub without a reservation (pmc_section charges what fits), then the meat Sphere. A burst head (lab_gib,
--     cut.head_mode 'burst') reserves no Piece end.
--   - The material of section i: lab_look's LOOK.material(section, side) (tier A or B for the cap_look knob, a pure
--     lookup) through ue_lab.set_material into slot i; else, or on a failed read-back (one tier down), the flat colour
--     of caps_beta_sizing.colors as a BasicShapeMaterial MID in slot i (tier C; the material a warm-time find kept,
--     never a load in a cut). A MID that fails leaves the section its default material (mid_err, as the lab nubs).
--   - Scale cut.size.scale (R / r_ref, lab_cut BD10; the D8 bucket when it does not read); cut.size.roll (about the
--     Cap's own +Z) is composed after C.z_to(d) on the Stump Cap, and the Piece-end Cap turns its +X to the same
--     anterior in its own frame (the cut bone's, or the subtree bone's; none on the carrier).
--   - C.fade(slot) (lab_fade BD13, inside its armed 'hide.comp'; arms nothing): both ends hidden, the slot faded.
--     C.show never shows a faded slot again, and a faded end may go at any time (nothing open shows behind it).
--   - cap_look_section (research CM1), once a session: on the first new Cap built while lab_look holds a candidate,
--     after its attach and while it is hidden, one armed 'cap.look.section' call (after its sentinel, sig and pin
--     checks) builds section C.TEST_SECTION from C.TRI (265 B, TA.CAP), hides it with SetMeshSectionVisible and tries
--     each candidate in turn: SetMaterial, then the GetMaterial read-back. One forced cap_look_section record {cands,
--     sections, ...}; the section stays hidden for the Cap's life, and a refusal or a raise never fails the cut.
--   - warm() expands the 30 section meshes (not the nubs) and keeps the BasicShapeMaterial find.
--   - cap_attach adds cap, look and look_err per section, sec_bytes, cap_why, cap_err, size_src, roll, want (the knob)
--     and route_kb; a beta Cap is no stand-in.
-- * The native look (cap_look 'native', lab_look's tier N; route B of docs/research/slicer-stumps.md): both ends of a
--   slot reserved under it are native (e.native). The meat section draws lab_look's native meat (section_look, tier
--   'N': the best native flesh; the NoHead texture's stump island is unknown, so the UVs stay). pale keeps
--   MI_Skull_Old_01, dark the flat colour. Each native end shown writes one forced cap_native record { id, part, side,
--   cap, kind, meat (tier), mat (the held name), mid, island ('unknown' on a Cap), pale, dark, cap_why, cap_err, stub,
--   stub_scale, stub_axis } next to its cap_attach.
--   - The vertebra stub (a native neck Stump Cap of kind 'cap', never a puppet's or vessel's: data/no_blood.lua), in
--     C.build after the Cap's attach, inside the stage call, under its own armed 'cap.stub' (SENT.is_disabled and
--     LAB.sig first; refused or failed: e.stub_why, the Cap stays): lab_look's held SM_Spine_001 (LOOK.stub(), no load
--     in a cut) on a hidden StaticMeshComponent of the corpse (ue.add_component: collision off, never culled, no
--     decals) attached to the Stump Cap keeping its relative scale (so the Cap's R / r_ref sizes it to the neck) and
--     posed in the Cap's frame: its bounds' longest axis along the Cap's +Z, its widest cross-section STUB_W, its top
--     STUB_OUT above the pale section's posterior inlay (the vertebral body), at most STUB_LEN long. One per Stump Cap,
--     no TArray bytes. It lives as its Cap: shown by C.show, hidden by C.fade, dropped by C.destroy and fail.
--   - The wound ring (every native Stump Cap of kind 'cap'; not on a data/no_blood.lua class, not while
--     C.effect('blood') is false), after the stub, under its own armed 'cap.ring' (gated as cap.stub): one
--     GameplayStatics.SpawnDecalAttached of the game's blood stain (dark red; else its spatter: lab_blood's
--     materials, found, never loaded) on the body leader at the stump bone with the Cap's own pose, a small box
--     across the Cap's axis projecting along -Z from the rim crest into the neck (cm: Cap units times the Cap's
--     scale), hidden at once and shown with its Cap. The Cap and the stub refuse decals, so it paints the skin round
--     the opening: a ring. The leader must receive decals (lab_blood switches the victim's on at its first bled hit;
--     else 'no_recv'; cap_native ring_recv logs the flag); a ring made is handed to lab_blood (B.recv_pin), which then
--     leaves the leader receiving while the ring lives (its switch back, B4). Lifetime as the stub's; whether
--     SetHiddenInGame hides a decal component is [inferred, UE source: the render state is rebuilt on the change].
-- * Jamon Iberico (cap_look 'textured', lab_iberico): while the knob reads 'textured' and lab_iberico's IB.parts(cut,
--   cap, side) answers (a body it has fitted Caps for, cut.asset's leaf: MaleThug_Body; its meshes prepared, the right
--   side mirrored), both ends take those meshes instead of data/caps_beta.lua's: two sections, face and inlay (e.secs,
--   e.iberico), booked as TA.CAP like any beta Cap, the same reserve, build, scale and fallback chain. Each
--   section draws lab_iberico's held atlas MID (IB.material(), a pure lookup; tier 'I'); while none is held, or on a
--   failed read-back, the section falls back as any beta section does, as the colour IB.LOOK_OF names (face meat, inlay
--   pale). Any other body, or meshes not ready yet, keeps today's Caps (e.ib_why: 'no_fit', 'loading', ...). No stub,
--   no ring (the inlay carries its own anatomy). cap_attach adds ib (the look the end drew, or why not) and ib_why.
--   - The seat (ib_seat): the meshes were fitted in their anchor's frame (contain.py's posed passes keep the Cap fixed
--     there), not along the death pose's d, so a built Iberico end takes IB.parts' anchor (e.anchor: the bone, lpos and
--     lrot in its bind frame, the right side mirrored by lab_iberico) through the same ue.cap_parent call: the Stump at
--     the stump bone, the Piece end at the poseable's cut bone (target 'cut_bone'), each only when the anchor names that
--     bone; no roll (e.roll nil). Else, and on any end that fell back to today's mesh, the direction seat (z_to(d) and
--     the roll) as for every caps_beta Cap and Serrano. cap_attach adds seat ('anchor', 'dir: <why>', nil: not Iberico).
-- API (section 3.9): reserve(cut) -> slot | nil, why; build(slot, cut) -> true | nil, why; attach_piece(slot, piece)
--   -> true | nil, why; show(slot[, side]); destroy(slot[, why]) -> true | false, why; state(slot) -> {stump, piece};
--   fade(slot) -> the number hidden (the beta); warm(); ring_mat() -> the ring's material, its short name | nil (no
--   engine call but one StaticFindObject per never-cached path per map; tests/test_lab_blood.lua); lifecycle
--   init(A, opts) shutdown(reason) status() reset(reason).
-- What the mock cannot prove: native faults, TArray marshalling on dff435dd, real seats, scale under a ragdoll, the
-- look of the stand-ins (TA1b), whether a hold keeps the assets alive.
local BUS = require('core.bus')
local S = require('core.sched')
local SENT = require('core.sentinel')
local MODOFF = require('core.modoff')
local CFG = require('core.config')
local ue = require('adapter.ue')
local L = require('adapter.ue_lab')
local TA = require('adapter.tarray')
local LAB = require('lab_probe')

local C = { SHOW_S = 5, MEAT_SCALE = 0.1, SIG_RETRY_S = 10, CHAIN_MAX = 8,
    PMC = '/Script/ProceduralMeshComponent.ProceduralMeshComponent', SMC = '/Script/Engine.StaticMeshComponent',
    MAT = '/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial', SPHERE = '/Engine/BasicShapes/Sphere.Sphere',
    PINK = { R = 1.0, G = 0.3, B = 0.55 },          -- P5 [P]
    FLESH = { R = 0.62, G = 0.21, B = 0.11 },       -- nubs: pale salmon sRGB 205,126,94 (caps.md cut-face looks) [P]
    MEAT = { R = 0.2, G = 0.01, B = 0.008 } }       -- the meat cap: SWZC DebrisColor (caps.md UE fast path) [P]
-- P4's one triangle (to_lua_mesh form): books (3 x 64 + 3 x 4) x 1.3 = 265 B (section 3.7)
C.TRI = { name = 'probe_tri', nverts = 3, ntris = 1, positions = { 0, 0, 0, 0, 1, 0, 1, 0, 0 },
    normals = { 0, 0, 1, 0, 0, 1, 0, 0, 1 }, uvs = { 0, 0, 0, 1, 1, 0 }, tris = { 0, 1, 2 } }
-- The beta (BD11): the hidden test section's index, at most SECTION_CANDS candidates tried on it; a cut.size.scale
-- above SCALE_MAX (or at or under 0) does not read
C.TEST_SECTION, C.SECTION_CANDS, C.SCALE_MAX = 3, 8, 10

-- Names this module reads (fields; its UFunctions are data/hooks.json calls rows): registered for the names contract
local N = {}
local F = {
    {"/Script/Engine.Character", "Mesh"},
    {"/Script/Engine.SkinnedMeshComponent", "SkinnedAsset"},
    {"/Script/Engine.SceneComponent", "bHiddenInGame"},
    {"/Script/Engine.SceneComponent", "bVisible"},
    {"/Script/Engine.Actor", "bHidden"},
    {"/Script/Engine.Actor", "bActorIsBeingDestroyed"},
    {"/Script/Engine.PrimitiveComponent", "bReceivesDecals"},
}
C.N, C.F = N, F

local A = nil
local function new_state()
    return { init = false, slots = 0, pend = { lab = 0, route = 0 }, warm = {}, lad = nil, ladder_done = false,
        proof_t = {}, refused = 0, no_destroy = false, at = {}, sig_at = {}, basic = nil, sec_done = nil, faded = 0,
        fallback = 0 }
end
local st = new_state()
local function now() return A and A.clock and A.clock.real() or 0 end
local function data(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == 'table' and m or {}
end
-- The two nubs of data/caps_generic.lua by name (required on first use: only the lab02 set loads this module)
local function nub(name)
    for _, m in ipairs(data('data.caps_generic').meshes or {}) do if m.name == name then return m end end
    return nil
end
-- The beta (BD11): data/caps_beta.lua's section meshes by name, data/caps_beta_sizing.lua (both required on first
-- use), and a sibling module of the set when it loaded (lab_look)
local beta_meshes = nil
local function cap_mesh(name)
    if not beta_meshes then
        beta_meshes = {}
        for _, m in ipairs(data('data.caps_beta').meshes or {}) do beta_meshes[m.name] = m end
    end
    return beta_meshes[name]
end
local function sizing() return data('data.caps_beta_sizing') end
-- A class of data/no_blood.lua (wooden puppets, vessels, metal: no red blood, no spine): no native dressing
local function no_blood(class) return class ~= nil and data('data.no_blood')[class] ~= nil end
local function sections()
    local l = sizing().sections
    return type(l) == 'table' and l[1] ~= nil and l or { 'meat', 'pale', 'dark' }
end
local function mod(name)
    local m = package.loaded[name]
    return type(m) == 'table' and m or nil
end

-- ---------- vectors and quaternions ({x, y, z}, {w, x, y, z}) ----------
local function unit3(v)
    if type(v) ~= 'table' or type(v.x) ~= 'number' or type(v.y) ~= 'number' or type(v.z) ~= 'number' then return nil end
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if n < 1e-6 or n ~= n then return nil end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
local function qmul(a, b)
    return { w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w }
end
local function conj(q) return { w = q.w, x = -q.x, y = -q.y, z = -q.z } end
-- The unit quaternion that turns +Z onto the unit vector d (the Cap's face axis, D9); nil for no direction
function C.z_to(d)
    d = unit3(d)
    if not d then return nil end
    if d.z < -0.999999 then return { w = 0.0, x = 1.0, y = 0.0, z = 0.0 } end      -- straight down: half a turn about X
    local q = { w = 1 + d.z, x = -d.y, y = d.x, z = 0.0 }
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y)
    return { w = q.w / n, x = q.x / n, y = q.y / n, z = 0.0 }
end
C.rotate = L.rotate
-- z_to(dir) turned about its own +Z so that its +X points along f projected across dir (the Cap's anterior, research
-- C4); z_to(dir) alone when f is nil or along dir
local function rolled(dir, f)
    local q0, d, u = C.z_to(dir), unit3(dir), unit3(f)
    if not (q0 and u) then return q0 end
    local k = u.x * d.x + u.y * d.y + u.z * d.z
    local pf = unit3({ x = u.x - k * d.x, y = u.y - k * d.y, z = u.z - k * d.z })
    if not pf then return q0 end
    local x0 = L.rotate(q0, { x = 1, y = 0, z = 0 })
    local cx = { x = x0.y * pf.z - x0.z * pf.y, y = x0.z * pf.x - x0.x * pf.z, z = x0.x * pf.y - x0.y * pf.x }
    local th = math.atan(cx.x * d.x + cx.y * d.y + cx.z * d.z, x0.x * pf.x + x0.y * pf.y + x0.z * pf.z)
    return qmul(q0, { w = math.cos(th / 2), x = 0.0, y = 0.0, z = math.sin(th / 2) })
end
-- cut.size.roll (lab_cut BD10) as a unit quaternion about +Z; nil when absent, not numbers, or off the Z axis
local function roll_of(size)
    local r = type(size) == 'table' and size.roll or nil
    if type(r) ~= 'table' then return nil end
    local w, x, y, z = tonumber(r.w), tonumber(r.x), tonumber(r.y), tonumber(r.z)
    if not (w and x and y and z) then return nil end
    local n = math.sqrt(w * w + x * x + y * y + z * z)
    if n ~= n or n < 1e-6 or n == math.huge or math.abs(x) / n > 1e-3 or math.abs(y) / n > 1e-3 then return nil end
    return { w = w / n, x = 0.0, y = 0.0, z = z / n }
end

-- ---------- the reserve (D8, section 3.7): a dry run of TA.charge and TA.pmc ----------
local function nub_bytes(m) return math.floor((m.nverts * 64 + 3 * m.ntris * 4) * 1.3) end
-- b fits when TA.charge would book it as a lab kind and TA.pmc would book one component after it, over the
-- reservations not built yet
local function fits(b)
    local s = TA.status()
    local route = s.bytes + s.pmc * TA.PMC_BYTES + st.pend.route
    return route + b + TA.PMC_BYTES <= s.budget and s.lab_bytes + st.pend.lab + b <= s.lab_budget
end
local function usable(name) return LAB.proof(name) == true and not SENT.is_disabled(name) end
-- The nub route: P3, P4 and P7 passed, not poisoned. The meat route: P8 passed
function C.nub_ok()
    return usable('cap.pmc') and usable('lab.tarray.probe') and usable('cap.mesh') and not TA.poisoned()
end
function C.meat_ok() return usable('cap.meat') end
local function refuse(why)
    st.refused = st.refused + 1
    LAB.count('cap_refused')
    return nil, why
end
-- One end: { side, kind, mesh, bytes (the reserved charge, 0 for meat), why (what turned a nub to meat) }
local function plan_end(side, want, nub_ok)
    local e = { side = side, kind = 'meat', mesh = 'sphere', bytes = 0 }
    local m = want and nub(want) or nil
    if want and not nub_ok then e.why = TA.poisoned() and 'poisoned' or 'nub_route' end
    if m and nub_ok then
        local b = nub_bytes(m)
        if fits(b) then
            e.kind, e.mesh, e.bytes = 'nub', want, b
            st.pend.lab, st.pend.route = st.pend.lab + b, st.pend.route + b + TA.PMC_BYTES
        else
            e.why = 'leak_budget'
        end
    end
    return e
end
local function scale_of(cut)
    local s = tonumber(cut.scale)
    if s and s > 0 then return s end
    local p = (data('data.lab_pairs').pair or {})[cut.pair]
    local part = p and p.parts and p.parts[cut.part]
    s = part and tonumber(part.scale)
    return (s and s > 0) and s or 1.0
end
-- ---------- the beta's Caps (BD11): the cut level, the three sections, the reserve ----------
-- The beta's scale: cut.size.scale (R / r_ref) when it reads, else the D8 bucket. scale, src ('read' | 'bucket')
local function beta_scale(cut)
    local size = type(cut.size) == 'table' and cut.size or {}
    local z = tonumber(size.scale)
    if z and z > 0 and z <= C.SCALE_MAX then return z, size.src == 'bucket' and 'bucket' or 'read' end
    return scale_of(cut), 'bucket'
end
-- The cut level: cut.size.cap when a sizing part names it, else the sizing part of the cut's part stem ('upperarm_l'
-- -> upperarm -> shoulder); nil for a part without a Cap
local function cap_of(cut)
    local parts = sizing().parts or {}
    local want = type(cut.size) == 'table' and cut.size.cap or nil
    for _, x in pairs(parts) do if want ~= nil and type(x) == 'table' and x.cap == want then return want end end
    local x = parts[(tostring(cut.part):gsub('_[lr]$', ''))]
    return type(x) == 'table' and type(x.cap) == 'string' and x.cap or nil
end
-- The section meshes of Cap cap at side ('stump' _s, 'piece' _p) in section order and the bytes they charge; nil
-- when one is missing
local function cap_parts(cap, side)
    if type(cap) ~= 'string' then return nil end
    local list, b = {}, 0
    for i, sec in ipairs(sections()) do
        local m = cap_mesh('cap_' .. cap .. '_' .. side:sub(1, 1) .. '_' .. sec)
        if not m then return nil end
        list[i], b = m, b + nub_bytes(m)
    end
    return list, b
end
-- b fits the session budget with one component after it, over the reservations not built yet (TA.CAP never books the
-- lab sub-budget)
local function room(b)
    local s = TA.status()
    return s.bytes + s.pmc * TA.PMC_BYTES + st.pend.route + b + TA.PMC_BYTES <= s.budget
end
-- Jamon Iberico (the header): lab_iberico's fitted meshes of this cut's end and their bytes, secs, nil, anchor (the
-- end's seat); else nil and why
local function ib_parts(cut, cap, side)
    local IB = mod('lab_iberico')
    if not (IB and type(IB.parts) == 'function') then return nil, nil, nil, 'no_module' end
    local ok, list, secs, anchor = pcall(IB.parts, cut, cap, side)
    if not ok then return nil, nil, nil, 'err: ' .. tostring(list):sub(1, 120) end
    if type(list) ~= 'table' or type(secs) ~= 'table' or list[1] == nil then return nil, nil, nil, tostring(secs) end
    local b = 0
    for _, m in ipairs(list) do b = b + nub_bytes(m) end
    return list, b, secs, nil, anchor
end
-- One beta end: its Cap (kind 'cap', the sections reserved) when the nub route is open and it fits, else the lab's
-- plan with fallback (generic_s, generic_p, or nil: meat), cap_why the reason. ib_cut (cap_look 'textured'): Jamon
-- Iberico's fitted meshes first, today's Caps when lab_iberico has none for this end (ib_why)
local function beta_end(side, cap, fallback, nub_ok, ib_cut)
    local list, b, secs, ib_why, anchor = nil, nil, nil, nil, nil
    if ib_cut then list, b, secs, ib_why, anchor = ib_parts(ib_cut, cap, side) end
    if list and not room(b) then list, b, secs, ib_why = nil, nil, nil, 'leak_budget' end   -- today's smaller Cap next
    local stem = secs and 'dd2_' or 'cap_'
    if not list then list, b = cap_parts(cap, side) end
    local why = (not list) and 'no_mesh' or (not nub_ok) and (TA.poisoned() and 'poisoned' or 'nub_route') or nil
    if not why and not room(b) then why = 'leak_budget' end
    if not why then
        st.pend.route = st.pend.route + b + TA.PMC_BYTES
        return { side = side, kind = 'cap', mesh = stem .. cap .. '_' .. side:sub(1, 1), bytes = b, parts = list,
            fallback = fallback, secs = secs, iberico = secs ~= nil, ib_why = ib_why, anchor = secs and anchor or nil }
    end
    local e = plan_end(side, fallback, nub_ok)
    e.cap_why, e.ib_why = why, ib_why
    return e
end
-- The Stump end is always generic_s or meat; the Piece end generic_p on a head, meat on a limb (D8). The beta takes
-- the Caps of the cut level first (BD11, beta_end)
function C.reserve(cut)
    if type(cut) ~= 'table' or cut.id == nil or type(cut.part) ~= 'string' then return refuse('bad_cut') end
    if LAB.proof('cap.parent') == false then return refuse('cap_attach') end
    local nub_ok, meat_ok = C.nub_ok(), C.meat_ok()
    if not nub_ok and not meat_ok then return refuse('no_cap') end
    -- D4: the attach class must have passed too (P6, or P8's own attach), and not be disabled: else C.build would run
    -- K2_AttachToComponent under 'lab.cut.stage' while its own name is pending, sig-refused or struck
    if not usable('cap.parent') then return refuse('cap_attach') end
    local p0 = { lab = st.pend.lab, route = st.pend.route }
    local beta, cap, want = LAB.beta(), nil, nil
    local stump, piece
    if beta then                                        -- BD11: the Caps of the cut level; a burst head: no Piece end
        cap, want = cap_of(cut), CFG.knob('cap_look')
        local ib_cut = want == 'textured' and cut or nil                -- Jamon Iberico's fitted Caps first
        stump = beta_end('stump', cap, 'generic_s', nub_ok, ib_cut)
        if cut.head_mode == 'burst' then piece = { side = 'piece', kind = 'none', mesh = 'none', bytes = 0 }
        else piece = beta_end('piece', cap, cut.part == 'head' and 'generic_p' or nil, nub_ok, ib_cut) end
    else
        stump = plan_end('stump', 'generic_s', nub_ok)
        piece = plan_end('piece', cut.part == 'head' and 'generic_p' or nil, nub_ok)
    end
    if (stump.kind == 'meat' or piece.kind == 'meat') and not meat_ok then
        st.pend = p0                                    -- nothing stays reserved for a refused cut
        return refuse('no_cap')
    end
    for _, e in ipairs({ stump, piece }) do
        if e.why == 'leak_budget' or e.why == 'poisoned' then st.refused = st.refused + 1 LAB.count('cap_refused') end
    end
    st.slots = st.slots + 1
    local slot = { n = st.slots, id = cut.id, pair = cut.pair, part = cut.part, row = cut.row, scale = scale_of(cut),
        stump = stump, piece = piece, state = 'reserved' }
    if beta then
        slot.beta, slot.cap, slot.rank, slot.want = true, cap, cut.rank, want
        slot.scale, slot.size_src = beta_scale(cut)
        if slot.want == 'native' then stump.native, piece.native = true, true end
    end
    return slot
end

-- ---------- building and seating (inside the caller's armed stage) ----------
local function live(rec)
    if type(rec) ~= 'table' then return nil end
    if rec.full then return ue.live_mod(rec) end
    return ue.live(rec)
end
local function keep(c) return ue.keep_mod(c) or ue.keep(c) end
-- A component the mod made goes through its owner; after a failed P9 it is hidden instead (section 3.5)
local function drop(c)
    if st.no_destroy then return ue.set_hidden(c, true) end
    return ue.destroy(c)
end
local function unpend(e)
    if (e.kind == 'nub' or e.kind == 'cap') and (e.bytes or 0) > 0 and not e.unpended then
        e.unpended = true
        if e.kind == 'nub' then st.pend.lab = math.max(0, st.pend.lab - e.bytes) end
        st.pend.route = math.max(0, st.pend.route - e.bytes - TA.PMC_BYTES)
    end
end
-- The cut's corpse while it is live and not being destroyed (the cut's actor, else its victim record)
local function actor_of(cut)
    if type(cut) ~= 'table' then return nil end
    local a = ue.valid(cut.actor) and cut.actor or (cut.victim and LAB.live(cut.victim)) or nil
    if not a or LAB.destroying(a) == true then return nil end
    return a
end
local function turn_meat(e, why)
    e.kind, e.mesh, e.bytes, e.why = 'meat', 'sphere', 0, why
    st.refused = st.refused + 1
    LAB.count('cap_refused')
end
-- A hidden Cap of end e on actor: a nub PMC (ue_lab.pmc_section books and builds section 0; the flesh MID when P5
-- passed) or the meat Sphere with its MID. A nub whose charge pmc_section refused or found poisoned turns meat here.
-- The component | nil, why
local function make(e, actor, scale)
    if e.kind == 'nub' then
        local c = ue.add_component(actor, C.PMC, { scale = scale })
        if not c then unpend(e) return nil, 'cap_add' end
        ue.set_hidden(c, true)
        local n, why = L.pmc_section(c, nub(e.mesh), 'nub')
        unpend(e)
        if n then
            e.sections, e.comp = n, keep(c)
            if usable('cap.mid') then
                local m, wm = L.mid(c, (ue.asset(C.MAT)), C.FLESH)
                if not m then e.mid_err = wm end
            else
                e.mid_err = 'no_mid'                    -- P5 failed or pending: the default material (logged)
            end
            return c
        end
        drop(c)
        if why ~= 'leak_budget' and why ~= 'poisoned' then return nil, 'cap_mesh' end
        if not C.meat_ok() then return nil, 'no_cap' end
        turn_meat(e, why)
    end
    local sphere = ue.asset(C.SPHERE)
    if not sphere then return nil, 'no_sphere' end
    -- collision off right after the add (review A5.1 F3): a StaticMeshComponent defaults to BlockAllDynamic, so a Piece
    -- end would push its own simulated box, a Stump Cap its ragdoll, and either one the player and the camera
    local c, _, half = ue.add_component(actor, C.SMC, { scale = C.MEAT_SCALE * scale, no_collision = true })
    if not c then
        if half then drop(half) end                     -- added, but its collision would not go off
        return nil, 'cap_add'
    end
    ue.set_hidden(c, true)
    local ok, why = L.set_static_mesh(c, sphere)
    if not ok then drop(c) return nil, 'cap_meat' end
    local m, wm = L.mid(c, nil, C.MEAT)
    if not m then e.mid_err = wm or why end
    e.comp = keep(c)
    return c
end
-- ---------- the beta's Caps (BD11): sections, materials, the fallback chain ----------
-- BasicShapeMaterial for the flat colours: the warm step's find while it holds, else one StaticFindObject (never a
-- load in a cut)
local function basic_mat()
    local m = st.basic and ue.live(st.basic) or nil
    if m then return m end
    m = ue.find(C.MAT)
    st.basic = ue.keep(m)
    return m
end
local function color_of(sec)
    local c = (sizing().colors or {})[sec]
    if type(c) ~= 'table' then return C.MEAT end
    return { R = c[1], G = c[2], B = c[3] }
end
-- Section sec (slot i) of a beta Cap: lab_look's tier A or B material through ue_lab.set_material, else (none, or a
-- failed read-back: one tier down) the flat colour MID, tier C. The tier ('A', 'B', 'C', or 'none': no material
-- written, the section keeps its default one) and why (the drop, or what refused the MID). ib (a Jamon Iberico end:
-- ib_look's answer): lab_iberico's held atlas MID first (tier 'I'), else sec as the flat colour IB.LOOK_OF names
local function section_look(c, slot, sec, side, ib)
    if not usable('cap.mid') then return 'none', 'no_mid' end
    local dropped = nil
    if ib then
        if ib.ok and ib.m ~= nil then
            local okm, why = L.set_material(c, slot, ib.m)
            if okm then return 'I', nil end
            dropped = 'I: ' .. tostring(why)
        else
            local w = ib.m                              -- the raised text, else IB.material's why
            if ib.ok then w = ib.look end
            dropped = 'I: ' .. tostring(w)
        end
        local IB = mod('lab_iberico')
        sec = (IB and IB.LOOK_OF or {})[sec] or 'meat'
    end
    local LOOK = mod('lab_look')
    if LOOK and type(LOOK.material) == 'function' then
        local ok, m, tier = pcall(LOOK.material, sec, side)
        if not ok then dropped = 'look: ' .. tostring(m)
        elseif m ~= nil then
            local okm, why = L.set_material(c, slot, m)
            if okm then return tostring(tier) end
            dropped = tostring(tier) .. ': ' .. tostring(why)
        end
    end
    local mat = basic_mat()
    if not mat then return 'none', 'no_material' end
    local mid, wm = L.mid(c, mat, color_of(sec), slot)
    if mid then return 'C', dropped end
    return 'none', wm
end
-- lab_iberico's held atlas MID, asked once per Jamon Iberico end: { ok (false: IB.material raised), m (or the raised
-- text), look (or IB.material's why) }
local function ib_look()
    local IB = mod('lab_iberico')
    local ok, m, look = pcall(function() if IB then return IB.material() end end)
    return { ok = ok, m = m, look = look }
end
-- A hidden beta Cap of end e on actor: one ProceduralMeshComponent at scale, its sections in order through
-- ue_lab.pmc_section as TA.CAP (section 0 books the component), then a material per section. The component | nil,
-- why ('cap_add', or 'section<i>: <why>' for the first section that failed: the component goes)
local function make_cap(e, actor, scale)
    local c = ue.add_component(actor, C.PMC, { scale = scale })
    if not c then unpend(e) return nil, 'cap_add' end
    ue.set_hidden(c, true)
    local n, b
    e.sec_bytes = {}
    for i, m in ipairs(e.parts) do
        n, b = L.pmc_section(c, m, TA.CAP, i - 1)
        if not n then break end
        e.sec_bytes[i] = b
    end
    unpend(e)
    if not n then
        drop(c)
        return nil, 'section' .. #e.sec_bytes .. ': ' .. tostring(b)
    end
    e.sections, e.look, e.look_err = n, {}, {}
    local ib = e.iberico and ib_look() or nil
    for i, sec in ipairs(e.secs or sections()) do      -- a Jamon Iberico end: face, inlay
        e.look[sec], e.look_err[sec] = section_look(c, i - 1, sec, e.side, ib)
        if e.look[sec] == 'none' and e.mid_err == nil then e.mid_err = e.look_err[sec] end     -- as the lab nubs log it
    end
    if next(e.look_err) == nil then e.look_err = nil end
    if ib then                                          -- the look its sections drew, or why none (cap_attach ib)
        local look = ib.look
        if not ib.ok then look = ib.m end               -- the raised text
        if ib.ok and ib.m ~= nil and e.look.face == 'I' then e.ib = tostring(look)
        else e.ib = 'none: ' .. tostring((e.look_err or {}).face or look) end
    end
    if e.native then                                    -- what tier N held at this build (cap_native)
        local LOOK = mod('lab_look')
        local ok, nat = pcall(function() return LOOK and LOOK.native() or nil end)
        e.nat = ok and type(nat) == 'table' and nat or { why = ok and 'no_look' or tostring(nat) }
    end
    e.comp = keep(c)
    return c
end
-- The beta chain of end e: its Cap; else generic_s on the Stump or generic_p on a head's Piece end (no reservation:
-- pmc_section charges what fits, make turns a refused charge to meat); else the meat Sphere. The component | nil, why
local function make_beta(e, actor, scale)
    if e.kind == 'none' then return nil, 'no_end' end
    if e.kind == 'cap' then
        local c, why = make_cap(e, actor, scale)
        if c then return c end
        st.fallback = st.fallback + 1
        e.cap_err, e.kind, e.mesh, e.bytes = why, 'nub', e.fallback, 0
        if not (e.fallback and C.nub_ok()) then
            if not C.meat_ok() then return nil, 'no_cap' end
            turn_meat(e, 'cap_fail')
        end
    end
    if e.kind == 'nub' then
        local c, why = make(e, actor, scale)
        if c or e.kind ~= 'nub' then return c, why end  -- built, or make turned it meat and tried that
        if not C.meat_ok() then return nil, why end
        turn_meat(e, 'nub_fail')
    end
    return make(e, actor, scale)
end
local function make_end(slot, e, actor)
    if slot.beta then return make_beta(e, actor, slot.scale) end
    return make(e, actor, slot.scale)
end
-- The beta's Stump Cap rotation: z_to(d), then cut.size.roll about the Cap's own +Z; the anterior that gives is kept
-- in the cut bone's frame (slot.fwd) for the Piece end
local function stump_q(slot, cut, q)
    local r = roll_of(cut.size)
    if not r then return q end
    q = qmul(q, r)
    slot.roll = true
    local lq = type(cut.lpose) == 'table' and type(cut.lpose.quat) == 'table' and cut.lpose.quat or nil
    if lq then slot.fwd = L.rotate(conj(lq), L.rotate(q, { x = 1, y = 0, z = 0 })) end
    return q
end
-- cap_look_section (the header): once a session, on a new Cap's component c while it is hidden. Never fails the cut
local function section_test(c, slot)
    if st.sec_done then return end
    local LOOK = mod('lab_look')
    local okc, cands = pcall(function() return LOOK and LOOK.candidates() or {} end)
    if not okc or type(cands) ~= 'table' or cands[1] == nil then return end         -- a later Cap tries again
    if LAB.pinned() ~= true then return end
    local why
    if SENT.is_disabled('cap.look.section') then why = 'disabled'
    elseif TA.poisoned() then why = 'poisoned'
    else
        local ok, ws = LAB.sig('cap.look.section')
        if not ok and ws == 'sig_pending' then return end
        if not ok then why = tostring(ws) end
    end
    st.sec_done = why or 'ran'
    local r, err = nil, why
    if not why then
        r, err = LAB.armed('cap.look.section', function()
            local out = { cands = {} }
            local n, b = L.pmc_section(c, C.TRI, TA.CAP, C.TEST_SECTION)
            out.sections = n
            if not n then out.err = b return out end
            out.bytes = b
            local okv, wv = ue.call(c, 'SetMeshSectionVisible', C.TEST_SECTION, false)
            out.hidden = okv == true
            if not okv then out.err = 'visible: ' .. tostring(wv) return out end
            for i, k in ipairs(cands) do
                if i > C.SECTION_CANDS then break end
                local okm, wm = L.set_material(c, C.TEST_SECTION, type(k) == 'table' and k.m or nil)
                out.cands[i] = { cand = type(k) == 'table' and tostring(k.name) or 'unread',
                    tier = type(k) == 'table' and k.tier or nil, set_ok = okm == true or wm == 'not_set',
                    readback_same = okm == true, why = wm }
            end
            return out
        end)
    end
    local f = type(r) == 'table' and r or {}
    LAB.rec('cap_look_section', { id = slot.id, cap = slot.cap, ok = err == nil and f.err == nil, why = err,
        err = f.err, sections = f.sections, bytes = f.bytes, hidden = f.hidden, cands = f.cands }, true)
end
-- ---------- the native Stump Cap's dressing (the header): the vertebra stub, the wound ring ----------
-- The components an end carries besides its Cap (the stub, the ring), shown, faded and dropped with it
C.EXTRAS = { 'stub', 'ring' }
local function each_extra(e, fn)
    for _, k in ipairs(C.EXTRAS) do
        local x = live(e[k])
        if x then fn(x, k) end
    end
end
local function drop_extras(e)
    each_extra(e, function(x) drop(x) end)
    for _, k in ipairs(C.EXTRAS) do e[k] = nil end
end
-- A name a dressing call may arm, else why ('disabled', 'sig_pending', the sig's word): the dressing is skipped then
local function dress_gate(name)
    if SENT.is_disabled(name) then return 'disabled' end
    local ok, why = LAB.sig(name)
    if not ok then return tostring(why or 'sig') end
    return nil
end
-- The stub in the Cap's own frame (the generated meshes' cm at r_ref; the Cap's world scale R / r_ref carries it): its
-- widest cross-section STUB_W, its top STUB_OUT above the pale section's posterior inlay (the vertebral body,
-- scratch/caps-beta/gen_caps.py PARTS.neck.s), at most STUB_LEN long (a uniform scale; thinner when the mesh is long)
C.STUB_W, C.STUB_OUT, C.STUB_LEN = 2.4, 1.2, 6.0
local inlays = {}
-- The posterior inlay of a pale section mesh: { x, y (its centroid), z (its top) } of its vertices behind the centre
-- (x < 0), cached by mesh name; nil when it has none
local function inlay(m)
    if type(m) ~= 'table' or type(m.positions) ~= 'table' then return nil end
    local key = tostring(m.name)
    if inlays[key] ~= nil then return inlays[key] or nil end
    local p, sx, sy, n, top = m.positions, 0, 0, 0, -math.huge
    for i = 1, #p - 2, 3 do
        if p[i] < 0 then sx, sy, n, top = sx + p[i], sy + p[i + 1], n + 1, math.max(top, p[i + 2]) end
    end
    inlays[key] = n > 0 and { x = sx / n, y = sy / n, z = top } or false
    return inlays[key] or nil
end
-- The stub's scale, rotation (its bounds' longest axis onto the Cap's +Z) and location (the bounds centre under the
-- inlay, the top STUB_OUT above it) from the spine mesh's bounds { extent, origin }; nil, why when they do not read
function C.stub_pose(info, at)
    local e, o = type(info) == 'table' and info.extent, type(info) == 'table' and info.origin
    if type(e) ~= 'table' or type(o) ~= 'table' or type(at) ~= 'table' then return nil, 'no_bounds' end
    for k = 1, 3 do
        local ek, ok = e[k], o[k]
        if type(ek) ~= 'number' or type(ok) ~= 'number' or ek ~= ek or ok ~= ok then return nil, 'no_bounds' end
    end
    local a = 1
    if e[2] > e[a] then a = 2 end
    if e[3] > e[a] then a = 3 end
    local w = 0
    for k = 1, 3 do if k ~= a then w = math.max(w, e[k]) end end
    if w <= 1e-3 or e[a] <= 1e-3 then return nil, 'flat' end
    local s = C.STUB_W / (2 * w)
    if 2 * e[a] * s > C.STUB_LEN then s = C.STUB_LEN / (2 * e[a]) end
    local q = conj(C.z_to({ x = a == 1 and 1 or 0, y = a == 2 and 1 or 0, z = a == 3 and 1 or 0 }))
    local c = L.rotate(q, { x = s * o[1], y = s * o[2], z = s * o[3] })
    return { scale = s, q = q, axis = a,
        loc = { x = at.x - c.x, y = at.y - c.y, z = at.z + C.STUB_OUT - s * e[a] - c.z } }
end
-- Inside 'cap.stub': SM_Spine_001 (lab_look's held mesh) on a hidden StaticMeshComponent of the corpse (collision off
-- from the add, never culled, no decals), attached to the Stump Cap c keeping its relative scale, posed in the Cap's
-- frame. { ok, why, scale, axis }
local function make_stub(e, c, actor)
    local LOOK = mod('lab_look')
    if not (LOOK and type(LOOK.stub) == 'function') then return { why = 'no_look' } end
    local okl, sm, info = pcall(LOOK.stub)
    if not okl then return { why = 'look: ' .. tostring(sm) } end
    if not sm then return { why = tostring(info) } end
    local at = nil
    for i, sec in ipairs(sections()) do if sec == 'pale' then at = inlay(e.parts[i]) end end
    if not at then return { why = 'no_inlay' } end
    local pose, wp = C.stub_pose(info, at)
    if not pose then return { why = wp } end
    local s, ws, half = ue.add_component(actor, C.SMC, { scale = pose.scale, no_collision = true })
    if not s then
        if half then drop(half) end
        return { why = 'add: ' .. tostring(ws) }
    end
    ue.set_hidden(s, true)
    local okm, wm = L.set_static_mesh(s, sm)
    if not okm then drop(s) return { why = 'mesh: ' .. tostring(wm) } end
    local oka, ra = ue.call(s, 'K2_AttachToComponent', c, ue.fname('None'), 0, 0, 0, false)
    if not oka or ra == false then drop(s) return { why = 'attach: ' .. tostring(ra) } end
    local okp, rp = ue.call(s, 'K2_SetRelativeLocationAndRotation', ue.vec(pose.loc.x, pose.loc.y, pose.loc.z),
        ue.quat_rot(pose.q), false, {}, false)
    if not okp then drop(s) return { why = 'pose: ' .. tostring(rp) } end
    e.stub = keep(s)
    return { ok = true, scale = pose.scale, axis = pose.axis }
end
-- The wound ring in Cap units (as the stub; times the Cap's scale R / r_ref in cm): a decal box RING_H half-size
-- across the Cap's axis, RING_D half-depth along it, its centre RING_Z on the Cap's +Z (so it spans the rim crest down
-- into the neck), projecting along -Z; the game's own blood stain (dark red), else its spatter: lab_blood's materials,
-- never loaded here. ring_mat: lab_blood's B.layer (the asset cache its warm-up fills and holds; a missing or stale
-- layer queues lab_blood's own LoadAsset reload), never a lookup (session 20261101-lag: a StaticFindObject miss cost
-- about 23 ms, two a Cap; review: a map load deletes the held layers' cache entries, so 'never cached' was looked up
-- and missed in the first Cap's frame). Only while lab_blood does not run: the cache, never a stale one looked up, a
-- path it never held looked up once per map (ring_miss: the map epoch of its miss). C.RING_MATS: the stain, then the
-- spatter (lab_blood's B.ADECAL_MATS[2] and [1]), filled in place at the first ring_mat (lab_blood loads after this
-- module)
C.RING_H, C.RING_D, C.RING_Z = 8.0, 1.6, -0.3
C.RING_MATS = {}
local ring_miss = {}
local function ring_mat()
    local list = C.RING_MATS
    local B = mod('lab_blood')
    if list[1] == nil then
        local m = B and B.ADECAL_MATS
        if type(m) == 'table' then list[1], list[2] = m[2], m[1] end
    end
    for _, p in ipairs(list) do
        local m, inert = nil, true
        if B and type(B.layer) == 'function' then
            local ok, o, why = pcall(B.layer, p)
            if ok then m, inert = o, why == 'inert' end
        end
        if inert then
            local o, _, why = ue.asset_peek(p)
            m = o
            if not m and why ~= 'stale' and ring_miss[p] ~= ue.epoch then
                m = ue.find(p)
                if not m then ring_miss[p] = ue.epoch end
            end
        end
        if m then return m, p:match('%.([^.]+)$') end
    end
    return nil
end
C.ring_mat = ring_mat
-- Inside 'cap.ring': GameplayStatics.SpawnDecalAttached on the body leader at the stump bone, KeepRelativeOffset, the
-- Cap's own pose (lp, q in the bone's space, as ue.cap_parent seats it) turned so the box projects along the Cap's -Z
-- with a random spin about it, no life span; hidden until the Cap shows. Not on the Cap: the engine attaches a decal
-- only to a primitive that receives decals [inferred, UE source UGameplayStatics::SpawnDecalAttached], and the Cap and
-- the stub refuse them (ue.add_component), which is also why the box paints the neck round the Cap and not the Cap.
-- The decal takes absolute scale [inferred, same source]: its size is in cm (Cap units times scale). { ok, why, mat,
-- recv (the leader's bReceivesDecals: lab_blood switches it on at the first bled hit; false refuses, 'no_recv') }
local Q_DOWN = C.z_to({ x = 1, y = 0, z = 0 })        -- the decal's +X (its projection) onto the Cap's -Z
local function make_ring(e, cut, lp, q, scale)
    local leader = cut.leader
    local recv = ue.get(leader, 'bReceivesDecals')
    if recv ~= true then return { why = 'no_recv', recv = recv } end
    local mat, name = ring_mat()
    if not mat then return { why = 'no_material', recv = recv } end
    local gs = ue.cdo('gs')
    if not gs then return { why = 'no_statics', recv = recv } end
    local th = math.random() * 2 * math.pi
    local qd = qmul(qmul(q, { w = math.cos(th / 2), x = 0.0, y = 0.0, z = math.sin(th / 2) }), Q_DOWN)
    local o = L.rotate(q, { x = 0, y = 0, z = C.RING_Z * scale })
    ue.count_write()
    -- lint:allow L016 a native Cap's wound ring: its cut passed the gates; no_blood and blood off refused above
    local d = ue.p(gs:SpawnDecalAttached(mat, ue.vec(C.RING_D * scale, C.RING_H * scale, C.RING_H * scale), leader,
        ue.fname(cut.stump), ue.vec(lp.x + o.x, lp.y + o.y, lp.z + o.z), ue.quat_rot(qd), 0, 0.0))
    if not ue.valid(d) then return { why = 'no_component', mat = name, recv = recv } end
    ue.set_hidden(d, true)
    e.ring = keep(d)
    return { ok = true, mat = name, recv = recv }
end
-- Blood is off for the ring: effects.blood or enabled false (core/config.lua C.effect)
local function blood_off()
    local ok, on = pcall(CFG.effect, 'blood')
    return ok and on == false
end
-- The native Stump Cap's dressing, after its attach (C.build): the stub on a neck Cap, the ring on every Stump Cap.
-- Never fails the cut
local function dress(slot, e, c, cut, actor, lp, q)
    if slot.part == 'head' and slot.cap == 'neck' then
        local why = no_blood(cut.class) and 'no_blood' or dress_gate('cap.stub')
        if why then e.stub_why = why
        else
            local r, err = LAB.armed('cap.stub', make_stub, e, c, actor)
            if type(r) == 'table' and r.ok then e.stub_scale, e.stub_axis = r.scale, r.axis
            else e.stub_why = type(r) == 'table' and tostring(r.why) or ('err: ' .. tostring(err):sub(1, 160)) end
        end
    end
    local why = (no_blood(cut.class) and 'no_blood') or (blood_off() and 'blood_off') or dress_gate('cap.ring')
    if why then e.ring_why = why return end
    local r, err = LAB.armed('cap.ring', make_ring, e, cut, lp, q, slot.scale)
    if type(r) == 'table' then e.ring_mat, e.ring_recv = r.mat, r.recv end
    if not (type(r) == 'table' and r.ok) then
        e.ring_why = type(r) == 'table' and tostring(r.why) or ('err: ' .. tostring(err):sub(1, 160))
        return
    end
    -- lab_blood leaves the leader receiving decals while the ring lives (its B.recv_pin, B4): else its switch back
    -- after the body's last stain would stop the ring drawing
    local B = mod('lab_blood')
    if B and type(B.recv_pin) == 'function' then pcall(B.recv_pin, actor, e.ring) end
end
-- Jamon Iberico (the header): an end built from fitted meshes rides the anchor they were fitted in (lab_iberico's
-- anchor: its bone, lpos and lrot in that bone's bind frame, the right side mirrored) when that anchor's bone is the
-- bone this end attaches to anyway (the stump bone, the Piece's cut bone): the same ue.cap_parent call, another pose.
-- The anchor, else nil and why (the end keeps the direction seat: e.seat 'dir: <why>'); nil, nil for any other end
local function ib_seat(e, bone)
    if not (e.kind == 'cap' and e.iberico) then return nil, nil end
    local a = e.anchor
    if type(a) ~= 'table' or type(a.bone) ~= 'string' or type(a.loc) ~= 'table' or type(a.quat) ~= 'table' then
        return nil, 'no_anchor'
    end
    if type(bone) ~= 'string' or a.bone:lower() ~= bone:lower() then return nil, 'anchor_bone ' .. a.bone end
    return a
end
-- A failed build or attach: what was built goes (hidden after a failed P9), the reservations are given back
local function fail(slot, why)
    for _, e in ipairs({ slot.stump, slot.piece }) do
        unpend(e)
        local c = live(e.comp)
        if c then drop(c) end
        e.comp = nil
        drop_extras(e)
    end
    slot.state, slot.why = 'failed', why
    return nil, why
end
-- D9: the Stump Cap, hidden, on the body leader at the stump bone with the cut joint's pose and +Z along d (a Jamon
-- Iberico Cap: its anchor's pose, ib_seat)
function C.build(slot, cut)
    if type(slot) ~= 'table' or slot.state ~= 'reserved' then return nil, 'bad_slot' end
    slot.cut = cut
    local actor = actor_of(cut)
    if not actor then return fail(slot, 'gone') end
    local q, lp = C.z_to(cut.d), type(cut.lpose) == 'table' and cut.lpose.loc or nil
    if not (q and lp and ue.valid(cut.leader) and type(cut.stump) == 'string') then return fail(slot, 'no_pose') end
    if slot.beta then q = stump_q(slot, cut, q) end     -- slot.fwd: a Piece end on the direction seat rolls to it
    local e = slot.stump
    local c, why = make_end(slot, e, actor)
    if not c then return fail(slot, why) end
    local a, wseat = ib_seat(e, cut.stump)
    if a then lp, q, e.seat = a.loc, a.quat, 'anchor' elseif wseat then e.seat = 'dir: ' .. wseat end
    local ok, wa = ue.cap_parent(c, cut.leader, cut.stump, lp, q)
    if not ok then
        e.attach_err = wa
        return fail(slot, 'cap_attach')
    end
    e.target, e.bone, e.roll = 'stump_bone', cut.stump, (not a) and slot.roll or nil
    slot.state = 'built'
    if e.kind == 'cap' then section_test(c, slot) end
    if e.kind == 'cap' and e.native then dress(slot, e, c, cut, actor, lp, q) end
    return true
end
-- The bones from the cut bone's child down to child on the leader (cut.chain when lab_cut passed it)
local function chain_of(cut)
    if type(cut.chain) == 'table' and cut.chain[1] then return cut.chain end
    if type(cut.child) ~= 'string' then return {} end
    local up, cur = { cut.child }, cut.child
    for _ = 1, C.CHAIN_MAX do
        local par = L.bone_parent(cut.leader, cur)
        if not par then return {} end
        if par:lower() == cut.bone:lower() then
            local down = {}
            for i = #up, 1, -1 do down[#down + 1] = up[i] end
            return down
        end
        up[#up + 1], cur = par, par
    end
    return {}
end
-- The Piece-end seat (D9): target, the mesh or carrier, bone, local position, face direction (+Z), in that frame, and
-- the rotation that takes the cut bone's frame to that frame (nil on the carrier: the beta's roll skips it)
local ID = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
local function seat(cut, piece)
    local dc = type(cut.cpose) == 'table' and unit3(cut.cpose.loc) or nil
    if not dc and type(cut.lpose) == 'table' and type(cut.lpose.quat) == 'table' and unit3(cut.d) then
        dc = L.rotate(conj(cut.lpose.quat), unit3(cut.d))
    end
    if not dc then return nil end
    local out = { x = -dc.x, y = -dc.y, z = -dc.z }
    local p = piece.poseable
    if ue.valid(p) and ue.has_bone(p, cut.bone) then
        return 'cut_bone', p, cut.bone, { x = 0, y = 0, z = 0 }, out, ID
    end
    local b = nil                                       -- the chain bone's pose in the cut bone's space, top down
    for _, bone in ipairs(ue.valid(p) and chain_of(cut) or {}) do
        local x = L.bone_parent_xform(cut.leader, bone)
        if not x then break end
        if b == nil then b = x else
            local t = L.rotate(b.quat, { x = b.scale.x * x.loc.x, y = b.scale.y * x.loc.y, z = b.scale.z * x.loc.z })
            b = { loc = { x = b.loc.x + t.x, y = b.loc.y + t.y, z = b.loc.z + t.z }, quat = qmul(b.quat, x.quat),
                scale = { x = b.scale.x * x.scale.x, y = b.scale.y * x.scale.y, z = b.scale.z * x.scale.z } }
        end
        if ue.has_bone(p, bone) then
            local ic = conj(b.quat)
            local l = L.rotate(ic, { x = -b.loc.x, y = -b.loc.y, z = -b.loc.z })
            return 'subtree_bone', p, bone, { x = l.x / b.scale.x, y = l.y / b.scale.y, z = l.z / b.scale.z },
                L.rotate(ic, out), ic
        end
    end
    if ue.valid(piece.carrier) then
        return 'carrier', piece.carrier, nil, piece.joint or { x = 0, y = 0, z = 0 }, piece.out or { x = 0, y = 0, z = 1 }
    end
    return nil
end
-- Parent mode on the carrier box (no bone: ue.cap_parent needs one): K2_AttachToComponent(carrier, None, 2, 2, 1,
-- false), then the local pose. true | false, why
local function to_carrier(c, carrier, lpos, q)
    local ok, r = ue.call(c, 'K2_AttachToComponent', carrier, ue.fname('None'), 2, 2, 1, false)
    if not ok then return false, 'attach: ' .. tostring(r) end
    if r == false then return false, 'attach_refused' end
    ok, r = ue.call(c, 'K2_SetRelativeLocationAndRotation', ue.vec(lpos.x, lpos.y, lpos.z), ue.quat_rot(q), false, {},
        false)
    if not ok then return false, 'pose: ' .. tostring(r) end
    return true
end
-- D9: the Piece-end Cap, hidden, on the Piece actor: the cut bone of its poseable, else the first subtree bone it has,
-- else the carrier; never an ancestor. piece = { actor, poseable, carrier, joint, out }
function C.attach_piece(slot, piece)
    if type(slot) ~= 'table' or slot.state ~= 'built' then return nil, 'bad_slot' end
    if type(piece) ~= 'table' or not ue.valid(piece.actor) then return fail(slot, 'no_piece') end
    local e = slot.piece
    if e.kind == 'none' then return nil, 'no_end' end   -- the beta's burst head: no Piece-end Cap was reserved
    local target, on, bone, lpos, dir, frame = seat(slot.cut, piece)
    local q = target and C.z_to(dir) or nil
    if q and slot.beta and slot.fwd and frame then      -- BD11: the Stump Cap's anterior, in this seat's frame
        q, e.roll = rolled(dir, L.rotate(frame, slot.fwd)), true
    end
    if not q then return fail(slot, 'no_seat') end
    local c, why = make_end(slot, e, piece.actor)
    if not c then return fail(slot, why) end
    local a, wseat = ib_seat(e, target == 'cut_bone' and bone or nil)     -- Jamon Iberico: the cut bone's anchor
    if a then lpos, q, e.seat, e.roll = a.loc, a.quat, 'anchor', nil
    elseif wseat then e.seat = 'dir: ' .. (target == 'cut_bone' and wseat or tostring(target)) end
    local ok, wa
    if target == 'carrier' then ok, wa = to_carrier(c, on, lpos, q) else ok, wa = ue.cap_parent(c, on, bone, lpos, q) end
    if not ok then
        e.attach_err = wa
        return fail(slot, 'cap_attach')
    end
    e.target, e.bone, slot.actor = target, bone, keep(piece.actor)
    slot.state = 'staged'
    return true
end

-- ---------- show, destroy, state ----------
-- The cap_native record of a shown native end (the header): what the native look applied to it
local function native_rec(slot, e)
    local look, nat = e.look or {}, e.nat or {}
    LAB.rec('cap_native', { id = slot.id, part = slot.part, side = e.side, cap = slot.cap, kind = e.kind,
        meat = look.meat, mat = nat.meat, mid = nat.mid, island = e.kind == 'cap' and 'unknown' or nil,
        nat_why = nat.why, pale = look.pale, dark = look.dark, cap_why = e.cap_why, cap_err = e.cap_err,
        stub = e.stub and 'ok' or e.stub_why, stub_scale = e.stub and e.stub_scale or nil,
        stub_axis = e.stub and e.stub_axis or nil, ring = e.ring and 'ok' or e.ring_why, ring_mat = e.ring_mat,
        ring_recv = e.ring_recv }, true)
end
-- The cap_attach record (section 3.1) of end e, forced; mid_err: the Cap draws with its default material (P5 failed
-- or the MID call did, section 3.5 'logged')
local function attach_rec(slot, e, ok, why)
    LAB.rec('cap_attach', { id = slot.id, part = slot.part, kind = e.kind, side = e.side, ok = ok == true, why = why,
        sections = e.sections, mesh = e.mesh, mode = 'parent', target = e.target or 'unread', bone = e.bone,
        scale = slot.scale, standin = e.kind ~= 'cap', bytes = e.bytes or 0, pair = slot.pair, row = slot.row,
        mid_err = e.mid_err, cap = slot.cap, rank = slot.rank, look = e.look, look_err = e.look_err,
        sec_bytes = e.sec_bytes, cap_why = e.cap_why, cap_err = e.cap_err, size_src = slot.size_src, roll = e.roll,
        want = slot.want, route_kb = slot.beta and TA.status().route_kb or nil, ib = e.ib, ib_why = e.ib_why,
        seat = e.seat }, true)
    if ok and e.native then native_rec(slot, e) end
end
-- Show side ('stump', 'piece' or nil for both): each Cap built is shown and gets its cap_attach record. The number
-- shown
function C.show(slot, side)
    if type(slot) ~= 'table' or slot.faded then return 0 end           -- a faded slot never shows again (BD11)
    local n = 0
    for _, e in ipairs({ slot.stump, slot.piece }) do
        if (side == nil or side == e.side) and e.comp and not e.shown then
            local c = live(e.comp)
            if c then
                ue.set_hidden(c, false)
                each_extra(e, function(x) ue.set_hidden(x, false) end)    -- the native dressing with its Cap
                e.shown, n = true, n + 1
                attach_rec(slot, e, true)
            else
                attach_rec(slot, e, false, 'gone')
            end
        end
    end
    if n > 0 then slot.state = 'shown' end
    return n
end
-- C4: may end e of slot go? Not shown yet, or faded (the beta: hidden on a dissolving body): yes. The Stump Cap: the
-- corpse gone, or the cut bone shown on the leader again (a restore). The Piece-end Cap: the Piece actor gone or hidden
local function may_go(slot, e)
    if not e.shown or e.faded then return true end
    local cut = slot.cut or {}
    if e.side == 'stump' then
        if not actor_of(cut) then return true end
        return L.is_bone_hidden(cut.leader, cut.bone) == false
    end
    local a = live(slot.actor)
    return a == nil or ue.get(a, 'bHidden') == true
end
-- Every Cap of the slot that may go goes (through its owner; hidden after a failed P9); a reserved end gives its
-- bytes back. true | false, 'cut_live' (an end is still drawn: it stays)
function C.destroy(slot)
    if type(slot) ~= 'table' then return false, 'bad_slot' end
    local kept = false
    for _, e in ipairs({ slot.stump, slot.piece }) do
        unpend(e)
        local c = live(e.comp)
        if c and not may_go(slot, e) then kept = true
        elseif c then
            drop(c)
            e.comp, e.shown = nil, false
            drop_extras(e)
        else
            drop_extras(e)                              -- a Cap already gone takes its dressing along
        end
    end
    if kept then return false, 'cut_live' end
    slot.state = 'destroyed'
    return true
end
-- The beta's dissolve fade (lab_fade BD13, MC7), inside the caller's armed 'hide.comp': every live Cap of the slot
-- hidden with ue.set_hidden, its ends and the slot marked faded (C.show never shows them again). The number hidden
function C.fade(slot)
    if type(slot) ~= 'table' then return 0 end
    local n = 0
    if not slot.faded then st.faded = st.faded + 1 end
    slot.faded = true
    for _, e in ipairs({ slot.stump, slot.piece }) do
        if type(e) == 'table' then
            e.faded = true
            local c = live(e.comp)
            if c and ue.set_hidden(c, true) then n = n + 1 end
            each_extra(e, function(x) ue.set_hidden(x, true) end)
        end
    end
    return n
end
-- { stump = live and visible, piece = live and visible (nil when no Piece-end Cap was built) }
local function drawn(e)
    local c = live(e.comp)
    if not c then return false end
    return L.comp_hidden(c) == false
end
function C.state(slot)
    if type(slot) ~= 'table' then return { stump = false } end
    local piece = nil                                   -- not 'comp and drawn() or nil': a hidden end reads false
    if slot.piece.comp ~= nil then piece = drawn(slot.piece) end
    return { stump = drawn(slot.stump), piece = piece }
end

-- ---------- the warm step (main.lua, after each map load): lookups only ----------
-- ue.find of the two engine assets (no LoadAsset, no hold, no write) and the two nubs expanded once (ue_lab caches);
-- the beta expands data/caps_beta.lua's 30 section meshes instead and keeps the material's find for the cuts
function C.warm()
    if not st.init then return nil end
    st.warm = { mat = ue.find(C.MAT) ~= nil, sphere = ue.find(C.SPHERE) ~= nil }
    if LAB.beta() then
        st.basic = ue.keep(ue.find(C.MAT))
        local n = 0
        for _, m in ipairs(data('data.caps_beta').meshes or {}) do if L.expand(m) then n = n + 1 end end
        st.warm.caps = n
        return st.warm
    end
    for _, n in ipairs({ 'generic_s', 'generic_p' }) do
        local m = nub(n)
        st.warm[n] = m ~= nil and L.expand(m) ~= nil
    end
    return st.warm
end

-- ---------- the ladder P3-P9b (section 3.5) on kept-only 1 ----------
-- Each run(lad, actor) returns { ok, f = proof fields } inside LAB.armed(name); need: proofs that must have passed
-- (a failed one skips the step); pmc: works on the test PMC (added again under 'cap.pmc' when its corpse went);
-- show: the test component shown SHOW_S, then hidden again under the same name
local function test_rec(lad, kind, mesh, c, f)
    LAB.rec('cap_attach', { id = lad.d.id, part = 'head', kind = kind, side = 'stump', ok = c ~= nil, mesh = mesh,
        sections = f.sections, mode = 'parent',
        target = (f.attached or LAB.proof('cap.parent')) and 'stump_bone' or 'unread',
        bone = lad.bones.stump, scale = 1.0, standin = true, bytes = f.bytes or 0, pair = lad.d.pair, ladder = true },
        true)
end
local function add_pmc(lad, actor)
    local c = ue.add_component(actor, C.PMC)
    if not c then return nil end
    ue.set_hidden(c, true)
    lad.pmc = keep(c)
    return c
end
C.LADDER = {
    { step = 'P3', name = 'cap.pmc', run = function(lad, actor) return { ok = add_pmc(lad, actor) ~= nil, f = {} } end },
    { step = 'P4', name = 'lab.tarray.probe', need = { 'cap.pmc' }, pmc = true, run = function(lad)
        local n, b
        local ok = TA.probe(function()
            n, b = L.pmc_section(live(lad.pmc), C.TRI, 'probe')
            return n
        end)
        -- b is the booked bytes when the section built and the refusal word when it did not (the first run logged
        -- the 265 bytes as err: a field mix-up, M1a 4.1 item 4)
        local f = { sections = n, bytes = n and b or nil, err = (not n) and b or nil }
        return { ok = ok == true, f = f }
    end },
    { step = 'P5', name = 'cap.mid', need = { 'cap.pmc' }, pmc = true, run = function(lad)
        local mat = ue.asset(C.MAT)
        if not mat then return { ok = false, f = { err = 'no_material' } } end
        local m, why, info = L.mid(live(lad.pmc), mat, C.PINK)
        info = info or {}
        return { ok = m ~= nil, f = { err = why, mid_via = info.via, n_mats = info.n_mats, slot0 = info.slot0 } }
    end },
    { step = 'P6', name = 'cap.parent', need = { 'cap.pmc' }, pmc = true, run = function(lad)
        local b = lad.bones
        local ok, why = ue.cap_parent(live(lad.pmc), b.leader, b.stump, b.lpose.loc, C.z_to(b.d))
        return { ok = ok == true, f = { err = why } }
    end },
    { step = 'P7', name = 'cap.mesh', need = { 'cap.pmc', 'lab.tarray.probe' }, pmc = true, show = 'pmc',
        run = function(lad)
            local c = live(lad.pmc)
            local n, b = L.pmc_section(c, nub('generic_s'), 'nub')
            if not n then return { ok = false, f = { err = b } } end
            ue.set_hidden(c, false)
            local f = { sections = n, bytes = b }
            test_rec(lad, 'nub', 'generic_s', c, f)
            return { ok = true, f = f }
        end },
    { step = 'P8', name = 'cap.meat', show = 'meat', run = function(lad, actor)
        local sphere, b = ue.asset(C.SPHERE), lad.bones
        if not sphere then return { ok = false, f = { err = 'no_sphere' } } end
        local c, wc, half = ue.add_component(actor, C.SMC, { scale = C.MEAT_SCALE, no_collision = true })   -- F3
        if not c then
            if half then ue.set_hidden(half, true) lad.meat = keep(half) end      -- collision stays on: P9 destroys it
            return { ok = false, f = { err = 'add: ' .. tostring(wc) } }      -- the add's own reason, half or not
        end
        ue.set_hidden(c, true)
        lad.meat = keep(c)
        local okm, wm = L.set_static_mesh(c, sphere)
        if not okm then return { ok = false, f = { err = wm } } end
        local m, wd = L.mid(c, nil, C.MEAT)
        local ok, why = ue.cap_parent(c, b.leader, b.stump, b.lpose.loc, C.z_to(b.d))
        lad.meat_attach = ok == true
        if not ok then return { ok = false, f = { err = why } } end
        ue.set_hidden(c, false)
        test_rec(lad, 'meat', 'sphere', c, { attached = true })     -- its own attach (P6 may not have run)
        return { ok = true, f = { mid_err = (not m) and wd or nil } }
    end },
    -- Read back through the owner's list (ue.listed): a destroyed component leaves it at once, while UE4SS's IsValid
    -- reads true until the GC runs (review A5.1 F2), so a validity read failed every live P9. A list that could not be
    -- read (ue.listed nil: the call failed or a live owner answered none) proves nothing: P9 fails, err
    -- 'readback_unread' (review A5.1 recheck)
    { step = 'P9', name = 'cap.destroy', run = function(lad)
        local ok, n, unread, how = true, 0, false, nil
        for _, k in ipairs({ 'pmc', 'meat' }) do
            local c = live(lad[k])
            if c then
                n = n + 1
                local owner = ue.owner(c)
                local destroyed, dwhy = ue.destroy(c)
                local listed, lwhy = nil, nil
                if destroyed then listed, lwhy = ue.listed(owner, c) end
                if listed == false then lad[k] = nil                -- gone: never touched again
                else
                    ok = false
                    if destroyed and listed == nil then unread, how = true, how or lwhy end
                    if not destroyed then how = how or dwhy end
                end
            end
        end
        return { ok = ok and n > 0, f = { err = (n == 0 and 'nothing') or (unread and 'readback_unread') or nil,
            read = how } }
    end },
    { step = 'P9b', name = 'cap.keep', run = function(lad, actor)
        local h1, w1, a1 = ue.hold(actor, (ue.asset(C.MAT)), 'material')
        local h2, w2, a2 = ue.hold(actor, (ue.asset(C.SPHERE)), 'mesh')
        st.holds = { h1, h2 }
        -- each hold's word apart, with the reason the holder's add gave (M1a 4.1 item 4): 'material: no_host add: ...'
        local w = {}
        for _, x in ipairs({ { 'material', w1, a1 }, { 'mesh', w2, a2 } }) do
            if x[2] ~= nil then
                w[#w + 1] = x[1] .. ': ' .. tostring(x[2]) .. (x[3] ~= nil and (' add: ' .. tostring(x[3])) or '')
            end
        end
        return { ok = h1 ~= nil and h2 ~= nil, f = { err = w[1] and table.concat(w, '; ') or nil } }
    end },
}
-- After a step: a failed P9 hides from then on (and hides both test components now); P8 proves P6 through its own
-- attach when P3 did not pass (failed, disabled or refused by its sig check: P6 never ran) and cap.parent itself is
-- not disabled
local function after(lad, s, ok, actor)
    if s.step == 'P9' and not ok then
        st.no_destroy = true
        for _, k in ipairs({ 'pmc', 'meat' }) do
            local c = live(lad[k])
            if c then ue.set_hidden(c, true) end
        end
    elseif s.step == 'P8' and LAB.proof('cap.parent') == nil and LAB.proof('cap.pmc') ~= true
            and not SENT.is_disabled('cap.parent') and lad.meat_attach ~= nil then
        LAB.prove('P6', 'cap.parent', lad.meat_attach, LAB.host_state(actor, lad.d,
            { id = lad.d.id, pair = lad.d.pair, via = 'cap.meat' }))
    end
end

-- The head bones of the pair on the corpse's body leader (lab_pairs candidates, GetBoneIndex; the stump bone the live
-- parent; d and the cut joint's pose, section 3.8): the 'lab.inherit.hide' class P1 proved
local function resolve(actor, pair)
    local leader = ue.get(actor, 'Mesh')
    if not ue.valid(leader) then return { why = 'no_leader' } end
    local p = ((data('data.lab_pairs').pair or {})[pair] or {}).parts
    local head = p and p.head
    if not head then return { why = 'no_part' } end
    local function first(list)
        for _, b in ipairs(list or {}) do if ue.has_bone(leader, b) then return b end end
    end
    local bone, child = first(head.cut), first(head.child)
    if not (bone and child) then return { why = 'no_bone' } end
    local stump = first(head.stump) or L.bone_parent(leader, bone)
    if not stump then return { why = 'no_parent' } end
    local d, a = L.bone_dir(leader, bone, child)
    if not d then return { why = tostring(a) } end
    return { leader = leader, bone = bone, child = child, stump = stump, d = d, lpose = a }
end
-- The corpse of a lab_row payload while it is alive (live and not being destroyed) and not on a later life; nil and
-- why ('destroyed', 'collected', 'reused', 'stale', 'none', 'revived') otherwise
local function corpse(d)
    if type(d) ~= 'table' then return nil, 'none' end
    local a, why = LAB.alive(d.victim or d.keep)
    if not a then return nil, why end
    if type(d.victim) == 'table' and d.corpse_life and d.victim.life ~= d.corpse_life + 1 then return nil, 'revived' end
    return a
end
local function wait_until(lad, t) if t > lad.next_t then lad.next_t = t end end
-- Section 3.5 and D4 against every module's proofs (lab_cut's P17 and P18 can land inside this ladder): a later frame
-- than the last proof and past its linger. A hide-back runs under its step's own name, so it skips the linger of a
-- last proof of that name (SHOW_S after it, as before) and waits out any other
local function spaced(t, name)
    local last = st.last
    if last == nil then return true end
    if last.f >= S.frame then return false end
    return last.name == name or t >= last.t + LAB.linger_s(last.name)
end
-- One armed call of the ladder (a step, the bone read, a hide-back, a PMC added again): the next waits its linger
local function run(lad, name, fn, ...)
    local t0 = os.clock()
    local r, err = LAB.armed(name, fn, ...)
    wait_until(lad, now() + LAB.linger_s(name))
    return r, err, math.floor((os.clock() - t0) * 1000 + 0.5)
end
-- The first step that has not run, past the skipped ones (ran already, disabled by the sentinel, a need that did not
-- pass: failed, or skipped itself as disabled or by its sig check, so its class never runs under another name)
local function next_step(lad)
    while C.LADDER[lad.i] do
        local s, skip = C.LADDER[lad.i], nil
        if LAB.proof(s.name) ~= nil then skip = 'ran'
        elseif SENT.is_disabled(s.name) then skip = 'disabled'
        else for _, n in ipairs(s.need or {}) do if LAB.proof(n) ~= true then skip = 'need:' .. n end end end
        if not skip then return s end
        if skip ~= 'ran' then lad.skipped[s.step] = skip end
        lad.i = lad.i + 1
    end
    lad.done = true
    return nil
end
-- M1a 4.1 item 3: the host reads dead before the next step (why: LAB.alive's word): that step is skipped 'host_dead'
-- (no call, no proof, one 'ladder_skip' record and the counter) and the ladder moves to the next kept corpse. Nothing
-- is skipped when no step is left to run
local function host_dead(lad, why)
    local s = next_step(lad)
    if not s then return end
    LAB.host_skip('lab_cap', s.step, lad.d, why)
    st.host_dead = (st.host_dead or 0) + 1
end
-- lab_end (D20): a test Cap still shown is hidden at once under its step's name, in the first tick after lab_end (the
-- lingers clear a frame after the end flush); while off it waits for 'on', which shows it first
local function end_hide(lad)
    local h = lad.hide
    if not h or h.ended or not MODOFF.enabled('lab_cap') then return end
    h.ended = true                                      -- tried once: a refused hide leaves it in the mod-off list
    local _, err = run(lad, h.name, function()
        local c = live(lad[h.key])
        if c then ue.set_hidden(c, true) end
        return true
    end)
    if err == nil then lad.hide = nil end
end
local function ladder_tick()
    local lad = st.lad
    if not lad or lad.done then return end
    if LAB.ended() then return end_hide(lad) end
    if LAB.paused() or not MODOFF.enabled('lab_cap') then return end
    local t = now()
    if lad.hide then                                    -- a shown test Cap hidden again after SHOW_S, its own frame
        if t >= lad.hide.at and spaced(t, lad.hide.name) then
            local h = lad.hide
            lad.hide = nil
            run(lad, h.name, function() local c = live(lad[h.key]) if c then ue.set_hidden(c, true) end return true end)
        end
        return
    end
    if t < lad.next_t then return end
    local p2, p1 = LAB.proof('keep.write'), LAB.proof('lab.inherit.hide')
    if p2 == false or p1 == false then
        lad.done, lad.why = true, p2 == false and 'no_keep' or 'l0i_nogo'
        return
    end
    if p2 == nil or p1 == nil or t < (st.proof_t['keep.write'] or 0) + LAB.linger_s('keep.write') then return end
    if not spaced(t) then return end                    -- the bone read, a PMC added again and every step
    local actor, dead = corpse(lad.d)
    if not actor then                                   -- the next kept-only corpse takes over
        lad.bones, lad.pmc, lad.meat = nil, nil, nil
        while true do
            if lad.d ~= nil then host_dead(lad, dead) end
            lad.d = table.remove(st.keeps, 1)
            if lad.d == nil then return end
            actor, dead = corpse(lad.d)
            if actor then break end
        end
    end
    if not lad.bones then
        local r, err = run(lad, 'lab.inherit.hide', resolve, actor, lad.d.pair)
        if type(r) == 'table' and r.leader then lad.bones = r
        elseif type(r) == 'table' then                  -- this corpse lacks the head bones: the next kept-only one
            lad.why, lad.d = 'bones:' .. tostring(r.why), nil
        else lad.done, lad.why = true, 'bones:' .. tostring(err) end   -- the read itself refused or raised
        return
    end
    local s = next_step(lad)
    if not s then return end
    if s.pmc and not live(lad.pmc) then                 -- the test PMC went with its corpse: added again, no proof
        run(lad, 'cap.pmc', add_pmc, lad, actor)
        return
    end
    local sig_ok, why = LAB.sig(s.name)
    if not sig_ok then
        if why == 'sig_mismatch' or why == 'sig_unknown' then lad.skipped[s.step], lad.i = why, lad.i + 1
        elseif why ~= 'sig_pending' then wait_until(lad, t + C.SIG_RETRY_S) end      -- pending: the next frame
        return
    end
    local r, err, ms = run(lad, s.name, s.run, lad, actor)
    local ok = err == nil and type(r) == 'table' and r.ok == true
    local f = type(r) == 'table' and type(r.f) == 'table' and r.f or {}
    f.err, f.ms, f.id, f.pair = f.err or err, ms, lad.d.id, lad.d.pair
    LAB.host_state(actor, lad.d, f)                     -- host_age_s, host_destroying (M1a 4.1 item 3)
    LAB.prove(s.step, s.name, ok, f)
    after(lad, s, ok, actor)
    lad.i = lad.i + 1
    if s.show and ok then lad.hide = { at = t + C.SHOW_S, name = s.name, key = s.show } end
end

-- ---------- lifecycle ----------
C.KEEPS = 8                                     -- kept-only corpses queued for the ladder
function C.init(adapter)
    A = adapter
    st = new_state()
    if not LAB.cut_set() then return true end
    st.init, st.keeps = true, {}
    LAB.names(N, F)
    LAB.count('cap_refused', 0)
    LAB.count('lab_cap_host_dead', 0)
    -- the vanilla compare blocks the ladder, as mod-off does; mod-off also hides the test Cap a step shows for SHOW_S
    -- (its hide-back waits while off) and 'on' shows it back. Cut Caps are not listed: hiding a Stump Cap while its
    -- bone stays hidden would show an open stump
    MODOFF.feature('lab_cap', { gameplay = true, live = function()
        local lad = st.lad
        local c = lad and lad.hide and live(lad[lad.hide.key]) or nil
        return c and { { obj = c, name = ue.name(c) } } or {}
    end })
    BUS.on('lab_row', 'lab_cap', function(row, d)       -- listeners only queue (kept-only corpses, proof times)
        if row ~= 'keep_only' or type(d) ~= 'table' or #st.keeps >= C.KEEPS then return end
        st.keeps[#st.keeps + 1] = d
        if not st.lad then st.lad = { i = 1, next_t = 0, skipped = {} } end
    end)
    BUS.on('lab_proof', 'lab_cap', function(name)
        if st.proof_t[name] == nil then st.proof_t[name] = now() end
        st.last = { name = name, t = now(), f = S.frame }  -- any module's last proof (spaced)
    end)
    S.ticker('lab_cap', ladder_tick)
    return true
end
-- A map load: queued corpses and the ladder's test components went with the old map; the step and the proofs stay
function C.reset()
    st.pend, st.keeps = { lab = 0, route = 0 }, st.init and {} or nil
    local lad = st.lad
    if lad and not lad.done then lad.d, lad.bones, lad.pmc, lad.meat, lad.hide = nil, nil, nil, nil, nil end
end
function C.status()
    local lad = st.lad or {}
    local s = C.LADDER[lad.i or 0]
    return { init = st.init, slots = st.slots, refused = st.refused, pend_lab = st.pend.lab, no_destroy = st.no_destroy,
        step = s and s.step or nil, done = lad.done, why = lad.why, skipped = lad.skipped, warm = st.warm,
        keeps = st.keeps and #st.keeps or nil, corpse = lad.d and lad.d.id or nil, host_dead = st.host_dead or 0,
        sec_test = st.sec_done, faded = st.faded, fallback = st.fallback }
end
function C.shutdown()
    S.remove_ticker('lab_cap')
    BUS.off('lab_row', 'lab_cap')
    BUS.off('lab_proof', 'lab_cap')
    st, A = new_state(), nil
end

return C
