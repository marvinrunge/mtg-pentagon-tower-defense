extends CanvasLayer
class_name SkillTree

const COLOR_NAMES: Array[String] = ["white", "blue", "black", "red", "green"]
const COLOR_DISPLAY: Dictionary = {
	"white": "White", "blue": "Blue", "black": "Black", "red": "Red", "green": "Green",
}
const COLOR_MANA: Dictionary = {
	"white": "White", "blue": "Blue", "black": "Black", "red": "Red", "green": "Green",
}
const COLOR_SYMBOL: Dictionary = {
	"white": "{W}", "blue": "{U}", "black": "{B}", "red": "{R}", "green": "{G}",
}
const COLOR_HEX: Dictionary = {
	"white": Color(0.95, 0.91, 0.72),
	"blue": Color(0.18, 0.52, 0.92),
	"black": Color(0.48, 0.25, 0.58),
	"red": Color(0.9, 0.2, 0.14),
	"green": Color(0.18, 0.7, 0.3),
}
const AFFINITY_DATA: Dictionary = {
	"white": {"name": "Holy Strength", "mechanic": "+% Life Regeneration", "flavor": "Protection, restoration, and enduring light."},
	"blue": {"name": "Curiosity", "mechanic": "+% Cooldown Reduction", "flavor": "Mind-speed, mental acuity, and tactical flow."},
	"black": {"name": "Vampiric Link", "mechanic": "+% Lifesteal", "flavor": "Dark bargains, parasitic drain, and vital siphon."},
	"red": {"name": "Reckless Charge", "mechanic": "+% Total Damage", "flavor": "Explosive aggression, raw power, and volatility."},
	"green": {"name": "Wild Growth", "mechanic": "+% Maximum HP", "flavor": "Primal vitality, physical mass, and resilience."},
}
const SPELL_DATA: Dictionary = {
	"white": [
		{"id": "white_1", "name": "Swords to Plowshares", "cost": 1, "desc": "Radiant projectile dealing maximum-HP damage or healing an ally."},
		{"id": "white_2", "name": "Path to Exile", "cost": 3, "desc": "Charged execute projectile that leaves a holy trail."},
		{"id": "white_3", "name": "Wrath of God", "cost": 7, "desc": "Charged nova that heals allies, damages enemies, and blinds."},
		{"id": "white_4", "name": "Pacifism", "cost": 15, "desc": "Reduces enemy damage and clears its current aggro."},
		{"id": "white_5", "name": "Gideon's Reproach", "cost": 30, "desc": "Reflects a portion of incoming damage for a short duration."},
	],
	"blue": [
		{"id": "blue_1", "name": "Unsummon", "cost": 1, "desc": "Damaging force projectile with obstacle-impact damage."},
		{"id": "blue_2", "name": "Aetherize", "cost": 3, "desc": "Charged frontal wave that throws enemies backward."},
		{"id": "blue_3", "name": "Psionic Blast", "cost": 7, "desc": "Powerful long-range strike with a self-HP cost."},
		{"id": "blue_4", "name": "Freeze Breath", "cost": 15, "desc": "Builds Chill stacks that trigger a freezing Shatter blast."},
		{"id": "blue_5", "name": "Counterspell", "cost": 30, "desc": "Briefly negates a hit and clears active spell cooldowns."},
	],
	"black": [
		{"id": "black_1", "name": "Drain Life", "cost": 1, "desc": "Damaging projectile that returns health to its caster."},
		{"id": "black_2", "name": "Toxic Deluge", "cost": 3, "desc": "Sacrifices current HP to create a charged poison zone."},
		{"id": "black_3", "name": "Doom Blade", "cost": 7, "desc": "Heavy strike that curses the target to take more damage."},
		{"id": "black_4", "name": "Tendrils of Agony", "cost": 15, "desc": "Life drain that chains after another recent spell cast."},
		{"id": "black_5", "name": "Sign in Blood", "cost": 30, "desc": "Sacrifices current HP to reset the other cooldowns."},
	],
	"red": [
		{"id": "red_1", "name": "Shock / Lightning Bolt", "cost": 1, "desc": "Fast direct-damage projectile that can gain a chain hit."},
		{"id": "red_2", "name": "Fireball", "cost": 3, "desc": "Charged explosive projectile with a scaling blast radius."},
		{"id": "red_3", "name": "Rain of Ember", "cost": 7, "desc": "Ground-targeted fire zone that burns enemies over time."},
		{"id": "red_4", "name": "Act of Treason", "cost": 15, "desc": "Short-range strike with knockback and stun."},
		{"id": "red_5", "name": "Chandra's Ignition", "cost": 30, "desc": "Large fiery shockwave that damages and pushes enemies."},
	],
	"green": [
		{"id": "green_1", "name": "Titanic Growth", "cost": 1, "desc": "Frontal cleave whose damage scales with maximum HP."},
		{"id": "green_2", "name": "Hurricane / Entangle", "cost": 3, "desc": "Charged rooting field with persistent poison damage."},
		{"id": "green_3", "name": "Overrun", "cost": 7, "desc": "Forward trampling dash with damage and knockback."},
		{"id": "green_4", "name": "Rabid Bite", "cost": 15, "desc": "Heavy bite that heals when used against a rooted enemy."},
		{"id": "green_5", "name": "Briar Patch", "cost": 30, "desc": "Reflects a portion of incoming melee damage."},
	],
}

