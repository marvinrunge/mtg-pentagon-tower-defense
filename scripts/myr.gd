extends CharacterBody3D
class_name Myr

enum State {
	IDLE,
	SPAWNING,
	WALKING_TO_MANA,
	HARVESTING,
	WALKING_TO_CRYSTAL,
	DEPOSITING
}

# color identity (matches scripts/main.gd's LANE_NAMES) -> rigged model. Built
# by tools/myr_character_builder.gd; each scene carries its own animation
# library ("walk", "walk_loaded", "harvest", "hit", "death", and "run" for a
# future speed buff - not wired up anywhere yet).
const VISUAL_SCENES := {
	"White": "res://scenes/myrs/gold_myr.tscn",
	"Blue": "res://scenes/myrs/silver_myr.tscn",
	"Black": "res://scenes/myrs/leaden_myr.tscn",
	"Red": "res://scenes/myrs/iron_myr.tscn",
	"Green": "res://scenes/myrs/copper_myr.tscn",
}

@export var speed: float = GameSettings.myr_speed

## Reused from the minibosses rather than written again - it is the same job (tint a rigged
## model in a colour without touching the material every other copy of that model shares)
## and the same answer.
const CARRY_GLOW_SHADER: Shader = preload("res://assets/shaders/miniboss_glow.gdshader")

var current_state: State = State.SPAWNING
var target_mana_source: Node3D
var target_crystal: Node3D
var lane_index: int = -1
var health: float = GameSettings.myr_max_hp
var max_health: float = GameSettings.myr_max_hp
## What the player calls this one. Empty means they never named it, and the base screen
## shows a positional "Myr 3" instead - a default name stored here would be wrong the
## moment an earlier myr died and the numbering shifted under it.
var display_name: String = ""
## Bought in the base, per myr. Raises health and how much mana it carries home; see
## set_level and carry_amount.
var level: int = 1
var fervor_active: bool = false
var is_dying: bool = false

# A lane change requested while this Myr is already out working one is queued
# here rather than applied immediately - it takes effect the next time this
# Myr sets out from the crystal (see the State.DEPOSITING branch of
# _physics_process), so reassigning never yanks it off a delivery in progress.
var _pending_lane_index: int = -1
var _pending_mana_source: Node3D

var visual_anim_player: AnimationPlayer
## Surface materials swapped in to make a loaded myr glow, kept so the glow can be taken
## off again on deposit. Empty whenever the myr is walking out empty-handed.
var _carry_glow_surfaces: Array = []
var _carrying: bool = false
## Blue, Propaganda: seconds this myr is still phased out of reach. Only ever set while
## carrying - see take_damage.
var _phase_left: float = 0.0
var _current_color: String = ""

# The slot at the well this Myr stands in while harvesting, so five Myrs fan out
# around one well the way workers fan around a mine rather than stacking on its
# centre - which is also what kept them wedged against the well's collision.
var _well_slot_offset: Vector3 = Vector3.ZERO

# Timer properties
var harvest_time: float = GameSettings.myr_harvest_time
var deposit_time: float = 1.0
var state_timer: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Add to group so enemies can find Myrs
	add_to_group("myrs")
	SignalBus.player_auras_changed.connect(_refresh_fervor_state)
	_refresh_fervor_state()
	
	# Set collision layer and mask
	# Layer 2: Myr (binary: 2)
	collision_layer = 2
	# Mask: Layer 3 (Enemies), Layer 5 (Environment/Static)
	# Layer 3 = 4, Layer 5 = 16. Total mask = 4 + 16 = 20.
	collision_mask = 20
	# A myr spawned already levelled (loaded from a save, or replicated to a client that
	# joined mid-run) never passes through set_level, so the size is applied here too.
	_apply_level_scale()
	
	# Read metadata targets set by map generator
	if has_meta("target_mana_source"):
		target_mana_source = get_meta("target_mana_source")
	else:
		# Fallback: search in group
		var sources = get_tree().get_nodes_in_group("mana_sources")
		if sources.size() > 0:
			# Just pick one if none was assigned
			target_mana_source = sources[0]
			
	if has_meta("target_crystal"):
		target_crystal = get_meta("target_crystal")
	else:
		var crystal_nodes = get_tree().get_nodes_in_group("crystal")
		if crystal_nodes.size() > 0:
			target_crystal = crystal_nodes[0]
			
	if has_meta("lane_index"):
		lane_index = get_meta("lane_index")

	# Initialize state
	if lane_index >= 0 and target_mana_source:
		current_state = State.WALKING_TO_MANA
		_apply_color_visual(_lane_color())
		update_navigation_target()
	else:
		current_state = State.IDLE

