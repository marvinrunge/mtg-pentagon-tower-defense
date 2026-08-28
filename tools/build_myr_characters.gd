extends SceneTree
## Headless entry point for MyrCharacterBuilder.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_myr_characters.gd
##
## The bare `godot` on PATH is 4.6.2 on this machine, not the 4.7 this project
## targets - always name the 4.7 binary explicitly (see .agents/learnings.md).
##
## Deadlocks if a Godot editor already has the project open (project lock).
## While the editor is open, invoke MyrCharacterBuilder.build_all() directly
## instead, e.g. through Godot MCP's execute_editor_script.

func _init() -> void:
	MyrCharacterBuilder.build_all()
	quit()
