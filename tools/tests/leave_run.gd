extends Node
## Regression test for leaving a run from the in-game menu: MAIN MENU and QUIT GAME each ask
## first, Cancel has the focus, B / Escape answers no and leaves the menu open, and confirming
## MAIN MENU lands on the main menu.
##
## Run with (windowed - it takes a screenshot of the question):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --windowed --resolution 1280x720 res://tools/tests/leave_run.tscn -- [screenshot.png]
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/leave_run.gd").new()
	probe.name = "LeaveRunTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 300:
		return
	_started = true
	await _run()
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(ok: bool, what: String, detail: String) -> void:
	print("%s   %s (%s)" % ["ok" if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s (%s)" % [what, detail])


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await _wait(3)


func _button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			return node as Button
	return null


func _run() -> void:
	var hud: Node = get_tree().current_scene.get_node("HUD")
	hud.call("set_settings_open", true)
	await _wait(5)
	var to_menu: Button = _button(hud, "Main Menu")
	var quit: Button = _button(hud, "Quit Game")
	_check(to_menu != null and quit != null, "the in-game menu offers Main Menu and Quit Game", "%s, %s" % [to_menu, quit])
	if to_menu == null or quit == null:
		return

	quit.pressed.emit()
	await _wait(5)
	_check(hud.get("_confirm_layer") != null, "Quit Game asks first", "")
	var focused: Control = get_viewport().gui_get_focus_owner()
	_check(focused is Button and (focused as Button).text == "Cancel", "with Cancel focused", str(focused))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	await _press(JOY_BUTTON_B)
	await _wait(3)
	_check(hud.get("_confirm_layer") == null and (hud.get("settings_panel") as Control).visible,
		"B answers no and leaves the menu open", "menu visible %s" % (hud.get("settings_panel") as Control).visible)

	to_menu.pressed.emit()
	await _wait(5)
	var confirm: Button = _button(hud, "Leave")
	_check(confirm != null, "Main Menu asks first", str(confirm))
	if confirm == null:
		return
	confirm.pressed.emit()
	await _wait(20)
	var scene: Node = get_tree().current_scene
	_check(scene != null and scene.scene_file_path == "res://scenes/ui/main_menu.tscn", "confirming lands on the main menu",
		scene.scene_file_path if scene != null else "none")
