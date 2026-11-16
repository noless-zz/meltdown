extends RefCounted

## How the main scene shows snaps (CMF-3, #132): a tick whose turn comes from a
## snap on any axis, including an auto-level roll snap, is shown at once; every
## other tick is interpolated between the two latest ship states.

const FRAME: float = 1.0 / 90.0
const ROLL_DEG: float = 12.0


func _main(preset_number: int) -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.call("set_comfort_preset", preset_number)
	return main


static func _values(right_stick: Vector2 = Vector2.ZERO) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	return values


static func _frame(main: Node, values: Dictionary, delta: float = FRAME) -> void:
	main.call("apply_controls", values)
	main.call("advance_frame", delta)


static func _rig_basis(main: Node) -> Basis:
	return (main.get_node("XRRig") as Node3D).transform.basis


static func _comfort(main: Node) -> ComfortWiring:
	return main.get("comfort") as ComfortWiring


## Banks the ship `degrees` about its nose before any tick, in the simulation
## and in both states the view reads, then places the rig.
static func _bank(main: Node, degrees: float) -> void:
	var session: LocalSession = main.get("session")
	var rolled: Basis = Basis(Vector3.BACK, deg_to_rad(degrees))
	session.sim.ships[0].orientation = rolled
	session.previous_ship().orientation = rolled
	session.current_ship().orientation = rolled
	main.call("place_rig")


static func _shown_roll(main: Node) -> float:
	return absf(rad_to_deg(ComfortAutoLevel.bank(_rig_basis(main))))


static func _ship_roll(main: Node) -> float:
	var session: LocalSession = main.get("session")
	return rad_to_deg(ComfortAutoLevel.bank(session.current_ship().orientation))


func test_a_snapped_tick_is_shown_without_slerp() -> String:
	var previous: ShipState = ShipState.new()
	var current: ShipState = ShipState.new()
	current.position = Vector3(0.0, 0.0, -1.0)
	current.orientation = Basis(Vector3.BACK, deg_to_rad(ROLL_DEG))
	var pose: Transform3D = ComfortWiring.interpolated_pose(previous, current, 0.5, true)
	if not pose.basis.is_equal_approx(current.orientation):
		return "a snapped 12 degree tick was blended: %s" % str(pose.basis)
	if not pose.origin.is_equal_approx(Vector3(0.0, 0.0, -0.5)):
		return "the snap tick's position was not interpolated: %s" % str(pose.origin)
	var blended: Transform3D = ComfortWiring.interpolated_pose(previous, current, 0.5)
	if not blended.basis.is_equal_approx(Basis(Vector3.BACK, deg_to_rad(ROLL_DEG * 0.5))):
		return "an unsnapped tick was not slerped: %s" % str(blended.basis)
	return ""


func test_preset_one_shows_an_auto_level_roll_snap_from_12_to_0() -> String:
	var main: Node = _main(1)
	_bank(main, ROLL_DEG)
	var shown: Array[float] = [_shown_roll(main)]
	for i: int in 9:
		_frame(main, _values())
		shown.append(_shown_roll(main))
	var ship_roll: float = _ship_roll(main)
	main.free()
	if absf(ship_roll) > 0.001:
		return "the auto-level left the ship at %.3f degrees (overshot or did not level)" % ship_roll
	for roll: float in shown:
		if not (is_equal_approx(roll, ROLL_DEG) or absf(roll) < 0.001):
			return "a frame showed %.3f degrees between 12 and 0: %s" % [roll, str(shown)]
	if not is_equal_approx(shown[0], ROLL_DEG) or absf(shown[shown.size() - 1]) > 0.001:
		return "the shown roll did not go from 12 to 0: %s" % str(shown)
	return ""


func test_a_hitch_frame_flies_a_roll_snap_only_once() -> String:
	var main: Node = _main(1)
	_bank(main, ROLL_DEG)
	_frame(main, _values(), 0.06)
	var ticks: int = (main.get("session") as LocalSession).sim.tick
	var ship_roll: float = _ship_roll(main)
	var snapped: bool = _comfort(main).latest_tick_snapped
	main.free()
	if ticks < 3:
		return "the hitch frame ran too few ticks to test: %d" % ticks
	if absf(ship_roll) > 0.001:
		return "a hitch frame left the ship at %.3f degrees, not level" % ship_roll
	if snapped:
		return "the snap was still marked as the latest tick after later ticks flew"
	return ""


