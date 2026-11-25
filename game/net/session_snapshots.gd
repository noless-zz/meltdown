class_name SessionSnapshots
extends RefCounted

## The copies `LocalSession` hands to the view. The view reads these and never
## the simulation's own objects, so nothing it does can write simulation state
## (MP-2). Kept out of `local_session.gd` so that file stays under its size
## limit (#296).

## Keys of the `debris` snapshot: metres, metres, and seconds until solid.
const DEBRIS_POSITIONS: String = "positions_m"
const DEBRIS_RADII: String = "radii_m"
## A box entry's full size in metres; `Vector3.ZERO` for a sphere (#459).
const DEBRIS_SIZES: String = "sizes_m"
const DEBRIS_SOLID: String = "solid"
const DEBRIS_HELD: String = "held"
const DEBRIS_SECONDS: String = "seconds_to_solid"
## Each entry's kind, `MeltdownFire.KIND_SOLID` or `KIND_FIRE` (#496). A fire
## is never solid, so without this the view could not tell a burning fire from a
## rock still to fall.
const DEBRIS_KINDS: String = "kinds"


## The alarm level of `alarm`, 0..1, as a plain number; 0 without an alarm
## (RUN-6, #1342). The view reads this and never the `Alarm` itself.
static func alarm_level(alarm: Alarm) -> float:
	return 0.0 if alarm == null else alarm.level


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


## Plain copies of the simulation's meltdown debris for the view (RUN-4, MP-2):
## a Dictionary of parallel arrays under the `DEBRIS_*` keys, every one empty
## for null. The view gets values, never the live `MeltdownDebris`.
## `DEBRIS_SIZES` holds a box's full size and zero for a sphere, so the other
## keys keep the values they had before boxes (a box's radius is zero).
## `DEBRIS_SECONDS` is the time until an entry is solid: zero once it is, and
## INF while the reactor lives (the clock has not started) or for a held
## entry, which never falls. For a fire it is the time until it starts to burn.
## `DEBRIS_KINDS` names each entry's kind; the other keys do not depend on it.
static func debris(source: MeltdownDebris) -> Dictionary:
	var positions: Array[Vector3] = []
	var radii: Array[float] = []
	var sizes: Array[Vector3] = []
	var solid: Array[bool] = []
	var held: Array[bool] = []
	var seconds: Array[float] = []
	var kinds: Array[String] = []
	var count: int = 0 if source == null else source.size()
	for index: int in count:
		positions.append(source.position(index))
		radii.append(source.radius(index))
		sizes.append(source.box_size(index))
		solid.append(source.is_solid(index))
		held.append(source.is_skipped(index))
		seconds.append(_seconds_until_solid(source, index))
		kinds.append(MeltdownFire.KIND_FIRE if source.is_fire(index) else MeltdownFire.KIND_SOLID)
	return {DEBRIS_POSITIONS: positions, DEBRIS_RADII: radii, DEBRIS_SIZES: sizes,
		DEBRIS_SOLID: solid, DEBRIS_HELD: held, DEBRIS_SECONDS: seconds, DEBRIS_KINDS: kinds}


static func _seconds_until_solid(source: MeltdownDebris, index: int) -> float:
	if source.is_skipped(index) or source.elapsed_ticks == 0:
		return INF
	var ticks: int = maxi(source.after_ticks[index] - source.elapsed_ticks, 0)
	return float(ticks) / float(MeltdownDebris.TICKS_PER_SECOND)


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
