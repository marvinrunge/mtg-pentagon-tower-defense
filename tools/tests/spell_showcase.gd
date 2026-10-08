extends "res://tools/tests/vfx_stage.gd"
## Every spell cast for real on the light VfxStage and photographed at a few moments after
## its release, one sheet per colour - the "look at all 25 as a set" view
## docs/SPELL_VFX_PLAN.md asks for.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/spell_showcase.tscn -- <out_prefix> [white,red] [rank5] [--glow]
## Writes <out_prefix>_<colour>.png: one row per spell, one column per moment. The colour
## list narrows the run; without it all five sheets are written.
##
## A real Player casts through `_run_spell_effect`, the server's own entry point, against
## real enemies, so whatever the game builds for a spell is what is photographed. Each tile
## is its own cast on a fresh player and a fresh pack: a software renderer is too slow to
## catch several moments of one cast in sequence, and a leftover from the last spell would
## be photographed as part of the next.

const TILE := Vector2i(480, 270)
## Seconds after the release, unless a spell names its own.
const MOMENTS: Array[float] = [0.12, 0.45, 1.3]
## Where the crosshair meets the ground, in front of the caster. Every aimed spell lands here.
const AIM_DISTANCE := 12.0
const COLOURS: Array[String] = ["white", "blue", "black", "red", "green"]

## Moments of their own, for spells whose interesting part is later than the default's.
const SPELL_MOMENTS: Dictionary = {
	"red_1": [0.25, 0.6, 1.4],
	"red_5": [0.3, 0.62, 1.1],
	"green_1": [0.1, 0.4, 1.1],
	"blue_4": [0.2, 0.8, 2.0],
	"black_4": [0.2, 0.8, 2.0],
	"red_3": [0.4, 1.2, 2.5],
	"green_3": [0.4, 1.2, 2.5],
	"blue_3": [0.3, 1.0, 2.2],
}

var _player: Player = null
var _camera: Camera3D = null
var _caption: Label = null
var _rank: int = 1


func _ready() -> void:
	build_stage()
	_start.call_deferred()


func _start() -> void:
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	await _shoot_all()


func _shoot_all() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var prefix: String = "spell_showcase"
	if not args.is_empty() and not args[0].begins_with("--"):
		prefix = args[0]
	var colours: Array[String] = COLOURS.duplicate()
	for arg: String in args:
		if arg.begins_with("rank"):
			_rank = clampi(int(arg.substr(4)), 1, GameSettings.spell_max_rank)
		elif arg.split(",")[0] in COLOURS:
			colours.clear()
			for colour: String in arg.split(","):
				colours.append(colour)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	for colour: String in colours:
		var sheet := Image.create(TILE.x * MOMENTS.size(), TILE.y * SpellDatabase.SPELLS_PER_COLOR, false, Image.FORMAT_RGB8)
		for row: int in range(SpellDatabase.SPELLS_PER_COLOR):
			var spell_id: String = "%s_%d" % [colour, row + 1]
			var moments: Array = SPELL_MOMENTS.get(spell_id, MOMENTS)
			for column: int in range(moments.size()):
				var frame: Image = await _shoot(spell_id, float(moments[column]))
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i(column * TILE.x, row * TILE.y))
		var path: String = "%s_%s.png" % [prefix, colour]
		sheet.save_png(path)
		print("SPELL SHEET: %s" % path)
	get_tree().quit()


## One cast, one photograph `after` seconds past its release.
func _shoot(spell_id: String, after: float) -> Image:
	var keep: Array[Node] = get_children()
	_spawn_player(spell_id)
	await _set_the_scene(spell_id)
	_frame_camera(spell_id)
	_camera.current = true
	await _cast(spell_id)
	await get_tree().create_timer(after).timeout
	_caption.text = "%s  %s  +%.2fs" % [spell_id.to_upper(), String(SpellDatabase.SPELLS[spell_id]["name"]), after]
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	print("  %s +%.2fs" % [spell_id, after])
	_clear(keep)
	return frame


