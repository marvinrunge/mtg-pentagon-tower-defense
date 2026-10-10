extends SceneTree
## Headless entry point for tools/retarget_pass.gd: retargets the clips in the enemy, myr
## and player animation libraries onto the skeletons that play them, writing only the
## libraries.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/retarget_libraries.gd
##
## Safe to run again: clips already retargeted are marked and skipped. Deadlocks if a Godot
## editor already has the project open (project lock).

const RetargetPass = preload("res://tools/retarget_pass.gd")


func _init() -> void:
	RetargetPass.run()
	quit()
