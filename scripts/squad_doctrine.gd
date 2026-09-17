extends Node
class_name SquadDoctrine
## How a colour fights as a UNIT: the shape its wave spawns in, how fast that shape
## marches, and when it stops being a formation and becomes a brawl.
##
## Waves used to be a trickle. Each colour's contingent arrived one enemy at a time on a
## per-enemy timer, which meant a "wave" was really five separate queues feeding five
## lanes, and the player fought a queue rather than an army. A whole colour now arrives
## at once, already standing in formation, and walks in as one body.
##
## The formation itself is the same idea every time and only its proportions change:
##
##     melee screen        #  #  #  #  #      <- closest to the crystal
##     archer shell         o     o
##                       o    M M    o        <- M = mages, in the middle
##                          o  o  o
##
## Mages are the squad's whole reason to exist - a White mage heals the rank in front of
## it, a Green one pumps whatever it can reach - so they stand in the middle where the
## player cannot reach them without going through everything else. Archers ring them.
## Melee stand in front of both, because they are the only ones that want to be there.
##
## Per-colour differences are deliberately expressed as GEOMETRY and SPEED rather than as
## extra states. A doctrine that needs its own branch in the squad brain is a doctrine
## that can deadlock; one that only moves numbers around cannot.

## Every key a doctrine can set, with the value used when a colour does not override it.
##
##   shape             "line" (ranks), "wedge" (an arrowhead) or "mob" (no ranks at all)
##   file_spacing      side-to-side gap between neighbours
##   rank_spacing      front-to-back gap between ranks
##   front_width       how many melee stand in one rank before a new one forms behind it
##   shell_gap         gap between the mage core and the archer ring around it
##   screen_gap        gap between the archer ring and the first melee rank
##   caster_setback    extra distance between the melee screen and the caster shell,
##                     applied by pushing the melee screen further FORWARD rather than
##                     pulling the casters back - the mage core sits at squad-local z=0,
##                     at or just ahead of the spawner, and never behind it: the walkable
##                     lane runs forward from the spawner toward the crystal, not behind
##                     it, and a caster shoved past the spawner lands off the baked navmesh
##                     with no path back onto its own formation. (This used to shift the
##                     casters backward instead, which is exactly how it put a Blue mage
##                     off the map - see WAVE_DESIGN.md.)
##   jitter            random scatter applied to every slot, so a rank is not a ruler line
##   march_mult        squad march speed as a fraction of its SLOWEST member's speed,
##                     clamped to the fastest member so the formation cannot run away from
##                     the people in it. Below 1.0 is a deliberate, disciplined advance;
##                     above 1.0 means the colour does not much care who it leaves behind
##   charge_mult       how much faster the squad moves once it charges
##   charge_seconds    how long the charge speed bonus lasts on the members themselves, so
##                     it does not evaporate at the moment of contact
##   break_radius      distance from the crystal at which the formation dissolves and every
##                     member goes back to fighting for itself. Small = holds together to
##                     the last step; large = falls apart early and arrives as a rabble
##   break_on_damage   whether being hit is enough to make a member abandon its slot
##   leash             how far a member may be shoved from its slot before it gives up on
##                     the formation rather than walking back into a fight it has left
##   banner            what the arrival is called on the warning banner
const DEFAULT: Dictionary = {
	"shape": "line",
	"file_spacing": 2.2,
	"rank_spacing": 2.0,
	"front_width": 5,
	"shell_gap": 2.4,
	"screen_gap": 3.0,
	"caster_setback": 0.0,
	"jitter": 0.35,
	"march_mult": 1.0,
	"charge_mult": 1.25,
	"charge_seconds": 6.0,
	"break_radius": 26.0,
	"break_on_damage": false,
	"leash": 14.0,
	"banner": "WARBAND",
}

