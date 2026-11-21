extends RefCounted

## The quit-after-N-frames switch used by the XR smoke test in CI
## (issue #26, PLT-2). It must stay off unless asked for, because the same
## `main.gd` runs on the headset.


func test_switch_is_off_without_the_flag() -> String:
	var cases: Array[PackedStringArray] = [
		PackedStringArray(),
		PackedStringArray(["--server"]),
		PackedStringArray(["--xr-smoke-frames"]),
		PackedStringArray(["--xr-smoke-frames="]),
		PackedStringArray(["--xr-smoke-frames=0"]),
		PackedStringArray(["--xr-smoke-frames=-5"]),
		PackedStringArray(["--xr-smoke-frames=ten"]),
		PackedStringArray(["--xr-smoke-frames=1.5"]),
		PackedStringArray(["xr-smoke-frames=30"]),
	]
	for args: PackedStringArray in cases:
		var frames: int = XrSmokeProbe.frames_from_args(args)
		if frames != 0:
			return "args %s gave %d frames, expected 0" % [str(args), frames]
		if XrSmokeProbe.new(frames).is_enabled():
			return "probe is enabled for args %s" % str(args)
	return ""


func test_flag_gives_the_frame_count() -> String:
	var frames: int = XrSmokeProbe.frames_from_args(PackedStringArray(["--other", "--xr-smoke-frames=120"]))
	if frames != 120:
		return "expected 120 frames, got %d" % frames
	return ""


func test_disabled_probe_never_asks_to_quit() -> String:
	var probe: XrSmokeProbe = XrSmokeProbe.new()
	for i: int in range(1000):
		if probe.tick():
			return "disabled probe asked to quit on tick %d" % (i + 1)
	if probe.frames_seen() != 0:
		return "disabled probe counted %d frames" % probe.frames_seen()
	return ""


func test_probe_asks_to_quit_once_on_frame_n() -> String:
	var probe: XrSmokeProbe = XrSmokeProbe.new(3)
	var results: Array[bool] = []
	for i: int in range(6):
		results.append(probe.tick())
	var expected: Array[bool] = [false, false, true, false, false, false]
	if results != expected:
		return "tick results were %s, expected %s" % [str(results), str(expected)]
	if probe.frames_seen() != 3:
		return "counted %d frames, expected 3" % probe.frames_seen()
	return ""


func test_line_is_prefixed_json_on_one_line() -> String:
	var line: String = XrSmokeProbe.format_line(true, "Monado(XRT)", 2, 90.0, 120)
	if not line.begins_with(XrSmokeProbe.LINE_PREFIX):
		return "line does not start with the prefix: %s" % line
	if line.contains("\n"):
		return "line spans more than one line"
	var parsed: Variant = JSON.parse_string(line.substr(XrSmokeProbe.LINE_PREFIX.length()))
	if not parsed is Dictionary:
		return "payload is not a JSON object: %s" % line
	var report: Dictionary = parsed
	if report.get("session") != true or report.get("runtime") != "Monado(XRT)":
		return "session or runtime wrong: %s" % line
	if int(report.get("views", -1)) != 2 or int(report.get("frames", -1)) != 120:
		return "views or frames wrong: %s" % line
	if not is_equal_approx(float(report.get("refresh_rate", -1.0)), 90.0):
		return "refresh rate wrong: %s" % line
	return ""


func test_main_scene_quits_only_through_an_enabled_probe() -> String:
	# The main scene now processes every frame to fly the ship (#60), so the
	# guard is no longer `set_process`: quitting must stay behind the probe,
	# and a probe nobody enabled must never ask to quit.
	var source: String = FileAccess.get_file_as_string("res://main.gd")
	if not source.contains("_smoke_probe.tick():"):
		return "main.gd no longer ties quitting to the smoke probe"
	if source.count("get_tree().quit()") != 1:
		return "main.gd quits somewhere other than behind the probe"
	var probe: XrSmokeProbe = XrSmokeProbe.new(0)
	for i: int in 1000:
		if probe.tick():
			return "a disabled probe asked to quit on frame %d" % i
	return ""


func test_line_reports_both_hands() -> String:
	var line: String = XrSmokeProbe.format_line(true, "Monado(XRT)", 2, 20.0, 120, true, false)
	var report: Dictionary = JSON.parse_string(line.substr(XrSmokeProbe.LINE_PREFIX.length()))
	if report.get("left_tracked") != true or report.get("right_tracked") != false:
		return "hand flags wrong: %s" % line
	var keys: Array = report.keys()
	keys.sort()
	var expected: Array = ["frames", "left_tracked", "refresh_rate", "right_tracked", "runtime", "session", "views"]
	if keys != expected:
		return "keys were %s, expected %s" % [str(keys), str(expected)]
	return ""


