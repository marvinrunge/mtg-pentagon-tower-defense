extends SceneTree
## Generates CANDIDATE textures for the empty slots in SpellFx.TEXTURES, plus one contact
## sheet to compare them on.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_vfx_candidates.gd [out_dir]
##
## Nothing here is wired into the game and nothing lands in assets/vfx/. These exist to be
## LOOKED AT: three takes on each of the five shapes the effect layer wants, so the choice
## between them - and between generating them at all and using authored art - is made by
## looking rather than by argument. Copy the winners into assets/vfx/ and point the slot at
## them in scripts/spell_fx.gd; that is the whole adoption step.
##
## Same rules as tools/build_vfx_textures.gd, for the same reason: WHITE on transparent,
## with every colour coming from the effect's gradient at runtime. A candidate with baked
## colour cannot serve a white spell and a black one from one file.

const SIZE := 256
## Cells on the sheet are drawn over this, because white on transparent is invisible on a
## white page and these are judged by their falloff more than by their silhouette.
const SHEET_BACKGROUND := Color(0.06, 0.07, 0.09, 1.0)
const GUTTER := 6

## Slot -> the three takes on it, in the order they appear across the contact sheet.
const CANDIDATES := {
	"mote": ["point", "glint", "speck"],
	"shard": ["diamond", "sliver", "chip"],
	"decal_scorch": ["burn", "cracked", "soot"],
	"decal_frost": ["star", "fern", "rime"],
	"decal_blight": ["mottle", "veins", "halo"],
}


func _init() -> void:
	var out_dir: String = "candidates"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var rows: Array = []
	for slot: String in CANDIDATES:
		var row: Array = []
		for variant: String in CANDIDATES[slot]:
			var image: Image = _build(slot, variant)
			var path: String = "%s/%s__%s.png" % [out_dir, slot, variant]
			if image.save_png(path) != OK:
				push_error("Could not write %s" % path)
			else:
				print("Wrote %s" % path)
			row.append(image)
		rows.append(row)

	var sheet_path: String = "%s/_contact_sheet.png" % out_dir
	if _contact_sheet(rows).save_png(sheet_path) == OK:
		print("Wrote %s" % sheet_path)
	quit()


func _build(slot: String, variant: String) -> Image:
	match slot:
		"mote":
			return _mote(variant)
		"shard":
			return _shard(variant)
		"decal_scorch":
			return _scorch(variant)
		"decal_frost":
			return _frost(variant)
		_:
			return _blight(variant)


# --- shared helpers ------------------------------------------------------------

func _noise(frequency: float, seed_value: int, fractal_octaves: int = 4) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = fractal_octaves
	return noise


