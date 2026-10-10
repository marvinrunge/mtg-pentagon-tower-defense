extends CharacterBody3D
class_name EnemyBase

var target_crystal: Node3D
var current_target: Node3D
var last_target_position: Vector3 = Vector3.INF

var _health_bar_scene: PackedScene = preload("res://scenes/ui/enemy_health_bar.tscn")
var _miniboss_glow_shader: Shader = preload("res://assets/shaders/miniboss_glow.gdshader")

const MELEE_VISUAL_SCENES := {
	"White": preload("res://scenes/melee/human_melee.tscn"),
	"Blue": preload("res://scenes/melee/merfolk_melee.tscn"),
	"Black": preload("res://scenes/melee/zombie_melee.tscn"),
	"Red": preload("res://scenes/melee/goblin_melee.tscn"),
	"Green": preload("res://scenes/melee/elf_melee.tscn"),
}
# Own dedicated mesh/animation set per colour, distinct from melee (see
# tools/character_builder.gd) - no longer "melee minus weapon".
const RANGED_VISUAL_SCENES := {
	"White": preload("res://scenes/ranged/human_ranged.tscn"),
	"Blue": preload("res://scenes/ranged/merfolk_ranged.tscn"),
	"Black": preload("res://scenes/ranged/zombie_ranged.tscn"),
	"Red": preload("res://scenes/ranged/goblin_ranged.tscn"),
	"Green": preload("res://scenes/ranged/elf_ranged.tscn"),
}
const MAGE_VISUAL_SCENES := {
	"White": preload("res://scenes/mage/human_mage.tscn"),
	"Blue": preload("res://scenes/mage/merfolk_mage.tscn"),
	"Black": preload("res://scenes/mage/zombie_mage.tscn"),
	"Red": preload("res://scenes/mage/goblin_mage.tscn"),
	"Green": preload("res://scenes/mage/elf_mage.tscn"),
}

# Shared across every EnemyBase instance so the corpse cap applies project-wide.
static var _corpses: Array[EnemyBase] = []

# The melee/ranged libraries call the damage reaction "knockback"; the Mixamo boss
# libraries call it "hit". Resolved once per enemy so either naming works.
const REACTION_CLIP_CANDIDATES := ["knockback", "hit"]

# Some source death clips run very long (the zombie boss's is 11.6s) - cap how
# long a body is still visibly settling.
const DEATH_MAX_SECONDS := 4.0
## How often a burn pays out. Half a second is frequent enough to read as burning and
## rare enough that fifty burning enemies are fifty ticks a second, not fifty a frame.
const BURN_TICK_INTERVAL := 0.5

var enemy_data: EnemyData
var health: float = 100.0
var health_bar: EnemyHealthBar
var visual_anim_player: AnimationPlayer
var is_dying: bool = false
## Client-side latch for the death clip. `is_dying` replicates, so it is true on every
## frame after the first, and the clip must only be started on that first one.
var _puppet_death_played: bool = false
## The death launch: the velocity a killed enemy is thrown away with (see
## _start_death_launch). Set once, on the server, and replicated, so every peer leans the
## body into the same throw; the throw itself is the replicated position.
var death_launch: Vector3 = Vector3.ZERO
## What the fatal hit was, kept by take_damage for die(): which way it came from and how
## big it was (a fraction of full health, knockback included).
var _fatal_hit_dir: Vector3 = Vector3.ZERO
var _fatal_hit_severity: float = 0.0
## Seconds since this peer saw the launch begin; -1 before that.
var _launch_time: float = -1.0
var _launch_landed: bool = false
## How long the death clip takes at the speed it was started with, on this peer.
var _death_clip_seconds: float = 0.0
## The lean has run its course and the model is back as built; nothing left to do per frame.
var _lean_done: bool = false
## Stage 2: the body went limp instead (EnemyRagdoll), on this peer. Asked once, as the
## hitstop ends; from then on the ragdoll owns the model and the lean leaves it alone.
var _ragdoll_asked: bool = false
var _ragdoll: EnemyRagdoll
## The model and its transform as built, so the lean can be laid over it and taken off.
var _visual_root: Node3D
var _visual_rest: Transform3D

# Playback multiplier for this enemy's clips. Stays 1.0 for regular enemies;
# bosses get a size-derived value so bigger ones move more ponderously.
var _anim_speed_scale: float = 1.0
var _reaction_clip: String = ""

## Physics layer 5, the one the lanes and the base plateau are on (see project.godot's
## 3d_physics/layer_5="Environment"). The only layer a corpse still needs.
const ENVIRONMENT_LAYER: int = 1 << 4

## The clips an enemy can MOVE on, in no particular order - _play_locomotion picks between
## whichever of them this enemy's library actually has. Matches
## CharacterBuilder.LOCOMOTION_CLIPS, which is what puts them there.
const LOCOMOTION_CLIPS: Array[String] = ["walk", "run"]

## Locomotion clip name -> how far that clip carries THIS enemy per second at playback 1.0,
## at the size it is rendered but before model_scale (see _resolve_locomotion). Empty for
## anything whose library was built before stride measuring - a boss, or a CSGBox
## placeholder - and an empty dictionary is what puts _play_locomotion back on the old
## "always walk, always at _anim_speed_scale" path.
var _locomotion: Dictionary = {}
## Playback rate currently applied to the locomotion clip, so the speed is only re-sent
## when it actually changed.
var _locomotion_speed: float = 0.0

# --- Boss special attack (telegraphed and dodgeable) ---
## Every special this boss has across all three phases, and a cooldown per entry. See
## BossDatabase.SPECIALS - index 0 is the big phase-1 attack and index 1 the melee one.
var _specials: Array = []
var _special_cooldowns: Array[float] = []
## Indices into _specials in the order _pick_special considers them (priority, then index).
var _special_order: Array[int] = []
## The one currently being played, once _begin_special has chosen it.
var _special_config: Dictionary = {}
var _special_index: int = -1
## Seconds until the MAIN strike lands, and until the whole special is over.
var _special_windup_timer: float = 0.0
var _special_total_timer: float = 0.0
var _is_special_active: bool = false
var _special_resolved: bool = false
## The special as a timeline - the main strike and its followups. See _start_cast.
var _cast_strikes: Array[Dictionary] = []
var _cast_elapsed: float = 0.0
var _cast_end_time: float = 0.0
var _cast_target: Node3D = null
## How the boss is moving during the special, if at all: a leap, a charge or a follow.
var _cast_move: Dictionary = {}
## Every telegraph this boss has standing, so dying can take them all down.
var _cast_indicators: Array[AttackIndicator] = []
## ...and every BossTell beside them - the meteors, spikes and walls of light.
var _cast_tells: Array[BossTell] = []
var _cast_is_transition: bool = false
## Named, MTG-flavoured trait - see GameSettings' Boss modifiers block and
## apply_boss_modifier(). Empty for an ordinary boss and for every non-boss enemy.
var boss_modifier: String = ""
## One-way latch for Enrage: true from the moment the boss reaches phase 3, never reverts.
## See _check_boss_phase().
var _enrage_active: bool = false

# --- Boss phases ---
## 1, 2 or 3. One-way - see _check_boss_phase and GameSettings' Boss phases block.
## Replicated, so a client's boss bar can name the phase.
var boss_phase: int = 1
## True while the boss heals itself for having been left alone - see _tick_boss_regen.
## Replicated for the same reason.
var boss_regenerating: bool = false
## Seconds since anything last hurt this boss.
var _since_boss_hit: float = 0.0
var _pending_phase_transition: bool = false
## BossDatabase.PHASES for this boss's colour.
var _phase_config: Dictionary = {}
## The punish window after a special that carries `exhaust`: rooted and taking more damage.
var _exhausted_timer: float = 0.0
var _exhausted_mult: float = 1.0
## White's Consecration: kneeling, healing at the end unless the team breaks it.
var _channel_active: bool = false
var _channel_damage: float = 0.0
var _channel_broken: bool = false
var _shield_feedback_ready_msec: int = 0
var _saplings_grown: bool = false
## A client holds whatever clip the server's boss_fx started for this long, instead of
## dropping back to walk-or-stand from the replicated velocity.
var _puppet_hold_timer: float = 0.0
## Set on a treant's sapling, on the server: whom it heals if it is left standing.
var sapling_boss: Node3D = null
var _sapling_timer: float = -1.0
## Recovery (see _check_recovery): time to the next check, and how long this enemy has been
## standing off the navmesh. The first check lands at a random point in the interval, so a
## squad spawned in one frame does not run all its checks in one frame from then on.
var _recovery_timer: float = randf() * GameSettings.enemy_recovery_check_interval
var _off_navmesh_time: float = 0.0
## A sapling that withered on its own was not killed, and pays nothing.
var _skip_kill_rewards: bool = false

# --- Miniboss special (Mage only, telegraphed and dodgeable) ---
## Deliberately separate state from the boss special block above rather than reusing it: a
## Mage miniboss has exactly ONE special, not a pair with its own cooldown array and shape
## choice, and it never roots the mage's ordinary spellcasting loop the way a boss's specials
## replace its whole attack pattern. -1 means no windup is in progress.
var _miniboss_special_windup: float = -1.0
var _miniboss_special_indicator: AttackIndicator
var damage_penalty: float = 0.0
var penalty_timer: float = 0.0
var attack_cooldown: float = 0.0
## Seconds until the swing in flight actually connects, or -1 when nothing is in
## flight. An attack used to pay out on the frame it STARTED, which left its impact
## sound - and its damage - landing while the weapon was still behind the enemy's
## head. The clip now carries the frame it connects on, measured at build time by
## tools/animation_impact.gd, and this is that moment counting down.
var _impact_timer: float = -1.0
## Seconds of flinch left, and the gap before another one may start.
var _hit_react_timer: float = 0.0
var _hit_react_cooldown: float = 0.0
var frost_slow_timer: float = 0.0
var path_update_timer: float = 0.0

# --- MTG Status Effects ---
var chill_stacks: int = 0
var freeze_timer: float = 0.0
var root_timer: float = 0.0
var stun_timer: float = 0.0
var blind_timer: float = 0.0
var curse_timer: float = 0.0
var curse_mult: float = 1.0
var pacified_timer: float = 0.0
## Fleeing: runs AWAY from whatever frightened it instead of fighting. Set by apply_fear, which
## no spell calls since Contagion replaced Fear in black's second slot.
var flee_timer: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
## Roar (green_4): forced onto one target regardless of what is closer. The taunt
## outranks the ordinary evaluation, which is the entire point of pulling enemies off
## the crystal and the myrs.
var taunt_timer: float = 0.0
var taunt_source: Node3D = null
## Fog (green_3): inside the cloud this enemy deals nothing at all. A separate timer
## from `damage_penalty` because that one is a flat SUBTRACTION and a big enough enemy
## would still push damage through it.
var damage_suppress_timer: float = 0.0
## The SOFT slow, as opposed to frost's hard one. Fog's wading and Fire Cone's sustained
## pressure both ride this; both refresh it continuously and both want a multiplier of their
## own rather than frost's iconic 0.3, which also drags attack speed with it.
##
## One channel shared by both rather than a timer per spell: they compose by taking the
## strongest slow rather than multiplying down to a standstill, and a third source later
## costs nothing but a call. See apply_slow().
var slow_timer: float = 0.0
var slow_mult: float = 1.0
## Burn (Orb of Fire, Fire Dash's trail is a zone instead): damage over time carried by
## the enemy rather than by a zone, so it follows whoever is running away with it.
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var burn_tick: float = 0.0
var burn_source: Node3D = null
## Contagion (black_2): a plague that burns like a burn and, every spread interval, jumps to
## the nearest uninfected enemy. Replicated, so every screen can see who is sick.
var contagion_timer: float = 0.0
var _contagion_tick: float = 0.0
var _contagion_spread_timer: float = 0.0
var _contagion_source: Node3D = null
## Shared by every victim of one cast - what caps how far one cast can run, and what each
## new victim is infected with. See SpellEffects.cast_black_contagion.
var _contagion_outbreak: Dictionary = {}
var _contagion_fx: GPUParticles3D = null
## The plague's colour: a sick green over black's violet. Here rather than on SpellEffects,
## which already depends on this class - the dependency only runs one way.
const CONTAGION_TINT := Color(0.6, 0.95, 0.35)

## The most health this enemy has, for anything reading it through HealthReader. Kill's
## boss clause asks for a boss's health RATIO, and with no maximum to divide by HealthReader
## answered "unreadable" - so Kill refused every boss at any health, forever.
var max_health: float:
	get:
		return enemy_data.health if enemy_data != null else health
## Exalted Strike marked this enemy: the killing blow exiles it instead of leaving a
## corpse. Set by take_damage, read by die().
var _exile_on_death: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
## Suction (blue_3). The zone re-applies every frame while the enemy is inside, so the
## timer only has to outlive one frame gap. Kept apart from knockback_velocity: the
## flinch reaction keys off knockback, and a held pull would read as one long flinch.
var _suction_timer: float = 0.0
var _suction_center: Vector3 = Vector3.ZERO
var _suction_strength: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aggro_area: Area3D = $AggroArea
@onready var aggro_col: CollisionShape3D = $AggroArea/CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# For Mages
var cast_timer: float = 0.0
var target_eval_timer: float = 0.0
var elite_modifier: String = ""
var elite_regeneration_per_second: float = 0.0
var elite_crystal_damage_multiplier: float = 1.0
var has_green_mage_buff: bool = false

# --- Minibosses ------------------------------------------------------------------------
#
# A separate, higher tier from Elite (see GameSettings' Minibosses block for the reasoning)
# - bigger, glowing in its colour, and for a Mage the one enemy in the wave that throws a
# real telegraphed spell instead of the quiet single-target cast every ordinary mage of its
# colour uses. See apply_miniboss() and _perform_miniboss_special().
var is_miniboss: bool = false
## Only ever set for a Mage miniboss; every other class leaves this at 0 and never reads it.
var _miniboss_special_timer: float = 0.0

# --- Squad formation ---------------------------------------------------------------
#
# A wave now arrives as whole formations rather than as a queue of individuals (see
# EnemySquad), and while an enemy is IN one it walks to a slot measured off the squad's
# moving anchor instead of straight at the crystal, capped to the squad's march speed so
# the melee cannot outrun the mages they are supposed to be screening.
#
# Untyped on purpose: EnemySquad has to name EnemyBase and this would have to name
# EnemySquad, and a pair of class_name scripts annotating each other is the cycle GDScript
# resolves badly. Everything here goes through duck typing instead.
#
# `leave_formation()` is the single exit, and it is deliberately one-way - an enemy that
# has broken ranks never re-joins. Re-forming mid-fight would mean walking back out of a
# fight it is already in.
var squad = null
## Cached off the squad at join time so the per-frame leash check costs no calls.
var _formation_leash: float = 0.0
## Charge bonus from the squad, kept on the ENEMY rather than read off the squad so it
## survives the squad dissolving at the moment of contact.
var charge_timer: float = 0.0
var charge_mult: float = 1.0

func _ready() -> void:
	# Spawned through MultiplayerSpawner, so the colour/class pair arrives as metadata
	# that _spawn_enemy set identically on every peer - setup() then rebuilds the same
	# EnemyData locally rather than trying to replicate a Resource.
	if has_meta("enemy_color") and has_meta("enemy_type"):
		setup(EnemyDatabase.get_enemy_data(String(get_meta("enemy_color")), String(get_meta("enemy_type"))))
	_build_synchronizer()
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 31
	
	if has_meta("target_crystal"):
		target_crystal = get_meta("target_crystal")
	else:
		var crystal_nodes = get_tree().get_nodes_in_group("crystal")
		if crystal_nodes.size() > 0:
			target_crystal = crystal_nodes[0]
			
	current_target = target_crystal
	update_path(true)
	
	if aggro_area:
		aggro_area.body_entered.connect(_on_aggro_body_entered)
		aggro_area.body_exited.connect(_on_aggro_body_exited)

func setup(data: EnemyData) -> void:
	enemy_data = data
	# EnemyDatabase hands out a fresh EnemyData per enemy, so scaling it here is safe and
	# keeps max health, the health bar and the flinch threshold all reading one number.
	enemy_data.health *= GameSettings.get_enemy_health_factor(PlayerRegistry.count())
	# Waves are their own difficulty axis on top of head count: a wave-20 enemy fights
	# at x2.2 the wave-1 health, linearly, so the curve never runs away.
	var wave: int = 0
	var scene: Node = get_tree().current_scene
	if scene != null:
		var wave_manager: Node = scene.get_node_or_null("WaveManager")
		if wave_manager != null and "current_wave" in wave_manager:
			wave = int(wave_manager.current_wave)
	enemy_data.health *= GameSettings.get_wave_health_factor(wave)
	health = enemy_data.health
	
	# Adjust Aggro Area based on range
	if aggro_col and aggro_col.shape is SphereShape3D:
		var shape: SphereShape3D = aggro_col.shape as SphereShape3D
		shape.radius = _get_detection_range()
		
	cast_timer = data.attack_speed

	# Visuals. Bosses have their own dedicated models; if one is missing they fall
	# back to the scaled-up melee model that stood in for them previously.
	var visual_scene: PackedScene = null
	# A sapling wears its boss's own model - a small treant, not a borrowed elf - so it reads
	# as the boss's offspring at a glance.
	if data.enemy_class == "Boss" or has_meta("sapling"):
		visual_scene = BossDatabase.get_visual_scene(data.color_identity)
	if visual_scene == null:
		if (data.enemy_class == "Melee" or data.enemy_class == "Boss") and MELEE_VISUAL_SCENES.has(data.color_identity):
			visual_scene = MELEE_VISUAL_SCENES[data.color_identity]
		elif data.enemy_class == "Ranged" and RANGED_VISUAL_SCENES.has(data.color_identity):
			visual_scene = RANGED_VISUAL_SCENES[data.color_identity]
		elif data.enemy_class == "Mage" and MAGE_VISUAL_SCENES.has(data.color_identity):
			visual_scene = MAGE_VISUAL_SCENES[data.color_identity]

	if visual_scene:
		var visual_instance: Node3D = visual_scene.instantiate()
		# Scale correction: imported models are tiny (~0.016m). We scale them up 100x to match a 1-unit base.
		visual_instance.scale = Vector3(100, 100, 100)
		add_child(visual_instance)
		_ground_visual(visual_instance)
		_visual_root = visual_instance
		_visual_rest = visual_instance.transform
		# find_child rather than get_node: it holds for both the melee scenes (player
		# is a direct child) and the imported boss scenes, without assuming depth.
		visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
		_reaction_clip = _resolve_reaction_clip()
		_resolve_locomotion(visual_instance)
		_rest_visual_animation()
	else:
		var visual = CSGBox3D.new()
		visual.size = Vector3(0.8, 1.7, 0.8)
		visual.position = Vector3(0, 0.85, 0)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = data.visual_color
		mat.roughness = 0.5
		visual.material = mat
		add_child(visual)

	# A treant's sapling: a small copy of the treant, rooted where it grew, and on a clock.
	# Sized off the boss rather than off a Green melee, so it stays in proportion to its parent.
	if has_meta("sapling"):
		data.model_scale = BossDatabase.get_model_scale(data.color_identity, 2.5) * GameSettings.boss_sapling_scale_mult
		data.speed = 0.0
		_sapling_timer = GameSettings.boss_sapling_heal_delay

	scale = Vector3(data.model_scale, data.model_scale, data.model_scale)
	aggro_area.scale = Vector3.ONE / maxf(data.model_scale, 0.01)
	health_bar = _health_bar_scene.instantiate() as EnemyHealthBar
	add_child(health_bar)
	health_bar.set_health(health, data.health)
	if has_meta("sapling"):
		# Says what it is before anyone has to work it out: the thing to kill before it heals.
		health_bar.set_modifier_tag("SAPLING", Color(0.45, 0.95, 0.35))

	if data.enemy_class == "Boss":
		# Announced out loud, in its own voice. A boss that walks in with the same
		# footsteps as a goblin is a boss the player does not look up for - and a treant
		# that arrives sounding like a fire giant is barely better.
		SoundBank.play_at(StringName("boss_spawn_" + data.color_identity.to_lower()), global_position)
		_anim_speed_scale = GameSettings.get_boss_anim_speed(data.model_scale)
		# A boss that animates slower should also swing less often - otherwise
		# perform_attack() just compresses the swing back to normal speed to fit
		# the unchanged cadence and the size never reads in the animation.
		data.attack_speed /= maxf(_anim_speed_scale, 0.01)
		_specials = BossDatabase.get_specials(data.color_identity)
		_phase_config = BossDatabase.get_phase_config(data.color_identity)
		_special_cooldowns.clear()
		_special_order.clear()
		for i: int in range(_specials.size()):
			_special_cooldowns.append(GameSettings.boss_special_first_delay)
			_special_order.append(i)
		# Priority first, then the order BossDatabase lists them in - the index tie-break is
		# what keeps this deterministic, since sort_custom is not stable.
		_special_order.sort_custom(func(a: int, b: int) -> bool:
			var pa: int = int((_specials[a] as Dictionary).get("priority", 0))
			var pb: int = int((_specials[b] as Dictionary).get("priority", 0))
			if pa != pb:
				return pa > pb
			return a < b)
		if has_meta("boss_modifier"):
			apply_boss_modifier(String(get_meta("boss_modifier")))

	if has_meta("elite_modifier"):
		apply_elite_modifier(String(get_meta("elite_modifier")))

	if has_meta("miniboss"):
		apply_miniboss()

