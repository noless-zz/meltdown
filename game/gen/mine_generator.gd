class_name MineGenerator
extends RefCounted

## A first seeded mine generator (GEN-1, GEN-2, GEN-5): chains modules one by
## one, each joined to an open connector of a module already placed, connector
## to connector (same size class, outward axes opposite), turned in 90° steps
## (`ModuleTurns`), in whole millimetres.
##
## Joined connectors meet exactly, so the two modules only touch across the
## opening. Each join therefore adds a doorway box: the opening's square,
## reaching `DOOR_DEPTH_MM` into each module, so the level is one piece under
## `LevelDef.joined` and a ship can fly through (`BoxUnion` keeps a ship in
## one box at a time, and boxes that only touch would wall it in).
##
## A placement whose boxes (and doorway) overlap boxes already placed, other
## than the doorway inside the module it joins, is rejected and another tried,
## as is a dead end while fewer than `dead_end_min_open` connectors are open.
## After `MAX_TRIES` rejections in a row the generator stops short and says so
## in `note`. With `LoopBridges` (#396), facing open connectors are then
## bridged, and `loops` counts the bridges.
##
## Randomness comes only from a `RandomNumberGenerator` seeded with the given
## seed, read through `randi()` (ARC-2): no time, no global random calls.

## Rejected placements in a row before the generator stops short.
const MAX_TRIES: int = 64
## Open connectors needed before a dead end (a module with one connector) may
## take one. A dead end closes an opening without adding one, so on the last
## openings it would end the level early, or with no opening to start in.
## Below 6, some of seeds 0..9,999 stop short when their few remaining
## openings are walled in (#395). The default; `generator.json` sets the value
## used with bridges (#421).
const DEAD_END_MIN_OPEN: int = 6
## How far a doorway box reaches into each of the two modules it joins. Above
## `LevelDef.MIN_OVERLAP_M`, so the doorway counts as joined to both.
const DOOR_DEPTH_MM: int = 3000
## How far inside its opening `to_level_def` puts the start: a ship's radius
## clear of the face for any ship up to 3 m across, while every shipped module
## is deeper than that at each opening.
const START_INSET_MM: int = 3000

