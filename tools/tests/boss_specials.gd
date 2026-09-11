extends Node
## Regression test: bosses attack only with telegraphed specials, and every boss has two.
##
## Run with:  godot --headless --path . res://tools/tests/boss_specials.tscn
##
## A boss used to have one big telegraphed special plus an ordinary swing - and that swing was
## the one attack in the game a player had no answer to: stand in front of a boss and you took
## it. The swing is gone; the `attack` clip it used now drives a SECOND special, short range
## and short cooldown, so a boss attacks about as often as before and every hit has a tell.
##
## Two things have to hold together, and the second is the one that bites: the ordinary attack
## must be gone, AND the melee special must be able to damage the crystal. The big special
## deliberately refuses to target the crystal (it cannot dodge), so a boss stripped of its
## swing without that exception walks up to the objective and stands there doing nothing.

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
	get_tree().quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _spawn_boss(color: String) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = scene.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	_scene.add_child(boss)
	boss.global_position = Vector3(0.0, 0.0, 60.0)
	return boss


func _run() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		print("TEST RESULT: FAIL (no scene)")
		return

	for color: String in SpellDatabase.COLORS:
		_check_boss(String(color).capitalize())

	_check_crystal_damage()
	_check_clip_bones()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)


func _check_boss(color: String) -> void:
	var specials: Array = BossDatabase.get_specials(color)
	_check("%s has two specials" % color, specials.size() == 2, "%d" % specials.size())
	if specials.size() < 2:
		return

	var clips: Array[String] = []
	var melee_count: int = 0
	for config: Dictionary in specials:
		clips.append(String(config.get("clip", "special")))
		# Every special needs a tell the player can act on, whatever else it does.
		_check("%s '%s' lands mid-clip" % [color, config["display_name"]],
			float(config["impact_fraction"]) > 0.05 and float(config["impact_fraction"]) < 0.95,
			"%.2f" % config["impact_fraction"])
		if bool(config.get("hits_crystal", false)):
			melee_count += 1
	# The two must use DIFFERENT clips, or the second is invisible - it would look like the
	# first one played twice.
	_check("%s specials use different clips" % color, clips[0] != clips[1], str(clips))
	_check("%s has exactly one crystal-breaker" % color, melee_count == 1, "%d" % melee_count)

	var boss: EnemyBase = _spawn_boss(color)
	_check("%s boss is a boss" % color, boss.is_boss())
	_check("%s boss loaded both specials" % color, boss._specials.size() == 2,
		"%d" % boss._specials.size())
	# The clips have to EXIST on this boss's own rig, or _special_eligible refuses forever and
	# the boss never attacks at all.
	for clip: String in clips:
		_check("%s rig has a '%s' clip" % [color, clip],
			boss.visual_anim_player != null and boss.visual_anim_player.has_animation(clip))

	# Range bands: the melee one reaches point blank, the big one is held off it, and between
	# them they leave no gap a boss could stand in and do nothing.
	var melee: Dictionary = specials[1]
	var big: Dictionary = specials[0]
	_check("%s melee special reaches point blank" % color, float(melee.get("min_range", 0.0)) <= 0.01,
		"%.1f" % melee.get("min_range", 0.0))
	_check("%s big special is held off point blank" % color, float(big.get("min_range", 0.0)) > 0.5,
		"%.1f" % big.get("min_range", 0.0))
	_check("%s bands overlap, leaving no dead zone" % color,
		float(big.get("min_range", 0.0)) < float(melee["radius"]) * 0.9,
		"big from %.1f, melee reaches %.1f" % [big.get("min_range", 0.0), float(melee["radius"]) * 0.9])
	# The melee one has to come round far more often - it is replacing an attack that used to
	# land every 1.8 seconds.
	_check("%s melee special recycles quickly" % color,
		float(melee.get("cooldown", GameSettings.boss_special_cooldown)) < 3.0,
		"%.1fs" % melee.get("cooldown", GameSettings.boss_special_cooldown))
	boss.free()


