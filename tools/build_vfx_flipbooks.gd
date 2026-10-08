extends SceneTree
## Generates the animated VFX textures - FLIPBOOKS, a grid of frames a particle plays
## through over its life - that the explosions are built from.
##
## Run with:
##   godot --headless --path . --script tools/build_vfx_flipbooks.gd
##
## Procedural stand-ins, like build_vfx_textures.gd's: white shapes on transparent, so the
## particle's own gradient colours them (see docs/VFX_TEXTURES.md). An authored sheet with the
## same layout - 4 x 4 frames, read left to right, top to bottom - can replace either file in
## place, and nothing else has to change.
##
## Each frame is a 3D noise field sampled at a time that advances frame by frame, so the
## shape boils and churns between frames rather than being one picture scaled up. FastNoiseLite
## rather than GDScript noise: 16 frames of 128x128 is a quarter of a million samples, four
## octaves each.

const OUT_DIR := "res://assets/vfx/"
const FRAME := 128
const GRID := 4


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_build_sheet(_smoke_frame), "flipbook_smoke.png")
	_save(_build_sheet(_fire_frame), "flipbook_fire.png")
	quit()


func _save(image: Image, file_name: String) -> void:
	var path: String = OUT_DIR + file_name
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("Could not write %s" % path)
		return
	print("Wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = frequency
	return noise


func _build_sheet(frame_builder: Callable) -> Image:
	var sheet := Image.create(FRAME * GRID, FRAME * GRID, false, Image.FORMAT_RGBA8)
	var count: int = GRID * GRID
	for f: int in range(count):
		var t: float = float(f) / float(count - 1)
		var frame: Image = frame_builder.call(t)
		sheet.blit_rect(frame, Rect2i(0, 0, FRAME, FRAME), Vector2i((f % GRID) * FRAME, (f / GRID) * FRAME))
	return sheet


## A billow of smoke: grows, thins and frays as it ages. Lit from above - the RGB carries a
## soft top-light (density sampled a few pixels higher, compared with here) so a grey puff
## still reads as round and lumpy once the gradient has tinted it.
func _smoke_frame(t: float) -> Image:
	var image := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	var shape := _noise(11, 0.018)
	var warp := _noise(29, 0.012)
	var z: float = t * 45.0
	var reach: float = lerpf(0.62, 0.98, sqrt(t))
	var fade: float = pow(1.0 - t, 0.9)
	for y: int in range(FRAME):
		for x: int in range(FRAME):
			var here: float = _smoke_field(shape, warp, x, y, z, reach, t)
			var above: float = _smoke_field(shape, warp, x, y - 5, z, reach, t)
			var a: float = smoothstep(0.02, 0.55, here)
			# Lumps catch the light on their upper side and fall into shade below: the field
			# rising towards the top of a lump is lit, falling away is in shadow.
			var light: float = clampf(0.62 + (above - here) * -1.8 + (here - 0.3) * 0.5 - (float(y) / FRAME - 0.5) * 0.2, 0.25, 1.0)
			image.set_pixel(x, y, Color(light, light, light, clampf(a * fade, 0.0, 1.0)))
	return image


func _smoke_field(shape: FastNoiseLite, warp: FastNoiseLite, x: int, y: int, z: float, reach: float, t: float) -> float:
	var u := Vector2(x, y) / float(FRAME) * 2.0 - Vector2.ONE
	var w: float = warp.get_noise_3d(x, y, z) * 9.0
	var n: float = shape.get_noise_3d(x + w, y - w, z) * 0.5 + 0.5
	var radial: float = 1.0 - pow(u.length() / reach, 2.0)
	# Billows: the noise decides where the puff bulges and where it frays, the radial term
	# keeps it a puff. Older frames need more noise to stay solid, so they thin out from inside.
	return radial * 0.85 + (n - 0.5) * 1.1 - t * 0.35


## A puff of flame: a hot, dense core that churns outward and burns away to nothing. The RGB
## is brightest in the core, so the gradient's hot end lands in the middle of each puff.
func _fire_frame(t: float) -> Image:
	var image := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	var shape := _noise(37, 0.022)
	var licks := _noise(41, 0.04)
	var z: float = t * 60.0
	var reach: float = lerpf(0.6, 0.92, t)
	for y: int in range(FRAME):
		for x: int in range(FRAME):
			var u := Vector2(x, y) / float(FRAME) * 2.0 - Vector2.ONE
			var n: float = shape.get_noise_3d(x, y + t * 50.0, z) * 0.5 + 0.5
			var l: float = licks.get_noise_3d(x, y + t * 90.0, z) * 0.5 + 0.5
			var radial: float = 1.0 - pow(u.length() / reach, 2.0)
			# Licks: the upper half is pushed about more than the lower, so it burns upward.
			var upper: float = clampf(-u.y * 0.8 + 0.4, 0.0, 1.0)
			var field: float = radial * 0.9 + (n - 0.5) * 0.9 + (l - 0.5) * 0.7 * upper - t * 0.55
			var a: float = smoothstep(0.02, 0.3, field)
			var core: float = smoothstep(0.25, 0.75, field)
			var lum: float = clampf(0.5 + core * 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(lum, lum, lum, a))
	return image
