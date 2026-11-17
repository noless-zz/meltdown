class_name MeltdownFire
extends RefCounted

## Fire among the meltdown entries (RUN-4): an entry of `"kind": "fire"` is
## not solid. It never pushes a ship, never stops a shot and never closes an
## opening, so routes, the guard and the bot pass through it. From its fall tick
## it burns every ship whose centre is inside it, each tick, through
## `ShipState.apply_damage`, the path wall hits and shots take (CMB-2).
##
## The damage is read as whole thousandths of a point per second, so the data
## is the same on every device (ARC-1, ARC-2); how much fire burns is data
## (ARC-4). Kept out of `MeltdownDebris`, which is near its size limit.

const KIND_SOLID: String = "solid"
const KIND_FIRE: String = "fire"
## Keeps the thousandths well inside a whole number.
const MAX_DAMAGE_PER_SECOND: int = 100000
const MILLI: int = 1000


## Reads `kind` and `damage_per_second` from one entry and appends the damage
## in thousandths per second to `read_milli`: 0 for a solid entry. Returns "" or
## the problem, without the entry's index.
static func read(data: Dictionary, read_milli: Array[int]) -> String:
	var kind: Variant = data.get("kind", KIND_SOLID)
	if typeof(kind) != TYPE_STRING or kind != KIND_SOLID and kind != KIND_FIRE:
		return "kind must be \"%s\" or \"%s\"" % [KIND_SOLID, KIND_FIRE]
	if kind == KIND_SOLID:
		if data.has("damage_per_second"):
			return "damage_per_second is only for fire"
		read_milli.append(0)
		return ""
	if not data.has("damage_per_second"):
		return "missing key \"damage_per_second\""
	var value: Variant = data["damage_per_second"]
	var bad: String = "damage_per_second must be a number above zero and at most %d" \
		% MAX_DAMAGE_PER_SECOND
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT or not is_finite(float(value)) \
			or float(value) <= 0.0 or float(value) > MAX_DAMAGE_PER_SECOND:
		return bad
	var milli: int = roundi(float(value) * MILLI)
	if milli < 1:
		return "damage_per_second must be at least 0.001"
	read_milli.append(milli)
	return ""


## Adds the fire keys to `entry`, a dictionary `MeltdownDebris.to_json` is
## writing, for a fire entry only, so lists without fire write as before.
static func write(debris: MeltdownDebris, index: int, entry: Dictionary) -> void:
	if debris.is_fire(index):
		entry["kind"] = KIND_FIRE
		entry["damage_per_second"] = debris.fire_milli_dps[index] / float(MILLI)


## One tick of every burning entry `debris` holds on `ship`: each one whose
## volume holds the ship's centre deals a sixtieth of its damage per second.
static func burn(debris: MeltdownDebris, ship: ShipState) -> void:
	for index: int in debris.size():
		if debris.is_burning(index) and contains(debris, index, ship.position):
			ship.apply_damage(debris.fire_milli_dps[index] / float(MILLI * ShipState.TICK_RATE))


## Whether `point` lies inside entry `index`, its surface included.
static func contains(debris: MeltdownDebris, index: int, point: Vector3) -> bool:
	var local: Vector3 = point - debris.position(index)
	if debris.is_box(index):
		var half: Vector3 = debris.box_size(index) * 0.5
		return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z
	var radius: float = debris.radius(index)
	return local.length_squared() <= radius * radius
