class_name UpdateDownload
extends RefCounted

## Downloads the build the pilot chose to install and checks it against its
## published SHA-256 (#647, DEV-8, PLT-1). The checksum file comes first, so a
## release without one costs no APK download. The APK is written under a fixed
## name in `directory`, replacing any earlier download, and is only reported
## through `verified` once its digest matches; a damaged, failed or cancelled
## download deletes what it wrote, so nothing unchecked can reach the installer
## (#648). Progress and outcome are a one-line `text` for the update notice.
##
## The downloads go through an `UpdateDownloader`, so tests can fake them.
## Call `step()` once per frame: it refreshes the progress and hashes the APK a
## few chunks per frame.

## Whenever `text` changes: progress or an outcome.
signal changed(text: String)
## The checked APK, ready for the installer.
signal verified(path: String)
## Once per `start()` that began, or at once when it refused: the final
## status and text.
signal ended(status: String, text: String)

const LOG_PREFIX: String = "MELTDOWN_UPDATE"

const STATUS_IDLE: String = "idle"
const STATUS_CHECKSUM: String = "checksum"
const STATUS_DOWNLOADING: String = "downloading"
const STATUS_VERIFYING: String = "verifying"
const STATUS_VERIFIED: String = "verified"
const STATUS_UP_TO_DATE: String = "up_to_date"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_DAMAGED: String = "damaged"
const STATUS_FAILED: String = "failed"
const BUSY: Array[String] = [STATUS_CHECKSUM, STATUS_DOWNLOADING, STATUS_VERIFYING]

const APK_NAME: String = "meltdown_update.apk"
const CHECKSUM_NAME: String = "meltdown_update.apk.sha256"

const CHECKSUM_TIMEOUT_SECONDS: float = 20.0
## A whole 89 MB APK on slow Wi-Fi; HTTPRequest's timeout covers the request.
const APK_TIMEOUT_SECONDS: float = 900.0
## 4 x 256 KB a frame: an 89 MB APK in under 100 frames, about a second.
const HASH_CHUNKS_PER_STEP: int = 4

const TEXT_STARTING: String = "Downloading update..."
const TEXT_PERCENT: String = "Downloading update: %d%%"
const TEXT_MEGABYTES: String = "Downloading update: %.1f MB"
const TEXT_VERIFYING: String = "Checking the download..."
const TEXT_VERIFIED: String = "Update downloaded and checked"
const TEXT_UP_TO_DATE: String = "Up to date: %s"
const TEXT_CANCELLED: String = "Download cancelled"
const TEXT_DAMAGED: String = "Download damaged, try again"
const TEXT_NO_CHECKSUM: String = "No checksum for this build, try again later"
const TEXT_FAILED: String = "Download failed: %s"
const TEXT_NOTHING: String = "Nothing to download: %s"

var downloader: UpdateDownloader
var directory: String
var status: String = STATUS_IDLE
var text: String = ""

var _hasher: ChunkedSha256 = ChunkedSha256.new()
var _expected_digest: String = ""
var _apk_url: String = ""
## Bumped on every start and cancel, so a late answer from an earlier
## download is ignored.
var _attempt: int = 0


func _init(p_downloader: UpdateDownloader, p_directory: String) -> void:
	downloader = p_downloader
	directory = p_directory


## Where downloads go: Godot's user directory, which on Android is the
## activity's files directory that the template's FileProvider serves.
static func default_directory() -> String:
	return OS.get_user_data_dir()


func apk_path() -> String:
	return directory.path_join(APK_NAME)


func checksum_path() -> String:
	return directory.path_join(CHECKSUM_NAME)


func is_busy() -> bool:
	return BUSY.has(status)


## Starts downloading the build in `check_result`, the latest
## `UpdateCheck.evaluate()` result. Returns whether a download began. An
## up-to-date result or one without URLs downloads nothing and ends at once.
func start(check_result: Dictionary) -> bool:
	if is_busy():
		return false
	_attempt += 1
	_apk_url = check_result.get("apk_url", "")
	var sha_url: String = check_result.get("sha256_url", "")
	var check_status: String = check_result.get("status", "")
	if check_status == UpdateCheck.STATUS_UP_TO_DATE:
		var commit: String = check_result.get("commit", BuildInfo.UNKNOWN)
		return _end(STATUS_UP_TO_DATE, TEXT_UP_TO_DATE % commit.left(7))
	if check_status != UpdateCheck.STATUS_UPDATE_AVAILABLE:
		return _end(STATUS_FAILED, TEXT_NOTHING % check_result.get("reason", "no newer build"))
	if _apk_url == "" or sha_url == "":
		return _end(STATUS_FAILED, TEXT_NOTHING % "the release has no APK or checksum")
	_remove_files()
	_show(STATUS_CHECKSUM, TEXT_STARTING)
	print("%s download %s" % [LOG_PREFIX, check_result.get("commit", BuildInfo.UNKNOWN)])
	var started: int = downloader.fetch(sha_url, checksum_path(), CHECKSUM_TIMEOUT_SECONDS,
		_on_checksum_done.bind(_attempt))
	if started != OK:
		return _fail(TEXT_FAILED % ("could not start (%s)" % error_string(started)))
	return true


