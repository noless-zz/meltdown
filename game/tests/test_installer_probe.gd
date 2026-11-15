extends RefCounted

## The installer spike (#130) must stay out of normal play and release builds,
## and must not reach for Android classes off Android.


func test_not_requested_without_argument_or_extra() -> String:
	if InstallerProbe.requested(PackedStringArray(), ""):
		return "requested with no argument and no intent extra"
	if InstallerProbe.requested(PackedStringArray(["--comfort-preset=2"]), ""):
		return "requested by an unrelated argument"
	return ""


func test_requested_by_command_line_argument() -> String:
	if not InstallerProbe.requested(PackedStringArray(["--installer-probe"]), ""):
		return "--installer-probe did not request the probe"
	if InstallerProbe.requested(PackedStringArray(["--installer-probe-x"]), ""):
		return "a longer argument requested the probe"
	return ""


func test_intent_extra_values() -> String:
	for value: String in ["1", "true", "yes", " 1 "]:
		if not InstallerProbe.requested(PackedStringArray(), value):
			return "intent extra '%s' did not request the probe" % value
	for value: String in ["", "0", "false", "FALSE", "off", "no", "  "]:
		if InstallerProbe.requested(PackedStringArray(), value):
			return "intent extra '%s' requested the probe" % value
	return ""


func test_never_runs_in_a_release_build() -> String:
	if InstallerProbe.should_run(false, PackedStringArray(["--installer-probe"]), "1"):
		return "would run in a release build"
	if not InstallerProbe.should_run(true, PackedStringArray(["--installer-probe"]), ""):
		return "would not run in a debug build when asked"
	if InstallerProbe.should_run(true, PackedStringArray(), ""):
		return "would run in a debug build without being asked"
	return ""


## Tests run headless on Linux, so this is the desktop path: no AndroidRuntime,
## no JavaClassWrapper call, just a reason.
func test_unsupported_off_android() -> String:
	var status: String = InstallerProbe.run(null)
	if not status.begins_with(InstallerProbe.STATUS_UNSUPPORTED + ": "):
		return "expected unsupported with a reason, got '%s'" % status
	if not status.contains(OS.get_name()):
		return "reason does not name the platform: '%s'" % status
	return ""


## Off Android the start-up call must be silent unless asked: the test run
## passes no `--installer-probe`, so it returns "" and logs nothing.
func test_start_up_call_is_silent_when_not_asked() -> String:
	if OS.get_cmdline_user_args().has(InstallerProbe.ARG):
		return ""
	var status: String = InstallerProbe.run_if_requested()
	if status != "":
		return "ran without being asked: '%s'" % status
	return ""


func test_log_line_format() -> String:
	var line: String = InstallerProbe.log_line(InstallerProbe.unsupported("x"))
	if line != "MELTDOWN_INSTALLER_PROBE unsupported: x":
		return "unexpected log line '%s'" % line
	if InstallerProbe.log_line(InstallerProbe.STATUS_STARTED) != "MELTDOWN_INSTALLER_PROBE started":
		return "unexpected started line"
	if not InstallerProbe.error("y").begins_with("error: "):
		return "error status lacks its prefix"
	return ""
