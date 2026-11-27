extends RefCounted

## The shaft choice's sounds (#1455, AUD-1, RUN-1, ARC-3, MP-2): pointing onto
## another shaft plays point once, holding still plays nothing, a taken choice
## plays select then launch, a refused press plays refused, a repeat waits out
## its gap, a bad file leaves the choice silent, and none of it changes the
## panel or the run. Sounds are only recorded here (no audio device).

const RUN_SEED: int = 12345
const FRAME: float = 1.0 / 60.0
const A: Dictionary = {DestroyedWiring.RESTART_BUTTON: true}
## The first of run 12345's offer after level one (`test_shaft_panel.gd`).
const FIRST_SHAFT: String = "deep"
const DOWN: Vector2 = Vector2(0.0, -1.0)
const UP: Vector2 = Vector2(0.0, 1.0)


static func _sounds(table: ShaftSoundTable = ShaftSoundTable.load_file()) -> ShaftChoiceSounds:
	var sounds: ShaftChoiceSounds = ShaftChoiceSounds.new(table)
	sounds.enabled = false
	return sounds


## One frame of `choice`: the values read, then the panel updated.
static func _frame(choice: ShaftChoiceWiring, run: RunWiring, buttons: Dictionary = {},
		stick: Vector2 = Vector2.ZERO, paused: bool = false) -> bool:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons.duplicate()
	values["right_stick"] = stick
	choice.read(values)
	return choice.update(run, paused, Transform3D.IDENTITY, false, FRAME)


## Frames of `stick` then frames of rest, long enough together to pass the point gap.
static func _step(choice: ShaftChoiceWiring, run: RunWiring, stick: Vector2) -> void:
	for i: int in 5:
		_frame(choice, run, {}, stick)
	for i: int in 5:
		_frame(choice, run)


## An open choice on run 12345's first offer, attached to `rig`, with its
## sounds recorded only.
static func _open(rig: Node3D) -> Array:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77)
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	choice.attach(rig)
	choice.sounds.enabled = false
	choice.open(run, {})
	_frame(choice, run, A)  # The press that opened it, still held.
	_frame(choice, run)
	return [choice, run]


func test_the_node_plays_once_per_gap() -> String:
	var sounds: ShaftChoiceSounds = _sounds()
	var problem: String = ""
	if sounds.hear(0, 1, "", false, FRAME) != Array(["point"], TYPE_STRING, "", null):
		problem = "a highlight change did not point"
	elif not sounds.hear(1, 2, "", false, FRAME).is_empty():
		problem = "point repeated inside its gap"
	elif not sounds.hear(2, 2, "", false, 1.0).is_empty():
		problem = "a still highlight made a sound"
	elif sounds.hear(2, 1, "", false, FRAME) != Array(["point"], TYPE_STRING, "", null):
		problem = "point did not play again after its gap"
	elif sounds.requested != Array(["point", "point"], TYPE_STRING, "", null):
		problem = "requested %s" % [sounds.requested]
	sounds.opened()
	if problem == "" and (not sounds.requested.is_empty() or sounds.hear(0, 1, "", false, 0.0).is_empty()):
		problem = "opening did not start a fresh log with nothing held back"
	sounds.free()
	return problem


func test_a_bad_file_leaves_the_choice_silent() -> String:
	var table: ShaftSoundTable = ShaftSoundTable.parse("{\"voices\": 0}")
	var sounds: ShaftChoiceSounds = _sounds(table)
	var played: Array[String] = sounds.hear(0, 1, "deep", true, 1.0)
	var problem: String = ""
	if not played.is_empty() or not sounds.requested.is_empty() or sounds.get_child_count() != 0:
		problem = "a refused table still played %s with %d voices" % [played, sounds.get_child_count()]
	sounds.free()
	return problem


func test_the_stick_points_and_a_chooses_and_launches() -> String:
	var rig: Node3D = Node3D.new()
	var opened: Array = _open(rig)
	var choice: ShaftChoiceWiring = opened[0]
	var run: RunWiring = opened[1]
	var sounds: ShaftChoiceSounds = choice.sounds
	var problem: String = ""
	if sounds == null or sounds.get_parent() != choice.panel:
		problem = "the sounds do not hang under the panel"
	elif not sounds.requested.is_empty():
		problem = "opening the panel played %s" % [sounds.requested]
	else:
		_step(choice, run, DOWN)
		_step(choice, run, UP)
		for i: int in 30:
			_frame(choice, run)  # Holding still.
		if sounds.requested != Array(["point", "point"], TYPE_STRING, "", null):
			problem = "down, up and a still hold played %s" % [sounds.requested]
		elif not _frame(choice, run, A):
			problem = "A did not take the shaft"
		elif sounds.requested != Array(["point", "point", "select", "launch"], TYPE_STRING, "", null):
			problem = "choosing played %s" % [sounds.requested]
		elif run.state.current_shaft() != FIRST_SHAFT:
			problem = "back up on the first shaft, A took '%s'" % run.state.current_shaft()
	rig.free()
	return problem


func test_a_refused_press_plays_refused_and_leaves_the_panel_open() -> String:
	var rig: Node3D = Node3D.new()
	var opened: Array = _open(rig)
	var choice: ShaftChoiceWiring = opened[0]
	var problem: String = ""
	# No run to take it: the press is answered but refused.
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = A.duplicate()
	choice.read(values)
	if choice.update(null, false, Transform3D.IDENTITY, false, FRAME) or not choice.is_open():
		problem = "a refused press closed the panel"
	elif choice.sounds.requested != Array(["refused"], TYPE_STRING, "", null):
		problem = "a refused press played %s" % [choice.sounds.requested]
	rig.free()
	return problem


func test_a_paused_session_makes_no_sound() -> String:
	var rig: Node3D = Node3D.new()
	var opened: Array = _open(rig)
	var choice: ShaftChoiceWiring = opened[0]
	var run: RunWiring = opened[1]
	for i: int in 5:
		_frame(choice, run, {}, DOWN, true)
	_frame(choice, run, A, Vector2.ZERO, true)
	var problem: String = ""
	if not choice.sounds.requested.is_empty() or choice.model.highlight != 0:
		problem = "while paused: played %s, highlight %d" % [choice.sounds.requested, choice.model.highlight]
	rig.free()
	return problem
