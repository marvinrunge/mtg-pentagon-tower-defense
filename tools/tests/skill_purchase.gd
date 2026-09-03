extends Node
## Regression test: can a player actually BUY things in the skill tree?
##
## Written because they could not, for as long as it took someone to try. The economy
## rework moved mana off MainController, and a leftover `has_method("spend_mana_cost")`
## guard in SkillTree._on_node_pressed then refused every purchase - silently, with no
## error, debug switch included. Nothing in the suite noticed, because nothing asserted
## that a click on a skill node changes anything.
##
## Run with:  godot --headless --path . res://tools/tests/skill_purchase.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not happen.

var _frames: int = 0
var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	_run()
	get_tree().quit()


func _record(st: Node, color: String, branch: int) -> Dictionary:
	for record: Dictionary in st._button_records:
		if record["color"] == color and record["branch_index"] == branch:
			return record
	return {}


func _run() -> void:
	var scene: Node = get_tree().current_scene
	var st: Node = scene.get_node_or_null("SkillTree")
	var player: Node = PlayerRegistry.get_local()
	print("TEST scene=%s skilltree=%s player=%s" % [scene, st != null, player != null])
	if st == null or player == null:
		print("TEST RESULT: FAIL (no tree or no player)")
		return

	var failures: Array[String] = []

	# --- A: debug free skills buys an affinity with zero points -------------------
	GameSettings.debug_free_skills = true
	var red_aff: Dictionary = _record(st, "red", 0)
	st._on_node_pressed(red_aff["color"], 0, red_aff["info"])
	print("TEST A red affinity rank = %d (points %d)" % [player.get_affinity_rank("red"), player.skill_points])
	if player.get_affinity_rank("red") != 1:
		failures.append("debug purchase of an affinity did nothing")

	# --- B: a gated spell node, still on the debug switch -------------------------
	var red_spell: Dictionary = _record(st, "red", 1)
	st._on_node_pressed(red_spell["color"], 1, red_spell["info"])
	print("TEST B unlocked spells = %s" % [player.unlocked_spells_in_path])
	if player.unlocked_spells_in_path.is_empty():
		failures.append("debug purchase of a spell did nothing")

	# --- C: the real economy - points are spent, and running out stops it ---------
	GameSettings.debug_free_skills = false
	player.grant_skill_points(1)
	var before: int = player.skill_points
	var white_aff: Dictionary = _record(st, "white", 0)
	st._on_node_pressed(white_aff["color"], 0, white_aff["info"])
	print("TEST C white rank = %d, points %d -> %d" % [player.get_affinity_rank("white"), before, player.skill_points])
	if player.get_affinity_rank("white") != 1:
		failures.append("paid purchase of an affinity did nothing")
	if player.skill_points != before - 1:
		failures.append("paid purchase did not spend a skill point")

	# --- D: broke means no --------------------------------------------------------
	var blue_aff: Dictionary = _record(st, "blue", 0)
	st._on_node_pressed(blue_aff["color"], 0, blue_aff["info"])
	print("TEST D blue rank with 0 points = %d" % player.get_affinity_rank("blue"))
	if player.get_affinity_rank("blue") != 0:
		failures.append("a purchase went through with no skill points")

	# --- E: the centre node -------------------------------------------------------
	GameSettings.debug_free_skills = true
	var center: Dictionary = _record(st, SkillTree.CENTER_KEY, SkillTree.CENTER_BRANCH)
	st._on_node_pressed(center["color"], SkillTree.CENTER_BRANCH, center["info"])
	print("TEST E blade dance = %s" % player.melee_combo_extended)
	if not player.melee_combo_extended:
		failures.append("Blade Dance could not be bought")

	# --- F: the capstone fork, through the BOARD rather than through the API ------
	# The roster test proves unlock_capstone works; this proves the node on the tree is
	# wired to it, which is a different failure and the one that actually bit before.
	player.unlocked_capstone_aura = ""
	var attunement: Dictionary = _record(st, "red", SkillTree.CAPSTONE_BRANCHES[0])
	st._on_node_pressed("red", SkillTree.CAPSTONE_BRANCHES[0], attunement["info"])
	print("TEST F capstone = %s" % player.unlocked_capstone_aura)
	if player.unlocked_capstone_aura != "aura_fervor":
		failures.append("the capstone node bought nothing")

	# And that the other half of the fork is now refused, from the board as well.
	var manifestation: Dictionary = _record(st, "red", SkillTree.CAPSTONE_BRANCHES[1])
	st._on_node_pressed("red", SkillTree.CAPSTONE_BRANCHES[1], manifestation["info"])
	if player.unlocked_capstone_aura != "aura_fervor":
		failures.append("the fork let a second capstone be bought")

	_check_layout(st, failures)

	if failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL - " + ", ".join(failures))

## The board has to FIT. Adding the capstone fork put two new nodes per colour outside the
## pentagon, and at the original radius the two lowest of them landed underneath the
## detail panel - clickable, because the panel ignores the mouse, but invisible.
##
## Checked by arithmetic rather than by looking at it, because "looks fine on my monitor"
## is how a layout regression reaches a player with a different aspect ratio.
func _check_layout(st: Node, failures: Array[String]) -> void:
	var board: Control = st._board
	for size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(2560, 1080)]:
		board.size = size
		st._layout_nodes()
		var panel: Rect2 = Rect2(st._detail_panel.position, st._detail_panel.size)
		var off_board: int = 0
		var behind_panel: int = 0
		for record: Dictionary in st._button_records:
			var button: TextureButton = record["button"]
			var rect: Rect2 = Rect2(button.position, button.size)
			if rect.position.x < 0.0 or rect.position.y < 0.0 					or rect.end.x > size.x or rect.end.y > size.y:
				off_board += 1
			if rect.intersects(panel):
				behind_panel += 1
		print("TEST G %dx%d off-board=%d behind-panel=%d" % [size.x, size.y, off_board, behind_panel])
		if off_board > 0:
			failures.append("%d nodes fall outside a %dx%d board" % [off_board, size.x, size.y])
		if behind_panel > 0:
			failures.append("%d nodes sit under the detail panel at %dx%d" % [behind_panel, size.x, size.y])
