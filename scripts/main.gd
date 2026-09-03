extends Node3D
class_name MainController

@export var player_scene: PackedScene = preload("res://scenes/misc/player.tscn")
@export var myr_scene: PackedScene = preload("res://scenes/misc/myr.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/misc/enemy.tscn")
@export var skill_tree_scene: PackedScene = preload("res://scenes/ui/skill_tree.tscn")
@export var base_ui_scene: PackedScene = preload("res://scenes/ui/base_ui.tscn")

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var lanes_parent: Node3D = $NavigationRegion3D/Lanes
@onready var crystal_anchor: Marker3D = $NavigationRegion3D/CrystalAnchor

# Lists of markers for spawners and mana sources (populated from static nodes)
var mana_sources: Array[Node3D] = []
var enemy_spawners: Array[Node3D] = []

# Game state variables
var crystal_health: float = GameSettings.crystal_max_hp
var max_crystal_health: float = GameSettings.crystal_max_hp

const LANE_NAMES = ["White", "Blue", "Black", "Red", "Green"]
var base_ui_instance: Control

func _ready() -> void:
	SignalBus.crystal_damaged.connect(damage_crystal)
	SignalBus.mana_deposited.connect(_on_mana_deposited)
	SignalBus.damage_number_requested.connect(_on_damage_number_requested)

	GraphicsSettings.apply_scene_dependent()

	# The crystal hums for the whole match, from where it hangs rather than from the
	# anchor on the floor beneath it - the sound is the levitation, not the base.
	var crystal_visual: Node3D = nav_region.get_node_or_null("MainCrystal") as Node3D
	if crystal_visual != null:
		SoundBank.attach_loop(&"crystal_ambience", crystal_visual)

	# Instantiate Base UI
	if base_ui_scene:
		base_ui_instance = base_ui_scene.instantiate()
		add_child(base_ui_instance)
		
	# Instantiate Skill Tree
	if skill_tree_scene:
		var st = skill_tree_scene.instantiate()
		st.name = "SkillTree"
		add_child(st)

	# The build phase between waves. Built in code rather than as a scene because it is
	# all data-driven from RunState and has no authored layout worth keeping in a .tscn.
	var upkeep := UpkeepPanel.new()
	upkeep.name = "UpkeepPanel"
	add_child(upkeep)

	RunState.reset()
	
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
	spawn_players(GameSettings.player_count)
	
	# Myrs are now spawned by the player via base UI, not here
		
	# Start Wave Manager
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.start_waves(self)

func damage_crystal(amount: float) -> void:
	crystal_health = clamp(crystal_health - amount, 0.0, max_crystal_health)
	SignalBus.health_changed.emit(crystal_health, max_crystal_health)
	if amount != 0:
		var text_color = Color(1.0, 0.35, 0.1) if amount > 0 else Color(0.2, 1.0, 0.4)
		var spawn_pos = crystal_anchor.global_position + Vector3(randf_range(-0.5, 0.5), 2.5, randf_range(-0.5, 0.5)) if crystal_anchor else Vector3(0, 2.5, 0)
		SignalBus.damage_number_requested.emit(spawn_pos, amount, text_color)
		
	if crystal_health <= 0.0:
		game_over()

func _on_damage_number_requested(pos: Vector3, amount: float, color: Color) -> void:
	if not GameSettings.show_damage_numbers:
		return
	var dn: DamageNumber = DamageNumberPool.get_damage_number()
	dn.activate(pos, amount, color)

## Spawns `count` players around the crystal, the first of them local.
##
## Takes a count rather than hardcoding one so the same path serves single-player and a
## five-player lobby; with a count of 1 the behaviour is exactly what it always was.
## Ringing them around the crystal rather than stacking them on the same point is what
## stops five bodies resolving their collisions by exploding outward on frame one.
func spawn_players(count: int) -> void:
	if player_scene == null:
		return
	var total: int = maxi(count, 1)
	for i in total:
		var player: Node3D = player_scene.instantiate()
		var angle: float = TAU * float(i) / float(total)
		var offset: Vector3 = Vector3(sin(angle), 0.0, cos(angle)) * (0.0 if total == 1 else 2.5)
		player.position = Vector3(0, 1.0, 0) + offset
		player.name = "Player" if i == 0 else "Player%d" % (i + 1)
		# Player 0 is whoever is sitting here. The rest are placeholders until Phase 1
		# gives them a peer to be driven by.
		player.set_meta("is_local", i == 0)
		add_child(player)


## The one place that knows how to build a myr. Both the base UI and the Upkeep panel
## call it, so the spawn position and crystal binding cannot drift between them.
func spawn_myr() -> Node3D:
	if myr_scene == null:
		return null
	var myr: Node3D = myr_scene.instantiate()
	myr.position = crystal_anchor.global_position + Vector3(0, 0.5, 0)
	myr.set_meta("target_crystal", crystal_anchor)
	add_child(myr)
	return myr


## Myrs still deposit through the bus; everything else banks straight into RunState
## when the enemy dies.
func _on_mana_deposited(color: String, amount: int) -> void:
	RunState.add_mana(color, amount)


func game_over() -> void:
	SignalBus.game_over.emit()
	if has_node("WaveManager"):
		get_node("WaveManager").set_process(false)
