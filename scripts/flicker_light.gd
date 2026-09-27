extends OmniLight3D
class_name FlickerLight
## A light that breathes rather than holds still - a lava glow, a brazier. The energy
## drifts on smooth noise around its authored value, so it wanders instead of strobing.
##
## The authored light_energy is the centre it flickers around; set it in the inspector
## as for any light.

## How far the energy strays from its centre, as a fraction of it.
@export_range(0.0, 1.0) var flicker_amount: float = 0.25
## How fast it wanders. Low is a slow lava pulse, high is a fire.
@export var flicker_speed: float = 0.6

var _base_energy: float
var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_base_energy = light_energy
	_noise.seed = randi()
	_noise.frequency = 1.0


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	light_energy = _base_energy * (1.0 + _noise.get_noise_1d(_time) * flicker_amount)