func update_path(force_update: bool = false) -> void:
	if not nav_agent:
		return
	
	var target_pos: Vector3 = Vector3.ZERO
	if is_in_formation():
		# The slot, not the objective. The squad's anchor is already walking towards the
		# crystal, so this still converges on it - just in rank, and at the formation's
		# pace rather than this enemy's own.
		target_pos = squad.formation_target(self)
	elif current_target and is_instance_valid(current_target):
		target_pos = current_target.global_position
	elif target_crystal and is_instance_valid(target_crystal):
		target_pos = target_crystal.global_position
		
	if force_update or target_pos.distance_squared_to(last_target_position) > 0.1:
		nav_agent.target_position = target_pos
		last_target_position = target_pos

## Whether this enemy is currently walking to a formation slot rather than fighting.
##
## Every condition here is a reason the slot has stopped being the right place to be: the
## squad dissolved, something worth attacking came into view, or the enemy is being moved
## by an effect that overrides its own intentions entirely.
func is_in_formation() -> bool:
	if squad == null or not is_instance_valid(squad) or not squad.holds_formation():
		return false
	if flee_timer > 0.0 or taunt_timer > 0.0:
		return false
	return current_target == target_crystal or current_target == null


func join_squad(new_squad) -> void:
	squad = new_squad
	_formation_leash = new_squad.leash()
	update_path(true)


## Breaking ranks. One-way, and safe to call more than once - disband() calls it for every
## member at the same moment a member may be calling it for itself.
func leave_formation() -> void:
	if squad == null:
		return
	var former = squad
	squad = null
	if is_instance_valid(former):
		former.release(self)
	update_path(true)


## The squad's charge. Lives on the enemy rather than on the squad so it outlasts the
## formation dissolving - the charge is most of the point at exactly the moment the ranks
## come apart on the crystal.
func apply_squad_charge(duration: float, multiplier: float) -> void:
	charge_timer = maxf(charge_timer, duration)
	charge_mult = maxf(charge_mult, multiplier)


## Position, rotation, health, motion and dying, authored by the server. An enemy's AI is
## expensive and must reach the same answer everywhere, so only the server runs it; clients
## render what they are told.
##
## `velocity` is on the list because `_update_visual_animation` picks walk-or-stand from
## it, and for want of it every enemy on a client stood perfectly still while gliding down
## the lane. The comment here used to say clients animate "from the replicated transform" -
## they did not, because the transform was replicated and the velocity behind the decision
## was not.
##
## `is_dying` for the same reason one step further on: the server plays the death clip and
## frees the body a couple of seconds later, and a client that never learns the enemy died
## shows it standing until it blinks out of existence mid-stride.
func _build_synchronizer() -> void:
	if not Net.is_active():
		return
	var config := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":health", ":velocity", ":is_dying", ":contagion_timer"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	# Once per enemy, at death; the lean starts on whichever frame it lands.
	config.add_property(NodePath(":death_launch"))
	config.property_set_replication_mode(NodePath(":death_launch"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	# What the HUD's boss bar shows beyond health. Only on bosses, and only when it changes -
	# both move a handful of times a fight. setup() has run by now, so is_boss() is settled
	# and every peer builds the same property list for the same enemy.
	if is_boss():
		for property: String in [":boss_phase", ":boss_regenerating"]:
			config.add_property(NodePath(property))
			config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(1)
	add_child(sync)


func _ground_visual(visual_instance: Node3D) -> void:
	var skeleton: Skeleton3D = visual_instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var mesh_instance: MeshInstance3D = null
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		return
	var local_aabb: AABB = mesh_instance.get_aabb()
	var min_y: float = INF
	for corner_idx: int in range(8):
		var corner: Vector3 = local_aabb.position + Vector3(
			local_aabb.size.x * float(corner_idx & 1),
			local_aabb.size.y * float((corner_idx >> 1) & 1),
			local_aabb.size.z * float((corner_idx >> 2) & 1)
		)
		min_y = min(min_y, (mesh_instance.global_transform * corner).y)
	if is_finite(min_y):
		visual_instance.position.y -= min_y - global_position.y


func _physics_process(delta: float) -> void:
	if not enemy_data:
		return # Not initialized yet
	# The client branch comes FIRST, before the is_dying guard below. A dying enemy is
	# exactly what a client still has work to do about - it has a death clip to play that
	# the server started on its own copy and cannot play on this one.
	if not Net.is_server():
		_update_puppet(delta)
		return
	if is_dying:
		if death_launch != Vector3.ZERO:
			_fly_corpse(delta)
		else:
			_settle_corpse(delta)
		_lean_corpse(delta)
		return

	if _check_recovery(delta):
		return

	if _sapling_timer > 0.0:
		_sapling_timer -= delta
		if _sapling_timer <= 0.0:
			_wither_sapling()
			return

	if is_boss():
		_tick_boss_regen(delta)

	if elite_regeneration_per_second > 0.0 and health < enemy_data.health:
		heal(elite_regeneration_per_second * delta, false)
		
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	if frost_slow_timer > 0:
		frost_slow_timer -= delta
		
	if penalty_timer > 0:
		penalty_timer -= delta
		if penalty_timer <= 0:
			damage_penalty = 0.0
			
	if attack_cooldown > 0:
		attack_cooldown -= delta

	if _hit_react_cooldown > 0.0:
		_hit_react_cooldown -= delta
	if _hit_react_timer > 0.0:
		_hit_react_timer -= delta

	if _impact_timer >= 0.0:
		_impact_timer -= delta
		if _impact_timer <= 0.0:
			_impact_timer = -1.0
			_resolve_attack_impact()
			# Landing a hit can kill the attacker: Reprisal Ward reflects a share of the
			# damage straight back, and the reflect runs inline inside the target's
			# take_damage. Same in-frame death as the slam and the burn below.
			if is_dying:
				return
		
	if enemy_data.enemy_class == "Mage":
		cast_timer -= delta
		if cast_timer <= 0:
			perform_mage_spell()
			# Spells have a longer cooldown than regular attacks
			cast_timer = enemy_data.attack_speed * GameSettings.enemy_mage_spell_cooldown_mult
		# The special runs on its OWN clock, entirely separate from the ordinary cast
		# above - it does not consume or reset cast_timer, so a miniboss keeps throwing its
		# normal spell on schedule and the special is purely additional.
		if is_miniboss and _miniboss_special_windup < 0.0:
			_miniboss_special_timer -= delta
			if _miniboss_special_timer <= 0.0:
				_begin_miniboss_special()

	var dist_to_target = 999.0
	if is_instance_valid(current_target):
		dist_to_target = global_position.distance_to(current_target.global_position)
		# Update path periodically so they track moving targets like the player
		path_update_timer -= delta
		if path_update_timer <= 0:
			path_update_timer = GameSettings.enemy_path_update_interval
			update_path()
		
	target_eval_timer -= delta
	if target_eval_timer <= 0:
		target_eval_timer = GameSettings.enemy_target_eval_interval
		evaluate_target()
		
	# Process Knockback & Wall Collision
	if knockback_velocity.length_squared() > 0.1:
		var collision = move_and_collide(knockback_velocity * delta)
		if collision:
			var collider = collision.get_collider()
			if collider and not collider.is_in_group("enemies"):
				var impact_damage: float = GameSettings.spell_blue_unsummon_impact_damage
				if collider.has_method("get_unsummon_bonus_damage"):
					impact_damage += float(collider.get_unsummon_bonus_damage())
				take_damage(impact_damage)
				knockback_velocity = Vector3.ZERO
				# The slam can be lethal - being shoved into a Wall of Frost adds its bonus
				# damage on top - and take_damage runs die() inline. Everything below this
				# point is AI and movement for an enemy that no longer exists, ending in
				# _update_visual_animation; the animation guard stops it clobbering the death
				# clip, and this stops it running at all.
				if is_dying:
					return
		else:
			knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)

	# Suction (blue_3): a steady drag toward the zone's centre, refreshed per frame by
	# the zone itself. move_and_collide rather than velocity, so it works on enemies
	# that are attacking, rooted or mid-swing exactly the way knockback does.
	if _suction_timer > 0.0:
		_suction_timer -= delta
		var inward: Vector3 = _suction_center - global_position
		inward.y = 0.0
		if inward.length() > 0.6:
			move_and_collide(inward.normalized() * _suction_strength * delta)

	# Process Timers
	if freeze_timer > 0: freeze_timer -= delta
	if root_timer > 0: root_timer -= delta
	if stun_timer > 0: stun_timer -= delta
	if blind_timer > 0: blind_timer -= delta
	if curse_timer > 0: curse_timer -= delta
	if pacified_timer > 0:
		pacified_timer -= delta
		if pacified_timer <= 0:
			damage_penalty = 0.0
	if damage_suppress_timer > 0.0:
		damage_suppress_timer -= delta
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_mult = 1.0
	if charge_timer > 0.0:
		charge_timer -= delta
		if charge_timer <= 0.0:
			charge_mult = 1.0
	if taunt_timer > 0.0:
		taunt_timer -= delta
		if taunt_timer <= 0.0:
			taunt_source = null
			evaluate_target()
	if flee_timer > 0.0:
		flee_timer -= delta
		if flee_timer <= 0.0:
			update_path(true)
	if burn_timer > 0.0:
		burn_timer -= delta
		burn_tick -= delta
		if burn_tick <= 0.0:
			burn_tick = BURN_TICK_INTERVAL
			take_damage(burn_dps * BURN_TICK_INTERVAL, burn_source)
			# A burn that ticks an enemy to death kills it from inside its own frame, exactly
			# as the knockback slam above does.
			if is_dying:
				return
		if burn_timer <= 0.0:
			burn_dps = 0.0
			burn_source = null
	if contagion_timer > 0.0:
		_tick_contagion(delta)
		# The plague can kill from inside this frame, exactly as the burn above can.
		if is_dying:
			return
	_sync_contagion_fx()

	# Boss special attack. Runs before the normal movement/attack block because a
	# committed special overrides both - the boss is rooted for its whole duration.
	for i: int in range(_special_cooldowns.size()):
		if _special_cooldowns[i] > 0.0:
			_special_cooldowns[i] -= delta
	# Exhausted: open, reeling and rooted until the window closes. See _begin_exhaust.
	if _exhausted_timer > 0.0:
		_exhausted_timer -= delta
		if _exhausted_timer <= 0.0:
			_exhausted_mult = 1.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if _is_special_active:
		_process_special(delta)
		return
	# A phase change waits for the special in flight to finish, then takes the next turn.
	if _pending_phase_transition:
		_begin_phase_transition()
		_process_special(0.0)
		return
	var ready_special: int = _pick_special(dist_to_target)
	if ready_special >= 0:
		_begin_special(ready_special)
		_process_special(0.0)
		return

	# A Mage miniboss's special, same idea as a boss's but on its own separate state - see
	# the block above _miniboss_special_windup's declaration. Rooted for the windup so the
	# indicator's ground position stays where the special was actually cast, exactly the
	# reason a boss special roots too.
	if _miniboss_special_windup >= 0.0:
		_process_miniboss_special(delta)
		return

	# Disable movement if frozen, stunned, or mid-attack-swing (the swing has no
	# root motion of its own - moving the body while it plays would make the legs
	# look planted while the character visibly slides).
	var is_attack_swing_playing: bool = visual_anim_player != null and visual_anim_player.current_animation == "attack" and visual_anim_player.is_playing()
	if freeze_timer > 0 or stun_timer > 0 or is_attack_swing_playing:
		# A shooter keeps tracking through its own wind-up. Its projectile leaves on a
		# measured frame partway into the clip (see _resolve_attack_impact), and that
		# shot is aimed from live positions - so a body still pointing where the target
		# stood when the animation started reads as firing sideways. A melee swing is
		# deliberately NOT tracked: committing to a direction is what makes stepping
		# out of one work. Frozen or stunned, nothing turns at all.
		if is_attack_swing_playing and freeze_timer <= 0 and stun_timer <= 0 and _tracks_target_while_attacking():
			_face_target(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_visual_animation()
		return

	# Feared: no target, no attack, just distance. Handled before the ordinary block
	# rather than inside it because a fleeing enemy has nothing to say about range -
	# it is running, and running is all it does until the timer ends.
	if flee_timer > 0.0:
		_flee(delta)
		_update_visual_animation()
		return

	# The leash. A member that has been shoved further from its slot than its colour
	# tolerates gives up on the formation rather than walking back through whoever shoved
	# it to stand in a rank. Re-pathing is not needed here: the ordinary path_update_timer
	# above already refreshes the target every enemy_path_update_interval, and for a member
	# in formation update_path() resolves that target to the live slot.
	var holding_formation: bool = is_in_formation()
	if holding_formation and global_position.distance_to(squad.formation_target(self)) > _formation_leash:
		leave_formation()
		holding_formation = false

	# A formation slot MOVES, which breaks every assumption the ordinary movement block
	# makes about arriving somewhere. The navigation agent calls itself finished within 1.5
	# units of its target - further than a slot travels in a frame - so an enemy that used
	# that as its stop condition would halt, be left behind, walk, halt again, and flicker
	# between its walk and idle clips the whole way down the lane. Instead a member in
	# formation never stops navigating and moves at exactly the speed needed to stay on its
	# slot, which in steady state IS the squad's march speed.
	var formation_pull: float = -1.0
	if holding_formation:
		var slot_gap: Vector3 = squad.formation_target(self) - global_position
		slot_gap.y = 0.0
		formation_pull = slot_gap.length() / maxf(delta, 0.0001)

	# Movement
	var is_in_attack_range: bool = dist_to_target <= enemy_data.attack_range
	if not is_in_attack_range and root_timer <= 0 and (holding_formation or not nav_agent.is_navigation_finished()):
		var next_path_position = nav_agent.get_next_path_position()
		# Close to its slot, a member steers at the LIVE slot rather than at the path's end
		# point, which is up to one repath interval out of date and would drag the whole
		# formation a step backwards every time it refreshed.
		if holding_formation and nav_agent.is_navigation_finished():
			next_path_position = squad.formation_target(self)
		var move_speed: float = enemy_data.speed * movement_speed_mult()
		# The cap is what makes a formation a formation: everyone moves at the anchor's
		# pace (plus a little, so stragglers can close up) instead of at their own, so a
		# 2.5-speed melee cannot leave the 1.5-speed mage it is screening behind.
		if holding_formation:
			move_speed = minf(move_speed, squad.member_speed_limit())
			move_speed = minf(move_speed, formation_pull)
		var new_velocity: Vector3 = (next_path_position - global_position).normalized() * move_speed
		velocity.x = new_velocity.x
		velocity.z = new_velocity.z
		
		if velocity.length_squared() > 0.01:
			var target_rotation = atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, GameSettings.enemy_turn_speed * delta)
			
		move_and_slide()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

		if not is_in_attack_range:
			if root_timer <= 0 and nav_agent.is_navigation_finished():
				update_path(true)
			_update_visual_animation()
			return

		_face_target(delta)

		# Bosses have no ordinary swing. Everything they do is a telegraphed special now (see
		# BossDatabase.SPECIALS), which is the whole point: an undodgeable hit from something
		# that big was the one attack in the game a player had no answer to. _pick_special
		# above is what actually attacks for them.
		if attack_cooldown <= 0 and blind_timer <= 0 and not is_boss():
			perform_attack()

	_update_visual_animation()

## The black mage's raise: a new weak enemy of this colour beside the caster.
##
## It goes through the MainController's enemy spawner like every wave enemy. Instantiating it
## here and add_child-ing it put it on the host alone: the host fought something no client
## could see, and nothing it did reached them.
func _raise_revived_enemy(enemy_type: String, power: float) -> void:
	if not Net.is_server():
		return
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("request_enemy"):
		return
	var revived_data: EnemyData = EnemyDatabase.get_enemy_data("Black", enemy_type)
	var spot: Vector3 = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	var new_enemy: Node3D = main.request_enemy({
		"position": (main as Node3D).to_local(spot),
		"color": "Black",
		"type": enemy_type,
	})
	if new_enemy == null:
		return
	new_enemy.health = revived_data.health * GameSettings.enemy_black_mage_revive_hp_mult * power
	var wm: Node = main.get_node_or_null("WaveManager")
	if wm:
		wm.register_enemy()


## Turns towards whatever this enemy is currently attacking. No-ops without a live
## target, so callers do not each need their own validity check.
func _face_target(delta: float) -> void:
	if not is_instance_valid(current_target):
		return
	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return
	var target_rotation: float = atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, GameSettings.enemy_turn_speed * delta)


## Whether this class attacks at range rather than by connecting with something.
## Shooters keep aiming while their attack clip plays, because they release partway
## through it - anything that swings a weapon does not, because a swing that tracked
## its target could never be side-stepped - and they make a release noise rather than
## a swing-and-impact pair.
func _is_shooter() -> bool:
	return enemy_data != null and (enemy_data.enemy_class == "Ranged" or enemy_data.enemy_class == "Mage")


func _tracks_target_while_attacking() -> bool:
	return _is_shooter()


## Everything a client's copy of an enemy does. It has no AI, no navigation and no
## damage - its transform arrives over the wire - but three things still have to happen
## here, because the code that normally does them only ever runs on the server:
##
##   * the HEALTH BAR. `health` replicates, but `set_health` is only called from
##     take_damage and heal, so the bar sat at full while the number underneath it fell.
##   * the ANIMATION, from the replicated velocity.
##   * the DEATH, which the server plays on its own copy and frees a moment later.
##
## Together these are why a joining player reported being unable to hurt anything: the
## damage was landing perfectly well on the host, and absolutely none of it was visible.
func _update_puppet(delta: float) -> void:
	if health_bar != null and enemy_data != null:
		health_bar.set_health(health, enemy_data.health)
	# The plague's look, from the replicated timer - the plague itself only runs on the server.
	_sync_contagion_fx()
	if is_dying:
		_play_puppet_death()
		_lean_corpse(delta)
		return
	# A boss special, transition or exhaust the server told us about: its clip keeps playing.
	if _puppet_hold_timer > 0.0:
		_puppet_hold_timer -= delta
		return
	_update_visual_animation()