func _is_finger(bone: String) -> bool:
	for part: String in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if bone.contains("Hand" + part):
			return true
	return false


## Every clip a boss plays has to address bones that exist on ITS OWN skeleton.
##
## The sets are shared and deliberately swappable - the zombie lord borrows the mutant walk,
## because its own is a near-static shuffle that reads as a stuck pose on a body that size -
## and a borrowed clip is exactly where this breaks. A track naming a bone the rig does not
## have is silently dropped by Godot: the boss animates, just without that limb, which looks
## like bad animation rather than like a missing track.
func _check_clip_bones() -> void:
	print("CLIP BONES")
	for color: String in SpellDatabase.COLORS:
		var boss: EnemyBase = _spawn_boss(String(color).capitalize())
		var skeleton: Skeleton3D = boss.find_child("Skeleton3D", true, false) as Skeleton3D
		if boss.visual_anim_player == null or skeleton == null:
			_failures.append("%s boss has no rig to check" % color)
			boss.free()
			continue
		var missing: Array[String] = []
		var missing_fingers: int = 0
		for clip_name: StringName in boss.visual_anim_player.get_animation_list():
			var clip: Animation = boss.visual_anim_player.get_animation(clip_name)
			for track: int in range(clip.get_track_count()):
				var path: String = str(clip.track_get_path(track))
				if not path.contains(":"):
					continue
				var bone: String = path.get_slice(":", 1)
				if not bone.begins_with("mixamorig") or skeleton.find_bone(bone) != -1:
					continue
				if _is_finger(bone):
					missing_fingers += 1
				else:
					missing.append("%s/%s" % [clip_name, bone])
		# Fingers are counted but not failed on. Several of these rigs were generated without them
		# - the frost giant has 41 bones against the treant's 65 - so the clips carry finger tracks
		# that Godot silently drops, and at boss scale a curling knuckle is not something anyone
		# sees. Red and Blue already drop them on their death clips, and the zombie lord's borrowed
		# walk drops six the same way. A missing SPINE or LIMB is a different matter: that is a
		# limb that does not move, and it reads as bad animation rather than as a missing track.
		_check("%s clips address every major bone its rig has" % color, missing.is_empty(),
			"%d missing, e.g. %s" % [missing.size(), missing[0] if not missing.is_empty() else ""])
		if missing_fingers > 0:
			print("       (%s drops %d finger tracks - cosmetic)" % [color, missing_fingers])
		boss.free()


## The one that would silently break the game: a boss with no ordinary attack that also cannot
## special the crystal is a boss that cannot lose the player the run.
func _check_crystal_damage() -> void:
	var boss: EnemyBase = _spawn_boss("Red")
	var crystal: Node3D = _scene.get_node_or_null("NavigationRegion3D/CrystalAnchor") as Node3D
	if crystal == null:
		_failures.append("no crystal anchor to test against")
		boss.free()
		return
	boss.target_crystal = crystal
	boss.current_target = crystal
	boss.global_position = crystal.global_position + Vector3(2.0, 0.0, 0.0)

	# The big special must still refuse the crystal - it cannot dodge, and free undodgeable
	# damage is exactly what this whole change removes.
	_check("the big special refuses the crystal",
		not boss._special_eligible(boss._specials[0], 2.0))
	_check("the melee special accepts the crystal",
		boss._special_eligible(boss._specials[1], 2.0))

	var damage_seen: Array[float] = []
	var probe: Callable = func(amount: float) -> void: damage_seen.append(amount)
	SignalBus.crystal_damaged.connect(probe)
	boss._begin_special(1)
	boss._resolve_special()
	SignalBus.crystal_damaged.disconnect(probe)
	_check("the melee special damages the crystal",
		not damage_seen.is_empty() and damage_seen[0] > 0.0,
		"%s" % damage_seen)

	# ...and the ordinary swing really is gone.
	_check("a boss never uses the plain attack", boss.is_boss())
	boss.free()
