extends Node3D
class_name OrbitingOrb
## The orb that circles a player for three of the five aura Manifestations.
##
## Winter Orb (blue), Orb of Fire (red) and Healing Orb (white) are one implementation
## with three payloads, because the only thing that differs between them is what happens
## on the tick - everything else, the orbit, the bob, the light, the target search, is
## shared. Writing three of these was the alternative, and three copies of an orbit is
## how the third one ends up subtly out of step with the other two.
##
## It lives as a child of the player and follows them by being parented to them, so
## nothing here has to chase a moving anchor.

enum Mode { FROST, FIRE, HEAL }

var mode: int = Mode.FROST

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _owner: Node3D
var _mesh: MeshInstance3D
var _light: OmniLight3D
## Fire's light flickers and heal's breathes, both off this. Frost's is steady.
var _light_phase: float = 0.0
var _light_base_energy: float = 1.8

const COLORS: Dictionary = {
	Mode.FROST: Color(0.45, 0.8, 1.0),
	Mode.FIRE: Color(1.0, 0.45, 0.12),
	Mode.HEAL: Color(1.0, 0.95, 0.65),
}

## A separate orbit per mode, because all three used to share one.
##
## `_angle` started at 0.0 for every orb and advanced at one shared speed, at one shared
## radius and height - so a player holding the blue, red and white Manifestations at once had
## three orbs occupying the exact same point in space for the whole run. Not merely crossing
## occasionally: coincident, permanently, with only the frost crown visible because it is the
## largest. The staggered `_tick_timer` in _ready hints that this was known about for the
## FIRING and missed for the orbit.
##
## Each orb now gets its own lane, and the numbers are picked so the three can never touch
## rather than merely usually missing: separated in radius AND height, so no combination of
## speeds can bring two together, then given different speeds and phases on top so they read
## as three independent things rather than a rotating rack. tools/tests/orb_orbits.gd
## brute-forces the minimum separation over a long run and fails if it closes.
##
## radius and speed are MULTIPLIERS on the GameSettings values, and height an offset in
## metres, so the global knobs still move all three together.
const ORBIT_PLAN: Dictionary = {
	# Innermost, lowest, fastest: the one that reads as a familiar on the player's shoulder.
	Mode.FROST: {"radius": 0.70, "height": -0.65, "speed": 1.05, "phase": 0.0, "tilt": 0.0, "bob": 0.05, "bob_rate": 2.0},
	# Middle lane, tilted, slower - the tilt is what stops three concentric rings reading as
	# one mechanism with three beads on it. Kept SMALL: a tilt of 0.09 was the first thing
	# tried and orb_orbits.gd measured it closing frost-to-fire to 0.68m, because a tilted
	# ring trades vertical separation for the look. 0.04 still reads as a canted orbit.
	Mode.FIRE: {"radius": 1.05, "height": 0.10, "speed": 0.71, "phase": TAU / 3.0, "tilt": 0.04, "bob": 0.05, "bob_rate": 2.7},
	# Outermost, highest, slowest, tilted the other way: it hangs over the player like
	# something watching over them, which is the only one of the three that is not a weapon.
	Mode.HEAL: {"radius": 1.40, "height": 0.90, "speed": 0.49, "phase": TAU * 2.0 / 3.0, "tilt": -0.04, "bob": 0.05, "bob_rate": 1.5},
}


