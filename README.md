# Strike Commander Reforged

An unofficial, modernized engine for Origin Systems' **Strike Commander**
(1993), built on **Godot 4**.

> **Requires the original game.** The project contains none of Origin/EA's
> content. All graphics, 3D models, terrain and palettes are read at runtime
> directly from your own Strike Commander CD-ROM Edition installation (e.g.
> GOG), and nothing is extracted to disk.

Why Godot: see [docs/MOOTTORIVALINTA.md](docs/MOOTTORIVALINTA.md).
File formats: see [docs/TIEDOSTOFORMAATIT.md](docs/TIEDOSTOFORMAATIT.md).
Tactical facts from the original game: see
[docs/ORIGINAL_DOCTRINE.md](docs/ORIGINAL_DOCTRINE.md) (extracted from the
official Playtester's Guide `docs/PLAYTESTERS_GUIDE.txt` and the Manual
`docs/SC_MANUAL.txt`, fetched from archive.org).
Port planning to Godot: see [docs/GODOT_PORT_PLAN.md](docs/GODOT_PORT_PLAN.md).
First mission's event chain (briefing, script, win/lose conditions): see
[docs/MISN-1A_TAPAHTUMAKETJU.md](docs/MISN-1A_TAPAHTUMAKETJU.md); any mission can be
dumped with `tools/mission_chain.gd`.
Reverse-engineering tooling: `tools/decompile/disasm.py` (annotated ASM dumps
of the original EXEs) and `tools/cutscenes/` (the DOS emulator used to record
the cutscenes). External free 3D models: `game/models/` with
`game/models/README.md` (rights) and `docs/MODEL_CONVERSION.md` (pipeline).

## Running

1. Install Strike Commander (the GOG version defaults to
   `C:\Gog games\Strike Commander`).
2. Start `Kaynnista.bat` (uses the bundled Godot 4.7.2 in `tools/godot`).
3. If the game is not found automatically, the program asks you to pick the
   folder containing `SC.dat` and `LILTRE.TRE`. The choice is saved to
   settings.

The project can be edited in the Godot editor: `Avaa_editori.bat`.

## What is implemented

- **Original data readers** (`game/scripts/formats/`): the CD image (raw
  2352-byte ISO 9660), TRE and PAK archives, IFF, the CD edition's LZW
  packing, VGA palettes, RealSpace 3D models (LOD levels, textures) and
  terrain areas (heights, terrain types, transition tiles).
- **All 17 terrain areas** and **213 3D models** load straight from the
  original data.
- **Modern rendering**: PBR lighting, dynamic shadows, atmospheric fog, ACES
  tone mapping, bloom, MSAA, FSR 2 upscaling, reflective water, procedural
  surface detail, high resolution and widescreen. The original pixel textures
  can be restored in the settings at any time.
- **Free flight**: a fly-by-wire flight model (G-command, flight-path hold,
  stall, thrust lapse with altitude, afterburner, landing/rollout), cannon,
  AI MiGs, explosions.
- **Modern vector HUD**: heading tape, speed (KTS/Mach), altitude (FT/ radar),
  pitch ladder, flight-path marker, target boxes with ranges, PULL UP warning.
  Original-scheme markers: FOE = amber box, friend = box with the IFF "X"
  (manual pp. 60), IN RNG / R n.m / C knots readouts on missile lock.
- **Cameras**: chase, cockpit and free orbit (right mouse button + wheel),
  adjustable FOV, and a scripted **flyby cutaway** whenever a waypoint is
  reached (cancelled by any camera cycle).
- **Controls**: keyboard, mouse and gamepad/HOTAS, all keys remappable.
- **Original missions** (47): the player starts where the mission dictates
  (often on the runway), enemy and wingman aircraft, base objectives and
  objective texts.
