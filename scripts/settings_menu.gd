extends VBoxContainer
## Every option a player can set, in one tabbed panel that the main menu and the in-game
## Escape menu both show.
##
## It used to exist only in the HUD, authored node by node in hud.tscn and wired up there,
## so nothing could be changed before a run started - and a second copy for the main menu
## would have been the same forty controls twice, drifting. Built in code instead, the way
## MainMenu builds its pages, so both hosts instance exactly the same thing.
##
## Owns no state. Every control reads its starting value from UserSettings or
## GraphicsSettings and writes straight back through them, which is what saves it; the
## host only decides where the panel sits and adds its own extras (the HUD's debug tab)
## through add_tab().
##
## Deliberately no `class_name` - hosts preload it by path. See scripts/icon_style.gd.

const TAB_SEPARATION := 14

var _tabs: TabContainer
## The first control of the first tab, so a host can put keyboard focus somewhere useful.
var _first_control: Control

# Graphics controls, kept because a preset moves several of them at once.
var _preset_option: OptionButton
var _render_scale_slider: HSlider
var _render_scale_value: Label
var _shadows_check: CheckBox
var _msaa_option: OptionButton
var _glow_check: CheckBox
var _parallax_check: CheckBox
var _particles_option: OptionButton
var _renderer_option: OptionButton
var _restart_label: Label
var _restart_button: Button
## True while a preset is being applied programmatically, so the handlers of the controls it
## moves don't each flip the preset back to Custom.
var _applying_preset: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_tabs = TabContainer.new()
	_tabs.name = "SettingsTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0.0, 420.0)
	_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tabs)

	_build_gameplay_tab(add_tab("Gameplay"))
	_build_controls_tab(add_tab("Controls"))
	_build_audio_tab(add_tab("Audio"))
	_build_graphics_tab(add_tab("Graphics"))
	_tabs.current_tab = 0


## A new, empty tab; returns the column to put its controls into. Public so a host can add
## options only it can offer - the HUD's debug switches, which mean nothing on the menu.
func add_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", TAB_SEPARATION)
	margin.add_child(column)
	_tabs.add_child(scroll)
	return column


## Gives the first option keyboard focus, for a host that has just opened the panel.
func focus_first() -> void:
	if is_instance_valid(_first_control):
		_first_control.grab_focus()


# --- tabs ---------------------------------------------------------------------

func _build_gameplay_tab(column: VBoxContainer) -> void:
	_first_control = _check(column, "Show Minimap", UserSettings.show_minimap,
		func(on: bool) -> void: UserSettings.set_value(&"show_minimap", on))
	_slider(column, "Minimap Size", 100.0, 400.0, 10.0, UserSettings.minimap_size,
		func(value: float) -> String: return "%d px" % int(value),
		func(value: float) -> void: UserSettings.set_value(&"minimap_size", value))
	_check(column, "Show Damage Numbers", UserSettings.show_damage_numbers,
		func(on: bool) -> void: UserSettings.set_value(&"show_damage_numbers", on))
	_check(column, "Show Enemy Health Bars", UserSettings.show_enemy_health_bars,
		func(on: bool) -> void: UserSettings.set_value(&"show_enemy_health_bars", on))
	_check(column, "Show Attack Hitbox Indicators", UserSettings.show_attack_indicators,
		func(on: bool) -> void: UserSettings.set_value(&"show_attack_indicators", on))
	_label(column, "Attack Indicator Style")
	var style_option := OptionButton.new()
	var style_names: Dictionary = {"themed": "Themed", "rim": "Glowing Rim", "late": "Late Reveal", "classic": "Classic"}
	for style: String in AttackIndicator.STYLES:
		style_option.add_item(String(style_names.get(style, style)))
		style_option.set_item_metadata(style_option.item_count - 1, style)
		if style == UserSettings.attack_indicator_style:
			style_option.select(style_option.item_count - 1)
	style_option.item_selected.connect(func(index: int) -> void:
		UserSettings.set_value(&"attack_indicator_style", String(style_option.get_item_metadata(index))))
	column.add_child(style_option)
	_check(column, "Camera Shake", UserSettings.camera_shake_enabled,
		func(on: bool) -> void: UserSettings.set_value(&"camera_shake_enabled", on))


