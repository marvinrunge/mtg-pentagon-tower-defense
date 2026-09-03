extends Area3D
class_name DoTZone

## fire_rain, toxic_deluge, holy_trail, fog.
##
## `fog` is the odd one and the reason this comment exists: it is the only zone that does
## not deal or restore anything. Green's green_3 puts down ground where enemies deal NO
## damage, which is a zone in every other respect - a placed radius with a duration that
## ticks over whoever is standing in it - so it belongs here rather than in a class of
## its own that would duplicate the disc, the timer and the tick loop to change one line.
var zone_type: String = "fire_rain"
var dps: float = 25.0
var radius: float = 5.0
var duration: float = 5.0
var tick_interval: float = 0.5
var caster: Node3D = null

var _tick_timer: float = 0.0
var _life_timer: float = 0.0
var visual: CSGCylinder3D
## Only fire_rain builds these; the other zone types stay the plain disc they were.
var _rain: GPUParticles3D
var _ground_fire: GPUParticles3D
var _light: OmniLight3D
var _flicker_phase: float = 0.0

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
		collision_mask = 4 # Enemies (fog included - it acts ON them, it just acts gently)
		
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
	elif zone_type == "fog":
		mat.albedo_color = Color(0.72, 0.82, 0.78, 0.35)
		mat.emission = Color(0.45, 0.6, 0.5)
		
	visual.material = mat
	add_child(visual)
	if zone_type == "fire_rain":
		_build_firestorm()
	elif zone_type == "fog":
		_build_fog()
	_life_timer = duration


## Turns the flat disc into an actual firestorm: embers falling into it from above,
## flames coming up off the ground, and a light that flickers with them so the effect
## lands on everything standing in it rather than only on itself.
##
## Built here rather than authored as a scene because the zone's radius is a runtime
## number - every emitter is sized from it, and a fixed .tscn would only ever be right
## at one radius.
func _build_firestorm() -> void:
	# The disc itself becomes a soft scorch mark under the flames, rather than the
	# whole effect: at the old opacity it read as a flat sticker once the particles
	# were on top of it.
	var disc_material: StandardMaterial3D = visual.material as StandardMaterial3D
	disc_material.albedo_color = Color(0.75, 0.16, 0.03, 0.5)
	disc_material.emission = Color(1.0, 0.35, 0.05)
	disc_material.emission_energy_multiplier = 2.2
	disc_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.height = 0.06

	# A brighter rim, so the edge of the danger is readable from across the map -
	# this zone is something the player has to place, and then avoid standing in.
	var rim := CSGTorus3D.new()
	rim.inner_radius = radius * 0.94
	rim.outer_radius = radius
	rim.sides = 8
	rim.ring_sides = 6
	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rim_material.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	rim.material = rim_material
	rim.position = Vector3(0.0, 0.08, 0.0)
	add_child(rim)

	_rain = EmberFx.build_rain(radius)
	add_child(_rain)
	_ground_fire = EmberFx.build_ground_fire(radius)
	add_child(_ground_fire)

	_light = EmberFx.build_fire_light(radius * 2.4, 3.0)
	_light.position = Vector3(0.0, 1.6, 0.0)
	add_child(_light)

	# Nothing spawns at full strength: the storm rolls in over its first moments,
	# which also stops the light from popping on.
	scale = Vector3(0.4, 1.0, 0.4)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## The cloud itself. Low, wide and slow - it has to read as SAFE ground at a glance,
## which is the opposite of everything else this class builds, so it borrows nothing from
## the firestorm but the sizing-from-radius trick.
func _build_fog() -> void:
	var bank := GPUParticles3D.new()
	bank.amount = 48
	bank.lifetime = 4.0
	bank.local_coords = false
	bank.draw_pass_1 = EmberFx.particle_mesh(radius * 0.75, null, false)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.8
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3.ZERO
	process.scale_min = 0.8
	process.scale_max = 1.5
	process.color = Color(0.78, 0.85, 0.82, 0.25)
	bank.process_material = process
	bank.position = Vector3(0.0, 1.0, 0.0)
	add_child(bank)


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return

	if _light != null:
		_flicker_phase += delta
		EmberFx.flicker(_light, _flicker_phase)
	# Emitters stop early so the last embers in the air get to finish falling instead
	# of vanishing with the zone.
	if _life_timer < 0.6 and _rain != null and _rain.emitting:
		_rain.emitting = false
		_ground_fire.emitting = false
		
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

		if zone_type == "fog":
			# Refreshed every tick rather than applied on entry, so walking OUT of the
			# fog restores the enemy within one tick instead of it carrying a duration
			# away with it.
			if b.is_in_group("enemies") and b.has_method("suppress_damage"):
				b.suppress_damage(tick_interval * 2.0)
			continue

		if zone_type == "holy_trail":
			if b.is_in_group("player") and b.has_method("heal"):
				b.heal(damage)
		else:
			if b.is_in_group("enemies") and b.has_method("take_damage"):
				b.take_damage(damage, caster)
