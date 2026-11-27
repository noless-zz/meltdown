class_name CockpitFrame
extends Node3D

## The cockpit frame around the eye point, built from a `CockpitSpec` with
## code-built meshes only: no imported models, no collision (CMF-1, NAM-3).
##
## This node's origin is the eye point and -Z is straight ahead. The frame is
## a shell over the forward half of the view at `frame_distance_m`, solid
## outside the window in the interior colour, with one seamless sheet of
## tinted glass inside it. In front of the shell sit a few large shapes that
## make it read as a ship (#607): a dashboard ledge below the window, a canopy
## pillar on each side and a rim above. Every piece lies outside the window.
## Each part is one `MultiMeshInstance3D`, one draw call on the headset. Since
## #659 the opaque parts are lit and patterned (`CockpitMaterials`) and the
## frame carries its own dim light, so it shows in a dark mine. Since #1306
## the surfaces are physically based (`CockpitFinish`), the glass reflects
## faintly at its edge, and the file's dash pieces (`CockpitDashPiece`) sit on
## the ledge: boxes in one part, knobs in another.
##
## The frame reads only its spec. It never reads or writes simulation state
## (ARC-3, MP-2); a preset change rebuilds it and touches nothing else.

## Largest angle one shell panel or shape segment spans, degrees. Smaller
## pieces follow the curve more closely and cost more instances.
const CELL_DEG: float = 10.0
## Opaque pieces are drawn this much larger than their cell so neighbours
## overlap and no gap shows between them.
const OVERLAP: float = 1.05
## Nearest the shapes go to the poles, degrees: past it a yaw cell is too
## thin to place a piece in.
const MAX_SHAPE_PITCH_DEG: float = 80.0
## Every part a frame can build. Shapes with zero size are left out.
const PARTS: Array[String] = ["Solid", "Glass", "Ledge", "Pillars", "Rim", "Dash", "Knobs"]
## The parts that are boxes, or fill their unit box; the others are flat.
const BOX_PARTS: Array[String] = ["Ledge", "Pillars", "Rim", "Dash", "Knobs"]
## Sides of a dash knob: enough to read round at arm's length.
const KNOB_SIDES: int = 12

var spec: CockpitSpec = null
## Instance transforms of each built part, by part name. Kept here because a
## headless renderer does not store multimesh transforms for reading back.
var _transforms: Dictionary[String, Array] = {}
## The glass mesh's points, in this node's space, for the same reason.
var _glass_points: PackedVector3Array = []


func _init(p_spec: CockpitSpec = null) -> void:
	name = "CockpitFrame"
	if p_spec != null:
		set_spec(p_spec)


## Replaces the frame with one built from `p_spec`.
func set_spec(p_spec: CockpitSpec) -> void:
	spec = p_spec
	_transforms.clear()
	_glass_points = PackedVector3Array()
	for child: Node in get_children():
		if child is MapHologram:
			continue  # Mounted here by the pilot's choice (#1321), not part of the frame.
		remove_child(child)
		child.free()
	_build()


## The built part named `part_name` (one of `PARTS`), or null when this frame
## has none.
func part(part_name: String) -> MultiMeshInstance3D:
	return get_node_or_null(part_name) as MultiMeshInstance3D


## Number of instances in part `part_name`; 0 when it is missing.
func instance_count(part_name: String) -> int:
	return instance_transforms(part_name).size()


## Where each instance of part `part_name` sits, in this node's space.
func instance_transforms(part_name: String) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.assign(_transforms.get(part_name, []))
	return result


## The points of the glass mesh in this node's space; empty with no glass.
func glass_points() -> PackedVector3Array:
	return _glass_points


## Unit vector from the eye at `yaw` degrees right and `pitch` degrees up.
static func direction(yaw: float, pitch: float) -> Vector3:
	return CockpitGeometry.direction(yaw, pitch)


