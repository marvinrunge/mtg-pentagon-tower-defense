extends CharacterBody3D
class_name EnemyBase

var target_crystal: Node3D
var current_target: Node3D
var last_target_position: Vector3 = Vector3.INF

var _health_bar_scene: PackedScene = preload("res://scenes/ui/enemy_health_bar.tscn")

const MELEE_VISUAL_SCENES := {
	"White": preload("res://scenes/melee/human_melee.tscn"),
	"Blue": preload("res://scenes/melee/merfolk_melee.tscn"),
	"Black": preload("res://scenes/melee/zombie_melee.tscn"),
	"Red": preload("res://scenes/melee/goblin_melee.tscn"),
	"Green": preload("res://scenes/melee/elf_melee.tscn"),
}
# Own dedicated mesh/animation set per colour, distinct from melee (see
# tools/character_builder.gd) - no longer "melee minus weapon".
const RANGED_VISUAL_SCENES := {
	"White": preload("res://scenes/ranged/human_ranged.tscn"),
	"Blue": preload("res://scenes/ranged/merfolk_ranged.tscn"),
	"Black": preload("res://scenes/ranged/zombie_ranged.tscn"),
	"Red": preload("res://scenes/ranged/goblin_ranged.tscn"),
	"Green": preload("res://scenes/ranged/elf_ranged.tscn"),
}
const MAGE_VISUAL_SCENES := {
	"White": preload("res://scenes/mage/human_mage.tscn"),
	"Blue": preload("res://scenes/mage/merfolk_mage.tscn"),
	"Black": preload("res://scenes/mage/zombie_mage.tscn"),
	"Red": preload("res://scenes/mage/goblin_mage.tscn"),
	"Green": preload("res://scenes/mage/elf_mage.tscn"),
}

# Shared across every EnemyBase instance so the corpse cap applies project-wide.
static var _corpses: Array[EnemyBase] = []

# The melee/ranged libraries call the damage reaction "knockback"; the Mixamo boss
# libraries call it "hit". Resolved once per enemy so either naming works.
const REACTION_CLIP_CANDIDATES := ["knockback", "hit"]

# Some source death clips run very long (the zombie boss's is 11.6s) - cap how
# long a body is still visibly settling.
const DEATH_MAX_SECONDS := 4.0

var enemy_data: EnemyData
var health: float = 100.0
var health_bar: EnemyHealthBar
var visual_anim_player: AnimationPlayer
var is_dying: bool = false

# Playback multiplier for this enemy's clips. Stays 1.0 for regular enemies;
# bosses get a size-derived value so bigger ones move more ponderously.
var _anim_speed_scale: float = 1.0
var _reaction_clip: String = ""

# --- Boss special attack (telegraphed and dodgeable) ---
var _special_config: Dictionary = {}
var _special_cooldown_timer: float = 0.0
var _special_windup_timer: float = 0.0
var _special_total_timer: float = 0.0
var _is_special_active: bool = false
var _special_resolved: bool = false
var _special_indicator: AttackIndicator
var damage_penalty: float = 0.0
var penalty_timer: float = 0.0
var attack_cooldown: float = 0.0
## Seconds until the swing in flight actually connects, or -1 when nothing is in
## flight. An attack used to pay out on the frame it STARTED, which left its impact
## sound - and its damage - landing while the weapon was still behind the enemy's
## head. The clip now carries the frame it connects on, measured at build time by
## tools/animation_impact.gd, and this is that moment counting down.
var _impact_timer: float = -1.0
## Seconds of flinch left, and the gap before another one may start.
var _hit_react_timer: float = 0.0
var _hit_react_cooldown: float = 0.0
var frost_slow_timer: float = 0.0
var path_update_timer: float = 0.0

# --- MTG Status Effects ---
var chill_stacks: int = 0
var freeze_timer: float = 0.0
var root_timer: float = 0.0
var stun_timer: float = 0.0
var blind_timer: float = 0.0
var curse_timer: float = 0.0
var curse_mult: float = 1.0
var pacified_timer: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aggro_area: Area3D = $AggroArea
@onready var aggro_col: CollisionShape3D = $AggroArea/CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# For Mages
var cast_timer: float = 0.0
var target_eval_timer: float = 0.0
var elite_modifier: String = ""
var elite_regeneration_per_second: float = 0.0
var elite_crystal_damage_multiplier: float = 1.0
var has_green_mage_buff: bool = false

func _ready() -> void:
	# Spawned through MultiplayerSpawner, so the colour/class pair arrives as metadata
	# that _spawn_enemy set identically on every peer - setup() then rebuilds the same
	# EnemyData locally rather than trying to replicate a Resource.
	if has_meta("enemy_color") and has_meta("enemy_type"):
		setup(EnemyDatabase.get_enemy_data(String(get_meta("enemy_color")), String(get_meta("enemy_type"))))
	_build_synchronizer()
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 31
	
	if has_meta("target_crystal"):
		target_crystal = get_meta("target_crystal")
	else:
		var crystal_nodes = get_tree().get_nodes_in_group("crystal")
		if crystal_nodes.size() > 0:
			target_crystal = crystal_nodes[0]
			
	current_target = target_crystal
	update_path(true)
	
	if aggro_area:
		aggro_area.body_entered.connect(_on_aggro_body_entered)
		aggro_area.body_exited.connect(_on_aggro_body_exited)

