extends RefCounted
## Gives every built character its "run" and "idle" clips and the stride measurement on both
## of its locomotion clips. Preloaded by path, never by class_name (see tools/animation_impact.gd).
##
## A SEPARATE PASS over the finished libraries, rather than a step inside
## CharacterBuilder._build_character, for two reasons - and the second is the load-bearing
## one:
##
##   1. It can run on its own. CharacterBuilder writes the character SCENES as well as the
##      libraries, and those scenes have been hand-corrected in the editor since they were
##      last generated (see .agents/learnings.md, 2026-08-23) - so the clip had to be
##      addable without a full rebuild, and this is the tool that did it.
##   2. Both measurements here drive an AnimationPlayer and read the pose back off a
##      Skeleton3D, which only works for a node that is actually IN the scene tree and on
##      a frame that has actually run. CharacterBuilder never adds its root to the tree and
##      its entry point works from SceneTree._init(), where no frame has happened yet;
##      measuring from in there reports every clip as covering zero ground. Rather than
##      restructure the builder around that, the measurement lives where the conditions
##      are right and the builder calls it afterwards.
##
## So tools/build_characters.gd runs build_all() and then this, and tools/add_run_clips.gd
## runs only this. Either way the numbers come from exactly one place.

const CharacterBuilder = preload("res://tools/character_builder.gd")
const AnimationStride = preload("res://tools/animation_stride.gd")


## Returns the number of libraries that FAILED, so a caller can set an exit code.
static func apply_all() -> int:
	var failed: int = 0
	for class_key: String in CharacterBuilder.CHARACTERS:
		var suffix: String = class_key.to_lower()
		for color: String in CharacterBuilder.CHARACTERS[class_key]:
			var config: Dictionary = CharacterBuilder.CHARACTERS[class_key][color]
			var race: String = CharacterBuilder.RACE_BY_COLOR[color]
			if not apply_to("%s_%s" % [race, suffix], suffix, config):
				failed += 1
	return failed


static func apply_to(output_name: String, class_suffix: String, config: Dictionary) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("LocomotionPass needs a SceneTree to pose characters in")
		return false

	var library_path: String = CharacterBuilder.ANIM_ROOT + "lib_%s.tres" % output_name
	var library: AnimationLibrary = ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if library == null:
		push_error("No animation library at %s" % library_path)
		return false

	var scene_path: String = CharacterBuilder.SCENE_DIR + class_suffix + "/%s.tscn" % output_name
	var packed: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if packed == null:
		push_error("No character scene at %s" % scene_path)
		return false
	# The BUILT character, not the raw fbx: grounding and stride both have to be measured
	# against the skeleton that will actually play the clip, at the scale it ships at.
	var root: Node3D = packed.instantiate()
	tree.get_root().add_child(root)
	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if anim_player == null or skeleton == null:
		push_error("%s has no AnimationPlayer/Skeleton3D" % scene_path)
		root.free()
		return false

	for clip_name: String in ["run", CharacterBuilder.IDLE_CLIP]:
		if not _add_looped_clip(library, clip_name, config, anim_player, root, skeleton):
			root.free()
			return false

	var strides: Dictionary = {}
	for clip_name: String in CharacterBuilder.LOCOMOTION_CLIPS:
		var source: String = CharacterBuilder._clip_source(config, clip_name)
		if source == "":
			continue
		strides[clip_name] = AnimationStride.annotate(
			library, clip_name, CharacterBuilder._extract_animation(source), anim_player, root, skeleton)

	root.free()
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Failed saving %s" % library_path)
		return false
	print("  %s  walk %.2f/s, run %.2f/s" % [
		library_path.get_file(), float(strides.get("walk", -1.0)), float(strides.get("run", -1.0))])
	return true


## Adds one looping clip from the set's source - "run", or "idle" for a character standing
## still (a raised ghoul with nothing to chase used to freeze on the first frame of its walk).
static func _add_looped_clip(library: AnimationLibrary, clip_name: String, config: Dictionary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> bool:
	var source: String = CharacterBuilder._clip_source(config, clip_name)
	if source == "":
		push_error("No %s source defined for set '%s'" % [clip_name, config["set"]])
		return false
	var raw: Animation = CharacterBuilder._extract_animation(source)
	if raw == null:
		push_error("Could not extract %s clip from %s" % [clip_name, source])
		return false

	# Same treatment, in the same order, that the builder gives every other clip: loop it,
	# pin the hips so the character does not walk off its own collision capsule, then drop
	# it onto this character's own ground plane.
	var clip: Animation = raw.duplicate(true)
	clip.loop_mode = Animation.LOOP_LINEAR
	CharacterBuilder._strip_horizontal_root_motion(clip, "mixamorig_Hips")
	var template := AnimationLibrary.new()
	template.add_animation(clip_name, clip)
	var grounded: AnimationLibrary = CharacterBuilder._ground_correct_library(template, anim_player, root, skeleton)
	# Idempotent: a re-run after a source swap should replace the clip, not error out.
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	library.add_animation(clip_name, grounded.get_animation(clip_name))
	return true
