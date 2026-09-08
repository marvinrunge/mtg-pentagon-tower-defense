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
@onready var xp_bar: ProgressBar = $Control/XPBar
@onready var settings_backdrop: ColorRect = $Control/SettingsBackdrop

@onready var settings_panel: PanelContainer = $Control/SettingsPanel
@onready var minimap_container: MarginContainer = $Control/MinimapContainer
@onready var minimap: ColorRect = $Control/MinimapContainer/Minimap
@onready var show_minimap_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/ShowMinimapCheckbox
@onready var damage_numbers_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/DamageNumbersCheckbox
@onready var enemy_health_bars_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/EnemyHealthBarsCheckbox
@onready var attack_indicators_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/AttackIndicatorsCheckbox
@onready var camera_shake_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/CameraShakeCheckbox
@onready var music_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/MusicCheckbox
@onready var music_volume_slider: HSlider = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/MusicVolumeSlider
@onready var minimap_size_slider: HSlider = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/MinimapSizeSlider

@onready var quality_preset_option: OptionButton = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/QualityPresetOption
@onready var render_scale_slider: HSlider = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/RenderScaleSlider
@onready var shadows_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/ShadowsCheckbox
@onready var anti_aliasing_option: OptionButton = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/AntiAliasingOption
@onready var glow_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/GlowCheckbox
@onready var vsync_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/VSyncCheckbox
@onready var show_fps_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/ShowFpsCheckbox
@onready var free_skills_checkbox: CheckBox = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/FreeSkillsCheckbox
@onready var fps_label: Label = $Control/FpsLabel
@onready var renderer_option: OptionButton = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/RendererOption
@onready var restart_required_label: Label = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/RestartRequiredLabel
@onready var apply_restart_btn: Button = $Control/SettingsPanel/MarginContainer/ScrollContainer/VBoxContainer/ApplyRestartBtn

const RENDERER_METHODS: Array[String] = ["forward_plus", "mobile", "gl_compatibility"]
# True while a preset is being applied programmatically, so the individual
# control handlers it drives don't each also flip the preset back to Custom.
var _applying_preset: bool = false

@onready var game_over_panel: PanelContainer = $Control/GameOverPanel
@onready var restart_btn: Button = $Control/GameOverPanel/MarginContainer/VBoxContainer/RestartBtn

# --- Spell Hotbar ---
var _hotbar_slots: Array[PanelContainer] = []
var _player: Node3D = null
var _active_spell_idx: int = 0
var _wave_panel: PanelContainer
var _wave_label: Label
var _enemy_count_label: Label
var _warning_panel: PanelContainer
var _warning_label: Label
var _warning_tween: Tween
var _fps_update_timer: float = 0.0
## Which full-screen menus are up right now. A set rather than a flag because more than one
## can be open at a time, and the HUD has to stay out of the way until the LAST one closes.
var _open_menus: Dictionary = {}
## Exactly what this hid when a menu opened, so closing it restores those and nothing else.
## Without this, a wave panel the player had put away with Tab would come back every time
## they closed the skill tree.
var _hidden_for_menu: Array[CanvasItem] = []

const ACTIVE_SLOT_COLOR: Color = Color(0.95, 0.72, 0.22)

## The player's health runs light to dark across the bar - a pale spring green at the left
## edge into a deep forest green at the right. Both sit off pure green (the light end is
## warmed towards yellow, the dark end cooled towards blue), which is what keeps the ramp
## reading as one material rather than as one colour being dimmed.
const HP_FILL_LIGHT: Color = Color(0.65, 0.90, 0.53, 0.95)
const HP_FILL_DARK: Color = Color(0.08, 0.38, 0.24, 0.95)
## Small, because it is stretched to the bar: only the ramp and the corner shape have to
## survive, and neither carries any detail worth more pixels than this.
## The frame every readout shares - both bars and the minimap. Kept as constants because
## the point of it is that they MATCH; three copies of "2px, this grey, 8px corners" drift
## the first time one of them is nudged.
const BAR_BORDER_COLOR: Color = Color(0.42, 0.5, 0.6, 0.9)
const BAR_BORDER_WIDTH: int = 2
const BAR_CORNER_RADIUS: int = 8

const HP_FILL_TEXTURE_SIZE := Vector2i(96, 24)
const HP_FILL_CORNER_RADIUS: float = 5.0

## Team XP runs blue into violet - the two colours nothing else in the HUD uses, so the
## bar cannot be mistaken for either health (green) or the crystal (red) at a glance. Same
## ramp direction as health: the lighter end at the left, where the bar starts.
const XP_FILL_LIGHT: Color = Color(0.35, 0.68, 1.0, 0.95)
const XP_FILL_DARK: Color = Color(0.47, 0.22, 0.82, 0.95)

