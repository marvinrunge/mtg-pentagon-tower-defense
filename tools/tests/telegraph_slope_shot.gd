extends Node
## Photographs boss telegraphs on a SLOPE, to check they are projected onto the ground rather
## than drawn on a flat plane the hill swallows.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/telegraph_slope_shot.tscn -- <out.png>
##   godot --rendering-driver vulkan --rendering-method forward_plus --path . res://tools/tests/telegraph_slope_shot.tscn -- <out.png>
## The two renderers rebuild the ground point from depth differently (see
## ground_projection.gdshaderinc), so both are worth a look after touching the projection.
##
## Finds its own hillside by raycasting: the spot around the base whose surroundings span the
## most height within reason. Then stands a Frost Giant there mid Absolute Zero (a 12-unit
## ring - the widest zone in the game), a Zombie Lord's charge line and a Fire Giant's meteors
## and burning ground nearby, frozen at 70 % of their windups.

const FREEZE_AT := 0.7

var _frames: int = 0
var _scene: Node = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/telegraph_slope_shot.gd").new()
	shooter.name = "TelegraphSlopeShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if not get_meta("armed", false):
		return
	_frames += 1
	if _frames == 90:
		_shoot()


class _Stand:
	extends Node3D
	var is_downed: bool = false
	var hp: float = 100.0
	var max_hp: float = 100.0
	func take_damage(_amount: float, _source: Node3D = null, _is_melee: bool = false, _exile: bool = false) -> void:
		pass
	func apply_slow(_duration: float) -> void:
		pass


func _ground(xz: Vector2) -> Vector3:
	var space: PhysicsDirectSpaceState3D = (_scene as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 200.0, xz.y), Vector3(xz.x, -200.0, xz.y))
	query.collision_mask = EnemyBase.ENVIRONMENT_LAYER
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get("position", Vector3(xz.x, 0.0, xz.y))


## The spot near the base where the ground within 10 units spans between 2.5 and 7 metres -
## a real slope, not a cliff.
func _find_slope() -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_span: float = 0.0
	for ring: float in [32.0, 40.0, 48.0, 56.0]:
		for step: int in range(24):
			var a: float = TAU * float(step) / 24.0
			var center := Vector2(sin(a), cos(a)) * ring
			var lo: float = INF
			var hi: float = -INF
			for k: int in range(8):
				var b: float = TAU * float(k) / 8.0
				var y: float = _ground(center + Vector2(sin(b), cos(b)) * 10.0).y
				lo = minf(lo, y)
				hi = maxf(hi, y)
			var span: float = hi - lo
			if span > best_span and span < 7.0:
				best_span = span
				best = _ground(center)
	print("  slope at %s spans %.1f m" % [best, best_span])
	return best


func _shoot() -> void:
	_scene = get_tree().current_scene
	for node: Node in get_tree().get_nodes_in_group("player"):
		node.remove_from_group("player")
	for node: Node in _scene.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)

	var spot: Vector3 = _find_slope()
	var blue: EnemyBase = _boss("Blue", spot, 3)
	var near: Node3D = _stand(_ground(Vector2(spot.x + 1.5, spot.z + 1.0)))
	blue.current_target = near
	_begin(blue, "Absolute Zero", 3)

	var black_at: Vector3 = _ground(Vector2(spot.x + 9.0, spot.z - 9.0))
	var black: EnemyBase = _boss("Black", black_at, 3)
	var weak: Node3D = _stand(_ground(Vector2(black_at.x - 8.0, black_at.z + 3.0)))
	(weak as _Stand).hp = 20.0
	_begin(black, "The Hunt", 3)

	var red_at: Vector3 = _ground(Vector2(spot.x - 12.0, spot.z - 6.0))
	var red: EnemyBase = _boss("Red", red_at, 2)
	_stand(_ground(Vector2(red_at.x + 4.0, red_at.z + 5.0)))
	_stand(_ground(Vector2(red_at.x - 3.0, red_at.z + 7.0)))
	_begin(red, "Meteor Strike", 2)
	_scene.request_effect({"kind": "boss_hazard", "position": _ground(Vector2(red_at.x + 2.0, red_at.z - 4.0)),
		"style": "fire", "radius": 2.5, "duration": 60.0, "dps": 0.0})

	for boss: EnemyBase in [blue, black, red]:
		for indicator: AttackIndicator in boss._cast_indicators:
			if is_instance_valid(indicator):
				indicator._elapsed = indicator._duration * FREEZE_AT
				indicator._auto_resolve = false
				indicator._process(0.0)
				indicator.set_process(false)
		for tell: BossTell in boss._cast_tells:
			if is_instance_valid(tell):
				tell.freeze_at(FREEZE_AT)

	var camera := Camera3D.new()
	_scene.add_child(camera)
	var focus: Vector3 = spot + Vector3(-2.0, 0.0, -3.0)
	camera.global_position = _ground(Vector2(focus.x + 20.0, focus.z + 14.0)) + Vector3(0.0, 13.0, 0.0)
	camera.look_at(focus)
	camera.fov = 62.0
	camera.current = true
	for _i: int in range(30):
		await get_tree().process_frame
	for _i: int in range(4):
		await RenderingServer.frame_post_draw

	var out_path: String = "telegraph_slope.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	get_viewport().get_texture().get_image().save_png(out_path)
	print("TELEGRAPH SLOPE SHOT (%s): %s" % [RenderingServer.get_current_rendering_method(), out_path])
	get_tree().quit()


func _boss(color: String, at: Vector3, phase: int) -> EnemyBase:
	var packed: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = packed.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	_scene.get_node("Enemies").add_child(boss)
	boss.global_position = at
	boss.set_physics_process(false)
	if phase > 1:
		boss.take_damage(boss.health - boss.enemy_data.health * (0.5 if phase == 2 else 0.2))
		boss._pending_phase_transition = false
	return boss


func _begin(boss: EnemyBase, display_name: String, phase: int) -> void:
	for i: int in range(boss._specials.size()):
		var config: Dictionary = boss._specials[i]
		if String(config["display_name"]) == display_name and BossDatabase.special_in_phase(config, phase):
			boss._begin_special(i)
			return


func _stand(at: Vector3) -> Node3D:
	var stand := _Stand.new()
	stand.add_to_group("player")
	var post := CSGCylinder3D.new()
	post.radius = 0.35
	post.height = 1.8
	post.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.2)
	post.material = mat
	stand.add_child(post)
	_scene.add_child(stand)
	stand.global_position = at
	return stand
