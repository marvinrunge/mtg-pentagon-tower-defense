extends CanvasLayer
class_name HUD

var _enemy_focus_stylebox: StyleBoxFlat

@onready var health_bar: ProgressBar = $Control/MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $Control/MarginContainer/VBoxContainer/HealthContainer/HealthLabel
@onready var player_health_bar: ProgressBar = $Control/PlayerHealthBar
@onready var player_health_label: Label = $Control/PlayerHealthBar/HPLabel
@onready var mana_label_w: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelW
@onready var mana_label_u: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelU
@onready var mana_label_b: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelB
@onready var mana_label_r: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelR
@onready var mana_label_g: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelG
@onready var status_label: Label = $Control/MarginContainer/VBoxContainer/StatusLabel
@onready var interact_label: Label = $Control/InteractLabel

@onready var settings_panel: PanelContainer = $Control/SettingsPanel
@onready var minimap_container: MarginContainer = $Control/MinimapContainer
@onready var minimap: ColorRect = $Control/MinimapContainer/Minimap
@onready var show_minimap_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/VBoxContainer/ShowMinimapCheckbox
@onready var damage_numbers_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/VBoxContainer/DamageNumbersCheckbox
@onready var minimap_size_slider: HSlider = $Control/SettingsPanel/MarginContainer/VBoxContainer/MinimapSizeSlider

@onready var game_over_panel: PanelContainer = $Control/GameOverPanel
@onready var restart_btn: Button = $Control/GameOverPanel/MarginContainer/VBoxContainer/RestartBtn

# --- Spell Hotbar ---
var _hotbar_slots: Array[PanelContainer] = []
var _unlocked_slots: Array[bool] = [true, false, false, false, false, false] # Melee is unlocked by default
var _player: Node3D = null
var _active_spell_idx: int = 0

const SLOT_COLORS = [
	Color(0.85, 0.7, 0.4), # Melee: Pale Gold/Bronze
	Color(0.9, 0.2, 0.2), # Red: Shock
	Color(0.25, 0.55, 0.9), # Blue: Unsummon
	Color(0.2, 0.8, 0.2), # Green: Giant Growth
	Color(0.95, 0.95, 0.95), # White: Healing Grace
	Color(0.65, 0.2, 0.8) # Black: Stab
]

const SPELL_TO_SLOT_INDEX = {
	"Basic Attack": 0,
	"Shock": 1,
	"Unsummon": 2,
	"Giant Growth": 3,
	"Healing Grace": 4,
	"Stab": 5
}

func _ready() -> void:
	SignalBus.health_changed.connect(update_health)
	SignalBus.player_health_changed.connect(update_player_health)
	SignalBus.mana_changed.connect(update_mana)
	SignalBus.active_spell_changed.connect(update_spell)
	SignalBus.at_base_changed.connect(_on_at_base_changed)
	SignalBus.enemy_focused.connect(_on_enemy_focused)
	SignalBus.interact_prompt_changed.connect(_on_interact_prompt_changed)
	SignalBus.spell_charge_changed.connect(_on_spell_charge_changed)
	SignalBus.spell_unlocked.connect(func(_c, _s): _update_hotbar_display(_active_spell_idx))
	SignalBus.color_path_chosen.connect(func(_c): _update_hotbar_display(_active_spell_idx))
	
	show_minimap_checkbox.toggled.connect(_on_show_minimap_toggled)
	if damage_numbers_checkbox:
		damage_numbers_checkbox.button_pressed = GameSettings.show_damage_numbers
		damage_numbers_checkbox.toggled.connect(_on_damage_numbers_toggled)
	minimap_size_slider.value_changed.connect(_on_minimap_size_changed)
	restart_btn.pressed.connect(_on_restart_pressed)
	settings_panel.hide()
	game_over_panel.hide()
	
	_hotbar_slots = [
		$Control/HotbarAndXPContainer/SpellHotbar/Slot1,
		$Control/HotbarAndXPContainer/SpellHotbar/Slot2,
		$Control/HotbarAndXPContainer/SpellHotbar/Slot3,
		$Control/HotbarAndXPContainer/SpellHotbar/Slot4,
		$Control/HotbarAndXPContainer/SpellHotbar/Slot5
	]
	var slot6 = $Control/HotbarAndXPContainer/SpellHotbar.get_node_or_null("Slot6")
	if slot6:
		slot6.hide()
	_setup_action_icons()
	SignalBus.active_spell_changed.connect(_on_active_spell_changed)
	SignalBus.skill_unlocked.connect(_on_skill_unlocked)
	
	# Try to fetch current player's unlocked skills to populate correct starting state
	var p_node = get_tree().get_first_node_in_group("player")
	if p_node and "unlocked_skills" in p_node:
		for color_key in p_node.unlocked_skills:
			if p_node.unlocked_skills[color_key]:
				var idx = _get_index_for_color(color_key)
				if idx != -1:
					_unlocked_slots[idx] = true
	
	_update_hotbar_display(0)
	
	_enemy_focus_stylebox = StyleBoxFlat.new()
	_enemy_focus_stylebox.corner_radius_top_left = 6
	_enemy_focus_stylebox.corner_radius_top_right = 6
	_enemy_focus_stylebox.corner_radius_bottom_left = 6
	_enemy_focus_stylebox.corner_radius_bottom_right = 6
	
	setup_styles()
	update_health(GameSettings.crystal_max_hp, GameSettings.crystal_max_hp)
	update_player_health(GameSettings.player_max_hp, GameSettings.player_max_hp)
	update_mana({})

