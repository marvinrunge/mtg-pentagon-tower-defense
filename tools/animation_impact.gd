extends RefCounted
## Preloaded by path, never by a global class name: a headless `--script` build run
## does not rescan the project, so a newly added `class_name` is not in
## .godot/global_script_class_cache.cfg until an editor session picks it up, and the
## builders that use this would fail to compile on the very run that adds it.
##
## Finds the frame on which an attack clip actually CONNECTS, by watching how fast
## the striking limb is travelling.
##
## Every non-player attack in this project used to pay out on the frame the swing
## STARTED - the damage, and now the impact sound, had nothing in the animation to
## line up with, so a club landed while the weapon was still behind the enemy's
## head. The player already measures this (tools/player_character_builder.gd records
## `hit_ratios` on its attack clips); this module is that measurement made reusable,
## so the enemy and boss builders can record the same thing on their "attack" clips.
##
## Deliberately reports ONE moment per clip, unlike the player's `hit_ratios`: an
## enemy attack pays out a single hit, so a second measured peak would either be
## ignored or silently double the damage. The one reported is the loudest - the
## global speed peak - which needs no threshold to tune and cannot be thrown off by
## a recovery flourish the way "every local maximum above a cutoff" can.
##
## The measurement drives the real AnimationPlayer/Skeleton3D rather than reading a
## position track: a hand several joints down the chain takes almost all of its
## world motion from its parents, so its own track says nothing about where the
## weapon actually is.
##
## Metadata written by callers onto the clip:
##   hit_ratio  the moment of impact, as a fraction of the clip's own length

## The clip is walked at this rate - the builders' own resample rate, and roughly
## Mixamo's authored frame rate, so a peak is not an interpolation artefact.
const SAMPLE_FPS := 30.0

## Every character in this project strikes, shoots or throws with the weapon hand,
## so unlike the player - which has a real kick clip and a per-clip bone override -
## there is nothing here to choose between. Measured against all four limbs across
## the whole cast: the right hand carries the loudest peak in every attack clip.
const WEAPON_HAND_BONE := "mixamorig_RightHand"

## An impact is never placed right at the start or the end of the clip, whatever the
## measurement says. At the extremes there is no swing left to read it as, and a
## bounded value keeps a clip with no usable motion from degenerating.
const MIN_RATIO := 0.1
const MAX_RATIO := 0.9


## Records the measured `hit_ratio` on `clip_name` of `library`, and returns it
## (-1.0 when the library has no such clip).
##
## Sets and restores the mixer's callback mode itself. Stepping a clip by hand needs
## MANUAL - without it the mixer never applies the seeked pose and every sample
## reads the rest pose - while the builders' own grounding pass runs in the default
## mode, so the switch has to be scoped to this pass rather than left on.
static func annotate(library: AnimationLibrary, clip_name: String, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D) -> float:
	if not library.has_animation(clip_name):
		return -1.0
	var anim: Animation = library.get_animation(clip_name)
	var previous_mode := anim_player.callback_mode_process
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var ratio: float = measure(anim, skeleton, anim_player, root)
	anim_player.callback_mode_process = previous_mode
	anim.set_meta("hit_ratio", ratio)
	return ratio


## Where in `anim` the tracked limb moves fastest, as a fraction of the clip length.
## Returns 0.5 when nothing measurable happens, so a caller always has a usable
## moment and never needs a "no data" branch of its own.
static func measure(anim: Animation, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D, bone_name: String = WEAPON_HAND_BONE) -> float:
	if anim.length <= 0.0:
		return 0.5
	var samples: Array[Vector2] = sample_bone_speed(anim, skeleton, anim_player, root, bone_name)
	var peak_speed: float = 0.0
	var peak_time: float = -1.0
	for s in samples:
		if s.y > peak_speed:
			peak_speed = s.y
			peak_time = s.x
	if peak_time < 0.0:
		return 0.5
	return clampf(peak_time / anim.length, MIN_RATIO, MAX_RATIO)


## Speed of `bone_name` in root space, sampled across the whole clip. Returns
## [Vector2(time, speed), ...]. Exposed so a diagnostic run can show the whole
## profile rather than just the winning frame.
static func sample_bone_speed(anim: Animation, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D, bone_name: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx == -1 or anim.length <= 0.0:
		return out

	var skeleton_to_root: Transform3D = transform_to_ancestor(skeleton, root)
	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP := "__impact_measure__"
	temp_library.add_animation(TEMP_CLIP, anim)
	anim_player.add_animation_library("__impact__", temp_library)
	anim_player.play("__impact__/" + TEMP_CLIP)

	var step: float = 1.0 / SAMPLE_FPS
	var previous := Vector3.ZERO
	var have_previous := false
	var t: float = 0.0
	while t <= anim.length:
		apply_pose_at(anim_player, t)
		var pos: Vector3 = (skeleton_to_root * bone_global_pose(skeleton, bone_idx)).origin
		if have_previous:
			out.append(Vector2(t, pos.distance_to(previous) / step))
		previous = pos
		have_previous = true
		t += step

	anim_player.stop()
	anim_player.remove_animation_library("__impact__")
	return out


static func transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
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


## Steps the mixer to `time` and applies it. `seek(time, true)` alone leaves the
## mixer's own accumulator untouched in manual callback mode; the advance(0) is what
## actually writes the sampled values onto the skeleton's bone poses.
static func apply_pose_at(anim_player: AnimationPlayer, time: float) -> void:
	anim_player.seek(time, true)
	anim_player.advance(0.0)


## Composes a bone's global pose from the local poses the mixer just wrote.
##
## Skeleton3D.get_bone_global_pose() must NOT be used here: it reads a cache that is
## only recomputed when the skeleton processes a frame, and a build-time script
## driving the mixer by hand never gives it one - so it keeps returning the REST
## pose no matter where the clip is seeked to.
static func bone_global_pose(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	var current: int = bone_idx
	while current != -1:
		chain.append(current)
		current = skeleton.get_bone_parent(current)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_pose(b)
	return accum
