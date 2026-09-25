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
const MUSIC_ROOT := "res://assets/music/"

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

	# --- Spells -----------------------------------------------------------------
	#
	# Named for the SKILL rather than for the noise, which is the opposite of the rule
	# above and deliberately so: a swing is a swing whoever makes it, but nothing else
	# in the game sounds like Zombify. Sharing these would be a lie about what the
	# player just did.
	&"spell_cast": ["magic/magic-missle-cast.wav"],
	&"spell_missile_impact": ["magic/magic-missle-impact1.wav", "magic/magic-missle-impact2.wav"],
	&"spell_unsummon": ["magic/unsummon.wav"],
	&"spell_frostwave": ["magic/frostwave1.wav", "magic/frostwave2.wav"],
	&"spell_frost_globe": ["magic/frost-globe.wav"],
	&"spell_suction": ["magic/suction.wav"],
	## GUESSED MAPPING: the recording is a violent howling gale and Fear is the closest
	## thing in the roster to terror sweeping outward. Unsummon already has a file of its
	## own, which is why the gale did not go there. One line to move if it belongs
	## somewhere else - the file keeps its neutral name for exactly that reason.
	&"spell_fear": ["magic/howling-gale.wav"],
	&"spell_kill": ["magic/kill.wav"],
	&"spell_zombify": ["magic/zombify.wav"],
	&"spell_lightning_bolt": ["lightning-bolt.wav"],
	## The two sustained spells. Both are held for as long as their effect lasts, so
	## both are attached rather than fired - see LOOPING_EVENTS.
	&"spell_rain_ember": ["magic/rain-of-ember-repeatable.wav"],
	&"spell_fire_cone": ["magic/fire-cone-repeatable.wav"],

	# --- Generated takes --------------------------------------------------------
	#
	# Written by tools/generate_sfx.py from the prompts in tools/sfx_prompts.json.
	# Several takes exist per event; the path below is the CHOSEN one, and
	# tools/apply_sfx_picks.py rewrites these lines from the audition page's output so
	# swapping a take is never a hand edit. Do not reformat between the markers.
	# BEGIN GENERATED PICKS
	## white_1 Exalted Strike
	&"spell_exalted_strike": ["generated/spell_exalted_strike/spell_exalted_strike_3.mp3"],
	## white_2 Circle of Protection
	&"spell_circle_protection": ["generated/spell_circle_protection/spell_circle_protection_3.mp3"],
	## white_3 Reprisal Ward
	&"spell_reprisal_ward": ["generated/spell_reprisal_ward/spell_reprisal_ward_3.mp3"],
	## white_4 Wrath of God
	&"spell_wrath_of_god": ["generated/spell_wrath_of_god/spell_wrath_of_god_2.mp3"],
	## white_5 Rally the Fallen
	&"spell_rally_fallen": ["generated/spell_rally_fallen/spell_rally_fallen_3.mp3"],
	## Former blue_5 Phantasmal Decoy sound, kept for older references.
	&"spell_decoy": ["generated/spell_decoy/spell_decoy_1.mp3"],
	## black_1 Doom Blade
	&"spell_doom_blade": ["generated/spell_doom_blade/spell_doom_blade_2.mp3"],
	## black_4 Wall of Souls
	&"spell_wall_of_souls": ["generated/spell_wall_of_souls/spell_wall_of_souls_3.mp3"],
	## red_1 Fireball, the burst
	&"spell_fireball_impact": ["generated/spell_fireball_impact/spell_fireball_impact_3.mp3"],
	## red_2 Fire Dash
	&"spell_fire_dash": ["generated/spell_fire_dash/spell_fire_dash_3.mp3"],
	## green_2 Giant Growth
	&"spell_giant_growth": ["generated/spell_giant_growth/spell_giant_growth_3.mp3"],
	## green_3 Fog
	&"spell_fog": ["generated/spell_fog/spell_fog_1.mp3"],
	## green_4 Roar
	&"spell_roar": ["generated/spell_roar/spell_roar_1.mp3"],
	## green_5 Ironbark
	&"spell_ironbark": ["generated/spell_ironbark/spell_ironbark_1.mp3"],
	## Shared team level-up chime.
	&"level_up": ["generated/level_up/level_up_1.mp3"],
	## Skill tree node unlock chime.
	&"skill_unlock": ["generated/skill_unlock/skill_unlock_1.mp3"],
	## Incoming hit absorbed by the player's guard, selected by enemy weapon class.
	&"block_impact_blunt": ["generated/block_impact_blunt/block_impact_blunt_1.mp3"],
	&"block_impact_arrow": ["generated/block_impact_arrow/block_impact_arrow_1.mp3"],
	&"block_impact_magic": ["generated/block_impact_magic/block_impact_magic_1.mp3"],
	## Aura choice: Winter Orb
	&"aura_orb_frost": ["generated/aura_orb_frost/aura_orb_frost_2.mp3"],
	## Aura: Orb of Fire
	&"aura_orb_fire": ["generated/aura_orb_fire/aura_orb_fire_2.mp3"],
	## Aura: Healing Orb
	&"aura_orb_heal": ["generated/aura_orb_heal/aura_orb_heal_3.mp3"],
	## Aura: Grave Pact
	&"aura_grave_pact": ["generated/aura_grave_pact/aura_grave_pact_2.mp3"],
	## One arrival per boss. They are five different creatures wearing five different
	## models (BossDatabase.VISUAL_SCENES), so one shared horn blast for all of them was
	## exactly why none of them sounded like itself.
	## Red boss: Fire Giant
	&"boss_spawn_red": ["generated/boss_spawn_red/boss_spawn_red_2.mp3"],
	## Blue boss: Frost Giant
	&"boss_spawn_blue": ["generated/boss_spawn_blue/boss_spawn_blue_1.mp3"],
	## Green boss: Treant
	&"boss_spawn_green": ["generated/boss_spawn_green/boss_spawn_green_3.mp3"],
	## White boss: Paladin
	&"boss_spawn_white": ["generated/boss_spawn_white/boss_spawn_white_1.mp3"],
	## Black boss: Zombie Lord
	&"boss_spawn_black": ["generated/boss_spawn_black/boss_spawn_black_1.mp3"],
	# END GENERATED PICKS
}

