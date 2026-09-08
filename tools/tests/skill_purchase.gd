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
	player.skill_points = 0
	var blue_aff: Dictionary = _record(st, "blue", 0)
	st._on_node_pressed(blue_aff["color"], 0, blue_aff["info"])
	print("TEST D blue rank with 0 points = %d" % player.get_affinity_rank("blue"))
	if player.get_affinity_rank("blue") != 0:
		failures.append("a purchase went through with no skill points")

	# --- E: the centre node -------------------------------------------------------
	GameSettings.debug_free_skills = true
	var center: Dictionary = _record(st, SkillTree.CENTER_KEY, SkillTree.CENTER_BRANCH)
	st._on_node_pressed(center["color"], SkillTree.CENTER_BRANCH, center["info"])
	# Blade Dance is no longer a purchase. It arrives with the team's tenth level, so the
	# assertion is that reaching that level grants it - and that the hub, which now shows
	# the level, cannot be bought at all.
	player.melee_combo_extended = false
	SignalBus.team_level_changed.emit(Player.BLADE_DANCE_LEVEL, 1)
	print("TEST E blade dance at level %d = %s" % [Player.BLADE_DANCE_LEVEL, player.melee_combo_extended])
	if not player.melee_combo_extended:
		failures.append("Blade Dance was not granted at team level %d" % Player.BLADE_DANCE_LEVEL)

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

	_check_heavy_retrigger_guard(player, failures)
	_check_spell_charge(player, failures)
	_check_hotbar(scene, player, failures)
	_check_myrs(scene, failures)
	_check_decal_grounding(player, failures)
	_check_ranks(st, player, failures)
	_check_connectivity(st, player, failures)
	_check_layout(st, failures)

	if failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL - " + ", ".join(failures))

func _check_heavy_retrigger_guard(player: Node, failures: Array[String]) -> void:
	player._action_timer = 0.1
	player._action_duration = 1.0
	player._action_elapsed = 0.9
	player._action_is_melee = true
	player._action_is_heavy = true
	if player._can_start_attack():
		failures.append("a heavy melee could retrigger before its first animation finished")
	print("TEST K heavy retrigger guard = %s" % [not player._can_start_attack()])

## A ground effect has to be ON the ground, whatever height the spell that made it went
## off at.
##
## Fireball detonates where it STRUCK - an enemy's chest, a wall - which can be metres up,
## and the scorch used to be placed at exactly that point, leaving a burn mark hanging in
## mid-air. Asserted against the helper rather than by firing a bolt, because the bolt's
## impact needs a target, a flight and a frame to land in; the rule being tested is that a
## point above the world resolves down to the world.
func _check_decal_grounding(player: Node, failures: Array[String]) -> void:
	var feet: float = player.global_position.y
	var above: Vector3 = player.global_position + Vector3(0.0, 6.0, 0.0)
	var grounded: Transform3D = SpellFx.ground_transform(player, above)
	print("TEST R decal from y=%.1f resolved to y=%.2f (feet %.2f)" % [above.y, grounded.origin.y, feet])
	if grounded.origin.y > feet + 1.0:
		failures.append("a ground decal spawned above the ground stayed in the air")


