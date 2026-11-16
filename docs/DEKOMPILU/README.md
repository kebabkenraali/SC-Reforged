# docs/DEKOMPILU — original-code disassembly dump

Purpose: give the port a verifiable trail back into the ORIGINAL code, since
the official source was lost. Every armor-piece of engine behaviour can be
cross-checked here against the disassembly when our behaviour differs from a
screenshot/quote from the manuals.

The original EXEs (from the player's install, `C:/Gog games/Strike Commander`)
are Borland C++ 16-bit DOS executables; STRIKE.EXE / OPTTEST.EXE are the big
VROOMM-overlay builds, MENU.EXE is plain. `tools/decompile/disasm.py`
(with `pip install capstone`) performs a linear sweep disassembly and sketch:

| File in this folder | Source EXE | Note |
|---|---|---|
| `STRIKE.EXE.asm`, `_xrefs.txt`, `_strings.txt` | the engine | identifier table at file offset ~0x70FC0: COCKPIT / FUSELAGELWING / ELEVATORTAIL / BIGSPHER / ENGINE / RUDDER / ELEVATORAILERON / LANDGEARFLAPS / BRAKES / HYDRLIC / PLAYER / HARDPT1..8 — these are RealSpace model part names, i.e. the object loader's structure registry |
| `MENU.EXE.asm`... | campaign menus | Borland messages visible; references `..\..\data\missions\`, `..\..\DATA\SOUND\DSOUNDFX.PAK`, "Failed add() NULL gadget to Menu!" — the UI gadget library |

## Limitations (read before trusting the dump)

- The linear sweep disassembles data as code; use `INT usage` and the xref
  tables to navigate, then jump to the referenced addresses.
- STRIKE.EXE's header is minimal (cs:ip 0:0, header pages 0x1a0) — this is a
  Borland overlay executable: the "real" code is distributed inline with the
  overlay data blocks. The sweep sees the byte layout the loader maps, which
  is enough to find named strings, tables and interrupt anchors, but NOT a
  full decompilation.
- IDs from `OPTTEST.EXE`/`TOPTTST1.EXE` (the cutscene tool used these) are
  not dumped here yet — keep the variable in sync with `tools/cutscenes`.
- Current trace coverage is listed in `docs/GODOT_PORT_PLAN.md`: story
  timelines are recorded for the campaign's referenced MID IDs, all 18
  establishing shots are recorded, and transport timelines exist for `t0`
  through `t8`. GAMEFLOW effect-12 values `9`, `11`–`39`, and `43`–`46` are
  not yet understood as direct cut-scene selector arguments; direct emulator
  probes for several of them reached `0000:0000`. Treat this as an unresolved
  code/data mapping, not evidence that the original has no corresponding
  animation.

## How to use for port verification

1. Pick the original feature from `docs/GODOT_PORT_PLAN.md`'s matrix.
2. Search the relevant EXE's `_strings.txt` for its data-file references
   (e.g. `DSOUNDFX.PAK`) or identifier table rows, then locate the code
   address in the `.asm` by line offset (the address column).
3. Compare the behaviour with our implementation (e.g. `weapons.gd` WDAT
   damage against STRIKE.EXE's weapon damage table).
4. Note the finding in the port-plan matrix row ("verified against STRIKE.EXE
   asm @0xXXXXX").

## Suggested anchors to explore next

- `int 21h` call sites in STRIKE.EXE around the identifier table → the
  model/terrain loader; cross-check with `realspace_model.gd`.
- `int 10h` sites → the VGA mode switches (320×200 256-colour) and the
  cutscene logic already emulated in `tools/cutscenes`.
- `int 33h` (mouse) sites in MENU.EXE → the dialogue hotspot layout that
  `base_screen.gd` re-implements.
- `int 67h` sites → the overlay manager + memory manager (not needed by the
  port beyond understanding memory budgets).
