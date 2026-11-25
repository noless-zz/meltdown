extends RefCounted

## A replay's alarm line (#1342, RUN-6, ARC-2): it round-trips the rules and
## the shaft's risk, a replay without it is written as before, a bad line is
## refused, and the shipped alarm replay raises the alarm past the music's
## first tension layer before it blows the reactor (AUD-3).

const ALARM_REPLAY: String = "res://acceptance/replays/bot_g2_escape_alarm.replay"
const PLAIN_REPLAY: String = "res://acceptance/replays/bot_g2_escape.replay"
const LINE: String = "alarm {\"cap\":1.0,\"per_robot_alert\":0.04,\"per_shot\":0.002," \
	+ "\"rise_per_second\":0.004,\"risk\":1.5,\"steps\":[0.35,0.7]}"


func _text(version: int, extra: String) -> String:
	return "meltdown-replay %d\nseed 1\nships 1\n%sinputs\n0 0 0 0 0 0 0 0 0 0\n" % [version, extra]


func test_the_line_round_trips() -> String:
	var replay: Replay = Replay.from_text(_text(20, LINE + "\n"))
	if replay.error != "":
		return replay.error
	if replay.alarm_rules == null or replay.alarm_rules.risk != 1.5 or replay.alarm_rules.per_shot != 0.002:
		return "the line read as %s" % [replay.alarm_rules]
	var text: String = replay.to_text()
	if not text.begins_with("meltdown-replay 20\n") or not text.contains("\n" + LINE + "\n"):
		return "written back as:\n%s" % text
	var sim: Sim = replay.run()
	if sim == null or sim.alarm == null or sim.alarm.risk != 1.5:
		return "the run flew without the replay's alarm"
	return ""


func test_a_replay_without_the_line_keeps_its_version() -> String:
	var replay: Replay = Replay.load_file(PLAIN_REPLAY)
	if replay.error != "" or replay.alarm_rules != null:
		return "the plain replay: '%s'" % replay.error
	if not replay.to_text().begins_with("meltdown-replay 17\n"):
		return "the plain replay is written as a newer version"
	return "" if replay.run().alarm == null else "the plain replay flew with an alarm"


func test_bad_lines_are_refused() -> String:
	var cases: Dictionary = {
		_text(19, LINE + "\n"): "line 4: an alarm line needs format version 20 or later",
		_text(20, LINE + "\n" + LINE + "\n"): "line 5: 'alarm' appears twice",
		_text(20, LINE.replace("\"risk\":1.5,", "") + "\n"):
			"line 4: alarm: key \"risk\" must be a number above 0 and at most 10.0",
		_text(20, LINE.replace("1.5", "0") + "\n"):
			"line 4: alarm: key \"risk\" must be a number above 0 and at most 10.0",
		_text(20, LINE.replace("\"cap\":1.0,", "") + "\n"): "line 4: alarm: missing key \"cap\"",
		_text(20, "alarm [1]\n"): "line 4: alarm: must be one JSON object",
	}
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if replay.error != cases[text]:
			return "%s: got '%s'" % [text.c_escape(), replay.error]
	return ""


func test_the_alarm_replay_flies_the_plain_one_with_a_rising_alarm() -> String:
	var replay: Replay = Replay.load_file(ALARM_REPLAY)
	var plain: Replay = Replay.load_file(PLAIN_REPLAY)
	if replay.error != "" or replay.alarm_rules == null:
		return "the alarm replay: '%s'" % replay.error
	if replay.frames.size() != plain.frames.size():
		return "the alarm replay flies other inputs"
	var shipped: Alarm = Alarm.parse_json(FileAccess.get_file_as_string(RunLevelRules.ALARM_FILE))
	if replay.alarm_rules.to_data() != shipped.to_data():
		return "the replay's alarm is not the shipped file's"
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	var at_reactor: float = -1.0
	for tick: int in frames.size():
		var inputs: Array[ShipInput] = []
		inputs.assign(frames[tick])
		sim.step(inputs)
		if at_reactor < 0.0 and sim.reactor.destroyed:
			at_reactor = sim.alarm.level
	if sim.state_hash() != replay.expected_hash:
		return "hash %d, pinned %d" % [sim.state_hash(), replay.expected_hash]
	var tension: float = 2.0
	for layer: MusicLayer in MusicTable.load_file().layers:
		if layer.plays == MusicLayer.RUN and layer.from_alarm > 0.0:
			tension = minf(tension, layer.from_alarm)
	if at_reactor < tension:
		return "the alarm was %f when the reactor blew, below %f" % [at_reactor, tension]
	return ""
