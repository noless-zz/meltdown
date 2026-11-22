extends RefCounted

## The thinnest wall between tunnels (#1240, GEN-3, GEN-5): hand-built unions
## with known answers, and the sweep's summary of per-seed gaps.

const WallGapSweep := preload("res://tests/wall_gap_sweep.gd")


func _box(low: Vector3, high: Vector3) -> BoxBounds:
	return BoxBounds.new(low, high)


## Two tunnels along z, 4 m wide, side by side with 0.5 m of rock between them.
func _parallel_tunnels() -> Array[BoxBounds]:
	var list: Array[BoxBounds] = [
		_box(Vector3(-4.0, -2.0, -40.0), Vector3(0.0, 2.0, 0.0)),
		_box(Vector3(0.5, -2.0, -40.0), Vector3(4.5, 2.0, 0.0)),
	]
	return list


func test_parallel_tunnels_half_a_metre_apart_give_half_a_metre() -> String:
	var found: WallGap = WallGap.measure(_parallel_tunnels())
	if not is_equal_approx(found.gap_m, 0.5):
		return "expected a 0.5 m gap, got %s" % found.gap_m
	if found.first_box != 0 or found.second_box != 1 or found.axis != 0:
		return "expected boxes 0 and 1 apart on x, got %d, %d on %d" % [found.first_box, found.second_box, found.axis]
	if not found.has_pair():
		return "a pair was found but has_pair says no"
	return ""


func test_the_order_of_the_two_boxes_does_not_matter() -> String:
	var list: Array[BoxBounds] = _parallel_tunnels()
	list.reverse()
	var found: WallGap = WallGap.measure(list)
	if not is_equal_approx(found.gap_m, 0.5) or found.first_box != 0 or found.second_box != 1:
		return "expected 0.5 m between boxes 0 and 1, got %s between %d and %d" % [found.gap_m, found.first_box, found.second_box]
	return ""


func test_overlapping_boxes_are_an_opening_not_a_wall() -> String:
	var list: Array[BoxBounds] = [
		_box(Vector3(-5.0, -5.0, -20.0), Vector3(5.0, 5.0, 0.0)),
		_box(Vector3(-2.0, -2.0, -60.0), Vector3(2.0, 2.0, -15.0)),
	]
	var found: WallGap = WallGap.measure(list)
	if found.gap_m != INF or found.has_pair():
		return "an opening counted as a wall: %s between %d and %d" % [found.gap_m, found.first_box, found.second_box]
	return ""


## Two rooms placed face to face at z 0, as the generator places modules,
## with a doorway box across the shared face.
func _rooms_and_doorway() -> Array[BoxBounds]:
	var list: Array[BoxBounds] = [
		_box(Vector3(-5.0, -5.0, -20.0), Vector3(5.0, 5.0, 0.0)),
		_box(Vector3(-12.0, -12.0, 0.0), Vector3(12.0, 12.0, 24.0)),
		_box(Vector3(-4.0, -4.0, -3.0), Vector3(4.0, 4.0, 3.0)),
	]
	return list


func test_rooms_joined_through_a_doorway_open_into_each_other() -> String:
	var found: WallGap = WallGap.measure(_rooms_and_doorway())
	if found.has_pair():
		return "rooms joined by a doorway counted as a %s m wall" % found.gap_m
	return ""


func test_count_joined_measures_the_rim_around_a_doorway() -> String:
	var found: WallGap = WallGap.measure(_rooms_and_doorway(), true)
	if found.gap_m != 0.0 or found.first_box != 0 or found.second_box != 1 or found.axis != 2:
		return "expected 0 m between boxes 0 and 1 on z, got %s between %d and %d on %d" % [found.gap_m, found.first_box, found.second_box, found.axis]
	return ""


func test_a_box_that_reaches_only_one_side_does_not_join_the_pair() -> String:
	var list: Array[BoxBounds] = _parallel_tunnels()
	# Overlaps the first tunnel only, stopping short of the rock.
	list.append(_box(Vector3(-6.0, -1.0, -10.0), Vector3(-1.0, 1.0, -5.0)))
	var found: WallGap = WallGap.measure(list)
	if not is_equal_approx(found.gap_m, 0.5):
		return "a one-sided box hid the 0.5 m wall: %s" % found.gap_m
	return ""


