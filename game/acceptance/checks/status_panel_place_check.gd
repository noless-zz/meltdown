extends RefCounted

## The `status_panel_place` check (#1452, CMF-8, PLT-5, DEV-6), lane-c's file
## under `acceptance/checks/`. In `suites/m6/look.json`:
##
##     {"id": "status_panel_place", "checks": ["no_script_errors", "status_panel_place"]}
##
## On the scene's own cockpit frame and status panel it puts each of the four
## comfort presets' cockpit files on the frame in turn, places frame and panel
## as the game does (`RigViews.place_at`), and fails when the panel is not
## where the corner setting (`PanelCorner.current`, bottom left by default)
## puts it against the cockpit, when any drawn part lies outside either
## eye's view (#1507, `EyeViews`: the runtime's own projections on a headset,
## else `xr/eye_views.json`), when the panel's centre comes within
## `StatusPanelBounds.CENTRAL_CONE_DEG` of straight ahead, or any drawn row
## within `StatusPanelBounds.ROW_CONE_DEG`. In the suite it runs after 300
## ticks of turning, rolling flight, so the frame is where flight left it. It saves
## `<step id>_preset<n>.png` under `m6/` for each preset. The frame's file and
## both transforms are put back afterwards; nothing is saved.

const CHECK: String = "status_panel_place"
const RIG_PATH: NodePath = ^"XRRig"
const PANEL_PROPERTY: String = "status_panel"
const SHOT_FOLDER: String = "m6"
## How far the panel may sit from its place against the cockpit.
const PLACE_TOLERANCE_M: float = 0.002


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	var panel: StatusPanel = main.get(PANEL_PROPERTY) as StatusPanel if main != null else null
	var frame: CockpitFrame = MapPlacement.cockpit_frame(main.get_node_or_null(RIG_PATH) if main != null else null)
	if panel == null or frame == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no status panel or no cockpit frame"]
	var views: EyeViews = EyeViews.from_interface(XRServer.primary_interface, EyeViews.load_file().margin_deg)
	return judge_presets(panel, frame, measurements,
		func(number: int) -> String: return _shot(runner, "%s_preset%d.png" % [step.id, number]), views)


## The verdict for `panel` and `frame`; `shoot` takes the preset number and
## returns the screenshot's path or why none was taken. `views` are the eyes
## to judge by; null reads `xr/eye_views.json`.
static func judge_presets(panel: StatusPanel, frame: CockpitFrame, measurements: Dictionary,
		shoot: Callable, views: EyeViews = null) -> Array:
	if views == null:
		views = EyeViews.load_file()
	measurements["eye_views"] = views.values
	var saved: Array = [frame.spec, frame.transform, panel.transform]
	var corner: String = PanelCorner.current
	var placement: Transform3D = StatusPanelLook.placement(StatusPanelLook.shared(), corner)
	var points: Array[Vector3] = StatusPanelBounds.drawn_points(panel)
	var at: Transform3D = frame.transform
	var problem: String = ""
	var shots: Array[String] = []
	measurements["panel_corner"] = corner
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		frame.set_spec(CockpitSpec.for_preset(ComfortPresetFiles.load_number(number)))
		RigViews.place_at(at, frame, panel)
		var against: Transform3D = frame.transform.affine_inverse() * panel.transform
		var off_m: float = against.origin.distance_to(placement.origin)
		var angles: Vector2 = StatusPanelBounds.angles(points, panel.transform, frame.transform)
		measurements["preset%d_panel_m" % number] = [snappedf(against.origin.x, 0.001),
			snappedf(against.origin.y, 0.001), snappedf(against.origin.z, 0.001)]
		var centre: float = StatusPanelBounds.centre_angle(panel.transform, frame.transform)
		var eyes: String = StatusPanelBounds.eyes_problem(points, panel.transform, frame.transform, views)
		measurements["preset%d_nearest_deg" % number] = snappedf(angles.x, 0.1)
		measurements["preset%d_centre_deg" % number] = snappedf(centre, 0.1)
		measurements["preset%d_both_eyes" % number] = "yes" if eyes == "" else eyes
		shots.append(str(shoot.call(number)))
		if problem == "" and off_m > PLACE_TOLERANCE_M:
			problem = "preset %d: the panel is %.3f m from its %s place against the cockpit" % [number, off_m, corner]
		if problem == "" and eyes != "":
			problem = "preset %d: the panel is not inside both eyes' views: %s" % [number, eyes]
		if problem == "" and centre < StatusPanelBounds.CENTRAL_CONE_DEG:
			problem = "preset %d: the panel's centre is %.1f degrees from straight ahead, inside the %.0f degree cone" % [
				number, centre, StatusPanelBounds.CENTRAL_CONE_DEG]
		if problem == "" and angles.x < StatusPanelBounds.ROW_CONE_DEG:
			problem = "preset %d: a row comes %.1f degrees from straight ahead, inside the %.0f degree cone" % [
				number, angles.x, StatusPanelBounds.ROW_CONE_DEG]
	frame.set_spec(saved[0])
	frame.transform = saved[1]
	panel.transform = saved[2]
	measurements["screenshots"] = ", ".join(PackedStringArray(shots))
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	return [AcceptanceReport.RESULT_PASS, "on all four presets the panel sits in its %s place, inside both eyes' views, its centre %.0f degrees or more off straight ahead" % [
		corner, StatusPanelBounds.CENTRAL_CONE_DEG]]


static func _shot(runner: AcceptanceRunner, file: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped %s: headless display, nothing is drawn" % file
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped %s: %s" % [file, str(got)]
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped %s: cannot write %s: %s" % [file, path, error_string(error)]
