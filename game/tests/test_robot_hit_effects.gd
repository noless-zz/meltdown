extends RefCounted

## Robots read as hit, hurt and destroyed (#604, CMB-3, MP-2): a flash on every
## hull drop that fades over `hit_flash_seconds`, a dim sputter below
## `damaged_below` of the hull, a burst where a robot leaves the array, a lean
## drawn from velocity, and the view never writes to the robots it is handed.

const ROBOTS_DIR: String = "res://data/robots"
const EPSILON: float = 1e-4


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


func _robot(id: String, position: Vector3, hull: float = -1.0) -> RobotState:
	var robot: RobotState = RobotState.new(_def(id), position)
	if hull >= 0.0:
		robot.hull = hull
	return robot


## A copy as the session hands it on the next tick.
func _next(robot: RobotState, hull: float) -> RobotState:
	var copy: RobotState = _robot(robot.def.id, robot.position, hull)
	copy.velocity = robot.velocity
	copy.orientation = robot.orientation
	return copy


func test_each_hit_flashes_and_the_flash_fades_on_time() -> String:
	var tracker: RobotHitTracker = RobotHitTracker.new()
	var effects: Dictionary = RobotLook.DEFAULT_EFFECTS
	var flash_s: float = effects["hit_flash_seconds"]
	var a: Array[RobotState] = [_robot("drone", Vector3.ZERO, 20.0)]
	tracker.observe(a, a, 0.0)
	if tracker.since_hit(0, 0.0) != INF:
		return "a robot that was never hit has a hit time"
	var b: Array[RobotState] = [_next(a[0], 15.0)]
	tracker.observe(a, b, 1.0)
	if absf(tracker.since_hit(0, 1.0)) > EPSILON:
		return "the hull drop was not stamped as a hit"
	var start: float = RobotHitTracker.glow(effects, 0.75, tracker.since_hit(0, 1.0), 1.0)["flash"]
	var middle: float = RobotHitTracker.glow(effects, 0.75, tracker.since_hit(0, 1.0 + flash_s * 0.5), 1.0)["flash"]
	var over: float = RobotHitTracker.glow(effects, 0.75, tracker.since_hit(0, 1.0 + flash_s), 1.0)["flash"]
	if absf(start - 1.0) > EPSILON or absf(middle - 0.5) > EPSILON or over != 0.0:
		return "flash %s, %s, %s at 0, half and all of %s s; expected 1, 0.5, 0" % [start, middle, over, flash_s]
	# Another frame of the same tick changes nothing.
	tracker.observe(a, b, 1.05)
	if absf(tracker.since_hit(0, 1.05) - 0.05) > EPSILON:
		return "a second frame of the same tick restarted the flash"
	# The next tick without damage keeps the old hit time; a new hit restamps it.
	var c: Array[RobotState] = [_next(b[0], 15.0)]
	tracker.observe(b, c, 1.1)
	if absf(tracker.since_hit(0, 1.1) - 0.1) > EPSILON:
		return "an undamaged tick lost or restarted the flash"
	var d: Array[RobotState] = [_next(c[0], 10.0)]
	tracker.observe(c, d, 1.2)
	if absf(tracker.since_hit(0, 1.2)) > EPSILON:
		return "the second hit did not flash again"
	return ""


