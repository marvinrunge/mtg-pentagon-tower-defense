class_name PlayerAnimator
extends Node3D
## Owns the player's animated visual and decides which clip is playing.
##
## `Player` tells this node what happened ("swing this attack", "you were hit from
## the left", "you're moving at 4.2 units/s while sprinting") and this node resolves
## that into clips, playback speeds and blends. Keeping the choice here rather than
## in player.gd means the combat code never has to reason about which clip outranks
## which.
##
## Runs on an AnimationTree built in code (see _build_tree) rather than on bare
## AnimationPlayer.play() calls, because a light attack has to play on the UPPER BODY
## ONLY while the legs keep walking - two clips at once on one skeleton, which a
## single AnimationPlayer cannot do. The graph is:
##
##   loco_<clip> ─┐
##   loco_<clip> ─┼─ loco (Transition) ── loco_speed (TimeScale) ──┐
##   loco_<clip> ─┘                                                ├─ shot (OneShot) ── out
##   action (Animation) ── action_speed (TimeScale) ───────────────┘
##
## `shot` carries a bone filter covering everything from the spine up. With the
## filter on, the fired clip drives only those bones and the legs keep whatever
## `loco` is playing; with it off, the fired clip takes the whole body. That switch
## is exactly the difference between a light attack (swing while walking) and a
## heavy attack or kick (a committed move that also roots the player - see
## Player._begin_action).
##
## Clip metadata comes from tools/player_character_builder.gd:
##   travel_speed  how fast a locomotion clip's own root motion moved the character
##   hit_ratios    normalized moments of impact within an attack clip
##
## A multi-hit clip can also be played one STAGE at a time rather than whole: see
## combo_windows(), which is what turns a single stored flourish into the player's
## click-by-click light attack chain.
##
## The scale, ground offset and 180-degree facing correction of the visual are baked
## into scenes/misc/player_visual.tscn, so this node sits at the CharacterBody3D's
## own origin with no correction of its own.

const VISUAL_SCENE := preload("res://scenes/misc/player_visual.tscn")

## The whole strike window of a clip, as the [start, end] ratio pair every action
## call takes. Anything narrower is one stage of a chain (see combo_windows).
const FULL_WINDOW := Vector2(0.0, 1.0)

const IDLE_CLIP := "idle"
const BLOCK_CLIP := "block_idle"
const JUMP_CLIP := "jump"
const DEATH_CLIP := "death"
const IDLE_VARIATIONS := ["idle_look_1", "idle_look_2"]

## Travel cycles, used only when sprinting with no fight in progress. The armed run
## reads badly at speed - the weapon pins the arms and the whole stride goes stiff -
## so covering ground borrows the unarmed cycles instead. Anything a fight touches
## stays on the armed set.
const RUN_FORWARD_TRAVEL := "run_forward_unarmed"
const RUN_BACK_TRAVEL := "run_back_unarmed"

## The non-directional states the locomotion layer can cross-fade into. `reset` restarts
## the clip on entry: wanted for the one-shot-ish ones, unwanted for the loops.
##
## Travel is NOT here. The four walk clips and the two run clips are blended rather than
## chosen, so they live inside the two BlendSpace2Ds below instead of being transition
## inputs of their own - see GAIT_SPACES.
const STATE_CLIPS := {
	"idle": false,
	"block_idle": false,
	"idle_look_1": true,
	"idle_look_2": true,
	"jump": true,
	"death": true,
}

const WALK_SPACE := "walk_space"
const RUN_SPACE := "run_space"

## The two gaits, each a BlendSpace2D over [forward, back, left, right].
##
## Replaces picking ONE cardinal clip per frame, which had no diagonal at all and flickered
## on every one. `_pick_locomotion_clip` decided with `absf(local.z) >= absf(local.x)`, and on
## a keyboard diagonal those two are exactly equal - the input is (0.7071, -0.7071) - so the
## comparison resolved on whatever floating-point noise `move_and_slide` had left in the
## velocity, differently most frames. Each flip restarted the transition's 0.16s cross-fade,
## so the character sat in a cross-fade that never finished. Mouse-turning made it permanent
## rather than causing it: movement is body-relative, so turning keeps the local direction
## pinned at exactly 45 degrees and there is no way to rotate off the boundary.
##
## The run row reuses the two WALK strafe clips because the pack ships no sideways run. A
## diagonal sprint therefore blends a real run with a sped-up walk, which is the same
## compromise the old picker made - it just no longer has to choose between them.
const GAIT_SPACES := {
	WALK_SPACE: {
		"forward": "walk_forward", "back": "walk_back",
		"left": "walk_left", "right": "walk_right",
	},
	RUN_SPACE: {
		"forward": "run_forward_unarmed", "back": "run_back_unarmed",
		"left": "walk_left", "right": "walk_right",
	},
}

