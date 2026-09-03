class_name BossCharacterBuilder
extends RefCounted
## Builds the boss character scenes and their shared animation libraries.
##
## Deliberately separate from MeleeCharacterBuilder: the melee/ranged character
## scenes are hand-tuned and must never be regenerated (see .agents/learnings.md),
## so nothing in here reads or writes scenes/*_melee.tscn / *_ranged.tscn.
##
## Source layout (all Mixamo-rigged, so every clip uses mixamorig_* bone names and
## is therefore interchangeable between these rigs - confirmed every bone named by
## each set's clips exists on the meshes that use it):
##
##   assets/animations/boss/common/          clips shared by more than one set
##   assets/animations/boss/<set>/           clips specific to one animation set
##   assets/bosses/<boss>/<boss>.fbx         rigged mesh + its extracted albedo
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_boss_characters.gd
##
## As with the melee builder this deadlocks if an editor already holds the project
## lock; while the editor is open call BossCharacterBuilder.build_all() through
## Godot MCP's execute_editor_script instead.

const AnimationImpact = preload("res://tools/animation_impact.gd")

const ANIM_ROOT := "res://assets/animations/boss/"
const LIBRARY_DIR := "res://assets/animations/boss/"
const SCENE_DIR := "res://scenes/bosses/"

## Every boss visual is normalized to this height (in metres) at scale 1.0, which
## matches the 1.7-tall collision box in scenes/enemy.tscn. Per-boss size then
## comes purely from EnemyData.model_scale, so one number controls how big a boss
## is and the animation-speed-from-size rule has a single input.
const BOSS_TARGET_HEIGHT := 1.7

## clip name -> source fbx, per animation set. Clip names are the contract with
## EnemyBase: "walk", "attack", "hit", "death", "special".
const ANIM_SETS := {
	# Fire + frost giant. Mixamo's standing-melee pack has no death clip of its
	# own, so it borrows the shared collapse.
	"standing_melee": {
		"walk": ANIM_ROOT + "standing_melee/walk.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"special": ANIM_ROOT + "standing_melee/special_whirlwind.fbx",
		"hit": ANIM_ROOT + "common/hit_react_gut.fbx",
		"death": ANIM_ROOT + "common/death_collapse.fbx",
	},
	# Treant. The mutant pack has no hit reaction, so it borrows the shared one.
	"mutant": {
		"walk": ANIM_ROOT + "mutant/walk.fbx",
		"attack": ANIM_ROOT + "mutant/attack.fbx",
		"special": ANIM_ROOT + "mutant/special_jump_attack.fbx",
		"hit": ANIM_ROOT + "common/hit_react_gut.fbx",
		"death": ANIM_ROOT + "common/death_collapse.fbx",
	},
	# White paladin - the only set that ships a complete five-clip spread.
	"sword_shield": {
		"walk": ANIM_ROOT + "sword_shield/walk.fbx",
		"attack": ANIM_ROOT + "sword_shield/attack.fbx",
		"special": ANIM_ROOT + "sword_shield/special_slash.fbx",
		"hit": ANIM_ROOT + "sword_shield/hit.fbx",
		"death": ANIM_ROOT + "sword_shield/death.fbx",
	},
	"zombie": {
		"walk": ANIM_ROOT + "zombie/walk.fbx",
		"attack": ANIM_ROOT + "zombie/attack.fbx",
		"special": ANIM_ROOT + "zombie/special_headbutt.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "zombie/death.fbx",
	},
}

const LOOPING_CLIPS := ["walk"]

## Bone names used to find "where the feet are" for the grounding correction
## below. LeftToeBase/RightToeBase are the lowest bones in the chain.
const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]

## Samples taken across a clip's length when measuring its lowest foot height.
## Sparse enough to be fast, dense enough to catch the true ground-contact frame
## of a walk cycle rather than missing it between keyframes.
const GROUND_SAMPLE_COUNT := 20

## boss key -> source mesh + which animation set it uses.
const BOSSES := {
	"fire_giant": {"mesh": "res://assets/enemies/bosses/fire_giant/fire_giant.fbx", "set": "standing_melee"},
	"frost_giant": {"mesh": "res://assets/enemies/bosses/frost_giant/frost_giant.fbx", "set": "standing_melee"},
	"treant": {"mesh": "res://assets/enemies/bosses/treant/treant.fbx", "set": "mutant"},
	"white_paladin": {"mesh": "res://assets/enemies/bosses/white_paladin/white_paladin.fbx", "set": "sword_shield"},
	"zombie_lord": {"mesh": "res://assets/enemies/bosses/zombie_lord/zombie_lord.fbx", "set": "zombie"},
}


