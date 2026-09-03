extends SceneTree
## Headless entry point for PlayerCharacterBuilder.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_player_character.gd
##
## The bare `godot` on PATH is 4.6.2 on this machine, not the 4.7 this project
## targets - always name the 4.7 binary explicitly (see .agents/learnings.md).
##
## Loaded by path rather than by its `class_name`: a headless `--script` run does
## not rescan the project, so a newly added global class isn't in
## .godot/global_script_class_cache.cfg until an editor session picks it up.
##
## Deadlocks if a Godot editor already has the project open (project lock).
## While the editor is open, invoke PlayerCharacterBuilder.build() directly
## instead, e.g. through Godot MCP's execute_editor_script.

const Builder = preload("res://tools/player_character_builder.gd")

func _init() -> void:
	Builder.build()
	quit()
