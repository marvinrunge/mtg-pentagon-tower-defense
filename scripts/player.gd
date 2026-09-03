extends CharacterBody3D
class_name Player

@export var speed: float = GameSettings.player_base_speed
@export var jump_velocity: float = GameSettings.player_jump_velocity
@export var mouse_sensitivity: float = GameSettings.player_mouse_sensitivity
@export var rotation_speed: float = 10.0
@export var projectile_scene: PackedScene = preload("res://scenes/misc/projectile.tscn")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var camera_pivot: Node3D
var camera: Camera3D

# --- Camera shake ---
# Applied as a local offset on the camera itself, which hangs off a ShakePivot rather
# than off the SpringArm3D directly (see setup_camera) - so the offset survives the
# frame, and still never fights the arm's collision handling the way shaking the orbit
# pivot or the arm length would.
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_phase: float = 0.0

# --- RPG Stats ---
var hp: float = GameSettings.player_max_hp
var max_hp: float = GameSettings.player_max_hp

var is_at_base: bool = false

# --- MTG 5-Color State ---
## The colour whose branch the tree last highlighted. PURELY COSMETIC now: it used to
## decide which five spells the hotbar showed, which is what made every build mono-colour.
var chosen_color_path: String = ""
var unlocked_spells_in_path: Array[String] = []
## spell id -> rank, 1 to GameSettings.spell_max_rank. Absent means not owned. This is the
## source of truth; `unlocked_spells_in_path` is kept beside it for the code that only
## asks "do I have this at all".
var spell_ranks: Dictionary = {}
## What each of the five hotbar keys casts, chosen by the PLAYER rather than derived from
## a colour. Empty means the slot is free.
##
## This is what makes multicolour builds real: a red main can carry Fireball, Fire Dash
## and Rain of Ember and still keep a slot for blue's Frostwave, because the slots are a
## loadout and not a view of one branch of the tree.
var quick_slots: Array[String] = ["", "", "", "", ""]
## The rank of the spell currently being cast. Set once where the cast starts and read by
## the cast functions, rather than threaded through twenty-five signatures - every one of
## them would have to pass it down to the same three helpers anyway.
var _casting_rank: int = 1
## Exalted Strike and Fire Dash both outlive the cast that started them - the first waits
## for a melee hit, the second keeps dropping fire for a third of a second - so both
## resolve their numbers AT CAST TIME rather than reading _casting_rank later, when
## another spell may have moved it.
var _exalted_damage_mult: float = 1.0
var _exalted_reach_bonus: float = 0.0
var _dash_trail_dps: float = 0.0
var _dash_trail_duration: float = 0.0
var _dash_trail_radius: float = 0.0
var unlocked_capstone_aura: String = ""
var affinity_ranks: Dictionary = {
	"white": 0,
	"blue": 0,
	"black": 0,
	"red": 0,
	"green": 0,
}

# --- Spell Charging State ---
var is_charging: bool = false
var charge_timer: float = 0.0
var charge_max_time: float = 2.0
var charging_spell_id: String = ""

# --- Temporary Buffs & Combo Timers ---
## Seconds of Titanic Leap still in the air. While it runs the player's own movement
## input is suspended so the launch impulse carries them, instead of being overwritten
## by the ordinary per-frame velocity assignment.
var _leap_timer: float = 0.0
var last_spell_cast_time: float = -999.0
var rhystic_shield: float = 0.0
var glorious_anthem_shield: float = 0.0
var _applied_capstone_aura: String = ""
var _applied_green_affinity_rank: int = -1

var active_spell_index: int = 0

# --- Buffs & Timers ---
var is_giant: bool = false
var giant_timer: float = 0.0
var base_scale: Vector3 = Vector3.ONE

var slow_timer: float = 0.0

# --- Skill roster state (docs/SKILL_DESIGN.md) ---
## Exalted Strike (white_1). Spent by melee HITS rather than by time, so the buff cannot
## be wasted by walking around with it.
var exalted_charges: int = 0
## Circle of Protection (white_2). A third shield pool beside the two capstone ones, kept
## separate so a capstone re-sync cannot wipe a shield the player just cast.
var protection_shield: float = 0.0
## Reprisal Ward (white_3). The two fractions are resolved at cast time and read back
## in take_damage, because a buff with a duration outlives the cast that set it.
var _reprisal_timer: float = 0.0
var _reprisal_reflect: float = 0.0
var _reprisal_block_chance: float = 0.0
## Ironbark (green_5). The only CC immunity in the game.
var _ironbark_timer: float = 0.0
var _ironbark_reduction: float = 0.0
## Giant Growth (green_2). `is_giant` / `giant_timer` / `base_scale` are declared above -
## they were stubbed long before the skill existed. This is the health half.
var _giant_bonus_hp: float = 0.0
var _applied_giant_bonus: float = -1.0
## Fire Dash (red_2). Seconds of dash left; drives movement the way _leap_timer does.
var _dash_timer: float = 0.0
var _dash_trail_timer: float = 0.0
## Fire Cone (red_4). The only HELD spell: it runs while the button is down.
var _channel_id: String = ""
var _channel_timer: float = 0.0
## The rank the channel was started at. Fire Cone pays out per frame for seconds, so it
## cannot read _casting_rank - anything cast in between would move it.
var _channel_rank: int = 1
## Whether the button that started the channel is one this can watch for a release.
var _channel_held: bool = false
var _channel_fx: Node3D = null
## Grave Pact (black capstone). Stacks decay if the player stops killing, which is the
## whole design - it pays aggression rather than existence.
var _grave_stacks: int = 0
var _grave_stack_timer: float = 0.0
## The orbiting orb, for whichever of the three Manifestations owns one.
var _capstone_orb: Node3D = null
## Points earned from team levels and from Upkeep purchases, and how many are already
## committed in the tree. Personal: the team levels together, but nobody spends your
## points for you.
var skill_points: int = 0
var spent_skill_points: int = 0

# --- Spell Cooldowns ---
var spell_cooldown_timers: Dictionary = {}

# --- Crosshair cache ---

# --- Respawn invulnerability ---
var _invulnerable_timer: float = 0.0

# --- Interaction notifications ---
var _notification_text: String = ""
var _notification_timer: float = 0.0
var _last_input_was_gamepad: bool = false

# --- Downed & Revive State ---
var is_downed: bool = false
var down_timer: float = 0.0

# --- Melee Combo State ---
## Swings fire on the button's RELEASE: a tap is a LIGHT attack, a release after at
## least GameSettings.player_heavy_hold_time is a HEAVY one.
##
## There are exactly two melee moves. The heavy is a single committed spin. The
## light is a CHAIN: one stored multi-hit flourish, spent one stage per click, so a
## single tap plays the opening stage and fades back to the resting pose while a
## second well-timed tap continues into the next stage instead of restarting. The
## clip is split into its stages by PlayerAnimator.combo_windows().
##
## Unlocking the chain extension in the skill tree swaps the two-stage clip for a
## three-stage one whose last stage lands harder.
const LIGHT_CHAIN_CLIP := "combo_3"
const LIGHT_CHAIN_STAGES := 2
const LIGHT_CHAIN_CLIP_EXTENDED := "combo_2"
const LIGHT_CHAIN_STAGES_EXTENDED := 3
## The third stage and beyond, i.e. only ever the last stage of the extended chain.
const LIGHT_CHAIN_HEAVY_STAGE := 2
const HEAVY_CLIP := "spin_high"

var animator: PlayerAnimator

## Set by the skill tree: lengthens the light chain from two stages to three.
var melee_combo_extended: bool = false

## How many stages of the light chain have been spent. Reset by anything that breaks
## the chain, so the next click starts it over from its opening stage.
var _combo_stage: int = 0
## Seconds the heavy attack's wind-up has been held, or -1 when none is. Once the
## hold makes a heavy inevitable there is nothing left to wait for, so the wind-up
## starts then rather than on release - see _update_heavy_charge.
var _heavy_charge_timer: float = -1.0
## Seconds the attack button has been held, or -1 when it is not down. The swing
## fires on RELEASE, and how long it was held is what picks light versus heavy.
var _attack_hold_timer: float = -1.0
## A resolved-but-not-yet-startable swing ("L"/"H"), held for
## player_attack_buffer_time so a release that lands just before the combo window
## opens still connects instead of being silently dropped.
var _buffered_swing: String = ""
var _buffered_swing_timer: float = 0.0
## Seconds of committed action left, and how long the commitment was. A swing and a
## cast are the same thing here. Kept in Player rather than read back off the
## animator so gameplay has one source of truth.
var _action_timer: float = 0.0
var _action_duration: float = 0.0
var _action_elapsed: float = 0.0
## True while the committed move holds the player in place.
var _action_roots_player: bool = false
## Only a melee action can be chained out of inside the combo window; a cast's tail
## must not become a free combo step.
var _action_is_melee: bool = false
## Impact moments still to pay out for the swing in flight, earliest first.
var _pending_hits: Array[float] = []
var _attack_damage_mult: float = 1.0
## What the move in flight sounds like: the swing through the air, played the moment
## it starts, and the impact, played on each frame that actually connects. A miss is
## just the first with nothing after it. Chosen where the move is started rather than
## derived from the damage multiplier, because the kick is a boot rather than a blade
## while dealing nothing like an enemy club's damage.
var _attack_swing_sound: StringName = &"blade_swing"
var _attack_impact_sound: StringName = &"blade_hit"
## How hard a connecting impact kicks the camera. Chosen alongside the sounds, for
## the same reason: it is a property of the move, not of its damage number.
var _attack_shake_strength: float = 0.0
## The spell whose wind-up is playing, and when in the action it actually goes off.
## Empty when no cast is in flight. Like melee damage, the effect lands on the clip's
## measured release frame rather than on the keypress.
var _pending_cast_id: String = ""
var _pending_cast_time: float = 0.0
var _pending_cast_charge: float = 1.0
## The chain lapses if nothing continues it, so a stage landed a minute ago isn't
## still counted as step one.
var _combo_reset_timer: float = 0.0

var is_blocking: bool = false
var _stagger_timer: float = 0.0
var _hit_react_cooldown: float = 0.0

## True for the player this machine drives. Only the local player reads the keyboard,
## owns the camera and captures the mouse - every other player on screen is a puppet
## moved by replication (see docs/MULTIPLAYER_PLAN.md, Phase 0).
##
## Set before the node enters the tree by whoever spawns it; a player spawned with no
## opinion assumes it is local, so single-player and tools keep working unchanged.
var is_local: bool = true


func _ready() -> void:
	add_to_group("player")
	animator = $Animator
	if Net.is_active():
		# Networked: the peer that owns this avatar drives it, everyone else runs it as a
		# puppet. Authority was set by MainController._spawn_avatar, which runs on every
		# peer - so is_local is DERIVED from it rather than tracked separately, and the
		# two can never disagree.
		is_local = is_multiplayer_authority()
		_build_synchronizer()
	elif has_meta("is_local"):
		is_local = bool(get_meta("is_local"))
	PlayerRegistry.register(self, is_local)
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	setup_camera()
	
	# A skill tree is PERSONAL. These signals carry no owner, so every avatar in the
	# scene would answer them - one player's purchase would unlock the spell on all four
	# remote puppets too. Only the avatar the tree belongs to listens.
	if is_local:
		SignalBus.skill_unlocked.connect(_on_skill_unlocked)
		SignalBus.spell_unlocked.connect(_on_spell_unlocked)
		SignalBus.melee_combo_unlocked.connect(_on_melee_combo_unlocked)
	
	# Delay emitting the initial active spell until the HUD is ready
	call_deferred("_emit_initial_spell")

func _emit_initial_spell() -> void:
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	camera_pivot.position = Vector3(
		GameSettings.player_camera_shoulder_offset,
		GameSettings.player_camera_height,
		0.0
	)

	var spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = GameSettings.player_camera_distance
	# The orbit height is the pivot's alone - the arm used to carry a second, hidden
	# +0.2 of its own, which made the framing two knobs instead of one.
	spring_arm.position = Vector3.ZERO
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.add_child(spring_arm)

	# A SpringArm3D REWRITES the transform of its direct children every frame, parking
	# them at (0, 0, current_spring_length) so collision can pull them in. The camera
	# used to be that direct child, so every shake offset written onto it was wiped
	# before it could be seen - the shake has been running and invisible. This node
	# takes the arm's rewriting instead, and the camera hangs off it with nothing but
	# the shake touching its own local position.
	var shake_pivot := Node3D.new()
	shake_pivot.name = "ShakePivot"
	spring_arm.add_child(shake_pivot)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 0, 0)
	shake_pivot.add_child(camera)
	# Exactly one camera may be current. Every player still builds its own rig - the
	# shake, the spring arm and the aim ray all read from it - but only the local one
	# is what the screen looks through.
	if is_local:
		camera.make_current()

	SignalBus.camera_shake_requested.connect(_on_camera_shake_requested)

## Strongest-wins: a heavy hit landing during a light shake takes over, but a
## light one can't cut short the tail of a heavy one.
func _on_camera_shake_requested(strength: float, duration: float) -> void:
	if not GameSettings.camera_shake_enabled:
		return
	if strength < _shake_strength and _shake_timer > 0.0:
		return
	_shake_strength = strength
	_shake_duration = maxf(duration, 0.01)
	_shake_timer = _shake_duration

