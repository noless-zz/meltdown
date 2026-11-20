class_name AndroidInstaller
extends UpdateInstallBridge

## The package installer hand-off on Android, through `JavaClassWrapper` only.
## The path is the one the installer probe proved on the Quest 3 (#595): a
## FileProvider content URI for a file in the app's files directory and an
## `ACTION_VIEW` intent. The probe (`InstallerProbeJava`) and the in-app update
## (`UpdateInstall`, #648) both use this class, so the proven calls exist once.
##
## Only constructed on Android: wrapping Java classes elsewhere fails.

const APK_MIME: String = "application/vnd.android.package-archive"
const PROVIDER_SUFFIX: String = ".fileprovider"

var activity: Object = null
var _uri: Object = null


func _init(runtime: Object) -> void:
	if runtime != null:
		activity = runtime.call("getActivity")


func may_install() -> int:
	if not has_activity():
		return UNKNOWN
	var manager: Object = activity.call("getPackageManager")
	if threw("getPackageManager"):
		return UNKNOWN
	if manager == null:
		failure = "getPackageManager gave nothing"
		return UNKNOWN
	var allowed: Variant = manager.call("canRequestPackageInstalls")
	if threw("canRequestPackageInstalls"):
		return UNKNOWN
	return ALLOWED if allowed else NOT_ALLOWED


func ask_install_permission() -> bool:
	if not has_activity():
		return false
	var package: String = package_name()
	if package == "":
		return false
	var settings_class: Object = wrap_class("android.provider.Settings")
	var uri_class: Object = wrap_class("android.net.Uri")
	var intent_class: Object = wrap_class("android.content.Intent")
	if settings_class == null or uri_class == null or intent_class == null:
		return false
	var package_uri: Object = uri_class.call("parse", "package:" + package)
	if threw("Uri.parse") or package_uri == null:
		if failure == "":
			failure = "Uri.parse gave nothing"
		return false
	var intent: Object = intent_class.call("Intent")
	if threw("new Intent") or intent == null:
		return false
	intent.call("setAction", settings_class.get("ACTION_MANAGE_UNKNOWN_APP_SOURCES"))
	intent.call("setData", package_uri)
	intent.call("addFlags", int(intent_class.get("FLAG_ACTIVITY_NEW_TASK")))
	if threw("building the settings intent"):
		return false
	activity.call("startActivity", intent)
	return not threw("startActivity")


func content_uri(target: String) -> String:
	if not has_activity():
		return ""
	var package: String = package_name()
	if package == "":
		return ""
	var provider_class: Object = wrap_class("androidx.core.content.FileProvider")
	var file: Object = java_file(target)
	if provider_class == null or file == null:
		return ""
	# The Godot Android template declares this FileProvider, serving the
	# files directory ("files-path" at "/").
	var authority: String = package + PROVIDER_SUFFIX
	_uri = provider_class.call("getUriForFile", activity, authority, file)
	if threw("FileProvider.getUriForFile"):
		return ""
	if _uri == null:
		failure = "FileProvider gave no URI for '%s'" % target
		return ""
	var text: Variant = _uri.call("toString")
	return str(text) if not threw("Uri.toString") else ""


func start_installer() -> bool:
	if not has_activity():
		return false
	if _uri == null:
		failure = "no content URI built"
		return false
	var intent_class: Object = wrap_class("android.content.Intent")
	if intent_class == null:
		return false
	var intent: Object = intent_class.call("Intent")
	if threw("new Intent") or intent == null:
		return false
	intent.call("setAction", intent_class.get("ACTION_VIEW"))
	intent.call("setDataAndType", _uri, APK_MIME)
	var flags: int = int(intent_class.get("FLAG_GRANT_READ_URI_PERMISSION")) \
			| int(intent_class.get("FLAG_ACTIVITY_NEW_TASK"))
	intent.call("addFlags", flags)
	if threw("building the intent"):
		return false
	activity.call("startActivity", intent)
	return not threw("startActivity")


func has_activity() -> bool:
	if activity == null:
		failure = "no Android activity"
		return false
	return true


## This app's package name, or "" with `failure` naming `getPackageName` when
## the call threw or gave nothing. Asked before anything else is wrapped, so a
## failure here is never reported under a later call (#719).
func package_name() -> String:
	var answer: Variant = activity.call("getPackageName")
	if threw("getPackageName"):
		return ""
	var text: String = str(answer) if answer != null else ""
	if text == "":
		failure = "getPackageName gave nothing"
	return text


func wrap_class(class_path: String) -> Object:
	var wrapped: Object = JavaClassWrapper.wrap(class_path)
	if wrapped == null:
		failure = "could not wrap %s" % class_path
	return wrapped


func java_file(path: String) -> Object:
	var file_class: Object = wrap_class("java.io.File")
	if file_class == null:
		return null
	var file: Object = file_class.call("File", path)
	if threw("new File('%s')" % path):
		return null
	return file


## Whether the last Java call threw; when it did, `failure` names the call and
## the exception's own text, so the log shows exactly what Java said.
func threw(call_name: String) -> bool:
	var exception: Object = pending_exception()
	if exception == null:
		return false
	failure = "%s threw %s" % [call_name, str(exception.call("toString"))]
	return true


## The exception the last Java call left, or null. Its own method so the tests
## can stand in for Java off Android.
func pending_exception() -> Object:
	return JavaClassWrapper.get_exception()
