class_name UpdateRequest
extends RefCounted

## Asks GitHub for the `main-latest` release and decides with `UpdateCheck`
## whether a newer build exists (#646, DEV-8, PLT-1). Debug builds only: a
## store or release build is never `allowed` and sends nothing, ever.
##
## One request on start and one each time the pilot asks, never a retry: a
## failure is logged under `LOG_PREFIX` and, unless the pilot asked, not shown
## at all, so a headset without a network flies exactly as before (PLT-1).
## The request goes through an `UpdateTransport`, so tests can fake it.

signal finished(result: Dictionary, asked: bool)

const LOG_PREFIX: String = "MELTDOWN_UPDATE"
## GitHub's API refuses requests without a user agent.
const HEADERS: PackedStringArray = [
	"User-Agent: meltdown-update-check",
	"Accept: application/vnd.github+json",
]
const NOTICE_AVAILABLE: String = "Update available: %s"
const NOTICE_UP_TO_DATE: String = "Up to date: %s"
const NOTICE_UNKNOWN: String = "Update check: %s"
const NOTICE_ERROR: String = "Update check failed: %s"

var settings: UpdateSettings
var transport: UpdateTransport
var running: BuildInfo
## False in release builds and when the data file turns the check off.
var allowed: bool = false
## Requests handed to the transport since this object was made.
var requests_sent: int = 0
var in_flight: bool = false

var _started: bool = false
var _asked: bool = false


func _init(p_settings: UpdateSettings, p_transport: UpdateTransport, p_running: BuildInfo, p_allowed: bool) -> void:
	settings = p_settings
	transport = p_transport
	running = p_running
	allowed = p_allowed and settings != null and settings.enabled


## Whether a build may ask GitHub at all. `platform_ok` is true on the headset,
## where an update can be installed, or when a desktop run asks for the check.
static func is_allowed(is_debug_build: bool, p_settings: UpdateSettings, platform_ok: bool) -> bool:
	return is_debug_build and p_settings != null and p_settings.enabled and platform_ok


## The automatic check, once per start: later calls send nothing.
func check_on_start() -> bool:
	if _started:
		return false
	_started = true
	return _send(false)


## The check the pilot asked for. Ignored while one is out, so a pilot tapping
## twice does not send two.
func check_on_request() -> bool:
	return _send(true)


## The words for the headset: the offer for an update, and for any other
## status a one-line reason only when the pilot asked; "" for nothing.
static func notice_text(result: Dictionary, asked: bool) -> String:
	var status: String = str(result.get("status", UpdateCheck.STATUS_ERROR))
	if status == UpdateCheck.STATUS_UPDATE_AVAILABLE:
		var release: BuildInfo = BuildInfo.new()
		release.commit = str(result.get("commit", BuildInfo.UNKNOWN))
		release.built_unix = int(result.get("built_unix", 0))
		return NOTICE_AVAILABLE % release.describe()
	if not asked:
		return ""
	var reason: String = str(result.get("reason", ""))
	match status:
		UpdateCheck.STATUS_UP_TO_DATE:
			var latest: BuildInfo = BuildInfo.new()
			latest.commit = str(result.get("commit", BuildInfo.UNKNOWN))
			return NOTICE_UP_TO_DATE % latest.short_commit()
		UpdateCheck.STATUS_UNKNOWN:
			return NOTICE_UNKNOWN % reason
	return NOTICE_ERROR % reason


## The result for a request that failed before any release JSON arrived.
static func failure(reason: String) -> Dictionary:
	return {"status": UpdateCheck.STATUS_ERROR, "reason": reason, "commit": BuildInfo.UNKNOWN,
		"built_unix": 0, "apk_url": "", "sha256_url": ""}


## Why a finished request has no release, or "" when it has one.
static func transport_failure(result: int, http_code: int, timeout_seconds: float) -> String:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "no answer within %s s" % timeout_seconds
	if result != HTTPRequest.RESULT_SUCCESS:
		return "request failed (result %d)" % result
	if http_code != 200:
		return "GitHub answered HTTP %d" % http_code
	return ""


func _send(asked: bool) -> bool:
	if not allowed or in_flight:
		return false
	in_flight = true
	_asked = asked
	requests_sent += 1
	print("%s checking %s (%s)" % [LOG_PREFIX, settings.url, "asked" if asked else "start"])
	var started: int = transport.send(settings.url, HEADERS, settings.timeout_seconds, _on_done)
	if started != OK:
		in_flight = false
		_finish(failure("could not start the request (error %d)" % started))
	return true


func _on_done(result: int, http_code: int, body: String) -> void:
	in_flight = false
	var why: String = transport_failure(result, http_code, settings.timeout_seconds)
	_finish(failure(why) if why != "" else UpdateCheck.evaluate(body, running))


func _finish(result: Dictionary) -> void:
	# Printed, never pushed as an error: a failed check is an expected case.
	print("%s %s %s %s" % [LOG_PREFIX, result["status"], result["commit"], result["reason"]])
	finished.emit(result, _asked)
