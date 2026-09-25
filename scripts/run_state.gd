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
## and because a singleton is far easier to make server-authoritative than scene state
## reached through `get_tree().current_scene`. That is now cashed in: every autoload has
## the same node path on every peer, so these RPCs route with nothing to look up.
##
## THE SERVER OWNS ALL OF IT. Clients never add XP or mana themselves; they are told.
## Otherwise five peers each bank their own kills and the pool disagrees with itself.

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]

# --- XP and levels ------------------------------------------------------------

var team_xp: float = 0.0
## Every skill point this run has handed to EVERY player: one per team level, plus one
## for each time the Upkeep panel bought the party a point.
##
## Kept as a running total rather than left implicit in the level, because the Upkeep
## purchases are not derivable from anything else - and because a total is the only form
## a player who was disconnected while it grew can act on. Skill points used to be paid
## out by iterating the avatars in the tree at the moment of the level-up, so a player who
## dropped out for five minutes came back with exactly what they left with while the rest
## of the party had levelled twice.
var points_awarded: int = 0


var team_level: int = 1

# --- mana ---------------------------------------------------------------------

var mana_pool: Dictionary = {"White": 0, "Blue": 0, "Black": 0, "Red": 0, "Green": 0}
## Sub-unit mana carried between kills. Without it an Overgrowth multiplier is invisible
## on the commonest income there is: a basic enemy pays 1, and round(1 * 1.12) is 1, so
## the whole enchantment would do nothing until an elite died.

# --- enchantments -------------------------------------------------------------

## colour -> stacks bought. Permanent for the run, global to every player.
var enchantments: Dictionary = {"White": 0, "Blue": 0, "Black": 0, "Red": 0, "Green": 0}


## Set whenever the server changes anything, cleared when the change goes out. Kills
## arrive far faster than a UI can read, so the pool is flushed at a fixed rate instead
## of once per enemy - five players clearing a wave would otherwise send hundreds of
## identical dictionaries a second.
var _dirty: bool = false
var _flush_timer: float = 0.0


func _process(delta: float) -> void:
	if not Net.is_active() or not Net.is_server() or not _dirty:
		return
	_flush_timer -= delta
	if _flush_timer > 0.0:
		return
	_flush_timer = GameSettings.run_state_sync_interval
	_dirty = false
	_apply_state.rpc(team_xp, team_level, mana_pool, enchantments, points_awarded)


## The whole economy in one message. Small enough that sending it entire is cheaper than
## working out which field moved, and it cannot drift the way incremental updates can.
@rpc("authority", "call_remote", "reliable")
func _apply_state(xp: float, level: int, pool: Dictionary, ench: Dictionary, awarded: int = 0) -> void:
	team_xp = xp
	team_level = level
	mana_pool = pool
	enchantments = ench
	points_awarded = awarded
	SignalBus.mana_changed.emit(mana_pool)
	# Emitted with levels_gained ZERO, which is what makes this a statement of where the
	# run is rather than a level-up: Player._on_team_level_changed returns early on a zero
	# gain, so nothing is paid out twice - but it still sets Blade Dance, which is
	# otherwise granted only at the instant of the level-up that reached BLADE_DANCE_LEVEL
	# and so was lost by anyone who arrived or reconnected afterwards.
	SignalBus.team_level_changed.emit(team_level, 0)
	# ...and whatever levels were missed while away are settled here, from the total rather
	# than from the events, because the events happened to nobody.
	var local: Node = PlayerRegistry.get_local()
	if local != null and local.has_method("reconcile_skill_points"):
		local.reconcile_skill_points()


## The whole economy, to ONE peer. The periodic flush only fires when something has
## changed, so a player who joins or reconnects mid-match would otherwise stare at an
## empty mana pool and level 1 until the next kill happened to dirty the state.
func push_state_to(peer_id: int) -> void:
	if not Net.is_active() or not Net.is_server():
		return
	_apply_state.rpc_id(peer_id, team_xp, team_level, mana_pool, enchantments, points_awarded)


func reset() -> void:
	team_xp = 0.0
	team_level = 1
	points_awarded = 0
	for color: String in COLORS:
		mana_pool[color] = 0
		enchantments[color] = 0
	SignalBus.mana_changed.emit(mana_pool)
	SignalBus.team_level_changed.emit(team_level, 0)


# --- earning ------------------------------------------------------------------

