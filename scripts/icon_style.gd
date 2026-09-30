extends RefCounted
## One rounded-corner look for every spell icon the game draws.
##
## The icons are square PNGs with hard edges. Left alone they read as stickers pasted onto
## the UI - a square of art inside a rounded slot, or a square of art on a round skill
## node - so every place that shows one rounds it by the same fraction of its own size.
##
## A fraction rather than a pixel count: the hotbar draws them at 60px, the skill tree at
## its node size and the mana row at 24px, and one radius in pixels would look heavy on
## the small ones and timid on the large ones.
##
## Done in a SHADER because none of the three is a plain rectangle we control the drawing
## of: a TextureRect and a TextureButton have no corner_radius, and clipping against the
## slot's own StyleBoxFlat would multiply the icon by that stylebox's translucent
## background. Masking the alpha is the one approach that works the same everywhere.
##
## Deliberately no `class_name`: a headless build or test run does not rescan the project,
## so a global class added in the same commit is not in the script class cache yet and
## every consumer would fail to compile on the very run that adds it. Preloaded by path
## instead - see tools/animation_impact.gd for the same reasoning.

const SHADER_PATH := "res://assets/shaders/rounded_icon.gdshader"

## As a fraction of the icon's shorter side, so 0.25 is a quarter of the icon's height.
const CORNER_RATIO: float = 0.25

## A full circle - the radius ratio at which the rounded box meets itself.
const CIRCLE_RATIO: float = 0.5

## Shared rather than one per icon: every icon rounds by the same ratio, so per-icon copies
## would buy nothing and cost a material switch each. Four in all: rounded or round, each
## tinted or bright.
static var _materials: Dictionary = {}


## The rounded square every icon that can go on the hotbar wears - an ACTIVE spell.
static func rounded_material(bright: bool = false) -> ShaderMaterial:
	return _cached(CORNER_RATIO, bright)


## The full circle a PASSIVE node wears in the skill tree - an affinity or an aura, something
## that is always on and never goes on the bar. The shape is the whole distinction: square is
## "cast me", round is "I just work", the convention WoW and Path of Exile taught players.
static func circle_material(bright: bool = false) -> ShaderMaterial:
	return _cached(CIRCLE_RATIO, bright)


static func _cached(ratio: float, bright: bool) -> ShaderMaterial:
	var key: String = "%.2f|%s" % [ratio, bright]
	var material: ShaderMaterial = _materials.get(key, null)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load(SHADER_PATH) as Shader
		material.set_shader_parameter("radius_ratio", ratio)
		material.set_shader_parameter("ignore_tint", bright)
		_materials[key] = material
	return material
