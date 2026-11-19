extends RefCounted

## The second installer probe (#595): the steps run in order, each logs its own
## line, a failure stops the run and names its step and the Java exception, and
## nothing reads the source APK through Godot's file access.

const ORDER: Array[String] = [
	"source_path", "source_size", "files_dir", "copy", "content_uri", "start_installer",
]

var _lines: Array[String] = []


func _run(bridge: InstallerProbeBridge) -> String:
	_lines.clear()
	return InstallerProbe.run_steps(bridge, func(line: String) -> void: _lines.append(line))


func test_all_steps_run_in_order_and_start_the_installer() -> String:
	var bridge: FakeInstallerProbeBridge = FakeInstallerProbeBridge.new()
	var status: String = _run(bridge)
	if status != InstallerProbe.STATUS_STARTED:
		return "expected started, got '%s'" % status
	if bridge.calls != ORDER:
		return "calls %s, expected %s" % [bridge.calls, ORDER]
	return ""


func test_one_log_line_per_step() -> String:
	_run(FakeInstallerProbeBridge.new())
	var expected: Array[String] = [
		"MELTDOWN_INSTALLER_PROBE source: /data/app/~~x==/io.example-y==/base.apk (1234 bytes)",
		"MELTDOWN_INSTALLER_PROBE target: /data/user/0/io.example/files/meltdown_installer_probe.apk",
		"MELTDOWN_INSTALLER_PROBE copied: 1234 bytes",
		"MELTDOWN_INSTALLER_PROBE content URI: content://io.example.fileprovider/root/meltdown_installer_probe.apk",
		"MELTDOWN_INSTALLER_PROBE intent: started",
	]
	if _lines != expected:
		return "log lines %s, expected %s" % [_lines, expected]
	return ""


## Each failing step stops the run there, logs nothing for itself or later
## steps, and returns its step name with the bridge's exact reason.
func test_a_failing_step_stops_the_run_and_names_itself() -> String:
	var cases: Dictionary[String, Array] = {
		"source_path": [InstallerProbe.STEP_SOURCE, 0],
		"source_size": [InstallerProbe.STEP_SOURCE, 0],
		"files_dir": [InstallerProbe.STEP_TARGET, 1],
		"copy": [InstallerProbe.STEP_COPY, 2],
		"content_uri": [InstallerProbe.STEP_URI, 3],
		"start_installer": [InstallerProbe.STEP_INTENT, 4],
	}
	for fail_at: String in cases:
		var bridge: FakeInstallerProbeBridge = FakeInstallerProbeBridge.new()
		bridge.fail_at = fail_at
		bridge.fail_reason = "java.lang.SecurityException: %s denied" % fail_at
		var status: String = _run(bridge)
		var step: String = cases[fail_at][0]
		var lines_before: int = cases[fail_at][1]
		if not status.begins_with("error: %s: " % step):
			return "%s: expected an error naming '%s', got '%s'" % [fail_at, step, status]
		if not status.contains(bridge.fail_reason):
			return "%s: the Java exception is missing from '%s'" % [fail_at, status]
		if bridge.calls.back() != fail_at:
			return "%s: steps ran after the failure: %s" % [fail_at, bridge.calls]
		if _lines.size() != lines_before:
			return "%s: %d log lines before the failure, expected %d" % [fail_at, _lines.size(), lines_before]
	return ""


## The first probe stopped here on the headset (#106): the source path must
## appear in the error so the log shows which file Java could not read.
func test_unreadable_source_names_the_path() -> String:
	var bridge: FakeInstallerProbeBridge = FakeInstallerProbeBridge.new()
	bridge.fail_at = "source_size"
	var status: String = _run(bridge)
	if not status.contains("/base.apk"):
		return "the source path is missing from '%s'" % status
	return ""


func test_a_short_copy_is_an_error() -> String:
	var bridge: FakeInstallerProbeBridge = FakeInstallerProbeBridge.new()
	bridge.copied = 1000
	var status: String = _run(bridge)
	if status != "error: copied: copied 1000 of 1234 bytes":
		return "unexpected status for a short copy: '%s'" % status
	if bridge.calls.has("content_uri"):
		return "built a content URI after a short copy"
	return ""


func test_a_failure_without_a_reason_still_says_so() -> String:
	var bridge: FakeInstallerProbeBridge = FakeInstallerProbeBridge.new()
	bridge.fail_at = "files_dir"
	bridge.fail_reason = ""
	var status: String = _run(bridge)
	if status != "error: target: failed without a reason":
		return "unexpected status '%s'" % status
	return ""


## The base bridge fails every step, so an unfinished bridge can never report
## that the installer started.
func test_base_bridge_never_starts() -> String:
	var status: String = _run(InstallerProbeBridge.new())
	if not status.begins_with("error: source: "):
		return "the base bridge got past the first step: '%s'" % status
	return ""


## Godot's file access cannot see `/data/app/` on Android (#106), so neither
## the probe nor its Java bridge may use it.
func test_no_godot_file_access_on_the_probe_path() -> String:
	for path: String in ["res://meta/installer_probe.gd", "res://meta/installer_probe_java.gd"]:
		var source: String = (load(path) as GDScript).source_code
		for banned: String in ["FileAccess.", "DirAccess."]:
			if source.contains(banned):
				return "%s uses %s" % [path, banned]
	return ""
