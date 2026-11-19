extends RefCounted

## The bot's escape rate over generated levels (#377, DEV-6 gate G3, GEN-3,
## RUN-3, RUN-5): over 20 seeds the bot escapes at least 95% of the levels it
## cleared; the summary line has the agreed shape; the same seeds give the
## same summary and the same flights twice; a lost countdown counts as cleared
## but not escaped; and a level with no reactor is counted apart, never as
## cleared. Since #420 the levels carry the shipped loop bridges, a looped
## seed flies to its exit, and `--robots` places robots as well, with a summary
## that says so and stays the same run to run. Since #495 a robot summary also
## says how the uncleared seeds ended, and every seed lands in exactly one of
## cleared, lost before the reactor, out of ticks or no reactor. Since #534 it
## also says when the lost flights died and how many robots were awake then.
## The 1,000-seed rates are in the
## #377 and #420 devlogs.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
const Losses := preload("res://tests/bot_sweep_losses.gd")
const SEEDS: int = 20
const FIRST_SEED: int = 1
## About ten seconds on a desktop; CI machines are slower.
const TIME_LIMIT_MS: int = 60000
## Seeds flown twice for the determinism check.
const REPEATED_SEEDS: int = 3
## A seed from 0..999 whose level the shipped bridges loop (one of 185, 379, 976
## at the time of #420).
const LOOPED_SEED: int = 185


static func _build(level_seed: int, plan: ReactorPlan) -> LevelDef:
	return Sweep.build_level(level_seed, SeedSweepRef.load_modules(), plan, SeedSweepRef.ship_radius())


static func _tuning() -> ShipTuning:
	return LocalSession.load_tuning(Sweep.SHIP_TUNING_PATH)


func test_twenty_seeds_escape_at_the_g3_rate() -> String:
	var result: Dictionary = Sweep.run(FIRST_SEED, SEEDS)
	print("  %s" % Sweep.summary(result))
	print("  %s" % Sweep.details(result))
	if result["ms"] > TIME_LIMIT_MS:
		return "took %d ms, over %d" % [result["ms"], TIME_LIMIT_MS]
	if result["no_reactor"] != 0:
		return "%d seeds without a reactor" % result["no_reactor"]
	if result["cleared"] < 1:
		return "no level cleared: %s" % ", ".join(result["failures"])
	if result["rate"] < Sweep.REQUIRED_RATE:
		return "rate %.4f under %.2f: %s" % [result["rate"], Sweep.REQUIRED_RATE,
				", ".join(result["failures"])]
	return ""


func test_the_summary_line_has_the_agreed_shape() -> String:
	var result: Dictionary = {"seeds": 7, "cleared": 6, "escaped": 5, "looped": 2,
			"robots": false, "robots_destroyed": 0, "rate": 5.0 / 6.0}
	var line: String = Sweep.summary(result)
	var expected: String = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"looped":2,"rate":0.8333}'
	if line != expected:
		return "summary \"%s\", expected \"%s\"" % [line, expected]
	var problem: String = _parses_with(line, ["seeds", "cleared", "escaped", "looped", "rate"])
	if problem != "":
		return problem
	if line.contains("robots"):
		return "a run without robots names robots: %s" % line
	var line_without_robots: String = line
	# The counts of uncleared seeds stay off a line without robots (#495).
	result["lost_before_reactor"] = 0
	result["timed_out"] = 1
	if Sweep.summary(result) != line_without_robots:
		return "the uncleared counts changed a line without robots: %s" % Sweep.summary(result)
	result["robots"] = true
	result["robots_destroyed"] = 31
	line = Sweep.summary(result)
	expected = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"looped":2,"rate":0.8333,"robots_destroyed":31,"lost_before_reactor":0,"timed_out":1,"robots":true,"lost_under_10_s":0,"lost_10_to_60_s":0,"lost_over_60_s":0,"lost_awake_median":null}'
	if line != expected:
		return "robot summary \"%s\", expected \"%s\"" % [line, expected]
	return _parses_with(line, ["looped", "robots_destroyed", "lost_before_reactor", "timed_out",
			"robots", "lost_under_10_s", "lost_10_to_60_s", "lost_over_60_s",
			"lost_awake_median"])


## Hand-built lost seeds: `[seed, tick, awake]` each.
static func _lost(entries: Array) -> Array[Dictionary]:
	var lost: Array[Dictionary] = []
	for entry: Array in entries:
		lost.append({"seed": entry[0], "tick": entry[1], "awake": entry[2]})
	return lost


