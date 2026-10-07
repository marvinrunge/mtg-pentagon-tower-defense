extends Node
## Regression test: the three-phase boss fights - phases, the new shapes, combos, movement,
## the punish window, and each colour's own mechanic.
##
## Run with:  godot --headless --path . res://tools/tests/boss_phases.tscn
##
## Two halves. The STATIC half reads BossDatabase and checks the promises the design makes
## (every phase brings something new, phase 2 reaches a player who stands off, every tell is
## readable). The LIVE half spawns real bosses on the real map and drives each mechanic by
## hand - _begin_special / _resolve_special / _process_special - rather than waiting out real
## windups, the same approach boss_specials.gd and boss_modifiers.gd take.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null
var _fakes: Array[Node] = []


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	_run()
	get_tree().quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## A minimal stand-in for a Player: in the "player" group, takes damage and slows, and has the
## hp/max_hp pair weakest_player reads. Far cheaper than the real Player scene for a hit test.
class _FakePlayer:
	extends Node3D
	var damage_taken: float = 0.0
	var slowed: float = 0.0
	var hp: float = 100.0
	var max_hp: float = 100.0
	func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false, _exile_on_kill: bool = false) -> void:
		damage_taken += amount
	func apply_slow(duration: float) -> void:
		slowed = maxf(slowed, duration)


const ORIGIN := Vector3(0.0, 0.0, 60.0)


func _spawn_boss(color: String, modifier: String = "") -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = scene.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	if modifier != "":
		boss.set_meta("boss_modifier", modifier)
	_scene.add_child(boss)
	boss.global_position = ORIGIN
	boss.rotation.y = 0.0
	return boss


## A fake player `offset` away from the test origin (the boss's +Z is forward at yaw 0).
func _fake_player(offset: Vector3) -> _FakePlayer:
	var fake := _FakePlayer.new()
	fake.add_to_group("player")
	_scene.add_child(fake)
	fake.global_position = ORIGIN + offset
	_fakes.append(fake)
	return fake


func _clear_fakes() -> void:
	for fake: Node in _fakes:
		if is_instance_valid(fake):
			fake.remove_from_group("player")
			fake.free()
	_fakes.clear()


## Real players on the map would be picked by the player-targeting rules; the test boss stands
## well away from the base, but they are taken out of the group for the run to be certain.
func _bench_real_players() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		node.remove_from_group("player")


func _index_of(color: String, display_name: String, phase: int) -> int:
	var specials: Array = BossDatabase.get_specials(color)
	for i: int in range(specials.size()):
		var config: Dictionary = specials[i]
		if String(config["display_name"]) == display_name and BossDatabase.special_in_phase(config, phase):
			return i
	return -1


func _set_phase(boss: EnemyBase, phase: int) -> void:
	var ratio: float = 0.5 if phase == 2 else 0.2
	boss.take_damage(boss.health - boss.enemy_data.health * ratio)
	boss._pending_phase_transition = false


func _run() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		print("TEST RESULT: FAIL (no scene)")
		return
	_bench_real_players()

	print("STATIC")
	for color: String in ["Red", "Blue", "Green", "White", "Black"]:
		_check_static(color)
	print("SHAPES")
	_check_shapes()
	print("PHASES")
	_check_phase_thresholds()
	_check_transition()
	print("RED")
	_check_meteors()
	_check_unbound_whirlwind()
	print("BLUE")
	_check_ice_lances_and_absolute_zero()
	print("GREEN")
	_check_leap()
	_check_saplings()
	print("WHITE")
	_check_shield_wall()
	_check_consecration()
	print("BLACK")
	_check_charge()
	_check_raise_dead()
	print("REGENERATION")
	_check_regeneration()
	print("BOSS BAR")
	_check_boss_bar()
	print("TELLS AND STYLES")
	_check_tells_and_styles()
	print("NETWORK")
	_check_fx_payload_is_plain_data()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)


# --- Static --------------------------------------------------------------------------------

func _names_in_phase(color: String, phase: int) -> Array[String]:
	var names: Array[String] = []
	for config: Dictionary in BossDatabase.get_specials(color):
		if BossDatabase.special_in_phase(config, phase):
			names.append("%s/%s" % [config["display_name"], str(config.get("phases", []))])
	return names