## Where `mode`'s orb sits, local to the player, `time` seconds in.
##
## Static and pure so the separation between the three lanes can be measured directly by a
## test - no scene, no player, no frames. Reading it back off three live orbs would mean
## sampling whatever positions one particular run happened to visit, which for orbits with
## incommensurable periods is exactly the wrong way to look for the closest approach.
static func orbit_position(orb_mode: int, time: float) -> Vector3:
	var plan: Dictionary = ORBIT_PLAN[orb_mode]
	var radius: float = GameSettings.aura_orb_radius * float(plan["radius"])
	var angle: float = time * GameSettings.aura_orb_speed * float(plan["speed"]) + float(plan["phase"])
	var height: float = GameSettings.aura_orb_height + float(plan["height"])
	height += sin(time * float(plan["bob_rate"])) * float(plan["bob"])
	# The tilt is applied as a rise and fall around the ring rather than by rotating the whole
	# orbit basis: same look, and it keeps this function one expression that a test can reason
	# about instead of a transform chain.
	height += sin(angle) * radius * float(plan["tilt"])
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)


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
	sphere.radius = 0.24
	sphere.height = 0.48
	_mesh.mesh = sphere
	var mat: StandardMaterial3D = _orb_material(tint)
	_mesh.material_override = mat
	add_child(_mesh)
	match mode:
		Mode.FROST: _build_frost_crown()
		Mode.FIRE: _build_fire_body()
		Mode.HEAL: _build_heal_body()

	_light = OmniLight3D.new()
	_light.light_color = tint
	# Fire's own light is warmer than its bolt colour - a fire that lights the ground the
	# same orange it is drawn in reads as a flat sticker rather than as something burning.
	if mode == Mode.FIRE:
		_light.light_color = Color(1.0, 0.62, 0.28)
		_light_base_energy = 2.4
	elif mode == Mode.HEAL:
		_light_base_energy = 1.5
	_light.light_energy = _light_base_energy
	_light.omni_range = 4.0
	add_child(_light)

	# Staggered so a player who somehow had two would not see them fire in lockstep,
	# and so the first tick does not land on the same frame the aura is bought.
	_tick_timer = _interval() * 0.5


func _orb_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if mode == Mode.FROST:
		mat.albedo_color = Color(0.78, 0.94, 1.0, 0.92)
		mat.metallic = 0.82
		mat.roughness = 0.18
		mat.emission_enabled = true
		mat.emission = Color(0.62, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.8
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.rim_enabled = true
		mat.rim = 0.75
		mat.rim_tint = 0.25
		return mat
	if mode == Mode.FIRE:
		# Shaded, not UNSHADED. That one flag is most of why this orb read as placeholder next
		# to the frost one: an unshaded emissive sphere has no light falling across it and no
		# rim, so at any distance it is a flat orange circle rather than a ball. Frost was the
		# only mode with a real material, and it was the only one that looked like an object.
		mat.albedo_color = Color(0.55, 0.13, 0.02)
		mat.metallic = 0.15
		mat.roughness = 0.55
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.42, 0.08)
		mat.emission_energy_multiplier = 2.4
		mat.rim_enabled = true
		mat.rim = 0.9
		mat.rim_tint = 0.15
		return mat
	# HEAL. Pale and soft rather than hot: low emission with a strong rim, so the light reads
	# as coming off the surface instead of out of it.
	mat.albedo_color = Color(1.0, 0.96, 0.82)
	mat.metallic = 0.1
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.68)
	mat.emission_energy_multiplier = 1.5
	mat.rim_enabled = true
	mat.rim = 0.95
	mat.rim_tint = 0.4
	return mat


func _build_frost_crown() -> void:
	var crown := MeshInstance3D.new()
	crown.name = "FrostCrown"
	var mesh := SphereMesh.new()
	mesh.radius = 0.31
	mesh.height = 0.62
	crown.mesh = mesh
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.56, 0.86, 1.0, 0.22)
	shell.emission_enabled = true
	shell.emission = Color(0.5, 0.86, 1.0)
	shell.emission_energy_multiplier = 0.45
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.metallic = 0.35
	shell.roughness = 0.08
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = shell
	add_child(crown)

	var shards := GPUParticles3D.new()
	shards.name = "FrostOrbitShards"
	shards.amount = 18
	shards.lifetime = 1.8
	shards.preprocess = 1.8
	shards.draw_pass_1 = SpellFx.premul_particle_mesh(0.22, "shard")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.34
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.12
	process.scale_min = 0.05
	process.scale_max = 0.16
	process.color_ramp = SpellFx._premul_ramp(Color(0.65, 0.92, 1.0))
	shards.process_material = process
	add_child(shards)


