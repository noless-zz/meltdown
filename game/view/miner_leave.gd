class_name MinerLeave
extends Node3D

## A rescued miner visibly boarding (#1375, SLV-3, ARC-4). The owner's G4
## note: a rescued miner was "gone but no notice", its marker simply vanished.
## Now, at `MINER_RESCUED`, a copy of the miner (beacon and pod) rises from
## where it waited into the ship that rescued it, shrinking as it goes, and is
## gone after `seconds`. When the rescuer is not the local ship, it rises
## `rise_m` straight up instead.
##
## It reads copies of the events and the ship it is handed and writes nothing
## back (MP-2); its clock is the view's own. Its look is the optional `leave`
## entry of `miner_look.json`:
##
##     "leave": {"seconds": s, "end_scale": 0..1, "rise_m": m}
##
## Without it, `FALLBACK` applies, so a rescue is always seen.

const NODE_NAME: String = "MinerLeave"
const KEY: String = "leave"
const COPY_PREFIX: String = "Leaving"
const KEYS: Array[String] = ["seconds", "end_scale", "rise_m"]
const RANGES: Dictionary = {"seconds": [0.2, 3.0], "end_scale": [0.0, 1.0], "rise_m": [0.0, 10.0]}
const FALLBACK: Dictionary = {"seconds": 0.9, "end_scale": 0.1, "rise_m": 1.5}

## Leavings started since this view was built, and the most seconds one was
## drawn for; acceptance and tests read them.
var started_count: int = 0
var longest_drawn_seconds: float = 0.0
## The furthest a leaving started from where that miner's marker was drawn.
var largest_offset_m: float = 0.0

var _look: Dictionary = FALLBACK
var _beacon_mesh: Mesh = null
var _pod: MinerPod = MinerPod.new()
var _copies: Array[Node3D] = []
var _ages: Array[float] = []
var _from: Array[Vector3] = []
## Whether each copy rises into the local ship (true) or straight up.
var _into_ship: Array[bool] = []


func _init() -> void:
	name = NODE_NAME


## `{"seconds", "end_scale", "rise_m"}` as floats, or `{"error": ...}`
## naming the field.
static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "key \"%s\" must be an object" % KEY}
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(key):
			return {"error": "\"%s\" has unknown key \"%s\"" % [KEY, str(key)]}
	var look: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			return {"error": "\"%s.%s\" is missing" % [KEY, key]}
		var problem: String = MinerLook.check_number("%s.%s" % [KEY, key], data[key], RANGES[key])
		if problem != "":
			return {"error": problem}
		look[key] = float(data[key])
	return look


## Uses `look` (a parsed entry, or empty for `FALLBACK`) and draws each copy
## with `beacon_mesh` and `pod`, as the waiting miner is drawn. Drops any
## copy in flight.
func configure(look: Dictionary, beacon_mesh: Mesh, pod: MinerPod) -> void:
	_look = FALLBACK if look.is_empty() else look
	_beacon_mesh = beacon_mesh
	_pod = pod
	for leaving: Node3D in _copies:
		leaving.free()
	_copies.clear()
	_ages.clear()
	_from.clear()
	_into_ship.clear()


func look() -> Dictionary:
	return _look


## Starts a leaving for every `MINER_RESCUED` in `events`. `markers` are the
## view's miner markers as last drawn, by index in `MinerRescue.trapped`
## before the rescue, to record how far the leaving starts from the marker.
func feed(events: Array[SimEvent], markers: Array[Node3D]) -> void:
	for event: SimEvent in events:
		if event.kind != SimEvent.Kind.MINER_RESCUED:
			continue
		var index: int = int(event.magnitude)
		if index >= 0 and index < markers.size() and markers[index].visible:
			largest_offset_m = maxf(largest_offset_m, markers[index].position.distance_to(event.vector))
		start(event.vector, event.ship == 0)


## Starts one leaving from `at`, into the local ship when `into_ship`. It
## shows from the next `advance`.
func start(at: Vector3, into_ship: bool) -> void:
	var index: int = _free_index()
	_ages[index] = 0.0
	_from[index] = at
	_into_ship[index] = into_ship
	_copies[index].position = at
	_copies[index].visible = false
	started_count += 1


## Runs every leaving on by `delta` seconds; a copy rising into the ship heads
## for `ship`'s position as it is now.
func advance(delta: float, ship: ShipState) -> void:
	var seconds: float = _look["seconds"]
	for index: int in _copies.size():
		var leaving: Node3D = _copies[index]
		if _ages[index] >= seconds:
			leaving.visible = false
			continue
		var age: float = _ages[index]
		var t: float = progress_at(age)
		var to: Vector3 = _from[index] + Vector3.UP * float(_look["rise_m"])
		if _into_ship[index] and ship != null:
			to = ship.position
		leaving.position = _from[index].lerp(to, t * t)
		leaving.scale = Vector3.ONE * maxf(lerpf(1.0, _look["end_scale"], t), 0.001)
		leaving.visible = true
		longest_drawn_seconds = maxf(longest_drawn_seconds, age)
		_ages[index] = age + maxf(delta, 0.0)


## How far through its leaving a copy is `age` seconds after it started, 0..1.
func progress_at(age: float) -> float:
	return clampf(age / float(_look["seconds"]), 0.0, 1.0)


## Copies drawn now.
func shown_count() -> int:
	var shown: int = 0
	for leaving: Node3D in _copies:
		if leaving.visible:
			shown += 1
	return shown


## The pooled copy at `index`, for tests.
func copy(index: int) -> Node3D:
	return _copies[index]


func _free_index() -> int:
	for index: int in _copies.size():
		if _ages[index] >= _look["seconds"]:
			return index
	var leaving: Node3D = Node3D.new()
	leaving.name = "%s%d" % [COPY_PREFIX, _copies.size()]
	leaving.visible = false
	var beacon: MeshInstance3D = MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = _beacon_mesh
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaving.add_child(beacon)
	_pod.dress(leaving)
	add_child(leaving)
	_copies.append(leaving)
	_ages.append(INF)
	_from.append(Vector3.ZERO)
	_into_ship.append(false)
	return _copies.size() - 1
