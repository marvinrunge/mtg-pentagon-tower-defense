extends Node
class_name WaveManager

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

var current_wave: int = 0
var wave_timer: float = 0.0
var spawn_timer: float = 0.0

var is_spawning: bool = false
var enemies_to_spawn: Array = []
var next_spawn_index: int = 0
var active_enemies: int = 0
var waiting_for_reward: bool = false

# The configuration for waves. Each wave is an array of dictionaries.
# Each round now spawns enemies on ALL colors.
var waves = [
	[ # Wave 1
		{ "color": "White", "type": "Melee", "count": 3 },
		{ "color": "Blue", "type": "Melee", "count": 3 },
		{ "color": "Black", "type": "Melee", "count": 3 },
		{ "color": "Red", "type": "Melee", "count": 3 },
		{ "color": "Green", "type": "Melee", "count": 3 }
	],
	[ # Wave 2
		{ "color": "White", "type": "Ranged", "count": 3 },
		{ "color": "Blue", "type": "Ranged", "count": 3 },
		{ "color": "Black", "type": "Melee", "count": 5 },
		{ "color": "Red", "type": "Ranged", "count": 3 },
		{ "color": "Green", "type": "Melee", "count": 5 }
	],
	[ # Wave 3
		{ "color": "White", "type": "Mage", "count": 1 },
		{ "color": "Blue", "type": "Mage", "count": 1 },
		{ "color": "Black", "type": "Melee", "count": 10 },
		{ "color": "Red", "type": "Mage", "count": 1 },
		{ "color": "Green", "type": "Mage", "count": 1 }
	]
]



var main_controller: Node3D

func _ready() -> void:
	SignalBus.enemy_died.connect(_on_enemy_died)
	SignalBus.wave_reward_selected.connect(_on_wave_reward_selected)

func start_waves(controller: Node3D) -> void:
	main_controller = controller
	current_wave = 0
	start_next_wave()

func start_next_wave() -> void:
	if current_wave >= waves.size():
		var dynamic_wave = _generate_dynamic_wave(current_wave)
		waves.append(dynamic_wave)
		
	print("Starting Wave: ", current_wave + 1)
	wave_started.emit(current_wave + 1)
	SignalBus.wave_started.emit(current_wave + 1)
	
	# Load wave config
	var wave_config = waves[current_wave]
	enemies_to_spawn.clear()
	next_spawn_index = 0
	
	var is_first_group: bool = true
	for group in wave_config:
		var initial_delay: float = GameSettings.wave_initial_warning_time if is_first_group else GameSettings.wave_delay_between_colors
		is_first_group = false
		
		for i in range(group["count"]):
			var spawn_delay: float = initial_delay if i == 0 else max(GameSettings.wave_spawn_delay_min, GameSettings.wave_spawn_delay_base - (current_wave * GameSettings.wave_spawn_delay_scaling))
			var spawn_info: Dictionary = {
				"color": group["color"],
				"type": group["type"],
				"delay": spawn_delay,
				"group_start": i == 0,
				"elite": "",
				"index": i,
				"total": group["count"]
			}
			enemies_to_spawn.append(spawn_info)

	_assign_elites()
	
	is_spawning = true
	spawn_timer = enemies_to_spawn[0]["delay"] if enemies_to_spawn.size() > 0 else 1.0
	if not enemies_to_spawn.is_empty():
		_emit_lane_warning(enemies_to_spawn[0])
	_emit_wave_state()

func _process(delta: float) -> void:
	if not is_spawning:
		return
		
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_next_enemy()

func spawn_next_enemy() -> void:
	if next_spawn_index >= enemies_to_spawn.size():
		is_spawning = false
		return
		
	var info = enemies_to_spawn[next_spawn_index]
	next_spawn_index += 1
	
	# Determine spawn lane based on color identity
	var lane_idx = _color_to_lane_index(info["color"])
	
	if main_controller and main_controller.enemy_spawners.size() > lane_idx:
		var spawner = main_controller.enemy_spawners[lane_idx]
		var enemy = enemy_scene.instantiate()
		
		# V-shape formation logic
		var idx = info["index"]
		var row = floor(float(idx) / 2.0)
		var side = 1.0 if (idx % 2 == 1) else -1.0
		if idx == 0: side = 0.0 # Center point
		
		# Spawner local axes: basis.z points backward (away from crystal), basis.x points right
		var offset = (spawner.global_transform.basis.z * row * 3.0) + (spawner.global_transform.basis.x * side * 3.0)
		
		# Add a tiny bit of random jitter so they aren't completely rigid
		offset += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))

		var desired_spawn_position: Vector3 = spawner.global_position + offset
		var navigation_map: RID = main_controller.nav_region.get_navigation_map()
		var navigable_spawn_position: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			desired_spawn_position
		)
		enemy.position = main_controller.to_local(navigable_spawn_position + Vector3(0, 0.5, 0))
		enemy.set_meta("target_crystal", main_controller.crystal_anchor)
		if info["elite"] != "":
			enemy.set_meta("elite_modifier", info["elite"])
		main_controller.add_child(enemy)
		
		# Apply data
		var data = EnemyDatabase.get_enemy_data(info["color"], info["type"])
		enemy.setup(data)
		
		active_enemies += 1
		
	if next_spawn_index < enemies_to_spawn.size():
		spawn_timer = enemies_to_spawn[next_spawn_index]["delay"]
		if enemies_to_spawn[next_spawn_index]["group_start"]:
			_emit_lane_warning(enemies_to_spawn[next_spawn_index])
	else:
		is_spawning = false
		
		# If somehow we already killed everything before the last spawn, trigger next immediately
		if active_enemies <= 0:
			_trigger_next_wave()

	_emit_wave_state()

