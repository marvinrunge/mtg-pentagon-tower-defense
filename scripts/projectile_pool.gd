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