func _update_camera_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_timer <= 0.0:
		if camera.position != Vector3.ZERO:
			camera.position = Vector3.ZERO
		return
	_shake_timer -= delta
	_shake_phase += delta * GameSettings.camera_shake_frequency
	# Decay to zero over the shake's life so it settles instead of cutting out.
	var falloff: float = clampf(_shake_timer / _shake_duration, 0.0, 1.0)
	var amplitude: float = _shake_strength * falloff * falloff
	# Two different frequencies per axis keeps it from reading as a clean orbit.
	camera.position = Vector3(
		sin(_shake_phase * 1.7) * amplitude,
		cos(_shake_phase * 2.3) * amplitude,
		0.0
	)
	if _shake_timer <= 0.0:
		camera.position = Vector3.ZERO

## Interact prompts hardcode "[E]" - swap to the gamepad button label when a
## controller was the last input device used, so the prompt matches what's in hand.
func _interact_key_label() -> String:
	return "[X]" if _last_input_was_gamepad else "[E]"

## Shared by mouse-motion look (per-event, already-scaled pixel delta) and the
## gamepad right-stick poll in _physics_process (per-frame, delta-scaled).
func _apply_look_delta(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	camera_pivot.rotate_x(pitch)
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -deg_to_rad(70.0), deg_to_rad(30.0))

## Replicates the least that produces the most: position, rotation and VELOCITY.
##
## Velocity is the one that matters. `PlayerAnimator.update_locomotion()` already picks
## idle, walk, run, strafe and their playback speeds from velocity alone, so sending it
## reconstructs every locomotion animation on every client without replicating a single
## bone. Actions - swings, casts, the heavy charge - are discrete events and are sent as
## RPCs instead, in Phase 2.
func _build_synchronizer() -> void:
	var config := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":velocity"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	# The owner publishes; everyone else listens. Without this every peer would try to
	# author every avatar and they would fight.
	sync.set_multiplayer_authority(get_multiplayer_authority())
	add_child(sync)


func _exit_tree() -> void:
	PlayerRegistry.unregister(self)


