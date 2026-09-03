class_name PlayerCharacterBuilder
extends RefCounted
## Builds the player's animated visual (res://scenes/misc/player_visual.tscn) and its
## animation library (res://assets/animations/player/lib_player.tres) from the Mixamo
## set under assets/player/.
##
## Structurally the same problem tools/character_builder.gd solves for enemies, with
## three differences that are specific to this character and worth stating up front:
##
##  1. This rig is ALREADY at metric scale (~1.905 units head-to-toe), unlike every
##     enemy mesh in this project (~0.02 units, blown up 85-100x). The root scale
##     correction below is therefore ~1.0 and exists only to land exactly on the
##     player's 1.9-tall capsule, not to rescue a tiny import.
##  2. The rigged mesh fbx carries texture *references* but no image data at all, so
##     its PBR maps come from a separate, later Meshy export of the same model
##     (TEXTURE_BASE). _build_material() documents why mixing the two is safe.
##  3. Attack clips are 2.3-4.7s of Mixamo wind-up/recovery against a 0.5s attack
##     cadence. _measure_action_window() records which slice of each is the actual
##     strike, plus the moments of impact, as clip METADATA - the clips themselves are
##     stored whole, and PlayerAnimator plays the window via a custom timeline. The
##     library therefore holds the animations exactly as downloaded.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_player_character.gd
##
## Deadlocks if an editor already holds the project lock; while the editor is open,
## call PlayerCharacterBuilder.build() through Godot MCP's execute_editor_script
## (see tools/character_builder.gd's header for the caching caveat that applies
## to repeated in-editor runs).

const PLAYER_ROOT := "res://assets/player/"
const ANIM_OUT_DIR := "res://assets/animations/player/"
const LIBRARY_PATH := ANIM_OUT_DIR + "lib_player.tres"
const OUTPUT_SCENE := "res://scenes/misc/player_visual.tscn"
const WEAPON_GLB := "res://assets/weapons/player/player_weapon.glb"

const MESH_FBX := PLAYER_ROOT + "Meshy_AI_Orc_Warrior_in_Fur_Ar_0829200310_texture.fbx"
## PBR maps live under a different Meshy export id than the rigged mesh - see
## _build_material() for why that is safe. Suffixes: "" (albedo), "_normal",
## "_metallic", "_roughness".
const TEXTURE_BASE := PLAYER_ROOT + "Meshy_AI_Orc_Warrior_in_Fur_Ar_0830103939_texture"

## Matches the 1.9-tall CapsuleShape3D in scenes/misc/player.tscn.
const TARGET_HEIGHT := 1.9

## These Mixamo rigs face +Z: "standing walk forward" carries its hips from
## z = -0.006 to z = +1.318, and a render from the +Z side shows the character's
## face. Godot's forward is -Z, so without this the player moonwalks and stares
## into the camera parked behind them.
##
## The correction goes on the VISUAL, not on the player's forward convention. The
## enemies solve the same mismatch the other way - `EnemyBase` turns with
## `atan2(dir.x, dir.z)` and documents "+Z is forward for these enemies" - but that
## option isn't open here: `Player` is a CharacterBody3D yawed by mouse look, and
## its -Z forward is already baked into the camera rig, the melee cone, the block
## cone and knockback. Rotating the mesh is the one change that touches nothing else.
const FACING_CORRECTION_DEGREES := 180.0

const HIPS_BONE := "mixamorig_Hips"
const WEAPON_HAND_BONE := "mixamorig_RightHand"
const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const HEIGHT_TOP_BONE := "mixamorig_HeadTop_End"
const HEIGHT_BOTTOM_BONE := "mixamorig_LeftToe_End"

const GROUND_SAMPLE_COUNT := 20
## Trimmed clips are rebuilt by resampling rather than by copying keys, so the
## boundaries land exactly on t0/t1 instead of on the nearest original key.
const RESAMPLE_FPS := 30.0

## Trim policy per clip.
enum Trim {
	NONE,   ## keep the clip whole (locomotion, idles, reactions)
	SWING,  ## one strike: keep a tight window centred on the moment of impact
	SPAN,   ## multi-hit flourish: keep the whole stretch where the limb is working
}

