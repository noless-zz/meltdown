extends RefCounted

## Robots take their chase stand-off, strafe band and radial gain from their
## data file, not from constants in `RobotState` (CMB-3, ARC-4, #246).

const ROBOTS_DIR: String = "res://data/robots"


## The shipped robot `id` with the optional keys in `extra` added to its file.
func _tuned(id: String, extra: Dictionary) -> RobotDef:
	var text: String = FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id])
	var data: Dictionary = JSON.parse_string(text)
	data.merge(extra, true)
	return RobotDef.parse_json(JSON.stringify(data))


## One ship at the origin holding still and one robot at `position`.
func _sim_with(def: RobotDef, position: Vector3) -> Sim:
	var sim: Sim = Sim.new(5, 1)
	sim.spawn_robot(def, position, Basis(Vector3.UP, PI))
	return sim


func _still() -> Array[ShipInput]:
	return [ShipInput.new()]


func test_strafer_settles_inside_a_30_to_40_m_band() -> String:
	var def: RobotDef = _tuned("glider", {"strafe_min_distance": 30.0, "strafe_max_distance": 40.0})
	if def.error != "":
		return "tuned glider rejected: %s" % def.error
	for start: Vector3 in [Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, -70.0)]:
		var sim: Sim = _sim_with(def, start)
		var robot: RobotState = sim.robots[0]
		for i: int in 600:
			sim.step(_still())
		for i: int in 600:
			sim.step(_still())
			var distance: float = robot.position.length()
			if distance < 30.0 or distance > 40.0:
				return "glider from %s at %s m, outside 30..40, at tick %d" % [start, distance, sim.tick]
	return ""


func test_chaser_with_standoff_8_stops_further_away_than_with_4() -> String:
	var distances: Array[float] = []
	for radii: float in [4.0, 8.0]:
		var def: RobotDef = _tuned("needler", {"standoff_radii": radii})
		if def.error != "":
			return "tuned needler rejected: %s" % def.error
		var sim: Sim = _sim_with(def, Vector3(0.0, 0.0, -60.0))
		var robot: RobotState = sim.robots[0]
		for i: int in 1800:
			sim.step(_still())
		var distance: float = robot.position.length()
		var standoff: float = robot.chase_standoff(sim.ships[0])
		if absf(distance - standoff) > 0.25:
			return "needler with %s radii at %s m, stand-off %s m" % [radii, distance, standoff]
		distances.append(distance)
	if distances[1] <= distances[0]:
		return "stand-off 8 stopped at %s m, not further than 4 at %s m" % [distances[1], distances[0]]
	return ""


func test_default_tuning_matches_the_old_constants() -> String:
	# The shipped files carry no tuning keys, so they must get the values the
	# removed constants had, or their movement and pinned hashes would change.
	var def: RobotDef = RobotDef.parse_json(
		FileAccess.get_file_as_string("%s/glider.json" % ROBOTS_DIR))
	if def.standoff_radii != 4.0 or def.strafe_min_distance != 10.0 \
			or def.strafe_max_distance != 20.0 or def.strafe_radial_gain != 0.5:
		return "glider defaults %s, %s, %s, %s" % [def.standoff_radii,
			def.strafe_min_distance, def.strafe_max_distance, def.strafe_radial_gain]
	return ""


func test_radial_gain_changes_how_a_strafer_moves() -> String:
	var positions: Array[Vector3] = []
	for gain: float in [0.5, 3.0]:
		var sim: Sim = _sim_with(_tuned("glider", {"strafe_radial_gain": gain}), Vector3(0.0, 0.0, -12.0))
		for i: int in 120:
			sim.step(_still())
		positions.append(sim.robots[0].position)
	if positions[0].is_equal_approx(positions[1]):
		return "gain 0.5 and 3.0 moved the glider to the same place %s" % positions[0]
	return ""