func _unhandled_input(event: InputEvent) -> void:
	# A remote player's node exists on this machine but is not driven by this keyboard.
	if not is_local:
		return
	# Ignore small joypad motion (idle stick drift/noise) so this doesn't flicker
	# true just from a controller sitting connected but unused.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		_last_input_was_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_input_was_gamepad = false

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look_delta(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)

	if is_downed:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		if GameSettings.debug_mode:
			if keycode == KEY_F1 or keycode == KEY_M:
				for c: String in RunState.COLORS:
					RunState.add_mana(c, 100)
				print("[DEBUG] Granted +100 of each Mana color!")
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()
			elif keycode == KEY_F2:
				chosen_color_path = ""
				unlocked_spells_in_path.clear()
				spell_ranks.clear()
				reset_quick_slots()
				unlocked_capstone_aura = ""
				for color: String in affinity_ranks:
					affinity_ranks[color] = 0
				_applied_green_affinity_rank = -1
				_sync_capstone_aura()
				SignalBus.color_path_chosen.emit("")
				SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
				print("[DEBUG] Reset all color affinities!")
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()
			elif keycode == KEY_F3:
				var target_color = chosen_color_path if chosen_color_path != "" else "red"
				chosen_color_path = target_color
				affinity_ranks[target_color] = 25
				for i in range(1, 6):
					var sid = target_color + "_" + str(i)
					if not unlocked_spells_in_path.has(sid):
						unlocked_spells_in_path.append(sid)
					# Straight to max: the point of the key is to try a colour out, and a
					# rank-1 version of it is not the thing being tried.
					spell_ranks[sid] = GameSettings.spell_max_rank
					var free_slot: int = first_free_quick_slot()
					if free_slot >= 0:
						assign_quick_slot(free_slot, sid)
				_applied_green_affinity_rank = -1
				_sync_capstone_aura()
				SignalBus.color_path_chosen.emit(target_color)
				SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
				print("[DEBUG] Unlocked full path for: " + target_color)
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()

		if keycode == KEY_K or keycode == KEY_N:
			var st = get_tree().current_scene.get_node_or_null("SkillTree")
			if st:
				st.visible = not st.visible
				if st.visible:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					if st.has_method("update_ui"):
						st.update_ui()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cycle_spell(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cycle_spell(1)

		# "cast_spell" covers both right-mouse-button and the gamepad left trigger.
		if event.is_action_pressed("cast_spell"):
			cast_active_spell()
		elif event.is_action_released("cast_spell") and is_charging:
			release_charged_spell()

		if event.is_action_pressed("cycle_spell_prev"):
			cycle_spell(-1)
		elif event.is_action_pressed("cycle_spell_next"):
			cycle_spell(1)

		# Number keys are a real hotbar: they select AND cast, which is what the five
		# slots the HUD already draws look like they do. They mirror "cast_spell"
		# exactly, press and release, so a chargeable spell charges while the key is
		# held and fires when it comes up - otherwise 1-5 could start a charge with
		# no way to release it.
		if event is InputEventKey and not event.echo:
			var keycode: int = event.keycode
			if keycode >= KEY_1 and keycode <= KEY_5:
				var target_idx: int = keycode - KEY_1
				if event.pressed:
					if is_spell_unlocked(target_idx):
						if active_spell_index != target_idx:
							active_spell_index = target_idx
							SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
						cast_active_spell()
				elif is_charging and charging_spell_id == _get_spell_id_for_slot(target_idx):
					release_charged_spell()

func cycle_spell(dir: int) -> void:
	var original_index = active_spell_index
	var max_spells = quick_slots.size()
	
	active_spell_index = (active_spell_index + dir) % max_spells
	if active_spell_index < 0:
		active_spell_index += max_spells
		
	var attempts = 0
	while not is_spell_unlocked(active_spell_index) and attempts < max_spells:
		active_spell_index = (active_spell_index + dir) % max_spells
		if active_spell_index < 0:
			active_spell_index += max_spells
		attempts += 1
			
	if active_spell_index != original_index:
		SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func _get_spell_id_for_slot(slot_idx: int) -> String:
	if slot_idx < 0 or slot_idx >= quick_slots.size():
		return ""
	return String(quick_slots[slot_idx])


## Binds a spell to one of the five hotbar keys. Owning it is the only requirement - any
## spell in any colour can go in any slot.
##
## A spell already sitting in another slot SWAPS with whatever is in the target, rather
## than appearing twice: two keys casting the same thing is never what anyone meant, and
## a silent removal from the old slot is worse than a swap the player can see.
func assign_quick_slot(slot_idx: int, spell_id: String) -> bool:
	if slot_idx < 0 or slot_idx >= quick_slots.size():
		return false
	if spell_id != "" and not is_spell_owned(spell_id):
		return false
	var previous: String = String(quick_slots[slot_idx])
	var existing_slot: int = quick_slots.find(spell_id)
	if existing_slot >= 0 and existing_slot != slot_idx:
		quick_slots[existing_slot] = previous
	quick_slots[slot_idx] = spell_id
	SignalBus.quick_slots_changed.emit()
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
	return true


## The first empty slot, or -1. Used to bind a newly bought spell without asking - a
## player who just spent a point should be able to cast the thing they bought.
func first_free_quick_slot() -> int:
	return quick_slots.find("")


## Empties the bar. A method rather than an assignment at each call site because
## `quick_slots` is an `Array[String]`, and an untyped array literal assigned to it from
## ANOTHER script is a runtime error - the literal only infers its type inside the script
## that declares the property.
func reset_quick_slots() -> void:
	quick_slots.clear()
	for _i: int in range(5):
		quick_slots.append("")
	SignalBus.quick_slots_changed.emit()


func is_spell_owned(spell_id: String) -> bool:
	return get_spell_rank(spell_id) > 0


func get_spell_rank(spell_id: String) -> int:
	return int(spell_ranks.get(spell_id, 0))


## Whether the NEXT rank of this spell is reachable right now, and why not if it is not.
## Returns an empty string when it is buyable, otherwise the reason to show the player -
## the tree prints it verbatim, so "cannot" is never silent.
func spell_rank_blocker(spell_id: String) -> String:
	var rank: int = get_spell_rank(spell_id)
	if rank >= GameSettings.spell_max_rank:
		return "Maximum rank"
	var required_level: int = GameSettings.rank_level_requirement(rank + 1)
	if RunState.team_level < required_level:
		return "Needs team level %d" % required_level
	if not GameSettings.debug_free_skills and skill_points < GameSettings.spell_rank_point_cost:
		return "Needs %d skill point" % GameSettings.spell_rank_point_cost
	return ""


## The rank curves for the spell being cast. Named for what they scale rather than for
## the curve behind them, so a cast reads as "damage times rank" and the shape of that
## relationship stays in GameSettings where a designer can change it once.
func _rank_damage() -> float:
	return GameSettings.rank_damage_mult(_casting_rank)


func _rank_area() -> float:
	return GameSettings.rank_area_mult(_casting_rank)


func _rank_duration() -> float:
	return GameSettings.rank_duration_mult(_casting_rank)


## Adds one rank. The tree charges the point; this only moves the rank, so a debug-free
## purchase and a paid one land in exactly the same state.
func grant_spell_rank(spell_id: String) -> bool:
	if not SpellDatabase.has_spell(spell_id):
		return false
	var rank: int = get_spell_rank(spell_id)
	if rank >= GameSettings.spell_max_rank:
		return false
	spell_ranks[spell_id] = rank + 1
	if rank == 0:
		if not unlocked_spells_in_path.has(spell_id):
			unlocked_spells_in_path.append(spell_id)
		# Newly bought spells land on the bar by themselves. A spell you own and cannot
		# cast because every slot is full is a bug report waiting to happen.
		var free_slot: int = first_free_quick_slot()
		if free_slot >= 0:
			assign_quick_slot(free_slot, spell_id)
	SignalBus.spell_rank_changed.emit(spell_id, get_spell_rank(spell_id))
	return true

## Highlights a colour in the tree. It used to REPLACE the hotbar with that colour's five
## spells, which is why a build could only ever be one colour - and why investing a single
## point in a second colour silently threw the first colour's bar away.
##
## Now it only marks which branch the player is looking at. What they cast is their
## loadout, in `quick_slots`.
func select_color_path(color: String) -> void:
	if not affinity_ranks.has(color):
		return
	chosen_color_path = color
	SignalBus.color_path_chosen.emit(color)

func invest_affinity(color: String) -> void:
	if not affinity_ranks.has(color):
		return
	affinity_ranks[color] = int(affinity_ranks[color]) + 1
	select_color_path(color)
	_applied_green_affinity_rank = -1
	_sync_capstone_aura()
	SignalBus.skill_unlocked.emit(color)

func get_affinity_rank(color: String) -> int:
	return int(affinity_ranks.get(color, 0))

func get_affinity_bonus(color: String) -> float:
	var rank: int = get_affinity_rank(color)
	var early_ranks: int = mini(rank, 10)
	var mid_ranks: int = mini(maxi(rank - 10, 0), 10)
	var late_ranks: int = maxi(rank - 20, 0)
	return (
		early_ranks * GameSettings.affinity_rank_bonus_early
		+ mid_ranks * GameSettings.affinity_rank_bonus_mid
		+ late_ranks * GameSettings.affinity_rank_bonus_late
	)

func get_spell_rank_requirement(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= GameSettings.affinity_spell_rank_requirements.size():
		return 999999
	return GameSettings.affinity_spell_rank_requirements[slot_idx]

func on_damage_dealt(amount: float) -> void:
	# Personal affinity plus the team's Exquisite Blood stacks - the enchantment
	# deliberately echoes the colour's own affinity rather than inventing a new axis.
	var lifesteal: float = get_affinity_bonus("black") + RunState.lifesteal_bonus()
	if lifesteal > 0.0 and amount > 0.0:
		heal(amount * lifesteal)

func get_spell_name_for_slot(slot_idx: int) -> String:
	return SpellDatabase.get_display_name(_get_spell_id_for_slot(slot_idx))

func is_spell_unlocked(slot_idx: int) -> bool:
	return is_spell_owned(_get_spell_id_for_slot(slot_idx))

## Melee feeding back into the spell kit: every impact frame that actually connects
## takes `seconds` off every spell on cooldown, so weaving swings between casts is
## worth doing. Deliberately per IMPACT FRAME rather than per enemy struck - paying
## per enemy would make one finisher into a crowd wipe reset the whole bar.
##
## Only spells are refunded. `spell_cooldown_timers` also holds the kick, and letting
## a kick's own impact shorten the kick would make it near-spammable.
func _reduce_spell_cooldowns(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for key in spell_cooldown_timers.keys():
		if not SpellDatabase.has_spell(key):
			continue
		var remaining: float = float(spell_cooldown_timers[key]) - seconds
		if remaining <= 0.0:
			spell_cooldown_timers.erase(key)
		else:
			spell_cooldown_timers[key] = remaining


## Wipes spell cooldowns only. `spell_cooldown_timers` also carries non-spell
## entries - the kick - and a blanket clear() would hand those back for free too.
func _clear_spell_cooldowns() -> void:
	for key in spell_cooldown_timers.keys():
		if SpellDatabase.has_spell(key):
			spell_cooldown_timers.erase(key)

## Cooldowns are flat across ranks with exactly one exception: black's Kill, whose whole
## rank curve IS its cooldown (docs/SKILL_DESIGN.md - "Scales with rank: cooldown, boss
## execute threshold"). An instant delete cannot be made stronger, only more frequent.
func _get_spell_cooldown(spell_id: String) -> float:
	var cooldown: float = SpellDatabase.get_cooldown(spell_id)
	if spell_id == "black_3":
		cooldown *= GameSettings.rank_fraction(
			1.0, GameSettings.spell_black_kill_cooldown_max_rank_mult, get_spell_rank(spell_id)
		)
	return cooldown

func is_chargeable(spell_id: String) -> bool:
	return SpellDatabase.is_chargeable(spell_id)

func cast_active_spell() -> void:
	if is_charging:
		return

	var spell_id = _get_spell_id_for_slot(active_spell_index)
	if spell_id == "":
		return

	if not is_spell_unlocked(active_spell_index):
		return

	var cd = spell_cooldown_timers.get(spell_id, 0.0)
	if cd > 0.0:
		return

	if not _can_start_cast():
		return

	if is_chargeable(spell_id):
		is_charging = true
		charge_timer = 0.0
		charge_max_time = 2.0
		charging_spell_id = spell_id
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, true)
	else:
		_begin_cast(spell_id, 1.0)


## A cast is a committed action like a swing, so it queues behind one rather than
## firing over the top of it. Blocking is not checked: raising the guard already
## requires no action in flight, so starting a cast drops it on the next frame.
func _can_start_cast() -> bool:
	return not is_downed and _stagger_timer <= 0.0 and _action_timer <= 0.0


## Starts a spell's wind-up. The effect itself does not happen here - it fires from
## _update_actions() when the animation reaches the release frame the builder
## measured for that clip, exactly as melee damage lands on its impact frames.
func _begin_cast(spell_id: String, charge_pct: float) -> void:
	var row: Dictionary = SpellDatabase.get_spell(spell_id)
	var clip: String = String(row.get("cast_clip", ""))
	var duration: float = float(row.get("cast_duration", 0.4))
	var roots: bool = bool(row.get("roots", false))

	if clip == "" or not animator.has_clip(clip):
		# No animation for this spell: fall back to the old instant behaviour rather
		# than swallowing the cast.
		push_warning("Spell '%s' has no usable cast clip '%s'; firing instantly" % [spell_id, clip])
		execute_spell(spell_id, charge_pct)
		return

	_casting_rank = get_spell_rank(spell_id)
	_pending_cast_id = spell_id
	_pending_cast_charge = charge_pct
	_pending_cast_time = animator.release_time(clip, duration, bool(row.get("release_on_last", false)))
	# A spell whose animation MOVES the caster has to start moving now, not on the
	# release frame - the release is the payload landing, and by then the leap has to
	# already have carried them there. Fire Dash is the same shape: the release frame
	# lights the trail the dash has by then already drawn.
	match spell_id:
		"green_1": cast_green_titanic_leap()
		"red_2": cast_red_fire_dash()
	_pending_hits.clear()
	# The two halves separately, rather than through _begin_action: a cast may be
	# committed for less time than its animation runs, and a recovery that is still
	# playing after the player has control back is the whole point of `commit`.
	_commit_action(float(row.get("commit", duration)), roots, false)
	animator.play_action(clip, duration, bool(row.get("upper_body", not roots)))

func release_charged_spell() -> void:
	if not is_charging:
		return
		
	var pct = clamp(charge_timer / charge_max_time, 0.2, 1.0)
	var spell_id = charging_spell_id
	is_charging = false
	charge_timer = 0.0
	SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	if not is_spell_owned(spell_id) or spell_cooldown_timers.get(spell_id, 0.0) > 0.0:
		return
	if not _can_start_cast():
		return
	_begin_cast(spell_id, pct)

## The moment a spell's effect actually happens, on the frame its clip releases.
##
## The cooldown and the animation are local and already ran; only the EFFECT needs an
## authority, because a projectile spawned on a client is invisible to everyone else and
## its damage would never reach the server's enemies.
func execute_spell(spell_id: String, charge_pct: float = 1.0) -> void:
	spell_cooldown_timers[spell_id] = _get_spell_cooldown(spell_id)
	if Net.is_active() and not Net.is_server():
		_request_spell.rpc_id(1, spell_id, charge_pct)
		return
	_run_spell_effect(spell_id, charge_pct)


@rpc("any_peer", "call_local", "reliable")
func _request_spell(spell_id: String, charge_pct: float) -> void:
	if not Net.is_server():
		return
	_run_spell_effect(spell_id, charge_pct)


func _run_spell_effect(spell_id: String, charge_pct: float) -> void:
	# A spell cast by a CLIENT arrives here on the server, where _begin_cast never ran -
	# so the rank is resolved again rather than assumed to be left over from the cast.
	_casting_rank = maxi(get_spell_rank(spell_id), 1)
	
	# Rhystic Study Shield trigger on cast
	if unlocked_capstone_aura == "aura_rhystic_study":
		rhystic_shield = minf(
			rhystic_shield + GameSettings.aura_rhystic_study_shield_amount,
			GameSettings.aura_rhystic_study_shield_max
		)
		
	match spell_id:
		# --- WHITE ---
		"white_1": cast_white_exalted_strike()
		"white_2": cast_white_circle_of_protection()
		"white_3": cast_white_reprisal_ward()
		"white_4": cast_white_wrath_of_god()
		"white_5": cast_white_rally_the_fallen()
		# --- BLUE ---
		"blue_1": cast_blue_unsummon()
		"blue_2": cast_blue_frostwave()
		"blue_3": cast_blue_frost_globe()
		"blue_4": cast_blue_suction()
		"blue_5": cast_blue_phantasmal_decoy()
		# --- BLACK ---
		"black_1": cast_black_doom_blade()
		"black_2": cast_black_fear()
		"black_3": cast_black_kill()
		"black_4": cast_black_wall_of_souls()
		"black_5": cast_black_zombify()
		# --- RED ---
		"red_1": cast_red_fireball(charge_pct)
		# The TRAIL, not the launch: the dash itself was already fired when the cast
		# began, exactly like Titanic Leap below.
		"red_2": _lay_fire_trail()
		"red_3": cast_red_rain_ember()
		"red_4": cast_red_fire_cone()
		"red_5": cast_red_lightning_bolt()
		# --- GREEN ---
		# The LANDING, not the launch: the leap itself was already fired when the cast
		# began, and this is the clip's final impact frame arriving.
		"green_1": _slam_ground()
		"green_2": cast_green_giant_growth()
		"green_3": cast_green_fog()
		"green_4": cast_green_roar()
		"green_5": cast_green_ironbark()

	last_spell_cast_time = Time.get_ticks_msec() / 1000.0

# --- RPG Logic ---
func _on_skill_unlocked(color: String) -> void:
	pass

func _on_melee_combo_unlocked() -> void:
	melee_combo_extended = true
	# The chain clip changes underneath, so a half-spent chain would carry its stage
	# count across into a different animation. Start the new one from the top.
	_combo_stage = 0
	_combo_reset_timer = 0.0


func _on_spell_unlocked(color: String, spell_id: String) -> void:
	select_color_path(color)
	grant_spell_rank(spell_id)
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

func take_damage(amount: float, source: Node3D = null, is_melee: bool = false) -> void:
	if _invulnerable_timer > 0.0:
		return

	var can_use_defenses: bool = source != self
	var remaining_damage: float = amount
	# The guard comes first: it should soak the hit before shields are spent on it.
	var was_blocked: bool = can_use_defenses and _blocks_attack_from(source)
	if was_blocked:
		remaining_damage *= 1.0 - GameSettings.player_block_damage_reduction
		animator.play_reaction("block_react", GameSettings.player_block_react_duration)
		if remaining_damage <= 0.0:
			return

	# Reprisal Ward's passive block: a flat chance to turn the hit aside entirely. Rolled
	# BEFORE the reflect, because an attack that never landed cannot be reflected.
	if can_use_defenses and _reprisal_timer > 0.0:
		if randf() < _reprisal_block_chance:
			animator.play_reaction("block_react", GameSettings.player_block_react_duration)
			_spawn_cast_flash(Color(1.0, 0.95, 0.7), 1.6)
			return
		# ...and its active half: the attacker takes a share of what it dealt. Measured
		# on the incoming damage rather than on what survives the shields, so stacking
		# shields with the ward does not quietly turn the reflect off.
		if is_instance_valid(source) and source.has_method("take_damage") and source.is_in_group("enemies"):
			source.take_damage(remaining_damage * _reprisal_reflect, self)

	# Ironbark: the only damage REDUCTION the player has. Applied before the shields so
	# it makes them last longer rather than being wasted on damage they already ate.
	if can_use_defenses and _ironbark_timer > 0.0:
		remaining_damage *= 1.0 - _ironbark_reduction

	if can_use_defenses:
		var absorbed: float = minf(glorious_anthem_shield, remaining_damage)
		glorious_anthem_shield -= absorbed
		remaining_damage -= absorbed
		absorbed = minf(rhystic_shield, remaining_damage)
		rhystic_shield -= absorbed
		remaining_damage -= absorbed
		# Circle of Protection is spent LAST of the three, because it is the only one a
		# player chose to cast - a capstone shield regenerates on its own and this does not.
		absorbed = minf(protection_shield, remaining_damage)
		protection_shield -= absorbed
		remaining_damage -= absorbed

	if remaining_damage <= 0.0:
		return

	hp -= remaining_damage
	SignalBus.player_health_changed.emit(hp, max_hp)
	var spawn_pos = global_position + Vector3(randf_range(-0.2, 0.2), 1.6, randf_range(-0.2, 0.2))
	SignalBus.damage_number_requested.emit(spawn_pos, remaining_damage, Color(1.0, 0.25, 0.25))
	if hp <= 0:
		die()
		return
	if not was_blocked:
		_try_hit_reaction(remaining_damage, source)


## Staggers the player, but only for a hit big enough to be worth it - chip damage
## from a swarm would otherwise leave the character permanently flinching and unable
## to swing back. The cooldown stops a burst of big hits chaining into a lockout.
func _try_hit_reaction(damage: float, source: Node3D) -> void:
	# Ironbark: nothing staggers you. This is the half of the skill players actually
	# feel - a swing that finishes instead of being interrupted.
	if _hit_react_cooldown > 0.0 or is_downed or is_control_immune():
		return
	if damage < max_hp * GameSettings.player_hit_react_damage_pct:
		return
	var from_direction: Vector3 = -transform.basis.z
	if is_instance_valid(source) and source != self:
		from_direction = source.global_position - global_position
	_hit_react_cooldown = GameSettings.player_hit_react_cooldown
	_stagger_timer = GameSettings.player_hit_react_duration
	_cancel_action()
	animator.play_reaction(animator.reaction_clip_for(from_direction), GameSettings.player_hit_react_duration)


## Drops whatever swing is in flight, including any impact frames it hadn't paid
## out yet, and the combo built up so far.
func _cancel_action() -> void:
	_action_timer = 0.0
	_action_duration = 0.0
	_action_roots_player = false
	_action_is_melee = false
	_pending_hits.clear()
	# A cast interrupted before its release frame simply never happens - and since
	# the cooldown is only stamped in execute_spell(), it costs the player nothing.
	_pending_cast_id = ""
	_end_channel()
	if is_charging:
		is_charging = false
		charge_timer = 0.0
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	_combo_stage = 0
	_combo_reset_timer = 0.0
	_cancel_heavy_charge()
	_clear_pending_swing()

## Recomputes maximum health and the capstone's permanent effects from scratch whenever
## one of their inputs moves. Giant Growth is one of those inputs now: it adds flat health
## for a duration, and rebuilding the total rather than adding and subtracting is what
## stops the bonus drifting when the aura changes while the buff is up.
func _sync_capstone_aura() -> void:
	var green_affinity_rank: int = get_affinity_rank("green")
	if (
		_applied_capstone_aura == unlocked_capstone_aura
		and _applied_green_affinity_rank == green_affinity_rank
		and is_equal_approx(_applied_giant_bonus, _giant_bonus_hp)
	):
		return

	var health_ratio: float = hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = GameSettings.player_max_hp
	max_hp *= 1.0 + get_affinity_bonus("green")
	rhystic_shield = 0.0
	glorious_anthem_shield = 0.0
	if unlocked_capstone_aura == "aura_sylvan_library":
		max_hp *= GameSettings.aura_sylvan_library_hp_mult
	elif unlocked_capstone_aura == "aura_glorious_anthem":
		glorious_anthem_shield = GameSettings.aura_glorious_anthem_shield
	max_hp += _giant_bonus_hp
	hp = clampf(max_hp * health_ratio, 1.0, max_hp)
	if _applied_capstone_aura != unlocked_capstone_aura:
		_rebuild_capstone_orb()
	_applied_capstone_aura = unlocked_capstone_aura
	_applied_green_affinity_rank = green_affinity_rank
	_applied_giant_bonus = _giant_bonus_hp
	SignalBus.player_health_changed.emit(hp, max_hp)
	SignalBus.player_capstone_aura_changed.emit()


## Three of the five Manifestations are an orb, and the orb is a real node rather than a
## per-frame effect - so it is created and destroyed here, where the capstone changes,
## and nowhere else.
func _rebuild_capstone_orb() -> void:
	if is_instance_valid(_capstone_orb):
		# remove_child BEFORE queue_free: freeing is deferred to the end of the frame, so
		# the old orb would otherwise still be a child when the new one is added - two
		# orbs at once, and the newcomer silently renamed to "CapstoneOrb2".
		remove_child(_capstone_orb)
		_capstone_orb.queue_free()
		_capstone_orb = null
	var mode: int = -1
	match unlocked_capstone_aura:
		"aura_orb_of_frost": mode = OrbitingOrb.Mode.FROST
		"aura_orb_of_fire": mode = OrbitingOrb.Mode.FIRE
		"aura_healing_orb": mode = OrbitingOrb.Mode.HEAL
	if mode < 0:
		return
	_capstone_orb = OrbitingOrb.create(mode, self)
	add_child(_capstone_orb)


## The one way a capstone is ever taken. Exclusive by construction: the field holds a
## single string, so buying either half of a colour's fork replaces whatever was there -
## which is what makes the choice permanent for the run rather than a shopping list.
func unlock_capstone(capstone_id: String) -> void:
	if capstone_id == "" or unlocked_capstone_aura == capstone_id:
		return
	# ONE capstone per run. Refused here rather than only in the skill tree, because
	# "permanent for the run" is a property of the player and not of the UI that happens
	# to sell it - the debug reset clears the field directly, which is the only way back.
	if unlocked_capstone_aura != "":
		return
	unlocked_capstone_aura = capstone_id
	var color: String = SpellDatabase.get_capstone_color(capstone_id)
	if color != "":
		select_color_path(color)
	# Grave Pact is the one capstone that has to be listening rather than ticking, so it
	# subscribes here instead of in _ready - a player without it should not be walking a
	# signal handler on every enemy death in the wave.
	if capstone_id == "aura_grave_pact":
		if not SignalBus.enemy_died_at.is_connected(_on_enemy_died_near):
			SignalBus.enemy_died_at.connect(_on_enemy_died_near)
	elif SignalBus.enemy_died_at.is_connected(_on_enemy_died_near):
		SignalBus.enemy_died_at.disconnect(_on_enemy_died_near)
	_sync_capstone_aura()


## Grave Pact: a kill near the player leaves a soul - a small heal, and one stack of a
## damage bonus whose timer restarts with every kill. Stop killing and the whole thing
## lapses at once rather than decaying one stack at a time, because a bonus that drains
## away slowly is one the player never notices losing.
func _on_enemy_died_near(position: Vector3) -> void:
	if is_downed or global_position.distance_to(position) > GameSettings.aura_grave_pact_radius:
		return
	heal(GameSettings.aura_grave_pact_heal)
	_grave_stacks = mini(_grave_stacks + 1, GameSettings.aura_grave_pact_max_stacks)
	_grave_stack_timer = GameSettings.aura_grave_pact_stack_duration

func get_spell_damage_multiplier() -> float:
	var affinity_multiplier: float = 1.0 + get_affinity_bonus("red")
	# Grave Pact's stacks multiply into the same term the affinity does, so they scale
	# everything the player does rather than only their melee.
	affinity_multiplier *= 1.0 + float(_grave_stacks) * GameSettings.aura_grave_pact_damage_per_stack
	if unlocked_capstone_aura == "aura_glorious_anthem":
		return GameSettings.aura_glorious_anthem_damage_mult * RunState.damage_multiplier() * affinity_multiplier
	# Furnace of Rath is the team's, so it multiplies whatever this player already has.
	var team_multiplier: float = RunState.damage_multiplier()
	if unlocked_capstone_aura == "aura_phyrexian_arena":
		return GameSettings.aura_phyrexian_arena_damage_mult * team_multiplier * affinity_multiplier
	return team_multiplier * affinity_multiplier

## Levels grant these to every player at once; Upkeep can buy more, also for everyone.
## What each player spends them on is their own business.
func grant_skill_points(amount: int) -> void:
	if amount <= 0:
		return
	skill_points += amount
	SignalBus.skill_points_changed.emit(self, skill_points)


func spend_skill_points(amount: int) -> bool:
	if amount <= 0 or skill_points < amount:
		return false
	skill_points -= amount
	spent_skill_points += amount
	SignalBus.skill_points_changed.emit(self, skill_points)
	return true


func apply_slow(duration: float) -> void:
	if is_control_immune():
		return
	slow_timer = maxf(slow_timer, duration)

func heal(amount: float, show_damage_number: bool = true) -> void:
	if hp >= max_hp:
		return
	hp = min(max_hp, hp + amount)
	SignalBus.player_health_changed.emit(hp, max_hp)
	if show_damage_number:
		var spawn_pos = global_position + Vector3(0, 1.8, 0)
		SignalBus.damage_number_requested.emit(spawn_pos, -amount, Color(0.2, 1.0, 0.4))

func die() -> void:
	if is_downed:
		return
	is_downed = true
	hp = 0.0
	SignalBus.player_health_changed.emit(hp, max_hp)
	_cancel_action()
	is_blocking = false
	_stagger_timer = 0.0
	animator.play_death()

	var total_players = get_tree().get_nodes_in_group("player").size()
	if total_players > 1:
		down_timer = 15.0
		print("Player downed! Can be revived for 15 seconds...")
	else:
		down_timer = 5.0
		print("Player died! Respawning in 5 seconds...")

func revive() -> void:
	if not is_downed:
		return
	is_downed = false
	down_timer = 0.0
	hp = max_hp
	SignalBus.player_health_changed.emit(hp, max_hp)
	_invulnerable_timer = 2.0
	animator.revive()
	print("Player revived by teammate!")

func respawn_at_base() -> void:
	if not is_downed:
		return
	is_downed = false
	down_timer = 0.0
	global_position = Vector3(0, 1.0, 0)
	hp = max_hp
	SignalBus.player_health_changed.emit(hp, max_hp)
	_invulnerable_timer = 2.0
	animator.revive()
	print("Player respawned at base!")

# --- 25 MTG SPELL IMPLEMENTATIONS ---

func cast_red_fireball(charge_pct: float) -> void:
	var proj = ProjectilePool.get_projectile()
	var spawn_pos = camera.global_position - camera.global_basis.z * 1.5
	var dir = -camera.global_basis.z.normalized()
	# Charge and rank multiply INTO each other: a rank-5 Fireball held to full is the
	# biggest single thing red can do, and that is the intended top of the colour.
	var radius = GameSettings.spell_red_fireball_base_radius * (0.8 + 0.7 * charge_pct) * _rank_area()
	var mult = (0.6 + 1.2 * charge_pct) * get_spell_damage_multiplier() * _rank_damage()
	proj.activate(spawn_pos, dir, 4, false, mult, -1.0, radius, self)

## The green ability: a running leap that ends in a ground slam.
##
## Two halves, split the same way every other committed move is. THIS half is the
## launch, fired when the cast starts: an impulse forward and up, with the ordinary
## movement code suspended for the flight so it cannot be steered away. The slam is
## the other half, and lands on the clip's own final impact frame - see
## `release_on_last` in SpellDatabase and _slam_ground below, which is what
## `execute_spell` actually calls.
func cast_green_titanic_leap() -> void:
	var forward: Vector3 = -transform.basis.z.normalized()
	forward.y = 0.0
	velocity = forward.normalized() * GameSettings.spell_green_leap_speed
	velocity.y = GameSettings.spell_green_leap_rise
	_leap_timer = GameSettings.spell_green_leap_duration
	SoundBank.play_at(&"blade_heavy_swing", global_position)


## The landing. Everything within reach takes the hit and is thrown outwards from the
## point of impact, so the slam reads as a shockwave rather than as a melee swing.
func _slam_ground() -> void:
	_leap_timer = 0.0
	SoundBank.play_at(&"heavy_landing", global_position)
	SignalBus.camera_shake_requested.emit(
		GameSettings.spell_green_leap_shake_strength,
		GameSettings.spell_green_leap_shake_duration
	)
	var damage: float = GameSettings.spell_green_leap_damage * get_spell_damage_multiplier() * _rank_damage()
	var radius: float = GameSettings.spell_green_leap_radius * _rank_area()
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		if offset.length() > radius:
			continue
		_deal_damage(enemy, damage, true)
		if enemy.has_method("apply_knockback"):
			offset.y = 0.0
			if offset.length_squared() < 0.01:
				offset = -transform.basis.z
			enemy.apply_knockback(offset.normalized() * GameSettings.spell_green_leap_knockback)


func cast_red_rain_ember() -> void:
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * 40.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 1)
	var result = space_state.intersect_ray(query)
	var target_pos = result.position if result else (global_position - transform.basis.z * 8.0)
	
	var zone = DoTZone.new()
	zone.setup(
		"fire_rain",
		GameSettings.spell_red_rain_ember_radius * _rank_area(),
		GameSettings.spell_red_rain_ember_dps * get_spell_damage_multiplier() * _rank_damage(),
		GameSettings.spell_red_rain_ember_duration * _rank_duration(),
		self
	)
	get_tree().current_scene.add_child(zone)
	zone.global_position = target_pos

# --- Shared aiming and area helpers -------------------------------------------
#
# Written once because eleven of the twenty-five skills need one of them, and eleven
# hand-rolled copies of "everything within N units" is eleven places for the y-axis to be
# forgotten in.

## Where the player is pointing on the ground, at most `max_distance` away. Falls back to
## a point straight ahead when the ray hits nothing, so a spell aimed at the sky still
## lands somewhere sensible instead of at the origin.
func _aim_point(max_distance: float, mask: int = 1) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var start: Vector3 = camera.global_position
	var end: Vector3 = start - camera.global_basis.z * max_distance
	var query := PhysicsRayQueryParameters3D.create(start, end, mask)
	query.exclude = [get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		return result.position
	return global_position - transform.basis.z * minf(max_distance, 10.0)


## Every living enemy within `radius` of `center`, nearest first. Sorted because several
## skills take the closest N rather than all of them, and an unsorted "first three" is
## whichever three the scene tree happened to list.
func _enemies_in_radius(center: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if center.distance_to(enemy.global_position) <= radius:
			found.append(enemy)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return center.distance_squared_to(a.global_position) < center.distance_squared_to(b.global_position))
	return found


## Enemies inside a cone ahead of the player. `min_dot` is the cosine of the half-angle:
## 1.0 is a line, 0.0 is everything in front, negative widens past the shoulders.
func _enemies_in_cone(range_units: float, min_dot: float) -> Array[Node3D]:
	var forward: Vector3 = -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var found: Array[Node3D] = []
	for enemy: Node3D in _enemies_in_radius(global_position, range_units):
		var to_enemy: Vector3 = enemy.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.01 or forward.dot(to_enemy.normalized()) >= min_dot:
			found.append(enemy)
	return found


## Players, myrs and summons within `radius`. What the three white support skills operate
## on - white is the only colour whose power goes UP with more allies alive, so it is the
## only one that needs to enumerate them.
func _allies_in_radius(radius: float, include_self: bool = true) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for group: String in ["player", "myrs", "allies"]:
		for ally: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(ally) or not ally is Node3D:
				continue
			if ally == self:
				if include_self:
					found.append(self)
				continue
			if global_position.distance_to((ally as Node3D).global_position) <= radius:
				found.append(ally as Node3D)
	return found


## Adds a node to the running scene at a world position. Every placed skill does exactly
## this, and doing it in the wrong order - position before parent - silently puts the
## thing at the origin, because global_position means nothing outside the tree.
func _place_in_world(node: Node3D, world_position: Vector3) -> void:
	get_tree().current_scene.add_child(node)
	node.global_position = world_position


# --- WHITE: protection and restoration ----------------------------------------

## white_1. Charges the NEXT melee hit rather than dealing damage itself - see
## _apply_melee_damage, which spends the charge and exiles anything the hit kills.
func cast_white_exalted_strike() -> void:
	exalted_charges = GameSettings.rank_count(
		GameSettings.spell_white_exalted_charges, GameSettings.spell_white_exalted_charges_max, _casting_rank
	)
	# Resolved now, not on the hit: the charge can sit unspent through several other casts.
	_exalted_damage_mult = GameSettings.spell_white_exalted_damage_mult * _rank_damage()
	_exalted_reach_bonus = GameSettings.spell_white_exalted_reach_bonus * _rank_area()
	SoundBank.play_at(&"blade_heavy_swing", global_position)
	_spawn_cast_flash(Color(1.0, 0.95, 0.7), 2.4)


## white_2. One pool of shield DIVIDED between everyone in range. Alone that is the whole
## pool on the caster, which is what makes the skill honest in single-player without
## being a strictly better personal shield in a group.
func cast_white_circle_of_protection() -> void:
	var allies: Array[Node3D] = _allies_in_radius(GameSettings.spell_white_circle_radius * _rank_area())
	if allies.is_empty():
		return
	var each: float = GameSettings.spell_white_circle_shield_total * _rank_damage() / float(allies.size())
	for ally: Node3D in allies:
		if "protection_shield" in ally:
			ally.protection_shield += each
		elif ally.has_method("heal"):
			# A myr has no shield to give, so its share arrives as health. The pool is
			# still divided the same way - what changes is the form it takes.
			ally.heal(each)
		_spawn_ring(ally.global_position, Color(1.0, 0.95, 0.65), 1.6)
	SoundBank.play_at(&"blade_swing", global_position)


## white_3. Reflect and block, for a duration. Both halves are applied in take_damage.
func cast_white_reprisal_ward() -> void:
	_reprisal_timer = GameSettings.spell_white_reprisal_duration * _rank_duration()
	# Both halves are chances, so both walk to a ceiling instead of being multiplied.
	_reprisal_reflect = GameSettings.rank_fraction(
		GameSettings.spell_white_reprisal_reflect, GameSettings.spell_white_reprisal_reflect_max, _casting_rank
	)
	_reprisal_block_chance = GameSettings.rank_fraction(
		GameSettings.spell_white_reprisal_block_chance, GameSettings.spell_white_reprisal_block_chance_max, _casting_rank
	)
	_spawn_cast_flash(Color(1.0, 0.9, 0.55), 2.6)


## white_4. White's one panic button: heavy damage, wide, around the caster.
func cast_white_wrath_of_god() -> void:
	var damage: float = GameSettings.spell_white_wrath_damage * get_spell_damage_multiplier() * _rank_damage()
	var radius: float = GameSettings.spell_white_wrath_radius * _rank_area()
	for enemy: Node3D in _enemies_in_radius(global_position, radius):
		_deal_damage(enemy, damage, false)
	SoundBank.play_at(&"heavy_landing", global_position)
	SignalBus.camera_shake_requested.emit(0.6, 0.4)
	_spawn_ring(global_position, Color(1.0, 0.97, 0.8), radius)


## white_5. The only skill in all thirty that UNDOES a loss rather than preventing one,
## which is about as white as a mechanic gets - and the only one that touches the co-op
## revive system.
func cast_white_rally_the_fallen() -> void:
	var heal_amount: float = GameSettings.spell_white_rally_heal * _rank_damage()
	# How many people one cast can pick up. Rank 1 is a rescue; rank 5 is a wipe undone.
	var revives_left: int = GameSettings.rank_count(
		GameSettings.spell_white_rally_revives, GameSettings.spell_white_rally_revives_max, _casting_rank
	)
	for ally: Node3D in _allies_in_radius(GameSettings.spell_white_rally_radius * _rank_area()):
		if ally == self:
			continue
		if "is_downed" in ally and ally.is_downed and ally.has_method("revive"):
			if revives_left <= 0:
				continue
			revives_left -= 1
			ally.revive()
			_spawn_ring(ally.global_position, Color(1.0, 1.0, 0.85), 2.2)
			continue
		if ally.has_method("heal"):
			ally.heal(heal_amount)
	# The caster is healed too, but never revived by their own cast - a downed player
	# cannot cast anything, so that branch could only ever be dead code.
	heal(heal_amount)
	SoundBank.play_at(&"blade_heavy_swing", global_position)


# --- BLUE: control -------------------------------------------------------------

## blue_1. Shoves the cone ahead far back and stuns whatever lands. The impact damage for
## anything thrown into a wall is EnemyBase's, on the knockback path.
func cast_blue_unsummon() -> void:
	var pushed: int = 0
	# Push distance and stun duration are what rank buys here - the cone itself does not
	# widen, so aiming it stays the skill.
	var push: float = GameSettings.spell_blue_unsummon_knockback * _rank_area()
	var stun: float = GameSettings.spell_blue_unsummon_stun * _rank_duration()
	for enemy: Node3D in _enemies_in_cone(GameSettings.spell_blue_unsummon_range, GameSettings.spell_blue_unsummon_cone_dot):
		var away: Vector3 = enemy.global_position - global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -transform.basis.z
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(away.normalized() * push)
		if enemy.has_method("apply_stun") and not (enemy.has_method("is_immune_to_control") and enemy.is_immune_to_control()):
			enemy.apply_stun(stun)
		pushed += 1
	if pushed > 0:
		SoundBank.play_at(&"blade_heavy_hit", global_position)
	SignalBus.camera_shake_requested.emit(0.3, 0.25)


## blue_2. Freezes everything around the caster. BOSSES ARE SLOWED, NEVER FROZEN - that
## clause is what stops one blue skill deleting a boss fight.
func cast_blue_frostwave() -> void:
	var damage: float = GameSettings.spell_blue_frostwave_damage * get_spell_damage_multiplier() * _rank_damage()
	var radius: float = GameSettings.spell_blue_frostwave_radius * _rank_area()
	var freeze: float = GameSettings.spell_blue_frostwave_freeze * _rank_duration()
	for enemy: Node3D in _enemies_in_radius(global_position, radius):
		_deal_damage(enemy, damage, false)
		var is_boss: bool = enemy.has_method("is_boss") and enemy.is_boss()
		if is_boss:
			if enemy.has_method("apply_frost_slow"):
				enemy.apply_frost_slow(GameSettings.spell_blue_frostwave_boss_slow * _rank_duration())
		elif "freeze_timer" in enemy:
			enemy.freeze_timer = maxf(enemy.freeze_timer, freeze)
	_spawn_ring(global_position, Color(0.55, 0.85, 1.0), radius)
	SignalBus.camera_shake_requested.emit(0.35, 0.3)


## blue_3. Cover. See FrostGlobe for why one collision layer is the whole skill.
func cast_blue_frost_globe() -> void:
	var target: Vector3 = _aim_point(18.0)
	var radius: float = GameSettings.spell_blue_frost_globe_radius * _rank_area()
	var globe := FrostGlobe.create(radius, GameSettings.spell_blue_frost_globe_duration * _rank_duration())
	_place_in_world(globe, target + Vector3(0.0, radius * 0.8, 0.0))


## blue_4. Packs enemies together for an area follow-up. The pull is a knockback aimed
## INWARD - one impulse toward the centre rather than a sustained drag, so an enemy can
## still walk out of it. Strength is fixed on purpose: see GameSettings.
func cast_blue_suction() -> void:
	# RADIUS scales, pull speed does not - a rank-5 pull that yanked everything in
	# instantly would remove the counterplay of walking out of it. See GameSettings.
	var radius: float = GameSettings.spell_blue_suction_radius * _rank_area()
	var center: Vector3 = _aim_point(radius)
	for enemy: Node3D in _enemies_in_radius(center, radius):
		if not enemy.has_method("apply_knockback"):
			continue
		var inward: Vector3 = center - enemy.global_position
		inward.y = 0.0
		if inward.length_squared() < 0.04:
			continue
		enemy.apply_knockback(inward.normalized() * GameSettings.spell_blue_suction_pull_speed)
	_spawn_ring(center, Color(0.35, 0.6, 1.0), radius * 0.6)


## blue_5. An illusion enemies attack instead of the player. See TemporaryAlly.
func cast_blue_phantasmal_decoy() -> void:
	var decoy := TemporaryAlly.new()
	decoy.configure(
		"decoy",
		GameSettings.spell_blue_decoy_hp * _rank_damage(),
		GameSettings.spell_blue_decoy_duration * _rank_duration(),
		0.0,
		self
	)
	_place_in_world(decoy, global_position - transform.basis.z * 2.5)
	# Enemies do not re-evaluate every frame, so without this the decoy stands unnoticed
	# until each enemy's own evaluation timer happens to come round.
	for enemy: Node3D in _enemies_in_radius(global_position, 20.0):
		if enemy.has_method("evaluate_target"):
			enemy.evaluate_target()


# --- BLACK: parasitic drain ----------------------------------------------------

## black_1. A line, not a cone: the blade passes THROUGH everything it touches and misses
## everything it does not, which is what makes it a skill shot.
func cast_black_doom_blade() -> void:
	var forward: Vector3 = -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var length: float = GameSettings.spell_black_doom_blade_length * _rank_area()
	# "Width (barely)" in the design doc, so barely: a blade that widened with the rest
	# would stop being a line and start being a cone.
	var half_width: float = GameSettings.rank_fraction(
		GameSettings.spell_black_doom_blade_width, GameSettings.spell_black_doom_blade_width_max, _casting_rank
	) * 0.5
	var damage: float = GameSettings.spell_black_doom_blade_damage * get_spell_damage_multiplier() * _rank_damage()

	for enemy: Node3D in _enemies_in_radius(global_position, length):
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var along: float = offset.dot(forward)
		if along < 0.0 or along > length:
			continue
		# Distance from the line itself, which is what "only what the blade touches" means.
		if (offset - forward * along).length() > half_width:
			continue
		_deal_damage(enemy, damage, false)

	_spawn_beam(global_position + Vector3(0.0, 1.1, 0.0), forward, length, Color(0.6, 0.15, 0.75))
	SoundBank.play_at(&"blade_heavy_swing", global_position)


## black_2. The colour's answer to being surrounded: they leave rather than stop. See
## EnemyBase.apply_fear, which moves the body rather than only suppressing the attack.
func cast_black_fear() -> void:
	var radius: float = GameSettings.spell_black_fear_radius * _rank_area()
	for enemy: Node3D in _enemies_in_radius(global_position, radius):
		if enemy.has_method("apply_fear"):
			enemy.apply_fear(GameSettings.spell_black_fear_duration * _rank_duration(), global_position)
	_spawn_ring(global_position, Color(0.45, 0.15, 0.6), radius)


## black_3. The only outright delete in the game. Bosses are executed ONLY below the
## threshold - without that clause this one skill would end every wave boss on sight.
func cast_black_kill() -> void:
	var target: Node3D = null
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_dot: float = 0.55
	# Whatever the player is most directly looking at, rather than whatever is nearest:
	# a single-target execute that picked its own victim would be a different skill.
	for enemy: Node3D in _enemies_in_radius(global_position, GameSettings.spell_black_kill_range * _rank_area()):
		var to_enemy: Vector3 = enemy.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.01:
			continue
		var alignment: float = forward.dot(to_enemy.normalized())
		if alignment > best_dot:
			best_dot = alignment
			target = enemy

	if target == null:
		return
	if target.has_method("is_boss") and target.is_boss():
		var ratio: float = HealthReader.ratio(target)
		# The window a boss can be executed inside is what rank widens - the cooldown is
		# the other half, in _get_spell_cooldown.
		var threshold: float = GameSettings.rank_fraction(
			GameSettings.spell_black_kill_boss_threshold, GameSettings.spell_black_kill_boss_threshold_max, _casting_rank
		)
		if ratio < 0.0 or ratio > threshold:
			# Too healthy to execute. The cooldown is still spent - the risk of calling it
			# early is what makes the threshold a decision rather than a formality.
			_notify("Not weak enough to kill")
			return
	_spawn_ring(target.global_position, Color(0.35, 0.05, 0.45), 2.4)
	SoundBank.play_at(&"blade_heavy_hit", target.global_position)
	SignalBus.camera_shake_requested.emit(0.5, 0.3)
	if target.has_method("exile"):
		target.exile()
	elif target.has_method("die"):
		target.die()


## black_4. Laid across the player's line of sight rather than along it - see SoulWall,
## where the placement rule is explained.
func cast_black_wall_of_souls() -> void:
	var center: Vector3 = _aim_point(20.0)
	var wall := SoulWall.create(
		GameSettings.spell_black_wall_length * _rank_area(),
		GameSettings.spell_black_wall_duration,
		GameSettings.spell_black_wall_mark_duration * _rank_duration(),
		# x2 damage is the headline at rank 1; x4 would eclipse every other black skill.
		GameSettings.rank_fraction(
			GameSettings.spell_black_wall_mark_mult, GameSettings.spell_black_wall_mark_mult_max, _casting_rank
		),
		self
	)
	_place_in_world(wall, center)
	var facing: Vector3 = -camera.global_basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.01:
		# Perpendicular: the wall lies ACROSS the approach the player is looking down.
		wall.rotation.y = atan2(facing.x, facing.z) + PI * 0.5


## black_5. Turns the corpse registry - which until now existed only to cap how many dead
## bodies stayed in the scene - into a resource.
func cast_black_zombify() -> void:
	var corpses: Array[EnemyBase] = EnemyBase.corpses()
	if corpses.is_empty():
		_notify("No corpses to raise")
		return
	# Nearest first, so the spell raises what the player is standing over rather than
	# something that died in another lane five waves ago.
	corpses.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))

	var raised: int = 0
	var to_raise: int = GameSettings.rank_count(
		GameSettings.spell_black_zombify_count, GameSettings.spell_black_zombify_count_max, _casting_rank
	)
	for corpse: EnemyBase in corpses:
		if raised >= to_raise:
			break
		var where: Vector3 = corpse.global_position
		var source: EnemyData = corpse.enemy_data
		EnemyBase.consume_corpse(corpse)
		var undead := TemporaryAlly.new()
		undead.configure(
			"undead",
			GameSettings.spell_black_zombify_hp * _rank_damage(),
			GameSettings.spell_black_zombify_duration * _rank_duration(),
			GameSettings.spell_black_zombify_damage * get_spell_damage_multiplier() * _rank_damage(),
			self,
			source
		)
		_place_in_world(undead, where + Vector3(0.0, 0.5, 0.0))
		_spawn_ring(where, Color(0.35, 0.8, 0.4), 1.8)
		raised += 1
	SoundBank.play_at(&"heavy_landing", global_position)


