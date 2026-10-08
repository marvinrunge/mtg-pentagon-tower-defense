extends Node3D
class_name OrbitingOrb
## The orb that hangs beside a player for the orb auras.
##
## Winter Orb (blue), Orb of Fire and Lightning Orb (red), Healing Orb (white) and the Soul
## Orb of Grave Pact (black) are one implementation with five payloads, because the only
## thing that differs between them is what happens on the tick - everything else, the orbit,
## the bob, the light, the target search, is shared. Writing five of these was the
## alternative, and five copies of an orbit is how the fifth one ends up subtly out of step
## with the others.
##
## It lives as a child of the player and follows them by being parented to them, so
## nothing here has to chase a moving anchor.

enum Mode { FROST, FIRE, HEAL, SOUL, LIGHTNING }

var mode: int = Mode.FROST

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _owner: Node3D
var _mesh: MeshInstance3D
var _light: OmniLight3D
## Fire's light flickers, heal's breathes, the soul orb brightens with what it holds.
var _light_phase: float = 0.0
var _light_base_energy: float = 0.45
## Grave Pact's stored souls - see add_soul. Server-side, like every payload.
var _souls: int = 0
var _soul_material: StandardMaterial3D = null

const COLORS: Dictionary = {
	Mode.FROST: Color(0.45, 0.8, 1.0),
	Mode.FIRE: Color(1.0, 0.45, 0.12),
	Mode.HEAL: Color(1.0, 0.95, 0.65),
	# The raised dead's own green, so a soul reads as the same substance as the zombies.
	Mode.SOUL: Color(0.45, 1.0, 0.62),
	# Lightning Bolt's blue-white - the same strike, in small.
	Mode.LIGHTNING: Color(0.75, 0.88, 1.0),
}

## Where each orb sits in the halo. They used to CIRCLE the player - up to three metres out,
## at head height - which put them straight through the over-the-shoulder camera's view every
## few seconds: three glowing balls sweeping between the player and what they were aiming at.
##
## Now they share one small, slow halo above and to the LEFT of the head. The camera sits over
## the right shoulder, so the left is the side of the frame the aim line never crosses, and a
## ring well under a metre across never reaches the camera at all. It reads as a familiar
## perched on the player rather than as satellites.
##
## One ring and one speed for all five, each on its own fifth of it. That is what keeps them
## apart whichever of them a player owns: any two sit at least a fifth of a turn apart for good,
## so their separation is a fixed chord instead of something two speeds bring together now and
## then. tools/tests/orb_orbits.gd brute-forces the minimum separation and fails if it closes.
##
## `bob` is metres, `bob_rate` radians per second - kept small and out of step with each
## other so the five do not rise and fall as one rigid rack.
const ORBIT_PLAN: Dictionary = {
	Mode.FROST: {"phase": 0.0, "bob": 0.035, "bob_rate": 2.1},
	Mode.FIRE: {"phase": TAU * 0.2, "bob": 0.035, "bob_rate": 2.7},
	Mode.HEAL: {"phase": TAU * 0.4, "bob": 0.035, "bob_rate": 1.6},
	Mode.SOUL: {"phase": TAU * 0.6, "bob": 0.035, "bob_rate": 2.4},
	Mode.LIGHTNING: {"phase": TAU * 0.8, "bob": 0.035, "bob_rate": 3.1},
}


## Where `mode`'s orb sits, local to the player, `time` seconds in.
##
## Static and pure so the separation between the orbs can be measured directly by a test -
## no scene, no player, no frames.
static func orbit_position(orb_mode: int, time: float) -> Vector3:
	var plan: Dictionary = ORBIT_PLAN[orb_mode]
	var radius: float = GameSettings.aura_orb_radius
	var angle: float = time * GameSettings.aura_orb_speed + float(plan["phase"])
	var centre: Vector3 = GameSettings.aura_orb_halo_centre
	var height: float = centre.y + sin(time * float(plan["bob_rate"])) * float(plan["bob"])
	# A slight cant, applied as a rise and fall around the ring rather than by rotating the
	# orbit basis - same look, and it keeps this function one expression a test can reason
	# about. The same cant for every orb, so it moves them together and cannot close a gap.
	height += sin(angle) * radius * GameSettings.aura_orb_tilt
	return Vector3(centre.x + cos(angle) * radius, height, centre.z + sin(angle) * radius)


