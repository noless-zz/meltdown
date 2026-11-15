extends "res://tests/layer_scanner.gd"

## Runs the layer scan over `core/`, `gen/` and `net/`, and feeds it snippets
## that break each rule so the scan cannot pass silently.


func _scan(source: String) -> Array[String]:
	return scan_source(source, "res://core/snippet.gd", ["ShipState"])


## "" if `source` gives exactly one finding, on `line`, containing `text`.
func _expect_one(source: String, line: int, text: String) -> String:
	var findings: Array[String] = _scan(source)
	if findings.size() != 1:
		return "expected 1 finding for %s, got %s" % [source.c_escape(), findings]
	if not findings[0].begins_with("res://core/snippet.gd:%d: " % line):
		return "wrong file or line in '%s'" % findings[0]
	if not findings[0].contains(text):
		return "'%s' does not mention %s" % [findings[0], text]
	return ""


func test_core_gen_and_net_follow_the_layer_rules() -> String:
	var scripts: Array[String] = []
	for root: String in SCANNED_DIRS:
		scripts.append_array(collect_scripts(root))
	# A scan that finds no file would pass forever, whatever the layers contain.
	for expected: String in ["res://core/sim.gd", "res://net/local_session.gd"]:
		if not scripts.has(expected):
			return "the scan did not find %s; found %s" % [expected, scripts]
	var layer_classes: Array[String] = []
	for path: String in scripts:
		layer_classes.append_array(declared_classes(FileAccess.get_file_as_string(path)))
	var outside_classes: Array[String] = []
	for root: String in OUTSIDE_DIRS:
		for path: String in collect_scripts(root):
			outside_classes.append_array(global_classes(FileAccess.get_file_as_string(path)))
	# Without a known outside class the dependency check could not fire.
	if not outside_classes.has("ThumbstickMapping"):
		return "no global class found in xr/; found %s" % [outside_classes]
	var findings: Array[String] = []
	for path: String in scripts:
		findings.append_array(scan_source(
			FileAccess.get_file_as_string(path), path, layer_classes, outside_classes))
	return "\n".join(findings)


func test_collect_scripts_looks_into_subfolders() -> String:
	var nested: String = SCRATCH_DIR + "/a/b"
	DirAccess.make_dir_recursive_absolute(nested)
	for path: String in [SCRATCH_DIR + "/top.gd", nested + "/deep.gd", nested + "/notes.txt"]:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string("extends RefCounted\n")
		file.close()
	var found: Array[String] = collect_scripts(SCRATCH_DIR)
	for path: String in [nested + "/deep.gd", nested + "/notes.txt", SCRATCH_DIR + "/top.gd",
			nested, SCRATCH_DIR + "/a", SCRATCH_DIR]:
		DirAccess.remove_absolute(path)
	if found != [nested + "/deep.gd", SCRATCH_DIR + "/top.gd"]:
		return "found %s" % [found]
	return ""


func test_scan_reports_a_base_class_outside_the_layers() -> String:
	var cases: Dictionary[String, String] = {
		"extends Resource\n": "Resource",
		"class_name Thing extends Object\n": "Object",
		"class Inner extends Resource:\n\tpass\n": "Resource",
		"extends \"res://view/test_tunnel.gd\"\n": "\"res://view/test_tunnel.gd\"",
	}
	for source: String in cases:
		var problem: String = _expect_one(source, 1, "extends " + cases[source])
		if problem != "":
			return problem
	return ""


func test_scan_accepts_bases_from_core_and_gen() -> String:
	var source: String = "\n".join([
		"class_name Drone", "extends ShipState", "",
		"class Part extends RefCounted:", "\tpass", "",
		"class Gun extends Part:", "\tpass", "",
		"class Wing extends \"res://gen/wing.gd\":", "\tpass", ""])
	var findings: Array[String] = _scan(source)
	if not findings.is_empty():
		return "reported %s" % [findings]
	return ""


func test_scan_reports_every_forbidden_api() -> String:
	for api: String in FORBIDDEN_APIS:
		var problem: String = _expect_one("extends RefCounted\n\tfoo(%s)\n" % api, 2, "'%s'" % api)
		if problem != "":
			return problem
	return ""


func test_scan_reports_one_snippet_per_category() -> String:
	var cases: Dictionary[String, String] = {
		"\tvar parent: Node3D = null\n": "'Node'",
		"\tRenderingServer.force_draw()\n": "'RenderingServer'",
		"\tif Input.is_action_pressed(\"fire\"):\n": "'Input.'",
		"\tAudioServer.set_bus_mute(0, true)\n": "'AudioServer'",
		"\tvar now: int = Time.get_ticks_msec()\n": "'Time.'",
		"\tvar roll: int = randi() % 6\n": "'randi'",
	}
	for line: String in cases:
		var problem: String = _expect_one("extends RefCounted\n\n" + line, 3, cases[line])
		if problem != "":
			return problem
	return ""


