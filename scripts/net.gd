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

## peer id -> {"name": String}. The server owns this and pushes it to everyone; a client
## never adds to it on its own, so the lobby cannot disagree with itself.
var peers: Dictionary = {}
var local_name: String = "Player"

signal peer_list_changed(peers: Dictionary)
signal connection_failed()
signal server_closed()
## The host started the match. Clients load the map when they get this.
signal match_started()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## True once a peer exists. Every single-player code path checks this and takes the
## old branch when it is false.
func is_active() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_server() -> bool:
	return not is_active() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func host(port: int = DEFAULT_PORT, player_name: String = "Host") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		push_error("Could not host on port %d: %d" % [port, result])
		return result
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	peers = {1: {"name": player_name}}
	peer_list_changed.emit(peers)
	return OK


func join(address: String, port: int = DEFAULT_PORT, player_name: String = "Player") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result: Error = peer.create_client(address, port)
	if result != OK:
		push_error("Could not reach %s:%d: %d" % [address, port, result])
		return result
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()
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
	_submit_identity.rpc_id(1, local_name)


@rpc("any_peer", "call_remote", "reliable")
func _submit_identity(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	peers[multiplayer.get_remote_sender_id()] = {"name": player_name}
	_publish_peers.rpc(peers)
	peer_list_changed.emit(peers)


## The server is the only writer of the peer list; clients take what they are given.
@rpc("authority", "call_remote", "reliable")
func _publish_peers(list: Dictionary) -> void:
	peers = list
	peer_list_changed.emit(peers)


# --- starting the match -------------------------------------------------------

func start_match() -> void:
	if not multiplayer.is_server():
		return
	_begin_match.rpc()
	_begin_match()


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_started.emit()