# --- RED: aggression -----------------------------------------------------------

## red_2, first half. Fired when the cast STARTS, like Titanic Leap: the dash has to be
## under way by the time the release frame lights the trail behind it.
func cast_red_fire_dash() -> void:
	var forward: Vector3 = -transform.basis.z
	forward.y = 0.0
	# Distance is speed x time, and it is the DISTANCE the design doc scales - so the
	# speed rises and the dash stays as short as it reads.
	velocity = forward.normalized() * GameSettings.spell_red_dash_speed * _rank_area()
	velocity.y = 0.0
	_dash_timer = GameSettings.spell_red_dash_duration
	_dash_trail_timer = 0.0
	# Fixed now: the trail keeps being laid after the cast is over, by which time
	# _casting_rank may belong to something else entirely.
	_dash_trail_dps = GameSettings.spell_red_dash_trail_dps * get_spell_damage_multiplier() * _rank_damage()
	_dash_trail_duration = GameSettings.spell_red_dash_trail_duration * _rank_duration()
	_dash_trail_radius = GameSettings.spell_red_dash_trail_radius * _rank_area()
	SoundBank.play_at(&"blade_heavy_swing", global_position)


## red_2, second half. Everything the dash passed over is already burning by now - the
## trail is dropped along the way in _physics_process; this is the last segment plus the
## noise that sells it.
func _lay_fire_trail() -> void:
	_drop_trail_segment()
	SignalBus.camera_shake_requested.emit(0.25, 0.2)