## Everything from the spine up. The complement of this - hips and both leg chains -
## stays with the locomotion layer during a filtered action, which is what lets the
## legs keep walking through a swing. Hips in particular MUST stay with locomotion:
## it carries the vertical bob and the builder's per-clip ground correction.
const LOWER_BODY_BONES := [
	"mixamorig_Hips",
	"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot",
	"mixamorig_LeftToeBase", "mixamorig_LeftToe_End",
	"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot",
	"mixamorig_RightToeBase", "mixamorig_RightToe_End",
]

const LOCO_NODE := "loco"
const LOCO_SPEED_NODE := "loco_speed"
const ACTION_NODE := "action"
const ACTION_SPEED_NODE := "action_speed"
const SHOT_NODE := "shot"
## The guard, as a layer of its own between locomotion and the action one-shot.
const GUARD_NODE := "guard"
const GUARD_POSE_NODE := "guard_pose"

const PARAM_WALK_POINT := "parameters/%s/blend_position" % WALK_SPACE
const PARAM_RUN_POINT := "parameters/%s/blend_position" % RUN_SPACE

const PARAM_LOCO_REQUEST := "parameters/%s/transition_request" % LOCO_NODE
const PARAM_LOCO_SPEED := "parameters/%s/scale" % LOCO_SPEED_NODE
const PARAM_ACTION_SPEED := "parameters/%s/scale" % ACTION_SPEED_NODE
const PARAM_SHOT_REQUEST := "parameters/%s/request" % SHOT_NODE
const PARAM_GUARD_AMOUNT := "parameters/%s/blend_amount" % GUARD_NODE

## How long the arms take to come up into the guard and back down. Short, because this
## follows a button being held rather than an animation being played - anything slower
## reads as the character being late to raise their shield.
const GUARD_BLEND_SECONDS := 0.12

## Below this planar speed the player counts as standing still.
const MOVING_SPEED_EPSILON := 0.15

var _anim: AnimationPlayer
var _visual: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _action_anim: AnimationNodeAnimation
var _shot: AnimationNodeOneShot
## False when the library has no block clip to hold, in which case the layer is not
## built at all and everything below is inert.
var _has_guard: bool = false
## Where the guard blend currently sits, 0 to 1. Held here rather than read back off the
## tree because it is driven towards a target every frame.
var _guard_amount: float = 0.0

## Only used to keep an idle variation from starting under a swing; gameplay's own
## commitment timers live in Player.
var _action_timer: float = 0.0
var _is_dead: bool = false

var _idle_timer: float = 0.0
var _next_idle_variation: float = 0.0
var _idle_variation_timer: float = 0.0

var _current_loco: String = ""
## The blend point actually in use, eased toward the target every frame. Smoothed because the
## velocity this is derived from carries floor-snap and wall-slide noise out of move_and_slide,
## and because a strafe turning into a forward run should read as a weight shift rather than a
## snap. Short enough (see GameSettings.player_anim_blend_point_smoothing) that it never lags
## behind the input in a way a player can feel.
var _blend_point: Vector2 = Vector2(0.0, 1.0)
## Which gait is current, kept so the walk/run switch can be hysteretic - a speed sitting on
## the threshold would otherwise chatter between two spaces the way the old picker chattered
## between two clips.
var _running: bool = false
var _cached_jump_scale: float = -1.0
## clip+stage-count -> the stage windows it splits into. Purely derived from the
## clip's impact metadata, so it is worked out once and kept.
var _combo_window_cache: Dictionary = {}


func _ready() -> void:
	_visual = VISUAL_SCENE.instantiate()
	add_child(_visual)
	_anim = _visual.find_child("AnimationPlayer", true, false)
	_skeleton = _visual.find_child("Skeleton3D", true, false)
	if _anim == null or _skeleton == null:
		push_error("player_visual.tscn is missing its AnimationPlayer or Skeleton3D; the player will not animate")
		return
	_build_tree()
	_roll_next_idle_variation()
	_request_loco(IDLE_CLIP)


