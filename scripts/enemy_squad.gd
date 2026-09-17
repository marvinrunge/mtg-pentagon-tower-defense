extends Node
class_name EnemySquad
## One colour's contingent for a wave, marching as a body instead of as a queue.
##
## A squad owns an ANCHOR - an invisible point that walks down the lane - and every member
## navigates to its own slot measured off that anchor rather than to the crystal. The
## anchor moves at the speed of the squad's slowest member (see SquadDoctrine.march_mult),
## which is the whole trick: without it the melee outrun the mages within ten seconds and
## the formation the wave spawned in never exists again.
##
## A member stops following the anchor the moment the anchor stops being the right answer
## - it saw a player, it was taunted, feared, shoved out of its slot, or the squad reached
## the crystal - and from then on it is an ordinary enemy with ordinary AI. Formation is a
## way of ARRIVING, not a way of fighting.
##
## Server-only. Enemy AI already is (see EnemyBase._physics_process), and a squad is
## nothing but AI: clients see the result in the replicated transforms.
##
## Lifetime: created by WaveManager when a colour deploys, freed when it disbands or when
## its last member dies.

## MARCH  walking to its hold point, or straight down the lane when it has none
## RALLY  standing formed at the rendezvous, waiting for the rest of the warband
## CHARGE rally done (or never needed): everything runs at the crystal together
## SPENT  dissolved. Members are on their own and this node is on its way out
enum State { MARCH, RALLY, CHARGE, SPENT }

## Announced by the squad that actually starts the charge, relayed by WaveManager so the
## banner reaches clients too. `colors` is every colour charging together.
signal charge_started(colors: PackedStringArray)

var color: String = ""
var lane_index: int = 0
var doctrine: Dictionary = {}
var state: State = State.MARCH

## Where the formation is centred right now, and which way it is facing. `forward` is flat
## and unit length; SquadDoctrine.to_world derives the squad's right-hand axis from it.
var anchor: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.FORWARD

var crystal_position: Vector3 = Vector3.ZERO
## Where this squad holds while the rest of its battle group catches up, or Vector3.INF
## when it has nobody to wait for and simply walks its own lane. Per squad rather than one
## point shared by the group - see WaveManager._rally_point.
var rally_point: Vector3 = Vector3.INF
## Every squad in this battle group, THIS ONE INCLUDED. A solo squad holds only itself.
var warband: Array = []

## Deliberately untyped rather than Array[EnemyBase]. EnemyBase has to name EnemySquad
## and EnemySquad has to name EnemyBase, and a pair of class_name scripts that each
## annotate the other is exactly the cycle GDScript resolves badly. Members are reached by
## duck typing instead - join_squad / leave_formation / apply_squad_charge / is_dying /
## enemy_data are the whole contract, and EnemyBase is the only thing ever put in here.
var _members: Array = []
var _slots: Dictionary = {}
var _initial_size: int = 0
var _march_speed: float = 2.0
var _rallied: bool = false
var _rally_wait: float = 0.0


func _ready() -> void:
	# Clients never run a squad: they have no authority over any enemy's position, so a
	# second brain here would only burn frames disagreeing with the server's.
	set_physics_process(Net.is_server())


## Called once, before any member joins. `spawn_forward` is the lane's own direction of
## advance, which is also the direction the formation was laid out along.
func configure(squad_color: String, lane: int, spawn_anchor: Vector3, spawn_forward: Vector3, crystal: Vector3) -> void:
	color = squad_color
	lane_index = lane
	doctrine = SquadDoctrine.get_doctrine(squad_color)
	anchor = spawn_anchor
	forward = _flatten(spawn_forward, Vector3.FORWARD)
	crystal_position = crystal
	warband = [self]


## `local_slot` is the squad-local offset SquadDoctrine.build_formation produced for this
## enemy. The enemy is expected to already be standing on it.
func add_member(enemy, local_slot: Vector3) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_members.append(enemy)
	_slots[enemy.get_instance_id()] = local_slot
	_initial_size = _members.size()
	enemy.join_squad(self)
	_recompute_march_speed()


