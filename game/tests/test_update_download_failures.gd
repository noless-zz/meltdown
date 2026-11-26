extends RefCounted

## A download that goes wrong (#647, DEV-8): a checksum that does not match, is
## missing or holds no digest, or a network failure, is never reported as
## verified and leaves no file. Split from `test_update_download.gd` (#1287).

const Fx := preload("res://tests/update_download_fixture.gd")


func test_checksum_mismatch_deletes_the_apk_and_says_damaged() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(2000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies[Fx.SHA_URL] = Fx.sha_line(Fx.apk_bytes(1999))
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	download.start(Fx.available())
	Fx.run_steps(download, 100)
	if download.status != UpdateDownload.STATUS_DAMAGED:
		return "status %s, expected damaged" % download.status
	if download.text != "Download damaged, try again":
		return "text '%s'" % download.text
	if not got.is_empty():
		return "a damaged APK must never be reported as verified"
	return Fx.no_files(download)

func test_missing_checksum_file_downloads_no_apk() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies.erase(Fx.SHA_URL)
	download.start(Fx.available())
	if download.status != UpdateDownload.STATUS_FAILED:
		return "status %s, expected failed" % download.status
	if fake.urls != [Fx.SHA_URL]:
		return "the APK should not be fetched without a checksum: %s" % [fake.urls]
	if download.text != UpdateDownload.TEXT_NO_CHECKSUM:
		return "text '%s'" % download.text
	return Fx.no_files(download)

func test_checksum_file_without_a_digest_fails() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.bodies[Fx.SHA_URL] = "Not Found".to_utf8_buffer()
	download.start(Fx.available())
	if download.status != UpdateDownload.STATUS_FAILED or fake.urls.size() != 1:
		return "status %s after %s" % [download.status, fake.urls]
	return Fx.no_files(download)

func test_network_failure_removes_the_partial_file() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	fake.results[Fx.APK_URL] = HTTPRequest.RESULT_CONNECTION_ERROR
	download.start(Fx.available())
	fake.answer()
	if not FileAccess.file_exists(download.apk_path()):
		return "the fake should have left half an APK to clean up"
	fake.answer()
	if download.status != UpdateDownload.STATUS_FAILED:
		return "status %s, expected failed" % download.status
	if not download.text.begins_with("Download failed: "):
		return "text '%s'" % download.text
	return Fx.no_files(download)
