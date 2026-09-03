extends Node

# ============================================================
# MAP
# ============================================================
@export var map_base_radius: float = 50.0

# ============================================================
# CRYSTAL
# ============================================================
@export var crystal_max_hp: float = 1000.0

# ============================================================
# PLAYER
# ============================================================
@export var player_max_hp: float = 100.0
## How many players the map spawns. 1 is single-player; the lobby will set this once
## Phase 1 of docs/MULTIPLAYER_PLAN.md lands. Everything downstream already scales -
## enemy damage, target selection and the Upkeep vote threshold all read the count.
@export var player_count: int = 1
@export var player_base_speed: float = 6.0
@export var player_sprint_speed_mult: float = 1.5
@export var player_jump_velocity: float = 4.5
@export var player_mouse_sensitivity: float = 0.002
@export var player_gamepad_look_sensitivity: float = 2.5
## Myrs only. The player no longer harvests: mana banks automatically on kill, because
## the pool is the team's and there is nobody for a pickup to belong to. Walking a well
## round trip used to cost the player ~40 seconds for a single mana.
@export var player_mana_harvest_distance: float = 6.0
@export var player_mana_harvest_time: float = 3.0
@export var player_base_proximity: float = 5.0
## Myrs only, for the same reason - the player never carries anything now.
@export var player_carry_speed_penalty: float = 0.5
@export var player_base_hp_regen: float = 1.0

# ============================================================
# PLAYER CAMERA
# ============================================================
## Classic over-the-shoulder third person. The offset shifts the whole orbit to the
## player's right so the character sits left of screen centre and the aim line stays
## clear; the height is the point the camera orbits around; the distance is the
## SpringArm3D's length, which still shortens automatically when geometry gets
## between the camera and the player.
##
## Pulled in from 4.5 on 2026-08-30. The offset and height are not guesses: 0.85 at
## 3.2 reproduces the 15-degree off-axis angle the old 1.2-at-4.5 rig framed the
## character with, and 1.80 is what that rig's orbit height actually was once the
## spring arm's own hidden +0.2 is folded in. So this is the same shot, just nearer.
@export var player_camera_shoulder_offset: float = 0.85
@export var player_camera_height: float = 1.80
@export var player_camera_distance: float = 3.2

# ============================================================
# PLAYER ANIMATION
# ============================================================
## Seconds of uninterrupted standing still before the player plays one of the
## "idle looking" variations instead of the plain idle loop.
@export var player_idle_variation_delay_min: float = 8.0
@export var player_idle_variation_delay_max: float = 16.0
## How far a locomotion clip may be sped up or slowed down to match real velocity
## before the feet start reading as skating either way.
@export var player_locomotion_speed_min: float = 0.6
@export var player_locomotion_speed_max: float = 1.8
## Cross-fade lengths. Locomotion changes often, so it gets the longer blend;
## a strike has to land on the frame it says it does.
@export var player_anim_blend_locomotion: float = 0.16
## Long enough that one swing chaining into the next reads as a blend rather than a
## snap, short enough that a strike still lands on the frame it says it does.
@export var player_anim_blend_action: float = 0.12