func test_scan_reports_unseeded_randomness() -> String:
	for call: String in GLOBAL_RANDOM + ANY_RANDOM:
		var problem: String = _expect_one("\tvar x = %s()\n" % call, 1, "'%s'" % call)
		if problem != "":
			return problem
	for line: String in ["\tdeck.shuffle()\n", "\tvar card = deck.pick_random()\n", "\trng.randomize()\n"]:
		if _scan(line).size() != 1:
			return "expected 1 finding for %s, got %s" % [line.c_escape(), _scan(line)]
	return ""


func test_scan_allows_a_seeded_generator_and_lookalike_names() -> String:
	var source: String = "\n".join([
		"extends RefCounted",
		"var rng: RandomNumberGenerator = RandomNumberGenerator.new()",
		"func roll(input: ShipInput) -> float:",
		"\trng.seed = 7",
		"\tvar other: ShipInput = ShipInput.new()",
		"\tvar junction: PathNode = PathNode.new()",
		"\tseeded_shuffle(junction.exits, rng)",
		"\treturn rng.randf() + rng.randi_range(1, 6) + rng.randfn() + run_time.x",
		""])
	var findings: Array[String] = scan_source(source, "res://gen/snippet.gd", ["PathNode"])
	if not findings.is_empty():
		return "reported %s" % [findings]
	return ""


func test_scan_ignores_comments_but_not_code_after_a_hash_in_a_string() -> String:
	var source: String = "\n".join([
		"extends RefCounted",
		"## No Node, no Input.get_vector(), no Time.get_ticks_msec(), no randf().",
		"\t# extends Node3D",
		"var tick: int = 0  # not from Time.get_ticks_msec() or get_tree()",
		""])
	var findings: Array[String] = _scan(source)
	if not findings.is_empty():
		return "comments were reported: %s" % [findings]
	return _expect_one("\tif line.begins_with(\"#\") or 'it\\'s #' == line: get_tree()\n", 1, "'get_tree'")


func test_scan_applies_the_same_rules_to_net() -> String:
	var source: String = "extends RefCounted\n\tvar now: int = Time.get_ticks_msec()\n\tvar x = randf()\n"
	var findings: Array[String] = scan_source(source, "res://net/snippet.gd", [])
	var expected: Array[String] = [
		"res://net/snippet.gd:2: forbidden API 'Time.'",
		"res://net/snippet.gd:3: unseeded randomness 'randf'",
	]
	if findings != expected:
		return "reported %s" % [findings]
	if not SCANNED_DIRS.has("res://net"):
		return "res://net is not scanned"
	return ""


func test_scan_reports_a_path_into_view_xr_or_meta() -> String:
	for dir: String in ["view", "xr", "meta"]:
		var line: String = "\tvar Tunnel = preload(\"res://%s/tunnel.gd\")\n" % dir
		var problem: String = _expect_one(line, 1, "depends on res://" + dir)
		if problem != "":
			return problem
	var allowed: String = "\tconst A = preload(\"res://core/a.gd\")\n\tload(\"res://viewer/b.gd\")\n"
	if not _scan(allowed).is_empty():
		return "reported %s" % [_scan(allowed)]
	return ""


func test_scan_reports_a_class_from_view_xr_or_meta() -> String:
	var outside: Array[String] = ["ThumbstickMapping", "Cockpit"]
	var cases: Dictionary[String, String] = {
		"\tvar m: ThumbstickMapping = null\n": "'ThumbstickMapping'",
		"\tCockpit.shake(ship)\n": "'Cockpit'",
	}
	for line: String in cases:
		var findings: Array[String] = scan_source(line, "res://net/snippet.gd", [], outside)
		if findings.size() != 1 or not findings[0].contains("uses class " + cases[line]):
			return "for %s reported %s" % [line.c_escape(), findings]
	var lookalikes: String = "\tvar cockpit_mapping: MyThumbstickMapping = ship.Cockpit\n"
	var quiet: Array[String] = scan_source(lookalikes, "res://net/snippet.gd", [], outside)
	if not quiet.is_empty():
		return "lookalikes reported %s" % [quiet]
	var base: Array[String] = scan_source("extends Cockpit\n", "res://core/s.gd", [], outside)
	if base.size() != 1 or not base[0].contains("extends Cockpit"):
		return "a bad base should be reported once, got %s" % [base]
	return ""


func test_global_classes_skip_inner_classes() -> String:
	var source: String = "class_name Cockpit\nextends Node3D\nclass Gauge:\n\tpass\n# class_name Old\n"
	if global_classes(source) != ["Cockpit"]:
		return "found %s" % [global_classes(source)]
	return ""
