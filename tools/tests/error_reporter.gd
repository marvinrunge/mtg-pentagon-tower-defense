extends Node
## Regression test: does ErrorReporter keep a usable log and turn the right things into
## reports?
##
## Checks, against the live autoload: the session log and its running-marker exist; an
## error lands in the log with a timestamp; a flood of one identical error is collapsed into
## a count rather than written thousands of times (the tester's crash log was 19 MB of one
## line); a leftover marker from a process that no longer exists becomes a "crash" report
## carrying that session's log; and an engine error naming a lost D3D12 device is caught and
## reported as "gpu_device_lost".
##
## The errors are handed straight to the reporter's Logger - the call the engine makes for a
## real one - rather than raised with push_error, because tools/validate_godot.ps1 fails any
## check that prints an engine error, and this one would print five hundred. That the logger
## is hooked into the engine at all is proven with an ordinary print.
##
## Nothing is uploaded - this runs from the editor binary, which only keeps reports locally
## (GameSettings.error_reports_upload_from_editor) - and every report it makes is deleted.
##
## Run with:  godot --headless --path . res://tools/tests/error_reporter.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const FAKE_PID := 999983

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var reporter: Node = ErrorReporter
	var pending_before: PackedStringArray = DirAccess.get_files_at(reporter.PENDING_DIR)

	if not FileAccess.file_exists(reporter._session_log):
		_failures.append("no session log at %s" % reporter._session_log)
	if not FileAccess.file_exists(reporter._marker):
		_failures.append("no running marker at %s" % reporter._marker)

	print("error reporter test: an ordinary print")
	_fake_error("error reporter test: a single error")
	for i in 500:
		_fake_error("error reporter test: the same error again")
	var log_text: String = reporter._current_log()
	if not log_text.contains("error reporter test: an ordinary print"):
		_failures.append("a print never reached the session log - the logger is not hooked in")
	if not log_text.contains("error reporter test: a single error"):
		_failures.append("an error never reached the session log")
	var copies: int = log_text.count("error reporter test: the same error again")
	if copies > 2:
		_failures.append("500 identical errors were written %d times instead of collapsed" % copies)
	if not log_text.contains("more times"):
		_failures.append("the collapsed repeats were not counted in the log")
	if int(reporter._error_total) < 501:
		_failures.append("only %d errors counted" % reporter._error_total)

	# A session whose process is gone: it has to become a crash report with its own log.
	var fake_log: String = reporter.SESSION_LOG_PATTERN % FAKE_PID
	var fake_marker: String = reporter.MARKER_PATTERN % FAKE_PID
	var file := FileAccess.open(fake_log, FileAccess.WRITE)
	file.store_string("the last words of a crashed session")
	file.close()
	file = FileAccess.open(fake_marker, FileAccess.WRITE)
	file.store_string(JSON.stringify({"pid": FAKE_PID, "started": "earlier"}))
	file.close()
	reporter._queue_dead_sessions_as_crashes()
	var crash: Dictionary = _newest_report("crash", pending_before)
	if crash.is_empty():
		_failures.append("a dead session's marker did not become a crash report")
	elif not String(crash.get("log", "")).contains("the last words of a crashed session"):
		_failures.append("the crash report does not carry the dead session's log")
	if FileAccess.file_exists(fake_marker) or FileAccess.file_exists(fake_log):
		_failures.append("the dead session's marker or log was left behind")

	# The error a lost D3D12 device actually logs, word for word from the tester's log.
	reporter.close_on_gpu_lost = false
	_fake_error("Can't create buffer of size: 256, error 0x887a0005.", "buffer_create")
	for i in 30:
		await get_tree().process_frame
	if not reporter._gpu_lost:
		_failures.append("a D3D12 device-removed error was not recognised as a lost GPU")
	var lost: Dictionary = _newest_report("gpu_device_lost", pending_before)
	if lost.is_empty():
		_failures.append("a lost GPU did not produce a gpu_device_lost report")
	else:
		for key: String in ["system", "context", "breadcrumbs", "top_errors", "log", "first_error"]:
			if not lost.has(key):
				_failures.append("the gpu_device_lost report has no '%s'" % key)
		if not String(lost.get("summary", "")).contains("0x887a0005"):
			_failures.append("the gpu_device_lost report does not say which error it was")

	# Leave the pending folder as it was found.
	for file_name: String in DirAccess.get_files_at(reporter.PENDING_DIR):
		if not pending_before.has(file_name):
			DirAccess.remove_absolute(reporter.PENDING_DIR + file_name)

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


## What the engine hands every Logger for an error, as buffer_create logged it on the day.
func _fake_error(rationale: String, function: String = "_run") -> void:
	var no_backtraces: Array[ScriptBacktrace] = []
	ErrorReporter._logger._log_error(function, "tools/tests/error_reporter.gd", 1, "", rationale,
		false, Logger.ERROR_TYPE_ERROR, no_backtraces)


func _newest_report(kind: String, ignore: PackedStringArray) -> Dictionary:
	var dir: String = ErrorReporter.PENDING_DIR
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	names.sort()
	names.reverse()
	for file_name: String in names:
		if file_name.begins_with(kind + "_") and not ignore.has(file_name):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + file_name))
			if parsed is Dictionary:
				return parsed
	return {}
