extends Node
## Persisted rendering-quality options, so lower-end machines (e.g. integrated
## GPUs) can turn cost down until the game runs smoothly. Separate from
## GameSettings, which holds unrelated, unpersisted gameplay-balance values.
##
## Every option saves the moment it changes - it used to save only on a preset, the FPS
## toggle or a renderer pick, so a hand-set render scale or shadow switch was forgotten on
## the next launch. The file is shared with UserSettings; see SettingsFile.

## An option moved. The HUD follows `show_fps` off this; nothing else needs to.
signal changed(key: StringName)

const SettingsFile := preload("res://scripts/settings_file.gd")
## Read by the engine BEFORE anything in the project runs, which is the only way the
## renderer can change: project.godot names this file in
## `application/config/project_settings_override`, and the engine merges it over the project
## settings at boot. Nothing else reads it, and nothing else should be put in it.
const OVERRIDE_PATH: String = "user://override.cfg"
## The rendering-device driver on Windows, which the Mobile renderer needs to be Vulkan - see
## _save for why.
const MOBILE_DRIVER_KEY := "rendering_device/driver.windows"
const SECTION := "graphics"

enum Preset { LOW, MEDIUM, HIGH, CUSTOM }
## How dense every particle effect is; see GameSettings.graphics_particle_quality_scale.
enum ParticleQuality { LOW, MEDIUM, HIGH, ULTRA }

## The three rendering methods, in the order the menus list them.
const RENDERER_METHODS: Array[String] = ["forward_plus", "mobile", "gl_compatibility"]

var render_scale: float = 1.0
var shadows_enabled: bool = true
var msaa_level: int = 0 # 0 = Off, 1 = MSAA 2x, 2 = MSAA 4x
var glow_enabled: bool = true
var terrain_parallax: bool = true
var vsync_enabled: bool = true
var show_fps: bool = false
var particle_quality: int = ParticleQuality.HIGH
var preset: int = Preset.HIGH

## The renderer the engine actually booted with this run (fixed until restart).
var active_rendering_method: String = "forward_plus"
## A renderer choice saved for next launch, if it differs from active_rendering_method.
var pending_rendering_method: String = ""
var restart_required: bool = false

var _save_queued: bool = false


func _ready() -> void:
	active_rendering_method = _booted_rendering_method()
	_load()
	apply_render_scale(render_scale)
	apply_msaa(msaa_level)
	apply_vsync(vsync_enabled)
	apply_terrain_parallax(terrain_parallax)
	# Every particle system that enters the tree is sized to the setting as it arrives,
	# which covers the effects built in code and the ones in scenes alike, without each of
	# them having to ask.
	get_tree().node_added.connect(_on_node_added)
	# shadows/glow touch scene nodes (the sun light, the world environment)
	# that don't exist yet at autoload _ready() - the main scene applies those
	# itself once its tree is up, via apply_scene_dependent().


## What the engine is really running. Asked of the RenderingServer rather than read back
## from the project settings: a command-line `--rendering-method` or a fallback the engine
## took on a machine that could not start the chosen one both win over the setting, and the
## menu has to describe the renderer on screen, not the one that was asked for.
func _booted_rendering_method() -> String:
	var method: String = ""
	if RenderingServer.has_method("get_current_rendering_method"):
		method = String(RenderingServer.call("get_current_rendering_method"))
	if method == "":
		method = String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	return method


## Called by the main scene once it's ready, so shadow/glow state reaches the
## actual light and environment nodes that only exist once that scene is live.
func apply_scene_dependent() -> void:
	apply_shadows(shadows_enabled)
	apply_glow(glow_enabled)


func apply_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	get_tree().root.scaling_3d_scale = render_scale
	_changed(&"render_scale")


