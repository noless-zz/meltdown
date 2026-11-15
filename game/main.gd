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
## The comfort preset a run starts with until the first-launch flight test
## (CMF-4) picks one. `--comfort-preset=1..4` overrides it.
const START_COMFORT_PRESET: int = 2
## Preset files in the numbering of the comfort table (CMF-1): index 0 is preset 1.
const COMFORT_PRESET_PATHS: Array[String] = [
	"res://xr/presets/comfort_anchored.tres", "res://xr/presets/comfort_guided.tres",
	"res://xr/presets/comfort_pilot.tres", "res://xr/presets/comfort_unrestricted.tres",
]
const COMFORT_PRESET_ARG: String = "--comfort-preset="

## Where each frame's sampled input goes; every tick until the next frame flies it.
var input_source: LatestInputSource = LatestInputSource.new()
## Flies inside the test tunnel's walls, from the same box the tunnel is drawn
## around (FLT-3).
var session: LocalSession = LocalSession.new(0, input_source, TestTunnel.interior_box(TUNNEL_OFFSET))
## Controller and keyboard values both fly through this one mapping (PLT-5).
var mapping: ThumbstickMapping = ThumbstickMapping.new()
var keyboard: KeyboardSampler = KeyboardSampler.new()
## Built from the rig's hands in `_ready`; null until then.
var controllers: ControllerSampler = null
## Number (1..4) of the active comfort preset; change it with `set_comfort_preset`.
var comfort_number: int = START_COMFORT_PRESET
var comfort_preset: ComfortPreset = load_comfort_preset(START_COMFORT_PRESET)
## Every frame's mapped input passes through this before the ship flies it.
## It only changes the input this player sends, never ship state (CMF-6, ARC-3).
var comfort_filter: ComfortInputFilter = ComfortInputFilter.new(comfort_preset)

var _session_begun: bool = false
## True between the XR session beginning and stopping; picks the input device.
var _xr_running: bool = false
var _smoke_probe: XrSmokeProbe = null
## The preset switch acts once per press, not once per frame it is held.
var _preset_button_held: bool = false
## True from the frame the filter fires a snap until a tick has flown it. A
## frame at 90 Hz runs no tick about one time in three, and a hitch runs
## several; the filter fires once per stick push, so the snap is held for
## exactly one tick.
var _snap_pending: bool = false
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
		print("Meltdown: OpenXR session active")
	else:
		print("Meltdown: running flat (no OpenXR session)")
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	set_comfort_preset(preset_number_from_args(args))
	_smoke_probe = XrSmokeProbe.new(XrSmokeProbe.frames_from_args(OS.get_cmdline_user_args()))
	controllers = ControllerSampler.for_controllers(
		get_node_or_null("XRRig/LeftHand") as XRController3D,
		get_node_or_null("XRRig/RightHand") as XRController3D)
	place_tunnel()
	place_rig()


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
	return keyboard.sample(pressed)


## Maps raw values through the comfort filter to the input every tick flies
## until the next frame. Public so tests can feed values without a device.
func apply_controls(values: Dictionary) -> void:
	_read_preset_button(values.get("buttons", {}))
	var input: ShipInput = ControllerSampler.map_values(mapping, values)
	if _snap_pending:
		# No tick has flown the snap yet; keep its turn, take the new thrust.
		var held: ShipInput = input_source.latest_input()
		input_source.set_input(ShipInput.new(input.thrust_q, held.turn_q, input.afterburner))
		return
	var filtered: ShipInput = comfort_filter.filter(input, session.current_ship().orientation)
	_snap_pending = carries_snap(filtered)
	input_source.set_input(filtered)


