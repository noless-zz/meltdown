class_name MapRouteWiring
extends RefCounted

## Hands the hologram map the escape route the player knows during the
## meltdown (#402, MAP-2, MAP-1, RUN-4): `EscapePath.known_route` from the ship
## to the exit through the explored boxes, around openings the simulation's
## solid debris blocks. Before the reactor dies, and once the run is escaped or
## lost, no route is drawn.
##
## `MapWiring` owns it and calls `update` once per frame. It sits beside
## `main.gd` because it reads the `net/` session and the simulation, which
## `xr/` may not depend on. It reads copies only: the reactor through
## `SessionSnapshots`, the ship from the session's snapshot, the exit from the
## replay and the debris through `debris_copy`; the run's outcome comes from the
## read-only `Sim.outcome`. Nothing here writes simulation state (MP-2), so
## every state hash stands.
##
## The search runs at most once every `ROUTE_EVERY_TICKS` ticks, so the route
## follows the ship, and at once when a box is explored or more debris falls,
## the only way an opening becomes blocked.
##
## Fire entries burning now go to the map with every route it is handed, and at
## once when another fire catches, picked by `MeltdownWiring.burning_fires` from
## a `SessionSnapshots` copy (#520, MAP-2). Fire is passable, so it never
## changes the route; the mark only warns. A paused session's tick stands still,
## so the marks freeze with the rest of the map (CMF-8).

## Simulation ticks between two searches while nothing else changed: a quarter
## of a second.
const ROUTE_EVERY_TICKS: int = 15

## The route last handed to the map, or null while none is drawn; tests read it.
var route: KnownRoute = null
## How often the route was searched for; tests read it.
var searches: int = 0

## The simulation tick and solid debris count of the last search.
var _tick: int = 0
var _solid: int = 0
## How many fire entries burned when the map's fires were last handed over.
var _burning: int = 0


## Once per frame, after the explored boxes were updated: searches for the
## route when it may have changed and hands it to `hologram`, or clears it
## outside the meltdown. `explored` lists the explored boxes of `walls`;
## `grew` is true when that list changed this frame.
func update(session: LocalSession, walls: BoxUnion, explored: Array[int], grew: bool,
		hologram: MapHologram) -> void:
	if not meltdown_running(session):
		clear(hologram)
		return
	var tick: int = session.sim.tick
	var solid: int = solid_count(session.sim.debris)
	var fires: Array = MeltdownWiring.burning_fires(SessionSnapshots.debris(session.sim.debris))
	var burning: int = (fires[0] as PackedVector3Array).size()
	var search: bool = route == null or grew or solid != _solid or tick - _tick >= ROUTE_EVERY_TICKS
	if not search and burning == _burning:
		return
	if search:
		_tick = tick
		_solid = solid
		searches += 1
		var ship: ShipState = session.current_ship()
		route = EscapePath.known_route(walls, explored, ship.position,
			ReplayStartLine.position(session.replay, 0), debris_copy(session.sim.debris), ship.radius)
		hologram.show_route(metres(route.points_mm), metres(route.blocked_centres_mm))
	_burning = burning
	hologram.show_fires(fires[0], fires[1])


## Removes any route and fire marks from `hologram`; a new session starts
## without them.
func clear(hologram: MapHologram) -> void:
	if route != null:
		route = null
		_burning = 0
		hologram.clear_route()
		hologram.show_fires(PackedVector3Array(), PackedFloat32Array())


## True from the tick the reactor dies until the run is escaped or lost.
static func meltdown_running(session: LocalSession) -> bool:
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	return reactor != null and reactor.destroyed \
		and session.sim.outcome() == ExitRule.Outcome.RUNNING


## How many debris entries have fallen; 0 without debris.
static func solid_count(debris: MeltdownDebris) -> int:
	var count: int = 0
	if debris != null:
		for index: int in debris.size():
			if debris.is_solid(index):
				count += 1
	return count


## A copy of `debris` as it stands now, so the search can never touch the
## simulation's own; null without debris.
static func debris_copy(debris: MeltdownDebris) -> MeltdownDebris:
	if debris == null:
		return null
	var copy: MeltdownDebris = debris.fresh_copy()
	copy.elapsed_ticks = debris.elapsed_ticks
	copy.skipped = debris.skipped.duplicate()
	return copy


## Whole-millimetre points as metres, as the map takes them.
static func metres(points_mm: Array[Vector3i]) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for point: Vector3i in points_mm:
		result.append(Vector3(point) / float(RobotSpawn.SCALE))
	return result
