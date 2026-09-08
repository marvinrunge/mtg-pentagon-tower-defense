class_name SpellFx
extends RefCounted
## The effects the non-fire spells are made of - white, blue, black and green.
##
## `EmberFx` is the same idea for red: one place that owns the shapes, so a colour's
## spells look like each other instead of like twenty-five separate ideas. This file is
## its sibling and follows its rules exactly:
##
##   * every shape is COLOURLESS and takes its tint from the caller, so one shockwave
##     serves Wrath of God, Unsummon and Roar
##   * a builder returns a node; the caller places it (see EmberFx.build_burst)
##   * anything one-shot frees itself from a tween started on `tree_entered`, because
##     `create_tween()` fails outside the tree and the effect would then never be freed
##
## What it replaces: `Player._spawn_ring`, `_spawn_beam` and `_spawn_cast_flash`, which
## drew every non-fire spell in the game as an emissive torus, an emissive cylinder or a
## bare light. Those three are now thin forwarders into this file - see
## docs/SPELL_VFX_PLAN.md, Phase 1.
##
## The two shaders here are deliberately TEXTURE-FREE: a ring and a beam are shapes a
## fragment function describes better than any stamp can, and neither costs a texture
## decision. Everything that genuinely needs authored art is listed under TEXTURES below.

const SHOCKWAVE_SHADER := "res://assets/shaders/shockwave.gdshader"
const BEAM_SHADER := "res://assets/shaders/energy_beam.gdshader"

## Drawn AFTER Sky3D's fog, which is the single reason spell effects looked washed out
## against the sky and worst of all along the horizon.
##
## Sky3D's fog is not Godot's fog. It is a full-screen quad (SkyDome._FogMeshI) with
## render_priority 100 that reads the DEPTH TEXTURE and paints atmospheric colour over
## whatever it finds. Every effect here uses `depth_draw_never` - correctly, they are
## translucent and must not occlude each other - so they write no depth, and the fog pass
## therefore reads the depth of whatever is BEHIND them. Against the sky that is the far
## plane, so the fog treats a fireball ten metres from the camera as if it were a thousand
## metres away and lays full-density haze over it. At the horizon, where the fog is
## thickest and brightest, that wipes the effect out almost completely.
##
## Sitting above the fog's own priority takes the effects out of that pass entirely. They
## are self-lit VFX that were already opted out of Godot's fog (`fog_disabled`), so this is
## the same decision applied to the fog that is actually in the scene.
const FX_RENDER_PRIORITY: int = 110

## Every texture this layer draws with, in one place, so swapping one is a one-line change
## and never a hunt through the builders.
##
## All five of the new ones are PROCEDURAL stand-ins picked off the contact sheet that
## tools/build_vfx_candidates.gd renders - the same status the two older ones have. They
## are chosen, not final: regenerate the sheet, drop a different PNG into assets/vfx/, or
## replace any of them with authored art, and only the path below changes.
##
## The one rule an authored replacement has to keep is WHITE ON TRANSPARENT. Every colour
## in this file comes from `tint_gradient`, and a texture with colour baked in cannot serve
## a white spell and a black one from the same file.
##
## An empty slot is legal and draws the untextured fallback, so a builder never silently
## substitutes a shape that was not chosen for it.
const TEXTURES := {
	"spark": "res://assets/vfx/spark_glow.png",
	"smoke": "res://assets/vfx/fire_smoke.png",
	# Rays rather than a plain dot: at the size motes are actually drawn, a soft round
	# speck is indistinguishable from `spark`, and the whole point of a second texture is
	# that it looks like something else.
	"mote": "res://assets/vfx/mote_glint.png",
	# Sharp at both ends, so it reads as ice at any rotation - which matters because the
	# particles carrying it spin.
	"shard": "res://assets/vfx/shard_diamond.png",
	# The three settle-beat marks. Dark tints for scorch and blight, pale for frost; the
	# masks themselves are white and carry only the shape.
	"decal_scorch": "res://assets/vfx/decal_scorch.png",
	"decal_frost": "res://assets/vfx/decal_frost.png",
	"decal_blight": "res://assets/vfx/decal_blight.png",
}


