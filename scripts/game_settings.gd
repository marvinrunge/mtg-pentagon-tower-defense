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
@export var player_hp_per_level: float = 10.0
@export var player_xp_base: int = 100
@export var player_xp_scaling: float = 1.2
@export var player_mana_harvest_distance: float = 6.0
@export var player_mana_harvest_time: float = 3.0
@export var player_base_proximity: float = 5.0
@export var player_carry_speed_penalty: float = 0.5

# ============================================================
# PLAYER SPELLS
# ============================================================
@export var spell_melee_range: float = 3.5
@export var spell_melee_cone: float = 0.5
@export var spell_melee_damage: float = 20.0
@export var spell_cooldown_melee: float = 0.5
@export var spell_cooldown_shock: float = 2.0
@export var spell_cooldown_unsummon: float = 3.0
@export var spell_cooldown_giant: float = 15.0
@export var spell_cooldown_heal: float = 10.0
@export var spell_cooldown_stab: float = 5.0
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

# ============================================================
# WAVES
# ============================================================
@export var wave_delay_between_colors: float = 20.0
@export var wave_rest_period: float = 5.0
@export var wave_spawn_delay_base: float = 1.0
@export var wave_spawn_delay_scaling: float = 0.05
@export var wave_spawn_delay_min: float = 0.1
@export var wave_dynamic_base_difficulty: int = 5
@export var wave_dynamic_difficulty_per_wave: int = 2
@export var wave_boss_interval: int = 5
@export var wave_boss_delay: float = 2.0

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
@export var enemy_green_mage_range: float = 10.0
@export var enemy_green_mage_buff_scale: float = 1.5
@export var enemy_green_mage_buff_damage: float = 1.5
@export var enemy_black_mage_revive_hp_mult: float = 0.5


# ============================================================
# MYRS
# ============================================================
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
@export var projectile_shock_damage_mult: float = 2.0
@export var projectile_unsummon_speed_mult: float = 0.8
@export var projectile_enemy_speed_mult: float = 0.5
@export var projectile_enemy_damage_mult: float = 0.2

# ============================================================
# MINIMAP
# ============================================================
@export var minimap_update_interval: float = 0.15

# ============================================================
# UI
# ============================================================
@export var show_damage_numbers: bool = true

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
