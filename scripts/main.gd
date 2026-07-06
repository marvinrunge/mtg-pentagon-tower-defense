extends Node3D
class_name MainController

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var myr_scene: PackedScene = preload("res://scenes/myr.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var skill_tree_scene: PackedScene = preload("res://scenes/skill_tree.tscn")
@export var base_ui_scene: PackedScene = preload("res://scenes/base_ui.tscn")

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var lanes_parent: Node3D = $NavigationRegion3D/Lanes
@onready var crystal_anchor: Marker3D = $NavigationRegion3D/CrystalAnchor

# Lists of markers for spawners and mana sources (populated from static nodes)
var mana_sources: Array[Node3D] = []
var enemy_spawners: Array[Node3D] = []

# Game state variables
var crystal_health: float = 1000.0
var max_crystal_health: float = 1000.0

var mana_pool: Dictionary = {
	"White": 0,
	"Blue": 0,
	"Black": 0,
	"Red": 0,
	"Green": 0
}

const LANE_NAMES = ["White", "Blue", "Black", "Red", "Green"]
var base_ui_instance: Control
var current_wall: Node3D = null

func _ready() -> void:
	SignalBus.crystal_damaged.connect(damage_crystal)
	SignalBus.mana_deposited.connect(add_mana)
	
	# Instantiate Skill Tree
	if skill_tree_scene:
		var st = skill_tree_scene.instantiate()
		add_child(st)
		
	# Instantiate Base UI
	if base_ui_scene:
		base_ui_instance = base_ui_scene.instantiate()
		add_child(base_ui_instance)
	
	# Populate mana sources and spawners from the static lanes
	for lane_name in LANE_NAMES:
		var lane_path = "NavigationRegion3D/Lanes/Lane_" + lane_name
		var lane_node = get_node(lane_path)
		if lane_node:
			var mana = lane_node.get_node("ManaSource")
			var spawner = lane_node.get_node("EnemySpawner")
			mana_sources.append(mana)
			enemy_spawners.append(spawner)
			
	# Bake navigation mesh
	call_deferred("bake_map_navigation")

func bake_map_navigation() -> void:
	print("Baking Navigation Mesh...")
	nav_region.bake_navigation_mesh(false)
	print("Navigation Mesh baked successfully!")
	
	# Wait two physics frames for the physics server to register all CSG collision shapes
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	spawn_entities()

func spawn_entities() -> void:
	# Spawn Player at center base
	if player_scene:
		var player = player_scene.instantiate()
		player.position = Vector3(0, 1.0, 0)
		player.name = "Player"
		add_child(player)
		print("Spawned Player at center.")
	
	# Spawn Myrs (one for each lane)
	if myr_scene:
		for i in range(5):
			var myr = myr_scene.instantiate()
			var angle_rad = deg_to_rad(i * 72.0)
			# Spawn offsetted slightly towards their lane
			myr.position = Vector3(sin(angle_rad) * 4.0, 0.75, -cos(angle_rad) * 4.0)
			myr.name = "Myr_" + LANE_NAMES[i]
			
			# Assign targets
			myr.set_meta("lane_index", i)
			myr.set_meta("target_mana_source", mana_sources[i])
			myr.set_meta("target_crystal", crystal_anchor)
			
			print("Spawned Myr for lane: ", LANE_NAMES[i])
			# WE NO LONGER SPAWN MYRS AUTOMATICALLY
			myr.queue_free()
			
	# Start Wave Manager
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.start_waves(self)

func damage_crystal(amount: float) -> void:
	crystal_health = max(0.0, crystal_health - amount)
	SignalBus.health_changed.emit(crystal_health, max_crystal_health)
		
	if crystal_health <= 0.0:
		game_over()

func add_mana(color: String, amount: int) -> void:
	if color == "":
		color = "Colorless"
	
	if mana_pool.has(color):
		mana_pool[color] += amount
	else:
		mana_pool["White"] += amount # Fallback
		
	SignalBus.mana_changed.emit(mana_pool)

func spend_any_mana(amount: int) -> bool:
	var total = 0
	for color in mana_pool.keys():
		total += mana_pool[color]
		
	if total < amount:
		return false
		
	var remaining_to_spend = amount
	for color in mana_pool.keys():
		if mana_pool[color] >= remaining_to_spend:
			mana_pool[color] -= remaining_to_spend
			remaining_to_spend = 0
			break
		else:
			remaining_to_spend -= mana_pool[color]
			mana_pool[color] = 0
			
	SignalBus.mana_changed.emit(mana_pool)
	return true

func can_afford(cost_dict: Dictionary) -> bool:
	var temp_pool = mana_pool.duplicate()
	
	# Check specific colors first
	for color in cost_dict.keys():
		if color == "Colorless":
			continue
		if not temp_pool.has(color) or temp_pool[color] < cost_dict[color]:
			return false
		temp_pool[color] -= cost_dict[color]
		
	# Check colorless
	if cost_dict.has("Colorless"):
		var colorless_needed = cost_dict["Colorless"]
		var total_remaining = 0
		for color in temp_pool.keys():
			total_remaining += temp_pool[color]
		if total_remaining < colorless_needed:
			return false
			
	return true

func spend_mana_cost(cost_dict: Dictionary) -> bool:
	if not can_afford(cost_dict):
		return false
		
	# Spend specific colors first
	for color in cost_dict.keys():
		if color == "Colorless":
			continue
		mana_pool[color] -= cost_dict[color]
		
	# Spend colorless
	if cost_dict.has("Colorless"):
		var remaining_to_spend = cost_dict["Colorless"]
		for color in mana_pool.keys():
			if remaining_to_spend <= 0:
				break
			if mana_pool[color] >= remaining_to_spend:
				mana_pool[color] -= remaining_to_spend
				remaining_to_spend = 0
			else:
				remaining_to_spend -= mana_pool[color]
				mana_pool[color] = 0
				
	SignalBus.mana_changed.emit(mana_pool)
	return true

func build_wall(wall_type: String) -> void:
	if current_wall:
		current_wall.queue_free()
		
	var wall_scene = load("res://scenes/wall.tscn")
	current_wall = wall_scene.instantiate()
	current_wall.position = crystal_anchor.position
	add_child(current_wall)
	
	if current_wall.has_method("setup"):
		current_wall.setup(wall_type)
		
	print("Built wall: ", wall_type)

func trigger_red_wall() -> void:
	if current_wall and current_wall.has_method("trigger_fire_wave"):
		current_wall.trigger_fire_wave()

func revive_bone_wall() -> void:
	if current_wall and current_wall.has_method("revive_bone_wall"):
		current_wall.revive_bone_wall()

func game_over() -> void:
	SignalBus.game_over.emit()
	if has_node("WaveManager"):
		get_node("WaveManager").set_process(false)
