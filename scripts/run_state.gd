extends Node
## Everything a RUN owns, as opposed to the map (MainController) or a player.
##
## Three currencies live here, with three different owners:
##
##   XP            shared by the whole team. Every kill by anyone feeds one pool, and
##                 everyone levels at the same moment - so nobody is ever behind, and
##                 there is no last-hit, no kill-stealing and nothing to contest.
##   Skill points  PERSONAL. Levels grant one to every player; what each spends it on
##                 is their own business. Held on `Player`, not here.
##   Mana          shared by the whole team, and still COLOURED. Spent only at Upkeep,
##                 only on team purchases.
##
## The split is the point: skill points answer "what do I want to play" and mana
## answers "what do we need to survive", so a player never has to choose between their
## own build and the team's.
##
## An autoload rather than state on MainController because it is the run, not the map -
## and because a singleton is far easier to make server-authoritative later than scene
## state reached through `get_tree().current_scene` (see docs/MULTIPLAYER_PLAN.md).

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]

# --- XP and levels ------------------------------------------------------------

var team_xp: float = 0.0
var team_level: int = 1

# --- mana ---------------------------------------------------------------------

var mana_pool: Dictionary = {"White": 0, "Blue": 0, "Black": 0, "Red": 0, "Green": 0}
## Sub-unit mana carried between kills. Without it an Overgrowth multiplier is invisible
## on the commonest income there is: a basic enemy pays 1, and round(1 * 1.12) is 1, so
## the whole enchantment would do nothing until an elite died.
var _mana_fraction: Dictionary = {"White": 0.0, "Blue": 0.0, "Black": 0.0, "Red": 0.0, "Green": 0.0}

# --- enchantments -------------------------------------------------------------

## colour -> stacks bought. Permanent for the run, global to every player.
var enchantments: Dictionary = {"White": 0, "Blue": 0, "Black": 0, "Red": 0, "Green": 0}


func reset() -> void:
	team_xp = 0.0
	team_level = 1
	for color: String in COLORS:
		mana_pool[color] = 0
		_mana_fraction[color] = 0.0
		enchantments[color] = 0
	SignalBus.mana_changed.emit(mana_pool)
	SignalBus.team_level_changed.emit(team_level, 0)


# --- earning ------------------------------------------------------------------

## One kill pays the team twice: XP towards the next level for everyone, and mana of
## the dead enemy's own colour. Which lanes the team fights in therefore still decides
## what it can afford, which is what keeps the pentagon meaningful now that personal
## builds are bought with points instead.
func on_enemy_killed(data: EnemyData, is_elite: bool) -> void:
	if data == null:
		return
	var xp: float = GameSettings.xp_per_basic
	var mana: int = GameSettings.mana_per_basic
	if data.enemy_class == "Boss":
		xp = GameSettings.xp_per_boss
		mana = GameSettings.mana_per_boss
	elif is_elite:
		xp = GameSettings.xp_per_elite
		mana = GameSettings.mana_per_elite
	add_xp(xp)
	add_mana(data.color_identity, mana)


func add_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	team_xp += amount
	var levels_gained: int = 0
	while team_xp >= xp_for_level(team_level + 1):
		team_level += 1
		levels_gained += 1
	if levels_gained > 0:
		# Every player gains the point, not just whoever landed the blow.
		for player: Node in get_tree().get_nodes_in_group("player"):
			if player.has_method("grant_skill_points"):
				player.grant_skill_points(levels_gained)
		SignalBus.team_level_changed.emit(team_level, levels_gained)


## Total XP required to have reached `level`. Superlinear, so early levels arrive every
## wave or two and late ones take three or four.
func xp_for_level(level: int) -> float:
	if level <= 1:
		return 0.0
	var steps: int = level - 1
	return GameSettings.xp_level_base * steps + GameSettings.xp_level_growth * steps * steps


## How far into the current level the team is, and how much the level costs, so a bar
## can be drawn without the caller redoing the curve.
func xp_progress() -> Vector2:
	var floor_xp: float = xp_for_level(team_level)
	var next_xp: float = xp_for_level(team_level + 1)
	return Vector2(team_xp - floor_xp, maxf(next_xp - floor_xp, 1.0))


## Banks mana of `color`, scaled by however many Overgrowth stacks the team has bought.
## Green's enchantment compounds precisely because it is applied here.
func add_mana(color: String, amount: int) -> void:
	if amount <= 0:
		return
	var color_key: String = color
	if not mana_pool.has(color_key):
		push_warning("RunState.add_mana: unknown colour '%s', banking as White" % color)
		color_key = "White"
	# Banked whole, with the remainder carried, so a +12% bonus on a 1-mana kill is not
	# rounded away - it turns up as an extra point roughly every ninth kill instead.
	var earned: float = float(amount) * mana_multiplier() + float(_mana_fraction[color_key])
	var whole: int = int(floor(earned))
	_mana_fraction[color_key] = earned - float(whole)
	mana_pool[color_key] += whole
	SignalBus.mana_changed.emit(mana_pool)


