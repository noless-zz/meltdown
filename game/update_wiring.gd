class_name UpdateWiring
extends RefCounted

## Joins the in-app update check to the main scene (#646, DEV-8, PLT-1): on
## start it asks once, a tap of the left menu button asks again, and a newer
## build is offered on the status panel with "Update" and "Later". Choosing
## "Update" only emits `update_chosen` for now; the download is #647 and the
## installer hand-off #648. Nothing is installed unless the pilot chooses.
##
## Debug builds on the headset only. A release or store build never makes
## the request, and a desktop debug run only with `ARG`, so CI and the tests
## never reach GitHub. Split from `main.gd` so it gains only a few lines.

## The release the pilot chose to install, as `UpdateCheck.evaluate` gave it.
signal update_chosen(result: Dictionary)

## Desktop or editor: `godot ... -- --update-check`.
const ARG: String = "--update-check"

var request: UpdateRequest = null
var notice: UpdateNotice = null
var tap: MenuTap = MenuTap.new()

var _offered: Dictionary = {}


## Checks whether this build may ask and, if so, wires the real request under
## `host` and the notice under `panel`. Returns whether it did.
func attach(host: Node, panel: Node3D, running: BuildInfo) -> bool:
	var settings: UpdateSettings = UpdateSettings.load_file()
	var platform_ok: bool = OS.has_feature("android") or OS.get_cmdline_user_args().has(ARG)
	if not UpdateRequest.is_allowed(OS.is_debug_build(), settings, platform_ok):
		return false
	attach_with(panel if panel != null else host as Node3D,
		UpdateRequest.new(settings, HttpUpdateTransport.new(host), running, true))
	return true


## The wiring with its parts passed in, so tests can fake the transport.
## Sends the start-up check at once.
func attach_with(notice_parent: Node3D, p_request: UpdateRequest) -> void:
	request = p_request
	request.finished.connect(_on_finished)
	notice = UpdateNotice.new()
	if notice_parent != null:
		notice_parent.add_child(notice)
	notice.update_chosen.connect(_on_update_chosen)
	notice.later_chosen.connect(_on_later_chosen)
	request.check_on_start()


## Once per frame with whether the menu button (or Backspace) is down. A tap
## chooses "Update" while the offer is up and asks for a check otherwise.
func press_menu(held: bool, now: float = MenuTap.steady_seconds()) -> void:
	if request == null or not tap.feed(held, now):
		return
	if not notice.choose_update():
		request.check_on_request()


func _on_finished(result: Dictionary, asked: bool) -> void:
	var text: String = UpdateRequest.notice_text(result, asked)
	if result.get("status", "") == UpdateCheck.STATUS_UPDATE_AVAILABLE:
		_offered = result
		notice.offer(text)
	else:
		notice.tell(text)


func _on_update_chosen() -> void:
	print("%s chosen %s" % [UpdateRequest.LOG_PREFIX, _offered.get("commit", BuildInfo.UNKNOWN)])
	update_chosen.emit(_offered)


func _on_later_chosen() -> void:
	print("%s later %s" % [UpdateRequest.LOG_PREFIX, _offered.get("commit", BuildInfo.UNKNOWN)])
