class_name ChecklistPageModel
extends RefCounted

## What the checklist page (#1325) shows and what each press does; no nodes,
## `ChecklistPage` draws its lines. It sits beside `main.gd` because it reads
## the `meta/` checklist and the `xr/` page draws only text. Input is the dev menu's named actions
## (`DevMenuModel.ACTIONS`), each counted once on the frame it is pressed:
## the stick up and down moves between steps, left and right between the
## choices under the step, and A confirms one. B and Y step the remark too,
## as they step the dev menu's seed, so a remark needs no walk along the row.
##
## `press` returns what was confirmed: `mark:<pass|fail|skip>` (with `remark`
## to go with it), `do` (the step's action), `pin` or `close`; "" otherwise.
## Choosing the remark steps it here and returns "". The model only returns
## these; marking and acting are the wiring's (ARC-3).

const PASS: String = ChecklistSession.PASS
const FAIL: String = ChecklistSession.FAIL
const SKIP: String = ChecklistSession.SKIP
const REMARK: String = "remark"
const DO: String = "do"
const PIN: String = "pin"
const CLOSE: String = "close"
const MARK_PREFIX: String = "mark:"
const CHOICE_WORDS: Dictionary = {PASS: "Pass", FAIL: "Fail", SKIP: "Skip", PIN: "Pin", CLOSE: "Close"}

var session: ChecklistSession
## The step shown, an index into the checklist's steps.
var step: int = 0
## The highlighted choice, an index into `choices()`.
var choice: int = 0
## The remark the next mark carries; "" for none.
var remark: String = ""

var _held: Dictionary = {}


func _init(p_session: ChecklistSession) -> void:
	session = p_session


## On the step to do next, its saved remark chosen. Every action counts as
## held, so the press that opened the page has to be let go first.
func open() -> void:
	show_step(session.current)
	for action: String in DevMenuModel.ACTIONS:
		_held[action] = true


## Shows step `index` with the first choice highlighted.
func show_step(index: int) -> void:
	step = clampi(index, 0, session.checklist.steps.size() - 1)
	choice = 0
	remark = session.remark_of(step)


func current_step() -> ChecklistStep:
	return session.checklist.steps[step]


## The choices under the step, left to right: the marks, the remark when the
## step offers any, its action when it has one, then pin and close.
func choices() -> Array[String]:
	var listed: Array[String] = [PASS, FAIL, SKIP]
	if not current_step().remarks.is_empty():
		listed.append(REMARK)
	if current_step().action != ChecklistStep.ACTION_NONE:
		listed.append(DO)
	listed.append_array([PIN, CLOSE])
	return listed


## One frame of named actions held; returns what was confirmed, or "".
func press(held: Dictionary) -> String:
	var result: String = ""
	var acted: bool = false
	for action: String in DevMenuModel.ACTIONS:
		var down: bool = bool(held.get(action, false))
		if down and not bool(_held.get(action, false)) and not acted:
			acted = true
			result = _act(action)
		_held[action] = down
	return result


## Steps the remark through none and the step's remarks by `direction`.
func step_remark(direction: int) -> void:
	var listed: Array[String] = [""]
	listed.append_array(current_step().remarks)
	remark = listed[posmod(listed.find(remark) + direction, listed.size())]


## The words a choice shows; the remark and action name their value.
func choice_text(name: String) -> String:
	match name:
		REMARK: return "Remark: %s" % (remark if remark != "" else "none")
		DO: return "Do: %s" % current_step().action_text()
	return str(CHOICE_WORDS.get(name, name))


## The full page, top to bottom: where in the checklist, what to do, what to
## look for, the step's mark, the choices with the highlighted one between
## `<` and `>`, and the tally.
func page_lines() -> Array[String]:
	var checklist: Checklist = session.checklist
	var item: ChecklistStep = current_step()
	var lines: Array[String] = ["%s · %s · %d/%d" % [checklist.title, checklist.parts[item.part],
		step + 1, checklist.steps.size()]]
	lines.append("Do: %s" % item.do_text)
	lines.append("Look for: %s" % item.look_for)
	var marked: String = session.mark_of(step)
	var noted: String = session.remark_of(step)
	if marked == "":
		lines.append("Not marked yet")
	else:
		lines.append("Marked %s%s" % [choice_text(marked).to_lower(), " (%s)" % noted if noted != "" else ""])
	var row: Array[String] = []
	var listed: Array[String] = choices()
	for index: int in listed.size():
		var words: String = choice_text(listed[index])
		row.append("< %s >" % words if index == choice else words)
	lines.append("   ".join(row))
	var tally: Dictionary = session.counts()
	lines.append("%d pass · %d fail · %d skip · %d open" % [tally[PASS], tally[FAIL], tally[SKIP], tally["open"]])
	return lines


## The pinned page's one line: the step to do next and what to do.
func pinned_line() -> String:
	var steps: Array[ChecklistStep] = session.checklist.steps
	return "%d/%d  %s" % [session.current + 1, steps.size(), steps[session.current].do_text]


func _act(action: String) -> String:
	match action:
		DevMenuModel.UP, DevMenuModel.DOWN:
			var count: int = session.checklist.steps.size()
			show_step(posmod(step + (-1 if action == DevMenuModel.UP else 1), count))
		DevMenuModel.LEFT, DevMenuModel.RIGHT:
			choice = posmod(choice + (-1 if action == DevMenuModel.LEFT else 1), choices().size())
		DevMenuModel.CONFIRM:
			return _confirm()
		DevMenuModel.SEED_UP, DevMenuModel.SEED_DOWN:
			step_remark(1 if action == DevMenuModel.SEED_UP else -1)
	return ""


func _confirm() -> String:
	var picked: String = choices()[choice]
	if ChecklistSession.MARKS.has(picked):
		return MARK_PREFIX + picked
	if picked == REMARK:
		step_remark(1)
		return ""
	return picked
