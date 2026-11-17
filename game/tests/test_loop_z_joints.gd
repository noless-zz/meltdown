extends RefCounted

## Z bridge joints (#472, GEN-5, GEN-3, GEN-2): every two boxes of a bridge
## that meet share at least the connector's square, in the two cases #438
## found (a short gap, and an offset on two axes), and for every gap and
## offset a bridge can have, and seeds 0..999 pass the validator at the
## `loop_bias` #438 means to ship.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
## Small connector width, mm.
const WIDTH_MM: int = 8000
## Looped seeds of 0..999 at `loop_bias` 0.6: 214 when this was written, the
## same as before #472, since the reshaped Z rejects no pair. A margin below.
const MIN_LOOPED_AT_0_6: int = 200


func _bridges() -> LoopBridges:
	return LoopBridges.parse_json(JSON.stringify(
			{"loop_min_m": 6, "loop_max_m": 60, "loop_max_count": 2, "loop_max_offset_m": 40,
			"dead_end_min_open": 6, "loop_bias": 0}))


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


## Two 20 m tubes `gap_mm` apart along z, openings facing but `shift` apart
## across; the first also opens at its far end, which stays open for the start.
func _pair(gap_mm: int, shift: Vector3i) -> MineGenerator:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-10000, -10000, -30000), Vector3i(10000, 10000, 0), [
		ModuleConnector.new(Vector3i(0, 0, 0), "+z"),
		ModuleConnector.new(Vector3i(0, 0, -30000), "-z"),
	])
	var far: Vector3i = Vector3i(shift.x, shift.y, gap_mm)
	_place(generator, far + Vector3i(-10000, -10000, 0), far + Vector3i(10000, 10000, 30000), [
		ModuleConnector.new(far, "-z"),
	])
	return generator


## The boxes `apply` added after the first `before`, as corner pairs.
func _added(generator: MineGenerator, before: int) -> Array[Vector3i]:
	var boxes: Array[Vector3i] = []
	for index: int in range(before, generator.min_mm.size()):
		boxes.append_array([generator.min_mm[index], generator.max_mm[index]])
	return boxes


## The Z as #411 shaped it: each leg half a tunnel width past the middle.
func _old_z(from: ModuleConnector, to: ModuleConnector) -> Array[Vector3i]:
	var half: int = WIDTH_MM / 2
	var gap: int = to.position_mm.z - from.position_mm.z
	var middle: int = gap / 2
	var low_a: Vector3i = from.position_mm - Vector3i(half, half, 0)
	var high_a: Vector3i = from.position_mm + Vector3i(half, half, 0)
	high_a.z = middle + half
	var low_b: Vector3i = to.position_mm - Vector3i(half, half, 0)
	var high_b: Vector3i = to.position_mm + Vector3i(half, half, 0)
	low_b.z = middle - half
	var cross_low: Vector3i = Vector3i(mini(low_a.x, low_b.x), mini(low_a.y, low_b.y), middle - half)
	var cross_high: Vector3i = Vector3i(maxi(high_a.x, high_b.x), maxi(high_a.y, high_b.y), middle + half)
	var boxes: Array[Vector3i] = [low_a, high_a, cross_low, cross_high, low_b, high_b]
	boxes.append_array(MineGenerator.door_for(from))
	boxes.append_array(MineGenerator.door_for(to))
	return boxes


## Bridges the pair and checks every two added boxes that meet share the
## connector's square on both axes across their joint.
func _bridged_with_full_joints(gap_mm: int, shift: Vector3i, label: String) -> String:
	var generator: MineGenerator = _pair(gap_mm, shift)
	var before: int = generator.min_mm.size()
	if _bridges().apply(generator) != 1:
		return "%s: not bridged; the Z can be reshaped here" % label
	var boxes: Array[Vector3i] = _added(generator, before)
	if boxes.size() != 10:
		return "%s: %d boxes added, expected a Z and two doorways" % [label, boxes.size() / 2]
	for a: int in range(0, boxes.size(), 2):
		for b: int in range(a + 2, boxes.size(), 2):
			var overlap: Array[int] = []
			for axis: int in 3:
				overlap.append(mini(boxes[a + 1][axis], boxes[b + 1][axis]) - maxi(boxes[a][axis], boxes[b][axis]))
			overlap.sort()
			if overlap[0] >= 0 and overlap[1] < WIDTH_MM:
				return "%s: boxes %d and %d meet through %s mm, under the %d mm connector" \
						% [label, a / 2, b / 2, overlap, WIDTH_MM]
	return ""


