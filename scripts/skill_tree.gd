extends CanvasLayer
class_name SkillTree

const COLOR_NAMES: Array[String] = ["white", "blue", "black", "red", "green"]
## Rounds every node icon by the same fraction the hotbar rounds its own.
const IconStyle := preload("res://scripts/icon_style.gd")
## The hub at the middle of the pentagon. It belongs to no colour and gates no
## spell - it is the one colourless purchase, paid for out of any mana, and it
## lengthens the player's light attack chain by a stage.
const CENTER_KEY: String = "center"
const CENTER_BRANCH: int = -1
## The two aura nodes sit past the end of a colour's branch, splayed either side of
## it - the fork in docs/SKILL_DESIGN.md drawn as a fork. 6 is the Attunement (the stat
## line), 7 the Manifestation (the visible one).
const AURA_BRANCHES: Array[int] = [6, 7]
## The guild passive's index in the radial navigation. It is DRAWN on the bisector
## between two colour spokes rather than on either, but the colour x branch grid needs
## a home for it, so it files under the gap's counterclockwise colour, past the fork.
const PASSIVE_BRANCH: int = 8
## One past the last real branch index, for the radial keyboard navigation's wrap.
const BRANCH_COUNT: int = 9
const CENTER_INFO: Dictionary = {
	"id": "melee_combo",
	"name": "Blade Dance",
	"desc": "Extends the light attack chain with a third strike that lands harder.",
	"is_affinity": false,
	"is_center": true,
}
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
## The five neutral passives, one per adjacent colour pair - the pentagon's gaps are
## the guilds. PASSIVE_ORDER is in gap order: gap i lies between COLOR_NAMES[i] and the
## next colour clockwise. Five ranks each, one skill point per rank, gated only by the
## shared team level.
const PASSIVE_ORDER: Array[String] = ["flight", "double_strike", "haste", "trample_strike", "vigilance"]
const PASSIVE_DATA: Dictionary = {
	"flight": {"name": "Flying", "guild": "Azorius", "colors": ["white", "blue"],
		"unit": "jump height",
		"desc": "Jump higher, and hold jump while falling to glide. 50% higher per rank, up to 250%."},
	"double_strike": {"name": "Double Strike", "guild": "Dimir", "colors": ["blue", "black"],
		"unit": "crit chance",
		"desc": "Everything you deal - melee and spells - can crit for double damage. 10% chance at rank 1, up to 50%."},
	"haste": {"name": "Haste", "guild": "Rakdos", "colors": ["black", "red"],
		"unit": "move speed",
		"desc": "Move faster. 10% at rank 1, up to 50%."},
	"trample_strike": {"name": "Trample", "guild": "Gruul", "colors": ["red", "green"],
		"unit": "of max HP",
		"desc": "Melee hits add bonus damage from your own max HP. 10% at rank 1, up to 50%."},
	"vigilance": {"name": "Vigilance", "guild": "Selesnya", "colors": ["green", "white"],
		"unit": "duration",
		"desc": "Your spells with a duration last longer. 10% longer per rank, up to 100%."},
}
# Spell rows come from SpellDatabase - names, costs and descriptions used to be
# duplicated here and drifted from the versions in player.gd and game_settings.gd.
@onready var control_root: Control = $Control

var _board: Control
var _passive_lines: Array[Line2D] = []
## Where each branch sits inside its colour's wedge: x is the angle off the colour's own
## axis in degrees, y is how far out it sits between the hub and the rim.
##
## A colour is a TREE, not a line. It used to be six nodes strung along one spoke, which
## made every colour identical in shape, wasted the whole width of its wedge, and said
## nothing about which spells belong together. Now it opens out:
##
##       affinity              one node, on the axis
##      /        \
##   spell 1   spell 2         the two the colour opens with
##    /   \    /   \
##  s3     s4      s5          the three it builds towards
##
## Red reads as: affinity, then Fireball and Fire Dash, then Rain of Ember, Fire Cone and
## Lightning Bolt. The wedge is 72 degrees wide, so the widest pair at 26 degrees still
## leaves a clear gap to the neighbouring colour - and the guild passive that sits on the
## bisector between them is at a different radius again.
const BRANCH_LAYOUT: Dictionary = {
	0: Vector2(0.0, 0.12),
	1: Vector2(-14.0, 0.58),
	2: Vector2(14.0, 0.58),
	3: Vector2(-26.0, 1.0),
	4: Vector2(0.0, 1.0),
	5: Vector2(26.0, 1.0),
}

## Which nodes are joined by a line, as pairs of branch indices (CENTER_BRANCH is the hub).
##
## The middle of the outer row is fed by BOTH openers rather than by one of them: three
## children over two parents has no symmetric strict-tree answer, and the diamond that
## makes reads as a lattice rather than as an arbitrary choice about which opener owns it.
## The two outer aura choices hang off neighbouring finisher skills. Each has two routes
## in, but the two choices do not connect directly to each other.
const BRANCH_EDGES: Array = [
	[CENTER_BRANCH, 0],
	[0, 1], [0, 2],
	[1, 3], [1, 4], [2, 4], [2, 5],
	[3, AURA_BRANCHES[0]], [4, AURA_BRANCHES[0]],
	[4, AURA_BRANCHES[1]], [5, AURA_BRANCHES[1]],
]

## Bigger nearer the trunk, so the eye reads the hierarchy before it reads the icons.
const BRANCH_DIAMETERS: Dictionary = {0: 48.0, 1: 44.0, 2: 44.0, 3: 40.0, 4: 40.0, 5: 40.0}

var _branch_lines: Dictionary = {}
var _button_records: Array[Dictionary] = []
var _texture_cache: Dictionary = {}
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_status: Label
var _detail_body: Label
var _hovered_record: Dictionary = {}
## Prominent, always-visible counter of the player's spendable skill points. Sits above
## the pentagon rather than buried in a corner, because it is the one number every
## purchase in this screen revolves around.
var _skill_points_label: Label
## The team level, drawn in the middle of the pentagon where Blade Dance used to sit. It is
## the one number the whole board is measured against, so it belongs at the centre of it.
var _level_badge: Panel
var _level_label: Label

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
	SignalBus.spell_rank_changed.connect(func(_spell_id: String, _rank: int): update_ui())
	SignalBus.passive_rank_changed.connect(func(_passive_id: String, _rank: int): update_ui())
	SignalBus.quick_slots_changed.connect(update_ui)
	SignalBus.skill_points_changed.connect(func(_player: Node, _points: int): update_ui())
	# The hub shows the team level now, so the board has to follow it.
	SignalBus.team_level_changed.connect(func(_level: int, _gained: int): update_ui())
	_build_ui()
	# The way out that is not a keystroke. See CloseButton.
	CloseButton.attach($Control, $Control, func() -> void: set_open(false))
	update_ui()


