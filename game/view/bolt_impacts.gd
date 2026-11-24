class_name BoltImpacts
extends Node3D

## What a bolt that ended on something shows (#1309, GFX-6, CMB-1). A wall,
## debris or the reactor gets the impact flash, a spark burst thrown back off
## the face in the bolt's weapon's spark colour, and a scorch mark that fades.
## A robot gets the hit flash and a burst of hit sparks every way, in other
## colours, so a hit reads apart from a miss. A robot's bolt on the pilot's
## ship gets only hit sparks, thrown away from the pilot: no flash in the face.
##
## Where the bolt ended is worked out from the walls (`LineOfSight`, read
## only), the robots and the ship poses the view is given, so it never asks the
## simulation and changes nothing in it (MP-2, ARC-1).

enum Kind { WALL, ROBOT, SHIP }

const HIT_FLASHES_NAME: String = "HitFlashes"
const WALL_SPARKS_NAME: String = "WallSparks"
const HIT_SPARKS_NAME: String = "HitSparks"
const SCORCHES_NAME: String = "Scorches"
## A robot's bolt ending this close to a ship (radius 1 m, plus room for its
## move) hit the pilot.
const SHIP_HIT_RADIUS_M: float = 1.5
## Robots are tested a little wider than their radius: the robots given are
## where they were a tick before the bolt ended.
const ROBOT_REACH: float = 1.25
## How far back along the bolt the wall's box is looked for, metres.
const BACK_M: float = 0.02

## Flashes where a bolt hit a robot.
var hit_flashes: BoltFlashes = BoltFlashes.new(HIT_FLASHES_NAME)
var wall_sparks: BoltSparks = BoltSparks.new(WALL_SPARKS_NAME)
var hit_sparks: BoltSparks = BoltSparks.new(HIT_SPARKS_NAME)
var scorches: BoltScorches = BoltScorches.new(SCORCHES_NAME)

var _look: Dictionary = ProjectileLook.DEFAULTS


func _init() -> void:
	name = "Impacts"
	add_child(hit_flashes)
	add_child(wall_sparks)
	add_child(hit_sparks)
	add_child(scorches)
	set_look(ProjectileLook.DEFAULTS)


## Takes the impact keys of a parsed `ProjectileLook`.
func set_look(look: Dictionary) -> void:
	_look = look
	hit_flashes.set_look(look["hit_flash_radius_m"], look["hit_flash_s"], look["hit_color"])
	scorches.set_look(look["scorch_radius_m"], look["scorch_fade_s"], look["scorch_color"])


## Shows what `kind` of end happened at `at`, facing `normal`, for a bolt
## whose weapon sparks in `spark_color`.
func strike(kind: Kind, at: Vector3, normal: Vector3, spark_color: Color) -> void:
	var speed: float = _look["spark_speed_mps"]
	var seconds: float = _look["spark_s"]
	match kind:
		Kind.WALL:
			wall_sparks.burst(at, normal, _look["spark_count"], speed, seconds, spark_color)
			scorches.mark(at, normal)
		Kind.ROBOT:
			hit_flashes.flash(at)
			hit_sparks.burst(at, normal, _look["hit_spark_count"], speed, seconds,
				_look["hit_spark_color"], true)
		Kind.SHIP:
			hit_sparks.burst(at, normal, _look["hit_spark_count"], speed, seconds,
				_look["hit_spark_color"])


## Where and on what `gone` ended, in the tick after it was last seen:
## [Kind, point, outward normal there]. `ship_poses` are the ships' poses,
## `robots` the robots a tick before and `walls` the level (null for open
## space). An end on nothing else (debris, the reactor) counts as a wall,
## half a tick on, facing back along the bolt.
static func classify(gone: Projectile, ship_poses: Array[Transform3D], robots: Array[RobotState],
		walls: BoxUnion) -> Array:
	var from: Vector3 = gone.position
	var step: Vector3 = gone.velocity * ShipState.TICK_DT
	var to: Vector3 = from + step
	var back: Vector3 = -step.normalized() if step.length_squared() > 1e-12 else Vector3.UP
	var best: float = -1.0
	var centre: Vector3 = Vector3.ZERO
	var kind: Kind = Kind.ROBOT
	if gone.is_robot_owned():
		kind = Kind.SHIP
		for pose: Transform3D in ship_poses:
			var t: float = Projectile.segment_entry(from, to, pose.origin, SHIP_HIT_RADIUS_M)
			if t >= 0.0 and (best < 0.0 or t < best):
				best = t
				centre = pose.origin
	else:
		for robot: RobotState in robots:
			if robot == null or robot.def == null:
				continue
			var t: float = Projectile.segment_entry(from, to, robot.position, robot.def.radius * ROBOT_REACH)
			if t >= 0.0 and (best < 0.0 or t < best):
				best = t
				centre = robot.position
	var wall: float = LineOfSight.exit_fraction(walls, from, to)
	# A robot's shot on the ship counts first: the ship is never past a wall.
	if best >= 0.0 and (kind == Kind.SHIP or wall < 0.0 or best <= wall):
		var at: Vector3 = from.lerp(to, best)
		var out: Vector3 = at - centre
		return [kind, at, out.normalized() if out.length_squared() > 1e-12 else back]
	if wall >= 0.0:
		var hit: Vector3 = from.lerp(to, wall)
		return [Kind.WALL, hit, wall_normal(walls, hit, -back)]
	return [Kind.WALL, from + step * 0.5, back]


## The outward normal of the wall face a bolt flying along `direction` met at
## `at`: the face of the box it was in that `at` lies nearest to, among the
## faces it was heading for. Facing back along the flight when no box holds it.
static func wall_normal(walls: BoxUnion, at: Vector3, direction: Vector3) -> Vector3:
	var back: Vector3 = -direction.normalized()
	if walls == null:
		return back
	var inside: Vector3 = at + back * BACK_M
	var box: BoxBounds = null
	for candidate: BoxBounds in walls.boxes:
		if candidate.holds(inside, 0.0):
			box = candidate
			break
	if box == null:
		return back
	var normal: Vector3 = back
	var nearest: float = INF
	for axis: int in 3:
		if absf(direction[axis]) < 1e-9:
			continue
		var heads_up: bool = direction[axis] > 0.0
		var face: float = box.max_corner[axis] if heads_up else box.min_corner[axis]
		var gap: float = absf(face - at[axis])
		if gap < nearest:
			nearest = gap
			normal = Vector3.ZERO
			normal[axis] = -1.0 if heads_up else 1.0
	return normal
