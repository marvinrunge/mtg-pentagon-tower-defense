extends CharacterBody3D
class_name Player

@export var speed: float = GameSettings.player_base_speed
@export var jump_velocity: float = GameSettings.player_jump_velocity
@export var mouse_sensitivity: float = GameSettings.player_mouse_sensitivity
@export var rotation_speed: float = 10.0
@export var projectile_scene: PackedScene = preload("res://scenes/misc/projectile.tscn")
## By path, not by class_name - see the note on `_charge_orb`.
const CHARGE_ORB_SCRIPT := preload("res://scripts/charge_orb.gd")
## How far in front of the caster the charged ball floats. See _update_charge_orb.
const CHARGE_ORB_REACH := 0.42

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
## How many spells the bar holds, and therefore the highest number key that casts one.
##
## Eight rather than ten because the bar has to be reachable on a CONTROLLER, where every
## slot costs a button or a modifier combination - ten needs a scheme no pad has room for,
## and the last two slots were the ones nothing was ever bound to anyway.
const QUICK_SLOT_COUNT: int = 8
## What a player starts a run with, before the team has levelled once.
const STARTING_SKILL_POINTS: int = 2

## What each of the QUICK_SLOT_COUNT hotbar keys casts, chosen by the PLAYER rather than
## derived from a colour. Empty means the slot is free.
##
## This is what makes multicolour builds real: a red main can carry Fireball, Fire Dash
## and Rain of Ember and still keep a slot for blue's Frost Breath, because the slots are a
## loadout and not a view of one branch of the tree.
var quick_slots: Array[String] = _empty_quick_slots()
## The rank of the spell currently being cast. Set once where the cast starts and read by
## the cast functions, rather than threaded through twenty-five signatures - every one of
## them would have to pass it down to the same three helpers anyway.
var _casting_rank: int = 1
## The team level that grants Blade Dance, the light attack's third stage. It is no longer
## purchasable - see _on_team_level_changed.
const BLADE_DANCE_LEVEL: int = 10
## Exalted Strike and Fire Dash both outlive the cast that started them - the first waits
## for a melee hit, the second keeps dropping fire for a third of a second - so both
## resolve their numbers AT CAST TIME rather than reading _casting_rank later, when
## another spell may have moved it.
var _exalted_damage_mult: float = 1.0
var _exalted_reach_bonus: float = 0.0
var _dash_trail_dps: float = 0.0
var _dash_trail_duration: float = 0.0
var _dash_trail_radius: float = 0.0
var aura_ranks: Dictionary = {}
var affinity_ranks: Dictionary = {
	"white": 0,
	"blue": 0,
	"black": 0,
	"red": 0,
	"green": 0,
}

# --- Spell Charging State ---
var is_charging: bool = false
## The fireball being built between the caster's hands while a charge is held. Null whenever
## nothing is charging - see ChargeOrb, and _update_charge_orb for how it is anchored.
## Typed as Node3D and built through a PRELOADED SCRIPT rather than through the global name
## `ChargeOrb`. A headless run does not rescan the project, so a newly added class_name is not
## in .godot/global_script_class_cache.cfg until an editor session picks it up - referencing it
## by name makes player.gd fail to parse on exactly the runs that would catch the mistake, and
## the whole scene silently never loads. Same rule tools/animation_impact.gd documents.
var _charge_orb: Node3D = null
## Where the orb was when the player let go. The cast runs on the animation's release frame,
## several tenths of a second later, so the position has to be captured at release time -
## by then the orb is mid-throw-out and the hands have moved on.
var _charge_muzzle: Vector3 = Vector3.ZERO
var charge_timer: float = 0.0
## Set again from GameSettings on every charge; seeded here so the HUD reads a real
## window even from a charge_changed emitted before the player has ever held one.
var charge_max_time: float = GameSettings.spell_charge_max_time
var charging_spell_id: String = ""

# --- Temporary Buffs & Combo Timers ---
## Seconds of Titanic Brawl still in the air. While it runs the player's own movement
## input is suspended so the launch impulse carries them, instead of being overwritten
## by the ordinary per-frame velocity assignment.
var _leap_timer: float = 0.0
var last_spell_cast_time: float = -999.0
var rhystic_shield: float = 0.0
var glorious_anthem_shield: float = 0.0
## Aura fingerprint as last applied. Never compared before the first _sync_auras pass:
## `_applied_green_affinity_rank` starts at -1 and no colour can be at rank -1, so the
## first call always runs in full whatever this happens to hold.
var _applied_auras: int = 0
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
## Circle of Protection (white_2). A third shield pool beside the two aura ones, kept
## separate so a aura re-sync cannot wipe a shield the player just cast.
var protection_shield: float = 0.0
## Where this player started, and which way they were looking. Set by MainController when the
## avatar is seated; respawning at base returns them to exactly this, rather than to the world
## origin - which is where the crystal is.
var spawn_point: Transform3D = Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))

## What this player has done this run, for the scoreboard on Tab.
##
## Kept on the PLAYER rather than in a central table because every one of these numbers is
## produced at a point that already knows whose it is - the hit that landed, the heal that was
## cast, the body that went down - and a central table would need that same attribution
## threaded to it anyway. The scoreboard walks PlayerRegistry.players and reads them off.
##
## `downs` and `deaths` are deliberately separate: going down is recoverable, and a teammate
## reviving you means it never becomes a death. A death is a down that ran out of time.
##
## Floats for the four totals, because damage and healing arrive in fractions and rounding
## each one before adding loses several percent over a run.
var stats: Dictionary = {
	"kills": 0,
	"deaths": 0,
	"downs": 0,
	"damage_dealt": 0.0,
	"damage_taken": 0.0,
	"heal_self": 0.0,
	"heal_others": 0.0,
}


func add_stat(key: String, amount: float = 1.0) -> void:
	if not stats.has(key):
		push_warning("Unknown player stat '%s'" % key)
		return
	stats[key] = stats[key] + (int(amount) if stats[key] is int else amount)


## What the scoreboard calls this player. The lobby's name when there is one - Net.peers is
## keyed by the same peer id the avatar's multiplayer authority carries - and a seat number
## otherwise, so a solo run and an unnamed peer still read as something.
func display_name() -> String:
	var peer_id: int = get_multiplayer_authority()
	if Net.peers.has(peer_id):
		var entry: Dictionary = Net.peers[peer_id]
		var peer_label: String = String(entry.get("name", "")).strip_edges()
		if peer_label != "":
			return peer_label
	if is_local and Net.local_name.strip_edges() != "":
		return Net.local_name.strip_edges()
	return "Player %d" % (PlayerRegistry.players.find(self) + 1)


## One enemy killed by this player. Called from EnemyBase.take_damage, which is the only
## place that knows both that the hit was fatal and who threw it.
func on_enemy_killed_by_me() -> void:
	add_stat("kills")


## Books `restored` health against this player as healing, split by whether it landed on
## themselves or on somebody else.
##
## Credited at the CALL SITE rather than inside heal(): players, myrs and summons each have
## their own heal(), and threading a `source` argument through all three would put the
## bookkeeping in the place least likely to know why the heal happened. Every caster already
## knows both halves - who cast it and who it landed on - so it is one call here instead.
func _credit_heal(target: Node, restored: float) -> void:
	if restored <= 0.0:
		return
	add_stat("heal_self" if target == self else "heal_others", restored)
## Circle of Protection's shield expires. Without this the spell's 18s cooldown was the only
## thing limiting it, and the correct play was to stand in the base casting it until the pool
## was arbitrarily large - see GameSettings.spell_white_circle_duration.
var _protection_shield_timer: float = 0.0
## Seconds since this player last TOOK damage, which is what Glorious Anthem's shield recharges
## on. Distinct from _combat_timer, which the player's own swings set - a white player meleeing
## safely behind their team is not what the recharge delay is there to lock out.
var _undamaged_timer: float = 0.0
## Reprisal Ward (white_3). The two fractions are resolved at cast time and read back
## in take_damage, because a buff with a duration outlives the cast that set it.
var _reprisal_timer: float = 0.0
var _reprisal_reflect: float = 0.0
var _reprisal_block_chance: float = 0.0
## Ironbark (green_5). The only CC immunity in the game.
var _ironbark_timer: float = 0.0
var _ironbark_reduction: float = 0.0
## Harvesting a mana well by hand. Seconds left on the channel, and which well is being
## worked. Both local to the harvesting player: this is a held action with a progress
## prompt, and only the peer holding the key can know it is still held. The mana itself is
## banked on the server - see _request_harvest.
var _harvest_left: float = 0.0
var _harvest_well: Node3D = null

## Giant Growth (green_2). `is_giant` / `giant_timer` / `base_scale` are declared above -
## they were stubbed long before the skill existed. This is the health half, and the
## scale factor the buff actually applied, which the damage and cadence halves read.
var _giant_bonus_hp: float = 0.0
var _applied_giant_bonus: float = -1.0
## The size this machine has already tweened to, so _sync_giant_scale can tell a real
## change from the sixty times a second it is asked.
var _applied_giant_scale: float = 1.0
var _giant_scale_mult: float = 1.0
## Fire Dash (red_2). Seconds of dash left; drives movement the way _leap_timer does.
var _dash_timer: float = 0.0
var _dash_trail_timer: float = 0.0
## Fire Cone (red_4). The only HELD spell: it runs while the button is down.
var _channel_id: String = ""
var _channel_timer: float = 0.0
## The rank the channel was started at. Fire Cone pays out per frame for seconds, so it
## cannot read _casting_rank - anything cast in between would move it.
var _channel_rank: int = 1
## The looping voice for the channel. Owned here rather than pooled: a pooled voice is
## recycled by the next impact, which is exactly wrong for something meant to sustain.
var _channel_voice: AudioStreamPlayer3D = null
## Whether the button that started the channel is one this can watch for a release.
var _channel_held: bool = false
var _channel_slot: int = -1
var _channel_fx: Node3D = null
## Set once a client has told the host its cast button came up, so the notice goes out
## once instead of every frame of the round trip. See _watch_remote_channel.
var _channel_release_sent: bool = false
## Fingerprint of the build as it was last broadcast, so _publish_build can tell a real
## change from the sixty times a second it is asked.
var _published_build: int = 0
## Grave Pact (black aura). Stacks decay if the player stops killing, which is the
## whole design - it pays aggression rather than existence.
var _grave_stacks: int = 0
var _grave_stack_timer: float = 0.0
## Neutral passives (the guild nodes between the colours in the skill tree). Rank per
## id; every effect reads through get_passive_bonus so the curves stay in GameSettings.
var passive_ranks: Dictionary = {}
## Rally the Fallen's solo floor: while this runs, the next death is refused outright.
var _phoenix_ward_timer: float = 0.0
## The helper's 3-second revive channel on a downed teammate. Any of the HELPER's own
## actions - moving, attacking, casting, jumping - drops it. The downed player's own
## timer keeps running meanwhile.
var _revive_channel_target: Player = null
var _revive_channel_left: float = 0.0
## Orbiting aura nodes, keyed by aura id. Aura choices are now per colour, so more than
## one orb aura can be active at once.
var _aura_orbs: Dictionary = {}
## Points earned from team levels and from Upkeep purchases, and how many are already
## committed in the tree. Personal: the team levels together, but nobody spends your
## points for you.
var skill_points: int = STARTING_SKILL_POINTS
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
const HEAVY_LUNGE_DISTANCE: float = 0.65
const HEAVY_LUNGE_EXTRA_DISTANCE: float = 0.35
const HEAVY_LUNGE_EXTRA_START: float = 0.50
const HEAVY_LUNGE_EXTRA_END: float = 0.70

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
## Counts down from player_combat_linger after anything that counts as fighting. Drives
## both the locomotion clip choice and the combat movement speed, so the two cannot
## disagree about whether a fight is happening.
var _combat_timer: float = 0.0
var _action_duration: float = 0.0
var _action_elapsed: float = 0.0
## True while the committed move holds the player in place.
var _action_roots_player: bool = false
## Only a melee action can be chained out of inside the combo window; a cast's tail
## must not become a free combo step.
var _action_is_melee: bool = false
## True while the current committed melee is the heavy spin. Heavy swings are a
## single full-body commitment and must not be retriggered before the first one ends.
var _action_is_heavy: bool = false
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
var _attack_knockback_strength: float = GameSettings.spell_melee_knockback
## How hard a connecting impact kicks the camera. Chosen alongside the sounds, for
## the same reason: it is a property of the move, not of its damage number.
var _attack_shake_strength: float = 0.0
## The spell whose wind-up is playing, and when in the action it actually goes off.
## Empty when no cast is in flight. Like melee damage, the effect lands on the clip's
## measured release frame rather than on the keypress.
var _pending_cast_id: String = ""
var _pending_cast_time: float = 0.0
var _pending_cast_charge: float = 1.0
## The clip whose LEAD-IN is being held while a chargeable spell is charged, empty when
## no charge is being wound up. Kept so the release can continue that same shot instead
## of firing a second one over the top of it - see _begin_cast.
var _cast_windup_clip: String = ""
## The chain lapses if nothing continues it, so a stage landed a minute ago isn't
## still counted as step one.
var _combo_reset_timer: float = 0.0