func test_the_flash_follows_a_robot_when_the_array_shifts() -> String:
	var tracker: RobotHitTracker = RobotHitTracker.new()
	var a: Array[RobotState] = [_robot("drone", Vector3.ZERO), _robot("hauler", Vector3(6, 0, 0))]
	tracker.observe(a, a, 0.0)
	var b: Array[RobotState] = [_next(a[0], a[0].hull), _next(a[1], 30.0)]
	tracker.observe(a, b, 1.0)
	# The drone is destroyed: the hauler moves to index 0 and keeps its flash.
	var c: Array[RobotState] = [_next(b[1], 30.0)]
	tracker.observe(b, c, 1.05)
	if absf(tracker.since_hit(0, 1.05) - 0.05) > EPSILON:
		return "the hauler's flash did not follow it to index 0"
	if tracker.partner(0) != 1:
		return "the hauler was paired with index %d, expected 1" % tracker.partner(0)
	if tracker.bursts.size() != 1 or tracker.bursts[0]["id"] != "drone":
		return "expected one drone burst, got %s" % [tracker.bursts]
	if (tracker.bursts[0]["position"] as Vector3).distance_to(Vector3.ZERO) > EPSILON:
		return "the burst is not where the drone was"
	tracker.prune_bursts(1.05 + float(RobotLook.DEFAULT_EFFECTS["burst_seconds"]), RobotLook.DEFAULT_EFFECTS["burst_seconds"])
	if not tracker.bursts.is_empty():
		return "the burst outlived burst_seconds"
	return ""


func test_a_reset_snapshot_makes_no_burst() -> String:
	var tracker: RobotHitTracker = RobotHitTracker.new()
	var a: Array[RobotState] = [_robot("drone", Vector3.ZERO), _robot("hauler", Vector3(6, 0, 0))]
	tracker.observe(a, a, 0.0)
	# A new level: the session's previous and current are the same new copies.
	var fresh: Array[RobotState] = [_robot("glider", Vector3(0, 0, -30))]
	tracker.observe(fresh, fresh, 1.0)
	if not tracker.bursts.is_empty():
		return "a level reset drew %d bursts" % tracker.bursts.size()
	return ""


func test_damage_state_starts_below_the_threshold_and_sputters() -> String:
	var effects: Dictionary = RobotLook.DEFAULT_EFFECTS
	var below: float = effects["damaged_below"]
	var period: float = effects["damaged_flicker_period"]
	var healthy: float = RobotHitTracker.glow(effects, below, INF, 0.0)["brightness"]
	if healthy != 1.0:
		return "a robot at exactly %s of its hull is already dimmed" % below
	var dim: float = RobotHitTracker.glow(effects, below - 0.01, INF, period * 0.5)["brightness"]
	if absf(dim - float(effects["damaged_brightness"])) > EPSILON:
		return "below the threshold the robot glows %s, expected %s" % [dim, effects["damaged_brightness"]]
	var sputter: float = RobotHitTracker.glow(effects, below - 0.01, INF, period * 0.1)["brightness"]
	if sputter >= dim:
		return "no sputter in the first quarter of the flicker period"
	return ""


func test_the_view_flashes_dims_and_bursts() -> String:
	var view: RobotView = RobotView.new()
	view.clock_s = 10.0
	var a: Array[RobotState] = [_robot("drone", Vector3.ZERO), _robot("hauler", Vector3(6, 0, 0))]
	view.show_robots(a, a, 1.0)
	var calm: Color = RobotSkin.shown_color(view.body_material(0))
	var b: Array[RobotState] = [_next(a[0], 5.0), _next(a[1], a[1].hull)]
	var hashes: Array[int] = []
	for robot: RobotState in a + b:
		hashes.append(robot.state_hash())
	view.show_robots(a, b, 0.0)
	var flash: ShaderMaterial = view.body_material(0)
	var result: String = ""
	if RobotSkin.energy(flash) <= 1.0 or RobotSkin.shown_color(flash).get_luminance() <= calm.get_luminance():
		result = "the hit drone did not flash"
	if result == "" and RobotSkin.energy(view.body_material(1)) != 1.0:
		result = "the unhurt hauler flashed"
	view.clock_s = 11.0
	view.show_robots(a, b, 1.0)
	if result == "" and RobotSkin.shown_color(view.body_material(0)).get_luminance() >= calm.get_luminance():
		result = "the drone at a quarter hull is not dimmed"
	var c: Array[RobotState] = [_next(b[1], b[1].hull)]
	view.show_robots(b, c, 0.0)
	if result == "" and view.visible_burst_count() != 1:
		result = "%d bursts drawn for one destroyed drone" % view.visible_burst_count()
	view.clock_s = 11.01 + float(view.effects()["burst_seconds"])
	view.show_robots(b, c, 1.0)
	if result == "" and view.visible_burst_count() != 0:
		result = "the burst is still drawn after burst_seconds"
	var after: Array[int] = []
	for robot: RobotState in a + b:
		after.append(robot.state_hash())
	if result == "" and after != hashes:
		result = "the view changed the robots"
	view.free()
	return result


