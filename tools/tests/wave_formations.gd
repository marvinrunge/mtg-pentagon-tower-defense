extends Node
## Regression test: waves arrive as formed squads, and battle groups are runs of allied
## neighbours rather than five independent lanes.
##
## Run with:  godot --headless --path . res://tools/tests/wave_formations.tscn
##
## A wave used to be five spawn queues. Each colour trickled in one enemy at a time on a
## per-enemy timer, staggered colour after colour, so its mages arrived long after the
## melee that were meant to be screening them were already dead - and the player fought a
## queue rather than an army. The three things that replaced it are all checked here:
##
##   1. A squad's shape. Mages in the middle, archers ringing them, melee in front. This
##      is what makes killing a White mage cost something: it is behind everything else.
##   2. The battle-group partition. Groups must be CONTIGUOUS runs of the colour wheel,
##      which is the same thing as runs of adjacent lanes, and between them they must
##      cover all five colours exactly once - a colour dropped by the partition is a lane
##      that silently sends nothing for a whole wave.
##   3. The escalation. Solo lanes, then allied pairs, then shards, then the whole wheel.
##
## Nothing here needs the map: SquadDoctrine is pure geometry and the planner only touches
## the map to place a rendezvous, which it declines to do without one.

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 5:
		return
	_done = true
	_run()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _run() -> void:
	print("Squad formations")
	_test_formations()
	print("Battle groups")
	_test_partitions()
	print("Wave plans")
	_test_wave_plans()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


# --- 1. Formation shape --------------------------------------------------------------

func _test_formations() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var counts: Dictionary = {"Melee": 8, "Ranged": 6, "Mage": 3}

	for color: String in COLORS:
		var slots: Dictionary = SquadDoctrine.build_formation(color, counts, rng)
		var melee: Array = slots["Melee"]
		var ranged: Array = slots["Ranged"]
		var mages: Array = slots["Mage"]
		_check("%s: every unit gets a slot" % color,
			melee.size() == 8 and ranged.size() == 6 and mages.size() == 3,
			"got %d/%d/%d" % [melee.size(), ranged.size(), mages.size()])

		# Melee are in front of the casters in every doctrine. For the ranked ones that is
		# a hard separation; Red's mob only has to be true on average, which is the whole
		# difference between a phalanx and a rabble.
		if String(SquadDoctrine.get_doctrine(color)["shape"]) == "mob":
			_check("%s: melee are on average ahead of the mages" % color,
				_mean_z(melee) > _mean_z(mages),
				"%.2f vs %.2f" % [_mean_z(melee), _mean_z(mages)])
			continue

		_check("%s: the whole melee screen stands ahead of the archers" % color,
			_min_z(melee) > _max_z(ranged),
			"nearest melee %.2f, furthest archer %.2f" % [_min_z(melee), _max_z(ranged)])
		_check("%s: archers stand outside the mage core" % color,
			_min_radius(ranged, mages) > _max_radius(mages, mages),
			"innermost archer %.2f, outermost mage %.2f" % [
				_min_radius(ranged, mages), _max_radius(mages, mages)])
		# "Ringed", not "in a line behind". Six archers around three mages have to come at
		# the player from more than one side or the mages are not actually protected.
		_check("%s: archers ring the mages rather than queue behind them" % color,
			_angular_spread(ranged, mages) > PI,
			"spread %.0f degrees" % rad_to_deg(_angular_spread(ranged, mages)))

	# Blue's doctrine IS the setback: its casters hang back behind the screen far enough
	# that reaching them means walking past everything Blue brought.
	var blue: Dictionary = SquadDoctrine.build_formation("Blue", counts, rng)
	var white: Dictionary = SquadDoctrine.build_formation("White", counts, rng)
	_check("Blue keeps its casters further back than White does",
		_min_z(blue["Melee"]) - _max_z(blue["Mage"]) > _min_z(white["Melee"]) - _max_z(white["Mage"]))

	# A squad of one class must still be laid out, not collapsed onto a single point.
	var melee_only: Dictionary = SquadDoctrine.build_formation("Black", {"Melee": 5}, rng)
	_check("a melee-only squad still spreads out",
		(melee_only["Melee"] as Array).size() == 5 and _spread(melee_only["Melee"]) > 1.0)
	var empty: Dictionary = SquadDoctrine.build_formation("Green", {}, rng)
	_check("an empty composition produces no slots",
		(empty["Melee"] as Array).is_empty() and (empty["Mage"] as Array).is_empty())

	# to_world has to agree with the lanes: +Z local is the squad's line of advance and +X
	# is its right. A sign error here mirrors every formation in the game.
	var forward: Vector3 = Vector3(0.0, 0.0, 1.0)
	_check("to_world: +Z is forward",
		SquadDoctrine.to_world(Vector3.ZERO, forward, Vector3(0, 0, 5)).is_equal_approx(Vector3(0, 0, 5)))
	_check("to_world: +X is the squad's right",
		SquadDoctrine.to_world(Vector3.ZERO, forward, Vector3(5, 0, 0)).is_equal_approx(Vector3(5, 0, 0)))
	var turned: Vector3 = Vector3(1.0, 0.0, 0.0)
	_check("to_world: the frame rotates with the squad",
		SquadDoctrine.to_world(Vector3.ZERO, turned, Vector3(0, 0, 5)).is_equal_approx(Vector3(5, 0, 0)))