var is_blocking: bool = false
## Whether this player is standing on something, published by the machine that owns them.
##
## `is_on_floor()` cannot answer it anywhere else. CharacterBody3D only updates that flag
## inside `move_and_slide()`, and a puppet never calls it - its position arrives over the
## wire - so `is_on_floor()` on somebody else's avatar is false forever. PlayerAnimator
## checks it before anything else and plays the JUMP clip when it is false, which is why a
## teammate walked around the map in a permanent mid-air pose while their attacks, which
## come through _net_play_action and bypass locomotion entirely, looked perfectly fine.
var is_grounded: bool = true
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
	SignalBus.team_level_changed.connect(_on_team_level_changed)

	# A build kept from a match this player was dropped out of. Applied here rather than
	# by whoever spawned the avatar, because the spawn runs on every peer and a build
	# belongs to exactly one of them.
	if is_local and PlayerRegistry.has_saved_build():
		apply_build(PlayerRegistry.take_saved_build())

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
	if is_downed:
		# A body on the ground does not pivot to follow the mouse. Yaw goes to the
		# camera rig instead of the body, so a downed player can still look around -
		# watching for the teammate coming to revive them is most of what there is to
		# do while down - without the corpse spinning in place.
		#
		# Set on the euler rather than rotate_y(): the pivot carries pitch too, and
		# rotating about its local axes once both are non-zero accumulates roll. Godot
		# composes euler angles in YXZ order, which is exactly yaw-then-pitch.
		camera_pivot.rotation.y += yaw
	else:
		rotate_y(yaw)
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x + pitch, -deg_to_rad(70.0), deg_to_rad(30.0)
	)

## Replicates the least that produces the most: position, rotation and VELOCITY.
##
## Velocity is the one that matters. `PlayerAnimator.update_locomotion()` already picks
## idle, walk, run, strafe and their playback speeds from velocity alone, so sending it
## reconstructs every locomotion animation on every client without replicating a single
## bone. Discrete actions - swings, casts, the heavy charge - are sent as RPCs instead
## (see _net_play_action), and one-shot spell visuals go through NetFx.
##
## TWO synchronizers, because this node has two authors.
##
## What the PLAYER does is authored by the machine they are sitting at: where they stand,
## which way they face, how far into a charge they are. What HAPPENS TO them is authored
## by the host: enemies only think on the server, so the server is where take_damage runs
## and where the shields are spent. Health on the owner-authored synchronizer would never
## have left the host - a client watched its own bar sit at full while the host quietly
## counted it down to nothing, and the first the player knew of it was being downed.
func _build_synchronizer() -> void:
	# --- what this player is doing, published by whoever is playing them --------
	var owned := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":velocity",
			":is_grounded", ":is_blocking",
			":is_charging", ":charge_timer", ":charge_max_time"]:
		owned.add_property(NodePath(property))
		owned.property_set_replication_mode(
			NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = owned
	# The owner publishes; everyone else listens. Without this every peer would try to
	# author every avatar and they would fight.
	sync.set_multiplayer_authority(get_multiplayer_authority())
	add_child(sync)

	# --- what is happening to them, published by the host ----------------------
	#
	# ON_CHANGE rather than ALWAYS: a health bar that has not moved is not worth a packet
	# sixty times a second, and between them these six change a handful of times a fight.
	var vitals := SceneReplicationConfig.new()
	for property: String in [":hp", ":max_hp",
			":glorious_anthem_shield", ":rhystic_shield", ":protection_shield",
			":_channel_id", ":_channel_rank", ":_channel_held",
			":_giant_scale_mult"]:
		vitals.add_property(NodePath(property))

	var vitals_sync := MultiplayerSynchronizer.new()
	vitals_sync.name = "VitalsSync"
	vitals_sync.replication_config = vitals
	vitals_sync.set_multiplayer_authority(MultiplayerPeer.TARGET_PEER_SERVER)
	vitals_sync.synchronized.connect(_on_vitals_synchronized)
	add_child(vitals_sync)


## The host has just told us what our health and shields really are. Nothing here changes
## a number - it announces the ones that arrived, because every other place that moves hp
## or a shield emits as it does so and replication does not go through any of them.
func _on_vitals_synchronized() -> void:
	if not is_local:
		return
	_emit_health_changed()
	emit_shield_changed()


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
				aura_ranks.clear()
				for color: String in affinity_ranks:
					affinity_ranks[color] = 0
				_applied_green_affinity_rank = -1
				_sync_auras()
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
				_sync_auras()
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
		elif event.is_action_released("cast_spell"):
			if is_charging:
				release_charged_spell()
			elif _channel_id != "" and _channel_held:
				_end_channel()

		if event.is_action_pressed("cycle_spell_prev"):
			cycle_spell(-1)
		elif event.is_action_pressed("cycle_spell_next"):
			cycle_spell(1)

		# Number keys are a real hotbar: they select AND cast, which is what the ten
		# slots the HUD already draws look like they do. They mirror "cast_spell"
		# exactly, press and release, so a chargeable spell charges while the key is
		# held and fires when it comes up - otherwise 1-5 could start a charge with
		# no way to release it.
		if event is InputEventKey and not event.echo:
			var keycode: int = event.keycode
			var target_idx: int = -1
			if keycode >= KEY_1 and keycode <= KEY_9:
				target_idx = keycode - KEY_1
			if target_idx >= 0 and target_idx < quick_slots.size():
				if event.pressed:
					if is_spell_unlocked(target_idx):
						if active_spell_index != target_idx:
							active_spell_index = target_idx
							SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))
						cast_active_spell()
				elif is_charging and charging_spell_id == _get_spell_id_for_slot(target_idx):
					release_charged_spell()
				elif _channel_id != "" and _channel_slot == target_idx:
					_end_channel()

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
	quick_slots = _empty_quick_slots()
	SignalBus.quick_slots_changed.emit()


## A full bar of empty slots. Static so the property's own initializer can call it, which
## is what keeps the bar's length and QUICK_SLOT_COUNT from drifting apart.
static func _empty_quick_slots() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(QUICK_SLOT_COUNT)
	return slots


## Everything this player SPENT, in a form that survives the avatar being destroyed.
##
## Only the choices are saved, never the moment-to-moment state: no hp, no cooldowns, no
## position. Coming back from a dropped connection puts you back in your build, not back
## in the middle of your last fight.
func export_build() -> Dictionary:
	return {
		"skill_points": skill_points,
		"spent_skill_points": spent_skill_points,
		"spell_ranks": spell_ranks.duplicate(true),
		"affinity_ranks": affinity_ranks.duplicate(true),
		"aura_ranks": aura_ranks.duplicate(true),
		"quick_slots": quick_slots.duplicate(),
		"unlocked_spells_in_path": unlocked_spells_in_path.duplicate(),
		"chosen_color_path": chosen_color_path,
		# Both of these were missing, and both cost the player something real. The five
		# neutral passives cost a skill point per rank, so coming back without them left
		# `spent_skill_points` counting points that had bought nothing; Blade Dance is the
		# third melee stage, granted at BLADE_DANCE_LEVEL and never saved.
		"passive_ranks": passive_ranks.duplicate(true),
		"melee_combo_extended": melee_combo_extended,
	}


## The other half of export_build, applied to a freshly spawned local avatar.
##
## The aura goes through grant_aura_rank rather than being assigned, because the aura
## is not a string - it is a signal connection and a spawned orb, and only that function
## builds them.
func apply_build(build: Dictionary) -> void:
	if build.is_empty():
		return
	skill_points = int(build.get("skill_points", skill_points))
	spent_skill_points = int(build.get("spent_skill_points", spent_skill_points))
	spell_ranks = (build.get("spell_ranks", {}) as Dictionary).duplicate(true)
	affinity_ranks = (build.get("affinity_ranks", affinity_ranks) as Dictionary).duplicate(true)
	aura_ranks = (build.get("aura_ranks", {}) as Dictionary).duplicate(true)
	passive_ranks = (build.get("passive_ranks", {}) as Dictionary).duplicate(true)
	melee_combo_extended = bool(build.get("melee_combo_extended", melee_combo_extended))
	chosen_color_path = String(build.get("chosen_color_path", ""))

	unlocked_spells_in_path.clear()
	for spell_id in build.get("unlocked_spells_in_path", []):
		unlocked_spells_in_path.append(String(spell_id))

	var slots: Array[String] = _empty_quick_slots()
	var saved_slots: Array = build.get("quick_slots", [])
	for i in mini(slots.size(), saved_slots.size()):
		slots[i] = String(saved_slots[i])
	quick_slots = slots

	# Forces the green affinity's move-speed bonus to be recomputed: it is applied as a
	# DIFFERENCE against the last rank seen, and this avatar has seen none.
	_applied_green_affinity_rank = -1
	_sync_auras()

	# Whatever the team earned while this player was away, settled against the total
	# RunState has been keeping rather than against the events they missed.
	reconcile_skill_points()

	SignalBus.quick_slots_changed.emit()
	SignalBus.active_spell_changed.emit(get_spell_name_for_slot(active_spell_index))


## Sets unspent points to what this player is OWED, rather than to what they happened to
## be handed while their avatar existed.
##
## Points were paid out by iterating the avatars standing in the map at the instant of a
## level-up, so every level the team gained while a player was disconnected paid them
## nothing - they returned with the number they left with while everyone else had moved
## on. The total is the honest source: start, plus everything awarded this run, minus
## everything this player has spent.
func reconcile_skill_points() -> void:
	var owed: int = STARTING_SKILL_POINTS + RunState.points_awarded - spent_skill_points
	if owed == skill_points:
		return
	skill_points = maxi(owed, 0)
	SignalBus.skill_points_changed.emit(self, skill_points)


func is_spell_owned(spell_id: String) -> bool:
	return get_spell_rank(spell_id) > 0


func get_spell_rank(spell_id: String) -> int:
	return int(spell_ranks.get(spell_id, 0))


## Everything this player has put into one colour, counted in ranks: the colour's affinity
## plus every rank held in its five spells.
##
## Derived rather than stored. A running total kept alongside the purchases would be one
## more thing to keep in step - and one more thing to migrate when an old save is loaded -
## for a sum over ten small numbers.
func color_investment(color: String) -> int:
	var total: int = get_affinity_rank(color)
	for index: int in range(1, 6):
		total += get_spell_rank("%s_%d" % [color, index])
	return total


## The colour a spell belongs to, from its id ("red_3" -> "red"). Auras and passives are
## not colour-scoped this way and never reach here.
static func spell_color(spell_id: String) -> String:
	var parts: PackedStringArray = spell_id.split("_")
	return parts[0] if parts.size() > 1 else ""


## Whether the NEXT rank of this spell is reachable right now, and why not if it is not.
## Returns an empty string when it is buyable, otherwise the reason to show the player -
## the tree prints it verbatim, so "cannot" is never silent.
func spell_rank_blocker(spell_id: String) -> String:
	var rank: int = get_spell_rank(spell_id)
	if rank >= GameSettings.spell_max_rank:
		return "Maximum rank"
	# The same ladder that decides which tier is reachable decides how deep a spell can go.
	# Rank 5 therefore costs a real commitment to the colour rather than waiting for the
	# team's clock to catch up - and a player who wants it can go and earn it now.
	var color: String = spell_color(spell_id)
	var required: int = GameSettings.color_investment_requirement(rank + 1)
	if color != "" and color_investment(color) < required:
		return "Needs %d invested in %s" % [required, color.capitalize()]
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
	# Vigilance (Selesnya passive) lengthens everything with a duration, so it rides the
	# one funnel every spell's duration already passes through.
	return GameSettings.rank_duration_mult(_casting_rank) * _vigilance_mult()


## The part of a duration bonus that is NOT rank. For a spell whose rank curve is written
## out explicitly (Suction), so the passive still applies without rank being counted twice.
func _vigilance_mult() -> float:
	return 1.0 + get_passive_bonus("vigilance")


## Rank of a neutral passive, 0 if not owned. The five passives live between the
## colours in the tree and cost one skill point per rank, exactly like spells.
func get_passive_rank(passive_id: String) -> int:
	return int(passive_ranks.get(passive_id, 0))


func grant_passive_rank(passive_id: String) -> bool:
	var rank: int = get_passive_rank(passive_id)
	if rank >= GameSettings.spell_max_rank:
		return false
	passive_ranks[passive_id] = rank + 1
	SignalBus.passive_rank_changed.emit(passive_id, rank + 1)
	return true


## What a passive grants at a given rank: its GameSettings minimum at rank 1, its
## ceiling at max rank, walked the way every other fraction skill walks. All five are
## fractions of something - a chance, a speed bonus, an HP share - never flat numbers.
func get_passive_bonus_at(passive_id: String, rank: int) -> float:
	if rank <= 0:
		return 0.0
	match passive_id:
		"vigilance":
			return GameSettings.rank_fraction(GameSettings.passive_vigilance_duration_min, GameSettings.passive_vigilance_duration_max, rank)
		"double_strike":
			return GameSettings.rank_fraction(GameSettings.passive_crit_chance_min, GameSettings.passive_crit_chance_max, rank)
		"trample_strike":
			return GameSettings.rank_fraction(GameSettings.passive_trample_hp_fraction_min, GameSettings.passive_trample_hp_fraction_max, rank)
		"haste":
			return GameSettings.rank_fraction(GameSettings.passive_haste_speed_min, GameSettings.passive_haste_speed_max, rank)
		"flight":
			return GameSettings.rank_fraction(GameSettings.passive_flight_jump_min, GameSettings.passive_flight_jump_max, rank)
	return 0.0


