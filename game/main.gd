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
var mapping: ThumbstickMapping = ControlsChoice.new().apply_hands(LayoutMapping.load_file())  # #790, #875.
var keyboard: KeyboardSampler = KeyboardSampler.new()
var controllers: ControllerSampler = null  # Built from the rig's hands in `_ready`.
var scheme: ControlSchemeSwitch = ControlSchemeSwitch.from_launch()  # --controls=gripped (#739).
## Comfort preset, filter, switch and one-tick bookkeeping: input only, never ship state (CMF-6, ARC-3).
var comfort: ComfortWiring = ComfortWiring.new(input_source, mapping)

var _session_begun: bool = false
## True between the XR session beginning and stopping; picks the input device.
var _xr_running: bool = false
var _smoke_probe: XrSmokeProbe = null
## Times the hold-both-clicks way back to the start and its fade (#90).
var reset_hold: ResetHold = ResetHold.new()
## The black quad under the camera, added by `attach_fade_overlay`.
var fade_overlay: FadeOverlay = null
var head_recentre: HeadRecentre = HeadRecentre.new()  # Eye point at the ship's centre (#102).
var _resume_frame: bool = false  # Set when focus returns; the next frame may run one tick.
var status_panel: StatusPanel = null  # Under the rig, added by `attach_status_panel` (#146).
var build_info: BuildInfo = BuildInfo.load_from(BuildInfo.DEFAULT_PATH)  # On the panel; unknown in an editor.
var boost_haptics: BoostHaptics = BoostHaptics.new()  # Logs the afterburner, pulses the hand (#170).
var combat: CombatWiring = CombatWiring.new()  # Bolts, robots, shield, hull from session copies (#189, #228, MP-2).
var map: MapWiring = MapWiring.new()  # Hologram map in the hand, filled in as the ship explores (#339).
var meltdown: MeltdownWiring = MeltdownWiring.new()  # Reactor, countdown and outcome row (#359, RUN-2).
var pickup_hint: PickupHint = PickupHint.load_file()  # Fly through a part to pick it up (#606, #600).
var refresh_rate: RefreshRate = RefreshRate.new()  # Preset's rate, asked for and read back (#598).
var foveation: FoveationSwitch = FoveationSwitch.from_launch()  # --foveation switches, logged (#738).
var update: UpdateWiring = UpdateWiring.new()  # Newer-build check, debug headset builds (#646).
var destroyed: DestroyedWiring = DestroyedWiring.new()  # SHIP DESTROYED, its restart, warning pulses (#616).
var level_start: LevelStart = LevelStart.new(comfort)
var flight_test: FlightTestWiring = FlightTestWiring.new()  # First-launch flight test, CMF-4 (#715).
var break_prompt: BreakPromptWiring = BreakPromptWiring.new()  # Take-a-break prompt, CMF-10 (#716).
var vignette: VignetteWiring = VignetteWiring.new()  # Comfort vignette from the shown motion, CMF-1 (#931).
var dev_menu: DevMenuWiring = DevMenuWiring.new(scheme, mapping, comfort, break_prompt, refresh_rate, foveation)  # #763, #852, #871.
var hub: HubWiring = HubWiring.new()  # The hub between runs: craft, fit, launch (#1093).
var checklist: ChecklistWiring = ChecklistWiring.new()  # In-headset test checklist, development builds (#1325).


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
	set_comfort_preset(ComfortSwitch.number_from_launch(args))  # --comfort=custom too (#806).
	_smoke_probe = XrSmokeProbe.new(XrSmokeProbe.frames_from_args(OS.get_cmdline_user_args()))
	$XRRig.mapping = mapping  # One mapping: a remap or left-handed mode reaches the labels (#110).
	scheme.attach_models($XRRig)  # The gripped stick and throttle in the hands (#789).
	boost_haptics.left_controller = get_node_or_null("XRRig/LeftHand") as XRController3D
	boost_haptics.right_controller = get_node_or_null("XRRig/RightHand") as XRController3D
	controllers = ControllerSampler.for_controllers(
		boost_haptics.left_controller, boost_haptics.right_controller)
	var opens_hub: bool = StartChoice.opens_hub(self)  # A normal start opens the hub on a new run (#1171).
	destroyed.escape.run = level_start.choose(StartChoice.source(opens_hub, LevelSwitch.requested_path()))  # #291, #989.
	if not use_level(level_start.source): level_start.source = ""  # The tunnel flies; the panel says so (#747).
	place_tunnel()
	attach_cockpit_frame()
	attach_fade_overlay()
	attach_status_panel()
	flight_test.attach(self, comfort, level_start.source, $XRRig)  # After the panel it sits above.
	combat.attach(self)  # Main's space is the simulation's; the tunnel is offset.
	map.attach($XRRig, mapping, level_start.crew_totals_for)  # A Surveyor reveals the level (#1393).
	meltdown.attach(self, session, map.route_wiring)  # One route search for map and arrow (#695).
	destroyed.attach($XRRig, boost_haptics.left_controller, boost_haptics.right_controller, level_start)  # #1376.
	hub.attach($XRRig)
	if opens_hub: StartChoice.open_hub(hub, level_start, destroyed)  # After `destroyed` and the hub attach.
	place_rig()
	InstallerProbe.run_if_requested()  # Debug builds, only when asked (#130).
	update.attach(self, status_panel, build_info)
	break_prompt.attach($XRRig, comfort, update)  # Takes the menu tap while it shows.
	dev_menu.attach($XRRig, update, level_start, restart_level, flight_test, destroyed, null, hub.is_open, get.bind("session"))
	checklist.attach($XRRig, dev_menu, comfort, level_start, get.bind("session"), build_info.commit)  # After the menu it joins.
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


