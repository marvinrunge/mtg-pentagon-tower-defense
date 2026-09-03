extends StaticBody3D
class_name FrostGlobe
## Blue's blue_3: a sphere of ice that enemy fire cannot pass through.
##
## The whole skill is one collision layer choice, so it is worth writing down which and
## why. The layers in this project are:
##
##   1  world and static obstacles      2  player, myrs and summons
##   3  enemies                         5  environment blockers
##
## An enemy projectile's mask is 19 (layers 1, 2 and 5); a player projectile's is 22
## (layers 2, 3 and 5). Layer **1** is the only one in the first and not the second - so
## a globe sitting on layer 1 stops enemy arrows and bolts while the player keeps
## shooting straight through their own cover, which is exactly what the design asks for.
##
## Enemies themselves mask 31, everything, so melee has to walk around it. That falls out
## of the same choice rather than needing a second one.

var _life_timer: float = 0.0
var _radius: float = 2.4
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


static func create(radius: float, duration: float) -> FrostGlobe:
	var globe := FrostGlobe.new()
	globe._radius = radius
	globe._life_timer = duration
	globe.name = "FrostGlobe"
	return globe


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = _radius
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = _radius
	sphere_mesh.height = _radius * 2.0
	_mesh.mesh = sphere_mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.55, 0.85, 1.0, 0.42)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color(0.4, 0.8, 1.0)
	_material.emission_energy_multiplier = 1.5
	_material.rim_enabled = true
	_material.rim = 0.9
	# Drawn from both sides so the player standing inside their own globe can still see
	# out of it rather than facing a wall of backface culling.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 2.0
	light.omni_range = _radius * 3.0
	add_child(light)

	# Grows into place rather than popping in, which also gives anything standing where
	# it lands a moment to be pushed clear by the physics rather than trapped.
	scale = Vector3.ONE * 0.2
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	# Fades over its last second, so the cover disappearing is something the player can
	# see coming rather than something they notice by being shot.
	if _life_timer < 1.0:
		_material.albedo_color.a = 0.42 * _life_timer
