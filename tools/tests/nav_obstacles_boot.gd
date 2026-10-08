extends Node
## Boot node, same shape as spawn_points_boot.gd: change_scene_to_file() frees whatever is
## the current scene, and that is THIS node - so the checks live on a separate node parented
## to the tree root, which survives the scene swap.


func _ready() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var reporter: Node = load("res://tools/tests/nav_obstacles.gd").new()
	reporter.name = "Reporter"
	get_tree().root.add_child(reporter)
	get_tree().node_added.connect(reporter.on_node_added)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")
