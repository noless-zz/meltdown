class_name RobotChecks
extends RefCounted

## The `robots` check of `LevelValidator` (#399, GEN-3, CMB-3): every robot a
## level starts with sits inside a box with its radius plus a ship's diameter
## clear of that box's faces, so a ship can fly round it; in a box the start
## reaches, so it can be fought; and outside the start module, so the pilot is
## not shot before the first input. A level with no robots passes.
##
## The clearance is worked in whole millimetres, as `GeneratedLevel` places
## robots: box corners are whole millimetres held in single-precision floats,
## so a robot placed exactly its clearance from a face would be failed by a
## rounding in metres (ARC-2).
##
## A robot's radius comes from its resolved `RobotDef`, else from the radii by
## id the caller hands over (the generator's robots are unresolved, and `gen/`
## opens no files). One with neither is a failure: a level must not pass a check
## nobody could run.


## The `robots` failures, one per robot at most, in robot order. `unreached`
## holds the boxes the start cannot reach; `start_module` the boxes of the
## module the start is in. Each message names the robot by index and type.
static func failures(level: LevelDef, ship_radius: float, start_box: int,
		unreached: Array[int], radii_mm: Dictionary[String, int],
		start_module: Array[int]) -> Array[String]:
	var found: Array[String] = []
	var boxes: Array[BoxBounds] = level.union.boxes
	var diameter_mm: int = roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	var spawns: Array[RobotSpawn] = level.robots.spawns
	for index: int in spawns.size():
		var spawn: RobotSpawn = spawns[index]
		var name: String = "robot %d (%s)" % [index, spawn.id]
		var radius_mm: int = RobotChecks.radius_mm(spawn, radii_mm)
		if radius_mm < 0:
			found.append("robots: %s has no known radius" % name)
			continue
		var clear_mm: int = radius_mm + diameter_mm
		var holding: Array[int] = []
		for box: int in boxes.size():
			if RobotChecks.holds_mm(boxes[box], spawn.position_mm, clear_mm):
				holding.append(box)
		if holding.is_empty():
			found.append("robots: %s at %s is not held by any box with %.2f m clear (radius plus a ship's diameter)"
					% [name, spawn.position(), clear_mm / float(RobotSpawn.SCALE)])
			continue
		var reached: bool = false
		for box: int in holding:
			if not unreached.has(box):
				reached = true
				break
		if not reached:
			found.append("robots: %s is in box %d, which cannot be reached from start box %d"
					% [name, holding[0], start_box])
			continue
		for box: int in start_module:
			if RobotChecks.holds_mm(boxes[box], spawn.position_mm, 0):
				found.append("robots: %s is inside the start module (box %d)" % [name, box])
				break
	return found


## The spawn's collision radius in millimetres, or -1 when it is not known.
static func radius_mm(spawn: RobotSpawn, radii_mm: Dictionary[String, int]) -> int:
	if spawn.def != null:
		return roundi(spawn.def.radius * RobotSpawn.SCALE)
	return radii_mm.get(spawn.id, -1)


## Whether `box` holds `point_mm` with `clear_mm` to spare on every side,
## counting a point exactly that far from a face as held.
static func holds_mm(box: BoxBounds, point_mm: Vector3i, clear_mm: int) -> bool:
	for axis: int in 3:
		var low: int = roundi(box.min_corner[axis] * RobotSpawn.SCALE)
		var high: int = roundi(box.max_corner[axis] * RobotSpawn.SCALE)
		if point_mm[axis] < low + clear_mm or point_mm[axis] > high - clear_mm:
			return false
	return true
