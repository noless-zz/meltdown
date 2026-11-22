extends RefCounted

## Choosing in the dev menu never flies the ship (#1206, PLT-5, MP-2, ARC-3):
## while the menu is open, on the frame it closes and until every control it
## was using has been released once, the session gets neutral input.

const FRAME: float = 1.0 / 72.0
const A: String = "right_button_lower"


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


static func _neutral(input: ShipInput) -> bool:
	return input.thrust_q == Vector3i.ZERO and input.turn_q == Vector3i.ZERO \
		and not input.afterburner and not input.fire_primary


## A main scene with its rig built and the menu opened by a tap.
static func _main_with_menu() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	main.call("apply_controls", _values({ControllerSampler.MENU_BUTTON: true}))
	main.call("apply_controls", _values())
	return main


## One frame through `main`; returns why the input or speed is wrong, or "".
static func _frame(main: Node, values: Dictionary, start_speed: float, label: String) -> String:
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)
	var input: ShipInput = (main.get("input_source") as LatestInputSource).latest_input()
	if not _neutral(input):
		return "%s: the session got thrust %s, turn %s, boost %s, fire %s" % [
			label, input.thrust_q, input.turn_q, input.afterburner, input.fire_primary]
	var speed: float = (main.get("session") as LocalSession).current_ship().velocity.length()
	if speed > start_speed + 0.0001:
		return "%s: the ship's speed grew from %.4f to %.4f" % [label, start_speed, speed]
	return ""


func test_stepping_choosing_and_closing_with_a_held_never_reaches_the_ship() -> String:
	var main: Node = _main_with_menu()
	var wiring: DevMenuWiring = main.get("dev_menu")
	if not wiring.is_open():
		main.free()
		return "a tap through main.gd did not open the menu"
	var start_speed: float = (main.get("session") as LocalSession).current_ship().velocity.length()
	var problem: String = ""
	var chosen: int = 0
	# 120 frames: the stick steps down a row every eighth frame, A chooses on
	# the Foveation row (a setting for this session only, so the menu stays
	# open), and the triggers and left stick are held as a pilot would.
	for frame: int in 120:
		var values: Dictionary = _values()
		values["left_stick"] = Vector2(0.2, 1.0)
		values["right_trigger"] = 1.0
		var kind: String = wiring.menu.model.kind()
		if kind == DevMenuSpec.KIND_FOVEATION and (chosen < 2 or frame % 8 == 1):
			values["buttons"] = {A: frame % 8 == 0}
			chosen += 1 if frame % 8 == 0 else 0
		elif kind != DevMenuSpec.KIND_CLOSE and frame % 8 == 0:
			values["right_stick"] = Vector2(0.0, -1.0)
		problem = _frame(main, values, start_speed, "open frame %d" % frame)
		if problem != "" or not wiring.is_open():
			break
	if problem == "" and (chosen == 0 or wiring.menu.model.kind() != DevMenuSpec.KIND_CLOSE):
		problem = "the walk chose %d times and ended on %s, not Close" % [chosen, wiring.menu.model.kind()]
	if problem == "":
		# A on Close, then held for half a second with the stick still pushed.
		var held: Dictionary = _values({A: true})
		held["right_stick"] = Vector2(0.0, 1.0)
		for frame: int in 36:
			problem = _frame(main, held, start_speed, "A held %d frames after Close" % frame)
			if problem != "":
				break
		if problem == "" and wiring.is_open():
			problem = "A on Close left the menu open"
	if problem == "":
		problem = _frame(main, _values(), start_speed, "the release frame")
	if problem == "":
		main.call("apply_controls", _values({A: true}))
		if not (main.get("input_source") as LatestInputSource).latest_input().afterburner:
			problem = "a fresh A after the release did not boost"
	main.free()
	return problem


func test_a_tap_that_closes_the_menu_keeps_held_sticks_and_triggers_from_the_ship() -> String:
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.attach(null, null, LevelStart.new(), func() -> void: pass, null, null,
		DevMenu.new(DevMenuSpec.load_file(), []))
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), 1.0)
	wiring.read(_values(), 1.2)
	var flying: Dictionary = _values({"left_button_upper": true})
	flying["left_stick"] = Vector2(0.0, 1.0)
	flying["right_trigger"] = 1.0
	var tap: Dictionary = flying.duplicate(true)
	tap["buttons"][ControllerSampler.MENU_BUTTON] = true
	wiring.read(tap, 2.0)
	var on_close: Dictionary = wiring.read(flying, 2.2)
	var result: String = ""
	if wiring.is_open():
		result = "the second tap did not close the menu"
	elif on_close["left_stick"] != Vector2.ZERO or float(on_close["right_trigger"]) != 0.0 \
			or (on_close["buttons"] as Dictionary).has("left_button_upper"):
		result = "the close frame passed %s" % [on_close]
	if result == "":
		var still: Dictionary = wiring.read(flying, 2.3)
		if still["left_stick"] != Vector2.ZERO or (still["buttons"] as Dictionary).has("left_button_upper"):
			result = "controls held since the close reached the ship: %s" % [still]
	if result == "":
		# The stick back to centre and Y up, the trigger still pulled: only
		# the released ones act again.
		wiring.read(_values(), 2.4)
		var again: Dictionary = wiring.read(flying, 2.5)
		if again["left_stick"] != Vector2(0.0, 1.0) or not (again["buttons"] as Dictionary).has("left_button_upper"):
			result = "released controls did not act again: %s" % [again]
	wiring.menu.free()
	return result


func test_the_release_latch_reads_each_control_on_its_own() -> String:
	var release: DevMenuRelease = DevMenuRelease.new()
	var at_close: Dictionary = _values({"right_button_lower": true, ResetHold.BUTTON: true})
	at_close["right_stick"] = Vector2(0.5, 0.5)
	at_close["left_grip"] = 0.8
	release.hold(at_close)
	var first: Dictionary = release.filter(at_close)
	if first["right_stick"] != Vector2.ZERO or float(first["left_grip"]) != 0.0 \
			or (first["buttons"] as Dictionary).has("right_button_lower"):
		return "held controls passed: %s" % [first]
	if not (first["buttons"] as Dictionary).has(ResetHold.BUTTON):
		return "the menu button was held back, so a hold could not reset"
	var partly: Dictionary = at_close.duplicate(true)
	partly["right_stick"] = Vector2(0.05, 0.0)
	release.filter(partly)
	var later: Dictionary = release.filter(at_close)
	if later["right_stick"] != Vector2(0.5, 0.5) or float(later["left_grip"]) != 0.0:
		return "the centred stick stayed held or the grip let go early: %s" % [later]
	var idle: Dictionary = _values()
	release.filter(idle)
	if release.holding() or release.filter(at_close) != at_close:
		return "everything released, the latch still held"
	return ""
