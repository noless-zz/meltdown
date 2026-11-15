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

var _frames_total: int = 0
var _frames_seen: int = 0


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
static func format_line(session: bool, runtime: String, views: int, refresh_rate: float, frames: int) -> String:
	var report: Dictionary = {
		"session": session,
		"runtime": runtime,
		"views": views,
		"refresh_rate": refresh_rate,
		"frames": frames,
	}
	return LINE_PREFIX + JSON.stringify(report)


func _init(frames: int = 0) -> void:
	_frames_total = maxi(frames, 0)


func is_enabled() -> bool:
	return _frames_total > 0


func frames_seen() -> int:
	return _frames_seen


## Counts one frame. Returns true exactly once, on the frame that reaches the
## requested count; a disabled probe never returns true.
func tick() -> bool:
	if not is_enabled() or _frames_seen >= _frames_total:
		return false
	_frames_seen += 1
	return _frames_seen == _frames_total
