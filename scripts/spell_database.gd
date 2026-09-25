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
const ICON_ROOT: String = "res://assets/icons/"
const ICON_FILES: Dictionary = {
	"white": "white.png", "blue": "blue.jpg", "black": "black.png", "red": "red.png", "green": "green.png",
	"white_1": "exalted-strike.png", "white_2": "circle-of-protection.png", "white_3": "reprisal-ward.png",
	"white_4": "wrath-of-god.png", "white_5": "rally-the-fallen.png", "blue_1": "unsummon.png",
	"blue_2": "frostwave.png", "blue_3": "suction.png", "blue_4": "frost-globe.png", "blue_5": "flying.png",
	"black_1": "doom-blade.png", "black_2": "fear.png", "black_3": "kill.png", "black_4": "wall-of-souls.png",
	"black_5": "zombify.png", "red_1": "fireball.png", "red_2": "fire-dash.png", "red_3": "rain-of-ember.png",
	"red_4": "fire-cone.png", "red_5": "lightning-bolt.png", "green_1": "titanic-leap.png",
	"green_2": "giant-growth.png", "green_3": "fog.png", "flight": "flying.png", "haste": "haste.png",
	"double_strike": "doublestrike.png", "trample_strike": "trample.png", "vigilance": "vigilance.png",
	"roar": "roar.png", "ironbark": "ironbark.png", "melee_combo": "blade-dance.png",
	"aura_glorious_anthem": "glorious anthem.png", "aura_healing_orb": "healing-orb.png",
	"aura_rhystic_study": "rhystic-study.png", "aura_orb_of_frost": "orb-of-frost.png",
	"aura_phyrexian_arena": "phyrexian-arena.png", "aura_grave_pact": "grave-pact.png",
	"aura_fervor": "fervor.png", "aura_orb_of_fire": "orb-of-fire.png",
	"aura_sylvan_library": "sylvan-library.png", "aura_trample": "trample.png",
}