## The crystal, on the same ramp shape as the other two: a hot ember at the left into deep
## crimson at the right. Read as "the thing that is burning down", which is what it is.
const BASE_FILL_LIGHT: Color = Color(1.0, 0.45, 0.32, 0.95)
const BASE_FILL_DARK: Color = Color(0.52, 0.07, 0.13, 0.95)

## The minimap's corners, as a fraction of its own size rather than the bars' flat 8px.
## It is a square window onto a PENTAGON, so there is nothing in the corners to clip - and
## at 200px a quarter is 50, which no fixed number shared with a 30px-tall bar could be.
const MINIMAP_CORNER_RATIO: float = 0.25

## Hotbar slots are square, so a square spell icon fills one instead of sitting
## letterboxed in an upright rectangle. 60 was already the minimum WIDTH, but the VBox
## stacked an icon, a key number and a name row, and that pushed the height past it.
const HOTBAR_SLOT_SIZE := 60.0
## The icon is the slot now: it sits directly under the PanelContainer, which stretches a
## direct child to fill, so there is no minimum size left to tune. The key number rides on
## top as an overlay instead of stealing a layout row from it.
##
## Its rounded corners come from IconStyle, which every icon in the game shares.
const IconStyle := preload("res://scripts/icon_style.gd")

func _ready() -> void:
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	SignalBus.health_changed.connect(update_health)
	SignalBus.player_health_changed.connect(update_player_health)
	SignalBus.mana_changed.connect(update_mana)
	SignalBus.active_spell_changed.connect(update_spell)
	SignalBus.at_base_changed.connect(_on_at_base_changed)
	SignalBus.interact_prompt_changed.connect(_on_interact_prompt_changed)
	SignalBus.spell_charge_changed.connect(_on_spell_charge_changed)
	SignalBus.spell_unlocked.connect(func(_c, _s): _update_hotbar_display(_active_spell_idx))
	SignalBus.color_path_chosen.connect(func(_c): _update_hotbar_display(_active_spell_idx))
	# The bar is a LOADOUT now, so it has to follow the loadout: a rank bought or a slot
	# rebound in the skill tree changes what these ten keys say they do.
	SignalBus.spell_rank_changed.connect(func(_id, _rank): _update_hotbar_display(_active_spell_idx))
	SignalBus.quick_slots_changed.connect(func(): _update_hotbar_display(_active_spell_idx))
	SignalBus.menu_opened.connect(_on_menu_opened)
	SignalBus.wave_state_changed.connect(_on_wave_state_changed)
	SignalBus.lane_warning_requested.connect(_on_lane_warning_requested)
	
	show_minimap_checkbox.toggled.connect(_on_show_minimap_toggled)
	if damage_numbers_checkbox:
		damage_numbers_checkbox.button_pressed = GameSettings.show_damage_numbers
		damage_numbers_checkbox.toggled.connect(_on_damage_numbers_toggled)
	if enemy_health_bars_checkbox:
		enemy_health_bars_checkbox.button_pressed = GameSettings.show_enemy_health_bars
		enemy_health_bars_checkbox.toggled.connect(_on_enemy_health_bars_toggled)
	if attack_indicators_checkbox:
		attack_indicators_checkbox.button_pressed = GameSettings.show_attack_indicators
		attack_indicators_checkbox.toggled.connect(_on_attack_indicators_toggled)
	if camera_shake_checkbox:
		camera_shake_checkbox.button_pressed = GameSettings.camera_shake_enabled
		camera_shake_checkbox.toggled.connect(_on_camera_shake_toggled)
	if music_checkbox:
		music_checkbox.button_pressed = GameSettings.music_enabled
		music_checkbox.toggled.connect(_on_music_toggled)
	if music_volume_slider:
		music_volume_slider.value = GameSettings.music_volume_db
		music_volume_slider.value_changed.connect(_on_music_volume_changed)
	minimap_size_slider.value_changed.connect(_on_minimap_size_changed)
	_setup_graphics_settings()
	_build_settings_tabs()
	restart_btn.pressed.connect(_on_restart_pressed)
	settings_panel.hide()
	game_over_panel.hide()
	_build_wave_ui()
	
	# hud.tscn authors the first five; the rest are duplicates of it, so the bar follows
	# Player.QUICK_SLOT_COUNT rather than a count written out twice.
	var spell_hotbar: HBoxContainer = $Control/HotbarContainer/SpellHotbar
	for slot_index: int in range(spell_hotbar.get_child_count(), Player.QUICK_SLOT_COUNT):
		var slot: PanelContainer = spell_hotbar.get_child(0).duplicate() as PanelContainer
		slot.name = "Slot%d" % (slot_index + 1)
		var num_label: Label = slot.get_node("VBox/Num") as Label
		num_label.text = str(slot_index + 1)
		spell_hotbar.add_child(slot)
	for child: Node in spell_hotbar.get_children():
		if child is PanelContainer:
			_hotbar_slots.append(child as PanelContainer)
	_ensure_hotbar_icons()
	_lay_out_hotbar_slots()
	_setup_mana_icons()
	SignalBus.active_spell_changed.connect(_on_active_spell_changed)
	SignalBus.skill_unlocked.connect(_on_skill_unlocked)
	SignalBus.upkeep_started.connect(func(_d: float): _upkeep_open = true)
	SignalBus.upkeep_finished.connect(func(): _upkeep_open = false)
	SignalBus.team_level_changed.connect(_on_team_level_changed)
	
	_player = PlayerRegistry.get_local()
	_update_hotbar_display(0)
	_update_xp_bar()
	
	setup_styles()
	update_health(GameSettings.crystal_max_hp, GameSettings.crystal_max_hp)
	update_player_health(GameSettings.player_max_hp, GameSettings.player_max_hp)
	update_mana({})

