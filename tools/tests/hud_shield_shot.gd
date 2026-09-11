extends Node
## Screenshots the player's health bar at several shield levels, so the shield band can be
## judged by looking at it.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/hud_shield_shot.tscn -- <out.png>
##
## Same reason skill_tree_shot.gd exists: whether the band lines up with the health fill,
## sits inside the border, keeps the number readable and caps off cleanly at the end of the
## bar are all questions no assertion answers. The states shot are the ones that go wrong -
## no shield, a shield smaller than the empty space, a shield that exactly fills it, and a
## shield far larger than the bar can show.
##
## Crops to the bar rather than saving the whole frame: at 1152x648 the bar is a 250x30 strip
## in one corner, and a full-screen shot of it is unreadable at a glance.

const STATES: Array[Dictionary] = [
	{"hp": 100.0, "shield": 0.0, "label": "no shield"},
	{"hp": 100.0, "shield": 50.0, "label": "full hp +50: 10/15 and 5/15"},
	{"hp": 60.0, "shield": 25.0, "label": "hurt, small shield"},
	{"hp": 100.0, "shield": 200.0, "label": "shield larger than max hp"},
	{"hp": 25.0, "shield": 75.0, "label": "low hp, big shield"},
	{"hp": 100.0, "shield": 10.0, "label": "full hp, small shield"},
]

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	# The shooter is another instance of THIS script, so it reaches _ready too. Without
	# this guard it boots again, swapping the scene under itself forever.
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/hud_shield_shot.gd").new()
	shooter.name = "ShieldShooter"
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
	var out_path: String = "hud_shield.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	# The live numbers, so the shot is checked against what a real cast actually grants rather
	# than against the hand-picked values below.
	var live: Node = PlayerRegistry.get_local()
	if live != null:
		live.spell_ranks["white_2"] = 1
		if not live.unlocked_spells_in_path.has("white_2"):
			live.unlocked_spells_in_path.append("white_2")
		live.protection_shield = 0.0
		live._run_spell_effect("white_2", 1.0)
		print("  live rank-1 cast: shield=%.0f for %.1fs (max hp %.0f)" % [
			live.protection_shield, live._protection_shield_timer, live.max_hp])
		live.spell_ranks["white_2"] = GameSettings.spell_max_rank
		live.protection_shield = 0.0
		live._run_spell_effect("white_2", 1.0)
		print("  live rank-5 cast: shield=%.0f for %.1fs" % [
			live.protection_shield, live._protection_shield_timer])
		live.protection_shield = 0.0
		live._protection_shield_timer = 0.0

	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if hud == null:
		push_error("No HUD in the scene")
		get_tree().quit()
		return
	var bar: ProgressBar = hud.player_health_bar

	# One tall image with every state stacked, so the four are compared against each other
	# rather than against a memory of the last file opened.
	var strips: Array[Image] = []
	for state: Dictionary in STATES:
		hud.update_player_health(float(state["hp"]), 100.0)
		hud.update_player_shield(float(state["shield"]))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		var rect := Rect2i(
			Vector2i(bar.global_position) - Vector2i(6, 6),
			Vector2i(bar.size) + Vector2i(12, 12)
		)
		strips.append(frame.get_region(rect.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))))
		var track: float = bar.size.x - 4.0
		print("  %-34s hp=%-5.0f shield=%-5.0f capacity=%-5.0f health=%4.1f%% shield=%4.1f%%" % [
			state["label"], state["hp"], state["shield"], bar.max_value,
			100.0 * (bar.value / bar.max_value),
			100.0 * ((hud._shield_fill.size.x if hud._shield_fill.visible else 0.0) / track)])

	var strip_size: Vector2i = strips[0].get_size()
	var sheet := Image.create(strip_size.x, strip_size.y * strips.size(), false, strips[0].get_format())
	for i: int in strips.size():
		sheet.blit_rect(strips[i], Rect2i(Vector2i.ZERO, strip_size), Vector2i(0, strip_size.y * i))
	if sheet.save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()
