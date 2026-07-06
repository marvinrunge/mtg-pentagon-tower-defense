extends SceneTree

func _init():
	var file = FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	# Base scale is 2. The user wants it "double its size" and "again double its size".
	# Effective radius was 25 * 2 = 50. Now they want 100.
	# We can just leave the scale as 2, and change radius to 50.0.
	content = content.replace("radius = 25.0", "radius = 50.0")
	
	# Z offsets for 100.0 radius. (100 * cos(36) = 80.9017)
	# Original Z offset for lanes was -20.2254 (for radius=25)
	# New Z offset should be -80.9017.
	content = content.replace(", 0, 0, -20.2254)", ", 0, 0, -80.9017)")
	
	# Mana source original Z = -92.2254. Diff from lane start = 72.
	# New Z = -80.9017 - 72 = -152.9017
	content = content.replace(", 0, 0.5, -92.2254)", ", 0, 0.5, -152.9017)")
	
	# Enemy Spawner original Z = -164.225. Diff from lane start = 144.
	# New Z = -80.9017 - 144 = -224.9017
	content = content.replace(", 0, 0.5, -164.225)", ", 0, 0.5, -224.9017)")
	
	# Polygons
	# Original: -14.6946, 0, -119.3168, -144, 119.3168, -144, 14.6946, 0
	# Since radius is 100 (4x of 25), widths should be 4x.
	# 14.6946 * 4 = 58.7784
	# 119.3168 * 4 = 477.2672
	# Let's replace the whole string.
	var old_poly = "polygon = PackedVector2Array(-14.6946, 0, -119.3168, -144, 119.3168, -144, 14.6946, 0)"
	var new_poly = "polygon = PackedVector2Array(-58.7784, 0, -477.2672, -144, 477.2672, -144, 58.7784, 0)"
	content = content.replace(old_poly, new_poly)
	
	var out_file = FileAccess.open("res://scenes/main.tscn", FileAccess.WRITE)
	out_file.store_string(content)
	out_file.close()
	
	print("Fix applied successfully!")
	quit()
