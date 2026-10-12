extends SceneTree
## Refits the collision cylinder of every tree wrapper scene to its trunk
## (tools/nature/trunk_collision.gd), in place.
##
## For scenes built before the builder measured trunks. It does NOT rebuild them: the
## builder would also rewrite the TerraBrush object resources, which carry hand-tuned
## placement (frequency, size range) the builder knows nothing about. This touches only the
## cylinder's size and the Shape node's transform, as text, so the diff is those lines.
##
## Run with:
##   godot --headless --path . --script res://tools/fit_tree_collision.gd            (dry run)
##   godot --headless --path . --script res://tools/fit_tree_collision.gd -- --write

const TrunkCollision = preload("res://tools/nature/trunk_collision.gd")
const SCENE_DIR := "res://assets/nature/scenes/"
const MANIFEST := "res://tools/nature/nature_assets.json"
const SPECIES_DIR := "res://tools/nature/blender/species/"


func _initialize() -> void:
	var write: bool = OS.get_cmdline_user_args().has("--write")
	var radii: Dictionary = _manifest_trunk_radii()
	var changed: int = 0
	for file_name: String in DirAccess.get_files_at(SCENE_DIR):
		if not file_name.ends_with(".tscn"):
			continue
		var path: String = SCENE_DIR + file_name
		var root: Node3D = (load(path) as PackedScene).instantiate()
		var shape_node: CollisionShape3D = root.get_node_or_null("Body/Shape")
		var mesh_node: MeshInstance3D = root.get_node_or_null("Mesh")
		if shape_node == null or mesh_node == null:
			root.free()
			continue
		var id: String = file_name.get_basename()
		var base_id: String = id.left(id.rfind("_v")) if id.rfind("_v") > 0 else id
		var fitted: Dictionary = TrunkCollision.fit(mesh_node.mesh, float(radii.get(base_id, 0.0)), _recipe(base_id))
		var old: CylinderShape3D = shape_node.shape as CylinderShape3D
		var old_transform: Transform3D = shape_node.transform
		root.free()
		if fitted.is_empty() or old == null:
			continue
		var shape: CylinderShape3D = fitted["shape"]
		var xform: Transform3D = fitted["transform"]
		var axis: Vector3 = xform.basis.y
		var at_ground: Vector3 = xform.origin - axis * (xform.origin.y / axis.y)
		print("%-38s r %.2f -> %.2f  h %4.1f -> %.1f  trunk at (%5.2f, %5.2f), %2d deg lean, was %.2f m off" % [
			id, old.radius, shape.radius, old.height, shape.height, at_ground.x, at_ground.z,
			roundi(rad_to_deg(axis.angle_to(Vector3.UP))), Vector2(at_ground.x, at_ground.z).distance_to(
				Vector2(old_transform.origin.x, old_transform.origin.z))])
		if write and _rewrite(path, shape, xform):
			changed += 1
	if write:
		print("rewrote %d scenes" % changed)
	quit()


## The recipe the tree was grown from, or {} for one that was not.
func _recipe(base_id: String) -> Dictionary:
	var path: String = "%s%s.json" % [SPECIES_DIR, base_id]
	if not FileAccess.file_exists(path):
		return {}
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return recipe if recipe is Dictionary else {}


func _manifest_trunk_radii() -> Dictionary:
	var radii: Dictionary = {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_collect_radii(manifest, radii)
	return radii


func _collect_radii(node: Variant, radii: Dictionary) -> void:
	if node is Dictionary:
		if node.has("id") and node.has("trunk_radius_m"):
			radii[String(node["id"])] = float(node["trunk_radius_m"])
		for value: Variant in node.values():
			_collect_radii(value, radii)
	elif node is Array:
		for value: Variant in node:
			_collect_radii(value, radii)


## The cylinder's two numbers and the Shape node's transform line, replaced in the text.
func _rewrite(path: String, shape: CylinderShape3D, xform: Transform3D) -> bool:
	var text: String = FileAccess.get_file_as_string(path)
	var cylinder := RegEx.create_from_string("(\\[sub_resource type=\"CylinderShape3D\"[^\\]]*\\]\\n)height = [^\\n]*\\nradius = [^\\n]*")
	var shape_node := RegEx.create_from_string("(\\[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"Body\"[^\\]]*\\]\\n)transform = [^\\n]*")
	if cylinder.search(text) == null or shape_node.search(text) == null:
		push_warning("%s: unexpected layout, left alone" % path)
		return false
	text = cylinder.sub(text, "$1height = %s\nradius = %s" % [_num(shape.height), _num(shape.radius)])
	var b: Basis = xform.basis
	var o: Vector3 = xform.origin
	var values: Array = [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, o.x, o.y, o.z]
	text = shape_node.sub(text, "$1transform = Transform3D(%s)" % ", ".join(values.map(_num)))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return true


func _num(value: float) -> String:
	return String.num(snappedf(value, 0.0001))
