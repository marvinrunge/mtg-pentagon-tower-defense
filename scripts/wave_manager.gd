extends Node
class_name WaveManager

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)

@export var enemy_scene: PackedScene = preload("res://scenes/misc/enemy.tscn")

## Lane order around the pentagon. Index adjacency IS map adjacency (see MainController's
## Lane_* nodes), and it is also the MTG colour wheel - so index +/-1 is both the lane next
## door and the ALLIED colour, which is what makes a warband of neighbours mean something.
const LANE_COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const UNIT_TYPES: Array[String] = ["Melee", "Ranged", "Mage"]

## The authored opening, as squads rather than as a spawn queue.
##
## Waves 1-3 are the only handwritten ones; everything after is generated. Each entry maps
## a colour to the composition of its squad, and the composition is what the formation is
## built from - so wave 1 is a bare melee screen, wave 2 puts an archer behind it, and
## wave 3 is the first time a colour fields the full melee/archer/mage shape the rest of
## the run is made of.
##
## Head counts for waves 1 and 2 are exactly what they were when a wave was a queue; only
## the shape changed. Wave 3 used to be four lone mages plus ten Black melee, which was
## both SMALLER than wave 2 and impossible to read as a formation, so it was re-authored
## up to a real opening line.
const OPENING_WAVES: Array = [
	{
		"White": {"Melee": 3},
		"Blue": {"Melee": 3},
		"Black": {"Melee": 3},
		"Red": {"Melee": 3},
		"Green": {"Melee": 3},
	},
	{
		"White": {"Melee": 2, "Ranged": 1},
		"Blue": {"Melee": 2, "Ranged": 1},
		"Black": {"Melee": 4, "Ranged": 1},
		"Red": {"Melee": 2, "Ranged": 1},
		"Green": {"Melee": 4, "Ranged": 1},
	},
	{
		"White": {"Melee": 2, "Ranged": 1, "Mage": 1},
		"Blue": {"Melee": 2, "Ranged": 1, "Mage": 1},
		"Black": {"Melee": 4, "Ranged": 1, "Mage": 1},
		"Red": {"Melee": 2, "Ranged": 1, "Mage": 1},
		"Green": {"Melee": 2, "Ranged": 1, "Mage": 1},
	},
]

var current_wave: int = 0

## Battle groups still waiting to deploy, in order, and the countdown to the next one.
## A battle group is one or more ADJACENT colours that arrive together; see _plan_wave.
var pending_groups: Array = []
var group_timer: float = 0.0
## How many enemies this wave still has to put on the map. Only used for the HUD's
## "enemies remaining" figure, which counts the unspawned as well as the standing.
var pending_enemies: int = 0

var is_spawning: bool = false
var active_enemies: int = 0
## True from the moment a wave ends until Upkeep closes. Nothing may start the next
## wave while it is set - the Upkeep panel owns that transition.
var in_upkeep: bool = false

var main_controller: Node3D

func _ready() -> void:
	SignalBus.enemy_died.connect(_on_enemy_died)
	SignalBus.upkeep_finished.connect(_on_upkeep_finished)
	SignalBus.game_over.connect(_disband_squads)

func start_waves(controller: Node3D) -> void:
	main_controller = controller
	current_wave = 0
	# Only the server plans and deploys. A client's wave number arrives with the wave
	# itself (see _net_wave_started) - it used to be planned locally from random numbers,
	# which meant every peer announced a different lane and, because nothing ever advanced
	# it on a client, enemy health bars there were scaled to wave 1 for the whole run.
	if Net.is_server():
		start_next_wave()

func start_next_wave() -> void:
	if not Net.is_server():
		return
	pending_groups = _plan_wave(current_wave)
	pending_enemies = _count_units(pending_groups)
	group_timer = float(pending_groups[0]["delay"]) if not pending_groups.is_empty() else 1.0
	is_spawning = not pending_groups.is_empty()
	print("Starting Wave: ", current_wave + 1)
	_begin_wave(current_wave + 1)
	if Net.is_active():
		_net_wave_started.rpc(current_wave + 1)
	_emit_wave_state()

