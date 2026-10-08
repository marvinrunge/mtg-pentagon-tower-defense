extends Node
## Screenshots the skill tree, so its LAYOUT can be judged by looking at it.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/skill_tree_shot.tscn -- <out.png>
##
## The board's geometry is asserted by tools/tests/skill_purchase.gd - nothing off-board,
## nothing under the detail panel, no two nodes overlapping, at three aspect ratios. None
## of that says whether the tree READS as a tree, which is the thing the fan layout was
## for, and no assertion can.
##
## Boots the real main scene rather than the tree alone: the tree draws its rank badges and
## its node states from a live Player, and an empty one would show every node in the same
## locked grey.

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	# The shooter is another instance of THIS script, so it reaches _ready too. Without
	# this guard it boots again, swapping the scene under itself forever.
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/skill_tree_shot.gd").new()
	shooter.name = "TreeShooter"
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
	var out_path: String = "skill_tree.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	var tree: Node = get_tree().current_scene.get_node_or_null("SkillTree")
	if tree == null:
		push_error("No SkillTree in the scene")
		get_tree().quit()
		return
	# Bought a few nodes first: a board where everything is locked is all one grey, and the
	# thing being looked at is how the shapes read against each other.
	GameSettings.debug_free_skills = true
	for record: Dictionary in tree._button_records:
		if record["color"] in ["red", "blue"] and record["branch_index"] <= 2:
			tree._on_node_pressed(record["color"], record["branch_index"], record["info"])
	# Bought with the debug switch, then judged WITHOUT it: _is_reachable waves everything
	# through while that switch is on, so a shot taken with it would show every node as
	# reachable and prove nothing about the state this screen is for.
	GameSettings.debug_free_skills = false
	tree.visible = true
	tree.update_ui()
	tree._layout_nodes()

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.save_png(out_path) == OK:
		print("Wrote %s" % out_path)
	get_tree().quit()