@onready var control_root: Control = $Control

var _board: Control
var _outer_line: Line2D
var _branch_lines: Dictionary = {}
var _button_records: Array[Dictionary] = []
var _texture_cache: Dictionary = {}
var _center_icon: TextureRect
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_status: Label
var _detail_body: Label
var _hovered_record: Dictionary = {}

# --- Gamepad/keyboard radial navigation (mouse hover still works independently) ---
var _selection_ring: Control
var _selected_color_index: int = 0
var _selected_branch_index: int = 0 # 0 = affinity/center, 1-5 = spell ranks outward

func _ready() -> void:
	hide()
	SignalBus.color_path_chosen.connect(func(_color: String): update_ui())
	SignalBus.mana_changed.connect(func(_pool: Dictionary): update_ui())
	SignalBus.skill_unlocked.connect(func(_color: String): update_ui())
	SignalBus.spell_unlocked.connect(func(_color: String, _spell_id: String): update_ui())
	_build_ui()
	update_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree") or (visible and event.is_action_pressed("ui_cancel")):
		visible = not visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			update_ui()
			_select_node(_selected_color_index, _selected_branch_index)
		else:
			_hide_details()
			if is_instance_valid(_selection_ring):
				_selection_ring.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	# Radial keyboard/gamepad navigation - ui_left/right/up/down/accept already carry
	# sensible engine-default gamepad bindings (d-pad + left stick + face button A).
	if event.is_action_pressed("ui_left"):
		_select_node(wrapi(_selected_color_index - 1, 0, COLOR_NAMES.size()), _selected_branch_index)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_node(wrapi(_selected_color_index + 1, 0, COLOR_NAMES.size()), _selected_branch_index)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select_node(_selected_color_index, wrapi(_selected_branch_index - 1, 0, 6))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_select_node(_selected_color_index, wrapi(_selected_branch_index + 1, 0, 6))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var record: Dictionary = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
		if not record.is_empty():
			_on_node_pressed(record["color"], record["branch_index"], record["info"])
		get_viewport().set_input_as_handled()

func _select_node(color_index: int, branch_index: int) -> void:
	_selected_color_index = color_index
	_selected_branch_index = branch_index
	var color: String = COLOR_NAMES[color_index]
	var record: Dictionary = _find_record(color, branch_index)
	if record.is_empty():
		return
	_show_details(color, branch_index, record["info"])
	_position_selection_ring(record["button"])

