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
##   * a builder returns a node; the caller places it (see ExplosionFx.fireball)
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
const SHOCKWAVE_GROUND_SHADER := "res://assets/shaders/shockwave_ground.gdshader"
const SHOCKWAVE_WALL_SHADER := "res://assets/shaders/shockwave_wall.gdshader"
const BEAM_SHADER := "res://assets/shaders/energy_beam.gdshader"
const HEAT_HAZE_SHADER := "res://assets/shaders/heat_haze.gdshader"

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

## Air shimmer goes the other way: BELOW the fog and every other effect. It redraws the
## screen behind it, and the screen texture is copied before any transparent pass - so
## drawn after a flame it would paint the flame over with the ground behind it, and drawn
## after the fog it would paint over the fog with unfogged ground. Before both, the fog
## lands on it like on anything else and the effects draw over it.
const HAZE_RENDER_PRIORITY: int = 90

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
	# Kenney's Particle Pack (CC0), trace_04: a streak with a hot head thinning into a tail.
	# The tail behind anything falling or flying fast - see `tail_mesh`.
	"trail": "res://assets/vfx/trail_trace.png",
	# Kenney's spark_05: one jagged arc of lightning, top to bottom.
	"arc": "res://assets/vfx/lightning_arc.png",
	# Kenney's twirl_03: a curl of wind, bright along its leading edge. Suction's vortex.
	"twirl": "res://assets/vfx/swirl_twirl.png",
	# Kenney's dirt_01 / dirt_02: a scatter of earth clods. Pigment, tinted dark - see
	# SpellVisuals.dirt_burst.
	"dirt": "res://assets/vfx/dirt_clods_01.png",
	"dirt_fine": "res://assets/vfx/dirt_clods_02.png",
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


