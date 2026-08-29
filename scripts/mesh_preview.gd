extends Node3D
## MeshPreview - Comprehensive 3D Model & Animation Inspector
## Displays all 25 animated models (5 Myrs, 5 Melee, 5 Ranged, 5 Mages, 5 Bosses)
## with individual focus camera, animation cycling, speed control, and MTG color theming.

const MTG_COLORS: Dictionary = {
	"White": Color(0.95, 0.90, 0.65),
	"Blue":  Color(0.20, 0.60, 1.00),
	"Black": Color(0.65, 0.35, 0.85),
	"Red":   Color(0.95, 0.25, 0.20),
	"Green": Color(0.25, 0.85, 0.35),
}

const CATEGORIES: Array[String] = ["Myrs", "Melee", "Ranged", "Mage", "Bosses"]

# All 25 model definitions in 5x5 grid (Columns: White, Blue, Black, Red, Green)
const MODEL_REGISTRY: Array[Dictionary] = [
	# --- Row 0: Myrs ---
	{"name": "Gold Myr", "cat": "Myrs", "color": "White", "scene": "res://scenes/myrs/gold_myr.tscn", "scale": 100.0, "pbr": true},
	{"name": "Silver Myr", "cat": "Myrs", "color": "Blue", "scene": "res://scenes/myrs/silver_myr.tscn", "scale": 100.0, "pbr": true},
	{"name": "Leaden Myr", "cat": "Myrs", "color": "Black", "scene": "res://scenes/myrs/leaden_myr.tscn", "scale": 100.0, "pbr": true},
	{"name": "Iron Myr", "cat": "Myrs", "color": "Red", "scene": "res://scenes/myrs/iron_myr.tscn", "scale": 100.0, "pbr": true},
	{"name": "Copper Myr", "cat": "Myrs", "color": "Green", "scene": "res://scenes/myrs/copper_myr.tscn", "scale": 100.0, "pbr": true},

	# --- Row 1: Melee Enemies ---
	{"name": "Human Melee", "cat": "Melee", "color": "White", "scene": "res://scenes/melee/human_melee.tscn", "scale": 90.0, "pbr": false},
	{"name": "Merfolk Melee", "cat": "Melee", "color": "Blue", "scene": "res://scenes/melee/merfolk_melee.tscn", "scale": 90.0, "pbr": false},
	{"name": "Zombie Melee", "cat": "Melee", "color": "Black", "scene": "res://scenes/melee/zombie_melee.tscn", "scale": 90.0, "pbr": false},
	{"name": "Goblin Melee", "cat": "Melee", "color": "Red", "scene": "res://scenes/melee/goblin_melee.tscn", "scale": 80.0, "pbr": false},
	{"name": "Elf Melee", "cat": "Melee", "color": "Green", "scene": "res://scenes/melee/elf_melee.tscn", "scale": 90.0, "pbr": false},

	# --- Row 2: Ranged Enemies ---
	{"name": "Human Ranged", "cat": "Ranged", "color": "White", "scene": "res://scenes/ranged/human_ranged.tscn", "scale": 90.0, "pbr": false},
	{"name": "Merfolk Ranged", "cat": "Ranged", "color": "Blue", "scene": "res://scenes/ranged/merfolk_ranged.tscn", "scale": 90.0, "pbr": false},
	{"name": "Zombie Ranged", "cat": "Ranged", "color": "Black", "scene": "res://scenes/ranged/zombie_ranged.tscn", "scale": 90.0, "pbr": false},
	{"name": "Goblin Ranged", "cat": "Ranged", "color": "Red", "scene": "res://scenes/ranged/goblin_ranged.tscn", "scale": 80.0, "pbr": false},
	{"name": "Elf Ranged", "cat": "Ranged", "color": "Green", "scene": "res://scenes/ranged/elf_ranged.tscn", "scale": 90.0, "pbr": false},

	# --- Row 3: Mage Enemies ---
	{"name": "Human Mage", "cat": "Mage", "color": "White", "scene": "res://scenes/mage/human_mage.tscn", "scale": 100.0, "pbr": false},
	{"name": "Merfolk Mage", "cat": "Mage", "color": "Blue", "scene": "res://scenes/mage/merfolk_mage.tscn", "scale": 100.0, "pbr": false},
	{"name": "Zombie Mage", "cat": "Mage", "color": "Black", "scene": "res://scenes/mage/zombie_mage.tscn", "scale": 100.0, "pbr": false},
	{"name": "Goblin Mage", "cat": "Mage", "color": "Red", "scene": "res://scenes/mage/goblin_mage.tscn", "scale": 85.0, "pbr": false},
	{"name": "Elf Mage", "cat": "Mage", "color": "Green", "scene": "res://scenes/mage/elf_mage.tscn", "scale": 100.0, "pbr": false},

	# --- Row 4: Bosses ---
	{"name": "White Paladin (Boss)", "cat": "Bosses", "color": "White", "scene": "res://scenes/bosses/white_paladin.tscn", "scale": 150.0, "pbr": false},
	{"name": "Frost Giant (Boss)", "cat": "Bosses", "color": "Blue", "scene": "res://scenes/bosses/frost_giant.tscn", "scale": 170.0, "pbr": false},
	{"name": "Zombie Lord (Boss)", "cat": "Bosses", "color": "Black", "scene": "res://scenes/bosses/zombie_lord.tscn", "scale": 160.0, "pbr": false},
	{"name": "Fire Giant (Boss)", "cat": "Bosses", "color": "Red", "scene": "res://scenes/bosses/fire_giant.tscn", "scale": 160.0, "pbr": false},
	{"name": "Treant (Boss)", "cat": "Bosses", "color": "Green", "scene": "res://scenes/bosses/treant.tscn", "scale": 180.0, "pbr": false},
]