## The death clip, played once on a client when `is_dying` arrives.
##
## Not routed through _play_visual_animation: that funnel refuses outright while
## `is_dying` is set, which is deliberate - it is what stops the rest of a fatal frame
## overwriting the death pose with a walk - and this is the one caller that has to get
## past it. The server's own copy reaches the same clip through die().
func _play_puppet_death() -> void:
	if _puppet_death_played or visual_anim_player == null:
		return
	_puppet_death_played = true
	# die() drops the collision layer on the server only; without this the client's copy
	# stays solid and the joined player cannot walk through corpses.
	collision_layer = 0
	collision_mask = ENVIRONMENT_LAYER
	if health_bar != null:
		health_bar.visible = false
	remove_from_group("enemies")
	if not visual_anim_player.has_animation("death"):
		return
	var death_anim: Animation = visual_anim_player.get_animation("death")
	var death_speed: float = maxf(_anim_speed_scale, 0.05)
	if death_anim and death_anim.length / death_speed > DEATH_MAX_SECONDS:
		death_speed = death_anim.length / DEATH_MAX_SECONDS
	visual_anim_player.play("death", -1, death_speed)
	_death_clip_seconds = death_anim.length / death_speed if death_anim else 0.0


func _update_visual_animation() -> void:
	if not visual_anim_player:
		return
	if (_hit_react_timer > 0.0 or knockback_velocity.length_squared() > 0.1) and _reaction_clip != "":
		# Squeezed into the flinch window the same way the player's reactions are:
		# the raw clips run about a second, which is far too long to hand over.
		_play_visual_animation(_reaction_clip, _reaction_speed_scale())
	elif visual_anim_player.current_animation == "attack" and visual_anim_player.is_playing():
		pass # Let the attack swing finish before switching states.
	elif Vector2(velocity.x, velocity.z).length_squared() > 0.01:
		_play_locomotion(Vector2(velocity.x, velocity.z).length())
	else:
		_rest_visual_animation()

## Reads the stride measurement off this enemy's own clips, once, at spawn.
##
## `stride_speed` was measured on the built character at its own root scale, and EnemyBase
## then instantiates that same character and OVERWRITES the scale with 100 - so the clip
## carries the enemy proportionally further than it carried the model it was measured on.
## `stride_scale` records what it was measured at, and the ratio is applied here rather
## than assumed, because those two numbers live in different files and have drifted apart
## once already.
##
## model_scale is deliberately NOT folded in here: a miniboss is rescaled after setup
## (_apply_miniboss), so it is applied at use time from the live node scale instead.
func _resolve_locomotion(visual_instance: Node3D) -> void:
	_locomotion.clear()
	if visual_anim_player == null:
		return
	var rendered_scale: float = visual_instance.scale.y
	for clip_name: String in LOCOMOTION_CLIPS:
		if not visual_anim_player.has_animation(clip_name):
			continue
		var clip: Animation = visual_anim_player.get_animation(clip_name)
		if clip == null or not clip.has_meta("stride_speed"):
			continue
		var measured: float = float(clip.get_meta("stride_speed"))
		var measured_at: float = float(clip.get_meta("stride_scale", rendered_scale))
		if measured <= 0.0 or measured_at <= 0.0:
			continue
		_locomotion[clip_name] = measured * rendered_scale / measured_at


## Walk or run, and at what rate, for an enemy actually travelling at `speed`.
##
## One rule does both halves of this. Each clip knows the speed it was authored to travel
## at; the enemy picks the clip whose own speed is CLOSEST to its real one and then plays
## it at exactly the ratio between them. Choosing and stretching are the same measurement,
## so they can never disagree - the clip that gets picked is by definition the one that
## needs the least stretching.
##
## Closest is measured as a RATIO, not a difference: a clip half as fast as the enemy and
## one twice as fast are equally wrong, and a plain subtraction would call the fast one
## much worse. That is what makes the switch fall where it looks right rather than at a
## hand-picked speed - between a 1.04 walk and a 2.58 run, a Melee crosses over at 1.64
## units per second, which is most of the way to its own 2.5 top speed.
##
## SIZE comes in through the same door, with no separate rule: the clip is played on a
## body scaled by model_scale, so it covers model_scale times the ground per cycle. A
## miniboss at 1.35x has a longer stride and stays walking where an ordinary enemy of the
## same speed would break into a run, and a boss - scaled several times up, and slow -
## never leaves its walk at all.
func _play_locomotion(speed: float) -> void:
	if _locomotion.is_empty():
		# No measurement to go on: exactly the behaviour this enemy had before.
		_play_visual_animation("walk")
		return

	var body_scale: float = maxf(scale.y, 0.01)
	var best_clip: String = ""
	var best_error: float = INF
	var best_rate: float = 1.0
	for clip_name: String in _locomotion:
		var natural: float = float(_locomotion[clip_name]) * body_scale
		if natural <= 0.0:
			continue
		var rate: float = speed / natural
		var error: float = absf(log(rate))
		if error < best_error:
			best_error = error
			best_clip = clip_name
			best_rate = rate
	if best_clip == "":
		_play_visual_animation("walk")
		return

	var rate_clamped: float = clampf(best_rate, GameSettings.enemy_anim_match_min, GameSettings.enemy_anim_match_max)
	# _anim_speed_scale is NOT applied on top. For a boss it is a size-derived slowdown,
	# and size is already in body_scale above - multiplying both would slow a giant twice
	# for being big once. Every other enemy leaves it at 1.0 anyway.
	if best_clip != visual_anim_player.current_animation or not visual_anim_player.is_playing():
		_play_visual_animation(best_clip, rate_clamped)
		_locomotion_speed = rate_clamped
		return
	# Same clip, new pace. Re-issuing play() on a clip that is already playing updates its
	# speed and keeps its position (verified against 4.7), so this does not pop the cycle
	# back to frame zero every time the enemy accelerates.
	if absf(rate_clamped - _locomotion_speed) > GameSettings.enemy_anim_match_epsilon * maxf(_locomotion_speed, 0.1):
		_play_visual_animation(best_clip, rate_clamped, true)
		_locomotion_speed = rate_clamped


## Every clip this enemy plays EXCEPT the death one goes through here, and the is_dying guard
## is the reason it is a funnel at all.
##
## `die()` starts "death" and then the frame keeps running: it is reached from take_damage,
## which is called from inside _physics_process by the knockback slam and the burn tick, and
## from _deal_attack_impact when Reprisal Ward reflects a fatal hit back at the attacker. In
## every one of those the top-of-_physics_process is_dying check has ALREADY passed, so the
## rest of the frame ran on a corpse and finished with _update_visual_animation playing "walk"
## or "hit" straight over the death clip that had just been started. The enemy then held that
## pose forever, because from the next frame on _physics_process really does return early and
## nothing ever asks for another animation.
##
## That is the "stuck in the last pose" report, and the debug logging shows it exactly: those
## enemies get a `play_requested` line and never a `confirmed` one, because by the time the
## deferred check runs the current animation is walk or hit rather than death.
## `force_speed` re-issues play() even when this clip is already the one running, which is
## the only way to change a playing clip's rate: the guard below otherwise treats "same
## clip" as "nothing to do" and silently swallows the new speed. Only locomotion needs it -
## a swing or a flinch is played once at a rate fixed when it starts.
func _play_visual_animation(anim_name: String, speed_scale: float = -1.0, force_speed: bool = false) -> void:
	if is_dying:
		return
	var speed: float = _anim_speed_scale if speed_scale <= 0.0 else speed_scale
	if force_speed or visual_anim_player.current_animation != anim_name or not visual_anim_player.is_playing():
		visual_anim_player.play(anim_name, -1, speed)


## Playback rate that fits the flinch clip into enemy_hit_react_duration, scaled by
## this enemy's own animation pace so a boss still flinches ponderously.
func _reaction_speed_scale() -> float:
	var clip: Animation = visual_anim_player.get_animation(_reaction_clip)
	if clip == null or clip.length <= 0.0:
		return _anim_speed_scale
	return maxf(clip.length / maxf(GameSettings.enemy_hit_react_duration, 0.05), 0.05) * _anim_speed_scale

## Whichever name this enemy's animation library uses for its damage reaction.
func _resolve_reaction_clip() -> String:
	if visual_anim_player == null:
		return ""
	for candidate in REACTION_CLIP_CANDIDATES:
		if visual_anim_player.has_animation(candidate):
			return candidate
	return ""

# No dedicated idle clip - hold the first frame of "walk" instead. Avoids ever
# switching between two different poses (idle vs walk) right at the attack-range
# boundary, which was the main source of visible flicker.
func _rest_visual_animation() -> void:
	if is_dying:
		return
	if visual_anim_player.current_animation != "walk":
		visual_anim_player.play("walk", -1, _anim_speed_scale)
	if visual_anim_player.is_playing():
		visual_anim_player.pause()

# ============================================================
# BOSS SPECIAL ATTACK
#
# A special is a committed, telegraphed attack: the boss commits to a target and a facing,
# AttackIndicators draw every danger zone on the ground, and the damage only lands once a
# zone's fill completes. That fill window is the dodge.
#
# A special is played as a short TIMELINE of strikes rather than as one hit: the main strike,
# then any `followups` chained after it (a second charge, aftershock rings, a backswing).
# Each strike draws its own telegraph when it starts and lands when that telegraph fills, so
# every hit in a combo has a tell of its own. The boss is rooted for the whole timeline unless
# the special moves it (a charge, a leap, a whirlwind that walks).
#
# Everything a player SEES of this goes through _emit_boss_fx, which shows it here and sends
# the same description to every client: the AI only runs on the server, so a telegraph drawn
# only here would be a hit the other four players never saw coming.
# ============================================================

## Which special to start now, or -1. Walked in priority order (see BossDatabase.SPECIALS),
## only over the specials this phase has in play - so the attack the player has to move for
## wins wherever several are legal.
func _pick_special(dist_to_target: float) -> int:
	if _specials.is_empty() or _is_special_active:
		return -1
	if freeze_timer > 0.0 or stun_timer > 0.0 or root_timer > 0.0 or blind_timer > 0.0 or pacified_timer > 0.0:
		return -1
	if visual_anim_player == null:
		return -1
	for i: int in _special_order:
		if _special_cooldowns[i] > 0.0:
			continue
		var config: Dictionary = _specials[i]
		if not BossDatabase.special_in_phase(config, boss_phase):
			continue
		if _special_eligible(config, dist_to_target):
			return i
	return -1


func _special_eligible(config: Dictionary, dist_to_target: float) -> bool:
	# Needs a real clip to telegraph with; the placeholder-box fallback has none.
	if visual_anim_player == null or not visual_anim_player.has_animation(String(config.get("clip", "special"))):
		return false
	match String(config.get("kind", "")):
		"raise_dead":
			return not _raisable_corpses(config).is_empty()
		"consecrate":
			# Nothing to heal at full health, and kneeling then would hand the team a free window.
			return enemy_data != null and health < enemy_data.health * 0.95
	var rule: String = String(config.get("target", "current"))
	if rule != "current":
		# Aimed at a player by rule rather than at whoever the boss is walking towards - which is
		# exactly what lets these reach a player standing off while the boss heads for the crystal.
		return _rule_target(rule, float(config.get("min_range", 0.0)), _special_max_range(config)) != null
	if not is_instance_valid(current_target):
		return false
	# The big area attacks are only ever aimed at something that can DODGE. The crystal cannot,
	# so pointing one there would burn the cooldown on a guaranteed whiff. The melee special is
	# the exception - it is flagged hits_crystal, because a boss with no ordinary swing left
	# still has to be able to break the thing it walked across the map for.
	var target_is_dodger: bool = current_target.is_in_group("player") or current_target.is_in_group("myrs")
	var may_hit_crystal: bool = bool(config.get("hits_crystal", false)) and current_target == target_crystal
	if not target_is_dodger and not may_hit_crystal:
		return false
	# min_range keeps them apart: the big one is held back at point-blank so the melee one owns
	# that band, and nothing is started from further away than it could reach.
	return dist_to_target >= float(config.get("min_range", 0.0)) and dist_to_target <= _special_max_range(config)


## How far away a special may be started from. Explicit when the special says so, otherwise
## what its shape actually reaches (with a little held back, so a target at the very edge is
## not a guaranteed miss).
func _special_max_range(config: Dictionary) -> float:
	if config.has("max_range"):
		return float(config["max_range"])
	match String(config.get("shape", "circle")):
		"line", "cross":
			return float(config.get("length", 5.0)) * 0.9
		"ring":
			return float(config.get("radius", 5.0))
	return float(config.get("radius", 5.0)) * 0.9


func _begin_special(index: int) -> void:
	# Duplicated (deep) rather than the shared reference _specials[index] itself:
	# BossDatabase.SPECIALS is one Dictionary per colour, reused by every boss of that colour,
	# and a modifier's reach bump mutates THIS boss's copy for THIS cast only. Mutating the
	# shared one in place would widen the special for every other boss of the same colour, in
	# every other match, permanently.
	_start_cast((_specials[index] as Dictionary).duplicate(true), index)


## Commits to a special: picks its target, locks the facing, lays out the timeline of strikes
## and starts the first one. `index` is -1 for a phase transition, which has no cooldown.
func _start_cast(config: Dictionary, index: int, min_duration: float = 0.0, clip_speed: float = -1.0) -> void:
	if _is_special_active:
		_cancel_special()
	_special_index = index
	_special_config = config
	_apply_modifier_reach(_special_config)

	var clip: String = String(config.get("clip", "special"))
	var anim: Animation = null
	if visual_anim_player != null and visual_anim_player.has_animation(clip):
		anim = visual_anim_player.get_animation(clip)
	var playback_speed: float = clip_speed if clip_speed > 0.0 else maxf(_anim_speed_scale, 0.05)
	var clip_time: float = (anim.length if anim else 1.5) / playback_speed
	var windup: float = _strike_windup(config, clip_time)

	_is_special_active = true
	_special_resolved = false
	_cast_elapsed = 0.0
	_cast_strikes.clear()
	_cast_move = {}
	_channel_active = String(config.get("kind", "")) == "consecrate"
	_channel_damage = 0.0
	_channel_broken = false
	_special_windup_timer = windup

	# Lock facing at commit time. The cone and line shapes are dodged by leaving them, so the
	# boss must not keep tracking the target once the telegraph is drawn.
	_cast_target = _commit_target(config)
	_face_now(_cast_target)

	_cast_strikes.append({"cfg": config, "tele": 0.0, "hit": windup})
	var last_hit: float = windup
	var tail: float = _strike_tail(config)
	for followup: Dictionary in config.get("followups", []):
		if not followup.has("tint"):
			followup["tint"] = config.get("tint", Color(1.0, 0.4, 0.1))
		var tele: float = last_hit + tail + float(followup.get("delay", 0.0))
		var hit: float = tele + _strike_windup(followup, 0.0)
		_cast_strikes.append({"cfg": followup, "tele": tele, "hit": hit})
		last_hit = hit
		tail = _strike_tail(followup)

	_cast_end_time = maxf(maxf(clip_time, last_hit + tail + 0.35), min_duration)
	if _channel_active:
		_cast_end_time = windup + 0.15
	_special_total_timer = _cast_end_time

	if is_dying:
		return
	_start_strike(0, clip, playback_speed)


## Seconds from a strike's tell to its hit. A FIXED `windup` for attacks aimed at a spot on
## the ground; otherwise a share of the clip, so a bigger, slower boss winds up longer.
##
## Floored at boss_modifier_min_windup_seconds for every strike, whatever shrank it - a small
## boss's short clip, a Riot speed-up, a quick followup. That floor is the one number this
## whole system is not allowed to push a telegraph below, so "faster" never quietly becomes
## "undodgeable".
func _strike_windup(config: Dictionary, clip_time: float) -> float:
	var windup: float
	if config.has("windup"):
		windup = float(config["windup"])
		if boss_modifier == "Riot":
			windup /= GameSettings.boss_modifier_riot_anim_speed_mult
	else:
		windup = clip_time * clampf(float(config.get("impact_fraction", 0.5)), 0.05, 0.95)
	return maxf(windup, GameSettings.boss_modifier_min_windup_seconds)


## How long a strike keeps the boss busy after it lands - a charge is still running.
func _strike_tail(config: Dictionary) -> float:
	if String(config.get("move", "")) == "charge":
		return float(config.get("dash_time", 0.35))
	return 0.0


## Annihilator's reach bump, onto this cast's own copy: every radius and length, followups
## included. A ring's SAFE middle is deliberately left alone.
func _apply_modifier_reach(config: Dictionary) -> void:
	var mult: float = _boss_modifier_radius_mult()
	if mult == 1.0:
		return
	var parts: Array = [config]
	parts.append_array(config.get("followups", []))
	for part: Dictionary in parts:
		for key: String in ["radius", "length"]:
			if part.has(key):
				part[key] = float(part[key]) * mult


## Who this special is aimed at, chosen once at commit time.
func _commit_target(config: Dictionary) -> Node3D:
	var rule: String = String(config.get("target", "current"))
	if rule == "current":
		return current_target if is_instance_valid(current_target) else null
	if rule == "each_player":
		rule = "nearest_player"
	return _rule_target(rule, float(config.get("min_range", 0.0)), _special_max_range(config))


