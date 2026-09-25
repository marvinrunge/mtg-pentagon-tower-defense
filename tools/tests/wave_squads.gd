extends Node
## Regression test: a wave arrives as marching formations, not as a trickle of individuals.
##
## Run with:  godot --headless --path . res://tools/tests/wave_squads.tscn
##
## This is the live half of the wave rework - tools/tests/wave_formations.tscn covers the
## geometry and the planning on their own, and this one boots the actual map and watches a
## wave walk down a lane. Five things have to still be true, and every one of them was
## false at some point in this system's life:
##
##   1. The whole squad spawned AT ONCE. Counted on the frame the first battle group lands:
##      a colour's mages used to arrive long after the melee meant to be screening them.
##   2. The formation is still a formation half a minute later - every member within its
##      colour's leash of its own slot.
##   3. The archers and mages are still BEHIND the melee screen. This is the one that pays
##      for all of it, and it only holds because the squad marches at its slowest member's
##      pace rather than at each member's own.
##   4. Allied neighbours reach their rendezvous and charge together.
##   5. Every formation slot lands within reach of the baked navmesh, for every colour and
##      at every head count the run reaches - see _check_formation_reachability for the
##      two real bugs this pins down, one at wave 3 and one at wave 13.
##
## Measured in GAME SECONDS, not frames. Headless renders as fast as the CPU allows while
## physics still steps at its fixed rate, so a frame counter here would sample a couple of
## seconds into a march that takes a minute - which is exactly the mistake this comment
## exists to stop someone repeating. Engine.time_scale then buys the march back in real
## time: the whole run is about forty seconds on the wall.

## Wave 1 is deliberately a bare melee screen, which has no casters to stand behind
## anything, so the test re-rolls onto the first wave that fields the full melee / archer /
## mage shape AND pairs allied colours into warbands.
const TEST_WAVE_INDEX: int = 3
const TIME_SCALE: float = 4.0
## Far enough in that the melee would long since have outrun the mages without the march
## speed cap - a 2.5-speed melee and a 1.5-speed mage drift 25 units apart in that time.
const MARCH_SECONDS: float = 25.0
## The last battle group of a wave lands about thirty seconds in and then walks eighty-odd
## units to its hold line at a mage's pace.
const RALLY_SECONDS: float = 150.0

## WaveManager existing is not the same moment its navmesh queries start answering
## correctly: NavigationServer3D syncs a freshly baked region into its queryable map over
## a few physics frames of its own, AFTER bake_navigation_mesh() has already returned and
## AFTER main.gd's own two-frame wait for collision shapes. Measured empirically at 12-13
## frames for the last lane to settle; this waits comfortably past that before trusting
## map_get_closest_point for the reachability check below. Nothing else in this file reads
## the navmesh this early, which is why only this one check needed it.
const NAV_SETTLE_FRAMES: int = 20

## Wave INDICES (wave number minus one) the reachability check samples. Wave 3 is where
## the first off-map bug showed up and wave 13 the second; the rest walk the curve out
## past anything a run realistically reaches, because head count is what drives the reach.
const REACHABILITY_WAVES: Array[int] = [2, 6, 12, 15, 19, 24, 29]

var _elapsed: float = 0.0
var _started: bool = false
var _done: bool = false
var _failures: Array[String] = []
var _marched_checks: int = 0
var _scene: Node = null
var _manager: Node = null
var _spawned_at_deploy: int = -1
var _saw_rendezvous: bool = false
var _saw_charge: bool = false
var _settle_frames: int = 0


func _ready() -> void:
	Engine.time_scale = TIME_SCALE


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not _started:
		# Retried rather than done once: MainController builds the WaveManager only after it
		# has baked the map's navigation, which is several steps after this node exists.
		# Giving up on the first step left the test watching wave 1 - five solo melee
		# screens, no casters and no warbands - and quietly checking nothing.
		if not _resolve():
			return
		_settle_frames += 1
		if _settle_frames < NAV_SETTLE_FRAMES:
			return
		_started = true
		_start_test_wave()
		return
	_elapsed += delta
	if _spawned_at_deploy < 0:
		_sample_deploy()
	_watch_warbands()
	if _marched_checks == 0 and _elapsed >= MARCH_SECONDS:
		_check_march()
		_marched_checks = 1
		return
	if _elapsed < RALLY_SECONDS:
		return
	_done = true
	_check_warbands()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _resolve() -> bool:
	_scene = get_tree().current_scene
	if _scene == null:
		return false
	_manager = _scene.get_node_or_null("WaveManager")
	return _manager != null


