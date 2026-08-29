extends Node
## Persisted rendering-quality options, so lower-end machines (e.g. integrated
## GPUs) can turn cost down until the game runs smoothly. Separate from
## GameSettings, which holds unrelated, unpersisted gameplay-balance values.

const CONFIG_PATH: String = "user://graphics_settings.cfg"
const OVERRIDE_PATH: String = "user://override.cfg"

enum Preset { LOW, MEDIUM, HIGH, CUSTOM }

var render_scale: float = 1.0
var shadows_enabled: bool = true
var msaa_level: int = 0 # 0 = Off, 1 = MSAA 2x, 2 = MSAA 4x
var glow_enabled: bool = true
var vsync_enabled: bool = true
var show_fps: bool = false
var preset: int = Preset.HIGH

## The renderer the engine actually booted with this run (fixed until restart).
var active_rendering_method: String = "forward_plus"
## A renderer choice saved for next launch, if it differs from active_rendering_method.
var pending_rendering_method: String = ""
var restart_required: bool = false


func _ready() -> void:
	active_rendering_method = String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	_load()
	apply_render_scale(render_scale)
	apply_msaa(msaa_level)
	apply_vsync(vsync_enabled)
	# shadows/glow touch scene nodes (the sun light, the world environment)
	# that don't exist yet at autoload _ready() - the main scene applies those
	# itself once its tree is up, via apply_scene_dependent().


## Called by the main scene once it's ready, so shadow/glow state reaches the
## actual light and environment nodes that only exist once that scene is live.
func apply_scene_dependent() -> void:
	apply_shadows(shadows_enabled)
	apply_glow(glow_enabled)


func apply_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	get_tree().root.scaling_3d_scale = render_scale


func apply_shadows(enabled: bool) -> void:
	shadows_enabled = enabled
	for light: Light3D in get_tree().get_nodes_in_group("sun_light"):
		light.shadow_enabled = enabled


func apply_msaa(level: int) -> void:
	msaa_level = level
	match level:
		1:
			get_tree().root.msaa_3d = Viewport.MSAA_2X
		2:
			get_tree().root.msaa_3d = Viewport.MSAA_4X
		_:
			get_tree().root.msaa_3d = Viewport.MSAA_DISABLED


func apply_glow(enabled: bool) -> void:
	glow_enabled = enabled
	for world_env: WorldEnvironment in get_tree().get_nodes_in_group("world_environment"):
		if world_env.environment:
			world_env.environment.glow_enabled = enabled


func apply_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


## Just a persisted flag - the HUD owns the actual FPS counter label since it
## lives in the HUD scene, not something reachable via a scene-wide group.
func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	_save()


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
			set_pending_rendering_method("gl_compatibility")
		Preset.MEDIUM:
			apply_render_scale(0.8)
			apply_shadows(true)
			apply_msaa(1)
			apply_glow(true)
			set_pending_rendering_method("mobile")
		Preset.HIGH:
			apply_render_scale(1.0)
			apply_shadows(true)
			apply_msaa(2)
			apply_glow(true)
			set_pending_rendering_method("forward_plus")
		Preset.CUSTOM:
			pass
	_save()


func set_pending_rendering_method(method: String) -> void:
	pending_rendering_method = method
	restart_required = method != active_rendering_method
	_save()


func quit_to_apply_restart() -> void:
	_save()
	get_tree().quit()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "shadows_enabled", shadows_enabled)
	cfg.set_value("graphics", "msaa_level", msaa_level)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "preset", preset)
	var method_to_persist: String = pending_rendering_method if pending_rendering_method != "" else active_rendering_method
	cfg.set_value("graphics", "rendering_method", method_to_persist)
	cfg.save(CONFIG_PATH)

	# The renderer has to be readable by the engine before any autoload runs,
	# so it also goes in its own override file - Godot merges this over
	# project.godot automatically at boot.
	var override_cfg := ConfigFile.new()
	override_cfg.load(OVERRIDE_PATH) # ignore error - fine if it doesn't exist yet
	override_cfg.set_value("rendering", "renderer/rendering_method", method_to_persist)
	override_cfg.save(OVERRIDE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	render_scale = cfg.get_value("graphics", "render_scale", render_scale)
	shadows_enabled = cfg.get_value("graphics", "shadows_enabled", shadows_enabled)
	msaa_level = cfg.get_value("graphics", "msaa_level", msaa_level)
	glow_enabled = cfg.get_value("graphics", "glow_enabled", glow_enabled)
	vsync_enabled = cfg.get_value("graphics", "vsync_enabled", vsync_enabled)
	show_fps = cfg.get_value("graphics", "show_fps", show_fps)
	preset = cfg.get_value("graphics", "preset", preset)
	var saved_method: String = cfg.get_value("graphics", "rendering_method", active_rendering_method)
	if saved_method != active_rendering_method:
		pending_rendering_method = saved_method
		restart_required = true
