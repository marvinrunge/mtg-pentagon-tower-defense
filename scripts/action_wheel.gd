extends CanvasLayer
## The gamepad's menu wheel: hold L3, point a stick at an entry, let go to open it.
##
## The face buttons cast spells now (Player.PAD_SLOT_BUTTONS), which pushed the things that
## lived on them somewhere else. Jump, kick and interact are needed at once and in a fight,
## so they took the free buttons; the screens a player opens between fights - the skill
## tree, the equipment - are what is left, and they live here.
##
## An entry is opened by sending its ordinary input action, exactly as the keyboard key
## would. The wheel therefore knows nothing about the menus behind it, and a menu that is
## reached from here behaves the same as one reached from its key.
##
## Deliberately no `class_name` - preloaded by path, see scripts/icon_style.gd.

const OPEN_BUTTON := JOY_BUTTON_LEFT_STICK
## [label, input action], placed clockwise from the top.
const ENTRIES: Array = [
	["Skill Tree", "skill_tree"],
	["Equipment", "equipment"],
]
const RADIUS: float = 130.0
## A stick has to be pushed this far before it points at anything, so a wheel opened and
## let go of without a decision closes with nothing chosen.
const POINT_DEADZONE: float = 0.5

var _root: Control
var _cards: Array[PanelContainer] = []
var _chosen: int = -1
var _open: bool = false


func _ready() -> void:
	layer = 105
	_build()
	_root.hide()


func _input(event: InputEvent) -> void:
	var button := event as InputEventJoypadButton
	if button != null and button.button_index == OPEN_BUTTON:
		if button.pressed and not _open:
			# Only over the game itself: every menu already owns the pad while it is up.
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				return
			_set_open(true)
			get_viewport().set_input_as_handled()
		elif not button.pressed and _open:
			var chosen: int = _chosen
			_set_open(false)
			if chosen >= 0:
				_send(String(ENTRIES[chosen][1]))
			get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _open:
		return
	# Either stick: the left one is the one already under the thumb holding L3 down, the
	# right one is what a wheel is pointed with in most games.
	var left: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var right: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var aim: Vector2 = right if right.length() > left.length() else left
	_set_chosen(_entry_at(aim) if aim.length() >= POINT_DEADZONE else -1)


## Opening hides the mouse rather than leaving it captured, which is what makes every
## gameplay button stand down (Player._menu_blocks_input) - otherwise the stick that points
## at an entry would also be walking or turning the character.
func _set_open(open: bool) -> void:
	_open = open
	_root.visible = open
	_set_chosen(-1)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if open else Input.MOUSE_MODE_CAPTURED


## A press and a release of `action`, as if its key had been tapped.
func _send(action: String) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


## The entry whose direction is nearest `aim`. Entries are spaced evenly from the top,
## clockwise, so the nearest is a matter of rounding the angle.
func _entry_at(aim: Vector2) -> int:
	# Screen space: up is -y. Measured clockwise from straight up.
	var angle: float = fposmod(atan2(aim.x, -aim.y), TAU)
	var step: float = TAU / ENTRIES.size()
	return int(roundf(angle / step)) % ENTRIES.size()


func _entry_offset(index: int) -> Vector2:
	var angle: float = TAU * index / ENTRIES.size()
	return Vector2(sin(angle), -cos(angle)) * RADIUS


func _set_chosen(index: int) -> void:
	_chosen = index
	for i: int in _cards.size():
		_cards[i].add_theme_stylebox_override("panel", _card_style(i == index))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var hint := Label.new()
	hint.text = "Point a stick and let go"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_root.add_child(hint)

	for i: int in ENTRIES.size():
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_anchors_preset(Control.PRESET_CENTER)
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		card.grow_vertical = Control.GROW_DIRECTION_BOTH
		card.custom_minimum_size = Vector2(150.0, 44.0)
		var offset: Vector2 = _entry_offset(i)
		card.offset_left = offset.x - 75.0
		card.offset_right = offset.x + 75.0
		card.offset_top = offset.y - 22.0
		card.offset_bottom = offset.y + 22.0
		var label := Label.new()
		label.text = String(ENTRIES[i][0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		card.add_child(label)
		_root.add_child(card)
		_cards.append(card)


func _card_style(chosen: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.12, 0.04, 0.95) if chosen else Color(0.02, 0.025, 0.035, 0.88)
	style.border_color = Color(1.0, 0.8, 0.3) if chosen else Color(0.45, 0.4, 0.3, 0.8)
	style.set_border_width_all(3 if chosen else 2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style
