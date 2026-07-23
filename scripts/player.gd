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

# --- MTG 5-Color State ---
var chosen_color_path: String = ""
var unlocked_spells_in_path: Array[String] = []
var unlocked_capstone_aura: String = ""

# --- Spell Charging State ---
var is_charging: bool = false
var charge_timer: float = 0.0
var charge_max_time: float = 2.0
var charging_spell_id: String = ""

# --- Temporary Buffs & Combo Timers ---
var counterspell_parry_timer: float = 0.0
var briar_patch_timer: float = 0.0
var gideon_reproach_timer: float = 0.0
var overrun_dash_timer: float = 0.0
var overrun_dir: Vector3 = Vector3.ZERO
var last_spell_cast_time: float = -999.0
var rhystic_shield: float = 0.0

var active_spell_index: int = 0
var spell_names = ["Basic Attack", "Spell 1", "Spell 2", "Spell 3", "Spell 4", "Spell 5"]

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
	SignalBus.spell_unlocked.connect(_on_spell_unlocked)
	
	# Delay emitting the initial active spell until the HUD is ready
	call_deferred("_emit_initial_spell")

func _emit_initial_spell() -> void:
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

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

	if event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		if GameSettings.debug_mode:
			if keycode == KEY_F1 or keycode == KEY_M:
				var main_c = get_tree().current_scene
				if main_c and main_c.has_method("add_mana"):
					for c in ["White", "Blue", "Black", "Red", "Green"]:
						main_c.add_mana(c, 100)
					print("[DEBUG] Granted +100 of each Mana color!")
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()
			elif keycode == KEY_F2:
				chosen_color_path = ""
				unlocked_spells_in_path.clear()
				unlocked_capstone_aura = ""
				SignalBus.color_path_chosen.emit("")
				SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
				print("[DEBUG] Reset Color Path commitment!")
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()
			elif keycode == KEY_F3:
				var target_color = chosen_color_path if chosen_color_path != "" else "red"
				chosen_color_path = target_color
				for i in range(1, 6):
					var sid = target_color + "_" + str(i)
					if not unlocked_spells_in_path.has(sid):
						unlocked_spells_in_path.append(sid)
				unlocked_capstone_aura = "aura_" + _get_aura_name_for_color(target_color)
				SignalBus.color_path_chosen.emit(target_color)
				SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
				print("[DEBUG] Unlocked full path for: " + target_color)
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()

		if keycode == KEY_K or keycode == KEY_N:
			var st = get_tree().current_scene.get_node_or_null("SkillTree")
			if st:
				st.visible = not st.visible
				if st.visible:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					if st.has_method("update_ui"):
						st.update_ui()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_spell(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_spell(1)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				cast_active_spell()
		elif event is InputEventMouseButton and not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT and is_charging:
				release_charged_spell()
		
		if event is InputEventKey and event.pressed and not event.echo:
			var keycode = event.keycode
			if keycode >= KEY_1 and keycode <= KEY_5:
				var target_idx = keycode - KEY_1
				if is_spell_unlocked(target_idx):
					if active_spell_index != target_idx:
						active_spell_index = target_idx
						SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func _get_aura_name_for_color(color: String) -> String:
	match color:
		"red": return "fervor"
		"blue": return "rhystic_study"
		"green": return "sylvan_library"
		"white": return "glorious_anthem"
		"black": return "phyrexian_arena"
		_: return ""

func cycle_spell(dir: int) -> void:
	var original_index = active_spell_index
	var max_spells = 5
	
	active_spell_index = (active_spell_index + dir) % max_spells
	if active_spell_index < 0:
		active_spell_index += max_spells
		
	var attempts = 0
	while not is_spell_unlocked(active_spell_index) and attempts < max_spells:
		active_spell_index = (active_spell_index + dir) % max_spells
		if active_spell_index < 0:
			active_spell_index += max_spells
		attempts += 1
			
	if active_spell_index != original_index:
		SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func _get_spell_id_for_slot(slot_idx: int) -> String:
	if chosen_color_path != "" and slot_idx >= 0 and slot_idx <= 4:
		return chosen_color_path + "_" + str(slot_idx + 1)
	return ""

func get_spell_name_for_slot(slot_idx: int) -> String:
	var spell_id = _get_spell_id_for_slot(slot_idx)
	const NAMES = {
		"red_1": "Shock / Lightning Bolt",
		"red_2": "Fireball",
		"red_3": "Rain of Ember",
		"red_4": "Act of Treason",
		"red_5": "Chandra's Ignition",
		"blue_1": "Unsummon",
		"blue_2": "Aetherize",
		"blue_3": "Psionic Blast",
		"blue_4": "Freeze Breath",
		"blue_5": "Counterspell",
		"green_1": "Titanic Growth",
		"green_2": "Hurricane / Entangle",
		"green_3": "Overrun",
		"green_4": "Rabid Bite",
		"green_5": "Briar Patch",
		"white_1": "Swords to Plowshares",
		"white_2": "Path to Exile",
		"white_3": "Wrath of God",
		"white_4": "Pacifism",
		"white_5": "Gideon's Reproach",
		"black_1": "Drain Life",
		"black_2": "Toxic Deluge",
		"black_3": "Doom Blade",
		"black_4": "Tendrils of Agony",
		"black_5": "Sign in Blood"
	}
	return NAMES.get(spell_id, "Locked Spell")

func is_spell_unlocked(slot_idx: int) -> bool:
	var spell_id = _get_spell_id_for_slot(slot_idx)
	return unlocked_spells_in_path.has(spell_id)

func _get_spell_cooldown(spell_id: String) -> float:
	match spell_id:
		"basic_attack": return GameSettings.spell_cooldown_melee
		"red_1": return 2.0
		"red_2": return 4.0
		"red_3": return 8.0
		"red_4": return 6.0
		"red_5": return 10.0
		"blue_1": return 3.0
		"blue_2": return 5.0
		"blue_3": return 4.0
		"blue_4": return 6.0
		"blue_5": return 12.0
		"green_1": return 1.5
		"green_2": return 6.0
		"green_3": return 8.0
		"green_4": return 5.0
		"green_5": return 12.0
		"white_1": return 4.0
		"white_2": return 6.0
		"white_3": return 12.0
		"white_4": return 10.0
		"white_5": return 10.0
		"black_1": return 3.0
		"black_2": return 8.0
		"black_3": return 5.0
		"black_4": return 6.0
		"black_5": return 15.0
		_: return 1.0

func is_chargeable(spell_id: String) -> bool:
	return spell_id in ["red_2", "blue_2", "green_2", "white_2", "white_3", "black_2"]

func cast_active_spell() -> void:
	if is_charging:
		return
		
	var spell_id = _get_spell_id_for_slot(active_spell_index)
	if spell_id == "":
		return
		
	if active_spell_index != 0 and not is_spell_unlocked(active_spell_index):
		return
		
	var cd = spell_cooldown_timers.get(spell_id, 0.0)
	if cd > 0.0:
		return
		
	if is_chargeable(spell_id):
		is_charging = true
		charge_timer = 0.0
		charge_max_time = 2.0
		charging_spell_id = spell_id
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, true)
	else:
		execute_spell(spell_id, 1.0)

