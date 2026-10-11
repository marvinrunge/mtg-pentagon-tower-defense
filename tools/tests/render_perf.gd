extends Node
## GPU benchmark for the map itself: what each part of the picture costs, so a graphics
## option or a default can be judged by a number instead of a guess.
##
## Run with (windowed - a headless run renders nothing and measures nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1920x1080 res://tools/tests/render_perf.tscn -- [--dump] [--presets] [--only=a,b] [--views=lane,hub,top]
##
## The map is loaded with no enemies and the waves stopped, at noon. It starts from the
## High preset (full render scale, MSAA 4x, shadows, bloom, ground relief), set straight on
## the viewport and environment rather than through GraphicsSettings, so the player's saved
## settings file is never written. From each view the baseline is measured, then every
## suspect is taken out on its own, measured, and put back; the difference is its cost.
##
## --presets measures each graphics preset (Ultra, High, Medium, Low) through GraphicsSettings
## itself, with saving switched off. Medium and Low also pick another renderer, which only a
## restart brings; here they run on whatever renderer this process booted with.
##
## --dump only lists what the scene holds (TerraBrush's runtime nodes, every light and
## whether it casts a shadow, particle systems, the sky's radiance settings) and quits.

const SETTLE_FRAMES := 40
const MEASURE_FRAMES := 180

var _frames: int = 0
var _started: bool = false
var _scene: Node3D
var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/render_perf.gd").new()
	probe.name = "RenderPerf"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	# Long enough for the navigation bake and the terrain to finish building.
	if _frames < 300:
		return
	_started = true
	_run()


func _args() -> Dictionary:
	var out := {"dump": false, "physics": false, "presets": false, "only": [], "views": ["lane", "hub", "top"]}
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dump":
			out["dump"] = true
		elif arg == "--presets":
			out["presets"] = true
		elif arg == "--physics":
			out["physics"] = true
		elif arg == "--spikes":
			out["spikes"] = true
		elif arg.begins_with("--only="):
			out["only"] = Array(arg.trim_prefix("--only=").split(","))
		elif arg.begins_with("--views="):
			out["views"] = Array(arg.trim_prefix("--views=").split(","))
	return out


