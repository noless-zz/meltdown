extends RefCounted

## The `checklist` check (#1325, DEV-6), lane-a's file under
## `acceptance/checks/`. In `suites/m6/ship.json`:
##
##     {"id": "checklist", "checks": ["no_script_errors", "checklist"]}
##
## In a development build the scene's checklist must be attached and offered
## in the dev menu; the check opens the page, marks its first step with the A
## press the stick and A would give (`ChecklistWiring.read`), and fails unless
## the results file is written with that mark and the build commit. It marks a
## fresh session saved under a scratch name, so the owner's own marks and
## results file are untouched, and closes the page afterwards. In a release
## build the page and its menu row must be absent.

const CHECK: String = "checklist"
const SCRATCH_PREFIX: String = "user://acceptance_checklist_"
const CONFIRM_BUTTON: String = "right_button_lower"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	if main == null:
		return [AcceptanceReport.RESULT_SKIPPED, "no scene"]
	var info: BuildInfo = main.get("build_info") as BuildInfo
	return judge_wiring(main.get("checklist") as ChecklistWiring, main.get("dev_menu") as DevMenuWiring,
		info.commit if info != null else BuildInfo.UNKNOWN, measurements)


## The verdict for `checklist` offered in `dev_menu`, its results carrying `commit`.
static func judge_wiring(checklist: ChecklistWiring, dev_menu: DevMenuWiring, commit: String,
		measurements: Dictionary) -> Array:
	if checklist == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no checklist wiring"]
	var entry: DevMenuChecklist = dev_menu.entry_for(DevMenuSpec.KIND_CHECKLIST) as DevMenuChecklist \
		if dev_menu != null else null
	var offered: bool = entry != null and entry.open_page.is_valid()
	if not checklist.available:
		if checklist.page != null or offered:
			return [AcceptanceReport.RESULT_FAIL, "a release build shows the checklist"]
		return [AcceptanceReport.RESULT_PASS, "release build: no checklist page and no menu row"]
	if checklist.checklist == null or checklist.page == null:
		return [AcceptanceReport.RESULT_FAIL, "no checklist attached; the shipped file was refused or missing"]
	if not offered:
		return [AcceptanceReport.RESULT_FAIL, "the dev menu does not offer the checklist"]
	var kept: Array = [checklist.session, checklist.model, checklist.store.prefix]
	checklist.session = ChecklistSession.new(checklist.checklist)
	checklist.model = ChecklistPageModel.new(checklist.session)
	checklist.store.prefix = SCRATCH_PREFIX
	var path: String = checklist.store.path_for(checklist.checklist.id)
	DirAccess.remove_absolute(path)
	var verdict: Array = _mark_first_step(checklist, path, commit, measurements)
	checklist.close()
	checklist.read(ControllerSampler.idle_values())  # Lets go of the page's pause.
	checklist.session = kept[0]
	checklist.model = kept[1]
	checklist.store.prefix = kept[2]
	return verdict


static func _mark_first_step(checklist: ChecklistWiring, path: String, commit: String,
		measurements: Dictionary) -> Array:
	checklist.open()
	if not checklist.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the page did not open"]
	var idle: Dictionary = ControllerSampler.idle_values()
	var pressed: Dictionary = ControllerSampler.idle_values()
	pressed["buttons"][CONFIRM_BUTTON] = true
	checklist.read(idle)
	checklist.read(pressed)
	checklist.read(idle)
	if not FileAccess.file_exists(path):
		return [AcceptanceReport.RESULT_FAIL, "A on the first step wrote no results file at %s" % path]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("steps")) != TYPE_ARRAY:
		return [AcceptanceReport.RESULT_FAIL, "the results file at %s is not readable" % path]
	var first: Dictionary = data["steps"][0]
	measurements["checklist_steps"] = (data["steps"] as Array).size()
	if first.get("mark") != ChecklistSession.PASS or str(data.get("build")) != commit:
		return [AcceptanceReport.RESULT_FAIL, "saved %s for build %s, want pass for %s" % [first, data.get("build"), commit]]
	return [AcceptanceReport.RESULT_PASS, "%s: first step marked pass with A and saved to %s with build %s" \
		% [checklist.checklist.id, path, commit]]
