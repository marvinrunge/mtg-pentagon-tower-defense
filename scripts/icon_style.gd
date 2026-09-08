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

## Shared rather than one per icon: every icon rounds by the same ratio, so per-icon copies
## would buy nothing and cost a material switch each.
static var _material: ShaderMaterial = null
static var _bright_material: ShaderMaterial = null


static func rounded_material(bright: bool = false) -> ShaderMaterial:
	var material: ShaderMaterial = _bright_material if bright else _material
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load(SHADER_PATH) as Shader
		material.set_shader_parameter("radius_ratio", CORNER_RATIO)
		material.set_shader_parameter("ignore_tint", bright)
		if bright:
			_bright_material = material
		else:
			_material = material
	return material
