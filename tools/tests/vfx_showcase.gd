extends Node3D
## Renders the effect layer against a BRIGHT SKY and saves a screenshot.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/vfx_showcase.tscn -- <out.png>
##
## Exists because "barely visible against the sky" is not a thing any assertion can catch,
## and it is exactly the failure additive blending produces: an additive effect can only ADD
## light to what is behind it, so it blazes over dark ground and disappears against a sky
## that is already near-white. The camera here deliberately sits low and looks at the
## horizon, so every effect is drawn half over ground and half over sky in one frame - the
## comparison the eye needs to judge it.
##
## It renders the SAME frame at several times of day, under the game's own Sky3D rather
## than a stand-in sky, because the background these effects have to survive is not one
## colour - the day/night cycle moves it from near-white to black over a run, and an effect
## tuned against either end alone is wrong at the other.
##
## Not part of validate_godot.ps1: it proves nothing automatically, it just makes the thing
## look-at-able. See docs/SPELL_VFX_PLAN.md, "How to know it worked".

const SHOT_DELAY := 0.9
## The hours worth looking at: hard noon (the worst case for anything additive), the low
## warm sun that most of a wave is fought under, dusk, and night.
const HOURS: Array[float] = [12.0, 17.5, 20.0, 23.0]
## Each frame is scaled to this width for the stacked sheet - four full-resolution frames
## stacked is a 2880-pixel-tall image nobody can look at in one go.
const SHEET_WIDTH := 900

var _sky: Sky3D
var _ground: MeshInstance3D


func _ready() -> void:
	_build_world()
	_spawn_effects()
	_shoot.call_deferred()


func _build_world() -> void:
	# The game's own sky, not an approximation of it. Sky3D brings its own sun, moon,
	# clock and environment - it IS a WorldEnvironment - so adding one is the whole setup.
	_sky = Sky3D.new()
	_sky.name = "Sky3D"
	add_child(_sky)
	if _sky.tod:
		# The clock must not advance between the shots, or each frame is lit slightly
		# differently from the one it is being compared against.
		_sky.tod.game_time_enabled = false

	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	_ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.22, 0.26, 0.20)
	_ground.material_override = ground_material
	add_child(_ground)

	var camera := Camera3D.new()
	# Low and level, so the horizon runs across the middle of the frame.
	camera.position = Vector3(0.0, 2.1, 14.0)
	camera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _spawn_effects() -> void:
	# Left: a ground wave, mostly over ground.
	_place(SpellFx.shockwave(Player.FX_WHITE, 3.5, 4.0), Vector3(-7.0, 0.12, 0.0))
	# Middle: a beam standing UP through the horizon line - the worst case, and the one
	# Lightning Bolt actually draws.
	_place(SpellFx.beam(Vector3.UP, 9.0, Player.FX_BLUE, 1.1, 4.0), Vector3(-1.0, 0.2, 0.0))
	# Right of centre: sparks thrown into the air.
	_place(SpellFx.sparks(Player.FX_RED, 2.0, 40, 7.0), Vector3(3.5, 1.2, 0.0))
	# Right: the wall, whose top half is always against sky.
	var wall: SoulWall = SoulWall.create(7.0, 30.0, 5.0, 2.0, null)
	_place(wall, Vector3(9.5, 0.0, 0.0))
	wall.rotation.y = PI * 0.5

	# Far left: the frost globe, centred ON the ground so only its dome shows.
	_place(FrostGlobe.create(2.6, 30.0), Vector3(-13.0, 0.0, 2.0))
	# Behind the camera line, wide: the standing vortex, which has to read for its whole
	# ten-to-thirty seconds rather than for one frame.
	_place(SpellFx.vortex(4.5, SuctionZone.VORTEX_TINT, 20.0), Vector3(5.0, 0.0, 4.0))
	# Front and centre: the gust, blown towards the camera's left.
	var blast: Node3D = SpellFx.gust(12.0, Player.FX_BLUE)
	_place(blast, Vector3(1.0, 1.0, 6.0))
	blast.look_at(blast.global_position + Vector3(-1.0, 0.0, 0.35), Vector3.UP)


func _place(node: Node3D, at: Vector3) -> void:
	add_child(node)
	node.global_position = at


func _shoot() -> void:
	var out_path: String = "vfx_showcase.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	var frames: Array[Image] = []
	for hour: float in HOURS:
		if _sky and _sky.tod:
			_sky.tod.current_time = hour
		# The effects are one-shots, so each hour gets a fresh set rather than the tail of
		# the last one: a screenshot of four dying particle systems says nothing.
		_clear_effects()
		_spawn_effects()
		await get_tree().create_timer(SHOT_DELAY).timeout
		# The frame has to have been DRAWN before the viewport holds anything worth saving.
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		var scaled_height: int = int(round(float(frame.get_height()) * float(SHEET_WIDTH) / float(frame.get_width())))
		frame.resize(SHEET_WIDTH, scaled_height, Image.INTERPOLATE_LANCZOS)
		frames.append(frame)

	if _save_sheet(frames, out_path):
		print("Wrote %s (%d times of day)" % [out_path, frames.size()])
	get_tree().quit()


## Every effect spawned by _spawn_effects, and nothing else - the sky, ground and camera
## have to survive between shots.
func _clear_effects() -> void:
	for child: Node in get_children():
		if child == _sky or child == _ground or child is Camera3D:
			continue
		child.queue_free()
		remove_child(child)


func _save_sheet(frames: Array[Image], path: String) -> bool:
	if frames.is_empty():
		return false
	var cell_height: int = frames[0].get_height()
	var sheet := Image.create(SHEET_WIDTH, cell_height * frames.size(), false, frames[0].get_format())
	for index: int in frames.size():
		sheet.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, Vector2i(SHEET_WIDTH, cell_height)),
			Vector2i(0, cell_height * index))
	if sheet.save_png(path) != OK:
		push_error("Could not write %s" % path)
		return false
	return true
