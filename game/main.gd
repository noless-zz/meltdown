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
## Where the test tunnel sits relative to the simulation origin, where the ship
## starts. The ship's collision sphere has a 1 m radius, so the floor goes 1 m
## below the start; otherwise the first tick would push the ship up off the
## floor with a jolt.
const TUNNEL_OFFSET: Vector3 = Vector3(0.0, -1.0, 0.0)
## The ship's feel values, tuned after headset sessions without code changes.
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"

## Where each frame's sampled input goes; every tick until the next frame flies it.
var input_source: LatestInputSource = LatestInputSource.new()
## Flies inside the test tunnel's walls, from the same box the tunnel is drawn
## around (FLT-3), with the tuning file's values or, if it is rejected, the defaults.
var session: LocalSession = LocalSession.new(0, input_source, TestTunnel.interior_box(TUNNEL_OFFSET),
		LocalSession.load_tuning(SHIP_TUNING_PATH))
## Controller and keyboard values both fly through this one mapping (PLT-5).
var mapping: ThumbstickMapping = ThumbstickMapping.new()
var keyboard: KeyboardSampler = KeyboardSampler.new()
## Built from the rig's hands in `_ready`; null until then.
var controllers: ControllerSampler = null
## Number (1..4) of the active comfort preset; change it with `set_comfort_preset`.
var comfort_number: int = ComfortPresetFiles.START_NUMBER
var comfort_preset: ComfortPreset = ComfortPresetFiles.load_number(comfort_number)
## Every frame's mapped input passes through this before the ship flies it.
## It only changes the input this player sends, never ship state (CMF-6, ARC-3).
var comfort_filter: ComfortInputFilter = ComfortInputFilter.new(comfort_preset)

var _session_begun: bool = false
## True between the XR session beginning and stopping; picks the input device.
var _xr_running: bool = false
var _smoke_probe: XrSmokeProbe = null
## The preset switch acts once per press, not once per frame it is held.
var _preset_button_held: bool = false
## Times the hold-both-clicks way back to the start and its fade (#90).
var reset_hold: ResetHold = ResetHold.new()
## The black quad under the camera, added by `attach_fade_overlay`.
var fade_overlay: FadeOverlay = null
## Keeps the eye point at the ship's centre, inside its collision sphere (#102).
var head_recentre: HeadRecentre = HeadRecentre.new()

## True from the frame an input that must fly exactly once (a snap, or the
## reset) is set until a tick has flown it. A frame at 90 Hz runs no tick
## about one time in three, and a hitch runs several.
var _one_tick_pending: bool = false
## Set when focus returns; the frame after a pause may run only one tick.
var _resume_frame: bool = false


func _ready() -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		# The headset compositor paces frames; desktop vsync would fight it.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		var openxr: OpenXRInterface = xr as OpenXRInterface
		if openxr != null:
			openxr.session_begun.connect(_on_session_begun.bind(openxr))
			openxr.session_visible.connect(on_session_visible)
			openxr.session_focussed.connect(on_session_focussed)
			openxr.session_loss_pending.connect(on_session_loss_pending)
			openxr.session_stopping.connect(on_session_stopping)
			openxr.pose_recentered.connect(head_recentre.request)
		print("Meltdown: OpenXR session active")
	else:
		head_recentre.request()
		print("Meltdown: running flat (no OpenXR session)")
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	set_comfort_preset(ComfortPresetFiles.number_from_args(args))
	_smoke_probe = XrSmokeProbe.new(XrSmokeProbe.frames_from_args(OS.get_cmdline_user_args()))
	# One mapping, so a remap or left-handed mode reaches the control labels too (#110).
	$XRRig.mapping = mapping
	controllers = ControllerSampler.for_controllers(
		get_node_or_null("XRRig/LeftHand") as XRController3D,
		get_node_or_null("XRRig/RightHand") as XRController3D)
	place_tunnel()
	attach_fade_overlay()
	place_rig()
	InstallerProbe.run_if_requested()  # Debug builds, only when asked (#130).


func _process(delta: float) -> void:
	apply_controls(sample_controls())
	advance_frame(delta)
	if _smoke_probe != null and _smoke_probe.tick():
		print(_smoke_report())
		get_tree().quit()