# ============================================================
# PLAYER MELEE COMBO
# ============================================================
## One stage of the light attack chain occupies this long; the stage is speed-scaled
## onto it, so a full chain runs one of these per click regardless of how the clip
## splits up.
@export var player_swing_duration: float = 0.5
## Swings fire when the attack button is RELEASED. A release before this counts as a
## tap and swings light; at or after it, heavy. Nothing is in flight while the button
## is down, so unlike the old fire-on-press scheme this has no upper bound tied to
## the swing's impact frame - it only has to be long enough that a deliberate tap
## does not overshoot it.
@export var player_heavy_hold_time: float = 0.25
## How long a resolved swing waits for the combo window to open before it is dropped.
## Without this, releasing a fraction too early is silently ignored and the chain
## feels like it is eating inputs.
@export var player_attack_buffer_time: float = 0.25
## The last FRACTION of a swing during which another attack chains instead of being
## dropped. Every chained swing cuts the one before it short at exactly this point,
## so a wide window throws the follow-through away on every hit of a combo: at 0.5
## the swing was cut the instant it landed, which read as the animations being
## truncated. 0.3 lets ~70% of each swing play. It costs nothing in feel because
## player_attack_buffer_time already holds an early release until the window opens.
@export var player_combo_window: float = 0.30
## SECONDS after a swing ends that the recorded combo symbols survive. Kept separate
## from player_combo_window, which is a fraction - the two used to be added together,
## mixing units.
@export var player_combo_grace: float = 0.45
## The heavy attack is a full 360 spin (1.22s of usable clip) rather than a single
## chop, so it gets its own, longer commitment instead of the light chain's cadence.
@export var player_heavy_duration: float = 0.9
## How long the heavy's wind-up can be held before it goes off on its own. The clip's
## whole discarded lead-in is stretched across this, so a full charge is a slow raise
## rather than a pose that snapped into place and then froze. Releasing early fires
## early; the strike that follows is identical either way, so this buys the player
## nothing but the timing.
@export var player_heavy_charge_max: float = 1.0
## How front-loaded the raise is inside that window. The wind-up's playback rate is
## the derivative of `1 - (1 - t)^this`, so at 3.0 the axe comes up three times faster
## than a flat rate at the start and has all but settled by two thirds through - which
## is what a wind-up being HELD should feel like, rather than one steady crawl. 1.0 is
## exactly the old flat rate; higher snaps harder and holds longer. The raise still
## finishes exactly as the charge does, whatever this is set to.
@export var player_heavy_charge_ease: float = 3.0
@export var player_heavy_damage_mult: float = 1.6
## Damage multiplier on the THIRD stage of the light chain, which only exists once
## the chain extension has been bought in the skill tree.
@export var player_combo_finisher_damage_mult: float = 1.5
## Skill points the tree charges for that extension.
@export var skill_point_cost_melee_combo: int = 3
## Legacy mana price, kept only so old saves and the tree's display do not break.
@export var melee_combo_unlock_cost: int = 12
## Seconds taken off every spell cooldown by each melee impact frame that connects.
## This is the melee/spell interlock: swinging between casts brings them back faster.
## Paid per impact frame, so a stage that lands two of them refunds twice over. A
## whiff refunds nothing. The kick's own cooldown is never refunded (see
## Player._reduce_spell_cooldowns).
@export var melee_hit_cooldown_reduction: float = 0.35

## Movement multiplier during a light attack STARTED ON THE MOVE, which is the only
## melee move the player can walk through - it plays on the upper body while the legs
## keep their walk cycle. A light attack started standing still takes the whole body
## and holds the player there instead, as do heavy attacks, kicks and staggers (see
## Player._advance_light_chain and Player._begin_action).
@export var player_attack_move_mult: float = 1.0

# ============================================================
# SOUND EFFECTS
# ============================================================
## Voices SoundBank keeps alive. Positional ones carry world impacts; the flat ones
## are for the few events with no place on the map. A wave lands far more hits than
## this per second, but they overlap for a fraction of a second each - the pool only
## has to cover that overlap, and the oldest voice is recycled past it.
@export var sfx_positional_voices: int = 16
@export var sfx_flat_voices: int = 4
@export var sfx_volume_db: float = -6.0
## Random detune either side of 1.0, so a handful of recordings survive being heard
## thousands of times without reading as a loop.
@export var sfx_pitch_jitter: float = 0.08
## Minimum gap between two triggers of the SAME event. Thirty enemies connecting on
## one frame is one impact sound, not thirty stacked into a clipping mess.
@export var sfx_min_retrigger: float = 0.05
## Beyond this the sound is inaudible; unit_size sets how quickly it falls off on
## the way there.
@export var sfx_max_distance: float = 45.0
@export var sfx_unit_size: float = 8.0
## A sustained ambience sits under the action rather than in it, so it is quieter
## than an impact - but it carries further, because it is what tells the player
## where the crystal is from across the map.
@export var sfx_ambience_volume_db: float = -14.0
@export var sfx_ambience_max_distance: float = 70.0

