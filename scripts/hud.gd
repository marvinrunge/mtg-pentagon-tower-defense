extends CanvasLayer
class_name HUD

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
@onready var enemy_health_bars_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/VBoxContainer/EnemyHealthBarsCheckbox
@onready var minimap_size_slider: HSlider = $Control/SettingsPanel/MarginContainer/VBoxContainer/MinimapSizeSlider

@onready var game_over_panel: PanelContainer = $Control/GameOverPanel
@onready var restart_btn: Button = $Control/GameOverPanel/MarginContainer/VBoxContainer/RestartBtn

# --- Spell Hotbar ---
var _hotbar_slots: Array[PanelContainer] = []
var _player: Node3D = null
var _active_spell_idx: int = 0
var _wave_label: Label
var _enemy_count_label: Label
var _warning_panel: PanelContainer
var _warning_label: Label
var _warning_tween: Tween
var _reward_overlay: ColorRect
var _reward_choices: HBoxContainer

const ACTIVE_SLOT_COLOR: Color = Color(0.95, 0.72, 0.22)

func _ready() -> void:
	SignalBus.health_changed.connect(update_health)
	SignalBus.player_health_changed.connect(update_player_health)
	SignalBus.mana_changed.connect(update_mana)
	SignalBus.active_spell_changed.connect(update_spell)
	SignalBus.at_base_changed.connect(_on_at_base_changed)
	SignalBus.interact_prompt_changed.connect(_on_interact_prompt_changed)
	SignalBus.spell_charge_changed.connect(_on_spell_charge_changed)
	SignalBus.spell_unlocked.connect(func(_c, _s): _update_hotbar_display(_active_spell_idx))
	SignalBus.color_path_chosen.connect(func(_c): _update_hotbar_display(_active_spell_idx))
	SignalBus.wave_state_changed.connect(_on_wave_state_changed)
	SignalBus.lane_warning_requested.connect(_on_lane_warning_requested)
	SignalBus.wave_reward_offered.connect(_on_wave_reward_offered)
	
	show_minimap_checkbox.toggled.connect(_on_show_minimap_toggled)
	if damage_numbers_checkbox:
		damage_numbers_checkbox.button_pressed = GameSettings.show_damage_numbers
		damage_numbers_checkbox.toggled.connect(_on_damage_numbers_toggled)
	if enemy_health_bars_checkbox:
		enemy_health_bars_checkbox.button_pressed = GameSettings.show_enemy_health_bars
		enemy_health_bars_checkbox.toggled.connect(_on_enemy_health_bars_toggled)
	minimap_size_slider.value_changed.connect(_on_minimap_size_changed)
	restart_btn.pressed.connect(_on_restart_pressed)
	settings_panel.hide()
	game_over_panel.hide()
	_build_wave_ui()
	
	_hotbar_slots = [
		$Control/HotbarContainer/SpellHotbar/Slot1,
		$Control/HotbarContainer/SpellHotbar/Slot2,
		$Control/HotbarContainer/SpellHotbar/Slot3,
		$Control/HotbarContainer/SpellHotbar/Slot4,
		$Control/HotbarContainer/SpellHotbar/Slot5
	]
	SignalBus.active_spell_changed.connect(_on_active_spell_changed)
	SignalBus.skill_unlocked.connect(_on_skill_unlocked)
	
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_update_hotbar_display(0)
	
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
	if _reward_overlay and _reward_overlay.visible:
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

func _on_enemy_health_bars_toggled(button_pressed: bool) -> void:
	GameSettings.show_enemy_health_bars = button_pressed
	SignalBus.enemy_health_bars_visibility_changed.emit(button_pressed)

func _on_minimap_size_changed(value: float) -> void:
	minimap.custom_minimum_size = Vector2(value, value)

func _on_at_base_changed(is_at_base: bool) -> void:
	if interact_label:
		interact_label.text = "Press [F] to Manage Base"
		interact_label.visible = is_at_base

