class_name InputHint
## The button to name in an on-screen prompt - "[E]" or "[X]" - depending on whether the
## player last touched the keyboard and mouse or a gamepad.
##
## Prompts used to hardcode the keyboard key, and the one that did not kept its own copy of
## the device detection inside Player, where a run's announcements and the HUD could not
## reach it. The labels here follow project.godot's input map and have to be changed with it,
## the same as the Controls tab in SettingsMenu.

## True once the last meaningful input came from a gamepad.
static var gamepad: bool = false

const KEYBOARD: Dictionary = {
	"interact": "E",
	"equipment": "I",
	"accept": "Click",
	"next_slot": "E",
}
const GAMEPAD: Dictionary = {
	"interact": "X",
	"equipment": "D-pad down",
	"accept": "A",
	"next_slot": "X",
}


## Updates `gamepad` from one input event. Small stick motion is ignored, so a controller
## sitting connected but unused - drifting a little - does not flip every prompt to it.
static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		gamepad = false


## "[E]" or "[X]" for one of the names above.
static func key(name: String) -> String:
	return "[%s]" % String((GAMEPAD if gamepad else KEYBOARD).get(name, name))
