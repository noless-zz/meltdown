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
## cleared, lost before the reactor, out of ticks or no reactor. The 1,000-seed rates are in the
## #377 and #420 devlogs.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
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
	expected = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"looped":2,"rate":0.8333,"robots_destroyed":31,"lost_before_reactor":0,"timed_out":1,"robots":true}'
	if line != expected:
		return "robot summary \"%s\", expected \"%s\"" % [line, expected]
	return _parses_with(line, ["looped", "robots_destroyed", "lost_before_reactor", "timed_out",
			"robots"])


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