static func create(p_mode: int, p_owner: Node3D) -> OrbitingOrb:
	var orb := OrbitingOrb.new()
	orb.mode = p_mode
	orb._owner = p_owner
	orb.name = "AuraOrb"
	return orb


func _ready() -> void:
	var tint: Color = COLORS[mode]

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	_mesh.mesh = sphere
	var mat: StandardMaterial3D = _orb_material(tint)
	_mesh.material_override = mat
	add_child(_mesh)
	match mode:
		Mode.FROST: _build_frost_crown()
		Mode.FIRE: _build_fire_body()
		Mode.HEAL: _build_heal_body()
		Mode.SOUL: _build_soul_body()
		Mode.LIGHTNING: _build_lightning_body()

	# A glow on the player, not a lamp. Up to four of these travel with the player, and at the
	# strength they used to have they lit the ground around them in four moving colours - the
	# most visible thing on screen was the orbs' light, not the orbs.
	_light = OmniLight3D.new()
	_light.light_color = tint
	_light_base_energy = GameSettings.aura_orb_light_energy
	# Fire's own light is warmer than its bolt colour - a fire that lights the ground the
	# same orange it is drawn in reads as a flat sticker rather than as something burning.
	if mode == Mode.FIRE:
		_light.light_color = Color(1.0, 0.62, 0.28)
		_light_base_energy *= 1.3
	_light.light_energy = _light_base_energy
	# What EmberFx.flicker swings around - without it the fire orb flickers about 1.0,
	# twice what the others glow at.
	_light.set_meta("base_energy", _light_base_energy)
	_light.omni_range = GameSettings.aura_orb_light_range
	_light.shadow_enabled = false
	add_child(_light)

	# Staggered so a player holding several does not see them fire in lockstep, and so the
	# first tick does not land on the same frame the aura is bought.
	_tick_timer = _interval() * (0.25 + 0.2 * float(mode))


func _orb_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if mode == Mode.FROST:
		mat.albedo_color = Color(0.78, 0.94, 1.0, 0.92)
		mat.metallic = 0.82
		mat.roughness = 0.18
		mat.emission_enabled = true
		mat.emission = Color(0.62, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.6
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.rim_enabled = true
		mat.rim = 0.75
		mat.rim_tint = 0.25
		return mat
	if mode == Mode.FIRE:
		# Shaded, not UNSHADED. That one flag is most of why this orb read as placeholder next
		# to the frost one: an unshaded emissive sphere has no light falling across it and no
		# rim, so at any distance it is a flat orange circle rather than a ball.
		mat.albedo_color = Color(0.55, 0.13, 0.02)
		mat.metallic = 0.15
		mat.roughness = 0.55
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.42, 0.08)
		mat.emission_energy_multiplier = 1.7
		mat.rim_enabled = true
		mat.rim = 0.9
		mat.rim_tint = 0.15
		return mat
	if mode == Mode.LIGHTNING:
		# A white-hot core: unshaded on purpose, unlike fire's crust - a spark has no surface
		# for light to fall across, it IS the light.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.92, 0.96, 1.0)
		return mat
	if mode == Mode.SOUL:
		# Dark, with the light INSIDE it: a violet-black husk the stored souls glow through.
		# The emission is what _update_soul_glow moves - an empty orb is nearly black, a full
		# one burns the zombies' green.
		mat.albedo_color = Color(0.16, 0.06, 0.22)
		mat.metallic = 0.3
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.3
		mat.rim_enabled = true
		mat.rim = 0.8
		mat.rim_tint = 0.5
		_soul_material = mat
		return mat
	# HEAL. Pale and soft rather than hot: low emission with a strong rim, so the light reads
	# as coming off the surface instead of out of it.
	mat.albedo_color = Color(1.0, 0.96, 0.82)
	mat.metallic = 0.1
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.68)
	mat.emission_energy_multiplier = 1.1
	mat.rim_enabled = true
	mat.rim = 0.95
	mat.rim_tint = 0.4
	return mat


