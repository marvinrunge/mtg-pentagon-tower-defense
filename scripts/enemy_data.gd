extends Resource
class_name EnemyData

@export var display_name: String = "Enemy"
@export var color_identity: String = "Red" # Red, Blue, Green, White, Black
@export var enemy_class: String = "Melee" # Melee, Ranged, Mage, Boss

@export var health: float = 100.0
@export var speed: float = 2.0
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0 # Seconds between attacks
@export var attack_range: float = 2.0

@export var model_scale: float = 1.0
@export var visual_color: Color = Color.WHITE
