extends RefCounted

## The wiring hands a checked download to the installer (#648): the notice
## shows the hand-off, a tap retries one that waits for the permission, a tap
## after the installer opened checks again, and the next start shows
## "Updated from ... to ..." once. Fakes stand in for GitHub and Android.

const Download := preload("res://tests/test_update_wiring_download.gd")
const DIR: String = "user://test_update_wiring_install"
const MARKER: String = DIR + "/last_build.json"
## The fixture release's commit, so the start check after the update says up to date.
const NEW_COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"


static func _running(commit: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	info.commit = commit
	return info


static func _wired(panel: Node3D, bridge: FakeUpdateInstallBridge, running_commit: String = Download.OTHER_COMMIT) -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = _running(running_commit)
	var transport: FakeUpdateTransport = FakeUpdateTransport.new()
	transport.body = FileAccess.get_file_as_string(Download.FIXTURE)
	var directory: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	var apk: PackedByteArray = Download._apk_bytes()
	downloader.bodies[Download.APK_URL] = apk
	downloader.bodies[Download.SHA_URL] = Download._sha_line(apk)
	var wiring: UpdateWiring = UpdateWiring.new()
	wiring.attach_with(panel, UpdateRequest.new(settings, transport, running, true),
		UpdateDownload.new(downloader, directory), UpdateInstall.new(bridge, running, MARKER))
	return wiring


static func _clean(wiring: UpdateWiring) -> void:
	for path: String in [wiring.download.apk_path(), ProjectSettings.globalize_path(MARKER)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Update chosen, downloaded and checked in one tap and one frame.
static func _update(wiring: UpdateWiring, at: float) -> void:
	Download._tap(wiring, at)
	Download._frames(wiring, at + 1.0, 100)


func test_a_checked_download_goes_to_the_installer() -> String:
	var panel: Node3D = Node3D.new()
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	var wiring: UpdateWiring = _wired(panel, bridge)
	_update(wiring, 10.0)
	var message: String = ""
	if bridge.calls != ["may_install", "content_uri", "start_installer"]:
		message = "calls %s" % [bridge.calls]
	elif bridge.uri_targets != [wiring.download.apk_path()]:
		message = "handed over %s" % [bridge.uri_targets]
	elif wiring.notice.line_text() != UpdateInstall.TEXT_STARTED:
		message = "the notice read '%s'" % wiring.notice.line_text()
	elif not FileAccess.file_exists(MARKER):
		message = "the running commit was not saved"
	_clean(wiring)
	panel.free()
	return message


func test_a_tap_retries_after_the_permission_screen() -> String:
	var panel: Node3D = Node3D.new()
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	bridge.allowed = UpdateInstallBridge.NOT_ALLOWED
	var wiring: UpdateWiring = _wired(panel, bridge)
	_update(wiring, 10.0)
	var message: String = ""
	if wiring.notice.line_text() != UpdateInstall.TEXT_ASK:
		message = "the notice read '%s'" % wiring.notice.line_text()
	else:
		var requests_before: int = (wiring.request.transport as FakeUpdateTransport).urls.size()
		bridge.allowed = UpdateInstallBridge.ALLOWED
		Download._tap(wiring, 30.0)
		if wiring.install.status != UpdateInstall.STATUS_STARTED:
			message = "the retry left the install %s" % wiring.install.status
		elif (wiring.request.transport as FakeUpdateTransport).urls.size() != requests_before:
			message = "the retrying tap also asked for a check"
		else:
			# Once the installer opened, a tap checks again instead.
			Download._tap(wiring, 40.0)
			if (wiring.request.transport as FakeUpdateTransport).urls.size() != requests_before + 1:
				message = "a tap after the hand-off did not check"
			elif bridge.calls.count("start_installer") != 1:
				message = "the installer opened %d times" % bridge.calls.count("start_installer")
	_clean(wiring)
	panel.free()
	return message


func test_a_failed_hand_off_is_shown_and_retried() -> String:
	var panel: Node3D = Node3D.new()
	var bridge: FakeUpdateInstallBridge = FakeUpdateInstallBridge.new()
	bridge.fail_at = "start_installer"
	var wiring: UpdateWiring = _wired(panel, bridge)
	_update(wiring, 10.0)
	var message: String = ""
	if not wiring.notice.line_text().begins_with("Installer did not start"):
		message = "the notice read '%s'" % wiring.notice.line_text()
	elif not FileAccess.file_exists(wiring.download.apk_path()):
		message = "the APK was removed"
	else:
		bridge.fail_at = ""
		Download._tap(wiring, 30.0)
		if wiring.install.status != UpdateInstall.STATUS_STARTED:
			message = "the retry left the install %s" % wiring.install.status
	_clean(wiring)
	panel.free()
	return message


func test_the_next_start_names_the_old_and_new_commits_once() -> String:
	var panel: Node3D = Node3D.new()
	var first: UpdateWiring = _wired(panel, FakeUpdateInstallBridge.new())
	_update(first, 10.0)
	var message: String = ""
	var after: UpdateWiring = _wired(panel, FakeUpdateInstallBridge.new(), NEW_COMMIT)
	if after.notice.line_text() != "Updated from 0123456 to e1b0a77" or not after.notice.is_showing():
		message = "the new build's notice read '%s'" % after.notice.line_text()
	else:
		var again: UpdateWiring = _wired(panel, FakeUpdateInstallBridge.new(), NEW_COMMIT)
		if again.notice.line_text().begins_with("Updated from"):
			message = "the message showed a second time"
	_clean(first)
	panel.free()
	return message


func test_without_an_installer_a_checked_download_is_only_passed_on() -> String:
	var panel: Node3D = Node3D.new()
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	var wiring: UpdateWiring = Download._wired(panel, downloader)
	_update(wiring, 10.0)
	var message: String = ""
	if wiring.install != null:
		message = "an installer was attached"
	elif wiring.notice.line_text() != UpdateDownload.TEXT_VERIFIED:
		message = "the notice read '%s'" % wiring.notice.line_text()
	DirAccess.remove_absolute(wiring.download.apk_path())
	panel.free()
	return message
