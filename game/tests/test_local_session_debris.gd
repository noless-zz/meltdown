extends RefCounted

## `LocalSession.for_level` carries the level's meltdown debris into the
## simulation and its replay (#439, RUN-4, RUN-2, MP-2, ARC-2), the same way as
## the reactor, so a flown level has the debris the main scene draws (#422).

const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## One box, the reactor 30 m ahead (five pulse shots), five seconds of meltdown,
## and two entries off the line of fire: the first falls half a second into the
## meltdown, the second a second in.
const DEBRIS_LEVEL: String = """{
	"boxes": [{"min": [-10.0, -10.0, -100.0], "max": [10.0, 10.0, 10.0]}],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 5},
	"debris": [
		{"position": [7.0, 7.0, -15.0], "radius": 1.0, "after_seconds": 0.5},
		{"position": [-7.0, -7.0, -15.0], "radius": 1.0, "after_seconds": 1.0}
	]
}"""
## Enough ticks to shoot the reactor down and pass both entries' times.
const FLIGHT_TICKS: int = 300


## Holds the trigger every tick and does not move, so the shots hit the reactor.
class FireSource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		var input: ShipInput = ShipInput.new()
		input.fire_primary = true
		return input


func _level() -> LevelDef:
	return LevelDef.parse_json(DEBRIS_LEVEL)


func _session(level: LevelDef, source: ShipInputSource = null) -> LocalSession:
	return LocalSession.for_level(level, 0, source, LocalSession.load_tuning(SHIP_TUNING_PATH))


func test_the_session_gives_the_level_debris_to_the_sim_and_the_replay() -> String:
	var level: LevelDef = _level()
	if level.error != "" or level.debris == null or level.debris.size() != 2:
		return "the debris level did not parse with two entries: '%s'" % level.error
	var session: LocalSession = _session(level)
	var live: MeltdownDebris = session.sim.debris
	var recorded: MeltdownDebris = session.replay.debris
	if live == null or recorded == null:
		return "debris on the sim %s, in the replay %s" % [live != null, recorded != null]
	if live == level.debris or recorded == level.debris or live == recorded:
		return "the sim, the replay and the level must each hold their own debris"
	for copy: MeltdownDebris in [live, recorded]:
		if copy.positions_mm != level.debris.positions_mm or copy.radii_mm != level.debris.radii_mm \
				or copy.after_ticks != level.debris.after_ticks:
			return "a copy's entries differ from the level's"
	if session.sim.tick != 0:
		return "the debris was set after tick %d" % session.sim.tick
	return ""


## Ticks on the live sim must not reach the copy a replay starts from.
func test_the_live_run_leaves_the_replay_copy_alone() -> String:
	var session: LocalSession = _session(_level(), FireSource.new())
	for tick: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	if session.sim.debris.elapsed_ticks == 0:
		return "the live debris clock never ran; the reactor was not destroyed"
	if session.replay.debris.elapsed_ticks != 0:
		return "the replay's debris clock moved to %d" % session.replay.debris.elapsed_ticks
	return ""


## Once the reactor is down and both times have passed, each entry is solid or
## held back by `DebrisRouteGuard`.
func test_after_the_meltdown_starts_the_entries_fall() -> String:
	var session: LocalSession = _session(_level(), FireSource.new())
	var died_at: int = -1
	for tick: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
		if died_at < 0 and session.sim.reactor.destroyed:
			died_at = session.sim.tick
			for index: int in session.sim.debris.size():
				if session.sim.debris.is_solid(index):
					return "entry %d was solid on the tick the reactor died" % index
	if died_at < 0:
		return "the reactor was never destroyed"
	if session.sim.tick < died_at + 61:
		return "the flight ended %d ticks after the reactor died" % (session.sim.tick - died_at)
	var debris: MeltdownDebris = session.sim.debris
	for index: int in debris.size():
		if not debris.is_solid(index) and not debris.is_skipped(index):
			return "entry %d is neither solid nor held after its time" % index
	return ""


## The replay, written as text and read back, ends on the live run's hash.
func test_the_replay_read_from_text_ends_on_the_session_hash() -> String:
	var session: LocalSession = _session(_level(), FireSource.new())
	for tick: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	var text: String = session.replay.to_text()
	if not text.contains("\ndebris "):
		return "the replay text has no debris line"
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	var sim: Sim = read.run()
	if sim == null:
		return read.run_error
	if sim.debris == null or sim.debris.elapsed_ticks != session.sim.debris.elapsed_ticks:
		return "the replayed debris clock does not match the live one"
	if sim.state_hash() != session.sim.state_hash():
		return "read back, the flight ends on %d, the session on %d" % [
			sim.state_hash(), session.sim.state_hash()]
	return ""


## The same level without its debris key gets no debris and no debris line.
func test_a_level_without_debris_gets_none() -> String:
	var data: Dictionary = JSON.parse_string(DEBRIS_LEVEL)
	data.erase("debris")
	var plain: LevelDef = LevelDef.parse_json(JSON.stringify(data))
	if plain.error != "" or plain.debris != null:
		return "the plain level: error '%s', debris %s" % [plain.error, plain.debris != null]
	var session: LocalSession = _session(plain, FireSource.new())
	if session.sim.debris != null or session.replay.debris != null:
		return "debris appeared in a level without any"
	for tick: int in 60:
		session.advance(ShipState.TICK_DT)
	if session.replay.to_text().contains("\ndebris "):
		return "the replay text has a debris line"
	return ""