func release_charged_spell() -> void:
	if not is_charging:
		return
		
	var pct = clamp(charge_timer / charge_max_time, 0.2, 1.0)
	var spell_id = charging_spell_id
	is_charging = false
	charge_timer = 0.0
	SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	execute_spell(spell_id, pct)

func execute_spell(spell_id: String, charge_pct: float = 1.0) -> void:
	spell_cooldown_timers[spell_id] = _get_spell_cooldown(spell_id)
	
	# Rhystic Study Shield trigger on cast
	if unlocked_capstone_aura == "aura_rhystic_study":
		rhystic_shield += GameSettings.aura_rhystic_study_shield_amount
		
	last_spell_cast_time = Time.get_ticks_msec() / 1000.0
	
	match spell_id:
		"basic_attack": cast_basic_attack()
		# RED
		"red_1": cast_red_shock()
		"red_2": cast_red_fireball(charge_pct)
		"red_3": cast_red_rain_ember()
		"red_4": cast_red_act_of_treason()
		"red_5": cast_red_chandras_ignition()
		# BLUE
		"blue_1": cast_blue_unsummon()
		"blue_2": cast_blue_aetherize(charge_pct)
		"blue_3": cast_blue_psionic_blast()
		"blue_4": cast_blue_freeze_breath()
		"blue_5": cast_blue_counterspell()
		# GREEN
		"green_1": cast_green_titanic_growth()
		"green_2": cast_green_hurricane(charge_pct)
		"green_3": cast_green_overrun()
		"green_4": cast_green_rabid_bite()
		"green_5": cast_green_briar_patch()
		# WHITE
		"white_1": cast_white_swords()
		"white_2": cast_white_path_to_exile(charge_pct)
		"white_3": cast_white_wrath_of_god(charge_pct)
		"white_4": cast_white_pacifism()
		"white_5": cast_white_gideons_reproach()
		# BLACK
		"black_1": cast_black_drain_life()
		"black_2": cast_black_toxic_deluge(charge_pct)
		"black_3": cast_black_doom_blade()
		"black_4": cast_black_tendrils()
		"black_5": cast_black_sign_in_blood()

