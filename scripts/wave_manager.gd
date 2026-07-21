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
var active_enemies: int = 0

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
	
	# Load wave config
	var wave_config = waves[current_wave]
	enemies_to_spawn.clear()
	
	var is_first_group = true
	for group in wave_config:
		var initial_delay = 0.0 if is_first_group else GameSettings.wave_delay_between_colors
		is_first_group = false
		
		for i in range(group["count"]):
			var spawn_delay = initial_delay if i == 0 else max(GameSettings.wave_spawn_delay_min, GameSettings.wave_spawn_delay_base - (current_wave * GameSettings.wave_spawn_delay_scaling))
			var spawn_info = {
				"color": group["color"],
				"type": group["type"],
				"delay": spawn_delay,
				"index": i,
				"total": group["count"]
			}
			enemies_to_spawn.append(spawn_info)
			
	# Shuffle to mix them up if they have same delay, or just keep order.
	# For now, keep order.
	
	is_spawning = true
	spawn_timer = enemies_to_spawn[0]["delay"] if enemies_to_spawn.size() > 0 else 1.0

func _process(delta: float) -> void:
	if not is_spawning:
		return
		
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_next_enemy()

func spawn_next_enemy() -> void:
	if enemies_to_spawn.size() == 0:
		is_spawning = false
		return
		
	var info = enemies_to_spawn.pop_front()
	
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
		
		enemy.position = spawner.global_position + Vector3(0, 0.5, 0) + offset
		enemy.set_meta("target_crystal", main_controller.crystal_anchor)
		enemy.set_meta("formation_offset", offset)
		main_controller.add_child(enemy)
		
		# Apply data
		var data = EnemyDatabase.get_enemy_data(info["color"], info["type"])
		enemy.setup(data)
		
		active_enemies += 1
		
	if enemies_to_spawn.size() > 0:
		spawn_timer = enemies_to_spawn[0]["delay"]
	else:
		is_spawning = false
		
		# If somehow we already killed everything before the last spawn, trigger next immediately
		if active_enemies <= 0:
			_trigger_next_wave()

func _color_to_lane_index(color: String) -> int:
	match color:
		"White": return 0
		"Blue": return 1
		"Black": return 2
		"Red": return 3
		"Green": return 4
	return randi() % 5

func _on_enemy_died(_xp: int) -> void:
	active_enemies -= 1
	if active_enemies <= 0 and not is_spawning:
		_trigger_next_wave()

func register_enemy() -> void:
	active_enemies += 1

func _trigger_next_wave() -> void:
	print("Wave ", current_wave + 1, " Completed!")
	wave_completed.emit(current_wave + 1)
	current_wave += 1
	
	# Small 5s rest period before the new wave begins
	var t = get_tree().create_timer(GameSettings.wave_rest_period)
	t.timeout.connect(start_next_wave)

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
