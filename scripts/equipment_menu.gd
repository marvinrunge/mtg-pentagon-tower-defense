extends CanvasLayer
## The equipment screen (I): everything the team has found, and what this player wears.
##
## Equipment is not bought in the skill tree - it drops from bosses and belongs to the team
## (RunState.equipment_unlocked). This is where a player looks through what has been found
## and puts pieces on or takes them off, which is a personal choice (Player.equipped_items),
## so two players can wear different things from the same stash.
##
## Pieces nobody has found yet are still listed, greyed out with the boss that drops them:
## knowing that the red boss carries the boots is what makes the red lane worth a detour.
##
## Built in code, like MainMenu and SettingsMenu. Added by the HUD, so it exists wherever a
## run does and nowhere else. Deliberately no `class_name` - see scripts/icon_style.gd.

const EquipmentDatabase := preload("res://scripts/equipment_database.gd")
const IconStyle := preload("res://scripts/icon_style.gd")

const CARD_SIZE := Vector2(300.0, 104.0)
const ICON_SIZE := 64.0
const GOLD := Color(1.0, 0.85, 0.35)

var _root: Control
var _grid: GridContainer
var _summary: Label
var _debug_button: Button
## id -> {panel, icon, name, status}, so a refresh restyles instead of rebuilding.
var _cards: Dictionary = {}


func _ready() -> void:
	layer = 110
	visible = false
	_build()
	SignalBus.equipment_unlocked_changed.connect(func(_item: String) -> void: _refresh())
	SignalBus.equipment_changed.connect(func(_player: Node) -> void: _refresh())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("equipment") or (visible and event.is_action_pressed("ui_cancel")):
		# Not over another menu: the skill tree and the settings each own the screen while open.
		if not visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		set_open(not visible)
		get_viewport().set_input_as_handled()


## Opening and closing in one place, the same way SkillTree.set_open does it - both have to
## leave the mouse the way the game needs it, and tell the HUD to step aside.
func set_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	SignalBus.menu_opened.emit("equipment", open)
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.022, 0.028, 0.95)
	_root.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.offset_left = -490.0
	panel.offset_right = 490.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.045, 1.0)
	style.border_color = Color(0.72, 0.62, 0.36, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	CloseButton.attach(_root, panel, func() -> void: set_open(false))

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	column.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	centre.add_child(_grid)

	for item_id: String in EquipmentDatabase.ORDER:
		_grid.add_child(_build_card(item_id))

	# A way to try the pieces on without farming bosses for them, for whoever is testing.
	# Only on a machine that may unlock anything - the server - and only in debug builds.
	_debug_button = Button.new()
	_debug_button.text = "Unlock all (debug)"
	_debug_button.custom_minimum_size = Vector2(0.0, 32.0)
	_debug_button.pressed.connect(func() -> void:
		for item_id: String in EquipmentDatabase.ORDER:
			RunState.unlock_equipment(item_id))
	column.add_child(_debug_button)


func _build_card(item_id: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = EquipmentDatabase.source_text(item_id)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle(item_id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = EquipmentDatabase.icon(item_id)
	# Round, like every other passive: equipment is always on and never goes on the bar.
	icon.material = IconStyle.circle_material()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var name_label := Label.new()
	name_label.text = EquipmentDatabase.display_name(item_id)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)

	var desc := Label.new()
	desc.text = EquipmentDatabase.description(item_id)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(desc)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(status)

	_cards[item_id] = {"panel": card, "icon": icon, "name": name_label, "status": status}
	return card


func _toggle(item_id: String) -> void:
	var player: Node = PlayerRegistry.get_local()
	if player == null or not player.has_method("set_equipped"):
		return
	if not RunState.is_equipment_unlocked(item_id):
		return
	var wear: bool = not bool(player.is_equipped(item_id))
	if player.set_equipped(item_id, wear):
		SoundBank.play(&"skill_unlock")


func _refresh() -> void:
	if not visible:
		return
	var player: Node = PlayerRegistry.get_local()
	var found: int = 0
	var worn: int = 0
	for item_id: String in EquipmentDatabase.ORDER:
		var unlocked: bool = RunState.is_equipment_unlocked(item_id)
		var equipped: bool = player != null and player.has_method("is_equipped") and bool(player.is_equipped(item_id))
		if unlocked:
			found += 1
		if equipped:
			worn += 1
		_style_card(item_id, unlocked, equipped)

	var limit: int = GameSettings.equipment_max_equipped
	var worn_text: String = ("%d/%d worn" % [worn, limit]) if limit > 0 else ("%d worn" % worn)
	_summary.text = "Bosses drop equipment for the whole team - %d of %d found, %s. Click a piece to put it on or take it off." % [
		found, EquipmentDatabase.ORDER.size(), worn_text]
	_debug_button.visible = GameSettings.debug_mode and Net.is_server() and found < EquipmentDatabase.ORDER.size()


func _style_card(item_id: String, unlocked: bool, equipped: bool) -> void:
	var card: Dictionary = _cards[item_id]
	var panel: PanelContainer = card["panel"]
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	for side: String in ["left", "right", "top", "bottom"]:
		box.set("content_margin_" + side, 10.0)
	var status: Label = card["status"]
	if equipped:
		box.bg_color = Color(0.13, 0.11, 0.05, 1.0)
		box.border_color = GOLD
		status.text = "Equipped - click to take off"
		status.add_theme_color_override("font_color", GOLD)
	elif unlocked:
		box.bg_color = Color(0.06, 0.07, 0.09, 1.0)
		box.border_color = Color(0.38, 0.42, 0.5)
		status.text = "Found - click to equip"
		status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.62))
	else:
		box.bg_color = Color(0.04, 0.045, 0.055, 1.0)
		box.border_color = Color(0.2, 0.22, 0.26)
		status.text = EquipmentDatabase.source_text(item_id)
		status.add_theme_color_override("font_color", Color(0.55, 0.56, 0.6))
	panel.add_theme_stylebox_override("panel", box)
	(card["icon"] as TextureRect).modulate = Color.WHITE if unlocked else Color(0.3, 0.31, 0.34)
	(card["name"] as Label).add_theme_color_override(
		"font_color", Color(0.95, 0.93, 0.86) if unlocked else Color(0.55, 0.56, 0.6))
