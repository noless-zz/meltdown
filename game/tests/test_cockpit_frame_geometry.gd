extends RefCounted

## The built cockpit frame (CMF-1, ARC-3, CMF-6): every preset's frame and the
## range extremes stay between the camera's near plane and the ship's hull, the
## frame is primitive meshes without collision, and switching preset swaps it
## without touching a simulation. The file data and its checks are in
## `test_cockpit_frame.gd`, whose fixtures these tests share.

const FrameTests := preload("res://tests/test_cockpit_frame.gd")


func test_every_preset_frame_lies_between_near_plane_and_hull() -> String:
	for number: int in range(1, 5):
		var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(number))
		var span: Vector2 = FrameTests.distance_range(frame)
		var parts: int = frame.get_child_count()
		frame.free()
		if parts == 0:
			return "preset %d built nothing" % number
		if span.x < FrameTests.MIN_DISTANCE_M or span.y > FrameTests.MAX_DISTANCE_M:
			return "preset %d spans %.3f..%.3f m" % [number, span.x, span.y]
	return ""


func test_range_extremes_stay_between_near_plane_and_hull() -> String:
	for extreme: int in 2:
		var data: Dictionary = FrameTests.valid_data()
		for key: String in CockpitSpec.KEYS:
			data[key] = CockpitSpec.RANGES[key][extreme]
		var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
		if spec.error != "":
			return "extreme %d rejected: %s" % [extreme, spec.error]
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var span: Vector2 = FrameTests.distance_range(frame)
		frame.free()
		if span.x < FrameTests.MIN_DISTANCE_M or span.y > FrameTests.MAX_DISTANCE_M:
			return "extreme %d spans %.3f..%.3f m" % [extreme, span.x, span.y]
	return ""


## The closest geometry a valid file can build: the frame as near as allowed,
## the largest shapes at their nearest, and the narrowest window so every
## shape is built. Neither all-minimum nor all-maximum covers this combination.
func test_nearest_valid_frame_stays_beyond_near_plane() -> String:
	var data: Dictionary = FrameTests.valid_data()
	for key: String in ["window_half_angle_h_deg", "window_half_angle_v_deg", "frame_distance_m",
			"ledge_top_deg", "ledge_distance_m", "pillar_distance_m", "rim_distance_m", "part_depth_m"]:
		data[key] = CockpitSpec.RANGES[key][0]
	for key: String in ["ledge_height_deg", "ledge_half_width_deg", "pillar_width_deg", "rim_height_deg"]:
		data[key] = CockpitSpec.RANGES[key][1]
	data["glass_transmission"] = CockpitSpec.MIN_GLASS_TRANSMISSION
	var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
	if spec.error != "":
		return "nearest combination rejected: %s" % spec.error
	var frame: CockpitFrame = CockpitFrame.new(spec)
	var shapes: int = frame.instance_count("Ledge") * frame.instance_count("Pillars") \
		* frame.instance_count("Rim")
	var span: Vector2 = FrameTests.distance_range(frame)
	frame.free()
	if shapes == 0:
		return "a 10 degree window did not build every shape"
	if span.x < FrameTests.MIN_DISTANCE_M or span.y > FrameTests.MAX_DISTANCE_M:
		return "nearest combination spans %.3f..%.3f m" % [span.x, span.y]
	return ""


## Primitive meshes, except the glass: one mesh built in code, never a file.
func test_frame_is_primitive_meshes_without_collision() -> String:
	var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(1))
	var message: String = ""
	for child: Node in frame.find_children("*", "", true, false):
		if child is CollisionObject3D or child is CollisionShape3D:
			message = "%s is a collision node" % child.name
		elif child is OmniLight3D and child.name == CockpitMaterials.LIGHT_NAME:
			# The frame's own dim light (#659); `test_cockpit_look.gd` checks it.
			continue
		elif not child is MultiMeshInstance3D:
			message = "%s is a %s" % [child.name, child.get_class()]
		else:
			var mesh: Mesh = (child as MultiMeshInstance3D).multimesh.mesh
			var built_glass: bool = child.name == "Glass" and mesh is ArrayMesh and mesh.resource_path == ""
			if not mesh is PrimitiveMesh and not built_glass:
				message = "%s is not a primitive mesh" % child.name
	for part_name: String in CockpitFrame.PARTS:
		if frame.instance_count(part_name) == 0:
			message = "preset 1 has no %s" % part_name
	frame.free()
	return message


## Preset 4 is the minimal glass canopy: shell and glass, no shapes.
func test_glass_canopy_builds_no_shapes() -> String:
	var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(4))
	var message: String = ""
	for part_name: String in ["Ledge", "Pillars", "Rim"]:
		if frame.part(part_name) != null:
			message = "preset 4 has a %s" % part_name
	if frame.part("Glass") == null:
		message = "preset 4 has no glass"
	frame.free()
	return message


func test_full_transmission_builds_no_glass() -> String:
	var data: Dictionary = FrameTests.valid_data()
	data["glass_transmission"] = 1.0
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.parse_json(JSON.stringify(data)))
	var glass: MultiMeshInstance3D = frame.part("Glass")
	frame.free()
	return "" if glass == null else "a fully clear window still has glass"



func test_switching_preset_swaps_the_frame_without_touching_a_sim() -> String:
	var sim: Sim = Sim.new(7)
	var inputs: Array[ShipInput] = [ShipInput.new()]
	for i: int in 30:
		sim.step(inputs)
	var hash_before: int = sim.state_hash()
	var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(1))
	var solid_before: int = frame.instance_count("Solid")
	frame.set_spec(FrameTests.spec_for(4))
	var solid_after: int = frame.instance_count("Solid")
	var parts: Array[String] = []
	for child: Node in frame.get_children():
		parts.append(String(child.name))
	frame.free()
	if solid_after >= solid_before:
		return "solid panels %d before, %d after: the frame was not swapped" % [solid_before, solid_after]
	if parts != ["Solid", "Glass", CockpitMaterials.LIGHT_NAME]:
		return "parts %s after the swap; the old frame was not removed" % [parts]
	if sim.state_hash() != hash_before:
		return "switching the cockpit changed the simulation"
	return ""
