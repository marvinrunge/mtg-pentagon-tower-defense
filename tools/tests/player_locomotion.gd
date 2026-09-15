extends Node
## Regression test: diagonal movement blends instead of flickering.
##
## Run with:  godot --headless --path . res://tools/tests/player_locomotion.tscn
##
## The player's travel used to be picked one clip at a time, with
## `absf(local.z) >= absf(local.x)`. On a keyboard diagonal those two are exactly equal - the
## input vector is (0.7071, -0.7071) - so the comparison resolved on whatever floating-point
## noise move_and_slide had left in the velocity, differently most frames. Each flip restarted
## the transition's 0.16s cross-fade, so W+D produced a character permanently mid-cross-fade
## between walk_forward and walk_right, and never a diagonal.
##
## Turning with the mouse made it permanent rather than causing it: movement is body-relative,
## so a held diagonal stays pinned at exactly 45 degrees no matter where the player looks.
## That is why the last check below turns the body while holding the input.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _player: Node3D = null
var _animator: PlayerAnimator = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	_run()
	get_tree().quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## Blocking while moving: the legs walk and the arms hold the block.
##
## Walking under guard used to be an ordinary walk with the shield down - the block was a
## LOCOMOTION state, so the moment the legs needed the walk instead, the guard had nowhere
## left to live. It is a filtered layer of its own now, above the legs and below the
## action one-shot.
func _check_guard() -> void:
	print("GUARD")
	var root: AnimationNodeBlendTree = _animator._tree.tree_root as AnimationNodeBlendTree
	_check("the tree has a guard layer", root.has_node(PlayerAnimator.GUARD_NODE))
	if not _animator._has_guard:
		return

	# Standing still keeps the full-body block pose it has always used.
	for _i: int in range(40):
		_animator.update_locomotion(1.0 / 60.0, Vector3.ZERO, false, true, true, false)
	_check("standing under guard still uses the whole-body block",
		_animator._current_loco == PlayerAnimator.BLOCK_CLIP, _animator._current_loco)

	# ...and walking under it drives the legs AND raises the arms.
	var velocity: Vector3 = _player.global_transform.basis * Vector3.FORWARD * 1.2
	for _i: int in range(40):
		_animator.update_locomotion(1.0 / 60.0, velocity, false, true, true, false)
	_check("walking under guard keeps the legs walking",
		_animator._current_loco == PlayerAnimator.WALK_SPACE, _animator._current_loco)
	var raised: float = float(_animator._tree.get(PlayerAnimator.PARAM_GUARD_AMOUNT))
	_check("...and puts the block on the arms", raised > 0.99, "guard %.2f" % raised)

	# THE one that was reported: a parried hit plays block_react through the one-shot, and
	# when it finishes the arms have to still be up. With the guard as a locomotion state
	# the flinch replaced it and the character stood there with their shield down.
	_animator.play_reaction("block_react", 0.3)
	for _i: int in range(40):
		_animator.update_locomotion(1.0 / 60.0, velocity, false, true, true, false)
	var after: float = float(_animator._tree.get(PlayerAnimator.PARAM_GUARD_AMOUNT))
	_check("a parry reaction does not drop the guard", after > 0.99, "guard %.2f" % after)

	# Letting go lowers them again, on every path out - this one via plain walking.
	for _i: int in range(40):
		_animator.update_locomotion(1.0 / 60.0, velocity, false, true, false, false)
	var lowered: float = float(_animator._tree.get(PlayerAnimator.PARAM_GUARD_AMOUNT))
	_check("letting go of block lowers them", lowered < 0.01, "guard %.2f" % lowered)


## Drives the animator the way Player does, for `steps` physics frames, and reports which
## locomotion state it settled on and where its blend point ended up.
func _walk(direction: Vector3, speed: float, steps: int = 40,
		sprinting: bool = false, in_combat: bool = false) -> Dictionary:
	var velocity: Vector3 = _player.global_transform.basis * direction.normalized() * speed
	for _i: int in range(steps):
		_animator.update_locomotion(1.0 / 60.0, velocity, sprinting, true, false, in_combat)
	return {
		"state": _animator._current_loco,
		"point": _animator._blend_point,
		"speed_scale": float(_animator._tree.get(PlayerAnimator.PARAM_LOCO_SPEED)),
	}