func _position_selection_ring(button: TextureButton) -> void:
	if not is_instance_valid(_selection_ring):
		return
	_selection_ring.size = button.size + Vector2(10.0, 10.0)
	_selection_ring.position = button.position - Vector2(5.0, 5.0)
	_selection_ring.show()

func _build_ui() -> void:
	for child: Node in control_root.get_children():
		control_root.remove_child(child)
		child.queue_free()

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.018, 0.022, 0.028, 0.97)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	control_root.add_child(background)

	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.clip_contents = true
	control_root.add_child(_board)

	_outer_line = Line2D.new()
	_outer_line.width = 2.0
	_outer_line.default_color = Color(0.72, 0.68, 0.52, 0.42)
	_outer_line.antialiased = true
	_board.add_child(_outer_line)

	for color: String in COLOR_NAMES:
		var branch_line := Line2D.new()
		branch_line.width = 3.0
		branch_line.default_color = COLOR_HEX[color] * Color(1.0, 1.0, 1.0, 0.46)
		branch_line.antialiased = true
		_board.add_child(branch_line)
		_branch_lines[color] = branch_line

	_center_icon = TextureRect.new()
	_center_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_center_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_center_icon.texture = _get_placeholder_texture("center", 0, "available")
	_center_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_center_icon)

	for color: String in COLOR_NAMES:
		var affinity_info: Dictionary = AFFINITY_DATA[color].duplicate()
		affinity_info["id"] = "affinity_" + color
		affinity_info["cost"] = GameSettings.affinity_rank_mana_cost
		affinity_info["is_affinity"] = true
		_create_icon_node(color, 0, affinity_info)

		var spells: Array = SPELL_DATA[color]
		for spell_index: int in range(spells.size()):
			var spell_info: Dictionary = spells[spell_index].duplicate()
			spell_info["is_affinity"] = false
			spell_info["rank_requirement"] = GameSettings.affinity_spell_rank_requirements[spell_index]
			_create_icon_node(color, spell_index + 1, spell_info)

	_build_selection_ring()
	_build_detail_panel()
	_board.resized.connect(_layout_nodes)
	call_deferred("_layout_nodes")

func _build_selection_ring() -> void:
	_selection_ring = Panel.new()
	_selection_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1.0, 0.85, 0.3, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_selection_ring.add_theme_stylebox_override("panel", style)
	_selection_ring.hide()
	_board.add_child(_selection_ring)

func _create_icon_node(color: String, branch_index: int, info: Dictionary) -> void:
	var button := TextureButton.new()
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(_show_details.bind(color, branch_index, info))
	button.mouse_exited.connect(_hide_details)
	button.pressed.connect(_on_node_pressed.bind(color, branch_index, info))
	_board.add_child(button)
	_button_records.append({"button": button, "color": color, "branch_index": branch_index, "info": info})

func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.size = Vector2(620.0, 116.0)
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.055, 0.97)
	style.border_color = Color(0.75, 0.7, 0.5, 0.65)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_detail_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 18)
	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 13)
	_detail_body = Label.new()
	_detail_body.add_theme_font_size_override("font_size", 13)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_detail_title)
	content.add_child(_detail_status)
	content.add_child(_detail_body)
	margin.add_child(content)
	_detail_panel.add_child(margin)
	_board.add_child(_detail_panel)
	_detail_panel.hide()

