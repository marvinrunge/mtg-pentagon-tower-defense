extends Node3D
## The fireball a player builds between their hands while Fireball is held.
##
## Deliberately NO `class_name`. A headless run does not rescan the project, so a newly added
## global class is not in .godot/global_script_class_cache.cfg until an editor session picks it
## up - and a script that names its own class in a signature then fails to compile on exactly
## the runs that would catch a mistake in it. Callers preload this by path and call `new()`,
## the same rule tools/animation_impact.gd documents.
##
## Fireball charges for three seconds (GameSettings.spell_charge_max_time) and, until this
## existed, nothing at all happened in that time: a slowly raising arm and a HUD bar, then a
## single flash at the moment of release. The ball appeared to come from nowhere, unconnected
## to the hold that produced it.
##
## Five things escalate together across the hold, because size alone does not read as power:
## the sphere grows, the colour climbs from ember red through orange to a white-hot core, the
## light gets brighter and reaches further, the embers gather faster, and at full charge the
## whole thing snaps to white and rings once.
##
## The embers move INWARD, which is the part doing most of the work. Particles drawn into the
## ball read as something being gathered; particles coming off it read as something already
## burning, which is what every other fire effect in the game is. Same negative radial
## acceleration SpellFx.vortex uses to make Suction read as a pull rather than a carousel.
##
## Premultiplied alpha throughout, like the rest of the effect layer - see
## docs/SPELL_VFX_PLAN.md. Additive would vanish against the sky, and a run now opens at 07:00.

## What the sphere measures at no charge and at full, before rank scaling. The small end is
## deliberately tiny: a charge that starts at half its final size has nowhere to go.
## These are SPHERE RADII, and the mesh below is a unit sphere - so 0.20 is a 40cm ball. The
## first pass used 0.55, which is a 1.1m ball: at full charge it swallowed the caster's head
## and most of their torso. A held spell has to read as held, not as worn.
const MIN_RADIUS := 0.03
const MAX_RADIUS := 0.28

## Growth is a CURVE, not a line. A linear ramp over three seconds reads as nothing happening
## for the first second; at 0.6 the ball swells early and then creeps, which is what makes the
## last half-second feel like it is straining.
const GROWTH_EXPONENT := 0.6

## The heat ladder. Deep ember at rest, orange through the middle, white-hot at the top - the
## last of which is the cue that the charge is ready, so it is a hard switch rather than the
## end of a gradient.
const COLD_TINT := Color(0.85, 0.16, 0.03)
const HOT_TINT := Color(1.0, 0.55, 0.12)
const FULL_TINT := Color(1.0, 0.93, 0.72)
## Where the colour stops warming and starts whitening.
const WHITEN_FROM := 0.7

const LIGHT_ENERGY := Vector2(0.5, 4.2)
const LIGHT_RANGE := Vector2(1.6, 8.0)

var _core: MeshInstance3D
var _shell: MeshInstance3D
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _gather: GPUParticles3D
var _gather_process: ParticleProcessMaterial
var _light: OmniLight3D
var _flicker_phase: float = 0.0
var _progress: float = 0.0
var _size_scale: float = 1.0
var _flared: bool = false
## Which tenth of the charge the ember ramp was last built for. See set_progress.
var _ramp_bucket: int = -1


## `size_scale` is the caster's rank multiplier for area, so a rank-5 charge is visibly bigger
## than a rank-1 one - the spell's own radius already scales that way and the orb should not
## quietly disagree with the thing it becomes.
##
## A method rather than a static factory, because a static one would have to name this class to
## construct it. Callers do `SCRIPT.new()` then `setup()`.
func setup(size_scale: float = 1.0) -> void:
	name = "ChargeOrb"
	_size_scale = maxf(size_scale, 0.1)


