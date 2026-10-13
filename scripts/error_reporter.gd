extends Node
## Writes a timestamped log of every session and sends it home when something went wrong.
##
## Godot already writes user://logs/godot.log, and it was not enough the first time a tester
## hit a real crash: no timestamps, nothing about what the game was doing, only the last five
## sessions kept (a single validation run rotates the interesting one away), and it stays on
## the tester's machine. This keeps its own log next to it, with the game's state stamped
## through it, and uploads it to the Firebase project the lobbies already use.
##
## THREE WAYS A SESSION GETS REPORTED.
##   gpu_device_lost  The graphics driver dropped the device (D3D12 0x887A0005, Vulkan
##                    DEVICE_LOST). The game does not crash on that - it carries on with a
##                    dead screen, logging a failed GPU call every frame, until somebody
##                    kills it. So it is caught as it happens, reported, and the game is
##                    closed with a message instead of hanging.
##   crash            The process died outright. Nothing can run at that point, so every
##                    session leaves a marker that a clean exit removes; finding it on the
##                    next start means the last session never got to exit, and its log is
##                    sent then.
##   errors           Engine or script errors in a session that otherwise survived. Sent
##                    once per session, a little after the first, so the report shows what
##                    followed too.
##
## Reports that cannot be sent yet (offline, no Firebase settings) wait in
## user://error_reports/pending/ and go out on a later start.
##
## Only EXPORTED builds upload. A run from the editor binary - the editor itself, the
## validation suite, every tool scene - writes its log and keeps it.

const REPORT_DIR := "user://error_reports/"
const PENDING_DIR := REPORT_DIR + "pending/"
## Per process, because two copies of the game on one machine is a normal thing to do - the
## LAN tests do it, and so does anyone trying LAN play alone. With one shared marker the
## second copy would report the first, still running, as crashed.
const SESSION_LOG_PATTERN := REPORT_DIR + "session_%d.log"
## Present while a session runs. Written at start, removed on a clean exit.
const MARKER_PATTERN := REPORT_DIR + "running_%d.json"
## The last session that exited cleanly, kept for a look by hand.
const LAST_SESSION_LOG := REPORT_DIR + "last_session.log"
## Written by the release workflow; absent in a checkout, which reports itself as "dev".
const BUILD_INFO := "res://build_info.json"
const FIREBASE_PATH := "crash_reports"

## How much of the log one report carries. The database holds it as one string, and the
## end of the session is what matters - the start is summarised in the header.
const MAX_LOG_CHARS := 150000
## Past this the session log only takes errors, so a runaway print cannot fill the disk.
const MAX_LOG_BYTES := 8 * 1024 * 1024
## Pending reports kept at most; the oldest go first.
const MAX_PENDING := 8
const STATUS_INTERVAL := 15.0
## The longest a written line may sit in the file buffer. A process that dies outright takes
## its unflushed lines with it, and those are the last thing it did.
const FLUSH_INTERVAL := 1.0
## Seconds after a session's first error before its report is sent.
const ERRORS_REPORT_DELAY := 30.0
## How long a device-lost report gets to upload before the game closes anyway.
const GPU_LOST_UPLOAD_TIMEOUT := 12.0

## What a lost GPU device looks like in an engine error, per rendering driver.
const DEVICE_LOST_MARKERS: Array[String] = [
	"0x887a0005", "0x887a0006", "0x887a0007", "DEVICE_REMOVED", "DEVICE_HUNG", "DEVICE_LOST",
]

## The game's state, stamped into every report and every status line. Kept current from
## SignalBus rather than asked for at report time, because by then - a dead GPU, a dying
## process - asking the scene anything is exactly what may not work.
var context: Dictionary = {}
## Off only in tools/tests/error_reporter.gd, which has to see a lost device reported without
## the game closing under it.
var close_on_gpu_lost: bool = true

