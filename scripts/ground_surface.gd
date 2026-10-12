class_name GroundSurface
extends RefCounted
## What the ground is made of at a point on the map, as far as a footstep cares.
##
## Read off the TerraBrush terrain: `getPositionInformation` hands back every texture set
## painted at a point, heaviest first, so the first one is what the ground mostly looks like
## there. Which sound a texture makes is decided by its albedo's file name - TerraBrush's
## texture sets in this map are unnamed, and the file name is the one thing about them that
## says "grass" or "rock".
##
## Two surfaces, because two were recorded. Grass, moss and the soft brown mud take the
## grass steps; everything else - rock, gravel, dry ground and sand - crunches. A new
## texture set falls into the gravel side unless its file name matches SOFT_KEYWORDS.

const FOOTSTEP_SOFT := &"footstep_grass"
const FOOTSTEP_HARD := &"footstep_gravel"

## Substrings of a texture set's albedo path that mark it as soft ground.
const SOFT_KEYWORDS: Array[String] = ["Grass", "Moss", "BrownMud03"]

## The terrain node and, per texture-set index, its footstep event. Static so every avatar
## shares one lookup; rebuilt whenever the terrain it was built from is gone (a new match).
static var _terrain: Node = null
static var _events: Array[StringName] = []


## The footstep event for a foot landing at `at`. Anywhere with no terrain under it - the
## lobby, a test scene - is grass.
static func footstep_event(at: Vector3) -> StringName:
	var terrain: Node = _find_terrain()
	if terrain == null:
		return FOOTSTEP_SOFT
	var info: Object = terrain.call("getPositionInformation", at.x, at.z)
	if info == null:
		return FOOTSTEP_SOFT
	var textures: Array = info.call("get_textures")
	if textures.is_empty():
		return FOOTSTEP_SOFT
	var index: int = int(textures[0].call("get_index"))
	return _events[index] if index >= 0 and index < _events.size() else FOOTSTEP_SOFT


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
			_events.append(_event_for(albedo.resource_path if albedo != null else ""))
	_terrain = terrain
	return _terrain


static func _event_for(albedo_path: String) -> StringName:
	for keyword: String in SOFT_KEYWORDS:
		if keyword in albedo_path:
			return FOOTSTEP_SOFT
	return FOOTSTEP_HARD
