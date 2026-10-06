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
var _disc_material: StandardMaterial3D


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


func _build_visual() -> void:
	var tint: Color = Color(1.0, 0.32, 0.06) if style == "fire" else Color(0.55, 0.85, 1.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _ring_mesh(inner_radius, radius) if inner_radius > 0.0 else _ring_mesh(0.0, radius)
	_disc_material = StandardMaterial3D.new()
	_disc_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.42)
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_disc_material.emission_enabled = true
	_disc_material.emission = tint
	_disc_material.emission_energy_multiplier = 1.4
	_disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material_override = _disc_material
	mesh.position.y = 0.06
	add_child(mesh)

	if style == "fire":
		var fire: GPUParticles3D = EmberFx.build_ground_fire(radius)
		fire.amount = 22
		add_child(fire)
		_light = EmberFx.build_fire_light(radius * 1.8, 1.4)
		_light.position = Vector3(0.0, 0.7, 0.0)
		add_child(_light)

	# Rolls in rather than popping on, the way DoTZone's firestorm does.
	scale = Vector3(0.4, 1.0, 0.4)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _ring_mesh(inner: float, outer: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var segments: int = 40
	var step: float = TAU / float(segments)
	for i in range(segments):
		var a0: float = step * i
		var a1: float = step * (i + 1)
		var o0 := Vector3(sin(a0) * outer, 0.0, cos(a0) * outer)
		var o1 := Vector3(sin(a1) * outer, 0.0, cos(a1) * outer)
		if inner <= 0.0:
			vertices.append_array([Vector3.ZERO, o0, o1])
			continue
		var i0 := Vector3(sin(a0) * inner, 0.0, cos(a0) * inner)
		var i1 := Vector3(sin(a1) * inner, 0.0, cos(a1) * inner)
		vertices.append_array([i0, o0, o1, i0, o1, i1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _light != null:
		_flicker_phase += delta
		EmberFx.flicker(_light, _flicker_phase)
	# Fades over its last half second so the edge of safety is visible coming.
	if _life < 0.5 and _disc_material != null:
		_disc_material.albedo_color.a = 0.42 * (_life / 0.5)

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
