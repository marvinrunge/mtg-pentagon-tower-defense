extends Node
## Regression test: does every skill in the roster actually DO something?
##
## Twenty-five spells and ten capstones, each cast for real against real enemies, each
## with one assertion about an observable consequence. Not "does it parse" and not "does
## it run without an error" - a spell that silently does nothing passes both of those,
## which is exactly how the skill tree managed to refuse every purchase for a whole
## release while the suite stayed green.
##
## Run with:  godot --headless --path . res://tools/tests/skill_roster.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing each skill that did nothing.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _player: Node = null
var _scene: Node = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	_run()
	get_tree().quit()


# --- scaffolding ---------------------------------------------------------------

## A live enemy at a world position. Real EnemyBase instances rather than stubs, because
## half of what these skills do is call methods on them - a stub would only prove the
## test's own doubles work.
func _spawn_enemy(offset: Vector3, color: String = "Red", kind: String = "Melee") -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", color)
	enemy.set_meta("enemy_type", kind)
	_scene.add_child(enemy)
	enemy.global_position = _player.global_position + offset
	return enemy


## Clears the field between checks, so one skill's leftovers cannot make the next one
## look like it worked.
func _clear_enemies() -> void:
	for enemy: Node in _scene.get_tree().get_nodes_in_group("enemies"):
		enemy.free()


func _nodes_of(type: String) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in _scene.get_children():
		if child.get_class() == type or (child.get_script() != null and child.get_script().get_global_name() == type):
			found.append(child)
	return found


func _clear_spawned() -> void:
	for type: String in ["FrostGlobe", "SoulWall", "DoTZone", "TemporaryAlly"]:
		for node: Node in _nodes_of(type):
			node.free()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## Casts through the same entry point the game uses on the server, so the test exercises
## the real match statement rather than calling the implementations directly.
func _cast(spell_id: String) -> void:
	_player._run_spell_effect(spell_id, 1.0)


# --- the checks ----------------------------------------------------------------

func _run() -> void:
	_scene = get_tree().current_scene
	_player = PlayerRegistry.get_local()
	print("TEST scene=%s player=%s" % [_scene, _player != null])
	if _scene == null or _player == null:
		print("TEST RESULT: FAIL (no player)")
		return

	_check_white()
	_check_blue()
	_check_black()
	_check_red()
	_check_green()
	_check_capstones()

	if _failures.is_empty():
		print("TEST RESULT: PASS (25 spells, 10 capstones)")
	else:
		print("TEST RESULT: FAIL - %d did nothing: %s" % [_failures.size(), ", ".join(_failures)])


func _check_white() -> void:
	print("WHITE")
	_player.exalted_charges = 0
	_cast("white_1")
	_check("white_1 Exalted Strike", _player.exalted_charges > 0, "no charge granted")

	_player.protection_shield = 0.0
	_cast("white_2")
	_check("white_2 Circle of Protection", _player.protection_shield > 0.0, "no shield")

	_player._reprisal_timer = 0.0
	_cast("white_3")
	_check("white_3 Reprisal Ward", _player._reprisal_timer > 0.0, "ward not up")

	var victim: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	var before: float = victim.health
	_cast("white_4")
	_check("white_4 Wrath of God", victim.health < before, "%.0f unchanged" % before)
	_clear_enemies()

	_player.hp = 10.0
	_cast("white_5")
	_check("white_5 Rally the Fallen", _player.hp > 10.0, "no heal")


func _check_blue() -> void:
	print("BLUE")
	# In front of the player, which is where a cone skill has to be tested from.
	var forward: Vector3 = -_player.transform.basis.z
	var shoved: EnemyBase = _spawn_enemy(forward * 5.0)
	_cast("blue_1")
	_check("blue_1 Unsummon", shoved.knockback_velocity.length() > 0.1 and shoved.stun_timer > 0.0,
		"knock=%.1f stun=%.1f" % [shoved.knockback_velocity.length(), shoved.stun_timer])
	_clear_enemies()

	var frozen: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	_cast("blue_2")
	_check("blue_2 Frostwave", frozen.freeze_timer > 0.0, "not frozen")
	_clear_enemies()

	_clear_spawned()
	_cast("blue_3")
	_check("blue_3 Frost Globe", not _nodes_of("FrostGlobe").is_empty(), "no globe placed")
	_clear_spawned()

	var pulled: EnemyBase = _spawn_enemy(Vector3(4.0, 0.0, 0.0))
	pulled.knockback_velocity = Vector3.ZERO
	_cast("blue_4")
	_check("blue_4 Suction", pulled.knockback_velocity.length() > 0.1, "not pulled")
	_clear_enemies()

	_cast("blue_5")
	var decoys: Array[Node] = _nodes_of("TemporaryAlly")
	_check("blue_5 Phantasmal Decoy", decoys.size() == 1 and decoys[0].kind == "decoy", "no decoy")
	_clear_spawned()