- **Mission scripts**: the original `PROG` bytecode runs on our own virtual
  machine (stack machine: variables, flags, conditional jumps, state machines,
  actions). The player's route with the original texts (HUD: NAV n/N and the
  steering caret), the wingman takes off behind the player and joins the
  formation, ambushes and reinforcements wake up by script conditions, AI
  attacks the script-named target (e.g. the escort mission's cargo aircraft),
  and characters speak with their original radio lines (e.g. Strike Base:
  "Mission accomplished. Return to base."). The mission ends when the
  objective is met and the route is flown home.
- **Enemies fight back**: fighters patrol their area and attack from 22 km
  with predictive pursuit, cannon and the missiles of their original loadout
  (e.g. MiG-29: 2 × AIM-9, 2 × AIM-120). Missiles are evaded with hard turns
  and countermeasures.
- **AAA and SAM** from the original `SWPN` data: guns (40MMAA, ZSU-23) fire
  predictive barrages and SAM sites (STASAMLN) launch when the target is in
  range, below the altitude ceiling and with line of sight over the terrain.
- **Player missiles and countermeasures**: lock the nearest enemy inside the
  forward lock cone, AIM-9 close and AIM-120 far per the aircraft's original
  loadout; 30 flares/chaff. The HUD shows hull %, stores, the LOCKED marker
  and a blinking MISSILE WARNING.
- **Campaign and story** (New campaign / Continue campaign): the original
  base screens (hangar, bar, office ...) with clickable people and their
  animations, conversations with the original backgrounds and speaking faces
  (lip sync, blinking), subtitles and the **original speech** (VOCLIST.TRE).
  Yes/no choices and wingman selection work. "Fly Mission" plays the briefing
  and flies the correct mission (1A, 1B, 1C, 2A, 3A ...); after a successful
  flight the campaign continues and progress saves automatically. Mouse,
  keyboard (Tab / Enter) and gamepad work.
- **Original cutscenes**: exact timelines are recorded for the campaign's
  referenced story scenes (intro MID1 plus MID2, MID3, MID5, MID12, MID14–17,
  MID20, MID34 and MID36), all 18 establishing shots, and transport scenes
  `trans0`–`trans8`. The scene player replays draw operations, animation
  frames, palette changes, speech and available subtitles; artwork and audio
  are read from the player's own game. These timelines were captured by
  emulating `OPTTEST.EXE` with `tools/cutscenes`. Esc/Enter/Start skips.
  **Coverage is not complete:** GAMEFLOW contains effect-12 values outside
  0–8 whose meaning or mapping to transport scenes is unresolved. The
  approximate story-scene fallback remains for scenes without an exact
  timeline. The test `cutscene_vm_test.gd` derives story-scene references
  from GAMEFLOW, checks recorded assets and reports effect-12 references
  without a matching timeline for investigation. See
  `docs/GODOT_PORT_PLAN.md` for current findings and next steps.
- **Campaign branching** as in the original interpreter: conditions
  `09`/`0a` (flag), `14`/`15` (conversation yes/no), `16` (flight succeeded),
  `20 n` (mission n succeeded), `21 n` (n conditions at once), `1e` else and
  `1f` endif.
- **Sound** from the original `SOUND/DSOUNDFX.PAK` (32 LZW-packed VOC files):
  engine (pitch follows throttle and speed), afterburner, cannon, explosions,
  hits and missile launches as 3D audio with Doppler; other aircraft's engines
  are audible by position. Missile warning, lock tone and cannon are
  synthesized (the original effect bank has no cannon sound). The cannon is a
  fast Gatling whose preset comes from the aircraft's original armament: 20 mm
  (F-16, F-22 etc.: ~110 rounds/s, bright) or 30 mm (A-10: ~65 rounds/s,
  heavy). Hits can also use a synthesized sound. Because the original data has
  no effect names, the roles were identified from waveforms — the Audio tab in
  the settings lets you audition every sound and swap each role's sound.
- **Landing and debrief**: on the way home the HUD shows the home runway
  outline and an ILS-style glide-slope (3°) and heading needles. When the
  aircraft stops on the runway or is lost, the mission ends in a debrief:
  result (accomplished / incomplete / failed), route score points, radio log,
  flight time, destroyed targets, shots, missiles, bombs, hull condition and
  wingmen. From there you can fly again or return to the main menu.
- **Ground-attack weapons** from the aircraft's original loadout (F-16: 6 ×
  AGM-65D, 12 × MK-82): the AGM-65 Maverick locks to a ground target in the
  nose direction and for bombs the HUD shows the CCIP impact point. Damage and
  blast radius come from the original `WDAT` values (MK-82: 350 / 75 ft), and
  ground-object strength from the original `DAMG` values.
