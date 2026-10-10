extends Node
## Key-art renders for the splash, menu, loading and game-over screens: the real map under
## the real sky, with the game's own creature models posed in it, framed for each screen.
## They are meant as the base for an image-to-image polish into card-art paintings, so what
## matters is the staging - who stands where, lit how - not the final finish. See
## docs/SCREEN_ART_PROMPTS.md.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --windowed --resolution 2400x1350 res://tools/tests/key_art_shot.tscn -- <folder> [shot,shot...]
##   ... -- --probe     prints the lanes, the crystal and every model's animation clips
##   ... -- <png> --map [--map-size=440]
##                       a top-down picture of the map at noon, without fog or people:
##                       orthographic, map-size metres across centred on the crystal, +X
##                       to the right and -Z up. Plans shots, and at 360 across it is the
##                       minimap's picture (assets/images/minimap.png - see Minimap)
##
## Shots are written as <folder>/<shot>.png. `--time=H` renders every shot at hour H instead of
## its own time of day.

## Which race each colour's units are, for res://scenes/<kind>/<race>_<kind>.tscn.
const RACES: Dictionary = {
	"White": "human", "Blue": "merfolk", "Black": "zombie", "Red": "goblin", "Green": "elf",
}
const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]

var _frames: int = 0
var _started: bool = false
var _scene: Node3D
var _crystal: Vector3
var _camera: Camera3D
var _staged: Array[Node] = []
var _rng := RandomNumberGenerator.new()
var _terrain: StaticBody3D


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/key_art_shot.gd").new()
	probe.name = "KeyArtShot"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	# The terrain, its foliage and the navmesh bake all have to have finished.
	if _frames < 300:
		return
	_started = true
	_scene = get_tree().current_scene as Node3D
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_terrain = _scene.call("_find_collision_body", _scene.get_node("TerraBrush"))
	if args.has("--probe"):
		_probe()
	elif args.has("--map"):
		var size: float = 440.0
		for arg: String in args:
			if arg.begins_with("--map-size="):
				size = float(arg.trim_prefix("--map-size="))
		await _map(args[0], size)
	else:
		await _render_all(args)
	get_tree().quit()


func _probe() -> void:
	var crystal: Node3D = _scene.get("crystal_anchor")
	print("KEYART crystal anchor %s, visual %s" % [crystal.global_position, (_scene.get("crystal_visual") as Node3D).global_position])
	var names: Array = _scene.get("LANE_NAMES")
	var spawners: Array = _scene.get("enemy_spawners")
	for i: int in spawners.size():
		var p: Vector3 = (spawners[i] as Node3D).global_position
		print("KEYART lane %s spawner %s  angle %.0f deg  dist %.0f" % [names[i], p.round(), rad_to_deg(atan2(p.z, p.x)), Vector2(p.x, p.z).length()])
	var wells: Array = _scene.get("mana_sources")
	_crystal = crystal.global_position
	for i: int in wells.size():
		var w: Vector3 = (wells[i] as Node3D).global_position - _crystal
		var lane: String = names[i]
		print("KEYART well %s at along %.0f side %.0f" % [lane, w.dot(_lane_forward(lane)), w.dot(_lane_side(lane))])
	var paths: Array[String] = ["res://scenes/melee/goblin_melee.tscn", "res://scenes/ranged/goblin_ranged.tscn",
		"res://scenes/mage/goblin_mage.tscn", "res://scenes/bosses/fire_giant.tscn", "res://scenes/bosses/treant.tscn"]
	for path: String in paths:
		var visual: Node = (load(path) as PackedScene).instantiate()
		var player: AnimationPlayer = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("KEYART %s anims %s" % [path.get_file(), player.get_animation_list() if player else "none"])
		visual.free()
	var avatar: Node = PlayerRegistry.get_local()
	if avatar != null:
		var ap: AnimationPlayer = avatar.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("KEYART player anims %s" % [ap.get_animation_list() if ap else "none"])


# --- shots ----------------------------------------------------------------------------
#
# Everything is in LANE coordinates: `along` metres out from the crystal towards that lane's
# spawner, `side` metres to its right, heights above the terrain at that spot.

## A unit of `color` and `kind` ("melee", "ranged", "mage", "boss") at lane coordinates,
## facing `face` ("crystal", "out", or a lane-coordinate Vector2 to look at).
func _actor(kind: String, color: String, along: float, side: float, anim: String = "walk",
		phase: float = -1.0, face: Variant = "crystal") -> Dictionary:
	return {"kind": kind, "color": color, "at": Vector2(along, side), "anim": anim, "phase": phase, "face": face}


