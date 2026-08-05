extends CharacterBody3D
class_name EnemyBase

var target_crystal: Node3D
var current_target: Node3D
var last_target_position: Vector3 = Vector3.INF

var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _health_bar_scene: PackedScene = preload("res://scenes/enemy_health_bar.tscn")

var enemy_data: EnemyData
var health: float = 100.0
var health_bar: EnemyHealthBar
var damage_penalty: float = 0.0
var penalty_timer: float = 0.0
var attack_cooldown: float = 0.0
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
	health = data.health
	
	# Adjust Aggro Area based on range
	if aggro_col and aggro_col.shape is SphereShape3D:
		var shape: SphereShape3D = aggro_col.shape as SphereShape3D
		shape.radius = _get_detection_range()
		
	cast_timer = data.attack_speed
	
	# Visuals
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

	if has_meta("elite_modifier"):
		apply_elite_modifier(String(get_meta("elite_modifier")))
	
	# Bosses get a special visual marker (a crown or just bigger)
	if data.enemy_class == "Boss":
		var crown = CSGCylinder3D.new()
		crown.radius = 0.5
		crown.height = 0.3
		crown.position = Vector3(0, 2.0, 0)
		var c_mat = StandardMaterial3D.new()
		c_mat.albedo_color = Color(1, 0.8, 0)
		c_mat.emission_enabled = true
		c_mat.emission = Color(1, 0.8, 0)
		crown.material = c_mat
		add_child(crown)

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

func _physics_process(delta: float) -> void:
	if not enemy_data:
		return # Not initialized yet

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

	# Disable movement if frozen or stunned
	if freeze_timer > 0 or stun_timer > 0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
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
			rotation.y = lerp_angle(rotation.y, target_rotation, 8.0 * delta)
			
		move_and_slide()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

		if not is_in_attack_range:
			if root_timer <= 0 and nav_agent.is_navigation_finished():
				update_path(true)
			return
		
		if is_instance_valid(current_target):
			var dir_to_target: Vector3 = (current_target.global_position - global_position).normalized()
			if dir_to_target.length_squared() > 0.01:
				var target_rotation: float = atan2(dir_to_target.x, dir_to_target.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, 8.0 * delta)
		
		if attack_cooldown <= 0 and blind_timer <= 0:
			perform_attack()

func perform_attack() -> void:
	if not is_instance_valid(current_target):
		evaluate_target()
		return
		
	attack_cooldown = enemy_data.attack_speed
	
	# Apply frost slow if active
	if frost_slow_timer > 0:
		attack_cooldown /= GameSettings.enemy_frost_slow_mult # Slower attacks when frosted
		
	if enemy_data.enemy_class == "Mage" or enemy_data.enemy_class == "Ranged":
		fire_projectile()
		return
		
	var actual_damage = max(0.0, enemy_data.attack_damage - damage_penalty)
	if current_target == target_crystal:
		actual_damage *= elite_crystal_damage_multiplier
	actual_damage *= GameSettings.get_player_scaling_factor(get_tree())
	
	if current_target == target_crystal:
		SignalBus.crystal_damaged.emit(actual_damage)
	elif current_target.has_method("take_damage"):
		current_target.take_damage(actual_damage, self, true)

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
			# AoE Heal
			var enemies = get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if is_instance_valid(e) and global_position.distance_to(e.global_position) < GameSettings.enemy_white_mage_range:
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
			var new_enemy = _enemy_scene.instantiate()
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
	_add_elite_marker()

func _add_elite_marker() -> void:
	var marker: CSGTorus3D = CSGTorus3D.new()
	marker.name = "EliteMarker"
	marker.inner_radius = 0.42
	marker.outer_radius = 0.58
	marker.position = Vector3(0.0, 2.05, 0.0)
	marker.rotation_degrees.x = 90.0
	var marker_material: StandardMaterial3D = StandardMaterial3D.new()
	marker_material.albedo_color = Color(1.0, 0.72, 0.12)
	marker_material.emission_enabled = true
	marker_material.emission = Color(1.0, 0.28, 0.04)
	marker_material.emission_energy_multiplier = 2.5
	marker.material = marker_material
	add_child(marker)

	var modifier_label: Label3D = Label3D.new()
	modifier_label.name = "EliteModifierLabel"
	modifier_label.text = elite_modifier.to_upper()
	modifier_label.position = Vector3(0.0, 2.45, 0.0)
	modifier_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	modifier_label.no_depth_test = true
	modifier_label.font_size = 32
	modifier_label.outline_size = 8
	modifier_label.modulate = Color(1.0, 0.78, 0.24)
	add_child(modifier_label)

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
func take_damage(amount: float, source: Node3D = null, _is_melee: bool = false) -> void:
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

func die() -> void:
	if enemy_data:
		SignalBus.enemy_died.emit()
	queue_free()

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
