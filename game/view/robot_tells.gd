class_name RobotTells
extends RefCounted

## How a robot's drawn body moves with what it is doing, so each type reads
## apart by behaviour as well as shape (CMB-3, #604, #638). Every tell is drawn
## from state the snapshot already holds (velocity, orientation, the line to
## its target), so nothing is added to the simulation and the view never
## writes to it (MP-2). How strongly each type shows a tell is data in
## `robot_look.json` under `tell` (ARC-4).

## The eye never dims below this share, so a watching warden that lost sight
## of the pilot still shows where it faces.
const MIN_EYE: float = 0.1


## The lean of a robot's drawn body, degrees about its own axes: `x` pitch
## (negative is nose down, as it closes on its target) and `y` roll (negative
## banks to its right, as it slides right around its target).
static func lean_degrees(robot: RobotState, tell: Dictionary) -> Vector2:
	var limit: float = float(tell["max_deg"])
	if limit <= 0.0:
		return Vector2.ZERO
	var local: Vector3 = _local_velocity(robot)
	var closing: float = -local.z
	var pitch: float = -clampf(closing * float(tell["pitch_deg_per_mps"]), -limit, limit)
	var roll: float = -clampf(local.x * float(tell["roll_deg_per_mps"]), -limit, limit)
	return Vector2(pitch, roll)


## The skid of a robot's drawn body, degrees about its own up axis: the nose
## swings toward a sideways move (negative turns it right), so a flat strafer
## crabs around its target instead of banking.
static func yaw_degrees(robot: RobotState, tell: Dictionary) -> float:
	var limit: float = float(tell["max_deg"])
	var rate: float = float(tell.get("yaw_deg_per_mps", 0.0))
	if limit <= 0.0 or rate <= 0.0:
		return 0.0
	return -clampf(_local_velocity(robot).x * rate, -limit, limit)


## The drawn rotation for a robot whose simulated facing is `rotation`, with
## its lean and skid applied about its own axes.
static func drawn_basis(rotation: Quaternion, robot: RobotState, tell: Dictionary) -> Basis:
	var lean: Vector2 = lean_degrees(robot, tell)
	var yaw: float = yaw_degrees(robot, tell)
	return Basis(rotation) * Basis.from_euler(Vector3(deg_to_rad(lean.x), deg_to_rad(yaw), deg_to_rad(lean.y)))


## Share of full eye brightness: 1 while the robot has a clear line to its
## target, less by `watch_dim` once it has lost that line (`unseen_ticks`),
## so a watcher's glare goes out when the pilot breaks line of sight.
static func eye_share(robot: RobotState, tell: Dictionary) -> float:
	if robot.unseen_ticks <= 0:
		return 1.0
	return maxf(MIN_EYE, 1.0 - float(tell.get("watch_dim", 0.0)))


static func _local_velocity(robot: RobotState) -> Vector3:
	return robot.orientation.orthonormalized().inverse() * robot.velocity