## Orb of Fire. The frost orb got a shell, orbiting shards and a tinted metallic core; this
## one was an unshaded orange ball with a light in it, which is why it read as placeholder
## next to the other. Same three-part construction, in fire's own language: a dark molten
## shell over a hot core, a flame guttering off the top, and embers shedding off the outside.
##
## Premultiplied throughout (SpellFx rather than EmberFx's additive builders) - see
## docs/SPELL_VFX_PLAN.md. Additive fire is invisible against a bright sky, which is exactly
## where an orb orbiting head-height sits.
func _build_fire_body() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "FireShell"
	var mesh := SphereMesh.new()
	mesh.radius = 0.30
	mesh.height = 0.60
	shell.mesh = mesh
	var crust := StandardMaterial3D.new()
	# Dark and rough, so the bright core shows THROUGH it in patches rather than being
	# wrapped in more of the same orange.
	crust.albedo_color = Color(0.32, 0.09, 0.03, 0.42)
	crust.emission_enabled = true
	crust.emission = Color(1.0, 0.35, 0.06)
	crust.emission_energy_multiplier = 1.1
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
	flame.amount = 28
	flame.lifetime = 0.85
	flame.preprocess = 0.85
	flame.local_coords = true
	flame.draw_pass_1 = SpellFx.premul_particle_mesh(0.52, "smoke")
	var rising := ParticleProcessMaterial.new()
	rising.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rising.emission_sphere_radius = 0.16
	rising.direction = Vector3.UP
	rising.spread = 24.0
	# Fire falls UP, the same trick EmberFx.build_flame uses: positive gravity makes the
	# tongue accelerate away instead of arcing back down like debris.
	rising.gravity = Vector3(0.0, 0.9, 0.0)
	rising.initial_velocity_min = 0.35
	rising.initial_velocity_max = 0.95
	rising.angle_min = -180.0
	rising.angle_max = 180.0
	rising.scale_min = 0.4
	rising.scale_max = 0.9
	rising.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.52, 0.14))
	flame.process_material = rising
	add_child(flame)

	var embers := GPUParticles3D.new()
	embers.name = "OrbEmbers"
	embers.amount = 14
	embers.lifetime = 1.1
	embers.preprocess = 1.1
	# World space, unlike the flame: embers are shed and LEFT BEHIND, so a moving orb should
	# trail them rather than drag them along in a clump.
	embers.local_coords = false
	embers.draw_pass_1 = SpellFx.premul_particle_mesh(0.09, "spark")
	var shed := ParticleProcessMaterial.new()
	shed.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	shed.emission_sphere_radius = 0.26
	shed.direction = Vector3.UP
	shed.spread = 180.0
	shed.gravity = Vector3(0.0, -0.35, 0.0)
	shed.initial_velocity_min = 0.1
	shed.initial_velocity_max = 0.45
	shed.scale_min = 0.05
	shed.scale_max = 0.14
	shed.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.72, 0.3))
	embers.process_material = shed
	add_child(embers)


## Healing Orb. The one of the three that is not a weapon, so it is built to read as calm
## where fire reads as violent: a soft halo instead of a crust, motes drifting UP out of it
## instead of shedding off it, and a ring lying flat around it that nothing else has.
func _build_heal_body() -> void:
	var halo := MeshInstance3D.new()
	halo.name = "HealHalo"
	var mesh := SphereMesh.new()
	mesh.radius = 0.34
	mesh.height = 0.68
	halo.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.97, 0.82, 0.16)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.93, 0.7)
	glow.emission_energy_multiplier = 0.6
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.roughness = 0.25
	glow.rim_enabled = true
	glow.rim = 0.85
	glow.rim_tint = 0.3
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = glow
	add_child(halo)

	# A flat ring around the orb's equator. The one silhouette cue the other two do not have,
	# which is what lets a glance tell the white orb from the blue one at distance, where both
	# are pale and the colours have washed together.
	var ring := MeshInstance3D.new()
	ring.name = "HealRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.40
	torus.outer_radius = 0.46
	ring.mesh = torus
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(1.0, 0.95, 0.75, 0.5)
	band.emission_enabled = true
	band.emission = Color(1.0, 0.9, 0.62)
	band.emission_energy_multiplier = 1.6
	band.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = band
	ring.rotation_degrees = Vector3(14.0, 0.0, 8.0)
	add_child(ring)

	var motes := GPUParticles3D.new()
	motes.name = "HealMotes"
	motes.amount = 16
	motes.lifetime = 1.6
	motes.preprocess = 1.6
	motes.local_coords = true
	# "mote" rather than "spark": rays instead of a round speck, so these read as something
	# rising rather than as more embers in a different colour.
	motes.draw_pass_1 = SpellFx.premul_particle_mesh(0.15, "mote")
	var drift := ParticleProcessMaterial.new()
	drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	drift.emission_sphere_radius = 0.3
	drift.direction = Vector3.UP
	drift.spread = 30.0
	drift.gravity = Vector3(0.0, 0.25, 0.0)
	drift.initial_velocity_min = 0.12
	drift.initial_velocity_max = 0.34
	drift.angle_min = -180.0
	drift.angle_max = 180.0
	drift.scale_min = 0.35
	drift.scale_max = 0.85
	drift.color_ramp = SpellFx._premul_ramp(Color(1.0, 0.95, 0.72))
	motes.process_material = drift
	add_child(motes)


