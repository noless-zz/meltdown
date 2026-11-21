class_name ComfortWiring
extends RefCounted

## Joins this player's comfort preset to the input the session flies (CMF-1,
## CMF-3, CMF-6, ARC-3): the active preset and its filter, the development
## preset switch, and the bookkeeping that makes a snap or a reset fly in
## exactly one tick.
##
## It sits beside `main.gd`, not in `xr/`, because it writes the `net/` input
## source; it never writes `ShipState` or `Sim` (ARC-3, MP-2). Every input it
## hands on is a whole copy of another with only the fields it means to change
## set, so a field added to `ShipInput` later cannot be dropped here (#99).

## Number (1..4, or `ComfortPresetFiles.CUSTOM_NUMBER`) of the active comfort
## preset; change it with `set_preset`.
var number: int = ComfortPresetFiles.START_NUMBER
var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
## Every frame's mapped input passes through this before the ship flies it.
var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
## True from the frame an input that must fly exactly once (a snap, or the
## reset) is set until a tick has flown it. A frame at 90 Hz runs no tick
## about one time in three, and a hitch runs several.
var one_tick_pending: bool = false
## True while the latest tick the session flew was a snap on any axis, so the
## view shows it at once instead of blending it (CMF-3, #132). Decided from the
## tick rather than from how far it turned: an auto-level roll snap can be
## smaller than any yaw or pitch snap.
var latest_tick_snapped: bool = false
## The active preset's cockpit frame under the rig origin, null until
## `attach_cockpit_frame`; placed at the head point so the head turns inside
## it (#478). `set_preset` rebuilds this one node, never two or none (CMF-1,
## #160). It only reads the preset (ARC-3).
var cockpit_frame: CockpitFrame = null
## The "Hits" row of the active preset (#169); its `preset` follows
## `set_preset`. Null when the data file was rejected: the shake stays off.
var hit_shake: HitShake = load_hit_shake(HitShake.DEFAULT_FILE)
## The shake's offset for this frame, in the cockpit's frame; the identity
## when nothing shows. `advance_hit_shake` sets it, the rig applies it.
var shake_offset: Transform3D = Transform3D.IDENTITY
## Keeps the window in front of the eyes (#651); `RigViews.place_guarded`
## feeds it each frame and places the frame and panel where it says.
var view_guard: ViewGuard = ViewGuard.new()
## The `MELTDOWN_VIEW` diagnostic lines, off unless asked for (#651).
var view_log: ViewLog = ViewLog.from_run()
## Swivel-chair yaw (CMF-7, #791): added to the input before `filter` when the
## active preset switches it on; `set_preset` hands it each new preset.
var swivel: SwivelWiring = SwivelWiring.new()

var _input_source: LatestInputSource
## Read for which hand carries the preset button.
var _mapping: ThumbstickMapping
## Where the custom comfort file is read (#806); tests point it at a scratch file.
var custom_path: String = ComfortCustom.DEFAULT_PATH
## The custom file, read once so a rejected file is logged once (#806).
var _custom: ComfortCustom = null
## Rejections of the custom file, for the status panel's preset row (#807).
var custom_notice: ComfortCustomNotice = ComfortCustomNotice.new()
## The preset switch acts once per press, not once per frame it is held.
var _preset_button_held: bool = false
## Seconds on a steady clock; `read_label_button` times a click with it. Tests
## replace it so a hold can be timed without waiting.
var clock: Callable = ClickHold.steady_seconds
## Click or hold of the label button, fed by `read_label_button` with `clock`
## each frame. The map reads it too while the label button also shows the map
## (`shared_click_hold`), so both answers come from one timer (#335).
var click_hold: ClickHold = ClickHold.new()
## The label toggle, likewise, flips once per click.
var _label_button_held: bool = false
## True while the pending one-tick input is a snap whose roll came from the
## auto-level, so that roll is not flown again before the next sample.
var _roll_snap_pending: bool = false


func _init(p_input_source: LatestInputSource, p_mapping: ThumbstickMapping) -> void:
	_input_source = p_input_source
	_mapping = p_mapping
	if hit_shake != null:
		hit_shake.preset = preset
	swivel.set_preset(preset)


