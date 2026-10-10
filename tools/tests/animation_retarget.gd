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
## Then the same for the enemies, myrs and player (tools/retarget_pass.gd): their feet
## against each clip's own file, played on the skeleton inside it - exact for the feet,
## which is why the pass touches nothing else - and every other bone's keys exactly as the
## file has them, because the weapons in the character scenes were placed against those
## hands. A library rebuilt without the pass run after it fails here.
##
## Run with:  godot --headless --path . res://tools/tests/animation_retarget.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const Builder = preload("res://tools/boss_character_builder.gd")
const Retarget = preload("res://tools/animation_retarget.gd")
const RetargetPass = preload("res://tools/retarget_pass.gd")
const FEET := ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const TOLERANCE_DEGREES := 1.0
## The last stretch of a clip is left out of every comparison: past its last key a looping
## clip blends back toward its first, a one-shot does not, and the two read differently
## there for a reason that has nothing to do with retargeting.
const LOOP_SEAM := 0.15

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
	_check_pass()
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check_pass() -> void:
	var sources: Dictionary = {}
	var checked: int = 0
	for target: Array in RetargetPass.targets():
		var library: AnimationLibrary = load(target[0])
		var root: Node3D = (load(target[1]) as PackedScene).instantiate()
		var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
		var clips: Dictionary = target[2]
		for clip: String in clips:
			if not library.has_animation(clip):
				continue
			var name: String = "%s %s" % [String(target[0]).get_file().get_basename().trim_prefix("lib_"), clip]
			var anim: Animation = library.get_animation(clip)
			if not _check(name + " retargeted", anim.has_meta("retargeted_from"), "no retargeted_from - run tools/retarget_libraries.gd"):
				continue
			var source_path: String = clips[clip]
			if not sources.has(source_path):
				sources[source_path] = [_clip(source_path), Retarget.source_skeleton(source_path)]
			var original: Animation = sources[source_path][0]
			var worst_feet: float = _worst_foot_difference(original, sources[source_path][1], anim, skeleton)
			var worst_rest: float = _worst_other_difference(original, anim)
			checked += 1
			_check(name, worst_feet <= TOLERANCE_DEGREES and worst_rest <= TOLERANCE_DEGREES,
				"feet %.1f deg off the original, other bones %.1f" % [worst_feet, worst_rest])
		root.free()
	_check("there are character clips to check at all", checked > 0, "none found")


## The largest difference between the local rotation keys `a` and `b` give any bone that
## is not a foot - the retarget pass must leave them as they are.
func _worst_other_difference(a: Animation, b: Animation) -> float:
	var tracks: Dictionary = {}
	for track: int in b.get_track_count():
		if b.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			tracks[String(b.track_get_path(track).get_subname(0))] = track
	var worst: float = 0.0
	for track: int in a.get_track_count():
		if a.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone: String = String(a.track_get_path(track).get_subname(0))
		if FEET.has(bone) or not tracks.has(bone):
			continue
		var time: float = 0.0
		while time <= minf(a.length, b.length) - LOOP_SEAM:
			worst = maxf(worst, rad_to_deg(a.rotation_track_interpolate(track, time).angle_to(
				b.rotation_track_interpolate(tracks[bone], time))))
			time += 0.1
	return worst


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
	while time <= minf(a.length, b.length) - LOOP_SEAM:
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


func _check(what: String, ok: bool, detail: String) -> bool:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
	return ok
