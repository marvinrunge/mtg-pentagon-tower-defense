extends SceneTree
## Keys plant sheets rendered on pure white into alpha-cutout tiles:
##   - every card-route asset in tools/nature/nature_assets.json -> assets/nature/cards/
##     (source: its `existing_sheet`, or the picked concept assets/nature/_concepts/<id>/pick.png)
##   - every leaf / moss sheet in assets/nature/_concepts/textures/ -> assets/nature/leaves/
##     (the canopy cards of the procedural trees, docs/NATURE_ASSETS.md 3b/3c)
##
## Usually run by `python tools/nature/nature_pipeline.py build`; by hand:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_nature_cards.gd -- [--only id,id] [--biome green]
##
## A sheet is split by SHAPE, not by quarters. The sheets are asked for as 2x2 grids,
## but generators do not always comply: long willow strands and moss cross the middle
## lines, some sheets come back with six plants instead of four, and some arrive with
## thin grid lines drawn between the cells. So each sheet is cleaned of drawn grid
## lines, keyed as a whole, and every separate plant (a connected blob of opaque pixels)
## becomes its own tile. Plants only have to not touch each other.
##
## Differs from tools/build_grass_billboards.gd in one more deliberate way: tiles are
## PADDED to one fixed square, not cropped to their own bounds. TerraBrush packs every
## texture of a foliage layer into one Texture2DArray, which needs identical sizes, and
## draws them all on the same quad - so each plant is fitted into the square standing
## on its bottom edge, centred. Keying itself is tools/alpha_key.gd, shared with grass.

const AlphaKey := preload("res://tools/alpha_key.gd")
const MANIFEST := "res://tools/nature/nature_assets.json"
const CARD_DIR := "res://assets/nature/cards/"
const LEAF_DIR := "res://assets/nature/leaves/"
const TEXTURE_SOURCE_DIR := "res://assets/nature/_concepts/textures/"

## Every tile is this square. Same detail budget as the grass billboards (see
## MAX_TILE_SIZE in build_grass_billboards.gd for why 512 and not 256).
const TILE_SIZE := 512

## Sheets are worked on at this size at most. A plant covers roughly half a sheet, so
## 1024 still yields ~512 px plants, and the per-pixel keying stays a quarter of the work
## a 2048 sheet would be.
const WORK_SIZE := 1024

## Empty rows kept under a plant's base. Zero would put the root on the quad's bottom
## edge, where bilinear filtering against the clamp border shaves it off.
const BASE_PADDING := 4

## Plant blobs are found on a coarse grid, LABEL_GRID cells across. One cell is ~4 px
## of the working sheet, which is fine enough to keep neighbouring plants apart and
## coarse enough that the leaves of one plant join up into one blob.
const LABEL_GRID := 256
## Cells of dilation before labelling, so a plant whose leaves are separated by thin
## gaps of background still counts as one blob.
const JOIN_CELLS := 2
## Blobs smaller than this share of the grid are specks, not plants.
const MIN_BLOB_SHARE := 0.006

## A row or column counts as part of a drawn grid line when more than this share of
## it is non-white AND grey, and the run of such rows is at most GRID_LINE_MAX_WIDTH
## thick. Both conditions matter: dark, desaturated foliage (the charcoal leaves of the
## ember flowers) also reads as grey, but it never spans 80% of the sheet in a band
## only a few pixels thick.
const GRID_LINE_COVERAGE := 0.8
const GRID_LINE_MAX_WIDTH := 6
const GREY_SATURATION := 0.12