# --- 2 & 3. Battle groups and escalation ---------------------------------------------

func _test_partitions() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	for wave_idx: int in range(0, 40):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash("partition:%d" % wave_idx)
		var groups: Array = manager._partition_colors(wave_idx, rng)
		var seen: Array[String] = []
		var contiguous: bool = true
		var within_cap: bool = true
		var cap: int = manager._max_group_size(wave_idx)
		for colors: PackedStringArray in groups:
			if colors.size() > cap:
				within_cap = false
			# A group has to be a RUN of the wheel: lane index n, n+1, n+2. Two colours
			# that are not neighbours have no shared arc to meet on, and the rendezvous
			# would drag one of them across the other's lane.
			for i: int in range(1, colors.size()):
				var previous: int = COLORS.find(colors[i - 1])
				var current: int = COLORS.find(colors[i])
				if posmod(current - previous, COLORS.size()) != 1:
					contiguous = false
			for color: String in colors:
				seen.append(color)
		seen.sort()
		var expected: Array[String] = COLORS.duplicate()
		expected.sort()
		if seen != expected or not contiguous or not within_cap:
			_check("wave %d partitions the wheel into contiguous runs" % (wave_idx + 1), false,
				"groups=%s" % [groups])
			manager.queue_free()
			return
	_check("every wave partitions the wheel into contiguous runs of neighbours", true)

	# The escalation itself, read off the settings rather than hardcoded here.
	var solo_wave: int = GameSettings.wave_alliance_start_wave - 2
	_check("colours arrive alone before wave %d" % GameSettings.wave_alliance_start_wave,
		manager._max_group_size(solo_wave) == 1)
	_check("allied pairs from wave %d" % GameSettings.wave_alliance_start_wave,
		manager._max_group_size(GameSettings.wave_alliance_start_wave - 1) == 2)
	_check("three-colour shards from wave %d" % GameSettings.wave_shard_start_wave,
		manager._max_group_size(GameSettings.wave_shard_start_wave - 1) == 3)
	_check("the whole wheel from wave %d" % GameSettings.wave_grand_alliance_start_wave,
		manager._max_group_size(GameSettings.wave_grand_alliance_start_wave - 1) == COLORS.size())
	manager.queue_free()