## This frame's raw values: the controllers while an XR session runs, the
## keyboard otherwise (PLT-4).
func sample_controls() -> Dictionary:
	if _xr_running and controllers != null:
		return controllers.sample()
	var pressed: Array[int] = []
	for key: int in keyboard.used_keys():
		if Input.is_physical_key_pressed(key):
			pressed.append(key)
	var values: Dictionary = keyboard.sample(pressed)
	if Input.is_physical_key_pressed(ResetHold.KEYBOARD_KEY):
		values["buttons"][ResetHold.KEYBOARD_BUTTON] = true
	return values


## Maps raw values through the comfort filter to the input every tick flies
## until the next frame. Public so tests can feed values without a device.
func apply_controls(values: Dictionary) -> void:
	_read_preset_button(values.get("buttons", {}))
	reset_hold.press(ResetHold.is_held(values))
	var input: ShipInput = ControllerSampler.map_values(mapping, values)
	if _one_tick_pending:
		# No tick has flown it yet: keep a snap's turn with the new thrust, a reset whole.
		var held: ShipInput = ComfortInputFilter.copy_input(input_source.latest_input())
		if not held.reset_to_start:
			held.thrust_q = input.thrust_q
			held.afterburner = input.afterburner
		input_source.set_input(held)
	else:
		var filtered: ShipInput = comfort_filter.filter(input, session.current_ship().orientation)
		if reset_hold.reset_due():
			# Still, so the reset tick ends exactly at the start pose.
			filtered = ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, true)
		_one_tick_pending = carries_snap(filtered) or filtered.reset_to_start
		input_source.set_input(filtered)


## Runs the simulation for one frame of `delta_seconds` and moves the rig to
## the ship. Public so tests can drive frames without a running scene tree.
## A pending snap or reset gets a tick of its own: the frame is split where
## the next tick falls, so a hitch frame cannot fly it twice.
func advance_frame(delta_seconds: float) -> void:
	reset_hold.advance(delta_seconds)
	var resuming: bool = _resume_frame
	_resume_frame = false
	var to_tick: float = (1.0 - session.interpolation_fraction) * ShipState.TICK_DT
	if _one_tick_pending and not session.paused and delta_seconds > to_tick:
		session.advance(to_tick)
		_end_one_tick_if_flown()
		# The session limits a resumed frame to one tick; the split must too.
		session.advance(0.0 if resuming else delta_seconds - to_tick)
	else:
		session.advance(delta_seconds)
		_end_one_tick_if_flown()
	if fade_overlay != null:
		fade_overlay.set_alpha(reset_hold.alpha)
	place_rig()


## True when `input` turns the ship by a snap on an axis the preset snaps.
func carries_snap(input: ShipInput) -> bool:
	return (comfort_preset.yaw_mode == ComfortPreset.YawMode.SNAP and input.turn_q.y != 0) \
		or (comfort_preset.pitch_mode == ComfortPreset.PitchMode.SNAP and input.turn_q.x != 0)


## Makes preset `number` (1..4) the active one with a fresh filter. Only this
## player's input handling changes; the ship is not touched (CMF-6).
func set_comfort_preset(number: int) -> void:
	comfort_number = number
	comfort_preset = ComfortPresetFiles.load_number(number)
	comfort_filter = ComfortInputFilter.new(comfort_preset)
	_one_tick_pending = false
	print("Meltdown: comfort preset %d %s" % [number, comfort_preset.display_name])


## The development preset switch: the upper face button of the hand that does
## not turn (Y, or B when left-handed). Read here rather than bound in the
## mapping, since it is not a flight control and a settings menu replaces it.
func preset_button() -> String:
	return "right_button_upper" if mapping.left_handed else "left_button_upper"


func _read_preset_button(buttons: Dictionary) -> void:
	var pressed: bool = bool(buttons.get(preset_button(), false))
	if pressed and not _preset_button_held:
		set_comfort_preset(ComfortPresetFiles.next_number(comfort_number))
	_preset_button_held = pressed