## One kill pays the team twice: XP towards the next level for everyone, and mana of
## the dead enemy's own colour. Which lanes the team fights in therefore still decides
## what it can afford, which is what keeps the pentagon meaningful now that personal
## builds are bought with points instead.
## `at` is where the enemy died, and it is here only so a payout can be SEEN. Ordinary
## enemies pay nothing now (GameSettings.mana_per_basic), so the ones that do pay are rare
## enough to be worth announcing - a drop that silently increments a number in the corner
## of the HUD is a drop the player never learns to want.
func on_enemy_killed(data: EnemyData, is_elite: bool, at: Vector3 = Vector3.INF) -> void:
	if data == null or not Net.is_server():
		return
	var xp: float = GameSettings.xp_per_basic
	var mana: int = GameSettings.mana_per_basic
	var is_boss: bool = data.enemy_class == "Boss"
	if is_boss:
		xp = GameSettings.xp_per_boss
		mana = GameSettings.mana_per_boss
	elif is_elite:
		xp = GameSettings.xp_per_elite
		mana = GameSettings.mana_per_elite
	add_xp(xp)
	if mana <= 0:
		return
	if is_boss:
		# Overgrowth's boss half, applied before the general multiplier in add_mana rather
		# than folded into it - a boss is supposed to be the stack's headline.
		mana = int(round(float(mana) * (1.0 + GameSettings.enchantment_green_boss_mana * enchantment_stacks("Green"))))
	var banked: int = add_mana(data.color_identity, mana)
	if banked > 0 and at.is_finite():
		_announce_mana_drop(data, banked, at)


## The visible half of a payout: a number in the enemy's own colour where it fell, and a
## ring under it for a boss, whose drop is worth looking up for.
func _announce_mana_drop(data: EnemyData, amount: int, at: Vector3) -> void:
	var tint: Color = data.visual_color
	# The label REPLACES the number in DamageNumber, so the amount has to be inside it -
	# and it says "mana" out loud, because a bare +4 floating off a corpse in a game full
	# of floating damage numbers reads as damage.
	NetFx.damage_number(at + Vector3(0.0, 2.1, 0.0), float(amount), tint, "+%d mana" % amount)
	if data.enemy_class == "Boss":
		NetFx.ring(at, tint, 3.0)
		NetFx.impact(at, tint, 1.6)


func add_xp(amount: float) -> void:
	if amount <= 0.0 or not Net.is_server():
		return
	team_xp += amount
	var levels_gained: int = 0
	while team_xp >= xp_for_level(team_level + 1):
		team_level += 1
		levels_gained += 1
	_dirty = true
	if levels_gained > 0:
		# Rare and important, so it goes out immediately rather than waiting for the
		# next flush - a level is the one economy event a player actually watches for.
		if Net.is_active():
			_apply_level.rpc(team_xp, team_level, levels_gained)
		_apply_level(team_xp, team_level, levels_gained)


## Levels land on every peer at the same moment, which is the whole point of sharing XP:
## nobody is ever behind, and a player who died repeatedly still keeps up.
@rpc("authority", "call_remote", "reliable")
func _apply_level(xp: float, level: int, levels_gained: int) -> void:
	team_xp = xp
	team_level = level
	points_awarded += levels_gained
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
## Returns the WHOLE mana actually banked, which is what a payout should show: the caller
## has no other way to know what its amount became once Overgrowth and the carried
## fraction below were applied to it.
func add_mana(color: String, amount: int) -> int:
	if amount <= 0 or not Net.is_server():
		return 0
	var color_key: String = color
	if not mana_pool.has(color_key):
		push_warning("RunState.add_mana: unknown colour '%s', banking as White" % color)
		color_key = "White"
	# Whole numbers, straight in. There used to be a fractional carry here, for Overgrowth's
	# general "+12% to all income" multiplier - a +12% bonus on a 1-mana kill would
	# otherwise round away to nothing. That multiplier is gone (Overgrowth is myr slots and
	# boss mana now), every income is an exact integer again, and the carry had nothing
	# left to carry.
	mana_pool[color_key] += amount
	_dirty = true
	SignalBus.mana_changed.emit(mana_pool)
	return amount


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


## Only ever called on the server - every purchase route goes through the Upkeep panel,
## which asks the server to buy on the team's behalf.
func spend(cost: Dictionary) -> bool:
	if not Net.is_server() or not can_afford(cost):
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
	_dirty = true
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
	_dirty = true
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