func _test_wave_plans() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	for wave_idx: int in range(0, 24):
		manager.current_wave = wave_idx
		var groups: Array = manager._plan_wave(wave_idx)
		if groups.is_empty():
			_check("wave %d plans something" % (wave_idx + 1), false)
			continue
		var units: int = manager._count_units(groups)
		if units <= 0:
			_check("wave %d sends enemies" % (wave_idx + 1), false)
			continue
		# Every squad must be a single colour standing in its own lane. The colour mixing
		# happens at the rendezvous, not in the spawn.
		for group: Dictionary in groups:
			for plan: Dictionary in group["squads"]:
				if manager._color_to_lane_index(String(plan["color"])) != int(plan["lane"]):
					_check("wave %d: squads spawn in their own lane" % (wave_idx + 1), false)
					manager.queue_free()
					return
	_check("every wave from 1 to 24 plans squads into their own lanes", true)

	# The first wave is the authored one and must still be exactly what it was: a bare
	# melee screen from every colour, arriving alone.
	manager.current_wave = 0
	var first: Array = manager._plan_wave(0)
	_check("wave 1 is five solo groups", first.size() == COLORS.size(),
		"got %d groups" % first.size())
	_check("wave 1 is 15 enemies", manager._count_units(first) == 15,
		"got %d" % manager._count_units(first))
	var all_melee: bool = true
	for group: Dictionary in first:
		if (group["colors"] as PackedStringArray).size() != 1:
			all_melee = false
		for plan: Dictionary in group["squads"]:
			for unit: Dictionary in plan["units"]:
				if String(unit["type"]) != "Melee":
					all_melee = false
	_check("wave 1 is melee only, one colour per group", all_melee)

	# A boss leads its wave, alone, so it is never buried inside a warband's rendezvous.
	manager.current_wave = GameSettings.wave_boss_interval - 1
	var boss_wave: Array = manager._plan_wave(GameSettings.wave_boss_interval - 1)
	var boss_group: Dictionary = boss_wave[0]
	var boss_units: int = 0
	for plan: Dictionary in boss_group["squads"]:
		for unit: Dictionary in plan["units"]:
			if String(unit["type"]) == "Boss":
				boss_units += 1
	_check("wave %d leads with a boss, on its own" % GameSettings.wave_boss_interval,
		boss_units > 0 and (boss_group["colors"] as PackedStringArray).size() == 1
			and manager._count_units([boss_group]) == boss_units,
		"boss units %d in a group of %d" % [boss_units, manager._count_units([boss_group])])
	# Rendezvous points are per squad, not per group - each one converges part of the way
	# towards its battle group's centre rather than everyone meeting on one spot. A colour
	# arriving on its own has nobody to converge with, and neither does a boss.
	_check("a lone colour gets no rendezvous",
		not manager._rally_point("White", PackedStringArray(["White"])).is_finite())
	_check("a four-colour push gets no rendezvous either",
		not manager._rally_point("White", PackedStringArray(["White", "Blue", "Black", "Red"])).is_finite())

	# Planning is seeded off the wave number, so the same wave is the same wave. Without
	# it a bug report cannot be read back.
	manager.current_wave = 11
	var a: Array = manager._plan_wave(11)
	var b: Array = manager._plan_wave(11)
	_check("a wave plan is reproducible", manager._count_units(a) == manager._count_units(b),
		"%d vs %d" % [manager._count_units(a), manager._count_units(b)])
	manager.queue_free()


# --- helpers -------------------------------------------------------------------------

func _min_z(positions: Array) -> float:
	var value: float = INF
	for position: Vector3 in positions:
		value = minf(value, position.z)
	return value


func _max_z(positions: Array) -> float:
	var value: float = -INF
	for position: Vector3 in positions:
		value = maxf(value, position.z)
	return value


func _mean_z(positions: Array) -> float:
	if positions.is_empty():
		return 0.0
	var total: float = 0.0
	for position: Vector3 in positions:
		total += position.z
	return total / float(positions.size())


func _centroid(positions: Array) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for position: Vector3 in positions:
		total += Vector2(position.x, position.z)
	return total / float(positions.size())


func _min_radius(positions: Array, about: Array) -> float:
	var centre: Vector2 = _centroid(about)
	var value: float = INF
	for position: Vector3 in positions:
		value = minf(value, (Vector2(position.x, position.z) - centre).length())
	return value


func _max_radius(positions: Array, about: Array) -> float:
	var centre: Vector2 = _centroid(about)
	var value: float = 0.0
	for position: Vector3 in positions:
		value = maxf(value, (Vector2(position.x, position.z) - centre).length())
	return value


## Widest angular gap between consecutive bearings, subtracted from a full turn: how much
## of the circle around the mages the archers actually cover.
func _angular_spread(positions: Array, about: Array) -> float:
	if positions.size() < 2:
		return 0.0
	var centre: Vector2 = _centroid(about)
	var angles: Array[float] = []
	for position: Vector3 in positions:
		var offset: Vector2 = Vector2(position.x, position.z) - centre
		angles.append(offset.angle())
	angles.sort()
	var widest_gap: float = TAU - (angles[angles.size() - 1] - angles[0])
	for i: int in range(1, angles.size()):
		widest_gap = maxf(widest_gap, angles[i] - angles[i - 1])
	return TAU - widest_gap


func _spread(positions: Array) -> float:
	var lowest: Vector2 = Vector2.INF
	var highest: Vector2 = -Vector2.INF
	for position: Vector3 in positions:
		lowest = lowest.min(Vector2(position.x, position.z))
		highest = highest.max(Vector2(position.x, position.z))
	return (highest - lowest).length()