## The kick a fireball detonation gives the camera. Still under the leap's slam - a
## fireball usually goes off across the map rather than under the player's feet - but
## well above a melee hit, because it is a detonation and should read as one.
@export var spell_red_fireball_shake_strength: float = 0.45
@export var spell_red_fireball_shake_duration: float = 0.35

# ============================================================
# GREEN: TITANIC LEAP
# ============================================================
## The launch impulse. Forward speed decides how far the leap carries; the rise is
## tuned against the clip rather than to taste - the jump_attack clip lands its slam
## at 79% of a 1.1s cast, i.e. 0.87s in, and at the engine's 9.8 gravity an initial
## 4.25/s puts the character back on the floor at exactly that moment. Retune it
## alongside spell green_1's cast_duration, never on its own.
@export var spell_green_leap_speed: float = 11.0
@export var spell_green_leap_rise: float = 4.25
## How long the player's own movement input stays suspended. Ends early at the slam.
@export var spell_green_leap_duration: float = 1.1
## The slam. Heavy single-target damage spread over an area, which is what makes it
## worth a leap rather than a swing.
@export var spell_green_leap_damage: float = 90.0
@export var spell_green_leap_radius: float = 6.0
@export var spell_green_leap_knockback: float = 12.0
## The hardest shake in the game, and the only one the player lands on themselves:
## the slam happens directly under the camera, so it can carry more than a detonation
## going off at range without reading as a glitch.
@export var spell_green_leap_shake_strength: float = 0.75
@export var spell_green_leap_shake_duration: float = 0.45

# ============================================================
# PLAYER KICK
# ============================================================
@export var spell_melee_kick_damage: float = 12.0
@export var spell_melee_kick_range: float = 2.6
@export var spell_melee_kick_knockback: float = 14.0
@export var spell_cooldown_kick: float = 1.5

# ============================================================
# PLAYER BLOCK
# ============================================================
## Fraction of incoming damage a successful block removes.
@export var player_block_damage_reduction: float = 0.8
## Minimum dot() between the player's facing and the direction to the attacker for
## a hit to count as coming from the front. 0.35 is roughly a 140-degree arc.
@export var player_block_cone: float = 0.35
@export var player_block_speed_mult: float = 0.4
## Bosses swing straight through a guard - blocking one does nothing.
@export var player_block_ignores_boss: bool = true
## How long the guard-flinch clip is squeezed into. Does not take control away -
## the player keeps blocking through it.
@export var player_block_react_duration: float = 0.35

# ============================================================
# PLAYER HIT REACTION
# ============================================================
## A hit only staggers the player when it takes at least this fraction of max HP in
## one go; chip damage would otherwise leave the character permanently flinching.
@export var player_hit_react_damage_pct: float = 0.12
## Minimum gap between staggers, so a burst of large hits can't lock the player out.
@export var player_hit_react_cooldown: float = 1.2
## How long a stagger takes control away. The raw reaction clips run 1.0-1.8s,
## which would be punishing; they get squeezed into this instead.
@export var player_hit_react_duration: float = 0.55

# ============================================================
# PLAYER SPELLS
# ============================================================
@export var spell_melee_range: float = 3.5
@export var spell_melee_cone: float = 0.5
@export var spell_melee_damage: float = 20.0
@export var spell_melee_knockback: float = 6.0
@export var spell_cooldown_melee: float = 0.5
@export var spell_giant_duration: float = 5.0
@export var spell_giant_scale: float = 1.5
@export var spell_giant_damage: float = 40.0
@export var skill_unlock_cost: int = 1
@export var spell_heal_amount: float = 50.0
@export var spell_stab_range: float = 10.0
@export var spell_stab_execute_threshold: float = 50.0
@export var spell_stab_debuff_damage: float = 5.0
@export var spell_stab_debuff_duration: float = 8.0
@export var spell_unsummon_teleport_distance: float = 15.0

# Infinite color affinity ranks. Rank 1-10 grants 2% each, 11-20 grants
# 1% each, and every rank after 20 grants 0.5%.
@export var affinity_rank_mana_cost: int = 1
@export var affinity_rank_bonus_early: float = 0.02
@export var affinity_rank_bonus_mid: float = 0.01
@export var affinity_rank_bonus_late: float = 0.005
@export var affinity_spell_rank_requirements: Array[int] = [1, 5, 10, 15, 25]

