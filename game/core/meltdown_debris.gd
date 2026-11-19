class_name MeltdownDebris
extends RefCounted

## Falling debris during the meltdown (RUN-4): solid spheres (rocks) and
## axis-aligned boxes (blast doors, cave-ins) from the level file that appear at
## set times after the reactor dies. Ships bounce off them as off a wall (FLT-3)
## and shots of either side stop on them. The shape tests are `DebrisShapes`.
## An entry of `"kind": "fire"` is never solid and burns ships instead; see
## `MeltdownFire`.
##
## Read from one JSON list, in the level file's optional `debris` key and in the
## replay's debris line alike, so there is one parser:
##
##     [{"position": [0, -15, -45], "radius": 1.5, "after_seconds": 10},
##      {"position": [0, 0, -80], "size": [6, 6, 0.5], "after_seconds": 20}, ...]
##
## An entry gives exactly one of `radius` (a sphere) and `size` (a box's full
## extent on x, y and z, each at least 0.1, centred on `position`). Positions,
## radii and sizes are metres held as whole millimetres, and times are held
## as whole ticks, so debris is the same on every device (ARC-1, ARC-2). What
## falls, how big and when is data (ARC-4).
##
## Timing follows the meltdown countdown: an entry with `after_ticks` k is solid
## from the k-th tick after the one the reactor died on (the tick on which
## `ReactorState.meltdown_ticks_left` has gone down by k), and stays solid,
## unless `DebrisRouteGuard` held it back because it would have closed a ship's
## last route to the exit: then it is skipped and never becomes solid.

const KEYS: Array[String] = ["position", "radius", "size", "after_seconds", "kind",
	"damage_per_second"]
## Each side of a box entry is at least this many millimetres.
const MIN_SIZE_MM: int = 100
const TICKS_PER_SECOND: int = 60

## Per entry, in file order: centre in millimetres, radius in millimetres (0
## for a box) and ticks after the reactor's death until it is solid (at least 1).
var positions_mm: Array[Vector3i] = []
var radii_mm: Array[int] = []
## Per entry: a box's full size in millimetres, or zero for a sphere. Code that
## builds spheres may leave it short; a missing entry is a sphere.
var sizes_mm: Array[Vector3i] = []
var after_ticks: Array[int] = []
## Per entry: a fire's damage in thousandths of a point per second, or 0 for a
## solid entry. Code that builds solid entries may leave it short.
var fire_milli_dps: Array[int] = []
## Per entry: held back by `DebrisRouteGuard` when it fell due, so never solid.
## Part of the hash only once one is set, so runs with nothing held keep theirs.
var skipped: Array[bool] = []
## Ticks since the reactor died: 0 while it is intact, 1 on the tick after the
## one it died on. Kept no higher than the latest entry needs. Part of the hash.
var elapsed_ticks: int = 0
## Set by `parse` when the data was rejected; empty otherwise.
var error: String = ""


## Reads debris from `value`, a parsed JSON list. On failure `error` is set,
## naming the entry's index and key, and the list is empty.
static func parse(value: Variant) -> MeltdownDebris:
	var debris: MeltdownDebris = MeltdownDebris.new()
	var problem: String = debris._read(value)
	if problem != "":
		debris = MeltdownDebris.new()
		debris.error = "debris" + problem
	return debris


## Reads debris from JSON text, as in the replay's debris line.
static func parse_json(text: String) -> MeltdownDebris:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		var failed: MeltdownDebris = MeltdownDebris.new()
		failed.error = "debris: invalid JSON: %s" % json.get_error_message()
		return failed
	return parse(json.data)


func size() -> int:
	return positions_mm.size()


func position(index: int) -> Vector3:
	return Vector3(positions_mm[index]) / float(RobotSpawn.SCALE)


func radius(index: int) -> float:
	return radii_mm[index] / float(RobotSpawn.SCALE)


func is_box(index: int) -> bool:
	return index < sizes_mm.size() and sizes_mm[index] != Vector3i.ZERO


## A box entry's full size in metres; zero for a sphere.
func box_size(index: int) -> Vector3:
	if not is_box(index):
		return Vector3.ZERO
	return Vector3(sizes_mm[index]) / float(RobotSpawn.SCALE)


## True once entry `index` has appeared, which a skipped entry never does.
func has_fallen(index: int) -> bool:
	return elapsed_ticks >= after_ticks[index] and not is_skipped(index)


## True once a solid entry has appeared: it blocks ships, shots and routes.
func is_solid(index: int) -> bool:
	return has_fallen(index) and not is_fire(index)


## True once a fire entry has appeared: it burns ships inside it.
func is_burning(index: int) -> bool:
	return has_fallen(index) and is_fire(index)


func is_fire(index: int) -> bool:
	return index < fire_milli_dps.size() and fire_milli_dps[index] > 0


func is_skipped(index: int) -> bool:
	return index < skipped.size() and skipped[index]


## The same debris as before the first tick: nothing has fallen.
func fresh_copy() -> MeltdownDebris:
	var copy: MeltdownDebris = MeltdownDebris.new()
	copy.positions_mm = positions_mm.duplicate()
	copy.radii_mm = radii_mm.duplicate()
	copy.sizes_mm = sizes_mm.duplicate()
	copy.after_ticks = after_ticks.duplicate()
	copy.fire_milli_dps = fire_milli_dps.duplicate()
	copy.skipped.resize(size())
	copy.skipped.fill(false)
	return copy


