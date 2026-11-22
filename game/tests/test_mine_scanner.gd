extends RefCounted

## The mine scanner module (#1072, CRF-5, CRF-4, SLV-3, MAP-1, ARC-4, MP-2):
## core accepts it as a utility module, so a crafted one can be fitted; its
## data file gives the scan radius; and while the ship's utility slots hold it
## the map marks the trapped miners within that radius, through walls, until
## each is rescued.

const RADIUS: float = 60.0
const FRAME: float = 1.0 / 60.0
## One corridor down -z from the start at the origin. The miners sit in rock
## beside it, so only a scan through walls finds them.
const LEVEL: String = '{"boxes": [{"min": [-3.0, -3.0, -100.0], "max": [3.0, 3.0, 3.0]}],' \
	+ '"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]}, "robots": []}'
## Rescued after one tick in reach, so a test can rescue a miner with one frame.
const RESCUE: String = '{"rescue_reach": 4.0, "hold_seconds": 0.01}'


## A session in `LEVEL` with miners at `miners_m` (metres), `utility` in the
## ship's slots, and a map wiring attached and run for one frame.
func _flown(miners_m: Array[Vector3], utility: Array[String]) -> Array:
	var session: LocalSession = LocalSession.for_level(LevelDef.parse_json(LEVEL))
	var miners: Array[Vector3i] = []
	for at: Vector3 in miners_m:
		miners.append(Vector3i(at * float(RobotSpawn.SCALE)))
	var problem: String = session.sim.set_rescue_rules(MinerRescue.parse_json(RESCUE), miners)
	session.sim.ships[0].utility_slots.assign(utility)
	session.reset_ship_snapshots()
	var rig: Node3D = Node3D.new()
	var hand: Node3D = Node3D.new()
	hand.name = "LeftHand"
	rig.add_child(hand)
	var wiring: MapWiring = MapWiring.new()
	wiring.attach(rig, ThumbstickMapping.new())
	wiring.scanner = MineScanner.parse('{"scan_radius_m": %f}' % RADIUS)
	wiring.update(session, FRAME)
	return [session, wiring, rig, problem]


func _marked(flown: Array) -> int:
	return _markers(flown[1]).marker_count()


func _markers(wiring: MapWiring) -> MapMinerMarkers:
	return wiring.hologram.get_node(MapMinerMarkers.NODE_NAME) as MapMinerMarkers


func test_the_core_accepts_the_mine_scanner() -> String:
	var loadout: ShipLoadout = ShipLoadout.from_data({"utility": [ShipLoadout.MINE_SCANNER_MODULE]})
	if loadout.error != "" or loadout.utility_ids != ([ShipLoadout.MINE_SCANNER_MODULE] as Array[String]):
		return "mine_scanner gave '%s' %s" % [loadout.error, loadout.utility_ids]
	return "" if ShipLoadout.MINE_SCANNER_MODULE == "mine_scanner" else "the id changed"


func test_a_crafted_mine_scanner_can_be_fitted() -> String:
	var ship_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/default_ship.json"))
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	var tree: UpgradeTree = UpgradeTree.parse(texts)
	var fitting: Fitting = Fitting.new()
	fitting.utility = ["", ShipLoadout.MINE_SCANNER_MODULE] as Array[String]
	var reason: String = Fitting.check(fitting, tree, ["wide_radar", "mine_scanner"], ship_data)
	if reason != "":
		return "mine_scanner refused: " + reason
	var loadout: ShipLoadout = ShipLoadout.from_data(Fitting.loadout(fitting, tree, ship_data))
	if loadout.error != "" or not loadout.utility_ids.has(ShipLoadout.MINE_SCANNER_MODULE):
		return "the fitted loadout gave '%s' %s" % [loadout.error, loadout.utility_ids]
	return ""


func test_a_miner_40_m_away_is_marked_with_the_scanner_and_not_without() -> String:
	var miner: Array[Vector3] = [Vector3(40.0, 0.0, 0.0)]
	var cases: Array = [[[], 0], [[ShipLoadout.WIDE_RADAR_MODULE, ""], 0],
			[["", ShipLoadout.MINE_SCANNER_MODULE], 1]]
	for case: Array in cases:
		var utility: Array[String] = []
		utility.assign(case[0])
		var flown: Array = _flown(miner, utility)
		var marked: int = _marked(flown)
		var wiring: MapWiring = flown[1]
		var where: PackedVector3Array = _markers(wiring).marker_positions()
		(flown[2] as Node).free()
		if flown[3] != "":
			return "rescue rules refused: %s" % flown[3]
		if marked != int(case[1]):
			return "%d miners marked with %s, want %d" % [marked, case[0], case[1]]
		if marked == 1 and where[0].x <= 0.0:
			return "the marker sits at %s, not towards the miner on +x" % where[0]
	return ""


