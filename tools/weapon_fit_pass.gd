extends RefCounted
## Measures, in a live scene tree, the hand orientation each weapon must be aimed against.
## Preloaded by path, never by class_name (see tools/animation_impact.gd).
##
## A SEPARATE PASS for the same reason tools/locomotion_pass.gd is one: a Skeleton3D that
## is not in a tree does not pose reliably. CharacterBuilder never adds its root to a
## tree, so the hand orientation it reads for a given frame is not the one that frame
## really produces - measured on the human crossbow, the bone's X axis reads
## (-0.38, 0.26, -0.89) during the build and (-0.88, 0.27, -0.38) in a live tree. That is
## about forty degrees, and forty degrees is the difference between a crossbow aimed
## down-range and one aimed across its owner's chest.
##
## This pass only MEASURES, and hands the result back through
## CharacterBuilder.measured_grip_bases for a second build pass to use.
##
## It used to rewrite the built scene instead, by re-packing an instantiated one. That
## quietly DUPLICATED every weapon's mesh: _own_recursive made the glb instance's own
## child node owned, so it was serialised a second time as a sibling of the instance and
## each weapon rendered twice. Scenes are written by _build_character and nothing else
## now - it builds from raw nodes and gets ownership right.

const CharacterBuilder = preload("res://tools/character_builder.gd")


## Fills CharacterBuilder.measured_grip_bases. Returns the number that FAILED.
static func measure_all() -> int:
	var failed: int = 0
	for key: String in CharacterBuilder.WEAPON_MODELS:
		var parts: PackedStringArray = key.split("/")
		if parts.size() != 2:
			push_error("Unreadable WEAPON_MODELS key '%s'" % key)
			failed += 1
			continue
		var basis: Variant = await measure(parts[0], parts[1])
		if basis == null:
			failed += 1
			continue
		CharacterBuilder.measured_grip_bases[key] = basis
	return failed


## The grip bone's orientation in the pose its weapon is aimed against, or null.
static func measure(class_key: String, color: String) -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("WeaponFitPass needs a SceneTree to pose characters in")
		return null
	var model: Dictionary = CharacterBuilder.WEAPON_MODELS["%s/%s" % [class_key, color]]
	var root: Node3D = _stage(class_key, color, tree)
	if root == null:
		return null

	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var bone_index: int = skeleton.find_bone(String(model["bone"])) if skeleton != null else -1
	if skeleton == null or anim_player == null or bone_index == -1:
		push_error("%s/%s has no Skeleton3D, AnimationPlayer or bone '%s'" % [class_key, color, model["bone"]])
		root.free()
		return null

	var pose: Array = model.get("pose", [])
	if pose.size() >= 2 and anim_player.has_animation(String(pose[0])):
		anim_player.play(String(pose[0]))
		anim_player.seek(anim_player.get_animation(String(pose[0])).length * clampf(float(pose[1]), 0.0, 1.0), true)
		# One frame, so the pose is actually applied rather than merely queued. This await
		# is the entire reason the pass exists.
		await tree.process_frame
		anim_player.stop()
	else:
		push_warning("No pose clip for %s/%s; measuring whatever pose it is in" % [class_key, color])

	var measured: Basis = skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
	root.free()
	return measured


## The built character, in the tree. Shared with tools/capture_weapon_fit.gd.
static func _stage(class_key: String, color: String, tree: SceneTree) -> Node3D:
	var race: String = CharacterBuilder.RACE_BY_COLOR[color]
	var suffix: String = class_key.to_lower()
	var scene_path: String = CharacterBuilder.SCENE_DIR + suffix + "/%s_%s.tscn" % [race, suffix]
	var packed: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if packed == null:
		push_error("No character scene at %s" % scene_path)
		return null
	var root: Node3D = packed.instantiate()
	tree.get_root().add_child(root)
	return root
