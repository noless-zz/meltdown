extends RefCounted

## The end screens' lists and base prompt (#1376, CRF-2, RUN-7, SLV-3, ARC-4):
## the words, the look file and its rejections, and the screens drawing them.

const NAMES: Dictionary[String, String] = {"cell_salts": "Cell Salts", "core_glass": "Core Glass"}


func test_the_escape_lists_the_banked_kinds_and_the_miners() -> String:
	var lists: EndScreenLists = EndScreenLists.new(EndScreenListsLook.FALLBACK, NAMES)
	var text: String = lists.escape_text({"core_glass": 1, "cell_salts": 3}, 2)
	if text != "Banked: 3 Cell Salts, 1 Core Glass\nMiners brought out: 2":
		return "escape lists '%s'" % text
	var empty: String = lists.escape_text({}, 0)
	if empty != "Banked: nothing\nMiners brought out: 0":
		return "an empty escape lists '%s'" % empty
	return ""


func test_the_destroyed_lists_say_what_was_kept_and_what_was_lost() -> String:
	var lists: EndScreenLists = EndScreenLists.new(EndScreenListsLook.FALLBACK, NAMES)
	var text: String = lists.destroyed_text({"cell_salts": 4}, {"core_glass": 2, "cell_salts": 0}, 1)
	if text != "Kept from earlier escapes: 4 Cell Salts\nLost on this level: 2 Core Glass | Miners 1":
		return "destroyed lists '%s'" % text
	return ""


func test_the_lists_word_copies_and_leave_the_counts_alone() -> String:
	var lists: EndScreenLists = EndScreenLists.new(EndScreenListsLook.FALLBACK, NAMES)
	var collected: Dictionary = {"cell_salts": 2, "core_glass": 0}
	lists.escape_text(collected, 1)
	lists.destroyed_text(collected, collected, 1)
	if collected != {"cell_salts": 2, "core_glass": 0}:
		return "the counts changed: %s" % collected
	return ""


func test_the_base_prompt_names_the_button_of_each_build() -> String:
	var lists: EndScreenLists = EndScreenLists.new()
	if lists.base_prompt(true) != "Press A: return to base" or lists.base_prompt(false) != "Press Enter: return to base":
		return "base prompts '%s' and '%s'" % [lists.base_prompt(true), lists.base_prompt(false)]
	return ""


func test_the_shipped_file_matches_the_fallback() -> String:
	var look: Dictionary = EndScreenListsLook.parse(FileAccess.get_file_as_string(EndScreenListsLook.DEFAULT_FILE))
	if look.has("error"):
		return "the shipped file is rejected: %s" % look["error"]
	if look != EndScreenListsLook.FALLBACK:
		return "the shipped file %s differs from the fallback %s" % [look, EndScreenListsLook.FALLBACK]
	return ""


func test_bad_files_are_rejected_naming_the_field() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EndScreenListsLook.DEFAULT_FILE))
	var cases: Array = [
		["banked_text", "Banked", "banked_text"],
		["lost_text", "Lost {items}", "lost_text"],
		["none_text", "  ", "none_text"],
		["color", [1.0, 2.0, 0.0], "color"],
		["font_size", true, "font_size"],
		["font_size", 900, "font_size"],
		["escape_position_m", [0.0, 0.0, 1.0], "escape_position_m"],
		["shout", "x", "shout"],
	]
	for case: Array in cases:
		var data: Dictionary = shipped.duplicate(true)
		data[case[0]] = case[1]
		var look: Dictionary = EndScreenListsLook.parse(JSON.stringify(data))
		if not look.has("error") or not String(look["error"]).contains(case[2]):
			return "%s = %s gave %s" % [case[0], case[1], look]
	var missing: Dictionary = shipped.duplicate(true)
	missing.erase("kept_text")
	var gone: Dictionary = EndScreenListsLook.parse(JSON.stringify(missing))
	if not String(gone.get("error", "")).contains("kept_text"):
		return "a missing key gave %s" % gone
	if EndScreenListsLook.load_file("res://no_such_lists.json") != EndScreenListsLook.FALLBACK:
		return "a missing file does not fall back"
	return ""


func test_the_screens_draw_the_lists_and_a_base_prompt_over_their_own() -> String:
	var lists: EndScreenLists = EndScreenLists.new(EndScreenListsLook.FALLBACK, NAMES)
	var escape: EscapeScreen = EscapeScreen.new(EscapeScreenLook.FALLBACK, lists)
	var destroyed: DestroyedScreen = DestroyedScreen.new(lists)
	var result: String = _check_screens(escape, destroyed)
	escape.free()
	destroyed.free()
	return result


func _check_screens(escape: EscapeScreen, destroyed: DestroyedScreen) -> String:
	escape.show_state(true, true, 30.0, true, false, "Banked: 1 Cell Salts", "")
	if escape.lists_text() != "Banked: 1 Cell Salts" or escape.prompt_text() != "Press A to fly again":
		return "escape shows '%s' and '%s'" % [escape.lists_text(), escape.prompt_text()]
	escape.show_state(true, true, 30.0, true, true, "", "Press A: return to base")
	if escape.lists_text() != "" or escape.prompt_text() != "Press A: return to base":
		return "a won escape shows '%s' and '%s'" % [escape.lists_text(), escape.prompt_text()]
	destroyed.show_state(true, true, false, "Lost on this level: nothing | Miners 0", "Press Enter: return to base")
	if destroyed.lists_text() == "" or destroyed.prompt_text() != "Press Enter: return to base":
		return "destroyed shows '%s' and '%s'" % [destroyed.lists_text(), destroyed.prompt_text()]
	destroyed.show_state(true, true, true)
	if destroyed.lists_text() != "" or destroyed.prompt_text() != DestroyedScreen.PROMPT_XR:
		return "outside a run destroyed shows '%s' and '%s'" % [destroyed.lists_text(), destroyed.prompt_text()]
	return ""
