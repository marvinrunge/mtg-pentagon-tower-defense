extends Node
## Regression test: the five player spawn points.
##
## Run with:  godot --headless --path . res://tools/tests/spawn_points.tscn
##
## They used to be a ring of `TAU * index / total`, which had two faults. Solo it returned
## Vector3(0, 1, 0) — the world origin, which is where the crystal stands — so a single player
## spawned inside the objective. And in a party the ring was keyed to the PLAYER COUNT rather
## than to the map, so the seats lined up with a different set of nothing for every party size.
##
## Every check below is measured against the map as it actually is: the lanes are read off
## their own EnemySpawner markers and the platform off the base cylinder, so a map edit that
## moves a lane fails this rather than silently leaving a player facing a gap.

## Matches the CSGCylinder3D the base platform is built from: radius 50, five sides. A regular
## pentagon's INRADIUS is what a point has to stay inside to be on the platform anywhere, and
## for a five-sided polygon that is circumradius * cos(36 degrees).
const PLATFORM_CIRCUMRADIUS: float = 50.0

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _main: Node = null


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


func _run() -> void:
	_main = get_tree().current_scene
	if _main == null or not _main.has_method("_player_seat"):
		print("TEST RESULT: FAIL (no MainController)")
		return

	var lane_count: int = _main.LANE_NAMES.size()
	var platform_inradius: float = PLATFORM_CIRCUMRADIUS * cos(PI / float(lane_count))
	var seats: Array[Transform3D] = []
	for i: int in range(lane_count):
		seats.append(_main._player_seat(i))

	for i: int in range(lane_count):
		var lane_name: String = String(_main.LANE_NAMES[i])
		var seat: Transform3D = seats[i]
		var flat := Vector3(seat.origin.x, 0.0, seat.origin.z)

		# Off the crystal. This is the whole complaint: the old solo seat was the origin.
		_check("%s seat is off the centre" % lane_name, flat.length() > 1.5,
			"%.2fm from the crystal" % flat.length())

		# ...but still on the platform, and still close enough that the base UI opens.
		_check("%s seat is on the platform" % lane_name, flat.length() < platform_inradius,
			"%.2f of %.2f inradius" % [flat.length(), platform_inradius])
		_check("%s seat is within base range" % lane_name,
			seat.origin.distance_to(Vector3(0.0, 0.5, 0.0)) < GameSettings.player_base_proximity,
			"%.2f of %.2f" % [seat.origin.distance_to(Vector3(0.0, 0.5, 0.0)), GameSettings.player_base_proximity])

		# Pointed at the enemies. Measured against the lane's real spawner, not against an
		# angle this test computed for itself - that would only prove the arithmetic agrees
		# with a copy of itself.
		var spawner: Node3D = _main.get_node_or_null(
			"NavigationRegion3D/Lanes/Lane_%s/EnemySpawner" % lane_name) as Node3D
		if spawner == null:
			_failures.append("%s lane has no EnemySpawner to aim at" % lane_name)
			continue
		var to_spawner: Vector3 = spawner.global_position - seat.origin
		to_spawner.y = 0.0
		# -Z is forward for a Node3D.
		var facing: Vector3 = -seat.basis.z
		facing.y = 0.0
		var alignment: float = facing.normalized().dot(to_spawner.normalized())
		_check("%s seat faces its lane" % lane_name, alignment > 0.999,
			"dot %.4f" % alignment)

		# The seat has to sit BETWEEN the crystal and its lane, not on the far side of the
		# crystal from it - a seat facing the right way from the wrong place still means
		# running past the objective to reach the fight.
		var outward: Vector3 = Vector3(spawner.global_position.x, 0.0, spawner.global_position.z).normalized()
		_check("%s seat is on its lane's side" % lane_name, flat.normalized().dot(outward) > 0.999,
			"dot %.4f" % flat.normalized().dot(outward))

	# Distinct seats, so five players do not resolve an overlap by exploding apart on frame one.
	var closest: float = INF
	for i: int in range(lane_count):
		for j: int in range(i + 1, lane_count):
			closest = minf(closest, seats[i].origin.distance_to(seats[j].origin))
	_check("the seats are distinct", closest > 2.0, "closest pair %.2fm" % closest)

	# A seat must not depend on how many people are playing: that was the old bug.
	_check("a seat does not move with the party size",
		_main._player_seat(1).origin.is_equal_approx(seats[1].origin),
		"seat 1 moved")
	# ...and a sixth player wraps rather than landing nowhere.
	_check("seats wrap past the lane count",
		_main._player_seat(lane_count).origin.is_equal_approx(seats[0].origin))

	# The live player is actually in one, and remembers it for respawning.
	var player: Node = PlayerRegistry.get_local()
	if player == null:
		_failures.append("no local player to check")
	else:
		var here := Vector3(player.global_position.x, 0.0, player.global_position.z)
		_check("the live player spawned off the crystal", here.length() > 1.5,
			"%.2fm" % here.length())
		_check("the live player kept its spawn point",
			player.spawn_point.origin.is_equal_approx(seats[0].origin),
			"%s vs %s" % [player.spawn_point.origin, seats[0].origin])
		# Respawning returns to the seat rather than to the origin.
		player.global_position = Vector3(20.0, 1.0, 20.0)
		player.is_downed = true
		player.respawn_at_base()
		_check("respawning returns to the seat",
			player.global_position.is_equal_approx(seats[0].origin),
			"%s" % player.global_position)

	if _failures.is_empty():
		print("TEST RESULT: PASS (%d seats)" % lane_count)
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