func _build_frost_crown() -> void:
	var crown := MeshInstance3D.new()
	crown.name = "FrostCrown"
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	crown.mesh = mesh
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.56, 0.86, 1.0, 0.2)
	shell.emission_enabled = true
	shell.emission = Color(0.5, 0.86, 1.0)
	shell.emission_energy_multiplier = 0.35
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.metallic = 0.35
	shell.roughness = 0.08
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = shell
	add_child(crown)

	var shards := GPUParticles3D.new()
	shards.name = "FrostOrbitShards"
	shards.amount = 8
	shards.lifetime = 1.8
	shards.preprocess = 1.8
	shards.draw_pass_1 = SpellFx.premul_particle_mesh(0.14, "shard")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.scale_min = 0.05
	process.scale_max = 0.14
	process.color_ramp = SpellFx._premul_ramp(Color(0.65, 0.92, 1.0))
	shards.process_material = process
	add_child(shards)


## Orb of Fire, in fire's own language: a dark molten shell over a hot core, a flame
## guttering off the top, and embers shedding off the outside.
##
## Premultiplied throughout (SpellFx rather than EmberFx's additive builders) - see
## docs/SPELL_VFX_PLAN.md. Additive fire is invisible against a bright sky, which is exactly
## where an orb hovering over a player's head sits.
func _build_fire_body() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "FireShell"
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	shell.mesh = mesh
	var crust := StandardMaterial3D.new()
	# Dark and rough, so the bright core shows THROUGH it in patches rather than being
	# wrapped in more of the same orange.
	crust.albedo_color = Color(0.32, 0.09, 0.03, 0.42)
	crust.emission_enabled = true
	crust.emission = Color(1.0, 0.35, 0.06)
	crust.emission_energy_multiplier = 0.8
	crust.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crust.roughness = 0.85
	crust.rim_enabled = true
	crust.rim = 0.9
	crust.rim_tint = 0.1
	crust.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = crust
	add_child(shell)

	var flame := GPUParticles3D.new()
	flame.name = "OrbFlame"
	flame.amount = 12
	flame.lifetime = 0.7
	flame.preprocess = 0.7
	flame.local_coords = true
	flame.draw_pass_1 = SpellFx.premul_particle_mesh(0.3, "smoke")
	var rising := ParticleProcessMaterial.new()
	rising.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rising.emission_sphere_radius = 0.09
	rising.direction = Vector3.UP
	rising.spread = 24.0
	# Fire falls UP, the same trick EmberFx.build_flame uses: positive gravity makes the
	# tongue accelerate away instead of arcing back down like debris.
	rising.gravity = Vector3(0.0, 0.6, 0.0)
	rising.initial_velocity_min = 0.2
	rising.initial_velocity_max = 0.55
	rising.angle_min = -180.0
	rising.angle_max = 180.0
	rising.scale_min = 0.4
	rising.scale_max = 0.8
	rising.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.52, 0.14))
	flame.process_material = rising
	add_child(flame)

	var embers := GPUParticles3D.new()
	embers.name = "OrbEmbers"
	embers.amount = 6
	embers.lifetime = 1.0
	embers.preprocess = 1.0
	# World space, unlike the flame: embers are shed and LEFT BEHIND, so a moving orb should
	# trail them rather than drag them along in a clump.
	embers.local_coords = false
	embers.draw_pass_1 = SpellFx.premul_particle_mesh(0.06, "spark")
	var shed := ParticleProcessMaterial.new()
	shed.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	shed.emission_sphere_radius = 0.15
	shed.direction = Vector3.UP
	shed.spread = 180.0
	shed.gravity = Vector3(0.0, -0.35, 0.0)
	shed.initial_velocity_min = 0.08
	shed.initial_velocity_max = 0.3
	shed.scale_min = 0.05
	shed.scale_max = 0.12
	shed.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.72, 0.3))
	embers.process_material = shed
	add_child(embers)


