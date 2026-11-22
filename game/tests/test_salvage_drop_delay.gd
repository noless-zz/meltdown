extends RefCounted

## A part dropped by a destroyed robot cannot be taken or pulled for its first
## `drop_delay_ticks` ticks, so a robot killed at point-blank range does not
## hand its part over unseen inside the explosion (#1217, SLV-1, ARC-2, ARC-4).

const DRONE: String = "res://data/robots/drone.json"
const SHIPPED: String = "res://data/salvage.json"
## Inside the shipped 1 m ship's pickup reach, straight ahead.
const POINT_BLANK: Vector3 = Vector3(0.0, 0.0, -2.0)


func _rules(delay: Variant = null) -> SalvageRules:
	var values: Dictionary = {"pickup_reach": 2.5, "pull_reach": 9.0, "pull_speed": 8.0,
		"swap_drop_distance": 4.0}
	if delay != null:
		values["drop_delay_ticks"] = delay
	return SalvageRules.parse_json(JSON.stringify(values))


func _step(sim: Sim) -> void:
	var inputs: Array[ShipInput] = []
	for i: int in sim.ships.size():
		inputs.append(ShipInput.new())
	sim.step(inputs)


## A sim whose ship sits at the origin with a drone at `at` that dies on the
## first tick, leaving its part there. Returns after that tick.
func _sim_after_kill(delay: int, at: Vector3 = POINT_BLANK) -> Sim:
	var sim: Sim = Sim.new(7, 1)
	sim.set_salvage_rules(_rules(delay))
	sim.spawn_robot(RobotDef.parse_json(FileAccess.get_file_as_string(DRONE)), at,
		Basis.IDENTITY)
	sim.robots[0].hull = 0.0
	_step(sim)
	return sim


func test_a_fresh_drop_is_not_taken_before_its_delay_and_is_on_that_tick() -> String:
	var delay: int = 45
	var sim: Sim = _sim_after_kill(delay)
	if sim.salvage.size() != 1:
		return "the drone left %d parts, expected 1" % sim.salvage.size()
	for tick: int in range(1, delay):
		_step(sim)
		if not sim.ships[0].hold.is_empty() or sim.salvage.size() != 1:
			return "the part was taken %d ticks after the drop, before %d" % [tick, delay]
	_step(sim)
	if sim.ships[0].hold.size() != 1 or not sim.salvage.is_empty():
		return "the part was not taken on tick %d after the drop" % delay
	return ""


func test_zero_delay_is_todays_behaviour() -> String:
	var sim: Sim = _sim_after_kill(0)
	if sim.salvage.size() != 1 or sim.salvage[0].pickup_delay != 0:
		return "the drop carries a delay with none in the rules"
	_step(sim)
	if sim.ships[0].hold.size() != 1:
		return "a part dropped with no delay was not taken on the next tick"
	return ""


func test_a_delayed_part_is_not_pulled_but_still_drifts() -> String:
	var sim: Sim = _sim_after_kill(30, Vector3(0.0, 0.0, -7.0))
	sim.salvage[0].velocity = Vector3(1.0, 0.0, 0.0)
	var start: Vector3 = sim.salvage[0].position
	for i: int in 29:
		_step(sim)
	var moved: Vector3 = sim.salvage[0].position - start
	if absf(moved.z) > 0.0001:
		return "a delayed part was pulled %.3f m towards the ship" % -moved.z
	if moved.x <= 0.0:
		return "a delayed part stopped drifting"
	for i: int in 120:
		_step(sim)
	if sim.ships[0].hold.size() != 1:
		return "the part was not pulled in once its delay ran out"
	return ""


func test_the_delay_is_in_the_state_hash_and_runs_repeat() -> String:
	var a: Sim = _sim_after_kill(45)
	var b: Sim = _sim_after_kill(45)
	var none: Sim = _sim_after_kill(0)
	if a.state_hash() == none.state_hash():
		return "a drop with a delay hashes like one without"
	for i: int in 90:
		_step(a)
		_step(b)
	if a.state_hash() != b.state_hash():
		return "two runs with the same seed and inputs ended on different hashes"
	return ""


func test_a_swapped_out_part_gets_no_delay() -> String:
	var item: SalvageItem = SalvageItem.new("pulse_cannon", Vector3.ZERO)
	if item.pickup_delay != 0 or not item.is_takeable():
		return "a part made outside a robot kill starts delayed"
	return ""


func test_the_key_is_optional_whole_and_bounded() -> String:
	if _rules().drop_delay_ticks != 0 or _rules().error != "":
		return "a file without the key does not read as no delay"
	if _rules().to_json().contains("drop_delay_ticks"):
		return "no delay changed the replay line"
	var failures: PackedStringArray = PackedStringArray()
	for bad: Variant in [1.5, -1, SalvageRules.MAX_DROP_DELAY_TICKS + 1, true, "45"]:
		if _rules(bad).error == "":
			failures.append("drop_delay_ticks %s was accepted" % str(bad))
	var rules: SalvageRules = _rules(45)
	if rules.error != "" or rules.drop_delay_ticks != 45:
		failures.append("45 read as %d (%s)" % [rules.drop_delay_ticks, rules.error])
	var back: SalvageRules = SalvageRules.parse_json(rules.to_json())
	if back.drop_delay_ticks != 45 or back.values_hash() != rules.values_hash():
		failures.append("the delay did not survive the replay line: %s" % rules.to_json())
	if _rules(0).to_json() != _rules().to_json():
		failures.append("a zero delay is written to the replay line")
	return "\n".join(failures)


func test_the_shipped_delay_is_about_three_quarters_of_a_second() -> String:
	var rules: SalvageRules = SalvageRules.parse_json(FileAccess.get_file_as_string(SHIPPED))
	if rules.error != "":
		return rules.error
	if rules.drop_delay_ticks < 30 or rules.drop_delay_ticks > 60:
		return "the shipped delay is %d ticks, the issue asks for about 45" % rules.drop_delay_ticks
	return ""
