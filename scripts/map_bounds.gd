extends StaticBody3D
class_name MapBounds
## The invisible fence just inside the terrain's edge, so a player cannot walk, dash, leap
## or get knocked off the end of the world.
##
## Four tall boxes on a physics layer of their own (6, "Bounds") that only the player's
## mask includes (scenes/misc/player.tscn). Nothing else is meant to meet it: projectiles,
## spells and ragdolls fly on past rather than splashing against thin air at the horizon,
## and enemies and Myrs never get near it - they walk the navmesh.
##
## Sized from TerraBrush's zone, which is centred on the origin, so a bigger or smaller map
## moves the fence with it. Built by MainController at load.

## Physics layer 6. Only the player masks it.
const BOUNDS_LAYER := 32
## How far inside the terrain's edge the fence stands, in metres - far enough that the very
## edge, where the ground is cut off, is never reached.
const INSET := 6.0
## From well below the lowest ground (about -10 m) to far above the highest peak (about
## 113 m), so no leap or knock-up carries anyone over it.
const BOTTOM := -40.0
const TOP := 240.0
const THICKNESS := 4.0


## half_extent: half the terrain's width, i.e. where its edge is.
func build(half_extent: float) -> void:
	name = "MapBounds"
	collision_layer = BOUNDS_LAYER
	collision_mask = 0
	var inner: float = half_extent - INSET
	var height: float = TOP - BOTTOM
	var length: float = 2.0 * (inner + THICKNESS)
	var centre_y: float = BOTTOM + height * 0.5
	# Each wall's inner face sits on the fence line; the thickness is outside it.
	var walls: Array = [
		[Vector3(0.0, centre_y, -(inner + THICKNESS * 0.5)), Vector3(length, height, THICKNESS)],
		[Vector3(0.0, centre_y, inner + THICKNESS * 0.5), Vector3(length, height, THICKNESS)],
		[Vector3(-(inner + THICKNESS * 0.5), centre_y, 0.0), Vector3(THICKNESS, height, length)],
		[Vector3(inner + THICKNESS * 0.5, centre_y, 0.0), Vector3(THICKNESS, height, length)],
	]
	for wall: Array in walls:
		var box := BoxShape3D.new()
		box.size = wall[1]
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = wall[0]
		add_child(shape)
