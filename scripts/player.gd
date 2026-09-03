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

var carried_color: String = ""
var harvest_timer: float = 0.0
var is_at_base: bool = false

# --- MTG 5-Color State ---
var chosen_color_path: String = ""
var unlocked_spells_in_path: Array[String] = []
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
var run_damage_multiplier: float = 1.0
var run_cooldown_recovery_multiplier: float = 1.0

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

func _ready() -> void:
	add_to_group("player")
	animator = $Animator
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	setup_camera()
	
	SignalBus.skill_unlocked.connect(_on_skill_unlocked)
	SignalBus.spell_unlocked.connect(_on_spell_unlocked)
	SignalBus.melee_combo_unlocked.connect(_on_melee_combo_unlocked)
	SignalBus.wave_reward_selected.connect(_on_wave_reward_selected)
	
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

func _unhandled_input(event: InputEvent) -> void:
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
				var main_c = get_tree().current_scene
				if main_c and main_c.has_method("add_mana"):
					for c in ["White", "Blue", "Black", "Red", "Green"]:
						main_c.add_mana(c, 100)
					print("[DEBUG] Granted +100 of each Mana color!")
				var st = get_tree().current_scene.get_node_or_null("SkillTree")
				if st and st.has_method("update_ui"):
					st.update_ui()
			elif keycode == KEY_F2:
				chosen_color_path = ""
				unlocked_spells_in_path.clear()
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

func _get_aura_name_for_color(color: String) -> String:
	match color:
		"red": return "fervor"
		"blue": return "rhystic_study"
		"green": return "sylvan_library"
		"white": return "glorious_anthem"
		"black": return "phyrexian_arena"
		_: return ""

func cycle_spell(dir: int) -> void:
	var original_index = active_spell_index
	var max_spells = 5
	
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
	if chosen_color_path != "" and slot_idx >= 0 and slot_idx <= 4:
		return chosen_color_path + "_" + str(slot_idx + 1)
	return ""

func select_color_path(color: String) -> void:
	if not affinity_ranks.has(color):
		return
	chosen_color_path = color
	active_spell_index = 0
	SignalBus.color_path_chosen.emit(color)
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))

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
	var lifesteal: float = get_affinity_bonus("black")
	if lifesteal > 0.0 and amount > 0.0:
		heal(amount * lifesteal)

func get_spell_name_for_slot(slot_idx: int) -> String:
	return SpellDatabase.get_display_name(_get_spell_id_for_slot(slot_idx))

func is_spell_unlocked(slot_idx: int) -> bool:
	var spell_id = _get_spell_id_for_slot(slot_idx)
	return unlocked_spells_in_path.has(spell_id)

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

func _get_spell_cooldown(spell_id: String) -> float:
	return SpellDatabase.get_cooldown(spell_id)

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

	_pending_cast_id = spell_id
	_pending_cast_charge = charge_pct
	_pending_cast_time = animator.release_time(clip, duration, bool(row.get("release_on_last", false)))
	# A spell whose animation MOVES the caster has to start moving now, not on the
	# release frame - the release is the payload landing, and by then the leap has to
	# already have carried them there.
	if spell_id == "green_1":
		cast_green_titanic_leap()
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
	if not unlocked_spells_in_path.has(spell_id) or spell_cooldown_timers.get(spell_id, 0.0) > 0.0:
		return
	if not _can_start_cast():
		return
	_begin_cast(spell_id, pct)

func execute_spell(spell_id: String, charge_pct: float = 1.0) -> void:
	spell_cooldown_timers[spell_id] = _get_spell_cooldown(spell_id)
	
	# Rhystic Study Shield trigger on cast
	if unlocked_capstone_aura == "aura_rhystic_study":
		rhystic_shield = minf(
			rhystic_shield + GameSettings.aura_rhystic_study_shield_amount,
			GameSettings.aura_rhystic_study_shield_max
		)
		
	match spell_id:
		"red_1": cast_red_fireball(charge_pct)
		"red_2": cast_red_rain_ember()
		# The LANDING, not the launch: the leap itself was already fired when the cast
		# began, and this is the clip's final impact frame arriving.
		"green_1": _slam_ground()

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
	if not unlocked_spells_in_path.has(spell_id):
		unlocked_spells_in_path.append(spell_id)
			
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

	if can_use_defenses:
		var absorbed: float = minf(glorious_anthem_shield, remaining_damage)
		glorious_anthem_shield -= absorbed
		remaining_damage -= absorbed
		absorbed = minf(rhystic_shield, remaining_damage)
		rhystic_shield -= absorbed
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
	if _hit_react_cooldown > 0.0 or is_downed:
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
	if is_charging:
		is_charging = false
		charge_timer = 0.0
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	_combo_stage = 0
	_combo_reset_timer = 0.0
	_cancel_heavy_charge()
	_clear_pending_swing()

func _sync_capstone_aura() -> void:
	var green_affinity_rank: int = get_affinity_rank("green")
	if _applied_capstone_aura == unlocked_capstone_aura and _applied_green_affinity_rank == green_affinity_rank:
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
	hp = clampf(max_hp * health_ratio, 0.0, max_hp)
	_applied_capstone_aura = unlocked_capstone_aura
	_applied_green_affinity_rank = green_affinity_rank
	SignalBus.player_health_changed.emit(hp, max_hp)
	SignalBus.player_capstone_aura_changed.emit()

