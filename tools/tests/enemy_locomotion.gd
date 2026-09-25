extends Node
## Regression test: enemies move on a clip that matches the speed they are actually
## travelling, instead of skating.
##
## Run with:  godot --headless --path . res://tools/tests/enemy_locomotion.tscn
##
## Every enemy used to play one clip, "walk", at playback 1.0, whatever it was doing. The
## clips were never authored for the speeds this game moves at, so the mismatch was large
## and visible - measured across the built cast:
##
##   Melee        travels 2.5/s on a 1.04/s walk cycle       2.4x slide
##   Black Ranged travels 2.0/s on a 0.38/s zombie shamble    5.3x slide
##   Mage         travels 1.5/s on a 1.58/s walk cycle        fine, by luck
##
## Every locomotion clip now carries a measured `stride_speed` (tools/animation_stride.gd),
## each enemy picks whichever of its clips is nearest the speed it is really going, and
## plays it at the ratio between the two. What is checked here:
##
##   1. Both locomotion clips exist on every character, with a measurement on each. Half
##      of this lives in the .tres files, so it is the half that silently rots - a rebuild
##      through the wrong tool drops "run" and everything still runs, just badly.
##   2. The residual slide is small. This is the actual goal, and the one check that would
##      still fail if the selection rule were replaced with a worse one.
##   3. Walking is for walking pace and running is for running pace: an enemy dawdling at
##      its squad's march speed must not be sprinting on the spot, and one at full charge
##      must not be gliding.
##   4. Size is respected without a rule of its own - a bigger body covers more ground per
##      stride, so it stays on the walk where a small one would run.
##   5. Bosses, whose libraries carry no measurement, behave exactly as they did before.

const LIB_DIR: String = "res://assets/animations/character/"
const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const RACE_BY_COLOR: Dictionary = {
	"White": "human", "Blue": "merfolk", "Black": "zombie", "Red": "goblin", "Green": "elf",
}

## Worst playback stretch that still reads as the same movement. The clamp in
## GameSettings is the same idea; this asserts the CAST actually fits inside it, which is
## a claim about the clips rather than about the code.
const MAX_ACCEPTABLE_SLIDE: float = 1.6

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_scene = get_tree().current_scene
	if _scene == null or not _scene.has_method("bake_map_navigation"):
		return
	_frames += 1
	if _frames < 5:
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
	print("Clip library")
	_test_libraries()
	print("Speed matching")
	_test_speed_matching()
	print("Clip choice")
	_test_clip_choice()
	print("Bosses")
	_test_boss_unchanged()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


# --- 1. The clips themselves ----------------------------------------------------------

func _test_libraries() -> void:
	var missing: Array[String] = []
	var unmeasured: Array[String] = []
	for class_key: String in ["melee", "ranged", "mage"]:
		for color: String in COLORS:
			var path: String = LIB_DIR + "lib_%s_%s.tres" % [RACE_BY_COLOR[color], class_key]
			var library: AnimationLibrary = load(path)
			if library == null:
				missing.append(path)
				continue
			for clip_name: String in EnemyBase.LOCOMOTION_CLIPS:
				if not library.has_animation(clip_name):
					missing.append("%s:%s" % [path.get_file(), clip_name])
					continue
				var clip: Animation = library.get_animation(clip_name)
				if not clip.has_meta("stride_speed") or float(clip.get_meta("stride_speed")) <= 0.0:
					unmeasured.append("%s:%s" % [path.get_file(), clip_name])
				# A locomotion clip that does not loop stutters once per cycle.
				elif clip.loop_mode != Animation.LOOP_LINEAR:
					unmeasured.append("%s:%s (not looped)" % [path.get_file(), clip_name])
	_check("every character has both locomotion clips", missing.is_empty(), str(missing))
	_check("every locomotion clip is measured and looped", unmeasured.is_empty(), str(unmeasured))


# --- 2 & 3. Matching and choice -------------------------------------------------------

