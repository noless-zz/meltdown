extends Node3D

## Entry scene. Starts an XR session when an OpenXR runtime is present and falls back to a
## flat window otherwise, so the same build runs on the headset, the desktop and headless CI
## (PLT-2, PLT-4). The scene also flies the local ship: `LocalSession` owns the simulation and
## the rig follows the simulated ship, so the view moves only with the ship's simulated
## motion (CMF-8). The rig reads copies of the ship and never writes simulation state (MP-2, ARC-3).

## Kept here, where tests read them, since #616 moved them to `LevelStart`.
const TUNNEL_OFFSET: Vector3 = LevelStart.TUNNEL_OFFSET
const SHIP_TUNING_PATH: String = LevelStart.SHIP_TUNING_PATH
const ROBOT_SPAWNS_PATH: String = LevelStart.ROBOT_SPAWNS_PATH

## Where each frame's sampled input goes; every tick until the next frame flies it.
var input_source: LatestInputSource = LatestInputSource.new()
## The test tunnel's session until `use_level` replaces it (`LevelStart.tunnel_session`).
var session: LocalSession = LevelStart.tunnel_session(input_source)
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
## Logs each afterburner start and stop and pulses the boosting hand (#170).
var boost_haptics: BoostHaptics = BoostHaptics.new()
## The bolts, robots, shield and hull, shown from session copies (#189, #228, MP-2).
var combat: CombatWiring = CombatWiring.new()
var map: MapWiring = MapWiring.new()  # Hologram map in the hand, filled in as the ship explores (#339).
var meltdown: MeltdownWiring = MeltdownWiring.new()  # Reactor, countdown and outcome row (#359, RUN-2).
## When the slot label says to fly through a part to pick it up (#606, #600).
var pickup_hint: PickupHint = PickupHint.load_file()
var refresh_rate: RefreshRate = RefreshRate.new()  # Preset's rate, asked for and read back (#598).
var foveation: FoveationSwitch = FoveationSwitch.from_launch()  # --foveation switches, logged (#738).
var update: UpdateWiring = UpdateWiring.new()  # Newer-build check, debug headset builds (#646).
## SHIP DESTROYED and the restart of what the launch flies, and the warning pulses (#616).
var destroyed: DestroyedWiring = DestroyedWiring.new()
var level_start: LevelStart = LevelStart.new()
var flight_test: FlightTestWiring = FlightTestWiring.new()  # First-launch flight test, CMF-4 (#715).


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
	boost_haptics.left_controller = get_node_or_null("XRRig/LeftHand") as XRController3D
	boost_haptics.right_controller = get_node_or_null("XRRig/RightHand") as XRController3D
	controllers = ControllerSampler.for_controllers(
		boost_haptics.left_controller, boost_haptics.right_controller)
	level_start.source = LevelSwitch.requested_path()  # Only with --level=<name> (#291) or --seed=<n> (#382).
	use_level(level_start.source)
	place_tunnel()
	attach_cockpit_frame()
	attach_fade_overlay()
	attach_status_panel()
	flight_test.attach(self, comfort, level_start.source, $XRRig)  # After the panel it sits above.
	combat.attach(self)  # Main's space is the simulation's; the tunnel is offset.
	map.attach($XRRig, mapping)
	meltdown.attach(self, session, map.route_wiring)  # One route search for map and arrow (#695).
	destroyed.attach($XRRig, boost_haptics.left_controller, boost_haptics.right_controller)
	place_rig()
	InstallerProbe.run_if_requested()  # Debug builds, only when asked (#130).
	update.attach(self, status_panel, build_info)
	AcceptanceRunner.start_if_requested(self)  # Only with --acceptance=<suite> (#165).


func _process(delta: float) -> void:
	apply_controls(sample_controls())
	advance_frame(delta)
	refresh_rate.advance_frame()
	foveation.advance(delta)
	if _smoke_probe != null and _smoke_probe.is_enabled():
		_smoke_probe.watch_hands(boost_haptics.left_controller, boost_haptics.right_controller)
	if _smoke_probe != null and _smoke_probe.tick():
		print(_smoke_probe.report(_session_begun))
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
	var buttons: Dictionary = flight_test.read_buttons(values.get("buttons", {}), ResetHold.is_held(values))
	comfort.read_preset_button(buttons)
	if comfort.read_label_button(buttons):
		$XRRig.show_labels = not $XRRig.show_labels  # View only (ARC-3, #181).
	map.buttons = buttons
	destroyed.read_buttons(buttons)
	reset_hold.press(ResetHold.is_held(values) and not flight_test.takes_menu_hold())  # Skips the test.
	update.press_menu(ResetHold.is_held(values))  # A tap shorter than the reset hold.
	comfort.hand_input(flight_test.held(ControllerSampler.map_values(mapping, values)),
		session.current_ship().orientation, reset_hold.reset_due())


## Runs the simulation for one frame and moves the rig to the ship; public so tests can drive frames.
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
	# A paused view holds still (CMF-8), shake included.
	comfort.advance_hit_shake(0.0 if session.paused else delta_seconds)
	if destroyed.update(session, delta_seconds, head_recentre, _xr_running):
		restart_level()
	if fade_overlay != null:
		fade_overlay.set_alpha(maxf(reset_hold.alpha, destroyed.fade_alpha()))
	boost_haptics.update(session.current_ship().afterburner_active, mapping, _xr_running)  # #146, #170.
	place_rig()
	flight_test.update(delta_seconds, session.paused)
	combat.update(session, get_node_or_null("XRRig/Camera") as Node3D, status_panel, delta_seconds)
	$XRRig.pickup_hint = pickup_hint.is_due(session.current_ship(), session.current_salvage())  # View only.
	map.update(session, delta_seconds, comfort.shared_click_hold())
	meltdown.update(session, status_panel)
	update_status_panel(delta_seconds)


