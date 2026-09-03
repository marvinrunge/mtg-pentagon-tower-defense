extends Node3D
class_name OrbitingOrb
## The orb that circles a player for three of the five capstone Manifestations.
##
## Orb of Frost (blue), Orb of Fire (red) and Healing Orb (white) are one implementation
## with three payloads, because the only thing that differs between them is what happens
## on the tick - everything else, the orbit, the bob, the light, the target search, is
## shared. Writing three of these was the alternative, and three copies of an orbit is
## how the third one ends up subtly out of step with the other two.
##
## It lives as a child of the player and follows them by being parented to them, so
## nothing here has to chase a moving anchor.

enum Mode { FROST, FIRE, HEAL }

var mode: int = Mode.FROST

var _angle: float = 0.0
var _tick_timer: float = 0.0
var _owner: Node3D
var _mesh: MeshInstance3D
var _light: OmniLight3D

const COLORS: Dictionary = {
	Mode.FROST: Color(0.45, 0.8, 1.0),
	Mode.FIRE: Color(1.0, 0.45, 0.12),
	Mode.HEAL: Color(1.0, 0.95, 0.65),
}


static func create(p_mode: int, p_owner: Node3D) -> OrbitingOrb:
	var orb := OrbitingOrb.new()
	orb.mode = p_mode
	orb._owner = p_owner
	orb.name = "CapstoneOrb"
	return orb


func _ready() -> void:
	var tint: Color = COLORS[mode]

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 1.8
	_light.omni_range = 4.0
	add_child(_light)

	# Staggered so a player who somehow had two would not see them fire in lockstep,
	# and so the first tick does not land on the same frame the capstone is bought.
	_tick_timer = _interval() * 0.5


func _process(delta: float) -> void:
	if not is_instance_valid(_owner):
		queue_free()
		return

	_angle += GameSettings.aura_orb_speed * delta
	var radius: float = GameSettings.aura_orb_radius
	# Local to the player, so the orbit does not have to be recomputed from the player's
	# world position every frame - and so it keeps circling correctly while they move.
	position = Vector3(
		cos(_angle) * radius,
		GameSettings.aura_orb_height + sin(_angle * 2.0) * 0.18,
		sin(_angle) * radius
	)

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


func _interval() -> float:
	match mode:
		Mode.FIRE: return GameSettings.aura_orb_of_fire_interval
		Mode.HEAL: return GameSettings.aura_healing_orb_interval
		_: return GameSettings.aura_orb_of_frost_interval


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
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_frost_range)
	if target == null:
		return
	_shoot_bolt(target, COLORS[Mode.FROST])
	var damage: float = GameSettings.aura_orb_of_frost_damage * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)
	if target.has_method("apply_frost_slow"):
		target.apply_frost_slow(GameSettings.aura_orb_of_frost_slow)


func _fire_flame() -> void:
	var target: Node3D = _nearest_enemy(GameSettings.aura_orb_of_fire_range)
	if target == null:
		return
	_shoot_bolt(target, COLORS[Mode.FIRE])
	var damage: float = GameSettings.aura_orb_of_fire_damage * _damage_multiplier()
	if target.has_method("take_damage"):
		target.take_damage(damage, _owner)
	if target.has_method("apply_burn"):
		target.apply_burn(
			GameSettings.aura_orb_of_fire_burn_duration,
			GameSettings.aura_orb_of_fire_burn_dps * _damage_multiplier(),
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
			if global_position.distance_to(node.global_position) > GameSettings.aura_healing_orb_radius:
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
	best.heal(GameSettings.aura_healing_orb_amount)


## A short-lived streak from the orb to whatever it just acted on. Without it the orb is
## a decoration that occasionally coincides with a damage number somewhere else.
func _shoot_bolt(target: Node3D, tint: Color) -> void:
	var beam := MeshInstance3D.new()
	var to_target: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0) - global_position
	var length: float = to_target.length()
	if length < 0.05:
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = length
	beam.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.8)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	# Parented to the scene rather than to the orb: the orb keeps orbiting, and a beam
	# that travelled with it would sweep across the field like a searchlight.
	get_tree().current_scene.add_child(beam)
	beam.global_position = global_position + to_target * 0.5
	beam.look_at(target.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tween: Tween = beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.18)
	tween.tween_callback(beam.queue_free)


## The orb is the player's, so it scales with everything the player's own spells scale
## with - red affinity, the team's Furnace of Rath, run modifiers. A capstone that
## ignored the build it was bought into would fall off exactly when it was bought.
func _damage_multiplier() -> float:
	if is_instance_valid(_owner) and _owner.has_method("get_spell_damage_multiplier"):
		return float(_owner.get_spell_damage_multiplier())
	return 1.0
