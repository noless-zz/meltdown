class_name HeadRecentre
extends RefCounted

## Puts the player's eye point at the ship's centre (#102, CMF-11).
##
## The headset is tracked from the floor, so with the rig origin at the ship's
## centre the eyes sat 1.1 to 1.7 m above it: outside the ship's 1 m collision
## sphere, where they reached a wall before the ship did. The fix is an offset
## between the ship's pose and the tracked space, `rig = ship * offset`, that
## maps the head's position (and heading) at the recentre moment to the rig
## origin. An offset was chosen over `XRServer.center_on_hmd()` because it
## works the same for the flat fallback camera, can be tested without a
## runtime, and leaves XRServer's reference frame alone.
##
## A recentre moves the view, so it happens only when asked for: when the XR
## session begins (or the flat scene starts), on the runtime's recentre event,
## and on reset-to-start under the fade. Never on its own during flight (CMF-8).
## Only this player's view moves; the ship is not touched (ARC-3).

## How far a seated player leans from the recentred point, in metres. The ship
## radius minus this must leave room for the camera's near plane, or a wall
## the ship touches could be cut by the view.
const HEAD_REACH: float = 0.4
## The head tracker Godot's XRCamera3D follows.
const HEAD_TRACKER: StringName = &"head"

## Sent whenever a head pose is taken, with that pose in tracked space, so
## anything else that measures from forward (swivel-chair yaw, #791) recentres
## with the view.
signal recentred(head: Transform3D)

## Tracked space relative to the ship's pose; identity until the first recentre.
var offset: Transform3D = Transform3D.IDENTITY
## True from a request until a head pose has been taken.
var pending: bool = false


## Asks for a recentre on the next frame that has a head pose.
func request() -> void:
	pending = true


## Takes the head pose and clears the request, if one is pending and the pose
## can be trusted: always for the flat camera, only once the headset is
## tracked during an XR session (the first frames after it begins may have
## no pose yet). Returns true when it recentred.
func update(head: Transform3D, xr_running: bool) -> bool:
	if not pending:
		return false
	if xr_running and not head_tracked():
		return false
	apply(head)
	return true


## Makes `head` (in tracked space) the eye point at the rig origin.
func apply(head: Transform3D) -> void:
	offset = offset_for(head)
	pending = false
	recentred.emit(head)


## The rig's transform for a ship at `ship_pose`.
func rig_transform(ship_pose: Transform3D) -> Transform3D:
	return ship_pose * offset


## The inverse of the head's position and heading. Tilt is kept, like
## `XRServer.RESET_BUT_KEEP_TILT`: the real horizon stays level for the
## inner ear; only which way is forward and where the eyes are change.
static func offset_for(head: Transform3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, heading(head.basis)), head.origin).affine_inverse()


## Radians about +Y from -Z to where `basis` looks, flattened to the floor.
## Looking straight up or down has no heading; 0 then.
static func heading(basis: Basis) -> float:
	var forward: Vector3 = -basis.z
	if Vector2(forward.x, forward.z).length() < 1.0e-4:
		return 0.0
	return atan2(-forward.x, -forward.z)


## True while the runtime reports a tracked head pose.
static func head_tracked() -> bool:
	var tracker: XRPositionalTracker = XRServer.get_tracker(HEAD_TRACKER) as XRPositionalTracker
	if tracker == null:
		return false
	var pose: XRPose = tracker.get_pose(&"default")
	return pose != null and pose.has_tracking_data
