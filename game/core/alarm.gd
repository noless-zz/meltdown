class_name Alarm
extends RefCounted

## The level's alarm (RUN-6, AUD-3, #1342): a level from 0 to `cap` that rises
## a little every tick and more with noise, the ships' shots and robots woken
## to a ship. The rates come from `data/alarm/alarm.json` (ARC-4); core opens
## no files, so the caller hands the text to `parse_json` and the rules, with
## the level's shaft `risk` multiplier, to `Sim.set_alarm_rules`. The sim then
## owns a copy holding the run's state: the level and how many of the data's
## `steps` it has passed. The static functions are the per-tick logic, kept out
## of `Sim` so its tick stays short.
##
## No unseeded randomness and no clock: the same seed and inputs give the same
## alarm curve (ARC-1, ARC-2), and the level is part of the state hash, so
## replays pin it. Robots do not react to it yet; the music reads it (AUD-3).

## Every key of the data file; all are required and no others are allowed.
const KEYS: Array[String] = ["rise_per_second", "per_shot", "per_robot_alert", "cap", "steps"]
const TICKS_PER_SECOND: int = 60
## Highest shaft risk multiplier `install` accepts.
const RISK_MAX: float = 10.0

## Rise every second with no noise at all, per second of flight.
var rise_per_second: float = 0.0
## Rise for each shot a ship fires.
var per_shot: float = 0.0
## Rise for each robot woken to a ship (or by a hit) on a tick.
var per_robot_alert: float = 0.0
## The highest the level goes, above 0 and at most 1.
var cap: float = 1.0
## Levels whose crossing reports an ALARM_RAISED event, rising, each in (0, cap].
var steps: Array[float] = []
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""

## Run state, only in the copy a sim owns: the shaft's alarm multiplier on
## every rise, the level now, and how many of `steps` it has reached.
var risk: float = 1.0
var level: float = 0.0
var steps_passed: int = 0


## Parses the text of the alarm file. A missing, unknown or out-of-range key
## is an error naming the key. On failure the returned rules have `error` set.
static func parse_json(text: String) -> Alarm:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var rules: Alarm = Alarm.new()
	var numbers: Array[float] = []
	for key: String in ["rise_per_second", "per_shot", "per_robot_alert", "cap"]:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		if float(value) < 0.0 or float(value) > 1.0 or (key == "cap" and float(value) == 0.0):
			return _rejected("key \"%s\" is %s, must be from 0 to 1%s" % [key, float(value),
				" and above 0" if key == "cap" else ""])
		numbers.append(float(value))
	rules.rise_per_second = numbers[0]
	rules.per_shot = numbers[1]
	rules.per_robot_alert = numbers[2]
	rules.cap = numbers[3]
	var problem: String = _read_steps(data["steps"], rules.cap, rules.steps)
	if problem != "":
		return _rejected(problem)
	return rules


static func _read_steps(value: Variant, top: float, out: Array[float]) -> String:
	var message: String = "key \"steps\" must be a list of rising levels above 0 and at most the cap"
	if typeof(value) != TYPE_ARRAY:
		return message
	var last: float = 0.0
	for entry: Variant in value:
		if typeof(entry) != TYPE_FLOAT and typeof(entry) != TYPE_INT:
			return message
		if float(entry) <= last or float(entry) > top:
			return message
		last = float(entry)
		out.append(last)
	return ""


## The data file's values as a dictionary, as `parse_json` reads them back.
func to_data() -> Dictionary:
	return {"rise_per_second": rise_per_second, "per_shot": per_shot,
		"per_robot_alert": per_robot_alert, "cap": cap, "steps": steps.duplicate()}


func values_hash() -> int:
	return hash(["alarm", rise_per_second, per_shot, per_robot_alert, cap, steps, risk])


## Gives `sim` a fresh copy of `rules` at level 0 with the shaft's `p_risk`
## multiplier unless `started`; for `Sim.set_alarm_rules`.
static func install(sim: Sim, rules: Alarm, p_risk: float, started: bool) -> String:
	if started:
		return "the alarm rules are set before the first tick"
	if rules == null or rules.error != "":
		return "the alarm rules are not resolved"
	if p_risk <= 0.0 or p_risk > RISK_MAX:
		return "the alarm risk is %s, must be above 0 and at most %s" % [p_risk, RISK_MAX]
	sim.alarm = rules.with_risk(p_risk)
	return ""


## A fresh copy of these rules at level 0 rising by `p_risk`, for a sim or a
## replay to own, so one rules object shared by two never shares a level.
func with_risk(p_risk: float) -> Alarm:
	var own: Alarm = Alarm.new()
	own.rise_per_second = rise_per_second
	own.per_shot = per_shot
	own.per_robot_alert = per_robot_alert
	own.cap = cap
	own.steps = steps.duplicate()
	own.risk = p_risk
	return own


## The robots of `sim` still asleep before a tick, for `step` to tell which woke.
static func sleeping(sim: Sim) -> Array[RobotState]:
	var out: Array[RobotState] = []
	if sim.alarm == null:
		return out
	for robot: RobotState in sim.robots:
		if not robot.awake:
			out.append(robot)
	return out


## Raises the level for one tick: the quiet rise, `shots` the ships fired this
## tick and every robot of `asleep` (from `sleeping`) now awake, all times the
## risk, up to the cap. Each step crossed adds one ALARM_RAISED event. Nothing
## rises once the run's outcome is decided; nothing at all without rules.
static func step(sim: Sim, shots: int, asleep: Array[RobotState]) -> void:
	var state: Alarm = sim.alarm
	if state == null or sim.outcome() != ExitRule.Outcome.RUNNING:
		return
	var woken: int = 0
	for robot: RobotState in asleep:
		if robot.awake:
			woken += 1
	var rise: float = state.rise_per_second / TICKS_PER_SECOND + shots * state.per_shot \
		+ woken * state.per_robot_alert
	state.level = minf(state.cap, state.level + rise * state.risk)
	while state.steps_passed < state.steps.size() and state.level >= state.steps[state.steps_passed]:
		sim.last_events.append(SimEvent.new(SimEvent.Kind.ALARM_RAISED, 0,
			state.steps[state.steps_passed]))
		state.steps_passed += 1


## Hash of the alarm, joined to the sim's only with rules set.
static func state_hash(sim: Sim) -> int:
	var state: Alarm = sim.alarm
	return hash([state.values_hash(), state.level, state.steps_passed])


static func _rejected(message: String) -> Alarm:
	var rules: Alarm = Alarm.new()
	rules.error = message
	return rules
