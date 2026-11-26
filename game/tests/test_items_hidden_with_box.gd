extends RefCounted

## Robots, pickups and effects in a box the level hides are hidden with it, and
## drawn in a box it shows (#1382, GFX-3, PRF-2, MP-2). Each view is handed a
## hand-made union of two cubes far apart, one shown and one hidden, and draws
## one thing in each; what it draws reads the sim's state and never writes it.

const TestMinerRescue := preload("res://tests/test_miner_rescue.gd")
const PICKUP: String = "res://data/components/pickup.json"
## Where the drawn and the hidden things are, and the half size of the cube round each.
const SHOWN_AT: Vector3 = Vector3(0, 0, -5)
const HIDDEN_AT: Vector3 = Vector3(0, 0, -105)
const HALF_M: float = 6.0


## Cube 0 round `shown`, cube 1 round `hidden`, culled so only cube 0 is drawn.
static func boxes_round(shown: Vector3, hidden: Vector3) -> VisibleBoxes:
	var half: Vector3 = Vector3.ONE * HALF_M
	var union: BoxUnion = BoxUnion.new([BoxBounds.new(shown - half, shown + half),
		BoxBounds.new(hidden - half, hidden + half)] as Array[BoxBounds])
	var boxes: VisibleBoxes = VisibleBoxes.new(union)
	boxes.set_flags([true, false] as Array[bool])
	return boxes


static func _pair(what: String, drawn: Node3D, hidden: Node3D) -> String:
	if not drawn.visible:
		return "%s in the shown box is hidden" % what
	if hidden.visible:
		return "%s in the hidden box is drawn" % what
	return ""


func _robot(at: Vector3) -> RobotState:
	return RobotState.new(RobotDef.parse_json(FileAccess.get_file_as_string("res://data/robots/drone.json")), at)


func test_robots_and_their_blasts() -> String:
	var view: RobotView = RobotView.new()
	view.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	var robots: Array[RobotState] = [_robot(SHOWN_AT), _robot(HIDDEN_AT)]
	var before: int = robots[0].state_hash() + robots[1].state_hash()
	view.show_robots(robots, robots, 1.0)
	var problem: String = _pair("a robot", view.node(0), view.node(1))
	if problem == "" and robots[0].state_hash() + robots[1].state_hash() != before:
		problem = "drawing changed the robots"
	view.free()
	if problem != "":
		return problem
	var bursts: RobotBursts = RobotBursts.new()
	bursts.set_boxes(boxes_round(SHOWN_AT, HIDDEN_AT))
	var blasts: Array[Dictionary] = [{"position": SHOWN_AT, "radius": 1.0, "start": 0.0, "id": "drone"},
		{"position": HIDDEN_AT, "radius": 1.0, "start": 0.0, "id": "drone"}]
	bursts.show_bursts(blasts, RobotLook.DEFAULT_EFFECTS, 0.05)
	problem = _pair("a blast", bursts.shell(0), bursts.shell(1))
	if problem == "" and bursts.core(1).visible:
		problem = "a blast's core in the hidden box is drawn"
	if problem == "" and bursts.sparks().shown().size() != 1:
		problem = "%d of 2 blast spark bursts drawn, expected 1" % bursts.sparks().shown().size()
	bursts.free()
	return problem


func test_floating_parts_and_their_rings() -> String:
	var items: Array[SalvageItem] = [SalvageItem.new("pulse_cannon", SHOWN_AT), SalvageItem.new("needle_gun", HIDDEN_AT)]
	var view: SalvageView = SalvageView.new()
	view.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	view.show_salvage(items, items, 1.0)
	var problem: String = _pair("a floating part", view.node(0), view.node(1))
	view.free()
	if problem != "":
		return problem
	var rings: SalvageRing = SalvageRing.new()
	rings.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	rings.show_rings(items, items, 1.0, ShipState.new(), SalvageRules.new())
	problem = _pair("a part's ring", rings.node(0), rings.node(1))
	rings.free()
	return problem