func _run() -> void:
	# Several cases drive GraphicsSettings itself; none of that may reach the player's file.
	GraphicsSettings.persist = false
	var args: Dictionary = _args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_scene = get_tree().current_scene as Node3D
	var hud: Node = _scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
		_env = (sky as WorldEnvironment).environment
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	for light: Node in _scene.find_children("*", "DirectionalLight3D", true, false):
		if (light as DirectionalLight3D).light_energy > 0.0:
			_sun = light
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	_camera = Camera3D.new()
	_camera.far = 4000.0
	_scene.add_child(_camera)
	_camera.current = true

	_high_preset()
	print("PERF %s  %s  %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_viewport().get_visible_rect().size])
	if args["dump"]:
		await get_tree().process_frame
		_dump()
		get_tree().quit()
		return

	if args.get("spikes", false):
		await _hunt_spikes()
		get_tree().quit()
		return
	if args.get("physics", false):
		await _hunt_physics()
		get_tree().quit()
		return
	if args["presets"]:
		await _measure_presets(args["views"])
		get_tree().quit()
		return

	var suspects: Array = _suspects()
	print("PERF %-6s %-22s %7s %7s %7s %7s %7s %7s %7s %6s %7s" % ["view", "case", "frame", "p99", "gpu", "gpu-", "rcpu", "proc", "phys", "draws", "prims k"])
	for view: String in args["views"]:
		_point_camera(view)
		var base: Dictionary = await _measure()
		_print(view, "baseline", base, base)
		for s: Array in suspects:
			var name: String = s[0]
			if not (args["only"] as Array).is_empty() and not (args["only"] as Array).has(name):
				continue
			var undo: Callable = (s[1] as Callable).call()
			var m: Dictionary = await _measure()
			_print(view, name, m, base)
			undo.call()
			await get_tree().process_frame
		_print(view, "baseline_again", await _measure(), base)
	get_tree().quit()


## What the slow frames (99th percentile, worst) belong to: each suspect is switched off and
## on again three times over, alternating with the baseline, so a drift cannot pass for a cause.
func _hunt_spikes() -> void:
	_point_camera("hub")
	var tb: Node = _scene.get_node_or_null("TerraBrush")
	var objects_nodes: Array = []
	for n: Node in tb.find_children("*", "", true, false):
		if String(n.name) == "Objects" or n.get_class() == "ObjectsOctreeMultiMesh":
			objects_nodes.append(n)
	var suspects := {
		"terrabrush_objects": objects_nodes,
		"sky3d": [_scene.get_node_or_null("Sky3D")],
		"wave_manager": [_scene.get_node_or_null("WaveManager")],
		"myrs": [_scene.get_node_or_null("Myrs")],
		"hud_ui": [_scene.get_node_or_null("HUD"), _scene.get_node_or_null("BaseUI"), _scene.get_node_or_null("SkillTree")],
	}
	print("PERF %-24s %7s %7s %7s" % ["case", "frame", "p99", "worst"])
	for round_i: int in 3:
		for key: String in suspects:
			var b: Dictionary = await _measure()
			print("PERF %-24s %7.2f %7.2f %7.2f" % ["baseline", b["frame"], b["p99"], b["worst"]])
			var saved: Array = []
			for n: Node in suspects[key]:
				if n != null:
					saved.append([n, n.process_mode])
					n.process_mode = Node.PROCESS_MODE_DISABLED
			var m: Dictionary = await _measure()
			print("PERF %-24s %7.2f %7.2f %7.2f" % [key + "_off", m["frame"], m["p99"], m["worst"]])
			for pair: Array in saved:
				(pair[0] as Node).process_mode = pair[1]


## Which part of the scene the physics step time belongs to: every top-level child (and
## TerraBrush's own children) is switched off on its own while the step time is averaged.
func _hunt_physics() -> void:
	_point_camera("hub")
	var phys := func() -> float:
		for i: int in 30:
			await get_tree().physics_frame
		var t: float = 0.0
		for i: int in 120:
			await get_tree().physics_frame
			t += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		return t / 120.0
	print("PERF physics baseline %.2f ms  bodies active %d  collision pairs %d" % [await phys.call(), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	var targets: Array = _scene.get_children()
	var tb: Node = _scene.get_node_or_null("TerraBrush")
	if tb != null:
		targets.append_array(tb.get_children())
	for n: Node in targets:
		var before: int = n.process_mode
		n.process_mode = Node.PROCESS_MODE_DISABLED
		var t: float = await phys.call()
		n.process_mode = before
		print("PERF physics without %-40s %.2f ms" % [String(n.name) + " (" + n.get_class() + ")", t])
	print("PERF physics baseline again %.2f ms" % [await phys.call()])


func _measure_presets(views: Array) -> void:
	GraphicsSettings.persist = false
	var names := {GraphicsSettings.Preset.ULTRA: "Ultra", GraphicsSettings.Preset.HIGH: "High",
		GraphicsSettings.Preset.MEDIUM: "Medium", GraphicsSettings.Preset.LOW: "Low"}
	print("PERF %-6s %-22s %7s %7s %7s %7s %7s %7s %7s %6s %7s" % ["view", "preset", "frame", "p99", "gpu", "", "rcpu", "proc", "phys", "draws", "prims k"])
	var base := {}
	for p: int in names:
		GraphicsSettings.apply_preset(p)
		GraphicsSettings.apply_scene_dependent()
		await get_tree().process_frame
		var tb: Node = _scene.get_node_or_null("TerraBrush")
		var grass: float = float(tb.get("foliages")[0].get("definition").get("maximumRenderDistance")) if tb != null else 0.0
		print("PERF   %s: scale %.2f mode %d msaa %d shadows %s grass %.0f m" % [names[p], get_tree().root.scaling_3d_scale, get_tree().root.scaling_3d_mode, get_tree().root.msaa_3d, GraphicsSettings.shadows_enabled, grass])
		for view: String in views:
			_point_camera(view)
			var m: Dictionary = await _measure()
			if not base.has(view):
				base[view] = m
			_print(view, names[p], m, base[view])


## What the High preset sets, straight on the engine.
func _high_preset() -> void:
	var root: Window = get_tree().root
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_4X
	if _env != null:
		GraphicsSettings.configure_glow(_env, true)
	if _sun != null:
		_sun.shadow_enabled = true
	RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 1.0)
	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.HIGH)


## [name, apply() -> undo()] for every suspect.
func _suspects() -> Array:
	var root: Window = get_tree().root
	var list: Array = []
	list.append(["msaa_off", func() -> Callable:
		root.msaa_3d = Viewport.MSAA_DISABLED
		return func() -> void: root.msaa_3d = Viewport.MSAA_4X])
	list.append(["msaa_2x", func() -> Callable:
		root.msaa_3d = Viewport.MSAA_2X
		return func() -> void: root.msaa_3d = Viewport.MSAA_4X])
	list.append(["render_scale_0.75", func() -> Callable:
		root.scaling_3d_scale = 0.75
		return func() -> void: root.scaling_3d_scale = 1.0])
	list.append(["sun_shadow_off", func() -> Callable:
		var dome: Variant = _scene.get_node_or_null("Sky3D/SkyDome")
		if dome != null and "shadows_allowed" in dome:
			dome.shadows_allowed = false
		_sun.shadow_enabled = false
		return func() -> void:
			if dome != null and "shadows_allowed" in dome:
				dome.shadows_allowed = true
			_sun.shadow_enabled = true])
	list.append(["sun_shadow_dist_60", func() -> Callable:
		var before: float = _sun.directional_shadow_max_distance
		_sun.directional_shadow_max_distance = 60.0
		return func() -> void: _sun.directional_shadow_max_distance = before])
	list.append(["omni_shadows_off", func() -> Callable:
		var lights: Array = []
		for l: Node in _scene.find_children("*", "OmniLight3D", true, false):
			if (l as Light3D).shadow_enabled:
				lights.append(l)
				(l as Light3D).shadow_enabled = false
		return func() -> void:
			for l: Light3D in lights:
				l.shadow_enabled = true])
	list.append(["omni_lights_off", func() -> Callable:
		var lights: Array = []
		for l: Node in _scene.find_children("*", "OmniLight3D", true, false):
			if (l as Light3D).visible:
				lights.append(l)
				(l as Light3D).visible = false
		return func() -> void:
			for l: Light3D in lights:
				l.visible = true])
	list.append(["foliage_off", func() -> Callable:
		return _hide_terrabrush("foliage")])
	list.append(["objects_off", func() -> Callable:
		return _hide_terrabrush("objects")])
	list.append(["terrain_off", func() -> Callable:
		return _hide_terrabrush("terrain")])
	list.append(["parallax_off", func() -> Callable:
		RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 0.0)
		return func() -> void: RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 1.0)])
	list.append(["glow_off", func() -> Callable:
		_env.glow_enabled = false
		return func() -> void: _env.glow_enabled = true])
	list.append(["sky_radiance_low", func() -> Callable:
		var s: Sky = _env.sky
		var mode: int = s.process_mode
		var size: int = s.radiance_size
		s.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		s.radiance_size = Sky.RADIANCE_SIZE_64
		return func() -> void:
			s.process_mode = mode
			s.radiance_size = size])
	list.append(["particles_off", func() -> Callable:
		var ps: Array = []
		for p: Node in _scene.find_children("*", "GPUParticles3D", true, false):
			if (p as GPUParticles3D).visible:
				ps.append(p)
				(p as GPUParticles3D).visible = false
		return func() -> void:
			for p: GPUParticles3D in ps:
				p.visible = true])
	list.append(["swamp_volcano_off", func() -> Callable:
		var nodes: Array = []
		for n: String in ["Swamp", "VolcanoLight", "VolcanoSmoke"]:
			var node := _scene.get_node_or_null(n) as Node3D
			if node != null and node.visible:
				nodes.append(node)
				node.visible = false
		return func() -> void:
			for node: Node3D in nodes:
				node.visible = true])
	list.append(["props_off", func() -> Callable:
		var nodes: Array = []
		for n: String in ["StoneRings", "OuterStoneRing", "PlacedCrystals"]:
			var node := _scene.get_node_or_null(n) as Node3D
			if node != null and node.visible:
				nodes.append(node)
				node.visible = false
		return func() -> void:
			for node: Node3D in nodes:
				node.visible = true])
	list.append(["terrabrush_process_off", func() -> Callable:
		return _disable_processing(_scene.get_node_or_null("TerraBrush"))])
	list.append(["sky3d_process_off", func() -> Callable:
		return _disable_processing(_scene.get_node_or_null("Sky3D"))])
	list.append(["scene_objects_off", func() -> Callable:
		# TerraBrush's PackedScenes objects (each a mesh, a body and a shape): taken out of the
		# tree entirely, so culling and physics stop seeing them too.
		var tb: Node = _scene.get_node_or_null("TerraBrush")
		var removed: Array = []
		if tb != null:
			for n: Node in tb.find_children("*", "", true, false):
				if String(n.name) == "Objects":
					removed.append([n, n.get_parent()])
			for pair: Array in removed:
				(pair[1] as Node).remove_child(pair[0])
		return func() -> void:
			for pair: Array in removed:
				(pair[1] as Node).add_child(pair[0])])
	list.append(["grass_35m", func() -> Callable:
		return _terrabrush_rebuild(35.0, 35, 1.0)])
	list.append(["grass_25m", func() -> Callable:
		return _terrabrush_rebuild(25.0, 25, 1.0)])
	list.append(["objects_x0.6", func() -> Callable:
		return _terrabrush_rebuild(-1.0, -1, 0.6)])
	list.append(["mesh_lod_x4", func() -> Callable:
		var before: float = root.mesh_lod_threshold
		root.mesh_lod_threshold = before * 4.0
		return func() -> void: root.mesh_lod_threshold = before])
	list.append(["aniso_2x_bias1", func() -> Callable:
		var a: int = root.anisotropic_filtering_level
		var b: float = root.texture_mipmap_bias
		root.anisotropic_filtering_level = Viewport.ANISOTROPY_2X
		root.texture_mipmap_bias = 1.0
		return func() -> void:
			root.anisotropic_filtering_level = a
			root.texture_mipmap_bias = b])
	list.append(["fsr2_0.67", func() -> Callable:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root.scaling_3d_scale = 0.67
		root.msaa_3d = Viewport.MSAA_DISABLED
		return func() -> void:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = 1.0
			root.msaa_3d = Viewport.MSAA_4X])
	list.append(["fsr1_0.77", func() -> Callable:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		root.scaling_3d_scale = 0.77
		return func() -> void:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = 1.0])
	return list


