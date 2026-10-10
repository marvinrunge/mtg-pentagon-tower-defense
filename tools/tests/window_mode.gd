extends Node
## Regression test for fullscreen and windowed play (GraphicsSettings.fullscreen): a tool or
## test start ends up in a window, the game's own start takes the player's choice, F11 and
## Alt+Enter switch it, and the choice is written where the engine reads it at the next boot.
##
## Run with (windowed):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/window_mode.tscn
## It briefly takes the screen fullscreen, and puts the player's own setting back at the end.
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String, detail: String) -> void:
	print("%s   %s (%s)" % ["ok" if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s (%s)" % [what, detail])


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _mode_name() -> String:
	return {DisplayServer.WINDOW_MODE_WINDOWED: "windowed", DisplayServer.WINDOW_MODE_FULLSCREEN: "fullscreen"}.get(
		DisplayServer.window_get_mode(), str(DisplayServer.window_get_mode()))


func _key(code: Key, alt: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.alt_pressed = alt
	event.pressed = true
	Input.parse_input_event(event)


func _override_mode() -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.OVERRIDE_PATH)
	return cfg.get_value("display", "window/size/mode.template", null)


func _run() -> void:
	var original: bool = GraphicsSettings.fullscreen
	await _frames(10)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "a test scene starts in a window", _mode_name())

	# The game's own start, as if this were the main menu.
	GraphicsSettings.fullscreen = true
	var main_menu: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	get_tree().current_scene.scene_file_path = main_menu
	GraphicsSettings.call("_apply_startup_window_mode")
	await _frames(10)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "the game starts fullscreen", _mode_name())

	_key(KEY_F11)
	await _frames(10)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and not GraphicsSettings.fullscreen,
		"F11 switches to a window", _mode_name())
	var screen: Vector2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var size: Vector2i = DisplayServer.window_get_size()
	_check(size.x > screen.x / 2 and size.x < screen.x, "a window most of the screen wide", "%s on %s" % [size, screen])
	await get_tree().create_timer(0.8).timeout
	_check(_override_mode() == 0, "the window is what the next launch opens in", str(_override_mode()))

	_key(KEY_ENTER, true)
	await _frames(10)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and GraphicsSettings.fullscreen,
		"Alt+Enter switches back to fullscreen", _mode_name())
	await get_tree().create_timer(0.8).timeout
	_check(_override_mode() == 3, "and that is saved too", str(_override_mode()))

	GraphicsSettings.apply_fullscreen(original)
	await get_tree().create_timer(0.8).timeout
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()