## Re-rolls the run onto TEST_WAVE_INDEX before anything has spawned. Cheaper and far more
## stable than playing four waves out.
func _start_test_wave() -> void:
	if not _resolve():
		return
	_check_formation_reachability()
	_manager.current_wave = TEST_WAVE_INDEX
	_manager.start_next_wave()


## Regression guard for two real bugs, both the same shape: a formation slot placed where
## the map is not, on a squad that then spends its march walking at a place that does not
## exist. Enemies are SPAWNED snapped onto the mesh (WaveManager._spawn_unit snaps the
## position) but they path to their SLOT, so a slot off the mesh strands whoever holds it
## - and a wave with a stranded enemy in it can never be finished.
##
##   Wave 3   Blue's caster_setback shoved its mage and archer BEHIND the spawner, off the
##            far edge of the mesh. Fixed by applying the setback forwards instead.
##   Wave 13  The same failure from the other direction, and the reason this check is no
##            longer wave 3 only: the mage core stacks its rows backward, the archer shell
##            is a ring AROUND that core, and Red's mob biases its casters backward - so
##            every colour reaches further behind its anchor the more it fields. At wave
##            3's one mage and one archer nothing reached back at all, which is why the
##            wave-3 fix looked complete; by wave 13 White, Blue and Red hung seven to
##            nine units off the back of their lanes, against about four units of mesh.
##            Fixed by SquadDoctrine._anchor_at_rear.
##
## Waves are sampled across the whole curve rather than at one authored composition, since
## the reach is a function of head count: wave 3 for the original bug, then on through the
## twenties where a colour fields thirty-odd units. Compositions come from the planner
## itself, so this tracks any future retuning of the difficulty curve for free.
##
## The tolerance is relative to the SPAWNER'S OWN baseline snap distance rather than a bare
## number: NavigationMesh baking insets the walkable surface from the raw lane polygon by
## its own agent_radius, so even the spawner marker itself does not sit exactly ON the
## mesh - only a slot that lands meaningfully FURTHER off than the spawner already is
## signals a real problem.
func _check_formation_reachability() -> void:
	if _scene == null or _scene.nav_region == null:
		return
	var nav_map: RID = _scene.nav_region.get_navigation_map()

	for wave_idx: int in REACHABILITY_WAVES:
		var plan_rng := RandomNumberGenerator.new()
		plan_rng.seed = hash("wave:%d:%d" % [wave_idx, PlayerRegistry.count()])
		var per_color: Dictionary = _manager._compose_wave(wave_idx, plan_rng)
		var worst: float = 0.0
		var worst_color: String = ""
		var tolerance: float = INF
		for color: String in WaveManager.LANE_COLORS:
			var counts: Dictionary = per_color.get(color, {})
			if counts.is_empty():
				continue
			var lane_index: int = _manager._color_to_lane_index(color)
			if _scene.enemy_spawners.size() <= lane_index:
				continue
			var spawner: Node3D = _scene.enemy_spawners[lane_index] as Node3D
			var origin: Vector3 = spawner.global_position
			var forward: Vector3 = Vector3(spawner.global_transform.basis.z.x, 0.0, spawner.global_transform.basis.z.z).normalized()
			var baseline: float = origin.distance_to(NavigationServer3D.map_get_closest_point(nav_map, origin))
			tolerance = minf(tolerance, baseline + 1.5)

			# The deploy's own seed, so this measures the formation the wave would really
			# build rather than a differently jittered one.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%s:%d:%d" % [color, wave_idx, lane_index])
			var slots: Dictionary = SquadDoctrine.build_formation(color, counts, rng)
			for unit_type: String in slots:
				for offset: Vector3 in (slots[unit_type] as Array):
					var world: Vector3 = SquadDoctrine.to_world(origin, forward, offset)
					var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, world)
					var off_mesh: float = world.distance_to(snapped)
					if off_mesh > worst:
						worst = off_mesh
						worst_color = color
		if tolerance == INF:
			continue
		_check("wave %d's formations stay within reach of the navmesh" % (wave_idx + 1),
			worst <= tolerance,
			"%s was worst at %.2f off (tolerance %.2f)" % [worst_color, worst, tolerance])


