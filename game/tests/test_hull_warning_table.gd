extends RefCounted

## The low-hull warning's table (#1456, AUD-1, ARC-4, NAM-3): the shipped file
## reads with its tone present, the threshold defaults to the status panel's
## red mark, a bad key names its field and leaves the warning silent, and the
## interval follows the hull.

const GOOD: String = "{\"interval_s\": 1.2, \"fast_threshold\": 0.1, \"fast_interval_s\": 0.6, \"sound\": \"res://data/audio/hull_warning.wav\", \"volume_db\": -12.0}"


func test_the_shipped_table_reads_and_its_tone_exists() -> String:
	var table: HullWarningTable = HullWarningTable.load_file()
	if table.error != "":
		return table.error
	if not ResourceLoader.exists(table.sound):
		return "the warning plays %s, which does not exist" % table.sound
	if table.fast_interval_s >= table.interval_s:
		return "the faster interval %.2f s is not shorter than %.2f s" % [table.fast_interval_s, table.interval_s]
	return ""


func test_the_threshold_defaults_to_the_status_panel_red_mark() -> String:
	var table: HullWarningTable = HullWarningTable.load_file()
	var panel: float = float(StatusPanelLook.shared()["low_hull_fraction"])
	if not is_equal_approx(table.threshold, panel):
		return "the shipped threshold is %.3f, the panel's red mark %.3f" % [table.threshold, panel]
	var parsed: HullWarningTable = HullWarningTable.parse(GOOD, 0.4)
	if parsed.error != "" or not is_equal_approx(parsed.threshold, 0.4):
		return "without threshold the panel's 0.4 should stand: %.3f %s" % [parsed.threshold, parsed.error]
	var own: HullWarningTable = HullWarningTable.parse(GOOD.replace("{", "{\"threshold\": 0.3, "), 0.4)
	if own.error != "" or not is_equal_approx(own.threshold, 0.3):
		return "the file's threshold 0.3 should stand: %.3f %s" % [own.threshold, own.error]
	return ""


func test_a_bad_key_names_its_field_and_stays_silent() -> String:
	var cases: Dictionary[String, String] = {
		"[]": "not a JSON object",
		GOOD.replace("{", "{\"threshhold\": 0.3, "): "threshhold",
		GOOD.replace("{", "{\"threshold\": 1.5, "): "threshold",
		GOOD.replace("\"fast_threshold\": 0.1", "\"fast_threshold\": 0.5"): "fast_threshold",
		GOOD.replace("\"interval_s\": 1.2", "\"interval_s\": 0"): "interval_s",
		GOOD.replace("\"fast_interval_s\": 0.6", "\"fast_interval_s\": 2.0"): "fast_interval_s",
		GOOD.replace("\"fast_interval_s\": 0.6,", ""): "fast_interval_s",
		GOOD.replace("res://data/audio/hull_warning.wav", "hull_warning.wav"): "sound",
		GOOD.replace("-12.0", "\"loud\""): "volume_db",
	}
	for text: String in cases:
		var table: HullWarningTable = HullWarningTable.parse(text)
		if not table.error.contains(cases[text]):
			return "expected an error naming %s, got '%s'" % [cases[text], table.error]
		if table.interval_for(0.0) != 0.0:
			return "a rejected table (%s) still asks for tones" % table.error
	return ""


func test_the_interval_follows_the_hull() -> String:
	var table: HullWarningTable = HullWarningTable.parse(GOOD, 0.25)
	var cases: Array[Array] = [[1.0, 0.0], [0.26, 0.0], [0.25, 1.2], [0.2, 1.2], [0.1, 0.6], [0.0, 0.6]]
	for case: Array in cases:
		var got: float = table.interval_for(case[0])
		if not is_equal_approx(got, case[1]):
			return "at hull %.2f the interval is %.2f, not %.2f" % [case[0], got, case[1]]
	return ""
