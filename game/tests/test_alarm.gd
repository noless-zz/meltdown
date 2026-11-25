extends RefCounted

## The level's alarm in the core (#1342, RUN-6, ARC-1, ARC-2, ARC-4): it rises
## with time, shots and robots woken, by data, scaled by the shaft's risk, up to
## the cap; it is deterministic and part of the state hash only while it is set.

const ALARM_FILE: String = "res://data/alarm/alarm.json"
const PULSE: String = "res://data/weapons/pulse_cannon.json"
const NEEDLER: String = "res://data/robots/needler.json"
const RULES: String = '{"rise_per_second": 0.01, "per_shot": 0.02, "per_robot_alert": 0.1,' \
	+ ' "cap": 0.9, "steps": [0.3, 0.6]}'


func _rules(text: String = RULES) -> Alarm:
	return Alarm.parse_json(text)


## One ship in a large box, armed with the pulse cannon, alarm on at `risk`.
func _sim(risk: float = 1.0, rules: Alarm = null) -> Sim:
	var sim: Sim = Sim.new(1342, 1, BoxBounds.new(Vector3(-50, -50, -400), Vector3(50, 50, 50)))
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon", WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	sim.equip(loadout)
	if risk > 0.0:
		sim.set_alarm_rules(_rules() if rules == null else rules, risk)
	return sim


func _step(sim: Sim, fire: bool = false) -> void:
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, fire)]
	sim.step(inputs)


func test_the_shipped_file_parses() -> String:
	var rules: Alarm = Alarm.parse_json(FileAccess.get_file_as_string(ALARM_FILE))
	if rules.error != "":
		return rules.error
	return "" if rules.cap > 0.0 and not rules.steps.is_empty() else "no cap or no steps"


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Dictionary = {
		"[]": "top level must be a JSON object",
		'{"rise_per_second": 0.01, "per_shot": 0.02, "per_robot_alert": 0.1, "cap": 0.9}': "missing key \"steps\"",
		RULES.replace("\"cap\"", "\"top\""): "unknown key \"top\"",
		RULES.replace("0.02", "true"): "key \"per_shot\" must be a number",
		RULES.replace("0.01", "-0.5"): "key \"rise_per_second\" is -0.5, must be from 0 to 1",
		RULES.replace("0.9", "0"): "key \"cap\" is 0.0, must be from 0 to 1 and above 0",
		RULES.replace("[0.3, 0.6]", "[0.6, 0.3]"): "key \"steps\" must be a list of rising levels above 0 and at most the cap",
		RULES.replace("[0.3, 0.6]", "[0.3, 0.95]"): "key \"steps\" must be a list of rising levels above 0 and at most the cap",
	}
	for text: String in cases:
		var rules: Alarm = Alarm.parse_json(text)
		if rules.error != cases[text]:
			return "%s: got '%s'" % [text, rules.error]
	return ""


func test_quiet_flight_rises_by_time_alone() -> String:
	var sim: Sim = _sim()
	for tick: int in 60:
		_step(sim)
	if not is_equal_approx(sim.alarm.level, 0.01):
		return "one quiet second gave %f, not 0.01" % sim.alarm.level
	return ""


func test_shots_raise_it_faster_than_quiet_flight() -> String:
	var quiet: Sim = _sim()
	var loud: Sim = _sim()
	for tick: int in 120:
		_step(quiet)
		_step(loud, true)
	if loud.alarm.level <= quiet.alarm.level:
		return "shooting gave %f, quiet %f" % [loud.alarm.level, quiet.alarm.level]
	var shots: int = 0
	for projectile: Projectile in loud.projectiles:
		shots += 1 if not projectile.is_robot_owned() else 0
	return "" if shots > 0 else "the armed ship fired nothing"


func test_a_riskier_shaft_raises_it_faster() -> String:
	var plain: Sim = _sim(1.0)
	var risky: Sim = _sim(1.5)
	for tick: int in 120:
		_step(plain, tick % 10 == 0)
		_step(risky, tick % 10 == 0)
	if not is_equal_approx(risky.alarm.level, plain.alarm.level * 1.5):
		return "risk 1.5 gave %f against %f" % [risky.alarm.level, plain.alarm.level]
	return ""


