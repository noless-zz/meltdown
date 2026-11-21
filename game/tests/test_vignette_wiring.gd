extends RefCounted

## The comfort vignette wired into the game (CMF-1, CMF-2, CMF-3, #931): its
## strength follows the active preset's row from the motion as shown, a snap
## adds nothing, it eases with the time constant in `vignette_feel.json`,
## preset 4 never shows it, and it writes nothing but the vignette (ARC-3).

const FRAME: float = 1.0 / 90.0
const SNAP_DEG: float = 30.0


static func _main(preset_number: int) -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.call("set_comfort_preset", preset_number)
	return main


static func _values(right_stick: Vector2 = Vector2.ZERO, left_stick: Vector2 = Vector2.ZERO) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	values["left_stick"] = left_stick
	return values


static func _frame(main: Node, values: Dictionary, delta: float = FRAME) -> void:
	main.call("apply_controls", values)
	main.call("advance_frame", delta)


static func _node(main: Node) -> Vignette:
	return main.get_node("XRRig/Camera/Vignette") as Vignette


static func _ship(degrees_yaw: float, speed: float) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.orientation = Basis(Vector3.UP, deg_to_rad(degrees_yaw))
	ship.velocity = Vector3(0.0, 0.0, -speed)
	return ship


func test_the_shipped_feel_file_loads_with_0_15_seconds() -> String:
	var feel: VignetteFeel = VignetteFeel.load_file()
	if feel.error != "":
		return feel.error
	if not is_equal_approx(feel.smooth_seconds, 0.15):
		return "smooth_seconds is %s" % feel.smooth_seconds
	return ""


func test_a_bad_feel_file_is_rejected_by_name() -> String:
	var cases: Dictionary[String, String] = {
		"{\"smooth_seconds\": 0}": "smooth_seconds",
		"{\"smooth_seconds\": true}": "smooth_seconds",
		"{}": "smooth_seconds",
		"{\"smooth_seconds\": 0.15, \"fade\": 1}": "fade",
		"[1]": "object",
	}
	for text: String in cases:
		var feel: VignetteFeel = VignetteFeel.parse_json(text)
		if feel.error == "" or not feel.error.contains(cases[text]):
			return "%s gave '%s'" % [text, feel.error]
	if VignetteWiring.load_feel("res://no_such_vignette_feel.json").smooth_seconds != 0.15:
		return "a missing file did not fall back to the defaults"
	return ""


func test_a_snap_tick_adds_nothing_while_hovering() -> String:
	var wiring: VignetteWiring = VignetteWiring.new()
	var preset: ComfortPreset = ComfortPresetFiles.load_number(1)
	for i: int in 10:
		wiring.advance(preset, _ship(0.0, 0.0), _ship(SNAP_DEG, 0.0), 0.5, true, false, FRAME)
	if wiring.shown != 0.0 or wiring.target != 0.0:
		return "a 30 degree snap gave target %s, shown %s" % [wiring.target, wiring.shown]
	# The same turn flown smoothly in one tick is a fast rotation and does count.
	wiring.advance(preset, _ship(0.0, 0.0), _ship(SNAP_DEG, 0.0), 0.5, false, false, FRAME)
	if wiring.target <= 0.0:
		return "an unsnapped 30 degree tick gave no target"
	return ""


func test_preset_one_snap_yaw_in_the_game_never_darkens_the_view() -> String:
	var main: Node = _main(1)
	var session: LocalSession = main.get("session")
	var start: Basis = session.current_ship().orientation
	var snapped: bool = false
	for i: int in 30:
		_frame(main, _values(Vector2(1.0, 0.0) if i < 6 else Vector2.ZERO))
		snapped = snapped or (main.get("comfort") as ComfortWiring).latest_tick_snapped
		var shown: float = (main.get("vignette") as VignetteWiring).shown
		if shown != 0.0 or _node(main).get_strength() != 0.0 or _node(main).visible:
			main.free()
			return "frame %d: the vignette showed %s on a preset 1 snap" % [i, shown]
	var turned: float = rad_to_deg(start.get_rotation_quaternion().angle_to(
		session.current_ship().orientation.get_rotation_quaternion()))
	main.free()
	if not snapped or not is_equal_approx(snappedf(turned, 0.5), SNAP_DEG):
		return "no 30 degree snap flew (snapped %s, turned %s)" % [snapped, turned]
	return ""


func test_flying_forward_on_preset_one_shows_the_vignette_on_its_node() -> String:
	var main: Node = _main(1)
	for i: int in 90:
		_frame(main, _values(Vector2.ZERO, Vector2(0.0, 1.0)))
	var wiring: VignetteWiring = main.get("vignette")
	var shown: float = wiring.shown
	var on_node: float = _node(main).get_strength()
	var visible: bool = _node(main).visible
	main.free()
	if shown <= 0.0 or not is_equal_approx(on_node, shown) or not visible:
		return "flying forward showed %s, node %s, visible %s" % [shown, on_node, visible]
	return ""