## Called from the base UI, any time, for any Myr. A Myr that hasn't been
## given a lane yet (fresh off the build queue, still IDLE) starts immediately
## - there's no delivery in progress to protect. One that's already working a
## lane instead has the change queued for its next departure from the crystal.
func assign_lane(index: int, source: Node3D) -> void:
	if lane_index == -1:
		_commit_lane(index, source)
	else:
		_pending_lane_index = index
		_pending_mana_source = source


## Claims one of the well's harvest slots, if there is a free one. MainController owns
## the per-well registry, because a Myr only knows its own lane, not its colleagues'.
func claim_well_slot() -> bool:
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("claim_well_slot"):
		return main_node.claim_well_slot(self, lane_index)
	return true


func release_well_slot() -> void:
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("release_well_slot"):
		main_node.release_well_slot(self)


func set_well_slot_offset(offset: Vector3) -> void:
	_well_slot_offset = offset
	if current_state == State.WALKING_TO_MANA:
		update_navigation_target()

func _commit_lane(index: int, source: Node3D) -> void:
	lane_index = index
	target_mana_source = source
	current_state = State.WALKING_TO_MANA
	_apply_color_visual(_lane_color())
	update_navigation_target()
	_pending_lane_index = -1
	_pending_mana_source = null

## Resolves this Myr's own lane color, matching how start_depositing() already
## looks it up (scripts/main.gd's LANE_NAMES).
func _lane_color() -> String:
	var main_node = get_tree().current_scene
	if main_node and "LANE_NAMES" in main_node and lane_index >= 0 and lane_index < main_node.LANE_NAMES.size():
		return main_node.LANE_NAMES[lane_index]
	return ""

## How much this myr brings back per trip. Levels are worth more to a myr that is already
## walking the route than a second myr would be, because the walk is the cost.
func carry_amount() -> int:
	return 1 + (level - 1) * GameSettings.myr_level_carry_bonus


## Sets the level and rebuilds what depends on it.
##
## The health GAIN arrives as health rather than only as headroom: a level bought while
## hurt that left the bar at the same number, only further from full, would read as having
## done nothing.
func set_level(new_level: int) -> void:
	var clamped: int = clampi(new_level, 1, GameSettings.myr_max_level)
	if clamped == level:
		return
	var gained: float = float(clamped - level) * GameSettings.myr_level_hp_bonus
	level = clamped
	max_health = GameSettings.myr_max_hp + float(level - 1) * GameSettings.myr_level_hp_bonus
	health = minf(max_health, health + maxf(gained, 0.0))
	_apply_level_scale()