func setup(data: EnemyData) -> void:
	enemy_data = data
	# EnemyDatabase hands out a fresh EnemyData per enemy, so scaling it here is safe and
	# keeps max health, the health bar and the flinch threshold all reading one number.
	enemy_data.health *= GameSettings.get_enemy_health_factor(PlayerRegistry.count())
	health = enemy_data.health
	
	# Adjust Aggro Area based on range
	if aggro_col and aggro_col.shape is SphereShape3D:
		var shape: SphereShape3D = aggro_col.shape as SphereShape3D
		shape.radius = _get_detection_range()
		
	cast_timer = data.attack_speed

	# Visuals. Bosses have their own dedicated models; if one is missing they fall
	# back to the scaled-up melee model that stood in for them previously.
	var visual_scene: PackedScene = null
	if data.enemy_class == "Boss":
		visual_scene = BossDatabase.get_visual_scene(data.color_identity)
	if visual_scene == null:
		if (data.enemy_class == "Melee" or data.enemy_class == "Boss") and MELEE_VISUAL_SCENES.has(data.color_identity):
			visual_scene = MELEE_VISUAL_SCENES[data.color_identity]
		elif data.enemy_class == "Ranged" and RANGED_VISUAL_SCENES.has(data.color_identity):
			visual_scene = RANGED_VISUAL_SCENES[data.color_identity]
		elif data.enemy_class == "Mage" and MAGE_VISUAL_SCENES.has(data.color_identity):
			visual_scene = MAGE_VISUAL_SCENES[data.color_identity]

	if visual_scene:
		var visual_instance: Node3D = visual_scene.instantiate()
		# Scale correction: imported models are tiny (~0.016m). We scale them up 100x to match a 1-unit base.
		visual_instance.scale = Vector3(100, 100, 100)
		add_child(visual_instance)
		# find_child rather than get_node: it holds for both the melee scenes (player
		# is a direct child) and the imported boss scenes, without assuming depth.
		visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
		_reaction_clip = _resolve_reaction_clip()
		_rest_visual_animation()
	else:
		var visual = CSGBox3D.new()
		visual.size = Vector3(0.8, 1.7, 0.8)
		visual.position = Vector3(0, 0.85, 0)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = data.visual_color
		mat.roughness = 0.5
		visual.material = mat
		add_child(visual)

	scale = Vector3(data.model_scale, data.model_scale, data.model_scale)
	aggro_area.scale = Vector3.ONE / maxf(data.model_scale, 0.01)
	health_bar = _health_bar_scene.instantiate() as EnemyHealthBar
	add_child(health_bar)
	health_bar.set_health(health, data.health)

	if data.enemy_class == "Boss":
		_anim_speed_scale = GameSettings.get_boss_anim_speed(data.model_scale)
		# A boss that animates slower should also swing less often - otherwise
		# perform_attack() just compresses the swing back to normal speed to fit
		# the unchanged cadence and the size never reads in the animation.
		data.attack_speed /= maxf(_anim_speed_scale, 0.01)
		_special_config = BossDatabase.get_special(data.color_identity)
		_special_cooldown_timer = GameSettings.boss_special_first_delay

	if has_meta("elite_modifier"):
		apply_elite_modifier(String(get_meta("elite_modifier")))

func update_path(force_update: bool = false) -> void:
	if not nav_agent:
		return
	
	var target_pos: Vector3 = Vector3.ZERO
	if current_target and is_instance_valid(current_target):
		target_pos = current_target.global_position
	elif target_crystal and is_instance_valid(target_crystal):
		target_pos = target_crystal.global_position
		
	if force_update or target_pos.distance_squared_to(last_target_position) > 0.1:
		nav_agent.target_position = target_pos
		last_target_position = target_pos

## Position, rotation and health, authored by the server. An enemy's AI is expensive
## and must reach the same answer everywhere, so only the server runs it; clients render
## what they are told and keep their own animator fed from the replicated transform.
func _build_synchronizer() -> void:
	if not Net.is_active():
		return
	var config := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":health"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(1)
	add_child(sync)


