class_name XrSmokeProbe
extends RefCounted

## Quit-after-N-frames switch for automated runs (issue #26, PLT-2).
##
## CI starts the game against a simulated headset, lets it render a fixed
## number of frames and reads one line that says whether an OpenXR session
## came up. The switch is off unless `--xr-smoke-frames=<N>` is passed after
## `--` on the command line, so a normal start never quits by itself.

const ARG_PREFIX: String = "--xr-smoke-frames="
const LINE_PREFIX: String = "MELTDOWN_XR_SMOKE "
## Progress lines, so `tools/xr_smoke.sh` can time the phases and a run that
## runs out of time shows how far it got (issue #727).
const FRAME_PREFIX: String = "MELTDOWN_XR_SMOKE_FRAME "
const FRAME_EVERY: int = 30

var _frames_total: int = 0
var _frames_seen: int = 0
var _left_tracked: bool = false
var _right_tracked: bool = false


## Frame count asked for on the command line; 0 means the switch is off.
## Anything that is not a whole number above zero counts as off, because a
## typo must not make a player's game quit.
static func frames_from_args(args: PackedStringArray) -> int:
	var frames: int = 0
	for arg: String in args:
		if not arg.begins_with(ARG_PREFIX):
			continue
		var value: String = arg.substr(ARG_PREFIX.length())
		frames = int(value) if value.is_valid_int() and int(value) > 0 else 0
	return frames


## One line a shell script can find and parse: the prefix, then JSON.
## The hand flags default to false so a caller that never watched the hands
## cannot claim tracking (issue #559).
static func format_line(session: bool, runtime: String, views: int, refresh_rate: float, frames: int,
		left_tracked: bool = false, right_tracked: bool = false) -> String:
	var report: Dictionary = {
		"session": session,
		"runtime": runtime,
		"views": views,
		"refresh_rate": refresh_rate,
		"frames": frames,
		"left_tracked": left_tracked,
		"right_tracked": right_tracked,
	}
	return LINE_PREFIX + JSON.stringify(report)


func _init(frames: int = 0) -> void:
	_frames_total = maxi(frames, 0)


func is_enabled() -> bool:
	return _frames_total > 0


func frames_seen() -> int:
	return _frames_seen


func left_tracked() -> bool:
	return _left_tracked


func right_tracked() -> bool:
	return _right_tracked


## Records this frame's hand state. A hand counts as tracked once it has
## reported a pose on any frame, because a simulated controller may drop out
## again before the run ends and the question is whether tracking works at all.
func note_hands(left: bool, right: bool) -> void:
	if not is_enabled():
		return
	_left_tracked = _left_tracked or left
	_right_tracked = _right_tracked or right


## Asks both controller nodes whether their tracker has a pose this frame.
## A missing node counts as untracked.
func watch_hands(left: XRController3D, right: XRController3D) -> void:
	note_hands(left != null and left.get_has_tracking_data(),
		right != null and right.get_has_tracking_data())


## The progress line for a frame, or "" when that frame prints none: the
## first frame marks the end of start-up, every FRAME_EVERY-th one shows the
## pace. `msec` is the engine's own clock since start.
static func progress_line(frame: int, msec: int) -> String:
	if frame != 1 and (frame <= 0 or frame % FRAME_EVERY != 0):
		return ""
	return FRAME_PREFIX + JSON.stringify({"frame": frame, "msec": msec})


## Counts one frame. Returns true exactly once, on the frame that reaches the
## requested count; a disabled probe never returns true.
func tick() -> bool:
	if not is_enabled() or _frames_seen >= _frames_total:
		return false
	_frames_seen += 1
	var line: String = XrSmokeProbe.progress_line(_frames_seen, Time.get_ticks_msec())
	if not line.is_empty():
		print(line)
	return _frames_seen == _frames_total


## Reads what the runtime reports at the moment of quitting, so the line shows
## the state after the frames ran and not what was hoped for at start.
func report(session_begun: bool) -> String:
	var runtime: String = ""
	var views: int = 0
	var refresh_rate: float = 0.0
	var openxr: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if openxr != null and openxr.is_initialized():
		runtime = str(openxr.get_system_info().get("XRRuntimeName", ""))
		views = openxr.get_view_count()
		refresh_rate = openxr.display_refresh_rate
	return XrSmokeProbe.format_line(session_begun, runtime, views, refresh_rate, frames_seen(),
		_left_tracked, _right_tracked)
