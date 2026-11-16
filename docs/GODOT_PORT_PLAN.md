# Strike Commander Reforged — Godot port plan

Purpose: a concrete, phased plan for porting the Original strike commander
engine to Godot 4 so that **everything in the original game is covered**, and
the port can be worked on in a verifiable order. Every phase defines
verifiable "done" criteria and names the original subsystems, the data files
that drive them, and the Godot implementations that must exist before the
next phase.

Current status is marked in every section — the port is already far along:
raw data readers, terrain, models, flight model, mission VM, campaign and
sound are implemented; cut-scene coverage is partial (see Phase D and the
"Status" column).

---

## 0. Sources of truth

| Source | What it gives |
|---|---|
| Player's install (`C:/Gog games/Strike Commander`) | All original game data read at runtime |
| `SC.dat` (2352-byte ISO image) | CD root files, terrain PAKs, archives |
| `LILTRE.TRE` / `BIGTRE.TRE` / `VOCLIST.TRE` | TRE archive index: VFS of the game |
| `docs/TIEDOSTOFORMAATIT.md` | decoded binary formats (ISO, TRE, PAK, IFF, LZW, VGA palettes, RealSpace models, terrain, RNWY, WEAP, SWPN, WDAT, PROG) |
| `docs/PLAYTESTERS_GUIDE.txt` | mission-by-mission chronology, enemy loadouts, tactics |
| `docs/SC_MANUAL.txt` | official manual: HUD semantics, weapons, flight doctrine |
| `docs/ORIGINAL_DOCTRINE.md` | extracted numbers (gun rate, missile envelopes, HUD symbols) |
| `docs/DEKOMPILU/` | disassembly and strings of the original EXEs (Borland overlay EXEs) |

The original source code was lost (Wikipedia: overwriting at Origin). The
port therefore reconstructs behaviour from **data files + documented
behaviour + reverse engineering of the EXEs**. `tools/decompile/disasm.py`
produces the annotated ASM listings under `docs/DEKOMPILU/`.

---

## 1. Phase plan (build order)

### Phase A — Data readers (DONE)
Verifiable: all data loads without the original binaries.

- ISO 2352 → TRE/PAK archives → IFF/LZW chunks: `scripts/formats/*`
- VGA palettes → Godot colors: `sc_palette.gd`
- RealSpace 3D models (POLY/TEX/LOD): `realspace_model.gd`, 213 ok / fallback
- Terrain: heights (24.8 ft i32), objects, type colors: `sc_terrain.gd`
- Mission files (MISN: NAME/AREA/CAST/MSGS/PART/SPOT/PROG/SCNE): `sc_mission.gd`
- Conversations, campaign flow (OPL/story effects): `sc_conversation.gd`,
  `sc_gameflow.gd`, `sc_midgame.gd`
- Sound FX (PAK of LZW VOCs), speech (VOCLIST), XMIDI music: `voc.gd`, `xmidi.gd`

**Done criteria (verified by tests):** `smoke_test.gd` mounts the virtual FS,
loads 213 models and every terrain; `mission_test.gd` loads 47 missions with
real enemy data.

### Phase B — Virtual vertical slice: fly a mission (DONE, hardening)
The first flyable loop: F-16 takes off, navpoints, enemies, objectives,
landing → mission end. This is now the active milestone.

- Flight scene: `scripts/game/flight_scene.gd`
- Fly-by-wire flight model: `scripts/game/aircraft.gd`
- Terrain renderer + runway/ground objects: `ground_object.gd`, shaders/
- HUD (heading tape, speed, altitude, waypoints, locks): `scripts/game/hud.gd`
- Mission VM (PROG opcodes): `scripts/game/mission_vm.gd` + host in
  `flight_scene.gd` (vm_* callbacks)

**Milestone M1 = "First mission end-to-end"** (the current build target):
1. Countersign: the player starts at Strike Base (or jumps: `--spawn_area=1`)
2. Fly the route: waypoints trigger scene blocks + radio texts
3. Air combat: missiles hit (decoys only mislead on final km), cannon
   effective to 1 NM, 30 shells/s; enemies: the exactly original PART data
