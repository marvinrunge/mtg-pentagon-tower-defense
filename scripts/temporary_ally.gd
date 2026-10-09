extends CharacterBody3D
class_name TemporaryAlly
## Something on the player's side for a while and then gone.
##
## Two skills need one and they need almost the same thing, which is why this is one
## class rather than two: black's **Zombify** raises corpses as ghouls, and blue's
## **Phantasmal Decoy** drops an illusion that enemies attack instead of the player.
##
## A ghoul FIGHTS, and only up close. It sprints at the nearest enemy and trades blows with
## it, swinging with a melee rig's `attack` clip, until its time runs out or something kills
## it. (It once stood and swung with no attack clip at all, playing its walk cycle on the
## spot; the enemy rigs have had a real one since, and that is what it uses.)
##
## Its end is where Mayhem Devil, the black+red guild node, comes in (TemporaryAlly._explode,
## docs/GUILD_PLAN.md Stage 1): with it, a ghoul that is cut down or runs out of time BURSTS
## for area damage; without it, it simply crumbles. Zombify alone is a few bodies that hold
## and hit; the guild node turns each one into a bomb on top.
##
## It is deliberately NOT an EnemyBase with a flipped team. EnemyBase carries a wave
## registration, a colour identity, mana and XP on death, an elite modifier and a boss
## special; an ally that inherited all of that would pay the team for killing its own
## summons. What it needs is the small part: a body, some health, and a reason for
## enemies to look at it.
##
## Being in the `decoys` group is what makes enemies consider it at all - see
## `EnemyBase.evaluate_target`, which treats the group exactly the way it treats a myr.
## Both kinds are in it: a ghoul nothing would swing at could run the whole lane untouched.

## Which of the two this is. "undead" rushes in and fights; "decoy" stands where it was put
## and soaks attention.
var kind: String = "undead"
var health: float = 100.0
var max_health: float = 100.0
## For a ghoul, what its burst deals to everything in the radius - only ever dealt with
## Mayhem Devil. Unused by a decoy.
var attack_damage: float = 20.0
## For a ghoul, what one of its swings deals. Unused by a decoy.
var hit_damage: float = 20.0
var move_speed: float = 4.5
## How close a ghoul stops to swing, from its centre to its target's.
var attack_range: float = 1.8
## Bumped by the server on every swing and replicated, so each peer starts the same swing
## clip from it rather than guessing at one from velocity.
var attack_serial: int = 0
## How far it will run to find something. Small on purpose: a ghoul that chased across the
## map would end up bursting in a lane nobody asked it to.
var leash_range: float = 26.0
var owner_player: Node3D = null
## What this used to be, for Zombify - a raised corpse rises in the colour it died in. Null
## for a decoy, which is an illusion of nothing in particular.
##
## A field rather than node metadata: `set_meta(name, null)` stores nothing at all, and
## `get_meta(name, null)` is an ERROR rather than a fallback, so the null case - which is
## every single decoy - printed a stack trace on spawn.
var visual_source: EnemyData = null
## The same two facts as `visual_source`, as plain strings.
##
## An EnemyData is a Resource, and a Resource cannot travel through a MultiplayerSpawner's
## spawn argument - it arrives on the client as null, and the raised corpse comes back as
## an untextured box while the host sees the model it died in. These are what the visual
## is actually chosen from, so they are what is sent instead. Ignored when `visual_source`
## is set, which is the single-player and server-side path.
var visual_color: String = ""
var visual_class: String = ""

var _life_timer: float = 0.0
var _target: Node3D = null
var _retarget_timer: float = 0.0
var _visual: Node3D
var _anim: AnimationPlayer
## The locomotion clip a ghoul runs with - "run" where the rig has one.
var _move_clip: String = ""
var _bar_fill: MeshInstance3D
var _burst: bool = false
## Seconds until the next swing may start, and until the current one lands (-1: none due).
var _attack_cooldown: float = 0.0
var _impact_timer: float = -1.0
## The swing being played on this peer, so a new `attack_serial` is noticed once.
var _seen_attack_serial: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const RETARGET_INTERVAL := 0.4
const IDLE_CLIP := "idle"
## True while a ghoul with nothing to chase is on its way back to the player who raised it.
## Kept between frames so it has two edges: it sets off past the far radius and only stops
## inside the near one, instead of stuttering along a single line.
var _returning: bool = false
## The ghouls' own green - the tint, the burst and the Soul Orb all share it.
const UNDEAD_TINT := Color(0.35, 1.0, 0.45)
const DECOY_TINT := Color(0.4, 0.75, 1.0)


