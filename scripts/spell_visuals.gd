class_name SpellVisuals
extends RefCounted
## Each spell's own look - the signature effect a player recognises it by.
##
## SpellFx and EmberFx hold the generic shapes (a shockwave, a beam, sparks, a fire body),
## and twenty-five spells drawn only with those read as five colours of the same ring. This
## file is the layer above: one builder per spell, made of the shared shapes plus the pieces
## below that only make sense as a set - magic circles in each colour's dialect, columns of
## light, shield domes, ground projected marks.
##
## It follows SpellFx's rules: builders return nodes, the caller places them, anything
## one-shot frees itself from a tween started on `tree_entered`. Colour still comes from the
## five dialect constants in Player, so the palette stays one rule.
##
## Spells reach it through NetFx.spell, which sends only the spell id and a few numbers and
## lets every peer build the effect locally - see `play`.

const MAGIC_CIRCLE_SHADER: Shader = preload("res://assets/shaders/magic_circle.gdshader")
const LIGHT_PILLAR_SHADER: Shader = preload("res://assets/shaders/light_pillar.gdshader")
const SHIELD_DOME_SHADER: Shader = preload("res://assets/shaders/shield_dome.gdshader")
const GROUND_CRACKS_SHADER: Shader = preload("res://assets/shaders/ground_cracks.gdshader")
const GROUND_SLASH_SHADER: Shader = preload("res://assets/shaders/ground_slash.gdshader")
const VOID_BLADE_SHADER: Shader = preload("res://assets/shaders/void_blade.gdshader")
const FLAME_JET_SHADER: Shader = preload("res://assets/shaders/flame_jet.gdshader")

## The rune figure each colour draws in its circles (magic_circle.gdshader's `pattern`).
const CIRCLE_PATTERN: Dictionary = {"white": 0, "blue": 1, "black": 2, "red": 3, "green": 4}
## Shield dome patterns (shield_dome.gdshader).
const DOME_HEX := 0
const DOME_RUNES := 1
const DOME_BARK := 2
## How tall a shield dome stands: over the head of a player (whose capsule is 1.9) with room
## to spare, so the whole character is inside it rather than poking out of its top.
const DOME_HEIGHT := 2.4
## Green's earth end: dust, bark, thrown rock.
const EARTH := Color(0.52, 0.4, 0.22)
## Black's smoke: near-black with violet in it, the colour that eats light.
const VOID_SMOKE := Color(0.1, 0.04, 0.14)
## Red's circles: deeper than FX_RED, whose orange turns gold once it glows.
const RED_CIRCLE := Color(1.0, 0.3, 0.08)
## Lightning: blue-white, hotter than any fire.
const LIGHTNING := Color(0.75, 0.88, 1.0)
## White's light is gold, not white: Player.FX_WHITE is a warm ivory that reads as plain
## white once it glows, which is the one thing a white spell must not look like - the sky.
const WHITE_GOLD := Color(1.0, 0.78, 0.36)


# --- entry point ----------------------------------------------------------------

## Builds spell `payload["spell"]`'s effect into `scene`. `owner` is the caster's avatar on
## this machine, or null when it has not been built here yet - effects that ride on the
## caster are then dropped rather than left floating where they were cast.
##
## payload: spell (id), at (where), size (the radius or length the spell used), dir (aim,
## may be zero), count (a small integer some spells need, e.g. rank).
static func play(scene: Node, payload: Dictionary, owner: Node3D) -> void:
	var at: Vector3 = payload.get("at", Vector3.ZERO)
	var size: float = float(payload.get("size", 1.0))
	match String(payload.get("spell", "")):
		"white_1":
			_on_ground(scene, magic_circle("white", WHITE_GOLD, 1.4, 0.7, 0.18), at)
			_on_owner(owner, light_pillar(WHITE_GOLD, 0.5, 3.2, 0.5, 1.4))
			_on_owner(owner, rising_motes(Player.FX_WHITE, 0.7, 26, 0.9))
			_on_owner(owner, SpellFx.cast_glow(Player.FX_WHITE, 2.2))
		"white_2":
			_on_ground(scene, magic_circle("white", WHITE_GOLD, size, 1.0, 0.3), at)
			_on_owner(owner, SpellFx.cast_glow(Player.FX_WHITE, 2.0))
		"white_2_ally":
			_on_owner(owner, shield_dome(WHITE_GOLD, 1.3, 1.1, DOME_HEX), at)
		"white_3":
			_on_ground(scene, magic_circle("white", WHITE_GOLD, 1.6, 0.6, 0.15), at)
			_on_owner(owner, shield_dome(WHITE_GOLD, 1.4, 1.0, DOME_RUNES, DOME_HEIGHT + 0.1))
			_on_owner(owner, SpellFx.cast_glow(Player.FX_WHITE, 2.4))
		"white_4":
			_on_ground(scene, wrath_of_god(size), at)
		"white_5":
			_on_ground(scene, rally(size), at)
			_on_owner(owner, SpellFx.cast_glow(Player.FX_WHITE, 2.8))
		"white_5_revive":
			_on_ground(scene, light_pillar(WHITE_GOLD, 0.8, 9.0, 1.2, 1.4, 2.0), at)
			_on_ground(scene, rising_motes(Player.FX_WHITE, 0.9, 30, 1.4), at)
		"blue_1":
			_on_ground(scene, magic_circle("blue", Player.FX_BLUE, 1.3, 0.3, 0.12, 1.5), at)
		"blue_2":
			_on_ground(scene, frost_breath(size), at)
		"blue_3":
			_on_ground(scene, magic_circle("blue", SuctionZone.VORTEX_TINT, size * 0.55, 0.6, 0.3, -1.2), at)
			_on_ground(scene, dust_ring(size * 0.5, 0.8, Color(0.7, 0.85, 1.0)), at)
		"blue_4":
			_on_ground(scene, frost_wall_rise(size, _flat(payload)), at)
		"blue_5_from":
			_on_ground(scene, blink(Player.FX_BLUE, false), at)
		"blue_5":
			_on_ground(scene, blink(Player.FX_BLUE, true), at)
		"black_1":
			_on_ground(scene, doom_blade(size, _flat(payload)), at)
		"black_2":
			_on_ground(scene, contagion_burst(), at)
		"black_3":
			_on_ground(scene, kill(), at)
		"black_4":
			_on_ground(scene, magic_circle("black", Player.FX_BLACK, 1.5, 0.5, 0.2), at)
		"black_5":
			_on_ground(scene, raise_dead(), at)
		"red_1":
			_on_ground(scene, magic_circle("red", RED_CIRCLE, 1.0 + size * 0.6, 0.15, 0.1, 2.0), at)
		"red_2":
			_on_ground(scene, magic_circle("red", RED_CIRCLE, 1.3, 0.2, 0.1, 2.0), at)
			_on_ground(scene, flame_burst(1.4), at)
		"red_3":
			_on_ground(scene, magic_circle("red", RED_CIRCLE, size, 0.5, 0.35, 1.0), at)
		"red_3_cast":
			_on_ground(scene, magic_circle("red", RED_CIRCLE, 1.2, 0.3, 0.12, 2.0), at)
		"red_5":
			_on_ground(scene, lightning_strike(size), at)
		"orb_bolt":
			var orb_mode: int = int(size)
			_on_ground(scene, OrbitingOrb.build_bolt(orb_mode, payload.get("dir", Vector3.ZERO)), at)
			# A soul thrown is a soul spent: one less on every screen but the server's.
			if orb_mode == OrbitingOrb.Mode.SOUL:
				_mirror_souls(owner, -1)
		"orb_soul_wisp":
			_on_ground(scene, OrbitingOrb.build_soul_wisp(payload.get("dir", Vector3.ZERO)), at)
			_mirror_souls(owner, 1)
		"orb_fire_shot":
			_on_ground(scene, fire_bolt(payload.get("dir", Vector3.FORWARD), size), at)
		"orb_lightning":
			_on_ground(scene, chain_lightning(payload.get("points", PackedVector3Array())), at)
		"green_1_launch":
			_on_ground(scene, dust_ring(1.6, 0.9), at)
		"green_1":
			_on_ground(scene, titanic_slam(size), at)
		"green_2":
			_on_ground(scene, magic_circle("green", Player.FX_GREEN, size, 0.8, 0.3, 0.5), at)
			_on_owner(owner, leaf_spiral(size * 0.45, 2.6 * maxf(size / 2.2, 1.0)))
			_on_owner(owner, light_pillar(Player.FX_GREEN, 0.5, 5.0, 0.6, 0.9, 2.2))
		"green_3":
			_on_ground(scene, magic_circle("green", Player.FX_GREEN, 1.3, 0.4, 0.2), at)
		"green_4":
			_on_ground(scene, roar(size), at)
		"green_5":
			_on_ground(scene, magic_circle("green", EARTH.lerp(Player.FX_GREEN, 0.35), 1.4, 0.6, 0.2), at)
			_on_owner(owner, splinters(EARTH, 1.0, 34))
			_on_owner(owner, dust_ring(1.2, 0.6))


