extends RefCounted

## The dev menu's value helpers (#908, ARC-4): every entry kind with a value
## resolves to a value helper, the action entries to none, and confirming a
## value entry returns what its helper confirms.


static func _model() -> DevMenuModel:
	return DevMenuModel.new(DevMenuSpec.load_file(), ["res://data/levels/g2_level.json"])


static func _check_kinds(model: DevMenuModel, kinds: Array[String]) -> String:
	for kind: String in kinds:
		var helper: DevMenuValue = model.value(kind)
		var is_action: bool = DevMenuModel.ACTION_KINDS.has(kind)
		if is_action and helper != null:
			return "the %s action entry has a value helper" % kind
		if not is_action and helper == null:
			return "the %s entry has no value helper" % kind
		if helper != null and helper.value_text() == "":
			return "the %s value shows no words" % kind
	return ""


func test_shipped_value_entries_resolve_to_a_value_helper() -> String:
	var model: DevMenuModel = _model()
	var kinds: Array[String] = []
	for entry: Dictionary in model.spec.entries:
		kinds.append(str(entry["kind"]))
	return _check_kinds(model, kinds)


func test_every_known_kind_resolves() -> String:
	return _check_kinds(_model(), DevMenuSpec.KINDS)


func test_confirming_a_value_entry_returns_its_helpers_choice() -> String:
	var model: DevMenuModel = _model()
	model.open("centre", "")
	for index: int in model.spec.entries.size():
		model.selected = index
		var helper: DevMenuValue = model.value(model.kind())
		if helper == null:
			continue
		model.press({DevMenuModel.RIGHT: true})
		model.press({})
		var expected: String = helper.confirmed()
		var got: String = model.press({DevMenuModel.CONFIRM: true})
		model.press({})
		if got != expected or expected == "":
			return "%s confirmed \"%s\", its helper \"%s\"" % [model.kind(), got, expected]
	return ""


func test_a_locked_toggle_does_not_step_and_shows_its_note() -> String:
	var toggle: DevMenuValueToggle = DevMenuValueToggle.new("t:", "on", "off", "On", "Off", "(note)")
	toggle.locked = true
	toggle.step(1)
	if toggle.on or toggle.value_text() != "Off (note)" or toggle.confirmed() != "t:off":
		return "a locked toggle gave %s, \"%s\", %s" % [toggle.on, toggle.value_text(), toggle.confirmed()]
	toggle.locked = false
	toggle.step(-1)
	return "" if toggle.on and toggle.value_text() == "On" and toggle.confirmed() == "t:on" \
		else "an unlocked toggle gave %s, \"%s\"" % [toggle.on, toggle.value_text()]