## Opening and closing, in one place because there are two ways in now - the key and the
## button in the corner - and they have to leave the mouse in the same state. A menu that
## closes without restoring MOUSE_MODE_CAPTURED leaves the player unable to look around.
func set_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	SignalBus.menu_opened.emit("skill_tree", visible)
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		update_ui()
		_select_node(_selected_color_index, _selected_branch_index)
	else:
		_hide_details()
		if is_instance_valid(_selection_ring):
			_selection_ring.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree") or (visible and event.is_action_pressed("ui_cancel")):
		set_open(not visible)
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	# Spatial keyboard/gamepad navigation - each direction chooses the nearest visible
	# node in that direction, so the controls follow the tree on screen instead of an
	# abstract colour/branch grid.
	if event.is_action_pressed("ui_left"):
		_select_direction(Vector2.LEFT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_direction(Vector2.RIGHT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select_direction(Vector2.UP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_select_direction(Vector2.DOWN)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var record: Dictionary = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
		if not record.is_empty():
			_on_node_pressed(record["color"], record["branch_index"], record["info"])
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode < KEY_1 + Player.QUICK_SLOT_COUNT:
		# Number keys bind whatever the pointer or the selection is on to that hotbar
		# slot. This is the whole loadout UI: the alternative was a drag-and-drop bar,
		# and the keys being bound ARE the keys you press to cast, which is easier to
		# explain than any widget would be.
		_bind_hovered_to_slot(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()

func _select_node(color_index: int, branch_index: int) -> void:
	var color: String = COLOR_NAMES[color_index]
	var record: Dictionary = _find_record(color, branch_index)
	if record.is_empty():
		return
	_select_record(record)

func _select_record(record: Dictionary) -> void:
	var record_color: String = String(record["color"])
	if COLOR_NAMES.has(record_color):
		_selected_color_index = COLOR_NAMES.find(record_color)
	_selected_branch_index = int(record["branch_index"])
	_show_details(record["color"], int(record["branch_index"]), record["info"])
	_position_selection_ring(record["button"])

func _select_direction(direction: Vector2) -> void:
	var current: Dictionary = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
	if current.is_empty():
		return
	var current_button: TextureButton = current["button"]
	var current_center: Vector2 = current_button.position + current_button.size * 0.5
	var best_record: Dictionary = {}
	var best_score: float = INF
	for record: Dictionary in _button_records:
		var candidate_button: TextureButton = record["button"]
		if candidate_button == current_button:
			continue
		var offset: Vector2 = candidate_button.position + candidate_button.size * 0.5 - current_center
		var distance: float = offset.length()
		if distance <= 0.01:
			continue
		var alignment: float = direction.dot(offset / distance)
		if alignment < 0.35:
			continue
		var score: float = distance / alignment
		if score < best_score:
			best_score = score
			best_record = record
	if not best_record.is_empty():
		_select_record(best_record)

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

	_level_badge = Panel.new()
	_level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_badge.z_index = 1
	var level_badge_style := StyleBoxFlat.new()
	level_badge_style.bg_color = Color(0.025, 0.03, 0.035, 0.94)
	level_badge_style.border_color = Color(0.72, 0.68, 0.52, 0.9)
	level_badge_style.set_border_width_all(2)
	level_badge_style.set_corner_radius_all(1000)
	_level_badge.add_theme_stylebox_override("panel", level_badge_style)
	_board.add_child(_level_badge)

	_level_label = Label.new()
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.z_index = 2
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 34)
	_level_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.82))
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_level_label.add_theme_constant_override("outline_size", 6)
	_board.add_child(_level_label)

	_skill_points_label = Label.new()
	_skill_points_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skill_points_label.position = Vector2(-320.0, 18.0)
	_skill_points_label.size = Vector2(300.0, 40.0)
	_skill_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_points_label.add_theme_font_size_override("font_size", 32)
	_skill_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_skill_points_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_skill_points_label.add_theme_constant_override("outline_size", 6)
	control_root.add_child(_skill_points_label)

	for _connection: int in range(COLOR_NAMES.size() * 2):
		var passive_line := Line2D.new()
		passive_line.width = 2.0
		passive_line.default_color = Color(0.72, 0.68, 0.52, 0.42)
		passive_line.antialiased = true
		_board.add_child(passive_line)
		_passive_lines.append(passive_line)

	for color: String in COLOR_NAMES:
		# One Line2D per EDGE now. A branching colour is not a polyline, and a single Line2D
		# can only ever draw one continuous run of points.
		var edges: Array[Line2D] = []
		for _edge: Array in BRANCH_EDGES:
			var branch_line := Line2D.new()
			branch_line.width = 3.0
			branch_line.default_color = COLOR_HEX[color] * Color(1.0, 1.0, 1.0, 0.46)
			branch_line.antialiased = true
			_board.add_child(branch_line)
			edges.append(branch_line)
		_branch_lines[color] = edges

	var center_info: Dictionary = CENTER_INFO.duplicate()
	center_info["cost"] = GameSettings.melee_combo_unlock_cost
	_create_icon_node(CENTER_KEY, CENTER_BRANCH, center_info)

	for color: String in COLOR_NAMES:
		var affinity_info: Dictionary = AFFINITY_DATA[color].duplicate()
		affinity_info["id"] = "affinity_" + color
		affinity_info["cost"] = GameSettings.affinity_rank_mana_cost
		affinity_info["is_affinity"] = true
		_create_icon_node(color, 0, affinity_info)

		var spells: Array = SpellDatabase.get_spells_for_color(color)
		for spell_index: int in range(spells.size()):
			var spell_info: Dictionary = spells[spell_index].duplicate()
			spell_info["is_affinity"] = false
			spell_info["rank_requirement"] = GameSettings.affinity_spell_rank_requirements[spell_index]
			_create_icon_node(color, spell_index + 1, spell_info)

		# The outer aura pair. Both are visible, rankable choices, but buying one side
		# locks the other side for this colour.
		var auras: Array[Dictionary] = SpellDatabase.get_auras(color)
		for half: int in range(auras.size()):
			var aura_info: Dictionary = auras[half].duplicate()
			aura_info["is_affinity"] = false
			# Still true, and it is a TYPE marker rather than a rule: it is what tells the
			# purchase path to call grant_aura_rank instead of grant_spell_rank, because these
			# two nodes grant an aura and the other five grant a castable spell. Setting it
			# false to "remove auras" routed them down the spell path, where there is no
			# spell by that id, and they silently stopped being buyable at all.
			#
			# What removing auras actually meant is three rules, all gone above: the
			# one-or-the-other exclusivity, the 20-rank gate, and the exemption from being
			# hidden until a neighbour is owned.
			aura_info["is_aura"] = true
			aura_info["cost"] = GameSettings.spell_rank_point_cost
			# No special gate: reached by connecting to a neighbour, like everything else on the
			# board. These two used to sit behind 20 owned ranks and refuse each other, which
			# made them an end-of-run reward rather than a skill.
			_create_icon_node(color, AURA_BRANCHES[half], aura_info)

	# The five guild passives, one per gap between adjacent colours. Filed under the
	# gap's counterclockwise colour at PASSIVE_BRANCH so the radial grid can reach them;
	# _layout_nodes draws them on the gap's bisector instead.
	for gap: int in range(COLOR_NAMES.size()):
		var passive_id: String = PASSIVE_ORDER[gap]
		var passive_info: Dictionary = PASSIVE_DATA[passive_id].duplicate()
		passive_info["id"] = passive_id
		passive_info["is_passive"] = true
		passive_info["rank_requirement"] = GameSettings.rank_level_requirement(1)
		_create_icon_node(COLOR_NAMES[gap], PASSIVE_BRANCH, passive_info)

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
	# The same rounding the hotbar gives its icons: a node in the tree and the slot it
	# gets bound to are the same picture, and they have to read as the same object.
	button.material = IconStyle.rounded_material()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(_show_details.bind(color, branch_index, info))
	button.mouse_exited.connect(_hide_details)
	button.pressed.connect(_on_node_pressed.bind(color, branch_index, info))
	_board.add_child(button)

	# Rank and hotbar key, drawn on the node itself. A tree where you have to hover every
	# node to find out what you already own is a tree nobody reads.
	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.hide()
	_board.add_child(badge)

	_button_records.append({
		"button": button, "badge": badge, "color": color,
		"branch_index": branch_index, "info": info,
	})

## Binds whatever node the player is pointing at to a hotbar slot. Silent on anything
## that is not an owned spell - a aura or an affinity node has nothing to cast.
func _bind_hovered_to_slot(slot_index: int) -> void:
	var record: Dictionary = _hovered_record
	if record.is_empty():
		record = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
	if record.is_empty():
		return
	var info: Dictionary = record["info"]
	if bool(info.get("is_affinity", false)) or bool(info.get("is_aura", false)) or bool(info.get("is_center", false)) or bool(info.get("is_passive", false)):
		return
	var player = PlayerRegistry.get_local()
	if player == null or not player.has_method("assign_quick_slot"):
		return
	if player.assign_quick_slot(slot_index, String(info["id"])):
		update_ui()
		_show_details(String(record["color"]), int(record["branch_index"]), info)


## Which hotbar key casts this spell, or 0 for one that is not bound. Printed in the
## detail panel, because a loadout the player cannot read is a loadout they will not use.
func _slot_of(player: Node, spell_id: String) -> int:
	if player == null or not ("quick_slots" in player):
		return 0
	var index: int = player.quick_slots.find(spell_id)
	return index + 1


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

	# The detail panel is an overlay, so the pentagon can use the full window. Its position
	# is chosen from the hovered node below, keeping the selected node readable at either
	# edge of the tree.
	var center := Vector2(_board.size.x * 0.5, _board.size.y * 0.5)
	var outer_radius: float = minf(_board.size.x * 0.43, _board.size.y * 0.46)
	var branch_radius: float = outer_radius * 0.87
	var inner_radius: float = branch_radius * 0.18
	var icon_scale: float = clampf(minf(_board.size.x, _board.size.y) / 720.0, 1.0, 2.0)
	var node_centers: Dictionary = {}
	var center_record: Dictionary = _find_record(CENTER_KEY, CENTER_BRANCH)
	if not center_record.is_empty():
		var center_button: TextureButton = center_record["button"]
		center_button.size = Vector2(48.0, 48.0) * icon_scale
		center_button.position = center - center_button.size * 0.5
	if is_instance_valid(_level_label):
		# Over the hub, which now draws nothing of its own.
		_level_label.size = Vector2(120.0, 48.0)
		_level_label.position = center - _level_label.size * 0.5
	if is_instance_valid(_level_badge):
		_level_badge.size = Vector2(58.0, 58.0) * icon_scale
		_level_badge.position = center - _level_badge.size * 0.5

	for color_index: int in range(COLOR_NAMES.size()):
		var color: String = COLOR_NAMES[color_index]
		var angle: float = -PI * 0.5 + TAU * float(color_index) / float(COLOR_NAMES.size())
		var direction := Vector2(cos(angle), sin(angle))
		# Every node's centre, kept so the edges can be drawn between them afterwards
		# rather than guessed at a second time.
		var points: Dictionary = {CENTER_BRANCH: center}

		for branch_index: int in range(6):
			var layout: Vector2 = BRANCH_LAYOUT[branch_index]
			var node_angle: float = angle + deg_to_rad(layout.x)
			var radius: float = lerpf(inner_radius, branch_radius, layout.y)
			var point: Vector2 = center + Vector2(cos(node_angle), sin(node_angle)) * radius
			points[branch_index] = point
			node_centers["%s_%d" % [color, branch_index]] = point
			var record: Dictionary = _find_record(color, branch_index)
			if not record.is_empty():
				var button: TextureButton = record["button"]
				var diameter: float = float(BRANCH_DIAMETERS.get(branch_index, 40.0)) * icon_scale
				button.size = Vector2(diameter, diameter)
				button.position = point - button.size * 0.5
				_place_badge(record, button)

		# The fork: past the end of the branch and splayed to either side of it, so the
		# two halves read as alternatives to each other rather than as two more steps.
		var fork_radius: float = outer_radius
		for half: int in range(AURA_BRANCHES.size()):
			# Splayed narrowly, INSIDE the outer row's own spread: the fork is the tip of
			# the colour, and a fork wider than the row it grows out of reads as a sixth
			# and seventh spell rather than as a choice between two endings.
			var splay: float = deg_to_rad(-11.0 if half == 0 else 11.0)
			var fork_direction := Vector2(cos(angle + splay), sin(angle + splay))
			var fork_point: Vector2 = center + fork_direction * fork_radius
			points[AURA_BRANCHES[half]] = fork_point
			var fork_record: Dictionary = _find_record(color, AURA_BRANCHES[half])
			if fork_record.is_empty():
				continue
			var fork_button: TextureButton = fork_record["button"]
			fork_button.size = Vector2(44.0, 44.0) * icon_scale
			fork_button.position = fork_point - fork_button.size * 0.5
			_place_badge(fork_record, fork_button)

		var edge_lines: Array = _branch_lines[color]
		for edge_index: int in range(BRANCH_EDGES.size()):
			var edge: Array = BRANCH_EDGES[edge_index]
			var line: Line2D = edge_lines[edge_index]
			if points.has(edge[0]) and points.has(edge[1]):
				line.points = PackedVector2Array([points[edge[0]], points[edge[1]]])
			else:
				line.points = PackedVector2Array()
	# The guild passives sit on the bisector of their two colours, a little inside the
	# ring of spell nodes - between the colours, which is the whole point of them.
	var passive_points: Array[Vector2] = []
	for gap: int in range(COLOR_NAMES.size()):
		var passive_record: Dictionary = _find_record(COLOR_NAMES[gap], PASSIVE_BRANCH)
		if passive_record.is_empty():
			continue
		var bisector: float = -PI * 0.5 + TAU * (float(gap) + 0.5) / float(COLOR_NAMES.size())
		var passive_button: TextureButton = passive_record["button"]
		passive_button.size = Vector2(36.0, 36.0) * icon_scale
		var passive_point: Vector2 = center + Vector2(cos(bisector), sin(bisector)) * (branch_radius * 0.55)
		passive_points.append(passive_point)
		passive_button.position = passive_point - passive_button.size * 0.5
		_place_badge(passive_record, passive_button)

	for gap: int in range(passive_points.size()):
		var next_color_index: int = (gap + 1) % COLOR_NAMES.size()
		var left_key: String = "%s_%d" % [COLOR_NAMES[gap], 2]
		var right_key: String = "%s_%d" % [COLOR_NAMES[next_color_index], 1]
		var passive_point: Vector2 = passive_points[gap]
		var line_index: int = gap * 2
		_passive_lines[line_index].points = PackedVector2Array([passive_point, node_centers[left_key]])
		_passive_lines[line_index + 1].points = PackedVector2Array([passive_point, node_centers[right_key]])
	if not _hovered_record.is_empty():
		var hovered_layout: Dictionary = _find_record(
			String(_hovered_record["color"]), int(_hovered_record["branch_index"]))
		if not hovered_layout.is_empty():
			_position_detail_panel(hovered_layout["button"])
	else:
		_detail_panel.position = Vector2(
			maxf((_board.size.x - _detail_panel.size.x) * 0.5, 18.0),
			_board.size.y - _detail_panel.size.y - 18.0)

	if is_instance_valid(_selection_ring) and _selection_ring.visible:
		var current_record: Dictionary = _find_record(COLOR_NAMES[_selected_color_index], _selected_branch_index)
		if not current_record.is_empty():
			_position_selection_ring(current_record["button"])

## The rank badge sits just under its node. Its own child of the board rather than a
## child of the button, because a TextureButton lays its children out to fill itself.
func _place_badge(record: Dictionary, button: TextureButton) -> void:
	if not record.has("badge"):
		return
	var badge: Label = record["badge"]
	badge.size = Vector2(button.size.x + 24.0, 16.0)
	badge.position = Vector2(button.position.x - 12.0, button.position.y + button.size.y - 2.0)


func _position_detail_panel(button: TextureButton) -> void:
	var side_margin: float = 18.0
	var max_x: float = maxf(side_margin, _board.size.x - _detail_panel.size.x - side_margin)
	var panel_x: float = clampf(
		button.position.x + button.size.x * 0.5 - _detail_panel.size.x * 0.5,
		side_margin, max_x)
	var node_center_y: float = button.position.y + button.size.y * 0.5
	var panel_y: float
	if node_center_y < _board.size.y * 0.5:
		panel_y = _board.size.y - _detail_panel.size.y - side_margin
	else:
		panel_y = side_margin
	_detail_panel.position = Vector2(panel_x, panel_y)


func _find_record(color: String, branch_index: int) -> Dictionary:
	# The hub sits under every colour: whichever branch the selection is on, stepping
	# inward past the affinity node arrives at the same node.
	if branch_index == CENTER_BRANCH:
		color = CENTER_KEY
	for record: Dictionary in _button_records:
		if record["color"] == color and record["branch_index"] == branch_index:
			return record
	return {}

func update_ui() -> void:
	# Nothing to draw while the board is closed, and this is called from eight signals -
	# one of them `mana_changed`, which fires on every enemy that dies. A full pass
	# restyles forty nodes and loads an icon for each, so a wave was rebuilding the whole
	# tree once per kill behind a hidden panel. set_open() refreshes on the way in, so
	# skipping here costs nothing.
	if not visible:
		return
	var player = PlayerRegistry.get_local()
	if player == null:
		return
	if is_instance_valid(_skill_points_label):
		_skill_points_label.text = "Skill Points: %d" % _skill_points(player)
	var mana_pool: Dictionary = RunState.mana_pool

	for record: Dictionary in _button_records:
		var button: TextureButton = record["button"]
		var color: String = record["color"]
		var branch_index: int = record["branch_index"]
		var info: Dictionary = record["info"]
		if bool(info.get("is_center", false)):
			# The hub is a READOUT now, not a node. Blade Dance arrives on its own at team
			# level 10 (Player._on_team_level_changed), so there is nothing here to buy -
			# and the number every colour's ladder is measured against belongs in the middle
			# of the board rather than in a corner of the HUD.
			button.texture_normal = null
			button.texture_hover = null
			button.modulate = Color.WHITE
			_set_badge(record, "", Color.WHITE)
			if is_instance_valid(_level_label):
				_level_label.text = "%d" % RunState.team_level
			continue

		var available_mana: int = int(mana_pool.get(COLOR_MANA[color], 0))
		var rank: int = _node_rank(player, color, info)
		var state: String = _node_state(player, color, branch_index, info, rank, available_mana)
		_apply_badge(record, player, color, info, rank)

		if _shows_mana_pip(info, state, rank):
			button.texture_normal = _mana_pip_texture(color)
			# Nothing to say about a node whose name _show_details will not give either.
			_set_badge(record, "", Color.WHITE)
		else:
			button.texture_normal = _get_icon_texture(info, color)
		button.texture_hover = button.texture_normal
		button.material = IconStyle.rounded_material(state == "unlocked")
		button.modulate = _icon_modulate(state)

	if not _hovered_record.is_empty():
		_show_details(_hovered_record["color"], _hovered_record["branch_index"], _hovered_record["info"])

# --- what one node is worth, whatever kind it is -----------------------------
#
# Four kinds sit on this board and they differ in exactly four places: where the rank
# comes from, what makes them reachable, what gates the next rank, and what the badge
# reads. Everything else - the state ladder, the icon, the tint, the material - is the
# same for all of them.
#
# They used to be four arms of one branch, each repeating that ladder with one word
# changed. That is how the aura arm came to set a rank badge which the arm below it then
# looked up as a spell, found at rank 0, and wiped: the duplication hid a fall-through
# nobody could see by reading one arm. Splitting the four differences out means a fifth
# kind is four small answers rather than a fifth arm that has to remember five things.

const KIND_AURA := "aura"
const KIND_PASSIVE := "passive"
const KIND_AFFINITY := "affinity"
const KIND_SPELL := "spell"


func _node_kind(info: Dictionary) -> String:
	if bool(info.get("is_aura", false)):
		return KIND_AURA
	if bool(info.get("is_passive", false)):
		return KIND_PASSIVE
	if bool(info.get("is_affinity", false)):
		return KIND_AFFINITY
	return KIND_SPELL


## How many ranks of this node the player owns. Zero means undiscovered or merely unbought.
func _node_rank(player: Node, color: String, info: Dictionary) -> int:
	match _node_kind(info):
		KIND_AURA:
			return _aura_rank_of(player, String(info["id"]))
		KIND_PASSIVE:
			return player.get_passive_rank(String(info["id"]))
		KIND_AFFINITY:
			return player.get_affinity_rank(color)
		_:
			return int(player.get_spell_rank(info["id"]))


## Whether something joined to this node is already owned, so it can be bought at all.
func _node_reachable(player: Node, color: String, branch_index: int, info: Dictionary) -> bool:
	match _node_kind(info):
		KIND_PASSIVE:
			return _passive_reachable(player, color)
		KIND_AFFINITY:
			# Joined to the hub, so every colour opens the same way and always can.
			return true
		_:
			return _is_reachable(player, color, branch_index)


## What the next rank costs in skill points.
func _node_cost(info: Dictionary) -> int:
	if _node_kind(info) == KIND_PASSIVE:
		return GameSettings.spell_rank_point_cost
	return int(info["cost"])


## Whether anything OTHER than the price is holding the next rank back.
##
## A spell asks the colour how much has been invested in it. That requirement has always
## been enforced on the way IN - clicking an under-invested node is refused with "Needs 5
## invested in Red" - but the board never showed it: the old spell arm read
## `rank > 0 and not _investment_met(...)` inside a branch only reachable at rank 0, so
## precedence made the whole term unreachable and the node sat there looking available
## until you clicked it. Now it reads locked, like anything else you cannot buy yet.
func _node_gate_met(player: Node, color: String, branch_index: int, info: Dictionary, rank: int) -> bool:
	match _node_kind(info):
		KIND_AURA:
			return _gate_met(player, color, info)
		KIND_PASSIVE:
			return _passive_gate_met(player, rank + 1)
		KIND_AFFINITY:
			# Joined to the hub: the price is the only thing in the way.
			return true
		_:
			return _investment_met(player, color, branch_index)


## Owned, out of reach, affordable, or merely wanted.
func _node_state(player: Node, color: String, branch_index: int, info: Dictionary,
		rank: int, available_mana: int) -> String:
	if rank > 0:
		return "unlocked"
	if not _node_reachable(player, color, branch_index, info):
		# Not merely unaffordable - unreachable. The node keeps its place on the board, so
		# the shape of the colour is always legible, but it shows the colour's mana symbol
		# instead of its own art and _show_details will not name it. What is behind it is
		# something to go and find.
		return "unreachable"
	if not _node_gate_met(player, color, branch_index, info, rank) or not _affordable(available_mana, _node_cost(info)):
		return "locked"
	return "available"


## Which nodes wear the colour's mana symbol instead of their own art.
##
## Undiscovered ones everywhere - except a between-colour passive, which keeps the pip
## until it is OWNED rather than until it is merely reachable. Those sit in the open where
## every colour can see them, and the whole point of them is that what they are stays
## hidden until somebody buys one.
func _shows_mana_pip(info: Dictionary, state: String, rank: int) -> bool:
	if _node_kind(info) == KIND_PASSIVE:
		return rank <= 0
	return state == "unreachable"


## The rank readout on the node itself.
func _apply_badge(record: Dictionary, player: Node, color: String, info: Dictionary, rank: int) -> void:
	if rank <= 0:
		_set_badge(record, "", Color.WHITE)
		return
	match _node_kind(info):
		KIND_AFFINITY:
			# A bare number rather than "n/5": affinity has no cap, and borrowing the
			# spells' five ranks would misread the board. This node is what every other
			# one in the colour is gated behind, and it used to show nothing at all.
			_set_badge(record, "%d" % rank, _rank_tint(rank))
		KIND_SPELL:
			_set_spell_badge(record, player, String(info["id"]), rank)
		_:
			_set_badge(record, _rank_text(rank), _rank_tint(rank))


func _rank_text(rank: int) -> String:
	return "%d/%d" % [rank, GameSettings.spell_max_rank]


## Maxed reads gold, still-rankable reads plain, so a board full of ranks still shows
## where there is room left.
func _rank_tint(rank: int) -> Color:
	if rank >= GameSettings.spell_max_rank:
		return Color(1.0, 0.85, 0.35)
	return Color(0.88, 0.92, 0.96)


## What a spell node says about itself without being hovered: its rank, and which key
## casts it. "3/5 [2]" is a whole build decision read at a glance.
func _set_spell_badge(record: Dictionary, player: Node, spell_id: String, rank: int) -> void:
	if rank <= 0:
		_set_badge(record, "", Color.WHITE)
		return
	var text: String = _rank_text(rank)
	var slot: int = _slot_of(player, spell_id)
	if slot > 0:
		text += "  [%d]" % slot
	_set_badge(record, text, _rank_tint(rank))


func _set_badge(record: Dictionary, text: String, tint: Color) -> void:
	if not record.has("badge"):
		return
	var badge: Label = record["badge"]
	# Only on a real change. Each of these three is a notification, not an assignment:
	# `text` queues a re-layout, `visible` propagates through the subtree, and a theme
	# override invalidates the control's cached theme and walks its children. update_ui()
	# calls this for all forty-six nodes and on almost all of them nothing has moved -
	# which made it the single most expensive part of a pass.
	#
	# The tint is remembered on the record rather than read back off the control, because
	# get_theme_color() is itself a cache miss the first time and a lookup every time.
	if badge.text != text:
		badge.text = text
	var wanted: bool = text != ""
	if badge.visible != wanted:
		badge.visible = wanted
	if record.get("badge_tint") != tint:
		record["badge_tint"] = tint
		badge.add_theme_color_override("font_color", tint)


func _show_details(color: String, branch_index: int, info: Dictionary) -> void:
	var player = PlayerRegistry.get_local()
	if player == null:
		return
	var mana_pool: Dictionary = RunState.mana_pool
	_hovered_record = {"color": color, "branch_index": branch_index, "info": info}
	_detail_panel.show()
	var detail_record: Dictionary = _find_record(color, branch_index)
	if not detail_record.is_empty():
		_position_detail_panel(detail_record["button"])

	if bool(info.get("is_center", false)):
		_detail_title.text = "Team Level %d" % RunState.team_level
		_detail_title.add_theme_color_override("font_color", Color(0.86, 0.84, 0.72))
		_detail_status.text = "Blade Dance is granted at level 10" if not bool(player.melee_combo_extended) else "Blade Dance unlocked"
		_detail_body.text = "Every colour's ladder is measured against this number."
		return

	# Withheld, not dimmed. A node with no owned neighbour shows its colour's mana symbol on
	# the board and says nothing here - no name, no description, no cost. Reaching it is the
	# thing that reveals what it is.
	#
	# The two outer nodes used to be exempt, back when they were capstones and the fork
	# between them was meant to be visible from the start. They are ordinary skills now, so
	# they are withheld like every other one.
	if not bool(info.get("is_passive", false)) and not bool(info["is_affinity"]) \
			and not _is_reachable(player, color, branch_index):
		_detail_title.text = "%s - Undiscovered" % COLOR_DISPLAY[color]
		_detail_title.add_theme_color_override("font_color", COLOR_HEX[color] * Color(1, 1, 1, 0.7))
		_detail_status.text = "Unlock a connected skill to reveal this"
		_detail_body.text = ""
		return

	var available_mana: int = int(mana_pool.get(COLOR_MANA[color], 0))
	_detail_title.text = "%s - %s" % [COLOR_DISPLAY[color], info["name"]]
	_detail_title.add_theme_color_override("font_color", COLOR_HEX[color])

	if bool(info.get("is_aura", false)):
		var aura_id: String = String(info["id"])
		var rank: int = _aura_rank_of(player, aura_id)
		var status: String = ""
		if rank >= GameSettings.spell_max_rank:
			status = "Rank %d/%d - MAX" % [rank, GameSettings.spell_max_rank]
		elif rank <= 0 and not _is_reachable(player, color, branch_index):
			status = "Unlock a connected skill first"
		elif rank <= 0:
			status = "Unlock for %d point" % GameSettings.spell_rank_point_cost
		else:
			status = "Rank %d/%d  -  next rank %d point" % [rank, GameSettings.spell_max_rank, GameSettings.spell_rank_point_cost]
		_detail_status.text = "%s  %s  Points %d" % [COLOR_SYMBOL[color], status, _skill_points(player)]
		_detail_body.text = info["desc"]
		return

	if bool(info.get("is_passive", false)):
		var passive_id: String = String(info["id"])
		var passive_rank: int = player.get_passive_rank(passive_id)
		var pair: Array = info["colors"]
		_detail_title.text = "%s - %s" % [String(info["guild"]), info["name"]]
		_detail_title.add_theme_color_override("font_color", (COLOR_HEX[pair[0]] + COLOR_HEX[pair[1]]) * 0.5)
		var passive_status: String
		if passive_rank <= 0 and not _passive_reachable(player, color):
			passive_status = "Unlock a connected skill first  |  "
		elif passive_rank >= GameSettings.spell_max_rank:
			passive_status = "Rank %d/%d - MAX  |  " % [passive_rank, GameSettings.spell_max_rank] + _passive_value_text(player, passive_id, passive_rank)
		elif passive_rank <= 0:
			passive_status = "Unlock for %d point  |  " % GameSettings.spell_rank_point_cost + _passive_value_text(player, passive_id, 1)
		else:
			passive_status = "Rank %d/%d  |  " % [passive_rank, GameSettings.spell_max_rank] + _passive_value_text(player, passive_id, passive_rank) + " -> " + _passive_value_text(player, passive_id, passive_rank + 1)
		_detail_status.text = "%s  |  Invested %d  |  Points %d" % [passive_status, passive_rank, _skill_points(player)]
		_detail_body.text = String(info["desc"])
		return

	if bool(info["is_affinity"]):
		var rank: int = player.get_affinity_rank(color)
		var bonus: float = player.get_affinity_bonus(color) * 100.0
		var next_bonus: float = _get_next_rank_bonus(rank + 1) * 100.0
		_detail_status.text = "%s  Rank %d  Total %.1f%%  Next +%.1f%%  Mana %d" % [COLOR_SYMBOL[color], rank, bonus, next_bonus, available_mana]
		_detail_body.text = "%s  %s" % [info["mechanic"], info["flavor"]]
	else:
		var spell_id: String = String(info["id"])
		var rank: int = int(player.get_spell_rank(spell_id))
		var status: String = ""
		if rank <= 0:
			# Not owned yet: the affinity gate is the thing standing in the way.
			status = "Unlock for %d point" % GameSettings.spell_rank_point_cost
		else:
			# Owned: what matters is what the NEXT rank costs and what is stopping it.
			var blocker: String = String(player.spell_rank_blocker(spell_id))
			status = "Rank %d/%d" % [rank, GameSettings.spell_max_rank]
			if blocker == "":
				status += "  -  next rank %d point" % GameSettings.spell_rank_point_cost
			else:
				status += "  -  " + blocker
		if GameSettings.debug_free_skills and rank < GameSettings.spell_max_rank:
			status += "  (free: debug)"
		var slot: int = _slot_of(player, spell_id)
		var binding: String = ("Key %d" % slot) if slot > 0 else "Unbound - press 1-5"
		_detail_status.text = "%s  %s  |  %s  |  Points %d  |  Cooldown %.1fs" % [
			COLOR_SYMBOL[color], status, binding, _skill_points(player), SpellDatabase.get_cooldown(spell_id),
		]
		_detail_body.text = info["desc"]

func _hide_details() -> void:
	_hovered_record.clear()
	if is_instance_valid(_detail_panel):
		_detail_panel.hide()

## Nothing here goes through MainController any more. This used to be guarded on
## `main_controller.has_method("spend_mana_cost")`, which the economy rework deleted when
## mana moved to RunState - so the guard silently refused EVERY purchase, debug switch
## included. The only thing a purchase actually needs is the local player.
func _on_node_pressed(color: String, branch_index: int, info: Dictionary) -> void:
	var player = PlayerRegistry.get_local()
	if player == null:
		return

	if bool(info.get("is_center", false)):
		# Nothing to buy: the hub shows the team level, and Blade Dance is granted at 10.
		return

	if bool(info.get("is_aura", false)):
		var aura_id: String = String(info["id"])
		if _aura_rank_of(player, aura_id) >= GameSettings.spell_max_rank:
			return
		if not _is_reachable(player, color, branch_index):
			return
		if _pay(player, GameSettings.spell_rank_point_cost) and player.has_method("grant_aura_rank"):
			player.grant_aura_rank(aura_id)
			update_ui()
			SoundBank.play(&"skill_unlock")
		return

	if bool(info.get("is_passive", false)):
		var passive_id: String = String(info["id"])
		var passive_rank: int = player.get_passive_rank(passive_id)
		if passive_rank >= GameSettings.spell_max_rank:
			return
		if passive_rank <= 0 and not _passive_reachable(player, color):
			return
		if _pay(player, GameSettings.spell_rank_point_cost):
			player.grant_passive_rank(passive_id)
			update_ui()
			SoundBank.play(&"skill_unlock")
		return

	if bool(info["is_affinity"]):
		if _pay(player, 1):
			player.invest_affinity(color)
			update_ui()
			SoundBank.play(&"skill_unlock")
		return

	# One click, one rank - the first buys the spell, the next four deepen it. Clicking a
	# node you already own used to only re-select its colour, which is what a mono-colour
	# tree needed and a loadout does not.
	var spell_id: String = String(info["id"])
	var rank: int = int(player.get_spell_rank(spell_id))
	if rank <= 0:
		# Unreachable nodes are not merely refused, they are not described either - see
		# _show_details. Nothing to flash here, because the player was never shown a name
		# to click at in the first place.
		if not _is_reachable(player, color, branch_index):
			return
		if _pay(player, GameSettings.spell_rank_point_cost):
			SignalBus.spell_unlocked.emit(color, spell_id)
			update_ui()
			SoundBank.play(&"skill_unlock")
		return

	# Level gates come from the team's level, not from anything the player can buy in
	# here, so a refusal has to SAY so rather than looking like a dead button.
	var blocker: String = String(player.spell_rank_blocker(spell_id))
	if blocker != "":
		_flash_status(blocker)
		return
	if _pay(player, GameSettings.spell_rank_point_cost):
		player.grant_spell_rank(spell_id)
		player.select_color_path(color)
		update_ui()
		SoundBank.play(&"skill_unlock")


## Says why a click did nothing, in the panel the player is already looking at. A skill
## tree that refuses silently is indistinguishable from a broken one - which this project
## has now learned twice.
func _flash_status(message: String) -> void:
	if not is_instance_valid(_detail_status):
		return
	_detail_panel.show()
	_detail_status.text = message
	_detail_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	var tween: Tween = create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_detail_status):
			_detail_status.remove_theme_color_override("font_color")
		if not _hovered_record.is_empty():
			_show_details(_hovered_record["color"], _hovered_record["branch_index"], _hovered_record["info"]))


