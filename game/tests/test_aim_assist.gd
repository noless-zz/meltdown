extends RefCounted

## The aim assist module (CMB-7, CMB-8, CRF-4, CRF-5, ARC-1, ARC-2, ARC-4,
## #1096): core accepts it, a crafted one fits, its data file is checked, and a
## ship with it fitted fires towards the nearest live robot just off the aim,
## while a ship without it fires exactly as before.

const SHIPPED: String = "res://data/aim/aim_assist.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const DRONE: String = "res://data/robots/drone.json"
## Enough ticks for any shipped shot to end.
const FLIGHT_TICKS: int = 240


## A point `metres` from the origin, `degrees` to the right of the nose (-z).
static func _off_aim(degrees: float, metres: float) -> Vector3:
	return Vector3(0.0, 0.0, -metres).rotated(Vector3.UP, -deg_to_rad(degrees))


## A sim whose ship 0 sits at the origin facing -z with a pulse cannon, a drone
## at `robot_at`, and `utility` in its utility slots.
static func _sim(robot_at: Vector3, utility: Array[String]) -> Sim:
	var sim: Sim = Sim.new(7, 1)
	sim.ships[0].primary_slots[0] = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	sim.ships[0].utility_slots.assign(utility)
	sim.spawn_robot(RobotDef.parse_json(FileAccess.get_file_as_string(DRONE)), robot_at, Basis.IDENTITY)
	return sim


## How many ROBOT_HIT events one shot from ship 0 makes in `sim`.
static func _hits(sim: Sim) -> int:
	ProjectileHits.fire(sim, 0, true)
	if sim.projectiles.size() != 1:
		return -1
	var events: Array[SimEvent] = []
	var killers: Dictionary = {}
	for i: int in FLIGHT_TICKS:
		ProjectileHits.advance(sim, events, killers)
	var hits: int = 0
	for event: SimEvent in events:
		if event.kind == SimEvent.Kind.ROBOT_HIT:
			hits += 1
	return hits


## Hits with and without the module for a drone at `robot_at`.
static func _with_and_without(robot_at: Vector3) -> Array[int]:
	return [_hits(_sim(robot_at, [ShipLoadout.AIM_ASSIST_MODULE, ""] as Array[String])),
		_hits(_sim(robot_at, ["", ""] as Array[String]))]


func test_the_core_accepts_the_aim_assist_module() -> String:
	var loadout: ShipLoadout = ShipLoadout.from_data({"utility": [ShipLoadout.AIM_ASSIST_MODULE]})
	if loadout.error != "" or loadout.utility_ids != ([ShipLoadout.AIM_ASSIST_MODULE] as Array[String]):
		return "aim_assist gave '%s' %s" % [loadout.error, loadout.utility_ids]
	return "" if ShipLoadout.AIM_ASSIST_MODULE == "aim_assist" else "the id changed"


func test_a_crafted_aim_assist_can_be_fitted() -> String:
	var ship_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships/default_ship.json"))
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	var tree: UpgradeTree = UpgradeTree.parse(texts)
	if tree.error != "":
		return tree.error
	var fitting: Fitting = Fitting.new()
	fitting.utility = [ShipLoadout.AIM_ASSIST_MODULE] as Array[String]
	var reason: String = Fitting.check(fitting, tree, ["aim_assist"], ship_data)
	if reason != "":
		return "aim_assist refused: " + reason
	var loadout: ShipLoadout = ShipLoadout.from_data(Fitting.loadout(fitting, tree, ship_data))
	if loadout.error != "" or not loadout.utility_ids.has(ShipLoadout.AIM_ASSIST_MODULE):
		return "the fitted loadout gave '%s' %s" % [loadout.error, loadout.utility_ids]
	if tree.get_upgrade("aim_assist").tier != 1:
		return "aim_assist is tier %d, want 1" % tree.get_upgrade("aim_assist").tier
	return ""


func test_the_shipped_file_parses_to_the_defaults() -> String:
	var assist: AimAssist = AimAssist.parse_json(FileAccess.get_file_as_string(SHIPPED))
	if assist.error != "":
		return "%s: %s" % [SHIPPED, assist.error]
	var plain: AimAssist = AimAssist.new()
	if assist.cone_degrees != plain.cone_degrees or assist.range_m != plain.range_m:
		return "shipped %s/%s, defaults %s/%s" % [assist.cone_degrees, assist.range_m,
			plain.cone_degrees, plain.range_m]
	return "" if plain.cone_degrees == 6.0 and plain.range_m == 60.0 else "defaults changed"


