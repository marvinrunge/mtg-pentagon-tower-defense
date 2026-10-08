extends SceneTree
## Turns the 2x2 grass sheets in assets/foliage/grass/source/ into 20 alpha-cutout
## billboard textures, four per biome.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_grass_billboards.gd
##
## The sources are grass tufts rendered against pure white; tools/alpha_key.gd keys
## them to alpha (and explains why that takes more than "white becomes transparent").
##
## Tiles are then cropped to their alpha bounding box, so the quad that carries them
## is all grass and no empty margin, so cropping to different sizes per variant is
## fine. The billboards are placed as TerraBrush foliage in the editor.
##
## The source sheets stay in the repo behind a .gdignore (Godot must not import 9 MB
## of white-background PNGs as game textures) so this stays re-runnable.

const SOURCE_DIR := "res://assets/foliage/grass/source/"
const OUT_DIR := "res://assets/foliage/grass/"
const BIOMES := ["white", "blue", "black", "red", "green"]

## Keying lives in tools/alpha_key.gd, shared with tools/build_nature_cards.gd.
const AlphaKey := preload("res://tools/alpha_key.gd")

## Longest edge of a finished tile, capped just under the ~600px the sources carry.
##
## 256 was too aggressive - clumps read as mushy up close, where the player camera
## spends all its time at a distance of 3.2. 512 keeps essentially all the blade
## detail the sheets have while staying a sane power of two, at roughly 25 MB across
## the 20 tiles including mipmaps. If that ever needs to come down, switching the
## imports to VRAM compression is a better first move than dropping back to 256,
## because it costs compression artefacts rather than silhouette.
const MAX_TILE_SIZE := 512


func _init() -> void:
	var out_absolute := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_absolute)

	var written := 0
	for biome: String in BIOMES:
		var sheet_path: String = SOURCE_DIR + biome + "_grass_sheet.png"
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
		if sheet == null:
			push_error("Could not load %s" % sheet_path)
			continue
		sheet.convert(Image.FORMAT_RGBAF)

		var half_w: int = sheet.get_width() / 2
		var half_h: int = sheet.get_height() / 2
		for index in 4:
			var column: int = index % 2
			var row: int = index / 2
			var region := Rect2i(column * half_w, row * half_h, half_w, half_h)
			var tile := sheet.get_region(region)

			AlphaKey.cut_out_white(tile)
			tile = AlphaKey.crop_to_alpha(tile)
			if tile == null:
				push_error("%s tile %d was empty after keying" % [biome, index + 1])
				continue
			# Order matters, and getting it wrong is invisible until the grass is a
			# few metres away. Transparent pixels still carry RGB, and both the
			# downscale filter and the mip chain average that RGB in alongside the
			# blades - so every transparent pixel has to hold a sensible colour
			# BEFORE either runs, or distant grass darkens toward whatever was left
			# in the holes.
			AlphaKey.fill_background(tile)
			AlphaKey.dilate_colour(tile)
			AlphaKey.downscale(tile, MAX_TILE_SIZE)
			AlphaKey.dilate_colour(tile)
			# save_png silently drops the alpha channel when handed a float format, so
			# the tile has to land in RGBA8 before it is written - without this every
			# billboard comes back as an opaque rectangle.
			tile.convert(Image.FORMAT_RGBA8)

			var file_name := "%s_grass_%02d.png" % [biome, index + 1]
			var path: String = OUT_DIR + file_name
			if tile.save_png(ProjectSettings.globalize_path(path)) != OK:
				push_error("Could not write %s" % path)
				continue
			print("Wrote %s (%dx%d)" % [path, tile.get_width(), tile.get_height()])
			written += 1

	print("Done - %d/%d billboard textures written." % [written, BIOMES.size() * 4])
	quit()

