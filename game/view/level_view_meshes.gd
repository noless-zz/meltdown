class_name LevelViewMeshes
extends RefCounted

## The meshes `LevelView` draws a box with, kept apart so the node stays small:
## the box's walls and opening frames in one surface, and its bevels in one
## surface (#1323, #1364): two draw calls a box. The walls' material carries
## the floor, wall and ceiling tints and the shader picks one per face from its
## normal (#1383), so the kinds no longer need a surface each.
## With an `AmbientBake` each vertex also carries its box's ambient in CUSTOM0
## (#1400), and walls near an opening are cut into pieces for the blend to show
## on: more triangles, the same surfaces.

## CUSTOM0 holds the baked ambient as three floats: 8-bit vertex colour would
## band at ambient's dim values.
const AMBIENT_FORMAT: int = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


## The material of a box's walls and frames: `LevelLookMaterials.wall_material` in the
## wall tint, with the floor and ceiling tints for the shader to pick by face.
## The tints stay in `level_look.json` (ARC-4).
static func kind_material(look: Dictionary, surface: Dictionary = {}) -> ShaderMaterial:
	var material: ShaderMaterial = LevelLookMaterials.wall_material(look, look["wall_color"], surface)
	material.set_shader_parameter("tint_by_kind", true)
	material.set_shader_parameter("floor_tint", look["floor_color"])
	material.set_shader_parameter("ceiling_tint", look["ceiling_color"])
	return material


## Switches `material` to the ambient baked into the vertices.
static func use_bake(material: ShaderMaterial) -> ShaderMaterial:
	material.set_shader_parameter("baked_ambient", true)
	return material


## The quads `walls` draws for `list`: as given, or cut into pieces by `bake`.
static func drawn_quads(list: Array, bake: AmbientBake) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quad: Dictionary in list:
		if bake == null:
			result.append(quad)
		else:
			result.append_array(bake.pieces(quad))
	return result


## Puts box `box`'s walls and frames (`quads`) and its `bevels` under `box`,
## baked by `bake` when not null. Its guide light `strips` (#1463) go in the
## bevels' surface, glowing `strip_color`. Returns how many wall pieces were drawn.
static func add_box(box: Node3D, quads: Array, edge_bevels: Array, wall_material: Material,
		bevel_material: Material, bake: AmbientBake, strips: Array[Dictionary] = [],
		strip_color: Color = Color.BLACK) -> int:
	var pieces: int = 0
	if not quads.is_empty():
		# Floor, wall and ceiling, and the opening frames, in one surface: the
		# shader tints each face by its normal (#1383).
		var lists: Array[Array] = [quads]
		var used: Array[Material] = [wall_material]
		var node: MeshInstance3D = walls(LevelView.WALLS_NAME, lists, used, bake)
		# Walls block the headlight (the one shadow-casting light, GFX-4), so it
		# cannot shine through a wall into the next room.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		box.add_child(node)
		pieces = (node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 6 \
				if node.mesh != null else 0
	if not edge_bevels.is_empty() or not strips.is_empty():
		var typed: Array[Dictionary] = []
		typed.assign(edge_bevels)
		box.add_child(bevels(typed, bevel_material, bake, strips, strip_color))
	return pieces


## One mesh with a surface per list in `lists`, drawn in the matching material.
static func walls(node_name: String, lists: Array[Array], materials: Array[Material],
		bake: AmbientBake = null) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: ArrayMesh = ArrayMesh.new()
	for index: int in lists.size():
		var list: Array = lists[index]
		if list.is_empty():
			continue
		var vertices: PackedVector3Array = PackedVector3Array()
		var normals: PackedVector3Array = PackedVector3Array()
		var ambient: PackedFloat32Array = PackedFloat32Array()
		for quad: Dictionary in drawn_quads(list, bake):
			for corner: Vector3 in quad_triangles(quad):
				vertices.append(corner)
				normals.append(quad["normal"])
				if bake != null:
					_append_ambient(ambient, bake.at(corner, int(quad["box"])))
		_add_surface(mesh, vertices, normals, ambient)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[index])
	if mesh.get_surface_count() > 0:
		instance.mesh = mesh
	return instance


## One mesh of `bevels` in `material`, followed by the guide light `strips`
## in the same surface. The vertex colour is each strip's glow (`strip_color`)
## and black on the bevels; the shader scales it by `strip_energy`. The bevels
## cast no shadow: they sit in the corners, where the walls' own shadow falls.
static func bevels(bevels: Array[Dictionary], material: Material, bake: AmbientBake = null,
		strips: Array[Dictionary] = [], strip_color: Color = Color.BLACK) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = LevelView.BEVELS_NAME
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bevels.is_empty() and strips.is_empty():
		return instance
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var ambient: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var parts: Array[Dictionary] = bevels.duplicate()
	parts.append_array(strips)
	for index: int in parts.size():
		var part: Dictionary = parts[index]
		var is_strip: bool = index >= bevels.size()
		var corners: Array[Vector3] = GuideLightPlacement.triangles(part) if is_strip else LevelBevels.triangles(part)
		for corner: Vector3 in corners:
			vertices.append(corner)
			normals.append(part["normal"])
			colors.append(strip_color if is_strip else Color.BLACK)
			if bake != null:
				_append_ambient(ambient, bake.at(corner, int(part["box"])))
	var mesh: ArrayMesh = ArrayMesh.new()
	_add_surface(mesh, vertices, normals, ambient, colors)
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	return instance


static func _append_ambient(into: PackedFloat32Array, light: Color) -> void:
	into.append(light.r)
	into.append(light.g)
	into.append(light.b)


## One triangle surface; `ambient` (three floats a vertex) goes in CUSTOM0 and
## `colors` in the vertex colour when not empty.
static func _add_surface(mesh: ArrayMesh, vertices: PackedVector3Array, normals: PackedVector3Array,
		ambient: PackedFloat32Array, colors: PackedColorArray = PackedColorArray()) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if ambient.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return
	arrays[Mesh.ARRAY_CUSTOM0] = ambient
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, AMBIENT_FORMAT)


## The baked ambient of each vertex of surface `surface` of `mesh`, or empty without one.
static func baked(mesh: Mesh, surface: int = 0) -> PackedFloat32Array:
	if mesh == null or surface >= mesh.get_surface_count():
		return PackedFloat32Array()
	var custom: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_CUSTOM0]
	return custom if custom is PackedFloat32Array else PackedFloat32Array()


## The six corners of the two triangles that draw `quad`. Godot draws the
## side from which a triangle's corners run clockwise, so the order is picked
## to make that the side the quad's normal points to: into its box.
static func quad_triangles(quad: Dictionary) -> Array[Vector3]:
	var axis: int = quad["axis"]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector3 = quad["min"]
	var high: Vector3 = quad["max"]
	var c00: Vector3 = low
	var c10: Vector3 = low
	c10[u] = high[u]
	var c11: Vector3 = high
	var c01: Vector3 = low
	c01[v] = high[v]
	# Corners c00, c10, c11 run counter-clockwise seen from +axis.
	if float((quad["normal"] as Vector3)[axis]) > 0.0:
		return [c00, c11, c10, c00, c01, c11]
	return [c00, c10, c11, c00, c11, c01]
