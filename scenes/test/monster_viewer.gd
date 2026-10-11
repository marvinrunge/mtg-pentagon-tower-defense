extends Node3D
## Animation viewer for the rigged beasts (assets/enemies/beasts/<name>/<name>.glb).
##
## Open scenes/test/monster_viewer.tscn and press F6. Every GLB found under MONSTER_DIR
## shows up in the list, so a new beast needs nothing but its folder.
##
## Controls: left-drag orbit, right/middle-drag pan, wheel zoom, F reframe,
## 1-9 pick clip, Space play/pause, Left/Right step one frame, L toggle loop.

const MONSTER_DIR := "res://assets/enemies/beasts"
## Clips that loop in game; everything else plays once and holds its last frame.
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "run"]
const FPS := 30.0

var _paths: Array[String] = []
var _instances: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []
var _current_clip := ""
var _speed := 1.0
var _loop_override := -1  # -1 = clip default, 0 = off, 1 = on

# camera orbit state
var _cam: Camera3D
var _target := Vector3(0, 0.6, 0)
var _yaw := deg_to_rad(-60.0)
var _pitch := deg_to_rad(-12.0)
var _dist := 4.0

# ui
var _monster_list: OptionButton
var _show_all: CheckBox
var _clip_box: VBoxContainer
var _play_btn: Button
var _loop_btn: CheckBox
var _speed_label: Label
var _timeline: HSlider
var _time_label: Label
var _info_label: Label
var _scrubbing := false


func _ready() -> void:
	_build_world()
	_build_ui()
	_paths = _find_monsters()
	for p in _paths:
		_monster_list.add_item(p.get_file().get_basename().capitalize())
	if _paths.is_empty():
		_info_label.text = "Keine GLBs in %s gefunden." % MONSTER_DIR
		return
	_load_selection()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.45, 0.58)
	mat.sky_horizon_color = Color(0.68, 0.7, 0.72)
	mat.ground_horizon_color = Color(0.68, 0.7, 0.72)
	mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	# checker floor: makes foot sliding and ground penetration easy to spot
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _checker_texture()
	fm.uv1_scale = Vector3(40, 40, 1)  # 1 m tiles
	fm.roughness = 0.95
	floor_mesh.material = fm
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	add_child(floor)

	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_update_camera()


func _checker_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var a := (((x >> 5) + (y >> 5)) & 1) == 0
			img.set_pixel(x, y, Color(0.42, 0.42, 0.4) if a else Color(0.32, 0.32, 0.31))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ monsters

func _find_monsters() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(MONSTER_DIR)
	if dir == null:
		return out
	for sub in dir.get_directories():
		var d := DirAccess.open(MONSTER_DIR.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			# exported builds list "x.glb.import" / "x.glb.remap" instead of "x.glb"
			var name := f.trim_suffix(".import").trim_suffix(".remap")
			if name.get_extension() == "glb":
				var p := MONSTER_DIR.path_join(sub).path_join(name)
				if not out.has(p):
					out.append(p)
	out.sort()
	return out


func _load_selection() -> void:
	for inst in _instances:
		inst.queue_free()
	_instances.clear()
	_players.clear()

	var paths: Array[String] = []
	if _show_all.button_pressed:
		paths.assign(_paths)
	else:
		paths.append(_paths[_monster_list.selected])
	var x := 0.0
	var gap := 0.6
	var widths: Array[float] = []
	var loaded: Array[Node3D] = []
	for p in paths:
		var scene := load(p) as PackedScene
		if scene == null:
			push_warning("Could not load %s" % p)
			continue
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		loaded.append(inst)
		widths.append(_bounds(inst).size.x)
	# lay them out side by side along X, centred on the origin
	var total := 0.0
	for w in widths:
		total += w
	total += gap * maxf(widths.size() - 1, 0)
	x = -total / 2.0
	for i in loaded.size():
		loaded[i].position.x = x + widths[i] / 2.0
		x += widths[i] + gap
		_instances.append(loaded[i])
		var ap := _find_player(loaded[i])
		if ap:
			_players.append(ap)
			ap.animation_finished.connect(_on_animation_finished)

	_rebuild_clip_buttons()
	_frame_all()
	var start := _current_clip if _has_clip(_current_clip) else _first_clip()
	if start != "":
		_play(start)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _clip_names() -> PackedStringArray:
	if _players.is_empty():
		return PackedStringArray()
	var names := _players[0].get_animation_list()
	var ordered := PackedStringArray()
	# game order first, then anything extra
	for c in ["idle", "walk", "run", "attack", "special", "hit", "knockback", "death"]:
		if names.has(c):
			ordered.append(c)
	for c in names:
		if not ordered.has(c) and c != "RESET":
			ordered.append(c)
	return ordered


func _has_clip(c: String) -> bool:
	return c != "" and _clip_names().has(c)


func _first_clip() -> String:
	var n := _clip_names()
	return n[0] if n.size() > 0 else ""


# ------------------------------------------------------------------ playback

func _clip_loops(clip: String) -> bool:
	if _loop_override >= 0:
		return _loop_override == 1
	return clip in LOOPING_CLIPS


func _play(clip: String) -> void:
	_current_clip = clip
	for ap in _players:
		if not ap.has_animation(clip):
			continue
		var anim := ap.get_animation(clip)
		anim.loop_mode = Animation.LOOP_LINEAR if _clip_loops(clip) else Animation.LOOP_NONE
		ap.speed_scale = _speed
		ap.play(clip, 0.0)
		ap.seek(0.0, true)
	_loop_btn.set_pressed_no_signal(_clip_loops(clip))
	_play_btn.text = "Pause"
	for b in _clip_box.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.name == clip)
	_update_info()


