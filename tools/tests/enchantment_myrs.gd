extends Node
## Regression test: every enchantment carries a stackable myr effect, and a stack is
## worth something.
##
## Run with:  godot --headless --path . res://tools/tests/enchantment_myrs.tscn
##
## Trash enemies stopped paying mana, which makes the myrs the economy - and the myrs were
## nowhere near carrying it. A delivery costs about 123 seconds (112 of them walking) for
## one mana at level 1, against the ~100 a wave of trash used to hand over for free. Each
## colour's enchantment now also does something to the myrs, per stack, so a team that
## wants the myr economy has five different ways to buy into it:
##
##   White  flat damage reduction, capped short of immunity
##   Blue   a LOADED myr phases out of reach after each hit
##   Black  a dying myr explodes
##   Red    myrs move faster - the round trip is the whole bottleneck
##   Green  +1 myr slot on every well, and richer bosses
##
## What is checked here is the shape the design depends on rather than the numbers
## themselves: nothing at zero stacks, monotonic in stacks, and each colour moving only
## its own lever. The numbers are tuning and will move; the shape is the promise.

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null
var _saved: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_scene = get_tree().current_scene
	if _scene == null or not _scene.has_method("bake_map_navigation"):
		return
	_frames += 1
	if _frames < 10:
		return
	_done = true
	_saved = RunState.enchantments.duplicate()
	_run()
	RunState.enchantments = _saved
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _run() -> void:
	print("Nothing at zero stacks")
	_test_inert_at_zero()
	print("Each stack is worth something")
	_test_monotonic()
	print("White")
	_test_white()
	print("Blue")
	_test_blue()
	print("Black")
	_test_black()
	print("Red / Green")
	_test_red_and_green()
	print("Upkeep row")
	_test_descriptions()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


# --- shape ----------------------------------------------------------------------------

## A colour nobody has bought must do nothing at all. Without this a "per stack" effect
## that accidentally reads as "base + per stack" would hand out its first tier for free.
func _test_inert_at_zero() -> void:
	_set_all(0)
	_check("no damage reduction", is_equal_approx(RunState.myr_damage_reduction(), 0.0))
	_check("no phase", is_equal_approx(RunState.myr_phase_duration(), 0.0))
	_check("no death blast", RunState.myr_blast_damage() <= 0.0 and RunState.myr_blast_radius() <= 0.0)
	_check("no speed bonus", is_equal_approx(RunState.myr_speed_multiplier(), 1.0))
	_check("wells are the authored size",
		RunState.myr_well_slots() == GameSettings.myr_well_max_slots)


## Every lever has to keep moving as stacks are bought - the whole point of putting these
## on the enchantments was that levelling one should be felt.
func _test_monotonic() -> void:
	var levers: Dictionary = {
		"White: damage reduction": func() -> float: return RunState.myr_damage_reduction(),
		"Blue: phase seconds": func() -> float: return RunState.myr_phase_duration(),
		"Black: blast damage": func() -> float: return RunState.myr_blast_damage(),
		"Red: speed multiplier": func() -> float: return RunState.myr_speed_multiplier(),
		"Green: well slots": func() -> float: return float(RunState.myr_well_slots()),
	}
	for label: String in levers:
		var color: String = label.split(":")[0]
		var readings: Array[float] = []
		for stacks: int in [1, 3, 5]:
			_set_all(0)
			RunState.enchantments[color] = stacks
			readings.append(float((levers[label] as Callable).call()))
		_check("%s rises with every stack" % label,
			readings[0] < readings[1] and readings[1] < readings[2],
			"1/3/5 = %.2f / %.2f / %.2f" % [readings[0], readings[1], readings[2]])

	# ...and only its own. A colour that moved somebody else's number would make the five
	# packages impossible to tell apart on the Upkeep row.
	_set_all(0)
	RunState.enchantments["Red"] = 5
	_check("Red moves speed and nothing else",
		RunState.myr_speed_multiplier() > 1.0
			and is_equal_approx(RunState.myr_damage_reduction(), 0.0)
			and is_equal_approx(RunState.myr_phase_duration(), 0.0)
			and RunState.myr_blast_damage() <= 0.0)


# --- per colour -----------------------------------------------------------------------

func _test_white() -> void:
	_set_all(0)
	RunState.enchantments["White"] = 3
	var myr: Myr = _spawn_myr()
	var before: float = myr.health
	myr.take_damage(50.0)
	var taken: float = before - myr.health
	_check("a myr takes less damage", taken < 50.0 and taken > 0.0, "took %.1f of 50" % taken)

	# Capped rather than growing to immunity, however many stacks are bought.
	RunState.enchantments["White"] = 99
	_check("the reduction stops short of immunity",
		RunState.myr_damage_reduction() <= GameSettings.enchantment_white_myr_reduction_cap
			and RunState.myr_damage_reduction() < 1.0,
		"%.2f" % RunState.myr_damage_reduction())
	myr.free()


