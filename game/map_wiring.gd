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
## the entrance. The reactor is marked from the first frame the ship has been
## in a box that holds the reactor's centre or had a clear line to that centre
## (`LineOfSight.clear` over the replay's copy of the walls), and always once
## the reactor is destroyed (#913, Planner decisions of 2026-11-17 and
## 2026-11-21), so the map does not give the level away before the player has
## found it, yet a pilot who shoots it from a doorway sees it. A destroyed
## reactor stays marked, dimmed, where the escape began. Whether it is
## destroyed comes from `MapRouteWiring.reactor_destroyed`, which reads a copy.
##
## While the wide radar module is in one of the ship's utility slots (#1059,
## CRF-5), every box within the radar's radius of the ship is marked too, walls
## ignored. The slots are read from the session's ship copy each frame, and the
## radius from `WideRadar`'s data file.
##
## While the mine scanner module is fitted (#1072, CRF-5, SLV-3), every miner
## still trapped within the scanner's radius of the ship is marked, walls
## ignored. The miners come from `MapRouteWiring.trapped_miners`, a copy, so a
## rescued miner leaves the list and its marker goes. Without the module, or
## without rescue in the run, no miner is marked.
##
## While the meltdown runs, `MapRouteWiring` hands the map the escape route the
## player knows (#402, MAP-2). It lives in its own file because it searches the
## meltdown's debris and names the simulation, which this file never does.

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
## The last `reactor_known` and `reactor_destroyed` handed to `set_markers`.
var _reactor_known: bool = false
var _reactor_destroyed: bool = false
## The reactor's centre in metres; meaningless without a reactor.
var _reactor_at: Vector3 = Vector3.ZERO
## The known escape route on the map during the meltdown (#402).
var route_wiring: MapRouteWiring = MapRouteWiring.new()
## The wide radar's data, read on the first `update`; tests may set it first.
var radar: WideRadar = null
## The mine scanner's data, read on the first frame it is fitted; tests may set it first.
var scanner: MineScanner = null
## The miner positions last handed to the hologram, so it redraws only on a change.
var _miners_shown: PackedVector3Array = PackedVector3Array()


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
## the ship's interpolated pose (#679) and toggles the map on a click of
## `show_map` (#914). `shared` is the label button's `ClickHold` when that button
## also toggles the map, else null (`ComfortWiring.shared_click_hold`). A new
## session (a restart or a level switch) and a destroyed ship close the map.
## `delta_seconds` is unused since the map stopped timing a hold (#914).
func update(session: LocalSession, _delta_seconds: float, shared: ClickHold = null) -> void:
	if hologram == null or session == null:
		return
	if session != _session:
		_start(session)
	_explore(session.current_ship())
	var now: Array[int] = explored.explored()
	var grew: bool = now != _drawn
	if grew:
		_drawn = now
		hologram.build(_union, _drawn)
		rebuilds += 1
	var destroyed: bool = MapRouteWiring.reactor_destroyed(session)
	var known: bool = _reactor_known or destroyed or _reactor_seen(now, session.current_ship().position)
	if known != _reactor_known or destroyed != _reactor_destroyed:
		_reactor_known = known
		_reactor_destroyed = destroyed
		_mark(session)
	route_wiring.update(session, _union, _drawn, grew, hologram)
	_scan(session)
	hologram.set_ship_position(session.previous_ship().position.lerp(
		session.current_ship().position, session.interpolation_fraction))
	hologram.set_ship_orientation(session.previous_ship().orientation.slerp(
		session.current_ship().orientation, session.interpolation_fraction))
	_follow_hand()
	hologram.read(_mapping, buttons, shared)
	if session.current_ship().is_destroyed():
		hologram.close()  # Closed through the end screen and the restart (#914).


## Starts a new map for `session`'s walls: the level's boxes, or the test
## tunnel's one box. Open space has no walls and maps nothing.
func _start(session: LocalSession) -> void:
	_session = session
	hologram.close()
	var walls: BoxUnion = session.replay.walls()
	_union = walls if walls != null else BoxUnion.new()
	explored = ExploredBoxes.new(_union)
	_drawn = []
	hologram.build(_union, _drawn)
	rebuilds += 1
	_reactor_boxes = []
	var reactor: ReactorState = session.replay.reactor
	if reactor != null:
		_reactor_at = _centre(reactor)
		for index: int in _union.boxes.size():
			if _union.boxes[index].holds(_reactor_at, 0.0):
				_reactor_boxes.append(index)
	_reactor_known = false
	_reactor_destroyed = false
	_mark(session)
	route_wiring.clear(hologram)
	_miners_shown = PackedVector3Array()
	hologram.show_miners(_miners_shown)


## Marks the boxes `ship` has found this frame: those holding it, or with the
## wide radar fitted, every box within its radius. A rejected radar file is
## reported once and the map falls back to the boxes flown through.
func _explore(ship: ShipState) -> void:
	if not ship.utility_slots.has(ShipLoadout.WIDE_RADAR_MODULE):
		explored.visit(ship.position)
		return
	if radar == null:
		radar = WideRadar.load_file()
		if radar.error != "":
			push_error(radar.error)
	if radar.error != "":
		explored.visit(ship.position)
		return
	explored.visit_within(ship.position, radar.reveal_radius_m)


## Marks the trapped miners within the mine scanner's radius of the ship while
## the scanner is fitted, and none otherwise. A rejected scanner file is
## reported once and marks nothing. The hologram is redrawn only on a change.
func _scan(session: LocalSession) -> void:
	var ship: ShipState = session.current_ship()
	var found: PackedVector3Array = PackedVector3Array()
	if ship.utility_slots.has(ShipLoadout.MINE_SCANNER_MODULE):
		if scanner == null:
			scanner = MineScanner.load_file()
			if scanner.error != "":
				push_error(scanner.error)
		found = scanner.in_range(MapRouteWiring.trapped_miners(session), ship.position)
	if found != _miners_shown:
		_miners_shown = found
		hologram.show_miners(found)


## Hands the exit, the reactor and whether it is known to the hologram. Both
## positions are read from the replay, which the run only copies from.
func _mark(session: LocalSession) -> void:
	var exit_at: Vector3 = ReplayStartLine.position(session.replay, 0)
	var reactor: ReactorState = session.replay.reactor
	var reactor_at: Vector3 = Vector3.ZERO if reactor == null else _centre(reactor)
	hologram.set_markers(exit_at, reactor_at, _reactor_known, _reactor_destroyed)


## The reactor's centre in metres.
static func _centre(reactor: ReactorState) -> Vector3:
	return Vector3(reactor.position_mm) / float(RobotSpawn.SCALE)


## Whether the ship at `ship_at` finds the reactor now: a box holding its centre
## is among `explored`, or the ship has a clear line to that centre. Without a
## reactor there is nothing to find.
func _reactor_seen(explored: Array[int], ship_at: Vector3) -> bool:
	if _session.replay.reactor == null:
		return false
	for index: int in _reactor_boxes:
		if explored.has(index):
			return true
	return LineOfSight.clear(_union, ship_at, _reactor_at)


## Moves the map to the other hand when left-handed mode or a remap moved the
## `show_map` click there.
func _follow_hand() -> void:
	var hand: String = MapHologram.hand_for(_mapping)
	if hand != _hand and hologram.attach_to(_rig, _mapping):
		_hand = hand
