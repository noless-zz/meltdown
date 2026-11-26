extends RefCounted

## Bolts drawn from the ship's muzzles, not the pilot's eye, and their muzzle
## and impact flashes (#602, CMB-1, CMB-3, ARC-4). The simulation still fires
## from the ship's centre; only the drawing moves.

const EYE_CLEARANCE_M: float = 0.3
const SPEED: float = 120.0
const LIFETIME_TICKS: int = 60
const EPSILON: float = 1e-4


func _ship_shot(at: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.FORWARD) -> Projectile:
	return Projectile.new(at, direction * SPEED, 0, LIFETIME_TICKS, 8.0)


func _robot_shot(at: Vector3, direction: Vector3) -> Projectile:
	return Projectile.new(at, direction * 60.0, Projectile.robot_owner(0), LIFETIME_TICKS, 5.0)


func _poses(pose: Transform3D) -> Array[Transform3D]:
	return [pose] as Array[Transform3D]


## Fires one bolt from a ship at the origin moving at `ship_velocity`, then
## flies it on for `ticks` ticks, drawing five frames between each pair of
## ticks with the eye interpolated like the rig. Returns the least distance
## from the eye to the drawn bolt.
func _nearest_to_eye(view: ProjectileView, ticks: int, ship_velocity: Vector3) -> float:
	var step: Vector3 = ship_velocity * ShipState.TICK_DT
	var eye_before: Vector3 = -step
	var eye_now: Vector3 = Vector3.ZERO
	var shots: Array[Projectile] = [_ship_shot(eye_now)]
	var nearest: float = INF
	for tick: int in ticks:
		if tick > 0:
			shots[0].advance()
			eye_before = eye_now
			eye_now += step
		for alpha: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var eye: Vector3 = eye_before.lerp(eye_now, alpha)
			view.show_projectiles(shots, alpha, _poses(Transform3D(Basis.IDENTITY, eye)))
			nearest = minf(nearest, view.bolt(0).position.distance_to(eye))
	return nearest


func test_a_bolt_fired_straight_ahead_never_passes_near_the_eye() -> String:
	for ship_speed: float in [0.0, 20.0, 35.0]:
		var view: ProjectileView = ProjectileView.new()
		var nearest: float = _nearest_to_eye(view, 10, Vector3.FORWARD * ship_speed)
		view.free()
		if nearest <= EYE_CLEARANCE_M:
			return "at %s m/s a bolt was drawn %.3f m from the eye" % [ship_speed, nearest]
	return ""


func test_a_slot_1_bolt_starts_at_the_right_muzzle() -> String:
	var view: ProjectileView = ProjectileView.new()
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(5.0, 1.0, -3.0))
	view.show_projectiles([_ship_shot(pose.origin, -pose.basis.z)] as Array[Projectile], 0.0, _poses(pose))
	var drawn: Vector3 = view.bolt(0).position
	var right: Vector3 = view.muzzles.for_slot(0)
	view.free()
	if not drawn.is_equal_approx(pose * right):
		return "slot 1 bolt drawn at %s, the right muzzle is at %s" % [drawn, pose * right]
	if right.x <= 0.0 or right.y >= 0.0 or right.z >= 0.0:
		return "slot 1's muzzle at %s is not low right ahead" % right
	return ""


## Both slots fire together (#1261): each slot's bolts leave its own gun,
## slot 1 right and slot 2 left, however many shots go before.
func test_each_slot_fires_from_its_own_muzzle() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shots: Array[Projectile] = []
	var sides: Array[float] = []
	for slot: int in [0, 0, 1, 0, 1, 1]:
		var shot: Projectile = _ship_shot()
		shot.slot = slot
		shots.append(shot)
		view.show_projectiles(shots, 0.0, _poses(Transform3D.IDENTITY))
		sides.append(view.bolt(shots.size() - 1).position.x)
	view.free()
	if not (sides[0] > 0.0 and sides[1] > 0.0 and sides[2] < 0.0 and sides[3] > 0.0
			and sides[4] < 0.0 and sides[5] < 0.0):
		return "slots 1, 1, 2, 1, 2, 2 were drawn at x %s, not right, right, left, right, left, left" % [sides]
	return ""


