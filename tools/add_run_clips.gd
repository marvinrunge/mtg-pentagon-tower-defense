extends SceneTree
## Runs the locomotion pass on its own - the run clip and the stride measurements - with
## no character scene rebuilt.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/add_run_clips.gd
##
## This is the entry point that added the run clips in the first place, and the one to use
## again after swapping a run source: the character .tscn files have been hand-corrected
## in the editor since they were last generated (.agents/learnings.md, 2026-08-23), and a
## full tools/build_characters.gd run would discard that to deliver a clip that lives in a
## separate resource file anyway.
##
## Deadlocks if a Godot editor already has the project open (project lock).

const LocomotionPass = preload("res://tools/locomotion_pass.gd")


## Deferred to the first real frame rather than run straight from _init(). The pass poses
## characters through an AnimationPlayer to measure them, and a node added to the root
## during _init() has not entered the tree yet - every clip would measure as covering zero
## ground. See LocomotionPass's own comment.
func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var failed: int = LocomotionPass.apply_all()
	print("Locomotion pass done. %d libraries failed." % failed)
	quit(1 if failed > 0 else 0)
