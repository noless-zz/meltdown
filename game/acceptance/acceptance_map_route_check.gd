class_name AcceptanceMapRouteCheck
extends RefCounted

## The `map_route` acceptance check (#884, MAP-2, MAP-1, RUN-4, DEV-6): the held
## map's escape route and its blocked-opening crosses as the running game draws
## them, which `test_main_map_route.gd` and `test_map_route.gd` only show on
## hand-built states. After every replay tick it reads the scene's `MapWiring`:
## the route `route_wiring` last searched and the line its hologram drew. It
## judges, naming the first tick that broke a rule:
##
## - before the reactor dies, no route is drawn;
## - from the reactor's death until the run ends a route is drawn on every tick,
##   except at most the first `MapRouteWiring.ROUTE_EVERY_TICKS`;
## - a drawn route ends in a box that holds the exit, and starts in a box that
##   holds the ship or one next to it (the search runs every quarter second, so
##   the ship may have flown on into the next box);
## - from the tick a door (a solid box entry, as `door_fallen` counts them)
##   falls, on every tick the route was searched, each mark that door makes on
##   its own is among the route's blocked marks. A door's marks are found by the
##   same `EscapePath.known_route` over the same explored boxes with every other
##   entry held back; the search is repeated only on ticks the wiring searched,
##   so both read the same ship, boxes and debris. A door that falls outside the
##   explored boxes makes no mark, because the map shows only what the player
##   knows (MAP-2); the message then says so.
##
## It reads the scene and copies of the debris; it writes nothing, so every
## hash of the step stands.

## One sample per tick, as `sample_main` builds it and the unit tests hand-feed it.
const KEY_TICK: String = "tick"
const KEY_REACTOR_DEAD: String = "reactor_dead"
const KEY_RUNNING: String = "running"  # The run is neither escaped nor lost.
const KEY_DRAWN: String = "drawn"  # A route is known and the hologram drew all of it.
const KEY_ENDS_AT_EXIT: String = "ends_at_exit"
const KEY_STARTS_NEAR_SHIP: String = "starts_near_ship"
const KEY_DOORS_FALLEN: String = "doors_fallen"  # Array[int]: solid box entries.
const KEY_DOOR_MARKS: String = "door_marks"  # Marks due from fallen doors this tick.
const KEY_DOORS_UNMARKED: String = "doors_unmarked"  # Array[int]: doors whose marks are missing.

var samples: Array[Dictionary] = []

## The searches counted when the last sample was taken.
var _searches: int = -1
var _session: LocalSession = null
var _walls: BoxUnion = null


## A check for `step`, or null when the step does not list `map_route`.
static func for_step(step: AcceptanceStep) -> AcceptanceMapRouteCheck:
	if not step.has_check(AcceptanceStep.CHECK_MAP_ROUTE):
		return null
	return AcceptanceMapRouteCheck.new()


## Samples `main`'s map after a replay tick. A scene without a held map adds
## nothing, and the check then fails for want of samples.
func sample_main(main: Node) -> void:
	var map: MapWiring = main.get("map") as MapWiring
	var session: LocalSession = main.get("session") as LocalSession
	if map == null or map.hologram == null or map.explored == null or session == null:
		return
	if session != _session:
		_session = session
		_walls = session.replay.walls()
		_searches = -1
	var wiring: MapRouteWiring = map.route_wiring
	var route: KnownRoute = wiring.route
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	var ship: ShipState = session.current_ship()
	var exit_at: Vector3 = ReplayStartLine.position(session.replay, 0)
	var known: bool = route != null and route.points_mm.size() >= 2
	var sample: Dictionary = {
		KEY_TICK: session.sim.tick,
		KEY_REACTOR_DEAD: reactor != null and reactor.destroyed,
		KEY_RUNNING: session.sim.outcome() == ExitRule.Outcome.RUNNING,
		KEY_DRAWN: known and map.hologram.route().segment_count() == route.points_mm.size() - 1,
		KEY_ENDS_AT_EXIT: known and _same_box(_mm_to_m(route.points_mm[-1]), exit_at),
		KEY_STARTS_NEAR_SHIP: known and _near(_mm_to_m(route.points_mm[0]), ship.position),
		KEY_DOORS_FALLEN: _fallen_doors(session.sim.debris),
		KEY_DOOR_MARKS: 0,
		KEY_DOORS_UNMARKED: [],
	}
	var searched: bool = wiring.searches != _searches
	_searches = wiring.searches
	if searched and route != null:
		for door: int in sample[KEY_DOORS_FALLEN]:
			var own: KnownRoute = EscapePath.known_route(_walls, map.explored.explored(), ship.position,
				exit_at, _only(session.sim.debris, door), ship.radius)
			var due: int = own.blocked_openings.size() + own.blocked_splits.size()
			sample[KEY_DOOR_MARKS] = int(sample[KEY_DOOR_MARKS]) + due
			if not _holds_marks(route, own):
				(sample[KEY_DOORS_UNMARKED] as Array).append(door)
	samples.append(sample)


## [result, message] for the samples taken, adding the measurements.
func run(measurements: Dictionary) -> Array:
	return judge(samples, MapRouteWiring.ROUTE_EVERY_TICKS, measurements)


