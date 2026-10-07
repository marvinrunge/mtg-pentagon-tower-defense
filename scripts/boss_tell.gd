extends Node3D
class_name BossTell
## A tell that belongs to the world rather than to the HUD: something you would see coming
## even with every ground decal switched off. Spawned beside a boss telegraph (see
## EnemyBase._spawn_telegraph) on every peer, from the same description, and timed off the
## same windup - so it lands exactly when the hit does.
##
## Only the attacks aimed somewhere other than at the boss's own feet get one. A whirlwind or a
## slam is read from the boss's body; a meteor falling on you, or lances fanning towards you,
## cannot be - that is the whole reason these exist.
##
## Kinds (BossDatabase `tell`):
##   meteor        a fireball falling out of the sky, its shadow growing under it
##   ice_spikes    ice spikes pushing up through the zone, nearest the boss first
##   root_spikes   the same in roots - the treant's aftershocks
##   light_walls   a wall of light rising along each arm of a cross
##   leap_shadow   the treant's shadow growing where it will land, roots twitching
##   dust          dust kicked up along the line a charge is about to run

const SHADOW_SHADER: Shader = preload("res://assets/shaders/boss_tell_shadow.gdshader")
const LIGHT_WALL_SHADER: Shader = preload("res://assets/shaders/boss_tell_light_wall.gdshader")
const DUST_TEXTURE := "res://assets/vfx/volcano_smoke_puff.png"
## Hard caps, so a giant ring cannot grow a forest of spikes.
const MAX_SPIKES := 70
## How long the tell outlives the hit, so spikes can shatter and the light can fade.
const LINGER := 0.4

var kind: String = ""
var _desc: Dictionary = {}
var _duration: float = 1.0
var _elapsed: float = 0.0
var _frozen: bool = false

var _spikes: Array[Dictionary] = []
var _fireball: Node3D = null
var _fireball_from: Vector3 = Vector3.ZERO
var _shadow: MeshInstance3D = null
var _shadow_material: ShaderMaterial = null
## Each wall's pivot, which sits on the ground - scaling it grows the wall up from its base.
var _walls: Array[Node3D] = []
var _wall_material: ShaderMaterial = null
var _dust: GPUParticles3D = null


## Builds the tell `desc["tell"]` names, or returns null when the description has none.
static func spawn(scene: Node, desc: Dictionary) -> BossTell:
	var tell_kind: String = String(desc.get("tell", ""))
	if tell_kind == "" or scene == null:
		return null
	var tell := BossTell.new()
	tell.kind = tell_kind
	tell._desc = desc
	tell._duration = maxf(float(desc.get("windup", 1.0)), 0.05)
	scene.add_child(tell)
	tell.global_position = desc.get("at", Vector3.ZERO)
	tell.rotation.y = float(desc.get("yaw", 0.0))
	tell._build()
	tell._apply(0.0)
	return tell


## Holds the tell at `progress` of its windup - for screenshots, which want a moment, not a clip.
func freeze_at(progress: float) -> void:
	_frozen = true
	_elapsed = _duration * progress
	_apply(progress)


func _build() -> void:
	match kind:
		"meteor":
			_build_shadow(float(_desc.get("radius", 3.0)), Color(0.05, 0.02, 0.0))
			_build_fireball()
		"ice_spikes":
			_build_spikes(_ice_material(), 1.6, 0.3)
		"root_spikes":
			_build_spikes(_root_material(), 1.2, 0.28, 40)
		"light_walls":
			_build_light_wall()
		"leap_shadow":
			_build_shadow(float(_desc.get("radius", 5.0)) * 0.85, Color(0.02, 0.05, 0.01))
			_build_spikes(_root_material(), 0.9, 0.28, 12)
		"dust":
			_build_dust()


func _process(delta: float) -> void:
	if _frozen:
		return
	_elapsed += delta
	_apply(clampf(_elapsed / _duration, 0.0, 1.0))
	if _elapsed >= _duration + LINGER:
		queue_free()


## Everything a tell shows is a function of how far through the windup it is, so it can be
## frozen at any moment and looks the same on every peer at the same moment.
func _apply(progress: float) -> void:
	var after: float = clampf((_elapsed - _duration) / LINGER, 0.0, 1.0)
	for spike: Dictionary in _spikes:
		var node: Node3D = spike["node"]
		var start: float = float(spike["t"]) * 0.6
		var grow: float = clampf((progress - start) / 0.4, 0.0, 1.0)
		grow = 1.0 - pow(1.0 - grow, 3.0)
		var shrink: float = 1.0 - after
		var h: float = maxf(0.03, grow * shrink)
		node.scale = Vector3(lerpf(0.3, 1.0, grow), h, lerpf(0.3, 1.0, grow)) * float(spike["size"])
	if _fireball != null:
		var fall: float = progress * progress
		_fireball.global_position = _fireball_from.lerp(global_position + Vector3(0.0, 0.4, 0.0), fall)
		_fireball.visible = progress < 1.0
	if _shadow_material != null:
		var reach: float = lerpf(0.3, 1.0, progress)
		_shadow.scale = Vector3(reach, 1.0, reach)
		_shadow_material.set_shader_parameter("strength", lerpf(0.15, 0.8, progress) * (1.0 - after))
	if _wall_material != null:
		var rise: float = 1.0 - pow(1.0 - progress, 2.0)
		for pivot: Node3D in _walls:
			pivot.scale = Vector3(1.0, maxf(rise, 0.02), 1.0)
		_wall_material.set_shader_parameter("intensity", lerpf(0.35, 1.6, progress) * (1.0 - after))
	if _dust != null:
		_dust.emitting = progress < 1.0


# --- builders ------------------------------------------------------------------------

