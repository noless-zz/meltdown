class_name BotFallback
extends RefCounted

## When the bot pilot gives ground instead of pressing on (#334, #492, #1135):
## it falls back out of fire once its shield runs low or too many robots can
## shoot it, and it waits where it stands for robots out of sight that close
## on it or while its shield recharges. Split out of `BotPilot` (#1135) so the
## pilot stays one file under the size limit; the rules are unchanged.
##
## Also answers whether any robot can shoot the ship now (`under_fire`).
## Remembers where the ship last stood with no robot able to shoot it, whether
## it is falling back and how long it has waited. Only reads the sim (MP-2);
## no randomness and no clock, so the same flight gives the same choices
## (ARC-1, ARC-2).

## The bot falls back out of fire once its shield drops below this many
## points, and comes on again only with the shield full, so hull damage comes
## in short exchanges rather than one long one (#334). In the G2 level every
## robot is awake from the start, so a straight fight is lost.
const RETREAT_SHIELD: float = 20.0
## The bot falls back too once this many robots can shoot it at once (#492):
## it meets them one at a time from cover instead.
const OUTNUMBERED: int = 2
## A robot out of sight that closes on the ship faster than this, metres per
## second, is waited for where the bot stands rather than met round a corner.
const CLOSING_ROBOT_SPEED: float = 0.5
## The longest the bot waits in a row for robots out of sight, ticks (10 s).
## Robots behind a wall no longer fire through it (#615), so one held against
## the wall can creep along it for good; the bot then goes to meet it.
const MAX_WAIT_TICKS: int = 600

var _sim: Sim = null
var _cover: BotCover = null
## Where the ship last stood with no robot able to shoot it.
var _last_safe: Vector3 = Vector3.ZERO
var _has_safe: bool = false
var _retreating: bool = false
## Ticks in a row the bot has waited for robots out of sight (`MAX_WAIT_TICKS`).
var _waited_ticks: int = 0


func _init(sim: Sim, cover: BotCover) -> void:
	_sim = sim
	_cover = cover


## Once a tick, before anything else is decided: out of fire the ship's place
## is remembered as safe and the fall-back ends; under fire with the shield
## low or outnumbered, the fall-back starts.
func update(ship: ShipState, threatened: bool) -> void:
	if not threatened:
		_last_safe = ship.position
		_has_safe = true
		_retreating = false
	elif ship.shield < RETREAT_SHIELD or _cover.threat_count(ship) >= OUTNUMBERED:
		_retreating = true


func retreating() -> bool:
	return _retreating


## Where to fall back to, INF when not falling back: where the ship last stood
## safe if no robot can hit it there now, else the nearest cover (#492), else
## where it last stood safe after all; INF too when there is nowhere.
func shelter(ship: ShipState) -> Vector3:
	if not _retreating:
		return Vector3.INF
	if _has_safe and not _cover.exposed(_last_safe):
		return _last_safe
	var point: Vector3 = _cover.point_for(ship)
	if point == Vector3.INF and _has_safe:
		return _last_safe
	return point


## Whether the bot waits this tick rather than flying on, counting the wait.
## It waits for a `has_target` out of sight while robots close on it or its
## shield recharges, unless it is under fire, flanking or stalled (#603: a
## wait is what keeps a stalled ship there), and never longer than
## `MAX_WAIT_TICKS` in a row. A robot in sight or a shot at the ship ends the wait.
func waits(ship: ShipState, has_target: bool, in_sight: bool, threatened: bool,
		flanking: bool, stalled: bool) -> bool:
	if in_sight or threatened:
		_waited_ticks = 0
	var waiting: bool = has_target and not in_sight and not threatened and not flanking \
		and not stalled and (robots_closing(_sim, ship) or ship.shield < ship.max_shield) \
		and _waited_ticks < MAX_WAIT_TICKS
	if waiting:
		_waited_ticks += 1
	return waiting


## Whether any live robot in `sim` is closing on `ship` faster than
## `CLOSING_ROBOT_SPEED`.
static func robots_closing(sim: Sim, ship: ShipState) -> bool:
	for robot: RobotState in sim.robots:
		if robot.is_alive() and robot.position != ship.position \
				and robot.velocity.dot((ship.position - robot.position).normalized()) > CLOSING_ROBOT_SPEED:
			return true
	return false


## Whether any live, armed robot in `sim` could hit `ship` now: in its weapon's
## range with a clear line past `walls` (null: open space). Robots turn to their
## target, so facing is not counted. An intact reactor stops robot shots too
## (#345), so one behind it is no threat.
static func under_fire(sim: Sim, walls: BoxUnion, ship: ShipState) -> bool:
	for robot: RobotState in sim.robots:
		if BotCover.hits(sim, walls, robot, ship.position):
			return true
	return false
