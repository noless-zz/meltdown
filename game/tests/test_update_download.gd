extends RefCounted

## The update the pilot chose downloads, is checked against its SHA-256 and is
## only reported when it matches; anything else leaves no file (#647, DEV-8).
## A fake downloader stands in for GitHub.

const DIR: String = "user://test_update_download"
const APK_URL: String = "https://github.com/noless-zz/meltdown/releases/download/main-latest/meltdown-quest-debug.apk"
const SHA_URL: String = APK_URL + ".sha256"
const COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"


static func _dir() -> String:
	var path: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func _apk_bytes(size: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(size)
	for i: int in size:
		bytes[i] = (i * 31 + 7) % 251
	return bytes


static func _sha_line(bytes: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return ("%s  meltdown-quest-debug.apk\n" % context.finish().hex_encode()).to_utf8_buffer()


static func _available() -> Dictionary:
	return {
		"status": UpdateCheck.STATUS_UPDATE_AVAILABLE,
		"reason": "",
		"commit": COMMIT,
		"apk_url": APK_URL,
		"sha256_url": SHA_URL,
	}


## A fake serving a matching APK and checksum, and a download using it.
static func _setup(apk: PackedByteArray) -> Array:
	var fake: FakeUpdateDownloader = FakeUpdateDownloader.new()
	fake.bodies[APK_URL] = apk
	fake.bodies[SHA_URL] = _sha_line(apk)
	var download: UpdateDownload = UpdateDownload.new(fake, _dir())
	download.cancel()
	for path: String in [download.apk_path(), download.checksum_path()]:
		DirAccess.remove_absolute(path)
	return [fake, download]


static func _run_steps(download: UpdateDownload, limit: int) -> int:
	var steps: int = 0
	while download.is_busy() and steps < limit:
		download.step()
		steps += 1
	return steps


static func _no_files(download: UpdateDownload) -> String:
	for path: String in [download.apk_path(), download.checksum_path()]:
		if FileAccess.file_exists(path):
			return "%s was left behind" % path
	return ""


func test_success_emits_verified_with_the_apk_path() -> String:
	var apk: PackedByteArray = _apk_bytes(3000)
	var parts: Array = _setup(apk)
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	if not download.start(_available()):
		return "the download did not start: %s" % download.text
	_run_steps(download, 100)
	if download.status != UpdateDownload.STATUS_VERIFIED:
		return "status %s (%s)" % [download.status, download.text]
	if got != [download.apk_path()]:
		return "verified emitted %s" % [got]
	if fake.urls != [SHA_URL, APK_URL]:
		return "the checksum should come first, then the APK: %s" % [fake.urls]
	if FileAccess.get_file_as_bytes(download.apk_path()) != apk:
		return "the APK on disk differs from the one served"
	if FileAccess.file_exists(download.checksum_path()):
		return "the checksum file should be removed once read"
	DirAccess.remove_absolute(download.apk_path())
	return ""


func test_the_apk_goes_to_a_fixed_name_in_the_directory() -> String:
	var parts: Array = _setup(_apk_bytes(10))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	download.start(_available())
	_run_steps(download, 10)
	var expected: String = _dir().path_join(UpdateDownload.APK_NAME)
	if fake.paths[1] != expected:
		return "APK written to %s, expected %s" % [fake.paths[1], expected]
	DirAccess.remove_absolute(expected)
	return ""


func test_a_new_download_replaces_an_earlier_one() -> String:
	var parts: Array = _setup(_apk_bytes(500))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var old: FileAccess = FileAccess.open(download.apk_path(), FileAccess.WRITE)
	old.store_buffer(_apk_bytes(9000))
	old.close()
	fake.deferred = true
	download.start(_available())
	if FileAccess.file_exists(download.apk_path()):
		return "the earlier APK should be gone before the new download"
	fake.answer()
	fake.answer()
	_run_steps(download, 10)
	if FileAccess.get_file_as_bytes(download.apk_path()) != _apk_bytes(500):
		return "the new APK did not replace the old one"
	DirAccess.remove_absolute(download.apk_path())
	return ""


func test_checksum_mismatch_deletes_the_apk_and_says_damaged() -> String:
	var parts: Array = _setup(_apk_bytes(2000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies[SHA_URL] = _sha_line(_apk_bytes(1999))
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	download.start(_available())
	_run_steps(download, 100)
	if download.status != UpdateDownload.STATUS_DAMAGED:
		return "status %s, expected damaged" % download.status
	if download.text != "Download damaged, try again":
		return "text '%s'" % download.text
	if not got.is_empty():
		return "a damaged APK must never be reported as verified"
	return _no_files(download)


func test_missing_checksum_file_downloads_no_apk() -> String:
	var parts: Array = _setup(_apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies.erase(SHA_URL)
	download.start(_available())
	if download.status != UpdateDownload.STATUS_FAILED:
		return "status %s, expected failed" % download.status
	if fake.urls != [SHA_URL]:
		return "the APK should not be fetched without a checksum: %s" % [fake.urls]
	if download.text != UpdateDownload.TEXT_NO_CHECKSUM:
		return "text '%s'" % download.text
	return _no_files(download)


func test_checksum_file_without_a_digest_fails() -> String:
	var parts: Array = _setup(_apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies[SHA_URL] = "Not Found".to_utf8_buffer()
	download.start(_available())
	if download.status != UpdateDownload.STATUS_FAILED or fake.urls.size() != 1:
		return "status %s after %s" % [download.status, fake.urls]
	return _no_files(download)


func test_network_failure_removes_the_partial_file() -> String:
	var parts: Array = _setup(_apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	fake.results[APK_URL] = HTTPRequest.RESULT_CONNECTION_ERROR
	download.start(_available())
	fake.answer()
	if not FileAccess.file_exists(download.apk_path()):
		return "the fake should have left half an APK to clean up"
	fake.answer()
	if download.status != UpdateDownload.STATUS_FAILED:
		return "status %s, expected failed" % download.status
	if not download.text.begins_with("Download failed: "):
		return "text '%s'" % download.text
	return _no_files(download)


func test_cancel_stops_the_download_and_removes_the_partial_file() -> String:
	var parts: Array = _setup(_apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	download.start(_available())
	fake.answer()
	download.step()
	if download.status != UpdateDownload.STATUS_DOWNLOADING:
		return "status %s, expected downloading" % download.status
	if not download.cancel():
		return "cancel refused while downloading"
	if download.status != UpdateDownload.STATUS_CANCELLED or fake.cancels != 1:
		return "status %s, cancels %d" % [download.status, fake.cancels]
	var problem: String = _no_files(download)
	if problem != "":
		return problem
	if download.cancel():
		return "a second cancel should do nothing"
	return "" if got.is_empty() else "a cancelled download reported verified"


func test_a_late_answer_after_cancel_is_ignored() -> String:
	var parts: Array = _setup(_apk_bytes(300))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(_available())
	var done: Callable = fake._pending
	download.cancel()
	done.call(HTTPRequest.RESULT_SUCCESS, 200)
	if download.status != UpdateDownload.STATUS_CANCELLED or fake.urls.size() != 1:
		return "a late answer moved the download on: %s %s" % [download.status, fake.urls]
	return _no_files(download)


func test_up_to_date_downloads_nothing() -> String:
	var parts: Array = _setup(_apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var result: Dictionary = _available()
	result["status"] = UpdateCheck.STATUS_UP_TO_DATE
	var ended: Array[String] = []
	download.ended.connect(func(s: String, _t: String) -> void: ended.append(s))
	if download.start(result):
		return "an up-to-date result must not start a download"
	if not fake.urls.is_empty():
		return "fetched %s" % [fake.urls]
	if download.text != "Up to date: e1b0a77":
		return "text '%s'" % download.text
	return "" if ended == [UpdateDownload.STATUS_UP_TO_DATE] else "ended %s" % [ended]


func test_a_result_without_urls_downloads_nothing() -> String:
	var parts: Array = _setup(_apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var result: Dictionary = _available()
	result["sha256_url"] = ""
	if download.start(result) or not fake.urls.is_empty():
		return "started without a checksum URL"
	return "" if download.status == UpdateDownload.STATUS_FAILED else "status %s" % download.status


func test_start_is_refused_while_busy() -> String:
	var parts: Array = _setup(_apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(_available())
	if download.start(_available()) or fake.urls.size() != 1:
		return "a second start began another download"
	download.cancel()
	return ""


func test_progress_reads_the_body_size() -> String:
	var parts: Array = _setup(_apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(_available())
	fake.answer()
	var texts: Array[String] = []
	download.changed.connect(func(t: String) -> void: texts.append(t))
	download.step()
	download.cancel()
	if texts.is_empty() or texts[0] != "Downloading update: 50%":
		return "progress texts %s" % [texts]
	return ""


func test_progress_without_a_size_shows_megabytes() -> String:
	if UpdateDownload.progress_text(3 * 1048576, -1) != "Downloading update: 3.0 MB":
		return UpdateDownload.progress_text(3 * 1048576, -1)
	if UpdateDownload.percent(1, 3) != 33 or UpdateDownload.percent(5, 4) != 100:
		return "percent rounds down and stops at 100"
	return ""


func test_hashing_is_spread_over_frames() -> String:
	var parts: Array = _setup(_apk_bytes(ChunkedSha256.DEFAULT_CHUNK_BYTES * 9 + 5))
	var download: UpdateDownload = parts[1]
	download.start(_available())
	if download.status != UpdateDownload.STATUS_VERIFYING:
		return "status %s, expected verifying" % download.status
	var steps: int = _run_steps(download, 100)
	DirAccess.remove_absolute(download.apk_path())
	if download.status != UpdateDownload.STATUS_VERIFIED:
		return "status %s" % download.status
	return "" if steps == 3 else "took %d steps, expected 3 (4 chunks each)" % steps
