extends RefCounted

## Look-aim in the headset (CMB-6, CMB-8, CMF-1, CMF-6, ARC-3, MP-2, decision
## record 0010, #923): each preset's look-aim value, the head's forward as the
## input's aim on presets 1 and 2, the nose on 3 and 4 and in custom mode, the
## value following a preset change from the next input, and no simulation
## state written.


func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	return rig


static func _turn_head(rig: Node3D, degrees_right: float) -> void:
	var camera: Node3D = rig.get_node("Camera") as Node3D
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees_right)), Vector3(0.0, 1.2, 0.0))


func _comfort(rig: Node3D, number: int) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.attach_cockpit_frame(rig, HeadRecentre.new())
	comfort.look_aim.head_trusted = func() -> bool: return true
	comfort.set_preset(number)
	return comfort


## The aim the session would fly after one frame of `input`.
static func _flown_aim(comfort: ComfortWiring, input: ShipInput = ShipInput.new()) -> Vector3i:
	comfort.hand_input(input, Basis.IDENTITY, false)
	return (comfort.get("_input_source") as LatestInputSource).latest_input().aim_q


## Degrees right of the nose, + right, in the ship's horizontal plane.
static func _degrees_right(aim_q: Vector3i) -> float:
	var aim: Vector3 = Vector3(aim_q).normalized()
	return rad_to_deg(atan2(aim.x, -aim.z))


func test_each_preset_has_its_look_aim_value() -> String:
	var expected: Array[bool] = [true, true, false, false]
	for number: int in range(1, 5):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		if preset == null:
			return "preset %d did not load" % number
		if preset.look_aim != expected[number - 1]:
			return "preset %d has look_aim %s, expected %s" % [number, preset.look_aim, expected[number - 1]]
	return ""


func test_custom_mode_follows_presets_three_and_four() -> String:
	for base: int in range(1, 5):
		var custom: ComfortCustom = ComfortCustom.parse("{\"base\": %d}" % base)
		if custom.error != "" or custom.preset == null:
			return "custom on base %d rejected: %s" % [base, custom.error]
		if custom.preset.look_aim:
			return "custom mode on base %d has look-aim on" % base
	var asked: ComfortCustom = ComfortCustom.parse("{\"base\": 3, \"look_aim\": true}")
	if asked.error == "" or (asked.preset != null and asked.preset.look_aim):
		return "the custom file switched look-aim on"
	if ComfortCustom.settable_fields().has("look_aim"):
		return "look_aim is listed as settable by the custom file"
	return ""


func test_head_yawed_twenty_degrees_aims_twenty_degrees_right_on_preset_one() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 1)
	_turn_head(rig, 20.0)
	var aim_q: Vector3i = _flown_aim(comfort)
	rig.free()
	var right: float = _degrees_right(aim_q)
	if absf(right - 20.0) > 0.2:
		return "preset 1 aimed %s degrees right (%s), expected 20" % [right, aim_q]
	if absf(Vector3(aim_q).normalized().y) > 0.001:
		return "a level head turn aimed up or down: %s" % aim_q
	return ""


func test_preset_two_aims_with_the_head_by_default() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 2)
	_turn_head(rig, -15.0)
	var aim_q: Vector3i = _flown_aim(comfort)
	rig.free()
	if absf(_degrees_right(aim_q) + 15.0) > 0.2:
		return "preset 2 aimed %s degrees right, expected -15" % _degrees_right(aim_q)
	return ""


func test_presets_three_and_four_aim_at_the_nose() -> String:
	for number: int in [3, 4]:
		var rig: Node3D = _rig()
		var comfort: ComfortWiring = _comfort(rig, number)
		_turn_head(rig, 20.0)
		var aim_q: Vector3i = _flown_aim(comfort)
		rig.free()
		if aim_q != ShipInput.NOSE_AIM_Q:
			return "preset %d aimed at %s, expected the nose" % [number, aim_q]
	return ""


func test_the_recentre_offset_turns_the_head_into_ship_space() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 1)
	# Forward was taken with the head 30 degrees right, so that heading is the nose.
	_turn_head(rig, 30.0)
	comfort.look_aim.recentre.apply((rig.get_node("Camera") as Node3D).transform)
	var on_forward: Vector3i = _flown_aim(comfort)
	_turn_head(rig, 50.0)
	var past_forward: float = _degrees_right(_flown_aim(comfort))
	rig.free()
	if on_forward != ShipInput.NOSE_AIM_Q:
		return "looking at the recentred forward aimed at %s, not the nose" % on_forward
	if absf(past_forward - 20.0) > 0.2:
		return "20 degrees past forward aimed %s degrees right" % past_forward
	return ""


