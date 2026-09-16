extends Node3D
class_name EnemyHealthBar

const BAR_WIDTH: float = 1.1

@onready var background: MeshInstance3D = $Background
@onready var fill: MeshInstance3D = $Fill
@onready var modifier_label: Label3D = $ModifierLabel

var target: Node3D
var camera: Camera3D
var health_ratio: float = 1.0
## The active boss modifier's name, or "" for none. Kept separately from the bar
## fill/background because it has to stay visible at full health too - see
## set_modifier_tag() - while the bar itself only shows once the boss has taken a hit.
var _modifier_tag: String = ""

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


## Names the boss modifier this enemy is carrying, in its own telegraph tint - see
## EnemyBase._apply_boss_modifier_tag. Shown from the moment the boss spawns rather than
## gated behind the same "has taken damage" rule as the bar itself: a player should know
## what they are about to fight, not only what they already are.
func set_modifier_tag(text: String, color: Color) -> void:
	_modifier_tag = text
	modifier_label.text = text
	modifier_label.modulate = color
	_update_visibility()


func _on_visibility_changed(_is_enabled: bool) -> void:
	_update_visibility()

func _update_visibility() -> void:
	var enabled: bool = GameSettings.show_enemy_health_bars
	var show_bar: bool = enabled and health_ratio > 0.0 and health_ratio < 1.0
	var show_tag: bool = enabled and _modifier_tag != ""
	background.visible = show_bar
	fill.visible = show_bar
	modifier_label.visible = show_tag
	visible = show_bar or show_tag
	# Most enemies sit at full health most of the time (or have bars disabled
	# entirely) - skip the per-frame position/billboard work for hidden bars
	# instead of just not drawing them.
	set_process(visible)