## The placed modules, in placement order.
var placements: Array[ModulePlacement] = []
## The level's boxes in metres, in placement order: each module's boxes, then
## its doorway.
var union: BoxUnion = BoxUnion.new()
## The same boxes' corners in millimetres, for exact checks.
var min_mm: Array[Vector3i] = []
var max_mm: Array[Vector3i] = []
## Connectors no module has been joined to, in level space, oldest first.
var open_connectors: Array[ModuleConnector] = []
## Which placement each open connector belongs to, and its index there.
var open_owner: Array[Vector2i] = []
## Empty when every requested module was placed; otherwise why it stopped.
var note: String = ""
## Tunnels `LoopBridges` added between facing open connectors: each closes a loop.
var loops: int = 0
## Open connectors needed before a dead end may join: from `bridges` when
## given one without an `error`, else `DEAD_END_MIN_OPEN`.
var dead_end_min_open: int = DEAD_END_MIN_OPEN
## Set by `to_level_def`: why a requested reactor was left out, else empty.
var reactor_note: String = ""
## Set by `to_level_def`: the placement holding the reactor, or -1.
var reactor_placement: int = -1
## Set by `to_level_def`: why fewer robots than a `RobotPlan` asked for were
## placed, else empty.
var robot_note: String = ""
## Set by `to_level_def`: why a `DebrisPlan` placed no debris, or fewer entries
## than it drew, else empty.
var debris_note: String = ""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The bridges given to `generate`, for `loop_bias` (#438), or null.
var _bridges: LoopBridges = null


## Builds a level of up to `count` modules from `modules` (rejected modules,
## those with an `error`, are left out) for `level_seed`, then, with `bridges`
## (one without an `error`), closes loops and takes its `dead_end_min_open`.
## Without it the level is a tree.
static func generate(level_seed: int, modules: Array[ModuleDef], count: int,
		bridges: LoopBridges = null) -> MineGenerator:
	var generator: MineGenerator = MineGenerator.new()
	if bridges != null and bridges.error == "":
		generator.dead_end_min_open = bridges.dead_end_min_open
		generator._bridges = bridges
	generator._run(level_seed, modules, count)
	if bridges != null and bridges.error == "" and not generator.placements.is_empty():
		generator.loops = bridges.apply(generator)
	return generator


## One number for the whole output: placements, boxes and open connectors.
func output_hash() -> int:
	var parts: Array = []
	for placement: ModulePlacement in placements:
		parts.append_array([hash(placement.module_id), placement.turn, placement.offset_mm,
				placement.parent, placement.parent_connector, placement.connector])
	parts.append(hash("boxes"))
	for index: int in min_mm.size():
		parts.append_array([min_mm[index], max_mm[index]])
	parts.append(hash("open"))
	for connector: ModuleConnector in open_connectors:
		parts.append_array([connector.position_mm, hash(connector.axis_name), hash(connector.size_class)])
	return hash(parts)


## The level as a `LevelDef` the game can fly (#317): these boxes
## and the start inside the oldest open connector. With `reactor_plan` (#356)
## it also gets a reactor in the module furthest from the first, or none and a
## `reactor_note`; `ship_radius` sets the clearance around it. See
## `GeneratedLevel`. With `robot_plan` (#378) it also gets robots; without it
## it has none. With `debris_plan` (#398) it gets meltdown debris; without it
## it has none. Not part of `output_hash`, which covers placements only.
func to_level_def(reactor_plan: ReactorPlan = null, ship_radius: float = 1.0,
		robot_plan: RobotPlan = null, debris_plan: DebrisPlan = null) -> LevelDef:
	return GeneratedLevel.build(self, reactor_plan, ship_radius, robot_plan, debris_plan)


## A module's connector `index`, turned by `turn` and moved by `offset_mm`.
static func placed_connector(module: ModuleDef, index: int, turn: int, offset_mm: Vector3i) -> ModuleConnector:
	var source: ModuleConnector = module.connectors[index]
	return ModuleConnector.new(
			ModuleTurns.apply(turn, source.position_mm) + offset_mm,
			ModuleTurns.axis_name(ModuleTurns.apply(turn, ModuleTurns.outward(source))),
			source.size_class)


func _run(level_seed: int, modules: Array[ModuleDef], count: int) -> void:
	_rng.seed = level_seed
	var usable: Array[ModuleDef] = []
	for module: ModuleDef in modules:
		if module.error == "" and not module.connectors.is_empty():
			usable.append(module)
	if usable.is_empty() or count < 1:
		note = "nothing to place: %d usable modules, %d requested" % [usable.size(), count]
		return
	var first: ModuleDef = usable[_pick(usable.size())]
	_place(first, 0, Vector3i.ZERO, -1, -1, -1, [])
	var by_id: Dictionary[String, ModuleDef] = {}
	for module: ModuleDef in usable:
		by_id[module.id] = module
	while placements.size() < count:
		if not _place_one(usable, by_id):
			note = "stopped after %d of %d modules: %s" % [placements.size(), count,
					"no open connector left" if open_connectors.is_empty()
					else "no placement fit in %d tries" % MAX_TRIES]
			return


## Tries up to `MAX_TRIES` placements; true when one fits. With a
## `loop_bias` and the seeded draw under it, keeps looking among up to
## `LoopBias.CANDIDATES` that fit for one that faces an open connector (#438).
func _place_one(usable: Array[ModuleDef], by_id: Dictionary[String, ModuleDef]) -> bool:
	var biased: bool = _bridges != null and _bridges.loop_bias_permille > 0 \
			and _pick(LoopBias.SCALE) < _bridges.loop_bias_permille
	var kept: PlacementChoice = null
	var fitted: int = 0
	for attempt: int in MAX_TRIES:
		if open_connectors.is_empty():
			return false
		var choice: PlacementChoice = _draw(usable)
		if choice == null:
			continue
		if not biased:
			kept = choice
			break
		if kept == null:
			kept = choice
		if LoopBias.facing(self, _bridges, choice) > 0:
			kept = choice
			break
		fitted += 1
		if fitted >= LoopBias.CANDIDATES:
			break
	if kept == null:
		return false
	var owner: Vector2i = open_owner[kept.open_index]
	open_connectors.remove_at(kept.open_index)
	open_owner.remove_at(kept.open_index)
	_place(kept.module, kept.turn, kept.offset_mm, owner.x, owner.y, kept.own, kept.door)
	return true


## One placement drawn from the seeded generator, or null when it does not fit.
func _draw(usable: Array[ModuleDef]) -> PlacementChoice:
	var open_index: int = _pick(open_connectors.size())
	var target: ModuleConnector = open_connectors[open_index]
	var module: ModuleDef = usable[_pick(usable.size())]
	var own: int = _pick(module.connectors.size())
	var joining: ModuleConnector = module.connectors[own]
	if joining.size_class != target.size_class:
		return null
	if module.connectors.size() == 1 and open_connectors.size() < dead_end_min_open:
		return null
	var turns: Array[int] = ModuleTurns.turns_between(ModuleTurns.outward(joining),
			-ModuleTurns.outward(target))
	var turn: int = turns[_pick(turns.size())]
	var offset: Vector3i = target.position_mm - ModuleTurns.apply(turn, joining.position_mm)
	var door: Array[Vector3i] = door_for(target)
	if not _fits(module, turn, offset, door, open_owner[open_index].x):
		return null
	var choice: PlacementChoice = PlacementChoice.new()
	choice.module = module
	choice.turn = turn
	choice.offset_mm = offset
	choice.open_index = open_index
	choice.own = own
	choice.door = door
	return choice


func _place(module: ModuleDef, turn: int, offset: Vector3i, parent: int, parent_connector: int,
		own: int, door: Array[Vector3i]) -> void:
	var placement: ModulePlacement = ModulePlacement.new(module.id, turn, offset)
	placement.parent = parent
	placement.parent_connector = parent_connector
	placement.connector = own
	placement.first_box = min_mm.size()
	for box: BoxBounds in module.boxes:
		var corners: Array[Vector3i] = _turned_box(box, turn, offset)
		add_box(corners[0], corners[1])
	placement.end_box = min_mm.size()
	if not door.is_empty():
		placement.door_box = min_mm.size()
		add_box(door[0], door[1])
	var index: int = placements.size()
	placements.append(placement)
	for connector_index: int in module.connectors.size():
		if connector_index != own:
			open_connectors.append(placed_connector(module, connector_index, turn, offset))
			open_owner.append(Vector2i(index, connector_index))


## True if the module's turned boxes and its doorway overlap nothing placed,
## apart from the doorway reaching into the parent module.
func _fits(module: ModuleDef, turn: int, offset: Vector3i, door: Array[Vector3i], parent: int) -> bool:
	var parent_placement: ModulePlacement = placements[parent]
	for index: int in min_mm.size():
		if index >= parent_placement.first_box and index < parent_placement.end_box:
			pass
		elif MineGenerator.overlaps(door[0], door[1], min_mm[index], max_mm[index]):
			return false
	for box: BoxBounds in module.boxes:
		var corners: Array[Vector3i] = _turned_box(box, turn, offset)
		for index: int in min_mm.size():
			if MineGenerator.overlaps(corners[0], corners[1], min_mm[index], max_mm[index]):
				return false
	return true


## True if two boxes share some volume; boxes that only touch do not.
static func overlaps(a_min: Vector3i, a_max: Vector3i, b_min: Vector3i, b_max: Vector3i) -> bool:
	for axis: int in 3:
		if mini(a_max[axis], b_max[axis]) <= maxi(a_min[axis], b_min[axis]):
			return false
	return true


## The doorway box for an opening: its square across the axis, `DOOR_DEPTH_MM`
## either side of the face along it.
static func door_for(connector: ModuleConnector) -> Array[Vector3i]:
	var half: int = connector.size_mm() / 2
	var low: Vector3i = connector.position_mm - Vector3i(half, half, half)
	var high: Vector3i = connector.position_mm + Vector3i(half, half, half)
	low[connector.axis()] = connector.position_mm[connector.axis()] - DOOR_DEPTH_MM
	high[connector.axis()] = connector.position_mm[connector.axis()] + DOOR_DEPTH_MM
	return [low, high]


## A module box turned and moved, as millimetre corners [min, max].
static func _turned_box(box: BoxBounds, turn: int, offset: Vector3i) -> Array[Vector3i]:
	var scale: float = float(RobotSpawn.SCALE)
	var a: Vector3i = ModuleTurns.apply(turn, Vector3i((box.min_corner * scale).round())) + offset
	var b: Vector3i = ModuleTurns.apply(turn, Vector3i((box.max_corner * scale).round())) + offset
	return [Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)),
			Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))]


## Appends a box to the level, in millimetres and in `union`.
func add_box(low: Vector3i, high: Vector3i) -> void:
	min_mm.append(low)
	max_mm.append(high)
	var scale: float = float(RobotSpawn.SCALE)
	union.boxes.append(BoxBounds.new(Vector3(low) / scale, Vector3(high) / scale))


## A whole number from 0 up to, not including, `size`, from the seeded generator.
func _pick(size: int) -> int:
	return int(_rng.randi() % size)
