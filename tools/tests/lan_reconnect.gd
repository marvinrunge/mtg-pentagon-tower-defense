extends Node
## Functional test: a player who loses the connection mid-match gets their seat back.
##
## Cross-process for the same reason as lan_lobby.gd - a drop is an ENet event and a
## reconnect is a fresh connection with a NEW peer id, and neither exists in a
## single-process fake. The peer id changing is the whole difficulty: the host has to
## recognise the returning player by name, because nothing else about them is the same.
##
## The host runs the assertions. It is the only side that can see that the seat was
## held while nobody was in it, and that the same seat came back to the same name.
##
## Run with:  godot --headless --path . res://tools/tests/lan_reconnect.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not happen.

const PORT: int = 27017
const PASSWORD: String = "hunter2"
const CLIENT_NAME: String = "Client"
const TIMEOUT_SECONDS: float = 60.0

var _is_client: bool = false
var _elapsed: float = 0.0
var _done: bool = false
var _failures: Array[String] = []

var _seat_before: int = -1
var _seat_after: int = -1
var _saw_drop: bool = false
var _seat_was_reserved: bool = false


func _ready() -> void:
	_is_client = "--lan-client" in OS.get_cmdline_user_args()
	if _is_client:
		_run_client()
	else:
		_run_host()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		if _is_client:
			_done = true
			get_tree().quit()
			return
		_failures.append("timed out after %.0fs waiting for the reconnect" % TIMEOUT_SECONDS)
		_finish()


# --- host ---------------------------------------------------------------------

func _run_host() -> void:
	if Net.host(PORT, "Host", "Reconnect Test", PASSWORD) != OK:
		_failures.append("the host could not open port %d" % PORT)
		_finish()
		return
	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.peer_left_match.connect(_on_peer_left_match)
	Net.peer_entered_match.connect(_on_peer_entered_match)
	Net.set_local_ready(true)
	var launched: Error = OS.create_instance([
		"--headless", "res://tools/tests/lan_reconnect.tscn", "++", "--lan-client",
	])
	if launched < 0:
		_failures.append("could not launch the client process")
		_finish()


func _on_peer_list_changed(_peers: Dictionary) -> void:
	if _done or _saw_drop:
		return
	if Net.peers.size() < 2 or not Net.all_ready():
		return
	_seat_before = _seat_of_client()
	Net.start_match()


## The drop. The seat must NOT be handed to anyone else while the player is away, and
## the match must keep advertising itself or they would have nothing to scan for.
func _on_peer_left_match(_peer_id: int) -> void:
	_saw_drop = true
	_seat_was_reserved = Net.has_reserved_seat(CLIENT_NAME)
	if not Net.match_in_progress:
		_failures.append("the match ended when one player dropped")
	if Net.free_seats() >= Net.MAX_PLAYERS:
		_failures.append("the dropped player's seat was released")


func _on_peer_entered_match(peer_id: int) -> void:
	if _done or not _saw_drop:
		return
	_seat_after = Net.seat_of(peer_id)
	_finish()


func _seat_of_client() -> int:
	for id in Net.peers:
		if Net.display_name(int(id)) == CLIENT_NAME:
			return Net.seat_of(int(id))
	return -1


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _saw_drop:
		_failures.append("the host never noticed the client drop out")
	if not _seat_was_reserved:
		_failures.append("the dropped player's seat was not held for them")
	if _seat_after == -1:
		_failures.append("the client never rejoined the running match")
	elif _seat_after != _seat_before:
		_failures.append(
			"the client came back to seat %d instead of %d" % [_seat_after, _seat_before]
		)
	_report()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _report() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("TEST RESULT: FAIL")


# --- client -------------------------------------------------------------------

func _run_client() -> void:
	Net.lan_scan_finished.connect(_on_scan_finished)
	Net.peer_list_changed.connect(_on_client_peer_list_changed)
	Net.match_started.connect(_on_match_started)
	Net.scan_lan()


func _on_scan_finished(servers: Array) -> void:
	if servers.is_empty() or Net.is_active():
		return
	var server: Dictionary = servers[0]
	Net.join(String(server["address"]), int(server["port"]), CLIENT_NAME, PASSWORD)


func _on_client_peer_list_changed(_peers: Dictionary) -> void:
	if Net.peers.has(Net.local_id()) and not Net.is_ready(Net.local_id()):
		Net.set_local_ready(true)


## Pulls the plug a moment after the match starts, then comes back the way the menu's
## RECONNECT button does: begin_join to remember the address, and complete_pending_join
## standing in for the map finishing its load.
func _on_match_started() -> void:
	await get_tree().create_timer(1.0).timeout
	var details: Dictionary = Net.last_join.duplicate()
	Net.leave()
	await get_tree().create_timer(1.0).timeout
	Net.begin_join(
		String(details["address"]),
		int(details["port"]),
		String(details["name"]),
		String(details["password"]),
	)
	if Net.complete_pending_join() != OK:
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.0).timeout
	_done = true
	get_tree().quit()
