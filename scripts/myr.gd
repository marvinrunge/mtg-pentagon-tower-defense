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

var current_state: State = State.SPAWNING
var target_mana_source: Node3D
var target_crystal: Node3D
var lane_index: int = -1
var health: float = GameSettings.myr_max_hp
var max_health: float = GameSettings.myr_max_hp
var fervor_active: bool = false
var is_dying: bool = false

# A lane change requested while this Myr is already out working one is queued
# here rather than applied immediately - it takes effect the next time this
# Myr sets out from the crystal (see the State.DEPOSITING branch of
# _physics_process), so reassigning never yanks it off a delivery in progress.
var _pending_lane_index: int = -1
var _pending_mana_source: Node3D

var visual_anim_player: AnimationPlayer
var _current_color: String = ""

# Timer properties
var harvest_time: float = 3.0
var deposit_time: float = 1.0
var state_timer: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Add to group so enemies can find Myrs
	add_to_group("myrs")
	SignalBus.player_capstone_aura_changed.connect(_refresh_fervor_state)
	_refresh_fervor_state()
	
	# Set collision layer and mask
	# Layer 2: Myr (binary: 2)
	collision_layer = 2
	# Mask: Layer 3 (Enemies), Layer 5 (Environment/Static)
	# Layer 3 = 4, Layer 5 = 16. Total mask = 4 + 16 = 20.
	collision_mask = 20
	
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

func take_damage(amount: float, _source: Node3D = null, _is_melee: bool = false) -> void:
	if is_dying:
		return
	health = maxf(0.0, health - amount)
	SignalBus.damage_number_requested.emit(global_position + Vector3(0, 1.2, 0), amount, Color(1.0, 0.25, 0.25))
	if health <= 0.0:
		die()
	elif visual_anim_player and visual_anim_player.has_animation("hit"):
		visual_anim_player.play("hit")

func heal(amount: float) -> void:
	var previous_health: float = health
	health = minf(max_health, health + amount)
	if health > previous_health:
		SignalBus.damage_number_requested.emit(global_position + Vector3(0, 1.2, 0), previous_health - health, Color(0.2, 1.0, 0.4))

func die() -> void:
	if is_dying:
		return
	is_dying = true
	remove_from_group("myrs")
	collision_layer = 0
	collision_mask = 0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		visual_anim_player.play("death")
		var death_anim: Animation = visual_anim_player.get_animation("death")
		get_tree().create_timer(death_anim.length).timeout.connect(queue_free)
	else:
		queue_free()

func _refresh_fervor_state() -> void:
	fervor_active = false
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and "unlocked_capstone_aura" in player and player.unlocked_capstone_aura == "aura_fervor":
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

	var visual_scene: PackedScene = load(VISUAL_SCENES[color])
	var visual_instance: Node3D = visual_scene.instantiate()
	# Scale correction: imported models are tiny (~0.016m). We scale them up 100x to match a 1-unit base.
	visual_instance.scale = Vector3(100, 100, 100)
	add_child(visual_instance)
	visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
	_current_color = color
	_rest_visual_animation()

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
				nav_agent.target_position = target_mana_source.global_position
		State.WALKING_TO_CRYSTAL:
			if target_crystal:
				nav_agent.target_position = target_crystal.global_position

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	var current_speed: float = speed
	if fervor_active:
		current_speed *= GameSettings.aura_fervor_speed_boost

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

	var color := _lane_color()
	SignalBus.mana_deposited.emit(color if color != "" else "Colorless", 1)