func _ready() -> void:
	_core = MeshInstance3D.new()
	_core.name = "Core"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 1.0
	core_mesh.height = 2.0
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	_core.mesh = core_mesh
	_core_material = StandardMaterial3D.new()
	# Shaded with a strong rim rather than unshaded: an unshaded emissive sphere is a flat
	# disc at any distance, which is exactly why the Orb of Fire read as placeholder before
	# it was given a real material.
	_core_material.albedo_color = Color(0.5, 0.11, 0.02)
	_core_material.metallic = 0.1
	_core_material.roughness = 0.5
	_core_material.emission_enabled = true
	_core_material.rim_enabled = true
	_core_material.rim = 0.9
	_core_material.rim_tint = 0.15
	_core_material.render_priority = SpellFx.FX_RENDER_PRIORITY
	_core.material_override = _core_material
	add_child(_core)

	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 1.0
	shell_mesh.height = 2.0
	shell_mesh.radial_segments = 20
	shell_mesh.rings = 10
	_shell.mesh = shell_mesh
	_shell_material = StandardMaterial3D.new()
	_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell_material.emission_enabled = true
	_shell_material.render_priority = SpellFx.FX_RENDER_PRIORITY
	_shell.material_override = _shell_material
	add_child(_shell)

	_gather = GPUParticles3D.new()
	_gather.name = "Gather"
	# Fixed at spawn: changing `amount` at runtime restarts the system, and this one is
	# updated every frame.
	_gather.amount = 44
	_gather.lifetime = 0.7
	_gather.preprocess = 0.7
	_gather.local_coords = true
	_gather.draw_pass_1 = SpellFx.premul_particle_mesh(0.13, "spark")
	_gather_process = ParticleProcessMaterial.new()
	_gather_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_gather_process.emission_sphere_radius = 0.6
	_gather_process.direction = Vector3.UP
	_gather_process.spread = 180.0
	_gather_process.gravity = Vector3.ZERO
	_gather_process.initial_velocity_min = 0.0
	_gather_process.initial_velocity_max = 0.15
	# The pull. Negative radial acceleration drags every mote toward the middle; the
	# tangential term makes them arrive on a curve instead of falling straight in.
	_gather_process.radial_accel_min = -5.0
	_gather_process.radial_accel_max = -2.5
	_gather_process.tangential_accel_min = 1.5
	_gather_process.tangential_accel_max = 3.5
	_gather_process.scale_min = 0.3
	_gather_process.scale_max = 0.9
	_gather_process.color_ramp = SpellFx._premul_ramp(HOT_TINT)
	_gather.process_material = _gather_process
	add_child(_gather)

	_light = EmberFx.build_fire_light(LIGHT_RANGE.x, LIGHT_ENERGY.x)
	add_child(_light)

	set_progress(0.0)


func _process(delta: float) -> void:
	_flicker_phase += delta
	if _light != null:
		# Flickers around whatever energy the charge has set, so the guttering rides on top of
		# the ramp instead of overwriting it.
		var base: float = lerpf(LIGHT_ENERGY.x, LIGHT_ENERGY.y, _progress)
		_light.light_energy = base * (1.0 + sin(_flicker_phase * 21.0) * 0.09 + sin(_flicker_phase * 7.3) * 0.05)
	if _core != null:
		# A slow tumble, so a held orb is never a static ball.
		_core.rotate_y(delta * 1.4)
		_shell.rotate_y(-delta * 0.9)


