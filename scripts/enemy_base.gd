extends CharacterBody3D
class_name EnemyBase

var target_crystal: Node3D
var current_target: Node3D
var last_target_position: Vector3
var target_offset: Vector3 = Vector3.ZERO

var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

var enemy_data: EnemyData
var health: float = 100.0
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
			
	if has_meta("formation_offset"):
		target_offset = get_meta("formation_offset")
			
	current_target = target_crystal
	update_path()
	
	if aggro_area:
		aggro_area.body_entered.connect(_on_aggro_body_entered)
		aggro_area.body_exited.connect(_on_aggro_body_exited)

func setup(data: EnemyData) -> void:
	enemy_data = data
	health = data.health
	
	# Adjust Aggro Area based on range
	if aggro_col and aggro_col.shape is SphereShape3D:
		var shape = aggro_col.shape as SphereShape3D
		shape.radius = max(GameSettings.enemy_aggro_radius, data.attack_range + 2.0)
		
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

func update_path() -> void:
	if not nav_agent:
		return
	
	var target_pos = Vector3.ZERO
	if current_target and is_instance_valid(current_target):
		target_pos = current_target.global_position
		# If they are targeting the central crystal, keep their formation offset so they walk parallel
		if current_target == target_crystal:
			target_pos += target_offset
	elif target_crystal:
		target_pos = target_crystal.global_position + target_offset
		
	if target_pos.distance_squared_to(last_target_position) > 0.1:
		nav_agent.target_position = target_pos
		last_target_position = target_pos

func _physics_process(delta: float) -> void:
	if not enemy_data:
		return # Not initialized yet
		
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
	if pacified_timer > 0: pacified_timer -= delta

	# Disable movement if frozen or stunned
	if freeze_timer > 0 or stun_timer > 0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Movement
	if dist_to_target > enemy_data.attack_range and not nav_agent.is_navigation_finished() and root_timer <= 0:
		var next_path_position = nav_agent.get_next_path_position()
		var speed_mult = 1.0
		if frost_slow_timer > 0:
			speed_mult = GameSettings.enemy_frost_slow_mult
		var new_velocity = (next_path_position - global_position).normalized() * enemy_data.speed * speed_mult
		velocity.x = new_velocity.x
		velocity.z = new_velocity.z
		
		if velocity.length_squared() > 0.01:
			var target_rotation = atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 8.0 * delta)
			
		move_and_slide()
	else:
		# In range or rooted, stop moving
		velocity.x = 0.0
		velocity.z = 0.0
		
		if is_instance_valid(current_target):
			var dir_to_target = (current_target.global_position - global_position).normalized()
			if dir_to_target.length_squared() > 0.01:
				var target_rotation = atan2(dir_to_target.x, dir_to_target.z)
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
	actual_damage *= GameSettings.get_player_scaling_factor(get_tree())
	
	if current_target == target_crystal:
		SignalBus.crystal_damaged.emit(actual_damage)
	elif current_target.is_in_group("myrs"):
		current_target.queue_free()
		# Force re-evaluate next frame so we don't target the dying Myr
		call_deferred("evaluate_target")
	elif current_target.is_in_group("player"):
		if current_target.has_method("take_damage"):
			current_target.take_damage(actual_damage)

func fire_projectile() -> void:
	var proj = ProjectilePool.get_projectile()
	if proj:
		# Add a little height so it shoots from chest/head level
		var start_pos = global_position + Vector3(0, 1.2, 0)
		var target_pos = current_target.global_position
		if current_target == target_crystal:
			target_pos += Vector3(0, 2.0, 0) # Aim at crystal center
		elif current_target.is_in_group("player"):
			target_pos += Vector3(0, 1.0, 0) # Aim at player chest
		
		var dir = (target_pos - start_pos).normalized()
		
		var actual_damage = max(0.0, enemy_data.attack_damage - damage_penalty)
		actual_damage *= GameSettings.get_player_scaling_factor(get_tree())
		
		proj.activate(start_pos, dir, 3, true, 1.0, actual_damage)

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
				# We don't have a slow debuff yet, let's just simulate it or add it to player
				if players[0].has_method("apply_slow"):
					players[0].apply_slow()
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
					e.scale *= GameSettings.enemy_green_mage_buff_scale
					if e.enemy_data:
						e.enemy_data.attack_damage *= GameSettings.enemy_green_mage_buff_damage
					break # Only buff one

func heal(amount: float) -> void:
	if enemy_data:
		health = min(enemy_data.health, health + amount)
		var spawn_pos = global_position + Vector3(0, 1.8, 0)
		SignalBus.damage_number_requested.emit(spawn_pos, -amount, Color(0.2, 1.0, 0.4))

func evaluate_target() -> void:
	var best_target = target_crystal
	var best_priority = 3 # 1:Player, 2:Myrs, 3:Crystal

	# Mathematically check for the player to guarantee detection
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		var detection_range = GameSettings.enemy_melee_detection_range
		if enemy_data and (enemy_data.enemy_class == "Mage" or enemy_data.enemy_class == "Ranged"):
			detection_range = GameSettings.enemy_ranged_detection_range
			
		if global_position.distance_to(players[0].global_position) < detection_range:
			best_target = players[0]
			best_priority = 1

	if best_priority > 1 and is_instance_valid(aggro_area):
		var bodies = aggro_area.get_overlapping_bodies()
		for body in bodies:
			if not is_instance_valid(body) or body.is_queued_for_deletion():
				continue
				
			var priority = 3
			if body.is_in_group("myrs"):
				priority = 2
				
			if priority < best_priority:
				best_target = body
				best_priority = priority

	if current_target != best_target:
		current_target = best_target
		update_path()

func _on_aggro_body_entered(body: Node3D) -> void:
	evaluate_target()

func _on_aggro_body_exited(body: Node3D) -> void:
	evaluate_target()

# --- Spell Interactions ---
func take_damage(amount: float) -> void:
	if curse_timer > 0:
		amount *= curse_mult
	health -= amount
	var spawn_pos = global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	SignalBus.damage_number_requested.emit(spawn_pos, amount, Color(1.0, 0.95, 0.2))
	if health <= 0.0:
		die()

func die() -> void:
	if enemy_data:
		SignalBus.enemy_died.emit(enemy_data.xp_yield)
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

func apply_stab_debuff() -> void:
	damage_penalty = GameSettings.spell_stab_debuff_damage
	penalty_timer = GameSettings.spell_stab_debuff_duration

func apply_frost_slow(duration: float) -> void:
	frost_slow_timer = duration
