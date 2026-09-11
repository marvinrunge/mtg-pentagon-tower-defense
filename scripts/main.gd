extends Node3D
class_name MainController

@export var player_scene: PackedScene = preload("res://scenes/misc/player.tscn")
@export var myr_scene: PackedScene = preload("res://scenes/misc/myr.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/misc/enemy.tscn")
@export var skill_tree_scene: PackedScene = preload("res://scenes/ui/skill_tree.tscn")
@export var base_ui_scene: PackedScene = preload("res://scenes/ui/base_ui.tscn")

## Where a peer goes when the match it was in stops existing.
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var lanes_parent: Node3D = $NavigationRegion3D/Lanes
@onready var crystal_anchor: Marker3D = $NavigationRegion3D/CrystalAnchor
@onready var crystal_visual: Node3D = $NavigationRegion3D/MainCrystal

var _crystal_motion_time: float = 0.0
var _crystal_base_position: Vector3

# Lists of markers for spawners and mana sources (populated from static nodes)
var mana_sources: Array[Node3D] = []
var enemy_spawners: Array[Node3D] = []

# Game state variables
var crystal_health: float = GameSettings.crystal_max_hp
var max_crystal_health: float = GameSettings.crystal_max_hp

const LANE_NAMES = ["White", "Blue", "Black", "Red", "Green"]

## What the run is FOR, announced once on the HUD when the map comes up. Lives here rather
## than in the HUD because it is a fact about this game mode - five lanes converging on one
## crystal - and the HUD's job is only to show whatever it is told.
const MISSION_OBJECTIVE: String = "Protect the Crystal!"
var base_ui_instance: Control

## Harvest slots per mana well. A well has room for a handful of Myrs standing AROUND
## it, Warcraft-mine style - and a sixth heading for the same well is what wedged them
## against the model and against each other, so the cap is enforced where the slots
## are handed out. `_well_slot_holders` is keyed by lane index, each entry the Myrs
## currently holding that lane's slots, in slot order.
var _well_slot_holders: Dictionary = {}

func _ready() -> void:
	SignalBus.crystal_damaged.connect(damage_crystal)
	# Players arriving and leaving mid-match. The map owns the avatars, so the map is
	# what answers - Net only reports who is connected.
	Net.peer_entered_match.connect(_on_peer_entered_match)
	Net.peer_left_match.connect(_on_peer_left_match)
	Net.match_connection_lost.connect(_on_match_connection_lost)
	SignalBus.mana_deposited.connect(_on_mana_deposited)
	SignalBus.damage_number_requested.connect(_on_damage_number_requested)

	GraphicsSettings.apply_scene_dependent()

	# The crystal hums for the whole match, from where it hangs rather than from the
	# anchor on the floor beneath it - the sound is the levitation, not the base.
	if crystal_visual != null:
		_crystal_base_position = crystal_visual.position
		_style_crystal_visual()
		_build_crystal_lights()
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

	# Nights pass faster than days. Sky3D's own clock is linear, so this cannot be a
	# setting on it - see DayNightPacing.
	var sky: Node = get_node_or_null("Sky3D")
	if sky:
		# The clock is set BEFORE the pacing node is attached, and the order is the point:
		# DayNightPacing._ready reads current_time to decide which phase it is starting in and
		# emits phase_changed accordingly. Attached first, it would read the scene's authored
		# time, announce night, and start the night music - which the next frame would then
		# correct, giving a run that opens on a stab of night music at dawn.
		sky.current_time = GameSettings.day_start_hour
		var pacing := DayNightPacing.new()
		pacing.name = "DayNightPacing"
		pacing.phase_changed.connect(SoundBank.set_gameplay_music)
		sky.add_child(pacing)

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
			_add_lane_grass(lane_node, lane_name)

	# Bake navigation mesh
	call_deferred("bake_map_navigation")