## Lightning Orb: a white-hot core in a shell of blue light, crackling - small arcs of the
## same lightning it throws flick on and off around it.
func _build_lightning_body() -> void:
	var crackle := GPUParticles3D.new()
	crackle.name = "OrbCrackle"
	crackle.amount = 8
	crackle.lifetime = 0.12
	crackle.preprocess = 0.2
	crackle.local_coords = true
	crackle.draw_pass_1 = SpellFx.premul_particle_mesh(0.34, "arc")
	var jitter := ParticleProcessMaterial.new()
	jitter.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	jitter.emission_sphere_radius = 0.12
	jitter.spread = 180.0
	jitter.initial_velocity_min = 0.0
	jitter.initial_velocity_max = 0.2
	jitter.gravity = Vector3.ZERO
	jitter.angle_min = -180.0
	jitter.angle_max = 180.0
	jitter.scale_min = 0.5
	jitter.scale_max = 1.0
	jitter.color_ramp = SpellFx._premul_ramp(COLORS[Mode.LIGHTNING])
	crackle.process_material = jitter
	add_child(crackle)

	var sparks := GPUParticles3D.new()
	sparks.name = "OrbSparks"
	sparks.amount = 6
	sparks.lifetime = 0.5
	sparks.preprocess = 0.5
	sparks.local_coords = false
	sparks.draw_pass_1 = SpellFx.premul_particle_mesh(0.05, "spark")
	var shed := ParticleProcessMaterial.new()
	shed.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	shed.emission_sphere_radius = 0.14
	shed.spread = 180.0
	shed.initial_velocity_min = 0.3
	shed.initial_velocity_max = 0.9
	shed.gravity = Vector3(0.0, -1.0, 0.0)
	shed.color_ramp = SpellFx._premul_ramp(COLORS[Mode.LIGHTNING])
	sparks.process_material = shed
	add_child(sparks)


## Healing Orb. The one that is not a weapon, so it is built to read as calm where fire
## reads as violent: a soft halo instead of a crust, motes drifting UP out of it instead of
## shedding off it, and a ring lying flat around it that nothing else has.
func _build_heal_body() -> void:
	var halo := MeshInstance3D.new()
	halo.name = "HealHalo"
	var mesh := SphereMesh.new()
	mesh.radius = 0.19
	mesh.height = 0.38
	halo.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.97, 0.82, 0.14)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.93, 0.7)
	glow.emission_energy_multiplier = 0.45
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.roughness = 0.25
	glow.rim_enabled = true
	glow.rim = 0.85
	glow.rim_tint = 0.3
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = glow
	add_child(halo)

	# A flat ring around the orb's equator. The one silhouette cue the others do not have,
	# which is what lets a glance tell the white orb from the blue one at distance, where both
	# are pale and the colours have washed together.
	var ring := MeshInstance3D.new()
	ring.name = "HealRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.25
	ring.mesh = torus
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(1.0, 0.95, 0.75, 0.45)
	band.emission_enabled = true
	band.emission = Color(1.0, 0.9, 0.62)
	band.emission_energy_multiplier = 1.1
	band.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = band
	ring.rotation_degrees = Vector3(14.0, 0.0, 8.0)
	add_child(ring)

	var motes := GPUParticles3D.new()
	motes.name = "HealMotes"
	motes.amount = 7
	motes.lifetime = 1.6
	motes.preprocess = 1.6
	motes.local_coords = true
	# "mote" rather than "spark": rays instead of a round speck, so these read as something
	# rising rather than as more embers in a different colour.
	motes.draw_pass_1 = SpellFx.premul_particle_mesh(0.1, "mote")
	var drift := ParticleProcessMaterial.new()
	drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	drift.emission_sphere_radius = 0.17
	drift.direction = Vector3.UP
	drift.spread = 30.0
	drift.gravity = Vector3(0.0, 0.2, 0.0)
	drift.initial_velocity_min = 0.08
	drift.initial_velocity_max = 0.22
	drift.angle_min = -180.0
	drift.angle_max = 180.0
	drift.scale_min = 0.35
	drift.scale_max = 0.8
	drift.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.95, 0.72))
	motes.process_material = drift
	add_child(motes)


