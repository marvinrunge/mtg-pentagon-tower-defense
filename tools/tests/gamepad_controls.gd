extends Node
## Regression test for playing on a gamepad: drives the real run with synthetic joypad
## events and checks that the menus answer to it and that gameplay keeps out of the way.
##
## Run with (windowed - menus are told apart from play by the captured mouse, and a
## headless run cannot capture it):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/gamepad_controls.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []
var _scene: Node
var _player: Player


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/gamepad_controls.gd").new()
	probe.name = "GamepadControlsTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 300:
		return
	_player = PlayerRegistry.get_local() as Player
	if _player == null or not _player.is_on_floor():
		return
	_started = true
	_scene = get_tree().current_scene
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _run()
	await _main_menu()
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
		await get_tree().physics_frame


func _press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(2)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(3)


func _stick(axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


## Average flat speed over a stretch of frames with the left stick held forward at `push`.
func _speed_at(push: float) -> float:
	_stick(JOY_AXIS_LEFT_Y, -push)
	await _wait(10)
	var total: float = 0.0
	for i: int in 20:
		await _wait(1)
		total += _flat_speed()
	_stick(JOY_AXIS_LEFT_Y, 0.0)
	await _wait(20)
	return total / 20.0


func _run() -> void:
	var hud: Node = _scene.get_node("HUD")
	var settings: Control = hud.get("settings_panel")
	var tree: CanvasLayer = _scene.get_node("SkillTree")
	var equipment: CanvasLayer = hud.get_node("EquipmentMenu")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the run starts with the mouse captured", "mode %d" % Input.mouse_mode)

	# B in play is kick, not "open the menu".
	_player.spell_cooldown_timers["kick"] = 0.0
	await _press(JOY_BUTTON_B)
	_check(not settings.visible, "B in play does not open the menu", "visible %s" % settings.visible)
	_check(float(_player.spell_cooldown_timers.get("kick", 0.0)) > 0.0, "B in play kicks",
		"kick cooldown %.2f" % float(_player.spell_cooldown_timers.get("kick", 0.0)))

	# Start opens the menu; LB/RB page its tabs; A presses the focused control; B closes
	# it without the same press kicking.
	await _press(JOY_BUTTON_START)
	_check(settings.visible, "Start opens the menu", "visible %s" % settings.visible)
	var tabs: TabContainer = settings.find_child("SettingsTabs", true, false)
	var tab_before: int = tabs.current_tab
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(tabs.current_tab == tab_before + 1, "RB goes to the next tab", "%d -> %d" % [tab_before, tabs.current_tab])
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	_check(tabs.current_tab == tab_before, "LB goes back", "now %d" % tabs.current_tab)
	var focused: Control = get_viewport().gui_get_focus_owner()
	_check(focused is CheckBox, "the menu opens with focus on its first option", str(focused))
	if focused is CheckBox:
		var was: bool = (focused as CheckBox).button_pressed
		await _press(JOY_BUTTON_A)
		_check((focused as CheckBox).button_pressed != was, "A toggles the focused option", "%s -> %s" % [was, (focused as CheckBox).button_pressed])
		await _press(JOY_BUTTON_A)
	_player.spell_cooldown_timers["kick"] = 0.0
	await _press(JOY_BUTTON_B)
	_check(not settings.visible, "B closes the menu", "visible %s" % settings.visible)
	_check(float(_player.spell_cooldown_timers.get("kick", 0.0)) <= 0.0, "and the B that closed it does not kick",
		"kick cooldown %.2f" % float(_player.spell_cooldown_timers.get("kick", 0.0)))

	# The skill tree owns the stick while it is open.
	await _press(JOY_BUTTON_Y)
	_check(tree.visible, "Y opens the skill tree", "visible %s" % tree.visible)
	var before: Vector3 = _player.global_position
	_stick(JOY_AXIS_LEFT_X, 1.0)
	await _wait(30)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	var drift: float = Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(drift < 0.05, "the left stick in the skill tree does not walk the character", "moved %.2f m" % drift)
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(not equipment.visible, "D-pad down in the skill tree does not open equipment", "visible %s" % equipment.visible)
	await _press(JOY_BUTTON_B)
	_check(not tree.visible, "B closes the skill tree", "visible %s" % tree.visible)
	await _wait(5)

	# Equipment on D-pad down, navigated with the same D-pad once open.
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(equipment.visible, "D-pad down opens equipment", "visible %s" % equipment.visible)
	_check(get_viewport().gui_get_focus_owner() is PanelContainer, "with a card focused", str(get_viewport().gui_get_focus_owner()))
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(equipment.visible, "D-pad down inside equipment moves instead of closing", "visible %s" % equipment.visible)
	await _press(JOY_BUTTON_B)
	_check(not equipment.visible, "B closes equipment", "visible %s" % equipment.visible)
	await _wait(5)

	# Half a push walks; a full push runs at full speed.
	var full: float = await _speed_at(1.0)
	var half: float = await _speed_at(0.6)
	_check(full > 1.0 and half > full * 0.35 and half < full * 0.65,
		"a part-way push moves at part speed", "full %.2f, at 0.6 push %.2f" % [full, half])

	# The Up arrow walks forwards.
	var start: Vector3 = _player.global_position
	_key(KEY_UP, true)
	await _wait(20)
	_key(KEY_UP, false)
	var moved: Vector3 = _player.global_position - start
	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	_check(moved.dot(forward.normalized()) > 0.5, "the Up arrow walks forwards",
		"%.2f m along facing, %.2f m total" % [moved.dot(forward.normalized()), Vector2(moved.x, moved.z).length()])


## The main menu has to be usable before a run exists: something must hold focus, or a
## gamepad cannot start a game at all.
func _main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _wait(30)
	var focused: Control = get_viewport().gui_get_focus_owner()
	_check(focused is Button, "the main menu opens with a button focused", str(focused))