## Stops a running download and deletes what it wrote. Returns whether one
## was running.
func cancel() -> bool:
	if not is_busy():
		return false
	_attempt += 1
	downloader.cancel()
	_hasher.close()
	_remove_files()
	_end(STATUS_CANCELLED, TEXT_CANCELLED)
	return true


## Once per frame: updates the progress text and hashes a few chunks.
func step() -> void:
	if status == STATUS_DOWNLOADING:
		_show(STATUS_DOWNLOADING, progress_text(downloader.downloaded_bytes(), downloader.total_bytes()))
	elif status == STATUS_VERIFYING and _hasher.feed(HASH_CHUNKS_PER_STEP):
		_finish_verify()


## 0 to 100 from the announced body size, or -1 when the size is unknown.
static func percent(downloaded: int, total: int) -> int:
	if total <= 0:
		return -1
	return clampi(int(floor(100.0 * float(downloaded) / float(total))), 0, 100)


static func progress_text(downloaded: int, total: int) -> String:
	var whole: int = percent(downloaded, total)
	if whole >= 0:
		return TEXT_PERCENT % whole
	return TEXT_MEGABYTES % (float(maxi(downloaded, 0)) / 1048576.0)


func _on_checksum_done(result: int, http_code: int, attempt: int) -> void:
	if attempt != _attempt or status != STATUS_CHECKSUM:
		return
	var failure: String = _http_failure(result, http_code)
	var digest: String = ""
	if failure == "" and FileAccess.file_exists(checksum_path()):
		digest = UpdateCheck.parse_sha256(FileAccess.get_file_as_string(checksum_path()))
	DirAccess.remove_absolute(checksum_path())
	if failure != "" or digest == "":
		if failure != "":
			print("%s checksum %s" % [LOG_PREFIX, failure])
		_fail(TEXT_NO_CHECKSUM)
		return
	_expected_digest = digest
	_show(STATUS_DOWNLOADING, TEXT_STARTING)
	var started: int = downloader.fetch(_apk_url, apk_path(), APK_TIMEOUT_SECONDS,
		_on_apk_done.bind(_attempt))
	if started != OK:
		_fail(TEXT_FAILED % ("could not start (%s)" % error_string(started)))


func _on_apk_done(result: int, http_code: int, attempt: int) -> void:
	if attempt != _attempt or status != STATUS_DOWNLOADING:
		return
	var failure: String = _http_failure(result, http_code)
	if failure != "":
		_fail(TEXT_FAILED % failure)
		return
	if not _hasher.open(apk_path()):
		_fail(TEXT_FAILED % _hasher.failure)
		return
	_show(STATUS_VERIFYING, TEXT_VERIFYING)


func _finish_verify() -> void:
	if _hasher.failure != "":
		_fail(TEXT_FAILED % _hasher.failure)
		return
	if _hasher.digest != _expected_digest:
		print("%s damaged: expected %s, got %s" % [LOG_PREFIX, _expected_digest, _hasher.digest])
		_remove_files()
		_end(STATUS_DAMAGED, TEXT_DAMAGED)
		return
	_end(STATUS_VERIFIED, TEXT_VERIFIED)
	verified.emit(apk_path())


static func _http_failure(result: int, http_code: int) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "network error %d" % result
	if http_code != 200:
		return "HTTP %d" % http_code
	return ""


func _fail(reason_text: String) -> bool:
	_remove_files()
	return _end(STATUS_FAILED, reason_text)


## Always false, so `start()` can return it for a download that never began.
func _end(final_status: String, final_text: String) -> bool:
	_show(final_status, final_text)
	print("%s %s: %s" % [LOG_PREFIX, final_status, final_text])
	ended.emit(final_status, final_text)
	return false


func _show(new_status: String, new_text: String) -> void:
	status = new_status
	if new_text == text:
		return
	text = new_text
	changed.emit(text)


func _remove_files() -> void:
	for path: String in [apk_path(), checksum_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
