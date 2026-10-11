extends Node
## Runs the crystal placement round the mana wells and the hub (scripts/well_crystals.gd)
## once, on the real terrain, and writes down every crystal and light it made - scene,
## name and exact transform - so tools/bake_placed_crystals.py can put them into main.tscn
## as ordinary nodes, to be seen and moved in the editor.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . res://tools/tests/bake_placed_crystals.tscn -- <out.json>
## then:  python -I tools/bake_placed_crystals.py <out.json>

const WellCrystalsScript := preload("res://scripts/well_crystals.gd")

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/bake_placed_crystals.gd").new()
	probe.name = "BakePlacedCrystals"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 240:
		return
	_done = true
	var scene: Node3D = get_tree().current_scene as Node3D
	var terrain: StaticBody3D = scene.call("_find_collision_body", scene.get_node("TerraBrush"))
	var placer: Node3D = WellCrystalsScript.new()
	scene.add_child(placer)
	placer.place(scene.get("mana_sources"), scene.get("LANE_NAMES"), (scene.get("crystal_anchor") as Node3D).global_position, terrain)
	var wells_end: int = placer.get_child_count()
	var stones: Array = scene.get_node("StoneRings").get_children()
	var pillars: Array = scene.get_node("OuterStoneRing").get_children()
	placer.place_hub((scene.get("crystal_anchor") as Node3D).global_position, stones, pillars, terrain)

	var entries: Array = []
	for i: int in placer.get_child_count():
		var node: Node3D = placer.get_child(i) as Node3D
		var entry: Dictionary = {
			"group": "Wells" if i < wells_end else "Hub",
			"name": String(node.name),
			"transform": var_to_str(node.global_transform),
		}
		if node.scene_file_path != "":
			entry["scene"] = node.scene_file_path
		elif node is OmniLight3D:
			var light := node as OmniLight3D
			entry["light"] = {
				"light_color": var_to_str(light.light_color),
				"light_energy": light.light_energy,
				"omni_range": light.omni_range,
				"distance_fade_begin": light.distance_fade_begin,
				"distance_fade_length": light.distance_fade_length,
			}
		entries.append(entry)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://placed_crystals.json"
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(entries, "  "))
	print("BAKE wrote %d entries to %s" % [entries.size(), out])
	get_tree().quit()