# --- RPG Logic ---
func _on_skill_unlocked(color: String) -> void:
	pass

func _on_spell_unlocked(color: String, spell_id: String) -> void:
	if chosen_color_path == "":
		chosen_color_path = color
		SignalBus.color_path_chosen.emit(color)
		
	if spell_id.begins_with("aura_"):
		unlocked_capstone_aura = spell_id
	else:
		if not unlocked_spells_in_path.has(spell_id):
			unlocked_spells_in_path.append(spell_id)
			
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func take_damage(amount: float) -> void:
	if _invulnerable_timer > 0.0:
		return
		
	hp -= amount
	SignalBus.player_health_changed.emit(hp, max_hp)
	var spawn_pos = global_position + Vector3(randf_range(-0.2, 0.2), 1.6, randf_range(-0.2, 0.2))
	SignalBus.damage_number_requested.emit(spawn_pos, amount, Color(1.0, 0.25, 0.25))
	if hp <= 0:
		die()

func heal(amount: float, show_damage_number: bool = true) -> void:
	if hp >= max_hp:
		return
	hp = min(max_hp, hp + amount)
	SignalBus.player_health_changed.emit(hp, max_hp)
	if show_damage_number:
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

# --- 25 MTG SPELL IMPLEMENTATIONS ---

# --- RED SPELLS ---
func cast_red_shock() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 1, false, 1.0)
	if unlocked_spells_in_path.size() >= 3:
		var enemies = get_tree().get_nodes_in_group("enemies")
		if enemies.size() > 1 and is_instance_valid(enemies[1]):
			var chain_proj = ProjectilePool.get_projectile()
			chain_proj.activate(spawn_pos, (enemies[1].global_position - spawn_pos).normalized(), 1, false, 0.8)

func cast_red_fireball(charge_pct: float) -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	var radius = GameSettings.spell_red_fireball_base_radius * (0.8 + 0.7 * charge_pct)
	var mult = 0.6 + 1.2 * charge_pct
	proj.activate(spawn_pos, dir, 4, false, mult, -1.0, radius, self)

func cast_red_rain_ember() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 40.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 1)
	var result = space_state.intersect_ray(query)
	var target_pos = result.position if result else (global_position - transform.basis.z * 8.0)
	
	var zone = DoTZone.new()
	zone.setup("fire_rain", GameSettings.spell_red_rain_ember_radius, GameSettings.spell_red_rain_ember_dps, GameSettings.spell_red_rain_ember_duration, self)
	zone.global_position = target_pos
	get_tree().current_scene.add_child(zone)

func cast_red_act_of_treason() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 4.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("take_damage"):
			enemy.take_damage(GameSettings.spell_red_act_of_treason_damage)
		if enemy.has_method("apply_knockback"):
			var kb_dir = -camera.global_basis.z.normalized() * GameSettings.spell_red_act_of_treason_knockback
			enemy.apply_knockback(kb_dir)
		if enemy.has_method("apply_stun"):
			enemy.apply_stun(GameSettings.spell_red_act_of_treason_stun)

func cast_red_chandras_ignition() -> void:
	var radius = GameSettings.spell_red_chandras_ignition_radius
	var damage = GameSettings.spell_red_chandras_ignition_damage
	var push = GameSettings.spell_red_chandras_ignition_push
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)
			if e.has_method("apply_knockback"):
				var push_dir = (e.global_position - global_position).normalized() * push
				e.apply_knockback(push_dir)
				
	var vis = CSGSphere3D.new()
	vis.radius = radius
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.0)
	vis.material = mat
	vis.global_position = global_position
	get_tree().current_scene.add_child(vis)
	
	var tw = vis.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.parallel().tween_property(vis, "scale", Vector3(1.2, 1.2, 1.2), 0.5)
	tw.tween_callback(vis.queue_free)

# --- BLUE SPELLS ---
func cast_blue_unsummon() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 2, false, 1.0)

func cast_blue_aetherize(charge_pct: float) -> void:
	var force = GameSettings.spell_blue_aetherize_push_force * charge_pct
	var forward = -camera_pivot.global_transform.basis.z.normalized()
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 12.0:
			var to_e = (e.global_position - global_position).normalized()
			if to_e.dot(forward) > 0.4:
				if e.has_method("apply_knockback"):
					e.apply_knockback(to_e * force)

