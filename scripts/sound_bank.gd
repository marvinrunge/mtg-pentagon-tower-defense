extends Node
## The one place that knows which file a given game event sounds like, and the pool
## of players that play it.
##
## Autoloaded, like ProjectilePool and DamageNumberPool, and pooled for the same
## reason: a wave can land dozens of hits in the same second, and creating an
## AudioStreamPlayer3D per hit would churn nodes exactly when the frame budget is
## tightest.
##
## Events are named for what they SOUND like, not for who made them - `blunt_hit` is
## both an enemy's club and the player's kick - so the same short clip can serve
## several sources without pretending they are different sounds.
##
## Callers pass a world position (`play_at`) whenever the sound belongs to something
## on the map, so distance and stereo placement come for free; `play` is for the
## handful of events with no position of their own.
##
## WHEN a sound fires is not this file's business, but it is the point of the
## exercise: an impact sound is only convincing on the frame the weapon actually
## connects. Those frames are measured at build time - `hit_ratios` for the player
## (tools/player_character_builder.gd) and `hit_ratio` for everyone else
## (tools/animation_impact.gd) - and the same schedule that pays out the damage is
## what triggers the sound.

const SFX_ROOT := "res://assets/soundeffects/"

## event -> the interchangeable recordings of it. More than one entry means the
## event picks between them, so a run of hits does not machine-gun one waveform.
const EVENT_FILES := {
	# Every attack is two sounds, not one: the SWING always plays, on the frame the
	# move starts, and the HIT follows only if the weapon found something - on the
	# frame it actually connects. A miss is simply the swing with nothing after it,
	# which is why there is no "miss" recording any more.
	&"blade_swing": ["axe/axe-swing1.wav", "axe/axe-swing2.wav"],
	&"blade_hit": ["axe/axe-hit3.wav"],
	&"blade_heavy_swing": ["axe/axe-heavy-swing.wav"],
	&"blade_heavy_hit": ["axe/axe-heavy-hit.wav"],
	# The blunt pair: an enemy's club and the player's kick share both halves.
	&"blunt_swing": ["general/attack-miss.wav"],
	&"blunt_hit": ["club/club-hit1.wav", "club/club-hit2.wav"],
	&"arrow_shot": ["arrow/arrow-shot.wav"],
	&"arrow_hit": ["arrow/arrow-hit1.wav", "arrow/arrow-hit2.wav"],
	## The moment a boss special resolves - the one impact in the game with real
	## weight behind it.
	&"heavy_landing": ["giant-landing.wav"],
	## Not an impact at all: the note the crystal holds while it levitates. Started
	## once by MainController and left running for the whole match.
	&"crystal_ambience": ["cristal.wav"],
}

## Events that sustain instead of firing once, and are therefore the only ones
## allowed to keep a loop. The loop itself is set on the IMPORT (`edit/loop_mode=2`
## in the matching .wav.import, forward) rather than here, so the engine loops the
## sample seamlessly instead of restarting it on a `finished` signal. Note the
## importer's enum is offset from the runtime one: 0 there means "detect from the
## WAV file", 1 disabled, 2 forward.
const LOOPING_EVENTS: Array[StringName] = [&"crystal_ambience"]

## event -> the streams behind it, resolved once at startup.
var _streams: Dictionary = {}
## event -> index last played, so a two-variant event alternates instead of
## sometimes repeating itself twice in a row.
var _last_variant: Dictionary = {}
## event -> engine time it last started. Dozens of enemies connecting on the same
## frame is one sound played once, not thirty stacked into a clipping mess.
var _last_played: Dictionary = {}

var _positional: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_positional: int = 0
var _next_flat: int = 0


func _ready() -> void:
	_load_streams()
	_build_pools()


