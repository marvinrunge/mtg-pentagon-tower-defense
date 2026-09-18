extends Node
## Self-check for the online lobby path: everything that can be answered from ONE
## machine, so that the two-machine test starts from a known-good base.
##
## Run with:  godot --headless --path . res://tools/tests/online_selfcheck.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not happen, plus a NOTES
## block with the facts worth knowing either way.
##
## What it settles, in the order the risk sits:
##
##  1. The scripts parse and the autoloads exist. Everything else is moot otherwise.
##  2. The WebRTC extension is really installed. Godot ships the INTERFACE in core, so
##     the classes resolve in the editor whether or not the implementation is there -
##     which means a missing extension looks exactly like a working one until runtime.
##  3. A REAL WebRTC handshake, loopback, between two connections in this process. This
##     is the part that was written against the documented API and never run: the signal
##     signatures, the offer/answer order, the candidate exchange.
##  4. The shape of WebRTCMultiplayerPeer's API that net_online.gd depends on.
##  5. Firebase end to end: anonymous sign-in, write a lobby, read it back, write a
##     ticket, delete both. That exercises the REST client AND the security rules.
##
## What it CANNOT settle, and nothing on one machine can: whether two players behind two
## different NATs can reach each other. Both connections here are on the same host and
## will pair over a local candidate, which is the one case that was never in doubt.

const TIMEOUT_SECONDS: float = 60.0
const HANDSHAKE_SECONDS: float = 20.0

var _failures: Array[String] = []
var _notes: Array[String] = []
var _skipped: Array[String] = []
var _done: bool = false
var _elapsed: float = 0.0


func _ready() -> void:
	_run()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		_fail("The self-check itself timed out after %ds." % int(TIMEOUT_SECONDS))
		_report()


func _run() -> void:
	_check_wiring()
	var webrtc_ok: bool = _check_webrtc_present()
	if webrtc_ok:
		await _check_webrtc_handshake()
		_check_multiplayer_peer_api()
	var config := OnlineConfig.load_config()
	if config.is_valid():
		await _check_firebase(config)
	else:
		_skip("Firebase", "no online_config.json (and no MTGPTD_FIREBASE_* environment)")
	_report()


# --- 1. wiring ----------------------------------------------------------------

func _check_wiring() -> void:
	for autoload: String in ["NetOnline", "Net"]:
		if get_node_or_null("/root/" + autoload) == null:
			_fail("Autoload %s is missing - check the [autoload] block in project.godot." % autoload)
	# NetOnline must come FIRST: Net._ready() connects to its handshake_failed signal,
	# and an autoload cannot connect to one that is not in the tree yet.
	var net := get_node_or_null("/root/Net")
	if net != null:
		for method: String in ["host_online", "join_online", "begin_join_online"]:
			if not net.has_method(method):
				_fail("Net.%s() is missing." % method)


# --- 2. is the extension actually there ---------------------------------------

func _check_webrtc_present() -> bool:
	if not ClassDB.class_exists("WebRTCPeerConnection"):
		_skip("WebRTC", "the WebRTCPeerConnection class does not exist at all")
		return false
	var probe: WebRTCPeerConnection = WebRTCPeerConnection.new()
	if probe == null:
		_skip("WebRTC", "WebRTCPeerConnection.new() returned nothing - the extension is not installed")
		return false
	var started: int = probe.initialize({"iceServers": []})
	if started != OK:
		_skip("WebRTC", "initialize() answered %d - the extension is not installed" % started)
		return false
	_note("WebRTC extension: present and initialising.")
	return true


# --- 3. a real handshake, loopback --------------------------------------------

