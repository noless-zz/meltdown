class_name EscapeCueWiring
extends RefCounted

## Joins the meltdown to its escape cues (#617, RUN-2, RUN-3, RUN-5, MAP-2,
## CMF-8): the large countdown and the arrow in the cockpit (`MeltdownCue`)
## and the sign at the exit (`ExitMarker`).
##
## `MeltdownWiring` owns it, so `main.gd` (lane-b) stays as it is. The cue
## hangs beside the status panel, under the rig at the cockpit's eye point,
## which it reads back from the panel's own placement, so it follows a
## recentre with the panel and never moves the camera.
##
## The arrow follows the route the held map draws. `main.gd` hands over the
## map's `MapRouteWiring` (#695), whose `KnownRoute` the arrow reads, so the
## meltdown searches once per interval, not twice, and the arrow and the map
## can never disagree. The map searches before this runs each frame. Without a
## route wiring (tests that build the cue alone) it searches as before:
## `EscapePath.known_route` from the ship to the exit through its own explored
## boxes, on the same inputs as `MapRouteWiring`.
##
## It sits beside `main.gd` because it reads the `net/` session. It reads
## copies only: the reactor through `SessionSnapshots`, the ship from the
## session's snapshot, the exit from the replay and the debris through
## `MapRouteWiring.debris_copy`. Nothing here writes simulation state (MP-2).

## The cockpit cue, under the rig once a meltdown was shown, null before.
var cue: MeltdownCue = null
## The exit sign, under the world node while the level has a reactor.
var exit_marker: ExitMarker = null
## The route the arrow follows, or null outside the meltdown; tests read it.
var route: KnownRoute = null
## How often this wiring searched for the route itself; tests read it.
var searches: int = 0
## Which boxes the ship has been in this session, kept only without a route
## wiring; tests read it.
var explored: ExploredBoxes = null
## The map's route search; when set, the arrow reads its route (#695).
var route_wiring: MapRouteWiring = null

var _world: Node3D = null
var _session: LocalSession = null
var _union: BoxUnion = null
var _drawn: Array[int] = []
## The simulation tick and solid debris count of the last search.
var _tick: int = 0
var _solid: int = 0
## The tick the reactor was first seen dead, or -1 before.
var _death_tick: int = -1


## Remembers `world`, the node whose space is the simulation's, and starts
## over for `session`: a level switch calls it again.
func attach(world: Node3D, session: LocalSession) -> void:
	_world = world
	if session != null:
		_start(session)


## Once per frame, after the ticks: marks the boxes holding the ship, and
## during the meltdown shows the countdown and points the arrow, under
## `panel`'s parent at the cockpit's eye point. Without a panel there is no
## cockpit to show the cue in.
func update(session: LocalSession, panel: StatusPanel) -> void:
	if session == null:
		return
	if session != _session:
		_start(session)
	var grew: bool = false
	if route_wiring == null:
		explored.visit(session.current_ship().position)
		var now: Array[int] = explored.explored()
		grew = now != _drawn
		_drawn = now
	if not MapRouteWiring.meltdown_running(session):
		route = null
		_death_tick = -1
		if cue != null:
			cue.show_countdown(-1.0, 0.0)
			cue.point_at(false, Vector3.ZERO, Transform3D.IDENTITY)
		return
	if _death_tick < 0:
		_death_tick = session.sim.tick
	if route_wiring != null:
		route = route_wiring.route
	else:
		_search(session, grew)
	if panel == null or panel.get_parent() == null:
		return
	_place(panel)
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	var elapsed: float = float(session.sim.tick - _death_tick) / float(ReactorState.TICKS_PER_SECOND)
	cue.show_countdown(MeltdownWiring.seconds_left(reactor), elapsed)
	if route == null:  # The map has not searched yet: no hand holds it.
		cue.point_at(false, Vector3.ZERO, Transform3D.IDENTITY)
		return
	var target: Array = MeltdownCue.waypoint(MapRouteWiring.metres(route.points_mm))
	cue.point_at(target[0], target[1], world_from_cue())


## Where the cue is in the world: its transforms up to the world node
## multiplied out, so it holds outside the scene tree too (tests).
func world_from_cue() -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var node: Node = cue
	while node != null and node != _world and node is Node3D:
		result = (node as Node3D).transform * result
		node = node.get_parent()
	return result


## Starts over for `session`: a new explored set without a route wiring, and
## the exit sign at its exit, only in a level with a reactor, the only kind
## with a meltdown.
func _start(session: LocalSession) -> void:
	_session = session
	var walls: BoxUnion = session.replay.walls()
	_union = walls if walls != null else BoxUnion.new()
	explored = ExploredBoxes.new(_union) if route_wiring == null else null
	_drawn = []
	route = null
	_death_tick = -1
	if exit_marker != null:
		exit_marker.get_parent().remove_child(exit_marker)
		exit_marker.queue_free()
		exit_marker = null
	if session.replay.reactor != null and _world != null:
		exit_marker = ExitMarker.new()
		exit_marker.place(ReplayStartLine.position(session.replay, 0),
			ReplayStartLine.orientation(session.replay, 0))
		_world.add_child(exit_marker)


## Searches for the route when it may have changed: at most once every
## `MapRouteWiring.ROUTE_EVERY_TICKS` ticks, and at once when a box was
## explored or more debris fell, as the map does.
func _search(session: LocalSession, grew: bool) -> void:
	var tick: int = session.sim.tick
	var solid: int = MapRouteWiring.solid_count(session.sim.debris)
	if route != null and not grew and solid == _solid \
			and tick - _tick < MapRouteWiring.ROUTE_EVERY_TICKS:
		return
	_tick = tick
	_solid = solid
	searches += 1
	var ship: ShipState = session.current_ship()
	route = EscapePath.known_route(_union, _drawn, ship.position,
		ReplayStartLine.position(session.replay, 0),
		MapRouteWiring.debris_copy(session.sim.debris), ship.radius)


## Puts the cue beside `panel`, at the eye point the panel was placed from.
func _place(panel: StatusPanel) -> void:
	var rig: Node = panel.get_parent()
	if cue == null:
		cue = MeltdownCue.new()
	if cue.get_parent() != rig:
		if cue.get_parent() != null:
			cue.get_parent().remove_child(cue)
		rig.add_child(cue)
	cue.transform = panel.transform * StatusPanel.rig_transform(Transform3D.IDENTITY).affine_inverse()
