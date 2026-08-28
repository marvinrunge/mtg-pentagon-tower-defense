class_name CharacterBuilder
extends RefCounted
## Builds every Melee/Ranged/Mage enemy scene from the new (2026-08-25) mesh and
## animation set, replacing tools/melee_character_builder.gd's output entirely
## (output paths: res://scenes/melee/<race>_melee.tscn, res://scenes/ranged/<race>_ranged.tscn,
## res://scenes/mage/<race>_mage.tscn - mage previously had no dedicated visual at all).
##
## Structurally the same problem solved for bosses/myrs (tools/boss_character_builder.gd,
## tools/myr_character_builder.gd): Mixamo-rigged meshes at a tiny raw import scale,
## clips borrowed across files needing a per-character grounding correction. See
## those files' own comments for why each technique is needed; not re-derived here.
##
## Source layout:
##   assets/enemies/<class>/<race>/<race>_<class>.fbx   mesh (+ own embedded clip)
##   assets/animations/character/<set>/{walk,attack,hit,death}.fbx   shared clips
##   assets/animations/character/mage/attack_<color>.fbx             per-colour mage attack
##   assets/animations/character/common/{throw_object,death_fallback}.fbx
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_characters.gd
##
## Deadlocks if an editor already holds the project lock; while the editor is open,
## call CharacterBuilder.build_all() through Godot MCP's execute_editor_script -
## and if this file has already been edited/re-run more than once in that same
## long-lived session, don't trust ResourceLoader.load(path, "", CACHE_MODE_REPLACE)
## to see the latest source; read it with FileAccess and compile a class_name-
## stripped throwaway GDScript instead (see .agents/learnings.md).

const ANIM_ROOT := "res://assets/animations/character/"
const CHAR_ROOT := "res://assets/enemies/"
const WEAPON_ROOT := "res://assets/weapons/"
const SCENE_DIR := "res://scenes/"

## Matches the 1.7-tall collision box in scenes/enemy.tscn, same as every other
## non-boss enemy visual this project has ever built.
const TARGET_HEIGHT := 1.7

const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const GROUND_SAMPLE_COUNT := 20

## Sentinel meaning "use this character's own mesh-embedded clip" for a given
## slot, instead of a shared file - only goblin_ranged's "walk" needs this (its
## own mesh was downloaded bundled with its own orc-walk cycle, per the user's
## explicit instruction to use that rather than a shared file).
const OWN_MESH_CLIP := "__OWN_MESH__"

const RACE_BY_COLOR := {
	"White": "human", "Blue": "merfolk", "Black": "zombie", "Red": "goblin", "Green": "elf",
}