func _layout_nodes() -> void:
	if not is_instance_valid(_board) or _board.size.x <= 0.0 or _board.size.y <= 0.0:
		return

	var center := _board.size * 0.5
	var outer_radius: float = minf(_board.size.x * 0.43, _board.size.y * 0.45)
	var inner_radius: float = outer_radius * 0.18
	var outer_vertices := PackedVector2Array()

	_center_icon.size = Vector2(48.0, 48.0)
	_center_icon.position = center - _center_icon.size * 0.5

	for color_index: int in range(COLOR_NAMES.size()):
		var color: String = COLOR_NAMES[color_index]
		var angle: float = -PI * 0.5 + TAU * float(color_index) / float(COLOR_NAMES.size())
		var direction := Vector2(cos(angle), sin(angle))
		var branch_points := PackedVector2Array([center])

		for branch_index: int in range(6):
			var progress: float = float(branch_index) / 5.0
			var radius: float = lerpf(inner_radius, outer_radius, progress)
			var point: Vector2 = center + direction * radius
			branch_points.append(point)
			var record: Dictionary = _find_record(color, branch_index)
			if not record.is_empty():
				var button: TextureButton = record["button"]
				var diameter: float = 48.0 if branch_index == 0 else 40.0
				button.size = Vector2(diameter, diameter)
				button.position = point - button.size * 0.5

		var branch_line: Line2D = _branch_lines[color]
		branch_line.points = branch_points
		outer_vertices.append(center + direction * outer_radius)

	outer_vertices.append(outer_vertices[0])
	_outer_line.points = outer_vertices
	_detail_panel.position = Vector2(center.x - 310.0, _board.size.y - 134.0)

	if is_instance_valid(_selection_ring) and _selection_ring.visible:
		var current_record: Dictionary = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
		if not current_record.is_empty():
			_position_selection_ring(current_record["button"])

func _find_record(color: String, branch_index: int) -> Dictionary:
	for record: Dictionary in _button_records:
		if record["color"] == color and record["branch_index"] == branch_index:
			return record
	return {}

func update_ui() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var main_controller = get_tree().current_scene
	if not player or not main_controller:
		return
	var mana_pool: Dictionary = main_controller.mana_pool

	for record: Dictionary in _button_records:
		var button: TextureButton = record["button"]
		var color: String = record["color"]
		var branch_index: int = record["branch_index"]
		var info: Dictionary = record["info"]
		var available_mana: int = int(mana_pool.get(COLOR_MANA[color], 0))
		var state: String = "available"

		if bool(info["is_affinity"]):
			if available_mana < int(info["cost"]):
				state = "locked"
		else:
			var is_unlocked: bool = player.unlocked_spells_in_path.has(info["id"])
			var gate_met: bool = player.get_affinity_rank(color) >= int(info["rank_requirement"])
			if is_unlocked:
				state = "unlocked"
			elif not gate_met or available_mana < int(info["cost"]):
				state = "locked"

		button.texture_normal = _get_placeholder_texture(color, branch_index, state)
		button.texture_hover = _get_placeholder_texture(color, branch_index, "hover")
		button.modulate = Color.WHITE if player.chosen_color_path == color else Color(0.78, 0.8, 0.82)

	if not _hovered_record.is_empty():
		_show_details(_hovered_record["color"], _hovered_record["branch_index"], _hovered_record["info"])

func _show_details(color: String, branch_index: int, info: Dictionary) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var main_controller = get_tree().current_scene
	if not player or not main_controller:
		return
	var mana_pool: Dictionary = main_controller.mana_pool
	var available_mana: int = int(mana_pool.get(COLOR_MANA[color], 0))
	_hovered_record = {"color": color, "branch_index": branch_index, "info": info}
	_detail_panel.show()
	_detail_title.text = "%s - %s" % [COLOR_DISPLAY[color], info["name"]]
	_detail_title.add_theme_color_override("font_color", COLOR_HEX[color])

	if bool(info["is_affinity"]):
		var rank: int = player.get_affinity_rank(color)
		var bonus: float = player.get_affinity_bonus(color) * 100.0
		var next_bonus: float = _get_next_rank_bonus(rank + 1) * 100.0
		_detail_status.text = "%s  Rank %d  Total %.1f%%  Next +%.1f%%  Mana %d" % [COLOR_SYMBOL[color], rank, bonus, next_bonus, available_mana]
		_detail_body.text = "%s  %s" % [info["mechanic"], info["flavor"]]
	else:
		var gate: int = int(info["rank_requirement"])
		var unlocked: bool = player.unlocked_spells_in_path.has(info["id"])
		var status: String = "UNLOCKED" if unlocked else "Requires affinity rank %d" % gate
		_detail_status.text = "%s  %s  Cost %d mana  Cooldown %.1fs" % [COLOR_SYMBOL[color], status, int(info["cost"]), GameSettings.get_spell_cooldown(info["id"])]
		_detail_body.text = info["desc"]

