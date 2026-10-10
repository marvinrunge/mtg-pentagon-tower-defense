extends RefCounted
## The button to name in an on-screen prompt - "[E]", "[X]", "[Square]" - depending on what
## the player last touched and, for a gamepad, which kind it is.
##
## Prompts used to hardcode the keyboard key, and the one that did not kept its own copy of
## the device detection inside Player, where a run's announcements and the HUD could not
## reach it. The names here follow project.godot's input map and have to be changed with it;
## SettingsMenu's Controls table reads its gamepad column from here too, so the table and the
## prompts cannot disagree.
##
## Deliberately no `class_name` - preloaded by path, see scripts/icon_style.gd.
##
## Gamepad buttons are named by POSITION ("bottom", "left"...), because that is how Godot
## numbers them: button 0 is the bottom face button on every pad. Jump is the same thumb
## movement on all three; only what is printed on the button differs - A on an Xbox pad,
## Cross on a PlayStation one, B on a Nintendo one.

## True once the last meaningful input came from a gamepad.
static var gamepad: bool = false
## The Controls tab's Button Labels setting: "auto" or one of the PAD families. Set by
## UserSettings.
static var label_style: String = "auto"
## The joypad that sent the last event, for "auto" to look at.
static var _device: int = 0

const STYLES: Array[String] = ["auto", "xbox", "playstation", "nintendo"]
const STYLE_NAMES: Dictionary = {
	"auto": "Auto", "xbox": "Xbox", "playstation": "PlayStation", "nintendo": "Nintendo",
}

## What is printed on each button, by family.
const PAD: Dictionary = {
	"xbox": {
		"bottom": "A", "right": "B", "left": "X", "top": "Y",
		"lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "back": "View", "start": "Menu",
	},
	"playstation": {
		"bottom": "Cross", "right": "Circle", "left": "Square", "top": "Triangle",
		"lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "back": "Create", "start": "Options",
	},
	"nintendo": {
		"bottom": "B", "right": "A", "left": "Y", "top": "X",
		"lb": "L", "rb": "R", "lt": "ZL", "rt": "ZR", "back": "Minus", "start": "Plus",
	},
}

## Prompt names -> the key, or the pad position from PAD. Anything not a position (the
## D-pad) is printed as it stands.
const KEYBOARD: Dictionary = {
	"interact": "E",
	"equipment": "I",
	"accept": "Click",
	"next_slot": "E",
}
const GAMEPAD: Dictionary = {
	"interact": "left",
	"equipment": "D-pad down",
	"accept": "bottom",
	"next_slot": "left",
}


## Updates `gamepad` from one input event. Small stick motion is ignored, so a controller
## sitting connected but unused - drifting a little - does not flip every prompt to it.
static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		gamepad = true
		_device = event.device
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		gamepad = false


## "[E]" or "[Square]" for one of the prompt names above.
static func key(name: String) -> String:
	if gamepad:
		return "[%s]" % pad(String(GAMEPAD.get(name, name)))
	return "[%s]" % String(KEYBOARD.get(name, name))


## What is printed on the button at `position` ("bottom", "lb"...) of the pad in use.
static func pad(position: String) -> String:
	return String((PAD[pad_family()] as Dictionary).get(position, position))


## The family whose names are shown: the setting, or on "auto" the pad last used - or, if
## none has been touched yet, the first one connected.
static func pad_family() -> String:
	if label_style != "auto" and PAD.has(label_style):
		return label_style
	var device: int = _device
	var connected: Array[int] = Input.get_connected_joypads()
	if not connected.has(device) and not connected.is_empty():
		device = connected[0]
	return family_from_name(Input.get_joy_name(device))


## Which family a controller belongs to, from the name the OS gives it ("PS5 Controller",
## "Nintendo Switch Pro Controller", "XInput Gamepad"...). Anything unrecognised is read as
## Xbox: it is what Windows and most third-party pads present themselves as.
static func family_from_name(joy_name: String) -> String:
	var lower: String = joy_name.to_lower()
	for marker: String in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony"]:
		if lower.contains(marker):
			return "playstation"
	for marker: String in ["nintendo", "switch", "joy-con", "joycon"]:
		if lower.contains(marker):
			return "nintendo"
	return "xbox"