## This frame's raw values: the controllers while an XR session runs, else the keyboard (PLT-4).
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


## Maps raw values through the comfort filter to the input ticks fly until the next frame; public for tests.
func apply_controls(values: Dictionary) -> void:
	values = hub.read(destroyed.escape.read(checklist.read(dev_menu.read(values))))  # An open menu or panel takes the controls.
	var buttons: Dictionary = flight_test.read_buttons(values.get("buttons", {}), ResetHold.is_held(values))
	if comfort.read_label_button(buttons):
		$XRRig.show_labels = not $XRRig.show_labels  # View only (ARC-3, #181).
	map.buttons = buttons
	destroyed.read_buttons(buttons)
	reset_hold.press(ResetHold.is_held(values) and not flight_test.takes_menu_hold())  # Skips the test.
	var held: bool = ShipHold.is_held(dev_menu, flight_test, session, destroyed) or hub.alpha() > 0.0  # Also while the mine fades in (#1396).
	var input: ShipInput = combat.slot_input(flight_test.held(scheme.map_values(mapping, values)), values, mapping, session, held)  # #1263.
	comfort.hand_input(input, session.current_ship().orientation, reset_hold.reset_due(), held)


## Runs the simulation for one frame and moves the rig to the ship; public so tests can drive frames.
## A pending snap or reset gets a tick of its own: the frame is split where
## the next tick falls, so a hitch frame cannot fly it twice.
func advance_frame(delta_seconds: float) -> void:
	reset_hold.advance(delta_seconds)
	var resuming: bool = _resume_frame
	_resume_frame = false
	var to_tick: float = (1.0 - session.interpolation_fraction) * ShipState.TICK_DT
	if comfort.one_tick_pending and not session.paused and not hub.is_open() and delta_seconds > to_tick:
		session.advance(to_tick)
		_end_one_tick_if_flown()
		# The session limits a resumed frame to one tick; the split must too.
		session.advance(0.0 if resuming else delta_seconds - to_tick)
		_end_one_tick_if_flown()  # A later tick ends the snap's showing.
	else:
		session.advance(0.0 if hub.is_open() else delta_seconds)  # Nothing flies behind the hub (#1171).
		_end_one_tick_if_flown()
	# A paused view holds still (CMF-8), shake included.
	comfort.advance_hit_shake(0.0 if session.paused else delta_seconds)
	if hub.update(session.paused, RigViews.head_point(head_recentre), delta_seconds):  # End screens wait behind it.
		destroyed.reset()  # Their fade is done: the hub's own fades the mine in (#1396).
		restart_level(true)
	elif not hub.is_open() and destroyed.update(session, delta_seconds, head_recentre, _xr_running) \
			and not hub.open_after(level_start, session):
		restart_level()
	if fade_overlay != null:
		fade_overlay.set_alpha(maxf(maxf(reset_hold.alpha, destroyed.fade_alpha()), maxf(dev_menu.alpha, hub.alpha())))
	boost_haptics.update(session.current_ship().afterburner_active, mapping, _xr_running)  # #146, #170.
	place_rig()
	vignette.update(comfort, session, delta_seconds, get_node_or_null("XRRig"))  # View only (ARC-3).
	flight_test.update(delta_seconds, session.paused)
	break_prompt.update(delta_seconds, BreakPromptWiring.is_flying(session, flight_test, destroyed), _xr_running)
	combat.update(session, get_node_or_null("XRRig/Camera") as Node3D, status_panel, delta_seconds, hub.is_open(), level_start.run)
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
	var kept: LocalSession = session  # A run's level drops components (#1028); the tunnel's loadout too (#1050).
	session = level_start.start_or_keep(self, path, input_source, kept)
	return session != kept