func cast_blue_psionic_blast() -> void:
	take_damage(GameSettings.spell_blue_psionic_blast_self_damage)
	
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 30.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("take_damage"):
			enemy.take_damage(GameSettings.spell_blue_psionic_blast_damage)

func cast_blue_freeze_breath() -> void:
	var forward = -camera_pivot.global_transform.basis.z.normalized()
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 10.0:
			var to_e = (e.global_position - global_position).normalized()
			if to_e.dot(forward) > 0.5:
				if e.has_method("apply_chill"):
					e.apply_chill()

func cast_blue_counterspell() -> void:
	counterspell_parry_timer = GameSettings.spell_blue_counterspell_duration
	print("Counterspell parry active for 1.5s!")

# --- GREEN SPELLS ---
func cast_green_titanic_growth() -> void:
	var forward = -camera_pivot.global_transform.basis.z.normalized()
	var cleave_damage = GameSettings.spell_melee_damage + max_hp * GameSettings.spell_green_titanic_growth_hp_scaling
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= GameSettings.spell_green_titanic_growth_cone:
			var to_e = (e.global_position - global_position).normalized()
			if to_e.dot(forward) > 0.3:
				if e.has_method("take_damage"):
					e.take_damage(cleave_damage)

func cast_green_hurricane(charge_pct: float) -> void:
	var radius = GameSettings.spell_green_hurricane_radius * charge_pct
	var dur = GameSettings.spell_green_hurricane_root_duration
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("apply_root"):
				e.apply_root(dur)
			if e.has_method("take_damage"):
				e.take_damage(GameSettings.spell_green_hurricane_poison_dps)

func cast_green_overrun() -> void:
	overrun_dash_timer = GameSettings.spell_green_overrun_dash_duration
	overrun_dir = -transform.basis.z.normalized()

func cast_green_rabid_bite() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 4.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		var dmg = GameSettings.spell_green_rabid_bite_damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		if "root_timer" in enemy and enemy.root_timer > 0:
			heal(dmg * GameSettings.spell_green_rabid_bite_lifesteal)

func cast_green_briar_patch() -> void:
	briar_patch_timer = 10.0

# --- WHITE SPELLS ---
func cast_white_swords() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 6, false, 1.0, -1.0, 0.0, self)

func cast_white_path_to_exile(charge_pct: float) -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 7, false, charge_pct, -1.0, 0.0, self)

func cast_white_wrath_of_god(charge_pct: float) -> void:
	var radius = GameSettings.spell_white_wrath_radius * charge_pct
	heal(GameSettings.spell_white_wrath_heal * charge_pct)
	SignalBus.crystal_damaged.emit(-GameSettings.spell_white_wrath_heal * charge_pct)
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if "enemy_data" in e and e.enemy_data and e.has_method("take_damage"):
				var dmg = e.enemy_data.health * GameSettings.spell_white_wrath_damage_pct * charge_pct
				e.take_damage(dmg)
			if e.has_method("apply_blind"):
				e.apply_blind(3.0)

func cast_white_pacifism() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 25.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("apply_pacifism"):
			enemy.apply_pacifism(GameSettings.spell_white_pacifism_duration)

func cast_white_gideons_reproach() -> void:
	gideon_reproach_timer = 8.0

# --- BLACK SPELLS ---
func cast_black_drain_life() -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	proj.activate(spawn_pos, dir, 5, false, 1.0, -1.0, 0.0, self)

func cast_black_toxic_deluge(charge_pct: float) -> void:
	var hp_cost = hp * GameSettings.spell_black_toxic_deluge_hp_cost_pct * charge_pct
	take_damage(hp_cost)
	
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 40.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 1)
	var result = space_state.intersect_ray(query)
	var target_pos = result.position if result else (global_position - transform.basis.z * 8.0)
	
	var zone = DoTZone.new()
	zone.setup("toxic_deluge", GameSettings.spell_black_toxic_deluge_radius, 40.0 * charge_pct, 6.0, self)
	zone.global_position = target_pos
	get_tree().current_scene.add_child(zone)

func cast_black_doom_blade() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 5.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("take_damage"):
			enemy.take_damage(GameSettings.spell_black_doom_blade_damage)
		if enemy.has_method("apply_doom_curse"):
			enemy.apply_doom_curse(GameSettings.spell_black_doom_blade_curse_duration, GameSettings.spell_black_doom_blade_curse_mult)

