extends Node
## Regression test: all gameplay music is one shuffled pool, and every track gets played.
##
## Run with:  godot --headless --path . res://tools/tests/music_playlist.tscn
##
## The music used to be four tracks in two hand-written lists - `day_music` and
## `night_music` - chosen by the day/night phase, and every dawn and dusk cut off whatever
## was playing to swap between them. Meanwhile twenty-odd tracks sat unreferenced in
## assets/music/, because adding a file to that folder did nothing unless somebody also
## remembered to add its name to the table.
##
## Both halves of that are what this checks: the pool is DISCOVERED from the folder rather
## than listed, and it is drawn from as a shuffled bag rather than rolled, so every track
## is heard once before any is heard twice.

const MUSIC_ROOT := "res://assets/music/"

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 5:
		return
	_done = true
	_run()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _run() -> void:
	print("The pool")
	_test_pool()
	print("The shuffle")
	_test_shuffle()
	print("Day and night no longer touch it")
	_test_phase_independent()

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


## Every music file on disk is in the pool, and the title theme is not.
##
## Checked against the FOLDER rather than against a count, because the failure worth
## catching is "somebody added a track and it is silently never played" - which a
## hardcoded expected number would not notice, since it would be updated by the same
## person who forgot.
func _test_pool() -> void:
	var on_disk: Array[String] = []
	for entry: String in DirAccess.get_files_at(MUSIC_ROOT):
		var file_name: String = entry
		if file_name.ends_with(".import") or file_name.ends_with(".remap"):
			file_name = file_name.get_basename()
		if SoundBank.MUSIC_EXTENSIONS.has(file_name.get_extension().to_lower()):
			if not on_disk.has(file_name):
				on_disk.append(file_name)

	var pool: Array = Array(SoundBank._gameplay_playlist)
	_check("there is gameplay music at all", pool.size() > 0)

	var missing: Array[String] = []
	for file_name: String in on_disk:
		if file_name != SoundBank.TITLE_TRACK and not pool.has(file_name):
			missing.append(file_name)
	_check("every track in the folder is in the pool", missing.is_empty(),
		"%d never played: %s" % [missing.size(), missing])
	_check("the menu theme is not in the gameplay pool",
		not pool.has(SoundBank.TITLE_TRACK))
	_check("the pool is exactly the folder minus the menu theme",
		pool.size() == on_disk.size() - 1,
		"%d in pool, %d on disk" % [pool.size(), on_disk.size()])


## A bag, not a dice roll: a full cycle plays each track exactly once, and the seam
## between two cycles does not repeat a track back to back.
func _test_shuffle() -> void:
	var size: int = SoundBank._gameplay_playlist.size()
	if size < 2:
		_check("there are enough tracks to shuffle", false, "%d" % size)
		return

	var first_cycle: Array[String] = _draw(size)
	var unique: Dictionary = {}
	for path: String in first_cycle:
		unique[path] = true
	_check("a full cycle plays every track exactly once",
		unique.size() == size, "%d distinct out of %d drawn" % [unique.size(), size])

	var second_cycle: Array[String] = _draw(size)
	var unique_second: Dictionary = {}
	for path: String in second_cycle:
		unique_second[path] = true
	_check("and so does the next cycle", unique_second.size() == size,
		"%d distinct out of %d" % [unique_second.size(), size])

	_check("no track repeats across the seam between cycles",
		first_cycle[size - 1] != second_cycle[0],
		"%s played twice running" % first_cycle[size - 1].get_file())

	# Shuffled, not merely walked in order. Two consecutive cycles laid out identically
	# would mean the reshuffle is not happening.
	_check("the order changes between cycles", first_cycle != second_cycle,
		"both cycles came out in the same order")


## A day/night transition must not restart or interrupt the music. start_gameplay_music is
## the only entry point now and is idempotent; there is no longer a per-phase call at all.
func _test_phase_independent() -> void:
	_check("SoundBank has no day/night music switch any more",
		not SoundBank.has_method("set_gameplay_music"))

	SoundBank.start_gameplay_music()
	var position_after_start: int = SoundBank._playlist_position
	SoundBank.start_gameplay_music()
	SoundBank.start_gameplay_music()
	_check("starting gameplay music again does not skip a track",
		SoundBank._playlist_position == position_after_start,
		"position moved %d -> %d" % [position_after_start, SoundBank._playlist_position])


func _draw(count: int) -> Array[String]:
	var drawn: Array[String] = []
	for _i: int in range(count):
		drawn.append(SoundBank._next_gameplay_path())
	return drawn