func _process(delta: float) -> void:
	if fps_label.visible:
		_fps_update_timer -= delta
		if _fps_update_timer <= 0.0:
			_fps_update_timer = 0.25
			fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if _player == null or not is_instance_valid(_player):
		_player = PlayerRegistry.get_local()
		
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
		_update_xp_bar()

func _update_xp_bar() -> void:
	if not xp_bar:
		return
	var progress: Vector2 = RunState.xp_progress()
	xp_bar.value = progress.x / progress.y


func setup_styles() -> void:
	# Style the Health ProgressBar with a modern glassmorphic theme
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.15, 0.5)
	sb_bg.set_border_width_all(BAR_BORDER_WIDTH)
	sb_bg.border_color = BAR_BORDER_COLOR
	sb_bg.set_corner_radius_all(BAR_CORNER_RADIUS)
	
	health_bar.add_theme_stylebox_override("background", sb_bg)
	health_bar.add_theme_stylebox_override("fill", _gradient_fill_style(BASE_FILL_LIGHT, BASE_FILL_DARK))
	
	player_health_bar.add_theme_stylebox_override("background", sb_bg)
	player_health_bar.add_theme_stylebox_override("fill", _gradient_fill_style(HP_FILL_LIGHT, HP_FILL_DARK))

	xp_bar.add_theme_stylebox_override("background", sb_bg)
	xp_bar.add_theme_stylebox_override("fill", _gradient_fill_style(XP_FILL_LIGHT, XP_FILL_DARK))

	# The frame goes over all three, and over the minimap, which is the fourth readout in
	# the same corner language even though it is not a bar.
	# The crystal's number goes INSIDE its bar, the way the player's health already does.
	# Beside it, the label pushed the bar off-centre and made the pair read as two separate
	# things rather than as one readout.
	_move_label_into_bar(health_label, health_bar)
	_add_border_overlay(health_bar)
	_add_border_overlay(player_health_bar)
	_add_border_overlay(xp_bar)
	_style_minimap(sb_bg)

	var settings_bg := StyleBoxFlat.new()
	settings_bg.bg_color = Color(0.015, 0.02, 0.03, 1.0)
	settings_bg.border_width_left = 2
	settings_bg.border_width_top = 2
	settings_bg.border_width_right = 2
	settings_bg.border_width_bottom = 2
	settings_bg.border_color = Color(0.35, 0.42, 0.55, 1.0)
	settings_panel.add_theme_stylebox_override("panel", settings_bg)

