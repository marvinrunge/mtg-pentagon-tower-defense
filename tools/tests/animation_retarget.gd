extends Node
## Regression test: do the bosses' borrowed clips move their feet the way the clips were
## made to?
##
## Every clip in a saved boss library (assets/animations/boss/lib_<boss>.tres) is checked
## against the source file it came from, played on the skeleton of the boss it was
## downloaded for (BossCharacterBuilder.CLIP_MADE_FOR). What has to match is the motion the
## MESH makes - each foot and toe bone's rotation away from its own rest - because that is
## what a raw copy got wrong: the borrowing bosses' feet came out 22-41 degrees off. A clip
## made for the boss playing it has to come through unchanged.
##
## Run with:  godot --headless --path . res://tools/tests/animation_retarget.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const Builder = preload("res://tools/boss_character_builder.gd")
const Retarget = preload("res://tools/animation_retarget.gd")
const FEET := ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const TOLERANCE_DEGREES := 1.0

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeletons: Dictionary = {}
	for boss: String in Builder.BOSSES:
		skeletons[boss] = Retarget.source_skeleton(Builder.BOSSES[boss]["mesh"])
	var borrowed: int = 0
	for boss: String in Builder.BOSSES:
		var library: AnimationLibrary = load(Builder.LIBRARY_DIR + "lib_%s.tres" % boss)
		var clips: Dictionary = Builder.ANIM_SETS[Builder.BOSSES[boss]["set"]]
		for clip: String in clips:
			var source_path: String = clips[clip]
			var made_for: String = Builder._made_for(source_path)
			if made_for == "" or not library.has_animation(clip):
				continue
			var original: Animation = _clip(source_path)
			var worst: float = _worst_foot_difference(original, skeletons[made_for], library.get_animation(clip), skeletons[boss])
			var own: bool = made_for == boss
			if not own:
				borrowed += 1
			_check("%s %s (%s)" % [boss, clip, "own" if own else "made for " + made_for],
				worst <= TOLERANCE_DEGREES, "feet %.1f deg off the original" % worst)
	_check("there are borrowed clips to check at all", borrowed > 0, "none found")
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _clip(path: String) -> Animation:
	var root: Node = (load(path) as PackedScene).instantiate()
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var anim: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	root.free()
	return anim


## The largest difference, over the clip, between how each foot bone turns away from its
## rest on `a_skeleton` playing `a` and on `b_skeleton` playing `b`.
func _worst_foot_difference(a: Animation, a_skeleton: Skeleton3D, b: Animation, b_skeleton: Skeleton3D) -> float:
	var worst: float = 0.0
	var time: float = 0.0
	while time <= minf(a.length, b.length):
		var da: Dictionary = _deltas(a, a_skeleton, time)
		var db: Dictionary = _deltas(b, b_skeleton, time)
		for bone: String in FEET:
			if da.has(bone) and db.has(bone):
				worst = maxf(worst, rad_to_deg((da[bone] as Quaternion).angle_to(db[bone])))
		time += 0.1
	return worst


func _deltas(anim: Animation, skeleton: Skeleton3D, time: float) -> Dictionary:
	var local: Dictionary = {}
	for track: int in anim.get_track_count():
		if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			local[String(anim.track_get_path(track).get_subname(0))] = anim.rotation_track_interpolate(track, time)
	var order: Array[int] = Retarget._parent_first(skeleton)
	var rests: Array[Quaternion] = Retarget._global_rests(skeleton, order)
	var globals: Dictionary = {}
	var out: Dictionary = {}
	for bone: int in order:
		var name: String = skeleton.get_bone_name(bone)
		var rotation: Quaternion = local.get(name, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		var parent: int = skeleton.get_bone_parent(bone)
		globals[bone] = (globals[parent] as Quaternion) * rotation if parent >= 0 else rotation
		out[name] = (globals[bone] as Quaternion) * rests[bone].inverse()
	return out


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
