extends Node
## Regression test: minibosses are bigger, tankier, glow in their colour, and a Mage
## miniboss fires a telegraphed special nothing else in its class gets.
##
## Run with:  godot --headless --path . res://tools/tests/minibosses.tscn
##
## Two halves, the same split as wave_formations.tscn (planning, no map needed) and
## wave_squads.tscn (live, the real scene) - because a miniboss is exactly those two kinds
## of claim stacked on top of each other: the PLANNER promises at most one per wave, never
## before wave_miniboss_start_wave, never also an Elite; and the ENEMY it flags actually
## comes out bigger, tankier, glowing, and - for a Mage - throwing a real telegraphed spell.
##
## Physics-driven state (the special's windup/resolve) is advanced by calling
## _physics_process() on the spawned enemy directly rather than waiting on the engine's own
## tick or Engine.time_scale: this test only needs ONE enemy's own timers to advance, not
## the whole scene's physics (navigation, other squads, multiplayer sync) the way
## wave_squads.tscn's march does - direct invocation is the simpler tool for that narrower
## job. The colour used for the special check (Green) is deliberately the one effect that
## touches neither a physics query nor a Player node: apply_green_mage_buff is a synchronous
## group lookup and a boolean flag, so it needs no physics-frame warm-up to observe.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	_run()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _run() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		_check("the map booted", false)
		return

	print("Planning")
	_check_gating_and_exclusivity()
	_check_escort_bonus()
	_check_slot_priority()

	print("Stats and glow")
	_check_stats_and_glow()

	print("Mage special")
	_check_mage_special()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


# --- Planning ----------------------------------------------------------------------------

## Scans a wide range of waves off the real planner - the same _plan_wave every actual run
## calls - rather than poking _roll_miniboss's internals for this part, so a change to how
## the two systems are wired together (not just their individual logic) would still be
## caught here.
func _check_gating_and_exclusivity() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	var early_violation: bool = false
	var saw_one: bool = false
	var multiple_in_one_wave: bool = false
	var stacked_with_elite: bool = false

	for wave_idx: int in range(0, 60):
		manager.current_wave = wave_idx
		var groups: Array = manager._plan_wave(wave_idx)
		var miniboss_count: int = 0
		for group: Dictionary in groups:
			for plan: Dictionary in group["squads"]:
				for unit: Dictionary in plan["units"]:
					if bool(unit.get("miniboss", false)):
						miniboss_count += 1
						if String(unit.get("elite", "")) != "":
							stacked_with_elite = true
		if miniboss_count > 0:
			saw_one = true
			if miniboss_count > 1:
				multiple_in_one_wave = true
			if wave_idx + 1 < GameSettings.wave_miniboss_start_wave:
				early_violation = true

	_check("no miniboss appears before wave %d" % GameSettings.wave_miniboss_start_wave,
		not early_violation)
	_check("at least one of the first 60 waves produces a miniboss", saw_one)
	_check("never more than one miniboss in the same wave", not multiple_in_one_wave)
	_check("a miniboss never also rolls an Elite modifier", not stacked_with_elite)
	manager.queue_free()


## _roll_miniboss directly, across enough seeds that at least one actually triggers
## (wave_miniboss_chance is 0.35, so this is not a rare event) - isolates the escort bump
## from the noise of the dynamic composition's own random melee counts, which scanning
## _plan_wave's output could not cleanly separate.
func _check_escort_bonus() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	var triggered: bool = false
	for seed_value: int in range(0, 200):
		var per_color: Dictionary = {}
		for color: String in ["White", "Blue", "Black", "Red", "Green"]:
			per_color[color] = {"Melee": 2, "Ranged": 1, "Mage": 1}
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		manager._roll_miniboss(GameSettings.wave_miniboss_start_wave - 1, per_color, rng)
		var chosen_color: String = String(per_color.get("__miniboss_color__", ""))
		if chosen_color == "":
			continue
		triggered = true
		var expected: int = 2 + GameSettings.wave_miniboss_escort_bonus
		_check("the miniboss's own squad gets the escort bonus",
			int(per_color[chosen_color].get("Melee", 0)) == expected,
			"expected %d, got %d" % [expected, per_color[chosen_color].get("Melee", 0)])
		var other_color: String = "White" if chosen_color != "White" else "Blue"
		_check("other colours are not touched by the escort bonus",
			int(per_color[other_color].get("Melee", 0)) == 2)
		break
	_check("the escort bonus check actually ran", triggered, "no seed in range triggered one")
	manager.queue_free()


## _assign_miniboss directly on a hand-built squad, checking the claim made in its own
## header comment: the flagged unit is the FIRST of its class in the list, which
## _deploy_squad hands the first formation slot for that class - front-and-centre, with no
## SquadDoctrine changes required to make a miniboss stand out.
func _check_slot_priority() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	var units: Array = manager._units_of({"Melee": 4, "Ranged": 2, "Mage": 3})
	var groups: Array = [{
		"colors": PackedStringArray(["Red"]),
		"squads": [{"color": "Red", "lane": 3, "units": units}],
	}]
	manager._assign_miniboss(groups, "Red", "Mage")

	var first_mage_index: int = -1
	var flagged_index: int = -1
	var flagged_count: int = 0
	for i: int in range(units.size()):
		var unit: Dictionary = units[i]
		if String(unit["type"]) == "Mage" and first_mage_index < 0:
			first_mage_index = i
		if bool(unit.get("miniboss", false)):
			flagged_count += 1
			flagged_index = i

	_check("exactly one unit is flagged as the miniboss", flagged_count == 1,
		"%d flagged" % flagged_count)
	_check("it is the first Mage in the list - the formation's front-and-centre slot",
		flagged_index == first_mage_index,
		"flagged index %d, first Mage index %d" % [flagged_index, first_mage_index])
	manager.queue_free()


