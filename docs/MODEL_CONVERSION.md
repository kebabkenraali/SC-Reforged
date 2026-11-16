# Model conversion pipeline (.blend → .glb)

How the project converts externally licensed (CC0/CC-BY) aircraft models into
the `.glb` files under `game/models/`. These are optional additions: when the
original RealSpace model (from the player's install) is available it is the
default — converted models serve demo/no-data fallbacks.

## Tooling

- **Blender 4.5 LTS** (portable, ships with the project):
  `tools/blender-4.5.15-windows-x64/blender.exe`

## Workflow

1. Find a model with a free licence (CC0/CC-BY), e.g. on OpenGameArt,
   poly.pizza, Sketchfab, BlendSwap. Record the source, author and licence in
   `game/models/README.md`.
2. Download the source file (.blend inside a .zip etc.).
3. Inspect object names/structure headlessly so grouping is known:

```bat
tools\blender-4.5.15-windows-x64\blender.exe --background --factory-startup ^
  -noaudio --python <inspect.py> -- <downloaded.blend>
```

4. Run the batch conversion. Per aircraft group the script:
   - joins the multi-object parts into one mesh,
   - orients the model: nose toward Blender -Y (glTF -Z = Godot forward),
     wings +X, ups +Z,
   - scales it into the RealSpace size class (e.g. F-16 length ≈ 15.1 m,
     TARGETS table in the export script),
   - recentres the origin to the bounding-box centre.

5. Copy the produced `NAME.glb` to `game/models/` (and to
   `demo/game/models/`). File names match the model family: `MIG21.glb`
   serves `MIG21` and `MIG21EW` (the suffixes DES/GRAY/GRA/EW are stripped
   when matching).

## Conventions

- Units: metres (RealSpace AABB, e.g. F-16 length ≈ 15.1 m)
- Orientation: nose -Y (Godot forward), wings +X, origin at the model centre

## Integration

- `game/scripts/game/external_models.gd` loads `.glb` files at runtime
  (GLTFDocument) and merges every MeshInstance into one ArrayMesh
  (transforms baked, materials preserved).
- `flight_scene._spawn()` prefers (in order): external drop-in → original
  RealSpace data → shipped procedural mesh (`aircraft_meshes.gd`, demo mode).
- The conversion scripts live under `tools/decompile`-adjacent tooling; add
  new aircraft to the TARGETS table of the export script.

## Rights

- OpenGameArt CC0 packages by Captain_Ahab_62 (adversary-aircraft,
  fighter-jets-0): free to use and redistribute; attribution appreciated.
- Original Strike Commander data is NEVER bundled — it is always read at
  runtime from the player's own installation.
