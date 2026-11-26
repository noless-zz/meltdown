extends RefCounted

## The home base hangar details (#1397, CRW-2, GFX-2, GFX-4, PRF-4, ARC-4):
## the room file's details parse and hold each kind of hangar piece the issue
## names; pieces that share a material are one mesh, each vertex keeping its
## piece's values for the worn surface; the whole room stays within 60 draw
## calls with no light added; and nothing stands between the seat and a
## station's screen, in the shipped file or in a file that tries.

const ROOM_FILE: String = "res://data/hub/room.json"
## #1369's lights; the details add none (GFX-4).
const LIGHTS_BEFORE: int = 7
## Each kind of hangar piece the issue asks for, by the id prefix it uses.
const KINDS: Dictionary[String, String] = {
	"rib_": "ribbed wall panels", "mark_": "floor markings", "cable_": "cable runs",
	"gantry_": "an overhead gantry", "toolrack_": "a tool rack", "tool_": "tools",
	"shaft_": "a shaft mouth",
}


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOM_FILE))


func test_the_details_hold_every_kind_of_hangar_piece() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	if spec.error != "":
		return "the shipped room is rejected: %s" % spec.error
	if spec.details.is_empty() or spec.details.size() > HubRoomSpec.MAX_DETAILS:
		return "%d details, expected 1..%d" % [spec.details.size(), HubRoomSpec.MAX_DETAILS]
	for prefix: String in KINDS:
		var found: bool = false
		for piece: Dictionary in spec.details:
			found = found or str(piece["id"]).begins_with(prefix)
		if not found:
			return "no %s (no detail named %s...)" % [KINDS[prefix], prefix]
	var lit: Array[String] = []
	for piece: Dictionary in spec.details:
		if float(spec.materials[piece["material"]]["emission_energy"]) > 0.0 and not lit.has(piece["material"]):
			lit.append(piece["material"])
	return "" if lit.has("shaft_light") else "the shaft mouth has no lit rim: lit materials %s" % [lit]


func test_details_sharing_a_material_are_one_mesh() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	var used: Array[String] = []
	for piece: Dictionary in spec.details:
		if not used.has(piece["material"]):
			used.append(piece["material"])
	var room: HubRoom = HubRoom.new(spec)
	var problem: String = ""
	var meshes: int = 0
	for child: Node in room.get_children():
		if not child.name.begins_with(HubRoomDetails.NAME_PREFIX):
			continue
		meshes += 1
		var detail: MeshInstance3D = child
		if detail.layers != HubRoom.LAYER_BIT or detail.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			problem = "%s is off the room's layer or casts a shadow" % detail.name
		var made: Material = detail.material_override
		if made is ShaderMaterial and (made as ShaderMaterial).shader != HubRoomParts.DETAIL_SHADER:
			problem = "%s wears the single-part surface, which cannot read merged pieces" % detail.name
	if meshes != used.size():
		problem = "%d detail meshes for %d materials" % [meshes, used.size()]
	if room.light_count() > LIGHTS_BEFORE:
		problem = "%d lights, more than #1369's %d" % [room.light_count(), LIGHTS_BEFORE]
	room.free()
	return problem


