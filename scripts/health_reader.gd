class_name HealthReader
extends RefCounted
## Reads "how hurt is this thing" off anything on the player's side.
##
## There are three of them and they do not agree: `Player` calls it `hp`/`max_hp`, `Myr`
## and `TemporaryAlly` call it `health`/`max_health`. That was harmless while nothing
## looked at more than one of them at a time - white's skills are the first things in the
## game that treat players, myrs and summons as one list, and Healing Orb has to pick the
## most hurt member of that list.
##
## Renaming one of the three would have been the other option. It is not obviously right:
## `hp` reads better on a player and `health` reads better on everything the enemies
## share the field with, and the rename would touch far more code than it is worth. One
## place that knows about both is the cheaper answer, as long as it is the ONLY place.

## Current health, or -1.0 for something that has none.
static func current(node: Node) -> float:
	if "hp" in node:
		return float(node.hp)
	if "health" in node:
		return float(node.health)
	return -1.0


## Maximum health, or -1.0 for something that has none.
static func maximum(node: Node) -> float:
	if "max_hp" in node:
		return float(node.max_hp)
	if "max_health" in node:
		return float(node.max_health)
	return -1.0


## How full, 0.0 to 1.0 - or -1.0 for anything this cannot read, so a caller can tell
## "unreadable" apart from "on the point of death".
static func ratio(node: Node) -> float:
	var maximum_health: float = maximum(node)
	if maximum_health <= 0.0:
		return -1.0
	var current_health: float = current(node)
	if current_health < 0.0:
		return -1.0
	return clampf(current_health / maximum_health, 0.0, 1.0)


## How much health is missing. What Circle of Protection and Rally the Fallen sort on.
static func missing(node: Node) -> float:
	var maximum_health: float = maximum(node)
	var current_health: float = current(node)
	if maximum_health < 0.0 or current_health < 0.0:
		return 0.0
	return maxf(maximum_health - current_health, 0.0)