func _check_static(color: String) -> void:
	var p1: Array[String] = _names_in_phase(color, 1)
	var p2: Array[String] = _names_in_phase(color, 2)
	var p3: Array[String] = _names_in_phase(color, 3)
	_check("%s phase 2 brings in something new" % color, p2.any(func(n: String) -> bool: return not p1.has(n)), str(p2))
	_check("%s phase 3 brings in something new" % color, p3.any(func(n: String) -> bool: return not p2.has(n)), str(p3))

	var phase_config: Dictionary = BossDatabase.get_phase_config(color)
	_check("%s names both later phases" % color,
		(phase_config.get("titles", {}) as Dictionary).has(2) and (phase_config.get("titles", {}) as Dictionary).has(3))

	# Phase 2's job for four of the five: answer a player who stands off. Black's answer is
	# different by design - it raises the dead around it instead - so it is checked for that.
	if color == "Black":
		_check("Black phase 2 raises the dead", BossDatabase.get_specials(color).any(func(c: Dictionary) -> bool:
			return String(c.get("kind", "")) == "raise_dead" and BossDatabase.special_in_phase(c, 2)))
	else:
		var reach: float = 0.0
		for config: Dictionary in BossDatabase.get_specials(color):
			if BossDatabase.special_in_phase(config, 2) and not BossDatabase.special_in_phase(config, 1):
				reach = maxf(reach, float(config.get("max_range", 0.0)))
		_check("%s phase 2 reaches a player standing off" % color, reach >= 14.0, "%.1f" % reach)

	# Every followup has a readable tell of its own.
	for config: Dictionary in BossDatabase.get_specials(color):
		for followup: Dictionary in config.get("followups", []):
			_check("%s '%s' followup has a windup" % [color, config["display_name"]],
				float(followup.get("windup", 0.0)) > 0.0)


# --- Shapes --------------------------------------------------------------------------------

func _check_shapes() -> void:
	var boss: EnemyBase = _spawn_boss("Blue")
	var ring: Dictionary = {"shape": "ring", "inner_radius": 3.0, "radius": 12.0}
	_check("a ring's middle is safe", not boss._offset_in_shape(Vector3(1.5, 0, 0), ring, 0.0))
	_check("a ring's band is not", boss._offset_in_shape(Vector3(0, 0, 7.0), ring, 0.0))
	_check("outside a ring is safe", not boss._offset_in_shape(Vector3(13.0, 0, 0), ring, 0.0))

	var line: Dictionary = {"shape": "line", "length": 14.0, "width": 1.6}
	_check("a line hits along its length", boss._offset_in_shape(Vector3(0.3, 0, 10.0), line, 0.0))
	_check("a line misses beside it", not boss._offset_in_shape(Vector3(1.5, 0, 5.0), line, 0.0))
	_check("a line misses behind its origin", not boss._offset_in_shape(Vector3(0, 0, -3.0), line, 0.0))
	_check("a line follows its yaw", boss._offset_in_shape(Vector3(10.0, 0, 0.0), line, PI * 0.5))

	var fan: Dictionary = {"shape": "line", "lines": [-25.0, 0.0, 25.0], "length": 14.0, "width": 1.6}
	var off_axis: Vector3 = Vector3(sin(deg_to_rad(25.0)), 0, cos(deg_to_rad(25.0))) * 9.0
	_check("a fan hits on its side lance", boss._offset_in_shape(off_axis, fan, 0.0))
	var between: Vector3 = Vector3(sin(deg_to_rad(12.5)), 0, cos(deg_to_rad(12.5))) * 9.0
	_check("a fan misses between its lances", not boss._offset_in_shape(between, fan, 0.0))

	var cross: Dictionary = {"shape": "cross", "length": 16.0, "width": 2.0}
	_check("a cross hits on an arm, either side", boss._offset_in_shape(Vector3(-7.0, 0, 0.2), cross, 0.0))
	_check("a cross misses on the diagonal", not boss._offset_in_shape(Vector3(4.0, 0, 4.0), cross, 0.0))

	var cone: Dictionary = {"shape": "cone", "radius": 7.5, "angle": 130.0}
	_check("a cone misses behind", not boss._offset_in_shape(Vector3(0, 0, -3.0), cone, 0.0))
	_check("a cone turned 180 degrees hits behind", boss._offset_in_shape(Vector3(0, 0, -3.0), cone, PI))
	boss.free()


