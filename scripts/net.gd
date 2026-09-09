extends Node
## Hosting, joining, and who is connected.
##
## Host-authoritative co-op: one player runs the server and also plays, the rest join.
## No dedicated server - this is PvE, and a lobby host is what players expect.
##
## Everything here is INERT until someone hosts or joins. `is_active()` is false in
## single-player, and every caller is written so that the single-player path is exactly
## what it was before networking existed. That is deliberate: the game has to stay
## playable alone at every step, or a regression in the netcode becomes a regression in
## the whole project.
##
## See docs/MULTIPLAYER_PLAN.md. This is Phase 1.

const DEFAULT_PORT: int = 27015
const MAX_PLAYERS: int = 5

## LAN discovery rides on its own UDP port, separate from the ENet game port: a host
## answers "who is out there" while ENet is busy with the actual session, and a client
## has to be able to ask before it has any connection to ask over.
const DISCOVERY_PORT: int = 27016
const DISCOVERY_QUERY: String = "MTGPTD1?"
const DISCOVERY_MAGIC: String = "MTGPTD1"
## Long enough for every machine on a home LAN to answer, short enough that the scan
## button feels like a button rather than a loading screen.
const SCAN_SECONDS: float = 1.5

## peer id -> {"name": String, "ready": bool}. The server owns this and pushes it to
## everyone; a client never adds to it on its own, so the lobby cannot disagree with
## itself.
var peers: Dictionary = {}
var local_name: String = "Player"
## What the server browser shows for this host.
var server_name: String = "LAN Game"

## The host's password, and the one a joining client will present. Both stay on the
## machine that owns them - the password is never put in a discovery reply, only the
## fact that there IS one.
var _password: String = ""
var _pending_password: String = ""
var _responder: PacketPeerUDP = null
var _advertised_port: int = DEFAULT_PORT
var _scanner: PacketPeerUDP = null
var _scan_time_left: float = 0.0
## "address:port" -> server description, so a host that answers twice is listed once.
var _found: Dictionary = {}

signal peer_list_changed(peers: Dictionary)
signal connection_failed()
signal server_closed()
## The server refused us - wrong password, most likely.
signal join_rejected(reason: String)
## A LAN scan produced results. Emitted as answers arrive and once more when the scan
## window closes, so the list fills in live.
signal lan_servers_updated(servers: Array)
signal lan_scan_finished(servers: Array)
## The host started the match. Clients load the map when they get this.
signal match_started()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Discovery is plain UDP with no engine plumbing behind it, so both sides have to be
## pumped by hand. Cheap when idle: both sockets are null unless someone is hosting or
## scanning right now.
func _process(delta: float) -> void:
	_poll_responder()
	_poll_scanner(delta)