## The sun and the moon, wherever they are.
##
## They used to be found through a `sun_light` group that nothing has joined since the map
## moved onto Sky3D, so the switch had nothing to act on and the shadows stayed. And turning
## them off on the lights alone would not hold either: Sky3D's SkyDome switches a light's
## shadow back on whenever that light has any energy, i.e. on the next update of a daytime
## sun. So Sky3D is told as well, through the one flag it was patched to respect.
func apply_shadows(enabled: bool) -> void:
	shadows_enabled = enabled
	var scene: Node = get_tree().current_scene
	if scene != null:
		for world_env: Node in scene.find_children("*", "WorldEnvironment", true, false):
			var dome: Variant = world_env.get("sky")
			if dome is Node and "shadows_allowed" in dome:
				dome.shadows_allowed = enabled
		for light: Node in scene.find_children("*", "DirectionalLight3D", true, false):
			var directional := light as DirectionalLight3D
			# A light Sky3D has put out for the night stays without a shadow either way.
			directional.shadow_enabled = enabled and directional.light_energy > 0.0
	for light: Light3D in get_tree().get_nodes_in_group("sun_light"):
		light.shadow_enabled = enabled
	_changed(&"shadows_enabled")


func apply_msaa(level: int) -> void:
	msaa_level = level
	match level:
		1:
			get_tree().root.msaa_3d = Viewport.MSAA_2X
		2:
			get_tree().root.msaa_3d = Viewport.MSAA_4X
		_:
			get_tree().root.msaa_3d = Viewport.MSAA_DISABLED
	_changed(&"msaa_level")


## Bloom, on the environment the map is actually lit by.
##
## Found by type rather than through the `world_environment` group, which - like the sun's
## group - nothing joined after the move to Sky3D. The environment also had no glow set up
## at all, so switching `glow_enabled` alone would turn on the engine's defaults, which bloom
## the whole daytime sky. The numbers come from GameSettings instead: only what is brighter
## than the HDR threshold blooms, which is the spells' hot cores and the sun, not the sky.
func apply_glow(enabled: bool) -> void:
	glow_enabled = enabled
	var scene: Node = get_tree().current_scene
	var environments: Array[Environment] = []
	if scene != null:
		for world_env: Node in scene.find_children("*", "WorldEnvironment", true, false):
			var environment: Environment = (world_env as WorldEnvironment).environment
			if environment != null and not environments.has(environment):
				environments.append(environment)
	for world_env: WorldEnvironment in get_tree().get_nodes_in_group("world_environment"):
		if world_env.environment != null and not environments.has(world_env.environment):
			environments.append(world_env.environment)
	for environment: Environment in environments:
		configure_glow(environment, enabled)
	_changed(&"glow_enabled")


## The game's bloom on one environment, and nothing else - no state kept, nothing saved.
## Split out so a test scene (tools/tests/vfx_showcase.gd) can light its own sky exactly as
## the map is lit without writing the player's settings file on the way.
func configure_glow(environment: Environment, enabled: bool) -> void:
	environment.glow_enabled = enabled
	if not enabled:
		return
	environment.glow_intensity = GameSettings.graphics_glow_intensity
	environment.glow_strength = GameSettings.graphics_glow_strength
	environment.glow_bloom = GameSettings.graphics_glow_bloom
	environment.glow_hdr_threshold = GameSettings.graphics_glow_hdr_threshold
	environment.glow_hdr_scale = GameSettings.graphics_glow_hdr_scale
	environment.glow_blend_mode = GameSettings.graphics_glow_blend_mode


## Relief on the ground close to the camera - stones that stand out of the mud and hide what
## is behind them as the view moves. A patch to TerraBrush's terrain shader, steered through
## global shader parameters (project.godot [shader_globals]), so this needs no handle on the
## terrain at all and takes effect the same frame, scene loaded or not.
func apply_terrain_parallax(enabled: bool) -> void:
	terrain_parallax = enabled
	RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 1.0 if enabled else 0.0)
	RenderingServer.global_shader_parameter_set(&"terrain_parallax_depth", GameSettings.graphics_terrain_parallax_depth)
	RenderingServer.global_shader_parameter_set(&"terrain_parallax_range", GameSettings.graphics_terrain_parallax_range)
	_changed(&"terrain_parallax")


func apply_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	_changed(&"vsync_enabled")