# --- Live enemy ---------------------------------------------------------------------------

func _spawn(color: String, unit_type: String, miniboss: bool) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", color)
	enemy.set_meta("enemy_type", unit_type)
	if miniboss:
		enemy.set_meta("miniboss", true)
	_scene.add_child(enemy)
	enemy.global_position = Vector3(0.0, 0.0, 60.0)
	return enemy


## Compares a plain enemy against a miniboss of the SAME colour and class, spawned side by
## side, and checks the RATIO between them rather than an absolute number - every other
## scaling factor (player count, wave number, colour modifiers) applies identically to both
## before apply_miniboss() runs, so it cancels out of the ratio and only the miniboss
## multipliers themselves are left to check.
func _check_stats_and_glow() -> void:
	var plain: EnemyBase = _spawn("Red", "Mage", false)
	var boosted: EnemyBase = _spawn("Red", "Mage", true)

	_check("a miniboss is flagged as one", boosted.is_miniboss)
	_check("an ordinary enemy is not", not plain.is_miniboss)

	var health_ratio: float = boosted.health / maxf(plain.health, 0.01)
	_check("health scales by wave_miniboss_health_mult",
		absf(health_ratio - GameSettings.wave_miniboss_health_mult) < 0.05,
		"ratio %.2f, expected %.2f" % [health_ratio, GameSettings.wave_miniboss_health_mult])

	var scale_ratio: float = boosted.scale.x / maxf(plain.scale.x, 0.01)
	_check("model scale increases by wave_miniboss_scale_mult",
		absf(scale_ratio - GameSettings.wave_miniboss_scale_mult) < 0.02,
		"ratio %.2f, expected %.2f" % [scale_ratio, GameSettings.wave_miniboss_scale_mult])

	_check("attack damage is boosted",
		boosted.enemy_data.attack_damage > plain.enemy_data.attack_damage)
	_check("speed is traded down a little, not zeroed",
		boosted.enemy_data.speed < plain.enemy_data.speed and boosted.enemy_data.speed > 0.0)

	_check("the glow was applied to the miniboss", _has_glow(boosted))
	_check("an ordinary enemy carries no glow", not _has_glow(plain))

	plain.queue_free()
	boosted.queue_free()


## Whichever branch _apply_miniboss_glow took actually ran: a NEXT_PASS on a duplicated
## surface material for a skinned mesh, or emission on the CSGBox3D fallback when no
## imported model is available (the case a headless run without generated assets falls
## into) - either counts as "the glow was applied."
func _has_glow(enemy: EnemyBase) -> bool:
	var skeleton: Skeleton3D = enemy.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		for child: Node in skeleton.get_children():
			if not (child is MeshInstance3D):
				continue
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			for surface: int in range(mesh_instance.get_surface_override_material_count()):
				var material: Material = mesh_instance.get_active_material(surface)
				if material != null and material.next_pass != null:
					return true
		return false
	var fallback: CSGBox3D = enemy.find_child("CSGBox3D", true, false) as CSGBox3D
	if fallback != null and fallback.material is StandardMaterial3D:
		return (fallback.material as StandardMaterial3D).emission_enabled
	return false


## Green rather than White/Red/Blue/Black: apply_green_mage_buff is a plain group lookup
## and a boolean flag, with no physics-shape query (White's heal) and no Player node
## (Red/Blue) involved - the one effect that needs no physics-frame warm-up after the
## bodies were just add_child()ed this same frame, which is what makes it safe to observe
## from a synchronous, manually-stepped test like this one.
func _check_mage_special() -> void:
	var mage: EnemyBase = _spawn("Green", "Mage", true)
	var ally: EnemyBase = _spawn("Green", "Melee", false)
	ally.global_position = mage.global_position + Vector3(1.0, 0.0, 0.0)

	_check("the special has not fired yet", mage._miniboss_special_windup < 0.0)
	_check("the ally starts unbuffed", not ally.has_green_mage_buff)

	# Forced to fire almost immediately rather than waiting out the real cooldown (several
	# seconds) - this is a regression test, not a playthrough.
	mage._miniboss_special_timer = 0.02

	var fired: bool = false
	var resolved: bool = false
	for _tick: int in range(80):
		mage._physics_process(0.1)
		if not fired and mage._miniboss_special_windup >= 0.0:
			fired = true
			_check("a ground telegraph is drawn", mage._miniboss_special_indicator != null)
		if fired and mage._miniboss_special_windup < 0.0:
			resolved = true
			break

	_check("the windup begins once the timer elapses", fired)
	_check("the windup resolves on its own", resolved)
	_check("Green's special buffed the ally in range", ally.has_green_mage_buff)

	mage.queue_free()
	ally.queue_free()
