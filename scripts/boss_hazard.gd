extends Node3D
class_name BossHazard
## Ground a boss leaves behind that hurts or hinders the PLAYERS standing in it - the
## mirror image of DoTZone, which only ever acts on enemies.
##
## A separate class rather than another DoTZone type because nearly every line of that
## one points the other way: its collision mask is the enemy layer, its damage is
## credited to a caster, and fog's suppression is an enemy-only verb. A hazard has no
## caster (the boss may well be dead before it fades) and checks distance against the
## players directly - there are at most five of them, so a physics area buys nothing.
##
## Spawned through MainController.request_effect("boss_hazard"), so every peer builds its
## own copy from the same numbers and sees the same ground. Like every other networked
## zone, only the server's copy deals anything.
##
## Styles:
##   fire   a burning patch - damage over time
##   frost  frozen ground - slows, deals nothing
## Either may be a disc or, with `inner_radius` > 0, a ring.

const TICK_INTERVAL := 0.5

var style: String = "fire"
var radius: float = 2.5
var inner_radius: float = 0.0
var duration: float = 4.0
## Already scaled for the party size and the boss's own damage by whoever spawned it.
var dps: float = 0.0
## Seconds of slow re-applied every tick to anyone inside. Short and refreshed rather than
## long and applied once, so walking out frees the player within a tick.
var slow_seconds: float = 0.0

var _life: float = 0.0
var _tick: float = 0.0
var _light: OmniLight3D
var _flicker_phase: float = 0.0
var _material: ShaderMaterial


static func create(p_style: String, p_radius: float, p_inner: float, p_duration: float, p_dps: float, p_slow: float) -> BossHazard:
	var hazard := BossHazard.new()
	hazard.style = p_style
	hazard.radius = p_radius
	hazard.inner_radius = clampf(p_inner, 0.0, p_radius * 0.95)
	hazard.duration = p_duration
	hazard.dps = p_dps
	hazard.slow_seconds = p_slow
	return hazard


func _ready() -> void:
	name = "BossHazard"
	_life = duration
	_build_visual()


const HAZARD_SHADER: Shader = preload("res://assets/shaders/boss_hazard.gdshader")


func _build_visual() -> void:
	var tint: Color = Color(1.0, 0.32, 0.06) if style == "fire" else Color(0.55, 0.85, 1.0)
	# Projected onto the ground it fell on, like the telegraphs: a box around the patch and the
	# hazard shader, rather than a flat disc the slope buries.
	var box := BoxMesh.new()
	box.size = Vector3(radius * 2.0, AttackIndicator.PROJECT_UP + AttackIndicator.PROJECT_DOWN, radius * 2.0)
	var volume := MeshInstance3D.new()
	volume.mesh = box
	volume.position.y = (AttackIndicator.PROJECT_UP - AttackIndicator.PROJECT_DOWN) * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = HAZARD_SHADER
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("inner_radius", inner_radius)
	_material.set_shader_parameter("style", 0 if style == "fire" else 1)
	_material.set_shader_parameter("projection_offset", volume.position)
	_material.set_shader_parameter("projection_up", AttackIndicator.PROJECT_UP)
	_material.set_shader_parameter("projection_down", AttackIndicator.PROJECT_DOWN)
	volume.material_override = _material
	add_child(volume)

	if style == "fire":
		var fire: GPUParticles3D = EmberFx.build_ground_fire(radius)
		fire.amount = 22
		add_child(fire)
		_light = EmberFx.build_fire_light(radius * 1.8, 1.4)
		_light.position = Vector3(0.0, 0.7, 0.0)
		add_child(_light)

	# Fades in rather than popping on.
	_material.set_shader_parameter("fade", 0.0)
	create_tween().tween_method(func(v: float) -> void: _material.set_shader_parameter("fade", v), 0.0, 1.0, 0.3)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _light != null:
		_flicker_phase += delta
		EmberFx.flicker(_light, _flicker_phase)
	# Fades over its last half second so the edge of safety is visible coming.
	if _life < 0.5 and _material != null:
		_material.set_shader_parameter("fade", _life / 0.5)

	if not Net.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_INTERVAL
	for player: Node3D in players_inside():
		if dps > 0.0 and player.has_method("take_damage"):
			player.take_damage(dps * TICK_INTERVAL, null, false)
		if slow_seconds > 0.0 and player.has_method("apply_slow"):
			player.apply_slow(slow_seconds)


## Living players whose feet are on this ground. Public so a test can ask the question
## without waiting out a tick.
func players_inside() -> Array[Node3D]:
	var inside: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not is_instance_valid(player):
			continue
		if "is_downed" in player and player.is_downed:
			continue
		var offset: Vector3 = player.global_position - global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist <= radius and dist >= inner_radius:
			inside.append(player)
	return inside