## Charges for a node, or waves it through when the free-skills debug switch is on.
## Every purchase goes through here so the switch cannot be half-applied - a node that
## skipped the rank gate but still charged would be worse than either.
##
## Skill tree nodes cost SKILL POINTS, never mana. Points come from team levels and from
## Upkeep purchases; mana is the team's and is spent only at Upkeep. Keeping them apart
## is what stops a player having to choose between their own build and the team's.
func _pay(player: Node, points: int) -> bool:
	if GameSettings.debug_free_skills:
		return true
	if player == null or not player.has_method("spend_skill_points"):
		return false
	return bool(player.spend_skill_points(points))


## Whether a node can be bought AT ALL yet: is anything joined to it already owned?
##
## This is the rule the fan layout was drawn for. A colour is a graph now, and BRANCH_EDGES
## is that graph, so reachability is a walk over the edges the player can already see
## rather than a second set of numbers to keep in step with the picture.
##
## The affinity is joined to the hub, so it is always reachable and every colour still opens
## the same way. The aura fork hangs off the middle finisher, which is why taking a
## aura means finishing a colour rather than rushing it.
func _is_reachable(player: Node, color: String, branch_index: int) -> bool:
	if GameSettings.debug_free_skills:
		return true
	if branch_index == CENTER_BRANCH or branch_index == PASSIVE_BRANCH:
		return true
	for edge: Array in BRANCH_EDGES:
		var neighbour: int = -99
		if edge[0] == branch_index:
			neighbour = edge[1]
		elif edge[1] == branch_index:
			neighbour = edge[0]
		else:
			continue
		if _branch_owned(player, color, neighbour):
			return true
	return false