func test_a_merged_vertex_keeps_its_piece() -> String:
	var a: Dictionary = {"shape": "box", "size": Vector3(1.0, 2.0, 3.0), "position": Vector3(5.0, 0.0, 0.0),
		"rotation": Vector3(0.0, 90.0, 0.0)}
	var b: Dictionary = {"shape": "cylinder", "size": Vector3(0.2, 1.0, 0.2), "position": Vector3(0.0, 1.0, 0.0),
		"rotation": Vector3.ZERO}
	var arrays: Array = HubRoomDetails.merged_arrays([a, b])
	var alone: int = (HubRoomParts.mesh("box", a["size"]).get_mesh_arrays()[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var on_piece: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var sizes: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if on_piece.size() != vertices.size() * 4 or sizes.size() != vertices.size() * 4:
		return "the custom channels do not hold four values per vertex"
	var local: Vector3 = Vector3(on_piece[0], on_piece[1], on_piece[2])
	if not vertices[0].is_equal_approx(HubRoomDetails.placed(a) * local):
		return "vertex 0 at %s is not its piece's %s placed" % [vertices[0], local]
	if on_piece[3] != 1.0 or Vector3(sizes[0], sizes[1], sizes[2]) != a["size"]:
		return "the box's vertex lost its size or box flag"
	if on_piece[alone * 4 + 3] != 0.0 or not is_equal_approx(sizes[alone * 4 + 1], 1.0):
		return "the cylinder's vertex carries the box's values"
	for index: int in indices:
		if index < 0 or index >= vertices.size():
			return "an index %d points past the %d vertices" % [index, vertices.size()]
	return ""


func test_the_room_is_within_sixty_draw_calls() -> String:
	var room: HubRoom = HubRoom.new()
	var cost: Dictionary = room.cost()
	room.free()
	if HubRoom.MAX_DRAW_CALLS > 60:
		return "the room's budget is %d, over the issue's 60" % HubRoom.MAX_DRAW_CALLS
	if int(cost["draw_calls"]) > HubRoom.MAX_DRAW_CALLS:
		return "%d draw calls, over %d" % [cost["draw_calls"], HubRoom.MAX_DRAW_CALLS]
	return ""


func test_no_piece_stands_between_the_seat_and_a_station() -> String:
	var spec: HubRoomSpec = HubRoomSpec.load_shipped()
	var pieces: Array[Dictionary] = spec.props.duplicate()
	pieces.append_array(spec.details)
	for piece: Dictionary in pieces:
		for station: Dictionary in spec.stations:
			if HubRoomSight.blocks(piece, station["position"]):
				return "%s blocks the %s station" % [piece["id"], station["id"]]
	return ""


func test_a_detail_in_a_stations_line_is_rejected() -> String:
	var data: Dictionary = _shipped()
	var craft: Array = (data["stations"] as Array).filter(func(s: Dictionary) -> bool: return s["id"] == "craft")[0]["position_m"]
	var midway: Array = [float(craft[0]) * 0.5, float(craft[1]) * 0.5, float(craft[2]) * 0.5]
	(data["details"] as Array).append({"id": "cable_in_the_way", "shape": "cylinder", "size_m": [0.04, 1.0, 0.04],
		"position_m": midway, "rotation_deg": [0.0, 0.0, 90.0], "material": "cable"})
	var error: String = HubRoomSpec.parse(JSON.stringify(data)).error
	if not (error.contains("cable_in_the_way") and error.contains("station")):
		return "a cable across the craft station's line gave: \"%s\"" % error
	var beside: Dictionary = _shipped()
	(beside["props"] as Array).append({"id": "crate_in_the_way", "shape": "box", "size_m": [0.3, 0.3, 0.3],
		"position_m": [float(craft[0]) + 0.2, float(craft[1]) + 0.05, float(craft[2]) * 0.8], "material": "crate"})
	error = HubRoomSpec.parse(JSON.stringify(beside)).error
	return "" if error.contains("crate_in_the_way") else "a crate within the clearance gave: \"%s\"" % error


func test_too_many_or_bad_details_are_rejected() -> String:
	var data: Dictionary = _shipped()
	var piece: Dictionary = (data["details"] as Array)[0]
	while (data["details"] as Array).size() <= HubRoomSpec.MAX_DETAILS:
		(data["details"] as Array).append(piece.duplicate())
	var error: String = HubRoomSpec.parse(JSON.stringify(data)).error
	if not error.contains("\"details\" has"):
		return "%d details gave: \"%s\"" % [(data["details"] as Array).size(), error]
	var bad: Dictionary = _shipped()
	(bad["details"] as Array)[2]["material"] = "gold"
	error = HubRoomSpec.parse(JSON.stringify(bad)).error
	return "" if error.begins_with("details[2]") else "an unknown material gave: \"%s\"" % error


func test_a_segment_meets_a_box_only_where_it_crosses() -> String:
	var half: Vector3 = Vector3(0.5, 0.5, 0.5)
	var cases: Array[Array] = [
		[Vector3(-2, 0, 0), Vector3(2, 0, 0), true],
		[Vector3(-2, 0.6, 0), Vector3(2, 0.6, 0), false],
		[Vector3(-2, 0, 0), Vector3(-0.6, 0, 0), false],
		[Vector3(0, 0, 0), Vector3(0, 0, 0.1), true],
		[Vector3(-2, -2, 0), Vector3(2, 2, 0), true],
		[Vector3(-2, 0, 2), Vector3(2, 0, 2), false],
	]
	for each: Array in cases:
		if HubRoomSight.segment_hits_box(each[0], each[1], half) != each[2]:
			return "%s to %s: expected %s" % [each[0], each[1], each[2]]
	return ""
