extends RefCounted

## Where bolts end (#1309, GFX-6, GFX-4, CMB-1): a wall strike sparks off the
## face and leaves a scorch that fades over the look's time; a robot hit and a
## hit on the ship burst differently; no light is added past `max_lights`.

const EPSILON: float = 1e-3


func _walls() -> BoxUnion:
	return BoxUnion.new([BoxBounds.new(Vector3(-10.0, -10.0, -10.0), Vector3(10.0, 10.0, 10.0))] as Array[BoxBounds])


func _robot(at: Vector3) -> RobotState:
	var def: RobotDef = RobotDef.new()
	def.radius = 1.0
	return RobotState.new(def, at)


func _view(robots: Array[RobotState]) -> ProjectileView:
	var view: ProjectileView = ProjectileView.new()
	view.set_scene([ShipState.new()] as Array[ShipState], robots, _walls())
	return view


## Shows `shot` once, then shows nothing: it ended in the tick after.
func _end(view: ProjectileView, shot: Projectile) -> void:
	var poses: Array[Transform3D] = [Transform3D.IDENTITY]
	view.show_projectiles([shot] as Array[Projectile], 1.0, poses)
	view.show_projectiles([] as Array[Projectile], 1.0, poses)


func test_a_wall_strike_is_placed_on_the_face_with_its_normal() -> String:
	var shot: Projectile = Projectile.new(Vector3(0.0, 2.0, 8.0), Vector3(0.0, 0.0, 300.0), 0, 20, 1.0)
	var end: Array = BoltImpacts.classify(shot, [], [], _walls())
	if end[0] != BoltImpacts.Kind.WALL or not (end[1] as Vector3).is_equal_approx(Vector3(0.0, 2.0, 10.0)):
		return "expected a wall at z 10, got %s" % [end]
	if not (end[2] as Vector3).is_equal_approx(Vector3(0.0, 0.0, -1.0)):
		return "the wall faces %s" % end[2]
	return ""


func test_a_robot_hit_is_told_from_a_wall_behind_it() -> String:
	var shot: Projectile = Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -600.0), 0, 20, 1.0)
	var end: Array = BoltImpacts.classify(shot, [], [_robot(Vector3(0.0, 0.0, -5.0))], _walls())
	if end[0] != BoltImpacts.Kind.ROBOT or absf((end[1] as Vector3).z + 3.75) > EPSILON:
		return "expected a robot hit at z -3.75, got %s" % [end]
	if not (end[2] as Vector3).is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		return "the hit faces %s, not back at the shooter" % end[2]
	var hidden: Array = BoltImpacts.classify(shot, [], [_robot(Vector3(0.0, 0.0, -12.0))], _walls())
	if hidden[0] != BoltImpacts.Kind.WALL:
		return "a robot behind the wall was hit: %s" % [hidden]
	return ""


func test_a_robot_shot_on_the_ship_bursts_away_from_the_pilot() -> String:
	var shot: Projectile = Projectile.new(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 120.0),
		Projectile.robot_owner(0), 20, 1.0)
	var end: Array = BoltImpacts.classify(shot, [Transform3D.IDENTITY], [], _walls())
	if end[0] != BoltImpacts.Kind.SHIP or (end[2] as Vector3).dot(Vector3(0.0, 0.0, -1.0)) < 0.99:
		return "expected a ship hit facing the shooter, got %s" % [end]
	return ""


func test_wall_robot_and_ship_ends_show_different_bursts() -> String:
	var view: ProjectileView = _view([_robot(Vector3(0.0, 0.0, -5.0))] as Array[RobotState])
	var result: String = view.look_error
	_end(view, Projectile.new(Vector3(0.0, 2.0, 8.0), Vector3(0.0, 0.0, 300.0), 0, 20, 1.0))
	var impacts: BoltImpacts = view.impacts
	if result == "" and (view.impact_flashes.shown().size() != 1 or impacts.wall_sparks.shown().size() != 1
			or impacts.scorches.shown().size() != 1 or impacts.hit_sparks.shown().size() != 0):
		result = "a wall strike did not flash, spark and scorch alone"
	_end(view, Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -600.0), 0, 20, 1.0))
	if result == "" and (impacts.hit_flashes.shown().size() != 1 or impacts.hit_sparks.shown().size() != 1
			or impacts.scorches.shown().size() != 1 or view.impact_flashes.shown().size() != 1):
		result = "a robot hit did not show the hit flash and hit sparks alone"
	_end(view, Projectile.new(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 120.0), Projectile.robot_owner(0), 20, 1.0))
	if result == "" and (impacts.hit_sparks.shown().size() != 2 or impacts.hit_flashes.shown().size() != 1
			or view.impact_flashes.shown().size() != 1):
		result = "a hit on the ship flashed in the pilot's face or gave no sparks"
	if result == "" and view.meshes.look("")["spark_color"] == ProjectileLook.parse(
			FileAccess.get_file_as_string(ProjectileLook.DEFAULT_FILE))["hit_spark_color"]:
		result = "wall and hit sparks share a colour"
	view.free()
	return result


