class_name AcceptanceEscapeCueCheck
extends RefCounted

## The `escape_cue` acceptance check (#885, RUN-2, RUN-3, RUN-5, MAP-2, CMF-8):
## the cockpit's meltdown cue (#617, #695) as the running game shows it, which
## `test_main_escape_cue.gd` only shows on hand-built states. After every
## replay tick it reads the scene's `EscapeCueWiring` and judges, naming the
## first tick that broke a rule:
##
## - before the reactor dies, no part of the cue shows;
## - during the meltdown the large countdown shows on every tick its look says
##   it is due (`MeltdownCue.large_visible`: the first seconds after the death
##   and the last stretch; the status panel's small row covers the gap), its
##   seconds never go up, and they never differ from the simulation's meltdown
##   ticks left by more than one second;
## - whenever the map has a route, the arrow shows and points within
##   `MAX_ARROW_DEGREES` of the direction from where the arrow hangs in the
##   world to the route's next point. Not from the ship's centre: the arrow hangs
##   away from it in the cockpit, so near a corner the two directions part by
##   more than the limit (5.2 degrees on seed 43), and once the ship's centre
##   has passed a corner before the next quarter-second search, by far more.
## - once the run has escaped, no part of the cue shows.
##
## It reads the scene; it writes nothing, so every hash of the step stands.

const MAX_ARROW_DEGREES: float = 5.0
const MAX_SECONDS_OFF: float = 1.0

## One sample per tick, as `sample_main` builds it and the unit tests hand-feed it.
const KEY_TICK: String = "tick"
const KEY_REACTOR_DEAD: String = "reactor_dead"
const KEY_RUNNING: String = "running"  # The run is neither escaped nor lost.
const KEY_ESCAPED: String = "escaped"
const KEY_CUE_SHOWN: String = "cue_shown"  # The countdown, its line or the arrow shows.
const KEY_COUNTDOWN_DUE: String = "countdown_due"
const KEY_COUNTDOWN_SHOWN: String = "countdown_shown"
const KEY_COUNTDOWN_SECONDS: String = "countdown_seconds"  # Whole seconds its text reads, or -1.
const KEY_SECONDS_LEFT: String = "seconds_left"  # The simulation's meltdown ticks left, in seconds.
const KEY_HAS_ROUTE: String = "has_route"
const KEY_ARROW_SHOWN: String = "arrow_shown"
const KEY_ARROW_DEGREES: String = "arrow_degrees"  # Off the arrow-to-next-point direction.

var samples: Array[Dictionary] = []

var _session: LocalSession = null
var _death_tick: int = -1


## A check for `step`, or null when the step does not list `escape_cue`.
static func for_step(step: AcceptanceStep) -> AcceptanceEscapeCueCheck:
	if not step.has_check(AcceptanceStep.CHECK_ESCAPE_CUE):
		return null
	return AcceptanceEscapeCueCheck.new()


## Samples `main`'s cue after a replay tick. A scene without a cockpit (no
## status panel, so the cue has nowhere to hang) adds nothing, and the check
## then fails for want of samples.
func sample_main(main: Node) -> void:
	var meltdown: MeltdownWiring = main.get("meltdown") as MeltdownWiring
	var session: LocalSession = main.get("session") as LocalSession
	if meltdown == null or session == null or main.get("status_panel") == null:
		return
	if session != _session:
		_session = session
		_death_tick = -1
	var wiring: EscapeCueWiring = meltdown.escape
	var cue: MeltdownCue = wiring.cue
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	var dead: bool = reactor != null and reactor.destroyed
	var tick: int = session.sim.tick
	if dead and _death_tick < 0:
		_death_tick = tick
	var seconds_left: float = MeltdownWiring.seconds_left(reactor) if dead else -1.0
	var elapsed: float = float(tick - _death_tick) / float(ReactorState.TICKS_PER_SECOND) if dead else 0.0
	var route: KnownRoute = wiring.route
	var has_route: bool = route != null and route.points_mm.size() >= 2
	var countdown_shown: bool = cue != null and cue.countdown.visible
	var arrow_shown: bool = cue != null and cue.arrow.visible
	var degrees: float = -1.0
	if has_route and arrow_shown:
		var next: Vector3 = Vector3(route.points_mm[1]) / float(RobotSpawn.SCALE)
		var world_from_cue: Transform3D = wiring.world_from_cue()
		var want: Vector3 = next - world_from_cue * cue.arrow.position
		if want.length_squared() > 1e-8:
			degrees = rad_to_deg(cue.arrow_direction(world_from_cue).angle_to(want))
	samples.append({
		KEY_TICK: tick,
		KEY_REACTOR_DEAD: dead,
		KEY_RUNNING: session.sim.outcome() == ExitRule.Outcome.RUNNING,
		KEY_ESCAPED: session.sim.outcome() == ExitRule.Outcome.ESCAPED,
		KEY_CUE_SHOWN: countdown_shown or arrow_shown or (cue != null and cue.line.visible),
		KEY_COUNTDOWN_DUE: dead and MeltdownCue.large_visible(elapsed, seconds_left, EscapeCueLook.shared()),
		KEY_COUNTDOWN_SHOWN: countdown_shown,
		KEY_COUNTDOWN_SECONDS: read_seconds(cue.countdown.text) if countdown_shown else -1,
		KEY_SECONDS_LEFT: seconds_left,
		KEY_HAS_ROUTE: has_route,
		KEY_ARROW_SHOWN: arrow_shown,
		KEY_ARROW_DEGREES: degrees,
	})