- **Game texts are in English** as in the original game.
- **Ground objects** from each map's own object lists (hangars, radars, air
  defence, buildings); destructible, and the original wrecked model replaces
  them. Runways are drawn procedurally from the original dimensions.
- **Model viewer** for every object in the game (LOD levels, dimensions,
  textures).
- **Settings**: fullscreen, VSync, MSAA, render scale, FOV, shadows, fog,
  SSAO, texture filtering, dead zone, mouse sensitivity, inverted pitch.

## Demo version

`python tools/make_demo.py` builds the folder `dist/StrikeCommanderDemo` and a
zip (~90 MB): the Godot runtime, the game scripts and cutscene draw lists, the
launcher `Kaynnista demo.bat` and the readme `LUEMINUT.txt`. No original data
is included; the demo reads it from the player's own Strike Commander
installation.

In demo mode (the package `game/demo.cfg` or command line `-- --demo`) the
menu has only *Start demo* / *Continue demo*, Options and Quit. The demo
advances from the original intro to the first base, the mission briefing and
the campaign's first mission (MISN-1A). Once the mission is flown successfully
and the debrief is dismissed, the *End of demo* screen appears. The demo's
save is separate (`user://demo_campaign.json`).

## Default controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Nose up / down | S / W or ↓ / ↑ | left stick Y |
| Roll | A / D or ← / → | left stick X |
| Rudder | Q / E | right stick X |
| Throttle + / − | Shift / Ctrl (or = / −) | RT / LT |
| Afterburner | Tab | RB |
| Cannon | Space / mouse left | A |
| Cycle weapon mode (AIR / AGM / BOMB) | V | dpad up |
| Fire weapon (missile / AGM / bomb) | R | LB |
| Countermeasures (flare/chaff) | F | B |
| Brakes | B | X |
| Next waypoint (jump) | (configurable) | |
| Auto-landing at base (animated; not with enemies inside 10 nm) | L | |
| Cycle camera | C | Y |
| Pause / menu | Esc | Start |
| Screenshot | F12 | |

Taking off from the runway: full throttle (Shift) and pull the nose up (S) at
about 130 knots (70 m/s).

## Structure

```
game/                     Godot project
  scripts/core/           SCData (virtual file system), Settings (options, input)
  scripts/formats/        readers for the original formats
  scripts/game/           flight scene, flight model, camera, HUD, effects
  scripts/ui/             menus, settings, model viewer, install picker
  shaders/                terrain and model shaders
  tests/                  headless tests (data readers, flight model, VM, ...)
  data/cutscenes/         cutscene draw lists (MIDn, recorded from OPTTEST.EXE)
  models/                 optional free-licence 3D drop-ins (see game/models/README.md)
docs/                     engine choice, format docs, port plan, doctrine, decompile dump
tools/cutscenes/          DOS/JEMM emulator + cutscene recorder (Python + unicorn)
tools/decompile/          annotated disassembler for the original EXEs
tools/godot/              Godot 4.7.2 (official release)
tools/blender-*           portable Blender for model conversion
```

## Tests

The whole suite (unit tests, the final-approach landing and N full MISN-1A
autopilot flights) runs with one command; the exit code is the number of
failed items and logs go to `tmp/testit/`:

```powershell
.\Aja_Testit.ps1 -Taydet 0
```

```powershell
.\Aja_Testit.ps1 -Taydet 5
```

