extends Button
class_name CloseButton
## The X in the corner of a menu.
##
## Every menu in the game closes on Escape, and Escape is the one key a windowed game
## cannot rely on: alt-tab away and back and the press can go to the window manager
## instead of to the game, leaving a player stood inside a full-screen panel with no way
## out of it. This is the way out that does not depend on a key arriving.
##
## Deliberately a plain Button built in code rather than a widget in each scene: there are
## three menus, they were authored at different times, and the alternative was the same
## corner drawn three slightly different ways.

## Big enough to hit without aiming, small enough not to crowd a panel corner.
const SIZE: Vector2 = Vector2(34.0, 34.0)
const MARGIN: float = 12.0


## The button itself, unplaced. Use `attach` unless the caller wants to position it.
static func build(on_pressed: Callable) -> CloseButton:
	var button := CloseButton.new()
	button.name = "CloseButton"
	button.text = "✕"
	button.custom_minimum_size = SIZE
	button.tooltip_text = "Close  (Esc)"
	# Never takes keyboard focus. The skill tree drives its selection with the arrow keys
	# and ui_accept, and a focused button would swallow both.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.88))
	button.add_theme_stylebox_override("normal", _style(Color(0.10, 0.11, 0.14, 0.92), Color(0.36, 0.38, 0.44)))
	button.add_theme_stylebox_override("hover", _style(Color(0.42, 0.14, 0.14, 0.96), Color(0.86, 0.36, 0.32)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.30, 0.10, 0.10, 0.98), Color(0.7, 0.28, 0.26)))
	button.pressed.connect(on_pressed)
	return button


## Pins the button to `panel`'s own top-right corner, as a child of `parent`.
##
## The corner is taken from the panel's ANCHORS, not from its rectangle, so the button
## follows it when the window is resized instead of sitting where the panel happened to be
## the moment this ran. `parent` has to be a plain Control - a container would lay the
## button out itself and throw the placement away, which is why this does not simply
## parent it to the panel.
static func attach(parent: Control, panel: Control, on_pressed: Callable) -> CloseButton:
	var button := build(on_pressed)
	parent.add_child(button)
	button.anchor_left = panel.anchor_right
	button.anchor_right = panel.anchor_right
	button.anchor_top = panel.anchor_top
	button.anchor_bottom = panel.anchor_top
	button.offset_right = panel.offset_right - MARGIN
	button.offset_left = button.offset_right - SIZE.x
	button.offset_top = panel.offset_top + MARGIN
	button.offset_bottom = button.offset_top + SIZE.y
	# Above the panel it belongs to, or a panel with its own z_index draws over it.
	button.z_index = panel.z_index + 1
	# Not a child of the panel (a container would lay it out), which means it does not
	# inherit the panel's visibility either - so the Escape menu closed and left its X
	# floating over the game with nothing behind it. Mirrored explicitly instead.
	button.visible = panel.visible
	panel.visibility_changed.connect(func() -> void:
		if is_instance_valid(button):
			button.visible = panel.visible)
	return button


static func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	return box
