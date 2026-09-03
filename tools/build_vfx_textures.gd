extends SceneTree
## Generates the two VFX textures EmberFx draws with, as PLACEHOLDERS.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_vfx_textures.gd
##
## Both are meant to be replaced by authored versions - see docs/VFX_TEXTURES.md for
## where to get better ones and what makes a texture usable here. Overwrite the files
## in place and keep the names; nothing else has to change, because every colour in
## the effects comes from the particle system's own gradient rather than from the
## texture (which is why these are white on transparent, and why the authored ones
## should be too).
##
## Generated rather than committed as art because a procedural stand-in that is
## exactly the right SHAPE - a soft round falloff, and a turbulent round puff - keeps
## the effects working and readable while the real art is still being chosen.

const OUT_DIR := "res://assets/vfx/"
const SIZE := 256


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_build_spark_glow(), "spark_glow.png")
	_save(_build_fire_smoke(), "fire_smoke.png")
	quit()


func _save(image: Image, file_name: String) -> void:
	var path: String = OUT_DIR + file_name
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("Could not write %s" % path)
		return
	print("Wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


## A soft round glow: white throughout, with only the alpha falling off. Used for
## sparks and for anything that wants to read as a point of light rather than as a
## shape - the falloff is smoothstepped rather than linear so the edge never bands.
func _build_spark_glow() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius: float = SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var distance: float = (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(centre) / radius
			# Flat core out to 40%, then a smooth shoulder to nothing at the edge.
			var alpha: float = 1.0 - smoothstep(0.4, 1.0, distance)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	return image


## A turbulent round puff. Fractal noise for the wisps, multiplied by a radial mask so
## it stays a blob rather than filling the quad, and contrast-stretched so the middle
## keeps a bright core the way a real explosion frame does.
func _build_fire_smoke() -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 20260902
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = 2.3

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.seed = 771
	detail.frequency = 0.045
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 3

	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius: float = SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var distance: float = (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(centre) / radius
			var mask: float = 1.0 - smoothstep(0.15, 0.95, distance)
			# Noise is -1..1; folded to 0..1 and biased so the puff has more substance
			# than holes.
			var base: float = (noise.get_noise_2d(x, y) + 1.0) * 0.5
			var wisps: float = (detail.get_noise_2d(x, y) + 1.0) * 0.5
			var value: float = clampf(base * 0.75 + wisps * 0.35, 0.0, 1.0)
			var alpha: float = clampf(smoothstep(0.35, 0.85, value) * mask, 0.0, 1.0)
			# A hotter core, so the particle still has a centre once it is tinted.
			var core: float = 1.0 - smoothstep(0.0, 0.55, distance)
			alpha = clampf(alpha + core * 0.45 * mask, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return image
