extends Label3D
class_name DamageNumber

const FLOAT_SPEED: float = 2.0
const MAX_LIFETIME: float = 0.85
const START_SCALE: Vector3 = Vector3(1.3, 1.3, 1.3)
const TARGET_SCALE: Vector3 = Vector3(1.0, 1.0, 1.0)

var active: bool = false
var _life_timer: float = 0.0
var _drift_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	double_sided = false
	font_size = 42
	outline_size = 12
	outline_modulate = Color.BLACK
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func activate(pos: Vector3, amount: float, text_color: Color) -> void:
	global_position = pos
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_life_timer = MAX_LIFETIME
	modulate = text_color
	scale = START_SCALE

	# Random subtle horizontal drift so multiple stacked damage numbers don't overlap completely
	var angle: float = randf_range(0, TAU)
	_drift_velocity = Vector3(cos(angle) * 0.4, 0, sin(angle) * 0.4)

	if amount < 0:
		text = "+%d" % round(abs(amount))
	else:
		text = "%d" % round(amount)

func deactivate() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	if not active:
		return

	_life_timer -= delta
	if _life_timer <= 0.0:
		deactivate()
		return

	# Float upwards and drift outward
	global_position += Vector3.UP * FLOAT_SPEED * delta + _drift_velocity * delta

	# Scale animation: pop initially then return to 1.0
	var elapsed: float = MAX_LIFETIME - _life_timer
	if elapsed < 0.15:
		scale = START_SCALE.lerp(TARGET_SCALE, elapsed / 0.15)
	else:
		scale = TARGET_SCALE

	# Fade out during the final 0.35 seconds
	modulate.a = clampf(_life_timer / 0.35, 0.0, 1.0) if _life_timer < 0.35 else 1.0
