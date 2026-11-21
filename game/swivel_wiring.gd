class_name SwivelWiring
extends RefCounted

## Feeds swivel-chair yaw (CMF-7, #722) into this player's input when the
## active comfort preset switches it on (#779, #791).
##
## `ComfortWiring.hand_input` passes each frame's mapped input through `added`
## before `ComfortInputFilter`, so the swivel is just more stick: preset 1
## still turns only by snaps and preset 2's caps still hold (CMF-3). With the
## swivel off the very same input object is handed back, so every replay
## flies bit for bit as before. Only the player's input changes; nothing here
## writes `ShipState` or `Sim` (ARC-3, MP-2), and the view still moves only
## with the ship (CMF-8).
##
## Forward is where the head was when `HeadRecentre` last took a pose (session
## start, the runtime's recentre event, reset-to-start, a restart). Turning the
## swivel on with a preset change also makes the current head heading forward,
## so the ship does not start turning by itself.

## Longest frame time handed to the swivel's follow, seconds. A hitch or a
## pause must not snap the reference across to the body in one go.
const MAX_DELTA_S: float = 0.25

## The active preset's swivel; off on all four shipped presets.
var yaw: SwivelYaw = SwivelYaw.new()
## The headset camera under the rig, tracked space; null until `attach`.
var camera: Node3D = null
## Seconds on a steady clock, for the reference's follow rate. Tests replace it.
var clock: Callable = ClickHold.steady_seconds
## Whether the camera's pose can be trusted this frame. Tests replace it.
var head_trusted: Callable = SwivelWiring.head_pose_trusted

var _last_s: float = NAN


## Takes the swivel settings of `preset`. Keeps forward where it was, unless
## this change turns the swivel on: then the current head heading is forward.
func set_preset(preset: ComfortPreset) -> void:
	var was_on: bool = yaw.enabled
	var reference: float = yaw.reference_rad
	yaw = SwivelYaw.from_preset(preset)
	yaw.reference_rad = reference
	if yaw.error != "":
		print("Meltdown: swivel off: %s" % yaw.error)
	if yaw.enabled and not was_on:
		yaw.recentre(head_yaw())
		_last_s = NAN


## Reads the head from `rig`'s camera and recentres with every `HeadRecentre` pose.
func attach(rig: Node3D, recentre: HeadRecentre) -> void:
	camera = rig.get_node_or_null("Camera") as Node3D
	if not recentre.recentred.is_connected(on_recentred):
		recentre.recentred.connect(on_recentred)


## `HeadRecentre` took `head` (tracked space) as forward.
func on_recentred(head: Transform3D) -> void:
	yaw.recentre(HeadRecentre.heading(head.basis))


## The head's heading in tracked space, radians about +Y, + turned left;
## 0 without a camera.
func head_yaw() -> float:
	return HeadRecentre.heading(camera.transform.basis) if camera != null else 0.0


## `input` with this frame's swivel yaw added, or `input` itself when the
## swivel is off or the head pose cannot be trusted.
func added(input: ShipInput) -> ShipInput:
	if not yaw.enabled:
		return input
	var now_s: float = float(clock.call())
	var delta: float = 0.0 if is_nan(_last_s) else clampf(now_s - _last_s, 0.0, MAX_DELTA_S)
	_last_s = now_s
	if not bool(head_trusted.call()):
		return input
	return SwivelYaw.added_to(input, yaw.update(head_yaw(), delta))


## True for the flat camera, and in an XR session while the head is tracked: a
## lost head keeps its last pose, which must not keep turning the ship.
static func head_pose_trusted() -> bool:
	var xr: XRInterface = XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return true
	return HeadRecentre.head_tracked()
