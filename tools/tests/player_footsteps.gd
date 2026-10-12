extends Node3D
## Regression test: does the player's footfall signal hear every step, once, on every gait?
##
## Drives a real PlayerAnimator through each way of moving and records every footfall. A
## step heard twice shows up as two footfalls closer together than any gait puts them; a
## step missed shows up as a gap longer than any gait leaves. The diagonal is the case this
## exists for: before the gait spaces were phase-locked (PlayerAnimator._build_gait_space)
## its two blended clips drifted apart and the feet stopped lifting, and it went more than a
## second at a time without a single step.
##
## Then the surface lookup, against the real map's terrain: every texture set has to come
## out as one of the two footstep events, and the map has to have some of each.
##
## Run with:  godot --headless --path . res://tools/tests/player_footsteps.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

## [name, velocity in the animator's space (-Z forward), sprinting]
const GAITS := [
	["walk forward", Vector3(0.0, 0.0, -1.0), false],
	["walk back", Vector3(0.0, 0.0, 0.9), false],
	["walk left", Vector3(-1.0, 0.0, 0.0), false],
	["walk right", Vector3(1.0, 0.0, 0.0), false],
	["walk diagonal", Vector3(0.7, 0.0, -0.7), false],
	["walk back diagonal", Vector3(-0.65, 0.0, 0.65), false],
	["sprint forward", Vector3(0.0, 0.0, -3.9), true],
	["sprint diagonal", Vector3(2.7, 0.0, -2.7), true],
]
## Seconds each gait runs, and how much of the start is left out of the checks - the
## cross-fade from the previous gait can land a foot at any moment.
const RUN_SECONDS := 4.0
const SETTLE_SECONDS := 0.6
## Two steps a stride, so ideally half a stride apart. The back-pedal is the most lopsided
## clip at 0.38 / 0.62; a step heard twice or missed lands well outside these.
const MIN_GAP_STRIDES := 0.3
const MAX_GAP_STRIDES := 0.7
const IDLE_SECONDS := 1.5

var _anim: PlayerAnimator
var _failures: Array[String] = []
var _gait: int = -1
var _clock: float = 0.0
var _steps: Array[float] = []


func _ready() -> void:
	_anim = PlayerAnimator.new()
	add_child(_anim)
	_anim.footfall.connect(func(_at: Vector3) -> void: _steps.append(_clock))


func _physics_process(delta: float) -> void:
	if _gait >= GAITS.size():
		return
	_clock += delta
	if _gait < 0:
		# Standing still first: nothing should be heard at all.
		_anim.update_locomotion(delta, Vector3.ZERO, false, true, false, false)
		if _clock >= IDLE_SECONDS:
			if not _steps.is_empty():
				_failures.append("standing still made %d footsteps" % _steps.size())
			_next_gait()
		return
	var gait: Array = GAITS[_gait]
	_anim.update_locomotion(delta, gait[1], gait[2], true, false, false)
	if _clock >= RUN_SECONDS:
		_check_gait(String(gait[0]), _anim._stride_seconds)
		_next_gait()
		if _gait >= GAITS.size():
			_check_surfaces()
			_finish()


func _next_gait() -> void:
	_gait += 1
	_clock = 0.0
	_steps.clear()


func _check_gait(gait_name: String, stride: float) -> void:
	var settled: Array[float] = []
	for t: float in _steps:
		if t >= SETTLE_SECONDS:
			settled.append(t)
	if stride <= 0.0 or settled.size() < 2:
		_failures.append("%s: %d footsteps in %.1f s, stride %.2f s" % [gait_name, settled.size(), RUN_SECONDS - SETTLE_SECONDS, stride])
		return
	# The edges count as gaps too, so a gait that goes quiet near the end is caught.
	var marks: Array[float] = [SETTLE_SECONDS]
	marks.append_array(settled)
	marks.append(RUN_SECONDS)
	var gaps: PackedStringArray = []
	for i in range(1, marks.size()):
		var gap: float = (marks[i] - marks[i - 1]) / stride
		var interior: bool = i > 1 and i < marks.size() - 1
		if interior:
			gaps.append("%.2f" % gap)
		if interior and gap < MIN_GAP_STRIDES:
			_failures.append("%s: two footsteps %.2f strides apart at %.2f s (one step heard twice)" % [gait_name, gap, marks[i]])
		if gap > MAX_GAP_STRIDES:
			_failures.append("%s: %.2f strides without a footstep before %.2f s (a step missed)" % [gait_name, gap, marks[i]])
	print("%s: stride %.2f s, gaps in strides %s" % [gait_name, stride, " ".join(gaps)])


func _check_surfaces() -> void:
	var packed: PackedScene = load("res://scenes/misc/main.tscn")
	var state: SceneState = packed.get_state()
	var terrain: Node3D = null
	for n in state.get_node_count():
		if state.get_node_name(n) != "TerraBrush":
			continue
		terrain = ClassDB.instantiate("TerraBrush")
		for p in state.get_node_property_count(n):
			terrain.set(state.get_node_property_name(n, p), state.get_node_property_value(n, p))
		terrain.name = "TerraBrush"
	if terrain == null:
		_failures.append("main.tscn has no TerraBrush node for GroundSurface to read")
		return
	# GroundSurface looks the terrain up under the current scene, as it does in a match.
	get_tree().current_scene.add_child(terrain)
	var event: StringName = GroundSurface.footstep_event(Vector3.ZERO)
	if event != GroundSurface.FOOTSTEP_SOFT and event != GroundSurface.FOOTSTEP_HARD:
		_failures.append("GroundSurface returned '%s'" % event)
	var events: Array[StringName] = GroundSurface._events
	var sets: int = (terrain.get("textureSets") as Resource).get("textureSets").size()
	if events.size() != sets:
		_failures.append("GroundSurface classified %d of the terrain's %d texture sets" % [events.size(), sets])
	if not events.has(GroundSurface.FOOTSTEP_SOFT) or not events.has(GroundSurface.FOOTSTEP_HARD):
		_failures.append("the map's texture sets are all one surface: %s" % [events])
	for missing: StringName in [GroundSurface.FOOTSTEP_SOFT, GroundSurface.FOOTSTEP_HARD]:
		if not SoundBank.EVENT_FILES.has(missing):
			_failures.append("SoundBank has no '%s' event" % missing)


func _finish() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()