## One burning patch of the dash's wake. Small and short-lived individually - it is the
## line of them that does the damage.
func _drop_trail_segment() -> void:
	var zone := DoTZone.new()
	zone.setup("fire_rain", _dash_trail_radius, _dash_trail_dps, _dash_trail_duration, self)
	_place_in_world(zone, global_position)


## red_4. Starts the channel; the damage is paid out per frame in _update_channel while
## the button stays down. Held spells are the only ones whose effect is not a single
## moment, which is why this one function does almost nothing.
func cast_red_fire_cone() -> void:
	_channel_id = "red_4"
	_channel_timer = GameSettings.spell_red_fire_cone_max_duration
	# Whether the player is HOLDING the cast button decides how it ends. Started from the
	# number-key hotbar instead, there is no hold to watch, so it simply runs its length.
	_channel_held = Input.is_action_pressed("cast_spell")
	_channel_rank = _casting_rank
	_channel_fx = EmberFx.build_flame(GameSettings.spell_red_fire_cone_length * _rank_area() * 0.25, 60)
	_channel_fx.position = Vector3(0.0, 1.2, -1.2)
	var process: ParticleProcessMaterial = _channel_fx.process_material
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 22.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = GameSettings.spell_red_fire_cone_length * 0.5
	process.initial_velocity_max = GameSettings.spell_red_fire_cone_length
	add_child(_channel_fx)