## The headline claim: whatever an enemy is doing, the clip under it is within
## MAX_ACCEPTABLE_SLIDE of its real speed. Checked at the speeds the game actually
## produces - a squad's disciplined march at the low end, an elite charge at the top.
func _test_speed_matching() -> void:
	var worst: float = 1.0
	var worst_case: String = ""
	for class_key: String in ["Melee", "Ranged", "Mage"]:
		for color: String in COLORS:
			var enemy: EnemyBase = _spawn(color, class_key)
			var base: float = enemy.enemy_data.speed
			# march pace, own pace, charging elite
			for factor: float in [0.7, 1.0, 1.3, 1.95]:
				var speed: float = base * factor
				var slide: float = _slide_at(enemy, speed)
				if slide > worst:
					worst = slide
					worst_case = "%s %s at %.2f/s" % [color, class_key, speed]
			enemy.free()
	_check("no enemy slides more than %.1fx at any speed it reaches" % MAX_ACCEPTABLE_SLIDE,
		worst <= MAX_ACCEPTABLE_SLIDE, "worst %.2fx (%s)" % [worst, worst_case])

	# The specific regression. Black's Ranged had the worst mismatch in the game by a wide
	# margin - a 0.38/s shamble under an enemy doing 2.0 - and is the reason the run clips
	# were imported at all.
	var zombie: EnemyBase = _spawn("Black", "Ranged")
	var slide_before: float = zombie.enemy_data.speed / 0.38
	var slide_after: float = _slide_at(zombie, zombie.enemy_data.speed)
	_check("Black's Ranged no longer shambles at five times its stride",
		slide_after < 1.5 and slide_after < slide_before,
		"was %.1fx, now %.2fx" % [slide_before, slide_after])
	zombie.free()


func _test_clip_choice() -> void:
	# A melee holding formation moves at its squad's pace, which is set by the slowest
	# member - roughly a mage's 1.5 and well under its own 2.5. It should be walking.
	var melee: EnemyBase = _spawn("Green", "Melee")
	_check("a melee marching at formation pace walks", _clip_at(melee, 1.1) == "walk",
		"got '%s'" % _clip_at(melee, 1.1))
	_check("the same melee at its own full speed runs", _clip_at(melee, 2.5) == "run",
		"got '%s'" % _clip_at(melee, 2.5))
	_check("and at a charge it is still running", _clip_at(melee, 3.75) == "run",
		"got '%s'" % _clip_at(melee, 3.75))

	# Mages are slow enough that their own walk already fits; nothing should have changed
	# for them, and a mage breaking into a sprint at walking pace would be the most
	# visible possible regression.
	var mage: EnemyBase = _spawn("White", "Mage")
	_check("a mage at its own speed still walks", _clip_at(mage, mage.enemy_data.speed) == "walk",
		"got '%s'" % _clip_at(mage, mage.enemy_data.speed))

	# 4. Size, with no rule of its own: the same clip on a bigger body covers more ground,
	# so the crossover moves up. Compared at ONE speed against the same colour and class,
	# so nothing but the scale differs.
	var small: EnemyBase = _spawn("Green", "Melee")
	var large: EnemyBase = _spawn("Green", "Melee")
	large.scale = Vector3.ONE * 2.2
	var crossover_speed: float = 1.8
	_check("a larger body of the same enemy is still walking where a small one runs",
		_clip_at(small, crossover_speed) == "run" and _clip_at(large, crossover_speed) == "walk",
		"small '%s', large '%s'" % [_clip_at(small, crossover_speed), _clip_at(large, crossover_speed)])
	melee.free()
	mage.free()
	small.free()
	large.free()


# --- 5. Bosses ------------------------------------------------------------------------

## Boss libraries were left alone: they are built by a different builder, a boss already
## has a size-derived animation pace of its own (GameSettings.get_boss_anim_speed), and a
## sprinting giant would undo the one thing that pace exists to say. So a boss must fall
## through to exactly the old behaviour rather than to something new.
func _test_boss_unchanged() -> void:
	var boss: EnemyBase = _spawn("Red", "Boss")
	if boss.visual_anim_player == null:
		_check("a boss spawned with a visual", false)
		return
	_check("a boss has no stride measurement to switch on", boss._locomotion.is_empty(),
		"got %s" % [boss._locomotion])
	_check("a boss still walks at any speed",
		_clip_at(boss, 1.2) == "walk" and _clip_at(boss, 6.0) == "walk")
	boss.free()


# --- helpers --------------------------------------------------------------------------

func _spawn(color: String, unit_type: String) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", color)
	enemy.set_meta("enemy_type", unit_type)
	_scene.add_child(enemy)
	enemy.global_position = Vector3(0.0, 0.0, 60.0)
	return enemy


func _clip_at(enemy: EnemyBase, speed: float) -> String:
	enemy._play_locomotion(speed)
	return enemy.visual_anim_player.current_animation


## How far the feet are out at this speed: the ratio between the enemy's real speed and
## the ground the chosen clip actually covers once its playback rate is applied. 1.0 is a
## perfect plant; 2.0 means the feet are going half the speed the body is.
func _slide_at(enemy: EnemyBase, speed: float) -> float:
	var clip: String = _clip_at(enemy, speed)
	if not enemy._locomotion.has(clip):
		return 1.0
	var covered: float = float(enemy._locomotion[clip]) * maxf(enemy.scale.y, 0.01) * enemy.visual_anim_player.get_playing_speed()
	if covered <= 0.0:
		return INF
	return maxf(speed / covered, covered / speed)
