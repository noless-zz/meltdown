extends RefCounted

## The seed sweep's reactor distance report (#924, GEN-3, RUN-3, RUN-5): the
## summary line's format is pinned, the numbers are the core's escape path and
## countdown, and no level of seeds 0..999 has its reactor in or next to the
## start's module.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const ReactorDistance := preload("res://tests/sweep_reactor_distance.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const SEEDS: int = 1000
## A seed whose level is checked by hand below; any generated level would do.
const SEED: int = 31


func test_summary_part_is_pinned() -> String:
	var stats: Dictionary = ReactorDistance.empty()
	stats[ReactorDistance.PATHS].append_array([61200, 80400, 120000, 300500, 99000])
	stats[ReactorDistance.COUNTDOWNS].append_array([4236, 6000, 600, 1200])
	var expected: String = ", escape_m_min 61.2, escape_m_p10 61.2, escape_m_median 99.0, escape_m_max 300.5" \
			+ ", countdown_s_min 10.0, countdown_s_p10 10.0, countdown_s_median 20.0, countdown_s_max 100.0" \
			+ ", reactor_near_start 0"
	var part: String = ReactorDistance.summary_part(stats)
	return "" if part == expected else "got \"%s\"" % part


func test_summary_line_puts_distance_before_the_checks() -> String:
	var stats: Dictionary = ReactorDistance.empty()
	stats[ReactorDistance.NEAR] = 2
	var line: String = SeedSweep.summary({"seeds": 3, "passed": 2, "failed": 1, "short": 0, "ms": 12,
			"reactor_distance": stats, "by_check": {"reactor_far": 1}})
	var expected: String = "level validator: 3 seeds, 2 passed, 1 failed, 0 stopped short, 12 ms" \
			+ ", escape_m_min 0.0, escape_m_p10 0.0, escape_m_median 0.0, escape_m_max 0.0" \
			+ ", countdown_s_min 0.0, countdown_s_p10 0.0, countdown_s_median 0.0, countdown_s_max 0.0" \
			+ ", reactor_near_start 2; failing seeds by check: reactor_far 1"
	return "" if line == expected else "got \"%s\"" % line


func test_rank_is_nearest_rank() -> String:
	var values: Array[int] = []
	for value: int in range(20, 0, -1):
		values.append(value)
	var got: Array[int] = [ReactorDistance.rank(values, 0.0), ReactorDistance.rank(values, 0.1),
			ReactorDistance.rank(values, 0.5), ReactorDistance.rank(values, 1.0),
			ReactorDistance.rank([] as Array[int], 0.5), ReactorDistance.rank([7] as Array[int], 0.1)]
	var expected: Array[int] = [1, 2, 10, 20, 0, 7]
	if got != expected:
		return "min, p10, median, max, empty, single: got %s, want %s" % [got, expected]
	return "" if values[0] == 20 else "rank sorted the caller's values"


func test_add_records_the_cores_path_and_countdown() -> String:
	var level: LevelDef = _level(SEED)
	if level.reactor == null:
		return "seed %d has no reactor" % SEED
	var stats: Dictionary = ReactorDistance.empty()
	ReactorDistance.add(stats, level)
	var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(), level.start_position())
	var ticks: int = level.reactor.meltdown_ticks_for_path(path_mm)
	if stats[ReactorDistance.PATHS] != [path_mm] or stats[ReactorDistance.COUNTDOWNS] != [ticks]:
		return "got paths %s and countdowns %s, want [%d] and [%d]" % [
				stats[ReactorDistance.PATHS], stats[ReactorDistance.COUNTDOWNS], path_mm, ticks]
	var without: LevelDef = _level(SEED)
	without.reactor = null
	ReactorDistance.add(stats, without)
	return "" if stats[ReactorDistance.PATHS].size() == 1 else "a level without a reactor was counted"


## The count is not 0 because it cannot be: a reactor moved into the start's
## module, or into a module joined to it, is counted.
func test_a_reactor_in_or_next_to_the_start_module_is_counted() -> String:
	var level: LevelDef = _level(SEED)
	if ReactorDistance.is_near_start(level):
		return "seed %d's generated reactor counted as near the start" % SEED
	var start: int = ReactorFar.module_at(level, level.start_position_mm)
	var hops: Array[int] = ReactorFar.hops_from(level, start)
	for module: int in [start, hops.find(1)]:
		if module < 0:
			return "seed %d has no module joined to the start's" % SEED
		var box: BoxBounds = level.union.boxes[ReactorFar.largest_box(level, module)]
		level.reactor.position_mm = EscapePath.to_mm((box.min_corner + box.max_corner) / 2.0)
		if not ReactorDistance.is_near_start(level):
			return "a reactor in module %d (%d joins from the start's) was not counted" % [module, hops[module]]
	var stats: Dictionary = ReactorDistance.empty()
	ReactorDistance.add(stats, level)
	return "" if stats[ReactorDistance.NEAR] == 1 else "add counted %d" % stats[ReactorDistance.NEAR]


## Reads the shipped levels the sweeps share (#903, #1139), so only the
## measuring is this test's own time.
func test_seeds_0_to_999_have_no_reactor_near_the_start() -> String:
	var started: int = Time.get_ticks_msec()
	var stats: Dictionary = ReactorDistance.empty()
	for level_seed: int in SEEDS:
		ReactorDistance.add(stats, SeedLevelCache.level(level_seed))
	print("  reactor distance over seeds 0..%d in %d ms%s" % [SEEDS - 1, Time.get_ticks_msec() - started,
			ReactorDistance.summary_part(stats)])
	if stats[ReactorDistance.PATHS].size() != SEEDS:
		return "%d of %d levels have a reactor with a way out" % [stats[ReactorDistance.PATHS].size(), SEEDS]
	if stats[ReactorDistance.NEAR] != 0:
		return "%d levels have their reactor in or next to the start's module" % stats[ReactorDistance.NEAR]
	return ""


func _level(level_seed: int) -> LevelDef:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	return inputs.level_of(inputs.generate(level_seed))
