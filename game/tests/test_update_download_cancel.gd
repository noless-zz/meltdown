extends RefCounted

## Cancelling a download and the starts it refuses (#647, DEV-8): a cancel
## leaves no file and ignores a late answer; an up-to-date result, one without
## URLs, or a start while busy downloads nothing. Split from
## `test_update_download.gd` (#1287).

const Fx := preload("res://tests/update_download_fixture.gd")


func test_cancel_stops_the_download_and_removes_the_partial_file() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(4000))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	var got: Array[String] = []
	download.verified.connect(func(path: String) -> void: got.append(path))
	download.start(Fx.available())
	fake.answer()
	download.step()
	if download.status != UpdateDownload.STATUS_DOWNLOADING:
		return "status %s, expected downloading" % download.status
	if not download.cancel():
		return "cancel refused while downloading"
	if download.status != UpdateDownload.STATUS_CANCELLED or fake.cancels != 1:
		return "status %s, cancels %d" % [download.status, fake.cancels]
	var problem: String = Fx.no_files(download)
	if problem != "":
		return problem
	if download.cancel():
		return "a second cancel should do nothing"
	return "" if got.is_empty() else "a cancelled download reported verified"

func test_a_late_answer_after_cancel_is_ignored() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(300))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(Fx.available())
	var done: Callable = fake._pending
	download.cancel()
	done.call(HTTPRequest.RESULT_SUCCESS, 200)
	if download.status != UpdateDownload.STATUS_CANCELLED or fake.urls.size() != 1:
		return "a late answer moved the download on: %s %s" % [download.status, fake.urls]
	return Fx.no_files(download)

func test_up_to_date_downloads_nothing() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var result: Dictionary = Fx.available()
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
	var parts: Array = Fx.setup(Fx.apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	var result: Dictionary = Fx.available()
	result["sha256_url"] = ""
	if download.start(result) or not fake.urls.is_empty():
		return "started without a checksum URL"
	return "" if download.status == UpdateDownload.STATUS_FAILED else "status %s" % download.status

func test_start_is_refused_while_busy() -> String:
	var parts: Array = Fx.setup(Fx.apk_bytes(100))
	var fake: FakeUpdateDownloader = parts[0]
	var download: UpdateDownload = parts[1]
	fake.deferred = true
	download.start(Fx.available())
	if download.start(Fx.available()) or fake.urls.size() != 1:
		return "a second start began another download"
	download.cancel()
	return ""
