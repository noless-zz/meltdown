extends RefCounted

## Ships rescue trapped miners by holding near them (SLV-3, CRW-1, #999): the
## rules are data, rescue is off unless switched on, and the same seed and
## inputs give the same hash and rescued count (ARC-2).

const LayerScanner := preload("res://tests/layer_scanner.gd")
const REPLAY_DIRS: Array[String] = ["res://acceptance/replays", "res://tests/replays"]
const RULES: String = "{\"rescue_reach\": 4.0, \"hold_seconds\": 0.5}"
## 0.5 s at 60 Hz.
const HOLD_TICKS: int = 30


static func rules() -> MinerRescue:
	return MinerRescue.parse_json(RULES)


## A one-ship sim at the origin with rescue on and `miners` in millimetres.
static func sim_with(miners: Array[Vector3i], run_seed: int = 1) -> Sim:
	var sim: Sim = Sim.new(run_seed, 1)
	sim.set_rescue_rules(rules(), miners)
	return sim


static func step_with(sim: Sim, input: ShipInput) -> bool:
	var inputs: Array[ShipInput] = [input]
	return sim.step(inputs)


static func idle(sim: Sim, ticks: int) -> void:
	for t: int in ticks:
		step_with(sim, ShipInput.new())


static func rescued_events(sim: Sim) -> Array[SimEvent]:
	var found: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.MINER_RESCUED:
			found.append(event)
	return found


func test_rules_file_ships_and_errors_name_the_key() -> String:
	var shipped: MinerRescue = MinerRescue.parse_json(
		FileAccess.get_file_as_string("res://data/miners/rescue.json"))
	if shipped.error != "" or shipped.rescue_reach <= 0.0 or shipped.hold_seconds <= 0.0:
		return "shipped rescue.json: \"%s\"" % shipped.error
	var cases: Dictionary = {
		"{\"hold_seconds\": 1}": "missing key \"rescue_reach\"",
		"{\"rescue_reach\": 4}": "missing key \"hold_seconds\"",
		"{\"rescue_reach\": 4, \"hold_seconds\": 1, \"speed\": 2}": "unknown key \"speed\"",
		"{\"rescue_reach\": 0, \"hold_seconds\": 1}": "key \"rescue_reach\"",
		"{\"rescue_reach\": -2, \"hold_seconds\": 1}": "key \"rescue_reach\"",
		"{\"rescue_reach\": 4, \"hold_seconds\": 0}": "key \"hold_seconds\"",
		"{\"rescue_reach\": 4, \"hold_seconds\": -1}": "key \"hold_seconds\"",
		"{\"rescue_reach\": true, \"hold_seconds\": 1}": "key \"rescue_reach\"",
		"{\"rescue_reach\": 4, \"hold_seconds\": 1000}": "key \"hold_seconds\"",
		"[]": "top level",
		"{": "invalid JSON",
	}
	for text: String in cases:
		var parsed: MinerRescue = MinerRescue.parse_json(text)
		if not parsed.error.contains(cases[text]):
			return "%s gave \"%s\", want it to name %s" % [text, parsed.error, cases[text]]
	return ""


func test_rules_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(1, 1)
	var none: Array[Vector3i] = [Vector3i.ZERO]
	if sim.set_rescue_rules(null, none) == "" \
			or sim.set_rescue_rules(MinerRescue.parse_json("{}"), none) == "":
		return "unresolved rules accepted"
	if sim.rescue != null:
		return "a refused setter switched rescue on"
	idle(sim, 1)
	if sim.set_rescue_rules(rules(), none) == "" or sim.rescue != null:
		return "rules accepted after the first tick"
	return ""


func test_parked_ship_rescues_after_exactly_the_hold() -> String:
	var miners: Array[Vector3i] = [Vector3i(1000, 0, 0)]
	var sim: Sim = sim_with(miners)
	if sim.rescue.hold_ticks() != HOLD_TICKS:
		return "hold_ticks %d, want %d" % [sim.rescue.hold_ticks(), HOLD_TICKS]
	for t: int in HOLD_TICKS - 1:
		step_with(sim, ShipInput.new())
		if not rescued_events(sim).is_empty() or sim.rescue.rescued != 0:
			return "rescued early, on tick %d" % (t + 1)
	step_with(sim, ShipInput.new())
	var events: Array[SimEvent] = rescued_events(sim)
	if events.size() != 1 or sim.rescue.rescued != 1 or not sim.rescue.trapped.is_empty():
		return "after %d ticks: %d events, rescued %d, %d trapped" % [HOLD_TICKS,
			events.size(), sim.rescue.rescued, sim.rescue.trapped.size()]
	if events[0].ship != 0 or events[0].magnitude != 0.0 or events[0].vector != Vector3(1, 0, 0):
		return "event %s" % events[0]
	idle(sim, HOLD_TICKS * 2)
	if sim.rescue.rescued != 1:
		return "one miner rescued %d times" % sim.rescue.rescued
	return ""