## A ProgressBar's fill is a stylebox, and a StyleBoxFlat is one flat colour - so a
## gradient fill has to be a TEXTURE. Drawn here rather than importped so the ramp lives
## next to the colours it is made of, and given the same rounded silhouette the flat fills
## have by baking the corner into the image's alpha, because a StyleBoxTexture carries no
## corner_radius of its own.
##
## The texture stretches to whatever the fill rect currently is, so the ramp always spans
## the FILLED part of the bar - at a sliver of health the player sees the whole light-to-
## dark run compressed, not just its light end.
## Gives the minimap the same rounded, bordered ground the bars stand on.
##
## The minimap is a ColorRect that paints its own square black rectangle and then draws the
## world's dots over it, so it cannot simply be given a stylebox. Its colour is cleared and
## a Panel is slipped in BEHIND it instead - a sibling drawn first, which is the only way to
## get a rounded background under something that does its own drawing - and the frame goes
## over the top the same way it does on a bar.
## Reparents a bar's number onto the bar itself, hard against the left edge.
##
## Left rather than centred: this one shares its line with nothing, and a number pinned to
## the edge it fills from is easier to read at a glance than one that floats in the middle
## of a bar whose fill is moving underneath it.
func _move_label_into_bar(label: Label, bar: ProgressBar) -> void:
	if label == null or bar == null or label.get_parent() == bar:
		return
	label.get_parent().remove_child(label)
	bar.add_child(label)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# It now sits ON the fill, which is bright at one end and dark at the other, so it
	# carries its own outline exactly as the player's health readout does.
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("line_spacing", 0)
	# Indented off the border rather than touching it.
	label.offset_left = 10.0
	label.offset_right = -10.0


func _style_minimap(background: StyleBoxFlat) -> void:
	if minimap == null or minimap_container == null:
		return
	if minimap_container.get_node_or_null("MinimapBackdrop") == null:
		var backdrop := Panel.new()
		backdrop.name = "MinimapBackdrop"
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Its own copy of the bars' background: the corner radius differs, and a shared
		# StyleBox would take the bars' corners with it.
		backdrop.add_theme_stylebox_override("panel", background.duplicate())
		minimap_container.add_child(backdrop)
		minimap_container.move_child(backdrop, 0)
	# Cleared, or the square corners of its own fill show outside the rounded frame.
	minimap.color = Color(0.0, 0.0, 0.0, 0.0)
	_add_border_overlay(minimap, _minimap_corner_radius())
	_apply_minimap_size(minimap.custom_minimum_size.x)


func _minimap_corner_radius() -> int:
	var side: float = minf(minimap.custom_minimum_size.x, minimap.custom_minimum_size.y)
	if side <= 0.0:
		side = minf(minimap.size.x, minimap.size.y)
	return int(roundf(side * MINIMAP_CORNER_RATIO))


## The radius is a FRACTION, so it has to be recomputed whenever the minimap is resized
## from the settings panel - otherwise a map dragged from 200px to 320px keeps the corners
## it had at 200 and stops matching itself.
func _refresh_minimap_corners() -> void:
	var radius: int = _minimap_corner_radius()
	for node: Node in [minimap_container.get_node_or_null("MinimapBackdrop"),
			minimap.get_node_or_null("BorderOverlay")]:
		if node == null:
			continue
		var style: StyleBoxFlat = (node as Control).get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.set_corner_radius_all(radius)


## Draws the frame ON TOP of `target` rather than behind it.
##
## A ProgressBar's fill ignores its background stylebox's margins and is drawn over the
## whole rect - so at 100% the fill covers the background's border completely, and the bar
## loses its outline at exactly the moment the player most wants to see that it is full.
## An overlay child is drawn after its parent, which is the one place a border survives a
## full bar.
##
## `draw_center = false` is what makes the stylebox a frame and nothing else, so the fill
## underneath shows through untouched.
func _add_border_overlay(target: Control, corner_radius: int = BAR_CORNER_RADIUS) -> void:
	if target == null or target.get_node_or_null("BorderOverlay") != null:
		return
	var overlay := Panel.new()
	overlay.name = "BorderOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = BAR_BORDER_COLOR
	style.set_border_width_all(BAR_BORDER_WIDTH)
	style.set_corner_radius_all(corner_radius)
	overlay.add_theme_stylebox_override("panel", style)

	target.add_child(overlay)
	# Anchors alone were not enough: a Panel added to a Control that has already been laid
	# out keeps a zero rect until something re-runs the layout, and nothing does - the
	# overlay was present, visible, and 0x0 on every bar. Sized explicitly now, and kept in
	# step with the bar afterwards, which the minimap needs anyway because its size is a
	# setting the player can drag.
	# NOT anchored to the parent's rect: stretched anchors plus an explicit size is exactly
	# what Godot warns about, and the anchors alone left the overlay at 0x0 anyway - nothing
	# re-runs the layout of a Control that was already laid out before the child arrived.
	overlay.size = target.size
	overlay.position = Vector2.ZERO
	target.resized.connect(func() -> void:
		if is_instance_valid(overlay):
			overlay.size = target.size
			overlay.position = Vector2.ZERO)