## Where this member should be standing at this instant. Falls back to the anchor itself
## for anything that somehow asks without a slot, which is a harmless place to walk to.
func formation_target(enemy) -> Vector3:
	var offset: Vector3 = _slots.get(enemy.get_instance_id(), Vector3.ZERO)
	return SquadDoctrine.to_world(anchor, forward, offset)


## Whether members should still be walking to their slots at all.
func holds_formation() -> bool:
	return state != State.SPENT


## Absolute speed cap for a member holding its slot, in units per second. Slightly above
## the anchor's own speed so somebody who fell behind can close the gap instead of
## trailing the formation forever at exactly the speed it is running away at.
func member_speed_limit() -> float:
	return _current_speed() * GameSettings.wave_squad_catchup_mult


func leash() -> float:
	return float(doctrine.get("leash", 14.0))


func breaks_on_damage() -> bool:
	return bool(doctrine.get("break_on_damage", false))


## A member deciding, for its own reasons, that it is done marching. Also the path every
## other exit takes: disband() calls it for everyone at once.
func release(enemy) -> void:
	_members.erase(enemy)
	if is_instance_valid(enemy):
		_slots.erase(enemy.get_instance_id())
	_recompute_march_speed()


## Red only: being hit is enough to make a goblin forget the plan.
func on_member_damaged(enemy) -> void:
	if breaks_on_damage() and is_instance_valid(enemy):
		enemy.leave_formation()


## The formation is over. Everyone left in it goes back to ordinary AI, keeping whatever
## charge bonus they are carrying - a squad that dissolves ON the crystal should not slow
## down at the moment of contact.
func disband() -> void:
	if state == State.SPENT:
		return
	state = State.SPENT
	for member in _members.duplicate():
		if is_instance_valid(member):
			member.leave_formation()
	_members.clear()
	_slots.clear()
	queue_free()


func _physics_process(delta: float) -> void:
	_prune()
	if state == State.SPENT:
		return
	if _members.is_empty():
		disband()
		return
	# A squad that has been shredded is not a formation any more, it is survivors. Letting
	# three enemies keep walking in rank towards a crystal they cannot threaten just makes
	# the wave take longer to end.
	if _initial_size > 0 and float(_members.size()) / float(_initial_size) < GameSettings.wave_squad_disband_fraction:
		disband()
		return

	if state == State.RALLY:
		_rally_wait += delta
		# The timeout is a safety net, not pacing: a partner that is alive but pinned down
		# the far side of the map must not park this squad at a rendezvous forever.
		if _warband_ready() or _rally_wait >= GameSettings.wave_rally_timeout:
			_begin_charge()
		else:
			return

	var heading_for_rally: bool = _has_rally() and not _rallied
	var goal: Vector3 = rally_point if heading_for_rally else crystal_position
	var to_goal: Vector3 = goal - anchor
	to_goal.y = 0.0
	var distance: float = to_goal.length()
	if distance > 0.05:
		_turn_towards(to_goal / distance, delta)

	if distance <= GameSettings.wave_squad_arrive_radius:
		if heading_for_rally:
			_rallied = true
			_rally_wait = 0.0
			if _warband_ready():
				_begin_charge()
			else:
				state = State.RALLY
			return
	else:
		anchor += forward * _current_speed() * delta

	var to_crystal: float = _flat_distance(anchor, crystal_position)
	var break_radius: float = float(doctrine.get("break_radius", 26.0))
	# The last stretch is a run, for a lone squad as much as for a warband. A warband has
	# already charged out of its rendezvous by now and this no-ops; a squad that had nobody
	# to meet gets its charge here instead, so no formation in the game simply walks into
	# contact at marching pace.
	if state == State.MARCH and to_crystal <= break_radius + GameSettings.wave_squad_charge_lead:
		_begin_charge()
	# Close enough to the objective that ranks stop helping and the fight starts. Every
	# colour picks its own distance for this; Red's is most of the lane. The charge bonus
	# lives on the members, so it survives this and they arrive still running.
	if to_crystal <= break_radius:
		disband()


