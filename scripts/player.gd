extends CharacterBody3D
class_name Player

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var rotation_speed: float = 10.0
@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var camera_pivot: Node3D
var camera: Camera3D

# --- RPG Stats ---
var hp: float = 100.0
var max_hp: float = 100.0
var level: int = 1
var current_xp: int = 0
var xp_to_next: int = 100
var sp: int = 0

var carried_color: String = ""
var harvest_timer: float = 0.0
var is_at_base: bool = false

var unlocked_skills = {
	"red": false,
	"blue": false,
	"green": false,
	"white": false,
	"black": false
}

var active_spell_index: int = 0
var spell_names = ["Basic Attack", "Shock", "Unsummon", "Giant Growth", "Healing Grace", "Stab"]
var spell_colors = ["none", "red", "blue", "green", "white", "black"]

# --- Buffs & Timers ---
var is_giant: bool = false
var giant_timer: float = 0.0
var base_scale: Vector3 = Vector3.ONE

var has_grace_shield: bool = false
var grace_visual: CSGSphere3D

var slow_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	collision_layer = 1
	# Add mask for layer 3 (Enemies) to detect Giant Growth collisions
	collision_mask = 21
	
	setup_camera()
	
	SignalBus.enemy_died.connect(_on_enemy_died)
	SignalBus.skill_unlocked.connect(_on_skill_unlocked)
	
	# Delay emitting the initial active spell until the HUD is ready
	call_deferred("_emit_initial_spell")
	
	# Giant growth Area3D for melee damage
	var giant_area = Area3D.new()
	giant_area.name = "GiantArea"
	giant_area.collision_layer = 0
	giant_area.collision_mask = 4 # Enemies
	giant_area.body_entered.connect(_on_giant_body_entered)
	add_child(giant_area)
	
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 1.2
	col.shape = shape
	giant_area.add_child(col)

func _emit_initial_spell() -> void:
	SignalBus.active_spell_changed.emit(spell_names[active_spell_index])

func setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	camera_pivot.position = Vector3(1.2, 1.6, 0)
	
	var spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = 4.5
	spring_arm.position = Vector3(0, 0.2, 0)
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.add_child(spring_arm)
	
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 0, 0)
	spring_arm.add_child(camera)
	camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -deg_to_rad(70.0), deg_to_rad(30.0))

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_spell(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_spell(1)
		
		if event.is_action_pressed("attack"):
			cast_active_spell()

func cycle_spell(dir: int) -> void:
	var original_index = active_spell_index
	var max_spells = spell_names.size()
	
	active_spell_index = (active_spell_index + dir) % max_spells
	if active_spell_index < 0:
		active_spell_index += max_spells
		
	# Skip if not unlocked
	while active_spell_index != 0 and not unlocked_skills[spell_colors[active_spell_index]]:
		active_spell_index = (active_spell_index + dir) % max_spells
		if active_spell_index < 0:
			active_spell_index += max_spells
			
		if active_spell_index == original_index:
			break # Looped all the way around
			
	if active_spell_index != original_index:
		SignalBus.active_spell_changed.emit(spell_names[active_spell_index])

func cast_active_spell() -> void:
	match active_spell_index:
		0: cast_basic_attack()
		1: cast_shock()
		2: cast_unsummon()
		3: cast_giant_growth()
		4: cast_healing_grace()
		5: cast_stab()

# --- RPG Logic ---
func _on_enemy_died(xp: int) -> void:
	current_xp += xp
	while current_xp >= xp_to_next:
		current_xp -= xp_to_next
		level_up()
	SignalBus.xp_changed.emit(current_xp, xp_to_next)

func level_up() -> void:
	level += 1
	sp += 1
	max_hp += 10
	hp = max_hp
	xp_to_next = int(xp_to_next * 1.2)
	SignalBus.player_health_changed.emit(hp, max_hp)
	SignalBus.player_leveled_up.emit(level, sp)

func _on_skill_unlocked(color: String) -> void:
	unlocked_skills[color] = true
	sp -= 1
	SignalBus.player_leveled_up.emit(level, sp)

func take_damage(amount: float) -> void:
	if has_grace_shield:
		has_grace_shield = false
		if grace_visual:
			grace_visual.queue_free()
			grace_visual = null
		# AoE Burst Heal
		SignalBus.crystal_damaged.emit(-50.0) # Negative damage heals
		heal(50.0)
		return
		
	hp -= amount
	SignalBus.player_health_changed.emit(hp, max_hp)
	if hp <= 0:
		die()

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	SignalBus.player_health_changed.emit(hp, max_hp)

func die() -> void:
	# Keep simple for now, just respawn or game over
	pass

# --- Spells ---
func cast_basic_attack() -> void:
	# Basic Melee Attack
	var hit_something = false
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var distance = global_position.distance_to(enemy.global_position)
		if distance < 3.5: # Melee range
			var to_enemy = (enemy.global_position - global_position).normalized()
			var forward = -camera_pivot.global_transform.basis.z.normalized()
			# Check if enemy is in front of the player (approx 60 degree cone)
			if to_enemy.dot(forward) > 0.5:
				if enemy.has_method("take_damage"):
					enemy.take_damage(20)
					hit_something = true
	if hit_something:
		print("Melee attack hit!")
	else:
		print("Melee attack missed.")

func cast_shock() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 1) # 1 for Red Shock

