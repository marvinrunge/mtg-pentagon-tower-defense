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

# 0 = Normal, 1 = Red Shock, 2 = Blue Unsummon
var proj_type: int = 0

@onready var visual: CSGSphere3D = $Visual

func _ready() -> void:
	base_speed = GameSettings.projectile_base_speed
	base_damage = GameSettings.projectile_base_damage
	base_lifetime = GameSettings.projectile_base_lifetime
	speed = base_speed
	damage = base_damage
	lifetime = base_lifetime
	body_entered.connect(_on_body_entered)

func activate(start_pos: Vector3, dir: Vector3, type: int, _is_enemy: bool = false, multiplier: float = 1.0, damage_override: float = -1.0) -> void:
	global_position = start_pos
	direction = dir
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	proj_type = type
	is_enemy = _is_enemy
	var mat = visual.material.duplicate() as StandardMaterial3D
	visual.material = mat
	
	if type == 0:
		# Normal (Blue-ish)
		speed = base_speed
		damage = base_damage
		mat.albedo_color = Color(0.3, 0.8, 1.0)
		mat.emission = Color(0.2, 0.6, 1.0)
	elif type == 1:
		# Shock (Red, fast, high damage)
		speed = base_speed * GameSettings.projectile_shock_speed_mult
		damage = base_damage * GameSettings.projectile_shock_damage_mult * multiplier
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
		
	if damage_override >= 0.0:
		damage = damage_override
	
	life_timer = base_lifetime

func deactivate() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

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
		
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage)
		elif body.has_method("take_damage"):
			body.take_damage(damage)
		elif body.is_in_group("crystal"):
			SignalBus.crystal_damaged.emit(damage)
		deactivate()
		return

	# Player projectile logic
	if body.is_in_group("player"):
		return
		
	if proj_type == 2:
		if body.has_method("unsummon"):
			body.unsummon()
	else:
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	deactivate()
