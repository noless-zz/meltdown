extends RefCounted

## The m6 `menu_look` step (#1458, CRW-2, PLT-5, decision record 0005): run
## through the acceptance runner on the real scene, the menu opens in the mine
## and at the home base, and every row it shows, in the top list and in a
## section, draws its icon and its value. The pilot's own files are never
## touched.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/menu.json"
const CHECK: GDScript = preload("res://acceptance/checks/menu_look_check.gd")
const FRAME_LIMIT: int = 20000


static func _runner() -> AcceptanceRunner:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == CHECK.CHECK:
			kept.append(found)
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func test_the_check_is_registered_and_the_step_is_in_the_menu_part() -> String:
	if not AcceptanceCheckFiles.judges().has(CHECK.CHECK):
		return "no check file judges %s: %s" % [CHECK.CHECK, AcceptanceCheckFiles.problem()]
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"id\": \"%s\"" % CHECK.CHECK):
		return "%s has no step %s" % [PART_PATH, CHECK.CHECK]
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	for found: AcceptanceStep in suite.steps:
		if found.id == CHECK.CHECK and found.checks[-1] != found.id:
			return "step %s checks %s; its own check must be last" % [found.id, found.checks]
	return ""


func test_the_check_finds_a_row_without_its_drawing() -> String:
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	menu.open("centre", "")
	var clean: String = CHECK.rows_problem(menu)
	var row: DevMenuRow = menu.shown_rows()[0]
	row.icon.free()
	row.icon = null
	var broken: String = CHECK.rows_problem(menu)
	menu.free()
	if clean != "" or broken == "":
		return "the check said \"%s\" of the menu and \"%s\" with an icon gone" % [clean, broken]
	return ""


func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _runner()
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		for key: String in ["rows_mine_top", "rows_mine_section", "rows_base_top", "rows_base_section"]:
			if str(measured.get(key, "")) == "":
				problem = "the step measured no %s: %s" % [key, measured]
	for path: String in [CHECK.PROFILE_FILE, CHECK.FITTING_FILE]:
		if FileAccess.file_exists(path):
			problem = "the step left %s behind" % path
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