func _physics_process(delta: float) -> void:
	if not enemy_data:
		return # Not initialized yet
	if is_dying:
		return
	if not Net.is_server():
		# A client's enemy is a puppet: its transform arrives over the wire and its AI
		# would only fight that. It still animates, from the same walk/attack state the
		# replicated motion implies.
		_update_visual_animation()
		return

	if elite_regeneration_per_second > 0.0 and health < enemy_data.health:
		heal(elite_regeneration_per_second * delta, false)
		
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	if frost_slow_timer > 0:
		frost_slow_timer -= delta
		
	if penalty_timer > 0:
		penalty_timer -= delta
		if penalty_timer <= 0:
			damage_penalty = 0.0
			
	if attack_cooldown > 0:
		attack_cooldown -= delta

	if _hit_react_cooldown > 0.0:
		_hit_react_cooldown -= delta
	if _hit_react_timer > 0.0:
		_hit_react_timer -= delta

	if _impact_timer >= 0.0:
		_impact_timer -= delta
		if _impact_timer <= 0.0:
			_impact_timer = -1.0
			_resolve_attack_impact()
		
	if enemy_data.enemy_class == "Mage":
		cast_timer -= delta
		if cast_timer <= 0:
			perform_mage_spell()
			# Spells have a longer cooldown than regular attacks
			cast_timer = enemy_data.attack_speed * GameSettings.enemy_mage_spell_cooldown_mult
			
	var dist_to_target = 999.0
	if is_instance_valid(current_target):
		dist_to_target = global_position.distance_to(current_target.global_position)
		# Update path periodically so they track moving targets like the player
		path_update_timer -= delta
		if path_update_timer <= 0:
			path_update_timer = GameSettings.enemy_path_update_interval
			update_path()
		
	target_eval_timer -= delta
	if target_eval_timer <= 0:
		target_eval_timer = GameSettings.enemy_target_eval_interval
		evaluate_target()
		
	# Process Knockback & Wall Collision
	if knockback_velocity.length_squared() > 0.1:
		var collision = move_and_collide(knockback_velocity * delta)
		if collision:
			var collider = collision.get_collider()
			if collider and not collider.is_in_group("enemies"):
				take_damage(GameSettings.spell_blue_unsummon_impact_damage)
				knockback_velocity = Vector3.ZERO
		else:
			knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)
			
	# Process Timers
	if freeze_timer > 0: freeze_timer -= delta
	if root_timer > 0: root_timer -= delta
	if stun_timer > 0: stun_timer -= delta
	if blind_timer > 0: blind_timer -= delta
	if curse_timer > 0: curse_timer -= delta
	if pacified_timer > 0:
		pacified_timer -= delta
		if pacified_timer <= 0:
			damage_penalty = 0.0

	# Boss special attack. Runs before the normal movement/attack block because a
	# committed special overrides both - the boss is rooted for its whole duration.
	if _special_cooldown_timer > 0.0:
		_special_cooldown_timer -= delta
	if _is_special_active:
		_process_special(delta)
		return
	if _can_begin_special(dist_to_target):
		_begin_special()
		_process_special(0.0)
		return

	# Disable movement if frozen, stunned, or mid-attack-swing (the swing has no
	# root motion of its own - moving the body while it plays would make the legs
	# look planted while the character visibly slides).
	var is_attack_swing_playing: bool = visual_anim_player != null and visual_anim_player.current_animation == "attack" and visual_anim_player.is_playing()
	if freeze_timer > 0 or stun_timer > 0 or is_attack_swing_playing:
		# A shooter keeps tracking through its own wind-up. Its projectile leaves on a
		# measured frame partway into the clip (see _resolve_attack_impact), and that
		# shot is aimed from live positions - so a body still pointing where the target
		# stood when the animation started reads as firing sideways. A melee swing is
		# deliberately NOT tracked: committing to a direction is what makes stepping
		# out of one work. Frozen or stunned, nothing turns at all.
		if is_attack_swing_playing and freeze_timer <= 0 and stun_timer <= 0 and _tracks_target_while_attacking():
			_face_target(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_visual_animation()
		return

	# Movement
	var is_in_attack_range: bool = dist_to_target <= enemy_data.attack_range
	if not is_in_attack_range and root_timer <= 0 and not nav_agent.is_navigation_finished():
		var next_path_position = nav_agent.get_next_path_position()
		var speed_mult: float = 1.0
		if frost_slow_timer > 0:
			speed_mult = GameSettings.enemy_frost_slow_mult
		var new_velocity: Vector3 = (next_path_position - global_position).normalized() * enemy_data.speed * speed_mult
		velocity.x = new_velocity.x
		velocity.z = new_velocity.z
		
		if velocity.length_squared() > 0.01:
			var target_rotation = atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, GameSettings.enemy_turn_speed * delta)
			
		move_and_slide()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

		if not is_in_attack_range:
			if root_timer <= 0 and nav_agent.is_navigation_finished():
				update_path(true)
			_update_visual_animation()
			return

		_face_target(delta)

		if attack_cooldown <= 0 and blind_timer <= 0:
			perform_attack()

	_update_visual_animation()

## Turns towards whatever this enemy is currently attacking. No-ops without a live
## target, so callers do not each need their own validity check.
func _face_target(delta: float) -> void:
	if not is_instance_valid(current_target):
		return
	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return
	var target_rotation: float = atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, GameSettings.enemy_turn_speed * delta)


## Whether this class attacks at range rather than by connecting with something.
## Shooters keep aiming while their attack clip plays, because they release partway
## through it - anything that swings a weapon does not, because a swing that tracked
## its target could never be side-stepped - and they make a release noise rather than
## a swing-and-impact pair.
func _is_shooter() -> bool:
	return enemy_data != null and (enemy_data.enemy_class == "Ranged" or enemy_data.enemy_class == "Mage")


func _tracks_target_while_attacking() -> bool:
	return _is_shooter()