## Fraction of peak limb speed that counts as "the limb is working".
const SWING_SPEED_THRESHOLD := 0.30
## SWING grows outward from the impact frame until the limb has actually settled -
## a fixed window cut some clips while they were still swinging hard (the kick ended
## at 41% of peak speed, cast_black at 42%), which is what a "cut off" animation is.
## It stops at the limits so a strike still fits a 0.5s cadence: a Mixamo swing
## spends most of its runtime drifting back to neutral, and keeping the whole
## above-threshold span (1.9-2.3s measured) would be far too long.
const SWING_SETTLED_FRACTION := 0.25
const SWING_PRE_IMPACT_MAX := 0.60
const SWING_POST_IMPACT_MAX := 0.60
## Never cut closer than this to the impact, however fast the limb is moving there.
const SWING_PRE_IMPACT_MIN := 0.30
const SWING_POST_IMPACT_MIN := 0.30
## SPAN keeps a little breathing room either side so the flourish doesn't pop.
const SPAN_LEAD_IN := 0.12
const SPAN_LEAD_OUT := 0.20
## Clips whose RECOVERY is part of the move rather than dead tail, and so must not be
## trimmed off. A jump attack is the case that needs it: the default lead-out ends the
## window 0.20s after the axe stops moving, which is mid-crouch on the landing, and the
## character then snaps back to idle without ever standing up. Generous values are
## fine - the window is clamped to the clip's own length.
const SPAN_LEAD_OUT_OVERRIDE := {
	"jump_attack": 2.5,
}
## Two impacts closer together than this are the same strike, not two hits.
const MIN_HIT_SEPARATION := 0.18

## clip name -> [source fbx (relative to PLAYER_ROOT), loop, trim policy].
## Deliberately excludes the unarmed/* and crouch* sets - the player is always
## armed, per the 2026-08-30 instruction.
const CLIPS := {
	# --- locomotion ---
	"idle": ["standing idle.fbx", true, Trim.NONE],
	"idle_look_1": ["standing idle looking ver. 1.fbx", false, Trim.NONE],
	"idle_look_2": ["standing idle looking ver. 2.fbx", false, Trim.NONE],
	"walk_forward": ["standing walk forward.fbx", true, Trim.NONE],
	"walk_back": ["standing walk back.fbx", true, Trim.NONE],
	"walk_left": ["standing walk left.fbx", true, Trim.NONE],
	"walk_right": ["standing walk right.fbx", true, Trim.NONE],
	"run_forward": ["standing run forward.fbx", true, Trim.NONE],
	"run_back": ["standing run back.fbx", true, Trim.NONE],
	"jump": ["standing jump.fbx", false, Trim.NONE],
	# --- attacks (trimmed to the swing) ---
	# The player has exactly two melee moves. The light attack is the combo_3
	# flourish spent one stage per click, and the heavy attack is the 360 spin; the
	# single-swing clips that used to back them are gone along with the old
	# three-press finisher system. combo_2 is the same idea in three stages and is
	# bought in the skill tree.
	"combo_2": ["standing melee combo attack ver. 2.fbx", false, Trim.SPAN],
	"combo_3": ["standing melee combo attack ver. 3.fbx", false, Trim.SPAN],
	"spin_high": ["standing melee attack 360 high.fbx", false, Trim.SPAN],
	"kick": ["standing melee attack kick ver. 1.fbx", false, Trim.SWING],
	# The green ability: a running leap that ends in a ground slam. SPAN rather than
	# SWING because the leap is the point - trimming to the impact alone would keep
	# the slam and throw the jump away.
	"jump_attack": ["standing melee run jump attack.fbx", false, Trim.SPAN],
	# Spell clips: a plain sword chop for the two short physical strikes (Act of
	# Treason, Rabid Bite). Named for the pose, not for a melee move - no melee move
	# uses it.
	"strike_downward": ["standing melee attack downward.fbx", false, Trim.SWING],
	# --- defence & reactions ---
	"block_idle": ["standing block idle.fbx", true, Trim.NONE],
	"block_react": ["standing block react large.fbx", false, Trim.NONE],
	"hit_left": ["standing react large from left.fbx", false, Trim.NONE],
	"hit_right": ["standing react large from right.fbx", false, Trim.NONE],
	"hit_gut": ["standing react large gut.fbx", false, Trim.NONE],
	# Big self-buff / ultimate casts borrow this rather than a spellcasting pose.
	"taunt_battlecry": ["standing taunt battlecry.fbx", false, Trim.SPAN],
}