## Events that sustain instead of firing once, and are therefore the only ones
## allowed to keep a loop. The loop itself is set on the IMPORT (`edit/loop_mode=2`
## in the matching .wav.import, forward) rather than here, so the engine loops the
## sample seamlessly instead of restarting it on a `finished` signal. Note the
## importer's enum is offset from the runtime one: 0 there means "detect from the
## WAV file", 1 disabled, 2 forward.
## Events the whole map hears, rather than only whoever is standing near them.
##
## The rule is PHYSICAL SCALE, not gameplay importance: thunder carries across a valley
## and a colossus arriving shakes the ground, so both carry here. It is deliberately a
## short list - if everything is global then nothing stands out, and the point of these is
## that they make players look up.
##
## `heavy_landing` is the interesting omission. It is enormous, but it is shared between
## the boss special's impact and the player's own Titanic Brawl, which comes off an eight
## second cooldown - making it global would turn the most frequent green skill into the
## loudest thing on the map.
const GLOBAL_EVENTS: Array[StringName] = [
	&"boss_spawn_white", &"boss_spawn_blue", &"boss_spawn_black",
	&"boss_spawn_red", &"boss_spawn_green",
	&"spell_lightning_bolt",
	&"spell_wrath_of_god",
]

const LOOPING_EVENTS: Array[StringName] = [
	&"crystal_ambience",
	## Rain of Ember burns for as long as its zone stands and Fire Cone for as long as
	## the button is held. Both recordings are short and seamless, so they hold the
	## moment by looping rather than by being long enough to cover the worst case.
	&"spell_rain_ember",
	&"spell_fire_cone",
]

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
## Kept apart from `_positional` rather than being the same voices with different
## settings: the whole reason these exist is that the ordinary pool recycles too fast to
## let a four-second arrival finish.
var _global: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer = null
var _gameplay_music: bool = false
## Every gameplay track, in the order they will be played. Shuffled, walked through once,
## then shuffled again - see _next_gameplay_path for why a bag rather than a dice roll.
var _gameplay_playlist: PackedStringArray = PackedStringArray()
var _playlist_position: int = 0
## Carried across reshuffles so a track cannot follow itself over the seam.
var _last_track: String = ""
var _next_positional: int = 0
var _next_flat: int = 0
var _next_global: int = 0