# --- Phases --------------------------------------------------------------------------------

func _check_phase_thresholds() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	_check("a boss starts in phase 1", boss.boss_phase == 1)
	boss.take_damage(boss.health - boss.enemy_data.health * (GameSettings.boss_phase2_threshold - 0.01))
	_check("crossing the first threshold enters phase 2", boss.boss_phase == 2, "%d" % boss.boss_phase)
	_check("...and queues a transition", boss._pending_phase_transition)
	var meteor: int = _index_of("Red", "Meteor Strike", 2)
	_check("phase 2's new special is ready soon after",
		boss._special_cooldowns[meteor] <= GameSettings.boss_phase_special_delay + 0.01,
		"%.1f" % boss._special_cooldowns[meteor])
	boss.heal(boss.enemy_data.health)
	_check("healing back up does not leave phase 2", boss.boss_phase == 2)
	boss.free()

	var jump: EnemyBase = _spawn_boss("Blue")
	jump.take_damage(jump.enemy_data.health * 0.8)
	_check("one big hit across both lines goes straight to phase 3", jump.boss_phase == 3, "%d" % jump.boss_phase)
	jump.free()

	var enraged: EnemyBase = _spawn_boss("Green", "Enrage")
	enraged.take_damage(enraged.health - enraged.enemy_data.health * 0.7)
	_check("Enrage reaches phase 2 early", enraged.boss_phase == 2, "%d" % enraged.boss_phase)
	var plain: EnemyBase = _spawn_boss("Green")
	plain.take_damage(plain.health - plain.enemy_data.health * 0.7)
	_check("...where a plain boss is still in phase 1", plain.boss_phase == 1, "%d" % plain.boss_phase)
	enraged.free()
	plain.free()


func _check_transition() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	var fake: _FakePlayer = _fake_player(Vector3(0, 0, 4.0))
	boss.take_damage(boss.health - boss.enemy_data.health * 0.5)
	var banners: Array[String] = []
	var probe: Callable = func(_lane: String, message: String, _tint: Color) -> void: banners.append(message)
	SignalBus.lane_warning_requested.connect(probe)
	boss._begin_phase_transition()
	SignalBus.lane_warning_requested.disconnect(probe)
	_check("the transition is a telegraphed special", boss._is_special_active and boss._cast_is_transition)
	_check("the transition holds the boss for its full length",
		boss._cast_end_time >= GameSettings.boss_phase_transition_seconds - 0.001, "%.2f" % boss._cast_end_time)
	_check("the phase is announced by name", not banners.is_empty() and banners[0].contains("KINDLED"), str(banners))
	boss._resolve_special()
	_check("the shockwave hits whoever stayed close", fake.damage_taken > 0.0)
	boss.free()
	_clear_fakes()


# --- Red -----------------------------------------------------------------------------------

func _count_hazards() -> int:
	var effects: Node = _scene.get_node_or_null("Effects")
	if effects == null:
		return 0
	return effects.get_children().filter(func(n: Node) -> bool: return n is BossHazard and not n.is_queued_for_deletion()).size()


func _check_meteors() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	_set_phase(boss, 2)
	var near: _FakePlayer = _fake_player(Vector3(0, 0, 6.0))
	var far: _FakePlayer = _fake_player(Vector3(18.0, 0, 0.0))
	var meteor: int = _index_of("Red", "Meteor Strike", 2)
	_check("Meteor Strike is legal against a player standing off", boss._special_eligible(boss._specials[meteor], 30.0))
	var hazards_before: int = _count_hazards()
	boss._begin_special(meteor)
	var strike: Dictionary = boss._cast_strikes[0]
	_check("a meteor falls under every player, plus one more", (strike["centers"] as Array).size() == 3,
		"%d" % (strike["centers"] as Array).size())
	boss._resolve_special()
	_check("the far player is hit", far.damage_taken > 0.0)
	_check("the near player is hit", near.damage_taken > 0.0)
	_check("every meteor leaves burning ground", _count_hazards() - hazards_before == 3,
		"%d" % (_count_hazards() - hazards_before))
	boss.free()
	_clear_fakes()


