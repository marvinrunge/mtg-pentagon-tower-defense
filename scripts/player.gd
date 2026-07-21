extends CharacterBody3D
class_name Player

@export var speed: float = GameSettings.player_base_speed
@export var jump_velocity: float = GameSettings.player_jump_velocity
@export var mouse_sensitivity: float = GameSettings.player_mouse_sensitivity
@export var rotation_speed: float = 10.0
@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var camera_pivot: Node3D
var camera: Camera3D

# --- RPG Stats ---
var hp: float = GameSettings.player_max_hp
var max_hp: float = GameSettings.player_max_hp

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

var skill_levels = {
	"red": 1,
	"blue": 1,
	"green": 1,
	"white": 1,
	"black": 1
}

var active_spell_index: int = 0
var spell_names = ["Basic Attack", "Shock", "Unsummon", "Giant Growth", "Healing Grace", "Stab"]
var spell_colors = ["none", "red", "blue", "green", "white", "black"]

# --- Buffs & Timers ---
var is_giant: bool = false
var giant_timer: float = 0.0
var base_scale: Vector3 = Vector3.ONE


var slow_timer: float = 0.0

# --- Spell Cooldowns ---
var spell_cooldown_timers: Dictionary = {}

# --- Crosshair cache ---
var _last_focused_enemy: Node3D = null

# --- Respawn invulnerability ---
var _invulnerable_timer: float = 0.0

# --- Interaction notifications ---
var _notification_text: String = ""
var _notification_timer: float = 0.0

# --- Downed & Revive State ---
var is_downed: bool = false
var down_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	setup_camera()
	
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

	if is_downed:
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_spell(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_spell(1)
		
		if event is InputEventKey and event.pressed and not event.echo:
			var keycode = event.keycode
			if keycode >= KEY_1 and keycode <= KEY_6:
				var target_idx = keycode - KEY_1
				if target_idx == 0 or (target_idx < spell_colors.size() and unlocked_skills[spell_colors[target_idx]]):
					if active_spell_index != target_idx:
						active_spell_index = target_idx
						SignalBus.active_spell_changed.emit(spell_names[active_spell_index])
		
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

func _get_spell_cooldown(index: int) -> float:
	match index:
		0: return GameSettings.spell_cooldown_melee
		1: return GameSettings.spell_cooldown_shock
		2: return GameSettings.spell_cooldown_unsummon
		3: return GameSettings.spell_cooldown_giant
		4: return GameSettings.spell_cooldown_heal
		5: return GameSettings.spell_cooldown_stab
		_: return 0.0

func cast_active_spell() -> void:
	var cd = spell_cooldown_timers.get(active_spell_index, 0.0)
	if cd > 0.0:
		return
	spell_cooldown_timers[active_spell_index] = _get_spell_cooldown(active_spell_index)
	match active_spell_index:
		0: cast_basic_attack()
		1: cast_shock()
		2: cast_unsummon()
		3: cast_giant_growth()
		4: cast_healing_grace()
		5: cast_stab()

# --- RPG Logic ---
func _on_skill_unlocked(color: String) -> void:
	if not unlocked_skills[color]:
		unlocked_skills[color] = true
	else:
		skill_levels[color] += 1

func take_damage(amount: float) -> void:
	if _invulnerable_timer > 0.0:
		return
		
	hp -= amount
	SignalBus.player_health_changed.emit(hp, max_hp)
	var spawn_pos = global_position + Vector3(randf_range(-0.2, 0.2), 1.6, randf_range(-0.2, 0.2))
	SignalBus.damage_number_requested.emit(spawn_pos, amount, Color(1.0, 0.25, 0.25))
	if hp <= 0:
		die()

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	SignalBus.player_health_changed.emit(hp, max_hp)
	var spawn_pos = global_position + Vector3(0, 1.8, 0)
	SignalBus.damage_number_requested.emit(spawn_pos, -amount, Color(0.2, 1.0, 0.4))

func die() -> void:
	if is_downed:
		return
	is_downed = true
	hp = 0.0
	SignalBus.player_health_changed.emit(hp, max_hp)
	
	# Visual indication of death (cylinder rotated flat on the ground)
	var visual = $VisualMesh
	if visual:
		visual.rotation = Vector3(deg_to_rad(90), 0, 0)
		visual.position = Vector3(0, 0.1, 0)
		
	var total_players = get_tree().get_nodes_in_group("player").size()
	if total_players > 1:
		down_timer = 15.0
		print("Player downed! Can be revived for 15 seconds...")
	else:
		down_timer = 5.0
		print("Player died! Respawning in 5 seconds...")

func revive() -> void:
	if not is_downed:
		return
	is_downed = false
	down_timer = 0.0
	hp = max_hp
	SignalBus.player_health_changed.emit(hp, max_hp)
	_invulnerable_timer = 2.0
	
	var visual = $VisualMesh
	if visual:
		visual.rotation = Vector3.ZERO
		visual.position = Vector3(0, 0.95, 0)
	print("Player revived by teammate!")

func respawn_at_base() -> void:
	if not is_downed:
		return
	is_downed = false
	down_timer = 0.0
	global_position = Vector3(0, 1.0, 0)
	hp = max_hp
	SignalBus.player_health_changed.emit(hp, max_hp)
	_invulnerable_timer = 2.0
	
	var visual = $VisualMesh
	if visual:
		visual.rotation = Vector3.ZERO
		visual.position = Vector3(0, 0.95, 0)
	print("Player respawned at base!")

# --- Spells ---
func cast_basic_attack() -> void:
	# Basic Melee Attack
	var hit_something = false
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var distance = global_position.distance_to(enemy.global_position)
		if distance < GameSettings.spell_melee_range: # Melee range
			var to_enemy = (enemy.global_position - global_position).normalized()
			var forward = -camera_pivot.global_transform.basis.z.normalized()
			# Check if enemy is in front of the player (approx 60 degree cone)
			if to_enemy.dot(forward) > GameSettings.spell_melee_cone:
				if enemy.has_method("take_damage"):
					enemy.take_damage(GameSettings.spell_melee_damage)
					hit_something = true
	if hit_something:
		print("Melee attack hit!")
	else:
		print("Melee attack missed.")

func cast_shock() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	var multiplier = GameSettings.get_skill_multiplier(skill_levels["red"])
	proj.activate(spawn_pos, dir, 1, false, multiplier) # 1 for Red Shock

func cast_unsummon() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	var multiplier = GameSettings.get_skill_multiplier(skill_levels["blue"])
	proj.activate(spawn_pos, dir, 2, false, multiplier) # 2 for Blue Unsummon

func cast_giant_growth() -> void:
	is_giant = true
	giant_timer = GameSettings.spell_giant_duration
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(GameSettings.spell_giant_scale, GameSettings.spell_giant_scale, GameSettings.spell_giant_scale), 0.5)

