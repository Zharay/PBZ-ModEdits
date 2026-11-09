LeovvayGore 0.2.3-beta

Beta: tested on Steam build 26266538 with UE4SS 3.0.1 build 1185. Install by hand; Vortex: not tested yet.
Cuts need that UE4SS build or build 1195 (UE4SS.log names Git SHA #dff435dd or #1ceefac8; see KNOWN ISSUES).

Dismemberment, gore and blood for Phantom Blade Zero, with much more blood than the game's own. The killing blow
takes off the part it lands on: the head, an arm or a leg. A blow to the body takes off an arm, a leg or the head,
depending on where and how it lands. A Sha-Qi weapon kill takes off up to three parts. The stumps are meat and
bone, on the body and on the part that flies off, in two modes: the game's own (Jamon Serrano) or LeovvayGore's
own (Jamon Iberico). Hits spray blood, more gushes out on the kill, stumps keep pumping it, and blood pools on the
ground. Drops fly from the wounds and splat where they land, and blood stains the enemies' clothes. Soul and the
weapon he strikes with end up covered in blood, and a full heal makes it fade faster. Enemy bodies stay where they
fell instead of fading away. Settings change in the game through Mods Menu (optional, see IN-GAME SETTINGS) or in
a settings file (see SETTINGS FILE).

WHAT GETS CUT
- Only the killing blow cuts. A living enemy is never cut, and neither are you.
- Kicks, counters after a deflect, executions (finishers and stealth kills included) and deaths from bleeding
  without a blow cut nothing.
- Bosses, allies, named characters, civilians and animals are not cut, and neither are puppets, vessels or metal
  enemies.

REQUIREMENTS
Local experimental option: "override_versions": true bypasses the game, engine build key and UE4SS version
checks below. It does not fix compatibility, bypass signature checks or disable the safety switch. Untested
versions may crash or have broken effects. Default: false. Restart the game after changing it.
- Phantom Blade Zero, Steam build 26266538 only. After a game update, this mod may need an update too.
- For cuts: Ultra+ for Phantom Blade Zero, installed with Ultra+ Manager from https://theultraplace.com/installing/.
  If Ultra+ Manager does not list the game, point it at the game folder. Ultra+ brings UE4SS 3.0.1 build 1185 or
  1195, the builds the cuts need (its UE4SS.log names Git SHA #dff435dd or #1ceefac8). Any other install of UE4SS
  build 1185 or 1195 turns the cuts on too. On another UE4SS build, turn on Cuts on other UE4SS builds in Mods Menu
  (or put "other_ue4ss": true in the settings file) and start the game again.
- Optional, for settings in the game: Mods Menu 0.4.2 or later with its Mods Menu - UE4SS Bridge 0.2.0 or later
  (Nexus mod 149; see IN-GAME SETTINGS).

INSTALL BY HAND
1. Install Ultra+ Manager from https://theultraplace.com/installing/ and install Ultra+ for Phantom Blade Zero
   with it. If Ultra+ Manager does not list the game, point it at the game folder (see REQUIREMENTS).
2. Unzip this archive into the game folder (the PBZ folder with the platform and ProjectPBZ folders in it).
   The LeovvayGore folder must end up in platform/steam/ue4ss/Mods, with enabled.txt inside it.
3. Start the game. Everything starts on.

INSTALL WITH VORTEX
1. Install Ultra+ Manager from https://theultraplace.com/installing/ and install Ultra+ for Phantom Blade Zero
   with it. If Ultra+ Manager does not list the game, point it at the game folder (see REQUIREMENTS).
2. In Vortex, open Mods, click Install From File and pick this archive. Then enable the mod.
3. Start the game. Everything starts on.

UNINSTALL
Delete the folder platform/steam/ue4ss/Mods/LeovvayGore, or remove the mod in Vortex. Your saves stay as they
are: the mod keeps its own files. Your settings stay too. For a clean start, also delete the files whose names
start with LeovvayGore_ in %LOCALAPPDATA%/ProjectPBZ/Saved. Deleting the folder also deletes
LeovvayGore.config.json, the Mods Menu copy of your settings; the settings file keeps them.

WHAT YOU GET
- Two stump modes, the Stumps row in Mods Menu ("cap_look" in the settings file):
  - Jamon Serrano, the default: the game's own stumps, its flesh and bone art, a bone in the neck and a ring of
    blood round the wound. On some enemies the game's own slicer makes the cut: the skin parts along a clean
    line, and both halves get the game's own cut face.
  - Jamon Iberico: LeovvayGore's own stumps, fitted to the body, with meat, fat and bone. So far only the brutes
    have them; other enemies keep the older meat and bone stumps, in plain colours.
- Every ordinary human enemy gets cut.
- Puppets, vessels and metal enemies do not bleed red.
- A heavy blow takes off up to two parts.
- A Power Surge or an Ultimate counts as Sha-Qi: up to three parts.
- When an enemy kills another enemy, one part comes off.
- Masks and hats fall off a cut head.
- A head with long cloth hair bursts into pieces (or flies with its hair: see hair_mode below).
- The blood on Soul also fades on its own, and his death washes it off.
- The weapon Soul strikes with takes the blood of the enemies he hits: his sword and his Sha-Qi weapons alike.
  It dries, fades as the blood on Soul does, and his death cleans it. Sheathing and switching weapons keep it.
- Blood on Soul and Blood on the sword switch on and off separately, so the sword can stay red while Soul stays
  clean.
- After 15 minutes a body goes when it is out of sight or far from you, and its cut parts go with it.
- A body that LingeringDead already keeps is left to LingeringDead: LeovvayGore never changes it and never
  removes it.
- Ctrl+F8: switch the whole mod off and on, live.
- Shift+F7: compare with the game's own look; press again to return.

IN-GAME SETTINGS (OPTIONAL)
- Install Mods Menu (Nexus mod 149) and its PBZModsMenuBridge UE4SS mod (the optional file Mods Menu - UE4SS
  Bridge) from the same page. LeovvayGore's main settings then show in the game's Settings, on the Mods Menu tab.
  Use Mods Menu 0.4.2 or later and the bridge 0.2.0 or later. Without the bridge, LeovvayGore does not show there.
- Open Settings (in the world: System, then Settings) and go to the last tab, Mods Menu. In play, F9 opens it
  straight away. LeovvayGore has its own section there: Blood, Blood on Soul and sword, Cuts, Stumps and Bodies.
- The Status row at the top of that section says whether everything runs, or what is off and why (for example
  Cuts off: UE4SS build). Its help says what to do.
- A change applies within about two seconds and stays for the next start. Cuts on other UE4SS builds and
  Override version checks (experimental) wait for the next start.
- The menu's values live in LeovvayGore.config.json in the mod's folder; the mod makes it at its first start. The
  settings file keeps working: a key you change there by hand, with the game closed, wins at the next start.
- If LeovvayGore.config.json gets damaged, LeovvayGore leaves the menu until the next start, which writes the file
  again from the settings file.
- The LeovvayGore rows follow the game's text language: English, Simplified or Traditional Chinese, or Vietnamese.
  For Vietnamese the mod writes LeovvayGore.modsmenu.json from its Vietnamese copy (LeovvayGore.modsmenu.vi.json)
  when the game starts in Vietnamese, and from LeovvayGore.modsmenu.en.json otherwise, so a language change shows
  after the next start. The menu's own words stay in English.

SETTINGS FILE
- Your settings live in %LOCALAPPDATA%/ProjectPBZ/Saved, in LeovvayGore_settings.a.json and
  LeovvayGore_settings.b.json. On a new install neither file exists until you change a setting in Mods Menu, so
  without it you write the first one yourself:
  1. Close the game.
  2. In %LOCALAPPDATA%/ProjectPBZ/Saved, open LeovvayGore_settings.a.json, or make a text file of that name if it
     is not there.
  3. Put the settings you want in it, in JSON, for example:
     {"preset": "light", "corpse_keep_s": 300, "hair_mode": "keep"}
  4. Start the game. The mod reads the file when the game starts.
- Every key is optional: a key you leave out keeps its default. A file that is not valid JSON is ignored.
- When both files exist, the mod loads the newer one (the mod saves to the two files in turn). To edit by hand,
  close the game first. Then edit the newer file (the later Date modified) and delete the other one. The change
  takes effect at the next start.
- Installing an update never replaces them.

- The keys, each one optional:
- "preset": "maximum" (the default), "balanced", "restrained" or "light". In this beta a preset sets
  blood_amount only: 3, 2.5, 2 or 1.5.
- "blood_amount": 3: how much blood the hits leave on bodies, on the ground and on you, and how many drops fly.
  5 or 7 gives more and bigger stains and keeps more pools; 1.5 or 0.75 gives less, for a weaker PC. Values
  under 0.75 count as 0.75 and values over 9 as 9.
- "effects": {"blood": false}: no blood sprays, stains, pools or drops from the mod, and no new blood on Soul or
  his weapons (true brings it back). A bursting head still sprays.
- "drops": false: no flying blood drops and no drop stains (true, the default, brings them back).
- "max_parts": 1: at most one part per kill (3 is the default). "heavy_parts" (2) and "shaqi_parts" (3) set how
  many parts a heavy blow and a Sha-Qi blow take off. Each takes 1 to 3.
- "cut_chance": 100: the chance in percent, 0 to 100, that a killing blow takes parts off (100 is the default). A
  kill that does not cut still bleeds. In Mods Menu this is the Cut chance row.
- "finisher_cuts": true: finishers and stealth kills cut like any other killing blow (false, the default, keeps
  them whole).
- "other_ue4ss": true: cuts, flying drops, blood on the sword and kept bodies also run on UE4SS builds other than
  1185 and 1195 (false, the default, gives those builds blood only). It takes effect at the next start. In Mods
  Menu this is the Cuts on other UE4SS builds row.
- "cap_look": the stump mode, named Stumps in Mods Menu: "native" (Jamon Serrano, the default: the game's own
  stumps, its flesh and bone art, a bone in the neck, a blood ring, and the game's own slicer on some enemies) or
  "textured" (Jamon Iberico: LeovvayGore's own stumps). The file also takes "game" (the game's flesh only) and
  "basic" (plain colours). A file an older version of the mod saved with "game" or "textured" moves to "native"
  once. On each map the look starts about 10 quiet seconds after the first kill (the stumps before that are plain).
- "cap_scale": 1.2: bigger stumps (0.85 smaller; from 0.7 to 1.5, 1 is the default).
- "cap_fade_s": 1.5: how many seconds the stumps stay once the body starts to dissolve (1.5 is the default, up
  to 30); 0 keeps them until the body is gone.
- "hair_mode": "keep": heads with long cloth hair fly off with their hair instead of bursting ("burst" is the
  default).
- "extras_fall": false: masks and hats vanish with the head instead of falling.
- "override_versions": true: try all features regardless of game, engine build key or UE4SS version, including
  unreadable versions. Also available as Override version checks (experimental) in Mods Menu. Default: false;
  changing it requires a restart. The Status row says Version checks bypassed (or Some effects off if the safety
  switch disabled a call), and the log records versions_overridden with the actual and expected versions.
  This overrides the version pins only, not signature checks, crash protection or feature settings. If it crashes
  or effects break, set it back to false and restart. It does not change "other_ue4ss".
- "corpse_keep_s": 900: how many seconds enemy bodies lie before they go, out of sight (900 is 15 minutes, the
  default, up to 3600; 0 lets the game dissolve them at once). "corpse_max" (60) is the most kept at once.
- "soul_blood_life_s": 300: how many seconds the blood stays on you and your weapons (300 is the default; 0 keeps it
  until the next map). After a full heal it stays "heal_hold_s" (15) seconds, then fades over "heal_fade_s" (45);
  "wash_on_heal": false turns that off.
- "soul_blood": false: enemies' blood no longer lands on Soul, and the blood he has washes off within seconds
  (true, the default, brings it back).
- "soul_face_blood": false: enemies' blood no longer splashes Soul's face, head, neck and upper chest, only the rest
  of his body and clothes, and the blood already there washes off within seconds; a big splash on a shoulder or a
  hand can still touch his face, more so at a high blood_amount (true, the default, brings it back).
- "sword_blood": false: your weapons stay clean, and the blood on them goes at once (true, the default, brings it
  back). With "soul_blood": false and this on, the blood stays on the sword only.

OTHER MODS
LeovvayGore keeps enemy bodies itself (see corpse_keep_s).
Other blood, corpse and gore mods: not tested together with LeovvayGore yet.

THE SAFETY SWITCH (IF CUTS OR BLOOD STOP)
The mod guards every risky game call it makes. If the game crashes during such a call, the mod switches that call
off at the next start and lists it in disabled.json. If the game closes within a few seconds after one (the game
tells mods nothing before it closes, so a normal quit right after a kill looks the same), the mod notes the call
in strikes.json. If that happens a second time in a row with the same mod build, the mod switches the call off
for good and lists it in disabled.json. The effect behind it (for example cuts) then stays off; everything else
keeps working. Both files are in platform/steam/ue4ss/Mods/LeovvayGore.
- To avoid it: after the last kill, wait about 10 seconds before you quit the game.
- To see what is off: open disabled.json in that folder with a text editor.
- To switch everything back on: close the game and delete disabled.json and strikes.json.

KNOWN ISSUES
- The local override_versions option can waive the version restrictions below for testing; compatibility is
  not guaranteed, and the existing runtime checks may still stop effects on an incompatible update.
- Beta: tested on Steam build 26266538 with UE4SS 3.0.1 build 1185. Install by hand; Vortex: not tested yet.
- Cuts come on only with Steam build 26266538 and UE4SS 3.0.1 build 1185 or 1195 (Git SHA #dff435dd or #1ceefac8).
  With another game build there are no cuts, no flying drops and no blood on the sword, and bodies fade as in the
  game; the Status row in Mods Menu then reads Cuts off: game version. With another UE4SS build the same happens
  unless you turn on Cuts on other UE4SS builds in Mods Menu, or put "other_ue4ss": true in the settings file, and
  start the game again. UE4SS builds other than 1185 and 1195: not tested yet. If the game crashes during cuts on such
  a build, turn the row off again.
- The UE4SS console does not reach mods in this game with build 1185, so settings cannot be changed from it. Use
  Mods Menu (see IN-GAME SETTINGS) or the settings file. The settings file is written the first time you change a
  setting, so without Mods Menu you write the first one yourself.
- On each map the stump look starts about 10 quiet seconds after the first kill, so the first stumps of a map are
  plain.
- UltraPlusExtensions binds F7 and F8 to its lighting settings. With its key binds on, Ctrl+F8 and Shift+F7 can
  also change its lighting. With its key binds off, Ctrl+F8 and Shift+F7 belong to this mod alone.
- A weapon in a cut-off hand is left to the game, so it can stay where the hand was.
- While Soul has blood on him, the ground's mud and dirt marks can tint him brown. A fix is on the way; until then
  Blood on Soul off in Mods Menu keeps it off him.

BUG REPORTS
If you want to report a bug, the Bugs tab is the place. What you did, a screenshot and these files help:
- the UE4SS log (UE4SS.log next to the UE4SS dll)
- the LeovvayGore log files (log.a.jsonl, log.b.jsonl, log.json) from platform/steam/ue4ss/Mods/LeovvayGore

PERMISSIONS
Do not reupload or modify this mod, and do not use its files in other mods, without my permission. Translations
and patches need my permission too.

CREDITS
- LeovvayGore by Leovvay. The stump texture Textures/cap_iberico_256.png is the mod's own.
- UE4SS by the UE4SS team. Ultra+ by the Ultra+ team (theultraplace.com). Mods Menu by SLEEP.

Phantom Blade Zero (c) S-GAME. Unofficial fan mod, not affiliated with or endorsed by S-GAME. Contains no game
files. Free.
