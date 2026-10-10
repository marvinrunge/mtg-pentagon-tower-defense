extends Node
## A screenshot of the gameplay HUD over the running map, for judging HUD changes.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --windowed --resolution 1600x900 res://tools/tests/hud_shot.tscn -- <out.png> [hour] [hud_scale]

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/hud_shot.gd").new()
	shooter.name = "HudShot"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 300:
		return
	_done = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://hud.png"
	var sky: Node = get_tree().current_scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", float(args[1]) if args.size() > 1 else 13.0)
	if args.size() > 2:
		# Straight onto the HUD rather than through UserSettings, which would save it.
		get_tree().current_scene.get_node("HUD").call("set_hud_scale", float(args[2]))
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("Wrote %s" % out)
	get_tree().quit()
