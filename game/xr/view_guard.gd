class_name ViewGuard
extends RefCounted

## Keeps the cockpit window in front of the eyes (#651, CMF-1, CMF-8).
##
## The frame sits at the recentred head point and the head turns inside it
## (#478). If the tracked head ever ends up far from that point, or looking
## well past the window's edge, for longer than the cockpit file allows, the
## pilot sees nothing but the inside of the shell. The owner saw exactly
## that: one flat interior colour over the whole view. This guard notices it
## and moves the frame and panel, never the rig, to the head's current point
## and heading, the way a recentre would place them; it does the same on
## every tracking regain. The world does not move, so the view is still moved
## only by the ship (CMF-8), and no simulation state is read or written
## (ARC-3, MP-2).
##
## A recentre (a new recentre point) puts the frame back at the head point.

## Where the frame and panel are placed, in the rig's space.
var frame_point: Transform3D = Transform3D.IDENTITY
## Clock time (`update`'s `now_s`) of the last placement.
var placed_at_s: float = 0.0
## Times the guard has re-placed the frame since it was made.
var replacements: int = 0
## Why the frame was last placed: "recentre", "head left the window" or
## "tracking regained".
var reason: String = ""

## The recentre point the frame was last put at; a change means a recentre.
var _recentre_point: Transform3D = Transform3D.IDENTITY
var _has_point: bool = false
## Clock time the head was first seen lost, below 0 while it is not.
var _lost_since_s: float = -1.0
var _was_tracked: bool = true


## Where the frame goes this frame. `recentre_point` is the recentred head
## point (`RigViews.head_point`), `head` the tracked head in the rig's space,
## `tracked` whether the runtime trusts that pose, `spec` the frame's cockpit
## and `now_s` a steady clock in seconds.
func update(recentre_point: Transform3D, head: Transform3D, tracked: bool, spec: CockpitSpec,
		now_s: float) -> Transform3D:
	if not _has_point or not recentre_point.is_equal_approx(_recentre_point):
		_has_point = true
		_recentre_point = recentre_point
		frame_point = recentre_point
		placed_at_s = now_s
		reason = "recentre"
		_lost_since_s = -1.0
	var regained: bool = tracked and not _was_tracked
	_was_tracked = tracked
	if not tracked or not _finite(head):
		_lost_since_s = -1.0
		return frame_point
	if regained:
		_replace(head, now_s, "tracking regained")
		return frame_point
	if not is_lost(frame_point, head, spec):
		_lost_since_s = -1.0
	elif _lost_since_s < 0.0:
		_lost_since_s = now_s
	elif now_s - _lost_since_s >= spec.guard_after_s:
		_replace(head, now_s, "head left the window")
	return frame_point


## Seconds since the frame was last placed.
func placed_age_s(now_s: float) -> float:
	return now_s - placed_at_s


## True when `head` looks further past `spec`'s window than its margin, or
## sits further from the frame's centre than its distance, with the frame at
## `frame`. Both in the rig's space.
static func is_lost(frame: Transform3D, head: Transform3D, spec: CockpitSpec) -> bool:
	if head_distance_m(frame, head) > spec.guard_distance_m:
		return true
	var angles: Vector2 = window_angles(frame, head)
	return absf(angles.x) > spec.window_half_angle_h_deg + spec.guard_margin_deg \
		or absf(angles.y) > spec.window_half_angle_v_deg + spec.guard_margin_deg


## Where `head` looks in the frame's own angles, degrees: x to the right of
## straight ahead, y up, as `CockpitFrame.direction` measures them. Looking
## straight up or down has no side angle; 0 then.
static func window_angles(frame: Transform3D, head: Transform3D) -> Vector2:
	var forward: Vector3 = (frame.basis.inverse() * -head.basis.z).normalized()
	var flat: float = Vector2(forward.x, forward.z).length()
	var yaw: float = rad_to_deg(atan2(forward.x, -forward.z)) if flat > 1.0e-4 else 0.0
	return Vector2(yaw, rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))))


## Angle between where `head` looks and the window's centre, degrees.
static func angle_to_window_deg(frame: Transform3D, head: Transform3D) -> float:
	return rad_to_deg((-frame.basis.z).angle_to(-head.basis.z))


## Distance of the eye from the frame's centre, metres.
static func head_distance_m(frame: Transform3D, head: Transform3D) -> float:
	return head.origin.distance_to(frame.origin)


## The frame point a recentre would give for `head`: its position and
## heading, its tilt left out (`HeadRecentre.offset_for`).
static func point_for(head: Transform3D) -> Transform3D:
	return HeadRecentre.offset_for(head).affine_inverse()


func _replace(head: Transform3D, now_s: float, why: String) -> void:
	frame_point = point_for(head)
	placed_at_s = now_s
	replacements += 1
	reason = why
	_lost_since_s = -1.0
	print("Meltdown: cockpit frame re-placed around the head: %s" % why)


static func _finite(transform: Transform3D) -> bool:
	return transform.basis.is_finite() and transform.origin.is_finite()