## Grass distance (and its grid rows) and/or a factor on every MultiMesh object's LOD
## distances, then TerraBrush rebuilt - what a view-distance option would do mid-match.
func _terrabrush_rebuild(grass: float, rows: int, objects: float) -> Callable:
	var tb: Node = _scene.get_node_or_null("TerraBrush")
	var saved: Array = []
	for f: Resource in tb.get("foliages"):
		var d: Resource = f.get("definition")
		saved.append([d, "maximumRenderDistance", d.get("maximumRenderDistance")])
		saved.append([d, "lodRowsPerLevel", d.get("lodRowsPerLevel")])
		if grass > 0.0:
			d.set("maximumRenderDistance", grass)
			d.set("lodRowsPerLevel", rows)
	for o: Resource in tb.get("objects"):
		for lod: Resource in o.get("definition").get("lodList"):
			saved.append([lod, "maxDistance", lod.get("maxDistance")])
			lod.set("maxDistance", float(lod.get("maxDistance")) * objects)
	var t0: int = Time.get_ticks_msec()
	tb.call("onUpdateTerrainSettings")
	print("PERF   rebuild took %d ms" % (Time.get_ticks_msec() - t0))
	return func() -> void:
		for entry: Array in saved:
			(entry[0] as Resource).set(entry[1], entry[2])
		tb.call("onUpdateTerrainSettings")


