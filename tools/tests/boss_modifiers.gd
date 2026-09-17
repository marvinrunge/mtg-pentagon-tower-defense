extends Node
## Regression test: boss modifiers reshape a boss's two specials without ever corrupting
## the shared BossDatabase config or pushing a telegraph below the dodge floor.
##
## Run with:  godot --headless --path . res://tools/tests/boss_modifiers.tscn
##
## Same split as the other wave/enemy tests: planning first (gating, and that the roll is
## reproducible off the wave's own seed), then live checks that drive a real boss's
## _begin_special/_resolve_special directly - the same technique boss_specials.gd already
## uses - and inspect what actually changed.
##
## The one check that matters most structurally: _begin_special must duplicate
## BossDatabase.SPECIALS before touching it. That dictionary is shared by every boss of a
## colour, in every match - a modifier that mutated it in place would permanently widen or
## speed up that colour's specials for everyone, not just the one boss that rolled it. See
## "a modifier's radius change never leaks into the shared config" below.

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
	_check_gating_and_names()
	_check_independent_rolls()

	print("Riot and Annihilator")
	_check_riot()
	_check_annihilator_and_shared_config_safety()

	print("Windup floor")
	_check_windup_floor()

	print("Cataclysm and Bloodthirst")
	_check_special_weighting("Cataclysm", 0, 1)
	_check_special_weighting("Bloodthirst", 1, 0)

	print("Enrage")
	_check_enrage()

	print("Lifelink")
	_check_lifelink()

	print("Health bar tag")
	_check_modifier_tag()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


# --- Planning ----------------------------------------------------------------------------

const MODIFIERS: Array[String] = ["Riot", "Annihilator", "Cataclysm", "Bloodthirst", "Enrage", "Lifelink"]

func _check_gating_and_names() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	var early_violation: bool = false
	var saw_one: bool = false
	var saw_invalid_name: bool = false

	for wave_idx: int in range(0, 60):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("test-boss-modifier:%d" % wave_idx)
		var modifier: String = manager._roll_boss_modifier(wave_idx, rng)
		if modifier == "":
			continue
		saw_one = true
		if not MODIFIERS.has(modifier):
			saw_invalid_name = true
		if wave_idx + 1 < GameSettings.boss_modifier_start_wave:
			early_violation = true

	_check("no modifier appears before wave %d" % GameSettings.boss_modifier_start_wave,
		not early_violation)
	_check("at least one of the first 60 waves rolls a modifier", saw_one)
	_check("every roll is one of the six named modifiers", not saw_invalid_name)
	manager.queue_free()


## _plan_wave assigns a Boss unit's modifier from the SAME seeded rng it reuses for every
## unit in the group (see the loop next to "The boss leads, alone" in _plan_wave) - a
## RandomNumberGenerator advances its own state on every call, so successive units draw
## independently without needing to be reseeded per unit. Checked directly against
## _roll_boss_modifier rather than by hunting for a wave whose boss_count happens to be
## greater than one, which needs both a late wave AND a boss-interval wave at once.
func _check_independent_rolls() -> void:
	var manager: WaveManager = WaveManager.new()
	add_child(manager)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var wave_idx: int = GameSettings.boss_modifier_start_wave + 4
	var seen: Dictionary = {}
	for _i: int in range(30):
		seen[manager._roll_boss_modifier(wave_idx, rng)] = true

	_check("repeated rolls from the same rng are not all identical", seen.size() > 1,
		"only ever got %s" % [seen.keys()])
	manager.queue_free()


# --- Live: Riot and Annihilator -----------------------------------------------------------

func _spawn_boss(color: String, modifier: String = "") -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = scene.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	if modifier != "":
		boss.set_meta("boss_modifier", modifier)
	_scene.add_child(boss)
	boss.global_position = Vector3(0.0, 0.0, 60.0)
	return boss


func _check_riot() -> void:
	var plain: EnemyBase = _spawn_boss("Red")
	var riot: EnemyBase = _spawn_boss("Red", "Riot")

	_check("a Riot boss is flagged", riot.boss_modifier == "Riot")
	_check("Riot trades away some damage",
		riot.enemy_data.attack_damage < plain.enemy_data.attack_damage,
		"%.1f vs %.1f" % [riot.enemy_data.attack_damage, plain.enemy_data.attack_damage])
	_check("Riot plays its clips faster",
		riot._anim_speed_scale > plain._anim_speed_scale,
		"%.2f vs %.2f" % [riot._anim_speed_scale, plain._anim_speed_scale])

	plain.queue_free()
	riot.queue_free()


## The critical safety property: BossDatabase.SPECIALS is one Dictionary per colour, shared
## by every boss of that colour in every match. _begin_special must work on a DUPLICATE, or
## an Annihilator's radius bump would permanently widen the special for every other Red
## boss for the rest of the process's life.
func _check_annihilator_and_shared_config_safety() -> void:
	var base_radius: float = float((BossDatabase.SPECIALS["Red"][0] as Dictionary)["radius"])

	var plain: EnemyBase = _spawn_boss("Red")
	var annihilator: EnemyBase = _spawn_boss("Red", "Annihilator")

	_check("Annihilator hits harder",
		annihilator.enemy_data.attack_damage > plain.enemy_data.attack_damage)

	plain._begin_special(0)
	annihilator._begin_special(0)

	var expected: float = base_radius * GameSettings.boss_modifier_annihilator_radius_mult
	_check("Annihilator's telegraph is wider by the configured multiplier",
		absf(float(annihilator._special_config["radius"]) - expected) < 0.01,
		"got %.2f, expected %.2f" % [annihilator._special_config["radius"], expected])
	_check("a plain boss's telegraph radius is untouched",
		absf(float(plain._special_config["radius"]) - base_radius) < 0.01)

	var after_radius: float = float((BossDatabase.SPECIALS["Red"][0] as Dictionary)["radius"])
	_check("the shared BossDatabase config was never mutated",
		absf(after_radius - base_radius) < 0.001,
		"was %.2f, is now %.2f" % [base_radius, after_radius])

	plain.queue_free()
	annihilator.queue_free()