func _update_visual_animation() -> void:
	if not visual_anim_player:
		return
	if (_hit_react_timer > 0.0 or knockback_velocity.length_squared() > 0.1) and _reaction_clip != "":
		# Squeezed into the flinch window the same way the player's reactions are:
		# the raw clips run about a second, which is far too long to hand over.
		_play_visual_animation(_reaction_clip, _reaction_speed_scale())
	elif visual_anim_player.current_animation == "attack" and visual_anim_player.is_playing():
		pass # Let the attack swing finish before switching states.
	elif Vector2(velocity.x, velocity.z).length_squared() > 0.01:
		_play_visual_animation("walk")
	else:
		_rest_visual_animation()

func _play_visual_animation(anim_name: String, speed_scale: float = -1.0) -> void:
	var speed: float = _anim_speed_scale if speed_scale <= 0.0 else speed_scale
	if visual_anim_player.current_animation != anim_name or not visual_anim_player.is_playing():
		visual_anim_player.play(anim_name, -1, speed)


## Playback rate that fits the flinch clip into enemy_hit_react_duration, scaled by
## this enemy's own animation pace so a boss still flinches ponderously.
func _reaction_speed_scale() -> float:
	var clip: Animation = visual_anim_player.get_animation(_reaction_clip)
	if clip == null or clip.length <= 0.0:
		return _anim_speed_scale
	return maxf(clip.length / maxf(GameSettings.enemy_hit_react_duration, 0.05), 0.05) * _anim_speed_scale

## Whichever name this enemy's animation library uses for its damage reaction.
func _resolve_reaction_clip() -> String:
	if visual_anim_player == null:
		return ""
	for candidate in REACTION_CLIP_CANDIDATES:
		if visual_anim_player.has_animation(candidate):
			return candidate
	return ""

# No dedicated idle clip - hold the first frame of "walk" instead. Avoids ever
# switching between two different poses (idle vs walk) right at the attack-range
# boundary, which was the main source of visible flicker.
func _rest_visual_animation() -> void:
	if visual_anim_player.current_animation != "walk":
		visual_anim_player.play("walk", -1, _anim_speed_scale)
	if visual_anim_player.is_playing():
		visual_anim_player.pause()

# ============================================================
# BOSS SPECIAL ATTACK
#
# A special is a committed, telegraphed swing: the boss roots itself, an
# AttackIndicator draws the danger zone on the ground, and the damage only lands
# once the indicator has filled. That fill window is the dodge - move out of the
# circle, or out of the arc for the cone shapes, and the hit misses entirely.
# ============================================================

func _can_begin_special(dist_to_target: float) -> bool:
	if _special_config.is_empty() or _special_cooldown_timer > 0.0:
		return false
	# Needs a real clip to telegraph with; the placeholder-box fallback has none.
	if visual_anim_player == null or not visual_anim_player.has_animation("special"):
		return false
	if freeze_timer > 0.0 or stun_timer > 0.0 or root_timer > 0.0 or blind_timer > 0.0 or pacified_timer > 0.0:
		return false
	if not is_instance_valid(current_target):
		return false
	# Only ever aimed at something that can actually dodge. The crystal can't, and
	# isn't in the hit set either, so letting a boss special the crystal would just
	# burn the cooldown on a guaranteed whiff while it stopped hitting the crystal.
	if not current_target.is_in_group("player") and not current_target.is_in_group("myrs"):
		return false
	# Held back at point-blank range so the boss still uses its ordinary swing up
	# close, and skipped entirely if the target could not be reached anyway.
	var reach: float = float(_special_config.get("radius", 5.0)) * 0.9
	return dist_to_target >= GameSettings.boss_special_min_range and dist_to_target <= reach

func _begin_special() -> void:
	var anim: Animation = visual_anim_player.get_animation("special")
	var clip_length: float = anim.length if anim else 1.5
	var playback_speed: float = maxf(_anim_speed_scale, 0.05)
	var impact_fraction: float = clampf(float(_special_config.get("impact_fraction", 0.5)), 0.05, 0.95)

	_is_special_active = true
	_special_resolved = false
	_special_total_timer = clip_length / playback_speed
	_special_windup_timer = _special_total_timer * impact_fraction

	visual_anim_player.play("special", -1, playback_speed)

	# Lock facing at commit time. The cone shapes are dodged by leaving the arc, so
	# the boss must not keep tracking the target once the indicator is drawn.
	if is_instance_valid(current_target):
		var to_target: Vector3 = current_target.global_position - global_position
		if Vector2(to_target.x, to_target.z).length_squared() > 0.01:
			rotation.y = atan2(to_target.x, to_target.z)

	var shape: AttackIndicator.Shape = AttackIndicator.Shape.CIRCLE
	if String(_special_config.get("shape", "circle")) == "cone":
		shape = AttackIndicator.Shape.CONE
	_special_indicator = AttackIndicator.spawn(
		self,
		shape,
		float(_special_config.get("radius", 5.0)),
		float(_special_config.get("angle", 360.0)),
		_special_windup_timer,
		_special_config.get("tint", Color(1.0, 0.4, 0.1)),
		enemy_data.model_scale
	)