# Per-spell cooldowns moved to scripts/spell_database.gd, which owns one row per
# spell. Tier costs stay here: they are shared tuning, not per-spell data.

# --- MTG 5-Color Tier Costs ---
const TIER_COSTS: Array[int] = [1, 3, 7, 15, 30, 50]

func get_tier_cost(tier_index: int) -> int:
	if tier_index >= 0 and tier_index < TIER_COSTS.size():
		return TIER_COSTS[tier_index]
	return 1

# --- RED SKILLS ---
@export var spell_red_shock_damage: float = 70.0
@export var spell_red_shock_chain_damage_mult: float = 0.6
@export var spell_red_fireball_max_charge: float = 2.0
@export var spell_red_fireball_base_radius: float = 3.0
@export var spell_red_fireball_base_damage: float = 60.0
@export var spell_red_rain_ember_duration: float = 5.0
@export var spell_red_rain_ember_radius: float = 6.0
@export var spell_red_rain_ember_dps: float = 25.0
@export var spell_red_act_of_treason_damage: float = 70.0
@export var spell_red_act_of_treason_knockback: float = 12.0
@export var spell_red_act_of_treason_stun: float = 2.0
@export var spell_red_chandras_ignition_radius: float = 8.0
@export var spell_red_chandras_ignition_damage: float = 120.0
@export var spell_red_chandras_ignition_push: float = 15.0
@export var aura_fervor_speed_boost: float = 1.15

# --- BLUE SKILLS ---
@export var spell_blue_unsummon_knockback: float = 14.0
@export var spell_blue_unsummon_damage: float = 35.0
@export var spell_blue_unsummon_impact_damage: float = 80.0
@export var spell_blue_aetherize_max_charge: float = 2.0
@export var spell_blue_aetherize_cone_angle: float = 60.0
@export var spell_blue_aetherize_push_force: float = 18.0
@export var spell_blue_psionic_blast_damage: float = 100.0
@export var spell_blue_psionic_blast_self_damage: float = 10.0
@export var spell_blue_freeze_breath_chill_duration: float = 5.0
@export var spell_blue_freeze_breath_shatter_damage: float = 90.0
@export var spell_blue_freeze_breath_shatter_radius: float = 4.0
@export var spell_blue_counterspell_duration: float = 1.5
@export var aura_rhystic_study_cdr_mult: float = 0.7
@export var aura_rhystic_study_shield_amount: float = 15.0
@export var aura_rhystic_study_shield_max: float = 45.0

# --- GREEN SKILLS ---
@export var spell_green_titanic_growth_hp_scaling: float = 0.35
@export var spell_green_titanic_growth_cone: float = 4.0
@export var spell_green_hurricane_max_charge: float = 2.0
@export var spell_green_hurricane_radius: float = 7.0
@export var spell_green_hurricane_root_duration: float = 3.0
@export var spell_green_hurricane_poison_dps: float = 20.0
@export var spell_green_overrun_dash_speed: float = 20.0
@export var spell_green_overrun_dash_duration: float = 0.6
@export var spell_green_overrun_damage_mult: float = 3.0
@export var spell_green_rabid_bite_damage: float = 75.0
@export var spell_green_rabid_bite_lifesteal: float = 0.5
@export var spell_green_briar_patch_reflect: float = 0.3
@export var aura_sylvan_library_hp_mult: float = 1.35
@export var aura_sylvan_library_regen: float = 3.0

# --- WHITE SKILLS ---
@export var spell_white_swords_exile_pct: float = 0.5
@export var spell_white_swords_damage_cap: float = 120.0
@export var spell_white_swords_ally_heal: float = 60.0
@export var spell_white_path_to_exile_max_charge: float = 2.0
@export var spell_white_path_to_exile_exec_mult: float = 0.5
@export var spell_white_wrath_max_charge: float = 2.0
@export var spell_white_wrath_radius: float = 10.0
@export var spell_white_wrath_damage_pct: float = 0.25
@export var spell_white_wrath_heal: float = 75.0
@export var spell_white_pacifism_duration: float = 6.0
@export var spell_white_pacifism_debuff_mult: float = 0.5
@export var spell_white_gideons_reproach_reflect_pct: float = 0.4
@export var aura_glorious_anthem_shield: float = 35.0
@export var aura_glorious_anthem_damage_mult: float = 1.15