func _gradient_fill_style(light: Color, dark: Color) -> StyleBoxTexture:
	var image := Image.create(HP_FILL_TEXTURE_SIZE.x, HP_FILL_TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(HP_FILL_TEXTURE_SIZE) * 0.5
	for x: int in range(HP_FILL_TEXTURE_SIZE.x):
		var ramp: Color = light.lerp(dark, float(x) / float(HP_FILL_TEXTURE_SIZE.x - 1))
		for y: int in range(HP_FILL_TEXTURE_SIZE.y):
			# Distance to a rounded box, the same shape the flat styleboxes draw, turned
			# into one pixel of coverage so the corners are not stair-stepped.
			var corner: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - half).abs() \
				- (half - Vector2(HP_FILL_CORNER_RADIUS, HP_FILL_CORNER_RADIUS))
			var dist: float = Vector2(maxf(corner.x, 0.0), maxf(corner.y, 0.0)).length() - HP_FILL_CORNER_RADIUS
			image.set_pixel(x, y, Color(ramp.r, ramp.g, ramp.b, ramp.a * clampf(0.5 - dist, 0.0, 1.0)))
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	return style


func update_health(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current
	health_label.text = "Base: %d / %d" % [current, max_health]
	
	if current <= 0:
		status_label.text = "DEFEAT - THE CRYSTAL SHATTERED!"
		status_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		if game_over_panel:
			game_over_panel.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			restart_btn.grab_focus()
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
	# Just the count. The colour is already carried by the icon _setup_mana_icons puts
	# in front of each label, so a "W:" prefix said the same thing twice.
	if mana_label_w:
		mana_label_w.text = "%d" % mana_pool.get("White", 0)
	if mana_label_u:
		mana_label_u.text = "%d" % mana_pool.get("Blue", 0)
	if mana_label_b:
		mana_label_b.text = "%d" % mana_pool.get("Black", 0)
	if mana_label_r:
		mana_label_r.text = "%d" % mana_pool.get("Red", 0)
	if mana_label_g:
		mana_label_g.text = "%d" % mana_pool.get("Green", 0)

func update_spell(spell_name: String) -> void:
	pass

func _input(event: InputEvent) -> void:
	if game_over_panel and game_over_panel.visible:
		return
	if _upkeep_open:
		return
	# Tab pulls the wave readout up and puts it away again. Skipped while the settings
	# panel is open, because Tab is also the UI focus key and stealing it there would
	# break keyboard navigation through the options.
	if event.is_action_pressed("wave_info") and not (settings_panel and settings_panel.visible):
		if _wave_panel:
			_wave_panel.visible = not _wave_panel.visible
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		settings_panel.visible = !settings_panel.visible
		settings_backdrop.visible = settings_panel.visible
		SignalBus.menu_opened.emit("settings", settings_panel.visible)
		if settings_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			show_minimap_checkbox.grab_focus()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_settings_tabs() -> void:
	var margin: MarginContainer = settings_panel.get_node("MarginContainer") as MarginContainer
	var scroll: ScrollContainer = margin.get_node("ScrollContainer") as ScrollContainer
	var source: VBoxContainer = scroll.get_node("VBoxContainer") as VBoxContainer
	var controls: Array[Node] = source.get_children()
	var tabs := TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.layout_mode = 2
	tabs.custom_minimum_size = Vector2(0.0, 500.0)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	var gameplay_scroll := ScrollContainer.new()
	gameplay_scroll.name = "Gameplay"
	gameplay_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	gameplay_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var gameplay := VBoxContainer.new()
	gameplay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gameplay.add_theme_constant_override("separation", 15)
	gameplay_scroll.add_child(gameplay)
	tabs.add_child(gameplay_scroll)
	var graphics_scroll := ScrollContainer.new()
	graphics_scroll.name = "Graphics"
	graphics_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	graphics_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var graphics := VBoxContainer.new()
	graphics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics.add_theme_constant_override("separation", 15)
	graphics_scroll.add_child(graphics)
	tabs.add_child(graphics_scroll)
	for child: Node in controls:
		source.remove_child(child)
		if child.name in ["GraphicsSeparator", "GraphicsHeaderLabel", "QualityPresetLabel", "QualityPresetOption", "RenderScaleLabel", "RenderScaleSlider", "ShadowsCheckbox", "AntiAliasingLabel", "AntiAliasingOption", "GlowCheckbox", "VSyncCheckbox", "ShowFpsCheckbox", "RendererLabel", "RendererOption", "RestartRequiredLabel", "ApplyRestartBtn"]:
			graphics.add_child(child)
		else:
			gameplay.add_child(child)
	margin.remove_child(scroll)
	scroll.queue_free()
	margin.add_child(tabs)
	tabs.current_tab = 0

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

func _on_attack_indicators_toggled(button_pressed: bool) -> void:
	GameSettings.show_attack_indicators = button_pressed
	SignalBus.attack_indicators_visibility_changed.emit(button_pressed)

func _on_camera_shake_toggled(button_pressed: bool) -> void:
	GameSettings.camera_shake_enabled = button_pressed


func _on_music_toggled(button_pressed: bool) -> void:
	GameSettings.music_enabled = button_pressed
	SoundBank.apply_music_settings()


func _on_music_volume_changed(value: float) -> void:
	GameSettings.music_volume_db = value
	SoundBank.apply_music_settings()


## Debug: makes every skill-tree node free and ungated. The tree redraws itself off
## the mana_changed signal, so nudging it is what repaints the nodes that just became
## affordable without waiting for the next mana pickup.
func _on_free_skills_toggled(button_pressed: bool) -> void:
	GameSettings.debug_free_skills = button_pressed
	SignalBus.mana_changed.emit(RunState.mana_pool)

func _on_minimap_size_changed(value: float) -> void:
	_apply_minimap_size(value)


## Resizes the minimap AND the container holding it.
##
## Setting only the map's minimum size is what produced the two mismatched frames: the
## container is pinned by its anchors and does not grow, so the ColorRect enforced its own
## minimum and overflowed while its backdrop - which has no minimum of its own - stayed at
## the old size. Moving the container's offsets is what actually resizes both of them.
func _apply_minimap_size(side: float) -> void:
	if minimap == null or minimap_container == null:
		return
	minimap.custom_minimum_size = Vector2(side, side)
	var margin_x: float = float(minimap_container.get_theme_constant("margin_right"))
	var margin_y: float = float(minimap_container.get_theme_constant("margin_bottom"))
	minimap_container.offset_left = -(side + margin_x)
	minimap_container.offset_top = -(side + margin_y)
	_refresh_minimap_corners()

func _setup_graphics_settings() -> void:
	quality_preset_option.clear()
	quality_preset_option.add_item("Low", GraphicsSettings.Preset.LOW)
	quality_preset_option.add_item("Medium", GraphicsSettings.Preset.MEDIUM)
	quality_preset_option.add_item("High", GraphicsSettings.Preset.HIGH)
	quality_preset_option.add_item("Custom", GraphicsSettings.Preset.CUSTOM)

	anti_aliasing_option.clear()
	anti_aliasing_option.add_item("Off", 0)
	anti_aliasing_option.add_item("MSAA 2x", 1)
	anti_aliasing_option.add_item("MSAA 4x", 2)

	renderer_option.clear()
	renderer_option.add_item("Forward+ (best visuals)", 0)
	renderer_option.add_item("Mobile (balanced)", 1)
	renderer_option.add_item("Compatibility (weak / integrated GPUs)", 2)

	_applying_preset = true
	quality_preset_option.select(GraphicsSettings.preset)
	render_scale_slider.value = GraphicsSettings.render_scale
	shadows_checkbox.button_pressed = GraphicsSettings.shadows_enabled
	anti_aliasing_option.select(GraphicsSettings.msaa_level)
	glow_checkbox.button_pressed = GraphicsSettings.glow_enabled
	vsync_checkbox.button_pressed = GraphicsSettings.vsync_enabled
	show_fps_checkbox.button_pressed = GraphicsSettings.show_fps
	fps_label.visible = GraphicsSettings.show_fps
	var current_method: String = GraphicsSettings.pending_rendering_method if GraphicsSettings.pending_rendering_method != "" else GraphicsSettings.active_rendering_method
	var method_idx: int = RENDERER_METHODS.find(current_method)
	renderer_option.select(maxi(method_idx, 0))
	_applying_preset = false
	_update_restart_notice()

	free_skills_checkbox.button_pressed = GameSettings.debug_free_skills
	free_skills_checkbox.toggled.connect(_on_free_skills_toggled)

	quality_preset_option.item_selected.connect(_on_quality_preset_selected)
	render_scale_slider.value_changed.connect(_on_render_scale_changed)
	shadows_checkbox.toggled.connect(_on_shadows_toggled)
	anti_aliasing_option.item_selected.connect(_on_anti_aliasing_selected)
	glow_checkbox.toggled.connect(_on_glow_toggled)
	vsync_checkbox.toggled.connect(_on_vsync_toggled)
	show_fps_checkbox.toggled.connect(_on_show_fps_toggled)
	renderer_option.item_selected.connect(_on_renderer_selected)
	apply_restart_btn.pressed.connect(_on_apply_restart_pressed)

func _mark_custom_preset() -> void:
	if _applying_preset:
		return
	GraphicsSettings.preset = GraphicsSettings.Preset.CUSTOM
	quality_preset_option.select(GraphicsSettings.Preset.CUSTOM)

func _update_restart_notice() -> void:
	restart_required_label.visible = GraphicsSettings.restart_required

func _on_quality_preset_selected(idx: int) -> void:
	var p: int = quality_preset_option.get_item_id(idx)
	if p == GraphicsSettings.Preset.CUSTOM:
		return
	_applying_preset = true
	GraphicsSettings.apply_preset(p)
	render_scale_slider.value = GraphicsSettings.render_scale
	shadows_checkbox.button_pressed = GraphicsSettings.shadows_enabled
	anti_aliasing_option.select(GraphicsSettings.msaa_level)
	glow_checkbox.button_pressed = GraphicsSettings.glow_enabled
	var method_idx: int = RENDERER_METHODS.find(GraphicsSettings.pending_rendering_method)
	renderer_option.select(maxi(method_idx, 0))
	_applying_preset = false
	_update_restart_notice()

func _on_render_scale_changed(value: float) -> void:
	GraphicsSettings.apply_render_scale(value)
	_mark_custom_preset()

func _on_shadows_toggled(button_pressed: bool) -> void:
	GraphicsSettings.apply_shadows(button_pressed)
	_mark_custom_preset()

func _on_anti_aliasing_selected(idx: int) -> void:
	GraphicsSettings.apply_msaa(idx)
	_mark_custom_preset()

func _on_glow_toggled(button_pressed: bool) -> void:
	GraphicsSettings.apply_glow(button_pressed)
	_mark_custom_preset()

func _on_vsync_toggled(button_pressed: bool) -> void:
	GraphicsSettings.apply_vsync(button_pressed)
	_mark_custom_preset()

func _on_show_fps_toggled(button_pressed: bool) -> void:
	GraphicsSettings.set_show_fps(button_pressed)
	fps_label.visible = button_pressed

func _on_renderer_selected(idx: int) -> void:
	GraphicsSettings.set_pending_rendering_method(RENDERER_METHODS[idx])
	_mark_custom_preset()
	_update_restart_notice()

func _on_apply_restart_pressed() -> void:
	GraphicsSettings.quit_to_apply_restart()

func _on_at_base_changed(is_at_base: bool) -> void:
	if interact_label:
		interact_label.text = "Press [E] to Manage Base"
		interact_label.visible = is_at_base

## Everything that belongs to PLAYING, as opposed to the panels that sit over the game.
##
## Listed rather than derived from the Control's children because the exceptions are the
## whole point: SettingsPanel, SettingsBackdrop and GameOverPanel are children of the same
## node, and hiding those along with the rest would hide the menu just opened. The FPS
## counter is left alone too - it is a diagnostic overlay, not part of the game's readout.
const GAMEPLAY_HUD_PATHS: Array[String] = [
	"Control/MarginContainer",
	"Control/PlayerHealthBar",
	"Control/HotbarContainer",
	"Control/XPBar",
	"Control/Crosshair",
	"Control/MinimapContainer",
	"Control/InteractLabel",
]


func _on_menu_opened(menu: String, is_open: bool) -> void:
	if is_open:
		_open_menus[menu] = true
	else:
		_open_menus.erase(menu)
	_refresh_gameplay_hud()


## Puts the gameplay HUD away while any menu is up and brings it back when the last one
## closes.
##
## Restores by remembering what it hid rather than by showing everything: several of these
## are conditionally visible in normal play - the interact prompt, the wave panel, the
## minimap the settings can switch off - and a blanket show() would turn all of them on.
func _refresh_gameplay_hud() -> void:
	if _open_menus.is_empty():
		for node: CanvasItem in _hidden_for_menu:
			if is_instance_valid(node):
				node.visible = true
		_hidden_for_menu.clear()
		return
	# Already hidden: a second menu opening on top of the first must not re-record an
	# empty set and lose what the first one put away.
	if not _hidden_for_menu.is_empty():
		return
	var gameplay: Array[CanvasItem] = []
	for path: String in GAMEPLAY_HUD_PATHS:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node != null:
			gameplay.append(node)
	# Built in code rather than authored in hud.tscn, so these two have no path to list.
	if _wave_panel:
		gameplay.append(_wave_panel)
	if _warning_panel:
		gameplay.append(_warning_panel)
	for node: CanvasItem in gameplay:
		if node.visible:
			node.visible = false
			_hidden_for_menu.append(node)


func _on_interact_prompt_changed(text: String, visible: bool) -> void:
	if interact_label:
		interact_label.text = text
		interact_label.visible = visible

func _update_hotbar_display(active_idx: int) -> void:
	for i in range(_hotbar_slots.size()):
		var slot = _hotbar_slots[i]
		if not slot:
			continue
			
		var num_label: Label = slot.get_node_or_null("Num") as Label
		var icon: TextureRect = slot.get_node_or_null("Icon") as TextureRect
		var spell_id: String = _player._get_spell_id_for_slot(i) if _player and _player.has_method("_get_spell_id_for_slot") else ""
		if icon:
			var icon_path: String = SpellDatabase.get_icon_path(spell_id)
			icon.texture = load(icon_path) as Texture2D if icon_path != "" else null
		
		var sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		
		var is_unlocked = false
		if _player and _player.has_method("is_spell_unlocked"):
			is_unlocked = _player.is_spell_unlocked(i)
			
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

## Gives every slot a rounded icon that covers the whole square.
##
## The icon is a DIRECT child of the PanelContainer rather than a VBox row: a
## PanelContainer stretches its direct children to fill, so this is what makes the icon
## the size of the slot. It goes in at index 0 so CooldownOverlay still draws over it.
func _ensure_hotbar_icons() -> void:
	for slot: PanelContainer in _hotbar_slots:
		if slot.get_node_or_null("Icon") != null:
			continue
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# SCALE, not KEEP_ASPECT_CENTERED: the slot is square and so are the spell icons,
		# so scaling fills it edge to edge instead of leaving a letterboxed margin.
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.material = IconStyle.rounded_material()
		slot.add_child(icon)
		slot.move_child(icon, 0)

## Squares every slot and leaves exactly one thing written on it: the key that fires it,
## in the bottom-left corner.
##
## Runs after the slots are duplicated, so it covers the five authored in hud.tscn and
## the five built at runtime alike.
##
## The number has to MOVE rather than just be restyled. It used to be a VBox row sharing
## the slot's height with the icon, next to a second row for the spell's rank, and an
## empty Label still reserves a full line - together that is what kept the icon small and
## the slot taller than it is wide. Reparenting the number onto the slot makes it an
## overlay instead: PanelContainer stretches a direct child to fill, so aligning it into a
## corner parks it over the icon without occupying any layout space at all.
##
## The rank row is freed rather than reparented. The icon and the key are the whole
## readout now; rank lives in the skill tree, which is where it is chosen.
func _lay_out_hotbar_slots() -> void:
	for slot: PanelContainer in _hotbar_slots:
		slot.custom_minimum_size = Vector2(HOTBAR_SLOT_SIZE, HOTBAR_SLOT_SIZE)
		var vbox: VBoxContainer = slot.get_node_or_null("VBox") as VBoxContainer
		if vbox == null:
			continue
		var num_label: Label = vbox.get_node_or_null("Num") as Label
		if num_label != null:
			vbox.remove_child(num_label)
			num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			num_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# The number sits ON the artwork now that the icon covers the whole slot, so
			# it carries its own outline rather than relying on the slot's background to
			# separate it from whatever is behind it.
			num_label.add_theme_constant_override("outline_size", 4)
			num_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
			slot.add_child(num_label)
		vbox.queue_free()


func _setup_mana_icons() -> void:
	var mana_labels: Array[Label] = [mana_label_w, mana_label_u, mana_label_b, mana_label_r, mana_label_g]
	var colors: Array[String] = ["white", "blue", "black", "red", "green"]
	for index: int in range(mana_labels.size()):
		var label: Label = mana_labels[index]
		var parent: HBoxContainer = label.get_parent() as HBoxContainer
		var icon := TextureRect.new()
		icon.name = "ManaIcon" + colors[index].capitalize()
		icon.custom_minimum_size = Vector2(24.0, 24.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(SpellDatabase.get_icon_path(colors[index])) as Texture2D
		icon.material = IconStyle.rounded_material()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(icon)
		parent.move_child(icon, label.get_index())

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
	_wave_panel = wave_panel
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
	# Hidden until asked for. _on_wave_state_changed keeps writing to the labels either
	# way, so the readout is already current the moment it is pulled up.
	wave_panel.hide()

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

## True while the Upkeep panel owns the mouse, so Escape does not open the settings
## panel underneath it.
var _upkeep_open: bool = false


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


## Levels are shared, so this fires for everyone at once - worth announcing on the same
## banner lane warnings use rather than burying in a corner.
func _on_team_level_changed(level: int, levels_gained: int) -> void:
	if levels_gained <= 0:
		return
	var points: String = "+%d skill point%s" % [levels_gained, "" if levels_gained == 1 else "s"]
	SignalBus.lane_warning_requested.emit("", "LEVEL %d  -  %s" % [level, points], Color(1.0, 0.85, 0.4))