func get_passive_bonus(passive_id: String) -> float:
	return get_passive_bonus_at(passive_id, get_passive_rank(passive_id))


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
	_sync_auras()
	SignalBus.skill_unlocked.emit(color)

func get_affinity_rank(color: String) -> int:
	return int(affinity_ranks.get(color, 0))

func get_affinity_bonus(color: String) -> float:
	var rank: int = get_affinity_rank(color)
	return float(rank) * GameSettings.affinity_rank_bonus_base

func get_spell_rank_requirement(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= GameSettings.affinity_spell_rank_requirements.size():
		return 999999
	return GameSettings.affinity_spell_rank_requirements[slot_idx]

func on_damage_dealt(amount: float) -> void:
	# EnemyBase clamps this to the health actually removed before calling, so overkill on a
	# finishing blow is not counted - the scoreboard shows damage done, not damage rolled.
	add_stat("damage_dealt", amount)
	# Personal affinity plus the team's Exquisite Blood stacks - the enchantment
	# deliberately echoes the colour's own affinity rather than inventing a new axis.
	var lifesteal: float = get_affinity_bonus("black") + RunState.lifesteal_bonus()
	if lifesteal > 0.0 and amount > 0.0:
		add_stat("heal_self", heal(amount * lifesteal))

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


func _spell_cooldown_recovery_rate() -> float:
	var cdr: float = 1.0
	if has_aura("aura_rhystic_study"):
		cdr = GameSettings.aura_bonus_mult(GameSettings.aura_rhystic_study_cdr_mult, get_aura_rank("aura_rhystic_study"))
	return (1.0 + get_affinity_bonus("blue")) / maxf(cdr, 0.01)

func is_chargeable(spell_id: String) -> bool:
	return SpellDatabase.is_chargeable(spell_id)

func cast_active_spell() -> void:
	if is_charging or _channel_id != "":
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

	if SpellDatabase.is_channelled(spell_id):
		_casting_rank = maxi(get_spell_rank(spell_id), 1)
		_run_spell_effect(spell_id, 1.0)
	elif is_chargeable(spell_id):
		is_charging = true
		charge_timer = 0.0
		charge_max_time = GameSettings.spell_charge_max_time
		charging_spell_id = spell_id
		_begin_spell_windup(spell_id)
		_spawn_charge_orb()
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, true)
	else:
		_begin_cast(spell_id, 1.0)


## A cast is a committed action like a swing, so it queues behind one rather than
## firing over the top of it. Blocking is not checked: raising the guard already
## requires no action in flight, so starting a cast drops it on the next frame.
func _can_start_cast() -> bool:
	return not is_downed and _stagger_timer <= 0.0 and _action_timer <= 0.0 and _channel_id == ""


## Starts the held part of a chargeable spell: the cast clip's discarded lead-in, spread
## across the whole charge window, so the caster is visibly building the spell for as long
## as the button is down instead of standing still until it fires.
##
## The lead-in is where the animation STOPS (see PlayerAnimator.play_windup), so a charge
## can never reach the release frame on its own - and because the charge fires by itself
## at charge_max_time, the raise arrives at the top exactly as the spell goes off.
##
## Upper body only, unlike the heavy's raise: charging does not root the caster, and the
## legs keeping their own cycle is what lets them reposition while the spell builds.
func _begin_spell_windup(spell_id: String) -> void:
	_cast_windup_clip = ""
	var row: Dictionary = SpellDatabase.get_spell(spell_id)
	var clip: String = String(row.get("cast_clip", ""))
	if clip == "" or not animator.has_clip(clip):
		return
	var upper_body: bool = bool(row.get("upper_body", not bool(row.get("roots", false))))
	if animator.play_windup(clip, maxf(charge_max_time, 0.01), upper_body):
		_cast_windup_clip = clip
		if Net.is_active() and is_local:
			_net_play_windup.rpc(clip, maxf(charge_max_time, 0.01), upper_body)


## Drops a wind-up that is not going to become a cast, so a charge the player gave up on
## does not leave the caster holding a pose for a spell that is no longer coming.
func _stop_spell_windup() -> void:
	if _cast_windup_clip == "":
		return
	_cast_windup_clip = ""
	animator.stop_action()
	if Net.is_active() and is_local:
		_net_stop_action.rpc()


## Builds the orb and parents it to the WORLD rather than to the player.
##
## Parented to the scene because the caster keeps moving while they charge - charging does not
## root them - and an orb parented to the body would inherit the body's rotation as well as
## its position, so it would swing rather than sit in the hands as the character turns.
## _update_charge_orb re-anchors it every frame instead.
func _spawn_charge_orb() -> void:
	if _charge_orb != null:
		return
	_build_charge_orb(_rank_area())
	# One small packet at the start, and nothing after it. Every other peer builds its own
	# ball from the size and then drives it off the replicated `charge_timer`, so a three
	# second charge does not cost three seconds of updates - the growth curve is already
	# written down in ChargeOrb, identically on every machine.
	if Net.is_active() and is_local:
		_net_charge_start.rpc(_rank_area())


func _build_charge_orb(size_scale: float) -> void:
	if _charge_orb != null:
		return
	_charge_orb = CHARGE_ORB_SCRIPT.new()
	_charge_orb.setup(size_scale)
	var scene: Node = get_tree().current_scene
	if scene == null:
		_charge_orb = null
		return
	scene.add_child(_charge_orb)
	_update_charge_orb()


@rpc("authority", "call_remote", "reliable")
func _net_charge_start(size_scale: float) -> void:
	_build_charge_orb(size_scale)


## The two ways a charge ends, told apart because they look nothing alike: a released ball
## is thrown and a dropped one collapses inward. `is_charging` alone could not separate
## them - it goes false either way - and a thrown fireball that fizzled in the caster's
## hands on every other screen is worse than no effect at all.
@rpc("authority", "call_remote", "reliable")
func _net_charge_end(released: bool) -> void:
	if released:
		_release_charge_orb()
	else:
		_fizzle_charge_orb()


## Moves the orb to the caster's hands and tells it how far along the charge is. The one place
## the effect is driven from, so the timer and the visual cannot disagree.
func _update_charge_orb() -> void:
	if not is_instance_valid(_charge_orb):
		return
	# Pushed FORWARD off the hand midpoint. `cast_red`'s lead-in raises one arm rather than
	# bringing both together, so the midpoint of the two hands sits inside the caster's chest
	# for most of the charge - the ball intersected the torso instead of being held out. The
	# offset is applied here rather than in hand_midpoint(), which stays honest about what it
	# measures; this is the spell deciding where a held thing belongs.
	var anchor: Transform3D = animator.hand_midpoint()
	anchor.origin += -global_transform.basis.z * CHARGE_ORB_REACH
	_charge_orb.global_transform = anchor
	var progress: float = clampf(charge_timer / maxf(charge_max_time, 0.01), 0.0, 1.0)
	_charge_orb.set_progress(progress)
	if progress >= 1.0:
		_charge_orb.flare()


## Hands the orb off, and returns where it WAS - the projectile spawns from there rather than
## from the camera, which is what makes the bolt look thrown instead of appearing in mid-air.
## Returns a zero vector when there is no orb, and the caller falls back to the camera.
func _release_charge_orb() -> Vector3:
	if Net.is_active() and is_local:
		_net_charge_end.rpc(true)
	if not is_instance_valid(_charge_orb):
		_charge_orb = null
		return Vector3.ZERO
	var muzzle: Vector3 = _charge_orb.global_position
	_charge_orb.release()
	_charge_orb = null
	return muzzle


## Dropped rather than thrown: collapses inward, so an abandoned charge does not look like a
## spell that went off somewhere the player could not see.
func _fizzle_charge_orb() -> void:
	if Net.is_active() and is_local:
		_net_charge_end.rpc(false)
	if is_instance_valid(_charge_orb):
		_charge_orb.fizzle()
	_charge_orb = null


## Abandons a charge in progress - the state, the HUD readout and the raise being held.
## Nothing is cast and nothing is spent: a dropped charge costs the player only the time
## they held it, since the cooldown is stamped in execute_spell() and never reached.
func _cancel_spell_charge() -> void:
	if is_charging:
		is_charging = false
		charge_timer = 0.0
		charging_spell_id = ""
		SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	_fizzle_charge_orb()
	_stop_spell_windup()


## Starts a spell's wind-up. The effect itself does not happen here - it fires from
## _update_actions() when the animation reaches the release frame the builder
## measured for that clip, exactly as melee damage lands on its impact frames.
##
## `windup_progress` is how far into the charge window a held cast got, or negative for
## an ordinary uncharged one. A released charge does NOT start a new shot: the one the
## charge is already playing speeds up to cast pace, so the caster continues from the
## exact pose the wind-up reached rather than snapping back and starting over - the same
## continuity _release_heavy_charge() gives the heavy swing.
func _begin_cast(spell_id: String, charge_pct: float, windup_progress: float = -1.0) -> void:
	var row: Dictionary = SpellDatabase.get_spell(spell_id)
	var clip: String = String(row.get("cast_clip", ""))
	var duration: float = float(row.get("cast_duration", 0.4))
	var roots: bool = bool(row.get("roots", false))
	var from_windup: bool = windup_progress >= 0.0 and _cast_windup_clip == clip
	_cast_windup_clip = ""

	if clip == "":
		# Deliberately instant: the spell declares no cast animation and resolves on the
		# frame it is pressed. Displace is the one that wants this - see its entry in
		# SpellDatabase.
		execute_spell(spell_id, charge_pct)
		return
	if not animator.has_clip(clip):
		# A clip was NAMED and is missing, which is a content bug rather than a choice.
		# Still fires, so the spell is not swallowed, but says so.
		push_warning("Spell '%s' has no usable cast clip '%s'; firing instantly" % [spell_id, clip])
		execute_spell(spell_id, charge_pct)
		return

	var release_on_last: bool = bool(row.get("release_on_last", false))
	var commit: float = float(row.get("commit", duration))
	# Clip-seconds per real second: the pace an uncharged cast of this spell plays at,
	# matched exactly, so continuing out of a wind-up makes the cast LONGER - there is
	# more lead-in still to cover - rather than slower.
	var pace: float = animator.strike_length(clip) / maxf(duration, 0.01)
	# Where the raise actually got to, in seconds of stored clip. A full charge sits
	# exactly at the start of the strike window, so it finishes as an ordinary cast.
	var from: float = animator.windup_length(clip) * clampf(windup_progress, 0.0, 1.0)
	var remaining: float = animator.windup_length(clip) + animator.strike_length(clip) - from

	_casting_rank = get_spell_rank(spell_id)
	_pending_cast_id = spell_id
	_pending_cast_charge = charge_pct
	if from_windup:
		# Scheduled off the position the animation continues from, so the effect still
		# lands on its own release frame however briefly the charge was held.
		_pending_cast_time = maxf(
			(animator.release_offset(clip, release_on_last) - from) / maxf(pace, 0.01), 0.0
		)
		# Only the leftover lead-in is added; the cast's own commitment is unchanged.
		commit += remaining / maxf(pace, 0.01) - duration
	else:
		_pending_cast_time = animator.release_time(clip, duration, release_on_last)
	# A spell whose animation MOVES the caster has to start moving now, not on the
	# release frame - the release is the payload landing, and by then the leap has to
	# already have carried them there. Fire Dash is the same shape: the release frame
	# lights the trail the dash has by then already drawn.
	match spell_id:
		"green_1": SpellEffects.cast_green_titanic_leap(self)
		"red_2": SpellEffects.cast_red_fire_dash(self)
	_pending_hits.clear()
	# The two halves separately, rather than through _begin_action: a cast may be
	# committed for less time than its animation runs, and a recovery that is still
	# playing after the player has control back is the whole point of `commit`.
	_commit_action(commit, roots, false)
	# Broadcast as well as played. Only _begin_action did this, which covered melee and
	# left every SPELL animation on the caster's own screen - the cast that was noticed
	# was Fire Cone, because a channel holds its pose for seconds and the short ones were
	# simply missed.
	if from_windup:
		var release_pace: float = remaining / maxf(pace, 0.01)
		animator.release_windup(remaining, release_pace)
		if Net.is_active() and is_local:
			_net_release_windup.rpc(remaining, release_pace)
	else:
		var upper: bool = bool(row.get("upper_body", not roots))
		animator.play_action(clip, duration, upper)
		if Net.is_active() and is_local:
			_net_play_action.rpc(clip, duration, upper, PlayerAnimator.FULL_WINDOW)

func release_charged_spell() -> void:
	if not is_charging:
		return
		
	# The payload has a 20% floor, but the ANIMATION does not: the raise is wherever the
	# hold actually left it, so a tap continues from near the start of the lead-in.
	var progress: float = clampf(charge_timer / maxf(charge_max_time, 0.01), 0.0, 1.0)
	var pct = clamp(progress, 0.2, 1.0)
	var spell_id = charging_spell_id
	is_charging = false
	charge_timer = 0.0
	SignalBus.spell_charge_changed.emit(0.0, charge_max_time, false)
	if not is_spell_owned(spell_id) or spell_cooldown_timers.get(spell_id, 0.0) > 0.0:
		_fizzle_charge_orb()
		_stop_spell_windup()
		return
	if not _can_start_cast():
		_fizzle_charge_orb()
		_stop_spell_windup()
		return
	# Where the ball actually was, handed to the cast below. Taken HERE rather than in
	# cast_red_fireball because the cast is deferred to the clip's release frame, by which
	# point the charge state is long gone.
	_charge_muzzle = _release_charge_orb()
	_begin_cast(spell_id, pct, progress)