func test_component_heaps() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.set_component_rules(ComponentPickup.parse_json(FileAccess.get_file_as_string(PICKUP)))
	sim.components.append(ComponentItem.new("cell_salts", 2, SHOWN_AT))
	sim.components.append(ComponentItem.new("core_glass", 1, HIDDEN_AT))
	var view: ComponentView = ComponentView.new()
	view.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	view.show_heaps(sim)
	var problem: String = _pair("a component heap", view.node(0), view.node(1))
	if problem == "" and view.shown_count() != 1:
		problem = "%d heaps counted drawn" % view.shown_count()
	view.free()
	return problem


func test_trapped_miners() -> String:
	var sim: Sim = TestMinerRescue.sim_with([Vector3i(0, 0, -1000), Vector3i(0, 0, -90000)] as Array[Vector3i])
	var near: Vector3 = MinerRescue.position_of(sim.rescue.trapped[0])
	var far: Vector3 = MinerRescue.position_of(sim.rescue.trapped[1])
	var before: int = MinerRescue.state_hash(sim)
	var view: MinerView = MinerView.new()
	view.boxes = boxes_round(near, far)
	view.show_miners(sim.rescue, sim.ships[0])
	var problem: String = _pair("a miner", view.marker(0), view.marker(1))
	if problem == "" and MinerRescue.state_hash(sim) != before:
		problem = "drawing changed the rescue"
	view.free()
	return problem


func test_bolts() -> String:
	var shots: Array[Projectile] = [Projectile.new(SHOWN_AT, Vector3(0, 0, -60), 0, 30, 10.0),
		Projectile.new(HIDDEN_AT, Vector3(0, 0, -60), 0, 30, 10.0)]
	var view: ProjectileView = ProjectileView.new()
	view.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	view.show_projectiles(shots, 1.0)
	var problem: String = _pair("a bolt", view.bolt(0), view.bolt(1))
	view.free()
	return problem


func test_bolt_flashes_sparks_and_scorches() -> String:
	var boxes: VisibleBoxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	var impacts: BoltImpacts = BoltImpacts.new()
	var look: Dictionary = ProjectileLook.DEFAULTS.duplicate()
	look["spark_count"] = 6
	look["hit_spark_count"] = 6
	look["scorch_fade_s"] = 5.0
	impacts.set_look(look)
	impacts.set_boxes(boxes)
	for at: Vector3 in [SHOWN_AT, HIDDEN_AT]:
		impacts.strike(BoltImpacts.Kind.ROBOT, at, Vector3.UP, Color.WHITE)
		impacts.strike(BoltImpacts.Kind.WALL, at, Vector3.UP, Color.WHITE)
	var problem: String = ""
	var counts: Array[int] = [impacts.hit_flashes.shown().size(), impacts.hit_sparks.shown().size(),
		impacts.wall_sparks.shown().size(), impacts.scorches.shown().size()]
	if counts != [1, 1, 1, 1]:
		problem = "flashes, hit sparks, wall sparks, scorches drawn %s of 2 each, expected 1" % [counts]
	# A hidden effect keeps running, and shows once its box is drawn again.
	impacts.wall_sparks.age(0.01)
	boxes.show_all()
	impacts.wall_sparks.age(0.01)
	impacts.hit_flashes.age(0.01)
	impacts.scorches.age(0.01)
	counts = [impacts.hit_flashes.shown().size(), impacts.wall_sparks.shown().size(), impacts.scorches.shown().size()]
	if problem == "" and counts != [2, 2, 2]:
		problem = "flashes, sparks, scorches drawn %s once every box was, expected 2 each" % [counts]
	if problem == "" and not impacts.wall_sparks.is_running(1):
		problem = "a hidden spark burst stopped"
	impacts.free()
	return problem


func test_debris() -> String:
	var view: DebrisView = DebrisView.new()
	view.boxes = boxes_round(SHOWN_AT, HIDDEN_AT)
	view.show_debris([SHOWN_AT, HIDDEN_AT] as Array[Vector3], [1.0, 1.0] as Array[float],
		[true, true] as Array[bool], [false, false] as Array[bool], [0.0, 0.0] as Array[float])
	var problem: String = _pair("debris", view.entry(0), view.entry(1))
	view.free()
	return problem
