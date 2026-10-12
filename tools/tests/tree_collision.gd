extends Node
## Regression test: does every tree's collision stand on its trunk?
##
## Each tree wrapper scene's cylinder is compared with the trunk fit for its mesh
## (tools/nature/trunk_collision.gd) - the same fit the nature builder and
## tools/fit_tree_collision.gd write. A scene rebuilt some other way, or edited by hand, shows
## up here as a cylinder somewhere the trunk is not. The fit replaced cylinders that stood at
## the canopy's centre, up to three metres from the trunk, and 12 m wide "hulls" round the
## landmark trees.
##
## Run with:  godot --headless --path . res://tools/tests/tree_collision.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const TrunkCollision = preload("res://tools/nature/trunk_collision.gd")
const SCENE_DIR := "res://assets/nature/scenes/"
const SPECIES_DIR := "res://tools/nature/blender/species/"
const MANIFEST := "res://tools/nature/nature_assets.json"
## How far the stored cylinder may stand from the fit at the ground and at head height.
const TOLERANCE_M := 0.05

var _failures: Array[String] = []
var _radii: Dictionary = {}


func _ready() -> void:
	_collect_radii(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)))
	var trees: int = 0
	for file_name: String in DirAccess.get_files_at(SCENE_DIR):
		if file_name.ends_with(".tscn") and _check(file_name):
			trees += 1
	if trees < 11:
		_failures.append("only %d tree scenes found - the bark material naming changed?" % trees)
	if _failures.is_empty():
		print("TEST RESULT: PASS (%d trees)" % trees)
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


## False for a scene that is not a tree with collision.
func _check(file_name: String) -> bool:
	var root: Node3D = (load(SCENE_DIR + file_name) as PackedScene).instantiate()
	var shape_node: CollisionShape3D = root.get_node_or_null("Body/Shape")
	var mesh_node: MeshInstance3D = root.get_node_or_null("Mesh")
	if shape_node == null or mesh_node == null:
		root.free()
		return false
	var id: String = file_name.get_basename()
	var base_id: String = id.left(id.rfind("_v")) if id.rfind("_v") > 0 else id
	var recipe_path: String = SPECIES_DIR + base_id + ".json"
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipe_path)) if FileAccess.file_exists(recipe_path) else {}
	var fitted: Dictionary = TrunkCollision.fit(mesh_node.mesh, float(_radii.get(base_id, 0.0)), recipe if recipe is Dictionary else {})
	var stored_shape := shape_node.shape as CylinderShape3D
	var stored: Transform3D = shape_node.transform
	root.free()
	if fitted.is_empty():
		return false
	var shape: CylinderShape3D = fitted["shape"]
	var xform: Transform3D = fitted["transform"]
	if stored_shape == null or absf(stored_shape.radius - shape.radius) > 0.01 or absf(stored_shape.height - shape.height) > 0.05:
		_failures.append("%s: cylinder is r %.2f h %.2f, its trunk wants r %.2f h %.2f" % [
			id, stored_shape.radius if stored_shape else -1.0, stored_shape.height if stored_shape else -1.0, shape.radius, shape.height])
	# Compare where each cylinder's axis passes the ground and head height.
	for height: float in [0.0, 1.8]:
		var off: float = _axis_at(stored, height).distance_to(_axis_at(xform, height))
		if off > TOLERANCE_M:
			_failures.append("%s: collision is %.2f m off the trunk at %.1f m up" % [id, off, height])
	return true


func _axis_at(xform: Transform3D, height: float) -> Vector2:
	var axis: Vector3 = xform.basis.y.normalized()
	var point: Vector3 = xform.origin + axis * ((height - xform.origin.y) / axis.y)
	return Vector2(point.x, point.z)


func _collect_radii(node: Variant) -> void:
	if node is Dictionary:
		if node.has("id") and node.has("trunk_radius_m"):
			_radii[String(node["id"])] = float(node["trunk_radius_m"])
		for value: Variant in node.values():
			_collect_radii(value)
	elif node is Array:
		for value: Variant in node:
			_collect_radii(value)