func _check_unbound_whirlwind() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	_set_phase(boss, 3)
	_fake_player(Vector3(0, 0, 8.0))
	var index: int = _index_of("Red", "Unbound Whirlwind", 3)
	_check("phase 3 drops the standing Whirlwind", not BossDatabase.special_in_phase(boss._specials[0], 3))
	boss._begin_special(index)
	_check("the Unbound Whirlwind lands three times", boss._cast_strikes.size() == 3, "%d" % boss._cast_strikes.size())
	_check("it walks while it spins", String(boss._cast_move.get("mode", "")) == "follow")
	for strike: Dictionary in boss._cast_strikes:
		_check("each spin has its own readable tell",
			float(strike["hit"]) - float(strike["tele"]) >= GameSettings.boss_modifier_min_windup_seconds - 0.001)
	# Run the whole timeline: it should end exhausted.
	for _step: int in range(400):
		if not boss._is_special_active:
			break
		boss._process_special(0.05)
	_check("surviving it leaves the giant exposed", boss._exhausted_timer > 0.0, "%.2f" % boss._exhausted_timer)
	var health_before: float = boss.health
	boss.take_damage(100.0)
	_check("an exposed boss takes extra damage", absf((health_before - boss.health) - 150.0) < 0.5,
		"%.1f" % (health_before - boss.health))
	boss.free()
	_clear_fakes()


# --- Blue ----------------------------------------------------------------------------------

func _check_ice_lances_and_absolute_zero() -> void:
	var boss: EnemyBase = _spawn_boss("Blue")
	_set_phase(boss, 3)
	var fake: _FakePlayer = _fake_player(Vector3(0, 0, 8.0))
	var lances: int = _index_of("Blue", "Ice Lances", 3)
	boss._begin_special(lances)
	_check("Ice Lances draws three lances", boss._telegraphs_for(boss._cast_strikes[0]).size() == 3)
	boss._resolve_special()
	_check("the centre lance hits the player it was aimed at", fake.damage_taken > 0.0)
	boss._cancel_special()

	var zero: int = _index_of("Blue", "Absolute Zero", 3)
	fake.damage_taken = 0.0
	fake.global_position = ORIGIN + Vector3(0, 0, 1.5)
	boss._begin_special(zero)
	_check("Absolute Zero is a ring with a followup", boss._cast_strikes.size() == 2)
	boss._resolve_special()
	_check("standing inside Absolute Zero is safe", fake.damage_taken == 0.0, "%.1f" % fake.damage_taken)
	var second: Dictionary = boss._cast_strikes[1]
	_check("the followup comes after the ring lands", float(second["tele"]) >= float(boss._cast_strikes[0]["hit"]))
	boss._cancel_special()

	var sweep: Dictionary = boss._specials[0]
	fake.slowed = 0.0
	fake.global_position = ORIGIN + Vector3(0, 0, 4.0)
	boss._begin_special(0)
	var hazards_before: int = _count_hazards()
	boss._resolve_special()
	_check("Glacial Sweep slows whoever it catches", fake.slowed >= float(sweep["slow"]) - 0.01, "%.1f" % fake.slowed)
	_check("from phase 2 it leaves a frozen ring", _count_hazards() - hazards_before == 1)
	boss.free()
	_clear_fakes()


# --- Green ---------------------------------------------------------------------------------

func _check_leap() -> void:
	var boss: EnemyBase = _spawn_boss("Green")
	_set_phase(boss, 3)
	_fake_player(Vector3(0, 0, 5.0))
	var far: _FakePlayer = _fake_player(Vector3(0, 0, 16.0))
	var leap: int = _index_of("Green", "Uprooting Leap", 3)
	boss._begin_special(leap)
	var strike: Dictionary = boss._cast_strikes[0]
	var landing: Vector3 = (strike["centers"] as Array)[0]
	_check("the leap lands on the farthest player", landing.distance_to(far.global_position) < 0.1)
	_check("the leap travels there", String(boss._cast_move.get("mode", "")) == "leap")
	_check("phase 3 adds two aftershock rings", boss._cast_strikes.size() == 3, "%d" % boss._cast_strikes.size())
	_check("an aftershock rolls out from the landing",
		String((boss._cast_strikes[1]["cfg"] as Dictionary).get("anchor", "")) == "same")
	boss._resolve_special()
	_check("the landing slows the player it hits", far.slowed > 0.0)
	boss.free()
	_clear_fakes()


