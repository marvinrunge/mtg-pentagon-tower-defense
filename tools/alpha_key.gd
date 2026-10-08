extends RefCounted
## Keys plant art rendered on pure white into alpha-cutout textures. Shared by
## tools/build_grass_billboards.gd and tools/build_nature_cards.gd, so both sets of
## foliage are keyed identically - the constants below were measured on the grass
## sheets and every card in the game should agree with them.
##
## The sources are plants rendered against pure white, which is unusable as-is: a
## billboard needs alpha, and a naive "white pixels become transparent" pass both
## punches holes in bright highlights and leaves a white halo on every antialiased
## edge. So keying does three things:
##
##  1. Estimates alpha from distance-from-white, normalised so that solid interior
##     pixels land at 1.0 and only the antialiased fringe is partial (see ALPHA_LO /
##     ALPHA_HI below for why a plain `1 - min(rgb)` is not enough).
##  2. Un-mattes the colour in that fringe. The source is a composite over white,
##     C = F*a + (1-a), so the original foreground is recoverable as (C - (1-a)) / a.
##     Without this every blade keeps a pale outline that reads as fog at distance.
##  3. Dilates colour outwards into the transparent region, so mipmapping down the
##     texture pulls in plant colour rather than the undefined colour of fully
##     transparent pixels - the usual cause of grass turning into a grey haze in the
##     distance.

## Foliage is rendered with an ALPHA SCISSOR, and that governs everything below.
##
## The scissor is binary: alpha >= threshold draws at full opacity, anything under it
## is discarded. There is no such thing as a 40%-opaque blade edge in the final image,
## so a fringe pixel that is still mostly white does not blend away politely - it is
## promoted to a solid white pixel. Keying tuned by eye against an alpha-BLENDED
## preview will look clean there and still fringe badly in game.
##
## The only number that really matters is therefore where the binary cutoff lands, so
## it is declared directly and the ramp is derived from it. The foliage shader
## (assets/shaders/nature_foliage.gdshader) uses this same value.
const SCISSOR_THRESHOLD := 0.3

## How plant-like a pixel must be to survive, in the grassiness metric below.
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
## fill; these passes only need to blend the first few pixels out from each blade so
## the boundary is not a hard step.
const DILATE_PASSES := 3

## Padding kept around the cropped alpha bounds, in pixels.
const CROP_PADDING := 2


## How much a pixel looks like plant rather than like the white backdrop.
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
static func grassiness(colour: Color) -> float:
	var highest: float = maxf(colour.r, maxf(colour.g, colour.b))
	var lowest: float = minf(colour.r, minf(colour.g, colour.b))
	var saturation: float = (highest - lowest) / maxf(highest, 0.0001)
	return maxf(1.0 - highest, saturation)


## Replaces the white backdrop with alpha, and un-mattes the colour that the backdrop
## was blended into. Operates in place on an RGBAF image.
static func cut_out_white(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var colour := image.get_pixel(x, y)
			var distance: float = grassiness(colour)
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


## Bounds of the non-transparent pixels plus CROP_PADDING, or an empty Rect2i when
## nothing survived the keying.
static func alpha_bounds(image: Image) -> Rect2i:
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
		return Rect2i()

	min_x = maxi(0, min_x - CROP_PADDING)
	min_y = maxi(0, min_y - CROP_PADDING)
	max_x = mini(width - 1, max_x + CROP_PADDING)
	max_y = mini(height - 1, max_y + CROP_PADDING)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Trims the transparent margin, so the billboard quad carries plant edge to edge.
## Returns null when nothing survived the keying.
static func crop_to_alpha(image: Image) -> Image:
	var bounds := alpha_bounds(image)
	if bounds.size == Vector2i.ZERO:
		return null
	return image.get_region(bounds)


## Floods every transparent pixel with the tile's mean plant colour.
##
## Dilation alone cannot do this job: it spreads a few pixels per pass, and a tuft's
## bounding box is mostly empty, so the far corners would stay at whatever they were
## initialised to. Seeding the whole background with the average first means the mip
## chain converges on "the colour of this plant" instead of on black, which is what
## turns distant clumps into dark blobs.
static func fill_background(image: Image) -> void:
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


## Shrinks the image so its longest edge is at most max_size, keeping aspect. Run it
## after fill_background and a dilation pass, so the filter has real plant colour to
## pull from rather than smearing holes into the blades.
static func downscale(image: Image, max_size: int) -> void:
	var longest: int = maxi(image.get_width(), image.get_height())
	if longest <= max_size:
		return
	var scale: float = float(max_size) / float(longest)
	image.resize(
		maxi(1, int(round(image.get_width() * scale))),
		maxi(1, int(round(image.get_height() * scale))),
		Image.INTERPOLATE_LANCZOS,
	)


## Floods plant colour outwards into fully transparent pixels, leaving alpha alone.
## Only the RGB matters here: it is what mipmap generation averages, and averaging
## against undefined transparent colour is what makes distant grass go grey.
static func dilate_colour(image: Image) -> void:
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
