extends RefCounted

## Bevelled box edges (#1323, GFX-2, #609): every edge where two walls of a
## box meet is cut by a 45 degree strip lying on both walls, facing into the
## box, never across an opening, drawn in the wall material with a dim glow in
## place of the old glowing edge strips.

const SeedSweep := preload("res://tests/seed_sweep.gd")

const WIDTH: float = 0.3
const EPSILON: float = 1e-3


func _union(boxes: Array[BoxBounds]) -> BoxUnion:
	return BoxUnion.new(boxes)


func _on_a_wall(point: Vector3, walls: Array[Dictionary]) -> bool:
	for wall: Dictionary in walls:
		if (point.clamp(wall["min"], wall["max"]) - point).length() < EPSILON:
			return true
	return false


func _inside_another(union: BoxUnion, index: int, point: Vector3) -> bool:
	for other_index: int in union.boxes.size():
		var other: BoxBounds = union.boxes[other_index]
		if other_index == index:
			continue
		var inside: bool = true
		for axis: int in 3:
			inside = inside and point[axis] > other.min_corner[axis] + EPSILON and point[axis] < other.max_corner[axis] - EPSILON
		if inside:
			return true
	return false


func test_one_box_gets_twelve_bevels_on_its_walls_facing_in() -> String:
	var union: BoxUnion = _union([BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))])
	var walls: Array[Dictionary] = LevelFaces.quads(union)
	var bevels: Array[Dictionary] = LevelBevels.quads(union, walls, WIDTH)
	if bevels.size() != 12:
		return "%d bevels for one box, expected 12" % bevels.size()
	for bevel: Dictionary in bevels:
		var normal: Vector3 = bevel["normal"]
		var corners: Array = bevel["corners"]
		var middle: Vector3 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
		if middle.dot(normal) >= 0.0:
			return "the bevel at %s faces out of the box" % middle
		var tilted: int = 0
		for axis: int in 3:
			tilted += 1 if is_equal_approx(absf(normal[axis]), sqrt(0.5)) else 0
		if tilted != 2:
			return "the bevel at %s is not at 45 degrees: %s" % [middle, normal]
		for corner: Vector3 in corners:
			if not _on_a_wall(corner, walls):
				return "a bevel corner at %s lies off the walls" % corner
		if not is_equal_approx(((corners[0] as Vector3) - (corners[1] as Vector3)).length(), WIDTH * sqrt(2.0)):
			return "the bevel at %s is not %s m on each wall" % [middle, WIDTH]
		var drawn: Array[Vector3] = LevelBevels.triangles(bevel)
		for start: int in [0, 3]:
			var a: Vector3 = drawn[start]
			# The side Godot draws a triangle from, as in `test_level_view`.
			if (drawn[start + 2] - a).cross(drawn[start + 1] - a).dot(normal) <= 0.0:
				return "the bevel at %s is drawn facing out" % middle
	return ""


func test_a_small_box_keeps_its_walls() -> String:
	var union: BoxUnion = _union([BoxBounds.new(Vector3.ZERO, Vector3(0.4, 4, 4))])
	for bevel: Dictionary in LevelBevels.quads(union, LevelFaces.quads(union), WIDTH):
		var corners: Array = bevel["corners"]
		var normal: Vector3 = bevel["normal"]
		var cut: float = ((corners[0] as Vector3) - (corners[1] as Vector3)).length() / sqrt(2.0)
		var limit: float = 0.1 if normal.x != 0.0 else WIDTH
		if cut > limit + EPSILON:
			return "a bevel facing %s cuts %.2f m into a 0.4 m box" % [normal, cut]
	return ""


func test_a_bevel_stops_at_an_opening() -> String:
	# A tunnel joins the room's x = 0 wall at floor level, 4 m wide.
	var union: BoxUnion = _union([BoxBounds.new(Vector3.ZERO, Vector3(10, 8, 10)),
		BoxBounds.new(Vector3(-6, 0, 3), Vector3(1, 4, 7))])
	var stretches: Array[Vector2] = []
	for bevel: Dictionary in LevelBevels.quads(union, LevelFaces.quads(union), WIDTH):
		if bevel["box"] == 0 and (bevel["normal"] as Vector3).is_equal_approx(Vector3(1, 1, 0).normalized()):
			var corners: Array = bevel["corners"]
			stretches.append(Vector2(minf(corners[0].z, corners[2].z), maxf(corners[0].z, corners[2].z)))
	stretches.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	if stretches.size() != 2 or not stretches[0].is_equal_approx(Vector2(0, 3)) or not stretches[1].is_equal_approx(Vector2(7, 10)):
		return "the room's floor edge under the mouth is bevelled along %s, expected 0..3 and 7..10" % [stretches]
	return ""


func test_no_bevel_in_the_shipped_levels_leaves_the_walls_or_crosses_an_opening() -> String:
	var unions: Array[BoxUnion] = [LevelDef.parse_json(FileAccess.get_file_as_string("res://data/levels/g2_level.json")).union]
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	for level_seed: int in [1, 2, 12345]:
		unions.append(MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT).union)
	for union: BoxUnion in unions:
		var walls: Array[Dictionary] = LevelFaces.quads(union)
		var bevels: Array[Dictionary] = LevelBevels.quads(union, walls, WIDTH)
		if bevels.is_empty():
			return "a level got no bevels"
		for bevel: Dictionary in bevels:
			var corners: Array = bevel["corners"]
			for corner: Vector3 in corners:
				if not _on_a_wall(corner, walls):
					return "a bevel corner at %s lies off the walls" % corner
			for share: float in [0.02, 0.5, 0.98]:
				var on_first: Vector3 = (corners[0] as Vector3).lerp(corners[3], share)
				var on_second: Vector3 = (corners[1] as Vector3).lerp(corners[2], share)
				if _inside_another(union, bevel["box"], on_first) or _inside_another(union, bevel["box"], on_second):
					return "the bevel of box %d near %s crosses an opening" % [bevel["box"], on_first]
	return ""


func test_the_level_view_draws_bevels_in_the_wall_material_with_a_dim_glow() -> String:
	var view: LevelView = LevelView.new()
	view.build(_union([BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]))
	var node: MeshInstance3D = view.bevels_of(0)
	var look: Dictionary = view.look()
	var result: String = ""
	var material: ShaderMaterial = node.mesh.surface_get_material(0) as ShaderMaterial
	var vertices: int = (node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# The box's guide light strips share the bevels' surface (#1463).
	var strips: int = view.guide_lights.strips_of(0).size()
	if node.mesh.get_surface_count() != 1 or vertices != (view.bevels().size() + strips) * 6:
		result = "the bevels are %d surfaces and %d vertices for %d bevels and %d strips" % [
			node.mesh.get_surface_count(), vertices, view.bevels().size(), strips]
	elif material.shader.resource_path != LevelLook.WALL_SHADER or material.get_shader_parameter("tint") != look["wall_color"]:
		result = "the bevels are not drawn in the wall material"
	elif not (material.get_shader_parameter("glow") as Color).is_equal_approx((look["edge_color"] as Color) * float(look["edge_energy"])):
		result = "the bevels glow %s, not the look's edge colour at its energy" % material.get_shader_parameter("glow")
	elif view.get_node_or_null("Edges") != null:
		result = "the old edge strips are still drawn"
	view.free()
	return result
