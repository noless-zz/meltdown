class_name DevMenuValues
extends RefCounted

## The development menu's value table (#908): one value helper per value entry
## kind, built from the menu spec. Split from `DevMenuModel` (#1282) so the
## model keeps the highlight, the presses and the action rows, and a new value
## entry adds one field and one table line here (ARC-4, files under about 300
## lines). The helpers only hold the menu's own choice; none reads or writes
## the simulation (MP-2, ARC-3).

var corner: DevMenuValueList
var scheme: DevMenuValueList
var hands: DevMenuValueList
var pitch: DevMenuValueList
var comfort: DevMenuValueComfort
var break_reminder: DevMenuValueToggle
var refresh: DevMenuValueToggle
var swivel: DevMenuValueToggle
var auto_level: DevMenuValueToggle
var foveation: DevMenuValueFoveation
var level: DevMenuValueLevel

var _by_kind: Dictionary[String, DevMenuValue] = {}


## The value helpers for the entries of `spec`, the Level entry showing `levels`.
func _init(spec: DevMenuSpec, levels: DevMenuLevels) -> void:
	corner = DevMenuValueList.new(DevMenuModel.CORNER_PREFIX, spec.corners)
	scheme = DevMenuValueList.new(DevMenuModel.CONTROLS_PREFIX, spec.schemes)
	hands = DevMenuValueList.new(DevMenuModel.HANDS_PREFIX, DevMenuModel.HANDS,
		[spec.right_handed_text, spec.left_handed_text] as Array[String])
	pitch = DevMenuValueList.new(DevMenuModel.PITCH_PREFIX, DevMenuModel.PITCHES,
		[spec.normal_pitch_text, spec.inverted_pitch_text] as Array[String])
	comfort = DevMenuValueComfort.new(DevMenuModel.COMFORT_PREFIX, spec.custom_text)
	break_reminder = DevMenuValueToggle.new(DevMenuModel.BREAK_PREFIX, DevMenuModel.BREAK_ON,
		DevMenuModel.BREAK_OFF, spec.break_on_text, spec.break_off_text, "", true)
	refresh = DevMenuValueToggle.new(DevMenuModel.REFRESH_PREFIX, DevMenuModel.REFRESH_HIGH,
		DevMenuModel.REFRESH_STANDARD, spec.refresh_120_text, spec.refresh_90_text,
		spec.refresh_note_text)
	swivel = DevMenuValueToggle.new(DevMenuModel.SWIVEL_PREFIX, DevMenuModel.SWIVEL_ON,
		DevMenuModel.SWIVEL_OFF, spec.swivel_on_text, spec.swivel_off_text,
		spec.swivel_custom_text)
	auto_level = DevMenuValueToggle.new(DevMenuModel.AUTO_LEVEL_PREFIX,
		DevMenuModel.AUTO_LEVEL_ON, DevMenuModel.AUTO_LEVEL_OFF, spec.auto_level_on_text,
		spec.auto_level_off_text, spec.auto_level_preset_text)
	foveation = DevMenuValueFoveation.new(DevMenuModel.FOVEATION_PREFIX,
		spec.foveation_off_text, spec.foveation_dynamic_text, spec.foveation_note_text)
	level = DevMenuValueLevel.new(DevMenuModel.LEVEL_PREFIX, levels, spec)
	_by_kind = {DevMenuSpec.KIND_CORNER: corner, DevMenuSpec.KIND_CONTROLS: scheme,
		DevMenuSpec.KIND_HANDS: hands, DevMenuSpec.KIND_PITCH: pitch,
		DevMenuSpec.KIND_COMFORT: comfort, DevMenuSpec.KIND_BREAK: break_reminder,
		DevMenuSpec.KIND_REFRESH: refresh, DevMenuSpec.KIND_SWIVEL: swivel,
		DevMenuSpec.KIND_FOVEATION: foveation, DevMenuSpec.KIND_AUTO_LEVEL: auto_level,
		DevMenuSpec.KIND_LEVEL: level}


## The value helper of entry kind `entry_kind`, or null for an action entry.
func value(entry_kind: String) -> DevMenuValue:
	return _by_kind.get(entry_kind, null)


## The words entry kind `entry_kind` shows for its value; "" for an action entry.
func value_text(entry_kind: String) -> String:
	var helper: DevMenuValue = value(entry_kind)
	return helper.value_text() if helper != null else ""
