extends Label3D
class_name DamageNumber

var float_speed: float = 2.0
var max_lifetime: float = 0.85
var _life_timer: float = 0.85
var _drift_velocity: Vector3 = Vector3.ZERO
var _start_scale: Vector3 = Vector3(1.3, 1.3, 1.3)
var _target_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	double_sided = false
	font_size = 42
	outline_size = 12
	outline_modulate = Color.BLACK
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Random subtle horizontal drift so multiple stacked damage numbers don't overlap completely
	var angle = randf_range(0, TAU)
	_drift_velocity = Vector3(cos(angle) * 0.4, 0, sin(angle) * 0.4)
	scale = _start_scale

func setup(amount: float, text_color: Color) -> void:
	if amount < 0:
		text = "+%d" % round(abs(amount))
	else:
		text = "%d" % round(amount)
		
	modulate = text_color

func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
		
	# Float upwards and drift outward
	position.y += float_speed * delta
	position += _drift_velocity * delta
	
	# Scale animation: pop initially then return to 1.0
	var elapsed = max_lifetime - _life_timer
	if elapsed < 0.15:
		scale = _start_scale.lerp(_target_scale, elapsed / 0.15)
	else:
		scale = _target_scale
		
	# Fade out during the final 0.35 seconds
	if _life_timer < 0.35:
		modulate.a = clamp(_life_timer / 0.35, 0.0, 1.0)