## One doctrine per colour, written to the colour pie rather than to a difficulty curve.
## Every one of these is the SAME set of enemies arranged differently - the wave planner
## decides how many of each class a colour gets, and this decides what that looks like.
const DOCTRINES: Dictionary = {
	# Order as a virtue. The tightest formation in the game, and the one that holds
	# longest: a White rank is still a rank when it reaches the crystal, which is what
	# makes its mages worth protecting - they are healing a line that is still standing
	# in front of them.
	"White": {
		"shape": "line",
		"file_spacing": 1.8,
		"rank_spacing": 1.7,
		"front_width": 6,
		"shell_gap": 2.0,
		"screen_gap": 2.6,
		"jitter": 0.15,
		"march_mult": 0.95,
		"charge_mult": 1.15,
		"break_radius": 16.0,
		"leash": 10.0,
		"banner": "PHALANX",
	},
	# Blue never wanted to be in the fight. Its melee screen advances normally and its
	# casters hang a long way back behind it - a skirmish line rather than a block. The
	# setback is the whole doctrine: killing a Blue mage means walking past everything
	# Blue brought with it.
	"Blue": {
		"shape": "line",
		"file_spacing": 3.2,
		"rank_spacing": 2.6,
		"front_width": 6,
		"shell_gap": 3.2,
		"screen_gap": 5.0,
		"caster_setback": 9.0,
		"jitter": 0.5,
		"march_mult": 1.0,
		"charge_mult": 1.1,
		"break_radius": 30.0,
		"leash": 20.0,
		"banner": "SKIRMISH LINE",
	},
	# A column, not a line: narrow and very deep, so Black arrives as something that keeps
	# arriving. It shambles in slower than anything else and its ranks are ragged.
	"Black": {
		"shape": "line",
		"file_spacing": 2.0,
		"rank_spacing": 1.6,
		"front_width": 4,
		"shell_gap": 2.0,
		"screen_gap": 2.2,
		"jitter": 0.8,
		"march_mult": 0.9,
		"charge_mult": 1.3,
		"charge_seconds": 7.0,
		"break_radius": 34.0,
		"leash": 16.0,
		"banner": "HORDE",
	},
	# Goblins do not hold formation, they hold it briefly. The shape exists only so the
	# mob leaves the lane together; it comes apart less than halfway down (break_radius is
	# most of the lane) and any goblin that gets hit abandons it on the spot. march_mult
	# above 1.0 says out loud that the fast ones do not wait for the slow ones.
	"Red": {
		"shape": "mob",
		"file_spacing": 2.4,
		"rank_spacing": 2.0,
		"jitter": 1.4,
		"march_mult": 1.6,
		"charge_mult": 1.5,
		"charge_seconds": 8.0,
		"break_radius": 90.0,
		"break_on_damage": true,
		"leash": 12.0,
		"banner": "WARBAND",
	},
	# An arrowhead with the casters in the pocket behind the point. Slow to arrive and
	# very hard to turn: Green holds together nearly to the crystal and hits the hardest
	# when it finally charges.
	"Green": {
		"shape": "wedge",
		"file_spacing": 2.6,
		"rank_spacing": 2.4,
		"front_width": 7,
		"shell_gap": 2.6,
		"screen_gap": 3.4,
		"jitter": 0.3,
		"march_mult": 0.9,
		"charge_mult": 1.35,
		"charge_seconds": 9.0,
		"break_radius": 20.0,
		"leash": 18.0,
		"banner": "STAMPEDE",
	},
}

## Golden angle. Used by the mob scatter so a Red blob is evenly filled rather than
## clumped in the middle the way uniform random points in a disc are.
const GOLDEN_ANGLE: float = 2.39996323


static func get_doctrine(color: String) -> Dictionary:
	var doctrine: Dictionary = DEFAULT.duplicate()
	var overrides: Dictionary = DOCTRINES.get(color, {})
	for key: String in overrides:
		doctrine[key] = overrides[key]
	return doctrine


