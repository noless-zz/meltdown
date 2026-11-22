extends RefCounted

## The m2 step for both primaries firing (#1261, decision record 0011, CMB-1,
## SLV-1): in a session built like the main scene's test tunnel, the bot
## destroys the first robot, flies through the part it drops, slots it into the
## empty second slot and holds the trigger. The step pins the final hash and
## checks shots of both slots are in flight.
##
## Re-recording after an intended change (from the repository root; then paste
## the printed hash into `expected_hash` of the step in `acceptance/suites/m2.json`):
##
##     MELTDOWN_RECORD_M2=both_primaries_fire godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "both_primaries_fire"
const REPLAY_PATH: String = "res://acceptance/replays/both_primaries_fire.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
const PickupStep := preload("res://tests/test_m2_pickup_step.gd")
## A minute of flight; the recording needs well under half of it.
const TICK_LIMIT: int = 3600
## Ticks the trigger is held before the recording may end. It then ends on the
## first tick both slots fire together, so both shots are in the air at the end
## however near a wall the ship points.
const MIN_FIRE_TICKS: int = 30
const Main := preload("res://main.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot taking a test tunnel robot's part, slotting it into slot 2 and firing both guns (#1261).
# Re-record from the repository root, then copy the printed hash into m2.json:
#     MELTDOWN_RECORD_M2=both_primaries_fire godot --headless --path game -s res://tests/run_tests.gd
"""


## The pickup step's flight until a part is held, then one tick pressing the
## slot control and from then on the trigger held. Set `sim` once the session
## exists.
class SlotAndFireSource extends ShipInputSource:
	var sim: Sim = null
	var seek: PickupStep.SeekSource = PickupStep.SeekSource.new()
	var slotted: bool = false

	func next_input(tick: int) -> ShipInput:
		if sim == null:
			return ShipInput.new()
		var input: ShipInput = ShipInput.new()
		if slotted:
			input.fire_primary = true
		elif not sim.ships[0].hold.is_empty():
			input.slot_held = true
			slotted = true
		else:
			input = seek.next_input(tick)
		return input


## A session like the main scene's in the test tunnel, flown by
## `SlotAndFireSource` until both slots fired on one tick after the trigger was
## held MIN_FIRE_TICKS, the ship is lost, or TICK_LIMIT.
static func record() -> LocalSession:
	var source: SlotAndFireSource = SlotAndFireSource.new()
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH),
		null, LocalSession.load_parts()).use_salvage_rules(SpawnLoader.load_salvage_rules())
	source.sim = session.sim
	source.seek.sim = session.sim
	source.seek.bot = BotPilot.new(session.sim)
	var fire_ticks: int = 0
	while session.sim.ships[0].hull > 0.0 and session.sim.tick < TICK_LIMIT:
		var tick: int = session.sim.tick
		session.advance(ShipState.TICK_DT)
		if session.sim.tick == tick or not source.slotted:
			continue
		fire_ticks += 1
		if fire_ticks >= MIN_FIRE_TICKS and _both_fired_this_tick(session.sim.ships[0]):
			break
	return session


## Whether both of `ship`'s slots fired on the last tick: a slot that fires
## restarts its interval, which counts down from the next tick on.
static func _both_fired_this_tick(ship: ShipState) -> bool:
	for slot: int in ship.primary_slots.size():
		var weapon: WeaponDef = ship.primary_slots[slot]
		if weapon == null or ship.fire_cooldowns[slot] != weapon.fire_interval_ticks:
			return false
	return true


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


func test_m2_suite_has_the_both_primaries_step() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_BOTH_PRIMARIES_FIRED, AcceptanceStep.CHECK_SHIP_ALIVE]
	if found.checks != wanted or found.replay_path != REPLAY_PATH or found.level != "":
		return "%s checks %s flying %s on level '%s'" % [STEP_ID, found.checks, found.replay_path,
			found.level]
	return ""


## Run twice from the file, the replay ends on the suite's hash with both
## slots filled and shots of each in flight.
func test_replay_replays_to_its_hash_with_both_guns_firing() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		if sim.state_hash() != found.expected_hash or sim.state_hash() != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" \
				% [attempt + 1, sim.state_hash(), found.expected_hash, replay.expected_hash]
		var measurements: Dictionary = {}
		var result: Array = AcceptanceStateChecks.both_primaries_fired(sim, measurements)
		if result[0] != AcceptanceReport.RESULT_PASS:
			return "run %d: %s" % [attempt + 1, result[1]]
	return ""


## The replay pins one flight; this checks the bot as it is now still slots a
## second gun and fires both.
func test_the_bot_still_fires_both_guns() -> String:
	var session: LocalSession = record()
	var result: Array = AcceptanceStateChecks.both_primaries_fired(session.sim, {})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "after %d ticks, hull %.1f, slots %s: %s" % [session.sim.tick,
			session.sim.ships[0].hull, session.sim.ships[0].primary_ids, result[1]]
	return ""


## The check fails one slot filled, or two filled with one silent, and passes
## shots of both in flight.
func test_both_primaries_check_reads_the_slots_and_shots() -> String:
	var sim: Sim = Sim.new(0, 1)
	sim.ships[0].primary_slots[0] = WeaponDef.new()
	var shot: Projectile = Projectile.new(Vector3.ZERO, Vector3.FORWARD, 0, 10, 1.0)
	sim.projectiles.append(shot)
	if AcceptanceStateChecks.both_primaries_fired(sim, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "one filled slot passed"
	sim.ships[0].primary_slots[1] = WeaponDef.new()
	if AcceptanceStateChecks.both_primaries_fired(sim, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "a silent second slot passed"
	var second: Projectile = Projectile.new(Vector3.ZERO, Vector3.FORWARD, 0, 10, 1.0)
	second.slot = 1
	sim.projectiles.append(second)
	var measurements: Dictionary = {}
	var result: Array = AcceptanceStateChecks.both_primaries_fired(sim, measurements)
	if result[0] != AcceptanceReport.RESULT_PASS or str(measurements["primary_shots_by_slot"]) != "[1, 1]":
		return "shots of both slots gave %s, %s" % [result, measurements]
	return ""