func _sapling_count() -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool:
		return e.has_meta("sapling") and not (e as EnemyBase).is_dying).size()


func _check_saplings() -> void:
	var boss: EnemyBase = _spawn_boss("Green")
	var before: int = _sapling_count()
	boss.take_damage(boss.health - boss.enemy_data.health * 0.5)
	boss._begin_phase_transition()
	boss._resolve_special()
	_check("phase 2 grows the saplings", _sapling_count() - before == GameSettings.boss_sapling_count,
		"%d" % (_sapling_count() - before))
	var sapling: EnemyBase = null
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if e.has_meta("sapling") and (e as EnemyBase).sapling_boss == boss:
			sapling = e
			break
	_check("a sapling knows its treant", sapling != null)
	if sapling != null:
		_check("a sapling is rooted", sapling.enemy_data.speed == 0.0)
		var wears_treant: bool = sapling.get_children().any(func(c: Node) -> bool:
			return c.scene_file_path == BossDatabase.VISUAL_SCENES["Green"])
		_check("a sapling wears the treant's own model", wears_treant)
		_check("a sapling is a small copy of its treant", sapling.scale.y < boss.scale.y * 0.5,
			"%.2f vs boss %.2f" % [sapling.scale.y, boss.scale.y])
		_check("a sapling can still swing", sapling.visual_anim_player != null and sapling.visual_anim_player.has_animation("attack"))
		var health_before: float = boss.health
		sapling._wither_sapling()
		_check("a sapling left standing heals the treant", boss.health > health_before,
			"%.1f -> %.1f" % [health_before, boss.health])
		_check("a withered sapling pays nothing", sapling._skip_kill_rewards)
	boss.free()


# --- White ---------------------------------------------------------------------------------

func _check_shield_wall() -> void:
	var boss: EnemyBase = _spawn_boss("White")
	var front: _FakePlayer = _fake_player(Vector3(0, 0, 5.0))
	var behind: _FakePlayer = _fake_player(Vector3(0, 0, -5.0))
	var before: float = boss.health
	boss.take_damage(100.0, front)
	_check("phase 1 has no shield", absf((before - boss.health) - 100.0) < 0.5)
	_set_phase(boss, 2)
	before = boss.health
	boss.take_damage(100.0, front)
	var expected: float = 100.0 * (1.0 - GameSettings.boss_shield_wall_reduction)
	_check("the shield turns aside a hit from the front", absf((before - boss.health) - expected) < 0.5,
		"%.1f" % (before - boss.health))
	before = boss.health
	boss.take_damage(100.0, behind)
	_check("a hit from behind lands in full", absf((before - boss.health) - 100.0) < 0.5,
		"%.1f" % (before - boss.health))
	boss.free()
	_clear_fakes()


func _check_consecration() -> void:
	var boss: EnemyBase = _spawn_boss("White")
	_set_phase(boss, 3)
	var index: int = _index_of("White", "Consecration", 3)
	_check("Consecration is legal once hurt", boss._special_eligible(boss._specials[index], 999.0))
	var twin: int = _index_of("White", "Twin Slash", 3)
	boss._begin_special(twin)
	_check("Twin Slash swings back the other way",
		absf(float(boss._cast_strikes[1]["cfg"].get("yaw_offset", 0.0)) - 180.0) < 0.1)
	boss._cancel_special()

	# Left alone, it heals.
	boss._begin_special(index)
	var health_before: float = boss.health
	for _step: int in range(200):
		if not boss._is_special_active:
			break
		boss._process_special(0.05)
	_check("an unbroken Consecration heals", boss.health > health_before,
		"%.1f -> %.1f" % [health_before, boss.health])

	# Hit hard enough while kneeling, it breaks and leaves him open.
	boss._special_cooldowns[index] = 0.0
	boss._begin_special(index)
	# From behind HIS facing, wherever kneeling turned him - the shield is still up.
	var behind: _FakePlayer = _fake_player(-boss._yaw_forward(boss.rotation.y) * 5.0)
	boss.take_damage(boss.enemy_data.health * 0.09, behind)
	boss._process_special(0.05)
	_check("enough damage breaks the Consecration", not boss._is_special_active)
	_check("a broken Consecration leaves him exposed", boss._exhausted_timer > 0.0)
	boss.free()
	_clear_fakes()


