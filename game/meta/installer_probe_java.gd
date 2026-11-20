class_name InstallerProbeJava
extends InstallerProbeBridge

## The installer probe's steps on Android, through `JavaClassWrapper` only.
## The first probe (#130) read the source APK with Godot's `FileAccess`, which
## on Android does not serve paths under `/data/app/` and so reported the APK
## missing (#106). Every step here goes through Java, which may read the app's
## own `base.apk` (#595). The content URI and the installer intent are the
## shared `AndroidInstaller` calls the in-app update uses too (#648).
##
## Only constructed on Android: wrapping Java classes elsewhere fails.

var _java: AndroidInstaller


func _init(runtime: Object) -> void:
	_java = AndroidInstaller.new(runtime)


func source_path() -> String:
	if not _java.has_activity():
		return _fail_text()
	var path: Variant = _java.activity.call("getPackageCodePath")
	if _java.threw("getPackageCodePath"):
		return _fail_text()
	if not path is String or path == "":
		failure = "getPackageCodePath gave no path"
		return ""
	return path


func source_size(path: String) -> int:
	var file: Object = _java.java_file(path)
	if file == null:
		return _fail_int()
	var exists: Variant = file.call("exists")
	if _java.threw("File.exists"):
		return _fail_int()
	if not exists:
		failure = "java.io.File says '%s' does not exist" % path
		return -1
	var readable: Variant = file.call("canRead")
	if _java.threw("File.canRead"):
		return _fail_int()
	if not readable:
		failure = "java.io.File says '%s' is not readable" % path
		return -1
	var length: Variant = file.call("length")
	if _java.threw("File.length"):
		return _fail_int()
	return int(length)


func files_dir() -> String:
	if not _java.has_activity():
		return _fail_text()
	var dir: Object = _java.activity.call("getFilesDir")
	if _java.threw("getFilesDir"):
		return _fail_text()
	if dir == null:
		failure = "getFilesDir gave nothing"
		return ""
	var path: Variant = dir.call("getAbsolutePath")
	if _java.threw("File.getAbsolutePath"):
		return _fail_text()
	return str(path)


## `Files.copy(Path, OutputStream)` copies the whole file inside Java. A read
## loop through the wrapper would not work: a `byte[]` passed from GDScript is a
## copy, so `InputStream.read(byte[])` would fill an array GDScript never sees.
func copy(source: String, target: String) -> int:
	_java.failure = ""
	var files_class: Object = _java.wrap_class("java.nio.file.Files")
	var stream_class: Object = _java.wrap_class("java.io.FileOutputStream")
	var source_file: Object = _java.java_file(source)
	if files_class == null or stream_class == null or source_file == null:
		return _fail_int()
	var source_path_object: Object = source_file.call("toPath")
	if _java.threw("File.toPath") or source_path_object == null:
		if _java.failure == "":
			_java.failure = "File.toPath gave nothing for '%s'" % source
		return _fail_int()
	var out: Object = stream_class.call("FileOutputStream", target)
	if _java.threw("new FileOutputStream") or out == null:
		if _java.failure == "":
			_java.failure = "could not open '%s' for writing" % target
		return _fail_int()
	var written: Variant = files_class.call("copy", source_path_object, out)
	var copy_failed: bool = _java.threw("Files.copy")
	var copy_failure: String = _java.failure
	out.call("close")
	if copy_failed:
		failure = copy_failure
		return -1
	if _java.threw("FileOutputStream.close"):
		return _fail_int()
	return int(written)


func content_uri(target: String) -> String:
	var uri: String = _java.content_uri(target)
	if uri == "":
		failure = _java.failure
	return uri


func start_installer() -> bool:
	if _java.start_installer():
		return true
	failure = _java.failure
	return false


func _fail_text() -> String:
	failure = _java.failure
	return ""


func _fail_int() -> int:
	failure = _java.failure
	return -1