## A loaded myr glows in the colour of what it is carrying.
##
## The myr economy is the quietest thing in the game: a myr walks out, stands at a well for
## ten seconds and walks back, and none of that reads at a glance as "this one is bringing
## you mana". The glow is the tell - a myr coming home lit up in its lane's colour is one
## the player can see working, and one an enemy killing it is visibly taking something off.
##
## Applied as a second render PASS on a duplicated material, exactly as EnemyBase does for
## a miniboss: the mesh's own material is shared with every other myr wearing this model,
## so tinting it in place would light up the whole fleet.
func _set_carrying(carrying: bool) -> void:
	if carrying == _carrying:
		return
	_carrying = carrying
	if not carrying:
		_clear_carry_glow()
		return
	var tint: Color = GameSettings.lane_tint(_lane_color())
	var glow_material := ShaderMaterial.new()
	glow_material.shader = CARRY_GLOW_SHADER
	glow_material.set_shader_parameter("glow_color", tint)

	var skeleton: Skeleton3D = find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	for child: Node in skeleton.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		for surface: int in range(mesh_instance.get_surface_override_material_count()):
			var base_material: Material = mesh_instance.get_active_material(surface)
			if base_material == null:
				continue
			var duplicated: Material = base_material.duplicate()
			duplicated.next_pass = glow_material
			mesh_instance.set_surface_override_material(surface, duplicated)
			_carry_glow_surfaces.append([mesh_instance, surface])


## Puts every surface the glow touched back to the model's own material. Cleared by
## reference rather than by re-duplicating, so a myr that changed colour mid-route (a lane
## reassignment commits on deposit) cannot leave a stale tint behind.
func _clear_carry_glow() -> void:
	for entry: Array in _carry_glow_surfaces:
		var mesh_instance: MeshInstance3D = entry[0]
		if is_instance_valid(mesh_instance):
			mesh_instance.set_surface_override_material(int(entry[1]), null)
	_carry_glow_surfaces.clear()


## Size, as a function of level. The whole node rather than just the visual, so the body a
## bigger myr presents to the enemies chasing it grows with it - a level is supposed to
## make it survive the walk, and half of surviving is being the thing that got noticed.
func _apply_level_scale() -> void:
	var factor: float = 1.0 + float(level - 1) * GameSettings.myr_level_scale_bonus
	scale = Vector3.ONE * factor


## What the base screen calls this myr. `fallback_index` is its position in the list, used
## only when the player has not named it.
func label(fallback_index: int) -> String:
	return display_name if display_name.strip_edges() != "" else "Myr %d" % fallback_index


## `amount` is what reached the myr; the two enchantments that protect it are applied here.
##
## White is flat armour and always applies. Blue is intermittent and only while LOADED: the
## hit that starts the phase still lands, and the follow-ups inside the window do not, so
## it buys a myr the seconds it needs to finish a delivery rather than making it tougher.
## A myr walking out empty-handed gets nothing from Blue at all.
func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false) -> void:
	if is_dying or _phase_left > 0.0:
		return
	amount *= 1.0 - RunState.myr_damage_reduction()
	if _carrying:
		var phase: float = RunState.myr_phase_duration()
		if phase > 0.0:
			_phase_left = phase
	health = maxf(0.0, health - amount)
	NetFx.damage_number(global_position + Vector3(0, 1.2, 0), amount, Color(1.0, 0.25, 0.25), "")
	if health <= 0.0:
		die()
	elif visual_anim_player and visual_anim_player.has_animation("hit"):
		visual_anim_player.play("hit")

## Returns the health actually restored, matching Player.heal - the white skills that heal
## myrs credit that number to the caster's scoreboard, and a myr already at full health should
## not pay out for a heal it could not use.
func heal(amount: float) -> float:
	var previous_health: float = health
	health = minf(max_health, health + amount)
	if health > previous_health:
		NetFx.damage_number(global_position + Vector3(0, 1.2, 0), previous_health - health, Color(0.2, 1.0, 0.4), "")
	return health - previous_health

## Whether anything may pick this myr as a target. Enemies check it in _acquire_target and
## in their special targeting, so a phased myr is walked away from rather than swung at.
func is_targetable() -> bool:
	return not is_dying and _phase_left <= 0.0