func _on_interact_prompt_changed(text: String, visible: bool) -> void:
	if interact_label:
		interact_label.text = text
		interact_label.visible = visible

func _update_hotbar_display(active_idx: int) -> void:
	for i in range(_hotbar_slots.size()):
		var slot = _hotbar_slots[i]
		if not slot:
			continue
			
		var num_label: Label = slot.get_node_or_null("VBox/Num") as Label
		var name_label: Label = slot.get_node_or_null("VBox/Name") as Label
		
		var sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		
		var is_unlocked = false
		if _player and _player.has_method("is_spell_unlocked"):
			is_unlocked = _player.is_spell_unlocked(i)
		if name_label:
			name_label.text = _player.get_spell_name_for_slot(i) if _player and is_unlocked else "Locked"
			
		if i == active_idx:
			sb.bg_color = Color(0.15, 0.15, 0.15, 0.95)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			sb.border_color = ACTIVE_SLOT_COLOR
			
			sb.shadow_color = ACTIVE_SLOT_COLOR * Color(1, 1, 1, 0.3)
			sb.shadow_size = 6
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color.WHITE)
		elif is_unlocked:
			sb.bg_color = Color(0.08, 0.08, 0.08, 0.7)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.3, 0.3, 0.3, 0.8)
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		else:
			sb.bg_color = Color(0.04, 0.04, 0.04, 0.4)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.15, 0.15, 0.15, 0.4)
			
			if num_label:
				num_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))

		slot.add_theme_stylebox_override("panel", sb)

func _on_active_spell_changed(spell_name: String) -> void:
	if _player and "active_spell_index" in _player:
		_active_spell_idx = _player.active_spell_index
	_update_hotbar_display(_active_spell_idx)

func _on_skill_unlocked(_color: String) -> void:
	_update_hotbar_display(_active_spell_idx)

func _on_spell_charge_changed(current: float, max_c: float, is_charging: bool) -> void:
	if interact_label:
		if is_charging:
			var pct = int((current / max_c) * 100)
			interact_label.text = "CHARGING SPELL... %d%%" % pct
			interact_label.visible = true
		else:
			interact_label.visible = false

