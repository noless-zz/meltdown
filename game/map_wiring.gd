class_name MapWiring
extends RefCounted

## Joins the session to the hologram map in the hand (MAP-1, #339): the boxes
## the ship has been in are drawn, and a marker shows where it is now.
##
## It sits beside `main.gd`, like `CombatWiring`, because it reads the `net/`
## session, which `xr/` and `view/` may not depend on. It reads copies only:
## the walls come back from the replay as a new union and the ship's position
## from the session's ship copies, so it never writes simulation state (MP-2).
## The view follows the simulated ship only (CMF-8); nothing here moves the rig.
##
## It also marks the exit and the reactor (#380, RUN-2, RUN-3). The exit is
## where ship 0 starts, read from the replay's start line, because the exit is
## the entrance. The reactor is marked only once the ship has been in a box
## that holds the reactor's centre (Planner decision, 2026-11-17), so the map
## does not give the level away before the player has found it.
##
## While the meltdown runs, `MapRouteWiring` hands the map the escape route the
## player knows (#402, MAP-2). It lives in its own file because it must read the
## meltdown from the simulation, which this file never names.

## The map, under a hand of the rig once `attach` has run, null before. A
## wiring that was never attached does nothing, so a scene can go without it.
var hologram: MapHologram = null
## Which boxes the ship has been in, for the session last seen by `update`.
var explored: ExploredBoxes = null
## How often the hologram's lines were rebuilt; tests read it.
var rebuilds: int = 0
## This frame's sampled buttons; `update` reads `show_map` from them.
var buttons: Dictionary = {}

var _rig: Node = null
var _mapping: ThumbstickMapping = null
## The session `explored` belongs to; a new session (a level switch) starts over.
var _session: LocalSession = null
var _union: BoxUnion = null
var _drawn: Array[int] = []
var _hand: String = ""
## Boxes holding the reactor's centre; empty without a reactor.
var _reactor_boxes: Array[int] = []
## The last `reactor_known` handed to `set_markers`.
var _reactor_known: bool = false
## The known escape route on the map during the meltdown (#402).
var route_wiring: MapRouteWiring = MapRouteWiring.new()


## Creates the hologram and hangs it in the hand that clicks `show_map` under
## `mapping` (`MapHologram.hand_for`). Calling it again adds nothing.
func attach(rig: Node, mapping: ThumbstickMapping) -> void:
	if hologram != null or rig == null:
		return
	_rig = rig
	_mapping = mapping
	hologram = MapHologram.new()
	_follow_hand()
	if hologram.get_parent() == null:  # No hand to hold it: stay unattached.
		hologram.free()
		hologram = null


## Once per frame, after the controls were read: marks the boxes holding the
## ship, redraws the map only when that set grew, moves and turns the marker to
## the ship's interpolated pose (#679) and shows or hides the map. `shared` is the
## label button's `ClickHold` when that button also shows the map, else null
## (`ComfortWiring.shared_click_hold`).
func update(session: LocalSession, delta_seconds: float, shared: ClickHold = null) -> void:
	if hologram == null or session == null:
		return
	if session != _session:
		_start(session)
	explored.visit(session.current_ship().position)
	var now: Array[int] = explored.explored()
	var grew: bool = now != _drawn
	if grew:
		_drawn = now
		hologram.build(_union, _drawn)
		rebuilds += 1
	var known: bool = _reactor_found(now)
	if known != _reactor_known:
		_reactor_known = known
		_mark(session)
	route_wiring.update(session, _union, _drawn, grew, hologram)
	hologram.set_ship_position(session.previous_ship().position.lerp(
		session.current_ship().position, session.interpolation_fraction))
	hologram.set_ship_orientation(session.previous_ship().orientation.slerp(
		session.current_ship().orientation, session.interpolation_fraction))
	_follow_hand()
	hologram.read(_mapping, buttons, delta_seconds, shared)


## Starts a new map for `session`'s walls: the level's boxes, or the test
## tunnel's one box. Open space has no walls and maps nothing.
func _start(session: LocalSession) -> void:
	_session = session
	var walls: BoxUnion = session.replay.walls()
	_union = walls if walls != null else BoxUnion.new()
	explored = ExploredBoxes.new(_union)
	_drawn = []
	hologram.build(_union, _drawn)
	rebuilds += 1
	_reactor_boxes = []
	var reactor: ReactorState = session.replay.reactor
	if reactor != null:
		var centre: Vector3 = _centre(reactor)
		for index: int in _union.boxes.size():
			if _union.boxes[index].holds(centre, 0.0):
				_reactor_boxes.append(index)
	_reactor_known = false
	_mark(session)
	route_wiring.clear(hologram)


## Hands the exit, the reactor and whether it is known to the hologram. Both
## positions are read from the replay, which the run only copies from.
func _mark(session: LocalSession) -> void:
	var exit_at: Vector3 = ReplayStartLine.position(session.replay, 0)
	var reactor: ReactorState = session.replay.reactor
	var reactor_at: Vector3 = Vector3.ZERO if reactor == null else _centre(reactor)
	hologram.set_markers(exit_at, reactor_at, _reactor_known)


## The reactor's centre in metres.
static func _centre(reactor: ReactorState) -> Vector3:
	return Vector3(reactor.position_mm) / float(RobotSpawn.SCALE)


## Whether any box holding the reactor's centre is among `explored`.
func _reactor_found(explored: Array[int]) -> bool:
	for index: int in _reactor_boxes:
		if explored.has(index):
			return true
	return false


## Moves the map to the other hand when left-handed mode or a remap moved the
## `show_map` click there.
func _follow_hand() -> void:
	var hand: String = MapHologram.hand_for(_mapping)
	if hand != _hand and hologram.attach_to(_rig, _mapping):
		_hand = hand
