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
@export var player_base_speed: float = 6.0
@export var player_sprint_speed_mult: float = 1.5
@export var player_jump_velocity: float = 4.5
@export var player_mouse_sensitivity: float = 0.002
@export var player_mana_harvest_distance: float = 6.0
@export var player_mana_harvest_time: float = 3.0
@export var player_base_proximity: float = 5.0
@export var player_carry_speed_penalty: float = 0.5
@export var player_base_hp_regen: float = 1.0

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

const SPELL_COOLDOWNS: Dictionary = {
	"basic_attack": 0.5,
	"red_1": 2.5,
	"red_2": 5.0,
	"red_3": 9.0,
	"red_4": 7.0,
	"red_5": 11.0,
	"blue_1": 3.0,
	"blue_2": 7.0,
	"blue_3": 6.0,
	"blue_4": 4.5,
	"blue_5": 14.0,
	"green_1": 2.0,
	"green_2": 8.0,
	"green_3": 7.0,
	"green_4": 6.0,
	"green_5": 16.0,
	"white_1": 4.5,
	"white_2": 8.0,
	"white_3": 18.0,
	"white_4": 10.0,
	"white_5": 14.0,
	"black_1": 4.0,
	"black_2": 10.0,
	"black_3": 7.0,
	"black_4": 8.0,
	"black_5": 20.0,
}

func get_spell_cooldown(spell_id: String) -> float:
	return float(SPELL_COOLDOWNS.get(spell_id, 1.0))

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
@export var wave_rest_period: float = 3.0
@export var wave_spawn_delay_base: float = 1.0
@export var wave_spawn_delay_scaling: float = 0.05
@export var wave_spawn_delay_min: float = 0.1
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

# ============================================================
# RUN REWARDS
# ============================================================
@export var reward_power_surge_damage_mult: float = 1.15
@export var reward_arcane_tempo_recovery_mult: float = 1.12
@export var reward_crystal_repair_amount: float = 150.0


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
@export var show_enemy_health_bars: bool = true
@export var enemy_health_bar_height: float = 2.35
@export var debug_mode: bool = true

# ============================================================
# MULTIPLAYER SCALING
# ============================================================
@export var scale_by_players: bool = true
@export var min_damage_scale: float = 0.2 # 20% damage at 1 player, scaling up to 100% at 5 players

func get_player_scaling_factor(tree: SceneTree) -> float:
	if not scale_by_players:
		return 1.0
	var players = tree.get_nodes_in_group("player")
	var player_count = max(1, players.size())
	var clamp_count = clamp(player_count, 1, 5)
	return lerp(min_damage_scale, 1.0, (clamp_count - 1) / 4.0)

# ============================================================
# SKILL UPGRADES
# ============================================================
func get_skill_upgrade_cost(current_level: int) -> int:
	return skill_unlock_cost + (current_level * current_level * 2)

func get_skill_multiplier(current_level: int) -> float:
	return 1.0 + (current_level - 1) * 0.2