func _face_now(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to_target: Vector3 = target.global_position - global_position
	if Vector2(to_target.x, to_target.z).length_squared() > 0.01:
		rotation.y = atan2(to_target.x, to_target.z)


## Starts strike `i`: works out where it lands, starts any movement it carries, and puts its
## telegraphs on every screen.
func _start_strike(i: int, clip: String = "", clip_speed: float = 1.0) -> void:
	var strike: Dictionary = _cast_strikes[i]
	strike["started"] = true
	var config: Dictionary = strike["cfg"]
	var yaw: float = rotation.y
	var centers: Array = [global_position]
	var follow: bool = false

	match String(config.get("anchor", "self")):
		"follow":
			follow = true
		"same":
			if i > 0:
				centers = (_cast_strikes[i - 1]["centers"] as Array).duplicate()
				yaw = float(_cast_strikes[i - 1]["yaw"])
		"target":
			centers = _target_centers(config)
			if not centers.is_empty():
				var to_first: Vector3 = (centers[0] as Vector3) - global_position
				if Vector2(to_first.x, to_first.z).length_squared() > 0.01:
					yaw = atan2(to_first.x, to_first.z)
		"retarget":
			var fresh: Node3D = _rule_target(String(config.get("target", "nearest_player")), 0.0, maxf(_special_max_range(config), 20.0))
			_face_now(fresh)
			yaw = rotation.y
			centers = [global_position]
	yaw += deg_to_rad(float(config.get("yaw_offset", 0.0)))

	if String(config.get("kind", "")) == "raise_dead":
		var corpses: Array = _raisable_corpses(config)
		strike["corpses"] = corpses
		centers = []
		for corpse: Node3D in corpses:
			centers.append(corpse.global_position)

	strike["centers"] = centers
	strike["yaw"] = yaw
	strike["follow"] = follow

	match String(config.get("move", "")):
		"leap":
			if not centers.is_empty():
				var travel: Vector3 = (centers[0] as Vector3) - global_position
				travel.y = 0.0
				var flight: float = maxf(float(strike["hit"]) - float(strike["tele"]), 0.05)
				_cast_move = {"mode": "leap", "velocity": travel / flight, "until": float(strike["hit"])}
		"follow":
			_cast_move = {"mode": "follow", "mult": float(config.get("follow_speed_mult", 0.6))}

	if i > 0 and clip == "":
		clip = String(config.get("clip", ""))
		if clip != "":
			clip_speed = _followup_clip_speed(clip, float(strike["hit"]) - float(strike["tele"]))

	_emit_boss_fx({
		"clip": clip,
		"speed": clip_speed,
		"hold": maxf(_cast_end_time - _cast_elapsed, 0.0),
		"telegraphs": _telegraphs_for(strike),
	})


## A followup's own clip, played so its swing roughly meets the hit rather than at the boss's
## ordinary pace - a 0.7 second backswing on a clip that normally takes two would otherwise
## land with the arm still raised.
func _followup_clip_speed(clip: String, windup: float) -> float:
	if visual_anim_player == null or not visual_anim_player.has_animation(clip):
		return _anim_speed_scale
	var anim: Animation = visual_anim_player.get_animation(clip)
	return clampf(anim.length * 0.45 / maxf(windup, 0.05), 0.6, 2.5)


## Where an anchor-"target" strike lands: under its target, or - for each_player - under
## every player in range, plus `extra_random` more beside random ones.
func _target_centers(config: Dictionary) -> Array:
	var centers: Array = []
	if String(config.get("target", "current")) != "each_player":
		if _cast_target != null and is_instance_valid(_cast_target):
			centers.append(_cast_target.global_position)
		return centers
	var pool: Array[Node3D] = _players_in_band(float(config.get("min_range", 0.0)), _special_max_range(config))
	for player: Node3D in pool:
		centers.append(player.global_position)
	if pool.is_empty():
		return centers
	for _n: int in range(int(config.get("extra_random", 0))):
		var near: Node3D = pool[randi() % pool.size()]
		var angle: float = randf() * TAU
		centers.append(near.global_position + Vector3(sin(angle), 0.0, cos(angle)) * randf_range(2.5, 5.0))
	return centers


## The telegraph descriptions for one strike - one per centre, and one per arm of a fan of
## lines or a cross. Plain data, so the same list can travel to every client.
func _telegraphs_for(strike: Dictionary) -> Array:
	var config: Dictionary = strike["cfg"]
	var windup: float = maxf(float(strike["hit"]) - float(strike["tele"]), 0.05)
	var tint: Color = config.get("tint", Color(1.0, 0.4, 0.1))
	var base: Dictionary = {
		"radius": float(config.get("radius", 5.0)),
		"inner_radius": float(config.get("inner_radius", 0.0)),
		"angle": float(config.get("angle", 360.0)),
		"length": float(config.get("length", 5.0)),
		"width": float(config.get("width", 1.0)),
	}
	# [shape, yaw offset, centred]
	var parts: Array = []
	match String(config.get("shape", "circle")):
		"ring":
			parts.append([AttackIndicator.Shape.RING, 0.0, false])
		"cone":
			parts.append([AttackIndicator.Shape.CONE, 0.0, false])
		"line":
			for offset: float in config.get("lines", [0.0]):
				parts.append([AttackIndicator.Shape.LINE, deg_to_rad(offset), false])
		"cross":
			parts.append([AttackIndicator.Shape.LINE, 0.0, true])
			parts.append([AttackIndicator.Shape.LINE, PI * 0.5, true])
		_:
			parts.append([AttackIndicator.Shape.CIRCLE, 0.0, false])

	var telegraphs: Array = []
	for center: Vector3 in strike["centers"]:
		for part: Array in parts:
			var desc: Dictionary = base.duplicate()
			desc["shape"] = int(part[0])
			desc["centered"] = bool(part[2])
			desc["at"] = center
			desc["yaw"] = float(strike["yaw"]) + float(part[1])
			desc["yaw_local"] = float(part[1]) + deg_to_rad(float(config.get("yaw_offset", 0.0)))
			desc["follow"] = bool(strike["follow"])
			desc["windup"] = windup
			desc["tint"] = tint
			# Which pattern the themed style draws, and which world tell (if any) goes with it.
			desc["palette"] = enemy_data.color_identity if enemy_data != null else ""
			if config.has("tell") and not bool(strike["follow"]):
				desc["tell"] = String(config["tell"])
			telegraphs.append(desc)
	return telegraphs


func _process_special(delta: float) -> void:
	_cast_elapsed += delta
	if not _cast_strikes.is_empty():
		_special_windup_timer = maxf(float(_cast_strikes[0]["hit"]) - _cast_elapsed, 0.0)
	_apply_cast_motion(delta)

	if _channel_broken:
		_break_channel()
		return

	for i: int in range(_cast_strikes.size()):
		var strike: Dictionary = _cast_strikes[i]
		if not bool(strike.get("started", false)):
			if _cast_elapsed < float(strike["tele"]):
				break
			_start_strike(i)
		if not bool(strike.get("done", false)) and _cast_elapsed >= float(strike["hit"]):
			if i == 0:
				_resolve_special()
			else:
				_hit_strike(strike)
			# A landed hit can end everything: Reprisal Ward reflects damage straight back, and
			# a fatal reflect runs die() - and with it _cancel_special - inline.
			if not _is_special_active:
				return

	_special_total_timer = maxf(_cast_end_time - _cast_elapsed, 0.0)
	if _cast_elapsed >= _cast_end_time:
		for i: int in range(_cast_strikes.size()):
			if not bool(_cast_strikes[i].get("done", false)):
				if not bool(_cast_strikes[i].get("started", false)):
					_start_strike(i)
				if i == 0:
					_resolve_special()
				else:
					_hit_strike(_cast_strikes[i])
				if not _is_special_active:
					return
		_finish_cast()


## Rooted, unless the special itself moves the boss. These clips carry their own footwork,
## and a danger zone is drawn where the boss stood when it committed.
func _apply_cast_motion(_delta: float) -> void:
	var motion: Vector3 = Vector3.ZERO
	match String(_cast_move.get("mode", "")):
		"leap", "charge":
			if _cast_elapsed < float(_cast_move.get("until", 0.0)):
				motion = _cast_move["velocity"]
		"follow":
			if is_instance_valid(current_target):
				var to_target: Vector3 = current_target.global_position - global_position
				to_target.y = 0.0
				if to_target.length() > 1.0:
					motion = to_target.normalized() * enemy_data.speed * movement_speed_mult() * float(_cast_move.get("mult", 0.6))
					rotation.y = atan2(motion.x, motion.z)
	velocity.x = motion.x
	velocity.z = motion.z
	move_and_slide()


## The main strike landing - also what pays the cooldown. Public in all but name: the tests
## call it directly to land a special without waiting out its windup.
func _resolve_special() -> void:
	_special_resolved = true
	if _special_index >= 0 and _special_index < _special_cooldowns.size():
		_special_cooldowns[_special_index] = _special_cooldown_for(_special_index)
	if _cast_strikes.is_empty():
		return
	_hit_strike(_cast_strikes[0])
	if _cast_is_transition and not is_dying:
		_on_phase_entered()


func _special_cooldown_for(index: int) -> float:
	var config: Dictionary = _specials[index]
	var cooldown: float = float(config.get("cooldown", GameSettings.boss_special_cooldown))
	var by_phase: Dictionary = config.get("cooldown_by_phase", {})
	for phase: int in by_phase:
		if boss_phase >= phase:
			cooldown = float(by_phase[phase])
	if boss_modifier != "":
		cooldown *= _boss_modifier_cooldown_mult(index)
	return cooldown


## One strike landing: whoever is still inside its shape is hit, and everything the strike
## carries - a slow, burning ground, a charge, a heal - happens here.
func _hit_strike(strike: Dictionary) -> void:
	if bool(strike.get("done", false)):
		return
	strike["done"] = true
	var config: Dictionary = strike["cfg"]
	match String(config.get("kind", "")):
		"raise_dead":
			_raise_dead(strike)
			return
		"consecrate":
			_finish_consecration()
			return
	if bool(strike.get("follow", false)):
		# A strike riding on a moving boss lands wherever the boss has got to.
		strike["centers"] = [global_position]
		strike["yaw"] = rotation.y
	var centers: Array = strike["centers"]
	var sound_at: Vector3 = centers[0] if not centers.is_empty() else global_position
	# Sounded from the strike itself rather than from whatever it caught: it makes that noise
	# whether or not anyone was still standing in it.
	NetFx.sound(StringName(config.get("sound", "heavy_landing")), sound_at)

	var damage: float = enemy_data.attack_damage
	damage *= float(config.get("damage_mult", GameSettings.boss_special_damage_mult))
	damage *= GameSettings.get_player_scaling_factor(get_tree())

	var hit_players: Array[Node3D] = []
	for target: Node3D in _targets_in_strike(strike):
		if not target.has_method("take_damage"):
			continue
		target.take_damage(damage, self, true)
		if target.is_in_group("player"):
			hit_players.append(target)
			if float(config.get("slow", 0.0)) > 0.0 and target.has_method("apply_slow"):
				target.apply_slow(float(config["slow"]))
	if is_dying:
		return

	if not hit_players.is_empty():
		var lifelink: float = _phase_lifelink_pct()
		if lifelink > 0.0:
			heal(damage * lifelink * hit_players.size())
		# Lifelink the modifier: a share of the nominal damage back, once per strike rather
		# than once per player it caught - a per-target heal would make this scale up for free
		# against a bigger team, which is not the trade the keyword promises.
		if boss_modifier == "Lifelink":
			heal(damage * GameSettings.boss_modifier_lifelink_pct)

	# The crystal is not in _targets_in_strike - that set is players and myrs, the things that
	# can move out of the way. It is hit here instead, and only by a strike flagged
	# hits_crystal, which is the melee one. Without this a boss stripped of its ordinary swing
	# would walk up to the objective and stand there doing nothing.
	if bool(config.get("hits_crystal", false)) and is_instance_valid(target_crystal):
		var to_crystal: Vector3 = target_crystal.global_position - sound_at
		to_crystal.y = 0.0
		if to_crystal.length() <= float(config.get("radius", 5.0)):
			NetFx.sound(&"blunt_hit", target_crystal.global_position)
			SignalBus.crystal_damaged.emit(
				damage * elite_crystal_damage_multiplier * _crystal_ward_multiplier()
			)

	var hazard: Dictionary = config.get("hazard", {})
	if not hazard.is_empty() and boss_phase >= int(config.get("hazard_from_phase", 1)):
		_spawn_hazards(hazard, centers)

	if String(config.get("move", "")) == "charge":
		# The charge runs the line it telegraphed, after the line has already struck - anyone
		# caught in it was caught at the moment it filled, which is what the tell promised.
		var dash: float = maxf(float(config.get("dash_time", 0.35)), 0.05)
		var direction: Vector3 = _yaw_forward(float(strike["yaw"]))
		_cast_move = {
			"mode": "charge",
			"velocity": direction * float(config.get("length", 10.0)) / dash,
			"until": _cast_elapsed + dash,
		}

	_shake_for_strike(config, sound_at, hit_players)


func _spawn_hazards(hazard: Dictionary, centers: Array) -> void:
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("request_effect"):
		return
	var dps: float = enemy_data.attack_damage * float(hazard.get("dps_mult", 0.0)) * GameSettings.get_player_scaling_factor(get_tree())
	for center: Vector3 in centers:
		main.request_effect({
			"kind": "boss_hazard",
			"position": center,
			"style": String(hazard.get("style", "fire")),
			"radius": float(hazard.get("radius", 2.5)),
			"inner_radius": float(hazard.get("inner_radius", 0.0)),
			"duration": float(hazard.get("duration", 4.0)),
			"dps": dps,
			"slow": float(hazard.get("slow", 0.0)),
		})


## Felt by whoever it hit, hard, and - softer - by anyone it only just missed: a slam this
## size landing next to you should register. Through NetFx, so it is felt on the screen of
## the player it happened to rather than only on the host's.
func _shake_for_strike(config: Dictionary, at: Vector3, hit_players: Array[Node3D]) -> void:
	if not GameSettings.camera_shake_enabled:
		return
	var heavy: float = GameSettings.camera_shake_heavy_strength * GameSettings.camera_shake_strength_mult
	var light: float = GameSettings.camera_shake_light_strength * GameSettings.camera_shake_strength_mult
	for player: Node3D in hit_players:
		NetFx.shake(heavy, GameSettings.camera_shake_heavy_duration, player.global_position, player.get_multiplayer_authority())
	if not hit_players.is_empty():
		return
	var reach: float = maxf(float(config.get("radius", 5.0)), float(config.get("length", 0.0))) * 1.6
	for player: Node3D in _living_players():
		if _flat_distance(at, player.global_position) <= reach:
			NetFx.shake(light, GameSettings.camera_shake_light_duration, player.global_position, player.get_multiplayer_authority())


## Players and myrs inside this strike's shape - the things that could have moved out of it.
func _targets_in_strike(strike: Dictionary) -> Array[Node3D]:
	var results: Array[Node3D] = []
	var config: Dictionary = strike["cfg"]
	var centers: Array = strike["centers"]
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("myrs"))
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		if candidate.is_in_group("player") and "is_downed" in candidate and candidate.is_downed:
			continue
		# A phased myr (Blue's Propaganda stack) is not there to be hit - see Myr.is_targetable.
		if candidate.has_method("is_targetable") and not candidate.is_targetable():
			continue
		for center: Vector3 in centers:
			var offset: Vector3 = (candidate as Node3D).global_position - center
			offset.y = 0.0
			if _offset_in_shape(offset, config, float(strike["yaw"])):
				results.append(candidate as Node3D)
				break
	return results


## Whether a point `offset` from a strike's centre is inside its shape, the shape facing `yaw`.
## The same geometry AttackIndicator draws - what is drawn is exactly what hits.
func _offset_in_shape(offset: Vector3, config: Dictionary, yaw: float) -> bool:
	var dist: float = offset.length()
	var radius: float = float(config.get("radius", 5.0))
	match String(config.get("shape", "circle")):
		"ring":
			return dist <= radius and dist >= float(config.get("inner_radius", 0.0))
		"cone":
			if dist > radius:
				return false
			if dist < 0.01:
				return true
			var half_angle: float = deg_to_rad(float(config.get("angle", 360.0))) * 0.5
			return _yaw_forward(yaw).angle_to(offset.normalized()) <= half_angle
		"line":
			for line_offset: float in config.get("lines", [0.0]):
				if _offset_in_line(offset, yaw + deg_to_rad(line_offset), config, false):
					return true
			return false
		"cross":
			return _offset_in_line(offset, yaw, config, true) or _offset_in_line(offset, yaw + PI * 0.5, config, true)
	return dist <= radius


func _offset_in_line(offset: Vector3, yaw: float, config: Dictionary, centered: bool) -> bool:
	var direction: Vector3 = _yaw_forward(yaw)
	var along: float = offset.dot(direction)
	var across: float = (offset - direction * along).length()
	if across > float(config.get("width", 1.0)) * 0.5:
		return false
	var length: float = float(config.get("length", 5.0))
	if centered:
		return absf(along) <= length * 0.5
	return along >= -0.5 and along <= length


