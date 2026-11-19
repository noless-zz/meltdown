class_name ReplayStartLine
extends RefCounted

## Writes and reads a replay's start lines (version 14, #328): `start <ship
## index> <x> <y> <z> <fx> <fy> <fz>`, at most one per ship, giving the pose the
## ship starts at and resets to (`Sim.set_start_pose`). Without one a ship
## starts at the origin facing -z, as every replay before version 14 does.
##
## Position is in whole millimetres, like robot spawns. Facing is a unit vector
## times `RobotSpawn.SCALE`, rounded to whole numbers, and turned back into an
## orientation exactly as a robot's facing is (`RobotSpawn.facing_basis`), so
## the pose read back from the text is the pose the run is given. The format is
## documented in `Replay`.

## First format version that may carry a start line.
const VERSION: int = 14


## A position in metres as whole millimetres.
static func position_mm(metres: Vector3) -> Vector3i:
	return Vector3i(roundi(metres.x * RobotSpawn.SCALE), roundi(metres.y * RobotSpawn.SCALE),
		roundi(metres.z * RobotSpawn.SCALE))


## A facing of any non-zero length as a unit vector in thousandths.
static func facing_mm(facing: Vector3) -> Vector3i:
	return position_mm(facing.normalized())


static func text(ship_index: int, p_position_mm: Vector3i, p_facing_mm: Vector3i) -> String:
	var p: Vector3i = p_position_mm
	var f: Vector3i = p_facing_mm
	return "start %d %d %d %d %d %d %d" % [ship_index, p.x, p.y, p.z, f.x, f.y, f.z]


## `words` is the whole line split on spaces, starting with "start". Returns
## "" with the pose stored on `replay`, or a problem without the line number,
## which `Replay.from_text` adds.
static func parse(replay: Replay, words: PackedStringArray,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a start line needs format version %d or later" % VERSION
	# The index is checked against the ship count, so that must be known.
	if not seen.has("ships"):
		return "a start line must come after the ships line"
	if words.size() != 8:
		return "start needs a ship index, a position and a facing"
	var values: Array[int] = []
	for index: int in range(1, 8):
		if not words[index].is_valid_int():
			return "'%s' is not a whole number" % words[index]
		values.append(words[index].to_int())
	var ship: int = values[0]
	if ship < 0 or ship >= replay.ship_count:
		return "start ship index must be 0 to %d, found %d" % [replay.ship_count - 1, ship]
	var seen_key: String = "start %d" % ship
	if seen.has(seen_key):
		return "'%s' appears twice" % seen_key
	seen[seen_key] = true
	var at_mm: Vector3i = Vector3i(values[1], values[2], values[3])
	var limit: int = roundi(RobotSpawn.MAX_COORDINATE_M * RobotSpawn.SCALE)
	if absi(at_mm.x) > limit or absi(at_mm.y) > limit or absi(at_mm.z) > limit:
		return "start position must be within %s m of the origin" % RobotSpawn.MAX_COORDINATE_M
	var facing: Vector3i = Vector3i(values[4], values[5], values[6])
	if facing == Vector3i.ZERO:
		return "start facing must not be zero"
	replay.start_positions_mm[ship] = at_mm
	replay.start_facings_mm[ship] = facing
	return ""


## Every start line of `replay`, by ship index.
static func lines(replay: Replay) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for ship: int in replay.ship_count:
		if replay.start_positions_mm.has(ship):
			result.append(text(ship, replay.start_positions_mm[ship], replay.start_facings_mm[ship]))
	return result


## Gives each ship of `sim` that has a start line its start pose. Call it
## before the first tick, so the ship also starts there.
static func apply(replay: Replay, sim: Sim) -> void:
	for ship: int in replay.ship_count:
		if replay.start_positions_mm.has(ship):
			sim.set_start_pose(ship, position(replay, ship), orientation(replay, ship))


## Where ship `ship` of `replay` starts, metres: the origin without a start line.
static func position(replay: Replay, ship: int) -> Vector3:
	if not replay.start_positions_mm.has(ship):
		return Vector3.ZERO
	return Vector3(replay.start_positions_mm[ship]) / float(RobotSpawn.SCALE)


## How ship `ship` of `replay` starts turned: facing -z without a start line.
static func orientation(replay: Replay, ship: int) -> Basis:
	if not replay.start_facings_mm.has(ship):
		return Basis.IDENTITY
	return RobotSpawn.facing_basis(replay.start_facings_mm[ship])
