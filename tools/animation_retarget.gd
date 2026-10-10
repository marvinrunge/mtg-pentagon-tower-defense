class_name AnimationRetarget
extends RefCounted
## Moves a Mixamo clip from the skeleton it was downloaded for onto another Mixamo skeleton.
##
## Why it is needed: a Mixamo clip stores each bone's ABSOLUTE local rotation, which only
## means the intended pose on the skeleton it was exported with. Mixamo's auto-rigger lays
## the bones out afresh for every model it rigs - the foot bone runs from ankle to the ball
## of THAT model's foot - so the same names carry different rest orientations from one rig
## to the next. Copied by bone name onto another rig, a clip keeps the first rig's rest
## built into every key, and the second rig's feet came out pitched by the difference: 25-38
## degrees on the bosses that borrowed each other's clips (measured against the skeletons
## inside the "without skin" downloads).
##
## What carries over instead is each bone's motion RELATIVE TO ITS REST, taken in skeleton
## space, where both rigs agree on up and forward:
##
##     delta  = source_global(t) * source_global_rest^-1
##     target_global(t) = delta * target_global_rest
##     target_local(t)  = target_parent_global(t)^-1 * target_global(t)
##
## On the skeleton the clip was made for this gives back the clip itself (delta applied to
## the very rest it was taken from), so running every clip through it is safe whether or not
## it was borrowed.
##
## Only rotation tracks are rewritten. Position and scale tracks pass through untouched - on
## these rigs that is the Hips position track alone, which the builders already strip and
## ground per character.

## Keys are rebuilt by sampling at this rate: every bone has to be evaluated at the same
## moments for the parent chain to compose, and Mixamo itself exports at 30.
const SAMPLE_FPS := 30.0


## A copy of `anim` (made for `source`) whose rotation tracks pose `target` the same way.
## Bones `target` does not have are dropped; bones only `target` has keep their rest.
static func retarget(anim: Animation, source: Skeleton3D, target: Skeleton3D) -> Animation:
	var out: Animation = anim.duplicate(true)
	# Rotation tracks by bone name, from the clip.
	var tracks: Dictionary = {}
	for track: int in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path: NodePath = anim.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		tracks[String(path.get_subname(0))] = track
	if tracks.is_empty():
		return out

	var source_order: Array[int] = _parent_first(source)
	var target_order: Array[int] = _parent_first(target)
	var source_rest_global: Array[Quaternion] = _global_rests(source, source_order)
	var target_rest_global: Array[Quaternion] = _global_rests(target, target_order)

	var frames: int = maxi(int(ceil(anim.length * SAMPLE_FPS)), 1)
	# bone name -> Array of [time, local rotation] for the target.
	var keys: Dictionary = {}
	for name: String in tracks:
		if target.find_bone(name) >= 0 and source.find_bone(name) >= 0:
			keys[name] = []

	var source_global: Array[Quaternion] = []
	source_global.resize(source.get_bone_count())
	var target_global: Array[Quaternion] = []
	target_global.resize(target.get_bone_count())
	for frame: int in frames + 1:
		var time: float = minf(float(frame) / SAMPLE_FPS, anim.length)
		for bone: int in source_order:
			var name: String = source.get_bone_name(bone)
			var local: Quaternion
			if tracks.has(name):
				local = anim.rotation_track_interpolate(tracks[name], time)
			else:
				local = source.get_bone_rest(bone).basis.get_rotation_quaternion()
			var parent: int = source.get_bone_parent(bone)
			source_global[bone] = (source_global[parent] * local).normalized() if parent >= 0 else local.normalized()
		for bone: int in target_order:
			var name: String = target.get_bone_name(bone)
			var parent: int = target.get_bone_parent(bone)
			var parent_global: Quaternion = target_global[parent] if parent >= 0 else Quaternion.IDENTITY
			var source_bone: int = source.find_bone(name)
			if keys.has(name):
				var delta: Quaternion = source_global[source_bone] * source_rest_global[source_bone].inverse()
				target_global[bone] = (delta * target_rest_global[bone]).normalized()
				(keys[name] as Array).append([time, (parent_global.inverse() * target_global[bone]).normalized()])
			else:
				# No track on this bone: at runtime it holds its rest, so it does here too.
				target_global[bone] = (parent_global * target.get_bone_rest(bone).basis.get_rotation_quaternion()).normalized()

	# Swap the rotation tracks for the rebuilt ones, dropping bones the target lacks.
	for track: int in range(out.get_track_count() - 1, -1, -1):
		if out.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path: NodePath = out.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var name: String = String(path.get_subname(0))
		if not keys.has(name):
			out.remove_track(track)
			continue
		for key: int in range(out.track_get_key_count(track) - 1, -1, -1):
			out.track_remove_key(track, key)
		for sample: Array in keys[name]:
			out.rotation_track_insert_key(track, sample[0], sample[1])
	return out


## The skeleton the clip in `fbx_path` was exported with - the "without skin" downloads
## still carry it. Null if the file has none.
static func source_skeleton(fbx_path: String) -> Skeleton3D:
	var scene: PackedScene = ResourceLoader.load(fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		root.free()
		return null
	# Detached and kept on its own: only its bone data is read.
	skeleton.get_parent().remove_child(skeleton)
	skeleton.owner = null
	root.free()
	return skeleton


## How far the clip's rest and the target's disagree on one bone, in degrees, by name.
## For a report - the bigger it is, the more a raw copy would have bent that bone.
static func rest_mismatch_degrees(source: Skeleton3D, target: Skeleton3D, bone_name: String) -> float:
	var s: int = source.find_bone(bone_name)
	var t: int = target.find_bone(bone_name)
	if s < 0 or t < 0:
		return 0.0
	return rad_to_deg(source.get_bone_rest(s).basis.get_rotation_quaternion().angle_to(
		target.get_bone_rest(t).basis.get_rotation_quaternion()))


static func _parent_first(skeleton: Skeleton3D) -> Array[int]:
	var order: Array[int] = []
	var stack: Array[int] = []
	for bone: int in skeleton.get_bone_count():
		if skeleton.get_bone_parent(bone) < 0:
			stack.append(bone)
	while not stack.is_empty():
		var bone: int = stack.pop_back()
		order.append(bone)
		for child: int in skeleton.get_bone_children(bone):
			stack.append(child)
	return order


static func _global_rests(skeleton: Skeleton3D, order: Array[int]) -> Array[Quaternion]:
	var rests: Array[Quaternion] = []
	rests.resize(skeleton.get_bone_count())
	for bone: int in order:
		var local: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var parent: int = skeleton.get_bone_parent(bone)
		rests[bone] = (rests[parent] * local).normalized() if parent >= 0 else local.normalized()
	return rests
