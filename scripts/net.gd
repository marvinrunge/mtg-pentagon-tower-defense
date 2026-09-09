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

## peer id -> {"name": String, "ready": bool, "seat": int}. The server owns this and
## pushes it to everyone; a client never adds to it on its own, so the lobby cannot
## disagree with itself.
##
## The SEAT is stored rather than derived from the peer id's position in the sorted
## list, because a reconnecting player gets a brand new peer id and would otherwise
## sort into somebody else's place around the crystal.
var peers: Dictionary = {}
var local_name: String = "Player"
## What the server browser shows for this host.
var server_name: String = "LAN Game"

## Set on the server when the match starts, and on a client when it is told to load the
## map. What it changes is who may join: an in-progress game admits a player straight
## into the running map instead of into the lobby.
var match_in_progress: bool = false

## How many seats the match was laid out for, fixed when it starts. The ring of spawn
## points is computed from it, so a player who reconnects stands where they started
## rather than in a ring resized by however many people happen to be connected.
var match_seats: int = 1

## Lowercased name -> seat, for players who dropped out of a match that is still
## running. A reconnecting player is recognised by NAME - the peer id is gone with the
## connection - and gets its old seat back rather than being ringed somewhere new.
var _reserved_seats: Dictionary = {}

## What the last join attempt used, so the menu can offer to try it again after a drop
## without making the player find the host in the browser a second time.
var last_join: Dictionary = {}

## Set between "the player chose to join a running match" and the peer actually being
## created. The map is loaded FIRST and the connection opened only once it is standing,
## because Godot pushes the whole current world to a peer the moment it connects - and
## a spawn command that arrives before the map exists is dropped, permanently.
var _pending_join: Dictionary = {}

## The host's password, and the one a joining client will present. Both stay on the
## machine that owns them - the password is never put in a discovery reply, only the
## fact that there IS one.
var _password: String = ""
var _pending_password: String = ""
var _responder: PacketPeerUDP = null
var _advertised_port: int = DEFAULT_PORT
var _scanner: PacketPeerUDP = null
var _scan_time_left: float = 0.0
## Where the next query goes. A broadcast finds the whole subnet; a single address is
## how the menu asks one typed host what it is, which matters because "is the match
## already running" decides whether the client loads the map before connecting.
var _scan_target: String = "255.255.255.255"
## "address:port" -> server description, so a host that answers twice is listed once.
var _found: Dictionary = {}

signal peer_list_changed(peers: Dictionary)
## A peer joined or left a match already in progress. The map listens: it is the thing
## that has to spawn or free the avatar.
signal peer_entered_match(peer_id: int)
signal peer_left_match(peer_id: int)
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
## We lost the host mid-match. Distinct from `server_closed`, which is the lobby case:
## this one has a map on screen that has to be torn down and a session worth offering
## to reconnect to.
signal match_connection_lost()


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


## The single-player answer is TRUE - one machine owns everything, and every
## server-only branch is what single-player has always run.
##
## The exception is the window in which a client has loaded the map but has not opened
## its connection yet (see begin_join). No peer exists, so `is_active()` is false, and
## without this the joining client would spend those seconds simulating a run of its
## own: spawning its own waves into a map it is about to be handed.
func is_server() -> bool:
	if is_joining():
		return false
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
	match_in_progress = false
	_reserved_seats.clear()
	peers = {1: {"name": player_name, "ready": false, "seat": 0}}
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
	_pending_join.clear()
	last_join = {"address": address, "port": port, "name": player_name, "password": password}
	return OK


## Joining a match that is ALREADY RUNNING: remember what to connect to, and let the
## map open the connection itself once it is fully built (see complete_pending_join).
##
## The order is the whole trick. Godot pushes every already-spawned node to a peer at
## the instant it connects, and a spawn command whose spawner is not in the tree yet is
## discarded rather than queued - so a client that connects while its map is still
## loading arrives into a world with no enemies in it and no way to learn about them.
## Connecting last costs nothing and removes the race entirely.
func begin_join(address: String, port: int, player_name: String, password: String) -> void:
	local_name = player_name
	match_in_progress = true
	last_join = {"address": address, "port": port, "name": player_name, "password": password}
	_pending_join = last_join.duplicate()


func is_joining() -> bool:
	return not _pending_join.is_empty()


## Called by the map once it is standing: spawners wired, navigation baked, nothing left
## that a replicated spawn could arrive too early for.
func complete_pending_join() -> Error:
	if _pending_join.is_empty():
		return OK
	var details: Dictionary = _pending_join
	_pending_join = {}
	return join(
		String(details["address"]),
		int(details["port"]),
		String(details["name"]),
		String(details["password"]),
	)


## What the menu needs to offer "try that again" after a drop.
func can_reconnect() -> bool:
	return not last_join.is_empty()


## For the ways of leaving that are not a drop - the LEAVE button, the host shutting the
## session down. There is nothing to go back to, so the menu should not offer it.
func forget_last_join() -> void:
	last_join.clear()


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()
	_password = ""
	_pending_password = ""
	_pending_join.clear()
	_reserved_seats.clear()
	match_in_progress = false
	_stop_advertising()
	peer_list_changed.emit(peers)


## Peer ids in a stable order, so every machine rings the same player around the crystal
## in the same seat. Sorted rather than insertion-ordered because a client's dictionary
## is filled by RPC and would otherwise depend on packet arrival.
func ordered_ids() -> Array:
	var ids: Array = peers.keys()
	ids.sort()
	return ids