# Spacing settings for layout
const SPACING_X: float = 3.2
const SPACING_Z: float = 4.0

# State
var _spawned_entries: Array[Dictionary] = []
var _current_focus_index: int = 0 # 0..24, or -1 for overview
var _is_overview: bool = false

# Camera & controls
@onready var _cam_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _models_container: Node3D = $ModelsContainer
@onready var _ui_container: CanvasLayer = $UI

# UI nodes
@onready var _model_select_opt: OptionButton = $UI/TopPanel/HBox/ModelSelectOpt
@onready var _anim_select_opt: OptionButton = $UI/BottomPanel/Card/VBox/AnimRow/AnimSelectOpt
@onready var _model_title_lbl: Label = $UI/BottomPanel/Card/VBox/TitleRow/ModelTitleLbl
@onready var _model_meta_lbl: Label = $UI/BottomPanel/Card/VBox/TitleRow/ModelMetaLbl
@onready var _speed_slider: HSlider = $UI/BottomPanel/Card/VBox/SpeedRow/SpeedSlider
@onready var _speed_lbl: Label = $UI/BottomPanel/Card/VBox/SpeedRow/SpeedLbl
@onready var _pause_btn: Button = $UI/BottomPanel/Card/VBox/AnimRow/PauseBtn

var _target_cam_pos: Vector3 = Vector3.ZERO
var _cam_pos: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = -15.0
var _target_yaw: float = 0.0
var _target_pitch: float = -15.0
var _zoom: float = 4.5
var _target_zoom: float = 4.5
var _is_dragging: bool = false
var _is_panning: bool = false
var _anim_speed: float = 1.0
var _is_paused: bool = false


func _ready() -> void:
	_spawn_all_models()
	_populate_ui()
	_focus_model(0, true)


func _spawn_all_models() -> void:
	# Clean up previous models if any
	for c: Node in _models_container.get_children():
		c.queue_free()
	_spawned_entries.clear()

	for i: int in range(MODEL_REGISTRY.size()):
		var def: Dictionary = MODEL_REGISTRY[i]
		var col_idx: int = i % 5      # 0..4 (White, Blue, Black, Red, Green)
		var row_idx: int = i / 5      # 0..4 (Myr, Melee, Ranged, Mage, Boss)

		var pos_x: float = (float(col_idx) - 2.0) * SPACING_X
		var pos_z: float = (float(row_idx) - 2.0) * SPACING_Z

		var wrapper: Node3D = Node3D.new()
		wrapper.name = def["name"].replace(" ", "_").replace("(", "").replace(")", "")
		wrapper.position = Vector3(pos_x, 0.0, pos_z)
		_models_container.add_child(wrapper)

		# Add pedestal
		var ped_mesh: CylinderMesh = CylinderMesh.new()
		ped_mesh.top_radius = 1.0
		ped_mesh.bottom_radius = 1.1
		ped_mesh.height = 0.1
		var ped_inst: MeshInstance3D = MeshInstance3D.new()
		ped_inst.mesh = ped_mesh
		ped_inst.position = Vector3(0.0, -0.05, 0.0)

		var ped_mat: StandardMaterial3D = StandardMaterial3D.new()
		var col_tint: Color = MTG_COLORS.get(def["color"], Color.GRAY)
		ped_mat.albedo_color = Color(0.12, 0.13, 0.16)
		ped_mat.roughness = 0.6
		ped_mat.emission_enabled = true
		ped_mat.emission = col_tint
		ped_mat.emission_energy_multiplier = 0.4
		ped_inst.material_override = ped_mat
		wrapper.add_child(ped_inst)

		# Add 3D text label above pedestal
		var lbl: Label3D = Label3D.new()
		lbl.text = def["name"]
		lbl.font_size = 18
		lbl.outline_size = 6
		lbl.modulate = col_tint
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = Vector3(0.0, 2.2 if row_idx == 4 else 1.9, 0.0)
		wrapper.add_child(lbl)

		# Instantiate character scene
		var scn: PackedScene = load(def["scene"]) as PackedScene
		var inst: Node3D = null
		var anim_player: AnimationPlayer = null
		if scn:
			inst = scn.instantiate() as Node3D
			var s: float = float(def["scale"])
			inst.scale = Vector3(s, s, s)
			wrapper.add_child(inst)
			anim_player = _find_animation_player(inst)
			_ground_instance(inst)

		# Record entry
		var entry: Dictionary = {
			"index": i,
			"def": def,
			"wrapper": wrapper,
			"instance": inst,
			"anim_player": anim_player,
			"label": lbl,
			"world_pos": wrapper.global_position,
		}
		_spawned_entries.append(entry)

		# Play default walk/run/first animation
		if anim_player:
			var default_clip: String = _pick_default_anim(anim_player)
			if default_clip != "":
				anim_player.play(default_clip)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var result: AnimationPlayer = _find_animation_player(child)
		if result != null:
			return result
	return null


