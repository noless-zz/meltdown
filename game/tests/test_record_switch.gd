extends RefCounted

## The per-step record switch (#560, DEV-6, ARC-2): only the steps named in
## `MELTDOWN_RECORD_M2` / `MELTDOWN_RECORD_M3` are re-recorded, and `1` still means all.

const RecordSwitch := preload("res://tests/record_switch.gd")
const G2: String = "bot_g2_escape"
const GENERATED: String = "bot_generated_escape"
const DOOR: String = "bot_generated_door_escape"
## Not a variable any run sets, so reading it from the environment gives "".
const UNSET_SWITCH: String = "MELTDOWN_RECORD_T560_UNSET"


func test_empty_asks_for_nothing() -> String:
	if RecordSwitch.lists("", G2):
		return "an empty switch asked for %s" % G2
	if RecordSwitch.lists(" , ", G2):
		return "a switch of only a comma and spaces asked for %s" % G2
	if RecordSwitch.asks_for(UNSET_SWITCH, G2):
		return "an unset switch asked for %s" % G2
	return ""


func test_one_asks_for_every_step() -> String:
	for step_id: String in [G2, GENERATED, DOOR, "bot_clears_g2_level"]:
		if not RecordSwitch.lists("1", step_id):
			return "'1' did not ask for %s" % step_id
	if not RecordSwitch.lists(" 1 ", G2):
		return "'1' with spaces did not ask for %s" % G2
	return ""


func test_one_id_asks_for_only_that_step() -> String:
	if not RecordSwitch.lists(GENERATED, GENERATED):
		return "'%s' did not ask for itself" % GENERATED
	for other: String in [G2, DOOR]:
		if RecordSwitch.lists(GENERATED, other):
			return "'%s' also asked for %s" % [GENERATED, other]
	return ""


func test_two_ids_ask_for_both_and_no_other() -> String:
	var value: String = "%s,%s" % [G2, DOOR]
	if not RecordSwitch.lists(value, G2) or not RecordSwitch.lists(value, DOOR):
		return "'%s' did not ask for both steps" % value
	if RecordSwitch.lists(value, GENERATED):
		return "'%s' also asked for %s" % [value, GENERATED]
	return ""


func test_spaces_around_ids_are_ignored() -> String:
	var value: String = " %s ,  %s " % [G2, GENERATED]
	if not RecordSwitch.lists(value, G2) or not RecordSwitch.lists(value, GENERATED):
		return "'%s' did not ask for both steps" % value
	if RecordSwitch.lists(value, DOOR):
		return "'%s' also asked for %s" % [value, DOOR]
	return ""


func test_unknown_id_asks_for_nothing() -> String:
	for step_id: String in [G2, GENERATED, DOOR]:
		if RecordSwitch.lists("bot_no_such_step", step_id):
			return "an unknown id asked for %s" % step_id
	# Only whole ids count: a prefix or a longer id is not the step.
	if RecordSwitch.lists("bot_generated", GENERATED) or RecordSwitch.lists(DOOR, "bot_generated"):
		return "a partial id matched"
	return ""
