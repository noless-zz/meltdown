extends RefCounted

## The shaft choice as a picture (#1320, RUN-2, GFX-2, PLT-2, CMF-8, ARC-1,
## ARC-4, ARC-5): each offered shaft drawn as a thing from its `look` key, its
## changes as gauges on one scale, short labels, "Suspend run" apart, and
## choosing by pointing or the stick. Presentation only.

const RUN_SEED: int = 12345
const PINNED_OFFER: Array[String] = ["deep", "hot", "steady"]


func _run() -> RunWiring:
	return RunWiring.new(RUN_SEED, null, func() -> int: return 77)


static func _shapes() -> ShaftPanelShapes:
	return ShaftPanelShapes.load_file()


func test_the_shipped_shapes_load_and_give_every_shipped_shaft_a_look() -> String:
	var shapes: ShaftPanelShapes = _shapes()
	if shapes.error != "":
		return "the shipped shapes were refused: %s" % shapes.error
	var offer: ShaftOffer = ShaftOffer.build(FileAccess.get_file_as_string("res://data/run/shafts.json"))
	var seen: Dictionary[String, bool] = {}
	for kind: String in offer.kinds:
		var key: String = shapes.look_of(kind)
		if key == "" or (shapes.looks[key]["parts"] as Array).is_empty():
			return "shaft %s has no look" % kind
		seen[key] = true
	if seen.size() != offer.kinds.size():
		return "two shafts share a look: %s" % [shapes.shafts]
	var sources: Array[String] = []
	for gauge: Dictionary in shapes.gauges:
		sources.append(gauge["source"])
	if sources != ShaftPanelShapes.SOURCES:
		return "the gauges are %s, expected robots, alarm and finds" % [sources]
	return ""


func test_each_shafts_gauges_come_from_its_modifiers() -> String:
	var shapes: ShaftPanelShapes = _shapes()
	var look: Dictionary = ShaftPanelLook.FALLBACK
	var calm: Array[Dictionary] = ShaftPanelGauges.for_shaft(shapes, {"robot_count": 1.0, "alarm": 1.0}, [6, 3, 1], look)
	var busy: Array[Dictionary] = ShaftPanelGauges.for_shaft(shapes, {"robot_count": 1.3, "alarm": 1.0}, [6, 3, 1], look)
	var loud: Array[Dictionary] = ShaftPanelGauges.for_shaft(shapes, {"robot_count": 1.0, "alarm": 1.5}, [6, 3, 1], look)
	var rich: Array[Dictionary] = ShaftPanelGauges.for_shaft(shapes, {"robot_count": 1.0, "alarm": 1.0}, [2, 3, 5], look)
	if float(busy[0]["fill"]) <= float(calm[0]["fill"]) or busy[1]["fill"] != calm[1]["fill"]:
		return "more robots did not lengthen only the robot gauge: %s vs %s" % [busy, calm]
	if float(loud[1]["fill"]) <= float(calm[1]["fill"]) or loud[0]["fill"] != calm[0]["fill"]:
		return "a faster alarm did not lengthen only the alarm gauge"
	if float(rich[2]["fill"]) <= float(calm[2]["fill"]) or rich[2]["value_text"] != "rare finds":
		return "rarer finds did not lengthen the finds gauge: %s" % [rich[2]]
	if busy[0]["value_text"] != "x1.3" or loud[1]["value_text"] != "x1.5":
		return "the values read %s and %s" % [busy[0]["value_text"], loud[1]["value_text"]]
	# One scale per gauge: the same value fills the same length on any shaft.
	var robots: Dictionary = shapes.gauges[0]
	var expected: float = (1.3 - float(robots["min"])) / (float(robots["max"]) - float(robots["min"]))
	if not is_equal_approx(float(busy[0]["fill"]), expected):
		return "the robot gauge fills %s, expected %s on its own scale" % [busy[0]["fill"], expected]
	if ShaftPanelGauges.fill(robots, 99.0) != 1.0 or ShaftPanelGauges.fill(robots, -1.0) != 0.0:
		return "a gauge ran past its ends"
	if not is_equal_approx(ShaftPanelGauges.mean_tier([2, 3, 5]), 2.3) or ShaftPanelGauges.mean_tier([0, 0, 0]) != 1.0:
		return "the mean tier is wrong"
	return ""


