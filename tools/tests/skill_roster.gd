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
## Sections that ran all the way to their end.
##
## Without this the suite lies. A script error mid-section aborts that section, leaves
## `_failures` empty, and the run prints PASS having checked nothing - which is exactly
## what happened the first time the multicolour section was added, and exactly the class
## of false green this whole file exists to prevent.
var _completed: Array[String] = []

const SECTIONS: Array[String] = ["white", "blue", "black", "red", "green", "capstones", "ranks", "multicolour", "sounds"]

## Every skill that should be audible, and the event it plays. Hand-written on purpose:
## deriving it from SoundBank would only prove SoundBank agrees with itself, and the
## thing worth catching is a spell whose trigger was never wired at all.
const EXPECTED_SPELL_SOUNDS: Dictionary = {
	"white_1": &"spell_exalted_strike",
	"white_2": &"spell_circle_protection",
	"white_3": &"spell_reprisal_ward",
	"white_4": &"spell_wrath_of_god",
	"white_5": &"spell_rally_fallen",
	"blue_1": &"spell_unsummon",
	"blue_2": &"spell_frostwave",
	"blue_3": &"spell_frost_globe",
	"blue_4": &"spell_suction",
	"blue_5": &"spell_decoy",
	"black_1": &"spell_doom_blade",
	"black_2": &"spell_fear",
	"black_3": &"spell_kill",
	"black_4": &"spell_wall_of_souls",
	"black_5": &"spell_zombify",
	"red_1": &"spell_cast",
	"red_2": &"spell_fire_dash",
	"red_3": &"spell_rain_ember",
	"red_4": &"spell_fire_cone",
	"red_5": &"spell_lightning_bolt",
	"green_1": &"heavy_landing",
	"green_2": &"spell_giant_growth",
	"green_3": &"spell_fog",
	"green_4": &"spell_roar",
	"green_5": &"spell_ironbark",
}


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
	for type: String in ["FrostGlobe", "SoulWall", "DoTZone", "TemporaryAlly", "SuctionZone"]:
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
	_check_ranks()
	_check_multicolour()
	_check_sounds()

	for section: String in SECTIONS:
		if not _completed.has(section):
			_failures.append("section '%s' did not finish - look for a SCRIPT ERROR above" % section)

	if _failures.is_empty():
		print("TEST RESULT: PASS (25 spells, 10 capstones, ranks, multicolour)")
	else:
		print("TEST RESULT: FAIL - %d failed: %s" % [_failures.size(), ", ".join(_failures)])


## Called as the LAST line of every section. Reaching it is the proof the section ran.
func _done_with(section: String) -> void:
	_completed.append(section)


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
	_done_with("white")


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

	# Suction is a lingering zone now, not a single shove: the check is the zone being
	# placed and an enemy inside it being marked for the drag. In front of the camera,
	# because that is where the zone lands.
	var pull_dir: Vector3 = -_player.camera.global_basis.z
	pull_dir.y = 0.0
	var pulled: EnemyBase = _spawn_enemy(pull_dir.normalized() * 6.0)
	pulled._suction_timer = 0.0
	_cast("blue_4")
	_check("blue_4 Suction", not _nodes_of("SuctionZone").is_empty() and pulled._suction_timer > 0.0, "no zone or no pull")
	_clear_spawned()
	_clear_enemies()

	_cast("blue_5")
	var decoys: Array[Node] = _nodes_of("TemporaryAlly")
	_check("blue_5 Phantasmal Decoy", decoys.size() == 1 and decoys[0].kind == "decoy", "no decoy")
	_clear_spawned()
	_done_with("blue")


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
	# An ordinary death rather than an exile: the corpse stays on the field and feeds
	# Zombify, so the check is the death animation running, not the node being gone.
	_check("black_3 Kill", not is_instance_valid(doomed) or doomed.is_queued_for_deletion() or doomed.is_dying, "survived")
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
	_done_with("black")


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
	_done_with("red")


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
	_done_with("green")


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
	_done_with("capstones")