func test_the_scorch_fades_over_the_looks_time() -> String:
	var view: ProjectileView = _view([] as Array[RobotState])
	_end(view, Projectile.new(Vector3(0.0, 2.0, 8.0), Vector3(0.0, 0.0, 300.0), 0, 20, 1.0))
	var scorches: BoltScorches = view.impacts.scorches
	var result: String = ""
	var fade: float = scorches.fade_s
	scorches.age(fade * 0.5)
	if scorches.shown().size() != 1 or absf(scorches.shown()[0].modulate.a - 0.5) > EPSILON:
		result = "half way through, the scorch is not half faded"
	scorches.age(fade * 0.51)
	if result == "" and scorches.shown().size() != 0:
		result = "the scorch outlived scorch_fade_s"
	for mark: int in BoltScorches.MAX_SCORCHES + 5:
		scorches.mark(Vector3(mark, 0.0, 0.0), Vector3.UP)
	if result == "" and scorches.shown().size() != BoltScorches.MAX_SCORCHES:
		result = "%d scorches kept, past the cap" % scorches.shown().size()
	view.free()
	return result


func test_sparks_fly_off_the_face_and_die_out() -> String:
	var normal: Vector3 = Vector3(0.0, 0.0, -1.0)
	for index: int in 12:
		if BoltSparks.direction(index, 12, normal, false).dot(normal) < -EPSILON:
			return "spark %d flies into the wall" % index
	var sparks: BoltSparks = BoltSparks.new()
	sparks.burst(Vector3.ZERO, normal, 12, 6.0, 0.25, Color.WHITE)
	var result: String = ""
	if sparks.shown().size() != 1 or sparks.shown()[0].multimesh.instance_count != 12:
		result = "a burst is not one multimesh of its sparks"
	sparks.age(0.26)
	if result == "" and sparks.shown().size() != 0:
		result = "the sparks outlived spark_s"
	sparks.free()
	return result


func test_todays_look_has_no_new_effects() -> String:
	var view: ProjectileView = _view([_robot(Vector3(0.0, 0.0, -5.0))] as Array[RobotState])
	view.load_look("res://view/no_such_look.json")
	_end(view, Projectile.new(Vector3(0.0, 2.0, 8.0), Vector3(0.0, 0.0, 300.0), 0, 20, 1.0))
	_end(view, Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -600.0), 0, 20, 1.0))
	var impacts: BoltImpacts = view.impacts
	var result: String = ""
	if impacts.wall_sparks.shown().size() + impacts.hit_sparks.shown().size() + impacts.scorches.shown().size() != 0:
		result = "the default look sparked or scorched"
	if result == "" and (view.impact_flashes.shown().size() != 1 or impacts.hit_flashes.shown().size() != 1
			or impacts.hit_flashes.radius_m != view.impact_flashes.radius_m):
		result = "the default look does not flash both ends alike, as before"
	view.free()
	return result


func test_impacts_add_no_lights() -> String:
	var view: ProjectileView = _view([_robot(Vector3(0.0, 0.0, -5.0))] as Array[RobotState])
	for shot: int in 10:
		_end(view, Projectile.new(Vector3(0.0, 2.0, 8.0), Vector3(0.0, 0.0, 300.0), 0, 20, 1.0))
		_end(view, Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -600.0), 0, 20, 1.0))
	var lights: int = view.find_children("*", "Light3D", true, false).size()
	var result: String = ""
	if lights > view.max_lights or view.impacts.find_children("*", "Light3D", true, false).size() != 0:
		result = "%d lights under the bolts, budget %d" % [lights, view.max_lights]
	view.free()
	return result
