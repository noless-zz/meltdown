class_name FakeUpdateInstallBridge
extends UpdateInstallBridge

## Stands in for Android in the update install tests: records the order of the
## calls, answers the permission check with `allowed` and fails the step named
## in `fail_at` with `fail_reason`.

var allowed: int = UpdateInstallBridge.ALLOWED
var fail_at: String = ""
var fail_reason: String = "android.content.ActivityNotFoundException: no installer"
var calls: Array[String] = []
var uri_targets: Array[String] = []


func may_install() -> int:
	calls.append("may_install")
	if allowed == UpdateInstallBridge.UNKNOWN:
		failure = "java.lang.SecurityException: no package manager"
	return allowed


func ask_install_permission() -> bool:
	return _step("ask_install_permission")


func content_uri(target: String) -> String:
	uri_targets.append(target)
	return "content://io.example.fileprovider/root/meltdown_update.apk" if _step("content_uri") else ""


func start_installer() -> bool:
	return _step("start_installer")


func _step(step: String) -> bool:
	calls.append(step)
	if fail_at == step:
		failure = fail_reason
		return false
	return true