static func _texture(slot: String) -> Texture2D:
	var path: String = String(TEXTURES.get(slot, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## White-hot core into the caller's colour into nothing.
##
## Every effect here ramps through the SAME shape, which is what makes a blue spell and a
## green one read as the same game: the hue is the only thing that changes, and the bright
## core is what stops an additive effect looking like flat coloured jelly.
static func tint_gradient(tint: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0).lerp(tint, 0.25))
	gradient.add_point(0.25, tint)
	gradient.add_point(0.7, Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.7, 0.55))
	gradient.set_offset(3, 1.0)
	gradient.set_color(3, Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.5, 0.0))
	return gradient


static func _ramp(tint: Color) -> GradientTexture1D:
	var texture := GradientTexture1D.new()
	texture.gradient = tint_gradient(tint)
	return texture


## The same ramp with every stop's RGB scaled by its own alpha.
##
## Needed because the particle materials below blend PREMULTIPLIED, and the blend equation
## is only correct if BOTH factors that reach it are premultiplied - the texture (handled by
## _premul_texture) and the vertex colour the ramp becomes. Premultiplying only one of them
## leaves particles that keep adding light as they fade out, which shows up as bright specks
## that never quite die.
static func _premul_ramp(tint: Color) -> GradientTexture1D:
	var gradient := tint_gradient(tint)
	for index: int in gradient.get_point_count():
		var stop: Color = gradient.get_color(index)
		gradient.set_color(index, Color(stop.r * stop.a, stop.g * stop.a, stop.b * stop.a, stop.a))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Premultiplying is an image operation and spells spawn particle systems by the handful, so
## each slot is converted once and kept.
static var _premul_textures: Dictionary = {}


static func _premul_texture(slot: String) -> Texture2D:
	if _premul_textures.has(slot):
		return _premul_textures[slot]
	var result: Texture2D = null
	var source: Texture2D = _texture(slot)
	if source != null:
		var image: Image = source.get_image()
		if image != null:
			image = image.duplicate() as Image
			image.convert(Image.FORMAT_RGBA8)
			image.premultiply_alpha()
			result = ImageTexture.create_from_image(image)
	_premul_textures[slot] = result
	return result


## A particle billboard that survives a BRIGHT background.
##
## The additive version (EmberFx.particle_mesh) can only add light to what is behind it, so
## over dark ground it glows and against the sky it disappears - which is exactly what the
## effects looked like in daylight. Premultiplied alpha lets one particle both cover what is
## behind it and add light on top of that, so the same spark reads at midnight and at noon.
##
## Everything else matches EmberFx.particle_mesh, including BILLBOARD_PARTICLES with
## billboard_keep_scale, so a system can be swapped between the two without retuning.
static func premul_particle_mesh(size: float, slot: String) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)

	var material := StandardMaterial3D.new()
	material.albedo_texture = _premul_texture(slot)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Godot applies fog to a premultiplied or additive surface incorrectly - the fog colour
	# is laid over the whole quad and then blended, so the quad itself becomes visible
	# (godotengine/godot#104427, still open). These are self-lit effects that should not be
	# fogged anyway, so the safest thing is to opt out rather than to tune around it.
	material.disable_fog = true
	material.render_priority = FX_RENDER_PRIORITY
	mesh.material = material
	return mesh


