class_name EmberFx
extends RefCounted
## Builds the fire effects the red and green spells are made of, so Fireball, Rain of
## Ember and Titanic Leap are recognisably the same element rather than three
## unrelated orange things.
##
## Two textures do all the work, and both are WHITE on transparent on purpose - every
## colour comes from the particle system's own gradient, so one texture serves a
## red fireball, an orange firestorm and anything blue or green a later spell wants.
## See docs/VFX_TEXTURES.md for where they came from and how to replace them.
##
## The shape of each effect is a pair of systems rather than one, which is the whole
## reason it reads as fire:
##
##   BODY   large, soft, slow, alpha-blended turbulent puffs that grow as they rise
##          and cool from bright orange to dark grey - the mass of the flame
##   SPARKS small, hard, fast, ADDITIVELY blended points on a jagged scale curve, so
##          they flicker on and off rather than fading - the embers coming off it
##
## Alpha for the body and additive for the sparks is the important half of that: a
## fully additive fire has no darks in it and turns into a white blob wherever it
## overlaps itself, while fully alpha-blended sparks never look hot.
##
## Counts are deliberately modest. This is a tower defence: a late wave can have a
## firestorm burning while several fireballs are in flight, on machines that already
## needed a graphics-options menu to run at all.

const TEXTURE_DIR := "res://assets/vfx/"
## The turbulent puff the flame body is made of.
const FIRE_TEXTURE := TEXTURE_DIR + "fire_smoke.png"
## The soft round falloff a spark or a point of light is made of.
const SPARK_TEXTURE := TEXTURE_DIR + "spark_glow.png"


## Bright orange through red into cooling grey, with the alpha carrying the fade so
## the puff dissolves rather than darkening into a visible grey disc.
static func fire_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 0.85, 0.42, 1.0))
	gradient.add_point(0.18, Color(1.0, 0.55, 0.12, 1.0))
	gradient.add_point(0.45, Color(0.92, 0.24, 0.05, 0.85))
	gradient.add_point(0.75, Color(0.35, 0.20, 0.18, 0.4))
	gradient.set_offset(4, 1.0)
	gradient.set_color(4, Color(0.16, 0.14, 0.14, 0.0))
	return gradient


static func _ramp() -> GradientTexture1D:
	var texture := GradientTexture1D.new()
	texture.gradient = fire_gradient()
	return texture


