extends RefCounted

## The ship flown by the session takes its feel values from the ship data file
## (ARC-4, ARC-5, FLT-1), and its replay flies the same values (ARC-2).

const SHIP_FILE: String = "res://data/ships/default_ship.json"
const BAD_FILE: String = "user://test_session_tuning_bad.json"


## Full forward thrust on every tick.
class ForwardSource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 250, 0))


static func _tuning(max_speed: float) -> ShipTuning:
	var tuning: ShipTuning = ShipTuning.new()
	tuning.max_speed = max_speed
	tuning.max_hull = 70.0
	return tuning


static func _fly(session: LocalSession, seconds: int) -> void:
	for frame: int in seconds * 90:
		session.advance(1.0 / 90.0)


func test_a_tuned_session_reaches_its_max_speed() -> String:
	var tuned: LocalSession = LocalSession.new(1, ForwardSource.new(), null, _tuning(8.0))
	var plain: LocalSession = LocalSession.new(1, ForwardSource.new())
	_fly(tuned, 5)
	_fly(plain, 5)
	var tuned_speed: float = tuned.current_ship().velocity.length()
	var plain_speed: float = plain.current_ship().velocity.length()
	if absf(tuned_speed - 8.0) > 0.01:
		return "tuned ship flies at %.3f m/s, expected 8" % tuned_speed
	# Damping holds the default ship a little under its 20 m/s cap.
	if plain_speed < 15.0:
		return "untuned ship flies at %.3f m/s, expected near the default 20" % plain_speed
	return ""


func test_the_tuning_is_applied_before_the_first_tick() -> String:
	var session: LocalSession = LocalSession.new(1, ForwardSource.new(), null, _tuning(8.0))
	var ship: ShipState = session.current_ship()
	if ship.max_hull != 70.0 or ship.hull != 70.0:
		return "first snapshot has max hull %s, hull %s" % [ship.max_hull, ship.hull]
	if session.sim.ships[0].max_speed != 8.0:
		return "simulated ship has max speed %s" % session.sim.ships[0].max_speed
	return ""


func test_a_rejected_tuning_flies_the_defaults() -> String:
	var rejected: ShipTuning = ShipTuning.parse_json("{}")
	var session: LocalSession = LocalSession.new(1, ForwardSource.new(), null, rejected)
	if rejected.error == "":
		return "an empty object was accepted"
	if session.sim.ships[0].max_speed != ShipState.new().max_speed:
		return "a rejected tuning changed the ship"
	if session.replay.tuning != null:
		return "a rejected tuning was recorded in the replay"
	return ""


func test_a_rejected_file_loads_as_null() -> String:
	var file: FileAccess = FileAccess.open(BAD_FILE, FileAccess.WRITE)
	if file == null:
		return "could not write %s" % BAD_FILE
	file.store_string("{\"max_speed\": 900.0}")
	file.close()
	var tuning: ShipTuning = LocalSession.load_tuning(BAD_FILE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_FILE))
	if tuning != null:
		return "a rejected file gave a tuning"
	var session: LocalSession = LocalSession.new(1, ForwardSource.new(), null, tuning)
	if session.sim.ships[0].max_speed != 20.0:
		return "a session after a rejected file flies max speed %s" % session.sim.ships[0].max_speed
	return ""


func test_a_missing_file_loads_as_null() -> String:
	if LocalSession.load_tuning("res://data/ships/no_such_ship.json") != null:
		return "a missing file gave a tuning"
	return ""


func test_the_shipped_file_is_accepted() -> String:
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_FILE)
	if tuning == null:
		return "%s was rejected" % SHIP_FILE
	return ""


