extends Node
## Regression test: does the bottom HUD strip fit the window?
##
## Run with:  godot --headless --path . res://tools/tests/hud_layout.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing each collision.
##
## The health bar, the XP bar, the hotbar and the minimap were each pinned in hud.tscn with
## fixed pixel offsets that only fit each other on a wide window. The XP bar's left edge is
## `width / 2 - 350`, so it ran into the health bar below 1260px - and the project's own
## default window is 1152x648. The hotbar reached under the minimap below 1160px. Both were
## overlapping out of the box, on the size the game actually ships in.
##
## Checked by arithmetic at a spread of window sizes rather than by looking at one, which is
## the whole reason it went unnoticed: it looks fine on a big monitor. HUD.bottom_hud_rects()
## is a pure function of the window size for exactly this - no frame has to be rendered and
## no anchors have to resolve, so every size below is asked in the same millisecond.

## Real sizes, not round numbers: 1152x648 is Godot's default window and what the project
## runs in, 1280x720 is the size the .tscn's offsets were authored against, 1024x600 is a
## small laptop, 800x600 is about as small as the game could be asked to run, and the last
## two are an ultrawide and a tall/narrow window - the two shapes that break a layout tuned
## on 16:9.
const SIZES: Array[Vector2] = [
	Vector2(1920, 1080),
	Vector2(1280, 720),
	Vector2(1152, 648),
	Vector2(1024, 600),
	Vector2(800, 600),
	Vector2(2560, 1080),
	Vector2(900, 900),
]

## The minimap is the player's own setting, and a big one is the case most likely to collide.
## Both ends of its slider are checked, because the cap that keeps it off the rest of the HUD
## only engages at the top end.
const MINIMAP_SIDES: Array[float] = [100.0, 200.0, 400.0]

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 60:
		return
	_done = true
	_run()
	get_tree().quit()


func _run() -> void:
	var hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if hud == null:
		print("TEST RESULT: FAIL (no HUD in the scene)")
		return

	for minimap_side: float in MINIMAP_SIDES:
		hud._minimap_preferred_side = minimap_side
		for size: Vector2 in SIZES:
			_check_size(hud, size, minimap_side)

	if _failures.is_empty():
		print("TEST RESULT: PASS (%d sizes x %d minimap sizes)" % [SIZES.size(), MINIMAP_SIDES.size()])
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)


func _check_size(hud: Node, size: Vector2, minimap_side: float) -> void:
	var plan: Dictionary = hud.bottom_hud_rects(size)
	var label: String = "%dx%d minimap=%d" % [size.x, size.y, minimap_side]

	# Nothing in the strip may touch anything else in it. The minimap is included: it is the
	# element the hotbar reached under, and it is the one whose size the player controls.
	var names: Array[String] = ["health", "xp", "hotbar", "minimap"]
	for first: int in range(names.size()):
		for second: int in range(first + 1, names.size()):
			var a: Rect2 = plan[names[first]]
			var b: Rect2 = plan[names[second]]
			if a.intersects(b):
				_failures.append("%s: %s overlaps %s (%s vs %s)" % [
					label, names[first], names[second], a, b])

	# ...and nothing may hang off the window either.
	var screen := Rect2(Vector2.ZERO, size)
	for key: String in names:
		var rect: Rect2 = plan[key]
		if not screen.encloses(rect):
			_failures.append("%s: %s falls outside the window (%s)" % [label, key, rect])

	# A bar squeezed to nothing is technically not overlapping anything. Both bars have to
	# stay wide enough to read, and the hotbar's slots big enough to see the icon on.
	if plan["xp"].size.x < 100.0:
		_failures.append("%s: XP bar squeezed to %.0fpx" % [label, plan["xp"].size.x])
	if plan["health"].size.x < 100.0:
		_failures.append("%s: health bar squeezed to %.0fpx" % [label, plan["health"].size.x])
	if plan["slot"] < 30.0:
		_failures.append("%s: hotbar slots squeezed to %.0fpx" % [label, plan["slot"]])

	# All three bars are one readout language, so they are one height. The crystal's bar was
	# authored 10px thinner than the other two and read as an unrelated widget because of it.
	if not is_equal_approx(plan["health"].size.y, plan["xp"].size.y):
		_failures.append("%s: health bar %.0fpx tall, XP bar %.0fpx" % [
			label, plan["health"].size.y, plan["xp"].size.y])

	print("  ok   %-22s scale=%.2f xp=%.0fpx slot=%.0fpx" % [
		label, plan["scale"], plan["xp"].size.x, plan["slot"]])
