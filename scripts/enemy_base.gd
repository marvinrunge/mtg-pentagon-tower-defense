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

# Playback multiplier for this enemy's clips. Stays 1.0 for regular enemies;
# bosses get a size-derived value so bigger ones move more ponderously.
var _anim_speed_scale: float = 1.0
var _reaction_clip: String = ""

# --- Boss special attack (telegraphed and dodgeable) ---
## Every special this boss has, and a cooldown per entry. Two, for every boss: the big
## telegraphed area attack and a short-range melee one. See BossDatabase.SPECIALS.
var _specials: Array = []
var _special_cooldowns: Array[float] = []
## The one currently being played, once _begin_special has chosen it.
var _special_config: Dictionary = {}
var _special_index: int = -1
var _special_windup_timer: float = 0.0
var _special_total_timer: float = 0.0
var _is_special_active: bool = false
var _special_resolved: bool = false
var _special_indicator: AttackIndicator
## Named, MTG-flavoured trait - see GameSettings' Boss modifiers block and
## apply_boss_modifier(). Empty for an ordinary boss and for every non-boss enemy.
var boss_modifier: String = ""
## One-way latch for Enrage: true from the moment health first drops under the threshold,
## never reverts. See _check_boss_enrage().
var _enrage_active: bool = false

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
## Fear (black_2): runs AWAY from whatever frightened it instead of fighting.
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
	if data.enemy_class == "Boss":
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
		# find_child rather than get_node: it holds for both the melee scenes (player
		# is a direct child) and the imported boss scenes, without assuming depth.
		visual_anim_player = visual_instance.find_child("AnimationPlayer", true, false)
		_reaction_clip = _resolve_reaction_clip()
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

	scale = Vector3(data.model_scale, data.model_scale, data.model_scale)
	aggro_area.scale = Vector3.ONE / maxf(data.model_scale, 0.01)
	health_bar = _health_bar_scene.instantiate() as EnemyHealthBar
	add_child(health_bar)
	health_bar.set_health(health, data.health)

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
		_special_cooldowns.clear()
		for _entry in _specials:
			_special_cooldowns.append(GameSettings.boss_special_first_delay)
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
	for property: String in [":position", ":rotation", ":health", ":velocity", ":is_dying"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
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
		_update_puppet()
		return
	if is_dying:
		return

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

	# Boss special attack. Runs before the normal movement/attack block because a
	# committed special overrides both - the boss is rooted for its whole duration.
	for i: int in range(_special_cooldowns.size()):
		if _special_cooldowns[i] > 0.0:
			_special_cooldowns[i] -= delta
	if _is_special_active:
		_process_special(delta)
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
func _update_puppet() -> void:
	if health_bar != null and enemy_data != null:
		health_bar.set_health(health, enemy_data.health)
	if is_dying:
		_play_puppet_death()
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
		_play_visual_animation("walk")
	else:
		_rest_visual_animation()

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
func _play_visual_animation(anim_name: String, speed_scale: float = -1.0) -> void:
	if is_dying:
		return
	var speed: float = _anim_speed_scale if speed_scale <= 0.0 else speed_scale
	if visual_anim_player.current_animation != anim_name or not visual_anim_player.is_playing():
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
# A special is a committed, telegraphed swing: the boss roots itself, an
# AttackIndicator draws the danger zone on the ground, and the damage only lands
# once the indicator has filled. That fill window is the dodge - move out of the
# circle, or out of the arc for the cone shapes, and the hit misses entirely.
# ============================================================

## Which special to start now, or -1. Walked in order, so the big one wins wherever both are
## legal - a boss at mid range should open with the attack the player has to move for.
func _pick_special(dist_to_target: float) -> int:
	if _specials.is_empty() or _is_special_active:
		return -1
	if freeze_timer > 0.0 or stun_timer > 0.0 or root_timer > 0.0 or blind_timer > 0.0 or pacified_timer > 0.0:
		return -1
	if not is_instance_valid(current_target) or visual_anim_player == null:
		return -1
	for i: int in range(_specials.size()):
		if _special_cooldowns[i] > 0.0:
			continue
		if _special_eligible(_specials[i], dist_to_target):
			return i
	return -1


func _special_eligible(config: Dictionary, dist_to_target: float) -> bool:
	# Needs a real clip to telegraph with; the placeholder-box fallback has none.
	if not visual_anim_player.has_animation(String(config.get("clip", "special"))):
		return false
	# The big area attack is only ever aimed at something that can DODGE. The crystal cannot,
	# so pointing it there would burn the cooldown on a guaranteed whiff. The melee special is
	# the exception - it is flagged hits_crystal, because a boss with no ordinary swing left
	# still has to be able to break the thing it walked across the map for.
	var target_is_dodger: bool = current_target.is_in_group("player") or current_target.is_in_group("myrs")
	var may_hit_crystal: bool = bool(config.get("hits_crystal", false)) and current_target == target_crystal
	if not target_is_dodger and not may_hit_crystal:
		return false
	# min_range keeps the two apart: the big one is held back at point-blank so the melee one
	# owns that band, and neither is started from further away than it could reach.
	var reach: float = float(config.get("radius", 5.0)) * 0.9
	return dist_to_target >= float(config.get("min_range", 0.0)) and dist_to_target <= reach

func _begin_special(index: int) -> void:
	_special_index = index
	# Duplicated rather than the shared reference _specials[index] itself: BossDatabase.
	# SPECIALS is one Dictionary per colour, reused by every boss of that colour, and a
	# modifier's radius bump below mutates THIS boss's copy for THIS cast only. Mutating
	# the shared one in place would widen the special for every other boss of the same
	# colour, in every other match, permanently.
	_special_config = (_specials[index] as Dictionary).duplicate()
	if boss_modifier != "":
		var radius_mult: float = _boss_modifier_radius_mult()
		if radius_mult != 1.0:
			_special_config["radius"] = float(_special_config.get("radius", 5.0)) * radius_mult
	var clip: String = String(_special_config.get("clip", "special"))
	var anim: Animation = visual_anim_player.get_animation(clip)
	var clip_length: float = anim.length if anim else 1.5
	var playback_speed: float = maxf(_anim_speed_scale, 0.05)
	var impact_fraction: float = clampf(float(_special_config.get("impact_fraction", 0.5)), 0.05, 0.95)

	_is_special_active = true
	_special_resolved = false
	_special_total_timer = clip_length / playback_speed
	_special_windup_timer = _special_total_timer * impact_fraction
	if boss_modifier != "":
		# The one thing no modifier may do: make a telegraph effectively undodgeable. A
		# small boss (short clip) combined with a speed-up modifier is exactly the
		# combination that could otherwise push this under reflex range.
		_special_windup_timer = maxf(_special_windup_timer, GameSettings.boss_modifier_min_windup_seconds)
		_special_total_timer = maxf(_special_total_timer, _special_windup_timer)

	if is_dying:
		return
	visual_anim_player.play(clip, -1, playback_speed)

	# Lock facing at commit time. The cone shapes are dodged by leaving the arc, so
	# the boss must not keep tracking the target once the indicator is drawn.
	if is_instance_valid(current_target):
		var to_target: Vector3 = current_target.global_position - global_position
		if Vector2(to_target.x, to_target.z).length_squared() > 0.01:
			rotation.y = atan2(to_target.x, to_target.z)

	var shape: AttackIndicator.Shape = AttackIndicator.Shape.CIRCLE
	if String(_special_config.get("shape", "circle")) == "cone":
		shape = AttackIndicator.Shape.CONE
	_special_indicator = AttackIndicator.spawn(
		self,
		shape,
		float(_special_config.get("radius", 5.0)),
		float(_special_config.get("angle", 360.0)),
		_special_windup_timer,
		_special_config.get("tint", Color(1.0, 0.4, 0.1)),
		enemy_data.model_scale
	)

func _process_special(delta: float) -> void:
	# Rooted for the whole special: these clips carry their own footwork, and the
	# danger zone is drawn where the boss stood when it committed.
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	if not _special_resolved:
		_special_windup_timer -= delta
		if _special_windup_timer <= 0.0:
			_resolve_special()

	_special_total_timer -= delta
	if _special_total_timer <= 0.0:
		if not _special_resolved:
			_resolve_special()
		_is_special_active = false

func _resolve_special() -> void:
	_special_resolved = true
	if _special_index >= 0 and _special_index < _special_cooldowns.size():
		var cooldown: float = float(_special_config.get("cooldown", GameSettings.boss_special_cooldown))
		if boss_modifier != "":
			cooldown *= _boss_modifier_cooldown_mult(_special_index)
		_special_cooldowns[_special_index] = cooldown
	# Sounded from the boss's own feet rather than from whatever it caught: every
	# special is a slam, a sweep or a landing centred on the boss, and it makes that
	# noise whether or not anyone was still standing in the circle.
	SoundBank.play_at(&"heavy_landing", global_position)

	if _special_indicator and is_instance_valid(_special_indicator):
		_special_indicator.resolve()
	_special_indicator = null

	var damage: float = enemy_data.attack_damage
	damage *= float(_special_config.get("damage_mult", GameSettings.boss_special_damage_mult))
	damage *= GameSettings.get_player_scaling_factor(get_tree())
	if boss_modifier == "Enrage":
		damage *= _boss_modifier_enrage_damage_mult()

	var hit_player: bool = false
	for target in _special_targets_in_shape():
		if target.has_method("take_damage"):
			target.take_damage(damage, self, true)
			if target.is_in_group("player"):
				hit_player = true

	# Lifelink: a share of the nominal damage back, once per resolve rather than once per
	# player it actually caught - a per-target heal would make this scale up for free
	# against a bigger team, which is not the trade the keyword promises.
	if boss_modifier == "Lifelink" and hit_player:
		heal(damage * GameSettings.boss_modifier_lifelink_pct)

	# The crystal is not in _special_targets_in_shape - that set is players and myrs, the
	# things that can move out of the way. It is hit here instead, and only by a special
	# flagged hits_crystal, which is the melee one. Without this a boss stripped of its
	# ordinary swing would walk up to the objective and stand there doing nothing.
	if bool(_special_config.get("hits_crystal", false)) and is_instance_valid(target_crystal):
		var to_crystal: Vector3 = target_crystal.global_position - global_position
		to_crystal.y = 0.0
		if to_crystal.length() <= float(_special_config.get("radius", 5.0)):
			SoundBank.play_at(&"blunt_hit", target_crystal.global_position)
			SignalBus.crystal_damaged.emit(
				damage * elite_crystal_damage_multiplier * _crystal_ward_multiplier()
			)

	# Felt even on a clean dodge, just softer - a slam this size landing next to
	# you should register.
	var radius: float = float(_special_config.get("radius", 5.0))
	if hit_player:
		_request_camera_shake(true)
	elif _is_player_within(radius * 1.6):
		_request_camera_shake(false)

func _special_targets_in_shape() -> Array[Node3D]:
	var results: Array[Node3D] = []
	var radius: float = float(_special_config.get("radius", 5.0))
	var is_cone: bool = String(_special_config.get("shape", "circle")) == "cone"
	var half_angle: float = deg_to_rad(float(_special_config.get("angle", 360.0))) * 0.5

	# +Z is forward for these enemies (they turn with atan2(dir.x, dir.z)), and the
	# basis has to be normalized because the boss carries a large model scale.
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return results
	forward = forward.normalized()

	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("myrs"))
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		if candidate.is_in_group("player") and "is_downed" in candidate and candidate.is_downed:
			continue
		var offset: Vector3 = (candidate as Node3D).global_position - global_position
		offset.y = 0.0
		if offset.length() > radius:
			continue
		if is_cone and offset.length_squared() > 0.0001:
			if forward.angle_to(offset.normalized()) > half_angle:
				continue
		results.append(candidate as Node3D)
	return results