# --- BLACK SKILLS ---
@export var spell_black_drain_life_damage: float = 70.0
@export var spell_black_drain_life_lifesteal: float = 0.65
@export var spell_black_toxic_deluge_max_charge: float = 2.0
@export var spell_black_toxic_deluge_radius: float = 7.0
@export var spell_black_toxic_deluge_hp_cost_pct: float = 0.2
@export var spell_black_toxic_deluge_dps: float = 30.0
@export var spell_black_toxic_deluge_duration: float = 5.0
@export var spell_black_doom_blade_damage: float = 80.0
@export var spell_black_doom_blade_curse_mult: float = 1.3
@export var spell_black_doom_blade_curse_duration: float = 6.0
@export var spell_black_tendrils_damage: float = 45.0
@export var spell_black_sign_in_blood_hp_cost_pct: float = 0.15
@export var aura_phyrexian_arena_hp_drain_pct: float = 0.015
@export var aura_phyrexian_arena_damage_mult: float = 1.25
@export var aura_phyrexian_arena_speed_mult: float = 1.15

# ============================================================
# WAVES
# ============================================================
@export var wave_initial_warning_time: float = 2.5
@export var wave_delay_between_colors: float = 3.5
## Superseded by upkeep_duration - kept only as the pause before the very first wave.
@export var wave_rest_period: float = 3.0
@export var wave_spawn_delay_base: float = 1.0
@export var wave_spawn_delay_scaling: float = 0.05
@export var wave_spawn_delay_min: float = 0.1
## How much bigger a wave gets per player beyond the first. Enemy DAMAGE already scales
## with head count (get_player_scaling_factor), but wave SIZE never did - five players
## against a solo-sized wave shred it without the crystal ever being threatened, and earn
## solo-sized income while doing it. At 0.45 a five-player wave is 2.8x a solo one.
@export var wave_size_per_extra_player: float = 0.45
## Extra enemy health per player beyond the first. 0.15 gives 1.6x at five players.
@export var enemy_health_per_extra_player: float = 0.15
@export var wave_dynamic_base_difficulty: int = 5
@export var wave_dynamic_difficulty_per_wave: int = 2
@export var wave_boss_interval: int = 5
@export var wave_boss_delay: float = 2.0
@export var wave_elite_start_wave: int = 2
@export var wave_elite_count_base: int = 1

# ============================================================
# ENEMIES
# ============================================================
@export var enemy_aggro_radius: float = 12.0
## How much further than its own attack range an enemy may still connect at the
## moment its swing actually lands. Damage now pays out on the clip's measured
## impact frame rather than on the frame the swing started, so a target that walks
## away during the wind-up escapes it - this is the forgiveness on that. Set it very
## high to go back to the old "committed swings always hit" behaviour.
@export var enemy_attack_impact_range_grace: float = 1.35
## How fast an enemy swings its facing around, in lerp weight per second.
@export var enemy_turn_speed: float = 8.0

