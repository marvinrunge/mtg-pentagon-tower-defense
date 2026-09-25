extends StaticBody3D
class_name WallOfFrost
## Blue's wall skill: a temporary ice barricade that turns Unsummon knockback into damage.

const TINT: Color = Color(0.58, 0.86, 1.0)
const HEIGHT: float = 3.2
const THICKNESS: float = 0.85
const WALL_MODEL: PackedScene = preload("res://assets/wall-of-frost.glb")
## Measured via tools/tests headless AABB probe; the model isn't centered on its own Y axis.
const MODEL_AABB_POSITION: Vector3 = Vector3(-0.931936, -0.6207, -0.372087)
const MODEL_AABB_SIZE: Vector3 = Vector3(1.861481, 1.189154, 0.750721)

var _life_timer: float = 0.0
var _length: float = 8.0
var _unsummon_bonus_damage: float = 0.0
var _despawning: bool = false


static func create(length: float, duration: float, unsummon_bonus_damage: float) -> WallOfFrost:
	var wall := WallOfFrost.new()
	wall._length = length
	wall._life_timer = duration
	wall._unsummon_bonus_damage = unsummon_bonus_damage
	wall.name = "WallOfFrost"
	return wall


func _ready() -> void:
	# Layer 1 is hit by enemy projectiles and enemy bodies, while player projectiles ignore it.
	collision_layer = 1
	collision_mask = 0
	add_to_group("frost_walls")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_length, HEIGHT, THICKNESS)
	shape.shape = box
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	_build_wall_mesh()
	_build_projectile_catcher()
	_build_frost_shards()
	_build_footprint()

	var light := OmniLight3D.new()
	light.light_color = TINT
	light.light_energy = 1.3
	light.omni_range = _length * 0.45
	light.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(light)

	scale = Vector3(1.0, 0.08, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_unsummon_bonus_damage() -> float:
	return _unsummon_bonus_damage


func _build_wall_mesh() -> void:
	var mesh_instance: Node3D = WALL_MODEL.instantiate()
	mesh_instance.name = "IceSlab"
	mesh_instance.scale = Vector3(
		_length / MODEL_AABB_SIZE.x,
		HEIGHT / MODEL_AABB_SIZE.y,
		THICKNESS / MODEL_AABB_SIZE.z
	)
	mesh_instance.position = Vector3(0.0, -MODEL_AABB_POSITION.y / MODEL_AABB_SIZE.y * HEIGHT, 0.0)

	var slab: MeshInstance3D = mesh_instance.find_child("Mesh_0")
	var material: StandardMaterial3D = (slab.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	material.emission_enabled = true
	material.emission = TINT
	material.emission_energy_multiplier = 0.55
	material.render_priority = SpellFx.FX_RENDER_PRIORITY
	slab.material_override = material
	add_child(mesh_instance)


func _build_projectile_catcher() -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_length + 0.3, HEIGHT + 0.3, THICKNESS + 0.4)
	shape.shape = box
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _build_frost_shards() -> void:
	var shards := GPUParticles3D.new()
	shards.name = "FrostShards"
	shards.amount = 42
	shards.lifetime = 2.4
	shards.preprocess = 2.4
	shards.local_coords = false
	shards.draw_pass_1 = SpellFx.premul_particle_mesh(0.42, "shard")
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(_length * 0.5, HEIGHT * 0.45, THICKNESS * 0.3)
	process.direction = Vector3.UP
	process.spread = 28.0
	process.gravity = Vector3(0.0, 0.18, 0.0)
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.38
	process.scale_min = 0.08
	process.scale_max = 0.2
	process.color_ramp = SpellFx._premul_ramp(TINT)
	shards.process_material = process
	shards.position = Vector3(0.0, HEIGHT * 0.45, 0.0)
	add_child(shards)


func _build_footprint() -> void:
	var strip: MeshInstance3D = SpellFx.ground_decal("decal_frost", Color(0.78, 0.94, 1.0, 0.82), _length * 0.5, _life_timer * 0.7)
	strip.scale = Vector3(1.0, 1.0, 0.18)
	add_child(strip)
	strip.global_position = SpellFx.ground_transform(self, global_position).origin


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("projectiles"):
		body.queue_free()


func _process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()
		return
	if _life_timer < 0.3 and not _despawning:
		_despawning = true
		var tween: Tween = create_tween()
		tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
