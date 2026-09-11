extends Node
## Regression test: what does a run OPEN with - the right time of day, and the mission?
##
## Run with:  godot --headless --path . res://tools/tests/day_start.tscn
##
## It did not. scenes/misc/main.tscn carried current_time = 20.757, which is past
## DayNightPacing's 20:00 dusk, so every run opened in the dark with the night music and the
## night clock rate before the player had done anything. That value was not chosen - it is
## whatever hour the Sky3D node happened to be scrubbed to when the scene was last saved,
## which means any editor session that touches the sky can put it back.
##
## So this asserts the CONSEQUENCES rather than the number: the clock reads morning, the
## pacing node agrees it is day, and the phase it announced was day - because the third one
## is a separate bug from the first two. Setting the time after attaching DayNightPacing
## leaves the clock correct while the music has already been told it is night.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
## Objectives announced on SignalBus.mission_announced. Connected before the scene swap, so
## unlike the phase signal this one does catch the opening emission.
var _missions: Array[String] = []
## Every phase the pacing node announced, in order. The FIRST one is what the run opened on.
var _announced: Array[bool] = []


func _ready() -> void:
	# Before main.tscn is even loaded: the mission goes out from MainController._ready, which
	# is long finished by the time this node has counted a frame.
	SignalBus.mission_announced.connect(func(objective: String) -> void: _missions.append(objective))


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames == 2:
		_listen()
	if _frames < 30:
		return
	_done = true
	_run()
	get_tree().quit()


## Connected as early as possible. DayNightPacing emits phase_changed from its own _ready,
## which has already happened by now - so the first emission cannot be caught this way and
## the starting phase is read off the node's state instead. What this catches is a LATER
## correction: a run that starts on the wrong phase and quietly flips a frame afterwards.
func _listen() -> void:
	var pacing: Node = _pacing()
	if pacing != null:
		pacing.phase_changed.connect(func(night: bool) -> void: _announced.append(night))


func _sky() -> Node:
	return get_tree().current_scene.get_node_or_null("Sky3D")


func _pacing() -> Node:
	var sky: Node = _sky()
	return sky.get_node_or_null("DayNightPacing") if sky != null else null


func _run() -> void:
	var sky: Node = _sky()
	var pacing: Node = _pacing()
	if sky == null or pacing == null:
		print("TEST RESULT: FAIL (no Sky3D or no DayNightPacing)")
		return

	var hour: float = float(sky.current_time)
	print("  clock reads %.2f, dawn %.1f, dusk %.1f" % [hour, pacing.dawn_hour, pacing.dusk_hour])

	if hour < pacing.dawn_hour or hour >= pacing.dusk_hour:
		_failures.append("run opens at %.2f, which is night (dawn %.1f, dusk %.1f)" % [
			hour, pacing.dawn_hour, pacing.dusk_hour])
	# Morning specifically, not merely "not night": opening at 19:00 passes the test above and
	# still gives the player one in-game hour of daylight.
	elif hour > pacing.dawn_hour + 6.0:
		_failures.append("run opens at %.2f, which is afternoon rather than morning" % hour)

	if bool(pacing._night_active):
		_failures.append("DayNightPacing starts in its night phase")

	# The clock rate has to be the DAY one. Getting this wrong is what makes a run that looks
	# like morning burn through its first day four times too fast.
	var day_hours: float = 24.0 - ((24.0 - pacing.dusk_hour) + pacing.dawn_hour)
	var expected: float = pacing.day_real_minutes * 24.0 / day_hours
	if not is_equal_approx(float(sky.minutes_per_day), expected):
		_failures.append("clock runs at %.2f minutes_per_day, day pace is %.2f" % [
			sky.minutes_per_day, expected])

	if _announced.has(true):
		_failures.append("phase_changed announced night during the opening frames")

	# --- the mission -----------------------------------------------------------
	if _missions.is_empty():
		_failures.append("no mission was announced")
	elif String(_missions[0]).strip_edges() == "":
		_failures.append("the mission announced was empty")
	else:
		print("  mission: \"%s\"" % _missions[0])

	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if hud == null:
		_failures.append("no HUD to show the mission on")
	elif hud._mission_panel == null:
		_failures.append("the HUD built no mission panel")
	else:
		# Still up. The banner holds MISSION_HOLD_SECONDS after fading in, and these checks run
		# well inside that - a mission that has already gone by frame 30 is one nobody read.
		if not bool(hud._mission_panel.visible):
			_failures.append("the mission banner is already gone")
		# ...and it must not be sitting on top of the lane-warning banner, which wave 1 raises
		# 2.5s in while this one is still up.
		if hud._warning_panel != null:
			var mission_rect := Rect2(hud._mission_panel.position, hud._mission_panel.size)
			var warning_rect := Rect2(hud._warning_panel.position, hud._warning_panel.size)
			if mission_rect.intersects(warning_rect):
				_failures.append("the mission banner overlaps the lane-warning banner")

	if _failures.is_empty():
		print("TEST RESULT: PASS (opens at %.2f, day pace %.1f min/day, mission shown)" % [
			hour, sky.minutes_per_day])
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