static func build_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))

	var templates: Dictionary = {}
	for set_name in ANIM_SETS.keys():
		var library := _build_animation_library(set_name)
		if library == null:
			continue
		templates[set_name] = library
		print("Built template set '", set_name, "' animations=", library.get_animation_list())

	var built := 0
	for boss_name in BOSSES.keys():
		var config: Dictionary = BOSSES[boss_name]
		if not templates.has(config["set"]):
			push_error("No animation template for set '%s' (boss %s)" % [config["set"], boss_name])
			continue
		if _build_boss(boss_name, config["mesh"], templates[config["set"]]):
			built += 1

	print("Done. Built %d boss scenes from %d animation sets." % [built, templates.size()])


## Builds the un-grounded template for one animation set - every clip's Hips
## position track still carries whatever absolute Y baseline Mixamo happened to
## bake in, which does NOT line up with any particular boss's own proportions
## (confirmed: even fire_giant's OWN embedded clip, exported from the SAME file
## as its OWN mesh, has its Hips position track sitting ~10x higher than that
## same skeleton's own bone_rest Hips Y - so this is a Mixamo-export quirk, not a
## cross-file mismatch). _build_boss() re-grounds a copy of this per boss instead
## of using it directly - see _ground_correct_library.
static func _build_animation_library(set_name: String) -> AnimationLibrary:
	var clips: Dictionary = ANIM_SETS[set_name]
	var library := AnimationLibrary.new()
	for clip_name in clips.keys():
		var anim := _extract_animation(clips[clip_name])
		if anim == null:
			push_error("Could not extract '%s' for set '%s' from %s" % [clip_name, set_name, clips[clip_name]])
			return null
		anim.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING_CLIPS else Animation.LOOP_NONE
		# Mixamo exports these with forward travel baked into the Hips track (walk
		# and the lunging attacks drift up to 1.5 body-lengths). The enemy is a
		# CharacterBody3D driven by navigation, so that translation would fight
		# physics and slide the mesh off its own collider - keep only the vertical
		# component, which is the bob and (for the jump attack) the actual hop.
		_strip_horizontal_root_motion(anim, "mixamorig_Hips")
		library.add_animation(clip_name, anim)
	return library


