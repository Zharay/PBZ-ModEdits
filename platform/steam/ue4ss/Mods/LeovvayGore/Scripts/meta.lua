-- status: worked SWZC (the values are new defaults) origin: kb:runtime-safety-perf#whole-mod-off-toggle
-- meta.lua: the mod's identity, the only adapter-side file with the LeovvayGore/leovvaygore tokens. Pure data: no require.
-- * build: the stamp line. tools/deploy.ps1 and package.ps1 replace the one placeholder in the shipped tree with
--   '<commit>[+dirty]-<codehash8>'; an unstamped build reads 'unstamped' in the session header.
-- * profile: 'release' (players), 'dev' (the author's lab: bare F8 mod-off, auto-armed RISKY names, the dev channel
--   when its marker exists, the features plus lab_modules) or 'probe' (a passive lab probe: lab_modules only, no
--   feature module). The repo stays 'release'; deploy -Variant probe|dev stamps the staged copy (spec M0 D4).
-- * lab_modules: the lab modules the probe and dev profiles load (main.lua, spec M0 D5); release never requires one.
--   lab_probe first: the lab core (API, stop rule, frame gauges, lab_flush) the others require (S2.9); then L0i-lite and
--   the lab keys (S2.10), the hook consumers (S2.11), the poll (S2.12), RC (S2.13), the timelines (S2.14), bleed and
--   slow-time observation (S2.15).
-- * lab_keys: TC-LAB-01's keys (D12 [P]): Ctrl+F3 lab_1, Ctrl+F5 lab_2, Ctrl+F11 lab_end (the inventory and the final
--   flush), and Ctrl+F2 lab_3 (spec M1a D15, D19 [P]: GCAP-a; lab_l0i binds it from A1.2); Ctrl+F7 lab_4, a spawn
--   target only (spawn below: lab_l0i binds it at lab_spawn's handler, so never in the probe). Ctrl with an exact
--   modifier match (UE4SS Handler.cpp:32): the bare F3, F5 and F7 that UltraPlusExtensions binds
--   with its EnableKeybinds on never fire these. None is on the D12 reserved list (Keybinds, BPModLoaderMod,
--   ConsoleEnabler, UltraPlusExtensions, SplitScreenMod, our Ctrl+F8 and Shift+F7); KEYS.bind reports a collision and
--   the key record carries it. Ctrl+F6, Ctrl+F9 and Ctrl+F10 are on that list (UltraPlusExtensions with EnableKeybinds
--   on), F4 opens the console (ConsoleEnabler) and F12 is Steam's screenshot: no lab key there.
-- * lab_risky: every sentinel name of spec M0 section 3.4 except the per-hook 'hook:<id>' (those come from the hook
--   data), then every name of spec M1a section 3.4 not listed yet, each once; main.lua adds them to the header's risky
--   list in the probe and dev profiles, never to ARM's auto list: lab names
--   are never ARM.gate'd (the lab run arms them). tests/test_lab_stage0.lua (S2.16) checks that every name a lab
--   module passes to LAB.armed or LAB.hot is listed here (tests/test_lab_spawn.lua for lab_spawn);
--   tests/test_ue4ss_main.lua checks the M1a section 3.4 names, each listed once.
-- * lab_inherited (spec M1a D4): the M1a section 3.4 names marked inherited ('yes'): after a stop LAB.armed and LAB.hot
--   refuse each listed name as they refuse 'lab.inherit.*' (A1.2); only the 'lab.inherit.' prefix keeps the M0 D9 start
--   rule. lab_linger (D4): the seconds a name stays armed after a call that ran, per M1a section 3.4 (the default when a
--   name is absent: 2 for an inherited name, 0 otherwise).
-- * dev_sets, dev_set (spec M1a D2; M0 D32 before it): the lab modules only the dev profile loads, after lab_modules,
--   as named sets: 'spawn' (TC-LAB-01 on spawned targets: lab_spawn, the one lab world write) and 'lab02' (TC-LAB-02,
--   the armed lab: the eight M1a modules). main.lua loads META.dev_sets[META.dev_set].modules in the dev profile only;
--   an unknown set name loads none and writes one start_error. The probe and release never require them. deploy
--   -Variant dev keeps the dev_set line byte for byte (spec M1a A1.9); A5.5 commits 'lab02' after TC-LAB-01's verdict.
-- * beta, beta_modules (docs/research/beta-port-steps.md S1, route A0): with beta true the release profile loads
--   beta_modules, the lab modules TC-LAB-02 runs 4-10 ran, in their dev order (lab_modules, then the lab02 set: the bus
--   listeners and the tickers keep their order); lab_keep, lab_spawn, lab_skin, lab_rc, lab_tl and lab_obs stay out.
--   lab_probe's LAB.beta() reads the same condition (profile 'release' and beta true): the cut set, no lab key, no
--   S-STATE or S-SPAWN-a, no UE4SS.log tail scan. The probe and dev profiles ignore both, so the lab keeps working.
-- * beta_spawn (the author's test build; «wait, stop, what do you mean there are no spawn keys / bring them back», 2026-10-31): with beta true
--   main.lua also loads lab_spawn after beta_modules, only when its file is there (a missing file is no failure: one
--   beta_spawn record). deploy.ps1 installs every file, so the build the author tests has the spawn keys (spawn
--   below); the player zip leaves lab_spawn.lua out (DEFAULTS ship_lab_tools), so it has none and no error.
--   lab_spawn's handlers bind the spawn keys alone through lab_l0i (no other lab key), every press keeps its
--   lab.spawn.* sentinel names and gates (L0i-lite, mod-off, the vanilla compare, the rate and caps), and lab_plan's
--   beta sig pass adds those names while lab_spawn runs. lab_keep stays out: a spawned pawn dies into a vanilla corpse
--   the beta cuts as any other. The probe and dev profiles ignore it.
-- * test_keys (the test build; the author 2026-11-01 «I did make those calls, by the way»: no console line reached the mod, as
--   UE4SS 1185 fails its ProcessConsoleExec hook in PBZ): with beta_spawn, main.lua also loads lab_testkeys after
--   lab_spawn (only when its file is there; the player zip leaves it out), which binds these keys to the console verbs
--   (lab_testkeys.lua's header): Shift+F1 grey census (press1, press2, ...), Shift+F2 soul_recv toggle, Shift+F3 leash
--   toggle, Shift+F8 soul_ovl toggle, Shift+F5 cap_look cycle, Shift+F6 hair_mode toggle, Shift+F9 blood_amount cycle,
--   Shift+F10 max_parts cycle. Shift with an exact modifier match: clear of the reserved list above and of
--   UltraPlusExtensions' keybinds.ini (F12, Alt+F12, Alt+F2) and Alt+F8/Alt+F9. Never F4 (ConsoleEnabler's console
--   key; the engine's console-key check may not look at Shift), F11 (UE5's F11 fullscreen toggle skips only Ctrl and
--   Alt, unverified in PBZ), F12 (Steam's screenshot), Shift+F7 (vanilla) or Alt+F4.
-- * beta_pins, beta_seed (beta port S2): the proofs the beta takes from runs 4-10 instead of the keep and ladder gate.
--   On its first lab tick with a build key, lab_probe compares the three pins together (the header's game_build, the
--   ARM build key, the header's loader commit; the values of every run 4-11 header and session_engine record); all
--   three equal: every beta_seed name is proven (LAB.seed: bus lab_proof each, one proof_seed record), else nothing is
--   (one beta_unpinned record: blood stays, cuts stay off). The seed list is the 16 ladder names runs 4-10 proved
--   ok in every record (scratch/port/proofs.py) less keep.write (no lab_keep in the beta), P1b, P9 and P9b (no
--   route reads them). L0i-lite is still earned live in every session.
-- * The beta's dismemberment (docs/research/beta-dismemberment-plan.md BD0, the contract of BD1-BD13 and lab_gib):
--   - beta_modules adds lab_census (after lab_poll), lab_look (after lab_plan), lab_gib (after lab_cut) and lab_fade
--     (after lab_gib): bus listeners and tickers run in this order.
--   - lab_risky, lab_inherited and lab_linger add the names of lab_look (cap.look.*, the LVF CVar), lab_cap's test
--     section (cap.look.section), lab_fade (lab.read.dissolve), lab_census (lab.read.census, .bodysize, .bounds) and
--     lab_gib (gib.*, extra.fall, hair.keep). None is seeded or ladder-proven: each module checks its own name
--     (SENT.is_disabled, LAB.sig) and LAB.pinned() before any native call. Inherited (refused after a stop): the
--     ones that create, attach or simulate objects, and the census's array reads; reads and loads are not.
--   - beta_limbs, beta_scan, beta_extras, beta_fade, beta_gib: one switch per new behaviour (integration's cut lines):
--     limbs (false: head only), the cut-subtree scan, the extra poseables on a Piece, the dissolve fade of the Caps,
--     lab_gib (false: no falling hats or masks, no burst head, no kept hair; a head that needs lab_gib is refused
--     'gib_off'). The console knobs are core/config.lua's C.KNOBS.
-- * lab_leash (docs/research/grey-under-trees.md fix 1; the author 2026-11-01: «let's try both options, yes»):
--   beta_modules lists it after lab_blood (lab_corpse follows); off by default ('<prefix> leash on|off', knob
--   leash_cm). lab_risky and lab_linger add leash.find, leash.read, leash.write and leash.restore (none inherited,
--   none seeded).
-- * The beta's corpse keep (the author, 2026-11-01: «all corpses stay 15 min»): beta_modules ends with lab_corpse (after
--   lab_leash), which writes the three proven keep levers on every admitted enemy and lets a corpse go after
--   corpse_keep_s (lab_corpse.lua's header; never in the probe or dev profiles, where lab_keep keeps the lab's
--   corpses). lab_risky, lab_linger and data/lab_classes.lua add its 'corpse.*' names, none inherited (a stop must not
--   leave kept corpses that can no longer go).
-- * The beta's volumetric drops (the author, 2026-11-01: «I don't care about pools / more volumetric drops»):
--   beta_modules lists lab_drops after lab_blood (whose bus lab_bleed it follows); beta_drops is its switch (false:
--   inert). lab_risky and lab_linger add drop.warm, drop.pmc, drop.fly, drop.land and drop.stop (the first three
--   inherited: they create or move objects), none seeded; the knobs drops, drops_n and drops_max live in
--   core/config.lua. test_keys adds Ctrl+Shift+F1, the drops on/off toggle (an exact modifier match: Shift+F1 stays
--   the grey census).
-- * The game's own skeletal-mesh slicer (docs/research/slicer-stumps.md; the author 2026-11-01: «there must be a way in
--   ue to make really ultra-high-quality stumps»): beta_modules ends with lab_slice, the slicer primitives, inert (no
--   listener, ticker or record; no native call unless a caller asks). lab_risky, lab_linger and data/lab_classes.lua
--   add its names: slicer.read, slicer.lodinfo, the CVar probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics,
--   slicer.preflight, slicer.load, slicer.mat, one cut name per body asset (slicer.cut.malethug, slicer.cut.guichai),
--   slicer.after, slicer.rehome, slicer.fix, slicer.push and slicer.gone (lab_corpse's going of a sliced corpse);
--   inherited: the LODInfo array read and the ones that create, attach, move or destroy, but slicer.gone (a corpse
--   name, as corpse.*: a stop must not leave kept sliced corpses that can no longer go). None is seeded. The test
--   build's S0 probe is lab_slice_probe (main.lua loads it with lab_spawn and lab_testkeys, only when its file is
--   there; the player zip leaves it out); test_keys adds Ctrl+Shift+F2 (slice_probe), clear of Shift+F2 (soul_recv),
--   Ctrl+F2 (lab_3, probe and dev only), UltraPlusExtensions' F2 and Alt+F2 and Keybinds' Ctrl+J, Ctrl+H and Ctrl+Num
--   (exact modifier matches).
-- * The game's own slice, observed (the route A study, 2026-11-01: the HeiMoShang execution slices MaleThug-skeleton
--   victims through GAAction_SliceSkeleton_C): the test build also loads lab_slice_watch (main.lua TEST_BUILD, only
--   when its file is there; the player zip leaves it out), a passive listener of the game's Prepare, SlicePrepared,
--   Capture, Release and Restore calls and of the slice action's events (data/hooks.json h25, h27-h32), one
--   vanilla_slice record per call. Its reads run under slicer.watch (lab_risky, linger 0, not inherited: reads only).
-- * The route's LOD experiment (the same study: UE 5.7 keeps the per-LOD CPU bit in SkeletalMesh.SourceModels, and
--   LODInfo reads empty): when the LOD 0 preflight reports 'failed while extracting source data', lab_slice_route
--   tries LOD 1-3 and then Prepare on LOD 0 (lab_slice_route's header 'pre', lab_slice_lod's). slicer.cpuflag is now
--   the LOD 0 preflight with the bit set and restored in its one call (the route runs it only as X4's rung after
--   Prepare, and never on a LOD 0 bit that read false: that job skips LOD 0 and X4, so it writes nothing there);
--   slicer.lodpre the LOD 1-3 ones (1 s);
--   slicer.prepare and slicer.release the game's Prepare and Release (3 s; Release not inherited, so a stop can still
--   undo a forced LOD); slicer.prep.read the wait for the prepared LOD (ForcedLodModel, GetPredictedLODLevel: 0 s, not
--   inherited, reads only); slicer.cut.prep the prepared cut, SlicePreparedSkeletalMeshComponentRuntime (10 s,
--   inherited). None is seeded. slicer.cut.lod (the direct cut on LOD k) crashed natively in the 2026-11-01 22:17 lab
--   run: it is retired, in no list here, and never reused (the author's disabled.json keeps it).
-- * The slicer on ordinary deaths (docs/research/slicer-stumps.md sections 4, 5 and 7; the author 2026-11-01: «I
--   need not just research but the implementation too»): beta_modules ends with lab_slice_route after lab_slice, and
--   beta_slicer is its switch (false: inert, every death the joint cut). lab_plan gives a death the row 'slice' where
--   it would give 'heads' when the route wants it; a job that cannot slice hands it back as 'heads' (one slice_skip
--   record). Its names: the cut of every other cut class by the row's route (slicer.cut.body, slicer.cut.meshhead) and
--   the re-slice of a half (slicer.reslice), each 10 s and inherited; none seeded. The knob 'slicer' (core/config.lua,
--   default on) switches the route live; test_keys adds Ctrl+Shift+F3 (slicer), its on/off toggle, clear of Shift+F3
--   (leash), Ctrl+F3 (lab_1, the MaleThug spawn), UltraPlusExtensions' bare F3 (Vignette; its keybinds register only
--   with EnableKeybinds on, and it is off) and Keybinds' Ctrl+J, Ctrl+H and Ctrl+Num (exact modifier matches;
--   LineTraceMod's bare F3 is disabled in mods.json).
-- * A sliced victim in the rest of the beta: lab_blood's bleed of a slice runs every call that reads, attaches to or
--   names a half under its own slicer.blood (LAB.hot as the blood.* names, no data/lab_classes.lua row; inherited, 3
--   s), never under a shared blood.* name; a sliced head's hats and masks are read and hidden under slicer.drop
--   (lab_slice_route, 3 s) and fall as lab_gib's copies under slicer.fall (extra.fall's class row, 10 s), both inherited
--   and in lab_plan's sig pass (lab_slice's names with a class row).
-- * Blood on the sword (spike S1 of scratch/swordblood/spike_spec.md with its skeptic's corrections; the author
--   2026-11-01: «launch a research workflow so the blood can stay on the sword only and not on Soul», then
--   2026-11-02 «I left the last mode on Ctrl+Shift+F5 as the reference one»: look A ships): beta_modules lists lab_sword
--   after lab_drops (it follows lab_blood's bus lab_bleed and lab_soul_heal), look A on the material of Soul's weapon
--   meshes, its setting sword_blood (core/config.lua, the Mods Menu row 'Blood on the sword'). The spike's other looks
--   and the look key stay in the test build: lab_sword_looks (main.lua TEST_BUILD before lab_testkeys, only when its
--   file is there; the player zip leaves it out). test_keys adds Ctrl+Shift+F5 (sword_look, the look cycle), clear of
--   Shift+F5 (cap_look), Ctrl+F5 (lab_2, probe and dev only) and UltraPlusExtensions' bare F5 (exact modifier
--   matches). Its names, none seeded: sword.read (the reads,
--   GetAttachedActors, GetNumMaterials and GetMaterial: 0 s, a proven read bare too in lab_hot_linger: the watch reads
--   every 3 s for the map), sword.load (a donor's LoadAsset and hold: 3 s), sword.mid (our MID: 1 s), sword.copy
--   (K2_CopyMaterialInstanceParameters: 1 s), sword.mat (SetMaterial on the game's Weapon Mesh: 3 s), sword.amt
--   (by-name writes on our MID: 0 s), sword.cpd (the custom primitive data setter on the game's mesh: 1 s),
--   sword.byinfo (the by-info setters and getter, the test build's look B: 0 s) and sword.restore (the vanilla material
--   and data back: 3 s);
--   inherited: load, mid, copy, mat, cpd and byinfo (never sword.restore: a stop must still give a weapon its material
--   back, as slicer.release; never the reads or the writes on our own MID).
-- * Jamon Iberico (cap_look 'textured'; the author 2026-11-02 after the f93cf2f run: «I didn't see much difference between
--   the jamon modes»): beta_modules lists lab_iberico after lab_look (lab_cap asks it at every reserve and section), the
--   DD2 pipeline's fitted Caps (data/caps_dd2) on the bodies they fit and our own atlas PNG as a MID of a game parent
--   (lab_iberico.lua's header). Its names, none seeded: cap.tex.load (a parent's find or LoadAsset: 3 s), cap.tex.import
--   (KismetRenderingLibrary:ImportFileAsTexture2D, a transient texture whose render resource is made after the call:
--   10 s), cap.tex.read (the texture's size getters and property reads: 0 s), cap.tex.mid (the MID, its texture
--   parameter and the read-back: 10 s); inherited: import and mid (they create objects), never the load or the reads.
--   The hold is cap.keep (P9b's class). test_keys adds Ctrl+Shift+F6 (cap_atlas: lab_iberico's look cycle, the
--   calibration atlas and the second parent), clear of Shift+F6 (hair_mode), UltraPlusExtensions' bare F6 and Ctrl+F6
--   (exact modifier matches) and F4 (ConsoleEnabler's console key).
-- * DEFAULTS (beta port S8): the zip's ship switches. tools/package.ps1 reads this one table as text for the
--   package.ship_when rows of gore.project.json (one 'key = true|false' per line, the closing brace in column 0); no
--   Lua reads it. ship_lab_tools false: the player zip leaves out the lab-only modules, which META.beta_modules never
--   lists (lab_keep: the corpse-keep levers LingeringDead writes too, and the ladder host; lab_spawn: CheatManager
--   Summon and the deferred spawn; lab_testkeys: the test keys; lab_slice_probe: the slicer's S0 probe;
--   lab_slice_watch: the game-slice listener; lab_sword_looks: the sword spike's other looks and its key; lab_skin:
--   the skin-weight dump to disk;
--   lab_rc, lab_tl, lab_obs).
--   ship_lab_hold
--   true: lab_hold ships while META.beta_modules lists it (S10 c turns both off together, else every start writes a
--   start_error). deploy.ps1 installs every file, so -Variant dev and probe keep the lab.
-- * lab_card (D4, A1.2): the card a lab build's ARM mark label names: the probe's here, else the dev set's card.
-- * lab_consent (D12, D26): the author's answers that gate a lab route. respawn: the level spawner's Respawn may write
--   the spawner's save state, so it runs only when true (A5.5 commits the author's part A answer; no answer is no).
-- * spawn: lab_spawn's data (D32, M1a D12). targets by lab key action: in the dev build and the beta test build
--   (beta_spawn) Ctrl+F3 (lab_1) and Ctrl+F5 (lab_2) each spawn one target; their key record stays as in the probe.
--   Both pairs start with the deferred spawn, the live CheatManager's Summon of the class path the fallback
--   (lab_spawn M.FIRST; spec M1a 4.0 and 4.2 item 4: a bare Summon left GuiChai Black invisible, MaleThug hidden
--   0.63-0.69 m from the player). family is the pair label (lab_probe LAB.PAIRS), class the class name, asset the
--   Blueprint package (the class object is '<asset>.<class>'; docs/research/compare/work/K02/usmap/structs.tsv:
--   22305, :23695, both BP_RenewalNPC_C descendants). press_s and cap: at most one press per press_s and cap spawn
--   attempts per session (the D12 values); near_m: the new pawn must appear near_m from the player; load_s: no spawn
--   in the first load_s after a map load.
--   - Ctrl+F7 (lab_4): a class the beta's new features show on, off the pairs (family is then the class's own label;
--     the record's pair reads 'other'): BP_Monster_IronMaskMan_C, the mask that falls off (data/cut_classes.lua row
--     B7_mask_body, fall 'Mask', route body). Its path is the census's (data/census.json 011_IronMaskMan base; the
--     same in the usmap struct index, docs/research/compare/work/K02/usmap/structs.tsv:20666); no class of
--     cut_classes.lua has a hat, and no cloth-hair (head_mode 'burst') class has its Blueprint path in the object dump
--     or the census, so neither has a key. first: the target's own first route, before M.FIRST: 'deferred', which
--     needs no CheatManager (Summon does: CheatManagerEnablerMod in mods.txt).
-- * steam_appid, saved_subdir, build_pins: no gore verb writes this file; copied by hand from gore.project.json
--   (spec M0 S2.1). nil = not read.
--   - steam_appid '4115450' (game.steam_appid): ENV.steam_buildid() reads appmanifest_4115450.acf, so the header's
--     game_build is the live Steam buildid ('unknown' only when the manifest is not found).
--   - saved_subdir 'ProjectPBZ': E.state = %LOCALAPPDATA%/ProjectPBZ/Saved/LeovvayGore_ (adapter/env.lua), the
--     game's own Saved folder (Config, Logs, Crashes; no SaveGames there). Settings and arm markers sit outside the
--     install, so a mod update or reinstall keeps them, and never next to the saves (those live under the install,
--     ProjectPBZ/Saved/SaveGames/Steam/<id>).
--   - build_pins: the build the hooks and names were checked on (game.build_pin buildid 26266538, engine.version
--     5.7.4, the changelist of the static recon). The header's game_build is the live value; a mismatch means a patch.
-- * region_gates (main.lua logs them as the header's gates): static, spec M0 D7. Recon found no region or rating
--   switch, only the PBZCensor gate (gore.project.json game.region_gates), so region and rating are 'none'; censor
--   'live' means its values are read in game and logged in the env record (adapter/session_pbz.lua, S2.8), never here:
--   the header is written on the update thread before any engine name resolves. A gore mod never obeys them.
-- * data_dir (nil = the mod folder, where tools/lab looks for dev.json, cmd.json and log.*.jsonl) and mods_txt (nil =
--   <Mods>/mods.txt) are absolute overrides, mainly for offline tests.
-- Evidence: [worked SWZC] Scripts/data/builds.lua, config.lua keys (Ctrl+F8 in player, F8 in dev);
-- kb:author-preferences (keys); kb:recon-feasibility principle 21 (log the region gates)
local META = {}
META.mod = 'LeovvayGore'
META.prefix = 'leovvaygore'
META.VERSION = '0.2.3-beta'   -- gore new renders mod.version; package checks the two agree
META.build = '3793fd1-5a72400a' -- BUILD_STAMP (deploy rewrites this token; keep it the only one in the tree)
META.profile = 'release'
META.steam_appid = '4115450'
META.saved_subdir = 'ProjectPBZ'
META.region_gates = { region = 'none', rating = 'none', censor = 'live' }   -- static (D7); live values: env record
META.build_pins = { buildid = '26266538', engine = '5.7.4', changelist = 'CL-301524_JKS-17219' }
META.data_dir = nil
META.mods_txt = nil
META.api_global = nil        -- the public API table name (core/api.lua), nil = no API
-- Keys (UE4SS Key / ModifierKey names). Bare F8 was too easy to hit in play: players get Ctrl+F8.
META.keys = { modoff = { key = 'F8', mods = { 'CONTROL' } }, vanilla = { key = 'F7', mods = { 'SHIFT' } } }
META.dev_keys = { modoff = { key = 'F8', mods = {} } }
META.warm_start_ms = 3000    -- the first warm step after a map load; then one module per warm_step_ms
META.warm_step_ms = 150
-- probe and dev only (main.lua, D5): the lab core first, then the lab modules in their bus order
META.lab_modules = { 'lab_probe', 'lab_l0i', 'lab_kill', 'lab_poll', 'lab_rc', 'lab_tl', 'lab_obs' }
META.lab_keys = { lab_1 = { key = 'F3', mods = { 'CONTROL' } }, lab_2 = { key = 'F5', mods = { 'CONTROL' } },
    lab_end = { key = 'F11', mods = { 'CONTROL' } }, lab_3 = { key = 'F2', mods = { 'CONTROL' } },
    lab_4 = { key = 'F7', mods = { 'CONTROL' } } }
-- M0 section 3.4 names, by call class: static CDO calls, CVar reads, the PBZ censor statics, reflection meta, the
-- inherited instance calls (refused after a stop, D9), new property types at death rate and at 10 Hz, FindAllOf, the
-- dev spawn key's LoadAsset and Summon (D32); then the M1a section 3.4 names in table order (probe.meta,
-- lab.spawn.load and lab.spawn.summon are listed above)
META.lab_risky = {
    'probe.static.GetEngineVersion', 'probe.static.GetFrameCount',
    'probe.cvar.PBZ.Censor.LaunchCensored', 'probe.cvar.z.Censoredlelvel',
    'pbz.censor.IsLaunchCensored', 'pbz.censor.GetCensored', 'pbz.censor.GetSuperCensored',
    'pbz.censor.IsCensoredVersion',
    'probe.meta',
    'lab.inherit.ipc', 'lab.inherit.bones', 'lab.inherit.rc', 'lab.inherit.sim', 'lab.inherit.summon',
    'lab.read.tmap', 'lab.read.multicast', 'lab.read.gas',
    'lab.findall',
    'lab.spawn.load', 'lab.spawn.summon',
    -- M1a section 3.4: the hide group and time, the keep levers, the mob group read
    'lab.inherit.hide', 'probe.static.GetTimeSeconds', 'keep.write', 'lab.inherit.group',
    -- Caps (ladder P3-P9b) and the TArray probe (P4)
    'cap.pmc', 'lab.tarray.probe', 'cap.mid', 'cap.parent', 'cap.mesh', 'cap.meat', 'cap.destroy', 'cap.keep',
    -- Pieces (P10-P16) and the head components (P17, P18)
    'hide.optim', 'piece.spawn', 'piece.mesh', 'piece.pose', 'piece.isolate', 'piece.phys', 'piece.destroy',
    'hide.comp', 'hide.tag',
    -- the commit: the bone hide, the per-cut routes, the read-back
    'hide.bone', 'lab.cut.stage', 'lab.cut.head', 'lab.cut.limb', 'lab.cut.gcap', 'lab.read.bonehidden',
    -- the spawn press (D12)
    'lab.spawn.deferred', 'lab.spawn.respawn', 'lab.spawn.move', 'lab.spawn.ai', 'lab.spawn.hold',
    -- S-SKIN (D16)
    'lab.skin.holder', 'lab.skin.copy', 'lab.skin.bones', 'lab.skin.read',
    -- CVar reads, mod-off
    'probe.cvar.r.FreeSkeletalMeshBuffers', 'probe.cvar.PBZ.Character.EnableHeadBonesToRemove',
    'modoff.hide', 'modoff.unhook',
    -- lab_blood (the beta's blood, lead 2026-10-31): system lookups, sprays, skinned decals, reads, the vanilla observer;
    -- Soul's splashes destroyed at a full heal (bd-heal)
    'blood.load', 'blood.fx', 'blood.spurt', 'blood.decal', 'blood.setup', 'blood.read', 'blood.comps', 'blood.hook',
    'blood.look', 'blood.adecal', 'blood.recv', 'blood.pool', 'blood.player', 'blood.wash',
    -- the beta's dismemberment (BD0): the cap look probe and the test section, the LVF CVar, the dissolve, the census,
    -- lab_gib's loads, carriers, meshes, physics, FX and destroys, the falling hats and masks, the kept hair
    'cap.look.load', 'cap.look.read', 'cap.look.mid', 'cap.look.slicer', 'cap.look.section',
    'probe.cvar.r.Material.IgnoreLVFUsageMode', 'lab.read.dissolve', 'lab.read.census', 'lab.read.bodysize',
    'lab.read.bounds', 'gib.load', 'gib.spawn', 'gib.mesh', 'gib.phys', 'gib.fx', 'gib.destroy', 'extra.fall',
    'hair.keep',
    -- lab_leash (the grey in tree shade, fix 1): the decal scan, the decal reads, the capped depth, the restore
    'leash.find', 'leash.read', 'leash.write', 'leash.restore',
    -- the beta's corpse keep (lab_corpse): the keep levers, the on-screen read, the vanish, the destroy
    'corpse.keep', 'corpse.seen', 'corpse.vanish', 'corpse.destroy',
    -- the grey A/B (2026-11-01, lab_blood's console verbs, lab_grey.lua): the world-decal census (FindAllOf and its
    -- reads); 'soul_ovl', route A3 on Soul: reads, the sampler set-up, the TB MID and its hold, the overlay set and
    -- cleared, SpawnDecal with DecalLast, the render-target texels
    'grey.census', 'blood.ovl.read', 'blood.ovl.setup', 'blood.ovl.mid', 'blood.ovl.set', 'blood.ovl.decal',
    'blood.ovl.rt',
    -- the beta's volumetric drops (lab_drops): the pool's keeper and meshes, their movement components, the launch, the
    -- landing polls and stains, the time-outs and the off hide
    'drop.warm', 'drop.pmc', 'drop.fly', 'drop.land', 'drop.stop',
    -- the game's own slicer (lab_slice): the reads, the LODInfo CPU bit, the crash-flagged CVar, the preflight, the cap
    -- material's load, hold and flags, the cut per body asset, the after reads, the re-home, the source fix, the
    -- head-half impulse, a sliced corpse's going (lab_corpse)
    'slicer.read', 'slicer.lodinfo', 'slicer.cpuflag', 'probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics',
    'slicer.preflight', 'slicer.load', 'slicer.mat', 'slicer.cut.malethug', 'slicer.cut.guichai', 'slicer.after', 'slicer.rehome',
    'slicer.fix', 'slicer.push', 'slicer.gone',
    -- the production slice route (lab_slice_route): the cut of every other cut class by its row's route, the re-slice
    -- of a half that still holds the next part
    'slicer.cut.body', 'slicer.cut.meshhead', 'slicer.reslice',
    -- a slice's bleed on its halves (lab_blood: the reads, the attached decals and spurts, the half's decal switch), a
    -- sliced head's hats and masks (lab_slice_route's read and hide, lab_gib's falling copies)
    'slicer.blood', 'slicer.drop', 'slicer.fall',
    -- the test build's listener of the game's own slice (lab_slice_watch): the source mesh, its LOD bits and the halves
    'slicer.watch',
    -- the route's LOD experiment (lab_slice_lod; slicer.cpuflag above is its LOD 0 rung): the LOD 1-3 preflights with
    -- the CPU bit set and restored, Prepare and Release, the wait for the prepared LOD, the prepared cut
    'slicer.lodpre', 'slicer.prepare', 'slicer.release', 'slicer.prep.read', 'slicer.cut.prep',
    -- the native Cap look (route B of docs/research/slicer-stumps.md, lab_cap): the vertebra stub on a neck Cap, the
    -- wound ring decal on every native Stump Cap
    'cap.stub', 'cap.ring',
    -- blood on the sword (lab_sword; sword.byinfo: the test build's lab_sword_looks): the reads, a donor's load, our
    -- MID, the copy, the swap on the game's Weapon Mesh, the by-name writes, the custom primitive data setter, the
    -- by-info probe, the restore
    'sword.read', 'sword.load', 'sword.mid', 'sword.copy', 'sword.mat', 'sword.amt', 'sword.cpd', 'sword.byinfo',
    'sword.restore',
    -- Jamon Iberico (lab_iberico): the parent's load, our PNG's import, the texture's reads, our atlas MID
    'cap.tex.load', 'cap.tex.import', 'cap.tex.read', 'cap.tex.mid',
}
-- M1a section 3.4's inherited ('yes') names: refused after a stop besides 'lab.inherit.*' (D4)
META.lab_inherited = {
    'cap.pmc', 'lab.tarray.probe', 'cap.mid', 'cap.parent', 'cap.mesh', 'cap.meat', 'cap.destroy', 'cap.keep',
    'hide.optim', 'piece.spawn', 'piece.mesh', 'piece.pose', 'piece.isolate', 'piece.phys', 'piece.destroy',
    'hide.comp', 'hide.tag', 'hide.bone', 'lab.cut.stage', 'lab.cut.head', 'lab.cut.limb', 'lab.cut.gcap',
    'lab.read.bonehidden', 'lab.spawn.summon', 'lab.spawn.move', 'lab.spawn.ai', 'lab.spawn.hold',
    'lab.skin.holder', 'lab.skin.copy', 'lab.skin.bones', 'lab.skin.read',
    -- the beta (BD0): the ones that create, attach or simulate objects, and the census's array reads
    'cap.look.mid', 'cap.look.section', 'lab.read.census', 'gib.spawn', 'gib.mesh', 'gib.phys', 'gib.destroy',
    'extra.fall', 'hair.keep',
    -- the volumetric drops: the ones that create or move objects
    'drop.warm', 'drop.pmc', 'drop.fly',
    -- the slicer: the LODInfo array read, the cap material's hold (a keeper component on the controller), the cuts, the
    -- re-home, the source fix, the impulse (never slicer.gone, a sliced corpse's going: a corpse name)
    'slicer.lodinfo', 'slicer.cpuflag', 'slicer.load', 'slicer.cut.malethug', 'slicer.cut.guichai', 'slicer.rehome', 'slicer.fix',
    'slicer.push', 'slicer.cut.body', 'slicer.cut.meshhead', 'slicer.reslice',
    -- a slice's bleed: it attaches to the runtime halves; the hats' hide and their falling copies
    'slicer.blood', 'slicer.drop', 'slicer.fall',
    -- the LOD experiment: the bit writes, the forced LOD, the prepared cut (never slicer.release: a stop must still
    -- give a prepared component its forced LOD back; never slicer.prep.read: reads only)
    'slicer.lodpre', 'slicer.prepare', 'slicer.cut.prep',
    -- the native Cap's stub: it adds, meshes and attaches a component, as cap.meat
    'cap.stub',
    -- blood on the sword: the load and hold, our MID, the copy, the swap and the setters on the game's mesh and our MID's by
    -- info (never sword.restore: a stop must still give a weapon its material back; never sword.read or sword.amt)
    'sword.load', 'sword.mid', 'sword.copy', 'sword.mat', 'sword.cpd', 'sword.byinfo',
    -- Jamon Iberico: the import and the MID create objects (never the parent's load or the reads)
    'cap.tex.import', 'cap.tex.mid',
}
-- M1a section 3.4's lingers in seconds after a call that ran (D4)
META.lab_linger = {
    ['lab.inherit.hide'] = 2, ['probe.static.GetTimeSeconds'] = 0, ['probe.meta'] = 0, ['keep.write'] = 3,
    ['lab.inherit.group'] = 2,
    ['cap.pmc'] = 3, ['lab.tarray.probe'] = 10, ['cap.mid'] = 10, ['cap.parent'] = 3, ['cap.mesh'] = 10,
    ['cap.meat'] = 10, ['cap.destroy'] = 3, ['cap.keep'] = 10,
    ['hide.optim'] = 3, ['piece.spawn'] = 3, ['piece.mesh'] = 3, ['piece.pose'] = 3, ['piece.isolate'] = 3,
    ['piece.phys'] = 3, ['piece.destroy'] = 3, ['hide.comp'] = 3, ['hide.tag'] = 3,
    ['hide.bone'] = 2, ['lab.cut.stage'] = 10, ['lab.cut.head'] = 3, ['lab.cut.limb'] = 3, ['lab.cut.gcap'] = 3,
    ['lab.read.bonehidden'] = 1,
    ['lab.spawn.load'] = 3, ['lab.spawn.summon'] = 3, ['lab.spawn.deferred'] = 3, ['lab.spawn.respawn'] = 3,
    ['lab.spawn.move'] = 3, ['lab.spawn.ai'] = 3, ['lab.spawn.hold'] = 3,
    ['lab.skin.holder'] = 3, ['lab.skin.copy'] = 10, ['lab.skin.bones'] = 3, ['lab.skin.read'] = 3,
    ['probe.cvar.r.FreeSkeletalMeshBuffers'] = 0, ['probe.cvar.PBZ.Character.EnableHeadBonesToRemove'] = 0,
    ['modoff.hide'] = 3, ['modoff.unhook'] = 3,
    ['blood.load'] = 3, ['blood.fx'] = 3, ['blood.spurt'] = 3, ['blood.decal'] = 3, ['blood.setup'] = 3,
    ['blood.read'] = 0, ['blood.comps'] = 0, ['blood.hook'] = 0, ['blood.look'] = 3,
    ['blood.adecal'] = 3, ['blood.recv'] = 3, ['blood.pool'] = 3, ['blood.player'] = 3, ['blood.wash'] = 0,
    -- the beta (BD0); an inherited name lingers at least LAB.INHERIT_LINGER_S whatever this says
    ['cap.look.load'] = 3, ['cap.look.read'] = 0, ['cap.look.mid'] = 10, ['cap.look.slicer'] = 3,
    ['cap.look.section'] = 10, ['probe.cvar.r.Material.IgnoreLVFUsageMode'] = 0, ['lab.read.dissolve'] = 0,
    ['lab.read.census'] = 0, ['lab.read.bodysize'] = 3, ['lab.read.bounds'] = 3,
    ['gib.load'] = 3, ['gib.spawn'] = 3, ['gib.mesh'] = 10, ['gib.phys'] = 3, ['gib.fx'] = 3, ['gib.destroy'] = 3,
    ['extra.fall'] = 10, ['hair.keep'] = 10,
    -- lab_leash: a size write's proxy is rebuilt at the end of the frame (render thread), so the writes linger longer
    ['leash.find'] = 1, ['leash.read'] = 1, ['leash.write'] = 3, ['leash.restore'] = 3,
    -- the beta's corpse keep (lab_corpse): three property writes with read-back, no delayed effect of their own; a
    -- read; the Blueprint vanish (a dissolve on the render side) and the actor destroy
    ['corpse.keep'] = 1, ['corpse.seen'] = 0, ['corpse.vanish'] = 3, ['corpse.destroy'] = 3,
    -- the grey A/B (2026-11-01)
    ['grey.census'] = 1, ['blood.ovl.read'] = 1, ['blood.ovl.setup'] = 3, ['blood.ovl.mid'] = 3, ['blood.ovl.set'] = 3,
    ['blood.ovl.decal'] = 3, ['blood.ovl.rt'] = 3,
    -- the volumetric drops: the warm-up's components register and build physics state (3), a launch's movement runs on
    -- the next ticks (2), the reads, hides and stain moves (1)
    ['drop.warm'] = 3, ['drop.pmc'] = 3, ['drop.fly'] = 2, ['drop.land'] = 1, ['drop.stop'] = 1,
    -- the slicer: the halves' render and physics state build after the call and the ragdoll starts a step later (10,
    -- the cut and the going of a sliced corpse), the re-home, fix and impulse take effect on the next ticks (3), the
    -- material load (3), the preflight and after reads (1), the plain reads (0; slicer.lodinfo lingers the inherited 2)
    ['slicer.read'] = 0, ['slicer.lodinfo'] = 0, ['slicer.cpuflag'] = 1, ['probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics'] = 0,
    ['slicer.preflight'] = 1, ['slicer.load'] = 3, ['slicer.mat'] = 0, ['slicer.cut.malethug'] = 10,
    ['slicer.cut.guichai'] = 10, ['slicer.after'] = 1, ['slicer.rehome'] = 3, ['slicer.fix'] = 3, ['slicer.push'] = 3,
    ['slicer.gone'] = 10, ['slicer.cut.body'] = 10, ['slicer.cut.meshhead'] = 10, ['slicer.reslice'] = 10,
    -- a slice's bleed: the attached spurts and decals render and tick after the call (3, as blood.spurt); the hats'
    -- hide (3, as slicer.rehome) and their falling copies (10, as extra.fall)
    ['slicer.blood'] = 3, ['slicer.drop'] = 3, ['slicer.fall'] = 10,
    -- the game-slice listener's reads (lab_slice_watch): property reads and getters, no delayed effect
    ['slicer.watch'] = 0,
    -- the LOD experiment: a rung as the preflight (1), the forced LOD streams over the next frames (3), the wait's
    -- reads (0), the prepared cut (10, as every cut)
    ['slicer.lodpre'] = 1, ['slicer.prepare'] = 3, ['slicer.release'] = 3, ['slicer.prep.read'] = 0,
    ['slicer.cut.prep'] = 10,
    -- the native Cap's stub: a mesh component added and attached, as cap.meat (10); the ring: an attached decal that
    -- renders after the call, as blood.adecal (3)
    ['cap.stub'] = 10, ['cap.ring'] = 3,
    -- blood on the sword: the reads and our MID's by-name and by-info writes (0), our MID and its copy (1), the custom
    -- primitive data that renders after the call (1), a donor's load and hold, the swap and the restore on the game's
    -- mesh (3: a new material's render state, a possible PSO compile)
    ['sword.read'] = 0, ['sword.load'] = 3, ['sword.mid'] = 1, ['sword.copy'] = 1, ['sword.mat'] = 3, ['sword.amt'] = 0,
    ['sword.cpd'] = 1, ['sword.byinfo'] = 0, ['sword.restore'] = 3,
    -- Jamon Iberico: a parent's load (3, as cap.look.load), the import (10: the texture's render resource is made on the
    -- render thread after the call), the reads (0), the MID (10, as cap.look.mid)
    ['cap.tex.load'] = 3, ['cap.tex.import'] = 10, ['cap.tex.read'] = 0, ['cap.tex.mid'] = 10,
}
-- The Mods Menu Status row (adapter/modsmenu.lua MENU.known; the author 2026-11-03: «maybe we can show some status in
-- our settings if something went wrong?»): a name of disabled.json reads "Some effects off" when it is one of
-- lab_risky or a data/hooks.lua hook ('hook:<id>'), less these: guarded calls no player effect depends on. A retired
-- name (slicer.cut.lod) is in no list and never counts. The session's log-only reads (session_engine's frame number,
-- session_pbz's censor CVars and statics); the lab builds' own calls (lab_rc, lab_tl, lab_obs, lab_keep, lab_skin, and
-- lab_cut's GCAP-a, the probe and dev lab_3 key); the test build's tools (lab_spawn's spawn keys, lab_slice_watch,
-- lab_sword_looks' look B, lab_grey's grey census and Soul overlay keys)
META.status_quiet = {
    'probe.static.GetFrameCount', 'probe.cvar.PBZ.Censor.LaunchCensored', 'probe.cvar.z.Censoredlelvel',
    'pbz.censor.IsLaunchCensored', 'pbz.censor.GetCensored', 'pbz.censor.GetSuperCensored',
    'pbz.censor.IsCensoredVersion',
    'lab.inherit.rc', 'lab.inherit.sim', 'lab.read.gas', 'keep.write', 'lab.inherit.group', 'lab.cut.gcap',
    'lab.skin.holder', 'lab.skin.copy', 'lab.skin.bones', 'lab.skin.read',
    'lab.spawn.load', 'lab.spawn.summon', 'lab.spawn.deferred', 'lab.spawn.respawn', 'lab.spawn.move', 'lab.spawn.ai',
    'lab.spawn.hold', 'slicer.watch', 'sword.byinfo', 'grey.census', 'blood.ovl.read', 'blood.ovl.setup',
    'blood.ovl.mid', 'blood.ovl.set', 'blood.ovl.decal', 'blood.ovl.rt',
}
-- The linger of a proven LAB.hot read, by name, where it is not LAB.HOT_LINGER_S (lab_probe): blood.wash runs bare
-- (it only destroys the mod's own decal components; a quit during a wash struck it in TC-BETA-01, and a second strike
-- would switch the Soul wash off for good). Its unproven first call lingers META.lab_linger['blood.wash'], 0 as well
META.lab_hot_linger = { ['blood.wash'] = 0, ['lab.read.bonehidden'] = 0,   -- bonehidden: kept corpses read it every second, so every quit struck it and a start disabled lab_hold (TC-BETA-01f)
    ['sword.read'] = 0 }   -- lab_sword's watch reads every 3 s for the rest of the map (its census always runs armed)
-- dev only (main.lua, D2): the set the dev profile loads after the lab modules; A5.5 sets 'lab02'
META.dev_sets = {
    spawn = { card = 'TC-LAB-01', modules = { 'lab_spawn' } },
    lab02 = { card = 'TC-LAB-02', modules = { 'lab_plan', 'lab_keep', 'lab_cap', 'lab_piece', 'lab_cut', 'lab_hold',
        'lab_spawn', 'lab_skin', 'lab_blood' } },
}
META.dev_set = 'lab02'
-- release only (main.lua, beta port S1): the player beta loads these after META.extra_modules
META.beta = true
META.beta_modules = { 'lab_probe', 'lab_l0i', 'lab_kill', 'lab_poll', 'lab_census', 'lab_plan', 'lab_look',
    'lab_iberico', 'lab_cap', 'lab_piece', 'lab_cut', 'lab_gib', 'lab_fade', 'lab_hold', 'lab_blood', 'lab_drops',
    'lab_sword', 'lab_leash', 'lab_corpse', 'lab_slice', 'lab_slice_route' }
-- the author's test build: the beta loads lab_spawn too when its file is there (the player zip leaves it out)
META.beta_spawn = true
-- the test build's keys for the console verbs (lab_testkeys; the console does not reach the mod on UE4SS 1185 in PBZ)
META.test_keys = {
    grey = { key = 'F1', mods = { 'SHIFT' } }, soul_recv = { key = 'F2', mods = { 'SHIFT' } },
    leash = { key = 'F3', mods = { 'SHIFT' } }, soul_ovl = { key = 'F8', mods = { 'SHIFT' } },
    cap_look = { key = 'F5', mods = { 'SHIFT' } }, hair_mode = { key = 'F6', mods = { 'SHIFT' } },
    blood_amount = { key = 'F9', mods = { 'SHIFT' } }, max_parts = { key = 'F10', mods = { 'SHIFT' } },
    drops = { key = 'F1', mods = { 'CONTROL', 'SHIFT' } },
    slice_probe = { key = 'F2', mods = { 'CONTROL', 'SHIFT' } },
    slicer = { key = 'F3', mods = { 'CONTROL', 'SHIFT' } },
    sword_look = { key = 'F5', mods = { 'CONTROL', 'SHIFT' } },
    cap_atlas = { key = 'F6', mods = { 'CONTROL', 'SHIFT' } },
}
-- the beta's dismemberment switches (BD0): limbs, the cut-subtree scan, extra poseables, the Cap fade, lab_gib
META.beta_limbs = true
META.beta_scan = true
META.beta_extras = true
META.beta_fade = true
META.beta_gib = true
-- the beta's volumetric drops (lab_drops)
META.beta_drops = true
-- the game's own slicer on ordinary death cuts (lab_slice_route; the knob 'slicer' switches it live). The 0.1.0-beta
-- player zip shipped it off (tag v0.1.0-beta): on 2026-11-01 every death fell back with cpu_unread at the LODInfo
-- read; a read that runs but gives no boolean now goes on to the native preflight (lab_slice cpu_of, 'soft')
META.beta_slicer = true
META.beta_pins = { game_build = '26266538', arm_key = '5.7.4-301524+42ecbfa37f78|26266538', loader = 'dff435dd' }
-- UE4SS builds the loader pin also takes: 1185 (dff435dd, Ultra+ up to 2026-11-02) and 1195 (1ceefac8). Since
-- 2026-11-03 Ultra+ Manager installs the official experimental 1196 zip, whose UE4SS.dll is byte-identical to 1195's
-- and reports Git SHA 1ceefac8 (spec fixes-0.2.2 D0, inv_engine). 1195 is 10 commits past 1185 and none touches the Lua
-- marshalling the mod uses (UObject:CallFunction fixed, two string pushers added, the game directory getters; RE-UE4SS
-- compare dff435dd...1ceefac8). Any other build waits for the player knob other_ue4ss (lab_probe pin_check, F4.1)
META.beta_loaders = { 'dff435dd', '1ceefac8' }
META.beta_seed = { 'lab.inherit.hide', 'cap.pmc', 'lab.tarray.probe', 'cap.mid', 'cap.parent', 'cap.mesh', 'cap.meat',
    'hide.optim', 'hide.comp', 'hide.tag', 'piece.spawn', 'piece.mesh', 'piece.pose', 'piece.isolate', 'piece.phys',
    'piece.destroy' }
-- package.ps1 only (S8, the header): the zip's ship switches
local DEFAULTS = {
    ship_lab_tools = false,
    ship_lab_hold = true,
}
META.lab_card = { probe = 'TC-LAB-01' }
META.lab_consent = { respawn = false }
META.spawn = {
    targets = {
        lab_1 = { family = 'MaleThug', class = 'BP_Monster_MaleThug_Sword_Blue_C',
            asset = '/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue' },
        lab_2 = { family = 'GuiChai', class = 'BP_Monster_GuiChai_Black_TwinBlade_C',
            asset = '/PBZCombatAsset/ActorData/Mobs/037_GuiChai/Blueprints/BP_Monster_GuiChai_Black_TwinBlade' },
        lab_4 = { family = 'IronMaskMan', class = 'BP_Monster_IronMaskMan_C', first = 'deferred',
            asset = '/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_IronMaskMan' },
    },
    press_s = 3, cap = 40, near_m = 10, load_s = 5,
}
return META
