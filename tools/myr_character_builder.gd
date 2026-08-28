class_name MyrCharacterBuilder
extends RefCounted
## Builds the five colour-specific Myr scenes and their animation libraries.
##
## Structurally the same problem as tools/boss_character_builder.gd (Mixamo-
## rigged meshes at a tiny raw import scale, clips borrowed across files that
## need a per-character grounding correction) with the combat-specific pieces
## (weapon attachment, attack/special clips) dropped - see that file's own
## comments for the reasoning behind each technique reused here.
##
## Source layout:
##   assets/myrs/<color>_myr/<color>_myr.fbx   mesh + its own embedded "walk" clip
##   assets/animations/myr/*.fbx               clips shared by all five colours
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_myr_characters.gd
##
## Deadlocks if an editor already holds the project lock; while the editor is
## open, call MyrCharacterBuilder.build_all() through Godot MCP's
## execute_editor_script instead - and if this file has been edited and re-run
## more than once already in that same long-lived editor session, don't trust
## ResourceLoader.load(path, "", CACHE_MODE_REPLACE) to see the latest source;
## read it with FileAccess and compile a class_name-stripped throwaway GDScript
## instead (see .agents/learnings.md, this bit the boss builder the same day).

const ANIM_ROOT := "res://assets/animations/myr/"
const SCENE_DIR := "res://scenes/myrs/"

## Matches scenes/myr.tscn's placeholder CSGCylinder3D (height=1.0, based at
## y=0) so swapping in a real model doesn't change the collision footprint.
const MYR_TARGET_HEIGHT := 1.0

const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const GROUND_SAMPLE_COUNT := 20

## Clips shared by every colour. "walk" (empty-handed, going to harvest) is NOT
## here - it comes from each colour's own mesh fbx instead (see _build_myr).
const SHARED_CLIPS := {
	"walk_loaded": ANIM_ROOT + "walk_loaded.fbx",
	"harvest": ANIM_ROOT + "harvest.fbx",
	"hit": ANIM_ROOT + "hit.fbx",
	"death": ANIM_ROOT + "death.fbx",
	# Not wired into scripts/myr.gd yet - there's no speed-buff mechanic to
	# trigger it. Included now so the clip is built, grounded, and ready in
	# every colour's library for whenever that buff exists.
	"run": ANIM_ROOT + "run.fbx",
}
const LOOPING_CLIPS := ["walk", "walk_loaded", "run"]

## color identity (matches scripts/main.gd's LANE_NAMES) -> mesh + output name.
const MYRS := {
	"White": {"mesh": "res://assets/myrs/gold_myr/gold_myr.fbx", "name": "gold_myr"},
	"Blue": {"mesh": "res://assets/myrs/silver_myr/silver_myr.fbx", "name": "silver_myr"},
	"Black": {"mesh": "res://assets/myrs/leaden_myr/leaden_myr.fbx", "name": "leaden_myr"},
	"Red": {"mesh": "res://assets/myrs/iron_myr/iron_myr.fbx", "name": "iron_myr"},
	"Green": {"mesh": "res://assets/myrs/copper_myr/copper_myr.fbx", "name": "copper_myr"},
}


static func build_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))

	var shared_clips: Dictionary = {}
	for clip_name in SHARED_CLIPS.keys():
		var anim := _extract_animation(SHARED_CLIPS[clip_name])
		if anim == null:
			push_error("Could not extract shared clip '%s' from %s" % [clip_name, SHARED_CLIPS[clip_name]])
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING_CLIPS else Animation.LOOP_NONE
		_strip_horizontal_root_motion(anim, "mixamorig_Hips")
		shared_clips[clip_name] = anim

	var built := 0
	for color in MYRS.keys():
		var config: Dictionary = MYRS[color]
		if _build_myr(color, config["mesh"], config["name"], shared_clips):
			built += 1

	print("Done. Built %d myr scenes." % built)


static func _extract_animation(source_fbx_path: String) -> Animation:
	var source_scene: PackedScene = ResourceLoader.load(source_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if source_scene == null:
		return null
	var source_root: Node = source_scene.instantiate()
	var player: AnimationPlayer = source_root.find_child("AnimationPlayer", true, false)
	if player == null or player.get_animation_list().is_empty():
		source_root.queue_free()
		return null
	var anim: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	source_root.queue_free()
	return anim


static func _strip_horizontal_root_motion(anim: Animation, bone_name: String) -> void:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			continue
		var key_count := anim.track_get_key_count(track_idx)
		if key_count == 0:
			return
		var base_value: Vector3 = anim.track_get_key_value(track_idx, 0)
		for key_idx in key_count:
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, Vector3(base_value.x, value.y, base_value.z))
		return


