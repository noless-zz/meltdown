extends RefCounted

## The theme's module kit, part two (#395, GEN-1, GEN-5, ARC-4, ARC-2): a
## six-way room, an offset shaft and a dead-end alcove, as data. Each parses,
## has the shape its name promises, is roomy enough for the largest default
## ship, and the generator over seeds 0..999 uses each of them while every
## level still passes every `LevelValidator` check.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const MODULES_DIR: String = "res://data/modules/"
const SHIPS_DIR: String = "res://data/ships/"
const KIT_IDS: Array[String] = ["dead_end_alcove", "offset_shaft", "room_six_way"]
const SEEDS: int = 1000


func _load(id: String) -> ModuleDef:
	return ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + id + ".json"))


## Diameter of the largest ship in `SHIPS_DIR`, metres.
func _largest_ship_diameter() -> float:
	var largest: float = 0.0
	for file: String in DirAccess.get_files_at(SHIPS_DIR):
		if file.ends_with(".json"):
			var tuning: ShipTuning = ShipTuning.parse_json(FileAccess.get_file_as_string(SHIPS_DIR + file))
			largest = maxf(largest, 2.0 * tuning.radius)
	return largest


func test_each_kit_file_parses_under_its_own_name() -> String:
	for id: String in KIT_IDS:
		var module: ModuleDef = _load(id)
		if module.error != "":
			return "%s rejected: %s" % [id, module.error]
		if module.id != id:
			return "%s.json holds id %s" % [id, module.id]
	return ""


func test_the_six_way_room_opens_on_all_six_faces() -> String:
	var room: ModuleDef = _load("room_six_way")
	if room.boxes.size() != 1:
		return "the room has %d boxes, expected one" % room.boxes.size()
	var axes: Array[String] = []
	for connector: ModuleConnector in room.connectors:
		if not axes.has(connector.axis_name):
			axes.append(connector.axis_name)
	for axis: String in ModuleConnector.AXES:
		if not axes.has(axis):
			return "no connector faces %s; found %s" % [axis, axes]
	return ""


func test_the_offset_shaft_moves_sideways_by_a_tunnel_width() -> String:
	var shaft: ModuleDef = _load("offset_shaft")
	if shaft.boxes.size() != 2 or not LevelDef.joined(shaft.boxes[0], shaft.boxes[1]):
		return "expected two boxes that overlap where they meet"
	var tunnel: BoxBounds = _load("straight_tunnel").boxes[0]
	var tunnel_width: float = tunnel.max_corner.x - tunnel.min_corner.x
	var top: ModuleConnector = null
	var bottom: ModuleConnector = null
	for connector: ModuleConnector in shaft.connectors:
		if connector.axis_name == "+y":
			top = connector
		elif connector.axis_name == "-y":
			bottom = connector
	if top == null or bottom == null:
		return "the shaft needs a +y and a -y connector"
	var sideways: Vector3 = top.position() - bottom.position()
	sideways.y = 0.0
	if sideways.length() < tunnel_width:
		return "top and bottom are %s m apart sideways, below the %s m tunnel" \
				% [sideways.length(), tunnel_width]
	return ""


func test_the_alcove_is_a_dead_end_with_room_for_the_reactor() -> String:
	var alcove: ModuleDef = _load("dead_end_alcove")
	if alcove.connectors.size() != 1:
		return "the alcove has %d connectors, expected one" % alcove.connectors.size()
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	# The reactor with a ship's diameter of clearance all round, as #356 places it.
	var needed: float = plan.reactor.radius_mm / 1000.0 + 2.0 * SeedSweep.ship_radius()
	for box: BoxBounds in alcove.boxes:
		var size: Vector3 = box.max_corner - box.min_corner
		if minf(size.x, minf(size.y, size.z)) >= 2.0 * needed:
			return ""
	return "no alcove box holds a %s m ball" % (2.0 * needed)


func test_kit_boxes_are_a_ship_wider_than_the_largest_ship_every_way() -> String:
	var diameter: float = _largest_ship_diameter()
	if diameter <= 0.0:
		return "no ship read from %s" % SHIPS_DIR
	# In six degrees of freedom a ship can fly through a box along any axis.
	for id: String in KIT_IDS:
		var module: ModuleDef = _load(id)
		for connector: ModuleConnector in module.connectors:
			if not ModuleConnector.SIZE_CLASSES.has(connector.size_class):
				return "%s: unknown size class %s" % [id, connector.size_class]
		for index: int in module.boxes.size():
			var box: BoxBounds = module.boxes[index]
			for axis: int in 3:
				var side: float = box.max_corner[axis] - box.min_corner[axis]
				if side < 2.0 * diameter:
					return "%s box %d is %s m on axis %d, below %s m" % [id, index, side, axis, 2.0 * diameter]
	return ""


func test_thousand_seeds_use_each_kit_module_and_pass_every_check() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var validator: LevelValidator = SeedSweep.load_validator()
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var radius: float = SeedSweep.ship_radius()
	if validator.error != "" or plan.error != "":
		return "data rejected: %s %s" % [validator.error, plan.error]
	var used: Dictionary[String, int] = {}
	for level_seed: int in SEEDS:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
		if generator.note != "":
			return "seed %d: %s" % [level_seed, generator.note]
		var level: LevelDef = generator.to_level_def(plan, radius)
		if level.error != "":
			return "seed %d: level: %s" % [level_seed, level.error]
		var found: Array[String] = validator.validate(level, radius)
		if not found.is_empty():
			return "seed %d: %s" % [level_seed, found]
		for placement: ModulePlacement in generator.placements:
			used[placement.module_id] = used.get(placement.module_id, 0) + 1
	for id: String in KIT_IDS:
		if used.get(id, 0) == 0:
			return "no seed in 0..%d uses %s" % [SEEDS - 1, id]
	return ""
