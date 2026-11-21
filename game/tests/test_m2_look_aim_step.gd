extends RefCounted

## The m2 step for look-aim in the simulation (#922, CMB-6, decision record
## 0010): in the test tunnel with the shipped ship and look-aim values, the
## ship hovers, aims ten degrees right of its nose and fires. The step pins the
## final hash, so a change to how the guns turn or where shots leave shows up.
##
## Re-recording after an intended change (from the repository root; then paste
## the printed hash into `expected_hash` of the step in `acceptance/suites/m2.json`):
##
##     MELTDOWN_RECORD_M2=look_aim_shot godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "look_aim_shot"
const REPLAY_PATH: String = "res://acceptance/replays/look_aim_shot.replay"
const LOOK_AIM_PATH: String = "res://data/aim/look_aim.json"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
const Main := preload("res://main.gd")
## Ticks spent turning the guns before the first shot, firing, then flying on.
const AIM_TICKS: int = 30
const FIRE_TICKS: int = 60
const SETTLE_TICKS: int = 60
const AIM_DEGREES_RIGHT: float = 10.0
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# Hovering in the test tunnel, aiming 10 degrees right of the nose and firing (#922).
# Re-record from the repository root, then copy the printed hash into m2.json:
#     MELTDOWN_RECORD_M2=look_aim_shot godot --headless --path game -s res://tests/run_tests.gd
"""


## Aims right of the nose throughout, and fires during the middle stretch.
class AimSource extends ShipInputSource:
	func next_input(tick: int) -> ShipInput:
		var input: ShipInput = ShipInput.new()
		var aim: Vector3 = LookAim.NOSE.rotated(Vector3.UP, -deg_to_rad(AIM_DEGREES_RIGHT))
		input.aim_q = ShipInput.aim_q_from(aim)
		input.fire_primary = tick >= AIM_TICKS and tick < AIM_TICKS + FIRE_TICKS
		return input


static func look_aim() -> LookAim:
	return LookAim.parse_json(FileAccess.get_file_as_string(LOOK_AIM_PATH))


## The test tunnel's walls and shipped ship, without its robots, so the step
## is about the shots alone, with the shipped look-aim values.
static func record() -> LocalSession:
	var robots: Array[RobotSpawn] = []
	var session: LocalSession = LocalSession.new(0, AimSource.new(),
		TestTunnel.interior_box(Main.TUNNEL_OFFSET), LocalSession.load_tuning(Main.SHIP_TUNING_PATH),
		robots)
	var aim: LookAim = look_aim()
	if session.sim.set_look_aim(aim) == "":
		session.replay.look_aim = aim
	while session.sim.tick < AIM_TICKS + FIRE_TICKS + SETTLE_TICKS:
		session.advance(ShipState.TICK_DT)
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
	print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [REPLAY_PATH,
		session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m2_suite_has_the_look_aim_step() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH]
	if found.checks != wanted or found.replay_path != REPLAY_PATH or found.level != "":
		return "%s checks %s flying %s on level '%s'" % [STEP_ID, found.checks, found.replay_path,
			found.level]
	return ""


## The replay carries the shipped look-aim values and aims off the nose, and
## run twice from the file it ends on the suite's hash.
func test_replay_replays_to_its_hash() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		if replay.look_aim == null or replay.look_aim.values_hash() != look_aim().values_hash():
			return "the replay does not carry the shipped look-aim values"
		if not (replay.frames[0][0] as ShipInput).aims_off_nose():
			return "the replay does not aim off the nose"
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		if sim.state_hash() != found.expected_hash or sim.state_hash() != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" \
				% [attempt + 1, sim.state_hash(), found.expected_hash, replay.expected_hash]
	return ""


## The device runner flies the step through `ReplayInputSource`, which must
## hand the session the replay's look-aim values and aims, or the shots would
## leave along the nose and miss the hash.
func test_the_replay_source_flies_the_same_run() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = source.new_session()
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	if session.sim.state_hash() != replay.expected_hash:
		return "the replay source flew to %d, the replay expects %d" % [session.sim.state_hash(),
			replay.expected_hash]
	return ""


## The recorder as it is now still fires along the aim: every shot of the
## live flight leaves ten degrees right of the nose.
func test_the_recorded_shots_leave_along_the_aim() -> String:
	var session: LocalSession = record()
	var gun: Vector3 = session.sim.ships[0].gun_direction
	var right: float = rad_to_deg(atan2(gun.x, -gun.z))
	if absf(right - AIM_DEGREES_RIGHT) > 0.1:
		return "the guns ended %.3f degrees right, expected %.1f" % [right, AIM_DEGREES_RIGHT]
	return ""