## Scatters the lane's biome grass across its wedge. The lane node is the parent, so
## the scatter inherits that lane's rotation and can work in a single lane-local frame
## regardless of which of the five directions it points.
##
## Seeded off the lane's index rather than left random, so a lane's grass is laid out
## the same way every run - a lane that reshuffles itself between runs makes it much
## harder to tell a real placement bug from noise.
func _add_lane_grass(lane_node: Node3D, lane_name: String) -> void:
	var grass := GrassScatter.new()
	grass.name = "Grass"
	grass.biome = lane_name.to_lower()
	grass.random_seed = hash(lane_name)
	lane_node.add_child(grass)


func _process(delta: float) -> void:
	if crystal_visual == null:
		return
	_crystal_motion_time += delta
	crystal_visual.rotation.y = _crystal_motion_time * 0.22
	crystal_visual.position = _crystal_base_position + Vector3(
		0.0,
		sin(_crystal_motion_time * 0.75) * 0.35,
		0.0
	)

func _style_crystal_visual() -> void:
	for mesh_instance: MeshInstance3D in crystal_visual.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source_material: Material = mesh_instance.get_active_material(surface_index)
			if not source_material is StandardMaterial3D:
				continue
			var crystal_material: StandardMaterial3D = (source_material as StandardMaterial3D).duplicate()
			# The five coloured lights only read on the crystal if it has a diffuse term
			# to catch them with. At the previous metallic 0.72 it had almost none - a
			# metallic surface reflects rather than scatters - and roughness 0.12 made it
			# near-mirror, so the lights showed up as five pinpoint dots and nothing else.
			# Enough metallic is kept for the faces to stay glassy rather than chalky.
			crystal_material.metallic = 0.15
			crystal_material.roughness = 0.35
			# Opaque. It used to run TRANSPARENCY_ALPHA at 0.99 alpha, which bought a
			# barely-perceptible see-through and cost real problems: an alpha material
			# writes no depth by default, so it lands in the sorted transparent queue
			# and anything behind the crystal sorts against it badly.
			crystal_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			var albedo_color: Color = crystal_material.albedo_color
			albedo_color.a = 1.0
			crystal_material.albedo_color = albedo_color
			crystal_material.emission_enabled = false
			crystal_material.emission_energy_multiplier = 0.0
			mesh_instance.set_surface_override_material(surface_index, crystal_material)
## Reach of each of the five coloured lights ringing the crystal. Generous on purpose:
## the crystal visual is scaled 5x, so the previous range of 5 barely cleared the mesh
## itself and none of the colour reached the ground around the base.
const CRYSTAL_LIGHT_RANGE: float = 50.0


func _build_crystal_lights() -> void:
	var light_colors: Array[Color] = [
		Color(1.0, 0.12, 0.08),
		Color(0.18, 0.9, 0.3),
		Color(0.12, 0.42, 1.0),
		Color(0.62, 0.16, 0.95),
		Color(1.0, 0.86, 0.62),
	]
	# How far out from the crystal's axis the five lights sit - the size of the ring,
	# not the reach of the lights.
	var light_ring_radius: float = 2.8
	for index: int in range(light_colors.size()):
		var light := OmniLight3D.new()
		var angle: float = TAU * float(index) / float(light_colors.size())
		light.name = "CrystalLight%d" % index
		light.light_color = light_colors[index]
		# Energy deliberately left where it was. Widening the range does brighten the
		# light at any given distance, since Godot spreads the falloff across the whole
		# range - but checked side by side at night, 0.7 holds up and dimming it just
		# took back the extra reach.
		light.light_energy = 0.7
		light.omni_range = CRYSTAL_LIGHT_RANGE
		light.shadow_enabled = false
		light.position = Vector3(
			cos(angle) * light_ring_radius, 2.6, sin(angle) * light_ring_radius
		)
		crystal_visual.add_child(light)

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
	$EffectNetSpawner.spawn_function = _spawn_effect
	if Net.is_joining():
		# Joining a match already under way. The map has to be complete BEFORE the
		# connection opens, because the server pushes the whole running world - every
		# enemy, myr and avatar - the instant a peer connects, and a spawn command that
		# arrives before its spawner exists is discarded rather than queued.
		#
		# Nothing is spawned locally: this peer's own avatar comes from the server like
		# everybody else's, a moment after the handshake.
		if Net.complete_pending_join() != OK:
			push_warning("Could not reconnect to the host.")
	elif Net.is_active():
		spawn_networked_players()
	else:
		spawn_players(GameSettings.player_count)
	# A run with no avatar has no current camera, which renders as a grey screen with the
	# HUD floating on it and no error anywhere. Worth saying out loud, because it is
	# otherwise silent and looks like a rendering fault rather than a spawn one.
	#
	# A joining client legitimately has none yet - the server has not been asked for one.
	if PlayerRegistry.count() == 0 and not Net.is_joining() and not Net.is_active():
		push_error("No player was spawned - the map will render as an empty grey screen")
	
	# Myrs are now spawned by the player via base UI, not here
		
	# Start Wave Manager
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.start_waves(self)

	# Last, so it goes up over a map that is already built. The HUD is instanced in
	# main.tscn, and children are ready before their parent, so it is already listening.
	SignalBus.mission_announced.emit(MISSION_OBJECTIVE)

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
		NetFx.damage_number(spawn_pos, amount, text_color, "")
		
	if crystal_health <= 0.0:
		game_over()