## Whole seconds in a countdown's "m:ss" text, or -1 when it is not one.
static func read_seconds(text: String) -> int:
	var parts: PackedStringArray = text.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	return int(parts[0]) * 60 + int(parts[1])


## [result, message] for the samples taken, adding the measurements.
func run(measurements: Dictionary) -> Array:
	return judge(samples, measurements)


## [result, message] for `taken`, adding the measurements.
static func judge(taken: Array[Dictionary], measurements: Dictionary) -> Array:
	var meltdown: int = 0
	var shown: int = 0
	var pointed: int = 0
	var worst: float = 0.0
	var last_seconds: int = -1
	var escaped: bool = false
	var failure: String = ""
	for sample: Dictionary in taken:
		var problem: String = ""
		var cue_shown: bool = bool(sample[KEY_CUE_SHOWN])
		if not bool(sample[KEY_REACTOR_DEAD]):
			if cue_shown:
				problem = "a cue shows before the reactor died"
		elif bool(sample[KEY_ESCAPED]):
			escaped = true
			if cue_shown:
				problem = "a cue still shows after the escape"
		elif bool(sample[KEY_RUNNING]):
			meltdown += 1
			problem = _countdown_problem(sample, last_seconds)
			if bool(sample[KEY_COUNTDOWN_SHOWN]):
				shown += 1
				last_seconds = int(sample[KEY_COUNTDOWN_SECONDS])
			if problem == "" and bool(sample[KEY_HAS_ROUTE]):
				var degrees: float = float(sample[KEY_ARROW_DEGREES])
				if not bool(sample[KEY_ARROW_SHOWN]):
					problem = "the arrow is hidden while the map has a route"
				elif degrees < 0.0 or degrees > MAX_ARROW_DEGREES:
					problem = "the arrow is %.1f degrees off the route's next point" % degrees
				else:
					pointed += 1
					worst = maxf(worst, degrees)
		if problem != "" and failure == "":
			failure = "tick %d: %s" % [int(sample[KEY_TICK]), problem]
	measurements["escape_cue_ticks"] = taken.size()
	measurements["escape_cue_meltdown_ticks"] = meltdown
	measurements["escape_cue_countdown_ticks"] = shown
	measurements["escape_cue_arrow_ticks"] = pointed
	measurements["escape_cue_worst_arrow_degrees"] = snappedf(worst, 0.01)
	if taken.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no tick was sampled: the scene holds no cockpit for the meltdown cue"]
	if failure != "":
		return [AcceptanceReport.RESULT_FAIL, failure]
	if meltdown == 0:
		return [AcceptanceReport.RESULT_FAIL, "the reactor never died while the replay flew"]
	if not escaped:
		return [AcceptanceReport.RESULT_FAIL, "the replay never escaped, so the cue's end was not seen"]
	return [AcceptanceReport.RESULT_PASS,
		"countdown shown on %d of %d meltdown ticks, arrow on the route on %d (worst %.1f degrees), gone after the escape"
		% [shown, meltdown, pointed, worst]]


## What is wrong with a meltdown sample's countdown, or "".
static func _countdown_problem(sample: Dictionary, last_seconds: int) -> String:
	var visible: bool = bool(sample[KEY_COUNTDOWN_SHOWN])
	if bool(sample[KEY_COUNTDOWN_DUE]) and not visible:
		return "the countdown is hidden while it is due"
	if not visible:
		return ""
	var seconds: int = int(sample[KEY_COUNTDOWN_SECONDS])
	var left: float = float(sample[KEY_SECONDS_LEFT])
	if seconds < 0:
		return "the countdown shows no time"
	if last_seconds >= 0 and seconds > last_seconds:
		return "the countdown went up from %d s to %d s" % [last_seconds, seconds]
	if absf(float(seconds) - left) > MAX_SECONDS_OFF:
		return "the countdown shows %d s with %.2f s of the meltdown left" % [seconds, left]
	return ""