func test_a_bolt_converges_onto_the_simulated_line() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shot: Projectile = _ship_shot()
	var shots: Array[Projectile] = [shot]
	view.show_projectiles(shots, 0.0, _poses(Transform3D.IDENTITY))
	var result: String = ""
	var last_gap: float = INF
	var offset: float = view.muzzles.for_slot(0).length()
	var converge: float = view.muzzles.converge_m
	for tick: int in 6:
		shot.advance()
		view.show_projectiles(shots, 1.0, _poses(Transform3D.IDENTITY))
		var flown: float = shot.position.length()
		var gap: float = view.bolt(0).position.distance_to(shot.position)
		if gap > last_gap + EPSILON:
			result = "the gap grew from %.3f to %.3f m" % [last_gap, gap]
		var expected: float = offset * maxf(0.0, 1.0 - flown / converge)
		if result == "" and absf(gap - expected) > EPSILON:
			result = "after %.1f m the gap is %.3f m, expected %.3f" % [flown, gap, expected]
		if result == "" and flown >= converge and gap > EPSILON:
			result = "after %.1f m the bolt is still %.3f m off its line" % [flown, gap]
		last_gap = gap
	view.free()
	if result == "" and last_gap > EPSILON:
		return "the bolt never reached its simulated line"
	return result


func test_robot_bolts_and_bolts_without_a_pose_fly_on_their_line() -> String:
	var view: ProjectileView = ProjectileView.new()
	var robot: Projectile = _robot_shot(Vector3(0.0, 0.0, -20.0), Vector3.BACK)
	var unposed: Projectile = _ship_shot(Vector3(3.0, 0.0, 0.0))
	view.show_projectiles([robot, unposed] as Array[Projectile], 0.0)
	var robot_ok: bool = view.bolt(0).position.is_equal_approx(robot.position)
	var unposed_ok: bool = view.bolt(1).position.is_equal_approx(unposed.position)
	view.free()
	if not robot_ok or not unposed_ok:
		return "a robot bolt or a bolt with no ship pose was moved off its line"
	return ""


func test_a_muzzle_flash_shows_at_the_muzzle_and_rides_with_the_ship() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shots: Array[Projectile] = [_ship_shot()]
	view.show_projectiles(shots, 0.0, _poses(Transform3D.IDENTITY))
	var result: String = ""
	var shown: Array[MeshInstance3D] = view.muzzle_flashes.shown()
	if shown.size() != 1:
		result = "%d muzzle flashes after one shot" % shown.size()
	elif not shown[0].position.is_equal_approx(view.muzzles.for_slot(0)):
		result = "the muzzle flash is at %s, not the muzzle" % shown[0].position
	elif shown[0].position.length() <= EYE_CLEARANCE_M:
		result = "the muzzle flash is at the eye"
	if result == "":
		var moved: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.5))
		view.show_projectiles(shots, 0.5, _poses(moved))
		if not shown[0].position.is_equal_approx(moved * view.muzzles.for_slot(0)):
			result = "the muzzle flash stayed behind when the ship moved"
	if result == "":
		view.muzzle_flashes.age(view.muzzle_flashes.lifetime_s)
		if not view.muzzle_flashes.shown().is_empty():
			result = "the muzzle flash outlived its lifetime"
	view.free()
	return result


func test_a_bolt_that_ends_early_flashes_where_it_ended() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shot: Projectile = _ship_shot(Vector3(0.0, 0.0, -10.0))
	view.show_projectiles([shot] as Array[Projectile], 0.0, _poses(Transform3D.IDENTITY))
	view.show_projectiles([] as Array[Projectile], 0.0, _poses(Transform3D.IDENTITY))
	var shown: Array[MeshInstance3D] = view.impact_flashes.shown()
	var result: String = ""
	var expected: Vector3 = shot.position + shot.velocity * ShipState.TICK_DT * 0.5
	if shown.size() != 1:
		result = "%d impact flashes for one bolt that hit" % shown.size()
	elif not shown[0].position.is_equal_approx(expected):
		result = "the impact flash is at %s, expected %s" % [shown[0].position, expected]
	elif not view.impact_flashes.material().emission.is_equal_approx(
			ProjectileLook.DEFAULTS["impact_color"]):
		result = "the impact flash does not use its own look entry"
	if result == "":
		view.impact_flashes.age(view.impact_flashes.lifetime_s * 0.5)
		if view.impact_flashes.shown().size() != 1 or shown[0].scale.x >= view.impact_flashes.radius_m:
			result = "the impact flash did not shrink over its life"
		view.impact_flashes.age(view.impact_flashes.lifetime_s)
		if result == "" and not view.impact_flashes.shown().is_empty():
			result = "the impact flash outlived its lifetime"
	view.free()
	return result