# --- enemy hit reaction ---
# Every enemy library ships a flinch clip, but until 2026-09-02 it only ever played
# while knockback was still carrying the body - so anything killed at range, which is
# most of what a Mage or Ranged enemy ever takes, never visibly reacted at all.
## A hit only flinches an enemy when it takes at least this fraction of its maximum
## health in one go; chip damage would otherwise leave a wave permanently twitching.
@export var enemy_hit_react_damage_pct: float = 0.08
## Minimum gap between two flinches, so a fast weapon cannot chain them.
@export var enemy_hit_react_cooldown: float = 1.0
## How long the flinch takes; the clip is squeezed into it the same way the player's
## reactions are.
@export var enemy_hit_react_duration: float = 0.4
## Whether a flinch also throws away the swing in flight. True is what "getting hit"
## normally means, and the cooldown above is what keeps it from becoming a stunlock -
## set false to make flinches purely cosmetic and leave the old balance untouched.
@export var enemy_hit_react_interrupts_attack: bool = true
@export var enemy_melee_detection_range: float = 15.0
@export var enemy_ranged_detection_range: float = 35.0
@export var enemy_target_eval_interval: float = 0.5
@export var enemy_path_update_interval: float = 0.3
@export var enemy_mage_spell_cooldown_mult: float = 4.0
@export var enemy_frost_slow_mult: float = 0.3
@export var enemy_white_mage_heal: float = 30.0
@export var enemy_white_mage_range: float = 15.0
@export var enemy_red_mage_range: float = 20.0
@export var enemy_blue_mage_range: float = 20.0
@export var enemy_blue_mage_slow_duration: float = 4.0
@export var enemy_blue_mage_slow_mult: float = 0.6
@export var enemy_green_mage_range: float = 10.0
@export var enemy_green_mage_buff_scale: float = 1.5
@export var enemy_green_mage_buff_damage: float = 1.5
@export var enemy_black_mage_revive_hp_mult: float = 0.5
@export var enemy_elite_haste_speed_mult: float = 1.3
@export var enemy_elite_haste_attack_speed_mult: float = 0.75
@export var enemy_elite_regenerator_health_mult: float = 1.25
@export var enemy_elite_regenerator_heal_pct_per_second: float = 0.025
@export var enemy_elite_juggernaut_health_mult: float = 1.6
@export var enemy_elite_juggernaut_damage_mult: float = 1.25
@export var enemy_elite_juggernaut_speed_mult: float = 0.8
@export var enemy_elite_crystal_hunter_damage_mult: float = 1.35
@export var enemy_max_corpses: int = 100

# ============================================================
# BOSSES
# ============================================================
# Bosses animate slower the bigger they are: a boss whose model_scale equals
# boss_anim_reference_scale plays at 1.0x, larger ones play slower and smaller
# ones faster. boss_anim_scale_strength dials how strongly size matters (0.0
# disables the effect entirely, 1.0 makes playback speed inversely proportional
# to scale). Result is clamped so a very large boss never crawls to a halt.
@export var boss_anim_reference_scale: float = 2.4
@export var boss_anim_scale_strength: float = 1.0
@export var boss_anim_speed_min: float = 0.55
@export var boss_anim_speed_max: float = 1.35

# Special (dodgeable) attacks. Each boss telegraphs a danger zone for
# boss_special_windup_* seconds before the hit lands - that window is the dodge.
@export var boss_special_cooldown: float = 9.0
@export var boss_special_first_delay: float = 5.0
@export var boss_special_min_range: float = 3.0
@export var boss_special_damage_mult: float = 2.0
# Bigger bosses wind up proportionally longer (they also animate slower), so the
# telegraph stays readable instead of the hit landing before the animation reads.
@export var boss_special_windup_scale_with_anim: bool = true

# ============================================================
# COMBAT FEEDBACK
# ============================================================
# Ground decals marking a boss special attack's danger zone during its windup.
# Turning this off removes the visual tell, making specials much harder to dodge.
@export var show_attack_indicators: bool = true
@export var attack_indicator_height: float = 0.08
@export var camera_shake_enabled: bool = true
@export var camera_shake_strength_mult: float = 1.0
# Heavy hits (boss melee and boss specials) shake harder than chip damage.
@export var camera_shake_heavy_strength: float = 0.42
@export var camera_shake_heavy_duration: float = 0.45
@export var camera_shake_light_strength: float = 0.12
@export var camera_shake_light_duration: float = 0.22
@export var camera_shake_frequency: float = 26.0
## The player's own melee connecting. Much smaller than being hit: this fires on every
## landed swing, several times a second through a chain, so anything larger reads as
## the camera being broken rather than as weight.
@export var camera_shake_melee_strength: float = 0.09
## The heavy spin and the chain's third stage, which land far less often.
@export var camera_shake_melee_heavy_strength: float = 0.2
@export var camera_shake_melee_duration: float = 0.16