## True once a REAL peer exists. Every single-player code path checks this and takes
## the old branch when it is false.
##
## The OfflineMultiplayerPeer check is the whole point. Godot hands every SceneTree one
## by default, so `multiplayer_peer` is never null and reports CONNECTION_CONNECTED even
## with no networking whatsoever - a plain null check therefore answers TRUE in
## single-player, which sent MainController down the networked spawn path with an empty
## peer list and spawned no player at all. No player means no current camera, which is a
## grey screen with the HUD still drawn on top of it.
func is_active() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_server() -> bool:
	return not is_active() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func host(port: int = DEFAULT_PORT, player_name: String = "Host", label: String = "", password: String = "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		push_error("Could not host on port %d: %d" % [port, result])
		return result
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	server_name = label.strip_edges() if not label.strip_edges().is_empty() else "%s's game" % player_name
	_password = password
	peers = {1: {"name": player_name, "ready": false}}
	_start_advertising(port)
	peer_list_changed.emit(peers)
	return OK


func join(address: String, port: int = DEFAULT_PORT, player_name: String = "Player", password: String = "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result: Error = peer.create_client(address, port)
	if result != OK:
		push_error("Could not reach %s:%d: %d" % [address, port, result])
		return result
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	_pending_password = password
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()
	_password = ""
	_pending_password = ""
	_stop_advertising()
	peer_list_changed.emit(peers)


## Peer ids in a stable order, so every machine rings the same player around the crystal
## in the same seat. Sorted rather than insertion-ordered because a client's dictionary
## is filled by RPC and would otherwise depend on packet arrival.
func ordered_ids() -> Array:
	var ids: Array = peers.keys()
	ids.sort()
	return ids


func seat_of(peer_id: int) -> int:
	return maxi(ordered_ids().find(peer_id), 0)


func display_name(peer_id: int) -> String:
	return String(peers.get(peer_id, {}).get("name", "Player %d" % peer_id))


func is_ready(peer_id: int) -> bool:
	return bool(peers.get(peer_id, {}).get("ready", false))


## Everybody, host included. The host plays too, so a lobby where the host never has to
## commit would let one player drag four others into a match they had not agreed to.
func all_ready() -> bool:
	if peers.is_empty():
		return false
	for id in peers:
		if not is_ready(int(id)):
			return false
	return true


## Ready is per peer and the server is the only writer, exactly like the peer list -
## otherwise two machines can disagree about whether the match may start.
func set_local_ready(value: bool) -> void:
	if not is_active():
		return
	if multiplayer.is_server():
		_apply_ready(1, value)
	else:
		_submit_ready.rpc_id(1, value)


func _apply_ready(peer_id: int, value: bool) -> void:
	if not peers.has(peer_id):
		return
	var entry: Dictionary = peers[peer_id]
	entry["ready"] = value
	peers[peer_id] = entry
	_publish_peers.rpc(peers)
	peer_list_changed.emit(peers)


@rpc("any_peer", "call_remote", "reliable")
func _submit_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	_apply_ready(multiplayer.get_remote_sender_id(), value)


# --- LAN discovery ------------------------------------------------------------

## Answers broadcast queries for as long as this machine is a joinable host. Stops the
## moment the match starts: a session already underway has nothing to offer a browser.
func _start_advertising(port: int) -> void:
	_stop_advertising()
	var socket := PacketPeerUDP.new()
	socket.set_broadcast_enabled(true)
	if socket.bind(DISCOVERY_PORT, "*") != OK:
		push_warning("LAN discovery port %d is taken - this host will not be listed." % DISCOVERY_PORT)
		return
	_responder = socket
	_advertised_port = port


func _stop_advertising() -> void:
	if _responder != null:
		_responder.close()
		_responder = null


func _poll_responder() -> void:
	if _responder == null:
		return
	while _responder.get_available_packet_count() > 0:
		var query: String = _responder.get_packet().get_string_from_utf8()
		var from_ip: String = _responder.get_packet_ip()
		var from_port: int = _responder.get_packet_port()
		if query != DISCOVERY_QUERY or from_ip.is_empty():
			continue
		if _responder.set_dest_address(from_ip, from_port) != OK:
			continue
		_responder.put_packet(JSON.stringify(_describe_server()).to_utf8_buffer())


## Never contains the password itself - only whether one is needed, so the browser can
## show a lock and ask for it before connecting.
func _describe_server() -> Dictionary:
	return {
		"magic": DISCOVERY_MAGIC,
		"name": server_name,
		"port": _advertised_port,
		"players": peers.size(),
		"max": MAX_PLAYERS,
		"password": not _password.is_empty(),
	}


## One broadcast, then a short listening window. Results arrive as they come in rather
## than all at once, so a fast host shows up immediately.
func scan_lan() -> void:
	_found.clear()
	lan_servers_updated.emit(found_servers())
	if _scanner == null:
		var socket := PacketPeerUDP.new()
		socket.set_broadcast_enabled(true)
		if socket.bind(0, "*") != OK:
			push_warning("Could not open a socket to scan the LAN with.")
			lan_scan_finished.emit(found_servers())
			return
		_scanner = socket
	if _scanner.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK:
		push_warning("Could not broadcast on this network.")
		_stop_scanning()
		lan_scan_finished.emit(found_servers())
		return
	_scanner.put_packet(DISCOVERY_QUERY.to_utf8_buffer())
	_scan_time_left = SCAN_SECONDS


func is_scanning() -> bool:
	return _scan_time_left > 0.0


## Sorted by name so the list does not reshuffle itself between scans purely because
## the packets came back in a different order.
func found_servers() -> Array:
	var servers: Array = _found.values()
	servers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", "")))
	return servers


func _poll_scanner(delta: float) -> void:
	if _scanner == null:
		return
	var changed: bool = false
	while _scanner.get_available_packet_count() > 0:
		var reply: String = _scanner.get_packet().get_string_from_utf8()
		var from_ip: String = _scanner.get_packet_ip()
		var parsed: Variant = JSON.parse_string(reply)
		if not (parsed is Dictionary):
			continue
		var info: Dictionary = parsed
		if String(info.get("magic", "")) != DISCOVERY_MAGIC:
			continue
		var port: int = int(info.get("port", DEFAULT_PORT))
		_found["%s:%d" % [from_ip, port]] = {
			"address": from_ip,
			"port": port,
			"name": String(info.get("name", "LAN Game")),
			"players": int(info.get("players", 1)),
			"max": int(info.get("max", MAX_PLAYERS)),
			"password": bool(info.get("password", false)),
		}
		changed = true
	if changed:
		lan_servers_updated.emit(found_servers())
	if _scan_time_left <= 0.0:
		return
	_scan_time_left -= delta
	if _scan_time_left <= 0.0:
		_scan_time_left = 0.0
		_stop_scanning()
		lan_scan_finished.emit(found_servers())


func _stop_scanning() -> void:
	if _scanner != null:
		_scanner.close()
		_scanner = null
	_scan_time_left = 0.0


# --- connection plumbing ------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# The newcomer does not know who else is here, and nobody here knows its name yet.
	# One round trip settles both: the server asks, the client answers, the server
	# republishes the whole list.
	_request_identity.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	if multiplayer.is_server():
		_publish_peers.rpc(peers)
	peer_list_changed.emit(peers)


func _on_connected_to_server() -> void:
	pass  # nothing until the server asks who we are


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	peers.clear()
	peer_list_changed.emit(peers)
	server_closed.emit()


@rpc("authority", "call_remote", "reliable")
func _request_identity() -> void:
	_submit_identity.rpc_id(1, local_name, _pending_password)


@rpc("any_peer", "call_remote", "reliable")
func _submit_identity(player_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if password != _password:
		_reject.rpc_id(sender, "Wrong password.")
		_kick_later(sender)
		return
	peers[sender] = {"name": player_name, "ready": false}
	_publish_peers.rpc(peers)
	peer_list_changed.emit(peers)


## The refused client hangs up on itself the moment it is told why, and the server cuts
## it loose a moment later in case it does not.
##
## The delay is the whole point of doing it this way. Disconnecting the peer in the same
## breath as the rejection threw the rejection away - the connection was gone before the
## reliable packet was ever flushed - and the client reported "the host closed the
## session", which is the one explanation that is not the reason.
@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	leave()
	join_rejected.emit(reason)


func _kick_later(peer_id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_active() or not multiplayer.is_server():
		return
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## The server is the only writer of the peer list; clients take what they are given.
@rpc("authority", "call_remote", "reliable")
func _publish_peers(list: Dictionary) -> void:
	peers = list
	peer_list_changed.emit(peers)


# --- starting the match -------------------------------------------------------

func start_match() -> void:
	if not multiplayer.is_server():
		return
	# A match in progress is not something the browser should offer to join.
	_stop_advertising()
	_begin_match.rpc()
	_begin_match()


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_started.emit()
