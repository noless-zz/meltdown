extends RefCounted

## Holding the left menu button to return to the start, behind a fade (#90,
## #162):
## FLT-1, CMF-8, PLT-5, ARC-3, MP-2. The main-scene tests go through the real
## input path: sampled values, the active comfort filter, `LatestInputSource`
## and the simulation.

const FRAME: float = 1.0 / 90.0
const MENU: Dictionary = {ResetHold.BUTTON: true}
## The gesture before #162; it no longer resets.
const BOTH_CLICKS: Dictionary = {"left_stick_click": true, "right_stick_click": true}
const KEY: Dictionary = {ResetHold.KEYBOARD_BUTTON: true}


## The main scene with a ship the tunnel's robots cannot destroy in these
## tests: they are about the reset gesture, and since #601 a destroyed ship
## refuses the reset.
func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return null
	var main: Node = scene.instantiate()
	var ship: ShipState = _session(main).sim.ships[0]
	ship.max_hull *= 100.0
	ship.hull = ship.max_hull
	return main


static func _values(left_stick: Vector2 = Vector2.ZERO, buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = left_stick
	values["buttons"] = buttons
	return values


static func _frames(main: Node, values: Dictionary, count: int) -> void:
	for i: int in count:
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


## Flies forward and sideways for a second so the ship is well away from the start.
static func _fly_away(main: Node) -> void:
	_frames(main, _values(Vector2(0.6, 1.0)), 90)


static func _session(main: Node) -> LocalSession:
	return main.get("session") as LocalSession


## Tick indices whose recorded input asked for the reset.
static func _reset_ticks(main: Node) -> Array[int]:
	var ticks: Array[int] = []
	var frames: Array[Array] = _session(main).replay.frames
	for i: int in frames.size():
		if (frames[i][0] as ShipInput).reset_to_start:
			ticks.append(i)
	return ticks


static func _at_start(main: Node) -> String:
	var sim: Sim = _session(main).sim
	var ship: ShipState = sim.ships[0]
	if not ship.position.is_equal_approx(sim.start_positions[0]):
		return "ship at %s, start is %s" % [ship.position, sim.start_positions[0]]
	if not ship.orientation.is_equal_approx(sim.start_orientations[0]):
		return "ship orientation %s is not the start's" % ship.orientation
	if ship.velocity != Vector3.ZERO:
		return "ship still moving at %s" % ship.velocity
	return ""


func test_the_gesture_is_the_left_menu_button_or_the_key() -> String:
	if ResetHold.BUTTON != "left_menu" or ResetHold.BUTTON != ControllerSampler.MENU_BUTTON:
		return "the reset button is '%s', not the sampler's left menu button" % ResetHold.BUTTON
	if not ResetHold.is_held(_values(Vector2.ZERO, MENU)):
		return "the left menu button is not the gesture"
	if ResetHold.is_held(_values(Vector2.ZERO, BOTH_CLICKS)) \
			or ResetHold.is_held(_values(Vector2.ZERO, {"left_stick_click": true})):
		return "stick clicks are still the gesture"
	if ResetHold.is_held(_values(Vector2.ZERO, {"right_menu": true})):
		return "a right menu button is the gesture"
	if not ResetHold.is_held(_values(Vector2.ZERO, KEY)):
		return "the keyboard button is not the gesture"
	if ResetHold.KEYBOARD_KEY != KEY_BACKSPACE or ResetHold.RESET_HOLD_SECONDS != 1.0 \
			or ResetHold.FADE_SECONDS != 0.25:
		return "the key, hold time or fade time changed"
	return ""


func test_fade_follows_the_stated_timings() -> String:
	var hold: ResetHold = ResetHold.new()
	hold.press(true)
	var step: float = 0.01
	for i: int in 99:
		hold.advance(step)
	if hold.phase != ResetHold.Phase.IDLE or hold.alpha != 0.0:
		return "faded before the hold reached a second"
	hold.advance(step)
	if hold.phase != ResetHold.Phase.FADING_OUT or not is_equal_approx(hold.alpha, 0.04):
		return "the firing step left alpha %.3f in phase %d" % [hold.alpha, hold.phase]
	for i: int in 9:
		hold.advance(step)
	if not is_equal_approx(hold.alpha, 0.4):
		return "0.1 s into the fade out alpha is %.3f, not 0.4" % hold.alpha
	for i: int in 14:
		hold.advance(step)
	if hold.reset_due() or hold.alpha >= 1.0:
		return "black before 0.25 s"
	hold.advance(step)
	if not hold.reset_due() or hold.alpha != 1.0:
		return "not black after 0.25 s (alpha %.3f)" % hold.alpha
	hold.advance(1.0)
	if not hold.reset_due():
		return "the view cleared before the reset was flown"
	hold.reset_flown()
	for i: int in 10:
		hold.advance(step)
	if not is_equal_approx(hold.alpha, 0.6):
		return "0.1 s into the fade in alpha is %.3f, not 0.6" % hold.alpha
	for i: int in 15:
		hold.advance(step)
	if hold.phase != ResetHold.Phase.IDLE or hold.alpha != 0.0:
		return "not clear 0.25 s after the reset (alpha %.3f)" % hold.alpha
	return ""


func test_a_short_hold_does_nothing() -> String:
	var main: Node = _main()
	_fly_away(main)
	_frames(main, _values(Vector2.ZERO, MENU), 45)
	_frames(main, _values(), 90)
	_frames(main, _values(Vector2.ZERO, MENU), 45)
	_frames(main, _values(), 90)
	var resets: Array[int] = _reset_ticks(main)
	var alpha: float = (main.get("reset_hold") as ResetHold).alpha
	var away: Vector3 = _session(main).current_ship().position
	main.free()
	if not resets.is_empty():
		return "two holds of 0.5 s reset at ticks %s" % [resets]
	if alpha != 0.0:
		return "a short hold faded the view to %.3f" % alpha
	if away.length() < 1.0:
		return "the ship is back near the start at %s" % away
	return ""


## The old gesture (#90) held for two seconds no longer resets or fades.
func test_both_stick_clicks_no_longer_reset() -> String:
	var main: Node = _main()
	_fly_away(main)
	_frames(main, _values(Vector2.ZERO, BOTH_CLICKS), 180)
	var resets: Array[int] = _reset_ticks(main)
	var hold: ResetHold = main.get("reset_hold")
	var alpha: float = hold.alpha
	var held: float = hold.held_seconds
	main.free()
	if not resets.is_empty() or alpha != 0.0 or held != 0.0:
		return "both clicks for 2 s reset at %s, alpha %.3f, held %.2f s" % [resets, alpha, held]
	return ""


## The flat build's Backspace, as `main.gd` passes it, still resets once.
func test_the_keyboard_hold_still_resets() -> String:
	var main: Node = _main()
	_fly_away(main)
	_frames(main, _values(Vector2.ZERO, KEY), 150)
	var resets: Array[int] = _reset_ticks(main)
	var failure: String = _at_start(main)
	main.free()
	if resets.size() != 1:
		return "holding the key for 1.67 s reset at ticks %s" % [resets]
	if failure != "":
		return "after the keyboard reset: " + failure
	return ""


func test_a_full_hold_resets_once_after_black_in_every_preset() -> String:
	for number: int in range(1, 5):
		var main: Node = _main()
		main.call("set_comfort_preset", number)
		_fly_away(main)
		var hold: ResetHold = main.get("reset_hold")
		var ticks_at_black: int = -1
		var start_failure: String = "never reset"
		for i: int in 300:
			_frames(main, _values(Vector2.ZERO, MENU), 1)
			if ticks_at_black < 0 and hold.alpha >= 1.0:
				ticks_at_black = _session(main).sim.tick
			# Checked on the frame that flew the reset; the held button thrusts nothing after it.
			if start_failure == "never reset" and _reset_ticks(main).size() == 1:
				start_failure = _at_start(main)
		var resets: Array[int] = _reset_ticks(main)
		var flown: ShipInput = _session(main).replay.frames[resets[0]][0] if resets.size() == 1 else null
		main.free()
		if resets.size() != 1:
			return "preset %d: holding on for 3.3 s reset at ticks %s" % [number, resets]
		if ticks_at_black < 0 or resets[0] < ticks_at_black:
			return "preset %d: reset at tick %d, the view was black at tick %d" % [number, resets[0], ticks_at_black]
		if start_failure != "":
			return "preset %d after the reset tick: %s" % [number, start_failure]
		# The reset tick flies nothing else.
		if flown.afterburner or flown.thrust_q != Vector3i.ZERO or flown.turn_q != Vector3i.ZERO:
			return "preset %d: the reset tick also flew %s %s" % [number, flown.thrust_q, flown.turn_q]
	return ""


func test_release_and_hold_again_resets_again() -> String:
	var main: Node = _main()
	_fly_away(main)
	_frames(main, _values(Vector2.ZERO, MENU), 150)
	_frames(main, _values(), 2)
	_fly_away(main)
	_frames(main, _values(Vector2.ZERO, MENU), 150)
	var resets: Array[int] = _reset_ticks(main)
	var failure: String = _at_start(main)
	main.free()
	if resets.size() != 2:
		return "two holds reset at ticks %s" % [resets]
	if failure != "":
		return "after the second reset: " + failure
	return ""


func test_a_hitch_frame_flies_the_reset_only_once() -> String:
	var main: Node = _main()
	_fly_away(main)
	var hold: ResetHold = main.get("reset_hold")
	# Bounded, so a gesture that never fires fails here instead of hanging the run.
	var frames: int = 0
	while not hold.reset_due() and frames < 600:
		_frames(main, _values(Vector2.ZERO, MENU), 1)
		frames += 1
	if not hold.reset_due():
		main.free()
		return "the reset never came due"
	main.call("apply_controls", _values(Vector2.ZERO, MENU))
	main.call("advance_frame", 0.1)
	var resets: Array[int] = _reset_ticks(main)
	main.free()
	if resets.size() != 1:
		return "a 0.1 s frame flew the reset at ticks %s" % [resets]
	return ""


func test_the_overlay_shows_the_fade_under_the_camera() -> String:
	var main: Node = _main()
	main.call("attach_fade_overlay")
	main.call("attach_fade_overlay")
	var overlay: FadeOverlay = main.get("fade_overlay")
	var camera: Node = main.get_node("XRRig/Camera")
	if overlay == null or overlay.get_parent() != camera:
		main.free()
		return "no overlay under the camera"
	var count: int = 0
	for child: Node in camera.get_children():
		count += 1 if child is FadeOverlay else 0
	var hidden_at_start: bool = not overlay.visible
	var hold: ResetHold = main.get("reset_hold")
	var mismatch: String = ""
	for i: int in 200:
		_frames(main, _values(Vector2.ZERO, MENU), 1)
		if mismatch == "" and not is_equal_approx(overlay.get_alpha(), hold.alpha):
			mismatch = "frame %d: overlay %.3f, fade %.3f" % [i, overlay.get_alpha(), hold.alpha]
	var hidden_at_end: bool = not overlay.visible
	var material: StandardMaterial3D = overlay.material_override as StandardMaterial3D
	# Read before main.free(): the overlay is freed with it.
	var is_quad: bool = overlay.mesh is QuadMesh
	main.free()
	if count != 1:
		return "%d overlays under the camera" % count
	if not hidden_at_start or not hidden_at_end:
		return "the overlay is visible while clear"
	if mismatch != "":
		return mismatch
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or not is_quad:
		return "the overlay is not one unshaded quad"
	return ""