## Clips the player borrows from the ENEMY rig (57 bones, ~96x smaller), because the
## standing pack has no equivalent: it ships no death animation and no spellcasting
## at all. _adopt_foreign_clip() rescales the hips track and drops anything this rig
## cannot use; rotation tracks transfer by bone name as usual.
##
## The five mage casts adopt more cleanly than the death clip does - every one of
## this rig's 33 bones exists in the source, and each carries exactly ONE position
## track, on Hips, so nothing has to be dropped at all.
##
## clip name -> [source fbx, loop, trim policy]
const FOREIGN_CLIPS := {
	"death": ["res://assets/animations/character/common/death_fallback.fbx", false, Trim.NONE],
	"cast_white": [ANIM_ROOT_SHARED + "mage/attack_white.fbx", false, Trim.SWING],
	"cast_blue": [ANIM_ROOT_SHARED + "mage/attack_blue.fbx", false, Trim.SWING],
	"cast_black": [ANIM_ROOT_SHARED + "mage/attack_black.fbx", false, Trim.SWING],
	"cast_red": [ANIM_ROOT_SHARED + "mage/attack_red.fbx", false, Trim.SWING],
	"cast_green": [ANIM_ROOT_SHARED + "mage/attack_green.fbx", false, Trim.SWING],
}

const ANIM_ROOT_SHARED := "res://assets/animations/character/"

## Kick lands with the foot, not the weapon hand - measuring hand speed would pick
## the wrong frame for it.
const SWING_TRACKING_BONE := {
	"kick": "mixamorig_RightToeBase",
}


