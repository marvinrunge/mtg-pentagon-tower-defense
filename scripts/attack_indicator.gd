extends Node3D
class_name AttackIndicator
## Flat ground decal marking the danger zone of a telegraphed (dodgeable) attack.
##
## Two coplanar shapes are drawn: a dim outline covering the whole danger zone,
## and a brighter "fill" that grows over the windup. The fill reaching the outline
## is the moment the hit lands, which is what makes the attack readable enough to
## dodge.
##
## Spawned as a child of the attacking enemy so it tracks that enemy's position
## and facing; pass the enemy's own scale as owner_scale so the radius stays in
## world units regardless of how large the boss is scaled. spawn_world() is the
## other way in: a telegraph pinned to a spot on the ground, for attacks aimed at
## where a player stands rather than at where the boss does.
##
## How the fill grows is part of what the shape SAYS, so it differs per shape:
##   CIRCLE, CONE  from the centre outwards, as they always have
##   RING          from the inner edge outwards - the safe middle never lights up,
##                 which is the whole message of a ring
##   LINE          from its origin along its length, so a charge reads as travelling

enum Shape { CIRCLE, CONE, RING, LINE }

const OUTLINE_ALPHA := 0.22
const FILL_ALPHA := 0.5
## Segments per full circle; a cone uses a proportional slice of this.
const ARC_SEGMENTS := 48

var _outline_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _fill_node: MeshInstance3D
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
	# Undo the boss's own model scale so `radius` means world units, and lift the
	# decal just off the ground to avoid z-fighting with the terrain.
	var inverse_scale: float = 1.0 / maxf(owner_scale, 0.01)
	indicator.scale = Vector3.ONE * inverse_scale
	indicator.position = Vector3(0.0, GameSettings.attack_indicator_height * inverse_scale, 0.0)
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
	_outline_material = _make_material(tint, OUTLINE_ALPHA)
	_fill_material = _make_material(tint, FILL_ALPHA)

	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.material_override = _outline_material
	_fill_node = MeshInstance3D.new()
	_fill_node.name = "Fill"
	_fill_node.material_override = _fill_material

	match _shape:
		Shape.RING:
			outline.mesh = _build_ring_mesh(_inner_radius, _radius)
			_fill_node.mesh = _build_ring_mesh(_inner_radius, _inner_radius + 0.01)
		Shape.LINE:
			var length: float = float(params.get("length", _radius))
			var width: float = float(params.get("width", 1.0))
			var centered: bool = bool(params.get("centered", false))
			outline.mesh = _build_line_mesh(length, width, centered)
			# Same mesh, squeezed along its length and grown back out by _process.
			_fill_node.mesh = _build_line_mesh(length, width, centered)
			_fill_node.scale = Vector3(1.0, 1.0, 0.01)
		_:
			var sweep: float = TAU if _shape == Shape.CIRCLE else deg_to_rad(float(params.get("angle", 360.0)))
			outline.mesh = _build_arc_mesh(_radius, sweep)
			# Same unit mesh as the outline, scaled up over time by _process.
			_fill_node.mesh = _build_arc_mesh(_radius, sweep)
			_fill_node.scale = Vector3(0.01, 1.0, 0.01)
	add_child(outline)
	add_child(_fill_node)

func _make_material(tint: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Ground decals must not occlude the characters standing on them.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

## Triangle fan on the XZ plane, centred on the sweep so a cone is symmetrical
## about the facing direction.
##
## Opens towards +Z, not Godot's usual -Z: enemies in this project are turned with
## `rotation.y = atan2(direction.x, direction.z)`, which points their +Z axis at
## the target. Using -Z here would draw every cone out of the boss's back.
func _build_arc_mesh(radius: float, sweep: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var segments: int = maxi(3, int(round(ARC_SEGMENTS * (sweep / TAU))))
	var start: float = -sweep * 0.5
	var step: float = sweep / float(segments)
	for i in range(segments):
		var a0: float = start + step * i
		var a1: float = start + step * (i + 1)
		var p0 := Vector3(sin(a0) * radius, 0.0, cos(a0) * radius)
		var p1 := Vector3(sin(a1) * radius, 0.0, cos(a1) * radius)
		vertices.append(Vector3.ZERO)
		vertices.append(p0)
		vertices.append(p1)
	return _mesh_from(vertices)

## An annulus: two triangles per segment between the inner and outer circle.
func _build_ring_mesh(inner: float, outer: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var step: float = TAU / float(ARC_SEGMENTS)
	for i in range(ARC_SEGMENTS):
		var a0: float = step * i
		var a1: float = step * (i + 1)
		var i0 := Vector3(sin(a0) * inner, 0.0, cos(a0) * inner)
		var i1 := Vector3(sin(a1) * inner, 0.0, cos(a1) * inner)
		var o0 := Vector3(sin(a0) * outer, 0.0, cos(a0) * outer)
		var o1 := Vector3(sin(a1) * outer, 0.0, cos(a1) * outer)
		vertices.append_array([i0, o0, o1, i0, o1, i1])
	return _mesh_from(vertices)

## A flat rectangle along +Z, `width` across. Centred lines run from -length/2 to
## +length/2, so scaling the fill along Z grows it out from the middle both ways.
func _build_line_mesh(length: float, width: float, centered: bool) -> ArrayMesh:
	var half_w: float = width * 0.5
	var z0: float = -length * 0.5 if centered else 0.0
	var z1: float = length * 0.5 if centered else length
	var a := Vector3(-half_w, 0.0, z0)
	var b := Vector3(half_w, 0.0, z0)
	var c := Vector3(half_w, 0.0, z1)
	var d := Vector3(-half_w, 0.0, z1)
	return _mesh_from(PackedVector3Array([a, b, c, a, c, d]))

func _mesh_from(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _process(delta: float) -> void:
	_elapsed += delta
	var progress: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if _fill_node:
		var s: float = maxf(progress, 0.01)
		match _shape:
			Shape.RING:
				_fill_node.mesh = _build_ring_mesh(_inner_radius, lerpf(_inner_radius + 0.01, _radius, s))
			Shape.LINE:
				_fill_node.scale = Vector3(1.0, 1.0, s)
			_:
				_fill_node.scale = Vector3(s, 1.0, s)
	if _fill_material:
		# Ramp brightness towards impact so the last moments read as urgent.
		_fill_material.emission_energy_multiplier = lerpf(1.2, 4.0, progress)
	if _auto_resolve and progress >= 1.0:
		resolve()

## Called by the attacker when the hit actually lands - flashes to full and fades
## out rather than vanishing, so the player can see what area was struck.
func resolve() -> void:
	set_process(false)
	if _fill_node:
		match _shape:
			Shape.RING:
				_fill_node.mesh = _build_ring_mesh(_inner_radius, _radius)
			_:
				_fill_node.scale = Vector3.ONE
	var tween := create_tween()
	tween.set_parallel(true)
	if _fill_material:
		tween.tween_property(_fill_material, "albedo_color:a", 0.0, 0.22)
		tween.tween_property(_fill_material, "emission_energy_multiplier", 6.0, 0.1)
	if _outline_material:
		tween.tween_property(_outline_material, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(queue_free)

## Cancelled before resolving (the attacker died or was interrupted mid-windup).
func cancel() -> void:
	set_process(false)
	queue_free()