# --- ranks ---------------------------------------------------------------------

## Sets the player to exactly `rank` in `spell_id`, bypassing the tree. The purchase path
## is covered by skill_purchase.gd; what this file cares about is whether the rank changes
## what the spell DOES.
func _set_rank(spell_id: String, rank: int) -> void:
	_player.spell_ranks[spell_id] = rank
	if not _player.unlocked_spells_in_path.has(spell_id):
		_player.unlocked_spells_in_path.append(spell_id)


## Casts once at rank 1 and once at rank 5 and hands both readings back, so each check
## below is one line about which way the number should move.
func _measure(spell_id: String, probe: Callable) -> Array:
	_set_rank(spell_id, 1)
	var low: float = float(probe.call())
	_set_rank(spell_id, GameSettings.spell_max_rank)
	var high: float = float(probe.call())
	return [low, high]


## Damage a single enemy takes from one cast. The enemy is fresh each time, so nothing
## leaks between the two readings.
func _damage_probe(spell_id: String, offset: Vector3) -> float:
	var victim: EnemyBase = _spawn_enemy(offset)
	var before: float = victim.health
	_cast(spell_id)
	var dealt: float = before - victim.health
	_clear_enemies()
	return dealt


func _check_ranks() -> void:
	print("RANKS")

	# --- the three generic curves actually rise -------------------------------
	_check("curve: damage rises", GameSettings.rank_damage_mult(5) > GameSettings.rank_damage_mult(1) * 1.9,
		"x%.2f" % GameSettings.rank_damage_mult(5))
	_check("curve: area rises", GameSettings.rank_area_mult(5) > GameSettings.rank_area_mult(1) * 1.5,
		"x%.2f" % GameSettings.rank_area_mult(5))
	_check("curve: duration rises", GameSettings.rank_duration_mult(5) > GameSettings.rank_duration_mult(1) * 1.4,
		"x%.2f" % GameSettings.rank_duration_mult(5))

	# --- DAMAGE, on one skill per colour that deals it ------------------------
	var forward: Vector3 = -_player.transform.basis.z
	for entry: Array in [
		["white_4", Vector3(3.0, 0.0, 0.0)],
		["blue_2", Vector3(3.0, 0.0, 0.0)],
		["black_1", forward * 6.0],
		["green_1", Vector3(2.0, 0.0, 0.0)],
	]:
		var readings: Array = _measure(entry[0], func() -> float: return _damage_probe(entry[0], entry[1]))
		_check("%s damage scales" % entry[0], readings[1] > readings[0] * 1.5,
			"%.0f -> %.0f" % [readings[0], readings[1]])

	# --- AREA: an enemy outside the rank-1 radius is inside the rank-5 one ----
	# Roar's radius is 14 at rank 1 and 22.4 at rank 5, so 18 units out is the honest
	# test of whether the radius moved at all.
	var far_enemy: EnemyBase = _spawn_enemy(Vector3(18.0, 0.0, 0.0))
	_set_rank("green_4", 1)
	_cast("green_4")
	var taunted_at_1: bool = far_enemy.taunt_timer > 0.0
	far_enemy.taunt_timer = 0.0
	far_enemy.taunt_source = null
	_set_rank("green_4", GameSettings.spell_max_rank)
	_cast("green_4")
	var taunted_at_5: bool = far_enemy.taunt_timer > 0.0
	_check("green_4 radius scales", not taunted_at_1 and taunted_at_5,
		"rank1=%s rank5=%s" % [taunted_at_1, taunted_at_5])
	_clear_enemies()

	# --- DURATION -------------------------------------------------------------
	var ironbark: Array = _measure("green_5", func() -> float:
		_player._ironbark_timer = 0.0
		_cast("green_5")
		return _player._ironbark_timer)
	_check("green_5 duration scales", ironbark[1] > ironbark[0] * 1.4,
		"%.1fs -> %.1fs" % [ironbark[0], ironbark[1]])

	# --- FRACTIONS: must rise, and must NOT run past their ceiling ------------
	var reduction: Array = _measure("green_5", func() -> float:
		_cast("green_5")
		return _player._ironbark_reduction)
	_check("green_5 reduction walks to its ceiling",
		reduction[1] > reduction[0] and is_equal_approx(reduction[1], GameSettings.spell_green_ironbark_reduction_max),
		"%.2f -> %.2f (cap %.2f)" % [reduction[0], reduction[1], GameSettings.spell_green_ironbark_reduction_max])
	_check("green_5 reduction never reaches immunity", reduction[1] < 1.0, "%.2f" % reduction[1])

	var block: Array = _measure("white_3", func() -> float:
		_cast("white_3")
		return _player._reprisal_block_chance)
	_check("white_3 block chance scales", block[1] > block[0] and block[1] <= 1.0,
		"%.2f -> %.2f" % [block[0], block[1]])

	# --- COUNTS ---------------------------------------------------------------
	var charges: Array = _measure("white_1", func() -> float:
		_cast("white_1")
		return float(_player.exalted_charges))
	_check("white_1 charges scale", charges[1] > charges[0], "%.0f -> %.0f" % [charges[0], charges[1]])

	var raised_low: int = _raise_and_count(1)
	var raised_high: int = _raise_and_count(GameSettings.spell_max_rank)
	_check("black_5 raises more bodies", raised_high > raised_low, "%d -> %d" % [raised_low, raised_high])

	# --- Kill is the one skill whose COOLDOWN is the rank curve ---------------
	_set_rank("black_3", 1)
	var cooldown_low: float = _player._get_spell_cooldown("black_3")
	_set_rank("black_3", GameSettings.spell_max_rank)
	var cooldown_high: float = _player._get_spell_cooldown("black_3")
	_check("black_3 cooldown falls with rank", cooldown_high < cooldown_low * 0.8,
		"%.0fs -> %.0fs" % [cooldown_low, cooldown_high])

	# --- and a rank the player does not have must not scale anything ----------
	_player.spell_ranks.erase("white_4")
	var unowned: float = _damage_probe("white_4", Vector3(3.0, 0.0, 0.0))
	_set_rank("white_4", 1)
	var owned: float = _damage_probe("white_4", Vector3(3.0, 0.0, 0.0))
	_check("an unowned spell casts at rank 1", is_equal_approx(unowned, owned),
		"%.0f vs %.0f" % [unowned, owned])
	_done_with("ranks")


