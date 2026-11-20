class_name UpdateInstall
extends RefCounted

## Hands a checked download to the Android package installer (#648, DEV-8,
## PLT-1) by the path the installer probe proved (#595), and tells the pilot
## on the next start which build replaced which.
##
## Before the hand-off it asks whether this app may install packages; if not,
## it says the headset will ask and opens the system screen, and the pilot taps
## Menu again once installs are allowed. The running build's commit is saved
## under `user://` just before the hand-off, so the new build can compare it
## with its own. The APK is never deleted here: if the installer does not
## start, it stays for a retry. The Android calls go through an
## `UpdateInstallBridge`, so tests can fake them.

const LOG_PREFIX: String = "MELTDOWN_UPDATE"
const DEFAULT_MARKER_PATH: String = "user://meltdown_last_build.json"

const STATUS_IDLE: String = "idle"
const STATUS_STARTED: String = "started"
const STATUS_ASKED: String = "asked_permission"
const STATUS_FAILED: String = "failed"

const TEXT_STARTED: String = "Opening the installer..."
const TEXT_ASK: String = "The headset will ask to allow installs from this app; then tap Menu"
const TEXT_NOT_STARTED: String = "Installer did not start: %s. Tap Menu to retry"
const TEXT_UPDATED: String = "Updated from %s to %s"

var bridge: UpdateInstallBridge
var running: BuildInfo
var marker_path: String
var status: String = STATUS_IDLE
## The line for the update notice after the last `install()`.
var text: String = ""
## The checked APK last handed over, kept so a tap can retry it.
var pending_path: String = ""


func _init(p_bridge: UpdateInstallBridge, p_running: BuildInfo, p_marker_path: String = DEFAULT_MARKER_PATH) -> void:
	bridge = p_bridge
	running = p_running
	marker_path = p_marker_path


## Whether a checked APK waits for a retry: after asking for the permission,
## after a failed hand-off, or after the pilot backed out of the installer.
func has_pending() -> bool:
	return pending_path != "" and FileAccess.file_exists(pending_path)


## Hands `apk_path` to the installer, or asks for the permission first.
## Returns the new `status`; `text` says what happened.
func install(apk_path: String) -> String:
	pending_path = apk_path
	bridge.failure = ""
	var allowed: int = bridge.may_install()
	if allowed == UpdateInstallBridge.NOT_ALLOWED:
		print("%s install not allowed yet, asking" % LOG_PREFIX)
		bridge.failure = ""
		if not bridge.ask_install_permission():
			return _not_started("permission screen: " + _reason())
		return _done(STATUS_ASKED, TEXT_ASK)
	if allowed == UpdateInstallBridge.UNKNOWN:
		# The installer asks for the permission itself if it is missing, so a
		# failed check is no reason to stop.
		print("%s install permission unknown (%s), trying the installer" % [LOG_PREFIX, _reason()])
	save_marker()
	bridge.failure = ""
	var uri: String = bridge.content_uri(apk_path)
	if uri == "":
		return _not_started("content URI: " + _reason())
	print("%s content URI %s" % [LOG_PREFIX, uri])
	bridge.failure = ""
	if not bridge.start_installer():
		return _not_started("intent: " + _reason())
	return _done(STATUS_STARTED, TEXT_STARTED)


## Saves the running build's commit for the next start to compare.
func save_marker() -> bool:
	var file: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
	if file == null:
		print("%s could not save %s (%s)" % [LOG_PREFIX, marker_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({"commit": running.commit}))
	file.close()
	return true


## Reads and clears the commit saved before the last hand-off. Returns
## "Updated from <old> to <new>" when it differs from `now_running`, "" when
## nothing was saved, either commit is unknown or the build did not change.
## The marker is removed either way, so the message shows once.
static func take_update_message(now_running: BuildInfo, path: String = DEFAULT_MARKER_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_commit: String = str(data.get("commit", ""))
	var old: BuildInfo = BuildInfo.new()
	if BuildInfo.is_full_commit(saved_commit):
		old.commit = saved_commit.to_lower()
	if old.commit == BuildInfo.UNKNOWN or now_running.commit == BuildInfo.UNKNOWN \
			or old.commit == now_running.commit:
		return ""
	var message: String = TEXT_UPDATED % [old.short_commit(), now_running.short_commit()]
	print("%s %s (%s -> %s)" % [LOG_PREFIX, message, old.commit, now_running.commit])
	return message


func _not_started(reason: String) -> String:
	# Nothing was handed over, so the next start must not claim an update.
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path))
	return _done(STATUS_FAILED, TEXT_NOT_STARTED % reason)


func _done(new_status: String, new_text: String) -> String:
	status = new_status
	text = new_text
	print("%s install %s: %s" % [LOG_PREFIX, status, text])
	return status


func _reason() -> String:
	return bridge.failure if bridge.failure != "" else "no reason given"
