class_name FakeInstallerProbeBridge
extends InstallerProbeBridge

## Stands in for Android in the installer probe tests: records the order of
## the calls and fails the step named in `fail_at` with `fail_reason`.

var fail_at: String = ""
var fail_reason: String = "java.io.IOException: boom"
var size: int = 1234
var copied: int = 1234
var calls: Array[String] = []


func source_path() -> String:
	return _step("source_path", "/data/app/~~x==/io.example-y==/base.apk")


func source_size(_path: String) -> int:
	calls.append("source_size")
	if fail_at == "source_size":
		failure = fail_reason
		return -1
	return size


func files_dir() -> String:
	return _step("files_dir", "/data/user/0/io.example/files")


func copy(_source: String, _target: String) -> int:
	calls.append("copy")
	if fail_at == "copy":
		failure = fail_reason
		return -1
	return copied


func content_uri(_target: String) -> String:
	return _step("content_uri", "content://io.example.fileprovider/root/meltdown_installer_probe.apk")


func start_installer() -> bool:
	return _step("start_installer", "ok") != ""


func _step(step: String, value: String) -> String:
	calls.append(step)
	if fail_at == step:
		failure = fail_reason
		return ""
	return value
