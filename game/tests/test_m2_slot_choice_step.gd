extends RefCounted

## The m2 step for the slot popup's choice as recorded input (#1262, decision
## record 0011, SLV-1, ARC-2): in a session built like the main scene's test
## tunnel, the bot takes a robot's part and clicks it into the empty second
## slot, takes the next part and chooses slot 2 for it (the old gun drops
## behind the ship), then takes the next and dumps it. The step pins the final
## hash and re-flies the replay to check every choice acted.
##
## Re-recording after an intended change (from the repository root; then paste
## the printed hash into `expected_hash` of the step in `acceptance/suites/m2.json`):
##
##     MELTDOWN_RECORD_M2=slot_choice_replace godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "slot_choice_replace"
const REPLAY_PATH: String = "res://acceptance/replays/slot_choice_replace.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
## Two minutes of flight.
const TICK_LIMIT: int = 7200
## Ticks flown on, idle, after the dump, so the step ends settled.
const SETTLE_TICKS: int = 30
const Main := preload("res://main.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot filling both slots, replacing slot 2 and dumping the next part (#1262).
# Re-record from the repository root, then copy the printed hash into m2.json:
#     MELTDOWN_RECORD_M2=slot_choice_replace godot --headless --path game -s res://tests/run_tests.gd
"""


## The bot until a part floats that the ship did not drop itself, then
## straight for it until the hold has it. The first part is clicked into the
## empty slot, the second replaces slot 2, the third is dumped. Set `sim` and
## `bot` once the session exists.
class ChoiceSource extends ShipInputSource:
	var sim: Sim = null
	var bot: BotPilot = null
	## Parts taken so far, and so which action the next one gets.
	var taken: int = 0
	## Items the ship dropped itself, never sought again.
	var skipped: Array[SalvageItem] = []
	var acted_last_tick: bool = false

	func done() -> bool:
		return taken >= 3

	func next_input(tick: int) -> ShipInput:
		if sim == null:
			return ShipInput.new()
		var ship: ShipState = sim.ships[0]
		if acted_last_tick:
			# The drop joined the salvage on the tick that acted.
			for item: SalvageItem in sim.salvage:
				if item.ignored_ship == 0 and not skipped.has(item):
					skipped.append(item)
			acted_last_tick = false
		if done():
			return ShipInput.new()
		if not ship.hold.is_empty():
			var input: ShipInput = ShipInput.new()
			match taken:
				0:
					input.slot_held = true
				1:
					input.slot_choice = ShipInput.SLOT_CHOICE_SLOT_2
				_:
					input.slot_choice = ShipInput.SLOT_CHOICE_DUMP
			taken += 1
			acted_last_tick = true
			return input
		var target: SalvageItem = null
		for item: SalvageItem in sim.salvage:
			if not skipped.has(item):
				target = item
				break
		if target == null:
			return bot.next_input(tick)
		var local: Vector3 = ship.orientation.inverse() * (target.position - ship.position)
		var thrust: float = 0.6 if local.normalized().z < -0.8 else 0.0
		return ShipInput.from_floats(Vector3(0.0, 0.0, -thrust), BotPilot.turn_towards(local), false)


## A session like the main scene's in the test tunnel, flown by `ChoiceSource`
## until SETTLE_TICKS after the dump, the ship is lost, or TICK_LIMIT.
static func record() -> LocalSession:
	var source: ChoiceSource = ChoiceSource.new()
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH),
		null, LocalSession.load_parts()).use_salvage_rules(SpawnLoader.load_salvage_rules())
	source.sim = session.sim
	source.bot = BotPilot.new(session.sim)
	var settled: int = 0
	while settled < SETTLE_TICKS and session.sim.ships[0].hull > 0.0 and session.sim.tick < TICK_LIMIT:
		var tick: int = session.sim.tick
		session.advance(ShipState.TICK_DT)
		if session.sim.tick != tick and source.done():
			settled += 1
	return session


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(REPLAY_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(REPLAY_HEADER + session.replay.to_text())
	file.close()
	print("Meltdown: recorded %s: %d ticks, slots %s, hash %d; put the hash in %s" % [REPLAY_PATH,
		session.sim.tick, session.sim.ships[0].primary_ids, session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m2_suite_has_the_slot_choice_step() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_SLOT_CHOICE_APPLIED, AcceptanceStep.CHECK_SHIP_ALIVE]
	if found.checks != wanted or found.replay_path != REPLAY_PATH or found.level != "":
		return "%s checks %s flying %s on level '%s'" % [STEP_ID, found.checks, found.replay_path,
			found.level]
	return ""


## Run twice from the file, the replay ends on the suite's hash, and every
## choice in it acted: one replace and one dump at least.
func test_replay_replays_to_its_hash_with_a_replace_and_a_dump() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		if replay.parse_version != ReplayLines.CHOICE_VERSION:
			return "the replay is format version %d, not %d" % [replay.parse_version, ReplayLines.CHOICE_VERSION]
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		if sim.state_hash() != found.expected_hash or sim.state_hash() != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" \
				% [attempt + 1, sim.state_hash(), found.expected_hash, replay.expected_hash]
		var measurements: Dictionary = {}
		var result: Array = AcceptanceSlotChoiceCheck.run(replay, measurements)
		if result[0] != AcceptanceReport.RESULT_PASS:
			return "run %d: %s" % [attempt + 1, result[1]]
		if measurements["slot_replaces"] != 1 or measurements["slot_dumps"] != 1:
			return "run %d: %s" % [attempt + 1, measurements]
	return ""


## The replay pins one flight; this checks the bot as it is now still fills
## both slots, replaces slot 2 and dumps.
func test_the_bot_still_replaces_and_dumps() -> String:
	var session: LocalSession = record()
	var result: Array = AcceptanceSlotChoiceCheck.run(session.replay, {})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "after %d ticks, hull %.1f, slots %s: %s" % [session.sim.tick,
			session.sim.ships[0].hull, session.sim.ships[0].primary_ids, result[1]]
	return ""


## Without the slot choices the replay flies differently and the check fails,
## so the step proves the choice travels in the replay.
func test_the_check_fails_without_the_choices() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	for frame: Array in replay.frames:
		(frame[0] as ShipInput).slot_choice = ShipInput.SLOT_CHOICE_NONE
	if AcceptanceSlotChoiceCheck.run(replay, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "the check passed a replay with no choices"
	var sim: Sim = replay.run()
	if sim != null and sim.state_hash() == replay.expected_hash:
		return "dropping the choices left the hash unchanged"
	return ""


## The check fails a replace that did not happen: a choice in a run whose
## slots are not both full is not judged, so a replay with only that fails.
func test_the_check_needs_a_replace_and_a_dump() -> String:
	var replay: Replay = Replay.new(1, 1)
	var input: ShipInput = ShipInput.new()
	input.slot_choice = ShipInput.SLOT_CHOICE_DUMP
	var inputs: Array[ShipInput] = [input]
	replay.add_tick(inputs)
	var measurements: Dictionary = {}
	var result: Array = AcceptanceSlotChoiceCheck.run(replay, measurements)
	if result[0] != AcceptanceReport.RESULT_FAIL or measurements["slot_dumps"] != 0:
		return "an empty-hold dump gave %s, %s" % [result, measurements]
	return ""
