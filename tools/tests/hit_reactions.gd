extends Node
## Regression test: every enemy's "hit" clip is a FLINCH, not a death.
##
## Run with:  godot --headless --path . res://tools/tests/hit_reactions.tscn
##
## `crossbow/hit.fbx` was not a hit. It was a second death animation that happened to be
## filed under that name, and Human and Merfolk Ranged played it every time they were
## grazed - collapsing to the floor and then standing back up, for 1.77 seconds, on every
## single point of chip damage. Nothing caught it because nothing was looking: the clip
## exists, it is named "hit", it loads, it plays, and only a person watching the game
## would know it was wrong.
##
## The distinction is measurable, which is the whole point of this file. A flinch returns
## the character to roughly the height it started at; a death leaves them on the ground.
## Measured across the cast, real flinches end at 81-100% of their starting head height
## and the two impostors ended at 13% (crossbow/hit) and 5% (crossbow/death).
##
## Checked on the BUILT libraries rather than the source fbx files, because that is what
## the game plays - a clip can be swapped in CLIP_SETS and not reach the library, which is
## a separate failure this also catches.

const RACE_BY_COLOR: Dictionary = {
	"White": "human", "Blue": "merfolk", "Black": "zombie", "Red": "goblin", "Green": "elf",
}
const CLASSES: Array[String] = ["melee", "ranged", "mage"]

## Below this share of its starting head height, a character has gone down and not got up.
## The lowest genuine flinch in the cast is the zombie rig's stagger at 81%; the deaths
## measured 13% and 5%. Nothing sits near this line, which is what makes it a safe one.
const STANDING_THRESHOLD: float = 0.7

## A flinch has to be over fast enough to survive being squeezed into
## GameSettings.enemy_hit_react_duration. EnemyBase compresses it (see
## _reaction_speed_scale), and compressing a 3-second death into 0.4s is a blur.
const MAX_FLINCH_SECONDS: float = 2.5

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []


func _process(_delta: float) -> void:
	if _done:
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
	print("Every hit clip is a flinch")
	var worst_name: String = ""
	var worst_share: float = 1.0
	var too_long: Array[String] = []
	var missing: Array[String] = []

	for class_key: String in CLASSES:
		for color: String in RACE_BY_COLOR:
			var name: String = "%s_%s" % [RACE_BY_COLOR[color], class_key]
			var result: Dictionary = _measure(class_key, color)
			if result.is_empty():
				missing.append(name)
				continue
			if float(result["share"]) < worst_share:
				worst_share = float(result["share"])
				worst_name = name
			if float(result["length"]) > MAX_FLINCH_SECONDS:
				too_long.append("%s %.2fs" % [name, result["length"]])

	_check("every character has a hit clip", missing.is_empty(), str(missing))
	_check("no hit clip leaves its character on the ground",
		worst_share >= STANDING_THRESHOLD,
		"%s ends at %.0f%% of its starting head height" % [worst_name, worst_share * 100.0])
	_check("no hit clip is too long to be a flinch", too_long.is_empty(), str(too_long))

	# The two that were broken, named explicitly - this is the regression, and a generic
	# sweep would let it back in the moment somebody re-pointed the crossbow set.
	for color: String in ["White", "Blue"]:
		var result: Dictionary = _measure("ranged", color)
		_check("%s Ranged flinches rather than dying" % color,
			not result.is_empty() and float(result["share"]) > 0.9,
			"ends at %.0f%%" % (float(result.get("share", 0.0)) * 100.0))

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


## How far the head has fallen by the end of a character's hit clip, as a share of where
## it started, plus the clip's length. {} when there is no clip to measure.
##
## Driven through the real AnimationPlayer on the real skeleton: the clips are borrowed
## across rigs, so what a clip does to THIS character is the only thing worth measuring.
func _measure(class_key: String, color: String) -> Dictionary:
	var path: String = "res://scenes/%s/%s_%s.tscn" % [class_key, RACE_BY_COLOR[color], class_key]
	var packed: PackedScene = load(path)
	if packed == null:
		return {}
	var root: Node3D = packed.instantiate()
	add_child(root)
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	var head: int = skeleton.find_bone("mixamorig_Head") if skeleton != null else -1
	if player == null or head == -1 or not player.has_animation("hit"):
		root.free()
		return {}

	var anim: Animation = player.get_animation("hit")
	player.play("hit")
	player.seek(0.0, true)
	var start: float = skeleton.get_bone_global_pose(head).origin.y
	player.seek(anim.length, true)
	var end: float = skeleton.get_bone_global_pose(head).origin.y
	root.free()
	return {"share": end / maxf(start, 0.0001), "length": anim.length}
