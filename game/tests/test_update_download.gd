extends RefCounted

## The update the pilot chose downloads, is checked against its SHA-256 and is
## only reported when it matches (#647, DEV-8): the verified path, where the APK
## goes, progress and hashing spread over frames. Failures are in
## `test_update_download_failures.gd`, cancel and refused starts in
## `test_update_download_cancel.gd` (split for the 300-line guide, #1287).
## A fake downloader stands in for GitHub.

const Fx := preload("res://tests/update_download_fixture.gd")


func test_success_emits_verified_with_the_apk_path() -> String:
	var apk: PackedByteArray = Fx.apk_bytes(3000)
	var parts: Array = Fx.setup(apk)
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	if not download.start(Fx.available()):
		return "the download did not start: %s" % download.text
	Fx.run_steps(download, 100)
	if download.status != UpdateDownload.STATUS_VERIFIED:
		return "status %s (%s)" % [download.status, download.text]
	if got != [download.apk_path()]:
		return "verified emitted %s" % [got]
	if fake.urls != [Fx.SHA_URL, Fx.APK_URL]:
		return "the checksum should come first, then the APK: %s" % [fake.urls]
	if FileAccess.get_file_as_bytes(download.apk_path()) != apk:
		return "the APK on disk differs from the one served"
	if FileAccess.file_exists(download.checksum_path()):
		return "the checksum file should be removed once read"
	DirAccess.remove_absolute(download.apk_path())
	return ""

func test_the_apk_goes_to_a_fixed_name_in_the_directory() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(10))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	download.start(Fx.available())
	Fx.run_steps(download, 10)
	var expected: String = Fx.dir().path_join(UpdateDownload.APK_NAME)
	if fake.paths[1] != expected:
		return "APK written to %s, expected %s" % [fake.paths[1], expected]
	DirAccess.remove_absolute(expected)
	return ""

func test_a_new_download_replaces_an_earlier_one() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(500))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var old: FileAccess = FileAccess.open(download.apk_path(), FileAccess.WRITE)
	old.store_buffer(Fx.apk_bytes(9000))
	old.close()
	fake.deferred = true
	download.start(Fx.available())
	if FileAccess.file_exists(download.apk_path()):
		return "the earlier APK should be gone before the new download"
	fake.answer()
	fake.answer()
	Fx.run_steps(download, 10)
	if FileAccess.get_file_as_bytes(download.apk_path()) != Fx.apk_bytes(500):
		return "the new APK did not replace the old one"
	DirAccess.remove_absolute(download.apk_path())
	return ""

func test_progress_reads_the_body_size() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(Fx.available())
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
	var parts: Array = Fx.setup(Fx.apk_bytes(ChunkedSha256.DEFAULT_CHUNK_BYTES * 9 + 5))
	var download: UpdateDownload = parts[1]
	download.start(Fx.available())
	if download.status != UpdateDownload.STATUS_VERIFYING:
		return "status %s, expected verifying" % download.status
	var steps: int = Fx.run_steps(download, 100)
	DirAccess.remove_absolute(download.apk_path())
	if download.status != UpdateDownload.STATUS_VERIFIED:
		return "status %s" % download.status
	return "" if steps == 3 else "took %d steps, expected 3 (4 chunks each)" % steps
