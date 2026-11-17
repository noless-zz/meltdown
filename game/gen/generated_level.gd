class_name GeneratedLevel
extends RefCounted

## Turns a `MineGenerator`'s output into a `LevelDef` the game can fly (#317,
## #356): its boxes, no robots, the start `MineGenerator.START_INSET_MM` inside
## the oldest open connector facing in, and with a `ReactorPlan` a reactor.
##
## The reactor goes to the module furthest from the first module in joins:
## each placement is one join further than its parent, and parents are always
## placed earlier, so one pass in placement order is the breadth-first walk
## over the placement parents. Ties go to the later placement. It sits at the
## centre of that module's largest box (ties to the lower box), so an L-shaped
## module still holds it; it is left out, with `MineGenerator.reactor_note`
## set, when the furthest module is fewer than `min_hops` joins away or that
## box cannot hold the reactor with a ship's diameter clear on every side.
## Positions are whole millimetres from the placements, so the same seed puts
## the reactor in the same place on every device (GEN-2, ARC-2).


## The level for `generator`. With no open connector the level is empty and
## `error` says so, as `LevelDef.parse_json` leaves it. Not checked here:
## `LevelValidator` does that.
static func build(generator: MineGenerator, plan: ReactorPlan, ship_radius: float) -> LevelDef:
	var level: LevelDef = LevelDef.new()
	generator.reactor_note = ""
	generator.reactor_placement = -1
	if generator.open_connectors.is_empty():
		level.error = "no open connector to start at"
		return level
	var opening: ModuleConnector = generator.open_connectors[0]
	var inward: Vector3i = -ModuleTurns.outward(opening)
	level.union = BoxUnion.new(generator.union.boxes.duplicate())
	level.start_position_mm = opening.position_mm + inward * MineGenerator.START_INSET_MM
	level.start_facing_mm = inward * RobotSpawn.SCALE
	if plan != null:
		_place_reactor(generator, plan, ship_radius, level)
	return level


## Joins between the first module and each placement, in placement order.
static func hops(generator: MineGenerator) -> Array[int]:
	var found: Array[int] = []
	for placement: ModulePlacement in generator.placements:
		found.append(0 if placement.parent < 0 else found[placement.parent] + 1)
	return found


## The box index of a placement's largest box; ties go to the lower index.
static func largest_box(generator: MineGenerator, placement: ModulePlacement) -> int:
	var best: int = placement.first_box
	var best_volume: int = -1
	for index: int in range(placement.first_box, placement.end_box):
		var size: Vector3i = generator.max_mm[index] - generator.min_mm[index]
		var volume: int = size.x * size.y * size.z
		if volume > best_volume:
			best = index
			best_volume = volume
	return best


static func _place_reactor(generator: MineGenerator, plan: ReactorPlan, ship_radius: float,
		level: LevelDef) -> void:
	var depth: Array[int] = hops(generator)
	var furthest: int = 0
	for index: int in depth.size():
		if depth[index] >= depth[furthest]:
			furthest = index
	if depth[furthest] < plan.min_hops:
		generator.reactor_note = "no reactor: the furthest module is %d joins from the first, below %d" \
				% [depth[furthest], plan.min_hops]
		return
	var box: int = largest_box(generator, generator.placements[furthest])
	var low: Vector3i = generator.min_mm[box]
	var high: Vector3i = generator.max_mm[box]
	var centre: Vector3i = (low + high) / 2
	var clear_mm: int = plan.reactor.radius_mm + roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	for axis: int in 3:
		if centre[axis] - clear_mm < low[axis] or centre[axis] + clear_mm > high[axis]:
			generator.reactor_note = "no reactor: box %d of module %d is too small for the reactor and a ship's diameter" \
					% [box, furthest]
			return
	var reactor: ReactorState = plan.reactor.fresh_copy()
	reactor.position_mm = centre
	reactor.exit_radius_mm = level.exit_radius_mm
	level.reactor = reactor
	generator.reactor_placement = furthest