func _build() -> void:
	var h: float = spec.window_half_angle_h_deg
	var v: float = spec.window_half_angle_v_deg
	var yaw_breaks: PackedFloat32Array = _shell_breaks(h)
	var pitch_breaks: PackedFloat32Array = _shell_breaks(v)
	var solid: Array[Transform3D] = []
	for i: int in yaw_breaks.size() - 1:
		for j: int in pitch_breaks.size() - 1:
			var a: Vector2 = Vector2(yaw_breaks[i], pitch_breaks[j])
			var b: Vector2 = Vector2(yaw_breaks[i + 1], pitch_breaks[j + 1])
			var middle: Vector2 = (a + b) * 0.5
			if absf(middle.x) < h and absf(middle.y) < v:
				continue
			var panel: Transform3D = CockpitGeometry.cell_piece(a, b, spec.frame_distance_m, 0.0, OVERLAP)
			solid.append(_outside(panel, false, middle))
	_add_part("Solid", _quad(), _surface("Solid", spec.interior_color), solid)
	if spec.glass_opacity() > 0.0:
		_add_glass(CockpitGeometry.breaks(-h, h, CELL_DEG), CockpitGeometry.breaks(-v, v, CELL_DEG))
	_add_part("Ledge", _box(), _surface("Ledge", spec.structure_color), _ledge())
	_add_part("Pillars", _box(), _surface("Pillars", spec.structure_color), _pillars())
	_add_part("Rim", _box(), _surface("Rim", spec.structure_color), _rim())
	_add_dash("Dash", _box())
	_add_dash("Knobs", _knob())
	var light: OmniLight3D = CockpitMaterials.light(spec.look)
	if light != null:
		add_child(light)


## The patterned, lit surface of part `part_name` in colour `base` (#659).
func _surface(part_name: String, base: Color) -> ShaderMaterial:
	return CockpitMaterials.surface(part_name, base, spec.look, OVERLAP, spec.finish)


## The dash pieces built as part `part_name`, each with its tone and lamp.
func _add_dash(part_name: String, mesh: Mesh) -> void:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var lamps: Array[Color] = []
	for piece: CockpitDashPiece in spec.dash:
		if CockpitDashPiece.SHAPE_PART[piece.shape] != part_name:
			continue
		transforms.append(piece.placed())
		colors.append(Color(piece.tone, piece.tone, piece.tone))
		lamps.append(piece.lamp_color)
	var material: ShaderMaterial = CockpitMaterials.dash(part_name, spec.structure_color, spec.look, spec.finish)
	_add_part(part_name, mesh, material, transforms, colors, lamps)


## The pitch band the ledge covers, as (top, bottom) degrees below straight
## ahead; (0, 0) when there is no ledge. Its top never rises into the window.
func ledge_band() -> Vector2:
	var top: float = maxf(spec.ledge_top_deg, spec.window_half_angle_v_deg)
	var bottom: float = minf(top + spec.ledge_height_deg, MAX_SHAPE_PITCH_DEG)
	return Vector2(top, bottom) if spec.ledge_height_deg > 0.0 and bottom > top else Vector2.ZERO


## The pitch band the rim covers, as (bottom, top) degrees above straight
## ahead; (0, 0) when there is no rim.
func rim_band() -> Vector2:
	var bottom: float = spec.window_half_angle_v_deg
	var top: float = minf(bottom + spec.rim_height_deg, MAX_SHAPE_PITCH_DEG)
	return Vector2(bottom, top) if spec.rim_height_deg > 0.0 and top > bottom else Vector2.ZERO


## The yaw band each pillar covers, as (inner, outer) degrees from straight
## ahead; (0, 0) when there are no pillars.
func pillar_band() -> Vector2:
	var inner: float = spec.window_half_angle_h_deg
	var outer: float = minf(inner + spec.pillar_width_deg, 90.0)
	return Vector2(inner, outer) if spec.pillar_width_deg > 0.0 and outer > inner else Vector2.ZERO


func _ledge() -> Array[Transform3D]:
	var band: Vector2 = ledge_band()
	if band == Vector2.ZERO:
		return []
	var half: float = spec.ledge_half_width_deg
	return _row(CockpitGeometry.breaks(-half, half, CELL_DEG), Vector2(-band.y, -band.x),
		spec.ledge_distance_m, -1.0, band.x)


func _rim() -> Array[Transform3D]:
	var band: Vector2 = rim_band()
	if band == Vector2.ZERO:
		return []
	var half: float = spec.window_half_angle_h_deg
	if pillar_band() != Vector2.ZERO:
		half = pillar_band().y
	return _row(CockpitGeometry.breaks(-half, half, CELL_DEG), band, spec.rim_distance_m, 1.0, band.x)