func _hide_details() -> void:
	_hovered_record.clear()
	if is_instance_valid(_detail_panel):
		_detail_panel.hide()

func _on_node_pressed(color: String, _branch_index: int, info: Dictionary) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var main_controller = get_tree().current_scene
	if not player or not main_controller or not main_controller.has_method("spend_mana_cost"):
		return
	var mana_key: String = COLOR_MANA[color]

	if bool(info["is_affinity"]):
		if main_controller.spend_mana_cost({mana_key: int(info["cost"])}):
			player.invest_affinity(color)
			update_ui()
		return

	if player.unlocked_spells_in_path.has(info["id"]):
		player.select_color_path(color)
		update_ui()
		return
	if player.get_affinity_rank(color) < int(info["rank_requirement"]):
		return
	if main_controller.spend_mana_cost({mana_key: int(info["cost"])}):
		SignalBus.spell_unlocked.emit(color, info["id"])
		update_ui()

func _get_next_rank_bonus(next_rank: int) -> float:
	if next_rank <= 10:
		return GameSettings.affinity_rank_bonus_early
	if next_rank <= 20:
		return GameSettings.affinity_rank_bonus_mid
	return GameSettings.affinity_rank_bonus_late

func _get_placeholder_texture(color: String, branch_index: int, state: String) -> ImageTexture:
	var cache_key: String = "%s_%d_%s" % [color, branch_index, state]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var base_color: Color = Color(0.72, 0.7, 0.6) if color == "center" else COLOR_HEX[color]
	if state == "locked":
		base_color = base_color.lerp(Color(0.16, 0.17, 0.18), 0.72)
	elif state == "unlocked":
		base_color = base_color.lightened(0.18)
	elif state == "hover":
		base_color = base_color.lightened(0.3)

	var texture_center := Vector2(47.5, 47.5)
	for y: int in range(96):
		for x: int in range(96):
			var offset := Vector2(float(x), float(y)) - texture_center
			var distance: float = offset.length()
			if distance > 45.0:
				continue
			var pixel_color: Color = base_color.darkened(0.28 * distance / 45.0)
			if distance > 39.0:
				pixel_color = base_color.lightened(0.3)
			if _is_placeholder_mark(offset, branch_index):
				pixel_color = Color(0.96, 0.94, 0.82, 1.0)
			image.set_pixel(x, y, pixel_color)

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture

func _is_placeholder_mark(offset: Vector2, branch_index: int) -> bool:
	var abs_x: float = absf(offset.x)
	var abs_y: float = absf(offset.y)
	match branch_index:
		0:
			return absf(offset.length() - 16.0) < 3.0 or (abs_x < 3.0 and abs_y < 10.0)
		1:
			return abs_x < 3.0 and abs_y < 18.0
		2:
			return absf(abs_x - abs_y) < 3.0 and abs_x < 15.0
		3:
			return (absf(abs_x - 14.0) < 3.0 and abs_y < 14.0) or (absf(abs_y - 14.0) < 3.0 and abs_x < 14.0)
		4:
			return absf(abs_x + abs_y - 20.0) < 3.0
		5:
			return absf(offset.length() - 18.0) < 3.0 or absf(offset.length() - 9.0) < 2.0
		_:
			return abs_x < 3.0 or abs_y < 3.0
