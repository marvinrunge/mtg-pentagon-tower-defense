extends RefCounted
class_name ExplosionFx
## Explosions built in layers, the way authored VFX are: one bright core, a body with real
## shape, flame and smoke that move, debris, and a mark left behind. A sibling of EmberFx and
## SpellFx - static builders that return a node for the caller to place.
##
## The Fireball's detonation used to be a one-shot ember burst topped with a translucent
## CSGSphere3D: a flat orange ball with visible facets, scaling up and fading, which hid the
## fire inside it. Each layer here is one of the four beats in docs/SPELL_VFX_PLAN.md:
##
##   release  a white flash for a few frames, and a light that falls across everything near
##   body     the fireball itself - a sphere that billows, burns from white-hot to soot and
##            erodes away (assets/shaders/explosion_volume.gdshader) - wrapped in flame puffs
##            from a flipbook, with sparks thrown out of it
##   settle   smoke that rolls up and lingers after the fire is gone, and a scorch projected
##            onto the ground whose embers cool while the mark stays
##
## Textures are the flipbooks tools/build_vfx_flipbooks.gd generates - white on transparent,
## coloured by each particle system's gradient, replaceable in place by authored sheets.

const VOLUME_SHADER: Shader = preload("res://assets/shaders/explosion_volume.gdshader")
const DECAL_SHADER: Shader = preload("res://assets/shaders/projected_decal.gdshader")
const FIRE_FLIPBOOK := "res://assets/vfx/flipbook_fire.png"
const SMOKE_FLIPBOOK := "res://assets/vfx/flipbook_smoke.png"
const FLASH_TEXTURE := "res://assets/vfx/spark_glow.png"
const SCORCH_TEXTURE := "res://assets/vfx/decal_scorch.png"
const FLIPBOOK_GRID := 4
## Seconds the fireball body lives; everything else is timed against it.
const BODY_SECONDS := 1.1
## Seconds before the whole explosion frees itself - after the last smoke has gone.
const TOTAL_SECONDS := 4.2


## A fire explosion of `radius` - the Fireball's, and the template for every other one.
static func fireball(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FireballExplosion"

	var body := _build_body()
	body.scale = Vector3.ONE * radius * 0.3
	root.add_child(body)
	var body_material: ShaderMaterial = body.material_override

	var flash := _build_flash()
	root.add_child(flash)
	var flash_material: StandardMaterial3D = flash.material_override

	var flames := _build_flames(radius)
	root.add_child(flames)
	var smoke := _build_smoke(radius)
	root.add_child(smoke)

	var sparks: GPUParticles3D = EmberFx.build_sparks(radius * 0.3, 40)
	sparks.lifetime = 0.9
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	var spark_process: ParticleProcessMaterial = sparks.process_material
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = radius * 1.8
	spark_process.initial_velocity_max = radius * 3.8
	spark_process.gravity = Vector3(0.0, -4.0, 0.0)
	root.add_child(sparks)

	var light: OmniLight3D = EmberFx.build_fire_light(radius * 4.0, 8.0)
	root.add_child(light)

	# Created on tree_entered: every caller builds the explosion and THEN adds it, and a tween
	# made outside the tree fails and returns nothing - which once left bursts with no fade
	# and nothing to free them, accumulating for the life of the run.
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.set_parallel(true)
		# The body bursts out fast and then barely grows - a blast front decelerating.
		tween.tween_property(body, "scale", Vector3.ONE * radius * 0.95, 0.22) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(body, "scale", Vector3.ONE * radius * 1.2, BODY_SECONDS - 0.22).set_delay(0.22)
		tween.tween_method(func(v: float) -> void: body_material.set_shader_parameter("age", v), 0.0, 1.0, BODY_SECONDS)
		tween.tween_property(flash, "scale", Vector3.ONE * radius * 2.2, 0.05)
		tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.12)
		tween.tween_property(light, "light_energy", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Smoke only once there is fire for it to come out of.
		tween.tween_callback(func() -> void: smoke.emitting = true).set_delay(0.16)
		tween.tween_callback(root.queue_free).set_delay(TOTAL_SECONDS), CONNECT_ONE_SHOT)
	return root


