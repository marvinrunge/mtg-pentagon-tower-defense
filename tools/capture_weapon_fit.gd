extends SceneTree
## Captures a weapon you have adjusted by hand in the editor, so the adjustment survives
## the next rebuild.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/capture_weapon_fit.gd
##
## The workflow this exists for:
##
##   1. open e.g. scenes/ranged/elf_ranged.tscn, drag the Weapon node's gizmo, save
##   2. run this
##   3. every future rebuild reproduces exactly what you dragged
##
## Step 3 is the point. A rebuild regenerates those .tscn files from scratch, so an edit
## that lives only in the scene is an edit that disappears the next time anything is
## rebuilt - which is exactly how a set of hand-tuned weapon rotations was lost once
## already. This reads the transform back out of the scene, works out the difference from
## what the builder would have produced on its own, and writes THAT difference to
## CharacterBuilder.WEAPON_FIT_PATH, where the builder picks it up.
##
## Safe to run repeatedly and safe to run when nothing has been adjusted: a weapon still
## sitting where the builder put it captures an identity fit, which changes nothing.
##
## Deadlocks if a Godot editor already has the project open (project lock) - save and
## close the scene first.

const CharacterBuilder = preload("res://tools/character_builder.gd")
const WeaponFitPass = preload("res://tools/weapon_fit_pass.gd")

## Below this, a difference is the arithmetic disagreeing with itself rather than a
## deliberate nudge, and recording it would add noise to the file for nothing.
const ROTATION_EPSILON_DEGREES := 0.05
const ORIGIN_EPSILON := 0.00001


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var fits: Dictionary = {}
	var failed: int = 0
	for key: String in CharacterBuilder.WEAPON_MODELS:
		var parts: PackedStringArray = key.split("/")
		if parts.size() != 2:
			push_error("Unreadable WEAPON_MODELS key '%s'" % key)
			failed += 1
			continue
		var fit: Variant = await _capture(key, parts[0], parts[1])
		if fit == null:
			failed += 1
			continue
		if not (fit as Dictionary).is_empty():
			fits[key] = fit

	if failed > 0:
		print("Captured nothing: %d weapon(s) could not be read." % failed)
		quit(1)
		return
	_write(fits)
	quit(0)


## The difference between where the weapon IS in the built scene and where the builder
## would put it unaided, or {} when they agree.
func _capture(key: String, class_key: String, color: String) -> Variant:
	var model: Dictionary = CharacterBuilder.WEAPON_MODELS[key]
	var root: Node3D = WeaponFitPass._stage(class_key, color, self)
	if root == null:
		return null
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var weapon: Node3D = root.find_child("Weapon", true, false) as Node3D
	var bone_index: int = skeleton.find_bone(String(model["bone"])) if skeleton != null else -1
	if skeleton == null or anim_player == null or weapon == null or bone_index == -1:
		push_error("%s: no Skeleton3D, AnimationPlayer, Weapon or bone '%s'" % [key, model["bone"]])
		root.free()
		return null

	# What the editor left there.
	var captured: Transform3D = weapon.transform

	# Pose it the way the builder aims against, so the baseline below is computed from the
	# same hand orientation the build used - see WeaponFitPass for why this needs a frame.
	var pose: Array = model.get("pose", [])
	if pose.size() >= 2 and anim_player.has_animation(String(pose[0])):
		anim_player.play(String(pose[0]))
		anim_player.seek(anim_player.get_animation(String(pose[0])).length * clampf(float(pose[1]), 0.0, 1.0), true)
		await process_frame
		anim_player.stop()

	# The baseline is computed with the fit file DELIBERATELY IGNORED. Capturing against a
	# baseline that already included the last capture would compound every run - drag once,
	# capture three times, and the weapon would have turned three times.
	var previous_fit: Dictionary = {}
	if FileAccess.file_exists(CharacterBuilder.WEAPON_FIT_PATH):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CharacterBuilder.WEAPON_FIT_PATH))
		if raw is Dictionary:
			previous_fit = raw as Dictionary
	var baseline: Transform3D = _baseline(key, model, skeleton, bone_index, root, weapon, previous_fit)

	var delta_basis: Basis = baseline.basis.orthonormalized().inverse() * captured.basis.orthonormalized()
	# Recorded as a quaternion, because that is what survives the trip - see the note in
	# CharacterBuilder.weapon_transform. The euler is computed too, but only to print: a
	# number a person can read is worth having, as long as nothing depends on it.
	var quat: Quaternion = delta_basis.get_rotation_quaternion().normalized()
	var euler: Vector3 = delta_basis.get_euler()
	var degrees := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
	root.free()

	var fit: Dictionary = {}
	if degrees.length() > ROTATION_EPSILON_DEGREES:
		fit["rotation_quat"] = [quat.x, quat.y, quat.z, quat.w]
	if captured.origin.distance_to(baseline.origin) > ORIGIN_EPSILON:
		fit["origin"] = [captured.origin.x, captured.origin.y, captured.origin.z]

	var scale_ratio: float = captured.basis.get_scale().x / maxf(baseline.basis.get_scale().x, 0.000001)
	if absf(scale_ratio - 1.0) > 0.01:
		# Deliberately not captured: size stays one number in WEAPON_MODELS so it can be
		# changed without re-dragging anything. Reported so a scaling nudge is not silently
		# swallowed.
		print("  %s: scaled %.2fx in the editor - set \"length\": %.2f in WEAPON_MODELS to keep it"
			% [key, scale_ratio, float(model["length"]) * scale_ratio])

	if fit.is_empty():
		print("  %s: unchanged" % key)
	else:
		print("  %s: rotation %s  origin %s" % [
			key, degrees.snapped(Vector3.ONE * 0.01),
			captured.origin if fit.has("origin") else Vector3.ZERO])
	return fit


## Where the builder would place this weapon with no captured fit applied.
func _baseline(key: String, model: Dictionary, skeleton: Skeleton3D, bone_index: int, root: Node3D, weapon: Node3D, previous_fit: Dictionary) -> Transform3D:
	var stripped: Dictionary = previous_fit.duplicate()
	stripped.erase(key)
	var swap_path: String = CharacterBuilder.WEAPON_FIT_PATH
	var restore: String = FileAccess.get_file_as_string(swap_path) if FileAccess.file_exists(swap_path) else ""
	_write_raw(swap_path, JSON.stringify(stripped, "\t"))
	var baseline: Transform3D = CharacterBuilder.weapon_transform(
		key,
		model,
		skeleton.get_bone_global_pose(bone_index).basis,
		CharacterBuilder._transform_to_ancestor(skeleton, root).basis.orthonormalized(),
		CharacterBuilder._model_extent(weapon, Vector3(model["axis"])),
		CharacterBuilder._get_node_global_scale(skeleton).y
	)
	if restore == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(swap_path))
	else:
		_write_raw(swap_path, restore)
	return baseline


func _write(fits: Dictionary) -> void:
	_write_raw(CharacterBuilder.WEAPON_FIT_PATH, JSON.stringify(fits, "\t") + "\n")
	if fits.is_empty():
		print("No hand adjustments found; %s cleared." % CharacterBuilder.WEAPON_FIT_PATH)
	else:
		print("Captured %d weapon fit(s) to %s. Rebuild to bake them in." % [
			fits.size(), CharacterBuilder.WEAPON_FIT_PATH])


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
