class_name UpdateWiring
extends RefCounted

## Joins the in-app update check to the main scene (#646, DEV-8, PLT-1): on
## start it asks once, a tap of the left menu button asks again, and a newer
## build is offered on the status panel with "Update" and "Later". Choosing
## "Update" emits `update_chosen` and downloads the build (#647, #673); the
## notice follows the download, and a menu tap while it runs cancels it. A
## checked download is passed on as `update_verified` and, on the headset,
## handed to the package installer (#648); a tap retries a hand-off that
## waits for the install permission or did not start. On the next start the
## notice names the old and new commits once. Nothing is installed unless the
## pilot chooses.
##
## Since #763 the tap opens the dev menu (`DevMenuWiring`) instead: it calls
## `step` each frame, and a waiting build is an entry in that menu
## (`waiting_version`, `choose_waiting`). `press_menu` keeps the tap's old
## meaning for the tests that drive it.
##
## Debug builds on the headset only. A release or store build never makes
## the request, and a desktop debug run only with `ARG`, so CI and the tests
## never reach GitHub. Split from `main.gd` so it gains only a few lines.

## The release the pilot chose to install, as `UpdateCheck.evaluate` gave it.
signal update_chosen(result: Dictionary)
## The downloaded APK matched its published SHA-256; ready for the installer.
signal update_verified(path: String)

## Desktop or editor: `godot ... -- --update-check`.
const ARG: String = "--update-check"

var request: UpdateRequest = null
var notice: UpdateNotice = null
## Null when the wiring was attached without one: then "Update" only emits.
var download: UpdateDownload = null
## Null off Android: then a checked download is only passed on.
var install: UpdateInstall = null
var tap: MenuTap = MenuTap.new()
## Offered each tap first; returning true takes it. The break prompt (#716) sets it.
var tap_taker: Callable = Callable()

var _offered: Dictionary = {}


## Checks whether this build may ask and, if so, wires the real request under
## `host` and the notice under `panel`. Returns whether it did.
func attach(host: Node, panel: Node3D, running: BuildInfo) -> bool:
	var settings: UpdateSettings = UpdateSettings.load_file()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var platform_ok: bool = OS.has_feature("android") or user_args.has(ARG)
	var runtime: Object = InstallerProbe.android_runtime()
	var intent_value: String = InstallerProbe.intent_extra(runtime, AcceptanceRunner.INTENT_EXTRA) if runtime != null else ""
	var suite: String = AcceptanceRunner.requested_suite(user_args, intent_value)
	if not may_attach(OS.is_debug_build(), settings, platform_ok, suite):
		return false
	attach_with(panel if panel != null else host as Node3D,
		UpdateRequest.new(settings, HttpUpdateTransport.new(host), running, true),
		UpdateDownload.new(HttpUpdateDownloader.new(host), UpdateDownload.default_directory()),
		UpdateInstall.new(AndroidInstaller.new(runtime), running) if runtime != null else null)
	return true


## Whether to check at all. Never during an acceptance run: on the headset that
## is an Android debug build too, and an offer appearing mid-suite would show
## in its screenshots and make its runs depend on GitHub.
static func may_attach(is_debug_build: bool, settings: UpdateSettings, platform_ok: bool, acceptance_suite: String) -> bool:
	if acceptance_suite != "":
		return false
	return UpdateRequest.is_allowed(is_debug_build, settings, platform_ok)


## The wiring with its parts passed in, so tests can fake the transport and
## the downloader and the installer. Shows "Updated from ... to ..." when the
## last hand-off replaced the build, then sends the start-up check.
func attach_with(notice_parent: Node3D, p_request: UpdateRequest, p_download: UpdateDownload = null,
		p_install: UpdateInstall = null) -> void:
	request = p_request
	download = p_download
	install = p_install
	if download != null:
		download.changed.connect(_on_download_changed)
		download.ended.connect(_on_download_ended)
		download.verified.connect(_on_download_verified)
	request.finished.connect(_on_finished)
	notice = UpdateNotice.new()
	if notice_parent != null:
		notice_parent.add_child(notice)
	notice.update_chosen.connect(_on_update_chosen)
	notice.later_chosen.connect(_on_later_chosen)
	if install != null:
		var updated: String = UpdateInstall.take_update_message(install.running, install.marker_path)
		if updated != "":
			notice.outcome(updated)
	request.check_on_start()


## Once per frame with whether the menu button (or Backspace) is down. It also
## steps a running download, since this is the wiring's one per-frame call. A
## tap `tap_taker` takes does nothing more; any other tap cancels a running
## download, chooses "Update" while the offer is up, retries an install that
## waits and asks for a check otherwise.
func press_menu(held: bool, now: float = MenuTap.steady_seconds()) -> void:
	var tapped: bool = tap.feed(held, now)  # Fed even without a request, for `tap_taker`.
	if tapped and tap_taker.is_valid() and bool(tap_taker.call()):
		tapped = false
	if request == null:
		return
	step()
	if not tapped:
		return
	if download != null and download.is_busy():
		download.cancel()
	elif notice.choose_update():
		pass
	elif _install_waits():
		_install(install.pending_path)
	else:
		request.check_on_request()


## Once per frame: steps a running download.
func step() -> void:
	if request != null and download_busy():
		download.step()


func download_busy() -> bool:
	return download != null and download.is_busy()


## The short commit of the newer build that waits for the pilot: offered by
## a check (even once the offer has hidden), downloading, or waiting for the
## installer. "" when none does, or when the check is not wired.
func waiting_version() -> String:
	if request == null or _offered.is_empty():
		return ""
	var release: BuildInfo = BuildInfo.new()
	release.commit = str(_offered.get("commit", BuildInfo.UNKNOWN))
	return release.short_commit()


## The menu's update entry was chosen: cancels a running download, retries
## an install that waits, and otherwise takes the offered build, as the tap
## did before #763. Does nothing when no build waits.
func choose_waiting() -> void:
	if waiting_version() == "":
		return
	if download_busy():
		download.cancel()
	elif _install_waits():
		_install(install.pending_path)
	elif not notice.choose_update():
		_on_update_chosen()  # The offer had hidden; the build still waits.


func _on_finished(result: Dictionary, asked: bool) -> void:
	if download != null and download.is_busy():
		return  # The download's progress matters more than a check's answer.
	var text: String = UpdateRequest.notice_text(result, asked)
	if result.get("status", "") == UpdateCheck.STATUS_UPDATE_AVAILABLE:
		_offered = result
		notice.offer(text)
	else:
		notice.tell(text)


func _on_update_chosen() -> void:
	print("%s chosen %s" % [UpdateRequest.LOG_PREFIX, _offered.get("commit", BuildInfo.UNKNOWN)])
	update_chosen.emit(_offered)
	if download != null:
		download.start(_offered)


func _on_later_chosen() -> void:
	print("%s later %s" % [UpdateRequest.LOG_PREFIX, _offered.get("commit", BuildInfo.UNKNOWN)])


func _on_download_changed(text: String) -> void:
	if download.is_busy():
		notice.follow(text)


func _on_download_ended(_status: String, text: String) -> void:
	notice.outcome(text)


func _on_download_verified(path: String) -> void:
	update_verified.emit(path)
	if install != null:
		_install(path)


## After the permission screen or a failed hand-off; not after the installer
## opened, so a later tap checks again instead of reopening it forever.
func _install_waits() -> bool:
	return install != null and install.status in [UpdateInstall.STATUS_ASKED, UpdateInstall.STATUS_FAILED] \
			and install.has_pending()


func _install(path: String) -> void:
	install.install(path)
	notice.outcome(install.text)
