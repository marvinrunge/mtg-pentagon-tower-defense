extends Node
## Fits the five mana well models (assets/structures/mana-well-<colour>) for the game and
## finds the magical surface in each basin. tools/build_mana_wells.py turns what it writes
## into scenes/mana_wells/*.tscn.
##
## For each well:
##   SIZE      scaled uniformly to WELL_WIDTH across its wider side and centred on the
##             well's origin - Meshy's models come at whatever size it likes.
##   SURFACE   the highest level the basin holds without spilling, less a margin: a
##             horizontal slice through the model at that height is flooded from the
##             basin's centre, cell by cell, and the level is too high once the flood
##             reaches the edge of the grid. Slices rather than a heightfield seen from
##             above, so the roots arching over the black well and the leaves of the green
##             one do not count as walls - only what stands at that height does. The
##             flooded cells become the surface mesh, saved beside the model.
##   GROUND    the terrain height under each well in main.tscn, so the model's base can be
##             stood on it.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . res://tools/tests/fit_mana_wells.tscn -- <out.json>

const COLOURS: Array[String] = ["white", "blue", "black", "red", "green"]
const LANES: Dictionary = {"white": "White", "blue": "Blue", "black": "Black", "red": "Red", "green": "Green"}
## The well across its wider side, in metres. Myrs harvest at myr_well_slot_radius (2.3 m),
## so the base keeps inside about 1.6 m of the centre.
const WELL_WIDTH := 3.0
## Flood grid cells across WELL_WIDTH.
const GRID := 96
## The surface sits this far under the spill level, so it never touches the lowest gap.
const MARGIN := 0.07
## The physics layer the fitted models go on: nothing else is on it, so the terrain and the
## map's props never answer these rays.
const FIT_LAYER := 1 << 30
## Where the models are fitted, far above the map.
const FIT_ORIGIN := Vector3(0.0, 2000.0, 0.0)

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/fit_mana_wells.gd").new()
	probe.name = "FitManaWells"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 240:
		return
	_done = true
	_run()


func _run() -> void:
	var scene: Node3D = get_tree().current_scene as Node3D
	var terrain: StaticBody3D = scene.call("_find_collision_body", scene.get_node("TerraBrush"))
	var out: Dictionary = {}
	for colour: String in COLOURS:
		var fit: Dictionary = await _fit(colour)
		var source: Node3D = _mana_source(scene, LANES[colour])
		fit["ground_offset"] = _ground(source.global_position, terrain) - source.global_position.y
		out[colour] = fit
		print("%s: scale %.3f, height %.2f m, surface at %.2f m (spill %.2f, floor %.2f), %d cells, ground %+.2f" % [
			colour, fit.scale, fit.height, fit.level, fit.spill, fit.floor, fit.cells, fit.ground_offset])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "user://mana_wells_fit.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	print("wrote ", path)
	get_tree().quit()


func _mana_source(scene: Node3D, lane: String) -> Node3D:
	for source: Node in get_tree().get_nodes_in_group("mana_sources"):
		if String(source.get_meta("lane_name", "")) == lane:
			return source as Node3D
	push_error("no mana source for " + lane)
	return scene


func _fit(colour: String) -> Dictionary:
	var path := "res://assets/structures/mana-well-%s/mana-well-%s.glb" % [colour, colour]
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(model)

	# Size and centre, from the model's own bounds.
	var box := AABB()
	var first := true
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		var mesh_box: AABB = _relative_transform(mesh, model) * mesh.mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	var scale: float = WELL_WIDTH / maxf(box.size.x, box.size.z)
	var centre := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	# The transform that puts the model's base centre on the well's origin at that size.
	var model_xform := Transform3D(Basis.from_scale(Vector3.ONE * scale), -centre * scale)
	model.transform = model_xform
	holder.global_position = FIT_ORIGIN

	# Its triangles as one collision body on the fit layer, both faces solid.
	var body := StaticBody3D.new()
	body.collision_layer = FIT_LAYER
	body.collision_mask = 0
	holder.add_child(body)
	for mesh: MeshInstance3D in meshes:
		var shape := CollisionShape3D.new()
		var trimesh: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		trimesh.backface_collision = true
		shape.shape = trimesh
		shape.transform = model_xform * _relative_transform(mesh, model)
		body.add_child(shape)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var height: float = box.size.y * scale
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	var floor_y: float = _floor(space, height)
	# The highest level that still holds: a binary search between the floor and the top.
	# Just above the floor may not hold either - where the model is hollow underneath, the
	# slice runs through its inside - so a level that leaks only sends the search down.
	var low: float = floor_y + 0.02
	var high: float = height
	for i: int in 16:
		var mid: float = (low + high) * 0.5
		if _flood(space, mid).is_empty():
			high = mid
		else:
			low = mid
	var spill: float = low
	# Leaves and roots are not one solid wall: a gap a little under the spill level can leak
	# where the level itself held, so step down until the surface's own level holds too.
	var level: float = maxf(spill - MARGIN, floor_y + 0.03)
	var cells: Dictionary = _flood(space, level)
	while cells.is_empty() and level > floor_y + 0.05:
		level -= 0.02
		cells = _flood(space, level)
	if cells.is_empty():
		push_error(colour + ": no level holds - the basin leaks all the way down")
	var surface_path := "res://assets/structures/mana-well-%s/mana-well-%s_surface.tres" % [colour, colour]
	ResourceSaver.save(_surface_mesh(cells), surface_path)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 1:
		_top_view(space, height, cells).save_png(args[1].path_join(colour + "_top.png"))
		# Where a flood leaks, at three heights - to see what it leaks through.
		for f: float in [0.4, 0.6, 0.8]:
			_top_view(space, height, _flood(space, height * f, false)).save_png(args[1].path_join("%s_leak_%d.png" % [colour, int(f * 100)]))
	holder.queue_free()
	return {
		"scale": scale,
		"model_transform": var_to_str(model_xform),
		"height": height,
		"floor": floor_y,
		"spill": spill,
		"level": level,
		"cells": cells.size(),
		"surface_mesh": surface_path,
		"surface_radius": _radius(cells),
	}


