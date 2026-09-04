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

## Harvest slots per mana well. A well has room for a handful of Myrs standing AROUND
## it, Warcraft-mine style - and a sixth heading for the same well is what wedged them
## against the model and against each other, so the cap is enforced where the slots
## are handed out. `_well_slot_holders` is keyed by lane index, each entry the Myrs
## currently holding that lane's slots, in slot order.
var _well_slot_holders: Dictionary = {}

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

	# Reachable from inside the map on F9 rather than sitting in front of it, so the
	# game stays playable alone at every step of the networking work.
	var lobby := Lobby.new()
	lobby.name = "Lobby"
	add_child(lobby)

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
	# The spawn function runs on EVERY peer with the same argument, which is the only
	# way to get per-avatar data across. Metadata set on the server's instance does not
	# replicate - the client would rebuild the node from the scene file alone and fall
	# back to defaults, giving every avatar authority 1 and is_local true.
	$PlayerSpawner.spawn_function = _spawn_avatar
	$EnemyNetSpawner.spawn_function = _spawn_enemy
	$MyrNetSpawner.spawn_function = _spawn_myr
	if Net.is_active():
		spawn_networked_players()
	else:
		spawn_players(GameSettings.player_count)
	# A run with no avatar has no current camera, which renders as a grey screen with the
	# HUD floating on it and no error anywhere. Worth saying out loud, because it is
	# otherwise silent and looks like a rendering fault rather than a spawn one.
	if PlayerRegistry.count() == 0:
		push_error("No player was spawned - the map will render as an empty grey screen")
	
	# Myrs are now spawned by the player via base UI, not here
		
	# Start Wave Manager
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.start_waves(self)

## Undoes leakage, up to whatever is actually missing. Server-only for the same reason
## damage is: five peers each healing their own copy would disagree instantly.
func repair_crystal(amount: float) -> float:
	if not Net.is_server():
		return 0.0
	var restored: float = minf(amount, max_crystal_health - crystal_health)
	if restored <= 0.0:
		return 0.0
	_apply_crystal_damage(-restored)
	if Net.is_active():
		_sync_crystal_health.rpc(crystal_health)
	return restored


func crystal_missing() -> float:
	return max_crystal_health - crystal_health


## Crystal health is the server's. Clients ask, the server decides, and the resulting
## value is broadcast - otherwise five peers each subtract their own damage and the
## crystal dies five times faster on some screens than others.
func damage_crystal(amount: float) -> void:
	if not Net.is_server():
		return
	_apply_crystal_damage(amount)
	if Net.is_active():
		_sync_crystal_health.rpc(crystal_health)


@rpc("authority", "call_remote", "reliable")
func _sync_crystal_health(value: float) -> void:
	crystal_health = value
	SignalBus.health_changed.emit(crystal_health, max_crystal_health)


func _apply_crystal_damage(amount: float) -> void:
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
		player.position = _player_seat(i, total)
		player.name = "Player" if i == 0 else "Player%d" % (i + 1)
		# Player 0 is whoever is sitting here. The rest are placeholders until Phase 1
		# gives them a peer to be driven by.
		player.set_meta("is_local", i == 0)
		$Players.add_child(player)


## One avatar per connected peer, in a seat order every machine agrees on.
##
## Only the server spawns - the nodes reach clients through the MultiplayerSpawner, so
## a client that joins late still gets everybody. Seats come from Net.ordered_ids() so
## the same peer stands in the same place on every screen.
func spawn_networked_players() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = Net.ordered_ids()
	for i in ids.size():
		$PlayerSpawner.spawn({"peer": int(ids[i]), "seat": i, "total": ids.size()})


## Runs on every peer, server and client alike, with the argument the server passed to
## spawn(). Authority and seat are set here rather than after add_child because the
## client builds this node from scratch and has nothing else to go on.
func _spawn_avatar(data: Variant) -> Node:
	var info: Dictionary = data
	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % int(info["peer"])
	player.set_multiplayer_authority(int(info["peer"]))
	player.position = _player_seat(int(info["seat"]), int(info["total"]))
	return player


## Ringed around the crystal rather than stacked on one point, so five bodies do not
## resolve their overlap by exploding outward on the first frame.
func _player_seat(index: int, total: int) -> Vector3:
	if total <= 1:
		return Vector3(0, 1.0, 0)
	var angle: float = TAU * float(index) / float(total)
	return Vector3(0, 1.0, 0) + Vector3(sin(angle), 0.0, cos(angle)) * 2.5


