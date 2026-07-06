extends Node3D
class_name BaseWall

var wall_type: String = "Colorless"
var health: float = 400.0
var max_health: float = 400.0
var is_dead: bool = false
var bone_revive_timer: float = 0.0

@onready var combiner: CSGCombiner3D = $Geometry
@onready var outer: CSGCylinder3D = $Geometry/Outer

func _ready() -> void:
	# Add the Area3D to walls group
	if not is_in_group("walls"):
		add_to_group("walls")
	set_meta("wall_parent", self)
	
	apply_wall_visuals()

func apply_wall_visuals() -> void:
	var color = Color.WHITE
	match wall_type:
		"Colorless": color = Color(0.6, 0.6, 0.6)
		"White": color = Color(1.0, 1.0, 0.9)
		"Blue": color = Color(0.4, 0.7, 1.0)
		"Black": color = Color(0.2, 0.2, 0.2)
		"Red": color = Color(0.8, 0.2, 0.1)
		"Green": color = Color(0.2, 0.7, 0.2)
		
	if outer:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		
		if wall_type == "Blue":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.3, 0.6, 1.0, 0.6)
		elif wall_type == "Red":
			mat.emission_enabled = true
			mat.emission = Color(0.8, 0.2, 0.0)
			
		outer.material = mat

func setup(type: String) -> void:
	wall_type = type
	match type:
		"Colorless": max_health = 400.0
		"White": max_health = 500.0
		"Blue": max_health = 700.0
		"Black": max_health = 400.0
		"Red": max_health = 500.0
		"Green": max_health = 500.0
		
	health = max_health
	apply_wall_visuals()

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if is_dead:
		return
		
	health -= amount
	
	if attacker:
		if wall_type == "White" and attacker.has_method("take_damage"):
			attacker.take_damage(15.0) # Thorns
		elif wall_type == "Blue" and attacker.has_method("apply_frost_slow"):
			attacker.apply_frost_slow(4.0) # Slow
			
	if health <= 0:
		die()

func die() -> void:
	is_dead = true
	if wall_type == "Black":
		# Pile of bones
		if combiner:
			combiner.use_collision = false
			combiner.scale.y = 0.1
			combiner.position.y = 0.1
	else:
		queue_free()

func revive_bone_wall() -> void:
	if wall_type == "Black" and is_dead:
		is_dead = false
		health = max_health * 0.5
		if combiner:
			combiner.use_collision = true
			combiner.scale.y = 1.0
			combiner.position.y = 1.0

func trigger_fire_wave() -> void:
	if wall_type == "Red" and not is_dead:
		# Deal massive damage to all enemies within 30m
		var enemies = get_tree().get_nodes_in_group("enemies")
		for e in enemies:
			if is_instance_valid(e) and global_position.distance_to(e.global_position) < 30.0:
				if e.has_method("take_damage"):
					e.take_damage(200.0)
					
func _process(delta: float) -> void:
	if wall_type == "Green" and not is_dead:
		# Passive buff to player action mana?
		# Currently player has no action mana. Let's just give small health regen to player.
		var players = get_tree().get_nodes_in_group("player")
		for p in players:
			if is_instance_valid(p) and global_position.distance_to(p.global_position) < 30.0:
				if p.has_method("heal"):
					p.heal(5.0 * delta)
