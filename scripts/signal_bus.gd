extends Node

# amount can be negative to represent healing
signal crystal_damaged(amount: float)
signal mana_deposited(color: String, amount: int)

signal health_changed(current: float, max_health: float)
signal player_health_changed(current_health: float, max_health: float)
signal mana_changed(mana_pool: Dictionary)
signal game_over()

signal enemy_died()
signal skill_unlocked(color: String)
signal spell_unlocked(color: String, spell_id: String)
signal color_path_chosen(color: String)
signal spell_charge_changed(current_charge: float, max_charge: float, is_charging: bool)
signal status_effect_applied(target: Node3D, effect_type: String, duration: float)
signal active_spell_changed(spell_name: String)
signal player_capstone_aura_changed()
signal at_base_changed(is_at_base: bool)
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal wave_state_changed(wave_number: int, enemies_remaining: int)
signal lane_warning_requested(lane_name: String, message: String, color: Color)
signal wave_reward_offered(options: Array)
signal wave_reward_selected(reward_id: String)

signal interact_prompt_changed(text: String, visible: bool)
signal damage_number_requested(pos: Vector3, amount: float, color: Color)
signal enemy_health_bars_visibility_changed(is_enabled: bool)

# strength is in world units of camera offset; the player applies it to its own
# camera, so listeners other than the local player should ignore it.
signal camera_shake_requested(strength: float, duration: float)
signal attack_indicators_visibility_changed(is_enabled: bool)