## A skill is reachable because something JOINED TO IT is owned - not because the team hit
## a number. This is the rule the fan layout was drawn for, and the one thing that would
## silently revert to "buy anything in any order" if the edge walk broke.
func _check_connectivity(st: Node, player: Node, failures: Array[String]) -> void:
	GameSettings.debug_free_skills = false
	player.spell_ranks.clear()
	player.unlocked_spells_in_path.clear()
	player.affinity_ranks["blue"] = 0
	player.skill_points = 40
	RunState.team_level = 30

	# Nothing owned in blue: only the affinity is reachable, because only it touches the hub.
	var opener: Dictionary = _record(st, "blue", 1)
	st._on_node_pressed("blue", 1, opener["info"])
	print("TEST S blue_1 without the affinity = %d" % player.get_spell_rank("blue_1"))
	if player.get_spell_rank("blue_1") != 0:
		failures.append("a spell was bought with no owned neighbour")

	# The affinity opens exactly the two openers.
	player.affinity_ranks["blue"] = 10
	print("TEST T reachable after affinity: 1=%s 2=%s 3=%s 5=%s" % [
		st._is_reachable(player, "blue", 1), st._is_reachable(player, "blue", 2),
		st._is_reachable(player, "blue", 3), st._is_reachable(player, "blue", 5)])
	if not st._is_reachable(player, "blue", 1) or not st._is_reachable(player, "blue", 2):
		failures.append("the affinity did not open its two openers")
	if st._is_reachable(player, "blue", 3) or st._is_reachable(player, "blue", 5):
		failures.append("a finisher was reachable with no opener owned")

	# Buying opener 1 reaches ITS finishers and nothing that hangs only off opener 2.
	st._on_node_pressed("blue", 1, opener["info"])
	print("TEST U after opener 1: 3=%s 4=%s 5=%s" % [
		st._is_reachable(player, "blue", 3), st._is_reachable(player, "blue", 4),
		st._is_reachable(player, "blue", 5)])
	if player.get_spell_rank("blue_1") <= 0:
		failures.append("the opener could not be bought once the affinity was owned")
	if not st._is_reachable(player, "blue", 3) or not st._is_reachable(player, "blue", 4):
		failures.append("an opener did not reach its own finishers")
	if st._is_reachable(player, "blue", 5):
		failures.append("a finisher of the OTHER opener was reachable")

	# And an unreachable node is not described: no name, no cost, nothing to plan against.
	st._show_details("blue", 5, _record(st, "blue", 5)["info"])
	var title: String = st._detail_title.text
	var body: String = st._detail_body.text
	print("TEST V unreachable detail title='%s' body='%s'" % [title, body])
	if title.contains(String(_record(st, "blue", 5)["info"]["name"])) or body != "":
		failures.append("an unreachable node revealed its name or description")


## Myrs are capped, nameable and levellable, and all three are rules a player only finds
## out about by hitting them.
##
## The cap is asserted against spawn_myr() rather than against the build BUTTON, because
## the button is one caller among several and the rule belongs to the roster, not the UI.
func _check_myrs(scene: Node, failures: Array[String]) -> void:
	var main: Node = scene
	if not main.has_method("spawn_myr"):
		failures.append("no MainController to check myrs on")
		return
	# Fill to the cap, then try once more. Whatever was already built counts towards it.
	var guard: int = GameSettings.myr_max_count * 2 + 4
	while main.myr_count() < GameSettings.myr_max_count and guard > 0:
		guard -= 1
		if main.spawn_myr() == null:
			break
	var at_cap: int = main.myr_count()
	var refused: bool = main.spawn_myr() == null
	print("TEST P myrs = %d/%d, one more refused = %s" % [at_cap, GameSettings.myr_max_count, refused])
	if at_cap != GameSettings.myr_max_count or not refused:
		failures.append("the myr cap did not hold at %d" % GameSettings.myr_max_count)

	var myrs: Array[Node] = scene.get_tree().get_nodes_in_group("myrs")
	if myrs.is_empty():
		failures.append("no myr to level")
		return
	var myr: Node = myrs[0]
	var base_hp: float = myr.max_health
	var base_carry: int = myr.carry_amount()
	myr.set_level(myr.level + 1)
	print("TEST Q myr level %d: hp %.0f -> %.0f, carry %d -> %d" % [
		myr.level, base_hp, myr.max_health, base_carry, myr.carry_amount()])
	if myr.max_health <= base_hp or myr.carry_amount() <= base_carry:
		failures.append("levelling a myr raised neither its health nor what it carries")

	# Naming: positional until the player names it, theirs afterwards.
	var fallback: String = myr.label(3)
	myr.display_name = "Scrapper"
	if fallback != "Myr 3" or myr.label(3) != "Scrapper":
		failures.append("myr naming does not fall back to a position, or ignores the name")

	# The cap must not be reachable by levelling past it either.
	myr.set_level(GameSettings.myr_max_level + 5)
	if myr.level != GameSettings.myr_max_level:
		failures.append("a myr levelled past the maximum")