## red_5. The smallest area in the game and the biggest single number, telegraphed so the
## precision is the player's rather than the spell's.
func cast_red_lightning_bolt() -> void:
	# "Radius (slightly)" in the design doc: the smallest area in the game is the point of
	# the skill, so rank buys damage and only a little forgiveness on the aim.
	var bolt_radius: float = GameSettings.spell_red_bolt_radius * GameSettings.rank_fraction(1.0, 1.25, _casting_rank)
	var bolt_damage: float = GameSettings.spell_red_bolt_damage * _rank_damage()
	var target: Vector3 = _aim_point(GameSettings.spell_red_bolt_range, 5)
	# AttackIndicator parents itself to whatever it is told to mark - the enemies pass
	# themselves, so the telegraph tracks them. A ground strike has nothing to track, so
	# it gets an anchor of its own to sit on.
	var anchor := Node3D.new()
	anchor.name = "BoltTelegraph"
	_place_in_world(anchor, target)
	var indicator: AttackIndicator = AttackIndicator.spawn(
		anchor,
		AttackIndicator.Shape.CIRCLE,
		bolt_radius,
		0.0,
		GameSettings.spell_red_bolt_delay,
		Color(0.7, 0.85, 1.0)
	)

	# The strike lands AFTER the telegraph, not with it - a warning that resolves on the
	# frame it appears is not a warning. Which also means the player can be dead, or the
	# whole scene gone, by the time it arrives.
	var timer: SceneTreeTimer = get_tree().create_timer(GameSettings.spell_red_bolt_delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(indicator):
			indicator.resolve()
		if is_instance_valid(anchor):
			# Outlives the indicator's own fade, which is parented to it.
			anchor.get_tree().create_timer(0.5).timeout.connect(anchor.queue_free)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		var damage: float = bolt_damage * get_spell_damage_multiplier()
		for enemy: Node3D in _enemies_in_radius(target, bolt_radius):
			_deal_damage(enemy, damage, false)
		_spawn_beam(target + Vector3(0.0, 18.0, 0.0), Vector3.DOWN, 18.0, Color(0.75, 0.9, 1.0))
		_spawn_ring(target, Color(0.8, 0.9, 1.0), bolt_radius)
		SoundBank.play_at(&"heavy_landing", target)
		SignalBus.camera_shake_requested.emit(0.55, 0.35))


# --- GREEN: primal vitality ----------------------------------------------------

## green_2. Bigger AND tougher: the size is what the player sees, the health is what the
## skill actually does. `_sync_capstone_aura` owns the health half so it cannot drift.
func cast_green_giant_growth() -> void:
	is_giant = true
	giant_timer = GameSettings.spell_green_giant_duration * _rank_duration()
	_giant_bonus_hp = GameSettings.spell_green_giant_bonus_hp * _rank_damage()
	var giant_scale: float = GameSettings.rank_fraction(
		GameSettings.spell_green_giant_scale, GameSettings.spell_green_giant_scale_max, _casting_rank
	)
	# Grown into rather than snapped to: an instant scale change reads as a glitch, and
	# the character's feet visibly leave the floor for a frame.
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", base_scale * giant_scale, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sync_capstone_aura()
	# Gaining maximum health should ARRIVE as health, or the buff reads as a downgrade
	# for the first few seconds while the bar sits at a lower fraction than before.
	heal(_giant_bonus_hp, false)
	SoundBank.play_at(&"blade_heavy_swing", global_position)


## green_3. Ground where enemies deal nothing. Half of green's crystal-defence pair.
func cast_green_fog() -> void:
	var target: Vector3 = _aim_point(20.0)
	var zone := DoTZone.new()
	zone.setup(
		"fog",
		GameSettings.spell_green_fog_radius * _rank_area(),
		0.0,
		GameSettings.spell_green_fog_duration * _rank_duration(),
		self
	)
	_place_in_world(zone, target)


## green_4. The other half: pulls enemies off the crystal and the myrs and onto the
## player, which is the only skill in the game that moves aggro deliberately.
func cast_green_roar() -> void:
	var taunted: int = 0
	var radius: float = GameSettings.spell_green_roar_radius * _rank_area()
	for enemy: Node3D in _enemies_in_radius(global_position, radius):
		if enemy.has_method("apply_taunt"):
			enemy.apply_taunt(self, GameSettings.spell_green_roar_duration * _rank_duration())
			taunted += 1
	_spawn_ring(global_position, Color(0.35, 0.85, 0.3), radius)
	SignalBus.camera_shake_requested.emit(0.3, 0.3)
	if taunted > 0:
		_notify("%d enemies turned on you" % taunted)


## green_5. Damage reduction AND immunity to knockback, stun and freeze - the only answer
## in the game to being controlled. Both halves are read where they apply: take_damage
## for the reduction, _try_hit_reaction and apply_slow for the immunity.
func cast_green_ironbark() -> void:
	_ironbark_timer = GameSettings.spell_green_ironbark_duration * _rank_duration()
	# A fraction, so it walks to a ceiling: x2 on 0.6 is 1.2, which is immunity.
	_ironbark_reduction = GameSettings.rank_fraction(
		GameSettings.spell_green_ironbark_reduction, GameSettings.spell_green_ironbark_reduction_max, _casting_rank
	)
	_stagger_timer = 0.0
	_spawn_cast_flash(Color(0.45, 0.32, 0.16), 2.2)
	SoundBank.play_at(&"blunt_hit", global_position)


## True while Ironbark holds. Everything that would interrupt or move the player checks
## this - one predicate rather than five copies of the timer test.
func is_control_immune() -> bool:
	return _ironbark_timer > 0.0


## How far apart the dash drops its burning patches. Close enough that the trail reads as
## continuous, far enough that a dash does not spawn thirty zones.
const DASH_TRAIL_SPACING := 0.07


## Everything the skill roster put on a clock, in one place. Called once per frame before
## anything reads any of it, so a buff can never be half-expired within a frame.
func _update_skill_timers(delta: float) -> void:
	if _reprisal_timer > 0.0:
		_reprisal_timer -= delta
	if _ironbark_timer > 0.0:
		_ironbark_timer -= delta

	if _grave_stack_timer > 0.0:
		_grave_stack_timer -= delta
		if _grave_stack_timer <= 0.0:
			# The whole stack lapses at once rather than draining away one at a time: a
			# bonus that decays gradually is one the player never notices losing.
			_grave_stacks = 0

	if giant_timer > 0.0:
		giant_timer -= delta
		if giant_timer <= 0.0:
			_end_giant_growth()


## Giant Growth wearing off. The health has to come back through _sync_capstone_aura
## rather than being subtracted here, or repeated casts would drift the maximum.
func _end_giant_growth() -> void:
	is_giant = false
	giant_timer = 0.0
	_giant_bonus_hp = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", base_scale, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_sync_capstone_aura()


## Fire Cone, running. The only per-frame spell in the game: it pays out damage every
## frame it is up, holds the player still, and ends on the button coming up or on its own
## limit - whichever is first.
func _update_channel(delta: float) -> void:
	_channel_timer -= delta

	var still_held: bool = true
	if _channel_held:
		still_held = Input.is_action_pressed("cast_spell")
	if _channel_timer <= 0.0 or not still_held or is_downed or _stagger_timer > 0.0:
		_end_channel()
		return

	# Rooted, but still turning: aiming a flamethrower is the whole interaction, and a
	# cone the player cannot sweep would be a worse Rain of Ember.
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	var damage: float = GameSettings.spell_red_fire_cone_dps * get_spell_damage_multiplier() \
		* GameSettings.rank_damage_mult(_channel_rank) * delta
	var length: float = GameSettings.spell_red_fire_cone_length * GameSettings.rank_area_mult(_channel_rank)
	for enemy: Node3D in _enemies_in_cone(length, GameSettings.spell_red_fire_cone_dot):
		_deal_damage(enemy, damage, false)
	animator.update_locomotion(delta, Vector3.ZERO, false, is_on_floor(), false)


## Ends the channel and takes its flames with it. Called from _update_channel when it
## runs out, and from _cancel_action when something interrupts the player - a channel
## that survived a stagger would keep burning while the character was knocked over.
func _end_channel() -> void:
	if _channel_id == "":
		return
	_channel_id = ""
	_channel_timer = 0.0
	_channel_held = false
	if is_instance_valid(_channel_fx):
		# Emission off rather than freed, so the flames already in the air burn out
		# instead of blinking away mid-frame.
		_channel_fx.emitting = false
		var doomed: Node3D = _channel_fx
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(doomed):
				doomed.queue_free())
	_channel_fx = null


# --- Shared spell visuals ------------------------------------------------------
#
# Deliberately small and generic. Every skill gets SOMETHING the player can see, because
# a spell with no feedback is indistinguishable from a spell that did not fire - which is
# exactly how the skill tree bug that hid all of this went unnoticed for a release.

## An expanding ring on the ground. The area a skill just affected, drawn at the size it
## actually used, so the player can learn the radius by watching rather than by reading.
func _spawn_ring(center: Vector3, tint: Color, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.88
	torus.outer_radius = radius
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.75)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 3.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = mat
	_place_in_world(ring, center + Vector3(0.0, 0.12, 0.0))
	ring.scale = Vector3(0.35, 1.0, 0.35)
	var tween: Tween = ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.tween_callback(ring.queue_free)