## Import settings for every tile. Mipmaps are essential for distant foliage; BPTC
## (compress/mode 2, high quality) keeps alpha and is a quarter of lossless in VRAM,
## which matters at ~70 tiles. All tiles must share one format to sit in one array.
const IMPORT_FILE := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=true
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
detect_3d/compress_to=0
"""


func _init() -> void:
	var options := _parse_args()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for dir in [CARD_DIR, LEAF_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var written := 0
	for asset: Dictionary in manifest["assets"]:
		if asset["route"] != "card" or not _selected(asset, options):
			continue
		var source: String = asset.get("existing_sheet", "assets/nature/_concepts/%s/pick.png" % asset["id"])
		var sheet := _load_sheet("res://" + source)
		if sheet == null:
			print("[nature] %s: no sheet at %s yet, skipped" % [asset["id"], source])
			continue
		written += _build_sheet(asset["id"], sheet, CARD_DIR)

	# Leaf and moss sheets are not manifest assets yet (revision 2, task 1), so they are
	# picked up by file name. --only/--biome do not filter them.
	if not options.has("only") and not options.has("biome"):
		var dir := DirAccess.open(TEXTURE_SOURCE_DIR)
		if dir != null:
			for file in dir.get_files():
				if file.ends_with(".png") and (file.begins_with("leaves_") or file.begins_with("moss_")):
					var sheet := _load_sheet(TEXTURE_SOURCE_DIR + file)
					if sheet != null:
						written += _build_sheet(file.get_basename(), sheet, LEAF_DIR)
	print("[nature] cards: %d tile(s) written" % written)
	quit()


func _load_sheet(path: String) -> Image:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(path))
	if sheet == null:
		return null
	sheet.convert(Image.FORMAT_RGBAF)
	var longest: int = maxi(sheet.get_width(), sheet.get_height())
	if longest > WORK_SIZE:
		var scale := float(WORK_SIZE) / longest
		sheet.resize(int(round(sheet.get_width() * scale)), int(round(sheet.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return sheet


func _build_sheet(id: String, sheet: Image, out_dir: String) -> int:
	var removed := _clean_grid_lines(sheet)
	AlphaKey.cut_out_white(sheet)
	var blobs := _find_plants(sheet)
	if blobs.is_empty():
		push_error("[nature] %s: no plants found after keying" % id)
		return 0

	_remove_stale_tiles(out_dir, id)
	var written := 0
	for index in blobs.size():
		var tile := _extract(sheet, blobs[index])
		if tile == null:
			continue
		# Same order as the grass builder, for the same reason: every transparent pixel
		# must hold plant colour before any filter or mip averages it.
		AlphaKey.fill_background(tile)
		AlphaKey.dilate_colour(tile)
		AlphaKey.downscale(tile, TILE_SIZE - BASE_PADDING)
		var square := _pad_to_square(tile)
		AlphaKey.dilate_colour(square)
		square.convert(Image.FORMAT_RGBA8)

		var path := out_dir + "%s_%02d.png" % [id, written + 1]
		if square.save_png(ProjectSettings.globalize_path(path)) != OK:
			push_error("[nature] could not write %s" % path)
			continue
		var import_path := ProjectSettings.globalize_path(path + ".import")
		if not FileAccess.file_exists(import_path):
			FileAccess.open(import_path, FileAccess.WRITE).store_string(IMPORT_FILE)
		written += 1
	print("[nature] %s: %d plant(s)%s" % [id, written, (", %d grid line(s) removed" % removed) if removed else ""])
	return written


## Whites out rows and columns that are mostly grey: the divider lines some generators
## draw between the cells of a "2x2 grid" despite being told not to. Left in, they key
## as opaque and glue all four plants into one blob. Returns how many were removed.
func _clean_grid_lines(sheet: Image) -> int:
	var width := sheet.get_width()
	var height := sheet.get_height()
	var rows := []
	var cols := []
	var col_counts := PackedInt32Array()
	col_counts.resize(width)
	for y in height:
		var row_count := 0
		for x in width:
			if _is_grey_ink(sheet.get_pixel(x, y)):
				row_count += 1
				col_counts[x] += 1
		if row_count > width * GRID_LINE_COVERAGE:
			rows.append(y)
	for x in width:
		if col_counts[x] > height * GRID_LINE_COVERAGE:
			cols.append(x)
	rows = _thin_runs(rows)
	cols = _thin_runs(cols)
	var white := Color(1, 1, 1, 1)
	for y: int in rows:
		for dy in range(-1, 2):
			if y + dy >= 0 and y + dy < height:
				for x in width:
					sheet.set_pixel(x, y + dy, white)
	for x: int in cols:
		for dx in range(-1, 2):
			if x + dx >= 0 and x + dx < width:
				for y in height:
					sheet.set_pixel(x + dx, y, white)
	return rows.size() + cols.size()


## Keeps only runs of consecutive indices at most GRID_LINE_MAX_WIDTH long.
func _thin_runs(indices: Array) -> Array:
	var kept := []
	var run := []
	for i in indices.size() + 1:
		if i < indices.size() and (run.is_empty() or indices[i] == run[-1] + 1):
			run.append(indices[i])
			continue
		if not run.is_empty() and run.size() <= GRID_LINE_MAX_WIDTH:
			kept.append_array(run)
		run = [indices[i]] if i < indices.size() else []
	return kept


func _is_grey_ink(colour: Color) -> bool:
	var highest: float = maxf(colour.r, maxf(colour.g, colour.b))
	var lowest: float = minf(colour.r, minf(colour.g, colour.b))
	if lowest > 0.94:
		return false  # background
	return (highest - lowest) / maxf(highest, 0.0001) < GREY_SATURATION


## Every separate plant on the keyed sheet, as [grid rect, cell mask] pairs, sorted
## top-to-bottom then left-to-right so tile numbering is stable between runs.
func _find_plants(sheet: Image) -> Array:
	var width := sheet.get_width()
	var height := sheet.get_height()
	var cell := int(ceil(float(maxi(width, height)) / LABEL_GRID))
	var gw := int(ceil(float(width) / cell))
	var gh := int(ceil(float(height) / cell))

	var filled := PackedByteArray()
	filled.resize(gw * gh)
	for y in height:
		for x in width:
			if sheet.get_pixel(x, y).a >= AlphaKey.SCISSOR_THRESHOLD:
				filled[(y / cell) * gw + (x / cell)] = 1

	# Dilate, so the leaves of one plant join into one blob.
	var joined := filled.duplicate()
	for pass_index in JOIN_CELLS:
		var source := joined.duplicate()
		for gy in gh:
			for gx in gw:
				if source[gy * gw + gx]:
					continue
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx := gx + ox
						var ny := gy + oy
						if nx >= 0 and ny >= 0 and nx < gw and ny < gh and source[ny * gw + nx]:
							joined[gy * gw + gx] = 1

	var labels := PackedInt32Array()
	labels.resize(gw * gh)
	var blobs := []
	var next_label := 1
	for start in gw * gh:
		if not joined[start] or labels[start] != 0:
			continue
		var queue := PackedInt32Array([start])
		labels[start] = next_label
		var head := 0
		var cells := PackedInt32Array()
		var min_x := gw
		var min_y := gh
		var max_x := -1
		var max_y := -1
		while head < queue.size():
			var index := queue[head]
			head += 1
			var gx := index % gw
			var gy := index / gw
			if filled[index]:
				cells.append(index)
			min_x = mini(min_x, gx)
			min_y = mini(min_y, gy)
			max_x = maxi(max_x, gx)
			max_y = maxi(max_y, gy)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := gx + ox
					var ny := gy + oy
					if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
						continue
					var neighbour := ny * gw + nx
					if joined[neighbour] and labels[neighbour] == 0:
						labels[neighbour] = next_label
						queue.append(neighbour)
		next_label += 1
		if cells.size() < gw * gh * MIN_BLOB_SHARE:
			continue
		blobs.append({"rect": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
			"label": next_label - 1, "labels": labels, "grid": Vector2i(gw, gh), "cell": cell})

	var band := gh / 3.0
	blobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int((a["rect"] as Rect2i).get_center().y / band)
		var rb := int((b["rect"] as Rect2i).get_center().y / band)
		if ra != rb:
			return ra < rb
		return (a["rect"] as Rect2i).get_center().x < (b["rect"] as Rect2i).get_center().x)
	return blobs


## Cuts one plant out of the keyed sheet: its bounding box, with every pixel that
## belongs to a different blob made transparent, so a neighbour's leaf reaching into
## the box does not come along.
func _extract(sheet: Image, blob: Dictionary) -> Image:
	var cell: int = blob["cell"]
	var grid: Vector2i = blob["grid"]
	var labels: PackedInt32Array = blob["labels"]
	var label: int = blob["label"]
	var rect: Rect2i = blob["rect"]
	var region := Rect2i(rect.position * cell, rect.size * cell).intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
	var tile := sheet.get_region(region)
	for y in tile.get_height():
		for x in tile.get_width():
			var gx: int = (region.position.x + x) / cell
			var gy: int = (region.position.y + y) / cell
			var owner := labels[gy * grid.x + gx]
			if owner != label and owner != 0:
				tile.set_pixel(x, y, Color(0, 0, 0, 0))
	return AlphaKey.crop_to_alpha(tile)


func _remove_stale_tiles(out_dir: String, id: String) -> void:
	var dir := DirAccess.open(out_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(id + "_") and file.trim_prefix(id + "_").get_basename().is_valid_int():
			dir.remove(file)


## Places the cropped plant bottom-centre on a TILE_SIZE square, with the gap flooded
## in the plant's own mean colour (alpha 0) so mips stay plant-coloured.
func _pad_to_square(tile: Image) -> Image:
	# A corner is always a hole (crop_to_alpha keeps a transparent margin), and holes
	# already carry the plant's mean colour from fill_background/dilate_colour.
	var mean := tile.get_pixel(0, 0)
	var square := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBAF)
	square.fill(Color(mean.r, mean.g, mean.b, 0.0))
	var x := (TILE_SIZE - tile.get_width()) / 2
	var y := TILE_SIZE - BASE_PADDING - tile.get_height()
	square.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, y))
	return square


func _selected(asset: Dictionary, options: Dictionary) -> bool:
	if options.has("only") and not (options["only"] as PackedStringArray).has(asset["id"]):
		return false
	return not options.has("biome") or asset["biome"] == options["biome"]


func _parse_args() -> Dictionary:
	var options := {}
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--only":
				options["only"] = args[i + 1].split(",")
			"--biome":
				options["biome"] = args[i + 1]
			"--no-scatter":
				options["no_scatter"] = true
	return options
