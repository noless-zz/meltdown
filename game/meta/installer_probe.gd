class_name InstallerProbe
extends RefCounted

## Debug-only spike for in-app updates (#130, DEV-8, PLT-1): can a sideloaded
## build hand an APK to the Android package installer on Horizon OS? It copies
## the running app's own APK into app storage and opens it with the installer,
## so no download is needed; on the headset the expected result is Android's
## "update this app?" dialog. The answer decides how the update issues are
## written, so the probe only reports and changes nothing in the game.
##
## No plugin: the Godot Android template already declares a FileProvider with
## the authority "<package>.fileprovider" that serves the app's files
## directory, so `JavaClassWrapper` can build the content URI and the intent.

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
const APK_MIME: String = "application/vnd.android.package-archive"
const PROVIDER_SUFFIX: String = ".fileprovider"


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
	return _run_if_requested(OS.is_debug_build(), OS.get_cmdline_user_args(), _android_runtime())


## The start-up decision with its inputs passed in, so the tests exercise the
## same release-build guard the game uses. The guard comes first: a release
## build returns before reading the intent extra or touching `runtime`.
static func _run_if_requested(is_debug_build: bool, user_args: PackedStringArray, runtime: Object) -> String:
	if not is_debug_build:
		return ""
	var intent_value: String = _intent_extra(runtime) if runtime != null else ""
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
	return _hand_own_apk_to_installer(runtime)


static func _android_runtime() -> Object:
	# The singleton only exists in an Android build; checking the OS first
	# keeps desktop, headless and test runs away from Android classes.
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime")


static func _intent_extra(runtime: Object) -> String:
	var activity: Object = runtime.call("getActivity")
	if activity == null:
		return ""
	var intent: Object = activity.call("getIntent")
	if intent == null:
		return ""
	var value: Variant = intent.call("getStringExtra", INTENT_EXTRA)
	return value if value is String else ""


static func _hand_own_apk_to_installer(runtime: Object) -> String:
	var activity: Object = runtime.call("getActivity")
	if activity == null:
		return error("no Android activity")
	var source: String = str(activity.call("getPackageCodePath"))
	if source == "" or not FileAccess.file_exists(source):
		return error("own APK not found at '%s'" % source)
	# The files directory, not user://, because that is what the template's
	# FileProvider serves ("files-path" at "/").
	var files_dir: Object = activity.call("getFilesDir")
	if files_dir == null:
		return error("no files directory")
	var target: String = str(files_dir.call("getAbsolutePath")).path_join(COPY_NAME)
	var copied: Error = DirAccess.copy_absolute(source, target)
	if copied != OK:
		return error("copy %s -> %s failed: %s" % [source, target, error_string(copied)])

	var file_class: Object = JavaClassWrapper.wrap("java.io.File")
	var provider_class: Object = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var intent_class: Object = JavaClassWrapper.wrap("android.content.Intent")
	if file_class == null or provider_class == null or intent_class == null:
		return error("could not wrap File, FileProvider or Intent")
	var file: Object = file_class.call("File", target)
	var authority: String = str(activity.call("getPackageName")) + PROVIDER_SUFFIX
	var uri: Object = provider_class.call("getUriForFile", activity, authority, file)
	var failure: String = _java_failure("FileProvider.getUriForFile")
	if failure != "":
		return failure
	if uri == null:
		return error("FileProvider gave no URI for %s" % target)
	var intent: Object = intent_class.call("Intent")
	intent.call("setAction", intent_class.get("ACTION_VIEW"))
	intent.call("setDataAndType", uri, APK_MIME)
	var flags: int = int(intent_class.get("FLAG_GRANT_READ_URI_PERMISSION")) \
			| int(intent_class.get("FLAG_ACTIVITY_NEW_TASK"))
	intent.call("addFlags", flags)
	activity.call("startActivity", intent)
	failure = _java_failure("startActivity")
	if failure != "":
		return failure
	return STATUS_STARTED


## An "error: ..." status when the last Java call threw, otherwise "".
static func _java_failure(step: String) -> String:
	var exception: Object = JavaClassWrapper.get_exception()
	if exception == null:
		return ""
	return error("%s threw %s" % [step, str(exception.call("toString"))])
