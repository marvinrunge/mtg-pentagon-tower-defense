extends Node

var pool_size: int
var pool: Array[Projectile] = []

@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

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
	
	# Pool exhausted — deactivate oldest projectile and reuse it
	pool[0].deactivate()
	return pool[0]
