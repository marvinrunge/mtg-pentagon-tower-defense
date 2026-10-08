extends "res://tools/tests/vfx_stage.gd"
## A contact sheet of the effects most likely to look placeholder - primitive meshes, flat
## discs, untextured spheres - caught at a chosen moment, so their look can be
## judged and compared before and after a VFX pass.
##
## Shot on the light VfxStage rather than the real map (see vfx_stage.gd): seconds to boot,
## not minutes.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/vfx_audit_shot.tscn -- <out.png>
##
## Every tile builds its effect the way the game does (the same builders and nodes), waits a
## fixed time into it, and photographs it. Times are wall-clock, so a slow software renderer
## catches the same moment a real GPU would.

const TILE := Vector2i(640, 360)
const COLUMNS := 2

var _scene: Node = null
var _camera: Camera3D = null
var _caption: Label = null
var _sheet: Image = null


func _ready() -> void:
	build_stage()
	_start.call_deferred()


func _start() -> void:
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	_shoot_all()


func _shoot_all() -> void:
	_scene = get_tree().current_scene
	for node: Node in get_tree().get_nodes_in_group("player"):
		node.remove_from_group("player")
		(node as Node3D).visible = false
	for node: Node in _scene.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 15.0)

	_camera = Camera3D.new()
	_scene.add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 36)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	var shots: Array[Callable] = [
		_fireball_flight, _fireball_blast.bind(0.08), _fireball_blast.bind(0.3), _enemy_shots,
		_zone.bind("holy_trail", "HOLY TRAIL ZONE"), _zone.bind("fire_rain", "RAIN OF EMBER ZONE"),
		_shockwave, _boss_meteor, _scorch_on_slope,
	]
	var rows: int = int(ceil(float(shots.size()) / float(COLUMNS)))
	_sheet = Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGB8)
	for i: int in range(shots.size()):
		var before: Array[Node] = _scene.get_children()
		await shots[i].call(i)
		for child: Node in _scene.get_children():
			if not before.has(child) and child != _camera:
				child.queue_free()
		await get_tree().process_frame

	var out_path: String = "vfx_audit.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	_sheet.save_png(out_path)
	print("VFX AUDIT SHEET: %s" % out_path)
	get_tree().quit()


func _look(from: Vector3, at: Vector3) -> void:
	_camera.global_position = from
	_camera.look_at(at)


func _capture(tile: int, caption: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	_caption.text = caption
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	_sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i((tile % COLUMNS) * TILE.x, (tile / COLUMNS) * TILE.y))
	print("  %d: %s" % [tile, caption])


func _projectile(at: Vector3, direction: Vector3, type: int, kind: String, tint: Color, enemy: bool) -> Projectile:
	var packed: PackedScene = load("res://scenes/misc/projectile.tscn") as PackedScene
	var projectile: Projectile = packed.instantiate()
	_scene.add_child(projectile)
	projectile.activate(at, direction, type, enemy, 1.0, -1.0, 0.0, null, kind, tint)
	projectile.global_position = at
	return projectile


func _fireball_flight(tile: int) -> void:
	var projectile: Projectile = _projectile(STAGE + Vector3(3.0, 1.6, 0.0), Vector3.LEFT, 4, "magic", Color(1.0, 0.45, 0.1), false)
	_look(STAGE + Vector3(0.0, 2.2, -6.0), STAGE + Vector3(0.0, 1.4, 0.0))
	# Flying for a moment so the trail exists, then held where the camera can see it.
	await get_tree().create_timer(0.25).timeout
	projectile.set_physics_process(false)
	projectile.global_position = STAGE + Vector3(-0.5, 1.6, 0.0)
	await _capture(tile, "FIREBALL - IN FLIGHT", 0.05)


func _fireball_blast(tile: int, after: float) -> void:
	var projectile: Projectile = _projectile(STAGE + Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, 4, "magic", Color(1.0, 0.45, 0.1), false)
	projectile.set_physics_process(false)
	projectile.visible = false
	_look(STAGE + Vector3(0.0, 3.0, -9.0), STAGE + Vector3(0.0, 1.0, 0.0))
	projectile._fireball_blast_visuals()
	await _capture(tile, "FIREBALL - EXPLOSION +%.2fs" % after, after)


func _enemy_shots(tile: int) -> void:
	var arrow: Projectile = _projectile(STAGE + Vector3(-1.8, 1.5, 0.0), Vector3.FORWARD, 0, "arrow", Color.WHITE, true)
	var stone: Projectile = _projectile(STAGE + Vector3(0.0, 1.5, 0.0), Vector3.FORWARD, 0, "stone", Color.WHITE, true)
	var bolt: Projectile = _projectile(STAGE + Vector3(1.8, 1.5, 0.0), Vector3.FORWARD, 1, "magic", Color(0.6, 0.3, 0.9), true)
	for p: Projectile in [arrow, stone, bolt]:
		p.set_physics_process(false)
	_look(STAGE + Vector3(2.5, 2.2, -3.5), STAGE + Vector3(0.0, 1.5, 0.0))
	await _capture(tile, "ENEMY ARROW / STONE / MAGE BOLT", 0.1)


func _zone(tile: int, type: String, caption: String) -> void:
	var zone := DoTZone.new()
	zone.setup(type, 4.0, 0.0, 30.0, null)
	_scene.add_child(zone)
	zone.global_position = STAGE
	_look(STAGE + Vector3(0.0, 6.0, -9.0), STAGE)
	await _capture(tile, caption, 0.6)


func _shockwave(tile: int) -> void:
	var wave: Node3D = SpellFx.shockwave(Color(1.0, 0.92, 0.6), 6.0)
	_scene.add_child(wave)
	wave.global_transform = SpellFx.ground_transform(_scene as Node3D, STAGE)
	_look(STAGE + Vector3(0.0, 5.0, -9.0), STAGE)
	await _capture(tile, "SHOCKWAVE (Wrath of God, Roar, ...)", 0.15)


func _boss_meteor(tile: int) -> void:
	var desc: Dictionary = {
		"tell": "meteor", "at": STAGE + Vector3(0.0, 0.0, 4.0), "yaw": 0.0, "radius": 3.0, "windup": 1.4,
	}
	var tell: BossTell = BossTell.spawn(_scene, desc)
	tell.freeze_at(0.6)
	_look(STAGE + Vector3(-4.0, 4.0, -8.0), STAGE + Vector3(2.0, 5.0, 6.0))
	await _capture(tile, "BOSS METEOR - FALLING", 0.3)


func _scorch_on_slope(tile: int) -> void:
	# The flank of the stage hill, so the flat decal's problem shows.
	var spot: Vector3 = ground_at(Vector2(STAGE_HILL.x + 4.0, STAGE_HILL.z - 3.0))
	var scorch: MeshInstance3D = SpellFx.ground_decal("decal_scorch", Color(0.07, 0.04, 0.03, 0.85), 4.0)
	_scene.add_child(scorch)
	scorch.global_transform = SpellFx.ground_transform(_scene as Node3D, spot)
	var frost: MeshInstance3D = SpellFx.ground_decal("decal_frost", Color(0.7, 0.9, 1.0, 0.9), 4.0)
	_scene.add_child(frost)
	frost.global_transform = SpellFx.ground_transform(_scene as Node3D, spot + Vector3(6.0, 0.0, -3.0))
	_look(spot + Vector3(8.0, 7.0, 12.0), spot + Vector3(3.0, 0.0, -1.5))
	await _capture(tile, "SCORCH + FROST DECALS ON A SLOPE", 0.4)
