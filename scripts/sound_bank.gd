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
	## blue_5 Phantasmal Decoy
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
	## Capstone: Orb of Frost
	&"aura_orb_frost": ["generated/aura_orb_frost/aura_orb_frost_2.mp3"],
	## Capstone: Orb of Fire
	&"aura_orb_fire": ["generated/aura_orb_fire/aura_orb_fire_2.mp3"],
	## Capstone: Healing Orb
	&"aura_orb_heal": ["generated/aura_orb_heal/aura_orb_heal_3.mp3"],
	## Capstone: Grave Pact
	&"aura_grave_pact": ["generated/aura_grave_pact/aura_grave_pact_2.mp3"],
	## One arrival per boss. They are five different creatures wearing five different
	## models (BossDatabase.VISUAL_SCENES), so one shared horn blast for all of them was
	## exactly why none of them sounded like itself.
	## Red boss: Fire Giant
	&"boss_spawn_red": ["generated/boss_spawn_red/boss_spawn_red_2.mp3"],
	## Blue boss: Frost Giant
	&"boss_spawn_blue": ["generated/boss_spawn_blue/boss_spawn_blue_1.mp3"],
	## Green boss: Treant
	&"boss_spawn_green": ["generated/boss_spawn_green/boss_spawn_green_1.mp3"],
	## White boss: Paladin
	&"boss_spawn_white": ["generated/boss_spawn_white/boss_spawn_white_2.mp3"],
	## Black boss: Zombie Lord
	&"boss_spawn_black": ["generated/boss_spawn_black/boss_spawn_black_2.mp3"],
	# END GENERATED PICKS
}

## Events that sustain instead of firing once, and are therefore the only ones
## allowed to keep a loop. The loop itself is set on the IMPORT (`edit/loop_mode=2`
## in the matching .wav.import, forward) rather than here, so the engine loops the
## sample seamlessly instead of restarting it on a `finished` signal. Note the
## importer's enum is offset from the runtime one: 0 there means "detect from the
## WAV file", 1 disabled, 2 forward.
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
