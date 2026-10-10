extends CanvasLayer
## The screen between the menu and the map: one of the five faction paintings, the logo, a
## bar and a tip, up from the moment PLAY is pressed until the map has its ground and its
## players (SignalBus.map_ready), then faded away into the intro flight.
##
## It lives on the root rather than in either scene, because it has to outlast the change
## from one to the other: the map's resources are loaded on a thread while this is shown,
## and most of the wait comes after the switch, while the terrain builds its collision.
##
## Deliberately no `class_name` - preloaded by path, see scripts/icon_style.gd.

const InputHint := preload("res://scripts/input_hint.gd")
const LOGO: Texture2D = preload("res://assets/images/logo_pentafall.png")
const ART: Array[String] = [
	"res://assets/images/loading_white.jpg",
	"res://assets/images/loading_blue.jpg",
	"res://assets/images/loading_black.jpg",
	"res://assets/images/loading_red.jpg",
	"res://assets/images/loading_green.jpg",
]
## How much of the bar the resource load fills; the rest is the terrain building after the
## switch, which reports no progress of its own and is eased towards instead.
const LOAD_SHARE := 0.7
## Seconds after the switch before the screen lifts anyway, should map_ready never come.
const BUILD_TIMEOUT := 45.0
const FADE_SECONDS := 0.7

var _path: String = ""
var _phase: String = "loading"
var _target: float = 0.0
var _build_elapsed: float = 0.0
var _root: Control
var _bar: ProgressBar


## Puts the screen up and starts loading `path`; the scene changes to it when it is ready.
static func begin(tree: SceneTree, path: String) -> void:
	var screen: CanvasLayer = load("res://scripts/loading_screen.gd").new()
	screen.set("_path", path)
	screen.name = "LoadingScreen"
	tree.root.add_child(screen)


func _ready() -> void:
	layer = 100
	_build()
	SignalBus.map_ready.connect(_on_map_ready)
	if ResourceLoader.load_threaded_request(_path) != OK:
		# No thread to load on - do it the plain way, the screen still covers the build.
		get_tree().change_scene_to_file(_path)
		_phase = "building"


func _process(delta: float) -> void:
	match _phase:
		"loading":
			var progress: Array = []
			var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_path, progress)
			if not progress.is_empty():
				_target = float(progress[0]) * LOAD_SHARE
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(_path) as PackedScene)
				_phase = "building"
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("LoadingScreen: could not load %s" % _path)
				get_tree().change_scene_to_file(_path)
				_phase = "building"
		"building":
			# Creeps towards the end without reaching it: there is nothing to measure here, and a
			# bar standing still reads as a hang.
			_build_elapsed += delta
			_target = lerpf(_target, 0.97, 1.0 - exp(-0.35 * delta))
			if _build_elapsed > BUILD_TIMEOUT:
				_on_map_ready()
	_bar.value = lerpf(_bar.value, _target, 1.0 - exp(-6.0 * delta))


func _on_map_ready() -> void:
	if _phase == "done":
		return
	_phase = "done"
	_target = 1.0
	_bar.value = 1.0
	var fade := create_tween()
	fade.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(queue_free)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks: nothing behind it is meant to be used while it is up.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color.BLACK
	_root.add_child(black)
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = load(ART[randi() % ART.size()]) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_root.add_child(art)

	# A shade up from the bottom, so the bar and the tip read over any of the paintings.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.85))
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0.0, 0.0)
	shade_texture.fill_to = Vector2(0.0, 1.0)
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.anchor_top = 0.72
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(shade)

	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.offset_left = 36.0
	logo.offset_top = 24.0
	logo.offset_right = 36.0 + 360.0
	logo.offset_bottom = 24.0 + 160.0
	_root.add_child(logo)

	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -520.0
	bottom.offset_right = 520.0
	bottom.offset_top = -118.0
	bottom.offset_bottom = -40.0
	bottom.add_theme_constant_override("separation", 14)
	_root.add_child(bottom)

	var tip := Label.new()
	tip.text = _tip()
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	tip.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	tip.add_theme_constant_override("outline_size", 5)
	bottom.add_child(tip)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 10.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.72, 0.45)
	fill.set_corner_radius_all(3)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	track.border_color = Color(0.62, 0.52, 0.38, 0.8)
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", track)
	bottom.add_child(_bar)


## One thing worth knowing, picked at random. Keys are named for the device in hand.
func _tip() -> String:
	var tips: Array[String] = [
		"Hold %s at a mana well to harvest it - moving gives the harvest up." % InputHint.key("interact"),
		"Upkeep follows every wave: spend the team's mana on Myrs, skill points and enchantments. In a team, enchantments need a majority vote.",
		"Neighbouring colours are allies. Their warbands can arrive together and charge as one.",
		"Bosses telegraph their attacks on the ground. Read the marking and step out of it.",
		"Bosses drop equipment for the whole team. Press %s to put it on." % InputHint.key("equipment"),
		"Hold block to take hits on your guard - you move slower while you do.",
		"Nights are dark. The crystal's light and your spells are what you see by.",
		"Myrs work the mana wells for you. Build them at the base by the crystal.",
	]
	return "TIP  -  " + tips[randi() % tips.size()]
