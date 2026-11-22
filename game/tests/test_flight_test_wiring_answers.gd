extends RefCounted

## The first-launch flight test in the game (CMF-4, CMF-6, CMF-8, ARC-3, #715):
## how answers and the skip hold drive it, that the ship is held while an
## answer is due, and that the result and later switches are saved. The
## fixtures are `test_flight_test_wiring_start.gd`'s.

const Wiring := preload("res://tests/test_flight_test_wiring_start.gd")
const A: String = Wiring.A
const B: String = Wiring.B
const Y: String = Wiring.Y
const X: String = Wiring.X


func test_answers_drive_the_session_and_the_ship_is_held_while_one_is_due() -> String:
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.TUNNEL, Wiring.scratch("answers.json"), c)
	var message: String = ""
	if wired.held(Wiring.moving()).thrust_q == Vector3i.ZERO:
		message = "the ship is held while a segment is flown"
	Wiring.frame(wired, {}, false, 60.0)
	var still: ShipInput = wired.held(Wiring.moving())
	if message == "" and not wired.test.awaiting_answer():
		message = "no answer due after the segment's time"
	elif message == "" and (still.thrust_q != Vector3i.ZERO or still.turn_q != Vector3i.ZERO or still.afterburner):
		message = "input flies while an answer is due"
	Wiring.frame(wired, {A: true})
	if message == "" and (wired.test.segment_index() != 1 or str(wired.test.answers()) != str(["fine"])):
		message = "A did not answer fine: %s" % [wired.test.answers()]
	elif message == "" and wired.held(Wiring.moving()).afterburner:
		message = "the A that answered also flew the afterburner"
	elif message == "" and c.number != 2:
		message = "preset %d for the second segment, expected 2" % c.number
	Wiring.frame(wired, {A: true})
	Wiring.frame(wired, {})
	if message == "" and wired.held(Wiring.moving()).thrust_q == Vector3i.ZERO:
		message = "the ship stays held after the answer button was let go"
	elif message == "" and wired.test.segment_index() != 1:
		message = "holding A answered twice"
	Wiring.free_panel(wired)
	return message


func test_holding_the_menu_button_skips_to_preset_one_and_saves() -> String:
	var path: String = Wiring.scratch("skip.json")
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.TUNNEL, path, c)
	Wiring.answer_with(wired, A)
	if not wired.takes_menu_hold():
		return "the menu hold would reset the ship during the test"
	for i: int in 45:
		Wiring.frame(wired, {}, true)
	if not wired.running():
		return "half a second of holding skipped the test"
	for i: int in 50:
		Wiring.frame(wired, {}, true)
	var back: ComfortChoice = Wiring.saved(path)
	var message: String = ""
	if wired.running() or not wired.test.skipped():
		message = "a 1 s hold did not skip"
	elif c.number != 1:
		message = "preset %d after a skip, expected 1" % c.number
	elif back.first_launch() or back.preset() != 1:
		message = "saved preset %d first launch %s after a skip" % [back.preset(), back.first_launch()]
	elif wired.takes_menu_hold():
		message = "the menu hold still skips after the test"
	Wiring.free_panel(wired)
	return message


func test_the_end_applies_and_saves_the_recommendation_and_shows_it_five_seconds() -> String:
	var path: String = Wiring.scratch("end.json")
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.TUNNEL, path, c)
	Wiring.answer_with(wired, A)
	Wiring.answer_with(wired, A)
	Wiring.answer_with(wired, B)
	var back: ComfortChoice = Wiring.saved(path)
	if wired.running():
		return "uneasy did not end the test"
	if wired.test.recommended() != 2 or c.number != 2:
		return "recommended %d, applied %d, expected 2" % [wired.test.recommended(), c.number]
	if back.first_launch() or back.preset() != 2:
		return "saved preset %d first launch %s" % [back.preset(), back.first_launch()]
	if wired.panel == null or not str(wired.panel.shown()["main"]).contains("2"):
		Wiring.free_panel(wired)
		return "the result is not shown"
	Wiring.frame(wired, {}, false, 4.0)
	if wired.panel == null:
		return "the result went before 5 s"
	Wiring.frame(wired, {}, false, 1.5)
	if wired.panel != null:
		Wiring.free_panel(wired)
		return "the result still shows after 5 s"
	return ""


func test_stop_ends_the_test_at_preset_one() -> String:
	var path: String = Wiring.scratch("stop.json")
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.TUNNEL, path, c)
	Wiring.answer_with(wired, Y)
	var message: String = ""
	if wired.running() or str(wired.test.answers()) != str(["stop"]):
		message = "Y did not answer stop: %s" % [wired.test.answers()]
	elif c.number != 1 or Wiring.saved(path).preset() != 1:
		message = "applied %d saved %d after stop" % [c.number, Wiring.saved(path).preset()]
	Wiring.free_panel(wired)
	return message


func test_x_is_ignored_during_the_test_and_saved_after() -> String:
	var path: String = Wiring.scratch("x.json")
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.TUNNEL, path, c)
	var rest: Dictionary = Wiring.frame(wired, {X: true, A: true})
	if rest.has(X) or not rest.has(A):
		Wiring.free_panel(wired)
		return "during the test the rest of the frame reads %s" % rest
	Wiring.answer_with(wired, Y)
	rest = Wiring.frame(wired, {X: true})
	if not rest.has(X):
		Wiring.free_panel(wired)
		return "X is still taken after the test"
	c.read_preset_button(rest)
	Wiring.frame(wired, {})
	Wiring.free_panel(wired)
	var back: ComfortChoice = Wiring.saved(path)
	if c.number != 2 or back.preset() != 2 or back.first_launch():
		return "after X: active %d, saved %d, first launch %s" % [c.number, back.preset(), back.first_launch()]
	return ""


func test_x_on_a_level_start_is_saved() -> String:
	var path: String = Wiring.scratch("level_x.json")
	Wiring.write(path, "{\"preset\": 4, \"flight_test_done\": true}")
	var c: ComfortWiring = Wiring.comfort()
	var wired: FlightTestWiring = Wiring.wiring(FlightTestWiring.Start.SAVED, path, c)
	c.read_preset_button(Wiring.frame(wired, {X: true}))
	Wiring.frame(wired, {})
	var back: ComfortChoice = Wiring.saved(path)
	if c.number != 1 or back.preset() != 1 or back.first_launch():
		return "after X from 4: active %d, saved %d, first launch %s" % [c.number, back.preset(), back.first_launch()]
	return ""