## Builds the blend graph described in this file's header. Done in code rather than
## authored as a .tres so the node set stays derived from STATE_CLIPS/GAIT_SPACES and the
## bone filter stays derived from the actual skeleton - adding a clip or re-rigging
## does not leave a stale resource behind.
func _build_tree() -> void:
	var library: AnimationLibrary = _anim.get_animation_library("")
	# The AnimationTree drives the skeleton from here on; leaving the player running
	# as well would have two mixers writing the same bones.
	_anim.stop()

	var graph := AnimationNodeBlendTree.new()

	var loco := AnimationNodeTransition.new()
	loco.xfade_time = GameSettings.player_anim_blend_locomotion
	loco.allow_transition_to_self = false

	# The transition's inputs are the STATES plus the two gait spaces. A blend tree accepts a
	# BlendSpace2D as a node like any other, and a transition input is an ordinary graph
	# connection, so travel becomes two inputs instead of six.
	var inputs: Array[String] = []
	var resets: Array[bool] = []
	for clip in STATE_CLIPS.keys():
		if library.has_animation(clip):
			inputs.append(clip)
			resets.append(bool(STATE_CLIPS[clip]))
		else:
			push_warning("Locomotion clip '%s' is missing from the player library" % clip)
	for space_name in GAIT_SPACES.keys():
		if _build_gait_space(graph, library, String(space_name)):
			inputs.append(String(space_name))
			resets.append(false)

	loco.set("input_count", inputs.size())
	for i in inputs.size():
		loco.set("input_%d/name" % i, inputs[i])
		loco.set("input_%d/reset" % i, resets[i])
	graph.add_node(LOCO_NODE, loco, Vector2(280.0, 0.0))
	for i in inputs.size():
		# A gait space is already a node in the graph; a state clip needs one building.
		if GAIT_SPACES.has(inputs[i]):
			graph.connect_node(LOCO_NODE, i, inputs[i])
			continue
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = inputs[i]
		graph.add_node("loco_" + inputs[i], clip_node, Vector2(0.0, 80.0 * i))
		graph.connect_node(LOCO_NODE, i, "loco_" + inputs[i])

	var loco_speed := AnimationNodeTimeScale.new()
	graph.add_node(LOCO_SPEED_NODE, loco_speed, Vector2(480.0, 0.0))
	graph.connect_node(LOCO_SPEED_NODE, 0, LOCO_NODE)

	_action_anim = AnimationNodeAnimation.new()
	graph.add_node(ACTION_NODE, _action_anim, Vector2(280.0, 240.0))
	var action_speed := AnimationNodeTimeScale.new()
	graph.add_node(ACTION_SPEED_NODE, action_speed, Vector2(480.0, 240.0))
	graph.connect_node(ACTION_SPEED_NODE, 0, ACTION_NODE)

	# The guard sits BETWEEN locomotion and the action one-shot, so that the three layers
	# stack in the order the player experiences them: the legs do whatever they are doing,
	# the arms hold the block on top of that, and a swing or a flinch plays over both and
	# hands the arms back to the guard when it finishes.
	#
	# That last part is the reason it is a layer at all rather than another locomotion
	# state. `block_react` is fired through the one-shot like any other action, so with the
	# guard living in the locomotion transition a parried hit played its flinch and left
	# the character standing with their arms down - the hit was blocked, and they had
	# visibly stopped blocking.
	_build_guard_layer(graph, library)

	_shot = AnimationNodeOneShot.new()
	_shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_shot.fadein_time = GameSettings.player_anim_blend_action
	_shot.fadeout_time = GameSettings.player_anim_blend_action
	_shot.autorestart = false
	for bone_name in _upper_body_bones():
		_shot.set_filter_path(NodePath("%s:%s" % [_visual.get_path_to(_skeleton), bone_name]), true)
	graph.add_node(SHOT_NODE, _shot, Vector2(880.0, 0.0))
	graph.connect_node(SHOT_NODE, 0, GUARD_NODE if _has_guard else LOCO_SPEED_NODE)
	graph.connect_node(SHOT_NODE, 1, ACTION_SPEED_NODE)
	graph.connect_node("output", 0, SHOT_NODE)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_visual.add_child(_tree)
	# root_node resolves the clips' "Skeleton3D:<bone>" track paths, so it has to be
	# the visual root, exactly as the AnimationPlayer's own root_node is.
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", library)
	_tree.tree_root = graph
	_tree.active = true


## One gait as a BlendSpace2D: forward at +Y, back at -Y, right at +X, left at -X.
##
## Four points on the axes rather than eight around a circle. The domain is then a diamond,
## and `_blend_point` normalizes by the L1 norm so a 45-degree input lands at (0.5, 0.5) -
## exactly the midpoint of the forward-right edge, a clean 50/50 blend. Normalizing the usual
## way would hand it (0.707, 0.707), which is OUTSIDE the diamond and gets clamped back to the
## same place anyway, only without the weights being anything this file could compute for
## itself - and `_blended_travel_speed` needs them.
##
## Returns false when the clips are missing, so a stripped library falls back to the states
## rather than leaving a dead transition input nothing can play.
func _build_gait_space(graph: AnimationNodeBlendTree, library: AnimationLibrary, space_name: String) -> bool:
	var clips: Dictionary = GAIT_SPACES[space_name]
	for clip in clips.values():
		if not library.has_animation(String(clip)):
			push_warning("Gait '%s' is missing clip '%s'; falling back" % [space_name, clip])
			return false

	var space := AnimationNodeBlendSpace2D.new()
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	for entry in [
		["forward", Vector2(0.0, 1.0)], ["back", Vector2(0.0, -1.0)],
		["right", Vector2(1.0, 0.0)], ["left", Vector2(-1.0, 0.0)],
	]:
		var point := AnimationNodeAnimation.new()
		point.animation = String(clips[entry[0]])
		space.add_blend_point(point, entry[1])
	graph.add_node(space_name, space, Vector2(60.0, 520.0 if space_name == RUN_SPACE else 360.0))
	return true


