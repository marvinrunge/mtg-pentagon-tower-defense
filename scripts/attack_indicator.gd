extends Node3D
class_name AttackIndicator
## Ground decal marking the danger zone of a telegraphed (dodgeable) attack.
##
## PROJECTED onto whatever is under it - slopes, steps, rocks - rather than drawn on a flat
## plane, which the rising ground used to swallow. It is one box around the zone and
## assets/shaders/boss_telegraph.gdshader, which reads the depth buffer and draws the shape on
## the real surface (see ground_projection.gdshaderinc for why it is not Godot's Decal node).
##
## A brighter "fill" grows over the windup; the fill reaching the edge is the moment the hit
## lands, which is what makes the attack readable enough to dodge.
##
## Spawned as a child of the attacking enemy so it tracks that enemy's position and facing;
## pass the enemy's own scale as owner_scale so the radius stays in world units regardless of
## how large the boss is scaled. spawn_world() is the other way in: a telegraph pinned to a
## spot on the ground, for attacks aimed at where a player stands rather than at the boss.
##
## How the fill grows is part of what the shape SAYS, so it differs per shape:
##   CIRCLE, CONE  from the centre outwards
##   RING          from the inner edge outwards - the safe middle never lights up,
##                 which is the whole message of a ring
##   LINE          from its origin along its length, so a charge reads as travelling

enum Shape { CIRCLE, CONE, RING, LINE }

## How a telegraph is drawn - GameSettings.attack_indicator_style, chosen in the options:
##   themed   a glowing rim plus a pattern in the boss's colour (embers, frost, roots, runes, smoke)
##   rim      a glowing rim, a faint interior and a bright front sweeping through it
##   late     the rim style, but hidden for the first half of the windup
##   classic  the original look: a flat translucent zone and a brighter fill growing through it
const STYLES: Array[String] = ["themed", "rim", "late", "classic"]
const _SHADER_STYLE := {"classic": 0, "rim": 1, "themed": 2, "late": 3}
## Boss colour -> the shader's pattern. A telegraph with no colour (Lightning Bolt's) has none.
const _PATTERNS := {"Red": 1, "Blue": 2, "Green": 3, "White": 4, "Black": 5}
const TELEGRAPH_SHADER: Shader = preload("res://assets/shaders/boss_telegraph.gdshader")
## The projection volume reaches this far above and below the telegraph's origin. Matches the
## shader's projection_up / projection_down, which fade the mark out at the same heights.
const PROJECT_UP := 3.0
const PROJECT_DOWN := 6.0

var _duration: float = 1.0
var _elapsed: float = 0.0
var _radius: float = 1.0
var _shape: Shape = Shape.CIRCLE
var _inner_radius: float = 0.0
## Resolves itself when the fill completes rather than waiting to be told. Every
## networked boss telegraph does this, on every peer, off the same windup the server
## used - the server holding the reference and calling resolve() works on one machine
## and leaves a permanent decal on every other one (see MainController._build_bolt_telegraph).
var _auto_resolve: bool = false
## The one material the whole telegraph is drawn with.
var _shader_material: ShaderMaterial = null

static func spawn(
	parent: Node3D,
	shape: Shape,
	radius: float,
	angle_degrees: float,
	windup_duration: float,
	tint: Color,
	owner_scale: float = 1.0
) -> AttackIndicator:
	return spawn_shape(parent, {
		"shape": shape, "radius": radius, "angle": angle_degrees,
	}, windup_duration, tint, owner_scale)


## Every shape, described by a dictionary so a networked telegraph can travel as one:
##   shape          Shape
##   radius         circle/cone/ring outer radius
##   inner_radius   ring only - the safe middle
##   angle          cone only, in degrees
##   length, width  line only. Opens along +Z from the origin, or both ways from it
##                  when `centered` is true (the arms of a cross)
##   palette        the boss's colour, which picks the themed style's pattern
##   style          one of STYLES, overriding GameSettings.attack_indicator_style
static func spawn_shape(
	parent: Node3D,
	params: Dictionary,
	windup_duration: float,
	tint: Color,
	owner_scale: float = 1.0,
	auto_resolve: bool = false
) -> AttackIndicator:
	if not GameSettings.show_attack_indicators:
		return null
	var indicator := AttackIndicator.new()
	indicator._duration = maxf(windup_duration, 0.05)
	indicator._radius = float(params.get("radius", 1.0))
	indicator._auto_resolve = auto_resolve
	parent.add_child(indicator)
	# Undo the boss's own model scale so `radius` means world units. No lift off the ground any
	# more: the mark is projected onto the surface, so there is nothing to z-fight with.
	var inverse_scale: float = 1.0 / maxf(owner_scale, 0.01)
	indicator.scale = Vector3.ONE * inverse_scale
	indicator._build_from(params, tint)
	return indicator