## Slot positions for a whole squad, in squad-local space: +Z points at the crystal, +X is
## the squad's right, Y is always 0 (the spawner snaps everything to the navmesh anyway).
##
## `counts` is class name -> how many, e.g. {"Melee": 6, "Ranged": 4, "Mage": 2}. The
## return is the same keys mapped to one Array[Vector3] each, in the order the enemies of
## that class should be handed out.
static func build_formation(color: String, counts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var doctrine: Dictionary = get_doctrine(color)
	var melee_count: int = int(counts.get("Melee", 0))
	var ranged_count: int = int(counts.get("Ranged", 0))
	var mage_count: int = int(counts.get("Mage", 0))

	var file: float = float(doctrine["file_spacing"])
	var rank: float = float(doctrine["rank_spacing"])
	var slots: Dictionary = {}

	if String(doctrine["shape"]) == "mob":
		# No ranks. Classes are only biased along the lane, so the melee are generally in
		# front and the mages generally behind without anything actually holding a line.
		slots["Melee"] = _scatter(melee_count, file, rank * 1.5)
		slots["Ranged"] = _scatter(ranged_count, file, 0.0)
		slots["Mage"] = _scatter(mage_count, file, -rank * 1.5)
	else:
		# The mage core sits on the squad origin, and everything else is measured off it.
		var mages: Array[Vector3] = _grid(mage_count, 3, file, rank)
		var core_radius: float = _outer_radius(mages)
		var ring_radius: float = maxf(core_radius, file * 0.5) + float(doctrine["shell_gap"])
		var ranged: Array[Vector3] = _rings(ranged_count, ring_radius, file)
		# caster_setback widens the melee-to-caster gap by pushing the SCREEN further
		# forward rather than pulling the casters back behind the spawner - see this
		# function's own doc comment on caster_setback for why the direction matters.
		var screen_z: float = _forward_extent(ranged, ring_radius) + float(doctrine["screen_gap"]) + float(doctrine["caster_setback"])
		var melee: Array[Vector3] = []
		if String(doctrine["shape"]) == "wedge":
			melee = _wedge(melee_count, screen_z, file, rank)
		else:
			melee = _ranks(melee_count, screen_z, int(doctrine["front_width"]), file, rank)

		slots["Melee"] = melee
		slots["Ranged"] = ranged
		slots["Mage"] = mages

	# Bosses never stand in a formation - they are a squad of one and the shape would be a
	# single point anyway - but the planner still asks for their slot so it has somewhere
	# to put them.
	slots["Boss"] = _grid(int(counts.get("Boss", 0)), 2, file * 2.0, rank * 2.0)

	var jitter: float = float(doctrine["jitter"])
	if jitter > 0.0 and rng != null:
		for key: String in slots:
			var positions: Array = slots[key]
			for i: int in range(positions.size()):
				positions[i] += Vector3(rng.randf_range(-jitter, jitter), 0.0, rng.randf_range(-jitter, jitter))
	return slots


## Turns a squad-local slot into a world position. `forward` must be a flat unit vector
## pointing where the squad is going; the right-hand axis is derived from it so a squad
## only ever has to track one direction.
static func to_world(anchor: Vector3, forward: Vector3, offset: Vector3) -> Vector3:
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return anchor + right * offset.x + forward * offset.z


# --- Formation primitives ------------------------------------------------------------
#
# All of these work in squad-local space and all of them are centred on x = 0, because the
# caller only ever wants to know where a block is relative to the squad's own line of
# advance.

## Rows of at most `per_row`, centred, growing BACKWARDS from z = 0.
static func _grid(count: int, per_row: int, file: float, rank: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var width: int = maxi(1, mini(per_row, count))
	for i: int in range(count):
		var row: int = i / width
		var column: int = i % width
		# The last row is usually short; centring it on its own width rather than on the
		# full one keeps the block symmetrical instead of left-heavy.
		var row_width: int = mini(width, count - row * width)
		var x: float = (float(column) - float(row_width - 1) * 0.5) * file
		out.append(Vector3(x, 0.0, -float(row) * rank))
	return out


## Concentric rings around the origin, filled from the inside out. Angle 0 is the squad's
## forward direction, so the first archer of a ring stands in front of the mages and the
## rest of the ring closes around behind them.
static func _rings(count: int, radius: float, spacing: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var placed: int = 0
	var ring_radius: float = radius
	while placed < count:
		var capacity: int = maxi(4, int(floor(TAU * ring_radius / maxf(spacing, 0.1))))
		var on_ring: int = mini(capacity, count - placed)
		for i: int in range(on_ring):
			var angle: float = TAU * float(i) / float(on_ring)
			out.append(Vector3(sin(angle) * ring_radius, 0.0, cos(angle) * ring_radius))
		placed += on_ring
		ring_radius += spacing
	return out


## Ranks stacked FORWARD from `front_z`, so a bigger melee contingent pushes its wall
## further ahead of the archers instead of crowding into them.
static func _ranks(count: int, front_z: float, width: int, file: float, rank: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var row_width: int = maxi(1, width)
	for i: int in range(count):
		var row: int = i / row_width
		var column: int = i % row_width
		var this_row: int = mini(row_width, count - row * row_width)
		var x: float = (float(column) - float(this_row - 1) * 0.5) * file
		out.append(Vector3(x, 0.0, front_z + float(row) * rank))
	return out


## An arrowhead: one unit at the point, the rest falling back alternately to either side.
## Green's stampede, and the reason a Green wave punches a hole rather than pushing a wall.
static func _wedge(count: int, front_z: float, file: float, rank: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var arms: int = (count + 1) / 2
	var apex_z: float = front_z + float(arms) * rank * 0.6
	for i: int in range(count):
		var arm: int = (i + 1) / 2
		var side: float = 1.0 if i % 2 == 1 else -1.0
		if arm == 0:
			side = 0.0
		out.append(Vector3(side * float(arm) * file * 0.9, 0.0, apex_z - float(arm) * rank * 0.6))
	return out


## A blob with no structure, laid out on a sunflower spiral so it fills evenly, then
## pushed along the lane by `z_bias` to keep the classes loosely layered.
static func _scatter(count: int, spacing: float, z_bias: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in range(count):
		var angle: float = float(i) * GOLDEN_ANGLE
		var radius: float = spacing * 0.62 * sqrt(float(i) + 0.5)
		out.append(Vector3(sin(angle) * radius, 0.0, cos(angle) * radius + z_bias))
	return out


static func _outer_radius(positions: Array[Vector3]) -> float:
	var radius: float = 0.0
	for position: Vector3 in positions:
		radius = maxf(radius, Vector2(position.x, position.z).length())
	return radius


## How far forward the archer ring reaches. Falls back to the ring radius when there are
## no archers at all, so the melee screen still stands clear of the mage core.
static func _forward_extent(positions: Array[Vector3], fallback: float) -> float:
	if positions.is_empty():
		return fallback
	var extent: float = -INF
	for position: Vector3 in positions:
		extent = maxf(extent, position.z)
	return maxf(extent, fallback)
