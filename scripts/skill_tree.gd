extends CanvasLayer
class_name SkillTree


@onready var points_label: Label = $Control/Panel/VBoxContainer/PointsLabel

var available_sp: int = 0
var unlocked_skills = {
	"red": false,
	"blue": false,
	"green": false,
	"white": false,
	"black": false
}

func _ready() -> void:
	hide()
	SignalBus.player_leveled_up.connect(_on_player_leveled_up)
	
	# Connect buttons
	$Control/Panel/PentagonLayout/RedNode/Button.pressed.connect(_on_unlock_pressed.bind("red", $Control/Panel/PentagonLayout/RedNode))
	$Control/Panel/PentagonLayout/BlueNode/Button.pressed.connect(_on_unlock_pressed.bind("blue", $Control/Panel/PentagonLayout/BlueNode))
	$Control/Panel/PentagonLayout/GreenNode/Button.pressed.connect(_on_unlock_pressed.bind("green", $Control/Panel/PentagonLayout/GreenNode))
	$Control/Panel/PentagonLayout/WhiteNode/Button.pressed.connect(_on_unlock_pressed.bind("white", $Control/Panel/PentagonLayout/WhiteNode))
	$Control/Panel/PentagonLayout/BlackNode/Button.pressed.connect(_on_unlock_pressed.bind("black", $Control/Panel/PentagonLayout/BlackNode))
	
	update_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree") or (visible and event.is_action_pressed("ui_cancel")):
		visible = not visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _on_player_leveled_up(_level: int, sp: int) -> void:
	available_sp = sp
	update_ui()

func _on_unlock_pressed(color: String, node: Control) -> void:
	if available_sp > 0 and not unlocked_skills[color]:
		unlocked_skills[color] = true
		SignalBus.skill_unlocked.emit(color)
		
		# Update the node visual
		var btn = node.get_node("Button")
		btn.text = "UNLOCKED"
		btn.disabled = true
		
		# We don't deduct SP here directly, we just notify the player script
		# which holds the true SP and will emit player_leveled_up with new SP.
		# But to prevent double clicking before signal arrives:
		available_sp -= 1
		update_ui()

func update_ui() -> void:
	points_label.text = "Available Skill Points: " + str(available_sp)