## Everything the ally needs, in one call, BEFORE it enters the tree - the same shape
## MainController._spawn_enemy uses, and for the same reason: a value set after _ready
## has already missed the frame that needed it.
##
## `visual_source` is the EnemyData of whatever this used to be, for Zombify. Passing it
## is what makes a raised corpse look like the thing that died rather than like a generic
## blob; a decoy passes none and gets the illusion look instead.
func configure(p_kind: String, p_health: float, p_duration: float, p_damage: float, p_owner: Node3D, p_visual_source: EnemyData = null) -> void:
	kind = p_kind
	health = p_health
	max_health = p_health
	attack_damage = p_damage
	owner_player = p_owner
	_life_timer = p_duration
	visual_source = p_visual_source


func _ready() -> void:
	add_to_group("allies")
	# The group enemies actually look for. Both kinds are in it - see the class comment.
	add_to_group("decoys")
	# Layer 2 is where the player and the myrs sit, which is what puts this body in front
	# of enemy fire (enemy projectile mask 19 covers it) without also making the player's
	# own projectiles collide with their summons.
	collision_layer = 2
	# The ground is on EnemyBase.ENVIRONMENT_LAYER, not layer 1 - masking only layer 1
	# left nothing underneath, and every summon fell out of the world the moment it rose.
	collision_mask = 1 | EnemyBase.ENVIRONMENT_LAYER
	if kind == "undead":
		move_speed = GameSettings.spell_black_zombify_speed

	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	body.shape = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)

	_build_visual()
	_build_health_bar()
	_build_synchronizer()


## Where it is and how fast it is going, from the server to everyone else.
##
## Summons used to replicate their existence and nothing more - the spawner puts one on every
## screen, but only the server moves it - so on a client a ghoul stood where it rose while the
## host watched it run. Velocity rides along because it is what picks the running or standing
## clip on a peer that does not think for itself.
func _build_synchronizer() -> void:
	if not Net.is_active():
		return
	var config := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":velocity", ":health", ":attack_serial"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(1)
	add_child(sync)


## A raised corpse rises as a melee body in the colour it died in; an illusion is a
## translucent blue copy of nothing in particular. Both go through the same path so the two
## only differ in the material laid over them.
##
## Always the MELEE model for a ghoul, whatever class the corpse was: a ghoul only ever
## fights hand to hand, and the archer's and the mage's `attack` clips are a bow being
## drawn and a spell being cast - a raised archer "hitting" something by aiming a bow at it
## read as broken. Their rigs are not all the same skeleton as the melee one either (six of
## its swing's tracks miss on some of them), so lending them the melee swing instead would
## distort on exactly those.
func _build_visual() -> void:
	var source: EnemyData = visual_source
	# The resource when there is one, the two replicated strings when there is not.
	var color: String = source.color_identity if source != null else visual_color
	var enemy_class: String = source.enemy_class if source != null else visual_class
	if kind == "undead":
		enemy_class = "Melee"
	var scene: PackedScene = null
	if color != "":
		if enemy_class == "Ranged" and EnemyBase.RANGED_VISUAL_SCENES.has(color):
			scene = EnemyBase.RANGED_VISUAL_SCENES[color]
		elif enemy_class == "Mage" and EnemyBase.MAGE_VISUAL_SCENES.has(color):
			scene = EnemyBase.MAGE_VISUAL_SCENES[color]
		elif EnemyBase.MELEE_VISUAL_SCENES.has(color):
			scene = EnemyBase.MELEE_VISUAL_SCENES[color]

	if scene != null:
		_visual = scene.instantiate()
		# Same 100x correction the enemies use: the imported models are ~0.016m tall.
		_visual.scale = Vector3(100, 100, 100)
		add_child(_visual)
		_anim = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim != null:
			# A ghoul sprints, so it runs where the rig can; a decoy never moves at all.
			for clip: String in (["run", "walk"] if kind == "undead" else ["walk"]):
				if _anim.has_animation(clip):
					_move_clip = clip
					break
	else:
		var box := CSGBox3D.new()
		box.size = Vector3(0.8, 1.7, 0.8)
		box.position = Vector3(0.0, 0.85, 0.0)
		_visual = box
		add_child(box)

	_apply_tint()
	_update_animation()


## The tint IS the readability of this feature. A raised corpse and the enemy standing
## next to it are the same model, so without a colour telling them apart the player
## cannot see what their own spell did.
func _apply_tint() -> void:
	var tint: Color = UNDEAD_TINT if kind == "undead" else DECOY_TINT
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = Color(tint.r, tint.g, tint.b, 0.55 if kind == "decoy" else 0.85)
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.emission_enabled = true
	overlay.emission = tint
	overlay.emission_energy_multiplier = 1.6
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_tint_recursive(_visual, overlay)

	var glow := OmniLight3D.new()
	glow.light_color = tint
	glow.light_energy = 1.4
	glow.omni_range = 3.5
	glow.position = Vector3(0.0, 1.2, 0.0)
	add_child(glow)


