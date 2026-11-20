extends RefCounted

## The in-app update check asks GitHub only from debug builds with the data
## file's flag on, once per start and once per ask, never retrying, and turns
## each answer into the words the headset shows (#646, DEV-8, PLT-1).

const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
const RELEASE_COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
const URL: String = "https://example.invalid/releases/tags/main-latest"


static func _settings(enabled: bool = true, timeout: float = 7.0) -> UpdateSettings:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = enabled
	settings.url = URL
	settings.timeout_seconds = timeout
	return settings


static func _running(commit: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	info.commit = commit
	return info


static func _fake(code: int = 200) -> FakeUpdateTransport:
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	fake.body = FileAccess.get_file_as_string(FIXTURE)
	fake.http_code = code
	return fake


## Runs one start-up check (or an asked one) and returns [result, asked].
static func _run(fake: FakeUpdateTransport, running: String, asked: bool) -> Array:
	var request: UpdateRequest = UpdateRequest.new(_settings(), fake, _running(running), true)
	var got: Array = []
	request.finished.connect(func(result: Dictionary, was_asked: bool) -> void:
		got.append(result)
		got.append(was_asked))
	if asked:
		request.check_on_request()
	else:
		request.check_on_start()
	return got


func test_release_builds_never_ask() -> String:
	if UpdateRequest.is_allowed(false, _settings(), true):
		return "a release build is allowed to ask"
	var fake: FakeUpdateTransport = _fake()
	var request: UpdateRequest = UpdateRequest.new(_settings(), fake, _running(OTHER_COMMIT), false)
	request.check_on_start()
	request.check_on_request()
	if request.requests_sent != 0 or not fake.urls.is_empty():
		return "a build that is not allowed sent %d requests" % fake.urls.size()
	return ""


func test_the_data_file_flag_turns_the_check_off() -> String:
	if UpdateRequest.is_allowed(true, _settings(false), true):
		return "a debug build with the flag off is allowed to ask"
	var fake: FakeUpdateTransport = _fake()
	var request: UpdateRequest = UpdateRequest.new(_settings(false), fake, _running(OTHER_COMMIT), true)
	request.check_on_start()
	request.check_on_request()
	if not fake.urls.is_empty():
		return "the flag was off and %d requests went out" % fake.urls.size()
	if not UpdateRequest.is_allowed(true, _settings(), true):
		return "a debug build with the flag on may not ask"
	if UpdateRequest.is_allowed(true, _settings(), false):
		return "a desktop run that did not ask for the check is allowed to"
	return ""


func test_one_request_per_start_with_the_data_file_url_and_timeout() -> String:
	var fake: FakeUpdateTransport = _fake()
	var request: UpdateRequest = UpdateRequest.new(_settings(true, 7.0), fake, _running(OTHER_COMMIT), true)
	if not request.check_on_start():
		return "the start-up check did not go out"
	request.check_on_start()
	request.check_on_start()
	if fake.urls != [URL]:
		return "start-up sent %s" % [fake.urls]
	if fake.timeouts != [7.0]:
		return "the timeout passed was %s" % [fake.timeouts]
	if not "User-Agent: meltdown-update-check" in fake.headers[0]:
		return "no user agent, which GitHub requires"
	request.check_on_request()
	if fake.urls.size() != 2:
		return "asking after start sent %d requests in all, expected 2" % fake.urls.size()
	return ""


func test_an_ask_while_one_is_out_sends_nothing() -> String:
	var fake: FakeUpdateTransport = _fake()
	fake.deferred = true
	var request: UpdateRequest = UpdateRequest.new(_settings(), fake, _running(OTHER_COMMIT), true)
	request.check_on_start()
	request.check_on_request()
	if fake.urls.size() != 1:
		return "an ask during the start-up request sent another"
	fake.answer()
	if request.in_flight:
		return "still in flight after the answer"
	request.check_on_request()
	return "" if fake.urls.size() == 2 else "an ask after the answer sent nothing"


func test_a_timeout_is_an_error_with_no_retry() -> String:
	var fake: FakeUpdateTransport = _fake()
	fake.result = HTTPRequest.RESULT_TIMEOUT
	var got: Array = _run(fake, OTHER_COMMIT, false)
	if got.is_empty() or got[0]["status"] != UpdateCheck.STATUS_ERROR:
		return "a timeout gave %s" % [got]
	if not str(got[0]["reason"]).contains("within 7"):
		return "the reason does not name the timeout: %s" % got[0]["reason"]
	if fake.urls.size() != 1:
		return "a timeout was retried: %d requests" % fake.urls.size()
	if UpdateRequest.notice_text(got[0], false) != "":
		return "a failed start-up check showed something"
	return ""


func test_a_request_that_cannot_start_is_an_error() -> String:
	var fake: FakeUpdateTransport = _fake()
	fake.start_error = ERR_CANT_CONNECT
	var got: Array = _run(fake, OTHER_COMMIT, true)
	if got.is_empty() or got[0]["status"] != UpdateCheck.STATUS_ERROR:
		return "a request that did not start gave %s" % [got]
	return "" if fake.urls.size() == 1 else "it was retried"


func test_update_available_is_offered_with_commit_and_date() -> String:
	var got: Array = _run(_fake(), OTHER_COMMIT, false)
	var want: String = "Update available: e1b0a77, built 2026-11-15 19:07 UTC"
	var text: String = UpdateRequest.notice_text(got[0], false)
	if text != want:
		return "start-up notice was '%s', expected '%s'" % [text, want]
	if UpdateRequest.notice_text(got[0], true) != want:
		return "the asked notice differs from the start-up one"
	return ""


func test_up_to_date_shows_only_when_asked() -> String:
	var got: Array = _run(_fake(), RELEASE_COMMIT, true)
	if got[0]["status"] != UpdateCheck.STATUS_UP_TO_DATE or got[1] != true:
		return "the same commit gave %s" % [got]
	if UpdateRequest.notice_text(got[0], false) != "":
		return "up to date showed something on start"
	var text: String = UpdateRequest.notice_text(got[0], true)
	return "" if text == "Up to date: e1b0a77" else "asked up-to-date line was '%s'" % text


func test_unknown_shows_only_when_asked() -> String:
	var got: Array = _run(_fake(), BuildInfo.UNKNOWN, true)
	if got[0]["status"] != UpdateCheck.STATUS_UNKNOWN:
		return "an unknown running commit gave %s" % got[0]["status"]
	if UpdateRequest.notice_text(got[0], false) != "":
		return "unknown showed something on start"
	var text: String = UpdateRequest.notice_text(got[0], true)
	return "" if text == "Update check: the running build's commit is unknown" else "asked line was '%s'" % text


func test_an_http_error_shows_only_when_asked() -> String:
	var got: Array = _run(_fake(404), OTHER_COMMIT, true)
	if got[0]["status"] != UpdateCheck.STATUS_ERROR:
		return "HTTP 404 gave %s" % got[0]["status"]
	if UpdateRequest.notice_text(got[0], false) != "":
		return "an error showed something on start"
	var text: String = UpdateRequest.notice_text(got[0], true)
	return "" if text == "Update check failed: GitHub answered HTTP 404" else "asked line was '%s'" % text
