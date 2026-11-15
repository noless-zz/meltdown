extends Node3D

## Entry scene. Starts an XR session when an OpenXR runtime is present and
## falls back to a flat window otherwise, so the same build runs on the
## headset, the desktop and headless CI (PLT-2, PLT-4).
##
## The scene also flies the local ship: `LocalSession` owns the simulation and
## the rig follows the simulated ship, so the view moves only with the ship's
## simulated motion (CMF-8). The rig reads copies of the ship and never writes
## simulation state (MP-2, ARC-3).

const TARGET_REFRESH_RATE: float = 90.0

## Where the caller (later the controller reader) puts the latest input.
var input_source: LatestInputSource = LatestInputSource.new()
var session: LocalSession = LocalSession.new(0, input_source)

var _session_begun: bool = false
var _smoke_probe: XrSmokeProbe = null


func _ready() -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		# The headset compositor paces frames; desktop vsync would fight it.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		var openxr: OpenXRInterface = xr as OpenXRInterface
		if openxr != null:
			openxr.session_begun.connect(_on_session_begun.bind(openxr))
		print("Meltdown: OpenXR session active")
	else:
		print("Meltdown: running flat (no OpenXR session)")
	_smoke_probe = XrSmokeProbe.new(XrSmokeProbe.frames_from_args(OS.get_cmdline_user_args()))
	place_rig()


func _process(delta: float) -> void:
	advance_frame(delta)
	if _smoke_probe != null and _smoke_probe.tick():
		print(_smoke_report())
		get_tree().quit()


## Runs the simulation for one frame of `delta_seconds` and moves the rig to
## the ship. Public so tests can drive frames without a running scene tree.
func advance_frame(delta_seconds: float) -> void:
	session.advance(delta_seconds)
	place_rig()


## Puts the rig at the ship's pose for this frame. The headset camera and
## controllers are tracked relative to the rig, so they ride along.
func place_rig() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig == null:
		return
	rig.transform = interpolated_pose(
		session.previous_ship(), session.current_ship(), session.interpolation_fraction)


## The ship's pose `fraction` of the way from `previous` to `current`:
## position lerped, rotation slerped. Frames fall between ticks, so showing
## either tick's pose alone would judder at 72 or 90 Hz against a 60 Hz sim.
static func interpolated_pose(previous: ShipState, current: ShipState, fraction: float) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var from_rotation: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to_rotation: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	var rotation: Quaternion = from_rotation.slerp(to_rotation, weight)
	return Transform3D(Basis(rotation), previous.position.lerp(current.position, weight))


func _on_session_begun(openxr: OpenXRInterface) -> void:
	_session_begun = true
	# PRF-1: 90 Hz by default when the headset offers it.
	var rates: Array = openxr.get_available_display_refresh_rates()
	if rates.has(TARGET_REFRESH_RATE):
		openxr.display_refresh_rate = TARGET_REFRESH_RATE
	print("Meltdown: refresh rate ", openxr.display_refresh_rate, " Hz, available ", rates)


## Reads what the runtime reports at the moment of quitting, so the line shows
## the state after the frames ran and not what was hoped for at start.
func _smoke_report() -> String:
	var runtime: String = ""
	var views: int = 0
	var refresh_rate: float = 0.0
	var openxr: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if openxr != null and openxr.is_initialized():
		runtime = str(openxr.get_system_info().get("XRRuntimeName", ""))
		views = openxr.get_view_count()
		refresh_rate = openxr.display_refresh_rate
	return XrSmokeProbe.format_line(_session_begun, runtime, views, refresh_rate, _smoke_probe.frames_seen())