func test_a_woken_robot_raises_it() -> String:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(NEEDLER))
	def.set_wake_range(10.0)
	var near: Sim = _sim()
	near.spawn_robot(def, Vector3(0, 0, -5), Basis.IDENTITY)
	var far: Sim = _sim()
	far.spawn_robot(def, Vector3(0, 0, -200), Basis.IDENTITY)
	_step(near)
	_step(far)
	if not near.robots[0].awake or far.robots[0].awake:
		return "the near robot did not wake or the far one did"
	var expected: float = 0.01 / 60.0 + 0.1
	if not is_equal_approx(near.alarm.level, expected):
		return "a woken robot gave %f, not %f" % [near.alarm.level, expected]
	_step(near)
	if not is_equal_approx(near.alarm.level, expected + 0.01 / 60.0):
		return "a robot already awake raised it again: %f" % near.alarm.level
	return ""


func test_it_stops_at_the_cap_and_reports_each_step_once() -> String:
	var sim: Sim = _sim(1.0, _rules(RULES.replace("0.01", "1")))
	var raised: Array[float] = []
	for tick: int in 120:
		_step(sim)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.ALARM_RAISED:
				raised.append(event.magnitude)
	if sim.alarm.level != 0.9:
		return "level %f, not the cap 0.9" % sim.alarm.level
	if str(raised) != str([0.3, 0.6]):
		return "raised %s" % [raised]
	return ""


func test_same_seed_and_inputs_give_the_same_curve() -> String:
	var first: Sim = _sim(1.25)
	var second: Sim = _sim(1.25)
	for tick: int in 300:
		_step(first, tick % 7 < 3)
		_step(second, tick % 7 < 3)
		if first.alarm.level != second.alarm.level or first.state_hash() != second.state_hash():
			return "the runs parted at tick %d" % tick
	return ""


func test_the_hash_holds_the_alarm_only_while_it_is_set() -> String:
	var off: Sim = _sim(0.0)
	var plain: Sim = Sim.new(1342, 1, BoxBounds.new(Vector3(-50, -50, -400), Vector3(50, 50, 50)))
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon", WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	plain.equip(loadout)
	if off.state_hash() != plain.state_hash():
		return "a sim without an alarm hashes differently"
	var on: Sim = _sim()
	if on.state_hash() == off.state_hash():
		return "the alarm's rules are not in the hash"
	var other: Sim = _sim()
	_step(on)
	_step(other)
	if other.state_hash() != on.state_hash():
		return "two equal runs hash apart"
	other.alarm.level += 0.1
	return "" if other.state_hash() != on.state_hash() else "the level is not in the hash"


func test_it_is_set_only_before_the_first_tick_with_a_sane_risk() -> String:
	var sim: Sim = _sim(0.0)
	if sim.set_alarm_rules(_rules(), 0.0) == "" or sim.set_alarm_rules(_rules(), 11.0) == "":
		return "a risk of 0 or 11 was taken"
	if sim.set_alarm_rules(_rules("[]")) == "":
		return "rejected rules were taken"
	_step(sim)
	if sim.set_alarm_rules(_rules()) == "" or sim.alarm != null:
		return "the alarm was set after the first tick"
	return ""


func test_two_sims_given_one_rules_object_rise_apart() -> String:
	var rules: Alarm = _rules()
	var loud: Sim = _sim(1.0, rules)
	var quiet: Sim = _sim(1.0, rules)
	for tick: int in 60:
		_step(loud, true)
		_step(quiet)
	if rules.level != 0.0:
		return "the shared rules object rose"
	return "" if loud.alarm.level > quiet.alarm.level else "the sims shared a level"


func test_the_session_copy_is_a_number_and_zero_without_an_alarm() -> String:
	if SessionSnapshots.alarm_level(null) != 0.0:
		return "no alarm read as %f" % SessionSnapshots.alarm_level(null)
	var sim: Sim = _sim()
	_step(sim, true)
	var copy: float = SessionSnapshots.alarm_level(sim.alarm)
	if copy != sim.alarm.level:
		return "the copy is %f, the level %f" % [copy, sim.alarm.level]
	return ""