var _mutex := Mutex.new()
var _file: FileAccess = null
var _busy: bool = false
var _start_msec: int = 0
var _start_wall: String = ""
var _last_line: String = ""
var _repeats: int = 0
var _bytes_written: int = 0
## "code @ file:line" -> how many times, for the report's summary.
var _error_counts: Dictionary = {}
var _error_total: int = 0
var _first_error: String = ""
var _gpu_lost: bool = false
var _errors_report_queued: bool = false
var _header: Dictionary = {}
var _breadcrumbs: Array[String] = []
var _status_timer: float = 0.0
var _flush_timer: float = 0.0
var _unflushed: bool = false
var _logger: SessionLogger = null
var _session_log: String = ""
var _marker: String = ""
var _home: String = ""


## Hooked into the engine's own logging, so it sees exactly what godot.log sees - engine
## errors, script errors with their backtraces, and every print - from whichever thread
## raised them.
class SessionLogger extends Logger:
	var reporter: Node

	func _log_message(message: String, error: bool) -> void:
		reporter._record("E " if error else "  ", message.strip_edges(false, true), error)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var text: String = rationale if not rationale.is_empty() else code
		var where: String = "%s (%s:%d)" % [function, file, line]
		var body: String = "%s: %s\n      at: %s" % [kind, text, where]
		for backtrace: ScriptBacktrace in script_backtraces:
			if backtrace != null and not backtrace.is_empty():
				body += "\n      " + backtrace.format(6).strip_edges().replace("\n", "\n      ")
		var is_error: bool = error_type != 1
		reporter._record("! " if is_error else "w ", body, is_error)
		if is_error:
			reporter._count_error("%s: %s @ %s:%d" % [kind, code, file, line], body, rationale + " " + code)


func _ready() -> void:
	# Runs through a quit and a lost GPU alike.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(PENDING_DIR)
	_start_msec = Time.get_ticks_msec()
	_start_wall = Time.get_datetime_string_from_system(true) + "Z"
	_home = OS.get_environment("USERPROFILE")
	if _home.is_empty():
		_home = OS.get_environment("HOME")
	_session_log = SESSION_LOG_PATTERN % OS.get_process_id()
	_marker = MARKER_PATTERN % OS.get_process_id()
	_header = _system_info()
	_queue_dead_sessions_as_crashes()
	_open_session_log()
	var marker := FileAccess.open(_marker, FileAccess.WRITE)
	if marker != null:
		marker.store_string(JSON.stringify({
			"pid": OS.get_process_id(), "started": _start_wall, "version": _header.get("version", ""),
		}))
		marker.close()
	_logger = SessionLogger.new()
	_logger.reporter = self
	OS.add_logger(_logger)
	_connect_context.call_deferred()
	_send_pending.call_deferred()


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null
	_mutex.lock()
	_flush_repeats()
	if _file != null:
		_file.store_line("[%s] session ended cleanly" % _stamp())
		_file.close()
		_file = null
	_mutex.unlock()
	DirAccess.remove_absolute(LAST_SESSION_LOG)
	DirAccess.rename_absolute(_session_log, LAST_SESSION_LOG)
	DirAccess.remove_absolute(_marker)


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL:
		_flush_timer = 0.0
		_mutex.lock()
		if _unflushed and _file != null:
			_file.flush()
			_unflushed = false
		_mutex.unlock()
	_status_timer += delta
	if _status_timer >= STATUS_INTERVAL:
		_status_timer = 0.0
		_record("~ ", "status " + JSON.stringify(_status()), false)


## A line in the log marking something the game did - a wave starting, a spell's effect
## going off. Kept in the report's context too, so the last few are there even when the log
## tail is all one repeated error.
func breadcrumb(text: String) -> void:
	_mutex.lock()
	_breadcrumbs.append("%s %s" % [_stamp(), text])
	if _breadcrumbs.size() > 25:
		_breadcrumbs.pop_front()
	_mutex.unlock()
	_record("> ", text, true)


# --- the log -----------------------------------------------------------------------------