## The bar has to hold exactly as many slots as the loadout does, and say exactly one
## thing on each of them: the key that fires it.
##
## Both halves are settings a person can only see by looking at the game, which is how the
## bar drifted to ten slots - two more than any controller scheme can reach - and to two
## numbers per slot in the first place.
func _check_hotbar(scene: Node, player: Node, failures: Array[String]) -> void:
	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		failures.append("no HUD in the scene to check the hotbar on")
		return
	var slots: Array = hud._hotbar_slots
	print("TEST O hotbar slots = %d (loadout %d)" % [slots.size(), player.quick_slots.size()])
	if slots.size() != Player.QUICK_SLOT_COUNT or player.quick_slots.size() != Player.QUICK_SLOT_COUNT:
		failures.append("the bar and the loadout do not both hold QUICK_SLOT_COUNT slots")
	for index: int in range(slots.size()):
		var slot: Node = slots[index]
		var num: Label = slot.get_node_or_null("Num") as Label
		if num == null or num.text != str(index + 1):
			failures.append("slot %d is not labelled with the key that casts it" % (index + 1))
			break
		if num.vertical_alignment != VERTICAL_ALIGNMENT_BOTTOM or num.horizontal_alignment != HORIZONTAL_ALIGNMENT_LEFT:
			failures.append("the slot number left the bottom-left corner")
			break
		if slot.get_node_or_null("Rank") != null or slot.get_node_or_null("VBox") != null:
			failures.append("a slot carries a second readout besides its key")
			break
		if slot.get_node_or_null("Icon") == null:
			failures.append("slot %d has no icon filling it" % (index + 1))
			break


## A held spell has to LOOK held. Charging used to set a timer and nothing else: the
## caster stood at rest for the whole hold and then snapped into the cast, and the only
## sign a charge was building at all was the HUD bar.
##
## Asserts the two halves that has to have - a wind-up in flight while the button is
## down, and a release that CONTINUES that same shot rather than starting a second one
## over the top of it - plus the charge window itself, which the payload scales against.
func _check_spell_charge(player: Node, failures: Array[String]) -> void:
	# The heavy-retrigger check left a fake action in flight, and a cast queues behind
	# one - so clear it, exactly as finishing that swing would.
	player._cancel_action()
	# Fireball was unlocked by check B; put it under the key cast_active_spell() reads.
	player.assign_quick_slot(0, "red_1")
	player.active_spell_index = 0
	player.spell_cooldown_timers.erase("red_1")
	player.cast_active_spell()
	print("TEST L charging=%s window=%.1fs windup='%s'" % [
		player.is_charging, player.charge_max_time, player._cast_windup_clip])
	if not player.is_charging:
		failures.append("holding a chargeable spell did not start a charge")
	if not is_equal_approx(player.charge_max_time, GameSettings.spell_charge_max_time):
		failures.append("the charge window is not the one GameSettings tunes")
	if player._cast_windup_clip == "":
		failures.append("a charge started with no wind-up animation playing")

	# A full hold, released: the cast takes the wind-up's shot over instead of firing a
	# fresh one, and its effect is still scheduled for the clip's own release frame.
	player.charge_timer = player.charge_max_time
	player.release_charged_spell()
	print("TEST M released cast='%s' at %.2fs, windup='%s'" % [
		player._pending_cast_id, player._pending_cast_time, player._cast_windup_clip])
	if player._pending_cast_id != "red_1":
		failures.append("releasing a full charge did not start the cast")
	if player._cast_windup_clip != "":
		failures.append("the released cast left its wind-up running underneath it")
	player._cancel_action()

	# And a charge given up on takes the pose with it, rather than leaving the caster
	# holding a spell that is never coming.
	player.spell_cooldown_timers.erase("red_1")
	player.cast_active_spell()
	player._cancel_spell_charge()
	print("TEST N dropped charge: charging=%s windup='%s'" % [
		player.is_charging, player._cast_windup_clip])
	if player.is_charging or player._cast_windup_clip != "":
		failures.append("a dropped charge left state or animation behind")