func test_leaving_reach_one_tick_early_resets_the_count() -> String:
	var miners: Array[Vector3i] = [Vector3i.ZERO]
	var sim: Sim = sim_with(miners)
	idle(sim, HOLD_TICKS - 1)
	sim.ships[0].position = Vector3(10, 0, 0)
	idle(sim, 1)
	if sim.rescue.held[0] != 0:
		return "count %d after leaving reach" % sim.rescue.held[0]
	sim.ships[0].position = Vector3.ZERO
	idle(sim, HOLD_TICKS - 1)
	if sim.rescue.rescued != 0:
		return "rescued without a full hold after returning"
	idle(sim, 1)
	if sim.rescue.rescued != 1:
		return "not rescued after a full hold"
	return ""


func test_miner_out_of_reach_stays() -> String:
	var miners: Array[Vector3i] = [Vector3i(0, 0, -4001), Vector3i(0, 0, 4000)]
	var sim: Sim = sim_with(miners)
	idle(sim, HOLD_TICKS)
	if sim.rescue.rescued != 1 or sim.rescue.trapped != [Vector3i(0, 0, -4001)]:
		return "rescued %d, trapped %s" % [sim.rescue.rescued, sim.rescue.trapped]
	var events: Array[SimEvent] = rescued_events(sim)
	if events.size() != 1 or events[0].magnitude != 1.0:
		return "events %s" % [events]
	idle(sim, HOLD_TICKS * 3)
	if sim.rescue.rescued != 1 or sim.rescue.held[0] != 0:
		return "the far miner was counted"
	return ""


func test_destroyed_ship_does_not_rescue() -> String:
	var miners: Array[Vector3i] = [Vector3i.ZERO]
	var sim: Sim = sim_with(miners)
	sim.ships[0].apply_damage(100000.0)
	idle(sim, HOLD_TICKS * 2)
	if sim.rescue.rescued != 0:
		return "a destroyed ship rescued a miner"
	return ""


func test_two_sims_sharing_rules_keep_their_own_counts() -> String:
	var miners: Array[Vector3i] = [Vector3i.ZERO]
	var shared: MinerRescue = rules()
	var a: Sim = Sim.new(1, 1)
	var b: Sim = Sim.new(1, 1)
	a.set_rescue_rules(shared, miners)
	b.set_rescue_rules(shared, miners)
	idle(a, HOLD_TICKS)
	if a.rescue.rescued != 1 or b.rescue.rescued != 0 or shared.rescued != 0 or miners.size() != 1:
		return "state leaked between sims"
	return ""


## A ship flies forward past three miners, slowing near one; two runs of the
## same inputs agree, and the rescue state is in the hash.
func test_same_seed_and_inputs_same_hash_and_rescued() -> String:
	var miners: Array[Vector3i] = [Vector3i(0, 0, -6000), Vector3i(0, 2000, -30000),
		Vector3i(50000, 0, 0)]
	var results: Array[String] = []
	for run: int in 2:
		var sim: Sim = sim_with(miners, 777)
		for t: int in 600:
			var forward: bool = t % 120 < 20
			var thrust: Vector3 = Vector3(0, 0, -1) if forward else Vector3.ZERO
			step_with(sim, ShipInput.from_floats(thrust, Vector3.ZERO))
		results.append("%d/%d" % [sim.state_hash(), sim.rescue.rescued])
	if results[0] != results[1]:
		return "runs differ: %s" % [results]
	var plain: Sim = Sim.new(777, 1)
	var with_rules: Sim = sim_with(miners, 777)
	if plain.state_hash() == with_rules.state_hash():
		return "rescue rules are not in the hash"
	var one: Sim = sim_with(miners, 777)
	var other: Sim = sim_with(miners, 777)
	idle(one, 3)
	idle(other, 3)
	other.rescue.held[0] += 1
	if one.state_hash() == other.state_hash():
		return "hold counts are not in the hash"
	return ""


func test_shipped_replays_keep_their_hashes_without_rescue() -> String:
	var checked: int = 0
	for dir: String in REPLAY_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if file.get_extension() != "replay":
				continue
			var replay: Replay = Replay.load_file("%s/%s" % [dir, file])
			if replay == null or replay.error != "" or replay.expected_hash == Replay.NO_HASH \
					or replay.walls() == null:
				continue
			var sim: Sim = replay.run()
			if sim == null:
				return "%s did not run: %s" % [file, replay.run_error]
			if sim.rescue != null:
				return "%s ran with rescue on" % file
			if sim.state_hash() != replay.expected_hash:
				return "%s ends on %d, recorded %d" % [file, sim.state_hash(), replay.expected_hash]
			checked += 1
	if checked < 5:
		return "only %d replays checked" % checked
	return ""


func test_event_kinds_keep_their_numbers() -> String:
	if SimEvent.Kind.COMPONENT_COLLECTED != 15 or SimEvent.Kind.MINER_RESCUED != 16:
		return "kinds renumbered: COMPONENT_COLLECTED %d, MINER_RESCUED %d" % [
			SimEvent.Kind.COMPONENT_COLLECTED, SimEvent.Kind.MINER_RESCUED]
	return ""


func test_rescue_file_keeps_the_layer_rules() -> String:
	var scanner: LayerScanner = LayerScanner.new()
	var classes: Array[String] = []
	for path: String in scanner.collect_scripts("res://core"):
		classes.append_array(scanner.declared_classes(FileAccess.get_file_as_string(path)))
	var path: String = "res://core/miner_rescue.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty():
		return "%s is missing" % path
	return "\n".join(scanner.scan_source(source, path, classes))
