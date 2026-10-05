extends Node
class_name BiomeAtmosphere
## Gives each lane's biome its own air: a fog colour, a fog thickness and, for Black, a
## darker exposure. Follows the active camera, so whoever is looking sees the biome they
## are standing in, and blends across the seams between wedges and into the hub so walking
## from one lane to the next never pops.
##
## The fog is Sky3D's own screen-space fog (SkyDome.fog_*). Its colour comes from the
## atmosphere's scattering, which is what makes it follow day, dusk and night - so the hue
## is not replaced here but pulled toward the biome's tint by the two uniforms AtmFog was
## patched with (biome_tint, biome_tint_amount), leaving the brightness where Sky3D put it.
## A bright green fog would otherwise glow in the dark.
##
## Attached to the Sky3D node by MainController.

## Per-biome settings, keyed by MainController.LANE_NAMES.
##   tint          hue the fog is pulled toward (normalised to unit luminance on use)
##   brightness    multiplier on that hue's luminance; below 1 makes the fog itself darker
##   amount        0 keeps Sky3D's colour, 1 is fully the tint
##   density_mult  multiplier on the fog_density authored on the SkyDome
##   fog_start     metres from the camera where the fog begins
##   fog_end       metres where it reaches full strength
##   exposure      multiplier on the environment's tonemap exposure - the whole frame
const BIOMES: Dictionary = {
	"White": {
		"tint": Color(1.0, 0.93, 0.78), "brightness": 1.1, "amount": 0.45,
		"density_mult": 1.0, "fog_start": 50.0, "fog_end": 100.0, "exposure": 1.0,
	},
	"Blue": {
		"tint": Color(0.55, 0.78, 1.0), "brightness": 1.0, "amount": 0.55,
		"density_mult": 1.15, "fog_start": 45.0, "fog_end": 100.0, "exposure": 1.0,
	},
	# Thick, violet-black and dim: the swamp should feel like it is always half night.
	"Black": {
		"tint": Color(0.38, 0.32, 0.48), "brightness": 0.4, "amount": 0.75,
		"density_mult": 2.0, "fog_start": 18.0, "fog_end": 85.0, "exposure": 0.72,
	},
	"Red": {
		"tint": Color(1.0, 0.55, 0.32), "brightness": 1.0, "amount": 0.55,
		"density_mult": 1.15, "fog_start": 45.0, "fog_end": 100.0, "exposure": 1.0,
	},
	# Thick, mossy forest haze.
	"Green": {
		"tint": Color(0.55, 0.85, 0.45), "brightness": 0.9, "amount": 0.65,
		"density_mult": 1.9, "fog_start": 20.0, "fog_end": 90.0, "exposure": 1.0,
	},
}

## The crystal hub between the wedges keeps the scene's authored look. Within hub_inner of
## the centre it is all hub; by hub_outer it is all lane. The wedges start at radius ~40.
@export var hub_inner_radius: float = 30.0
@export var hub_outer_radius: float = 50.0

## How far either side of a wedge's edge the two biomes are blended, in degrees.
@export var seam_blend_degrees: float = 10.0

## How quickly the look settles on the target, per second. ~1.5 settles in about two
## seconds, which also hides the jump when the camera teleports (respawn, recall).
@export var settle_rate: float = 1.5

const _LUMA := Vector3(0.2126, 0.7152, 0.0722)

var _sky3d: Node = null
var _dome: Node = null
var _fog_material: ShaderMaterial = null
var _environment: Environment = null

var _center := Vector2.ZERO
var _lane_angles: PackedFloat32Array = []
var _lane_profiles: Array[Dictionary] = []
var _hub_profile: Dictionary = {}

## The authored fog density and exposure the biome multipliers scale.
var _base_density: float = 0.0
var _base_exposure: float = 1.0

## The blended values currently applied, eased toward the target every frame.
var _current: Dictionary = {}


