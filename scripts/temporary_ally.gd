extends CharacterBody3D
class_name TemporaryAlly
## Something that fights on the player's side for a while and then is gone.
##
## Two skills need one and they need almost the same thing, which is why this is one
## class rather than two: black's **Zombify** raises corpses that then attack, and blue's
## **Phantasmal Decoy** drops an illusion that enemies attack instead of the player. The
## difference between them is a single flag - whether it fights back.
##
## It is deliberately NOT an EnemyBase with a flipped team. EnemyBase carries a wave
## registration, a colour identity, mana and XP on death, an elite modifier and a boss
## special; an ally that inherited all of that would pay the team for killing its own
## summons. What it needs is the small part: a body, some health, and a reason for
## enemies to look at it.
##
## Being in the `decoys` group is what makes enemies consider it at all - see
## `EnemyBase.evaluate_target`, which treats the group exactly the way it treats a myr.
## Both kinds are in it: an undead that could not be attacked would be a turret, and a
## decoy nothing looked at would do nothing whatsoever.

## Which of the two this is. "undead" walks to the nearest enemy and hits it; "decoy"
## stands where it was put and soaks attention.
var kind: String = "undead"
var health: float = 100.0
var max_health: float = 100.0
var attack_damage: float = 20.0
var attack_interval: float = 1.2
var move_speed: float = 4.5
var attack_range: float = 2.4
## How far it will walk to find something. Small on purpose: an undead that chased
## across the map would end up defending a lane nobody asked it to.
var leash_range: float = 22.0
var owner_player: Node3D = null
## What this used to be, for Zombify - a raised corpse wears the model it died in. Null
## for a decoy, which is an illusion of nothing in particular.
##
## A field rather than node metadata: `set_meta(name, null)` stores nothing at all, and
## `get_meta(name, null)` is an ERROR rather than a fallback, so the null case - which is
## every single decoy - printed a stack trace on spawn.
var visual_source: EnemyData = null

var _life_timer: float = 0.0
var _attack_timer: float = 0.0
var _target: Node3D = null
var _retarget_timer: float = 0.0
var _visual: Node3D
var _bar_fill: MeshInstance3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const RETARGET_INTERVAL := 0.5


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
	collision_mask = 1

	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	body.shape = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)

	_build_visual()
	_build_health_bar()


## A raised corpse wears the model it died in; an illusion is a translucent blue copy of
## nothing in particular. Both go through the same path so the two only differ in the
## material laid over them.
func _build_visual() -> void:
	var source: EnemyData = visual_source
	var scene: PackedScene = null
	if source != null:
		if source.enemy_class == "Ranged" and EnemyBase.RANGED_VISUAL_SCENES.has(source.color_identity):
			scene = EnemyBase.RANGED_VISUAL_SCENES[source.color_identity]
		elif source.enemy_class == "Mage" and EnemyBase.MAGE_VISUAL_SCENES.has(source.color_identity):
			scene = EnemyBase.MAGE_VISUAL_SCENES[source.color_identity]
		elif EnemyBase.MELEE_VISUAL_SCENES.has(source.color_identity):
			scene = EnemyBase.MELEE_VISUAL_SCENES[source.color_identity]

	if scene != null:
		_visual = scene.instantiate()
		# Same 100x correction the enemies use: the imported models are ~0.016m tall.
		_visual.scale = Vector3(100, 100, 100)
		add_child(_visual)
		var anim: AnimationPlayer = _visual.find_child("AnimationPlayer", true, false)
		if anim != null and anim.has_animation("walk"):
			anim.play("walk")
	else:
		var box := CSGBox3D.new()
		box.size = Vector3(0.8, 1.7, 0.8)
		box.position = Vector3(0.0, 0.85, 0.0)
		_visual = box
		add_child(box)

	_apply_tint()


## The tint IS the readability of this feature. A raised corpse and the enemy standing
## next to it are the same model, so without a colour telling them apart the player
## cannot see what their own spell did.
func _apply_tint() -> void:
	var tint: Color = Color(0.35, 1.0, 0.45) if kind == "undead" else Color(0.4, 0.75, 1.0)
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
	mat.albedo_color = Color(0.35, 1.0, 0.45) if kind == "undead" else Color(0.4, 0.75, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bar.material_override = mat
	bar.position = Vector3(0.0, 2.15, 0.0)
	_bar_fill = bar
	add_child(bar)


func _physics_process(delta: float) -> void:
	# Summons are the server's, like every other combatant. A client renders what it is
	# told; running the AI on both ends would give two different answers.
	if not Net.is_server():
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

	if _attack_timer > 0.0:
		_attack_timer -= delta

	# A decoy is a target and nothing else. It does not move, it does not swing - all it
	# does is exist somewhere the player would rather the enemies were looking.
	if kind != "undead":
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_acquire_target()

	if not is_instance_valid(_target):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance > attack_range:
		var direction: Vector3 = to_target.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 8.0 * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_timer <= 0.0:
			_attack_timer = attack_interval
			SoundBank.play_at(&"blade_hit", global_position)
			if _target.has_method("take_damage"):
				_target.take_damage(attack_damage, self)
	move_and_slide()


## Nearest living enemy inside the leash. Nearest rather than weakest or strongest,
## because a summon that walked past the thing standing on top of it to reach a better
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
	health -= amount
	SignalBus.damage_number_requested.emit(
		global_position + Vector3(0.0, 1.6, 0.0), amount, Color(0.8, 0.9, 1.0)
	)
	if health <= 0.0:
		_expire()


## Summons do not die, they end. No corpse, no mana, no XP - the team is not paid for
## losing its own zombie, and a raised corpse must not be raisable a second time.
func _expire() -> void:
	if is_queued_for_deletion():
		return
	queue_free()
