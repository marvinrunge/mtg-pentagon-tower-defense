class_name EmberFx
extends RefCounted
## Builds the fire effects the red and green spells are made of, so Fireball, Rain of
## Ember and Titanic Brawl are recognisably the same element rather than three
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


## The wind every drop of a Rain of Ember shares, so the big drops and the small ones read
## as one storm slanting the same way rather than two that disagree.
const RAIN_SLANT := Vector3(0.2, -1.0, 0.08)


## Drops of fire falling INTO a zone from above - the half of Rain of Ember that sells it
## as something falling rather than as a decal switched on.
##
## A plain bright point with a tail, not a textured lump: falling fire reads as a hot point
## of light dragging its own streak, and a flame texture squashed into a ball read as
## neither. The head is a warm yellow and the tail a deeper orange, so the two read as one
## glowing drop rather than a white pearl on a thread.
##
## Premultiplied rather than additive (see SpellFx.premul_particle_mesh), so the drops still
## read against a bright sky. They do not blink like the sparks do: a tail flickering on and
## off with its head looked like a fault, not like fire.
##
## `height` is where they start above the zone. Lifetime is sized to carry the slowest drop
## a little past the ground, so drops end by sinking into it rather than vanishing in the air.
static func build_falling_drops(radius: float, amount: int, size: float, speed_min: float,
		speed_max: float, tail_width: float, tail_length: float, height: float) -> GPUParticles3D:
	var gravity: float = 8.0
	var particles := GPUParticles3D.new()
	particles.amount = amount
	# Time for the slowest drop to fall `height` (v t + g t^2 / 2 = h), plus a margin.
	particles.lifetime = (-speed_min + sqrt(speed_min * speed_min + 2.0 * gravity * height)) / gravity + 0.15
	particles.randomness = 0.5
	particles.local_coords = false
	# Down to the ground and a little under it, plus the slant's drift sideways.
	particles.visibility_aabb = AABB(Vector3(-radius - 3.0, -height - 2.0, -radius - 3.0),
		Vector3(radius * 2.0 + 6.0, height + 3.0, radius * 2.0 + 6.0))
	var head: QuadMesh = SpellFx.premul_particle_mesh(size, "spark")
	# Above 1 so the head blooms, but warm: a near-white head read as a pearl, not as fire.
	(head.material as StandardMaterial3D).albedo_color = Color(1.6, 1.15, 0.6)
	particles.draw_pass_1 = head
	# The head is a billboard and has no direction of its own; the tail gives it one.
	particles.draw_passes = 2
	particles.draw_pass_2 = _drop_tail_mesh(tail_width, tail_length, size * 0.25, Color(1.8, 0.66, 0.16))

	var process := ParticleProcessMaterial.new()
	# Spawned in a flat slab well overhead, so they are already falling by the time they
	# enter frame.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(radius, 0.4, radius)
	process.direction = RAIN_SLANT
	process.spread = 4.0
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0.0, -gravity, 0.0)
	process.particle_flag_align_y = true
	process.scale_min = 0.8
	process.scale_max = 1.2
	process.color_ramp = _premul_ramp(_drop_gradient())
	particles.process_material = process
	# Shifted up-wind by roughly the drift the slant adds on the way down, so the drops
	# land on the zone and not beside it.
	var drift: float = height * 0.8
	particles.position = Vector3(-RAIN_SLANT.x * drift, height, -RAIN_SLANT.z * drift)
	return particles