## Volumes are sliders from silent to full. The bottom of each is OFF, not merely quiet -
## the old music slider stopped at -24 dB, which is still clearly audible.
func _build_controls_tab(column: VBoxContainer) -> void:
	var table := GridContainer.new()
	table.columns = 3
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 8)
	column.add_child(table)

	var header_color := Color(0.18, 0.22, 0.30, 1.0)
	var alt_row_color := Color(0.12, 0.14, 0.18, 1.0)
	var headers: Array = ["Action", "Keyboard", "Gamepad"]
	for header_text: String in headers:
		var header_label := Label.new()
		header_label.text = header_text
		header_label.add_theme_font_size_override("font_size", 14)
		header_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
		header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		header_label.self_modulate = header_color
		table.add_child(header_label)

	var rows: Array = [
		["Movement", "W / A / S / D or Arrow Keys", "Left stick"],
		["Jump", "Space", "A"],
		["Main spell", "Q", "RT"],
		["Attack", "Left mouse button", "LT"],
		["Block", "Right mouse button", "LB"],
		["Interact", "E", "X"],
		["Kick", "F", "B"],
		["Hotbar", "1 - 8", "-"],
		["Cycle spell", "Mouse wheel", "L/R shoulder"],
		["Skill tree", "P", "Y"],
		["Menu", "Esc", "Start"],
		["Sprint", "Shift", "L3"],
		["Wave info", "F1", "-"],
	]
	for row_index: int in range(rows.size()):
		for value_idx: int in range(3):
			var cell := Label.new()
			cell.text = String(rows[row_index][value_idx])
			cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if row_index % 2 == 1:
				cell.self_modulate = alt_row_color
			if value_idx == 0:
				cell.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
			table.add_child(cell)


func _build_audio_tab(column: VBoxContainer) -> void:
	_slider(column, "Master Volume", 0.0, 100.0, 1.0, UserSettings.master_volume * 100.0,
		_percent_text, func(value: float) -> void: UserSettings.set_value(&"master_volume", value / 100.0))
	_slider(column, "Music Volume", 0.0, 100.0, 1.0, UserSettings.music_volume * 100.0,
		_percent_text, func(value: float) -> void: UserSettings.set_value(&"music_volume", value / 100.0))
	_slider(column, "Effects Volume", 0.0, 100.0, 1.0, UserSettings.sfx_volume * 100.0,
		_percent_text, func(value: float) -> void: UserSettings.set_value(&"sfx_volume", value / 100.0))
	_check(column, "Music", UserSettings.music_enabled,
		func(on: bool) -> void: UserSettings.set_value(&"music_enabled", on))


func _build_graphics_tab(column: VBoxContainer) -> void:
	_label(column, "Quality Preset")
	_preset_option = OptionButton.new()
	_preset_option.add_item("Low", GraphicsSettings.Preset.LOW)
	_preset_option.add_item("Medium", GraphicsSettings.Preset.MEDIUM)
	_preset_option.add_item("High", GraphicsSettings.Preset.HIGH)
	_preset_option.add_item("Custom", GraphicsSettings.Preset.CUSTOM)
	_preset_option.select(_preset_option.get_item_index(GraphicsSettings.preset))
	_preset_option.item_selected.connect(_on_preset_selected)
	column.add_child(_preset_option)

	var scale_row: Array = _slider(column, "Render Scale", 0.5, 1.0, 0.05, GraphicsSettings.render_scale,
		func(value: float) -> String: return "%d%%" % int(round(value * 100.0)),
		func(value: float) -> void:
			GraphicsSettings.apply_render_scale(value)
			_mark_custom())
	_render_scale_slider = scale_row[0]
	_render_scale_value = scale_row[1]

	_shadows_check = _check(column, "Shadows", GraphicsSettings.shadows_enabled,
		func(on: bool) -> void:
			GraphicsSettings.apply_shadows(on)
			_mark_custom())

	_label(column, "Anti-Aliasing")
	_msaa_option = OptionButton.new()
	_msaa_option.add_item("Off", 0)
	_msaa_option.add_item("MSAA 2x", 1)
	_msaa_option.add_item("MSAA 4x", 2)
	_msaa_option.select(GraphicsSettings.msaa_level)
	_msaa_option.item_selected.connect(func(index: int) -> void:
		GraphicsSettings.apply_msaa(index)
		_mark_custom())
	column.add_child(_msaa_option)

	_glow_check = _check(column, "Bloom / Glow", GraphicsSettings.glow_enabled,
		func(on: bool) -> void:
			GraphicsSettings.apply_glow(on)
			_mark_custom())
	_parallax_check = _check(column, "Ground Relief (Parallax)", GraphicsSettings.terrain_parallax,
		func(on: bool) -> void:
			GraphicsSettings.apply_terrain_parallax(on)
			_mark_custom())

	_label(column, "Particle Effects")
	_particles_option = OptionButton.new()
	_particles_option.add_item("Low", GraphicsSettings.ParticleQuality.LOW)
	_particles_option.add_item("Medium", GraphicsSettings.ParticleQuality.MEDIUM)
	_particles_option.add_item("High", GraphicsSettings.ParticleQuality.HIGH)
	_particles_option.add_item("Ultra", GraphicsSettings.ParticleQuality.ULTRA)
	_particles_option.select(_particles_option.get_item_index(GraphicsSettings.particle_quality))
	_particles_option.item_selected.connect(func(index: int) -> void:
		GraphicsSettings.apply_particle_quality(_particles_option.get_item_id(index))
		_mark_custom())
	column.add_child(_particles_option)
	_check(column, "VSync", GraphicsSettings.vsync_enabled,
		func(on: bool) -> void: GraphicsSettings.apply_vsync(on))
	_check(column, "Show FPS Counter", GraphicsSettings.show_fps,
		func(on: bool) -> void: GraphicsSettings.set_show_fps(on))

	_label(column, "Renderer")
	_renderer_option = OptionButton.new()
	_renderer_option.add_item("Forward+ (best visuals)", 0)
	_renderer_option.add_item("Mobile (balanced)", 1)
	_renderer_option.add_item("Compatibility (weak / integrated GPUs)", 2)
	_renderer_option.select(maxi(GraphicsSettings.RENDERER_METHODS.find(GraphicsSettings.chosen_rendering_method()), 0))
	_renderer_option.item_selected.connect(func(index: int) -> void:
		GraphicsSettings.set_pending_rendering_method(GraphicsSettings.RENDERER_METHODS[index])
		_mark_custom()
		_refresh_restart_notice())
	column.add_child(_renderer_option)

	_restart_label = Label.new()
	_restart_label.text = "The new renderer takes effect after a restart."
	_restart_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	column.add_child(_restart_label)

	_restart_button = Button.new()
	_restart_button.text = "Restart Now"
	_restart_button.custom_minimum_size = Vector2(0.0, 36.0)
	_restart_button.pressed.connect(GraphicsSettings.restart_to_apply)
	column.add_child(_restart_button)
	_refresh_restart_notice()