func test_the_strength_eases_with_the_fed_clock() -> String:
	var wiring: VignetteWiring = VignetteWiring.new()
	var preset: ComfortPreset = ComfortPresetFiles.load_number(1)
	var moving: ShipState = _ship(0.0, ComfortVignette.MOTION_FULL_M_PER_S)
	wiring.advance(preset, moving, moving, 0.5, false, false, 1.0 / 72.0)
	var full: float = preset.vignette_strength
	if not is_equal_approx(wiring.target, full):
		return "full speed asked for %s, not %s" % [wiring.target, full]
	var expected: float = full * (1.0 - exp(-(1.0 / 72.0) / 0.15))
	if not is_equal_approx(wiring.shown, expected) or wiring.shown > full * 0.2:
		return "one 72 Hz frame showed %s, expected %s" % [wiring.shown, expected]
	for i: int in 72:
		wiring.advance(preset, moving, moving, 0.5, false, false, 1.0 / 72.0)
	if absf(wiring.shown - full) > 0.01:
		return "after a second it showed %s of %s" % [wiring.shown, full]
	for i: int in 72:
		wiring.advance(preset, moving, moving, 0.5, false, true, 1.0 / 72.0)
	if wiring.shown > 0.01:
		return "a paused second still showed %s" % wiring.shown
	return ""


func test_preset_four_never_shows_and_drops_to_zero_at_once() -> String:
	var wiring: VignetteWiring = VignetteWiring.new()
	var fast: ShipState = _ship(0.0, 30.0)
	var turned: ShipState = _ship(5.0, 30.0)
	for i: int in 60:
		wiring.advance(ComfortPresetFiles.load_number(1), fast, turned, 0.5, false, false, FRAME)
	if wiring.shown <= 0.5:
		return "preset 1 at speed showed only %s" % wiring.shown
	wiring.advance(ComfortPresetFiles.load_number(4), fast, turned, 0.5, false, false, FRAME)
	if wiring.shown != 0.0:
		return "preset 4 kept %s for a frame" % wiring.shown
	for i: int in 60:
		wiring.advance(ComfortPresetFiles.load_number(4), fast, turned, 0.5, false, false, FRAME)
		if wiring.shown != 0.0:
			return "preset 4 showed %s" % wiring.shown
	return ""


func test_a_preset_change_takes_the_new_row_from_the_next_frame() -> String:
	var main: Node = _main(1)
	var comfort: ComfortWiring = main.get("comfort")
	var session: LocalSession = main.get("session")
	var wiring: VignetteWiring = main.get("vignette")
	for i: int in 30:
		_frame(main, _values(Vector2.ZERO, Vector2(0.0, 1.0)))
	main.call("set_comfort_preset", 3)
	_frame(main, _values(Vector2.ZERO, Vector2(0.0, 1.0)))
	var expected: float = ComfortVignette.strength(comfort.preset,
		VignetteWiring.shown_turn_rate(session.previous_ship(), session.current_ship(), comfort.latest_tick_snapped),
		VignetteWiring.shown_speed(session.previous_ship(), session.current_ship(), session.interpolation_fraction))
	var target: float = wiring.target
	main.free()
	if not is_equal_approx(target, expected):
		return "after the change the target was %s, preset 3's row gives %s" % [target, expected]
	return ""


func test_custom_mode_uses_its_own_row() -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var custom: ComfortPreset = ComfortPresetFiles.load_number(1).duplicate() as ComfortPreset
	custom.vignette_strength = 0.3
	comfort.preset = custom
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	session.current_ship().velocity = Vector3(0.0, 0.0, -ComfortVignette.MOTION_FULL_M_PER_S)
	session.previous_ship().velocity = session.current_ship().velocity
	var wiring: VignetteWiring = VignetteWiring.new()
	wiring.update(comfort, session, FRAME, null)
	if not is_equal_approx(wiring.target, 0.3):
		return "the custom row asked for %s, not 0.3" % wiring.target
	return ""


func test_the_vignette_writes_no_ship_state() -> String:
	var flown: Array[int] = []
	for with_vignette: bool in [false, true]:
		var main: Node = _main(1)
		if not with_vignette:
			main.set("vignette", null)
		var session: LocalSession = main.get("session")
		for i: int in 120:
			var values: Dictionary = _values(Vector2(0.6, 0.3), Vector2(0.2, 1.0))
			main.call("apply_controls", values)
			session.advance(FRAME)
			var wiring: VignetteWiring = main.get("vignette")
			if wiring != null:
				wiring.update(main.get("comfort"), session, FRAME, main.get_node("XRRig"))
		flown.append(session.sim.state_hash())
		main.free()
	if flown[0] != flown[1]:
		return "the ship flew to %d without the vignette and %d with it" % [flown[0], flown[1]]
	return ""
