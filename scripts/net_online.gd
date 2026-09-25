extends Node
## Online lobbies: Firebase finds the game, WebRTC carries it.
##
## The split is the whole idea. Firebase is a NOTICEBOARD and a POST BOX, never a game
## server: it lists who is hosting, and it passes the handful of messages two machines
## need in order to find each other. The moment they have, the connection is direct
## between the players and Firebase is out of the loop entirely - no traffic, no cost,
## no latency added. See docs/ONLINE_LOBBY_PLAN.md.
##
## WHY THIS BARELY TOUCHES THE REST OF THE NETCODE. `WebRTCMultiplayerPeer` is a
## `MultiplayerPeer` exactly like `ENetMultiplayerPeer`, and it has a server/client mode
## rather than only a mesh - so the host is peer 1 and everybody else talks to it and to
## nobody else, which is the topology `net.gd` already assumes. Every `@rpc`, every
## `MultiplayerSpawner`, every `MultiplayerSynchronizer`, `NetFx`, the authority split,
## the seat bookkeeping: unchanged. What changes is which object is assigned to
## `multiplayer.multiplayer_peer`, and nothing else.
##
## WHAT IS DELIBERATELY NOT HERE. No relay, no TURN by default, no server-side matchmaker.
## A small fraction of players sit behind a NAT that refuses to be punched through, and
## for them this fails and the LAN path or a direct connection is still there. Buying
## that last fraction means paying for relayed bandwidth, which is the thing the whole
## design is avoiding.

## Bumped when the wire format changes in a way that makes two builds unable to play
## together. Lobbies advertise it and the browser hides the ones that do not match, which
## is cheaper than discovering the mismatch three minutes into a run.
const PROTOCOL_VERSION: int = 1

## Public STUN only. STUN costs nothing and is only ever asked one question - "what does
## my address look like from outside" - so using Google's is not a dependency worth
## worrying about. TURN, which actually carries traffic, is opt-in via the config file.
const STUN_SERVERS: Array = [
	"stun:stun.l.google.com:19302",
	"stun:stun1.l.google.com:19302",
]

const LOBBIES_PATH: String = "lobbies"
const TICKETS_PATH: String = "tickets"

## A host says it is still alive this often. Long enough to be nearly free, short enough
## that a crashed host disappears from the browser inside a couple of minutes.
const HEARTBEAT_SECONDS: float = 20.0
## What the browser treats as dead. Generously more than the heartbeat, because a host
## mid-frame-hitch must not blink out of the list.
const STALE_SECONDS: float = 90.0
## How often the browser refreshes itself while it is on screen. Nothing polls when it
## is not.
const BROWSE_SECONDS: float = 4.0
## The handshake is a conversation of four or five short messages, so it is polled hard
## and briefly rather than gently and forever.
const SIGNAL_SECONDS: float = 0.4
## A handshake that has not completed by now is not going to. Long enough for ICE to
## work through a slow set of candidates, short enough that the player is not left
## staring at a menu.
const HANDSHAKE_TIMEOUT: float = 25.0
## The host forgets a ticket that never became a connection, so one abandoned join does
## not hold a seat or a peer id.
const TICKET_TIMEOUT: float = 40.0

## The browser produces exactly the dictionaries `Net.found_servers()` produces, so the
## menu renders a LAN game and an online game with the same code. `online` and `lobby`
## are the only additions, and they are what JOIN dispatches on.
signal servers_updated(servers: Array)
signal browse_failed(reason: String)
## The join could not be set up - Firebase refused, the lobby went away, or the two
## machines never managed to see each other. Distinct from Godot's own
## `connection_failed`, which cannot fire for a connection that was never opened.
signal handshake_failed(reason: String)
## Progress worth putting in the status line: signing in, exchanging, connecting.
signal status_changed(text: String)

var _config: OnlineConfig
var _db: FirebaseRtdb
## Whether the WebRTC extension is actually installed. Godot ships the INTERFACE in core
## and the implementation in a GDExtension, so the classes exist either way and the only
## honest test is to build one and see whether it works.
var _webrtc_ready: bool = false