## Grave Pact's Soul Orb. Black's Manifestation used to be a number - a heal and a stacking
## damage bonus nobody could see - and is now a thing hanging beside the player: a dark husk
## the souls of whatever dies nearby are drawn into, and that throws them back out at the
## living. The wisps circling it are the souls it is holding.
func _build_soul_body() -> void:
	var wisps := GPUParticles3D.new()
	wisps.name = "SoulWisps"
	wisps.amount = 8
	wisps.lifetime = 1.4
	wisps.preprocess = 1.4
	wisps.local_coords = true
	wisps.draw_pass_1 = SpellFx.premul_particle_mesh(0.12, "mote")
	var swirl := ParticleProcessMaterial.new()
	swirl.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	swirl.emission_ring_axis = Vector3.UP
	swirl.emission_ring_radius = 0.2
	swirl.emission_ring_inner_radius = 0.16
	swirl.emission_ring_height = 0.05
	swirl.direction = Vector3.UP
	swirl.spread = 40.0
	swirl.gravity = Vector3(0.0, 0.15, 0.0)
	swirl.initial_velocity_min = 0.02
	swirl.initial_velocity_max = 0.1
	swirl.orbit_velocity_min = 0.4
	swirl.orbit_velocity_max = 0.7
	swirl.scale_min = 0.3
	swirl.scale_max = 0.7
	swirl.color_ramp = SpellFx._premul_ramp(COLORS[Mode.SOUL])
	wisps.process_material = swirl
	add_child(wisps)
	_update_soul_glow()


func _process(delta: float) -> void:
	if not is_instance_valid(_owner):
		queue_free()
		return

	_elapsed += delta
	# Local to the player, so the halo does not have to be recomputed from the player's
	# world position every frame - and so it keeps its place while they move.
	position = orbit_position(mode, _elapsed)
	_animate_light(delta)

	# The payload is a game effect, so it is the server's, exactly like a spell. The
	# halo above is cosmetic and runs everywhere, which is what keeps the orb visible on
	# every client without any of them deciding it dealt damage.
	if not Net.is_server():
		return
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = _interval()
	match mode:
		Mode.FROST: _fire_frost()
		Mode.FIRE: _fire_flame()
		Mode.HEAL: _heal_lowest()
		Mode.SOUL: _release_soul()
		Mode.LIGHTNING: _fire_lightning()


## Fire gutters, heal breathes, frost holds steady, the soul orb burns brighter the more it
## holds. Kept faint on purpose - see _ready.
func _animate_light(delta: float) -> void:
	if _light == null:
		return
	_light_phase += delta
	match mode:
		Mode.FIRE:
			EmberFx.flicker(_light, _light_phase)
		Mode.HEAL:
			# Slow and shallow: a heartbeat under the surface, not a blinker.
			_light.light_energy = _light_base_energy * (1.0 + sin(_light_phase * 1.6) * 0.22)
		Mode.SOUL:
			_light.light_energy = _light_base_energy * (0.4 + 1.2 * _soul_fill())
		Mode.LIGHTNING:
			# Crackles: mostly steady, with a hard flicker now and then.
			_light.light_energy = _light_base_energy * (1.6 if randf() < 0.08 else 0.9)


func _interval() -> float:
	var speed_mult: float = _rank_mult()
	match mode:
		Mode.FIRE: return GameSettings.aura_orb_of_fire_interval / speed_mult
		Mode.HEAL: return GameSettings.aura_healing_orb_interval / speed_mult
		# Not rank-scaled: the souls are the rate limit, and a rank that emptied the orb
		# faster would only make it sit empty sooner.
		Mode.SOUL: return GameSettings.aura_grave_pact_release_interval
		Mode.LIGHTNING: return GameSettings.aura_lightning_orb_interval / speed_mult
		_: return GameSettings.aura_orb_of_frost_interval / speed_mult


