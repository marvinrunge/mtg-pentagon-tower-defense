extends Node
## Screenshots all three aura orbs on one player, mid-fight, so the two that were
## rebuilt can be judged against the one that was already good.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/orb_shot.tscn -- <out.png>
##
## orb_orbits.gd proves the three cannot touch. What it cannot say is whether they read as
## three different THINGS - the Winter Orb had a shell, orbiting shards and a tinted core
## while the other two were unshaded balls with a light in them, and no assertion catches
## "looks like a placeholder". Enemies are spawned in range so the beams fire too, since the
## bolts were the other half of the complaint.

var _frames: int = 0
var _done: bool = false
var _shots: int = 0


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/orb_shot.gd").new()
	shooter.name = "OrbShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames == 60:
		_arm()
	if _frames > 60 and (_frames - 60) % 11 == 0:
		_shoot()


## All three Manifestations at once. They are one-per-colour and mutually exclusive only
## WITHIN a colour, so blue + red + white is a legal build a player can actually reach - which
## is the whole reason the shared orbit mattered.
func _arm() -> void:
	var player: Node = PlayerRegistry.get_local()
	if player == null:
		return
	player.aura_ranks.clear()
	for aura_id: String in ["aura_orb_of_frost", "aura_orb_of_fire", "aura_healing_orb"]:
		player.aura_ranks[aura_id] = GameSettings.spell_max_rank
	player._sync_auras()
	# Something to shoot at, and something to heal - the heal orb picks the most hurt ally in
	# range and does nothing at all when everyone is full, so a shot of it firing needs a
	# wounded player as much as the other two need a live enemy.
	player.hp = player.max_hp * 0.45
	var scene: Node = get_tree().current_scene
	# Off the crystal and onto open ground. The player spawns ringed around the crystal, and
	# the gameplay camera sits close behind their shoulder - the first version of this shot was
	# the inside of the crystal with one orb filling a third of the frame.
	var stage: Vector3 = (player as Node3D).global_position + Vector3(26.0, 0.0, 26.0)
	(player as Node3D).global_position = stage

	for offset: Vector3 in [Vector3(5.0, 0.0, 2.0), Vector3(-4.0, 0.0, 5.0), Vector3(3.0, 0.0, -6.0)]:
		var enemy: Node3D = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
		enemy.set_meta("enemy_color", "Red")
		enemy.set_meta("enemy_type", "Melee")
		scene.add_child(enemy)
		enemy.global_position = stage + offset

	# A framing camera of this tool's own, rather than the gameplay rig: the orbs orbit out to
	# 3.1m and the shoulder camera sits 3.2m behind the player, so the outer one spends half its
	# orbit behind the lens. Far enough back and high enough to hold all three lanes at once.
	var camera := Camera3D.new()
	camera.name = "OrbShotCamera"
	scene.add_child(camera)
	camera.global_position = stage + Vector3(2.5, 2.9, 6.0)
	camera.look_at(stage + Vector3(0.0, 1.9, 0.0), Vector3.UP)
	camera.current = true
	print("armed: %d orbs" % player._aura_orbs.size())


func _shoot() -> void:
	var out_path: String = "orbs.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	# Several frames apart, because the bolts are brief and the orbs are on three different
	# periods: one frame is unlikely to catch more than one of them doing anything.
	_shots += 1
	var numbered: String = out_path.get_basename() + "_%d.png" % _shots
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(numbered) == OK:
		print("Wrote %s" % numbered)
	if _shots >= 8:
		_done = true
		get_tree().quit()