## animation-set name -> clip slot -> source fbx (or OWN_MESH_CLIP).
const CLIP_SETS := {
	"sword_and_shield": {
		"walk": ANIM_ROOT + "sword_and_shield/walk.fbx",
		"attack": ANIM_ROOT + "sword_and_shield/attack.fbx",
		"hit": ANIM_ROOT + "sword_and_shield/hit.fbx",
		"death": ANIM_ROOT + "sword_and_shield/death.fbx",
	},
	# Mixamo's standing-melee pack has no death clip of its own (same gap noted
	# for the fire/frost giant bosses) - borrows the shared fallback.
	"standing_melee": {
		"walk": ANIM_ROOT + "standing_melee/walk.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"hit": ANIM_ROOT + "standing_melee/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	# Walk/attack borrowed from standing_melee per the user's explicit request
	# (2026-08-25) that melee zombies move/attack like goblin-melee; hit/death
	# stay zombie-specific.
	"zombie": {
		"walk": ANIM_ROOT + "standing_melee/walk.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	"bow": {
		"walk": ANIM_ROOT + "bow/walk.fbx",
		"attack": ANIM_ROOT + "bow/attack.fbx",
		"hit": ANIM_ROOT + "bow/hit.fbx",
		"death": ANIM_ROOT + "bow/death.fbx",
	},
	"crossbow": {
		"walk": ANIM_ROOT + "crossbow/walk.fbx",
		"attack": ANIM_ROOT + "crossbow/attack.fbx",
		"hit": ANIM_ROOT + "crossbow/hit.fbx",
		"death": ANIM_ROOT + "crossbow/death.fbx",
	},
	"goblin_ranged": {
		"walk": OWN_MESH_CLIP,
		"attack": ANIM_ROOT + "common/throw_object.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	"zombie_ranged": {
		"walk": ANIM_ROOT + "zombie/walk.fbx",
		"attack": ANIM_ROOT + "common/throw_object.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	# "attack" is deliberately absent - every mage gets a different one, added
	# per-character in _build_character (config.attack below).
	"mage": {
		"walk": ANIM_ROOT + "mage/walk.fbx",
		"hit": ANIM_ROOT + "mage/hit.fbx",
		"death": ANIM_ROOT + "mage/death.fbx",
	},
}

enum Prop { NONE, WEAPON_GLB, BOW, CROSSBOW, STONE, BONE_SMALL }

const CHARACTERS := {
	"Melee": {
		"White": {"mesh": CHAR_ROOT + "melee/human/human_melee.fbx", "set": "sword_and_shield", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "human/human_weapon.glb"},
		"Green": {"mesh": CHAR_ROOT + "melee/elf/elf_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "elf/elf_weapon.glb"},
		"Blue": {"mesh": CHAR_ROOT + "melee/merfolk/merfolk_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "merfolk/merfolk_weapon.glb"},
		"Black": {"mesh": CHAR_ROOT + "melee/zombie/zombie_melee.fbx", "set": "zombie", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "zombie/zombie_weapon.glb"},
		"Red": {"mesh": CHAR_ROOT + "melee/goblin/goblin_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "goblin/goblin_weapon.glb"},
	},
	"Ranged": {
		"Green": {"mesh": CHAR_ROOT + "ranged/elf/elf_ranged.fbx", "set": "bow", "prop": Prop.BOW},
		"White": {"mesh": CHAR_ROOT + "ranged/human/human_ranged.fbx", "set": "crossbow", "prop": Prop.CROSSBOW},
		"Blue": {"mesh": CHAR_ROOT + "ranged/merfolk/merfolk_ranged.fbx", "set": "crossbow", "prop": Prop.CROSSBOW},
		"Red": {"mesh": CHAR_ROOT + "ranged/goblin/goblin_ranged.fbx", "set": "goblin_ranged", "prop": Prop.STONE},
		"Black": {"mesh": CHAR_ROOT + "ranged/zombie/zombie_ranged.fbx", "set": "zombie_ranged", "prop": Prop.BONE_SMALL},
	},
	"Mage": {
		"White": {"mesh": CHAR_ROOT + "mage/human/human_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_white.fbx"},
		"Blue": {"mesh": CHAR_ROOT + "mage/merfolk/merfolk_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_blue.fbx"},
		"Black": {"mesh": CHAR_ROOT + "mage/zombie/zombie_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_black.fbx"},
		"Red": {"mesh": CHAR_ROOT + "mage/goblin/goblin_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_red.fbx"},
		"Green": {"mesh": CHAR_ROOT + "mage/elf/elf_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_green.fbx"},
	},
}

## Confirmed via direct inspection that these new meshes use "mixamorig_"-
## prefixed bone names (unlike the OLD melee assets tools/melee_character_builder.gd
## targets, which use bare names like "RightHand" - a different export/import
## convention, not a mistake in either file).
const WEAPON_GRIP_BONE := "mixamorig_RightHand"
const WEAPON_WORLD_SCALE := 0.5
const WEAPON_GRIP_DROP_WORLD := 0.08
const WEAPON_TWIST_DEGREES := 90.0
const WEAPON_LEAN_AXIS := Vector3(0.0, 0.0, 1.0)
const WEAPON_LEAN_DEGREES := 70.791
const WEAPON_GRIP_EXTRA_OFFSET_WORLD := Vector3(-0.136396, -0.08001, 0.012326)


static func build_all() -> void:
	var built := 0
	for class_key in CHARACTERS.keys():
		var suffix: String = class_key.to_lower()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR + suffix + "/"))
		for color in CHARACTERS[class_key].keys():
			var config: Dictionary = CHARACTERS[class_key][color]
			var race: String = RACE_BY_COLOR[color]
			if _build_character(color, race, suffix, config):
				built += 1

	print("Done. Built %d character scenes." % built)


static func _build_character(color: String, race: String, class_suffix: String, config: Dictionary) -> bool:
	var mesh_fbx_path: String = config["mesh"]
	var base_scene: PackedScene = ResourceLoader.load(mesh_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load mesh %s" % mesh_fbx_path)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = race.capitalize() + class_suffix.capitalize()

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if anim_player == null:
		push_error("%s has no AnimationPlayer" % mesh_fbx_path)
		return false

	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if mesh_node == null:
		push_error("%s has no MeshInstance3D" % mesh_fbx_path)
		return false
	var array_mesh: ArrayMesh = mesh_node.mesh
	array_mesh.surface_set_material(0, _build_albedo_material(mesh_fbx_path))

	# Root scale/lift must be set BEFORE grounding: the correction is measured
	# in this same (post-normalization) coordinate frame.
	_normalize_to_target_height(root, mesh_node)

	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("%s has no Skeleton3D" % mesh_fbx_path)
		return false

	var template: AnimationLibrary = _build_template_library(CLIP_SETS[config["set"]], mesh_fbx_path)
	if template == null:
		return false
	if config.has("attack"):
		var attack_anim := _extract_animation(config["attack"])
		if attack_anim == null:
			push_error("Could not extract per-character attack clip %s" % config["attack"])
			return false
		attack_anim.loop_mode = Animation.LOOP_NONE
		_strip_horizontal_root_motion(attack_anim, "mixamorig_Hips")
		template.add_animation("attack", attack_anim)

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var library: AnimationLibrary = _ground_correct_library(template, anim_player, root, skeleton)
	var output_name: String = "%s_%s" % [race, class_suffix]
	var library_path: String = ANIM_ROOT + "lib_%s.tres" % output_name
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Failed saving animation library %s" % library_path)
		return false
	anim_player.add_animation_library("", ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists, and
	# EnemyBase pauses it on the first frame as its resting pose.
	anim_player.autoplay = "walk"

	var prop_type: int = config.get("prop", Prop.NONE)
	if prop_type == Prop.WEAPON_GLB:
		_attach_weapon(skeleton, config["weapon_glb"])
	elif prop_type != Prop.NONE:
		_attach_prop(skeleton, prop_type)

	_own_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("PackedScene.pack failed for %s" % output_name)
		return false
	var output_path: String = SCENE_DIR + class_suffix + "/%s.tscn" % output_name
	if ResourceSaver.save(packed, output_path) != OK:
		push_error("ResourceSaver.save failed for %s" % output_name)
		return false

	print("Saved ", output_path, " (set=", config["set"], ")")
	root.queue_free()
	return true


static func _build_template_library(clip_set: Dictionary, mesh_fbx_path: String) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in clip_set.keys():
		var source_path: String = clip_set[clip_name]
		var anim: Animation
		if source_path == OWN_MESH_CLIP:
			anim = _extract_animation(mesh_fbx_path)
		else:
			anim = _extract_animation(source_path)
		if anim == null:
			push_error("Could not extract clip '%s' from %s" % [clip_name, source_path if source_path != OWN_MESH_CLIP else mesh_fbx_path])
			return null
		anim.loop_mode = Animation.LOOP_LINEAR if clip_name == "walk" else Animation.LOOP_NONE
		_strip_horizontal_root_motion(anim, "mixamorig_Hips")
		library.add_animation(clip_name, anim)
	return library


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


## Per-character copy of `template_library` with every clip's Hips position
## track shifted vertically so its lowest ground-contact point actually touches
## y=0 on THIS character's own (already height-normalized) skeleton - see
## tools/boss_character_builder.gd's matching function for why this is needed
## even for a mesh's own embedded clip (a Mixamo-export quirk, not a cross-file
## mismatch).
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
	var factor: float = TARGET_HEIGHT / bounds.size.y
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


## Rebuild the material from the albedo Godot extracts alongside the fbx rather
## than trusting the fbx's own imported material - the embedded-texture path
## has repeatedly pointed at a stale/duplicated extraction this project, and
## glTF/FBX metallic defaults render as chrome skin.
static func _build_albedo_material(mesh_fbx_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo_path: String = mesh_fbx_path.replace(".fbx", "_0.png")
	var albedo: Texture2D = ResourceLoader.load(albedo_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if albedo == null:
		push_warning("No albedo found at %s; character will render untextured" % albedo_path)
	else:
		mat.albedo_texture = albedo
	mat.metallic = 0.0
	mat.roughness = 1.0
	return mat


## Ported unchanged from tools/melee_character_builder.gd - the existing weapon
## glbs and hand-tuned constants above are still valid, they're unrelated to
## which body mesh holds them. Grips the weapon into WEAPON_GRIP_BONE via a
## BoneAttachment3D; the correction is computed per-skeleton (hand rest orientation
## differs per character), canceling that rotation then applying the shared
## twist/lean/offset tuning.
static func _attach_weapon(skeleton: Skeleton3D, weapon_glb_path: String) -> void:
	if skeleton == null:
		push_error("No Skeleton3D found for weapon attachment")
		return

	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandAttachment"
	attachment.bone_name = WEAPON_GRIP_BONE
	skeleton.add_child(attachment)

	var weapon_scene: PackedScene = ResourceLoader.load(weapon_glb_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	var weapon_root: Node3D = weapon_scene.instantiate()
	weapon_root.name = "Weapon"

	var armature_scale: float = _get_node_global_scale(skeleton).y
	var local_scale: float = WEAPON_WORLD_SCALE / armature_scale
	var local_grip_drop: float = WEAPON_GRIP_DROP_WORLD / armature_scale

	var hand_rest: Transform3D = _get_bone_global_rest(skeleton, WEAPON_GRIP_BONE)
	var intrinsic_rotation: Basis = Basis(Vector3.UP, deg_to_rad(WEAPON_TWIST_DEGREES)) * Basis(WEAPON_LEAN_AXIS, deg_to_rad(WEAPON_LEAN_DEGREES))
	var correction: Basis = hand_rest.basis.inverse() * intrinsic_rotation
	var grip_point_local: Vector3 = Vector3(0.0, local_scale - local_grip_drop, 0.0) + WEAPON_GRIP_EXTRA_OFFSET_WORLD / armature_scale
	weapon_root.transform = Transform3D(
		correction.scaled(Vector3.ONE * local_scale),
		correction * grip_point_local
	)

	attachment.add_child(weapon_root)

	var weapon_mesh_node: MeshInstance3D = weapon_root.find_child("mesh_node", true, false)
	if weapon_mesh_node and weapon_mesh_node.mesh:
		var weapon_array_mesh: ArrayMesh = weapon_mesh_node.mesh
		weapon_array_mesh.surface_set_material(0, _build_weapon_material(weapon_glb_path))


## Simple placeholder props (bow/crossbow stand-ins for weapons not delivered
## yet, and procedurally-built stone/bone for the two throwing classes) - held
## at the grip bone's own origin with no hand-rest cancellation, unlike
## _attach_weapon(). That correction exists to make a REAL weapon look right;
## it's not worth the complexity for shapes the user has already said are
## temporary and will be replaced.
static func _attach_prop(skeleton: Skeleton3D, prop_type: int) -> void:
	if skeleton == null:
		return
	var bone_name: String = "mixamorig_LeftHand" if prop_type in [Prop.BOW, Prop.CROSSBOW] else WEAPON_GRIP_BONE
	if skeleton.find_bone(bone_name) == -1:
		bone_name = WEAPON_GRIP_BONE

	var attachment := BoneAttachment3D.new()
	attachment.name = "PropAttachment"
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)

	var armature_scale: float = _get_node_global_scale(skeleton).y
	var prop := _build_prop_mesh(prop_type, armature_scale)
	attachment.add_child(prop)


static func _build_prop_mesh(prop_type: int, armature_scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop"
	match prop_type:
		Prop.STONE:
			var mesh := CSGSphere3D.new()
			mesh.radius = 0.05 / armature_scale
			mesh.radial_segments = 8
			mesh.rings = 6
			# Slightly irregular, not a perfect sphere - reads as a thrown rock
			# rather than a ball at this size.
			mesh.scale = Vector3(1.0, 0.8, 1.15)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.42, 0.40, 0.38)
			mat.roughness = 0.95
			mesh.material = mat
			root.add_child(mesh)
		Prop.BONE_SMALL:
			# A small thrown bone: thin shaft with two rounded knobs, scaled down
			# from the melee zombie club's own rough proportions per instruction.
			var shaft := CSGCylinder3D.new()
			shaft.radius = 0.012 / armature_scale
			shaft.height = 0.16 / armature_scale
			shaft.rotation_degrees.x = 90.0
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.88, 0.85, 0.76)
			mat.roughness = 0.7
			shaft.material = mat
			root.add_child(shaft)
			for offset_sign in [-1.0, 1.0]:
				var knob := CSGSphere3D.new()
				knob.radius = 0.022 / armature_scale
				knob.position = Vector3(0.0, 0.0, offset_sign * 0.08 / armature_scale)
				knob.material = mat
				root.add_child(knob)
		Prop.BOW:
			# Thin vertical stave - a clear "this is a stand-in" shape until the
			# real bow model is delivered.
			var mesh := CSGBox3D.new()
			mesh.size = Vector3(0.03, 0.9, 0.03) / armature_scale
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.35, 0.24, 0.14)
			mat.roughness = 0.8
			mesh.material = mat
			root.add_child(mesh)
		Prop.CROSSBOW:
			var mesh := CSGBox3D.new()
			mesh.size = Vector3(0.08, 0.18, 0.45) / armature_scale
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.2, 0.19)
			mat.roughness = 0.6
			mesh.material = mat
			root.add_child(mesh)
	return root


## The weapon glb embeds its own texture data and Godot's glTF importer re-extracts
## it under a name derived from the glb's own filename + material slot name,
## ignoring loose renamed files sitting alongside it - rebuild the material
## explicitly instead (same fix as _build_albedo_material, ported unchanged
## from tools/melee_character_builder.gd).
static func _build_weapon_material(weapon_glb_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ResourceLoader.load(weapon_glb_path.replace(".glb", "_albedo.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.normal_enabled = true
	mat.normal_texture = ResourceLoader.load(weapon_glb_path.replace(".glb", "_normal.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	var metallic_roughness: Texture2D = ResourceLoader.load(weapon_glb_path.replace(".glb", "_metallic_roughness.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.metallic = 1.0
	mat.metallic_texture = metallic_roughness
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.roughness = 1.0
	mat.roughness_texture = metallic_roughness
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	return mat


static func _get_node_global_scale(node: Node3D) -> Vector3:
	var scale := Vector3.ONE
	var current: Node = node
	while current is Node3D:
		scale *= (current as Node3D).transform.basis.get_scale()
		current = current.get_parent()
	return scale


static func _get_bone_global_rest(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	var chain: Array[int] = []
	var bone_idx := skeleton.find_bone(bone_name)
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_rest(b)
	return accum


static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_recursive(child, owner)