func _toggle_pause() -> void:
	if _players.is_empty():
		return
	var playing := _players[0].is_playing()
	for ap in _players:
		if playing:
			ap.pause()
		elif ap.current_animation == "" or (not _clip_loops(_current_clip) and ap.current_animation_position >= ap.current_animation_length - 0.001):
			ap.play(_current_clip, 0.0)
			ap.seek(0.0, true)
		else:
			ap.play()
	_play_btn.text = "Play" if playing else "Pause"


func _step(frames: int) -> void:
	for ap in _players:
		if ap.current_animation == "":
			continue
		ap.pause()
		var t := clampf(ap.current_animation_position + frames / FPS, 0.0, ap.current_animation_length)
		ap.seek(t, true)
	_play_btn.text = "Play"


func _seek_fraction(f: float) -> void:
	for ap in _players:
		if ap.current_animation == "":
			continue
		ap.seek(f * ap.current_animation_length, true)


func _on_animation_finished(_name: StringName) -> void:
	_play_btn.text = "Play"


func _process(_delta: float) -> void:
	if _players.is_empty() or _current_clip == "":
		return
	var ap := _players[0]
	var length := ap.current_animation_length if ap.current_animation != "" else 0.0
	var pos := ap.current_animation_position if ap.current_animation != "" else 0.0
	if not _scrubbing and length > 0.0:
		_timeline.set_value_no_signal(pos / length)
	_time_label.text = "%.2f / %.2f s   Frame %d / %d" % [pos, length, roundi(pos * FPS) + 1, roundi(length * FPS) + 1]


func _update_info() -> void:
	if _players.is_empty():
		return
	var ap := _players[0]
	var anim := ap.get_animation(_current_clip) if ap.has_animation(_current_clip) else null
	var names := []
	for p in (_paths if _show_all.button_pressed else [_paths[_monster_list.selected]]):
		names.append(p.get_file().get_basename())
	_info_label.text = "%s\nClip: %s  (%.2f s, %s)" % [
		", ".join(names), _current_clip, anim.length if anim else 0.0,
		"Loop" if _clip_loops(_current_clip) else "einmalig"]


# ------------------------------------------------------------------ camera

func _frame_all() -> void:
	var box := AABB()
	var first := true
	for inst in _instances:
		var b := _bounds(inst)
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	_target = box.get_center()
	var radius := box.size.length() * 0.5
	_dist = radius / sin(deg_to_rad(_cam.fov * 0.5)) * 0.9
	_update_camera()


