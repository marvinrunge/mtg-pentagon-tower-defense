extends SceneTree
## Headless entry point for BossCharacterBuilder.build_libraries(): rebuilds the five
## per-boss animation libraries - retargeted and grounded - against the boss scenes as they
## stand, without writing any scene.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_boss_libraries.gd
##
## Deadlocks if a Godot editor already has the project open (project lock). While the
## editor is open, call BossCharacterBuilder.build_libraries() through Godot MCP's
## execute_editor_script instead.

const Builder = preload("res://tools/boss_character_builder.gd")


func _init() -> void:
	Builder.build_libraries()
	quit()
