extends Node
## A camera flight over the map at the start of a run: from high over the volcano, round the
## outside of the pentagon looking down each lane from where its warband spawns, then down
## onto the crystal and into the player's own camera. It shows the player what they are
## defending and where it will come from before the first wave arrives.
##
## Played once per run, when the run is entered from the main menu - not on Restart, and not
## in the test scenes, which load the map directly (see MainController.play_intro_tour).
## Cosmetic and local: every peer flies its own, and the waves do not wait - the first
## warbands spawn 180 m out and take far longer than this to reach the hub.
##
## Any key, click or gamepad button skips to the last moment of the descent.
##
## Deliberately no `class_name` - preloaded by path, see scripts/icon_style.gd.

## True while a tour is flying. Player reads it: no walking, looking or attacking while the
## camera is somewhere else.
static var playing: bool = false

## Seconds for each leg: in from the volcano, then one per lane round the ring, then the
## descent onto the crystal and the settle into the player's camera.
const OPENING_SECONDS := 2.6
const LANE_SECONDS := 1.9
const DESCENT_SECONDS := 2.4
const SETTLE_SECONDS := 1.4
## How far out and how high the ring is flown, metres from the crystal.
const RING_RADIUS := 110.0
const RING_HEIGHT := 40.0
## How thin the biome fog is while the camera is up - see BiomeAtmosphere.fog_scale. Back to
## 1 over the settle, so the player lands in the fog they will play in.
const FOG_SCALE := 0.3
## Lanes whose trees stand taller than RING_HEIGHT, and how high to fly over them instead.
const LANE_HEIGHTS: Dictionary = {"Green": 60.0}
## Lanes in the order the ring passes them - round the pentagon, starting at the volcano.
const LANE_ORDER: Array[String] = ["Red", "Black", "Blue", "White", "Green"]

var _camera: Camera3D
var _player_camera: Camera3D
var _hint: CanvasLayer
## Keyframes: where the camera is, what it looks at, and when it gets there.
var _positions: Array[Vector3] = []
var _targets: Array[Vector3] = []
var _times: Array[float] = []
var _elapsed: float = 0.0


## `spawners` and `lane_names` are MainController's, in the same order; `player_camera` is
## where the flight ends.
func setup(crystal: Vector3, spawners: Array, lane_names: Array, player_camera: Camera3D) -> void:
	_player_camera = player_camera
	var first: Vector3 = _lane_forward(crystal, spawners, lane_names, LANE_ORDER[0])
	var first_side: Vector3 = first.cross(Vector3.UP).normalized()
	# Opening: beside the Red lane, looking at the volcano - which stands ~225 m out along
	# that lane and ~17 m to its right.
	var volcano: Vector3 = crystal + first * 225.0 + first_side * 17.0 + Vector3.UP * 45.0
	_key(crystal + first * 135.0 - first_side * 70.0 + Vector3.UP * 45.0, volcano, 0.0)
	for i: int in LANE_ORDER.size():
		var forward: Vector3 = _lane_forward(crystal, spawners, lane_names, LANE_ORDER[i])
		var height: float = float(LANE_HEIGHTS.get(LANE_ORDER[i], RING_HEIGHT))
		_key(crystal + forward * RING_RADIUS + Vector3.UP * height, crystal + forward * 35.0,
			OPENING_SECONDS if i == 0 else LANE_SECONDS)
	# The descent comes in over the player's shoulder, so the settle that follows is a short
	# move rather than a swing round - and inside the ring of standing stones (~25 m out),
	# clear of the forest that grows right up to it on the Green side.
	var end_position: Vector3 = player_camera.global_position
	var end_target: Vector3 = end_position - player_camera.global_basis.z * 12.0
	var approach := Vector3(end_position.x - crystal.x, 0.0, end_position.z - crystal.z)
	if approach.length() < 1.0:
		approach = first
	_key(crystal + approach.normalized() * 20.0 + Vector3.UP * 11.0, crystal + Vector3.UP * 5.0, DESCENT_SECONDS)
	_key(end_position, end_target, SETTLE_SECONDS)