func test_line_without_hands_says_untracked() -> String:
	var line: String = XrSmokeProbe.format_line(true, "Monado(XRT)", 2, 20.0, 120)
	var report: Dictionary = JSON.parse_string(line.substr(XrSmokeProbe.LINE_PREFIX.length()))
	if report.get("left_tracked") != false or report.get("right_tracked") != false:
		return "a caller that never watched the hands claimed tracking: %s" % line
	if report.get("session") != true or int(report.get("views", -1)) != 2:
		return "existing keys changed: %s" % line
	return ""


func test_existing_keys_keep_their_order() -> String:
	# The script and earlier logs read the line as it was; new keys must not
	# move the old ones relative to each other.
	var line: String = XrSmokeProbe.format_line(true, "R", 2, 20.0, 120, true, true)
	var order: Array[String] = ["\"frames\"", "\"refresh_rate\"", "\"runtime\"", "\"session\"", "\"views\""]
	var last: int = -1
	for key: String in order:
		var at: int = line.find(key)
		if at <= last:
			return "key %s out of order in %s" % [key, line]
		last = at
	return ""


func test_a_hand_stays_tracked_once_seen() -> String:
	var probe: XrSmokeProbe = XrSmokeProbe.new(10)
	probe.note_hands(false, false)
	if probe.left_tracked() or probe.right_tracked():
		return "a hand counted as tracked without a pose"
	probe.note_hands(true, false)
	probe.note_hands(false, true)
	probe.note_hands(false, false)
	if not probe.left_tracked() or not probe.right_tracked():
		return "a hand that reported a pose was forgotten: left %s right %s" % [
			probe.left_tracked(), probe.right_tracked()]
	return ""


func test_disabled_probe_ignores_hands() -> String:
	var probe: XrSmokeProbe = XrSmokeProbe.new(0)
	probe.note_hands(true, true)
	if probe.left_tracked() or probe.right_tracked():
		return "a disabled probe recorded hand tracking"
	return ""


func test_missing_controller_nodes_count_as_untracked() -> String:
	var probe: XrSmokeProbe = XrSmokeProbe.new(5)
	probe.watch_hands(null, null)
	if probe.left_tracked() or probe.right_tracked():
		return "missing controller nodes counted as tracked"
	var left: XRController3D = XRController3D.new()
	var right: XRController3D = XRController3D.new()
	probe.watch_hands(left, right)
	left.free()
	right.free()
	if probe.left_tracked() or probe.right_tracked():
		return "controllers without a tracker counted as tracked"
	return ""


func test_main_scene_watches_both_hands_for_the_probe() -> String:
	var source: String = FileAccess.get_file_as_string("res://main.gd")
	if not source.contains("_smoke_probe.watch_hands(boost_haptics.left_controller, boost_haptics.right_controller)"):
		return "main.gd does not pass both controller nodes to the smoke probe"
	return ""


func test_progress_lines_mark_the_first_frame_and_every_thirtieth() -> String:
	var printed: Array[int] = []
	for frame: int in range(-1, 125):
		if not XrSmokeProbe.progress_line(frame, 0).is_empty():
			printed.append(frame)
	var expected: Array[int] = [1, 30, 60, 90, 120]
	if printed != expected:
		return "progress lines on frames %s, expected %s" % [str(printed), str(expected)]
	return ""


func test_first_frame_line_is_what_the_smoke_script_looks_for() -> String:
	# tools/xr_smoke.sh times start-up by matching this exact start (#727).
	var line: String = XrSmokeProbe.progress_line(1, 4321)
	if not line.begins_with('MELTDOWN_XR_SMOKE_FRAME {"frame":1,'):
		return "first frame line was %s" % line
	if line.begins_with(XrSmokeProbe.LINE_PREFIX):
		return "progress line would be read as the result line: %s" % line
	var parsed: Variant = JSON.parse_string(line.substr(XrSmokeProbe.FRAME_PREFIX.length()))
	if not parsed is Dictionary or int((parsed as Dictionary).get("msec", -1)) != 4321:
		return "progress line does not carry the engine clock: %s" % line
	return ""