## Every bone that is not hips-or-below. Derived from the skeleton rather than
## listed, so a rig change cannot silently leave a bone unmasked.
## The guard overlay: `block_idle` on the upper body only, over whatever the legs are
## doing underneath.
##
## A Blend2 filtered to the same bones the action one-shot uses, so "upper body" means one
## thing in this file. Filtered paths take input 1; everything else passes input 0 through
## untouched, which is what leaves the walk driving the legs.
func _build_guard_layer(graph: AnimationNodeBlendTree, library: AnimationLibrary) -> void:
	_has_guard = library.has_animation(BLOCK_CLIP)
	if not _has_guard:
		push_warning("No '%s' clip: the guard will not be held while moving" % BLOCK_CLIP)
		return
	var pose := AnimationNodeAnimation.new()
	pose.animation = BLOCK_CLIP
	graph.add_node(GUARD_POSE_NODE, pose, Vector2(480.0, 140.0))

	var guard := AnimationNodeBlend2.new()
	guard.filter_enabled = true
	for bone_name in _upper_body_bones():
		guard.set_filter_path(NodePath("%s:%s" % [_visual.get_path_to(_skeleton), bone_name]), true)
	graph.add_node(GUARD_NODE, guard, Vector2(700.0, 0.0))
	graph.connect_node(GUARD_NODE, 0, LOCO_SPEED_NODE)
	graph.connect_node(GUARD_NODE, 1, GUARD_POSE_NODE)


## Moves the guard towards `wanted` rather than snapping it, so the arms come up over
## GUARD_BLEND_SECONDS instead of popping into place on the frame the button went down.
func _drive_guard(wanted: bool, delta: float) -> void:
	if not _has_guard:
		return
	var target: float = 1.0 if wanted else 0.0
	if is_equal_approx(_guard_amount, target):
		return
	_guard_amount = move_toward(_guard_amount, target, delta / GUARD_BLEND_SECONDS)
	_tree.set(PARAM_GUARD_AMOUNT, _guard_amount)


func _upper_body_bones() -> Array[String]:
	var out: Array[String] = []
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if not LOWER_BODY_BONES.has(bone_name):
			out.append(bone_name)
	return out


# --- queries the combat code needs -------------------------------------------
#
# Deliberately no is_acting()/is_staggered() here. `Player` runs its own timers for
# how long a swing commits it and how long a stagger locks it out, and those are
# gameplay facts, not animation ones - exposing a second copy from this node would
# invite the two to disagree.

## Where a held spell should sit: midway between the two hands, in world space.
##
## Read off the live skeleton rather than from an offset on the body, because the point of a
## charge effect is that the character is visibly holding it - an orb pinned to the chest
## drifts away from the hands the moment the cast clip moves them, and `cast_red`'s lead-in
## does exactly that over the whole charge.
##
## Falls back to a point in front of the chest if either hand is missing from the rig, so a
## re-rig degrades to "roughly right" instead of dropping the effect at the character's feet.
func hand_midpoint() -> Transform3D:
	var fallback := Transform3D(global_transform.basis, global_position + Vector3(0.0, 1.25, 0.0) - global_transform.basis.z * 0.45)
	if _skeleton == null:
		return fallback
	var left: int = _skeleton.find_bone("mixamorig_LeftHand")
	var right: int = _skeleton.find_bone("mixamorig_RightHand")
	if left == -1 or right == -1:
		return fallback
	var to_world: Transform3D = _skeleton.global_transform
	var left_pos: Vector3 = (to_world * _skeleton.get_bone_global_pose(left)).origin
	var right_pos: Vector3 = (to_world * _skeleton.get_bone_global_pose(right)).origin
	return Transform3D(global_transform.basis, (left_pos + right_pos) * 0.5)


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## When, in seconds from the start of playback, `clip` lands its hits if the slice
## `window` of its strike window is stretched to `duration`. Empty for clips the
## builder found no impact in, and for a stage that contains none of them.
##
## `hit_ratios` are normalized within the strike WINDOW, not the whole stored clip,
## and an action always plays exactly the requested slice of that window over
## `duration` - so scaling by duration is right, and must not be "corrected" to use
## the full clip length.
func hit_times(clip: String, duration: float, window: Vector2 = FULL_WINDOW) -> Array[float]:
	var out: Array[float] = []
	var span: float = window.y - window.x
	if span <= 0.0:
		return out
	for ratio in _hit_ratios(clip):
		# Half-open on the upper edge so an impact sitting exactly on a stage boundary
		# pays out once, in the stage that follows it - except at the very end of the
		# clip, where there is no following stage to hand it to.
		if ratio < window.x or (ratio >= window.y and window.y < 1.0):
			continue
		out.append(clampf((ratio - window.x) / span, 0.0, 1.0) * duration)
	return out


