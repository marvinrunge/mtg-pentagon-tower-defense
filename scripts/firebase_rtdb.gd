extends Node
class_name FirebaseRtdb
## The Firebase Realtime Database over plain REST, plus anonymous sign-in.
##
## There is no Firebase SDK for Godot, and none is needed: the Realtime Database is a
## JSON tree addressed by URL, so every operation here is one HTTPS request with the ID
## token in the query string. That is the whole client.
##
## WHY THE REALTIME DATABASE AND NOT FIRESTORE. Firestore's live updates are gRPC only;
## over REST it can be polled and nothing else. The Realtime Database can be polled the
## same way AND, unlike Firestore, its free tier is not priced per document read - which
## matters when a lobby browser refreshes itself. See docs/ONLINE_LOBBY_PLAN.md.
##
## WHY POLLING AND NOT THE EVENT STREAM. The database does offer server-sent events over
## REST, and it was tempting. Two things decided against it: the stream answers with a
## 307 to a different host that HTTPRequest will not follow for a streaming body, and
## the free tier allows 100 SIMULTANEOUS CONNECTIONS - one held open per player browsing
## would cap the game at a hundred people looking at the menu. Polling holds nothing
## open, costs a few kilobytes per refresh, and only runs while a browser or a handshake
## is actually on screen.

## Anonymous sign-in. The uid it returns is what the security rules check writes against.
const SIGNUP_URL: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp"
const REFRESH_URL: String = "https://securetoken.googleapis.com/v1/token"
## The refresh token is kept so the uid survives a restart. That is not a convenience:
## a host whose game crashed comes back with the SAME uid and is therefore still, by the
## security rules, the owner of the lobby entry it left behind - so it can delete it.
const AUTH_CACHE_PATH: String = "user://online_auth.json"
const REQUEST_TIMEOUT: float = 15.0

var api_key: String = ""
var database_url: String = ""

var _id_token: String = ""
var _refresh_token: String = ""
var _uid: String = ""
var _expires_at: float = 0.0
var _auth_in_flight: bool = false
## Set when sign-in failed for a reason retrying will not fix - a wrong API key, or
## anonymous sign-in left disabled in the console. Retrying that on every request turns
## one mistake into a request storm.
var _auth_blocked: String = ""

signal auth_failed(reason: String)


func configure(key: String, url: String) -> void:
	api_key = key
	database_url = url
	_load_cached_auth()


func uid() -> String:
	return _uid


func is_signed_in() -> bool:
	return not _id_token.is_empty()


# --- the four operations ------------------------------------------------------
#
# Every one answers the same dictionary: {"ok": bool, "code": int, "data": Variant,
# "error": String}. Callers check `ok` and nothing else, so a transport failure and a
# permission denial are handled in one place rather than at nineteen call sites.

func get_json(path: String, query: Dictionary = {}) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, null, query)


## Replaces whatever is at `path`.
func put_json(path: String, value: Variant) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, path, value, {})


## Merges into whatever is at `path`, leaving the keys it does not mention alone. This
## is what keeps two peers writing to the same ticket from overwriting each other.
func patch_json(path: String, value: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PATCH, path, value, {})


## Appends under a server-generated key and answers with it. Used for lobby ids and
## ticket ids: both need to be unique without anyone coordinating.
func push_json(path: String, value: Variant) -> Dictionary:
	var result: Dictionary = await _request(HTTPClient.METHOD_POST, path, value, {})
	if result["ok"] and result["data"] is Dictionary:
		result["key"] = String((result["data"] as Dictionary).get("name", ""))
	return result


func delete_json(path: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_DELETE, path, null, {})


const _METHOD_NAMES: Dictionary = {
	HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_PUT: "PUT",
	HTTPClient.METHOD_PATCH: "PATCH", HTTPClient.METHOD_POST: "POST",
	HTTPClient.METHOD_DELETE: "DELETE",
}


func _request(method: int, path: String, body: Variant, query: Dictionary) -> Dictionary:
	if not await ensure_auth():
		var reason: String = _auth_blocked if not _auth_blocked.is_empty() else "not signed in"
		print("[Firebase] %s %s refused: %s" % [_METHOD_NAMES.get(method, method), path, reason])
		return {"ok": false, "code": 0, "data": null, "error": reason}
	var url: String = "%s/%s.json?auth=%s" % [database_url, path, _id_token.uri_encode()]
	for key: String in query:
		url += "&%s=%s" % [key, String(query[key]).uri_encode()]
	var payload: String = "" if body == null else JSON.stringify(body)
	var result: Dictionary = await _http(url, method, payload, ["Content-Type: application/json"])
	if result["ok"]:
		print("[Firebase] %s %s -> %d ok" % [_METHOD_NAMES.get(method, method), path, result["code"]])
	else:
		print("[Firebase] %s %s -> %d FAILED: %s" % [_METHOD_NAMES.get(method, method), path, result["code"], result["error"]])
	return result


# --- authentication -----------------------------------------------------------

