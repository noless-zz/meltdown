extends RefCounted

## The `wall_depth_shown` check (#1323, GFX-2, PRF-2, DEV-6), lane-b's file
## under `acceptance/checks/`. In `suites/m6/effects.json` the `wall_depth`
## step flies m2's `bot_clears_g2_level` flight with screenshots where the
## ship faces a doorway at 8 to 12 m, then this check reads the level view in
## the main scene: openings are framed, box edges are bevelled, the old
## glowing edge strips are gone, and the frames cost no draw call of their
## own: a box draws its walls and frames in one surface (#1383). It reads the view only; the step's pinned hash holds the simulation
## (ARC-1, ARC-2). Whether walls look like they have mass stays human-checked
## in the headset.

const CHECK: String = "wall_depth_shown"
const OLD_EDGES_NAME: String = "Edges"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	var view: LevelView = main.get_node_or_null(LevelView.NODE_NAME) as LevelView if main != null else null
	return judge_view(view, measurements)


## [result, message] for `view`, adding what it draws to `measurements`.
static func judge_view(view: LevelView, measurements: Dictionary) -> Array:
	if view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no level"]
	# One node per box since #1364: each box's walls and frames, and its bevels.
	var wall_vertices: int = 0
	var bevel_vertices: int = 0
	var surfaces: int = 0
	var bevel_material: ShaderMaterial = null
	for box: int in view.box_count():
		var walls: MeshInstance3D = view.walls_of(box)
		var bevels: MeshInstance3D = view.bevels_of(box)
		if walls != null and walls.mesh != null:
			# Floor, wall and ceiling share one surface since #1383.
			if walls.mesh.get_surface_count() != 1:
				return [AcceptanceReport.RESULT_FAIL, "the walls of box %d take %d surfaces" % [box, walls.mesh.get_surface_count()]]
			surfaces += walls.mesh.get_surface_count()
			for surface: int in walls.mesh.get_surface_count():
				wall_vertices += (walls.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if bevels != null and bevels.mesh != null:
			if bevels.mesh.get_surface_count() != 1:
				return [AcceptanceReport.RESULT_FAIL, "the bevels of box %d take %d surfaces" % [box, bevels.mesh.get_surface_count()]]
			surfaces += 1
			bevel_vertices += (bevels.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			bevel_material = bevels.mesh.surface_get_material(0) as ShaderMaterial
	if wall_vertices == 0 or bevel_material == null:
		return [AcceptanceReport.RESULT_FAIL, "the level view draws no walls or no bevels"]
	measurements["wall_frame_quads"] = view.frames().size()
	measurements["wall_bevels"] = view.bevels().size()
	measurements["wall_triangles"] = (wall_vertices + bevel_vertices) / 3
	measurements["wall_surfaces"] = surfaces
	if view.frames().is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no opening is framed"]
	if view.bevels().is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no box edge is bevelled"]
	if view.get_node_or_null(OLD_EDGES_NAME) != null:
		return [AcceptanceReport.RESULT_FAIL, "the old glowing edge strips are still drawn"]
	if wall_vertices != (view.quads().size() + view.frames().size()) * 6:
		return [AcceptanceReport.RESULT_FAIL, "the frames are not drawn in the walls' surfaces"]
	var glow: Color = bevel_material.get_shader_parameter("glow")
	if glow.r > 1.0 or glow.g > 1.0 or glow.b > 1.0:
		return [AcceptanceReport.RESULT_FAIL, "the bevels glow %s, more than an outline" % glow]
	return [AcceptanceReport.RESULT_PASS, "%d frame quads and %d bevels, %d triangles in %d surfaces" \
			% [view.frames().size(), view.bevels().size(), measurements["wall_triangles"], measurements["wall_surfaces"]]]
