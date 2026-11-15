extends RefCounted

## The comfort presets in the main scene (CMF-1, CMF-3, CMF-6, CMF-8, ARC-3):
## the filter sits between the mapping and the ship, the preset switch, the
## command-line override and how snaps are shown.

const FRAME: float = 1.0 / 90.0


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func _values(right_stick: Vector2 = Vector2.ZERO, buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	values["buttons"] = buttons
	return values


## One frame as `_process` runs it: sample, then advance.
static func _frame(main: Node, values: Dictionary, delta: float = FRAME) -> void:
	main.call("apply_controls", values)
	main.call("advance_frame", delta)


static func _ship_turn(main: Node) -> float:
	var session: LocalSession = main.get("session")
	return rad_to_deg(session.current_ship().orientation.get_rotation_quaternion().angle_to(Quaternion.IDENTITY))


func test_the_start_preset_is_guided() -> String:
	var main: Node = _main()
	var number: int = main.get("comfort_number")
	var preset: ComfortPreset = main.get("comfort_preset")
	var filter: ComfortInputFilter = main.get("comfort_filter")
	main.free()
	if number != 2 or preset.display_name != "Guided":
		return "started on preset %d %s" % [number, preset.display_name]
	if filter.preset != preset:
		return "the filter does not use the active preset"
	return ""


func test_preset_one_turns_a_held_yaw_into_one_snap() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	# 90 Hz frames: about one frame in three runs no tick, which must not lose
	# the snap, and holding the stick must not repeat it.
	for i: int in 90:
		_frame(main, _values(Vector2(1.0, 0.0)))
	var turned: float = _ship_turn(main)
	main.free()
	if not is_equal_approx(turned, 30.0):
		return "a held yaw turned the ship %.3f degrees, not one 30 degree snap" % turned
	return ""


func test_a_snap_is_flown_even_when_its_frame_runs_no_tick() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	_frame(main, _values(Vector2(1.0, 0.0)), 0.001)
	var ticks_first: int = (main.get("session") as LocalSession).sim.tick
	_frame(main, _values(Vector2(1.0, 0.0)), FRAME * 2.0)
	var turned: float = _ship_turn(main)
	main.free()
	if ticks_first != 0:
		return "the short frame ran %d ticks" % ticks_first
	if not is_equal_approx(turned, 30.0):
		return "the held snap turned %.3f degrees" % turned
	return ""


func test_a_hitch_frame_flies_a_snap_only_once() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	_frame(main, _values(Vector2(0.0, 0.0)))
	_frame(main, _values(Vector2(1.0, 0.0)), 0.06)
	var session: LocalSession = main.get("session")
	var ticks: int = session.sim.tick
	var turned: float = _ship_turn(main)
	main.free()
	if ticks < 3:
		return "the hitch frame ran too few ticks to test: %d" % ticks
	if not is_equal_approx(turned, 30.0):
		return "a hitch frame turned %.3f degrees, not one snap" % turned
	return ""


func test_preset_four_passes_input_unchanged() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 4)
	var values: Dictionary = _values(Vector2(0.7, -0.4))
	values["left_stick"] = Vector2(0.2, 0.9)
	values["right_grip"] = 0.6
	main.call("apply_controls", values)
	var flown: ShipInput = (main.get("input_source") as LatestInputSource).latest_input()
	var mapped: ShipInput = ControllerSampler.map_values(main.get("mapping"), values)
	main.free()
	if flown.thrust_q != mapped.thrust_q or flown.turn_q != mapped.turn_q \
			or flown.afterburner != mapped.afterburner:
		return "preset 4 changed %s/%s to %s/%s" % [mapped.thrust_q, mapped.turn_q, flown.thrust_q, flown.turn_q]
	return ""


func test_the_pitch_limit_sees_the_real_ship() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	# Push and release the pitch stick six times: with the ship's real
	# orientation the 60 degree limit stops it after two 30 degree snaps.
	for push: int in 6:
		for i: int in 6:
			_frame(main, _values(Vector2(0.0, 1.0)))
		for i: int in 6:
			_frame(main, _values())
	var orientation: Basis = (main.get("session") as LocalSession).current_ship().orientation
	main.free()
	var elevation: float = rad_to_deg(absf(ComfortInputFilter.nose_elevation(orientation)))
	if not is_equal_approx(elevation, 60.0):
		return "after six pitch snaps the nose is %.3f degrees from level, not at the 60 degree limit" % elevation
	return ""


func test_the_preset_button_cycles_once_per_press_and_wraps() -> String:
	var main: Node = _main()
	var seen: Array[int] = []
	for press: int in 4:
		for i: int in 5:
			main.call("apply_controls", _values(Vector2.ZERO, {"left_button_upper": true}))
		main.call("apply_controls", _values())
		seen.append(int(main.get("comfort_number")))
	var name_after: String = (main.get("comfort_preset") as ComfortPreset).display_name
	main.free()
	if seen != [3, 4, 1, 2]:
		return "presses from preset 2 gave %s, expected [3, 4, 1, 2]" % str(seen)
	if name_after != "Guided":
		return "back at 2 the preset is %s" % name_after
	return ""


