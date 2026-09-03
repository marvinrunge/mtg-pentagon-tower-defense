extends Area3D
class_name SoulWall
## Black's black_4: a wall enemies can walk through, and regret.
##
## It blocks nothing. Anything that crosses it is MARKED, and a marked enemy takes double
## damage from every source until the mark lapses - the existing `curse_timer` /
## `curse_mult` pair on EnemyBase, which `take_damage` already multiplies by.
##
## Placement is the interesting half. Rain of Ember picks a point with a camera raycast
## and that is enough for a circle, but a wall also needs to know which way it faces, and
## a wall the player has to rotate is a wall nobody places in a fight. It is therefore
## laid down PERPENDICULAR to the direction the player is looking - across the approach,
## never along it - so pointing at where the enemies are coming from is the whole
## interaction.

var _life_timer: float = 0.0
var _length: float = 14.0
var _mark_duration: float = 8.0
var _mark_mult: float = 2.0
var _caster: Node3D
var _material: StandardMaterial3D
## Enemies inside the wall right now. Re-marked every tick rather than only on entry, so
## an enemy that stops inside it does not walk out with a mark that started ticking down
## while it was still standing in the wall.
var _tick: float = 0.0

const TICK_INTERVAL := 0.4


static func create(length: float, duration: float, mark_duration: float, mark_mult: float, caster: Node3D) -> SoulWall:
	var wall := SoulWall.new()
	wall._length = length
	wall._life_timer = duration
	wall._mark_duration = mark_duration
	wall._mark_mult = mark_mult
	wall._caster = caster
	wall.name = "SoulWall"
	return wall


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # enemies only

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_length, 4.0, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, 0.0)
	add_child(shape)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.55, 0.2, 0.75, 0.4)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color(0.65, 0.25, 0.9)
	_material.emission_energy_multiplier = 2.4
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var curtain := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(_length, 4.0)
	curtain.mesh = quad
	curtain.material_override = _material
	curtain.position = Vector3(0.0, 2.0, 0.0)
	add_child(curtain)

	# The souls themselves, rising out of the line. Without them the wall is a purple
	# rectangle, and a purple rectangle does not read as something to avoid.
	var souls := EmberFx.build_sparks(_length * 0.5, 60)
	souls.lifetime = 2.2
	var process: ParticleProcessMaterial = souls.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(_length * 0.5, 0.2, 0.2)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 12.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.2
	process.gravity = Vector3.ZERO
	# build_sparks ships the FIRE ramp, which would multiply this purple back to orange.
	process.color_ramp = null
	process.color = Color(0.7, 0.35, 1.0)
	souls.draw_pass_1 = EmberFx.particle_mesh(0.45, null, true)
	add_child(souls)

	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.25, 0.95)
	light.light_energy = 2.2
	light.omni_range = _length * 0.5
	light.position = Vector3(0.0, 1.6, 0.0)
	add_child(light)


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	if _life_timer < 1.2:
		_material.albedo_color.a = 0.4 * (_life_timer / 1.2)

	# Marking is a game effect, so it is the server's. The curtain and the souls are not,
	# which is why the fade above runs everywhere.
	if not Net.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_INTERVAL
	for body: Node3D in get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("enemies"):
			continue
		if body.has_method("apply_doom_curse"):
			body.apply_doom_curse(_mark_duration, _mark_mult)