## Splits `clip`'s strike window into `stages` consecutive slices, each an
## [start, end] pair of ratios within that window, in playback order.
##
## The cuts land at the MIDPOINT of the widest gaps between measured impacts, so a
## stage always holds whole strikes and the clip is never cut while the weapon is
## still travelling - which is what lets one stored flourish be spent one click at a
## time. A clip with fewer impacts than stages has nothing to measure against, so it
## is divided evenly instead.
func combo_windows(clip: String, stages: int) -> Array[Vector2]:
	var count: int = maxi(stages, 1)
	var cache_key: String = "%s#%d" % [clip, count]
	if _combo_window_cache.has(cache_key):
		return _combo_window_cache[cache_key]

	var windows: Array[Vector2] = []
	var hits: PackedFloat32Array = _hit_ratios(clip)
	if count == 1 or hits.size() < count:
		for i in count:
			windows.append(Vector2(float(i) / float(count), float(i + 1) / float(count)))
	else:
		# x is a gap's width, y the midpoint that would cut it. Sorted by width, so the
		# widest pauses in the flourish are the ones that become stage boundaries.
		var gaps: Array[Vector2] = []
		for i in hits.size() - 1:
			gaps.append(Vector2(hits[i + 1] - hits[i], (hits[i] + hits[i + 1]) * 0.5))
		gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
		var cuts: Array[float] = []
		for i in count - 1:
			cuts.append(gaps[i].y)
		cuts.sort()
		var start: float = 0.0
		for cut in cuts:
			windows.append(Vector2(start, cut))
			start = cut
		windows.append(Vector2(start, 1.0))

	_combo_window_cache[cache_key] = windows
	return windows


func _hit_ratios(clip: String) -> PackedFloat32Array:
	if _anim == null or not _anim.has_animation(clip):
		return PackedFloat32Array()
	return _anim.get_animation(clip).get_meta("hit_ratios", PackedFloat32Array())


## When, in seconds from the start of playback, `clip` should pay out if it is
## stretched to `duration`. The first measured impact frame, or the middle of the
## clip when the builder found none. Casts use this for their release moment, which
## is why SpellDatabase carries no release ratio of its own: the clip already knows.
## `use_last` picks the FINAL impact instead, for a clip whose payload is its last
## beat rather than its first - a jump attack lands on the slam, not the take-off.
func release_time(clip: String, duration: float, use_last: bool = false) -> float:
	var times := hit_times(clip, duration)
	if times.is_empty():
		return duration * 0.5
	return times[times.size() - 1] if use_last else times[0]


# --- things the combat code makes happen -------------------------------------

## Where `clip` releases, in seconds from the START of the stored clip rather than as a
## time within the played window - the same relationship hit_offsets() has to hit_times().
## What a cast continuing out of its own wind-up needs, since its playhead is measured
## against the whole clip rather than against the strike window alone.
func release_offset(clip: String, use_last: bool = false) -> float:
	var offsets: Array[float] = hit_offsets(clip)
	if offsets.is_empty():
		return windup_length(clip) + strike_length(clip) * 0.5
	return offsets[-1] if use_last else offsets[0]


## Fires `clip` over `duration` seconds, speeding it up or slowing it down to fit.
##
## `upper_body` decides whether the legs keep walking underneath. Pass true for a
## move the player can walk through (the light attack chain), false for one that
## takes the whole body - and for those, root the player, because a full-body clip
## over a moving character is exactly the foot-sliding this layering exists to
## remove.
##
## `window` narrows playback to one slice of the clip's strike window, which is how
## a multi-hit flourish is spent one stage per click (see combo_windows). The
## one-shot's own fade-out carries the character from wherever that stage ended back
## to its resting pose, so a stage never has to finish on a neutral frame.
func play_action(clip: String, duration: float, upper_body: bool, window: Vector2 = FULL_WINDOW) -> void:
	if _tree == null or _is_dead or not has_clip(clip):
		return
	# Play only the strike, out of a clip that is stored whole. The Mixamo originals
	# wind all the way back down to a rest pose, which is far too long at this
	# cadence - but cutting the stored clip down instead would leave the library full
	# of stumps, so the window is applied here via the custom timeline.
	var full_length: float = _action_length(clip)
	var span: float = clampf(window.y - window.x, 0.01, 1.0)
	var played: float = full_length * span
	_fire_shot(clip, windup_length(clip) + window.x * full_length, played, played / maxf(duration, 0.01), duration, upper_body)


## How much clip sits IN FRONT of `clip`'s strike window - the wind-up the trim
## discards. Zero for a clip whose window starts at its own first frame.
func windup_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return float(_anim.get_animation(clip).get_meta("trim_start", 0.0))


## How long `clip`'s strike window runs, in seconds of stored clip.
func strike_length(clip: String) -> float:
	return _action_length(clip)


## Where `clip`'s impacts fall, in seconds from the START of the stored clip rather
## than as ratios within its strike window - which is what a play beginning outside
## that window, like a charged swing continuing out of its own lead-in, needs.
func hit_offsets(clip: String) -> Array[float]:
	var out: Array[float] = []
	var window_start: float = windup_length(clip)
	var window_length: float = _action_length(clip)
	for ratio in _hit_ratios(clip):
		out.append(window_start + ratio * window_length)
	return out