## `material_overlay` rather than `material_override`: the overlay draws ON TOP of the
## model's own materials, so the character keeps its shape and detail and only gains the
## colour. An override would flatten it into a silhouette.
func _tint_recursive(node: Node, overlay: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = overlay
	elif node is CSGBox3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (overlay as StandardMaterial3D).emission
		mat.emission_enabled = true
		mat.emission = (overlay as StandardMaterial3D).emission
		(node as CSGBox3D).material = mat
	for child: Node in node.get_children():
		_tint_recursive(child, overlay)


## A summon with a hidden timer is a summon the player cannot plan around, so the bar
## shows the LIFE remaining, not the health - the health is what the enemies are doing to
## it, but the clock is what the player has to spend.
func _build_health_bar() -> void:
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.12)
	bar.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UNDEAD_TINT if kind == "undead" else DECOY_TINT
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bar.material_override = mat
	bar.position = Vector3(0.0, 2.15, 0.0)
	_bar_fill = bar
	add_child(bar)


## Running while it moves and idling while it does not - read off velocity, so a client
## whose copy only receives the replicated velocity picks the same clip the server's does.
## The idle clip comes from tools/locomotion_pass.gd; a rig without one holds the first frame
## of its run instead of running on the spot.
func _update_animation() -> void:
	if _anim == null or _move_clip == "":
		return
	if attack_serial != _seen_attack_serial:
		_seen_attack_serial = attack_serial
		if _anim.has_animation("attack"):
			# Stretched to fill exactly one swing interval, the way EnemyBase.perform_attack
			# does, so it finishes as the next swing starts instead of restarting mid-way.
			var clip: Animation = _anim.get_animation("attack")
			_anim.play("attack", 0.1, clip.length / GameSettings.spell_black_zombify_attack_interval)
			return
	if _swinging():
		return
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.4
	var wanted: String = _move_clip
	if not moving:
		if not _anim.has_animation(IDLE_CLIP):
			if _anim.is_playing():
				_anim.play(_move_clip)
				_anim.seek(0.0, true)
				_anim.pause()
			return
		wanted = IDLE_CLIP
	if _anim.current_animation != wanted or not _anim.is_playing():
		_anim.play(wanted, 0.2)


func _physics_process(delta: float) -> void:
	_update_animation()
	# Summons are the server's, like every other combatant. A client renders what it is
	# told; running the AI on both ends would give two different answers.
	if not Net.is_server() or _burst:
		return

	_life_timer -= delta
	if _life_timer <= 0.0:
		_expire()
		return
	if is_instance_valid(_bar_fill) and max_health > 0.0:
		_bar_fill.scale.x = clampf(health / max_health, 0.05, 1.0)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# A decoy is a target and nothing else. It does not move, it does not swing - all it
	# does is exist somewhere the player would rather the enemies were looking.
	if kind != "undead":
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_attack_cooldown -= delta
	if _impact_timer >= 0.0:
		_impact_timer -= delta
		if _impact_timer < 0.0:
			_land_hit()

	_retarget_timer -= delta
	# A swing is committed to its target; picking another mid-swing would land it on
	# something it was never aimed at.
	if _retarget_timer <= 0.0 and _impact_timer < 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_acquire_target()

	if not is_instance_valid(_target):
		_follow_owner(delta)
		return
	_returning = false

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= attack_range or _swinging():
		# In reach: stand, face it and swing. Rooted for the whole swing, like an enemy's -
		# the clip has no root motion, so sliding through it would look like skating.
		velocity.x = 0.0
		velocity.z = 0.0
		if to_target.length() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 10.0 * delta)
		if _attack_cooldown <= 0.0 and to_target.length() <= attack_range:
			_start_swing()
		move_and_slide()
		return
	var direction: Vector3 = to_target.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 10.0 * delta)
	move_and_slide()


func _swinging() -> bool:
	return _anim != null and _anim.current_animation == "attack" and _anim.is_playing()


## Server only. The clip itself starts on every peer from the replicated `attack_serial`
## (see _update_animation); what lands, and when, is decided here.
func _start_swing() -> void:
	var interval: float = GameSettings.spell_black_zombify_attack_interval
	_attack_cooldown = interval
	attack_serial += 1
	var impact_ratio: float = 0.5
	if _anim != null and _anim.has_animation("attack"):
		impact_ratio = float(_anim.get_animation("attack").get_meta("hit_ratio", 0.5))
	_impact_timer = maxf(impact_ratio * interval, 0.01)
	SoundBank.play_at(&"blunt_swing", global_position)


