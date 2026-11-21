extends RefCounted

## A suspended run keeps its chosen shafts, so a resumed run flies the same
## levels (#1029, RUN-8, RUN-1, ARC-2): save, take and resume give the run that
## was suspended, an old save resumes without choices, and each bad resume is
## refused with a reason.

const RUN: String = "res://data/run/run.json"
const SHAFTS: String = "res://data/run/shafts.json"
const DIR: String = "user://test_run_resume"
const LOADOUT: Dictionary = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}


func _plan(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, FileAccess.get_file_as_string(RUN))


func _shafts() -> ShaftOffer:
	return ShaftOffer.build(FileAccess.get_file_as_string(SHAFTS))


func _state(run_seed: int) -> RunState:
	return RunState.new(_plan(run_seed), _shafts())


## Escapes the current level and takes the offer's `pick`-th shaft, if any.
func _escape_and_choose(state: RunState, pick: int) -> void:
	state.advance()
	if state.needs_choice():
		var offered: Array[String] = state.offer()
		state.choose(offered[pick % offered.size()])


func _same_level(a: RunState, b: RunState) -> String:
	if a.current_depth() != b.current_depth() or a.current_level_seed() != b.current_level_seed():
		return "depth %d seed %d, against depth %d seed %d" % [
			a.current_depth(), a.current_level_seed(), b.current_depth(), b.current_level_seed()]
	if a.current_shaft() != b.current_shaft() or a.current_risk() != b.current_risk():
		return "shaft %s risk %s, against %s %s" % [a.current_shaft(), a.current_risk(), b.current_shaft(), b.current_risk()]
	if a.current_reward() != b.current_reward() or a.needs_choice() != b.needs_choice():
		return "reward %s choice due %s, against %s %s" % [a.current_reward(), a.needs_choice(), b.current_reward(), b.needs_choice()]
	if a.state_hash() != b.state_hash():
		return "state hash %d against %d" % [a.state_hash(), b.state_hash()]
	return ""


func _through_store(run: RunSave) -> RunSave:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: RunSaveStore = RunSaveStore.new(DIR + "/meltdown_run.json")
	store.discard()
	if not store.save(run):
		return null
	var taken: RunSave = RunSaveStore.new(store.path).take()
	store.discard()
	return taken


func test_a_run_saved_after_two_choices_resumes_the_same() -> String:
	for run_seed: int in [0, 7, 12345]:
		var original: RunState = _state(run_seed)
		_escape_and_choose(original, 1)
		_escape_and_choose(original, 2)
		if original.current_depth() != 3 or original.chosen_so_far().size() != 2:
			return "run seed %d: setup reached depth %d with %s" % [run_seed, original.current_depth(), original.chosen_so_far()]
		var run: RunSave = RunResume.to_save(original, "default_ship", LOADOUT)
		if run.error != "":
			return "run seed %d: to_save refused: %s" % [run_seed, run.error]
		var taken: RunSave = _through_store(run)
		if taken == null or taken.chosen != original.chosen_so_far():
			return "run seed %d: took %s" % [run_seed, taken.to_json() if taken != null else "nothing"]
		var resumed: RunState = RunResume.resume(taken, _plan(taken.run_seed), _shafts())
		if resumed.error != "":
			return "run seed %d: resume refused: %s" % [run_seed, resumed.error]
		var differs: String = _same_level(resumed, original)
		if differs != "":
			return "run seed %d: %s" % [run_seed, differs]
		# The two runs stay together through the rest of the run.
		while not original.is_over():
			_escape_and_choose(original, 0)
			_escape_and_choose(resumed, 0)
			differs = _same_level(resumed, original)
			if differs != "" or resumed.won != original.won:
				return "run seed %d after resuming: %s" % [run_seed, differs]
	return ""


func test_a_run_saved_before_its_choice_resumes_with_the_choice_due() -> String:
	var original: RunState = _state(12345)
	_escape_and_choose(original, 0)
	original.advance()
	if not original.needs_choice():
		return "setup did not wait for a choice"
	var taken: RunSave = _through_store(RunResume.to_save(original, "default_ship", LOADOUT))
	if taken == null or taken.chosen.size() != 1 or taken.next_level != 3:
		return "took %s" % (taken.to_json() if taken != null else "nothing")
	var resumed: RunState = RunResume.resume(taken, _plan(12345), _shafts())
	var differs: String = _same_level(resumed, original)
	if differs != "" or resumed.offer() != original.offer():
		return differs if differs != "" else "offers %s against %s" % [resumed.offer(), original.offer()]
	original.choose(original.offer()[0])
	resumed.choose(resumed.offer()[0])
	return _same_level(resumed, original)