func _check_windup_floor() -> void:
	# Every colour, both specials - the floor has to hold regardless of which boss or
	# which special a Riot roll lands on, not just the one combination that happens to be
	# closest to it already.
	for color: String in ["White", "Blue", "Black", "Red", "Green"]:
		var boss: EnemyBase = _spawn_boss(color, "Riot")
		for index: int in range(boss._specials.size()):
			boss._begin_special(index)
			_check("%s special %d windup never drops below the floor" % [color, index],
				boss._special_windup_timer >= GameSettings.boss_modifier_min_windup_seconds - 0.001,
				"%.3f" % boss._special_windup_timer)
		boss.queue_free()


# --- Live: special weighting ---------------------------------------------------------------

## Cataclysm favours the big special (index 0) and starves the melee one (index 1);
## Bloodthirst is the mirror image. Checked by actually resolving both specials and reading
## back the cooldown each one was reset to, rather than inspecting the multiplier table
## directly - this is what a player's boss actually experiences.
func _check_special_weighting(modifier: String, favoured_index: int, starved_index: int) -> void:
	var boss: EnemyBase = _spawn_boss("Red", modifier)
	var base_cooldowns: Array[float] = []
	for config: Dictionary in BossDatabase.SPECIALS["Red"]:
		base_cooldowns.append(float(config.get("cooldown", GameSettings.boss_special_cooldown)))

	boss._begin_special(favoured_index)
	boss._resolve_special()
	boss._begin_special(starved_index)
	boss._resolve_special()

	_check("%s: the favoured special recycles faster than its own base cooldown" % modifier,
		boss._special_cooldowns[favoured_index] < base_cooldowns[favoured_index],
		"%.1f vs base %.1f" % [boss._special_cooldowns[favoured_index], base_cooldowns[favoured_index]])
	_check("%s: the starved special recycles slower than its own base cooldown" % modifier,
		boss._special_cooldowns[starved_index] > base_cooldowns[starved_index],
		"%.1f vs base %.1f" % [boss._special_cooldowns[starved_index], base_cooldowns[starved_index]])
	boss.queue_free()


# --- Live: Enrage and Lifelink ---------------------------------------------------------------

func _check_enrage() -> void:
	var boss: EnemyBase = _spawn_boss("Green", "Enrage")
	var starting_damage: float = boss.enemy_data.attack_damage
	var threshold_health: float = boss.enemy_data.health * GameSettings.boss_modifier_enrage_health_threshold

	_check("Enrage has not latched above the threshold", not boss._enrage_active)
	boss.take_damage(boss.enemy_data.health - threshold_health + 1.0)
	_check("Enrage latches the moment health crosses the threshold", boss._enrage_active)
	_check("Enrage raises damage once it latches",
		boss.enemy_data.attack_damage > starting_damage)

	# One-way: a small further hit must not somehow un-latch or re-scale it a second time.
	var damage_after_latch: float = boss.enemy_data.attack_damage
	boss.take_damage(1.0)
	_check("Enrage does not re-trigger on a later hit",
		boss.enemy_data.attack_damage == damage_after_latch and boss._enrage_active)
	boss.queue_free()


## A minimal stand-in for a Player: just enough to be a valid "player" group member with a
## take_damage() method, so _resolve_special's hit_player flag can actually go true without
## spinning up the real Player scene's animator, camera and skill state for one assertion.
class _FakeTarget:
	extends Node3D
	var damage_taken: float = 0.0
	func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false, _exile_on_kill: bool = false) -> void:
		damage_taken += amount


func _check_lifelink() -> void:
	var boss: EnemyBase = _spawn_boss("Red", "Lifelink")
	boss.take_damage(boss.enemy_data.health * 0.5)
	var health_before: float = boss.health

	var target := _FakeTarget.new()
	target.add_to_group("player")
	_scene.add_child(target)
	target.global_position = boss.global_position

	boss._begin_special(1)
	boss._resolve_special()

	_check("Lifelink's target actually took damage", target.damage_taken > 0.0)
	_check("Lifelink heals the boss back on a landed hit", boss.health > health_before,
		"%.1f -> %.1f" % [health_before, boss.health])

	target.queue_free()
	boss.queue_free()


func _check_modifier_tag() -> void:
	var boss: EnemyBase = _spawn_boss("Blue", "Annihilator")
	_check("the health bar carries the modifier's name",
		boss.health_bar.modifier_label.text == "ANNIHILATOR",
		boss.health_bar.modifier_label.text)
	_check("the tag is visible even at full health, unlike the bar itself",
		boss.health_bar.modifier_label.visible or not GameSettings.show_enemy_health_bars)
	boss.queue_free()