## Signs in if there is no token, refreshes it if it is about to expire, and otherwise
## returns immediately. The minute of slack is so a token cannot expire between this
## check and the request it was checked for.
func ensure_auth() -> bool:
	if not _auth_blocked.is_empty():
		return false
	if is_signed_in() and Time.get_unix_time_from_system() < _expires_at - 60.0:
		return true
	# A menu opening fires several requests at once, and each of them would otherwise
	# start its own sign-in. The first one does it; the rest wait for its answer.
	if _auth_in_flight:
		while _auth_in_flight:
			await get_tree().process_frame
		return is_signed_in()
	_auth_in_flight = true
	# Spelled out rather than folded into a conditional expression: `await a if c else b`
	# parses as `(await a) if c else b`, which would refresh a token that does not exist.
	var ok: bool = false
	if not _refresh_token.is_empty():
		ok = await _refresh()
	if not ok:
		ok = await _sign_up_anonymous()
	_auth_in_flight = false
	return ok


func _sign_up_anonymous() -> bool:
	var url: String = "%s?key=%s" % [SIGNUP_URL, api_key.uri_encode()]
	var body: String = JSON.stringify({"returnSecureToken": true})
	var result: Dictionary = await _http(url, HTTPClient.METHOD_POST, body, ["Content-Type: application/json"])
	if not result["ok"]:
		var reason: String = _identity_error(result)
		# 400 ADMIN_ONLY_OPERATION is anonymous sign-in left switched off in the console,
		# and 400 API_KEY_INVALID is a typo in the config. Neither improves with retries.
		if int(result["code"]) == 400:
			_auth_blocked = reason
		auth_failed.emit(reason)
		return false
	var data: Dictionary = result["data"] if result["data"] is Dictionary else {}
	_id_token = String(data.get("idToken", ""))
	_refresh_token = String(data.get("refreshToken", ""))
	_uid = String(data.get("localId", ""))
	_expires_at = Time.get_unix_time_from_system() + float(String(data.get("expiresIn", "3600")).to_int())
	_save_cached_auth()
	print("[Firebase] signed in anonymously, uid=%s..." % _uid.substr(0, 6))
	return is_signed_in()


func _refresh() -> bool:
	var url: String = "%s?key=%s" % [REFRESH_URL, api_key.uri_encode()]
	var body: String = "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var result: Dictionary = await _http(
		url, HTTPClient.METHOD_POST, body, ["Content-Type: application/x-www-form-urlencoded"]
	)
	if not result["ok"]:
		# A refresh token goes stale if the anonymous account was swept up by Firebase's
		# own cleanup. That is not an error worth showing anybody - sign up again.
		_refresh_token = ""
		return false
	var data: Dictionary = result["data"] if result["data"] is Dictionary else {}
	_id_token = String(data.get("id_token", ""))
	_refresh_token = String(data.get("refresh_token", _refresh_token))
	_uid = String(data.get("user_id", _uid))
	_expires_at = Time.get_unix_time_from_system() + float(String(data.get("expires_in", "3600")).to_int())
	_save_cached_auth()
	print("[Firebase] refreshed cached sign-in, uid=%s..." % _uid.substr(0, 6))
	return is_signed_in()


func _identity_error(result: Dictionary) -> String:
	var data: Variant = result["data"]
	if data is Dictionary:
		var error: Variant = (data as Dictionary).get("error", null)
		if error is Dictionary:
			var message: String = String((error as Dictionary).get("message", ""))
			match message:
				"ADMIN_ONLY_OPERATION":
					return "Anonymous sign-in is switched off in the Firebase console."
				"API_KEY_INVALID", "INVALID_API_KEY":
					return "That Firebase API key is not valid."
				_:
					if not message.is_empty():
						return message
	return String(result["error"])


func _load_cached_auth() -> void:
	if not FileAccess.file_exists(AUTH_CACHE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTH_CACHE_PATH))
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	# Tied to the project it was issued for: pointing the build at another database must
	# not try to reuse a token that database has never heard of.
	if String(data.get("database_url", "")) != database_url:
		return
	_refresh_token = String(data.get("refresh_token", ""))
	_uid = String(data.get("uid", ""))


func _save_cached_auth() -> void:
	var file := FileAccess.open(AUTH_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"database_url": database_url,
		"refresh_token": _refresh_token,
		"uid": _uid,
	}))
	file.close()


# --- transport ----------------------------------------------------------------

func _http(url: String, method: int, body: String, headers: Array) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var started: Error = http.request(url, PackedStringArray(headers), method, body)
	if started != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "could not send the request (%d)" % started}
	var answer: Array = await http.request_completed
	http.queue_free()

	var result: int = int(answer[0])
	var code: int = int(answer[1])
	var text: String = (answer[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": code, "data": data, "error": _transport_error(result)}
	if code < 200 or code >= 300:
		return {"ok": false, "code": code, "data": data, "error": _status_error(code, data)}
	return {"ok": true, "code": code, "data": data, "error": ""}


func _transport_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "The server did not answer in time."
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not reach Firebase - check the connection."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "The secure connection to Firebase failed."
		_:
			return "The request failed (%d)." % result


func _status_error(code: int, data: Variant) -> String:
	if code == 401 or code == 403:
		# Almost always the security rules, and almost always because they were never
		# pasted in - a fresh database starts locked and answers every write this way.
		return "Firebase refused that (%d) - check the database rules." % code
	if data is Dictionary and (data as Dictionary).has("error"):
		return String((data as Dictionary)["error"])
	return "Firebase answered %d." % code