func _process(delta: float) -> void:

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		
	if _player != null and "spell_cooldown_timers" in _player:
		for i in range(_hotbar_slots.size()):
			var slot = _hotbar_slots[i]
			if not slot:
				continue
				
			var overlay = slot.get_node_or_null("CooldownOverlay")
			if overlay:
				var spell_id = ""
				if _player.has_method("_get_spell_id_for_slot"):
					spell_id = _player._get_spell_id_for_slot(i)
				var cd = _player.spell_cooldown_timers.get(spell_id, 0.0)
				if cd > 0.0:
					overlay.show()
					var label = overlay.get_node_or_null("Label")
					if label:
						label.text = "%.1fs" % cd
				else:
					overlay.hide()


func setup_styles() -> void:
	# Style the Health ProgressBar with a modern glassmorphic theme
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.15, 0.5)
	sb_bg.border_width_left = 2
	sb_bg.border_width_top = 2
	sb_bg.border_width_right = 2
	sb_bg.border_width_bottom = 2
	sb_bg.border_color = Color(0.2, 0.25, 0.3, 0.7)
	sb_bg.corner_radius_top_left = 8
	sb_bg.corner_radius_top_right = 8
	sb_bg.corner_radius_bottom_left = 8
	sb_bg.corner_radius_bottom_right = 8
	
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.85, 0.2, 0.3, 0.9) # Crimson red
	sb_fg.corner_radius_top_left = 6
	sb_fg.corner_radius_top_right = 6
	sb_fg.corner_radius_bottom_left = 6
	sb_fg.corner_radius_bottom_right = 6
	
	health_bar.add_theme_stylebox_override("background", sb_bg)
	health_bar.add_theme_stylebox_override("fill", sb_fg)
	
	var sb_player_fg = sb_fg.duplicate()
	sb_player_fg.bg_color = Color(0.2, 0.8, 0.3, 0.9) # Green
	player_health_bar.add_theme_stylebox_override("background", sb_bg)
	player_health_bar.add_theme_stylebox_override("fill", sb_player_fg)