static func _extract_animation(source_fbx_path: String) -> Animation:
	# CACHE_MODE_REPLACE throughout: this runs repeatedly inside one long-lived
	# editor session, where a plain load() can hand back a stale cached scene.
	var source_scene: PackedScene = ResourceLoader.load(source_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if source_scene == null:
		return null
	var source_root: Node = source_scene.instantiate()
	var player: AnimationPlayer = source_root.find_child("AnimationPlayer", true, false)
	if player == null or player.get_animation_list().is_empty():
		source_root.queue_free()
		return null
	# Mixamo names every exported clip "mixamo_com"; the useful name is the one we
	# assign in ANIM_SETS, so just take the single animation each file carries.
	var anim: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	source_root.queue_free()
	return anim


## Builds a per-boss copy of `template_library` with every clip's Hips position
## track shifted vertically so its feet actually reach y=0 (this boss's own
## floor, in the coordinate frame `root`'s already-normalized transform defines)
## at that clip's own lowest point - see _build_animation_library's docstring
## for why this is needed even for a boss's own self-consistent embedded clip.
##
## The shift is a single constant per clip (not a per-frame retarget): only Hips
## carries a position track here, every other bone is rotation-only, so a
## constant vertical offset on Hips moves the whole character without touching
## the walk cycle's own leg motion/bob at all.
static func _ground_correct_library(template_library: AnimationLibrary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	# _measure_min_foot_height reads through root.transform, so it returns a
	# WORLD-scale value (post the ~85x normalization factor). The Hips position
	# track itself lives in RAW, pre-scale units - dividing by this factor is
	# what converts "shift the rendered character down by 0.85 world units" into
	# "shift this raw track's numbers by 0.01", not 0.85.
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

	# Leave the player without a library attached to Godot's runtime resource
	# cache under the wrong path - _build_boss attaches the saved-and-reloaded
	# corrected library right after this returns.
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	return corrected


## Scrubs `anim` across its own length on the live `skeleton` (via a temporary
## library on `anim_player`) and returns the lowest Y either foot bone reaches,
## expressed in `root`'s own coordinate frame (i.e. where EnemyBase expects y=0
## to be the floor). Returns INF if this rig has neither foot bone.
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
		# update=true applies the pose to the skeleton immediately, synchronously -
		# nothing here waits on a process frame, which matters since this all
		# happens on nodes that are never added to a live tree during a build.
		anim_player.seek(t, true)
		for idx in foot_indices:
			var world_equiv: Transform3D = root.transform * skeleton_to_root * skeleton.get_bone_global_pose(idx)
			min_y = minf(min_y, world_equiv.origin.y)

	anim_player.stop()
	anim_player.remove_animation_library("__ground__")
	return min_y


## Adds `delta_y` to every keyframe of `bone_name`'s position track, if it has one.
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


static func _build_boss(boss_name: String, mesh_fbx_path: String, template_library: AnimationLibrary) -> bool:
	var base_scene: PackedScene = ResourceLoader.load(mesh_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load boss mesh %s" % mesh_fbx_path)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = _to_pascal_case(boss_name)

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if anim_player == null:
		push_error("%s has no AnimationPlayer" % mesh_fbx_path)
		return false
	# Drop the single clip Mixamo baked into the mesh download - it gets replaced
	# below with a grounded, per-boss copy of the set's template library.
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if mesh_node == null:
		push_error("%s has no MeshInstance3D" % mesh_fbx_path)
		return false
	var array_mesh: ArrayMesh = mesh_node.mesh
	array_mesh.surface_set_material(0, _build_boss_material(mesh_fbx_path))

	# Root scale/lift must be set BEFORE grounding: the correction is measured in
	# this same (post-normalization) coordinate frame, so the two stay consistent
	# regardless of this boss's own raw import scale or proportions.
	_normalize_to_target_height(root, mesh_node)

	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("%s has no Skeleton3D" % mesh_fbx_path)
		return false
	var library: AnimationLibrary = _ground_correct_library(template_library, anim_player, root, skeleton)
	# Records where the ordinary swing actually connects, so EnemyBase can pay the
	# hit out on that frame instead of on the frame the swing started. The SPECIAL is
	# deliberately not measured: its impact moment is authored in BossDatabase
	# because it also sets how long the dodge indicator fills, and the leap-and-land
	# specials connect with the whole body rather than with a limb a peak can see.
	var impact_ratio: float = AnimationImpact.annotate(library, "attack", skeleton, anim_player, root)
	var library_path: String = LIBRARY_DIR + "lib_%s.tres" % boss_name
	var lib_save_result := ResourceSaver.save(library, library_path)
	if lib_save_result != OK:
		push_error("Failed saving grounded boss animation library %s: %d" % [library_path, lib_save_result])
		return false
	# Reload from disk so the boss scene references the saved file as an
	# ext_resource instead of embedding a copy of the clips.
	anim_player.add_animation_library("", ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists, and
	# EnemyBase pauses it on the first frame as its resting pose.
	anim_player.autoplay = "walk"

	_own_recursive(root, root)

	var packed := PackedScene.new()
	var pack_result := packed.pack(root)
	if pack_result != OK:
		push_error("PackedScene.pack failed for %s: %d" % [boss_name, pack_result])
		return false

	var output_path := SCENE_DIR + "%s.tscn" % boss_name
	var save_result := ResourceSaver.save(packed, output_path)
	if save_result != OK:
		push_error("ResourceSaver.save failed for %s: %d" % [boss_name, save_result])
		return false

	print("Saved ", output_path, " (attack impact at ", "%.0f%%" % (impact_ratio * 100.0), ")")
	root.queue_free()
	return true


## These rigs import ~0.02 units tall (Mixamo centimetres run through the FBX
## importer's own scale conversion) and centred on the origin rather than standing
## on it. Scale the visual root so the character is BOSS_TARGET_HEIGHT tall and
## lift it so its feet sit at y=0, matching where scenes/enemy.tscn puts the body.
static func _normalize_to_target_height(root: Node3D, mesh_node: MeshInstance3D) -> void:
	var mesh_to_root: Transform3D = _transform_to_ancestor(mesh_node, root)
	var bounds: AABB = mesh_to_root * mesh_node.mesh.get_aabb()
	if bounds.size.y <= 0.0:
		push_error("Degenerate mesh bounds for %s; leaving scale untouched" % root.name)
		return
	var factor: float = BOSS_TARGET_HEIGHT / bounds.size.y
	# Preserve whatever orientation the importer put on the root, just add scale.
	var basis: Basis = root.transform.basis.orthonormalized().scaled(Vector3.ONE * factor)
	root.transform = Transform3D(basis, Vector3(0.0, -bounds.position.y * factor, 0.0))


## Composed local transform from `node` up to (but excluding) `ancestor`. Uses
## local .transform only: global_transform requires being inside a live tree,
## which nothing here is during a build.
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


## Rebuild the material from the albedo Godot extracts alongside the fbx rather
## than trusting the fbx's own imported material - same reasoning as the melee
## builder: the embedded-texture path has repeatedly pointed at a stale or
## duplicated extraction, and glTF/FBX metallic defaults render as chrome skin.
static func _build_boss_material(mesh_fbx_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo_path: String = mesh_fbx_path.replace(".fbx", "_0.png")
	var albedo: Texture2D = ResourceLoader.load(albedo_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if albedo == null:
		push_warning("No albedo found at %s; boss will render untextured" % albedo_path)
	else:
		mat.albedo_texture = albedo
	mat.metallic = 0.0
	mat.roughness = 1.0
	return mat


static func _to_pascal_case(snake: String) -> String:
	var out := ""
	for part in snake.split("_", false):
		out += part.capitalize()
	return out


static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_recursive(child, owner)