## `node`'s transform relative to `ancestor`.
func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at: Node = node
	while at != ancestor and at is Node3D:
		xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


## The basin floor under the centre: the lowest upward-facing surface there, which is the
## inside of the bowl - not whatever arches over it.
func _floor(space: PhysicsDirectSpaceState3D, height: float) -> float:
	var from := FIT_ORIGIN + Vector3(0.0, height + 1.0, 0.0)
	var lowest: float = 0.0
	for i: int in 32:
		var hit: Dictionary = _ray(space, from, FIT_ORIGIN + Vector3(0.0, -1.0, 0.0))
		if hit.is_empty():
			break
		if (hit.normal as Vector3).y > 0.3:
			lowest = (hit.position as Vector3).y - FIT_ORIGIN.y
		from = (hit.position as Vector3) + Vector3(0.0, -0.002, 0.0)
	return lowest


## The cells a flood at height `level` reaches from the centre, keyed Vector2i - or empty if
## it reaches the grid's edge, which means the basin spills at that level.
func _flood(space: PhysicsDirectSpaceState3D, level: float, bounded: bool = true) -> Dictionary:
	var start := Vector2i(GRID / 2, GRID / 2)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if cell.x == 0 or cell.y == 0 or cell.x == GRID - 1 or cell.y == GRID - 1:
			if bounded:
				return {}
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next):
				continue
			if not _ray(space, _cell_point(cell, level), _cell_point(next, level)).is_empty():
				continue
			seen[next] = true
			queue.append(next)
	# A pocket that is a cell or two across is the flood stuck inside a wall, not a basin.
	return seen if seen.size() > 16 else {}


func _cell_point(cell: Vector2i, level: float) -> Vector3:
	var size: float = WELL_WIDTH / float(GRID)
	return FIT_ORIGIN + Vector3((float(cell.x) + 0.5) * size - WELL_WIDTH * 0.5, level, (float(cell.y) + 0.5) * size - WELL_WIDTH * 0.5)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, FIT_LAYER)
	query.hit_back_faces = true
	return space.intersect_ray(query)


## The flooded cells as one flat mesh at y 0 - a quad per run of cells along each row, each
## a little wider than its cells so neighbouring rows overlap rather than leave hairlines.
## UV is the position in metres, for the shader's patterns.
func _surface_mesh(cells: Dictionary) -> ArrayMesh:
	var size: float = WELL_WIDTH / float(GRID)
	var pad: float = size * 0.15
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for row: int in GRID:
		var col: int = 0
		while col < GRID:
			if not cells.has(Vector2i(col, row)):
				col += 1
				continue
			var run_start: int = col
			while col < GRID and cells.has(Vector2i(col, row)):
				col += 1
			var x0: float = float(run_start) * size - WELL_WIDTH * 0.5 - pad
			var x1: float = float(col) * size - WELL_WIDTH * 0.5 + pad
			var z0: float = float(row) * size - WELL_WIDTH * 0.5 - pad
			var z1: float = float(row + 1) * size - WELL_WIDTH * 0.5 + pad
			for corner: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z0), Vector2(x1, z1), Vector2(x0, z1)]:
				st.set_uv(corner)
				st.add_vertex(Vector3(corner.x, 0.0, corner.y))
	st.index()
	return st.commit()


## For checking a fit by eye (second user arg, a folder): the model from straight above,
## brighter where higher, with the flooded cells tinted blue.
func _top_view(space: PhysicsDirectSpaceState3D, height: float, cells: Dictionary) -> Image:
	var image := Image.create(GRID, GRID, false, Image.FORMAT_RGB8)
	for row: int in GRID:
		for col: int in GRID:
			var top: Vector3 = _cell_point(Vector2i(col, row), height + 1.0)
			var hit: Dictionary = _ray(space, top, top - Vector3(0.0, height + 2.0, 0.0))
			var value: float = 0.0 if hit.is_empty() else ((hit.position as Vector3).y - FIT_ORIGIN.y) / height
			var shade := Color(value, value, value)
			if cells.has(Vector2i(col, row)):
				shade = shade.lerp(Color(0.1, 0.4, 1.0), 0.6)
			image.set_pixel(col, row, shade)
	image.resize(GRID * 4, GRID * 4, Image.INTERPOLATE_NEAREST)
	return image


## How far the flooded cells reach from the centre, at most - where the motes rise from.
func _radius(cells: Dictionary) -> float:
	var size: float = WELL_WIDTH / float(GRID)
	var widest: float = 0.0
	for cell: Vector2i in cells:
		var at := Vector2((float(cell.x) + 0.5) * size - WELL_WIDTH * 0.5, (float(cell.y) + 0.5) * size - WELL_WIDTH * 0.5)
		widest = maxf(widest, at.length())
	return widest


## The terrain's height under `at`, stepping through anything else on the ray - see
## scripts/well_crystals.gd.
func _ground(at: Vector3, terrain: StaticBody3D) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z), Vector3(at.x, -200.0, at.z))
	var exclude: Array[RID] = []
	for i: int in 32:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return at.y
		if terrain == null or hit.collider == terrain:
			return (hit.position as Vector3).y
		exclude.append(hit.rid)
	return at.y
