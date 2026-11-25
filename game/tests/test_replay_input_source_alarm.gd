extends RefCounted

## An acceptance replay flies with its level's alarm (#1374, RUN-6, AUD-3,
## DEV-6, ARC-2): m6's `music_follows_alarm` step flies
## `bot_g2_escape_alarm.replay` through `ReplayInputSource`, which once left
## the alarm line out and ended on the hash of the same flight with the alarm
## off. Flown the acceptance runner's way, the alarm replay must end on its
## pinned hash and on a different one from the same text without the line.

const ALARM_REPLAY: String = "res://acceptance/replays/bot_g2_escape_alarm.replay"
## The hash m6's `music_follows_alarm` step pins (suites/m6/sound.json).
const PINNED_HASH: int = 2803663058


static func _fly(replay: Replay) -> LocalSession:
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = source.new_session()
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	return session


static func _without_alarm_line(text: String) -> String:
	var kept: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.begins_with("alarm "):
			kept.append(line)
	return "\n".join(kept)


static func _load(text: String) -> Replay:
	return Replay.from_text(text)


func test_the_replay_session_starts_with_its_own_copy_of_the_alarm() -> String:
	var replay: Replay = Replay.load_file(ALARM_REPLAY)
	if replay == null or replay.error != "" or replay.alarm_rules == null:
		return "%s did not load with an alarm line" % ALARM_REPLAY
	var session: LocalSession = ReplayInputSource.new(replay).new_session()
	var live: Alarm = session.sim.alarm
	var recorded: Alarm = session.replay.alarm_rules
	if live == null or recorded == null:
		return "alarm on the sim %s, in the session's replay %s" % [live != null, recorded != null]
	if live == replay.alarm_rules or recorded == replay.alarm_rules or live == recorded:
		return "the sim, the session's replay and the source replay must each hold their own alarm"
	if live.risk != replay.alarm_rules.risk or recorded.risk != replay.alarm_rules.risk:
		return "the alarm risk is %s on the sim and %s in the session's replay, %s in the file" % [
			live.risk, recorded.risk, replay.alarm_rules.risk]
	if session.sim.tick != 0:
		return "the alarm was set after tick %d" % session.sim.tick
	return ""


func test_the_alarm_replay_ends_on_its_pinned_hash_and_not_on_the_alarm_off_one() -> String:
	var text: String = FileAccess.get_file_as_string(ALARM_REPLAY)
	var with_alarm: Replay = _load(text)
	var without_alarm: Replay = _load(_without_alarm_line(text))
	if with_alarm.error != "" or without_alarm.error != "":
		return "the replay did not read back: '%s' / '%s'" % [with_alarm.error, without_alarm.error]
	if without_alarm.alarm_rules != null:
		return "the alarm line was not removed"
	var on_hash: int = _fly(with_alarm).sim.state_hash()
	var off_session: LocalSession = _fly(without_alarm)
	if off_session.sim.alarm != null:
		return "a replay without an alarm line gave the session an alarm"
	var off_hash: int = off_session.sim.state_hash()
	if on_hash == off_hash:
		return "with and without its alarm line the flight ends on %d" % on_hash
	if on_hash != PINNED_HASH:
		return "with its alarm the flight ends on %d, the m6 step pins %d" % [on_hash, PINNED_HASH]
	if on_hash != with_alarm.expected_hash:
		return "the flight ends on %d, the replay's hash line says %d" % [on_hash, with_alarm.expected_hash]
	var headless: Sim = with_alarm.run()
	if headless == null or headless.state_hash() != on_hash:
		return "Replay.run ends on %s, ReplayInputSource on %d" % [
			"nothing" if headless == null else str(headless.state_hash()), on_hash]
	return ""
