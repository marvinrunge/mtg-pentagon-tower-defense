extends Node
## Regression test for playing on a gamepad: drives the real run with synthetic joypad
## events and checks that the menus answer to it and that gameplay keeps out of the way.
##
## Run with (windowed - menus are told apart from play by the captured mouse, and a
## headless run cannot capture it):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/gamepad_controls.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const InputHint := preload("res://scripts/input_hint.gd")
const IntroTour := preload("res://scripts/intro_tour.gd")

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
	# Not while the opening camera flight is up: it takes every button press as "skip",
	# so the first presses of the test would land on it instead of on the game.
	if _player == null or not _player.is_on_floor() or IntroTour.playing:
		return
	_started = true
	_scene = get_tree().current_scene
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _run()
	await _labels()
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


func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## Lets whatever the last press started finish, so the next press is free to start a cast.
func _clear_cast() -> void:
	if _player.is_charging:
		_player.release_charged_spell()
	if _player._channel_id != "":
		_player._end_channel()
	_player.spell_cooldown_timers.clear()
	await _wait(60)


## Holds L3, points the right stick `direction` (screen space, up is -y), and lets go.
func _wheel(direction: Vector2) -> void:
	_button(JOY_BUTTON_LEFT_STICK, true)
	await _wait(3)
	_stick(JOY_AXIS_RIGHT_X, direction.x)
	_stick(JOY_AXIS_RIGHT_Y, direction.y)
	await _wait(5)
	_button(JOY_BUTTON_LEFT_STICK, false)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	await _wait(5)


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

	# The face buttons are the hotbar now: A B X Y cast slots 1-4, and with RB held 5-8.
	# Eight spells on the bar, so every slot has something to select.
	var spells: Array[String] = ["red_1", "red_2", "red_4", "red_5", "blue_1", "blue_2", "blue_3", "red_3"]
	for slot: int in spells.size():
		_player.spell_ranks[spells[slot]] = 1
		_player.assign_quick_slot(slot, spells[slot])
	var faces: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
	var picked: Array[int] = []
	for face: JoyButton in faces:
		await _clear_cast()
		await _press(face)
		picked.append(_player.active_spell_index)
	_check(picked == [0, 1, 2, 3], "A B X Y pick slots 1-4", "picked %s" % [picked])
	picked.clear()
	for face: JoyButton in faces:
		await _clear_cast()
		_button(JOY_BUTTON_RIGHT_SHOULDER, true)
		await _press(face)
		_button(JOY_BUTTON_RIGHT_SHOULDER, false)
		picked.append(_player.active_spell_index)
	_check(picked == [4, 5, 6, 7], "RB + A B X Y pick slots 5-8", "picked %s" % [picked])
	_check(not settings.visible, "B in play does not open the menu", "visible %s" % settings.visible)

	# A channel lasts as long as the button that started it is held - the face button, not
	# a cast button the pad no longer has.
	await _clear_cast()
	_button(JOY_BUTTON_X, true)
	await _wait(30)
	_check(_player._channel_id != "", "holding X keeps Fire Cone going", "channel '%s'" % _player._channel_id)
	_button(JOY_BUTTON_X, false)
	await _wait(3)
	_check(_player._channel_id == "", "letting go of X ends it", "channel '%s'" % _player._channel_id)

	# The buttons the face buttons used to be.
	await _clear_cast()
	_player.spell_cooldown_timers["kick"] = 0.0
	await _press(JOY_BUTTON_RIGHT_STICK)
	_check(float(_player.spell_cooldown_timers.get("kick", 0.0)) > 0.0, "R3 kicks",
		"kick cooldown %.2f" % float(_player.spell_cooldown_timers.get("kick", 0.0)))
	await _wait(60)
	var floor_y: float = _player.global_position.y
	_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await _wait(10)
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_check(_player.global_position.y > floor_y + 0.1 or _player.velocity.y > 0.5, "LB jumps",
		"rose %.2f m, vy %.2f" % [_player.global_position.y - floor_y, _player.velocity.y])
	await _wait(90)

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
	var slot_before: int = _player.active_spell_index
	await _press(JOY_BUTTON_B)
	_check(not settings.visible, "B closes the menu", "visible %s" % settings.visible)
	_check(_player.active_spell_index == slot_before, "and the B that closed it casts nothing",
		"slot %d -> %d" % [slot_before, _player.active_spell_index])

	# The skill tree and equipment open from the L3 wheel: hold, point, let go.
	var wheel: CanvasLayer = hud.get_node("ActionWheel")
	await _wheel(Vector2.UP)
	_check(tree.visible, "the wheel's top entry opens the skill tree", "visible %s" % tree.visible)
	var before: Vector3 = _player.global_position
	_stick(JOY_AXIS_LEFT_X, 1.0)
	await _wait(30)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	var drift: float = Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(drift < 0.05, "the left stick in the skill tree does not walk the character", "moved %.2f m" % drift)
	await _press(JOY_BUTTON_B)
	_check(not tree.visible, "B closes the skill tree", "visible %s" % tree.visible)
	await _wait(5)

	await _wheel(Vector2.DOWN)
	_check(equipment.visible, "the wheel's bottom entry opens equipment", "visible %s" % equipment.visible)
	_check(get_viewport().gui_get_focus_owner() is PanelContainer, "with a card focused", str(get_viewport().gui_get_focus_owner()))
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(equipment.visible, "D-pad down inside equipment moves instead of closing", "visible %s" % equipment.visible)
	await _press(JOY_BUTTON_B)
	_check(not equipment.visible, "B closes equipment", "visible %s" % equipment.visible)
	await _wait(5)

	# Let go without pointing anywhere: nothing opens, and play has the mouse back.
	await _wheel(Vector2.ZERO)
	_check(not tree.visible and not equipment.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"a wheel let go of unpointed opens nothing", "tree %s, equipment %s, mouse %d" % [tree.visible, equipment.visible, Input.mouse_mode])
	_check(not wheel.get_child(0).visible, "and is gone again", "visible %s" % wheel.get_child(0).visible)

	# Half a push walks; a full push runs at full speed.
	var full: float = await _speed_at(1.0)
	var half: float = await _speed_at(0.6)
	_check(full > 1.0 and half > full * 0.3 and half < full * 0.65,
		"a part-way push moves at part speed", "full %.2f, at 0.6 push %.2f" % [full, half])
	# Sprint is the pad's default: a full push goes at sprint pace with no button held.
	var sprint_pace: float = GameSettings.player_base_speed * GameSettings.player_sprint_speed_mult
	_check(full > sprint_pace * 0.9, "a full push sprints", "full %.2f, sprint pace %.2f" % [full, sprint_pace])

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