func update_health(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current
	health_label.text = "Crystal Integrity: %d / %d" % [current, max_health]
	
	if current <= 0:
		status_label.text = "DEFEAT - THE CRYSTAL SHATTERED!"
		status_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		if game_over_panel:
			game_over_panel.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif current < max_health * 0.03:
		status_label.text = "CRITICAL WARNING: BASE UNDER ATTACK!"
		status_label.add_theme_color_override("font_color", Color(1, 0.5, 0))

func update_player_health(current: float, max_health: float) -> void:
	player_health_bar.max_value = max_health
	player_health_bar.value = current
	player_health_label.text = "%d / %d" % [current, max_health]
	if current <= 0:
		status_label.text = "YOU DIED!"
		status_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

func update_mana(mana_pool: Dictionary) -> void:
	if mana_label_w:
		mana_label_w.text = "W: %d" % mana_pool.get("White", 0)
	if mana_label_u:
		mana_label_u.text = "U: %d" % mana_pool.get("Blue", 0)
	if mana_label_b:
		mana_label_b.text = "B: %d" % mana_pool.get("Black", 0)
	if mana_label_r:
		mana_label_r.text = "R: %d" % mana_pool.get("Red", 0)
	if mana_label_g:
		mana_label_g.text = "G: %d" % mana_pool.get("Green", 0)

func update_spell(spell_name: String) -> void:
	pass

func _input(event: InputEvent) -> void:
	if game_over_panel and game_over_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		settings_panel.visible = !settings_panel.visible
		if settings_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _on_show_minimap_toggled(button_pressed: bool) -> void:
	minimap_container.visible = button_pressed

func _on_damage_numbers_toggled(button_pressed: bool) -> void:
	GameSettings.show_damage_numbers = button_pressed

func _on_minimap_size_changed(value: float) -> void:
	minimap.custom_minimum_size = Vector2(value, value)

func _on_enemy_focused(is_focused: bool, enemy_name: String, hp: float, max_hp: float, color: Color) -> void:
	var target_container = $Control/TargetContainer
	if not is_focused:
		target_container.hide()
		return
		
	target_container.show()
	var label = $Control/TargetContainer/TargetLabel
	var bar = $Control/TargetContainer/TargetHealthBar
	
	label.text = enemy_name
	label.add_theme_color_override("font_color", color)
	
	bar.max_value = max_hp
	bar.value = hp
	
	# Reuse the cached stylebox, just update the color
	_enemy_focus_stylebox.bg_color = color
	bar.add_theme_stylebox_override("fill", _enemy_focus_stylebox)

func _on_at_base_changed(is_at_base: bool) -> void:
	if interact_label:
		interact_label.text = "Press [F] to Manage Base"
		interact_label.visible = is_at_base

func _on_interact_prompt_changed(text: String, visible: bool) -> void:
	if interact_label:
		interact_label.text = text
		interact_label.visible = visible

func _get_index_for_color(color: String) -> int:
	const color_map = {
		"red": 1,
		"blue": 2,
		"green": 3,
		"white": 4,
		"black": 5
	}
	return color_map.get(color.to_lower(), -1)

func _setup_action_icons() -> void:
	var grid_tex = load("res://scenes/action_icons.jpg")
	if not grid_tex:
		push_error("Failed to load action icons image!")
		return
		
	var cell_w = grid_tex.get_width() / 3.0
	var cell_h = grid_tex.get_height() / 3.0
	
	# Slot indices mapping:
	# 0: Melee -> (Col 2, Row 1) (axe)
	# 1: Shock -> (Col 0, Row 0) (lightning)
	# 2: Unsummon -> (Col 1, Row 0) (blue ghost)
	# 3: Giant -> (Col 0, Row 1) (green fist)
	# 4: Heal -> (Col 1, Row 1) (potion)
	# 5: Stab -> (Col 2, Row 0) (dagger)
	var coords = [
		Vector2(2, 1),
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(2, 0)
	]
	
	for i in range(_hotbar_slots.size()):
		var slot = _hotbar_slots[i]
		if not slot:
			continue
			
		# Create and configure the TextureRect child
		var tex_rect = TextureRect.new()
		tex_rect.name = "IconRect"
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var atlas = AtlasTexture.new()
		atlas.atlas = grid_tex
		var coord = coords[i]
		atlas.region = Rect2(coord.x * cell_w, coord.y * cell_h, cell_w, cell_h)
		tex_rect.texture = atlas
		
		slot.add_child(tex_rect)
		slot.move_child(tex_rect, 0) # Render behind everything else
		
		# Hide text label and overlay the hotkey number at top-left
		var name_label = slot.get_node_or_null("VBox/Name")
		if name_label:
			name_label.hide()
			
		var num_label = slot.get_node_or_null("VBox/Num")
		var vbox = slot.get_node_or_null("VBox")
		if num_label and vbox:
			vbox.remove_child(num_label)
			slot.add_child(num_label)
			num_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			num_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			num_label.custom_minimum_size = Vector2(16, 16)
			num_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			num_label.add_theme_constant_override("outline_size", 4)
			num_label.add_theme_font_size_override("font_size", 10)

func _update_hotbar_display(active_idx: int) -> void:
	for i in range(_hotbar_slots.size()):
		var slot = _hotbar_slots[i]
		if not slot:
			continue
			
		var num_label = slot.get_node_or_null("Num")
		var icon_rect = slot.get_node_or_null("IconRect")
		
		var sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		
		var is_unlocked = false
		if _player and _player.has_method("is_spell_unlocked"):
			is_unlocked = _player.is_spell_unlocked(i)
		else:
			is_unlocked = (i == 0)
			
		if i == active_idx:
			sb.bg_color = Color(0.15, 0.15, 0.15, 0.95)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			sb.border_color = SLOT_COLORS[i]
			
			sb.shadow_color = SLOT_COLORS[i] * Color(1, 1, 1, 0.3)
			sb.shadow_size = 6
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color.WHITE)
			if icon_rect:
				icon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		elif is_unlocked:
			sb.bg_color = Color(0.08, 0.08, 0.08, 0.7)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.3, 0.3, 0.3, 0.8)
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			if icon_rect:
				icon_rect.modulate = Color(0.65, 0.65, 0.65, 1.0)
		else:
			sb.bg_color = Color(0.04, 0.04, 0.04, 0.4)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.15, 0.15, 0.15, 0.4)
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))
			if icon_rect:
				icon_rect.modulate = Color(0.15, 0.15, 0.15, 0.4)
				
		slot.add_theme_stylebox_override("panel", sb)

func _on_active_spell_changed(spell_name: String) -> void:
	if _player and "active_spell_index" in _player:
		_active_spell_idx = _player.active_spell_index
	_update_hotbar_display(_active_spell_idx)

func _on_skill_unlocked(color: String) -> void:
	_update_hotbar_display(_active_spell_idx)

func _on_spell_charge_changed(current: float, max_c: float, is_charging: bool) -> void:
	if interact_label:
		if is_charging:
			var pct = int((current / max_c) * 100)
			interact_label.text = "CHARGING SPELL... %d%%" % pct
			interact_label.visible = true
		else:
			interact_label.visible = false