# --- Black ---------------------------------------------------------------------------------

func _check_charge() -> void:
	var boss: EnemyBase = _spawn_boss("Black")
	var fake: _FakePlayer = _fake_player(Vector3(0, 0, 6.0))
	boss.current_target = fake
	_check("the charge is legal at mid range", boss._special_eligible(boss._specials[0], 6.0))
	boss._begin_special(0)
	boss._resolve_special()
	_check("the charge hits what stands on its line", fake.damage_taken > 0.0)
	_check("and then actually runs the line", String(boss._cast_move.get("mode", "")) == "charge")

	_set_phase(boss, 3)
	boss._cancel_special()
	var weak: _FakePlayer = _fake_player(Vector3(8.0, 0, 0.0))
	weak.hp = 20.0
	var hunt: int = _index_of("Black", "The Hunt", 3)
	boss._begin_special(hunt)
	_check("the Hunt goes for the weakest player", boss._cast_target == weak)
	_check("the Hunt charges twice", boss._cast_strikes.size() == 2)
	boss.free()
	_clear_fakes()


func _check_raise_dead() -> void:
	var boss: EnemyBase = _spawn_boss("Black")
	_set_phase(boss, 2)
	var index: int = _index_of("Black", "Raise Dead", 2)
	_check("nothing to raise, nothing to cast", not boss._special_eligible(boss._specials[index], 0.0)
		or not boss._raisable_corpses(boss._specials[index]).is_empty())

	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var victim: EnemyBase = scene.instantiate()
	victim.set_meta("enemy_color", "Red")
	victim.set_meta("enemy_type", "Melee")
	_scene.add_child(victim)
	victim.global_position = ORIGIN + Vector3(3.0, 0, 0)
	victim.take_damage(99999.0)
	_check("a corpse lies near him", boss._raisable_corpses(boss._specials[index]).has(victim))
	_check("Raise Dead is legal with a corpse near", boss._special_eligible(boss._specials[index], 0.0))

	var enemies_before: int = get_tree().get_nodes_in_group("enemies").size()
	boss._begin_special(index)
	var raising: int = (boss._cast_strikes[0].get("corpses", []) as Array).size()
	_check("the telegraph marks every corpse it will raise",
		boss._telegraphs_for(boss._cast_strikes[0]).size() == raising)
	boss._resolve_special()
	_check("the corpse is used up", not is_instance_valid(victim) or victim.is_queued_for_deletion())
	_check("every corpse it marked gets back up", get_tree().get_nodes_in_group("enemies").size() == enemies_before + raising,
		"%d -> %d, %d marked" % [enemies_before, get_tree().get_nodes_in_group("enemies").size(), raising])

	# Lifelink from phase 2: a landed hit heals him.
	var fake: _FakePlayer = _fake_player(Vector3(0, 0, 2.0))
	boss.current_target = fake
	boss.take_damage(boss.enemy_data.health * 0.1)
	var health_before: float = boss.health
	boss._begin_special(1)
	boss._resolve_special()
	_check("phase 2's hits feed him", fake.damage_taken > 0.0 and boss.health > health_before,
		"%.1f -> %.1f" % [health_before, boss.health])
	boss.free()
	_clear_fakes()


# --- Network -------------------------------------------------------------------------------

## Everything a telegraph description holds has to survive an RPC: no node, no resource.
func _check_fx_payload_is_plain_data() -> void:
	var plain: bool = true
	for color: String in ["Red", "Blue", "Green", "White", "Black"]:
		var boss: EnemyBase = _spawn_boss(color)
		_set_phase(boss, 3)
		_fake_player(Vector3(0, 0, 6.0))
		for i: int in range(boss._specials.size()):
			if not BossDatabase.special_in_phase(boss._specials[i], 3):
				continue
			boss._begin_special(i)
			for desc: Dictionary in boss._telegraphs_for(boss._cast_strikes[0]):
				for key: Variant in desc:
					if typeof(desc[key]) == TYPE_OBJECT:
						plain = false
			boss._cancel_special()
		boss.free()
		_clear_fakes()
	_check("telegraph descriptions are plain data", plain)


