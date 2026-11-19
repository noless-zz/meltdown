extends RefCounted

## The m3 G2 escape recorder and the suite step build the same level (#578,
## ARC-2, DEV-6, decision record 0005): same level hash, same debris. Without
## this a re-recording could silently change what the step tests.

const Setup := preload("res://tests/m3_g2_setup.gd")
const DOCTORED_REPLAY: String = "user://t578_no_debris.replay"


func test_recorder_and_step_build_the_same_g2_level() -> String:
	var step: Replay = Setup.step_replay()
	if step.error != "":
		return step.error
	var recorder: Replay = Setup.recorder_replay()
	if Setup.debris_text(recorder) == "":
		return "the recorder flew G2 without its debris; g2_level.json has some"
	var problem: String = Setup.differences(recorder, step)
	if problem != "":
		return "%s; re-record: %s" % [problem, AcceptanceStateChecks.record_command(Setup.STEP_ID)]
	return ""


## The check sees a replay without the level's debris, as the one stored
## before #449 was.
func test_a_replay_missing_the_debris_is_named() -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(Setup.REPLAY_PATH).split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line: String in lines:
		if not line.begins_with("debris "):
			kept.append(line)
	if kept.size() == lines.size():
		return "%s has no debris line to drop" % Setup.REPLAY_PATH
	var file: FileAccess = FileAccess.open(DOCTORED_REPLAY, FileAccess.WRITE)
	if file == null:
		return "could not write %s" % DOCTORED_REPLAY
	file.store_string("\n".join(kept))
	file.close()
	var step: Replay = Setup.step_replay(DOCTORED_REPLAY)
	DirAccess.remove_absolute(DOCTORED_REPLAY)
	if step.error != "":
		return step.error
	var problem: String = Setup.differences(Setup.recorder_replay(), step)
	if not problem.contains("level hash") or not problem.contains("debris: recorder"):
		return "a replay without debris gave '%s'" % problem
	return ""
