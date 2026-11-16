# game/models/ — externally supplied aircraft models (drop-ins)

These are third-party, freely licensed (CC0 / CC-BY) aircraft models. When a
`.glb` file with a matching name exists in this folder, the engine uses it
in place of the original RealSpace mesh. When it does not exist — the normal
case — the model is read from the player's own original installation.
The conversion pipeline (`.blend` → `.glb`) is documented in
`docs/MODEL_CONVERSION.md`; drop-ins are only used to cover the demo mode or
when original data is unavailable.

## Current drop-ins (downloaded 2026-11)

All from **OpenGameArt — Captain_Ahab_62 — CC0 (public domain)**:

- `https://opengameart.org/content/adversary-aircraft`
  → MIG21, MIG29, MIG15, MIG17, MIG19, MIG25, SU7, SU9, J7G, J10A, J10B,
    CHENGDU_J_20, TU14_BISON, XIAN_JH7, YAK23, YAK_50
- `https://opengameart.org/content/fighter-jets-0`
  → F15_EAGLE, F4_PHANTOM_II, F5_FREEDOM_FIGHTER, F14_TOMCAT, MIRAGE_III,
    F100_SUPER_SABER, F101_VOODOO, F86_SABER, F7U_CUTLASS, JAGUAR, RAFALE_B,
    EUROFIGHTER, BUCCANEER, S3_VIKING, A4E/A4M_SKYHAWK, A6E_INTRUDER,
    A7E_CORSAIR_II, EA6B_PROWLER, EF_111_RAVEN, F_111_AARDVARK

- `F16DES.glb` — **"F-16 Fighting Falcon - Fighter Jet - Free" by bohmerang**
  (Sketchfab, downloaded 2026-11-11) — **CC BY-NC-SA 4.0**: author must be
  credited, no commercial use, modified versions share the same licence.
  Source: https://sketchfab.com/3d-models/f-16-fighting-falcon-fighter-jet-free-f0b00989e5634764848ef2c235c64db5
  30.3k triangles, 4k textures. Used here in a free, non-commercial fan port —
  keep this credit when redistributing.

- `C130DES.glb` — **"Lockheed C-130 Hercules" by mgg8** (Sketchfab, downloaded
  2026-11-11) — **CC0 1.0 public domain** (commercial use allowed, attribution
  optional; a link to airmuseums.co.uk is appreciated by the author).
  Source: https://sketchfab.com/3d-models/lockheed-c-130-hercules-d2f92fa0bc004cbba8d4733b29014588
  254.9k triangles (Blender + embedded textures). This model also covers the
  plain `C130` PART entries.

Author: Captain_Ahab_62 (the low-poly bases trace back to the ysFlight community
model set); published under CC0 on OpenGameArt — usage and redistribution free,
attribution not required (included here as a courtesy).

## Known gaps (researched 2026-11-11)

- **F-16 / F16DES** — covered now (see F16DES.glb above, CC BY-NC-SA).
- **C-130 / C130DES** — covered now (see C130DES.glb above, CC0).
- Still open: none of the two required the licence of the 747 / L-1011 / E-3 /
  Lear Jet transports (the guide lists "C-130 (Gwen/Mauritania)" variants;
  they reuse the same C130DES drop-in). If a separate 747/E-3 model is ever
  wanted, Sketchfab has CC0 candidates under the same search terms.

## Licence summary

- **CC0**: free to use, modify and redistribute.
- **CC-BY / OGA-BY** (if added later): attribution required — list the author
  and licence here and in the project credits.
- **Original Strike Commander data** (RealSpace models, textures, palettes) is
  **never** bundled in this project: it is read at runtime from the player's
  own copy (see the rights note at the bottom of `README.md`).
- The Playtester's Guide + Manual (docs/PLAYTESTERS_GUIDE.txt,
  docs/SC_MANUAL.txt) were fetched from archive.org purely as developer
  reference — original copyright Origin/Prima; do not redistribute the OCR
  copies.

## Adding more models

Good CC0/CC-BY sources: poly.pizza (direct GLB), Sketchfab (CC-BY/CC0),
OpenGameArt, BlendSwap. Pipeline and conventions: `docs/MODEL_CONVERSION.md`.