## Thins out or thickens every particle effect in the game.
##
## Applied centrally rather than by each effect: there are dozens of them, built in code and
## in scenes, and a setting each one had to remember to read would be missed by the next one
## written. Systems already in the tree are resized on the spot.
func apply_particle_quality(level: int) -> void:
	particle_quality = clampi(level, ParticleQuality.LOW, ParticleQuality.ULTRA)
	for node: Node in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		_scale_particles(node as GPUParticles3D)
	_changed(&"particle_quality")


func _on_node_added(node: Node) -> void:
	if node is GPUParticles3D:
		_scale_particles(node as GPUParticles3D)


## Up to High, `amount_ratio` emits a share of the authored count, which costs nothing and
## does not restart the system. Ultra has to raise `amount` itself, as the ratio stops at 1.
##
## The authored count is remembered on the node, so applying this again - a new setting, the
## node moved to another parent - always scales from it and never compounds. A script that
## changed `amount` since is taken at its word.
func _scale_particles(particles: GPUParticles3D) -> void:
	var base: int = particles.amount
	if particles.has_meta(&"pq_base") and particles.amount == int(particles.get_meta(&"pq_set")):
		base = int(particles.get_meta(&"pq_base"))
	var scales: Array[float] = GameSettings.graphics_particle_quality_scale
	var factor: float = scales[clampi(particle_quality, 0, scales.size() - 1)]
	var target: int = base
	var ratio: float = 1.0
	if factor > 1.0:
		target = int(ceil(float(base) * factor))
	else:
		ratio = maxf(factor, minf(1.0, float(GameSettings.graphics_particle_min_amount) / float(maxi(base, 1))))
	if particles.amount != target:
		particles.amount = target
	particles.amount_ratio = ratio
	particles.set_meta(&"pq_base", base)
	particles.set_meta(&"pq_set", target)


## Just a persisted flag - the HUD owns the actual FPS counter label since it
## lives in the HUD scene, not something reachable via a scene-wide group.
func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	_changed(&"show_fps")


## Bundles the above into one-click tiers. LOW also switches the renderer to
## Compatibility (OpenGL-class, far lighter than Forward+) - that's the single
## biggest lever for a machine with only an integrated GPU, but it needs a
## restart to take effect.
func apply_preset(p: int) -> void:
	preset = p
	match p:
		Preset.LOW:
			apply_render_scale(0.6)
			apply_shadows(false)
			apply_msaa(0)
			apply_glow(false)
			apply_terrain_parallax(false)
			apply_particle_quality(ParticleQuality.LOW)
			set_pending_rendering_method("gl_compatibility")
		Preset.MEDIUM:
			apply_render_scale(0.8)
			apply_shadows(true)
			apply_msaa(1)
			apply_glow(true)
			apply_terrain_parallax(false)
			apply_particle_quality(ParticleQuality.MEDIUM)
			set_pending_rendering_method("mobile")
		Preset.HIGH:
			apply_render_scale(1.0)
			apply_shadows(true)
			apply_msaa(2)
			apply_glow(true)
			apply_terrain_parallax(true)
			apply_particle_quality(ParticleQuality.HIGH)
			set_pending_rendering_method("forward_plus")
		Preset.CUSTOM:
			pass
	_changed(&"preset")


## The player touched one option by hand, so no preset describes the result any more.
func mark_custom() -> void:
	if preset == Preset.CUSTOM:
		return
	preset = Preset.CUSTOM
	_changed(&"preset")


func set_pending_rendering_method(method: String) -> void:
	pending_rendering_method = method
	restart_required = method != active_rendering_method
	_changed(&"rendering_method")


## The renderer the menu should show as chosen: the one waiting for a restart if there is
## one, otherwise the one running.
func chosen_rendering_method() -> String:
	return pending_rendering_method if pending_rendering_method != "" else active_rendering_method