func test_preset_one_shows_yaw_and_pitch_snaps_at_once() -> String:
	for stick: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
		var main: Node = _main(1)
		var shown_snap: bool = false
		for i: int in 6:
			_frame(main, _values(stick))
			var session: LocalSession = main.get("session")
			if _comfort(main).latest_tick_snapped:
				if not _rig_basis(main).is_equal_approx(session.current_ship().orientation):
					var basis: Basis = _rig_basis(main)
					main.free()
					return "stick %s: the rig blended the snap tick: %s" % [stick, basis]
				shown_snap = true
		main.free()
		if not shown_snap:
			return "stick %s: no snap tick was seen" % stick
	return ""


func test_a_later_tick_ends_the_snap_showing() -> String:
	var main: Node = _main(1)
	var snapped_frames: int = 0
	for i: int in 9:
		_frame(main, _values(Vector2(1.0, 0.0)))
		if _comfort(main).latest_tick_snapped:
			snapped_frames += 1
	var still_snapped: bool = _comfort(main).latest_tick_snapped
	main.free()
	# At 90 Hz a tick's state is shown for one or two frames.
	if snapped_frames < 1 or snapped_frames > 2:
		return "the snap tick was shown as the latest for %d frames" % snapped_frames
	if still_snapped:
		return "the snap was still marked after later ticks flew"
	return ""


func test_preset_two_auto_level_is_smooth_and_interpolated() -> String:
	var main: Node = _main(2)
	_bank(main, ROLL_DEG)
	var last: float = _shown_roll(main)
	var between_ticks: bool = false
	for i: int in 45:
		_frame(main, _values())
		var session: LocalSession = main.get("session")
		var roll: float = _shown_roll(main)
		if _comfort(main).latest_tick_snapped:
			main.free()
			return "preset 2 marked a tick as a snap"
		if absf(roll - last) > 1.0:
			main.free()
			return "the shown roll jumped from %.3f to %.3f" % [last, roll]
		var fraction: float = session.interpolation_fraction
		var expected: Transform3D = ComfortWiring.interpolated_pose(session.previous_ship(),
			session.current_ship(), fraction)
		if not _rig_basis(main).is_equal_approx(expected.basis):
			main.free()
			return "the rig is not at the interpolated pose"
		if fraction > 0.01 and fraction < 0.99 \
				and not _rig_basis(main).is_equal_approx(session.current_ship().orientation):
			between_ticks = true
		last = roll
	var ship_roll: float = _ship_roll(main)
	main.free()
	if not between_ticks:
		return "no frame showed a roll between two ticks"
	if absf(ship_roll) >= ROLL_DEG - 0.1:
		return "preset 2 did not level: %.3f degrees" % ship_roll
	return ""


func test_the_filter_reports_which_ticks_snap() -> String:
	var anchored: ComfortInputFilter = ComfortInputFilter.new(ComfortPresetFiles.load_number(1))
	var level: ShipInput = ShipInput.new()
	anchored.filter(level, Basis(Vector3.BACK, deg_to_rad(ROLL_DEG)))
	if not anchored.produced_snap or not anchored.produced_roll_snap:
		return "a 12 degree auto-level roll snap was not reported"
	anchored.filter(level, Basis(Vector3.BACK, deg_to_rad(5.0)))
	if anchored.produced_snap or anchored.produced_roll_snap:
		return "a 5 degree bank under the threshold was reported as a snap"
	var yaw: ShipInput = ShipInput.new()
	yaw.turn_q = Vector3i(0, roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE), 0)
	anchored.filter(yaw)
	if not anchored.produced_snap or anchored.produced_roll_snap:
		return "a yaw snap was reported as %s / roll %s" % [anchored.produced_snap,
			anchored.produced_roll_snap]
	var guided: ComfortInputFilter = ComfortInputFilter.new(ComfortPresetFiles.load_number(2))
	guided.filter(level, Basis(Vector3.BACK, deg_to_rad(ROLL_DEG)))
	if guided.produced_snap or guided.produced_roll_snap:
		return "preset 2's smooth auto-level was reported as a snap"
	return ""
