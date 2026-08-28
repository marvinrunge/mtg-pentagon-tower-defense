extends Node
class_name EnemyDatabase

static func get_enemy_data(color_id: String, type_id: String) -> EnemyData:
	var data = EnemyData.new()
	data.color_identity = color_id
	data.enemy_class = type_id
	
	# Base Stats by Type
	if type_id == "Melee":
		data.health = 80.0
		data.speed = 2.5
		data.attack_damage = 10.0
		data.attack_range = 2.0
		data.model_scale = 0.8
	elif type_id == "Ranged":
		data.health = 60.0
		data.speed = 2.0
		data.attack_damage = 8.0
		data.attack_range = 10.0
		data.model_scale = 0.8
	elif type_id == "Mage":
		data.health = 100.0
		data.speed = 1.5
		data.attack_damage = 15.0
		data.attack_range = 8.0
		data.attack_speed = 3.0 # Slow cast time
		data.model_scale = 1.0
	elif type_id == "Boss":
		data.health = 800.0
		data.speed = 1.2
		data.attack_damage = 40.0
		data.attack_range = 3.0
		# Each colour's boss is a different creature at a different size; the boss
		# visuals are all built to a common 1.7-unit height so this is the only
		# thing setting how big it actually is (and, via
		# GameSettings.get_boss_anim_speed, how slowly it animates).
		data.model_scale = BossDatabase.get_model_scale(color_id, 2.5)
		data.attack_speed = 1.8
		
	# Apply Color Modifiers & Visuals
	if color_id == "Red":
		data.visual_color = Color(0.8, 0.1, 0.1)
		data.display_name = "Goblin " + type_id
		# Goblins: Low HP, High Speed
		data.health *= 0.6
		data.speed *= 1.3
	elif color_id == "Blue":
		data.visual_color = Color(0.1, 0.3, 0.8)
		data.display_name = "Illusion " + type_id
		# Blue: High Range, low damage
		data.attack_range *= 1.5
		data.attack_damage *= 0.8
	elif color_id == "Green":
		data.visual_color = Color(0.1, 0.6, 0.1)
		data.display_name = "Beast " + type_id
		# Green: High HP, High Damage, Low Speed
		data.health *= 1.5
		data.attack_damage *= 1.2
		data.speed *= 0.8
	elif color_id == "White":
		data.visual_color = Color(0.9, 0.9, 0.9)
		data.display_name = "Cleric " + type_id
		# White: Balanced/Tanky
		data.health *= 1.2
	elif color_id == "Black":
		data.visual_color = Color(0.2, 0.2, 0.2)
		data.display_name = "Undead " + type_id
		# Black: Medium stats, slightly slower
		data.speed *= 0.9
		
	return data