func _open_session_log() -> void:
	_file = FileAccess.open(_session_log, FileAccess.WRITE)
	if _file == null:
		return
	_file.store_line("Pentafall session %s" % _start_wall)
	_file.store_line(JSON.stringify(_header, "  "))
	_file.flush()


## Called from the logger, on any thread. Identical consecutive lines are counted rather
## than written: a lost device logs the same failure thousands of times a second, and the
## tester's crash log was 19 MB of exactly that.
func _record(prefix: String, text: String, flush: bool) -> void:
	_mutex.lock()
	if _busy or _file == null:
		_mutex.unlock()
		return
	_busy = true
	var line: String = prefix + _scrub(text)
	if line == _last_line:
		_repeats += 1
	else:
		_flush_repeats()
		_last_line = line
		if _bytes_written < MAX_LOG_BYTES or flush:
			var stamped: String = "[%s] %s" % [_stamp(), line]
			_file.store_line(stamped)
			_bytes_written += stamped.length() + 1
			if flush:
				_file.flush()
			_unflushed = not flush
	_busy = false
	_mutex.unlock()


## Caller holds the mutex.
func _flush_repeats() -> void:
	if _repeats > 0 and _file != null:
		_file.store_line("[%s]   ... the line above %d more times" % [_stamp(), _repeats])
		_file.flush()
		_unflushed = false
	_repeats = 0


func _count_error(key: String, body: String, searchable: String) -> void:
	_mutex.lock()
	_error_counts[key] = int(_error_counts.get(key, 0)) + 1
	_error_total += 1
	if _first_error.is_empty():
		_first_error = body
	var lost: bool = false
	if not _gpu_lost:
		for marker: String in DEVICE_LOST_MARKERS:
			if searchable.containsn(marker):
				lost = true
				_gpu_lost = true
				break
	var queue_errors: bool = not _errors_report_queued and not lost
	if queue_errors:
		_errors_report_queued = true
	_mutex.unlock()
	# Deferred onto the main thread: this can be running on the render thread.
	if lost:
		_on_gpu_device_lost.call_deferred(body)
	elif queue_errors:
		_send_errors_report_later.call_deferred()


func _stamp() -> String:
	return "%9.3f" % ((Time.get_ticks_msec() - _start_msec) / 1000.0)


## The tester's Windows user name is in every path under their profile. Not ours to keep.
func _scrub(text: String) -> String:
	if _home.is_empty():
		return text
	return text.replace(_home, "~").replace(_home.replace("\\", "/"), "~")


# --- what the game is doing --------------------------------------------------------------

func _connect_context() -> void:
	context["scene"] = String(get_tree().current_scene.name) if get_tree().current_scene != null else ""
	SignalBus.wave_started.connect(func(wave: int) -> void:
		context["wave"] = wave
		breadcrumb("wave %d started" % wave))
	SignalBus.wave_completed.connect(func(wave: int) -> void:
		breadcrumb("wave %d completed" % wave))
	SignalBus.health_changed.connect(_on_base_health)
	SignalBus.game_over.connect(func() -> void: breadcrumb("game over"))
	get_tree().node_added.connect(_on_node_added)


## Base health is in every status line; crossing a quarter on the way down is a breadcrumb,
## because "the base was nearly gone" is exactly the kind of thing a tester remembers.
func _on_base_health(current: float, max_health: float) -> void:
	var fraction: float = current / maxf(max_health, 1.0)
	var previous: float = float(context.get("base_hp_fraction", 1.0))
	context["base_hp"] = "%d/%d" % [roundi(current), roundi(max_health)]
	context["base_hp_fraction"] = snappedf(fraction, 0.01)
	for mark: float in [0.75, 0.5, 0.25, 0.1]:
		if previous > mark and fraction <= mark:
			breadcrumb("base health below %d%%" % roundi(mark * 100.0))


func _on_node_added(node: Node) -> void:
	if node == get_tree().current_scene:
		context["scene"] = String(node.name)
		breadcrumb("scene %s" % node.name)


