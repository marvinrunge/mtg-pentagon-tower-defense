extends Node

# amount can be negative to represent healing
signal crystal_damaged(amount: float)
signal mana_deposited(color: String, amount: int)

signal health_changed(current: float, max_health: float)
signal player_health_changed(current_health: float, max_health: float)
signal mana_changed(mana_pool: Dictionary)
signal game_over()

signal enemy_died()
## Where it died. `enemy_died` carries nothing, which is enough for a counter and not
## enough for anything that happens AT the corpse - black's Grave Pact pays out only for
## kills near the player, so it needs the position that the plain signal throws away.
signal enemy_died_at(position: Vector3)
signal skill_unlocked(color: String)
signal spell_unlocked(color: String, spell_id: String)
## The colourless skill-tree node at the centre of the pentagon: lengthens the
## player's light attack chain from two stages to three.
signal melee_combo_unlocked()
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
## The build phase between waves. `upkeep_finished` is what actually starts the next
## wave, so nothing else may emit it.
signal upkeep_started(duration: float)
signal upkeep_finished()
## Team level went up, granting `levels_gained` skill points to every player.
signal team_level_changed(level: int, levels_gained: int)
signal skill_points_changed(player: Node, points: int)
signal enchantment_changed(color: String, stacks: int)
## A player joined or left the run.
signal players_changed(count: int)

signal interact_prompt_changed(text: String, visible: bool)
signal damage_number_requested(pos: Vector3, amount: float, color: Color)
signal enemy_health_bars_visibility_changed(is_enabled: bool)

# strength is in world units of camera offset; the player applies it to its own
# camera, so listeners other than the local player should ignore it.
signal camera_shake_requested(strength: float, duration: float)
signal attack_indicators_visibility_changed(is_enabled: bool)