## +Z is forward for these enemies (they turn with atan2(dir.x, dir.z)).
func _yaw_forward(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _living_players() -> Array[Node3D]:
	var players: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		if "is_downed" in player and player.is_downed:
			continue
		players.append(player)
	return players


func _players_in_band(min_range: float, max_range: float) -> Array[Node3D]:
	var band: Array[Node3D] = []
	for player: Node3D in _living_players():
		var dist: float = _flat_distance(global_position, player.global_position)
		if dist >= min_range and dist <= max_range:
			band.append(player)
	return band


## A player chosen by `rule` among those between `min_range` and `max_range`, or null.
func _rule_target(rule: String, min_range: float, max_range: float) -> Node3D:
	var pool: Array[Node3D] = _players_in_band(min_range, max_range)
	if pool.is_empty():
		return null
	if rule == "random_player":
		return pool[randi() % pool.size()]
	var best: Node3D = null
	var best_score: float = INF
	for player: Node3D in pool:
		var score: float = _flat_distance(global_position, player.global_position)
		match rule:
			"farthest_player":
				score = -score
			"weakest_player":
				score = _health_ratio_of(player)
		if score < best_score:
			best_score = score
			best = player
	return best


func _health_ratio_of(player: Node3D) -> float:
	if "hp" in player and "max_hp" in player and float(player.max_hp) > 0.0:
		return float(player.hp) / float(player.max_hp)
	return 1.0


## Everything a strike is over: rooted again, and - if the special carries one - open to
## punishment for a moment.
func _finish_cast() -> void:
	var config: Dictionary = _special_config
	var was_transition: bool = _cast_is_transition
	_is_special_active = false
	_cast_move = {}
	_cast_is_transition = false
	_channel_active = false
	if not was_transition and String(config.get("kind", "")) != "consecrate":
		_begin_exhaust(config.get("exhaust", {}))
	update_path(true)


## The punish window: rooted, reeling, and taking `mult` times damage for `time` seconds.
## Every boss earns its own - surviving the Unbound Whirlwind, the Absolute Zero combo, a
## leap that sticks it in the ground, a broken Consecration, the end of the Hunt.
func _begin_exhaust(spec: Dictionary) -> void:
	var duration: float = float(spec.get("time", 0.0))
	if duration <= 0.0 or is_dying:
		return
	_exhausted_timer = duration
	_exhausted_mult = float(spec.get("mult", 1.5))
	var clip: String = _reaction_clip
	var speed: float = _anim_speed_scale
	if clip != "" and visual_anim_player != null:
		var anim: Animation = visual_anim_player.get_animation(clip)
		if anim != null:
			speed = clampf(anim.length / duration, 0.2, 2.0)
	_emit_boss_fx({"clip": clip, "speed": speed, "hold": duration, "telegraphs": []})
	NetFx.damage_number(_label_point(), 0.0, Color(1.0, 0.85, 0.3), "EXPOSED")


func _label_point() -> Vector3:
	return global_position + Vector3(0.0, 1.7 * scale.y + 0.4, 0.0)


# --- Regeneration ------------------------------------------------------------------------

## A boss nobody is fighting heals. Hitting it once and walking off to farm used to cost the
## team nothing - the damage stayed done and the fight could be finished whenever suited.
## Now, boss_regen_delay seconds after the last hit of any kind, it starts healing
## boss_regen_pct_per_second of its maximum health until someone engages it again.
##
## Any damage counts as engaging, burns and zones included: what this punishes is leaving,
## not the choice of how to fight. Phases stay one-way - healing back over a threshold does
## not undo the phase it already reached.
func _tick_boss_regen(delta: float) -> void:
	if is_dying or enemy_data == null:
		boss_regenerating = false
		return
	_since_boss_hit += delta
	var healing: bool = _since_boss_hit >= GameSettings.boss_regen_delay and health < enemy_data.health
	if healing and not boss_regenerating:
		NetFx.damage_number(_label_point(), 0.0, Color(0.45, 1.0, 0.55), "REGENERATING")
	boss_regenerating = healing
	if healing:
		heal(enemy_data.health * GameSettings.boss_regen_pct_per_second * delta, false)


# --- Phases ------------------------------------------------------------------------------

## The health shares at which this boss enters phase 2 and phase 3. Public for the HUD's
## boss bar, which marks them.
func phase_thresholds() -> Array[float]:
	return _phase_thresholds()


## What the boss bar calls this boss, and the phase it is in.
func boss_display_name() -> String:
	return String(_phase_config.get("name", "BOSS"))


func phase_title() -> String:
	return String((_phase_config.get("titles", {}) as Dictionary).get(boss_phase, ""))


## The boss's own colour, as its shockwave and phase banner use it.
func boss_tint() -> Color:
	return (_phase_config.get("shockwave", {}) as Dictionary).get("tint", Color(1.0, 0.85, 0.4))


func _phase_thresholds() -> Array[float]:
	if boss_modifier == "Enrage":
		return [GameSettings.boss_modifier_enrage_phase2_threshold, GameSettings.boss_modifier_enrage_health_threshold]
	return [GameSettings.boss_phase2_threshold, GameSettings.boss_phase3_threshold]


## Called from take_damage right after health drops, rather than polled every frame, since
## that is the one moment the answer can change. One-way, like a squad breaking ranks:
## flickering in and out at a threshold would read as a bug, not a mechanic.
func _check_boss_phase() -> void:
	if not is_boss() or enemy_data == null or health <= 0.0:
		return
	var thresholds: Array[float] = _phase_thresholds()
	var ratio: float = health / maxf(enemy_data.health, 0.001)
	var reached: int = 1
	if ratio <= thresholds[1]:
		reached = 3
	elif ratio <= thresholds[0]:
		reached = 2
	if reached <= boss_phase:
		return
	var previous: int = boss_phase
	boss_phase = reached
	_pending_phase_transition = true
	# What this phase brings in is ready soon after the transition, so the new phase announces
	# itself with its new attack.
	for i: int in range(_specials.size()):
		var config: Dictionary = _specials[i]
		if BossDatabase.special_in_phase(config, boss_phase) and not BossDatabase.special_in_phase(config, previous):
			_special_cooldowns[i] = GameSettings.boss_phase_special_delay
	if boss_modifier == "Enrage" and boss_phase >= 3 and not _enrage_active:
		_enrage_active = true
		enemy_data.attack_damage *= GameSettings.boss_modifier_enrage_damage_mult


## The transition itself: the boss stops, roars, and lets out a telegraphed shockwave. Waits
## for any special already in flight - see the caller in _physics_process.
func _begin_phase_transition() -> void:
	_pending_phase_transition = false
	var shockwave: Dictionary = _phase_config.get("shockwave", {})
	var config: Dictionary = {
		"display_name": String(shockwave.get("display_name", "Shockwave")),
		"clip": _reaction_clip if _reaction_clip != "" else "special",
		"shape": "circle",
		"radius": GameSettings.boss_phase_shockwave_radius,
		"windup": GameSettings.boss_phase_shockwave_windup,
		"damage_mult": GameSettings.boss_phase_shockwave_damage_mult,
		"tint": shockwave.get("tint", Color(1.0, 1.0, 1.0)),
	}
	var clip_speed: float = -1.0
	if visual_anim_player != null and visual_anim_player.has_animation(String(config["clip"])):
		clip_speed = visual_anim_player.get_animation(String(config["clip"])).length / GameSettings.boss_phase_transition_seconds
	_announce_phase()
	if enemy_data != null:
		NetFx.sound(StringName("boss_spawn_" + enemy_data.color_identity.to_lower()), global_position)
	_start_cast(config, -1, GameSettings.boss_phase_transition_seconds, clip_speed)
	_cast_is_transition = true


## What a phase brings with it beyond its specials. Runs as the shockwave lands.
func _on_phase_entered() -> void:
	var sapling_phase: int = int(_phase_config.get("saplings_on_phase", 0))
	if sapling_phase > 0 and boss_phase >= sapling_phase and not _saplings_grown:
		_grow_saplings()


func _announce_phase() -> void:
	var titles: Dictionary = _phase_config.get("titles", {})
	var title: String = String(titles.get(boss_phase, ""))
	if title == "":
		return
	var message: String = "%s  -  %s" % [String(_phase_config.get("name", "BOSS")), title]
	var tint: Color = (_phase_config.get("shockwave", {}) as Dictionary).get("tint", Color(1.0, 0.85, 0.4))
	_show_phase_banner(message, tint)
	if Net.is_active() and Net.is_server():
		_net_phase_banner.rpc(message, tint)


@rpc("authority", "call_remote", "reliable")
func _net_phase_banner(message: String, tint: Color) -> void:
	_show_phase_banner(message, tint)


func _show_phase_banner(message: String, tint: Color) -> void:
	SignalBus.lane_warning_requested.emit("", message, tint)
	# Runs on every peer (the banner RPC brings it there), and the fog is per viewer anyway.
	var surge: Dictionary = _phase_config.get("fog_surge", {})
	if surge.is_empty() or enemy_data == null:
		return
	var scene: Node = get_tree().current_scene
	var atmosphere: Node = scene.find_child("BiomeAtmosphere", true, false) if scene != null else null
	if atmosphere != null and atmosphere.has_method("surge"):
		atmosphere.surge(enemy_data.color_identity, float(surge.get("mult", 1.8)), float(surge.get("seconds", 6.0)))


func _phase_lifelink_pct() -> float:
	var lifelink: Dictionary = _phase_config.get("lifelink", {})
	if lifelink.is_empty() or boss_phase < int(lifelink.get("from_phase", 99)):
		return 0.0
	return float(lifelink.get("pct", 0.0))


## Everything that changes what a hit on a boss is worth: open while exhausted, and - for the
## paladin from phase 2 - turned aside by a shield from the front.
func _boss_incoming_damage(amount: float, source: Node3D) -> float:
	if _exhausted_timer > 0.0:
		return amount * _exhausted_mult
	if _shield_wall_faces(source):
		var now: int = Time.get_ticks_msec()
		if now >= _shield_feedback_ready_msec:
			# Said once a second at most - the number itself already shows the reduction.
			_shield_feedback_ready_msec = now + 1000
			NetFx.damage_number(_label_point(), 0.0, Color(0.85, 0.9, 1.0), "Shielded")
		return amount * (1.0 - GameSettings.boss_shield_wall_reduction)
	return amount


func _shield_wall_faces(source: Node3D) -> bool:
	var from_phase: int = int(_phase_config.get("shield_wall_from_phase", 0))
	if from_phase <= 0 or boss_phase < from_phase:
		return false
	if source == null or not is_instance_valid(source) or source == self:
		return false
	var to_source: Vector3 = source.global_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.01:
		return false
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	return rad_to_deg(forward.normalized().angle_to(to_source.normalized())) <= GameSettings.boss_shield_wall_arc_degrees * 0.5


# --- Green: saplings ---------------------------------------------------------------------

func _grow_saplings() -> void:
	_saplings_grown = true
	if not Net.is_server():
		return
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("request_enemy"):
		return
	var wave_manager: Node = main.get_node_or_null("WaveManager")
	var count: int = GameSettings.boss_sapling_count
	for i: int in range(count):
		var angle: float = rotation.y + TAU * float(i) / float(maxi(count, 1))
		var spot: Vector3 = global_position + Vector3(sin(angle), 0.0, cos(angle)) * GameSettings.boss_sapling_ring_radius
		var sapling: Node3D = main.request_enemy({
			"position": (main as Node3D).to_local(spot),
			"color": "Green",
			"type": "Melee",
			"sapling": true,
		})
		if sapling == null:
			continue
		sapling.set("sapling_boss", self)
		if wave_manager:
			wave_manager.register_enemy()


## A sapling left standing long enough feeds its treant and withers. Withers rather than dies:
## the team is not paid for a sapling it did NOT kill.
func _wither_sapling() -> void:
	if is_instance_valid(sapling_boss) and not sapling_boss.is_dying and sapling_boss.enemy_data != null:
		sapling_boss.heal(sapling_boss.enemy_data.health * GameSettings.boss_sapling_heal_pct)
	_skip_kill_rewards = true
	die()


# --- Black: raise dead -------------------------------------------------------------------

func _raisable_corpses(config: Dictionary) -> Array:
	var radius: float = float(config.get("raise_radius", 12.0))
	var found: Array = []
	for corpse: EnemyBase in EnemyBase.corpses():
		if corpse == self or corpse.is_boss():
			continue
		if _flat_distance(global_position, corpse.global_position) <= radius:
			found.append(corpse)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat_distance(global_position, a.global_position) < _flat_distance(global_position, b.global_position))
	return found.slice(0, int(config.get("raise_count", 4)))


func _raise_dead(strike: Dictionary) -> void:
	if not Net.is_server():
		return
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("request_enemy"):
		return
	var wave_manager: Node = main.get_node_or_null("WaveManager")
	for corpse: Node3D in strike.get("corpses", []):
		if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
			continue
		var spot: Vector3 = corpse.global_position
		EnemyBase.consume_corpse(corpse as EnemyBase)
		NetFx.sound(&"spell_zombify", spot)
		var raised: Node3D = main.request_enemy({
			"position": (main as Node3D).to_local(spot),
			"color": "Black",
			"type": "Melee",
		})
		if raised == null:
			continue
		if raised.get("enemy_data") != null:
			raised.health = raised.enemy_data.health * GameSettings.boss_raise_dead_health_mult
			if raised.health_bar:
				raised.health_bar.set_health(raised.health, raised.enemy_data.health)
		if wave_manager:
			wave_manager.register_enemy()


# --- White: consecration -----------------------------------------------------------------

func _finish_consecration() -> void:
	_channel_active = false
	if enemy_data == null or is_dying:
		return
	heal(enemy_data.health * float(_special_config.get("heal_pct", 0.15)))
	NetFx.sound(&"aura_orb_heal", global_position)


## The team hit hard enough while he knelt: the heal is lost and he is left open.
func _break_channel() -> void:
	var config: Dictionary = _special_config
	if _special_index >= 0 and _special_index < _special_cooldowns.size():
		_special_cooldowns[_special_index] = _special_cooldown_for(_special_index)
	_cancel_special()
	NetFx.damage_number(_label_point(), 0.0, Color(1.0, 0.9, 0.5), "INTERRUPTED")
	_begin_exhaust(config.get("exhaust", {}))


# --- Showing it on every screen ------------------------------------------------------------

## Shows a boss's clip and telegraphs here and on every client. The AI only runs on the
## server, so without the second half a client saw the boss stand still and then took a hit
## it was never shown.
func _emit_boss_fx(payload: Dictionary) -> void:
	_show_boss_fx(payload)
	if Net.is_active() and Net.is_server():
		_net_boss_fx.rpc(payload)


@rpc("authority", "call_remote", "reliable")
func _net_boss_fx(payload: Dictionary) -> void:
	_show_boss_fx(payload)


func _show_boss_fx(payload: Dictionary) -> void:
	var clip: String = String(payload.get("clip", ""))
	if clip != "" and not is_dying and visual_anim_player != null and visual_anim_player.has_animation(clip):
		visual_anim_player.play(clip, -1, maxf(float(payload.get("speed", 1.0)), 0.05))
	# A client's copy would otherwise go straight back to walk-or-stand from the replicated
	# velocity on its next frame and throw the clip away.
	_puppet_hold_timer = maxf(_puppet_hold_timer, float(payload.get("hold", 0.0)))
	for desc: Dictionary in payload.get("telegraphs", []):
		_spawn_telegraph(desc)


func _spawn_telegraph(desc: Dictionary) -> void:
	# The world tell first, and whatever the indicator setting says: it is not a HUD element,
	# it is the meteor itself - turning the ground decals off must not take it with them.
	var tell: BossTell = BossTell.spawn(get_tree().current_scene, desc)
	if tell != null:
		for i: int in range(_cast_tells.size() - 1, -1, -1):
			if not is_instance_valid(_cast_tells[i]):
				_cast_tells.remove_at(i)
		_cast_tells.append(tell)
	var windup: float = float(desc.get("windup", 1.0))
	var tint: Color = desc.get("tint", Color(1.0, 0.4, 0.1))
	var indicator: AttackIndicator = null
	if bool(desc.get("follow", false)):
		indicator = AttackIndicator.spawn_shape(self, desc, windup, tint, maxf(scale.y, 0.01), true)
		if indicator != null:
			indicator.rotation.y = float(desc.get("yaw_local", 0.0))
	else:
		indicator = AttackIndicator.spawn_world(get_tree().current_scene, desc.get("at", global_position), float(desc.get("yaw", 0.0)), desc, windup, tint)
	if indicator == null:
		return
	# Resolved telegraphs free themselves; drop them here so the list only ever holds live ones.
	for i: int in range(_cast_indicators.size() - 1, -1, -1):
		if not is_instance_valid(_cast_indicators[i]):
			_cast_indicators.remove_at(i)
	_cast_indicators.append(indicator)


@rpc("authority", "call_remote", "reliable")
func _net_boss_cancel() -> void:
	_cancel_local_fx()


func _cancel_local_fx() -> void:
	for indicator: AttackIndicator in _cast_indicators:
		if is_instance_valid(indicator):
			indicator.cancel()
	_cast_indicators.clear()
	for tell: BossTell in _cast_tells:
		if is_instance_valid(tell):
			tell.queue_free()
	_cast_tells.clear()
	_puppet_hold_timer = 0.0


## Physics-space sphere query around this enemy, filtered by collision layer
## (e.g. 4 = "Enemies"). Broadphase-accelerated, unlike looping every node in
## a group - use this instead for AoE effects that scale with wave size.
func _bodies_in_range(radius: float, mask: int) -> Array[Node3D]:
	var results: Array[Node3D] = []
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result: Dictionary in space_state.intersect_shape(query, 64):
		var collider: Object = result.get("collider")
		if collider is Node3D and is_instance_valid(collider):
			results.append(collider as Node3D)
	return results

## Heavy shakes are boss specials landing on the player; light ones are the boss's
## ordinary swing, or a special that just missed.
func _request_camera_shake(is_heavy: bool) -> void:
	if not GameSettings.camera_shake_enabled:
		return
	var strength: float = GameSettings.camera_shake_heavy_strength if is_heavy else GameSettings.camera_shake_light_strength
	var duration: float = GameSettings.camera_shake_heavy_duration if is_heavy else GameSettings.camera_shake_light_duration
	SignalBus.camera_shake_requested.emit(strength * GameSettings.camera_shake_strength_mult, duration)

## Dying, being exiled or having a Consecration broken mid-special drops every telegraph
## without dealing its damage.
func _cancel_special() -> void:
	var had_fx: bool = _is_special_active or not _cast_indicators.is_empty() or not _cast_tells.is_empty()
	_cancel_local_fx()
	if had_fx and Net.is_active() and Net.is_server():
		_net_boss_cancel.rpc()
	_is_special_active = false
	_cast_strikes.clear()
	_cast_move = {}
	_channel_active = false
	_channel_broken = false
	_cast_is_transition = false

# ============================================================
# MINIBOSS SPECIAL (Mage only, telegraphed and dodgeable)
#
# One special, on its own long cooldown, running entirely alongside the ordinary cast loop
# in perform_mage_spell() rather than replacing it - a miniboss keeps throwing its normal
# spell on schedule, and the special is purely a periodic, more dramatic extra. See
# apply_miniboss() for how a Mage gets flagged into this at all.
# ============================================================

## Starts the windup: draws the ground telegraph and roots the caster until it resolves.
## The radius is exactly what the special will reach - see _miniboss_special_radius - the
## same discipline boss specials already keep between what is drawn and what actually hits.
func _begin_miniboss_special() -> void:
	if damage_suppress_timer > 0.0:
		# Fog silences this the same way it silences the ordinary cast (see
		# perform_mage_spell) - still pays the cooldown, so a silenced special does not
		# simply retry next frame.
		_report_fog_prevented(0.0)
		_miniboss_special_timer = enemy_data.attack_speed * GameSettings.wave_miniboss_special_cooldown_mult
		return

	_miniboss_special_windup = GameSettings.wave_miniboss_special_windup
	_miniboss_special_indicator = AttackIndicator.spawn(
		self,
		AttackIndicator.Shape.CIRCLE,
		_miniboss_special_radius(),
		360.0,
		_miniboss_special_windup,
		enemy_data.visual_color,
		enemy_data.model_scale
	)

func _process_miniboss_special(delta: float) -> void:
	# Rooted for the whole windup, same reasoning as a boss special: the indicator is drawn
	# where the mage stood when it committed, and a mage that kept walking would drag the
	# danger zone somewhere the player never actually saw telegraphed.
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	_miniboss_special_windup -= delta
	if _miniboss_special_windup <= 0.0:
		_resolve_miniboss_special()

## Reuses the SAME per-colour range perform_mage_spell() already casts at, scaled up by
## wave_miniboss_special_power_mult. Black has no range of its own to scale - its ordinary
## cast raises something at its own feet rather than reaching out - so the indicator
## borrows Green's footprint as a sane default size for the telegraph.
func _miniboss_special_radius() -> float:
	var base_range: float = GameSettings.enemy_white_mage_range
	match enemy_data.color_identity:
		"Red": base_range = GameSettings.enemy_red_mage_range
		"Blue": base_range = GameSettings.enemy_blue_mage_range
		"Green": base_range = GameSettings.enemy_green_mage_range
		"Black": base_range = GameSettings.enemy_green_mage_range
	return base_range * GameSettings.wave_miniboss_special_power_mult

## The payoff: a bigger version of the SAME effect this colour's ordinary cast already
## throws (see perform_mage_spell), never a new mechanic per colour - just the signature
## spell turned up. Red and Blue additionally reach every player in range rather than only
## the first one found the way the ordinary single-target cast does - a telegraphed special
## a second player could simply stand next to and ignore would not read as a threat to them
## at all.
func _resolve_miniboss_special() -> void:
	_miniboss_special_windup = -1.0
	if _miniboss_special_indicator and is_instance_valid(_miniboss_special_indicator):
		_miniboss_special_indicator.resolve()
	_miniboss_special_indicator = null
	_miniboss_special_timer = enemy_data.attack_speed * GameSettings.wave_miniboss_special_cooldown_mult

	if is_dying or enemy_data == null:
		return

	var power: float = GameSettings.wave_miniboss_special_power_mult
	var radius: float = _miniboss_special_radius()

	match enemy_data.color_identity:
		"White":
			for e: Node3D in _bodies_in_range(radius, 4):
				if e.has_method("heal"):
					e.heal(GameSettings.enemy_white_mage_heal * power)
		"Red":
			var scaled_damage: float = enemy_data.attack_damage * power * GameSettings.get_player_scaling_factor(get_tree())
			for player: Node3D in get_tree().get_nodes_in_group("player"):
				if is_instance_valid(player) and global_position.distance_to(player.global_position) < radius and player.has_method("take_damage"):
					player.take_damage(scaled_damage, self)
		"Blue":
			for player: Node3D in get_tree().get_nodes_in_group("player"):
				if is_instance_valid(player) and global_position.distance_to(player.global_position) < radius and player.has_method("apply_slow"):
					player.apply_slow(GameSettings.enemy_blue_mage_slow_duration * power)
		"Black":
			# The signature raise, upgraded from a lone weak melee to a real Ranged unit -
			# a body that can actually threaten the crystal from where it lands, rather
			# than one more goblin walking in from the back of the fight.
			_raise_revived_enemy("Ranged", power)
		"Green":
			# Every ally in range rather than breaking on the first - the ordinary cast is
			# one Giant Growth, the special is a whole rally.
			for e: Node3D in get_tree().get_nodes_in_group("enemies"):
				if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) < radius:
					if e.has_method("apply_green_mage_buff"):
						e.apply_green_mage_buff()

## Dying or being exiled mid-windup drops the telegraph without resolving it - the same
## treatment a boss special gets from _cancel_special(), called alongside this one from
## die() and exile().
func _cancel_miniboss_special() -> void:
	if _miniboss_special_indicator and is_instance_valid(_miniboss_special_indicator):
		_miniboss_special_indicator.cancel()
	_miniboss_special_indicator = null
	_miniboss_special_windup = -1.0

func perform_attack() -> void:
	if not is_instance_valid(current_target):
		evaluate_target()
		return
		
	# Propaganda, the blue enchantment: every enemy attacks and casts more slowly. A
	# multiplier above 1 lengthens the gap between swings.
	attack_cooldown = enemy_data.attack_speed * RunState.enemy_attack_speed_multiplier()

	# Apply frost slow if active
	if frost_slow_timer > 0:
		attack_cooldown /= GameSettings.enemy_frost_slow_mult # Slower attacks when frosted

	# Every class now has a real "attack" clip (Ranged/Mage previously fired with
	# no visual windup at all - their models only got real animations recently).
	var impact_ratio: float = 0.5
	if visual_anim_player and visual_anim_player.has_animation("attack"):
		# Match the swing's playback speed to the actual attack cadence so it always
		# finishes exactly as the next attack fires, instead of restarting mid-swing.
		var attack_anim: Animation = visual_anim_player.get_animation("attack")
		var speed_scale: float = attack_anim.length / attack_cooldown if attack_cooldown > 0.0 else 1.0
		# Played directly rather than through _play_visual_animation: that helper skips a clip
		# already running, and a swing has to RESTART on every attack even when the previous
		# one has not quite finished. Only the is_dying guard is borrowed from it.
		if not is_dying:
			visual_anim_player.play("attack", -1, speed_scale)
		impact_ratio = float(attack_anim.get_meta("hit_ratio", 0.5))

	# A shooter's noise is its release, which happens partway into the clip; everyone
	# else is swinging something, and that is heard now whether or not it connects.
	if not _is_shooter():
		SoundBank.play_at(&"blunt_swing", global_position)

	# Nothing lands yet. The swing is stretched to fill exactly one attack cooldown,
	# so the measured fraction converts straight into seconds from here, and what the
	# swing commits to is settled in _resolve_attack_impact.
	_impact_timer = maxf(impact_ratio * attack_cooldown, 0.01)