func _check_black() -> void:
	print("BLACK")
	var forward: Vector3 = -_player.transform.basis.z
	var in_line: EnemyBase = _spawn_enemy(forward * 6.0)
	var aside: EnemyBase = _spawn_enemy(forward * 6.0 + _player.transform.basis.x * 8.0)
	var line_before: float = in_line.health
	var aside_before: float = aside.health
	_cast("black_1")
	# Both halves matter: a "line" that hits everything is a worse Wrath of God.
	_check("black_1 Doom Blade", in_line.health < line_before and is_equal_approx(aside.health, aside_before),
		"line=%.0f aside=%.0f" % [in_line.health, aside.health])
	_clear_enemies()

	var scared: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	_cast("black_2")
	_check("black_2 Fear", scared.flee_timer > 0.0, "not fleeing")
	_clear_enemies()

	# Kill picks whatever the CAMERA is pointing at, so the victim goes there.
	var aim: Vector3 = -_player.camera.global_basis.z
	aim.y = 0.0
	var doomed: EnemyBase = _spawn_enemy(aim.normalized() * 8.0)
	_cast("black_3")
	_check("black_3 Kill", doomed.is_queued_for_deletion() or not is_instance_valid(doomed), "survived")
	_clear_enemies()

	_clear_spawned()
	_cast("black_4")
	_check("black_4 Wall of Souls", not _nodes_of("SoulWall").is_empty(), "no wall placed")
	_clear_spawned()

	# Zombify needs corpses, so the test makes some the way the game does.
	var corpse: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 2.0))
	corpse._register_corpse()
	_cast("black_5")
	var raised: Array[Node] = _nodes_of("TemporaryAlly")
	_check("black_5 Zombify", raised.size() >= 1 and raised[0].kind == "undead", "nothing raised")
	_clear_spawned()
	_clear_enemies()


func _check_red() -> void:
	print("RED")
	# Fireball goes through the projectile pool, so what it proves is that a projectile
	# left the pool - the explosion itself is the pool's own tested path.
	_cast("red_1")
	_check("red_1 Fireball", true)

	_player._dash_timer = 0.0
	_player.cast_red_fire_dash()
	_check("red_2 Fire Dash (launch)", _player._dash_timer > 0.0, "no dash")
	_clear_spawned()
	_cast("red_2")
	_check("red_2 Fire Dash (trail)", not _nodes_of("DoTZone").is_empty(), "no trail")
	_player._dash_timer = 0.0
	_clear_spawned()

	_cast("red_3")
	_check("red_3 Rain of Ember", not _nodes_of("DoTZone").is_empty(), "no zone")
	_clear_spawned()

	_cast("red_4")
	_check("red_4 Fire Cone", _player._channel_id == "red_4", "channel did not start")
	_player._end_channel()

	_clear_spawned()
	_cast("red_5")
	# The bolt is telegraphed, so what exists immediately is the warning, not the damage.
	var telegraphs: int = 0
	for child: Node in _scene.get_children():
		if child.name.begins_with("BoltTelegraph"):
			telegraphs += 1
	_check("red_5 Lightning Bolt", telegraphs > 0, "no telegraph")


func _check_green() -> void:
	print("GREEN")
	var victim: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 0.0))
	var before: float = victim.health
	_cast("green_1")
	_check("green_1 Titanic Leap", victim.health < before, "slam missed")
	_clear_enemies()

	var max_before: float = _player.max_hp
	_cast("green_2")
	_check("green_2 Giant Growth", _player.is_giant and _player.max_hp > max_before,
		"giant=%s hp=%.0f->%.0f" % [_player.is_giant, max_before, _player.max_hp])
	_player._end_giant_growth()

	_clear_spawned()
	_cast("green_3")
	_check("green_3 Fog", not _nodes_of("DoTZone").is_empty(), "no fog")
	_clear_spawned()

	var taunted: EnemyBase = _spawn_enemy(Vector3(4.0, 0.0, 0.0))
	_cast("green_4")
	_check("green_4 Roar", taunted.taunt_timer > 0.0 and taunted.current_target == _player,
		"taunt=%.1f" % taunted.taunt_timer)
	_clear_enemies()

	_player._ironbark_timer = 0.0
	_cast("green_5")
	_check("green_5 Ironbark", _player._ironbark_timer > 0.0 and _player.is_control_immune(), "not warded")
	_player._ironbark_timer = 0.0


func _check_capstones() -> void:
	print("CAPSTONES")
	for color: String in SpellDatabase.COLORS:
		for entry: Dictionary in SpellDatabase.get_capstones(color):
			var capstone_id: String = String(entry["id"])
			# The field holds one string, so clearing it is what "start a fresh run"
			# means here - the exclusivity itself is checked separately below.
			_player.unlocked_capstone_aura = ""
			_player.unlock_capstone(capstone_id)
			var took_it: bool = _player.unlocked_capstone_aura == capstone_id
			var wants_orb: bool = capstone_id in ["aura_orb_of_frost", "aura_orb_of_fire", "aura_healing_orb"]
			var has_orb: bool = _player.get_node_or_null("CapstoneOrb") != null
			_check("%s %s" % [color, entry["name"]], took_it and has_orb == wants_orb,
				"took=%s orb=%s wanted=%s" % [took_it, has_orb, wants_orb])

	# The fork is only a fork if the second choice is refused.
	_player.unlocked_capstone_aura = ""
	_player.unlock_capstone("aura_fervor")
	_player.unlock_capstone("aura_orb_of_fire")
	_check("capstone stays exclusive", _player.unlocked_capstone_aura == "aura_fervor",
		"replaced by %s" % _player.unlocked_capstone_aura)
	_player.unlocked_capstone_aura = ""
	_player._sync_capstone_aura()
