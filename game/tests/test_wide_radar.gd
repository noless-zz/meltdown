extends RefCounted

## The wide radar module (#1059, CRF-5, CRF-4, MAP-1, ARC-4, MP-2): core accepts
## it as a utility module, so a crafted one can be fitted; its data file gives
## the reveal radius; `ExploredBoxes.visit_within` marks boxes near the ship
## through walls; and the map wiring uses it only while the ship's utility
## slots hold the module.

const RADIUS: float = 40.0
const FRAME: float = 1.0 / 60.0
## A start room, a corridor down -z and a far room. From the start (4, 0, 0)
## the corridor's nearest point is about 18 m away and the far room's 38 m,
## neither holding the ship.
const LEVEL: String = '{"boxes": [' \
	+ '{"min": [-5.0, -5.0, -20.0], "max": [5.0, 5.0, 5.0]},' \
	+ '{"min": [-2.0, -2.0, -40.0], "max": [2.0, 2.0, -18.0]},' \
	+ '{"min": [-10.0, -10.0, -70.0], "max": [10.0, 10.0, -38.0]}],' \
	+ '"start": {"position": [4.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]}, "robots": []}'


## The ship's box at the origin, one box whose nearest face is 30 m away along
## +x and one 50 m away along -x.
func _union() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3(-5.0, -5.0, -5.0), Vector3(5.0, 5.0, 5.0)),
		BoxBounds.new(Vector3(30.0, -5.0, -5.0), Vector3(40.0, 5.0, 5.0)),
		BoxBounds.new(Vector3(-60.0, -5.0, -5.0), Vector3(-50.0, 5.0, 5.0)),
	]
	return BoxUnion.new(boxes)


func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


## How many boxes the wiring has explored after one frame at the level start,
## with `utility` in the ship's utility slots.
func _explored_after_one_frame(utility: Array[String]) -> int:
	var session: LocalSession = LocalSession.for_level(LevelDef.parse_json(LEVEL))
	var rig: Node3D = Node3D.new()
	var hand: Node3D = Node3D.new()
	hand.name = "LeftHand"
	rig.add_child(hand)
	var wiring: MapWiring = MapWiring.new()
	wiring.attach(rig, ThumbstickMapping.new())
	wiring.radar = WideRadar.parse('{"reveal_radius_m": %f}' % RADIUS)
	session.sim.ships[0].utility_slots.assign(utility)
	session.reset_ship_snapshots()
	wiring.update(session, FRAME)
	var count: int = wiring.explored.explored().size()
	rig.free()
	return count


func test_the_level_is_as_the_tests_need() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL)
	if level.error != "":
		return "the hand-built level was rejected: %s" % level.error
	for index: int in range(1, 3):
		if level.union.boxes[index].holds(level.start_position(), 0.0):
			return "box %d holds the start" % index
	return ""


func test_the_core_accepts_the_wide_radar_and_still_refuses_the_mine_scanner() -> String:
	var radar: ShipLoadout = ShipLoadout.from_data({"utility": [ShipLoadout.WIDE_RADAR_MODULE]})
	if radar.error != "" or radar.utility_ids != ([ShipLoadout.WIDE_RADAR_MODULE] as Array[String]):
		return "wide_radar gave '%s' %s" % [radar.error, radar.utility_ids]
	var scanner: ShipLoadout = ShipLoadout.from_data({"utility": ["mine_scanner"]})
	if scanner.error.find("\"loadout.utility[0]\"") < 0:
		return "mine_scanner gave '%s'" % scanner.error
	return ""


func test_a_crafted_wide_radar_can_be_fitted() -> String:
	var ship_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/default_ship.json"))
	var tree: UpgradeTree = _tree()
	var fitting: Fitting = Fitting.new()
	fitting.utility = [ShipLoadout.WIDE_RADAR_MODULE] as Array[String]
	var reason: String = Fitting.check(fitting, tree, ["wide_radar"], ship_data)
	if reason != "":
		return "wide_radar refused: " + reason
	var section: Dictionary = Fitting.loadout(fitting, tree, ship_data)
	var loadout: ShipLoadout = ShipLoadout.from_data(section)
	if loadout.error != "" or not loadout.utility_ids.has(ShipLoadout.WIDE_RADAR_MODULE):
		return "the fitted loadout %s gave '%s'" % [section, loadout.error]
	return ""


func test_the_radar_marks_a_box_30_m_away_and_visit_does_not() -> String:
	var plain: ExploredBoxes = ExploredBoxes.new(_union())
	plain.visit(Vector3.ZERO)
	var radar: ExploredBoxes = ExploredBoxes.new(_union())
	radar.visit_within(Vector3.ZERO, RADIUS)
	if plain.explored() != ([0] as Array[int]):
		return "visit marked %s" % [plain.explored()]
	if radar.explored() != ([0, 1] as Array[int]):
		return "visit_within marked %s, want the ship's box and the one 30 m away" % [radar.explored()]
	return ""


func test_the_radar_does_not_mark_a_box_50_m_away() -> String:
	var radar: ExploredBoxes = ExploredBoxes.new(_union())
	radar.visit_within(Vector3(0.0, 0.0, 0.0), RADIUS)
	if radar.explored().has(2):
		return "a box 50 m away was marked"
	var edge: ExploredBoxes = ExploredBoxes.new(_union())
	edge.visit_within(Vector3(-10.0, 0.0, 0.0), RADIUS)
	if not edge.explored().has(2):
		return "a box exactly 40 m away was not marked"
	return ""


func test_the_wiring_explores_more_with_the_radar_fitted() -> String:
	var without: int = _explored_after_one_frame([])
	var other: int = _explored_after_one_frame([ShipLoadout.LOOK_AIM_MODULE, ""])
	var with_radar: int = _explored_after_one_frame(["", ShipLoadout.WIDE_RADAR_MODULE])
	if without != 1 or other != 1:
		return "%d and %d boxes without the radar, want 1" % [without, other]
	if with_radar != 3:
		return "%d boxes with the radar, want 3" % with_radar
	return ""


func test_the_shipped_data_file_loads() -> String:
	var radar: WideRadar = WideRadar.load_file()
	if radar.error != "":
		return radar.error
	return "" if radar.reveal_radius_m > 0.0 else "radius %f" % radar.reveal_radius_m


func test_bad_data_is_an_error_naming_the_file_and_key() -> String:
	var path: String = "res://data/utility/wide_radar.json"
	for text: String in ['{}', '{"reveal_radius_m": 0}', '{"reveal_radius_m": -5}',
			'{"reveal_radius_m": "40"}', '{"reveal_radius_m": true}', '{"reveal_radius_m": null}']:
		var radar: WideRadar = WideRadar.parse(text, path)
		if not radar.error.contains(path) or not radar.error.contains("reveal_radius_m"):
			return "'%s' gave '%s'" % [text, radar.error]
	var extra: WideRadar = WideRadar.parse('{"reveal_radius_m": 40, "range": 3}', path)
	if not extra.error.contains(path) or not extra.error.contains("range"):
		return "an unknown key gave '%s'" % extra.error
	var bare: WideRadar = WideRadar.parse('[40]', path)
	if not bare.error.contains(path) or bare.reveal_radius_m != 0.0:
		return "a list gave '%s'" % bare.error
	var missing: WideRadar = WideRadar.load_file("res://data/utility/nope.json")
	return "" if missing.error.contains("nope.json") else "a missing file gave '%s'" % missing.error