# --- graphics presets ---------------------------------------------------------

func _on_preset_selected(index: int) -> void:
	var chosen: int = _preset_option.get_item_id(index)
	if chosen == GraphicsSettings.Preset.CUSTOM:
		GraphicsSettings.mark_custom()
		return
	_applying_preset = true
	GraphicsSettings.apply_preset(chosen)
	_render_scale_slider.value = GraphicsSettings.render_scale
	_shadows_check.button_pressed = GraphicsSettings.shadows_enabled
	_msaa_option.select(GraphicsSettings.msaa_level)
	_glow_check.button_pressed = GraphicsSettings.glow_enabled
	_parallax_check.button_pressed = GraphicsSettings.terrain_parallax
	_particles_option.select(_particles_option.get_item_index(GraphicsSettings.particle_quality))
	_renderer_option.select(maxi(GraphicsSettings.RENDERER_METHODS.find(GraphicsSettings.chosen_rendering_method()), 0))
	_applying_preset = false
	_refresh_restart_notice()


## One option moved by hand, so the preset no longer describes the settings.
func _mark_custom() -> void:
	if _applying_preset:
		return
	GraphicsSettings.mark_custom()
	_preset_option.select(_preset_option.get_item_index(GraphicsSettings.Preset.CUSTOM))


func _refresh_restart_notice() -> void:
	_restart_label.visible = GraphicsSettings.restart_required
	_restart_button.visible = GraphicsSettings.restart_required


# --- building blocks ----------------------------------------------------------

func _check(column: VBoxContainer, text: String, pressed: bool, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	check.toggled.connect(on_toggled)
	column.add_child(check)
	return check


func _label(column: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	column.add_child(label)
	return label


## A labelled slider with its current value printed beside the name, because "Music Volume"
## over an unmarked bar leaves the player guessing where the old -24 dB floor went.
## Returns [slider, value label].
func _slider(column: VBoxContainer, text: String, min_value: float, max_value: float, step: float,
		value: float, format: Callable, on_changed: Callable) -> Array:
	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := Label.new()
	value_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	header.add_child(value_label)
	column.add_child(header)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	value_label.text = format.call(slider.value)
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = format.call(new_value)
		on_changed.call(new_value))
	column.add_child(slider)
	return [slider, value_label]


func _percent_text(value: float) -> String:
	return "%d%%" % int(round(value)) if value > 0.0 else "Off"
