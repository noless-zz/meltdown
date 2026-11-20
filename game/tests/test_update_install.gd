extends RefCounted

## Handing a checked download to the installer (#648, DEV-8, PLT-1): the
## permission is checked first and asked for when missing, the running commit
## is saved just before the hand-off, a hand-off that does not start says so
## and keeps the APK, and the next start says "Updated from ... to ..." once,
## only when the commit changed. A fake bridge stands in for Android.

const DIR: String = "user://test_update_install"
const OLD_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
const NEW_COMMIT: String = "fedcba9876543210fedcba9876543210fedcba98"


static func _marker() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	return DIR.path_join("last_build.json")


static func _apk() -> String:
	var path: String = ProjectSettings.globalize_path(DIR).path_join("meltdown_update.apk")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("apk")
	file.close()
	return path


static func _build(commit: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	info.commit = commit
	return info


static func _install(bridge: FakeUpdateInstallBridge) -> UpdateInstall:
	var marker: String = _marker()
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	return UpdateInstall.new(bridge, _build(OLD_COMMIT), marker)


static func _clean(install: UpdateInstall) -> void:
	for path: String in [install.marker_path, install.pending_path]:
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_permission_granted_hands_the_apk_over() -> String:
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	var install: UpdateInstall = _install(bridge)
	var apk: String = _apk()
	var status: String = install.install(apk)
	var message: String = ""
	if status != UpdateInstall.STATUS_STARTED or install.text != UpdateInstall.TEXT_STARTED:
		message = "install gave %s, '%s'" % [status, install.text]
	elif bridge.calls != ["may_install", "content_uri", "start_installer"]:
		message = "calls %s" % [bridge.calls]
	elif bridge.uri_targets != [apk]:
		message = "the URI was built for %s" % [bridge.uri_targets]
	elif not FileAccess.file_exists(install.marker_path):
		message = "the running commit was not saved"
	elif not FileAccess.get_file_as_string(install.marker_path).contains(OLD_COMMIT):
		message = "the marker holds '%s'" % FileAccess.get_file_as_string(install.marker_path)
	_clean(install)
	return message


func test_permission_missing_explains_and_opens_the_prompt() -> String:
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	bridge.allowed = UpdateInstallBridge.NOT_ALLOWED
	var install: UpdateInstall = _install(bridge)
	var apk: String = _apk()
	var status: String = install.install(apk)
	var message: String = ""
	if status != UpdateInstall.STATUS_ASKED:
		message = "install gave %s" % status
	elif bridge.calls != ["may_install", "ask_install_permission"]:
		message = "calls %s" % [bridge.calls]
	elif install.text != UpdateInstall.TEXT_ASK or not install.text.contains("allow installs from this app"):
		message = "the notice read '%s'" % install.text
	elif FileAccess.file_exists(install.marker_path):
		message = "a commit was saved though nothing was handed over"
	elif not install.has_pending() or install.pending_path != apk:
		message = "the APK is not kept for the retry"
	else:
		# The pilot allows installs and taps again.
		bridge.allowed = UpdateInstallBridge.ALLOWED
		if install.install(install.pending_path) != UpdateInstall.STATUS_STARTED:
			message = "the retry gave %s" % install.status
	_clean(install)
	return message


func test_an_unknown_permission_still_tries_the_installer() -> String:
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	bridge.allowed = UpdateInstallBridge.UNKNOWN
	var install: UpdateInstall = _install(bridge)
	var status: String = install.install(_apk())
	var message: String = "" if status == UpdateInstall.STATUS_STARTED else "install gave %s" % status
	_clean(install)
	return message


func test_installer_not_starting_says_so_and_keeps_the_apk() -> String:
	for fail_at: String in ["content_uri", "start_installer", "ask_install_permission"]:
		var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
		bridge.fail_at = fail_at
		if fail_at == "ask_install_permission":
			bridge.allowed = UpdateInstallBridge.NOT_ALLOWED
		var install: UpdateInstall = _install(bridge)
		var apk: String = _apk()
		var status: String = install.install(apk)
		var message: String = ""
		if status != UpdateInstall.STATUS_FAILED:
			message = "%s: install gave %s" % [fail_at, status]
		elif not install.text.begins_with("Installer did not start") or not install.text.contains(bridge.fail_reason):
			message = "%s: the notice read '%s'" % [fail_at, install.text]
		elif not FileAccess.file_exists(apk) or not install.has_pending():
			message = "%s: the APK was not kept for a retry" % fail_at
		elif FileAccess.file_exists(install.marker_path):
			message = "%s: the saved commit would claim an update next start" % fail_at
		_clean(install)
		if message != "":
			return message
	return ""


func test_updated_message_shows_once_when_the_commit_changed() -> String:
	var install: UpdateInstall = _install(FakeUpdateInstallBridge.new())
	install.save_marker()
	var first: String = UpdateInstall.take_update_message(_build(NEW_COMMIT), install.marker_path)
	var second: String = UpdateInstall.take_update_message(_build(NEW_COMMIT), install.marker_path)
	if first != "Updated from 0123456 to fedcba9":
		return "the first start said '%s'" % first
	if second != "":
		return "the second start said '%s' again" % second
	if FileAccess.file_exists(install.marker_path):
		return "the marker was not cleared"
	return ""


func test_no_message_when_the_commit_did_not_change() -> String:
	var install: UpdateInstall = _install(FakeUpdateInstallBridge.new())
	install.save_marker()
	var same: String = UpdateInstall.take_update_message(_build(OLD_COMMIT), install.marker_path)
	if same != "":
		return "the same build said '%s'" % same
	if FileAccess.file_exists(install.marker_path):
		return "the marker was not cleared"
	return ""


func test_no_message_without_a_marker_or_with_unknown_commits() -> String:
	var install: UpdateInstall = _install(FakeUpdateInstallBridge.new())
	if UpdateInstall.take_update_message(_build(NEW_COMMIT), install.marker_path) != "":
		return "a message without a saved commit"
	install.save_marker()
	if UpdateInstall.take_update_message(BuildInfo.new(), install.marker_path) != "":
		return "a message for an unknown running build"
	var file: FileAccess = FileAccess.open(install.marker_path, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	if UpdateInstall.take_update_message(_build(NEW_COMMIT), install.marker_path) != "":
		return "a message from a damaged marker"
	if FileAccess.file_exists(install.marker_path):
		return "the damaged marker was not cleared"
	return ""


## The probe uses the same Java class for the URI and the intent; off Android
## both fail with its reason instead of touching Java.
func test_probe_shares_the_android_installer() -> String:
	var probe: InstallerProbeJava = InstallerProbeJava.new(null)
	if probe.content_uri("/x/y.apk") != "" or probe.failure != "no Android activity":
		return "the probe's URI step gave '%s'" % probe.failure
	probe.failure = ""
	if probe.start_installer() or probe.failure != "no Android activity":
		return "the probe's intent step gave '%s'" % probe.failure
	var installer: AndroidInstaller = AndroidInstaller.new(null)
	if installer.may_install() != UpdateInstallBridge.UNKNOWN or installer.ask_install_permission():
		return "the installer answered without an activity"
	return ""