func _spawn_player(spell_id: String) -> void:
	var packed: PackedScene = load("res://scenes/misc/player.tscn") as PackedScene
	_player = packed.instantiate() as Player
	_player.set_meta("is_local", true)
	add_child(_player)
	_player.global_position = STAGE
	_player.spell_ranks[spell_id] = _rank
	# The crosshair on the ground AIM_DISTANCE ahead, so every aimed spell lands in frame.
	var drop: float = _player.aim_origin().y - STAGE.y
	_player.camera_pivot.rotation.x = -atan2(drop, AIM_DISTANCE)


## What each spell needs in front of it to show what it does.
func _set_the_scene(spell_id: String) -> void:
	match spell_id:
		"black_5":
			# Corpses to raise, made the way the game makes them.
			for offset: Vector3 in [Vector3(2.0, 0.0, -3.0), Vector3(-2.0, 0.0, -4.5), Vector3(0.5, 0.0, -7.0)]:
				var corpse: EnemyBase = _enemy(offset)
				await get_tree().physics_frame
				corpse.die()
			await get_tree().create_timer(1.2).timeout
		"white_1", "white_3", "white_5", "green_2", "green_5", "blue_5", "black_4", "green_3":
			pass
		_:
			for offset: Vector3 in [Vector3(-2.0, 0.0, -6.0), Vector3(1.5, 0.0, -7.5), Vector3(3.0, 0.0, -4.5),
					Vector3(-3.5, 0.0, -9.0), Vector3(0.5, 0.0, -11.0)]:
				_enemy(offset)
			if spell_id in ["black_2", "black_3"]:
				_enemy(_under_crosshair(11.0))
			for _i: int in range(6):
				await get_tree().physics_frame


func _cast(spell_id: String) -> void:
	match spell_id:
		"red_2":
			SpellEffects.cast_red_fire_dash(_player)
			await get_tree().create_timer(GameSettings.spell_red_dash_duration).timeout
		"green_1":
			SpellEffects.cast_green_titanic_leap(_player)
			await get_tree().create_timer(GameSettings.spell_green_leap_duration).timeout
	_player._run_spell_effect(spell_id, 1.0)


func _frame_camera(spell_id: String) -> void:
	var at := STAGE + Vector3(0.0, 0.8, -5.5)
	var from := STAGE + Vector3(8.0, 5.5, 3.0)
	match spell_id:
		"white_1", "white_3", "white_5", "green_2", "green_5":
			# Self buffs: close on the caster.
			at = STAGE + Vector3(0.0, 1.1, 0.0)
			from = STAGE + Vector3(3.2, 2.4, 3.6)
		"red_5", "red_1":
			from = STAGE + Vector3(11.0, 6.0, 0.0)
			at = STAGE + Vector3(0.0, 2.5, -9.0)
	_camera.global_position = from
	_camera.look_at(at)


func _enemy(offset: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	get_node("Enemies").add_child(enemy)
	enemy.global_position = ground_at(Vector2(STAGE.x + offset.x, STAGE.z + offset.z))
	return enemy


## The ground under the crosshair, `distance` metres along it - where an enemy has to stand
## to be the one Kill and Contagion pick.
func _under_crosshair(distance: float) -> Vector3:
	var spot: Vector3 = _player.aim_origin() + _player.aim_direction() * distance
	spot.y = STAGE.y
	return spot - STAGE


## Everything the cast left behind goes, so the next tile starts from the bare stage.
func _clear(keep: Array[Node]) -> void:
	for holder: String in ["Enemies", "Effects"]:
		for child: Node in get_node(holder).get_children():
			child.free()
	for child: Node in get_children():
		if not keep.has(child):
			child.free()
	for p: Projectile in ProjectilePool.pool:
		if p.active and p.has_method("deactivate"):
			p.deactivate()
	_player = null
