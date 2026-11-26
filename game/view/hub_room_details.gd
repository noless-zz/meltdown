class_name HubRoomDetails
extends RefCounted

## The hangar details of the home base room (#1397, CRW-2, GFX-2, PRF-4,
## ARC-4): the `details` list of `data/hub/room.json`, pieces in the same form
## as props (ribbed wall panels, floor markings, cable runs, the gantry over
## the ship, the tool rack and its tools, the shaft mouth). A room of loose
## pieces would spend a draw call on each, so every detail that shares a
## material is merged into one mesh, named `Detail_<material>`: the details
## cost one draw call per material however many pieces there are.
##
## The worn surface measures its edges and seams from each piece's own centre,
## size and faces, which merging loses; so each vertex carries them for
## `hub_room_detail.gdshader`: CUSTOM0 the position on the piece and 1 on a
## box, CUSTOM1 the piece's size, CUSTOM2 the normal on the piece.

const NAME_PREFIX: String = "Detail_"
const CUSTOM_FORMAT: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)


## One mesh per material used by `spec.details`, in the order the materials
## first appear, every one drawn on `layers` only.
static func build(spec: HubRoomSpec, layers: int) -> Array[MeshInstance3D]:
	var by_material: Dictionary[String, Array] = {}
	for piece: Dictionary in spec.details:
		if not by_material.has(piece["material"]):
			by_material[piece["material"]] = []
		by_material[piece["material"]].append(piece)
	var built: Array[MeshInstance3D] = []
	for material_name: String in by_material:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = NAME_PREFIX + material_name
		instance.mesh = merged(by_material[material_name])
		instance.material_override = HubRoomParts.material(spec.materials[material_name], true)
		instance.layers = layers
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # GFX-4: headlight shadows only.
		built.append(instance)
	return built


## Where `piece` ({"position": Vector3, "rotation": Vector3 in degrees}) stands in the room.
static func placed(piece: Dictionary) -> Transform3D:
	var rotation_rad: Vector3 = (piece["rotation"] as Vector3) * (PI / 180.0)
	return Transform3D(Basis.from_euler(rotation_rad), piece["position"])


## `pieces` as one triangle mesh in room space.
static func merged(pieces: Array) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged_arrays(pieces), [], {}, CUSTOM_FORMAT)
	return mesh


## The surface arrays of `merged`: vertices and normals in room space, and
## each vertex's piece values in the custom channels.
static func merged_arrays(pieces: Array) -> Array:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var on_piece: PackedFloat32Array = PackedFloat32Array()
	var sizes: PackedFloat32Array = PackedFloat32Array()
	var faces: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for piece: Dictionary in pieces:
		var size: Vector3 = piece["size"]
		var box: float = 1.0 if piece["shape"] == "box" else 0.0
		var arrays: Array = HubRoomParts.mesh(piece["shape"], size).get_mesh_arrays()
		var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var local_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var at: Transform3D = placed(piece)
		var first: int = vertices.size()
		for i: int in local_vertices.size():
			var v: Vector3 = local_vertices[i]
			var n: Vector3 = local_normals[i]
			vertices.append(at * v)
			normals.append(at.basis * n)
			on_piece.append_array([v.x, v.y, v.z, box])
			sizes.append_array([size.x, size.y, size.z, 0.0])
			faces.append_array([n.x, n.y, n.z, 0.0])
		var local_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if local_indices.is_empty():
			for i: int in local_vertices.size():
				indices.append(first + i)
		for index: int in local_indices:
			indices.append(first + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_CUSTOM0] = on_piece
	arrays[Mesh.ARRAY_CUSTOM1] = sizes
	arrays[Mesh.ARRAY_CUSTOM2] = faces
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