func _process(delta: float) -> void:
	if not is_instance_valid(_owner):
		queue_free()
		return

	_elapsed += delta
	# Local to the player, so the orbit does not have to be recomputed from the player's
	# world position every frame - and so it keeps circling correctly while they move.
	position = orbit_position(mode, _elapsed)
	_animate_light(delta)

	# The payload is a game effect, so it is the server's, exactly like a spell. The
	# orbit above is cosmetic and runs everywhere, which is what keeps the orb visible on
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


## Fire gutters, heal breathes, frost holds steady. One line each, and it is most of what
## separates the three at a glance in a dark scene - a static point light reads as a lamp
## bolted to the player whatever colour it is.
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


func _interval() -> float:
	var speed_mult: float = _rank_mult()
	match mode:
		Mode.FIRE: return GameSettings.aura_orb_of_fire_interval / speed_mult
		Mode.HEAL: return GameSettings.aura_healing_orb_interval / speed_mult
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


func _fire_frost() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_frost_range * _rank_mult("area"))
	if target == null:
		return
	_shoot_bolt(target, COLORS[Mode.FROST])
	SoundBank.play_at(&"aura_orb_frost", global_position)
	var damage: float = GameSettings.aura_orb_of_frost_damage * _rank_mult() * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)
	if target.has_method("apply_frost_slow"):
		target.apply_frost_slow(GameSettings.aura_orb_of_frost_slow * _rank_mult("duration"))


func _fire_flame() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_fire_range * _rank_mult("area"))
	if target == null:
		return
	_shoot_bolt(target, COLORS[Mode.FIRE])
	SoundBank.play_at(&"aura_orb_fire", global_position)
	var damage: float = GameSettings.aura_orb_of_fire_damage * _rank_mult() * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)
	if target.has_method("apply_burn"):
		target.apply_burn(
			GameSettings.aura_orb_of_fire_burn_duration * _rank_mult("duration"),
			GameSettings.aura_orb_of_fire_burn_dps * _rank_mult() * _damage_multiplier(),
			_owner
		)


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
	SoundBank.play_at(&"aura_orb_heal", global_position)
	# Bound to the player's max HP like every white/green HP number, so the orb scales
	# with green affinity and Giant Growth instead of falling behind them.
	var restored: float = best.heal(GameSettings.player_max_hp * GameSettings.aura_healing_orb_hp_mult * _rank_mult())
	# The orb is the player's, so what it heals is credited to them - a white player who took
	# the Manifestation over the Attunement should see it on the scoreboard.
	if is_instance_valid(_owner) and _owner.has_method("_credit_heal"):
		_owner._credit_heal(best, restored)


func _aura_id() -> String:
	match mode:
		Mode.FIRE: return "aura_orb_of_fire"
		Mode.HEAL: return "aura_healing_orb"
		_: return "aura_orb_of_frost"