## A telegraph standing on its own at `at`, turned to `yaw`, rather than riding on the
## attacker. It owns its anchor and frees it after the resolve flash, so nothing has
## to come back and clean it up - which matters on a client, where nothing would.
static func spawn_world(
	scene: Node,
	at: Vector3,
	yaw: float,
	params: Dictionary,
	windup_duration: float,
	tint: Color
) -> AttackIndicator:
	if not GameSettings.show_attack_indicators or scene == null:
		return null
	var anchor := Node3D.new()
	anchor.name = "BossTelegraph"
	scene.add_child(anchor)
	anchor.global_position = at
	anchor.rotation.y = yaw
	var indicator: AttackIndicator = spawn_shape(anchor, params, windup_duration, tint, 1.0, true)
	indicator.tree_exited.connect(anchor.queue_free)
	return indicator


func _build_from(params: Dictionary, tint: Color) -> void:
	_shape = int(params.get("shape", Shape.CIRCLE)) as Shape
	_radius = float(params.get("radius", 1.0))
	_inner_radius = clampf(float(params.get("inner_radius", 0.0)), 0.0, _radius * 0.95)
	var style: String = String(params.get("style", GameSettings.attack_indicator_style))
	var length: float = float(params.get("length", _radius))
	var width: float = float(params.get("width", 1.0))
	var centered: bool = bool(params.get("centered", false))
	var sweep: float = TAU if _shape == Shape.CIRCLE else deg_to_rad(float(params.get("angle", 360.0)))

	# The projection volume: the zone's footprint, from PROJECT_DOWN below to PROJECT_UP above.
	# Nothing outside it can receive the mark, so it is kept tight to the shape.
	var box := BoxMesh.new()
	var footprint_center := Vector3.ZERO
	if _shape == Shape.LINE:
		box.size = Vector3(width, PROJECT_UP + PROJECT_DOWN, length)
		footprint_center.z = 0.0 if centered else length * 0.5
	else:
		box.size = Vector3(_radius * 2.0, PROJECT_UP + PROJECT_DOWN, _radius * 2.0)
	var volume := MeshInstance3D.new()
	volume.name = "Telegraph"
	volume.mesh = box
	volume.position = footprint_center + Vector3(0.0, (PROJECT_UP - PROJECT_DOWN) * 0.5, 0.0)
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = TELEGRAPH_SHADER
	var shape_code: int = 0
	match _shape:
		Shape.CONE:
			shape_code = 1
		Shape.RING:
			shape_code = 2
		Shape.LINE:
			shape_code = 3
	var values: Dictionary = {
		"tint": tint, "shape": shape_code, "radius": _radius, "inner_radius": _inner_radius,
		"half_angle": sweep * 0.5, "line_length": length, "line_width": width, "centered": centered,
		"style": int(_SHADER_STYLE.get(style, 2)), "pattern": int(_PATTERNS.get(String(params.get("palette", "")), 0)),
		"progress": 0.0, "flash": 0.0, "fade": 1.0,
		# The box sits offset inside this node, but the shape is anchored on the node's own
		# origin - the shader adds this back so it measures from there.
		"projection_offset": volume.position,
		"projection_up": PROJECT_UP, "projection_down": PROJECT_DOWN,
	}
	for key: String in values:
		_shader_material.set_shader_parameter(key, values[key])
	volume.material_override = _shader_material
	add_child(volume)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if _shader_material:
		_shader_material.set_shader_parameter("progress", progress)
	if _auto_resolve and progress >= 1.0:
		resolve()

## Called when the hit actually lands - flashes and fades out rather than vanishing, so the
## player can see what area was struck.
func resolve() -> void:
	set_process(false)
	if _shader_material == null:
		queue_free()
		return
	_shader_material.set_shader_parameter("progress", 1.0)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _shader_material.set_shader_parameter("flash", v), 1.0, 0.0, 0.25)
	tween.parallel().tween_method(func(v: float) -> void: _shader_material.set_shader_parameter("fade", v), 1.0, 0.0, 0.3)
	tween.tween_callback(queue_free)

## Cancelled before resolving (the attacker died or was interrupted mid-windup).
func cancel() -> void:
	set_process(false)
	queue_free()
