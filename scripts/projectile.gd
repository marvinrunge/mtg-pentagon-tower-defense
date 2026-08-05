extends Area3D
class_name Projectile

var base_speed: float
var base_damage: float
var base_lifetime: float

var speed: float
var damage: float
var lifetime: float

var direction: Vector3 = Vector3.FORWARD
var active: bool = false
var life_timer: float = 0.0
var is_enemy: bool = false
var proj_type: int = 0
var aoe_radius: float = 0.0
var caster_ref: WeakRef
var effect_multiplier: float = 1.0

@onready var visual: CSGSphere3D = $Visual
var projectile_material: StandardMaterial3D

func _ready() -> void:
	base_speed = GameSettings.projectile_base_speed
	base_damage = GameSettings.projectile_base_damage
	base_lifetime = GameSettings.projectile_base_lifetime
	speed = base_speed
	damage = base_damage
	lifetime = base_lifetime
	projectile_material = visual.material.duplicate() as StandardMaterial3D
	visual.material = projectile_material
	body_entered.connect(_on_body_entered)

func activate(start_pos: Vector3, dir: Vector3, type: int, _is_enemy: bool = false, multiplier: float = 1.0, damage_override: float = -1.0, p_aoe_radius: float = 0.0, p_caster: Node3D = null) -> void:
	global_position = start_pos
	direction = dir
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	proj_type = type
	is_enemy = _is_enemy
	collision_mask = 19 if is_enemy else 22
	aoe_radius = p_aoe_radius
	caster_ref = weakref(p_caster) if is_instance_valid(p_caster) else null
	effect_multiplier = multiplier
	
	var mat: StandardMaterial3D = projectile_material
	
	if type == 0:
		# Normal (Blue-ish)
		speed = base_speed
		damage = base_damage
		mat.albedo_color = Color(0.3, 0.8, 1.0)
		mat.emission = Color(0.2, 0.6, 1.0)
	elif type == 1:
		# Shock (Red, fast, high damage)
		speed = base_speed * GameSettings.projectile_shock_speed_mult
		damage = GameSettings.spell_red_shock_damage * multiplier
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission = Color(1.0, 0.1, 0.1)
	elif type == 2:
		# Unsummon (Blue wave)
		speed = base_speed * GameSettings.projectile_unsummon_speed_mult * multiplier
		damage = 0.0 # Doesn't deal damage, triggers unsummon
		mat.albedo_color = Color(0.1, 0.3, 1.0)
		mat.emission = Color(0.1, 0.3, 1.0)
	elif type == 3:
		# Enemy Magic Missile (Purple/Pink)
		speed = base_speed * GameSettings.projectile_enemy_speed_mult
		damage = base_damage * GameSettings.projectile_enemy_damage_mult * GameSettings.get_player_scaling_factor(get_tree())
		mat.albedo_color = Color(0.8, 0.2, 0.8)
		mat.emission = Color(0.8, 0.2, 0.8)
	elif type == 4:
		# Fireball (Red Explosive)
		speed = base_speed * 0.9
		damage = GameSettings.spell_red_fireball_base_damage * multiplier
		mat.albedo_color = Color(1.0, 0.4, 0.0)
		mat.emission = Color(1.0, 0.3, 0.0)
	elif type == 5:
		# Drain Life (Black Vampiric)
		speed = base_speed * 1.1
		damage = GameSettings.spell_black_drain_life_damage * multiplier
		mat.albedo_color = Color(0.3, 0.0, 0.4)
		mat.emission = Color(0.4, 0.0, 0.5)
	elif type == 6:
		# Swords to Plowshares (White Holy Lance)
		speed = base_speed * 1.3
		damage = 0.0 # Handled in impact
		mat.albedo_color = Color(1.0, 1.0, 0.8)
		mat.emission = Color(1.0, 1.0, 0.6)
	elif type == 7:
		# Path to Exile Ray (White Execute Beam)
		speed = base_speed * 1.4
		damage = 0.0
		mat.albedo_color = Color(0.9, 0.9, 1.0)
		mat.emission = Color(0.9, 0.9, 1.0)
		
	if damage_override >= 0.0:
		damage = damage_override
	
	life_timer = base_lifetime

func deactivate() -> void:
	active = false
	visible = false
	caster_ref = null
	process_mode = Node.PROCESS_MODE_DISABLED

func _get_caster() -> Node3D:
	if caster_ref == null:
		return null
	return caster_ref.get_ref() as Node3D

func _physics_process(delta: float) -> void:
	if not active:
		return
		
	global_position += direction * speed * delta
	
	life_timer -= delta
	if life_timer <= 0:
		deactivate()

func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
		
	if is_enemy:
		# Enemy projectile hits player, myrs, crystal
		if body.is_in_group("enemies"):
			return # Ignore other enemies
		
		if body.has_method("take_damage"):
			body.take_damage(damage, _get_caster(), false)
		elif body.is_in_group("crystal_hitbox"):
			SignalBus.crystal_damaged.emit(damage)
		deactivate()
		return

	# Player projectile logic
	if body.is_in_group("player"):
		return
		
	if proj_type == 2:
		# Unsummon
		if body.has_method("unsummon"):
			body.unsummon(direction * GameSettings.spell_blue_unsummon_knockback)
	elif proj_type == 4:
		# Fireball AoE
		_trigger_fireball_aoe()
	elif proj_type == 5:
		# Drain Life
		if body.has_method("take_damage"):
			body.take_damage(damage)
			var current_caster: Node3D = _get_caster()
			if current_caster and current_caster.has_method("heal"):
				current_caster.heal(damage * GameSettings.spell_black_drain_life_lifesteal)
	elif proj_type == 6:
		# Swords to Plowshares (% Max HP Holy Exile or Ally Heal)
		if body.is_in_group("enemies"):
			if "health" in body and body.has_method("take_damage"):
				var max_h = body.enemy_data.health if ("enemy_data" in body and body.enemy_data) else 100.0
				var holy_dmg = minf(
					max_h * GameSettings.spell_white_swords_exile_pct * effect_multiplier,
					GameSettings.spell_white_swords_damage_cap
				)
				body.take_damage(holy_dmg)
		elif body.has_method("heal"):
			body.heal(GameSettings.spell_white_swords_ally_heal)
	elif proj_type == 7:
		# Path to Exile (% missing HP execute + Holy Trail)
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			if "health" in body and "enemy_data" in body and body.enemy_data:
				var missing_hp = body.enemy_data.health - body.health
				var exec_dmg = (40.0 + missing_hp * GameSettings.spell_white_path_to_exile_exec_mult) * effect_multiplier
				body.take_damage(exec_dmg)
		# Spawn Holy Trail
		var trail = DoTZone.new()
		trail.setup("holy_trail", 3.0, 15.0, 4.0, _get_caster())
		trail.global_position = global_position
		get_tree().current_scene.add_child(trail)
	else:
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	deactivate()

func _trigger_fireball_aoe() -> void:
	var radius = aoe_radius if aoe_radius > 0.0 else GameSettings.spell_red_fireball_base_radius
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)
	
	# Spawn temporary visual explosion
	var exp_mesh = CSGSphere3D.new()
	exp_mesh.radius = radius
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	exp_mesh.material = mat
	exp_mesh.global_position = global_position
	get_tree().current_scene.add_child(exp_mesh)
	
	var tw = exp_mesh.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.parallel().tween_property(exp_mesh, "scale", Vector3(1.3, 1.3, 1.3), 0.4)
	tw.tween_callback(exp_mesh.queue_free)
