class_name RobotSpawn
extends RefCounted

## One robot placed before the first tick: its type, where it starts and which
## way it faces (CMB-3). Spawns are data (ARC-4): a level file lists them and
## `RobotSpawnList` reads it; the replay records them, so a replay starts with
## the same robots as the run it recorded (ARC-2).
##
## Position and facing are kept in whole millimetres, like the replay's box,
## so the text a replay writes reads back exactly and the orientation worked
## out from it is the same on every run.

## Millimetres per metre.
const SCALE: int = 1000
## Furthest a spawn may be from the origin on any axis, metres. Far beyond any
## level, and small enough that millimetres stay exact in a float.
const MAX_COORDINATE_M: float = 10000.0

## The robot's type, resolved from its data file; null until resolved.
var def: RobotDef = null
## The weapon it fires, resolved by the caller from `def.weapon` because core
## opens no files; null for an unarmed robot. Carried here so a replay spawns
## the robot with exactly the weapon it had (ARC-2, #266).
var weapon: WeaponDef = null
## Id of the type, the data file's name without `.json`.
var id: String = ""
var position_mm: Vector3i = Vector3i.ZERO
## Direction the robot faces at spawn, any non-zero length.
var facing_mm: Vector3i = Vector3i(0, 0, -SCALE)


func _init(p_def: RobotDef = null, p_position_mm: Vector3i = Vector3i.ZERO,
		p_facing_mm: Vector3i = Vector3i(0, 0, -SCALE), p_weapon: WeaponDef = null) -> void:
	def = p_def
	weapon = p_weapon
	id = p_def.id if p_def != null else ""
	position_mm = p_position_mm
	facing_mm = p_facing_mm


## Where the robot starts, metres.
func position() -> Vector3:
	return Vector3(position_mm) / float(SCALE)


## The robot's starting orientation: its local -z (its forward) along the
## facing, with up as near world up as it can be. Straight up or down uses
## world back as the up hint, since world up is then undefined.
func orientation() -> Basis:
	return facing_basis(facing_mm)


## The orientation whose local -z points along `p_facing_mm` (any non-zero
## length), rolled as `orientation` describes. Shared with the replay's start
## line (#328), so a ship and a robot facing the same way get the same basis.
static func facing_basis(p_facing_mm: Vector3i) -> Basis:
	var direction: Vector3 = Vector3(p_facing_mm).normalized()
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.999:
		up = Vector3.BACK
	return Basis.looking_at(direction, up)


## Adds every spawn with a resolved type to `sim`, armed with its weapon if it
## has one, in list order: the order
## decides each robot's index and so its strafe direction. Returns false,
## after spawning nothing, if any spawn is unresolved or the sim refuses one.
static func spawn_all(sim: Sim, spawns: Array[RobotSpawn]) -> bool:
	for spawn: RobotSpawn in spawns:
		if spawn.def == null:
			return false
	for spawn: RobotSpawn in spawns:
		if sim.spawn_robot(spawn.def, spawn.position(), spawn.orientation(), spawn.weapon) < 0:
			return false
	return true


## Millimetres from a JSON array of three numbers in metres, in `into`.
## Returns "" or the problem, naming `what`.
static func read_mm(value: Variant, what: String, into: Array[Vector3i]) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "%s must be a list of three numbers" % what
	var mm: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		var number: Variant = (value as Array)[axis]
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
			return "%s must be a list of three numbers" % what
		var metres: float = float(number)
		if not is_finite(metres) or absf(metres) > MAX_COORDINATE_M:
			return "%s must be within %s m of the origin" % [what, MAX_COORDINATE_M]
		mm[axis] = roundi(metres * SCALE)
	into.append(mm)
	return ""
