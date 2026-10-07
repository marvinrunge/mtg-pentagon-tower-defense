extends Node
## The player's own preferences, remembered between sessions: the name they play under, how
## loud things are, and which of the HUD's optional readouts they want.
##
## Graphics are next door in GraphicsSettings, which has apply logic of its own; both keep
## their values in the one file SettingsFile writes.
##
## Most of these are still READ off GameSettings at runtime - the HUD toggles and the music
## switch were live there long before anything remembered them, and a dozen call sites ask
## GameSettings for them. So this is the layer that loads them into GameSettings at boot and
## writes them back out when the player changes one, not a second place to read them from.
##
## Volumes are the exception, and live only here: they are bus volumes (see
## ensure_audio_buses), so nothing else needs to know them.

## A preference moved. The HUD follows the ones only it can apply - the minimap - off this.
signal changed(key: StringName)

const SettingsFile := preload("res://scripts/settings_file.gd")

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

## A slider at the bottom is OFF, not merely quiet. linear_to_db(0) is -inf, which the audio
## server accepts but reads as a bug when printed; muting the bus says what is meant.
const SILENT_BELOW := 0.005

## key -> the file section it is saved under. Also the list of what may be set at all, so a
## typo at a call site fails loudly instead of quietly saving a key nothing ever reads.
const SECTIONS: Dictionary = {
	&"player_name": "player",
	&"master_volume": "audio",
	&"music_volume": "audio",
	&"sfx_volume": "audio",
	&"music_enabled": "audio",
	&"show_damage_numbers": "interface",
	&"show_enemy_health_bars": "interface",
	&"show_attack_indicators": "interface",
	&"attack_indicator_style": "interface",
	&"camera_shake_enabled": "interface",
	&"show_minimap": "interface",
	&"minimap_size": "interface",
}

## Empty until the player has typed one; the main menu shows "Player" in its place.
var player_name: String = ""
## 0..1, linear. The slider position IS this number; the bus gets linear_to_db of it.
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var music_enabled: bool = true
var show_damage_numbers: bool = true
var show_enemy_health_bars: bool = true
var show_attack_indicators: bool = true
var attack_indicator_style: String = "themed"
var camera_shake_enabled: bool = true
var show_minimap: bool = true
var minimap_size: float = 200.0

var _save_queued: bool = false


func _ready() -> void:
	ensure_audio_buses()
	_load()
	_apply_all()


## Sets one preference, applies it, tells whoever follows it, and saves soon after.
##
## Saving is deferred a moment rather than done here: a slider reports every pixel it is
## dragged across, and writing the file sixty times a second while it moves is pointless.
func set_value(key: StringName, value: Variant) -> void:
	if not SECTIONS.has(key):
		push_error("UserSettings: '%s' is not a user setting" % key)
		return
	if get(key) == value:
		return
	set(key, value)
	_apply(key)
	changed.emit(key)
	_queue_save()


## The Music and SFX buses, created if the project has none. SoundBank routes every voice
## into one of the two, which is what lets a slider turn the music down without the swords.
##
## Static and idempotent so SoundBank can call it too without caring which autoload ran
## first: whichever gets here first makes the buses, and the other finds them.
static func ensure_audio_buses() -> void:
	for bus_name: StringName in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)


func _apply_all() -> void:
	for key: StringName in SECTIONS:
		_apply(key)


func _apply(key: StringName) -> void:
	match key:
		&"master_volume":
			_set_bus_volume(BUS_MASTER, master_volume)
		&"music_volume":
			_set_bus_volume(BUS_MUSIC, music_volume)
		&"sfx_volume":
			_set_bus_volume(BUS_SFX, sfx_volume)
		&"music_enabled":
			GameSettings.music_enabled = music_enabled
			# SoundBank reads GameSettings itself when it starts, so this is only needed
			# once it has - and only safe then, whichever autoload happens to boot first.
			if SoundBank.is_node_ready():
				SoundBank.apply_music_settings()
		&"show_damage_numbers":
			GameSettings.show_damage_numbers = show_damage_numbers
		&"show_enemy_health_bars":
			GameSettings.show_enemy_health_bars = show_enemy_health_bars
			SignalBus.enemy_health_bars_visibility_changed.emit(show_enemy_health_bars)
		&"show_attack_indicators":
			GameSettings.show_attack_indicators = show_attack_indicators
			SignalBus.attack_indicators_visibility_changed.emit(show_attack_indicators)
		&"attack_indicator_style":
			# An old or hand-edited file must not leave telegraphs in a style nothing draws.
			if not AttackIndicator.STYLES.has(attack_indicator_style):
				attack_indicator_style = "themed"
			GameSettings.attack_indicator_style = attack_indicator_style
		&"camera_shake_enabled":
			GameSettings.camera_shake_enabled = camera_shake_enabled


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var silent: bool = linear < SILENT_BELOW
	AudioServer.set_bus_mute(index, silent)
	if not silent:
		AudioServer.set_bus_volume_db(index, linear_to_db(linear))


func _queue_save() -> void:
	if _save_queued or not is_inside_tree():
		return
	_save_queued = true
	get_tree().create_timer(0.4).timeout.connect(_save)


func _save() -> void:
	_save_queued = false
	var by_section: Dictionary = {}
	for key: StringName in SECTIONS:
		var section: String = SECTIONS[key]
		if not by_section.has(section):
			by_section[section] = {}
		by_section[section][String(key)] = get(key)
	for section: String in by_section:
		SettingsFile.write_section(section, by_section[section])


## Reads what was saved, keeping each default for anything the file does not have and for
## anything whose saved type no longer matches - a hand-edited file must not crash the menu.
func _load() -> void:
	var cfg: ConfigFile = SettingsFile.load_file()
	for key: StringName in SECTIONS:
		var section: String = SECTIONS[key]
		var current: Variant = get(key)
		var saved: Variant = cfg.get_value(section, String(key), current)
		if typeof(saved) == typeof(current):
			set(key, saved)
		elif typeof(current) == TYPE_FLOAT and typeof(saved) == TYPE_INT:
			set(key, float(saved))
	master_volume = clampf(master_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