static func _curve_texture(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("VFX texture '%s' is missing; fire will fall back to flat quads" % path)
		return null
	return load(path) as Texture2D


## One particle's billboard.
##
## `additive` is what separates a spark from a puff of flame - see this file's header.
## BILLBOARD_PARTICLES rather than plain BILLBOARD_ENABLED so the quads keep facing
## the camera while still honouring each particle's own rotation and scale, which is
## what stops a rising column from reading as a stack of identical stamps.
static func particle_mesh(size: float, texture: Texture2D, additive: bool) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this the billboarding throws each particle's own scale away.
	material.billboard_keep_scale = true
	# The colour ramp reaches the quad as a vertex colour; this is what lets it tint.
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	# Particles overlap themselves constantly and are never anything but translucent,
	# so sorting and depth writes buy nothing and cost fill rate.
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = material
	return mesh


## The rising body of a flame: born small in a tight sphere, drifting up, growing and
## cooling as it goes. The shared base every fire effect here is built on.
static func build_flame(scale_factor: float, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 1.2
	particles.local_coords = false
	particles.draw_pass_1 = particle_mesh(1.1 * scale_factor, _texture(FIRE_TEXTURE), false)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2 * scale_factor
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 1.0 * scale_factor
	process.initial_velocity_max = 2.0 * scale_factor
	# Fire falls UP: positive gravity is what makes the column accelerate away rather
	# than arc back down like debris.
	process.gravity = Vector3(0.0, 1.0 * scale_factor, 0.0)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.5
	process.scale_max = 0.9
	# Small at birth, largest around two thirds through, thinning as it dies - a puff
	# that only ever grows never looks like it is being consumed.
	process.scale_curve = _curve_texture([
		Vector2(0.0, 0.35), Vector2(0.65, 1.0), Vector2(1.0, 0.75),
	])
	process.color_ramp = _ramp()
	particles.process_material = process
	return particles


## The embers coming off a flame. Additive, on a ring rather than a sphere so they
## come off the OUTSIDE of the fire, and on a deliberately jagged scale curve: bouncing
## between large and tiny several times over a particle's life is what reads as a spark
## blinking, where a smooth fade would just read as a small soft dot.
static func build_sparks(radius: float, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 1.0
	particles.local_coords = false
	particles.draw_pass_1 = particle_mesh(0.18, _texture(SPARK_TEXTURE), true)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.35
	process.emission_ring_height = 0.2
	process.direction = Vector3.UP
	process.spread = 22.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, 1.4, 0.0)
	process.damping_min = 0.5
	process.damping_max = 2.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.scale_curve = _curve_texture([
		Vector2(0.0, 1.0), Vector2(0.12, 0.15), Vector2(0.28, 0.95),
		Vector2(0.44, 0.2), Vector2(0.58, 0.8), Vector2(0.74, 0.1),
		Vector2(0.88, 0.55), Vector2(1.0, 0.0),
	])
	process.color_ramp = _ramp()
	particles.process_material = process
	return particles


## A light that never sits still, for the middle of a fire. Driven from code rather
## than from a keyframed AnimationPlayer: two waves at unrelated frequencies never
## repeat over any window the eye can latch onto, where a looping keyframe track
## eventually does. Callers tick it with `flicker()`.
static func build_fire_light(range_units: float, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.48, 0.16)
	light.omni_range = range_units
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	return light


static func flicker(light: OmniLight3D, phase: float) -> void:
	var base: float = float(light.get_meta("base_energy", 1.0))
	light.light_energy = base + sin(phase * 11.0) * base * 0.18 + sin(phase * 6.3) * base * 0.12


# --- the effects themselves ---------------------------------------------------

## The tail a fireball drags behind it. Emitted in world space and left behind by the
## projectile's own motion, which is why the particles need almost no velocity of
## their own - `local_coords = false` is doing the work.
static func build_trail(amount: int) -> GPUParticles3D:
	var particles := build_flame(0.45, amount)
	particles.lifetime = 0.5
	var process: ParticleProcessMaterial = particles.process_material
	# A trail is dragged, not launched: its own motion would smear the tail sideways.
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.5
	process.gravity = Vector3(0.0, 0.8, 0.0)
	return particles


## The one-shot flash a fireball leaves where it detonated. Frees itself; nothing
## pools these because a fireball only ever explodes once.
static func build_burst(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FireballBurst"

	var flame := build_flame(radius * 0.22, 40)
	flame.lifetime = 0.8
	flame.one_shot = true
	flame.explosiveness = 0.85
	flame.emitting = true
	var flame_process: ParticleProcessMaterial = flame.process_material
	flame_process.spread = 180.0
	flame_process.initial_velocity_min = radius * 0.8
	flame_process.initial_velocity_max = radius * 2.0
	flame_process.damping_min = 4.0
	flame_process.damping_max = 9.0
	root.add_child(flame)

	var sparks := build_sparks(radius * 0.3, 36)
	sparks.lifetime = 0.9
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	var spark_process: ParticleProcessMaterial = sparks.process_material
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = radius * 1.5
	spark_process.initial_velocity_max = radius * 3.2
	spark_process.gravity = Vector3(0.0, -3.0, 0.0)
	root.add_child(sparks)

	var flash := build_fire_light(radius * 3.5, 6.0)
	root.add_child(flash)

	# Both halves are driven from one tween so the light dies with the embers rather
	# than snapping off while they are still visible.
	var tween := root.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.45)
	tween.tween_interval(0.5)
	tween.tween_callback(root.queue_free)
	return root


## Embers raining down INTO a zone from above - the half of Rain of Ember that sells
## it as something falling rather than as a decal switched on. Sparks rather than
## flame bodies, because falling fire reads as points of light, not as puffs.
static func build_rain(radius: float) -> GPUParticles3D:
	var particles := build_sparks(radius, 70)
	particles.lifetime = 1.6
	particles.draw_pass_1 = particle_mesh(0.3, _texture(SPARK_TEXTURE), true)
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Spawned in a flat slab well overhead, so they are already falling by the time
	# they enter frame.
	process.emission_box_extents = Vector3(radius, 0.4, radius)
	process.direction = Vector3.DOWN
	process.spread = 6.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 9.0
	process.gravity = Vector3(0.0, -6.0, 0.0)
	particles.position = Vector3(0.0, 7.0, 0.0)
	return particles


## The fire actually burning on the ground under that rain. The flame body, spread
## across the whole zone rather than rising from one point.
static func build_ground_fire(radius: float) -> GPUParticles3D:
	var particles := build_flame(1.0, 54)
	particles.lifetime = 1.3
	particles.draw_pass_1 = particle_mesh(radius * 0.5, _texture(FIRE_TEXTURE), false)
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.1
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0.0, 1.6, 0.0)
	particles.position = Vector3(0.0, 0.2, 0.0)
	return particles