Individual tests:

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/smoke_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/flight_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/mission_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/vm_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/audio_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/story_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/campaign_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/cutscene_vm_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/demo_test.gd -- --demo
```

Campaign test launches: `--auto=campaign` (new), `--auto=continue`, `--conv=N`
plays conversation N, `--story=N` cutscene MIDn, `--shot_scene=N` an
establishing shot.

Cutscene verification against the original, screen by screen:
`python tools/cutscenes/compare.py midN N folder [count]` runs the cutscene
both in the emulator and the Godot player at the same instants, prints the
share of differing pixels and saves a comparison image (original left, Godot
right).

Cutscene re-recording (developers only; needs the original game and
`pip install unicorn`): `python tools/cutscenes/trace_mid.py N 30000
game/data/cutscenes/midN.json` (establishing shots: `eN … estN.json`).
Subtitles are then added with `python tools/cutscenes/subtitles.py N
game/data/cutscenes/midN.json` (`--tidy` cleans already-added texts without
running the emulator). Transport traces use `tN … transN.json`; only `t0`–`t8`
are currently recorded. GAMEFLOW also references effect-12 values `9`,
`11`–`39` and `43`–`46`, but direct emulator probes for several of those
values stop at an invalid DOS address. Do not save those partial traces as
cut-scenes until the original selector and argument meaning are understood.
Game folder in the `SC_GAME_DIR` environment variable.

`tests/all_missions_test.gd` loads all 47 missions (slow, several minutes) and
verifies that every spawned aircraft comes exactly from the original PART
data (model + side split).

Combat testing without controllers: `--autopilot` flies the player's aircraft
at the nearest enemy (ground targets without enemies; the mission route when
far from enemies or out of air-to-air stores). The cannon fires inside 1 NM
(1850 m) when the nose is on the gun pipper, and missiles fire only with a
lock, suitable aspect and a 12 s cooldown (one volley per window).
`--endless_ammo` never depletes missiles or countermeasures (the original
loadout is topped up continuously) — useful in long AI playtests.
`--speed=N` runs the simulation N times faster than real time, `--bomb_run`
starts from the computed bomb release point, `--approach` from an 8 km final
approach to the home runway (`--approach=M --approach_high=M --approach_speed=M/S`
for other starts; negative M = beyond the field), `--autoland` starts the
animated auto-landing (key L) at once, `--debrief=N` shows the debrief after N seconds,
and `--log` prints every second the altitude, speed, hull condition and the
nearest enemy's flight state.

```bash
tools/godot/Godot_v4.7.2-stable_win64.exe --path game -- --auto=flight --mission=MISSIONS/MISN-10A.IFF --spawn_area=1 --autopilot --log --frames=3600 --shot=C:/temp/dogfight.png
```

Automatic screenshot (e.g. for regression checks):

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game -- --auto=flight --mission=MISSIONS/MISN-10A.IFF --spawn_area=4 --cam=1 --frames=300 --shot=C:/temp/base.png
```

Headless runs of the main scene (no window, for CI and scripted mission tests).
The game runs on the normal main loop and stops by itself when the mission
ends (exit 0 = success, 3 = any other result), after `--frames=N` (default 90
without a mission, unlimited with one) or after `--timeout=S` wall-clock
seconds (default 600, exit 4). A status line is printed every `--status=S`
seconds; `--ap_debug` adds the autopilot's debug line. Do not add Godot's own
`--quit` (it stops after one frame). `--shot` does nothing in headless mode
(dummy renderer); run without `--headless` for screenshots. Options work with
or without the `--` separator.

```bash
tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --dir="C:/Gog games/Strike Commander"
```

## Next steps

The current plan with verified status and acceptance criteria is
[SUUNNITELMA.md](SUUNNITELMA.md); the list below is the feature backlog.

1. **Landing at the base at mission end — REGRESSED.** M1 (MISN-1A
   end-to-end on autopilot) was reached on 8.–11.11.2026, but on 16.11.2026
   the full flight failed 3/3: the aircraft hits the ground about 600 m short
   of the threshold. The 8 km final approach (`--approach`) still lands.
   Remaining mission-script ops: parameter table `21/24/25/2f` and the `97`
   query.
2. **Wingman commands** and AI energy-management polish; per-shooter kill
   attribution for the debrief statistics.
3. **Missile impact-rate playtest** (MISN-10A, decoy 30/15 %, authority
   boost — pending since the M1 run).