static func _build_myr(color: String, mesh_fbx_path: String, output_name: String, shared_clips: Dictionary) -> bool:
	var base_scene: PackedScene = ResourceLoader.load(mesh_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load myr mesh %s" % mesh_fbx_path)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = output_name.capitalize().replace(" ", "")

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if anim_player == null:
		push_error("%s has no AnimationPlayer" % mesh_fbx_path)
		return false
	# This mesh's own embedded clip becomes "walk" (empty-handed) - extract it
	# before the library gets removed below.
	var own_walk: Animation = null
	for lib_name in anim_player.get_animation_library_list():
		var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
		var names := lib.get_animation_list()
		if names.size() > 0:
			own_walk = lib.get_animation(names[0]).duplicate(true)
			break
	if own_walk == null:
		push_error("%s's own AnimationPlayer has no clip to use as 'walk'" % mesh_fbx_path)
		return false
	own_walk.loop_mode = Animation.LOOP_LINEAR
	_strip_horizontal_root_motion(own_walk, "mixamorig_Hips")
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if mesh_node == null:
		push_error("%s has no MeshInstance3D" % mesh_fbx_path)
		return false
	var array_mesh: ArrayMesh = mesh_node.mesh
	array_mesh.surface_set_material(0, _build_myr_material(mesh_fbx_path))

	# Root scale/lift must be set BEFORE grounding: the correction is measured in
	# this same (post-normalization) coordinate frame.
	_normalize_to_target_height(root, mesh_node)

	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("%s has no Skeleton3D" % mesh_fbx_path)
		return false

	var template := AnimationLibrary.new()
	template.add_animation("walk", own_walk)
	for clip_name in shared_clips.keys():
		template.add_animation(clip_name, shared_clips[clip_name].duplicate(true))

	var library: AnimationLibrary = _ground_correct_library(template, anim_player, root, skeleton)
	var library_path: String = ANIM_ROOT + "lib_%s.tres" % output_name
	var lib_save_result := ResourceSaver.save(library, library_path)
	if lib_save_result != OK:
		push_error("Failed saving grounded myr animation library %s: %d" % [library_path, lib_save_result])
		return false
	anim_player.add_animation_library("", ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists, and
	# Myr pauses it on the first frame as its resting pose (mirrors EnemyBase).
	anim_player.autoplay = "walk"

	_own_recursive(root, root)

	var packed := PackedScene.new()
	var pack_result := packed.pack(root)
	if pack_result != OK:
		push_error("PackedScene.pack failed for %s: %d" % [output_name, pack_result])
		return false

	var output_path := SCENE_DIR + "%s.tscn" % output_name
	var save_result := ResourceSaver.save(packed, output_path)
	if save_result != OK:
		push_error("ResourceSaver.save failed for %s: %d" % [output_name, save_result])
		return false

	print("Saved ", output_path, " (color=", color, ")")
	root.queue_free()
	return true


## See tools/boss_character_builder.gd's _build_animation_library docstring for
## why this is needed even for a mesh's own embedded clip: Mixamo's Hips
## position track carries an absolute Y baseline unrelated to that same
## skeleton's own bind pose, which floats the whole character once it animates.
static func _ground_correct_library(template_library: AnimationLibrary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var factor: float = root.transform.basis.get_scale().y
	var corrected := AnimationLibrary.new()

	for clip_name in template_library.get_animation_list():
		var anim: Animation = template_library.get_animation(clip_name).duplicate(true)
		var min_foot_y: float = _measure_min_foot_height(anim_player, skeleton, root, skeleton_to_root, anim)
		if is_finite(min_foot_y):
			_shift_hips_y(anim, "mixamorig_Hips", -min_foot_y / factor)
		else:
			push_warning("Could not measure foot height for clip '%s'; leaving ungrounded" % clip_name)
		corrected.add_animation(clip_name, anim)

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	return corrected


static func _measure_min_foot_height(anim_player: AnimationPlayer, skeleton: Skeleton3D, root: Node3D, skeleton_to_root: Transform3D, anim: Animation) -> float:
	var foot_indices: Array[int] = []
	for bone_name in FOOT_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			foot_indices.append(idx)
	if foot_indices.is_empty():
		return INF

	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP_NAME := "__ground_measure__"
	temp_library.add_animation(TEMP_CLIP_NAME, anim)
	anim_player.add_animation_library("__ground__", temp_library)
	anim_player.play("__ground__/" + TEMP_CLIP_NAME)

	var min_y := INF
	for i in range(GROUND_SAMPLE_COUNT + 1):
		var t: float = anim.length * float(i) / float(GROUND_SAMPLE_COUNT)
		anim_player.seek(t, true)
		for idx in foot_indices:
			var world_equiv: Transform3D = root.transform * skeleton_to_root * skeleton.get_bone_global_pose(idx)
			min_y = minf(min_y, world_equiv.origin.y)

	anim_player.stop()
	anim_player.remove_animation_library("__ground__")
	return min_y


static func _shift_hips_y(anim: Animation, bone_name: String, delta_y: float) -> void:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			continue
		for key_idx in anim.track_get_key_count(track_idx):
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, value + Vector3(0.0, delta_y, 0.0))
		return


static func _normalize_to_target_height(root: Node3D, mesh_node: MeshInstance3D) -> void:
	var mesh_to_root: Transform3D = _transform_to_ancestor(mesh_node, root)
	var bounds: AABB = mesh_to_root * mesh_node.mesh.get_aabb()
	if bounds.size.y <= 0.0:
		push_error("Degenerate mesh bounds for %s; leaving scale untouched" % root.name)
		return
	var factor: float = MYR_TARGET_HEIGHT / bounds.size.y
	var basis: Basis = root.transform.basis.orthonormalized().scaled(Vector3.ONE * factor)
	root.transform = Transform3D(basis, Vector3(0.0, -bounds.position.y * factor, 0.0))


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			chain.append(current as Node3D)
		current = current.get_parent()
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for n in chain:
		accum = accum * n.transform
	return accum


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
			return node as MeshInstance3D
		for child in node.get_children():
			stack.append(child)
	return null


static func _build_myr_material(mesh_fbx_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo_path: String = mesh_fbx_path.replace(".fbx", "_0.png")
	var albedo: Texture2D = ResourceLoader.load(albedo_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if albedo == null:
		push_warning("No albedo found at %s; myr will render untextured" % albedo_path)
	else:
		mat.albedo_texture = albedo
	mat.metallic = 0.0
	mat.roughness = 1.0
	return mat


static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_recursive(child, owner)