## The JSON list `parse` reads back to these entries, at full precision.
func to_json() -> String:
	var scale: float = float(RobotSpawn.SCALE)
	var entries: Array = []
	for index: int in size():
		var at: Vector3i = positions_mm[index]
		# Keys in this order, so sphere-only lists write exactly as before boxes.
		var entry: Dictionary = {"position": [at.x / scale, at.y / scale, at.z / scale]}
		if is_box(index):
			var extent: Vector3i = sizes_mm[index]
			entry["size"] = [extent.x / scale, extent.y / scale, extent.z / scale]
		else:
			entry["radius"] = radii_mm[index] / scale
		entry["after_seconds"] = after_ticks[index] / float(TICKS_PER_SECOND)
		MeltdownFire.write(self, index, entry)
		entries.append(entry)
	return JSON.stringify(entries, "", false, true)


## One tick of the clock. `Sim.step` calls it at the start of every tick, right
## after the reactor's countdown, so a shot that kills the reactor on tick T
## lets debris with `after_ticks` 1 stop shots and ships from tick T + 1.
func advance(reactor: ReactorState) -> void:
	if elapsed_ticks > 0:
		elapsed_ticks = mini(elapsed_ticks + 1, _latest())
	elif reactor != null and reactor.destroyed:
		elapsed_ticks = 1


## Where the segment `from`..`to` first enters solid debris, as a fraction
## 0..1, or -1.0 if it enters none. Entries are tested in order and only a
## strictly nearer one replaces the best.
func segment_entry(from: Vector3, to: Vector3) -> float:
	var best: float = -1.0
	for index: int in size():
		if not is_solid(index):
			continue
		var t: float = DebrisShapes.box_entry(from, to, position(index), box_size(index) * 0.5) \
			if is_box(index) else DebrisShapes.sphere_entry(from, to, position(index), radius(index))
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Pushes `ship` out of every solid entry it overlaps, in order, exactly as a
## wall does (`BoxBounds.contain_impact`): the overshoot is mirrored back out,
## the velocity into the entry is reflected and scaled by the ship's
## restitution, and the wall damage applies once for all of them. A ship caught
## inside when an entry appears is pushed out the same way. Returns the velocity
## carried into the debris, or Vector3.ZERO when nothing was hit.
func contain_impact(ship: ShipState) -> Vector3:
	var impact: Vector3 = Vector3.ZERO
	var bounce: float = ship.bounce_factor()
	for index: int in size():
		if not is_solid(index):
			continue
		if is_box(index):
			impact += DebrisShapes.push_out_of_box(ship, position(index), box_size(index) * 0.5, bounce)
		else:
			impact += DebrisShapes.push_out_of_sphere(ship, position(index), radius(index), bounce)
	var impact_speed: float = impact.length()
	if impact_speed > 0.0:
		ship.take_wall_hit(impact_speed)
	return impact


## Which entries are solid, through the clock that decides it and the entries
## held back. The held ones join only when there are any, so every hash pinned
## before the guard existed stands.
func state_hash() -> int:
	var held: Array[int] = []
	for index: int in size():
		if is_skipped(index):
			held.append(index)
	if held.is_empty():
		return hash(["debris", elapsed_ticks])
	return hash(["debris", elapsed_ticks, held])


## The most ticks any entry waits; the clock need not count further.
func _latest() -> int:
	var latest: int = 1
	for ticks: int in after_ticks:
		latest = maxi(latest, ticks)
	return latest


## Returns "" or the problem, starting with ": " or " <index>: " so `parse`
## can put "debris" in front.
func _read(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ": must be a list"
	var entries: Array = value
	for index: int in entries.size():
		var problem: String = _read_entry(entries[index])
		if problem != "":
			return " %d: %s" % [index, problem]
	return ""


func _read_entry(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in ["position", "after_seconds"]:
		if not data.has(key):
			return "missing key \"%s\"" % key
	if data.has("radius") == data.has("size"):
		return "needs exactly one of \"radius\" and \"size\""
	var read: Array[Vector3i] = []
	var problem: String = RobotSpawn.read_mm(data["position"], "position", read)
	if problem != "":
		return problem
	var radius_read: Array[int] = []
	if data.has("radius"):
		problem = ReactorState.read_radius_mm(data["radius"], "radius", radius_read)
	else:
		radius_read.append(0)
		problem = _read_size(data["size"], read)
	if problem != "":
		return problem
	var seconds: Variant = data["after_seconds"]
	if typeof(seconds) != TYPE_FLOAT and typeof(seconds) != TYPE_INT \
			or not is_finite(float(seconds)) or float(seconds) < 0.0:
		return "after_seconds must be a number of at least zero"
	var ticks: int = roundi(float(seconds) * TICKS_PER_SECOND)
	if ticks < 1:
		return "after_seconds must be at least one tick"
	var fire: Array[int] = []
	problem = MeltdownFire.read(data, fire)
	if problem != "":
		return problem
	positions_mm.append(read[0])
	radii_mm.append(radius_read[0])
	sizes_mm.append(read[1] if read.size() > 1 else Vector3i.ZERO)
	after_ticks.append(ticks)
	fire_milli_dps.append(fire[0])
	skipped.append(false)
	return ""


## Appends the size to `read` after the position.
func _read_size(value: Variant, read: Array[Vector3i]) -> String:
	var problem: String = RobotSpawn.read_mm(value, "size", read)
	if problem != "":
		return problem
	var extent: Vector3i = read[1]
	if mini(extent.x, mini(extent.y, extent.z)) < MIN_SIZE_MM:
		return "size must be at least 0.1 m on every axis"
	return ""