func _run() -> void:
	_player = PlayerRegistry.get_local()
	if _player == null:
		print("TEST RESULT: FAIL (no player)")
		return
	_animator = _player.animator as PlayerAnimator
	if _animator == null or _animator._tree == null:
		print("TEST RESULT: FAIL (no animator)")
		return

	# The tree has to actually contain the two gait spaces, or everything below silently
	# measures a fallback.
	var root: AnimationNodeBlendTree = _animator._tree.tree_root as AnimationNodeBlendTree
	for space: String in [PlayerAnimator.WALK_SPACE, PlayerAnimator.RUN_SPACE]:
		_check("the tree has a %s" % space, root.has_node(space))

	# --- the cardinals still work -------------------------------------------------
	# Forward is +Y in the blend space and back is -Y; strafing is +/-X. Getting a sign wrong
	# here plays the back cycle for forward movement, which every other check would pass.
	var forward: Dictionary = _walk(Vector3.FORWARD, 2.5)
	_check("forward blends forward", forward["point"].y > 0.9 and absf(forward["point"].x) < 0.1,
		"%s" % forward["point"])
	var back: Dictionary = _walk(Vector3.BACK, 2.5)
	_check("back blends backward", back["point"].y < -0.9, "%s" % back["point"])
	var right: Dictionary = _walk(Vector3.RIGHT, 2.5)
	_check("right blends right", right["point"].x > 0.9, "%s" % right["point"])
	var left: Dictionary = _walk(Vector3.LEFT, 2.5)
	_check("left blends left", left["point"].x < -0.9, "%s" % left["point"])

	# --- the diagonal, which is the whole point -----------------------------------
	for entry: Array in [
		[Vector3.FORWARD + Vector3.RIGHT, "W+D", 1.0, 1.0],
		[Vector3.FORWARD + Vector3.LEFT, "W+A", -1.0, 1.0],
		[Vector3.BACK + Vector3.RIGHT, "S+D", 1.0, -1.0],
		[Vector3.BACK + Vector3.LEFT, "S+A", -1.0, -1.0],
	]:
		var result: Dictionary = _walk(entry[0], 2.5)
		var point: Vector2 = result["point"]
		# Half of each neighbour, which is what the L1 normalization is for: a 45-degree input
		# lands exactly on the diamond edge rather than being clamped there from outside.
		_check("%s blends both clips" % entry[1],
			is_equal_approx(snappedf(point.x, 0.01), snappedf(0.5 * float(entry[2]), 0.01))
			and is_equal_approx(snappedf(point.y, 0.01), snappedf(0.5 * float(entry[3]), 0.01)),
			"%s" % point)

	# --- and it must not flicker --------------------------------------------------
	# The blend checks above are the ones that demonstrably catch the original bug: restore the
	# winner-take-all pick and they fail immediately, reporting (0, 1) for W+D instead of
	# (0.5, 0.5). These two are weaker - they feed clean velocity, where the real flicker came
	# from the post-collision jitter move_and_slide leaves behind - so they guard the mechanism
	# rather than reproduce the original noise. Worth keeping: a future change that reintroduces
	# a per-frame decision would trip them even though these inputs are quiet.
	#
	# Holding a diagonal through a long run must produce exactly one state change - the one
	# that entered it.
	_walk(Vector3.FORWARD, 2.5)
	var settled: String = _animator._current_loco
	var changes: int = 0
	var velocity: Vector3 = _player.global_transform.basis * (Vector3.FORWARD + Vector3.RIGHT).normalized() * 2.5
	for _i: int in range(240):
		_animator.update_locomotion(1.0 / 60.0, velocity, false, true, false, false)
		if _animator._current_loco != settled:
			settled = _animator._current_loco
			changes += 1
	_check("a held diagonal does not flicker", changes <= 1, "%d state changes in 240 frames" % changes)

	# ...including while the body is TURNING, which is what made it permanent. The velocity is
	# recomputed from the rotating basis each frame, exactly as Player does it.
	var turn_changes: int = 0
	var before_turn: String = _animator._current_loco
	for i: int in range(240):
		_player.rotation.y += 0.01
		var turning_velocity: Vector3 = _player.global_transform.basis * (Vector3.FORWARD + Vector3.RIGHT).normalized() * 2.5
		_animator.update_locomotion(1.0 / 60.0, turning_velocity, false, true, false, false)
		if _animator._current_loco != before_turn:
			before_turn = _animator._current_loco
			turn_changes += 1
	_check("a diagonal held while turning does not flicker", turn_changes == 0,
		"%d state changes" % turn_changes)

	# --- the gait switch must not chatter either ----------------------------------
	# A speed parked between the two thresholds has to stay on whichever gait it arrived in.
	_walk(Vector3.FORWARD, 0.8)
	var walked_in: String = _animator._current_loco
	_walk(Vector3.FORWARD, 1.5, 20)
	_check("a speed inside the hysteresis band keeps its gait",
		_animator._current_loco == walked_in, "%s -> %s" % [walked_in, _animator._current_loco])
	_walk(Vector3.FORWARD, 3.0, 40)
	_check("a clear sprint reaches the run gait",
		_animator._current_loco == PlayerAnimator.RUN_SPACE, _animator._current_loco)

	# --- the diagonal is timed to the blend, not to one clip ----------------------
	# walk_forward covers 0.99 m/s and walk_right 1.06, so a diagonal's real stride is ~1.03.
	# Dividing by either clip alone asks the legs to turn over at the wrong rate.
	var diagonal: Dictionary = _walk(Vector3.FORWARD + Vector3.RIGHT, 1.03, 60)
	_check("a diagonal plays at about 1.0x", absf(float(diagonal["speed_scale"]) - 1.0) < 0.08,
		"%.3f" % diagonal["speed_scale"])

	_check_guard()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
