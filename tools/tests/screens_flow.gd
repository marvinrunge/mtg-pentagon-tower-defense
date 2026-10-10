extends Node
## Walks the whole front end the way a player does - start, splash into the menu, PLAY SOLO,
## the loading screen, the intro flight, and the defeat screen - checking each hand-over and
## leaving a picture of every step.
##
## Run with (windowed - it takes screenshots):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/screens_flow.tscn -- <folder>
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _failures: Array[String] = []
var _folder: String = "user://screens_flow"
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/screens_flow.gd").new()
	probe.name = "ScreensFlowTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


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
	await _seconds(0.25)
	await _shot("1_splash_fading")
	await _seconds(2.2)
	await _shot("2_menu")
	var menu: Node = get_tree().current_scene
	# The tallest page, which has to fit under the logo in a 720p window too.
	menu.call("_show_page", 2)
	await _seconds(0.3)
	await _shot("2b_menu_join")
	menu.call("_show_page", 0)
	_check(ProjectSettings.get_setting("application/config/name") == "Pentafall", "the game is called Pentafall",
		str(ProjectSettings.get_setting("application/config/name")))

	menu.call("_on_solo_pressed")
	await _seconds(0.3)
	var loading: Node = get_tree().root.get_node_or_null("LoadingScreen")
	_check(loading != null, "PLAY puts the loading screen up", str(loading))
	await _shot("3_loading")
	# Until the map reports ready, the screen stays; then it fades into the flight.
	var waited: float = 0.0
	while is_instance_valid(loading) and String(loading.get("_phase")) != "done" and waited < 60.0:
		await _seconds(0.25)
		waited += 0.25
	_check(is_instance_valid(loading) == false or String(loading.get("_phase")) == "done",
		"the loading screen lifts once the map is ready", "after %.1f s" % waited)
	await _seconds(0.35)
	await _shot("4_loading_lifting")
	await _seconds(1.0)
	_check(not is_instance_valid(loading), "and is gone", str(loading))
	var scene: Node = get_tree().current_scene
	_check(scene.get_node_or_null("IntroTour") != null, "into the intro flight", "")
	await _shot("5_intro")

	# Skip the flight, lose the crystal.
	var press := InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	await _seconds(2.0)
	scene.call("damage_crystal", 1.0e9)
	await _seconds(GameSettings.crystal_death_seconds + 0.6)
	var panel: Control = scene.get_node("HUD").get("game_over_panel")
	_check(panel.visible and panel.find_child("DefeatTitle", true, false) != null, "defeat shows the DEFEAT lettering",
		"visible %s" % panel.visible)
	await _shot("6_defeat")
