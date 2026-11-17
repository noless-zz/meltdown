extends RefCounted

## Picks and records the generated seed the m3 suite's seed step flies (#494,
## DEV-6, GEN-2, RUN-4, decision record 0005). The step moved from seed 205 to
## 40 by hand (#438); any generator, robot or debris change can move it again,
## so re-recording now finds the seed itself: the step's seed if the bot still
## escapes it with a meltdown entry down, otherwise the lowest seed in
## SEARCH_FIRST..SEARCH_LAST that does. The seed, hash and level hash are then
## written into the suite file, which is the only place they live.
##
## `pick` and `rewrite_step` are pure, so the unit test checks them on
## hand-made input without flying anything.

const SEARCH_FIRST: int = 1
const SEARCH_LAST: int = 300
## Ten minutes of flight, as `bot_escape_sweep.gd` allows.
const TICK_LIMIT: int = 36000
const BotSweep := preload("res://tests/bot_escape_sweep.gd")
## The one command that re-records the m3 suite, from the repository root.
const RECORD_COMMAND: String = AcceptanceStateChecks.RECORD_COMMAND


## How the bot flew one seed: whether it escaped and how many meltdown entries
## had fallen (or were held back by the route guard) when the run ended, which
## for an escape is before it.
class Flown extends RefCounted:
	var level_seed: int = 0
	var escaped: bool = false
	var fallen: int = 0
	var session: LocalSession = null
	var reason: String = ""

	func qualifies() -> bool:
		return escaped and fallen >= 1

	static func of(level_seed: int, escaped: bool, fallen: int) -> Flown:
		var flown: Flown = Flown.new()
		flown.level_seed = level_seed
		flown.escaped = escaped
		flown.fallen = fallen
		return flown


## The lowest seed in `results` that qualifies, as {"seed": n}, or
## {"error": ...} naming the searched range when none does.
static func pick(results: Array[Flown], first: int = SEARCH_FIRST, last: int = SEARCH_LAST) -> Dictionary:
	var best: int = -1
	for flown: Flown in results:
		if flown.qualifies() and (best < 0 or flown.level_seed < best):
			best = flown.level_seed
	if best < 0:
		return {"error": "no seed in %d..%d escapes with a meltdown entry fallen" % [first, last]}
	return {"seed": best}


## The bot's flight on `level_seed` as the step builds it (`SeedLevel`, the
## shipped data files, robots and debris), keeping the session for recording.
static func fly(level_seed: int) -> Flown:
	var flown: Flown = Flown.of(level_seed, false, 0)
	var level: LevelDef = SeedLevel.load_level(level_seed)
	if level == null:
		flown.reason = "the level was rejected"
		return flown
	var source: BotSweep.BotSource = BotSweep.BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(AcceptanceStepLevel.SHIP_FILE))
	source.bot = BotPilot.new(session.sim, 0, level)
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	var measured: Dictionary = {}
	AcceptanceStateChecks.debris_fallen(sim, measured)
	flown.escaped = sim.outcome() == ExitRule.Outcome.ESCAPED
	flown.fallen = int(measured.get("debris_fallen", 0))
	flown.session = session
	flown.reason = "outcome %s at tick %d, %d of %d entries fallen" % [
		AcceptanceStateChecks.outcome_name(sim.outcome()), sim.tick, flown.fallen, int(measured.get("debris", 0))]
	return flown


## `current` if it still qualifies, otherwise the lowest qualifying seed in the
## search range. Returns {"flown": Flown} or {"error": ...}.
static func choose(current: int) -> Dictionary:
	var kept: Flown = fly(current)
	if kept.qualifies():
		return {"flown": kept}
	print("Meltdown: seed %d no longer qualifies (%s); searching %d..%d" % [
		current, kept.reason, SEARCH_FIRST, SEARCH_LAST])
	var results: Array[Flown] = []
	for level_seed: int in range(SEARCH_FIRST, SEARCH_LAST + 1):
		var flown: Flown = kept if level_seed == current else fly(level_seed)
		results.append(flown)
		# Seeds are flown in order, so the first that qualifies is the lowest.
		if flown.qualifies():
			break
	var picked: Dictionary = pick(results)
	if picked.has("error"):
		return picked
	for flown: Flown in results:
		if flown.level_seed == picked["seed"]:
			return {"flown": flown}
	return {"error": "seed %d picked but not flown" % picked["seed"]}


## `suite_text` with the seed, expected hash and expected level hash of step
## `step_id` replaced, everything else kept as written. Returns "" when the
## step or one of the three fields is missing.
static func rewrite_step(suite_text: String, step_id: String, level_seed: int, hash: int,
		level_hash: int) -> String:
	var start: int = suite_text.find("\"id\": \"%s\"" % step_id)
	if start < 0:
		return ""
	var end: int = suite_text.find("}", start)
	if end < 0:
		return ""
	var block: String = suite_text.substr(start, end - start)
	for pair: Array in [["seed", level_seed], ["expected_hash", hash], ["expected_level_hash", level_hash]]:
		var pattern: RegEx = RegEx.create_from_string("\"%s\": -?\\d+" % pair[0])
		if pattern.search(block) == null:
			return ""
		block = pattern.sub(block, "\"%s\": %d" % pair, false)
	return suite_text.substr(0, start) + block + suite_text.substr(end)
