class_name BotRescue
extends RefCounted

## The bot pilot's rescue goal (#1084, SLV-3, CRW-1, DEV-6): once no robot is
## left in reach and before the reactor is shot, the bot flies to one trapped
## miner and holds there until the sim's `MinerRescue` counts it rescued; then
## `BotEscape` takes the ship to the reactor and out as before.
##
## A bot is given the goal only when a recording asks for it
## (`BotPilot.set_rescue_goal`), so without one every bot flight, the run
## sweep and every pinned replay keep their hashes.
##
## Only reads the sim and answers with a `ShipInput`, as a pilot's controllers
## would (MP-2). No randomness and no clock (ARC-1, ARC-2).

## Fastest the bot flies to the miner, metres per second, as `BotPilot.ROUTE_SPEED`.
const ROUTE_SPEED: float = 10.0
## Slowest it flies at a corner on the way, metres per second, as `BotPilot.CORNER_SPEED`.
const CORNER_SPEED: float = 3.0
## Wanted speed per metre still to go, per second: it slows to a stop at the miner.
const CLOSING_GAIN: float = 1.0
## Thrust per metre per second of velocity still missing, as `BotPilot.THRUST_GAIN`.
const THRUST_GAIN: float = 0.25
## The longest the bot tries, ticks (60 s). A miner it cannot reach in that
## time is given up, so the flight still ends with the escape.
const MAX_TICKS: int = 3600

var _sim: Sim = null
var _route: LevelRoute = null
## The miner, in whole millimetres as `MinerRescue.trapped` holds it.
var miner: Vector3i = Vector3i.ZERO
var _point: Vector3 = Vector3.ZERO
var _ticks: int = 0
## Set once the miner is rescued or given up; the goal is then spent.
var done: bool = false


func _init(sim: Sim, route: LevelRoute, p_miner: Vector3i) -> void:
	_sim = sim
	_route = route
	miner = p_miner
	_point = MinerRescue.position_of(p_miner)


## Whether the goal still flies the ship: the miner is still trapped (a sim
## without rescue rules has none to free) and the time is not up.
func active() -> bool:
	if done:
		return false
	if _sim.rescue == null or not _sim.rescue.trapped.has(miner) or _ticks >= MAX_TICKS:
		done = true
	return not done


## Flies along the route to the miner and comes to rest on it. The nose turns
## along the way while far off and is left alone once within reach, so the
## ship does not spin on the spot.
func next_input(ship: ShipState) -> ShipInput:
	_ticks += 1
	var waypoint: Vector3 = _route.next_waypoint(ship.position, _point, ship.radius)
	var min_speed: float = -ROUTE_SPEED if waypoint == _point else CORNER_SPEED
	var offset: Vector3 = waypoint - ship.position
	var distance: float = offset.length()
	var wanted: Vector3 = Vector3.ZERO
	if distance > 0.0:
		wanted = offset / distance * clampf(distance * CLOSING_GAIN, min_speed, ROUTE_SPEED)
	var push: Vector3 = ((wanted - ship.velocity) * THRUST_GAIN).limit_length(1.0)
	var basis_inverse: Basis = ship.orientation.transposed()
	var turn: Vector3 = Vector3.ZERO
	if ship.position.distance_to(_point) > _sim.rescue.rescue_reach:
		turn = BotAim.turn_towards(basis_inverse * offset)
	return ShipInput.from_floats(basis_inverse * push, turn)