## The seat the server assigned, which survives a reconnect. Falls back to the position
## in the sorted list for the window before the server's list has arrived.
func seat_of(peer_id: int) -> int:
	var entry: Dictionary = peers.get(peer_id, {})
	if entry.has("seat"):
		return int(entry["seat"])
	return maxi(ordered_ids().find(peer_id), 0)


## Seats are handed out lowest-free-first and never renumbered, so nobody is moved
## around the crystal because somebody else dropped.
func _free_seat() -> int:
	var taken: Dictionary = {}
	for id in peers:
		taken[seat_of(int(id))] = true
	for seat in _reserved_seats.values():
		taken[int(seat)] = true
	for seat in MAX_PLAYERS:
		if not taken.has(seat):
			return seat
	return peers.size()


## How many seats a match still has room for, counting the ones being held for players
## who dropped out and may yet come back.
func free_seats() -> int:
	return maxi(MAX_PLAYERS - peers.size() - _reserved_seats.size(), 0)


func has_reserved_seat(player_name: String) -> bool:
	return _reserved_seats.has(player_name.to_lower())


func _is_name_taken(player_name: String) -> bool:
	for id in peers:
		if display_name(int(id)).to_lower() == player_name.to_lower():
			return true
	return false


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

## Answers discovery queries for as long as this machine is hosting - INCLUDING during
## the match, which is what makes a dropped player able to find the game again. The
## reply says whether the match is under way, so the browser can label it and the
## joiner knows to load the map before connecting.
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
		"in_progress": match_in_progress,
		"free": free_seats(),
	}


## One broadcast, then a short listening window. Results arrive as they come in rather
## than all at once, so a fast host shows up immediately.
func scan_lan(address: String = "255.255.255.255") -> void:
	_scan_target = address
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
	if _scanner.set_dest_address(_scan_target, DISCOVERY_PORT) != OK:
		push_warning("Could not reach %s on this network." % _scan_target)
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
			"in_progress": bool(info.get("in_progress", false)),
			"free": int(info.get("free", MAX_PLAYERS)),
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


## A player who drops out of a RUNNING match keeps their seat, by name, until the match
## ends. They are removed from `peers` all the same: that list is who is connected right
## now, and anything that waits for everybody - the Upkeep vote above all - would
## deadlock on a player who is not there to answer.
func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and match_in_progress and peers.has(id):
		_reserved_seats[display_name(id).to_lower()] = seat_of(id)
	peers.erase(id)
	if multiplayer.is_server():
		_publish_peers.rpc(peers)
		peer_left_match.emit(id)
	peer_list_changed.emit(peers)


func _on_connected_to_server() -> void:
	pass  # nothing until the server asks who we are


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	var was_in_match: bool = match_in_progress
	multiplayer.multiplayer_peer = null
	peers.clear()
	match_in_progress = false
	peer_list_changed.emit(peers)
	# In the lobby this is "the host closed the session". In a match it is a map on
	# screen with nothing behind it, which is a different problem and a different
	# offer: come back to the menu and reconnect.
	if was_in_match:
		match_connection_lost.emit()
	else:
		server_closed.emit()


@rpc("authority", "call_remote", "reliable")
func _request_identity() -> void:
	_submit_identity.rpc_id(1, local_name, _pending_password)


@rpc("any_peer", "call_remote", "reliable")
func _submit_identity(player_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var refusal: String = _refuse_reason(player_name, password)
	if not refusal.is_empty():
		_reject.rpc_id(sender, refusal)
		_kick_later(sender)
		return
	# A returning player is recognised by name and gets their own seat back; anybody
	# else takes the lowest free one.
	var key: String = player_name.to_lower()
	var seat: int = int(_reserved_seats[key]) if _reserved_seats.has(key) else _free_seat()
	_reserved_seats.erase(key)
	# Already playing, so they are ready by definition - a match in progress must not
	# wait on a ready flag from somebody who is standing in it.
	peers[sender] = {"name": player_name, "ready": match_in_progress, "seat": seat}
	_publish_peers.rpc(peers)
	peer_list_changed.emit(peers)
	if match_in_progress:
		_set_match_seats.rpc_id(sender, match_seats)
		# Tells the newcomer's own machine nothing it does not already know - it loaded
		# the map before connecting - but the MAP on this machine has to spawn them.
		peer_entered_match.emit(sender)


## Everything that can turn a join away, in one place so the client is told which of
## them it was rather than simply dropped.
func _refuse_reason(player_name: String, password: String) -> String:
	if password != _password:
		return "Wrong password."
	if _is_name_taken(player_name):
		return "Somebody is already playing under that name."
	if peers.size() >= MAX_PLAYERS:
		return "That game is full."
	# A held seat is the returning player's, and nobody else may take it.
	if free_seats() <= 0 and not has_reserved_seat(player_name):
		return "That game is full."
	return ""


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
	_set_match_seats.rpc(peers.size())
	match_seats = peers.size()
	_begin_match.rpc()
	_begin_match()


## The host keeps answering the browser after this, deliberately: a running match is
## exactly what a player who just lost their connection is looking for.
@rpc("authority", "call_remote", "reliable")
func _set_match_seats(count: int) -> void:
	match_seats = count


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_in_progress = true
	match_started.emit()