func _disable_processing(node: Node) -> Callable:
	if node == null:
		return func() -> void: pass
	var before: int = node.process_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED
	return func() -> void: node.process_mode = before


## TerraBrush builds its terrain, foliage and objects as children at runtime; which is which
## is told apart by class and name (see --dump for what is actually there).
func _hide_terrabrush(kind: String) -> Callable:
	var tb: Node = _scene.get_node_or_null("TerraBrush")
	var hidden: Array = []
	if tb == null:
		return func() -> void: pass
	for n: Node in tb.find_children("*", "", true, false):
		if not (n is Node3D) or not (n as Node3D).visible:
			continue
		var tag: String = (n.name + " " + n.get_class()).to_lower()
		var hit: bool = false
		match kind:
			"foliage":
				hit = tag.contains("foliage")
			"objects":
				hit = tag.contains("object") and not tag.contains("foliage")
			"terrain":
				hit = tag.contains("terrain") or tag.contains("clipmap") or tag.contains("heightmap")
		if hit:
			(n as Node3D).visible = false
			hidden.append(n)
	return func() -> void:
		for n: Node3D in hidden:
			if is_instance_valid(n):
				n.visible = true


func _point_camera(view: String) -> void:
	var spawners: Array = _scene.get("enemy_spawners")
	var crystal: Vector3 = (_scene.get("crystal_anchor") as Node3D).global_position
	var spawner: Vector3 = (spawners[0] as Node3D).global_position
	match view:
		"lane":
			# Where a player defending a lane stands: a third of the way out, looking at the spawner.
			_camera.global_position = crystal.lerp(spawner, 0.35) + Vector3.UP * 6.0
			_camera.look_at(spawner, Vector3.UP)
		"hub":
			# Behind the crystal, looking out across it and two lanes.
			var out: Vector3 = (spawner - crystal).normalized()
			_camera.global_position = crystal - out * 12.0 + Vector3.UP * 9.0
			_camera.look_at(crystal + out * 60.0, Vector3.UP)
		"top":
			# High over the middle, the whole map in view.
			_camera.global_position = crystal + Vector3(0, 120, 90)
			_camera.look_at(crystal, Vector3.UP)


