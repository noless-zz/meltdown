class_name MapPanelClearance
extends RefCounted

## Whether a map mounted in the cockpit (#1321, MAP-1) stays readable and out
## of the way: seen from the eye, it lies inside the cockpit's window (so it
## reads in preset 1's reduced view too), in front of the frame's shell, and
## clear of the status panel in its corner and of every declared instrument.
## The unit tests run it over every corner, turn and preset, and the m6
## acceptance step `map_places` runs it on the live scene.
##
## Views are in degrees of yaw and pitch from the eye at the frame's origin
## looking along -z (`CockpitGeometry.yaw_pitch`). The map can turn any way
## (`MapChoice.TURN_FOLLOWS`), so it is measured by the sphere round its cube,
## which no turn leaves. Pure arithmetic on copies: nothing here moves a node
## or reaches the simulation (ARC-3, CMF-6).

## The panel's rows in its own plane, metres: the labels from x = -0.12 and
## the level row right-aligned at 0.12, the top row at 0.0945 and the bottom
## at -0.1215, each widened by half a line of `StatusPanel.SMALL_FONT` text.
## The large preset name, the build line and the outcome row show only for
## seconds or on the end screen and are left out.
const PANEL_RECT: Rect2 = Rect2(-0.13, -0.135, 0.26, 0.24)
## The least gap, degrees, between the map and the panel or an instrument.
const GAP_DEG: float = 1.0
## How far round its point an instrument is taken to reach, degrees.
const INSTRUMENT_HALF_DEG: float = 4.0
## A cube's bounding sphere radius over its edge: half the space diagonal.
const SPHERE_PER_EDGE: float = 0.8660254


## The status panel in `corner`, as the eye sees it: the box round its four
## corners in yaw and pitch.
static func panel_rect(corner: String, look: Dictionary = StatusPanelLook.shared()) -> Rect2:
	var placed: Transform3D = StatusPanelLook.placement(look, corner)
	var rect: Rect2 = Rect2()
	var first: bool = true
	for x: float in [PANEL_RECT.position.x, PANEL_RECT.end.x]:
		for y: float in [PANEL_RECT.position.y, PANEL_RECT.end.y]:
			var seen: Vector2 = CockpitGeometry.yaw_pitch(placed * Vector3(x, y, 0.0))
			rect = Rect2(seen, Vector2.ZERO) if first else rect.expand(seen)
			first = false
	return rect


## A map of cube edge `edge_m` centred at `centre` (frame space), as the eye
## sees it: a square of the sphere's half-angle round the centre's direction.
static func map_rect(centre: Vector3, edge_m: float) -> Rect2:
	var radius: float = edge_m * SPHERE_PER_EDGE
	var half: float = rad_to_deg(asin(clampf(radius / maxf(centre.length(), radius), 0.0, 1.0)))
	var seen: Vector2 = CockpitGeometry.yaw_pitch(centre)
	return Rect2(seen - Vector2(half, half), Vector2(half, half) * 2.0)


## The first problem with a map of edge `edge_m` at `centre` in cockpit `spec`
## while the panel is in `corner`, or "" when it is clear.
static func problem(spec: CockpitSpec, corner: String, centre: Vector3, edge_m: float) -> String:
	var map: Rect2 = map_rect(centre, edge_m)
	var window: Rect2 = Rect2(-spec.window_half_angle_h_deg, -spec.window_half_angle_v_deg,
		2.0 * spec.window_half_angle_h_deg, 2.0 * spec.window_half_angle_v_deg)
	if not window.encloses(map):
		return "map %s leaves the %.0f x %.0f degree window" % [_text(map),
			spec.window_half_angle_h_deg, spec.window_half_angle_v_deg]
	var back: float = centre.length() + edge_m * SPHERE_PER_EDGE
	if back >= spec.frame_distance_m:
		return "map reaches %.3f m from the eye, behind the shell at %.3f m" % [back, spec.frame_distance_m]
	var panel: Rect2 = panel_rect(corner)
	if map.grow(GAP_DEG).intersects(panel):
		return "map %s overlaps the panel in %s at %s" % [_text(map), corner, _text(panel)]
	for instrument: CockpitInstrument in spec.instruments:
		var at: Vector2 = Vector2(instrument.yaw_deg, instrument.pitch_deg)
		var reach: Rect2 = Rect2(at, Vector2.ZERO).grow(INSTRUMENT_HALF_DEG)
		if map.grow(GAP_DEG).intersects(reach):
			return "map %s overlaps instrument %s" % [_text(map), instrument.id]
	return ""


## The first problem with the map at `spec`'s own mount for a panel in
## `corner`, or "" when it is clear.
static func mount_problem(spec: CockpitSpec, corner: String) -> String:
	var mount: CockpitMapMount = spec.map_mount
	return problem(spec, corner, mount.spot(corner), mount.size_m)


static func _text(rect: Rect2) -> String:
	return "yaw %.1f..%.1f, pitch %.1f..%.1f" % [rect.position.x, rect.end.x, rect.position.y, rect.end.y]