## Between-colour passives are connected to the two adjacent skills shown by their lines:
## the second opener on the gap's left colour and the first opener on the next colour.
func _passive_reachable(player: Node, gap_color: String) -> bool:
	if GameSettings.debug_free_skills:
		return true
	var gap_index: int = COLOR_NAMES.find(gap_color)
	if gap_index < 0:
		return false
	var next_color: String = COLOR_NAMES[(gap_index + 1) % COLOR_NAMES.size()]
	return _branch_owned(player, gap_color, 2) or _branch_owned(player, next_color, 1)


## Whether the player already holds the node at `branch_index` of `color`. The hub counts as
## owned unconditionally - it is the root every colour grows from, and after the level
## readout replaced Blade Dance there is nothing there to buy.
func _branch_owned(player: Node, color: String, branch_index: int) -> bool:
	if branch_index == CENTER_BRANCH:
		return true
	if branch_index == 0:
		return player.get_affinity_rank(color) > 0
	if branch_index in AURA_BRANCHES:
		var aura_id: String = _aura_id_for_branch(color, branch_index)
		return aura_id != "" and _aura_rank_of(player, aura_id) > 0
	return player.get_spell_rank("%s_%d" % [color, branch_index]) > 0


func _aura_rank_of(player: Node, aura_id: String) -> int:
	if player != null and player.has_method("get_aura_rank"):
		return int(player.get_aura_rank(aura_id))
	return 0