## The scorch an explosion leaves: projected onto the ground, embers glowing in it that cool
## over a few seconds, then the mark itself weathering away. Placed by the caller on the
## ground point under the blast (SpellFx.ground_transform's origin).
static func scorch(radius: float, hold: float = 5.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Scorch"
	var box := BoxMesh.new()
	box.size = Vector3(radius * 2.0, AttackIndicator.PROJECT_UP + AttackIndicator.PROJECT_DOWN, radius * 2.0)
	var volume := MeshInstance3D.new()
	volume.mesh = box
	volume.position.y = (AttackIndicator.PROJECT_UP - AttackIndicator.PROJECT_DOWN) * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = DECAL_SHADER
	material.set_shader_parameter("mark", _texture(SCORCH_TEXTURE))
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("seed", randf() * 100.0)
	material.set_shader_parameter("fade", 0.0)
	material.set_shader_parameter("embers", 1.0)
	material.set_shader_parameter("projection_offset", volume.position)
	material.set_shader_parameter("projection_up", AttackIndicator.PROJECT_UP)
	material.set_shader_parameter("projection_down", AttackIndicator.PROJECT_DOWN)
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	volume.material_override = material
	root.add_child(volume)
	# A random turn, so two scorches side by side are not the same stamp.
	root.rotation.y = randf() * TAU

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		var set_param := func(key: String) -> Callable:
			return func(v: float) -> void: material.set_shader_parameter(key, v)
		# On fast, embers cooling over seconds, the mark weathering away slowest of all.
		tween.tween_method(set_param.call("fade"), 0.0, 1.0, 0.06)
		tween.parallel().tween_method(set_param.call("embers"), 1.0, 0.0, 2.6).set_delay(0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_interval(hold)
		tween.tween_method(set_param.call("fade"), 1.0, 0.0, hold * 0.6)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- layers ------------------------------------------------------------------------------

static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("VFX texture '%s' is missing" % path)
		return null
	return load(path) as Texture2D


static func _build_body() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# Enough vertices for the billows to read as lumps, not as a faceted ball.
	sphere.radial_segments = 48
	sphere.rings = 24
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = sphere
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = VOLUME_SHADER
	material.set_shader_parameter("seed", randf() * 50.0)
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	body.material_override = material
	return body


## The release beat: a hot white flash that is gone in a fifth of a second.
static func _build_flash() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture(FLASH_TEXTURE)
	# Far above 1.0, so the game's bloom catches it - the one bright core the effect has.
	material.albedo_color = Color(4.0, 3.2, 2.2, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.render_priority = SpellFx.FX_RENDER_PRIORITY + 1
	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	flash.mesh = quad
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.scale = Vector3.ONE * 0.3
	return flash


## A particle system drawing a 4 x 4 flipbook over each particle's life.
## A one-shot particle system that plays a 4x4 flipbook once over each particle's life -
## shared with the zones (DoTZone) and anything else that wants fire or smoke that moves.
static func flipbook_particles(texture_path: String, size: float, amount: int, lifetime: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture(texture_path)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.particles_anim_h_frames = FLIPBOOK_GRID
	material.particles_anim_v_frames = FLIPBOOK_GRID
	material.particles_anim_loop = false
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	quad.material = material
	particles.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	# One play of the flipbook over the particle's life, from a slightly different frame each.
	process.anim_speed_min = 1.0
	process.anim_speed_max = 1.0
	process.anim_offset_max = 0.12
	process.angle_min = -180.0
	process.angle_max = 180.0
	particles.process_material = process
	return particles


static func _build_flames(radius: float) -> GPUParticles3D:
	var flames := flipbook_particles(FIRE_FLIPBOOK, radius * 0.95, 18, 0.8)
	flames.explosiveness = 0.95
	flames.emitting = true
	var process: ParticleProcessMaterial = flames.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.3
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = radius * 1.1
	process.initial_velocity_max = radius * 2.6
	process.damping_min = radius * 2.0
	process.damping_max = radius * 3.5
	process.gravity = Vector3(0.0, 2.2, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.25
	process.scale_curve = EmberFx._curve_texture([Vector2(0.0, 0.45), Vector2(0.4, 1.0), Vector2(1.0, 1.15)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = EmberFx.fire_gradient()
	process.color_ramp = ramp
	return flames


## The settle beat: smoke rolling up out of the fire and hanging there after it has gone.
static func _build_smoke(radius: float) -> GPUParticles3D:
	var smoke := flipbook_particles(SMOKE_FLIPBOOK, radius * 1.9, 16, 3.2)
	smoke.explosiveness = 0.8
	smoke.emitting = false
	var process: ParticleProcessMaterial = smoke.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.5
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.4
	process.damping_min = 0.4
	process.damping_max = 0.9
	process.gravity = Vector3(0.0, 0.55, 0.0)
	process.angular_velocity_min = -12.0
	process.angular_velocity_max = 12.0
	process.scale_min = 0.7
	process.scale_max = 1.1
	process.scale_curve = EmberFx._curve_texture([Vector2(0.0, 0.5), Vector2(1.0, 1.7)])
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	# Born warm and dark out of the fire, cooling to a lighter ash grey as it thins - a dark
	# brown that stays dark reads as dirt thrown up rather than as smoke.
	gradient.set_color(0, Color(0.3, 0.2, 0.15, 0.0))
	gradient.add_point(0.08, Color(0.28, 0.24, 0.21, 0.85))
	gradient.add_point(0.5, Color(0.4, 0.38, 0.36, 0.6))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)
	gradient.set_color(gradient.get_point_count() - 1, Color(0.46, 0.45, 0.44, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	return smoke