func test_a_bolt_whose_range_ran_out_does_not_flash() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shot: Projectile = Projectile.new(Vector3(0.0, 0.0, -30.0), Vector3.FORWARD * SPEED, 0, 1, 8.0)
	view.show_projectiles([shot] as Array[Projectile], 0.0)
	view.show_projectiles([] as Array[Projectile], 0.0)
	var flashes: int = view.impact_flashes.shown().size()
	view.free()
	if flashes != 0:
		return "a bolt at the end of its range flashed in open space"
	return ""


func test_robot_bolts_flash_at_walls_but_not_on_the_pilot() -> String:
	var view: ProjectileView = ProjectileView.new()
	var poses: Array[Transform3D] = _poses(Transform3D.IDENTITY)
	var at_wall: Projectile = _robot_shot(Vector3(10.0, 0.0, 0.0), Vector3.RIGHT)
	var at_ship: Projectile = _robot_shot(Vector3(0.0, 0.0, -1.5), Vector3.BACK)
	view.show_projectiles([at_wall, at_ship] as Array[Projectile], 0.0, poses)
	view.show_projectiles([] as Array[Projectile], 0.0, poses)
	var shown: Array[MeshInstance3D] = view.impact_flashes.shown()
	var result: String = ""
	if shown.size() != 1:
		result = "%d impact flashes, expected only the one at the wall" % shown.size()
	elif shown[0].position.x < 10.0:
		result = "the flash is not at the robot bolt that hit the wall"
	view.free()
	return result


func test_flash_nodes_are_pooled() -> String:
	var view: ProjectileView = ProjectileView.new()
	for burst: int in 5:
		view.show_projectiles([_ship_shot(Vector3(0.0, 0.0, -5.0))] as Array[Projectile], 0.0)
		view.show_projectiles([] as Array[Projectile], 0.0)
		view.impact_flashes.age(1.0)
	var pool: int = view.impact_flashes.pool_size()
	view.free()
	if pool != 1:
		return "five flashes one after another made %d nodes" % pool
	return ""


func test_a_zero_lifetime_turns_a_flash_off() -> String:
	var flashes: BoltFlashes = BoltFlashes.new()
	flashes.set_look(0.2, 0.0, Color.WHITE)
	flashes.flash(Vector3.ONE)
	var made: int = flashes.pool_size()
	flashes.free()
	if made != 0:
		return "a flash with no lifetime was made"
	return ""


## The real main scene with the trigger held: no bolt is ever drawn within the
## clearance of the camera, which sits at the ship's centre.
func test_main_scene_bolts_keep_clear_of_the_camera() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var fire: ShipInput = ShipInput.new(Vector3i(0, 0, -1), Vector3i.ZERO, false, false, true)
	(main.get("input_source") as LatestInputSource).set_input(fire)
	var view: ProjectileView = main.get_node(ProjectileView.NODE_NAME) as ProjectileView
	var camera: Node3D = main.get_node("XRRig/Camera") as Node3D
	var nearest: float = INF
	var drawn: int = 0
	for frame: int in 60:
		main.call("advance_frame", 1.0 / 90.0)
		var eye: Vector3 = NodePoints.point_in(view, camera)
		for index: int in view.bolt_count():
			if view.bolt(index).visible:
				drawn += 1
				nearest = minf(nearest, view.bolt(index).position.distance_to(eye))
	var flashes: int = view.muzzle_flashes.pool_size()
	main.free()
	if drawn == 0:
		return "no bolt was drawn while firing"
	if nearest <= EYE_CLEARANCE_M:
		return "a bolt was drawn %.3f m from the camera" % nearest
	if flashes == 0:
		return "firing made no muzzle flash"
	return ""