## Per-spell definition.
##   cooldown       seconds before the spell can be cast again
##   chargeable     held to charge, released to fire (min 20%, max GameSettings charge time)
##   cast_clip      animation the caster plays
##   cast_duration  how long that clip is squeezed into - the per-spell timing knob
##   commit         how long the player is actually tied up, if that is SHORTER than
##                  the animation. Defaults to cast_duration. Only a move with a long
##                  recovery needs it: Titanic Brawl's clip runs on for two seconds of
##                  standing back up after the slam, which should finish playing
##                  without locking the player out of everything while it does
##   roots          true for casts that hold the player still
##   upper_body     whether the cast plays on the upper body only, leaving the legs to
##                  the locomotion layer. Defaults to the opposite of `roots`, because
##                  a full-body clip over a character still sliding around is exactly
##                  the foot-sliding the layering exists to remove. Titanic Brawl is
##                  the one case where the two come apart and so states it outright:
##                  it moves the caster AND needs its own legs, because the movement
##                  it makes IS the brawl leap the clip is playing
##
## Two things are deliberately NOT stored here, both because storing them is how they
## drifted in the first place:
##
##   the release moment - when in the clip the effect fires is a property of the
##   ANIMATION, measured at build time by tools/player_character_builder.gd and kept
##   as `hit_ratios` metadata on the clip itself. Several spells share one clip and
##   all want the same moment. The one knob on top of that is `release_on_last`, for
##   a clip whose payload is its FINAL impact rather than its first: Titanic Brawl
##   lands on the slam at 79% of the jump, not on the take-off at 15%.
##
##   the unlock cost - that is the tier's cost from GameSettings.TIER_COSTS.
## Slot order is the RING order from docs/SKILL_DESIGN.md, not a power ranking: slots 1
## and 2 are the colour's Core ring - the skills that work with no setup and read
## instantly - and slots 3-5 are its Specialist ring, which need positioning or are
## situationally stronger. The skill tree gates slots on affinity rank, so putting the
## Core skills first is what makes a colour playable the moment you invest in it.
const SPELLS: Dictionary = {
	# --- WHITE: protection and restoration ---
	# The only colour built around the myrs and the crystal rather than the player, and
	# the only one whose power goes UP with more allies alive.
	"white_1": {
		"name": "Exalted Strike",
		"desc": "Your next melee hit lands harder and reaches further. Anything it kills is exiled, leaving no corpse.",
		"cooldown": 8.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.5, "roots": false,
	},
	"white_2": {
		"name": "Circle of Protection",
		"desc": "A pool of shield divided between nearby allies. Alone, you take all of it.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.7, "roots": true,
	},
	"white_3": {
		"name": "Reprisal Ward",
		"desc": "For a time, reflect part of all damage taken back at the attacker, and block some attacks outright.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.5, "roots": false,
	},
	"white_4": {
		"name": "Wrath of God",
		"desc": "Heavy damage to every enemy in a wide radius around you.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.85, "roots": true,
	},
	"white_5": {
		"name": "Rally the Fallen",
		"desc": "Revives every downed teammate in range and heals surviving allies - myrs included.",
		"cooldown": 45.0, "chargeable": false,
		"cast_clip": "cast_white", "cast_duration": 0.9, "roots": true,
	},

	# --- BLUE: control ---
	# Blue never kills quickly. It decides WHERE the fight happens and WHO is allowed to
	# participate.
	"blue_1": {
		"name": "Unsummon",
		"desc": "Shoves every enemy ahead of you far back and stuns them where they land.",
		"cooldown": 9.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.55, "roots": false,
	},
	"blue_2": {
		"name": "Frost Breath",
		"desc": "Freezes every enemy around you and deals moderate damage. Bosses are slowed instead.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.7, "roots": true,
	},
	"blue_3": {
		"name": "Suction",
		"desc": "Drags nearby enemies into one place, packing them for whatever comes next.",
		"cooldown": 11.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": true,
	},
	"blue_4": {
		"name": "Wall of Frost",
		"desc": "Raises a solid ice wall across your aim line. Unsummon deals bonus damage when it slams enemies into the wall.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "cast_blue", "cast_duration": 0.6, "roots": false,
	},
	"blue_5": {
		"name": "Displace",
		"desc": "Blink a short distance to the ground you are aiming at.",
		"cooldown": 10.0, "chargeable": false,
		# The one spell with NO cast animation. A blink that has to be announced for
		# two-thirds of a second is not an escape, and the cast pose read as the caster
		# hesitating before a movement skill they had already committed to. An empty
		# cast_clip is the supported way to say "resolve now" - see Player._begin_cast.
		"cast_clip": "", "cast_duration": 0.0, "roots": false,
	},

	# --- BLACK: parasitic drain ---
	# Trades its own resources for removal, and the only colour that can delete a target
	# outright.
	"black_1": {
		"name": "Doom Blade",
		"desc": "A black blade travels straight ahead, passing through everything in the line.",
		"cooldown": 7.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.5, "roots": false,
	},
	"black_2": {
		"name": "Fear",
		"desc": "Nearby enemies turn and flee instead of fighting, and take more damage for as long as they run.",
		"cooldown": 14.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.6, "roots": false,
	},
	# The harshest cooldown in the game, deliberately. An instant delete on a short
	# cooldown invalidates every other black skill.
	"black_3": {
		"name": "Kill",
		"desc": "Instantly kills one enemy. Bosses only below a third of their health.",
		"cooldown": 60.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.75, "roots": true,
	},
	"black_4": {
		"name": "Wall of Souls",
		"desc": "A wall of souls. Enemies that cross it take double damage from every source.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.7, "roots": true,
	},
	"black_5": {
		"name": "Zombify",
		"desc": "Raises the corpses already lying on the field as undead that fight for you.",
		"cooldown": 30.0, "chargeable": false,
		"cast_clip": "cast_black", "cast_duration": 0.9, "roots": true,
	},

	# --- RED: aggression ---
	# The damage colour, and the only one with no defensive option at all.
	"red_1": {
		"name": "Fireball",
		"desc": "Charged explosive projectile with a scaling blast radius.",
		"cooldown": 5.0, "chargeable": true,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},
	# Like Titanic Brawl, this one MOVES the caster - so it launches when the cast starts
	# rather than on the release frame, and the release is the trail catching light.
	"red_2": {
		"name": "Fire Dash",
		"desc": "Dash forward, leaving a burning trail behind you. Escape and damage in one.",
		"cooldown": 8.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.45, "roots": false,
	},
	"red_3": {
		"name": "Rain of Ember",
		"desc": "Calls down a burning firestorm that scorches everything beneath it.",
		"cooldown": 9.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.55, "roots": false,
	},
	# HELD, not cast: Fire Cone spends a refill meter while the button is down.
	"red_4": {
		"name": "Fire Cone",
		"desc": "Held. Burns and slows everything in a cone ahead of you while you hold it, then refills before it can be used again.",
		"cooldown": 0.0, "chargeable": false, "channel": true,
		"cast_clip": "cast_red", "cast_duration": 0.4, "roots": false,
	},
	"red_5": {
		"name": "Lightning Bolt",
		"desc": "Calls a bolt down on a small area, striking bosses and elites for double. The precision answer to one big target.",
		"cooldown": 12.0, "chargeable": false,
		"cast_clip": "cast_red", "cast_duration": 0.7, "roots": true,
	},

	# --- GREEN: primal vitality ---
	# Green fights by being physically present: bigger, harder to ignore, and dangerous
	# to stand next to.
	#
	# Titanic Brawl must NOT root: the leap drives the player's own movement, and holding
	# them still would fight it. See Player.cast_green_titanic_leap.
	#
	# And must NOT be filtered to the upper body either, which is the usual partner of
	# not rooting: this clip is a running jump, so its legs are the whole point. The
	# walk cycle the filter would leave underneath is precisely wrong for a character
	# who is in the air.
	"green_1": {
		"name": "Titanic Brawl",
		"desc": "Leap forward and slam the ground, hurting everything around the landing.",
		"cooldown": 8.0, "chargeable": false,
		# 2.6s is the whole clip - leap, slam and the stand-up afterwards - at the pace
		# it was authored at. The leap is a real commitment, though: nothing else may
		# start until the slam has landed, so `commit` covers launch AND landing rather
		# than ending early the way a move with a free recovery does.
		#
		# ROOTS for that whole window, including the stand-up. The flight itself is not
		# affected - Player's leap branch moves the character before the rooting check ever
		# runs - so this only governs the seconds after the landing, where the player used
		# to be able to walk out of their own recovery. A character sliding across the
		# ground while playing an animation of getting to their feet is the one thing that
		# reads as broken rather than as slow.
		"cast_clip": "jump_attack", "cast_duration": 2.6, "commit": 2.6, "roots": true,
		"upper_body": false,
		"release_on_last": true,
	},
	"green_2": {
		"name": "Giant Growth",
		"desc": "Grow enormous for a time, gaining maximum health with the size.",
		"cooldown": 22.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.7, "roots": false,
	},
	"green_3": {
		"name": "Fog",
		"desc": "A bank of fog where enemies deal no damage at all and wade rather than walk. Ground to hold, not to kill on.",
		"cooldown": 18.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.6, "roots": false,
	},
	# A shout, so it uses the shout: full body, and long enough to read as one.
	"green_4": {
		"name": "Roar",
		"desc": "Nearby enemies turn on you, pulling them off the crystal and the myrs.",
		"cooldown": 16.0, "chargeable": false,
		"cast_clip": "taunt_battlecry", "cast_duration": 1.2, "commit": 0.9, "roots": true,
		"upper_body": false,
	},
	"green_5": {
		"name": "Ironbark",
		"desc": "Bark over your skin: heavy damage reduction, and nothing can knock you back, stun or freeze you.",
		"cooldown": 20.0, "chargeable": false,
		"cast_clip": "cast_green", "cast_duration": 0.55, "roots": false,
	},
}


