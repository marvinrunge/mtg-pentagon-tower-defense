extends RefCounted
## Re-imports ONE clip into an already-built character's animation library, leaving the
## character's .tscn completely alone. Preloaded by path, never by class_name (see
## tools/animation_impact.gd).
##
## For when a source clip in CharacterBuilder.CLIP_SETS is swapped for a better one and
## the only thing that needs to change is the clip. A full rebuild would do it too, and
## would also regenerate the scene - discarding any hand adjustment made in the editor,
## which is how a set of tuned weapon rotations was lost once already. `lib_<x>.tres` is a
## separate resource that the scene merely REFERENCES, so replacing a clip inside it
## reaches the game without rewriting a single scene.
##
## The scene is still read, because grounding has to be measured against the skeleton that
## will actually play the clip - read, never written.

const CharacterBuilder = preload("res://tools/character_builder.gd")


## Returns the number that FAILED.
static func apply_all(clip_name: String, model_keys: Array) -> int:
	var failed: int = 0
	for key: String in model_keys:
		var parts: PackedStringArray = key.split("/")
		if parts.size() != 2 or not apply_to(parts[0], parts[1], clip_name):
			failed += 1
	return failed


static func apply_to(class_key: String, color: String, clip_name: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("ReclipPass needs a SceneTree to ground clips against")
		return false
	var config: Dictionary = CharacterBuilder.CHARACTERS[class_key][color]
	var race: String = CharacterBuilder.RACE_BY_COLOR[color]
	var suffix: String = class_key.to_lower()
	var output_name: String = "%s_%s" % [race, suffix]

	var library_path: String = CharacterBuilder.ANIM_ROOT + "lib_%s.tres" % output_name
	var library: AnimationLibrary = ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if library == null:
		push_error("No animation library at %s" % library_path)
		return false
	var source: String = CharacterBuilder._clip_source(config, clip_name)
	if source == "":
		push_error("Set '%s' defines no '%s' clip" % [config["set"], clip_name])
		return false
	var raw: Animation = CharacterBuilder._extract_animation(source)
	if raw == null:
		push_error("Could not extract '%s' from %s" % [clip_name, source])
		return false

	var scene_path: String = CharacterBuilder.SCENE_DIR + suffix + "/%s.tscn" % output_name
	var packed: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if packed == null:
		push_error("No character scene at %s" % scene_path)
		return false
	# READ ONLY. Instantiated purely so the clip can be grounded against this character's
	# own skeleton; nothing here writes the scene back.
	var root: Node3D = packed.instantiate()
	tree.get_root().add_child(root)
	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if anim_player == null or skeleton == null:
		push_error("%s has no AnimationPlayer/Skeleton3D" % scene_path)
		root.free()
		return false

	# Exactly the treatment _build_template_library + _ground_correct_library give it.
	var clip: Animation = raw.duplicate(true)
	clip.loop_mode = Animation.LOOP_LINEAR if clip_name in CharacterBuilder.LOCOMOTION_CLIPS else Animation.LOOP_NONE
	CharacterBuilder._strip_horizontal_root_motion(clip, "mixamorig_Hips")
	var template := AnimationLibrary.new()
	template.add_animation(clip_name, clip)
	var grounded: AnimationLibrary = CharacterBuilder._ground_correct_library(template, anim_player, root, skeleton)
	root.free()

	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	library.add_animation(clip_name, grounded.get_animation(clip_name))
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Failed saving %s" % library_path)
		return false
	print("  %s: '%s' <- %s (%.2fs)" % [library_path.get_file(), clip_name, source.get_file(), clip.length])
	return true