## A marching block: `rows` deep from `front` outwards, `cols` wide, mixed classes behind a
## melee front rank, everyone at their own point in the walk so the block is not lockstep.
func _horde(color: String, front: float, rows: int, cols: int, spacing: float = 2.2,
		side: float = 0.0, anim: String = "walk") -> Array:
	var out: Array = []
	var kinds: Array[String] = ["melee", "melee", "ranged", "mage"]
	for r: int in rows:
		for c: int in cols:
			var jitter := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.6, 0.6))
			var kind: String = "melee" if r == 0 else kinds[_rng.randi() % kinds.size()]
			out.append(_actor(kind, color, front + r * spacing + jitter.x,
				side + (c - (cols - 1) * 0.5) * spacing + jitter.y, anim))
	return out


func _shots() -> Dictionary:
	_rng.seed = 7
	var shots: Dictionary = {}

	# Splash: the hero seen from behind, in front of the crystal, facing out down the Red lane
	# towards the volcano. The upper third is sky, for the logo.
	shots["splash"] = {
		"lane": "Red", "time": 16.0, "fov": 42.0,
		"cam": Vector3(-21.0, 0.6, 2.0), "look": Vector3(0.0, 0.0, 4.2),
		"actors": [{"kind": "hero", "at": Vector2(-10.0, 1.0), "anim": "idle_look_1", "phase": 0.35, "face": "out"}],
	}

	# Menu: the hero close on the right, facing a Red warband and its fire giant cresting the
	# rise below the volcano (lane coordinates ~225 along, 17 side). The left is kept quiet
	# for the menu.
	var menu_actors: Array = [
		{"kind": "hero", "at": Vector2(52.0, 3.0), "anim": "taunt_battlecry", "phase": 0.45, "face": Vector2(70.0, -3.0)},
		_actor("boss", "Red", 70.0, -3.0, "walk", 0.3),
	]
	menu_actors.append_array(_horde("Red", 66.0, 4, 6, 2.3, -4.0))
	shots["menu"] = {
		"lane": "Red", "time": 16.2, "fov": 50.0,
		"cam": Vector3(46.0, 1.0, 1.5), "look": Vector3(70.0, -4.0, 3.5),
		"actors": menu_actors,
	}

	# Loading: one per colour - the boss at the head of its warband in its own biome, seen
	# close and low from in front, so it towers the way a creature does on a card. Well short
	# of the lane's mana well (112 along). The bottom strip stays clear for the bar and a tip.
	var stage: Dictionary = {
		"White": {"time": 15.6, "boss": 70.0, "side": 1.0, "cam_side": -2.5, "anim": "walk", "phase": 0.25},
		"Blue": {"time": 15.2, "boss": 70.0, "side": 1.0, "cam_side": -2.5, "anim": "walk", "phase": 0.25},
		"Black": {"time": 15.6, "boss": 68.0, "side": 0.5, "cam_side": -2.0, "anim": "walk", "phase": 0.25},
		"Red": {"time": 16.0, "boss": 52.0, "side": 0.5, "cam_side": 2.0, "anim": "walk", "phase": 0.25},
		# The treant's special raises an arm over its head, which reads; the others' is a
		# ground slam that photographs as a boss bent double.
		"Green": {"time": 14.8, "boss": 64.0, "side": 1.0, "cam_side": -4.0, "anim": "special", "phase": 0.4},
	}
	for color: String in COLORS:
		var at: Dictionary = stage[color]
		var boss_along: float = at["boss"]
		var actors: Array = [_actor("boss", color, boss_along, at["side"], String(at["anim"]), float(at["phase"]))]
		actors.append_array(_horde(color, boss_along + 5.0, 4, 5, 2.4, 0.0))
		shots["loading_" + color.to_lower()] = {
			"lane": color, "time": float(at["time"]), "fov": 50.0,
			"cam": Vector3(boss_along - 8.5, float(at["cam_side"]), 1.0),
			"look": Vector3(boss_along + 2.0, float(at["side"]), 3.0),
			"actors": actors,
		}

	# Game over: the hub overrun. Every colour around the crystal, the bosses looming behind
	# it, the hero down in the foreground. Inside the ring of standing stones.
	var over: Array = [{"kind": "hero", "at": Vector2(-10.0, 1.5), "anim": "death", "phase": 1.0, "face": "out"}]
	var kinds: Array[String] = ["melee", "melee", "ranged", "mage"]
	for i: int in 16:
		var angle: float = TAU * float(i) / 16.0 + _rng.randf_range(-0.12, 0.12)
		var radius: float = _rng.randf_range(5.5, 8.5)
		over.append(_actor(kinds[i % kinds.size()], COLORS[i % COLORS.size()], cos(angle) * radius,
			sin(angle) * radius, "attack", _rng.randf_range(0.2, 0.6), Vector2.ZERO))
	for i: int in COLORS.size():
		var angle: float = deg_to_rad(-70.0 + 35.0 * float(i))
		over.append(_actor("boss", COLORS[i], cos(angle) * 14.0, sin(angle) * 14.0, "attack", 0.4, Vector2.ZERO))
	shots["game_over"] = {
		"lane": "Black", "time": 17.0, "fov": 52.0,
		"cam": Vector3(-15.0, 2.0, 1.4), "look": Vector3(0.0, 0.0, 3.6),
		"actors": over,
	}
	return shots


