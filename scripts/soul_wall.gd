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
var _curtain_material: ShaderMaterial
## Enemies inside the wall right now. Re-marked every tick rather than only on entry, so
## an enemy that stops inside it does not walk out with a mark that started ticking down
## while it was still standing in the wall.
var _tick: float = 0.0

const TICK_INTERVAL := 0.4
const CURTAIN_SHADER := "res://assets/shaders/soul_curtain.gdshader"
## Black's dialect from docs/SPELL_VFX_PLAN.md: violet, low value. Shared by the curtain,
## the souls and the light so all three read as one object.
const CURTAIN_TINT: Color = Color(0.62, 0.25, 0.92)
const HEIGHT := 4.0


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
	box.size = Vector3(_length, HEIGHT, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, 0.0)
	add_child(shape)

	_build_curtain()
	_build_souls()
	_build_haze()
	_build_footprint()

	var light := OmniLight3D.new()
	light.light_color = CURTAIN_TINT
	light.light_energy = 2.2
	light.omni_range = _length * 0.5
	light.position = Vector3(0.0, 1.6, 0.0)
	add_child(light)


## The veil itself. A shader rather than a flat quad, because the thing that has to be
## legible is the LINE ON THE GROUND, and a uniformly bright rectangle puts its emphasis
## everywhere except there. See assets/shaders/soul_curtain.gdshader.
func _build_curtain() -> void:
	_curtain_material = ShaderMaterial.new()
	_curtain_material.shader = load(CURTAIN_SHADER) as Shader
	# Above Sky3D's fog pass - see SpellFx.FX_RENDER_PRIORITY.
	_curtain_material.render_priority = SpellFx.FX_RENDER_PRIORITY
	_curtain_material.set_shader_parameter("tint", CURTAIN_TINT)
	_curtain_material.set_shader_parameter("half_height", HEIGHT * 0.5)
	_curtain_material.set_shader_parameter("fade", 0.0)
	_curtain_material.set_shader_parameter("veil_noise", _veil_noise())

	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain"
	var quad := QuadMesh.new()
	quad.size = Vector2(_length, HEIGHT)
	curtain.mesh = quad
	curtain.material_override = _curtain_material
	curtain.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(curtain)


## Seamless noise, built here rather than imported: it is one channel of drifting cloud,
## which FastNoiseLite describes in five lines and no artist should be asked to paint.
func _veil_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 41172
	noise.frequency = 0.015
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	return texture


## The souls, rising out of the line and thinning as they go.
##
## Drawn with the `mote` texture. They used to be drawn with NO texture at all, which in an
## additive material means literal glowing squares - the single biggest reason the wall
## looked unfinished up close.
func _build_souls() -> void:
	var souls := SpellFx.sparks(CURTAIN_TINT, _length * 0.5, 48, 2.2, "mote")
	souls.name = "Souls"
	# SpellFx.sparks builds a BURST - one shot, everything at once. The wall emits for as
	# long as it stands, so both of those have to come back off.
	souls.one_shot = false
	souls.explosiveness = 0.0
	souls.lifetime = 2.4
	souls.draw_pass_1 = SpellFx.premul_particle_mesh(0.5, "mote")
	var process: ParticleProcessMaterial = souls.process_material
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(_length * 0.5, 0.2, 0.15)
	process.direction = Vector3.UP
	process.spread = 14.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.9
	# Rising, not thrown: souls leaving a body drift up and stop, they do not arc.
	process.gravity = Vector3(0.0, 0.35, 0.0)
	process.damping_min = 0.4
	process.damping_max = 1.2
	add_child(souls)


## The half of black that the plan calls "smoke that eats light": alpha-blended, dark, and
## sitting low. Without it the wall is made only of things that ADD brightness, and a wall
## of pure light is not what black looks like in any other part of the game.
func _build_haze() -> void:
	var haze := GPUParticles3D.new()
	haze.name = "Haze"
	haze.amount = 26
	haze.lifetime = 3.2
	haze.local_coords = false
	haze.draw_pass_1 = EmberFx.particle_mesh(1.6, SpellFx._texture("smoke"), false)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(_length * 0.5, 0.3, 0.25)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.5
	process.gravity = Vector3(0.0, 0.1, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.5
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, Color(0.10, 0.03, 0.16, 0.0))
	ramp.add_point(0.25, Color(0.13, 0.04, 0.20, 0.55))
	ramp.set_offset(2, 1.0)
	ramp.set_color(2, Color(0.05, 0.02, 0.09, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	haze.process_material = process
	haze.position = Vector3(0.0, 0.4, 0.0)
	add_child(haze)


## The blight the wall stands on, stretched into a strip along its length. What the player
## actually aims at when placing the next one, and it stays legible from directly above,
## where the curtain itself is edge-on and nearly invisible.
func _build_footprint() -> void:
	var strip: MeshInstance3D = SpellFx.ground_decal(
		"decal_blight", Color(0.20, 0.06, 0.28, 0.85), _length * 0.5, _life_timer * 0.7)
	# ground_decal builds a square; the wall is a line.
	strip.scale = Vector3(1.0, 1.0, 0.26)
	add_child(strip)
	# The wall is placed by an aim raycast that can land above the floor, and the strip has
	# to be ON the floor either way.
	var grounded: Transform3D = SpellFx.ground_transform(self, global_position)
	strip.global_position = grounded.origin


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	if _life_timer < 1.2 and _curtain_material != null:
		_curtain_material.set_shader_parameter("fade", 1.0 - _life_timer / 1.2)

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