## A straight shaft of light. Doom Blade's line and Lightning Bolt's strike are the same
## shape seen from two angles.
func _spawn_beam(origin: Vector3, direction: Vector3, length: float, tint: Color) -> void:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.22
	cylinder.bottom_radius = 0.22
	cylinder.height = length
	beam.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = mat
	_place_in_world(beam, origin + direction.normalized() * length * 0.5)
	# A cylinder mesh stands on Y, so it has to be laid down along the direction asked for.
	if absf(direction.normalized().dot(Vector3.UP)) < 0.99:
		beam.look_at(origin + direction.normalized() * length, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tween: Tween = beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tween.tween_callback(beam.queue_free)


## A pulse of light on the caster. What a self-buff looks like, since it has nowhere else
## to happen.
func _spawn_cast_flash(tint: Color, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 4.0
	light.omni_range = radius * 2.0
	light.position = Vector3(0.0, 1.2, 0.0)
	add_child(light)
	var tween: Tween = light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.5)
	tween.tween_callback(light.queue_free)


## The on-screen line every skill uses to explain itself when it did nothing visible -
## Zombify with no corpses, Kill on a healthy boss. Silence there is indistinguishable
## from a bug.
func _notify(text: String) -> void:
	if not is_local:
		return
	_notification_text = text
	_notification_timer = 1.8
	SignalBus.interact_prompt_changed.emit(text, true)


# --- MELEE ---
#
# Two moves, both fired on the button's RELEASE: a tap is a light attack, a release
# after player_heavy_hold_time is the heavy spin. Firing on release is what lets one
# button carry both without the light attack having to wait out the hold threshold
# to find out which it is; player_attack_buffer_time then holds a release that
# arrives slightly too early until the swing in flight can be chained out of.
#
# The light attack is a chain rather than a single swing - see LIGHT_CHAIN_CLIP.
#
# Damage does not land on the keypress. Each attack clip carries the moments its
# weapon actually connects (measured at build time by
# tools/player_character_builder.gd) and those are queued as _pending_hits.

## The whole melee input path. Called once per physics frame from _physics_process.
##
## Everything below the timers is INPUT, so a remote player runs the timers - its
## pending hits and cooldowns still tick - and reads no keys. What it should do instead
## is replicated; see docs/MULTIPLAYER_PLAN.md.
func _update_actions(delta: float) -> void:
	if _hit_react_cooldown > 0.0:
		_hit_react_cooldown -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
	if _combo_reset_timer > 0.0:
		_combo_reset_timer -= delta
		if _combo_reset_timer <= 0.0:
			_combo_stage = 0

	if _action_timer > 0.0:
		_action_elapsed += delta
		while not _pending_hits.is_empty() and _pending_hits[0] <= _action_elapsed:
			_pending_hits.remove_at(0)
			if _apply_melee_damage(_attack_damage_mult) > 0:
				_reduce_spell_cooldowns(GameSettings.melee_hit_cooldown_reduction)
				# The swing was already heard when the move began; this is the weapon
				# arriving. A whiff simply never reaches this line.
				SoundBank.play_at(_attack_impact_sound, global_position)
				SignalBus.camera_shake_requested.emit(
					_attack_shake_strength, GameSettings.camera_shake_melee_duration)
		if _pending_cast_id != "" and _action_elapsed >= _pending_cast_time:
			var ready_spell: String = _pending_cast_id
			var ready_charge: float = _pending_cast_charge
			_pending_cast_id = ""
			execute_spell(ready_spell, ready_charge)
		_action_timer -= delta
		if _action_timer <= 0.0:
			_action_duration = 0.0
			_action_roots_player = false
			_action_is_melee = false
			_pending_hits.clear()

	if _attack_hold_timer >= 0.0:
		_attack_hold_timer += delta
	if _buffered_swing_timer > 0.0:
		_buffered_swing_timer -= delta
		if _buffered_swing_timer <= 0.0:
			_buffered_swing = ""

	if not is_local:
		return
	if is_downed or _stagger_timer > 0.0 or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_pending_swing()
		return

	if Input.is_action_just_pressed("kick"):
		_try_kick()

	# Nothing fires on the press - it only starts the clock. Firing on press and
	# then swapping the clip once the hold threshold passed used to cut the light
	# swing off mid-stroke, which is the whole reason this is release-driven.
	if is_blocking:
		_clear_pending_swing()
	else:
		# Press and release are checked independently, NOT as an if/elif chain: a
		# click fast enough to land both inside one physics frame reports both as
		# "just" happened, and an elif would take the press and never see the
		# release, silently eating the attack. Handling both in order resolves it
		# as a zero-length hold, i.e. a light tap.
		if Input.is_action_just_pressed("attack"):
			_attack_hold_timer = 0.0
		if Input.is_action_just_released("attack") and _attack_hold_timer >= 0.0:
			# Already winding up settles it regardless of the clock: the player has
			# watched the charge start, so the release has to be the heavy.
			var is_heavy: bool = _heavy_charge_timer >= 0.0 or _attack_hold_timer >= GameSettings.player_heavy_hold_time
			_buffered_swing = "H" if is_heavy else "L"
			_buffered_swing_timer = GameSettings.player_attack_buffer_time
			_attack_hold_timer = -1.0
		_update_heavy_charge(delta)

	if _buffered_swing != "" and _can_start_attack():
		var symbol := _buffered_swing
		_clear_pending_swing()
		_try_attack(symbol)


## The heavy attack's wind-up, from the moment the hold makes a heavy inevitable.
##
## Starting the animation here rather than on release is the whole point: the player
## sees the raise while they are still holding, instead of the character standing
## still and then snapping into a swing. The clip's lead-in is spread across
## player_heavy_charge_max, front-loaded by player_heavy_charge_ease: the axe comes up
## quickly and then settles near the top, which is what holding a wind-up should feel
## like. See _windup_speed.
##
## Nothing about the strike lives here. The wind-up stops where the strike window
## begins (see PlayerAnimator.play_windup), so a charge can never land a hit, and the
## swing released out of it is the ordinary full-speed heavy - a long charge buys
## position and timing, not damage.
func _update_heavy_charge(delta: float) -> void:
	if _heavy_charge_timer < 0.0:
		if _attack_hold_timer < GameSettings.player_heavy_hold_time or is_blocking:
			return
		# Anything else still committed owns the body; the wind-up waits its turn and
		# starts on whichever later frame the chain window opens.
		if not _can_start_attack():
			return
		if not animator.play_windup(HEAVY_CLIP, GameSettings.player_heavy_charge_max):
			return
		_heavy_charge_timer = 0.0
		animator.set_action_speed(_windup_speed())
		return

	_heavy_charge_timer += delta
	if _heavy_charge_timer < GameSettings.player_heavy_charge_max:
		# Re-timed every frame rather than set once: the raise is meant to slow down
		# as it goes, and a one-shot cannot ease itself.
		animator.set_action_speed(_windup_speed())
		return
	# Held to the end of the raise. It goes off by itself rather than leaving the
	# character frozen at the top of a wind-up with the button still down.
	_attack_hold_timer = -1.0
	_clear_pending_swing()
	_start_heavy()


## How much of the raise is behind the player after holding for `progress` of the
## charge window. Front-loaded, so the axe comes up fast and then settles near the top
## instead of crawling at one rate the whole way.
##
## The release reads the same curve, which is what keeps the swing continuous: the
## pose it picks up from has to be the pose the wind-up actually reached.
func _charge_progress_eased(progress: float) -> float:
	return 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), GameSettings.player_heavy_charge_ease)


## Clip-seconds per real second for the wind-up at this instant - the rate of change
## of _charge_progress_eased - so however front-loaded it is, the raise still arrives
## at the top of the swing exactly as the charge window closes.
func _windup_speed() -> float:
	var charge_max: float = maxf(GameSettings.player_heavy_charge_max, 0.01)
	var progress: float = clampf(_heavy_charge_timer / charge_max, 0.0, 1.0)
	var ease_power: float = GameSettings.player_heavy_charge_ease
	return animator.windup_length(HEAVY_CLIP) * ease_power * pow(1.0 - progress, ease_power - 1.0) / charge_max


## Drops a wind-up that is not going to become a swing. Does nothing unless one is
## actually being held, so the callers that cancel everything else - a stagger, the
## guard going up - do not abort an unrelated action's animation in passing.
func _cancel_heavy_charge() -> void:
	if _heavy_charge_timer < 0.0:
		return
	_heavy_charge_timer = -1.0
	animator.stop_action()


func _clear_pending_swing() -> void:
	_attack_hold_timer = -1.0
	_buffered_swing = ""
	_buffered_swing_timer = 0.0


## Starts the swing a completed press/release resolved to. `symbol` is "L" for a tap
## and "H" for a hold.
func _try_attack(symbol: String) -> void:
	if is_blocking or not _can_start_attack():
		return
	if symbol == "H":
		_start_heavy()
	else:
		_advance_light_chain()


## The spin: one committed move rather than a chain step, so it takes the whole body,
## roots the player, and drops whatever light chain was building.
func _start_heavy() -> void:
	_combo_stage = 0
	_combo_reset_timer = 0.0
	_attack_swing_sound = &"blade_heavy_swing"
	_attack_impact_sound = &"blade_heavy_hit"
	_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength

	if _heavy_charge_timer >= 0.0:
		_release_heavy_charge()
		return
	# No charge was running - something else owned the body when the hold crossed the
	# threshold - so this is an ordinary swing from the top of the strike window.
	var duration: float = GameSettings.player_heavy_duration / _attack_speed_mult()
	_begin_melee_action(HEAVY_CLIP, duration, GameSettings.player_heavy_damage_mult, false)


## Turns a held wind-up into its swing WITHOUT restarting anything: the shot the
## charge is already playing simply speeds up, so the character carries on from the
## exact pose the raise had reached.
##
## Firing a fresh shot here is what used to make a full-length charge visibly start
## over. A one-shot ends when its own clip does and fades back to the locomotion
## layer, so at the moment the raise completed the character dropped towards idle -
## and the new shot then blended in from there rather than from the raise.
##
## Releasing early is continuous for the same reason: the swing picks up wherever the
## raise got to and finishes it at full speed, so a barely-charged heavy simply has a
## little more clip left to cover.
func _release_heavy_charge() -> void:
	var lead_in: float = animator.windup_length(HEAVY_CLIP)
	var strike: float = animator.strike_length(HEAVY_CLIP)
	# Clip-seconds per real second: the pace an uncharged heavy plays at, matched
	# exactly, so a charge makes the swing longer rather than slower.
	var pace: float = strike / maxf(GameSettings.player_heavy_duration / _attack_speed_mult(), 0.01)
	var progress: float = clampf(_heavy_charge_timer / GameSettings.player_heavy_charge_max, 0.0, 1.0)
	var from: float = lead_in * _charge_progress_eased(progress)
	var remaining: float = lead_in + strike - from

	_attack_damage_mult = GameSettings.player_heavy_damage_mult
	_pending_cast_id = ""
	SoundBank.play_at(_attack_swing_sound, global_position)
	# Roots, like every heavy swing: this used to read as `upper_body = false`, which
	# meant the same thing back when rooting was derived from it.
	_commit_action(remaining / maxf(pace, 0.01), true, true)
	animator.release_windup(remaining, _action_duration)

	# Scheduled off the same position the animation continues from, so the impacts
	# stay on their frames however long the charge was held.
	_pending_hits.clear()
	for offset: float in animator.hit_offsets(HEAVY_CLIP):
		if offset > from:
			_pending_hits.append((offset - from) / pace)
	if _pending_hits.is_empty():
		_pending_hits = [_action_duration * 0.5]


## One click, one stage of the light chain. A click that lands while the chain is
## still live continues it; anything else starts over at the opening stage.
##
## Standing still and moving get genuinely different swings. A player who is not
## asking to go anywhere gets the clip WHOLE - its own footwork included - and is
## held in place until it finishes, which is the version the animation was authored
## for. A player on the move gets the same swing masked to the upper body, with the
## walk cycle carrying on underneath.
##
## Stage durations are proportional to how much of the clip the stage covers, so
## every stage plays at the same speed and a whole chain still runs one swing
## duration per click.
func _advance_light_chain() -> void:
	var clip: String = LIGHT_CHAIN_CLIP_EXTENDED if melee_combo_extended else LIGHT_CHAIN_CLIP
	var stages: int = LIGHT_CHAIN_STAGES_EXTENDED if melee_combo_extended else LIGHT_CHAIN_STAGES
	if not animator.has_clip(clip):
		push_warning("Light attack chain clip '%s' is missing from the player library" % clip)
		return

	var moving: bool = _wants_to_move()
	var stage: int = _combo_stage if _combo_stage < stages else 0
	# Blade Dance's third stage is a planted, full-body flourish - there is no walking
	# version of it to mask onto the legs - so a player on the move never reaches it
	# and simply starts the chain over instead.
	if moving and stage >= LIGHT_CHAIN_HEAVY_STAGE:
		stage = 0

	var window: Vector2 = animator.combo_windows(clip, stages)[stage]
	var duration: float = _swing_duration() * (window.y - window.x) * float(stages)
	var damage_mult: float = 1.0
	_attack_swing_sound = &"blade_swing"
	_attack_impact_sound = &"blade_hit"
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	if stage >= LIGHT_CHAIN_HEAVY_STAGE:
		damage_mult = GameSettings.player_combo_finisher_damage_mult
		# The chain's last stage hits harder than the rest, and sounds and feels like it.
		_attack_swing_sound = &"blade_heavy_swing"
		_attack_impact_sound = &"blade_heavy_hit"
		_attack_shake_strength = GameSettings.camera_shake_melee_heavy_strength
	_combo_stage = stage + 1
	_combo_reset_timer = duration + GameSettings.player_combo_grace
	_begin_melee_action(clip, duration, damage_mult, moving, window)


## Whether the player is asking to go somewhere right now.
##
## Read from INPUT rather than from velocity on purpose: a standing swing roots the
## character, so by the time the next stage of the chain is due their velocity is zero
## whatever they are holding, and a chain that started standing would lock itself into
## standing until it lapsed.
func _wants_to_move() -> bool:
	if not is_local:
		return false
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.01


func _try_kick() -> void:
	if is_blocking or not _can_start_attack():
		return
	if spell_cooldown_timers.get("kick", 0.0) > 0.0:
		return
	spell_cooldown_timers["kick"] = GameSettings.spell_cooldown_kick
	# A kick is its own move, not a combo step - it breaks the chain. The negative
	# damage multiplier is what marks it as a kick for _apply_melee_damage().
	_combo_stage = 0
	_clear_pending_swing()
	# A boot, not a blade - the same blunt pair an enemy's club uses.
	_attack_swing_sound = &"blunt_swing"
	_attack_impact_sound = &"blunt_hit"
	_attack_shake_strength = GameSettings.camera_shake_melee_strength
	# Rooted despite being a single strike: it is a leg animation, and a walk cycle
	# running underneath it would destroy it.
	_begin_melee_action("kick", GameSettings.player_swing_duration * 1.4, -1.0, false)


## A new attack may start when nothing is committed, or late enough into the swing
## in flight that it reads as continuing the chain rather than cancelling it.
func _can_start_attack() -> bool:
	if is_downed or _stagger_timer > 0.0:
		return false
	if _action_timer <= 0.0:
		return true
	if not _action_is_melee:
		# Mid-cast: the wind-up is a commitment, not a combo step to chain out of.
		return false
	var progress: float = 1.0 - _action_timer / maxf(_action_duration, 0.001)
	return progress >= 1.0 - GameSettings.player_combo_window


## Attack cadence, shortened by Fervor exactly as the old flat melee cooldown was.
func _swing_duration() -> float:
	return GameSettings.player_swing_duration / _attack_speed_mult()


func _attack_speed_mult() -> float:
	return GameSettings.aura_fervor_speed_boost if unlocked_capstone_aura == "aura_fervor" else 1.0


