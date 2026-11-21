extends RefCounted

## Swivel-chair yaw in the input path (CMF-7, CMF-3, CMF-6, ARC-3, #791): off
## leaves input untouched, on adds yaw from the head before the comfort filter,
## recentres zero it, and turning it on with a preset change recentres.

## Sixty frames' worth of steady clock, so the reference never follows here.
var _now_s: float = 0.0


func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	return rig


static func _turn_head(rig: Node3D, degrees_right: float) -> void:
	var camera: Node3D = rig.get_node("Camera") as Node3D
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees_right)), Vector3(0.0, 1.2, 0.0))


static func _swivel_on(number: int) -> ComfortPreset:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(number).duplicate() as ComfortPreset
	preset.swivel_enabled = true
	return preset


func _comfort(rig: Node3D, recentre: HeadRecentre) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.swivel.attach(rig, recentre)
	comfort.swivel.clock = func() -> float: return _now_s
	return comfort


func _frame(comfort: ComfortWiring, input: ShipInput) -> ShipInput:
	_now_s += 1.0 / 90.0
	return comfort.swivel.added(input)


## The stick yaw value a turned `ShipInput` stands for, + nose right.
static func _stick_of(input: ShipInput) -> float:
	return -float(input.turn_q.y) / (ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)


func test_off_gives_unchanged_input_on_every_preset() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, HeadRecentre.new())
	_turn_head(rig, 90.0)
	var input: ShipInput = ShipInput.new(Vector3i(10, -20, -300), Vector3i(40, 50, 60), true)
	for number: int in [1, 2, 3, 4]:
		comfort.set_preset(number)
		if comfort.swivel.yaw.enabled:
			rig.free()
			return "preset %d switched the swivel on" % number
		if _frame(comfort, input) != input:
			rig.free()
			return "preset %d: an off swivel did not hand back the same input" % number
	rig.free()
	return ""


func test_on_head_right_gives_right_yaw_past_the_dead_zone() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, HeadRecentre.new())
	comfort.swivel.set_preset(_swivel_on(4))
	_turn_head(rig, 20.0)
	var inside: ShipInput = _frame(comfort, ShipInput.new())
	_turn_head(rig, 45.0)
	var out: ShipInput = _frame(comfort, ShipInput.new())
	rig.free()
	if inside.turn_q != Vector3i.ZERO:
		return "head 20 degrees right, inside the dead zone, turned %s" % inside.turn_q
	var want: float = (45.0 - 30.0) * 0.03
	if not is_equal_approx(snappedf(_stick_of(out), 0.001), want):
		return "head 45 degrees right gave stick yaw %s, expected +%s" % [_stick_of(out), want]
	return ""


func test_on_preset_one_turns_only_by_snaps() -> String:
	var rig: Node3D = _rig()
	var source: LatestInputSource = LatestInputSource.new()
	var comfort: ComfortWiring = ComfortWiring.new(source, ThumbstickMapping.new())
	comfort.swivel.attach(rig, HeadRecentre.new())
	comfort.swivel.clock = func() -> float: return _now_s
	comfort.set_preset(1)
	comfort.swivel.set_preset(_swivel_on(1))
	var snap: int = comfort.filter.snap_rate_q()
	_turn_head(rig, 60.0)
	var snaps: int = 0
	for i: int in 30:
		_now_s += 1.0 / 90.0
		comfort.hand_input(ShipInput.new(), Basis.IDENTITY, false)
		var yaw: int = source.latest_input().turn_q.y
		if yaw != 0 and absi(yaw) != snap:
			rig.free()
			return "frame %d: yaw %d is not 0 or one snap (%d)" % [i, yaw, snap]
		if yaw != 0:
			snaps += 1
		comfort.end_one_tick_if_flown(1)
	rig.free()
	if snaps != 1:
		return "a held body turn snapped %d times, expected once" % snaps
	return ""


func test_a_recentre_zeros_it() -> String:
	var rig: Node3D = _rig()
	var recentre: HeadRecentre = HeadRecentre.new()
	var comfort: ComfortWiring = _comfort(rig, recentre)
	comfort.swivel.set_preset(_swivel_on(3))
	_turn_head(rig, -70.0)
	var before: ShipInput = _frame(comfort, ShipInput.new())
	recentre.request()
	recentre.update((rig.get_node("Camera") as Node3D).transform, false)
	var after: ShipInput = _frame(comfort, ShipInput.new())
	rig.free()
	if not _stick_of(before) < 0.0:
		return "head 70 degrees left gave stick yaw %s before the recentre" % _stick_of(before)
	if after.turn_q != Vector3i.ZERO:
		return "after a recentre the same head turned %s" % after.turn_q
	return ""


func test_a_preset_change_to_swivel_on_recentres() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, HeadRecentre.new())
	_turn_head(rig, 80.0)
	comfort.swivel.set_preset(_swivel_on(3))
	var out: ShipInput = _frame(comfort, ShipInput.new())
	_turn_head(rig, 125.0)
	var further: ShipInput = _frame(comfort, ShipInput.new())
	rig.free()
	if out.turn_q != Vector3i.ZERO:
		return "switching the swivel on with the head 80 degrees right turned %s" % out.turn_q
	if not _stick_of(further) > 0.0:
		return "turning 45 degrees further right after switching on gave %s" % _stick_of(further)
	return ""


func test_an_untracked_head_gives_nothing() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, HeadRecentre.new())
	comfort.swivel.set_preset(_swivel_on(3))
	comfort.swivel.head_trusted = func() -> bool: return false
	_turn_head(rig, 90.0)
	var input: ShipInput = ShipInput.new()
	var out: ShipInput = _frame(comfort, input)
	rig.free()
	if out != input:
		return "a head without tracking turned the ship %s" % out.turn_q
	return ""


func test_main_connects_the_swivel_to_the_recentre() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.call("attach_cockpit_frame")
	var comfort: ComfortWiring = main.get("comfort")
	var recentre: HeadRecentre = main.get("head_recentre")
	var connected: bool = recentre.recentred.is_connected(comfort.swivel.on_recentred)
	var has_camera: bool = comfort.swivel.camera == main.get_node("XRRig/Camera")
	main.free()
	if not connected:
		return "main's head recentre does not recentre the swivel"
	if not has_camera:
		return "the swivel does not read the head from the rig's camera"
	return ""


func test_writes_no_simulation_state() -> String:
	var source: String = FileAccess.get_file_as_string("res://swivel_wiring.gd")
	for forbidden: String in ["set_input", ".step(", "res://core/"]:
		if source.find(forbidden) >= 0:
			return "swivel_wiring.gd uses %s; it may only change the input it is handed" % forbidden
	return ""
