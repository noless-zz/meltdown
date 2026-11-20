extends ShipInputSource

## The scripted pilot of the m1 `flight_axes` step (#686, FLT-1, FLT-3): in the
## empty test tunnel it rises from the floor to the tunnel's centre, thrusts forward and back, strafes
## both ways, rises and sinks, pitches, yaws and rolls both ways, boosts down
## the tunnel into the far wall, turns about, boosts back into the near wall,
## then holds the reset for a second. Each boost is held until the wall is hit,
## so the hit is always at boost speed whatever the tuning; the two together
## hold the afterburner for about two seconds. Reads the session's own `Sim`,
## so that is set once the session exists.

## Turn rates in radians per second.
const TURN: float = 0.6
## A half turn in two seconds, so the second boost runs back up the tunnel.
const HALF_TURN: float = PI / 2.0
## A boost ends on the first wall impact at least this fast, in metres per
## second, or after BOOST_LIMIT ticks.
const BOOST_IMPACT: float = 15.0
const BOOST_LIMIT: int = 180
## Ticks of coasting after a move: the ship's damping leaves about 5% of its speed.
const COAST: int = 90

enum Kind { HOLD, BOOST, RESET }

var sim: Sim = null
## [kind, ticks, thrust, turn]; a BOOST's ticks are its limit.
var _plan: Array[Array] = []
var _index: int = 0
var _left: int = 0
var _boost_ticks: int = 0
var _done: bool = false


func _init() -> void:
	_hold(30, Vector3.ZERO)
	# The ship starts resting on the floor: up to the tunnel's centre first.
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
		_turn(axis * TURN, 60)
		_turn(-axis * TURN, 120)
		_turn(axis * TURN, 60)
	_plan.append([Kind.BOOST, BOOST_LIMIT, Vector3(0, 0, -1), Vector3.ZERO])
	_hold(120, Vector3.ZERO)
	_turn(Vector3(0, HALF_TURN, 0), 120)
	_plan.append([Kind.BOOST, BOOST_LIMIT, Vector3(0, 0, -1), Vector3.ZERO])
	_hold(120, Vector3.ZERO)
	_plan.append([Kind.RESET, 60, Vector3.ZERO, Vector3.ZERO])
	_hold(60, Vector3.ZERO)
	_left = _plan[0][1]


func done() -> bool:
	return _done


## Ticks the afterburner was held.
func boost_ticks() -> int:
	return _boost_ticks


func next_input(_tick: int) -> ShipInput:
	if _done:
		return ShipInput.new()
	var step: Array = _plan[_index]
	var kind: Kind = step[0]
	var input: ShipInput = ShipInput.from_floats(step[2], step[3], kind == Kind.BOOST)
	input.reset_to_start = kind == Kind.RESET
	if kind == Kind.BOOST:
		_boost_ticks += 1
	_left -= 1
	if _left <= 0 or (kind == Kind.BOOST and _hit_wall()):
		_index += 1
		_done = _index >= _plan.size()
		if not _done:
			_left = _plan[_index][1]
	return input


## The last tick hit a wall at boost speed.
func _hit_wall() -> bool:
	if sim == null:
		return false
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.WALL_IMPACT and event.magnitude >= BOOST_IMPACT:
			return true
	return false


## Thrust for `ticks`, then coast COAST ticks so the ship all but stops.
func _move(thrust: Vector3, ticks: int) -> void:
	_hold(ticks, thrust)
	_hold(COAST, Vector3.ZERO)


func _turn(turn: Vector3, ticks: int) -> void:
	_plan.append([Kind.HOLD, ticks, Vector3.ZERO, turn])


func _hold(ticks: int, thrust: Vector3) -> void:
	_plan.append([Kind.HOLD, ticks, thrust, Vector3.ZERO])
