extends RefCounted

## The inside of a box-union level drawn as walls (GEN-5, LGT-1, ARC-4): no
## wall across an opening, each face's wall is exactly the face minus its
## overlaps, every quad faces into its box, rebuilding replaces, the look is
## data with a fallback, and the view adds no lights and reads no upper layer.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SCRIPT_PATHS: Array[String] = ["res://view/level_view.gd", "res://view/level_faces.gd",
	"res://view/level_faces_frames.gd", "res://view/level_faces_bevels.gd",
	"res://view/level_look.gd", "res://view/headlight.gd"]
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
const EPSILON: float = 1e-3


func _g2() -> BoxUnion:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))
	return level.union


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


func _centre(quad: Dictionary) -> Vector3:
	return ((quad["min"] as Vector3) + (quad["max"] as Vector3)) * 0.5


func _strictly_inside(box: BoxBounds, point: Vector3) -> bool:
	for axis: int in 3:
		if point[axis] <= box.min_corner[axis] or point[axis] >= box.max_corner[axis]:
			return false
	return true


## Rectangle in a face's (u, v) plane covered by `other`, or a zero-size rect.
func _cover(box: BoxBounds, other: BoxBounds, axis: int, plane: float) -> Rect2:
	if not (other.min_corner[axis] < plane and plane < other.max_corner[axis]):
		return Rect2()
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector2 = Vector2(maxf(box.min_corner[u], other.min_corner[u]), maxf(box.min_corner[v], other.min_corner[v]))
	var high: Vector2 = Vector2(minf(box.max_corner[u], other.max_corner[u]), minf(box.max_corner[v], other.max_corner[v]))
	if high.x <= low.x or high.y <= low.y:
		return Rect2()
	return Rect2(low, high - low)


## Area of the union of `rects`, by inclusion and exclusion over every subset,
## independent of how `LevelFaces` cuts the face.
func _union_area(rects: Array[Rect2]) -> float:
	var total: float = 0.0
	for mask: int in range(1, 1 << rects.size()):
		var common: Rect2 = Rect2()
		var first: bool = true
		var count: int = 0
		for index: int in rects.size():
			if mask & (1 << index) == 0:
				continue
			count += 1
			common = rects[index] if first else common.intersection(rects[index])
			first = false
		var sign: float = 1.0 if count % 2 == 1 else -1.0
		total += sign * common.get_area()
	return total


func test_no_wall_lies_across_an_opening() -> String:
	var union: BoxUnion = _g2()
	var view: LevelView = LevelView.new()
	view.build(union)
	var result: String = ""
	if view.quads().is_empty():
		result = "no quads built for the G2 level"
	for quad: Dictionary in view.quads():
		for index: int in union.boxes.size():
			if result == "" and index != quad["box"] and _strictly_inside(union.boxes[index], _centre(quad)):
				result = "quad of box %d centred at %s lies inside box %d" % [quad["box"], _centre(quad), index]
	view.free()
	return result


func test_each_face_is_its_area_minus_the_overlaps() -> String:
	var union: BoxUnion = _g2()
	var quads: Array[Dictionary] = LevelFaces.quads(union)
	var overlapped: int = 0
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		for axis: int in 3:
			for facing: float in [1.0, -1.0]:
				var plane: float = box.min_corner[axis] if facing > 0.0 else box.max_corner[axis]
				var size: Vector3 = box.max_corner - box.min_corner
				var face_area: float = size[(axis + 1) % 3] * size[(axis + 2) % 3]
				var covers: Array[Rect2] = []
				for other_index: int in union.boxes.size():
					var cover: Rect2 = _cover(box, union.boxes[other_index], axis, plane)
					if other_index != index and cover.has_area():
						covers.append(cover)
				var want: float = face_area - _union_area(covers)
				if not covers.is_empty():
					overlapped += 1
				var got: float = 0.0
				for quad: Dictionary in quads:
					if quad["box"] == index and quad["axis"] == axis and (quad["normal"] as Vector3)[axis] == facing:
						got += LevelFaces.area(quad)
				if absf(got - want) > EPSILON:
					return "box %d axis %d facing %s: wall area %s, expected %s" % [index, axis, facing, got, want]
	if overlapped < 5:
		return "only %d faces had an opening; the level has five joins" % overlapped
	return ""