func test_a_preset_change_mid_run_takes_effect_from_the_next_input() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 1)
	_turn_head(rig, 20.0)
	var on_one: Vector3i = _flown_aim(comfort)
	comfort.set_preset(3)
	var on_three: Vector3i = _flown_aim(comfort)
	comfort.set_preset(2)
	var on_two: Vector3i = _flown_aim(comfort)
	comfort.read_preset_button({comfort.preset_button(): true})  # 2 > 3 with the button.
	var after_button: Vector3i = _flown_aim(comfort)
	rig.free()
	if on_one == ShipInput.NOSE_AIM_Q:
		return "preset 1 did not aim with the head"
	if on_three != ShipInput.NOSE_AIM_Q:
		return "after switching to preset 3 the aim stayed at %s" % on_three
	if on_two != on_one:
		return "after switching back to preset 2 the aim was %s, expected %s" % [on_two, on_one]
	if comfort.number != 3 or after_button != ShipInput.NOSE_AIM_Q:
		return "the preset button to %d left the aim at %s" % [comfort.number, after_button]
	return ""


func test_an_untracked_head_aims_at_the_nose() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 1)
	_turn_head(rig, 20.0)
	comfort.look_aim.head_trusted = func() -> bool: return false
	var aim_q: Vector3i = _flown_aim(comfort)
	rig.free()
	if aim_q != ShipInput.NOSE_AIM_Q:
		return "a lost head aimed at %s" % aim_q
	return ""


func test_off_or_on_the_nose_hands_back_the_same_input() -> String:
	var head: LookAimHead = LookAimHead.new()
	var input: ShipInput = ShipInput.new(Vector3i(0, 0, -500), Vector3i.ZERO, false, false, true)
	if head.aimed(input) != input:
		return "look-aim off copied an input that was already on the nose"
	head.enabled = true
	head.head_trusted = func() -> bool: return true
	if head.aimed(input) != input:
		return "a head on the nose (no camera) copied the input"
	input.aim_q = ShipInput.aim_q_from(Vector3(0.3, 0.0, -1.0))
	head.enabled = false
	var back: ShipInput = head.aimed(input)
	if back.aim_q != ShipInput.NOSE_AIM_Q or back.thrust_q != input.thrust_q or not back.fire_primary:
		return "look-aim off did not put an off-nose aim back on the nose, keeping the rest"
	return ""


func test_main_reads_the_head_from_the_rig_camera() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.call("attach_cockpit_frame")
	var comfort: ComfortWiring = main.get("comfort")
	var has_camera: bool = comfort.look_aim.camera == main.get_node("XRRig/Camera")
	var same_recentre: bool = comfort.look_aim.recentre == main.get("head_recentre")
	main.free()
	if not has_camera:
		return "look-aim does not read the head from the rig's camera"
	if not same_recentre:
		return "look-aim does not use main's head recentre"
	return ""


func test_writes_no_simulation_state() -> String:
	var source: String = FileAccess.get_file_as_string("res://xr/look_aim_head.gd")
	for forbidden: String in ["set_input", ".step(", "LocalSession", "current_ship", "state_hash"]:
		if source.find(forbidden) >= 0:
			return "look_aim_head.gd uses %s; it may only change the input it is handed" % forbidden
	# Flying a frame with look-aim on changes nothing in the session until a tick runs.
	var input_source: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LevelStart.tunnel_session(input_source)
	var before: int = session.sim.state_hash()
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = ComfortWiring.new(input_source, ThumbstickMapping.new())
	comfort.attach_cockpit_frame(rig, HeadRecentre.new())
	comfort.look_aim.head_trusted = func() -> bool: return true
	comfort.set_preset(1)
	_turn_head(rig, 20.0)
	comfort.hand_input(ShipInput.new(), session.current_ship().orientation, false)
	var after: int = session.sim.state_hash()
	var aimed: bool = input_source.latest_input().aims_off_nose()
	rig.free()
	if before != after:
		return "handing the head's aim on changed the session's state hash"
	if not aimed:
		return "the head's aim did not reach the input source"
	return ""