func _process_special(delta: float) -> void:
	# Rooted for the whole special: these clips carry their own footwork, and the
	# danger zone is drawn where the boss stood when it committed.
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	if not _special_resolved:
		_special_windup_timer -= delta
		if _special_windup_timer <= 0.0:
			_resolve_special()

	_special_total_timer -= delta
	if _special_total_timer <= 0.0:
		if not _special_resolved:
			_resolve_special()
		_is_special_active = false

func _resolve_special() -> void:
	_special_resolved = true
	_special_cooldown_timer = GameSettings.boss_special_cooldown
	# Sounded from the boss's own feet rather than from whatever it caught: every
	# special is a slam, a sweep or a landing centred on the boss, and it makes that
	# noise whether or not anyone was still standing in the circle.
	SoundBank.play_at(&"heavy_landing", global_position)

	if _special_indicator and is_instance_valid(_special_indicator):
		_special_indicator.resolve()
	_special_indicator = null

	var damage: float = enemy_data.attack_damage
	damage *= float(_special_config.get("damage_mult", GameSettings.boss_special_damage_mult))
	damage *= GameSettings.get_player_scaling_factor(get_tree())

	var hit_player: bool = false
	for target in _special_targets_in_shape():
		if target.has_method("take_damage"):
			target.take_damage(damage, self, true)
			if target.is_in_group("player"):
				hit_player = true

	# Felt even on a clean dodge, just softer - a slam this size landing next to
	# you should register.
	var radius: float = float(_special_config.get("radius", 5.0))
	if hit_player:
		_request_camera_shake(true)
	elif _is_player_within(radius * 1.6):
		_request_camera_shake(false)

func _special_targets_in_shape() -> Array[Node3D]:
	var results: Array[Node3D] = []
	var radius: float = float(_special_config.get("radius", 5.0))
	var is_cone: bool = String(_special_config.get("shape", "circle")) == "cone"
	var half_angle: float = deg_to_rad(float(_special_config.get("angle", 360.0))) * 0.5

	# +Z is forward for these enemies (they turn with atan2(dir.x, dir.z)), and the
	# basis has to be normalized because the boss carries a large model scale.
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return results
	forward = forward.normalized()

	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("myrs"))
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		if candidate.is_in_group("player") and "is_downed" in candidate and candidate.is_downed:
			continue
		var offset: Vector3 = (candidate as Node3D).global_position - global_position
		offset.y = 0.0
		if offset.length() > radius:
			continue
		if is_cone and offset.length_squared() > 0.0001:
			if forward.angle_to(offset.normalized()) > half_angle:
				continue
		results.append(candidate as Node3D)
	return results

func _is_player_within(distance: float) -> bool:
	for player in get_tree().get_nodes_in_group("player"):
		if player is Node3D and is_instance_valid(player):
			if global_position.distance_to((player as Node3D).global_position) <= distance:
				return true
	return false

## Physics-space sphere query around this enemy, filtered by collision layer
## (e.g. 4 = "Enemies"). Broadphase-accelerated, unlike looping every node in
## a group - use this instead for AoE effects that scale with wave size.
func _bodies_in_range(radius: float, mask: int) -> Array[Node3D]:
	var results: Array[Node3D] = []
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result: Dictionary in space_state.intersect_shape(query, 64):
		var collider: Object = result.get("collider")
		if collider is Node3D and is_instance_valid(collider):
			results.append(collider as Node3D)
	return results

## Heavy shakes are boss specials landing on the player; light ones are the boss's
## ordinary swing, or a special that just missed.
func _request_camera_shake(is_heavy: bool) -> void:
	if not GameSettings.camera_shake_enabled:
		return
	var strength: float = GameSettings.camera_shake_heavy_strength if is_heavy else GameSettings.camera_shake_light_strength
	var duration: float = GameSettings.camera_shake_heavy_duration if is_heavy else GameSettings.camera_shake_light_duration
	SignalBus.camera_shake_requested.emit(strength * GameSettings.camera_shake_strength_mult, duration)

func _cancel_special() -> void:
	if _special_indicator and is_instance_valid(_special_indicator):
		_special_indicator.cancel()
	_special_indicator = null
	_is_special_active = false

func perform_attack() -> void:
	if not is_instance_valid(current_target):
		evaluate_target()
		return
		
	# Propaganda, the blue enchantment: every enemy attacks and casts more slowly. A
	# multiplier above 1 lengthens the gap between swings.
	attack_cooldown = enemy_data.attack_speed * RunState.enemy_attack_speed_multiplier()

	# Apply frost slow if active
	if frost_slow_timer > 0:
		attack_cooldown /= GameSettings.enemy_frost_slow_mult # Slower attacks when frosted

	# Every class now has a real "attack" clip (Ranged/Mage previously fired with
	# no visual windup at all - their models only got real animations recently).
	var impact_ratio: float = 0.5
	if visual_anim_player and visual_anim_player.has_animation("attack"):
		# Match the swing's playback speed to the actual attack cadence so it always
		# finishes exactly as the next attack fires, instead of restarting mid-swing.
		var attack_anim: Animation = visual_anim_player.get_animation("attack")
		var speed_scale: float = attack_anim.length / attack_cooldown if attack_cooldown > 0.0 else 1.0
		visual_anim_player.play("attack", -1, speed_scale)
		impact_ratio = float(attack_anim.get_meta("hit_ratio", 0.5))

	# A shooter's noise is its release, which happens partway into the clip; everyone
	# else is swinging something, and that is heard now whether or not it connects.
	if not _is_shooter():
		SoundBank.play_at(&"blunt_swing", global_position)

	# Nothing lands yet. The swing is stretched to fill exactly one attack cooldown,
	# so the measured fraction converts straight into seconds from here, and what the
	# swing commits to is settled in _resolve_attack_impact.
	_impact_timer = maxf(impact_ratio * attack_cooldown, 0.01)