## Embers rising off a burning zone the way they rise off a campfire: let go near the
## ground at random, carried up by the heat, swirling and fluttering on the way.
##
## Real sparks are tiny - far smaller than a pixel a few metres off - and what makes them
## look fine rather than cheap is exactly that. Both halves are shaders of their own:
## ember_sparks.gdshader moves them (a climb and a swirl kept separate, so they can loop
## hard and still rise), and ember_spark_streak.gdshader draws each one as a short smear
## of light along its travel that never blinks out for being below a pixel.
##
## Cheap enough to use plenty: one small quad each, no texture.
static func build_rising_sparks(radius: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = clampi(int(radius * 36.0), 80, 240)
	particles.lifetime = 2.4
	# Let go at uneven moments, not in a steady trickle.
	particles.randomness = 0.8
	particles.local_coords = false
	# Steps the swirl often enough that its fast flutter stays a curve, not a zigzag.
	particles.fixed_fps = 60
	particles.visibility_aabb = AABB(Vector3(-radius - 2.0, -1.0, -radius - 2.0),
		Vector3(radius * 2.0 + 4.0, 7.0, radius * 2.0 + 4.0))

	var process := ShaderMaterial.new()
	process.shader = preload("res://assets/shaders/ember_sparks.gdshader")
	process.set_shader_parameter("emission_radius", radius * 0.85)
	particles.process_material = process

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var draw := ShaderMaterial.new()
	draw.shader = preload("res://assets/shaders/ember_spark_streak.gdshader")
	draw.render_priority = SpellFx.FX_RENDER_PRIORITY
	mesh.material = draw
	particles.draw_pass_1 = mesh
	particles.position = Vector3(0.0, 0.1, 0.0)
	return particles


## Yellow into orange, holding its alpha almost to the end: a drop is still burning when
## it lands.
static func _drop_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	gradient.add_point(0.35, Color(1.0, 0.7, 0.3, 1.0))
	gradient.add_point(0.85, Color(1.0, 0.48, 0.14, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.9, 0.3, 0.08, 0.0))
	return gradient


## The streak behind a falling drop: two crossed quads running from just inside the head
## back along -Y (so `particle_flag_align_y` lays it along the fall), tapering from
## `width` at the head to a point.
##
## Not SpellFx.tail_mesh: trail_trace.png fills only a sliver of its quad and is brightest
## in the MIDDLE, so a tail built from it was a hairline floating behind the head with a gap
## in front. This one is brightest where it meets the head and fades out along its length.
static func _drop_tail_mesh(width: float, length: float, overlap: float, tint: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head_half: float = width * 0.5
	var end_half: float = width * 0.12
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var corners: Array = [
			[-side * head_half + Vector3.UP * overlap, Vector2(0.0, 0.0)],
			[side * head_half + Vector3.UP * overlap, Vector2(1.0, 0.0)],
			[side * end_half + Vector3.DOWN * length, Vector2(1.0, 1.0)],
			[-side * end_half + Vector3.DOWN * length, Vector2(0.0, 1.0)],
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.set_uv(corners[index][1])
			st.add_vertex(corners[index][0])
	var mesh: ArrayMesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = _drop_tail_texture()
	material.albedo_color = tint
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_fog = true
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	mesh.surface_set_material(0, material)
	return mesh


static var _tail_texture: Texture2D


## Soft across, bright at the head (v = 0) and fading to nothing at the end (v = 1),
## premultiplied. Built once in code: it is a falloff, not a picture worth a file.
static func _drop_tail_texture() -> Texture2D:
	if _tail_texture != null:
		return _tail_texture
	var image := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y: int in 128:
		var along: float = pow(1.0 - float(y) / 127.0, 1.6)
		for x: int in 32:
			var across: float = (float(x) + 0.5) / 32.0 * 2.0 - 1.0
			var a: float = exp(-across * across * 4.0) * along
			image.set_pixel(x, y, Color(a, a, a, a))
	_tail_texture = ImageTexture.create_from_image(image)
	return _tail_texture


## `gradient` with every stop's RGB scaled by its alpha, for the premultiplied meshes - see
## SpellFx._premul_ramp for why both halves of the blend have to be premultiplied.
static func _premul_ramp(gradient: Gradient) -> GradientTexture1D:
	for index: int in gradient.get_point_count():
		var stop: Color = gradient.get_color(index)
		gradient.set_color(index, Color(stop.r * stop.a, stop.g * stop.a, stop.b * stop.a, stop.a))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


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
