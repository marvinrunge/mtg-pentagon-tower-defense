extends Node
## Network benchmark: what a crowd of enemies costs to keep in step between a host and a
## client - bytes the host sends, and both sides' frame times.
##
## Run with:  godot --headless --path . res://tools/tests/net_perf.tscn -- [enemies]
##
## Two real processes, the same way tools/tests/net_effects.gd does it: this one hosts, opens
## a second Godot as the client, and both load the map. The host then fills the lanes with
## enemies marching on the crystal and, after a settling pause, measures for MEASURE_SECONDS:
## the bytes its ENet host sent (everything, to the one client), and its own average frame.
## The client measures its frame over the same stretch and reports it back. Headless on both
## sides, so the frames are game logic and replication, not rendering.

const PORT: int = 27019
const MAP_SCENE := "res://scenes/misc/main.tscn"
const SETTLE_SECONDS := 4.0
const MEASURE_SECONDS := 8.0
const TIMEOUT_SECONDS := 150.0
const TYPES: Array = ["Melee", "Melee", "Ranged", "Mage"]

var _is_client: bool = false
var _started: bool = false
var _done: bool = false
var _elapsed: float = 0.0
var _count: int = 200


func _ready() -> void:
	if get_meta("survivor", false):
		return
	_boot.call_deferred()


func _boot() -> void:
	_is_client = "--lan-client" in OS.get_cmdline_user_args()
	var survivor: Node = load("res://tools/tests/net_perf.gd").new()
	survivor.name = "NetPerfProbe"
	survivor.set_meta("survivor", true)
	get_tree().root.add_child(survivor)
	survivor._is_client = _is_client
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			survivor._count = int(arg)
	survivor._begin()


func _begin() -> void:
	Net.match_started.connect(_on_match_started)
	if _is_client:
		Net.peer_list_changed.connect(func(_peers: Dictionary) -> void:
			if Net.peers.has(Net.local_id()) and not Net.is_ready(Net.local_id()):
				Net.set_local_ready(true))
		if Net.join("127.0.0.1", PORT, "Client") != OK:
			get_tree().quit()
		return
	if Net.host(PORT, "Host", "Net Perf") != OK:
		print("NETPERF the host could not open port %d" % PORT)
		get_tree().quit()
		return
	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.set_local_ready(true)
	OS.create_instance(["--headless", "res://tools/tests/net_perf.tscn", "++", "--lan-client"])


func _process(delta: float) -> void:
	if _done or not get_meta("survivor", false):
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		print("NETPERF timed out")
		_done = true
		get_tree().quit()


func _on_peer_list_changed(_peers: Dictionary) -> void:
	if _started or Net.peers.size() < 2 or not Net.all_ready():
		return
	_started = true
	Net.start_match()


func _on_match_started() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
	_run.call_deferred()


func _await_world() -> bool:
	var waited: float = 0.0
	while waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var scene: Node = get_tree().current_scene
		if scene == null or scene.get_node_or_null("Effects") == null:
			continue
		if PlayerRegistry.count() >= 2:
			return true
	return false


func _run() -> void:
	if not await _await_world():
		print("NETPERF the map never finished building")
		get_tree().quit()
		return
	if _is_client:
		return  # the client only answers _client_measure
	var scene: Node3D = get_tree().current_scene as Node3D
	# Made once the navmesh is baked, which is after both avatars are standing.
	while not scene.has_node("WaveManager"):
		await get_tree().process_frame
	scene.get_node("WaveManager").set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().create_timer(2.0).timeout
	_spawn(scene)
	await get_tree().create_timer(SETTLE_SECONDS).timeout

	var enet: ENetConnection = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	_client_measure.rpc(MEASURE_SECONDS)
	var host_ms: float = await _measure_frames(MEASURE_SECONDS)
	var sent: float = enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var packets: float = enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	print("NETPERF %d enemies: host sent %.0f KB/s in %.0f packets/s to one client; host frame %.2f ms" % [
		get_tree().get_nodes_in_group("enemies").size(), sent / 1024.0 / MEASURE_SECONDS,
		packets / MEASURE_SECONDS, host_ms])


func _spawn(scene: Node3D) -> void:
	var spawners: Array = scene.get("enemy_spawners")
	var colors: Array = scene.get("LANE_NAMES")
	var map: RID = (scene.get("nav_region") as NavigationRegion3D).get_navigation_map()
	var crystal: Vector3 = (scene.get("crystal_anchor") as Node3D).global_position
	for i: int in _count:
		var lane: int = i % spawners.size()
		var start: Vector3 = (spawners[lane] as Node3D).global_position
		var along: float = float(i / spawners.size()) / maxf(float(_count / spawners.size()), 1.0) * 0.6
		var at: Vector3 = NavigationServer3D.map_get_closest_point(map, start.lerp(crystal, along))
		scene.call("request_enemy", {
			"position": scene.to_local(at + Vector3(0, 0.5, 0)),
			"color": String(colors[lane]),
			"type": String(TYPES[i % TYPES.size()]),
		})


func _measure_frames(seconds: float) -> float:
	var frames: int = 0
	var started: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await get_tree().process_frame
		frames += 1
	return float(Time.get_ticks_usec() - started) / 1000.0 / maxf(frames, 1)


@rpc("authority", "call_remote", "reliable")
func _client_measure(seconds: float) -> void:
	var client_ms: float = await _measure_frames(seconds)
	var seen: int = get_tree().get_nodes_in_group("enemies").size()
	_client_report.rpc_id(1, client_ms, seen)


@rpc("any_peer", "call_remote", "reliable")
func _client_report(client_ms: float, seen: int) -> void:
	print("NETPERF client frame %.2f ms with %d enemies on its side" % [client_ms, seen])
	_done = true
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