var _rtc: WebRTCMultiplayerPeer = null

# --- host state ---
## Both sides hold the lobby id - the host to keep it alive, the client to post its
## ticket into it - so the id alone cannot say which set of timers should be running.
var _hosting: bool = false
var _lobby_id: String = ""
var _lobby_info: Dictionary = {}
var _heartbeat_left: float = 0.0
var _pump_left: float = 0.0
var _pump_busy: bool = false
## ticket id -> {"peer_id", "conn", "remote_set", "ice_sent", "ice_applied", "started"}
var _tickets: Dictionary = {}
## Throttles the "post box is empty" log to roughly once every 10 pumps, so a host left
## sitting on the lobby screen for a while does not bury the one line that matters under
## a wall of identical ones.
var _empty_pump_count: int = 0
## Tickets that have been served and deleted. A delete and the next read of the post box
## are two separate requests, so a finished ticket can come back one more time - and
## without this the host would answer it a second time, build a second connection for a
## player that already has one, and write the refusal into a path the delete had just
## emptied, recreating it. Ids only, and they cost nothing to keep for a session.
var _retired: Dictionary = {}

# --- client state ---
var _ticket_path: String = ""
var _client_peer_id: int = 0
var _client_conn: WebRTCPeerConnection = null
var _client_remote_set: bool = false
var _client_ice: Array = []
var _client_ice_sent: int = 0
var _client_ice_applied: int = 0
var _client_offer_sent: bool = false
var _client_poll_left: float = 0.0
var _client_busy: bool = false
var _client_deadline: float = 0.0

# --- browser state ---
var _browsing: bool = false
var _browse_left: float = 0.0
var _browse_busy: bool = false
var _servers: Array = []


func _log(message: String) -> void:
	print("[NetOnline] %s" % message)


func _ready() -> void:
	_config = OnlineConfig.load_config()
	_db = FirebaseRtdb.new()
	_db.name = "FirebaseRtdb"
	add_child(_db)
	if _config.is_valid():
		_db.configure(_config.api_key, _config.database_url)
	_webrtc_ready = _probe_webrtc()
	_log("config valid=%s webrtc_ready=%s database_url=%s" % [
		_config.is_valid(), _webrtc_ready,
		_config.database_url if _config.is_valid() else "(none)",
	])


## True when online play can be offered at all. Both halves have to be there: the
## database to find games through, and the extension to connect with. When either is
## missing the menu hides ONLINE rather than offering a button that cannot work.
func is_available() -> bool:
	return _config != null and _config.is_valid() and _webrtc_ready


## What to tell the player when it is not. Two very different fixes, and guessing which
## one it is wastes an evening.
func unavailable_reason() -> String:
	if _config == null or not _config.is_valid():
		return "Online play is not configured on this build (no Firebase settings)."
	if not _webrtc_ready:
		return "This build has no WebRTC support - the extension is missing."
	return ""


func _probe_webrtc() -> bool:
	if not ClassDB.class_exists("WebRTCPeerConnection"):
		return false
	var probe: WebRTCPeerConnection = WebRTCPeerConnection.new()
	if probe == null:
		return false
	# Without the extension this is the call that fails: the class instantiates and does
	# nothing. Initialising an empty configuration is harmless and answers the question.
	return probe.initialize({"iceServers": []}) == OK


func _ice_configuration() -> Dictionary:
	var servers: Array = [{"urls": STUN_SERVERS}]
	servers.append_array(_config.ice_servers)
	return {"iceServers": servers}


func _process(delta: float) -> void:
	_tick_heartbeat(delta)
	_tick_host_pump(delta)
	_tick_client(delta)
	_tick_browse(delta)


# --- hosting ------------------------------------------------------------------