## The board has to FIT. The detail panel is intentionally an overlay now, so it may cover
## nodes while it explains the one currently being hovered.
##
## Checked by arithmetic rather than by looking at it, because "looks fine on my monitor"
## is how a layout regression reaches a player with a different aspect ratio.
func _check_layout(st: Node, failures: Array[String]) -> void:
	var board: Control = st._board
	for size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(2560, 1080)]:
		board.size = size
		st._layout_nodes()
		# Nodes must not sit on top of each other. Only worth asserting since the colours
		# became FANS rather than lines: a straight spoke could not collide with its
		# neighbours no matter how the board was shaped, and a wedge that opens out can.
		var overlaps: int = 0
		for first: int in range(st._button_records.size()):
			var a: Control = st._button_records[first]["button"]
			for second: int in range(first + 1, st._button_records.size()):
				var b: Control = st._button_records[second]["button"]
				if Rect2(a.position, a.size).intersects(Rect2(b.position, b.size)):
					overlaps += 1
		if overlaps > 0:
			failures.append("%d skill nodes overlap at %dx%d" % [overlaps, size.x, size.y])
		var off_board: int = 0
		for record: Dictionary in st._button_records:
			var button: TextureButton = record["button"]
			var rect: Rect2 = Rect2(button.position, button.size)
			if rect.position.x < 0.0 or rect.position.y < 0.0 					or rect.end.x > size.x or rect.end.y > size.y:
				off_board += 1
		print("TEST G %dx%d off-board=%d" % [size.x, size.y, off_board])
		if off_board > 0:
			failures.append("%d nodes fall outside a %dx%d board" % [off_board, size.x, size.y])

## Ranks, bought the way a player buys them: by clicking the same node again.
##
## The LEVEL gate is the interesting half - it is the only thing in the tree a player
## cannot buy their way past, so a refusal there must be real and must be explained.
func _check_ranks(st: Node, player: Node, failures: Array[String]) -> void:
	GameSettings.debug_free_skills = false
	player.spell_ranks.clear()
	player.unlocked_spells_in_path.clear()
	player.reset_quick_slots()
	# One affinity rank, so the colour's investment is exactly what the test spends into it.
	player.affinity_ranks["red"] = 1
	player.skill_points = 20
	# Deliberately low: the team's level no longer gates a rank, and this asserts that.
	RunState.team_level = 1

	var node: Dictionary = _record(st, "red", 1)
	st._on_node_pressed("red", 1, node["info"])
	print("TEST H rank=%d slot0=%s invested=%d" % [
		player.get_spell_rank("red_1"), player._get_spell_id_for_slot(0),
		player.color_investment("red")])
	if player.get_spell_rank("red_1") != 1:
		failures.append("clicking an unowned spell did not unlock it")
	if player._get_spell_id_for_slot(0) != "red_1":
		failures.append("a newly bought spell did not bind itself to the bar")

	# Rank 2 asks for 2 invested in red, and the affinity plus this spell is exactly 2 - so
	# it goes through at team level 1, which the old rule would have refused until level 3.
	st._on_node_pressed("red", 1, node["info"])
	print("TEST I rank at team level 1 = %d (invested %d)" % [
		player.get_spell_rank("red_1"), player.color_investment("red")])
	if player.get_spell_rank("red_1") != 2:
		failures.append("the colour ladder refused a rank the investment had paid for")

	# Rank 3 asks for 5. Three invested is not five, and the refusal has to SAY so rather
	# than being a dead button.
	st._on_node_pressed("red", 1, node["info"])
	var blocker: String = String(player.spell_rank_blocker("red_1"))
	print("TEST I2 rank=%d blocked with '%s'" % [player.get_spell_rank("red_1"), blocker])
	if player.get_spell_rank("red_1") != 2:
		failures.append("a rank went through with too little invested in the colour")
	if not blocker.to_lower().contains("invested"):
		failures.append("an investment-gated rank gave no reason: '%s'" % blocker)

	# With the colour genuinely invested in, every remaining rank is buyable, one point each.
	player.affinity_ranks["red"] = 10
	var points_before: int = player.skill_points
	for _i: int in range(6):
		st._on_node_pressed("red", 1, node["info"])
	var spent: int = points_before - player.skill_points
	print("TEST J maxed rank=%d spent=%d" % [player.get_spell_rank("red_1"), spent])
	if player.get_spell_rank("red_1") != GameSettings.spell_max_rank:
		failures.append("ranks did not reach the maximum with the investment for them")
	if spent != GameSettings.spell_max_rank - 2:
		failures.append("ranking up spent %d points for 3 ranks" % spent)

	# Six clicks for five ranks: the last one must have been refused, not charged.
	if player.get_spell_rank("red_1") > GameSettings.spell_max_rank:
		failures.append("rank ran past the maximum")

	RunState.team_level = 1
