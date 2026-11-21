extends RefCounted

## Picks and records the generated seed the m3 suite's seed step flies (#494,
## DEV-6, GEN-2, RUN-4, decision record 0005). The step moved from seed 205 to
## 40 by hand (#438); any generator, robot or debris change can move it again,
## so re-recording now finds the seed itself: the step's seed if the bot still
## escapes it with a meltdown entry down, otherwise the lowest seed in
## SEARCH_FIRST..SEARCH_LAST that does. The seed, hash and level hash are then
## written into the suite file, which is the only place they live.
##
## The door step (#516) is chosen the same way, except that a blast door must
## also be down when the bot gets out. The fire step (#517) needs the bot to
## escape having been burnt by fire on the way (`FireBurnCheck`).
##
## The door-marked step (#899) needs a door down whose cross the map must draw:
## before the door falls the bot has explored the boxes on both sides of at
## least one opening it closes, so `map_route` sees the mark in the running
## game (`doors_marked`).
##
## A seed another generated step already flies can be excluded (#548), so the
## suite covers two generated levels instead of one and a generator change
## does not move both steps at once.
##
## `pick` and `rewrite_step` are pure, so the unit test checks them on
## hand-made input without flying anything.

const SEARCH_FIRST: int = 1
const SEARCH_LAST: int = 300
## Ten minutes of flight, as `bot_escape_sweep.gd` allows.
const TICK_LIMIT: int = 36000
const BotSweep := preload("res://tests/bot_escape_sweep.gd")
const SUITE_PATH: String = "res://acceptance/suites/m3.json"
## What a seed step needs besides the escape: a meltdown entry down (the first
## seed step), a blast door down as well (#516), or a burn by fire (#517).
const NEED_DEBRIS: String = "debris"
const NEED_DOOR: String = "door"
const NEED_BURN: String = "burn"
const NEED_DOOR_MARKED: String = "door_marked"


## How the bot flew one seed: whether it escaped, how many meltdown entries
## had fallen (or were held back by the route guard) and how many blast doors
## were down when the run ended, which for an escape is before it, and on how
## many ticks fire burnt the ship.
class Flown extends RefCounted:
	var level_seed: int = 0
	var escaped: bool = false
	var fallen: int = 0
	var doors_fallen: int = 0
	var burnt_ticks: int = 0
	## Doors that made a mark on the map the tick they fell (#899): a blocked
	## opening or split between boxes the bot had explored by then.
	var doors_marked: int = 0
	var session: LocalSession = null
	var reason: String = ""

	## `need` is one of the NEED_ values. A burn is all the fire step asks
	## for besides the escape; the other two need a meltdown entry down.
	func qualifies(need: String = NEED_DEBRIS) -> bool:
		if not escaped:
			return false
		match need:
			NEED_BURN:
				return burnt_ticks >= 1
			NEED_DOOR:
				return fallen >= 1 and doors_fallen >= 1
			NEED_DOOR_MARKED:
				return fallen >= 1 and doors_marked >= 1
		return fallen >= 1

	static func of(level_seed: int, escaped: bool, fallen: int, doors_fallen: int = 0,
			burnt_ticks: int = 0, doors_marked: int = 0) -> Flown:
		var flown: Flown = Flown.new()
		flown.level_seed = level_seed
		flown.escaped = escaped
		flown.fallen = fallen
		flown.doors_fallen = doors_fallen
		flown.burnt_ticks = burnt_ticks
		flown.doors_marked = doors_marked
		return flown


## Counts, while the bot flies, the doors that make a mark on the held map the
## tick they fall: the boxes the ship has passed through so far, as the map's
## `ExploredBoxes` keeps them, and the door alone down, searched as
## `AcceptanceMapRouteCheck` searches it. Reads the session; writes nothing.
class DoorMarks extends RefCounted:
	var marked: int = 0
	var _session: LocalSession = null
	var _explored: ExploredBoxes = null
	var _walls: BoxUnion = null
	var _seen: Array[int] = []

	func _init(session: LocalSession) -> void:
		_session = session
		_walls = session.replay.walls()
		_explored = ExploredBoxes.new(_walls)

	func after_tick() -> void:
		var ship: ShipState = _session.current_ship()
		_explored.visit(ship.position)
		for door: int in AcceptanceMapRouteCheck._fallen_doors(_session.sim.debris):
			if _seen.has(door):
				continue
			_seen.append(door)
			var own: KnownRoute = EscapePath.known_route(_walls, _explored.explored(), ship.position,
				ReplayStartLine.position(_session.replay, 0),
				AcceptanceMapRouteCheck._only(_session.sim.debris, door), ship.radius)
			if own.blocked_openings.size() + own.blocked_splits.size() > 0:
				marked += 1