## The peer for `multiplayer.multiplayer_peer`, in server mode so the topology matches
## ENet's exactly: everyone talks to peer 1 and to nobody else.
func create_host_peer() -> WebRTCMultiplayerPeer:
	if not is_available():
		_log("create_host_peer refused: not available (%s)" % unavailable_reason())
		return null
	_reset()
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_server() != OK:
		push_error("Could not create the WebRTC host peer.")
		return null
	_rtc = peer
	_hosting = true
	_log("host peer created, id=%d" % peer.get_unique_id())
	return peer


## Puts the lobby on the noticeboard and starts listening for people knocking. `info` is
## `Net._describe_server()` - the same description the LAN responder answers with, so
## the two browsers cannot drift apart.
func publish(info: Dictionary) -> void:
	if _rtc == null:
		return
	_lobby_info = info
	status_changed.emit("Publishing the lobby...")
	var record: Dictionary = _lobby_record(info)
	record["created_at"] = {".sv": "timestamp"}
	var result: Dictionary = await _db.push_json(LOBBIES_PATH, record)
	if not result["ok"]:
		_log("publish FAILED: %s" % result["error"])
		status_changed.emit("Could not list the game online: %s" % result["error"])
		browse_failed.emit(String(result["error"]))
		return
	_lobby_id = String(result.get("key", ""))
	_heartbeat_left = HEARTBEAT_SECONDS
	_pump_left = 0.0
	_log("published lobby id=%s" % _lobby_id)
	status_changed.emit("Listed online. Waiting for players.")


## Called whenever the peer list or the match state moves, so the browser shows a lobby
## filling up rather than a snapshot from when it opened.
func update_lobby(info: Dictionary) -> void:
	_lobby_info = info
	if _lobby_id.is_empty():
		return
	var record: Dictionary = _lobby_record(info)
	record["heartbeat"] = {".sv": "timestamp"}
	_heartbeat_left = HEARTBEAT_SECONDS
	await _db.patch_json("%s/%s" % [LOBBIES_PATH, _lobby_id], record)


func _lobby_record(info: Dictionary) -> Dictionary:
	return {
		"name": String(info.get("name", "Online Game")),
		"host_uid": _db.uid(),
		"players": int(info.get("players", 1)),
		"max": int(info.get("max", 5)),
		"free": int(info.get("free", 0)),
		"has_password": bool(info.get("password", false)),
		"in_progress": bool(info.get("in_progress", false)),
		"version": PROTOCOL_VERSION,
		"heartbeat": {".sv": "timestamp"},
	}


func _tick_heartbeat(delta: float) -> void:
	if not _hosting or _lobby_id.is_empty():
		return
	_heartbeat_left -= delta
	if _heartbeat_left > 0.0:
		return
	_heartbeat_left = HEARTBEAT_SECONDS
	_db.patch_json("%s/%s" % [LOBBIES_PATH, _lobby_id], {"heartbeat": {".sv": "timestamp"}})


## Everything the host does for a join: read the knocks, answer them, feed both sides
## the addresses they discover, and tidy up after the ones that worked and the ones that
## gave up.
func _tick_host_pump(delta: float) -> void:
	if not _hosting or _lobby_id.is_empty() or _pump_busy:
		return
	_pump_left -= delta
	if _pump_left > 0.0:
		return
	_pump_left = SIGNAL_SECONDS if not _tickets.is_empty() else 1.0
	_pump_busy = true
	await _pump_tickets()
	_pump_busy = false


func _pump_tickets() -> void:
	var result: Dictionary = await _db.get_json("%s/%s" % [TICKETS_PATH, _lobby_id])
	if not result["ok"]:
		_log("pump: could not read tickets: %s" % result["error"])
		return
	var tickets: Dictionary = result["data"] if result["data"] is Dictionary else {}
	if not tickets.is_empty():
		_empty_pump_count = 0
		_log("pump: %d ticket(s) in the post box: %s" % [tickets.size(), tickets.keys()])
	else:
		_empty_pump_count += 1
		if _empty_pump_count % 10 == 1:
			_log("pump: post box is empty (lobby %s, checked %d times so far)" % [_lobby_id, _empty_pump_count])
	for ticket_id: String in tickets:
		var ticket: Variant = tickets[ticket_id]
		if ticket is Dictionary:
			await _service_ticket(ticket_id, ticket)
	_retire_tickets()


