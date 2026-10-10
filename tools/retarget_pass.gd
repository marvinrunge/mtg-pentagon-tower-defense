extends RefCounted
## Retargets the clips in the finished animation libraries of the enemies, the myrs and the
## player onto the skeleton that plays them (tools/animation_retarget.gd says why: a Mixamo
## clip copied by bone name onto a rig it was not made for bends that rig's feet, here up to
## 25 degrees on the enemies). Preloaded by path, never by class_name.
##
## A pass over the SAVED libraries rather than a step inside each builder, for the reason
## LocomotionPass and ReclipPass are passes too: the character scenes have been tuned by
## hand since they were generated (.agents/learnings.md, 2026-08-23), and a library is a
## separate resource the scene only references. The scenes are read here - for the skeleton
## and to measure the feet - and never written.
##
## The source skeleton is the one inside each clip's own file - the only one there is, as
## many of these clips were downloaded for models no longer in the project. That skeleton
## is Mixamo's T-pose, not the A-pose the model was rigged in (AnimationRetarget.
## source_skeleton), and only the feet and toes - of the bones that matter here - sit
## exactly as on the model. So only they are retargeted: everything else keeps its keys as
## they were, which matters beyond correctness, because every weapon in the character
## scenes was placed by hand against the hands those keys give. Retargeting the arms too
## turned them 60-115 degrees.
##
## Grounding is kept, not redone: each builder grounds its clips its own way, so a clip's
## Hips track is shifted only by however much the retarget moved the lowest foot, and lands
## exactly as high as it did before. Every clip done is marked `retargeted_from`, and a
## marked clip is skipped - running this twice changes nothing the second time.
##
## The bosses are not in here: BossCharacterBuilder retargets as it builds.

const Retarget = preload("res://tools/animation_retarget.gd")
const CharacterBuilder = preload("res://tools/character_builder.gd")
const MyrBuilder = preload("res://tools/myr_character_builder.gd")
const PlayerBuilder = preload("res://tools/player_character_builder.gd")

const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
## The bones retargeted - the ones the source skeleton has right (see above).
const RETARGETED_BONES := ["mixamorig_LeftFoot", "mixamorig_LeftToeBase", "mixamorig_RightFoot", "mixamorig_RightToeBase"]
const GROUND_SAMPLES := 20


## Every library this pass covers: [library path, scene that plays it, {clip: source fbx}].
static func targets() -> Array:
	var out: Array = []
	for class_key: String in CharacterBuilder.CHARACTERS:
		var suffix: String = class_key.to_lower()
		for color: String in CharacterBuilder.CHARACTERS[class_key]:
			var config: Dictionary = CharacterBuilder.CHARACTERS[class_key][color]
			var race: String = CharacterBuilder.RACE_BY_COLOR[color]
			var clips: Dictionary = (CharacterBuilder.CLIP_SETS[config["set"]] as Dictionary).duplicate()
			if config.has("attack"):
				clips["attack"] = config["attack"]
			# A clip that comes from the character's own mesh is its own by definition.
			for clip: String in clips.keys():
				if clips[clip] == CharacterBuilder.OWN_MESH_CLIP:
					clips.erase(clip)
			var name: String = "%s_%s" % [race, suffix]
			out.append([CharacterBuilder.ANIM_ROOT + "lib_%s.tres" % name,
				CharacterBuilder.SCENE_DIR + suffix + "/%s.tscn" % name, clips])
	for color: String in MyrBuilder.MYRS:
		var name: String = MyrBuilder.MYRS[color]["name"]
		out.append([MyrBuilder.ANIM_ROOT + "lib_%s.tres" % name, MyrBuilder.SCENE_DIR + "%s.tscn" % name,
			MyrBuilder.SHARED_CLIPS.duplicate()])
	# The player's own clips were downloaded onto the player's own model; the ones it borrows
	# from the enemy rig - the death and the five casts - were not.
	var foreign: Dictionary = {}
	for clip: String in PlayerBuilder.FOREIGN_CLIPS:
		foreign[clip] = PlayerBuilder.FOREIGN_CLIPS[clip][0]
	out.append([PlayerBuilder.LIBRARY_PATH, PlayerBuilder.OUTPUT_SCENE, foreign])
	return out


## Runs the pass over every library in targets(). Returns how many clips were retargeted.
static func run() -> int:
	var done: int = 0
	var sources: Dictionary = {}
	for target: Array in targets():
		done += _retarget_library(target[0], target[1], target[2], sources)
	print("Retarget pass done: %d clips retargeted; no scene was touched." % done)
	return done


