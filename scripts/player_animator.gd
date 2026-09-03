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

## Clips that live on the locomotion layer, i.e. can be cross-faded into as the
## character's resting state. `reset` restarts the clip on entry: wanted for the
## one-shot-ish ones, unwanted for the loops (it would jerk the stride every time
## walk and run swap).
const LOCOMOTION_CLIPS := {
	"idle": false,
	"walk_forward": false,
	"walk_back": false,
	"walk_left": false,
	"walk_right": false,
	"run_forward": false,
	"run_back": false,
	"block_idle": false,
	"idle_look_1": true,
	"idle_look_2": true,
	"jump": true,
	"death": true,
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

const PARAM_LOCO_REQUEST := "parameters/%s/transition_request" % LOCO_NODE
const PARAM_LOCO_SPEED := "parameters/%s/scale" % LOCO_SPEED_NODE
const PARAM_ACTION_SPEED := "parameters/%s/scale" % ACTION_SPEED_NODE
const PARAM_SHOT_REQUEST := "parameters/%s/request" % SHOT_NODE

## Below this planar speed the player counts as standing still.
const MOVING_SPEED_EPSILON := 0.15

var _anim: AnimationPlayer
var _visual: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _action_anim: AnimationNodeAnimation
var _shot: AnimationNodeOneShot

## Only used to keep an idle variation from starting under a swing; gameplay's own
## commitment timers live in Player.
var _action_timer: float = 0.0
var _is_dead: bool = false

var _idle_timer: float = 0.0
var _next_idle_variation: float = 0.0
var _idle_variation_timer: float = 0.0

var _current_loco: String = ""
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
## authored as a .tres so the node set stays derived from LOCOMOTION_CLIPS and the
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
	var available: Array[String] = []
	for clip in LOCOMOTION_CLIPS.keys():
		if library.has_animation(clip):
			available.append(clip)
		else:
			push_warning("Locomotion clip '%s' is missing from the player library" % clip)
	loco.set("input_count", available.size())
	for i in available.size():
		loco.set("input_%d/name" % i, available[i])
		loco.set("input_%d/reset" % i, LOCOMOTION_CLIPS[available[i]])
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = available[i]
		graph.add_node("loco_" + available[i], clip_node, Vector2(0.0, 80.0 * i))
	graph.add_node(LOCO_NODE, loco, Vector2(280.0, 0.0))
	for i in available.size():
		graph.connect_node(LOCO_NODE, i, "loco_" + available[i])

	var loco_speed := AnimationNodeTimeScale.new()
	graph.add_node(LOCO_SPEED_NODE, loco_speed, Vector2(480.0, 0.0))
	graph.connect_node(LOCO_SPEED_NODE, 0, LOCO_NODE)

	_action_anim = AnimationNodeAnimation.new()
	graph.add_node(ACTION_NODE, _action_anim, Vector2(280.0, 240.0))
	var action_speed := AnimationNodeTimeScale.new()
	graph.add_node(ACTION_SPEED_NODE, action_speed, Vector2(480.0, 240.0))
	graph.connect_node(ACTION_SPEED_NODE, 0, ACTION_NODE)

	_shot = AnimationNodeOneShot.new()
	_shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_shot.fadein_time = GameSettings.player_anim_blend_action
	_shot.fadeout_time = GameSettings.player_anim_blend_action
	_shot.autorestart = false
	for bone_name in _upper_body_bones():
		_shot.set_filter_path(NodePath("%s:%s" % [_visual.get_path_to(_skeleton), bone_name]), true)
	graph.add_node(SHOT_NODE, _shot, Vector2(700.0, 0.0))
	graph.connect_node(SHOT_NODE, 0, LOCO_SPEED_NODE)
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


## Every bone that is not hips-or-below. Derived from the skeleton rather than
## listed, so a rig change cannot silently leave a bone unmasked.
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
func play_windup(clip: String, duration: float) -> bool:
	var lead_in: float = windup_length(clip)
	if _tree == null or _is_dead or lead_in <= 0.0:
		return false
	_fire_shot(clip, 0.0, lead_in + strike_length(clip), lead_in / maxf(duration, 0.01), duration, false)
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
func update_locomotion(delta: float, planar_velocity: Vector3, sprinting: bool, on_floor: bool, blocking: bool) -> void:
	if _tree == null or _is_dead:
		return

	if _action_timer > 0.0:
		_action_timer -= delta

	var speed := planar_velocity.length()

	if blocking:
		_cancel_idle_variation()
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
		var clip := _pick_locomotion_clip(planar_velocity, sprinting)
		_request_loco(clip)
		_tree.set(PARAM_LOCO_SPEED, _speed_scale_for(clip, speed))
		return

	_tree.set(PARAM_LOCO_SPEED, 1.0)
	_update_idle(delta)


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

func _pick_locomotion_clip(planar_velocity: Vector3, sprinting: bool) -> String:
	var local := global_transform.basis.inverse() * planar_velocity
	# -Z is forward for a Node3D, so a negative local z means moving ahead.
	if absf(local.z) >= absf(local.x):
		if local.z <= 0.0:
			return "run_forward" if sprinting else "walk_forward"
		return "run_back" if sprinting else "walk_back"
	# The pack has no sideways run, so a sprinting strafe keeps the walk cycle and
	# leans on the speed scaling below instead.
	return "walk_right" if local.x > 0.0 else "walk_left"


## Playback speed that makes the clip's own stride cover the ground the character is
## actually covering. Clamped: past a point, stretching a walk cycle looks worse
## than letting the feet slide a little.
func _speed_scale_for(clip: String, speed: float) -> float:
	var native := _travel_speed(clip)
	if native <= 0.01:
		return 1.0
	return clampf(speed / native, GameSettings.player_locomotion_speed_min, GameSettings.player_locomotion_speed_max)


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
