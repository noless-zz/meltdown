extends RefCounted

## The aiming hand (#1470, CRW-2, PLT-5, DEV-6, ARC-3, MP-2): the right
## controller aims, or the left one in left-handed mode, at the home base's
## stations, at the shaft choice and for the aim ray; a scripted pose stands in
## for the flat simulator's untracked controllers and is dropped on request.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const RUN_SEED: int = 12345
const PINNED_OFFER: Array[String] = ["deep", "hot", "steady"]
const EPSILON: float = 0.0005


static func _rig(left_handed: bool) -> Node3D:
	var rig: Node3D = (load(RIG_SCENE) as PackedScene).instantiate() as Node3D
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = left_handed
	rig.set("mapping", mapping)
	return rig


static func _aim(hand: Vector3, target: Vector3) -> Transform3D:
	return Transform3D.IDENTITY.looking_at(target - hand, Vector3.UP).translated(hand)


static func _set_left_handed(rig: Node, left_handed: bool) -> void:
	(rig.get("mapping") as ThumbstickMapping).left_handed = left_handed


func test_the_aiming_controller_follows_the_hand_mode() -> String:
	var problem: String = ""
	for left_handed: bool in [false, true]:
		var rig: Node3D = _rig(left_handed)
		var want: String = "LeftHand" if left_handed else "RightHand"
		var controller: XRController3D = AimHand.controller_on(rig)
		if controller == null or controller.name != want:
			problem = "left-handed %s aims with %s, not %s" % [left_handed, controller, want]
		elif AimHand.new(rig).hand() != (AimHand.LEFT if left_handed else AimHand.RIGHT):
			problem = "left-handed %s names the %s hand" % [left_handed, AimHand.new(rig).hand()]
		rig.free()
		if problem != "":
			break
	if problem == "" and (AimHand.hand_on(null) != AimHand.RIGHT or bool(AimHand.pose_on(null)["tracked"])):
		problem = "no rig is not the right hand, untracked"
	return problem


func test_a_scripted_pose_is_the_aiming_hands_until_cleared() -> String:
	var rig: Node3D = _rig(false)
	var left_pose: Transform3D = _aim(Vector3(-0.2, 1.0, -0.3), Vector3(0.0, 1.2, -2.0))
	AimHand.script_pose(rig, AimHand.LEFT, left_pose)
	var problem: String = ""
	if AimHand.headset_running():
		problem = "the unit tests run with an XR interface initialised"
	elif bool(AimHand.pose_on(rig)["tracked"]):
		problem = "right-handed, a scripted left pose (and an untracked right controller) aims"
	_set_left_handed(rig, true)
	var held: Dictionary = AimHand.pose_on(rig)
	if problem == "" and (not bool(held["tracked"]) or not (held["aim"] as Transform3D).is_equal_approx(left_pose)):
		problem = "left-handed, the scripted left pose is not the aim: %s" % [held]
	AimHand.clear_scripted(rig)
	if problem == "" and bool(AimHand.pose_on(rig)["tracked"]):
		problem = "a cleared pose still aims"
	rig.free()
	return problem


func test_the_hub_picks_stations_with_the_aiming_hand() -> String:
	var stations: HubStations = Stations._open(Stations._hub(Profile.new()))
	var room: HubRoom = stations.get_parent() as HubRoom
	var points: Dictionary[String, Vector3] = room.station_points()
	var rig: Node3D = _rig(false)
	var hub: HubWiring = HubWiring.new()
	hub.stations = stations
	hub.room = room
	hub.aiming.rig = rig
	var hand: Vector3 = Vector3(0.2, -0.4, -0.3)
	AimHand.script_pose(rig, AimHand.RIGHT, _aim(hand, points["logbook"]))
	AimHand.script_pose(rig, AimHand.LEFT, _aim(-hand, points["resume"]))
	var problem: String = ""
	hub._point()
	if stations.highlighted_id() != "logbook":
		problem = "right-handed, the hub picked %s, not the right hand's logbook" % stations.highlighted_id()
	_set_left_handed(rig, true)
	hub._point()
	if problem == "" and stations.highlighted_id() != "resume":
		problem = "left-handed, the hub picked %s, not the left hand's resume" % stations.highlighted_id()
	rig.free()
	Stations._free(stations)
	return problem


func test_the_shaft_choice_picks_with_the_aiming_hand() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77)
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	var rig: Node3D = _rig(false)
	choice.attach(rig)
	choice.model = ShaftPanelModel.build(PINNED_OFFER, run.shafts, choice.look, choice.shapes)
	choice.panel.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.2, 0.0))
	choice.panel.show_model(choice.model, true)
	var at: Dictionary[String, Vector3] = {}
	for kind: String in ["hot", "steady"]:
		at[kind] = choice.panel.transform * choice.panel.entry_points()[kind]
	AimHand.script_pose(rig, AimHand.RIGHT, _aim(Vector3(0.15, 0.85, -0.3), at["hot"]))
	AimHand.script_pose(rig, AimHand.LEFT, _aim(Vector3(-0.15, 0.85, -0.3), at["steady"]))
	var problem: String = ""
	choice._point()
	if choice.model.selected() != "hot":
		problem = "right-handed, the shaft choice picked %s, not the right hand's hot" % choice.model.selected()
	_set_left_handed(rig, true)
	choice._point()
	if problem == "" and choice.model.selected() != "steady":
		problem = "left-handed, the shaft choice picked %s, not the left hand's steady" % choice.model.selected()
	rig.free()
	return problem


func test_the_ray_hangs_from_the_aiming_hand() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77)
	var rig: Node3D = _rig(false)
	rig.call("build")
	var shapes: ShaftPanelShapes = ShaftPanelShapes.load_file()
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.2, 0.0))
	rig.add_child(panel)
	panel.show_model(ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes), true)
	var target: Vector3 = panel.transform * panel.entry_points()["hot"]
	var right_pose: Transform3D = _aim(panel.transform * Vector3(0.15, -0.35, -0.3), target)
	var left_pose: Transform3D = _aim(panel.transform * Vector3(-0.15, -0.35, -0.3), target)
	AimHand.script_pose(rig, AimHand.RIGHT, right_pose)
	AimHand.script_pose(rig, AimHand.LEFT, left_pose)
	var ray: AimRay = rig.call("aim_ray")
	var problem: String = "the rig built no aim ray" if ray == null else ""
	for left_handed: bool in [false, true]:
		if problem != "":
			break
		_set_left_handed(rig, left_handed)
		rig.call("point_ray")
		var from: Vector3 = (left_pose if left_handed else right_pose).origin
		if not ray.shows_dot() or ray.transform.origin.distance_to(from) > EPSILON:
			problem = "left-handed %s: the ray starts at %s, not the hand at %s (dot %s)" % [
				left_handed, ray.transform.origin, from, ray.shows_dot()]
	AimHand.clear_scripted(rig)
	if problem == "" and ray != null:
		rig.call("point_ray")
		if ray.visible:
			problem = "untracked controllers without a scripted pose still show the ray"
	rig.free()
	return problem
