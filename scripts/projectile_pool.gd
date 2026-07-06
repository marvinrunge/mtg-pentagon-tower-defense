extends Node

var pool_size: int = 20
var pool: Array[Projectile] = []

@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

func _ready() -> void:
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
	
	# If we run out, maybe spawn a new one or just return the oldest one.
	# For simplicity, we just reuse the first one.
	return pool[0]
