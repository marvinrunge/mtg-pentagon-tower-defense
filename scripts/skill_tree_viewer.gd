extends Node
## Standalone 2D preview scene for inspecting the complete skill tree in Godot.

const SKILL_TREE_SCENE: PackedScene = preload("res://scenes/ui/skill_tree.tscn")

var _preview_player: SkillTreePreviewPlayer


func _ready() -> void:
	RunState.reset()
	RunState.team_level = 25
	_preview_player = SkillTreePreviewPlayer.new()
	_preview_player.name = "SkillTreePreviewPlayer"
	add_child(_preview_player)
	PlayerRegistry.register(_preview_player, true)
	var tree: SkillTree = SKILL_TREE_SCENE.instantiate() as SkillTree
	tree.name = "SkillTree"
	add_child(tree)
	call_deferred("_show_tree", tree)


func _exit_tree() -> void:
	if is_instance_valid(_preview_player):
		PlayerRegistry.unregister(_preview_player)


func _show_tree(tree: SkillTree) -> void:
	tree.show()
	tree.update_ui()
	tree._layout_nodes()


class SkillTreePreviewPlayer extends Node3D:
	var skill_points: int = 99
	var spent_skill_points: int = 0
	var melee_combo_extended: bool = true
	var aura_ranks: Dictionary = {}
	var quick_slots: Array[String] = ["blue_1", "blue_2", "blue_3", "blue_4", "blue_5"]
	var _affinity_ranks: Dictionary = {}
	var _spell_ranks: Dictionary = {}
	var _passive_ranks: Dictionary = {}


	func _init() -> void:
		for color: String in SkillTree.COLOR_NAMES:
			_affinity_ranks[color] = GameSettings.spell_max_rank
			for tier: int in range(1, SpellDatabase.SPELLS_PER_COLOR + 1):
				_spell_ranks[SpellDatabase.make_id(color, tier)] = GameSettings.spell_max_rank
		for passive_id: String in SkillTree.PASSIVE_ORDER:
			_passive_ranks[passive_id] = GameSettings.spell_max_rank
		for color: String in SkillTree.COLOR_NAMES:
			var auras: Array[Dictionary] = SpellDatabase.get_auras(color)
			if not auras.is_empty():
				aura_ranks[String(auras[0]["id"])] = GameSettings.spell_max_rank


	func get_affinity_rank(color: String) -> int:
		return int(_affinity_ranks.get(color, 0))


	func get_affinity_bonus(color: String) -> float:
		return float(get_affinity_rank(color)) * GameSettings.affinity_rank_bonus_base


	func get_spell_rank(spell_id: String) -> int:
		return int(_spell_ranks.get(spell_id, 0))


	func get_passive_rank(passive_id: String) -> int:
		return int(_passive_ranks.get(passive_id, 0))


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


	func spell_rank_blocker(_spell_id: String) -> String:
		return "Maximum rank"


	func color_investment(color: String) -> int:
		var total: int = get_affinity_rank(color)
		for tier: int in range(1, SpellDatabase.SPELLS_PER_COLOR + 1):
			total += get_spell_rank(SpellDatabase.make_id(color, tier))
		return total


	func assign_quick_slot(slot_idx: int, spell_id: String) -> bool:
		if slot_idx < 0 or slot_idx >= quick_slots.size():
			return false
		quick_slots[slot_idx] = spell_id
		SignalBus.quick_slots_changed.emit()
		return true


	func spend_skill_points(amount: int) -> bool:
		if amount <= 0 or skill_points < amount:
			return false
		skill_points -= amount
		spent_skill_points += amount
		SignalBus.skill_points_changed.emit(self, skill_points)
		return true


	func invest_affinity(color: String) -> void:
		_affinity_ranks[color] = get_affinity_rank(color) + 1
		SignalBus.skill_unlocked.emit(color)


	func grant_spell_rank(spell_id: String) -> bool:
		_spell_ranks[spell_id] = get_spell_rank(spell_id) + 1
		SignalBus.spell_rank_changed.emit(spell_id, get_spell_rank(spell_id))
		return true


	func grant_passive_rank(passive_id: String) -> bool:
		_passive_ranks[passive_id] = get_passive_rank(passive_id) + 1
		SignalBus.passive_rank_changed.emit(passive_id, get_passive_rank(passive_id))
		return true


	func get_aura_rank(aura_id: String) -> int:
		return int(aura_ranks.get(aura_id, 0))


	func get_aura_rank_mult(aura_id: String, curve: String = "damage") -> float:
		var rank: int = maxi(get_aura_rank(aura_id), 1)
		match curve:
			"area": return GameSettings.rank_area_mult(rank)
			"duration": return GameSettings.rank_duration_mult(rank)
			_: return GameSettings.rank_damage_mult(rank)


	func has_aura(aura_id: String) -> bool:
		return get_aura_rank(aura_id) > 0


	func grant_aura_rank(aura_id: String) -> bool:
		if get_aura_rank(aura_id) >= GameSettings.spell_max_rank:
			return false
		aura_ranks[aura_id] = get_aura_rank(aura_id) + 1
		return true


	func grant_aura_rank(aura_id: String) -> void:
		grant_aura_rank(aura_id)
