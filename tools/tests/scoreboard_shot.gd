extends Node
## Screenshots the Tab panel with real numbers in it, so the table and the log can be judged
## for legibility and fit.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/scoreboard_shot.tscn -- <out.png>
##
## scoreboard.gd asserts that the numbers are recorded and that the rows exist. What it cannot
## say is whether seven columns of figures actually fit the panel, whether the columns line up,
## or whether a five-figure damage total pushes the table out of its own frame - which is why
## the numbers below are deliberately large and awkward.

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/scoreboard_shot.gd").new()
	shooter.name = "ScoreboardShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	_shoot()


func _shoot() -> void:
	var out_path: String = "scoreboard.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	var player: Node = PlayerRegistry.get_local()
	if hud == null or player == null:
		push_error("No HUD or player")
		get_tree().quit()
		return

	# A run's worth of numbers, with the big ones big enough to test the "k" folding.
	player.stats = {
		"kills": 148, "deaths": 2, "downs": 5,
		"damage_dealt": 128450.0, "damage_taken": 9310.0,
		"heal_self": 2140.0, "heal_others": 15870.0,
	}

	# A log with every kind of line in it, in the order a run would produce them.
	SignalBus.mission_announced.emit("Protect the Crystal!")
	SignalBus.wave_started.emit(1)
	SignalBus.lane_warning_requested.emit("White", "WHITE LANE - MELEE ASSAULT", Color(0.95, 0.95, 0.85))
	SignalBus.lane_warning_requested.emit("Blue", "BLUE LANE - RANGED ASSAULT - ELITE HASTE", Color(0.25, 0.55, 1.0))
	SignalBus.wave_completed.emit(1)
	SignalBus.team_level_changed.emit(2, 1)
	SignalBus.wave_started.emit(2)
	# Deliberately NOT upkeep_started: it opens the Upkeep panel, which in real play cannot
	# happen while Tab is held (the input handler returns early during Upkeep) and here only
	# puts a second full-screen panel behind the one being photographed.
	hud.log_message("Upkeep - 20s", Color(0.85, 0.8, 1.0))
	SignalBus.lane_warning_requested.emit("Red", "RED BOSS HAS ARRIVED", Color(1.0, 0.25, 0.14))

	hud._set_tab_panel_shown(true)
	print("scoreboard rows=%d log rows=%d panel=%s" % [
		hud._scoreboard_rows.get_child_count(), hud._log_rows.get_child_count(),
		hud._tab_panel.size])

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()