## Starts the heavy's wind-up: the lead-in, crawling by at `duration`'s pace.
##
## Where it STOPS is the design: exactly where the strike window begins, i.e. where
## the builder measured the limb starting to work. Everything the player came to see
## - the acceleration, the impact, the follow-through - is therefore still ahead of
## them when they let go. Measured on spin_high, the lead-in is 8 frames over which
## the hand travels 0.13, against 5.35 for the swing proper: holding it reads as a
## slow raise while costing the swing nothing.
##
## The shot's TIMELINE deliberately runs past that stop, all the way through the
## strike window, even though the wind-up will never reach it at this speed. A
## one-shot ends when its own clip does, fading back to the locomotion layer - so a
## timeline that stopped at the top of the raise would drop the character to idle at
## the exact moment a full-length charge completes, and the swing would then have to
## blend in from idle rather than continue the raise. release_windup() speeds this
## same shot up instead of firing another one.
## `upper_body` is the same switch play_action() takes: false for a move that owns the
## whole body (the heavy's raise, which roots the player anyway), true for one the player
## can keep walking through - a held spell, where the legs staying on their cycle is what
## lets the caster reposition while the charge builds.
func play_windup(clip: String, duration: float, upper_body: bool = false) -> bool:
	var lead_in: float = windup_length(clip)
	if _tree == null or _is_dead or lead_in <= 0.0:
		return false
	_fire_shot(clip, 0.0, lead_in + strike_length(clip), lead_in / maxf(duration, 0.01), duration, upper_body)
	return true


## Turns the wind-up in flight into the swing, by changing nothing but its speed.
## `remaining` is how much stored clip is still ahead, `duration` how long it should
## take. No new shot is fired, so the character continues from the exact pose the
## raise had reached, at any point in the hold.
func release_windup(remaining: float, duration: float) -> void:
	if _tree == null or _is_dead:
		return
	_action_timer = maxf(duration, 0.01)
	set_action_speed(remaining / _action_timer)


## Retimes the shot in flight, in clip-seconds per real second, without restarting it
## or touching how long it is expected to run. The wind-up drives this every frame:
## it starts fast and eases towards a hold, so the raise is a snap rather than a crawl
## at one rate the whole way.
func set_action_speed(clip_seconds_per_second: float) -> void:
	if _tree == null:
		return
	_tree.set(PARAM_ACTION_SPEED, clip_seconds_per_second)


## Aborts whatever the action layer is playing and lets the locomotion layer take
## the whole body back. For a move that is dropped rather than finished - a charge
## the player gave up on - where letting the one-shot run on would leave the
## character still winding up something that is no longer happening.
func stop_action() -> void:
	if _tree == null:
		return
	_action_timer = 0.0
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Fires `clip` from `start_offset`, giving the shot a `timeline_length`-second
## window of it to play through at `speed` clip-seconds per real second. The one
## place the action layer is actually driven from.
##
## Speed is passed rather than derived from `hold_seconds` because the two come apart
## for a wind-up: it is given a timeline long enough to cover the swing that follows,
## but crawls through only the lead-in during the hold.
func _fire_shot(clip: String, start_offset: float, timeline_length: float, speed: float, hold_seconds: float, upper_body: bool) -> void:
	_action_timer = maxf(hold_seconds, 0.01)
	_cancel_idle_variation()
	_shot.filter_enabled = upper_body
	_action_anim.animation = clip
	_action_anim.use_custom_timeline = true
	_action_anim.stretch_time_scale = false
	_action_anim.loop_mode = Animation.LOOP_NONE
	_action_anim.start_offset = start_offset
	_action_anim.timeline_length = timeline_length
	_tree.set(PARAM_ACTION_SPEED, speed)
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Plays a flinch, squeezed into `duration` the same way an action is. The raw
## Mixamo reactions run 1.0-1.8s, which is far too long to take control away for,
## hence the squeeze rather than natural playback. Always full-body: `Player` roots
## the character for the same window.
func play_reaction(clip: String, duration: float) -> void:
	play_action(clip, duration, false)


## Which of the three reaction clips matches a hit arriving from `world_direction`
## (pointing from the player towards whatever hit them).
func reaction_clip_for(world_direction: Vector3) -> String:
	var local := global_transform.basis.inverse() * world_direction
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return "hit_gut"
	local = local.normalized()
	# -Z is forward; a hit from roughly ahead or behind folds the player forward.
	if absf(local.x) < 0.6:
		return "hit_gut"
	return "hit_right" if local.x > 0.0 else "hit_left"


func play_death() -> void:
	if _tree == null or _is_dead:
		return
	_is_dead = true
	_action_timer = 0.0
	_cancel_idle_variation()
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_tree.set(PARAM_LOCO_SPEED, 1.0)
	# Death rides the locomotion layer rather than the one-shot: a one-shot fades
	# back out at the end, and a corpse has to hold its final pose.
	_request_loco(DEATH_CLIP)