## Nearest enemy within `range_units`, or null. Nearest rather than lowest-health: the
## orb is meant to feel like something fighting beside you, and something fighting beside
## you hits what is closest.
func _nearest_enemy(range_units: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = range_units
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## The sound of this orb's shot. Somebody else's orb is background to this player rather
## than a sound of their own doing, so it sits further down still.
func _play_shot_sound(event: StringName) -> void:
	var extra_db: float = 0.0
	if is_instance_valid(_owner) and "is_local" in _owner and not bool(_owner.is_local):
		extra_db = GameSettings.aura_orb_remote_gain_db
	SoundBank.play_at(event, global_position, extra_db)


func _fire_frost() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_frost_range * _rank_mult("area"))
	if target == null:
		return
	_shoot_bolt(target, COLORS[Mode.FROST])
	_play_shot_sound(&"aura_orb_frost")
	var damage: float = GameSettings.aura_orb_of_frost_damage * _rank_mult() * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)
	if target.has_method("apply_frost_slow"):
		target.apply_frost_slow(GameSettings.aura_orb_of_frost_slow * _rank_mult("duration"))


## Orb of Fire throws a ball of fire rather than drawing a beam: a projectile with a tail
## (SpellVisuals.fire_bolt), seen on every screen through NetFx. The hit lands when the ball
## does, not when it leaves - a damage number that pops before the fire arrives reads as the
## orb missing.
func _fire_flame() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_fire_range * _rank_mult("area"))
	if target == null:
		return
	var muzzle: Vector3 = global_position
	var offset: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0) - muzzle
	var travel: float = clampf(offset.length() / GameSettings.aura_orb_of_fire_bolt_speed, 0.08, 0.6)
	NetFx.spell("orb_fire_shot", muzzle, travel, _owner_peer(), offset)
	_play_shot_sound(&"aura_orb_fire")
	var damage: float = GameSettings.aura_orb_of_fire_damage * _rank_mult() * _damage_multiplier()
	var burn_duration: float = GameSettings.aura_orb_of_fire_burn_duration * _rank_mult("duration")
	var burn_dps: float = GameSettings.aura_orb_of_fire_burn_dps * _rank_mult() * _damage_multiplier()
	var owner_node: Node3D = _owner
	get_tree().create_timer(travel).timeout.connect(func() -> void:
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			return
		if target.has_method("take_damage"):
			target.take_damage(damage, owner_node)
		if target.has_method("apply_burn"):
			target.apply_burn(burn_duration, burn_dps, owner_node))


## Lightning Orb: an arc into the nearest enemy that leaps on to the nearest enemy not yet
## struck, a few times, each jump a little weaker. Instant - lightning does not travel - and
## drawn as one chain (SpellVisuals.chain_lightning) on every screen.
func _fire_lightning() -> void:
	var first: Node3D = _nearest_enemy(GameSettings.aura_lightning_orb_range * _rank_mult("area"))
	if first == null:
		return
	var struck: Array[Node3D] = [first]
	var points := PackedVector3Array([global_position, first.global_position + Vector3(0.0, 1.0, 0.0)])
	var jumps: int = GameSettings.aura_lightning_orb_chains + (1 if _owner_rank() >= 3 else 0) + (1 if _owner_rank() >= 5 else 0)
	var reach: float = GameSettings.aura_lightning_orb_chain_range * _rank_mult("area")
	while struck.size() <= jumps:
		var from: Vector3 = struck[-1].global_position
		var next: Node3D = null
		var best: float = reach
		for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or struck.has(enemy):
				continue
			var distance: float = from.distance_to(enemy.global_position)
			if distance < best:
				best = distance
				next = enemy
		if next == null:
			break
		struck.append(next)
		points.append(next.global_position + Vector3(0.0, 1.0, 0.0))
	NetFx.spell("orb_lightning", global_position, 0.0, _owner_peer(), Vector3.ZERO, points)
	_play_shot_sound(&"aura_orb_lightning")
	var damage: float = GameSettings.aura_lightning_orb_damage * _rank_mult() * _damage_multiplier()
	for index: int in range(struck.size()):
		var enemy: Node3D = struck[index]
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage * pow(GameSettings.aura_lightning_orb_chain_falloff, index), _owner)


func _owner_rank() -> int:
	if is_instance_valid(_owner) and _owner.has_method("get_aura_rank"):
		return int(_owner.get_aura_rank(_aura_id()))
	return 1


## The peer whose orb this is, for NetFx: an effect parented to its caster needs to know who
## that is on every screen.
func _owner_peer() -> int:
	if is_instance_valid(_owner) and _owner.has_method("_fx_peer"):
		return int(_owner._fx_peer())
	return 0


