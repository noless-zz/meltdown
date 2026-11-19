extends RefCounted

## The status panel draws over the cockpit frame and under the reset fade
## (#199): the solid shell of presets 1 and 2 is nearer than the panel, so
## without this the panel would be hidden on preset 1 and cut by the window
## edge on preset 2 (CMF-1, CMF-6, ARC-3).

const COCKPIT_DIR: String = "res://xr/cockpits"
const SHIPPED_COCKPITS: Array[String] = ["anchored.json", "guided.json", "glass.json", "open.json"]


## The render priorities of every material the panel draws with, by node name.
static func _panel_priorities(panel: StatusPanel) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in panel.get_children():
		if child is Label3D:
			result[String(child.name)] = (child as Label3D).render_priority
		elif child is MeshInstance3D:
			result[String(child.name)] = (child as MeshInstance3D).material_override.render_priority
	return result


## The highest render priority on any material of `frame`.
static func _highest_frame_priority(frame: CockpitFrame) -> int:
	var highest: int = Material.RENDER_PRIORITY_MIN
	for child: Node in frame.get_children():
		var instance: GeometryInstance3D = child as GeometryInstance3D
		if instance == null:
			continue
		var material: Material = instance.material_override
		while material != null:
			highest = maxi(highest, material.render_priority)
			material = material.next_pass
		var multimesh_node: MultiMeshInstance3D = instance as MultiMeshInstance3D
		if multimesh_node != null and multimesh_node.multimesh.mesh != null:
			var mesh: Mesh = multimesh_node.multimesh.mesh
			for surface: int in mesh.get_surface_count():
				var surface_material: Material = mesh.surface_get_material(surface)
				if surface_material != null:
					highest = maxi(highest, surface_material.render_priority)
	return highest


func test_every_label_and_bar_draws_without_depth_test() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var problems: Array[String] = []
	var drawn: int = 0
	for child: Node in panel.get_children():
		if child is Label3D:
			drawn += 1
			if not (child as Label3D).no_depth_test:
				problems.append(String(child.name))
		elif child is MeshInstance3D:
			drawn += 1
			var material: BaseMaterial3D = (child as MeshInstance3D).material_override as BaseMaterial3D
			if material == null or not material.no_depth_test:
				problems.append(String(child.name))
	panel.free()
	if drawn < 7:
		return "expected at least 7 labels and bars, found %d" % drawn
	if not problems.is_empty():
		return "depth test still on for %s" % [problems]
	return ""


func test_priority_sits_above_every_shipped_frame_and_below_the_fade() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var priorities: Dictionary = _panel_priorities(panel)
	panel.free()
	var fade: FadeOverlay = FadeOverlay.new()
	var fade_priority: int = fade.material_override.render_priority
	fade.free()
	var lowest: int = Material.RENDER_PRIORITY_MAX
	var highest: int = Material.RENDER_PRIORITY_MIN
	for value: int in priorities.values():
		lowest = mini(lowest, value)
		highest = maxi(highest, value)
	if highest >= fade_priority or highest >= Material.RENDER_PRIORITY_MAX:
		return "panel priority %d does not sit below the fade quad's %d" % [highest, fade_priority]
	for file: String in SHIPPED_COCKPITS:
		var spec: CockpitSpec = CockpitSpec.load_file(COCKPIT_DIR + "/" + file)
		if spec.error != "":
			return "%s: %s" % [file, spec.error]
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var frame_priority: int = _highest_frame_priority(frame)
		var parts: int = frame.get_child_count()
		frame.free()
		if parts == 0:
			return "%s built no parts, so the comparison means nothing" % file
		if lowest <= frame_priority:
			return "panel priority %d is not above %s's %d" % [lowest, file, frame_priority]
	return ""


func test_named_priority_lies_between_frame_and_fade() -> String:
	if StatusPanel.RENDER_PRIORITY <= 0:
		return "RENDER_PRIORITY %d is not above the frame's default 0" % StatusPanel.RENDER_PRIORITY
	if StatusPanel.RENDER_PRIORITY_TOP >= Material.RENDER_PRIORITY_MAX:
		return "RENDER_PRIORITY_TOP %d reaches the fade's priority" % StatusPanel.RENDER_PRIORITY_TOP
	return ""


func test_the_filled_bar_draws_over_its_track() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var priorities: Dictionary = _panel_priorities(panel)
	panel.free()
	if priorities[StatusPanel.ENERGY_BAR_NAME] <= priorities[StatusPanel.ENERGY_TRACK_NAME]:
		return "bar priority %d is not above its track's %d" % [
			priorities[StatusPanel.ENERGY_BAR_NAME], priorities[StatusPanel.ENERGY_TRACK_NAME]]
	return ""


## The panel sits where the look file says (#605 moved it there from code).
func test_the_panel_sits_where_the_look_file_says() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	var at: Transform3D = StatusPanel.rig_transform(Transform3D.IDENTITY)
	if not at.origin.is_equal_approx(look["position_m"]):
		return "the panel sits at %s, not the look's %s" % [at.origin, look["position_m"]]
	var tilt: float = rad_to_deg(Vector3.UP.angle_to(at.basis.y))
	if not is_equal_approx(snappedf(tilt, 0.01), snappedf(float(look["tilt_deg"]), 0.01)):
		return "the panel is tilted %.2f degrees, not the look's %.2f" % [tilt, look["tilt_deg"]]
	return ""