static func _retarget_library(library_path: String, scene_path: String, clips: Dictionary, sources: Dictionary) -> int:
	var library: AnimationLibrary = ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	var scene: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if library == null or scene == null:
		push_error("Retarget pass: cannot load %s or %s" % [library_path, scene_path])
		return 0
	var root: Node3D = scene.instantiate()
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("Retarget pass: %s has no Skeleton3D" % scene_path)
		root.free()
		return 0

	var done: int = 0
	for clip: String in clips:
		if not library.has_animation(clip):
			continue
		var anim: Animation = library.get_animation(clip)
		if anim.has_meta("retargeted_from"):
			continue
		var source_path: String = clips[clip]
		if not sources.has(source_path):
			sources[source_path] = Retarget.source_skeleton(source_path)
		var source: Skeleton3D = sources[source_path]
		if source == null:
			push_warning("Retarget pass: no skeleton in %s; %s keeps its clip as it is" % [source_path, clip])
			continue
		var floor_before: float = _lowest_foot(skeleton, root, anim)
		var retargeted: Animation = Retarget.retarget(anim, source, skeleton, PackedStringArray(RETARGETED_BONES))
		var floor_after: float = _lowest_foot(skeleton, root, retargeted)
		if is_finite(floor_before) and is_finite(floor_after):
			var scale: float = (root.transform * _to_ancestor(skeleton, root)).basis.get_scale().y
			_shift_hips_y(retargeted, (floor_before - floor_after) / maxf(scale, 0.000001))
		retargeted.set_meta("retargeted_from", source_path)
		library.add_animation(clip, retargeted)
		done += 1
	root.free()
	if done > 0:
		if not _save_keeping_uid(library, library_path):
			push_error("Retarget pass: failed saving %s" % library_path)
			return 0
		print("Retargeted %d clips in %s" % [done, library_path])
	return done


## Saves `library` over `path` with the uid the file already carries. A headless run
## without an import first has no uid cache to take it from, and the save then writes the
## file without one - leaving every scene that references it by uid to fall back on the
## path, with a warning.
static func _save_keeping_uid(library: AnimationLibrary, path: String) -> bool:
	var header: String = FileAccess.get_file_as_string(path).get_slice("\n", 0)
	var uid_at: int = header.find("uid=\"")
	var uid: int = ResourceUID.INVALID_ID
	if uid_at >= 0:
		uid = ResourceUID.text_to_id(header.substr(uid_at + 5).get_slice("\"", 0))
	if ResourceSaver.save(library, path) != OK:
		return false
	return uid == ResourceUID.INVALID_ID or ResourceSaver.set_uid(path, uid) == OK


## The lowest either foot reaches over `anim`, in the frame `root` sits in. Posed by hand
## from the tracks: outside a scene tree an AnimationPlayer never writes to its skeleton.
static func _lowest_foot(skeleton: Skeleton3D, root: Node3D, anim: Animation) -> float:
	var feet: Array[int] = []
	for bone_name: String in FOOT_BONES:
		var bone: int = skeleton.find_bone(bone_name)
		if bone >= 0:
			feet.append(bone)
	if feet.is_empty():
		return INF
	var skeleton_to_root: Transform3D = root.transform * _to_ancestor(skeleton, root)
	var lowest: float = INF
	for i: int in GROUND_SAMPLES + 1:
		var globals: Array[Transform3D] = bone_globals(skeleton, anim, anim.length * float(i) / float(GROUND_SAMPLES))
		for bone: int in feet:
			lowest = minf(lowest, (skeleton_to_root * globals[bone]).origin.y)
	return lowest


## Every bone's skeleton-space transform under `anim` at `time`: a track's value where the
## clip has one, the rest where it does not - what playing it would give.
static func bone_globals(skeleton: Skeleton3D, anim: Animation, time: float) -> Array[Transform3D]:
	var rotations: Dictionary = {}
	var positions: Dictionary = {}
	for track: int in anim.get_track_count():
		var path: NodePath = anim.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone: int = skeleton.find_bone(String(path.get_subname(0)))
		if bone < 0:
			continue
		match anim.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				rotations[bone] = anim.rotation_track_interpolate(track, time)
			Animation.TYPE_POSITION_3D:
				positions[bone] = anim.position_track_interpolate(track, time)
	var out: Array[Transform3D] = []
	out.resize(skeleton.get_bone_count())
	for bone: int in Retarget._parent_first(skeleton):
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		var local := Transform3D(
			Basis(rotations.get(bone, rest.basis.get_rotation_quaternion())).scaled(rest.basis.get_scale()),
			positions.get(bone, rest.origin))
		var parent: int = skeleton.get_bone_parent(bone)
		out[bone] = out[parent] * local if parent >= 0 else local
	return out


static func _shift_hips_y(anim: Animation, delta: float) -> void:
	for track: int in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(anim.track_get_path(track)).ends_with(":mixamorig_Hips"):
			continue
		for key: int in anim.track_get_key_count(track):
			anim.track_set_key_value(track, key, (anim.track_get_key_value(track, key) as Vector3) + Vector3(0.0, delta, 0.0))
		return


static func _to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			chain.append(current as Node3D)
		current = current.get_parent()
	chain.reverse()
	var out := Transform3D.IDENTITY
	for item: Node3D in chain:
		out = out * item.transform
	return out
