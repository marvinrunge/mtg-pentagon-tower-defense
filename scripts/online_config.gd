extends RefCounted
class_name OnlineConfig
## Where the Firebase project's coordinates come from, and why they are not in the repo.
##
## The Web API key is NOT a secret in Firebase's model - it names the project, it ships
## inside every client that talks to it, and it can be read out of any build. What
## actually guards the database is the security rules; see docs/ONLINE_LOBBY_PLAN.md.
##
## It is kept out of git all the same, for a reason that has nothing to do with secrecy:
## a fork that inherited this file would write its lobbies into somebody else's database
## and show its players somebody else's games.
##
## Looked up in this order, first hit wins:
##   1. user://online_config.json  - a tester pointing one build at a scratch project
##   2. res://online_config.json   - what a release build ships with (gitignored)
##   3. MTGPTD_FIREBASE_API_KEY / MTGPTD_FIREBASE_DB_URL - CI and command-line testing
##
## Absent entirely, the game is exactly what it was: LAN hosting, LAN browser, direct
## connect. ONLINE is hidden rather than broken, which is the same rule the rest of the
## networking follows - nothing degrades the single-player or LAN path.

const USER_PATH: String = "user://online_config.json"
const RES_PATH: String = "res://online_config.json"

## Firebase Web API key, from Project settings > General.
var api_key: String = ""
## Realtime Database URL, e.g. https://your-project-default-rtdb.europe-west1.firebasedatabase.app
var database_url: String = ""
## Optional TURN entries, appended to the free STUN list. Each is a dictionary in the
## shape WebRTC wants: {"urls": "turn:host:3478", "username": "...", "credential": "..."}.
## Empty is the normal case - TURN only matters for the minority of players whose NAT
## refuses to be punched through, and it is the one part of this that costs money.
var ice_servers: Array = []


static func load_config() -> OnlineConfig:
	var config := OnlineConfig.new()
	for path: String in [USER_PATH, RES_PATH]:
		if config._read_file(path):
			return config
	config._read_environment()
	return config


func is_valid() -> bool:
	return not api_key.is_empty() and not database_url.is_empty()


func _read_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("%s is not valid JSON - online play stays off." % path)
		return false
	_apply(parsed)
	return is_valid()


func _read_environment() -> void:
	_apply({
		"api_key": OS.get_environment("MTGPTD_FIREBASE_API_KEY"),
		"database_url": OS.get_environment("MTGPTD_FIREBASE_DB_URL"),
	})


func _apply(data: Dictionary) -> void:
	api_key = String(data.get("api_key", api_key)).strip_edges()
	# A trailing slash turns every request path into a double slash, which the database
	# answers with a 404 that says nothing about why.
	database_url = String(data.get("database_url", database_url)).strip_edges().rstrip("/")
	var extra: Variant = data.get("ice_servers", null)
	if extra is Array:
		ice_servers = extra
