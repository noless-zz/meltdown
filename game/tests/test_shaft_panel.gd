extends RefCounted

## The shaft panel between a run's levels (#990, RUN-1, CRF-7, CMF-8, ARC-3,
## MP-2): `ShaftPanelModel` lists the offer in order with its words,
## `ShaftChoiceWiring` takes the stick and A as the dev menu's named actions,
## and `RunWiring` flies the chosen shaft's level. No scene is needed.

const RUN_SEED: int = 12345
## `RunPlan.offer_after(0, ...)` for run 12345 with the shipped run and shaft files.
const PINNED_OFFER: Array[String] = ["deep", "hot", "steady"]
const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"


func _run(run_text: String = "") -> RunWiring:
	return RunWiring.new(RUN_SEED, null, func() -> int: return 77, run_text)


## One frame: the values read, then the panel updated. Returns update's answer.
static func _frame(choice: ShaftChoiceWiring, run: RunWiring, buttons: Dictionary = {},
		stick: Vector2 = Vector2.ZERO, paused: bool = false) -> bool:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	values["right_stick"] = stick
	choice.read(values)
	return choice.update(run, paused, Transform3D.IDENTITY, false)


func test_the_panel_lists_run_12345s_offer_after_level_one_in_pinned_order() -> String:
	var run: RunWiring = _run()
	if run.shafts == null or not run.choice_due_after_escape():
		return "run %d has no shaft choice due after level 1" % RUN_SEED
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	if not choice.open(run, {}):
		return "the panel did not open"
	if choice.model.kinds != PINNED_OFFER or choice.model.kinds != run.state.offer():
		return "the panel lists %s, the run offers %s, pinned %s" % [choice.model.kinds, run.state.offer(),
			PINNED_OFFER]
	var want_labels: Array[String] = []
	for kind: String in PINNED_OFFER:
		want_labels.append(run.shafts.labels[kind])
	if choice.model.labels != want_labels:
		return "labels %s, expected %s" % [choice.model.labels, want_labels]
	var want_details: Array[String] = ["robots x1.3, alarm x1.1: richer finds",
		"robots x1.1, alarm x1.5: rare finds", "robots x1.0, alarm x1.0: common finds"]
	if choice.model.details != want_details:
		return "details %s, expected %s" % [choice.model.details, want_details]
	if run.state.level_index != 1 or not run.escape_taken:
		return "opening the panel did not move the run past level 1"
	return ""


func test_a_confirm_on_the_second_entry_flies_that_shafts_level() -> String:
	var run: RunWiring = _run()
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	choice.open(run, {})
	var a: Dictionary = {DestroyedWiring.RESTART_BUTTON: true}
	# The press that opened the panel is still held: it must not confirm.
	if _frame(choice, run, a) or _frame(choice, run) or _frame(choice, run, {}, Vector2(0.0, -1.0)):
		return "the panel confirmed before A was pressed again"
	if _frame(choice, run) or choice.model.highlight != 1:
		return "the stick down left the highlight on %d" % choice.model.highlight
	if not _frame(choice, run, a):
		return "A did not confirm"
	if choice.is_open() or run.state.current_shaft() != PINNED_OFFER[1]:
		return "after the confirm: open %s, shaft '%s'" % [choice.is_open(), run.state.current_shaft()]
	# The level is named with its shaft's robot scale (#1011).
	var want: String = LevelSwitch.seed_source(run.state.current_level_seed(), run.level_robot_scale())
	var through: int = run.state.plan.level_seed_through(1, run.shafts, PINNED_OFFER[1])
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if next != want or run.state.current_level_seed() != through or run.state.level_index != 1 or run.escape_taken:
		return "the restart flies %s at index %d, expected %s (seed %d)" % [next, run.state.level_index, want, through]
	return ""


func test_the_stick_stops_at_either_end_without_wrapping() -> String:
	var run: RunWiring = _run()
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	choice.open(run, {})
	_frame(choice, run)
	for i: int in 5:
		_frame(choice, run, {}, Vector2(0.0, 1.0))
		_frame(choice, run)
	if choice.model.highlight != 0:
		return "up past the top left the highlight on %d" % choice.model.highlight
	for i: int in 6:
		_frame(choice, run, {}, Vector2(0.0, -1.0))
		_frame(choice, run)
	if choice.model.highlight != PINNED_OFFER.size() - 1:
		return "down past the bottom left the highlight on %d" % choice.model.highlight
	var empty: ShaftPanelModel = ShaftPanelModel.new()
	for actions: Dictionary in [{}, {DevMenuModel.UP: true}, {}, {DevMenuModel.DOWN: true}, {},
			{DevMenuModel.CONFIRM: true}]:
		if empty.update(actions) != "" or empty.highlight != 0:
			return "an empty panel answered or moved"
	return ""


