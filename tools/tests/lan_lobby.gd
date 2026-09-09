extends Node
## Functional test: the main menu's LAN path, end to end, with a REAL second process.
##
## Everything here is cross-process on purpose. Discovery is a UDP broadcast, a password
## is checked over an ENet connection, and readiness is a round trip - none of those can
## fail in a single-process fake, which is exactly why the single-process version of
## this test would have passed while the feature was broken.
##
## The host runs the assertions, because the host is the only peer that can see all of
## them: whether the client found it by broadcast (the client is told nothing but what
## discovery returns, so a join at all proves the scan worked), whether the wrong
## password was refused (a refused client would be sitting in the peer list under the
## name "Rejected"), and whether readiness and the start gate work.
##
## Run with:  godot --headless --path . res://tools/tests/lan_lobby.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not happen.

const PORT: int = 27015
const PASSWORD: String = "hunter2"
const CLIENT_NAME: String = "Client"
const REJECTED_NAME: String = "Rejected"
const TIMEOUT_SECONDS: float = 45.0

var _is_client: bool = false
var _elapsed: float = 0.0
var _done: bool = false
var _failures: Array[String] = []
var _saw_ready_client: bool = false
var _started: bool = false


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
		_done = true
		if not _is_client:
			_failures.append("timed out after %.0fs waiting for the LAN handshake" % TIMEOUT_SECONDS)
			_report()
		get_tree().quit(1 if not _is_client else 0)


# --- host ---------------------------------------------------------------------

func _run_host() -> void:
	if Net.host(PORT, "Host", "Test Game", PASSWORD) != OK:
		_failures.append("the host could not open port %d" % PORT)
		_finish()
		return
	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.match_started.connect(_on_match_started)
	Net.set_local_ready(true)
	# The child inherits this project and this executable; only the role differs.
	var launched: Error = OS.create_instance([
		"--headless", "res://tools/tests/lan_lobby.tscn", "++", "--lan-client",
	])
	if launched < 0:
		_failures.append("could not launch the client process")
		_finish()


func _on_peer_list_changed(_peers: Dictionary) -> void:
	if _is_client or _done:
		return
	for id in Net.peers:
		var peer_id: int = int(id)
		if Net.display_name(peer_id) == REJECTED_NAME:
			_failures.append("a client with the WRONG password was let in")
			_finish()
			return
	if Net.peers.size() < 2:
		return
	if not Net.all_ready():
		return
	_saw_ready_client = true
	Net.start_match()


func _on_match_started() -> void:
	if _is_client:
		# Reaching this proves the whole chain from the client's side: it found the
		# host by broadcast, was refused once, got in with the password, and was told
		# to load the map.
		_done = true
		get_tree().quit()
		return
	_started = true
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _saw_ready_client:
		_failures.append("no client ever appeared in the lobby as ready")
	if not _started:
		_failures.append("the match never started")
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
	Net.join_rejected.connect(_on_join_rejected)
	Net.peer_list_changed.connect(_on_client_peer_list_changed)
	Net.match_started.connect(_on_match_started)
	Net.scan_lan()


## The client only ever learns the address from discovery. If the broadcast fails it has
## nowhere to connect to, and the host's timeout reports the failure.
func _on_scan_finished(servers: Array) -> void:
	if servers.is_empty():
		return
	var server: Dictionary = servers[0]
	# Wrong password first, under a name the host can recognise if it wrongly gets in.
	Net.join(String(server["address"]), int(server["port"]), REJECTED_NAME, "wrong")
	set_meta("server", server)


func _on_join_rejected(_reason: String) -> void:
	var server: Dictionary = get_meta("server", {})
	if server.is_empty():
		return
	Net.leave()
	Net.join(String(server["address"]), int(server["port"]), CLIENT_NAME, PASSWORD)


func _on_client_peer_list_changed(_peers: Dictionary) -> void:
	if Net.peers.has(Net.local_id()) and not Net.is_ready(Net.local_id()):
		Net.set_local_ready(true)
