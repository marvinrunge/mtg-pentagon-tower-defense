extends Node
## Photographs all five bosses side by side, in their idle pose, so their models can be
## compared against each other.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/boss_shot.tscn -- <out.png>
##
## Built to answer "which bosses are missing a weapon": the boss visuals are single skinned
## meshes generated from one FBX each, so if a weapon is absent it is absent from the source
## art rather than detached at runtime, and the only way to tell which is which is to look.
## Also prints each rig's bone and surface inventory, which is what would show a weapon that
## IS present but skinned to the wrong bone.

const BOSSES: Array[String] = ["Red", "Blue", "Green", "White", "Black"]

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/boss_shot.gd").new()
	shooter.name = "BossShooter"
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
	_shoot()


func _shoot() -> void:
	var out_path: String = "bosses.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	var scene: Node = get_tree().current_scene

	# On the base platform, whose top surface is a known flat y=0.5 (the CSGCylinder sits at
	# y=0.25 with height 0.5). The first version staged them at z=90, out on the lane geometry,
	# where the ground is at a different height - the whole row spawned below the camera and
	# the shot came back empty.
	var stage := Vector3(0.0, 0.5, 20.0)
	for i: int in range(BOSSES.size()):
		var visual_scene: PackedScene = BossDatabase.get_visual_scene(BOSSES[i])
		if visual_scene == null:
			print("  %s: no visual scene" % BOSSES[i])
			continue
		var visual: Node3D = visual_scene.instantiate()
		scene.add_child(visual)
		visual.global_position = stage + Vector3(float(i) * 3.2 - 6.4, 0.0, 0.0)
		# 100x, exactly as EnemyBase does it: the imported models are stored at about 0.017m
		# and only reach their 1.7m target height once scaled. The first version of this used
		# 1.6 and photographed five bosses two and a half centimetres tall, which is also why
		# their AABBs printed as zero.
		visual.scale = Vector3.ONE * 160.0
		# Posed rather than left in rest. A skinned MeshInstance3D whose mesh resource reports a
		# zero AABB - which these do - is culled as a zero-size point until a skeleton pose has
		# given it real bounds, so an un-animated boss photographs as nothing at all.
		var player: AnimationPlayer = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation("attack"):
			player.play("attack")
			player.seek(player.get_animation("attack").length * 0.5, true)
		# Lifted so the feet meet the platform. EnemyBase does this properly in
		# _ground_visual() by measuring the lowest foot bone; here the mesh AABB is enough,
		# and without it the row photographs buried to the waist.
		var mesh_node: MeshInstance3D = _first_mesh(visual)
		if mesh_node != null and mesh_node.mesh != null:
			var box: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
			visual.global_position.y += stage.y - box.position.y
		_report(BOSSES[i], visual)

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = stage + Vector3(0.0, 2.0, 8.0)
	camera.look_at(stage + Vector3(0.0, 1.3, 0.0), Vector3.UP)
	camera.current = true

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()


## What the rig is actually made of. A weapon that exists but hangs off the wrong bone shows
## up here as an extra surface or a non-mixamorig bone; a weapon that was never modelled shows
## up as neither, and no amount of runtime attachment work would put one in its hand.
func _first_mesh(visual: Node3D) -> MeshInstance3D:
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false) as Skeleton3D
	for child: Node in (skeleton.get_children() if skeleton else []):
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _report(color: String, visual: Node3D) -> void:
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh: MeshInstance3D = visual.find_child("*texture*", true, false) as MeshInstance3D
	if mesh == null:
		for child: Node in (skeleton.get_children() if skeleton else []):
			if child is MeshInstance3D:
				mesh = child as MeshInstance3D
				break
	var extra_bones: Array[String] = []
	if skeleton != null:
		for i: int in range(skeleton.get_bone_count()):
			var bone_name: String = skeleton.get_bone_name(i)
			if not bone_name.begins_with("mixamorig"):
				extra_bones.append(bone_name)
	var world_aabb: String = "none"
	if mesh != null and mesh.mesh != null:
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		world_aabb = "pos%s size%s" % [box.position.round(), box.size.round()]
	print("  %-6s at%s visible=%s aabb=%s" % [
		color, visual.global_position.round(), visual.visible, world_aabb])
	print("  %-6s bones=%d surfaces=%d non-rig bones=%s" % [
		color,
		skeleton.get_bone_count() if skeleton else -1,
		mesh.mesh.get_surface_count() if mesh != null and mesh.mesh != null else -1,
		str(extra_bones) if not extra_bones.is_empty() else "none",
	])
