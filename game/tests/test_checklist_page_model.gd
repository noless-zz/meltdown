extends RefCounted

## The checklist page's controls (#1325, DEV-6, PLT-5): the stick moves
## between steps and choices, A confirms, B and Y step the remark, and the
## press that opened the page does nothing until let go.


static func opened() -> ChecklistPageModel:
	var model: ChecklistPageModel = ChecklistPageModel.new(ChecklistFixtures.session())
	model.open()
	model.press({})  # Everything let go after the opening press.
	return model


static func tap(model: ChecklistPageModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


func test_the_press_that_opened_the_page_does_not_mark() -> String:
	var model: ChecklistPageModel = ChecklistPageModel.new(ChecklistFixtures.session())
	model.open()
	var held: String = model.press({DevMenuModel.CONFIRM: true})
	if held != "":
		return "a held A gave %s" % held
	model.press({})
	var again: String = model.press({DevMenuModel.CONFIRM: true})
	return "" if again == "mark:pass" else "a fresh A gave %s" % again


func test_it_opens_on_the_step_to_do_next() -> String:
	var session: ChecklistSession = ChecklistFixtures.session()
	session.mark(0, ChecklistSession.PASS, "", {}, "t")
	var model: ChecklistPageModel = ChecklistPageModel.new(session)
	model.open()
	return "" if model.step == 1 else "opened on step %d" % model.step


func test_the_stick_and_a_choose_each_mark() -> String:
	var model: ChecklistPageModel = opened()
	if tap(model, DevMenuModel.CONFIRM) != "mark:pass":
		return "first choice is not pass"
	tap(model, DevMenuModel.RIGHT)
	if tap(model, DevMenuModel.CONFIRM) != "mark:fail":
		return "second choice is not fail"
	tap(model, DevMenuModel.RIGHT)
	return "" if tap(model, DevMenuModel.CONFIRM) == "mark:skip" else "third choice is not skip"


func test_choices_offer_do_only_for_a_step_with_an_action() -> String:
	var model: ChecklistPageModel = opened()
	var first: Array[String] = model.choices()
	tap(model, DevMenuModel.DOWN)
	var second: Array[String] = model.choices()
	if not first.has(ChecklistPageModel.DO) or second.has(ChecklistPageModel.DO):
		return "choices %s then %s" % [first, second]
	return "" if first[-2] == ChecklistPageModel.PIN and first[-1] == ChecklistPageModel.CLOSE else "choices %s" % [first]


func test_left_from_pass_reaches_close() -> String:
	var model: ChecklistPageModel = opened()
	tap(model, DevMenuModel.LEFT)
	return "" if tap(model, DevMenuModel.CONFIRM) == ChecklistPageModel.CLOSE else "left of pass is not close"


func test_up_from_the_first_step_wraps_to_the_last_and_resets_the_choice() -> String:
	var model: ChecklistPageModel = opened()
	tap(model, DevMenuModel.RIGHT)
	tap(model, DevMenuModel.UP)
	return "" if model.step == 2 and model.choice == 0 else "step %d, choice %d" % [model.step, model.choice]


func test_b_and_y_step_the_remark_through_none() -> String:
	var model: ChecklistPageModel = opened()
	tap(model, DevMenuModel.SEED_UP)
	if model.remark != "unclear":
		return "B gave %s" % model.remark
	tap(model, DevMenuModel.SEED_UP)
	tap(model, DevMenuModel.SEED_UP)
	if model.remark != "":
		return "three presses gave %s, want none" % model.remark
	tap(model, DevMenuModel.SEED_DOWN)
	return "" if model.remark == "broken" else "Y gave %s" % model.remark


func test_confirming_the_remark_choice_steps_it_and_marks_nothing() -> String:
	var model: ChecklistPageModel = opened()
	model.choice = model.choices().find(ChecklistPageModel.REMARK)
	var result: String = tap(model, DevMenuModel.CONFIRM)
	return "" if result == "" and model.remark == "unclear" else "gave %s, remark %s" % [result, model.remark]


func test_the_page_lines_say_where_what_and_the_tally() -> String:
	var model: ChecklistPageModel = opened()
	var lines: Array[String] = model.page_lines()
	var text: String = "\n".join(lines)
	for want: String in ["T · P · 1/3", "Do: A", "Look for: a", "Not marked yet", "< Pass >", "Do: set comfort preset 1",
			"0 pass · 0 fail · 0 skip · 3 open"]:
		if not text.contains(want):
			return "no \"%s\" in\n%s" % [want, text]
	return "" if model.pinned_line() == "1/3  A" else "pinned %s" % model.pinned_line()