4. **Weapons and loads** from the original `WEAP`/`HPTS`, flight model
   parameters from the `DYNM` chunk.
5. **Cockpit models** (`*-CKPT.IFF`, `COCKPITS/*.PAK`) and the original
   instruments.
6. **Music** (XMIDI → MIDI synthesizer) and radio speech (VOCLIST.TRE: 2301
   VOC files, the message-to-file mapping still unknown).
7. Adding **names** ($N, wingman) to subtitles, the kill board (`13`), weapon
   catalog (`17`), ledger (`19`) and effects `18`, `1a`, `1b`, `1d`, `22`,
   `24`, `26`.

### LLM Development Guide

This section is meant for a second LLM (or a human) continuing development.
Read [AI_INSTRUCTIONS.md](AI_INSTRUCTIONS.md) for the working rules and known
pitfalls. The project is a git repository since 16.11.2026; the old hand-kept
`demo/` copy of the game folder was removed (it is in the first commit).

#### Current state
* **PROG opcode decoding** — the tool `game/tools/prog_analyze.gd` lists the
  usage contexts of the open opcodes from every mission. With its results,
  `mission_vm.gd`/`flight_scene.gd` now implement: `14 n` = var n = pop,
  `21/24/25/2e/2f k` = parameter pushes, `93` = aircraft flying, `98` =
  aircraft on the ground, `95` = distance in whole miles to a target.
  `97` is still open.
* **Autopilot** follows the mission route when far from enemies (12 km),
  pursuit with lead shrinks into the 1 NM gun envelope (pipper-based), pulls
  up on terrain prediction, hands over to the landing autopilot when the
  route is done and no hostiles remain. Landing: glide-slope intercept
  (3°), dead-centre short final, flare over the threshold, rollout → mission
  end at the home base. (Works from the `--approach` start; from a full
  mission it currently crashes short of the runway, see SUUNNITELMA.md.)
* **Waypoint jump** = teleport to the next waypoint (original behaviour),
  and a flyby camera cutaway plays at every waypoint.
* **External free models**: `.glb` drop-ins in `game/models/` are loaded at
  runtime; rights documented in `game/models/README.md` (CC0 sources only);
  conversion pipeline in `docs/MODEL_CONVERSION.md`.
* **Disassembler**: `tools/decompile/disasm.py` produces annotated ASM
  listings + strings + xrefs of the original Borland overlay EXEs into
  `docs/DEKOMPILU/` for feature-coverage comparison.
* **VehicleQuery stub removed** — it was dead code (contained `Quat`, an
  invalid Godot-4 call) and was replaced by the real `vm_query_object`/
  `vm_query_param` hosts in `flight_scene.gd`.
* **Cutscene VM** — the `Array.get_type()` error fixed.

#### Continuation tasks
1. Resolve the parameter table the `21/24/25/2f` pushes read from (`2e k` is
   proven to push the constant) and the meaning of the `97` query. Tool:
   `game/tools/prog_analyze.gd`.
2. Implement the remaining mission-script commands and integrate the
   93–98-style query findings into the flight scene.
3. Add unit and Godot tests for the new opcodes (partly done:
   `tests/vm_test.gd` covers 14/2e/93/98/95).
4. Keep the README test instructions up to date.

#### Code conventions
* All file paths are absolute.
* GDScript uses 4-space indentation (tabs in mission_vm/hud files where
  established by the surrounding file).
* Constants are UPPER_SNAKE_CASE.
* Launchers (`Kaynnista.bat`, `Aja_*.bat`) use paths relative to their own
  folder and the engine in `tools/godot`. The game data folder comes from
  the `SC_GAME_DIR` environment variable or the game's own auto-detection.
* PowerShell scripts stay pure ASCII.

## Rights

Strike Commander © 1993 Origin Systems / Electronic Arts. This is an
unofficial fan project and is not approved by EA. The project's own code
contains no game content; to play you need a legal copy of the original game.
External free-licence model licences are documented in
`game/models/README.md` (CC0 sources only for shipped assets).