## Keeps a client's copy of the caster's Grave Pact orb in step with the server's soul count.
static func _mirror_souls(owner: Node3D, change: int) -> void:
	if owner == null or not ("_aura_orbs" in owner):
		return
	var orb: Variant = owner._aura_orbs.get("aura_grave_pact", null)
	if is_instance_valid(orb) and orb.has_method("mirror_soul"):
		orb.mirror_soul(change)


## The aim a payload carries, flattened onto the ground. Falls back to -Z, the way a
## Node3D faces, when the spell sent none.
static func _flat(payload: Dictionary) -> Vector3:
	var dir: Vector3 = payload.get("dir", Vector3.ZERO)
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD


## Put on the ground under `at`. Projected effects find the real ground themselves, so this
## only has to get the node to the right point.
static func _on_ground(scene: Node, node: Node3D, at: Vector3) -> void:
	# Placed BEFORE it enters the tree: builders that spawn helpers of their own read their
	# position on tree_entered, which fires inside add_child.
	var parent := scene as Node3D
	node.position = at if parent == null else parent.to_local(at)
	scene.add_child(node)


## Ridden by the caster, so a buff cast on the move goes with them. `at`, when given, is a
## world point that is not the owner - an ally the caster shielded - and the effect is
## parented to whatever player or myr stands there instead, if anything.
static func _on_owner(owner: Node3D, node: Node3D, at: Variant = null) -> void:
	var host: Node3D = owner
	if at != null and owner != null:
		host = _nearest_ally(owner, at)
	if host == null:
		node.free()
		return
	host.add_child(node)