## The swing's measured hit frame. Lands only if the target is still there and still in
## reach - stepping out of a ghoul's swing works the way stepping out of an enemy's does.
##
## Credited to the player who raised it, like the burst: what it kills is theirs and leaves
## an ordinary corpse. Not flagged as melee - the player's own melee perks (an execute
## threshold, say) are about their weapon, not about their summons.
func _land_hit() -> void:
	if not is_instance_valid(_target) or _target.is_queued_for_deletion():
		return
	var reach: float = attack_range * GameSettings.enemy_attack_impact_range_grace
	if global_position.distance_to(_target.global_position) > reach + 0.5:
		return
	if not _target.has_method("take_damage"):
		return
	var credited: Node3D = owner_player if is_instance_valid(owner_player) else null
	SoundBank.play_at(&"blunt_hit", _target.global_position)
	_target.take_damage(hit_damage * Player.anthem_damage_mult(self), credited)


## Nothing to chase: stay with the player who raised it. A ghoul left standing where its
## corpse lay is a ghoul the player walks away from and never sees burst; this keeps the pack
## at heel, so it is around the player when the next enemy comes into reach.
func _follow_owner(delta: float) -> void:
	var to_owner: Vector3 = Vector3.ZERO
	if is_instance_valid(owner_player):
		to_owner = owner_player.global_position - global_position
		to_owner.y = 0.0
	var distance: float = to_owner.length()
	if distance > GameSettings.spell_black_zombify_follow_far:
		_returning = true
	elif distance <= GameSettings.spell_black_zombify_follow_near:
		_returning = false
	if _returning and distance > 0.01:
		var direction: Vector3 = to_owner / distance
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 10.0 * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()


## Nearest living enemy inside the leash. Nearest rather than weakest or strongest,
## because a summon that ran past the thing standing on top of it to reach a better
## target would read as broken no matter how correct the choice was.
func _acquire_target() -> void:
	var best: Node3D = null
	var best_distance: float = leash_range
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	_target = best


func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false) -> void:
	if _burst:
		return
	# A white teammate's Glorious Anthem shelters summons too.
	amount *= Player.anthem_damage_taken_mult(self)
	health -= amount
	NetFx.damage_number(
		global_position + Vector3(0.0, 1.6, 0.0), amount, Color(0.8, 0.9, 1.0), ""
	)
	if health <= 0.0:
		_expire()


## Summons do not die, they end. No corpse, no mana, no XP - the team is not paid for
## losing its own summon, a raised corpse must not be raisable a second time, and a ghoul's
## end is not a death Grave Pact takes a soul from (it never emits enemy_died_at).
##
## A ghoul's end goes through _explode however it comes - timed out or cut down - and
## _explode decides whether that end is a burst or a crumble.
func _expire() -> void:
	if is_queued_for_deletion():
		return
	if kind == "undead":
		_explode()
		return
	queue_free()


## The ghoul's end. With Mayhem Devil (black+red guild node, docs/GUILD_PLAN.md Stage 1)
## it is a burst: everything around the ghoul takes its damage, credited to the player who
## raised it - so what it kills counts as theirs and leaves an ordinary corpse to raise.
## Without it the ghoul crumbles and hurts nothing. Server only; the visuals go out through
## NetFx so every screen sees the same end.
##
## Checked on owner_player rather than on `self`: a ghoul is a TemporaryAlly, not a Player,
## and has no skill tree of its own to ask.
func _explode() -> void:
	if _burst or not Net.is_server():
		return
	_burst = true
	var centre: Vector3 = global_position
	var credited: Node3D = owner_player if is_instance_valid(owner_player) else null
	if kind == "undead" and is_instance_valid(owner_player) and owner_player.has_method("has_guild") \
			and owner_player.has_guild("guild_rakdos"):
		var radius: float = GameSettings.spell_black_zombify_burst_radius
		var damage: float = attack_damage * Player.anthem_damage_mult(self)
		for enemy: Node in get_tree().get_nodes_in_group("enemies"):
			var body := enemy as Node3D
			if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
				continue
			if body.global_position.distance_to(centre) > radius:
				continue
			if body.has_method("take_damage"):
				body.take_damage(damage, credited)
		var at: Vector3 = centre + Vector3(0.0, 1.0, 0.0)
		NetFx.ring(centre, UNDEAD_TINT, radius)
		NetFx.impact(at, UNDEAD_TINT, radius * 0.5)
		NetFx.decal("decal_blight", Color(0.12, 0.3, 0.1, 0.75), radius * 0.8, centre, 0)
		NetFx.sound(&"zombie_burst", at)
		NetFx.shake(0.12, 0.2, centre, 0)
	elif kind == "undead":
		# No guild node: it falls apart where it stands. A small puff so it reads as the
		# summon ending, not as a model vanishing mid-frame.
		NetFx.impact(centre + Vector3(0.0, 0.8, 0.0), UNDEAD_TINT, 0.6)
	queue_free()