func test_a_miner_80_m_away_is_not_marked() -> String:
	var flown: Array = _flown([Vector3(0.0, 0.0, -80.0), Vector3(0.0, 60.0, 0.0)] as Array[Vector3],
			["", ShipLoadout.MINE_SCANNER_MODULE] as Array[String])
	var marked: int = _marked(flown)
	(flown[2] as Node).free()
	return "" if marked == 1 else "%d miners marked, want only the one exactly 60 m away" % marked


func test_a_rescued_miners_marker_goes() -> String:
	var flown: Array = _flown([Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -40.0)] as Array[Vector3],
			[ShipLoadout.MINE_SCANNER_MODULE] as Array[String])
	var session: LocalSession = flown[0]
	var wiring: MapWiring = flown[1]
	var before: int = _marked(flown)
	session.advance(FRAME)
	wiring.update(session, FRAME)
	var after: int = _marked(flown)
	var rescued: int = session.sim.rescue.rescued
	(flown[2] as Node).free()
	if before != 2:
		return "%d marked before the rescue, want 2" % before
	if rescued != 1 or after != 1:
		return "%d rescued, %d still marked, want 1 and 1" % [rescued, after]
	return ""


func test_the_scan_writes_no_simulation_state() -> String:
	var flown: Array = _flown([Vector3(40.0, 0.0, 0.0)] as Array[Vector3],
			[ShipLoadout.MINE_SCANNER_MODULE] as Array[String])
	var session: LocalSession = flown[0]
	var wiring: MapWiring = flown[1]
	var before: int = session.sim.state_hash()
	wiring.update(session, FRAME)
	wiring.update(session, FRAME)
	var after: int = session.sim.state_hash()
	(flown[2] as Node).free()
	return "" if before == after else "the sim hash moved from %d to %d" % [before, after]


func test_the_marker_look_comes_from_the_map_look_file() -> String:
	var look: Dictionary = MapLook.load_file(MapHologram.DEFAULT_LOOK_FILE)["look"]
	var shipped: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapHologram.DEFAULT_LOOK_FILE))
	if not (shipped as Dictionary).has("miner_color") or not (shipped as Dictionary).has("miner_size_m"):
		return "map_look.json has no miner keys"
	var markers: MapMinerMarkers = MapMinerMarkers.new()
	markers.at_m = PackedVector3Array([Vector3.ZERO])
	markers.draw_fitted(Transform3D.IDENTITY, look)
	var material: StandardMaterial3D = markers.mesh_node().mesh.surface_get_material(0)
	var color: Color = material.emission
	markers.free()
	if not color.is_equal_approx(look["miner_color"]):
		return "marker colour %s, look %s" % [color, look["miner_color"]]
	var bad: Dictionary = MapLook.parse('{"line_color": [1, 1, 1], "line_energy": 1, "size_m": 0.25,'
			+ ' "marker_color": [1, 1, 1], "marker_radius_m": 0.008, "miner_size_m": 1.0}')
	if not str(bad.get("error", "")).contains("miner_size_m"):
		return "a too large miner size gave %s" % bad
	return ""


func test_the_shipped_data_file_loads() -> String:
	var scanner: MineScanner = MineScanner.load_file()
	if scanner.error != "":
		return scanner.error
	return "" if scanner.scan_radius_m == RADIUS else "radius %f, want %f" % [scanner.scan_radius_m, RADIUS]


func test_bad_data_is_an_error_naming_the_file_and_key() -> String:
	var path: String = MineScanner.PATH
	for text: String in ['{}', '{"scan_radius_m": 0}', '{"scan_radius_m": -5}',
			'{"scan_radius_m": "60"}', '{"scan_radius_m": true}', '{"scan_radius_m": null}']:
		var scanner: MineScanner = MineScanner.parse(text, path)
		if not scanner.error.contains(path) or not scanner.error.contains("scan_radius_m"):
			return "'%s' gave '%s'" % [text, scanner.error]
	var extra: MineScanner = MineScanner.parse('{"scan_radius_m": 60, "range": 3}', path)
	if not extra.error.contains(path) or not extra.error.contains("range"):
		return "an unknown key gave '%s'" % extra.error
	var rejected: MineScanner = MineScanner.parse('[60]', path)
	var none: PackedVector3Array = rejected.in_range([Vector3i.ZERO] as Array[Vector3i], Vector3.ZERO)
	if not rejected.error.contains(path) or not none.is_empty():
		return "a list gave '%s' and found %d miners" % [rejected.error, none.size()]
	var missing: MineScanner = MineScanner.load_file("res://data/utility/nope.json")
	return "" if missing.error.contains("nope.json") else "a missing file gave '%s'" % missing.error
