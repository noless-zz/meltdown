extends RefCounted

## Where the aim ray shows (#1508, PLT-5, CMF-8, CRW-2, MP-2): at the home
## base while its room holds the camera, at the shaft choice and while the dev
## menu is open; hidden from launch until the next base or shaft choice, and
## hidden again when the dev menu closes in flight. The open dev menu alone
## leaves flight's labels on the hands.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
## The flight the issue asks for: 120 ticks with the ray asked every frame.
const FLIGHT_TICKS: int = 120


## A right-hand aim in the rig's space, forward from about where a hand rests.
static func _aim() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.2, 1.2, -0.3))


## A plain rig with a camera, the hub's room and stations, a shaft panel and
## the dev menu hung as the scene hangs them, all closed.
static func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	var room: HubRoom = HubRoom.new()
	rig.add_child(room)
	var stations: HubStations = HubStations.new(room)
	stations.visible = false
	rig.add_child(stations)
	rig.add_child(ShaftPanel.new())
	rig.add_child(DevMenu.new())
	return rig


static func _open_base(rig: Node3D) -> void:
	(rig.get_node(HubRoom.NODE_NAME) as HubRoom).show_for(rig.get_node("Camera") as Camera3D)
	(rig.get_node(HubStations.NODE_NAME) as HubStations).visible = true


## As `HubWiring.close` leaves them on launch.
static func _launch(rig: Node3D) -> void:
	(rig.get_node(HubStations.NODE_NAME) as HubStations).visible = false
	(rig.get_node(HubRoom.NODE_NAME) as HubRoom).hide_room()


static func _menu(rig: Node3D) -> DevMenu:
	return rig.get_node(DevMenu.NODE_NAME) as DevMenu


## The ray after one frame's `follow` with a tracked controller.
static func _shown(rig: Node3D, ray: AimRay) -> bool:
	ray.follow(rig, _aim(), true)
	return ray.visible or ray.shows_dot()


func test_the_ray_shows_at_the_base_the_shaft_choice_and_the_open_menu() -> String:
	var rig: Node3D = _rig()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var problem: String = ""
	_open_base(rig)
	if not _shown(rig, ray):
		problem = "no ray at the home base"
	_launch(rig)
	var panel: ShaftPanel = rig.get_node(ShaftPanel.NODE_NAME) as ShaftPanel
	panel.visible = true
	if problem == "" and not _shown(rig, ray):
		problem = "no ray at the shaft choice"
	panel.visible = false
	_menu(rig).open(PanelCorner.DEFAULT_CORNER, "")
	if problem == "" and not _shown(rig, ray):
		problem = "no ray in the open dev menu"
	if problem == "" and ray.shows_dot():
		problem = "the ray lands on something in the dev menu, which has no targets yet"
	rig.free()
	return problem


func test_from_launch_the_ray_stays_hidden_until_the_next_base() -> String:
	var rig: Node3D = _rig()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	_open_base(rig)
	_shown(rig, ray)
	_launch(rig)
	var problem: String = ""
	for tick: int in FLIGHT_TICKS:
		if _shown(rig, ray):
			problem = "the ray shows in flight at tick %d" % tick
			break
	_open_base(rig)
	if problem == "" and not _shown(rig, ray):
		problem = "the ray did not come back at the next base"
	rig.free()
	return problem


func test_a_room_left_visible_without_the_camera_shows_no_ray() -> String:
	var rig: Node3D = _rig()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var room: HubRoom = rig.get_node(HubRoom.NODE_NAME) as HubRoom
	room.visible = true  # Drawn, but the camera still draws the mine.
	(rig.get_node(HubStations.NODE_NAME) as HubStations).visible = true
	var problem: String = "the ray shows over the mine" if _shown(rig, ray) else ""
	rig.free()
	return problem


func test_closing_the_menu_in_flight_hides_the_ray() -> String:
	var rig: Node3D = _rig()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var problem: String = ""
	if _shown(rig, ray):
		problem = "the ray shows in flight before the menu opens"
	_menu(rig).open(PanelCorner.DEFAULT_CORNER, "")
	if problem == "" and not _shown(rig, ray):
		problem = "the open menu shows no ray"
	_menu(rig).close()
	if problem == "" and _shown(rig, ray):
		problem = "the ray stayed after the menu closed in flight"
	rig.free()
	return problem


func test_an_untracked_controller_shows_no_ray_in_the_menu() -> String:
	var rig: Node3D = _rig()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	_menu(rig).open(PanelCorner.DEFAULT_CORNER, "")
	ray.follow(rig, _aim(), false)
	var problem: String = "an untracked controller shows a ray" if ray.visible else ""
	rig.free()
	return problem


func test_the_open_menu_in_flight_keeps_flight_labels() -> String:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.call("build")
	var menu: DevMenu = DevMenu.new()
	rig.add_child(menu)
	menu.open(PanelCorner.DEFAULT_CORNER, "")
	rig.call("refresh_labels")
	var problem: String = ""
	if bool(rig.call("pointing_selects")) or bool(rig.call("base_labels_shown")):
		problem = "the dev menu in flight switched the hands to the base's labels"
	rig.free()
	return problem
