extends SceneTree
## Re-imports the "hit" clip for the two crossbow-carrying ranged characters.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/fix_ranged_hit.gd
##
## crossbow/hit.fbx is not a hit, it is a second death animation - over its 1.77s the
## head drops to 13% of its starting height and stays there, where every genuine flinch
## in the cast returns to 100%. Human and Merfolk Ranged were collapsing to the floor
## every time they were grazed. CLIP_SETS now points the crossbow set's hit at the bow
## rig's, and this pushes that into the two libraries already built.
##
## Touches the animation LIBRARIES only. The character scenes carry hand-adjusted weapon
## transforms and are deliberately not regenerated - see tools/reclip_pass.gd.

const ReclipPass = preload("res://tools/reclip_pass.gd")

## Human and Merfolk. Elf Ranged is on the bow set and always had the right clip; Goblin
## and Zombie Ranged use the zombie rig's, which measures as a proper flinch.
const SUBJECTS: Array = ["Ranged/White", "Ranged/Blue"]


## Deferred to the first frame: grounding poses the skeleton, which needs a live tree.
func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var failed: int = ReclipPass.apply_all("hit", SUBJECTS)
	print("Ranged hit clips updated. %d failed." % failed)
	quit(1 if failed > 0 else 0)