func _load_streams() -> void:
	for event: StringName in EVENT_FILES.keys():
		var streams: Array[AudioStream] = []
		for relative_path: String in EVENT_FILES[event]:
			var path: String = SFX_ROOT + relative_path
			if not ResourceLoader.exists(path):
				push_warning("Sound effect '%s' is missing; '%s' will be silent" % [path, event])
				continue
			var stream: AudioStream = load(path) as AudioStream
			if stream == null:
				push_warning("'%s' did not load as an AudioStream" % path)
				continue
			# A short impact imported with its source file's loop flag still set
			# would never stop. The sustained events are the exception, and are the
			# only ones allowed to keep whatever the importer gave them.
			if stream is AudioStreamWAV and not LOOPING_EVENTS.has(event):
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
			streams.append(stream)
		_streams[event] = streams


func _build_pools() -> void:
	for i in GameSettings.sfx_positional_voices:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = GameSettings.sfx_max_distance
		player.unit_size = GameSettings.sfx_unit_size
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_positional.append(player)
	for i in GameSettings.sfx_flat_voices:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat.append(player)


## Plays `event` at a point on the map. Silently does nothing for an event with no
## usable recording, so a missing file costs a warning at startup rather than an
## error on every hit.
func play_at(event: StringName, position: Vector3) -> void:
	var stream: AudioStream = _pick(event)
	if stream == null or _positional.is_empty():
		return
	# Round-robin rather than "first free": the oldest voice is the one whose tail
	# is least missed, and it needs no scan.
	var player: AudioStreamPlayer3D = _positional[_next_positional]
	_next_positional = (_next_positional + 1) % _positional.size()
	player.stream = stream
	player.global_position = position
	player.volume_db = GameSettings.sfx_volume_db
	player.pitch_scale = _jittered_pitch()
	player.play()


## Plays `event` without a position - for things that happen to the player rather
## than somewhere on the map.
func play(event: StringName) -> void:
	var stream: AudioStream = _pick(event)
	if stream == null or _flat.is_empty():
		return
	var player: AudioStreamPlayer = _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	player.stream = stream
	player.volume_db = GameSettings.sfx_volume_db
	player.pitch_scale = _jittered_pitch()
	player.play()


## The recording to use for this trigger, or null if the event has none left to give
## - either it has no files at all, or it already fired this instant.
func _pick(event: StringName) -> AudioStream:
	var streams: Array = _streams.get(event, [])
	if streams.is_empty():
		return null
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - float(_last_played.get(event, -999.0)) < GameSettings.sfx_min_retrigger:
		return null
	_last_played[event] = now

	if streams.size() == 1:
		return streams[0]
	var previous: int = int(_last_variant.get(event, -1))
	var index: int = randi() % streams.size()
	if index == previous:
		index = (index + 1) % streams.size()
	_last_variant[event] = index
	return streams[index]


## A little detune per trigger, so the same two recordings stop reading as a loop
## once the player has heard them a few hundred times.
func _jittered_pitch() -> float:
	return 1.0 + randf_range(-GameSettings.sfx_pitch_jitter, GameSettings.sfx_pitch_jitter)


## Hangs a sustained voice for `event` on `emitter`, so it plays from wherever that
## node is for as long as it lives. Kept out of the one-shot pool: a pooled voice is
## recycled by the next impact, which is exactly wrong for something meant to hold.
##
## Returns the player, so a caller that needs to stop or retune it can.
func attach_loop(event: StringName, emitter: Node3D) -> AudioStreamPlayer3D:
	var streams: Array = _streams.get(event, [])
	if streams.is_empty() or not is_instance_valid(emitter):
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = "Ambience_" + String(event)
	player.stream = streams[0]
	player.volume_db = GameSettings.sfx_ambience_volume_db
	player.max_distance = GameSettings.sfx_ambience_max_distance
	player.unit_size = GameSettings.sfx_unit_size
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	emitter.add_child(player)
	# Started here rather than through `autoplay`, which only fires for a node that
	# was already in the scene when it loaded - this one is hung on at runtime.
	player.play()
	return player