# --- Regeneration ----------------------------------------------------------------------------

func _check_regeneration() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	boss._tick_boss_regen(30.0)
	_check("a boss at full health has nothing to regenerate", not boss.boss_regenerating)
	boss.take_damage(boss.enemy_data.health * 0.5)
	var hurt: float = boss.health
	for _i: int in range(int(GameSettings.boss_regen_delay / 0.5) - 1):
		boss._tick_boss_regen(0.5)
	_check("no regeneration before the delay", boss.health == hurt and not boss.boss_regenerating,
		"%.1f -> %.1f" % [hurt, boss.health])
	boss._tick_boss_regen(0.5)
	boss._tick_boss_regen(1.0)
	_check("left alone past the delay, it regenerates", boss.boss_regenerating and boss.health > hurt,
		"%.1f -> %.1f" % [hurt, boss.health])
	var expected: float = boss.enemy_data.health * GameSettings.boss_regen_pct_per_second
	_check("at the configured rate", absf((boss.health - hurt) - expected) < expected * 0.6,
		"healed %.1f, ~%.1f per second" % [boss.health - hurt, expected])
	boss.take_damage(1.0)
	_check("any hit stops it at once", not boss.boss_regenerating and boss._since_boss_hit == 0.0)
	var phase_before: int = boss.boss_phase
	boss.heal(boss.enemy_data.health)
	_check("healing back up never undoes a phase", boss.boss_phase == phase_before)
	boss.free()


# --- Boss bar ----------------------------------------------------------------------------------

func _check_boss_bar() -> void:
	var hud: Node = _scene.get_node_or_null("HUD")
	_check("the HUD is there to test", hud != null and hud.has_method("refresh_boss_bars"))
	if hud == null:
		return
	hud.refresh_boss_bars()
	_check("no boss, no bar", not hud._boss_bar_box.visible)

	var boss: EnemyBase = _spawn_boss("Blue", "Enrage")
	hud.refresh_boss_bars()
	var row: Dictionary = hud._boss_rows[0]
	_check("a boss gets a bar", hud._boss_bar_box.visible and (row["panel"] as Control).visible)
	var name_text: String = (row["name"] as Label).text
	_check("the bar names the boss and its modifier", name_text.contains("FROST GIANT") and name_text.contains("ENRAGE"), name_text)
	_check("the bar starts in phase 1", (row["phase"] as Label).text.begins_with("PHASE 1"), (row["phase"] as Label).text)

	boss.take_damage(boss.health - boss.enemy_data.health * 0.6)
	hud.refresh_boss_bars()
	var phase_text: String = (row["phase"] as Label).text
	_check("the bar names the new phase", phase_text.contains("PHASE 2") and phase_text.contains("WINTER'S GRIP"), phase_text)
	_check("the bar shows the boss's health", absf((row["bar"] as ProgressBar).value - boss.health) < 0.5)
	_check("Enrage's earlier phase lines are the ones marked",
		absf(boss.phase_thresholds()[0] - GameSettings.boss_modifier_enrage_phase2_threshold) < 0.001)
	_check("not regenerating, no regen tag", (row["regen"] as Label).modulate.a == 0.0)
	boss.boss_regenerating = true
	hud.refresh_boss_bars()
	_check("regenerating shows on the bar", (row["regen"] as Label).modulate.a > 0.0)

	var second: EnemyBase = _spawn_boss("Black")
	hud.refresh_boss_bars()
	_check("two bosses, two bars", (hud._boss_rows[1]["panel"] as Control).visible)
	var viewport_width: float = hud.get_viewport().get_visible_rect().size.x
	var box_rect: Rect2 = Rect2(hud._boss_bar_box.position, Vector2(hud._boss_bar_box.size.x, 1.0))
	# A headless run has a token 64-pixel viewport; on-screen only means something at a real size.
	if viewport_width >= 640.0:
		_check("the bars sit on screen", box_rect.position.x >= 0.0 and box_rect.end.x <= viewport_width,
			"%s in %.0f" % [box_rect, viewport_width])
	_check("the bars clear the crystal readout", box_rect.position.x > hud.health_bar.get_global_rect().end.x,
		"%.0f vs %.0f" % [box_rect.position.x, hud.health_bar.get_global_rect().end.x])
	_check("the banner moves below the bars", hud._warning_panel.position.y >= hud._boss_bar_box.position.y + hud._boss_bar_box.get_combined_minimum_size().y)
	second.free()
	boss.free()
	hud.refresh_boss_bars()
	_check("the bar goes once the boss does", not hud._boss_bar_box.visible)