## Makes preset `p_number` (1..4, or the custom mode, which needs an accepted
## file) the active one with a fresh filter. Only this player's input handling
## changes; the ship is not touched (CMF-6).
func set_preset(p_number: int) -> void:
	if p_number == ComfortPresetFiles.CUSTOM_NUMBER and not custom_available():
		push_warning("Meltdown: custom comfort mode not available, keeping preset %d" % number)
		custom_notice.refused(custom())
		p_number = number
	number = p_number
	preset = preset_for(p_number)
	filter = ComfortInputFilter.new(preset)
	one_tick_pending = false
	latest_tick_snapped = false
	_roll_snap_pending = false
	if cockpit_frame != null:
		cockpit_frame.set_spec(cockpit_spec())
	if hit_shake != null:
		hit_shake.preset = preset
	swivel.set_preset(preset)
	print("Meltdown: comfort preset %d %s" % [p_number, preset.display_name])
	view_log.event("preset=%d rebuilt=cockpit_frame,input_filter,hit_shake frame_point=unchanged" % p_number)


## The preset numbered `p_number`; the custom file's for `CUSTOM_NUMBER`.
func preset_for(p_number: int) -> ComfortPreset:
	if p_number == ComfortPresetFiles.CUSTOM_NUMBER:
		return custom().preset
	return ComfortPresetFiles.load_number(p_number)


## The custom comfort file at `custom_path`, read on first use and kept. A
## rejected file is logged then by `ComfortCustom`, naming the field.
func custom() -> ComfortCustom:
	if _custom == null:
		_custom = ComfortCustom.load_from(custom_path)
	return _custom


## True when the custom file exists and was accepted whole.
func custom_available() -> bool:
	return custom().preset != null and custom().error.is_empty()


## The preset after the active one: 1 > 2 > 3 > 4 > Custom > 1 with an
## accepted custom file, 1 > 2 > 3 > 4 > 1 without (CMF-1, #806).
func next_number() -> int:
	if number == ComfortPresetFiles.CUSTOM_NUMBER:
		return 1
	if number == ComfortPresetFiles.PATHS.size() and custom_available():
		return ComfortPresetFiles.CUSTOM_NUMBER
	return ComfortPresetFiles.next_number(number)


## Builds the active preset's cockpit frame under `rig`, the rig origin, not
## its camera: the frame is fixed to the ship and the head looks around inside
## it (#478). Does nothing once a frame exists; `set_preset` rebuilds it in place.
## Created here rather than with the wiring, so a wiring that never reaches
## a scene owns no node. With `recentre`, the swivel reads the rig's camera
## and recentres with every pose it takes (#791).
func attach_cockpit_frame(rig: Node3D, recentre: HeadRecentre = null) -> void:
	if recentre != null:
		swivel.attach(rig, recentre)
	if cockpit_frame != null:
		return
	cockpit_frame = CockpitFrame.new(cockpit_spec())
	rig.add_child(cockpit_frame)


## The cockpit named by the active preset. A rejected file still gives a frame
## (the spec's defaults) so the view is never left without one, and says why.
func cockpit_spec() -> CockpitSpec:
	var spec: CockpitSpec = CockpitSpec.for_preset(preset)
	if spec.error != "":
		push_warning("Meltdown: cockpit for preset %d rejected, using defaults: %s" % [number, spec.error])
	return spec


## The development preset switch: the lower face button of the hand that does
## not turn (X, or A when left-handed; #613). Read here rather than bound in
## the layout, since it is not a flight control and a settings menu replaces it.
func preset_button() -> String:
	return _mapping.preset_button()


## Next preset as the button goes down; from 4 a rejected custom file is reported (#807).
func read_preset_button(buttons: Dictionary) -> void:
	var pressed: bool = bool(buttons.get(preset_button(), false))
	if pressed and not _preset_button_held:
		if number == ComfortPresetFiles.PATHS.size():
			custom_notice.refused(custom())
		set_preset(next_number())
	_preset_button_held = pressed


## The control-label toggle: the stick click of the hand that does not turn
## (left, or right when left-handed), as decision record 0004 places it. Read
## here like the preset button; it never reaches `ShipInput` (ARC-3).
func label_button() -> String:
	return _mapping.label_button()


## True on the one frame a click should flip the labels. When the label
## button also shows the map (`show_map`, #314), that is the release of a
## click shorter than `MapHologram.HOLD_SECONDS`, as `click_hold` decides, so
## holding for the map never flips them; otherwise it is the frame the button
## goes down. Call once per frame, before the map reads `shared_click_hold`.
func read_label_button(buttons: Dictionary) -> bool:
	var pressed: bool = bool(buttons.get(label_button(), false))
	var went_down: bool = pressed and not _label_button_held
	_label_button_held = pressed
	if not label_button_shows_map():
		return went_down
	click_hold.feed(pressed, float(clock.call()))
	return click_hold.short_click_released()


