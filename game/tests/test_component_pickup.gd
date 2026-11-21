extends RefCounted

## Destroyed robots drop components and ships fly through them to collect
## them (CRF-1, #976): rolls are seeded per robot, so the same seed and inputs
## give the same items (ARC-2) whatever order robots die in.

const ROBOT: String = "{\"id\": \"drone\", \"hull\": 20.0, \"radius\": 0.8, \"max_speed\": 8.0, \"acceleration\": 16.0, \"turn_rate\": 120.0, \"movement\": \"hover\", \"weapon\": \"robot_pulse\", \"salvage\": \"pulse_cannon\", \"components\": %s}"
const CERTAIN: String = "[{\"id\": \"scrap_alloy\", \"chance\": 1.0, \"count\": [2, 2]}]"
const MIXED: String = "[{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 99]}, {\"id\": \"cell_salts\", \"chance\": 0.5, \"count\": [1, 99]}, {\"id\": \"circuit_shards\", \"chance\": 0.5, \"count\": [1, 99]}, {\"id\": \"core_glass\", \"chance\": 0.5, \"count\": [1, 99]}]"
const RULES: String = "{\"pickup_reach\": 2.5}"


static func robot_def(table: String) -> RobotDef:
	return RobotDef.parse_json(ROBOT % table)


static func rules() -> ComponentPickup:
	return ComponentPickup.parse_json(RULES)


## A one-ship sim with component rules, the ship at the origin.
static func sim_with_rules(run_seed: int) -> Sim:
	var sim: Sim = Sim.new(run_seed, 1)
	sim.set_component_rules(rules())
	return sim


static func idle(sim: Sim) -> bool:
	var inputs: Array[ShipInput] = []
	for i: int in sim.ships.size():
		inputs.append(ShipInput.new())
	return sim.step(inputs)


static func kill(sim: Sim, robot_index: int) -> void:
	sim.robots[robot_index].apply_damage(1000.0)


## "kind:count" of each heap, in list order.
static func heaps(items: Array[ComponentItem]) -> Array[String]:
	var found: Array[String] = []
	for item: ComponentItem in items:
		found.append("%s:%d" % [item.kind_id, item.count])
	return found


func test_rules_file_ships_and_errors_name_the_key() -> String:
	var shipped: ComponentPickup = ComponentPickup.parse_json(
		FileAccess.get_file_as_string("res://data/components/pickup.json"))
	if shipped.error != "" or shipped.pickup_reach <= 0.0:
		return "shipped pickup.json: \"%s\", reach %s" % [shipped.error, shipped.pickup_reach]
	var cases: Dictionary = {
		"{}": "missing key \"pickup_reach\"",
		"{\"pickup_reach\": 2.5, \"pull\": 1}": "unknown key \"pull\"",
		"{\"pickup_reach\": true}": "key \"pickup_reach\"",
		"{\"pickup_reach\": -1}": "key \"pickup_reach\"",
		"{\"pickup_reach\": 21}": "key \"pickup_reach\"",
		"[]": "top level",
	}
	for text: String in cases:
		var parsed: ComponentPickup = ComponentPickup.parse_json(text)
		if not parsed.error.contains(cases[text]):
			return "%s gave \"%s\", want it to name %s" % [text, parsed.error, cases[text]]
	return ""


func test_the_kind_list_skips_the_rules_file() -> String:
	var texts: Dictionary = {"pickup.json": RULES}
	var list: ComponentList = ComponentList.parse(texts)
	if list.error != "" or not list.kinds.is_empty():
		return "pickup.json read as a kind: \"%s\"" % list.error
	return ""


func test_rules_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(1, 1)
	if sim.set_component_rules(null) == "" or sim.set_component_rules(ComponentPickup.parse_json("{}")) == "":
		return "unresolved rules accepted"
	idle(sim)
	if sim.set_component_rules(rules()) == "" or sim.component_rules != null:
		return "rules accepted after the first tick"
	return ""


func test_without_rules_nothing_drops() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.spawn_robot(robot_def(CERTAIN), Vector3(0, 0, -30), Basis.IDENTITY)
	kill(sim, 0)
	idle(sim)
	if not sim.components.is_empty() or not sim.collected.is_empty():
		return "%d heaps dropped without rules" % sim.components.size()
	return ""


func test_a_certain_line_always_drops() -> String:
	for run_seed: int in 50:
		var sim: Sim = sim_with_rules(run_seed)
		sim.spawn_robot(robot_def(CERTAIN), Vector3(0, 0, -30), Basis.IDENTITY)
		kill(sim, 0)
		idle(sim)
		if heaps(sim.components) != ["scrap_alloy:2"]:
			return "seed %d dropped %s" % [run_seed, heaps(sim.components)]
		if not sim.robots.is_empty():
			return "the robot was not removed"
	return ""


func test_an_empty_table_never_drops() -> String:
	for run_seed: int in 50:
		var sim: Sim = sim_with_rules(run_seed)
		sim.spawn_robot(robot_def("[]"), Vector3(0, 0, -30), Basis.IDENTITY)
		kill(sim, 0)
		idle(sim)
		if not sim.components.is_empty():
			return "seed %d dropped %s" % [run_seed, heaps(sim.components)]
	return ""


