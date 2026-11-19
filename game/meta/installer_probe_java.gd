class_name InstallerProbeJava
extends InstallerProbeBridge

## The installer probe's steps on Android, through `JavaClassWrapper` only.
## The first probe (#130) read the source APK with Godot's `FileAccess`, which
## on Android does not serve paths under `/data/app/` and so reported the APK
## missing (#106). Every step here goes through Java, which may read the app's
## own `base.apk` (#595).
##
## Only constructed on Android: wrapping Java classes elsewhere fails.

const APK_MIME: String = "application/vnd.android.package-archive"
const PROVIDER_SUFFIX: String = ".fileprovider"

var _activity: Object = null
var _uri: Object = null


func _init(runtime: Object) -> void:
	if runtime != null:
		_activity = runtime.call("getActivity")


func source_path() -> String:
	if not _has_activity():
		return ""
	var path: Variant = _activity.call("getPackageCodePath")
	if _threw("getPackageCodePath"):
		return ""
	if not path is String or path == "":
		failure = "getPackageCodePath gave no path"
		return ""
	return path


func source_size(path: String) -> int:
	var file: Object = _file(path)
	if file == null:
		return -1
	var exists: Variant = file.call("exists")
	if _threw("File.exists"):
		return -1
	if not exists:
		failure = "java.io.File says '%s' does not exist" % path
		return -1
	var readable: Variant = file.call("canRead")
	if _threw("File.canRead"):
		return -1
	if not readable:
		failure = "java.io.File says '%s' is not readable" % path
		return -1
	var length: Variant = file.call("length")
	if _threw("File.length"):
		return -1
	return int(length)


func files_dir() -> String:
	if not _has_activity():
		return ""
	var dir: Object = _activity.call("getFilesDir")
	if _threw("getFilesDir"):
		return ""
	if dir == null:
		failure = "getFilesDir gave nothing"
		return ""
	var path: Variant = dir.call("getAbsolutePath")
	if _threw("File.getAbsolutePath"):
		return ""
	return str(path)


## `Files.copy(Path, OutputStream)` copies the whole file inside Java. A read
## loop through the wrapper would not work: a `byte[]` passed from GDScript is a
## copy, so `InputStream.read(byte[])` would fill an array GDScript never sees.
func copy(source: String, target: String) -> int:
	var files_class: Object = _wrap("java.nio.file.Files")
	var stream_class: Object = _wrap("java.io.FileOutputStream")
	var source_file: Object = _file(source)
	if files_class == null or stream_class == null or source_file == null:
		return -1
	var source_path_object: Object = source_file.call("toPath")
	if _threw("File.toPath") or source_path_object == null:
		if failure == "":
			failure = "File.toPath gave nothing for '%s'" % source
		return -1
	var out: Object = stream_class.call("FileOutputStream", target)
	if _threw("new FileOutputStream") or out == null:
		if failure == "":
			failure = "could not open '%s' for writing" % target
		return -1
	var written: Variant = files_class.call("copy", source_path_object, out)
	var copy_failed: bool = _threw("Files.copy")
	var copy_failure: String = failure
	out.call("close")
	if copy_failed:
		failure = copy_failure
		return -1
	if _threw("FileOutputStream.close"):
		return -1
	return int(written)


func content_uri(target: String) -> String:
	if not _has_activity():
		return ""
	var provider_class: Object = _wrap("androidx.core.content.FileProvider")
	var file: Object = _file(target)
	if provider_class == null or file == null:
		return ""
	# The Godot Android template declares this FileProvider, serving the
	# files directory ("files-path" at "/").
	var authority: String = str(_activity.call("getPackageName")) + PROVIDER_SUFFIX
	_uri = provider_class.call("getUriForFile", _activity, authority, file)
	if _threw("FileProvider.getUriForFile"):
		return ""
	if _uri == null:
		failure = "FileProvider gave no URI for '%s'" % target
		return ""
	var text: Variant = _uri.call("toString")
	return str(text) if not _threw("Uri.toString") else ""


func start_installer() -> bool:
	if not _has_activity():
		return false
	if _uri == null:
		failure = "no content URI built"
		return false
	var intent_class: Object = _wrap("android.content.Intent")
	if intent_class == null:
		return false
	var intent: Object = intent_class.call("Intent")
	if _threw("new Intent") or intent == null:
		return false
	intent.call("setAction", intent_class.get("ACTION_VIEW"))
	intent.call("setDataAndType", _uri, APK_MIME)
	var flags: int = int(intent_class.get("FLAG_GRANT_READ_URI_PERMISSION")) \
			| int(intent_class.get("FLAG_ACTIVITY_NEW_TASK"))
	intent.call("addFlags", flags)
	if _threw("building the intent"):
		return false
	_activity.call("startActivity", intent)
	return not _threw("startActivity")


func _has_activity() -> bool:
	if _activity == null:
		failure = "no Android activity"
		return false
	return true


func _wrap(class_path: String) -> Object:
	var wrapped: Object = JavaClassWrapper.wrap(class_path)
	if wrapped == null:
		failure = "could not wrap %s" % class_path
	return wrapped


func _file(path: String) -> Object:
	var file_class: Object = _wrap("java.io.File")
	if file_class == null:
		return null
	var file: Object = file_class.call("File", path)
	if _threw("new File('%s')" % path):
		return null
	return file


## Whether the last Java call threw; when it did, `failure` names the call and
## the exception's own text, so the log shows exactly what Java said.
func _threw(call_name: String) -> bool:
	var exception: Object = JavaClassWrapper.get_exception()
	if exception == null:
		return false
	failure = "%s threw %s" % [call_name, str(exception.call("toString"))]
	return true
