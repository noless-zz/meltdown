class_name MeltdownDebris
extends RefCounted

## Falling debris during the meltdown (RUN-4, first slice): solid spheres from the
## level file that appear at set times after the reactor dies. Ships bounce off
## them as off a wall (FLT-3) and shots of either side stop on them.
##
## Read from one JSON list, in the level file's optional `debris` key and in the
## replay's debris line alike, so there is one parser:
##
##     [{"position": [0, -15, -45], "radius": 1.5, "after_seconds": 10}, ...]
##
## Positions and radii are metres held as whole millimetres, and times are held
## as whole ticks, so debris is the same on every device (ARC-1, ARC-2). What
## falls, how big and when is data (ARC-4).
##
## Timing follows the meltdown countdown: an entry with `after_ticks` k is solid
## from the k-th tick after the one the reactor died on (the tick on which
## `ReactorState.meltdown_ticks_left` has gone down by k), and stays solid,
## unless `DebrisRouteGuard` held it back because it would have closed a ship's
## last route to the exit: then it is skipped and never becomes solid.

const KEYS: Array[String] = ["position", "radius", "after_seconds"]
const TICKS_PER_SECOND: int = 60

## Per entry, in file order: centre in millimetres, radius in millimetres and
## ticks after the reactor's death until it is solid (at least 1).
var positions_mm: Array[Vector3i] = []
var radii_mm: Array[int] = []
var after_ticks: Array[int] = []
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


## True once entry `index` has appeared, which a skipped entry never does.
func is_solid(index: int) -> bool:
	return elapsed_ticks >= after_ticks[index] and not is_skipped(index)


func is_skipped(index: int) -> bool:
	return index < skipped.size() and skipped[index]


## The same debris as before the first tick: nothing has fallen.
func fresh_copy() -> MeltdownDebris:
	var copy: MeltdownDebris = MeltdownDebris.new()
	copy.positions_mm = positions_mm.duplicate()
	copy.radii_mm = radii_mm.duplicate()
	copy.after_ticks = after_ticks.duplicate()
	copy.skipped.resize(size())
	copy.skipped.fill(false)
	return copy


## The JSON list `parse` reads back to these entries, at full precision.
func to_json() -> String:
	var scale: float = float(RobotSpawn.SCALE)
	var entries: Array = []
	for index: int in size():
		var at: Vector3i = positions_mm[index]
		entries.append({"position": [at.x / scale, at.y / scale, at.z / scale],
			"radius": radii_mm[index] / scale,
			"after_seconds": after_ticks[index] / float(TICKS_PER_SECOND)})
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
		var t: float = Projectile.segment_entry(from, to, position(index), radius(index))
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Pushes `ship` out of every solid entry it overlaps, in order, exactly as a
## wall does (`BoxBounds.contain_impact`): the overshoot along the line between
## centres is mirrored back out, the velocity into the sphere is reflected and
## scaled by the ship's restitution, and the wall damage applies. A ship caught
## inside when an entry appears is pushed out the same way. Returns the velocity
## carried into the debris, or Vector3.ZERO when nothing was hit.
func contain_impact(ship: ShipState) -> Vector3:
	var impact: Vector3 = Vector3.ZERO
	var bounce: float = ship.bounce_factor()
	for index: int in size():
		if not is_solid(index):
			continue
		var offset: Vector3 = ship.position - position(index)
		var reach: float = ship.radius + radius(index)
		var distance: float = offset.length()
		if distance >= reach:
			continue
		# A ship exactly at the centre has no line out; up is as good as any
		# and the same on every device.
		var normal: Vector3 = Vector3.UP if distance == 0.0 else offset / distance
		ship.position = position(index) + normal * (reach + (reach - distance) * bounce)
		var into: float = ship.velocity.dot(normal)
		if into < 0.0:
			impact += normal * into
			ship.velocity -= normal * into * (1.0 + bounce)
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
	for key: String in KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
	var read: Array[Vector3i] = []
	var problem: String = RobotSpawn.read_mm(data["position"], "position", read)
	if problem != "":
		return problem
	var radius_read: Array[int] = []
	problem = ReactorState.read_radius_mm(data["radius"], "radius", radius_read)
	if problem != "":
		return problem
	var seconds: Variant = data["after_seconds"]
	if typeof(seconds) != TYPE_FLOAT and typeof(seconds) != TYPE_INT \
			or not is_finite(float(seconds)) or float(seconds) < 0.0:
		return "after_seconds must be a number of at least zero"
	var ticks: int = roundi(float(seconds) * TICKS_PER_SECOND)
	if ticks < 1:
		return "after_seconds must be at least one tick"
	positions_mm.append(read[0])
	radii_mm.append(radius_read[0])
	after_ticks.append(ticks)
	skipped.append(false)
	return ""