func _prune() -> void:
	var live: Array = []
	for member in _members:
		# `is_dying` rather than only validity: a corpse is still a node for the couple of
		# seconds its death animation runs, and it should not be holding a slot or setting
		# the squad's march speed while it plays.
		if is_instance_valid(member) and not member.is_queued_for_deletion() and not member.is_dying:
			live.append(member)
		elif is_instance_valid(member):
			_slots.erase(member.get_instance_id())
	if live.size() != _members.size():
		_members = live
		_recompute_march_speed()


## The anchor moves at the slowest member's pace, scaled by the colour's discipline, and
## clamped to the FASTEST member so no doctrine can set a speed nobody in the squad is
## able to keep up with.
func _recompute_march_speed() -> void:
	var slowest: float = INF
	var fastest: float = 0.0
	for member in _members:
		if not is_instance_valid(member) or member.enemy_data == null:
			continue
		slowest = minf(slowest, member.enemy_data.speed)
		fastest = maxf(fastest, member.enemy_data.speed)
	if not is_finite(slowest) or fastest <= 0.0:
		return
	_march_speed = clampf(slowest * float(doctrine.get("march_mult", 1.0)), 0.25, fastest)


func _current_speed() -> float:
	if state == State.CHARGE:
		return _march_speed * float(doctrine.get("charge_mult", 1.25))
	return _march_speed


func _has_rally() -> bool:
	return rally_point.is_finite()


## A warband is ready when every squad in it has either reached the rendezvous or stopped
## existing. Counting the dead as ready is what stops a wiped partner stranding everybody
## else at a meeting point nobody is coming to.
func _warband_ready() -> bool:
	for squad in warband:
		if squad == null or not is_instance_valid(squad):
			continue
		if squad.state == State.SPENT:
			continue
		if not squad._rallied:
			return false
	return true


func _begin_charge() -> void:
	if state == State.CHARGE:
		return
	state = State.CHARGE
	_rallied = true
	var bonus: float = float(doctrine.get("charge_mult", 1.25))
	var seconds: float = float(doctrine.get("charge_seconds", 6.0))
	for member in _members:
		if is_instance_valid(member):
			member.apply_squad_charge(seconds, bonus)
	# Only the squad that TRIPS the charge announces it, and only when there was actually
	# a warband to wait for - five separate "charge" banners for one battle group is noise,
	# and a lone squad charging the last twenty metres of its own lane is not news.
	if warband.size() > 1 and _is_warband_leader():
		var colors: PackedStringArray = PackedStringArray()
		for squad in warband:
			if is_instance_valid(squad) and squad.state != State.SPENT:
				colors.append(squad.color)
		charge_started.emit(colors)
	for squad in warband:
		if is_instance_valid(squad) and squad != self and squad.state != State.SPENT:
			squad._begin_charge()


## The first still-standing squad in the warband, so exactly one of them speaks.
func _is_warband_leader() -> bool:
	for squad in warband:
		if is_instance_valid(squad) and squad.state != State.SPENT:
			return squad == self
	return true


## The formation WHEELS towards a new heading rather than snapping to it. A rendezvous
## sits off the lane's own axis, so without this the whole slot frame rotates forty degrees
## on the squad's first frame and every member is suddenly walking sideways to a slot that
## teleported around the anchor.
func _turn_towards(desired: Vector3, delta: float) -> void:
	var blended: Vector3 = forward.lerp(desired, clampf(GameSettings.wave_squad_turn_speed * delta, 0.0, 1.0))
	blended.y = 0.0
	# Exactly antiparallel headings cancel in a lerp. Nothing in the game turns a squad a
	# full half-circle, but a zero-length forward would put NaN into every slot in it.
	if blended.length_squared() < 0.0001:
		forward = desired
		return
	forward = blended.normalized()


## Squads live on a flat arena and their anchors never leave the floor, but the crystal
## marker and the lane spawners do not sit at exactly the same height - so break_radius is
## measured on the ground plane rather than through the air.
static func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


static func _flatten(vector: Vector3, fallback: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(vector.x, 0.0, vector.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()