func _ice_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.92, 1.0, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic_specular = 0.9
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.65, 1.0)
	mat.emission_energy_multiplier = 0.9
	mat.rim_enabled = true
	mat.rim = 0.8
	return mat


func _root_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.16)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.6, 0.15)
	mat.emission_energy_multiplier = 0.45
	return mat


## Spikes scattered over the zone the description draws, each with a `t` - how far along the
## fill it sits - so the ones nearest the boss break the ground first and the wave of them
## shows which way the hit is coming.
func _build_spikes(material: Material, height_scale: float, base_radius: float, cap: int = MAX_SPIKES) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = base_radius
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = material
	var rng := RandomNumberGenerator.new()
	# Seeded off the spot, so two peers drawing the same tell scatter the same spikes.
	rng.seed = hash(Vector3i(global_position.round()))
	var radius: float = float(_desc.get("radius", 5.0))
	var inner: float = float(_desc.get("inner_radius", 0.0))
	var points: Array[Vector3] = []
	match int(_desc.get("shape", AttackIndicator.Shape.CIRCLE)):
		AttackIndicator.Shape.LINE:
			var length: float = float(_desc.get("length", 5.0))
			var width: float = float(_desc.get("width", 1.0))
			var along: float = 0.8
			while along < length and points.size() < cap:
				points.append(Vector3(rng.randf_range(-0.3, 0.3) * width, along / length, along))
				along += rng.randf_range(0.7, 1.1)
		AttackIndicator.Shape.RING:
			var count: int = mini(cap, int(PI * (radius * radius - inner * inner) / 2.6))
			for _i: int in range(count):
				var r: float = sqrt(rng.randf_range(inner * inner, radius * radius))
				var a: float = rng.randf() * TAU
				points.append(Vector3(sin(a) * r, (r - inner) / maxf(radius - inner, 0.01), cos(a) * r))
		_:
			var count: int = mini(cap, int(PI * radius * radius / 3.0))
			for _i: int in range(count):
				var r: float = sqrt(rng.randf()) * radius * 0.9
				var a: float = rng.randf() * TAU
				points.append(Vector3(sin(a) * r, r / maxf(radius, 0.01), cos(a) * r))
	for point: Vector3 in points:
		var spike := MeshInstance3D.new()
		spike.mesh = mesh
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pivot := Node3D.new()
		pivot.position = Vector3(point.x, 0.0, point.z)
		pivot.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		# The cone stands on its base: lift it half its height inside the scaled pivot.
		spike.position.y = 0.5
		pivot.add_child(spike)
		add_child(pivot)
		_spikes.append({"node": pivot, "t": clampf(point.y, 0.0, 1.0), "size": rng.randf_range(0.7, 1.4) * height_scale})


func _build_shadow(radius: float, color: Color) -> void:
	_shadow = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	_shadow.mesh = plane
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADOW_SHADER
	_shadow_material.set_shader_parameter("shadow_color", color)
	_shadow.material_override = _shadow_material
	_shadow.position.y = 0.05
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func _build_fireball() -> void:
	_fireball = Node3D.new()
	add_child(_fireball)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.12)
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireball.add_child(core)
	# Wrapped in the same flame the fire spells use, so it reads as burning rock, not a ball.
	var flame: GPUParticles3D = EmberFx.build_flame(0.9, 28)
	_fireball.add_child(flame)
	var trail: GPUParticles3D = EmberFx.build_trail(40)
	_fireball.add_child(trail)
	var light: OmniLight3D = EmberFx.build_fire_light(6.0, 2.0)
	_fireball.add_child(light)
	# Falls in at a shallow angle rather than straight down, so the streak crosses the view from
	# a camera behind the player instead of happening somewhere overhead.
	_fireball_from = global_position + Vector3(12.0, 20.0, 6.0).rotated(Vector3.UP, rotation.y)


## A wall of light standing along the arm the description draws.
func _build_light_wall() -> void:
	_wall_material = ShaderMaterial.new()
	_wall_material.shader = LIGHT_WALL_SHADER
	_wall_material.set_shader_parameter("tint", _desc.get("tint", Color(1.0, 0.95, 0.6)))
	var length: float = float(_desc.get("length", 16.0))
	var height: float = 4.5
	var quad := QuadMesh.new()
	quad.size = Vector2(length, height)
	var wall := MeshInstance3D.new()
	wall.mesh = quad
	wall.material_override = _wall_material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Standing on the ground, along the arm: the quad's X onto the arm's Z, and lifted half its
	# height inside a pivot on the ground, so scaling the pivot grows it up out of the earth.
	var pivot := Node3D.new()
	pivot.rotation.y = PI * 0.5
	wall.position = Vector3(0.0, height * 0.5, 0.0)
	pivot.add_child(wall)
	add_child(pivot)
	_walls.append(pivot)


func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = 48
	_dust.lifetime = 0.9
	_dust.local_coords = false
	# A soft puff, not a bare quad - without a texture every particle is a hard square.
	var puff: Texture2D = load(DUST_TEXTURE) as Texture2D if ResourceLoader.exists(DUST_TEXTURE) else null
	_dust.draw_pass_1 = EmberFx.particle_mesh(1.1, puff, false)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.8, 0.1, 0.6)
	process.direction = Vector3(0.0, 0.25, 1.0)
	process.spread = 18.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0.0, -1.5, 0.0)
	process.damping_min = 2.0
	process.damping_max = 3.0
	process.scale_min = 0.7
	process.scale_max = 1.6
	process.color = Color(0.58, 0.52, 0.44, 0.55)
	_dust.process_material = process
	# Already kicking up dust the moment the charge is telegraphed, not a beat later.
	_dust.preprocess = 0.6
	_dust.position = Vector3(0.0, 0.3, 0.6)
	add_child(_dust)
