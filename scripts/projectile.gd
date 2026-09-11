extends Area3D
class_name Projectile

var base_speed: float
var base_damage: float
var base_lifetime: float

var speed: float
var damage: float
var lifetime: float

var direction: Vector3 = Vector3.FORWARD
var active: bool = false
var life_timer: float = 0.0
var is_enemy: bool = false
var proj_type: int = 0
var aoe_radius: float = 0.0
var caster_ref: WeakRef
var effect_multiplier: float = 1.0
var visual_kind: String = "magic"

@onready var visual: CSGSphere3D = $Visual
var projectile_material: StandardMaterial3D
var _arrow_visual: MeshInstance3D
var _stone_visual: MeshInstance3D
var _arrow_material: StandardMaterial3D
var _stone_material: StandardMaterial3D
## Built once per pooled projectile and retinted per shot, rather than per spell:
## these live and die with the pool entry, not with the bolt.
var _trail: GPUParticles3D
var _glow: OmniLight3D

func _ready() -> void:
	base_speed = GameSettings.projectile_base_speed
	base_damage = GameSettings.projectile_base_damage
	base_lifetime = GameSettings.projectile_base_lifetime
	speed = base_speed
	damage = base_damage
	lifetime = base_lifetime
	projectile_material = visual.material.duplicate() as StandardMaterial3D
	visual.material = projectile_material
	_build_physical_visuals()
	_trail = EmberFx.build_trail(28)
	_trail.emitting = false
	add_child(_trail)
	_glow = OmniLight3D.new()
	_glow.omni_range = 4.5
	_glow.light_energy = 0.0
	add_child(_glow)
	body_entered.connect(_on_body_entered)

