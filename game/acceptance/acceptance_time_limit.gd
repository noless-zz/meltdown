class_name AcceptanceTimeLimit
extends RefCounted

## How long a step may run before the runner fails it and moves on (#1444, DEV-6, DEV-7). On the
## headset one stuck step (`m1/focus_pause`, #1439) once held the suite for the script's whole
## 15 minutes, and nothing after it ran.
##
## A step may set `time_limit_seconds`; otherwise it gets its suite's `default_time_limit_seconds`,
## or DEFAULT_SECONDS when the suite sets none. The default is counted on top of the time the
## step is told to spend waiting (`settle_seconds`, `measure_seconds`, `view_seconds`,
## `pause_seconds`) and the time its replays take to fly, so the 25-minute soak, the measured perf
## steps and the long replays are not cut short by a limit meant for a stuck wait. A step's own
## value is used as written.
##
## The runner flies one tick per rendered frame, so on the headset a replay takes its ticks divided
## by the refresh rate. It is counted at SLOWEST_HZ, the lowest rate the device may fall back to
## (PRF-1): `crew_joins.replay` alone is about 146 s there. Headless runs are not frame-capped and
## would never show a limit that is too short.
##
## The clock is wall time, not ticks: a stuck step may fly no ticks at all.

const KEY: String = "time_limit_seconds"
const SUITE_KEY: String = "default_time_limit_seconds"
const DEFAULT_SECONDS: float = 120.0
## Not set on the step: the suite's default applies.
const UNSET: float = 0.0
## The lowest refresh rate a replay's ticks are flown at on the device (PRF-1: 90 Hz, 72 Hz fallback).
const SLOWEST_HZ: float = 72.0


## Reads the step's `time_limit_seconds`, if any, into `step.time_limit_seconds`.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	if not data.has(KEY):
		return ""
	var problem: String = _positive(data[KEY], "%s.%s" % [field, KEY])
	if problem == "":
		step.time_limit_seconds = float(data[KEY])
	return problem


## The suite file's default limit, or DEFAULT_SECONDS; `problem` gets why the value is bad.
static func parse_suite(data: Dictionary, problem: Array[String]) -> float:
	if not data.has(SUITE_KEY):
		return DEFAULT_SECONDS
	var bad: String = _positive(data[SUITE_KEY], SUITE_KEY)
	if bad != "":
		problem.append(bad)
		return DEFAULT_SECONDS
	return float(data[SUITE_KEY])


## The seconds `step` may run in a suite whose default is `suite_default`. Reads the step's replay
## files, so the runner works out the deadline once, when the step starts.
static func seconds_for(step: AcceptanceStep, suite_default: float) -> float:
	if step.time_limit_seconds > UNSET:
		return step.time_limit_seconds
	return suite_default + step.settle_seconds + step.measure_seconds + step.view_seconds + step.pause_seconds \
		+ flight_seconds(step)


## The `clock` time at which `step` of `suite` fails. The replay files are read before the clock,
## so reading them is not charged to the step.
static func deadline_msec(step: AcceptanceStep, suite: AcceptanceSuite, clock: Callable) -> int:
	var limit_msec: int = int(seconds_for(step, suite.default_time_limit_seconds) * 1000.0)
	return int(clock.call()) + limit_msec


## The seconds the step's replay and `next_replay` take to fly at SLOWEST_HZ. A looped replay
## flies for `measure_seconds`, which is already counted; a replay that cannot be read counts as
## none, and the step reports why it could not fly.
static func flight_seconds(step: AcceptanceStep) -> float:
	if step.loop_replay:
		return 0.0
	var ticks: int = 0
	for path: String in [step.replay_path, step.next_replay_path]:
		if path == "":
			continue
		var replay: Replay = Replay.load_file(path)
		if replay.error == "":
			ticks += replay.frames.size()
	return float(ticks) / SLOWEST_HZ


## The step's failure message, as the issue words it.
static func message(limit_seconds: float, tick: int) -> String:
	return "timed out after %s s at tick %d" % [format_seconds(limit_seconds), tick]


## "120" for a whole number of seconds, "2.5" otherwise.
static func format_seconds(seconds: float) -> String:
	if seconds == floorf(seconds):
		return str(int(seconds))
	return str(snappedf(seconds, 0.1))


static func _positive(value: Variant, field: String) -> String:
	if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) \
			or float(value) <= 0.0:
		return "%s: must be a number of seconds above 0" % field
	return ""