func _find_body_mesh_instance(root: Node) -> MeshInstance3D:
	# Find the Skeleton3D first, then only look at its direct children so
	# attached props/weapons (nested under BoneAttachment3D) are ignored.
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		return null
	for child: Node in skel.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var result: Skeleton3D = _find_skeleton(child)
		if result != null:
			return result
	return null


func _ground_instance(inst: Node3D) -> void:
	# Some imported models have their lowest vertex offset from y=0 in local
	# space; at the preview's large uniform scale that offset becomes a
	# visible sink into (or float above) the pedestal. Measure the body
	# mesh's bind-pose AABB in world space and shift the instance so its
	# lowest point rests exactly on the pedestal (wrapper's y=0).
	var mesh_inst: MeshInstance3D = _find_body_mesh_instance(inst)
	if mesh_inst == null:
		return

	var wrapper: Node3D = inst.get_parent() as Node3D
	var local_aabb: AABB = mesh_inst.get_aabb()
	var xform: Transform3D = mesh_inst.global_transform

	var min_y: float = INF
	for corner_idx: int in range(8):
		var corner: Vector3 = local_aabb.position + Vector3(
			local_aabb.size.x * float(corner_idx & 1),
			local_aabb.size.y * float((corner_idx >> 1) & 1),
			local_aabb.size.z * float((corner_idx >> 2) & 1)
		)
		var world_corner: Vector3 = xform * corner
		min_y = min(min_y, world_corner.y)

	if is_finite(min_y):
		var wrapper_y: float = wrapper.global_position.y if wrapper else 0.0
		inst.position.y -= (min_y - wrapper_y)


func _pick_default_anim(player: AnimationPlayer) -> String:
	var lib_names: PackedStringArray = player.get_animation_library_list()
	var fallback: String = ""

	for lib_name: StringName in lib_names:
		var lib: AnimationLibrary = player.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			var full_name: String = (str(lib_name) + "/" + str(anim_name)) if str(lib_name) != "" else str(anim_name)
			if fallback == "":
				fallback = full_name
			# Prefer standard locomotion
			var s_anim: String = str(anim_name).to_lower()
			if s_anim in ["walk", "walk_loaded", "run", "idle"]:
				return full_name

	return fallback


func _get_all_animations(player: AnimationPlayer) -> Array[String]:
	var list: Array[String] = []
	if player == null:
		return list
	var lib_names: PackedStringArray = player.get_animation_library_list()
	for lib_name: StringName in lib_names:
		var lib: AnimationLibrary = player.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			var full_name: String = (str(lib_name) + "/" + str(anim_name)) if str(lib_name) != "" else str(anim_name)
			list.append(full_name)
	return list


func _populate_ui() -> void:
	_model_select_opt.clear()
	for i: int in range(MODEL_REGISTRY.size()):
		var def: Dictionary = MODEL_REGISTRY[i]
		var tag: String = "[PBR] " if def["pbr"] else ""
		_model_select_opt.add_item("%02d. %s%s (%s)" % [i + 1, tag, def["name"], def["cat"]], i)

	_model_select_opt.item_selected.connect(func(idx: int) -> void:
		_focus_model(idx, false)
	)

	_anim_select_opt.item_selected.connect(func(idx: int) -> void:
		var clip_name: String = _anim_select_opt.get_item_text(idx)
		var cur: Dictionary = _spawned_entries[_current_focus_index]
		if cur["anim_player"]:
			cur["anim_player"].play(clip_name)
	)

	_speed_slider.value_changed.connect(func(val: float) -> void:
		_anim_speed = val
		_speed_lbl.text = "Speed: %.1fx" % val
		_apply_speed_to_all()
	)

	_pause_btn.pressed.connect(func() -> void:
		_is_paused = not _is_paused
		_pause_btn.text = "Resume" if _is_paused else "Pause"
		_apply_speed_to_all()
	)


