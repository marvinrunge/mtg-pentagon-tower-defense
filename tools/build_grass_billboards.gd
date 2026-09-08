extends SceneTree
## Turns the 2x2 grass sheets in assets/foliage/grass/source/ into 20 alpha-cutout
## billboard textures, four per biome.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_grass_billboards.gd
##
## The sources are grass tufts photographed/rendered against pure white, which is
## unusable as-is: a billboard needs alpha, and a naive "white pixels become
## transparent" pass both punches holes in bright highlights and leaves a white halo
## on every antialiased blade edge. So this does three things per tile:
##
##  1. Estimates alpha from distance-from-white, normalised so that solid interior
##     pixels land at 1.0 and only the antialiased fringe is partial (see ALPHA_LO /
##     ALPHA_HI below for why a plain `1 - min(rgb)` is not enough).
##  2. Un-mattes the colour in that fringe. The source is a composite over white,
##     C = F*a + (1-a), so the original foreground is recoverable as (C - (1-a)) / a.
##     Without this every blade keeps a pale outline that reads as fog at distance.
##  3. Dilates colour outwards into the transparent region, so mipmapping down the
##     texture pulls in blade colour rather than the undefined colour of fully
##     transparent pixels - the usual cause of grass turning into a grey haze in the
##     distance.
##
## Tiles are then cropped to their alpha bounding box, so the quad that carries them
## is all grass and no empty margin. GrassScatter reads the aspect back off the
## texture at build time, so cropping to different sizes per variant is fine.
##
## The source sheets stay in the repo behind a .gdignore (Godot must not import 9 MB
## of white-background PNGs as game textures) so this stays re-runnable.

const SOURCE_DIR := "res://assets/foliage/grass/source/"
const OUT_DIR := "res://assets/foliage/grass/"
const BIOMES := ["white", "blue", "black", "red", "green"]

## Grass is rendered with an ALPHA SCISSOR, and that governs everything below.
##
## The scissor is binary: alpha >= threshold draws at full opacity, anything under it
## is discarded. There is no such thing as a 40%-opaque blade edge in the final image,
## so a fringe pixel that is still mostly white does not blend away politely - it is
## promoted to a solid white pixel. Keying tuned by eye against an alpha-BLENDED
## preview will look clean there and still fringe badly in game.
##
## The only number that really matters is therefore where the binary cutoff lands, so
## it is declared directly and the ramp is derived from it.
const SCISSOR_THRESHOLD := 0.3

## How grass-like a pixel must be to survive, in the _grassiness metric below.
## Measured, not guessed: the cumulative distribution over the source tiles puts 60.9%
## (green), 67.8% (red) and 66.7% (wheat) of pixels under 0.05 - the white backdrop -
## and by 0.30 those have risen only to 62.9%, 69.4% and 73.2%. The 2%, 1.6% and 6.5%
## in between is the antialiased halo, which is exactly what should be discarded.
const BLADE_CUTOFF := 0.30

## Width of the soft ramp around the cutoff. Narrow, because the scissor throws most
## of it away regardless; it exists so mipmaps have some coverage gradient to average
## instead of a hard binary edge.
const ALPHA_SOFTNESS := 0.26

## Derived so a pixel sitting exactly at BLADE_CUTOFF lands exactly on the scissor
## threshold. Deriving rather than hand-tuning is the whole point: an earlier pair of
## hand-picked values put the effective cutoff at 0.108, which let through anything
## with a min channel below 0.892 - as fully opaque white.
const ALPHA_LO := BLADE_CUTOFF - SCISSOR_THRESHOLD * ALPHA_SOFTNESS
const ALPHA_HI := ALPHA_LO + ALPHA_SOFTNESS

## Below this the pixel is background, not fringe - zeroed outright so the crop box
## is not dragged out by JPEG-ish noise in the white field.
const ALPHA_FLOOR := 0.02

## Passes of colour dilation into transparent pixels, run either side of the
## downscale. The bulk of the transparent region is handled by the average-colour
## fill below; these passes only need to blend the first few pixels out from each
## blade so the boundary is not a hard step.
const DILATE_PASSES := 3

## Padding kept around the cropped alpha bounds, in pixels.
const CROP_PADDING := 2

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

			_cut_out_white(tile)
			tile = _crop_to_alpha(tile)
			if tile == null:
				push_error("%s tile %d was empty after keying" % [biome, index + 1])
				continue
			# Order matters, and getting it wrong is invisible until the grass is a
			# few metres away. Transparent pixels still carry RGB, and both the
			# downscale filter and the mip chain average that RGB in alongside the
			# blades - so every transparent pixel has to hold a sensible colour
			# BEFORE either runs, or distant grass darkens toward whatever was left
			# in the holes.
			_fill_background(tile)
			_dilate_colour(tile)
			_downscale(tile)
			_dilate_colour(tile)
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