func test_left_handed_uses_the_right_upper_button() -> String:
	var main: Node = _main()
	(main.get("mapping") as ThumbstickMapping).left_handed = true
	main.call("apply_controls", _values(Vector2.ZERO, {"left_button_upper": true}))
	var after_left: int = main.get("comfort_number")
	main.call("apply_controls", _values(Vector2.ZERO, {"right_button_upper": true}))
	var after_right: int = main.get("comfort_number")
	main.free()
	if after_left != 2 or after_right != 3:
		return "left-handed: Y gave %d, B gave %d (expected 2 then 3)" % [after_left, after_right]
	return ""


func test_the_command_line_picks_the_preset() -> String:
	var main_script: GDScript = load("res://main.gd") as GDScript
	var cases: Dictionary[String, int] = {
		"--comfort-preset=1": 1, "--comfort-preset=3": 3, "--comfort-preset=4": 4,
		"--comfort-preset=0": 2, "--comfort-preset=5": 2, "--comfort-preset=x": 2,
		"--comfort-preset=": 2, "--other=1": 2,
	}
	for arg: String in cases:
		var got: int = main_script.call("preset_number_from_args", PackedStringArray([arg]))
		if got != cases[arg]:
			return "%s gave preset %d, expected %d" % [arg, got, cases[arg]]
	if int(main_script.call("preset_number_from_args", PackedStringArray())) != 2:
		return "no argument did not give preset 2"
	return ""


func test_switching_presets_leaves_the_ship_alone() -> String:
	var main: Node = _main()
	for i: int in 30:
		_frame(main, _values(Vector2(0.5, 0.3)))
	var session: LocalSession = main.get("session")
	var hash_before: int = session.sim.state_hash()
	var ship_before: int = session.current_ship().state_hash()
	for number: int in [1, 3, 4, 2]:
		main.call("set_comfort_preset", number)
	main.call("apply_controls", _values(Vector2.ZERO, {"left_button_upper": true}))
	var hash_after: int = session.sim.state_hash()
	var ship_after: int = session.current_ship().state_hash()
	var tick: int = session.sim.tick
	main.free()
	if hash_before != hash_after or ship_before != ship_after:
		return "switching presets changed the simulation"
	if tick != 20:
		return "30 frames ran %d ticks" % tick
	return ""


func test_a_snap_tick_is_shown_without_slerp() -> String:
	var main_script: GDScript = load("res://main.gd") as GDScript
	var previous: ShipState = ShipState.new()
	previous.position = Vector3(0.0, 0.0, 0.0)
	var snapped: ShipState = ShipState.new()
	snapped.position = Vector3(0.0, 0.0, -1.0)
	snapped.orientation = Basis(Vector3.UP, deg_to_rad(30.0))
	var half_snap: float = deg_to_rad(15.0)
	var pose: Transform3D = main_script.call("interpolated_pose", previous, snapped, 0.5, half_snap)
	if not pose.basis.is_equal_approx(snapped.orientation):
		return "a 30 degree tick was blended: %s" % str(pose.basis)
	if not pose.origin.is_equal_approx(Vector3(0.0, 0.0, -0.5)):
		return "the snap tick's position was not interpolated: %s" % str(pose.origin)
	var smooth: ShipState = ShipState.new()
	smooth.orientation = Basis(Vector3.UP, deg_to_rad(1.5))
	var blended: Transform3D = main_script.call("interpolated_pose", previous, smooth, 0.5, half_snap)
	if not blended.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(0.75))):
		return "a smooth 1.5 degree tick was not slerped: %s" % str(blended.basis)
	return ""


func test_the_rig_shows_a_snap_at_once() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	var shown_snap: bool = false
	for i: int in 6:
		_frame(main, _values(Vector2(1.0, 0.0)))
		var session: LocalSession = main.get("session")
		var turn: float = session.previous_ship().orientation.get_rotation_quaternion().angle_to(
			session.current_ship().orientation.get_rotation_quaternion())
		if turn > deg_to_rad(15.0):
			var rig: Node3D = main.get_node("XRRig") as Node3D
			if not rig.transform.basis.is_equal_approx(session.current_ship().orientation):
				main.free()
				return "the rig blended the snap tick: %s" % str(rig.transform.basis)
			shown_snap = true
	var snap_angle: float = main.call("snap_show_angle")
	main.call("set_comfort_preset", 4)
	var smooth_angle: float = main.call("snap_show_angle")
	main.free()
	if not shown_snap:
		return "no snap tick was seen"
	if not is_equal_approx(snap_angle, deg_to_rad(15.0)) or smooth_angle != 0.0:
		return "snap show angles %f / %f" % [snap_angle, smooth_angle]
	return ""
