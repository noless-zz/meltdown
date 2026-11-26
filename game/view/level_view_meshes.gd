class_name LevelViewMeshes
extends RefCounted

## The meshes `LevelView` draws a box with, kept apart so the node stays small:
## the box's walls and opening frames in one surface, and its bevels in one
## surface (#1323, #1364): two draw calls a box. The walls' material carries
## the floor, wall and ceiling tints and the shader picks one per face from its
## normal (#1383), so the kinds no longer need a surface each.


## The material of a box's walls and frames: `LevelLook.wall_material` in the
## wall tint, with the floor and ceiling tints for the shader to pick by face.
## The tints stay in `level_look.json` (ARC-4).
static func kind_material(look: Dictionary, surface: Dictionary = {}) -> ShaderMaterial:
	var material: ShaderMaterial = LevelLook.wall_material(look, look["wall_color"], surface)
	material.set_shader_parameter("tint_by_kind", true)
	material.set_shader_parameter("floor_tint", look["floor_color"])
	material.set_shader_parameter("ceiling_tint", look["ceiling_color"])
	return material


## One mesh with a surface per list in `lists`, drawn in the matching material.
static func walls(node_name: String, lists: Array[Array], materials: Array[Material]) -> MeshInstance3D:
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
		for quad: Dictionary in list:
			for corner: Vector3 in LevelView.triangles(quad):
				vertices.append(corner)
				normals.append(quad["normal"])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[index])
	if mesh.get_surface_count() > 0:
		instance.mesh = mesh
	return instance


## One mesh of `bevels` in `material`. The bevels cast no shadow: they sit in
## the corners, where the walls' own shadow already falls.
static func bevels(bevels: Array[Dictionary], material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = LevelView.BEVELS_NAME
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bevels.is_empty():
		return instance
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for bevel: Dictionary in bevels:
		for corner: Vector3 in LevelBevels.triangles(bevel):
			vertices.append(corner)
			normals.append(bevel["normal"])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	return instance