func _ready() -> void:
	playing = true
	BiomeAtmosphere.fog_scale = FOG_SCALE
	_camera = Camera3D.new()
	_camera.name = "IntroTourCamera"
	_camera.far = 4000.0
	_camera.fov = 60.0
	add_child(_camera)
	_place(0.0)
	_camera.make_current()
	SignalBus.menu_opened.emit("intro_tour", true)
	_build_hint()


func _exit_tree() -> void:
	playing = false
	BiomeAtmosphere.fog_scale = 1.0


func _process(delta: float) -> void:
	_elapsed += delta
	# Where the flight lands is read live: the avatar may still be settling onto the ground
	# when the tour is set up, and its camera moves with it.
	if is_instance_valid(_player_camera):
		_positions[-1] = _player_camera.global_position
		_targets[-1] = _player_camera.global_position - _player_camera.global_basis.z * 12.0
	if _elapsed >= _times[-1]:
		_finish()
		return
	_place(_elapsed)


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	# To the start of the settle rather than straight to the end, so a skip is still a
	# short move into the player's view instead of a cut.
	_elapsed = maxf(_elapsed, _times[-1] - SETTLE_SECONDS * 0.6)


## Adds a keyframe `after` seconds after the previous one.
func _key(position: Vector3, target: Vector3, after: float) -> void:
	_positions.append(position)
	_targets.append(target)
	_times.append((_times[-1] if not _times.is_empty() else 0.0) + after)


## Puts the camera at its point on the path at `time` - a Catmull-Rom spline through the
## keyframes, so it flies through each one instead of stopping at it.
func _place(time: float) -> void:
	var i: int = 0
	while i < _times.size() - 2 and time > _times[i + 1]:
		i += 1
	var span: float = maxf(_times[i + 1] - _times[i], 0.001)
	var w: float = clampf((time - _times[i]) / span, 0.0, 1.0)
	# The first and last legs ease, so the flight starts and lands rather than jolting.
	if i == 0:
		w = w * w * (3.0 - 2.0 * w) * 0.5 + w * 0.5
	if i == _times.size() - 2:
		w = 1.0 - pow(1.0 - w, 3.0)
	var p_before: int = maxi(i - 1, 0)
	var p_after: int = mini(i + 2, _times.size() - 1)
	var position: Vector3 = _positions[i].cubic_interpolate(_positions[i + 1], _positions[p_before], _positions[p_after], w)
	var target: Vector3 = _targets[i].cubic_interpolate(_targets[i + 1], _targets[p_before], _targets[p_after], w)
	_camera.global_position = position
	if not position.is_equal_approx(target):
		_camera.look_at(target, Vector3.UP)
	# The last leg also matches the player camera's lens, so the hand-over does not zoom, and
	# lets the fog back in.
	if i == _times.size() - 2:
		BiomeAtmosphere.fog_scale = lerpf(FOG_SCALE, 1.0, w)
		if is_instance_valid(_player_camera):
			_camera.fov = lerpf(60.0, _player_camera.fov, w)


func _finish() -> void:
	set_process(false)
	set_process_input(false)
	if is_instance_valid(_player_camera):
		_player_camera.make_current()
	SignalBus.menu_opened.emit("intro_tour", false)
	queue_free()


func _build_hint() -> void:
	_hint = CanvasLayer.new()
	_hint.layer = 20
	add_child(_hint)
	var label := Label.new()
	label.text = "Press any button to skip"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -280.0
	label.offset_top = -48.0
	label.offset_right = -24.0
	label.offset_bottom = -20.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_child(label)


static func _lane_forward(crystal: Vector3, spawners: Array, lane_names: Array, lane: String) -> Vector3:
	var spawner: Vector3 = (spawners[lane_names.find(lane)] as Node3D).global_position
	return Vector3(spawner.x - crystal.x, 0.0, spawner.z - crystal.z).normalized()
