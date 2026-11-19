class_name InstallerProbe
extends RefCounted

## Debug-only spike for in-app updates (#130, #595, DEV-8, PLT-1): can a
## sideloaded build hand an APK to the Android package installer on Horizon OS?
## It copies the running app's own APK into app storage and opens it with the
## installer, so no download is needed; on the headset the expected result is
## Android's "update this app?" dialog. The answer decides how the update
## issues are written, so the probe only reports and changes nothing in the
## game.
##
## No plugin: the Godot Android template already declares a FileProvider with
## the authority "<package>.fileprovider" that serves the app's files
## directory. All Android work is in `InstallerProbeJava`, through
## `JavaClassWrapper`; Godot's `FileAccess` cannot read the APK (#106).

const STATUS_STARTED: String = "started"
const STATUS_UNSUPPORTED: String = "unsupported"
const STATUS_ERROR: String = "error"
const LOG_PREFIX: String = "MELTDOWN_INSTALLER_PROBE"

## Desktop or editor: `godot ... -- --installer-probe`.
const ARG: String = "--installer-probe"
## Headset: `adb shell am start ... --es meltdown_installer_probe 1`. Godot
## strips `command_line_params` from intents to exported activities, and the
## launcher alias is exported, so the probe reads its own extra instead.
const INTENT_EXTRA: String = "meltdown_installer_probe"
const OFF_VALUES: Array[String] = ["", "0", "false", "no", "off"]

const COPY_NAME: String = "meltdown_installer_probe.apk"

## Step names, the first word of each step's log line and of its error.
const STEP_SOURCE: String = "source"
const STEP_TARGET: String = "target"
const STEP_COPY: String = "copied"
const STEP_URI: String = "content URI"
const STEP_INTENT: String = "intent"


## Whether the owner asked for the probe, from the user command-line arguments
## (after `--`) or the value of the intent extra ("" when absent).
static func requested(user_args: PackedStringArray, intent_value: String) -> bool:
	if user_args.has(ARG):
		return true
	return not OFF_VALUES.has(intent_value.strip_edges().to_lower())


static func unsupported(reason: String) -> String:
	return "%s: %s" % [STATUS_UNSUPPORTED, reason]


static func error(reason: String) -> String:
	return "%s: %s" % [STATUS_ERROR, reason]


static func log_line(status: String) -> String:
	return "%s %s" % [LOG_PREFIX, status]


## The one entry point the game calls at start. Returns "" when the probe was
## not asked for (or this is not a debug build) and does nothing then;
## otherwise runs it, prints the log line and returns the status.
static func run_if_requested() -> String:
	return _run_if_requested(OS.is_debug_build(), OS.get_cmdline_user_args(), android_runtime())


## The start-up decision with its inputs passed in, so the tests exercise the
## same release-build guard the game uses. The guard comes first: a release
## build returns before reading the intent extra or touching `runtime`.
static func _run_if_requested(is_debug_build: bool, user_args: PackedStringArray, runtime: Object) -> String:
	if not is_debug_build:
		return ""
	var intent_value: String = intent_extra(runtime, INTENT_EXTRA) if runtime != null else ""
	if not requested(user_args, intent_value):
		return ""
	var status: String = run(runtime)
	print(log_line(status))
	return status


## Runs the probe with `runtime` as the AndroidRuntime singleton, or null off
## Android. Returns "started", "unsupported: <reason>" or "error: <reason>".
static func run(runtime: Object) -> String:
	if OS.get_name() != "Android":
		return unsupported("not running on Android (%s)" % OS.get_name())
	if runtime == null:
		return unsupported("the AndroidRuntime singleton is missing")
	return run_steps(InstallerProbeJava.new(runtime), func(line: String) -> void: print(line))


## The AndroidRuntime singleton, or null off Android. Public so other launch
## switches (the acceptance runner, #165) read intents the same way.
static func android_runtime() -> Object:
	# The singleton only exists in an Android build; checking the OS first
	# keeps desktop, headless and test runs away from Android classes.
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime")


## The string extra `extra_name` of the intent that started the activity, or
## "" when it is absent.
static func intent_extra(runtime: Object, extra_name: String) -> String:
	var activity: Object = runtime.call("getActivity")
	if activity == null:
		return ""
	var intent: Object = activity.call("getIntent")
	if intent == null:
		return ""
	var value: Variant = intent.call("getStringExtra", extra_name)
	return value if value is String else ""


## The probe's steps in order, each logging its own line through `emit` so one
## run on the headset shows where it stopped. Returns "started" or
## "error: <step>: <reason>". The tests drive this with a fake bridge.
static func run_steps(bridge: InstallerProbeBridge, emit: Callable) -> String:
	bridge.failure = ""
	var source: String = bridge.source_path()
	if source == "":
		return _step_error(STEP_SOURCE, bridge.failure)
	var size: int = bridge.source_size(source)
	if size < 0:
		return _step_error(STEP_SOURCE, "'%s': %s" % [source, bridge.failure])
	emit.call(log_line("%s: %s (%d bytes)" % [STEP_SOURCE, source, size]))

	bridge.failure = ""
	var dir: String = bridge.files_dir()
	if dir == "":
		return _step_error(STEP_TARGET, bridge.failure)
	var target: String = dir.path_join(COPY_NAME)
	emit.call(log_line("%s: %s" % [STEP_TARGET, target]))

	bridge.failure = ""
	var copied: int = bridge.copy(source, target)
	if copied < 0:
		return _step_error(STEP_COPY, "%s -> %s: %s" % [source, target, bridge.failure])
	emit.call(log_line("%s: %d bytes" % [STEP_COPY, copied]))
	if copied != size:
		return _step_error(STEP_COPY, "copied %d of %d bytes" % [copied, size])

	bridge.failure = ""
	var uri: String = bridge.content_uri(target)
	if uri == "":
		return _step_error(STEP_URI, bridge.failure)
	emit.call(log_line("%s: %s" % [STEP_URI, uri]))

	bridge.failure = ""
	if not bridge.start_installer():
		return _step_error(STEP_INTENT, bridge.failure)
	emit.call(log_line("%s: started" % STEP_INTENT))
	return STATUS_STARTED


static func _step_error(step: String, reason: String) -> String:
	return error("%s: %s" % [step, reason if reason != "" else "failed without a reason"])