## Button names follow the controller: detected from the name the OS gives it, or forced by
## the Button Labels setting - and the Controls table follows along.
func _labels() -> void:
	var names: Dictionary = {
		"PS5 Controller": "playstation", "DualSense Wireless Controller": "playstation",
		"PS4 Controller": "playstation", "Nintendo Switch Pro Controller": "nintendo",
		"Xbox Series X Controller": "xbox", "XInput Gamepad": "xbox", "Generic USB Joystick": "xbox",
	}
	var wrong: Array = []
	for joy_name: String in names:
		if InputHint.family_from_name(joy_name) != names[joy_name]:
			wrong.append("%s -> %s" % [joy_name, InputHint.family_from_name(joy_name)])
	_check(wrong.is_empty(), "controllers are recognised by name", "wrong: %s" % [wrong])

	var before: String = UserSettings.button_labels
	UserSettings.set_value(&"button_labels", "playstation")
	InputHint.gamepad = true
	_check(InputHint.pad("left") == "Square" and InputHint.pad("bottom") == "Cross",
		"the PlayStation setting names PlayStation buttons", "%s, %s" % [InputHint.pad("left"), InputHint.pad("bottom")])
	UserSettings.set_value(&"button_labels", "nintendo")
	_check(InputHint.pad("bottom") == "B" and InputHint.pad("rt") == "ZR",
		"the Nintendo setting names Nintendo buttons", "%s, %s" % [InputHint.pad("bottom"), InputHint.pad("rt")])

	var hud: Node = _scene.get_node("HUD")
	var tabs: TabContainer = (hud.get("settings_panel") as Control).find_child("SettingsTabs", true, false)
	var controls: Node = tabs.get_node("Controls")
	var texts: PackedStringArray = []
	for label: Node in controls.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	_check(texts.has("Gamepad (Nintendo)") and texts.has("ZR"), "the Controls table follows the setting",
		"header found %s, ZR found %s" % [texts.has("Gamepad (Nintendo)"), texts.has("ZR")])
	UserSettings.set_value(&"button_labels", before)
	InputHint.gamepad = false


## The main menu has to be usable before a run exists: something must hold focus, or a
## gamepad cannot start a game at all.
func _main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _wait(30)
	var focused: Control = get_viewport().gui_get_focus_owner()
	_check(focused is Button, "the main menu opens with a button focused", str(focused))