## A battle group lands in ONE step, so the enemy count on the first step anything exists is
## also the size of everything that arrived together. In the old trickle it was 1.
func _sample_deploy() -> void:
	if not _resolve():
		return
	var standing: int = get_tree().get_nodes_in_group("enemies").size()
	if standing > 0:
		_spawned_at_deploy = standing


## Rallying and charging are transient - a squad holds for a few seconds and then frees
## itself on contact - so they are watched every step rather than sampled.
func _watch_warbands() -> void:
	if _manager == null:
		return
	for child: Node in _manager.get_children():
		if not (child is EnemySquad):
			continue
		var squad: EnemySquad = child as EnemySquad
		if squad.warband.size() < 2:
			continue
		if squad.rally_point.is_finite() and squad._rallied:
			_saw_rendezvous = true
		if squad.state == EnemySquad.State.CHARGE:
			_saw_charge = true


func _check_march() -> void:
	if not _resolve():
		_check("the map has a WaveManager", false)
		return

	print("Deployment")
	_check("a battle group lands as a whole squad, not one enemy at a time",
		_spawned_at_deploy >= 4, "%d enemies on the map the step the first group landed" % _spawned_at_deploy)

	var squads: Array = []
	for child: Node in _manager.get_children():
		if child is EnemySquad:
			squads.append(child)
	_check("the wave created squads", not squads.is_empty(), "%d squads" % squads.size())
	if squads.is_empty():
		return

	print("March at %.0f seconds" % _elapsed)
	var crystal: Vector3 = _crystal_position()
	var marched: bool = false
	var in_slot: bool = true
	var worst_gap: float = 0.0
	var worst_color: String = ""
	var casters_behind: bool = true
	var casters_checked: int = 0

	for squad: EnemySquad in squads:
		if _flat(squad.anchor, crystal) < _lane_distance(squad.lane_index, crystal) - 10.0:
			marched = true

		var melee_front: float = INF
		var caster_front: float = INF
		for enemy: Node in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.squad != squad or enemy.enemy_data == null:
				continue
			var gap: float = enemy.global_position.distance_to(squad.formation_target(enemy))
			if gap > worst_gap:
				worst_gap = gap
				worst_color = squad.color
			if gap > squad.leash():
				in_slot = false
			# Measured along the SQUAD's own line of advance rather than towards the
			# crystal: a warband converging on its hold line is not pointed straight at the
			# crystal, and "in front" means in front of the formation.
			var ahead: float = (enemy.global_position - squad.anchor).dot(squad.forward)
			if enemy.enemy_data.enemy_class == "Melee":
				melee_front = minf(melee_front, ahead)
			elif enemy.enemy_data.enemy_class == "Mage" or enemy.enemy_data.enemy_class == "Ranged":
				caster_front = minf(caster_front, ahead)
		# Only meaningful for a squad that actually fields both, and only for the ranked
		# doctrines - Red's mob has no ranks to hold by design.
		if is_finite(melee_front) and is_finite(caster_front) and squad.color != "Red":
			casters_checked += 1
			if melee_front <= caster_front:
				casters_behind = false

	_check("squads advance down their lane", marched)
	_check("members still hold their slots", in_slot,
		"worst gap %.1f (%s)" % [worst_gap, worst_color])
	_check("archers and mages are still behind the melee screen",
		casters_behind and casters_checked > 0,
		"checked %d squads" % casters_checked)


func _check_warbands() -> void:
	print("Warbands")
	_check("allied squads reach their rendezvous", _saw_rendezvous)
	_check("the warband then charges together", _saw_charge)
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


func _crystal_position() -> Vector3:
	var crystals: Array[Node] = get_tree().get_nodes_in_group("crystal")
	if not crystals.is_empty() and crystals[0] is Node3D:
		return (crystals[0] as Node3D).global_position
	return Vector3.ZERO


func _lane_distance(lane_index: int, crystal: Vector3) -> float:
	if _scene == null or _scene.enemy_spawners.size() <= lane_index:
		return 0.0
	return _flat((_scene.enemy_spawners[lane_index] as Node3D).global_position, crystal)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
