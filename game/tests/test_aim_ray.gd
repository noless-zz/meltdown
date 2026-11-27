extends RefCounted

## The aim ray (#1451, CRW-2, RUN-1, PLT-5, ARC-3, ARC-4, MP-2): it starts at
## the aim pose the selection reads and ends where the stations' and the shaft
## panel's own pick lands, with a dot; with nothing hit it fades out at its set
## length; it shows only where pointing selects; its look is a data file whose
## bad field is named and replaced by built-in values.

const RUN_SEED: int = 12345
const PINNED_OFFER: Array[String] = ["deep", "hot", "steady"]
const EPSILON: float = 0.0005


func _aim(hand: Vector3, target: Vector3) -> Transform3D:
	return Transform3D.IDENTITY.looking_at(target - hand, Vector3.UP).translated(hand)


## A stand-in rig: the room and its stations at a head point, as the hub hangs them.
func _rig_with_room() -> Node3D:
	var rig: Node3D = Node3D.new()
	var room: HubRoom = HubRoom.new()
	room.transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 1.2, 0.1))
	rig.add_child(room)
	var stations: HubStations = HubStations.new(room)
	rig.add_child(stations)
	room.visible = true
	stations.visible = true
	return rig


func test_the_shipped_look_loads() -> String:
	var spec: AimRaySpec = AimRaySpec.load_file()
	if spec.error != "":
		return spec.error
	if spec.length_m <= 0.0 or spec.width_m <= 0.0 or spec.dot_size_m <= 0.0:
		return "the shipped ray has no size"
	return ""


func test_a_bad_field_is_named_and_built_in_values_are_used() -> String:
	var cases: Dictionary = {
		"{\"width_m\": 0.004, \"length_m\": 99, \"dot_size_m\": 0.02, \"color\": [1,1,1,1], \"dot_color\": [1,1,1,1]}": "length_m",
		"{\"width_m\": 0.004, \"length_m\": 1, \"dot_size_m\": 0.02, \"color\": [1,1,1], \"dot_color\": [1,1,1,1]}": "color",
		"{\"width_m\": 0.004, \"length_m\": 1, \"dot_size_m\": 0.02, \"color\": [1,1,1,1]}": "dot_color",
		"{\"width_m\": 0.004, \"length_m\": 1, \"dot_size_m\": 0.02, \"color\": [1,1,1,1], \"dot_color\": [1,1,1,1], \"glow\": 1}": "glow",
	}
	var built_in: AimRaySpec = AimRaySpec.new()
	for text: String in cases:
		var spec: AimRaySpec = AimRaySpec.parse_json(text)
		if not spec.error.contains(cases[text]):
			return "the error '%s' does not name %s" % [spec.error, cases[text]]
		if spec.length_m != built_in.length_m or spec.color != built_in.color:
			return "a rejected file did not leave the built-in values"
	var ray: AimRay = AimRay.new(AimRaySpec.parse_json("{}"))
	var problem: String = "" if ray.spec.error == "" else "the ray kept a rejected spec"
	ray.free()
	return problem


func test_the_ray_ends_on_the_point_the_stations_pick() -> String:
	var rig: Node3D = _rig_with_room()
	var room: HubRoom = rig.get_node(HubRoom.NODE_NAME) as HubRoom
	var stations: HubStations = rig.get_node(HubStations.NODE_NAME) as HubStations
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var problem: String = ""
	for id: String in stations.ids:
		var target: Vector3 = room.transform * room.station_points()[id]
		var aim: Transform3D = _aim(room.transform * Vector3(0.2, -0.4, -0.2), target + Vector3(0.0, 0.05, 0.0))
		# The pick the hub's own `_point` makes, in the room's space.
		var to_room: Transform3D = room.transform.affine_inverse()
		var picked: String = HubStations.pick(to_room * aim.origin, to_room.basis * -aim.basis.z,
			room.station_points(), HubStations.POINT_RADIUS_M)
		ray.follow(rig, aim, true)
		var end: Vector3 = ray.end_point()
		var off_ray: float = (end - aim.origin).cross(-aim.basis.z.normalized()).length()
		var to_station: Vector3 = target - end
		if picked != id or not ray.visible or not ray.shows_dot():
			problem = "aiming at %s picked '%s', ray shown %s, dot %s" % [id, picked, ray.visible, ray.shows_dot()]
		elif off_ray > EPSILON or absf(to_station.dot(-aim.basis.z.normalized())) > EPSILON:
			problem = "the ray at %s ends %.4f m off its line, not across from the station" % [id, off_ray]
		if problem != "":
			break
	rig.free()
	return problem