func _process(delta: float) -> void:
	# Waves are the server's. A client that also spawned would double every wave.
	if not Net.is_server():
		return
	if not is_spawning:
		return

	group_timer -= delta
	if group_timer <= 0.0:
		_deploy_next_group()

## One battle group hits the map: every squad in it spawns at once, already in formation.
##
## "At once" is the point of the whole rework. A colour used to trickle in one enemy every
## fraction of a second, so its mages arrived long after its melee were already dead and
## the player fought five separate queues rather than an army.
func _deploy_next_group() -> void:
	if pending_groups.is_empty():
		_finish_spawning()
		return

	var group: Dictionary = pending_groups.pop_front()
	var squads: Array = []
	for plan: Dictionary in group["squads"]:
		var squad: Node = _deploy_squad(plan, group)
		if squad != null:
			squads.append(squad)
	# One shared array instance, so every squad sees the same warband and exactly one of
	# them decides when the group is assembled.
	for squad: Node in squads:
		squad.warband = squads
	_announce_group(group)

	if pending_groups.is_empty():
		_finish_spawning()
	else:
		group_timer = float(pending_groups[0]["delay"])
	_emit_wave_state()


func _finish_spawning() -> void:
	is_spawning = false
	pending_enemies = 0
	# If somehow everything died before the last group landed, move straight on.
	if active_enemies <= 0:
		_trigger_next_wave()


## Spawns one colour's whole contingent in formation and hands it to an EnemySquad.
##
## Returns the squad, or null when the colour has no lane on this map or nothing to send.
## A boss is deliberately NOT given a squad: it is one unit, a formation of one is a point,
## and its own AI is already built around telegraphed specials rather than marching.
func _deploy_squad(plan: Dictionary, group: Dictionary) -> Node:
	var lane_index: int = int(plan["lane"])
	if main_controller == null or main_controller.enemy_spawners.size() <= lane_index:
		return null
	var spawner: Node3D = main_controller.enemy_spawners[lane_index]
	var color: String = String(plan["color"])
	var origin: Vector3 = spawner.global_position
	# basis.z of every lane's spawner points at the crystal (the lanes are a pentagon built
	# around it), so it doubles as the formation's forward axis.
	var forward: Vector3 = Vector3(spawner.global_transform.basis.z.x, 0.0, spawner.global_transform.basis.z.z).normalized()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [color, current_wave, lane_index])
	var slots: Dictionary = SquadDoctrine.build_formation(color, _composition_of(plan), rng)
	var taken: Dictionary = {}

	var squad: Node = null
	var units: Array = plan["units"]
	for unit: Dictionary in units:
		var unit_type: String = String(unit["type"])
		var slot_list: Array = slots.get(unit_type, [])
		var slot_index: int = int(taken.get(unit_type, 0))
		taken[unit_type] = slot_index + 1
		var offset: Vector3 = slot_list[slot_index] if slot_index < slot_list.size() else Vector3.ZERO
		var enemy: Node3D = _spawn_unit(color, unit_type, String(unit.get("elite", "")), bool(unit.get("miniboss", false)), origin, forward, offset)
		if enemy == null:
			continue
		if unit_type == "Boss":
			continue
		if squad == null:
			squad = _create_squad(color, lane_index, origin, forward, group)
		squad.add_member(enemy, offset)
	return squad


func _create_squad(color: String, lane_index: int, origin: Vector3, forward: Vector3, group: Dictionary) -> Node:
	var squad: EnemySquad = EnemySquad.new()
	squad.name = "Squad_%s_%d" % [color, current_wave + 1]
	add_child(squad)
	squad.configure(color, lane_index, origin, forward, _crystal_position())
	squad.rally_point = _rally_point(color, group["colors"])
	squad.charge_started.connect(_on_warband_charged)
	return squad