func _measure() -> Dictionary:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var vp: RID = get_viewport().get_viewport_rid()
	var acc := {"gpu": 0.0, "rcpu": 0.0, "proc": 0.0, "phys": 0.0, "draws": 0.0, "prims": 0.0}
	var frames: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for i: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		acc["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		acc["rcpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		acc["proc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc["phys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		acc["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		acc["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n: float = float(MEASURE_FRAMES)
	for k: String in acc:
		acc[k] = float(acc[k]) / n
	acc["prims"] = float(acc["prims"]) / 1000.0
	var total: float = 0.0
	for f: float in frames:
		total += f
	frames.sort()
	acc["frame"] = total / n
	acc["p99"] = frames[int(frames.size() * 0.99)]
	acc["worst"] = frames[frames.size() - 1]
	return acc


func _print(view: String, case: String, m: Dictionary, base: Dictionary) -> void:
	print("PERF %-6s %-22s %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f %6.0f %7.0f" % [view, case,
		m["frame"], m["p99"], m["gpu"], float(base["gpu"]) - float(m["gpu"]), m["rcpu"], m["proc"], m["phys"], m["draws"], m["prims"]])


func _dump() -> void:
	var tb: Node = _scene.get_node_or_null("TerraBrush")
	if tb != null:
		var classes: Dictionary = {}
		for n: Node in tb.find_children("*", "", true, false):
			var key: String = "%s  %s" % [n.get_class(), String(n.name).rstrip("0123456789_")]
			var instances: int = 0
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				instances = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var entry: Array = classes.get(key, [0, 0, 0])
			entry[0] += 1
			entry[1] += instances
			if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				entry[2] += 1
			classes[key] = entry
		for key: String in classes:
			print("DUMP terrabrush %-60s nodes %5d  instances %8d  shadow-casters %5d" % [key, classes[key][0], classes[key][1], classes[key][2]])
	if tb != null:
		for f: Resource in tb.get("foliages"):
			var d: Resource = f.get("definition")
			print("DUMP foliage %-40s maxDist %5.1f  lodLevels %d  rows %d  cell %.2f  shadow %s" % [String(f.resource_path).get_file(), d.get("maximumRenderDistance"), d.get("lodLevels"), d.get("lodRowsPerLevel"), d.get("lodInitialCellWidth"), d.get("castShadow")])
		for o: Resource in tb.get("objects"):
			var d: Resource = o.get("definition")
			var dists: Array = []
			for lod: Resource in d.get("lodList"):
				dists.append(lod.get("maxDistance"))
			print("DUMP object %-48s strategy %d  lods %s  update every %.2fs / %.1fm" % [String(o.resource_path).get_file(), d.get("strategy"), dists, d.get("updateTimeFrequency"), d.get("updateDistanceThreshold")])
		print("DUMP terrain lodLevels %d rows %d cell %.2f  textureDetail %d" % [tb.get("lodLevels"), tb.get("lodRowsPerLevel"), tb.get("lodInitialCellWidth"), tb.get("textureDetail")])
	for l: Node in _scene.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		var rng: float = light.get("omni_range") if light is OmniLight3D else (light.get("spot_range") if light is SpotLight3D else 0.0)
		print("DUMP light %-40s %-18s energy %5.2f shadow %s range %6.1f" % [light.get_path(), light.get_class(), light.light_energy, light.shadow_enabled, rng])
	if _sun != null:
		print("DUMP sun shadow mode %d  max distance %.0f  splits %.2f %.2f %.2f  blend %s" % [_sun.directional_shadow_mode, _sun.directional_shadow_max_distance, _sun.directional_shadow_split_1, _sun.directional_shadow_split_2, _sun.directional_shadow_split_3, _sun.directional_shadow_blend_splits])
	var particles: Array = _scene.find_children("*", "GPUParticles3D", true, false)
	var total: int = 0
	for p: GPUParticles3D in particles:
		total += p.amount
	print("DUMP particles systems %d  total amount %d" % [particles.size(), total])
	if _env != null and _env.sky != null:
		print("DUMP sky process mode %d  radiance size %d" % [_env.sky.process_mode, _env.sky.radiance_size])
	print("DUMP directional shadow size %s  soft %s  positional atlas %s  soft %s" % [
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
		ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size"),
		ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality")])
	var meshes: int = 0
	var shadow_meshes: int = 0
	for m: Node in _scene.find_children("*", "GeometryInstance3D", true, false):
		meshes += 1
		if (m as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_meshes += 1
	print("DUMP geometry instances %d  shadow casters %d  nodes %d" % [meshes, shadow_meshes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
