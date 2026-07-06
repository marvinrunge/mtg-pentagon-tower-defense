extends Area3D
class_name Projectile

@export var base_speed: float = 30.0
@export var base_damage: float = 50.0
@export var base_lifetime: float = 2.5

var speed: float = 30.0
var damage: float = 50.0
var lifetime: float = 2.5

var direction: Vector3 = Vector3.FORWARD
var active: bool = false
var life_timer: float = 0.0

# 0 = Normal, 1 = Red Shock, 2 = Blue Unsummon
var proj_type: int = 0

@onready var visual: CSGSphere3D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func activate(start_pos: Vector3, dir: Vector3, type: int) -> void:
	global_position = start_pos
	direction = dir
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	proj_type = type
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
		speed = base_speed * 1.5
		damage = base_damage * 2.0
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission = Color(1.0, 0.1, 0.1)
	elif type == 2:
		# Unsummon (Blue wave)
		speed = base_speed * 0.8
		damage = 0.0 # Doesn't deal damage, triggers unsummon
		mat.albedo_color = Color(0.1, 0.3, 1.0)
		mat.emission = Color(0.1, 0.3, 1.0)
	
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
		
	if body.is_in_group("player"):
		return
		
	if proj_type == 2:
		if body.has_method("unsummon"):
			body.unsummon()
	else:
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	deactivate()
