extends Node3D
## Renders models on their own - a neutral grey studio, soft light from above, the model
## framed whole from three-quarters front and three-quarters back - to look at a new asset
## without the map around it.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 900x900 res://tools/tests/asset_shot.tscn -- <folder> res://a.glb,res://b.glb
##
## Writes <folder>/<file name>_front.png and _back.png per model.

const SETTLE_FRAMES := 20

var _camera: Camera3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.5
	add_child(fill)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	add_child(_camera)
	_camera.current = true
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0]
	DirAccess.make_dir_recursive_absolute(folder)
	for path: String in args[1].split(","):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		add_child(model)
		# A creature comes with its clips; one playing would walk it out of the frame.
		for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
			player.stop()
		await get_tree().process_frame
		var box := _bounds(model)
		var centre := box.get_center()
		var radius: float = box.size.length() * 0.5
		var distance: float = radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.05
		for side: Array in [["front", 35.0], ["back", 215.0]]:
			var dir := Vector3(sin(deg_to_rad(side[1])), 0.45, cos(deg_to_rad(side[1]))).normalized()
			_camera.global_position = centre + dir * distance
			_camera.look_at(centre, Vector3.UP)
			_camera.far = distance * 4.0
			for i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file := "%s_%s.png" % [path.get_file().get_basename(), side[0]]
			get_viewport().get_texture().get_image().save_png(folder.path_join(file))
			print("ASSET saved %s (%.2f x %.2f x %.2f)" % [file, box.size.x, box.size.y, box.size.z])
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## What the model covers. A skinned mesh's own AABB is its bind pose and can sit far from
## where the skeleton puts it, so a model with a skeleton is framed by its bones instead,
## padded by a tenth of their spread for the flesh round them.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for skeleton: Skeleton3D in root.find_children("*", "Skeleton3D", true, false):
		for bone: int in skeleton.get_bone_count():
			var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			box = AABB(at, Vector3.ZERO) if first else box.expand(at)
			first = false
	if not first:
		return box.grow(box.size.length() * 0.1)
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
