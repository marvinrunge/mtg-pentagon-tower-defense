extends Node
## Regression test: the Tab scoreboard and message log.
##
## Run with:  godot --headless --path . res://tools/tests/scoreboard.tscn
##
## Two things worth asserting rather than looking at:
##
## The STATS have to be recorded at the points that actually know whose they are - a kill is
## credited from the fatal hit, healing from the caster, a death only once nobody revived
## them. Each of those is a separate hook in a different file, and a silent zero looks exactly
## like a player who did nothing.
##
## The LOG has to capture every announcement. It listens to the existing banner signals rather
## than asking each emitter to also log, so what this checks is that the wiring covers all of
## them - a new announcement that reaches the banner and misses the log is the failure that
## design is meant to prevent.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _hud: Node = null
var _player: Node = null
var _scene: Node = null


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


func _spawn_enemy(offset: Vector3) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	_scene.add_child(enemy)
	enemy.global_position = (_player as Node3D).global_position + offset
	return enemy


func _run() -> void:
	_scene = get_tree().current_scene
	_hud = _scene.find_child("HUD", true, false)
	_player = PlayerRegistry.get_local()
	if _scene == null or _hud == null or _player == null:
		print("TEST RESULT: FAIL (no scene, HUD or player)")
		return

	_check_stats()
	_check_log()
	_check_panel()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)


func _check_stats() -> void:
	print("STATS")
	for key: String in _player.stats.keys():
		_player.stats[key] = 0 if _player.stats[key] is int else 0.0

	# A kill and the damage that caused it, through the real path: EnemyBase.take_damage is
	# what credits both, and it is the only place that knows the hit was fatal.
	var victim: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	var victim_health: float = victim.health
	victim.take_damage(victim_health * 0.5, _player)
	_check("damage dealt is recorded", _player.stats["damage_dealt"] > 0.0,
		"%.1f" % _player.stats["damage_dealt"])
	victim.take_damage(victim_health, _player)
	_check("a kill is credited to whoever landed it", _player.stats["kills"] == 1,
		"%d" % _player.stats["kills"])
	# Overkill must not inflate the total: EnemyBase clamps to the health actually removed.
	_check("overkill is not counted as damage", _player.stats["damage_dealt"] <= victim_health + 0.01,
		"%.1f of %.1f max" % [_player.stats["damage_dealt"], victim_health])
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.free()

	# Damage taken counts what reached HEALTH, not what a shield ate.
	_player.hp = _player.max_hp
	_player.protection_shield = 0.0
	_player.rhystic_shield = 0.0
	_player.glorious_anthem_shield = 0.0
	_player.take_damage(20.0)
	_check("damage taken is recorded", is_equal_approx(_player.stats["damage_taken"], 20.0),
		"%.1f" % _player.stats["damage_taken"])

	# Healing is credited to the caster, and only for what was actually restored.
	_player.hp = _player.max_hp * 0.5
	var restored: float = _player.heal(15.0, false)
	_player._credit_heal(_player, restored)
	_check("self healing is recorded", is_equal_approx(_player.stats["heal_self"], 15.0),
		"%.1f" % _player.stats["heal_self"])
	_player.hp = _player.max_hp
	_player._credit_heal(_player, _player.heal(500.0, false))
	_check("overhealing is not counted", is_equal_approx(_player.stats["heal_self"], 15.0),
		"%.1f" % _player.stats["heal_self"])

	# Going down and dying are separate: a revive means the down never became a death.
	_player.hp = _player.max_hp
	_player.die()
	_check("going down is recorded", _player.stats["downs"] == 1, "%d" % _player.stats["downs"])
	_check("going down is not yet a death", _player.stats["deaths"] == 0, "%d" % _player.stats["deaths"])
	_player.revive()
	_check("a revive leaves no death", _player.stats["deaths"] == 0, "%d" % _player.stats["deaths"])
	_player.die()
	_player.respawn_at_base()
	_check("respawning is a death", _player.stats["deaths"] == 1, "%d" % _player.stats["deaths"])
	_player.hp = _player.max_hp


func _check_log() -> void:
	print("LOG")
	# Every announcement channel, driven through the signals the banners themselves use.
	var before: int = _hud._message_log.size()
	SignalBus.mission_announced.emit("Protect the Crystal!")
	SignalBus.lane_warning_requested.emit("Red", "RED BOSS HAS ARRIVED", Color.RED)
	SignalBus.wave_started.emit(3)
	SignalBus.wave_completed.emit(3)
	SignalBus.upkeep_started.emit(20.0)
	var added: int = _hud._message_log.size() - before
	_check("every announcement reaches the log", added == 5, "%d of 5" % added)

	var texts: Array[String] = []
	for entry: Dictionary in _hud._message_log:
		texts.append(String(entry["text"]))
	_check("the boss arrival is in the log", texts.has("RED BOSS HAS ARRIVED"),
		"last=%s" % texts[-1] if not texts.is_empty() else "empty")
	_check("the mission is in the log", texts.has("Mission: Protect the Crystal!"))

	# The log is a recent-history readout, not a transcript: it must not grow forever.
	for i: int in range(HUD.MESSAGE_LOG_MAX + 25):
		_hud.log_message("filler %d" % i, Color.WHITE)
	_check("the log is capped", _hud._message_log.size() == HUD.MESSAGE_LOG_MAX,
		"%d entries" % _hud._message_log.size())
	_check("the cap drops the OLDEST", String(_hud._message_log[-1]["text"]) == "filler %d" % (HUD.MESSAGE_LOG_MAX + 24),
		String(_hud._message_log[-1]["text"]))


func _check_panel() -> void:
	print("PANEL")
	_check("the panel starts hidden", not _hud._tab_panel.visible)
	# Held, not toggled: showing twice in a row must leave it shown, and the release is what
	# puts it away. A toggle would hide it on the second press.
	_hud._set_tab_panel_shown(true)
	_hud._set_tab_panel_shown(true)
	_check("holding keeps it up", _hud._tab_panel.visible)
	_check("the wave readout comes with it", _hud._wave_panel.visible)
	# One header row plus one row per player.
	var rows: int = _hud._scoreboard_rows.get_child_count()
	_check("the scoreboard has a row per player", rows == PlayerRegistry.players.size() + 1,
		"%d rows for %d players" % [rows, PlayerRegistry.players.size()])
	_check("the log rendered its lines", _hud._log_rows.get_child_count() > 0,
		"%d" % _hud._log_rows.get_child_count())
	_hud._set_tab_panel_shown(false)
	_check("releasing puts it away", not _hud._tab_panel.visible)