func test_losses_fall_into_three_time_buckets() -> String:
	# 10 s is 600 ticks and 60 s is 3600: the edges belong to the middle bucket.
	var cases: Dictionary[int, String] = {0: "lost_under_10_s", 599: "lost_under_10_s",
			600: "lost_10_to_60_s", 3600: "lost_10_to_60_s", 3601: "lost_over_60_s",
			36000: "lost_over_60_s"}
	for tick: int in cases:
		if Losses.bucket(tick) != cases[tick]:
			return "tick %d in %s, expected %s" % [tick, Losses.bucket(tick), cases[tick]]
	var counts: Dictionary[String, int] = Losses.buckets(_lost([[1, 30, 0], [2, 599, 0],
			[3, 1200, 0], [4, 4000, 0], [5, 9000, 0], [6, 20000, 0]]))
	var expected: Dictionary[String, int] = {"lost_under_10_s": 2, "lost_10_to_60_s": 1,
			"lost_over_60_s": 3}
	if counts != expected:
		return "buckets %s, expected %s" % [counts, expected]
	return ""


func test_the_awake_median_is_the_middle_value() -> String:
	if Losses.awake_median(_lost([[1, 10, 7], [2, 10, 0], [3, 10, 3]])) != 3.0:
		return "odd count: %.1f, expected 3.0" % Losses.awake_median(
				_lost([[1, 10, 7], [2, 10, 0], [3, 10, 3]]))
	var even: float = Losses.awake_median(_lost([[1, 10, 5], [2, 10, 1], [3, 10, 2], [4, 10, 3]]))
	if even != 2.5:
		return "even count: %.1f, expected 2.5" % even
	if Losses.awake_median(_lost([])) >= 0.0:
		return "nothing lost gave a median"
	return ""


func test_a_robot_summary_carries_the_losses_and_lost_lines() -> String:
	var result: Dictionary = {"seeds": 10, "cleared": 5, "escaped": 5, "looped": 0,
			"robots": true, "robots_destroyed": 12, "lost_before_reactor": 3, "timed_out": 0,
			"rate": 1.0, "debris": true,
			"lost": _lost([[2, 300, 4], [5, 1500, 1], [9, 5000, 2]])}
	var line: String = Sweep.summary(result)
	var expected: String = 'MELTDOWN_BOT_ESCAPE {"seeds":10,"cleared":5,"escaped":5,"looped":0,"rate":1.0000,"robots_destroyed":12,"lost_before_reactor":3,"timed_out":0,"robots":true,"lost_under_10_s":1,"lost_10_to_60_s":1,"lost_over_60_s":1,"lost_awake_median":2.0,"debris":true}'
	if line != expected:
		return "summary \"%s\", expected \"%s\"" % [line, expected]
	var lines: Array[String] = Losses.lines(result["lost"])
	var expected_lines: Array[String] = [
			'MELTDOWN_BOT_LOST {"seed":2,"seconds":5.00,"awake":4}',
			'MELTDOWN_BOT_LOST {"seed":5,"seconds":25.00,"awake":1}',
			'MELTDOWN_BOT_LOST {"seed":9,"seconds":83.33,"awake":2}']
	if lines != expected_lines:
		return "lost lines %s, expected %s" % [lines, expected_lines]
	# A run without robots keeps its line exactly as before (#534).
	result["robots"] = false
	result["debris"] = false
	if Sweep.summary(result).contains("lost"):
		return "a line without robots names losses: %s" % Sweep.summary(result)
	return ""


## "" when `line` is the tag and a JSON object holding every key in `keys`.
static func _parses_with(line: String, keys: Array[String]) -> String:
	if not line.begins_with(Sweep.SUMMARY_TAG + " "):
		return "\"%s\" does not start with the tag" % line
	var parsed: Variant = JSON.parse_string(line.trim_prefix(Sweep.SUMMARY_TAG + " "))
	if not parsed is Dictionary:
		return "the summary's JSON does not parse: %s" % line
	for key: String in keys:
		if not (parsed as Dictionary).has(key):
			return "the summary has no %s: %s" % [key, line]
	return ""


func test_the_same_seeds_give_the_same_summary_and_flights() -> String:
	var first: Dictionary = Sweep.run(FIRST_SEED, REPEATED_SEEDS)
	var second: Dictionary = Sweep.run(FIRST_SEED, REPEATED_SEEDS)
	if Sweep.summary(first) != Sweep.summary(second):
		return "\"%s\" then \"%s\"" % [Sweep.summary(first), Sweep.summary(second)]
	if first["failures"] != second["failures"]:
		return "failures differ: %s then %s" % [first["failures"], second["failures"]]
	# The summary could match by luck; each flight must end on the same state.
	var plan: ReactorPlan = SeedSweepRef.load_reactor_plan()
	for level_seed: int in range(FIRST_SEED, FIRST_SEED + REPEATED_SEEDS):
		var a: Sweep.SeedResult = Sweep.fly(level_seed, _build(level_seed, plan), _tuning())
		var b: Sweep.SeedResult = Sweep.fly(level_seed, _build(level_seed, plan), _tuning())
		if a.tick != b.tick or a.state_hash != b.state_hash or a.outcome != b.outcome:
			return "seed %d: %s tick %d hash %d, then %s tick %d hash %d" % [level_seed,
					a.outcome, a.tick, a.state_hash, b.outcome, b.tick, b.state_hash]
	return ""


