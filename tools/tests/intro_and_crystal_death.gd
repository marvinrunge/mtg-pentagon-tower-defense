extends Node
## Regression test and filmstrip for the two set pieces that bracket a run: the intro camera
## flight (IntroTour) and the crystal's destruction (MainController._destroy_crystal).
##
## Run with (windowed - it takes screenshots):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/intro_and_crystal_death.tscn -- <folder>
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, and leaves frames of both
## in <folder> to look at.

const IntroTour := preload("res://scripts/intro_tour.gd")

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []
var _folder: String = "user://set_pieces"


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/intro_and_crystal_death.gd").new()
	probe.name = "SetPiecesTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	# As the main menu does on its way into a run.
	GameSettings.intro_tour_pending = true
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_started = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_folder = args[0]
	DirAccess.make_dir_recursive_absolute(_folder)
	await _run()
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(ok: bool, what: String, detail: String) -> void:
	print("%s   %s (%s)" % ["ok" if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s (%s)" % [what, detail])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_folder.path_join(name + ".png"))


func _run() -> void:
	# The tour starts once the players are on the ground.
	var tour: Node = null
	for i: int in 600:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		tour = scene.get_node_or_null("IntroTour") if scene != null else null
		if tour != null:
			break
	_check(tour != null, "a run entered from the menu opens with the camera flight", str(tour))
	if tour == null:
		return
	var scene: Node = get_tree().current_scene
	_check(IntroTour.playing and get_viewport().get_camera_3d().name == "IntroTourCamera",
		"the flight has the camera", str(get_viewport().get_camera_3d()))
	_check(not GameSettings.intro_tour_pending, "and will not play again on a restart", "pending %s" % GameSettings.intro_tour_pending)
	var at: float = 0.0
	for t: float in [0.6, 3.0, 5.2, 7.4, 9.5, 11.6]:
		await _seconds(t - at)
		at = t
		await _shot("tour_%04.1f" % t)
		if not is_instance_valid(tour):
			break
	# Whatever is left of it - let it land, or skip.
	if is_instance_valid(tour):
		var press := InputEventKey.new()
		press.keycode = KEY_SPACE
		press.pressed = true
		Input.parse_input_event(press)
		await _seconds(1.5)
	var player: Node = PlayerRegistry.get_local()
	_check(not is_instance_valid(tour) and not IntroTour.playing, "the flight ends", "playing %s" % IntroTour.playing)
	_check(get_viewport().get_camera_3d() == player.get("camera"), "and hands back to the player's camera",
		str(get_viewport().get_camera_3d()))

	# The crystal falls.
	var hud: Node = scene.get_node("HUD")
	var panel: Control = hud.get("game_over_panel")
	scene.call("damage_crystal", 1.0e9)
	await _seconds(0.3)
	_check(bool(scene.get("_crystal_destroyed")), "the crystal's destruction starts at zero health", "")
	_check(get_viewport().get_camera_3d().name == "CrystalDeathCamera", "with the camera on the crystal",
		str(get_viewport().get_camera_3d()))
	_check(not panel.visible, "and the game-over panel held back", "visible %s" % panel.visible)
	await _seconds(0.5)
	await _shot("death_1_cracks")
	await _seconds(0.75)
	await _shot("death_2_blast")
	var crystal: Node3D = scene.get("crystal_visual")
	_check(not crystal.visible, "the big blast takes the crystal", "visible %s" % crystal.visible)
	await _seconds(1.0)
	await _shot("death_3_smoke")
	await _seconds(GameSettings.crystal_death_seconds - 2.3)
	_check(panel.visible, "the game-over panel follows", "visible %s" % panel.visible)
	await _shot("death_4_panel")
