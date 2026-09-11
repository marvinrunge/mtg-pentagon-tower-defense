extends Node
## Regression test: can the three aura orbs ever touch each other?
##
## Run with:  godot --headless --path . res://tools/tests/orb_orbits.tscn
##
## A player holding the blue, red and white Manifestations at once carries three orbs. They
## used to share one orbit outright - the same `_angle` starting at 0.0, the same speed, the
## same radius and height - so all three sat at exactly the same point, permanently, with only
## the largest visible. This is what stops that coming back, and it has to be an assertion
## rather than a look: two orbits with different speeds spend most of their time apart and
## meet rarely, so the one screenshot that gets taken is almost certainly a screenshot of them
## not touching.
##
## OrbitingOrb.orbit_position is pure and static, so the closest approach is found by brute
## force over a long span instead of by watching a scene.

## Long enough to cover many beats of the three speeds against each other (1.05 / 0.71 / 0.49
## multipliers on a shared base), sampled fine enough that a fast pass cannot be stepped over:
## the quickest orb travels about 4mm per sample at this rate.
const SPAN_SECONDS: float = 600.0
const STEP_SECONDS: float = 0.002

## Visual radius of each orb, taken from the meshes actually built in OrbitingOrb._ready: the
## frost crown is the widest at 0.31, fire's crust 0.30, heal's halo 0.34.
const VISUAL_RADIUS: Dictionary = {
	OrbitingOrb.Mode.FROST: 0.31,
	OrbitingOrb.Mode.FIRE: 0.30,
	OrbitingOrb.Mode.HEAL: 0.34,
}

## Clear air required between two orbs' surfaces on top of their radii. Not zero: orbs that
## merely fail to intersect still read as one clump when they pass, and the particle systems
## around each are wider than the mesh they hang on.
const REQUIRED_CLEARANCE: float = 0.22

var _frames: int = 0
var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 5:
		return
	_done = true
	_run()
	get_tree().quit()


func _run() -> void:
	var failures: Array[String] = []
	var pairs: Array[Array] = [
		[OrbitingOrb.Mode.FROST, OrbitingOrb.Mode.FIRE],
		[OrbitingOrb.Mode.FROST, OrbitingOrb.Mode.HEAL],
		[OrbitingOrb.Mode.FIRE, OrbitingOrb.Mode.HEAL],
	]
	var names: Dictionary = {
		OrbitingOrb.Mode.FROST: "frost",
		OrbitingOrb.Mode.FIRE: "fire",
		OrbitingOrb.Mode.HEAL: "heal",
	}

	for pair: Array in pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		var needed: float = float(VISUAL_RADIUS[a]) + float(VISUAL_RADIUS[b]) + REQUIRED_CLEARANCE
		var closest: float = INF
		var closest_at: float = 0.0
		var t: float = 0.0
		while t < SPAN_SECONDS:
			var distance: float = OrbitingOrb.orbit_position(a, t).distance_to(
				OrbitingOrb.orbit_position(b, t))
			if distance < closest:
				closest = distance
				closest_at = t
			t += STEP_SECONDS
		var label: String = "%s vs %s" % [names[a], names[b]]
		if closest < needed:
			failures.append("%s close to %.3fm at t=%.1fs (needs %.3fm)" % [
				label, closest, closest_at, needed])
		else:
			print("  ok   %-14s closest %.3fm at t=%.1fs (needs %.3fm)" % [
				label, closest, closest_at, needed])

	# Separately: no orb may be so low it sits inside the player, nor so high it leaves frame.
	for orb_mode: int in names.keys():
		var lowest: float = INF
		var highest: float = -INF
		var t2: float = 0.0
		while t2 < 60.0:
			var y: float = OrbitingOrb.orbit_position(orb_mode, t2).y
			lowest = minf(lowest, y)
			highest = maxf(highest, y)
			t2 += 0.01
		if lowest < 0.9:
			failures.append("%s dips to %.2fm, inside the player" % [names[orb_mode], lowest])
		if highest > 3.2:
			failures.append("%s rises to %.2fm, off over the player's head" % [names[orb_mode], highest])
		print("  ok   %-14s height %.2f..%.2fm" % [names[orb_mode], lowest, highest])

	if failures.is_empty():
		print("TEST RESULT: PASS (%.0fs simulated at %.0fHz)" % [SPAN_SECONDS, 1.0 / STEP_SECONDS])
		return
	print("TEST RESULT: FAIL")
	for failure: String in failures:
		print("  " + failure)