func test_an_l_whose_faces_do_not_overlap_in_projection_is_not_counted() -> String:
	# One corridor ends at x 10, z 0..4; the other starts at x 12 but at z 6.
	# Facing faces on x miss each other on z, facing faces on z miss on x.
	var list: Array[BoxBounds] = [
		_box(Vector3(0.0, -2.0, 0.0), Vector3(10.0, 2.0, 4.0)),
		_box(Vector3(12.0, -2.0, 6.0), Vector3(16.0, 2.0, 30.0)),
	]
	var found: WallGap = WallGap.measure(list)
	if found.gap_m != INF:
		return "corner-only boxes counted: %s" % found.gap_m
	return ""


func test_faces_that_only_share_an_edge_are_not_counted() -> String:
	var list: Array[BoxBounds] = [
		_box(Vector3(0.0, 0.0, 0.0), Vector3(4.0, 4.0, 4.0)),
		_box(Vector3(5.0, 4.0, 0.0), Vector3(9.0, 8.0, 4.0)),
	]
	if WallGap.measure(list).gap_m != INF:
		return "boxes meeting along an edge in projection counted as a wall"
	return ""


func test_touching_boxes_are_a_wall_of_no_thickness() -> String:
	var list: Array[BoxBounds] = [
		_box(Vector3(0.0, 0.0, 0.0), Vector3(4.0, 4.0, 4.0)),
		_box(Vector3(0.0, 4.0, 1.0), Vector3(4.0, 8.0, 3.0)),
	]
	var found: WallGap = WallGap.measure(list)
	if found.gap_m != 0.0 or found.axis != 1:
		return "expected a 0 m wall on y, got %s on %d" % [found.gap_m, found.axis]
	return ""


func test_the_thinnest_of_several_walls_wins_and_ties_keep_the_first_pair() -> String:
	var list: Array[BoxBounds] = [
		_box(Vector3(0.0, 0.0, 0.0), Vector3(4.0, 4.0, 40.0)),
		_box(Vector3(7.0, 0.0, 0.0), Vector3(11.0, 4.0, 40.0)),
		_box(Vector3(0.0, 5.0, 0.0), Vector3(4.0, 9.0, 40.0)),
		_box(Vector3(0.0, -5.0, 0.0), Vector3(4.0, -1.0, 40.0)),
	]
	var found: WallGap = WallGap.measure(list)
	if not is_equal_approx(found.gap_m, 1.0) or found.first_box != 0 or found.second_box != 2:
		return "expected 1 m between boxes 0 and 2, got %s between %d and %d" % [found.gap_m, found.first_box, found.second_box]
	return ""


func test_the_same_union_always_gives_the_same_answer() -> String:
	var list: Array[BoxBounds] = _parallel_tunnels()
	list.append(_box(Vector3(-4.0, 3.25, -40.0), Vector3(4.5, 7.0, 0.0)))
	var first: WallGap = WallGap.of_union(BoxUnion.new(list))
	for run: int in 5:
		var again: WallGap = WallGap.of_union(BoxUnion.new(list))
		if again.gap_m != first.gap_m or again.first_box != first.first_box \
				or again.second_box != first.second_box or again.axis != first.axis:
			return "run %d differed from the first" % run
	if not is_equal_approx(first.gap_m, 0.5):
		return "expected 0.5 m, got %s" % first.gap_m
	return ""


func test_an_empty_or_single_box_union_has_no_wall_pair() -> String:
	var none: Array[BoxBounds] = []
	if WallGap.measure(none).has_pair():
		return "an empty union found a pair"
	var one: Array[BoxBounds] = [_box(Vector3.ZERO, Vector3.ONE)]
	if WallGap.measure(one).gap_m != INF:
		return "one box found a gap"
	return ""


func test_sweep_summary_takes_nearest_rank_percentiles_and_lists_thin_seeds() -> String:
	var gaps: Dictionary[int, float] = {}
	for level_seed: int in range(1, 21):
		gaps[level_seed] = float(level_seed) * 0.25
	gaps[21] = INF
	var summary: Dictionary = WallGapSweep.summarize(gaps)
	if summary["seeds"] != 21 or summary["measured"] != 20 or summary["no_pair"] != 1:
		return "counts wrong: %s" % summary
	if not is_equal_approx(summary["min_m"], 0.25) or not is_equal_approx(summary["p5_m"], 0.25) \
			or not is_equal_approx(summary["median_m"], 2.5):
		return "stats wrong: %s" % summary
	var thin: Array = summary["below_1m"]
	if str(thin) != str([1, 2, 3]):
		return "expected seeds 1, 2, 3 below 1 m, got %s" % [thin]
	return ""