func _rank_mult(curve: String = "damage") -> float:
	if is_instance_valid(_owner) and _owner.has_method("get_aura_rank_mult"):
		return float(_owner.get_aura_rank_mult(_aura_id(), curve))
	return 1.0


## The shot from the orb to whatever it just acted on.
##
## Was a plain emissive CYLINDER, which energy_beam.gdshader's own header names as the thing
## it exists to replace: "a visible silhouette and a hard cap at each end - the two things
## that made every beam in the game read as a coloured pipe". Every other beam in the game
## had already moved to the shader; the orbs were the last caller still drawing pipes, so
## they were the last effects that looked untouched.
##
## SpellFx.beam gives crossed quads with a hot core, a softer sheath and both ends tapered,
## drawn premultiplied so it survives a bright sky. On top of that the shot now LANDS: a
## flash and a scatter of points at the far end, because a beam that simply stops is only
## half an event, and the orbs fire often enough that the arrival is what the eye follows.
func _shoot_bolt(target: Node3D, tint: Color) -> void:
	var muzzle: Vector3 = global_position
	var hit: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0)
	var to_target: Vector3 = hit - muzzle
	var length: float = to_target.length()
	if length < 0.05:
		return

	var scene: Node = get_tree().current_scene
	# Thin and quick: this fires every 1.4-2.0 seconds, and a shot as wide or as long-lived
	# as a spell's beam would leave the player permanently looking at one.
	var shaft: Node3D = SpellFx.beam(to_target / length, length, tint, _beam_width(), 0.22)
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
		Mode.FIRE: return 0.34
		Mode.HEAL: return 0.42
		_: return 0.26


## The far end of the shot. Deliberately not SpellFx.impact, which builds a shockwave, a
## light and 28 sparks sized for a spell landing - at this fire rate that is both far too
## much to look at and far too much to spawn. This is the same idea at a tenth the weight.
func _spawn_bolt_impact(scene: Node, point: Vector3, tint: Color) -> void:
	var burst := Node3D.new()
	burst.name = "OrbBoltImpact"

	var flash := OmniLight3D.new()
	flash.light_color = tint
	flash.light_energy = 3.2
	flash.omni_range = 2.4
	burst.add_child(flash)

	var motes := GPUParticles3D.new()
	motes.amount = 8
	motes.lifetime = 0.4
	motes.one_shot = true
	motes.explosiveness = 1.0
	# Each mode scatters its own shape: ice splinters, fire sparks, and soft rays for the
	# heal - the same slot-per-colour split the rest of the effect layer already uses.
	motes.draw_pass_1 = SpellFx.premul_particle_mesh(0.16, _impact_slot())
	var scatter := ParticleProcessMaterial.new()
	scatter.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	scatter.emission_sphere_radius = 0.12
	scatter.direction = Vector3.UP
	scatter.spread = 180.0
	scatter.gravity = Vector3(0.0, -1.5, 0.0) if mode != Mode.HEAL else Vector3(0.0, 0.8, 0.0)
	scatter.initial_velocity_min = 1.2
	scatter.initial_velocity_max = 2.8
	scatter.scale_min = 0.3
	scatter.scale_max = 0.8
	scatter.color_ramp = SpellFx._premul_ramp(tint)
	motes.process_material = scatter
	burst.add_child(motes)

	scene.add_child(burst)
	burst.global_position = point
	var tween: Tween = burst.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.16)
	# Outlives the flash by the particles' own lifetime, or the scatter is cut off mid-air.
	tween.tween_interval(0.45)
	tween.tween_callback(burst.queue_free)


func _impact_slot() -> String:
	match mode:
		Mode.FIRE: return "spark"
		Mode.HEAL: return "mote"
		_: return "shard"


## The orb is the player's, so it scales with everything the player's own spells scale
## with - red affinity, the team's Furnace of Rath, run modifiers. A aura that
## ignored the build it was bought into would fall off exactly when it was bought.
func _damage_multiplier() -> float:
	if is_instance_valid(_owner) and _owner.has_method("get_spell_damage_multiplier"):
		return float(_owner.get_spell_damage_multiplier())
	return 1.0
