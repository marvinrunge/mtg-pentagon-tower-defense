extends Node
## Every cosmetic that has to happen on more than one screen.
##
## Spells run on the SERVER. `Player.execute_spell` hands a client's cast to the host,
## because that is where the damage, the zones and the summons belong - but their VISUALS
## do not belong there. A ring drawn with `get_tree().current_scene.add_child()` on the
## host exists on exactly one machine, which is why a client used to cast Frost Breath
## and see nothing at all: not the ring, not the decal, not even their own cast flash.
## The spell worked; it was invisible to the person who cast it.
##
## So the effect layer is split in two. The SHAPES stay in SpellFx and EmberFx, where they
## have always been. What goes on the wire is a description - which shape, where, what
## colour, how big - and every peer rebuilds it locally from those numbers. No visual node
## is ever replicated, and no bone, mesh or particle crosses the connection.
##
## Effects start in two places, so this travels in two directions:
##
##   * the SERVER runs a spell and broadcasts down to everybody;
##   * a CLIENT plays its own melee impacts, which are detected locally so that a swing
##     lands the moment it looks like it lands. It plays its copy immediately and asks the
##     server to relay it to the rest - the rule docs/MULTIPLAYER_PLAN.md already sets for
##     melee, applied to the noise and the sparks as well as to the hit.
##
## Inert in single-player, like everything else in the netcode: `Net.is_active()` is false,
## nothing is sent, and `_play_local` runs exactly the code that used to sit at the call
## site.

## What to build. Sent as an int, so adding one here never renumbers the others.
enum Kind {
	RING,      ## SpellFx.shockwave - the area a skill just affected.
	BEAM,      ## SpellFx.beam - a straight shaft from `at` along `dir`.
	IMPACT,    ## SpellFx.impact - a front leaving a point.
	GUST,      ## SpellFx.gust - a blast down one direction.
	DECAL,     ## SpellFx.ground_decal - a mark laid onto the ground under `at`.
	GLOW,      ## SpellFx.cast_glow - a pulse ON a player, so it travels with them.
	SOUND,     ## SoundBank.play_at.
	SHAKE,     ## SignalBus.camera_shake_requested, distance-gated per viewer.
	NUMBER,    ## SignalBus.damage_number_requested - a figure floating off what was hit.
}

## Beyond this a shake is somebody else's business. The caster always feels its own at
## full strength (see `_play_shake`); this is what a bystander gets, and it exists so that
## a Wrath of God two lanes away does not rattle a camera that cannot see it.
const SHAKE_FALLOFF_RANGE: float = 34.0


# --- What a spell asks for ----------------------------------------------------
#
# One function per shape, so a call site still reads as "a ring at this radius" rather
# than as a dictionary literal. The keys live here and nowhere else.

func ring(center: Vector3, tint: Color, radius: float) -> void:
	_dispatch({"kind": Kind.RING, "at": center, "tint": tint, "size": radius})


func beam(origin: Vector3, direction: Vector3, length: float, tint: Color) -> void:
	_dispatch({"kind": Kind.BEAM, "at": origin, "dir": direction, "size": length, "tint": tint})


func impact(center: Vector3, tint: Color, radius: float) -> void:
	_dispatch({"kind": Kind.IMPACT, "at": center, "tint": tint, "size": radius})


## `facing` may be zero, in which case the gust keeps the orientation it was built with.
func gust(origin: Vector3, facing: Vector3, length: float, tint: Color) -> void:
	_dispatch({"kind": Kind.GUST, "at": origin, "dir": facing, "size": length, "tint": tint})


func decal(slot: String, tint: Color, radius: float, at: Vector3, peer: int) -> void:
	_dispatch({"kind": Kind.DECAL, "slot": slot, "tint": tint, "size": radius, "at": at, "peer": peer})


## A pulse on the player who owns `peer` - parented to them, so a buff cast on the move
## travels with the caster instead of being left behind where it was cast.
func glow(peer: int, tint: Color, radius: float) -> void:
	_dispatch({"kind": Kind.GLOW, "peer": peer, "tint": tint, "size": radius})


## A figure floating up off whatever was just hit or healed.
##
## Every one of these used to be emitted from code that only runs on the server -
## EnemyBase.take_damage, Player.take_damage, Myr, the crystal - so a client swung at an
## enemy and saw no number, no flinch and no falling health bar. The hit was landing; it
## was landing on a machine they were not looking at.
func damage_number(at: Vector3, amount: float, tint: Color, label: String = "") -> void:
	_dispatch({"kind": Kind.NUMBER, "at": at, "size": amount, "tint": tint, "slot": label})


func sound(event: StringName, at: Vector3) -> void:
	_dispatch({"kind": Kind.SOUND, "event": String(event), "at": at})


## `at` is where it happened and `peer` is who caused it. The owner of `peer` feels the
## full shake wherever they are; everyone else feels it by how close they are standing.
func shake(strength: float, duration: float, at: Vector3, peer: int) -> void:
	_dispatch({
		"kind": Kind.SHAKE, "size": strength, "time": duration, "at": at, "peer": peer,
	})