func test_a_heap_lies_where_the_robot_died() -> String:
	var sim: Sim = sim_with_rules(3)
	sim.spawn_robot(robot_def(CERTAIN), Vector3(4, 5, -30), Basis.IDENTITY)
	kill(sim, 0)
	var where: Vector3 = sim.robots[0].position
	idle(sim)
	var item: ComponentItem = sim.components[0]
	if item.position.distance_to(where) > 1.0 or item.velocity != Vector3.ZERO:
		return "heap at %s moving %s, robot was near %s" % [item.position, item.velocity, where]
	return ""


## Ten robots of mixed odds, all destroyed on one tick, then the ship flies
## through the field.
static func _mixed_run(run_seed: int) -> Sim:
	var sim: Sim = sim_with_rules(run_seed)
	for k: int in 10:
		sim.spawn_robot(robot_def(MIXED), Vector3(0, 0, -5.0 - 3.0 * k), Basis.IDENTITY)
		kill(sim, k)
	idle(sim)
	var forward: Array[ShipInput] = [ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE))]
	for t: int in 240:
		sim.step(forward)
	return sim


func test_same_seed_and_inputs_give_the_same_drops() -> String:
	var first: Sim = _mixed_run(42)
	var second: Sim = _mixed_run(42)
	if first.state_hash() != second.state_hash() or first.collected != second.collected:
		return "two runs differ: %s vs %s" % [first.collected, second.collected]
	if first.collected.is_empty():
		return "the ship collected nothing, so the test shows nothing"
	if _mixed_run(43).collected == first.collected:
		return "another seed collected exactly the same"
	return ""


func test_death_order_does_not_change_a_robot_roll() -> String:
	var rolls: Array[Dictionary] = []
	for order: Array in [[0, 1], [1, 0]]:
		var sim: Sim = sim_with_rules(7)
		sim.spawn_robot(robot_def(MIXED), Vector3(-10, 0, -30), Basis.IDENTITY)
		sim.spawn_robot(robot_def(MIXED), Vector3(10, 0, -30), Basis.IDENTITY)
		var by_robot: Dictionary = {}
		for robot_index: int in order:
			# After the first death the survivor is index 0.
			kill(sim, 0 if by_robot.size() == 1 else robot_index)
			var before: int = sim.components.size()
			idle(sim)
			by_robot[robot_index] = heaps(sim.components.slice(before))
		rolls.append(by_robot)
	if rolls[0] != rolls[1]:
		return "rolls follow the death order: %s vs %s" % [rolls[0], rolls[1]]
	if rolls[0][0] == rolls[0][1]:
		return "both robots rolled %s; the salt shows nothing" % [rolls[0][0]]
	return ""


func test_a_heap_out_of_reach_stays() -> String:
	var sim: Sim = sim_with_rules(1)
	sim.components.append(ComponentItem.new("scrap_alloy", 3, Vector3(0, 0, 3.6)))
	idle(sim)
	if sim.components.size() != 1 or not sim.collected.is_empty():
		return "a heap 3.6 m off was taken by a 1 m ship with 2.5 m reach"
	return ""


func test_collecting_fires_one_event() -> String:
	var sim: Sim = sim_with_rules(1)
	sim.components.append(ComponentItem.new("scrap_alloy", 3, Vector3(0, 0, 3.4)))
	sim.components.append(ComponentItem.new("cell_salts", 1, Vector3(0, 0, 50)))
	idle(sim)
	var events: Array[SimEvent] = []
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.COMPONENT_COLLECTED:
			events.append(event)
	if events.size() != 1 or events[0].component != "scrap_alloy" or events[0].magnitude != 3.0:
		return "events %s" % [events]
	if sim.collected != {"scrap_alloy": 3} or heaps(sim.components) != ["cell_salts:1"]:
		return "collected %s, left %s" % [sim.collected, heaps(sim.components)]
	idle(sim)
	for event: SimEvent in sim.last_events:
		if event.kind == SimEvent.Kind.COMPONENT_COLLECTED:
			return "the heap was collected twice"
	return ""


func test_rules_and_tables_join_the_hash_only_with_rules() -> String:
	var plain: Sim = Sim.new(5, 1)
	var with_rules: Sim = sim_with_rules(5)
	if plain.state_hash() == with_rules.state_hash():
		return "the rules do not join the hash"
	var a: Sim = Sim.new(5, 1)
	var b: Sim = Sim.new(5, 1)
	a.spawn_robot(robot_def(CERTAIN), Vector3(0, 0, -30), Basis.IDENTITY)
	b.spawn_robot(robot_def(MIXED), Vector3(0, 0, -30), Basis.IDENTITY)
	if a.state_hash() != b.state_hash():
		return "the drop table joined the hash without rules"
	a.set_component_rules(rules())
	b.set_component_rules(rules())
	if a.state_hash() == b.state_hash():
		return "the drop table does not join the hash with rules"
	return ""