# --- staging --------------------------------------------------------------------------

func _render_all(args: PackedStringArray) -> void:
	var folder: String = args[0] if args.size() > 0 else "user://key_art"
	DirAccess.make_dir_recursive_absolute(folder)
	var wanted: Array = Array(args[1].split(",")) if args.size() > 1 else []

	var hud: Node = _scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	_crystal = (_scene.get("crystal_anchor") as Node3D).global_position
	var avatar: Node3D = PlayerRegistry.get_local() as Node3D
	if avatar != null:
		avatar.visible = false
	_camera = Camera3D.new()
	_camera.far = 4000.0
	_scene.add_child(_camera)
	_camera.current = true

	var shots: Dictionary = _shots()
	for shot_name: String in shots:
		if not wanted.is_empty() and not wanted.has(shot_name):
			continue
		await _stage(shots[shot_name])
		var path: String = folder.path_join(shot_name + ".png")
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(path)
		print("KEYART wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
		_clear()


func _stage(shot: Dictionary) -> void:
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		var hour: float = float(shot["time"])
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--time="):
				hour = float(arg.trim_prefix("--time="))
		sky.set("current_time", hour)
	var lane: String = shot["lane"]
	_camera.fov = float(shot.get("fov", 55.0))
	var cam: Vector3 = shot["cam"]
	var look: Vector3 = shot["look"]
	_camera.global_position = _lane_point(lane, cam.x, cam.y, cam.z)
	_camera.look_at(_lane_point(lane, look.x, look.y, look.z), Vector3.UP)
	for actor: Dictionary in shot["actors"]:
		_place(lane, actor)
	if OS.get_cmdline_user_args().has("--debug"):
		print("KEYART camera %s" % _camera.global_position)
		for node: Node in _staged.slice(0, 3):
			print("KEYART   actor %s at %s" % [node.name, (node as Node3D).global_position])
		for a: float in [-25.0, -21.0, -15.0, -10.0, -5.0, 0.0]:
			print("KEYART   ground at along %.0f: %.2f" % [a, _lane_point(lane, a, 0.0, 0.0).y])
	# The biome fog eases towards wherever the camera is; snap it there instead of waiting.
	var atmosphere: Node = _scene.find_child("BiomeAtmosphere", true, false)
	for i: int in 90:
		if atmosphere != null:
			atmosphere.set("_current", atmosphere.call("_target"))
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _clear() -> void:
	for node: Node in _staged:
		if node is Player:
			# Not freed - it is the run's own avatar - but out of the next shot.
			(node as Node3D).visible = false
		elif is_instance_valid(node):
			node.queue_free()
	_staged.clear()


## World position of a lane coordinate, `height` above the terrain there.
func _lane_point(lane: String, along: float, side: float, height: float) -> Vector3:
	var flat: Vector3 = _crystal + _lane_forward(lane) * along + _lane_side(lane) * side
	return Vector3(flat.x, _ground(flat) + height, flat.z)


func _lane_forward(lane: String) -> Vector3:
	var names: Array = _scene.get("LANE_NAMES")
	var spawner: Vector3 = ((_scene.get("enemy_spawners") as Array)[names.find(lane)] as Node3D).global_position
	return Vector3(spawner.x - _crystal.x, 0.0, spawner.z - _crystal.z).normalized()


func _lane_side(lane: String) -> Vector3:
	return _lane_forward(lane).cross(Vector3.UP).normalized()


## The terrain's height under `at`. The Environment layer also holds the trees, rocks and the
## crystal's own collision box, so anything else the ray meets is stepped through - the
## first version stood whole warbands on the forest canopy.
func _ground(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z), Vector3(at.x, -200.0, at.z), 1 << 4)
	var exclude: Array[RID] = []
	for i: int in 32:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return 0.0
		if hit.collider == _terrain:
			return hit.position.y
		exclude.append(hit.rid)
	return 0.0