# --- World tells and telegraph styles ----------------------------------------------------------

func _live_tells(boss: EnemyBase) -> Array:
	return boss._cast_tells.filter(func(t: BossTell) -> bool: return is_instance_valid(t) and not t.is_queued_for_deletion())


func _check_tells_and_styles() -> void:
	var keep_style: String = GameSettings.attack_indicator_style
	var keep_shown: bool = GameSettings.show_attack_indicators

	var boss: EnemyBase = _spawn_boss("Red")
	_set_phase(boss, 2)
	_fake_player(Vector3(-5, 0, 6))
	_fake_player(Vector3(6, 0, 9))
	var meteor: int = _index_of("Red", "Meteor Strike", 2)

	GameSettings.show_attack_indicators = false
	boss._begin_special(meteor)
	var centers: int = (boss._cast_strikes[0]["centers"] as Array).size()
	_check("a meteor falls for every strike centre", _live_tells(boss).size() == centers,
		"%d tells, %d centres" % [_live_tells(boss).size(), centers])
	_check("the tells stay with the ground telegraphs switched off", boss._cast_indicators.is_empty() and not _live_tells(boss).is_empty())
	var tell: BossTell = _live_tells(boss)[0]
	_check("a meteor tell has a fireball and a shadow", tell._fireball != null and tell._shadow != null)
	tell.freeze_at(0.5)
	_check("the meteor is still in the air halfway through", tell._fireball.global_position.y > tell.global_position.y + 3.0)
	boss._cancel_special()
	_check("cancelling takes the tells down too", _live_tells(boss).is_empty())

	GameSettings.show_attack_indicators = true
	for style: String in AttackIndicator.STYLES:
		GameSettings.attack_indicator_style = style
		boss._special_cooldowns[meteor] = 0.0
		boss._begin_special(meteor)
		var indicator: AttackIndicator = boss._cast_indicators[0]
		_check("the %s style draws" % style, indicator != null and indicator.get_child_count() > 0)
		_check("the %s style uses %s" % [style, "the classic meshes" if style == "classic" else "the telegraph shader"],
			(indicator._shader_material == null) == (style == "classic"))
		boss._cancel_special()
	boss.free()
	_clear_fakes()

	# Every attack that names a tell gets one, and only those do.
	var kinds_seen: Dictionary = {}
	for color: String in ["Red", "Blue", "Green", "White", "Black"]:
		var b: EnemyBase = _spawn_boss(color)
		_set_phase(b, 3)
		_fake_player(Vector3(0, 0, 7))
		b.current_target = _fakes[0]
		for i: int in range(b._specials.size()):
			var config: Dictionary = b._specials[i]
			if not BossDatabase.special_in_phase(config, 3) and not BossDatabase.special_in_phase(config, 2):
				continue
			b._begin_special(i)
			var named: bool = config.has("tell")
			if named:
				kinds_seen[String(config["tell"])] = true
				_check("%s '%s' raises its %s tell" % [color, config["display_name"], config["tell"]], not _live_tells(b).is_empty())
			elif String(config.get("kind", "")) == "":
				_check("%s '%s' has no world tell" % [color, config["display_name"]], _live_tells(b).is_empty())
			b._cancel_special()
		b.free()
		_clear_fakes()
	_check("every tell kind is used by some attack", kinds_seen.size() >= 5, str(kinds_seen.keys()))

	GameSettings.attack_indicator_style = keep_style
	GameSettings.show_attack_indicators = keep_shown