func cast_black_tendrils() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var is_combo = (now - last_spell_cast_time) < 3.0
	var targets_count = 3 if is_combo else 1
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	var hit = 0
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 15.0:
			if e.has_method("take_damage"):
				e.take_damage(GameSettings.spell_black_tendrils_damage)
				heal(GameSettings.spell_black_tendrils_damage * 0.5)
				hit += 1
				if hit >= targets_count:
					break

func cast_black_sign_in_blood() -> void:
	var cost = hp * GameSettings.spell_black_sign_in_blood_hp_cost_pct
	take_damage(cost)
	spell_cooldown_timers.clear()
	print("Sign in Blood: All skill cooldowns reset!")

func cast_basic_attack() -> void:
	var cd = spell_cooldown_timers.get("basic_attack", 0.0)
	if cd > 0.0:
		return
	spell_cooldown_timers["basic_attack"] = GameSettings.spell_cooldown_melee
	
	var dmg = GameSettings.spell_melee_damage
	if unlocked_capstone_aura == "aura_glorious_anthem":
		dmg *= GameSettings.aura_glorious_anthem_damage_mult
	elif unlocked_capstone_aura == "aura_phyrexian_arena":
		dmg *= GameSettings.aura_phyrexian_arena_damage_mult
		
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * GameSettings.spell_melee_range
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
	else:
		var enemies = get_tree().get_nodes_in_group("enemies")
		for e in enemies:
			if is_instance_valid(e) and global_position.distance_to(e.global_position) <= GameSettings.spell_melee_range:
				var dir_to_e = (e.global_position - global_position).normalized()
				if -transform.basis.z.dot(dir_to_e) > GameSettings.spell_melee_cone:
					if e.has_method("take_damage"):
						e.take_damage(dmg)

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
		return

	# Continuous Auto-Attack on Left Click hold
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cast_basic_attack()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Overrun Dash Physics
	if overrun_dash_timer > 0.0:
		overrun_dash_timer -= delta
		velocity = overrun_dir * GameSettings.spell_green_overrun_dash_speed
		move_and_slide()
		var enemies = get_tree().get_nodes_in_group("enemies")
		for e in enemies:
			if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 2.5:
				if e.has_method("take_damage"):
					e.take_damage(GameSettings.spell_melee_damage * GameSettings.spell_green_overrun_damage_mult)
				if e.has_method("apply_knockback"):
					e.apply_knockback(overrun_dir * 10.0)
		return

	# Charging Logic
	if is_charging:
		charge_timer += delta
		SignalBus.spell_charge_changed.emit(charge_timer, charge_max_time, true)
		if charge_timer >= charge_max_time:
			release_charged_spell()

	# Timers
	if counterspell_parry_timer > 0.0: counterspell_parry_timer -= delta
	if briar_patch_timer > 0.0: briar_patch_timer -= delta
	if gideon_reproach_timer > 0.0: gideon_reproach_timer -= delta

	# Base & Aura Passive HP Regeneration
	var regen_amount = GameSettings.player_base_hp_regen * delta
	if unlocked_capstone_aura == "aura_sylvan_library":
		regen_amount += GameSettings.aura_sylvan_library_regen * delta
	heal(regen_amount, false)

	if unlocked_capstone_aura == "aura_phyrexian_arena":
		var drain = max_hp * GameSettings.aura_phyrexian_arena_hp_drain_pct * delta
		hp = max(1.0, hp - drain)
		SignalBus.player_health_changed.emit(hp, max_hp)

	# Crosshair target checking
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 50.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
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

	# Teammate revive check
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

	# Mana Harvesting & Base
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

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = speed
	if unlocked_capstone_aura == "aura_fervor":
		current_speed *= GameSettings.aura_fervor_speed_boost
	elif unlocked_capstone_aura == "aura_phyrexian_arena":
		current_speed *= GameSettings.aura_phyrexian_arena_speed_mult
		
	if Input.is_action_pressed("sprint"):
		current_speed *= GameSettings.player_sprint_speed_mult
	if slow_timer > 0:
		current_speed *= GameSettings.player_carry_speed_penalty
	if carried_color != "":
		current_speed *= GameSettings.player_carry_speed_penalty
		
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

	# Cooldowns
	for key in spell_cooldown_timers.keys():
		var cdr = 1.0
		if unlocked_capstone_aura == "aura_rhystic_study":
			cdr = GameSettings.aura_rhystic_study_cdr_mult
		spell_cooldown_timers[key] -= delta / cdr
		if spell_cooldown_timers[key] <= 0.0:
			spell_cooldown_timers.erase(key)
