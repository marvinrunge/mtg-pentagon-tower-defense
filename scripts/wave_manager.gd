extends Node
class_name WaveManager

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_waves_completed()

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

var current_wave: int = 0
var wave_timer: float = 0.0
var spawn_timer: float = 0.0

var is_spawning: bool = false
var enemies_to_spawn: Array = []
var active_enemies: int = 0

# The configuration for waves. Each wave is an array of dictionaries:
# { "color": "Red", "type": "Melee", "count": 10, "delay": 1.0 }
var waves = [
	[ # Wave 1: 5 Red Melee, 1 per second
		{ "color": "Red", "type": "Melee", "count": 5, "delay": 1.0 }
	],
	[ # Wave 2: 5 Blue Ranged, slightly faster
		{ "color": "Blue", "type": "Ranged", "count": 5, "delay": 0.8 }
	],
	[ # Wave 3: Mix of White Melee and Green Mages
		{ "color": "White", "type": "Melee", "count": 5, "delay": 1.5 },
		{ "color": "Green", "type": "Mage", "count": 2, "delay": 4.0 }
	],
	[ # Wave 4: Black swarm
		{ "color": "Black", "type": "Melee", "count": 15, "delay": 0.5 }
	],
	[ # Wave 5: Red Boss and some minions
		{ "color": "Red", "type": "Boss", "count": 1, "delay": 0.0 },
		{ "color": "Red", "type": "Ranged", "count": 5, "delay": 2.0 }
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
	
	for group in wave_config:
		for i in range(group["count"]):
			var spawn_info = {
				"color": group["color"],
				"type": group["type"],
				"delay": group["delay"]
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
		enemy.position = spawner.global_position + Vector3(0, 0.5, 0)
		enemy.set_meta("target_crystal", main_controller.crystal_anchor)
		main_controller.add_child(enemy)
		
		# Apply data
		var data = EnemyDatabase.get_enemy_data(info["color"], info["type"])
		enemy.setup(data)
		
		active_enemies += 1
		
	if enemies_to_spawn.size() > 0:
		spawn_timer = enemies_to_spawn[0]["delay"]
	else:
		is_spawning = false

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
		# Wave clear
		print("Wave ", current_wave + 1, " Completed!")
		wave_completed.emit(current_wave + 1)
		current_wave += 1
		
		# Simple 5 second delay before next wave
		var t = get_tree().create_timer(5.0)
		t.timeout.connect(start_next_wave)

func _generate_dynamic_wave(wave_idx: int) -> Array:
	var wave_config = []
	var colors = ["White", "Blue", "Black", "Red", "Green"]
	var types = ["Melee", "Ranged", "Mage"]
	
	# Base difficulty
	var difficulty = 5 + wave_idx * 2
	
	# Add a boss every 5 waves
	if (wave_idx + 1) % 5 == 0:
		wave_config.append({
			"color": colors[randi() % colors.size()],
			"type": "Boss",
			"count": 1 + wave_idx / 10,
			"delay": 2.0
		})
		difficulty -= 5
		
	while difficulty > 0:
		var c = colors[randi() % colors.size()]
		var t = types[randi() % types.size()]
		var count = 3 + randi() % 5 + (wave_idx / 3) # Scales up over time
		var delay = max(0.2, 1.5 - (wave_idx * 0.05)) # Gets faster over time
		wave_config.append({
			"color": c,
			"type": t,
			"count": count,
			"delay": delay
		})
		difficulty -= 3
		
	return wave_config
