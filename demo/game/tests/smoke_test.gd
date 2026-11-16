## Headless check of the data loaders against the user's original install.
## Run: Godot --headless --path game --script res://tests/smoke_test.gd -- "<game dir>"
extends SceneTree

const IsoImage = preload("res://scripts/formats/iso_image.gd")
const Tre = preload("res://scripts/formats/tre_archive.gd")
const RealSpaceModel = preload("res://scripts/formats/realspace_model.gd")
const Terrain = preload("res://scripts/formats/sc_terrain.gd")
const Palette = preload("res://scripts/formats/sc_palette.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "C:/Gog games/Strike Commander"
	var failures := 0
	var t0 := Time.get_ticks_msec()

	var iso = IsoImage.new()
	var err: Error = iso.open(dir + "/SC.dat")
	print("ISO open: ", error_string(err), " sector=", iso.sector_size, " files=", iso.files.size())
	var big := Tre.index(iso.file_source("BIGTRE.TRE"))
	print("BIGTRE entries: ", big.size())
	if big.size() < 500:
		failures += 1

	var read := func(n: String) -> PackedByteArray:
		var e = big[n]
		return e[0].read(e[1], e[2])
	var pal := Palette.from_iff(read.call("PALETTE/PALETTE.IFF"))
	print("palette[255]=", pal[255], " palette[50]=", pal[50])

	var ok := 0
	var bad := []
	var tris := 0
	for n in big:
		if not n.begins_with("OBJECTS/") or not n.ends_with(".IFF"):
			continue
		var m = RealSpaceModel.load_from(read.call(n), n)
		if m == null:
			bad.append(n)
			continue
		ok += 1
		var mesh: ArrayMesh = m.build_mesh(pal, 0)
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(s) / 3
	print("models ok=%d failed=%d tris=%d" % [ok, bad.size(), tris])
	print("  not POLY models: ", bad.slice(0, 12))
	if ok < 150:
		failures += 1

	var f16 = RealSpaceModel.load_from(read.call("OBJECTS/F-16DES.IFF"))
	print("F-16 verts=%d tris=%d lods=%d textures=%d aabb=%s" % [f16.vertices.size(),
		f16.triangles.size(), f16.lods.size(), f16.textures.size(), f16.aabb()])
	for tx in f16.textures.slice(0, 4):
		print("  tex ", tx.name, " ", tx.w, "x", tx.h, " px=", tx.pixels.size())

	var t1 := Time.get_ticks_msec()
	var src = iso.file_source("CANYON.PAK")
	var terr = Terrain.load_from(src.read(0, src.size()), "CANYON")
	var hmin := 1e9
	var hmax := -1e9
	for h in terr.heights:
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
	print("CANYON grid=%d size=%.1f km h=[%.0f, %.0f] m textures=%s (%d ms)" % [terr.grid_size,
		terr.world_size() / 1000.0, hmin, hmax, terr.texture_names.slice(0, 5), Time.get_ticks_msec() - t1])
	if hmax <= hmin:
		failures += 1

	print("total %d ms, failures=%d" % [Time.get_ticks_msec() - t0, failures])
	quit(failures)
