extends Node
## Who is playing, and which one of them is sitting at THIS machine.
##
## Every UI in the project used to reach for `get_first_node_in_group("player")`, which
## is correct only while there is exactly one player. With five it silently picks an
## arbitrary one, so the HUD would show a stranger's health and the skill tree would
## spend a stranger's points.
##
## `local_player` is the answer to "whose screen is this", and it is the only thing a
## HUD, the skill tree or the Upkeep panel should ever ask for. `players` is the answer
## to "who is in this run", for the things that genuinely mean everyone - team levels,
## enemy target selection, difficulty scaling.
##
## Phase 0 of docs/MULTIPLAYER_PLAN.md: no networking yet, and with a single player
## `local_player` is simply that player. What changes later is only who registers as
## local, not any of the call sites.

## The player this machine's input, camera and HUD belong to.
var local_player: Node3D = null

## Every player in the run, local and remote, in join order.
var players: Array[Node3D] = []

## The local player's BUILD, kept across a reconnect.
##
## A build is not the server's - skill points are spent locally and the host never had a
## copy to give back - so the machine that owns it is the one that has to remember it.
## That is enough for the case this exists for: the connection dropped, the process did
## not, and the same player comes back to the same run a few seconds later.
var _saved_build: Dictionary = {}


## Called when a match is left in a way it might be returned from.
func save_local_build() -> void:
	var player: Node3D = get_local()
	if player == null or not player.has_method("export_build"):
		return
	_saved_build = player.export_build()


## Handed to the next local avatar, once. Cleared as it is taken so a NEW run does not
## quietly inherit the build of the last one.
func take_saved_build() -> Dictionary:
	var build: Dictionary = _saved_build
	_saved_build = {}
	return build


func has_saved_build() -> bool:
	return not _saved_build.is_empty()


func clear_saved_build() -> void:
	_saved_build = {}


## Called by each player as it enters the tree. `is_local` is true for exactly one of
## them per machine - the one whose camera becomes current and whose input is read.
func register(player: Node3D, is_local: bool) -> void:
	if not players.has(player):
		players.append(player)
	if is_local:
		if local_player != null and local_player != player:
			push_warning("A second player registered as local; keeping the first")
		else:
			local_player = player
	SignalBus.players_changed.emit(players.size())


func unregister(player: Node3D) -> void:
	players.erase(player)
	if local_player == player:
		local_player = null
	SignalBus.players_changed.emit(players.size())


## The local player, falling back to any player at all.
##
## The fallback exists for the window before registration completes and for tools that
## instantiate a player outside a run; it is deliberately not the normal path, because
## silently picking an arbitrary player is the bug this whole file exists to prevent.
func get_local() -> Node3D:
	if is_instance_valid(local_player):
		return local_player
	for player: Node3D in players:
		if is_instance_valid(player):
			return player
	return null


## The avatar owned by `peer_id`. The server uses it to attribute damage that arrived
## as an RPC back to the player who dealt it, so lifesteal and cooldown refunds land on
## the right person.
func by_peer(peer_id: int) -> Node3D:
	for player: Node3D in players:
		if is_instance_valid(player) and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func count() -> int:
	var alive: int = 0
	for player: Node3D in players:
		if is_instance_valid(player):
			alive += 1
	return alive