func test_the_ray_ends_on_the_shaft_the_panel_picks() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77)
	var shapes: ShaftPanelShapes = ShaftPanelShapes.load_file()
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes)
	var rig: Node3D = Node3D.new()
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.2, 0.0))
	rig.add_child(panel)
	panel.show_model(model, true)
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var problem: String = ""
	for kind: String in PINNED_OFFER:
		var target: Vector3 = panel.transform * panel.entry_points()[kind]
		var aim: Transform3D = _aim(panel.transform * Vector3(0.15, -0.35, -0.3), target)
		var pointed: String = ShaftChoiceWiring.point_in(panel, aim, shapes.lengths["point_radius_m"])
		ray.follow(rig, aim, true)
		if pointed != kind or not ray.shows_dot() or ray.end_point().distance_to(target) > EPSILON:
			problem = "aiming at %s pointed '%s'; the ray ends %s, not on %s" % [kind, pointed, ray.end_point(), target]
			break
	rig.free()
	return problem


func test_with_nothing_hit_the_ray_fades_out_at_its_length() -> String:
	var rig: Node3D = _rig_with_room()
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var aim: Transform3D = _aim(Vector3(0.2, 0.8, 0.0), Vector3(0.2, 0.8, 5.0))  # Behind the seat.
	ray.follow(rig, aim, true)
	var length: float = ray.end_point().distance_to(aim.origin)
	var problem: String = ""
	if not ray.visible or ray.shows_dot() or absf(length - ray.spec.length_m) > EPSILON:
		problem = "a miss shows %s, dot %s, length %.3f" % [ray.visible, ray.shows_dot(), length]
	rig.free()
	return problem


func test_the_ray_shows_only_where_pointing_selects() -> String:
	var rig: Node3D = _rig_with_room()
	var room: HubRoom = rig.get_node(HubRoom.NODE_NAME) as HubRoom
	var stations: HubStations = rig.get_node(HubStations.NODE_NAME) as HubStations
	var ray: AimRay = AimRay.new()
	rig.add_child(ray)
	var aim: Transform3D = _aim(Vector3(0.2, 0.8, 0.0), room.transform * room.station_points()[stations.ids[0]])
	var problem: String = ""
	ray.follow(rig, aim, false)
	if ray.visible:
		problem = "an untracked controller shows a ray"
	room.visible = false
	stations.visible = false
	ray.follow(rig, aim, true)
	if problem == "" and ray.visible:
		problem = "the ray shows in flight"
	rig.free()
	return problem


func test_the_ray_is_drawn_on_the_hands_layer_above_the_fade() -> String:
	var ray: AimRay = AimRay.new()
	var fade: FadeOverlay = FadeOverlay.new()
	var fade_priority: int = (fade.material_override as Material).render_priority
	fade.free()
	var problem: String = ""
	for child: Node in ray.get_children():
		var part: MeshInstance3D = child as MeshInstance3D
		if part == null:
			continue
		if (part.layers & HubRoom.HANDS_LAYER_BIT) == 0:
			problem = "%s is not on the hands layer" % part.name
		elif (part.material_override as Material).render_priority <= fade_priority:
			problem = "%s draws under the fade" % part.name
	ray.free()
	return problem
