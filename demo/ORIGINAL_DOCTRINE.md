# Original Strike Commander doctrine — facts used by the port

Extracted from the official Playtester's Guide (Prima) and the Strike Commander
Manual. Both live here as OCR text for development reference:

- `docs/PLAYTESTERS_GUIDE.txt` — mission-by-mission chronology, enemy loadouts
- `docs/SC_MANUAL.txt` — HUD semantics, weapon behaviour, flight doctrine

(Original archives: archive.org item "Strike_Commander_PlaytestersGuide" and
"StrikeCommanderManual". Copyright Origin/Prima — developer reference only.)

## Air-to-air combat (Manual pp. 7–8, Guide pp. 40–44)

- Missile types: AMRAAM (the only medium-range weapon; the IN RNG indicator
  lights up BVR), AIM-9J (rear-aspect IR), AIM-9M (all-aspect IR).
- **Sidewinder optimal launch range 2–6 NM** (3.7–11 km).
- **AMRAAM 2–30 NM** (3.7–55 km); launch as soon as IN RNG appears; faster
  closure ⇒ launch farther out.
- **20 mm Vulcan: 1000 rounds at 30 rounds per second**; defenceless use of the
  gun: ~1 NM (6000 ft ≈ 1850 m); effective gun envelope: about 1 NM, even
  well-equipped fighters die to it.
- Enemy loadouts per mission (Guide): e.g. MISN-10A (Rhode Island 1):
  **F-18, 20mm (600), 9J (2)**; Nav 1 two F-18s (ace, veteran), Base 2 two more,
  and a second-two pair in a scripted ambush.
- Wingman loadouts (from PART/WEAP data): e.g. F-16 20mm (1000), 9J (2).

## HUD semantics (Manual pp. 58–61)

- Designated target: a **box** around the target. **Friend = box with an X
  drawn through it** (IFF). **Diamond-X** = target left the HUD's field of view.
- **IN RNG** text appears low-left when the target is in the selected weapon's
  effective range.
- Original readouts: "R n.m" (range to target) and "C knots" (closure rate).
- Weapon modes: DGFT (cannon), SRM, MRM, STRF, I-R, CCIP, CCRP.
- Missile lock in SRM: the seeker diamond drifts to the target and flashes;
  MRM: lock = radar lock.

## Mission lists (Guide pp. 24–77)

- MISN-1A = "Mauritania – Mission 1": escort the government C-130; SAS: three
  MiG-21 rookies with guns; release the cargo at Cargo Destination; fly home
  via Nouakchott.
- MISN-10A = "Rhode Island – Mission 1": 9 points at Base 1 + 5 at Base 2, or
  destroy both runways; F-18 enemies.
- Every enemy aircraft comes from the original PART data (side splits make the
  FOE lists); the engine spawns exactly those PART models.
- Wingman skills and the mission scoring (mission payoff, kill bonuses,
  per-point bonuses) are shown per mission in the Guide.