func _on_giant_body_entered(body: Node3D) -> void:
	if is_giant and body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			var multiplier = GameSettings.get_skill_multiplier(skill_levels["green"])
			body.take_damage(GameSettings.spell_giant_damage * multiplier) # Massive melee damage

func cast_healing_grace() -> void:
	var multiplier = GameSettings.get_skill_multiplier(skill_levels["white"])
	var heal_amt = GameSettings.spell_heal_amount * multiplier
	SignalBus.crystal_damaged.emit(-heal_amt)
	heal(heal_amt)
	
	var visual = CSGSphere3D.new()
	visual.radius = 1.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.9, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.8)
	visual.material = mat
	add_child(visual)
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	tween.parallel().tween_property(visual, "scale", Vector3(1.5, 1.5, 1.5), 1.0)
	tween.tween_callback(visual.queue_free)

func cast_stab() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * GameSettings.spell_stab_range # Short range
	var query = PhysicsRayQueryParameters3D.create(start, end, 4) # Mask 4 = Enemies
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		var multiplier = GameSettings.get_skill_multiplier(skill_levels["black"])
		var execute_thresh = GameSettings.spell_stab_execute_threshold * multiplier
		if enemy.health <= execute_thresh:
			enemy.die()
		else:
			if enemy.has_method("apply_stab_debuff"):
				enemy.apply_stab_debuff()



