class_name SessionSnapshots
extends RefCounted

## The copies `LocalSession` hands to the view. The view reads these and never
## the simulation's own objects, so nothing it does can write simulation state
## (MP-2). Kept out of `local_session.gd` so that file stays under its size
## limit (#296).


## A copy of `ship`: writing to it changes nothing in the simulation.
static func ship(source: ShipState) -> ShipState:
	var copy: ShipState = ShipState.new()
	copy_fields(source, copy)
	return copy


## Copies of `source`, keyed by the simulation's projectile, in the
## simulation's order. A projectile keeps the copy it has in `previous`, so the
## view can tell a bolt it already drew from a new one and blend it between
## ticks; the copies of removed projectiles are dropped.
static func projectiles(source: Array[Projectile],
		previous: Dictionary[Projectile, Projectile]) -> Dictionary[Projectile, Projectile]:
	var copies: Dictionary[Projectile, Projectile] = {}
	for projectile: Projectile in source:
		var copy: Projectile = previous.get(projectile, null) as Projectile
		if copy == null:
			copy = Projectile.new()
		copy_fields(projectile, copy)
		copies[projectile] = copy
	return copies


## A copy of each robot. The type is shared: `RobotDef` is never changed
## after it is read.
static func robots(source: Array[RobotState]) -> Array[RobotState]:
	var copies: Array[RobotState] = []
	for robot: RobotState in source:
		var copy: RobotState = RobotState.new(robot.def)
		copy_fields(robot, copy)
		copies.append(copy)
	return copies


## A copy of each floating part.
static func salvage(source: Array[SalvageItem]) -> Array[SalvageItem]:
	var copies: Array[SalvageItem] = []
	for item: SalvageItem in source:
		var copy: SalvageItem = SalvageItem.new()
		copy_fields(item, copy)
		copies.append(copy)
	return copies


## A copy of the level's reactor, or null when there is none. The view reads
## its position, hull and countdown from this, never from the simulation's own
## reactor (MP-2).
static func reactor(source: ReactorState) -> ReactorState:
	if source == null:
		return null
	var copy: ReactorState = ReactorState.new()
	copy_fields(source, copy)
	return copy


## Copies every script variable, so fields added to `ShipState` or
## `Projectile` later are carried along without changing this file.
static func copy_fields(from: Object, to: Object) -> void:
	for property: Dictionary in from.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var prop_name: String = property["name"]
			to.set(prop_name, from.get(prop_name))


## `metres` rounded to the whole millimetres a replay stores walls in.
static func to_mm(metres: Vector3) -> Vector3i:
	return Vector3i((metres * float(Replay.BOX_SCALE)).round())
