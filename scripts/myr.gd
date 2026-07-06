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

@export var speed: float = 2.0

var current_state: State = State.SPAWNING
var target_mana_source: Node3D
var target_crystal: Node3D
var lane_index: int = -1

# Timer properties
var harvest_time: float = 3.0
var deposit_time: float = 1.0
var state_timer: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Add to group so enemies can find Myrs
	add_to_group("myrs")
	
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
		
	# Setup visual helper (yellow body)
	setup_visuals()
	
	# Initialize state
	if lane_index >= 0 and target_mana_source:
		current_state = State.WALKING_TO_MANA
		update_navigation_target()
	else:
		current_state = State.IDLE

func assign_lane(index: int, source: Node3D) -> void:
	lane_index = index
	target_mana_source = source
	current_state = State.WALKING_TO_MANA
	update_navigation_target()

func setup_visuals() -> void:
	# Create a simple visual cylinder/capsule for the Myr
	var visual = CSGCylinder3D.new()
	visual.radius = 0.4
	visual.height = 1.0
	visual.position = Vector3(0, 0.5, 0)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.1) # Gold/yellow
	mat.metallic = 0.8
	mat.roughness = 0.2
	visual.material = mat
	add_child(visual)

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
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	# Process states
	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
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
				var new_velocity = (next_path_position - current_agent_position).normalized() * speed
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
			state_timer -= delta
			if state_timer <= 0.0:
				current_state = State.WALKING_TO_CRYSTAL
				update_navigation_target()
				
		State.DEPOSITING:
			velocity.x = 0.0
			velocity.z = 0.0
			state_timer -= delta
			if state_timer <= 0.0:
				current_state = State.WALKING_TO_MANA
				update_navigation_target()

func start_harvesting() -> void:
	current_state = State.HARVESTING
	state_timer = harvest_time

func start_depositing() -> void:
	current_state = State.DEPOSITING
	state_timer = deposit_time
	
	var main_node = get_tree().current_scene
	var color = "Colorless"
	if main_node and "LANE_NAMES" in main_node and lane_index >= 0 and lane_index < main_node.LANE_NAMES.size():
		color = main_node.LANE_NAMES[lane_index]
		
	SignalBus.mana_deposited.emit(color, 1)
