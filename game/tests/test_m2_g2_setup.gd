extends RefCounted

## The m2 G2 recorder and the m2 suite's G2 step build the same level (#591,
## follow-up to #578; ARC-2, DEV-6, decision record 0005): same level hash
## without the hash line, same debris. The step flies the replay's own copy of
## the level, so a replay written before a change to the level or to
## `LocalSession.for_level` would fly a different level from the one a fresh
## recording flies, and nothing else would notice.
##
## The comparison is the m3 one (`m3_g2_setup.gd`); only the recorder differs:
## `test_m2_g2_level.gd`'s `record()`.

const M2Level := preload("res://tests/test_m2_g2_level.gd")
const Setup := preload("res://tests/m3_g2_setup.gd")
const DOCTORED_REPLAY: String = "user://t591_no_debris.replay"

## One bot flight per test run; clearing G2 takes a few thousand ticks.
static var _recorded: Replay = null


## The replay the m2 recorder would write now. Its level lines are copies the
## run never moves, so they read as they did before the first tick.
static func recorder_replay() -> Replay:
	if _recorded == null:
		_recorded = M2Level.record().replay
	return _recorded


func test_recorder_and_step_build_the_same_g2_level() -> String:
	var step: Replay = Setup.step_replay(M2Level.REPLAY_PATH)
	if step.error != "":
		return step.error
	var recorder: Replay = recorder_replay()
	if Setup.debris_text(recorder) == "":
		return "the m2 recorder flew G2 without its debris; g2_level.json has some"
	var problem: String = Setup.differences(recorder, step)
	if problem != "":
		return "%s; re-record from the repository root: %s=%s godot --headless --path game -s res://tests/run_tests.gd" % [
			problem, M2Level.RECORD_SWITCH, M2Level.STEP_ID]
	return ""


## The check sees a replay without the level's debris, as the m3 one stored
## before #449 was.
func test_a_replay_missing_the_debris_is_named() -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(M2Level.REPLAY_PATH).split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line: String in lines:
		if not line.begins_with("debris "):
			kept.append(line)
	if kept.size() == lines.size():
		return "%s has no debris line to drop" % M2Level.REPLAY_PATH
	var file: FileAccess = FileAccess.open(DOCTORED_REPLAY, FileAccess.WRITE)
	if file == null:
		return "could not write %s" % DOCTORED_REPLAY
	file.store_string("\n".join(kept))
	file.close()
	var step: Replay = Setup.step_replay(DOCTORED_REPLAY)
	DirAccess.remove_absolute(DOCTORED_REPLAY)
	if step.error != "":
		return step.error
	var problem: String = Setup.differences(recorder_replay(), step)
	if not problem.contains("level hash") or not problem.contains("debris: recorder"):
		return "a replay without debris gave '%s'" % problem
	return ""