# --- spending -----------------------------------------------------------------

func total_mana() -> int:
	var total: int = 0
	for color: String in mana_pool.keys():
		total += int(mana_pool[color])
	return total


## `cost` is colour -> amount, where the key "Colorless" may be paid from any colour.
func can_afford(cost: Dictionary) -> bool:
	var remaining: Dictionary = mana_pool.duplicate()
	for color: String in cost.keys():
		if color == "Colorless":
			continue
		if int(remaining.get(color, 0)) < int(cost[color]):
			return false
		remaining[color] = int(remaining[color]) - int(cost[color])
	if cost.has("Colorless"):
		var left: int = 0
		for color: String in remaining.keys():
			left += int(remaining[color])
		if left < int(cost["Colorless"]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for color: String in cost.keys():
		if color == "Colorless":
			continue
		mana_pool[color] = int(mana_pool[color]) - int(cost[color])
	if cost.has("Colorless"):
		var owed: int = int(cost["Colorless"])
		for color: String in mana_pool.keys():
			if owed <= 0:
				break
			var taken: int = mini(int(mana_pool[color]), owed)
			mana_pool[color] = int(mana_pool[color]) - taken
			owed -= taken
	SignalBus.mana_changed.emit(mana_pool)
	return true


## What is missing to afford `cost`, as colour -> shortfall. Empty when affordable.
## The Upkeep panel shows this rather than only greying a button out: knowing that a
## purchase needs six more black is what sends the team to the black lane next wave.
func shortfall(cost: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	var remaining: Dictionary = mana_pool.duplicate()
	for color: String in cost.keys():
		if color == "Colorless":
			continue
		var short: int = int(cost[color]) - int(remaining.get(color, 0))
		if short > 0:
			missing[color] = short
		remaining[color] = maxi(int(remaining.get(color, 0)) - int(cost[color]), 0)
	if cost.has("Colorless"):
		var left: int = 0
		for color: String in remaining.keys():
			left += int(remaining[color])
		var short_any: int = int(cost["Colorless"]) - left
		if short_any > 0:
			missing["Colorless"] = short_any
	return missing


# --- enchantments -------------------------------------------------------------

func enchantment_stacks(color: String) -> int:
	return int(enchantments.get(color, 0))


## Rising per stack, so a sixth Furnace of Rath is a real commitment rather than the
## obvious purchase every Upkeep.
func enchantment_cost(color: String) -> Dictionary:
	var stacks: int = enchantment_stacks(color)
	return {color: GameSettings.enchantment_base_cost + GameSettings.enchantment_cost_step * stacks}


func buy_enchantment(color: String) -> bool:
	if not enchantments.has(color):
		return false
	if not spend(enchantment_cost(color)):
		return false
	enchantments[color] = enchantment_stacks(color) + 1
	SignalBus.enchantment_changed.emit(color, enchantments[color])
	return true


# --- what the enchantments actually do ----------------------------------------
#
# One per colour, each on an axis no other colour occupies, so the team's spread is a
# statement of how they intend to win rather than five flavours of "more damage". Each
# deliberately echoes its colour's own affinity bonus: a colour should mean the same
# thing at every layer of the game.

## Red, Furnace of Rath: every player hits harder.
func damage_multiplier() -> float:
	return 1.0 + GameSettings.enchantment_red_damage * enchantment_stacks("Red")


## Blue, Propaganda: every enemy attacks and casts more slowly. Buys time rather than
## adding power, so it is worth little early and enormous against a boss.
func enemy_attack_speed_multiplier() -> float:
	var slow: float = GameSettings.enchantment_blue_attack_slow * enchantment_stacks("Blue")
	return 1.0 / maxf(1.0 - slow, 0.25)


## Black, Exquisite Blood: every player heals for a share of what they deal. Keeps the
## PLAYERS alive, where white keeps the CRYSTAL alive - so the two defensive colours
## never compete for the same purchase.
func lifesteal_bonus() -> float:
	return GameSettings.enchantment_black_lifesteal * enchantment_stacks("Black")


## White, Sphere of Safety: enemies close to the crystal deal less damage to it.
func crystal_damage_reduction() -> float:
	return minf(GameSettings.enchantment_white_reduction * enchantment_stacks("White"), 0.85)


func crystal_ward_radius() -> float:
	return GameSettings.enchantment_white_radius * enchantment_stacks("White")


## Green, Overgrowth: all mana income rises. Compounds, so it is worth most at wave 3
## and almost nothing at wave 22 - the one enchantment whose value is a bet on the run
## being long.
func mana_multiplier() -> float:
	return 1.0 + GameSettings.enchantment_green_income * enchantment_stacks("Green")


func enchantment_name(color: String) -> String:
	return String(GameSettings.ENCHANTMENT_NAMES.get(color, color))


func enchantment_description(color: String) -> String:
	return String(GameSettings.ENCHANTMENT_DESCRIPTIONS.get(color, ""))