func _on_damage_number_requested(pos: Vector3, amount: float, color: Color, label: String) -> void:
	if not GameSettings.show_damage_numbers:
		return
	var dn: DamageNumber = DamageNumberPool.get_damage_number()
	dn.activate(pos, amount, color, label)

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
		_seat_player(player, i)
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
	for id in ids:
		# The seat comes from Net rather than from the loop counter, because it has to
		# survive a reconnect - the same player must come back to the same chair.
		$PlayerSpawner.spawn({
			"peer": int(id), "seat": Net.seat_of(int(id)), "total": Net.match_seats,
		})


## One avatar for a player who arrived after the match began - a reconnecting player,
## most of the time. Their seat came back with them, so they reappear where they were
## rather than being ringed somewhere new.
##
## Deferred by a frame because the peer list has only just changed and the newcomer's
## own map is finishing its handshake; spawning into that frame is what produced an
## avatar the client acknowledged before it had a spawner to build it with.
func _on_peer_entered_match(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	await get_tree().process_frame
	if not Net.peers.has(peer_id):
		return
	_despawn_avatar(peer_id)
	$PlayerSpawner.spawn({
		"peer": peer_id, "seat": Net.seat_of(peer_id), "total": Net.match_seats,
	})
	# The economy and the crystal only ever go out when they CHANGE, so a newcomer would
	# otherwise play with a full crystal and an empty mana pool until the next kill.
	RunState.push_state_to(peer_id)
	_sync_crystal_health.rpc_id(peer_id, crystal_health)
	# ...and everybody's skill build. A build goes out when it CHANGES, and in a match
	# already under way every change happened before this player connected - so without
	# this their copies of the rest of the party have empty trees and no aura orbs.
	for player: Node3D in PlayerRegistry.players:
		if is_instance_valid(player) and player.has_method("push_build_to"):
			player.push_build_to(peer_id)


## A player who dropped leaves no body standing in the map. Their seat is held by Net
## for the rest of the match, so this is not a departure - it is an empty chair.
func _on_peer_left_match(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_despawn_avatar(peer_id)


func _despawn_avatar(peer_id: int) -> void:
	var avatar: Node3D = PlayerRegistry.by_peer(peer_id)
	if avatar == null:
		return
	PlayerRegistry.unregister(avatar)
	avatar.get_parent().remove_child(avatar)
	avatar.queue_free()


## The host is gone and this map has nothing behind it any more. Keep the build, drop
## the map, and let the menu offer to reconnect.
func _on_match_connection_lost() -> void:
	PlayerRegistry.save_local_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## Runs on every peer, server and client alike, with the argument the server passed to
## spawn(). Authority and seat are set here rather than after add_child because the
## client builds this node from scratch and has nothing else to go on.
func _spawn_avatar(data: Variant) -> Node:
	var info: Dictionary = data
	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % int(info["peer"])
	player.set_multiplayer_authority(int(info["peer"]))
	_seat_player(player, int(info["seat"]))
	return player


## The five spawn points: one per lane, each on the crystal's own platform and each already
## facing the lane its enemies walk down.
##
## Replaces a ring of `TAU * index / total`, which had two problems. Solo it returned
## Vector3(0, 1, 0) - the world origin, which is where the crystal stands, so a single player
## spawned INSIDE the objective; the 5x-scaled CrystalVisual swallowed them and the camera
## started looking at the inside of a gemstone. And in a party the ring was keyed to the
## PLAYER COUNT rather than to the map, so with two players the seats were 180 degrees apart
## and lined up with no lane at all, and with three they were 120 apart and lined up with a
## different set of nothing each time somebody joined.
##
## Seats are fixed to the five lanes now, so seat 2 is the same place whether two people are
## playing or five, and every one of them looks down a lane from the moment they arrive.
func _player_seat(index: int) -> Transform3D:
	var lane: int = posmod(index, LANE_NAMES.size())
	var outward: Vector3 = _lane_outward(lane)
	var origin: Vector3 = Vector3(0.0, 1.0, 0.0) + outward * GameSettings.player_spawn_ring_radius
	# atan2(x, z) aims local +Z along a direction, so the NEGATED direction aims -Z - which is
	# what a Node3D calls forward. Same idiom as the wall placement in Player.
	var basis := Basis(Vector3.UP, atan2(-outward.x, -outward.z))
	return Transform3D(basis, origin)


## Which way lane `index` lies, as a flat unit vector from the crystal.
##
## Measured off the lane's actual EnemySpawner rather than computed as `index * 72 degrees`.
## The five lanes are a pentagon in main.tscn and the arithmetic would agree today, but a map
## edit that nudges one lane would silently leave one player facing a gap - and the whole point
## of these seats is that they point at something real. Falls back to the pentagon angles only
## if the scene has no spawner to measure, which is the case in a stripped test scene.
func _lane_outward(index: int) -> Vector3:
	var spawner: Node3D = get_node_or_null(
		"NavigationRegion3D/Lanes/Lane_%s/EnemySpawner" % LANE_NAMES[index]
	) as Node3D
	if spawner != null:
		var to_lane: Vector3 = spawner.global_position - _crystal_origin()
		to_lane.y = 0.0
		if to_lane.length_squared() > 0.01:
			return to_lane.normalized()
	var angle: float = TAU * float(index) / float(LANE_NAMES.size())
	return Vector3(-sin(angle), 0.0, -cos(angle))


## Puts `player` in its seat and points it down its lane. The seat is also recorded on the
## player, because respawning at base has to return them to it - it used to teleport them to
## Vector3(0, 1, 0), which is the same spot inside the crystal the solo spawn used.
func _seat_player(player: Node3D, seat: int) -> void:
	var seat_transform: Transform3D = _player_seat(seat)
	player.position = seat_transform.origin
	player.rotation.y = seat_transform.basis.get_euler().y
	player.set("spawn_point", seat_transform)


func _crystal_origin() -> Vector3:
	if is_instance_valid(crystal_anchor):
		return Vector3(crystal_anchor.global_position.x, 0.0, crystal_anchor.global_position.z)
	return Vector3.ZERO


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
	# Enforced here rather than only on the button, so nothing else in the game can route
	# around the cap by calling this directly.
	if myr_count() >= GameSettings.myr_max_count:
		return null
	return $MyrNetSpawner.spawn({}) as Node3D


## The persistent half of a spell: zones, walls, summons and telegraphs.
##
## These are not cosmetics and they do not go through NetFx. A suction vortex has a
## collision shape that drags enemies, a soul wall stops what walks into it, a raised
## undead fights - the server has to own one, and every other peer has to be able to SEE
## the same object standing in the same place. That is exactly what a MultiplayerSpawner
## is for, and it is the same arrangement enemies and myrs already use: the arguments
## travel, not the node, and every peer builds its own copy from them.
##
## Which means every argument has to survive the trip. A caster is sent as its PEER ID
## rather than as a node reference, and Zombify's corpse - an EnemyData resource on the
## server - as the colour and class strings TemporaryAlly actually reads off it. A
## resource passed by reference would arrive on the client as null and the summon would
## come back as an untextured box.
##
## The gameplay logic inside these nodes is server-only (see the `Net.is_server()` guards
## in DoTZone, SuctionZone, SoulWall and TemporaryAlly). The client copies are there to be
## looked at; they run their own visuals, their own lifetime and nothing else.
func request_effect(info: Dictionary) -> Node3D:
	if not Net.is_server():
		return null
	return $EffectNetSpawner.spawn(info) as Node3D


func _spawn_effect(data: Variant) -> Node:
	var info: Dictionary = data
	var caster: Node3D = NetFx.player_for(int(info.get("caster", 0)))
	var node: Node3D = null
	match String(info.get("kind", "")):
		"dot_zone":
			var zone := DoTZone.new()
			zone.setup(
				String(info["type"]), float(info["radius"]), float(info["dps"]),
				float(info["duration"]), caster
			)
			node = zone
		"suction":
			node = SuctionZone.create(
				float(info["radius"]), float(info["duration"]), float(info["pull"])
			)
		"wall_of_frost":
			node = WallOfFrost.create(
				float(info["length"]), float(info["duration"]), float(info["damage"])
			)
		"soul_wall":
			node = SoulWall.create(
				float(info["length"]), float(info["duration"]),
				float(info["mark_duration"]), float(info["mark_mult"]), caster
			)
		"undead":
			var ally := TemporaryAlly.new()
			ally.configure(
				"undead", float(info["hp"]), float(info["duration"]),
				float(info["damage"]), caster
			)
			# What it looked like when it died. The EnemyData itself cannot cross the wire;
			# these two strings are everything TemporaryAlly reads off it.
			ally.visual_color = String(info.get("color", ""))
			ally.visual_class = String(info.get("class", ""))
			node = ally
		"bolt_telegraph":
			node = _build_bolt_telegraph(float(info["radius"]), float(info["delay"]))
		_:
			push_warning("Unknown networked effect: %s" % info.get("kind", ""))
			return null
	node.position = info.get("position", Vector3.ZERO)
	# Sent as a yaw rather than as a look_at target, because the node is not in the tree
	# yet - it has no global transform to aim from until the spawner has added it.
	if info.has("yaw"):
		node.rotation.y = float(info["yaw"])
	return node


## The ground circle Lightning Bolt draws before it lands, plus the clock that clears it.
##
## The telegraph resolves ITSELF, on every peer, off the same delay the server used. The
## caster used to hold the reference and call resolve() when its own timer fired, which
## works on one machine and leaves a permanent blue ring on every other one.
func _build_bolt_telegraph(radius: float, delay: float) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = "BoltTelegraph"
	var indicator: AttackIndicator = AttackIndicator.spawn(
		anchor, AttackIndicator.Shape.CIRCLE, radius, 0.0, delay, Color(0.7, 0.85, 1.0)
	)
	# Deferred, because the timer needs a tree and this node has not been added to one yet.
	anchor.ready.connect(func() -> void:
		anchor.get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(indicator):
				indicator.resolve()
			if is_instance_valid(anchor):
				# Outlives the indicator's own fade, which is parented to it.
				anchor.get_tree().create_timer(0.5).timeout.connect(anchor.queue_free)))
	return anchor


## Myrs alive right now. The group is the roster - there is no separate list to keep in
## step with it.
func myr_count() -> int:
	return get_tree().get_nodes_in_group("myrs").size()


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
