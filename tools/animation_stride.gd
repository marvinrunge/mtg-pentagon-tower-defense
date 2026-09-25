extends RefCounted
## Preloaded by path, never by a global class name - same reason as
## tools/animation_impact.gd: a headless `--script` build run does not rescan the project,
## so a `class_name` added in the same commit is not in the global class cache yet and
## every builder that used it would fail to compile on the very run that adds it.
##
## Measures how fast a locomotion clip actually carries a character across the ground, so
## the game can play it back at the rate the character is really moving instead of letting
## the feet slide.
##
## The problem this exists for, measured across the cast: a Melee enemy moves at 2.5 units
## per second while its walk cycle only covers 1.04, so it skates along at nearly two and a
## half times its own stride. Black's Ranged was the worst - a shambling 0.38-unit zombie
## walk under an enemy travelling at 2.0, a 5.3x slide.
##
## MEASURED, not tabulated. Every clip in this project is borrowed across rigs and then
## height-normalised to TARGET_HEIGHT, so a number written down per animation set would be
## wrong for any character whose mesh normalised differently, and silently wrong again the
## next time a clip is swapped. The measurement is taken on the character that will
## actually play it.
##
## Must be given the RAW clip, before CharacterBuilder._strip_horizontal_root_motion has
## flattened the hips track - stripping is exactly what removes the travel this measures.
## The clip stored in the library is still the stripped one; only the number comes from the
## raw version.
##
## Metadata written by callers onto the clip:
##   stride_speed  ground distance covered per second of clip at playback speed 1.0, in
##                 world units, on this character's own normalised skeleton
##   stride_scale  the uniform root scale the measurement was taken at
##
## Both, because the two are only meaningful together. The builder normalises a character
## to a root scale of 85 (1.7 units tall), but EnemyBase instantiates the visual and
## OVERWRITES that with 100 - so an enemy in the game is 1.18x the size the clip was
## measured on, and covers 1.18x the ground per stride. Recording the measurement scale
## lets the reader rescale instead of hardcoding today's ratio between two numbers that
## live in different files and have already drifted apart once.

## The hips carry the whole body's travel; every rig in this project is Mixamo.
const ROOT_BONE := "mixamorig_Hips"

## Samples per clip. The clips are 0.7-1.3s at roughly 30fps, so this is a little over one
## sample per authored frame - enough that the path length below is not chasing
## interpolation noise, cheap enough to run for the whole cast in one pass.
const SAMPLE_STEPS := 60


## Ground speed of `raw_anim` in world units per second, or -1.0 if it cannot be measured.
##
## Summed as a PATH LENGTH rather than first-key-to-last-key. A walk cycle is authored to
## loop, so its last frame nearly coincides with its first on every axis the loop closes -
## measuring endpoint to endpoint reports a character sprinting on the spot as standing
## still. The path length is also what the eye reads as "how far the feet went".
static func measure(raw_anim: Animation, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> float:
	if raw_anim == null or raw_anim.length <= 0.0 or anim_player == null or skeleton == null:
		return -1.0
	var hips: int = skeleton.find_bone(ROOT_BONE)
	if hips == -1:
		return -1.0

	var library := AnimationLibrary.new()
	const TEMP_CLIP := "__stride_measure__"
	library.add_animation(TEMP_CLIP, raw_anim)
	anim_player.add_animation_library("__stride__", library)
	anim_player.play("__stride__/" + TEMP_CLIP)

	# Driven through the real AnimationPlayer and read back off the posed skeleton rather
	# than read off the position track, for the same reason animation_impact.gd does it:
	# a bone's own track is expressed in its parent's space and says nothing about where
	# it ends up in the world once the rig's own scaling is applied.
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var travel: float = 0.0
	var previous := Vector3.INF
	for i: int in range(SAMPLE_STEPS + 1):
		anim_player.seek(raw_anim.length * float(i) / float(SAMPLE_STEPS), true)
		var pose: Transform3D = root.transform * skeleton_to_root * skeleton.get_bone_global_pose(hips)
		var flat := Vector3(pose.origin.x, 0.0, pose.origin.z)
		if previous != Vector3.INF:
			travel += flat.distance_to(previous)
		previous = flat

	anim_player.stop()
	anim_player.remove_animation_library("__stride__")
	return travel / raw_anim.length


## Measures `raw_anim` and records the result on the library's own (already stripped and
## ground-corrected) copy of that clip. Returns the measured speed, or -1.0.
static func annotate(library: AnimationLibrary, clip_name: String, raw_anim: Animation, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> float:
	if library == null or not library.has_animation(clip_name):
		return -1.0
	var speed: float = measure(raw_anim, anim_player, root, skeleton)
	if speed <= 0.0:
		push_warning("Could not measure stride speed for clip '%s'" % clip_name)
		return -1.0
	var clip: Animation = library.get_animation(clip_name)
	clip.set_meta("stride_speed", speed)
	clip.set_meta("stride_scale", root.transform.basis.get_scale().y)
	return speed


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != ancestor:
		combined = current.transform * combined
		current = current.get_parent() as Node3D
	return combined