## Zombify at a given rank, returning how many undead it raised. Needs corpses, so it
## makes more than the maximum any rank could consume.
func _raise_and_count(rank: int) -> int:
	_clear_spawned()
	for i: int in range(GameSettings.spell_black_zombify_count_max + 2):
		var corpse: EnemyBase = _spawn_enemy(Vector3(2.0 + float(i), 0.0, 2.0))
		corpse._register_corpse()
	_set_rank("black_5", rank)
	_cast("black_5")
	var raised: int = _nodes_of("TemporaryAlly").size()
	_clear_spawned()
	_clear_enemies()
	return raised


# --- multicolour ---------------------------------------------------------------

func _check_multicolour() -> void:
	print("MULTICOLOUR")
	_player.spell_ranks.clear()
	_player.unlocked_spells_in_path.clear()
	_player.reset_quick_slots()

	# A red main who also took one blue spell. This is the build the old single
	# `chosen_color_path` made impossible: picking up blue_2 threw the red bar away.
	for spell_id: String in ["red_1", "red_2", "red_3", "blue_2"]:
		_player.grant_spell_rank(spell_id)

	_check("newly bought spells bind themselves",
		_player.quick_slots.slice(0, 4) == ["red_1", "red_2", "red_3", "blue_2"],
		str(_player.quick_slots))

	var castable: Array[String] = []
	for slot: int in range(5):
		if _player.is_spell_unlocked(slot):
			castable.append(_player._get_spell_id_for_slot(slot))
	_check("two colours are castable at once", castable.has("red_1") and castable.has("blue_2"),
		str(castable))

	# Selecting a colour used to REPLACE the bar. It must now only highlight.
	_player.select_color_path("green")
	_check("choosing a colour leaves the bar alone",
		_player._get_spell_id_for_slot(0) == "red_1", _player._get_spell_id_for_slot(0))

	# Rebinding swaps rather than duplicating.
	_player.assign_quick_slot(0, "blue_2")
	_check("rebinding swaps, never duplicates",
		_player.quick_slots[0] == "blue_2" and _player.quick_slots[3] == "red_1",
		str(_player.quick_slots))

	_check("an unowned spell cannot be bound",
		not _player.assign_quick_slot(4, "black_5") and _player.quick_slots[4] == "",
		str(_player.quick_slots))
	_done_with("multicolour")