func _is_player_within(distance: float) -> bool:
	for player in get_tree().get_nodes_in_group("player"):
		if player is Node3D and is_instance_valid(player):
			if global_position.distance_to((player as Node3D).global_position) <= distance:
				return true
	return false

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

func _cancel_special() -> void:
	if _special_indicator and is_instance_valid(_special_indicator):
		_special_indicator.cancel()
	_special_indicator = null
	_is_special_active = false

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
			var revived_data: EnemyData = EnemyDatabase.get_enemy_data("Black", "Ranged")
			var enemy_scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
			var new_enemy: Node3D = enemy_scene.instantiate()
			new_enemy.position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			new_enemy.set_meta("target_crystal", target_crystal)
			get_parent().add_child(new_enemy)
			new_enemy.setup(revived_data)
			new_enemy.health = revived_data.health * GameSettings.enemy_black_mage_revive_hp_mult * power
			var wm: Node = get_tree().current_scene.get_node_or_null("WaveManager")
			if wm:
				wm.register_enemy()
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
			var revived_data = EnemyDatabase.get_enemy_data("Black", "Melee")
			var enemy_scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
			var new_enemy = enemy_scene.instantiate()
			new_enemy.position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			new_enemy.set_meta("target_crystal", target_crystal)
			get_parent().add_child(new_enemy)
			# Needs to be setup after adding to tree usually, but we can call setup directly
			new_enemy.setup(revived_data)
			new_enemy.health = revived_data.health * GameSettings.enemy_black_mage_revive_hp_mult
			var wm = get_tree().current_scene.get_node_or_null("WaveManager")
			if wm:
				wm.register_enemy()
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


