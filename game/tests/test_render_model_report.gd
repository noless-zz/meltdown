extends RefCounted

## Render-model logging for the Quest 3 controller check (#145, PLT-2, PLT-5):
## both `MELTDOWN_RENDER_MODELS` lines have a fixed JSON shape, the second
## line comes once (first model added, ten seconds, or exit), nothing is
## printed without an OpenXR interface, and the rig starts the report
## without changing the controller shapes.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const PREFIX: String = "MELTDOWN_RENDER_MODELS "


## The JSON after the prefix, or null when the line is not one of ours.
static func _parse(line: String) -> Variant:
	if not line.begins_with(PREFIX):
		return null
	return JSON.parse_string(line.substr(PREFIX.length()))


static func _keys_are(report: Dictionary, want: Array) -> String:
	var keys: Array = report.keys()
	keys.sort()
	var sorted_want: Array = want.duplicate()
	sorted_want.sort()
	if keys != sorted_want:
		return "keys %s, want %s" % [keys, sorted_want]
	return ""


func test_session_line_shape() -> String:
	var info: Dictionary = {"XRRuntimeName": "Oculus", "XRRuntimeVersion": "1.2.3"}
	var report: Variant = _parse(RenderModelReport.format_session_line(info, true, false))
	if not report is Dictionary:
		return "session line is not prefix + JSON object"
	var keys: String = _keys_are(report, [
		"phase", "runtime", "runtime_version", "extension_enabled_in_settings",
		"extension_supported", "extensions_exposed", "extensions",
	])
	if keys != "":
		return keys
	if report["phase"] != "session" or report["runtime"] != "Oculus" or report["runtime_version"] != "1.2.3":
		return "wrong phase or runtime: %s" % report
	if report["extension_enabled_in_settings"] != true or report["extension_supported"] != false:
		return "wrong extension flags: %s" % report
	if report["extensions_exposed"] != false or report["extensions"] != null:
		return "extensions should be null and not exposed: %s" % report
	return ""


func test_session_line_with_extension_list_and_missing_info() -> String:
	var list: Array = ["XR_EXT_render_model", "XR_FB_render_model"]
	var report: Dictionary = _parse(RenderModelReport.format_session_line({}, false, true, list))
	if report["runtime"] != "" or report["runtime_version"] != "":
		return "missing system info should give empty strings: %s" % report
	if report["extensions_exposed"] != true or report["extensions"] != list:
		return "extension list not passed through: %s" % report
	return ""


func test_models_line_shape() -> String:
	var paths: PackedStringArray = PackedStringArray(["/user/hand/left", "/user/hand/right"])
	var report: Variant = _parse(RenderModelReport.format_models_line(paths, 2, "added", 1))
	if not report is Dictionary:
		return "models line is not prefix + JSON object"
	var keys: String = _keys_are(report, ["phase", "models", "paths", "added_signals", "trigger", "vendor_models"])
	if keys != "":
		return keys
	if report["phase"] != "models" or int(report["models"]) != 2 or int(report["added_signals"]) != 2:
		return "wrong counts: %s" % report
	if report["paths"] != ["/user/hand/left", "/user/hand/right"] or report["trigger"] != "added":
		return "wrong paths or trigger: %s" % report
	if int(report["vendor_models"]) != 1:
		return "vendor model count not passed through: %s" % report
	return ""


func test_models_line_with_none_says_zero() -> String:
	var line: String = RenderModelReport.format_models_line(PackedStringArray(), 0, "timeout")
	if not line.contains("\"models\":0"):
		return "no-model line lacks \"models\":0: %s" % line
	if not line.contains("\"vendor_models\":0"):
		return "line without the plugin lacks \"vendor_models\":0: %s" % line
	return ""


func test_no_xr_interface_prints_nothing() -> String:
	var report: RenderModelReport = RenderModelReport.new()
	var message: String = ""
	if report.attach(null, null):
		message = "attached to a null interface"
	elif report.is_attached():
		message = "claims to be attached"
	elif report.advance(RenderModelReport.WAIT_SECONDS * 2.0):
		message = "printed the models line without a session"
	else:
		report.on_render_model_added(RID())
		if not report.lines.is_empty():
			message = "printed without an XR interface: %s" % report.lines
	report.free()
	return message


func test_uninitialized_interface_prints_nothing() -> String:
	# Headless and flat runs: the OpenXR interface exists but never starts.
	var openxr: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if openxr == null or openxr.is_initialized():
		return ""
	var report: RenderModelReport = RenderModelReport.new()
	var attached: bool = report.attach(openxr, null)
	report.free()
	return "attached to an interface that is not initialized" if attached else ""


func test_models_line_after_wait() -> String:
	var report: RenderModelReport = RenderModelReport.new()
	report.report_session({"XRRuntimeName": "Test"}, true, true)
	var message: String = ""
	if report.lines.size() != 1 or _parse(report.lines[0]) == null:
		message = "session line not printed once: %s" % report.lines
	elif report.advance(RenderModelReport.WAIT_SECONDS - 0.5):
		message = "models line printed before the wait was over"
	elif not report.advance(0.5):
		message = "models line not printed at the end of the wait"
	elif report.advance(1.0):
		message = "models line printed twice"
	else:
		var models: Dictionary = _parse(report.lines[1])
		if int(models["models"]) != 0 or models["trigger"] != "timeout":
			message = "wrong models line with no runtime: %s" % models
	report.free()
	return message


func test_first_added_model_prints_once() -> String:
	var report: RenderModelReport = RenderModelReport.new()
	report.report_session({}, true, true)
	report.on_render_model_added(RID())
	report.on_render_model_added(RID())
	report.report_models("exit")
	var message: String = ""
	if report.lines.size() != 2:
		message = "want two lines, got %s" % report.lines
	else:
		var models: Dictionary = _parse(report.lines[1])
		if models["trigger"] != "added" or int(models["added_signals"]) != 1:
			message = "second line should come from the first added model: %s" % models
	report.free()
	return message


func test_rig_starts_the_report_and_keeps_generic_shapes() -> String:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	if scene == null:
		return "%s did not load" % RIG_SCENE
	var rig: Node = scene.instantiate()
	rig.call("build")
	rig.call("build")
	var message: String = ""
	var count: int = 0
	for child: Node in rig.get_children():
		if child is RenderModelReport:
			count += 1
	if count != 1:
		message = "rig has %d render model reports, want 1" % count
	elif rig.call("render_model_report") == null:
		message = "render_model_report() is null"
	else:
		for hand: String in ["left", "right"]:
			var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
			if model == null or not model.generic_shape_visible():
				message = "%s hand lost its generic shape" % hand
				break
	rig.free()
	return message