func _aura_id_for_branch(color: String, branch_index: int) -> String:
	var half: int = AURA_BRANCHES.find(branch_index)
	if half < 0:
		return ""
	var auras: Array[Dictionary] = SpellDatabase.get_auras(color)
	if half >= auras.size():
		return ""
	return String(auras[half]["id"])


## What the colour-investment ladder asks of this node, and whether it has been paid.
##
## Connectivity says WHERE you may go; this says how deep into the colour you have to be to
## go there. Two questions, one ladder - see GameSettings.color_investment_ladder.
func _investment_met(player: Node, color: String, branch_index: int) -> bool:
	if GameSettings.debug_free_skills:
		return true
	if branch_index < 1 or branch_index > 5:
		return true
	return player.color_investment(color) >= GameSettings.color_investment_requirement(branch_index)


func _gate_met(player: Node, color: String, info: Dictionary) -> bool:
	return true


## Passive ranks use the same shared team-level clock as active skill ranks.
func _passive_gate_met(player: Node, rank: int) -> bool:
	return true


## "25% move speed" style readout for the detail panel, computed from the same numbers
## the player script actually applies.
func _passive_value_text(player: Node, passive_id: String, rank: int) -> String:
	var value: float = player.get_passive_bonus_at(passive_id, rank) * 100.0
	if absf(value - roundf(value)) < 0.05:
		return "%d%% %s" % [int(roundf(value)), String(PASSIVE_DATA[passive_id]["unit"])]
	return "%.1f%% %s" % [value, String(PASSIVE_DATA[passive_id]["unit"])]