func _update_camera() -> void:
	_pitch = clampf(_pitch, deg_to_rad(-85), deg_to_rad(85))
	_dist = clampf(_dist, 0.5, 60.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= mm.relative.x * 0.008
			_pitch += mm.relative.y * 0.008
			_update_camera()
		elif mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var b := _cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0015
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.9
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist /= 0.9
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE:
			_toggle_pause()
		elif k == KEY_LEFT:
			_step(-1)
		elif k == KEY_RIGHT:
			_step(1)
		elif k == KEY_F:
			_frame_all()
		elif k == KEY_L:
			_loop_btn.button_pressed = not _loop_btn.button_pressed
		elif k >= KEY_1 and k <= KEY_9:
			var names := _clip_names()
			var i := k - KEY_1
			if i < names.size():
				_play(names[i])


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(260, 0)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var title := Label.new()
	title.text = "Monster Viewer"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)

	_monster_list = OptionButton.new()
	_monster_list.item_selected.connect(func(_i: int) -> void: _load_selection())
	v.add_child(_monster_list)

	_show_all = CheckBox.new()
	_show_all.text = "Alle nebeneinander"
	_show_all.toggled.connect(func(_on: bool) -> void: _load_selection())
	v.add_child(_show_all)

	v.add_child(HSeparator.new())
	_clip_box = VBoxContainer.new()
	v.add_child(_clip_box)
	v.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	v.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "Pause"
	_play_btn.custom_minimum_size = Vector2(70, 0)
	_play_btn.pressed.connect(_toggle_pause)
	row.add_child(_play_btn)
	var back := Button.new()
	back.text = "<"
	back.tooltip_text = "Einen Frame zurück (Pfeil links)"
	back.pressed.connect(func() -> void: _step(-1))
	row.add_child(back)
	var fwd := Button.new()
	fwd.text = ">"
	fwd.tooltip_text = "Einen Frame vor (Pfeil rechts)"
	fwd.pressed.connect(func() -> void: _step(1))
	row.add_child(fwd)
	_loop_btn = CheckBox.new()
	_loop_btn.text = "Loop"
	_loop_btn.toggled.connect(func(on: bool) -> void:
		_loop_override = 1 if on else 0
		if _current_clip != "":
			for ap in _players:
				if ap.has_animation(_current_clip):
					ap.get_animation(_current_clip).loop_mode = Animation.LOOP_LINEAR if on else Animation.LOOP_NONE
		_update_info())
	row.add_child(_loop_btn)

	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.drag_started.connect(func() -> void:
		_scrubbing = true
		for ap in _players:
			ap.pause()
		_play_btn.text = "Play")
	_timeline.drag_ended.connect(func(_changed: bool) -> void: _scrubbing = false)
	_timeline.value_changed.connect(func(f: float) -> void:
		if _scrubbing:
			_seek_fraction(f))
	v.add_child(_timeline)
	_time_label = Label.new()
	v.add_child(_time_label)

	_speed_label = Label.new()
	_speed_label.text = "Tempo: 1.00x"
	v.add_child(_speed_label)
	var speed := HSlider.new()
	speed.min_value = 0.1
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = 1.0
	speed.value_changed.connect(func(s: float) -> void:
		_speed = s
		_speed_label.text = "Tempo: %.2fx" % s
		for ap in _players:
			ap.speed_scale = s)
	v.add_child(speed)

	v.add_child(HSeparator.new())
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info_label)
	var help := Label.new()
	help.text = "Links ziehen: drehen\nRechts/Mitte ziehen: verschieben\nRad: Zoom   F: einrahmen\n1-9 Clip   Leertaste Play/Pause\nPfeile: Frame   L: Loop"
	help.modulate = Color(1, 1, 1, 0.6)
	help.add_theme_font_size_override("font_size", 12)
	v.add_child(help)


func _rebuild_clip_buttons() -> void:
	for c in _clip_box.get_children():
		_clip_box.remove_child(c)  # free the name right away; new buttons reuse it
		c.queue_free()
	var names := _clip_names()
	for i in names.size():
		var b := Button.new()
		b.name = names[i]
		b.text = "%d  %s" % [i + 1, names[i]]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var clip := names[i]
		b.pressed.connect(func() -> void:
			_loop_override = -1
			_play(clip))
		_clip_box.add_child(b)