func activate(start_pos: Vector3, dir: Vector3, type: int, _is_enemy: bool = false, multiplier: float = 1.0, damage_override: float = -1.0, p_aoe_radius: float = 0.0, p_caster: Node3D = null, p_visual_kind: String = "magic", p_tint: Color = Color(0.8, 0.2, 0.8)) -> void:
	global_position = start_pos
	direction = dir
	if direction.length_squared() > 0.001:
		look_at(global_position + direction.normalized(), Vector3.UP)
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	proj_type = type
	is_enemy = _is_enemy
	visual_kind = p_visual_kind
	collision_mask = 19 if is_enemy else 22
	aoe_radius = p_aoe_radius
	caster_ref = weakref(p_caster) if is_instance_valid(p_caster) else null
	effect_multiplier = multiplier
	
	var mat: StandardMaterial3D = projectile_material
	
	if type == 0:
		# Normal (Blue-ish)
		speed = base_speed
		damage = base_damage
		mat.albedo_color = Color(0.3, 0.8, 1.0)
		mat.emission = Color(0.2, 0.6, 1.0)
	elif type == 1:
		# Shock (Red, fast, high damage)
		speed = base_speed * GameSettings.projectile_shock_speed_mult
		damage = GameSettings.spell_red_shock_damage * multiplier
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission = Color(1.0, 0.1, 0.1)
	elif type == 2:
		# Unsummon (Blue wave)
		speed = base_speed * GameSettings.projectile_unsummon_speed_mult
		damage = GameSettings.spell_blue_unsummon_damage * multiplier
		mat.albedo_color = Color(0.1, 0.3, 1.0)
		mat.emission = Color(0.1, 0.3, 1.0)
	elif type == 3:
		# Enemy shot. Mages tint the magic by mana colour; ranged units use physical meshes.
		speed = base_speed * GameSettings.projectile_enemy_speed_mult
		damage = base_damage * GameSettings.projectile_enemy_damage_mult * GameSettings.get_player_scaling_factor(get_tree())
		mat.albedo_color = p_tint
		mat.emission = p_tint
	elif type == 4:
		# Fireball (Red Explosive)
		speed = base_speed * 0.9
		damage = GameSettings.spell_red_fireball_base_damage * multiplier
		mat.albedo_color = Color(1.0, 0.4, 0.0)
		mat.emission = Color(1.0, 0.3, 0.0)
	elif type == 5:
		# Drain Life (Black Vampiric)
		speed = base_speed * 1.1
		damage = GameSettings.spell_black_drain_life_damage * multiplier
		mat.albedo_color = Color(0.3, 0.0, 0.4)
		mat.emission = Color(0.4, 0.0, 0.5)
	elif type == 6:
		# Swords to Plowshares (White Holy Lance)
		speed = base_speed * 1.3
		damage = 0.0 # Handled in impact
		mat.albedo_color = Color(1.0, 1.0, 0.8)
		mat.emission = Color(1.0, 1.0, 0.6)
	elif type == 7:
		# Path to Exile Ray (White Execute Beam)
		speed = base_speed * 1.4
		damage = 0.0
		mat.albedo_color = Color(0.9, 0.9, 1.0)
		mat.emission = Color(0.9, 0.9, 1.0)
		
	if damage_override >= 0.0:
		damage = damage_override

	_apply_visual_mode(mat.emission)

	# Every bolt carries its own light and tail, tinted to match itself; the fireball
	# just gets much more of both, because it is the one meant to look dangerous while
	# it is still in the air.
	_glow.light_color = mat.emission
	_glow.light_energy = _glow_energy_for_visual(type)
	_glow.omni_range = 6.5 if type == 4 else 3.5
	# Tinting the RAMP rather than the mesh: the texture is white, and the ramp is
	# what actually colours each particle. Only the fireball keeps the full fire
	# gradient - everything else is a bolt of its own colour, fading out.
	var trail_process: ParticleProcessMaterial = _trail.process_material
	if type != 4:
		var gradient := Gradient.new()
		gradient.set_offset(0, 0.0)
		gradient.set_color(0, Color(mat.emission, 1.0))
		gradient.set_offset(1, 1.0)
		gradient.set_color(1, Color(mat.emission.darkened(0.5), 0.0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		trail_process.color_ramp = ramp
	_trail.amount = _trail_amount_for_visual(type)
	_trail.restart()
	_trail.emitting = _trail.amount > 0

	life_timer = base_lifetime


func _build_physical_visuals() -> void:
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.albedo_color = Color(0.42, 0.30, 0.18)
	_arrow_material.roughness = 0.75
	_arrow_visual = MeshInstance3D.new()
	_arrow_visual.name = "ArrowVisual"
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.035
	arrow_mesh.bottom_radius = 0.035
	arrow_mesh.height = 0.95
	_arrow_visual.mesh = arrow_mesh
	_arrow_visual.material_override = _arrow_material
	_arrow_visual.rotation.x = PI * 0.5
	_arrow_visual.hide()
	add_child(_arrow_visual)

	_stone_material = StandardMaterial3D.new()
	_stone_material.albedo_color = Color(0.34, 0.32, 0.28)
	_stone_material.roughness = 0.95
	_stone_visual = MeshInstance3D.new()
	_stone_visual.name = "StoneVisual"
	var stone_mesh := SphereMesh.new()
	stone_mesh.radius = 0.18
	stone_mesh.height = 0.34
	_stone_visual.mesh = stone_mesh
	_stone_visual.material_override = _stone_material
	_stone_visual.hide()
	add_child(_stone_visual)


func _apply_visual_mode(tint: Color) -> void:
	visual.show()
	_arrow_visual.hide()
	_stone_visual.hide()
	if visual_kind == "arrow":
		visual.hide()
		_arrow_visual.show()
	elif visual_kind == "stone":
		visual.hide()
		_stone_visual.show()
	else:
		visual.show()
		projectile_material.albedo_color = tint
		projectile_material.emission = tint


func _glow_energy_for_visual(type: int) -> float:
	if visual_kind == "arrow" or visual_kind == "stone":
		return 0.0
	return 3.2 if type == 4 else 1.4


func _trail_amount_for_visual(type: int) -> int:
	if visual_kind == "arrow" or visual_kind == "stone":
		return 0
	return 28 if type == 4 else 14

## Only the enemy shots have recordings of their own; a spell's own effect is
## already what the player hears, and firing an arrow sound off a fireball would be
## worse than the silence.
func _play_impact_sound() -> void:
	if is_enemy:
		SoundBank.play_at(&"arrow_hit", global_position)


func deactivate() -> void:
	# Only stopped, never hidden with the body: the tail still in the air belongs to
	# where the bolt WAS, and clearing it outright snips the trail off mid-flight.
	if _trail != null:
		_trail.emitting = false
	if _glow != null:
		_glow.light_energy = 0.0
	active = false
	visible = false
	caster_ref = null
	# deactivate() runs from _on_body_entered (a physics callback); disabling collision
	# synchronously there is unsafe, so defer the process_mode change - but a BLIND
	# deferred set is itself a race: if ProjectilePool.get_projectile() reuses this
	# same slot and calls activate() later in this same physics frame (routine once
	# several casters fire in one tick), that reactivation runs synchronously and
	# this deferred call would still land afterward, disabling the reactivated
	# projectile and freezing it in place forever with active=true, visible=true.
	# Re-checking `active` at the deferred call site closes that: it only disables
	# if nothing reclaimed this slot in the meantime.
	call_deferred("_finish_deactivate")

func _finish_deactivate() -> void:
	if not active:
		process_mode = Node.PROCESS_MODE_DISABLED

func _get_caster() -> Node3D:
	if caster_ref == null:
		return null
	return caster_ref.get_ref() as Node3D

func _physics_process(delta: float) -> void:
	if not active:
		return
		
	global_position += direction * speed * delta
	
	life_timer -= delta
	if life_timer <= 0:
		deactivate()

func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
	# Only the server's projectiles deal damage. A client's own bolt is spawned locally
	# for the shooter's benefit; the authoritative one was fired by the server when the
	# cast was requested (see Player.execute_spell).
	if not Net.is_server():
		# The LOOK of the detonation still belongs here. A client's fireball reaching an
		# enemy and winking out without a fireball is the same nothing the whole exercise
		# is meant to remove - the damage is the server's, the explosion is everybody's.
		if proj_type == 4:
			_fireball_blast_visuals()
		_play_impact_sound()
		deactivate()
		return
		
	if is_enemy:
		# Enemy projectile hits player, myrs, crystal
		if body.is_in_group("enemies"):
			return # Ignore other enemies
		
		if body.has_method("take_damage"):
			body.take_damage(damage, _get_caster(), false)
		elif body.is_in_group("crystal_hitbox"):
			SignalBus.crystal_damaged.emit(damage)
		_play_impact_sound()
		deactivate()
		return

	# Player projectile logic
	if body.is_in_group("player"):
		return
		
	if proj_type == 2:
		# Unsummon
		if body.has_method("take_damage"):
			body.take_damage(damage, _get_caster())
		if body.has_method("unsummon"):
			body.unsummon(direction * GameSettings.spell_blue_unsummon_knockback)
	elif proj_type == 4:
		# Fireball AoE
		_trigger_fireball_aoe()
	elif proj_type == 5:
		# Drain Life
		if body.has_method("take_damage"):
			var current_caster: Node3D = _get_caster()
			body.take_damage(damage, current_caster)
			if current_caster and current_caster.has_method("heal"):
				var drained: float = current_caster.heal(damage * GameSettings.spell_black_drain_life_lifesteal)
				if current_caster.has_method("_credit_heal"):
					current_caster._credit_heal(current_caster, drained)
	elif proj_type == 6:
		# Swords to Plowshares (% Max HP Holy Exile or Ally Heal)
		if body.is_in_group("enemies"):
			if "health" in body and body.has_method("take_damage"):
				var max_h = body.enemy_data.health if ("enemy_data" in body and body.enemy_data) else 100.0
				var holy_dmg = minf(
					max_h * GameSettings.spell_white_swords_exile_pct * effect_multiplier,
					GameSettings.spell_white_swords_damage_cap
				)
				body.take_damage(holy_dmg, _get_caster())
		elif body.has_method("heal"):
			var given: float = body.heal(GameSettings.spell_white_swords_ally_heal)
			var healer: Node3D = _get_caster()
			if is_instance_valid(healer) and healer.has_method("_credit_heal"):
				healer._credit_heal(body, given)
	elif proj_type == 7:
		# Path to Exile (% missing HP execute + Holy Trail)
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			if "health" in body and "enemy_data" in body and body.enemy_data:
				var missing_hp = body.enemy_data.health - body.health
				var exec_dmg = (40.0 + missing_hp * GameSettings.spell_white_path_to_exile_exec_mult) * effect_multiplier
				body.take_damage(exec_dmg, _get_caster())
		# Spawn Holy Trail - through the effect spawner, so the ally who is meant to walk
		# through it can see where it is.
		var scene: Node = get_tree().current_scene
		if scene != null and scene.has_method("request_effect"):
			var healer: Node3D = _get_caster()
			scene.request_effect({
				"kind": "dot_zone", "type": "holy_trail", "position": global_position,
				"radius": 3.0, "dps": 15.0, "duration": 4.0,
				"caster": healer.get_multiplayer_authority() if healer != null else 0,
			})
	else:
		if body.has_method("take_damage"):
			body.take_damage(damage, _get_caster())
	
	deactivate()

func _trigger_fireball_aoe() -> void:
	_fireball_blast_visuals()
	var radius = aoe_radius if aoe_radius > 0.0 else GameSettings.spell_red_fireball_base_radius
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage, _get_caster())


## Everything about the detonation that is not damage. Split out because it runs on every
## peer while the damage above runs on one.
func _fireball_blast_visuals() -> void:
	var radius = aoe_radius if aoe_radius > 0.0 else GameSettings.spell_red_fireball_base_radius
	var burst: Node3D = EmberFx.build_burst(radius)
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position
	# What the blast leaves behind. Outlives the fire by seconds, which is the whole point:
	# a detonation with nothing after it reads as having happened in front of the world
	# rather than to it. See docs/SPELL_VFX_PLAN.md, the settle beat.
	var scorch: MeshInstance3D = SpellFx.ground_decal(
		"decal_scorch", Color(0.07, 0.04, 0.03, 0.85), radius)
	get_tree().current_scene.add_child(scorch)
	# Dropped onto the floor, not left where the bolt happened to strike - a fireball that
	# detonates against an enemy's chest goes off well above the ground it burns.
	scorch.global_transform = SpellFx.ground_transform(self, global_position)
	# Its own burst rather than the giant's landing thud, which is what it used to
	# borrow: a fireball detonating and a body hitting the ground are not the same event.
	SoundBank.play_at(&"spell_fireball_impact", global_position)
	SignalBus.camera_shake_requested.emit(
		GameSettings.spell_red_fireball_shake_strength,
		GameSettings.spell_red_fireball_shake_duration
	)
	# Spawn temporary visual explosion
	var exp_mesh = CSGSphere3D.new()
	exp_mesh.radius = radius
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	exp_mesh.material = mat
	exp_mesh.global_position = global_position
	get_tree().current_scene.add_child(exp_mesh)
	
	var tw = exp_mesh.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.parallel().tween_property(exp_mesh, "scale", Vector3(1.3, 1.3, 1.3), 0.4)
	tw.tween_callback(exp_mesh.queue_free)