func test_every_quad_faces_into_its_box() -> String:
	var union: BoxUnion = _g2()
	var view: LevelView = LevelView.new()
	view.build(union)
	var result: String = ""
	for quad: Dictionary in view.quads():
		var box: BoxBounds = union.boxes[quad["box"]]
		var inward: Vector3 = (box.min_corner + box.max_corner) * 0.5 - _centre(quad)
		if inward.dot(quad["normal"]) <= 0.0:
			result = "quad of box %d at %s faces out of its box" % [quad["box"], _centre(quad)]
			break
		var corners: Array[Vector3] = LevelView.triangles(quad)
		for start: int in [0, 3]:
			# The normal Godot gives a triangle from its winding (as SurfaceTool's
			# generate_normals does): the side it is drawn from.
			var a: Vector3 = corners[start]
			var drawn: Vector3 = (corners[start + 2] - a).cross(corners[start + 1] - a)
			if result == "" and drawn.dot(quad["normal"]) <= 0.0:
				result = "quad of box %d at %s is drawn facing out" % [quad["box"], _centre(quad)]
	var walls: MeshInstance3D = view.get_node(LevelView.WALLS_NAME)
	var vertex_count: int = 0
	for surface: int in walls.mesh.get_surface_count():
		vertex_count += (walls.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# Opening frames are drawn in the walls' surfaces (#1323).
	var drawn_quads: int = view.quads().size() + view.frames().size()
	if result == "" and vertex_count != drawn_quads * 6:
		result = "wall mesh has %d vertices for %d quads and frames" % [vertex_count, drawn_quads]
	view.free()
	return result


func test_a_single_box_gives_six_whole_faces() -> String:
	var union: BoxUnion = _one_box()
	var quads: Array[Dictionary] = LevelFaces.quads(union)
	if quads.size() != 6:
		return "%d quads for one box, expected 6" % quads.size()
	var total: float = 0.0
	for quad: Dictionary in quads:
		total += LevelFaces.area(quad)
	# 2 * (4*6 + 6*8 + 4*8)
	if absf(total - 208.0) > EPSILON:
		return "one box's walls cover %s m², expected 208" % total
	var view: LevelView = LevelView.new()
	view.build(union)
	var bevels: int = view.bevels().size()
	var frames: int = view.frames().size()
	view.free()
	if bevels != 12:
		return "%d bevels for one box, expected 12 (one per edge)" % bevels
	if frames != 0:
		return "%d frame quads for one box with no opening" % frames
	return ""


func test_rebuilding_replaces_the_walls() -> String:
	var view: LevelView = LevelView.new()
	view.build(_g2())
	var children: int = view.get_child_count()
	var quads: int = view.quads().size()
	view.build(_g2())
	var result: String = ""
	if view.get_child_count() != children or view.quads().size() != quads:
		result = "second build has %d children and %d quads, first had %d and %d" % [
				view.get_child_count(), view.quads().size(), children, quads]
	view.build(_one_box())
	if result == "" and (view.quads().size() != 6 or view.get_child_count() != children):
		result = "building one box after G2 left %d quads and %d children" % [view.quads().size(), view.get_child_count()]
	view.free()
	return result


func test_the_look_is_dark_dim_and_adds_no_lights() -> String:
	var view: LevelView = LevelView.new()
	var result: String = ""
	if view.look_error != "":
		result = "shipped look rejected: %s" % view.look_error
	view.build(_g2())
	for child: Node in view.find_children("*", "Light3D", true, false):
		result = "the level view adds a light: %s" % child.name
	var wall_mesh: Mesh = (view.get_node(LevelView.WALLS_NAME) as MeshInstance3D).mesh
	var bevels: ShaderMaterial = (view.get_node(LevelView.BEVELS_NAME) as MeshInstance3D).mesh.surface_get_material(0)
	for surface: int in wall_mesh.get_surface_count():
		var material: ShaderMaterial = wall_mesh.surface_get_material(surface) as ShaderMaterial
		var glow: Variant = material.get_shader_parameter("glow")
		# Walls are lit, never glowing: only the bevels may emit.
		if result == "" and (material.shader.code.contains("unshaded") or (glow != null and (glow as Color).get_luminance() > 0.0)):
			result = "walls glow or ignore light; only the bevels may"
	var bevel_glow: Color = bevels.get_shader_parameter("glow")
	if result == "" and (bevel_glow.get_luminance() <= 0.0 or bevel_glow.r > 1.0 or bevel_glow.g > 1.0 or bevel_glow.b > 1.0):
		result = "bevels are not dimly emissive (glow %s)" % bevel_glow
	var world: WorldEnvironment = view.get_node(LevelView.ENVIRONMENT_NAME) as WorldEnvironment
	if result == "" and world.environment.ambient_light_energy > 0.3:
		result = "ambient light %s is not dark (LGT-1)" % world.environment.ambient_light_energy
	view.free()
	return result


func test_a_bad_or_missing_look_falls_back_naming_the_field() -> String:
	var good: Dictionary = {"wall_color": [0.1, 0.1, 0.1], "roughness": 0.5, "edge_color": [0.2, 0.3, 0.4],
			"edge_energy": 0.3, "edge_width_m": 0.1, "floor_color": [0.2, 0.2, 0.2],
			"ceiling_color": [0.05, 0.05, 0.05], "grid_spacing_m": 2.0, "grid_line_width_m": 0.05,
			"grid_line_factor": 2.0, "fog_color": [0.0, 0.0, 0.0], "fog_density": 0.03,
			"ambient_color": [0.2, 0.2, 0.2], "ambient_energy": 0.1,
			"plate_floor_m": 1.0, "plate_wall_m": 1.0, "plate_ceiling_m": 1.0,
			"plate_floor_aspect": 1.0, "plate_wall_aspect": 2.0, "plate_ceiling_aspect": 3.0,
			"plate_floor_stagger": 0.0, "plate_wall_stagger": 0.5, "plate_ceiling_stagger": 0.0,
			"plate_seam_m": 0.02, "plate_contrast": 0.1, "frame_depth_m": 0.5, "frame_width_m": 0.2}
	if LevelView.parse_look(JSON.stringify(good)).has("error"):
		return "a valid look was rejected: %s" % LevelView.parse_look(JSON.stringify(good))["error"]
	var cases: Dictionary[String, Variant] = {
		"edge_energy": 2.0, "roughness": true, "edge_width_m": 0.0, "wall_color": [0.1, 0.1], "edge_color": [0.1, 2.0, 0.1],
		"frame_depth_m": 2.0, "frame_width_m": 0.6,
	}
	for key: String in cases:
		var bad: Dictionary = good.duplicate()
		bad[key] = cases[key]
		var parsed: Dictionary = LevelView.parse_look(JSON.stringify(bad))
		if not parsed.has("error") or not String(parsed["error"]).contains(key):
			return "bad %s gave %s" % [key, parsed]
	var extra: Dictionary = good.duplicate()
	extra["glow"] = 1.0
	if not String(LevelView.parse_look(JSON.stringify(extra)).get("error", "")).contains("glow"):
		return "an unknown key was not named"
	var view: LevelView = LevelView.new()
	var error: String = view.load_look("res://view/no_such_level_look.json")
	var fell_back: bool = view.look() == LevelView.FALLBACK_LOOK
	view.build(_one_box())
	var built: int = view.quads().size()
	view.free()
	if error == "" or not fell_back:
		return "a missing look file did not fall back (error \"%s\")" % error
	if built != 6:
		return "the fallback look did not build"
	return ""


func test_reads_no_layer_above_core() -> String:
	for path: String in SCRIPT_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		for root: String in OUTSIDE_DIRS:
			for file: String in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
				if not file.ends_with(".gd"):
					continue
				var head: String = FileAccess.get_file_as_string("%s/%s" % [root, file]).get_slice("\n", 0)
				if head.begins_with("class_name "):
					var class_id: String = head.trim_prefix("class_name ").strip_edges()
					var found: RegEx = RegEx.create_from_string("\\b%s\\b" % class_id)
					if found.search(source) != null:
						return "%s references %s from %s" % [path, class_id, root]
	return ""