## The per-special-INDEX cooldown multiplier for whichever modifier is active. Index 0 is
## always the big area special and index 1 the short-range melee one across every colour's
## BossDatabase.SPECIALS entry (boss_specials.gd's "has exactly one crystal-breaker" check
## is what keeps that true) - Cataclysm and Bloodthirst read that ordering directly rather
## than searching for hits_crystal themselves.
func _boss_modifier_cooldown_mult(index: int) -> float:
	match boss_modifier:
		"Riot":
			return GameSettings.boss_modifier_riot_cooldown_mult
		"Annihilator":
			return GameSettings.boss_modifier_annihilator_cooldown_mult
		"Cataclysm":
			return GameSettings.boss_modifier_cataclysm_big_cooldown_mult if index == 0 else GameSettings.boss_modifier_cataclysm_melee_cooldown_mult
		"Bloodthirst":
			return GameSettings.boss_modifier_bloodthirst_big_cooldown_mult if index == 0 else GameSettings.boss_modifier_bloodthirst_melee_cooldown_mult
		"Enrage":
			return GameSettings.boss_modifier_enrage_cooldown_mult if _enrage_active else 1.0
	return 1.0


func _boss_modifier_radius_mult() -> float:
	if boss_modifier == "Annihilator":
		return GameSettings.boss_modifier_annihilator_radius_mult
	return 1.0