## Called by MainController before the node is added. `lane_markers` are the enemy
## spawners in LANE_NAMES order - they sit on each wedge's centre line, far enough out
## that their direction from the centre is the lane's direction.
func setup(center: Vector3, lane_markers: Array[Node3D], lane_names: Array) -> void:
	_center = Vector2(center.x, center.z)
	_lane_angles.clear()
	_lane_profiles.clear()
	for i in lane_markers.size():
		var p: Vector3 = lane_markers[i].global_position
		_lane_angles.append(atan2(p.z - _center.y, p.x - _center.x))
		_lane_profiles.append(BIOMES.get(String(lane_names[i]), {}))


func _ready() -> void:
	_sky3d = get_parent()
	_dome = _sky3d.get("sky") if _sky3d != null else null
	if _dome == null or not ("fog_material" in _dome):
		push_error("BiomeAtmosphere expects to be a child of a Sky3D node.")
		set_process(false)
		return
	_fog_material = _dome.fog_material as ShaderMaterial
	_environment = (_sky3d as WorldEnvironment).environment

	# Whatever the scene was authored with is the hub's look, and the base every biome's
	# multipliers apply to.
	_hub_profile = {
		"tint": Color(1, 1, 1), "brightness": 1.0, "amount": 0.0,
		"density_mult": 1.0, "fog_start": float(_dome.fog_start),
		"fog_end": float(_dome.fog_end), "exposure": 1.0,
	}
	_base_density = float(_dome.fog_density)
	_base_exposure = _environment.tonemap_exposure if _environment != null else 1.0
	for i in _lane_profiles.size():
		if _lane_profiles[i].is_empty():
			_lane_profiles[i] = _hub_profile

	_current = _target()
	_apply()


func _process(delta: float) -> void:
	var target: Dictionary = _target()
	var t: float = 1.0 - exp(-settle_rate * delta)
	for key: String in _current:
		_current[key] = lerp(_current[key], target[key], t)
	_apply()


## The blended profile for wherever the active camera is. Without a camera (a headless
## server, a scene change in progress) that is the hub.
func _target() -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _lane_angles.is_empty():
		return _hub_profile.duplicate()

	var offset := Vector2(camera.global_position.x, camera.global_position.z) - _center
	var hub_weight: float = 1.0 - smoothstep(hub_inner_radius, hub_outer_radius, offset.length())
	var angle: float = offset.angle()

	# Each wedge owns the half-angle either side of its centre line; within the seam the
	# two neighbours' smoothsteps cross and sum to one.
	var half: float = PI / float(_lane_angles.size())
	var seam: float = deg_to_rad(seam_blend_degrees)
	var weights: PackedFloat32Array = []
	var total: float = 0.0
	for lane_angle in _lane_angles:
		var d: float = absf(angle_difference(angle, lane_angle))
		var w: float = 1.0 - smoothstep(half - seam, half + seam, d)
		weights.append(w)
		total += w

	var blended: Dictionary = _hub_profile.duplicate()
	for key: String in blended:
		blended[key] = blended[key] * hub_weight
	var lane_share: float = (1.0 - hub_weight) / maxf(total, 0.0001)
	for i in weights.size():
		var w: float = weights[i] * lane_share
		if w <= 0.0:
			continue
		for key: String in blended:
			blended[key] += _lane_profiles[i][key] * w
	return blended


func _apply() -> void:
	var tint: Color = _current["tint"]
	var luma: float = maxf(Vector3(tint.r, tint.g, tint.b).dot(_LUMA), 0.001)
	var hue := Vector3(tint.r, tint.g, tint.b) / luma * float(_current["brightness"])
	_fog_material.set_shader_parameter("biome_tint", hue)
	_fog_material.set_shader_parameter("biome_tint_amount", float(_current["amount"]))
	_dome.fog_density = _base_density * float(_current["density_mult"])
	_dome.fog_start = float(_current["fog_start"])
	_dome.fog_end = maxf(float(_current["fog_end"]), float(_current["fog_start"]) + 1.0)
	if _environment != null:
		_environment.tonemap_exposure = _base_exposure * float(_current["exposure"])