## [result, message] for `taken`, allowing `grace` meltdown ticks without a route.
static func judge(taken: Array[Dictionary], grace: int, measurements: Dictionary) -> Array:
	var meltdown: int = 0
	var drawn: int = 0
	var first_death: int = -1
	var door_ticks: Dictionary[int, int] = {}  # Door entry: the tick it was first seen down.
	var marks_due: int = 0
	var failure: String = ""
	for sample: Dictionary in taken:
		var tick: int = int(sample[KEY_TICK])
		var dead: bool = bool(sample[KEY_REACTOR_DEAD])
		var is_drawn: bool = bool(sample[KEY_DRAWN])
		var problem: String = ""
		if not dead and is_drawn:
			problem = "a route is drawn before the reactor died"
		elif dead and bool(sample[KEY_RUNNING]):
			if first_death < 0:
				first_death = tick
			meltdown += 1
			if is_drawn:
				drawn += 1
			elif meltdown > grace:
				problem = "no route is drawn %d ticks into the meltdown" % (meltdown - 1)
		if problem == "" and is_drawn and not bool(sample[KEY_ENDS_AT_EXIT]):
			problem = "the route ends outside the box that holds the exit"
		if problem == "" and is_drawn and not bool(sample[KEY_STARTS_NEAR_SHIP]):
			problem = "the route starts more than one box from the ship"
		for door: Variant in sample[KEY_DOORS_FALLEN]:
			if not door_ticks.has(int(door)):
				door_ticks[int(door)] = tick
		marks_due += int(sample.get(KEY_DOOR_MARKS, 0))
		var unmarked: Array = sample.get(KEY_DOORS_UNMARKED, [])
		if problem == "" and not unmarked.is_empty():
			problem = "fallen door entry %d (down since tick %d) is not among the route's blocked marks" % [
				int(unmarked[0]), door_ticks.get(int(unmarked[0]), tick)]
		if problem != "" and failure == "":
			failure = "tick %d: %s" % [tick, problem]
	measurements["map_route_ticks"] = taken.size()
	measurements["map_route_meltdown_ticks"] = meltdown
	measurements["map_route_drawn_ticks"] = drawn
	measurements["map_route_door_marks"] = marks_due
	if taken.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no tick was sampled: the scene holds no map"]
	if failure != "":
		return [AcceptanceReport.RESULT_FAIL, failure]
	if meltdown == 0:
		return [AcceptanceReport.RESULT_FAIL, "the reactor never died while the replay flew"]
	var text: String = "route drawn on %d of %d meltdown ticks from tick %d, ending at the exit" % [
		drawn, meltdown, first_death]
	return [AcceptanceReport.RESULT_PASS, "%s; %s" % [text, _doors_text(door_ticks, marks_due)]]


static func _doors_text(door_ticks: Dictionary[int, int], marks_due: int) -> String:
	if door_ticks.is_empty():
		return "no door fell"
	var parts: PackedStringArray = PackedStringArray()
	for door: int in door_ticks:
		parts.append("door %d fell on tick %d" % [door, door_ticks[door]])
	if marks_due == 0:
		return "%s outside the explored boxes, so no mark was due" % ", ".join(parts)
	return "%s; all %d of its marks drawn on the ticks searched" % [", ".join(parts), marks_due]


## Box entries of `debris` that are solid now: fallen doors and cave-ins.
static func _fallen_doors(debris: MeltdownDebris) -> Array[int]:
	var doors: Array[int] = []
	if debris != null:
		for index: int in debris.size():
			if debris.is_box(index) and debris.is_solid(index):
				doors.append(index)
	return doors


## A copy of `debris` in which only entry `keep` may be solid.
static func _only(debris: MeltdownDebris, keep: int) -> MeltdownDebris:
	var copy: MeltdownDebris = MapRouteWiring.debris_copy(debris)
	copy.skipped.resize(copy.size())
	for index: int in copy.size():
		copy.skipped[index] = copy.skipped[index] or index != keep
	return copy


## Whether `route` lists every blocked opening and split of `own`.
static func _holds_marks(route: KnownRoute, own: KnownRoute) -> bool:
	for opening: int in own.blocked_openings:
		if not route.blocked_openings.has(opening):
			return false
	for split: Vector2i in own.blocked_splits:
		if not route.blocked_splits.has(split):
			return false
	return true


## Whether one box of the level holds both `a` and `b`.
func _same_box(a: Vector3, b: Vector3) -> bool:
	for box: BoxBounds in _walls.boxes:
		if box.holds(a, 0.0) and box.holds(b, 0.0):
			return true
	return false


## Whether `a` lies in a box holding `b`, or in a box that opens into one.
func _near(a: Vector3, b: Vector3) -> bool:
	var around_b: Array[BoxBounds] = []
	for box: BoxBounds in _walls.boxes:
		if box.holds(b, 0.0):
			around_b.append(box)
	for box: BoxBounds in _walls.boxes:
		if not box.holds(a, 0.0):
			continue
		for other: BoxBounds in around_b:
			if box == other or _overlap(box, other):
				return true
	return false


static func _overlap(a: BoxBounds, b: BoxBounds) -> bool:
	var low: Vector3 = a.min_corner.max(b.min_corner)
	var high: Vector3 = a.max_corner.min(b.max_corner)
	return low.x < high.x and low.y < high.y and low.z < high.z


static func _mm_to_m(point_mm: Vector3i) -> Vector3:
	return Vector3(point_mm) / float(RobotSpawn.SCALE)
