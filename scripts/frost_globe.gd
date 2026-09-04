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
var _base_alpha: float = 0.24


static func create(radius: float, duration: float) -> FrostGlobe:
	var globe := FrostGlobe.new()
	globe._radius = radius
	globe._life_timer = duration
	globe.name = "FrostGlobe"
	return globe


func _ready() -> void:
	# Solid to nothing: the projectile stop is the Area3D below, so every unit on
	# either side walks straight through the sphere instead of being walled by it.
	collision_layer = 0
	collision_mask = 0

	# The wall that is not a wall: enemy projectiles (group `projectiles`, marked by
	# Projectile.activate) are freed the moment they cross the shell. The area's mask
	# of 1 matches the layer Projectile sets on itself, so nothing else is even
	# reported to it.
	var shield_area := Area3D.new()
	shield_area.collision_layer = 0
	shield_area.collision_mask = 1
	var shield_shape := CollisionShape3D.new()
	var shield_sphere := SphereShape3D.new()
	shield_sphere.radius = _radius
	shield_shape.shape = shield_sphere
	shield_area.add_child(shield_shape)
	shield_area.body_entered.connect(_on_body_entered)
	add_child(shield_area)

	_mesh = MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = _radius
	sphere_mesh.height = _radius * 2.0
	_mesh.mesh = sphere_mesh
	_material = StandardMaterial3D.new()
	# High frost, low alpha: the colour rides on emission and a hard rim rather than on
	# the surface, so it reads as glowing ice haze rather than as a painted balloon.
	_material.albedo_color = Color(0.7, 0.92, 1.0, _base_alpha)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color(0.5, 0.85, 1.0)
	_material.emission_energy_multiplier = 2.2
	_material.rim_enabled = true
	_material.rim = 1.0
	_material.rim_tint = 0.9
	# Drawn from both sides so the player standing inside their own globe can still see
	# out of it rather than facing a wall of backface culling.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	add_child(_mesh)

	_build_frost_motes()

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 1.6
	light.omni_range = _radius * 3.0
	add_child(light)

	# Grows into place rather than popping in, which also gives anything standing where
	# it lands a moment to be pushed clear by the physics rather than trapped.
	scale = Vector3.ONE * 0.2
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A projectile caught by the shield simply never arrives. The globe's reason to exist
## is the projectile NOT coming through, so the stop is silent rather than spending a
## burst effect on every arrow that dies in it.
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("projectiles"):
		body.queue_free()


## The frost half of "frostier": slow icy motes drifting up through the volume of the
## sphere, so it reads as a shell of cold air rather than as a solid glass ball. Same
## builder path every other spell uses - colour comes from the ramp, never the texture.
func _build_frost_motes() -> void:
	var motes := GPUParticles3D.new()
	motes.amount = 36
	motes.lifetime = 2.8
	motes.preprocess = 2.8
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = _radius * 0.85
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.gravity = Vector3(0.0, 0.35, 0.0)
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.45
	process.scale_min = 0.04
	process.scale_max = 0.12
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.9, 1.0, 0.0))
	gradient.add_point(0.25, Color(0.8, 0.95, 1.0, 0.7))
	gradient.set_color(1, Color(0.5, 0.8, 1.0, 0.0))
	process.color_ramp = EmberFx._ramp()
	process.color_ramp.gradient = gradient
	motes.process_material = process
	motes.draw_pass_1 = EmberFx.particle_mesh(1.0, EmberFx._texture(EmberFx.SPARK_TEXTURE), true)
	add_child(motes)


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	# Fades over its last second, so the cover disappearing is something the player can
	# see coming rather than something they notice by being shot.
	if _life_timer < 1.0:
		_material.albedo_color.a = _base_alpha * _life_timer