static func build() -> bool:
	var base_scene: PackedScene = ResourceLoader.load(MESH_FBX, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load player mesh %s" % MESH_FBX)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = "PlayerVisual"

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if anim_player == null or skeleton == null or mesh_node == null:
		push_error("Player mesh is missing an AnimationPlayer, Skeleton3D or MeshInstance3D")
		return false

	(mesh_node.mesh as ArrayMesh).surface_set_material(0, _build_material())

	# Scale/lift must be set BEFORE grounding: the correction is measured in this
	# same (post-normalization) coordinate frame.
	_normalize_to_target_height(root, skeleton)

	# Both measurement passes below step the clip by hand rather than by letting a
	# frame elapse, so the mixer must not also be advancing itself. Restored before
	# packing so the shipped scene keeps the importer's own callback mode.
	var original_callback_mode := anim_player.callback_mode_process
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var template := _build_template_library(skeleton, anim_player, root)
	if template == null:
		return false

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var library := _ground_correct_library(template, anim_player, root, skeleton)
	anim_player.callback_mode_process = original_callback_mode

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ANIM_OUT_DIR))
	if ResourceSaver.save(library, LIBRARY_PATH) != OK:
		push_error("Failed saving %s" % LIBRARY_PATH)
		return false
	anim_player.add_animation_library("", ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists.
	anim_player.autoplay = "idle"

	_attach_weapon(skeleton)
	_own_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("PackedScene.pack failed for the player visual")
		return false
	if ResourceSaver.save(packed, OUTPUT_SCENE) != OK:
		push_error("ResourceSaver.save failed for %s" % OUTPUT_SCENE)
		return false

	print("Saved ", OUTPUT_SCENE, " with ", library.get_animation_list().size(), " clips.")
	root.queue_free()
	return true


static func _build_template_library(skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in CLIPS.keys():
		var spec: Array = CLIPS[clip_name]
		var anim := _extract_animation(PLAYER_ROOT + spec[0])
		if anim == null:
			push_error("Could not extract clip '%s' from %s" % [clip_name, spec[0]])
			return null
		# Measured BEFORE the root motion is stripped - afterwards there is nothing
		# left to measure, and the animator needs it to match stride to real speed.
		if spec[1]:
			anim.set_meta("travel_speed", _measure_travel_speed(anim))
		_strip_horizontal_root_motion(anim, HIPS_BONE)
		if spec[2] != Trim.NONE:
			_measure_action_window(anim, clip_name, spec[2], skeleton, anim_player, root)
		anim.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		library.add_animation(clip_name, anim)

	for clip_name in FOREIGN_CLIPS.keys():
		var spec: Array = FOREIGN_CLIPS[clip_name]
		var adopted := _adopt_foreign_clip(spec[0], skeleton, clip_name)
		if adopted == null:
			push_warning("Could not adopt '%s' from %s" % [clip_name, spec[0]])
			continue
		if spec[2] != Trim.NONE:
			_measure_action_window(adopted, clip_name, spec[2], skeleton, anim_player, root)
		adopted.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		library.add_animation(clip_name, adopted)
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


## Ported from tools/character_builder.gd - movement is driven by the CharacterBody3D,
## so the clip must not also walk the character across the floor.
static func _strip_horizontal_root_motion(anim: Animation, bone_name: String) -> void:
	var track_idx := _find_position_track(anim, bone_name)
	if track_idx == -1:
		return
	var key_count := anim.track_get_key_count(track_idx)
	if key_count == 0:
		return
	var base_value: Vector3 = anim.track_get_key_value(track_idx, 0)
	for key_idx in key_count:
		var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
		anim.track_set_key_value(track_idx, key_idx, Vector3(base_value.x, value.y, base_value.z))


## How fast the clip's own root motion carries the character along the floor, in
## units/second. Locomotion is driven by the CharacterBody3D, so this is what the
## animator divides real velocity by to pick a playback speed that keeps the feet
## planted instead of skating.
static func _measure_travel_speed(anim: Animation) -> float:
	var track_idx := _find_position_track(anim, HIPS_BONE)
	if track_idx == -1 or anim.length <= 0.0:
		return 0.0
	var key_count := anim.track_get_key_count(track_idx)
	if key_count < 2:
		return 0.0
	var first: Vector3 = anim.track_get_key_value(track_idx, 0)
	var last: Vector3 = anim.track_get_key_value(track_idx, key_count - 1)
	return Vector2(last.x - first.x, last.z - first.z).length() / anim.length


static func _find_position_track(anim: Animation, bone_name: String) -> int:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			return track_idx
	return -1


# --- swing trimming -----------------------------------------------------------

## Works out which part of a Mixamo clip is actually the strike - these ship with
## long neutral-stance lead-ins and recoveries that are unusable at a 0.5s cadence -
## and records it as metadata. It does NOT cut the clip up.
##
## That distinction matters: an earlier version sliced the animation down to the
## window, which meant the saved library contained truncated animations. Opening the
## scene showed 0.63s stumps instead of the 2.40s clips that were downloaded, and
## changing your mind about the window meant a rebuild. The full animation is stored
## and `PlayerAnimator` plays the window through AnimationNodeAnimation's custom
## timeline (start_offset + timeline_length) instead.
##
## Metadata written:
##   trim_start   where the usable window begins, in seconds into the full clip
##   trim_length  how long that window is
##   hit_ratios   moments of impact, normalized WITHIN the window
##
## SWING takes a tight window around the single loudest impact; SPAN takes the whole
## working stretch, which for the combo clips is a genuine multi-hit flourish.
static func _measure_action_window(anim: Animation, clip_name: String, policy: Trim, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D) -> void:
	var bone_name: String = SWING_TRACKING_BONE.get(clip_name, WEAPON_HAND_BONE)
	var samples := _sample_bone_speed(anim, skeleton, anim_player, root, bone_name)
	var peak_speed: float = 0.0
	var peak_time: float = 0.0
	for s in samples:
		if s.y > peak_speed:
			peak_speed = s.y
			peak_time = s.x
	if peak_speed <= 0.0:
		push_warning("Could not measure a strike in '%s'; it will play whole" % clip_name)
		anim.set_meta("trim_start", 0.0)
		anim.set_meta("trim_length", anim.length)
		anim.set_meta("hit_ratios", PackedFloat32Array([0.5]))
		return

	var cutoff: float = peak_speed * SWING_SPEED_THRESHOLD
	var t0: float
	var t1: float
	if policy == Trim.SWING:
		t0 = _settle_time(samples, peak_time, -1, peak_speed)
		t1 = _settle_time(samples, peak_time, 1, peak_speed)
	else:
		var first_time: float = peak_time
		var last_time: float = peak_time
		for s in samples:
			if s.y >= cutoff:
				first_time = minf(first_time, s.x)
				last_time = maxf(last_time, s.x)
		t0 = first_time - SPAN_LEAD_IN
		t1 = last_time + float(SPAN_LEAD_OUT_OVERRIDE.get(clip_name, SPAN_LEAD_OUT))
	t0 = clampf(t0, 0.0, anim.length)
	t1 = clampf(t1, t0 + 1.0 / RESAMPLE_FPS, anim.length)

	var window_length: float = maxf(t1 - t0, 1.0 / RESAMPLE_FPS)
	var hits := PackedFloat32Array()
	if policy == Trim.SWING:
		hits.append(clampf((peak_time - t0) / window_length, 0.0, 1.0))
	else:
		for hit_time in _find_impact_times(samples, cutoff):
			if hit_time >= t0 and hit_time <= t1:
				hits.append(clampf((hit_time - t0) / window_length, 0.0, 1.0))
	if hits.is_empty():
		hits.append(0.5)

	anim.set_meta("trim_start", t0)
	anim.set_meta("trim_length", window_length)
	anim.set_meta("hit_ratios", hits)

	var hit_text := PackedStringArray()
	for h in hits:
		hit_text.append("%.0f%%" % (h * 100.0))
	print("  window %-13s full %.2fs, plays [%.2f..%.2f] = %.2fs, hits at %s" % [
		clip_name, anim.length, t0, t1, window_length, ", ".join(hit_text)])


## Walks away from the impact frame in `direction` until the limb has slowed to
## SWING_SETTLED_FRACTION of its peak, so the clip is cut where the motion is calm
## rather than at an arbitrary offset. Clamped both ways: never closer to the impact
## than the MIN, never further than the MAX.
static func _settle_time(samples: Array[Vector2], peak_time: float, direction: int, peak_speed: float) -> float:
	var limit_min: float = SWING_PRE_IMPACT_MIN if direction < 0 else SWING_POST_IMPACT_MIN
	var limit_max: float = SWING_PRE_IMPACT_MAX if direction < 0 else SWING_POST_IMPACT_MAX
	var settled: float = peak_speed * SWING_SETTLED_FRACTION
	var best: float = peak_time + direction * limit_max
	var i := 0
	while i < samples.size():
		var idx: int = i if direction > 0 else samples.size() - 1 - i
		var sample: Vector2 = samples[idx]
		var offset: float = (sample.x - peak_time) * direction
		i += 1
		if offset < limit_min:
			continue
		if offset > limit_max:
			continue
		if sample.y <= settled:
			# First calm sample past the minimum in this direction - cut here.
			best = sample.x
			break
	return best


## Local maxima of the limb-speed profile above `cutoff`, thinned so two samples of
## the same strike don't register as two hits.
static func _find_impact_times(samples: Array[Vector2], cutoff: float) -> Array[float]:
	var out: Array[float] = []
	for i in range(1, samples.size() - 1):
		var speed: float = samples[i].y
		if speed < cutoff:
			continue
		if speed < samples[i - 1].y or speed < samples[i + 1].y:
			continue
		if not out.is_empty() and samples[i].x - out[out.size() - 1] < MIN_HIT_SEPARATION:
			# Same strike, still accelerating - keep whichever sample is louder.
			if speed > samples[i - 1].y:
				out[out.size() - 1] = samples[i].x
			continue
		out.append(samples[i].x)
	return out


## Speed of `bone_name` in root space, sampled across the clip. Returns
## [Vector2(time, speed), ...]. Driving the real AnimationPlayer/Skeleton3D (rather
## than reading the raw track) is what makes this correct for a bone several joints
## down the chain, whose world motion comes mostly from its parents.
static func _sample_bone_speed(anim: Animation, skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D, bone_name: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return out

	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP := "__swing_measure__"
	temp_library.add_animation(TEMP_CLIP, anim)
	anim_player.add_animation_library("__swing__", temp_library)
	anim_player.play("__swing__/" + TEMP_CLIP)

	var step: float = 1.0 / RESAMPLE_FPS
	var previous := Vector3.ZERO
	var have_previous := false
	var t: float = 0.0
	while t <= anim.length:
		_apply_pose_at(anim_player, t)
		var pos: Vector3 = (skeleton_to_root * _bone_global_pose(skeleton, bone_idx)).origin
		if have_previous:
			out.append(Vector2(t, pos.distance_to(previous) / step))
		previous = pos
		have_previous = true
		t += step

	anim_player.stop()
	anim_player.remove_animation_library("__swing__")
	return out


# --- borrowed enemy clip ------------------------------------------------------

## Adapts a clip authored on the enemy rig (57 bones, ~0.02 units tall) onto this
## rig (33 bones, ~1.9 units). Rotation tracks carry over untouched - they're
## scale-free and match by bone name. Position tracks do NOT: they'd move this
## rig's joints to enemy-scale offsets and collapse it into a puddle. Only the
## hips track survives, rescaled by the height ratio between the two rigs; every
## other position track is dropped so those bones keep their own rest offsets.
## Tracks for the 24 bones this rig doesn't have are dropped as well.
static func _adopt_foreign_clip(source_fbx_path: String, skeleton: Skeleton3D, clip_name: String) -> Animation:
	var anim := _extract_animation(source_fbx_path)
	if anim == null:
		return null
	var source_skeleton := _skeleton_of(source_fbx_path)
	if source_skeleton == null:
		return null

	var ratio: float = _rig_height(skeleton) / maxf(_rig_height(source_skeleton), 0.00001)
	var dropped := 0
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(track_idx))
		var bone_name := path.get_slice(":", 1)
		if skeleton.find_bone(bone_name) == -1:
			anim.remove_track(track_idx)
			dropped += 1
			continue
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if bone_name != HIPS_BONE:
			anim.remove_track(track_idx)
			dropped += 1
			continue
		for key_idx in anim.track_get_key_count(track_idx):
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, value * ratio)

	_strip_horizontal_root_motion(anim, HIPS_BONE)
	print("  adopt %-13s rig ratio %.1fx, dropped %d incompatible tracks" % [clip_name, ratio, dropped])
	return anim


static func _skeleton_of(fbx_path: String) -> Skeleton3D:
	var scene: PackedScene = ResourceLoader.load(fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if scene == null:
		return null
	return scene.instantiate().find_child("Skeleton3D", true, false)


static func _rig_height(skeleton: Skeleton3D) -> float:
	var top := skeleton.find_bone(HEIGHT_TOP_BONE)
	var bottom := skeleton.find_bone(HEIGHT_BOTTOM_BONE)
	if top == -1 or bottom == -1:
		return 0.0
	return absf(_bone_global_rest(skeleton, top).origin.y - _bone_global_rest(skeleton, bottom).origin.y)


# --- grounding & scale --------------------------------------------------------

## Unlike every enemy in this project, this rig is authored at real-world scale, so
## this is a small trim (~1.0x) onto the player's 1.9-tall capsule rather than the
## 85-100x rescue the enemy meshes need. Measured from the skeleton's own rest pose,
## not the mesh AABB: this mesh's skin binds into a differently-scaled vertex space,
## so its ArrayMesh AABB reports a meaningless 0.004 units tall.
##
## Also yaws the visual 180 degrees - see FACING_CORRECTION_DEGREES.
static func _normalize_to_target_height(root: Node3D, skeleton: Skeleton3D) -> void:
	var height := _rig_height(skeleton)
	if height <= 0.0:
		push_error("Could not measure the player rig's height; leaving scale untouched")
		return
	var factor: float = TARGET_HEIGHT / height
	var basis := Basis(Vector3.UP, deg_to_rad(FACING_CORRECTION_DEGREES)).scaled(Vector3.ONE * factor)
	root.transform = Transform3D(basis, Vector3.ZERO)
	print("Player rig measured %.3f units tall; scaling %.4fx to %.2f, yawed %.0f degrees." % [height, factor, TARGET_HEIGHT, FACING_CORRECTION_DEGREES])


## Per-clip copy with the hips position track shifted vertically so the lowest
## ground-contact point actually touches y=0 - ported from tools/character_builder.gd,
## which documents why this is needed even for a rig's own clips.
static func _ground_correct_library(template_library: AnimationLibrary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var factor: float = root.transform.basis.get_scale().y
	var corrected := AnimationLibrary.new()

	for clip_name in template_library.get_animation_list():
		var anim: Animation = template_library.get_animation(clip_name).duplicate(true)
		# duplicate() drops metadata, so carry the build-time measurements across.
		var source_anim: Animation = template_library.get_animation(clip_name)
		for key in ["hit_ratios", "travel_speed", "trim_start", "trim_length"]:
			if source_anim.has_meta(key):
				anim.set_meta(key, source_anim.get_meta(key))
		var min_foot_y := _measure_min_foot_height(anim_player, skeleton, root, skeleton_to_root, anim)
		if is_finite(min_foot_y):
			_shift_hips_y(anim, HIPS_BONE, -min_foot_y / factor)
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
		_apply_pose_at(anim_player, t)
		for idx in foot_indices:
			var world_equiv: Transform3D = root.transform * skeleton_to_root * _bone_global_pose(skeleton, idx)
			min_y = minf(min_y, world_equiv.origin.y)

	anim_player.stop()
	anim_player.remove_animation_library("__ground__")
	return min_y


static func _shift_hips_y(anim: Animation, bone_name: String, delta_y: float) -> void:
	var track_idx := _find_position_track(anim, bone_name)
	if track_idx == -1:
		return
	for key_idx in anim.track_get_key_count(track_idx):
		var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
		anim.track_set_key_value(track_idx, key_idx, value + Vector3(0.0, delta_y, 0.0))


# --- weapon -------------------------------------------------------------------

## Same grip maths as tools/character_builder.gd's _attach_weapon(): the constants
## are expressed in world units and divided by the armature's own scale, so they
## carry over unchanged to this (metric, ~1.0-scale) rig. The hand-rest cancellation
## is computed per-skeleton, which is what lets one set of constants serve rigs
## whose hand bones rest at different orientations.
const WEAPON_WORLD_SCALE := 0.5
const WEAPON_GRIP_DROP_WORLD := 0.08
const WEAPON_TWIST_DEGREES := 90.0
const WEAPON_LEAN_AXIS := Vector3(0.0, 0.0, 1.0)
const WEAPON_LEAN_DEGREES := 70.791
const WEAPON_GRIP_EXTRA_OFFSET_WORLD := Vector3(-0.136396, -0.08001, 0.012326)


static func _attach_weapon(skeleton: Skeleton3D) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandAttachment"
	attachment.bone_name = WEAPON_HAND_BONE
	skeleton.add_child(attachment)

	var weapon_scene: PackedScene = ResourceLoader.load(WEAPON_GLB, "", ResourceLoader.CACHE_MODE_REPLACE)
	if weapon_scene == null:
		push_error("Could not load %s" % WEAPON_GLB)
		return
	var weapon_root: Node3D = weapon_scene.instantiate()
	weapon_root.name = "Weapon"

	var armature_scale: float = _get_node_global_scale(skeleton).y
	var local_scale: float = WEAPON_WORLD_SCALE / armature_scale
	var local_grip_drop: float = WEAPON_GRIP_DROP_WORLD / armature_scale

	var hand_rest: Transform3D = _bone_global_rest(skeleton, skeleton.find_bone(WEAPON_HAND_BONE))
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
		(weapon_mesh_node.mesh as ArrayMesh).surface_set_material(0, _build_weapon_material())


## The glb embeds its own texture data and Godot's glTF importer re-extracts it
## under a name derived from the glb's filename + material slot, ignoring the loose
## renamed files sitting alongside it - rebuild the material explicitly instead.
static func _build_weapon_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ResourceLoader.load(WEAPON_GLB.replace(".glb", "_albedo.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.normal_enabled = true
	mat.normal_texture = ResourceLoader.load(WEAPON_GLB.replace(".glb", "_normal.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	var metallic_roughness: Texture2D = ResourceLoader.load(WEAPON_GLB.replace(".glb", "_metallic_roughness.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.metallic = 1.0
	mat.metallic_texture = metallic_roughness
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.roughness = 1.0
	mat.roughness_texture = metallic_roughness
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	return mat


## The PBR maps come from a SECOND Meshy export (TEXTURE_BASE, 0830103939) than the
## rigged mesh (MESH_FBX, 0829200310) - the rigged one carries texture *references*
## with no image data at all, so on its own the body renders flat grey.
##
## Mixing the two is safe, and that was verified rather than assumed: both exports
## are the same 24014-vertex mesh with the same 20750 triangles, and once the
## differing vertex ORDER is corresponded triangle-by-triangle, all 62250 UV corners
## are identical to the last decimal. Only the vertex ordering was shuffled by the
## re-export, and ordering is exactly what a texture lookup does not care about.
##
## The emission map is deliberately skipped: sampled across the image its maximum is
## 0.027, i.e. black, so wiring it in would cost 4MB of VRAM to add nothing.
static func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0
	mat.roughness = 1.0

	var albedo := _optional_texture(".png")
	if albedo == null:
		push_warning("No %s.png - the player will render untextured." % TEXTURE_BASE)
	else:
		mat.albedo_texture = albedo
	var normal := _optional_texture("_normal.png")
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	# Both maps are greyscale, so any channel would do; red matches how the enemy
	# materials in scenes/melee/*.tscn read theirs.
	var metallic := _optional_texture("_metallic.png")
	if metallic != null:
		mat.metallic = 1.0
		mat.metallic_texture = metallic
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var roughness := _optional_texture("_roughness.png")
	if roughness != null:
		mat.roughness_texture = roughness
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat


static func _optional_texture(suffix: String) -> Texture2D:
	var path := TEXTURE_BASE + suffix
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


# --- shared helpers -----------------------------------------------------------

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


## Steps the mixer to `time` and applies it. `seek(time, true)` alone leaves the
## mixer's own accumulator untouched in manual callback mode; the advance(0) is
## what actually writes the sampled values onto the skeleton's bone poses.
static func _apply_pose_at(anim_player: AnimationPlayer, time: float) -> void:
	anim_player.seek(time, true)
	anim_player.advance(0.0)


## Composes a bone's global pose from the local poses the mixer just wrote.
##
## Skeleton3D.get_bone_global_pose() must NOT be used here: it reads a cache that
## is only recomputed when the skeleton processes a frame, and a build-time script
## driving the mixer by hand never gives it one - so it keeps returning the REST
## pose no matter where the clip is seeked to. Confirmed directly: local poses from
## get_bone_pose() varied across a swing while get_bone_global_pose() returned one
## constant rest value for every sample.
static func _bone_global_pose(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_pose(b)
	return accum


static func _bone_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_rest(b)
	return accum


static func _get_node_global_scale(node: Node3D) -> Vector3:
	var node_scale := Vector3.ONE
	var current: Node = node
	while current is Node3D:
		node_scale *= (current as Node3D).transform.basis.get_scale()
		current = current.get_parent()
	return node_scale


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
			return node as MeshInstance3D
		for child in node.get_children():
			stack.append(child)
	return null


static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_recursive(child, owner)