## Blue protects the CARGO, not the creature: only a loaded myr phases, the hit that
## starts the phase still lands, and the follow-ups inside the window do not.
func _test_blue() -> void:
	_set_all(0)
	RunState.enchantments["Blue"] = 3

	var empty: Myr = _spawn_myr()
	var before: float = empty.health
	empty.take_damage(10.0)
	empty.take_damage(10.0)
	_check("an EMPTY myr gets no phase and takes both hits",
		is_equal_approx(before - empty.health, 20.0) and empty.is_targetable(),
		"took %.1f of 20" % (before - empty.health))
	empty.free()

	var loaded: Myr = _spawn_myr()
	loaded._set_carrying(true)
	before = loaded.health
	loaded.take_damage(10.0)
	var after_first: float = loaded.health
	_check("the hit that starts the phase still lands",
		is_equal_approx(before - after_first, 10.0), "took %.1f" % (before - after_first))
	loaded.take_damage(10.0)
	_check("the follow-up inside the window does not",
		is_equal_approx(loaded.health, after_first), "health moved to %.1f" % loaded.health)
	_check("and it cannot be targeted while phased", not loaded.is_targetable())

	# An enemy re-acquiring in that moment has to walk away rather than stand and swing.
	var enemy: EnemyBase = _spawn_enemy(loaded.global_position + Vector3(1.5, 0.0, 0.0))
	enemy.target_crystal = _scene.crystal_anchor
	enemy.evaluate_target()
	_check("an enemy drops a phased myr as a target", enemy.current_target != loaded,
		"still targeting the myr")

	# ...and picks it back up once the window closes.
	loaded._phase_left = 0.0
	loaded.visible = true
	_check("it is targetable again afterwards", loaded.is_targetable())
	enemy.free()
	loaded.free()


func _test_black() -> void:
	_set_all(0)
	var near_position: Vector3 = Vector3(0.0, 0.0, 52.0)

	# No stacks: a myr dying is just a myr dying.
	var quiet: Myr = _spawn_myr(near_position)
	var bystander: EnemyBase = _spawn_enemy(near_position + Vector3(1.0, 0.0, 0.0))
	var unhurt: float = bystander.health
	quiet.die()
	_check("no blast without the enchantment", is_equal_approx(bystander.health, unhurt),
		"lost %.1f" % (unhurt - bystander.health))
	bystander.free()

	RunState.enchantments["Black"] = 3
	var bomb: Myr = _spawn_myr(near_position)
	var radius: float = RunState.myr_blast_radius()
	var inside: EnemyBase = _spawn_enemy(near_position + Vector3(radius * 0.5, 0.0, 0.0))
	var outside: EnemyBase = _spawn_enemy(near_position + Vector3(radius + 6.0, 0.0, 0.0))
	var inside_before: float = inside.health
	var outside_before: float = outside.health
	bomb.die()
	_check("a dying myr damages what is in radius", inside.health < inside_before,
		"lost %.1f" % (inside_before - inside.health))
	_check("and nothing outside it", is_equal_approx(outside.health, outside_before),
		"lost %.1f" % (outside_before - outside.health))
	inside.free()
	outside.free()


func _test_red_and_green() -> void:
	_set_all(0)
	RunState.enchantments["Red"] = 5
	_check("Red speeds myrs up meaningfully", RunState.myr_speed_multiplier() >= 1.2,
		"x%.2f" % RunState.myr_speed_multiplier())

	_set_all(0)
	var base_slots: int = RunState.myr_well_slots()
	RunState.enchantments["Green"] = 2
	_check("Green adds well slots", RunState.myr_well_slots() == base_slots + 2,
		"%d -> %d" % [base_slots, RunState.myr_well_slots()])

	# The boss half, and the proof that the old general income multiplier is really gone:
	# it used to compound with this one and turn a 25-mana boss into 53 at two stacks.
	var boss: EnemyData = EnemyDatabase.get_enemy_data("Red", "Boss")
	_set_all(0)
	var plain: int = _boss_payout(boss)
	_check("a boss pays its authored mana with no stacks", plain == GameSettings.mana_per_boss,
		"%d vs %d" % [plain, GameSettings.mana_per_boss])
	RunState.enchantments["Green"] = 2
	var boosted: int = _boss_payout(boss)
	var expected: int = int(round(float(GameSettings.mana_per_boss)
		* (1.0 + GameSettings.enchantment_green_boss_mana * 2)))
	_check("and more with Overgrowth, from one multiplier only", boosted == expected,
		"%d, expected %d" % [boosted, expected])


## Every row in the Upkeep shop has to name what the player owns AND what the next stack
## buys - that is the question the shop is being asked, and a static sentence cannot
## answer it.
func _test_descriptions() -> void:
	for color: String in COLORS:
		_set_all(0)
		var at_zero: String = RunState.enchantment_description(color)
		RunState.enchantments[color] = 2
		var at_two: String = RunState.enchantment_description(color)
		var ok: bool = (
			at_zero != "" and at_two != ""
			and at_zero != at_two
			and at_two.contains("Next stack")
			and at_zero.contains("One stack")
		)
		_check("%s's row shows the live value and the next one" % color, ok, at_two)


# --- helpers --------------------------------------------------------------------------

func _set_all(stacks: int) -> void:
	for color: String in COLORS:
		RunState.enchantments[color] = stacks


func _spawn_myr(at: Vector3 = Vector3(0.0, 0.0, 50.0)) -> Myr:
	var myr: Myr = (load("res://scenes/misc/myr.tscn") as PackedScene).instantiate()
	_scene.add_child(myr)
	myr.global_position = at
	myr.lane_index = 0
	return myr


func _spawn_enemy(at: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	_scene.add_child(enemy)
	enemy.global_position = at
	return enemy


## What a boss kill actually banks, read off the pool rather than recomputed - so this
## goes through the real on_enemy_killed path including whatever it does to the number.
func _boss_payout(boss: EnemyData) -> int:
	var before: int = int(RunState.mana_pool.get(boss.color_identity, 0))
	RunState.on_enemy_killed(boss, false, Vector3(0.0, 1.0, 50.0))
	return int(RunState.mana_pool.get(boss.color_identity, 0)) - before