## Runs the simulation for one frame of `delta_seconds` and moves the rig to
## the ship. Public so tests can drive frames without a running scene tree.
## A pending snap gets a tick of its own: the frame is split where the next
## tick falls, so a hitch frame cannot fly the same snap twice.
func advance_frame(delta_seconds: float) -> void:
	var resuming: bool = _resume_frame
	_resume_frame = false
	var to_tick: float = (1.0 - session.interpolation_fraction) * ShipState.TICK_DT
	if _snap_pending and not session.paused and delta_seconds > to_tick:
		session.advance(to_tick)
		_end_snap_if_flown()
		# The session limits a resumed frame to one tick; the split must too.
		session.advance(0.0 if resuming else delta_seconds - to_tick)
	else:
		session.advance(delta_seconds)
		_end_snap_if_flown()
	place_rig()


## True when `input` turns the ship by a snap on an axis the preset snaps.
func carries_snap(input: ShipInput) -> bool:
	return (comfort_preset.yaw_mode == ComfortPreset.YawMode.SNAP and input.turn_q.y != 0) \
		or (comfort_preset.pitch_mode == ComfortPreset.PitchMode.SNAP and input.turn_q.x != 0)


## Makes preset `number` (1..4) the active one with a fresh filter. Only this
## player's input handling changes; the ship is not touched (CMF-6).
func set_comfort_preset(number: int) -> void:
	comfort_number = number
	comfort_preset = load_comfort_preset(number)
	comfort_filter = ComfortInputFilter.new(comfort_preset)
	_snap_pending = false
	print("Meltdown: comfort preset %d %s" % [number, comfort_preset.display_name])


static func load_comfort_preset(number: int) -> ComfortPreset:
	return load(COMFORT_PRESET_PATHS[number - 1]) as ComfortPreset


## 1 > 2 > 3 > 4 > 1.
static func next_preset_number(number: int) -> int:
	return number % COMFORT_PRESET_PATHS.size() + 1


## The last `--comfort-preset=N` with N in 1..4, else `START_COMFORT_PRESET`.
static func preset_number_from_args(args: PackedStringArray) -> int:
	var number: int = START_COMFORT_PRESET
	for arg: String in args:
		if not arg.begins_with(COMFORT_PRESET_ARG):
			continue
		var value: String = arg.substr(COMFORT_PRESET_ARG.length())
		var valid: bool = value.is_valid_int() and int(value) >= 1 \
			and int(value) <= COMFORT_PRESET_PATHS.size()
		number = int(value) if valid else START_COMFORT_PRESET
	return number


## The development preset switch: the upper face button of the hand that does
## not turn (Y, or B when left-handed). Read here rather than bound in the
## mapping, since it is not a flight control and a settings menu replaces it.
func preset_button() -> String:
	return "right_button_upper" if mapping.left_handed else "left_button_upper"


func _read_preset_button(buttons: Dictionary) -> void:
	var pressed: bool = bool(buttons.get(preset_button(), false))
	if pressed and not _preset_button_held:
		set_comfort_preset(next_preset_number(comfort_number))
	_preset_button_held = pressed


## Once a tick has flown the snap, later ticks before the next sample must
## not repeat it; the filter keeps the axis at zero until the stick returns.
func _end_snap_if_flown() -> void:
	if not _snap_pending or session.ticks_last_advance == 0:
		return
	_snap_pending = false
	var flown: ShipInput = input_source.latest_input()
	var turn: Vector3i = flown.turn_q
	if comfort_preset.pitch_mode == ComfortPreset.PitchMode.SNAP:
		turn.x = 0
	if comfort_preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		turn.y = 0
	input_source.set_input(ShipInput.new(flown.thrust_q, turn, flown.afterburner))


## Moves the drawn tunnel to `TUNNEL_OFFSET`, where the session's walls are.
func place_tunnel() -> void:
	var tunnel: Node3D = get_node_or_null("TestTunnel") as Node3D
	if tunnel != null:
		tunnel.position = TUNNEL_OFFSET


## Puts the rig at the ship's pose for this frame. The headset camera and
## controllers are tracked relative to the rig, so they ride along.
func place_rig() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig == null:
		return
	rig.transform = interpolated_pose(session.previous_ship(), session.current_ship(),
		session.interpolation_fraction, snap_show_angle())


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
