extends Node
## Regression test: every menu can be closed without a keystroke, and Escape closes the
## menu you are actually in.
##
## Run with:  godot --headless --path . res://tools/tests/menu_close.tscn
##
## Escape used to be taken UNCONDITIONALLY by the HUD's settings panel, which also never
## marked the event handled. So pressing it with the skill tree open did two things at
## once - the tree closed itself and Settings opened over the top - and the mouse mode was
## left by whichever of the two ran last. The next press then did something different
## again, which is what "sometimes Escape does not work" actually was.
##
## The close buttons are the other half: a windowed game cannot rely on Escape arriving at
## all, because alt-tabbing away and back can send the press to the window manager, and a
## player stuck inside a full-screen panel has lost the run.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	await _run()
	get_tree().quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## The Escape key, as the game receives it.
func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _close_button_of(node: Node) -> CloseButton:
	for child: Node in node.get_children():
		if child is CloseButton:
			return child as CloseButton
	return null


func _run() -> void:
	_scene = get_tree().current_scene
	var hud: Node = _scene.get_node_or_null("HUD")
	var tree: Node = _scene.get_node_or_null("SkillTree")
	var base_ui: Node = _scene.get_node_or_null("BaseUI")
	if _scene == null or hud == null or tree == null:
		print("TEST RESULT: FAIL (no scene, HUD or skill tree)")
		return

	# --- every menu offers a way out that is not a key ------------------------
	print("CLOSE BUTTONS")
	var tree_button: CloseButton = _close_button_of(tree.get_node("Control"))
	_check("the skill tree has one", tree_button != null)
	var settings_button: CloseButton = _close_button_of(hud.settings_panel.get_parent())
	_check("the settings panel has one", settings_button != null)
	if base_ui != null:
		_check("the base panel has one", _close_button_of(base_ui) != null)

	# ...and it is not something the arrow keys can land on, because the skill tree
	# navigates its board with them and ui_accept buys the selected node.
	if tree_button != null:
		_check("it cannot steal keyboard focus", tree_button.focus_mode == Control.FOCUS_NONE)

	# --- and the button actually closes, mouse included -----------------------
	print("WHAT THE BUTTON DOES")
	if tree_button != null:
		tree.set_open(true)
		_check("the tree opens", tree.visible)
		tree_button.pressed.emit()
		_check("the button closes it", not tree.visible)
		# A menu that closes without recapturing the mouse leaves the player unable to
		# look around, which reads as the game having frozen. Only checkable with a window
		# to capture INTO: a headless run has no display server to set the mode on, and
		# reads back VISIBLE whatever it was told.
		if DisplayServer.get_name() != "headless":
			_check("...and gives the mouse back to the game",
				Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, str(Input.mouse_mode))
		else:
			print("       (no display server - mouse capture not judged)")

	if settings_button != null:
		hud.set_settings_open(true)
		_check("settings opens", hud.settings_panel.visible)
		settings_button.pressed.emit()
		_check("the button closes it", not hud.settings_panel.visible)

	# --- Escape goes to the menu that is open ---------------------------------
	print("WHERE ESCAPE GOES")
	tree.set_open(true)
	await _press_escape()
	_check("Escape closes the skill tree", not tree.visible)
	# THE bug: Settings must not have opened behind it.
	_check("...and does not open settings behind it", not hud.settings_panel.visible,
		"settings came up as well")

	# With nothing else open it still belongs to Settings, which is the whole reason it
	# was written that way.
	await _press_escape()
	_check("Escape with nothing open still opens settings", hud.settings_panel.visible)
	await _press_escape()
	_check("...and closes it again", not hud.settings_panel.visible)

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL - %d failed: %s" % [_failures.size(), ", ".join(_failures)])