## Flies the level, or a run's next one, from its start (#616) through the launch's loading path (MP-2).
## `moved_on` when the run already moved on from the ended session (the hub's launch, #1093).
func restart_level(moved_on: bool = false) -> void:
	var paused: bool = session.paused_by(LocalSession.PAUSE_FOCUS)  # The menu holds its own (#1245).
	session = level_start.fresh_session(self, input_source, null if moved_on else session)  # A run moves on first (#989).
	session.paused = paused
	meltdown.attach(self, session)
	head_recentre.request()


func place_tunnel() -> void:
	var tunnel: Node3D = get_node_or_null("TestTunnel") as Node3D
	if tunnel != null:
		tunnel.position = TUNNEL_OFFSET


## Puts the active preset's cockpit frame under the rig origin, at the head point with the status
## panel, so the head turns inside it (#478); every preset change rebuilds it there (`ComfortWiring.set_preset`).
func attach_cockpit_frame() -> void:
	var rig: Node3D = get_node_or_null("XRRig") as Node3D
	if rig != null:
		comfort.attach_cockpit_frame(rig, head_recentre)  # The swivel recentres with it (#791).
		RigViews.place(head_recentre, comfort.cockpit_frame, status_panel)


func attach_fade_overlay() -> void:
	if fade_overlay == null:
		fade_overlay = RigViews.add_fade_overlay(get_node_or_null("XRRig") as Node3D)


## Under the rig origin, not the camera, so it stays in the cockpit as the head turns.
func attach_status_panel() -> void:
	if status_panel == null:
		status_panel = RigViews.add_status_panel(get_node_or_null("XRRig") as Node3D)
		RigViews.place(head_recentre, comfort.cockpit_frame, status_panel)


## Hands the panel copies of the latest ship state; it never sees the session itself (ARC-3).
func update_status_panel(delta_seconds: float) -> void:
	if status_panel != null:
		RigViews.show_ship(status_panel, session.current_ship(), comfort.number,
			comfort.preset.display_name, refresh_rate.beside(build_info.describe()), delta_seconds, level_start.source)


## Puts the rig at the ship's pose, offset so the head sits at the ship's centre; the tracked
## camera and controllers ride along. A requested recentre takes the head pose here. The hit
## shake goes on after the pose; the cockpit frame and panel follow the head point.
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


func on_session_loss_pending() -> void:
	session.paused = true


## Pauses and hands back to the keyboard; a stopped session resumes only through `on_session_focussed`.
func on_session_stopping() -> void:
	_xr_running = false
	session.paused = true