## Once a tick has flown a snap or the reset, later ticks before the next
## sample must not repeat it; the filter keeps a snapped axis at zero until
## the stick returns, and the reset is followed by the fade back in.
func _end_one_tick_if_flown() -> void:
	if not _one_tick_pending or session.ticks_last_advance == 0:
		return
	_one_tick_pending = false
	var flown: ShipInput = ComfortInputFilter.copy_input(input_source.latest_input())
	if flown.reset_to_start:
		reset_hold.reset_flown()
		head_recentre.request()
		input_source.set_input(ShipInput.new())
		return
	if comfort_preset.pitch_mode == ComfortPreset.PitchMode.SNAP:
		flown.turn_q.x = 0
	if comfort_preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		flown.turn_q.y = 0
	input_source.set_input(flown)


## Moves the drawn tunnel to `TUNNEL_OFFSET`, where the session's walls are.
func place_tunnel() -> void:
	var tunnel: Node3D = get_node_or_null("TestTunnel") as Node3D
	if tunnel != null:
		tunnel.position = TUNNEL_OFFSET


## Puts the fade quad under the rig's camera; the rig scene stays as it is.
func attach_fade_overlay() -> void:
	var camera: Node3D = get_node_or_null("XRRig/Camera") as Node3D
	if camera != null and fade_overlay == null:
		fade_overlay = FadeOverlay.new()
		camera.add_child(fade_overlay)


## Puts the rig at the ship's pose for this frame, offset so the head sits at
## the ship's centre. The headset camera and controllers are tracked relative
## to the rig, so they ride along. A requested recentre takes the head pose here.
func place_rig() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig == null:
		return
	var camera: Node3D = rig.get_node_or_null("Camera") as Node3D
	if camera != null:
		head_recentre.update(camera.transform, _xr_running)
	rig.transform = head_recentre.rig_transform(interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, snap_show_angle()))


## Radians a tick must turn to be shown as a snap: half a snap while the
## preset snaps yaw or pitch, 0 (never) otherwise.
func snap_show_angle() -> float:
	var snaps: bool = comfort_preset.yaw_mode == ComfortPreset.YawMode.SNAP \
		or comfort_preset.pitch_mode == ComfortPreset.PitchMode.SNAP
	return deg_to_rad(comfort_preset.snap_angle_deg) * 0.5 if snaps else 0.0


## The ship's pose `fraction` of the way from `previous` to `current`:
## position lerped, rotation slerped. Frames fall between ticks, so showing
## either tick's pose alone would judder at 72 or 90 Hz against a 60 Hz sim.
## A turn of at least `snap_angle` (when above 0) is a snap and is shown at
## once: slerping it would show a snap as smooth rotation (CMF-3).
static func interpolated_pose(previous: ShipState, current: ShipState, fraction: float,
		snap_angle: float = 0.0) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var from_rotation: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to_rotation: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	var rotation: Quaternion = from_rotation.slerp(to_rotation, weight)
	if snap_angle > 0.0 and from_rotation.angle_to(to_rotation) >= snap_angle:
		rotation = to_rotation
	return Transform3D(Basis(rotation), previous.position.lerp(current.position, weight))


func _on_session_begun(openxr: OpenXRInterface) -> void:
	_session_begun = true
	_xr_running = true
	head_recentre.request()
	# PRF-1: 90 Hz by default when the headset offers it.
	var rates: Array = openxr.get_available_display_refresh_rates()
	if rates.has(TARGET_REFRESH_RATE):
		openxr.display_refresh_rate = TARGET_REFRESH_RATE
	print("Meltdown: refresh rate ", openxr.display_refresh_rate, " Hz, available ", rates)


## The app is shown but has lost input focus: the headset was taken off or
## the system menu is up. Solo play holds still until focus returns (PLT-7).
## The runtime also passes through this state on the way to focus at start,
## which is harmless: nothing has been flown yet.
func on_session_visible() -> void:
	session.paused = true


## Focus is back; the session limits the next frame to one tick, so the ship
## does not jump (CMF-8).
func on_session_focussed() -> void:
	session.paused = false
	_resume_frame = true


## The runtime is about to lose the session; nothing should move meanwhile.
func on_session_loss_pending() -> void:
	session.paused = true


## Pauses, and hands back to the keyboard so the input device matches what is
## left. A stopped XR session only resumes through `on_session_focussed`.
func on_session_stopping() -> void:
	_xr_running = false
	session.paused = true


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
