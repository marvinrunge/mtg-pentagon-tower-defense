extends Node
## Screenshots the opening mission banner over its whole life, so the announcement can be
## judged for placement and dwell rather than only asserted to exist.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/mission_shot.tscn -- <out.png>
##
## Shot at several points across the fade-in, the hold and the fade-out, because the two
## things most likely to be wrong about a timed banner are both invisible in a single frame:
## whether it collides with the wave-1 lane warning that arrives 2.5s in, and whether it is
## still up long enough after that to finish being read.

## Frames after boot to capture at. The banner fades in over 0.45s, holds 4.5s and fades out
## over 0.8s, so at 60fps its life is roughly frames 0-345 from the emit.
const SHOT_FRAMES: Array[int] = [70, 100, 200, 260, 380, 440]

var _frames: int = 0
var _shots: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/mission_shot.gd").new()
	shooter.name = "MissionShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if SHOT_FRAMES.has(_frames):
		_shoot()


func _shoot() -> void:
	var out_path: String = "mission.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	var panel: Control = hud._mission_panel if hud != null else null
	var alpha: float = panel.modulate.a if panel != null and panel.visible else 0.0
	_shots += 1
	print("  frame %3d  mission alpha %.2f visible=%s" % [
		_frames, alpha, panel.visible if panel != null else false])
	await RenderingServer.frame_post_draw
	var numbered: String = out_path.get_basename() + "_%d.png" % _shots
	if get_viewport().get_texture().get_image().save_png(numbered) == OK:
		print("Wrote %s" % numbered)
	if _shots >= SHOT_FRAMES.size():
		_done = true
		get_tree().quit()