func cast_unsummon() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 2) # 2 for Blue Unsummon

func cast_giant_growth() -> void:
	is_giant = true
	giant_timer = 10.0
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.5)

func _on_giant_body_entered(body: Node3D) -> void:
	if is_giant and body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(100.0) # Massive melee damage

func cast_healing_grace() -> void:
	if has_grace_shield:
		return
	has_grace_shield = true
	grace_visual = CSGSphere3D.new()
	grace_visual.radius = 1.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.9, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.8)
	grace_visual.material = mat
	add_child(grace_visual)

func cast_stab() -> void:
	# Use Physics Direct Space State for raycast
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 10.0 # Short range
	var query = PhysicsRayQueryParameters3D.create(start, end, 4) # Mask 4 = Enemies
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.health <= 50.0:
			enemy.die()
		else:
			if enemy.has_method("apply_stab_debuff"):
				enemy.apply_stab_debuff()



func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Crosshair target checking
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 50.0 # 50m range for UI focus
	var query = PhysicsRayQueryParameters3D.create(start, end, 4) # Mask 4 = Enemies
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if "enemy_data" in enemy and enemy.enemy_data:
			var e_name = enemy.enemy_data.color_identity + " " + enemy.enemy_data.enemy_class
			var e_color = enemy.enemy_data.visual_color
			SignalBus.enemy_focused.emit(true, e_name, enemy.health, enemy.enemy_data.health, e_color)
	else:
		SignalBus.enemy_focused.emit(false, "", 0, 0, Color.WHITE)

	# Mana Harvesting & Depositing logic
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("add_mana"):
		var at_mana_source = false
		var source_color = ""
		for i in range(main_node.mana_sources.size()):
			var ms = main_node.mana_sources[i]
			if global_position.distance_to(ms.global_position) < 6.0:
				at_mana_source = true
				source_color = main_node.LANE_NAMES[i]
				break
				
		if at_mana_source and carried_color == "":
			harvest_timer += delta
			if harvest_timer >= 3.0:
				carried_color = source_color
				harvest_timer = 0.0
		else:
			harvest_timer = 0.0
			
			
		var near_base = global_position.distance_to(main_node.crystal_anchor.global_position) < 5.0
		if near_base != is_at_base:
			is_at_base = near_base
			SignalBus.at_base_changed.emit(is_at_base)
			
		if is_at_base:
			if carried_color != "":
				SignalBus.mana_deposited.emit(carried_color, 1)
				carried_color = ""
				
			if Input.is_action_just_pressed("ui_accept"):
				if main_node.base_ui_instance and not main_node.base_ui_instance.visible:
					main_node.base_ui_instance.open(main_node)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = speed
	if slow_timer > 0:
		current_speed = speed * 0.5
	if carried_color != "":
		current_speed *= 0.5 # 50% slow when carrying mana
		
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	
	if is_giant:
		giant_timer -= delta
		if giant_timer <= 0:
			is_giant = false
			var tween = create_tween()
			tween.tween_property(self, "scale", Vector3.ONE, 0.5)

	if slow_timer > 0:
		slow_timer -= delta

func apply_slow() -> void:
	slow_timer = 3.0