## Always the MOST HURT ally in range, which is what makes this read as a healer rather
## than as a regeneration stat. Myrs count: white is the colour built around them.
func _heal_lowest() -> void:
	var best: Node3D = null
	var best_ratio: float = 1.0
	for group: String in ["player", "myrs", "allies"]:
		for ally: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(ally) or not ally is Node3D or not ally.has_method("heal"):
				continue
			var node: Node3D = ally as Node3D
			if global_position.distance_to(node.global_position) > GameSettings.aura_healing_orb_radius * _rank_mult("area"):
				continue
			var ratio: float = HealthReader.ratio(node)
			if ratio >= 0.0 and ratio < best_ratio:
				best_ratio = ratio
				best = node
	# Nobody is hurt: the tick is spent rather than saved, which is what stops the orb
	# banking heals through a quiet stretch and dumping them the instant someone is hit.
	if best == null:
		return
	_shoot_bolt(best, COLORS[Mode.HEAL])
	_play_shot_sound(&"aura_orb_heal")
	# Bound to the player's max HP like every white/green HP number, so the orb scales
	# with green affinity and Giant Growth instead of falling behind them.
	var restored: float = best.heal(GameSettings.player_max_hp * GameSettings.aura_healing_orb_hp_mult * _rank_mult())
	# The orb is the player's, so what it heals is credited to them - a white player who took
	# the Manifestation over the Attunement should see it on the scoreboard.
	if is_instance_valid(_owner) and _owner.has_method("_credit_heal"):
		_owner._credit_heal(best, restored)


## An enemy died near the owner: its soul is drawn into the orb. Called by Player on the
## server, where the deaths are. A wisp streaks from the body to the orb so the player can see
## WHY the orb just brightened - a count that climbs invisibly is the old Grave Pact again.
##
## Capped: the orb holds a handful and lets the rest go. Without a cap one wave-clearing
## Wrath of God would bank enough souls to keep firing for a minute after the fight ended.
func add_soul(from: Vector3) -> void:
	if mode != Mode.SOUL:
		return
	if _souls >= GameSettings.aura_grave_pact_max_souls:
		return
	_souls += 1
	_update_soul_glow()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var start: Vector3 = from + Vector3(0.0, 1.0, 0.0)
	var to_orb: Vector3 = global_position - start
	var length: float = to_orb.length()
	if length > 0.05:
		var streak: Node3D = SpellFx.beam(to_orb / length, length, COLORS[Mode.SOUL], 0.16, 0.3)
		scene.add_child(streak)
		streak.global_position = start


## Held souls, for anything that has to read the orb from outside (tests, the HUD one day).
func soul_count() -> int:
	return _souls


## Throws one held soul at the nearest enemy. Nothing held, or nothing in reach, and the
## tick passes - the souls wait for the next living thing to come close.
func _release_soul() -> void:
	if _souls <= 0:
		return
	var target: Node3D = _nearest_enemy(GameSettings.aura_grave_pact_range * _rank_mult("area"))
	if target == null:
		return
	_souls -= 1
	_update_soul_glow()
	_shoot_bolt(target, COLORS[Mode.SOUL])
	_play_shot_sound(&"aura_grave_pact")
	var damage: float = GameSettings.aura_grave_pact_soul_damage * _rank_mult() * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)


## How full the orb is, 0 to 1.
func _soul_fill() -> float:
	return clampf(float(_souls) / maxf(float(GameSettings.aura_grave_pact_max_souls), 1.0), 0.0, 1.0)


## An empty orb is a dark husk; a full one burns the zombies' green through it.
func _update_soul_glow() -> void:
	if _soul_material == null:
		return
	_soul_material.emission_energy_multiplier = lerpf(0.25, 2.4, _soul_fill())


func _aura_id() -> String:
	match mode:
		Mode.FIRE: return "aura_orb_of_fire"
		Mode.HEAL: return "aura_healing_orb"
		Mode.SOUL: return "aura_grave_pact"
		Mode.LIGHTNING: return "aura_lightning_orb"
		_: return "aura_orb_of_frost"


