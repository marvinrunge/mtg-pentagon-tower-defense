extends Node
## Regression test: a wave arrives as marching formations, not as a trickle of individuals.
##
## Run with:  godot --headless --path . res://tools/tests/wave_squads.tscn
##
## This is the live half of the wave rework - tools/tests/wave_formations.tscn covers the
## geometry and the planning on their own, and this one boots the actual map and watches a
## wave walk down a lane. Four things have to still be true a long way into the march, and
## every one of them was false in the old trickle:
##
##   1. The whole squad spawned AT ONCE. Counted on the frame the first battle group lands:
##      a colour's mages used to arrive long after the melee meant to be screening them.
##   2. The formation is still a formation half a minute later - every member within its
##      colour's leash of its own slot.
##   3. The archers and mages are still BEHIND the melee screen. This is the one that pays
##      for all of it, and it only holds because the squad marches at its slowest member's
##      pace rather than at each member's own.
##   4. Allied neighbours reach their rendezvous and charge together.
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
	_manager.current_wave = TEST_WAVE_INDEX
	_manager.start_next_wave()


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