## The frame the swing in flight connects on. What that means depends on the class:
## a shooter releases its projectile, everyone else lands - or misses - a hit.
##
## Re-checking the target here rather than trusting the one picked when the swing
## started is the point of moving the payout. The enemy is rooted for the whole
## swing (see the is_attack_swing_playing guard in _physics_process), so a target
## that walks out of reach during the wind-up now escapes the hit instead of being
## struck from across the gap; GameSettings.enemy_attack_impact_range_grace is the
## forgiveness on that.
func _resolve_attack_impact() -> void:
	if is_dying or enemy_data == null:
		return

	if _is_shooter():
		if not is_instance_valid(current_target):
			return
		SoundBank.play_at(&"arrow_shot", global_position)
		fire_projectile()
		return

	var reach: float = enemy_data.attack_range * GameSettings.enemy_attack_impact_range_grace
	if not is_instance_valid(current_target) or global_position.distance_to(current_target.global_position) > reach:
		# Missed. The swing through the air was already heard when it started, and
		# nothing arrives after it.
		return

	var actual_damage: float = max(0.0, enemy_data.attack_damage - damage_penalty)
	if current_target == target_crystal:
		actual_damage *= elite_crystal_damage_multiplier
	actual_damage *= GameSettings.get_player_scaling_factor(get_tree())

	# The crystal has no take_damage() of its own - it is hit through the bus - but a
	# weapon landing on it still sounds like a weapon landing.
	if current_target == target_crystal:
		SoundBank.play_at(&"blunt_hit", current_target.global_position)
		SignalBus.crystal_damaged.emit(actual_damage * _crystal_ward_multiplier())
		return

	if current_target.has_method("take_damage"):
		SoundBank.play_at(&"blunt_hit", current_target.global_position)
		current_target.take_damage(actual_damage, self, true)
		if enemy_data.enemy_class == "Boss" and current_target.is_in_group("player"):
			_request_camera_shake(false)


## Sphere of Safety, the white enchantment: an enemy standing inside the ward hurts
## the crystal less. Radius grows per stack, so late stacks also protect the approach
## rather than only the last step of it.
func _crystal_ward_multiplier() -> float:
	var reduction: float = RunState.crystal_damage_reduction()
	if reduction <= 0.0 or not is_instance_valid(target_crystal):
		return 1.0
	var ward: float = GameSettings.player_base_proximity + RunState.crystal_ward_radius()
	if global_position.distance_to(target_crystal.global_position) > ward:
		return 1.0
	return 1.0 - reduction


func fire_projectile() -> void:
	var proj = ProjectilePool.get_projectile()
	if proj:
		# Add a little height so it shoots from chest/head level
		var start_pos = global_position + Vector3(0, 1.2, 0)
		var target_pos = current_target.global_position
		if current_target == target_crystal:
			target_pos += Vector3(0, 2.0, 0) # Aim at crystal center
		elif current_target.is_in_group("player") or current_target.is_in_group("myrs"):
			target_pos += Vector3(0, 1.0, 0) # Aim at player chest
		
		var dir = (target_pos - start_pos).normalized()
		
		var actual_damage = max(0.0, enemy_data.attack_damage - damage_penalty)
		if current_target == target_crystal:
			actual_damage *= elite_crystal_damage_multiplier
		actual_damage *= GameSettings.get_player_scaling_factor(get_tree())
		
		proj.activate(start_pos, dir, 3, true, 1.0, actual_damage, 0.0, self)

func perform_mage_spell() -> void:
	match enemy_data.color_identity:
		"White":
			# AoE Heal - a physics broadphase query instead of scanning every
			# enemy in the level, so this doesn't scale with wave size.
			for e: Node3D in _bodies_in_range(GameSettings.enemy_white_mage_range, 4):
				if e.has_method("heal"):
					e.heal(GameSettings.enemy_white_mage_heal)
		"Red":
			# Damagedealer (Fireball at player)
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < GameSettings.enemy_red_mage_range:
				if players[0].has_method("take_damage"):
					var scaled_damage = enemy_data.attack_damage * GameSettings.get_player_scaling_factor(get_tree())
					players[0].take_damage(scaled_damage)
		"Blue":
			# Slows player
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < GameSettings.enemy_blue_mage_range:
				if players[0].has_method("apply_slow"):
					players[0].apply_slow(GameSettings.enemy_blue_mage_slow_duration)
		"Black":
			# Revive weak enemy
			# Just spawn a new weak melee of the same color
			var revived_data = EnemyDatabase.get_enemy_data("Black", "Melee")
			var enemy_scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
			var new_enemy = enemy_scene.instantiate()
			new_enemy.position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			new_enemy.set_meta("target_crystal", target_crystal)
			get_parent().add_child(new_enemy)
			# Needs to be setup after adding to tree usually, but we can call setup directly
			new_enemy.setup(revived_data)
			new_enemy.health = revived_data.health * GameSettings.enemy_black_mage_revive_hp_mult
			var wm = get_tree().current_scene.get_node_or_null("WaveManager")
			if wm:
				wm.register_enemy()
		"Green":
			# Buff enemy (Giant Growth)
			var enemies = get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) < GameSettings.enemy_green_mage_range:
					if e.has_method("apply_green_mage_buff") and e.apply_green_mage_buff():
						break

