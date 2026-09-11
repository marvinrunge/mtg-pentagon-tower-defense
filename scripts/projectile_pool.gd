extends Node

var pool_size: int
var pool: Array[Projectile] = []

@export var projectile_scene: PackedScene = preload("res://scenes/misc/projectile.tscn")

func _ready() -> void:
	pool_size = GameSettings.projectile_pool_size
	for i in range(pool_size):
		var proj = projectile_scene.instantiate()
		proj.active = false
		proj.visible = false
		proj.process_mode = Node.PROCESS_MODE_DISABLED
		# Add to the current scene so it can interact with the physics world properly
		add_child(proj)
		pool.append(proj)

## Fires one bolt on EVERY peer, and hands back this machine's copy.
##
## Projectiles are not replicated as nodes. They are pooled, there can be dozens in the
## air, and their whole path is a straight line from a start point along a direction -
## which every peer can draw for itself from the handful of numbers that go out here. The
## alternative, a MultiplayerSpawner per bolt, would put a spawn and a despawn packet on
## the wire for something that lives for two seconds and never deviates.
##
## Only the SERVER's copy does anything. Projectile._on_body_entered has always turned a
## client's bolt into sound and a deactivation rather than damage - that guard was written
## for exactly this, and until now there were no client bolts for it to guard.
##
## The caster is deliberately NOT sent. It is a node, it is only ever needed to credit
## damage, and damage is the half that never leaves the server.
func fire(
	start_pos: Vector3, dir: Vector3, type: int, is_enemy: bool = false,
	multiplier: float = 1.0, damage_override: float = -1.0, aoe_radius: float = 0.0,
	caster: Node3D = null, visual_kind: String = "magic",
	tint: Color = Color(0.8, 0.2, 0.8)
) -> Projectile:
	var proj: Projectile = get_projectile()
	proj.activate(start_pos, dir, type, is_enemy, multiplier, damage_override, aoe_radius,
		caster, visual_kind, tint)
	if Net.is_active() and Net.is_server():
		_net_fire.rpc(start_pos, dir, type, is_enemy, multiplier, damage_override,
			aoe_radius, visual_kind, tint)
	return proj


## Unreliable, because a bolt is a cosmetic on this side and one that never arrives is a
## missing flash rather than a broken game state - and a resend that lands after the shot
## has already hit is worse than the miss.
@rpc("authority", "call_remote", "unreliable")
func _net_fire(
	start_pos: Vector3, dir: Vector3, type: int, is_enemy: bool,
	multiplier: float, damage_override: float, aoe_radius: float,
	visual_kind: String, tint: Color
) -> void:
	get_projectile().activate(start_pos, dir, type, is_enemy, multiplier, damage_override,
		aoe_radius, null, visual_kind, tint)


func get_projectile() -> Projectile:
	for proj in pool:
		if not proj.active:
			return proj
	
	# Pool exhausted — reuse the oldest projectile as-is. The caller activates it
	# synchronously right after this returns (no await in between), and activate()
	# fully reinitializes every field deactivate() would touch. Calling deactivate()
	# here would queue a deferred process_mode change that lands *after* the
	# reactivation and disables the projectile it just reused, freezing it in place
	# forever (life_timer stops ticking under PROCESS_MODE_DISABLED).
	return pool[0]
