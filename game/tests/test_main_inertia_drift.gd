extends RefCounted

## Preset 4's inertia drift wired into the main scene (#840; CMF-1, CMF-6,
## ARC-3, MP-2): a boost from a stop moves the rig back from the ship's pose
## on preset 4 and not on preset 3, the drift never turns the rig, and a
## flight with it ends on the same state hash as one without.

const FRAME: float = 1.0 / 90.0


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate() if scene != null else null
	if main != null:
		# The main scene's robots shoot the ship from the start (#269); their
		# hits would shake the rig and hide the drift.
		for robot: RobotState in (main.get("session") as LocalSession).sim.robots:
			robot.weapon = null
	return main


static func _values(boost: bool) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	if boost:
		values["buttons"] = {"right_button_lower": true}
	return values


static func _frame(main: Node, boost: bool) -> void:
	main.call("apply_controls", _values(boost))
	main.call("advance_frame", FRAME)


## The rig transform `place_rig` would give with neither shake nor drift.
static func _plain_pose(main: Node) -> Transform3D:
	var session: LocalSession = main.get("session")
	var comfort: ComfortWiring = main.get("comfort")
	var recentre: HeadRecentre = main.get("head_recentre")
	return recentre.rig_transform(ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, comfort.latest_tick_snapped))


## How far the rig sits behind the plain pose, in the ship's frame (+Z is back).
static func _lag(main: Node) -> Vector3:
	var rig: Transform3D = (main.get_node("XRRig") as Node3D).transform
	return (_plain_pose(main).affine_inverse() * rig).origin


func test_a_boost_on_preset_4_moves_the_rig_back() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 4)
	_frame(main, false)
	var peak: float = 0.0
	for frame: int in 20:
		_frame(main, true)
		var rig: Transform3D = (main.get_node("XRRig") as Node3D).transform
		if rig.basis.get_rotation_quaternion().angle_to(_plain_pose(main).basis.get_rotation_quaternion()) > 1e-5:
			main.free()
			return "the drift turned the rig on frame %d" % frame
		peak = maxf(peak, _lag(main).z)
	main.free()
	return "" if peak > 0.001 else "a boost on preset 4 moved the rig back only %f m" % peak


func test_a_boost_on_preset_3_leaves_the_rig_on_the_pose() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 3)
	for frame: int in 20:
		_frame(main, frame > 0)
		if _lag(main).length() > 1e-6:
			main.free()
			return "preset 3 moved the rig %s on frame %d" % [_lag(main), frame]
	main.free()
	return ""


func test_a_preset_change_drops_the_drift_at_once() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 4)
	for frame: int in 10:
		_frame(main, frame > 0)
	if _lag(main).length() < 1e-4:
		main.free()
		return "the boost gave no drift to drop"
	main.call("set_comfort_preset", 3)
	_frame(main, true)
	var left: Vector3 = _lag(main)
	main.free()
	return "" if left.length() < 1e-6 else "preset 3 kept %s of the drift" % left


func test_the_drift_leaves_the_state_hash_alone() -> String:
	var hashes: Array[int] = []
	var lags: Array[float] = []
	for with_drift: bool in [true, false]:
		var main: Node = _main()
		main.call("set_comfort_preset", 4)
		var comfort: ComfortWiring = main.get("comfort")
		if not with_drift:
			comfort.drift.drift = null
		var peak: float = 0.0
		for frame: int in 90:
			_frame(main, frame > 0 and frame < 40)
			peak = maxf(peak, _lag(main).length())
		hashes.append((main.get("session") as LocalSession).sim.state_hash())
		lags.append(peak)
		main.free()
	if lags[0] <= 0.0 or lags[1] > 0.0:
		return "the flights did not differ in drift: %s" % [lags]
	return "" if hashes[0] == hashes[1] else "the drift changed the state hash: %s" % [hashes]