# --- Getting it to the other screens ------------------------------------------

## Plays it here, then makes sure everybody else gets it too.
##
## Immediate locally in every case. A client that waited for the server to tell it about
## its own sword hitting something would hear the clang after the enemy had already
## flinched, and the whole reason melee is detected client-side is to avoid exactly that.
func _dispatch(payload: Dictionary) -> void:
	_play_local(payload)
	if not Net.is_active():
		return
	if Net.is_server():
		_play.rpc(payload)
	else:
		_relay.rpc_id(1, payload)


## The server's copy of an effect a client started, passed on to everyone who has not
## seen it yet - which is everyone except the client that sent it, since that one played
## its own copy before the packet left.
@rpc("any_peer", "call_remote", "reliable")
func _relay(payload: Dictionary) -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_play_local(payload)
	for id: int in multiplayer.get_peers():
		if id != sender:
			_play.rpc_id(id, payload)


@rpc("authority", "call_remote", "reliable")
func _play(payload: Dictionary) -> void:
	_play_local(payload)


# --- Building it -------------------------------------------------------------

func _play_local(payload: Dictionary) -> void:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	match int(payload.get("kind", -1)):
		Kind.RING:
			# Lifted just clear of the ground: coplanar with it, the wave z-fights the terrain.
			_place(scene, SpellFx.shockwave(payload["tint"], payload["size"]),
				payload["at"] + Vector3(0.0, 0.12, 0.0))
		Kind.BEAM:
			# Placed at the beam's START, not its middle: SpellFx.beam runs out along its own
			# +X from wherever it is put, which is what a caster-to-target shot wants.
			_place(scene, SpellFx.beam(payload["dir"], payload["size"], payload["tint"]), payload["at"])
		Kind.IMPACT:
			_place(scene, SpellFx.impact(payload["tint"], payload["size"]), payload["at"])
		Kind.GUST:
			var blast: Node3D = SpellFx.gust(payload["size"], payload["tint"])
			_place(scene, blast, payload["at"])
			var facing: Vector3 = payload["dir"]
			if facing.length_squared() > 0.01:
				blast.look_at(blast.global_position + facing.normalized(), Vector3.UP)
		Kind.DECAL:
			_play_decal(scene, payload)
		Kind.GLOW:
			var owner_node: Node3D = player_for(int(payload.get("peer", 0)))
			if owner_node != null:
				owner_node.add_child(SpellFx.cast_glow(payload["tint"], payload["size"]))
		Kind.SOUND:
			SoundBank.play_at(StringName(payload["event"]), payload["at"])
		Kind.SHAKE:
			_play_shake(payload)
		Kind.NUMBER:
			SignalBus.damage_number_requested.emit(
				payload["at"], float(payload["size"]), payload["tint"], String(payload["slot"])
			)


func _place(scene: Node, node: Node3D, at: Vector3) -> void:
	scene.add_child(node)
	node.global_position = at


## A decal has to find the ground, and finding the ground needs a node in the world to
## raycast from. The caster is the honest one to ask; any player will do when that peer's
## avatar has not been built here yet (a decal a frame before the newcomer spawns).
func _play_decal(scene: Node, payload: Dictionary) -> void:
	var world: Node3D = player_for(int(payload.get("peer", 0)))
	if world == null:
		world = PlayerRegistry.get_local()
	if world == null:
		return
	var mark: MeshInstance3D = SpellFx.ground_decal(payload["slot"], payload["tint"], payload["size"])
	scene.add_child(mark)
	mark.global_transform = SpellFx.ground_transform(world, payload["at"])


## Full strength for whoever caused it, and by distance for everybody else.
##
## Both halves are needed. Without the first, a caster who blinks away from their own
## Wrath of God stops feeling the spell they just cast; without the second, every player
## in the run is shaken by everything anyone does anywhere on the map, which in a five
## player party is a camera that never stops moving.
func _play_shake(payload: Dictionary) -> void:
	var viewer: Node3D = PlayerRegistry.get_local()
	if viewer == null:
		return
	var strength: float = float(payload["size"])
	var peer: int = int(payload.get("peer", 0))
	if peer == 0 or player_for(peer) != viewer:
		var distance: float = viewer.global_position.distance_to(payload["at"])
		strength *= clampf(1.0 - distance / SHAKE_FALLOFF_RANGE, 0.0, 1.0)
		if strength <= 0.01:
			return
	SignalBus.camera_shake_requested.emit(strength, float(payload["time"]))


## The avatar `peer` owns. Public because MainController's effect spawner needs the same
## lookup for the caster it hands to a zone or a summon.
##
## Falls back to the local player in single-player, where there are no peer ids and
## `by_peer` has nothing to match on.
func player_for(peer: int) -> Node3D:
	if peer == 0:
		return null
	if not Net.is_active():
		return PlayerRegistry.get_local()
	return PlayerRegistry.by_peer(peer)