func revive() -> void:
	if _tree == null:
		return
	_is_dead = false
	_tree.set(PARAM_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_request_loco(IDLE_CLIP)


# --- per-frame locomotion ----------------------------------------------------

## Called every physics frame by `Player`. `planar_velocity` is in world space; it
## is resolved against the player's own facing here so strafing picks the sideways
## clips.
##
## Unlike the pre-AnimationTree version this does NOT stand down while an action is
## playing: the legs have to keep walking underneath a filtered swing. A full-body
## action masks this layer out anyway, and `Player` roots the character for those, so
## what is chosen here is idle.
func update_locomotion(
	delta: float,
	planar_velocity: Vector3,
	sprinting: bool,
	on_floor: bool,
	blocking: bool,
	in_combat: bool,
) -> void:
	if _tree == null or _is_dead:
		return

	if _action_timer > 0.0:
		_action_timer -= delta

	var speed := planar_velocity.length()

	# Driven here, above every branch below, so that the arms come back DOWN on any path
	# out of blocking - jumping, dying, letting go, being staggered - without each of
	# those having to remember to lower them.
	#
	# Only while MOVING. Standing still under guard stays on the full-body `block_idle`
	# state: it is the pose the whole thing is modelled on, and overlaying it on an idle
	# lower body would be the same arms over a slightly different stance for no gain.
	var moving: bool = speed > MOVING_SPEED_EPSILON
	_drive_guard(blocking and moving, delta)

	if blocking:
		_cancel_idle_variation()
		# block_idle has no travel of its own (travel_speed 0), so holding it while the
		# player is actually moving plants both feet and slides the whole character
		# across the ground. Walking under guard keeps the legs driving and the guard
		# layer above puts the block back on the arms - which is what was missing:
		# blocking on the move used to be an ordinary walk with the shield down.
		if moving:
			_drive_gait(WALK_SPACE, planar_velocity, speed, delta)
		else:
			_request_loco(BLOCK_CLIP)
			_tree.set(PARAM_LOCO_SPEED, 1.0)
		return

	if not on_floor and has_clip(JUMP_CLIP):
		_cancel_idle_variation()
		_request_loco(JUMP_CLIP)
		# The jump clip is far longer than the player is actually airborne (1.90s of
		# clip against ~0.92s of hang time), so at 1.0 it only ever showed its first
		# half before landing cut it off. Fitting it to the hang time plays the whole
		# arc - crouch, launch, tuck, land.
		_tree.set(PARAM_LOCO_SPEED, _jump_speed_scale())
		return

	if speed > MOVING_SPEED_EPSILON:
		_cancel_idle_variation()
		_drive_gait(_pick_gait(speed, sprinting, in_combat), planar_velocity, speed, delta)
		return

	_tree.set(PARAM_LOCO_SPEED, 1.0)
	_update_idle(delta)


func start_jump(vertical_velocity: float) -> void:
	if _tree == null or _is_dead or not has_clip(JUMP_CLIP):
		return
	_cancel_idle_variation()
	_request_loco(JUMP_CLIP)
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var air_time: float = 2.0 * maxf(vertical_velocity, 0.01) / maxf(gravity, 0.01)
	_cached_jump_scale = _clip_length(JUMP_CLIP) / maxf(air_time, 0.05)
	_tree.set(PARAM_LOCO_SPEED, clampf(_cached_jump_scale, 0.5, 3.0))


## Standing still: the plain idle loop, with an occasional "looking around" clip so
## the character doesn't read as a statue between waves. Any movement, attack or hit
## cancels a variation back to the plain loop (see _cancel_idle_variation).
func _update_idle(delta: float) -> void:
	if _idle_variation_timer > 0.0:
		_idle_variation_timer -= delta
		if _idle_variation_timer > 0.0:
			return
		_request_loco(IDLE_CLIP)
		_roll_next_idle_variation()
		return

	# Not while a swing is still in flight - the character would start idly looking
	# around mid-attack.
	if _action_timer <= 0.0:
		_idle_timer += delta
	if _idle_timer >= _next_idle_variation:
		var variation: String = IDLE_VARIATIONS[randi() % IDLE_VARIATIONS.size()]
		if has_clip(variation):
			_idle_variation_timer = _clip_length(variation)
			_request_loco(variation)
			return
		_roll_next_idle_variation()
		return

	_request_loco(IDLE_CLIP)


func _cancel_idle_variation() -> void:
	_idle_timer = 0.0
	if _idle_variation_timer > 0.0:
		_idle_variation_timer = 0.0
		_roll_next_idle_variation()


func _roll_next_idle_variation() -> void:
	_idle_timer = 0.0
	_next_idle_variation = randf_range(
		GameSettings.player_idle_variation_delay_min,
		GameSettings.player_idle_variation_delay_max
	)


# --- clip selection ----------------------------------------------------------

## Points a gait space at this velocity and times it to the ground actually being covered.
func _drive_gait(space: String, planar_velocity: Vector3, speed: float, delta: float) -> void:
	_request_loco(space)
	_drive_blend_point(_blend_point_for(planar_velocity), space, delta)
	var native: float = _blended_travel_speed(space, _blend_point)
	if native <= 0.01:
		_tree.set(PARAM_LOCO_SPEED, 1.0)
		return
	_tree.set(PARAM_LOCO_SPEED, clampf(
		speed / native,
		GameSettings.player_locomotion_speed_min,
		GameSettings.player_locomotion_speed_max
	))


## The speed band the run cycle takes over at, with hysteresis: break into a run above the
## first, drop back to a walk only below the second.
##
## Two numbers rather than one because a single threshold is a boundary a speed can sit on -
## a slow debuff or a haste bonus landing near it would flip the gait every frame, which is
## the same failure the diagonal had. The pair sit either side of the old 1.5, so ordinary
## movement and blocking still land where they did.
const RUN_ENTER_SPEED := 1.65
const RUN_EXIT_SPEED := 1.35


## Which gait to blend in. Unlike the old picker this depends only on SPEED and whether a
## fight is on - never on direction - so turning with the mouse cannot change it.
##
## `in_combat` is what separates travelling from fighting. A player mid-fight keeps the armed
## walk however fast they are going; a player who has stopped swinging and is holding sprint
## gets the travel cycle.
func _pick_gait(speed: float, sprinting: bool, in_combat: bool) -> String:
	if in_combat:
		_running = false
		return WALK_SPACE
	if sprinting:
		_running = true
	elif _running:
		_running = speed > RUN_EXIT_SPEED
	else:
		_running = speed >= RUN_ENTER_SPEED
	return RUN_SPACE if _running else WALK_SPACE


## Where in a gait space this velocity sits, as the L1-normalized [right, forward] pair.
##
## L1 rather than the usual normalize: it puts a 45-degree input exactly on the diamond's edge
## at (0.5, 0.5), which is both a clean 50/50 blend and a pair of weights this file can read
## back off directly - `_blended_travel_speed` is those same two numbers.
func _blend_point_for(planar_velocity: Vector3) -> Vector2:
	var local: Vector3 = global_transform.basis.inverse() * planar_velocity
	# -Z is forward for a Node3D, so forward is the NEGATED local z.
	var point := Vector2(local.x, -local.z)
	var l1: float = absf(point.x) + absf(point.y)
	if l1 < 0.0001:
		return _blend_point
	return point / l1


## Eases the live blend point toward `target` and hands it to whichever space is playing.
func _drive_blend_point(target: Vector2, space: String, delta: float) -> void:
	var tau: float = maxf(GameSettings.player_anim_blend_point_smoothing, 0.001)
	_blend_point = _blend_point.lerp(target, 1.0 - exp(-delta / tau))
	_tree.set(PARAM_RUN_POINT if space == RUN_SPACE else PARAM_WALK_POINT, _blend_point)


## How fast the BLEND is travelling under its own power, in units/second.
##
## The old _speed_scale_for divided by one clip's travel_speed, which is meaningless once two
## clips are playing at once: a forward-right diagonal is half walk_forward (0.99 m/s) and half
## walk_right (1.06), so its real stride covers 1.03 and dividing by either one alone asks the
## legs to turn over at the wrong rate. The blend weights are exactly |x| and |y| of the L1
## point, so the blended figure is one line.
func _blended_travel_speed(space: String, point: Vector2) -> float:
	var clips: Dictionary = GAIT_SPACES[space]
	var forward_back: String = String(clips["forward"] if point.y >= 0.0 else clips["back"])
	var sideways: String = String(clips["right"] if point.x >= 0.0 else clips["left"])
	var native: float = absf(point.y) * _travel_speed(forward_back) + absf(point.x) * _travel_speed(sideways)
	return native


## Playback speed that fits the jump clip into the time a jump actually lasts, from
## the launch velocity and gravity that produce it. Cached: neither input changes.
func _jump_speed_scale() -> float:
	if _cached_jump_scale > 0.0:
		return _cached_jump_scale
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var air_time: float = 2.0 * GameSettings.player_jump_velocity / maxf(gravity, 0.01)
	_cached_jump_scale = clampf(_clip_length(JUMP_CLIP) / maxf(air_time, 0.05), 0.5, 3.0)
	return _cached_jump_scale


func _travel_speed(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return _anim.get_animation(clip).get_meta("travel_speed", 0.0)


## How much of `clip` an action actually plays: the measured strike window when the
## builder found one, otherwise the whole clip (reactions and the like are untrimmed).
func _action_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	var anim := _anim.get_animation(clip)
	return float(anim.get_meta("trim_length", anim.length))


func _clip_length(clip: String) -> float:
	if not has_clip(clip):
		return 0.0
	return _anim.get_animation(clip).length


## The transition node cross-fades on its own, but re-requesting the state it is
## already in would restart that fade every frame.
func _request_loco(clip: String) -> void:
	if _current_loco == clip:
		return
	_current_loco = clip
	_tree.set(PARAM_LOCO_REQUEST, clip)
