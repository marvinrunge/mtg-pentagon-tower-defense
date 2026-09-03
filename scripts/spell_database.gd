extends Node
class_name SpellDatabase
## The single definition of every player spell.
##
## Before this existed the same 25 spells were described in five places that nothing
## kept in sync: `GameSettings.SPELL_COOLDOWNS` (cooldowns), `Player.is_chargeable()`
## (a hardcoded id list), `Player.get_spell_name_for_slot()` (a NAMES dictionary),
## `SkillTree.SPELL_DATA` (names again, plus costs and descriptions), and
## `Player.execute_spell()`'s match statement. Adding a spell meant editing five
## files correctly; disagreeing with yourself was silent.
##
## `execute_spell()`'s match statement deliberately stays where it is - what each
## spell DOES is genuinely bespoke code, and only the data around it was duplicated.
##
## Follows the same shape as `EnemyDatabase` / `BossDatabase`: a `class_name` with
## static accessors, reached through the global class name, not an autoload.
##
## Per-spell numbers live here rather than in `GameSettings` on purpose. The repo
## contract puts reusable tuning in GameSettings but keeps per-entity definitions in
## the database layer (`AGENTS.md`: "Keep enemy definitions in the existing
## data/database layer"), which is exactly what these are. Global spell knobs - charge
## time, tier costs - stay in GameSettings.

const COLORS: Array[String] = ["white", "blue", "black", "red", "green"]
const SPELLS_PER_COLOR: int = 5

## Fallback for an id that isn't in the table at all.
const DEFAULT_COOLDOWN: float = 1.0

## Per-spell definition.
##   cooldown       seconds before the spell can be cast again
##   chargeable     held to charge, released to fire (min 20%, max GameSettings charge time)
##   cast_clip      animation the caster plays
##   cast_duration  how long that clip is squeezed into - the per-spell timing knob
##   commit         how long the player is actually tied up, if that is SHORTER than
##                  the animation. Defaults to cast_duration. Only a move with a long
##                  recovery needs it: Titanic Leap's clip runs on for two seconds of
##                  standing back up after the slam, which should finish playing
##                  without locking the player out of everything while it does
##   roots          true for casts that hold the player still
##   upper_body     whether the cast plays on the upper body only, leaving the legs to
##                  the locomotion layer. Defaults to the opposite of `roots`, because
##                  a full-body clip over a character still sliding around is exactly
##                  the foot-sliding the layering exists to remove. Titanic Leap is
##                  the one case where the two come apart and so states it outright:
##                  it moves the caster AND needs its own legs, because the movement
##                  it makes IS the jump the clip is playing
##
## Two things are deliberately NOT stored here, both because storing them is how they
## drifted in the first place:
##
##   the release moment - when in the clip the effect fires is a property of the
##   ANIMATION, measured at build time by tools/player_character_builder.gd and kept
##   as `hit_ratios` metadata on the clip itself. Several spells share one clip and
##   all want the same moment. The one knob on top of that is `release_on_last`, for
##   a clip whose payload is its FINAL impact rather than its first: Titanic Leap
##   lands on the slam at 79% of the jump, not on the take-off at 15%.
##
##   the unlock cost - that is the tier's cost from GameSettings.TIER_COSTS.
const SPELLS: Dictionary = {
	# --- RED: aggression ---
	"red_1": {
		"name": "Fireball",
		"desc": "Charged explosive projectile with a scaling blast radius.",
		"cooldown": 5.0, "chargeable": true,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},
	"red_2": {
		"name": "Rain of Ember",
		"desc": "Calls down a burning firestorm that scorches everything beneath it.",
		"cooldown": 9.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},

	# --- GREEN: primal vitality ---
	# Must NOT root: the leap drives the player's own movement, and holding them
	# still would fight it. See Player.cast_green_titanic_leap.
	#
	# And must NOT be filtered to the upper body either, which is the usual partner of
	# not rooting: this clip is a running jump, so its legs are the whole point. The
	# walk cycle the filter would leave underneath is precisely wrong for a character
	# who is in the air.
	"green_1": {
		"name": "Titanic Leap",
		"desc": "Leap forward and slam the ground, hurting everything around the landing.",
		"cooldown": 8.0, "chargeable": false,
		# 2.6s is the whole clip - leap, slam and the stand-up afterwards - at the pace
		# it was authored at. `commit` is what keeps that from being a two-and-a-half
		# second lockout: control comes back just after the slam lands at ~0.86s, and
		# the recovery plays itself out unless the player interrupts it.
		"cast_clip": "jump_attack", "cast_duration": 2.6, "commit": 1.2, "roots": false,
		"upper_body": false,
		"release_on_last": true,
	},
}


static func has_spell(spell_id: String) -> bool:
	return SPELLS.has(spell_id)


static func get_spell(spell_id: String) -> Dictionary:
	return SPELLS.get(spell_id, {})


## Not `get_name()`: this extends Node, which already has one.
static func get_display_name(spell_id: String) -> String:
	return String(SPELLS.get(spell_id, {}).get("name", "Locked Spell"))


static func get_description(spell_id: String) -> String:
	return String(SPELLS.get(spell_id, {}).get("desc", ""))


static func get_cooldown(spell_id: String) -> float:
	return float(SPELLS.get(spell_id, {}).get("cooldown", DEFAULT_COOLDOWN))


static func is_chargeable(spell_id: String) -> bool:
	return bool(SPELLS.get(spell_id, {}).get("chargeable", false))


## Colour half of an id, e.g. "red_2" -> "red". Empty for anything that isn't a spell
## id, which is what keeps non-spell entries such as the kick's cooldown out of the
## spell-only sweeps.
static func get_color(spell_id: String) -> String:
	if not SPELLS.has(spell_id):
		return ""
	return spell_id.get_slice("_", 0)


## 1-based tier, or 0 for a non-spell id.
static func get_tier(spell_id: String) -> int:
	if not SPELLS.has(spell_id):
		return 0
	return int(spell_id.get_slice("_", 1))


static func make_id(color: String, tier: int) -> String:
	return "%s_%d" % [color, tier]


## Mana price of unlocking the spell, taken from the shared tier table so it can
## never disagree with what the skill tree charges.
static func get_unlock_cost(spell_id: String) -> int:
	var tier: int = get_tier(spell_id)
	if tier <= 0:
		return 0
	return GameSettings.get_tier_cost(tier - 1)


## The colour's five spells in tier order, shaped for the skill tree's board builder:
## {id, name, cost, desc}.
static func get_spells_for_color(color: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tier in range(1, SPELLS_PER_COLOR + 1):
		var spell_id := make_id(color, tier)
		if not SPELLS.has(spell_id):
			continue
		out.append({
			"id": spell_id,
			"name": get_display_name(spell_id),
			"cost": get_unlock_cost(spell_id),
			"desc": get_description(spell_id),
		})
	return out