## Enrage's damage step, applied once the first time it latches - see _check_boss_enrage.
## Kept separate from apply_boss_modifier because it fires mid-fight, not at spawn.
func _boss_modifier_enrage_damage_mult() -> float:
	return GameSettings.boss_modifier_enrage_damage_mult if boss_modifier == "Enrage" and _enrage_active else 1.0


## The classic "phase 2": latches the FIRST time health crosses the threshold and never
## reverts, same one-way philosophy the squad system already uses for breaking ranks -
## flickering in and out at the threshold would read as a bug, not a mechanic. Called from
## take_damage() right after health drops, rather than polled every frame, since that is
## the one moment the answer can actually change.
func _check_boss_enrage() -> void:
	if boss_modifier != "Enrage" or _enrage_active or enemy_data == null:
		return
	if health <= enemy_data.health * GameSettings.boss_modifier_enrage_health_threshold:
		_enrage_active = true
		enemy_data.attack_damage *= GameSettings.boss_modifier_enrage_damage_mult


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
func take_damage(amount: float, source: Node3D = null, _is_melee: bool = false, exile_on_kill: bool = false) -> void:
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
	var damage_dealt: float = minf(maxf(amount, 0.0), maxf(health, 0.0))
	health -= amount
	if boss_modifier == "Enrage":
		_check_boss_enrage()
	if damage_dealt > 0.0 and is_instance_valid(source) and source.has_method("on_damage_dealt"):
		source.on_damage_dealt(damage_dealt)
	if health_bar and enemy_data:
		health_bar.set_health(health, enemy_data.health)
	var spawn_pos = global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	NetFx.damage_number(spawn_pos, amount, Color(1.0, 0.95, 0.2), "")
	if health <= 0.0:
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
	# The slot goes back before anything else happens: a corpse holds one for the couple of
	# seconds its death animation runs, and a squad measuring its march speed off a dead
	# mage would keep walking at the dead mage's pace.
	leave_formation()
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
		RunState.on_enemy_killed(enemy_data, elite_modifier != "")

	# Dying mid-windup drops the telegraph without dealing its damage - and the same
	# goes for an ordinary swing whose impact frame has not arrived yet.
	_cancel_special()
	_cancel_miniboss_special()
	_impact_timer = -1.0
	_hit_react_timer = 0.0

	if visual_anim_player and visual_anim_player.has_animation("death"):
		_log_death_animation_debug("play_requested", death_debug_before)
		is_dying = true
		collision_layer = 0
		collision_mask = 0
		remove_from_group("enemies")
		if health_bar:
			health_bar.visible = false
		var death_anim: Animation = visual_anim_player.get_animation("death")
		var death_speed: float = maxf(_anim_speed_scale, 0.05)
		if death_anim and death_anim.length / death_speed > DEATH_MAX_SECONDS:
			death_speed = death_anim.length / DEATH_MAX_SECONDS
		visual_anim_player.play("death", -1, death_speed)
		call_deferred("_check_death_animation_started", death_speed)
		_register_corpse()
	else:
		push_warning("Enemy death animation unavailable: %s" % _format_death_animation_debug(death_debug_before))
		queue_free()


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

func apply_blind(duration: float) -> void:
	blind_timer = duration

## Vulnerability: this enemy takes `mult` times damage for `duration`. Wall of Souls' mark
## (black_4) and Fear's flee window (black_2) both land here.
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

## Fear (black_2). The enemy turns and runs from `origin` for `duration`, attacking
## nothing on the way. This is the colour's answer to being surrounded, so it has to
## actually create distance rather than only stopping the attacks - which is why it
## moves the body instead of setting `pacified_timer`.
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


## Kill (black_3) and Exalted Strike (white_1). Removes the enemy WITHOUT leaving a
## corpse - which is a real mechanical difference and not only flavour: corpses are kept
## in the scene up to a cap and are what black's Zombify raises. Exiling denies that.
func exile() -> void:
	if is_dying:
		return
	if enemy_data:
		SignalBus.enemy_died.emit()
		SignalBus.enemy_died_at.emit(global_position)
		RunState.on_enemy_killed(enemy_data, elite_modifier != "")
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
