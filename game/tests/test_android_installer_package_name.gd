extends RefCounted

## A failed `getPackageName` is reported under its own name (#719, DEV-8,
## PLT-1): the permission request and the content URI both stop there with a
## reason naming it, and `UpdateInstall` shows that reason in its usual retry
## line. A fake activity and fake exception stand in for Java.

const DIR: String = "user://test_android_installer_package_name"
const THREW: String = "getPackageName threw java.lang.SecurityException: package hidden"


static func _installer(package: String, throws: bool, allowed: bool = true) -> FakeAndroidInstaller:
	var activity: FakeJavaActivity = FakeJavaActivity.new()
	activity.package = package
	activity.allowed = allowed
	var installer: FakeAndroidInstaller = FakeAndroidInstaller.new(activity)
	installer.throw_on = "getPackageName" if throws else ""
	return installer


static func _update(installer: FakeAndroidInstaller) -> UpdateInstall:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var running: BuildInfo = BuildInfo.new()
	running.commit = "0123456789abcdef0123456789abcdef01234567"
	return UpdateInstall.new(installer, running, DIR.path_join("last_build.json"))


static func _clean(install: UpdateInstall) -> void:
	if FileAccess.file_exists(install.marker_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(install.marker_path))


func test_permission_request_names_a_throwing_package_name() -> String:
	var installer: FakeAndroidInstaller = _installer("io.example.meltdown", true)
	if installer.ask_install_permission():
		return "the permission screen opened without a package name"
	if installer.failure != THREW:
		return "the reason was '%s'" % installer.failure
	return ""


func test_content_uri_names_a_throwing_package_name() -> String:
	var installer: FakeAndroidInstaller = _installer("io.example.meltdown", true)
	var uri: String = installer.content_uri("/data/files/meltdown_update.apk")
	if uri != "":
		return "a URI was built: %s" % uri
	if installer.failure != THREW:
		return "the reason was '%s'" % installer.failure
	return ""


func test_an_empty_package_name_is_named_in_both_calls() -> String:
	var installer: FakeAndroidInstaller = _installer("", false)
	if installer.ask_install_permission() or installer.failure != "getPackageName gave nothing":
		return "the permission request gave '%s'" % installer.failure
	installer.failure = ""
	if installer.content_uri("/x/y.apk") != "" or installer.failure != "getPackageName gave nothing":
		return "the URI build gave '%s'" % installer.failure
	return ""


func test_update_shows_the_reason_from_the_permission_request() -> String:
	var installer: FakeAndroidInstaller = _installer("io.example.meltdown", true, false)
	var install: UpdateInstall = _update(installer)
	var status: String = install.install("/x/meltdown_update.apk")
	_clean(install)
	var expected: String = UpdateInstall.TEXT_NOT_STARTED % ("permission screen: " + THREW)
	if status != UpdateInstall.STATUS_FAILED or install.text != expected:
		return "install gave %s, '%s'" % [status, install.text]
	return ""


func test_update_shows_the_reason_from_the_uri_build() -> String:
	var installer: FakeAndroidInstaller = _installer("io.example.meltdown", true, true)
	var install: UpdateInstall = _update(installer)
	var status: String = install.install("/x/meltdown_update.apk")
	var marker_left: bool = FileAccess.file_exists(install.marker_path)
	_clean(install)
	var expected: String = UpdateInstall.TEXT_NOT_STARTED % ("content URI: " + THREW)
	if status != UpdateInstall.STATUS_FAILED or install.text != expected:
		return "install gave %s, '%s'" % [status, install.text]
	if marker_left:
		return "the running commit stayed saved after a failed hand-off"
	return ""
