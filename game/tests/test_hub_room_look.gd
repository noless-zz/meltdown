extends RefCounted

## The home base room lit as a hangar (#1369, CRW-2, GFX-2, GFX-4, GFX-5,
## LGT-1, ARC-4): the room file parses with worn materials, spot lights and
## the ship; the lights stay within GFX-4's budget, light the room's layer and
## cast no shadows; the ship on the cradle is `ShipModel`, turned to the seat
## at the file's angle and lit by its own light; nothing glows brighter than
## the station screens in their direction; the room's draw calls stay within
## its share of PRF-4.

const ROOM_FILE: String = "res://data/hub/room.json"
## A glow this close to a station's direction from the eye, plus its own
## angular size, counts as "in the station's direction".
const STATION_CONE_DEG: float = 10.0
## A three-quarter view: neither nose-on nor side-on.
const THREE_QUARTER_DEG: Array[float] = [25.0, 55.0]


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOM_FILE))


func test_the_room_file_parses_with_worn_materials() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	if spec.error != "":
		return "the shipped room is rejected: %s" % spec.error
	var room: HubRoom = HubRoom.new(spec)
	var problem: String = ""
	for name: String in ["WallLeft", "Floor", "Prop_rack_left", "Prop_cradle_left", "Prop_crate_a"]:
		var part: MeshInstance3D = room.get_node_or_null(name) as MeshInstance3D
		if part == null or not part.material_override is ShaderMaterial:
			problem = "%s has no worn surface" % name
		elif part.get_instance_shader_parameter("part_size") != (part.mesh as PrimitiveMesh).get_aabb().size:
			problem = "%s's surface does not know its size" % name
	var screen: MeshInstance3D = room.get_node("Station_craft/Screen") as MeshInstance3D
	if not screen.material_override is StandardMaterial3D:
		problem = "a station screen took the worn surface"
	room.free()
	return problem


func test_bad_room_values_are_rejected() -> String:
	var cases: Dictionary[String, Callable] = {
		"a wear of 2": func(data: Dictionary) -> void: data["materials"]["wall"]["wear"] = 2.0,
		"a spot with no aim": func(data: Dictionary) -> void: (data["lights"][0] as Dictionary).erase("aim_m"),
		"a light of type laser": func(data: Dictionary) -> void: data["lights"][1]["type"] = "laser",
		"a light of role sun": func(data: Dictionary) -> void: data["lights"][1]["role"] = "sun",
		"a ship turned 120 degrees": func(data: Dictionary) -> void: data["ship"]["facing_deg"] = 120.0,
		"a ship on the seat": func(data: Dictionary) -> void: data["ship"]["position_m"] = [0.0, -0.4, 0.0],
		"a ship with a colour": func(data: Dictionary) -> void: data["ship"]["colour"] = [1.0, 0.0, 0.0],
	}
	for name: String in cases:
		var data: Dictionary = _shipped()
		cases[name].call(data)
		if HubRoomSpec.parse(JSON.stringify(data)).error == "":
			return "%s was accepted" % name
	var none: Dictionary = _shipped()
	none.erase("ship")
	var spec: HubRoomSpec = HubRoomSpec.parse(JSON.stringify(none))
	var room: HubRoom = HubRoom.new(spec)
	var problem: String = "" if spec.error == "" and room.ship() == null else "a room with no ship: %s" % spec.error
	room.free()
	return problem


func test_the_lights_are_within_budget_and_light_the_room() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	var room: HubRoom = HubRoom.new(spec)
	var roles: Array[String] = []
	var problem: String = ""
	for child: Node in room.get_children():
		if not child is Light3D:
			continue
		var light: Light3D = child
		roles.append(str(light.get_meta("role", "")))
		if light.shadow_enabled:
			problem = "%s casts shadows (GFX-4)" % light.name
		if light.layers != HubRoom.LAYER_BIT or light.light_cull_mask != HubRoom.LAYER_BIT:
			problem = "%s is not on the room's layer, so the room's camera drops it" % light.name
	if room.light_count() > HubRoomSpec.MAX_LIGHTS:
		problem = "%d lights, over %d (GFX-4)" % [room.light_count(), HubRoomSpec.MAX_LIGHTS]
	for role: String in ["key", "fill", "practical", "ship"]:
		if not roles.has(role):
			problem = "no %s light" % role
	if roles.count("practical") < 2:
		problem = "%d practical lights, expected the screens' and the pad's" % roles.count("practical")
	room.free()
	return problem


