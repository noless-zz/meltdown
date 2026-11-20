class_name ViewLog
extends RefCounted

## A once-a-second `MELTDOWN_VIEW` line on the device log while flying, so
## the owner can send it if the view ever goes dark again (#651). Off unless
## the `--view-log` command-line switch, the `meltdown/debug/view_log`
## project setting or, on the Quest, the `meltdown_view_log` intent extra
## (#671) turns it on: the log stays quiet otherwise.
##
## It only formats copies of values it is handed; it never reads or writes
## simulation state (ARC-3, MP-2).

const PREFIX: String = "MELTDOWN_VIEW"
const SWITCH: String = "--view-log"
const SETTING: String = "meltdown/debug/view_log"
## The intent extra the headset is started with, as `meltdown_level` is:
## `adb shell am start ... --es meltdown_view_log 1` (#671).
const INTENT_EXTRA: String = "meltdown_view_log"
## Intent values that turn the log on, compared without case.
const INTENT_ON: Array[String] = ["1", "true"]
## Seconds between two sample lines.
const PERIOD_S: float = 1.0

var enabled: bool = false
## Every line logged, so tests can read them.
var lines: PackedStringArray = PackedStringArray()

## Clock time the next sample line is due; below 0 before the first.
var _next_s: float = -1.0


## On when `args` holds the switch, `setting` is true or `intent` (the
## intent extra's value, "" when absent) is `1` or `true`. Any one is enough.
static func enabled_by(args: PackedStringArray, setting: Variant, intent: String = "") -> bool:
	return args.has(SWITCH) or (typeof(setting) == TYPE_BOOL and bool(setting)) \
		or INTENT_ON.has(intent.strip_edges().to_lower())


## A log switched on or off from this run's command line, project setting
## and, on Android, the intent extra.
static func from_run() -> ViewLog:
	var view_log: ViewLog = ViewLog.new()
	view_log.enabled = enabled_by(OS.get_cmdline_args() + OS.get_cmdline_user_args(),
		ProjectSettings.get_setting(SETTING, false), intent_value())
	return view_log


## The `meltdown_view_log` extra of the intent that started the game, or ""
## off Android or when it is absent. The same reading as
## `InstallerProbe.intent_extra`, repeated here because `xr/` may not depend
## on `meta/` (CLAUDE.md layer table).
static func intent_value() -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var activity: Object = Engine.get_singleton("AndroidRuntime").call("getActivity")
	var intent: Object = activity.call("getIntent") if activity != null else null
	var value: Variant = intent.call("getStringExtra", INTENT_EXTRA) if intent != null else null
	return value if value is String else ""


## Logs one sample line made from `values` if the log is on and a second has
## passed since the last one. Returns true when it logged.
func sample(now_s: float, values: Dictionary) -> bool:
	if not enabled or (_next_s >= 0.0 and now_s < _next_s):
		return false
	_next_s = now_s + PERIOD_S
	_log(sample_line(values))
	return true


## Logs `text` at once, if the log is on: a preset change, a re-placement.
func event(text: String) -> void:
	if enabled:
		_log("%s event %s" % [PREFIX, text])


## One sample line: the prefix, then each key=value of `values` in key order,
## floats with three decimals, so lines from two runs line up.
static func sample_line(values: Dictionary) -> String:
	var keys: Array = values.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray([PREFIX])
	for key: Variant in keys:
		var value: Variant = values[key]
		var shown: String = "%.3f" % value if typeof(value) == TYPE_FLOAT else str(value)
		parts.append("%s=%s" % [key, shown])
	return " ".join(parts)


## The values one sample shows: how far the head looks and sits from the
## frame, the shake, how long ago the frame was placed and why, the preset,
## the hull and whether the head is tracked.
static func values(guard: ViewGuard, head: Transform3D, shake: Transform3D, preset: int,
		hull: float, tracked: bool, now_s: float) -> Dictionary:
	var angles: Vector2 = ViewGuard.window_angles(guard.frame_point, head)
	return {
		"head_to_window_deg": ViewGuard.angle_to_window_deg(guard.frame_point, head),
		"head_yaw_deg": angles.x,
		"head_pitch_deg": angles.y,
		"head_offset_m": ViewGuard.head_distance_m(guard.frame_point, head),
		"shake_offset_m": shake.origin.length(),
		"frame_placed_age_s": guard.placed_age_s(now_s),
		"frame_placed_by": guard.reason.replace(" ", "_"),
		"replacements": guard.replacements,
		"preset": preset,
		"hull": hull,
		"tracked": tracked,
	}


func _log(line: String) -> void:
	lines.append(line)
	print(line)
