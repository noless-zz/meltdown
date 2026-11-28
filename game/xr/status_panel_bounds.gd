class_name StatusPanelBounds
extends RefCounted

## Where the status panel's drawn rows reach, seen from the eye (#1452). The
## owner saw the panel drift into the middle of the view, over the tunnel;
## this measures how near straight ahead any drawn part of it comes, so a unit
## test and the m6 `status_panel_place` step can hold it outside a central
## cone in every corner and on every cockpit.
##
## Labels are measured from their font with wide sample words for the rows
## whose text changes in flight, so the panel needs no scene tree and a short
## text on the day cannot hide a long one. The outcome row is left out: it
## shows only after the flight has ended. Reads the panel only (ARC-3).
##
## #1507: the whole panel must also lie where both eyes see it (`EyeViews`),
## which leaves too little room to keep every row outside the central cone
## within a glance down. The panel's centre keeps the cone; its rows keep a
## narrower one.

## The panel's centre may not come nearer straight ahead than this.
const CENTRAL_CONE_DEG: float = 25.0
## No drawn part of the panel may come nearer straight ahead than this.
const ROW_CONE_DEG: float = 20.0
## Wide sample words for the rows whose text changes in flight.
const SAMPLE_TEXT: Dictionary = {
	"Meltdown": "MELTDOWN 9:59",
	"Hold": "Hold: Shield booster",
	"Tally": "Carried 12 | Miners 3",
	"TallyBanked": "Banked 24",
	"Weapon": "> Pulse laser",
	"Weapon2": "  Needle gun",
}


## Every corner of every node `panel` may draw in flight, in the panel's space.
static func drawn_points(panel: StatusPanel) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child: Node in panel.get_children():
		var node: VisualInstance3D = child as VisualInstance3D
		if node == null or node.layers == 0 or child.name == StatusPanel.OUTCOME_NAME:
			continue
		var box: AABB = node.get_aabb()
		var label: Label3D = node as Label3D
		if label != null:
			box = label_box(label, SAMPLE_TEXT.get(String(label.name), label.text))
		for i: int in 8:
			points.append(node.transform * box.get_endpoint(i))
	return points


## The box `text` takes on `label`, which is left-aligned and centred on its
## row like every panel label (`StatusPanelLabels.make`).
static func label_box(label: Label3D, text: String) -> AABB:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size) * label.pixel_size
	return AABB(Vector3(0.0, -size.y * 0.5, 0.0), Vector3(size.x, size.y, 0.0))


## The nearest and farthest angle off the cockpit's straight ahead, in
## degrees, of `points` on a panel at `panel_at`, both in the rig's space,
## seen from the eye point of a cockpit frame at `cockpit`.
static func angles(points: Array[Vector3], panel_at: Transform3D, cockpit: Transform3D) -> Vector2:
	var ahead: Vector3 = cockpit.basis * Vector3.FORWARD
	var near: float = 180.0
	var far: float = 0.0
	for point: Vector3 in points:
		var angle: float = rad_to_deg((panel_at * point - cockpit.origin).angle_to(ahead))
		near = minf(near, angle)
		far = maxf(far, angle)
	return Vector2(near, far)


## The angle off the cockpit's straight ahead, in degrees, of the centre of
## a panel at `panel_at`, seen from the eye point of a cockpit at `cockpit`.
static func centre_angle(panel_at: Transform3D, cockpit: Transform3D) -> float:
	return rad_to_deg((panel_at.origin - cockpit.origin).angle_to(cockpit.basis * Vector3.FORWARD))


## Empty when every one of `points` on a panel at `panel_at` lies inside both
## eyes' `views` of a cockpit at `cockpit` (all in the rig's space), else the
## first problem, naming the eye and the edge.
static func eyes_problem(points: Array[Vector3], panel_at: Transform3D, cockpit: Transform3D,
		views: EyeViews) -> String:
	var into: Transform3D = cockpit.affine_inverse() * panel_at
	for point: Vector3 in points:
		var problem: String = views.problem_at(into * point)
		if problem != "":
			return problem
	return ""