func test_the_main_scene_flies_the_shipped_file() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return "main.tscn did not load"
	var main: Node = scene.instantiate()
	var session: LocalSession = main.get("session")
	var recorded: ShipTuning = session.replay.tuning
	main.free()
	if recorded == null:
		return "the main scene's session has no tuning"
	var shipped: ShipTuning = LocalSession.load_tuning(SHIP_FILE)
	for key: String in ShipTuning.KEYS:
		if recorded.get(key) != shipped.get(key):
			return "key %s is %s in the session, %s in the file" % [key, recorded.get(key), shipped.get(key)]
	return ""


func test_the_replay_reproduces_a_tuned_session() -> String:
	var session: LocalSession = LocalSession.new(7, ForwardSource.new(), null, _tuning(8.0))
	_fly(session, 3)
	var replayed: Sim = session.replay.run()
	if replayed == null:
		return session.replay.run_error
	if replayed.state_hash() != session.sim.state_hash():
		return "replay ended at a different hash"
	var loaded: Replay = Replay.from_text(session.replay.to_text())
	if loaded.error != "":
		return loaded.error
	if loaded.run().state_hash() != session.sim.state_hash():
		return "replay read back from text ended at a different hash"
	if loaded.to_text() != session.replay.to_text():
		return "text changed in the round trip"
	return ""


func test_an_untuned_replay_has_no_tuning_line() -> String:
	var session: LocalSession = LocalSession.new(7, ForwardSource.new())
	_fly(session, 1)
	if session.replay.to_text().contains("tuning"):
		return "an untuned replay wrote a tuning line"
	return ""


func test_a_tuning_value_survives_the_text_exactly() -> String:
	var tuning: ShipTuning = _tuning(8.0)
	tuning.damping = 0.1 + 0.2
	var replay: Replay = Replay.new(1, 1)
	replay.tuning = tuning
	var loaded: Replay = Replay.from_text(replay.to_text())
	if loaded.error != "":
		return loaded.error
	if loaded.tuning.damping != tuning.damping:
		return "damping read back as %s" % loaded.tuning.damping
	return ""


func test_bad_tuning_lines_are_rejected() -> String:
	var line: String = "tuning " + JSON.stringify({"max_speed": 8.0})
	var cases: Dictionary = {
		"before version 5": "meltdown-replay 4\nseed 1\nships 1\ntuning {}\ninputs\n",
		"incomplete": "meltdown-replay 5\nseed 1\nships 1\n%s\ninputs\n" % line,
		"not JSON": "meltdown-replay 5\nseed 1\nships 1\ntuning max_speed=8\ninputs\n",
	}
	var good: Replay = Replay.new(1, 1)
	good.tuning = ShipTuning.new()
	var good_line: String = good.to_text().split("\n")[3]
	cases["twice"] = "meltdown-replay 5\nseed 1\nships 1\n%s\n%s\ninputs\n" % [good_line, good_line]
	for name: String in cases:
		if Replay.from_text(cases[name]).error == "":
			return "accepted a tuning line %s" % name
	return ""


## A replay read from text holds its weapons on their own lines, with the
## tuning's loadout unresolved; the session it starts must still be armed with
## them, or a flown replay would never fire (#270).
func test_a_given_loadout_replaces_the_tunings() -> String:
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_FILE)
	var replay: Replay = Replay.from_text(LocalSession.new(3, null, null, tuning).replay.to_text())
	if replay.error != "" or replay.loadout == null:
		return "the recorded replay has no weapons: %s" % replay.error
	if replay.tuning.loadout.is_armed():
		return "the parsed tuning's loadout is already resolved; this test checks nothing"
	var unarmed: LocalSession = LocalSession.new(3, null, null, replay.tuning)
	if unarmed.sim.ships[0].primary_slots[0] != null:
		return "the unresolved tuning armed the ship"
	var session: LocalSession = LocalSession.new(3, null, null, replay.tuning, [], replay.loadout)
	if session.sim.ships[0].primary_slots[0] == null:
		return "the given loadout did not arm the ship"
	if session.replay.loadout != replay.loadout:
		return "the given loadout was not recorded"
	return ""