func test_a_countdown_too_short_counts_as_cleared_not_escaped() -> String:
	var level: LevelDef = _build(FIRST_SEED, SeedSweepRef.load_reactor_plan())
	if level.reactor == null:
		return "seed %d has no reactor" % FIRST_SEED
	level.reactor.scales_with_path = false
	level.reactor.meltdown_seconds = 1.0
	var flown: Sweep.SeedResult = Sweep.fly(FIRST_SEED, level, _tuning())
	if not flown.cleared:
		return "the reactor was not destroyed: %s" % flown.line()
	if flown.escaped or flown.outcome != "LOST":
		return "expected LOST, got %s" % flown.line()
	if not flown.line().begins_with("seed %d: LOST at tick " % FIRST_SEED):
		return "failing line \"%s\" does not name the seed, outcome and tick" % flown.line()
	if flown.reason == "":
		return "no reason given"
	return ""


func test_a_level_without_a_reactor_is_counted_apart() -> String:
	# Without a reactor plan the generator places no reactor.
	var level: LevelDef = _build(FIRST_SEED, null)
	if level.reactor != null:
		return "a level built without a plan has a reactor"
	var flown: Sweep.SeedResult = Sweep.fly(FIRST_SEED, level, _tuning())
	if flown.outcome != "NO_REACTOR" or flown.cleared or flown.escaped:
		return "expected NO_REACTOR, neither cleared nor escaped: %s" % flown.line()
	return ""


func test_the_sweep_builds_levels_with_the_shipped_loop_bridges() -> String:
	var bridges: LoopBridges = SeedSweepRef.load_loop_bridges()
	if bridges.error != "":
		return "generator.json: %s" % bridges.error
	var modules: Array[ModuleDef] = SeedSweepRef.load_modules()
	var looped: MineGenerator = Sweep.generate(LOOPED_SEED, modules, bridges)
	if looped.loops < 1:
		return "seed %d no longer loops; pick another looped seed from 0..999" % LOOPED_SEED
	# The sweep must count it: one seed run on its own reports one looped level.
	var result: Dictionary = Sweep.run(LOOPED_SEED, 1)
	if result["looped"] != 1:
		return "a run of seed %d counted %d looped levels" % [LOOPED_SEED, result["looped"]]
	if not Sweep.summary(result).contains('"looped":1'):
		return "the summary does not show the loop: %s" % Sweep.summary(result)
	return ""


func test_a_looped_seed_flies_to_its_exit() -> String:
	var plan: ReactorPlan = SeedSweepRef.load_reactor_plan()
	var level: LevelDef = Sweep.build_level(LOOPED_SEED, SeedSweepRef.load_modules(), plan,
			SeedSweepRef.ship_radius(), SeedSweepRef.load_loop_bridges())
	var flown: Sweep.SeedResult = Sweep.fly(LOOPED_SEED, level, _tuning())
	if flown.outcome != "ESCAPED" or not flown.cleared:
		return "expected ESCAPED: %s" % flown.line()
	return ""


func test_robots_on_request_give_a_deterministic_summary() -> String:
	var first: Dictionary = Sweep.run(FIRST_SEED, REPEATED_SEEDS, true)
	var line: String = Sweep.summary(first)
	print("  %s" % line)
	var problem: String = _parses_with(line, ["seeds", "cleared", "escaped", "looped", "rate",
			"robots_destroyed", "lost_before_reactor", "timed_out", "robots"])
	if problem != "":
		return problem
	# combine works out "without a reactor" as what is left, so the counts must
	# not overlap or miss a seed.
	if first["lost"].size() != first["lost_before_reactor"]:
		return "%d lost entries for %d lost seeds" % [first["lost"].size(),
				first["lost_before_reactor"]]
	var ended: int = first["cleared"] + first["lost_before_reactor"] + first["timed_out"] \
			+ first["no_reactor"]
	if ended != first["seeds"]:
		return "%d cleared, %d lost, %d timed out and %d without a reactor of %d seeds" % [
				first["cleared"], first["lost_before_reactor"], first["timed_out"],
				first["no_reactor"], first["seeds"]]
	if JSON.parse_string(line.trim_prefix(Sweep.SUMMARY_TAG + " "))["robots"] != true:
		return "\"robots\" is not true: %s" % line
	var second: Dictionary = Sweep.run(FIRST_SEED, REPEATED_SEEDS, true)
	if Sweep.summary(second) != line:
		return "\"%s\" then \"%s\"" % [line, Sweep.summary(second)]
	if first["failures"] != second["failures"]:
		return "failures differ: %s then %s" % [first["failures"], second["failures"]]
	return ""