## The frame the swing in flight connects on. What that means depends on the class:
## a shooter releases its projectile, everyone else lands - or misses - a hit.
##
## Re-checking the target here rather than trusting the one picked when the swing
## started is the point of moving the payout. The enemy is rooted for the whole
## swing (see the is_attack_swing_playing guard in _physics_process), so a target
## that walks out of reach during the wind-up now escapes the hit instead of being
## struck from across the gap; GameSettings.enemy_attack_impact_range_grace is the
## forgiveness on that.
func _resolve_attack_impact() -> void:
	if is_dying or enemy_data == null:
		return

	if _is_shooter():
		if not is_instance_valid(current_target):
			return
		SoundBank.play_at(&"arrow_shot", global_position)
		fire_projectile()
		return

	var reach: float = enemy_data.attack_range * GameSettings.enemy_attack_impact_range_grace
	if not is_instance_valid(current_target) or global_position.distance_to(current_target.global_position) > reach:
		# Missed. The swing through the air was already heard when it started, and
		# nothing arrives after it.
		return

	if damage_suppress_timer > 0.0:
		# Standing in Fog. The swing plays out and connects with nothing.
		_report_fog_prevented(max(0.0, enemy_data.attack_damage - damage_penalty)
			* GameSettings.get_player_scaling_factor(get_tree()))
		return
	var actual_damage: float = max(0.0, enemy_data.attack_damage - damage_penalty)
	if current_target == target_crystal:
		actual_damage *= elite_crystal_damage_multiplier
	actual_damage *= GameSettings.get_player_scaling_factor(get_tree())

	# The crystal has no take_damage() of its own - it is hit through the bus - but a
	# weapon landing on it still sounds like a weapon landing.
	if current_target == target_crystal:
		SoundBank.play_at(&"blunt_hit", current_target.global_position)
		SignalBus.crystal_damaged.emit(actual_damage * _crystal_ward_multiplier())
		return

	if current_target.has_method("take_damage"):
		SoundBank.play_at(&"blunt_hit", current_target.global_position)
		current_target.take_damage(actual_damage, self, true)
		if enemy_data.enemy_class == "Boss" and current_target.is_in_group("player"):
			_request_camera_shake(false)


## Sphere of Safety, the white enchantment: an enemy standing inside the ward hurts
## the crystal less. Radius grows per stack, so late stacks also protect the approach
## rather than only the last step of it.
func _crystal_ward_multiplier() -> float:
	var reduction: float = RunState.crystal_damage_reduction()
	if reduction <= 0.0 or not is_instance_valid(target_crystal):
		return 1.0
	var ward: float = GameSettings.player_base_proximity + RunState.crystal_ward_radius()
	if global_position.distance_to(target_crystal.global_position) > ward:
		return 1.0
	return 1.0 - reduction


func fire_projectile() -> void:
	if damage_suppress_timer > 0.0:
		# Fog: the bow is drawn and nothing leaves it.
		_report_fog_prevented(max(0.0, enemy_data.attack_damage - damage_penalty)
			* GameSettings.get_player_scaling_factor(get_tree()))
		return
	# Add a little height so it shoots from chest/head level
	var start_pos = global_position + Vector3(0, 1.2, 0)
	var target_pos = current_target.global_position
	if current_target == target_crystal:
		target_pos += Vector3(0, 2.0, 0) # Aim at crystal center
	elif current_target.is_in_group("player") or current_target.is_in_group("myrs"):
		target_pos += Vector3(0, 1.0, 0) # Aim at player chest
	
	var dir = (target_pos - start_pos).normalized()
	
	var actual_damage = max(0.0, enemy_data.attack_damage - damage_penalty)
	if current_target == target_crystal:
		actual_damage *= elite_crystal_damage_multiplier
	actual_damage *= GameSettings.get_player_scaling_factor(get_tree())
	
	ProjectilePool.fire(start_pos, dir, 3, true, 1.0, actual_damage, 0.0, self, _enemy_projectile_visual_kind(), _enemy_projectile_tint())


func _enemy_projectile_visual_kind() -> String:
	if enemy_data == null or enemy_data.enemy_class != "Ranged":
		return "magic"
	match enemy_data.color_identity:
		"White", "Blue", "Green":
			return "arrow"
		"Black", "Red":
			return "stone"
	return "arrow"


func _enemy_projectile_tint() -> Color:
	if enemy_data == null:
		return Color(0.8, 0.2, 0.8)
	match enemy_data.color_identity:
		"White": return Color(1.0, 0.96, 0.72)
		"Blue": return Color(0.35, 0.68, 1.0)
		"Black": return Color(0.58, 0.24, 0.72)
		"Red": return Color(1.0, 0.25, 0.14)
		"Green": return Color(0.25, 0.9, 0.36)
	return enemy_data.visual_color

func perform_mage_spell() -> void:
	if damage_suppress_timer > 0.0:
		# Fog silences the casters too, not only the ones that swing. A mage's spell has no
		# single damage number to report, so this one only says that it was stopped.
		_report_fog_prevented(0.0)
		return
	match enemy_data.color_identity:
		"White":
			# AoE Heal - a physics broadphase query instead of scanning every
			# enemy in the level, so this doesn't scale with wave size.
			for e: Node3D in _bodies_in_range(GameSettings.enemy_white_mage_range, 4):
				if e.has_method("heal"):
					e.heal(GameSettings.enemy_white_mage_heal)
		"Red":
			# Damagedealer (Fireball at player)
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < GameSettings.enemy_red_mage_range:
				if players[0].has_method("take_damage"):
					var scaled_damage = enemy_data.attack_damage * GameSettings.get_player_scaling_factor(get_tree())
					players[0].take_damage(scaled_damage, self)
		"Blue":
			# Slows player
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and global_position.distance_to(players[0].global_position) < GameSettings.enemy_blue_mage_range:
				if players[0].has_method("apply_slow"):
					players[0].apply_slow(GameSettings.enemy_blue_mage_slow_duration)
		"Black":
			# Revive weak enemy
			# Just spawn a new weak melee of the same color
			_raise_revived_enemy("Melee", 1.0)
		"Green":
			# Buff enemy (Giant Growth)
			var enemies = get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) < GameSettings.enemy_green_mage_range:
					if e.has_method("apply_green_mage_buff") and e.apply_green_mage_buff():
						break

func apply_green_mage_buff() -> bool:
	if has_green_mage_buff or not enemy_data:
		return false
	has_green_mage_buff = true
	scale *= GameSettings.enemy_green_mage_buff_scale
	enemy_data.attack_damage *= GameSettings.enemy_green_mage_buff_damage
	return true

func heal(amount: float, show_damage_number: bool = true) -> void:
	if enemy_data:
		health = min(enemy_data.health, health + amount)
		if health_bar:
			health_bar.set_health(health, enemy_data.health)
		if show_damage_number:
			var spawn_pos = global_position + Vector3(0, 1.8, 0)
			NetFx.damage_number(spawn_pos, -amount, Color(0.2, 1.0, 0.4), "")

func apply_elite_modifier(modifier: String) -> void:
	elite_modifier = modifier
	match elite_modifier:
		"Haste":
			enemy_data.speed *= GameSettings.enemy_elite_haste_speed_mult
			enemy_data.attack_speed *= GameSettings.enemy_elite_haste_attack_speed_mult
		"Regenerator":
			enemy_data.health *= GameSettings.enemy_elite_regenerator_health_mult
			elite_regeneration_per_second = enemy_data.health * GameSettings.enemy_elite_regenerator_heal_pct_per_second
		"Juggernaut":
			enemy_data.health *= GameSettings.enemy_elite_juggernaut_health_mult
			enemy_data.attack_damage *= GameSettings.enemy_elite_juggernaut_damage_mult
			enemy_data.speed *= GameSettings.enemy_elite_juggernaut_speed_mult
		"Crystal Hunter":
			elite_crystal_damage_multiplier = GameSettings.enemy_elite_crystal_hunter_damage_mult

	health = enemy_data.health
	if health_bar:
		health_bar.set_health(health, enemy_data.health)

## The step up from Elite: bigger, tankier, harder-hitting, and visibly so - see
## GameSettings' Minibosses block for every multiplier. Runs at the very end of setup(), same
## as apply_elite_modifier, so it reapplies scale/health/health_bar on top of whatever the
## rest of setup() already put there rather than needing setup() itself restructured.
##
## Only a Mage gets a special (see _perform_miniboss_special) - a Melee or Ranged miniboss
## is simply a stat-scaled version of the ordinary attack it already throws, same swing,
## same bow, nothing new to build for those two classes.
func apply_miniboss() -> void:
	is_miniboss = true
	enemy_data.health *= GameSettings.wave_miniboss_health_mult
	enemy_data.attack_damage *= GameSettings.wave_miniboss_damage_mult
	enemy_data.speed *= GameSettings.wave_miniboss_speed_mult
	enemy_data.model_scale *= GameSettings.wave_miniboss_scale_mult
	enemy_data.display_name = "Miniboss " + enemy_data.display_name

	health = enemy_data.health
	if health_bar:
		health_bar.set_health(health, enemy_data.health)
	scale = Vector3(enemy_data.model_scale, enemy_data.model_scale, enemy_data.model_scale)
	aggro_area.scale = Vector3.ONE / maxf(enemy_data.model_scale, 0.01)

	_apply_miniboss_glow()

	if enemy_data.enemy_class == "Mage":
		# Its own long cooldown, ON TOP of the ordinary cast loop in perform_mage_spell() -
		# the special is the payoff for finding a mage miniboss, not a replacement for its
		# normal casting.
		_miniboss_special_timer = enemy_data.attack_speed * GameSettings.wave_miniboss_special_cooldown_mult

## The size and health bump alone are easy to miss across a battlefield full of goblins -
## the glow is what actually catches the eye from across the lane, in the enemy's own lane
## colour (see EnemyDatabase.get_enemy_data's visual_color per colour).
##
## Layered on as a NEXT_PASS on a DUPLICATE of the mesh's own material, never as
## material_override: the base material is a shared resource used by every ordinary enemy
## wearing this same model, and touching it in place would glow every goblin in the game,
## not just this one.
func _apply_miniboss_glow() -> void:
	var glow_material := ShaderMaterial.new()
	glow_material.shader = _miniboss_glow_shader
	glow_material.set_shader_parameter("glow_color", enemy_data.visual_color)

	# find_child by name rather than a stored reference: the visual was added a few lines
	# up in setup(), by name "Skeleton3D" for a real model or the CSGBox3D fallback's own
	# default node name otherwise - the same trick _ground_visual already relies on for the
	# skeleton lookup.
	var skeleton: Skeleton3D = find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		for child: Node in skeleton.get_children():
			if not (child is MeshInstance3D):
				continue
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			for surface: int in range(mesh_instance.get_surface_override_material_count()):
				var base_material: Material = mesh_instance.get_active_material(surface)
				if base_material == null:
					continue
				var duplicated_material: Material = base_material.duplicate()
				duplicated_material.next_pass = glow_material
				mesh_instance.set_surface_override_material(surface, duplicated_material)
			return

	# No skinned model - the CSGBox3D fallback used when a colour/class has no imported mesh
	# yet. It already carries its own plain material, so the glow becomes emission on that
	# instead of a second render pass; there is no skeleton mesh here for next_pass to sit on.
	var fallback: CSGBox3D = find_child("CSGBox3D", true, false) as CSGBox3D
	if fallback != null and fallback.material is StandardMaterial3D:
		var fallback_material: StandardMaterial3D = (fallback.material as StandardMaterial3D).duplicate()
		fallback_material.emission_enabled = true
		fallback_material.emission = enemy_data.visual_color
		fallback_material.emission_energy_multiplier = 2.0
		fallback.material = fallback_material

# ============================================================
# BOSS MODIFIERS
#
# A named, MTG-flavoured trait a boss can spawn with - Elite's own system never reaches
# bosses at all (_assign_elites excludes them), and a boss's whole kit is its two
# telegraphed specials rather than ordinary stats, so these reshape THAT rather than
# reusing Elite's stat-multiplier shape. At most one per boss. See GameSettings' Boss
# modifiers block for every number.
# ============================================================

## Whatever a modifier changes about the specials THEMSELVES (cooldown weighting, reach,
## Enrage's damage step) is applied per-cast in _begin_special, on a duplicated config - see
## that function's own comment for why a shared BossDatabase dict may never be mutated in
## place. Only the two flat, permanent changes live here: Riot's damage cut (applies from
## the very first cast) and the anim-speed bump that shortens every future windup.
func apply_boss_modifier(modifier: String) -> void:
	boss_modifier = modifier
	match modifier:
		"Riot":
			enemy_data.attack_damage *= GameSettings.boss_modifier_riot_damage_mult
			_anim_speed_scale *= GameSettings.boss_modifier_riot_anim_speed_mult
		"Annihilator":
			enemy_data.attack_damage *= GameSettings.boss_modifier_annihilator_damage_mult
	_apply_boss_modifier_tag()


## The per-special cooldown multiplier for whichever modifier is active. Cataclysm and
## Bloodthirst weigh the melee special (the one flagged hits_crystal - boss_specials.gd checks
## there is exactly one) against everything else; every phase special counts as "big".
##
## Enrage has no entry: since every boss gained phases, Enrage is a boss that reaches them
## early and hits harder in the last one (see _check_boss_phase), and the phases themselves
## are what speed it up.
func _boss_modifier_cooldown_mult(index: int) -> float:
	var is_melee: bool = index >= 0 and index < _specials.size() and bool((_specials[index] as Dictionary).get("hits_crystal", false))
	match boss_modifier:
		"Riot":
			return GameSettings.boss_modifier_riot_cooldown_mult
		"Annihilator":
			return GameSettings.boss_modifier_annihilator_cooldown_mult
		"Cataclysm":
			return GameSettings.boss_modifier_cataclysm_melee_cooldown_mult if is_melee else GameSettings.boss_modifier_cataclysm_big_cooldown_mult
		"Bloodthirst":
			return GameSettings.boss_modifier_bloodthirst_melee_cooldown_mult if is_melee else GameSettings.boss_modifier_bloodthirst_big_cooldown_mult
	return 1.0


func _boss_modifier_radius_mult() -> float:
	if boss_modifier == "Annihilator":
		return GameSettings.boss_modifier_annihilator_radius_mult
	return 1.0


## Shows the modifier's name over the boss's health bar, in the tint its own telegraph
## already uses - the same colour a player learns to read as "get out of this" during the
## fight now also tells them what they walked up to before the first hit even lands.
func _apply_boss_modifier_tag() -> void:
	if health_bar == null or boss_modifier == "":
		return
	health_bar.set_modifier_tag(boss_modifier.to_upper(), _boss_modifier_tint())


func _boss_modifier_tint() -> Color:
	match boss_modifier:
		"Riot": return Color(1.0, 0.55, 0.15)
		"Annihilator": return Color(0.55, 0.15, 0.65)
		"Cataclysm": return Color(0.85, 0.2, 0.75)
		"Bloodthirst": return Color(0.75, 0.05, 0.1)
		"Enrage": return Color(1.0, 0.85, 0.1)
		"Lifelink": return Color(0.15, 0.85, 0.4)
	return Color.WHITE

func _get_detection_range() -> float:
	if enemy_data and (enemy_data.enemy_class == "Mage" or enemy_data.enemy_class == "Ranged"):
		return GameSettings.enemy_ranged_detection_range
	return GameSettings.enemy_melee_detection_range

## Who this enemy is trying to reach. Priority, highest first:
##   1. a TAUNT - Roar drags it onto the player no matter what else is nearby
##   2. pacified - back to the crystal, ignoring everyone
##   3. the nearest valid aggro target, decoys included
##
## Decoys are in `decoys` rather than `player`, so they are chosen the same way a myr
## is but nothing else in the game mistakes one for a real player.
func evaluate_target() -> void:
	if taunt_timer > 0.0 and is_instance_valid(taunt_source):
		if current_target != taunt_source:
			current_target = taunt_source
			update_path(true)
		return

	if pacified_timer > 0.0:
		if current_target != target_crystal:
			current_target = target_crystal
			update_path(true)
		return

	var best_target: Node3D = target_crystal
	var best_distance_squared: float = INF
	var detection_range: float = _get_detection_range()
	var detection_range_squared: float = detection_range * detection_range

	for candidate in aggro_area.get_overlapping_bodies():
		if not candidate is Node3D or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if not candidate.is_in_group("player") and not candidate.is_in_group("myrs") and not candidate.is_in_group("decoys"):
			continue
		if candidate.is_in_group("player") and "is_downed" in candidate and candidate.is_downed:
			continue
		# A phased myr stops being a target mid-approach, and evaluate_target falls back to
		# the crystal on this same pass - see Myr.is_targetable.
		if candidate.has_method("is_targetable") and not candidate.is_targetable():
			continue
		var candidate_distance_squared: float = global_position.distance_squared_to(candidate.global_position)
		if candidate_distance_squared <= detection_range_squared and candidate_distance_squared < best_distance_squared:
			best_target = candidate
			best_distance_squared = candidate_distance_squared

	if current_target != best_target:
		current_target = best_target
		update_path(true)

	# Seeing something worth attacking is the ordinary way out of a formation: the slot was
	# only ever a way of getting here. The squad is told so it can stop counting this one,
	# and so a squad that has lost most of its members can stand itself down.
	if squad != null and current_target != target_crystal:
		leave_formation()

func _on_aggro_body_entered(body: Node3D) -> void:
	evaluate_target()

func _on_aggro_body_exited(body: Node3D) -> void:
	evaluate_target()

# --- Spell Interactions ---
## How every client asks for damage to be dealt.
##
## The client has already played its own hit sound, particles and screen shake - those
## are local and instant, which is what makes combat feel right. Only the CONSEQUENCE
## travels, and only the server applies it, so health can never disagree between peers.
##
## `attacker_peer` rather than a node path: paths are fragile across peers, and the
## server can resolve the avatar itself. Attribution matters because lifesteal and the
## melee-into-spell cooldown refund both pay the player who landed the blow.
@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: float, attacker_peer: int, is_melee: bool, exile_on_kill: bool = false) -> void:
	if not Net.is_server() or is_dying:
		return
	take_damage(amount, PlayerRegistry.by_peer(attacker_peer), is_melee, exile_on_kill)


