extends RefCounted

## Every session start hands the local ship's loadout to the comfort wiring
## (CMB-8, CRF-4, CRF-5, MP-2, ARC-3, #1050): a ship fitted with the look-aim
## module aims with the head at preset 3, the same ship without it does not,
## and a module from an earlier session never sticks. The loadout is only read.

const SHIP_FILE: String = "res://data/ships/default_ship.json"


func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	return rig


static func _turn_head(rig: Node3D, degrees_right: float) -> void:
	var camera: Node3D = rig.get_node("Camera") as Node3D
	camera.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees_right)), Vector3(0.0, 1.2, 0.0))


## The shipped ship file as a test dictionary, with `modules` in its utility slots.
static func _tuning(modules: Array) -> ShipTuning:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHIP_FILE))
	data["loadout"]["utility"] = modules
	return ShipTuning.parse_json(JSON.stringify(data))


func _comfort(rig: Node3D, input: LatestInputSource) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(input, ThumbstickMapping.new())
	comfort.attach_cockpit_frame(rig, HeadRecentre.new())
	comfort.look_aim.head_trusted = func() -> bool: return true
	comfort.set_preset(3)
	return comfort


## The aim preset 3 hands the session after a session whose ship carries `modules` starts.
func _aim_with(modules: Array) -> Array:
	var rig: Node3D = _rig()
	var input: LatestInputSource = LatestInputSource.new()
	var comfort: ComfortWiring = _comfort(rig, input)
	var tuning: ShipTuning = _tuning(modules)
	if tuning.error != "":
		rig.free()
		return [Vector3i.ZERO, "ship refused: " + tuning.error]
	var session: LocalSession = LocalSession.new(0, input, null, tuning)
	LevelStart.new(comfort).hand_loadout(session)
	_turn_head(rig, 20.0)
	comfort.hand_input(ShipInput.new(), session.current_ship().orientation, false)
	var aim: Vector3i = input.latest_input().aim_q
	rig.free()
	return [aim, ""]


func test_preset_three_aims_with_the_head_when_the_ship_has_the_module() -> String:
	var fitted: Array = _aim_with(["look_aim"])
	var bare: Array = _aim_with([])
	if fitted[1] != "" or bare[1] != "":
		return "%s %s" % [fitted[1], bare[1]]
	if fitted[0] == ShipInput.NOSE_AIM_Q:
		return "preset 3 with the module fitted stayed on the nose"
	if bare[0] != ShipInput.NOSE_AIM_Q:
		return "preset 3 without the module aimed at %s" % bare[0]
	return ""


func test_the_local_loadout_is_the_ship_files() -> String:
	var session: LocalSession = LocalSession.new(0, null, null, _tuning(["look_aim"]))
	var ids: Array[String] = LevelStart.local_loadout(session).utility_ids
	if ids != (["look_aim"] as Array[String]):
		return "loadout utility %s" % [ids]
	if not LevelStart.local_loadout(LocalSession.new()).utility_ids.is_empty():
		return "a session without a ship file has modules"
	if not LevelStart.local_loadout(null).utility_ids.is_empty():
		return "no session has modules"
	return ""


func test_a_new_level_without_the_module_turns_it_off() -> String:
	var rig: Node3D = _rig()
	var world: Node3D = Node3D.new()
	var input: LatestInputSource = LatestInputSource.new()
	var comfort: ComfortWiring = _comfort(rig, input)
	var start: LevelStart = LevelStart.new(comfort)
	start.hand_loadout(LocalSession.new(0, input, null, _tuning(["look_aim"])))
	var on_before: bool = comfort.look_aim.enabled
	start.source = LevelSwitch.path_for("g2")
	var level: LocalSession = start.fresh_session(world, input)
	var on_level: bool = comfort.look_aim.enabled
	start.hand_loadout(LocalSession.new(0, input, null, _tuning(["look_aim"])))
	start.source = ""
	var tunnel: LocalSession = start.fresh_session(world, input)
	var on_tunnel: bool = comfort.look_aim.enabled
	world.free()
	rig.free()
	if level == null or tunnel == null:
		return "a session did not start"
	if not on_before or on_level or on_tunnel:
		return "look-aim at preset 3: fitted %s, then g2 %s, then the tunnel %s" % [on_before, on_level, on_tunnel]
	return ""


func test_handing_the_loadout_leaves_the_session_alone() -> String:
	var rig: Node3D = _rig()
	var input: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(0, input, null, _tuning(["look_aim"]))
	var before: int = session.sim.state_hash()
	var replay_before: String = session.replay.to_text()
	LevelStart.new(_comfort(rig, input)).hand_loadout(session)
	rig.free()
	if session.sim.state_hash() != before or session.replay.to_text() != replay_before:
		return "handing the loadout changed the session"
	return ""


## The launch with no level, or a rejected one, keeps flying the tunnel's
## session (#1050 review): its ship's look-aim module still reaches preset 3.
func test_a_launch_into_the_tunnel_hands_its_loadout() -> String:
	var rig: Node3D = _rig()
	var world: Node3D = Node3D.new()
	var input: LatestInputSource = LatestInputSource.new()
	var comfort: ComfortWiring = _comfort(rig, input)
	var start: LevelStart = LevelStart.new(comfort)
	var tunnel: LocalSession = LocalSession.new(0, input, null, _tuning(["look_aim"]))
	var kept_empty: LocalSession = start.start_or_keep(world, "", input, tunnel)
	var on_empty: bool = comfort.look_aim.enabled
	comfort.set_loadout(ShipLoadout.new())
	var kept_rejected: LocalSession = start.start_or_keep(world, "res://no_such_level.json", input, tunnel)
	var on_rejected: bool = comfort.look_aim.enabled
	world.free()
	rig.free()
	if kept_empty != tunnel or kept_rejected != tunnel:
		return "the launch did not keep the tunnel's session"
	if not on_empty or not on_rejected:
		return "look-aim at preset 3 after a tunnel launch: no level %s, rejected level %s" % [on_empty, on_rejected]
	return ""