func _service_ticket(ticket_id: String, ticket: Dictionary) -> void:
	if _retired.has(ticket_id):
		return
	if not _tickets.has(ticket_id):
		await _accept_ticket(ticket_id, ticket)
		return
	var state: Dictionary = _tickets[ticket_id]
	if not bool(state["remote_set"]):
		return
	_apply_remote_ice(state, ticket.get("ice_client", []), state["conn"])
	await _flush_ice(state, "%s/%s/%s/ice_host" % [TICKETS_PATH, _lobby_id, ticket_id])


## A new knock. The client has already written its offer; the host builds its side of
## the connection, hands it to the multiplayer peer under the id the client chose, and
## answers.
func _accept_ticket(ticket_id: String, ticket: Dictionary) -> void:
	var offer: String = String(ticket.get("offer", ""))
	if offer.is_empty():
		return  # still being written; it will be complete on the next pass
	var peer_id: int = int(ticket.get("peer_id", 0))
	_log("accept_ticket %s: peer_id=%d offer_len=%d" % [ticket_id, peer_id, offer.length()])
	var refusal: String = _refuse_ticket(peer_id)
	if not refusal.is_empty():
		_log("accept_ticket %s REFUSED: %s" % [ticket_id, refusal])
		await _db.patch_json("%s/%s/%s" % [TICKETS_PATH, _lobby_id, ticket_id], {"rejected": refusal})
		return

	var conn := WebRTCPeerConnection.new()
	if conn.initialize(_ice_configuration()) != OK:
		_log("accept_ticket %s: conn.initialize() FAILED" % ticket_id)
		return
	var state: Dictionary = {
		"peer_id": peer_id,
		"conn": conn,
		"remote_set": false,
		"ice": [],
		"ice_sent": 0,
		"ice_applied": 0,
		"started": Time.get_ticks_msec(),
	}
	# Connected BEFORE add_peer, because the multiplayer peer starts polling the
	# connection the moment it owns it and the first candidates can appear immediately.
	conn.session_description_created.connect(
		_on_host_description.bind(ticket_id, conn)
	)
	conn.ice_candidate_created.connect(_on_ice_candidate.bind(state, ticket_id))
	if _rtc.add_peer(conn, peer_id) != OK:
		_log("accept_ticket %s: _rtc.add_peer(%d) FAILED" % [ticket_id, peer_id])
		return
	_tickets[ticket_id] = state
	# The host never offers: Godot's convention is that the peer with the LOWER remote id
	# waits, and the host's own id is 1, so every client offers and every host answers.
	if conn.set_remote_description("offer", offer) != OK:
		_log("accept_ticket %s: set_remote_description(offer) FAILED" % ticket_id)
		_drop_ticket(ticket_id, "the offer could not be read")
		return
	state["remote_set"] = true
	_log("accept_ticket %s: offer accepted, waiting on an answer from session_description_created" % ticket_id)
	_apply_remote_ice(state, ticket.get("ice_client", []), conn)


## Refuses before a peer is ever created, for the two things that are the host's to
## know. The password is NOT checked here - that happens over the connection, in
## `Net._submit_identity`, exactly as it does on the LAN, so there is one answer to
## "why was I turned away" rather than two.
func _refuse_ticket(peer_id: int) -> String:
	if peer_id <= 1:
		return "That client sent an invalid id."
	if peer_id in _rtc.get_peers():
		return "Id collision - try again."
	return ""


## The host collects its own candidates per ticket, since each joining player gets its
## own connection and therefore its own list to publish.
func _on_ice_candidate(media: String, index: int, name_: String, state: Dictionary, ticket_id: String) -> void:
	(state["ice"] as Array).append({"media": media, "index": index, "name": name_})
	_log("host gathered ICE candidate #%d for %s (media=%s)" % [(state["ice"] as Array).size(), ticket_id, media])


