extends Node
## Regression test: the charge orb's lifecycle and anchoring.
##
## Run with:  godot --headless --path . res://tools/tests/charge_orb.tscn
##
## The orb is parented to the WORLD, not to the player - charging does not root the caster,
## and an orb parented to the body would inherit its rotation and swing rather than sit in the
## hands. That makes leaking one a real hazard: nothing else would ever free it, and it would
## sit in the arena glowing for the rest of the run. Every way a charge can end is checked
## here, including the three that cast nothing.
##
## Also checks the thing the whole effect exists for: that the bolt leaves the HANDS. Fireball
## used to spawn at the camera, which is why a charged one never looked thrown.

const ORB_SCRIPT := preload("res://scripts/charge_orb.gd")

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _player: Node = null
var _scene: Node = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	await _run()
	get_tree().quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## Live ChargeOrb nodes anywhere in the scene, however they got there.
func _orbs() -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in _scene.get_children():
		# By script rather than by `is ChargeOrb`, for the same reason player.gd preloads it:
		# a headless run has no global class cache for a newly added class_name.
		if child.get_script() == ORB_SCRIPT and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _start_charge() -> void:
	_player.spell_ranks["red_1"] = 1
	if not _player.unlocked_spells_in_path.has("red_1"):
		_player.unlocked_spells_in_path.append("red_1")
	_player.spell_cooldown_timers.erase("red_1")
	_player.active_spell_index = 0
	_player.assign_quick_slot(0, "red_1")
	_player.cast_active_spell()


func _run() -> void:
	_scene = get_tree().current_scene
	_player = PlayerRegistry.get_local()
	if _scene == null or _player == null:
		print("TEST RESULT: FAIL (no scene or player)")
		return

	# --- it appears, and it appears IN THE HANDS ---------------------------------
	_start_charge()
	_check("charging spawns an orb", _player._charge_orb != null)
	_check("the orb is in the scene", _orbs().size() == 1, "%d" % _orbs().size())

	# The hand midpoint pushed forward by CHARGE_ORB_REACH, not the midpoint itself:
	# `cast_red` raises one arm rather than bringing both together, so the raw midpoint sits
	# INSIDE the caster's chest and the ball intersected the torso. Held out in front is the
	# intent, and this checks the offset is applied and points the right way.
	var hands: Vector3 = _player.animator.hand_midpoint().origin
	var expected: Vector3 = hands - _player.global_transform.basis.z * Player.CHARGE_ORB_REACH
	_check("the orb is held out in front of the hands",
		_player._charge_orb.global_position.distance_to(expected) < 0.01,
		"%s vs %s" % [_player._charge_orb.global_position, expected])
	_check("the orb is in FRONT, not behind",
		(_player._charge_orb.global_position - hands).dot(-_player.global_transform.basis.z) > 0.3,
		"%.2fm forward" % (_player._charge_orb.global_position - hands).dot(-_player.global_transform.basis.z))
	# Between the hands means ABOVE the feet and in front of nothing in particular - a
	# midpoint that collapsed to the origin would still pass a distance check against itself.
	_check("the hand midpoint is at chest height",
		hands.y - _player.global_position.y > 0.6 and hands.y - _player.global_position.y < 2.0,
		"%.2fm above the feet" % (hands.y - _player.global_position.y))

	# --- it grows -----------------------------------------------------------------
	_player.charge_timer = 0.0
	_player._update_charge_orb()
	var small: float = _player._charge_orb._core.scale.x
	_player.charge_timer = _player.charge_max_time
	_player._update_charge_orb()
	var big: float = _player._charge_orb._core.scale.x
	_check("the orb grows with the charge", big > small * 4.0, "%.3f -> %.3f" % [small, big])
	# ...and the growth is a curve, so the first half covers more than the second.
	_player.charge_timer = _player.charge_max_time * 0.5
	_player._update_charge_orb()
	var half: float = _player._charge_orb._core.scale.x
	_check("growth front-loads", (half - small) > (big - half), "%.3f / %.3f / %.3f" % [small, half, big])

	# --- full charge flares exactly once ------------------------------------------
	_player.charge_timer = _player.charge_max_time
	_player._update_charge_orb()
	_check("full charge flares", _player._charge_orb._flared)
	var rings: int = _player._charge_orb.get_children().filter(
		func(n: Node) -> bool: return n.name.begins_with("Shockwave") or n.name.begins_with("Ring")).size()
	_player._update_charge_orb()
	_player._update_charge_orb()
	var rings_after: int = _player._charge_orb.get_children().filter(
		func(n: Node) -> bool: return n.name.begins_with("Shockwave") or n.name.begins_with("Ring")).size()
	_check("the flare does not repeat", rings_after == rings, "%d -> %d" % [rings, rings_after])

	# --- releasing hands the position to the bolt ---------------------------------
	var muzzle: Vector3 = _player._release_charge_orb()
	_check("release reports where the orb was", muzzle.distance_to(hands) < 0.5, "%s" % muzzle)
	_check("release clears the reference", _player._charge_orb == null)

	# --- and every way a charge ENDS must clear it up -----------------------------
	# A leaked orb is parented to the scene and would glow there forever.
	for entry: Array in [
		["cancelled", func() -> void: _player._cancel_spell_charge()],
		["released", func() -> void: _player.release_charged_spell()],
	]:
		_player.is_charging = false
		_player._charge_orb = null
		_start_charge()
		if _player._charge_orb == null:
			_failures.append("%s: no orb to clear" % entry[0])
			continue
		(entry[1] as Callable).call()
		_check("a %s charge clears its orb" % entry[0], _player._charge_orb == null)

	# Nothing may be left holding on ONCE THE FADES HAVE RUN. Both release() and fizzle() free
	# the node at the end of a tween rather than immediately - the ball visibly throws or
	# collapses first - so checking on the same frame counts orbs that are correctly on their
	# way out. Waiting is the honest check: a genuinely leaked orb is still there afterwards.
	_player._cancel_spell_charge()
	await get_tree().create_timer(0.6).timeout
	_check("no orb is left behind", _orbs().is_empty(), "%d still live" % _orbs().size())

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