## The shared primitive behind every committed move, melee or cast: play `clip` over
## `duration`, and hold the player still unless it is an upper-body one.
##
## `upper_body` decides whether the legs keep their walk cycle underneath (see
## PlayerAnimator's bone filter) and `roots` whether the player can move at all.
## They are nearly always opposites - a full-body clip on a character sliding along
## the floor is the problem the layering exists to solve - so they are passed
## separately rather than derived, precisely so the one move where they come apart
## can say so. That move is Titanic Leap: full body, and moving, because the movement
## it makes is the jump the clip is playing.
##
## `window` narrows playback to one stage of a chained clip; see _advance_light_chain.
func _begin_action(clip: String, duration: float, upper_body: bool, roots: bool, is_melee: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_commit_action(duration, roots, is_melee)
	animator.play_action(clip, _action_duration, upper_body, window)
	# Tell the other peers WHAT started, not what it looks like. Each of them runs the
	# same PlayerAnimator over the same clip metadata and arrives at the same pose, so a
	# swing costs five floats on the wire instead of a skeleton.
	if Net.is_active() and is_local:
		_net_play_action.rpc(clip, _action_duration, upper_body, window)


@rpc("authority", "call_remote", "reliable")
func _net_play_action(clip: String, duration: float, upper_body: bool, window: Vector2) -> void:
	animator.play_action(clip, duration, upper_body, window)


## The gameplay half of starting a committed move: how long it owns the player, and
## what that stops them doing. Split out from _begin_action because a charged heavy
## continues an animation that is already running instead of starting a new one, and
## so needs this half without the other.
func _commit_action(duration: float, roots: bool, is_melee: bool) -> void:
	# Ends the charge as a flag only. Whatever animation follows either replaces the
	# wind-up's shot or continues it; either way there is nothing to abort.
	_heavy_charge_timer = -1.0
	_action_duration = maxf(duration, 0.01)
	_action_timer = _action_duration
	_action_elapsed = 0.0
	_action_roots_player = roots
	_action_is_melee = is_melee


## A swing: commits the player and schedules the impact frames measured inside the
## stretch of clip it actually plays.
func _begin_melee_action(clip: String, duration: float, damage_mult: float, upper_body: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_attack_damage_mult = damage_mult
	_pending_cast_id = ""
	# Heard now, whatever it goes on to hit. The impact is a separate sound scheduled
	# with the damage below, so a swing through empty air still makes a noise.
	SoundBank.play_at(_attack_swing_sound, global_position)
	# Melee keeps the two tied together: a swing that takes the whole body is a
	# committed move, and one masked to the upper body is walked through.
	_begin_action(clip, duration, upper_body, not upper_body, true, window)
	_pending_hits = animator.hit_times(clip, _action_duration, window)
	if _pending_hits.is_empty():
		# Nothing measured in this stretch: still land one hit, halfway through.
		_pending_hits = [_action_duration * 0.5]


## Deals `amount` to `target`, wherever authority for that actually lives.
##
## Solo and on the host this is a direct call, exactly as it always was. On a client it
## becomes a request the server applies - the client keeps its instant feedback and
## gives up only the authority to decide the number.
func _deal_damage(target: Node, amount: float, is_melee: bool, exile_on_kill: bool = false) -> void:
	if not is_instance_valid(target):
		return
	if Net.is_server():
		if target.has_method("take_damage"):
			target.take_damage(amount, self, is_melee, exile_on_kill)
		return
	if target.has_method("request_damage"):
		target.request_damage.rpc_id(1, amount, Net.local_id(), is_melee, exile_on_kill)


## One impact frame's worth of melee damage. A negative `damage_mult` means "this is
## the kick", which has its own damage and knockback rather than scaling the sword.
##
## Returns how many enemies it connected with, which is what lets a whiff earn the
## player nothing from the melee-into-spell cooldown refund.
func _apply_melee_damage(damage_mult: float) -> int:
	var is_kick: bool = damage_mult < 0.0
	var reach: float = GameSettings.spell_melee_kick_range if is_kick else GameSettings.spell_melee_range
	var knockback: float = GameSettings.spell_melee_kick_knockback if is_kick else GameSettings.spell_melee_knockback
	var dmg: float = GameSettings.spell_melee_kick_damage if is_kick else GameSettings.spell_melee_damage * damage_mult
	dmg *= get_spell_damage_multiplier()

	# Exalted Strike (white_1). A kick is not a strike, so it never spends the charge -
	# otherwise the buff could be thrown away by a button the player pressed for spacing.
	var exalted: bool = exalted_charges > 0 and not is_kick
	if exalted:
		exalted_charges -= 1
		dmg *= _exalted_damage_mult
		reach += _exalted_reach_bonus
		_spawn_cast_flash(Color(1.0, 0.97, 0.75), 2.0)

	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * reach
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)

	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		_deal_damage(enemy, dmg, true, exalted)
		_apply_basic_attack_knockback(enemy, knockback)
		return 1

	var connected: int = 0
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= reach:
			var dir_to_e = (e.global_position - global_position).normalized()
			if -transform.basis.z.dot(dir_to_e) > GameSettings.spell_melee_cone:
				_deal_damage(e, dmg, true, exalted)
				_apply_basic_attack_knockback(e, knockback)
				connected += 1
	return connected

func _apply_basic_attack_knockback(enemy: Node3D, strength: float = -1.0) -> void:
	if not enemy.has_method("apply_knockback"):
		return
	if strength < 0.0:
		strength = GameSettings.spell_melee_knockback
	var knockback_direction: Vector3 = enemy.global_position - global_position
	knockback_direction.y = 0.0
	if knockback_direction.length_squared() <= 0.001:
		knockback_direction = -transform.basis.z
	enemy.apply_knockback(knockback_direction.normalized() * strength)


# --- BLOCK ---

## Guard state for this frame. Deliberately not gated on a swing being in flight -
## releasing into a guard mid-swing is fine, the swing still finishes because
## _can_start_attack() and the animator both keep their own timers.
func _update_block() -> void:
	var wants_to_block: bool = (
		is_local
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_pressed("block")
		and is_on_floor()
		and not is_downed
		and _stagger_timer <= 0.0
		and _action_timer <= 0.0
	)
	if wants_to_block and not is_blocking:
		# Raising the guard drops any half-built combo, and any heavy being wound up.
		_combo_stage = 0
		_attack_hold_timer = -1.0
		_cancel_heavy_charge()
	is_blocking = wants_to_block


## Whether a guard actually stops this hit: it has to come from in front, and - per
## GameSettings.player_block_ignores_boss - a Boss swings straight through one.
func _blocks_attack_from(source: Node3D) -> bool:
	if not is_blocking or not is_instance_valid(source):
		return false
	if GameSettings.player_block_ignores_boss and "enemy_data" in source:
		var data = source.enemy_data
		if data != null and data.enemy_class == "Boss":
			return false
	var to_source: Vector3 = source.global_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() <= 0.001:
		return true
	return -transform.basis.z.dot(to_source.normalized()) >= GameSettings.player_block_cone

func _physics_process(delta: float) -> void:
	if not is_local:
		# A puppet's transform is authored by its owner and arrives over the wire. All
		# this end has to do is keep the animator fed from the replicated velocity,
		# which is what makes it walk, run and strafe correctly with nothing else sent.
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), false, is_on_floor(), is_blocking)
		return
	_sync_capstone_aura()
	# Runs before the downed early-out so a shake still settles while downed.
	_update_camera_shake(delta)
	if is_downed:
		down_timer -= delta
		if down_timer <= 0.0:
			respawn_at_base()
			return
			
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_skill_timers(delta)

	# Melee fires on release: a tap advances the light chain by one stage, a hold
	# commits to the heavy spin. See _update_actions().
	_update_block()
	_update_actions(delta)

	# Fire Cone owns the player completely while it runs - no movement, no melee, no
	# second cast - so it returns rather than falling through to the movement code.
	if _channel_id != "":
		_update_channel(delta)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_local and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Titanic Leap is in the air: gravity and the launch impulse own the player, so
	# the ordinary movement code below is skipped entirely rather than being allowed
	# to overwrite velocity.x/z with whatever the stick is doing. The slam itself is
	# scheduled off the clip's landing frame, not off this timer.
	if _leap_timer > 0.0:
		_leap_timer -= delta
		move_and_slide()
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), true, is_on_floor(), false)
		return

	# Fire Dash, the same shape as the leap: the impulse owns the player for its length,
	# and the ordinary movement code below would otherwise overwrite it on the very next
	# line. Unlike the leap it stays on the ground, and it leaves something behind.
	if _dash_timer > 0.0:
		_dash_timer -= delta
		_dash_trail_timer -= delta
		if _dash_trail_timer <= 0.0:
			_dash_trail_timer = DASH_TRAIL_SPACING
			_drop_trail_segment()
		move_and_slide()
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), true, is_on_floor(), false)
		return

	# Charging Logic
	if is_charging:
		charge_timer += delta
		SignalBus.spell_charge_changed.emit(charge_timer, charge_max_time, true)
		if charge_timer >= charge_max_time:
			release_charged_spell()


	# Base & Aura Passive HP Regeneration
	var regen_amount = GameSettings.player_base_hp_regen * (1.0 + get_affinity_bonus("white")) * delta
	if unlocked_capstone_aura == "aura_sylvan_library":
		regen_amount += GameSettings.aura_sylvan_library_regen * delta
	heal(regen_amount, false)

	if unlocked_capstone_aura == "aura_phyrexian_arena":
		var drain = max_hp * GameSettings.aura_phyrexian_arena_hp_drain_pct * delta
		hp = max(1.0, hp - drain)
		SignalBus.player_health_changed.emit(hp, max_hp)

	# Trample, green's Manifestation. Gated on actually MOVING, which is the whole
	# design: it rewards the colour that fights by being physically present, and it does
	# nothing at all for a player standing still at the crystal.
	if unlocked_capstone_aura == "aura_trample" and Vector3(velocity.x, 0.0, velocity.z).length() > 1.0:
		var trample: float = GameSettings.aura_trample_dps * get_spell_damage_multiplier() * delta
		for enemy: Node3D in _enemies_in_radius(global_position, GameSettings.aura_trample_radius):
			_deal_damage(enemy, trample, true)

	# Teammate revive check
	var revived_teammate = false
	var teammates = get_tree().get_nodes_in_group("player")
	for teammate in teammates:
		if teammate != self and teammate.is_downed:
			var dist = global_position.distance_to(teammate.global_position)
			if dist < 3.0:
				revived_teammate = true
				if _notification_timer <= 0.0:
					SignalBus.interact_prompt_changed.emit("Press %s to Revive Teammate" % _interact_key_label(), true)
				
				if Input.is_action_just_pressed("interact"):
					teammate.revive()
					_notification_text = "Revived Teammate!"
					_notification_timer = 1.5
				break

	# Base proximity. Mana is banked automatically when an enemy dies now - there is no
	# harvest, no carrying and no deposit trip, because the pool is the team's and there
	# is nobody for a pickup to belong to. What is left here is only "am I at the base",
	# which is what opens the base UI and what the HUD prompt reads.
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("spawn_myr"):
		var near_base = global_position.distance_to(main_node.crystal_anchor.global_position) < GameSettings.player_base_proximity
		if near_base != is_at_base:
			is_at_base = near_base
			SignalBus.at_base_changed.emit(is_at_base)

		if is_at_base and is_local and Input.is_action_just_pressed("interact"):
			if main_node.base_ui_instance and not main_node.base_ui_instance.visible:
				main_node.base_ui_instance.open(main_node)

		if is_local and not revived_teammate:
			if main_node.base_ui_instance and main_node.base_ui_instance.visible:
				SignalBus.interact_prompt_changed.emit("", false)
			elif _notification_timer > 0.0:
				_notification_timer -= delta
				SignalBus.interact_prompt_changed.emit(_notification_text, true)
			elif is_at_base:
				SignalBus.interact_prompt_changed.emit("Press %s to Manage Base" % _interact_key_label(), true)
			else:
				SignalBus.interact_prompt_changed.emit("", false)

	# Gamepad right-stick look (mouse look is event-driven in _unhandled_input;
	# a held stick deflection needs continuous per-frame polling instead).
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.2) if is_local else Vector2.ZERO
	if look_input != Vector2.ZERO:
		_apply_look_delta(-look_input.x * GameSettings.player_gamepad_look_sensitivity * delta,
			-look_input.y * GameSettings.player_gamepad_look_sensitivity * delta)

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if is_local else Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = speed
	if unlocked_capstone_aura == "aura_fervor":
		current_speed *= GameSettings.aura_fervor_speed_boost
	elif unlocked_capstone_aura == "aura_phyrexian_arena":
		current_speed *= GameSettings.aura_phyrexian_arena_speed_mult
		
	# A heavy attack, a kick or a stagger plays on the whole body, so the player is
	# held in place for its duration - otherwise the character slides along the floor
	# with no leg animation driving it. The light chain is masked to the upper body
	# and leaves movement alone.
	# A wind-up roots as hard as the swing it becomes: it is a full-body clip, and the
	# player chooses when it ends by letting go.
	var rooted: bool = (_action_timer > 0.0 and _action_roots_player) or _stagger_timer > 0.0 or _heavy_charge_timer >= 0.0
	var sprinting: bool = is_local and Input.is_action_pressed("sprint") and not is_blocking and not rooted
	if sprinting:
		current_speed *= GameSettings.player_sprint_speed_mult
	if slow_timer > 0:
		current_speed *= GameSettings.enemy_blue_mage_slow_mult
	if is_blocking:
		current_speed *= GameSettings.player_block_speed_mult
	elif _action_timer > 0.0:
		current_speed *= GameSettings.player_attack_move_mult

	if rooted:
		# Zeroed outright rather than by falling through to move_toward() below:
		# with current_speed at 0 that call is a no-op, and the player would coast
		# on at whatever velocity the swing started with.
		velocity.x = 0.0
		velocity.z = 0.0
	elif direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), sprinting, is_on_floor(), is_blocking)
	
	if is_giant:
		giant_timer -= delta
		if giant_timer <= 0:
			is_giant = false
			var tween = create_tween()
			tween.tween_property(self, "scale", Vector3.ONE, 0.5)

	if slow_timer > 0:
		slow_timer -= delta

	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta

	# Cooldowns
	for key in spell_cooldown_timers.keys():
		var cdr = 1.0
		if unlocked_capstone_aura == "aura_rhystic_study":
			cdr = GameSettings.aura_rhystic_study_cdr_mult
		var affinity_recovery: float = 1.0 + get_affinity_bonus("blue")
		spell_cooldown_timers[key] -= delta * affinity_recovery / cdr
		if spell_cooldown_timers[key] <= 0.0:
			spell_cooldown_timers.erase(key)
