extends RefCounted
## Every piece of equipment in the game: what it is called, what it does, which bosses can
## drop it, and the one number its effect needs.
##
## Equipment is FOUND, not bought. A slain wave boss can drop one piece (RunState.
## try_drop_equipment), drawn from the pool of its own colour, and what drops belongs to the
## whole team - every player can put it on from the equipment menu (I).
##
## The first five pieces are the keyword passives that used to sit on the skill tree between
## the colours - Flying, Double Strike, Haste, Trample and Vigilance. They were numbers that
## belonged to no colour, bought with points from whichever neighbour was nearer. Each is an
## MTG equipment now, dropped by the boss whose colour it fits; black and blue gained pieces
## of their own, because black had none at all.
##
## Same shape as SpellDatabase - static accessors over one table - but preloaded by path
## rather than given a `class_name`: see scripts/icon_style.gd for why a new global class is a
## hazard on the headless runs that validate the project.

## id -> definition.
##   name    display name (a real MTG artifact where one fits)
##   desc    one line for the menu
##   colors  the boss colours that can drop it
##   value   the GameSettings export holding the one number the effect reads
##   icon    file under SpellDatabase.ICON_ROOT, or "" for the colour's own symbol
const ITEMS: Dictionary = {
	"swiftfoot_boots": {
		"name": "Swiftfoot Boots",
		"desc": "You move faster.",
		"colors": ["red"],
		"value": "equipment_swiftfoot_boots_speed",
		"icon": "haste.png",
	},
	"cobbled_wings": {
		"name": "Cobbled Wings",
		"desc": "You jump higher, and hold jump while falling to glide.",
		"colors": ["blue", "white"],
		"value": "equipment_cobbled_wings_jump",
		"icon": "flying.png",
	},
	"fireshrieker": {
		"name": "Fireshrieker",
		"desc": "Double strike: your melee hits sometimes land twice.",
		"colors": ["red", "white"],
		"value": "equipment_fireshrieker_chance",
		"icon": "doublestrike.png",
	},
	"amulet_of_vigor": {
		"name": "Amulet of Vigor",
		"desc": "Your spells with a duration last longer.",
		"colors": ["green", "white"],
		"value": "equipment_amulet_of_vigor_duration",
		"icon": "vigilance.png",
	},
	"loxodon_warhammer": {
		"name": "Loxodon Warhammer",
		"desc": "Trample: your melee hits add a share of your maximum health as damage.",
		"colors": ["green"],
		"value": "equipment_loxodon_warhammer_hp_share",
		"icon": "trample.png",
	},
	"icy_manipulator": {
		"name": "Icy Manipulator",
		"desc": "Your melee hits sometimes freeze the enemy. Bosses are slowed instead.",
		"colors": ["blue"],
		"value": "equipment_icy_manipulator_chance",
		"icon": "",
	},
	"executioners_capsule": {
		"name": "Executioner's Capsule",
		"desc": "Your melee hits kill any enemy left nearly dead. Not bosses.",
		"colors": ["black"],
		"value": "equipment_executioners_capsule_threshold",
		"icon": "",
	},
	"whispersilk_cloak": {
		"name": "Whispersilk Cloak",
		"desc": "Every kill of yours hides you from enemies for a moment.",
		"colors": ["black", "blue"],
		"value": "equipment_whispersilk_cloak_duration",
		"icon": "",
	},
}

## The order the menu lists them in: grouped by colour, WUBRG, the way the lanes run.
const ORDER: Array[String] = [
	"cobbled_wings", "fireshrieker", "amulet_of_vigor",
	"icy_manipulator", "whispersilk_cloak",
	"executioners_capsule",
	"swiftfoot_boots",
	"loxodon_warhammer",
]


static func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)


static func get_item(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


static func display_name(item_id: String) -> String:
	return String(get_item(item_id).get("name", item_id))


static func description(item_id: String) -> String:
	return String(get_item(item_id).get("desc", ""))


static func colors(item_id: String) -> Array:
	return get_item(item_id).get("colors", [])


## The one number an item's effect reads, from GameSettings. 0 for an unknown item.
static func value(item_id: String) -> float:
	var key: String = String(get_item(item_id).get("value", ""))
	if key == "":
		return 0.0
	return float(GameSettings.get(key))


## The pieces a boss of `color` can drop. `color` is lower-case, like SpellDatabase's.
static func pool_for(color: String) -> Array[String]:
	var pool: Array[String] = []
	for item_id: String in ORDER:
		if colors(item_id).has(color):
			pool.append(item_id)
	return pool


## The item's icon, or the first dropping colour's mana symbol when it has none of its own.
static func icon(item_id: String) -> Texture2D:
	var file: String = String(get_item(item_id).get("icon", ""))
	var fallback: Array = colors(item_id)
	var fallback_color: String = String(fallback[0]) if not fallback.is_empty() else ""
	if file != "":
		var path: String = SpellDatabase.ICON_ROOT + file
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return SpellDatabase.get_icon(fallback_color)


## "Dropped by the red boss" / "...the blue or white boss", for the menu.
static func source_text(item_id: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	for color: Variant in colors(item_id):
		names.append(String(color).capitalize())
	if names.is_empty():
		return ""
	return "Dropped by the %s boss" % " or ".join(names)
