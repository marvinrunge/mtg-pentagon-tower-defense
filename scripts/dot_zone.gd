extends Area3D
class_name DoTZone

## fire_rain, fire_patch, toxic_deluge, holy_trail, fog.
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
var visual: MeshInstance3D
var _ground_material: ShaderMaterial
## The fire zones build these; fog builds _fog.
var _rain: GPUParticles3D
var _drops: GPUParticles3D
var _sparks: GPUParticles3D
var _ground_fire: GPUParticles3D
## Air shimmering over the fire (SpellFx.heat_haze) - a bare Node3D where it is not drawn.
var _heat: Node3D
var _light: OmniLight3D
var _flicker_phase: float = 0.0
var _fog: GPUParticles3D
## Seconds the ground takes to come up and to go.
const FADE_IN := 0.25
const FADE_OUT := 0.6

## zone_ground.gdshader's look per zone type: style, burnt/damp colour, glowing colour.
const GROUND_LOOKS: Dictionary = {
	"fire_rain": [0, Color(0.07, 0.035, 0.02), Color(1.0, 0.42, 0.1)],
	"fire_patch": [0, Color(0.07, 0.035, 0.02), Color(1.0, 0.36, 0.08)],
	"toxic_deluge": [1, Color(0.08, 0.14, 0.04), Color(0.55, 0.95, 0.2)],
	"holy_trail": [2, Color(0.0, 0.0, 0.0), Color(1.0, 0.78, 0.36)],
	"fog": [3, Color(0.09, 0.13, 0.1), Color(0.7, 0.85, 0.75)],
}

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
	
	# The ground it covers, projected onto the real surface with a soft ragged edge. It
	# used to be a CSG cylinder: a hard-edged octagon that floated off any slope.
	_ground_material = _build_ground_material()
	visual = SpellVisuals.projected_volume(radius * 1.15, _ground_material)
	add_child(visual)
	if zone_type == "fire_rain":
		_build_firestorm()
	elif zone_type == "fire_patch":
		_build_fire_patch()
	elif zone_type == "fog":
		_build_fog()
	_life_timer = duration


## Turns the flat disc into an actual firestorm: drops of fire falling into it from above,
## flames coming up off the ground, sparks rising off them, and a light that flickers with
## them so the effect lands on everything standing in it rather than only on itself.
##
## Built here rather than authored as a scene because the zone's radius is a runtime
## number - every emitter is sized from it, and a fixed .tscn would only ever be right
## at one radius.
func _build_firestorm() -> void:
	# One looping voice per firestorm, hung on the zone so it stops when the zone does.
	# A one-shot at the cast site would end long before the fire did.
	SoundBank.attach_loop(&"spell_rain_ember", self, false)

	_rain = EmberFx.build_falling_drops(radius, 60, 0.13, 7.0, 10.0, 0.12, 1.6, 7.0)
	add_child(_rain)
	_drops = _build_falling_fire()
	add_child(_drops)
	_ground_fire = _build_flames(radius, 22, 1.1)
	add_child(_ground_fire)
	_sparks = EmberFx.build_rising_sparks(radius)
	add_child(_sparks)
	_heat = SpellFx.heat_haze(Vector3(radius * 0.7, 0.2, radius * 0.7), clampf(radius * 0.55, 1.4, 2.6),
		clampi(int(radius * 5.0), 10, 40), 1.3, 1.5, 0.013)
	_heat.position.y = 0.4
	add_child(_heat)

	_light = EmberFx.build_fire_light(radius * 2.4, 3.0)
	_light.position = Vector3(0.0, 1.6, 0.0)
	add_child(_light)

	# Nothing spawns at full strength: the storm rolls in over its first moments,
	# which also stops the light from popping on.
	scale = Vector3(0.4, 1.0, 0.4)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_fire_patch() -> void:
	_ground_fire = _build_flames(radius, 6, 0.9)
	add_child(_ground_fire)
	_heat = SpellFx.heat_haze(Vector3(radius * 0.6, 0.15, radius * 0.6), clampf(radius * 0.8, 1.0, 2.0),
		clampi(int(radius * 4.0), 5, 16), 1.1, 1.2, 0.011)
	_heat.position.y = 0.3
	add_child(_heat)

	_light = EmberFx.build_fire_light(radius * 1.8, 1.5)
	_light.position = Vector3(0.0, 0.7, 0.0)
	add_child(_light)