func _on_host_description(type: String, sdp: String, ticket_id: String, conn: WebRTCPeerConnection) -> void:
	_log("host session_description_created for %s: type=%s" % [ticket_id, type])
	if conn.set_local_description(type, sdp) != OK:
		_log("host %s: set_local_description(%s) FAILED" % [ticket_id, type])
		return
	if type != "answer":
		return
	_log("host %s: writing answer to Firebase" % ticket_id)
	_db.patch_json("%s/%s/%s" % [TICKETS_PATH, _lobby_id, ticket_id], {"answer": sdp})


## A ticket has done its job once the peer is actually connected: the connection lives
## in the multiplayer peer from here on and the post box entry is litter. A ticket that
## never got there is dropped so its seat and its id come back.
func _retire_tickets() -> void:
	var now: int = Time.get_ticks_msec()
	for ticket_id: String in _tickets.keys():
		var state: Dictionary = _tickets[ticket_id]
		var peer_id: int = int(state["peer_id"])
		if peer_id in _rtc.get_peers() and _is_peer_connected(peer_id):
			_log("ticket %s: peer %d is connected - retiring" % [ticket_id, peer_id])
			_retire(ticket_id)
			continue
		if now - int(state["started"]) > int(TICKET_TIMEOUT * 1000.0):
			var entry: Dictionary = _rtc.get_peer(peer_id) if peer_id in _rtc.get_peers() else {}
			_log("ticket %s: TIMED OUT after %ds - last known peer entry: %s" % [
				ticket_id, int(TICKET_TIMEOUT), entry,
			])
			_drop_ticket(ticket_id, "timed out")


func _is_peer_connected(peer_id: int) -> bool:
	var entry: Dictionary = _rtc.get_peer(peer_id)
	if entry.is_empty():
		return false
	return bool(entry.get("connected", false))


func _drop_ticket(ticket_id: String, _reason: String) -> void:
	if not _tickets.has(ticket_id):
		return
	var state: Dictionary = _tickets[ticket_id]
	var peer_id: int = int(state["peer_id"])
	if peer_id in _rtc.get_peers():
		_rtc.remove_peer(peer_id)
	_retire(ticket_id)


## Done with, either way: the connection it set up is live and owned by the multiplayer
## peer, or it never became one. Off the local list, out of the post box, and remembered
## so a late read cannot resurrect it.
func _retire(ticket_id: String) -> void:
	_tickets.erase(ticket_id)
	_retired[ticket_id] = true
	_db.delete_json("%s/%s/%s" % [TICKETS_PATH, _lobby_id, ticket_id])


# --- joining ------------------------------------------------------------------

## Starts the handshake and hands back the peer straight away. It reports CONNECTING
## until the data channels open, which is exactly what `Net` and the menu already expect
## from a connection in progress - so the waiting screen, the timeout and the failure
## path are the ones that were already there.
func create_client_peer(lobby: Dictionary) -> WebRTCMultiplayerPeer:
	if not is_available():
		_log("create_client_peer refused: not available (%s)" % unavailable_reason())
		return null
	_reset()
	var lobby_id: String = String(lobby.get("lobby", ""))
	if lobby_id.is_empty():
		_log("create_client_peer refused: lobby dictionary had no lobby id (%s)" % lobby)
		return null
	# Godot's WebRTC peers need an id before they have a connection to be assigned one
	# over, so the client picks its own and the host refuses a collision. With a 31-bit
	# range and at most four other players, a collision is a formality.
	_client_peer_id = randi_range(2, 2147483646)
	_log("create_client_peer: lobby=%s own peer_id=%d" % [lobby_id, _client_peer_id])
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_client(_client_peer_id) != OK:
		_log("create_client_peer: peer.create_client() FAILED")
		return null
	_rtc = peer
	_lobby_id = lobby_id

	var conn := WebRTCPeerConnection.new()
	if conn.initialize(_ice_configuration()) != OK:
		_log("create_client_peer: conn.initialize() FAILED, ice config=%s" % _ice_configuration())
		return null
	_client_conn = conn
	conn.session_description_created.connect(_on_client_description)
	conn.ice_candidate_created.connect(_on_client_ice_candidate)
	if peer.add_peer(conn, 1) != OK:
		_log("create_client_peer: peer.add_peer(host=1) FAILED")
		return null
	# The client is the one that offers - see the note in _accept_ticket.
	if conn.create_offer() != OK:
		_log("create_client_peer: conn.create_offer() FAILED")
		return null
	_client_deadline = Time.get_ticks_msec() + int(HANDSHAKE_TIMEOUT * 1000.0)
	_client_poll_left = SIGNAL_SECONDS
	_log("create_client_peer: offer requested, waiting on session_description_created")
	status_changed.emit("Finding a route to the host...")
	return peer