func test_the_drawn_gauges_follow_the_offer() -> String:
	var run: RunWiring = _run()
	var shapes: ShaftPanelShapes = _shapes()
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes)
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.show_model(model, true)
	var cards: Array[ShaftPanelCard] = panel.cards()
	var problem: String = ""
	if cards.size() != 3 or not panel.shaft_texts().is_empty():
		problem = "%d cards and text rows %s" % [cards.size(), panel.shaft_texts()]
	else:
		# deep: robots x1.3, alarm x1.1; hot: robots x1.1, alarm x1.5.
		var deep: Array[float] = cards[0].fill_lengths()
		var hot: Array[float] = cards[1].fill_lengths()
		if deep.size() != 3 or deep[0] <= hot[0] or deep[1] >= hot[1] or deep[2] >= hot[2]:
			problem = "fills deep %s, hot %s" % [deep, hot]
		elif cards[0].part_count() == 0 or cards[0].texts()[0] != "> Long drop":
			problem = "the first card shows %s with %d parts" % [cards[0].texts(), cards[0].part_count()]
		elif cards[0].position.x >= cards[1].position.x or cards[1].position.x >= cards[2].position.x:
			problem = "the cards are not side by side"
	panel.free()
	return problem


func test_every_word_fits_its_limit() -> String:
	var shapes: ShaftPanelShapes = _shapes()
	var words: Array[String] = [RunSuspend.words()["row_text"]]
	for key: String in shapes.looks:
		words.append(shapes.looks[key]["label"])
	for gauge: Dictionary in shapes.gauges:
		words.append(gauge["label"])
	for rule: Dictionary in ShaftPanelLook.load_file()["rewards"]:
		words.append(rule["text"])
	for word: String in words:
		if word.length() > shapes.label_max_chars:
			return "\"%s\" is longer than %d characters" % [word, shapes.label_max_chars]
	var good: String = FileAccess.get_file_as_string(ShaftPanelShapes.DEFAULT_FILE)
	var cases: Dictionary[String, String] = {
		good.replace("\"Vent shaft\"", "\"Vent shaft with a very long name\""): "longer than 24",
		good.replace("\"label\": \"Robots\"", "\"label\": \"Robots and drones and turrets\""): "longer than 24",
		good.replace("\"hot\": \"vent\"", "\"hot\": \"chute\""): "shafts.hot must name one of the looks",
		good.replace("\"source\": \"alarm\"", "\"source\": \"heat\""): "gauges[1].source",
		good.replace("\"shape\": \"sphere\"", "\"shape\": \"torus\""): "shape must be one of",
		good.replace("[0.0, 0.0, -0.03]", "[0.2, 0.0, -0.03]"): "reaches past",
		good.replace("\"card_step_m\"", "\"card_stride_m\""): "unknown key",
	}
	for text: String in cases:
		var parsed: ShaftPanelShapes = ShaftPanelShapes.parse(text)
		if not parsed.error.contains(cases[text]) or not parsed.looks.is_empty():
			return "expected an error saying %s, got '%s'" % [cases[text], parsed.error]
	return ""


func test_a_missing_look_key_falls_back_to_the_text_row() -> String:
	var run: RunWiring = _run()
	var text: String = FileAccess.get_file_as_string(ShaftPanelShapes.DEFAULT_FILE)
	var shapes: ShaftPanelShapes = ShaftPanelShapes.parse(text.replace("\"hot\": \"vent\"", "\"other\": \"vent\""))
	if shapes.error != "" or shapes.look_of("hot") != "":
		return "the edited file was refused or still has hot: %s" % shapes.error
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes)
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.show_model(model, true)
	var cards: Array[ShaftPanelCard] = panel.cards()
	var problem: String = ""
	if model.looks != ["drop", "", "lift"] or cards.size() != 3:
		problem = "looks %s, %d cards" % [model.looks, cards.size()]
	elif cards[1].part_count() != 0 or not cards[1].fill_lengths().is_empty() \
			or cards[1].texts() != PackedStringArray([model.labels[1], model.details[1]]):
		problem = "the shaft without a look shows %s" % cards[1].texts()
	panel.free()
	# With no shapes at all, the panel is today's list of text rows.
	var plain: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, ShaftPanelShapes.parse("{}"))
	plain.show_model(ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, null), true)
	if problem == "" and (not plain.cards().is_empty() or plain.shaft_texts().size() != 3):
		problem = "a refused shapes file did not leave text rows: %s" % plain.shaft_texts()
	plain.free()
	return problem


