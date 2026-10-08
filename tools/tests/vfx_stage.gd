extends Node3D
## A light stand-in for main.tscn that the effect render tools build their shots on.
##
## Loading the real map for a screenshot costs minutes on a software renderer: TerraBrush's
## terrain and its clipmap shader, the navmesh bake, Sky3D's sky and fog, the HUD and the
## first wave all come up before a single effect is placed, and every frame after that draws
## all of it again. None of it is what an effect shot is judging. This is just enough world
## to judge an effect against: a sky, a sun that casts shadows, ground with some texture to
## it, a hill for anything that has to lie on a slope (STAGE_HILL), and a few standing stones
## for scale.
##
## A shot tool's scene root uses a script that `extends "res://tools/tests/vfx_stage.gd"`,
## calls build_stage() in _ready, waits ready_frames(), then shoots. Being the current scene
## it also stands in for the two MainController calls effects make on it - request_effect and
## request_enemy - by building the node locally, which is all single-player does anyway.
##
## Lit for mid-afternoon. `--glow` among the user args turns on the game's bloom.

## The flat middle of the stage. Effects that want flat ground go here.
const STAGE := Vector3(0.0, 0.0, 0.0)
## The top of the hill, about 4 m up with slopes falling away on every side.
const STAGE_HILL := Vector3(-22.0, 0.0, 6.0)
const HILL_HEIGHT := 4.0
const HILL_RADIUS := 11.0
## Wide enough that no shot sees its edge against the sky.
const GROUND_SIZE := 240.0

var environment: Environment = null
var sun: DirectionalLight3D = null


func build_stage() -> void:
	_build_environment()
	_build_ground()
	_build_hill()
	_build_stones()
	for holder: String in ["Enemies", "Effects"]:
		var node := Node3D.new()
		node.name = holder
		add_child(node)


## Frames to wait after build_stage() before shooting: physics needs a few steps before a
## fresh static body answers ray queries, and the noise texture is generated on a thread.
func ready_frames() -> int:
	return 12


## The ground height under `xz` - flat at 0 everywhere but the hill.
func ground_at(xz: Vector2) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 50.0, xz.y), Vector3(xz.x, -50.0, xz.y))
	query.collision_mask = EnemyBase.ENVIRONMENT_LAYER
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get("position", Vector3(xz.x, 0.0, xz.y))


# --- MainController's spawning, for effects that ask the scene for it --------------------

func request_effect(info: Dictionary) -> Node3D:
	var node: Node3D = null
	match String(info.get("kind", "")):
		"boss_hazard":
			node = BossHazard.create(
				String(info["style"]), float(info["radius"]), float(info.get("inner_radius", 0.0)),
				float(info["duration"]), float(info.get("dps", 0.0)), float(info.get("slow", 0.0)))
		"dot_zone":
			var zone := DoTZone.new()
			zone.setup(String(info["type"]), float(info["radius"]), float(info["dps"]), float(info["duration"]), null)
			node = zone
	if node == null:
		return null
	get_node("Effects").add_child(node)
	node.global_position = info.get("position", Vector3.ZERO)
	return node


func request_enemy(info: Dictionary) -> Node3D:
	var enemy: Node3D = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.position = info.get("position", Vector3.ZERO)
	# The same metadata MainController._spawn_enemy sets.
	if String(info.get("elite", "")) != "":
		enemy.set_meta("elite_modifier", String(info["elite"]))
	if String(info.get("boss_modifier", "")) != "":
		enemy.set_meta("boss_modifier", String(info["boss_modifier"]))
	for flag: String in ["miniboss", "sapling"]:
		if bool(info.get(flag, false)):
			enemy.set_meta(flag, true)
	enemy.set_meta("enemy_color", String(info["color"]))
	enemy.set_meta("enemy_type", String(info["type"]))
	get_node("Enemies").add_child(enemy)
	return enemy


# --- building it --------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.78, 0.84)
	# Below the horizon the sky is what shows past the ground's edge: keep it ground-coloured.
	sky_material.ground_horizon_color = Color(0.5, 0.58, 0.44)
	sky_material.ground_bottom_color = Color(0.4, 0.48, 0.34)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	if OS.get_cmdline_user_args().has("--glow"):
		GraphicsSettings.configure_glow(environment, true)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _ground_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.26, 0.14))
	ramp.set_color(1, Color(0.36, 0.34, 0.25))
	texture.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.uv1_scale = Vector3(GROUND_SIZE / 7.5, GROUND_SIZE / 7.5, 1.0)
	material.roughness = 0.95
	return material


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.material_override = _ground_material()
	add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = EnemyBase.ENVIRONMENT_LAYER | 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)


## A smooth bump - a raised cosine, so its slopes run from flat at the top and the foot to
## about 30 degrees in between: the range a projected telegraph has to cope with.
func _build_hill() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells: int = 36
	var extent: float = HILL_RADIUS * 1.2
	var height := func(x: float, z: float) -> float:
		var r: float = Vector2(x, z).length() / HILL_RADIUS
		return 0.0 if r >= 1.0 else HILL_HEIGHT * (0.5 + 0.5 * cos(r * PI))
	for i: int in range(cells):
		for j: int in range(cells):
			var x0: float = lerpf(-extent, extent, float(i) / cells)
			var x1: float = lerpf(-extent, extent, float(i + 1) / cells)
			var z0: float = lerpf(-extent, extent, float(j) / cells)
			var z1: float = lerpf(-extent, extent, float(j + 1) / cells)
			var a := Vector3(x0, height.call(x0, z0), z0)
			var b := Vector3(x1, height.call(x1, z0), z0)
			var c := Vector3(x1, height.call(x1, z1), z1)
			var d := Vector3(x0, height.call(x0, z1), z1)
			for v: Vector3 in [a, b, c, a, c, d]:
				surface.set_uv(Vector2(v.x, v.z) * 0.08)
				surface.add_vertex(v)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = _ground_material()
	mesh.position = Vector3(STAGE_HILL.x, 0.0, STAGE_HILL.z)
	add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = EnemyBase.ENVIRONMENT_LAYER | 1
	var shape := CollisionShape3D.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	body.position = mesh.position
	add_child(body)


func _build_stones() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.42, 0.44)
	material.roughness = 0.9
	for spot: Vector3 in [Vector3(-5.0, 0.0, 12.0), Vector3(8.0, 0.0, 11.0), Vector3(12.0, 0.0, -3.0)]:
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 3.2, 0.9)
		var stone := MeshInstance3D.new()
		stone.mesh = box
		stone.material_override = material
		stone.position = spot + Vector3(0.0, 1.6, 0.0)
		stone.rotation.y = spot.x * 0.3
		add_child(stone)