func _on_client_description(type: String, sdp: String) -> void:
	_log("client session_description_created: type=%s" % type)
	if _client_conn == null:
		return
	if _client_conn.set_local_description(type, sdp) != OK:
		_log("client: set_local_description(%s) FAILED" % type)
		return
	if type != "offer" or _client_offer_sent:
		return
	_client_offer_sent = true
	_post_ticket(sdp)


## The knock: one entry in the post box, under a key nobody else can guess, containing
## the offer and the id this client intends to be.
func _post_ticket(sdp: String) -> void:
	var result: Dictionary = await _db.push_json("%s/%s" % [TICKETS_PATH, _lobby_id], {
		"client_uid": _db.uid(),
		"peer_id": _client_peer_id,
		"offer": sdp,
		"created_at": {".sv": "timestamp"},
	})
	if not result["ok"]:
		_log("post_ticket FAILED: %s" % result["error"])
		handshake_failed.emit(String(result["error"]))
		return
	_ticket_path = "%s/%s/%s" % [TICKETS_PATH, _lobby_id, String(result.get("key", ""))]
	_log("post_ticket ok: %s" % _ticket_path)
	status_changed.emit("Waiting for the host to answer...")


func _on_client_ice_candidate(media: String, index: int, name_: String) -> void:
	_client_ice.append({"media": media, "index": index, "name": name_})
	_log("client gathered ICE candidate #%d (media=%s)" % [_client_ice.size(), media])


func _tick_client(delta: float) -> void:
	if _client_conn == null or _client_busy:
		return
	if _is_client_connected():
		_log("client: WebRTCMultiplayerPeer reports CONNECTED")
		_finish_client()
		return
	if Time.get_ticks_msec() > _client_deadline:
		_log("client: HANDSHAKE TIMED OUT. connection_status=%d remote_set=%s ice_sent=%d ice_applied=%d peer_status=%s" % [
			_rtc.get_connection_status() if _rtc != null else -1,
			_client_remote_set, _client_ice_sent, _client_ice_applied,
			_rtc.get_peer(1) if _rtc != null and 1 in _rtc.get_peers() else {},
		])
		_fail_client("Could not reach the host - the connection could not be opened.")
		return
	if _ticket_path.is_empty():
		return  # the offer is still being posted
	_client_poll_left -= delta
	if _client_poll_left > 0.0:
		return
	_client_poll_left = SIGNAL_SECONDS
	_client_busy = true
	await _exchange_client()
	_client_busy = false


