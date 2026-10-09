extends Node3D
## Screenshots Rain of Ember's firestorm under the game's own sky, wide and close up, at
## several times of day.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/fire_rain_shot.tscn -- <folder> [--glow]
##
## One PNG per view and hour lands in <folder>. The wide view shows the drops falling in
## against the sky; the close one sits at the edge of the zone, low, where the sparks rising
## off the ground are big enough to judge.
##
## Not part of validate_godot.ps1, for the same reason as vfx_showcase: it proves nothing
## automatically, it just makes the effect look-at-able.

const ZONE_RADIUS := 5.0
const HOURS: Array[float] = [12.0, 17.5, 20.0, 23.0]
## Long enough for the storm to roll in and the first sparks to have climbed.
const SETTLE_SECONDS := 1.6
const VIEWS := {
	"wide": [Vector3(0.0, 4.5, 15.0), Vector3(0.0, 3.0, 0.0)],
	"close": [Vector3(1.5, 1.3, 7.5), Vector3(0.0, 1.6, 0.0)],
}

var _sky: Sky3D
var _camera: Camera3D


func _ready() -> void:
	_sky = Sky3D.new()
	add_child(_sky)
	if _sky.tod:
		_sky.tod.game_time_enabled = false
	if OS.get_cmdline_user_args().has("--glow") and _sky.environment != null:
		GraphicsSettings.configure_glow(_sky.environment, true)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.22, 0.26, 0.20)
	ground.material_override = ground_material
	add_child(ground)

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = "user://fire_rain_shot"
	if not args.is_empty() and not args[0].begins_with("--"):
		folder = args[0]
	DirAccess.make_dir_recursive_absolute(folder)

	for hour: float in HOURS:
		if _sky.tod:
			_sky.tod.current_time = hour
		# A fresh storm per hour, so every shot catches it at the same point in its life.
		var zone := DoTZone.new()
		zone.setup("fire_rain", ZONE_RADIUS, 0.0, 600.0)
		add_child(zone)
		for view: String in VIEWS:
			_camera.position = VIEWS[view][0]
			_camera.look_at(VIEWS[view][1], Vector3.UP)
			await get_tree().create_timer(SETTLE_SECONDS).timeout
			await RenderingServer.frame_post_draw
			var file: String = "%s_%05.2f.png" % [view, hour]
			get_viewport().get_texture().get_image().save_png(folder.path_join(file))
			print("FIRE_RAIN saved %s" % file)
		zone.queue_free()
	get_tree().quit()
