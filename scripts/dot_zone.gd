extends Area3D
class_name DoTZone

var zone_type: String = "fire_rain" # fire_rain, toxic_deluge, holy_trail
var dps: float = 25.0
var radius: float = 5.0
var duration: float = 5.0
var tick_interval: float = 0.5
var caster: Node3D = null

var _tick_timer: float = 0.0
var _life_timer: float = 0.0
var visual: CSGCylinder3D

func setup(p_type: String, p_radius: float, p_dps: float, p_duration: float, p_caster: Node3D = null) -> void:
	zone_type = p_type
	radius = p_radius
	dps = p_dps
	duration = p_duration
	caster = p_caster

func _ready() -> void:
	# Collision setup
	collision_layer = 0
	if zone_type == "holy_trail":
		collision_mask = 2 # Player & allies
	else:
		collision_mask = 4 # Enemies
		
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.0
	col.shape = shape
	add_child(col)
	
	# Visual setup
	visual = CSGCylinder3D.new()
	visual.radius = radius
	visual.height = 0.2
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	
	if zone_type == "fire_rain":
		mat.albedo_color = Color(1.0, 0.3, 0.1, 0.4)
		mat.emission = Color(1.0, 0.2, 0.0)
	elif zone_type == "toxic_deluge":
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.4)
		mat.emission = Color(0.1, 0.6, 0.1)
	elif zone_type == "holy_trail":
		mat.albedo_color = Color(1.0, 1.0, 0.8, 0.4)
		mat.emission = Color(1.0, 0.9, 0.5)
		
	visual.material = mat
	add_child(visual)
	_life_timer = duration

func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
		
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_ticks()

func _apply_ticks() -> void:
	var bodies = get_overlapping_bodies()
	var damage = dps * tick_interval
	
	for b in bodies:
		if not is_instance_valid(b):
			continue
			
		if zone_type == "holy_trail":
			if b.is_in_group("player") and b.has_method("heal"):
				b.heal(damage)
		else:
			if b.is_in_group("enemies") and b.has_method("take_damage"):
				b.take_damage(damage, caster)
