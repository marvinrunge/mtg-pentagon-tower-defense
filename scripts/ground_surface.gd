class_name GroundSurface
extends RefCounted
## What the ground is made of at a point on the map, as far as a footstep cares.
##
## Read off the TerraBrush terrain: `getPositionInformation` hands back every texture set
## painted at a point, heaviest first, so the first one is what the ground mostly looks like
## there. Which sound a texture makes is decided by the name of the folder its albedo lives
## in (`.../Textures/Rock037/Rock037_Albedo.png` -> "Rock037") - TerraBrush's texture sets
## in this map are unnamed, and the texture's own name is the one thing about them that says
## "grass" or "rock".

const FOOTSTEP_GRASS := &"footstep_grass"
const FOOTSTEP_GRAVEL := &"footstep_gravel"
const FOOTSTEP_MUD := &"footstep_mud"
const FOOTSTEP_ROCK := &"footstep_rock"
## Every event this can return, so a caller can check they all exist.
const FOOTSTEP_EVENTS: Array[StringName] = [FOOTSTEP_GRASS, FOOTSTEP_GRAVEL, FOOTSTEP_MUD, FOOTSTEP_ROCK]

## [texture name prefix, event], first match wins - so "BrownMudRocks" has to come before
## both "BrownMud" and "Rock", which it would otherwise be taken for. Anything unmatched -
## the dry ground and sand textures - crunches like gravel, as does somewhere with no
## terrain at all.
const SURFACES := [
	["Grass", FOOTSTEP_GRASS],
	["Moss", FOOTSTEP_GRASS],
	["BrownMudRocks", FOOTSTEP_GRAVEL],
	["BrownMud", FOOTSTEP_MUD],
	["Rock", FOOTSTEP_ROCK],
]
const DEFAULT_EVENT := FOOTSTEP_GRAVEL

## The terrain node and, per texture-set index, its footstep event. Static so every avatar
## shares one lookup; rebuilt whenever the terrain it was built from is gone (a new match).
static var _terrain: Node = null
static var _events: Array[StringName] = []


## The footstep event for a foot landing at `at`.
static func footstep_event(at: Vector3) -> StringName:
	var terrain: Node = _find_terrain()
	if terrain == null:
		return DEFAULT_EVENT
	var info: Object = terrain.call("getPositionInformation", at.x, at.z)
	if info == null:
		return DEFAULT_EVENT
	var textures: Array = info.call("get_textures")
	if textures.is_empty():
		return DEFAULT_EVENT
	var index: int = int(textures[0].call("get_index"))
	return _events[index] if index >= 0 and index < _events.size() else DEFAULT_EVENT


static func _find_terrain() -> Node:
	if is_instance_valid(_terrain):
		return _terrain
	_terrain = null
	_events.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	var terrain: Node = tree.current_scene.get_node_or_null("TerraBrush")
	if terrain == null or not terrain.has_method("getPositionInformation"):
		return null
	var sets: Resource = terrain.get("textureSets")
	if sets != null:
		for texture_set: Resource in sets.get("textureSets"):
			var albedo: Texture2D = texture_set.get("albedoTexture") if texture_set != null else null
			_events.append(event_for_texture(albedo.resource_path.get_base_dir().get_file() if albedo != null else ""))
	_terrain = terrain
	return _terrain


## The footstep event for a terrain texture, by its name ("Rock037", "Grass004").
static func event_for_texture(texture_name: String) -> StringName:
	for entry: Array in SURFACES:
		if texture_name.begins_with(String(entry[0])):
			return entry[1]
	return DEFAULT_EVENT