func _focus_model(index: int, instant: bool = false) -> void:
	if index < 0 or index >= _spawned_entries.size():
		return
	_current_focus_index = index
	_is_overview = false
	_model_select_opt.select(index)

	var entry: Dictionary = _spawned_entries[index]
	var def: Dictionary = entry["def"]
	var target_pt: Vector3 = entry["world_pos"] + Vector3(0.0, 0.9, 0.0)

	_target_cam_pos = target_pt
	_target_zoom = 3.8 if def["cat"] != "Bosses" else 5.2
	_target_pitch = -12.0
	_target_yaw = 0.0

	if instant:
		_cam_pos = _target_cam_pos
		_zoom = _target_zoom
		_pitch = _target_pitch
		_yaw = _target_yaw
		_cam_pivot.position = _cam_pos
		_camera.position.z = _zoom
		_cam_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0.0)

	# Update Card UI
	var col_tint: Color = MTG_COLORS.get(def["color"], Color.WHITE)
	_model_title_lbl.text = def["name"]
	_model_title_lbl.modulate = col_tint
	_model_meta_lbl.text = "Category: %s  |  Mana Color: %s  |  Scale: %dx%s" % [
		def["cat"],
		def["color"],
		int(def["scale"]),
		"  |  [PBR Textures: Albedo, Normal, Metallic, Roughness, Emission]" if def["pbr"] else ""
	]

	# Update Animations dropdown
	_anim_select_opt.clear()
	if entry["anim_player"]:
		var anims: Array[String] = _get_all_animations(entry["anim_player"])
		var current_anim: String = entry["anim_player"].current_animation
		for a_i: int in range(anims.size()):
			var a_name: String = anims[a_i]
			_anim_select_opt.add_item(a_name, a_i)
			if a_name == current_anim:
				_anim_select_opt.select(a_i)


func _focus_overview() -> void:
	_is_overview = true
	_target_cam_pos = Vector3(0.0, 0.0, 0.0)
	_target_zoom = 18.0
	_target_pitch = -40.0
	_target_yaw = 0.0
	_model_title_lbl.text = "— Pentagon Arena Overview (All 25 Models) —"
	_model_title_lbl.modulate = Color.WHITE
	_model_meta_lbl.text = "Click any model or use Left/Right/Up/Down arrows to focus | F: Toggle Overview"


func _apply_speed_to_all() -> void:
	var actual: float = 0.0 if _is_paused else _anim_speed
	for entry: Dictionary in _spawned_entries:
		if entry["anim_player"]:
			entry["anim_player"].speed_scale = actual


func _process(delta: float) -> void:
	# Smooth camera interpolation
	_cam_pos = _cam_pos.lerp(_target_cam_pos, delta * 8.0)
	_zoom = lerpf(_zoom, _target_zoom, delta * 8.0)
	_pitch = lerpf(_pitch, _target_pitch, delta * 10.0)
	_yaw = lerpf(_yaw, _target_yaw, delta * 10.0)

	_cam_pivot.position = _cam_pos
	_camera.position.z = _zoom
	_cam_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0.0)


func _input(event: InputEvent) -> void:
	# Mouse Orbit & Zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom - 0.4, 1.2, 35.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom + 0.4, 1.2, 35.0)

	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * 0.4
		_target_pitch = clampf(_target_pitch - mm.relative.y * 0.3, -80.0, 80.0)

	# Keyboard Controls
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		match key.keycode:
			KEY_LEFT, KEY_A:
				var next_idx: int = (_current_focus_index - 1 + _spawned_entries.size()) % _spawned_entries.size()
				_focus_model(next_idx)
			KEY_RIGHT, KEY_D:
				var next_idx: int = (_current_focus_index + 1) % _spawned_entries.size()
				_focus_model(next_idx)
			KEY_UP, KEY_W:
				# Move up one category row (minus 5)
				var next_idx: int = (_current_focus_index - 5 + _spawned_entries.size()) % _spawned_entries.size()
				_focus_model(next_idx)
			KEY_DOWN, KEY_S:
				# Move down one category row (plus 5)
				var next_idx: int = (_current_focus_index + 5) % _spawned_entries.size()
				_focus_model(next_idx)
			KEY_F, KEY_SPACE:
				if _is_overview:
					_focus_model(_current_focus_index)
				else:
					_focus_overview()
			KEY_R:
				_restart_current_animation()
			KEY_H:
				_ui_container.visible = not _ui_container.visible
			KEY_Q:
				get_tree().quit()


func _restart_current_animation() -> void:
	var cur: Dictionary = _spawned_entries[_current_focus_index]
	if cur["anim_player"]:
		cur["anim_player"].seek(0.0, true)
		cur["anim_player"].play()