func _status() -> Dictionary:
	var status: Dictionary = context.duplicate()
	status["fps"] = Engine.get_frames_per_second()
	status["vram_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	status["texture_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1)
	status["ram_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	status["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	status["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	status["enemies"] = get_tree().get_node_count_in_group("enemies")
	status["players"] = get_tree().get_node_count_in_group("player")
	return status


func _system_info() -> Dictionary:
	var build: Dictionary = {}
	if FileAccess.file_exists(BUILD_INFO):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_INFO))
		if parsed is Dictionary:
			build = parsed
	var driver_info: PackedStringArray = OS.get_video_adapter_driver_info()
	var memory: Dictionary = OS.get_memory_info()
	var override_cfg: String = ""
	if FileAccess.file_exists("user://override.cfg"):
		override_cfg = FileAccess.get_file_as_string("user://override.cfg")
	return {
		"version": String(build.get("version", "dev")),
		"commit": String(build.get("commit", "")),
		"exported": OS.has_feature("template"),
		"engine": Engine.get_version_info().get("string", ""),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": "%s x%d" % [OS.get_processor_name(), OS.get_processor_count()],
		"ram_gb": snappedf(float(memory.get("physical", 0)) / 1073741824.0, 0.1),
		"gpu": "%s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()],
		"gpu_driver": " ".join(driver_info),
		"renderer": "%s / %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()],
		"graphics_api": RenderingServer.get_video_adapter_api_version(),
		"screen": "%s @ %d Hz" % [DisplayServer.screen_get_size(), roundi(DisplayServer.screen_get_refresh_rate())],
		"override_cfg": override_cfg.strip_edges(),
	}


# --- reports -----------------------------------------------------------------------------

## A marker whose process is gone belongs to a session that never exited: its log is the
## crash. A marker whose process is still running is another copy of the game, left alone.
func _queue_dead_sessions_as_crashes() -> void:
	for file_name: String in DirAccess.get_files_at(REPORT_DIR):
		if not (file_name.begins_with("running_") and file_name.ends_with(".json")):
			continue
		var pid: int = file_name.trim_prefix("running_").trim_suffix(".json").to_int()
		if pid <= 0 or pid == OS.get_process_id() or OS.is_process_running(pid):
			continue
		var started: String = ""
		var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_DIR + file_name))
		if marker is Dictionary:
			started = String(marker.get("started", ""))
		var log_path: String = SESSION_LOG_PATTERN % pid
		var log_text: String = FileAccess.get_file_as_string(log_path) if FileAccess.file_exists(log_path) else ""
		_save_pending(_build_report("crash", {
			"summary": "A session started %s ended without exiting." % started,
			"crashed_session_started": started,
		}, log_text))
		DirAccess.remove_absolute(REPORT_DIR + file_name)
		DirAccess.remove_absolute(log_path)


func _send_errors_report_later() -> void:
	await get_tree().create_timer(ERRORS_REPORT_DELAY, true, false, true).timeout
	var path: String = _save_pending(_build_report("errors", {}, _current_log()))
	await _upload(path)


## The game cannot render again after this, so: report it, tell the player in a native
## message box (which needs no GPU), and close.
func _on_gpu_device_lost(first_line: String) -> void:
	breadcrumb("GPU device lost - closing")
	var path: String = _save_pending(_build_report("gpu_device_lost", {"summary": first_line}, _current_log()))
	var timeout := get_tree().create_timer(GPU_LOST_UPLOAD_TIMEOUT, true, false, true)
	var done: Array[bool] = [false]
	(func() -> void:
		await _upload(path)
		done[0] = true
	).call()
	while not done[0] and timeout.time_left > 0.0:
		await get_tree().process_frame
	if not close_on_gpu_lost:
		return
	var where: String = "A report was sent to the developer."
	if FileAccess.file_exists(path):
		where = "A report was saved to:\n" + ProjectSettings.globalize_path(path)
		if _uploads_enabled():
			where += "\nIt will be sent the next time the game starts."
	OS.alert(
		"The graphics driver stopped responding (GPU device lost), so Pentafall has to close.\n\n" + where,
		"Pentafall"
	)
	get_tree().quit(1)


