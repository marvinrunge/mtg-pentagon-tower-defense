extends Node3D
class_name AttackIndicator
## Flat ground decal marking the danger zone of a telegraphed (dodgeable) attack.
##
## Two coplanar shapes are drawn: a dim outline covering the whole danger zone,
## and a brighter "fill" that grows from the centre outwards over the windup. The
## fill reaching the outline is the moment the hit lands, which is what makes the
## attack readable enough to dodge.
##
## Spawned as a child of the attacking enemy so it tracks that enemy's position
## and facing; pass the enemy's own scale as owner_scale so the radius stays in
## world units regardless of how large the boss is scaled.

enum Shape { CIRCLE, CONE }

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

static func spawn(
	parent: Node3D,
	shape: Shape,
	radius: float,
	angle_degrees: float,
	windup_duration: float,
	tint: Color,
	owner_scale: float = 1.0
) -> AttackIndicator:
	if not GameSettings.show_attack_indicators:
		return null
	var indicator := AttackIndicator.new()
	indicator._duration = maxf(windup_duration, 0.05)
	indicator._radius = radius
	parent.add_child(indicator)
	# Undo the boss's own model scale so `radius` means world units, and lift the
	# decal just off the ground to avoid z-fighting with the terrain.
	var inverse_scale: float = 1.0 / maxf(owner_scale, 0.01)
	indicator.scale = Vector3.ONE * inverse_scale
	indicator.position = Vector3(0.0, GameSettings.attack_indicator_height * inverse_scale, 0.0)
	indicator._build(shape, radius, angle_degrees, tint)
	return indicator

func _build(shape: Shape, radius: float, angle_degrees: float, tint: Color) -> void:
	var sweep: float = TAU if shape == Shape.CIRCLE else deg_to_rad(angle_degrees)

	_outline_material = _make_material(tint, OUTLINE_ALPHA)
	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = _build_arc_mesh(radius, sweep)
	outline.material_override = _outline_material
	add_child(outline)

	_fill_material = _make_material(tint, FILL_ALPHA)
	_fill_node = MeshInstance3D.new()
	_fill_node.name = "Fill"
	# Same unit mesh as the outline, scaled up over time by _process.
	_fill_node.mesh = _build_arc_mesh(radius, sweep)
	_fill_node.material_override = _fill_material
	_fill_node.scale = Vector3(0.01, 1.0, 0.01)
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
		_fill_node.scale = Vector3(s, 1.0, s)
	if _fill_material:
		# Ramp brightness towards impact so the last moments read as urgent.
		_fill_material.emission_energy_multiplier = lerpf(1.2, 4.0, progress)

## Called by the attacker when the hit actually lands - flashes to full and fades
## out rather than vanishing, so the player can see what area was struck.
func resolve() -> void:
	set_process(false)
	if _fill_node:
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
