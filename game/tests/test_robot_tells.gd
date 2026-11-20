extends RefCounted

## The behaviour tells of the four robot types #604 left (#638, CMB-3): each
## responds to the snapshot values that drive it, and drawing them never
## changes the robots (MP-2).

const ROBOTS_DIR: String = "res://data/robots"
const EPSILON: float = 0.001


func _robot(id: String) -> RobotState:
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))
	return RobotState.new(def, Vector3.ZERO)


func _tell(view: RobotView, id: String) -> Dictionary:
	return view.look_for(id)["tell"]


func test_the_glider_banks_hard_into_a_sideways_move() -> String:
	var view: RobotView = RobotView.new()
	var tell: Dictionary = _tell(view, "glider")
	var glider: RobotState = _robot("glider")
	var still: Vector2 = RobotTells.lean_degrees(glider, tell)
	glider.velocity = Vector3(-6.0, 0.0, 0.0)
	var left: Vector2 = RobotTells.lean_degrees(glider, tell)
	glider.velocity = Vector3(0.0, 0.0, -6.0)
	var closing: Vector2 = RobotTells.lean_degrees(glider, tell)
	view.free()
	if still != Vector2.ZERO:
		return "a still glider leans %s" % still
	if left.y < 15.0:
		return "sliding left at 6 m/s banks only %.1f degrees" % left.y
	if absf(closing.x) >= absf(left.y):
		return "the glider pitches %.1f closing, as much as it banks %.1f" % [closing.x, left.y]
	return ""


func test_the_needler_dives_nose_down_as_it_closes() -> String:
	var view: RobotView = RobotView.new()
	var tell: Dictionary = _tell(view, "needler")
	var needler: RobotState = _robot("needler")
	needler.velocity = Vector3(0.0, 0.0, -5.0)
	var closing: Vector2 = RobotTells.lean_degrees(needler, tell)
	needler.velocity = Vector3(0.0, 0.0, 5.0)
	var backing: Vector2 = RobotTells.lean_degrees(needler, tell)
	needler.velocity = Vector3(0.0, 0.0, -500.0)
	var capped: Vector2 = RobotTells.lean_degrees(needler, tell)
	view.free()
	if closing.x > -10.0:
		return "closing at 5 m/s pitches only %.1f degrees" % closing.x
	if backing.x <= 0.0:
		return "backing off does not lift the nose: %s" % backing
	if absf(capped.x + float(tell["max_deg"])) > EPSILON:
		return "the dive is not capped at %s degrees: %s" % [tell["max_deg"], capped]
	return ""


func test_the_skimmer_skids_flat_instead_of_banking() -> String:
	var view: RobotView = RobotView.new()
	var tell: Dictionary = _tell(view, "skimmer")
	var skimmer: RobotState = _robot("skimmer")
	skimmer.velocity = Vector3(5.0, 0.0, 0.0)
	var lean: Vector2 = RobotTells.lean_degrees(skimmer, tell)
	var right: float = RobotTells.yaw_degrees(skimmer, tell)
	skimmer.velocity = Vector3(-5.0, 0.0, 0.0)
	var left: float = RobotTells.yaw_degrees(skimmer, tell)
	skimmer.velocity = Vector3.ZERO
	var still: float = RobotTells.yaw_degrees(skimmer, tell)
	var hauler: RobotState = _robot("hauler")
	hauler.velocity = Vector3(5.0, 0.0, 0.0)
	var hauler_yaw: float = RobotTells.yaw_degrees(hauler, _tell(view, "hauler"))
	skimmer.velocity = Vector3(5.0, 0.0, 0.0)
	var robots: Array[RobotState] = [skimmer]
	view.show_robots(robots, robots, 1.0)
	var nose: Vector3 = -view.node(0).transform.basis.z.normalized()
	view.free()
	if lean != Vector2.ZERO:
		return "the skimmer banks or pitches: %s" % lean
	if right > -10.0 or left < 10.0 or still != 0.0:
		return "skid right %.1f, left %.1f, still %.1f: expected a clear turn into each slide" % [right, left, still]
	if hauler_yaw != 0.0:
		return "the hauler, which has no skid, turns %.1f degrees" % hauler_yaw
	if nose.x < 0.1 or absf(nose.y) > 0.05:
		return "the drawn skimmer's nose points %s, not flat and into its slide" % nose
	return ""


## The emission of the eye parts: the first child is the body, and every part
## with a material other than the body's is an eye.
func _eye_emission(view: RobotView) -> Color:
	var parts: Array[Node] = view.node(0).get_children()
	var body: Material = (parts[0] as MeshInstance3D).material_override
	for child: Node in parts:
		var material: StandardMaterial3D = (child as MeshInstance3D).material_override
		if material != body:
			return material.emission
	return Color.BLACK


func test_the_warden_holds_still_and_its_eye_goes_out_without_a_line() -> String:
	var view: RobotView = RobotView.new()
	var tell: Dictionary = _tell(view, "warden")
	var warden: RobotState = _robot("warden")
	warden.velocity = Vector3(1.5, 0.0, -1.5)
	var lean: Vector2 = RobotTells.lean_degrees(warden, tell)
	var yaw: float = RobotTells.yaw_degrees(warden, tell)
	warden.awake = true
	warden.unseen_ticks = 0
	var seeing: float = RobotTells.eye_share(warden, tell)
	var robots: Array[RobotState] = [warden]
	view.show_robots(robots, robots, 1.0)
	var bright: Color = _eye_emission(view)
	warden.unseen_ticks = 3
	var lost: float = RobotTells.eye_share(warden, tell)
	view.show_robots(robots, robots, 1.0)
	var dim: Color = _eye_emission(view)
	var drone: RobotState = _robot("drone")
	drone.unseen_ticks = 3
	var drone_share: float = RobotTells.eye_share(drone, _tell(view, "drone"))
	view.free()
	if lean != Vector2.ZERO or yaw != 0.0:
		return "the warden leans %s or turns %.1f while it drifts" % [lean, yaw]
	if seeing != 1.0 or lost > 0.5:
		return "eye share %.2f with a line, %.2f without: expected 1 and under half" % [seeing, lost]
	if bright == Color.BLACK or dim.v >= bright.v * 0.5:
		return "the drawn eye %s with a line, %s without: it does not go out" % [bright, dim]
	if warden.unseen_ticks != 3 or not warden.awake:
		return "the view changed the warden"
	if drone_share != 1.0:
		return "the drone, which has no watch tell, dims its eye"
	return ""