## The menu theme, and the one track that is NOT in the gameplay shuffle: it is the sound
## of the main menu, and hearing it mid-wave reads as the game having fallen back to the
## title screen.
const TITLE_TRACK := "main-title.mp3"

## What counts as music in MUSIC_ROOT. Everything else in that folder is ignored.
const MUSIC_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]


func _ready() -> void:
	_load_streams()
	_build_pools()
	_build_gameplay_playlist()
	_setup_title_music()


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
	for i in GameSettings.sfx_global_voices:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = GameSettings.sfx_global_max_distance
		player.unit_size = GameSettings.sfx_global_unit_size
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_global.append(player)
	for i in GameSettings.sfx_flat_voices:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat.append(player)


## Every track in MUSIC_ROOT except the title theme, discovered rather than listed.
##
## Read off the directory so that dropping a new mp3 into assets/music/ is the whole job.
## The alternative is a hand-maintained table, which is wrong the moment somebody adds a
## file and forgets - and that is exactly what happened here: the old day/night tables
## named four tracks while twenty sat on disk.
func _build_gameplay_playlist() -> void:
	var found: Dictionary = {}
	for entry: String in DirAccess.get_files_at(MUSIC_ROOT):
		# An exported build hands back the import bookkeeping rather than the source file,
		# so the real name is underneath one of these suffixes.
		var file_name: String = entry
		if file_name.ends_with(".import") or file_name.ends_with(".remap"):
			file_name = file_name.get_basename()
		if not MUSIC_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		if file_name == TITLE_TRACK:
			continue
		found[file_name] = true

	var names: Array = found.keys()
	# Sorted before shuffling, so the pool does not depend on the order the filesystem
	# happened to hand the files back.
	names.sort()
	_gameplay_playlist = PackedStringArray(names)
	if _gameplay_playlist.is_empty():
		push_warning("No gameplay music found in %s; only the title theme will play" % MUSIC_ROOT)
		return
	_shuffle_playlist()


## Reshuffles, and makes sure the new order does not open with the track that just played.
func _shuffle_playlist() -> void:
	var names: Array = Array(_gameplay_playlist)
	names.shuffle()
	if names.size() > 1 and String(names[0]) == _last_track:
		names.push_back(names.pop_front())
	_gameplay_playlist = PackedStringArray(names)
	_playlist_position = 0


## The next track, drawn from a bag rather than rolled.
##
## Random-with-replacement is random on paper and clumpy in the ear: over a long run it
## will play the same track twice in a row and leave others unheard for an hour. Shuffling
## the whole set and walking it means every track is heard once before any is heard twice,
## which is what "play them all randomly" means to a listener.
func _next_gameplay_path() -> String:
	if _gameplay_playlist.is_empty():
		return ""
	if _playlist_position >= _gameplay_playlist.size():
		_shuffle_playlist()
	var track_name: String = _gameplay_playlist[_playlist_position]
	_playlist_position += 1
	_last_track = track_name
	return MUSIC_ROOT + track_name