## White throughout, alpha carrying the shape. Every builder below fills through this so
## none of them can accidentally bake a colour in.
func _mask(shape: Callable) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE, SIZE) * 0.5
	var half: float = SIZE * 0.5
	for y: int in SIZE:
		for x: int in SIZE:
			var offset: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / half
			var alpha: float = clampf(shape.call(offset), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return image


# --- mote: the drifting speck --------------------------------------------------

func _mote(variant: String) -> Image:
	match variant:
		"point":
			# A tighter spark_glow: most of the quad is empty, so a cloud of these reads as
			# separate points rather than as one wash.
			return _mask(func(p: Vector2) -> float:
				return pow(1.0 - smoothstep(0.08, 0.62, p.length()), 2.0))
		"glint":
			# Four-rayed star. What catches the eye in a slow-moving cloud, because the rays
			# stay visible at sizes where a round dot is one pixel.
			return _mask(func(p: Vector2) -> float:
				var core: float = pow(1.0 - smoothstep(0.0, 0.35, p.length()), 2.0)
				var rays: float = maxf(
					1.0 - smoothstep(0.0, 0.035, absf(p.x)) * 1.0,
					1.0 - smoothstep(0.0, 0.035, absf(p.y)))
				rays *= 1.0 - smoothstep(0.15, 0.95, p.length())
				return maxf(core, rays * 0.8))
		_:
			# An irregular grain: pollen, ash, whatever a green or black spell is shedding.
			var noise: FastNoiseLite = _noise(0.9, 40404, 3)
			return _mask(func(p: Vector2) -> float:
				var wobble: float = noise.get_noise_2d(p.x * 60.0, p.y * 60.0) * 0.16
				return 1.0 - smoothstep(0.25 + wobble, 0.7 + wobble, p.length()))


# --- shard: blue's hard edge ---------------------------------------------------

func _shard(variant: String) -> Image:
	match variant:
		"diamond":
			# Sharp at both ends and widest in the middle. Reads as ice however it is
			# rotated, which matters for particles that spin.
			return _mask(func(p: Vector2) -> float:
				var d: float = absf(p.x) * 3.4 + absf(p.y)
				return 1.0 - smoothstep(0.55, 0.95, d))
		"sliver":
			# One bright spine down a soft body: a splinter catching the light rather than a
			# flat shape.
			return _mask(func(p: Vector2) -> float:
				var body: float = 1.0 - smoothstep(0.3, 0.9, absf(p.x) * 4.0 + absf(p.y) * 0.9)
				var spine: float = (1.0 - smoothstep(0.0, 0.05, absf(p.x))) \
					* (1.0 - smoothstep(0.35, 0.95, absf(p.y)))
				return maxf(body * 0.75, spine))
		_:
			# An asymmetric chip. Three straight cuts, so it never reads as a machined shape
			# the way a diamond can.
			return _mask(func(p: Vector2) -> float:
				var a: float = p.y * 0.9 + 0.45
				var b: float = -p.y * 0.5 - p.x * 1.5 + 0.5
				var c: float = -p.y * 0.4 + p.x * 1.6 + 0.5
				var inside: float = minf(minf(a, b), c)
				return smoothstep(0.0, 0.09, inside))


# --- decals: what a spell leaves on the ground ---------------------------------

func _scorch(variant: String) -> Image:
	match variant:
		"burn":
			# A ragged round burn. The radius is warped by noise sampled in the PLANE rather
			# than by angle: sampling round a circle at high amplitude is what turned this
			# into a starburst on the first pass, because the warp changes faster than the
			# shape it is warping.
			var noise: FastNoiseLite = _noise(1.0, 7311, 3)
			return _mask(func(p: Vector2) -> float:
				var warp: float = noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.13
				return 1.0 - smoothstep(0.52 + warp, 0.80 + warp, p.length()))
		"cracked":
			# Burn with the cracks cut OUT of it as dark lines, rather than drawn on top as
			# bright ones - a break in the ground is an absence of surface, and a decal made
			# of bright cracks reads as glowing lava instead.
			var noise: FastNoiseLite = _noise(1.0, 991, 2)
			return _mask(func(p: Vector2) -> float:
				var dist: float = p.length()
				var angle: float = atan2(p.y, p.x)
				var warp: float = noise.get_noise_2d(p.x * 2.5, p.y * 2.5) * 0.12
				var body: float = 1.0 - smoothstep(0.5 + warp, 0.78 + warp, dist)
				# Six wandering splits, wide near the middle and closing towards the rim.
				var split: float = absf(sin(angle * 3.0 + noise.get_noise_2d(p.x * 4.0, p.y * 4.0) * 2.0))
				var cut: float = 1.0 - smoothstep(0.0, 0.10 * (1.0 - dist), split)
				return body * (1.0 - cut * 0.85))
		_:
			# Soot: no clean boundary at all, just density falling off through blotches. The
			# one that layers best when several land on top of each other. Coarse on purpose
			# - fine grain at this size averages out to a plain grey disc on screen.
			var noise: FastNoiseLite = _noise(1.0, 5150, 4)
			return _mask(func(p: Vector2) -> float:
				var blotch: float = noise.get_noise_2d(p.x * 5.0, p.y * 5.0) * 0.5 + 0.5
				var falloff: float = 1.0 - smoothstep(0.05, 0.9, p.length())
				return falloff * smoothstep(0.25, 0.85, blotch * 0.7 + falloff * 0.5))


func _frost(variant: String) -> Image:
	match variant:
		"star":
			# Six-armed crystal: long thin primary arms with a short secondary set between
			# them. Thin is what makes it ice - the fat-armed version of this reads as a
			# flower, which is what the first pass produced.
			return _mask(func(p: Vector2) -> float:
				var angle: float = atan2(p.y, p.x)
				var dist: float = p.length()
				var long_arms: float = pow(absf(cos(angle * 3.0)), 22.0)
				var short_arms: float = pow(absf(sin(angle * 3.0)), 26.0) * 0.45
				var reach: float = 0.12 + long_arms * 0.82 + short_arms * 0.4
				var spine: float = 1.0 - smoothstep(reach * 0.75, reach, dist)
				return clampf(spine + (1.0 - smoothstep(0.0, 0.1, dist)), 0.0, 1.0))
		"fern":
			# Branching rime, the way frost actually grows on glass: a spine per arm with
			# finer noise breaking it up along its length.
			var noise: FastNoiseLite = _noise(1.1, 8802, 4)
			return _mask(func(p: Vector2) -> float:
				var angle: float = atan2(p.y, p.x)
				var dist: float = p.length()
				var spines: float = pow(absf(cos(angle * 3.0 + noise.get_noise_2d(dist * 10.0, 0.0) * 1.2)), 6.0)
				var fade: float = 1.0 - smoothstep(0.1, 0.95, dist)
				return clampf(spines * fade * 1.4 + fade * 0.18, 0.0, 1.0))
		_:
			# A patch of rime: crystal EDGES rather than crystal shapes, which is what the
			# thin bright lines of a cellular noise ridge give. The quiet one, for a wide
			# area where six repeating arms would read as a stamp.
			# Ridged simplex rather than cellular: the crystal edges are the noise field's
			# own zero crossings, which is a range that always has values in it. The
			# cellular version of this rendered EMPTY - its return type put every sample
			# outside the window the ridge was cut from.
			var noise: FastNoiseLite = _noise(1.0, 3311, 3)
			return _mask(func(p: Vector2) -> float:
				var ridge: float = 1.0 - smoothstep(0.0, 0.13, absf(noise.get_noise_2d(p.x * 6.0, p.y * 6.0)))
				var second: float = 1.0 - smoothstep(0.0, 0.09, absf(noise.get_noise_2d(p.x * 13.0 + 40.0, p.y * 13.0)))
				return maxf(ridge, second * 0.7) * (1.0 - smoothstep(0.15, 0.92, p.length())))


func _blight(variant: String) -> Image:
	match variant:
		"mottle":
			# Blotches of rot at two scales, thresholded into actual PATCHES. Left as a
			# smooth noise field it averages into the same grey disc as every other noise
			# texture on the sheet; the threshold is what gives it edges to read.
			var coarse: FastNoiseLite = _noise(1.0, 6161, 3)
			var fine: FastNoiseLite = _noise(1.0, 6162, 4)
			return _mask(func(p: Vector2) -> float:
				var blotch: float = coarse.get_noise_2d(p.x * 3.5, p.y * 3.5) * 0.5 + 0.5
				var grain: float = fine.get_noise_2d(p.x * 14.0, p.y * 14.0) * 0.2
				var falloff: float = 1.0 - smoothstep(0.1, 0.9, p.length())
				return smoothstep(0.35, 0.62, blotch + grain) * falloff)
		"veins":
			# Creeping tendrils reaching outward - the one that reads as something SPREADING
			# rather than something that has already happened.
			#
			# The wander is sampled along the tendril's own length, so each one bends as it
			# travels. Sampling it by angle alone, as the first pass did, bends every
			# tendril identically and the result is a starburst.
			var noise: FastNoiseLite = _noise(1.0, 2277, 3)
			return _mask(func(p: Vector2) -> float:
				var dist: float = p.length()
				var angle: float = atan2(p.y, p.x) + noise.get_noise_2d(p.x * 2.2, p.y * 2.2) * 1.9
				var vein: float = pow(absf(cos(angle * 2.5)), 16.0)
				# Thinning as they reach out, and never quite reaching the rim.
				var reach: float = 1.0 - smoothstep(0.25, 0.85, dist)
				var root: float = 1.0 - smoothstep(0.0, 0.18, dist)
				return clampf(vein * reach * 1.6 + root * 0.6, 0.0, 1.0))
		_:
			# Hollow: dark at the rim, clear in the middle. For a zone whose EDGE is the
			# information - where the effect stops being dangerous.
			var noise: FastNoiseLite = _noise(0.8, 4004, 3)
			return _mask(func(p: Vector2) -> float:
				var angle: float = atan2(p.y, p.x)
				var wobble: float = noise.get_noise_2d(cos(angle) * 5.0, sin(angle) * 5.0) * 0.12
				var ring: float = 1.0 - smoothstep(0.0, 0.22, absf(p.length() - (0.68 + wobble)))
				return ring * ring)


# --- the sheet -----------------------------------------------------------------

## Every candidate in one image: a row per slot, three variants across. Composited over a
## dark ground because that is what they will actually be drawn over, and because white on
## transparent shows nothing at all in a file browser.
func _contact_sheet(rows: Array) -> Image:
	var columns: int = 3
	var width: int = columns * SIZE + (columns + 1) * GUTTER
	var height: int = rows.size() * SIZE + (rows.size() + 1) * GUTTER
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BACKGROUND)
	for row_index: int in rows.size():
		for column_index: int in rows[row_index].size():
			var cell: Image = rows[row_index][column_index]
			var origin := Vector2i(
				GUTTER + column_index * (SIZE + GUTTER),
				GUTTER + row_index * (SIZE + GUTTER))
			sheet.blend_rect(cell, Rect2i(Vector2i.ZERO, Vector2i(SIZE, SIZE)), origin)
	return sheet