# ============================================================
# RUN REWARDS
# ============================================================
# ============================================================
# XP, LEVELS AND SKILL POINTS
# ============================================================
## XP is shared by the whole team and every kill feeds one pool, so levels arrive for
## everyone at the same moment. Each level grants every player one skill point.
@export var xp_per_basic: float = 10.0
@export var xp_per_elite: float = 40.0
@export var xp_per_boss: float = 250.0
@export var xp_per_camp: float = 120.0
## Total XP to reach level N is base*(N-1) + growth*(N-1)^2 - superlinear, so early
## levels land every wave or two and late ones take three or four. Target is roughly
## 15-18 levels across a full run.
@export var xp_level_base: float = 90.0
@export var xp_level_growth: float = 26.0

# ============================================================
# TEAM MANA
# ============================================================
## Banked automatically on kill, in the dead enemy's own colour. There is no pickup:
## the pool is shared, so there is nobody for a drop to belong to and no reason to make
## anyone walk to it.
@export var mana_per_basic: int = 1
@export var mana_per_elite: int = 4
@export var mana_per_boss: int = 25
@export var mana_per_camp: int = 12

# ============================================================
# UPKEEP
# ============================================================
## The build phase between waves: the only time mana can be spent, and the one moment
## each wave the whole team is in the same place. Replaces a 3-second rest that was long
## enough for nothing.
## How often the server pushes the economy to clients. Kills arrive far faster than a
## HUD can read, so the pool is flushed at a fixed rate rather than once per enemy.
@export var run_state_sync_interval: float = 0.25
@export var upkeep_duration: float = 30.0
## What the team pays for one skill point FOR EVERY PLAYER, in any colour.
@export var upkeep_skill_point_cost: int = 10
## Crystal repair. The only way to undo leakage, and deliberately a PURCHASE rather than
## an automatic scaling: the crystal is one shared objective whose maximum stays the same
## whether one player is defending it or five, so a team that leaks pays to fix it out of
## the same pool it wanted to spend on enchantments. That trade is the point.
@export var upkeep_crystal_repair_amount: float = 200.0
@export var upkeep_crystal_repair_cost: int = 8

# ============================================================
# ENCHANTMENTS
# ============================================================
## Permanent, stackable, global. Bought at Upkeep in their own colour, which is what
## makes lane choice strategic rather than only tactical.
@export var enchantment_base_cost: int = 8
@export var enchantment_cost_step: int = 6
## Red - Furnace of Rath: every player deals more damage. The benchmark buy.
@export var enchantment_red_damage: float = 0.08
## Blue - Propaganda: enemies attack and cast more slowly. Scales into the late game.
@export var enchantment_blue_attack_slow: float = 0.06
## Black - Exquisite Blood: players heal for a share of the damage they deal. Keeps the
## PLAYERS alive, where white keeps the CRYSTAL alive.
@export var enchantment_black_lifesteal: float = 0.03
## White - Sphere of Safety: enemies near the crystal hurt it less. Does nothing while
## the team is winning; saves the run when they are not.
@export var enchantment_white_reduction: float = 0.08
@export var enchantment_white_radius: float = 2.0
## Green - Overgrowth: all mana income rises. Compounds, so it is a bet on a long run.
@export var enchantment_green_income: float = 0.12

const ENCHANTMENT_NAMES: Dictionary = {
	"White": "Sphere of Safety",
	"Blue": "Propaganda",
	"Black": "Exquisite Blood",
	"Red": "Furnace of Rath",
	"Green": "Overgrowth",
}
const ENCHANTMENT_DESCRIPTIONS: Dictionary = {
	"White": "Enemies near the crystal deal less damage to it",
	"Blue": "All enemies attack and cast more slowly",
	"Black": "Every player heals for a share of the damage they deal",
	"Red": "Every player deals more damage",
	"Green": "All mana income increases",
}


# ============================================================
# MYRS
# ============================================================
@export var myr_max_hp: float = 75.0
@export var myr_speed: float = 2.0
@export var myr_harvest_time: float = 3.0
@export var myr_deposit_time: float = 1.0
@export var myr_mana_cost: int = 2