func _load_music_stream() -> AudioStream:
	var path: String = _next_gameplay_path() if _gameplay_music else MUSIC_ROOT + TITLE_TRACK
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		push_warning("Music track '%s' is missing; music will be silent" % path)
		return null
	# Loaded one at a time rather than all at once: twenty mp3s held open is a lot of
	# memory for a thing that plays one of them.
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("'%s' did not load as an AudioStream" % path)
		return null
	return stream


## Switches from the menu theme to the shuffled gameplay playlist. Idempotent: called
## again while gameplay music is already running it does nothing, so it can never cut a
## track off partway through.
##
## Day and night no longer choose the music. There were two day tracks and two night ones
## picked by phase, and every dawn and dusk interrupted whatever was playing to swap them.
## With every track in one shuffled pool there is nothing to swap to and no reason to cut
## anything short, so DayNightPacing.phase_changed is no longer wired to audio at all.
func start_gameplay_music() -> void:
	if _gameplay_music:
		return
	_gameplay_music = true
	if _music_player == null:
		_setup_title_music()
		return
	var stream: AudioStream = _load_music_stream()
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.play()


func _setup_title_music() -> void:
	if _music_player != null:
		_apply_music_settings()
		return

	var stream: AudioStream = _load_music_stream()
	if stream == null:
		return

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "TitleMusicPlayer"
	_music_player.stream = stream
	_music_player.autoplay = false
	_music_player.bus = "Master"
	# One track ends, the next begins. In gameplay that is the next entry in the shuffled
	# playlist; on the menu it is the title theme again, which simply loops.
	_music_player.finished.connect(func() -> void:
		if not GameSettings.music_enabled or _music_player == null:
			return
		if _gameplay_music:
			var next_stream: AudioStream = _load_music_stream()
			if next_stream != null:
				_music_player.stream = next_stream
		if _music_player.stream != null:
			_music_player.play()
	)
	add_child(_music_player)
	_apply_music_settings()


func apply_music_settings() -> void:
	if _music_player == null:
		_setup_title_music()
	if _music_player == null:
		return
	_apply_music_settings()


func _apply_music_settings() -> void:
	if _music_player == null:
		return
	if GameSettings.music_enabled:
		_music_player.volume_db = GameSettings.music_volume_db
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()


## Plays `event` at a point on the map. Silently does nothing for an event with no
## usable recording, so a missing file costs a warning at startup rather than an
## error on every hit.
func play_at(event: StringName, position: Vector3) -> void:
	var stream: AudioStream = _pick(event)
	if stream == null:
		return

	# Round-robin rather than "first free": the oldest voice is the one whose tail
	# is least missed, and it needs no scan.
	var player: AudioStreamPlayer3D
	if GLOBAL_EVENTS.has(event) and not _global.is_empty():
		player = _global[_next_global]
		_next_global = (_next_global + 1) % _global.size()
	elif not _positional.is_empty():
		player = _positional[_next_positional]
		_next_positional = (_next_positional + 1) % _positional.size()
	else:
		return
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
## `ambience` picks which of the two voicings this loop wants. The crystal's note is
## meant to sit under everything and carry across the map; a spell that is burning right
## where the player is standing is a foreground sound at ordinary effect range. Passing
## the crystal's settings to a firestorm made it both too quiet and audible from the far
## side of the pentagon.
func attach_loop(event: StringName, emitter: Node3D, ambience: bool = true) -> AudioStreamPlayer3D:
	var streams: Array = _streams.get(event, [])
	if streams.is_empty() or not is_instance_valid(emitter):
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = "Loop_" + String(event)
	player.stream = streams[0]
	player.volume_db = GameSettings.sfx_ambience_volume_db if ambience else GameSettings.sfx_volume_db
	player.max_distance = GameSettings.sfx_ambience_max_distance if ambience else GameSettings.sfx_max_distance
	player.unit_size = GameSettings.sfx_unit_size
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	emitter.add_child(player)
	# Started here rather than through `autoplay`, which only fires for a node that
	# was already in the scene when it loaded - this one is hung on at runtime.
	player.play()
	return player