func test_an_old_save_without_choices_resumes_without_choices() -> String:
	var text: String = "{\"version\": 1, \"run_seed\": \"12345\", \"next_level\": 3, \"ship\": \"default_ship\", \"loadout\": %s}" % JSON.stringify(LOADOUT)
	var old: RunSave = RunSave.parse_json(text)
	if old.error != "" or not old.chosen.is_empty() or old.version != 1:
		return "version-1 save read as '%s', chosen %s" % [old.error, old.chosen]
	var resumed: RunState = RunResume.resume(old, _plan(12345), _shafts())
	if resumed.error != "" or resumed.current_depth() != 3:
		return "resume: '%s', depth %d" % [resumed.error, resumed.current_depth()]
	if resumed.current_shaft() != "" or not resumed.chosen_so_far().is_empty() or not resumed.needs_choice():
		return "an old save resumed with shaft '%s', chosen %s" % [resumed.current_shaft(), resumed.chosen_so_far()]
	var plain: RunState = RunState.resumed(_plan(12345), null, null, 3, [] as Array[String])
	if plain.error != "" or plain.current_level_seed() != plain.plan.level_seed(2) or plain.needs_choice():
		return "a run without a shaft offer resumed as '%s', seed %d" % [plain.error, plain.current_level_seed()]
	return ""


func test_each_bad_resume_is_refused_with_a_reason() -> String:
	var plan: RunPlan = _plan(12345)
	var shafts: ShaftOffer = _shafts()
	var first: Array[String] = plan.offer_after(0, shafts)
	var unoffered: String = ""
	for kind: String in shafts.kinds:
		if not first.has(kind):
			unoffered = kind
	var cases: Array = [
		[0, [] as Array[String], "outside"],
		[plan.level_count() + 1, [] as Array[String], "outside"],
		[2, ["not_a_shaft"] as Array[String], "not_a_shaft"],
		[3, [first[0], first[0], first[0]] as Array[String], "do not fit"],
		[4, [first[0]] as Array[String], "do not fit"],
		[1, [first[0]] as Array[String], "do not fit"],
	]
	if unoffered != "":
		cases.append([2, [unoffered] as Array[String], unoffered])
	for case: Array in cases:
		var state: RunState = RunState.resumed(plan, shafts, null, case[0], case[1])
		if not state.error.contains(case[2]) or state.level_index != 0:
			return "depth %d with %s: '%s'" % [case[0], case[1], state.error]
	var no_offer: RunState = RunState.resumed(plan, null, null, 2, [first[0]] as Array[String])
	if not no_offer.error.contains("without a shaft offer"):
		return "choices without an offer: '%s'" % no_offer.error
	var run: RunSave = RunResume.to_save(_advanced(_state(12345)), "default_ship", LOADOUT)
	var wrong_plan: RunState = RunResume.resume(run, _plan(54321), shafts)
	if not wrong_plan.error.contains("run seed"):
		return "a plan for another seed: '%s'" % wrong_plan.error
	return ""


func test_a_run_that_cannot_suspend_gives_no_save() -> String:
	var fresh: RunState = _state(12345)
	var carrying: RunState = _advanced(_state(12345))
	carrying.choose(carrying.offer()[0])
	carrying.carry({"scrap": 1})
	var lost: RunState = _advanced(_state(12345))
	lost.lose()
	for state: RunState in [fresh, carrying, lost]:
		var run: RunSave = RunResume.to_save(state, "default_ship", LOADOUT)
		if run.error == "" or run.ship != "":
			return "depth %d, carried %s, lost %s gave a save" % [state.current_depth(), state.carried, state.lost]
	var bad_ship: RunSave = RunResume.to_save(_advanced(_state(12345)), "", LOADOUT)
	return "" if bad_ship.error.contains("ship") else "an empty ship id: '%s'" % bad_ship.error


func _advanced(state: RunState) -> RunState:
	state.advance()
	return state
