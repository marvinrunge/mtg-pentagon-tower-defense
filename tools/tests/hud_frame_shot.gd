extends Node
## Screenshots the whole HUD at one window size, so the responsive bottom strip can be
## checked against what the arithmetic in hud_layout.gd claims.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1024x600 \
##       res://tools/tests/hud_frame_shot.tscn -- <out.png>
##
## hud_layout.gd already asserts that the four rects do not collide, and it does so at seven
## window sizes in one millisecond. What it CANNOT catch is the rects being right and the
## Controls still landing somewhere else - the offsets are applied against three different
## anchor presets (bottom-left for health, bottom-centre for the XP bar and the hotbar), and
## a sign error in one of those conversions passes every assertion and moves the bar off
## screen. That is what this looks at.

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/hud_frame_shot.gd").new()
	shooter.name = "FrameShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	_shoot()


func _shoot() -> void:
	var out_path: String = "hud_frame.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if hud == null:
		push_error("No HUD in the scene")
		get_tree().quit()
		return
	# Something in every readout, so nothing is invisible because it happens to be empty.
	hud.update_player_health(72.0, 100.0)
	hud.update_player_shield(28.0)
	hud.update_health(640.0, 1000.0)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var plan: Dictionary = hud.bottom_hud_rects(vp)
	print("viewport %dx%d scale=%.2f" % [vp.x, vp.y, plan["scale"]])
	# The planned rect against where the Control actually ended up. These must agree, and it
	# is the anchor-offset conversion in _layout_bottom_hud that decides whether they do.
	for pair: Array in [
		["health", hud.player_health_bar],
		["xp", hud.xp_bar],
		["hotbar", hud.get_node("Control/HotbarContainer")],
	]:
		var planned: Rect2 = plan[pair[0]]
		var actual := Rect2((pair[1] as Control).global_position, (pair[1] as Control).size)
		var agrees: bool = planned.position.distance_to(actual.position) < 1.5
		print("  %-8s planned=%s actual=%s %s" % [
			pair[0], planned, actual, "ok" if agrees else "MISMATCH"])

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()
