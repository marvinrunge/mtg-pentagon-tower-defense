extends Node

# amount can be negative to represent healing
signal crystal_damaged(amount: float)
signal mana_deposited(color: String, amount: int)

signal health_changed(current: float, max_health: float)
signal player_health_changed(current_health: float, max_health: float)
signal mana_changed(mana_pool: Dictionary)
signal game_over()

signal enemy_died(xp: int)
signal player_leveled_up(level: int, sp: int)
signal xp_changed(current_xp: int, max_xp: int)
signal skill_unlocked(color: String)
signal active_spell_changed(spell_name: String)
signal at_base_changed(is_at_base: bool)
signal enemy_focused(is_focused: bool, enemy_name: String, hp: float, max_hp: float, color: Color)

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)

signal interact_prompt_changed(text: String, visible: bool)
signal damage_number_requested(pos: Vector3, amount: float, color: Color)
