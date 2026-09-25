extends Node
## Regression test: does the death animation survive the frame it started in?
##
## Run with:  godot --headless --path . res://tools/tests/enemy_death_anim.tscn
##
## `EnemyBase._physics_process` checks `is_dying` at the top and returns - but an enemy can be
## killed from INSIDE that frame, after the check has already passed:
##
##   * the knockback slam (Unsummon shoving it into a Wall of Frost, which adds its bonus
##     damage) calls take_damage from the collision branch
##   * a burn tick calls take_damage from the timers block
##   * landing a hit can kill the attacker, because Reprisal Ward reflects damage back inside
##     the target's own take_damage
##
## In all three the rest of the frame then ran on a corpse and ended at
## _update_visual_animation, which played "walk" or "hit" straight over the death clip that
## had just been started. From the next frame on _physics_process really does return early, so
## nothing ever asked for another animation and the body held that pose forever.
##
## The death-animation debug logging shows this as a `play_requested` line with no matching
## `confirmed` line. This drives the same paths directly and checks the clip that is actually
## playing afterwards.
##
## The same early return is also why a corpse used to hang in the air - it skipped GRAVITY
## along with the AI - so _corpse_falls_to_the_ground lives here too, against the same
## branch.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _scene: Node = null


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	await _run()
	get_tree().quit()


func _spawn_enemy(offset: Vector3) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	_scene.add_child(enemy)
	enemy.global_position = offset
	return enemy


## The clip an enemy is left playing once the frame that killed it has finished. Driving
## _physics_process by hand is the point: the bug is entirely about what runs AFTER die()
## returns, inside the very same call.
func _clip_after_death(label: String, kill: Callable) -> void:
	var enemy: EnemyBase = _spawn_enemy(Vector3(0.0, 0.0, 40.0))
	# Moving, so the state machine has a "walk" it actively wants to play - a stationary
	# enemy would rest on "walk" paused and hide the overwrite behind an identical name.
	enemy.velocity = Vector3(1.0, 0.0, 0.0)
	kill.call(enemy)

	if not enemy.is_dying:
		_failures.append("%s: the enemy did not die at all" % label)
		enemy.free()
		return
	var current: String = enemy.visual_anim_player.current_animation
	if current != "death":
		_failures.append("%s: left playing \"%s\" instead of \"death\"" % [label, current])
	elif not enemy.visual_anim_player.is_playing():
		_failures.append("%s: the death clip is not playing" % label)
	else:
		print("  ok   %-28s clip=%s playing=%s" % [label, current, enemy.visual_anim_player.is_playing()])
	enemy.free()


## An enemy killed off the ground has to come DOWN. It used to play its whole death
## animation at whatever height it was knocked to, because `if is_dying: return` sits above
## the gravity in _physics_process - so the corpse kept its last altitude forever.
##
## die() drops collision_layer to 0 but must KEEP the Environment bit in collision_mask,
## or the body has no floor to find and falls through the world instead. Both halves are
## checked: that it fell, and that it stopped.
func _corpse_falls_to_the_ground() -> void:
	var enemy: EnemyBase = _spawn_enemy(Vector3(0.0, 4.0, 48.0))
	var start_y: float = enemy.global_position.y
	enemy.take_damage(enemy.health + 50.0)
	if not enemy.is_dying:
		_failures.append("corpse fall: the enemy did not die at all")
		enemy.free()
		return
	if enemy.collision_mask & EnemyBase.ENVIRONMENT_LAYER == 0:
		_failures.append("corpse fall: die() dropped the Environment bit, so there is no floor to land on")

	# Driven by hand for the same reason as the checks above - what matters is the branch
	# _physics_process takes for a body that is already dying.
	for _step: int in range(180):
		enemy._physics_process(0.016)
		if enemy.is_on_floor():
			break
	var landed: bool = enemy.is_on_floor()
	var dropped: float = start_y - enemy.global_position.y
	if not landed:
		_failures.append("corpse fall: never reached the floor (dropped %.2f of %.2f)" % [dropped, start_y])
	elif dropped < 1.0:
		_failures.append("corpse fall: barely moved (%.2f)" % dropped)
	elif absf(enemy.velocity.x) > 0.01 or absf(enemy.velocity.z) > 0.01:
		_failures.append("corpse fall: landed but is still sliding (%s)" % enemy.velocity)
	else:
		print("  ok   %-28s fell %.2f to y=%.2f" % ["corpse lands", dropped, enemy.global_position.y])
	enemy.free()


## Something solid for the knockback to slam an enemy into. On every collision layer, so it
## does not matter which of them the enemy happens to mask.
func _build_wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	wall.collision_layer = 0xFFFFFFFF
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 4.0, 12.0)
	shape.shape = box
	wall.add_child(shape)
	_scene.add_child(wall)
	wall.global_position = at
	return wall


func _run() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		print("TEST RESULT: FAIL (no scene)")
		return

	# The reported case, through the real knockback path, which is how Unsummon-into-a-wall
	# actually reaches it - the branch that calls take_damage on a collision.
	#
	# It has to be driven this way rather than by calling take_damage and then _physics_process
	# by hand: doing that sets is_dying BEFORE the frame starts, so the top-of-function guard
	# catches it and the bug never fires. The whole defect is that the guard has already been
	# passed by the time the enemy dies, which only a kill from inside the frame reproduces.
	#
	# Needs something solid to hit, too: over open ground the shove simply decays and nothing
	# dies at all, which is what the first version of this check silently measured.
	var wall: StaticBody3D = _build_wall(Vector3(3.0, 0.0, 40.0))
	# A body added this frame is not in the physics space until the space has stepped, and
	# move_and_collide asks the space. Without this wait the shove sails straight through the
	# wall, nothing dies, and the check passes or fails for the wrong reason entirely.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_clip_after_death("slammed into a wall", func(enemy: EnemyBase) -> void:
		enemy.health = 1.0
		enemy.knockback_velocity = Vector3(40.0, 0.0, 0.0)
		for _step: int in range(12):
			if enemy.is_dying:
				break
			enemy._physics_process(0.016))
	wall.free()

	# And a burn ticking it down, which kills from the timers block rather than the
	# collision one.
	_clip_after_death("burned to death", func(enemy: EnemyBase) -> void:
		enemy.health = 1.0
		enemy.apply_burn(5.0, 500.0)
		for _step: int in range(40):
			if enemy.is_dying:
				break
			enemy._physics_process(0.016))

	# ...and the ordinary case, killed from outside the frame, which always worked and must
	# keep working: the guards must not stop the death clip itself from starting.
	_clip_after_death("killed between frames", func(enemy: EnemyBase) -> void:
		enemy.take_damage(enemy.health + 50.0))

	# A death clip must also survive a LATER frame asking for an animation. _physics_process
	# returns early once is_dying is set, but a client puppet still calls
	# _update_visual_animation directly from its own branch.
	var puppet: EnemyBase = _spawn_enemy(Vector3(0.0, 0.0, 44.0))
	puppet.velocity = Vector3(1.0, 0.0, 0.0)
	puppet.take_damage(puppet.health + 50.0)
	puppet._update_visual_animation()
	var puppet_clip: String = puppet.visual_anim_player.current_animation
	if puppet_clip != "death":
		_failures.append("a later _update_visual_animation replaced death with \"%s\"" % puppet_clip)
	else:
		print("  ok   %-28s clip=%s" % ["survives a later update", puppet_clip])
	puppet.free()

	_corpse_falls_to_the_ground()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