func _exchange_client() -> void:
	var state: Dictionary = {
		"conn": _client_conn,
		"ice": _client_ice,
		"ice_sent": _client_ice_sent,
		"ice_applied": _client_ice_applied,
	}
	await _flush_ice(state, "%s/ice_client" % _ticket_path)
	_client_ice_sent = int(state["ice_sent"])

	var result: Dictionary = await _db.get_json(_ticket_path)
	if not result["ok"] or _client_conn == null:
		if not result["ok"]:
			_log("client: could not read the ticket back: %s" % result["error"])
		return
	if not (result["data"] is Dictionary):
		# The host deleted the ticket, which it only does once the peer is connected -
		# or the lobby is gone. The connection check on the next tick settles which.
		_log("client: ticket is gone (host deleted it, or the lobby is gone)")
		return
	var ticket: Dictionary = result["data"]
	var rejected: String = String(ticket.get("rejected", ""))
	if not rejected.is_empty():
		_log("client: host REJECTED the ticket: %s" % rejected)
		_fail_client(rejected)
		return
	if not _client_remote_set:
		var answer: String = String(ticket.get("answer", ""))
		if answer.is_empty():
			_log("client: no answer from the host yet")
			return
		_log("client: got an answer, applying it")
		if _client_conn.set_remote_description("answer", answer) != OK:
			_log("client: set_remote_description(answer) FAILED")
			_fail_client("The host's answer could not be read.")
			return
		_client_remote_set = true
		status_changed.emit("Connecting directly to the host...")
	state["ice_applied"] = _client_ice_applied
	_apply_remote_ice(state, ticket.get("ice_host", []), _client_conn)
	_client_ice_applied = int(state["ice_applied"])
	_log("client poll: connection_status=%d remote_set=%s ice_sent=%d ice_applied=%d" % [
		_rtc.get_connection_status() if _rtc != null else -1,
		_client_remote_set, _client_ice_sent, _client_ice_applied,
	])


func _is_client_connected() -> bool:
	if _rtc == null:
		return false
	return _rtc.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The handshake worked. The ticket is litter now, and the client's own poll stops: from
## here the connection is direct and Firebase has no further part in the session.
func _finish_client() -> void:
	_log("client: handshake finished, connection is live")
	if not _ticket_path.is_empty():
		_db.delete_json(_ticket_path)
		_ticket_path = ""
	_client_conn = null
	_client_ice.clear()
	status_changed.emit("Connected.")


func _fail_client(reason: String) -> void:
	_log("client: FAILED - %s" % reason)
	if not _ticket_path.is_empty():
		_db.delete_json(_ticket_path)
		_ticket_path = ""
	_client_conn = null
	_client_ice.clear()
	handshake_failed.emit(reason)


# --- ICE, from both sides -----------------------------------------------------
#
# Candidates are the addresses each machine believes it can be reached at. They arrive
# over a second or two, and both sides need all of them, so each side owns one list and
# only ever appends to it. Writing the whole list back rather than pushing entries one
# at a time keeps it to one request per poll no matter how many candidates turned up,
# and since each list has exactly one writer there is nothing to race with.

func _flush_ice(state: Dictionary, path: String) -> void:
	var ice: Array = state["ice"]
	if ice.size() <= int(state["ice_sent"]):
		return
	var result: Dictionary = await _db.put_json(path, ice)
	if result["ok"]:
		state["ice_sent"] = ice.size()


## Applies what the other side has published, from where we left off. Candidates that
## arrive before the remote description would be thrown away, which is why nothing is
## applied until `remote_set` - the caller guarantees it.
func _apply_remote_ice(state: Dictionary, remote: Variant, conn: WebRTCPeerConnection) -> void:
	if conn == null or not (remote is Array):
		return
	var list: Array = remote
	var applied: int = int(state["ice_applied"])
	if list.size() > applied:
		_log("applying %d new remote ICE candidate(s) (%d -> %d)" % [list.size() - applied, applied, list.size()])
	for index: int in range(applied, list.size()):
		var candidate: Variant = list[index]
		if candidate is Dictionary:
			var entry: Dictionary = candidate
			conn.add_ice_candidate(
				String(entry.get("media", "")),
				int(entry.get("index", 0)),
				String(entry.get("name", "")),
			)
	state["ice_applied"] = list.size()


# --- the browser --------------------------------------------------------------

## Starts refreshing while the browse page is open, and stops when it is not. Nothing in
## this file polls anything unless a player is looking at a list or opening a connection.
func set_browsing(value: bool) -> void:
	_browsing = value
	if value:
		_browse_left = 0.0
	else:
		_servers = []