func test_the_panel_never_opens_after_the_last_level() -> String:
	var run: RunWiring = _run(THREE_LEVELS)
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	for level: int in 2:
		if not choice.open(run, {}):
			return "no panel after level %d" % (level + 1)
		run.choose(choice.model.kinds[0])
		choice.close()
		run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if not run.on_last_level() or run.choice_due_after_escape() or choice.open(run, {}) or choice.is_open():
		return "a choice is offered after the last level"
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if run.ended == null or not run.ended.won:
		return "escaping the last level did not win the run"
	return ""


func test_while_open_the_ship_gets_neutral_input_and_a_pause_holds_the_panel() -> String:
	var run: RunWiring = _run()
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = Vector2(0.7, 0.2)
	values["buttons"] = {DestroyedWiring.RESTART_BUTTON: true}
	if choice.read(values) != values:
		return "a closed panel changed the values"
	choice.open(run, {})
	var passed: Dictionary = choice.read(values)
	if passed["left_stick"] != Vector2.ZERO or not (passed["buttons"] as Dictionary).is_empty():
		return "an open panel passed %s on to the ship" % passed
	_frame(choice, run)
	if _frame(choice, run, {DestroyedWiring.RESTART_BUTTON: true}, Vector2.ZERO, true) or not choice.is_open():
		return "A while paused took a shaft"
	if _frame(choice, run, {}, Vector2(0.0, -1.0), true) or choice.model.highlight != 0:
		return "the stick while paused moved the highlight"
	return ""


func test_a_restart_with_no_choice_takes_the_first_offered_shaft() -> String:
	var run: RunWiring = _run()
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if run.state.needs_choice() or run.state.current_shaft() != PINNED_OFFER[0]:
		return "the run was left on shaft '%s', choice due %s" % [run.state.current_shaft(), run.state.needs_choice()]
	if next != LevelSwitch.seed_source(run.state.current_level_seed(),
			float(run.shafts.risks[PINNED_OFFER[0]]["robot_count"])):
		return "flies %s" % next
	return ""


func test_a_rejected_shaft_file_runs_without_a_choice() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, Callable(), "", true, "{\"offer_min\": 9}")
	if run.shafts != null or run.choice_due_after_escape() or not run.active():
		return "a rejected shaft file still gave a choice"
	return ""


func test_the_shipped_look_loads_and_bad_files_are_named() -> String:
	var look: Dictionary = ShaftPanelLook.load_file()
	if look.has("error") or look["title_text"] != ShaftPanelLook.FALLBACK["title_text"]:
		return "the shipped look did not load as the fallback has it"
	var good: String = FileAccess.get_file_as_string(ShaftPanelLook.DEFAULT_FILE)
	var cases: Dictionary[String, String] = {
		good.replace("\"title_text\"", "\"titel\""): "unknown key \"titel\"",
		good.replace("{reward}", "{prize}"): "must contain {reward}",
		good.replace("\"min_share\": 0.0", "\"min_share\": 0.1"): "rewards[2].min_share must be 0",
		good.replace("\"tier\": 3", "\"tier\": 4"): "rewards[0].tier must be a whole number",
		good.replace("\"entry_step_m\": 0.14", "\"entry_step_m\": true"): "\"entry_step_m\" must be a number",
		good.replace("[0.0, 0.3, -1.5]", "[0.0, 0.3, 1.5]"): "\"title_position_m\" must be",
	}
	for text: String in cases:
		var parsed: Dictionary = ShaftPanelLook.parse(text)
		if not str(parsed.get("error", "")).contains(cases[text]):
			return "expected an error saying %s, got %s" % [cases[text], parsed.get("error", "no error")]
	if ShaftPanelLook.reward_text(look, [6, 3, 1]) != "common finds" \
			or ShaftPanelLook.reward_text(look, [2, 3, 5]) != "rare finds":
		return "reward words are wrong"
	return ""


func test_the_view_shows_the_model_with_the_highlight_marked() -> String:
	var run: RunWiring = _run()
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK)
	model.highlight = 1
	var panel: ShaftPanel = ShaftPanel.new()
	panel.show_model(model, true)
	var texts: PackedStringArray = panel.shaft_texts()
	var problem: String = ""
	if not panel.visible or texts.size() != 3 or not texts[1].begins_with("> ") or texts[0].begins_with("> "):
		problem = "shown %s" % texts
	elif panel.detail_texts()[1] != model.details[1] or panel.prompt_text() != ShaftPanelLook.FALLBACK["prompt_xr"]:
		problem = "details %s, prompt %s" % [panel.detail_texts(), panel.prompt_text()]
	panel.show_model(null, false)
	if problem == "" and panel.visible:
		problem = "a closed panel still shows"
	panel.free()
	return problem