## Saves, then relaunches the game with the same arguments it was started with.
##
## It used to quit and leave the starting-again to the player, which read as a crash. Any
## renderer flag on the command line is dropped from the relaunch: it outranks the override
## file, so keeping it would bring the game straight back up on the renderer being replaced.
func restart_to_apply() -> void:
	_save()
	var args: PackedStringArray = PackedStringArray()
	var skip_next: bool = false
	for arg: String in OS.get_cmdline_args():
		if skip_next:
			skip_next = false
			continue
		if arg == "--rendering-method" or arg == "--rendering-driver":
			skip_next = true
			continue
		if arg.begins_with("--rendering-method=") or arg.begins_with("--rendering-driver="):
			continue
		args.append(arg)
	OS.set_restart_on_exit(true, args)
	get_tree().quit()


## Kept for anything still calling the old name.
func quit_to_apply_restart() -> void:
	restart_to_apply()


func _changed(key: StringName) -> void:
	changed.emit(key)
	_queue_save()


## A slider reports every step it is dragged through; the file is written once it settles.
func _queue_save() -> void:
	if _save_queued or not is_inside_tree():
		return
	_save_queued = true
	get_tree().create_timer(0.4).timeout.connect(_save)


func _save() -> void:
	_save_queued = false
	var method_to_persist: String = chosen_rendering_method()
	SettingsFile.write_section(SECTION, {
		"render_scale": render_scale,
		"shadows_enabled": shadows_enabled,
		"msaa_level": msaa_level,
		"glow_enabled": glow_enabled,
		"terrain_parallax": terrain_parallax,
		"vsync_enabled": vsync_enabled,
		"show_fps": show_fps,
		"particle_quality": particle_quality,
		"preset": preset,
		"rendering_method": method_to_persist,
	})

	# The renderer has to be readable by the engine before any autoload runs,
	# so it also goes in its own override file - the engine merges it over
	# project.godot at boot (see OVERRIDE_PATH).
	var override_cfg := ConfigFile.new()
	override_cfg.load(OVERRIDE_PATH) # ignore error - fine if it doesn't exist yet
	override_cfg.set_value("rendering", "renderer/rendering_method", method_to_persist)
	# The Mobile renderer runs on Vulkan, not on the project's D3D12. On D3D12 it cannot build
	# TerraBrush's terrain shader - CreateGraphicsPipelineState fails with E_OUTOFMEMORY
	# (0x8007000e) and the whole terrain is simply not drawn. Forward+ and Compatibility keep
	# the project's own drivers, and a machine with no Vulkan falls back to D3D12 by itself
	# (rendering/rendering_device/fallback_to_d3d12).
	if method_to_persist == "mobile":
		override_cfg.set_value("rendering", MOBILE_DRIVER_KEY, "vulkan")
	elif override_cfg.has_section_key("rendering", MOBILE_DRIVER_KEY):
		override_cfg.erase_section_key("rendering", MOBILE_DRIVER_KEY)
	override_cfg.save(OVERRIDE_PATH)


func _load() -> void:
	var cfg: ConfigFile = SettingsFile.load_file()
	if not cfg.has_section(SECTION):
		return
	render_scale = float(cfg.get_value(SECTION, "render_scale", render_scale))
	shadows_enabled = bool(cfg.get_value(SECTION, "shadows_enabled", shadows_enabled))
	msaa_level = int(cfg.get_value(SECTION, "msaa_level", msaa_level))
	glow_enabled = bool(cfg.get_value(SECTION, "glow_enabled", glow_enabled))
	terrain_parallax = bool(cfg.get_value(SECTION, "terrain_parallax", terrain_parallax))
	vsync_enabled = bool(cfg.get_value(SECTION, "vsync_enabled", vsync_enabled))
	show_fps = bool(cfg.get_value(SECTION, "show_fps", show_fps))
	particle_quality = clampi(int(cfg.get_value(SECTION, "particle_quality", particle_quality)),
		ParticleQuality.LOW, ParticleQuality.ULTRA)
	preset = int(cfg.get_value(SECTION, "preset", preset))
	var saved_method: String = String(cfg.get_value(SECTION, "rendering_method", active_rendering_method))
	if saved_method != active_rendering_method and RENDERER_METHODS.has(saved_method):
		pending_rendering_method = saved_method
		restart_required = true