## `exile_on_kill` is Exalted Strike (white_1) and nothing else: if THIS hit is what
## kills the enemy, it leaves no corpse. It rides on the damage rather than being a
## separate call because the kill and the exile have to be the same decision - checking
## health first and exiling second would race a simultaneous hit from another player.
func take_damage(amount: float, source: Node3D = null, is_melee: bool = false, exile_on_kill: bool = false) -> void:
	if is_dying:
		return
	# Some colours hold their formation under fire and some do not (SquadDoctrine's
	# break_on_damage - Red's goblins scatter the moment anything touches them). The squad
	# owns that decision, so it is asked rather than told.
	if squad != null and is_instance_valid(squad):
		squad.on_member_damaged(self)
	if exile_on_kill:
		_exile_on_death = true
	if curse_timer > 0:
		amount *= curse_mult
	if is_boss():
		amount = _boss_incoming_damage(amount, source)
		if amount > 0.0:
			_since_boss_hit = 0.0
			boss_regenerating = false
	var damage_dealt: float = minf(maxf(amount, 0.0), maxf(health, 0.0))
	health -= amount
	if is_boss():
		_check_boss_phase()
		if _channel_active and enemy_data != null:
			_channel_damage += damage_dealt
			if _channel_damage >= enemy_data.health * float(_special_config.get("break_pct", 0.08)):
				_channel_broken = true
	if damage_dealt > 0.0 and is_instance_valid(source) and source.has_method("on_damage_dealt"):
		source.on_damage_dealt(damage_dealt)
	if health_bar and enemy_data:
		health_bar.set_health(health, enemy_data.health)
	var spawn_pos = global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	NetFx.damage_number(spawn_pos, amount, Color(1.0, 0.95, 0.2), "")
	# Executioner's Capsule: a melee hit from its wearer finishes off anything it leaves this
	# close to death. Never a boss - Kill's boss window is the one way to execute those.
	if health > 0.0 and is_melee and not is_boss() and is_instance_valid(source) \
			and source.has_method("melee_execute_threshold"):
		var threshold: float = float(source.melee_execute_threshold())
		if threshold > 0.0 and enemy_data != null and health <= enemy_data.health * threshold:
			NetFx.damage_number(spawn_pos + Vector3(0.0, 0.4, 0.0), 0.0, Color(0.75, 0.3, 0.95), "Executed")
			health = 0.0
	if health <= 0.0:
		_record_fatal_hit(amount, source)
		# The only point that knows both that this hit was fatal and who threw it. die() takes
		# no source, and SignalBus.enemy_died carries none either - it is a team-wide "one
		# fewer enemy", which is what the wave counter wants and not what a scoreboard does.
		if is_instance_valid(source) and source.has_method("on_enemy_killed_by_me"):
			source.on_enemy_killed_by_me()
		die()
		return
	_react_to_hit(damage_dealt)


## Starts the flinch, if the hit was worth flinching at. Driven from take_damage
## rather than from knockback, which is what it used to key off: a shooter standing
## its ground is the enemy most often shot at and the one least often knocked back,
## so it never visibly reacted to anything.
func _react_to_hit(damage_dealt: float) -> void:
	if _reaction_clip == "" or enemy_data == null:
		return
	if _hit_react_cooldown > 0.0:
		return
	if damage_dealt < enemy_data.health * GameSettings.enemy_hit_react_damage_pct:
		return
	_hit_react_timer = GameSettings.enemy_hit_react_duration
	_hit_react_cooldown = GameSettings.enemy_hit_react_cooldown
	if GameSettings.enemy_hit_react_interrupts_attack:
		# The swing is dropped along with the pose that was building it. Damage is
		# scheduled separately from the animation now, so without this the enemy
		# would flinch and still land the hit it was in the middle of.
		_impact_timer = -1.0

func die() -> void:
	# Dimir Guildmage's own question - "did this thing die under control?" - captured
	# before anything below resets the timers it reads (contagion_timer two lines down,
	# the rest never reset by die() itself but easiest kept next to the one that is).
	var died_controlled: bool = (
		freeze_timer > 0.0 or stun_timer > 0.0 or curse_timer > 0.0 or contagion_timer > 0.0
	)
	# The slot goes back before anything else happens: a corpse holds one for the couple of
	# seconds its death animation runs, and a squad measuring its march speed off a dead
	# mage would keep walking at the dead mage's pace.
	leave_formation()
	# A corpse is not sick - and the replicated timer going to 0 is what clears the haze on
	# every client's copy too.
	contagion_timer = 0.0
	_contagion_outbreak = {}
	_sync_contagion_fx()
	# Exiled rather than killed: same rewards, no body left behind. See exile().
	if _exile_on_death:
		exile()
		return
	var death_debug_before: Dictionary = _death_animation_debug_state()
	if enemy_data:
		SignalBus.enemy_died.emit()
		SignalBus.enemy_died_at.emit(global_position)
		# The team is paid twice for one kill: XP towards a level everybody shares, and
		# mana in this enemy's own colour. Banked here rather than dropped, because the
		# pool is shared and there is nobody for a pickup to belong to.
		if not _skip_kill_rewards:
			RunState.on_enemy_killed(enemy_data, elite_modifier != "", global_position)
			if died_controlled:
				_raise_as_dimir_ghoul()

	# Dying mid-windup drops the telegraph without dealing its damage - and the same
	# goes for an ordinary swing whose impact frame has not arrived yet.
	_cancel_special()
	_cancel_miniboss_special()
	_exhausted_timer = 0.0
	_pending_phase_transition = false
	_impact_timer = -1.0
	_hit_react_timer = 0.0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		_log_death_animation_debug("play_requested", death_debug_before)
		is_dying = true
		# Nothing collides with a corpse (layer 0), but the corpse still has to find the
		# FLOOR, or one killed in mid-air plays its death clip hanging there. See
		# _settle_corpse.
		collision_layer = 0
		collision_mask = ENVIRONMENT_LAYER
		remove_from_group("enemies")
		if health_bar:
			health_bar.visible = false
		var death_anim: Animation = visual_anim_player.get_animation("death")
		var death_speed: float = maxf(_anim_speed_scale, 0.05)
		if death_anim and death_anim.length / death_speed > DEATH_MAX_SECONDS:
			death_speed = death_anim.length / DEATH_MAX_SECONDS
		visual_anim_player.play("death", -1, death_speed)
		_death_clip_seconds = death_anim.length / death_speed if death_anim else 0.0
		call_deferred("_check_death_animation_started", death_speed)
		_start_death_launch()
		_register_corpse()
	else:
		push_warning("Enemy death animation unavailable: %s" % _format_death_animation_debug(death_debug_before))
		queue_free()


## Puts an enemy that has left the walkable map back on it. Server only; the move reaches
## every other screen as the replicated position. True on the frame it happens, so the rest
## of that frame's movement does not carry the old velocity on from the new spot.
##
## The navmesh is the one thing that knows where an enemy may stand, so it is the test:
## further below its nearest point than `below_distance` means the body has gone through
## the ground and only ever falls further; further beside it than `off_distance` for longer
## than `off_seconds` means it has been pushed or walked somewhere it cannot path out of -
## over a cliff, into a wall, off the edge of the map. Both end with the enemy standing on
## that nearest point with nothing carrying it, and a fresh path.
##
## Not a kill: the wave still has to deal with it, and nobody is paid for an enemy the map
## lost. Every recovery is logged with where it happened, which is how a hole in the map is
## found.
##
## Asking the navmesh is expensive, though: map_get_closest_point searches the whole terrain
## navmesh, about 1.3 ms a call on this map, and with every enemy asking every half second it
## was most of the frame drops in a crowded wave. So the path the agent last planned is asked
## first - every point of it lies on the navmesh, so an enemy standing on it by the same two
## measures is on the map, and only an enemy that has strayed from its path pays for the
## real question.
func _check_recovery(delta: float) -> bool:
	_recovery_timer -= delta
	if _recovery_timer > 0.0:
		return false
	var interval: float = GameSettings.enemy_recovery_check_interval
	_recovery_timer = interval
	if _on_planned_path():
		_off_navmesh_time = 0.0
		return false
	var map: RID = get_world_3d().navigation_map
	# Nothing to measure against until the navmesh is in: an empty map answers (0, 0, 0)
	# for everything, and every enemy would be "off" it.
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var nearest: Vector3 = NavigationServer3D.map_get_closest_point(map, global_position)
	if nearest == Vector3.ZERO and global_position.length() > 5.0:
		return false
	var below: float = nearest.y - global_position.y
	var beside: float = Vector2(nearest.x - global_position.x, nearest.z - global_position.z).length()
	var reason: String = ""
	if below > GameSettings.enemy_recovery_below_distance:
		reason = "below the ground"
	elif beside > GameSettings.enemy_recovery_off_distance:
		_off_navmesh_time += interval
		if _off_navmesh_time >= GameSettings.enemy_recovery_off_seconds:
			reason = "off the walkable map"
	else:
		_off_navmesh_time = 0.0
	if reason == "":
		return false
	print("Enemy recovered (%s): %s at %s -> %s" % [reason, name, global_position, nearest])
	_off_navmesh_time = 0.0
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	global_position = nearest + Vector3(0.0, 0.1, 0.0)
	NetFx.spell("corpse_land", nearest, 0.8, 0)
	update_path(true)
	return true


## Whether this enemy stands on the path its agent last planned, by the same two measures
## _check_recovery uses: no further beside it than `off_distance`, no further below it than
## `below_distance`. Only the legs either side of the waypoint it is walking to are tried -
## an enemy anywhere else along its path has been moved off it, and the full check should
## run. A false here is never a verdict, only "ask the navmesh".
func _on_planned_path() -> bool:
	if nav_agent == null:
		return false
	var path: PackedVector3Array = nav_agent.get_current_navigation_path()
	if path.is_empty():
		return false
	var here: Vector3 = global_position
	var index: int = clampi(nav_agent.get_current_navigation_path_index(), 0, path.size() - 1)
	var off_squared: float = GameSettings.enemy_recovery_off_distance * GameSettings.enemy_recovery_off_distance
	for i: int in range(maxi(index - 1, 0), mini(index + 1, path.size() - 1) + 1):
		var point: Vector3 = path[i]
		if i + 1 < path.size():
			point = Geometry3D.get_closest_point_to_segment(here, path[i], path[i + 1])
		var beside: float = Vector2(point.x - here.x, point.z - here.z).length_squared()
		if beside <= off_squared and point.y - here.y <= GameSettings.enemy_recovery_below_distance:
			return true
	return false


## Which way the fatal hit came from and how big it was, for _start_death_launch.
##
## Away from whoever dealt it - for a spell that is the caster, which is close enough to
## where the blast came from to read right. A knockback already moving the body (Unsummon,
## a slam) wins over that, since it is the push the player actually aimed, and it counts
## towards how hard the body is thrown.
func _record_fatal_hit(amount: float, source: Node3D) -> void:
	var dir := Vector3.ZERO
	var push: float = Vector2(knockback_velocity.x, knockback_velocity.z).length()
	if push > 0.5:
		dir = Vector3(knockback_velocity.x, 0.0, knockback_velocity.z)
	elif is_instance_valid(source):
		dir = global_position - source.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		var angle: float = randf() * TAU
		dir = Vector3(cos(angle), 0.0, sin(angle))
	_fatal_hit_dir = dir.normalized()
	var full: float = maxf(enemy_data.health if enemy_data != null else 100.0, 1.0)
	_fatal_hit_severity = maxf(amount, 0.0) / full + push * 0.08


## Throws a killed enemy away from the hit that killed it. Server only; the body's flight
## reaches every other screen as its replicated position, and `death_launch` tells them
## which way to lean it.
##
## Not for bosses: a colossus is not thrown across the field by the hit that finishes it,
## and its long death is a set piece of its own. Elites and minibosses are bigger and go
## proportionally less far.
##
## The body is also turned so its death clip falls the way it is thrown - the clips fall
## forwards on some rigs and backwards on others, and a body flying back while toppling
## towards its killer reads as wrong at once.
func _start_death_launch() -> void:
	if is_boss() or enemy_data == null or _fatal_hit_dir == Vector3.ZERO:
		return
	var t: float = clampf(inverse_lerp(GameSettings.enemy_death_launch_severity_min,
		GameSettings.enemy_death_launch_severity_full, _fatal_hit_severity), 0.0, 1.0)
	var heft: float = maxf(enemy_data.model_scale, 1.0)
	var speed: float = lerpf(GameSettings.enemy_death_launch_speed_min, GameSettings.enemy_death_launch_speed_max, t) / heft
	var up: float = lerpf(GameSettings.enemy_death_launch_up_min, GameSettings.enemy_death_launch_up_max, t) / heft
	_face_death_fall(_fatal_hit_dir)
	velocity = Vector3.ZERO
	death_launch = _fatal_hit_dir * speed + Vector3.UP * up


## Turns the body about Y so the death clip's own fall points along `dir`.
##
## Measured off the clip rather than assumed: the hips' rotation on the last key, applied
## to the rig as it stands now, gives which way the torso ends up lying. The difference
## between that and `dir` is the turn. Cached per clip - every enemy on a rig shares it.
static var _death_fall_cache: Dictionary = {}

func _face_death_fall(dir: Vector3) -> void:
	if visual_anim_player == null or _visual_root == null or not visual_anim_player.has_animation("death"):
		return
	var clip: Animation = visual_anim_player.get_animation("death")
	var skeleton: Skeleton3D = _visual_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var local_fall: Vector3
	if _death_fall_cache.has(clip):
		local_fall = _death_fall_cache[clip]
	else:
		local_fall = Vector3.ZERO
		for track: int in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var path: NodePath = clip.track_get_path(track)
			if path.get_subname_count() == 0 or not String(path.get_subname(0)).ends_with("Hips"):
				continue
			var last: Quaternion = clip.track_get_key_value(track, clip.track_get_key_count(track) - 1)
			var bone: int = skeleton.find_bone(String(path.get_subname(0)))
			var parent_basis := Basis()
			if bone >= 0 and skeleton.get_bone_parent(bone) >= 0:
				parent_basis = skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).basis
			# In the skeleton's own space; the body's yaw is applied below, each time.
			local_fall = parent_basis * Basis(last) * Vector3.UP
			break
		_death_fall_cache[clip] = local_fall
	var fall: Vector3 = skeleton.global_basis * local_fall
	fall.y = 0.0
	if fall.length_squared() < 0.0001:
		return
	rotation.y += fall.normalized().signed_angle_to(dir, Vector3.UP)


## The flight. Held still for the hitstop, then thrown, falling under gravity; once down it
## skids to a stop against `friction` and stays. Walls stop it like they stop anything.
func _fly_corpse(delta: float) -> void:
	if _launch_time < GameSettings.enemy_death_hitstop:
		return
	if velocity == Vector3.ZERO and not _launch_landed:
		velocity = death_launch
		# Off the ground this frame, so the first floor check does not land it at once.
		global_position.y += 0.02
	var falling_speed: float = -velocity.y
	velocity.y -= gravity * delta
	move_and_slide()
	if is_on_floor() and velocity.y <= 0.0:
		if not _launch_landed:
			_launch_landed = true
			_land_corpse(falling_speed)
		velocity.y = 0.0
		var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, GameSettings.enemy_death_launch_friction * delta)
		velocity.x = flat.x
		velocity.z = flat.y


func _land_corpse(impact_speed: float) -> void:
	var threshold: float = GameSettings.enemy_death_land_dust_speed
	if impact_speed < threshold:
		return
	NetFx.spell("corpse_land", global_position, clampf(impact_speed / threshold * 0.7, 0.7, 1.6), 0)
	if impact_speed > threshold * 2.0:
		NetFx.sound(&"blunt_hit", global_position)


## Leans the model into its throw - the body tipping over as it flies - and back upright by
## the time it lands, so the death clip, which lays the body down on its own, finishes it.
## Runs on every peer from the replicated `death_launch`: the lean is the model, not the
## body, and is not replicated itself. Also holds the death clip for the hitstop.
func _lean_corpse(delta: float) -> void:
	if death_launch == Vector3.ZERO or _visual_root == null or _lean_done:
		return
	if _launch_time < 0.0:
		_launch_time = 0.0
	_launch_time += delta
	var hitstop: float = GameSettings.enemy_death_hitstop
	if _launch_time >= hitstop and not _ragdoll_asked:
		_ragdoll_asked = true
		if EnemyRagdoll.wanted(Vector2(death_launch.x, death_launch.z).length()):
			_ragdoll = EnemyRagdoll.start(self, _visual_root, visual_anim_player, death_launch)
	if _ragdoll != null:
		_lean_done = true
		return
	var flight: float = maxf(2.0 * death_launch.y / maxf(gravity, 0.01), 0.05)
	var phase: float = clampf((_launch_time - hitstop) / flight, 0.0, 1.0)
	if visual_anim_player != null:
		# Frozen for the hitstop; through the flight, fast enough that the body is most of the
		# way down when it lands; its own pace after that.
		var flight_speed: float = maxf(_death_clip_seconds * GameSettings.enemy_death_launch_clip_at_landing / flight, 1.0)
		if _launch_time < hitstop:
			visual_anim_player.speed_scale = 0.0
		elif phase < 1.0:
			visual_anim_player.speed_scale = flight_speed
		else:
			visual_anim_player.speed_scale = 1.0
	var lean: float = deg_to_rad(GameSettings.enemy_death_launch_lean_degrees) * sin(phase * PI)
	var throw_dir: Vector3 = Vector3(death_launch.x, 0.0, death_launch.z)
	if lean <= 0.0001 or throw_dir.length_squared() < 0.0001:
		_visual_root.transform = _visual_rest
		_lean_done = phase >= 1.0
		return
	# Tipping the top of the body along the throw, about the hips rather than the feet.
	var axis_world: Vector3 = Vector3.UP.cross(throw_dir.normalized())
	var axis: Vector3 = (global_basis.orthonormalized().inverse() * axis_world).normalized()
	var pivot := Vector3(0.0, 0.9, 0.0)
	var tilt := Transform3D(Basis(axis, lean), Vector3.ZERO)
	_visual_root.transform = Transform3D(Basis(), pivot) * tilt * Transform3D(Basis(), -pivot) * _visual_rest


## A corpse still falls.
##
## Everything else about a dying enemy is deliberately frozen - it has left its formation,
## it deals and takes nothing, and its death clip is already playing - but the early
## return that freezes it skipped GRAVITY along with the AI, so anything killed off the
## ground (knocked up by Unsummon, caught mid-slope, killed while a squad shoved it) held
## whatever height it died at and played its whole death animation in the air.
##
## Horizontal velocity is dropped rather than kept: the body has no collision left to stop
## it, so any speed it died carrying would slide it across the map for the length of the
## clip. It falls straight down and stays where it lands.
func _settle_corpse(delta: float) -> void:
	if is_on_floor():
		velocity = Vector3.ZERO
		return
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y -= gravity * delta
	move_and_slide()


func _death_animation_debug_state() -> Dictionary:
	var data: Dictionary = {
		"id": get_instance_id(),
		"name": name,
		"class": enemy_data.enemy_class if enemy_data else "<no enemy_data>",
		"color": enemy_data.color_identity if enemy_data else "<no enemy_data>",
		"elite": elite_modifier,
		"health": health,
		"is_dying": is_dying,
		"queued": is_queued_for_deletion(),
		"visual_player": "<none>",
		"current": "<none>",
		"playing": false,
		"has_death": false,
		"death_length": 0.0,
		"animations": "",
	}
	if visual_anim_player == null:
		return data
	data["visual_player"] = str(visual_anim_player.get_path())
	data["current"] = visual_anim_player.current_animation
	data["playing"] = visual_anim_player.is_playing()
	data["has_death"] = visual_anim_player.has_animation("death")
	data["animations"] = ",".join(visual_anim_player.get_animation_list())
	if visual_anim_player.has_animation("death"):
		var death_anim: Animation = visual_anim_player.get_animation("death")
		data["death_length"] = death_anim.length if death_anim else 0.0
	return data


func _log_death_animation_debug(stage: String, data: Dictionary, extra: String = "") -> void:
	var suffix: String = "" if extra == "" else " %s" % extra
	print("Enemy death animation %s: %s%s" % [stage, _format_death_animation_debug(data), suffix])


func _format_death_animation_debug(data: Dictionary) -> String:
	return "id=%s node=%s color=%s class=%s elite=%s health=%.2f dying=%s queued=%s player=%s current=%s playing=%s has_death=%s death_len=%.2f anims=[%s]" % [
		str(data.get("id", "?")),
		str(data.get("name", "?")),
		str(data.get("color", "?")),
		str(data.get("class", "?")),
		str(data.get("elite", "")),
		float(data.get("health", 0.0)),
		str(data.get("is_dying", false)),
		str(data.get("queued", false)),
		str(data.get("visual_player", "?")),
		str(data.get("current", "?")),
		str(data.get("playing", false)),
		str(data.get("has_death", false)),
		float(data.get("death_length", 0.0)),
		str(data.get("animations", "")),
	]


