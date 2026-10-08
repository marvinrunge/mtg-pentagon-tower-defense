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
##   fog_falloff   how fast the fog thins above eye level; lower climbs higher up slopes and sky
##   exposure      multiplier on the environment's tonemap exposure - the whole frame
const BIOMES: Dictionary = {
	"White": {
		"tint": Color(1.0, 0.93, 0.78), "brightness": 1.1, "amount": 0.45,
		"density_mult": 1.0, "fog_start": 50.0, "fog_end": 100.0, "fog_falloff": 3.0,
		"exposure": 1.0,
	},
	"Blue": {
		"tint": Color(0.55, 0.78, 1.0), "brightness": 1.0, "amount": 0.55,
		"density_mult": 1.15, "fog_start": 45.0, "fog_end": 100.0, "fog_falloff": 3.0,
		"exposure": 1.0,
	},
	# Thick black fog with a faint violet cast, and dim: the swamp should feel like it is
	# always half night. Brightness this low means the fog stays near-black even at noon,
	# so distant terrain and the horizon sink into darkness rather than into haze. It starts
	# at the camera and is near-opaque by ~50 m, so the lane ahead fades out of the dark, and
	# its low falloff carries it up the mountains instead of leaving them clear above it.
	"Black": {
		"tint": Color(0.35, 0.30, 0.42), "brightness": 0.06, "amount": 1.0,
		"density_mult": 5.0, "fog_start": 0.0, "fog_end": 45.0, "fog_falloff": 0.8,
		"exposure": 0.72,
	},
	"Red": {
		"tint": Color(1.0, 0.55, 0.32), "brightness": 1.0, "amount": 0.55,
		"density_mult": 1.15, "fog_start": 45.0, "fog_end": 100.0, "fog_falloff": 3.0,
		"exposure": 1.0,
	},
	# Thick, mossy forest haze that hangs between the trees, not just on the horizon.
	"Green": {
		"tint": Color(0.55, 0.85, 0.45), "brightness": 0.9, "amount": 0.65,
		"density_mult": 3.5, "fog_start": 5.0, "fog_end": 60.0, "fog_falloff": 1.8,
		"exposure": 1.0,
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

## How bright the fog is at night, as a share of the moonlight. Sky3D's scatter goes almost
## black after dusk while the moon still lights the ground brightly, which left a fog that
## only dimmed the lane and read as gone; this gives it a moonlit colour to fall back on.
## The floor goes in before the biome tint, so each biome's hue and brightness still apply.
@export var night_fog_strength: float = 0.1

const _LUMA := Vector3(0.2126, 0.7152, 0.0722)

var _sky3d: Node = null
var _dome: Node = null
var _fog_material: ShaderMaterial = null
var _environment: Environment = null
var _moon: DirectionalLight3D = null

var _center := Vector2.ZERO
var _lane_angles: PackedFloat32Array = []
var _lane_profiles: Array[Dictionary] = []
var _hub_profile: Dictionary = {}

## The authored fog density and exposure the biome multipliers scale.
var _base_density: float = 0.0
var _base_exposure: float = 1.0

## The blended values currently applied, eased toward the target every frame.
var _current: Dictionary = {}

## Lane names in the same order as _lane_profiles, so a surge can be asked for by name.
var _lane_names: Array = []
## A lane's fog thickening for a while - the zombie lord's phase change calls the swamp in
## around it. Lane name -> {"until": msec, "mult": density multiplier}. Eased in and out by
## the same settle as everything else here, so it rolls in rather than switching on.
var _surges: Dictionary = {}


## Called by MainController before the node is added. `lane_markers` are the enemy
## spawners in LANE_NAMES order - they sit on each wedge's centre line, far enough out
## that their direction from the centre is the lane's direction.
func setup(center: Vector3, lane_markers: Array[Node3D], lane_names: Array) -> void:
	_center = Vector2(center.x, center.z)
	_lane_angles.clear()
	_lane_profiles.clear()
	_lane_names = lane_names.duplicate()
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
	_moon = _sky3d.get("moon") as DirectionalLight3D

	# Whatever the scene was authored with is the hub's look, and the base every biome's
	# multipliers apply to.
	_hub_profile = {
		"tint": Color(1, 1, 1), "brightness": 1.0, "amount": 0.0,
		"density_mult": 1.0, "fog_start": float(_dome.fog_start),
		"fog_end": float(_dome.fog_end), "fog_falloff": float(_dome.fog_falloff), "exposure": 1.0,
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
		var profile: Dictionary = _surged(i)
		for key: String in blended:
			blended[key] += profile[key] * w
	return blended


## Thickens `lane_name`'s fog by `mult` for `seconds`: denser, and closing in nearer the
## camera by the same factor.
func surge(lane_name: String, mult: float, seconds: float) -> void:
	_surges[lane_name] = {"until": Time.get_ticks_msec() + int(seconds * 1000.0), "mult": mult}


func _surged(i: int) -> Dictionary:
	var profile: Dictionary = _lane_profiles[i]
	if i >= _lane_names.size() or not _surges.has(String(_lane_names[i])):
		return profile
	var surge_info: Dictionary = _surges[String(_lane_names[i])]
	if Time.get_ticks_msec() >= int(surge_info["until"]):
		_surges.erase(String(_lane_names[i]))
		return profile
	var mult: float = float(surge_info["mult"])
	var thick: Dictionary = profile.duplicate()
	thick["density_mult"] = float(profile["density_mult"]) * mult
	thick["fog_end"] = maxf(float(profile["fog_end"]) / mult, float(profile["fog_start"]) + 8.0)
	return thick


func _apply() -> void:
	var tint: Color = _current["tint"]
	var luma: float = maxf(Vector3(tint.r, tint.g, tint.b).dot(_LUMA), 0.001)
	var hue := Vector3(tint.r, tint.g, tint.b) / luma * float(_current["brightness"])
	_fog_material.set_shader_parameter("biome_tint", hue)
	_fog_material.set_shader_parameter("biome_tint_amount", float(_current["amount"]))
	var floor_color := Vector3.ZERO
	if _moon != null and _moon.visible:
		var moon: Color = _moon.light_color
		floor_color = Vector3(moon.r, moon.g, moon.b) * _moon.light_energy * night_fog_strength
	_fog_material.set_shader_parameter("fog_color_floor", floor_color)
	_dome.fog_density = _base_density * float(_current["density_mult"])
	_dome.fog_start = float(_current["fog_start"])
	_dome.fog_end = maxf(float(_current["fog_end"]), float(_current["fog_start"]) + 1.0)
	_dome.fog_falloff = float(_current["fog_falloff"])
	if _environment != null:
		_environment.tonemap_exposure = _base_exposure * float(_current["exposure"])
