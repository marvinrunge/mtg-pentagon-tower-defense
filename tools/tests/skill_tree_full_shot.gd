extends Node
## A photograph of the whole skill tree with EVERY node bought - every icon revealed, every
## edge lit - for looking at the board as a whole (planning where it grows next, checking
## which nodes still wear a placeholder icon). skill_tree_shot.gd shows the layout as a
## fresh player sees it.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/skill_tree_full_shot.tscn -- <out.png>
## Loads the real main scene, so it takes a while on a software renderer.

var _frames: int = 0
var _started: bool = false


func _ready() -> void:
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		# Boot: survive the scene swap by moving the photographer onto the root.
		(func() -> void:
			var shooter: Node = (load("res://tools/tests/skill_tree_full_shot.gd") as GDScript).new()
			shooter.name = "FullTreeShooter"
			get_tree().root.add_child(shooter)
			get_tree().change_scene_to_file("res://scenes/misc/main.tscn")).call_deferred()
		set_process(false)


func _process(_delta: float) -> void:
	if _started:
		return
	_frames += 1
	if _frames < 120:
		return
	_started = true
	_shoot()


func _shoot() -> void:
	var scene: Node = get_tree().current_scene
	var st: Node = scene.get_node_or_null("SkillTree") if scene != null else null
	var player: Node = PlayerRegistry.get_local()
	if st == null or player == null:
		print("SKILL TREE SHOT: no tree or no player")
		get_tree().quit()
		return
	st.set_open(true)
	GameSettings.debug_free_skills = true
	# Several passes: a node only opens once a neighbour is owned, so the board is bought
	# outward from the hub one ring at a time.
	for _pass: int in range(12):
		for record: Dictionary in st._button_records:
			for _rank: int in range(GameSettings.spell_max_rank):
				st._on_node_pressed(record["color"], record["branch_index"], record["info"])
	st.update_ui()
	st._hide_details()
	for _i: int in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out_path: String = "skill_tree.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	get_viewport().get_texture().get_image().save_png(out_path)
	print("SKILL TREE SHOT: %s" % out_path)
	get_tree().quit()