func die() -> void:
	if is_dying:
		return
	_phase_left = 0.0
	visible = true
	_myr_death_blast()
	is_dying = true
	remove_from_group("myrs")
	release_well_slot()
	collision_layer = 0
	collision_mask = 0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		visual_anim_player.play("death")
		var death_anim: Animation = visual_anim_player.get_animation("death")
		get_tree().create_timer(death_anim.length).timeout.connect(queue_free)
	else:
		queue_free()

## Black, Exquisite Blood: a myr that dies takes the neighbourhood with it.
##
## Server-only. Myr._physics_process has no authority guard and every peer runs its own
## copy of the state machine, so an unguarded blast would be dealt once per peer - and the
## FX go out through NetFx from here for the same reason, so every peer sees one blast
## rather than each spawning its own.
func _myr_death_blast() -> void:
	var damage: float = RunState.myr_blast_damage()
	var radius: float = RunState.myr_blast_radius()
	if damage <= 0.0 or radius <= 0.0 or not Net.is_server():
		return
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if global_position.distance_to((enemy as Node3D).global_position) > radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, self, false)
	var tint: Color = GameSettings.lane_tint(_lane_color())
	NetFx.impact(global_position, tint, radius)
	NetFx.ring(global_position, tint, radius)


func _refresh_fervor_state() -> void:
	fervor_active = false
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.has_method("has_aura") and player.has_aura("aura_fervor"):
			fervor_active = true
			return

## A Myr with no lane/colour assigned yet has no model - showing any shape here
## reads as a real unit already working the field, when it's actually just
## sitting unassigned at the crystal. Gives this Myr the rigged model matching
## `color`, once assign_lane() (or pre-set spawn metadata) makes it known - and
## replaces it if a queued reassignment (_commit_lane, once a delivery finishes)
## changes the colour later. A no-op if `color` is what it already has.
func _apply_color_visual(color: String) -> void:
	if not VISUAL_SCENES.has(color) or color == _current_color:
		return
	if visual_anim_player and is_instance_valid(visual_anim_player):
		visual_anim_player.get_parent().queue_free()
		visual_anim_player = null

	# The old model's surfaces are about to be freed with it, so anything still pointing
	# at them has to go first.
	_carry_glow_surfaces.clear()
	var visual_scene: PackedScene = load(VISUAL_SCENES[color])
	var visual_instance: Node3D = visual_scene.instantiate()
	# Scale correction: imported models are tiny (~0.016m). We scale them up 100x to match a 1-unit base.
	visual_instance.scale = Vector3(100, 100, 100)
	add_child(visual_instance)
	_ground_visual(visual_instance)
	visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
	_current_color = color
	_rest_visual_animation()


func _ground_visual(visual_instance: Node3D) -> void:
	var skeleton: Skeleton3D = visual_instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var mesh_instance: MeshInstance3D = null
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		return
	var local_aabb: AABB = mesh_instance.get_aabb()
	var min_y: float = INF
	for corner_idx: int in range(8):
		var corner: Vector3 = local_aabb.position + Vector3(
			local_aabb.size.x * float(corner_idx & 1),
			local_aabb.size.y * float((corner_idx >> 1) & 1),
			local_aabb.size.z * float((corner_idx >> 2) & 1)
		)
		min_y = min(min_y, (mesh_instance.global_transform * corner).y)
	if is_finite(min_y):
		visual_instance.position.y -= min_y - global_position.y

func _play_visual_animation(anim_name: String) -> void:
	if visual_anim_player.current_animation != anim_name or not visual_anim_player.is_playing():
		visual_anim_player.play(anim_name)

## No dedicated idle clip for the empty-handed state - hold the first frame of
## "walk" instead, same reasoning as EnemyBase._rest_visual_animation().
func _rest_visual_animation() -> void:
	if visual_anim_player.current_animation != "walk":
		visual_anim_player.play("walk")
	if visual_anim_player.is_playing():
		visual_anim_player.pause()