## The moment a spell's effect actually happens, on the frame its clip releases.
##
## The cooldown and the animation are local and already ran; only the EFFECT needs an
## authority, because a projectile spawned on a client is invisible to everyone else and
## its damage would never reach the server's enemies.
func execute_spell(spell_id: String, charge_pct: float = 1.0) -> void:
	var cooldown: float = _get_spell_cooldown(spell_id)
	if cooldown > 0.0:
		spell_cooldown_timers[spell_id] = cooldown / _spell_cooldown_recovery_rate()
	# Whether the caster is still HOLDING the button, read on the machine that owns the
	# keyboard. Only Fire Cone uses it - a channel ends when the button comes up - and the
	# server has no way to find it out for itself: asking Input there answers for the HOST,
	# which is how a client's channel ended the instant the host was not pressing anything.
	var held: bool = is_local and Input.is_action_pressed("cast_spell")
	if Net.is_active() and not Net.is_server():
		_request_spell.rpc_id(1, spell_id, charge_pct, held)
		return
	_run_spell_effect(spell_id, charge_pct, held)


@rpc("any_peer", "call_local", "reliable")
func _request_spell(spell_id: String, charge_pct: float, held: bool = false) -> void:
	if not Net.is_server():
		return
	_run_spell_effect(spell_id, charge_pct, held)


func _run_spell_effect(spell_id: String, charge_pct: float, held: bool = false) -> void:
	# A spell cast by a CLIENT arrives here on the server, where _begin_cast never ran -
	# so the rank is resolved again rather than assumed to be left over from the cast.
	_casting_rank = maxi(get_spell_rank(spell_id), 1)
	
	# Rhystic Study Shield trigger on cast
	if has_aura("aura_rhystic_study"):
		rhystic_shield = minf(
			rhystic_shield + GameSettings.aura_rhystic_study_shield_amount * get_aura_rank_mult("aura_rhystic_study"),
			GameSettings.aura_rhystic_study_shield_max * get_aura_rank_mult("aura_rhystic_study")
		)
		emit_shield_changed()
		
	match spell_id:
		# --- WHITE ---
		"white_1": SpellEffects.cast_white_exalted_strike(self)
		"white_2": SpellEffects.cast_white_circle_of_protection(self)
		"white_3": SpellEffects.cast_white_reprisal_ward(self)
		"white_4": SpellEffects.cast_white_wrath_of_god(self)
		"white_5": SpellEffects.cast_white_rally_the_fallen(self)
		# --- BLUE ---
		"blue_1": SpellEffects.cast_blue_unsummon(self)
		"blue_2": SpellEffects.cast_blue_frostwave(self)
		"blue_3": SpellEffects.cast_blue_suction(self)
		"blue_4": SpellEffects.cast_blue_wall_of_frost(self)
		"blue_5": SpellEffects.cast_blue_displace(self)
		# --- BLACK ---
		"black_1": SpellEffects.cast_black_doom_blade(self)
		"black_2": SpellEffects.cast_black_fear(self)
		"black_3": SpellEffects.cast_black_kill(self)
		"black_4": SpellEffects.cast_black_wall_of_souls(self)
		"black_5": SpellEffects.cast_black_zombify(self)
		# --- RED ---
		"red_1": SpellEffects.cast_red_fireball(self, charge_pct)
		# The TRAIL, not the launch: the dash itself was already fired when the cast
		# began, exactly like Titanic Brawl below.
		"red_2": SpellEffects._lay_fire_trail(self)
		"red_3": SpellEffects.cast_red_rain_ember(self)
		"red_4": SpellEffects.cast_red_fire_cone(self, held)
		"red_5": SpellEffects.cast_red_lightning_bolt(self)
		# --- GREEN ---
		# The LANDING, not the launch: the leap itself was already fired when the cast
		# began, and this is the clip's final impact frame arriving.
		"green_1": SpellEffects._slam_ground(self)
		"green_2": SpellEffects.cast_green_giant_growth(self)
		"green_3": SpellEffects.cast_green_fog(self)
		"green_4": SpellEffects.cast_green_roar(self)
		"green_5": SpellEffects.cast_green_ironbark(self)

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
		_play_sound(_block_sound_for(source), global_position)
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
			# A block is a hit that never happened, so without this the ward's defensive half
			# is invisible: a flash and no number is indistinguishable from an enemy missing.
			# Said in the same place the damage would have appeared, so the ward is legible
			# from what is NOT there.
			NetFx.damage_number(
				global_position + Vector3(randf_range(-0.2, 0.2), 1.9, randf_range(-0.2, 0.2)),
				0.0, Color(1.0, 0.95, 0.7), "Warded"
			)
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
		# Any hit that reaches the shields restarts Anthem's recharge delay, including one the
		# shields eat outright - a shield absorbing damage is the player being in trouble, which
		# is exactly when the recharge should not be running.
		_undamaged_timer = 0.0
		var shield_before: float = total_shield()
		var absorbed: float = minf(glorious_anthem_shield, remaining_damage)
		glorious_anthem_shield -= absorbed
		remaining_damage -= absorbed
		absorbed = minf(rhystic_shield, remaining_damage)
		rhystic_shield -= absorbed
		remaining_damage -= absorbed
		# Circle of Protection is spent LAST of the three, because it is the only one a
		# player chose to cast - a aura shield regenerates on its own and this does not.
		absorbed = minf(protection_shield, remaining_damage)
		protection_shield -= absorbed
		remaining_damage -= absorbed
		if not is_equal_approx(shield_before, total_shield()):
			emit_shield_changed()

	if remaining_damage <= 0.0:
		return

	# Counted here rather than at the top of the function, so it is damage that actually
	# reached HEALTH: everything a block, Ironbark, a ward or a shield ate is damage the
	# player took steps to avoid, and crediting it would make the best defensive builds look
	# like the ones being hit hardest.
	add_stat("damage_taken", remaining_damage)
	hp -= remaining_damage
	_emit_health_changed()
	var spawn_pos = global_position + Vector3(randf_range(-0.2, 0.2), 1.6, randf_range(-0.2, 0.2))
	NetFx.damage_number(spawn_pos, remaining_damage, Color(1.0, 0.25, 0.25), "")
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
	_cancel_spell_charge()
	_combo_stage = 0
	_combo_reset_timer = 0.0
	_cancel_heavy_charge()
	_clear_pending_swing()

## Recomputes maximum health and the aura's permanent effects from scratch whenever
## one of their inputs moves. Giant Growth is one of those inputs now: it adds flat health
## for a duration, and rebuilding the total rather than adding and subtracting is what
## stops the bonus drifting when the aura changes while the buff is up.
func _sync_auras() -> void:
	var green_affinity_rank: int = get_affinity_rank("green")
	var aura_signature: int = _aura_signature()
	if (
		_applied_auras == aura_signature
		and _applied_green_affinity_rank == green_affinity_rank
		and is_equal_approx(_applied_giant_bonus, _giant_bonus_hp)
	):
		return

	var health_ratio: float = hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = GameSettings.player_max_hp
	max_hp *= 1.0 + get_affinity_bonus("green")
	# Circle of Protection's shield is deliberately NOT cleared here. This function re-runs
	# whenever the giant bonus changes, i.e. on every Giant Growth, and a green/white player
	# growing should not lose a shield an ally just cast on them. Its own timer expires it.
	rhystic_shield = 0.0
	glorious_anthem_shield = 0.0
	if has_aura("aura_sylvan_library"):
		max_hp *= GameSettings.aura_bonus_mult(GameSettings.aura_sylvan_library_hp_mult, get_aura_rank("aura_sylvan_library"))
	if has_aura("aura_glorious_anthem"):
		glorious_anthem_shield = GameSettings.aura_glorious_anthem_shield * get_aura_rank_mult("aura_glorious_anthem")
	max_hp += _giant_bonus_hp
	hp = clampf(max_hp * health_ratio, 1.0, max_hp)
	if _applied_auras != aura_signature:
		_rebuild_aura_orbs()
	_applied_auras = aura_signature
	_applied_green_affinity_rank = green_affinity_rank
	_applied_giant_bonus = _giant_bonus_hp
	if has_aura("aura_grave_pact"):
		if not SignalBus.enemy_died_at.is_connected(_on_enemy_died_near):
			SignalBus.enemy_died_at.connect(_on_enemy_died_near)
	elif SignalBus.enemy_died_at.is_connected(_on_enemy_died_near):
		SignalBus.enemy_died_at.disconnect(_on_enemy_died_near)
	_emit_health_changed()
	emit_shield_changed()
	SignalBus.player_auras_changed.emit()


## Three of the aura choices are orbiting nodes. Rebuild them from ownership so old
## exclusive aura saves and new ranked aura choices both converge on the same state.
func _rebuild_aura_orbs() -> void:
	for aura_id: String in _aura_orbs.keys():
		var orb: Node3D = _aura_orbs[aura_id]
		if is_instance_valid(orb):
			remove_child(orb)
			orb.queue_free()
	_aura_orbs.clear()
	var orb_modes: Dictionary = {
		"aura_orb_of_frost": OrbitingOrb.Mode.FROST,
		"aura_orb_of_fire": OrbitingOrb.Mode.FIRE,
		"aura_healing_orb": OrbitingOrb.Mode.HEAL,
	}
	for aura_id: String in orb_modes.keys():
		if not has_aura(aura_id):
			continue
		var orb: Node3D = OrbitingOrb.create(int(orb_modes[aura_id]), self)
		orb.name = String(aura_id).capitalize()
		_aura_orbs[aura_id] = orb
		add_child(orb)


# --- the skill build, on every machine ----------------------------------------
#
# The server resolves every spell (see _run_spell_effect), and until this existed it
# resolved a CLIENT's spells against an empty build. `_casting_rank` fell back to 1,
# `has_aura` answered false for everything, `get_spell_damage_multiplier` found no
# affinity, and `_update_shields` had no Anthem to recharge. A client with a maxed tree
# cast rank-1 spells with nothing behind them - on every screen, their own included. The
# tree was drawn, bought and paid for, and did nothing.
#
# Broadcast rather than sent to the server alone, because the aura ORBS come out of the
# same state: a teammate's orbiting frost orb is theirs to show, not the host's.


## Everything about this player that a spell of theirs needs to know.
func build_snapshot() -> Dictionary:
	return {
		"path": chosen_color_path,
		"unlocked": unlocked_spells_in_path,
		"spells": spell_ranks,
		"auras": aura_ranks,
		"affinity": affinity_ranks,
		"passives": passive_ranks,
		"combo": melee_combo_extended,
	}


## Sends the build out when it has actually moved.
##
## A dirty CHECK rather than a notification from each of the six places that can change a
## build - grant_spell_rank, grant_aura_rank, grant_passive_rank, the affinity purchase
## and the two debug resets. A notification is a thing a future skill-tree change can
## forget to send; watching the state cannot be forgotten, and the same reasoning already
## drives _sync_auras and _sync_channel_fx.
func _publish_build() -> void:
	if not Net.is_active() or not is_local:
		return
	var fingerprint: int = _build_fingerprint()
	if fingerprint == _published_build:
		return
	_published_build = fingerprint
	_net_sync_build.rpc(build_snapshot())


## A number that changes when any part of the build does.
##
## This runs every frame, so it must not allocate its answer. It used to be
## `JSON.stringify(build_snapshot())`, which built a dictionary with seven string keys and
## then serialised the whole thing to text sixty times a second in order to notice that
## nothing had changed. The snapshot is now built only on the frame the fingerprint moves.
func _build_fingerprint() -> int:
	return hash([
		spell_ranks, aura_ranks, affinity_ranks, passive_ranks,
		unlocked_spells_in_path, chosen_color_path, melee_combo_extended,
	])


