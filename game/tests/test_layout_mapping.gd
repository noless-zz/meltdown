extends RefCounted

## The game's mapping comes from the layout file (#875, PLT-5, ARC-4): the main
## scene flies the file's bindings and dead zone, a scratch file with a wider
## dead zone reaches the mapping, and a missing or rejected file falls back to
## the built-in layout with one warning naming the file.

const SCRATCH: String = "user://t875_layout.json"
const MISSING: String = "user://t875_no_such_layout.json"


func _write_scratch(text: String) -> void:
	var file: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## The shipped default layout with `stick_dead_zone` replaced.
func _default_with_dead_zone(value: String) -> String:
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(ThumbstickMapping.DEFAULT_LAYOUT_FILE))
	data.erase(StickDeadZone.FIELD)
	var text: String = JSON.stringify(data)
	return "{\"%s\": %s, %s" % [StickDeadZone.FIELD, value, text.substr(1)]


static func _yaw_at(mapping: ThumbstickMapping, deflection: float) -> float:
	return mapping.map_controls(Vector2.ZERO, Vector2(deflection, 0.0), 0.0, 0.0, 0.0, 0.0).turn().y


func test_main_scene_flies_the_file() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	var mapping: ThumbstickMapping = main.get("mapping")
	main.free()
	var file: ThumbstickMapping = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	if file.error != "":
		return "shipped layout rejected: %s" % file.error
	if mapping.layout != file.layout:
		return "main scene layout %s differs from the file's %s" % [mapping.layout, file.layout]
	if mapping.stick_dead_zone != file.stick_dead_zone:
		return "main scene dead zone %s, file %s" % [mapping.stick_dead_zone, file.stick_dead_zone]
	if mapping.error != "" or mapping.warning != "":
		return "main scene mapping error \"%s\" warning \"%s\"" % [mapping.error, mapping.warning]
	return ""


func test_shipped_file_flies_as_the_built_in_layout() -> String:
	var mapping: ThumbstickMapping = LayoutMapping.load_file()
	if mapping.layout != ThumbstickMapping.default_layout():
		return "shipped file differs from the built-in layout, so flight would change"
	if mapping.stick_dead_zone != ThumbstickMapping.STICK_DEAD_ZONE:
		return "shipped dead zone %s" % mapping.stick_dead_zone
	return ""


func test_scratch_dead_zone_reaches_the_mapping() -> String:
	_write_scratch(_default_with_dead_zone("0.25"))
	var mapping: ThumbstickMapping = LayoutMapping.load_file(SCRATCH)
	_cleanup()
	if mapping.error != "" or mapping.warning != "":
		return "scratch layout: error \"%s\" warning \"%s\"" % [mapping.error, mapping.warning]
	if mapping.stick_dead_zone != 0.25:
		return "dead zone %s, want 0.25" % mapping.stick_dead_zone
	if _yaw_at(mapping, 0.2) != 0.0:
		return "0.2 deflection turns the ship with a 0.25 dead zone"
	if _yaw_at(LayoutMapping.load_file(), 0.2) == 0.0:
		return "0.2 deflection does nothing with the shipped 0.15 dead zone"
	return ""


func test_scratch_bindings_reach_the_mapping() -> String:
	_write_scratch("{\"yaw\": {\"left_stick_x\": 1.0}}")
	var mapping: ThumbstickMapping = LayoutMapping.load_file(SCRATCH)
	_cleanup()
	if mapping.layout != {"yaw": {"left_stick_x": 1.0}}:
		return "scratch bindings not used: %s" % mapping.layout
	return ""


func test_missing_file_flies_the_built_in_layout() -> String:
	var mapping: ThumbstickMapping = LayoutMapping.load_file(MISSING)
	if mapping.error == "":
		return "missing file not reported"
	if mapping.layout != ThumbstickMapping.default_layout():
		return "missing file did not give the built-in layout"
	if mapping.stick_dead_zone != ThumbstickMapping.STICK_DEAD_ZONE:
		return "missing file dead zone %s" % mapping.stick_dead_zone
	if not LayoutMapping.fallback_warning(MISSING, mapping.error).contains(MISSING):
		return "warning does not name the file"
	return ""


func test_rejected_file_flies_the_built_in_layout() -> String:
	_write_scratch("{\"yaw\": {\"left_stick_q\": 1.0}}")
	var mapping: ThumbstickMapping = LayoutMapping.load_file(SCRATCH)
	_cleanup()
	if mapping.error == "":
		return "rejected file not reported"
	if mapping.layout != ThumbstickMapping.default_layout():
		return "rejected file did not give the built-in layout"
	if not LayoutMapping.fallback_warning(SCRATCH, mapping.error).contains(SCRATCH):
		return "warning does not name the file"
	return ""


func test_rejected_dead_zone_keeps_the_file_bindings() -> String:
	_write_scratch("{\"%s\": 2.0, \"yaw\": {\"left_stick_x\": 1.0}}" % StickDeadZone.FIELD)
	var mapping: ThumbstickMapping = LayoutMapping.load_file(SCRATCH)
	_cleanup()
	if mapping.error != "":
		return "bindings rejected with the dead zone: %s" % mapping.error
	if mapping.layout != {"yaw": {"left_stick_x": 1.0}}:
		return "file bindings not kept: %s" % mapping.layout
	if mapping.stick_dead_zone != 0.15:
		return "dead zone %s, want 0.15" % mapping.stick_dead_zone
	if not mapping.warning.contains(SCRATCH):
		return "dead zone warning does not name the file: %s" % mapping.warning
	return ""