func _physics_process(delta: float) -> void:
	if is_downed:
		down_timer -= delta
		if down_timer <= 0.0:
			respawn_at_base()
			return
			
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		
		# Show countdown prompt
		var total_players = get_tree().get_nodes_in_group("player").size()
		if total_players > 1:
			SignalBus.interact_prompt_changed.emit("Downed! Can be revived. Respawning in %.1fs" % down_timer, true)
		else:
			SignalBus.interact_prompt_changed.emit("You Died! Respawning in %.1fs" % down_timer, true)
		
		# Check if all players are dead
		var living_players = 0
		for p in get_tree().get_nodes_in_group("player"):
			if not p.is_downed:
				living_players += 1
		if living_players == 0:
			SignalBus.crystal_damaged.emit(9999.0) # Trigger Defeat
			
		return # Skip normal physics process when dead/downed

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Crosshair target checking (cached to avoid emitting every frame)
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 50.0 # 50m range for UI focus
	var query = PhysicsRayQueryParameters3D.create(start, end, 4) # Mask 4 = Enemies
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy != _last_focused_enemy:
			_last_focused_enemy = enemy
			if "enemy_data" in enemy and enemy.enemy_data:
				var e_name = enemy.enemy_data.display_name
				var e_color = enemy.enemy_data.visual_color
				SignalBus.enemy_focused.emit(true, e_name, enemy.health, enemy.enemy_data.health, e_color)
	else:
		if _last_focused_enemy != null:
			_last_focused_enemy = null
			SignalBus.enemy_focused.emit(false, "", 0, 0, Color.WHITE)

	# Teammate revive check (takes precedence over mana and base prompts)
	var revived_teammate = false
	var teammates = get_tree().get_nodes_in_group("player")
	for teammate in teammates:
		if teammate != self and teammate.is_downed:
			var dist = global_position.distance_to(teammate.global_position)
			if dist < 3.0:
				revived_teammate = true
				if _notification_timer <= 0.0:
					SignalBus.interact_prompt_changed.emit("Press [F] to Revive Teammate", true)
				
				if Input.is_action_just_pressed("interact"):
					teammate.revive()
					_notification_text = "Revived Teammate!"
					_notification_timer = 1.5
				break

	# Mana Harvesting & Depositing logic
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("add_mana"):
		var at_mana_source = false
		var source_color = ""
		for i in range(main_node.mana_sources.size()):
			var ms = main_node.mana_sources[i]
			if global_position.distance_to(ms.global_position) < GameSettings.player_mana_harvest_distance:
				at_mana_source = true
				source_color = main_node.LANE_NAMES[i]
				break
				
		var near_base = global_position.distance_to(main_node.crystal_anchor.global_position) < GameSettings.player_base_proximity
		if near_base != is_at_base:
			is_at_base = near_base
			SignalBus.at_base_changed.emit(is_at_base)
			
		if is_at_base:
			if carried_color != "":
				SignalBus.mana_deposited.emit(carried_color, 1)
				_notification_text = "Deposited %s Mana!" % carried_color
				_notification_timer = 1.5
				carried_color = ""
				
			if Input.is_action_just_pressed("interact"):
				if main_node.base_ui_instance and not main_node.base_ui_instance.visible:
					main_node.base_ui_instance.open(main_node)

		# Prompt/Notification UI updating (only runs if not busy reviving a teammate)
		if not revived_teammate:
			if main_node.base_ui_instance and main_node.base_ui_instance.visible:
				SignalBus.interact_prompt_changed.emit("", false)
			elif _notification_timer > 0.0:
				_notification_timer -= delta
				SignalBus.interact_prompt_changed.emit(_notification_text, true)
			elif at_mana_source and carried_color == "":
				if Input.is_action_pressed("interact"):
					harvest_timer += delta
					var progress = int((harvest_timer / GameSettings.player_mana_harvest_time) * 100)
					SignalBus.interact_prompt_changed.emit("Harvesting %s Mana... %d%%" % [source_color, progress], true)
					
					if harvest_timer >= GameSettings.player_mana_harvest_time:
						carried_color = source_color
						harvest_timer = 0.0
						_notification_text = "Collected %s Mana!" % source_color
						_notification_timer = 1.5
				else:
					harvest_timer = 0.0
					SignalBus.interact_prompt_changed.emit("Hold [F] to Harvest %s Mana" % source_color, true)
			elif is_at_base:
				SignalBus.interact_prompt_changed.emit("Press [F] to Manage Base", true)
			else:
				harvest_timer = 0.0
				SignalBus.interact_prompt_changed.emit("", false)
		else:
			# Decrement notification timer even if we are showing the revive prompt
			if _notification_timer > 0.0:
				_notification_timer -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = speed
	if Input.is_action_pressed("sprint"):
		current_speed *= GameSettings.player_sprint_speed_mult
	if slow_timer > 0:
		current_speed *= GameSettings.player_carry_speed_penalty
	if carried_color != "":
		current_speed *= GameSettings.player_carry_speed_penalty # Slow when carrying mana
		
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

	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta

	# Decrement spell cooldown timers
	for key in spell_cooldown_timers.keys():
		spell_cooldown_timers[key] -= delta
		if spell_cooldown_timers[key] <= 0.0:
			spell_cooldown_timers.erase(key)

func apply_slow() -> void:
	slow_timer = 4.0
