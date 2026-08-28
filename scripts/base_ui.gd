extends Control
class_name BaseUI

@onready var myr_list_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/MyrListContainer
@onready var build_btn: Button = $Panel/MarginContainer/VBoxContainer/BuildButton

var main_controller: Node3D
var skill_list_container: VBoxContainer

func _ready() -> void:
	hide()
	build_btn.pressed.connect(_on_build_pressed)
	
	# Dynamically add skill unlock UI
	var sep = HSeparator.new()
	$Panel/MarginContainer/VBoxContainer.add_child(sep)
	
	var title = Label.new()
	title.text = "Unlock Skills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	$Panel/MarginContainer/VBoxContainer.add_child(title)
	
	skill_list_container = VBoxContainer.new()
	$Panel/MarginContainer/VBoxContainer.add_child(skill_list_container)

func open(main_ref: Node3D) -> void:
	main_controller = main_ref
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_ui()
	build_btn.grab_focus()

func close() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func refresh_ui() -> void:
	if not main_controller:
		return
		
	# Clear list
	for child in myr_list_container.get_children():
		child.queue_free()
		
	var active_myrs = get_tree().get_nodes_in_group("myrs")
	
	build_btn.text = "Build Myr (Cost: %d Any Mana) - Built: %d" % [GameSettings.myr_mana_cost, active_myrs.size()]
	var total = 0
	for c in main_controller.mana_pool.values():
		total += c
	build_btn.disabled = total < GameSettings.myr_mana_cost
		
	# Create entries for each Myr
	for i in range(active_myrs.size()):
		var myr = active_myrs[i]
		var hbox = HBoxContainer.new()
		
		var lbl = Label.new()
		lbl.text = "Myr " + str(i + 1) + "  "
		hbox.add_child(lbl)
		
		var current_lane = myr.lane_index
		
		var w_btn = Button.new()
		w_btn.text = "W"
		w_btn.add_theme_color_override("font_color", Color.WHITE)
		if current_lane == 0: w_btn.disabled = true
		w_btn.pressed.connect(func(): _assign(myr, 0))
		hbox.add_child(w_btn)
		
		var u_btn = Button.new()
		u_btn.text = "U"
		u_btn.add_theme_color_override("font_color", Color(0.3,0.5,1))
		if current_lane == 1: u_btn.disabled = true
		u_btn.pressed.connect(func(): _assign(myr, 1))
		hbox.add_child(u_btn)
		
		var b_btn = Button.new()
		b_btn.text = "B"
		b_btn.add_theme_color_override("font_color", Color.GRAY)
		if current_lane == 2: b_btn.disabled = true
		b_btn.pressed.connect(func(): _assign(myr, 2))
		hbox.add_child(b_btn)
		
		var r_btn = Button.new()
		r_btn.text = "R"
		r_btn.add_theme_color_override("font_color", Color.RED)
		if current_lane == 3: r_btn.disabled = true
		r_btn.pressed.connect(func(): _assign(myr, 3))
		hbox.add_child(r_btn)
		
		var g_btn = Button.new()
		g_btn.text = "G"
		g_btn.add_theme_color_override("font_color", Color.GREEN)
		if current_lane == 4: g_btn.disabled = true
		g_btn.pressed.connect(func(): _assign(myr, 4))
		hbox.add_child(g_btn)
		
		myr_list_container.add_child(hbox)
		
	# Open Skill Tree Button
	for child in skill_list_container.get_children():
		child.queue_free()
		
	var st_btn = Button.new()
	st_btn.custom_minimum_size = Vector2(0, 45)
	st_btn.text = "OPEN MTG SKILL TREE (Press 'K')"
	st_btn.pressed.connect(_open_skill_tree)
	skill_list_container.add_child(st_btn)

func _open_skill_tree() -> void:
	var st = get_tree().current_scene.get_node_or_null("SkillTree")
	if st:
		close()
		st.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		st.update_ui()

func _on_build_pressed() -> void:
	if main_controller and main_controller.spend_any_mana(GameSettings.myr_mana_cost):
		var myr_scene = preload("res://scenes/misc/myr.tscn")
		var myr = myr_scene.instantiate()
		myr.position = main_controller.crystal_anchor.global_position + Vector3(0, 0.5, 0)
		myr.set_meta("target_crystal", main_controller.crystal_anchor)
		main_controller.add_child(myr)
		refresh_ui()

func _assign(myr: Node3D, lane: int) -> void:
	if main_controller:
		var source = main_controller.mana_sources[lane]
		if myr.has_method("assign_lane"):
			myr.assign_lane(lane, source)
		refresh_ui()
