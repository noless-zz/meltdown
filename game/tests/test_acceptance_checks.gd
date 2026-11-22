extends RefCounted

## The acceptance check dispatch (#817, DEV-6): every check a suite may name is
## judged somewhere, so a new check cannot be added to `AcceptanceStep` without
## a judge, and a name that is not known is still answered "unknown check".


func _runner() -> AcceptanceRunner:
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	return runner


func _missing(names: Array[String], from: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for name: String in names:
		if not from.has(name):
			missing.append(name)
	return missing


func test_every_known_check_has_a_judge() -> String:
	var judged: Array[String] = AcceptanceChecks.new().judged_checks()
	var known: Array[String] = AcceptanceCheckFiles.known_checks()  # Check files' too (#1297).
	var missing: Array[String] = _missing(known, judged)
	if not missing.is_empty():
		return "known checks without a judge: %s" % ", ".join(missing)
	var stray: Array[String] = _missing(judged, known)
	if not stray.is_empty():
		return "judged checks that are not known: %s" % ", ".join(stray)
	return ""


func test_no_check_is_judged_twice() -> String:
	var judged: Array[String] = AcceptanceChecks.new().judged_checks()
	for name: String in judged:
		if judged.count(name) != 1:
			return "%s is judged %d times" % [name, judged.count(name)]
	return ""


func test_unknown_name_is_answered_unknown_check() -> String:
	var runner: AcceptanceRunner = _runner()
	var measurements: Dictionary = {}
	var result: Array = AcceptanceChecks.new().run("robot_cleared", AcceptanceStep.new(), runner, measurements)
	runner.free()
	if result != [AcceptanceReport.RESULT_FAIL, AcceptanceChecks.UNKNOWN_CHECK]:
		return "a name that is not a check: got %s" % str(result)
	if not measurements.is_empty():
		return "an unknown check measured %s" % str(measurements)
	return ""


func test_known_check_is_not_answered_unknown() -> String:
	# Off the headset with no OpenXR runtime the xr_session check is skipped, not unknown.
	var runner: AcceptanceRunner = _runner()
	var step: AcceptanceStep = AcceptanceStep.new()
	step.checks.append(AcceptanceStep.CHECK_XR_SESSION)
	var result: Array = AcceptanceChecks.new().run(AcceptanceStep.CHECK_XR_SESSION, step, runner, {})
	runner.free()
	if result.size() != 2 or str(result[1]) == AcceptanceChecks.UNKNOWN_CHECK:
		return "xr_session: got %s" % str(result)
	if result[0] != AcceptanceReport.RESULT_SKIPPED:
		return "xr_session without a runtime: expected %s, got %s" % [AcceptanceReport.RESULT_SKIPPED, str(result)]
	return ""


func test_unsampled_comfort_check_fails_not_sampled() -> String:
	var runner: AcceptanceRunner = _runner()
	var result: Array = AcceptanceChecks.new().run(AcceptanceStep.CHECK_COMFORT_MOTION, AcceptanceStep.new(), runner, {})
	runner.free()
	if result != [AcceptanceReport.RESULT_FAIL, "not sampled"]:
		return "comfort_motion with no sampler: got %s" % str(result)
	return ""


func test_runner_and_suite_files_stay_short() -> String:
	var limits: Dictionary[String, int] = {
		"res://acceptance/acceptance_runner.gd": 260,
		"res://acceptance/acceptance_suite.gd": 280,
	}
	for path: String in limits:
		var lines: int = FileAccess.get_file_as_string(path).split("\n").size()
		if lines >= limits[path]:
			return "%s has %d lines, the limit is under %d" % [path, lines, limits[path]]
	return ""
