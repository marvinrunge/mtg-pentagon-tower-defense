extends Node
## Soak test: each boss fights through all three phases in the real game loop.
##
## Run with:  godot --headless --path . res://tools/tests/boss_soak.tscn
##
## boss_phases.gd drives every mechanic by hand; this one lets _physics_process do it. Each
## boss is spawned in its own lane with two stand-in players - one in its face, one standing
## off - and is worn down steadily until it dies. What is checked is what only the real loop
## can show: that it reaches every phase, actually USES its phase specials on its own, gets
## exposed at least once, and hurts the player who stands off. Script errors along the way
## show up in the log; read it, not only the verdict.

const COLORS: Array[String] = ["Red", "Blue", "Green", "White", "Black"]
## Game seconds from full health to dead. Long enough for every phase to get several turns.
const FIGHT_SECONDS := 45.0
const TIME_SCALE := 3.0

var _frames: int = 0
var _failures: Array[String] = []
var _scene: Node = null
var _color_index: int = -1
var _boss: EnemyBase = null
var _close: Node3D = null
var _far: Node3D = null
var _elapsed: float = 0.0
var _seen_specials: Dictionary = {}
var _seen_phases: Dictionary = {}
var _was_exposed: bool = false
var _last_cast: String = ""
var _far_replace_timer: float = 0.0


class _FakePlayer:
	extends Node3D
	var damage_taken: float = 0.0
	var is_downed: bool = false
	var hp: float = 100.0
	var max_hp: float = 100.0
	func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false, _exile_on_kill: bool = false) -> void:
		damage_taken += amount
	func apply_slow(_duration: float) -> void:
		pass


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _physics_process(delta: float) -> void:
	_frames += 1
	if _frames < 90:
		return
	if _scene == null:
		_scene = get_tree().current_scene
		for node: Node in get_tree().get_nodes_in_group("player"):
			node.remove_from_group("player")
		Engine.time_scale = TIME_SCALE
		_next_boss()
		return
	if _boss == null:
		return
	_elapsed += delta
	_step_fight(delta)


func _next_boss() -> void:
	_color_index += 1
	if _color_index >= COLORS.size():
		_finish()
		return
	var color: String = COLORS[_color_index]
	print("%s" % color.to_upper())
	var spawners: Array = _scene.get("enemy_spawners")
	var lane: int = ["White", "Blue", "Black", "Red", "Green"].find(color)
	var crystal: Node3D = _scene.get_node("NavigationRegion3D/CrystalAnchor") as Node3D
	var start: Vector3 = crystal.global_position.lerp((spawners[lane] as Node3D).global_position, 0.6)

	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	_boss = scene.instantiate()
	_boss.set_meta("enemy_color", color)
	_boss.set_meta("enemy_type", "Boss")
	_scene.get_node("Enemies").add_child(_boss)
	_boss.global_position = start + Vector3(0.0, 2.0, 0.0)

	_close = _make_fake()
	_far = _make_fake()
	_elapsed = 0.0
	_seen_specials = {}
	_seen_phases = {1: true}
	_was_exposed = false
	_last_cast = ""
	_far_replace_timer = 0.0


func _make_fake() -> Node3D:
	var fake := _FakePlayer.new()
	fake.add_to_group("player")
	_scene.add_child(fake)
	return fake


func _step_fight(delta: float) -> void:
	if not is_instance_valid(_boss) or _boss.is_dying:
		_report()
		return
	# The close one stays in its face and holds its attention. The far one stands still, off
	# to one side, and is only moved back out every few seconds - a stand-in that tracked the
	# boss every frame would side-step every telegraph aimed at it.
	var forward: Vector3 = _boss._yaw_forward(_boss.rotation.y)
	_close.global_position = _boss.global_position + forward * 3.5
	_far_replace_timer -= delta
	if _far_replace_timer <= 0.0:
		_far_replace_timer = 6.0
		_far.global_position = _boss.global_position - forward * 15.0
	_boss.taunt_source = _close
	_boss.taunt_timer = 1.0
	# A hurt stand-in, so the Hunt has someone to pick.
	(_far as _FakePlayer).hp = 30.0

	if _boss._is_special_active:
		var name: String = String(_boss._special_config.get("display_name", ""))
		if name != _last_cast:
			_seen_specials[name] = true
			_last_cast = name
	else:
		_last_cast = ""
	if _boss._exhausted_timer > 0.0:
		_was_exposed = true
	_seen_phases[_boss.boss_phase] = true

	# Steady damage, from no particular side so the paladin's shield does not bend the clock.
	_boss.take_damage(_boss.enemy_data.health / FIGHT_SECONDS * delta)
	if _elapsed > FIGHT_SECONDS * 2.5:
		_report()


func _report() -> void:
	var color: String = COLORS[_color_index]
	_check("%s reached phase 3" % color, _seen_phases.has(3), str(_seen_phases.keys()))
	var phase_specials: Array[String] = []
	for config: Dictionary in BossDatabase.get_specials(color):
		if not BossDatabase.special_in_phase(config, 1):
			phase_specials.append(String(config["display_name"]))
	var used: Array = phase_specials.filter(func(n: String) -> bool: return _seen_specials.has(n))
	_check("%s used a phase special on its own" % color, not used.is_empty(), "saw %s" % str(_seen_specials.keys()))
	_check("%s announced its phases with a shockwave" % color, _seen_specials.has(String(BossDatabase.get_phase_config(color)["shockwave"]["display_name"])),
		str(_seen_specials.keys()))
	_check("%s was exposed at least once" % color, _was_exposed)
	# Black answers distance by raising the dead, and Blue's lances go for the NEAREST player -
	# with someone in its face, standing off is genuinely safer from the frost giant.
	if color != "Black" and color != "Blue":
		_check("%s reached the player standing off" % color, (_far as _FakePlayer).damage_taken > 0.0)
	print("       used: %s" % str(_seen_specials.keys()))
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	for fake: Node3D in [_close, _far]:
		if is_instance_valid(fake):
			fake.remove_from_group("player")
			fake.queue_free()
	_next_boss()


func _finish() -> void:
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL")
		for failure: String in _failures:
			print("  " + failure)
	get_tree().quit()