func _update_visual_animation() -> void:
	if not visual_anim_player:
		return
	# Let a triggered "hit" reaction finish before any state-driven clip
	# overrides it, same pattern as EnemyBase's attack-swing check.
	if visual_anim_player.current_animation == "hit" and visual_anim_player.is_playing():
		return
	match current_state:
		State.WALKING_TO_MANA:
			_play_visual_animation("walk")
		State.WALKING_TO_CRYSTAL:
			_play_visual_animation("walk_loaded")
		State.HARVESTING, State.DEPOSITING:
			_play_visual_animation("harvest")
		_:
			_rest_visual_animation()

func update_navigation_target() -> void:
	if not nav_agent:
		return
	
	match current_state:
		State.WALKING_TO_MANA:
			if target_mana_source:
				# The slot, not the centre: five Myrs heading for the same point on the
				# well is what jammed them against it and against each other.
				nav_agent.target_position = target_mana_source.global_position + _well_slot_offset
		State.WALKING_TO_CRYSTAL:
			if target_crystal:
				nav_agent.target_position = target_crystal.global_position

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	var current_speed: float = speed
	if fervor_active:
		current_speed *= GameSettings.aura_fervor_speed_boost
	# Red, Furnace of Rath. Multiplied alongside Fervor rather than instead of it: they are
	# different sources and a team that has bought both should get both.
	current_speed *= RunState.myr_speed_multiplier()

	if _phase_left > 0.0:
		_phase_left -= delta
		# Flickering IS the tell. There is no other way to see that a myr cannot be hit,
		# and the alternative - tinting it - is already spoken for by the carry glow.
		visible = int(_phase_left * 12.0) % 2 == 0
		if _phase_left <= 0.0:
			visible = true

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	# Process states
	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)
			move_and_slide()
		State.WALKING_TO_MANA, State.WALKING_TO_CRYSTAL:
			if nav_agent.is_navigation_finished():
				if current_state == State.WALKING_TO_MANA:
					start_harvesting()
				else:
					start_depositing()
			else:
				var next_path_position = nav_agent.get_next_path_position()
				var current_agent_position = global_position
				var new_velocity = (next_path_position - current_agent_position).normalized() * current_speed
				velocity.x = new_velocity.x
				velocity.z = new_velocity.z
				
				# Rotate to face direction
				if velocity.length_squared() > 0.01:
					var target_rotation = atan2(velocity.x, velocity.z)
					rotation.y = lerp_angle(rotation.y, target_rotation, 10.0 * delta)
				
				move_and_slide()
				
		State.HARVESTING:
			velocity.x = 0.0
			velocity.z = 0.0
			_set_carrying(false)
			# move_and_slide() must still run every frame even while stationary -
			# it's the only thing that applies the gravity integrated above and
			# refreshes is_on_floor(). Skipping it let velocity.y fall unbounded
			# for the whole harvest_time, and the next move (WALKING_TO_CRYSTAL)
			# would have to resolve several seconds of pent-up fall speed in one
			# slide, which could jam the Myr into the well's collision instead of
			# walking off - the "stuck at the mana well" symptom.
			move_and_slide()
			state_timer -= delta
			if state_timer <= 0.0:
				current_state = State.WALKING_TO_CRYSTAL
				# Full, and it should look it from across the lane - see _set_carrying.
				_set_carrying(true)
				update_navigation_target()

		State.DEPOSITING:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			state_timer -= delta
			if state_timer <= 0.0:
				if _pending_lane_index != -1:
					_commit_lane(_pending_lane_index, _pending_mana_source)
				else:
					current_state = State.WALKING_TO_MANA
					update_navigation_target()

	_update_visual_animation()

func start_harvesting() -> void:
	current_state = State.HARVESTING
	state_timer = harvest_time

func start_depositing() -> void:
	current_state = State.DEPOSITING
	state_timer = deposit_time
	_set_carrying(false)

	var color := _lane_color()
	SignalBus.mana_deposited.emit(color if color != "" else "Colorless", carry_amount())
