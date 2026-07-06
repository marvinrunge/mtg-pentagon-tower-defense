extends CanvasLayer
class_name HUD

@onready var health_bar: ProgressBar = $Control/MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $Control/MarginContainer/VBoxContainer/HealthContainer/HealthLabel
@onready var player_health_bar: ProgressBar = $Control/MarginContainer/VBoxContainer/PlayerHealthContainer/Bar
@onready var player_health_label: Label = $Control/MarginContainer/VBoxContainer/PlayerHealthContainer/Label
@onready var xp_bar: ProgressBar = $Control/MarginContainer/VBoxContainer/XPContainer/Bar
@onready var xp_label: Label = $Control/MarginContainer/VBoxContainer/XPContainer/Label
@onready var mana_label_w: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelW
@onready var mana_label_u: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelU
@onready var mana_label_b: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelB
@onready var mana_label_r: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelR
@onready var mana_label_g: Label = $Control/MarginContainer/VBoxContainer/ManaContainer/ManaLabelG
@onready var spell_label: Label = $Control/MarginContainer/VBoxContainer/SpellLabel
@onready var status_label: Label = $Control/MarginContainer/VBoxContainer/StatusLabel
@onready var interact_label: Label = $Control/InteractLabel

@onready var settings_panel: PanelContainer = $Control/SettingsPanel
@onready var minimap_container: MarginContainer = $Control/MinimapContainer
@onready var minimap: ColorRect = $Control/MinimapContainer/Minimap
@onready var show_minimap_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/VBoxContainer/ShowMinimapCheckbox
@onready var minimap_size_slider: HSlider = $Control/SettingsPanel/MarginContainer/VBoxContainer/MinimapSizeSlider

func _ready() -> void:
	SignalBus.health_changed.connect(update_health)
	SignalBus.player_health_changed.connect(update_player_health)
	SignalBus.mana_changed.connect(update_mana)
	SignalBus.xp_changed.connect(update_xp)
	SignalBus.player_leveled_up.connect(update_level)
	SignalBus.active_spell_changed.connect(update_spell)
	SignalBus.at_base_changed.connect(_on_at_base_changed)
	SignalBus.enemy_focused.connect(_on_enemy_focused)
	
	show_minimap_checkbox.toggled.connect(_on_show_minimap_toggled)
	minimap_size_slider.value_changed.connect(_on_minimap_size_changed)
	settings_panel.hide()
	
	setup_styles()
	update_health(1000, 1000)
	update_player_health(100, 100)
	update_mana({})
	update_xp(0, 100)
	update_level(1, 0)

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
	
	var sb_xp_fg = sb_fg.duplicate()
	sb_xp_fg.bg_color = Color(0.8, 0.6, 0.1, 0.9) # Gold
	xp_bar.add_theme_stylebox_override("background", sb_bg)
	xp_bar.add_theme_stylebox_override("fill", sb_xp_fg)

func update_health(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current
	health_label.text = "Crystal Integrity: %d / %d" % [current, max_health]
	
	if current <= 0:
		status_label.text = "DEFEAT - THE CRYSTAL SHATTERED!"
		status_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	elif current < 30:
		status_label.text = "CRITICAL WARNING: BASE UNDER ATTACK!"
		status_label.add_theme_color_override("font_color", Color(1, 0.5, 0))

func update_player_health(current: float, max_health: float) -> void:
	player_health_bar.max_value = max_health
	player_health_bar.value = current
	player_health_label.text = "Hero Health: %d / %d" % [current, max_health]
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

func update_xp(current: int, max_xp: int) -> void:
	xp_bar.max_value = max_xp
	xp_bar.value = current
	xp_label.text = xp_label.text.split(" | ")[0] + " | XP: %d / %d" % [current, max_xp]

func update_level(level: int, sp: int) -> void:
	var xp_part = ""
	if xp_label.text.split(" | ").size() > 1:
		xp_part = " | " + xp_label.text.split(" | ")[1]
	xp_label.text = "Level: %d (SP: %d)" % [level, sp] + xp_part

func update_spell(spell_name: String) -> void:
	if spell_label:
		spell_label.text = "Active Spell: " + spell_name

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		settings_panel.visible = !settings_panel.visible
		if settings_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_show_minimap_toggled(button_pressed: bool) -> void:
	minimap_container.visible = button_pressed

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
	
	# Create a temporary style for the enemy health bar based on its color
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = color
	sb_fg.corner_radius_top_left = 6
	sb_fg.corner_radius_top_right = 6
	sb_fg.corner_radius_bottom_left = 6
	sb_fg.corner_radius_bottom_right = 6
	bar.add_theme_stylebox_override("fill", sb_fg)

func _on_at_base_changed(is_at_base: bool) -> void:
	if interact_label:
		interact_label.visible = is_at_base