func _current_log() -> String:
	_mutex.lock()
	_flush_repeats()
	if _file != null:
		_file.flush()
	_mutex.unlock()
	return FileAccess.get_file_as_string(_session_log)


func _build_report(kind: String, extra: Dictionary, log_text: String) -> Dictionary:
	_mutex.lock()
	var counts: Array = []
	for key: String in _error_counts:
		counts.append([key, _error_counts[key]])
	var first_error: String = _first_error
	var total: int = _error_total
	var crumbs: Array[String] = _breadcrumbs.duplicate()
	_mutex.unlock()
	counts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var top: Dictionary = {}
	for entry: Array in counts.slice(0, 15):
		# Database keys cannot hold . $ # [ ] /
		top[_db_key(String(entry[0]))] = entry[1]
	var report: Dictionary = {
		"kind": kind,
		"local_time": Time.get_datetime_string_from_system(true) + "Z",
		"session_started": _start_wall,
		"system": _header,
		"context": context.duplicate() if kind != "crash" else {},
		"breadcrumbs": crumbs if kind != "crash" else [],
		"error_total": total if kind != "crash" else -1,
		"first_error": _scrub(first_error),
		"top_errors": top,
		"log_truncated": log_text.length() > MAX_LOG_CHARS,
		"log": log_text.right(MAX_LOG_CHARS),
	}
	report.merge(extra, true)
	return report


func _db_key(text: String) -> String:
	for bad: String in [".", "$", "#", "[", "]", "/"]:
		text = text.replace(bad, "_")
	return text.left(700)


## Returns the file the report was saved to.
func _save_pending(report: Dictionary) -> String:
	var path: String = PENDING_DIR + "%s_%d.json" % [String(report["kind"]), Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report))
	file.close()
	var pending: Array[String] = _pending_oldest_first()
	while pending.size() > MAX_PENDING:
		DirAccess.remove_absolute(PENDING_DIR + pending.pop_front())
	return path


## The waiting reports, oldest first, by the time in their name (`<kind>_<unix time>.json`).
## Sorting the names themselves put every "crash_" before every "errors_" and "gpu_", so with
## the folder full a new crash report was the first thing pruned - the one report that most
## needed to survive.
func _pending_oldest_first() -> Array[String]:
	var names: Array[String] = []
	for file_name: String in DirAccess.get_files_at(PENDING_DIR):
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort_custom(func(a: String, b: String) -> bool:
		return _report_time(a) < _report_time(b) or (_report_time(a) == _report_time(b) and a < b))
	return names


func _report_time(file_name: String) -> int:
	return file_name.get_basename().get_slice("_", file_name.get_basename().get_slice_count("_") - 1).to_int()


func _send_pending() -> void:
	for file_name: String in _pending_oldest_first():
		if not await _upload(PENDING_DIR + file_name):
			return


## Sends one saved report and deletes it once the database has it. False when it could not
## be sent - the file stays for next time.
func _upload(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return true
	if not _uploads_enabled():
		return false
	var db: FirebaseRtdb = NetOnline.database()
	if db == null:
		return false
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (report is Dictionary):
		DirAccess.remove_absolute(path)
		return true
	if not await db.ensure_auth():
		return false
	report["uid"] = db.uid()
	report["created"] = {".sv": "timestamp"}
	var result: Dictionary = await db.push_json(FIREBASE_PATH, report)
	if not result["ok"]:
		return false
	DirAccess.remove_absolute(path)
	_record("~ ", "report %s sent as %s/%s" % [path.get_file(), FIREBASE_PATH, result.get("key", "?")], true)
	return true


func _uploads_enabled() -> bool:
	return GameSettings.error_reports_upload and (OS.has_feature("template") or GameSettings.error_reports_upload_from_editor)
