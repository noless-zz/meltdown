extends ShipInputSource

## The scripted pilot of the m1 `comfort_preset_1` and `comfort_preset_2` steps
## (#697, CMF-1, CMF-3, CMF-8, DEV-6). It flies the manoeuvres of
## `m1_flight_axes_source.gd` as a player's sticks would: every turn is the
## stick pushed fully over and let go, because that is what fires a snap on
## preset 1. Its inputs are raw controller inputs; the recorder hands each one
## to `ComfortWiring.hand_input`, so the replay stores what the comfort filter
## let through, as the headset flies it.
##
## The half turn before the second boost cannot be a fixed number of pushes:
## preset 1 turns 30° a snap, preset 2 is capped at 60°/s. The pilot pushes
## until the ship faces back up the tunnel. Reads the session's own `Sim`, so
## that is set once the session exists.

const FlightAxesSource := preload("res://tests/m1_flight_axes_source.gd")

## A push of the stick, then its release: long enough to re-arm a snap.
const PUSH_TICKS: int = 10
const RELEASE_TICKS: int = 20
## The turn about ends once the nose points at least this far back, as the
## cosine between the nose before and after (about 172°).
const FACING_BACK: float = -0.99
const TURN_ABOUT_LIMIT: int = 40

enum Kind { HOLD, BOOST, RESET, TURN_ABOUT }

var sim: Sim = null
## [kind, ticks, thrust, turn]; a BOOST's ticks are its limit, a TURN_ABOUT's
## the most pushes it makes.
var _plan: Array[Array] = []
var _index: int = 0
var _left: int = 0
var _done: bool = false
## The nose when the turn about began, and the ticks spent in it.
var _nose_before: Vector3 = Vector3.ZERO
var _about_ticks: int = 0


func _init() -> void:
	var full: Vector3 = Vector3(ThumbstickMapping.MAX_PITCH_RATE, ThumbstickMapping.MAX_YAW_RATE,
		ThumbstickMapping.MAX_ROLL_RATE)
	_hold(30, Vector3.ZERO)
	_move(Vector3(0, 0.25, 0), 10)
	_move(Vector3(0, 0, -0.5), 30)
	_move(Vector3(0, 0, 0.5), 30)
	_move(Vector3(0.15, 0, 0), 10)
	_move(Vector3(-0.15, 0, 0), 20)
	_move(Vector3(0.15, 0, 0), 10)
	_move(Vector3(0, 0.15, 0), 10)
	_move(Vector3(0, -0.15, 0), 20)
	_move(Vector3(0, 0.15, 0), 10)
	for axis: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
		_push(axis * full, 1)
		_push(-axis * full, 2)
		_push(axis * full, 1)
	_plan.append([Kind.BOOST, FlightAxesSource.BOOST_LIMIT, Vector3(0, 0, -1), Vector3.ZERO])
	_hold(120, Vector3.ZERO)
	_plan.append([Kind.TURN_ABOUT, TURN_ABOUT_LIMIT, Vector3.ZERO, Vector3(0, full.y, 0)])
	_hold(60, Vector3.ZERO)
	_plan.append([Kind.BOOST, FlightAxesSource.BOOST_LIMIT, Vector3(0, 0, -1), Vector3.ZERO])
	_hold(120, Vector3.ZERO)
	_plan.append([Kind.RESET, 60, Vector3.ZERO, Vector3.ZERO])
	_hold(60, Vector3.ZERO)
	_left = _plan[0][1]


func done() -> bool:
	return _done


func next_input(_tick: int) -> ShipInput:
	if _done:
		return ShipInput.new()
	var step: Array = _plan[_index]
	var kind: int = step[0]
	if kind == Kind.TURN_ABOUT:
		return _turn_about(step)
	var input: ShipInput = ShipInput.from_floats(step[2], step[3], kind == Kind.BOOST)
	input.reset_to_start = kind == Kind.RESET
	_left -= 1
	if _left <= 0 or (kind == Kind.BOOST and _hit_wall()):
		_next()
	return input


## Pushes and releases the stick until the nose points back where it came from.
func _turn_about(step: Array) -> ShipInput:
	var cycle: int = PUSH_TICKS + RELEASE_TICKS
	if _about_ticks == 0:
		_nose_before = _nose()
	elif _about_ticks % cycle == 0 and (_nose().dot(_nose_before) <= FACING_BACK
			or _about_ticks >= int(step[1]) * cycle):
		_about_ticks = 0
		_next()
		return next_input(0)
	var pushed: bool = _about_ticks % cycle < PUSH_TICKS
	_about_ticks += 1
	return ShipInput.from_floats(Vector3.ZERO, step[3] if pushed else Vector3.ZERO)


func _next() -> void:
	_index += 1
	_done = _index >= _plan.size()
	if not _done:
		_left = _plan[_index][1]


func _nose() -> Vector3:
	return -sim.ships[0].orientation.z if sim != null else Vector3.FORWARD


## The last tick hit a wall at boost speed.
func _hit_wall() -> bool:
	if sim == null:
		return false
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.WALL_IMPACT and event.magnitude >= FlightAxesSource.BOOST_IMPACT:
			return true
	return false


func _move(thrust: Vector3, ticks: int) -> void:
	_hold(ticks, thrust)
	_hold(FlightAxesSource.COAST, Vector3.ZERO)


## `count` pushes of the stick to `turn`, each let go again.
func _push(turn: Vector3, count: int) -> void:
	for i: int in count:
		_plan.append([Kind.HOLD, PUSH_TICKS, Vector3.ZERO, turn])
		_hold(RELEASE_TICKS, Vector3.ZERO)


func _hold(ticks: int, thrust: Vector3) -> void:
	_plan.append([Kind.HOLD, ticks, thrust, Vector3.ZERO])
