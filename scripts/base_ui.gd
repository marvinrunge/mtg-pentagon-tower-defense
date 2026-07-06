extends Control
class_name BaseUI

@onready var myr_list_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/MyrListContainer
@onready var build_btn: Button = $Panel/MarginContainer/VBoxContainer/BuildButton

@onready var wall_steel_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/SteelWallBtn
@onready var wall_swords_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/SwordsWallBtn
@onready var wall_frost_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/FrostWallBtn
@onready var wall_bone_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/BoneWallBtn
@onready var wall_fire_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/FireWallBtn
@onready var wall_roots_btn: Button = $Panel/MarginContainer/VBoxContainer/WallContainer/RootsWallBtn

@onready var bone_restore_btn: Button = $Panel/MarginContainer/VBoxContainer/WallActionsContainer/BoneRestoreBtn
@onready var fire_wave_btn: Button = $Panel/MarginContainer/VBoxContainer/WallActionsContainer/FireWaveBtn

var main_controller: Node3D

func _ready() -> void:
	hide()
	build_btn.pressed.connect(_on_build_pressed)
	
	wall_steel_btn.pressed.connect(func(): _build_wall("Colorless", {"Colorless": 1}))
	wall_swords_btn.pressed.connect(func(): _build_wall("White", {"Colorless": 3, "White": 1}))
	wall_frost_btn.pressed.connect(func(): _build_wall("Blue", {"Colorless": 1, "Blue": 2}))
	wall_bone_btn.pressed.connect(func(): _build_wall("Black", {"Colorless": 2, "Black": 1}))
	wall_fire_btn.pressed.connect(func(): _build_wall("Red", {"Colorless": 1, "Red": 2}))
	wall_roots_btn.pressed.connect(func(): _build_wall("Green", {"Colorless": 1, "Green": 1}))
	
	bone_restore_btn.pressed.connect(_on_bone_restore)
	fire_wave_btn.pressed.connect(_on_fire_wave)

func open(main_ref: Node3D) -> void:
	main_controller = main_ref
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_ui()

func close() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()

func refresh_ui() -> void:
	if not main_controller:
		return
		
	# Clear list
	for child in myr_list_container.get_children():
		child.queue_free()
		
	var active_myrs = get_tree().get_nodes_in_group("myrs")
	
	build_btn.text = "Build Myr (Cost: 2 Any Mana) - Built: " + str(active_myrs.size())
	var can_afford = false
	var total = 0
	for c in main_controller.mana_pool.values():
		total += c
	build_btn.disabled = total < 2
		
	# Update Wall Buttons
	wall_steel_btn.disabled = not main_controller.can_afford({"Colorless": 1})
	wall_swords_btn.disabled = not main_controller.can_afford({"Colorless": 3, "White": 1})
	wall_frost_btn.disabled = not main_controller.can_afford({"Colorless": 1, "Blue": 2})
	wall_bone_btn.disabled = not main_controller.can_afford({"Colorless": 2, "Black": 1})
	wall_fire_btn.disabled = not main_controller.can_afford({"Colorless": 1, "Red": 2})
	wall_roots_btn.disabled = not main_controller.can_afford({"Colorless": 1, "Green": 1})
	
	# Update Actions
	bone_restore_btn.visible = false
	fire_wave_btn.visible = false
	if main_controller.current_wall:
		if main_controller.current_wall.wall_type == "Black" and main_controller.current_wall.is_dead:
			bone_restore_btn.visible = true
			bone_restore_btn.disabled = bone_restore_timer > 0
			if bone_restore_timer > 0:
				bone_restore_btn.text = "Restore Bone Wall (" + str(int(bone_restore_timer)) + "s)"
			else:
				bone_restore_btn.text = "Restore Bone Wall"
		elif main_controller.current_wall.wall_type == "Red" and not main_controller.current_wall.is_dead:
			fire_wave_btn.visible = true
			fire_wave_btn.disabled = not main_controller.can_afford({"Red": 1})
		
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

func _on_build_pressed() -> void:
	if main_controller and main_controller.spend_any_mana(2):
		var myr_scene = preload("res://scenes/myr.tscn")
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

var bone_restore_timer: float = 0.0
func _process(delta: float) -> void:
	if bone_restore_timer > 0:
		bone_restore_timer -= delta
		if bone_restore_timer <= 0:
			bone_restore_timer = 0
			if main_controller and main_controller.current_wall and main_controller.current_wall.wall_type == "Black":
				main_controller.revive_bone_wall()
		if visible:
			refresh_ui()

func _build_wall(type: String, cost: Dictionary) -> void:
	if main_controller and main_controller.spend_mana_cost(cost):
		main_controller.build_wall(type)
		refresh_ui()

func _on_bone_restore() -> void:
	# Starts the 15s restore timer
	bone_restore_timer = 15.0
	refresh_ui()

func _on_fire_wave() -> void:
	if main_controller and main_controller.spend_mana_cost({"Red": 1}):
		main_controller.trigger_red_wall()
		refresh_ui()
