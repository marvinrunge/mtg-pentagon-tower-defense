extends CharacterBody3D
class_name EnemyBase

var target_crystal: Node3D
var current_target: Node3D
var last_target_position: Vector3

var enemy_data: EnemyData
var health: float = 100.0
var damage_penalty: float = 0.0
var penalty_timer: float = 0.0
var attack_cooldown: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aggro_area: Area3D = $AggroArea
@onready var aggro_col: CollisionShape3D = $AggroArea/CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# For Mages
var cast_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 27
	
	if has_meta("target_crystal"):
		target_crystal = get_meta("target_crystal")
	else:
		var crystal_nodes = get_tree().get_nodes_in_group("crystal")
		if crystal_nodes.size() > 0:
			target_crystal = crystal_nodes[0]
			
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
		shape.radius = max(12.0, data.attack_range + 2.0)
		
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
	elif target_crystal:
		target_pos = target_crystal.global_position
		
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
			cast_timer = enemy_data.attack_speed
			
	var dist_to_target = 999.0
	if is_instance_valid(current_target):
		dist_to_target = global_position.distance_to(current_target.global_position)
		
	# Movement
	if dist_to_target > enemy_data.attack_range and not nav_agent.is_navigation_finished():
		var next_path_position = nav_agent.get_next_path_position()
		var speed_mult = 1.0
		if frost_slow_timer > 0:
			speed_mult = 0.3
		var new_velocity = (next_path_position - global_position).normalized() * enemy_data.speed * speed_mult
		velocity.x = new_velocity.x
		velocity.z = new_velocity.z
		
		if velocity.length_squared() > 0.01:
			var target_rotation = atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 8.0 * delta)
			
		move_and_slide()
	else:
		# In range, stop moving
		velocity.x = 0.0
		velocity.z = 0.0
		
		if attack_cooldown <= 0 and enemy_data.enemy_class != "Mage":
			perform_attack()

func perform_attack() -> void:
	if not is_instance_valid(current_target):
		current_target = target_crystal
		update_path()
		return
		
	attack_cooldown = enemy_data.attack_speed
	
	# Apply frost slow if active
	if frost_slow_timer > 0:
		attack_cooldown /= 0.3 # 70% slower attacks (takes 3.33x as long)
	var actual_damage = max(0.0, enemy_data.attack_damage - damage_penalty)
	
	if current_target == target_crystal:
		SignalBus.crystal_damaged.emit(actual_damage)
		# Melee units vanish after hitting crystal. Ranged keep shooting?
		# Standard TD logic: enemies die when hitting base.
		if enemy_data.enemy_class == "Melee" or enemy_data.enemy_class == "Boss":
			queue_free()
	elif current_target.is_in_group("myrs"):
		current_target.queue_free()
		current_target = target_crystal
		update_path()
	elif current_target.is_in_group("player"):
		if current_target.has_method("take_damage"):
			current_target.take_damage(actual_damage)
	elif current_target.is_in_group("walls"):
		var wall_script = current_target.get_meta("wall_parent")
		if wall_script and wall_script.has_method("take_damage"):
			wall_script.take_damage(actual_damage, self)
			if wall_script.is_dead:
				current_target = target_crystal
				update_path()

func perform_mage_spell() -> void:
	match enemy_data.color_identity:
		"White":
			# AoE Heal
			var enemies = get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if is_instance_valid(e) and global_position.distance_to(e.global_position) < 15.0:
					if e.has_method("heal"):
						e.heal(30.0)
		"Red":
			# Damagedealer (Fireball at player)
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < 20.0:
				if players[0].has_method("take_damage"):
					players[0].take_damage(enemy_data.attack_damage)
		"Blue":
			# Slows player
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < 20.0:
				# We don't have a slow debuff yet, let's just simulate it or add it to player
				if players[0].has_method("apply_slow"):
					players[0].apply_slow()
		"Black":
			# Revive weak enemy
			# Just spawn a new weak melee of the same color
			var revived_data = EnemyDatabase.get_enemy_data("Black", "Melee")
			var enemy_scene = load("res://scenes/enemy.tscn")
			var new_enemy = enemy_scene.instantiate()
			new_enemy.position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			new_enemy.set_meta("target_crystal", target_crystal)
			get_parent().add_child(new_enemy)
			# Needs to be setup after adding to tree usually, but we can call setup directly
			new_enemy.setup(revived_data)
			new_enemy.health = revived_data.health * 0.5 # 50% HP
		"Green":
			# Buff enemy (Giant Growth)
			var enemies = get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) < 10.0:
					e.scale = Vector3(1.5, 1.5, 1.5)
					if e.enemy_data:
						e.enemy_data.attack_damage *= 1.5
					break # Only buff one

func heal(amount: float) -> void:
	if enemy_data:
		health = min(enemy_data.health, health + amount)

func _on_aggro_body_entered(body: Node3D) -> void:
	if body.is_in_group("myrs") or body.is_in_group("player") or body.is_in_group("walls"):
		if current_target == target_crystal or (current_target.is_in_group("myrs") and body.is_in_group("player")):
			current_target = body
			update_path()

func _on_aggro_body_exited(body: Node3D) -> void:
	if current_target == body:
		current_target = target_crystal
		update_path()

# --- Spell Interactions ---
func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()

func die() -> void:
	if enemy_data:
		SignalBus.enemy_died.emit(enemy_data.xp_yield)
	queue_free()

func unsummon() -> void:
	if is_instance_valid(target_crystal):
		var dir_away = (global_position - target_crystal.global_position).normalized()
		global_position += dir_away * 15.0
		
	current_target = target_crystal
	update_path()

func apply_stab_debuff() -> void:
	damage_penalty = 5.0
	penalty_timer = 8.0

var frost_slow_timer: float = 0.0

func apply_frost_slow(duration: float) -> void:
	frost_slow_timer = duration