func _check_webrtc_handshake() -> void:
	var config: Dictionary = {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
	var offerer := WebRTCPeerConnection.new()
	var answerer := WebRTCPeerConnection.new()
	if offerer.initialize(config) != OK or answerer.initialize(config) != OK:
		_fail("WebRTC: two connections could not both be initialised.")
		return

	# Negotiated on both sides with the same id, so the channel exists before the offer
	# and nothing depends on a renegotiation round.
	var left: WebRTCDataChannel = offerer.create_data_channel("selfcheck", {"negotiated": true, "id": 1})
	var right: WebRTCDataChannel = answerer.create_data_channel("selfcheck", {"negotiated": true, "id": 1})
	if left == null or right == null:
		_fail("WebRTC: create_data_channel() answered nothing.")
		return

	# Exactly the wiring net_online.gd uses. If the signal signatures in that file are
	# wrong, this is where it shows: Godot refuses the connect and the handshake stalls.
	var saw_offer: Array[bool] = [false]
	var saw_answer: Array[bool] = [false]
	offerer.session_description_created.connect(
		func(type: String, sdp: String) -> void:
			saw_offer[0] = saw_offer[0] or type == "offer"
			offerer.set_local_description(type, sdp)
			answerer.set_remote_description(type, sdp)
	)
	answerer.session_description_created.connect(
		func(type: String, sdp: String) -> void:
			saw_answer[0] = saw_answer[0] or type == "answer"
			answerer.set_local_description(type, sdp)
			offerer.set_remote_description(type, sdp)
	)
	offerer.ice_candidate_created.connect(
		func(media: String, index: int, name_: String) -> void:
			answerer.add_ice_candidate(media, index, name_)
	)
	answerer.ice_candidate_created.connect(
		func(media: String, index: int, name_: String) -> void:
			offerer.add_ice_candidate(media, index, name_)
	)

	if offerer.create_offer() != OK:
		_fail("WebRTC: create_offer() was refused.")
		return

	var waited: float = 0.0
	while waited < HANDSHAKE_SECONDS:
		offerer.poll()
		answerer.poll()
		left.poll()
		right.poll()
		if left.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
				and right.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			break
		await get_tree().process_frame
		waited += get_process_delta_time()

	if not saw_offer[0]:
		_fail("WebRTC: no offer was ever produced - session_description_created did not fire as expected.")
	if not saw_answer[0]:
		_fail("WebRTC: no answer was ever produced - setting the remote offer did not trigger one.")
	if left.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		_fail("WebRTC: the data channel never opened (%.1fs). States: %d / %d." % [
			waited, left.get_ready_state(), right.get_ready_state(),
		])
		return

	# The channel is open, so prove it carries something - an open channel that drops
	# every packet would pass every check above.
	left.put_packet("selfcheck".to_utf8_buffer())
	var carried: bool = false
	var carry_waited: float = 0.0
	while carry_waited < 5.0:
		offerer.poll()
		answerer.poll()
		left.poll()
		right.poll()
		if right.get_available_packet_count() > 0:
			carried = right.get_packet().get_string_from_utf8() == "selfcheck"
			break
		await get_tree().process_frame
		carry_waited += get_process_delta_time()
	if not carried:
		_fail("WebRTC: the data channel opened but carried no packet.")
		return
	_note("WebRTC handshake: offer, answer, candidates, open channel, packet delivered (%.1fs)." % waited)


# --- 4. the API net_online.gd was written against -----------------------------

func _check_multiplayer_peer_api() -> void:
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_server() != OK:
		_fail("WebRTCMultiplayerPeer.create_server() was refused.")
		return
	if peer.get_unique_id() != 1:
		_fail("A WebRTC host is peer %d, not 1 - net.gd assumes the host is peer 1." % peer.get_unique_id())
	# net_online.gd does `peer_id in _rtc.get_peers()` and reads ["connected"] out of
	# get_peer(). Both are only true if get_peers() answers a Dictionary.
	var listed: Variant = peer.get_peers()
	if not (listed is Dictionary):
		_fail("WebRTCMultiplayerPeer.get_peers() answers %s, not a Dictionary - net_online.gd reads it as one." % type_string(typeof(listed)))
	else:
		_note("WebRTCMultiplayerPeer.get_peers(): Dictionary, as assumed.")
	# Net._kick_later asks the peer which one it has rather than branching on transport.
	_note("Peer teardown method: %s" % (
		"disconnect_peer" if peer.has_method("disconnect_peer")
		else ("remove_peer" if peer.has_method("remove_peer") else "NEITHER")
	))
	if not peer.has_method("disconnect_peer") and not peer.has_method("remove_peer"):
		_fail("The WebRTC peer has neither disconnect_peer nor remove_peer - a refused client cannot be cut loose.")
	peer.close()


# --- 5. Firebase, end to end --------------------------------------------------

func _check_firebase(config: OnlineConfig) -> void:
	var db := FirebaseRtdb.new()
	add_child(db)
	db.configure(config.api_key, config.database_url)

	if not await db.ensure_auth():
		_fail("Firebase: anonymous sign-in failed. Authentication > Sign-in method > Anonymous, and check the API key.")
		return
	if db.uid().is_empty():
		_fail("Firebase: signed in but no uid came back.")
		return
	_note("Firebase: anonymous sign-in works (uid %s...)." % db.uid().substr(0, 6))

	# A lobby, written exactly as NetOnline writes one.
	var created: Dictionary = await db.push_json("lobbies", {
		"name": "selfcheck",
		"host_uid": db.uid(),
		"players": 1,
		"max": 5,
		"free": 4,
		"has_password": false,
		"in_progress": false,
		"version": 1,
		"heartbeat": {".sv": "timestamp"},
	})
	if not created["ok"]:
		_fail("Firebase: could not create a lobby - %s. Most likely the security rules are not the ones in docs/ONLINE_LOBBY_PLAN.md." % created["error"])
		return
	var lobby_id: String = String(created.get("key", ""))
	_note("Firebase: lobby written (%s)." % lobby_id)

	var read: Dictionary = await db.get_json("lobbies/%s" % lobby_id)
	if not read["ok"] or not (read["data"] is Dictionary):
		_fail("Firebase: the lobby could not be read back - %s." % read["error"])
	else:
		var record: Dictionary = read["data"]
		# The server timestamp is the one field whose value this machine did not choose.
		# A number here proves {".sv": "timestamp"} was honoured rather than stored raw.
		if not (record.get("heartbeat", null) is float or record.get("heartbeat", null) is int):
			_fail("Firebase: heartbeat came back as %s, not a number - the server timestamp was not resolved." % type_string(typeof(record.get("heartbeat", null))))
		if String(record.get("host_uid", "")) != db.uid():
			_fail("Firebase: the lobby came back owned by somebody else.")

	# A ticket, which is the half the rules treat differently.
	var ticket: Dictionary = await db.push_json("tickets/%s" % lobby_id, {
		"client_uid": db.uid(),
		"peer_id": 1234,
		"offer": "v=0 selfcheck",
	})
	if not ticket["ok"]:
		_fail("Firebase: could not write a ticket - %s. Check the `tickets` branch of the rules." % ticket["error"])
	else:
		_note("Firebase: ticket written and the rules allowed it.")
		await db.delete_json("tickets/%s" % lobby_id)

	var removed: Dictionary = await db.delete_json("lobbies/%s" % lobby_id)
	if not removed["ok"]:
		_fail("Firebase: the lobby could not be deleted - %s. A host that cannot clean up leaves dead lobbies in the browser." % removed["error"])
		return
	var gone: Dictionary = await db.get_json("lobbies/%s" % lobby_id)
	if gone["ok"] and gone["data"] != null:
		_fail("Firebase: the lobby was still there after being deleted.")
	else:
		_note("Firebase: lobby deleted and confirmed gone.")


# --- reporting ----------------------------------------------------------------

func _fail(message: String) -> void:
	_failures.append(message)


func _note(message: String) -> void:
	_notes.append(message)


func _skip(what: String, why: String) -> void:
	_skipped.append("%s - %s" % [what, why])


func _report() -> void:
	if _done:
		return
	_done = true
	print("")
	for note: String in _notes:
		print("  ok    %s" % note)
	for skip: String in _skipped:
		print("  SKIP  %s" % skip)
	for failure: String in _failures:
		print("  FAIL  %s" % failure)
	print("")
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		if not _skipped.is_empty():
			print("  (with %d check(s) skipped - see SKIP above)" % _skipped.size())
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())
	print("")
	print("Not covered here, and not coverable on one machine: whether two players behind")
	print("two different NATs can reach each other. Both sides of the handshake above are")
	print("on this host and pair over a local candidate.")
	get_tree().quit(0 if _failures.is_empty() else 1)
