extends RefCounted

## The bot's escape rate over generated levels (#377, DEV-6 gate G3, GEN-3,
## RUN-3, RUN-5): over 20 seeds the bot escapes at least 95% of the levels it
## cleared; the summary line has the agreed shape; the same seeds give the
## same summary and the same flights twice; a lost countdown counts as cleared
## but not escaped; and a level with no reactor is counted apart, never as
## cleared. The 1,000-seed rate is in the #377 devlog.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 20
const FIRST_SEED: int = 1
## About ten seconds on a desktop; CI machines are slower.
const TIME_LIMIT_MS: int = 60000
## Seeds flown twice for the determinism check.
const REPEATED_SEEDS: int = 3


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
	var result: Dictionary = {"seeds": 7, "cleared": 6, "escaped": 5, "rate": 5.0 / 6.0}
	var line: String = Sweep.summary(result)
	var expected: String = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"rate":0.8333}'
	if line != expected:
		return "summary \"%s\", expected \"%s\"" % [line, expected]
	var parsed: Variant = JSON.parse_string(line.trim_prefix(Sweep.SUMMARY_TAG + " "))
	if not parsed is Dictionary:
		return "the summary's JSON does not parse"
	for key: String in ["seeds", "cleared", "escaped", "rate"]:
		if not (parsed as Dictionary).has(key):
			return "the summary has no %s" % key
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