## The lowest seed in `results` that qualifies and is not in `excluded`, as
## {"seed": n}, or {"error": ...} naming the searched range when none does.
static func pick(results: Array[Flown], first: int = SEARCH_FIRST, last: int = SEARCH_LAST,
		need: String = NEED_DEBRIS, excluded: Array[int] = []) -> Dictionary:
	var best: int = -1
	for flown: Flown in results:
		if flown.level_seed in excluded:
			continue
		if flown.qualifies(need) and (best < 0 or flown.level_seed < best):
			best = flown.level_seed
	if best < 0:
		var wanted: String = {NEED_DOOR: "with a blast door fallen", NEED_BURN: "having been burnt by fire",
				NEED_DOOR_MARKED: "with a door fallen across explored boxes"} \
			.get(need, "with a meltdown entry fallen")
		return {"error": "no seed in %d..%d escapes %s" % [first, last, wanted]}
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
	var marks: DoorMarks = DoorMarks.new(session)
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 and sim.tick < TICK_LIMIT:
		var shield: float = sim.ships[0].shield
		var hull: float = sim.ships[0].hull
		session.advance(ShipState.TICK_DT)
		if FireBurnCheck.burnt_this_tick(sim, shield, hull):
			flown.burnt_ticks += 1
		marks.after_tick()
	flown.doors_marked = marks.marked
	var measured: Dictionary = {}
	AcceptanceStateChecks.debris_fallen(sim, measured)
	AcceptanceStateChecks.door_fallen("", sim, measured)
	flown.escaped = sim.outcome() == ExitRule.Outcome.ESCAPED
	flown.fallen = int(measured.get("debris_fallen", 0))
	flown.doors_fallen = int(measured.get("doors_fallen", 0))
	flown.session = session
	flown.reason = "outcome %s at tick %d, %d of %d entries and %d of %d doors fallen (%d marked), burnt on %d ticks" % [
		AcceptanceStateChecks.outcome_name(sim.outcome()), sim.tick, flown.fallen,
		int(measured.get("debris", 0)), flown.doors_fallen, int(measured.get("doors", 0)),
		flown.doors_marked, flown.burnt_ticks]
	return flown


## `current` if it still qualifies and is not excluded, otherwise the lowest
## qualifying seed in the search range that is not in `excluded`. Returns
## {"flown": Flown} or {"error": ...}.
static func choose(current: int, need: String = NEED_DEBRIS, excluded: Array[int] = []) -> Dictionary:
	var kept: Flown = null
	if not current in excluded:
		kept = fly(current)
		if kept.qualifies(need):
			return {"flown": kept}
		print("Meltdown: seed %d no longer qualifies (%s); searching %d..%d" % [
			current, kept.reason, SEARCH_FIRST, SEARCH_LAST])
	else:
		print("Meltdown: seed %d is flown by another step; searching %d..%d without %s" % [
			current, SEARCH_FIRST, SEARCH_LAST, excluded])
	var results: Array[Flown] = []
	for level_seed: int in range(SEARCH_FIRST, SEARCH_LAST + 1):
		if level_seed in excluded:
			continue
		var flown: Flown = kept if kept != null and level_seed == current else fly(level_seed)
		results.append(flown)
		# Seeds are flown in order, so the first that qualifies is the lowest.
		if flown.qualifies(need):
			break
	var picked: Dictionary = pick(results, SEARCH_FIRST, SEARCH_LAST, need, excluded)
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


## The command that re-records only step `step_id`, from the repository root;
## the same one a level-hash failure of that step names.
static func record_command(step_id: String) -> String:
	return AcceptanceStateChecks.record_command(step_id)


## The m3 step `step_id`, or null.
static func find_step(step_id: String) -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for found: AcceptanceStep in suite.steps:
		if found.id == step_id:
			return found
	return null


## The seeds the m3 steps in `step_ids` fly; steps that are missing or fly a
## hand-made level are left out.
static func seeds_of(step_ids: Array[String]) -> Array[int]:
	var seeds: Array[int] = []
	for step_id: String in step_ids:
		var found: AcceptanceStep = find_step(step_id)
		if found != null and found.level_seed != AcceptanceStep.NO_SEED:
			seeds.append(found.level_seed)
	return seeds


## Re-records seed step `step_id`: keeps or picks its seed (`choose`, never one
## in `excluded`), writes the inputs to `replay_path` under `header` and the
## seed and both hashes into the suite. Returns "" or what went wrong; nothing
## is written on failure.
static func record(step_id: String, replay_path: String, header: String, need: String,
		excluded: Array[int] = []) -> String:
	var found: AcceptanceStep = find_step(step_id)
	if found == null:
		return "%s has no step %s; nothing recorded" % [SUITE_PATH, step_id]
	var chosen: Dictionary = choose(found.level_seed, need, excluded)
	if chosen.has("error"):
		return "%s: %s; nothing recorded" % [step_id, chosen["error"]]
	var flown: Flown = chosen["flown"]
	var session: LocalSession = flown.session
	# Inputs only: the level is the seed's, not the replay's.
	var inputs: Replay = Replay.new(session.replay.run_seed, 1)
	inputs.frames = session.replay.frames
	inputs.expected_hash = session.sim.state_hash()
	var level_hash: int = AcceptanceStepLevel.level_hash(session.replay)
	var rewritten: String = rewrite_step(SeedLevel.read_text(SUITE_PATH), step_id, flown.level_seed,
		inputs.expected_hash, level_hash)
	if rewritten == "":
		return "%s has no step %s with seed and both hashes; nothing recorded" % [SUITE_PATH, step_id]
	for written: Array in [[replay_path, header + inputs.to_text()], [SUITE_PATH, rewritten]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s: %s" % [written[0], error_string(FileAccess.get_open_error())]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: seed %d (was %d), %s, hash %d, level hash %d; written to %s" % [
		replay_path, flown.level_seed, found.level_seed, flown.reason, inputs.expected_hash, level_hash,
		SUITE_PATH])
	return ""