## True while `show_map` is bound to the label button.
func label_button_shows_map() -> bool:
	return _mapping.physical_controls("show_map").has(label_button())


## The `ClickHold` the map must read while it shares the label button, null
## when `show_map` is on another control and the map times its own hold.
func shared_click_hold() -> ClickHold:
	return click_hold if label_button_shows_map() else null


## Hands this frame's mapped `input` to the session's input source.
## `orientation` is the ship's, read only, for the pitch limit and auto-level.
## `reset_due` replaces the input with a still reset tick; `ship_held` stops the swivel (#819).
func hand_input(input: ShipInput, orientation: Basis, reset_due: bool, ship_held: bool = false) -> void:
	if one_tick_pending:
		var held: ShipInput = _input_source.latest_input()
		if held.reset_to_start:
			return  # A pending reset flies whole.
		# No tick has flown the snap yet: keep its turn, take everything else new.
		var next: ShipInput = ComfortInputFilter.copy_input(input)
		next.turn_q = held.turn_q
		_input_source.set_input(next)
		return
	var filtered: ShipInput = filter.filter(swivel.added(input, ship_held), orientation)
	var snapped: bool = filter.produced_snap and not reset_due
	_roll_snap_pending = snapped and filter.produced_roll_snap
	if reset_due:
		# Still and not firing, so the reset tick ends exactly at the start pose.
		filtered.thrust_q = Vector3i.ZERO
		filtered.turn_q = Vector3i.ZERO
		filtered.afterburner = false
		filtered.fire_primary = false
		filtered.reset_to_start = true
	one_tick_pending = snapped or filtered.reset_to_start
	_input_source.set_input(filtered)


## Call after the session advanced `ticks` ticks. Once a tick has flown a snap
## or the reset, later ticks before the next sample must not repeat it; the
## filter keeps a snapped axis at zero until the stick returns. Returns true
## when the flown input was the reset, so the caller can fade back in.
## Call after every advance, including the second half of a split frame, so
## `latest_tick_snapped` drops once a later tick has flown.
func end_one_tick_if_flown(ticks: int) -> bool:
	if ticks == 0:
		return false
	latest_tick_snapped = false
	if not one_tick_pending:
		return false
	one_tick_pending = false
	var flown: ShipInput = ComfortInputFilter.copy_input(_input_source.latest_input())
	if flown.reset_to_start:
		# Nothing is held until the next sample.
		_input_source.set_input(ShipInput.new())
		return true
	if preset.pitch_mode == ComfortPreset.PitchMode.SNAP:
		flown.turn_q.x = 0
	if preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		flown.turn_q.y = 0
	if _roll_snap_pending:
		flown.turn_q.z = 0
	_roll_snap_pending = false
	# The caller splits the frame so a pending snap flies in a tick of its own.
	latest_tick_snapped = ticks == 1
	_input_source.set_input(flown)
	return false


## Reads the hit-shake file at `path`. A rejected file is printed once, here,
## and gives null, so no shake shows rather than one with guessed values.
static func load_hit_shake(path: String) -> HitShake:
	var shake: HitShake = HitShake.load_file(path)
	if shake.error != "":
		print("Meltdown: hit shake off: %s" % shake.error)
		return null
	return shake


## Hands the shake the events of the ticks just run, for ship `ship` whose
## orientation is `ship_basis`. Read only: the events and basis are copies.
func feed_hit_shake(events: Array[SimEvent], ship: int, ship_basis: Basis) -> void:
	if hit_shake != null:
		hit_shake.feed(events, ship, ship_basis)


## Moves the shake on by one frame of `delta` seconds and keeps its offset.
func advance_hit_shake(delta: float) -> void:
	shake_offset = hit_shake.advance(delta) if hit_shake != null else Transform3D.IDENTITY


## The ship's pose `fraction` of the way from `previous` to `current`:
## position lerped, rotation slerped. Frames fall between ticks, so showing
## either tick's pose alone would judder at 72 or 90 Hz against a 60 Hz sim.
## With `snapped` (the latest tick was a snap) the rotation is shown at once:
## slerping it would show a snap as smooth rotation (CMF-3).
static func interpolated_pose(previous: ShipState, current: ShipState, fraction: float,
		snapped: bool = false) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var from_rotation: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to_rotation: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	var rotation: Quaternion = to_rotation if snapped else from_rotation.slerp(to_rotation, weight)
	return Transform3D(Basis(rotation), previous.position.lerp(current.position, weight))