## The one place that knows how to build an enemy, and the one place that knows how to
## build a myr. Both go through a MultiplayerSpawner so a client rebuilds them from the
## same arguments the server used - metadata set on the server's instance would not
## survive the trip (see MainController._spawn_avatar).
##
## `request_*` is the server-side entry point; `_spawn_*` is what actually runs, on
## every peer. In single-player the spawner has no peers and simply calls it locally.
func request_enemy(info: Dictionary) -> Node3D:
	if not Net.is_server():
		return null
	return $EnemyNetSpawner.spawn(info) as Node3D


func _spawn_enemy(data: Variant) -> Node:
	var info: Dictionary = data
	var enemy: Node3D = enemy_scene.instantiate()
	enemy.position = info["position"]
	enemy.set_meta("target_crystal", crystal_anchor)
	if String(info.get("elite", "")) != "":
		enemy.set_meta("elite_modifier", String(info["elite"]))
	# setup() has to wait for _ready, and the client reaches this the same way, so the
	# colour/class pair travels in the spawn argument rather than as a pre-applied
	# resource that could not replicate.
	enemy.set_meta("enemy_color", String(info["color"]))
	enemy.set_meta("enemy_type", String(info["type"]))
	return enemy


func spawn_myr() -> Node3D:
	if not Net.is_server():
		return null
	return $MyrNetSpawner.spawn({}) as Node3D


## Claims a harvest slot at `lane_index`'s well for `myr`, and hands the Myr the
## offset to stand at. Slots fan out around the well's centre rather than stacking on
## it, which is both the Warcraft-mine look and the fix for Myrs piling onto one
## navigation point. Returns false - and the assignment should be refused - when the
## well is already full.
func claim_well_slot(myr: Node3D, lane_index: int) -> bool:
	if lane_index < 0 or lane_index >= mana_sources.size():
		return false
	var holders: Array = _well_slot_holders.get(lane_index, [])
	# A dead Myr never got to return its slot, so reclaim stale claims before counting.
	holders = holders.filter(func(h: Node3D) -> bool: return is_instance_valid(h))
	if holders.has(myr):
		return true
	if holders.size() >= GameSettings.myr_well_max_slots:
		return false
	# Reserve the new well only after its capacity check succeeds. This preserves the
	# old assignment when the target well is full, while reassignment cannot leave the
	# Myr registered in two wells.
	release_well_slot(myr)
	holders.append(myr)
	_well_slot_holders[lane_index] = holders
	if myr.has_method("set_well_slot_offset"):
		myr.set_well_slot_offset(_well_slot_offset(lane_index, holders.size() - 1))
	return true


## Returns whatever slot `myr` was holding, on death or reassignment. Sweeping every
## lane rather than tracking the Myr's own keeps a stale claim from outliving the
## reassignment that abandoned it.
func release_well_slot(myr: Node3D) -> void:
	for lane_index: int in _well_slot_holders.keys():
		var holders: Array = _well_slot_holders[lane_index]
		if holders.has(myr):
			holders.erase(myr)
			_well_slot_holders[lane_index] = holders


## How many Myrs are currently harvesting `lane_index`'s well - what the base UI shows
## next to the lane buttons so "the well is full" is visible before the click.
func well_slot_count(lane_index: int) -> int:
	var holders: Array = _well_slot_holders.get(lane_index, [])
	holders = holders.filter(func(h: Node3D) -> bool: return is_instance_valid(h))
	_well_slot_holders[lane_index] = holders
	return holders.size()


## Where slot `slot_index` of `lane_index`'s well stands, in world space relative to
## the well: an even ring around the centre, one slot straight ahead of it first.
func _well_slot_offset(lane_index: int, slot_index: int) -> Vector3:
	var angle: float = TAU * float(slot_index) / float(GameSettings.myr_well_max_slots)
	var offset := Vector3(sin(angle), 0.0, cos(angle)) * GameSettings.myr_well_slot_radius
	if lane_index >= 0 and lane_index < mana_sources.size() and is_instance_valid(mana_sources[lane_index]):
		# The ring is built in the lane's frame, so slot 0 faces down-lane rather than
		# world-forward - five wells rotated around the pentagon then read the same.
		offset = mana_sources[lane_index].global_transform.basis * offset
		offset.y = 0.0
	return offset


func _spawn_myr(_data: Variant) -> Node:
	if myr_scene == null:
		return null
	var myr: Node3D = myr_scene.instantiate()
	myr.position = crystal_anchor.global_position + Vector3(0, 0.5, 0)
	myr.set_meta("target_crystal", crystal_anchor)
	return myr


## Myrs still deposit through the bus; everything else banks straight into RunState
## when the enemy dies.
func _on_mana_deposited(color: String, amount: int) -> void:
	RunState.add_mana(color, amount)


func game_over() -> void:
	SignalBus.game_over.emit()
	if has_node("WaveManager"):
		get_node("WaveManager").set_process(false)