func apply_green_mage_buff() -> bool:
	if has_green_mage_buff or not enemy_data:
		return false
	has_green_mage_buff = true
	scale *= GameSettings.enemy_green_mage_buff_scale
	enemy_data.attack_damage *= GameSettings.enemy_green_mage_buff_damage
	return true

func heal(amount: float, show_damage_number: bool = true) -> void:
	if enemy_data:
		health = min(enemy_data.health, health + amount)
		if health_bar:
			health_bar.set_health(health, enemy_data.health)
		if show_damage_number:
			var spawn_pos = global_position + Vector3(0, 1.8, 0)
			SignalBus.damage_number_requested.emit(spawn_pos, -amount, Color(0.2, 1.0, 0.4))

func apply_elite_modifier(modifier: String) -> void:
	elite_modifier = modifier
	match elite_modifier:
		"Haste":
			enemy_data.speed *= GameSettings.enemy_elite_haste_speed_mult
			enemy_data.attack_speed *= GameSettings.enemy_elite_haste_attack_speed_mult
		"Regenerator":
			enemy_data.health *= GameSettings.enemy_elite_regenerator_health_mult
			elite_regeneration_per_second = enemy_data.health * GameSettings.enemy_elite_regenerator_heal_pct_per_second
		"Juggernaut":
			enemy_data.health *= GameSettings.enemy_elite_juggernaut_health_mult
			enemy_data.attack_damage *= GameSettings.enemy_elite_juggernaut_damage_mult
			enemy_data.speed *= GameSettings.enemy_elite_juggernaut_speed_mult
		"Crystal Hunter":
			elite_crystal_damage_multiplier = GameSettings.enemy_elite_crystal_hunter_damage_mult

	health = enemy_data.health
	if health_bar:
		health_bar.set_health(health, enemy_data.health)

func _get_detection_range() -> float:
	if enemy_data and (enemy_data.enemy_class == "Mage" or enemy_data.enemy_class == "Ranged"):
		return GameSettings.enemy_ranged_detection_range
	return GameSettings.enemy_melee_detection_range

func evaluate_target() -> void:
	if pacified_timer > 0.0:
		if current_target != target_crystal:
			current_target = target_crystal
			update_path(true)
		return

	var best_target: Node3D = target_crystal
	var best_distance_squared: float = INF
	var detection_range: float = _get_detection_range()
	var detection_range_squared: float = detection_range * detection_range

	for candidate in aggro_area.get_overlapping_bodies():
		if not candidate is Node3D or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if not candidate.is_in_group("player") and not candidate.is_in_group("myrs"):
			continue
		if candidate.is_in_group("player") and "is_downed" in candidate and candidate.is_downed:
			continue
		var candidate_distance_squared: float = global_position.distance_squared_to(candidate.global_position)
		if candidate_distance_squared <= detection_range_squared and candidate_distance_squared < best_distance_squared:
			best_target = candidate
			best_distance_squared = candidate_distance_squared

	if current_target != best_target:
		current_target = best_target
		update_path(true)

func _on_aggro_body_entered(body: Node3D) -> void:
	evaluate_target()

func _on_aggro_body_exited(body: Node3D) -> void:
	evaluate_target()

# --- Spell Interactions ---
## How every client asks for damage to be dealt.
##
## The client has already played its own hit sound, particles and screen shake - those
## are local and instant, which is what makes combat feel right. Only the CONSEQUENCE
## travels, and only the server applies it, so health can never disagree between peers.
##
## `attacker_peer` rather than a node path: paths are fragile across peers, and the
## server can resolve the avatar itself. Attribution matters because lifesteal and the
## melee-into-spell cooldown refund both pay the player who landed the blow.
@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: float, attacker_peer: int, is_melee: bool) -> void:
	if not Net.is_server() or is_dying:
		return
	take_damage(amount, PlayerRegistry.by_peer(attacker_peer), is_melee)


func take_damage(amount: float, source: Node3D = null, _is_melee: bool = false) -> void:
	if is_dying:
		return
	if curse_timer > 0:
		amount *= curse_mult
	var damage_dealt: float = minf(maxf(amount, 0.0), maxf(health, 0.0))
	health -= amount
	if damage_dealt > 0.0 and is_instance_valid(source) and source.has_method("on_damage_dealt"):
		source.on_damage_dealt(damage_dealt)
	if health_bar and enemy_data:
		health_bar.set_health(health, enemy_data.health)
	var spawn_pos = global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	SignalBus.damage_number_requested.emit(spawn_pos, amount, Color(1.0, 0.95, 0.2))
	if health <= 0.0:
		die()
		return
	_react_to_hit(damage_dealt)