static func _nearest_ally(owner: Node3D, at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1.5
	for group: String in ["player", "myrs"]:
		for node: Node in owner.get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null:
				continue
			var d: float = body.global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = body
	return best


# --- shared pieces ---------------------------------------------------------------

## A box the ground-projection shaders draw on: `radius` across, `up` above the node and
## `down` below it (by default the projection's own band, AttackIndicator.PROJECT_UP/DOWN),
## offset so the band is centred on the node.
##
## A mark at someone's feet wants a much thinner band than a zone does: the projection
## paints on anything flat enough inside it, and the top of a shoulder or a raised forearm
## is flat enough. Keep `up` below a character's knees for anything drawn under one.
static func projected_volume(radius: float, material: ShaderMaterial,
		up: float = AttackIndicator.PROJECT_UP, down: float = AttackIndicator.PROJECT_DOWN) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(radius * 2.0, up + down, radius * 2.0)
	var volume := MeshInstance3D.new()
	volume.mesh = box
	volume.position.y = (up - down) * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.set_shader_parameter("projection_offset", volume.position)
	material.set_shader_parameter("projection_up", up)
	material.set_shader_parameter("projection_down", down)
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	volume.material_override = material
	return volume


static func _setter(material: ShaderMaterial, key: String) -> Callable:
	return func(value: float) -> void: material.set_shader_parameter(key, value)


## A rune circle on the ground in `colour`'s dialect: drawn outward over `reveal_time`,
## flaring as it closes, held for `hold` and then fading.
static func magic_circle(colour: String, tint: Color, radius: float, hold: float,
		reveal_time: float = 0.25, spin_speed: float = 0.6) -> Node3D:
	var root := Node3D.new()
	root.name = "MagicCircle"
	var material := ShaderMaterial.new()
	material.shader = MAGIC_CIRCLE_SHADER
	material.set_shader_parameter("pattern", int(CIRCLE_PATTERN.get(colour, 0)))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("reveal", 0.0)
	material.set_shader_parameter("fade", 1.0)
	material.set_shader_parameter("spin_speed", spin_speed)
	material.set_shader_parameter("seed", randf() * 100.0)
	# A little past the circle, for the rays and flames that reach outside its frame. The
	# band is thin above: the circle is under the caster's feet, and it must not climb onto
	# them. Below, it follows a slope falling away across the circle's width.
	root.add_child(projected_volume(radius * 1.08, material,
		clampf(radius * 0.25, 0.35, 2.0), clampf(radius * 0.6, 0.8, AttackIndicator.PROJECT_DOWN)))
	root.rotation.y = randf() * TAU

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_method(_setter(material, "reveal"), 0.0, 1.0, reveal_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_method(_setter(material, "flare"), 1.0, 0.0, 0.35)
		tween.tween_interval(hold)
		tween.tween_method(_setter(material, "fade"), 1.0, 0.0, 0.45)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## A column of light standing on the node's origin: opens out to `radius` almost at once,
## holds, and narrows away over `duration`. `flow` is which way the light pours - negative
## down out of the sky, positive up off the ground.
static func light_pillar(tint: Color, radius: float, height: float, duration: float,
		glow: float = 1.4, flow: float = -1.6) -> Node3D:
	var root := Node3D.new()
	root.name = "LightPillar"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 24
	cylinder.rings = 1
	var column := MeshInstance3D.new()
	column.mesh = cylinder
	column.position.y = height * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = LIGHT_PILLAR_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("glow", glow)
	material.set_shader_parameter("flow", flow)
	material.set_shader_parameter("seed", randf() * 100.0)
	column.material_override = material
	root.add_child(column)
	# An inner core, narrower and hotter, so the column has a centre.
	var core := MeshInstance3D.new()
	var core_mesh := cylinder.duplicate() as CylinderMesh
	core_mesh.top_radius = radius * 0.35
	core_mesh.bottom_radius = radius * 0.35
	core.mesh = core_mesh
	core.position.y = height * 0.5
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_material := material.duplicate() as ShaderMaterial
	core_material.set_shader_parameter("tint", tint.lerp(Color.WHITE, 0.6))
	core_material.set_shader_parameter("glow", glow * 1.3)
	core.material_override = core_material
	root.add_child(core)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 3.0
	light.omni_range = radius * 4.0 + 2.0
	light.position.y = 1.2
	root.add_child(light)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		root.scale = Vector3(0.05, 1.0, 0.05)
		tween.tween_property(root, "scale", Vector3.ONE, minf(0.12, duration * 0.2)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(duration * 0.35)
		tween.tween_property(root, "scale", Vector3(0.02, 1.0, 0.02), duration * 0.65) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_method(_setter(material, "fade"), 1.0, 0.0, duration * 0.65)
		tween.parallel().tween_method(_setter(core_material, "fade"), 1.0, 0.0, duration * 0.65)
		tween.parallel().tween_property(light, "light_energy", 0.0, duration * 0.65)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## A dome of light over whoever it is parented to: raised from the ground, flashing as it
## closes, held for `hold`, then eaten away downward.
static func shield_dome(tint: Color, radius: float, hold: float, pattern: int,
		height: float = DOME_HEIGHT) -> Node3D:
	var root := Node3D.new()
	root.name = "ShieldDome"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	# For a hemisphere `height` is the dome's own height, not the whole sphere's - and it may
	# differ from the radius, which makes the dome a tall bubble. A round one as wide as a
	# player stands is only waist-high and cut through the character's chest.
	sphere.height = height
	sphere.is_hemisphere = true
	sphere.radial_segments = 40
	sphere.rings = 16
	var dome := MeshInstance3D.new()
	dome.mesh = sphere
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A hemisphere's flat side is at its origin; a little below the feet so the ground line
	# shows all the way round on uneven ground.
	dome.position.y = -0.05
	var material := ShaderMaterial.new()
	material.shader = SHIELD_DOME_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("pattern", pattern)
	material.set_shader_parameter("reveal", 0.0)
	material.set_shader_parameter("seed", randf() * 100.0)
	dome.material_override = material
	root.add_child(dome)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_method(_setter(material, "reveal"), 0.0, 1.05, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_method(_setter(material, "flare"), 1.0, 0.0, 0.3)
		tween.tween_interval(hold)
		tween.tween_method(_setter(material, "reveal"), 1.05, 0.0, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Points of light drifting UP off the ground around the node - the settle beat of a white
## or green blessing.
static func rising_motes(tint: Color, radius: float, amount: int, lifetime: float,
		slot: String = "mote") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "RisingMotes"
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.55
	particles.local_coords = false
	particles.draw_pass_1 = SpellFx.premul_particle_mesh(0.18, slot)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.2
	process.emission_ring_height = 0.3
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.5
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.scale_curve = SpellFx._curve_texture([
		Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(0.7, 0.6), Vector2(1.0, 0.0),
	])
	process.color_ramp = SpellFx._premul_ramp(tint)
	particles.process_material = process
	particles.position.y = 0.2
	particles.tree_entered.connect(func() -> void:
		particles.get_tree().create_timer(lifetime + 0.3).timeout.connect(particles.queue_free),
		CONNECT_ONE_SHOT)
	return particles


# --- white ---------------------------------------------------------------------

## White's loudest moment: a shaft of light out of the sky onto the caster, a circle of
## runes the full width of the blast, and the blast itself as a front of light.
static func wrath_of_god(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "WrathOfGod"
	root.add_child(light_pillar(WHITE_GOLD, 1.5, 36.0, 0.7, 1.8, -3.0))
	root.add_child(magic_circle("white", WHITE_GOLD, radius, 0.6, 0.18, 0.8))
	root.add_child(SpellFx.impact(Player.FX_WHITE, radius))
	var motes := rising_motes(Player.FX_WHITE, radius * 0.7, 60, 1.4)
	root.add_child(motes)
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(2.6).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Rally the Fallen: a column of light the caster stands in, poured UP rather than down -
## raising, not striking - over a circle of the rally's reach.
static func rally(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Rally"
	root.add_child(light_pillar(WHITE_GOLD, 1.0, 14.0, 1.3, 1.4, 2.0))
	root.add_child(magic_circle("white", WHITE_GOLD, minf(radius, 4.0), 1.0, 0.3, 0.4))
	root.add_child(rising_motes(Player.FX_WHITE, 1.4, 50, 1.6))
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(3.0).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- green ---------------------------------------------------------------------

## Ground split by an impact: cracks running out from the centre, glowing from inside and
## cooling, the scar lingering after the glow has gone.
static func ground_cracks(radius: float, tint: Color, hold: float = 2.5) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundCracks"
	var material := ShaderMaterial.new()
	material.shader = GROUND_CRACKS_SHADER
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("glow_color", tint)
	material.set_shader_parameter("spread", 0.0)
	material.set_shader_parameter("seed", randf() * 100.0)
	root.add_child(projected_volume(radius, material))
	root.rotation.y = randf() * TAU
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_method(_setter(material, "spread"), 0.0, 1.05, 0.18) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_method(_setter(material, "heat"), 1.0, 0.0, 1.6).set_delay(0.2)
		tween.tween_interval(hold)
		tween.tween_method(_setter(material, "fade"), 1.0, 0.0, 1.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Dust thrown outward along the ground from a point - a landing, a stamp, a shout.
static func dust_ring(radius: float, lifetime: float, tint: Color = EARTH) -> GPUParticles3D:
	var dust := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, radius * 0.9, 22, lifetime)
	dust.explosiveness = 0.95
	var process: ParticleProcessMaterial = dust.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 0.3
	process.emission_ring_inner_radius = radius * 0.2
	process.emission_ring_height = 0.1
	process.direction = Vector3(1.0, 0.15, 0.0)
	process.spread = 180.0
	process.flatness = 0.85
	process.initial_velocity_min = radius * 2.0
	process.initial_velocity_max = radius * 3.2
	process.damping_min = radius * 2.5
	process.damping_max = radius * 3.5
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.2
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(1.0, 1.4)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.1, Color(tint.r, tint.g, tint.b, 0.75))
	gradient.set_color(gradient.get_point_count() - 1, Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.8, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	dust.position.y = 0.3
	dust.tree_entered.connect(func() -> void:
		dust.emitting = true
		dust.get_tree().create_timer(lifetime + 0.3).timeout.connect(dust.queue_free), CONNECT_ONE_SHOT)
	return dust


## Lumps of ground thrown up by an impact, arcing out and dropping back.
static func rock_chunks(radius: float, count: int) -> Node3D:
	var root := Node3D.new()
	root.name = "RockChunks"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.3, 0.22)
	material.roughness = 1.0
	for i: int in range(count):
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: float = randf_range(0.18, 0.42)
		box.size = Vector3(size, size * randf_range(0.6, 1.1), size * randf_range(0.7, 1.2))
		chunk.mesh = box
		chunk.material_override = material
		chunk.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		root.add_child(chunk)
		var angle: float = randf() * TAU
		var reach: float = radius * randf_range(0.45, 1.0)
		var rise: float = randf_range(1.2, 3.0)
		var flight: float = randf_range(0.55, 0.85)
		var spin := Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		var start_rot: Vector3 = chunk.rotation
		chunk.tree_entered.connect(func() -> void:
			var tween: Tween = chunk.create_tween()
			tween.tween_method(func(t: float) -> void:
				var flat: Vector2 = Vector2(cos(angle), sin(angle)) * reach * t
				chunk.position = Vector3(flat.x, 4.0 * rise * t * (1.0 - t) + 0.1, flat.y)
				chunk.rotation = start_rot + spin * t * flight,
				0.0, 1.0, flight)
			# Lands, sits for a moment, sinks out of sight.
			tween.tween_interval(0.6)
			tween.tween_property(chunk, "position:y", -0.4, 0.5), CONNECT_ONE_SHOT)
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(2.2).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Titanic Brawl's landing: the ground cracks open under the slam, rock and dust are thrown
## out, and a front of force runs to the edge of what it hit.
static func titanic_slam(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TitanicSlam"
	root.add_child(ground_cracks(radius * 0.8, Player.FX_GREEN, 2.5))
	root.add_child(dust_ring(radius * 0.7, 1.2))
	root.add_child(rock_chunks(radius * 0.8, 12))
	root.add_child(SpellFx.shockwave(EARTH.lerp(Player.FX_GREEN, 0.4), radius, 0.4))
	var flash := OmniLight3D.new()
	flash.light_color = Player.FX_GREEN
	flash.light_energy = 4.0
	flash.omni_range = radius * 2.0
	flash.position.y = 0.8
	root.add_child(flash)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.25)
		tween.tween_interval(5.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Leaves whirling UP around the caster - growth, not a blast.
static func leaf_spiral(radius: float, height: float) -> GPUParticles3D:
	var leaves := GPUParticles3D.new()
	leaves.name = "LeafSpiral"
	leaves.amount = 46
	leaves.lifetime = 1.3
	leaves.one_shot = true
	leaves.explosiveness = 0.6
	leaves.local_coords = true
	leaves.draw_pass_1 = SpellFx.premul_particle_mesh(0.3, "shard")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.7
	process.emission_ring_height = 0.2
	process.direction = Vector3.UP
	process.spread = 5.0
	process.initial_velocity_min = height * 0.8
	process.initial_velocity_max = height * 1.3
	process.damping_min = height * 0.5
	process.damping_max = height * 0.8
	process.tangential_accel_min = radius * 6.0
	process.tangential_accel_max = radius * 9.0
	process.radial_accel_min = -radius * 1.5
	process.radial_accel_max = -radius * 0.5
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.6
	process.scale_max = 1.1
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.0), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	process.color_ramp = SpellFx._premul_ramp(Player.FX_GREEN)
	leaves.process_material = process
	leaves.tree_entered.connect(func() -> void:
		leaves.emitting = true
		leaves.get_tree().create_timer(1.8).timeout.connect(leaves.queue_free), CONNECT_ONE_SHOT)
	return leaves


## Splinters thrown off the caster - bark growing over them cracks the air around it.
static func splinters(tint: Color, radius: float, amount: int) -> GPUParticles3D:
	var chips: GPUParticles3D = SpellFx.sparks(tint, radius, amount, 4.5, "shard")
	chips.position.y = 1.0
	var process: ParticleProcessMaterial = chips.process_material
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.angular_velocity_min = -400.0
	process.angular_velocity_max = 400.0
	chips.tree_entered.connect(func() -> void:
		chips.emitting = true
		chips.get_tree().create_timer(1.2).timeout.connect(chips.queue_free), CONNECT_ONE_SHOT)
	return chips


## Roar: the shout goes out as rings of force along the ground, dust and grass thrown back
## by it, the colour's circle under the one shouting.
static func roar(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Roar"
	root.add_child(magic_circle("green", Player.FX_GREEN, 1.6, 0.4, 0.12, 1.4))
	root.add_child(dust_ring(minf(radius * 0.35, 2.5), 0.9))
	root.add_child(splinters(Player.FX_GREEN, radius * 0.5, 30))
	root.tree_entered.connect(func() -> void:
		# Three fronts, one after another: a wave starts expanding the moment it enters the
		# tree, so the later ones are added later rather than hidden.
		for i: int in range(3):
			var tint: Color = Player.FX_GREEN.lerp(EARTH, 0.3 * float(i))
			var reach: float = radius * (1.0 - 0.15 * float(i))
			root.get_tree().create_timer(0.13 * float(i)).timeout.connect(func() -> void:
				if is_instance_valid(root):
					root.add_child(SpellFx.shockwave(tint, reach, 0.55)))
		root.get_tree().create_timer(2.0).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- blue ----------------------------------------------------------------------

## Frost Breath: ice breaking out of the ground in a ring around the caster, a cold mist
## rolling out with it, and a frost wave running to the edge of the freeze.
static func frost_breath(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FrostBreath"
	root.add_child(magic_circle("blue", Player.FX_BLUE, minf(radius * 0.45, 2.5), 0.5, 0.15, 1.0))
	root.add_child(SpellFx.shockwave(Color(0.6, 0.88, 1.0), radius, 0.5))
	root.add_child(dust_ring(radius * 0.55, 1.4, Color(0.82, 0.92, 1.0)))
	root.add_child(SpellFx.sparks(Player.FX_BLUE, radius * 0.6, 40, radius * 1.4, "shard"))
	root.tree_entered.connect(func() -> void:
		# The ice itself, as BossTell already draws it: spikes breaking the ground, nearest
		# first, standing for a moment and sinking away.
		BossTell.spawn(root.get_parent(), {
			"tell": "ice_spikes", "at": root.global_position, "yaw": randf() * TAU,
			"radius": radius * 0.95, "inner_radius": 1.4, "windup": 0.22,
			"shape": AttackIndicator.Shape.RING,
		})
		root.get_tree().create_timer(2.0).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Wall of Frost going up: bursts of cold mist along its length, so the wall arrives instead
## of appearing. The wall's own model carries the ice; spikes on top of it were clutter.
static func frost_wall_rise(length: float, facing: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "FrostWallRise"
	root.tree_entered.connect(func() -> void:
		var across := Vector3(-facing.z, 0.0, facing.x)
		for i: int in range(3):
			var mist: GPUParticles3D = dust_ring(1.6, 1.1, Color(0.85, 0.94, 1.0))
			root.add_child(mist)
			mist.position = across * length * (float(i) - 1.0) * 0.35
		root.get_tree().create_timer(1.6).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Displace: the caster folding out of one spot (`arrive` false) and into another - shards
## pulled into a thin column of light, then thrown out of it.
static func blink(tint: Color, arrive: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Blink"
	root.add_child(light_pillar(tint, 0.35, 3.0, 0.35, 1.3, 4.0 if arrive else -4.0))
	root.add_child(magic_circle("blue", tint, 1.1, 0.25, 0.08, 2.5))
	if arrive:
		var burst: GPUParticles3D = SpellFx.sparks(tint, 1.0, 30, 5.0, "shard")
		burst.position.y = 1.0
		root.add_child(burst)
	else:
		var gather: Node3D = SpellFx.cast_glow(tint, 1.4)
		root.add_child(gather)
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(1.4).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- black ---------------------------------------------------------------------

## A crescent of smoke with a violet edge, swept out along `facing` to `length`, cutting a
## scar into the ground behind it.
static func doom_blade(length: float, facing: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "DoomBlade"
	var blade := MeshInstance3D.new()
	blade.mesh = _crescent_mesh(2.4, 1.2, 150.0)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = VOID_BLADE_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("edge_color", Player.FX_BLACK)
	material.set_shader_parameter("glow", 3.5)
	material.set_shader_parameter("seed", randf() * 100.0)
	blade.material_override = material
	blade.position.y = 1.1
	# Tilted a little off flat, the way a blade thrown from a swing travels.
	blade.rotation.z = 0.25
	root.add_child(blade)

	var trail := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 1.5, 30, 0.9)
	trail.one_shot = false
	trail.explosiveness = 0.0
	var process: ParticleProcessMaterial = trail.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.0, 0.2, 0.2)
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.5), Vector2(1.0, 1.3)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(VOID_SMOKE.r, VOID_SMOKE.g, VOID_SMOKE.b, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(VOID_SMOKE.r, VOID_SMOKE.g, VOID_SMOKE.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	blade.add_child(trail)

	var scar_material := ShaderMaterial.new()
	scar_material.shader = GROUND_SLASH_SHADER
	scar_material.set_shader_parameter("length", length)
	scar_material.set_shader_parameter("glow_color", Player.FX_BLACK)
	scar_material.set_shader_parameter("reach", 0.0)
	scar_material.set_shader_parameter("seed", randf() * 100.0)
	var scar_box := BoxMesh.new()
	scar_box.size = Vector3(1.6, AttackIndicator.PROJECT_UP + AttackIndicator.PROJECT_DOWN, length)
	var scar := MeshInstance3D.new()
	scar.mesh = scar_box
	scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The scar runs along the node's local +Z, the projection box centred on it.
	scar.position = Vector3(0.0, (AttackIndicator.PROJECT_UP - AttackIndicator.PROJECT_DOWN) * 0.5, length * 0.5)
	scar_material.set_shader_parameter("projection_offset", scar.position)
	scar_material.set_shader_parameter("projection_up", AttackIndicator.PROJECT_UP)
	scar_material.set_shader_parameter("projection_down", AttackIndicator.PROJECT_DOWN)
	scar_material.render_priority = SpellFx.FX_RENDER_PRIORITY
	scar.material_override = scar_material
	root.add_child(scar)

	var travel: float = clampf(length / 40.0, 0.18, 0.4)
	root.tree_entered.connect(func() -> void:
		# +Z along the aim: the scar runs along local +Z, the blade travels with it.
		root.look_at(root.global_position - facing, Vector3.UP)
		var tween: Tween = root.create_tween()
		tween.tween_property(blade, "position:z", length, travel)
		tween.parallel().tween_method(_setter(scar_material, "reach"), 0.0, 1.0, travel)
		tween.tween_callback(func() -> void: trail.emitting = false)
		tween.tween_method(_setter(material, "fade"), 1.0, 0.0, 0.25)
		tween.parallel().tween_method(_setter(scar_material, "heat"), 1.0, 0.0, 1.0)
		tween.tween_interval(1.2)
		tween.tween_method(_setter(scar_material, "fade"), 1.0, 0.0, 0.8)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## A flat crescent in the XZ plane, bulging toward +Z, built as a strip: UV.x runs tip to
## tip, UV.y from the cutting edge (the outer arc) to the trailing one.
static func _crescent_mesh(radius: float, thickness: float, span_degrees: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 24
	var span: float = deg_to_rad(span_degrees)
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		# The arc bulges toward +Z, the way the blade travels along the node's +Z.
		var a: float = -span * 0.5 + span * t
		var width: float = thickness * sin(t * PI)
		outer.append(Vector3(sin(a) * radius, 0.0, cos(a) * radius - radius * 0.6))
		inner.append(Vector3(sin(a) * (radius - width), 0.0, cos(a) * (radius - width) - radius * 0.6))
	for i: int in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		for v: Array in [[outer[i], Vector2(t0, 0.0)], [outer[i + 1], Vector2(t1, 0.0)], [inner[i + 1], Vector2(t1, 1.0)],
				[outer[i], Vector2(t0, 0.0)], [inner[i + 1], Vector2(t1, 1.0)], [inner[i], Vector2(t0, 1.0)]]:
			st.set_uv(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()


## Smoke that eats the light around it, rising off a point.
static func void_smoke(radius: float, amount: int, lifetime: float, tint: Color = VOID_SMOKE) -> GPUParticles3D:
	var smoke := ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, radius, amount, lifetime)
	smoke.explosiveness = 0.85
	var process: ParticleProcessMaterial = smoke.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.3
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 2.2
	process.damping_min = 0.8
	process.damping_max = 1.6
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(1.0, 1.4)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.12, Color(tint.r, tint.g, tint.b, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(tint.r, tint.g, tint.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	smoke.tree_entered.connect(func() -> void:
		smoke.emitting = true
		smoke.get_tree().create_timer(lifetime + 0.4).timeout.connect(smoke.queue_free), CONNECT_ONE_SHOT)
	return smoke


## Kill: the target is taken - the black circle opens under it, light is pulled in, and a
## violet bolt and a column of black smoke go up where it stood.
static func kill() -> Node3D:
	var root := Node3D.new()
	root.name = "Kill"
	root.add_child(magic_circle("black", Player.FX_BLACK, 2.0, 0.6, 0.12, -1.5))
	root.add_child(light_pillar(Player.FX_BLACK, 0.4, 9.0, 0.45, 1.6, 6.0))
	var smoke: GPUParticles3D = void_smoke(2.0, 18, 1.6)
	smoke.position.y = 0.6
	root.add_child(smoke)
	var pull: Node3D = SpellFx.cast_glow(Player.FX_BLACK, 2.0)
	root.add_child(pull)
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(2.4).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Contagion taking hold: a sick green-violet puff off the target and the black sigil under it.
static func contagion_burst() -> Node3D:
	var root := Node3D.new()
	root.name = "Contagion"
	root.add_child(magic_circle("black", EnemyBase.CONTAGION_TINT, 1.2, 0.3, 0.1, 2.0))
	var puff: GPUParticles3D = void_smoke(1.3, 12, 1.2, Color(0.25, 0.4, 0.12))
	puff.position.y = 0.8
	root.add_child(puff)
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(1.8).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Zombify, per corpse: the black circle opens, dark smoke and grave-light rise out of it.
static func raise_dead() -> Node3D:
	var root := Node3D.new()
	root.name = "RaiseDead"
	root.add_child(magic_circle("black", Color(0.55, 0.9, 0.5).lerp(Player.FX_BLACK, 0.4), 1.3, 0.9, 0.2, -0.8))
	root.add_child(void_smoke(1.5, 14, 1.8))
	root.add_child(rising_motes(Color(0.55, 0.95, 0.5), 0.8, 24, 1.3))
	root.tree_entered.connect(func() -> void:
		root.get_tree().create_timer(2.6).timeout.connect(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- red -----------------------------------------------------------------------

## A burst of the fire flipbook off a point - a dash setting off, a hand catching fire.
static func flame_burst(radius: float) -> GPUParticles3D:
	var flames := ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, radius, 14, 0.6)
	flames.explosiveness = 0.9
	var process: ParticleProcessMaterial = flames.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.4
	process.direction = Vector3.UP
	process.spread = 60.0
	process.initial_velocity_min = radius * 1.0
	process.initial_velocity_max = radius * 2.4
	process.damping_min = radius * 2.0
	process.damping_max = radius * 3.0
	process.gravity = Vector3(0.0, 2.0, 0.0)
	var ramp := GradientTexture1D.new()
	ramp.gradient = EmberFx.fire_gradient()
	process.color_ramp = ramp
	flames.position.y = 0.6
	flames.add_child(SpellFx.heat_haze(Vector3(radius * 0.4, 0.2, radius * 0.4), radius * 1.2, 8, 0.9,
		radius * 1.4, 0.014, true))
	flames.tree_entered.connect(func() -> void:
		flames.emitting = true
		flames.get_tree().create_timer(1.0).timeout.connect(flames.queue_free), CONNECT_ONE_SHOT)
	return flames


## Fire Cone's channel: a jet of fire poured along -Z from the node for as long as it stands,
## `length` long. Stop it with `stop_stream`, which lets it gutter out instead of vanishing.
##
## Layers: three flame-jet cones (flame_jet.gdshader) - the jet, a narrower, shorter, hotter
## core inside it, and a wide faint haze around it - then billows of flame rolling down it
## and blooming at its end, embers streaking out, smoke climbing off the tips, air shimmer,
## and a light that flickers with it. The billows are braked and swell as they go: thrown
## fast and small, as they once were, they read as orange balls, not as fire.
static func fire_stream(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FireStream"
	var outer_material := _flame_jet_material(1.0, 2.2, 2.2)
	var inner_material := _flame_jet_material(0.62, 2.6, 2.8)
	var outer := MeshInstance3D.new()
	outer.name = "Jet"
	outer.mesh = _cone_mesh(0.15, length * 0.3, length)
	outer.material_override = outer_material
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(outer)
	var inner := MeshInstance3D.new()
	inner.name = "Core"
	inner.mesh = _cone_mesh(0.08, length * 0.14, length * 0.7)
	inner.material_override = inner_material
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner)

	# A wide, soft outer layer: the heat haze of flame around the jet, so its silhouette is
	# fire thinning into air rather than the edge of a cone.
	var haze_material := _flame_jet_material(1.1, 1.6, 1.8)
	haze_material.set_shader_parameter("density", 0.45)
	var haze := MeshInstance3D.new()
	haze.name = "Haze"
	haze.mesh = _cone_mesh(0.3, length * 0.42, length * 1.05)
	haze.material_override = haze_material
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(haze)

	var embers: GPUParticles3D = SpellFx.sparks(Color(1.0, 0.6, 0.2), 0.3, 40, length * 2.2)
	embers.name = "Embers"
	embers.one_shot = false
	embers.explosiveness = 0.0
	embers.lifetime = 0.6
	var ep: ParticleProcessMaterial = embers.process_material
	ep.direction = Vector3(0.0, 0.0, -1.0)
	ep.spread = 26.0
	ep.gravity = Vector3(0.0, 1.5, 0.0)
	ep.particle_flag_align_y = true
	embers.draw_pass_1 = SpellFx.streak_mesh(0.08, 0.45)
	root.add_child(embers)

	# Billows of flame rolling down the jet: born small at the hands, braked as they go so
	# they swell and pile up toward the end of the cone, burning out into soot there. Slow
	# and growing, unlike the jet - fast small ones read as balls thrown along it.
	var billows: GPUParticles3D = ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, 2.6, 26, 0.75)
	billows.name = "Billows"
	billows.one_shot = false
	var bp: ParticleProcessMaterial = billows.process_material
	bp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bp.emission_sphere_radius = 0.25
	bp.direction = Vector3(0.0, 0.0, -1.0)
	bp.spread = 16.0
	bp.initial_velocity_min = length * 1.5
	bp.initial_velocity_max = length * 2.1
	bp.damping_min = length * 1.6
	bp.damping_max = length * 2.4
	bp.gravity = Vector3(0.0, 1.8, 0.0)
	bp.scale_min = 0.7
	bp.scale_max = 1.2
	bp.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.45), Vector2(0.45, 0.9), Vector2(1.0, 1.3)])
	# Faded in rather than born opaque: inside the jet's bright core a fresh puff is only its
	# dark-rimmed outline, a row of little rings along the cone.
	var billow_gradient: Gradient = EmberFx.fire_gradient()
	billow_gradient.set_color(0, Color(1.0, 0.85, 0.42, 0.0))
	billow_gradient.add_point(0.2, Color(1.0, 0.7, 0.25, 1.0))
	var billow_ramp := GradientTexture1D.new()
	billow_ramp.gradient = billow_gradient
	bp.color_ramp = billow_ramp
	billows.position = Vector3(0.0, 0.0, -0.9)
	root.add_child(billows)

	# And the cloud the jet ends in: puffs blooming at the tip and drifting up, so the cone
	# finishes in a mass of fire instead of thinning to its point.
	var plume: GPUParticles3D = ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, 3.4, 12, 0.9)
	plume.name = "Plume"
	plume.one_shot = false
	var pp: ParticleProcessMaterial = plume.process_material
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(length * 0.16, 0.3, length * 0.12)
	pp.direction = Vector3(0.0, 0.4, -1.0)
	pp.spread = 35.0
	pp.initial_velocity_min = 0.8
	pp.initial_velocity_max = 2.0
	pp.gravity = Vector3(0.0, 2.2, 0.0)
	pp.scale_min = 0.6
	pp.scale_max = 1.1
	pp.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(0.35, 1.0), Vector2(1.0, 1.4)])
	var plume_ramp := GradientTexture1D.new()
	plume_ramp.gradient = EmberFx.fire_gradient()
	pp.color_ramp = plume_ramp
	plume.position = Vector3(0.0, 0.2, -length * 0.8)
	root.add_child(plume)

	# Air shimmering over the whole jet and climbing off it.
	var heat: Node3D = SpellFx.heat_haze(Vector3(length * 0.18, 0.25, length * 0.42), 1.8, 26, 0.9, 1.4, 0.014)
	heat.position = Vector3(0.0, 0.3, -length * 0.55)
	root.add_child(heat)

	var smoke: GPUParticles3D = ExplosionFx.flipbook_particles(ExplosionFx.SMOKE_FLIPBOOK, 2.4, 10, 1.6)
	smoke.name = "Smoke"
	smoke.one_shot = false
	smoke.local_coords = false
	var sp: ParticleProcessMaterial = smoke.process_material
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(length * 0.3, 0.3, length * 0.15)
	sp.direction = Vector3.UP
	sp.spread = 20.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.4
	sp.gravity = Vector3(0.0, 0.8, 0.0)
	sp.scale_curve = SpellFx._curve_texture([Vector2(0.0, 0.4), Vector2(1.0, 1.5)])
	var smoke_gradient := Gradient.new()
	smoke_gradient.set_color(0, Color(0.16, 0.1, 0.08, 0.0))
	smoke_gradient.add_point(0.2, Color(0.16, 0.1, 0.08, 0.45))
	smoke_gradient.set_color(smoke_gradient.get_point_count() - 1, Color(0.2, 0.17, 0.15, 0.0))
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke_gradient
	sp.color_ramp = smoke_ramp
	smoke.position = Vector3(0.0, 0.4, -length * 0.85)
	root.add_child(smoke)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 0.0
	light.omni_range = length * 1.1
	light.position = Vector3(0.0, 0.0, -length * 0.45)
	root.add_child(light)

	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		# Catches in a fifth of a second rather than switching on.
		tween.tween_method(func(v: float) -> void:
			outer_material.set_shader_parameter("intensity", v)
			inner_material.set_shader_parameter("intensity", v)
			haze_material.set_shader_parameter("intensity", v),
			0.0, 1.0, 0.2)
		var flicker: Tween = root.create_tween().set_loops()
		for energy: float in [5.0, 3.2, 4.4, 2.8, 4.8, 3.6]:
			flicker.tween_property(light, "light_energy", energy, 0.07), CONNECT_ONE_SHOT)
	return root


## Lets a fire stream gutter out: emission stops, the jet thins to nothing, and the node frees
## itself once the last of its particles has burned out.
static func stop_stream(stream: Node3D) -> void:
	if not is_instance_valid(stream):
		return
	for child: Node in stream.get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = false
	var materials: Array[ShaderMaterial] = []
	for jet: String in ["Jet", "Core", "Haze"]:
		var mesh := stream.get_node_or_null(jet) as MeshInstance3D
		if mesh != null:
			materials.append(mesh.material_override as ShaderMaterial)
	var light := stream.get_node_or_null("Light") as OmniLight3D
	var tween: Tween = stream.create_tween()
	tween.tween_method(func(v: float) -> void:
		for material: ShaderMaterial in materials:
			material.set_shader_parameter("intensity", v)
		if light != null:
			light.light_energy = v * 3.0,
		1.0, 0.0, 0.3)
	tween.tween_interval(1.4)
	tween.tween_callback(stream.queue_free)


static func _flame_jet_material(reach: float, glow: float, speed: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLAME_JET_SHADER
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	material.set_shader_parameter("reach", reach)
	material.set_shader_parameter("glow", glow)
	material.set_shader_parameter("speed", speed)
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("seed", randf() * 100.0)
	return material


## An open cone along -Z: `near_radius` at the origin, `far_radius` at `length`. UV.y runs
## along it from 0 at the origin, UV.x round it. Normals point outward.
static func _cone_mesh(near_radius: float, far_radius: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around: int = 28
	var along: int = 8
	for j: int in range(along):
		var v0: float = float(j) / float(along)
		var v1: float = float(j + 1) / float(along)
		var r0: float = lerpf(near_radius, far_radius, v0)
		var r1: float = lerpf(near_radius, far_radius, v1)
		for i: int in range(around):
			var u0: float = float(i) / float(around)
			var u1: float = float(i + 1) / float(around)
			var c0 := Vector2(cos(u0 * TAU), sin(u0 * TAU))
			var c1 := Vector2(cos(u1 * TAU), sin(u1 * TAU))
			var p00 := Vector3(c0.x * r0, c0.y * r0, -v0 * length)
			var p10 := Vector3(c1.x * r0, c1.y * r0, -v0 * length)
			var p01 := Vector3(c0.x * r1, c0.y * r1, -v1 * length)
			var p11 := Vector3(c1.x * r1, c1.y * r1, -v1 * length)
			var n0 := Vector3(c0.x, c0.y, 0.0)
			var n1 := Vector3(c1.x, c1.y, 0.0)
			for vert: Array in [[p00, Vector2(u0, v0), n0], [p10, Vector2(u1, v0), n1], [p11, Vector2(u1, v1), n1],
					[p00, Vector2(u0, v0), n0], [p11, Vector2(u1, v1), n1], [p01, Vector2(u0, v1), n0]]:
				st.set_uv(vert[1])
				st.set_normal(vert[2])
				st.add_vertex(vert[0])
	return st.commit()


## A forked bolt: a jagged ribbon from `height` down to the node, with a couple of branches,
## re-drawn a few times as it flickers.
static func _bolt_mesh(height: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main: Array[Vector3] = _bolt_path(Vector3(rng.randf_range(-1.5, 1.5), height, rng.randf_range(-1.5, 1.5)), Vector3.ZERO, 6, height * 0.09, rng)
	_ribbon(st, main, 0.32)
	for b: int in range(3):
		var from: Vector3 = main[rng.randi_range(2, main.size() - 3)]
		var to: Vector3 = from + Vector3(rng.randf_range(-3.0, 3.0), -rng.randf_range(2.0, 4.5), rng.randf_range(-3.0, 3.0))
		_ribbon(st, _bolt_path(from, to, 4, 0.5, rng), 0.14)
	return st.commit()


## Midpoint displacement between two points, `depth` times over.
static func _bolt_path(from: Vector3, to: Vector3, depth: int, jitter: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var points: Array[Vector3] = [from, to]
	var amount: float = jitter
	for _d: int in range(depth):
		var next: Array[Vector3] = []
		for i: int in range(points.size() - 1):
			next.append(points[i])
			var mid: Vector3 = (points[i] + points[i + 1]) * 0.5
			mid += Vector3(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount) * 0.3, rng.randf_range(-amount, amount))
			next.append(mid)
		next.append(points[-1])
		points = next
		amount *= 0.55
	return points


## Two crossed quad strips along a path, so the bolt holds up from any side.
static func _ribbon(st: SurfaceTool, path: Array[Vector3], width: float) -> void:
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		for i: int in range(path.size() - 1):
			var w0: float = width * (1.0 - float(i) / float(path.size()) * 0.5)
			var w1: float = width * (1.0 - float(i + 1) / float(path.size()) * 0.5)
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			for v: Array in [[a - side * w0, 0.0], [a + side * w0, 1.0], [b + side * w1, 1.0],
					[a - side * w0, 0.0], [b + side * w1, 1.0], [b - side * w1, 0.0]]:
				st.set_uv(Vector2(float(v[1]), 0.0))
				st.add_vertex(v[0])


## Lightning Bolt landing: a forked bolt out of the sky, flickering, a blinding flash, the
## ground split and scorched where it hit, sparks thrown off.
static func lightning_strike(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "LightningStrike"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bolt := MeshInstance3D.new()
	bolt.mesh = _bolt_mesh(22.0, rng)
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(LIGHTNING.r * 2.2, LIGHTNING.g * 2.2, LIGHTNING.b * 2.4, 1.0)
	material.disable_fog = true
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	bolt.material_override = material
	root.add_child(bolt)
	root.add_child(light_pillar(LIGHTNING, 0.45, 22.0, 0.25, 1.0, -8.0))
	root.add_child(ground_cracks(maxf(radius * 1.6, 2.5), LIGHTNING, 1.5))
	root.add_child(ExplosionFx.scorch(maxf(radius, 1.6), 3.0))
	var sparks: GPUParticles3D = SpellFx.sparks(LIGHTNING, 1.0, 40, 9.0)
	sparks.position.y = 0.3
	root.add_child(sparks)
	var flash := OmniLight3D.new()
	flash.light_color = LIGHTNING
	flash.light_energy = 10.0
	flash.omni_range = 14.0
	flash.position.y = 2.0
	root.add_child(flash)
	root.tree_entered.connect(func() -> void:
		var tween: Tween = root.create_tween()
		# Flickers: re-struck twice along a new path, then gone.
		for i: int in range(3):
			tween.tween_interval(0.05)
			tween.tween_callback(func() -> void: bolt.visible = false)
			tween.tween_interval(0.03)
			tween.tween_callback(func() -> void:
				bolt.mesh = _bolt_mesh(22.0, rng)
				bolt.visible = true)
		tween.parallel().tween_property(flash, "light_energy", 0.0, 0.3)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.12)
		tween.tween_callback(bolt.queue_free)
		tween.tween_interval(5.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


# --- the orbs' shots -------------------------------------------------------------

## Orb of Fire's shot: a ball of fire with a tail, flown from the node along `offset` in
## `travel` seconds, bursting where it lands. The tail (SpellFx.tail_mesh's texture) is laid
## along the flight once rather than per particle - a single projectile flies straight.
static func fire_bolt(offset: Vector3, travel: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FireBolt"
	var length: float = offset.length()
	if length < 0.05:
		root.tree_entered.connect(root.queue_free, CONNECT_ONE_SHOT)
		return root
	var direction: Vector3 = offset / length

	var head := Node3D.new()
	head.name = "Head"
	root.add_child(head)
	# The ball: the fire flipbook, a handful of particles churning in place around the head.
	var ball := ExplosionFx.flipbook_particles(ExplosionFx.FIRE_FLIPBOOK, 0.8, 6, 0.3)
	ball.one_shot = false
	ball.local_coords = true
	ball.preprocess = 0.3
	var bp: ParticleProcessMaterial = ball.process_material
	bp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bp.emission_sphere_radius = 0.05
	bp.spread = 180.0
	bp.initial_velocity_min = 0.0
	bp.initial_velocity_max = 0.3
	var fire_ramp := GradientTexture1D.new()
	fire_ramp.gradient = EmberFx.fire_gradient()
	bp.color_ramp = fire_ramp
	head.add_child(ball)
	# The tail: one crossed streak behind the head, its +Y turned along the flight.
	var tail := MeshInstance3D.new()
	tail.mesh = SpellFx.tail_mesh(0.75, 2.4, Color(1.6, 0.62, 0.16))
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(tail)
	# Embers shed along the way, left behind in the world.
	var embers: GPUParticles3D = SpellFx.sparks(Color(1.0, 0.6, 0.2), 0.1, 16, 1.2)
	embers.one_shot = false
	embers.explosiveness = 0.0
	embers.lifetime = 0.45
	head.add_child(embers)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.2
	light.omni_range = 2.2
	head.add_child(light)

	root.tree_entered.connect(func() -> void:
		# Point the tail's +Y along the flight: a basis whose Y is the direction.
		var up: Vector3 = direction
		var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
		tail.basis = Basis(side, up, side.cross(up).normalized())
		var tween: Tween = root.create_tween()
		tween.tween_property(head, "position", offset, travel)
		tween.tween_callback(func() -> void:
			ball.emitting = false
			embers.emitting = false
			tail.visible = false
			light.light_energy = 0.0
			var burst: GPUParticles3D = flame_burst(0.7)
			burst.position = offset - Vector3(0.0, 0.6, 0.0)
			root.add_child(burst)
			var sparks: GPUParticles3D = SpellFx.sparks(Color(1.0, 0.6, 0.2), 0.3, 12, 3.0)
			sparks.position = offset
			root.add_child(sparks))
		tween.tween_interval(1.0)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Lightning Orb's shot: a jagged arc from each point in `points` to the next, flickering
## through a few shapes and gone in a fifth of a second, with a flash where each one lands.
## The arcs are Kenney's spark_05 stretched between the two ends; the node's own position
## is ignored, the points are world positions.
static func chain_lightning(points: PackedVector3Array) -> Node3D:
	var root := Node3D.new()
	root.name = "ChainLightning"
	if points.size() < 2:
		root.tree_entered.connect(root.queue_free, CONNECT_ONE_SHOT)
		return root
	var material := StandardMaterial3D.new()
	material.albedo_texture = SpellFx._texture("arc")
	material.albedo_color = Color(LIGHTNING.r * 2.0, LIGHTNING.g * 2.0, LIGHTNING.b * 2.4, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_fog = true
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	var arcs: Array[MeshInstance3D] = []
	for index: int in range(points.size() - 1):
		var arc := MeshInstance3D.new()
		arc.mesh = SpellFx.streak_mesh(1.0, 1.0, "arc")
		arc.material_override = material
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arc.set_meta("from", points[index])
		arc.set_meta("to", points[index + 1])
		root.add_child(arc)
		arcs.append(arc)
		var spark: GPUParticles3D = SpellFx.sparks(LIGHTNING, 0.2, 10, 4.0)
		spark.set_meta("at", points[index + 1])
		root.add_child(spark)
		var flash := OmniLight3D.new()
		flash.light_color = LIGHTNING
		flash.light_energy = 2.5
		flash.omni_range = 3.0
		flash.set_meta("at", points[index + 1])
		root.add_child(flash)

	root.tree_entered.connect(func() -> void:
		for child: Node in root.get_children():
			if child.has_meta("at"):
				(child as Node3D).global_position = child.get_meta("at")
		for arc: MeshInstance3D in arcs:
			_stretch_arc(arc)
		var tween: Tween = root.create_tween()
		# Re-struck twice: each arc flips and turns about its own line, so the bolt crackles.
		for _strike: int in range(2):
			tween.tween_interval(0.05)
			tween.tween_callback(func() -> void:
				for arc: MeshInstance3D in arcs:
					_stretch_arc(arc))
		tween.tween_property(material, "albedo_color:a", 0.0, 0.12)
		for child: Node in root.get_children():
			if child is OmniLight3D:
				tween.parallel().tween_property(child, "light_energy", 0.0, 0.12)
		tween.tween_interval(0.5)
		tween.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## Lays an arc mesh (unit length along +Y) from its "from" meta to its "to" meta, turned a
## random way about that line and randomly mirrored, so every re-strike is a new shape.
static func _stretch_arc(arc: MeshInstance3D) -> void:
	var from: Vector3 = arc.get_meta("from")
	var to: Vector3 = arc.get_meta("to")
	var along: Vector3 = to - from
	var length: float = along.length()
	if length < 0.01:
		arc.visible = false
		return
	var up: Vector3 = along / length
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	side = side.rotated(up, randf() * TAU)
	var mirror: float = -1.0 if randf() < 0.5 else 1.0
	arc.global_transform = Transform3D(
		Basis(side * mirror * minf(length * 0.35, 1.6), up * length, side.cross(up).normalized()),
		(from + to) * 0.5)
