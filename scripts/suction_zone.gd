extends Node3D
class_name SuctionZone
## Blue's blue_4: the lingering eye that Suction leaves behind.
##
## The spell used to be a single inward shove. It is now a zone that keeps dragging
## every enemy inside toward its centre for a few seconds - the pull is per-frame and
## gentle, so walking out stays the counterplay the design comment in GameSettings
## promises. Enemies are pulled through `EnemyBase.apply_suction`, which is velocity
## rather than knockback on purpose: the flinch reaction keys off knockback, and a
## held pull would otherwise read as one long flinch.

var radius: float = 12.0
var pull_speed: float = 4.0
var _life_timer: float = 0.0


static func create(p_radius: float, p_duration: float, p_pull_speed: float) -> SuctionZone:
	var zone := SuctionZone.new()
	zone.radius = p_radius
	zone.pull_speed = p_pull_speed
	zone._life_timer = p_duration
	zone.name = "SuctionZone"
	return zone


func _physics_process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	# Enemy movement is the server's: a client dragging its puppet copies would fight
	# the replicated transform and win for one frame at a time.
	if not Net.is_server():
		return
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > radius:
			continue
		if enemy.has_method("apply_suction"):
			enemy.apply_suction(global_position, pull_speed)