func test_the_hauler_leans_in_as_it_closes_and_banks_into_a_slide() -> String:
	var view: RobotView = RobotView.new()
	var tell: Dictionary = view.look_for("hauler")["tell"]
	var hauler: RobotState = _robot("hauler", Vector3.ZERO)
	if RobotView.lean_degrees(hauler, tell) != Vector2.ZERO:
		view.free()
		return "a still hauler leans"
	hauler.velocity = Vector3(0, 0, -4.0)
	var closing: Vector2 = RobotView.lean_degrees(hauler, tell)
	hauler.velocity = Vector3(4.0, 0, 0)
	var sliding: Vector2 = RobotView.lean_degrees(hauler, tell)
	hauler.velocity = Vector3(0, 0, -400.0)
	var capped: Vector2 = RobotView.lean_degrees(hauler, tell)
	var still_drone: Vector2 = RobotView.lean_degrees(_robot("drone", Vector3.ZERO), view.look_for("drone")["tell"])
	view.free()
	if closing.x >= 0.0 or absf(closing.y) > EPSILON:
		return "closing gave lean %s, expected nose down only" % closing
	if sliding.y >= 0.0 or absf(sliding.x) > EPSILON:
		return "sliding right gave lean %s, expected a bank right only" % sliding
	if absf(capped.x + float(tell["max_deg"])) > EPSILON:
		return "the lean is not capped at %s degrees: %s" % [tell["max_deg"], capped]
	if still_drone != Vector2.ZERO:
		return "the drone, which holds its station, leans"
	return ""


func test_the_drawn_lean_tilts_the_hauler_node() -> String:
	var view: RobotView = RobotView.new()
	var hauler: RobotState = _robot("hauler", Vector3.ZERO)
	hauler.velocity = Vector3(0, 0, -5.0)
	var robots: Array[RobotState] = [hauler]
	view.show_robots(robots, robots, 1.0)
	var nose: Vector3 = -view.node(0).transform.basis.z.normalized()
	view.free()
	if nose.y >= -0.05:
		return "the closing hauler's nose points %s, not down" % nose
	return ""


func test_the_glow_grows_over_the_wind_up() -> String:
	var weapon: WeaponDef = WeaponDef.parse_json(JSON.stringify({
		"fire_interval_ticks": 5, "projectile_speed": 100.0, "lifetime": 1.0,
		"damage": 4.0, "energy_cost": 0.0, "windup_ticks": 20,
	}))
	var robot: RobotState = _robot("hauler", Vector3.ZERO)
	if RobotHitTracker.windup_fraction(robot) != 0.0:
		return "an unarmed robot winds up"
	robot.weapon = weapon
	robot.windup_elapsed = 5
	if absf(RobotHitTracker.windup_fraction(robot) - 0.25) > EPSILON:
		return "5 of 20 wind-up ticks gave %s, expected 0.25" % RobotHitTracker.windup_fraction(robot)
	var view: RobotView = RobotView.new()
	view.clock_s = 0.0
	var energies: Array[float] = []
	for elapsed: int in [0, 10, 19]:
		var copy: RobotState = _next(robot, robot.hull)
		copy.weapon = weapon
		copy.windup_elapsed = elapsed
		var robots: Array[RobotState] = [copy]
		view.show_robots(robots, robots, 1.0)
		energies.append(RobotSkin.energy(view.body_material(0)))
	view.free()
	if not (energies[0] == 1.0 and energies[1] > energies[0] and energies[2] > energies[1]):
		return "glow over the wind-up was %s, expected 1 then growing" % [energies]
	return ""
