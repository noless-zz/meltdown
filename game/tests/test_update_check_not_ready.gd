extends RefCounted

## A `main-latest` release whose body names a commit its APK is not (#1202,
## DEV-8): the check answers "not ready", never "update available", so the
## headset cannot install the old APK and be offered the same update again.
## The two-halves fixture rebuilds the release of 22 Nov as the issue records it:
## body from the server-only step for d0b568b, built 06:58 UTC; APK uploaded at
## 06:43 UTC by the run for 719b634.

const TWO_HALVES: String = "res://tests/fixtures/main_latest_release_two_halves.json"
const WHOLE: String = "res://tests/fixtures/main_latest_release.json"
const BODY_COMMIT: String = "d0b568b9357991d4da3ff8dbd757110b41e917a9"
const APK_COMMIT: String = "719b634ef59fe7ca59a534f8d71cf77be209f1cf"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
const WHOLE_BODY: String = "Latest Quest APK (debug), desktop client and dedicated server from main, commit %s. Replaced on every push; not a versioned release.\n\nBuilt: %s UTC (Asia/Jerusalem)"


static func _running(commit: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	info.commit = commit
	return info


static func _release(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The two-halves release with its body replaced by the text the whole publish
## writes, built at `built` ("YYYY-MM-DD HH:MM"), and its APK uploaded at `apk_at`.
static func _whole(built: String, apk_at: String) -> String:
	var release: Dictionary = _release(TWO_HALVES)
	release["body"] = WHOLE_BODY % [BODY_COMMIT, built]
	for asset: Dictionary in release["assets"]:
		if asset["name"] == UpdateCheck.APK_ASSET:
			asset["created_at"] = apk_at
			asset["updated_at"] = apk_at
	return JSON.stringify(release)


static func _expect(result: Dictionary, status: String) -> String:
	if result["status"] != status:
		return "status is '%s' (%s), expected '%s'" % [result["status"], result["reason"], status]
	return ""


func test_the_two_halves_release_is_not_ready() -> String:
	var json: String = FileAccess.get_file_as_string(TWO_HALVES)
	# The headset that looped ran the APK's own build; any other build too.
	for running: String in [APK_COMMIT, OTHER_COMMIT]:
		var result: Dictionary = UpdateCheck.evaluate(json, _running(running))
		var message: String = _expect(result, UpdateCheck.STATUS_NOT_READY)
		if message != "":
			return "running %s: %s" % [running.left(7), message]
		if result["commit"] != BODY_COMMIT:
			return "commit is '%s'" % result["commit"]
		if String(result["reason"]) == "":
			return "not ready without a reason"
	return ""


func test_the_server_only_body_alone_is_not_ready() -> String:
	var release: Dictionary = _release(TWO_HALVES)
	for asset: Dictionary in release["assets"]:
		asset.erase("created_at")
		asset.erase("updated_at")
	var result: Dictionary = UpdateCheck.evaluate(JSON.stringify(release), _running(APK_COMMIT))
	return _expect(result, UpdateCheck.STATUS_NOT_READY)


func test_an_apk_older_than_the_build_is_not_ready() -> String:
	# The whole text but the 06:43 APK under a 06:58 stamp: still two halves.
	var json: String = _whole("2026-11-22 06:58", "2026-11-22T06:43:22Z")
	return _expect(UpdateCheck.evaluate(json, _running(APK_COMMIT)), UpdateCheck.STATUS_NOT_READY)


func test_a_whole_release_is_an_update() -> String:
	# The stamp rounds down to the minute and is taken after the APK upload, in
	# a job of at most 10 minutes: an APK in the stamp's minute, in the minute
	# before it, or exactly 10 minutes before it is this build's.
	for apk_at: String in ["2026-11-22T06:58:49Z", "2026-11-22T06:57:55Z", "2026-11-22T06:48:00Z"]:
		var json: String = _whole("2026-11-22 06:58", apk_at)
		var result: Dictionary = UpdateCheck.evaluate(json, _running(APK_COMMIT))
		var message: String = _expect(result, UpdateCheck.STATUS_UPDATE_AVAILABLE)
		if message != "":
			return "APK at %s: %s" % [apk_at, message]
	return ""


func test_the_trimmed_fixture_without_upload_times_is_still_an_update() -> String:
	var json: String = FileAccess.get_file_as_string(WHOLE)
	return _expect(UpdateCheck.evaluate(json, _running(OTHER_COMMIT)),
			UpdateCheck.STATUS_UPDATE_AVAILABLE)


func test_the_running_body_commit_is_up_to_date_even_mid_publish() -> String:
	var json: String = FileAccess.get_file_as_string(TWO_HALVES)
	return _expect(UpdateCheck.evaluate(json, _running(BODY_COMMIT)), UpdateCheck.STATUS_UP_TO_DATE)


func test_not_ready_shows_no_offer_and_a_line_only_when_asked() -> String:
	var json: String = FileAccess.get_file_as_string(TWO_HALVES)
	var result: Dictionary = UpdateCheck.evaluate(json, _running(APK_COMMIT))
	if UpdateRequest.notice_text(result, false) != "":
		return "an unasked check shows '%s'" % UpdateRequest.notice_text(result, false)
	var asked: String = UpdateRequest.notice_text(result, true)
	if asked != UpdateRequest.NOTICE_UNKNOWN % result["reason"]:
		return "an asked check shows '%s'" % asked
	return ""


func test_the_start_up_check_offers_no_update_row() -> String:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	fake.body = FileAccess.get_file_as_string(TWO_HALVES)
	var panel: Node3D = Node3D.new()
	var wiring: UpdateWiring = UpdateWiring.new()
	wiring.attach_with(panel, UpdateRequest.new(settings, fake, _running(APK_COMMIT), true))
	var message: String = ""
	if fake.urls.size() != 1:
		message = "the start-up check sent %d requests" % fake.urls.size()
	elif wiring.notice.offering or wiring.notice.is_showing():
		message = "the notice shows '%s'" % wiring.notice.line_text()
	panel.free()
	return message
