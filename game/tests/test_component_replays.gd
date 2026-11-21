extends RefCounted

## Component drops are off unless switched on (#976): every shipped replay that
## carries its own level, the m1 to m3 suites' included, still ends on its
## recorded hash (the suite tests pin the generated-level ones), and the new
## core files keep the layer rules (ARC-1).

const LayerScanner := preload("res://tests/layer_scanner.gd")
const REPLAY_DIRS: Array[String] = ["res://acceptance/replays", "res://tests/replays"]
const NEW_FILES: Array[String] = ["res://core/component_item.gd", "res://core/component_pickup.gd"]


func test_shipped_replays_keep_their_hashes() -> String:
	var checked: int = 0
	for dir: String in REPLAY_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if file.get_extension() != "replay":
				continue
			var replay: Replay = Replay.load_file("%s/%s" % [dir, file])
			# A replay without walls holds inputs only: its suite builds the level
			# from a seed, and the suite tests compare those hashes.
			if replay == null or replay.error != "" or replay.expected_hash == Replay.NO_HASH \
					or replay.walls() == null:
				continue
			var sim: Sim = replay.run()
			if sim == null:
				return "%s did not run: %s" % [file, replay.run_error]
			if sim.state_hash() != replay.expected_hash:
				return "%s ends on %d, recorded %d" % [file, sim.state_hash(), replay.expected_hash]
			checked += 1
	# A loop that checked nothing would pass forever.
	print("Meltdown: %d self-contained replays keep their hashes" % checked)
	if checked < 5:
		return "only %d replays checked" % checked
	return ""


func test_new_component_files_keep_the_layer_rules() -> String:
	var scanner: LayerScanner = LayerScanner.new()
	var classes: Array[String] = []
	for path: String in scanner.collect_scripts("res://core"):
		classes.append_array(scanner.declared_classes(FileAccess.get_file_as_string(path)))
	var findings: Array[String] = []
	for path: String in NEW_FILES:
		var source: String = FileAccess.get_file_as_string(path)
		if source.is_empty():
			return "%s is missing" % path
		findings.append_array(scanner.scan_source(source, path, classes))
	return "\n".join(findings)
