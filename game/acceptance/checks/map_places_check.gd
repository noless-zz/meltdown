extends RefCounted

## The `map_places` check (#1321, MAP-1, PLT-5, DEV-6), lane-a's file under
## `acceptance/checks/`. In `suites/m6/ship.json`:
##
##     {"id": "map_places", "checks": ["no_script_errors", "map_places"]}
##
## On the scene's own map and cockpit frame it cycles every panel corner, map
## place, map turn and comfort preset (`MapChoice`, `PanelCorner`), places the
## map as the game does (`MapWiring.follow_choice`) and fails when a mounted
## map is not at its cockpit file's spot, overlaps the panel or an instrument,
## or leaves the window (`MapPanelClearance`); when a hand-held map is not in a
## hand; or when a map that follows the ship does not point the ship ahead.
## The choices are set in memory only, never saved, and everything is put back
## afterwards. Skipped, not passed, when the scene has no map or no frame.

const CHECK: String = "map_places"
const MAP_PROPERTY: String = "map"
const RIG_PATH: NodePath = ^"XRRig"
## A ship turned off every axis, so a map that does not follow it shows.
static var ship_turn: Basis = Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.9)


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	var map: MapWiring = main.get(MAP_PROPERTY) as MapWiring if main != null else null
	return judge_map(map, main.get_node_or_null(RIG_PATH) if main != null else null, measurements)


## The verdict for `map` hanging in `rig`; either may be null.
static func judge_map(map: MapWiring, rig: Node, measurements: Dictionary) -> Array:
	var frame: CockpitFrame = MapPlacement.cockpit_frame(rig)
	if map == null or map.hologram == null or frame == null:
		return [AcceptanceReport.RESULT_SKIPPED, "the scene has no map or no cockpit frame"]
	var saved: Array = [MapChoice.current_place, MapChoice.current_turn, PanelCorner.current, frame.spec]
	var problem: String = ""
	var cases: int = 0
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		var spec: CockpitSpec = CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))
		frame.set_spec(spec)
		for corner: String in PanelCorner.names():
			for place: String in MapChoice.PLACES:
				for turn: String in MapChoice.TURNS:
					problem = _case(map, spec, corner, place, turn)
					cases += 1
					if problem != "":
						problem = "preset %d, panel %s, map %s, %s: %s" % [number, corner, place, turn, problem]
						break
				if problem != "":
					break
			if problem != "":
				break
		if problem != "":
			break
	MapChoice.current_place = saved[0]
	MapChoice.current_turn = saved[1]
	PanelCorner.current = saved[2]
	frame.set_spec(saved[3])
	map.hologram.set_ship_orientation(Basis.IDENTITY)
	map.follow_choice()
	measurements["map_place_cases"] = cases
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	return [AcceptanceReport.RESULT_PASS, "%d combinations of preset, corner, place and turn: mounted maps clear of the panel and inside the window" % cases]


## The first problem with one combination, or "".
static func _case(map: MapWiring, spec: CockpitSpec, corner: String, place: String, turn: String) -> String:
	MapChoice.current_place = place
	MapChoice.current_turn = turn
	PanelCorner.current = corner
	var hologram: MapHologram = map.hologram
	hologram.set_ship_orientation(ship_turn)
	map.follow_choice()
	var turned: Basis = (hologram.basis * ship_turn).orthonormalized()
	var want_turned: Basis = Basis.IDENTITY if turn == MapChoice.TURN_FOLLOWS else ship_turn
	if not turned.is_equal_approx(want_turned):
		return "the ship marker is turned %s, want %s" % [turned, want_turned]
	if place == MapChoice.PLACE_HAND:
		var hand: String = str(hologram.get_parent().name) if hologram.get_parent() != null else ""
		if not hand.ends_with("Hand"):
			return "the map hangs under %s, not a hand" % (hand if hand != "" else "nothing")
		return ""
	if not hologram.get_parent() is CockpitFrame:
		return "the map is not mounted in the cockpit frame"
	if not hologram.position.is_equal_approx(spec.map_mount.spot(corner)):
		return "the map is at %s, the cockpit file says %s" % [hologram.position, spec.map_mount.spot(corner)]
	var edge: float = float(hologram.look()["size_m"]) * hologram.mount_scale() * hologram.zoom()
	return MapPanelClearance.problem(spec, corner, hologram.position, edge)
