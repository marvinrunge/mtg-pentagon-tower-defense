extends ColorRect
class_name Minimap

# The world size to map (radius from center)
# The outer edge of the pentagon is at distance ~164 from the center.
# We'll use 180 to give it a little padding.
@export var world_radius: float = 180.0

@export var player_color: Color = Color.GREEN
@export var enemy_color: Color = Color.RED
@export var myr_color: Color = Color.CYAN
@export var base_color: Color = Color.WHITE

func _process(_delta: float) -> void:
	# Continuously request to redraw the minimap
	queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	var scale_factor = (size.x / 2.0) / world_radius
	
	# Draw the base at the center
	draw_circle(center, 4.0, base_color)
	
	# Draw Myrs
	var myrs = get_tree().get_nodes_in_group("myrs")
	for myr in myrs:
		var pos = _world_to_map(myr.global_position, center, scale_factor)
		draw_circle(pos, 2.5, myr_color)
		
	# Draw Enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var pos = _world_to_map(enemy.global_position, center, scale_factor)
		draw_circle(pos, 3.0, enemy_color)
		
	# Draw Players
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		var pos = _world_to_map(player.global_position, center, scale_factor)
		
		# Draw view direction indicator as a triangle (arrow)
		var forward_3d = -player.global_transform.basis.z
		var forward_2d = Vector2(forward_3d.x, forward_3d.z).normalized()
		var right_2d = forward_2d.rotated(PI/2.0)
		
		var p1 = pos + forward_2d * 8.0
		var p2 = pos - forward_2d * 6.0 + right_2d * 5.0
		var p3 = pos - forward_2d * 6.0 - right_2d * 5.0
		
		draw_polygon(PackedVector2Array([p1, p2, p3]), PackedColorArray([player_color]))

func _world_to_map(world_pos: Vector3, center: Vector2, scale_factor: float) -> Vector2:
	# Godot 3D coordinates: X is right, Z is backward (or forward if negative)
	# Minimap 2D coordinates: X is right, Y is down
	# So X maps to X, and Z maps to Y.
	return center + Vector2(world_pos.x, world_pos.z) * scale_factor