func _rank_mult(curve: String = "damage") -> float:
	if is_instance_valid(_owner) and _owner.has_method("get_aura_rank_mult"):
		return float(_owner.get_aura_rank_mult(_aura_id(), curve))
	return 1.0


## The shot from the orb to whatever it just acted on (frost, heal, souls - fire throws a
## projectile and lightning arcs, see their own payloads): SpellFx.beam's crossed quads with a
## hot core and tapered ends, drawn premultiplied so it survives a bright sky, and a small
## landing at the far end - a beam that simply stops is only half an event.
func _shoot_bolt(target: Node3D, tint: Color) -> void:
	var muzzle: Vector3 = global_position
	var hit: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	var to_target: Vector3 = hit - muzzle
	var length: float = to_target.length()
	if length < 0.05:
		return

	var scene: Node = get_tree().current_scene
	# Thin and quick: this fires every second or two, and a shot as wide or as long-lived
	# as a spell's beam would leave the player permanently looking at one.
	var shaft: Node3D = SpellFx.beam(to_target / length, length, tint, _beam_width(), 0.18)
	scene.add_child(shaft)
	# Placed at the beam's START, not its middle: SpellFx.beam builds it running out along
	# its own +X from wherever it is put.
	shaft.global_position = muzzle
	_spawn_bolt_impact(scene, hit, tint)


## How wide each mode's shot is drawn. Frost's is the narrowest - it is a splinter of ice -
## and heal's the widest and softest, because it is the one that is not meant to read as a
## weapon hitting something.
func _beam_width() -> float:
	match mode:
		Mode.HEAL: return 0.26
		Mode.SOUL: return 0.24
		_: return 0.17


## The far end of the shot. Deliberately not SpellFx.impact, which builds a shockwave, a
## light and 28 sparks sized for a spell landing - at this fire rate that is both far too
## much to look at and far too much to spawn. This is the same idea at a tenth the weight.
func _spawn_bolt_impact(scene: Node, point: Vector3, tint: Color) -> void:
	var burst := Node3D.new()
	burst.name = "OrbBoltImpact"

	var flash := OmniLight3D.new()
	flash.light_color = tint
	flash.light_energy = 1.4
	flash.omni_range = 1.8
	burst.add_child(flash)

	var motes := GPUParticles3D.new()
	motes.amount = 5
	motes.lifetime = 0.4
	motes.one_shot = true
	motes.explosiveness = 1.0
	# Each mode scatters its own shape: ice splinters, fire sparks, and soft rays for the
	# heal and the souls - the same slot-per-colour split the rest of the effect layer uses.
	motes.draw_pass_1 = SpellFx.premul_particle_mesh(0.12, _impact_slot())
	var scatter := ParticleProcessMaterial.new()
	scatter.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	scatter.emission_sphere_radius = 0.1
	scatter.direction = Vector3.UP
	scatter.spread = 180.0
	scatter.gravity = Vector3(0.0, -1.5, 0.0) if mode != Mode.HEAL else Vector3(0.0, 0.8, 0.0)
	scatter.initial_velocity_min = 1.0
	scatter.initial_velocity_max = 2.2
	scatter.scale_min = 0.3
	scatter.scale_max = 0.7
	scatter.color_ramp = SpellFx._premul_ramp(tint)
	motes.process_material = scatter
	burst.add_child(motes)

	scene.add_child(burst)
	burst.global_position = point
	var tween: Tween = burst.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.14)
	# Outlives the flash by the particles' own lifetime, or the scatter is cut off mid-air.
	tween.tween_interval(0.45)
	tween.tween_callback(burst.queue_free)


func _impact_slot() -> String:
	match mode:
		Mode.HEAL, Mode.SOUL: return "mote"
		_: return "shard"


## The orb is the player's, so it scales with everything the player's own spells scale
## with - red affinity, the team's Furnace of Rath, run modifiers. An aura that
## ignored the build it was bought into would fall off exactly when it was bought.
func _damage_multiplier() -> float:
	if is_instance_valid(_owner) and _owner.has_method("get_spell_damage_multiplier"):
		return float(_owner.get_spell_damage_multiplier())
	return 1.0
