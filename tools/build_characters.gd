extends SceneTree
## Headless entry point for CharacterBuilder.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_characters.gd
##
## The bare `godot` on PATH is 4.6.2 on this machine, not the 4.7 this project
## targets - always name the 4.7 binary explicitly (see .agents/learnings.md).
##
## Deadlocks if a Godot editor already has the project open (project lock).
## While the editor is open, invoke CharacterBuilder.build_all() directly
## instead, e.g. through Godot MCP's execute_editor_script - followed by
## LocomotionPass.apply_all(), which is the second half of a build now.
##
## NOTE this rewrites every character .tscn, and those have been hand-corrected in the
## editor since they were last generated (.agents/learnings.md, 2026-08-23). To add or
## re-measure locomotion clips WITHOUT that, run tools/add_run_clips.gd instead - it is
## the same second half on its own.

const LocomotionPass = preload("res://tools/locomotion_pass.gd")


## Deferred to the first real frame: the locomotion pass below poses characters through an
## AnimationPlayer to measure them, which needs a live tree and a frame that has actually
## run. See LocomotionPass's own comment.
func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	CharacterBuilder.build_all()
	# The run clip itself comes out of build_all() (it is in CLIP_SETS like any other), but
	# its stride measurement cannot be taken in there - so a build is only finished once
	# this has run, and EnemyBase falls back to "always walk" for any character it misses.
	var failed: int = LocomotionPass.apply_all()
	print("Locomotion pass done. %d libraries failed." % failed)
	quit(1 if failed > 0 else 0)
