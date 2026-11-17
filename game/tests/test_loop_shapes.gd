extends RefCounted

## Z bridges (#411, GEN-5, ARC-4): near-facing open connectors offset sideways
## up to `loop_max_offset_m` get a leg out of each doorway and a cross box, the
## passage clears a ship at every joint, and offsets over the limit, a blocked
## middle and openings facing away are left alone.

const SeedSweep := preload("res://tests/seed_sweep.gd")
## Sideways offset of the second opening in the hand-built pair, mm.
const SHIFT_MM: int = 12000


func _bridges(offset: float) -> LoopBridges:
	return LoopBridges.parse_json(JSON.stringify(
			{"loop_min_m": 6, "loop_max_m": 60, "loop_max_count": 2, "loop_max_offset_m": offset,
			"dead_end_min_open": 6}))


## Adds a placement to a hand-built level: one box and its open connectors.
func _place(generator: MineGenerator, low: Vector3i, high: Vector3i,
		connectors: Array[ModuleConnector]) -> void:
	var placement: ModulePlacement = ModulePlacement.new("hand_%d" % generator.placements.size())
	placement.first_box = generator.min_mm.size()
	generator.add_box(low, high)
	placement.end_box = generator.min_mm.size()
	for index: int in connectors.size():
		generator.open_connectors.append(connectors[index])
		generator.open_owner.append(Vector2i(generator.placements.size(), index))
	generator.placements.append(placement)


## Two 20 m tubes 20 m apart along z, openings facing but `shift_mm` apart
## along x; the first also opens at its far end, which stays open for the start.
func _offset_pair(shift_mm: int = SHIFT_MM) -> MineGenerator:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-10000, -10000, -30000), Vector3i(10000, 10000, 0), [
		ModuleConnector.new(Vector3i(0, 0, 0), "+z"),
		ModuleConnector.new(Vector3i(0, 0, -30000), "-z"),
	])
	_place(generator, Vector3i(-10000 + shift_mm, -10000, 20000), Vector3i(10000 + shift_mm, 10000, 50000), [
		ModuleConnector.new(Vector3i(shift_mm, 0, 20000), "-z"),
	])
	return generator


## Overlap of two boxes on each axis, mm.
func _overlap(generator: MineGenerator, a: int, b: int) -> Vector3i:
	var overlap: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		overlap[axis] = mini(generator.max_mm[a][axis], generator.max_mm[b][axis]) \
				- maxi(generator.min_mm[a][axis], generator.min_mm[b][axis])
	return overlap


func test_shipped_offset_is_set() -> String:
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	return "" if bridges.error == "" and bridges.max_offset_mm > 0 \
			else "generator.json: %s, offset %d mm" % [bridges.error, bridges.max_offset_mm]


func test_straight_shape_for_openings_in_line() -> String:
	var boxes: Array[Vector3i] = LoopShapes.straight(ModuleConnector.new(Vector3i(0, 0, 0), "+z"),
			ModuleConnector.new(Vector3i(0, 0, 20000), "-z"))
	return "" if boxes.size() == 2 and boxes[0] == Vector3i(-4000, -4000, 0) and boxes[1] == Vector3i(4000, 4000, 20000) \
			else "straight is %s" % [boxes]


func test_offset_within_limit_gets_a_z_that_clears_a_ship_at_every_joint() -> String:
	var generator: MineGenerator = _offset_pair()
	var before: int = generator.min_mm.size()
	if _bridges(20).apply(generator) != 1:
		return "an opening 12 m sideways was not bridged under a 20 m limit"
	if generator.min_mm.size() != before + 5:
		return "%d boxes added, expected two legs, a cross box and two doorways" % (generator.min_mm.size() - before)
	var leg_a: int = before
	var cross: int = before + 1
	var leg_b: int = before + 2
	if generator.min_mm[leg_a] != Vector3i(-4000, -4000, 0) or generator.max_mm[leg_a] != Vector3i(4000, 4000, 14000):
		return "first leg is %s..%s" % [generator.min_mm[leg_a], generator.max_mm[leg_a]]
	if generator.min_mm[cross] != Vector3i(-4000, -4000, 6000) or generator.max_mm[cross] != Vector3i(16000, 4000, 14000):
		return "cross box is %s..%s" % [generator.min_mm[cross], generator.max_mm[cross]]
	if generator.min_mm[leg_b] != Vector3i(8000, -4000, 6000) or generator.max_mm[leg_b] != Vector3i(16000, 4000, 20000):
		return "second leg is %s..%s" % [generator.min_mm[leg_b], generator.max_mm[leg_b]]
	var diameter_mm: int = roundi(2.0 * SeedSweep.ship_radius() * RobotSpawn.SCALE)
	# Door at a, first leg, cross, second leg, door at b: the path a ship flies.
	var path: Array[int] = [before + 3, leg_a, cross, leg_b, before + 4]
	for step: int in path.size() - 1:
		var overlap: Vector3i = _overlap(generator, path[step], path[step + 1])
		for axis: int in 3:
			if overlap[axis] < diameter_mm:
				return "joint %d overlaps %s mm, under a ship's %d mm" % [step, overlap, diameter_mm]
	for joint: Array in [[leg_a, cross], [cross, leg_b]]:
		var overlap: Vector3i = _overlap(generator, joint[0], joint[1])
		if overlap.x < 8000 or overlap.y < 8000 or overlap.z < 8000:
			return "a bend overlaps %s mm, narrower than the 8 m connector" % overlap
	return "" if generator.open_connectors.size() == 1 else "%d connectors left open" % generator.open_connectors.size()


func test_offset_over_the_limit_is_not_bridged() -> String:
	var generator: MineGenerator = _offset_pair()
	if _bridges(11.999).apply(generator) != 0:
		return "an opening 12 m sideways was bridged under an 11.999 m limit"
	return "" if generator.open_connectors.size() == 3 else "connectors were taken off the open list"


func test_blocked_middle_box_is_not_bridged() -> String:
	var generator: MineGenerator = _offset_pair()
	# Inside the cross box only, between the two legs.
	_place(generator, Vector3i(5000, -1000, 9000), Vector3i(7000, 1000, 11000), [])
	return "" if _bridges(20).apply(generator) == 0 else "the Z was cut through a box in its middle"


func test_openings_facing_away_are_not_bridged() -> String:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-10000, -10000, -30000), Vector3i(10000, 10000, 0), [
		ModuleConnector.new(Vector3i(0, 0, -30000), "-z"),
		ModuleConnector.new(Vector3i(10000, 0, -15000), "+x"),
	])
	_place(generator, Vector3i(2000, -10000, 20000), Vector3i(22000, 10000, 50000), [
		ModuleConnector.new(Vector3i(12000, 0, 50000), "+z"),
	])
	return "" if _bridges(100).apply(generator) == 0 else "openings facing away were bridged"


func test_gap_shorter_than_a_tunnel_width_gets_no_z() -> String:
	var from: ModuleConnector = ModuleConnector.new(Vector3i(0, 0, 0), "+z")
	var to: ModuleConnector = ModuleConnector.new(Vector3i(12000, 0, 7999), "-z")
	return "" if LoopShapes.z_shape(from, to).is_empty() else "a Z was shaped in a 7.999 m gap"
