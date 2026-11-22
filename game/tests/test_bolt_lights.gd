extends RefCounted

## `BoltLights`, the bolt-light pool moved out of `ProjectileView` (#1160,
## LGT-1, PRF-1): with more bolts than lights the lights go to the bolts nearest
## the viewer, nearest first; ties keep the bolts' order; hidden bolts get none;
## and the pool never grows past its budget.

const RANGE_M: float = 8.0
const ENERGY: float = 1.5
const COLOR: Color = Color(0.2, 0.6, 1.0)


## Bolts on the X axis at `xs`, all shown.
static func _positions(xs: Array[int]) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for x: int in xs:
		positions.append(Vector3(x, 0.0, 0.0))
	return positions


static func _all_shown(count: int) -> Array[bool]:
	var shown: Array[bool] = []
	for index: int in count:
		shown.append(true)
	return shown


func test_more_bolts_than_lights_light_the_nearest_to_the_viewer() -> String:
	var host: Node3D = Node3D.new()
	var lamps: BoltLights = BoltLights.new(host)
	lamps.viewer = Vector3(10.0, 0.0, 0.0)
	# Index i sits at x; the viewer at x = 10 is nearest to 9, 8, 7.
	var positions: Array[Vector3] = _positions([7, 2, 9, 0, 5, 3, 8, 1, 6, 4])
	lamps.light_nearest(positions, _all_shown(positions.size()), 3, RANGE_M, ENERGY, COLOR)
	var problem: String = ""
	if lamps.lit_bolts() != ([2, 6, 0] as Array[int]):
		problem = "lit %s, wanted bolts at x 9, 8, 7 (indices 2, 6, 0)" % [lamps.lit_bolts()]
	elif lamps.count() != 3 or host.get_child_count() != 3:
		problem = "%d lights in the pool, %d nodes under the host" % [lamps.count(), host.get_child_count()]
	else:
		for slot: int in 3:
			var lamp: OmniLight3D = lamps.light(slot)
			if not lamp.visible or lamp.position != positions[lamps.lit_bolts()[slot]] \
					or lamp.shadow_enabled or lamp.light_color != COLOR \
					or not is_equal_approx(lamp.omni_range, RANGE_M) \
					or not is_equal_approx(lamp.light_energy, ENERGY):
				problem = "light %d: %s at %s" % [slot, lamp.name, lamp.position]
				break
	host.free()
	return problem


func test_equal_distances_keep_the_bolts_order_and_hidden_bolts_get_none() -> String:
	var positions: Array[Vector3] = _positions([-1, 1, 0, -1, 1])
	var shown: Array[bool] = [true, true, false, true, true]
	var chosen: Array[int] = BoltLights.nearest(Vector3.ZERO, positions, shown, 3)
	if chosen != ([0, 1, 3] as Array[int]):
		return "chose %s, wanted [0, 1, 3]" % [chosen]
	if not BoltLights.nearest(Vector3.ZERO, positions, shown, 0).is_empty():
		return "a budget of 0 still chose bolts"
	return ""


func test_fewer_bolts_hide_spare_lights_and_a_smaller_budget_frees_them() -> String:
	var host: Node3D = Node3D.new()
	var lamps: BoltLights = BoltLights.new(host)
	lamps.light_nearest(_positions([1, 2, 3, 4]), _all_shown(4), 4, RANGE_M, ENERGY, COLOR)
	lamps.light_nearest(_positions([5]), _all_shown(1), 4, RANGE_M, ENERGY, COLOR)
	var problem: String = ""
	var visible: int = 0
	for slot: int in lamps.count():
		visible += 1 if lamps.light(slot).visible else 0
	if lamps.count() != 4 or visible != 1 or lamps.lit_bolts() != ([0] as Array[int]):
		problem = "%d lights, %d visible, lit %s" % [lamps.count(), visible, lamps.lit_bolts()]
	else:
		lamps.apply_look(2, 3.0, ENERGY, COLOR)
		if lamps.count() != 2 or host.get_child_count() != 2 \
				or not is_equal_approx(lamps.light(0).omni_range, 3.0):
			problem = "after a budget of 2: %d lights, %d nodes" % [lamps.count(), host.get_child_count()]
	host.free()
	return problem
