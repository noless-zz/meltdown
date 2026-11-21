extends RefCounted

## Swivel-chair yaw while the ship is held (#819, CMF-7, CMF-8, MP-2, ARC-3):
## held input gets no swivel yaw, the end of a hold recentres on the head, and
## `ShipHold` calls the dev menu, the flight test's answer, the focus pause and
## the end screens a hold. Swivel off leaves input untouched as before.

const SCRATCH_DIR: String = "user://test_swivel_hold"

## A steady clock that never lets the reference follow far.
var _now_s: float = 0.0


static func _rig() -> Node3D:
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


func _comfort(rig: Node3D, source: LatestInputSource = LatestInputSource.new()) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(source, ThumbstickMapping.new())
	comfort.swivel.attach(rig, HeadRecentre.new())
	comfort.swivel.clock = func() -> float: return _now_s
	return comfort


func _frame(comfort: ComfortWiring, held: bool) -> ShipInput:
	_now_s += 1.0 / 90.0
	return comfort.swivel.added(ShipInput.new(), held)


## The stick yaw a turned `ShipInput` stands for, + nose right.
static func _stick_of(input: ShipInput) -> float:
	return -float(input.turn_q.y) / (ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)


## Head 60 degrees right through a hold, the hold ends with the head still
## there, then 45 degrees further: zero, zero, then (45 - 30) * 0.03.
func _hold_then_turn(held_frames: int) -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig)
	comfort.swivel.set_preset(_swivel_on(4))
	_turn_head(rig, 60.0)
	var during: ShipInput = ShipInput.new()
	for i: int in held_frames:
		during = _frame(comfort, true)
	var released: ShipInput = _frame(comfort, false)
	_turn_head(rig, 105.0)
	var further: ShipInput = _frame(comfort, false)
	rig.free()
	if during.turn_q != Vector3i.ZERO:
		return "held with the head 60 degrees right turned %s" % during.turn_q
	if released.turn_q != Vector3i.ZERO:
		return "the hold ended with the head still turned and the ship turned %s" % released.turn_q
	var want: float = (45.0 - 30.0) * 0.03
	if absf(_stick_of(further) - want) > 0.002:
		return "45 degrees further after the hold gave stick yaw %s, expected +%s" % [_stick_of(further), want]
	return ""


func test_held_input_gets_no_swivel_and_the_release_recentres() -> String:
	return _hold_then_turn(90)


func test_a_one_frame_hold_still_recentres() -> String:
	return _hold_then_turn(1)


func test_held_is_handed_through_hand_input() -> String:
	var rig: Node3D = _rig()
	var source: LatestInputSource = LatestInputSource.new()
	var comfort: ComfortWiring = _comfort(rig, source)
	comfort.set_preset(4)
	comfort.swivel.set_preset(_swivel_on(4))
	_turn_head(rig, 60.0)
	_now_s += 1.0 / 90.0
	comfort.hand_input(ShipInput.new(), Basis.IDENTITY, false, true)
	var held_yaw: int = source.latest_input().turn_q.y
	_now_s += 1.0 / 90.0
	comfort.hand_input(ShipInput.new(), Basis.IDENTITY, false)
	var released_yaw: int = source.latest_input().turn_q.y
	_turn_head(rig, 105.0)
	_now_s += 1.0 / 90.0
	comfort.hand_input(ShipInput.new(), Basis.IDENTITY, false)
	var turned: float = _stick_of(source.latest_input())
	rig.free()
	if held_yaw != 0 or released_yaw != 0:
		return "through hand_input: held yaw %d, released yaw %d, expected 0 and 0" % [held_yaw, released_yaw]
	if not turned > 0.4:
		return "through hand_input 45 degrees further gave stick yaw %s" % turned
	return ""


func test_a_preset_turning_the_swivel_on_inside_a_hold_recentres_at_its_end() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig)
	_frame(comfort, true)  # Menu open on a swivel-off preset.
	comfort.swivel.set_preset(_swivel_on(4))  # Chosen in the menu.
	_turn_head(rig, 90.0)  # The chair turns while the menu is open.
	var held: ShipInput = _frame(comfort, true)
	var released: ShipInput = _frame(comfort, false)
	rig.free()
	if held.turn_q != Vector3i.ZERO or released.turn_q != Vector3i.ZERO:
		return "swivel switched on in a hold turned %s held, %s on release" % [held.turn_q, released.turn_q]
	return ""


func test_swivel_off_and_shipped_presets_hand_back_the_same_input() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig)
	_turn_head(rig, 90.0)
	var input: ShipInput = ShipInput.new(Vector3i(10, -20, -300), Vector3i(40, 50, 60), true)
	for number: int in [1, 2, 3, 4]:
		comfort.set_preset(number)
		for held: bool in [true, false]:
			if comfort.swivel.added(input, held) != input:
				rig.free()
				return "preset %d held=%s did not hand back the same input" % [number, held]
	rig.free()
	return ""


static func _session() -> LocalSession:
	return LevelStart.tunnel_session(LatestInputSource.new())


func test_flying_freely_is_not_a_hold() -> String:
	var menu: DevMenu = DevMenu.new()
	var dev_menu: DevMenuWiring = DevMenuWiring.new()
	dev_menu.menu = menu
	menu.visible = false
	var held: bool = ShipHold.is_held(dev_menu, FlightTestWiring.new(), _session(), DestroyedWiring.new())
	var nothing_wired: bool = ShipHold.is_held(null, null, _session(), null)
	menu.free()
	if held or nothing_wired:
		return "flying freely counts as held (wired %s, nothing wired %s)" % [held, nothing_wired]
	return ""


func test_the_dev_menu_open_is_a_hold() -> String:
	var menu: DevMenu = DevMenu.new()
	var dev_menu: DevMenuWiring = DevMenuWiring.new()
	dev_menu.menu = menu
	menu.visible = true
	var held: bool = ShipHold.is_held(dev_menu, null, _session(), null)
	menu.free()
	return "" if held else "the open dev menu is not a hold"


func test_the_flight_test_answer_is_a_hold() -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/choice.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var wired: FlightTestWiring = FlightTestWiring.new()
	wired.choice_path = path
	wired.begin(FlightTestWiring.Start.TUNNEL, comfort, comfort.set_preset)
	var flying: bool = ShipHold.is_held(null, wired, _session(), null)
	wired.read_buttons({}, false)
	wired.update(60.0, false)  # The segment's time runs out: an answer is due.
	var answering: bool = ShipHold.is_held(null, wired, _session(), null)
	if not wired.test.awaiting_answer():
		return "no answer due after the segment's time"
	if flying or not answering:
		return "flight test: held while flying %s, while answering %s" % [flying, answering]
	return ""


func test_the_focus_pause_and_a_lost_ship_are_holds() -> String:
	var paused: LocalSession = _session()
	paused.paused = true
	var lost: LocalSession = _session()
	lost.sim.ships[0].hull = 0.0
	lost.advance(1.0 / 60.0)  # The panel's copy follows at the next tick.
	if not ShipHold.is_held(null, null, paused, null):
		return "the focus pause is not a hold"
	if not ShipHold.is_held(null, null, lost, null):
		return "a lost ship is not a hold"
	return ""


func test_ship_hold_writes_nothing() -> String:
	var source: String = FileAccess.get_file_as_string("res://ship_hold.gd")
	for forbidden: String in ["set_input", ".step(", ".advance(", " = "]:
		if source.find(forbidden) >= 0:
			return "ship_hold.gd uses %s; it may only read" % forbidden
	return ""