func test_short_gap_of_seed_44_is_reshaped_with_full_joints() -> String:
	# #438: seed 44 at loop_bias 0.6, a 10 m gap and a 5 m offset.
	return _bridged_with_full_joints(10000, Vector3i(5000, 0, 0), "10 m gap, 5 m offset")


func test_two_axis_offset_of_seed_226_is_reshaped_with_full_joints() -> String:
	# #438: seed 226 at loop_bias 0.6, a 19 m gap and offsets of 5 m and 6 m.
	return _bridged_with_full_joints(19000, Vector3i(5000, 6000, 0), "19 m gap, 5 and 6 m offsets")


func test_the_old_long_legs_fail_the_joint_check_in_both_cases() -> String:
	var from: ModuleConnector = ModuleConnector.new(Vector3i.ZERO, "+z")
	for case: Array in [[10000, Vector3i(5000, 0, 0)], [19000, Vector3i(5000, 6000, 0)]]:
		var to: ModuleConnector = ModuleConnector.new(case[1] + Vector3i(0, 0, case[0]), "-z")
		if LoopShapes.joints_clear(_old_z(from, to), WIDTH_MM):
			return "the #411 Z with a %d mm gap and offset %s passed the joint check" % [case[0], case[1]]
	return ""


func test_joint_check_skips_apart_boxes_and_fails_slivers() -> String:
	var apart: Array[Vector3i] = [Vector3i.ZERO, Vector3i(8000, 8000, 8000),
			Vector3i(0, 0, 8001), Vector3i(1000, 1000, 9000)]
	if not LoopShapes.joints_clear(apart, WIDTH_MM):
		return "boxes 1 mm apart failed"
	var face: Array[Vector3i] = [Vector3i.ZERO, Vector3i(8000, 8000, 8000),
			Vector3i(0, 0, 8000), Vector3i(8000, 8000, 9000)]
	if not LoopShapes.joints_clear(face, WIDTH_MM):
		return "boxes meeting face to face through the whole square failed"
	var edge: Array[Vector3i] = [Vector3i.ZERO, Vector3i(8000, 8000, 8000),
			Vector3i(8000, 0, 8000), Vector3i(9000, 8000, 9000)]
	if LoopShapes.joints_clear(edge, WIDTH_MM):
		return "boxes touching along an edge passed"
	var sliver: Array[Vector3i] = [Vector3i.ZERO, Vector3i(8000, 8000, 8000),
			Vector3i(1, 0, 2000), Vector3i(8001, 8000, 20000)]
	return "" if not LoopShapes.joints_clear(sliver, WIDTH_MM) \
			else "boxes sharing 7.999 m across passed"


func test_every_gap_and_offset_keeps_full_joints() -> String:
	var bridges: LoopBridges = _bridges()
	for size_class: String in ModuleConnector.SIZE_CLASSES:
		var width: int = ModuleConnector.SIZE_CLASSES[size_class]
		var from: ModuleConnector = ModuleConnector.new(Vector3i.ZERO, "+z", size_class)
		for gap: int in range(width, bridges.max_gap_mm + 1, 500):
			for shift_x: int in range(0, 24001, 1000):
				for shift_y: int in range(0, 24001, 3000):
					if shift_x == 0 and shift_y == 0:
						continue
					var to: ModuleConnector = ModuleConnector.new(Vector3i(shift_x, shift_y, gap), "-z", size_class)
					var boxes: Array[Vector3i] = LoopShapes.z_shape(from, to)
					boxes.append_array(MineGenerator.door_for(from))
					boxes.append_array(MineGenerator.door_for(to))
					if not LoopShapes.joints_clear(boxes, width):
						return "%s: gap %d mm, offset %d, %d mm: a joint is under the connector" \
								% [size_class, gap, shift_x, shift_y]
	return ""


func test_seeds_at_bias_0_6_pass_the_validator() -> String:
	# #438 will ship 0.6; before #472, 11 of these seeds failed `passage`.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data["loop_bias"] = 0.6
	var result: Dictionary = SeedSweep.run(0, SEEDS, SeedSweep.MODULE_COUNT, SeedSweep.KEPT_FAILURES,
			{SeedSweep.GENERATOR_FILE: JSON.stringify(data)})
	var failing: int = 0
	for check: String in LevelValidator.CHECKS:
		failing += result["by_check"][check]
	if failing > 0 or result["by_check"]["level"] > 0:
		return "%d seeds failed: %s" % [result["failed"], result["failures"]]
	return "" if result["looped"] >= MIN_LOOPED_AT_0_6 \
			else "%d seeds looped at 0.6, expected at least %d" % [result["looped"], MIN_LOOPED_AT_0_6]