static func _curve_texture(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


# --- the shapes ----------------------------------------------------------------

## A wave running outward along the ground, at the radius the spell actually used.
##
## The ring EXPANDS through a shader uniform rather than by scaling the node, which is the
## whole difference from the torus this replaces: a scaled ring gets thicker as it grows
## and reads as a balloon, while a travelling band keeps its width and reads as a front.
## It is also flat, so it hugs the ground the effect is happening on.
## `upright` turns the ground wave on its edge: a ring standing across the direction of
## travel, which is what a pressure front looks like from behind it. Used by `gust`.
static func shockwave(tint: Color, radius: float, duration: float = 0.45,
		upright: bool = false) -> MeshInstance3D:
	var wave := MeshInstance3D.new()
	wave.name = "Shockwave"
	var quad := QuadMesh.new()
	# The shader fades everything past 0.7 of the quad, so the quad is oversized to let
	# the band reach the requested radius before it goes.
	quad.size = Vector2(radius * 2.6, radius * 2.6)
	# QuadMesh already stands upright in XY; a ground wave is the one that gets laid down.
	if not upright:
		quad.orientation = PlaneMesh.FACE_Y
	wave.mesh = quad

	var material := ShaderMaterial.new()
	material.shader = load(SHOCKWAVE_SHADER) as Shader
	material.render_priority = FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("progress", 0.0)
	wave.material_override = material

	wave.tree_entered.connect(func() -> void:
		var tween: Tween = wave.create_tween()
		# Fast out of the caster and easing off as it loses energy - a front decelerating
		# is most of what sells it as one.
		tween.tween_method(
			func(value: float) -> void: material.set_shader_parameter("progress", value),
			0.0, 1.0, duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(wave.queue_free), CONNECT_ONE_SHOT)
	return wave


## A shaft of light from `origin` along `direction`.
##
## Two quads crossed at right angles rather than one: a single quad disappears edge-on,
## and billboarding a beam twists it as the camera moves. Crossed quads hold up from every
## angle for the price of one extra triangle pair.
static func beam(direction: Vector3, length: float, tint: Color, width: float = 0.9,
		duration: float = 0.28) -> Node3D:
	var root := Node3D.new()
	root.name = "Beam"

	var material := ShaderMaterial.new()
	material.shader = load(BEAM_SHADER) as Shader
	material.render_priority = FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("fade", 0.0)

	for index: int in range(2):
		var blade := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(length, width)
		# The quad's own +X is along the beam, so it is built lying along X and the root
		# is what aims it - the same split _place_in_world expects.
		quad.center_offset = Vector3(length * 0.5, 0.0, 0.0)
		blade.mesh = quad
		blade.material_override = material
		blade.rotate_object_local(Vector3.RIGHT, PI * 0.5 * float(index))
		root.add_child(blade)

	var forward: Vector3 = direction.normalized()
	root.tree_entered.connect(func() -> void:
		# Aimed once it is in the tree: look_at needs a global transform to work against.
		if absf(forward.dot(Vector3.UP)) < 0.99:
			root.look_at(root.global_position + forward, Vector3.UP)
			# look_at points -Z at the target; the quads run along +X.
			root.rotate_object_local(Vector3.UP, PI * 0.5)
		else:
			# Straight up or straight down, where look_at has no basis to work from.
			# Rotating the quads' own +X onto the world Y axis is the whole job.
			root.rotate_object_local(Vector3.BACK, PI * 0.5 * signf(forward.y))
		var tween: Tween = root.create_tween()
		tween.tween_method(
			func(value: float) -> void: material.set_shader_parameter("fade", value),
			0.0, 1.0, duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Points of light thrown out of a point. The generic sibling of EmberFx.build_sparks -
## same jagged scale curve, because a spark blinking is what separates it from a dot, but
## tinted by the caller and with no fire in it.
## `slot` is which texture the points are drawn with - "spark" for a plain point of light,
## "shard" for blue's splinters. The shape is the only thing that changes; everything about
## how they move is shared, which is what keeps a frost burst and a holy one related.
static func sparks(tint: Color, radius: float, amount: int, speed: float = 6.0,
		slot: String = "spark") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Sparks"
	particles.amount = amount
	particles.lifetime = 0.75
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.draw_pass_1 = premul_particle_mesh(0.22, slot)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.3
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = speed * 0.4
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, -5.0, 0.0)
	process.damping_min = 2.0
	process.damping_max = 6.0
	process.scale_min = 0.5
	process.scale_max = 1.2
	process.scale_curve = _curve_texture([
		Vector2(0.0, 1.0), Vector2(0.15, 0.2), Vector2(0.35, 0.9),
		Vector2(0.6, 0.25), Vector2(0.82, 0.6), Vector2(1.0, 0.0),
	])
	process.color_ramp = _premul_ramp(tint)
	particles.process_material = process
	return particles


## A blast of air driven FORWARD, for a spell that pushes rather than detonates.
##
## Deliberately not built out of `shockwave`: a ring says "this happened here, in every
## direction", and Unsummon does the opposite - it happens in a cone in front of the caster
## and nowhere behind them. A player reading a ring learns the wrong thing about what the
## spell just did and where it is safe to stand.
##
## Two layers, the same split that makes EmberFx's fire work: fast hard particles for the
## force, slow soft ones for the air it drags with it.
static func gust(length: float, tint: Color, slot: String = "shard") -> Node3D:
	var root := Node3D.new()
	root.name = "Gust"

	# The front: a ring standing across the direction of travel that both EXPANDS and moves
	# away. Together those two are what read as pressure - the particles alone read as
	# debris being thrown, which is a different event.
	var front: MeshInstance3D = shockwave(tint, length * 0.35, 0.4, true)
	root.add_child(front)

	var blast := GPUParticles3D.new()
	blast.name = "Blast"
	blast.amount = 110
	blast.lifetime = 0.45
	blast.one_shot = true
	blast.explosiveness = 0.95
	blast.local_coords = false
	# Small. At half a unit these read as ice crystals hanging in the air rather than as
	# air being displaced - the shape stops mattering once something is moving this fast,
	# and the size is what decides whether it is debris or wind.
	blast.draw_pass_1 = premul_particle_mesh(0.22, slot)
	var driven := ParticleProcessMaterial.new()
	# A narrow slab at the caster rather than a point, so the front has width from the
	# start instead of visibly fanning out of one spot.
	driven.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	driven.emission_box_extents = Vector3(0.9, 0.7, 0.15)
	driven.direction = Vector3.FORWARD
	# Tight: a gust has a direction, and 20 degrees of spread put a third of it sideways.
	driven.spread = 11.0
	driven.initial_velocity_min = length * 2.2
	driven.initial_velocity_max = length * 3.4
	# Braked hard, so the gust STOPS at about the range the push actually reaches instead
	# of streaming off across the map.
	driven.damping_min = length * 2.4
	driven.damping_max = length * 3.6
	driven.scale_min = 0.5
	driven.scale_max = 1.3
	driven.scale_curve = _curve_texture([
		Vector2(0.0, 0.3), Vector2(0.2, 1.0), Vector2(1.0, 0.0),
	])
	# Aligned to travel, so each particle reads as a streak of moving air rather than as a
	# floating shape that happens to be sliding.
	driven.particle_flag_align_y = true
	driven.color_ramp = _premul_ramp(tint)
	blast.process_material = driven
	root.add_child(blast)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 16
	dust.lifetime = 0.75
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.local_coords = false
	# Thin and wide rather than thick and round: this is the air the front drags with it,
	# and at any real opacity it stops being air and becomes a smoke bomb.
	dust.draw_pass_1 = premul_particle_mesh(1.1, "smoke")
	var drag := ParticleProcessMaterial.new()
	drag.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	drag.emission_box_extents = Vector3(0.8, 0.35, 0.15)
	drag.direction = Vector3.FORWARD
	drag.spread = 22.0
	drag.initial_velocity_min = length * 0.9
	drag.initial_velocity_max = length * 1.6
	drag.damping_min = length * 1.2
	drag.damping_max = length * 2.0
	drag.scale_min = 0.5
	drag.scale_max = 1.2
	drag.scale_curve = _curve_texture([
		Vector2(0.0, 0.35), Vector2(0.4, 1.0), Vector2(1.0, 0.2),
	])
	drag.color_ramp = _premul_ramp(Color(tint.r, tint.g, tint.b, 0.22))
	dust.process_material = drag
	root.add_child(dust)

	var flash := OmniLight3D.new()
	flash.light_color = tint
	flash.light_energy = 4.0
	flash.omni_range = length * 0.9
	flash.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(flash)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		# look_at aims -Z at the target, so forward is NEGATIVE Z in the root's own space.
		# The front travels most of the range while it expands; it is freed by its own
		# tween, so this one only has to outlive the trip.
		tween.tween_property(front, "position:z", -length * 0.75, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(flash, "light_energy", 0.0, 0.2)
		tween.tween_interval(0.9)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## The release beat, as one node: the flash, the wave and the sparks together.
##
## Callers get this rather than three separate spawns because the three have to happen on
## the SAME frame to read as one event - a light that comes up a frame after its own
## shockwave reads as two effects.
static func impact(tint: Color, radius: float, slot: String = "spark") -> Node3D:
	var root := Node3D.new()
	root.name = "SpellImpact"
	root.add_child(shockwave(tint, radius))
	root.add_child(sparks(tint, radius, 28, radius * 1.6, slot))

	var flash := OmniLight3D.new()
	flash.light_color = tint
	flash.light_energy = 5.0
	flash.omni_range = radius * 2.2
	flash.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(flash)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		# The light is the shortest-lived part by far: a flash that lingers stops being a
		# flash and starts being a lamp sitting on the ground.
		tween.tween_property(flash, "light_energy", 0.0, 0.18)
		tween.tween_interval(0.9)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## A standing vortex: something that keeps happening, rather than something that happened.
##
## Suction runs for ten to thirty seconds, which is long enough that a single ring at the
## cast frame tells the player nothing about the twenty-nine seconds that follow - they have
## to be able to see where the pull IS, the whole time it is pulling.
##
## Three parts, and the spiral is the one that matters: particles get inward acceleration
## AND tangential acceleration at once, which is what turns a pull into a swirl. Inward
## alone reads as debris falling into a hole; tangential alone reads as a carousel.
static func vortex(radius: float, tint: Color, lifetime: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Vortex"

	var swirl := GPUParticles3D.new()
	swirl.name = "Swirl"
	swirl.amount = 80
	swirl.lifetime = 2.4
	swirl.local_coords = false
	swirl.draw_pass_1 = premul_particle_mesh(0.35, "shard")
	var process := ParticleProcessMaterial.new()
	# Born at the RIM, which is the edge the player needs to read - it is the line between
	# being dragged and not being dragged.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.82
	process.emission_ring_height = 0.4
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	# Inward, hard enough that a particle crosses the whole radius inside its own lifetime.
	process.radial_accel_min = -radius * 1.6
	process.radial_accel_max = -radius * 2.4
	process.tangential_accel_min = radius * 1.2
	process.tangential_accel_max = radius * 2.0
	# Lifted as they converge, so the middle of the zone reads as a column rather than as a
	# flat disc of particles piling up at one point.
	process.gravity = Vector3(0.0, 1.6, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.1
	process.scale_curve = _curve_texture([
		Vector2(0.0, 0.2), Vector2(0.3, 1.0), Vector2(1.0, 0.1),
	])
	process.color_ramp = _premul_ramp(tint)
	swirl.process_material = process
	root.add_child(swirl)

	# The footprint, so the zone is legible from above and while standing in it.
	var mark: MeshInstance3D = ground_decal("decal_frost", Color(tint.r, tint.g, tint.b, 0.5),
		radius, lifetime)
	mark.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(mark)

	var glow := OmniLight3D.new()
	glow.light_color = tint
	glow.light_energy = 1.8
	glow.omni_range = radius * 1.5
	glow.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(glow)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		# The mark turns for as long as the zone stands. Slowly - a fast spin reads as a
		# spinning texture, where a slow one reads as something being wound in.
		tween.set_loops()
		tween.tween_property(mark, "rotation:y", TAU, 9.0).from(0.0)
		, CONNECT_ONE_SHOT)
	return root


## Where a ground effect actually belongs, given a point that might be anywhere.
##
## A decal has to be ON the ground, and the point a spell hands it usually is not: a
## fireball detonates where it STRUCK - an enemy's chest, a wall, a flying target - which
## can be metres up. Placed there, the scorch hangs in mid-air, which is worse than having
## no scorch at all because it is unmistakably a bug.
##
## Returns a full transform rather than a position: on sloped ground a flat quad laid level
## cuts through the hill it is supposed to be lying on, so the decal is tilted onto the
## surface normal as well as dropped onto it.
##
## Mask 17 is layers 1 and 5 - world geometry and environment blockers - the same pair
## Player._ground_snap uses. Enemies are deliberately not in it: a scorch mark belongs on
## the floor, not on whatever happened to be standing on it.
static func ground_transform(world: Node3D, point: Vector3, lift: float = 0.06,
		drop: float = 30.0) -> Transform3D:
	var normal: Vector3 = Vector3.UP
	var origin: Vector3 = point
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3(0.0, 1.0, 0.0), point - Vector3(0.0, drop, 0.0), 17)
	var hit: Dictionary = space.intersect_ray(query)
	if hit:
		origin = hit.position
		normal = (hit.normal as Vector3).normalized()
	# Nothing underneath - a shot off the edge of the map - is left where it was rather
	# than dropped to the world origin.
	var basis := Basis.IDENTITY
	if normal.dot(Vector3.UP) < 0.999:
		var reference: Vector3 = Vector3.FORWARD
		if absf(normal.dot(reference)) > 0.9:
			reference = Vector3.RIGHT
		var right: Vector3 = reference.cross(normal).normalized()
		basis = Basis(right, normal, normal.cross(right).normalized())
	return Transform3D(basis, origin + normal * lift)


## What a spell LEAVES: the settle beat from docs/SPELL_VFX_PLAN.md.
##
## The cheapest large win in the plan, and the one most often skipped. A blast that leaves
## a scorch for three seconds reads as having happened TO the world; the same blast with
## twice the particles and nothing left behind reads as having happened in front of it.
##
## Blended normally rather than additively, unlike everything else here - a mark on the
## ground is pigment, not light, and an additive scorch would brighten the very ground it
## is supposed to have burned. `tint` therefore carries the mark's actual colour: near-black
## for scorch, pale for frost, dead violet for blight.
static func ground_decal(slot: String, tint: Color, radius: float,
		hold: float = 3.0) -> MeshInstance3D:
	var decal := MeshInstance3D.new()
	decal.name = "SpellDecal"
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	decal.mesh = quad

	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture(slot)
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# It sits a few centimetres above the ground and must not fight it for depth, nor
	# occlude the effects that land on top of it.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	# A decal lies on the ground, so it is only ever seen against terrain - but the same
	# fog pass still covers it, and a scorch mark fading into haze at ten metres is the
	# same bug in a quieter place.
	material.render_priority = FX_RENDER_PRIORITY
	decal.material_override = material

	decal.tree_entered.connect(func() -> void:
		var tween: Tween = decal.create_tween()
		# On fast, off slow: the mark is made in the same instant as the blast, then
		# weathers away over seconds.
		tween.tween_property(material, "albedo_color:a", tint.a, 0.08)
		tween.tween_interval(hold)
		tween.tween_property(material, "albedo_color:a", 0.0, hold * 0.6)
		tween.tween_callback(decal.queue_free), CONNECT_ONE_SHOT)
	return decal


## What a spell looks like ON the caster, for the ones with nowhere else to happen: a
## self-buff, a ward, a shout. The light, plus motes drawn inward to it, so a buff reads as
## something gathering rather than as the screen briefly changing brightness.
static func cast_glow(tint: Color, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CastGlow"

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 4.0
	light.omni_range = radius * 2.0
	light.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(light)

	var motes := GPUParticles3D.new()
	motes.amount = 24
	motes.lifetime = 0.55
	motes.one_shot = true
	motes.explosiveness = 0.7
	motes.local_coords = true
	motes.draw_pass_1 = premul_particle_mesh(0.16, "mote")
	var process := ParticleProcessMaterial.new()
	# Born on a ring around the caster and pulled INWARD - the direction is the whole
	# point, and it is the one thing that separates a buff from an explosion.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.85
	process.emission_ring_height = 1.6
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.4
	process.radial_accel_min = -radius * 4.0
	process.radial_accel_max = -radius * 6.0
	process.scale_curve = _curve_texture([
		Vector2(0.0, 0.2), Vector2(0.45, 1.0), Vector2(1.0, 0.0),
	])
	process.color_ramp = _premul_ramp(tint)
	motes.process_material = process
	motes.position = Vector3(0.0, 0.4, 0.0)
	root.add_child(motes)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_property(light, "light_energy", 0.0, 0.5)
		tween.tween_interval(0.4)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root