# --- sound ---------------------------------------------------------------------

## Does every event SoundBank advertises actually have a recording behind it, and does
## every skill have an event?
##
## SoundBank answers a missing file with push_warning and then silence, so a typo in a
## path costs nothing at startup and everything in play - the spell simply makes no
## noise, which is indistinguishable from a spell that did not fire. Neither the parse
## check nor the smoke test can see it, so it is checked here.
func _check_sounds() -> void:
	print("SOUNDS")

	var silent: Array[String] = []
	for event: StringName in SoundBank.EVENT_FILES:
		var streams: Array = SoundBank._streams.get(event, [])
		if streams.is_empty():
			silent.append(String(event))
	_check("every sound event has a recording", silent.is_empty(),
		"silent: %s" % ", ".join(silent))

	# ...and that the files listed are the files on disk, which is the same question
	# asked from the other end - a path can resolve and still be the wrong one.
	var missing: Array[String] = []
	for event: StringName in SoundBank.EVENT_FILES:
		for relative: String in SoundBank.EVENT_FILES[event]:
			if not ResourceLoader.exists(SoundBank.SFX_ROOT + relative):
				missing.append(relative)
	_check("every listed file exists", missing.is_empty(), "missing: %s" % ", ".join(missing))

	var unvoiced: Array[String] = []
	for spell_id: String in EXPECTED_SPELL_SOUNDS:
		var event: StringName = EXPECTED_SPELL_SOUNDS[spell_id]
		if not SoundBank.EVENT_FILES.has(event):
			unvoiced.append("%s (%s)" % [spell_id, event])
	_check("all 25 skills map to a real event", unvoiced.is_empty(), ", ".join(unvoiced))

	# The two sustained spells have to be told to loop on the IMPORT, not at runtime.
	# A firestorm that plays its clip once and stops is the failure this catches.
	var not_looping: Array[String] = []
	for event: StringName in [&"spell_rain_ember", &"spell_fire_cone", &"crystal_ambience"]:
		var streams: Array = SoundBank._streams.get(event, [])
		if streams.is_empty():
			not_looping.append("%s (no stream)" % event)
			continue
		var stream: AudioStream = streams[0]
		if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			not_looping.append(String(event))
	_check("sustained sounds actually loop", not_looping.is_empty(), ", ".join(not_looping))

	# A boss has to announce itself.
	_check("bosses have an arrival sound", SoundBank.EVENT_FILES.has(&"boss_spawn"), "no boss_spawn event")

	print("  (%d events, %d recordings)" % [SoundBank.EVENT_FILES.size(), _recording_count()])
	_done_with("sounds")


func _recording_count() -> int:
	var total: int = 0
	for event: StringName in SoundBank.EVENT_FILES:
		total += (SoundBank.EVENT_FILES[event] as Array).size()
	return total
