class_name RenderModelReport
extends Node

## Logs whether the OpenXR runtime offers controller render models (#145,
## PLT-2, PLT-5).
##
## On a Quest 3 the generic controller shape still shows, so either the
## runtime never offers a model or the model never replaces the shape. This
## node only finds out which: once the session has begun it prints one line
## about the runtime and the render-model extension, and a second line with
## the models the runtime added, ten seconds later or as soon as the first
## one arrives. Both lines are `MELTDOWN_RENDER_MODELS ` and then JSON, so
## `adb logcat -s godot` and the CI smoke log can be searched for them.
## Logging only: it changes nothing on screen and touches no simulation
## state (ARC-3). Without an OpenXR interface it prints nothing.

const LINE_PREFIX: String = "MELTDOWN_RENDER_MODELS "
const SETTING: String = "xr/openxr/extensions/render_model"
const EXTENSION_SINGLETON: String = "OpenXRRenderModelExtension"
## Long enough for a runtime to load its models after the session starts.
const WAIT_SECONDS: float = 10.0

## Every line printed so far, in order; the tests read it.
var lines: PackedStringArray = PackedStringArray()

var _openxr: OpenXRInterface = null
var _extension: Object = null
var _session_begun: bool = false
var _models_reported: bool = false
var _added_signals: int = 0
var _waited: float = 0.0


## The first line: who the runtime is and what it says about render models.
## Godot 4.7.2 does not expose the runtime's extension list to scripts, so
## `extensions` is null there and `extensions_exposed` says so.
static func format_session_line(
	system_info: Dictionary, enabled_in_settings: bool, supported: bool, extensions: Variant = null
) -> String:
	var report: Dictionary = {
		"phase": "session",
		"runtime": str(system_info.get("XRRuntimeName", "")),
		"runtime_version": str(system_info.get("XRRuntimeVersion", "")),
		"extension_enabled_in_settings": enabled_in_settings,
		"extension_supported": supported,
		"extensions_exposed": extensions != null,
		"extensions": extensions,
	}
	return LINE_PREFIX + JSON.stringify(report)


## The second line: how many models the runtime has, under which top-level
## paths (empty where the runtime has not bound one yet), how many
## `render_model_added` signals arrived, and what printed the line:
## `"added"`, `"timeout"` or `"exit"`.
static func format_models_line(paths: PackedStringArray, added_signals: int, trigger: String) -> String:
	var report: Dictionary = {
		"phase": "models",
		"models": paths.size(),
		"paths": Array(paths),
		"added_signals": added_signals,
		"trigger": trigger,
	}
	return LINE_PREFIX + JSON.stringify(report)


func _ready() -> void:
	var extension: Object = null
	if Engine.has_singleton(EXTENSION_SINGLETON):
		extension = Engine.get_singleton(EXTENSION_SINGLETON)
	attach(XRServer.find_interface("OpenXR") as OpenXRInterface, extension)


func _process(delta: float) -> void:
	advance(delta)


func _exit_tree() -> void:
	# The CI smoke run quits after a fixed number of frames, often before the
	# wait is over; the line still has to reach its log.
	if _session_begun and not _models_reported:
		report_models("exit")


## Starts listening when `openxr` is an initialized interface; returns false,
## and stays silent for good, otherwise. Public so the tests can pass null.
func attach(openxr: OpenXRInterface, extension: Object) -> bool:
	if openxr == null or not openxr.is_initialized():
		return false
	_openxr = openxr
	_extension = extension
	if not openxr.session_begun.is_connected(on_session_begun):
		openxr.session_begun.connect(on_session_begun)
	if extension != null and extension.has_signal("render_model_added"):
		extension.connect("render_model_added", on_render_model_added)
	return true


## True once `attach` accepted an interface.
func is_attached() -> bool:
	return _openxr != null


func on_session_begun() -> void:
	if _session_begun:
		return
	var info: Dictionary = _openxr.get_system_info() if _openxr != null else {}
	report_session(info, bool(ProjectSettings.get_setting(SETTING, false)), _extension_active())


## Prints the first line and starts the wait for the second.
func report_session(system_info: Dictionary, enabled_in_settings: bool, supported: bool) -> void:
	_session_begun = true
	_waited = 0.0
	_emit(format_session_line(system_info, enabled_in_settings, supported))


func on_render_model_added(_render_model: RID) -> void:
	_added_signals += 1
	if _session_begun and not _models_reported:
		report_models("added")


## Counts frame time after the session began; prints the second line once
## the wait is over. Returns true on the call that printed it.
func advance(delta: float) -> bool:
	if not _session_begun or _models_reported:
		return false
	_waited += delta
	if _waited < WAIT_SECONDS:
		return false
	report_models("timeout")
	return true


## Prints the second line once; later calls do nothing.
func report_models(trigger: String) -> void:
	if _models_reported:
		return
	_models_reported = true
	_emit(format_models_line(_model_paths(), _added_signals, trigger))


func _extension_active() -> bool:
	return _extension != null and _extension.has_method("is_active") and bool(_extension.call("is_active"))


func _model_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	if not _extension_active():
		return paths
	var models: Array = _extension.call("render_model_get_all")
	for model: Variant in models:
		paths.append(str(_extension.call("render_model_get_top_level_path", model)))
	return paths


func _emit(line: String) -> void:
	lines.append(line)
	print(line)
