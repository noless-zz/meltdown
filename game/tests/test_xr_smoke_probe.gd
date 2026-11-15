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