func test_a_spot_points_where_the_file_aims_it() -> String:
	var data: Dictionary = {"role": "key", "type": "spot", "position": Vector3(1.0, 2.0, -1.0),
		"aim": Vector3(0.0, -1.0, -3.0), "angle": 30.0, "color": Color.WHITE, "energy": 1.0, "range": 6.0}
	var spot: SpotLight3D = HubRoomLights.build(0, data, HubRoom.LAYER_BIT) as SpotLight3D
	var forward: Vector3 = -spot.transform.basis.z
	var wanted: Vector3 = (data["aim"] - data["position"]).normalized()
	var problem: String = ""
	if spot == null or forward.angle_to(wanted) > 0.001 or spot.spot_angle != 30.0 or spot.spot_range != 6.0:
		problem = "the spot shines along %s, not %s" % [forward, wanted]
	if not HubRoomLights.spot_reaches(data, data["aim"]) or HubRoomLights.spot_reaches(data, Vector3(5.0, 2.0, 2.0)):
		problem = "spot_reaches is wrong"
	spot.free()
	return problem


func test_the_ship_on_the_cradle_faces_the_seat_at_the_set_angle() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	if spec.ship.is_empty():
		return "the room file has no ship"
	for prop: Dictionary in spec.props:
		if str(prop["id"]).begins_with("ship_"):
			return "the old prop %s is still in the room" % prop["id"]
	var facing: float = spec.ship["facing_deg"]
	if facing < THREE_QUARTER_DEG[0] or facing > THREE_QUARTER_DEG[1]:
		return "the ship is turned %.0f degrees, not three-quarters to the seat" % facing
	var room: HubRoom = HubRoom.new(spec)
	var ship: ShipModel = room.ship()
	var problem: String = ""
	if ship == null or ship.pieces().is_empty():
		problem = "the room has no ship model"
	elif absf(HubRoomShip.facing_angle_deg(ship) - facing) > 0.5:
		problem = "the ship faces %.1f degrees off the seat, not %.1f" % [HubRoomShip.facing_angle_deg(ship), facing]
	elif ship.position != spec.ship["position"] or not is_equal_approx(ship.transform.basis.get_scale().x, spec.ship["scale"]):
		problem = "the ship is at %s, scale %s" % [ship.position, ship.transform.basis.get_scale()]
	else:
		for piece: MeshInstance3D in ship.pieces():
			if piece.layers != HubRoom.LAYER_BIT:
				problem = "a ship piece is drawn off the room's layer"
	room.free()
	return problem


func test_the_ship_is_lit_by_its_own_light() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	for light: Dictionary in spec.lights:
		if light["role"] == "ship" and HubRoomLights.spot_reaches(light, spec.ship["position"]):
			return ""
	return "no spot with the ship role reaches the ship at %s" % spec.ship["position"]


func test_nothing_glows_brighter_than_the_screens_in_their_direction() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	var room: HubRoom = HubRoom.new(spec)
	var dimmest: float = INF
	for station: Dictionary in spec.stations:
		dimmest = minf(dimmest, HubRoomParts.glow(HubRoomParts.material(spec.materials[station["screen"]])))
	var points: Dictionary[String, Vector3] = room.station_points()
	var problem: String = ""
	var pending: Array[Node] = room.get_children()
	while not pending.is_empty() and problem == "":
		var node: Node = pending.pop_back()
		if node.name.begins_with("Station_"):
			continue
		pending.append_array(node.get_children())
		if not node is MeshInstance3D or HubRoomParts.glow((node as MeshInstance3D).material_override) < dimmest:
			continue
		var box: AABB = _in_room(node as Node3D, room) * (node as MeshInstance3D).mesh.get_aabb()
		var centre: Vector3 = box.get_center()
		var size_deg: float = rad_to_deg(atan2(box.size.length() * 0.5, centre.length()))
		for id: String in points:
			var apart: float = rad_to_deg(centre.angle_to(points[id]))
			if apart < STATION_CONE_DEG + size_deg:
				problem = "%s glows %.2f, over the screens' %.2f, %.0f degrees from the %s station" % [
					node.name, HubRoomParts.glow((node as MeshInstance3D).material_override), dimmest, apart, id]
	room.free()
	return problem


func test_the_room_stays_within_its_draw_calls() -> String:
	var room: HubRoom = HubRoom.new()
	var cost: Dictionary = room.cost()
	room.free()
	print("  hub room: %d draw calls, %d materials, %d lights" % [cost["draw_calls"], cost["materials"], cost["lights"]])
	if int(cost["draw_calls"]) > HubRoom.MAX_DRAW_CALLS:
		return "%d draw calls, over the room's %d" % [cost["draw_calls"], HubRoom.MAX_DRAW_CALLS]
	return "" if int(cost["draw_calls"]) > 0 else "the room counts no draw calls"


func _in_room(node: Node3D, room: HubRoom) -> Transform3D:
	var at: Transform3D = Transform3D.IDENTITY
	var each: Node = node
	while each != room and each is Node3D:
		at = (each as Node3D).transform * at
		each = each.get_parent()
	return at
