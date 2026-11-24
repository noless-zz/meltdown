extends RefCounted

## The `reactor_wreck_look` acceptance check (#1310): it passes on a burning,
## breached machine and fails on an intact one or on the bare sphere.

const CHECK_SCRIPT: String = "res://acceptance/checks/reactor_look_check.gd"


func _judge(view: ReactorView) -> Array:
	var script: GDScript = load(CHECK_SCRIPT)
	return script.call("judge_view", view, {})


func test_registers_its_name() -> String:
	var script: GDScript = load(CHECK_SCRIPT)
	var judges: Dictionary = script.call("judges")
	return "" if judges.has("reactor_wreck_look") else "the check is not registered under reactor_wreck_look"


func test_passes_on_the_burning_wreck() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 40.0)
	var result: Array = _judge(view)
	view.free()
	return "" if result[0] == AcceptanceReport.RESULT_PASS else "the wreck failed: %s" % result[1]


func test_fails_on_the_intact_machine() -> String:
	var view: ReactorView = ReactorView.new()
	view.show_state(Vector3.ZERO, 2.5, 1.0, false, 90.0)
	var result: Array = _judge(view)
	view.free()
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "an intact reactor passed as a wreck"


func test_fails_without_a_machine() -> String:
	var view: ReactorView = ReactorView.new()
	var path: String = "user://test_reactor_look_check_bare.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ReactorLook.DEFAULT_FILE))
	data.erase(ReactorLook.MACHINE_KEY)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	view.load_look(path)
	view.show_state(Vector3.ZERO, 2.5, 0.0, true, 40.0)
	var result: Array = _judge(view)
	view.free()
	DirAccess.remove_absolute(path)
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "a bare sphere passed as the machine's wreck"
