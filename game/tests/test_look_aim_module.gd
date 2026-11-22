extends RefCounted

## A fitted look-aim module keeps look-aim on at every preset (CMB-8, CRF-5,
## CMB-6, CMF-6, ARC-3, MP-2, decision record 0010, #1042): the flag comes
## from the local ship's loadout, survives every preset change, and only
## changes which aim this player's input carries.

## Each preset's own look-aim value, presets 1 to 4 (record 0010).
const TABLE: Array[bool] = [true, true, false, false]


func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	return rig


## Turns the rig's head `degrees_right` of the nose.
static func _turn_head(rig: Node3D, degrees_right: float) -> void:
	var camera: Node3D = rig.get_node("Camera") as Node3D
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees_right)), Vector3(0.0, 1.2, 0.0))


## A loadout as a ship file names it, with `modules` in its utility slots.
static func _loadout(modules: Array) -> ShipLoadout:
	var loadout: ShipLoadout = ShipLoadout.from_data({"utility": modules})
	loadout.utility_slots = 2
	return loadout


func _comfort(rig: Node3D, number: int, modules: Array) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.attach_cockpit_frame(rig, HeadRecentre.new())
	comfort.look_aim.head_trusted = func() -> bool: return true
	comfort.set_loadout(_loadout(modules))
	comfort.set_preset(number)
	return comfort


## The aim the session would fly after one frame of `input`.
static func _flown_aim(comfort: ComfortWiring, input: ShipInput = ShipInput.new()) -> Vector3i:
	comfort.hand_input(input, Basis.IDENTITY, false)
	return (comfort.get("_input_source") as LatestInputSource).latest_input().aim_q


func test_the_module_id_loads() -> String:
	var loadout: ShipLoadout = _loadout(["look_aim"])
	if loadout.error != "":
		return "look_aim refused: " + loadout.error
	return ""


func test_preset_three_aims_with_the_head_only_with_the_module() -> String:
	var rig: Node3D = _rig()
	var with_module: ComfortWiring = _comfort(rig, 3, ["look_aim"])
	var without: ComfortWiring = _comfort(rig, 3, [])
	_turn_head(rig, 20.0)
	var aimed: Vector3i = _flown_aim(with_module)
	var nose: Vector3i = _flown_aim(without)
	rig.free()
	if aimed == ShipInput.NOSE_AIM_Q:
		return "preset 3 with the module stayed on the nose"
	if nose != ShipInput.NOSE_AIM_Q:
		return "preset 3 without the module aimed at %s" % nose
	return ""


func test_cycling_presets_keeps_look_aim_on_with_the_module() -> String:
	for fitted: bool in [true, false]:
		var rig: Node3D = _rig()
		var comfort: ComfortWiring = _comfort(rig, 1, ["look_aim"] if fitted else [])
		_turn_head(rig, 20.0)
		var seen: Array[String] = []
		for number: int in range(1, 5):
			if number > 1:
				comfort.set_preset(comfort.next_number())  # The switch the menu uses (#1260).
			var on: bool = _flown_aim(comfort) != ShipInput.NOSE_AIM_Q
			var expected: bool = fitted or TABLE[number - 1]
			if comfort.number != number or on != expected or comfort.look_aim.enabled != expected:
				seen.append("preset %d aimed %s" % [comfort.number, "with the head" if on else "at the nose"])
		rig.free()
		if not seen.is_empty():
			return "%s the module: %s" % ["with" if fitted else "without", ", ".join(seen)]
	return ""


func test_removing_the_module_gives_the_preset_back() -> String:
	var rig: Node3D = _rig()
	var comfort: ComfortWiring = _comfort(rig, 4, ["look_aim"])
	var on_with: bool = comfort.look_aim.enabled
	comfort.set_loadout(_loadout([]))
	var on_without: bool = comfort.look_aim.enabled
	comfort.set_loadout(null)
	var on_null: bool = comfort.look_aim.enabled
	rig.free()
	if not on_with or on_without or on_null:
		return "preset 4: with %s, without %s, no loadout %s" % [on_with, on_without, on_null]
	return ""


func test_the_module_flag_never_changes_the_sim_hash_for_the_same_aim() -> String:
	# Preset 1 aims with the head either way, so both players hand on the same
	# aim; the flag itself must reach nothing the simulation hashes (ARC-3).
	var rig: Node3D = _rig()
	var with_module: ComfortWiring = _comfort(rig, 1, ["look_aim"])
	var without: ComfortWiring = _comfort(rig, 1, [])
	var a: Sim = Sim.new(1042, 1)
	var b: Sim = Sim.new(1042, 1)
	var problem: String = ""
	for i: int in 90:
		_turn_head(rig, float(i % 30) - 15.0)
		var input: ShipInput = ShipInput.new(Vector3i(0, 0, -800), Vector3i(0, 30, 0), false, false, i % 4 == 0)
		with_module.hand_input(input, a.ships[0].orientation, false)
		without.hand_input(input, b.ships[0].orientation, false)
		var flown_a: ShipInput = (with_module.get("_input_source") as LatestInputSource).latest_input()
		var flown_b: ShipInput = (without.get("_input_source") as LatestInputSource).latest_input()
		if flown_a.aim_q != flown_b.aim_q:
			problem = "frame %d: aims %s and %s differ" % [i, flown_a.aim_q, flown_b.aim_q]
			break
		a.step([flown_a] as Array[ShipInput])
		b.step([flown_b] as Array[ShipInput])
	rig.free()
	if problem != "":
		return problem
	if a.state_hash() != b.state_hash():
		return "hash %d with the module flag, %d without" % [a.state_hash(), b.state_hash()]
	return ""


func test_the_cone_and_gimbal_rate_do_not_depend_on_the_module() -> String:
	var source: String = FileAccess.get_file_as_string("res://xr/look_aim_head.gd")
	for forbidden: String in ["set_look_aim", "LookAim.new", "LookAim.parse", "set_input", ".step("]:
		if source.find(forbidden) >= 0:
			return "look_aim_head.gd mentions %s; the module may only change the aim it hands on" % forbidden
	return ""
