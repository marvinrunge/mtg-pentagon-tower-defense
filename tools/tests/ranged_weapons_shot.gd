extends Node
## Photographs the three ranged characters that carry a real weapon model, so the grip can
## be judged by looking at it.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/ranged_weapons_shot.tscn -- <out.png>
##
## The two numbers in CharacterBuilder.WEAPON_MODELS that cannot be derived - `rotation`
## and `grip` - are found here. Everything else about wearing a weapon is arithmetic: the
## scale comes from the model's measured extent and the bone comes from the table. Whether
## a bow looks HELD does not, so this builds the characters, poses them mid-attack and
## writes a PNG to look at.
##
## Posed rather than left in rest on purpose, and posed on the ATTACK clip specifically:
## a bow at rest tells you nothing about whether it is aimed, and a skinned mesh with no
## pose applied reports a zero AABB and is culled to a point (the same trap boss_shot.gd
## documents).

## Colour -> the scene to photograph. Only the three with Prop.WEAPON_MODEL; Red throws a
## stone and Black throws a bone, and neither is a model this tool could be wrong about.
const SUBJECTS: Array[Dictionary] = [
	{"color": "Green", "scene": "res://scenes/ranged/elf_ranged.tscn", "weapon": "elf-bow"},
	{"color": "White", "scene": "res://scenes/ranged/human_ranged.tscn", "weapon": "human-crossbow"},
	{"color": "Blue", "scene": "res://scenes/ranged/merfolk_ranged.tscn", "weapon": "merfolk-harpoon"},
]

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/ranged_weapons_shot.gd").new()
	shooter.name = "RangedWeaponShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 75:
		return
	_done = true
	await _shoot()


func _shoot() -> void:
	var out_path: String = "ranged_weapons.png"
	# Second argument picks the pose. "walk" is what the player actually sees for most of a
	# wave - an enemy marching down a lane carrying the thing - and "attack" is the frame
	# the weapon has to justify itself in. A grip can look right in one and wrong in the
	# other, so both get photographed.
	var clip: String = "attack"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	if args.size() > 1:
		clip = args[1]
	# Third argument narrows to one colour and moves in close, for judging a single grip
	# rather than comparing the row.
	var only: String = String(args[2]) if args.size() > 2 else ""
	var subjects: Array[Dictionary] = []
	for subject: Dictionary in SUBJECTS:
		if only == "" or String(subject["color"]) == only:
			subjects.append(subject)
	var scene: Node = get_tree().current_scene
	# The HUD is a full-screen CanvasLayer over the top of everything; a mission banner
	# across the subjects' chests is exactly where the weapons are.
	for layer: Node in scene.get_children():
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = false

	# The base platform's flat top, exactly as boss_shot.gd stages its row - out on the
	# lane geometry the ground sits at a different height and the subjects photograph
	# below the camera.
	var stage := Vector3(0.0, 0.5, 20.0)
	for i: int in range(subjects.size()):
		var subject: Dictionary = subjects[i]
		var visual: Node3D = (load(String(subject["scene"])) as PackedScene).instantiate()
		scene.add_child(visual)
		visual.global_position = stage + Vector3(float(i) * 1.3 - 1.3 * float(subjects.size() - 1) * 0.5, 0.0, 0.0)
		# 100, exactly as EnemyBase does it when it instantiates these same scenes.
		visual.scale = Vector3.ONE * 100.0
		# Three-quarters, not head-on. A crossbow aimed correctly points straight at the
		# camera and photographs as a stub; turned, its length is visible and so is whether
		# it is level.
		visual.rotation_degrees.y = 40.0

		var player: AnimationPlayer = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation(clip):
			player.play(clip)
			player.seek(player.get_animation(clip).length * 0.5, true)

		var mesh_node: MeshInstance3D = _body_mesh(visual)
		if mesh_node != null and mesh_node.mesh != null:
			var box: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
			visual.global_position.y += stage.y - box.position.y
		_report(subject, visual)

	var camera := Camera3D.new()
	scene.add_child(camera)
	var distance: float = 2.35 if subjects.size() > 1 else 1.5
	camera.global_position = stage + Vector3(0.0, 1.45, distance)
	camera.look_at(stage + Vector3(0.0, 1.15, 0.0), Vector3.UP)
	camera.current = true

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()


## Where the weapon actually ended up, in world units, printed alongside the photo so a
## grip that is off by a factor rather than by an angle can be read off the numbers
## instead of squinting at the image.
func _report(subject: Dictionary, visual: Node3D) -> void:
	var weapon: Node3D = visual.find_child("Weapon", true, false) as Node3D
	if weapon == null:
		print("SHOT %-6s %-16s NO WEAPON NODE" % [subject["color"], subject["weapon"]])
		return
	var attachment: Node = weapon.get_parent()
	var bone: String = str(attachment.bone_name) if attachment is BoneAttachment3D else "<not a BoneAttachment3D>"
	var bounds := AABB()
	var found: bool = false
	for mesh_instance: MeshInstance3D in _meshes(weapon):
		if mesh_instance.mesh == null:
			continue
		# mesh.get_aabb(), not MeshInstance3D.get_aabb(): the node's own version folds in
		# skinned/shadow bounds and reported every weapon as 20m long.
		var world: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = world if not found else bounds.merge(world)
		found = true
	var meshes: Array[MeshInstance3D] = _meshes(weapon)
	var local_aabb: AABB = meshes[0].mesh.get_aabb() if not meshes.is_empty() and meshes[0].mesh != null else AABB()
	print("SHOT %-6s %-16s bone=%-18s local_scale=%s world_scale=%s mesh_aabb=%s -> world_len=%.3fm" % [
		subject["color"], subject["weapon"], bone,
		weapon.transform.basis.get_scale().snapped(Vector3.ONE * 0.0001),
		weapon.global_transform.basis.get_scale().snapped(Vector3.ONE * 0.001),
		local_aabb.size.snapped(Vector3.ONE * 0.001),
		maxf(maxf(local_aabb.size.x, local_aabb.size.y), local_aabb.size.z)
			* weapon.global_transform.basis.get_scale().x])


func _body_mesh(visual: Node3D) -> MeshInstance3D:
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false) as Skeleton3D
	for child: Node in (skeleton.get_children() if skeleton else []):
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_meshes(child))
	return found
