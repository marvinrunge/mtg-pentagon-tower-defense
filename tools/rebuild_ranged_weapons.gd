extends SceneTree
## Rebuilds ONLY the three ranged characters that wear a real weapon model, then re-runs
## the locomotion pass over their libraries.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/rebuild_ranged_weapons.gd
##
## Three characters rather than all fifteen on purpose. CharacterBuilder.build_all()
## rewrites every character .tscn, and those have been hand-corrected in the editor since
## they were last generated (.agents/learnings.md, 2026-08-23) - there is no reason to put
## twelve of them at risk to change the weapon on three.
##
## The locomotion pass at the end is NOT optional: _build_character rewrites
## lib_<race>_ranged.tres, which drops the "run" clip and its stride_speed metadata and
## would quietly put these three back on "always walk at playback 1.0".
##
## Deadlocks if a Godot editor already has the project open (project lock).

const CharacterBuilder = preload("res://tools/character_builder.gd")
const LocomotionPass = preload("res://tools/locomotion_pass.gd")
const WeaponFitPass = preload("res://tools/weapon_fit_pass.gd")

## The characters whose prop is a real model. Derived rather than listed, so adding a
## fourth weapon to WEAPON_MODELS is enough to have it rebuilt here too.
const CLASS_KEY := "Ranged"


## Deferred to the first frame: the locomotion pass poses characters to measure them,
## which needs a live tree. See LocomotionPass's own comment.
func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var built: int = 0
	var failed: int = 0
	for color: String in CharacterBuilder.CHARACTERS[CLASS_KEY]:
		var config: Dictionary = CharacterBuilder.CHARACTERS[CLASS_KEY][color]
		if int(config.get("prop", CharacterBuilder.Prop.NONE)) != CharacterBuilder.Prop.WEAPON_MODEL:
			continue
		var race: String = CharacterBuilder.RACE_BY_COLOR[color]
		if CharacterBuilder._build_character(color, race, CLASS_KEY.to_lower(), config):
			built += 1
		else:
			failed += 1
	print("Built %d ranged characters (provisional weapon placement), %d failed." % [built, failed])

	# Two build passes, not one. The first put the weapons somewhere approximate, because
	# the hand orientation the builder can read out of a tree-less skeleton is wrong by up
	# to forty degrees. This measures the real one in a live tree and builds again with it.
	failed += await WeaponFitPass.measure_all()
	for color: String in CharacterBuilder.CHARACTERS[CLASS_KEY]:
		var config: Dictionary = CharacterBuilder.CHARACTERS[CLASS_KEY][color]
		if int(config.get("prop", CharacterBuilder.Prop.NONE)) != CharacterBuilder.Prop.WEAPON_MODEL:
			continue
		if not CharacterBuilder._build_character(color, CharacterBuilder.RACE_BY_COLOR[color], CLASS_KEY.to_lower(), config):
			failed += 1
	print("Rebuilt with measured grips.")

	failed += LocomotionPass.apply_all()
	print("Locomotion pass done. %d failures overall." % failed)
	quit(1 if failed > 0 else 0)