func _map(path: String, size: float) -> void:
	var hud: Node = _scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var avatar: Node3D = PlayerRegistry.get_local() as Node3D
	if avatar != null:
		avatar.visible = false
	# From straight above, the volcano's smoke is a grey blot over a corner of the map.
	var smoke: Node3D = _scene.get_node_or_null("VolcanoSmoke") as Node3D
	if smoke != null:
		smoke.visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
		# From 600 m up the screen-space fog is all there is to see.
		var atmosphere: Node = _scene.find_child("BiomeAtmosphere", true, false)
		if atmosphere != null:
			atmosphere.set_process(false)
		var dome: Node = sky.get("sky")
		if dome != null:
			dome.set("fog_density", 0.0)
			dome.set("fog_visible", false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.far = 2000.0
	_scene.add_child(camera)
	camera.global_position = Vector3(0.0, 600.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("KEYART wrote map %s" % path)


func _place(lane: String, actor: Dictionary) -> void:
	var at: Vector2 = actor["at"]
	var node: Node3D
	if actor["kind"] == "hero":
		node = PlayerRegistry.get_local() as Node3D
		node.visible = true
		node.set_physics_process(false)
		node.set_process(false)
		for tree: Node in node.find_children("*", "AnimationTree", true, false):
			(tree as AnimationTree).active = false
	else:
		node = _unit_visual(String(actor["kind"]), String(actor["color"]))
		_scene.add_child(node)
	_staged.append(node)
	node.global_position = _lane_point(lane, at.x, at.y, 0.0)

	var face: Variant = actor.get("face", "crystal")
	var target: Vector3
	if face is Vector2:
		target = _lane_point(lane, (face as Vector2).x, (face as Vector2).y, 0.0)
	elif String(face) == "out":
		target = node.global_position + _lane_forward(lane)
	else:
		target = Vector3(_crystal.x, node.global_position.y, _crystal.z)
	var d: Vector3 = target - node.global_position
	# The unit models face +Z, the convention EnemyBase turns its bodies by; the player's
	# body faces -Z, the camera's convention.
	node.rotation.y = atan2(d.x, d.z) + (PI if actor["kind"] == "hero" else 0.0)

	var anim_player: AnimationPlayer = node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim: String = actor.get("anim", "walk")
	if anim_player != null and anim_player.has_animation(anim):
		var length: float = anim_player.get_animation(anim).length
		var phase: float = float(actor.get("phase", -1.0))
		if phase < 0.0:
			phase = _rng.randf()
		anim_player.play(anim)
		anim_player.seek(minf(phase * length, length - 0.001), true)
		anim_player.pause()
	_ground_pose(node)


## Stands a posed figure on the ground it was placed on: lifts or lowers it until its lowest
## bone - the toe tips, Mixamo's Toe_End, which sit on the sole - is at its own origin height.
## The models' origins are not at their feet, so without this they stood half sunk into the
## terrain. By the pose rather than the mesh bounds (what EnemyBase._ground_visual does),
## because these are frozen mid-stride, mid-swing or lying dead.
func _ground_pose(node: Node3D) -> void:
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var lowest: float = INF
	for bone: int in skeleton.get_bone_count():
		lowest = minf(lowest, (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin.y)
	if is_finite(lowest):
		node.global_position.y += node.global_position.y - lowest


## The bare model of a unit - no AI, no health bar - at the size EnemyBase gives it.
func _unit_visual(kind: String, color: String) -> Node3D:
	var scene: PackedScene
	var scale: float
	if kind == "boss":
		scene = BossDatabase.get_visual_scene(color)
		scale = BossDatabase.get_model_scale(color, 2.5)
	else:
		scene = load("res://scenes/%s/%s_%s.tscn" % [kind, RACES[color], kind]) as PackedScene
		scale = EnemyDatabase.get_enemy_data(color, kind.capitalize()).model_scale
	var visual: Node3D = scene.instantiate()
	visual.scale = Vector3.ONE * 100.0 * scale
	return visual
