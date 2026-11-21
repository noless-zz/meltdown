class_name FlightTestPanel
extends Node3D

## Shows the first-launch flight test (CMF-4) to the pilot: what to do in the
## current segment and how long it runs, the three answers while one is due,
## and at the end the recommended preset's name and how to change it.
##
## Drawn like the status panel's labels, at its pixel size and font sizes and
## `raise_m` above it in its plane, so it reads at the same distance. It only
## reads a `FlightTestSession` and never writes to it or to the simulation
## (ARC-3, CMF-6). Text only, no motion (CMF-3). The words live in
## `res://xr/flight_test/panel.json` (`FlightTestPanelText`, ARC-4); the
## answer line names each answer's button from the answers file (#764).

const NODE_NAME: String = "FlightTestPanel"
const MAIN_NAME: String = "FlightTestMain"
const DETAIL_NAME: String = "FlightTestDetail"
const ANSWERS_NAME: String = "FlightTestAnswers"
const DETAIL_Y: float = -0.045
const ANSWERS_Y: float = -0.075

## Set when the text file was rejected and the built-in words are used; empty otherwise.
var text_error: String = ""
## Set when the answer line could not name the buttons and the plain
## `answers` text is shown; names the field. Empty otherwise.
var answer_line_error: String = ""

var _text: Dictionary = FlightTestPanelText.FALLBACK
var _main: Label3D
var _detail: Label3D
var _answers: Label3D
var _preset_names: Dictionary[int, String] = {}
var _buttons: Dictionary[String, String] = FlightTestAnswers.DEFAULTS.duplicate()
var _answer_line: String = ""


## The wiring builds the panel without arguments, so it reads the shipped
## answers file itself; `set_buttons` overrides that.
func _init(path: String = FlightTestPanelText.DEFAULT_FILE,
		answers_path: String = FlightTestAnswers.DEFAULT_FILE) -> void:
	name = NODE_NAME
	_main = _label(MAIN_NAME, 0.0, StatusPanel.LARGE_FONT / 2)
	_detail = _label(DETAIL_NAME, DETAIL_Y, StatusPanel.SMALL_FONT)
	_answers = _label(ANSWERS_NAME, ANSWERS_Y, StatusPanel.SMALL_FONT)
	_buttons = FlightTestAnswers.load_file(answers_path).buttons
	load_text(path)


## Applies the panel text file at `path`. A missing or rejected file keeps the
## built-in words, sets `text_error` and pushes a warning naming the field.
func load_text(path: String = FlightTestPanelText.DEFAULT_FILE) -> String:
	_text = FlightTestPanelText.load_file(path)
	text_error = str(_text.get("error", ""))
	if text_error != "":
		push_warning("FlightTestPanel uses the built-in words; %s" % text_error)
	_build_answer_line()
	return text_error


## Uses `buttons` (answer -> button, as `FlightTestAnswers.buttons`) for the
## answer line.
func set_buttons(buttons: Dictionary[String, String]) -> void:
	_buttons = buttons.duplicate()
	_build_answer_line()


## The line shown while an answer is due.
func answer_line() -> String:
	return _answer_line


## The panel's transform under the rig origin: the status panel's, raised by
## `raise_m` in its own plane. See `StatusPanel.rig_transform`.
func rig_transform(cockpit: Transform3D) -> Transform3D:
	return StatusPanel.rig_transform(cockpit) * Transform3D(Basis.IDENTITY, Vector3(0.0, raise_m(), 0.0))


func raise_m() -> float:
	return float(_text["raise_m"])


## Draws the state of `session`. Reads it only.
func show_session(session: FlightTestSession) -> void:
	if session == null:
		visible = false
		return
	visible = true
	if session.finished():
		var preset: int = session.recommended()
		StatusPanelLabels.set_text(_main, str(_text["result"]).replace("{preset}", preset_name(preset)))
		StatusPanelLabels.set_text(_detail, str(_text["change_hint"]))
		_answers.visible = false
		return
	var segment: FlightTestSegment = session.current_segment()
	StatusPanelLabels.set_text(_main, instruction(segment.manoeuvre))
	if session.awaiting_answer():
		StatusPanelLabels.set_text(_detail, str(_text["question"]))
		StatusPanelLabels.set_text(_answers, _answer_line)
		_answers.visible = true
	else:
		var seconds: int = ceili(session.seconds_left())
		StatusPanelLabels.set_text(_detail, str(_text["time_left"]).replace("{seconds}", str(seconds)))
		_answers.visible = false


## The instruction shown for `manoeuvre`; the manoeuvre's key when the text has none.
func instruction(manoeuvre: String) -> String:
	return str((_text["instructions"] as Dictionary).get(manoeuvre, manoeuvre))


## The display name of comfort preset `number` (1..4), from its preset file.
func preset_name(number: int) -> String:
	if not _preset_names.has(number):
		var preset: ComfortPreset = null
		if number >= 1 and number <= ComfortPresetFiles.PATHS.size():
			preset = ComfortPresetFiles.load_number(number)
		_preset_names[number] = "%d %s" % [number, preset.display_name] if preset != null else str(number)
	return _preset_names[number]


## Text of the three lines and whether the answers line shows, for tests.
func shown() -> Dictionary:
	return {"main": _main.text, "detail": _detail.text, "answers": _answers.text if _answers.visible else ""}


# A bad answer line falls back to the plain `answers` text, logged once per
# change so a broken template does not flood the log.
func _build_answer_line() -> void:
	var built: Dictionary = FlightTestAnswerLine.build(_text.get("answer_line"), _buttons)
	var error: String = str(built.get("error", ""))
	_answer_line = str(built["line"]) if error == "" else str(_text["answers"])
	if error != "" and error != answer_line_error:
		push_warning("FlightTestPanel shows the plain answer line; %s" % error)
	answer_line_error = error


func _label(label_name: String, y: float, font_size: int) -> Label3D:
	var label: Label3D = StatusPanelLabels.make(self, label_name, Vector3(0.0, y, 0.0), font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