## One box across `pitch_span` (low, high) for each yaw cell, kept beyond
## pitch `edge` on side `side`.
func _row(yaw_breaks: PackedFloat32Array, pitch_span: Vector2, distance: float, side: float,
		edge: float) -> Array[Transform3D]:
	var pieces: Array[Transform3D] = []
	for i: int in yaw_breaks.size() - 1:
		var box: Transform3D = CockpitGeometry.cell_piece(Vector2(yaw_breaks[i], pitch_span.x),
			Vector2(yaw_breaks[i + 1], pitch_span.y), distance, spec.part_depth_m, OVERLAP)
		pieces.append(CockpitGeometry.keep_out(box, true, CockpitGeometry.Edge.PITCH, side, edge))
	return pieces


## Each pillar runs from the bottom of the ledge to the top of the rim, so the
## shapes join into one frame round the window.
func _pillars() -> Array[Transform3D]:
	var band: Vector2 = pillar_band()
	if band == Vector2.ZERO:
		return []
	var v: float = spec.window_half_angle_v_deg
	var low: float = -minf(maxf(v, ledge_band().y), MAX_SHAPE_PITCH_DEG)
	var high: float = minf(maxf(v, rim_band().y), MAX_SHAPE_PITCH_DEG)
	var pitch_breaks: PackedFloat32Array = CockpitGeometry.breaks(low, high, CELL_DEG)
	var pieces: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for j: int in pitch_breaks.size() - 1:
			var a: Vector2 = Vector2(minf(side * band.x, side * band.y), pitch_breaks[j])
			var b: Vector2 = Vector2(maxf(side * band.x, side * band.y), pitch_breaks[j + 1])
			var box: Transform3D = CockpitGeometry.cell_piece(a, b, spec.pillar_distance_m, spec.part_depth_m, OVERLAP)
			pieces.append(CockpitGeometry.keep_out(box, true, CockpitGeometry.Edge.YAW, side, band.x))
	return pieces


## `piece` of the shell cell centred on `middle`, turned clear of the window
## edge it borders: a cell beside the window clears the side edge, any other
## clears the top or bottom edge.
func _outside(piece: Transform3D, deep: bool, middle: Vector2) -> Transform3D:
	if absf(middle.x) > spec.window_half_angle_h_deg:
		return CockpitGeometry.keep_out(piece, deep, CockpitGeometry.Edge.YAW, signf(middle.x), spec.window_half_angle_h_deg)
	return CockpitGeometry.keep_out(piece, deep, CockpitGeometry.Edge.PITCH, signf(middle.y), spec.window_half_angle_v_deg)


## Edges of the shell's cells along one axis, degrees from -90 to 90. The
## window's edges at -`half` and `half` are always among them, so every cell
## lies wholly inside or wholly outside the window.
static func _shell_breaks(half: float) -> PackedFloat32Array:
	var result: PackedFloat32Array = [-90.0]
	for span: Vector2 in [Vector2(-90.0, -half), Vector2(-half, half), Vector2(half, 90.0)]:
		if span.y - span.x <= 0.0:
			continue
		var edges: PackedFloat32Array = CockpitGeometry.breaks(span.x, span.y, CELL_DEG)
		result.append_array(edges.slice(1))
	return result


func _add_glass(yaw_breaks: PackedFloat32Array, pitch_breaks: PackedFloat32Array) -> void:
	_glass_points = CockpitGeometry.glass_points(yaw_breaks, pitch_breaks, spec.frame_distance_m)
	var tint: Color = spec.glass_tint
	tint.a = spec.glass_opacity()
	var single: Array[Transform3D] = [Transform3D.IDENTITY]
	var window: Vector2 = Vector2(spec.window_half_angle_h_deg, spec.window_half_angle_v_deg)
	_add_part("Glass", CockpitGeometry.glass_mesh(_glass_points, yaw_breaks.size()),
		CockpitMaterials.glass(tint, window, spec.finish), single)


## Adds part `part_name`; `colors` and `customs`, when given, are each
## instance's colour and custom data, as the dash uses them.
func _add_part(part_name: String, mesh: Mesh, material: Material, transforms: Array[Transform3D],
		colors: Array[Color] = [], customs: Array[Color] = []) -> void:
	if transforms.is_empty():
		return
	_transforms[part_name] = transforms
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.use_custom_data = not customs.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for k: int in transforms.size():
		multimesh.set_instance_transform(k, transforms[k])
		if multimesh.use_colors:
			multimesh.set_instance_color(k, colors[k])
		if multimesh.use_custom_data:
			multimesh.set_instance_custom_data(k, customs[k])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = part_name
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


static func _quad() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2.ONE
	return mesh


static func _box() -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh


static func _knob() -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = KNOB_SIDES
	mesh.rings = 0
	return mesh