## Starts the flinch, if the hit was worth flinching at. Driven from take_damage
## rather than from knockback, which is what it used to key off: a shooter standing
## its ground is the enemy most often shot at and the one least often knocked back,
## so it never visibly reacted to anything.
func _react_to_hit(damage_dealt: float) -> void:
	if _reaction_clip == "" or enemy_data == null:
		return
	if _hit_react_cooldown > 0.0:
		return
	if damage_dealt < enemy_data.health * GameSettings.enemy_hit_react_damage_pct:
		return
	_hit_react_timer = GameSettings.enemy_hit_react_duration
	_hit_react_cooldown = GameSettings.enemy_hit_react_cooldown
	if GameSettings.enemy_hit_react_interrupts_attack:
		# The swing is dropped along with the pose that was building it. Damage is
		# scheduled separately from the animation now, so without this the enemy
		# would flinch and still land the hit it was in the middle of.
		_impact_timer = -1.0

func die() -> void:
	if enemy_data:
		SignalBus.enemy_died.emit()
		# The team is paid twice for one kill: XP towards a level everybody shares, and
		# mana in this enemy's own colour. Banked here rather than dropped, because the
		# pool is shared and there is nobody for a pickup to belong to.
		RunState.on_enemy_killed(enemy_data, elite_modifier != "")

	# Dying mid-windup drops the telegraph without dealing its damage - and the same
	# goes for an ordinary swing whose impact frame has not arrived yet.
	_cancel_special()
	_impact_timer = -1.0
	_hit_react_timer = 0.0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		is_dying = true
		collision_layer = 0
		collision_mask = 0
		remove_from_group("enemies")
		if health_bar:
			health_bar.visible = false
		var death_anim: Animation = visual_anim_player.get_animation("death")
		var death_speed: float = maxf(_anim_speed_scale, 0.05)
		if death_anim and death_anim.length / death_speed > DEATH_MAX_SECONDS:
			death_speed = death_anim.length / DEATH_MAX_SECONDS
		visual_anim_player.play("death", -1, death_speed)
		_register_corpse()
	else:
		queue_free()

# Corpses are left in the scene (not freed) once their death clip finishes, up to
# a cap; the oldest corpse is freed to make room for each new one past the cap.
func _register_corpse() -> void:
	_corpses.append(self)
	# Walk from the oldest corpse forward, freeing the first one whose death clip
	# has actually finished. A burst of simultaneous kills (e.g. an AoE wipe at the
	# crystal) can otherwise land several very-fresh corpses at the front of the
	# queue at once; force-freeing strictly by age would cut their death animation
	# off mid-play. Leaving the list briefly over the cap is harmless - it corrects
	# itself as soon as any corpse's clip finishes.
	var i := 0
	while _corpses.size() > GameSettings.enemy_max_corpses and i < _corpses.size():
		var oldest: EnemyBase = _corpses[i]
		if not is_instance_valid(oldest):
			_corpses.remove_at(i)
			continue
		if oldest.visual_anim_player and oldest.visual_anim_player.is_playing():
			i += 1
			continue
		_corpses.remove_at(i)
		oldest.queue_free()

func unsummon(force_vec: Vector3 = Vector3.ZERO) -> void:
	if force_vec != Vector3.ZERO:
		apply_knockback(force_vec)
	else:
		if is_instance_valid(target_crystal):
			var dir_away = (global_position - target_crystal.global_position).normalized()
			global_position += dir_away * GameSettings.spell_unsummon_teleport_distance
			
		current_target = target_crystal
		update_path()

func apply_knockback(force_vec: Vector3) -> void:
	knockback_velocity = force_vec

func apply_chill() -> void:
	chill_stacks += 1
	if chill_stacks >= 3:
		chill_stacks = 0
		freeze_timer = 3.0
		_trigger_shatter_aoe()

func _trigger_shatter_aoe() -> void:
	var radius = GameSettings.spell_blue_freeze_breath_shatter_radius
	var damage = GameSettings.spell_blue_freeze_breath_shatter_damage
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)

func apply_root(duration: float) -> void:
	root_timer = duration

func apply_stun(duration: float) -> void:
	stun_timer = duration

func apply_blind(duration: float) -> void:
	blind_timer = duration

func apply_doom_curse(duration: float, mult: float) -> void:
	curse_timer = duration
	curse_mult = mult

func apply_pacifism(duration: float) -> void:
	pacified_timer = duration
	damage_penalty = enemy_data.attack_damage * GameSettings.spell_white_pacifism_debuff_mult
	current_target = target_crystal
	update_path(true)

func apply_stab_debuff() -> void:
	damage_penalty = GameSettings.spell_stab_debuff_damage
	penalty_timer = GameSettings.spell_stab_debuff_duration

func apply_frost_slow(duration: float) -> void:
	frost_slow_timer = duration