## Hands this player's build to ONE peer, from the server. For a player who joined after
## the build was set: `_publish_build` fires on a change, and every change a running match
## has already made happened before the newcomer connected.
##
## Never to the player it belongs to. The server's copy of a RECONNECTING player is an
## avatar spawned seconds ago with nothing in it, and they have just restored the real one
## from PlayerRegistry - so sending them "their" build would hand them back the empty one
## and wipe the tree they came back for. A build only ever travels away from its owner.
func push_build_to(peer_id: int) -> void:
	if not Net.is_server() or get_multiplayer_authority() == peer_id:
		return
	_net_sync_build.rpc_id(peer_id, build_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func _net_sync_build(build: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# The owner authors their own build; the server may FORWARD it (push_build_to). Nobody
	# else may write somebody else's tree.
	if sender != get_multiplayer_authority() and sender != 1:
		return
	# ...and nothing forwarded may write OUR OWN. This machine is where this player's tree
	# is authored, so a copy arriving from anywhere else is by definition the older one.
	# Belt and braces with the guard in push_build_to, because the failure it prevents -
	# a returning player losing their whole build - is silent and unrecoverable.
	if is_local and sender != get_multiplayer_authority():
		return
	_apply_build(build)


func _apply_build(build: Dictionary) -> void:
	chosen_color_path = String(build.get("path", ""))
	# Rebuilt element by element rather than assigned: `unlocked_spells_in_path` is an
	# Array[String], and a plain Array off the wire cannot be assigned to a typed one.
	unlocked_spells_in_path.clear()
	for spell_id: Variant in build.get("unlocked", []):
		unlocked_spells_in_path.append(String(spell_id))
	spell_ranks = (build.get("spells", {}) as Dictionary).duplicate()
	aura_ranks = (build.get("auras", {}) as Dictionary).duplicate()
	affinity_ranks = (build.get("affinity", {}) as Dictionary).duplicate()
	passive_ranks = (build.get("passives", {}) as Dictionary).duplicate()
	melee_combo_extended = bool(build.get("combo", false))
	# The whole reason it was sent: maximum health, the shields the auras carry, and the
	# orbiting ones. On the host this makes a client's spells resolve at their real rank;
	# on the other clients it puts that player's orbs around them.
	_sync_auras()


func get_aura_rank(aura_id: String) -> int:
	return int(aura_ranks.get(aura_id, 0))


## The generic rank curve for an aura's AMOUNTS - a shield's size, a heal, a dps, a radius.
## Rank 1 is x1.0, which is correct for those: the base number is already the benefit.
##
## NOT for an aura whose benefit is itself a MULTIPLIER (Fervor's x1.15, Rhystic Study's
## x0.7). Those want GameSettings.aura_bonus_mult(), which walks from a smaller bonus to the
## listed one. Feeding this into `lerpf(1.0, ceiling, mult - 1.0)` is what silently made rank
## 1 of five different auras grant nothing at all.
func get_aura_rank_mult(aura_id: String, curve: String = "damage") -> float:
	var rank: int = maxi(get_aura_rank(aura_id), 1)
	match curve:
		"area": return GameSettings.rank_area_mult(rank)
		"duration": return GameSettings.rank_duration_mult(rank)
		_: return GameSettings.rank_damage_mult(rank)


func has_aura(aura_id: String) -> bool:
	return get_aura_rank(aura_id) > 0


## A number that changes when the set of owned auras or their ranks does.
##
## Summed rather than concatenated, so it is order-independent without a sort: the same
## auras at the same ranks compare equal however the dictionary was filled. That property
## is the point - `_sync_auras` rebuilds the orbiting orbs when this moves, and an orb
## rebuild is visible, so it must not fire on a reordering that changed nothing.
##
## Was a sorted, joined "id:rank" string, built every frame for one player in order to
## discover that it matched the last one.
func _aura_signature() -> int:
	var signature: int = 0
	for aura_id: String in aura_ranks:
		var rank: int = get_aura_rank(aura_id)
		if rank > 0:
			signature += hash(aura_id) * (rank + 1)
	return signature


## Buys one rank of an aura. No exclusivity: the two auras a colour offers used to be a
## aura FORK - taking one refused the other for the rest of the run - and that check lived
## here. They are ordinary skills now, so both are buyable and both rank to 5 like anything
## else on the board.
func grant_aura_rank(aura_id: String) -> bool:
	if aura_id == "" or get_aura_rank(aura_id) >= GameSettings.spell_max_rank:
		return false
	var color: String = SpellDatabase.get_aura_color(aura_id)
	if color == "":
		return false
	aura_ranks[aura_id] = get_aura_rank(aura_id) + 1
	select_color_path(color)
	_sync_auras()
	return true


## Grave Pact: a kill near the player leaves a soul - a small heal, and one stack of a
## damage bonus whose timer restarts with every kill. Stop killing and the whole thing
## lapses at once rather than decaying one stack at a time, because a bonus that drains
## away slowly is one the player never notices losing.
func _on_enemy_died_near(position: Vector3) -> void:
	if is_downed or global_position.distance_to(position) > GameSettings.aura_grave_pact_radius:
		return
	heal(GameSettings.aura_grave_pact_heal * get_aura_rank_mult("aura_grave_pact"))
	_grave_stacks = mini(_grave_stacks + 1, GameSettings.aura_grave_pact_max_stacks)
	_grave_stack_timer = GameSettings.aura_grave_pact_stack_duration * get_aura_rank_mult("aura_grave_pact", "duration")

func get_spell_damage_multiplier() -> float:
	var affinity_multiplier: float = 1.0 + get_affinity_bonus("red")
	# Grave Pact's stacks multiply into the same term the affinity does, so they scale
	# everything the player does rather than only their melee.
	affinity_multiplier *= 1.0 + float(_grave_stacks) * GameSettings.aura_grave_pact_damage_per_stack * get_aura_rank_mult("aura_grave_pact")
	if has_aura("aura_glorious_anthem"):
		return GameSettings.aura_bonus_mult(GameSettings.aura_glorious_anthem_damage_mult, get_aura_rank("aura_glorious_anthem")) * RunState.damage_multiplier() * affinity_multiplier
	# Furnace of Rath is the team's, so it multiplies whatever this player already has.
	var team_multiplier: float = RunState.damage_multiplier()
	if has_aura("aura_phyrexian_arena"):
		return GameSettings.aura_bonus_mult(GameSettings.aura_phyrexian_arena_damage_mult, get_aura_rank("aura_phyrexian_arena")) * team_multiplier * affinity_multiplier
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

## Everything currently standing between the player and their health bar. The three shields
## are spent as one pool in take_damage - Anthem, then Rhystic, then Circle of Protection -
## so they are also reported as one number.
func total_shield() -> float:
	return glorious_anthem_shield + rhystic_shield + protection_shield


## Announces the shield pool to the HUD. Called from every place any of the three changes;
## there is no per-frame poll, so a site that forgets this is a shield the bar never draws.
##
## Local only, because the HUD has exactly one player to draw and a teammate's shield is not
## it. (`player_health_changed` has no such guard and predates this - in a real multiplayer
## session a remote player's damage still moves the local health bar. Left alone here rather
## than fixed in passing, but new code should not copy it.)
## The two shields that change on their own: Circle of Protection's expires, and Glorious
## Anthem's comes back. Rhystic Study's is not here - it is granted by casting and capped, so
## it has no clock of its own.
##
## Both halves report through emit_shield_changed only when the total actually MOVED. This runs
## every physics frame, and the recharge moves the number by a fraction each one; announcing all
## of that would push a signal at the HUD sixty times a second for three seconds.
func _update_shields(delta: float) -> void:
	var before: float = total_shield()
	_undamaged_timer += delta

	if _protection_shield_timer > 0.0:
		_protection_shield_timer -= delta
		if _protection_shield_timer <= 0.0:
			_protection_shield_timer = 0.0
			protection_shield = 0.0

	if has_aura("aura_glorious_anthem") and not is_downed:
		var full: float = GameSettings.aura_glorious_anthem_shield * get_aura_rank_mult("aura_glorious_anthem")
		if glorious_anthem_shield < full and _undamaged_timer >= GameSettings.aura_glorious_anthem_recharge_delay:
			glorious_anthem_shield = minf(
				glorious_anthem_shield + GameSettings.aura_glorious_anthem_recharge_rate * delta, full
			)

	if not is_equal_approx(before, total_shield()):
		emit_shield_changed()


## Circle of Protection landing on this player. Takes the STRONGER shield and the longer
## duration rather than adding, the same way apply_burn and apply_doom_curse do on the enemy
## side - two white players covering the same ally should not multiply, and neither should one
## player recasting into their own shield if the cooldown is ever shortened below the duration.
##
## Called on the ALLY rather than run by the caster, because the shield landed on them and in a
## party the caster is usually not the one whose bar has to change.
func grant_protection_shield(amount: float, duration: float) -> void:
	protection_shield = maxf(protection_shield, amount)
	_protection_shield_timer = maxf(_protection_shield_timer, duration)
	emit_shield_changed()


## The HUD draws exactly ONE player and it is this machine's. Every other avatar's health
## moves for reasons the local bar must not follow: a teammate taking a hit, or the host's
## copy of somebody else rebuilding its maximum when their auras arrive. Guarded in one
## place rather than at the ten call sites - `emit_shield_changed` below has always done
## this, and the comment there flagged that health did not.
func _emit_health_changed() -> void:
	if is_local:
		SignalBus.player_health_changed.emit(hp, max_hp)


func emit_shield_changed() -> void:
	if is_local:
		SignalBus.player_shield_changed.emit(total_shield())


## Returns the health ACTUALLY restored, which is what the scoreboard records: a 200-point
## heal on a player missing 20 is worth 20, and counting the request instead would let one
## overheal outrank a run of well-timed ones.
func heal(amount: float, show_damage_number: bool = true) -> float:
	if hp >= max_hp:
		return 0.0
	var before: float = hp
	hp = min(max_hp, hp + amount)
	var restored: float = hp - before
	_emit_health_changed()
	if show_damage_number:
		var spawn_pos = global_position + Vector3(0, 1.8, 0)
		NetFx.damage_number(spawn_pos, -restored, Color(0.2, 1.0, 0.4), "")
	return restored

func die() -> void:
	if is_downed:
		return
	# Rally the Fallen's ward: the cast's promise that its caster does not fall. Spent
	# either way - a ward that survived its own trigger is not a ward you keep.
	if _phoenix_ward_timer > 0.0:
		_phoenix_ward_timer = 0.0
		hp = max_hp * GameSettings.spell_white_rally_ward_hp_fraction
		_emit_health_changed()
		_invulnerable_timer = 1.0
		_spawn_ring(global_position, Color(1.0, 1.0, 0.85), 2.4)
		_play_sound(&"aura_grave_pact", global_position)
		return
	add_stat("downs")

	var total_players = get_tree().get_nodes_in_group("player").size()
	var timer: float = (
		GameSettings.player_downed_duration if total_players > 1
		else GameSettings.player_downed_solo_duration
	)
	_enter_downed(timer)
	# Enemies only think on the server, so `die` is reached there and nowhere else - which
	# left a client at zero health still walking around on their own screen while the host
	# had them face down. The DECISION stays here; the state it produces goes out to
	# everybody, this player's own machine included.
	if Net.is_active() and Net.is_server():
		_net_downed.rpc(timer)


## Falling over, on whichever machine is told to do it. No decision in here: die() above
## weighs the ward and the stats, this is only what being down looks like.
func _enter_downed(timer: float) -> void:
	if is_downed:
		return
	is_downed = true
	# A helper who goes down mid-channel is nobody's helper.
	_revive_channel_target = null
	_revive_channel_left = 0.0
	hp = 0.0
	_emit_health_changed()
	_cancel_action()
	_end_channel()
	is_blocking = false
	_stagger_timer = 0.0
	down_timer = timer
	animator.play_death()


@rpc("any_peer", "call_remote", "reliable")
func _net_downed(timer: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_enter_downed(timer)


func revive() -> void:
	if not is_downed:
		return
	_leave_downed()
	if Net.is_active() and Net.is_server():
		_net_revived.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _net_revived() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_leave_downed()


## Getting up where you fell. Shared by revive() and respawn_at_base(), which differ only
## in whether the player is also moved.
func _leave_downed() -> void:
	if not is_downed:
		return
	is_downed = false
	down_timer = 0.0
	_recentre_camera_after_downed()
	hp = max_hp
	_emit_health_changed()
	_invulnerable_timer = 2.0
	animator.revive()
	print("Player revived by teammate!")

## Folds any yaw the player accumulated while down back onto the body, so getting up
## faces the direction they were actually looking instead of snapping back to whatever
## way they happened to fall.
func _recentre_camera_after_downed() -> void:
	if is_zero_approx(camera_pivot.rotation.y):
		return
	rotate_y(camera_pivot.rotation.y)
	camera_pivot.rotation.y = 0.0


func respawn_at_base() -> void:
	if not is_downed:
		return
	# A DEATH, as opposed to the down recorded when they fell: reaching this means the timer
	# ran out and nobody revived them. revive() deliberately records nothing - a teammate
	# getting there in time is the down not becoming a death.
	add_stat("deaths")
	_return_to_seat()
	if Net.is_active() and Net.is_server():
		_net_respawned.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _net_respawned() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_return_to_seat()


## Up, and back where they started.
##
## The MOVE only happens on the machine that owns this player. Position is published by
## the owner's synchronizer, so a server that set it on its own puppet would have the
## client's next packet drag the body straight back to where it died. `spawn_point` is set
## by _seat_player on every peer, so both ends already know where that is.
func _return_to_seat() -> void:
	_leave_downed()
	if not is_local:
		return
	# Back to their own seat, facing their own lane. The old Vector3(0, 1, 0) was the world
	# origin, i.e. inside the crystal: a respawn dropped the player into the objective and left
	# them looking at whatever direction they happened to fall in.
	global_position = spawn_point.origin
	rotation.y = spawn_point.basis.get_euler().y

# --- 25 MTG SPELL IMPLEMENTATIONS ---







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
## Layer 3 is enemies (EnemyBase sets collision_layer 4). Dropping that bit from the
## player's own mask is what lets Fire Dash and Titanic Brawl travel through a pack instead
## of stopping dead on the first body they touch.
##
## Both are committed moves the player cannot steer once they start, and one that bounces
## off the front rank is one that never reaches what it was aimed at - the leap in
## particular exists to land IN the crowd. Nothing else changes: layer 1 (world) and layer 5
## (blockers) stay in the mask, so walls still stop both.
const ENEMY_COLLISION_BIT: int = 4

var _phasing: bool = false


func _set_phasing(active: bool) -> void:
	if _phasing == active:
		return
	_phasing = active
	if active:
		collision_mask &= ~ENEMY_COLLISION_BIT
	else:
		collision_mask |= ENEMY_COLLISION_BIT


## A settle-beat mark, dropped onto whatever ground is under `at` and tilted onto it.
##
## The player's own origin sits at their feet, so a decal centred on them is already close
## to right - but not on a slope, and not on the stairs and rises the lanes are built from.
func _place_ground_decal(slot: String, tint: Color, radius: float, at: Vector3) -> void:
	NetFx.decal(slot, tint, radius, at, _fx_peer())


## A persistent spell object - a zone, a wall, a summon, a telegraph - put into the world
## on EVERY peer rather than only on the one that ran the spell.
##
## Handed to MainController's effect spawner (see request_effect there) instead of being
## add_child()ed here. The old local version is what made a client's Wall of Souls a wall
## only the host could see: the collision was real and enemies stopped at it, but on the
## caster's screen the lane was empty and the enemies were walking into nothing.
##
## Returns the SERVER'S copy, so a spell that has to act on what it placed still can.
func _place_networked(info: Dictionary) -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("request_effect"):
		push_warning("No effect spawner in this scene - '%s' was not placed" % info.get("kind", ""))
		return null
	info["caster"] = _fx_peer()
	# Almost every caller of this runs on the server already, because that is where a
	# spell resolves - but not all of them. Fire Dash lays its trail from the CASTER's
	# own _physics_process while the dash is running, and on a client `request_effect`
	# refuses outright, so a client's dash left no fire anywhere: not on their screen,
	# not on the host, and nothing burning what it passed over.
	if Net.is_active() and not Net.is_server():
		_net_place_effect.rpc_id(1, info)
		return null
	return scene.request_effect(info) as Node3D


## A placement a client asked for, made on the server so that every peer gets it.
##
## The caster is stamped HERE from the sender rather than read out of the packet, so a
## peer can only ever place something credited to itself.
@rpc("any_peer", "call_remote", "reliable")
func _net_place_effect(info: Dictionary) -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("request_effect"):
		return
	info["caster"] = sender
	scene.request_effect(info)


## Drops `pos` straight down onto the world geometry (layer 1/5). A spawn handed the
## corpse's own mid-air position would leave the summon falling through the floor it
## was raised above; a ray down finds the ground that is actually there.
## `mask` defaults to Player + Environment, which is what most callers want. Displace
## passes Environment alone so it lands on the GROUND under a Wall of Frost rather than on
## top of it - see cast_blue_displace.
func _ground_snap(pos: Vector3, mask: int = 17) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 2.0, 0.0), pos - Vector3(0.0, 8.0, 0.0), mask)
	query.exclude = [get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	return result.position if result else pos


## Harvesting the nearest mana well, ticked. Returns true when this player is standing at
## a well at all - held or not - so the caller knows the HUD prompt is spoken for.
##
## The player used to be the only way mana was gathered, and it was cut when kills started
## banking it automatically: a forty-second round trip for a single mana is not a choice
## anybody makes twice. It is back for the opposite reason - trash kills pay nothing now
## (GameSettings.mana_per_basic), so a player already standing in the lane guarding a well
## should be able to work it instead of watching it.
##
## Deliberately NOT competitive with a myr. A myr works a well for the whole wave and a
## player cannot: this pays in the gaps, and stops paying the moment the lane needs
## defending, which is the trade that keeps the myrs the actual economy.
func _update_mana_harvest(delta: float, revive_available: bool) -> bool:
	var well: Node3D = _nearest_mana_well() if (is_local and not is_downed and not revive_available) else null
	if well == null:
		_harvest_left = 0.0
		_harvest_well = null
		return false

	# Standing still AND holding. Moving gives it up, so harvesting costs the player their
	# position as well as their time - otherwise it is passive income with extra steps.
	var moving: bool = Vector2(velocity.x, velocity.z).length_squared() > 0.25
	if not Input.is_action_pressed("interact") or moving:
		_harvest_left = 0.0
		_harvest_well = null
		SignalBus.interact_prompt_changed.emit("Hold %s to Harvest Mana" % _interact_key_label(), true)
		return true

	if well != _harvest_well:
		_harvest_well = well
		_harvest_left = GameSettings.player_mana_harvest_time

	_harvest_left -= delta
	if _harvest_left <= 0.0:
		# Keeps going while the key is held: one hold is a rhythm, not a single pickup.
		_harvest_left = GameSettings.player_mana_harvest_time
		var color: String = _well_color(well)
		if Net.is_active():
			_request_harvest.rpc_id(1, color)
		else:
			_request_harvest(color)

	var elapsed: float = GameSettings.player_mana_harvest_time - _harvest_left
	var pct: int = int(round(elapsed / maxf(GameSettings.player_mana_harvest_time, 0.01) * 100.0))
	SignalBus.interact_prompt_changed.emit("Harvesting... %d%%" % pct, true)
	return true


## The closest well within reach, or null. Wells sit in the "mana_sources" group and carry
## their lane in metadata, which is how the myrs already find them.
func _nearest_mana_well() -> Node3D:
	var best: Node3D = null
	var best_distance: float = GameSettings.player_mana_harvest_distance
	for source: Node in get_tree().get_nodes_in_group("mana_sources"):
		if not (source is Node3D):
			continue
		var distance: float = global_position.distance_to((source as Node3D).global_position)
		if distance <= best_distance:
			best_distance = distance
			best = source as Node3D
	return best


func _well_color(well: Node3D) -> String:
	return String(well.get_meta("lane_name", "White"))


## Banked on the server, like every other reward, and shown from there too - the payout
## FX has to reach every peer, not only the one that did the holding. The channel itself
## stays local, because only the peer holding the key can see that it is still held.
@rpc("any_peer", "call_local", "reliable")
func _request_harvest(color: String) -> void:
	if not Net.is_server():
		return
	var banked: int = RunState.add_mana(color, GameSettings.player_mana_harvest_amount)
	if banked <= 0:
		return
	var tint: Color = GameSettings.lane_tint(color)
	NetFx.damage_number(global_position + Vector3(0.0, 2.2, 0.0), float(banked), tint, "+%d mana" % banked)
	NetFx.ring(global_position, tint, 1.4)


## The revive channel, ticked. Everything the HELPER does that is not kneeling breaks
## it - moving, attacking, casting, kicking, jumping. Taking a hit does NOT: a rescue
## under fire is supposed to be possible, just slow.
func _update_revive_channel(delta: float, in_range_of_someone: bool) -> void:
	if _revive_channel_target == null:
		if in_range_of_someone and _notification_timer <= 0.0:
			SignalBus.interact_prompt_changed.emit("Press %s to Revive Teammate" % _interact_key_label(), true)
		return
	var target: Player = _revive_channel_target
	var interrupted: bool = (
		not is_instance_valid(target)
		or not target.is_downed
		or global_position.distance_to(target.global_position) > GameSettings.player_revive_range
		or _wants_to_move()
		or Input.is_action_just_pressed("attack")
		or Input.is_action_just_pressed("cast_spell")
		or Input.is_action_just_pressed("kick")
		or Input.is_action_just_pressed("jump")
	)
	if interrupted:
		_revive_channel_target = null
		_revive_channel_left = 0.0
		SignalBus.interact_prompt_changed.emit("", false)
		return
	_revive_channel_left -= delta
	var pct: int = int(100.0 * (1.0 - _revive_channel_left / GameSettings.player_revive_channel_time))
	SignalBus.interact_prompt_changed.emit("Reviving... %d%%" % pct, true)
	if _revive_channel_left <= 0.0:
		_revive_channel_target = null
		target.revive()
		_notification_text = "Revived Teammate!"
		_notification_timer = 1.5
		SignalBus.interact_prompt_changed.emit(_notification_text, true)


# --- WHITE: protection and restoration ----------------------------------------











# --- BLUE: control -------------------------------------------------------------











# --- BLACK: parasitic drain ----------------------------------------------------











# --- RED: aggression -----------------------------------------------------------









## Grows or shrinks this player to match `_giant_scale_mult`, wherever they are drawn.
##
## Called every frame on every avatar on every peer, and does nothing at all until the
## number moves - the same shape as _sync_channel_fx, and for the same reason: Giant
## Growth is not a moment but a condition, so what crosses the wire is the size and each
## machine tweens its own body to it.
func _sync_giant_scale() -> void:
	if is_equal_approx(_applied_giant_scale, _giant_scale_mult):
		return
	var growing: bool = _giant_scale_mult > _applied_giant_scale
	_applied_giant_scale = _giant_scale_mult
	# Grown into rather than snapped to: an instant scale change reads as a glitch, and
	# the character's feet visibly leave the floor for a frame.
	var seconds: float = 0.25 if growing else 0.3
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	var grow: PropertyTweener = tween.tween_property(
		self, "scale", base_scale * _giant_scale_mult, seconds
	)
	if growing:
		grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		grow.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	# The camera rig is a CHILD of this node (see setup_camera), so scaling the body
	# scaled the spring arm with it: the camera backed off by exactly the factor the
	# character grew by, and a giant filled precisely as much of its own screen as it had
	# a moment earlier. That is why Giant Growth looked like it did nothing to the person
	# who cast it - it was working, and they were watching it through a camera that had
	# grown too. Cancelled here so the pivot's WORLD scale stays 1: the camera keeps its
	# authored distance while the body it is pointed at gets bigger.
	#
	# The pivot's local POSITION still scales with the body, which is wanted - a giant's
	# head is higher up, and the camera belongs there rather than at its knees.
	if camera_pivot != null:
		tween.tween_property(
			camera_pivot, "scale", Vector3.ONE / _giant_scale_mult, seconds
		)


## Builds or clears the channel's flames and its loop to match `_channel_id`. Called every
## frame on EVERY avatar on every peer, which is what makes a teammate's Fire Cone visible
## without any of it being sent: `_channel_id` crosses the wire on the vitals synchronizer
## and the fire is rebuilt locally from it.
func _sync_channel_fx() -> void:
	var wanted: bool = _channel_id != ""
	if wanted and _channel_fx == null:
		_build_channel_fx()
	elif not wanted and _channel_fx != null:
		_drop_channel_fx()


func _build_channel_fx() -> void:
	# Held rather than fired: the loop runs for as long as the channel does.
	_channel_voice = SoundBank.attach_loop(&"spell_fire_cone", self, false)
	# Off `_channel_rank` rather than `_rank_area()`, because this now runs on peers where
	# no cast is in progress and `_casting_rank` is whatever was cast here last.
	var length: float = GameSettings.spell_red_fire_cone_length * GameSettings.rank_area_mult(_channel_rank)
	_channel_fx = EmberFx.build_flame(length * 0.25, 60)
	_channel_fx.position = Vector3(0.0, 1.2, -1.2)
	var process: ParticleProcessMaterial = _channel_fx.process_material
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 22.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = GameSettings.spell_red_fire_cone_length * 0.5
	process.initial_velocity_max = GameSettings.spell_red_fire_cone_length
	add_child(_channel_fx)


func _drop_channel_fx() -> void:
	if is_instance_valid(_channel_voice):
		_channel_voice.stop()
		_channel_voice.queue_free()
	_channel_voice = null
	if is_instance_valid(_channel_fx):
		# Emission off rather than freed, so the flames already in the air burn out
		# instead of blinking away mid-frame.
		_channel_fx.emitting = false
		var doomed: Node3D = _channel_fx
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(doomed):
				doomed.queue_free())
	_channel_fx = null




## Lightning Bolt's niche, and the answer to red having four ways to burn a crowd and none
## to kill one big thing. A boss or an elite takes the full multiplier; anything else takes
## the bolt at face value, so this never becomes a better way to clear a wave.
##
## Elites count as well as bosses because they are the targets that actually survive an area
## spell - a wave boss is obvious, but an elite walking out of a Rain of Ember is exactly the
## moment the player wants one big answer instead of a fifth way to cover ground in fire.
func _bolt_target_multiplier(enemy: Node3D, elite_mult: float) -> float:
	var is_boss: bool = enemy.has_method("is_boss") and enemy.is_boss()
	var is_elite: bool = "elite_modifier" in enemy and String(enemy.elite_modifier) != ""
	return elite_mult if is_boss or is_elite else 1.0


# --- GREEN: primal vitality ----------------------------------------------------









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
	if _phoenix_ward_timer > 0.0:
		_phoenix_ward_timer -= delta
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


## Giant Growth wearing off. The health has to come back through _sync_auras
## rather than being subtracted here, or repeated casts would drift the maximum.
func _end_giant_growth() -> void:
	is_giant = false
	giant_timer = 0.0
	_giant_bonus_hp = 0.0
	_giant_scale_mult = 1.0
	_sync_auras()


## Fire Cone, running. It pays out damage every frame it is up and ends on the button
## coming up or on its own limit - whichever is first. Movement stays in _physics_process.
func _update_channel(delta: float) -> void:
	_channel_timer -= delta

	var still_held: bool = true
	if _channel_held:
		# Only the caster's own machine can read this. When the caster is somebody else's
		# avatar the server waits to be told the button came up (see _net_end_channel)
		# rather than answering with the host's keyboard, which is not the one being held.
		still_held = Input.is_action_pressed("cast_spell") if is_local else true
	if _channel_timer <= 0.0 or not still_held or is_downed or _stagger_timer > 0.0:
		_end_channel()
		return

	var damage: float = GameSettings.spell_red_fire_cone_dps * get_spell_damage_multiplier() \
		* GameSettings.rank_damage_mult(_channel_rank) * delta
	var length: float = GameSettings.spell_red_fire_cone_length * GameSettings.rank_area_mult(_channel_rank)
	for enemy: Node3D in _enemies_in_cone(length, GameSettings.spell_red_fire_cone_dot):
		_deal_damage(enemy, damage, false)
		# The control half of the cone's job, now that it is no longer red's biggest damage
		# number. Refreshed per frame with a duration barely longer than a frame, so what
		# holds an enemy back is the flame STAYING on it - sweep away and it is walking again
		# within half a second. apply_slow refuses on a boss, as every slow does.
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(GameSettings.spell_red_fire_cone_slow_duration, GameSettings.spell_red_fire_cone_slow_mult)


## The visible half of what another player is doing, on this machine.
##
## Neither of these is sent as a visual. The channel is rebuilt from `_channel_id` and the
## charge ball is driven by the replicated `charge_timer`, which is also what makes them
## agree with the owner's own screen frame for frame instead of drifting.
func _update_remote_effects() -> void:
	_sync_channel_fx()
	if _charge_orb != null:
		_update_charge_orb()


## A client's own channel, which the SERVER is running. Nothing here ticks it: this
## watches for the cast button coming up and tells the host, which is the one thing about
## a channel the host cannot find out for itself.
func _watch_remote_channel() -> void:
	if _channel_release_sent or not _channel_held:
		return
	if Input.is_action_pressed("cast_spell"):
		return
	_channel_release_sent = true
	_net_end_channel.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _net_end_channel() -> void:
	if not Net.is_server():
		return
	# A player may end their OWN channel and nobody else's.
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_end_channel()


## Ends the channel and takes its flames with it. Called from _update_channel when it
## runs out, and from _cancel_action when something interrupts the player - a channel
## that survived a stagger would keep burning while the character was knocked over.
func _end_channel() -> void:
	if _channel_id == "":
		return
	var spent: float = maxf(GameSettings.spell_red_fire_cone_max_duration - _channel_timer, 0.0)
	if spent > 0.05:
		spell_cooldown_timers[_channel_id] = spent / _spell_cooldown_recovery_rate()
	_channel_id = ""
	_channel_timer = 0.0
	_channel_held = false
	_channel_release_sent = false
	_channel_slot = -1
	# Here as well as in _sync_channel_fx, so a channel that ends on this machine puts its
	# flames out on the same frame rather than on the next one.
	_sync_channel_fx()


# --- Shared spell visuals ------------------------------------------------------
#
# The five dialects from docs/SPELL_VFX_PLAN.md, as constants rather than as a colour
# typed at each call site. Twenty-odd spells used to pick their own literal, which is how
# white ended up with four different whites - and a colour the player cannot recognise
# across its own spells is not carrying any information.
const FX_WHITE: Color = Color(1.0, 0.94, 0.72)
const FX_BLUE: Color = Color(0.55, 0.82, 1.0)
const FX_BLACK: Color = Color(0.62, 0.25, 0.92)
const FX_RED: Color = Color(1.0, 0.55, 0.18)
const FX_GREEN: Color = Color(0.55, 0.9, 0.45)

#
# Every skill gets SOMETHING the player can see, because a spell with no feedback is
# indistinguishable from a spell that did not fire - which is exactly how the skill tree
# bug that hid all of this went unnoticed for a release.
#
# The SHAPES now live in scripts/spell_fx.gd, the way every fire effect lives in
# ember_fx.gd. These three stay as the names the twenty-odd call sites already use, so a
# spell asks for "a ring at this radius" and the effect layer decides what a ring is.

## The area a skill just affected, drawn at the size it actually used, so the player can
## learn a radius by watching rather than by reading.
func _spawn_ring(center: Vector3, tint: Color, radius: float) -> void:
	NetFx.ring(center, tint, radius)


## A straight shaft of light. Doom Blade's line and Lightning Bolt's strike are the same
## shape seen from two angles.
func _spawn_beam(origin: Vector3, direction: Vector3, length: float, tint: Color) -> void:
	NetFx.beam(origin, direction, length, tint)


## A pulse of light on the caster. What a self-buff looks like, since it has nowhere else
## to happen. Parented to the player rather than to the world, so a buff cast on the move
## travels with them.
func _spawn_cast_flash(tint: Color, radius: float) -> void:
	NetFx.glow(_fx_peer(), tint, radius)


## A front leaving a point - the release beat of anything that goes off around the caster.
func _spawn_impact(center: Vector3, tint: Color, radius: float) -> void:
	NetFx.impact(center, tint, radius)


## A blast down ONE direction. Unsummon pushes in a line, and a ring told the player it
## had happened in every direction including behind them, where nothing was shoved at all.
func _spawn_gust(origin: Vector3, facing: Vector3, length: float, tint: Color) -> void:
	NetFx.gust(origin, facing, length, tint)


## Positional audio, heard by everyone in earshot rather than only on the machine that
## ran the spell. Same shape as the visuals above, and for exactly the same reason.
func _play_sound(event: StringName, at: Vector3) -> void:
	NetFx.sound(event, at)


## A knock felt at full strength by whoever caused it and by distance for everyone else.
## `at` defaults to the caster, which is where all but a couple of these happen.
func _shake(strength: float, duration: float, at: Vector3 = Vector3.INF) -> void:
	NetFx.shake(strength, duration, global_position if at == Vector3.INF else at, _fx_peer())


## Who to credit an effect to, so the other peers can find this avatar and so a shake
## reaches its own caster wherever they have got to. Zero in single-player, where there
## are no peer ids and nothing is looked up.
func _fx_peer() -> int:
	return get_multiplayer_authority() if Net.is_active() else 1


func _on_team_level_changed(level: int, levels_gained: int) -> void:
	# Blade Dance used to be the tree's centre node, bought with mana. It is a reward for
	# surviving now: the hub shows the team level instead, and the third combo stage arrives
	# on its own when that level reaches BLADE_DANCE_LEVEL.
	if level >= BLADE_DANCE_LEVEL and not melee_combo_extended:
		melee_combo_extended = true
		SignalBus.melee_combo_unlocked.emit()
		_notify("Blade Dance unlocked")
	if levels_gained <= 0:
		return
	hp = max_hp
	_emit_health_changed()
	_spawn_level_up_glow()
	SoundBank.play_at(&"level_up", global_position)


func _spawn_level_up_glow() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.91, 0.56)
	light.light_energy = 0.0
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 4.0, 0.0)
	add_child(light)
	var tween: Tween = light.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "light_energy", 8.0, 0.16)
	tween.tween_property(light, "omni_range", 9.0, 0.35)
	tween.chain()
	tween.tween_property(light, "light_energy", 0.0, 0.75)
	tween.tween_property(light, "omni_range", 3.0, 0.75)
	tween.chain()
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
				_play_sound(_attack_impact_sound, global_position)
				_shake(
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
			_action_is_heavy = false
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
		# Once the hold is clearly heavy, commit the full attack immediately. A short
		# tap is still resolved on release as a normal fast attack.
		if not _can_start_attack():
			return
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
	_attack_knockback_strength = GameSettings.player_heavy_knockback
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
	_play_sound(_attack_swing_sound, global_position)
	# Roots, like every heavy swing: this used to read as `upper_body = false`, which
	# meant the same thing back when rooting was derived from it.
	_commit_action(remaining / maxf(pace, 0.01), true, true)
	animator.release_windup(remaining, _action_duration)
	if Net.is_active() and is_local:
		_net_release_windup.rpc(remaining, _action_duration)

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
	_attack_knockback_strength = GameSettings.spell_melee_knockback
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
	_attack_knockback_strength = GameSettings.spell_melee_kick_knockback
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
	if _action_is_heavy:
		# A heavy spin is a full-body commitment. It must finish before the player can
		# trigger another heavy or any follow-up swing from the same committed move.
		return false
	if not _action_is_melee:
		# Mid-cast: the wind-up is a commitment, not a combo step to chain out of.
		return false
	var progress: float = 1.0 - _action_timer / maxf(_action_duration, 0.001)
	return progress >= 1.0 - GameSettings.player_combo_window


## Attack cadence, shortened by Fervor exactly as the old flat melee cooldown was.
func _swing_duration() -> float:
	return GameSettings.player_swing_duration / _attack_speed_mult()


## The shared primitive behind every committed move, melee or cast: play `clip` over
## `duration`, and hold the player still unless it is an upper-body one.
##
## `upper_body` decides whether the legs keep their walk cycle underneath (see
## PlayerAnimator's bone filter) and `roots` whether the player can move at all.
## They are nearly always opposites - a full-body clip on a character sliding along
## the floor is the problem the layering exists to solve - so they are passed
## separately rather than derived, precisely so the one move where they come apart
## can say so. That move is Titanic Brawl: full body, and moving, because the movement
## it makes is the jump the clip is playing.
##
## `window` narrows playback to one stage of a chained clip; see _advance_light_chain.
func _begin_action(clip: String, duration: float, upper_body: bool, roots: bool, is_melee: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_combat_timer = GameSettings.player_combat_linger
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


## The raise a charge holds. Sent as its own message rather than folded into
## _net_play_action because a wind-up is played at a speed fitted to the charge window and
## then CONTINUED by _net_release_windup, not restarted.
@rpc("authority", "call_remote", "reliable")
func _net_play_windup(clip: String, duration: float, upper_body: bool) -> void:
	animator.play_windup(clip, duration, upper_body)


## The wind-up becoming the swing, which changes nothing but the speed of a shot already
## in flight - so the far end has to have been given that shot first.
@rpc("authority", "call_remote", "reliable")
func _net_release_windup(remaining: float, duration: float) -> void:
	animator.release_windup(remaining, duration)


## A charge abandoned. Without it the other screens hold the raise forever, because
## nothing else they are told about ever ends it.
@rpc("authority", "call_remote", "reliable")
func _net_stop_action() -> void:
	animator.stop_action()


## How much the giant hits for, straight off the size: twice as tall is twice as hard.
## The cadence pays for it below, so the buff reads as mighty rather than as a cheat.
func _giant_damage_mult() -> float:
	return _giant_scale_mult if is_giant else 1.0


## Attack cadence, shortened by Fervor exactly as the old flat melee cooldown was - and
## stretched by Giant Growth's size. The slow is capped: a rank-5 giant swings at most
## a little over half speed, so the growth never tips into feeling broken.
func _attack_speed_mult() -> float:
	var mult: float = GameSettings.aura_bonus_mult(GameSettings.aura_fervor_speed_boost, get_aura_rank("aura_fervor")) if has_aura("aura_fervor") else 1.0
	if is_giant:
		mult /= minf(_giant_scale_mult, GameSettings.spell_green_giant_attack_slow_cap)
	return mult


## The gameplay half of starting a committed move: how long it owns the player, and
## what that stops them doing. Split out from _begin_action because a charged heavy
## continues an animation that is already running instead of starting a new one, and
## so needs this half without the other.
func _commit_action(duration: float, roots: bool, is_melee: bool) -> void:
	# Ends the charge as a flag only. Whatever animation follows either replaces the
	# wind-up's shot or continues it; either way there is nothing to abort.
	_heavy_charge_timer = -1.0
	# A held spell is dropped outright instead, because the action layer has room for
	# exactly one thing: a swing started mid-charge would take the shot the charge is
	# riding, and the release would then speed up the SWING. A cast released out of its
	# own wind-up has already handed that shot over (see _begin_cast), so this is a
	# no-op for the one action that is allowed to continue a charge.
	_cancel_spell_charge()
	_action_duration = maxf(duration, 0.01)
	_action_timer = _action_duration
	_action_elapsed = 0.0
	_action_roots_player = roots
	_action_is_melee = is_melee
	_action_is_heavy = false


## A swing: commits the player and schedules the impact frames measured inside the
## stretch of clip it actually plays.
func _begin_melee_action(clip: String, duration: float, damage_mult: float, upper_body: bool, window: Vector2 = PlayerAnimator.FULL_WINDOW) -> void:
	_attack_damage_mult = damage_mult
	_pending_cast_id = ""
	_action_is_heavy = clip == HEAVY_CLIP
	# Heard now, whatever it goes on to hit. The impact is a separate sound scheduled
	# with the damage below, so a swing through empty air still makes a noise.
	_play_sound(_attack_swing_sound, global_position)
	# Melee keeps the two tied together: a swing that takes the whole body is a
	# committed move, and one masked to the upper body is walked through.
	_begin_action(clip, duration, upper_body, not upper_body, true, window)
	_pending_hits = animator.hit_times(clip, _action_duration, window)
	if clip == HEAVY_CLIP and not _pending_hits.is_empty():
		_pending_hits = [_pending_hits[-1]]
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
	# Double Strike (Dimir passive): everything the player causes can crit, melee and
	# spells alike, so the roll lives in the one funnel all of it passes through.
	var crit_chance: float = get_passive_bonus("double_strike")
	if crit_chance > 0.0 and randf() < crit_chance:
		amount *= GameSettings.passive_crit_damage_mult
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
	var knockback: float = GameSettings.spell_melee_kick_knockback if is_kick else _attack_knockback_strength
	var dmg: float = GameSettings.spell_melee_kick_damage if is_kick else GameSettings.spell_melee_damage * damage_mult
	dmg *= get_spell_damage_multiplier() * _giant_damage_mult()
	# Trample (Gruul passive): melee scales off the player's own health pool, which is
	# what makes the passive pair with Giant Growth inside the same colours.
	dmg += max_hp * get_passive_bonus("trample_strike")

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


func _heavy_lunge_distance(progress: float) -> float:
	if progress <= HEAVY_LUNGE_EXTRA_START:
		return HEAVY_LUNGE_DISTANCE * progress / HEAVY_LUNGE_EXTRA_START
	if progress <= HEAVY_LUNGE_EXTRA_END:
		var extra_progress: float = (progress - HEAVY_LUNGE_EXTRA_START) / (HEAVY_LUNGE_EXTRA_END - HEAVY_LUNGE_EXTRA_START)
		return HEAVY_LUNGE_DISTANCE + HEAVY_LUNGE_EXTRA_DISTANCE * extra_progress
	return HEAVY_LUNGE_DISTANCE + HEAVY_LUNGE_EXTRA_DISTANCE


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
	if wants_to_block:
		_combat_timer = GameSettings.player_combat_linger
	if wants_to_block and not is_blocking:
		# Raising the guard drops any half-built combo, and anything being wound up -
		# a heavy or a held spell alike. Both are two-handed commitments; neither can
		# survive the same hands coming up to guard.
		_combo_stage = 0
		_attack_hold_timer = -1.0
		_cancel_heavy_charge()
		_cancel_spell_charge()
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


func _block_sound_for(source: Node3D) -> StringName:
	if is_instance_valid(source) and "enemy_data" in source:
		var data: EnemyData = source.enemy_data as EnemyData
		if data != null:
			if data.enemy_class == "Ranged":
				return &"block_impact_arrow"
			if data.enemy_class == "Mage":
				return &"block_impact_magic"
	return &"block_impact_blunt"

func _physics_process(delta: float) -> void:
	if not is_local:
		# A puppet's transform is authored by its owner and arrives over the wire. All
		# this end has to do is keep the animator fed from the replicated velocity,
		# which is what makes it walk, run and strafe correctly with nothing else sent.
		# `is_grounded`, not `is_on_floor()` - see the property. Blocking is replicated for
		# the same reason: it changes which gait the animator drives, and without it a
		# teammate holding guard walked around with their sword down.
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), false, is_grounded, is_blocking, false)
		# Everything about this player that is a CONDITION rather than a pose - the
		# fireball growing between their hands, the flames of a channel - rebuilt here
		# from replicated numbers rather than sent as visuals.
		_update_remote_effects()
		_sync_giant_scale()
		# ...and the half of their state THIS machine authors. On the host that is the
		# gameplay half: enemies only think here, so a remote player's shields and their
		# channel are ticked on this side and replicated back on the vitals synchronizer.
		# Without it a client's Anthem shield never recharged and their Fire Cone, which
		# is started by the server, never ticked down at all.
		if Net.is_server():
			# Every duration a spell puts on this player: Giant Growth, Ironbark, both
			# wards, the Grave Pact stack. All of them are set by code that resolves HERE,
			# on the server, and all of them were ticked only in the branch below - which a
			# remote player's avatar never reaches. So a client casting Giant Growth stayed
			# giant for the rest of the run, and their Ironbark never wore off.
			_update_skill_timers(delta)
			_update_shields(delta)
			# Their down timer, which only this machine advances: a client's avatar is a
			# puppet here and its owner is not allowed to decide when it gets back up.
			if is_downed:
				down_timer -= delta
				if down_timer <= 0.0:
					respawn_at_base()
			if _channel_id != "":
				_update_channel(delta)
		return
	_sync_auras()
	_publish_build()
	# Runs before the downed early-out so a shake still settles while downed.
	_update_camera_shake(delta)
	if is_downed:
		# The clock runs everywhere so the countdown on screen reads correctly, but only
		# the server may act on it - the same split UpkeepPanel uses. Two peers deciding
		# a player is back up would respawn them twice.
		down_timer -= delta
		if down_timer <= 0.0 and Net.is_server():
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

	# A client's channel is STARTED by the server, so this has to run before the branch
	# below rather than only where the spell is cast - on that machine the spell was never
	# cast, it only arrived.
	_sync_channel_fx()
	_sync_giant_scale()
	if _channel_id != "":
		if Net.is_server():
			_update_channel(delta)
		else:
			_watch_remote_channel()
	else:
		# Melee fires on release: a tap advances the light chain by one stage, a hold
		# commits to the heavy spin. See _update_actions().
		_update_block()
		_update_actions(delta)

	# Published for the other peers, who have no way to work it out for themselves.
	is_grounded = is_on_floor()

	if not is_on_floor():
		# Flying (Azorius passive): holding jump on the way down trades the fall for a
		# glide. Only the fall - a rising jump keeps full weight, or it floats forever.
		var fall_gravity: float = gravity
		if velocity.y < 0.0 and get_passive_rank("flight") > 0 and Input.is_action_pressed("jump"):
			fall_gravity *= GameSettings.passive_flight_glide_gravity_mult
		velocity.y -= fall_gravity * delta

	if is_local and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity * (1.0 + get_passive_bonus("flight"))
		animator.start_jump(velocity.y)

	# Titanic Brawl is in the air: gravity and the launch impulse own the player, so
	# the ordinary movement code below is skipped entirely rather than being allowed
	# to overwrite velocity.x/z with whatever the stick is doing. The slam itself is
	# scheduled off the clip's landing frame, not off this timer.
	# Both committed dashes pass THROUGH bodies. Re-evaluated every frame rather than
	# toggled at each end, so a leap cut short by a stagger, a death or a cancelled cast
	# cannot leave the player permanently able to walk through enemies.
	_set_phasing(_leap_timer > 0.0 or _dash_timer > 0.0)

	if _leap_timer > 0.0:
		_leap_timer -= delta
		move_and_slide()
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), true, is_on_floor(), false, true)
		return

	# Fire Dash, the same shape as the leap: the impulse owns the player for its length,
	# and the ordinary movement code below would otherwise overwrite it on the very next
	# line. Unlike the leap it stays on the ground, and it leaves something behind.
	if _dash_timer > 0.0:
		_dash_timer -= delta
		_dash_trail_timer -= delta
		if _dash_trail_timer <= 0.0:
			_dash_trail_timer = DASH_TRAIL_SPACING
			SpellEffects._drop_trail_segment(self)
		move_and_slide()
		animator.update_locomotion(delta, Vector3(velocity.x, 0.0, velocity.z), true, is_on_floor(), false, true)
		return

	# Charging Logic
	if is_charging:
		charge_timer += delta
		SignalBus.spell_charge_changed.emit(charge_timer, charge_max_time, true)
		_update_charge_orb()
		if charge_timer >= charge_max_time:
			release_charged_spell()


	# Base & Aura Passive HP Regeneration
	var regen_amount = GameSettings.player_base_hp_regen * (1.0 + get_affinity_bonus("white")) * delta
	if has_aura("aura_sylvan_library"):
		regen_amount += GameSettings.aura_sylvan_library_regen * get_aura_rank_mult("aura_sylvan_library") * delta
	heal(regen_amount, false)

	if has_aura("aura_phyrexian_arena"):
		var drain = max_hp * GameSettings.aura_phyrexian_arena_hp_drain_pct * delta
		hp = max(1.0, hp - drain)
		_emit_health_changed()

	# Trample, green's Manifestation. Gated on actually MOVING, which is the whole
	# design: it rewards the colour that fights by being physically present, and it does
	# nothing at all for a player standing still at the crystal.
	if has_aura("aura_trample") and Vector3(velocity.x, 0.0, velocity.z).length() > 1.0:
		var trample: float = GameSettings.aura_trample_dps * get_aura_rank_mult("aura_trample") * get_spell_damage_multiplier() * delta
		for enemy: Node3D in _enemies_in_radius(global_position, GameSettings.aura_trample_radius * get_aura_rank_mult("aura_trample", "area")):
			_deal_damage(enemy, trample, true)

	# Teammate revive: a channel by the HELPER, not an instant key press - and the downed
	# player's own timer keeps running meanwhile, so help that arrives too late arrives
	# too late. See _update_revive_channel for what breaks the channel.
	var revived_teammate = false
	var teammates = get_tree().get_nodes_in_group("player")
	for teammate in teammates:
		if teammate != self and teammate.is_downed:
			var dist = global_position.distance_to(teammate.global_position)
			if dist < GameSettings.player_revive_range:
				revived_teammate = true
				if _revive_channel_target == null and Input.is_action_just_pressed("interact"):
					_revive_channel_target = teammate
					_revive_channel_left = GameSettings.player_revive_channel_time
				break
	_update_revive_channel(delta, revived_teammate)

	# Working a well by hand. A channel like the revive above rather than a key press, and
	# checked right after it so the two cannot both be writing the same line of HUD text -
	# a revive always wins, because somebody is on the floor.
	var harvesting: bool = _update_mana_harvest(delta, revived_teammate)

	# Base proximity. What is left here is only "am I at the base", which is what opens the
	# base UI and what the HUD prompt reads.
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("spawn_myr"):
		var near_base = global_position.distance_to(main_node.crystal_anchor.global_position) < GameSettings.player_base_proximity
		if near_base != is_at_base:
			is_at_base = near_base
			SignalBus.at_base_changed.emit(is_at_base)

		if is_at_base and is_local and Input.is_action_just_pressed("interact"):
			if main_node.base_ui_instance and not main_node.base_ui_instance.visible:
				main_node.base_ui_instance.open(main_node)

		if is_local and not revived_teammate and not harvesting:
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
	if has_aura("aura_fervor"):
		current_speed *= GameSettings.aura_bonus_mult(GameSettings.aura_fervor_speed_boost, get_aura_rank("aura_fervor"))
	elif has_aura("aura_phyrexian_arena"):
		current_speed *= GameSettings.aura_bonus_mult(GameSettings.aura_phyrexian_arena_speed_mult, get_aura_rank("aura_phyrexian_arena"))
	# Haste (Rakdos passive): a plain multiplier on top of whatever else is moving you.
	var haste_bonus: float = get_passive_bonus("haste")
	if haste_bonus > 0.0:
		current_speed *= 1.0 + haste_bonus
		
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
	elif _combat_timer > 0.0:
		# Still in a fight, just not mid-swing: walk pace, matching the armed walk cycle
		# the animator holds for the same window.
		current_speed *= GameSettings.player_combat_speed_mult

	if rooted:
		# Zeroed outright rather than by falling through to move_toward() below:
		# with current_speed at 0 that call is a no-op, and the player would coast
		# on at whatever velocity the swing started with.
		var lunge_speed: float = 0.0
		if _action_is_melee and _attack_swing_sound == &"blade_heavy_swing":
			var previous_progress: float = clampf((_action_elapsed - delta) / maxf(_action_duration, 0.01), 0.0, 1.0)
			var current_progress: float = clampf(_action_elapsed / maxf(_action_duration, 0.01), 0.0, 1.0)
			lunge_speed = (_heavy_lunge_distance(current_progress) - _heavy_lunge_distance(previous_progress)) / maxf(delta, 0.001)
		var lunge_direction: Vector3 = -transform.basis.z
		lunge_direction.y = 0.0
		velocity.x = lunge_direction.normalized().x * lunge_speed
		velocity.z = lunge_direction.normalized().z * lunge_speed
	elif direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	_combat_timer = maxf(_combat_timer - delta, 0.0)
	animator.update_locomotion(
		delta, Vector3(velocity.x, 0.0, velocity.z), sprinting, is_on_floor(), is_blocking,
		_combat_timer > 0.0
	)
	
	# NOTE: there used to be a second giant-growth timer here, left over from when
	# `is_giant` was a stub with nothing behind it. It ticked `giant_timer` a second time
	# every frame (so the buff lasted half its stated duration) and, worse, ended with an
	# unconditional `_giant_scale_mult = 1.0` - which ran while the buff was ACTIVE and
	# pinned the multiplier back to 1 every single frame. _sync_giant_scale duly tweened
	# the player straight back down, and Giant Growth never visibly grew anybody. The real
	# timer is in _update_skill_timers, which ends the buff through _end_giant_growth.

	if slow_timer > 0:
		slow_timer -= delta

	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta

	# Server-side even for one's OWN player. The host is where the hits land and where the
	# shields are spent, and a client recharging its own on top of that would draw a bar
	# the host disagreed with until the next packet corrected it. Always true in
	# single-player, where this is the code it has always been.
	if Net.is_server():
		_update_shields(delta)

	# Cooldowns store real remaining seconds so the hotbar display counts down at real time.
	for key in spell_cooldown_timers.keys():
		spell_cooldown_timers[key] -= delta
		if spell_cooldown_timers[key] <= 0.0:
			spell_cooldown_timers.erase(key)