## How many myrs may work ONE well, Overgrowth included. The base cap is five slots a
## well and ten myrs in total, so without this the myr economy tops out well below its own
## headcount limit whenever a team wants to concentrate on a lane.
func myr_well_slots() -> int:
	return GameSettings.myr_well_max_slots + GameSettings.enchantment_green_well_slots * enchantment_stacks("Green")


func enchantment_name(color: String) -> String:
	return String(GameSettings.ENCHANTMENT_NAMES.get(color, color))


## What this enchantment is doing RIGHT NOW, and what one more stack would make of it.
##
## The Upkeep shop is asked one question - "is another stack worth it?" - and a static
## sentence cannot answer it. Every effect here is per stack, so at zero stacks the row
## reads as what the first one buys, and after that as the live value plus the step.
func enchantment_description(color: String) -> String:
	var template: String = String(GameSettings.ENCHANTMENT_DESCRIPTIONS.get(color, ""))
	if template == "":
		return ""
	var stacks: int = enchantment_stacks(color)
	var next: Array = _enchantment_values(color, stacks + 1)
	# Nothing owned yet, so there is no live value to state - filling the template with
	# zeroes produces "enemies deal no less damage", which reads as a description of the
	# enchantment rather than of not having it. Only the offer is shown.
	if stacks <= 0:
		return "One stack: %s." % [template % next]
	return "%s.  Next stack: %s." % [template % _enchantment_values(color, stacks), template % next]


## The two numbers a colour's description template takes, at `stacks` stacks, already
## formatted. Kept next to the template rather than inside it so the units - a percentage,
## a count, a duration, a damage figure - live with the values they belong to.
func _enchantment_values(color: String, stacks: int) -> Array:
	match color:
		"White":
			return [
				_pct(GameSettings.enchantment_white_reduction * stacks),
				_pct(minf(GameSettings.enchantment_white_myr_reduction * stacks,
					GameSettings.enchantment_white_myr_reduction_cap)),
			]
		"Blue":
			return [
				_pct(GameSettings.enchantment_blue_attack_slow * stacks),
				"%.1fs" % (GameSettings.enchantment_blue_myr_phase * stacks),
			]
		"Black":
			return [
				_pct(GameSettings.enchantment_black_lifesteal * stacks),
				"%d damage" % int(round(GameSettings.enchantment_black_myr_blast_damage * stacks)),
			]
		"Red":
			return [
				_pct(GameSettings.enchantment_red_damage * stacks),
				_pct(GameSettings.enchantment_red_myr_speed * stacks),
			]
		"Green":
			var slots: int = GameSettings.enchantment_green_well_slots * stacks
			return [
				"+%d myr slot%s" % [slots, "" if slots == 1 else "s"],
				_pct(GameSettings.enchantment_green_boss_mana * stacks),
			]
	return ["", ""]


func _pct(fraction: float) -> String:
	return "%d%%" % int(round(fraction * 100.0))


# --- the myr half of the enchantments -----------------------------------------
#
# Read live by Myr rather than cached on it, the same way _refresh_fervor_state already
# reads aura state, so a stack bought at Upkeep applies to myrs that are already walking.

## White, Sphere of Safety. Capped short of immunity on purpose - see the cap's own note.
func myr_damage_reduction() -> float:
	return minf(GameSettings.enchantment_white_myr_reduction * enchantment_stacks("White"),
		GameSettings.enchantment_white_myr_reduction_cap)


## Blue, Propaganda. Seconds a LOADED myr is out of reach after being hit; 0 disables it.
func myr_phase_duration() -> float:
	return GameSettings.enchantment_blue_myr_phase * enchantment_stacks("Blue")


## Black, Exquisite Blood. Damage and radius of a dying myr's blast; 0 damage disables it.
func myr_blast_damage() -> float:
	return GameSettings.enchantment_black_myr_blast_damage * enchantment_stacks("Black")


func myr_blast_radius() -> float:
	var stacks: int = enchantment_stacks("Black")
	if stacks <= 0:
		return 0.0
	return GameSettings.enchantment_black_myr_blast_radius \
		+ GameSettings.enchantment_black_myr_blast_radius_per_stack * stacks


## Red, Furnace of Rath. Multiplier on myr move speed.
func myr_speed_multiplier() -> float:
	return 1.0 + GameSettings.enchantment_red_myr_speed * enchantment_stacks("Red")