## The aura fork: one per colour, two ways to take it, exactly one owned per run.
##
## `attunement` is the stat line - the five auras the game already shipped with, kept
## rather than replaced, because deleting working content to make room for planned
## content is how a game ends up with the same amount of content forever.
## `manifestation` is the visible one from the colour tables: something fighting
## alongside the player rather than a multiplier on the player.
##
## Both halves stay honest. Attunements are stronger on paper; Manifestations do work
## while the player is somewhere else - which, in a five-lane tower defence where you
## can only stand in one lane, is worth more than it looks.
##
## Deliberately UN-RANKED. One purchase, expensive, permanent for the run: the moment a
## aura becomes rankable it turns back into a stat slider and the fork stops being a
## decision.
const AURAS: Dictionary = {
	"white": {
		"attunement": {
			"id": "aura_glorious_anthem", "name": "Glorious Anthem",
			"desc": "A permanent shield, and every hit you land is stronger.",
		},
		"manifestation": {
			"id": "aura_healing_orb", "name": "Healing Orb",
			"desc": "An orb circles you, healing the most hurt ally in range every few seconds.",
		},
	},
	"blue": {
		"attunement": {
			"id": "aura_rhystic_study", "name": "Rhystic Study",
			"desc": "Sharply faster cooldowns, and every cast grants shield.",
		},
		"manifestation": {
			"id": "aura_orb_of_frost", "name": "Winter Orb",
			"desc": "An orb circles you, firing ice at nearby enemies for damage and slow.",
		},
	},
	"black": {
		"attunement": {
			"id": "aura_phyrexian_arena", "name": "Phyrexian Arena",
			"desc": "More damage and more speed, paid for with your own health, every second.",
		},
		"manifestation": {
			"id": "aura_grave_pact", "name": "Grave Pact",
			"desc": "Enemies dying near you leave souls: a small heal and a stacking damage bonus that decays if you stop killing.",
		},
	},
	"red": {
		"attunement": {
			"id": "aura_fervor", "name": "Fervor",
			"desc": "You attack and move faster, permanently.",
		},
		"manifestation": {
			"id": "aura_orb_of_fire", "name": "Orb of Fire",
			"desc": "An orb circles you, firing bolts at nearby enemies that set them burning.",
		},
	},
	"green": {
		"attunement": {
			"id": "aura_sylvan_library", "name": "Sylvan Library",
			"desc": "Far more maximum health, and steady regeneration.",
		},
		"manifestation": {
			# NOT "Trample": the Gruul passive already owns that name, and it is the one
			# that matches the MTG keyword. Two nodes reading "Trample" in the same tree is
			# a naming bug, not a theme.
			"id": "aura_trample", "name": "Stampede",
			"desc": "Enemies near you take continuous damage - but only while you are moving.",
		},
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


## Icon textures, kept after the first load.
##
## `get_icon_path` below probes the filesystem with ResourceLoader.exists() on every call,
## up to twice, and every caller then load()s whatever came back. Neither is expensive on
## its own and neither is free at the rate the skill tree asks for them: one full
## update_ui() pass wants an icon for each of forty nodes. The texture behind an id never
## changes, so the first answer is the only one worth working out.
static var _icon_cache: Dictionary = {}


## The texture for `icon_id`, or null when neither it nor its colour has one.
static func get_icon(icon_id: String, fallback_color: String = "") -> Texture2D:
	var key: String = icon_id + "|" + fallback_color
	if _icon_cache.has(key):
		return _icon_cache[key]
	var path: String = get_icon_path(icon_id, fallback_color)
	var texture: Texture2D = load(path) as Texture2D if path != "" else null
	_icon_cache[key] = texture
	return texture


static func get_icon_path(icon_id: String, fallback_color: String = "") -> String:
	if ICON_FILES.has(icon_id):
		var icon_path: String = ICON_ROOT + String(ICON_FILES[icon_id])
		if ResourceLoader.exists(icon_path):
			return icon_path
	var color: String = fallback_color if fallback_color != "" else get_color(icon_id)
	if ICON_FILES.has(color):
		var fallback_path: String = ICON_ROOT + String(ICON_FILES[color])
		if ResourceLoader.exists(fallback_path):
			return fallback_path
	return ""


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


## True for a spell that is HELD rather than cast: it starts on the press, runs while
## the button is down, and ends on the release or when its own limit runs out.
static func is_channelled(spell_id: String) -> bool:
	return bool(SPELLS.get(spell_id, {}).get("channel", false))


## Both halves of one colour's aura fork, attunement first. Empty for a colour that
## has none, which no colour currently does.
static func get_auras(color: String) -> Array[Dictionary]:
	var row: Dictionary = AURAS.get(color, {})
	if row.is_empty():
		return []
	return [row["attunement"], row["manifestation"]]


## The colour a aura id belongs to, or "" if it is not a aura at all.
static func get_aura_color(aura_id: String) -> String:
	for color: String in AURAS:
		for half: String in ["attunement", "manifestation"]:
			if String(AURAS[color][half]["id"]) == aura_id:
				return color
	return ""


static func get_aura_name(aura_id: String) -> String:
	for color: String in AURAS:
		for half: String in ["attunement", "manifestation"]:
			var entry: Dictionary = AURAS[color][half]
			if String(entry["id"]) == aura_id:
				return String(entry["name"])
	return ""