## How much a pixel looks like grass rather than like the white backdrop.
##
## Two terms, whichever is larger. Darkness (1 - max channel) catches blades in shadow;
## saturation catches bright but strongly coloured ones. White scores zero on both -
## and so does the pale grey-white halo around a blade, which a plain
## distance-from-white metric could not tell apart from pale golden straw.
##
## That was the previous metric's failure. Solid wheat at RGB(0.90, 0.75, 0.43) and a
## halo pixel at RGB(0.95, 0.92, 0.89) score 0.57 and 0.11 on min-channel distance -
## too close for any threshold to separate cleanly. Here they score 0.52 and 0.06,
## because the wheat is colourful and the halo is merely pale.
func _grassiness(colour: Color) -> float:
	var highest: float = maxf(colour.r, maxf(colour.g, colour.b))
	var lowest: float = minf(colour.r, minf(colour.g, colour.b))
	var saturation: float = (highest - lowest) / maxf(highest, 0.0001)
	return maxf(1.0 - highest, saturation)


## Replaces the white backdrop with alpha, and un-mattes the colour that the backdrop
## was blended into. Operates in place.
func _cut_out_white(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var colour := image.get_pixel(x, y)
			var distance: float = _grassiness(colour)
			var alpha: float = clampf((distance - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0.0, 1.0)

			if alpha <= ALPHA_FLOOR:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue

			if alpha < 1.0:
				# C = F*a + 1*(1-a) with a white backdrop, so F = (C - (1-a)) / a.
				var inverse: float = 1.0 - alpha
				colour = Color(
					clampf((colour.r - inverse) / alpha, 0.0, 1.0),
					clampf((colour.g - inverse) / alpha, 0.0, 1.0),
					clampf((colour.b - inverse) / alpha, 0.0, 1.0),
				)

			colour.a = alpha
			image.set_pixel(x, y, colour)


## Trims the transparent margin, so the billboard quad carries grass edge to edge.
## Returns null when nothing survived the keying.
func _crop_to_alpha(image: Image) -> Image:
	var width := image.get_width()
	var height := image.get_height()
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1

	for y in height:
		for x in width:
			if image.get_pixel(x, y).a <= ALPHA_FLOOR:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)

	if max_x < 0:
		return null

	min_x = maxi(0, min_x - CROP_PADDING)
	min_y = maxi(0, min_y - CROP_PADDING)
	max_x = mini(width - 1, max_x + CROP_PADDING)
	max_y = mini(height - 1, max_y + CROP_PADDING)
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


## Floods every transparent pixel with the tile's mean blade colour.
##
## Dilation alone cannot do this job: it spreads a few pixels per pass, and a tuft's
## bounding box is mostly empty, so the far corners would stay at whatever they were
## initialised to. Seeding the whole background with the average first means the mip
## chain converges on "the colour of this grass" instead of on black, which is what
## turns distant clumps into dark blobs.
func _fill_background(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var total := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	for y in height:
		for x in width:
			var colour := image.get_pixel(x, y)
			if colour.a < 0.9:
				continue
			total += Color(colour.r, colour.g, colour.b, 0.0)
			count += 1
	if count == 0:
		return
	var mean := Color(total.r / count, total.g / count, total.b / count, 0.0)
	for y in height:
		for x in width:
			if image.get_pixel(x, y).a > 0.0:
				continue
			image.set_pixel(x, y, mean)


## Shrinks the tile so its longest edge is at most MAX_TILE_SIZE, keeping aspect.
## Runs after the background fill and a dilation pass, so the filter has real blade
## colour to pull from rather than smearing holes into the blades.
func _downscale(image: Image) -> void:
	var longest: int = maxi(image.get_width(), image.get_height())
	if longest <= MAX_TILE_SIZE:
		return
	var scale: float = float(MAX_TILE_SIZE) / float(longest)
	image.resize(
		maxi(1, int(round(image.get_width() * scale))),
		maxi(1, int(round(image.get_height() * scale))),
		Image.INTERPOLATE_LANCZOS,
	)


## Floods blade colour outwards into fully transparent pixels, leaving alpha alone.
## Only the RGB matters here: it is what mipmap generation averages, and averaging
## against undefined transparent colour is what makes distant grass go grey.
func _dilate_colour(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	const NEIGHBOURS := [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]

	for pass_index in DILATE_PASSES:
		var source := image.duplicate() as Image
		for y in height:
			for x in width:
				if source.get_pixel(x, y).a > 0.0:
					continue
				var total := Color(0.0, 0.0, 0.0, 0.0)
				var count := 0
				for offset: Vector2i in NEIGHBOURS:
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var neighbour := source.get_pixel(nx, ny)
					if neighbour.a <= 0.0:
						continue
					total += Color(neighbour.r, neighbour.g, neighbour.b, 0.0)
					count += 1
				if count == 0:
					continue
				# Alpha stays at zero - this pixel is still a hole, it just now has a
				# sensible colour for the mip chain to average.
				image.set_pixel(x, y, Color(total.r / count, total.g / count, total.b / count, 0.0))