## The cloud itself. Low, wide and slow - it has to read as SAFE ground at a glance,
## which is the opposite of everything else this class builds, so it borrows nothing from
## the firestorm but the sizing-from-radius trick.
func _build_fog() -> void:
	# Slow, churning banks of the smoke flipbook rather than flat untextured quads, which
	# drew as hard-edged squares: low, wide, pale and barely moving, so it reads as safe
	# ground and not as something burning.
	_fog = ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, radius * 0.9, 26, 5.0)
	_fog.one_shot = false
	_fog.preprocess = 2.0
	var process: ParticleProcessMaterial = _fog.process_material
	process.anim_speed_min = 0.6
	process.anim_speed_max = 0.8
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 0.8
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.6
	process.direction = Vector3.UP
	process.spread = 60.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3(0.0, 0.03, 0.0)
	process.angular_velocity_min = -6.0
	process.angular_velocity_max = 6.0
	process.scale_min = 0.8
	process.scale_max = 1.3
	process.scale_curve = EmberFx._curve_texture([Vector2(0.0, 0.6), Vector2(1.0, 1.2)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.82, 0.9, 0.86, 0.0))
	gradient.add_point(0.25, Color(0.82, 0.9, 0.86, 0.42))
	gradient.add_point(0.75, Color(0.78, 0.86, 0.82, 0.38))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.75, 0.84, 0.8, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	_fog.position = Vector3(0.0, 0.7, 0.0)
	add_child(_fog)


func _build_ground_material() -> ShaderMaterial:
	var look: Array = GROUND_LOOKS.get(zone_type, GROUND_LOOKS["fire_patch"])
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/zone_ground.gdshader")
	material.set_shader_parameter("style", int(look[0]))
	material.set_shader_parameter("base_color", look[1])
	material.set_shader_parameter("glow_color", look[2])
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("seed", randf() * 100.0)
	material.set_shader_parameter("fade", 0.0)
	return material


## Fire burning ON the zone: the flame flipbook, looping for as long as the zone stands.
func _build_flames(size_radius: float, amount: int, lifetime: float) -> GPUParticles3D:
	var flames := ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, minf(size_radius * 0.55, 1.6), amount, lifetime)
	flames.one_shot = false
	var process: ParticleProcessMaterial = flames.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 0.85
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.0, 1.2, 0.0)
	process.angle_min = -15.0
	process.angle_max = 15.0
	process.scale_min = 0.6
	process.scale_max = 1.1
	process.scale_curve = EmberFx._curve_texture([Vector2(0.0, 0.3), Vector2(0.3, 1.0), Vector2(1.0, 0.5)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = EmberFx.fire_gradient()
	process.color_ramp = ramp
	flames.position = Vector3(0.0, 0.35, 0.0)
	return flames


## Rain of Ember's heavier half: big drops streaking down into the zone between the small
## ones, so the storm has weight as well as glitter.
func _build_falling_fire() -> GPUParticles3D:
	return EmberFx.build_falling_drops(radius * 0.8, 9, 0.32, 12.0, 16.0, 0.26, 3.2, 8.0)


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	var shown: float = minf((duration - _life_timer) / FADE_IN, _life_timer / FADE_OUT)
	_ground_material.set_shader_parameter("fade", clampf(shown, 0.0, 1.0))
	if _life_timer < FADE_OUT and _fog != null:
		_fog.emitting = false

	if _light != null:
		_flicker_phase += delta
		EmberFx.flicker(_light, _flicker_phase)
	# Emitters stop early so the last drops in the air get to finish falling instead
	# of vanishing with the zone.
	if _life_timer < 0.6 and _rain != null and _rain.emitting:
		_rain.emitting = false
		_drops.emitting = false
		_sparks.emitting = false
		_ground_fire.emitting = false
		if _heat is GPUParticles3D:
			(_heat as GPUParticles3D).emitting = false
		
	# The disc, the embers and the light run everywhere; the DAMAGE runs on the server
	# alone. The zone is spawned onto every peer so that all five players can see the
	# ground they must not stand on, and a client applying its own ticks on top of the
	# host's would burn everything inside it twice.
	if not Net.is_server():
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

		if zone_type == "fog":
			# Refreshed every tick rather than applied on entry, so walking OUT of the
			# fog restores the enemy within one tick instead of it carrying a duration
			# away with it.
			if b.is_in_group("enemies") and b.has_method("suppress_damage"):
				b.suppress_damage(tick_interval * 2.0)
				# Wading, not walking. Fog's real effect is invisible - enemies swinging and
				# connecting with nothing - so the cloud also has to LOOK like it is doing
				# something from across the field. Same refresh window as the suppression, so
				# both halves lapse together.
				if b.has_method("apply_slow"):
					b.apply_slow(tick_interval * 2.0, GameSettings.spell_green_fog_slow_mult)
			continue

		if zone_type == "holy_trail":
			if b.is_in_group("player") and b.has_method("heal"):
				var restored: float = b.heal(damage)
				if is_instance_valid(caster) and caster.has_method("_credit_heal"):
					caster._credit_heal(b, restored)
		else:
			if b.is_in_group("enemies") and b.has_method("take_damage"):
				b.take_damage(damage, caster)
