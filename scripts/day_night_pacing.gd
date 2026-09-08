extends Node
class_name DayNightPacing
## Makes a night take less real time than a day, without shortening the night itself.
##
## Sky3D cannot do this on its own. Its clock is linear - TimeOfDay._progress_time()
## advances current_time by a constant HOURS_PER_DAY / (minutes_per_day * 60) every
## tick, so the addon has no concept of a day and a night of different lengths.
##
## The astronomical route would be to push TimeOfDay.latitude far north and set the
## date near midsummer, which genuinely produces long days and short nights. That was
## rejected here because it also flattens the sun's arc across the sky, tilts the star
## field, and ties the arena's pacing to a calendar date that has nothing to do with
## how long a player should be fighting in the dark.
##
## So this leaves the in-game hours exactly where they are and changes only how fast
## they are consumed: each phase gets whatever clock rate makes it last the real number
## of minutes asked for below. The clock still reads 20:00 to 06:00, and the sun, moon
## and stars still travel their proper paths - they just get through the dark faster.
##
## Because both phases are driven from here, Sky3D's own minutes_per_day no longer
## controls anything at runtime; this node overwrites it at every dusk and dawn. It
## still governs the editor preview.
##
## Attached to the Sky3D node by MainController.

## In-game hours that count as night. The window wraps midnight, so dusk is the larger
## of the two.
@export var dawn_hour: float = 6.0
@export var dusk_hour: float = 20.0

## How long each phase should actually last, in real minutes.
##
## Stated as durations rather than as a speed multiplier deliberately: a multiplier
## silently changes a phase's length whenever dawn_hour or dusk_hour move, whereas
## these hold regardless of how the window is split.
@export var day_real_minutes: float = 20.0
@export var night_real_minutes: float = 5.0

var _sky: Node = null
var _night_active: bool = false
signal phase_changed(night: bool)


func _ready() -> void:
	_sky = get_parent()
	if _sky == null or not ("minutes_per_day" in _sky):
		push_error("DayNightPacing expects to be a child of a Sky3D node.")
		set_process(false)
		return
	_apply(_is_night(float(_sky.current_time)))


func _process(_delta: float) -> void:
	if _sky == null:
		return
	var night_now: bool = _is_night(float(_sky.current_time))
	if night_now != _night_active:
		_apply(night_now)


## The night window wraps midnight, so it is "after dusk OR before dawn" rather than a
## single range test.
func _is_night(hour: float) -> bool:
	return hour >= dusk_hour or hour < dawn_hour


## In-game hours between dusk and dawn, wrapping midnight.
func _night_hours() -> float:
	return (24.0 - dusk_hour) + dawn_hour


func _apply(night: bool) -> void:
	_night_active = night
	phase_changed.emit(night)
	# minutes_per_day is the real minutes a FULL 24 in-game hours would take, so a phase
	# covering `hours` of them costs hours/24 of it. Inverting that gives the rate that
	# lands the phase on its requested real duration.
	var hours: float = _night_hours() if night else 24.0 - _night_hours()
	var wanted: float = night_real_minutes if night else day_real_minutes
	_sky.minutes_per_day = wanted * 24.0 / maxf(hours, 0.01)