func _build_wave_ui() -> void:
	var root: Control = $Control
	var wave_panel: PanelContainer = PanelContainer.new()
	wave_panel.name = "WaveStatusPanel"
	wave_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_panel.position = Vector2(-300.0, 20.0)
	wave_panel.size = Vector2(280.0, 72.0)
	wave_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.045, 0.06, 0.92), Color(0.85, 0.63, 0.18, 0.9)))
	root.add_child(wave_panel)

	var wave_margin: MarginContainer = MarginContainer.new()
	wave_margin.add_theme_constant_override("margin_left", 16)
	wave_margin.add_theme_constant_override("margin_top", 9)
	wave_margin.add_theme_constant_override("margin_right", 16)
	wave_margin.add_theme_constant_override("margin_bottom", 9)
	wave_panel.add_child(wave_margin)
	var wave_rows: VBoxContainer = VBoxContainer.new()
	wave_margin.add_child(wave_rows)
	_wave_label = Label.new()
	_wave_label.text = "WAVE 1"
	_wave_label.add_theme_font_size_override("font_size", 19)
	_wave_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	wave_rows.add_child(_wave_label)
	_enemy_count_label = Label.new()
	_enemy_count_label.text = "Enemies remaining: 0"
	_enemy_count_label.add_theme_font_size_override("font_size", 14)
	wave_rows.add_child(_enemy_count_label)

	_warning_panel = PanelContainer.new()
	_warning_panel.name = "LaneWarningPanel"
	_warning_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_panel.position = Vector2(-260.0, 112.0)
	_warning_panel.size = Vector2(520.0, 58.0)
	_warning_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.035, 0.045, 0.94), Color.WHITE))
	root.add_child(_warning_panel)
	_warning_label = Label.new()
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 22)
	_warning_label.add_theme_constant_override("outline_size", 5)
	_warning_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_warning_panel.add_child(_warning_label)
	_warning_panel.hide()

	_reward_overlay = ColorRect.new()
	_reward_overlay.name = "WaveRewardOverlay"
	_reward_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_overlay.color = Color(0.015, 0.018, 0.025, 0.88)
	_reward_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_reward_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	root.add_child(_reward_overlay)

	var reward_panel: PanelContainer = PanelContainer.new()
	reward_panel.set_anchors_preset(Control.PRESET_CENTER)
	reward_panel.position = Vector2(-445.0, -170.0)
	reward_panel.size = Vector2(890.0, 340.0)
	reward_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.045, 0.055, 0.98), Color(0.9, 0.67, 0.2)))
	_reward_overlay.add_child(reward_panel)
	var reward_margin: MarginContainer = MarginContainer.new()
	reward_margin.add_theme_constant_override("margin_left", 28)
	reward_margin.add_theme_constant_override("margin_top", 24)
	reward_margin.add_theme_constant_override("margin_right", 28)
	reward_margin.add_theme_constant_override("margin_bottom", 24)
	reward_panel.add_child(reward_margin)
	var reward_rows: VBoxContainer = VBoxContainer.new()
	reward_rows.add_theme_constant_override("separation", 18)
	reward_margin.add_child(reward_rows)
	var reward_heading: Label = Label.new()
	reward_heading.text = "CHOOSE A BATTLE BOON"
	reward_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_heading.add_theme_font_size_override("font_size", 27)
	reward_heading.add_theme_color_override("font_color", Color(1.0, 0.8, 0.36))
	reward_rows.add_child(reward_heading)
	var reward_subheading: Label = Label.new()
	reward_subheading.text = "Wave secured. Choose one upgrade before the next assault."
	reward_subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_subheading.add_theme_font_size_override("font_size", 15)
	reward_rows.add_child(reward_subheading)
	_reward_choices = HBoxContainer.new()
	_reward_choices.add_theme_constant_override("separation", 14)
	reward_rows.add_child(_reward_choices)
	_reward_overlay.hide()

func _make_panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style

func _on_wave_state_changed(wave_number: int, enemies_remaining: int) -> void:
	_wave_label.text = "WAVE %d" % wave_number
	_enemy_count_label.text = "Enemies remaining: %d" % enemies_remaining

func _on_lane_warning_requested(_lane_name: String, message: String, lane_color: Color) -> void:
	if _warning_tween and _warning_tween.is_valid():
		_warning_tween.kill()
	_warning_label.text = message
	_warning_label.add_theme_color_override("font_color", lane_color)
	_warning_panel.modulate = Color.WHITE
	_warning_panel.show()
	_warning_tween = create_tween()
	_warning_tween.tween_interval(1.8)
	_warning_tween.tween_property(_warning_panel, "modulate:a", 0.0, 0.45)
	_warning_tween.tween_callback(_warning_panel.hide)

func _on_wave_reward_offered(options: Array) -> void:
	for child in _reward_choices.get_children():
		child.queue_free()

	for option in options:
		var choice: Button = Button.new()
		choice.custom_minimum_size = Vector2(260.0, 145.0)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.text = "%s\n\n%s" % [option["title"], option["description"]]
		choice.add_theme_font_size_override("font_size", 17)
		choice.add_theme_stylebox_override("normal", _make_panel_style(Color(0.08, 0.09, 0.11, 1.0), Color(0.28, 0.3, 0.34)))
		choice.add_theme_stylebox_override("hover", _make_panel_style(Color(0.15, 0.12, 0.07, 1.0), Color(1.0, 0.74, 0.22)))
		choice.pressed.connect(_on_reward_selected.bind(String(option["id"])))
		_reward_choices.add_child(choice)

	_reward_overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _on_reward_selected(reward_id: String) -> void:
	get_tree().paused = false
	_reward_overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SignalBus.wave_reward_selected.emit(reward_id)
