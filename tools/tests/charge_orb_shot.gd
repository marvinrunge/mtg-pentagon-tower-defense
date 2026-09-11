extends Node
## Photographs the fireball charge at four points across its three seconds, so the growth,
## the heat ramp and the full-charge flare can be judged by looking at them.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/charge_orb_shot.tscn -- <out.png>
##
## charge_orb.gd asserts the lifecycle and that the numbers move. None of that says whether
## the ball reads as something being GATHERED, whether it is visible against a bright morning
## sky, or whether it actually sits between the hands rather than inside the character's chest
## - and the last of those is the one thing about this effect I could not check without a
## camera pointed at it.

## Fractions of the charge to capture. The last one is a real 1.0, which also fires the
## full-charge flare - see the is_charging note below for how the auto-fire is kept off.
const STAGES: Array[float] = [0.0, 0.35, 0.7, 1.0]

var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/charge_orb_shot.gd").new()
	shooter.name = "ChargeShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	_shoot()


func _shoot() -> void:
	var out_path: String = "charge.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]

	var player: Node3D = PlayerRegistry.get_local() as Node3D
	var scene: Node = get_tree().current_scene
	if player == null:
		push_error("no player")
		get_tree().quit()
		return

	# Onto open ground and side-on to the camera, because the whole question is whether the
	# ball sits between the HANDS - a shot from behind the shoulder hides that completely.
	var stage: Vector3 = player.global_position + Vector3(24.0, 0.0, 24.0)
	player.global_position = stage
	player.rotation.y = PI * 0.5

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = stage + Vector3(0.0, 1.5, 3.4)
	camera.look_at(stage + Vector3(0.0, 1.25, 0.0), Vector3.UP)
	camera.current = true

	player.spell_ranks["red_1"] = 1
	if not player.unlocked_spells_in_path.has("red_1"):
		player.unlocked_spells_in_path.append("red_1")
	player.assign_quick_slot(0, "red_1")
	player.active_spell_index = 0
	player.spell_cooldown_timers.erase("red_1")
	player.cast_active_spell()
	# Charging is switched OFF straight after starting it, while keeping the orb the start
	# created. Player._physics_process advances charge_timer and fires the spell the instant it
	# reaches max, so any attempt to park the timer near full and then wait frames throws the
	# fireball before the shutter opens - re-pinning per frame is not enough, because physics
	# steps between the process frames this loop awaits. The orb does not read is_charging.
	player.is_charging = false

	for i: int in range(STAGES.size()):
		# Re-pinned EVERY frame, not just once. Player._physics_process keeps adding delta to
		# charge_timer while these frames run, so setting it once and then waiting walks the
		# charge up to full and fires the spell - which is what made the last stage photograph
		# an empty hand on the first two attempts.
		player.charge_timer = player.charge_max_time * STAGES[i]
		player._update_charge_orb()
		# A few frames per stage so the particle system has motes in flight and the light has
		# settled - a single frame photographs an empty emitter.
		for _f: int in range(6):
			await get_tree().process_frame
			player.charge_timer = player.charge_max_time * STAGES[i]
			player._update_charge_orb()
		var orb: Node3D = player._charge_orb
		print("  %3d%%  radius=%.3f  light=%.2f  tint=%s" % [
			int(STAGES[i] * 100.0),
			orb._core.scale.x if orb != null else -1.0,
			orb._light.light_energy if orb != null else -1.0,
			orb._core_material.emission if orb != null else Color.BLACK])
		await RenderingServer.frame_post_draw
		var numbered: String = out_path.get_basename() + "_%d.png" % i
		if get_viewport().get_texture().get_image().save_png(numbered) == OK:
			print("Wrote %s" % numbered)

	get_tree().quit()