func _spawn_unit(color: String, unit_type: String, elite: String, miniboss: bool, origin: Vector3, forward: Vector3, offset: Vector3) -> Node3D:
	var desired: Vector3 = SquadDoctrine.to_world(origin, forward, offset)
	var navigation_map: RID = main_controller.nav_region.get_navigation_map()
	var navigable: Vector3 = NavigationServer3D.map_get_closest_point(navigation_map, desired)
	# Everything the enemy needs travels in the spawn argument, because a client rebuilds
	# the node from it and cannot see anything set on the server's copy.
	var enemy: Node3D = main_controller.request_enemy({
		"position": main_controller.to_local(navigable + Vector3(0, 0.5, 0)),
		"color": color,
		"type": unit_type,
		"elite": elite,
		"miniboss": miniboss,
	})
	if enemy != null:
		active_enemies += 1
		pending_enemies = maxi(0, pending_enemies - 1)
	return enemy


func _crystal_position() -> Vector3:
	var crystals: Array[Node] = get_tree().get_nodes_in_group("crystal")
	if not crystals.is_empty() and crystals[0] is Node3D:
		return (crystals[0] as Node3D).global_position
	return Vector3.ZERO


# ============================================================
# WAVE PLANNING
# ============================================================

## Builds the whole wave as an ordered list of BATTLE GROUPS.
##
## A battle group is a run of ADJACENT colours whose squads spawn together, walk to a
## shared rendezvous between their lanes, wait for each other and then charge the crystal
## as one. How many colours may share a group grows with the wave number, which is the
## run's real difficulty curve now: the same enemies arriving in two pushes of two-and-a-
## half lanes are a completely different fight from the same enemies arriving in five.
##
## Seeded off the wave number so the plan is reproducible - useful for reading a bug report
## back, and it means a re-rolled wave is the same wave.
func _plan_wave(wave_idx: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("wave:%d:%d" % [wave_idx, PlayerRegistry.count()])

	var per_color: Dictionary = _compose_wave(wave_idx, rng)
	var groups: Array = []

	# The boss leads, alone. It is the one arrival the player has to stop for, and burying
	# it inside a warband's rally would hide it behind thirty goblins.
	var boss_color: String = String(per_color.get("__boss__", ""))
	if boss_color != "":
		groups.append({
			"delay": GameSettings.wave_boss_delay,
			"colors": PackedStringArray([boss_color]),
			"squads": [{
				"color": boss_color,
				"lane": _color_to_lane_index(boss_color),
				"units": _units_of({"Boss": int(per_color["__boss_count__"])}),
			}],
		})
		per_color.erase("__boss__")
		per_color.erase("__boss_count__")

	var miniboss_color: String = String(per_color.get("__miniboss_color__", ""))
	var miniboss_class: String = String(per_color.get("__miniboss_class__", ""))
	per_color.erase("__miniboss_color__")
	per_color.erase("__miniboss_class__")

	var first: bool = groups.is_empty()
	for colors: PackedStringArray in _partition_colors(wave_idx, rng):
		var squads: Array = []
		for color: String in colors:
			var counts: Dictionary = per_color.get(color, {})
			if _total_of(counts) <= 0:
				continue
			squads.append({
				"color": color,
				"lane": _color_to_lane_index(color),
				"units": _units_of(counts),
			})
		if squads.is_empty():
			continue
		groups.append({
			"delay": GameSettings.wave_initial_warning_time if first else GameSettings.wave_delay_between_groups,
			"colors": colors,
			"squads": squads,
		})
		first = false

	# Miniboss first, elites second: _assign_elites skips whatever unit this flags, so a
	# rare miniboss can never also roll Haste or Juggernaut on top by pure coincidence and
	# quietly become a second boss in the same wave.
	_assign_miniboss(groups, miniboss_color, miniboss_class)
	_assign_elites(groups)
	return groups


## How many of each class each colour fields this wave.
##
## The budget arithmetic is unchanged from when waves were queues - same base, same growth
## per wave, same player-count factor, same two-difficulty-per-group cost - so the head
## count curve a run is balanced around did not move. All that changed is that a colour's
## draws are MERGED into one composition instead of becoming several separate spawn groups.
func _compose_wave(wave_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var per_color: Dictionary = {}
	for color: String in LANE_COLORS:
		per_color[color] = {}

	if wave_idx < OPENING_WAVES.size():
		for color: String in OPENING_WAVES[wave_idx]:
			per_color[color] = (OPENING_WAVES[wave_idx][color] as Dictionary).duplicate()
		return per_color

	# Base difficulty, scaled by how many players are actually here. Without this a
	# five-player team meets a solo-sized wave and never has to defend anything.
	var difficulty: int = GameSettings.wave_dynamic_base_difficulty + wave_idx * GameSettings.wave_dynamic_difficulty_per_wave
	difficulty = int(round(float(difficulty) * GameSettings.get_wave_size_factor(PlayerRegistry.count())))

	if (wave_idx + 1) % GameSettings.wave_boss_interval == 0:
		per_color["__boss__"] = LANE_COLORS[rng.randi() % LANE_COLORS.size()]
		per_color["__boss_count__"] = 1 + wave_idx / 10
		difficulty -= 5

	while difficulty > 0:
		for color: String in LANE_COLORS:
			var unit_type: String = UNIT_TYPES[rng.randi() % UNIT_TYPES.size()]
			var count: int = 2 + rng.randi() % 3 + wave_idx / 4
			var counts: Dictionary = per_color[color]
			counts[unit_type] = int(counts.get(unit_type, 0)) + count
			difficulty -= 2

	_roll_miniboss(wave_idx, per_color, rng)
	return per_color


## At most one miniboss per wave (see GameSettings' Minibosses block), so a hit is a
## genuinely notable arrival rather than a stat roll a player has learned to tune out.
## Picked here, in composition, rather than later alongside the elites: the escort bonus
## has to land BEFORE the wave is partitioned into squads, or the extra melee it adds would
## never get formation slots.
func _roll_miniboss(wave_idx: int, per_color: Dictionary, rng: RandomNumberGenerator) -> void:
	if wave_idx + 1 < GameSettings.wave_miniboss_start_wave:
		return
	if rng.randf() >= GameSettings.wave_miniboss_chance:
		return

	var candidates: Array = []
	for color: String in LANE_COLORS:
		var counts: Dictionary = per_color[color]
		for unit_type: String in UNIT_TYPES:
			if int(counts.get(unit_type, 0)) > 0:
				candidates.append([color, unit_type])
	if candidates.is_empty():
		return

	var picked: Array = candidates[rng.randi() % candidates.size()]
	per_color["__miniboss_color__"] = picked[0]
	per_color["__miniboss_class__"] = picked[1]

	# The escort: more melee for the SQUAD the miniboss stands in, regardless of which
	# class it actually is. The formation itself (melee screen in front - see
	# SquadDoctrine) turns that into a denser guard for free, no new formation geometry
	# required - a mage miniboss ends up with more bodies between it and the player exactly
	# the way an ordinary mage core does, just more of them.
	var escort_counts: Dictionary = per_color[picked[0]]
	escort_counts["Melee"] = int(escort_counts.get("Melee", 0)) + GameSettings.wave_miniboss_escort_bonus


## Splits the five colours into runs of NEIGHBOURS, each run one battle group.
##
## Group size is the escalation: solo lanes while the player is learning the map, then
## allied pairs, then three-colour shards, then the whole wheel at once. The starting
## offset rotates with the wave so it is not the same pairing every time.
func _partition_colors(wave_idx: int, rng: RandomNumberGenerator) -> Array:
	var total: int = LANE_COLORS.size()
	var max_size: int = _max_group_size(wave_idx)
	var start: int = rng.randi() % total
	var groups: Array = []
	var placed: int = 0
	while placed < total:
		var size: int = mini(max_size, total - placed)
		# Never leave exactly one colour over at the end. Five does not divide by two or
		# four, and a lone lane arriving as an afterthought behind a four-colour push is a
		# free lane. Shrinking this group rather than growing it keeps every group inside
		# the wave's cap: at a cap of two, five colours come as 2 + 1 + 2, with the odd one
		# in the middle instead of trailing.
		if size > 1 and total - placed - size == 1:
			size -= 1
		var colors: PackedStringArray = PackedStringArray()
		for offset: int in range(size):
			colors.append(LANE_COLORS[(start + placed + offset) % total])
		groups.append(colors)
		placed += size
	groups.shuffle()
	return groups


func _max_group_size(wave_idx: int) -> int:
	var wave: int = wave_idx + 1
	if wave >= GameSettings.wave_grand_alliance_start_wave:
		return LANE_COLORS.size()
	if wave >= GameSettings.wave_shard_start_wave:
		return 3
	if wave >= GameSettings.wave_alliance_start_wave:
		return 2
	return 1


## Where ONE squad of a battle group forms up before the group charges.
##
## Not a single shared point on the arc between the lanes: two neighbouring lanes are 72
## degrees apart, so meeting exactly in the middle means each squad walking an 80-unit
## sideways detour - most of a lane's length again, spent crossing ground with nothing on
## it. Instead each squad converges PART of the way towards the group's centre
## (wave_rally_convergence) and holds there. They end up close enough to read as one army
## massing, the detour stays a fraction of the march, and the lanes converge the rest of
## the way on their own as the charge closes on the crystal.
##
## Groups of one have nobody to meet. Groups of four or five do not get one either - the
## average direction of most of a pentagon points nowhere useful, and five lanes arriving
## at once is what a wave that big should feel like anyway.
func _rally_point(color: String, colors: PackedStringArray) -> Vector3:
	if colors.size() < 2 or colors.size() > 3 or main_controller == null:
		return Vector3.INF
	var crystal: Vector3 = _crystal_position()
	var own: Vector3 = _lane_outward(_color_to_lane_index(color), crystal)
	if own == Vector3.ZERO:
		return Vector3.INF
	var centre: Vector3 = Vector3.ZERO
	for other: String in colors:
		var outward: Vector3 = _lane_outward(_color_to_lane_index(other), crystal)
		if outward == Vector3.ZERO:
			return Vector3.INF
		centre += outward
	if centre.length_squared() < 0.04:
		return Vector3.INF
	var direction: Vector3 = own.lerp(centre.normalized(), GameSettings.wave_rally_convergence)
	if direction.length_squared() < 0.04:
		return Vector3.INF
	return crystal + direction.normalized() * GameSettings.wave_rally_radius


## Flat unit vector from the crystal out along a lane, measured off the lane's own spawner
## rather than computed as index * 72 degrees - a map edit that nudges a lane should move
## the rendezvous with it.
func _lane_outward(lane: int, crystal: Vector3) -> Vector3:
	if main_controller == null or main_controller.enemy_spawners.size() <= lane:
		return Vector3.ZERO
	var outward: Vector3 = main_controller.enemy_spawners[lane].global_position - crystal
	outward.y = 0.0
	if outward.length_squared() < 0.01:
		return Vector3.ZERO
	return outward.normalized()


## Flattens a composition into the individual units a squad is built from, biggest class
## first so the formation's front ranks are filled before its back ones.
func _units_of(counts: Dictionary) -> Array:
	var units: Array = []
	for unit_type: String in ["Boss", "Melee", "Ranged", "Mage"]:
		for _i: int in range(int(counts.get(unit_type, 0))):
			units.append({"type": unit_type, "elite": "", "miniboss": false})
	return units


func _composition_of(plan: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for unit: Dictionary in plan["units"]:
		var unit_type: String = String(unit["type"])
		counts[unit_type] = int(counts.get(unit_type, 0)) + 1
	return counts


func _total_of(counts: Dictionary) -> int:
	var total: int = 0
	for unit_type: String in counts:
		total += int(counts[unit_type])
	return total


func _count_units(groups: Array) -> int:
	var total: int = 0
	for group: Dictionary in groups:
		for plan: Dictionary in group["squads"]:
			total += (plan["units"] as Array).size()
	return total


## Flags the single unit _roll_miniboss chose, back when it still had to pick from raw
## class COUNTS rather than individual units - _units_of() had not been called yet at that
## point, so the actual Dictionary to flag only exists now that squads are built. Flags the
## FIRST unit of the chosen class in its squad: _units_of orders a squad's units class by
## class, and _deploy_squad hands out formation slots in that same list order, so "first of
## its class" is also the formation's front-and-centre slot for that class - the miniboss
## lands exactly where it should stand out, with no SquadDoctrine changes required.
func _assign_miniboss(groups: Array, color: String, unit_class: String) -> void:
	if color == "":
		return
	for group: Dictionary in groups:
		for plan: Dictionary in group["squads"]:
			if String(plan["color"]) != color:
				continue
			for unit: Dictionary in plan["units"]:
				if String(unit["type"]) == unit_class:
					unit["miniboss"] = true
					return


## Elites are drawn across the WHOLE wave rather than per squad, so a wave's elites can all
## land in one colour - which is a more interesting thing to run into than one guaranteed
## elite per lane.
func _assign_elites(groups: Array) -> void:
	if current_wave + 1 < GameSettings.wave_elite_start_wave:
		return
	var candidates: Array = []
	for group: Dictionary in groups:
		for plan: Dictionary in group["squads"]:
			for unit: Dictionary in plan["units"]:
				# Never the miniboss - see _assign_miniboss's own comment on why the two
				# are kept mutually exclusive rather than merely unrelated.
				if String(unit["type"]) != "Boss" and not bool(unit.get("miniboss", false)):
					candidates.append(unit)
	var elite_count: int = mini(GameSettings.wave_elite_count_base + current_wave / 5, candidates.size())
	for _elite_index in range(elite_count):
		var picked: int = randi_range(0, candidates.size() - 1)
		var unit: Dictionary = candidates.pop_at(picked)
		unit["elite"] = _pick_elite_modifier()


func _pick_elite_modifier() -> String:
	const MODIFIERS: Array[String] = ["Haste", "Regenerator", "Juggernaut", "Crystal Hunter"]
	return MODIFIERS[randi() % MODIFIERS.size()]


func _color_to_lane_index(color: String) -> int:
	var index: int = LANE_COLORS.find(color)
	return index if index >= 0 else randi() % LANE_COLORS.size()


# ============================================================
# WAVE LIFECYCLE
# ============================================================

func _on_enemy_died() -> void:
	active_enemies = maxi(0, active_enemies - 1)
	_emit_wave_state()
	if active_enemies <= 0 and not is_spawning:
		_trigger_next_wave()

func register_enemy() -> void:
	active_enemies += 1
	_emit_wave_state()

func _trigger_next_wave() -> void:
	if in_upkeep:
		return
	print("Wave ", current_wave + 1, " Completed!")
	_disband_squads()
	wave_completed.emit(current_wave + 1)
	SignalBus.wave_completed.emit(current_wave + 1)
	current_wave += 1
	# Upkeep, not a boon screen: the team spends its mana together and decides when to
	# move on. The next wave starts when the panel says so, never on a timer here.
	in_upkeep = true
	if Net.is_active():
		_net_upkeep_started.rpc(GameSettings.upkeep_duration)
	SignalBus.upkeep_started.emit(GameSettings.upkeep_duration)


## Nothing should be marching during Upkeep or after the crystal falls, and a squad whose
## members are all gone would free itself next frame anyway - this just makes it immediate.
func _disband_squads() -> void:
	for child: Node in get_children():
		if child is EnemySquad:
			(child as EnemySquad).disband()


@rpc("authority", "call_remote", "reliable")
func _net_upkeep_started(duration: float) -> void:
	in_upkeep = true
	SignalBus.upkeep_started.emit(duration)


## Only the server may actually start the next wave. A client reaching this just drops
## its own Upkeep flag - the wave arrives when the server's enemies do.
func _on_upkeep_finished() -> void:
	if not in_upkeep:
		return
	in_upkeep = false
	if not Net.is_server():
		return
	if Net.is_active():
		_net_upkeep_finished.rpc()
	start_next_wave()


@rpc("authority", "call_remote", "reliable")
func _net_upkeep_finished() -> void:
	in_upkeep = false
	SignalBus.upkeep_finished.emit()


func _begin_wave(wave_number: int) -> void:
	current_wave = wave_number - 1
	wave_started.emit(wave_number)
	SignalBus.wave_started.emit(wave_number)


## Carries the wave NUMBER as well as the fact of it. EnemyBase scales an enemy's maximum
## health off WaveManager.current_wave, and it does that on every peer - so a client whose
## wave counter never advanced was drawing wave-1 health bars over wave-20 enemies.
@rpc("authority", "call_remote", "reliable")
func _net_wave_started(wave_number: int) -> void:
	_begin_wave(wave_number)


# ============================================================
# ANNOUNCEMENTS
# ============================================================

## Banners are raised by the SERVER, when the thing they describe actually happens, and
## relayed. They used to be emitted locally on every peer from a locally planned wave,
## which meant a client was told about lanes that were never coming.
func _announce(lane_name: String, message: String) -> void:
	if Net.is_active():
		_net_announce.rpc(lane_name, message)
	_show_announcement(lane_name, message)


@rpc("authority", "call_remote", "reliable")
func _net_announce(lane_name: String, message: String) -> void:
	_show_announcement(lane_name, message)


func _show_announcement(lane_name: String, message: String) -> void:
	SignalBus.lane_warning_requested.emit(lane_name, message, _get_lane_color(lane_name))


func _announce_group(group: Dictionary) -> void:
	var colors: PackedStringArray = group["colors"]
	var lane_name: String = String(colors[0]) if not colors.is_empty() else ""
	var strength: int = 0
	var has_boss: bool = false
	var has_miniboss: bool = false
	for plan: Dictionary in group["squads"]:
		for unit: Dictionary in plan["units"]:
			strength += 1
			if String(unit["type"]) == "Boss":
				has_boss = true
			elif bool(unit.get("miniboss", false)):
				has_miniboss = true

	if has_boss:
		# A boss gets its own wording rather than "RED LANE - BOSS ASSAULT". It is the one
		# arrival the player has to stop what they are doing for, and it reads back in the
		# Tab log as an event rather than as one more lane warning among fifty. A miniboss
		# can never coincide with this - a Boss occupies its own dedicated group, never an
		# ordinary squad's unit list.
		_announce(lane_name, "%s BOSS HAS ARRIVED" % lane_name.to_upper())
		return

	# Appended to whichever wording follows rather than given its own branch - a miniboss
	# can land inside either a solo colour's warband or an alliance, and it is worth
	# calling out in both without duplicating the rest of the message.
	var miniboss_suffix: String = " - MINIBOSS SIGHTED" if has_miniboss else ""

	if colors.size() > 1:
		_announce(lane_name, "%s ALLIANCE MASSING - %d STRONG%s" % [_color_list(colors), strength, miniboss_suffix])
		return

	var banner: String = String(SquadDoctrine.get_doctrine(lane_name).get("banner", "WARBAND"))
	_announce(lane_name, "%s %s - %d STRONG%s" % [lane_name.to_upper(), banner, strength, miniboss_suffix])


func _on_warband_charged(colors: PackedStringArray) -> void:
	if colors.is_empty():
		return
	_announce(String(colors[0]), "%s ALLIANCE CHARGES" % _color_list(colors))


func _color_list(colors: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for color: String in colors:
		parts.append(color.to_upper())
	return " + ".join(parts)


func _get_lane_color(lane_name: String) -> Color:
	match lane_name:
		"White": return Color(0.95, 0.95, 0.85)
		"Blue": return Color(0.25, 0.55, 1.0)
		"Black": return Color(0.65, 0.35, 0.8)
		"Red": return Color(1.0, 0.25, 0.2)
		"Green": return Color(0.25, 0.85, 0.35)
		_: return Color.WHITE


func _emit_wave_state() -> void:
	SignalBus.wave_state_changed.emit(current_wave + 1, active_enemies + pending_enemies)
	if Net.is_active() and Net.is_server():
		_net_wave_state.rpc(current_wave + 1, active_enemies + pending_enemies)


## Enemy deaths are resolved on the server (EnemyBase.take_damage is server-only), so
## SignalBus.enemy_died never fires on a client and a client's own count could only ever
## drift upwards. The count travels instead.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_wave_state(wave_number: int, enemies_remaining: int) -> void:
	SignalBus.wave_state_changed.emit(wave_number, enemies_remaining)