## How many points the player has left, or 0 for anything that has none. Only used to
## print the number, so an unreadable player is 0 rather than an error.
func _skill_points(player: Node) -> int:
	if player == null or not ("skill_points" in player):
		return 0
	return int(player.skill_points)


## Affordability is measured in the player's own skill points now, not in mana.
func _affordable(_available: int, cost: int) -> bool:
	if GameSettings.debug_free_skills:
		return true
	var player: Node = PlayerRegistry.get_local()
	if player == null or not ("skill_points" in player):
		return false
	return int(player.skill_points) >= cost


func _total_mana(mana_pool: Dictionary) -> int:
	var total: int = 0
	for color: String in mana_pool.keys():
		total += int(mana_pool[color])
	return total


func _get_next_rank_bonus(next_rank: int) -> float:
	return GameSettings.affinity_rank_bonus_base

## The blended pair colour of each guild passive, built lazily because a const cannot
## blend two Colors at parse time.
var _guild_hex_cache: Dictionary = {}
func _guild_hex() -> Dictionary:
	if _guild_hex_cache.is_empty():
		for pid: String in PASSIVE_ORDER:
			var pair: Array = PASSIVE_DATA[pid]["colors"]
			_guild_hex_cache[pid] = (COLOR_HEX[pair[0]] + COLOR_HEX[pair[1]]) * 0.5
	return _guild_hex_cache