func _color_to_lane_index(color: String) -> int:
	match color:
		"White": return 0
		"Blue": return 1
		"Black": return 2
		"Red": return 3
		"Green": return 4
	return randi() % 5

func _on_enemy_died() -> void:
	active_enemies = maxi(0, active_enemies - 1)
	_emit_wave_state()
	if active_enemies <= 0 and not is_spawning:
		_trigger_next_wave()

func register_enemy() -> void:
	active_enemies += 1
	_emit_wave_state()

func _trigger_next_wave() -> void:
	if waiting_for_reward:
		return
	print("Wave ", current_wave + 1, " Completed!")
	wave_completed.emit(current_wave + 1)
	SignalBus.wave_completed.emit(current_wave + 1)
	current_wave += 1
	waiting_for_reward = true
	SignalBus.wave_reward_offered.emit(_get_reward_options())

func _on_wave_reward_selected(_reward_id: String) -> void:
	if not waiting_for_reward:
		return
	waiting_for_reward = false
	var rest_timer: SceneTreeTimer = get_tree().create_timer(GameSettings.wave_rest_period)
	rest_timer.timeout.connect(start_next_wave)

func _assign_elites() -> void:
	if current_wave + 1 < GameSettings.wave_elite_start_wave:
		return

	var candidates: Array[int] = []
	for index in range(enemies_to_spawn.size()):
		if enemies_to_spawn[index]["type"] != "Boss":
			candidates.append(index)

	var elite_count: int = mini(GameSettings.wave_elite_count_base + current_wave / 5, candidates.size())
	for _elite_index in range(elite_count):
		var candidate_position: int = randi_range(0, candidates.size() - 1)
		var spawn_index: int = candidates.pop_at(candidate_position)
		enemies_to_spawn[spawn_index]["elite"] = _pick_elite_modifier()

func _pick_elite_modifier() -> String:
	const MODIFIERS: Array[String] = ["Haste", "Regenerator", "Juggernaut", "Crystal Hunter"]
	return MODIFIERS[randi() % MODIFIERS.size()]

func _emit_lane_warning(spawn_info: Dictionary) -> void:
	var lane_name: String = spawn_info["color"]
	var enemy_type: String = spawn_info["type"]
	var message: String = "%s LANE - %s ASSAULT" % [lane_name.to_upper(), enemy_type.to_upper()]
	if spawn_info["elite"] != "":
		message += " - ELITE %s" % String(spawn_info["elite"]).to_upper()
	SignalBus.lane_warning_requested.emit(lane_name, message, _get_lane_color(lane_name))

func _get_lane_color(lane_name: String) -> Color:
	match lane_name:
		"White": return Color(0.95, 0.95, 0.85)
		"Blue": return Color(0.25, 0.55, 1.0)
		"Black": return Color(0.65, 0.35, 0.8)
		"Red": return Color(1.0, 0.25, 0.2)
		"Green": return Color(0.25, 0.85, 0.35)
		_: return Color.WHITE

func _emit_wave_state() -> void:
	var pending_enemies: int = maxi(0, enemies_to_spawn.size() - next_spawn_index)
	SignalBus.wave_state_changed.emit(current_wave + 1, active_enemies + pending_enemies)

func _get_reward_options() -> Array:
	return [
		{
			"id": "power_surge",
			"title": "Power Surge",
			"description": "+15% player damage for this run"
		},
		{
			"id": "arcane_tempo",
			"title": "Arcane Tempo",
			"description": "+12% cooldown recovery for this run"
		},
		{
			"id": "crystal_repair",
			"title": "Crystal Repair",
			"description": "Restore 150 crystal integrity"
		}
	]

func _generate_dynamic_wave(wave_idx: int) -> Array:
	var wave_config = []
	var colors = ["White", "Blue", "Black", "Red", "Green"]
	var types = ["Melee", "Ranged", "Mage"]
	
	# Base difficulty
	var difficulty = GameSettings.wave_dynamic_base_difficulty + wave_idx * GameSettings.wave_dynamic_difficulty_per_wave
	
	# Add a boss every 5 waves
	if (wave_idx + 1) % GameSettings.wave_boss_interval == 0:
		wave_config.append({
			"color": colors[randi() % colors.size()],
			"type": "Boss",
			"count": 1 + wave_idx / 10,
			"delay": GameSettings.wave_boss_delay
		})
		difficulty -= 5
		
	while difficulty > 0:
		# Dynamic waves now ensure we spawn at least something on all 5 colors
		for c in colors:
			var t = types[randi() % types.size()]
			var count = 2 + randi() % 3 + (wave_idx / 4)
			wave_config.append({
				"color": c,
				"type": t,
				"count": count
			})
			difficulty -= 2
		
	return wave_config