func _check_death_animation_started(requested_speed: float) -> void:
	if not is_instance_valid(self) or visual_anim_player == null:
		return
	var data: Dictionary = _death_animation_debug_state()
	var playing_death: bool = String(data["current"]) == "death" and bool(data["playing"])
	var extra: String = "requested_speed=%.3f" % requested_speed
	if playing_death:
		_log_death_animation_debug("confirmed", data, extra)
	else:
		push_warning("Enemy death animation did not take over: %s %s" % [_format_death_animation_debug(data), extra])

# Corpses are left in the scene (not freed) once their death clip finishes, up to
# a cap; the oldest corpse is freed to make room for each new one past the cap.
func _register_corpse() -> void:
	_corpses.append(self)
	# Walk from the oldest corpse forward, freeing the first one whose death clip
	# has actually finished. A burst of simultaneous kills (e.g. an AoE wipe at the
	# crystal) can otherwise land several very-fresh corpses at the front of the
	# queue at once; force-freeing strictly by age would cut their death animation
	# off mid-play. Leaving the list briefly over the cap is harmless - it corrects
	# itself as soon as any corpse's clip finishes.
	var i := 0
	while _corpses.size() > GameSettings.enemy_max_corpses and i < _corpses.size():
		var oldest: EnemyBase = _corpses[i]
		if not is_instance_valid(oldest):
			_corpses.remove_at(i)
			continue
		if oldest.visual_anim_player and oldest.visual_anim_player.is_playing():
			i += 1
			continue
		_corpses.remove_at(i)
		oldest.queue_free()

func unsummon(force_vec: Vector3 = Vector3.ZERO) -> void:
	if force_vec != Vector3.ZERO:
		apply_knockback(force_vec)
	else:
		if is_instance_valid(target_crystal):
			var dir_away = (global_position - target_crystal.global_position).normalized()
			global_position += dir_away * GameSettings.spell_unsummon_teleport_distance
			
		current_target = target_crystal
		update_path()

func apply_knockback(force_vec: Vector3) -> void:
	knockback_velocity = force_vec


## Suction's pull, refreshed by the zone every frame the enemy is inside it. Strength
## is low on purpose - walking out of the zone is the counterplay.
##
## CAPPED PER ENEMY, because Suction's duration curve (10s at rank 1 to 30s at rank 5) runs
## well past its 11-second cooldown and a high-rank blue player can have three vortexes
## standing at once. Overlapping zones each call this every frame; last-writer-wins meant an
## enemy in two of them was dragged towards a different centre on alternating frames, which
## both jittered the body and let the pulls compound into something nothing could walk out of.
##
## The nearest centre wins instead. Stable frame to frame, so no jitter, and one enemy is never
## pulled faster than a single vortex pulls - stacking vortexes covers more GROUND, which is
## the reward the duration curve was actually meant to buy.
func apply_suction(center: Vector3, strength: float) -> void:
	if _suction_timer > 0.0:
		var held: float = global_position.distance_squared_to(_suction_center)
		if global_position.distance_squared_to(center) >= held:
			# Already being pulled by something nearer; this zone contributes nothing extra.
			_suction_timer = 0.2
			return
	_suction_center = center
	_suction_strength = strength
	_suction_timer = 0.2

func apply_chill() -> void:
	chill_stacks += 1
	if chill_stacks >= 3:
		chill_stacks = 0
		freeze_timer = 3.0
		_trigger_shatter_aoe()

func _trigger_shatter_aoe() -> void:
	var radius = GameSettings.spell_blue_freeze_breath_shatter_radius
	var damage = GameSettings.spell_blue_freeze_breath_shatter_damage
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e != self and is_instance_valid(e) and global_position.distance_to(e.global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)

func apply_root(duration: float) -> void:
	root_timer = duration

func apply_stun(duration: float) -> void:
	stun_timer = duration

## Azorius Justiciar (white+blue guild node): an enemy a player freezes, stuns or knocks
## back deals less damage for a while afterwards. `source` is whichever player caused the
## control effect - every caller already has one in scope - and this is a no-op for
## anyone who does not own the node, so every caller can call it unconditionally.
##
## Reuses `damage_penalty`/`penalty_timer` rather than a multiplier of its own: that is
## the same flat reduction Pacifism and the melee stab debuff already use, and the merge
## rule (keep the larger of either) matches apply_doom_curse's reasoning on the other
## side of the ledger - two different control effects landing a moment apart should not
## halve the enemy's damage twice over.
func apply_control_weaken(source: Node3D) -> void:
	if enemy_data == null or source == null or not is_instance_valid(source):
		return
	if not source.has_method("has_guild") or not source.has_guild("guild_azorius"):
		return
	damage_penalty = maxf(damage_penalty, enemy_data.attack_damage * GameSettings.guild_azorius_weaken_mult)
	penalty_timer = maxf(penalty_timer, GameSettings.guild_azorius_weaken_duration)

func apply_blind(duration: float) -> void:
	blind_timer = duration

## Vulnerability: this enemy takes `mult` times damage for `duration`. Wall of Souls' mark
## (black_4) lands here - and Fear's flee window did, while black had Fear.
##
## Keeps the HIGHER multiplier and the LONGER duration rather than overwriting, the same way
## apply_burn keeps the higher dps. Overwriting meant whichever of black's two debuffs landed
## second silently cancelled the first - Fear cast into a Wall of Souls would have downgraded
## a x2 mark to x1.3, which is the opposite of what casting both should do.
##
## The two halves are taken independently, so a short strong curse does extend its strength
## across a long weak one's remaining time. That is the same trade apply_burn already makes,
## and it errs towards the player in a game where the player is the one applying them.
func apply_doom_curse(duration: float, mult: float) -> void:
	curse_mult = maxf(curse_mult, mult) if curse_timer > 0.0 else mult
	curse_timer = maxf(curse_timer, duration)

func apply_pacifism(duration: float) -> void:
	pacified_timer = duration
	damage_penalty = enemy_data.attack_damage * GameSettings.spell_white_pacifism_debuff_mult
	current_target = target_crystal
	update_path(true)

func apply_stab_debuff() -> void:
	damage_penalty = GameSettings.spell_stab_debuff_damage
	penalty_timer = GameSettings.spell_stab_debuff_duration

func apply_frost_slow(duration: float) -> void:
	frost_slow_timer = duration


## The soft slow, from Fog and from Fire Cone. Takes the STRONGEST multiplier and the
## LONGEST duration rather than stacking them, exactly as apply_burn takes the higher dps:
## two sources multiplying would put an enemy standing in fog under a fire cone at 0.39 speed,
## which is a hard root neither spell was meant to be.
##
## Both callers refresh this every tick with a short duration, so an enemy that walks out
## recovers within a fraction of a second instead of carrying the slow away with it.
func apply_slow(duration: float, mult: float) -> void:
	# A slow is control, so bosses shrug it off with everything else that would take them out
	# of their own fight. Kept here rather than at the two call sites so a third source cannot
	# forget it - and so Fog still suppresses a boss's damage while failing to slow it, which
	# is the same split Frost Breath already makes.
	if is_immune_to_control():
		return
	if slow_timer <= 0.0:
		slow_mult = mult
	else:
		slow_mult = minf(slow_mult, mult)
	slow_timer = maxf(slow_timer, duration)


## How fast this enemy actually walks, as a fraction of its own speed. Frost and the soft
## slow do not multiply - the strongest one wins - so no combination of them can stop an
## enemy dead. Only movement reads this; frost's attack-speed half stays frost's alone.
func movement_speed_mult() -> float:
	var mult: float = 1.0
	if frost_slow_timer > 0.0:
		mult = GameSettings.enemy_frost_slow_mult
	if slow_timer > 0.0:
		mult = minf(mult, slow_mult)
	# Applied on TOP of the slows rather than clamped against them: a charge that a single
	# frost stack could cancel outright would not read as a charge at all, and a charging
	# enemy that has been slowed should still be visibly faster than a walking one.
	if charge_timer > 0.0:
		mult *= charge_mult
	return mult


# --- Skill-tree status effects -------------------------------------------------
#
# One entry point per effect, all server-side: every one of them is reached from a
# player spell, and player spells only run their effect on the server (see
# Player.execute_spell). Clients see the consequence through the enemy's replicated
# transform and health.

## Flee. The enemy turns and runs from `origin` for `duration`, attacking nothing on the
## way. Built for black's old Fear, kept for whatever wants it next: it moves the body rather
## than setting `pacified_timer`, because a flee has to actually create distance.
func apply_fear(duration: float, origin: Vector3) -> void:
	if is_immune_to_control():
		return
	flee_timer = maxf(flee_timer, duration)
	flee_from = origin
	current_target = null
	leave_formation()


## Runs directly away from whatever caused the fear. Deliberately NOT navigated: the
## navigation agent can only path TOWARD a target, and asking it to reach a point behind
## the enemy would route it back through the player it is running from. Straight-line
## movement with the ordinary collision slide is what "flee" means here.
func _flee(delta: float) -> void:
	var away: Vector3 = global_position - flee_from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -transform.basis.z
	away = away.normalized()
	var speed_mult: float = movement_speed_mult()
	velocity.x = away.x * enemy_data.speed * GameSettings.enemy_flee_speed_mult * speed_mult
	velocity.z = away.z * enemy_data.speed * GameSettings.enemy_flee_speed_mult * speed_mult
	rotation.y = lerp_angle(rotation.y, atan2(away.x, away.z), GameSettings.enemy_turn_speed * delta)
	move_and_slide()


## Roar (green_4). Forces this enemy onto `source` - the point being to peel it off the
## crystal or a myr, which the ordinary nearest-target rule would never do while the
## crystal is closer.
func apply_taunt(source: Node3D, duration: float) -> void:
	if not is_instance_valid(source) or is_immune_to_control():
		return
	taunt_timer = maxf(taunt_timer, duration)
	taunt_source = source
	flee_timer = 0.0
	pacified_timer = 0.0
	# Roar is meant to pull an enemy OUT of whatever it was doing, and standing in a rank
	# is something to be pulled out of. Left in the squad it would keep being counted as a
	# member and would walk straight back to its slot the moment the taunt expired.
	leave_formation()
	evaluate_target()


## Fog (green_3). Refreshed every tick while the enemy stands in the cloud, so walking
## out of it restores the enemy's damage within one tick rather than at the end of a
## duration it carried away with it.
func suppress_damage(duration: float) -> void:
	damage_suppress_timer = maxf(damage_suppress_timer, duration)


## Fog's feedback. Suppressed damage is the only effect in the game with NO observable
## consequence - the player sees enemies swinging and nothing happening, which reads as the
## spell having failed rather than as the spell working, and made green's best defensive
## cooldown feel like a dud in solo play. Every swing the cloud eats now says so over the
## enemy that threw it, in the same floating-number language everything else uses.
##
## Shown over the ENEMY rather than over what it was aiming at: the crystal is often off
## screen, and what the player wants to see is which attackers the cloud is holding.
func _report_fog_prevented(amount: float) -> void:
	var spawn_pos: Vector3 = global_position + Vector3(randf_range(-0.3, 0.3), 1.9, randf_range(-0.3, 0.3))
	var fog_color := Color(0.72, 0.92, 0.82)
	if amount <= 0.0:
		NetFx.damage_number(spawn_pos, 0.0, fog_color, "Fogged")
		return
	NetFx.damage_number(spawn_pos, 0.0, fog_color, "-%d" % roundi(amount))


## Burn. Refreshing re-arms the duration and takes the HIGHER damage of the two, so a
## weak burn can never overwrite a strong one - stacking them instead would make the
## Orb of Fire's own repeat fire scale quadratically with its fire rate.
func apply_burn(duration: float, dps: float, source: Node3D = null) -> void:
	burn_timer = maxf(burn_timer, duration)
	burn_dps = maxf(burn_dps, dps)
	burn_source = source
	if burn_tick <= 0.0:
		burn_tick = BURN_TICK_INTERVAL


## Contagion (black_2). `outbreak` is the cast's shared record - how many more enemies it may
## still reach, and the duration, damage and jump radius every victim gets. Re-infecting a
## sick enemy only refreshes it; it is the SPREAD that the outbreak counts.
func apply_contagion(outbreak: Dictionary, source: Node3D = null) -> void:
	if is_dying or outbreak.is_empty():
		return
	var fresh: bool = contagion_timer <= 0.0
	contagion_timer = maxf(contagion_timer, float(outbreak.get("duration", 0.0)))
	_contagion_outbreak = outbreak
	_contagion_source = source
	if fresh:
		_contagion_tick = BURN_TICK_INTERVAL
		_contagion_spread_timer = GameSettings.spell_black_contagion_spread_interval
	_sync_contagion_fx()


## One frame of plague: the damage, on the burn's tick, and the jump, on its own clock.
func _tick_contagion(delta: float) -> void:
	contagion_timer -= delta
	_contagion_tick -= delta
	if _contagion_tick <= 0.0:
		_contagion_tick = BURN_TICK_INTERVAL
		take_damage(float(_contagion_outbreak.get("dps", 0.0)) * BURN_TICK_INTERVAL, _contagion_source)
		if is_dying:
			return
	_contagion_spread_timer -= delta
	if _contagion_spread_timer <= 0.0:
		_contagion_spread_timer = GameSettings.spell_black_contagion_spread_interval
		_spread_contagion()
	if contagion_timer <= 0.0:
		contagion_timer = 0.0
		_contagion_outbreak = {}
		_contagion_source = null


## Jumps to the nearest enemy that is not sick yet, if the outbreak has any reach left. The
## jump is drawn - a plague that moves invisibly reads as enemies randomly taking damage.
func _spread_contagion() -> void:
	if int(_contagion_outbreak.get("left", 0)) <= 0:
		return
	var radius: float = float(_contagion_outbreak.get("radius", 0.0))
	var best: EnemyBase = null
	var best_distance: float = radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var other := node as EnemyBase
		if other == null or other == self or other.is_dying or other.contagion_timer > 0.0:
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	if best == null:
		return
	_contagion_outbreak["left"] = int(_contagion_outbreak["left"]) - 1
	best.apply_contagion(_contagion_outbreak, _contagion_source)
	var from: Vector3 = global_position + Vector3(0.0, 1.1, 0.0)
	var to: Vector3 = best.global_position + Vector3(0.0, 1.1, 0.0)
	if from.distance_to(to) > 0.05:
		NetFx.beam(from, (to - from).normalized(), from.distance_to(to), CONTAGION_TINT)


## A sick green haze rising off an infected enemy, built and cleared to follow
## `contagion_timer` - on the server from the plague itself, on a client from the replicated
## timer.
func _sync_contagion_fx() -> void:
	var sick: bool = contagion_timer > 0.0 and not is_dying
	if sick and _contagion_fx == null:
		_contagion_fx = GPUParticles3D.new()
		_contagion_fx.name = "ContagionFx"
		_contagion_fx.amount = 10
		_contagion_fx.lifetime = 1.1
		_contagion_fx.draw_pass_1 = SpellFx.premul_particle_mesh(0.3, "smoke")
		var haze := ParticleProcessMaterial.new()
		haze.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		haze.emission_sphere_radius = 0.45
		haze.direction = Vector3.UP
		haze.spread = 30.0
		haze.gravity = Vector3(0.0, 0.5, 0.0)
		haze.initial_velocity_min = 0.1
		haze.initial_velocity_max = 0.4
		haze.scale_min = 0.5
		haze.scale_max = 1.0
		haze.color_ramp = SpellFx._premul_ramp(CONTAGION_TINT)
		_contagion_fx.process_material = haze
		_contagion_fx.position = Vector3(0.0, 1.0, 0.0)
		add_child(_contagion_fx)
	elif not sick and _contagion_fx != null:
		_contagion_fx.emitting = false
		var fading: GPUParticles3D = _contagion_fx
		_contagion_fx = null
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(fading):
				fading.queue_free())


## The Icy Manipulator's freeze, from a melee hit. Bosses are slowed instead of frozen - the
## same line Frost Breath draws, because a frozen boss is not a fight.
func apply_equipment_freeze(duration: float) -> void:
	if is_dying:
		return
	if is_boss():
		apply_frost_slow(duration)
		return
	freeze_timer = maxf(freeze_timer, duration)


## A client's melee hit asking for that freeze - status lives on the server, like damage.
## `attacker_peer` is who swung, 0 for an older/absent caller - needed for Azorius
## Justiciar's weaken, which otherwise has no way to know whose guild node to ask about.
@rpc("any_peer", "call_local", "reliable")
func request_freeze(duration: float, attacker_peer: int = 0) -> void:
	if not Net.is_server():
		return
	apply_equipment_freeze(minf(duration, GameSettings.equipment_icy_manipulator_freeze))
	apply_control_weaken(PlayerRegistry.by_peer(attacker_peer))


## Dimir Guildmage (blue+black guild node): dying frozen, stunned, cursed (Wall of Souls)
## or diseased (Contagion) raises the same ghoul Zombify would, no cast spent. Credited
## to whichever player on the team owns the node - nothing upstream of die() tracks WHICH
## player applied the control that killed this enemy, and the five-player game is co-op,
## so one player building towards Dimir benefits the team the same way one player finding
## a piece of equipment does.
##
## Goes through the same `request_effect("undead")` path Zombify's own cast uses
## (SpellEffects.cast_black_zombify), not a local add_child: that is what lets every peer
## see the ghoul, exactly the bug ../temporary_ally.gd's class comment and the earlier
## black-mage-raise fix both exist to avoid repeating.
func _raise_as_dimir_ghoul() -> void:
	var raiser: Node3D = null
	for player: Node3D in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.has_method("has_guild") and player.has_guild("guild_dimir"):
			raiser = player
			break
	if raiser == null or enemy_data == null or is_boss():
		return
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("request_effect"):
		return
	main.request_effect({
		"kind": "undead",
		"position": global_position,
		"hp": GameSettings.spell_black_zombify_hp,
		"duration": GameSettings.spell_black_zombify_duration,
		"hit_damage": GameSettings.spell_black_zombify_hit_damage,
		"damage": GameSettings.spell_black_zombify_burst_damage,
		"caster": raiser.get_multiplayer_authority() if Net.is_active() else 1,
		"color": enemy_data.color_identity,
		"class": enemy_data.enemy_class,
	})


## Kill (black_3) and Exalted Strike (white_1). Removes the enemy WITHOUT leaving a
## corpse - which is a real mechanical difference and not only flavour: corpses are kept
## in the scene up to a cap and are what black's Zombify raises. Exiling denies that.
func exile() -> void:
	if is_dying:
		return
	if enemy_data:
		SignalBus.enemy_died.emit()
		SignalBus.enemy_died_at.emit(global_position)
		# Exiled, but still paid for - and the payout is still shown where the body would
		# have fallen, or an exiled elite would be the one kill that banks in silence.
		RunState.on_enemy_killed(enemy_data, elite_modifier != "", global_position)
	_cancel_special()
	_cancel_miniboss_special()
	queue_free()


## True for a wave boss. Several skills treat bosses as a special case - Frost Breath slows
## rather than freezes them, Kill only executes them below a threshold - and every one of
## those clauses is what stops the skill trivialising the boss fights.
func is_boss() -> bool:
	return enemy_data != null and enemy_data.enemy_class == "Boss"


## Bosses shrug off the effects that would otherwise remove them from their own fight.
## Hard control on a boss is either irrelevant or the whole encounter.
func is_immune_to_control() -> bool:
	return is_boss()


## The corpses currently lying on the field, oldest first. Zombify's raw material - the
## registry already existed purely to cap how many stay in the scene.
static func corpses() -> Array[EnemyBase]:
	var alive: Array[EnemyBase] = []
	for corpse: EnemyBase in _corpses:
		if is_instance_valid(corpse) and not corpse.is_queued_for_deletion():
			alive.append(corpse)
	return alive


## Consumes a corpse - Zombify raises it, so it stops being scenery and must not be
## raised twice.
static func consume_corpse(corpse: EnemyBase) -> void:
	_corpses.erase(corpse)
	if is_instance_valid(corpse):
		corpse.queue_free()
