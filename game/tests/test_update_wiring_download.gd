extends RefCounted

## Choosing "Update" downloads the offered build: the notice follows the
## download, a menu tap cancels it, and a checked APK is passed on as
## `update_verified` for the installer (#673, DEV-8, PLT-1). Fakes stand in
## for GitHub on both the check and the download.

const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
const DIR: String = "user://test_update_wiring_download"
const APK_URL: String = "https://github.com/noless-zz/meltdown/releases/download/main-latest/meltdown-quest-debug.apk"
const SHA_URL: String = APK_URL + ".sha256"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
const APK_SIZE: int = 300000


static func _apk_bytes() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(APK_SIZE)
	for i: int in APK_SIZE:
		bytes[i] = (i * 17 + 3) % 253
	return bytes


static func _sha_line(bytes: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return ("%s  meltdown-quest-debug.apk\n" % context.finish().hex_encode()).to_utf8_buffer()


## A wiring offering a newer build, with a download served by `downloader`.
static func _wired(panel: Node3D, downloader: FakeUpdateDownloader) -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = BuildInfo.new()
	running.commit = OTHER_COMMIT
	var transport: FakeUpdateTransport = FakeUpdateTransport.new()
	transport.body = FileAccess.get_file_as_string(FIXTURE)
	var directory: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var apk: PackedByteArray = _apk_bytes()
	downloader.bodies[APK_URL] = apk
	downloader.bodies[SHA_URL] = _sha_line(apk)
	var wiring: UpdateWiring = UpdateWiring.new()
	wiring.attach_with(panel, UpdateRequest.new(settings, transport, running, true),
		UpdateDownload.new(downloader, directory))
	return wiring


## A tap: down at `at`, up `held` seconds later. Two frames.
static func _tap(wiring: UpdateWiring, at: float, held: float = 0.2) -> void:
	wiring.press_menu(true, at)
	wiring.press_menu(false, at + held)


## Frames with the button up until the download ends or `limit` runs out.
static func _frames(wiring: UpdateWiring, from: float, limit: int) -> int:
	var frames: int = 0
	while wiring.download.is_busy() and frames < limit:
		wiring.press_menu(false, from + 0.02 * frames)
		frames += 1
	return frames


func test_choosing_update_downloads_and_passes_the_apk_on() -> String:
	var panel: Node3D = Node3D.new()
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	var wiring: UpdateWiring = _wired(panel, downloader)
	var lines: Array[String] = []
	var verified: Array[String] = []
	wiring.download.changed.connect(func(_text: String) -> void: lines.append(wiring.notice.line_text()))
	wiring.update_verified.connect(func(path: String) -> void: verified.append(path))
	_tap(wiring, 10.0)
	_frames(wiring, 11.0, 100)
	var message: String = ""
	if downloader.urls != [SHA_URL, APK_URL]:
		message = "the download fetched %s" % [downloader.urls]
	elif wiring.download.status != UpdateDownload.STATUS_VERIFIED:
		message = "the download ended as %s" % wiring.download.status
	elif verified != [wiring.download.apk_path()]:
		message = "update_verified gave %s" % [verified]
	elif not lines.has(UpdateDownload.TEXT_VERIFYING):
		message = "the notice never showed the check: %s" % [lines]
	elif wiring.notice.line_text() != UpdateDownload.TEXT_VERIFIED or not wiring.notice.is_showing():
		message = "the notice ended on '%s'" % wiring.notice.line_text()
	else:
		wiring.notice.advance(UpdateNotice.OUTCOME_SECONDS - 0.5)
		if not wiring.notice.is_showing():
			message = "the outcome went before its time"
		else:
			wiring.notice.advance(1.0)
			if wiring.notice.is_showing():
				message = "the outcome stayed up"
	DirAccess.remove_absolute(wiring.download.apk_path())
	panel.free()
	return message


func test_progress_reaches_the_notice_and_stays_while_it_runs() -> String:
	var panel: Node3D = Node3D.new()
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	downloader.deferred = true
	var wiring: UpdateWiring = _wired(panel, downloader)
	_tap(wiring, 10.0)
	downloader.answer()  # The checksum; the APK is now half written.
	var message: String = ""
	if wiring.download.status != UpdateDownload.STATUS_DOWNLOADING:
		message = "after the checksum the download was %s" % wiring.download.status
	else:
		wiring.press_menu(false, 11.0)
		if wiring.notice.line_text() != "Downloading update: 50%":
			message = "the notice read '%s' halfway" % wiring.notice.line_text()
		else:
			wiring.notice.advance(UpdateNotice.OFFER_SECONDS * 3.0)
			if not wiring.notice.is_showing():
				message = "the progress line timed out while the download ran"
	wiring.download.cancel()
	panel.free()
	return message


func test_step_runs_once_per_frame_while_busy() -> String:
	var panel: Node3D = Node3D.new()
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	var wiring: UpdateWiring = _wired(panel, downloader)
	_tap(wiring, 10.0)
	var message: String = ""
	if wiring.download.status != UpdateDownload.STATUS_VERIFYING:
		message = "the fake download did not reach the check: %s" % wiring.download.status
	else:
		# 300 000 bytes are two 256 KB chunks, hashed within one step.
		wiring.press_menu(false, 11.0)
		if wiring.download.status != UpdateDownload.STATUS_VERIFIED:
			message = "one frame did not step the check: %s" % wiring.download.status
	DirAccess.remove_absolute(wiring.download.apk_path())
	panel.free()
	return message


func test_a_menu_tap_cancels_a_running_download() -> String:
	var panel: Node3D = Node3D.new()
	var downloader: FakeUpdateDownloader = FakeUpdateDownloader.new()
	downloader.deferred = true
	var wiring: UpdateWiring = _wired(panel, downloader)
	var chosen: Array[bool] = []
	wiring.update_chosen.connect(func(_result: Dictionary) -> void: chosen.append(true))
	_tap(wiring, 10.0)
	downloader.answer()
	var requests_before: int = (wiring.request.transport as FakeUpdateTransport).urls.size()
	_tap(wiring, 12.0)
	var message: String = ""
	if wiring.download.status != UpdateDownload.STATUS_CANCELLED or downloader.cancels != 1:
		message = "the tap left the download %s, %d cancels" % [wiring.download.status, downloader.cancels]
	elif wiring.notice.line_text() != "Download cancelled" or not wiring.notice.is_showing():
		message = "the notice read '%s'" % wiring.notice.line_text()
	elif FileAccess.file_exists(wiring.download.apk_path()):
		message = "the cancelled APK was left behind"
	elif (wiring.request.transport as FakeUpdateTransport).urls.size() != requests_before:
		message = "the cancelling tap also asked for a check"
	elif chosen.size() != 1:
		message = "Update was chosen %d times" % chosen.size()
	panel.free()
	return message


func test_without_a_download_update_only_emits() -> String:
	var panel: Node3D = Node3D.new()
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = BuildInfo.new()
	running.commit = OTHER_COMMIT
	var transport: FakeUpdateTransport = FakeUpdateTransport.new()
	transport.body = FileAccess.get_file_as_string(FIXTURE)
	var wiring: UpdateWiring = UpdateWiring.new()
	wiring.attach_with(panel, UpdateRequest.new(settings, transport, running, true))
	var chosen: Array[bool] = []
	wiring.update_chosen.connect(func(_result: Dictionary) -> void: chosen.append(true))
	_tap(wiring, 10.0)
	var message: String = "" if chosen.size() == 1 and wiring.download == null else "Update did not emit alone"
	panel.free()
	return message
