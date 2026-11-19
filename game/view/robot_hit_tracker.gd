class_name RobotHitTracker
extends RefCounted

## Works out, from the robot snapshots alone, which drawn robot was just hit and
## which was destroyed, so `RobotView` can flash and burst them (CMB-3).
##
## `ROBOT_HIT` and `ROBOT_DESTROYED` name the ship that fired, not the robot,
## and the view is handed only copies of the robot array (MP-2). A robot whose
## hull dropped since its partner on the previous tick was hit; a robot of the
## previous tick with no partner now was removed, which only happens when it
## is destroyed. Times are seconds on any clock the caller keeps.

## A robot whose position jumped further than this many ticks of its top speed
## (plus `JUMP_MARGIN_M`) is not the same robot as the one before it.
const JUMP_TICKS: float = 2.0
const JUMP_MARGIN_M: float = 0.1

## Bursts in flight: {"position": Vector3, "id": String, "radius": float, "start": float}.
var bursts: Array[Dictionary] = []

## The current robots last observed, by identity, to tell a new tick from another frame.
var _seen: Array[RobotState] = []
## For each robot of `_seen`, the time of its latest hit, or -INF.
var _hit_at: Array[float] = []
## For each robot of `_seen`, the index of its partner in that tick's previous array, or -1.
var _partners: PackedInt32Array = PackedInt32Array()


## Takes this frame's snapshots. Only a new tick (other robot copies than last
## time) changes anything; then hits are stamped with `now_s`.
func observe(previous: Array[RobotState], current: Array[RobotState], now_s: float) -> void:
	if _is_seen(current):
		return
	var partners: PackedInt32Array = pair(previous, current)
	var carried: Array[float] = []
	var used: Dictionary[int, bool] = {}
	for index: int in current.size():
		var at: int = partners[index]
		var hit_at: float = -INF
		if at >= 0:
			used[at] = true
			var before: RobotState = previous[at]
			# The partner's last hit, if the previous tick is the one seen last.
			if at < _hit_at.size() and _seen.size() > at and _seen[at] == before:
				hit_at = _hit_at[at]
			if current[index].hull < before.hull:
				hit_at = now_s
		carried.append(hit_at)
	for index: int in previous.size():
		var gone: RobotState = previous[index]
		if used.has(index) or gone == null or gone.def == null or not gone.is_alive():
			continue
		bursts.append({"position": gone.position, "id": gone.def.id,
			"radius": gone.def.radius, "start": now_s})
	_seen = current.duplicate()
	_hit_at = carried
	_partners = partners


## Seconds since robot `index` of the last observed tick was hit, or INF.
func since_hit(index: int, now_s: float) -> float:
	if index < 0 or index >= _hit_at.size() or _hit_at[index] == -INF:
		return INF
	return now_s - _hit_at[index]


## The partner index in the previous array of robot `index` of the last
## observed tick, or -1 when it has none (new, or the arrays were not paired).
func partner(index: int) -> int:
	return _partners[index] if index < _partners.size() else -1


## Drops bursts older than `seconds`.
func prune_bursts(now_s: float, seconds: float) -> void:
	var live: Array[Dictionary] = []
	for burst: Dictionary in bursts:
		if now_s - float(burst["start"]) < seconds:
			live.append(burst)
	bursts = live


## For each robot of `current`, the index of the same robot in `previous`, or
## -1. Robots keep their order and are only removed or appended, so the scan
## moves forward: an unmatched robot of `previous` was removed.
static func pair(previous: Array[RobotState], current: Array[RobotState]) -> PackedInt32Array:
	var partners: PackedInt32Array = PackedInt32Array()
	partners.resize(current.size())
	partners.fill(-1)
	var from: int = 0
	for index: int in current.size():
		var robot: RobotState = current[index]
		if robot == null or robot.def == null:
			continue
		for at: int in range(from, previous.size()):
			if is_same_robot(previous[at], robot):
				partners[index] = at
				from = at + 1
				break
	return partners


## Whether `before` can be the previous tick's copy of `robot`: same type, and
## no further away than it could have moved.
static func is_same_robot(before: RobotState, robot: RobotState) -> bool:
	if before == null or before.def == null or robot == null or robot.def == null \
			or before.def.id != robot.def.id:
		return false
	var reach: float = robot.def.max_speed * ShipState.TICK_DT * JUMP_TICKS + JUMP_MARGIN_M
	return before.position.distance_to(robot.position) <= reach


## How a robot's body glows: `flash` 0..1, how far towards the hit colour, and
## `brightness` 0..1 of its own colour. Full brightness above
## `damaged_below` of its hull; below it, dimmed and sputtering darker for a
## quarter of every `damaged_flicker_period`. `windup` 0..1 is how far the
## robot is through the wind-up before its next burst (`windup_fraction`).
static func glow(effects: Dictionary, hull_fraction: float, since_hit_s: float, now_s: float,
		windup: float = 0.0) -> Dictionary:
	var flash_s: float = float(effects["hit_flash_seconds"])
	var flash: float = 0.0
	if since_hit_s >= 0.0 and since_hit_s < flash_s:
		flash = 1.0 - since_hit_s / flash_s
	var brightness: float = 1.0
	if hull_fraction < float(effects["damaged_below"]):
		brightness = float(effects["damaged_brightness"])
		var period: float = float(effects["damaged_flicker_period"])
		if fposmod(now_s, period) < period * 0.25:
			brightness *= 1.0 - float(effects["damaged_flicker_depth"])
	return {"flash": flash, "brightness": brightness, "windup": clampf(windup, 0.0, 1.0)}


## How far `robot` is through winding up for a burst, 0..1, from the state the
## simulation exposes for it (#612); 0 for a weapon with no wind-up.
static func windup_fraction(robot: RobotState) -> float:
	if robot.weapon == null or robot.weapon.windup_ticks <= 0:
		return 0.0
	return clampf(float(robot.windup_elapsed) / float(robot.weapon.windup_ticks), 0.0, 1.0)


func _is_seen(current: Array[RobotState]) -> bool:
	if current.size() != _seen.size():
		return false
	for index: int in current.size():
		if current[index] != _seen[index]:
			return false
	return true
