extends RefCounted

## What the player sees through the preset 1 (Anchored) window looking straight
## ahead (#212, CMF-1, CMF-3). In the headset the old 25 by 15 degree window
## felt like a slot: the 1 m marker and the controller labels sat behind the
## solid panels. Everything here is measured in the frame's own angles (yaw
## right, pitch up from the horizon, see `CockpitFrame.direction`). Since #607
## every piece of the frame lies outside the window, so the window's own edge
## is the limit.

const LABEL_LAYOUT: GDScript = preload("res://tests/test_label_layout.gd")
## The flat stand-in for a seated head, as in `test_head_recentre.gd`.
const SEATED_HEAD: Vector3 = Vector3(0.0, 1.6, 0.0)
static func _anchored() -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(1))


## Angle in degrees the frame reaches into the window: none since #607, when
## the struts on the window's edge gave way to shapes outside it.
static func frame_margin_deg(_spec: CockpitSpec) -> float:
	return 0.0


## (yaw, pitch) in degrees of `point`, seen from an eye at the origin looking along -z.
static func yaw_pitch(point: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(point.x, -point.z)),
		rad_to_deg(atan2(point.y, Vector2(point.x, point.z).length())))


## Empty when `point` is inside `spec`'s window and clear of its frame.
static func outside_message(spec: CockpitSpec, point: Vector3, what: String) -> String:
	var angles: Vector2 = yaw_pitch(point)
	var margin: float = frame_margin_deg(spec)
	if absf(angles.x) > spec.window_half_angle_h_deg - margin \
			or absf(angles.y) > spec.window_half_angle_v_deg - margin:
		return "%s at yaw %.1f, pitch %.1f is outside the %.0f x %.0f window less %.1f for the frame" % [
			what, angles.x, angles.y, spec.window_half_angle_h_deg, spec.window_half_angle_v_deg, margin]
	return ""


func test_anchored_window_is_wider_than_the_slot() -> String:
	var spec: CockpitSpec = _anchored()
	if spec.error != "":
		return spec.error
	if spec.window_half_angle_h_deg < 35.0 or spec.window_half_angle_v_deg < 22.0:
		return "preset 1 window is still %.0f x %.0f degrees" % [
			spec.window_half_angle_h_deg, spec.window_half_angle_v_deg]
	return ""


func test_control_labels_are_inside_the_anchored_window() -> String:
	var spec: CockpitSpec = _anchored()
	var layout: RefCounted = LABEL_LAYOUT.new()
	var rig: Node = layout.call("_rig_in_neutral_pose", LABEL_LAYOUT.CLOSE_APART_M)
	# Each label's rectangle in tangent units, eye at the origin looking along -z.
	var rects: Dictionary = LABEL_LAYOUT._view_rects(rig)
	rig.free()
	if rects.size() != 11:  # 11 since X lost its preset label (#1260).
		return "want the 11 default labels, measured %d" % rects.size()
	for key: Variant in rects:
		var rect: Rect2 = rects[key]
		for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y),
				Vector2(rect.end.x, rect.position.y)]:
			var message: String = outside_message(spec, Vector3(corner.x, corner.y, -1.0),
				"the corner of label '%s'" % key)
			if message != "":
				return message
	return ""


func test_distance_markers_are_inside_the_anchored_window() -> String:
	var spec: CockpitSpec = _anchored()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var camera: Node3D = main.get_node("XRRig/Camera") as Node3D
	camera.transform = Transform3D(Basis(), SEATED_HEAD)
	(main.get("head_recentre") as HeadRecentre).request()
	main.call("place_rig")
	main.call("place_tunnel")
	var eye: Transform3D = (main.get_node("XRRig") as Node3D).transform * camera.transform
	var tunnel: Node3D = main.get_node("TestTunnel") as Node3D
	tunnel.call("build")
	var markers: Node = tunnel.get_node_or_null("Markers")
	var checked: int = 0
	var message: String = ""
	if markers != null:
		for marker: Node3D in markers.get_children():
			# Every marker's label too: the 1 m label once hung about 34 degrees
			# up, outside both the preset 1 and 2 windows (#249).
			var label: Node3D = marker.get_node("Label") as Node3D
			var points: Dictionary = {"the %s ball" % marker.name: marker.position,
				"the %s label" % marker.name: marker.position + label.position}
			for what: String in points:
				var seen: Vector3 = eye.affine_inverse() * (tunnel.transform * (points[what] as Vector3))
				message = outside_message(spec, seen, what)
				if message != "":
					break
			checked += 1
			if message != "":
				break
	main.free()
	if message != "":
		return message
	if checked != TestTunnel.MARKER_DISTANCES.size():
		return "checked %d markers, the tunnel has %d" % [checked, TestTunnel.MARKER_DISTANCES.size()]
	return ""