func get_spell_damage_multiplier() -> float:
	var affinity_multiplier: float = 1.0 + get_affinity_bonus("red")
	if unlocked_capstone_aura == "aura_glorious_anthem":
		return GameSettings.aura_glorious_anthem_damage_mult * run_damage_multiplier * affinity_multiplier
	if unlocked_capstone_aura == "aura_phyrexian_arena":
		return GameSettings.aura_phyrexian_arena_damage_mult * run_damage_multiplier * affinity_multiplier
	return run_damage_multiplier * affinity_multiplier

func _on_wave_reward_selected(reward_id: String) -> void:
	match reward_id:
		"power_surge":
			run_damage_multiplier *= GameSettings.reward_power_surge_damage_mult
		"arcane_tempo":
			run_cooldown_recovery_multiplier *= GameSettings.reward_arcane_tempo_recovery_mult

func apply_slow(duration: float) -> void:
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
	var radius = GameSettings.spell_red_fireball_base_radius * (0.8 + 0.7 * charge_pct)
	var mult = (0.6 + 1.2 * charge_pct) * get_spell_damage_multiplier()
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
	var damage: float = GameSettings.spell_green_leap_damage * get_spell_damage_multiplier()
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		if offset.length() > GameSettings.spell_green_leap_radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, self, true)
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
	zone.setup("fire_rain", GameSettings.spell_red_rain_ember_radius, GameSettings.spell_red_rain_ember_dps * get_spell_damage_multiplier(), GameSettings.spell_red_rain_ember_duration, self)
	get_tree().current_scene.add_child(zone)
	zone.global_position = target_pos

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

	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start - camera.global_basis.z * reach
	var query = PhysicsRayQueryParameters3D.create(start, end, 4)
	var result = space_state.intersect_ray(query)

	if result and result.collider.is_in_group("enemies"):
		var enemy = result.collider
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg, self, true)
		_apply_basic_attack_knockback(enemy, knockback)
		return 1

	var connected: int = 0
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= reach:
			var dir_to_e = (e.global_position - global_position).normalized()
			if -transform.basis.z.dot(dir_to_e) > GameSettings.spell_melee_cone:
				if e.has_method("take_damage"):
					e.take_damage(dmg, self, true)
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
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
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

	# Melee fires on release: a tap advances the light chain by one stage, a hold
	# commits to the heavy spin. See _update_actions().
	_update_block()
	_update_actions(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
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

	# Mana Harvesting & Base
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("add_mana"):
		var at_mana_source = false
		var source_color = ""
		for i in range(main_node.mana_sources.size()):
			var ms = main_node.mana_sources[i]
			if global_position.distance_to(ms.global_position) < GameSettings.player_mana_harvest_distance:
				at_mana_source = true
				source_color = main_node.LANE_NAMES[i]
				break
				
		var near_base = global_position.distance_to(main_node.crystal_anchor.global_position) < GameSettings.player_base_proximity
		if near_base != is_at_base:
			is_at_base = near_base
			SignalBus.at_base_changed.emit(is_at_base)
			
		if is_at_base:
			if carried_color != "":
				SignalBus.mana_deposited.emit(carried_color, 1)
				_notification_text = "Deposited %s Mana!" % carried_color
				_notification_timer = 1.5
				carried_color = ""
				
			if Input.is_action_just_pressed("interact"):
				if main_node.base_ui_instance and not main_node.base_ui_instance.visible:
					main_node.base_ui_instance.open(main_node)

		if not revived_teammate:
			if main_node.base_ui_instance and main_node.base_ui_instance.visible:
				SignalBus.interact_prompt_changed.emit("", false)
			elif _notification_timer > 0.0:
				_notification_timer -= delta
				SignalBus.interact_prompt_changed.emit(_notification_text, true)
			elif at_mana_source and carried_color == "":
				if Input.is_action_pressed("interact"):
					harvest_timer += delta
					var progress = int((harvest_timer / GameSettings.player_mana_harvest_time) * 100)
					SignalBus.interact_prompt_changed.emit("Harvesting %s Mana... %d%%" % [source_color, progress], true)
					
					if harvest_timer >= GameSettings.player_mana_harvest_time:
						carried_color = source_color
						harvest_timer = 0.0
						_notification_text = "Collected %s Mana!" % source_color
						_notification_timer = 1.5
				else:
					harvest_timer = 0.0
					SignalBus.interact_prompt_changed.emit("Hold %s to Harvest %s Mana" % [_interact_key_label(), source_color], true)
			elif is_at_base:
				SignalBus.interact_prompt_changed.emit("Press %s to Manage Base" % _interact_key_label(), true)
			else:
				harvest_timer = 0.0
				SignalBus.interact_prompt_changed.emit("", false)

	# Gamepad right-stick look (mouse look is event-driven in _unhandled_input;
	# a held stick deflection needs continuous per-frame polling instead).
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.2)
	if look_input != Vector2.ZERO:
		_apply_look_delta(-look_input.x * GameSettings.player_gamepad_look_sensitivity * delta,
			-look_input.y * GameSettings.player_gamepad_look_sensitivity * delta)

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
	var sprinting: bool = Input.is_action_pressed("sprint") and not is_blocking and not rooted
	if sprinting:
		current_speed *= GameSettings.player_sprint_speed_mult
	if slow_timer > 0:
		current_speed *= GameSettings.enemy_blue_mage_slow_mult
	if carried_color != "":
		current_speed *= GameSettings.player_carry_speed_penalty
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
		spell_cooldown_timers[key] -= delta * run_cooldown_recovery_multiplier * affinity_recovery / cdr
		if spell_cooldown_timers[key] <= 0.0:
			spell_cooldown_timers.erase(key)