func _get_placeholder_texture(color: String, branch_index: int, state: String) -> ImageTexture:
	var cache_key: String = "%s_%d_%s" % [color, branch_index, state]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	# Guild nodes are keyed by passive id rather than by a single colour, so the blended
	# pair colour is looked up first; everything else keeps its own colour.
	var base_color: Color
	if _guild_hex().has(color):
		base_color = _guild_hex()[color]
	elif color == "center":
		base_color = Color(0.72, 0.7, 0.6)
	else:
		base_color = COLOR_HEX[color]
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


func _get_icon_texture(info: Dictionary, fallback_color: String) -> Texture2D:
	var texture: Texture2D = SpellDatabase.get_icon(String(info.get("id", "")), fallback_color)
	if texture != null:
		return texture
	return _get_placeholder_texture(fallback_color, 0, "available")


## The mana symbol a colour's undiscovered nodes wear. Five colours of pip serve the whole
## board, and SpellDatabase keeps them alongside every other icon - this used to hold a
## second cache of its own for the same five textures.
func _mana_pip_texture(color: String) -> Texture2D:
	return SpellDatabase.get_icon(color)


func _icon_modulate(state: String) -> Color:
	# Darker than "locked", and deliberately so: a locked node is something the player can
	# see and cannot yet afford, while an unreachable one is not an offer at all.
	if state == "unreachable":
		return Color(0.2, 0.21, 0.24, 1.0)
	if state == "locked":
		return Color(0.32, 0.34, 0.38)
	if state == "hover":
		return Color(1.15, 1.15, 1.15)
	if state == "unlocked":
		return Color.WHITE
	return Color(0.42, 0.44, 0.48)


func _is_placeholder_mark(offset: Vector2, branch_index: int) -> bool:
	var abs_x: float = absf(offset.x)
	var abs_y: float = absf(offset.y)
	# Kept out of the match below rather than added as a case: a bare constant name
	# in a match pattern reads as a binding, not a comparison.
	if branch_index == CENTER_BRANCH:
		# Crossed blades: the one node that is about melee rather than magic.
		return (absf(abs_x - abs_y) < 3.0 and offset.length() < 21.0) or offset.length() < 4.0
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
		6:
			# Attunement: a solid core. The stat line - dense, inert, all of it inside you.
			return offset.length() < 13.0
		7:
			# Manifestation: a core with something in orbit around it. The visible half of
			# the fork, drawn as the thing it actually is.
			return offset.length() < 6.0 or (absf(offset.length() - 17.0) < 2.5 and offset.y < -2.0)
		_:
			return abs_x < 3.0 or abs_y < 3.0