## Makes preset `number` (1..4) the active one; see `ComfortWiring.set_preset`.
func set_comfort_preset(number: int) -> void:
	comfort.set_preset(number)
	refresh_rate.apply(comfort.preset)  # Display only; the tick stays at 60 Hz (ARC-3).


## Runs after every `session.advance`. The ticks' wall impacts reach the hit
## shake with the ship's orientation (#169). A flown reset is followed by the
## fade back in and a recentre.
func _end_one_tick_if_flown() -> void:
	comfort.feed_hit_shake(session.frame_events(), 0, session.current_ship().orientation)
	combat.feed_events(session.frame_events(), session.current_ship(), _xr_running)  # #618.
	if comfort.end_one_tick_if_flown(session.ticks_last_advance):
		reset_hold.reset_flown()
		head_recentre.request()


## Flies the level file at `path` in place of the test tunnel (#291): a new
## session in the level's walls, from its start, with its robots, and the
## level drawn where the tunnel was. Call it before the first frame. Returns
## false, leaving the tunnel and its session, for "" or a rejected file.
func use_level(path: String) -> bool:
	var fresh: LocalSession = LevelStart.level_session(self, path, input_source)
	session = fresh if fresh != null else session
	return fresh != null


## Flies the level again from its start (#616) through the launch's loading path (MP-2).
func restart_level() -> void:
	var paused: bool = session.paused
	session = level_start.fresh_session(self, input_source)
	session.paused = paused
	meltdown.attach(self, session)
	head_recentre.request()


## Moves the drawn tunnel to `TUNNEL_OFFSET`, where the session's walls are.
func place_tunnel() -> void:
	var tunnel: Node3D = get_node_or_null("TestTunnel") as Node3D
	if tunnel != null:
		tunnel.position = TUNNEL_OFFSET


## Puts the active preset's cockpit frame under the rig origin, at the head
## point with the status panel, so the head turns inside it (#478); every
## preset change rebuilds it there (`ComfortWiring.set_preset`).
func attach_cockpit_frame() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig != null:
		comfort.attach_cockpit_frame(rig)
		RigViews.place(head_recentre, comfort.cockpit_frame, status_panel)


## Puts the fade quad under the rig's camera; the rig scene stays as it is.
func attach_fade_overlay() -> void:
	if fade_overlay == null:
		fade_overlay = RigViews.add_fade_overlay(get_node_or_null("XRRig") as Node3D)


## Puts the status panel under the rig origin, not the camera, so it stays in
## the cockpit while the head turns; `place_rig` places it.
func attach_status_panel() -> void:
	if status_panel == null:
		status_panel = RigViews.add_status_panel(get_node_or_null("XRRig") as Node3D)
		RigViews.place(head_recentre, comfort.cockpit_frame, status_panel)


## Hands the panel copies of the latest ship state; it never sees the session itself (ARC-3).
func update_status_panel(delta_seconds: float) -> void:
	if status_panel != null:
		RigViews.show_ship(status_panel, session.current_ship(), comfort.number,
			comfort.preset.display_name, refresh_rate.beside(build_info.describe()), delta_seconds)


## Puts the rig at the ship's pose for this frame, offset so the head sits at
## the ship's centre. The headset camera and controllers are tracked relative
## to the rig, so they ride along. A requested recentre takes the head pose here.
## The hit shake goes on after the pose, in the cockpit's own frame. The
## cockpit frame and panel follow the head point, so a recentre moves both.
func place_rig() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig == null:
		return
	var camera: Node3D = rig.get_node_or_null("Camera") as Node3D
	if camera != null:
		head_recentre.update(camera.transform, _xr_running)
	var pose: Transform3D = ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, comfort.latest_tick_snapped)
	rig.transform = head_recentre.rig_transform(pose * comfort.shake_offset)
	RigViews.place_guarded(head_recentre, comfort, status_panel, camera, session.current_ship(), _xr_running)


func _on_session_begun(openxr: OpenXRInterface) -> void:
	_session_begun = true
	_xr_running = true
	head_recentre.request()
	refresh_rate.begin(openxr, comfort.preset)  # PRF-1, CMF-1 (#598).
	foveation.begin(openxr)  # Before the first frame is drawn (#738).


## The app is shown but has lost input focus: the headset was taken off or the
## system menu is up. Solo play holds still until focus returns (PLT-7). The
## runtime passes through here on the way to focus at start; nothing has flown yet.
func on_session_visible() -> void:
	session.paused = true


## Focus is back; the session limits the next frame to one tick, so the ship does not jump (CMF-8).
func on_session_focussed() -> void:
	session.paused = false
	_resume_frame = true


## The runtime is about to lose the session; nothing should move meanwhile.
func on_session_loss_pending() -> void:
	session.paused = true


## Pauses and hands back to the keyboard; a stopped session resumes only through `on_session_focussed`.
func on_session_stopping() -> void:
	_xr_running = false
	session.paused = true
