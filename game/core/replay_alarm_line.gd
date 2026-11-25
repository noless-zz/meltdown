class_name ReplayAlarmLine
extends RefCounted

## Writes and reads a replay's alarm line (version 20, #1342): the `Alarm`
## data file the level flies with plus "risk", the shaft's alarm multiplier
## (RUN-6), kept on `Replay.alarm_rules` as `Alarm.risk`. Kept apart from
## `Replay`, which is at its size limit, and called through `ReplayRulesLine`,
## which writes and applies the other run-level lines.
##
##     alarm {"cap":1.0,"per_robot_alert":0.04,"per_shot":0.002,"rise_per_second":0.004,"risk":1.0,"steps":[0.35,0.7]}
##
## A replay without the line flies with the alarm off, as every replay before
## version 20 did, and is written as an older version, so the text of every
## other replay, and every hash taken from it, stays as it was.

## First format version that may carry the line.
const VERSION: int = 20
const RISK_KEY: String = "risk"


## The version a replay with an alarm needs at least, or 0 without one.
static func format_version(replay: Replay) -> int:
	return VERSION if replay.alarm_rules != null else 0


static func lines(replay: Replay) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if replay.alarm_rules != null:
		var data: Dictionary = replay.alarm_rules.to_data()
		data[RISK_KEY] = replay.alarm_rules.risk
		out.append("alarm " + JSON.stringify(data, "", true, true))
	return out


## Gives `sim` the replay's alarm, if it has one. Before the first tick.
static func apply(replay: Replay, sim: Sim) -> void:
	if replay.alarm_rules != null:
		sim.set_alarm_rules(replay.alarm_rules, replay.alarm_rules.risk)


## `json_text` is everything after "alarm ". Returns "" with the rules, risk
## included, stored on `replay`, or a problem without the line number.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "an alarm line needs format version %d or later" % VERSION
	if seen.has("alarm"):
		return "'alarm' appears twice"
	seen["alarm"] = true
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "alarm: must be one JSON object"
	var data: Dictionary = json.data
	var risk: Variant = data.get(RISK_KEY, null)
	if typeof(risk) != TYPE_FLOAT and typeof(risk) != TYPE_INT \
			or float(risk) <= 0.0 or float(risk) > Alarm.RISK_MAX:
		return "alarm: key \"%s\" must be a number above 0 and at most %s" % [RISK_KEY, Alarm.RISK_MAX]
	data.erase(RISK_KEY)
	var rules: Alarm = Alarm.parse_json(JSON.stringify(data, "", true, true))
	if rules.error != "":
		return "alarm: " + rules.error
	rules.risk = float(risk)
	replay.alarm_rules = rules
	return ""