## Drives the whole effect from one number: how far through the charge the player is, 0 to 1.
func set_progress(charge: float) -> void:
	_progress = clampf(charge, 0.0, 1.0)
	var eased: float = pow(_progress, GROWTH_EXPONENT)
	var radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, eased) * _size_scale

	_core.scale = Vector3.ONE * radius
	# The shell leads the core slightly and thins as it grows, so the ball looks like it is
	# straining against its own surface rather than simply being scaled up.
	_shell.scale = Vector3.ONE * radius * lerpf(1.6, 1.22, _progress)

	var tint: Color = _heat_tint(_progress)
	_core_material.emission = tint
	_core_material.emission_energy_multiplier = lerpf(1.4, 4.0, _progress)
	_core_material.albedo_color = tint.darkened(0.72)
	_shell_material.albedo_color = Color(tint.r, tint.g, tint.b, lerpf(0.10, 0.30, _progress))
	_shell_material.emission = tint
	_shell_material.emission_energy_multiplier = lerpf(0.5, 2.4, _progress)

	_light.light_color = tint
	_light.omni_range = lerpf(LIGHT_RANGE.x, LIGHT_RANGE.y, _progress)

	# The motes are drawn from further out and arrive faster as the charge builds, so the
	# gathering visibly accelerates rather than just widening.
	_gather_process.emission_sphere_radius = radius * lerpf(4.5, 7.0, _progress)
	_gather_process.radial_accel_min = lerpf(-3.0, -11.0, _progress)
	_gather_process.radial_accel_max = lerpf(-1.5, -6.0, _progress)
	# Rebuilt only when the colour has actually moved. This runs every frame, and
	# _premul_ramp allocates a GradientTexture1D each call - sixty throwaway textures a second
	# for a tint that shifts by a fraction of a percent between frames.
	var bucket: int = int(_progress * 10.0)
	if bucket != _ramp_bucket:
		_ramp_bucket = bucket
		_gather_process.color_ramp = SpellFx._premul_ramp(tint)
	_gather_process.scale_min = 0.25 + _progress * 0.35
	_gather_process.scale_max = 0.7 + _progress * 0.8


## The moment the charge completes. One frame of white and a ring, so the player can tell it
## is ready without watching the HUD bar - a three-second hold with no completion cue is a
## hold nobody knows when to end.
##
## Idempotent: the charge sits at 1.0 for as long as the player keeps holding, and this must
## fire once rather than on every frame after.
func flare() -> void:
	if _flared:
		return
	_flared = true
	# An outward spark burst, not SpellFx.shockwave. That builds a GROUND ring - a flat disc
	# lying on the floor plane, which is right for something landing and wrong for something
	# completing in mid-air: the first version drew a two-metre dinner plate through the
	# caster's waist.
	var burst: GPUParticles3D = SpellFx.sparks(FULL_TINT, MAX_RADIUS * _size_scale * 2.0, 20, 3.2)
	burst.one_shot = true
	burst.explosiveness = 1.0
	add_child(burst)
	burst.restart()
	var tween: Tween = create_tween()
	tween.tween_property(_core, "scale", _core.scale * 1.18, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_core, "scale", _core.scale, 0.13)


## Thrown. Scales up hard and fades, leaving the projectile to carry on from where the ball
## actually was - see Player.cast_red_fireball, which spawns the bolt at this node's position
## rather than at the camera.
func release() -> void:
	if _gather != null:
		_gather.emitting = false
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_core, "scale", _core.scale * 1.35, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_shell, "scale", _shell.scale * 1.6, 0.12)
	tween.tween_property(_shell_material, "albedo_color:a", 0.0, 0.12)
	tween.tween_property(_core_material, "emission_energy_multiplier", 0.0, 0.12)
	tween.tween_property(_light, "light_energy", 0.0, 0.1)
	tween.chain().tween_callback(queue_free)


## Dropped rather than thrown - the player let go early or was interrupted. Collapses inward,
## which is the opposite read to release() on purpose: nothing was fired.
func fizzle() -> void:
	if _gather != null:
		_gather.emitting = false
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_core, "scale", Vector3.ZERO, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_shell, "scale", Vector3.ZERO, 0.13)
	tween.tween_property(_light, "light_energy", 0.0, 0.14)
	tween.chain().tween_callback(queue_free)


## Ember red through orange, then hard into white over the last of the charge. Two segments
## rather than one gradient: the whitening is a SIGNAL, and a signal that arrives gradually
## is not one.
func _heat_tint(charge: float) -> Color:
	if charge < WHITEN_FROM:
		return COLD_TINT.lerp(HOT_TINT, charge / WHITEN_FROM)
	return HOT_TINT.lerp(FULL_TINT, (charge - WHITEN_FROM) / (1.0 - WHITEN_FROM))
