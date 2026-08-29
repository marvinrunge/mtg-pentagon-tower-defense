extends Node3D
class_name EnemyHealthBar

const BAR_WIDTH: float = 1.1

@onready var fill: MeshInstance3D = $Fill

var target: Node3D
var camera: Camera3D
var health_ratio: float = 1.0

func _ready() -> void:
	target = get_parent() as Node3D
	camera = get_viewport().get_camera_3d()
	top_level = true
	SignalBus.enemy_health_bars_visibility_changed.connect(_on_visibility_changed)
	_update_visibility()

func _process(_delta: float) -> void:
	if is_instance_valid(target):
		var target_scale: float = maxf(absf(target.scale.x), absf(target.scale.z))
		global_position = target.global_position + Vector3.UP * GameSettings.enemy_health_bar_height * target_scale
		scale = Vector3.ONE * target_scale

	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if camera:
		look_at(camera.global_position, Vector3.UP, true)

func set_health(current: float, maximum: float) -> void:
	health_ratio = clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	fill.scale.x = maxf(health_ratio, 0.001)
	fill.position.x = -BAR_WIDTH * (1.0 - health_ratio) * 0.5
	_update_visibility()

func _on_visibility_changed(_is_enabled: bool) -> void:
	_update_visibility()

func _update_visibility() -> void:
	visible = GameSettings.show_enemy_health_bars and health_ratio > 0.0 and health_ratio < 1.0
	# Most enemies sit at full health most of the time (or have bars disabled
	# entirely) - skip the per-frame position/billboard work for hidden bars
	# instead of just not drawing them.
	set_process(visible)