4. Mission end: on landing at home base, debrief shows
   success/failed summary with stats (shots, kills, landing quality)
5. Everything survives flight: terrain pull-up, no crash into hillside

**Milestone M1 status (8.11.2026): REACHED.**
Full end-to-end test (`m1_fullG`, MISN-1A Mauritania 1, `--autopilot`):
takeoff -> waypoint route (all 4 reached) -> 3/3 MiG-21 kills -> escort
landed -> autopilot-landing at home base -> debrief
`result=success — Landed at base`, hull 100 %, wingman alive, flight 15:59.
No script errors. Enablers fixed on the way:
- escort targets (the mission's `a8` queue from a player-side block) are
  classified as allies even when their side byte reads enemy — the C-130
  was being chased as a FOE before (Egypt/California AWACS escorts keep
  their enemy class),
- combat autopilot hands over to the landing autopilot once the last
  waypoint index is reached (nav print counts nav_index+1),
- touchdown gate widened to ~165 m/s; wheels PIN during the roll-out so
  the plane cannot bounce off on its own lift surplus,
- enemy raiders start in standby (they hold the briefing position and
  join the fight when the player is inside 18 km, with a radio call),
- cockpit radio traffic: a squak under every message plus 20-45 s
  idle chatter; scene entries get a flyby camera cut and a radio note;
  off-screen FOE arrows on the HUD bezel.

**Open items for M1** (status after m1_fullG):
- [x] landing autopilot: line up dead-centre on the runway, flare, stop in
      the strip. VERIFIED twice: `landtestAK` (--approach) and `m1_fullG`
      (full mission).
- [x] waypoint jump = teleport (done), flyby camera cut at each navpoint
      (done — `camera_rig.start_flyby()`)
- [x] debrief result "success" when landing after objectives — VERIFIED in
      `m1_fullG` (3/3 kills, route complete, landed, `result=success`).
- [ ] missile impact rate: 2–6 NM Sidewinder doctrine + countermeasure
      balance (decoy 30%/15%, turn-authority boost under 1.5 km, AIM-9
      lifetime 18 s — playtest pending)
- [ ] cosmetic: in the auto-run the 3 air kills came from AI fighters, but
      "Rounds fired: 0" only counts the player — attribution per shooter
      pending (the original credited the pilot's own kills).

### Phase C — Mission systems completion (PARTLY DONE)
- Mission script VM: all observed opcodes decoded (14/21/24/25/2e/2f pushes,
  93/95/97/98 queries) — `vm_test.gd` green
- Wingman: take-off, formation, follow/attack (`a1`, `aa`, `a7`, `a8`)
- Enemy AI: patrol, engage at 22 km, lead pursuit, evade+flares, attack
  scripted targets: `_enemy_ai()`
- Air defences (AAA barrage, SAM launch within altitude/LOS): `_air_defences`
- Ground objectives: destroyed-model swap, DAMG strength, WDAT damage
- Landing & debrief, mission results, radio log

**Next:** mission 10A's escort/order blocks need `vm_remove` (91) + landing
at SPOT (a2) verified in a live run.

### Phase D — Campaign / story (PARTLY DONE)
- Base screens (hall, bar, office...) with clickable people and hotspots:
  `scripts/ui/base_screen.gd`
- Conversations with original speech, lip sync, yes/no choices:
  `scripts/ui/conversation_player.gd`
- Exact story cut-scene timelines for the campaign-referenced MID IDs and
  intro: `cutscene_vm.gd` + JSON scripts (see coverage notes below)
- Campaign branching (flags, yes/no, mission success): `campaign.gd`
- Establishing shots (18) and transport timelines `trans0`–`trans8`:
  `estN.json` / `transN.json`; remaining GAMEFLOW effect-12 IDs need
  identification before they can be treated as transport cut-scenes.

**Cut-scene coverage audit (2026-11-15):**
- The campaign's `GAMEFLOW.IFF` references story effects for MID2, MID3,
  MID5, MID12, MID14–MID17, MID20, MID34 and MID36. MID1 is also played
  directly at new-campaign start. Matching exact timelines exist; MID33 is
  recorded too, although no campaign effect currently references it.
- All 18 establishing-shot timelines and `trans0`–`trans8` exist.
- GAMEFLOW also contains effect `12` values outside 0–8: `9`, `11`–`39` and
  `43`–`46`. Direct probes of `t9`, `t11`, `t43` and `t46` stopped at an
  invalid DOS address (`0000:0000`); do not save these partial traces as
  timelines. `t0` completed. The map animation selector is therefore still
  unresolved for effect-12 values outside the known range; determine which
  values represent transport scenes and how the original selects them before
  extending coverage.
- `tests/cutscene_vm_test.gd` now derives required story MID IDs from stage
  and sprite effects, includes MID1, and checks each timeline's JSON and
  shape references. It reports effect-12 references without a matching
  timeline as an unresolved audit item, and checks all 18 establishing shots
  and the nine known transport timelines.
- To trace an established scene against the player's original install:
  `python tools/cutscenes/trace_mid.py N 12000 game/data/cutscenes/midN.json`,
  or use `eN` / `tN` for establishing / transport scenes. The trace requires
  Python package `unicorn`; screenshot comparisons additionally use Pillow.
- Verified earlier: a fresh MID2 trace completed with no unknown shapes;
  its draw/audio operations match `mid2.json` exactly after excluding the
  separately recorded subtitle and music operations. A fresh `t0` trace also
  completed with no unknown shapes and its display list matches `trans0.json`.
- Fresh full trace audit: 30/31 scenes matched. MID1 reached the 12,000-tick
  limit without finishing (`9,706` operations, no unknown shapes,
  `base_ops_match=false`); this is an incomplete trace, not proof that the
  timeline is missing. All other audited story scenes and 18 establishing
  shots matched. Rerun MID1 with a larger trace budget and inspect the first
  draw-list divergence.
- The bundled Godot executable launched successfully in the latest session.
  Remaining work: resolve the effect-12 selector; finish the MID1 trace; run
  `cutscene_vm_test.gd` and sampled original-vs-Godot comparisons.

### Phase E — Audio (DONE)
- 32 engine/damage/weapon VOX effects, 3D + Doppler: `sfx.gd`
- Synthesized weapon warning/lock/gun (no original gun sound data)
- XMIDI music: `music.gd` + `fm_synth.gd` (OPL3-emulated, per-song)

### Phase F — Presentation (PARTLY DONE)
- PBR lighting, atmosphere, ACES, bloom, FSR: `flight_scene._build_environment`
- Original pixel-art textures (default) or procedural, settings toggle
- Free 3D drop-ins (CC0 .glb) for demo-mode/no-data fallback:
  `scripts/game/external_models.gd` + `game/models/` (documented in
  `game/models/README.md` — **rights**: CC0 sources only for shipping assets)
- Cockpit 2D assets (COCKPITS/*.PAK) — **NOT STARTED** (needs a cockpit PAK
  reader; see Phase G)

### Phase G — Remaining original features (BACKLOG)
- Cockpit models `*-CKPT.IFF`, `COCKPITS/*.PAK` offline renders → 2D HUD
- Instruments (radar MFD, RAW scope) drawn from original behavior
- Wingman Commands / radio orders, kill board (`13`), weapon catalog (`17`),
  ledger (`19`), mission text effects (`18`, `1a`, `1b`, `1d`, `22`, `24`, `26`)
- Aircraft loadout purchases between missions (the original "shopping" flow)
- Music: verify all campaign themes in a pass over the whole campaign
- Original radio speech (VOCLIST.TRE 2301 VOCs) → map message strings to clips

### Phase H — Release engineering (PARTLY DONE)
- Demo build (`tools/make_demo.py`): standalone folder with `--demo` mode
- Rights: no original content bundled, `game/models/README.md` documents
  every drop-in's licence, credit line requirements honored
- Tests: `game/tests/*.gd` headless suite (runs with the provided Godot)

---

## 2. Feature/coverage matrix (original → Godot)

| Original feature | Data | Godot implementation | Status |
|---|---|---|---|
| CD-ROM virtual FS (ISO 2352) | SC.dat | `iso_image.gd`, `tre_archive.gd` | DONE |
| RealSpace 3D objects (LOD, textures) | OBJECTS/*.IFF | `realspace_model.gd` | DONE |
| VGA palettes + world palettes | PALETTE/*.IFF | `sc_palette.gd` | DONE |
| Terrain (heights, type maps, objects) | <AREA>.PAK | `sc_terrain.gd` | DONE |
| Mission scripts (PROG VM) | MISSN/*/PROG | `mission_vm.gd` | DONE |
| Conversations + speech (VOCLIST) | INTEL/*.IFF | `sc_conversation.gd`, `voc.gd` | DONE |
| Story cut-scenes (campaign MID effects + intro) | OPTTEST.EXE, MIDGAMES | `cutscene_vm.gd`, `data/cutscenes/midN.json` | PARTIAL: referenced IDs covered; dynamic audit added |
| Establishing shots (18) | OPTIONS.IFF / GAMEFLOW | `data/cutscenes/estN.json` | DONE |
| Transports | GAMEFLOW / OPTTEST.EXE | `data/cutscenes/transN.json` | PARTIAL: `trans0`–`trans8`; other effect-12 IDs unresolved |
| Aircraft flight model (DYNM approx) | DYNM chunk | `aircraft.gd` | PARTIAL (tuned, not exact DYNM) |
| Cannons / missiles / bombs (WDAT) | OBJT | `weapons.gd`, `missile.gd`, `bomb.gd` | DONE |
| AAA / SAM systems | SWPN `DATA` | `_setup_air_defences()` | DONE |
| Ground objectives + destroyed models | DAMG OBJT | `ground_object.gd` | DONE |
| HUD (vector, original symbols) | cockpit draws | `hud.gd` + manual cross-check | DONE (2D cockpit pending) |
| Landing sequence + ILS | RNWY APPR | `_autopilot_land()`, `landing_info()` | DONE (M1 "success" verified 8.11.2026; fast-forward on F2 when >25 km; go-around pattern) |
| Waypoint autopilot + nav | route blocks (a5/a6/ab) | `_autopilot_waypoint()`, `_update_nav()` | DONE (area-radius reach, lead turn, route-complete handover) |
| Cockpit radio traffic | mission radio msgs (ab) | `Sfx.radio_blip()` + `_radio_chatter()` | DONE (squak under every message + idle chatter 22-45 s) |
| Scene cutaways / flyby camera | scene on_enter blocks | `camera_rig.start_flyby()` | DONE (waypoints, scene entries, fast travel; 4 s dramatic sweep) |
| Enemy scenario behaviour | PART slots + scenes | standby hold + `_enemy_ai()` | DONE (raiders hold briefing pos; join inside 18 km with a radio call) |
| Escort / transport friendly logic | `a8` escort op | `_escort_ids` classification | DONE (player-side escort targets are allies even with enemy side byte) |
| Mission end + debrief screen | scoring | `_end_mission`, `debrief.gd` | DONE |
| Campaign screens | OPTIONS.IFF | `base_screen.gd` | DONE |
| Music (XMIDI/OPL3) | CMID | `music.gd`, `fm_synth.gd` | DONE (verify full set) |
| Settings (video/audio/controls) | same | `settings_menu.gd` | DONE |
| Demo/build/packaging | - | `tools/make_demo.py` + `tests/` | DONE |

The missing-feature list is the Phase G backlog; each item links to the
relevant section of TIEDOSTOFORMAATIT.md or the disassembly dump.

## 3. Verification harness

- `game/tests/` headless: `smoke/vm/mission/flight/audio/story/campaign/
  cutscene_vm/all_missions` (the last one checks, per mission, that every
  spawned aircraft is exactly an original PART with matching sides).
- Playtest harness: `--autopilot --endless_ammo --log` (per-second state:
  lives, enemies, route, weapons) — used to validate M1.
- Install check: player install at `C:/Gog games/Strike Commander` (SC.dat
  + LILTRE.TRE verified every mount).