func test_suspend_run_sits_apart_below_the_shafts() -> String:
	var run: RunWiring = _run()
	var shapes: ShaftPanelShapes = _shapes()
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes)
	model.add_row(RunSuspend.ROW_KIND, "Suspend run", "bank, save and leave for the hub")
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.show_model(model, true)
	var points: Dictionary[String, Vector3] = panel.entry_points()
	var lowest_plate: float = INF
	for card: ShaftPanelCard in panel.cards():
		lowest_plate = minf(lowest_plate, card.position.y - shapes.lengths["plate_drop_m"] - shapes.plate_size_m.y * 0.5)
	var problem: String = ""
	if panel.cards().size() != 3 or panel.shaft_texts() != PackedStringArray(["Suspend run"]):
		problem = "cards %d, rows %s" % [panel.cards().size(), panel.shaft_texts()]
	elif not points.has(RunSuspend.ROW_KIND) or lowest_plate - points[RunSuspend.ROW_KIND].y < shapes.lengths["suspend_gap_m"] - 0.001:
		problem = "Suspend run is not %s m under the plates: %s vs %s" % [shapes.lengths["suspend_gap_m"],
			points.get(RunSuspend.ROW_KIND), lowest_plate]
	panel.free()
	return problem


func test_pointing_or_the_stick_highlights_a_shaft() -> String:
	var run: RunWiring = _run()
	var shapes: ShaftPanelShapes = _shapes()
	var model: ShaftPanelModel = ShaftPanelModel.build(PINNED_OFFER, run.shafts, ShaftPanelLook.FALLBACK, shapes)
	model.add_row(RunSuspend.ROW_KIND, "Suspend run", "bank, save and leave for the hub")
	var panel: ShaftPanel = ShaftPanel.new(ShaftPanelLook.FALLBACK, shapes)
	panel.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.2, 0.0))
	panel.show_model(model, true)
	var problem: String = ""
	for kind: String in [PINNED_OFFER[2], RunSuspend.ROW_KIND, PINNED_OFFER[0]]:
		# An aim from a resting hand under the eye, towards the entry's point.
		var target: Vector3 = panel.transform * panel.entry_points()[kind]
		var hand: Vector3 = panel.transform * Vector3(0.15, -0.35, -0.3)
		var aim: Transform3D = Transform3D.IDENTITY.looking_at(target - hand, Vector3.UP).translated(hand)
		var pointed: String = ShaftChoiceWiring.point_in(panel, aim, shapes.lengths["point_radius_m"])
		model.point(pointed)
		if pointed != kind or model.selected() != kind:
			problem = "aiming at %s pointed at '%s', highlighted %s" % [kind, pointed, model.selected()]
			break
	# A still hand does not undo a stick step; right steps like down.
	model.update({})
	model.update({DevMenuModel.RIGHT: true})
	model.point(PINNED_OFFER[0])
	if problem == "" and model.highlight != 1:
		problem = "after a step right the highlight is %d" % model.highlight
	model.update({})
	model.update({DevMenuModel.LEFT: true})
	if problem == "" and model.highlight != 0:
		problem = "after a step left the highlight is %d" % model.highlight
	panel.free()
	return problem


func test_choosing_through_the_new_look_keeps_the_runs_rules() -> String:
	var plain: RunWiring = _run()
	var drawn: RunWiring = _run()
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	choice.open(drawn, {})
	if choice.model.looks.has("") or choice.model.kinds != PINNED_OFFER:
		return "the wiring's model has looks %s for %s" % [choice.model.looks, choice.model.kinds]
	plain.escape_for_choice({}, 0)
	plain.choose(PINNED_OFFER[1])
	drawn.choose(choice.model.kinds[1])
	if plain.state.current_level_seed() != drawn.state.current_level_seed() \
			or plain.level_robot_scale() != drawn.level_robot_scale():
		return "the drawn panel changed what the shaft flies"
	return ""