func refresh_now() -> void:
	_browse_left = 0.0


func found_servers() -> Array:
	return _servers


func _tick_browse(delta: float) -> void:
	if not _browsing or _browse_busy or not is_available():
		return
	_browse_left -= delta
	if _browse_left > 0.0:
		return
	_browse_left = BROWSE_SECONDS
	_browse_busy = true
	await _fetch_lobbies()
	_browse_busy = false


func _fetch_lobbies() -> void:
	var result: Dictionary = await _db.get_json(LOBBIES_PATH)
	if not result["ok"]:
		browse_failed.emit(String(result["error"]))
		return
	var lobbies: Dictionary = result["data"] if result["data"] is Dictionary else {}
	var now: float = Time.get_unix_time_from_system() * 1000.0
	var listed: Array = []
	for lobby_id: String in lobbies:
		var entry: Variant = lobbies[lobby_id]
		if not (entry is Dictionary):
			continue
		var lobby: Dictionary = entry
		if int(lobby.get("version", 0)) != PROTOCOL_VERSION:
			_log("browse: hiding %s (%s) - protocol %s vs our %d, one side is on a different build" % [
				lobby_id, lobby.get("name", "?"), lobby.get("version", "?"), PROTOCOL_VERSION,
			])
			continue
		if now - float(lobby.get("heartbeat", 0.0)) > STALE_SECONDS * 1000.0:
			# Nobody owns the job of clearing these, so whoever notices does it. The
			# security rules allow a stale entry to be deleted by anyone and a live one
			# by its host alone, so this cannot be used to close somebody's game.
			_log("browse: hiding %s (%s) - stale, no heartbeat for over %ds, deleting it" % [
				lobby_id, lobby.get("name", "?"), int(STALE_SECONDS),
			])
			_db.delete_json("%s/%s" % [LOBBIES_PATH, lobby_id])
			continue
		_log("browse: listing %s (%s) - heartbeat %ds ago" % [
			lobby_id, lobby.get("name", "?"), int((now - float(lobby.get("heartbeat", 0.0))) / 1000.0),
		])
		listed.append({
			"online": true,
			"lobby": lobby_id,
			"address": "",
			"port": 0,
			"name": String(lobby.get("name", "Online Game")),
			"players": int(lobby.get("players", 1)),
			"max": int(lobby.get("max", 5)),
			"password": bool(lobby.get("has_password", false)),
			"in_progress": bool(lobby.get("in_progress", false)),
			"free": int(lobby.get("free", 0)),
		})
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", "")))
	_servers = listed
	servers_updated.emit(_servers)


# --- teardown -----------------------------------------------------------------

## Takes the lobby off the noticeboard and empties the post box. Called from `Net.leave`,
## and worth doing even though a heartbeat that stops would eventually have the same
## effect: "eventually" is up to ninety seconds of players trying to join a game that
## has closed.
func close() -> void:
	var lobby_id: String = _lobby_id
	var ticket_path: String = _ticket_path
	var was_hosting: bool = _hosting
	_reset()
	if not ticket_path.is_empty():
		_db.delete_json(ticket_path)
	# Only the host owns the entry. A leaving client that tried this would be refused by
	# the rules anyway, but asking is a request and a log line for nothing.
	if was_hosting and not lobby_id.is_empty():
		_db.delete_json("%s/%s" % [LOBBIES_PATH, lobby_id])
		_db.delete_json("%s/%s" % [TICKETS_PATH, lobby_id])


func _reset() -> void:
	_rtc = null
	_hosting = false
	_lobby_id = ""
	_lobby_info = {}
	_tickets.clear()
	_retired.clear()
	_empty_pump_count = 0
	_heartbeat_left = 0.0
	_pump_left = 0.0
	_ticket_path = ""
	_client_peer_id = 0
	_client_conn = null
	_client_remote_set = false
	_client_ice = []
	_client_ice_sent = 0
	_client_ice_applied = 0
	_client_offer_sent = false
	_client_deadline = 0.0