func test_bad_files_are_rejected_naming_the_key() -> String:
	var cases: Array = [
		['{"cone_degrees": 6}', "range_m"],
		['{"range_m": 60}', "cone_degrees"],
		['{"cone_degrees": 6, "range_m": 60, "lock": 1}', "lock"],
		['{"cone_degrees": true, "range_m": 60}', "cone_degrees"],
		['{"cone_degrees": 6, "range_m": "60"}', "range_m"],
		['{"cone_degrees": 90, "range_m": 60}', "cone_degrees"],
		['{"cone_degrees": 6, "range_m": 0}', "range_m"],
	]
	for case: Array in cases:
		var assist: AimAssist = AimAssist.parse_json(case[0])
		if not assist.error.contains(case[1]):
			return "'%s' gave '%s', want it to name %s" % [case[0], assist.error, case[1]]
	if AimAssist.parse_json("[6, 60]").error == "" or AimAssist.parse_json("{").error == "":
		return "a list or broken JSON was accepted"
	return ""


func test_a_robot_three_degrees_off_is_hit_with_the_module_and_missed_without() -> String:
	var hits: Array[int] = _with_and_without(_off_aim(3.0, 30.0))
	return "" if hits == [1, 0] else "hits with and without the module: %s, want [1, 0]" % [hits]


func test_a_robot_twenty_degrees_off_is_missed_either_way() -> String:
	var hits: Array[int] = _with_and_without(_off_aim(20.0, 30.0))
	return "" if hits == [0, 0] else "hits with and without the module: %s, want [0, 0]" % [hits]


func test_a_robot_beyond_range_is_missed() -> String:
	var hits: Array[int] = _with_and_without(_off_aim(3.0, 80.0))
	return "" if hits == [0, 0] else "hits with and without the module: %s, want [0, 0]" % [hits]


func test_the_nearest_of_two_in_the_cone_is_chosen() -> String:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var far: RobotState = RobotState.new(def, _off_aim(2.0, 40.0))
	var near: RobotState = RobotState.new(def, _off_aim(-2.0, 20.0))
	var dead: RobotState = RobotState.new(def, _off_aim(1.0, 10.0))
	dead.apply_damage(def.hull * 2.0)
	var robots: Array[RobotState] = [dead, far, near]
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var bent: Vector3 = AimAssist.new().bend(Vector3.ZERO, aim, robots)
	if not bent.is_equal_approx(near.position.normalized()):
		return "bent towards %s, want the nearer live robot at %s" % [bent, near.position.normalized()]
	var none: Vector3 = AimAssist.new().bend(Vector3.ZERO, aim, [] as Array[RobotState])
	return "" if none == aim else "with no robot the aim became %s" % none


func test_without_the_module_shots_and_hashes_are_unchanged() -> String:
	# A sim given a much wider assist, yet without the module, must fly exactly
	# as one with the shipped values: the module alone switches it on.
	var plain: Sim = _sim(_off_aim(3.0, 30.0), ["", ""] as Array[String])
	var wide: Sim = _sim(_off_aim(3.0, 30.0), ["", ""] as Array[String])
	var problem: String = wide.set_aim_assist(AimAssist.parse_json('{"cone_degrees": 45, "range_m": 1000}'))
	if problem != "":
		return problem
	var input: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true)
	for i: int in 90:
		plain.step([input] as Array[ShipInput])
		wide.step([input] as Array[ShipInput])
	if plain.state_hash() != wide.state_hash():
		return "hash %d with the shipped assist, %d with a wide one, no module fitted" % [
			plain.state_hash(), wide.state_hash()]
	return ""


func test_with_the_module_the_same_inputs_give_the_same_hash_twice() -> String:
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _sim(_off_aim(3.0, 30.0), [ShipLoadout.AIM_ASSIST_MODULE] as Array[String])
		var input: ShipInput = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, true)
		for i: int in 90:
			sim.step([input] as Array[ShipInput])
		hashes.append(sim.state_hash())
	return "" if hashes[0] == hashes[1] else "hashes %s" % [hashes]


func test_aim_assist_is_set_before_the_first_tick_only() -> String:
	var sim: Sim = Sim.new(1, 1)
	if sim.set_aim_assist(AimAssist.parse_json("{}")) == "":
		return "a rejected assist was accepted"
	if sim.set_aim_assist(AimAssist.new()) != "":
		return "a good assist was refused before the first tick"
	sim.step([ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, false, false)] as Array[ShipInput])
	return "" if sim.set_aim_assist(AimAssist.new()) != "" else "an assist was accepted after a tick"
