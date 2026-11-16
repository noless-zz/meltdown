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
## The comfort preset, its filter and switch, and the one-tick bookkeeping.
## It only changes the input this player sends, never ship state (CMF-6, ARC-3).
var comfort: ComfortWiring = ComfortWiring.new(input_source, mapping)

var _session_begun: bool = false
## True between the XR session beginning and stopping; picks the input device.
var _xr_running: bool = false
var _smoke_probe: XrSmokeProbe = null
## Times the hold-both-clicks way back to the start and its fade (#90).
var reset_hold: ResetHold = ResetHold.new()
## The black quad under the camera, added by `attach_fade_overlay`.
var fade_overlay: FadeOverlay = null
## Keeps the eye point at the ship's centre, inside its collision sphere (#102).
var head_recentre: HeadRecentre = HeadRecentre.new()
## Set when focus returns; the frame after a pause may run only one tick.
var _resume_frame: bool = false
## The panel under the rig, added by `attach_status_panel` (#146).
var status_panel: StatusPanel = null
## Which build this is, shown on the status panel; unknown in an editor run.
var build_info: BuildInfo = BuildInfo.load_from(BuildInfo.DEFAULT_PATH)
## The afterburner state last logged, so each start and stop is logged once.
var _afterburner_logged: bool = false


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
	attach_cockpit_frame()
	attach_fade_overlay()
	attach_status_panel()
	place_rig()
	InstallerProbe.run_if_requested()  # Debug builds, only when asked (#130).
	AcceptanceRunner.start_if_requested(self)  # Only with --acceptance=<suite> (#165).


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
	comfort.read_preset_button(values.get("buttons", {}))
	reset_hold.press(ResetHold.is_held(values))
	comfort.hand_input(ControllerSampler.map_values(mapping, values),
		session.current_ship().orientation, reset_hold.reset_due())


## Runs the simulation for one frame of `delta_seconds` and moves the rig to
## the ship. Public so tests can drive frames without a running scene tree.
## A pending snap or reset gets a tick of its own: the frame is split where
## the next tick falls, so a hitch frame cannot fly it twice.
func advance_frame(delta_seconds: float) -> void:
	reset_hold.advance(delta_seconds)
	var resuming: bool = _resume_frame
	_resume_frame = false
	var to_tick: float = (1.0 - session.interpolation_fraction) * ShipState.TICK_DT
	if comfort.one_tick_pending and not session.paused and delta_seconds > to_tick:
		session.advance(to_tick)
		_end_one_tick_if_flown()
		# The session limits a resumed frame to one tick; the split must too.
		session.advance(0.0 if resuming else delta_seconds - to_tick)
		_end_one_tick_if_flown()  # A later tick ends the snap's showing.
	else:
		session.advance(delta_seconds)
		_end_one_tick_if_flown()
	if fade_overlay != null:
		fade_overlay.set_alpha(reset_hold.alpha)
	log_afterburner()
	place_rig()
	update_status_panel(delta_seconds)


## Makes preset `number` (1..4) the active one; see `ComfortWiring.set_preset`.
func set_comfort_preset(number: int) -> void:
	comfort.set_preset(number)


## A flown reset is followed by the fade back in and a recentre.
func _end_one_tick_if_flown() -> void:
	if comfort.end_one_tick_if_flown(session.ticks_last_advance):
		reset_hold.reset_flown()
		head_recentre.request()


## Moves the drawn tunnel to `TUNNEL_OFFSET`, where the session's walls are.
func place_tunnel() -> void:
	var tunnel: Node3D = get_node_or_null("TestTunnel") as Node3D
	if tunnel != null:
		tunnel.position = TUNNEL_OFFSET


## Puts the active preset's cockpit frame under the rig's camera, as the fade
## quad is; every preset change rebuilds it there (`ComfortWiring.set_preset`).
func attach_cockpit_frame() -> void:
	var camera: Node3D = get_node_or_null("XRRig/Camera") as Node3D
	if camera != null:
		comfort.attach_cockpit_frame(camera)


## Puts the fade quad under the rig's camera; the rig scene stays as it is.
func attach_fade_overlay() -> void:
	var camera: Node3D = get_node_or_null("XRRig/Camera") as Node3D
	if camera != null and fade_overlay == null:
		fade_overlay = FadeOverlay.new()
		camera.add_child(fade_overlay)


## Puts the status panel under the rig origin, not the camera, so it stays in
## the cockpit while the head turns; `update_status_panel` places it.
func attach_status_panel() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig != null and status_panel == null:
		status_panel = StatusPanel.new()
		rig.add_child(status_panel)


## Hands the panel this frame's values, read from copies of the latest ship
## state; the panel never sees the session itself (ARC-3).
func update_status_panel(delta_seconds: float) -> void:
	if status_panel == null:
		return
	# The ship's centre sits at the recentred head point in the rig's space.
	status_panel.transform = StatusPanel.rig_transform(head_recentre.offset.affine_inverse())
	var ship: ShipState = session.current_ship()
	var boost: String = ""
	if ship.afterburner_active:
		boost = StatusPanel.BOOST_ON
	elif ship.afterburner_locked:
		boost = StatusPanel.BOOST_RECHARGING
	var energy_fraction: float = ship.energy / ship.max_energy if ship.max_energy > 0.0 else 0.0
	status_panel.show_values(comfort.number, comfort.preset.display_name, ship.velocity.length(),
		energy_fraction, boost, build_info.describe())
	status_panel.advance(delta_seconds)


## Logs each afterburner start and stop, so a device log shows whether the
## stick click reaches the simulation (#146). Read from the latest state once
## per frame: `Sim.last_events` only holds the last tick of a frame, so an
## event on an earlier tick of a multi-tick frame would be missed.
func log_afterburner() -> void:
	var active: bool = session.current_ship().afterburner_active
	if active != _afterburner_logged:
		_afterburner_logged = active
		print("Meltdown: afterburner %s" % ("on" if active else "off"))


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
	rig.transform = head_recentre.rig_transform(ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, comfort.latest_tick_snapped))


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