## A streak of light for particles that fly fast: two quads crossed along the particle's Y,
## so with `particle_flag_align_y` it lies along the travel and reads from any side.
##
## Not a billboard: a billboarded particle keeps its Y pointing up the SCREEN whatever
## align_y says, which drew every gust streak and skidding spark as a vertical tick.
static func streak_mesh(width: float, length: float, slot: String = "spark") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = length * 0.5
	var w: float = width * 0.5
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var corners: Array = [
			[-side * w + Vector3.DOWN * h, Vector2(0.0, 1.0)], [side * w + Vector3.DOWN * h, Vector2(1.0, 1.0)],
			[side * w + Vector3.UP * h, Vector2(1.0, 0.0)], [-side * w + Vector3.UP * h, Vector2(0.0, 0.0)],
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.set_uv(corners[index][1])
			st.add_vertex(corners[index][0])
	var mesh: ArrayMesh = st.commit()
	var material := (premul_particle_mesh(width, slot).material as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


## A tail for a fast particle: `streak_mesh` shifted to hang BEHIND the particle, so with
## `particle_flag_align_y` it trails along the path the particle came from. Meant as a
## second draw pass under whatever the particle itself is drawn as - the ball of fire keeps
## its own look and gains a direction.
##
## Premultiplied and tinted by `tint` times the particle's own colour ramp, so the tail cools
## with the particle it belongs to. `tint` may go above 1 for a hot tail that blooms.
static func tail_mesh(width: float, length: float, tint: Color, slot: String = "trail") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(streak_mesh(width, length, slot), 0)
	var arrays: Array = st.commit_to_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# The particle's +Y points along its travel, so the tail goes the other way. Most of
	# it, not all: a sliver ahead of the centre runs the tail into the ball, not off its back.
	for index: int in vertices.size():
		vertices[index].y -= length * 0.45
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _premul_texture(slot)
	material.albedo_color = tint
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Premultiplied, not additive: additive orange over a blue sky comes out PINK, which is
	# what the first version of these tails looked like at noon.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_fog = true
	material.render_priority = FX_RENDER_PRIORITY
	mesh.surface_set_material(0, material)
	return mesh


static func _curve_texture(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


# --- the shapes ----------------------------------------------------------------

## A front of force running outward along the ground, at the radius the spell actually used.
##
## Two layers: the wave on the ground itself (shockwave_ground.gdshader, projected onto the
## real surface so it rolls over slopes), and a low wall of shoved air riding on its edge
## (shockwave_wall.gdshader) that gives it height from any camera angle. Both are keyed to
## one `progress`, tweened fast out of the centre and easing off - a front losing energy.
##
## The edge is a fixed width in metres, not a share of the radius: the old flat ring's band
## grew with it, so a Wrath of God front was a two-metre glowing tube.
##
## `arc_half` limits the wave to a sector round the node's -Z, for a push that goes one way
## (Unsummon); PI is the full circle. A wave started well above the ground - a hit on an
## enemy's chest - has no ground to run along and stays a ring in the air (_air_ring).
static func shockwave(tint: Color, radius: float, duration: float = 0.45,
		arc_half: float = PI, wall_height: float = -1.0, on_ground: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Shockwave"
	# Deferred one frame: callers place the node AFTER add_child, so inside tree_entered it
	# is still at the origin and the ground check would test the wrong spot.
	root.tree_entered.connect(func() -> void:
		(func() -> void:
			if not is_instance_valid(root):
				return
			if on_ground:
				_start_wave(root, tint, radius, duration, arc_half, wall_height)
			else:
				root.add_child(_air_ring(tint, radius, duration))
				root.get_tree().create_timer(duration + 0.1).timeout.connect(root.queue_free)).call_deferred(),
		CONNECT_ONE_SHOT)
	return root


## How far above the ground a wave may start and still run along it. Gusts are spawned at
## chest height on purpose (their particles fly there), so this is generous.
const GROUND_WAVE_REACH := 1.4


static func _start_wave(root: Node3D, tint: Color, radius: float, duration: float,
		arc_half: float, wall_height: float) -> void:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		root.global_position + Vector3(0.0, 0.3, 0.0),
		root.global_position - Vector3(0.0, GROUND_WAVE_REACH, 0.0), 17)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		root.add_child(_air_ring(tint, radius, duration))
		root.get_tree().create_timer(duration + 0.1).timeout.connect(root.queue_free)
		return
	# The wave sits ON the ground under the point, however high above it the point was.
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = hit["position"]

	var ground := ShaderMaterial.new()
	ground.shader = load(SHOCKWAVE_GROUND_SHADER) as Shader
	ground.set_shader_parameter("tint", tint)
	ground.set_shader_parameter("radius", radius)
	ground.set_shader_parameter("edge_width", clampf(radius * 0.05, 0.2, 0.55))
	ground.set_shader_parameter("wake_length", clampf(radius * 0.4, 0.8, 4.0))
	ground.set_shader_parameter("arc_half", arc_half)
	ground.set_shader_parameter("edge_strength", 0.35 if wall_height > 0.0 else 1.0)
	ground.set_shader_parameter("seed", randf() * 100.0)
	holder.add_child(SpellVisuals.projected_volume(radius * 1.08, ground,
		clampf(radius * 0.3, 0.5, 3.0), clampf(radius * 0.5, 1.0, 6.0)))

	var height: float = wall_height if wall_height > 0.0 else clampf(radius * 0.16, 0.45, 1.6)
	# A wall asked for by height is the point of the effect (a gust's front) and keeps most of
	# it; a ground wave's wall sinks as the wave runs out of strength.
	var settle: float = 0.7 if wall_height > 0.0 else 0.35
	var wall := MeshInstance3D.new()
	var span: float = minf(arc_half * 2.0, TAU)
	wall.mesh = _arc_wall_mesh(span)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var air := ShaderMaterial.new()
	air.shader = load(SHOCKWAVE_WALL_SHADER) as Shader
	air.render_priority = FX_RENDER_PRIORITY
	air.set_shader_parameter("tint", tint)
	air.set_shader_parameter("arc_fraction", span / TAU)
	air.set_shader_parameter("streak_cells", clampf(radius * span * 1.4, 6.0, 90.0))
	air.set_shader_parameter("seed", randf() * 100.0)
	wall.material_override = air
	wall.scale = Vector3(0.05, height, 0.05)
	holder.add_child(wall)
	# The air itself rippling with the front, a little taller than the visible wall: it is
	# what makes a wave read as force rather than as a ring of light.
	var ripple: MeshInstance3D = null
	var ripple_material: ShaderMaterial = null
	var ripple_height: float = height * 1.4 + 0.4
	if haze_supported():
		ripple = _haze_wall(span, 0.03 if wall_height > 0.0 else 0.022)
		ripple_material = ripple.material_override as ShaderMaterial
		ripple.scale = Vector3(0.05, ripple_height, 0.05)
		holder.add_child(ripple)

	holder.add_child(_edge_sparks(tint, radius, duration, arc_half))

	var tween: Tween = root.create_tween()
	tween.tween_method(func(t: float) -> void:
		ground.set_shader_parameter("progress", t)
		var r: float = maxf(t * radius, 0.05)
		wall.scale = Vector3(r, height * lerpf(1.0, settle, t), r)
		if ripple != null:
			ripple.scale = Vector3(r * 1.02, ripple_height * lerpf(1.0, settle, t), r * 1.02)
			ripple_material.set_shader_parameter("fade", 1.0 - smoothstep(0.6, 1.0, t))
		air.set_shader_parameter("fade", 1.0 - smoothstep(0.45, 1.0, t)),
		0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float) -> void: ground.set_shader_parameter("fade", v), 1.0, 0.0, 0.15)
	tween.tween_callback(root.queue_free)


## Sparks skidding along the ground with the front - fast out of the centre and braked to a
## stop at about the wave's radius, the way the wave itself eases off. Streaked along their
## travel, so they read as grit thrown by the wave rather than as floating points.
static func _edge_sparks(tint: Color, radius: float, duration: float, arc_half: float) -> GPUParticles3D:
	var sparks := GPUParticles3D.new()
	sparks.name = "EdgeSparks"
	sparks.amount = clampi(int(radius * 10.0 * arc_half / PI), 10, 90)
	sparks.lifetime = duration * 1.3
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	sparks.draw_pass_1 = streak_mesh(0.14, 1.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3.FORWARD
	process.spread = rad_to_deg(arc_half) * 0.9
	process.flatness = 1.0
	# Out to the radius in about the wave's own time: v0 = 2r/T, braked by v0/T.
	var speed: float = 2.0 * radius / maxf(duration, 0.05)
	process.initial_velocity_min = speed * 0.75
	process.initial_velocity_max = speed
	process.damping_min = speed / duration
	process.damping_max = speed / duration
	process.particle_flag_align_y = true
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.scale_curve = _curve_texture([Vector2(0.0, 1.0), Vector2(0.7, 0.6), Vector2(1.0, 0.0)])
	process.color_ramp = _premul_ramp(tint)
	sparks.process_material = process
	sparks.position.y = 0.12
	return sparks


## An open wall round the origin: radius 1, height 1, `span` radians wide and centred on -Z.
## UV.x runs along it, UV.y up it. Normals point outward.
static func _arc_wall_mesh(span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = maxi(8, int(span / TAU * 64.0))
	for i: int in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var a0: float = -span * 0.5 + span * t0
		var a1: float = -span * 0.5 + span * t1
		# Angle measured from -Z, so the middle of the arc faces the node's forward.
		var d0 := Vector3(sin(a0), 0.0, -cos(a0))
		var d1 := Vector3(sin(a1), 0.0, -cos(a1))
		var quad: Array = [
			[d0, Vector2(t0, 0.0), d0], [d1, Vector2(t1, 0.0), d1], [d1 + Vector3.UP, Vector2(t1, 1.0), d1],
			[d0, Vector2(t0, 0.0), d0], [d1 + Vector3.UP, Vector2(t1, 1.0), d1], [d0 + Vector3.UP, Vector2(t0, 1.0), d0],
		]
		for v: Array in quad:
			st.set_uv(v[1])
			st.set_normal(v[2])
			st.add_vertex(v[0])
	return st.commit()


## The old flat ring, for a wave with no ground under it: a band expanding on a quad laid
## level, thin so it reads as a ripple in the air rather than a disc.
static func _air_ring(tint: Color, radius: float, duration: float) -> MeshInstance3D:
	var wave := MeshInstance3D.new()
	wave.name = "AirRing"
	var quad := QuadMesh.new()
	# The shader fades everything past 0.7 of the quad, so the quad is oversized to let
	# the band reach the requested radius before it goes.
	quad.size = Vector2(radius * 2.6, radius * 2.6)
	quad.orientation = PlaneMesh.FACE_Y
	wave.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = load(SHOCKWAVE_SHADER) as Shader
	material.render_priority = FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("thickness", 0.1)
	wave.material_override = material
	wave.tree_entered.connect(func() -> void:
		var tween: Tween = wave.create_tween()
		tween.tween_method(
			func(value: float) -> void: material.set_shader_parameter("progress", value),
			0.0, 1.0, duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(wave.queue_free), CONNECT_ONE_SHOT)
	return wave


## Whether air shimmer is drawn at all. Not on the Compatibility renderer: there, with glow
## off (the LOW preset turns both on together), the screen texture it re-draws is already
## tone-mapped, so the shimmer showed as pale patches instead of bent air - and LOW is for
## the machines that can least afford the extra screen copy anyway.
static func haze_supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## The material every air shimmer draws with (heat_haze.gdshader). `billboard` for particle
## quads; off for a mesh that is already shaped, like the arc wall of a shockwave.
static func haze_material(strength: float, billboard: bool, scale: float = 4.0,
		speed: float = 1.2, drift: Vector2 = Vector2(0.0, 1.0)) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(HEAT_HAZE_SHADER) as Shader
	material.render_priority = HAZE_RENDER_PRIORITY
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("billboard", billboard)
	material.set_shader_parameter("scale", scale)
	material.set_shader_parameter("speed", speed)
	material.set_shader_parameter("drift", drift)
	return material


## Heat rising off fire: soft quads of shimmering air drifting up out of a box `extents` big
## round the node, each `size` across, swelling as it climbs and fading out. Keeps running
## until `emitting` is turned off, or with `burst` once, all at the start - the heat a blast
## throws off.
##
## Draws nothing of its own - only bends what is behind it - so it can be laid generously
## over any fire without changing its colour.
static func heat_haze(extents: Vector3, size: float, amount: int, lifetime: float = 1.1,
		rise: float = 1.6, strength: float = 0.012, burst: bool = false) -> Node3D:
	if not haze_supported():
		var nothing := Node3D.new()
		nothing.name = "HeatHaze"
		return nothing
	var haze := GPUParticles3D.new()
	haze.name = "HeatHaze"
	haze.amount = amount
	haze.lifetime = lifetime
	haze.local_coords = false
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if burst:
		haze.one_shot = true
		haze.explosiveness = 0.7
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.surface_set_material(0, haze_material(strength, true))
	haze.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = rise * 0.6
	process.initial_velocity_max = rise
	# Hot air climbs: without this the default gravity pulled every quad back into the ground.
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.scale_min = 0.8
	process.scale_max = 1.2
	process.scale_curve = _curve_texture([Vector2(0.0, 0.6), Vector2(1.0, 1.4)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.25, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	haze.process_material = process
	# Generous bounds: the quads climb well out of the box, and a culled haze pops.
	haze.visibility_aabb = AABB(-extents - Vector3(size, size, size),
		(extents + Vector3(size, size, size)) * 2.0 + Vector3(0.0, rise * lifetime * 1.5, 0.0))
	return haze


## A shockwave's ripple in the air: the arc wall of `_arc_wall_mesh`, bending what is behind
## it instead of drawing on it. Scaled and faded by the wave's own tween.
static func _haze_wall(span: float, strength: float) -> MeshInstance3D:
	var wall := MeshInstance3D.new()
	wall.name = "HazeWall"
	wall.mesh = _arc_wall_mesh(span)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fine and fast, streaming outward along the wall rather than up it.
	var material := haze_material(strength, false, 9.0, 1.6, Vector2(0.4, 1.0))
	material.set_shader_parameter("arc_fraction", span / TAU)
	wall.material_override = material
	return wall


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
static func gust(length: float, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Gust"

	# The front: the shockwave held to the cone the push actually covers, its wall of air
	# taller than a ground wave's - this is the thing doing the shoving. A ring standing
	# across the path used to stand in for it, and read as a white arch.
	var front: Node3D = shockwave(tint, length, 0.42, deg_to_rad(52.0), 1.9)
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
	# Long thin streaks rather than shards: at this speed what reads as wind is a
	# line of motion, and a shard sliding along only reads as a shard.
	blast.draw_pass_1 = streak_mesh(0.09, 1.2)
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
		# The front is freed by its own tween, so this one only has to outlive the trip.
		tween.tween_property(flash, "light_energy", 0.0, 0.2)
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
	# A small impact is a hit on something - a chest, a shield - and its ring belongs in the
	# air where the hit happened; only a blast big enough to be about the ground runs along it.
	root.add_child(shockwave(tint, radius, 0.45, PI, -1.0, radius >= 1.5))
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

	# Curls of wind a couple of metres across, wound round and in from the rim. Small ice
	# shards used to carry this alone, and at a third of a metre on a twelve-metre zone they
	# read as dust rather than as air being dragged.
	var curl: float = clampf(radius * 0.4, 2.4, 5.0)
	var swirl: GPUParticles3D = _vortex_layer("Swirl", radius, 40, 2.6, premul_particle_mesh(curl, "twirl"),
		_premul_ramp(tint))
	var swirl_process: ParticleProcessMaterial = swirl.process_material
	# Each curl turns WITH the vortex, so its bright edge leads the way it is travelling.
	swirl_process.angle_min = 0.0
	swirl_process.angle_max = 360.0
	swirl_process.angular_velocity_min = -160.0
	swirl_process.angular_velocity_max = -90.0
	swirl_process.scale_curve = _curve_texture([
		Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.4),
	])
	root.add_child(swirl)

	# A low mist dragged round with it, so the ground inside reads as stirred-up air.
	var mist_gradient := Gradient.new()
	mist_gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	mist_gradient.add_point(0.3, Color(tint.r * 0.32, tint.g * 0.32, tint.b * 0.32, 0.32))
	mist_gradient.set_color(mist_gradient.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var mist_ramp := GradientTexture1D.new()
	mist_ramp.gradient = mist_gradient
	var mist: GPUParticles3D = _vortex_layer("Mist", radius, 14, 3.0,
		premul_particle_mesh(clampf(radius * 0.4, 2.2, 5.0), "smoke"), mist_ramp)
	var mist_process: ParticleProcessMaterial = mist.process_material
	mist_process.gravity = Vector3(0.0, 0.3, 0.0)
	mist_process.angle_min = 0.0
	mist_process.angle_max = 360.0
	mist_process.angular_velocity_min = -60.0
	mist_process.angular_velocity_max = -30.0
	root.add_child(mist)

	# Ice glinting in it - fewer and bigger than before, the detail rather than the body.
	var shards: GPUParticles3D = _vortex_layer("Shards", radius, 30, 2.4, premul_particle_mesh(0.5, "shard"),
		_premul_ramp(tint))
	root.add_child(shards)

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


## One layer of `vortex`: particles born at the rim of `radius` and spiralled into a column
## in its middle - inward hard enough to cross the whole radius in their own lifetime,
## round fast enough to read as a whirl, and lifted as they converge.
static func _vortex_layer(layer_name: String, radius: float, amount: int, lifetime: float,
		mesh: Mesh, ramp: Texture2D) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = layer_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.draw_pass_1 = mesh
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
	process.color_ramp = ramp
	particles.process_material = process
	return particles


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
