extends RefCounted

## The re-record hint in a level-hash failure (#576, DEV-6, ARC-2, decision
## record 0005). `MELTDOWN_RECORD_M3=1` re-records every m3 step, including the
## G2 escape whose recorder no longer reproduces its stored flight (#560), so
## the hint must name only the step that failed.

const SeedPick := preload("res://tests/m3_seed_pick.gd")
const ALL_STEPS_COMMAND: String = "MELTDOWN_RECORD_M3=1"


func _failed_level_hash(step_id: String) -> Array:
	var replay: Replay = Replay.new(0, 1)
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = step_id
	step.expected_level_hash = AcceptanceStepLevel.level_hash(replay) + 1
	return AcceptanceStateChecks.level_hash(step, replay, {})


func test_record_command_names_the_step() -> String:
	var expected: String = "MELTDOWN_RECORD_M3=bot_g2_escape godot --headless --path game -s res://tests/run_tests.gd"
	var actual: String = AcceptanceStateChecks.record_command("bot_g2_escape")
	if actual != expected:
		return "record_command gave '%s', expected '%s'" % [actual, expected]
	return ""


func test_a_level_hash_failure_names_only_its_step() -> String:
	for step_id: String in ["bot_generated_escape", "bot_generated_door_escape"]:
		var result: Array = _failed_level_hash(step_id)
		var message: String = str(result[1])
		if result[0] != AcceptanceReport.RESULT_FAIL:
			return "%s: a wrong level hash gave %s" % [step_id, result]
		if not message.contains(AcceptanceStateChecks.record_command(step_id)):
			return "%s: the failure does not name its command: %s" % [step_id, message]
		if message.contains(ALL_STEPS_COMMAND):
			return "%s: the failure still names %s: %s" % [step_id, ALL_STEPS_COMMAND, message]
	return ""


func test_a_matching_level_hash_names_no_command() -> String:
	var replay: Replay = Replay.new(0, 1)
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = "bot_generated_escape"
	step.expected_level_hash = AcceptanceStepLevel.level_hash(replay)
	var result: Array = AcceptanceStateChecks.level_hash(step, replay, {})
	if result[0] != AcceptanceReport.RESULT_PASS or str(result[1]).contains("MELTDOWN_RECORD"):
		return "a matching level hash gave %s" % [result]
	return ""


func test_the_seed_picker_uses_the_same_command() -> String:
	var actual: String = SeedPick.record_command("bot_generated_escape")
	var expected: String = AcceptanceStateChecks.record_command("bot_generated_escape")
	if actual != expected:
		return "m3_seed_pick gave '%s', the level-hash check '%s'" % [actual, expected]
	return ""