# ============================================================
# PROJECTILES
# ============================================================
@export var projectile_pool_size: int = 20
@export var projectile_base_speed: float = 30.0
@export var projectile_base_damage: float = 50.0
@export var projectile_base_lifetime: float = 2.5
@export var projectile_shock_speed_mult: float = 1.5
@export var projectile_unsummon_speed_mult: float = 0.8
@export var projectile_enemy_speed_mult: float = 0.5
@export var projectile_enemy_damage_mult: float = 0.2

# ============================================================
# MINIMAP
# ============================================================
@export var minimap_update_interval: float = 0.15

# ============================================================
# UI & DEBUG
# ============================================================
@export var show_damage_numbers: bool = true
## Debug: everything in the skill tree is free and ungated. Costs nothing, requires
## no affinity rank, and spends no mana - for trying builds out without farming them.
## Deliberately not persisted: it resets to off every launch, so it cannot be left on
## by accident. Toggled from the in-game options panel.
@export var debug_free_skills: bool = false
@export var damage_number_pool_size: int = 40
@export var show_enemy_health_bars: bool = true
@export var enemy_health_bar_height: float = 2.35
@export var debug_mode: bool = true

# ============================================================
# MULTIPLAYER SCALING
# ============================================================
@export var scale_by_players: bool = true
## Enemy DAMAGE at one player, rising to 100% at five.
##
## Deliberately shallow. Damage is the worst of the three difficulty levers to lean on,
## because it is the only one that changes what a hit COSTS - at 0.2 a Cleric's swing was
## worth 20% solo and 100% in a full team, so a player could never learn what any attack
## is actually worth; it depended on how many friends had logged in. Worse, with five
## players you are usually alone in your own lane, so it punished the individual for the
## team growing.
##
## The solo assist now comes almost entirely from facing FEWER enemies
## (wave_size_per_extra_player), which is the same help without the side effects. This
## keeps a small cushion on top, because one player genuinely cannot cover five lanes and
## some leakage is unavoidable.
@export var min_damage_scale: float = 0.75

## Multiplier on a wave's enemy budget for the number of players present. Counts the
## registry rather than the group, so an avatar mid-spawn cannot briefly inflate a wave.
##
## The PRIMARY difficulty lever, because it is the only one that uses the map: more
## enemies means more lanes under real pressure at once, which is the entire reason a
## five-player team exists. It also leaves every enemy feeling exactly as it does solo.
func get_wave_size_factor(player_count: int) -> float:
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * wave_size_per_extra_player


## Multiplier on an enemy's maximum health for the number of players present.
##
## The correction that wave size alone cannot make. Count scaling assumes players SPREAD
## OUT - one per lane, each fighting alone, killing at solo speed. The moment they group
## up, on a boss or a collapsing lane, five players focus-fire and delete each enemy
## roughly five times faster, and more enemies does not help with that.
##
## Kept modest on purpose: this is the lever that makes things spongy, and melee suffers
## most from sponginess because every swing is a committed animation.
func get_enemy_health_factor(player_count: int) -> float:
	if not scale_by_players:
		return 1.0
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * enemy_health_per_extra_player


func get_player_scaling_factor(tree: SceneTree) -> float:
	if not scale_by_players:
		return 1.0
	var players = tree.get_nodes_in_group("player")
	var player_count = max(1, players.size())
	var clamp_count = clamp(player_count, 1, 5)
	return lerp(min_damage_scale, 1.0, (clamp_count - 1) / 4.0)

# ============================================================
# BOSSES
# ============================================================
## Animation playback speed for a boss of the given model_scale - bigger bosses
## animate slower. See the boss_anim_* settings for the tunables.
func get_boss_anim_speed(model_scale: float) -> float:
	if boss_anim_scale_strength <= 0.0 or model_scale <= 0.0:
		return 1.0
	var ratio: float = boss_anim_reference_scale / model_scale
	return clampf(pow(ratio, boss_anim_scale_strength), boss_anim_speed_min, boss_anim_speed_max)

# ============================================================
# SKILL UPGRADES
# ============================================================
func get_skill_upgrade_cost(current_level: int) -> int:
	return skill_unlock_cost + (current_level * current_level * 2)

func get_skill_multiplier(current_level: int) -> float:
	return 1.0 + (current_level - 1) * 0.2
